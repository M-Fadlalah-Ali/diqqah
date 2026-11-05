import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات مستند التجميع — الفحص البنيوي الخالص (F-211 — الدفعة 29
/// سادسة م2، س88): ما لا يحتاج قاعدة بيانات هنا، وفحوص القاعدة
/// (الوجود والتفعيل والنوع والاكتفاء) شأن التخزين على ما خُزّن.
void main() {
  AssemblyDraft draft({
    String date = '2026-11-05',
    int warehouse = 1,
    int bundle = 5,
    int qty = 10,
  }) =>
      AssemblyDraft(
        dateText: date,
        warehouseId: warehouse,
        bundleItemId: bundle,
        qtyBundles: qty,
      );

  group('الفحص البنيوي الخالص — مسودة سليمة تمر بلا أخطاء', () {
    test('المسودة الكاملة السليمة لا أخطاء لها', () {
      expect(validateAssemblyStructure(draft()), isEmpty);
    });

    test('التاريخ الفاسد يرفض — الصيغة والمدى معاً (D-077 ميلاد حصراً)', () {
      for (final bad in [
        '2026/11/05',
        '2026-13-01',
        '2026-00-10',
        '2026-11-00',
        '2026-11-32',
        'لا تاريخ',
        '',
      ]) {
        final errors = validateAssemblyStructure(draft(date: bad));
        expect(errors, isNotEmpty, reason: 'التاريخ «$bad» يرفض');
        expect(errors.first, isA<AssemblyDateInvalid>(),
            reason: 'التاريخ «$bad» أول خطأه التاريخ');
      }
    });

    test('كمية الناتج صفر أو سالبة ترفض — لا تجميع بلا ناتج', () {
      for (final qty in [0, -1, -10]) {
        final errors = validateAssemblyStructure(draft(qty: qty));
        expect(errors.map((e) => e.runtimeType),
            contains(AssemblyQtyInvalid),
            reason: 'الكمية «$qty» ترفض');
      }
    });

    test('المستودع والصنف التجميعي الإصفيّان يرفضان بنيوياً', () {
      expect(
          validateAssemblyStructure(draft(warehouse: 0))
              .whereType<AssemblyWarehouseMissing>(),
          isNotEmpty);
      expect(
          validateAssemblyStructure(draft(bundle: 0))
              .whereType<AssemblyBundleItemMissing>(),
          isNotEmpty);
      expect(
          validateAssemblyStructure(draft(warehouse: -3))
              .whereType<AssemblyWarehouseMissing>(),
          isNotEmpty);
    });
  });

  group('سجل الرسائل العربي الواحد — بادئة التجميع بأوصافها الصادقة', () {
    test('كل خطأ بنهائه وصف عربي صادق يخدم رسالة أول خطأ', () {
      final errors = <AssemblyValidationError>[
        const AssemblyDateInvalid('2026-13-01'),
        const AssemblyQtyInvalid(0),
        const AssemblyWarehouseMissing(7),
        const AssemblyWarehouseInactive('مستودع مغلق'),
        const AssemblyBundleItemMissing(9),
        const AssemblyBundleItemInactive('سلّة قديمة'),
        const AssemblyBundleItemNotBundle('خشب'),
        const AssemblyRecipeRequired(),
        const AssemblyComponentMissing(0, 99),
        const AssemblyComponentInactive(1, 'حبل معطل'),
        const AssemblyComponentIsBundle(2, 'سلّة'),
        const AssemblyComponentInsufficient(
            index: 3, componentLabel: 'خشب', neededQty: 20, onHandQty: 5),
      ];
      for (final e in errors) {
        final text = describeAssemblyValidationError(e);
        expect(text, isNotEmpty, reason: '${e.runtimeType} بلا وصف');
        expect(text, isNot(contains('Assembly')),
            reason: 'السجل عربي صافٍ بلا أسماء تقنية');
      }
      expect(describeAssemblyValidationError(const AssemblyQtyInvalid(0)),
          contains('كمية الناتج'));
      expect(
          describeAssemblyValidationError(const AssemblyRecipeRequired()),
          contains('بلا وصفة'));
      expect(
          describeAssemblyValidationError(const AssemblyComponentInsufficient(
              index: 3, componentLabel: 'خشب', neededQty: 20, onHandQty: 5)),
          contains('منع السالب (F-042)'));
    });

    test('أول وصف للقائمة هو أول خطأ — والقائمة الفارغة «لا خطأ»', () {
      expect(firstAssemblyError([]), 'لا خطأ');
      expect(
        firstAssemblyError([
          const AssemblyQtyInvalid(-2),
          const AssemblyRecipeRequired(),
        ]),
        contains('كمية الناتج'),
      );
    });

    test('الاستثناء يحمل القائمة كاملة ويصف بأول خطأ', () {
      const ex = AssemblyValidationException([
        AssemblyQtyInvalid(0),
        AssemblyRecipeRequired(),
      ]);
      expect(ex.errors, hasLength(2));
      expect(ex.toString(), contains('رفض مدقق مستند التجميع'));
      expect(ex.toString(), contains('كمية الناتج'));
    });
  });
}
