import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات مجال الجرد وتسوياته — س-19/F-046 (المرحلة 2، دفعة 25).
///
/// الفحص البنيوي خالص حصراً — لا قاعدة ولا واجهة: تاريخ ميلاد ISO،
/// ومستودع معرف، ونطاق وصافٌه بتصنيفه، وعدّة صفر أو أكثر (الصفر «الرف
/// فارغ» شرعي)، وصنف مكتشف بعدّة موجبة. فحوص القاعدة (الوجود والتفعيل
/// والبضاعة والنطاق والجلسة الجارية السابقة) بكمّن التخزين ولا تُختبر
/// هنا كي لا يكذب الاختبار عن ما لا يمتلكه.
void main() {
  StockCountStartDraft draft({
    int warehouse = 1,
    String date = '2026-11-04',
    StockCountScope scope = StockCountScope.all,
    String? category,
  }) =>
      StockCountStartDraft(
        dateText: date,
        warehouseId: warehouse,
        scope: scope,
        scopeCategory: category,
      );

  group('validateStockCountStartStructure — افتتاح الجلسة (س-19)', () {
    test('التاريخ بغير صورة الميلاد ISO مرفوض', () {
      for (final bad in ['2026/11/04', '04-11-2026', 'هجري', '2026-13-01']) {
        final errors = validateStockCountStartStructure(draft(date: bad));
        expect(errors.whereType<StockCountDateInvalid>(), isNotEmpty,
            reason: 'التاريخ «$bad» كان يجب أن يرفض');
      }
      expect(
        describeStockCountValidationError(
            validateStockCountStartStructure(draft(date: 'x')).first),
        contains('YYYY-MM-DD'),
      );
    });

    test('مستودع بلا معرف مرفوض', () {
      final errors = validateStockCountStartStructure(draft(warehouse: 0));
      expect(errors.whereType<StockCountWarehouseMissing>(), isNotEmpty);
    });

    test('نطاق المجموعة بلا تصنيف مرفوض — والنطاق الكل يحتمل غيابه',
        () {
      final errors = validateStockCountStartStructure(
          draft(scope: StockCountScope.group));
      expect(errors.whereType<StockCountScopeCategoryMissing>(), isNotEmpty);
      // التصنيف الفراغي المحيط يرفض كذلك
      expect(
        validateStockCountStartStructure(draft(
                scope: StockCountScope.group, category: '   '))
            .whereType<StockCountScopeCategoryMissing>(),
        isNotEmpty,
      );
      expect(
        validateStockCountStartStructure(draft())
            .whereType<StockCountScopeCategoryMissing>(),
        isEmpty,
      );
    });

    test('لسان النطاق سجل واحد — «كل الأصناف» و«مجموعة تصنيف»', () {
      expect(stockCountScopeLabel(StockCountScope.all), 'كل الأصناف');
      expect(stockCountScopeLabel(StockCountScope.group), 'مجموعة تصنيف');
    });
  });

  group('validateStockCountCounts — العدّة صفر أو أكثر (الصفر شرعي)', () {
    test('العدّة السالبة مرفوضة والصفر والموجب يمران', () {
      final errors = validateStockCountCounts({1: -3});
      expect(errors.whereType<StockCountCountedInvalid>(), isNotEmpty);
      expect(
        describeStockCountValidationError(errors.first),
        contains('الرف فارغ'),
      );
      expect(validateStockCountCounts({1: 0, 2: 5}), isEmpty,
          reason: 'الصفر عدّ شرعي لا يرفض — العجز الكامل مسموح');
    });

    test('سطر الصنف المكتشف بعدّة موجبة حصراً — وجوده يعني عدّه', () {
      expect(
        validateStockCountFoundLine(
            const StockCountLineDraft(itemId: 9, countedQtyBase: 0)),
        isNotEmpty,
        reason: 'صنف وجدناه بعدّة صفر لا معنى لإضافته',
      );
      expect(
        validateStockCountFoundLine(
            const StockCountLineDraft(itemId: 9, countedQtyBase: 4)),
        isEmpty,
      );
    });
  });

  group('سجل الرسائل العربية الواحد — نمط التحول النقدي', () {
    test('كل نوع خطأ يوصف من السجل لا من الواجهة', () {
      final samples = <StockCountValidationError>[
        const StockCountOpenSessionExists('المستودع الرئيسي'),
        const StockCountLineNotCounted('زيت محلي (Z-100)', 0),
        const StockCountItemOutsideScope(
            itemLabel: 'أرز فاخر (R-200)',
            scopeCategory: 'زيوت',
            lineIndex: 0),
        const StockCountAlreadyPosted(),
        const StockCountNotFound(7),
        const StockCountNoLines(),
      ];
      for (final s in samples) {
        expect(describeStockCountValidationError(s), isNotEmpty);
      }
      expect(
        describeStockCountValidationError(
            const StockCountOpenSessionExists('المستودع الرئيسي')),
        contains('جلسة جرد جارٍ'),
      );
      expect(
        describeStockCountValidationError(const StockCountLineNotCounted(
            'زيت محلي (Z-100)', 0)),
        contains('لا تسوية جزئية'),
      );
      expect(
        firstStockCountError([
          const StockCountLineNotCounted('زيت (Z-1)', 0),
          const StockCountAlreadyPosted(),
        ]),
        contains('زيت (Z-1)'),
        reason: 'العرض بأول خطأ حصراً',
      );
      expect(firstStockCountError(const []), 'لا خطأ');
    });
  });
}
