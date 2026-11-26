// اختبار أساس أرقام التسليم — دفعة (14) س-148/D-138 بقرار المالك:
// الافتراضي «مجموع الكميات بالواحدة» وخيار الأسطر بقائمة منسدلة،
// وقاعدة الوحدة الموثقة: وحدة واحدة باسمها، ومختلفة بمجموعاتها
// بلا عدد مفبرك يجمع قلماً بعلبة.
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/delivery_summary.dart';

void main() {
  group('التجميع بالواحدة', () {
    test('quantitiesByUnit يجمع بالوحدة لا بفهرسها', () {
      expect(
        quantitiesByUnit(const [(6, 'قطعة'), (4, 'قطعة'), (2, 'علبة')]),
        {'قطعة': 10, 'علبة': 2},
      );
      expect(quantitiesByUnit(const []), isEmpty);
    });
    test('groupedQuantitiesText: الفراغ والوحدة الواحدة والمختلفة', () {
      expect(groupedQuantitiesText(const {}), '');
      expect(groupedQuantitiesText(const {'قطعة': 6}), '6 قطعة');
      expect(
        groupedQuantitiesText(const {'علبة': 2, 'قلم': 5}),
        '2 علبة · 5 قلم',
      );
    });
    test('remainingQuantitiesByUnit ينقص ما استُلم بوحدته', () {
      expect(
        remainingQuantitiesByUnit(
            const {'قلم': 10, 'علبة': 2}, const {'قلم': 5}),
        {'قلم': 5, 'علبة': 2},
      );
    });
  });

  group('سطر خلاصة الفاتورة — invoiceDeliverySummary', () {
    test('الكميات بوحدة واحدة — الافتراضي بقرار المالك', () {
      expect(
        invoiceDeliverySummary(
          deliveredLines: 0,
          totalLines: 1,
          deliveredQtyByUnit: const {},
          totalQtyByUnit: const {'قطعة': 6},
          basis: DeliveryBasis.quantities,
        ),
        'مستلم 0 من 6 قطعة — المتبقي: 6 قطعة',
      );
      expect(
        invoiceDeliverySummary(
          deliveredLines: 2,
          totalLines: 3,
          deliveredQtyByUnit: const {'قلم': 12},
          totalQtyByUnit: const {'قلم': 17},
          basis: DeliveryBasis.quantities,
        ),
        'مستلم 12 من 17 قلم — المتبقي: 5 قلم',
      );
    });
    test('اكتمال التسليم يُعلن لا يُخمَّن', () {
      expect(
        invoiceDeliverySummary(
          deliveredLines: 3,
          totalLines: 3,
          deliveredQtyByUnit: const {'قطعة': 6},
          totalQtyByUnit: const {'قطعة': 6},
          basis: DeliveryBasis.quantities,
        ),
        'مستلم 6 من 6 قطعة — اكتمل التسليم',
      );
    });
    test('وحدات مختلفة: لا جمع مفبرك — العدد بالأسطر والمتبقي بوحداته', () {
      expect(
        invoiceDeliverySummary(
          deliveredLines: 1,
          totalLines: 3,
          deliveredQtyByUnit: const {'قلم': 5},
          totalQtyByUnit: const {'قلم': 7, 'علبة': 1},
          basis: DeliveryBasis.quantities,
        ),
        'مستلم 1 من 3 — المتبقي: 2 قلم · 1 علبة',
      );
    });
    test('أساس الأسطر: العدد بسطور الفاتورة', () {
      expect(
        invoiceDeliverySummary(
          deliveredLines: 1,
          totalLines: 3,
          deliveredQtyByUnit: const {'قلم': 5},
          totalQtyByUnit: const {'قلم': 7},
          basis: DeliveryBasis.lines,
        ),
        'مستلم 1 من 3 — المتبقي: 2',
      );
      expect(
        invoiceDeliverySummary(
          deliveredLines: 3,
          totalLines: 3,
          deliveredQtyByUnit: const {'قلم': 7},
          totalQtyByUnit: const {'قلم': 7},
          basis: DeliveryBasis.lines,
        ),
        'مستلم 3 من 3 — اكتمل التسليم',
      );
    });
  });

  group('ترويسة شاشة المتابعة — deliveryHeaderCount', () {
    test('الكميات بمجموعات وحداتها', () {
      expect(
        deliveryHeaderCount(
          basis: DeliveryBasis.quantities,
          filteredLines: 2,
          allLines: 3,
          filteredQtyByUnit: const {'علبة': 2, 'قلم': 5},
        ),
        '2 علبة · 5 قلم',
      );
    });
    test('الأسطر بلسان D-133 القائم: المفلتر من الإجمالي', () {
      expect(
        deliveryHeaderCount(
          basis: DeliveryBasis.lines,
          filteredLines: 1,
          allLines: 1,
          filteredQtyByUnit: const {'قطعة': 6},
        ),
        '1 من 1',
      );
    });
  });
}
