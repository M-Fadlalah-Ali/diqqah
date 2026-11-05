import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart' show Variable;

/// الصيغة الجديدة D-169 (سنة رقمين + عدّاد مبطن) — مشتقة من سنة البذرة.
String seqNum(int year, int n, [int w = 6]) =>
    '${(year % 100).toString().padLeft(2, '0')}${n.toString().padLeft(w, '0')}';

/// أدوات الدفعة — بنمط invoice_flow_test: معرفات بالبحث بالكود لا
/// بالثبوت الأعمى، وسنة ديناميكية من البذر.
Future<int> accountIdByCode(DiqqahDatabase db, String code) async {
  final rows = await db.customSelect(
    'SELECT id FROM accounts WHERE code = ?',
    variables: [Variable.withString(code)],
  ).get();
  expect(rows, hasLength(1), reason: 'كود الدليل $code فريد من البذر');
  return rows.first.data['id'] as int;
}

Future<int> seededYear(DiqqahDatabase db) async {
  final rows =
      await db.customSelect('SELECT name, state FROM fiscal_years').get();
  expect(rows, hasLength(1));
  expect(rows.first.data['state'], 'open');
  return int.parse(rows.first.data['name'] as String);
}

Future<List<Map<String, Object?>>> moveLinesOf(
    DiqqahDatabase db, int moveId) async {
  final rows = await db.customSelect(
    'SELECT account_id, debit_minor, credit_minor, party_id, currency_id, '
    'amount_minor, fx_rate FROM move_lines WHERE move_id = ? ORDER BY id',
    variables: [Variable.withInt(moveId)],
  ).get();
  return [for (final r in rows) r.data];
}

/// أرضية كل اختبار: وحدة وصنف وعميل ومورد والمستودع والصندوق المزروعان
/// (س-51) — وأموال ضُخّت بضخ رأس مال (س-66) كي يصح الصرف والتحويل بعدها.
class Fixture {
  final DiqqahDatabase db;
  final int year;
  final String date;
  final int unitId;
  final int oilId;
  final int customerId;
  final int supplierId;
  final int boxId;
  final int warehouseId;

  Fixture({
    required this.db,
    required this.year,
    required this.date,
    required this.unitId,
    required this.oilId,
    required this.customerId,
    required this.supplierId,
    required this.boxId,
    required this.warehouseId,
  });

  InvoiceLineDraft line(int itemId, int qty, int price) => InvoiceLineDraft(
      itemId: itemId, unitId: unitId, qtyBase: qty, unitPriceMinor: price);

  /// ضخ رأس مال (س-66) — تمويل الصندوق قبل أي صرف أو تحويل.
  Future<int> capitalInjection(int amount) async {
    final id = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      directAccountId: await accountIdByCode(db, '311'),
      cashBoxId: boxId,
      amountDocMinor: amount,
    ));
    await db.postVoucher(id);
    return id;
  }

  /// شراء آجل (س-04)
  Future<int> purchaseCredit({required List<InvoiceLineDraft> lines}) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
  }

  /// بيع آجل (س-07)
  Future<int> saleCredit({required List<InvoiceLineDraft> lines}) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
  }

  /// سند قبض طرفي بمطابقاته (س-63)
  Future<int> receiptFromCustomer({
    required int amount,
    List<VoucherAllocationDraft> allocations = const [],
    int currencyId = 1,
    int fxRate = baseCurrencyFxRate,
    int? boxId,
  }) async {
    final id = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      partyId: customerId,
      cashBoxId: boxId ?? this.boxId,
      currencyId: currencyId,
      fxRate: fxRate,
      amountDocMinor: amount,
      allocations: allocations,
    ));
    await db.postVoucher(id);
    return id;
  }

  /// سند صرف طرفي بمطابقاته (س-65)
  Future<int> paymentToSupplier({
    required int amount,
    List<VoucherAllocationDraft> allocations = const [],
  }) async {
    final id = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.payment,
      dateText: date,
      partyId: supplierId,
      cashBoxId: boxId,
      amountDocMinor: amount,
      allocations: allocations,
    ));
    await db.postVoucher(id);
    return id;
  }
}

Future<Fixture> buildFixture(DiqqahDatabase db, {bool funded = true}) async {
  final year = await seededYear(db);
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
      number: '0001', name: 'عميل الأمل', kind: 'customer', defaultCurrencyId: 1);
  final supplierId = await db.insertParty(
      number: '0002', name: 'مورد الشرق', kind: 'supplier', defaultCurrencyId: 1);
  final boxId = (await db.customSelect(
    'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
  ).getSingle()).data['id'] as int;
  final warehouseId = (await db.customSelect(
    'SELECT id FROM warehouses ORDER BY id LIMIT 1',
  ).getSingle()).data['id'] as int;
  final f = Fixture(
    db: db,
    year: year,
    date: date,
    unitId: unitId,
    oilId: oilId,
    customerId: customerId,
    supplierId: supplierId,
    boxId: boxId,
    warehouseId: warehouseId,
  );
  if (funded) {
    await f.capitalInjection(500000);
  }
  return f;
}

void main() {
  late DiqqahDatabase db;

  setUp(() {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('س-61 بذر v8: الجداول الأربعة وحسابا فروق العملة صارا مفعّلين',
      () async {
    expect(db.schemaVersion, 19);
    for (final table in const [
      'vouchers',
      'voucher_allocations',
      'box_transfers',
      'cash_adjustments',
    ]) {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      ).get();
      expect(rows, hasLength(1), reason: 'جدول $table مبني في v8');
    }
    for (final code in const ['44', '55']) {
      final rows = await db.customSelect(
        'SELECT is_active FROM accounts WHERE code = ?',
        variables: [Variable.withString(code)],
      ).getSingle();
      expect(rows.data['is_active'], 1,
          reason: 'حساب فروق العملة $code فُعِّل إعداداً (F-123/D-085 معروضان)');
    }
    // وحاجز سالب الصندوق موسَّع حياً في القاعدة
    final boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    await expectLater(
      db.customStatement(
        "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
        "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, uuid) "
        "VALUES (?, 'transfer_out', 1000, 1000, 1000000, 'x', 1, 'g')",
        [boxId],
      ),
      throwsA(anything),
    );
  });

  test('س-62 صندوق جديد بحسابه الورقي 1112 والفاتورة النقدية الدولارية تعمل',
      () async {
    final f = await buildFixture(db, funded: false);
    final usdBoxId = await db.createCashBox(name: 'صندوق الدولار', currencyId: 2);
    final usdBox = (await db.cashBoxById(usdBoxId))!;
    expect(usdBox.name, 'صندوق الدولار');
    expect(usdBox.currencyId, 2);
    expect(usdBox.accountId, await accountIdByCode(db, '1112'),
        reason: 'الصندوق الجديد يولّد حسابه الورقي التالي 1112 (03 §3/D-086 معروض)');
    final secondBoxId =
        await db.createCashBox(name: 'صندوق الفرع', currencyId: 1);
    expect((await db.cashBoxById(secondBoxId))!.accountId,
        await accountIdByCode(db, '1113'));
    expect(
        db.createCashBox(name: 'صندوق الدولار', currencyId: 1),
        throwsA(anything),
        reason: 'الاسم مستخدم سلفاً');
    // تعطيل آمن: الصندوق الجديد صفر الرصيد فيعطل حسابه ويختفي من القيد
    await db.disableCashBox(secondBoxId);
    final accRows = await db.customSelect(
      'SELECT is_active FROM accounts WHERE id = ?',
      variables: [Variable.withInt((await db.cashBoxById(secondBoxId))!.accountId)],
    ).getSingle();
    expect(accRows.data['is_active'], 0);

    // شراء تمويني بالليرة كي يصح البيع على رصيد (F-042) — بلا مساس بالصندوق
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    // الفاتورة النقدية بالدولار (المؤجلة من دفعة 4 — إفصاح س32) تعمل
    // الآن فوق صندوقها الدولاري: 100.00 دولار بلقطة 15,000
    final saleId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: f.date,
      cashBoxId: usdBoxId,
      warehouseId: f.warehouseId,
      currencyId: 2,
      fxRate: 15000 * fxRateScale,
      lines: [f.line(f.oilId, 1, 10000)],
    ));
    await db.postInvoice(saleId);
    final sale = (await db.invoiceById(saleId))!;
    expect(sale.state, 'paid', reason: 'النقدية مدفوعة فوراً (س-03/س-06)');
    expect(sale.totalDocMinor, 10000);
    expect(sale.totalBaseMinor, 150000000,
        reason: '100.00 دولار × 15,000 = 1,500,000 ليرة');
    expect(await db.cashBoxBalanceOf(usdBoxId), 150000000);
  });

  test('س-63 سند قبض من عميل: توزيع بالأقدمية وقيد 1111/112 وحالة جزئية',
      () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final saleId = await f.saleCredit(lines: [f.line(f.oilId, 4, 40000)]);

    // التوزيع الآلي بالأقدمية يقترح الفاتورة الوحيدة بمتبقيها
    final proposal = await db.proposeVoucherAllocations(
        kind: VoucherKind.receipt,
        partyId: f.customerId,
        currencyId: 1,
        amountDocMinor: 100000);
    expect(proposal, hasLength(1));
    expect(proposal.single.invoiceId, saleId);
    expect(proposal.single.appliedDocMinor, 100000);

    final voucherId = await f.receiptFromCustomer(
        amount: 100000,
        allocations: [VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 100000)]);
    final voucher = (await db.voucherById(voucherId))!;
    expect(voucher.state, 'posted');
    expect(voucher.number, '${seqNum(f.year, 2)}',
        reason: 'سند القبض الثاني — ضخ رأس المال الأول');
    expect(voucherDisplayLabel(voucher), 'سند قبض ${seqNum(f.year, 2)}');
    expect(voucher.moveId, isNotNull);

    // القيد: 1111 مدين 100,000 / 112 دائن 100,000 بحمولة الطرف ولقطة
    // الفاتورة (1,000,000 للأساسية) — من دفتر النقدية بنوع move_cash
    final lines = await moveLinesOf(db, voucher.moveId!);
    expect(lines, hasLength(2));
    final boxAcc = await accountIdByCode(db, '1111');
    final acc112 = await accountIdByCode(db, '112');
    expect(lines[0]['account_id'], boxAcc);
    expect(lines[0]['debit_minor'], 100000);
    expect(lines[1]['account_id'], acc112);
    expect(lines[1]['credit_minor'], 100000);
    expect(lines[1]['party_id'], f.customerId);
    expect(lines[1]['currency_id'], 1);
    expect(lines[1]['fx_rate'], fxRateScale);

    // صف المطابقة بمكافئه بلقطة الفاتورة (آخر ما يغطيها يمتص الفارق)
    final allocs = await db.voucherAllocationsOf(voucherId);
    expect(allocs.single.appliedDocMinor, 100000);
    expect(allocs.single.appliedBaseMinor, 100000);

    // الحالة مشتقة آلياً: جزئية — والذمة 60,000 والصندوق 600,000
    expect((await db.invoiceById(saleId))!.state, 'partially_paid');
    expect(await db.invoiceCoveredDocMinor(saleId), 100000);
    expect(await db.accountBalanceOf(acc112), 60000);
    expect(await db.cashBoxBalanceOf(f.boxId), 600000);
  });

  test('س-64 قبض جزئي ثم تكميل مع فائض «رصيد مقدّم» وحاجزا المطابقة',
      () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final saleId = await f.saleCredit(lines: [f.line(f.oilId, 4, 40000)]);
    await f.receiptFromCustomer(
        amount: 100000,
        allocations: [VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 100000)]);

    // مطابقة تتجاوز المتبقي (60,000) مرفوضة
    expect(
        () => f.receiptFromCustomer(
            amount: 200000,
            allocations: [
              VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 200000)
            ]),
        throwsA(isA<VoucherValidationException>()));

    // التكميل: 60,000 تغطي الفاتورة كلياً و20,000 فائض يبقى رصيداً مقدماً
    final second = await f.receiptFromCustomer(
        amount: 80000,
        allocations: [VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 60000)]);
    expect((await db.invoiceById(saleId))!.state, 'paid');
    expect(await db.invoiceCoveredDocMinor(saleId), 160000);
    final acc112 = await accountIdByCode(db, '112');
    expect(await db.accountBalanceOf(acc112), -20000,
        reason: 'الذمة صفر والفائض 20,000 رصيد مقدّم دائن (س-12/س5)');

    // وفاتورة مغطاة كلياً لا تُطابق بعد الآن
    expect(
        () => f.receiptFromCustomer(
            amount: 10000,
            allocations: [
              VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 10000)
            ]),
        throwsA(isA<VoucherValidationException>()));
    final secondVoucher = (await db.voucherById(second))!;
    expect(secondVoucher.number, '${seqNum(f.year, 3)}');
  });

  test('س-65 سند صرف لمورد: قيد 211/1111 وحركة خروج وذمة تصفو', () async {
    final f = await buildFixture(db);
    final purchaseId = await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final proposal = await db.proposeVoucherAllocations(
        kind: VoucherKind.payment,
        partyId: f.supplierId,
        currencyId: 1,
        amountDocMinor: 250000);
    expect(proposal.single.invoiceId, purchaseId);
    expect(proposal.single.appliedDocMinor, 250000);

    final voucherId = await f.paymentToSupplier(
        amount: 250000,
        allocations: [
          VoucherAllocationDraft(invoiceId: purchaseId, appliedDocMinor: 250000)
        ]);
    final voucher = (await db.voucherById(voucherId))!;
    // D-105 (دفعة 8 س39): «سند دفع» في أرقام المستندات المعروضة —
    // والنص الحرفي تحديثًا بقرار المصطلح (درس س35: الحكم بالنص الحرفي).
    expect(voucherDisplayLabel(voucher), 'سند دفع ${seqNum(f.year, 1)}');
    final lines = await moveLinesOf(db, voucher.moveId!);
    expect(lines[0]['account_id'], await accountIdByCode(db, '211'));
    expect(lines[0]['debit_minor'], 250000);
    expect(lines[0]['party_id'], f.supplierId);
    expect(lines[1]['account_id'], await accountIdByCode(db, '1111'));
    expect(lines[1]['credit_minor'], 250000);

    expect((await db.invoiceById(purchaseId))!.state, 'paid');
    expect(await db.accountBalanceOf(await accountIdByCode(db, '211')), 0);
    expect(await db.cashBoxBalanceOf(f.boxId), 250000,
        reason: '500,000 ضخ − 250,000 صرف');
    // حركة الصندوق «خارج» بمرجع السند
    final movement = await db.customSelect(
      "SELECT kind, amount_minor, amount_base_minor, ref_doc_type, ref_doc_id "
      'FROM cash_movements WHERE ref_doc_type = ?1 AND ref_doc_id = ?2',
      variables: [Variable.withString('voucher'), Variable.withInt(voucherId)],
    ).getSingle();
    expect(movement.data['kind'], 'out');
    expect(movement.data['amount_minor'], 250000);
  });

  test('س-66/س-67 السند بغير طرف: ضخ 311 ومسحوبات 321 ومصروف 542 وحاجزاه',
      () async {
    final f = await buildFixture(db, funded: false);
    final boxAcc = await accountIdByCode(db, '1111');
    final acc311 = await accountIdByCode(db, '311');
    final acc321 = await accountIdByCode(db, '321');
    final acc542 = await accountIdByCode(db, '542');

    final capitalId = await f.capitalInjection(500000);
    final capital = (await db.voucherById(capitalId))!;
    expect(voucherDisplayLabel(capital), 'سند قبض ${seqNum(f.year, 1)}');
    final capitalLines = await moveLinesOf(db, capital.moveId!);
    expect(capitalLines[0]['account_id'], boxAcc);
    expect(capitalLines[0]['debit_minor'], 500000);
    expect(capitalLines[1]['account_id'], acc311);
    expect(capitalLines[1]['credit_minor'], 500000);

    Future<int> directPayment(int accountId, int amount) async {
      final id = await db.createVoucherDraft(VoucherDraft(
        kind: VoucherKind.payment,
        dateText: f.date,
        directAccountId: accountId,
        cashBoxId: f.boxId,
        amountDocMinor: amount,
      ));
      await db.postVoucher(id);
      return id;
    }

    final withdrawalsId = await directPayment(acc321, 20000);
    final withdrawalsLines = await moveLinesOf(db, (await db.voucherById(withdrawalsId))!.moveId!);
    expect(withdrawalsLines[0]['account_id'], acc321);
    expect(withdrawalsLines[0]['debit_minor'], 20000);
    expect(withdrawalsLines[1]['account_id'], boxAcc);
    expect(withdrawalsLines[1]['credit_minor'], 20000);
    await directPayment(acc542, 10000);
    expect(await db.cashBoxBalanceOf(f.boxId), 470000);
    expect(await db.accountBalanceOf(acc321), 20000,
        reason: 'المسحوبات تجمع على 321 لا في المصروفات (02 §7)');

    // الحاجز الأول: الحساب المباشر لا يكون حساب صندوق — التحويل مستنده
    expect(
        () => db.createVoucherDraft(VoucherDraft(
              kind: VoucherKind.receipt,
              dateText: f.date,
              directAccountId: boxAcc,
              cashBoxId: f.boxId,
              amountDocMinor: 10000,
            )),
        throwsA(isA<VoucherValidationException>()));
    // الحاجز الثاني: حساب معطل يرفض
    final acc549 = await accountIdByCode(db, '549');
    await db.customStatement('UPDATE accounts SET is_active = 0 WHERE id = ?',
        [acc549]);
    expect(
        () => directPayment(acc549, 5000),
        throwsA(isA<VoucherValidationException>()));
    // والطرف مع الحساب المباشر معاً مرفوض بنيوياً
    expect(
        () => db.createVoucherDraft(VoucherDraft(
              kind: VoucherKind.receipt,
              dateText: f.date,
              partyId: f.customerId,
              directAccountId: acc311,
              cashBoxId: f.boxId,
              amountDocMinor: 10000,
            )),
        throwsA(isA<VoucherValidationException>()));
  });

  test('س-68 سند دولار وفرق صرف محقق: 44 دائناً بالربح و55 مديناً بالخسارة',
      () async {
    final f = await buildFixture(db, funded: false);
    final usdBoxId = await db.createCashBox(name: 'صندوق الدولار', currencyId: 2);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final acc44 = await accountIdByCode(db, '44');
    final acc55 = await accountIdByCode(db, '55');
    final acc112 = await accountIdByCode(db, '112');

    // فاتورة دولار آجلة بلقطة 15,000 ثم قبضها بلقطة 16,000: ربح محقق
    final inv1 = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: f.date,
      partyId: f.customerId,
      warehouseId: f.warehouseId,
      currencyId: 2,
      fxRate: 15000 * fxRateScale,
      lines: [f.line(f.oilId, 1, 10000)],
    ));
    await db.postInvoice(inv1);
    final v1 = await f.receiptFromCustomer(
        amount: 10000,
        currencyId: 2,
        fxRate: 16000 * fxRateScale,
        boxId: usdBoxId,
        allocations: [VoucherAllocationDraft(invoiceId: inv1, appliedDocMinor: 10000)]);
    final v1Lines = await moveLinesOf(db, (await db.voucherById(v1))!.moveId!);
    // 1112 مدين 160,000,000 / 112 دائن 150,000,000 + 44 دائن 10,000,000
    expect(v1Lines, hasLength(3));
    expect(v1Lines[0]['debit_minor'], 160000000);
    expect(v1Lines[1]['credit_minor'], 150000000,
        reason: 'الذمة تُقيَّد بلقطة الفاتورة فتصفو حرفاً (D-084 معروض)');
    expect(v1Lines[2]['account_id'], acc44);
    expect(v1Lines[2]['credit_minor'], 10000000);
    expect(await db.accountBalanceOf(acc112), 0);
    expect(await db.cashBoxBalanceOf(usdBoxId), 160000000);
    expect((await db.invoiceById(inv1))!.state, 'paid');

    // والعكس: فاتورة بلقطة 16,000 وقبض بلقطة 15,000: خسارة محقق 55 مديناً
    final inv2 = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: f.date,
      partyId: f.customerId,
      warehouseId: f.warehouseId,
      currencyId: 2,
      fxRate: 16000 * fxRateScale,
      lines: [f.line(f.oilId, 1, 10000)],
    ));
    await db.postInvoice(inv2);
    await f.receiptFromCustomer(
        amount: 10000,
        currencyId: 2,
        fxRate: 15000 * fxRateScale,
        boxId: usdBoxId,
        allocations: [VoucherAllocationDraft(invoiceId: inv2, appliedDocMinor: 10000)]);
    expect(await db.accountBalanceOf(acc55), 10000000);
    expect(await db.accountBalanceOf(acc112), 0,
        reason: 'الذمتان صفتا بالأساسية والفروق كلها على 44/55 (F-123/D-085 معروضان)');

    // وسند بعملة على صندوق بعملة أخرى مرفوض — سند كل صندوق بعملته
    expect(
        () => f.receiptFromCustomer(amount: 10000, currencyId: 2),
        throwsA(isA<VoucherValidationException>()));
    // والميزان كله متوازن
    final (debit, credit) = await db.trialBalanceTotalsOf();
    expect(debit, credit);
  });

  test('س-69 تحويل بين صندوقين: قيد سطرين وحركتان متبادلتان وحواجز التحويل',
      () async {
    final f = await buildFixture(db);
    final branchBoxId = await db.createCashBox(name: 'صندوق الفرع', currencyId: 1);
    final usdBoxId = await db.createCashBox(name: 'صندوق الدولار', currencyId: 2);

    final transferId = await db.createCashTransferDraft(CashTransferDraft(
      dateText: f.date,
      fromBoxId: f.boxId,
      toBoxId: branchBoxId,
      amountDocMinor: 100000,
    ));
    await db.postCashTransfer(transferId);

    final transferRows = await db.customSelect(
      'SELECT number, state, move_id FROM box_transfers WHERE id = ?',
      variables: [Variable.withInt(transferId)],
    ).getSingle();
    expect(transferRows.data['state'], 'posted');
    expect(transferRows.data['number'], '${seqNum(f.year, 1)}');
    final lines = await moveLinesOf(db, transferRows.data['move_id'] as int);
    expect(lines[0]['account_id'], await accountIdByCode(db, '1112'),
        reason: 'صندوق الفرع أُنشئ أولاً فيأخذ 1112 والدولاري يليه 1113');
    expect(lines[0]['debit_minor'], 100000);
    expect(lines[1]['account_id'], await accountIdByCode(db, '1111'));
    expect(lines[1]['credit_minor'], 100000);

    // حركتا الصندوق بمرجعية المستند المتبادلة (03 §4/D-087 معروض)
    final movements = await db.customSelect(
      "SELECT cash_box_id, kind FROM cash_movements "
      "WHERE ref_doc_type = 'box_transfer' AND ref_doc_id = ? ORDER BY id",
      variables: [Variable.withInt(transferId)],
    ).get();
    expect(movements, hasLength(2));
    expect(movements[0].data['cash_box_id'], f.boxId);
    expect(movements[0].data['kind'], 'transfer_out');
    expect(movements[1].data['cash_box_id'], branchBoxId);
    expect(movements[1].data['kind'], 'transfer_in');

    expect(await db.cashBoxBalanceOf(f.boxId), 400000);
    expect(await db.cashBoxBalanceOf(branchBoxId), 100000);

    // الحواجز: نفس الصندوق؛ وعملتان مختلفتان؛ ورصيد المرسل لا يكفي
    expect(
        () => db.createCashTransferDraft(CashTransferDraft(
            dateText: f.date,
            fromBoxId: f.boxId,
            toBoxId: f.boxId,
            amountDocMinor: 1000)),
        throwsA(isA<CashTransferValidationException>()));
    expect(
        () => db.createCashTransferDraft(CashTransferDraft(
            dateText: f.date,
            fromBoxId: f.boxId,
            toBoxId: usdBoxId,
            amountDocMinor: 1000)),
        throwsA(isA<CashTransferValidationException>()));
    expect(
        () => db.createCashTransferDraft(CashTransferDraft(
            dateText: f.date,
            fromBoxId: branchBoxId,
            toBoxId: f.boxId,
            amountDocMinor: 1000000000)),
        throwsA(isA<CashTransferValidationException>()));
  });

  test('س-70 تسوية الصندوق: عجز على 57 وسبب إلزامي ومرحّلتها مجمدة',
      () async {
    final f = await buildFixture(db);
    final acc57 = await accountIdByCode(db, '57');

    // الفرق صفر لا يولّد تسوية (بنية المسودة ترفض الصفر)
    expect(
        () => db.createCashAdjustmentDraft(CashAdjustmentDraft(
              dateText: f.date,
              cashBoxId: f.boxId,
              direction: CashAdjustmentDirection.shortage,
              amountDocMinor: 0,
              reason: 'عجز',
            )),
        throwsA(isA<CashAdjustmentValidationException>()));
    // والسبب النصي إلزامي
    expect(
        () => db.createCashAdjustmentDraft(CashAdjustmentDraft(
              dateText: f.date,
              cashBoxId: f.boxId,
              direction: CashAdjustmentDirection.shortage,
              amountDocMinor: 5000,
              reason: '   ',
            )),
        throwsA(isA<CashAdjustmentValidationException>()));

    final adjId = await db.createCashAdjustmentDraft(CashAdjustmentDraft(
      dateText: f.date,
      cashBoxId: f.boxId,
      direction: CashAdjustmentDirection.shortage,
      amountDocMinor: 5000,
      reason: 'عجز حصر فعلي 2026-03-15',
    ));
    await db.postCashAdjustment(adjId);
    final adj = await db.customSelect(
      'SELECT number, state, move_id FROM cash_adjustments WHERE id = ?',
      variables: [Variable.withInt(adjId)],
    ).getSingle();
    expect(adj.data['state'], 'posted');
    expect(adj.data['number'], '${seqNum(f.year, 1)}');
    final lines = await moveLinesOf(db, adj.data['move_id'] as int);
    expect(lines[0]['account_id'], acc57);
    expect(lines[0]['debit_minor'], 5000);
    expect(lines[1]['account_id'], await accountIdByCode(db, '1111'));
    expect(lines[1]['credit_minor'], 5000);
    expect(await db.accountBalanceOf(acc57), 5000);
    expect(await db.cashBoxBalanceOf(f.boxId), 495000);

    // والزيادة تدخل بالعكس: الصندوق مدين و57 دائن (س8/F-067)
    final overId = await db.createCashAdjustmentDraft(CashAdjustmentDraft(
      dateText: f.date,
      cashBoxId: f.boxId,
      direction: CashAdjustmentDirection.overage,
      amountDocMinor: 2000,
      reason: 'زيادة حصر فعلي',
    ));
    await db.postCashAdjustment(overId);
    expect(await db.accountBalanceOf(acc57), 3000,
        reason: '57 عجز مدين 5,000 وزيادة دائنة 2,000 — الحساب الواحد للاتجاهين');

    // المرحّلة مجمدة بالقاعدة
    await expectLater(
      db.customStatement(
        'UPDATE cash_adjustments SET amount_doc_minor = 1 WHERE id = ?',
        [adjId],
      ),
      throwsA(anything),
    );
  });

  test('الحواجز (المُشغِّلات): السند المرحّل ومطابقاته مجمدة والمسودة تُحذف',
      () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final saleId = await f.saleCredit(lines: [f.line(f.oilId, 4, 40000)]);
    final voucherId = await f.receiptFromCustomer(
        amount: 100000,
        allocations: [VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 100000)]);

    await expectLater(
      db.customStatement(
        'UPDATE vouchers SET amount_doc_minor = 1 WHERE id = ?',
        [voucherId],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'DELETE FROM vouchers WHERE id = ?',
        [voucherId],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'UPDATE voucher_allocations SET applied_doc_minor = 1 '
        'WHERE voucher_id = ?',
        [voucherId],
      ),
      throwsA(anything),
    );
    // لا مطابقة تضاف لسند مرحّل ولا على فاتورة مسودة (حاجز القاعدة)
    final draftSale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: f.date,
      partyId: f.customerId,
      warehouseId: f.warehouseId,
      lines: [f.line(f.oilId, 1, 40000)],
    ));
    await expectLater(
      db.customStatement(
        'INSERT INTO voucher_allocations (voucher_id, invoice_id, '
        "applied_doc_minor, applied_base_minor, uuid) VALUES (?, ?, 1000, 0, 'g')",
        [voucherId, draftSale],
      ),
      throwsA(anything),
    );
    // وحذف المسودة بالحرس لا بالمُشغِّل: المرحّل يرفض بالمدقق
    expect(
        db.deleteVoucherDraft(voucherId),
        throwsA(isA<VoucherValidationException>()));

    // المسودة تُحذف بلقطة كاملة في السجل ولا رقم يُهدر
    final draftId = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: f.date,
      partyId: f.customerId,
      cashBoxId: f.boxId,
      amountDocMinor: 5000,
    ));
    await db.deleteVoucherDraft(draftId);
    expect(await db.voucherById(draftId), isNull);
    final events = await db.customSelect(
      "SELECT action FROM events WHERE entity_type = 'voucher' "
      'AND entity_id = ? ORDER BY id',
      variables: [Variable.withInt(draftId)],
    ).get();
    expect(events.map((e) => e.data['action']),
        ['created', 'draft_deleted']);
    // والسند التالي يأخذ الرقم التالي بلا فجوة ولا إعادة استخدام (07 §1.9):
    // المرحّلان 000001 و000002 ثم المسودة حُذفت بلا رقم فالتالي 000003
    final nextId = await f.receiptFromCustomer(amount: 7000);
    expect((await db.voucherById(nextId))!.number, '${seqNum(f.year, 3)}');
  });

  test('ترحيلة 6→8 بقاعدة خام (F-011): جداول السندات وفعالية 44/55 فوق قائمة',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v8_mig_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate.db');
    // قاعدة v6 خام: items بالشكل البعد v5 وصف واحد — والبقية تبنيها
    // خطوات v7 ثم v8 (نمط اختبار الترحيلات المجرَّب).
    final raw = sqlite3.open(dbPath);
    raw.execute('CREATE TABLE "items" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"sku" TEXT NOT NULL UNIQUE,'
        '"name" TEXT NOT NULL,'
        '"category" TEXT NULL,'
        '"kind" TEXT NOT NULL,'
        '"base_unit_id" INTEGER NOT NULL,'
        '"purchase_price_minor" INTEGER NOT NULL,'
        '"sale_price_minor" INTEGER NOT NULL,'
        '"price_currency_id" INTEGER NOT NULL,'
        '"default_tax_id" INTEGER NULL,'
        '"is_active" INTEGER NOT NULL DEFAULT 0,'
        '"uuid" TEXT NOT NULL,'
        '"created_at" INTEGER NOT NULL DEFAULT 0,'
        '"updated_at" INTEGER NOT NULL DEFAULT 0,'
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)');
    raw.execute(
        "INSERT INTO items (sku, name, kind, base_unit_id, "
        "purchase_price_minor, sale_price_minor, price_currency_id, "
        "is_active, uuid) VALUES ('SKU-OLD', 'بضاعة قبل الترحيل', 'good', 1, "
        "250000, 275000, 1, 1, 'uuid-old-1')");
    raw.execute('PRAGMA user_version = 6');
    raw.dispose();

    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    expect(migrated.schemaVersion, 19);
    final vouchers = await migrated.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'vouchers'",
    ).get();
    expect(vouchers, hasLength(1));
    for (final code in const ['44', '55']) {
      final rows = await migrated.customSelect(
        'SELECT is_active FROM accounts WHERE code = ?',
        variables: [Variable.withString(code)],
      ).getSingle();
      expect(rows.data['is_active'], 1,
          reason: 'البذر فُعِّل فوق بيانات قائمة (F-123/D-085 معروضان)');
    }
    // والمحرك يعمل فوق المهدَّر: ضخ رأس مال كامل بأرقام س-66
    final year = await seededYear(migrated);
    final boxId = (await migrated.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final voucherId = await migrated.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: '$year-03-15',
      directAccountId: await accountIdByCode(migrated, '311'),
      cashBoxId: boxId,
      amountDocMinor: 500000,
    ));
    await migrated.postVoucher(voucherId);
    expect((await migrated.voucherById(voucherId))!.number, '${seqNum(year, 1)}');
    expect(await migrated.cashBoxBalanceOf(boxId), 500000);
  });
}
