// اختبارات p3 (س146 — خط التشفير المرحلة الثالثة): مشفر سجلات
// الأحداث والأخطاء — AES-256-GCM لكل سجل بHKDF وملح القاعدة،
// البادئة حارس التوافق الرجعي، ووسم GCM حارس العبث (DQ-1108).
import 'dart:convert';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  const salt = '0123456789abcdef0123456789abcdef';
  final cipher = LogCipher();

  test('الجولة: ختم ثم فك يعيد النص حرفاً (عربي وJSON)', () async {
    const text = '{"entity":"move","amount":123456,"ملاحظة":"قيد افتتاحي"}';
    final sealed = await cipher.seal(text, salt);
    expect(sealed.startsWith(LogCipher.envelopePrefix), isTrue,
        reason: 'الغلاف المعتمد dq3log1: لا استثناء');
    expect(await cipher.open(sealed, salt), text);
  });

  test('النونس لكل سجل: سجلا حكما متطابقان لا تتطابق بايتاتهما', () async {
    const text = 'نفس النص تماماً';
    final a = await cipher.seal(text, salt);
    final b = await cipher.seal(text, salt);
    expect(a, isNot(b),
        reason: 'نونس عشوائي لكل سجل — بند IV الفريد بالوثيقة');
    expect(await cipher.open(a, salt), text);
    expect(await cipher.open(b, salt), text);
  });

  test('العبث ببايت واحد يكسر وسم GCM — DQ-1108 لا نص ملفّق', () async {
    final sealed = await cipher.seal('{"payload":true}', salt);
    final raw = base64Decode(sealed.substring(LogCipher.envelopePrefix.length));
    raw[raw.length - 3] ^= 0x01; // العبث داخل وسم الـGCM من آخره
    final tampered = LogCipher.envelopePrefix + base64Encode(raw);
    await expectLater(
      cipher.open(tampered, salt),
      throwsA(isA<LogCipherIntegrityException>()),
    );
  });

  test('العبث بالحمولة لا بالوسم يُرفض هو أيضاً', () async {
    final sealed = await cipher.seal('{"payload":true}', salt);
    final raw = base64Decode(sealed.substring(LogCipher.envelopePrefix.length));
    raw[20] ^= 0x80; // وسط النص المشفر
    final tampered = LogCipher.envelopePrefix + base64Encode(raw);
    await expectLater(
      cipher.open(tampered, salt),
      throwsA(isA<LogCipherIntegrityException>()),
    );
  });

  test('ملح آخر لا يفك — الاشتقاق بملح القاعدة حصراً', () async {
    final sealed = await cipher.seal('بيانات مالية', salt);
    await expectLater(
      cipher.open(sealed, 'ffffffffffffffffffffffffffffffff'),
      throwsA(isA<LogCipherIntegrityException>()),
    );
  });

  test('التوافق الرجعي: النص الخام بلا بادئة يمر كما هو', () async {
    const legacy = '{"old":"plaintext"}';
    expect(await cipher.open(legacy, salt), legacy,
        reason: 'سجلات ما قبل الإحكام تُقرأ بلا تمييز ثانٍ');
  });

  test('الغلاف قصير غير المكتمل — DQ-1108 لا RangeError', () async {
    final broken =
        LogCipher.envelopePrefix + base64Encode(<int>[1, 2, 3]);
    await expectLater(
      cipher.open(broken, salt),
      throwsA(isA<LogCipherIntegrityException>()),
    );
  });

  test('بعد البادئة ليس base64 — DQ-1108 لا FormatException', () async {
    await expectLater(
      cipher.open('${LogCipher.envelopePrefix}ليس-باز64-أصلاً!!!', salt),
      throwsA(isA<LogCipherIntegrityException>()),
    );
  });

  test('الاستثناء يحمل الرمز المعتمد DQ-1108 بنصه', () {
    const integrity = LogCipherIntegrityException();
    expect(integrity.toString().contains('DQ-1108'), isTrue);
    // والرمز مسجل بالسلطة الموحدة — لا رمز شارد خارج السجل.
    expect(diqqahErrorCodeOf('DQ-1108'), isNotNull);
  });

  test('ذاكرة الاشتقاق: المفتاح ذاته لملح واحد بنداءات متكررة', () async {
    final k1 = await cipher.deriveKey(salt);
    final k2 = await cipher.deriveKey(salt);
    expect(identical(k1, k2), isTrue,
        reason: 'HKDF سريع أصلاً والذاكرة تحفظ النداء لا الصواب');
    expect(k1.length, 32);
  });

  // ── س230 (د11 الجزء الثاني — جذر الجهاز من الخزنة) ──────────────

  // جذر سجلات هذا الجهاز — 32 بايتة مستقلة عن جذر النسخ (عقد الفصل).
  final deviceRoot = List<int>.generate(32, (i) => (i * 5 + 41) % 256);
  final otherRoot = List<int>.generate(32, (i) => (i * 17 + 3) % 256);

  test('س230: مشفر بجذر الجهاز — ختم وفك بجذره حرفاً', () async {
    final deviceCipher = LogCipher(deviceRoot);
    const text = '{"entity":"move","amount":9001,"ملاحظة":"بجذر الجهاز"}';
    final sealed = await deviceCipher.seal(text, salt);
    expect(await deviceCipher.open(sealed, salt), text);
  });

  test('س230: القراءة الإرثية — الجذر المضمّن يبقى قارئاً لسجلات ما قبل '
      'س230 (عقد دائم)، وجذر الجهاز يقرأ القديمة والإرثية معاً',
      () async {
    final legacySealed = await LogCipher().seal('سجل قديم إرثي', salt);
    // جذر الجهاز يفتح ما ختمه الإرثي المضمّن — القراءة الإرثية حرفاً.
    final deviceCipher = LogCipher(deviceRoot);
    expect(await deviceCipher.open(legacySealed, salt), 'سجل قديم إرثي');
    // والإرثي يفتح ما ختمه هو، وجهازٌ آخر بجذره لا يفتحه (وسم GCM حاكم).
    expect(await LogCipher().open(legacySealed, salt), 'سجل قديم إرثي');
    final sealedElsewhere = await LogCipher(otherRoot).seal('جذر آخر', salt);
    await expectLater(
      deviceCipher.open(sealedElsewhere, salt),
      throwsA(isA<LogCipherIntegrityException>()),
    );
  });

  test('س230: openWithRoots — جذور مرشحة بالترتيب والإرثي أخيراً، ونفادها '
      'استثناء سلامة واحد', () async {
    final deviceCipher = LogCipher(deviceRoot);
    final sealedByDevice = await deviceCipher.seal('بجذر هذا الجهاز', salt);
    final legacySealed = await LogCipher().seal('بالإرثي المضمّن', salt);
    // جذر النسخة أولاً ثم جذر هذا الجهاز ثم الإرثي — كلا السجلين يُفتح.
    expect(
        await LogCipher()
            .openWithRoots(sealedByDevice, salt, [deviceRoot, otherRoot]),
        'بجذر هذا الجهاز');
    expect(await LogCipher().openWithRoots(legacySealed, salt, [otherRoot]),
        'بالإرثي المضمّن',
        reason: 'الإرثي يُجرَّب أخيراً دائماً — عقد القراءة الإرثية');
    // النص الخام يمر كما هو بالتوافق الرجعي ذاته.
    expect(await LogCipher().openWithRoots('خام', salt, [deviceRoot]), 'خام');
    // نفاد الجذور كلها = استثناء سلامة واحد صريح.
    final sealedOther = await LogCipher(otherRoot).seal('جذر غريب', salt);
    await expectLater(
      LogCipher().openWithRoots(sealedOther, salt, [deviceRoot]),
      throwsA(isA<LogCipherIntegrityException>()),
    );
  });

  test('س230: باني الجذر يرفض المبتور والشاذ بصوت عالٍ — لا مشفر بمفتاح '
      'ناقص', () {
    expect(() => LogCipher([1, 2, 3]), throwsA(isA<ArgumentError>()));
    expect(() => LogCipher(List<int>.filled(16, 7)), throwsA(isA<ArgumentError>()));
    // والجذر الصحيح 32 بايتة يُقبل، والغائب = الإرثي المضمّن (انخفاض موثق).
    expect(LogCipher(deviceRoot), isNotNull);
    expect(LogCipher(), isNotNull);
  });
}
