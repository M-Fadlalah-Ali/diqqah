// اختبارات د11 (س229/D-225 الجزء الأول) — جيل الخزنة v4 بمفاتيح
// النسخ: الجذر العشوائي لكل جهاز يغلّف DEK بسجلين (مفتاح الخزنة هنا
// صامتاً، ورمز الاسترداد على أي جهاز آخر) — فسيناريو «فتح النسخة على
// أي جهاز» (N-005) يلتئم بالرمز بلا كسر، ومفتاح البرنامج المضمّن
// يبقى قارئاً حصراً لنسخ v2 القديمة (التزام دائم).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  // تكرارات منخفضة لسرعة الاختبار (نمط backup_cipher_test) — جيل v4
  // لا يستعمل PBKDF2 إلا لسجل الرمز، ورياضياته واحدة بالافتراضي
  // الإنتاجي 100000.
  final cipher = BackupCipher(iterations: 500);

  // جذر خزنة الجهاز الأول — 32 بايتة عشوائية (نمط التوليد بالإنتاج).
  final rootA = List<int>.generate(32, (i) => (i * 7 + 13) % 256);
  // جذر جهاز آخر — يختلف عن الأول فالفتح الصامت لا يعبر الأجهزة.
  final rootB = List<int>.generate(32, (i) => (i * 11 + 5) % 256);
  const code = 'ABCD-2345-FGHI-6789';

  test('د11: تدوير كامل — الكتابة v4 بالجذر والرمز والفك بمفتاح الخزنة '
      'الصامت (الجهاز ذاته)', () async {
    final plain = utf8.encode('محتوى قاعدة تجريبية ' * 100);
    final blob = await cipher.encryptVaulted(
      plain,
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(BackupCipher.identify(blob), BackupKind.encrypted);
    expect(BackupCipher.encryptedVersion(blob), BackupCipher.vaultFormatVersion);
    expect(BackupCipher.isVaulted(blob), isTrue);
    expect(BackupCipher.needsUnlock(blob), isFalse,
        reason: 'v4 ليس مقفلاً بكلمة مستخدم — موادّه خزنة ورمز');
    final back = await cipher.decryptVaulted(blob, vaultRootKey: rootA);
    expect(back, equals(plain));
  });

  test('د11: الجهاز الآخر يفتح بالرمز وحده — N-005 يلتئم بلا كسر '
      '(بأي هيئة كتابة: صغير الشرطات ومسافات)', () async {
    final plain = utf8.encode('قاعدة انتقلت لجهاز جديد');
    final blob = await cipher.encryptVaulted(
      plain,
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    for (final typed in [code, code.toLowerCase(), 'abcd 2345 fg hi 6789']) {
      final back =
          await cipher.decryptVaulted(blob, recoveryCode: typed);
      expect(back, equals(plain), reason: 'هيئة الكتابة: $typed');
    }
  });

  test('د11: جذر جهاز آخر لا يفتح — السجل الصامت لا يعبر الأجهزة',
      () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('سر هذا الجهاز'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(
      () => cipher.decryptVaulted(blob, vaultRootKey: rootB),
      throwsA(isA<BackupCipherException>()),
    );
    // والجذر الخاطئ مع الرمز الصحيح يفتح بالرمز — المادة الصحيحة تكفي.
    final back = await cipher.decryptVaulted(
      blob,
      vaultRootKey: rootB,
      recoveryCode: code,
    );
    expect(back, equals(utf8.encode('سر هذا الجهاز')));
  });

  test('د11: لا مواد = رسالة الطلب بلسان الجيل — لا استثناء أعمى',
      () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('نسخة خام'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(
      () => cipher.decryptVaulted(blob),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('رمز الاسترداد'))),
    );
  });

  test('د11: كل المواد خاطئة = رفض صريح قبل أي بايت للقاعدة (روح F-013) '
      '— والمادة الصحيحة الواحدة تكفي فتحاً',
      () async {
    final plain = utf8.encode('نسخة');
    final blob = await cipher.encryptVaulted(
      plain,
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    // جذر جهاز آخر + رمز خاطئ = كل المواد خاطئة فرفض صريح.
    expect(
      () => cipher.decryptVaulted(
        blob,
        vaultRootKey: rootB,
        recoveryCode: 'WRONG-CODE-0000',
      ),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('خاطئ'))),
    );
    // ومفتاح الخزنة الصحيح مع رمز خاطئ يفتح صامتاً — سجل الجذر كاف.
    expect(
        await cipher.decryptVaulted(
          blob,
          vaultRootKey: rootA,
          recoveryCode: 'WRONG-CODE-0000',
        ),
        equals(plain));
  });

  test('د11: بنية الجيل — بايتة الإصدار 4 وعدّاد السجلين 2 وسجلان '
      'ب77 بايتة (النوع 3 ثم 2) — توثيق البايتات للفحص البنائي', () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('بنية'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(utf8.decode(blob.sublist(0, 7)), 'DIQQENC');
    expect(blob[7], BackupCipher.vaultFormatVersion);
    expect(blob[8], 2, reason: 'سجلان حصراً');
    expect(blob[9], 3, reason: 'الأول مفتاح الخزنة');
    final second = 9 + 1 + 16 + 12 + 16 + 32;
    expect(blob[second], 2, reason: 'الثاني رمز الاسترداد');
    // الطول: الترويسة 7 + الإصدار 1 + العداد 1 + سجلان 77 + نونس 12
    // + وسم 16 + نص البيانات.
    expect(
      blob.length - (7 + 1 + 1 + 2 * 77 + 12 + 16),
      utf8.encode('بنية').length,
    );
  });

  test('د11: عبث بايت بسجل مفتاح الخزنة يُكتشف — وسم GCM في كل سجل',
      () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('سلامة السجل'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    blob[15] ^= 0xFF; // داخل ملح السجل الأول
    expect(
      () => cipher.decryptVaulted(blob, vaultRootKey: rootA),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('د11: نوع سجل شاذ يُرفض كاملاً — لا تخمين صامت (بنية الخزنة)',
      () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('رفض النوع الشاذ'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    blob[9] = 1; // نوع كلمة المستخدم — مقبول بv3 وشاذ بv4
    expect(
      () => cipher.decryptVaulted(blob, vaultRootKey: rootA),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('نوع سجل'))),
    );
  });

  test('د11: المسارات الثلاثة ترفض الجيل المعاكس بتوجيه صريح — لا فشل صامت',
      () async {
    final v2 = await cipher.encrypt(utf8.encode('مفتاح البرنامج'));
    final v3 = await cipher.encryptLocked(
      utf8.encode('مقفلة بكلمة'),
      password: 'كلمة-القفل-8محارف',
      recoveryCode: code,
    );
    final v4 = await cipher.encryptVaulted(
      utf8.encode('مفاتيح الخزنة'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(
      () => cipher.decryptVaulted(v2, vaultRootKey: rootA),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('مفتاح البرنامج'))),
    );
    expect(
      () => cipher.decryptVaulted(v3, vaultRootKey: rootA),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('مقفلة'))),
    );
    expect(
      () => cipher.decryptLocked(v4, password: 'كلمة', recoveryCode: code),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('الخزنة'))),
    );
    // وv2 القديمة تُقرأ بمفتاح البرنامج كما كانت حرفاً (قارئ الإرث).
    expect(await cipher.decrypt(v2), equals(utf8.encode('مفتاح البرنامج')));
  });

  test('د11: نسختا v4 لمحتوى واحد تختلفان — DEK وملح ونونس لكل ملف',
      () async {
    final a = await cipher.encryptVaulted(
      utf8.encode('نفس البيانات'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    final b = await cipher.encryptVaulted(
      utf8.encode('نفس البيانات'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(a, isNot(equals(b)));
    expect(await cipher.decryptVaulted(a, vaultRootKey: rootA),
        await cipher.decryptVaulted(b, vaultRootKey: rootA));
  });

  test('د11: مواد الخزنة صنف المجال النقي — جذر 32 بايتة ورمز بنمط v3',
      () {
    const keys = BackupVaultKeys(rootKey: [1, 2, 3], recoveryCode: code);
    expect(keys.rootKey, hasLength(3));
    expect(keys.recoveryCode, code);
    // والمولّد الرسمي للرمز يطابق نمط v3 حرفاً (4 مجموعات مفصولة).
    final generated = BackupCipher.generateRecoveryCode();
    expect(
        RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$').hasMatch(generated),
        isTrue,
        reason: 'بلا متشابهات (0/O و1/I/L) وبأربع مجموعات');
  });

  // ── س230 (د11 الجزء الثاني — سفر جذر السجلات بالنسخة) ──────────────

  // جذر سجلات الجهاز الأول — جذر مستقل عن جذر النسخ (فصل النطاقات من
  // الجذر لا من الاشتقاق — عقد LogCipher القائم).
  final logRootA = List<int>.generate(32, (i) => (i * 13 + 29) % 256);

  test('س230: v5 بالجذر — الإصدار 5 والكشف حاضر والجذر يسافر تحت DEK '
      '(بمفتاح الخزنة هنا وبالرمز على جهاز آخر)', () async {
    final plain = utf8.encode('قاعدة بسجلات مسافرة');
    final blob = await cipher.encryptVaulted(
      plain,
      vaultRootKey: rootA,
      recoveryCode: code,
      logRootKey: logRootA,
    );
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.vaultLogFormatVersion);
    expect(BackupCipher.isVaulted(blob), isTrue);
    expect(BackupCipher.needsUnlock(blob), isFalse);
    // الفتح الصامت هنا — والجذر المحمول يعاد كما هو.
    final (back, carriedRoot) =
        await cipher.decryptVaultedWithLogRoot(blob, vaultRootKey: rootA);
    expect(back, equals(plain));
    expect(carriedRoot, equals(logRootA));
    // والرمز على جهاز آخر — والجذر يسافر به أيضاً.
    final (byCode, carriedByCode) =
        await cipher.decryptVaultedWithLogRoot(blob, recoveryCode: code);
    expect(byCode, equals(plain));
    expect(carriedByCode, equals(logRootA));
  });

  test('س230: بلا جذر — v4 حرفاً (انخفاض موثق) والجذر المحمول null',
      () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('بلا جذر'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(BackupCipher.encryptedVersion(blob), BackupCipher.vaultFormatVersion);
    final (back, carriedRoot) =
        await cipher.decryptVaultedWithLogRoot(blob, vaultRootKey: rootA);
    expect(back, equals(utf8.encode('بلا جذر')));
    expect(carriedRoot, isNull);
    // والمفوّض القديم يعمل حرفاً — توافق المستدعين القائمين.
    expect(await cipher.decryptVaulted(blob, vaultRootKey: rootA),
        equals(utf8.encode('بلا جذر')));
  });

  test('س230: v6 المقفلة بالجذر — الإصدار 6 والجذر يسافر بالكلمة والرمز',
      () async {
    final plain = utf8.encode('مقفلة بسجلاتها');
    final blob = await cipher.encryptLocked(
      plain,
      password: 'كلمة-القفل-8محارف',
      recoveryCode: code,
      logRootKey: logRootA,
    );
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.lockedLogFormatVersion);
    expect(BackupCipher.needsUnlock(blob), isTrue);
    expect(BackupCipher.isVaulted(blob), isFalse);
    final (byPassword, byPasswordRoot) = await cipher.decryptLockedWithLogRoot(
      blob,
      password: 'كلمة-القفل-8محارف',
    );
    expect(byPassword, equals(plain));
    expect(byPasswordRoot, equals(logRootA));
    final (byCode, byCodeRoot) = await cipher.decryptLockedWithLogRoot(
      blob,
      recoveryCode: code,
    );
    expect(byCode, equals(plain));
    expect(byCodeRoot, equals(logRootA));
  });

  test('س230: المقفلة بلا جذر تعود v3 حرفاً — والقديمة v3 تُقرأ بالمفوّض',
      () async {
    final blob = await cipher.encryptLocked(
      utf8.encode('مقفلة إرثية'),
      password: 'كلمة-القفل-8محارف',
      recoveryCode: code,
    );
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.lockedFormatVersion);
    final (back, carriedRoot) = await cipher.decryptLockedWithLogRoot(
      blob,
      password: 'كلمة-القفل-8محارف',
    );
    expect(back, equals(utf8.encode('مقفلة إرثية')));
    expect(carriedRoot, isNull);
    expect(await cipher.decryptLocked(blob, password: 'كلمة-القفل-8محارف'),
        equals(utf8.encode('مقفلة إرثية')));
  });

  test('س230: بنية v5 — سجل السجلات نوع 4 ب61 بايتة بين السجلين والبيانات '
      '— توثيق البايتات للفحص البنائي', () async {
    final plain = utf8.encode('بنية الخامس');
    final blob = await cipher.encryptVaulted(
      plain,
      vaultRootKey: rootA,
      recoveryCode: code,
      logRootKey: logRootA,
    );
    expect(utf8.decode(blob.sublist(0, 7)), 'DIQQENC');
    expect(blob[7], BackupCipher.vaultLogFormatVersion);
    expect(blob[8], 2, reason: 'سجلا التغليف حصراً');
    // سجل السجلات بعد السجلين مباشرة: النوع 4 ثم نونس 12 ووسم 16 وجذر
    // مشفر 32 = 61 بايتة، ثم قسم البيانات.
    final logAt = 7 + 1 + 1 + 2 * 77;
    expect(blob[logAt], 4, reason: 'سجل مفتاح السجلات');
    // الطول: الترويسة 7 + الإصدار 1 + العداد 1 + سجلان 77 + سجل السجلات
    // 61 + نونس 12 + وسم 16 + نص البيانات.
    expect(
      blob.length - (7 + 1 + 1 + 2 * 77 + 61 + 12 + 16),
      plain.length,
    );
  });

  test('س230: عبث سجل السجلات يُرفض — وسم GCM حاكم تحت DEK', () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('عبث السجل الرابع'),
      vaultRootKey: rootA,
      recoveryCode: code,
      logRootKey: logRootA,
    );
    final logAt = 7 + 1 + 1 + 2 * 77 + 1 + 12 + 16 + 5; // داخل الجذر المشفر
    blob[logAt] ^= 0xFF;
    expect(
      () => cipher.decryptVaultedWithLogRoot(blob, vaultRootKey: rootA),
      throwsA(isA<BackupCipherException>().having(
          (e) => e.message, 'message', contains('سجل السجلات'))),
    );
  });

  test('س230: القارئ الموحد decryptAny — الأجيال الستة كلها بموادها '
      'والجذر يسافر بالأجيال الحاملة فقط', () async {
    final v1 = await cipher
        .encryptWithPassword(utf8.encode('جيل أول'), 'كلمة-v1-قديمة');
    final v2 = await cipher.encrypt(utf8.encode('جيل ثانٍ'));
    final v3 = await cipher.encryptLocked(
      utf8.encode('جيل ثالث'),
      password: 'كلمة-القفل-8محارف',
      recoveryCode: code,
    );
    final v4 = await cipher.encryptVaulted(
      utf8.encode('جيل رابع'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    final v5 = await cipher.encryptVaulted(
      utf8.encode('جيل خامس'),
      vaultRootKey: rootA,
      recoveryCode: code,
      logRootKey: logRootA,
    );
    final v6 = await cipher.encryptLocked(
      utf8.encode('جيل سادس'),
      password: 'كلمة-القفل-8محارف',
      recoveryCode: code,
      logRootKey: logRootA,
    );
    expect((await cipher.decryptAny(v1, password: 'كلمة-v1-قديمة')).$1,
        equals(utf8.encode('جيل أول')));
    expect((await cipher.decryptAny(v2)).$1, equals(utf8.encode('جيل ثانٍ')));
    expect(
        (await cipher.decryptAny(v3,
                password: 'كلمة-القفل-8محارف', recoveryCode: code))
            .$1,
        equals(utf8.encode('جيل ثالث')));
    final (plain4, root4) =
        await cipher.decryptAny(v4, vaultRootKey: rootA);
    expect(plain4, equals(utf8.encode('جيل رابع')));
    expect(root4, isNull);
    final (plain5, root5) =
        await cipher.decryptAny(v5, vaultRootKey: rootA);
    expect(plain5, equals(utf8.encode('جيل خامس')));
    expect(root5, equals(logRootA));
    final (plain6, root6) = await cipher.decryptAny(v6,
        password: 'كلمة-القفل-8محارف', recoveryCode: code);
    expect(plain6, equals(utf8.encode('جيل سادس')));
    expect(root6, equals(logRootA));
    // v1 بلا كلمة = رسالة الطلب القديمة نفسها لا استثناء أعمى.
    expect(
      () => cipher.decryptAny(v1),
      throwsA(isA<BackupCipherException>().having(
          (e) => e.message, 'message', contains('الجيل القديم'))),
    );
    // والإصدار المجهول يُرفض بلا تخمين — بايتة إصدار 99 مزورة.
    final forged = List<int>.from(v2);
    forged[7] = 99;
    expect(
      () => cipher.decryptAny(forged),
      throwsA(isA<BackupCipherException>().having(
          (e) => e.message, 'message', contains('غير معروف'))),
    );
  });

  test('س230: جذر سجلات جهاز آخر بالسجل لا يفتح شيئاً إضافياً — السجل '
      'المحمول بيانات تحت DEK لا مادة فك', () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('الجذر المحمول بيانات'),
      vaultRootKey: rootA,
      recoveryCode: code,
      logRootKey: logRootA,
    );
    // جذر سجلات آخر لا يفك النسخة — المواد الخاطئة ترفض صراحة.
    expect(
      () => cipher.decryptVaultedWithLogRoot(
        blob,
        vaultRootKey: rootB,
        recoveryCode: 'WRONG-CODE-0000',
      ),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('خاطئ'))),
    );
  });
}
