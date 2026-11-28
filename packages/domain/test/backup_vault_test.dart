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

  test('د11: مادة خاطئة واحدة = رفض صريح قبل أي بايت للقاعدة (روح F-013)',
      () async {
    final blob = await cipher.encryptVaulted(
      utf8.encode('نسخة'),
      vaultRootKey: rootA,
      recoveryCode: code,
    );
    expect(
      () => cipher.decryptVaulted(
        blob,
        vaultRootKey: rootA,
        recoveryCode: 'WRONG-CODE-0000',
      ),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('خاطئ'))),
    );
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
}
