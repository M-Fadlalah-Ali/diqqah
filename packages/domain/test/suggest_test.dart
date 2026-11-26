import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات قواعد الاقتراح النقية — F-146 جزءها الأول/الدفعة 23
/// (D-183): حتمية «الأكثر تداولاً» وتقديم آخر سعر فعلي على المرجعي.
void main() {
  group('suggestMostActiveParty — الأكثر عدداً بحتمية كاملة', () {
    test('الأكثر عدداً يفوز', () {
      expect(suggestMostActiveParty({3: 2, 7: 9, 5: 4}), 7);
    });

    test('التساوي يذهب للأصغر معرفاً — لا اعتماد على ترتيب الخريطة', () {
      expect(suggestMostActiveParty({9: 4, 2: 4, 5: 4}), 2);
      expect(suggestMostActiveParty({5: 4, 9: 4, 2: 4}), 2,
          reason: 'ترتيب الإدخال لا يغير الحكم');
    });

    test('الخلو بلا اقتراح والصفر عدّاً لا يعطي أحداً', () {
      expect(suggestMostActiveParty({}), isNull);
      expect(suggestMostActiveParty({4: 0}), isNull,
          reason: 'عدّاد صفر = لا تداول فلا اقتراح');
    });
  });

  group('suggestLinePriceMinor — آخر سعر فعلي على المرجعي', () {
    test('آخر سعر فعلي موجب يقدم', () {
      expect(
        suggestLinePriceMinor(lastActualPriceMinor: 15000, referencePriceMinor: 12000),
        15000,
      );
    });

    test('لا تاريخ ← المرجعي', () {
      expect(
        suggestLinePriceMinor(lastActualPriceMinor: null, referencePriceMinor: 12000),
        12000,
      );
    });

    test('آخر سعر صفري ليس سعراً (س6) ← المرجعي حتى لو صفراً', () {
      expect(
        suggestLinePriceMinor(lastActualPriceMinor: 0, referencePriceMinor: 12000),
        12000,
        reason: 'الصفر المخزن ليس سعراً فلا يقدَّم اقتراحاً',
      );
      expect(
        suggestLinePriceMinor(lastActualPriceMinor: null, referencePriceMinor: 0),
        0,
        reason: '«بلا سعر بعد» يبقى الحقل فارغاً بنفس اللسان',
      );
    });
  });
}
