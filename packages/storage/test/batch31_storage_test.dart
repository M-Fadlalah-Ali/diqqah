import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 31 (ثامنة م2) — ربط المخزون بالدفتر: تقرير مطابقة
/// دفتر المخزون (07 §3.1/D-012/D-067/F-178).
///
/// القاعدة `inMemory` والترحيل عبر المحرك الموحد حصراً (نمط
/// invoice_flow_test): شراء ثم بيع آجل ثم إذن إخراج — كل حركة قيمة
/// تمر بقيدها المربوط بحركاته فثابت المطابقة يثبت بالأرقام على كل
/// صنف وعلى الإجمالي بعد كل خطوة.
void main() {
  late DiqqahDatabase db;
  late int unitId;
  late int itemId;
  late int warehouseId;
  late int supplierId;
  late int customerId;
  late String date;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    unitId = await db.insertUnit(name: 'قطعة');
    itemId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1);
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    supplierId = await db.insertParty(
        number: '0001', name: 'مورد الشرق', kind: 'supplier',
        defaultCurrencyId: 1);
    customerId = await db.insertParty(
        number: '0002', name: 'عميل الأمل', kind: 'customer',
        defaultCurrencyId: 1);
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    date = '${int.parse(yearRows.single.data['name'] as String)}-03-15';
  });

  tearDown(() => db.close);

  Future<int> postPurchase(int qty, int price) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: qty,
            unitPriceMinor: price),
      ],
    ));
    return db.postInvoice(id);
  }

  Future<int> postCreditSale(int qty) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: qty,
            unitPriceMinor: 2000),
      ],
    ));
    return db.postInvoice(id);
  }

  test('الدورة الكاملة متطابقة: شراء 5×1,000 فبيع 2 فإخراج 1 — القيود '
      'المربوطة والحركات متساويان لكل صنف والإجمالي بعد كل خطوة (F-178)',
      () async {
    await postPurchase(5, 1000);

    // بعد الشراء: 113 مدين 5,000 والحركات 5,000 — ومطابقة صحيحة.
    var report = await db.inventoryLedgerReconciliation();
    expect(report.rows, hasLength(1));
    expect(report.rows.single.ledgerValueMinor, 5000);
    expect(report.rows.single.stockValueMinor, 5000);
    expect(report.isMatched, isTrue);
    expect(report.driftMinor, 0);

    // البيع الآجل: تكلفة الخروج بالمتوسط 1,000 × 2 — 113 دائن 2,000
    // والحركات 3,000 — والمطابقة باقية.
    await postCreditSale(2);
    report = await db.inventoryLedgerReconciliation();
    expect(report.rows.single.ledgerValueMinor, 3000);
    expect(report.rows.single.stockValueMinor, 3000);
    expect(report.isMatched, isTrue);

    // إذن الإخراج بالامتصاص (سببه الإلزامي والمقابل الافتراضي 596):
    // 113 دائن 1,000 والحركات 2,000 — والثابت باقياً حرفاً.
    final lossAccountId = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '596'",
    ).getSingle()).data['id'] as int;
    await db.stockIssuePost(StockIssueDraft(
      dateText: date,
      warehouseId: warehouseId,
      reason: 'استهلاك داخلي',
      counterAccountId: lossAccountId,
      lines: [
        StockDocLineDraft(
            itemId: itemId, qtyBase: 1),
      ],
    ));
    report = await db.inventoryLedgerReconciliation();
    expect(report.rows.single.ledgerValueMinor, 2000);
    expect(report.rows.single.stockValueMinor, 2000);
    expect(report.isMatched, isTrue);
    expect(report.rows.single.sku, 'Z-100');
  });

  test('الصنف الخدمي بلا حركة لا صف له بالمطابقة — والبضاعة وحدها تظهر',
      () async {
    await db.insertItem(
        sku: 'S-1',
        name: 'خدمة تركيب',
        kind: 'service',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 5000,
        priceCurrencyId: 1);
    await postPurchase(5, 1000);

    final report = await db.inventoryLedgerReconciliation();
    expect(report.rows, hasLength(1),
        reason: 'الخدمة بلا مخزون ولا قيد مخزون فلا طرف لها أصلاً');
    expect(report.rows.single.sku, 'Z-100');
    expect(report.isMatched, isTrue);
  });

  test('قاعدة خام بلا حركات: التقرير فارغاً متطابقاً بلا استثناء', () async {
    final report = await db.inventoryLedgerReconciliation();
    expect(report.rows, isEmpty);
    expect(report.isMatched, isTrue);
    expect(report.ledgerTotalMinor, 0);
    expect(report.stockTotalMinor, 0);
  });
}
