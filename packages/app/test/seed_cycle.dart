import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// أرضية الأرقام المعروفة المشتركة لاختبارات واجهات دفعة (6-ب) — بنمط
/// reports_flow_test حرفاً: ضخ 500,000 فشراء 10×10,000 آجل فبيع
/// 6×15,000 آجل فقبض 50,000 بعطلة على فاتورة البيع فتسوية عجز 5,000.
///
/// النتائج المعروفة على هذه الدورة: الميزان 805,000/805,000 (الصندوق
/// 545,000 والعملاء 40,000 والمخزون 4×40,000) والذمم «هم يدينون» 40,000
/// و«نحن مدينون» 100,000 والحركة البيعية 6×90,000 والمشتريات 10×100,000.
///
/// ملاحظة بيئة اختبارات الواجهة: بلا استيراد drift هنا — القيم بالبحث
/// بـcustomSelect بلا متغيرات فتنظف حزمة الواجهة من اعتماد مباشر.
Future<int> seedKnownCycle(DiqqahDatabase db) async {
  final yearRows =
      await db.customSelect('SELECT name FROM fiscal_years').get();
  final year = int.parse(yearRows.single.data['name'] as String);
  final date = '$year-03-15';
  final unitId = await db.insertUnit(name: 'قطعة');
  final oilId = await db.insertItem(
      sku: 'Z-100',
      name: 'زيت محلي',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 25000,
      salePriceMinor: 40000,
      priceCurrencyId: 1);
  final customerId = await db.insertParty(
      number: '0001',
      name: 'عميل الأمل',
      kind: 'customer',
      defaultCurrencyId: 1);
  final supplierId = await db.insertParty(
      number: '0002',
      name: 'مورد الشرق',
      kind: 'supplier',
      defaultCurrencyId: 1);
  final boxId = (await db.customSelect(
    'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
  ).getSingle()).data['id'] as int;
  final warehouseId = (await db.customSelect(
    'SELECT id FROM warehouses ORDER BY id LIMIT 1',
  ).getSingle()).data['id'] as int;
  final capitalId = (await db.customSelect(
    "SELECT id FROM accounts WHERE code = '311'",
  ).getSingle()).data['id'] as int;

  // ضخ رأس المال 500,000 (سند قبض بغير طرف على 311)
  final capitalVoucher = await db.createVoucherDraft(VoucherDraft(
    kind: VoucherKind.receipt,
    dateText: date,
    directAccountId: capitalId,
    cashBoxId: boxId,
    amountDocMinor: 500000,
  ));
  await db.postVoucher(capitalVoucher);

  // شراء آجل 10×10,000 = 100,000 (113 مدين / 211 دائن)
  final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
    kind: InvoiceKind.purchase,
    dateText: date,
    partyId: supplierId,
    warehouseId: warehouseId,
    lines: [
      InvoiceLineDraft(
          itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 10000),
    ],
  ));
  await db.postInvoice(purchaseId);

  // بيع آجل 6×15,000 = 90,000 (112 مدين / 411 دائن + 51/113 بالتكلفة)
  final saleId = await db.createInvoiceDraft(InvoiceDraft(
    kind: InvoiceKind.sale,
    dateText: date,
    partyId: customerId,
    warehouseId: warehouseId,
    lines: [
      InvoiceLineDraft(
          itemId: oilId, unitId: unitId, qtyBase: 6, unitPriceMinor: 15000),
    ],
  ));
  await db.postInvoice(saleId);

  // قبض 50,000 بمطابقة على فاتورة البيع
  final receiptId = await db.createVoucherDraft(VoucherDraft(
    kind: VoucherKind.receipt,
    dateText: date,
    partyId: customerId,
    cashBoxId: boxId,
    amountDocMinor: 50000,
    allocations: [
      VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 50000),
    ],
  ));
  await db.postVoucher(receiptId);

  // عجز صندوق 5,000 على 57
  final adjustmentId = await db.createCashAdjustmentDraft(CashAdjustmentDraft(
    dateText: date,
    cashBoxId: boxId,
    direction: CashAdjustmentDirection.shortage,
    amountDocMinor: 5000,
    reason: 'فرق جرد يومي',
  ));
  await db.postCashAdjustment(adjustmentId);

  return year;
}
