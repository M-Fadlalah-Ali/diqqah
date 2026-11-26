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

  // ═══ الجيل المقفل v3 — P1-أ (س149/D-210) ═══

  test('v3: تغليف بكلمة المستخدم ورمز الاسترداد — فك بالكلمة أو بالرمز',
      () async {
    final plain = utf8.encode('نسخة مقفلة تجريبية ' * 100);
    final blob = await cipher.encryptLocked(
      plain,
      password: 'كلمة-المالك-القوية',
      recoveryCode: BackupCipher.generateRecoveryCode(),
    );
    expect(BackupCipher.identify(blob), BackupKind.encrypted);
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.lockedFormatVersion);
    expect(BackupCipher.needsUnlock(blob), isTrue);
    expect(await cipher.decryptLocked(blob, password: 'كلمة-المالك-القوية'),
        equals(plain));
  });

  test('v3: رمز الاسترداد يفك حصراً — وأي هيئة كتابة تصل للمفتاح ذاته',
      () async {
    final plain = utf8.encode('البيانات بالرمز');
    const code = 'ABCD-EFGH-JK2M-NP4Q';
    final blob = await cipher.encryptLocked(
        plain, password: 'كلمة', recoveryCode: code);
    // الكلمة الخاطئة وحدها ترفض…
    expect(
      () => cipher.decryptLocked(blob, password: 'خاطئة'),
      throwsA(isA<BackupCipherException>()),
    );
    // …والرمز الصحيح يفك — بالأحرف الكبيرة وبالصغيرة وبلا شرطات.
    expect(await cipher.decryptLocked(blob, recoveryCode: code),
        equals(plain));
    expect(await cipher.decryptLocked(blob, recoveryCode: 'abcd-efgh-jk2m-np4q'),
        equals(plain));
    expect(await cipher.decryptLocked(blob, recoveryCode: 'A B C D E F G H J K 2 M N P 4 Q'),
        equals(plain));
  });

  test('v3: الكلمة الخاطئة والرمز الصحيح — تجربة السجلات تنجو بالرمز',
      () async {
    final plain = utf8.encode('فشل سجل لا يمنع التالي');
    const code = 'WWWW-XXXX-YYYY-ZZZZ';
    final blob = await cipher.encryptLocked(
        plain, password: 'الكلمة-الصحيحة', recoveryCode: code);
    expect(
        await cipher.decryptLocked(
            blob, password: 'كلمة-خاطئة', recoveryCode: code.toLowerCase()),
        equals(plain));
  });

  test('v3: بلا مواد أو كل المواد خاطئة — رفض صريح برسالة الطلب والخطأ',
      () async {
    final blob = await cipher.encryptLocked(
        utf8.encode('مقفلة'), password: 'الكلمة', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    expect(
      () => cipher.decryptLocked(blob),
      throwsA(isA<BackupCipherException>().having(
          (e) => e.toString(), 'msg', contains('مقفلة'))),
    );
    expect(
      () => cipher.decryptLocked(blob,
          password: 'خاطئة', recoveryCode: 'ZZZZ-ZZZZ-ZZZZ-ZZZZ'),
      throwsA(isA<BackupCipherException>().having(
          (e) => e.toString(), 'msg', contains('خاطئ'))),
    );
  });

  test('v3: بنية الغلاف — ترويسة الجيل 3 وسجلان 77 بايتة لكل منهما',
      () async {
    final plain = utf8.encode('ب');
    final blob = await cipher.encryptLocked(
        plain, password: 'كلمة-كاملة-الثمانية', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    expect(utf8.decode(blob.sublist(0, 7)), 'DIQQENC');
    expect(blob[7], BackupCipher.lockedFormatVersion);
    expect(blob[8], 2); // سجلان حصراً: الكلمة والرمز
    // 9 (ترويسة+إصدار+عدّاد) + 154 (سجلان) + 12 (نونس) + 1 (نص) + 16 (وسم)
    expect(blob.length, 9 + 2 * 77 + 12 + plain.length + 16);
  });

  test('v3: لا سجل مفتاح البرنامج — مسار v2 يرفضه والعبث يُكتشف', () async {
    final blob = await cipher.encryptLocked(
        utf8.encode('مقفلة'), password: 'الكلمة-الصحيحة', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    // مسار v2 يرفض الجيل المقفل بتوجيه صريح — لا فك صامت بمفتاح البرنامج.
    expect(
      () => cipher.decrypt(blob),
      throwsA(isA<BackupCipherException>()),
    );
    // عبث بايت داخل DEK المشفر في سجل الكلمة يكسر الفك بالكلمة —
    // ويجبر مسار الرمز وحده.
    final tampered = List<int>.of(blob);
    tampered[10] ^= 0xFF; // أول بايتات ملح سجل الكلمة (بعد النوع)
    expect(
      () => cipher.decryptLocked(tampered, password: 'الكلمة-الصحيحة'),
      throwsA(isA<BackupCipherException>()),
    );
    expect(await cipher.decryptLocked(tampered, recoveryCode: 'ABCD-EFGH-JK2M-NP4Q'),
        equals(utf8.encode('مقفلة')));
  });

  test('v3: نسختان لنفس المدخل تختلفان — DEK وملح ونونس عشوائيان', () async {
    final a = await cipher.encryptLocked(
        utf8.encode('نفسها'), password: 'كلمة-واحدة', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    final b = await cipher.encryptLocked(
        utf8.encode('نفسها'), password: 'كلمة-واحدة', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    expect(a, isNot(equals(b)));
    expect(await cipher.decryptLocked(a, password: 'كلمة-واحدة'),
        await cipher.decryptLocked(b, password: 'كلمة-واحدة'));
  });

  test('needsUnlock يفرق الأجيال الثلاثة بلا أي فك', () async {
    final v2 = await cipher.encrypt(utf8.encode('جيل مفتوح'));
    expect(BackupCipher.needsUnlock(v2), isFalse);
    final v1 = await cipher.encryptWithPassword(
        utf8.encode('جيل قديم'), 'كلمة');
    expect(BackupCipher.needsUnlock(v1), isFalse);
    final v3 = await cipher.encryptLocked(
        utf8.encode('جيل مقفل'), password: 'كلمة-طويلة', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    expect(BackupCipher.needsUnlock(v3), isTrue);
  });

  test('generateRecoveryCode: الصيغة 4×4 بشرطات وألفباء بلا متشابهات',
      () {
    final code = BackupCipher.generateRecoveryCode();
    expect(code.length, 19); // 16 محرفاً + 3 شرطات
    final groups = code.split('-');
    expect(groups.length, 4);
    for (final g in groups) {
      expect(g.length, 4);
      expect(g, matches(RegExp(r'^[A-HJ-NP-Z2-9]+$')));
    }
    // عشوائية حية: نداءان متتاليان يختلفان (احتمال التطابق متناهي الصغر).
    expect(BackupCipher.generateRecoveryCode(),
        isNot(equals(BackupCipher.generateRecoveryCode())));
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
