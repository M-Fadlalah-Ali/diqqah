import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات الدفعة 28 (خامسة م2) — التجميعي الجاهز والفكك
/// (F-034/F-212).
///
/// المثال الحرفي للمتطلب موضع اختبار (F-034): بيع 12 سلّة برصيد 6
/// جاهزة ⇒ 6 بتكلفة المخزون و6 بحركات مكونات — والثابت F-178 مستقر
/// (تكاليف المخزون المحمولة تساوي دلتا قيم الأرصدة حرفاً)، وخدمة
/// الوصفة بخياريها (F-212): بلا تكلفة بند بيعي وبقيمة تدخل مجموع كلف
/// الوصفة — وبلا حركة مخزون في الحالتين.
void main() {
  /// مكونات وصفة المثال: سلّة = 2 خشب + 1 حبل + خدمة تجميع.
  List<BundleComponentStockInput> exampleComponents({
    int woodQty = 20,
    int woodValue = 200000,
    int ropeQty = 20,
    int ropeValue = 40000,
    int? assemblyCostPerUnit = 500,
  }) {
    return [
      BundleComponentStockInput(
        itemId: 11,
        isService: false,
        qtyPerBundle: 2,
        stockQty: woodQty,
        stockValue: woodValue,
      ),
      BundleComponentStockInput(
        itemId: 12,
        isService: false,
        qtyPerBundle: 1,
        stockQty: ropeQty,
        stockValue: ropeValue,
      ),
      BundleComponentStockInput(
        itemId: 13,
        isService: true,
        qtyPerBundle: 1,
        serviceCostMinor: assemblyCostPerUnit,
      ),
    ];
  }

  group('مدقق الوصفة البنيوي — validateBundleRecipeStructure', () {
    test('وصفة فارغة مرفوضة (س-09)', () {
      final errors = validateBundleRecipeStructure(
          const BundleRecipeDraft(bundleItemId: 5, components: []));
      expect(errors, hasLength(1));
      expect(errors.single, isA<BundleRecipeEmpty>());
    });

    test('كمية صفر أو سالبة مرفوضة (س6)', () {
      final errors = validateBundleRecipeStructure(BundleRecipeDraft(
        bundleItemId: 5,
        components: [
          const BundleComponentDraft(componentItemId: 7, qtyBase: 0),
          const BundleComponentDraft(componentItemId: 8, qtyBase: -3),
        ],
      ));
      expect(errors, hasLength(2));
      expect(errors[0], isA<BundleComponentQtyInvalid>());
      expect((errors[0] as BundleComponentQtyInvalid).qtyBase, 0);
      expect((errors[1] as BundleComponentQtyInvalid).qtyBase, -3);
    });

    test('مكوّن مكرر مرفوض — حتى ولو بكمية سليمة', () {
      final errors = validateBundleRecipeStructure(BundleRecipeDraft(
        bundleItemId: 5,
        components: const [
          BundleComponentDraft(componentItemId: 7, qtyBase: 2),
          BundleComponentDraft(componentItemId: 7, qtyBase: 3),
        ],
      ));
      expect(errors, hasLength(1));
      expect(errors.single, isA<BundleComponentDuplicate>());
      expect((errors.single as BundleComponentDuplicate).index, 1);
    });

    test('التجميعي مكوّناً من نفسه مرفوض', () {
      final errors = validateBundleRecipeStructure(BundleRecipeDraft(
        bundleItemId: 5,
        components: const [
          BundleComponentDraft(componentItemId: 5, qtyBase: 1),
        ],
      ));
      expect(errors, hasLength(1));
      expect(errors.single, isA<BundleSelfComponent>());
    });

    test('تكلفة سالبة مرفوضة (س6)', () {
      final errors = validateBundleRecipeStructure(BundleRecipeDraft(
        bundleItemId: 5,
        components: const [
          BundleComponentDraft(
              componentItemId: 7, qtyBase: 1, costMinor: -1),
        ],
      ));
      expect(errors, hasLength(1));
      expect(errors.single, isA<BundleComponentCostInvalid>());
    });

    test('وصفة سليمة تمر بلا أخطاء — خدمة بتكلفة وبضاعة بلا خانة', () {
      final errors = validateBundleRecipeStructure(BundleRecipeDraft(
        bundleItemId: 5,
        components: const [
          BundleComponentDraft(componentItemId: 7, qtyBase: 2),
          BundleComponentDraft(
              componentItemId: 8, qtyBase: 1, costMinor: 500),
        ],
      ));
      expect(errors, isEmpty);
    });
  });

  group('مخطط بيع التجميعي — planBundleSaleBreakdown (F-034 حرفاً)', () {
    test('مثال المتطلب: بيع 12 برصيد 6 جاهزة ⇒ 6 جاهزة بكلفة المخزون '
        'و6 مفككة بحركات مكونات', () {
      // رصيد السلّة الجاهز: (6، 60,000) — كلفتها 10,000 للوحدة.
      final outcome = planBundleSaleBreakdown(
        saleQtyBase: 12,
        bundleReadyQty: 6,
        bundleReadyValue: 60000,
        components: exampleComponents(
            woodQty: 20, woodValue: 200000, ropeQty: 20, ropeValue: 40000),
      );
      expect(outcome.errors, isEmpty);
      final plan = outcome.plan;
      expect(plan.readyQty, 6);
      expect(plan.brokenQty, 6);

      // الجاهز: الخروج بكل الرصيد يمتص قيمته كلها (D-067).
      expect(plan.readyValueMinor, 60000);

      // الفكك: 6 سلل × (2 خشب + 1 حبل).
      final wood = plan.components.singleWhere((c) => c.itemId == 11);
      expect(wood.qtyOut, 12);
      expect(wood.valueMinor, 120000); // متوسط الخشب 10,000 × 12
      final rope = plan.components.singleWhere((c) => c.itemId == 12);
      expect(rope.qtyOut, 6);
      expect(rope.valueMinor, 12000); // متوسط الحبل 2,000 × 6

      // الخدمة: بلا حركة وتكلفتها 500 × 6 = 3,000 (F-212).
      final service = plan.components.singleWhere((c) => c.itemId == 13);
      expect(service.isService, isTrue);
      expect(service.qtyOut, 0);
      expect(service.valueMinor, 3000);

      // التكاليف الثلاث: المخزنية للمحرك، والخدمية بالمجال، والمركبة
      // لسطر التكلفة الواحد (F-034).
      expect(plan.inventoryCostMinor, 60000 + 120000 + 12000);
      expect(plan.serviceCostMinor, 3000);
      expect(plan.compositeCostMinor, 195000);
    });

    test('البيع كلُّه من الجاهز: لا فكك ولا مساس بالمكونات ولا وصفة '
        'مطلوبة', () {
      final outcome = planBundleSaleBreakdown(
        saleQtyBase: 4,
        bundleReadyQty: 6,
        bundleReadyValue: 60000,
        components: exampleComponents(),
      );
      expect(outcome.errors, isEmpty);
      final plan = outcome.plan;
      expect(plan.readyQty, 4);
      expect(plan.brokenQty, 0);
      // خروج جزئي بالنسبة: 60,000 × 4/6 = 40,000 بالنصف بعيداً عن الصفر.
      expect(plan.readyValueMinor, 40000);
      // المكونات بلا مساس: البضاعة لا خطط لها والخدمة بتكلفة صفر.
      expect(
          plan.components.where((c) => !c.isService).map((c) => c.qtyOut),
          everyElement(0));
      expect(plan.serviceCostMinor, 0);
      expect(plan.compositeCostMinor, 40000);
    });

    test('رصيد الجاهز صفر: الفكك كلُّه من المكونات — والقيم تُمتص '
        'بحكم الكلية (D-067)', () {
      final outcome = planBundleSaleBreakdown(
        saleQtyBase: 3,
        bundleReadyQty: 0,
        bundleReadyValue: 0,
        components: exampleComponents(
            woodQty: 10, woodValue: 100000, ropeQty: 5, ropeValue: 10000),
      );
      expect(outcome.errors, isEmpty);
      final plan = outcome.plan;
      expect(plan.readyQty, 0);
      expect(plan.brokenQty, 3);
      expect(plan.readyValueMinor, 0);
      final wood = plan.components.singleWhere((c) => c.itemId == 11);
      expect(wood.qtyOut, 6);
      expect(wood.valueMinor, 60000);
      expect(plan.inventoryCostMinor, 60000 + 6000);
    });

    test('نقص مكوّن يُرفض بالكلية قبل القبول — المطلوب والمتاح يحملان '
        '(س-09/F-042)', () {
      final outcome = planBundleSaleBreakdown(
        saleQtyBase: 5,
        bundleReadyQty: 2,
        bundleReadyValue: 20000,
        components: exampleComponents(
            woodQty: 5, woodValue: 50000, ropeQty: 20, ropeValue: 40000),
      );
      // المفكك 3 سلل × 2 خشب = 6 والرصيد 5 ⇒ رفض.
      expect(outcome.errors, hasLength(1));
      final err = outcome.errors.single as BundleSaleComponentInsufficient;
      expect(err.componentItemId, 11);
      expect(err.neededQty, 6);
      expect(err.availableQty, 5);
    });

    test('النقص بلا وصفة مرفوض — BundleSaleRecipeRequired', () {
      final outcome = planBundleSaleBreakdown(
        saleQtyBase: 5,
        bundleReadyQty: 2,
        bundleReadyValue: 20000,
        components: const [],
      );
      expect(outcome.errors, hasLength(1));
      expect(outcome.errors.single, isA<BundleSaleRecipeRequired>());
    });

    test('خدمة بلا تكلفة: بند بيعي ضمن السعر — صفر بالمركب (F-212)', () {
      final outcome = planBundleSaleBreakdown(
        saleQtyBase: 2,
        bundleReadyQty: 0,
        bundleReadyValue: 0,
        components: [
          BundleComponentStockInput(
            itemId: 11,
            isService: false,
            qtyPerBundle: 1,
            stockQty: 10,
            stockValue: 10000,
          ),
          const BundleComponentStockInput(
            itemId: 13,
            isService: true,
            qtyPerBundle: 1,
            serviceCostMinor: null,
          ),
        ],
      );
      expect(outcome.errors, isEmpty);
      expect(outcome.plan.serviceCostMinor, 0);
      expect(outcome.plan.compositeCostMinor, 2000);
    });

    test('ثبات F-178 بالمحاكاة: دلتا قيم الأرصدة تساوي التكلفة '
        'المخزنية المحمولة حرفاً', () {
      // محاكاة الرصيد قبل وبعد — مجموع قيم الأرصدة الثلاثة (الجاهز
      // ومكوّنا البضاعة) ينقص بمقدار inventoryCostMinor حرفاً،
      // والخدمة بلا رصيد بلا دلتا قيمة (F-212).
      final before = {11: (20, 200000), 12: (20, 40000), 99: (6, 60000)};
      final outcome = planBundleSaleBreakdown(
        saleQtyBase: 12,
        bundleReadyQty: 6,
        bundleReadyValue: 60000,
        components: exampleComponents(),
      );
      final after = Map<int, (int, int)>.from(before);
      void applyOut(int itemId, int qtyOut, int valueOut) {
        final (q, v) = after[itemId]!;
        after[itemId] = (q - qtyOut, v - valueOut);
      }

      applyOut(99, outcome.plan.readyQty, outcome.plan.readyValueMinor);
      for (final c in outcome.plan.components) {
        if (!c.isService) applyOut(c.itemId, c.qtyOut, c.valueMinor);
      }
      final sumBefore = before.values.fold(0, (s, b) => s + b.$2);
      final sumAfter = after.values.fold(0, (s, b) => s + b.$2);
      expect(sumBefore - sumAfter, outcome.plan.inventoryCostMinor);
      // الجاهز فرُغ قيمةً وكميةً (امتصاص الكل — D-067).
      expect(after[99], (0, 0));
      // وكميات الأرصدة سليمة: خشب 8 وحبل 14.
      expect(after[11]!.$1, 8);
      expect(after[12]!.$1, 14);
    });
  });

  group('أوصاف الأخطاء العربية', () {
    test('كل نوع خطأ يصف بنص غير فارغ', () {
      final errors = <BundleValidationError>[
        const BundleRecipeEmpty(),
        const BundleComponentQtyInvalid(0, 0),
        const BundleComponentDuplicate(1, 7),
        const BundleSelfComponent(0, 5),
        const BundleComponentCostInvalid(0, -1),
        const BundleComponentNotFound(0, 7),
        const BundleComponentInactive(0, 'خشب'),
        const BundleComponentIsBundle(0, 'سلّة'),
        const BundleOwnerNotFound(5),
        const BundleOwnerInactive('سلّة'),
        const BundleOwnerNotBundle('خشب'),
      ];
      for (final e in errors) {
        expect(describeBundleValidationError(e), isNotEmpty);
      }
    });

    test('الاستثناء يحمل الأخطاء كله بنصها', () {
      const ex = BundleValidationException([BundleRecipeEmpty()]);
      expect(ex.toString(), contains('الوصفة بلا مكونات'));
    });
  });
}
