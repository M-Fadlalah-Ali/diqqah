// اختبارات د3 (س170 — الترقيم متعدد الأجهزة وتعدد الشركات بموضع
// م-٢/م-٥): عقد بادئة الجهاز بعد حسم D-071، وجهازان بلا تصادم
// والعدادات سليمة (س-24 التفريغ الأولي)، وصيغة D-169 بالبادئة
// والصيغة القائمة بلا مساس، والشركة الحاملة kDefaultCompanyId.
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  test('بادئة الجهاز: الصيغة السليمة وحرس الشكل الصوتي', () {
    expect(isValidDevicePrefix('ج1'), isTrue);
    expect(isValidDevicePrefix('ج12'), isTrue);
    expect(isValidDevicePrefix('ج999'), isTrue);
    expect(isValidDevicePrefix(''), isFalse);
    expect(isValidDevicePrefix('ج'), isFalse);
    expect(isValidDevicePrefix('ج0'), isFalse, reason: 'لا صفر بلا رقم');
    expect(isValidDevicePrefix('ج1000'), isFalse, reason: 'حد الثلاث خانات');
    expect(isValidDevicePrefix('device-1'), isFalse);
    expect(isValidDevicePrefix('ج1x'), isFalse);
    expect(
      () => validateDevicePrefix('wrong'),
      throwsA(isA<FormatException>()),
    );
    expect(validateDevicePrefix('ج7'), 'ج7');
  });

  test('س-24 التفريغ الأولي: أول بادئة حرة متصلة من 1 وحتمية', () {
    expect(nextDevicePrefix({}), 'ج1');
    expect(nextDevicePrefix({'ج1'}), 'ج2');
    expect(nextDevicePrefix({'ج1', 'ج2', 'ج4'}), 'ج3',
        reason: 'أول حرة لا أعلى مأخوذة +1 — والثغرات تُستدرك');
    expect(
      () => nextDevicePrefix({'junk'}),
      throwsA(isA<FormatException>()),
      reason: 'المأخوذ الفاسد يُرفض صوتياً فلا تسجيل خاطئ',
    );
  });

  test('جهازان ببادئتين يترحّلان بلا تصادم والعدادات سليمة (عرف §4)',
      () {
    // العدّاد محلي لكل جهاز: نفس السنة ونفس الرقم المتصل — والبادئة
    // وحدها تفصل الرقمين فلا تصادم ممكن حرفاً.
    final a = formatDocumentNumber(2026, 1, devicePrefix: 'ج1');
    final b = formatDocumentNumber(2026, 1, devicePrefix: 'ج2');
    expect(a, '26ج1-000001');
    expect(b, '26ج2-000001');
    expect(a, isNot(b));
    // العدادات سليمة داخل الجهاز: التتابع متصل بلا فجوات (F-054).
    final seqA = [
      formatDocumentNumber(2026, 1, devicePrefix: 'ج1'),
      formatDocumentNumber(2026, 2, devicePrefix: 'ج1'),
      formatDocumentNumber(2026, 3, devicePrefix: 'ج1'),
    ];
    expect(seqA, ['26ج1-000001', '26ج1-000002', '26ج1-000003']);
  });

  test('الجهاز الواحد بلا بادئة يعيد الصيغة القائمة حرفاً (D-169)', () {
    expect(formatDocumentNumber(2026, 1), '26000001');
    expect(formatDocumentNumber(2026, 123456), '26123456');
    expect(
      formatSequenceLabel('قيد عام', 2026, 7),
      'قيد عام 26000007',
      reason: 'الغلاف القائم بلا بادئة لم يُمس حرفاً',
    );
    expect(
      formatSequenceLabel('فاتورة بيع', 2026, 3, counterWidth: 6),
      'فاتورة بيع 26000003',
    );
  });

  test('التسمية الكاملة بالبادئة عبر الغلاف الموحد', () {
    expect(
      formatSequenceLabel('فاتورة بيع', 2026, 1, devicePrefix: 'ج2'),
      'فاتورة بيع 26ج2-000001',
      reason: 'نموذج 08 §4 بلسانه المعاصر D-169',
    );
  });

  test('الشركة الافتراضية الواحدة ثابتة الصيغة ASCII', () {
    expect(kDefaultCompanyId, 'main');
  });
}
