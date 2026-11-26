import 'dart:convert';

import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// س221 — تنفيذ المؤجل س219 «تسريع التجزئة بتنفيذ أصلي» بأمر المالك
/// «ابدأ بتنفيذ الدفعات الخمسة بالتسلسل الذي عرضته»: النواة الأصيلة
/// القابلة للتثبيت ([PasswordHasher.nativeCore]) — الاختبارات هنا تحكم
/// العقد الرباعية: الاستخدام حين تُثبت، والمطابقة الحرفية للخالصة،
/// والهوي للبديل الخالص بعزل الخلفية عند أي فشل أصيل، والإغلاق
/// الفشلي (نتيجة أصيلة مخالفة = رفض) مع بقاء فاسد السجل بلا عمل.
/// التثبيت الحقيقي بالتحقق الذاتي بيد اختبار الواجهة s221 بقناة محاكاة.
void main() {
  tearDown(() {
    // حالة ساكنة مشتركة — إعادة الضبط بعد كل اختبار فلا تلويث لاحق.
    PasswordHasher.nativeCore = null;
  });

  test('س221: الأصيلة المثبتة تُنادى بالوسائط ذاتها وتُقبل نتيجتها — '
      'والنتيجة مطابقة للخالصة حرفاً بالمسارات الثلاثة', () async {
    final calls = <List<Object?>>[];
    PasswordHasher.nativeCore = (password, salt, iterations, dkLen) async {
      calls.add(<Object?>[
        utf8.decode(password),
        utf8.decode(salt),
        iterations,
        dkLen,
      ]);
      return PasswordHasher.pbkdf2Bytes(password, salt, iterations, dkLen);
    };
    final salt = PasswordHasher.newSalt();
    final nativeHash = await PasswordHasher.hashInBackground(
        'م-س221', salt,
        iterations: 200);
    final pureHash = PasswordHasher(iterations: 200).hash('م-س221', salt);
    expect(nativeHash, pureHash,
        reason: 'الأصيلة تُطبق الرياضيات ذاتها فالنواتج واحدة');
    expect(calls, hasLength(1));
    expect(calls.single[0], 'م-س221');
    expect(calls.single[1], salt);
    expect(calls.single[2], 200);
    expect(calls.single[3], 32, reason: 'طول الاشتقاق 32 بعقد الكلمات');

    final stored = PasswordHasher.formatStored(salt, pureHash, 200);
    expect(await PasswordHasher.verifyStoredInBackground(stored, 'م-س221'),
        isTrue,
        reason: 'التحقق عبر الأصيلة المثبتة — والنتيجة مطابقة');
    expect(await PasswordHasher.verifyStoredInBackground(stored, 'خطأ'),
        isFalse,
        reason: 'والرفض عبر الأصيلة ذاتها');
    await PasswordHasher.equalizingWorkInBackground(iterations: 200);
    expect(calls, hasLength(4),
        reason: 'hash وتحققا وعمل الموازنة — كلها عبر الأصيلة');
  });

  test('س221: فشل الأصيلة يهوي للبديل الخالص بعزل الخلفية — النتيجة '
      'صحيحة والمسار لا يتعطل أبداً (شبكة س219 الأخيرة)', () async {
    var attempts = 0;
    PasswordHasher.nativeCore = (password, salt, iterations, dkLen) async {
      attempts++;
      throw StateError('أصيلة معطلة (محاكاة)');
    };
    final salt = PasswordHasher.newSalt();
    final nativeHash = await PasswordHasher.hashInBackground(
        'م-س221', salt,
        iterations: 200);
    expect(
        nativeHash,
        PasswordHasher(iterations: 200).hash('م-س221', salt),
        reason: 'الهوي للخالص يجيب بالنتيجة الصحيحة رغم فشل الأصيلة');
    expect(attempts, 1, reason: 'المحاولة الأصيلة جرت ثم هوت');

    final stored = PasswordHasher.formatStored(
        salt, PasswordHasher(iterations: 200).hash('م-س221', salt), 200);
    expect(await PasswordHasher.verifyStoredInBackground(stored, 'م-س221'),
        isTrue,
        reason: 'التحقق يتجاوز الأصيلة الفاشلة للخالص');
    expect(attempts, 2);
  });

  test('س221: الإغلاق الفشلي — جواب أصيل مخالف يرفض الدخول ولا يُقبل '
      'نتيجة غير متحققة (والتثبيت الذاتي يعزل هذا أصلاً)', () async {
    PasswordHasher.nativeCore =
        (password, salt, iterations, dkLen) async =>
            List<int>.filled(dkLen, 0);
    final salt = PasswordHasher.newSalt();
    final stored = PasswordHasher.formatStored(
        salt, PasswordHasher(iterations: 200).hash('م-س221', salt), 200);
    expect(await PasswordHasher.verifyStoredInBackground(stored, 'م-س221'),
        isFalse,
        reason: 'نتيجة أصيلة مخالفة = رفض فشلي لا قبول');
  });

  test('س221: فاسد السجل بلا عمل — الأصيلة المثبتة لا تُنادى أبداً '
      '(عقد parseStored باقياً)', () async {
    var calls = 0;
    PasswordHasher.nativeCore = (password, salt, iterations, dkLen) async {
      calls++;
      return PasswordHasher.pbkdf2Bytes(password, salt, iterations, dkLen);
    };
    expect(await PasswordHasher.verifyStoredInBackground('سجل-فاسد', 'م-س221'),
        isFalse);
    expect(calls, 0,
        reason: 'التفكيك هنا — الفاسد false بلا عمل إطلاقاً');
  });
}
