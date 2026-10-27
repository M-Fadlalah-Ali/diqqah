import 'dart:convert';

import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  // تكرارات منخفضة لسرعة الاختبار — الرياضيات واحدة والافتراضي الإنتاجي 100000.
  // (المُنشئ غير ثابت — AesGcm يُبنى زمنياً)
  final cipher = BackupCipher(iterations: 500);

  test('تدوير كامل: تشفير ثم فك يعيد بايتات القاعدة الأصلية حرفاً', () async {
    final plain = utf8.encode('محتوى قاعدة تجريبية ' * 200);
    final blob = await cipher.encrypt(plain, 'كلمة-السر');
    expect(BackupCipher.identify(blob), BackupKind.encrypted);
    final back = await cipher.decrypt(blob, 'كلمة-السر');
    expect(back, equals(plain));
  });

  test('كلمة مرور خاطئة ترفض صراحة — لا صمت ولا بيانات مشوهة', () async {
    final blob = await cipher.encrypt(utf8.encode('بيانات'), 'الصحيحة');
    expect(
      () => cipher.decrypt(blob, 'الخاطئة'),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('عبث بايت واحد داخل النص المشفر يُكتشف بوسم GCM — سلامة الملف (F-013)',
      () async {
    final blob = await cipher.encrypt(utf8.encode('قاعدة حقيقية' * 50), 'الصحيحة');
    blob[blob.length - 30] ^= 0xFF;
    expect(
      () => cipher.decrypt(blob, 'الصحيحة'),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('عبث بايت في الترويسة (الملح) يُكتشف أيضاً', () async {
    final blob = await cipher.encrypt(utf8.encode('بيانات'), 'الصحيحة');
    blob[10] ^= 0xFF; // داخل الملح
    expect(
      () => cipher.decrypt(blob, 'الصحيحة'),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('identify يميز الأنواع الثلاثة بلا أي فك', () {
    expect(
      BackupCipher.identify(utf8.encode('SQLite format 3\x00وبقية الملف')),
      BackupKind.plainSqlite,
    );
    expect(BackupCipher.identify(utf8.encode('ملف عشوائي ليس نسخة')),
        BackupKind.unknown);
    expect(BackupCipher.identify(const <int>[]), BackupKind.unknown);
  });

  test('الغلاف المشفر لا يحمل أي ترويسة SQLite — لا يُفتح بأداة خارجية', () async {
    final blob = await cipher.encrypt(utf8.encode('محتوى'), 'p');
    expect(utf8.decode(blob.sublist(0, 8)), 'DIQQENC');
    expect(
      BackupCipher.identify(blob),
      isNot(BackupKind.plainSqlite),
    );
  });

  test('توافق الجيل السابق: نسخة بترويسة «HESEBENC» تُميّز وتُفك كما هي (D-053)',
      () async {
    final plain = utf8.encode('نسخة من جيل حسيب');
    final blob = await cipher.encrypt(plain, 'كلمة-السر');
    // إحلال الترويسة القديمة مكان الجديدة — بقية البايتات كما هي
    final legacyHeader = utf8.encode('HESEBENC');
    final legacy = <int>[...legacyHeader, ...blob.sublist(legacyHeader.length)];
    expect(BackupCipher.identify(legacy), BackupKind.encrypted);
    final back = await cipher.decrypt(legacy, 'كلمة-السر');
    expect(back, equals(plain));
  });

  test('نسختان لنفس المدخل تختلفان — ملح ونونس عشوائيان في كل مرة', () async {
    final a = await cipher.encrypt(utf8.encode('نفس البيانات'), 'نفس الكلمة');
    final b = await cipher.encrypt(utf8.encode('نفس البيانات'), 'نفس الكلمة');
    expect(a, isNot(equals(b)));
    expect(await cipher.decrypt(a, 'نفس الكلمة'),
        await cipher.decrypt(b, 'نفس الكلمة'));
  });
}
