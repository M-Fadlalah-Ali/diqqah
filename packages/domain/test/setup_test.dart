import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  group('PasswordHasher — PBKDF2-HMAC-SHA256 وفق متجهات PKCS#5 المعيارية',
      () {
    test('المتجه المعياري: password/salt، تكرار واحد (dkLen=32)', () {
      const hasher = PasswordHasher(iterations: 1);
      // متجه معياري معروف (password, salt, c=1, dkLen=32)
      expect(
        hasher.hash('password', 'salt'),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('المتجه المعياري: تكراران (dkLen=32)', () {
      const hasher = PasswordHasher(iterations: 2);
      expect(
        hasher.hash('password', 'salt'),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('نفس المدخل والملح يعيد البصمة نفسها — والملح الآخر يغيّرها', () {
      const hasher = PasswordHasher(iterations: 4);
      final a = hasher.hash('secret123', 'aabbccdd');
      final b = hasher.hash('secret123', 'aabbccdd');
      final c = hasher.hash('secret123', '11223344');
      expect(a, b);
      expect(a == c, isFalse);
    });

    test('verify يصادق الصحيح ويرد الخاطئ', () {
      const hasher = PasswordHasher(iterations: 4);
      final stored = hasher.hash('كلمة-مرور', 'deadbeef');
      expect(hasher.verify('كلمة-مرور', 'deadbeef', stored), isTrue);
      expect(hasher.verify('كلمة-مرور-x', 'deadbeef', stored), isFalse);
    });

    test('verifyStored يحلل صيغة «salt:hash» ويرد السجلات الفاسدة', () {
      const hasher = PasswordHasher(iterations: 4);
      final hash = hasher.hash('pass', '00112233');
      expect(PasswordHasher.verifyStored('00112233:$hash', 'pass',
          iterations: 4), isTrue);
      expect(
          PasswordHasher.verifyStored('00112233', 'pass', iterations: 4),
          isFalse);
    });

    test('newSalt: 16 بايت سداسية (32 محرفاً) وغير متكررة عملياً', () {
      final a = PasswordHasher.newSalt();
      final b = PasswordHasher.newSalt();
      expect(a.length, 32);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(a), isTrue); // سداسية صالحة
      expect(a == b, isFalse);
    });

    test('الصيغة الذاتية الوصف (P2): «salt:hash:iterations» تتحقق بتكراراتها المسجلة',
        () {
      const hasher = PasswordHasher(iterations: 5);
      final hash = hasher.hash('pass5', 'aabbccdd');
      final stored = PasswordHasher.formatStored('aabbccdd', hash, 5);
      final parsed = PasswordHasher.parseStored(stored);
      expect(parsed, isNotNull);
      expect(parsed!.iterations, 5);
      expect(parsed.salt, 'aabbccdd');
      expect(parsed.hash, hash);
      expect(PasswordHasher.verifyStored(stored, 'pass5'), isTrue);
      expect(PasswordHasher.verifyStored(stored, 'pass5-x'), isFalse);
    });

    test('سجل الإرث «salt:hash» تكراراته 50,000 ضمنياً — والوسيط الصريح يتجاوز',
        () {
      final parsed = PasswordHasher.parseStored('00112233:deadbeef');
      expect(parsed, isNotNull);
      expect(parsed!.iterations, PasswordHasher.legacyIterations);
      const hasher = PasswordHasher(iterations: 4);
      final hash = hasher.hash('pass', '00112233');
      // بلا وسيط صريح: القراءة بالضمني (50,000) فلا تصادق تجزئة 4.
      expect(PasswordHasher.verifyStored('00112233:$hash', 'pass'), isFalse);
      // بالوسيط الصريح: عقد المتجهات القديم باقٍ حرفاً.
      expect(PasswordHasher.verifyStored('00112233:$hash', 'pass',
          iterations: 4), isTrue);
    });

    test('السجلات الفاسدة تُرد بالتفكيك والتحقق — الصيغ والأطراف والمدى', () {
      expect(PasswordHasher.parseStored(''), isNull);
      expect(PasswordHasher.parseStored('onlysalt'), isNull);
      expect(PasswordHasher.parseStored('a:b:c:d'), isNull);
      expect(PasswordHasher.parseStored('a:b:x'), isNull);
      expect(PasswordHasher.parseStored('a:b:0'), isNull);
      expect(PasswordHasher.parseStored('a:b:-4'), isNull);
      expect(PasswordHasher.parseStored('a:b:99999999'), isNull);
      expect(PasswordHasher.parseStored(':b:4'), isNull);
      expect(PasswordHasher.parseStored('a::4'), isNull);
      expect(PasswordHasher.verifyStored('a:b:c:d', 'p'), isFalse);
      expect(PasswordHasher.verifyStored('a:b:x', 'p'), isFalse);
    });

    test('الافتراضي الإنتاجي 600,000 والقياس الحي بنمط P0 — والمتجه الحي كامل',
        () {
      expect(PasswordHasher.secureIterations, 600000);
      expect(PasswordHasher.legacyIterations, 50000);
      const secure = PasswordHasher();
      expect(secure.iterations, PasswordHasher.secureIterations);
      // القياس الحي: الكلفة توثق بطبعتها على عُدّة الحكم — والجهاز
      // المنخفض بيد المالك (حد P0 الصادق بنص الخطة).
      const legacy =
          PasswordHasher(iterations: PasswordHasher.legacyIterations);
      final legacyWatch = Stopwatch()..start();
      legacy.hash('measure', PasswordHasher.newSalt());
      legacyWatch.stop();
      final secureWatch = Stopwatch()..start();
      secure.hash('measure', PasswordHasher.newSalt());
      secureWatch.stop();
      // ignore: avoid_print
      print('P2 القياس الحي: إرث(${legacy.iterations})='
          '${legacyWatch.elapsedMilliseconds}ms '
          'معتمد(${secure.iterations})='
          '${secureWatch.elapsedMilliseconds}ms');
      // المتجه الحي عند المعتمد: الصيغة كاملة تجزئة ثم تحقق ثم رفض.
      final salt = PasswordHasher.newSalt();
      final stored = PasswordHasher.formatStored(salt,
          secure.hash('roundtrip-600k', salt),
          PasswordHasher.secureIterations);
      expect(PasswordHasher.verifyStored(stored, 'roundtrip-600k'), isTrue);
      expect(
          PasswordHasher.verifyStored(stored, 'roundtrip-600k-x'), isFalse);
    });
  });

  group('FirstRunGate — بوابة أول التشغيل (F-014، س-01)', () {
    test('بلا مستخدمين: التهيئة إلزامية', () {
      expect(const FirstRunGate(hasAnyUser: false).needsSetup, isTrue);
    });

    test('بمدير موجود: لا شاشة أولى', () {
      expect(const FirstRunGate(hasAnyUser: true).needsSetup, isFalse);
    });
  });
}
