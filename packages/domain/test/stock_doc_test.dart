import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات مجال إذني المخزون (F-209/F-210 — الدفعة 26 أولى م2 س85).
///
/// الفحص البنيوي الخالص حصراً هنا — لا قاعدة ولا واجهة (نمط التحويل
/// والجرد). الحدود الموثقة: السبب النصي إلزامي، الأسطر بضاعة كمية موجبة
/// بلا تكرار، المقابل معرف موجب، التاريخ ISO ميلادي حصراً (D-077).
void main() {
  final lines = [
    StockDocLineDraft(itemId: 1, qtyBase: 5),
    StockDocLineDraft(itemId: 2, qtyBase: 3),
  ];

  StockReceiptDraft receipt({
    String dateText = '2026-03-15',
    int warehouseId = 1,
    String reason = 'هدية مورد',
    int counterAccountId = 99,
    List<StockDocLineDraft>? lines_,
  }) =>
      StockReceiptDraft(
        dateText: dateText,
        warehouseId: warehouseId,
        reason: reason,
        counterAccountId: counterAccountId,
        lines: lines_ ?? lines,
      );

  StockIssueDraft issue({
    String dateText = '2026-03-15',
    int warehouseId = 1,
    String reason = 'تالف',
    int counterAccountId = 98,
    List<StockDocLineDraft>? lines_,
  }) =>
      StockIssueDraft(
        dateText: dateText,
        warehouseId: warehouseId,
        reason: reason,
        counterAccountId: counterAccountId,
        lines: lines_ ?? lines,
      );

  group('إذن الإدخال — الفحص البنيوي (F-209)', () {
    test('مسودة سليمة تمر بلا أخطاء', () {
      expect(validateStockReceiptStructure(receipt()), isEmpty);
    });

    test('السبب النصي إلزامي — الفارغ والأبياض مرفوضان', () {
      final errors = validateStockReceiptStructure(receipt(reason: '   '));
      expect(errors, hasLength(1));
      expect(errors.single, isA<StockDocReasonEmpty>());
      expect(
        describeStockDocValidationError(errors.single),
        contains('سبب إذن الإدخال إلزامي'),
      );
    });

    test('التاريخ غير الصالح مرفوض — ميلادي ISO حصراً (D-077)', () {
      final errors = validateStockReceiptStructure(
          receipt(dateText: '15/03/2026'));
      expect(errors.single, isA<StockDocDateInvalid>());
    });

    test('بلا أسطر مرفوض', () {
      final errors = validateStockReceiptStructure(receipt(lines_: []));
      expect(errors.single, isA<StockDocNoLines>());
    });

    test('كمية غير موجبة مرفوضة بمؤشر سطرها', () {
      final errors = validateStockReceiptStructure(receipt(lines_: [
        StockDocLineDraft(itemId: 1, qtyBase: 0),
      ]));
      expect(errors.single, isA<StockDocQtyInvalid>());
      expect((errors.single as StockDocQtyInvalid).lineIndex, 0);
    });

    test('الصنف المكرر مرفوض — الصنف الواحد سطراً واحداً (نمط س-18)', () {
      final errors = validateStockReceiptStructure(receipt(lines_: [
        StockDocLineDraft(itemId: 7, qtyBase: 1),
        StockDocLineDraft(itemId: 7, qtyBase: 2),
      ]));
      expect(errors.single, isA<StockDocItemDuplicated>());
    });

    test('معرف المقابل غير الموجب مرفوض — من الحسابات المفعلة حصراً', () {
      final errors = validateStockReceiptStructure(
          receipt(counterAccountId: 0));
      expect(errors.single, isA<StockDocCounterAccountInvalid>());
    });
  });

  group('إذن الإخراج — الفحص البنيوي (F-210)', () {
    test('مسودة سليمة تمر بلا أخطاء', () {
      expect(validateStockIssueStructure(issue()), isEmpty);
    });

    test('السبب النصي إلزامي برسالة الإخراج', () {
      final errors = validateStockIssueStructure(issue(reason: ''));
      expect(errors.single, isA<StockDocReasonEmpty>());
      expect(
        describeStockDocValidationError(errors.single),
        contains('سبب إذن الإخراج إلزامي'),
      );
    });

    test('التاريخ والأسطر والمقابل بنفس قواعد الإدخال', () {
      expect(
        validateStockIssueStructure(issue(
            dateText: 'bad', lines_: [], counterAccountId: -1)),
        hasLength(3),
      );
    });

    test('منع السالب رسالة المحرك تسمي الإذن والرصيدين (F-042)', () {
      final error = StockDocStockInsufficient(
        itemLabel: 'زيت محلي (Z-100)',
        onHandQty: 2,
        requestedQty: 5,
        lineIndex: 0,
        direction: 'issue',
      );
      final text = describeStockDocValidationError(error);
      expect(text, contains('بالمستودع 2 والمطلوب إخراجه 5'));
      expect(text, contains('منع السالب (F-042)'));
    });
  });

  group('سجل الرسائل الواحد', () {
    test('الاستثناء يحمل القائمة ويصف أول خطأ حصراً (نمط س-36)', () {
      final errors = validateStockReceiptStructure(
          receipt(dateText: 'x', reason: '', lines_: []));
      final ex = StockDocValidationException(errors);
      expect(ex.toString(), startsWith('رفض مدقق إذن المخزون'));
      expect(firstStockDocError(errors),
          contains('تاريخ إذن الإدخال «x» ليس بتاريخ صالح'));
    });

    test('القائمة الفارغة لا خطأ فيها', () {
      expect(firstStockDocError(const []), 'لا خطأ');
    });
  });
}
