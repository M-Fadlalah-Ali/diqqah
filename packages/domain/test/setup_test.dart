import 'package:test/test.dart';
import 'package:heseb_domain/heseb_domain.dart';

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
