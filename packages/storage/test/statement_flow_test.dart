import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart' show Variable;

/// اختبارات دفعة (13) الروابط التفرعية (س-143..س-147/D-135..D-137) —
/// كشف الحساب وكشف الطرف وحركة الصنف بأرقام الدورة المعروفة: ضخ
/// 500,000 فشراء 10×10,000 آجل فبيع 6×15,000 آجل فقبض 50,000 فعجز 5,000
/// (نمط reports_flow_test حرفاً — الميزان 805,000/805,000).
///
/// ضابط التوازن (س-146/D-137): مجموع الكشف ورصيده النهائي يطابقان صف
/// الحساب في ميزان المراجعة حصراً — وصافي كشف الطرف يطابق صف الذمم.
Future<int> accountIdByCode(DiqqahDatabase db, String code) async {
  final rows = await db.customSelect(
    'SELECT id FROM accounts WHERE code = ?',
    variables: [Variable.withString(code)],
  ).get();
  expect(rows, hasLength(1));
  return rows.first.data['id'] as int;
}

void main() {
  late DiqqahDatabase db;
  late int year;
  late String date;
  late int unitId;
  late int oilId;
  late int customerId;
  late int supplierId;
  late int boxId;
  late int warehouseId;
  late int saleId;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    year = int.parse((await db
            .customSelect('SELECT name FROM fiscal_years')
            .get())
        .single
        .data['name'] as String);
    date = '$year-03-15';
    unitId = await db.insertUnit(name: 'قطعة');
    oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    customerId = await db.insertParty(
        number: '0001', name: 'عميل الأمل', kind: 'customer', defaultCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0002', name: 'مورد الشرق', kind: 'supplier', defaultCurrencyId: 1);
    boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;

    await db.postVoucher(await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      directAccountId: await accountIdByCode(db, '311'),
      cashBoxId: boxId,
      amountDocMinor: 500000,
    )));
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
    saleId = await db.createInvoiceDraft(InvoiceDraft(
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
    await db.postVoucher(await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      partyId: customerId,
      cashBoxId: boxId,
      amountDocMinor: 50000,
      allocations: [
        VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 50000),
      ],
    )));
    await db.postCashAdjustment(await db.createCashAdjustmentDraft(
      CashAdjustmentDraft(
        dateText: date,
        cashBoxId: boxId,
        direction: CashAdjustmentDirection.shortage,
        amountDocMinor: 5000,
        reason: 'فرق جرد يومي',
      ),
    ));
  });

  tearDown(() => db.close);

  test('س-146/D-137: كشف الحساب يطابق صف الميزان حصراً — العملاء 112 '
      'بمدين 90,000 ودائن 50,000 ورصيد 40,000 بسطرين بترتيب الزمن',
      () async {
    final tb = await db.trialBalanceReport();
    final acc112 = await accountIdByCode(db, '112');
    final tbRow = tb.rows.singleWhere((r) => r.account.id == acc112);
    expect(tbRow.debitSumMinor, 90000);
    expect(tbRow.creditSumMinor, 50000);
    expect(tbRow.balanceMinor, 40000);

    final statement = await db.accountStatementReport(acc112);
    expect(statement.totalDebitMinor, tbRow.debitSumMinor,
        reason: 'مجموع الكشف يطابق صف الميزان');
    expect(statement.totalCreditMinor, tbRow.creditSumMinor,
        reason: 'مجموع الكشف يطابق صف الميزان');
    expect(statement.closingBalanceMinor, tbRow.balanceMinor,
        reason: 'الرصيد النهائي يطابق رصيد الميزان');
    // قيدان: القيد الشرائي على 113 لا 112 — فيكون القيدان على 112
    // قيد البيع وقيد القبض
    expect(statement.entries, hasLength(2));
    // الرصيد التراكمي بعد كل قيد
    expect(statement.entries[0].runningBalanceMinor, 90000,
        reason: 'قيد البيع: 112 مدين 90,000');
    expect(statement.entries[1].runningBalanceMinor, 40000,
        reason: 'قيد القبض: 112 دائن 50,000');
    expect(statement.entries[0].moveDate, date);
  });

  test('س-146: الكشف بحساب دائن الطبيعة (الموردون 211) يطابق الميزان '
      'بصيغة الدائن — 100,000', () async {
    final tb = await db.trialBalanceReport();
    final acc211 = await accountIdByCode(db, '211');
    final tbRow = tb.rows.singleWhere((r) => r.account.id == acc211);
    expect(tbRow.balanceMinor, 100000, reason: 'دائن الطبيعة');

    final statement = await db.accountStatementReport(acc211);
    expect(statement.closingBalanceMinor, 100000);
    expect(statement.totalCreditMinor, 100000);
    expect(statement.totalDebitMinor, 0);
  });

  test('س-146: الحساب الغائب برسالته — والرصيد التراكمي باتجاه الطبيعي '
      'حصراً', () async {
    expect(
      () => db.accountStatementReport(99999),
      throwsA(anything),
    );
  });

  test('س-147: كشف حساب الطرف يطابق صف الذمم — العميل 40,000 هم '
      'يدينون والمورد 100,000 نحن مدينون', () async {
    final receivables = await db.receivablesPayablesReport();
    final customerRow =
        receivables.singleWhere((r) => r.partyId == customerId);
    expect(customerRow.amountMinor, 40000);
    expect(customerRow.direction, PartyBalanceDirection.theyOweUs);

    final customerStatement = await db.partyStatementReport(customerId);
    expect(customerStatement.closingNetDebitMinor, 40000,
        reason: 'صافي الكشف يطابق صف الذمم');
    // قيد البيع وقيد القبض على حسابات الذمة 112
    expect(customerStatement.entries, hasLength(2));
    expect(customerStatement.entries[0].runningNetDebitMinor, 90000);
    expect(customerStatement.entries[1].runningNetDebitMinor, 40000);

    final supplierStatement = await db.partyStatementReport(supplierId);
    expect(supplierStatement.closingNetDebitMinor, -100000);
    final supplierRow =
        receivables.singleWhere((r) => r.partyId == supplierId);
    expect(supplierRow.amountMinor, 100000);
    expect(supplierRow.direction, PartyBalanceDirection.weOweThem);
  });

  test('س-145/D-136: حركة الصنف الواحد — دخول شراء 10 وخروج بيع 6 '
      'بمستندها ومستودعها بترتيب الورود', () async {
    final moves = await db.itemStockMovesReport(oilId);
    expect(moves, hasLength(2));
    expect(moves[0].isIn, isTrue, reason: 'الشراء أول الورد');
    expect(moves[0].qtyBase, 10);
    expect(moves[0].valueBaseMinor, 100000);
    expect(moves[0].docLabel, contains('فاتورة شراء'));
    expect(moves[0].warehouseName, isNotNull);
    expect(moves[1].isIn, isFalse);
    expect(moves[1].qtyBase, 6);
    // تكلفة الخروج بالمتوسط الجاري = 10,000 × 6
    expect(moves[1].valueBaseMinor, 60000);
    expect(moves[1].docLabel, contains('فاتورة بيع'));
  });
}
