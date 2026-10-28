import 'dart:convert';

import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  // تكرارات اشتقاق الجيل القديم v1 منخفضة لسرعة الاختبار — الرياضيات
  // واحدة والافتراضي الإنتاجي 100000. جيل v2 (مفتاح البرنامج) اشتقاقه
  // HKDF سريع لا يتأثر بالتكرارات.
  final cipher = BackupCipher(iterations: 500);

  test('D-060: تدوير كامل بمفتاح البرنامج — تشفير ثم فك بلا أي كلمة مرور',
      () async {
    final plain = utf8.encode('محتوى قاعدة تجريبية ' * 200);
    final blob = await cipher.encrypt(plain);
    expect(BackupCipher.identify(blob), BackupKind.encrypted);
    final back = await cipher.decrypt(blob);
    expect(back, equals(plain));
  });

  test('D-060: بايتة الإصدار 2 — والغلاف بلا ترويسة SQLite فلا يُفتح بأداة خارجية',
      () async {
    final blob = await cipher.encrypt(utf8.encode('محتوى'));
    // الترويسة 7 بايتات (DIQQENC) وبعدها بايتة الإصدار
    expect(utf8.decode(blob.sublist(0, 7)), 'DIQQENC');
    expect(blob[7], BackupCipher.formatVersion);
    expect(BackupCipher.encryptedVersion(blob), BackupCipher.formatVersion);
    expect(BackupCipher.identify(blob), isNot(BackupKind.plainSqlite));
  });

  test('عبث بايت داخل النص المشفر يُكتشف بوسم GCM — سلامة الملف (F-013)',
      () async {
    final blob = await cipher.encrypt(utf8.encode('قاعدة حقيقية' * 50));
    blob[blob.length - 30] ^= 0xFF;
    expect(
      () => cipher.decrypt(blob),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('عبث بايت في الملح يُكتشف أيضاً — الملح يدخل اشتقاق مفتاح الملف',
      () async {
    final blob = await cipher.encrypt(utf8.encode('بيانات'));
    blob[8] ^= 0xFF; // الملح يلي بايتة الإصدار مباشرة (7 + 1)
    expect(
      () => cipher.decrypt(blob),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('نسختان لنفس المدخل تختلفان — ملح ونونس عشوائيان في كل مرة (شرط D-060)',
      () async {
    final a = await cipher.encrypt(utf8.encode('نفس البيانات'));
    final b = await cipher.encrypt(utf8.encode('نفس البيانات'));
    expect(a, isNot(equals(b)));
    expect(await cipher.decrypt(a), await cipher.decrypt(b));
  });

  test('الجيل القديم v1 يبقى مقروءاً بكلمته — التزام القراءة الدائم (D-060)',
      () async {
    final plain = utf8.encode('نسخة بكلمة مرور من أيام D-050');
    final blob = await cipher.encryptWithPassword(plain, 'كلمة-القديمة');
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.legacyFormatVersion);
    final back = await cipher.decryptWithPassword(blob, 'كلمة-القديمة');
    expect(back, equals(plain));
    // الكلمة الخاطئة ترفض صراحة — لا صمت ولا بيانات مشوهة
    expect(
      () => cipher.decryptWithPassword(blob, 'الخاطئة'),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('المساران يرفضان الجيل المعاكس بتوجيه صريح — لا فشل صامت', () async {
    final v2 = await cipher.encrypt(utf8.encode('جيل جديد'));
    expect(
      () => cipher.decryptWithPassword(v2, 'أي-كلمة'),
      throwsA(isA<BackupCipherException>()),
    );
    final v1 =
        await cipher.encryptWithPassword(utf8.encode('جيل قديم'), 'كلمة');
    expect(
      () => cipher.decrypt(v1),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('توافق الجيل الأسبق: ترويسة «HESEBENC» تُميّز وتُفك بكلمتها (D-053)',
      () async {
    final plain = utf8.encode('نسخة من جيل حسيب');
    final blob = await cipher.encryptWithPassword(plain, 'كلمة-السر');
    // بنية الجيل السابق حرفاً (كود ما قبل إعادة التسمية): ترويسة بثمانية
    // بايتات ثم بايتة الإصدار ثم الملح — فما بعد الترويسة الجديدة (7)
    // يحفظ بايتة الإصدار والملح والبقية كما هي.
    final legacyHeader = utf8.encode('HESEBENC');
    final legacy = <int>[
      ...legacyHeader,
      ...blob.sublist(BackupCipher.magic.length),
    ];
    expect(BackupCipher.identify(legacy), BackupKind.encrypted);
    expect(BackupCipher.encryptedVersion(legacy),
        BackupCipher.legacyFormatVersion);
    final back = await cipher.decryptWithPassword(legacy, 'كلمة-السر');
    expect(back, equals(plain));
  });

  test('identify يميز الأنواع الثلاثة بلا أي فك', () {
    expect(
      BackupCipher.identify(utf8.encode('SQLite format 3\x00وبقية الملف')),
      BackupKind.plainSqlite,
    );
    expect(BackupCipher.identify(utf8.encode('ملف عشوائي ليس نسخة')),
        BackupKind.unknown);
    expect(BackupCipher.identify(const <int>[]), BackupKind.unknown);
    expect(BackupCipher.encryptedVersion(utf8.encode('SQLite format 3\x00')),
        0);
  });
}
