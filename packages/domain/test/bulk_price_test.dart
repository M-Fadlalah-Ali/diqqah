import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات الترقية الجماعية للأسعار — F-165/الدفعة 23 (D-183): التقريب
/// بقاعدة س7 بمساعدها الواحد، والصفر ليس سعراً، وهدف الحقول، ومصدر
/// النسبة بعدد صحيح بلا كسور عائمة.
void main() {
  group('parsePercentToBps — النسبة أعداد صحيحة حصراً', () {
    test('الأشكال السليمة', () {
      expect(parsePercentToBps('5'), 500);
      expect(parsePercentToBps('2.5'), 250);
      expect(parsePercentToBps('2.55'), 255);
      expect(parsePercentToBps('0.1'), 10);
      expect(parsePercentToBps('-3'), -300);
      expect(parsePercentToBps('-3.25'), -325);
      expect(parsePercentToBps(' 7 '), 700, reason: 'الأطراف تُقلَّم');
      expect(parsePercentToBps('+4'), 400);
    });

    test('المجال (−100, +10000] — الزائد والناقص والفاسد رفض', () {
      expect(parsePercentToBps('10000'), 1000000, reason: 'الحد الأعلى داخل');
      expect(parsePercentToBps('10000.01'), isNull, reason: 'فوق الحد رفض');
      expect(parsePercentToBps('-100'), isNull, reason: 'تصفير كامل مرفوض');
      expect(parsePercentToBps('-99.99'), -9999, reason: 'قبله بقليل داخل');
      expect(parsePercentToBps('2.555'), isNull, reason: 'ثلاث خانات رفض');
      expect(parsePercentToBps(''), isNull);
      expect(parsePercentToBps('abc'), isNull);
      expect(parsePercentToBps('5%'), isNull, reason: 'الرمز لا يدخل');
      expect(parsePercentToBps('٢'), isNull, reason: 'الأرقام العربية الشرقية بلا تحويل صامت');
    });
  });

  group('bulkPriceOutcome — س7 والصفر والهدف', () {
    test('رفع 2.5% على 10,000 ← تقريب النصف بعيداً عن الصفر', () {
      // 10000 × 10250 / 10000 = 10250 بالتمام.
      expect(
        bulkPriceOutcome(
                oldSalePriceMinor: 10000,
                oldPurchasePriceMinor: 0,
                percentBps: 250,
                target: BulkPriceTarget.sale)
            .newSalePriceMinor,
        10250,
      );
    });

    test('النصف يذهب بعيداً عن الصفر — 5% على 10,001', () {
      // 10001 × 10500 / 10000 = 10501.05 ← 10501
      expect(
        bulkPriceOutcome(
                oldSalePriceMinor: 10001,
                oldPurchasePriceMinor: 0,
                percentBps: 500,
                target: BulkPriceTarget.sale)
            .newSalePriceMinor,
        10501,
      );
      // 10005 × 10500 / 10000 = 10505.25 ← 10505
      expect(
        bulkPriceOutcome(
                oldSalePriceMinor: 10005,
                oldPurchasePriceMinor: 0,
                percentBps: 500,
                target: BulkPriceTarget.sale)
            .newSalePriceMinor,
        10505,
      );
      // س7 الحرفية: 9999 × 1.05 = 10498.95 ← 10499 (نصف وما فوق يبعد)
      expect(
        bulkPriceOutcome(
                oldSalePriceMinor: 9999,
                oldPurchasePriceMinor: 0,
                percentBps: 500,
                target: BulkPriceTarget.sale)
            .newSalePriceMinor,
        10499,
      );
    });

    test('الصفر ليس سعراً فلا يُرفع (س6 «بلا سعر بعد»)', () {
      final out = bulkPriceOutcome(
          oldSalePriceMinor: 0,
          oldPurchasePriceMinor: 0,
          percentBps: 1000,
          target: BulkPriceTarget.both);
      expect(out.newSalePriceMinor, 0);
      expect(out.newPurchasePriceMinor, 0);
    });

    test('الهدف يحدد الحقل — الغير مستهدف يمر كما هو', () {
      final sale = bulkPriceOutcome(
          oldSalePriceMinor: 1000,
          oldPurchasePriceMinor: 700,
          percentBps: 1000,
          target: BulkPriceTarget.sale);
      expect(sale.newSalePriceMinor, 1100);
      expect(sale.newPurchasePriceMinor, 700, reason: 'الشراء لم يُمس');

      final purchase = bulkPriceOutcome(
          oldSalePriceMinor: 1000,
          oldPurchasePriceMinor: 700,
          percentBps: 1000,
          target: BulkPriceTarget.purchase);
      expect(purchase.newSalePriceMinor, 1000, reason: 'البيع لم يُمس');
      expect(purchase.newPurchasePriceMinor, 770);
    });

    test('التخفيض بنسبة سالبة مشروع — ولا سعر سالب أبداً', () {
      final out = bulkPriceOutcome(
          oldSalePriceMinor: 1000,
          oldPurchasePriceMinor: 0,
          percentBps: -250,
          target: BulkPriceTarget.sale);
      expect(out.newSalePriceMinor, 975);
      // −50% على 1 ← 0.5 ← النصف بعيداً عن الصفر ← 1؟ لا: 1×5000/10000
      // بسط 5000 ومقام 10000: (2×5000+10000)~/20000 = 20000~/20000 = 1
      final half = bulkPriceOutcome(
          oldSalePriceMinor: 1,
          oldPurchasePriceMinor: 0,
          percentBps: -5000,
          target: BulkPriceTarget.sale);
      expect(half.newSalePriceMinor, 1,
          reason: '0.5 يقرب إلى 1 بالنصف بعيداً عن الصفر — لا صفر زائف');
    });
  });
}
