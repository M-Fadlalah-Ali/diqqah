import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات مجال التحويل بين المستودعات وفحص أسماء المستودعات —
/// س-18 (المرحلة 2، دفعة 24).
///
/// الفحص البنيوي خالص حصراً — لا قاعدة ولا واجهة: نفس المستودع على
/// الطرفين، ولا أسطر، وكمية موجبة بالوحدة الأساسية، وصنف واحد سطراً
/// واحداً، وتاريخ ميلاد ISO. فحوص القاعدة (الوجود والتفعيل والبضاعة
/// والاكتفاء) بكمّن التخزين ولا تُختبر هنا كي لا يكذب الاختبار عن
/// ما لا يمتلكه.
void main() {
  StockTransferDraft draft({
    int? from,
    int? to,
    String date = '2026-11-04',
    List<TransferLineDraft> lines = const [],
  }) =>
      StockTransferDraft(
        dateText: date,
        fromWarehouseId: from ?? 1,
        toWarehouseId: to ?? 2,
        lines: lines,
      );

  group('validateStockTransferStructure — الرفض قبل الكتابة (س-18)', () {
    test('نفس المستودع على الطرفين مرفوض', () {
      final errors =
          validateStockTransferStructure(draft(from: 3, to: 3));
      expect(errors.whereType<StockTransferSameWarehouse>(), isNotEmpty);
      expect(
        describeStockTransferValidationError(errors.first),
        contains('مستودعان مختلفان'),
      );
    });

    test('التحويل بلا أسطر مرفوض — لا تحويل فارغ', () {
      final errors = validateStockTransferStructure(draft());
      expect(errors.whereType<StockTransferNoLines>(), isNotEmpty);
    });

    test('كمية صفر أو سالبة مرفوضة بالسطر — الوحدة الأساسية موجبة', () {
      final errors = validateStockTransferStructure(draft(lines: [
        const TransferLineDraft(itemId: 1, qtyBase: 0),
        const TransferLineDraft(itemId: 2, qtyBase: -5),
      ]));
      final qtyErrors = errors.whereType<StockTransferQtyInvalid>().toList();
      expect(qtyErrors.length, 2);
      expect(qtyErrors.first.lineIndex, 0);
      expect(qtyErrors.last.lineIndex, 1);
    });

    test('تكرار الصنف مرفوض — الصنف الواحد سطراً واحداً', () {
      final errors = validateStockTransferStructure(draft(lines: [
        const TransferLineDraft(itemId: 7, qtyBase: 3),
        const TransferLineDraft(itemId: 7, qtyBase: 2),
      ]));
      expect(errors.whereType<StockTransferItemDuplicated>(), isNotEmpty);
    });

    test('التاريخ الفاسد مرفوض بلا اختراع (D-077)', () {
      for (final bad in ['2026-13-01', '04-11-2026', 'بلا تاريخ', '']) {
        final errors = validateStockTransferStructure(draft(date: bad));
        expect(errors.whereType<StockTransferDateInvalid>(), isNotEmpty,
            reason: 'التاريخ «$bad» يرفض');
      }
    });

    test('التحويل السليم يمر بلا أخطاء', () {
      final errors = validateStockTransferStructure(draft(lines: [
        const TransferLineDraft(itemId: 1, qtyBase: 5),
        const TransferLineDraft(itemId: 2, qtyBase: 1),
      ]));
      expect(errors, isEmpty);
    });

    test('سجل الرسائل عربي مفهوم لكل نوع', () {
      expect(
        describeStockTransferValidationError(const StockTransferNoLines()),
        contains('لا صنف'),
      );
      expect(
        describeStockTransferValidationError(
            const StockTransferQtyInvalid(0)),
        contains('موجبة'),
      );
      expect(
        describeStockTransferValidationError(
            const StockTransferItemDuplicated(1)),
        contains('سطراً واحداً'),
      );
      expect(
        describeStockTransferValidationError(const StockTransferSameWarehouse()),
        contains('نفسه'),
      );
      expect(
        describeStockTransferValidationError(
            const StockTransferDateInvalid('x')),
        contains('YYYY-MM-DD'),
      );
      expect(
        describeStockTransferValidationError(
            const StockTransferItemNotGood('زيت محلي (Z-100)', 0)),
        contains('بضاعة حصراً'),
      );
      expect(
        describeStockTransferValidationError(
            const StockTransferStockInsufficient(
                itemLabel: 'زيت محلي (Z-100)',
                onHandQty: 3,
                requestedQty: 5,
                lineIndex: 0)),
        contains('منع السالب'),
      );
    });
  });

  group('warehouseNameError — فحص اسم المستودع الخالص', () {
    test('الفارغ أو الفراغ المحيط مرفوض', () {
      expect(warehouseNameError(''), isNotNull);
      expect(warehouseNameError('   '), isNotNull);
    });

    test('الطويل عن الحد مرفوض والقصير يمر', () {
      expect(warehouseNameError('م' * 61), isNotNull);
      expect(warehouseNameError('مستودع الفرع'), isNull);
    });
  });
}
