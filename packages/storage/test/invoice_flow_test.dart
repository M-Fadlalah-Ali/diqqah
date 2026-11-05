import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart' show Value, Variable;

/// الصيغة الجديدة D-169 (سنة رقمين + عدّاد مبطن) — مشتقة من سنة البذرة.
String seqNum(int year, int n, [int w = 6]) =>
    '${(year % 100).toString().padLeft(2, '0')}${n.toString().padLeft(w, '0')}';

/// أدوات الدفعة — بنمط ledger_test: معرفات بالبحث بالكود لا بالثبوت
/// الأعمى، وسنة ديناميكية من البذر لا مثبتة كي لا يكسرها تغيّر سنة CI.
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

/// أرضية كل اختبار: وحدة وصنفان بضاعة وخدمة وعميل ومورد والمستودع
/// والصندوق المزروعان (س-51) — وأرقام الأصناف من بطاقتها (س-36).
class Fixture {
  final DiqqahDatabase db;
  final int year;
  final String date;
  final int unitId;
  final int oilId;
  final int sugarId;
  final int serviceId;
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
    required this.sugarId,
    required this.serviceId,
    required this.customerId,
    required this.supplierId,
    required this.boxId,
    required this.warehouseId,
  });

  InvoiceLineDraft line(int itemId, int qty, int price) =>
      InvoiceLineDraft(
          itemId: itemId, unitId: unitId, qtyBase: qty, unitPriceMinor: price);

  /// شراء آجل معروض (س-04): ذمة مورد بحمولة party_id
  Future<int> purchaseCredit({
    required List<InvoiceLineDraft> lines,
    int discountRate = 0,
    int? partyId,
  }) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: partyId ?? supplierId,
      warehouseId: warehouseId,
      discountRate: discountRate,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
  }

  /// بيع آجل معروض (س-07)
  Future<int> saleCredit({
    required List<InvoiceLineDraft> lines,
    int? partyId,
  }) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: partyId ?? customerId,
      warehouseId: warehouseId,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
  }

  /// بيع نقدي معروض (س-06): يطلب الصندوق
  Future<int> saleCash({required List<InvoiceLineDraft> lines}) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
  }

  /// مردود بيع بتخفيض ذمة العميل (س-11)
  Future<int> saleReturnAgainst(
    int originalId, {
    required List<InvoiceLineDraft> lines,
  }) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.saleReturn,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      originalInvoiceId: originalId,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
  }
}

Future<Fixture> buildFixture(DiqqahDatabase db) async {
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
  final sugarId = await db.insertItem(
      sku: 'S-200',
      name: 'سكر حبوب',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 12000,
      salePriceMinor: 18000,
      priceCurrencyId: 1);
  final serviceId = await db.insertItem(
      sku: 'SRV-1',
      name: 'تغليف هدايا',
      kind: 'service',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 15000,
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
  return Fixture(
    db: db,
    year: year,
    date: date,
    unitId: unitId,
    oilId: oilId,
    sugarId: sugarId,
    serviceId: serviceId,
    customerId: customerId,
    supplierId: supplierId,
    boxId: boxId,
    warehouseId: warehouseId,
  );
}

/// جلب أسطر قيد فاتورة بأعمدته الكاملة — لفحص لقطات العملة والربط.
Future<List<Map<String, Object?>>> moveLinesOf(
  DiqqahDatabase db,
  int moveId,
) async {
  final rows = await db.customSelect(
    'SELECT account_id, debit_minor, credit_minor, party_id, currency_id, '
    'amount_minor, fx_rate, ref_stock_move_id '
    'FROM move_lines WHERE move_id = ? ORDER BY id',
    variables: [Variable.withInt(moveId)],
  ).get();
  return [for (final r in rows) r.data];
}

void main() {
  late DiqqahDatabase db;

  setUp(() {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('بذر v7 (س-51): العملتان ببنيتهما والمستودع والصندوق على 1111', () async {
    expect(db.schemaVersion, 21);
    final currencies = await db.currenciesOf();
    expect(currencies, hasLength(2),
        reason: 'قبل م3 لا عملة ثالثة — الأساسية والدولار حصراً (D-070)');
    expect(currencies[0].code, 'SYP');
    expect(currencies[0].isBase, isTrue);
    expect(currencies[0].minorUnits, 2);
    expect(currencies[1].code, 'USD');
    expect(currencies[1].isBase, isFalse);
    final warehouse = (await db.warehouseById((await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int))!;
    expect(warehouse.name, 'المستودع الرئيسي');
    final boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final box = (await db.cashBoxById(boxId))!;
    expect(box.name, 'الصندوق الرئيسي');
    expect(box.currencyId, 1);
    expect(box.accountId, await accountIdByCode(db, '1111'),
        reason: 'الصندوق الرئيسي هو 1111 في الدليل (03 §3)');
    expect(await db.cashBoxBalanceOf(boxId), 0);
  });

  test('س-52 شراء آجل: القيد 113/211 بالذمة والمخزون والرقم والربط', () async {
    final f = await buildFixture(db);
    final id = await f.purchaseCredit(
        lines: [f.line(f.oilId, 10, 25000)]);
    final inv = (await db.invoiceById(id))!;
    expect(inv.state, 'posted');
    expect(inv.number, '${seqNum(f.year, 1)}');
    expect(inv.totalDocMinor, 250000);
    expect(inv.totalBaseMinor, 250000);
    expect(inv.moveId, isNotNull);
    expect(invoiceDisplayLabel(inv), 'فاتورة شراء ${seqNum(f.year, 1)}');

    final acc113 = await accountIdByCode(db, '113');
    final acc211 = await accountIdByCode(db, '211');
    expect(await db.accountBalanceOf(acc113), 250000);
    expect(await db.accountBalanceOf(acc211), 250000);

    // سطر الذمة يحمل الطرف على حساب السيطرة (م-14/س-04)
    final lines = await moveLinesOf(db, inv.moveId!);
    final payable = lines.firstWhere((l) => l['account_id'] == acc211);
    expect(payable['credit_minor'], 250000);
    expect(payable['party_id'], f.supplierId);
    // لقطة العملة على أرجل المستند (F-122/D-082): الأساسية لقطتها 10^6
    final inventory = lines.firstWhere((l) => l['account_id'] == acc113);
    expect(inventory['debit_minor'], 250000);
    expect(inventory['currency_id'], 1);
    expect(inventory['amount_minor'], 250000);
    expect(inventory['fx_rate'], baseCurrencyFxRate);

    // المخزون وحركته بلقطة كلفة ومرجع مستند (F-041/F-140)
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (10, 250000));
    final stockMove = (await db.customSelect(
      "SELECT qty_base, to_warehouse_id, value_base_minor, "
      "unit_cost_base_minor, ref_doc_type, ref_doc_id FROM stock_moves",
    ).getSingle()).data;
    expect(stockMove['qty_base'], 10);
    expect(stockMove['to_warehouse_id'], f.warehouseId);
    expect(stockMove['value_base_minor'], 250000);
    expect(stockMove['unit_cost_base_minor'], 25000);
    expect(stockMove['ref_doc_type'], 'invoice');
    expect(stockMove['ref_doc_id'], id);
    expect(inventory['ref_stock_move_id'],
        (await db.customSelect('SELECT id FROM stock_moves').getSingle())
            .data['id']);

    // الميزان متوازن وترقيم القيد من دفتر المشتريات (D-080 معروض)
    final (debit, credit) = await db.trialBalanceTotalsOf();
    expect(debit, credit);
    final move = (await db.customSelect(
      'SELECT number, journal_id FROM moves WHERE id = ?',
      variables: [Variable.withInt(inv.moveId!)],
    ).getSingle()).data;
    expect(move['number'], '${seqNum(f.year, 1)}');
    final seqInvoice = await db.customSelect(
      'SELECT last_number FROM sequences WHERE kind = ? AND year = ?',
      variables: [
        Variable.withString('invoice_purchase'),
        Variable.withInt(f.year)
      ],
    ).get();
    expect(seqInvoice, hasLength(1));
    expect(seqInvoice.first.data['last_number'], 1);
  });

  test('س-53 بيع آجل: منع السالب قبل الحفظ والتكلفة 51/113 والذمة', () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);

    // الرفض قبل الحفظ (س-06/F-042): 11 > رصيد 10 — ولا صف يُكتب
    Object? caught;
    try {
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: f.date,
        partyId: f.customerId,
        warehouseId: f.warehouseId,
        lines: [f.line(f.oilId, 11, 40000)],
      ));
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
    expect((caught as InvoiceValidationException).errors
        .whereType<InvoiceStockInsufficient>(), isNotEmpty);
    expect(await db.customSelect('SELECT COUNT(*) AS c FROM invoices')
        .getSingle().then((r) => r.data['c']), 1,
        reason: 'المرفوضة لا تترك أثراً');

    final id = await f.saleCredit(lines: [f.line(f.oilId, 4, 40000)]);
    final inv = (await db.invoiceById(id))!;
    expect(inv.state, 'posted');
    expect(inv.number, '${seqNum(f.year, 1)}');

    // تكلفة الخروج: 250,000 × 4/10 = 100,000 تام (لا غبار)
    final acc112 = await accountIdByCode(db, '112');
    final acc411 = await accountIdByCode(db, '411');
    final acc51 = await accountIdByCode(db, '51');
    final acc113 = await accountIdByCode(db, '113');
    expect(await db.accountBalanceOf(acc112), 160000);
    expect(await db.accountBalanceOf(acc411), 160000);
    expect(await db.accountBalanceOf(acc51), 100000);
    expect(await db.accountBalanceOf(acc113), 150000);
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (6, 150000));
    final receivable = (await moveLinesOf(db, inv.moveId!))
        .firstWhere((l) => l['account_id'] == acc112);
    expect(receivable['party_id'], f.customerId);
  });

  test('س-54 بيع نقدي بضاعة وخدمة: مدفوعة فوراً والصندوق 411/412', () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    await f.saleCredit(lines: [f.line(f.oilId, 4, 40000)]);
    final id = await f.saleCash(lines: [
      f.line(f.oilId, 6, 40000),
      f.line(f.serviceId, 2, 15000),
    ]);
    final inv = (await db.invoiceById(id))!;
    expect(inv.state, 'paid',
        reason: 'النقدية «مدفوعة» فور ترحيلها (س-03/س-06)');

    final acc411 = await accountIdByCode(db, '411');
    final acc412 = await accountIdByCode(db, '412');
    final acc51 = await accountIdByCode(db, '51');
    final acc113 = await accountIdByCode(db, '113');
    expect(await db.accountBalanceOf(acc411), 400000);
    expect(await db.accountBalanceOf(acc412), 30000);
    expect(await db.accountBalanceOf(acc51), 250000);
    expect(await db.accountBalanceOf(acc113), 0);
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (0, 0), reason: 'الخروج بكل الكمية يمتص القيمة كلها (D-067)');
    expect(await db.cashBoxBalanceOf(f.boxId), 270000);
    final movement = (await db.customSelect(
      'SELECT kind, amount_minor, amount_base_minor, ref_doc_type, '
      'ref_doc_id FROM cash_movements',
    ).getSingle()).data;
    expect(movement['kind'], 'in');
    expect(movement['amount_base_minor'], 270000);
    expect(movement['ref_doc_type'], 'invoice');
    expect(movement['ref_doc_id'], id);
  });

  test('س-55 خصم فاتورة شراء يخفض الكلفة: توزيع نسبي وآخر سطر يمتص',
      () async {
    final f = await buildFixture(db);
    final id = await f.purchaseCredit(
      discountRate: 1000,
      lines: [f.line(f.oilId, 3, 10001), f.line(f.sugarId, 1, 9999)],
    );
    final inv = (await db.invoiceById(id))!;
    expect(inv.subtotalDocMinor, 40002);
    expect(inv.discountDocMinor, 4000);
    expect(inv.totalDocMinor, 36002);
    expect(inv.totalBaseMinor, 36002);

    final acc113 = await accountIdByCode(db, '113');
    final acc211 = await accountIdByCode(db, '211');
    expect(await db.accountBalanceOf(acc211), 36002);
    // الصافي يتوزع: زيت 27,003 (امتصاص آخر سطر) وسكر 8,999
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (3, 27003));
    expect(
        await db.stockBalanceOf(itemId: f.sugarId, warehouseId: f.warehouseId),
        (1, 8999));
    expect(await db.accountBalanceOf(acc113), 36002,
        reason: 'ثابت المطابقة: رصيد 113 = مجموع القيمة الإجمالية (D-067)');
    final invLines = await db.invoiceLines(id);
    expect(invLines[0].lineTotalBaseMinor, 27003);
    expect(invLines[1].lineTotalBaseMinor, 8999);
  });

  test('س-56 مردود بيع جزئي: لقطة الأصل و58 على المخزون الفارغ والمتبقي',
      () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final saleId = await f.saleCredit(lines: [f.line(f.oilId, 4, 40000)]);
    await f.saleCash(lines: [f.line(f.oilId, 6, 40000)]);

    final acc42 = await accountIdByCode(db, '42');
    final acc112 = await accountIdByCode(db, '112');
    final acc51 = await accountIdByCode(db, '51');
    final acc113 = await accountIdByCode(db, '113');
    final acc58 = await accountIdByCode(db, '58');

    final firstReturn = await f.saleReturnAgainst(
        saleId, lines: [f.line(f.oilId, 2, 40000)]);
    final retInv = (await db.invoiceById(firstReturn))!;
    expect(retInv.state, 'posted');
    expect(retInv.number, '${seqNum(f.year, 1)}');
    expect(invoiceDisplayLabel(retInv), 'مردود بيع ${seqNum(f.year, 1)}');

    // الدخول بلقطة كلفة خروج الأصل (25,000×2 = 50,000) والنظير صفر
    // لأن المتوسط على مخزون فارغ صفر — فالفرق كله على 58 (م-25/س-56)
    expect(await db.accountBalanceOf(acc42), 80000);
    expect(await db.accountBalanceOf(acc112), 80000,
        reason: 'تخفيض ذمة العميل بمقدار المردود');
    expect(await db.accountBalanceOf(acc113), 50000);
    expect(await db.accountBalanceOf(acc51), 250000,
        reason: 'تكلفة البيعين السابقين (100,000 + 150,000) — والمردود نظيره صفر لأن المتوسط على مخزون فارغ صفر');
    expect(await db.accountBalanceOf(acc58), -50000,
        reason: '58 حساب عكسي — دائن به عند فرق الاستعادة (03 §3)');
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (2, 50000));

    // المتبقي 2: طلب 3 مرفوض وطلب 2 يمتص ما تبقى من قيمة الأصل (D-067)
    Object? caught;
    try {
      await f.saleReturnAgainst(saleId, lines: [f.line(f.oilId, 3, 40000)]);
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
    expect((caught as InvoiceValidationException).errors
        .whereType<InvoiceReturnQtyExceedsRemaining>(), isNotEmpty);

    await f.saleReturnAgainst(saleId, lines: [f.line(f.oilId, 2, 40000)]);
    expect(await db.accountBalanceOf(acc113), 100000);
    expect(await db.accountBalanceOf(acc58), -50000,
        reason: 'المردود الثاني استعاد ما تبقى فلا فرق جديد على 58');
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (4, 100000));
    final (debit, credit) = await db.trialBalanceTotalsOf();
    expect(debit, credit);
  });

  test('س-57 مردود شراء: الخروج بالقيمة الدفترية والفرق على 58', () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final secondPurchase =
        await f.purchaseCredit(lines: [f.line(f.oilId, 5, 30000)]);
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (15, 400000));

    final acc211 = await accountIdByCode(db, '211');
    final acc113 = await accountIdByCode(db, '113');
    final acc58 = await accountIdByCode(db, '58');

    // مردود 2 من الثاني: ائتمان 60,000 والقيمة الدفترية
    // 400,000×2/15 = 53,333 — والفرق 6,667 على 58 (س-05/D-067)
    final returnId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchaseReturn,
      dateText: f.date,
      partyId: f.supplierId,
      warehouseId: f.warehouseId,
      originalInvoiceId: secondPurchase,
      lines: [f.line(f.oilId, 2, 30000)],
    ));
    await db.postInvoice(returnId);
    expect(await db.accountBalanceOf(acc211), 340000);
    expect(await db.accountBalanceOf(acc113), 346667);
    expect(await db.accountBalanceOf(acc58), -6667,
        reason: 'الائتمان أكبر من القيمة الدفترية فيدائن 58 العكسية');
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (13, 346667));

    // المتبقي من الثاني 5: طلب 6 مرفوض — والأصل من نوع آخر مرفوض
    Object? caught;
    try {
      final badQty = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchaseReturn,
        dateText: f.date,
        partyId: f.supplierId,
        warehouseId: f.warehouseId,
        originalInvoiceId: secondPurchase,
        lines: [f.line(f.oilId, 6, 30000)],
      ));
      await db.postInvoice(badQty);
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
    expect((caught as InvoiceValidationException).errors
        .whereType<InvoiceReturnQtyExceedsRemaining>(), isNotEmpty);

    caught = null;
    try {
      await f.saleCredit(lines: [f.line(f.oilId, 1, 40000)]);
      final saleId = (await db.customSelect(
        "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
      ).getSingle()).data['id'] as int;
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchaseReturn,
        dateText: f.date,
        partyId: f.supplierId,
        warehouseId: f.warehouseId,
        originalInvoiceId: saleId,
        lines: [f.line(f.oilId, 1, 30000)],
      ));
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
    expect((caught as InvoiceValidationException).errors
        .whereType<InvoiceOriginalKindMismatch>(), isNotEmpty);
  });

  test('س-58 فاتورة بالدولار: اللقطة على أرجل المستند والمكافئ بالأساسية',
      () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 1, 25000)]);

    const usdFx = 15000 * fxRateScale;
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: f.date,
      partyId: f.customerId,
      warehouseId: f.warehouseId,
      currencyId: 2,
      fxRate: usdFx,
      lines: [f.line(f.oilId, 1, 10000)],
    ));
    await db.postInvoice(id);
    final inv = (await db.invoiceById(id))!;
    expect(inv.totalDocMinor, 10000, reason: '100.00 دولار بوحدة صغرى');
    expect(inv.totalBaseMinor, 150000000,
        reason: '100 دولار × 15,000 = 1,500,000 ليرة = 150,000,000 وحدة صغرى');

    final acc112 = await accountIdByCode(db, '112');
    final acc411 = await accountIdByCode(db, '411');
    final acc51 = await accountIdByCode(db, '51');
    final acc113 = await accountIdByCode(db, '113');
    expect(await db.accountBalanceOf(acc112), 150000000);
    expect(await db.accountBalanceOf(acc411), 150000000);
    expect(await db.accountBalanceOf(acc113), 0);
    expect(await db.stockBalanceOf(itemId: f.oilId, warehouseId: f.warehouseId),
        (0, 0));

    // لقطة العملة على أرجل المستند والتكلفة بالأساسية الخالصة (F-174)
    final lines = await moveLinesOf(db, inv.moveId!);
    final receivable = lines.firstWhere((l) => l['account_id'] == acc112);
    expect(receivable['currency_id'], 2);
    expect(receivable['amount_minor'], 10000);
    expect(receivable['fx_rate'], usdFx);
    final revenue = lines.firstWhere((l) => l['account_id'] == acc411);
    expect(revenue['currency_id'], 2);
    expect(revenue['fx_rate'], usdFx);
    final cost = lines.firstWhere((l) => l['account_id'] == acc51);
    expect(cost['currency_id'], 1);
    expect(cost['amount_minor'], 25000);
    expect(cost['fx_rate'], isNull);

    // والدولار النقدي بلا صندوق دولاري (دفعة 5) مرفوض — كل صندوق عملته
    // واحدة (05 §3.3/D-070)
    Object? caught;
    try {
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: f.date,
        cashBoxId: f.boxId,
        warehouseId: f.warehouseId,
        currencyId: 2,
        fxRate: usdFx,
        lines: [f.line(f.oilId, 1, 10000)],
      ));
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
    expect((caught as InvoiceValidationException).errors
        .whereType<InvoiceBoxCurrencyMismatch>(), isNotEmpty);
  });

  test('س-59 حذف مسودة الفاتورة: اللقطة في السجل ولا رقم يُهدر', () async {
    final f = await buildFixture(db);
    final draftId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: f.date,
      partyId: f.supplierId,
      warehouseId: f.warehouseId,
      lines: [f.line(f.oilId, 1, 25000)],
    ));
    expect((await db.invoiceById(draftId))!.state, 'draft');
    await db.deleteInvoiceDraft(draftId);
    expect(await db.invoiceById(draftId), isNull);
    final event = (await db.customSelect(
      "SELECT action, payload FROM events WHERE entity_type = 'invoice' "
      'ORDER BY id DESC LIMIT 1',
    ).getSingle()).data;
    expect(event['action'], 'draft_deleted');
    expect(event['payload'] as String, contains('purchase'));

    // الترقيم لحظة الترحيل حصراً فالحذف لا يهدر رقماً (07 §1.9)
    final id = await f.purchaseCredit(lines: [f.line(f.oilId, 1, 25000)]);
    expect((await db.invoiceById(id))!.number, '${seqNum(f.year, 1)}');

    // والمرحّلة مستحيلة الحذف حرساً ومشغلاً
    Object? caught;
    try {
      await db.deleteInvoiceDraft(id);
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
  });

  test('س-60 الترقيم المركزي: تسلسل لكل نوع بلا فجوات ولا إعادة استخدام',
      () async {
    final f = await buildFixture(db);
    final p1 = await f.purchaseCredit(lines: [f.line(f.oilId, 1, 25000)]);
    final p2 = await f.purchaseCredit(lines: [f.line(f.oilId, 1, 25000)]);
    final s1 = await f.saleCredit(lines: [f.line(f.oilId, 1, 40000)]);
    expect((await db.invoiceById(p1))!.number, '${seqNum(f.year, 1)}');
    expect((await db.invoiceById(p2))!.number, '${seqNum(f.year, 2)}');
    expect((await db.invoiceById(s1))!.number, '${seqNum(f.year, 1)}',
        reason: 'تسلسل البيع مستقل عن الشراء');

    // قيود المستندات من دفاتر جهتها (D-080 معروض)
    Future<String> moveNumberOf(int invoiceId) async {
      final moveId = (await db.invoiceById(invoiceId))!.moveId!;
      return (await db.customSelect(
        'SELECT number FROM moves WHERE id = ?',
        variables: [Variable.withInt(moveId)],
      ).getSingle()).data['number'] as String;
    }

    expect(await moveNumberOf(p1), '${seqNum(f.year, 1)}');
    expect(await moveNumberOf(p2), '${seqNum(f.year, 2)}');
    expect(await moveNumberOf(s1), '${seqNum(f.year, 1)}');

    // حذف مسودة لا يفتح فجوة: الثالثة 000003
    final draftId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: f.date,
      partyId: f.supplierId,
      warehouseId: f.warehouseId,
      lines: [f.line(f.oilId, 1, 25000)],
    ));
    await db.deleteInvoiceDraft(draftId);
    final p3 = await f.purchaseCredit(lines: [f.line(f.oilId, 1, 25000)]);
    expect((await db.invoiceById(p3))!.number, '${seqNum(f.year, 3)}');
  });

  test('الزمن المحاسبي: الفترة المقفلة ترفض الترحيل والخارج يرفض صراحة',
      () async {
    final f = await buildFixture(db);
    // مسودة فوق فترة ستقفل — الإدخال مشروع والترحيل لا (نمط القيود)
    final draftId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: f.date,
      partyId: f.supplierId,
      warehouseId: f.warehouseId,
      lines: [f.line(f.oilId, 1, 25000)],
    ));
    await (db.update(db.periods)).write(const PeriodsCompanion(
      state: Value('closed'),
    ));
    Object? caught;
    try {
      await db.postInvoice(draftId);
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
    expect((caught as InvoiceValidationException).errors
        .whereType<InvoiceClosedPeriod>(), isNotEmpty);

    // تاريخ خارج كل الفترات — والمرفوض لا يلمس العدّاد
    final outsideDraft = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '${f.year + 1}-06-15',
      partyId: f.supplierId,
      warehouseId: f.warehouseId,
      lines: [f.line(f.oilId, 1, 25000)],
    ));
    caught = null;
    try {
      await db.postInvoice(outsideDraft);
    } on InvoiceValidationException catch (e) {
      caught = e;
    }
    expect(caught, isA<InvoiceValidationException>());
    expect((caught as InvoiceValidationException).errors
        .whereType<InvoiceNoPeriod>(), isNotEmpty);
    final seq = await db.customSelect(
      "SELECT COUNT(*) AS c FROM sequences WHERE kind = 'invoice_purchase'",
    ).getSingle();
    expect(seq.data['c'], 0,
        reason: 'المحاولة المرفوضة لا تصدر رقماً (07 §1.9)');
  });

  test('الرفض المرجعي: صنف/وحدة/تعطيل/صندوق/طرف/خدمة في الشراء/صندوق فائض',
      () async {
    final f = await buildFixture(db);
    Future<List<Type>> draftErrors(InvoiceDraft draft) async {
      try {
        await db.createInvoiceDraft(draft);
      } on InvoiceValidationException catch (e) {
        return [for (final err in e.errors) err.runtimeType];
      }
      fail('المفروض الرفض');
    }

    expect(
      await draftErrors(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: f.date,
          partyId: f.customerId,
          warehouseId: f.warehouseId,
          lines: [f.line(9999, 1, 100)])),
      contains(InvoiceItemNotFound),
    );
    expect(
      await draftErrors(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: f.date,
          partyId: f.customerId,
          warehouseId: f.warehouseId,
          lines: [
            InvoiceLineDraft(
                itemId: f.oilId,
                unitId: 999,
                qtyBase: 1,
                unitPriceMinor: 100)
          ])),
      contains(InvoiceUnitMismatch),
    );
    await db.setItemActive(f.oilId, active: false);
    expect(
      await draftErrors(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: f.date,
          partyId: f.customerId,
          warehouseId: f.warehouseId,
          lines: [f.line(f.oilId, 1, 100)])),
      contains(InvoiceItemInactive),
    );
    await db.setItemActive(f.oilId, active: true);

    expect(
      await draftErrors(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: f.date,
          partyId: 999,
          warehouseId: f.warehouseId,
          lines: [f.line(f.oilId, 1, 100)])),
      contains(InvoicePartyMissing),
    );
    expect(
      await draftErrors(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: f.date,
          cashBoxId: 999,
          warehouseId: f.warehouseId,
          lines: [f.line(f.oilId, 1, 100)])),
      contains(InvoiceBoxMissing),
    );
    expect(
      await draftErrors(InvoiceDraft(
          kind: InvoiceKind.purchase,
          dateText: f.date,
          partyId: f.supplierId,
          warehouseId: f.warehouseId,
          lines: [f.line(f.serviceId, 1, 100)])),
      contains(InvoiceServiceInPurchase),
      reason: 'شراء الخدمات يحتاج حساب مصروف — خارج نطاق الدفعة (D-079)',
    );
    // شراء نقدي يفرغ الصندوق الفارغ — منع السالب الموحد (05 §7-2)
    expect(
      await draftErrors(InvoiceDraft(
          kind: InvoiceKind.purchase,
          dateText: f.date,
          cashBoxId: f.boxId,
          warehouseId: f.warehouseId,
          lines: [f.line(f.oilId, 1, 25000)])),
      contains(InvoiceBoxInsufficient),
    );
  });

  test('الحواجز (المُشغِّلات): السالب مستحيل واللقطات والمرحّل مجمدة',
      () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    // بيع خدمة نقدي كي تولد حركة صندوق يفحص عليها تجميد الحذف — بلا مساس
    // المخزون كي تبقى أرقام الحواجز المخزنية كما هي
    await f.saleCash(lines: [f.line(f.serviceId, 1, 15000)]);
    final invId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'purchase'",
    ).getSingle()).data['id'] as int;
    final stockMoveId = (await db.customSelect(
      'SELECT id FROM stock_moves',
    ).getSingle()).data['id'] as int;
    final acc113 = await accountIdByCode(db, '113');

    // منع سالب المخزون بالقوة الخام (الحاجز الثاني — 07 §2.2 نمط D-067)
    await expectLater(
      db.customStatement(
        'UPDATE stock_balances SET qty_base = qty_base - 100 '
        'WHERE item_id = ?',
        [Variable.withInt(f.oilId)],
      ),
      throwsA(anything),
    );
    // حركة المخزون لقطة: لا تعديل ولا حذف (F-140)
    await expectLater(
      db.customStatement(
        'UPDATE stock_moves SET value_base_minor = 1 WHERE id = ?',
        [Variable.withInt(stockMoveId)],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('DELETE FROM stock_moves WHERE id = ?',
          [Variable.withInt(stockMoveId)]),
      throwsA(anything),
    );
    // حركة الصندوق لا تحذف ولا يفرغ تحت الصفر
    await expectLater(
      db.customStatement('DELETE FROM cash_movements'),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
        "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, uuid) "
        "VALUES (?, 'out', 999999999, 999999999, 1000000, 'test', 1, 'raw-1')",
        [Variable.withInt(f.boxId)],
      ),
      throwsA(anything),
    );
    // الفاتورة المرحّلة وأسطرها تجمد (05 §4.1/F-055)
    await expectLater(
      db.customStatement(
        "UPDATE invoices SET number = 'تلاعب' WHERE id = ?",
        [Variable.withInt(invId)],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('DELETE FROM invoices WHERE id = ?',
          [Variable.withInt(invId)]),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'UPDATE invoice_lines SET unit_price_minor = 1 WHERE invoice_id = ?',
        [Variable.withInt(invId)],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO invoice_lines (invoice_id, item_id, unit_id, qty, "
        "qty_base, uuid) VALUES (?, ?, ?, 1, 1, 'raw-line')",
        [Variable.withInt(invId), Variable.withInt(f.oilId),
         Variable.withInt(f.unitId)],
      ),
      throwsA(anything),
    );
    // والحاجز الأول: الترحيل للمسودة حصراً
    await expectLater(
      db.postInvoice(invId),
      throwsA(isA<InvoiceValidationException>()),
    );
    expect(await db.accountBalanceOf(acc113), 250000,
        reason: 'لا رفض يترك أثراً — المعاملات تتراجع كاملة');
  });

  test('ترحيلة 6→7 بقاعدة خام (F-011): بذر الفواتير فوق بيانات قائمة',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v7_mig_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate.db');
    // قاعدة v6 خام: items بالشكل البعد v5 (مع id) وصف واحد — والبقية
    // يبنيها createAll في خطوة v7 (نمط اختبار الترحيلات السابقة).
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
    expect(migrated.schemaVersion, 21);
    final items = await migrated.select(migrated.items).get();
    expect(items, hasLength(1));
    expect(items.first.sku, 'SKU-OLD');

    // بذر الفواتير زُرع فوقها: العملتان والمستودع والصندوق على 1111
    final currencies = await migrated.currenciesOf();
    expect(currencies, hasLength(2));
    expect(currencies[0].code, 'SYP');
    expect(currencies[0].isBase, isTrue);
    final boxId = (await migrated.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final box = (await migrated.cashBoxById(boxId))!;
    expect(box.name, 'الصندوق الرئيسي');
    final mainAccount = await migrated.customSelect(
      "SELECT id FROM accounts WHERE code = '1111'",
    ).getSingle();
    expect(box.accountId, mainAccount.data['id']);

    // والمحرك يعمل فوق المزروع: شراء آجل كامل بأرقام س-52
    final year = await seededYear(migrated);
    final unitId = await migrated.insertUnit(name: 'قطعة');
    final oilId = await migrated.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final supplierId = await migrated.insertParty(
        number: '0002', name: 'مورد الشرق', kind: 'supplier', defaultCurrencyId: 1);
    final warehouseId = (await migrated.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final invId = await migrated.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '$year-03-15',
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 25000)
      ],
    ));
    await migrated.postInvoice(invId);
    expect((await migrated.invoiceById(invId))!.number, '${seqNum(year, 1)}');
    expect(
        await migrated.stockBalanceOf(
            itemId: oilId, warehouseId: warehouseId),
        (10, 250000));

    // والحاجز الثاني حي في القاعدة المهدَّرة
    await expectLater(
      migrated.customStatement(
        'UPDATE stock_balances SET qty_base = -1 WHERE item_id = ?',
        [Variable.withInt(oilId)],
      ),
      throwsA(anything),
    );
  });

  test('الدورة الكاملة (شراء ← بيع ← مردود): الميزان متوازن وثابت المطابقة',
      () async {
    final f = await buildFixture(db);
    await f.purchaseCredit(lines: [f.line(f.oilId, 10, 25000)]);
    final saleId = await f.saleCredit(lines: [f.line(f.oilId, 4, 40000)]);
    await f.saleCash(lines: [f.line(f.oilId, 3, 40000)]);
    await f.saleReturnAgainst(saleId, lines: [f.line(f.oilId, 2, 40000)]);

    final (debit, credit) = await db.trialBalanceTotalsOf();
    expect(debit, credit, reason: 'كل قيد متوازن بالبناء والميزان يتبعه');

    // ثابت المطابقة المخزني (07 §1.10/D-067): رصيد 113 = مجموع القيم
    final acc113 = await accountIdByCode(db, '113');
    final totals = await db.customSelect(
      'SELECT COALESCE(SUM(total_value_minor), 0) AS v, '
      'COALESCE(SUM(qty_base), 0) AS q FROM stock_balances',
    ).getSingle().then((r) => r.data);
    expect(await db.accountBalanceOf(acc113), totals['v']);
    expect(totals['q'], 5, reason: '10 − 4 − 3 + 2 = 5 قطع');
    // التكلفة: خروج 100,000 + 75,000 والمردود نظير متوسطه الجاري 50,000
    // (المخزون عند المردود 3 قطع بـ 75,000 — فالنظير 50,000 لا صفر)
    // فصافي 51 = 125,000 = كلفة الخمس المتباعة فعلاً بلا فرق على 58
    final acc51 = await accountIdByCode(db, '51');
    final acc58 = await accountIdByCode(db, '58');
    expect(await db.accountBalanceOf(acc51), 125000,
        reason: '5 قطع × 25,000 — المردود عاد بنظير متوسطه فلا فرق على 58');
    expect(await db.accountBalanceOf(acc58), 0,
        reason: 'اللقطة تساوي المتوسط الجاري هنا فلا فرق — عكس س-56 حيث المخزون فارغ');
    expect(await db.cashBoxBalanceOf(f.boxId), 120000,
        reason: 'بيع نقدي 3×40,000 = 120,000 — والمردود على الذمة لا الصندوق');
  });
}
