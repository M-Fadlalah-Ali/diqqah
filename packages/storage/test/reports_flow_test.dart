import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart' show Variable;

/// أدوات الدفعة — بنمط voucher_flow_test: معرفات بالبحث بالكود لا
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

Future<int> generalJournalId(DiqqahDatabase db) async {
  final rows = await db.customSelect(
    "SELECT id FROM journals WHERE kind = 'general'",
  ).getSingle();
  return rows.data['id'] as int;
}

Future<int> periodIdByMonth(DiqqahDatabase db, int month) async {
  final year = await seededYear(db);
  final mm = month.toString().padLeft(2, '0');
  final rows = await db.customSelect(
    'SELECT id FROM periods WHERE start_date_text = ?',
    variables: [Variable.withString('$year-$mm-01')],
  ).get();
  expect(rows, hasLength(1), reason: 'بذر السنة شهري كامل');
  return rows.first.data['id'] as int;
}

/// أرضية التقارير — دورة كاملة بأرقام معروفة (نمط voucher_flow_test):
/// ضخ 500,000 فشراء 10×10,000 آجل فبيع 6×15,000 آجل فقبض 50,000
/// بعطلة على فاتورة البيع فتسوية عجز 5,000.
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

  Future<int> receiptFromCustomer({
    required int amount,
    List<VoucherAllocationDraft> allocations = const [],
  }) async {
    final id = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      partyId: customerId,
      cashBoxId: boxId,
      amountDocMinor: amount,
      allocations: allocations,
    ));
    await db.postVoucher(id);
    return id;
  }

  Future<int> cashShortage(int amount) async {
    final id = await db.createCashAdjustmentDraft(CashAdjustmentDraft(
      dateText: date,
      cashBoxId: boxId,
      direction: CashAdjustmentDirection.shortage,
      amountDocMinor: amount,
      reason: 'فرق جرد يومي',
    ));
    await db.postCashAdjustment(id);
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

  test('س-71..س-75 التقارير الخمسة على دورة كاملة بأرقام معروفة', () async {
    final f = await buildFixture(db);
    final oil = f.line(f.oilId, 10, 10000);
    await f.purchaseCredit(lines: [oil]);
    final saleId = await f.saleCredit(lines: [f.line(f.oilId, 6, 15000)]);
    await f.receiptFromCustomer(
      amount: 50000,
      allocations: [VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 50000)],
    );
    await f.cashShortage(5000);

    // ═══ س-71 ميزان المراجعة — متوازن بالبناء وبأرصدة معروفة ═══
    final trial = await db.trialBalanceReport();
    expect(trial.isBalanced, isTrue, reason: 'F-068: متوازن بالبناء');
    expect(trial.totalDebitMinor, 805000);
    expect(trial.totalCreditMinor, 805000);
    final byCode = {for (final r in trial.rows) r.account.code: r};
    expect(byCode.keys, containsAll(['1111', '112', '113', '211', '311', '411', '51', '57']));
    expect(byCode['1111']!.balanceMinor, 545000);
    expect(byCode['112']!.balanceMinor, 40000);
    expect(byCode['113']!.balanceMinor, 40000);
    expect(byCode['211']!.balanceMinor, 100000);
    expect(byCode['311']!.balanceMinor, 500000);
    expect(byCode['411']!.balanceMinor, 90000);
    expect(byCode['51']!.balanceMinor, 60000);
    expect(byCode['57']!.balanceMinor, 5000);

    // ═══ س-72 تقرير الصناديق ═══
    final boxes = await db.cashBoxesReport();
    expect(boxes, hasLength(1));
    expect(boxes.single.accountCode, '1111');
    expect(boxes.single.currencyCode, 'SYP');
    expect(boxes.single.balanceBaseMinor, 545000,
        reason: '500,000 ضخ + 50,000 قبض − 5,000 عجز');
    expect(boxes.single.isActive, isTrue);

    // ═══ س-73 تقرير الذمم بالاتجاهين ═══
    final balances = await db.receivablesPayablesReport();
    expect(balances, hasLength(2));
    final customer = balances.singleWhere((r) => r.partyId == f.customerId);
    expect(customer.direction, PartyBalanceDirection.theyOweUs);
    expect(customer.amountMinor, 40000, reason: '90,000 بيع − 50,000 قبض');
    final supplier = balances.singleWhere((r) => r.partyId == f.supplierId);
    expect(supplier.direction, PartyBalanceDirection.weOweThem);
    expect(supplier.amountMinor, 100000);

    // ═══ س-74 تقرير المخزون ═══
    final inventory = await db.inventoryReport();
    expect(inventory, hasLength(1));
    expect(inventory.single.sku, 'Z-100');
    expect(inventory.single.qtyBase, 4, reason: '10 شراء − 6 بيع');
    expect(inventory.single.totalValueMinor, 40000,
        reason: '100,000 دخول − 60,000 تكلفة خروج');
    expect(inventory.single.avgCostBaseMinor, 10000);
    expect(inventory.single.warehouseName, isNotNull);

    // ═══ س-75 مبيعات وحركة الأصناف بمدى تاريخ ═══
    final movement = await db.salesMovementReport(
      fromText: '${f.year}-01-01',
      toText: '${f.year}-12-31',
    );
    expect(movement, hasLength(1));
    expect(movement.single.qtySoldBase, 6);
    expect(movement.single.salesValueBaseMinor, 90000);
    expect(movement.single.qtyReturnedBase, 0);
    expect(movement.single.netValueBaseMinor, 90000);
    // ومدى لا يشمل الشهر يعطي صفر صفوف لا خطأ
    final empty = await db.salesMovementReport(
      fromText: '${f.year - 1}-01-01',
      toText: '${f.year - 1}-12-31',
    );
    expect(empty, isEmpty);

    // ═══ س-84 تقرير المشتريات المستقل (دفعة 6-ب) — بمرآة الحركة البيعية ═══
    final purchases = await db.purchasesMovementReport(
      fromText: '${f.year}-01-01',
      toText: '${f.year}-12-31',
    );
    expect(purchases, hasLength(1));
    expect(purchases.single.qtyPurchasedBase, 10,
        reason: 'شراء 10×10,000 الآجل من الدورة المعروفة');
    expect(purchases.single.purchasesValueBaseMinor, 100000);
    expect(purchases.single.qtyReturnedBase, 0);
    expect(purchases.single.netValueBaseMinor, 100000,
        reason: 'الصافي مشتق لا مخزن');
    // ومدى لا يشمل الشهر يعطي صفر صفوف لا خطأ
    final emptyPurchases = await db.purchasesMovementReport(
      fromText: '${f.year - 1}-01-01',
      toText: '${f.year - 1}-12-31',
    );
    expect(emptyPurchases, isEmpty);
  });

  test('مدقق المدى يرفض المدى المقلوب قبل لمس القاعدة', () async {
    final year = await seededYear(db);
    await expectLater(
      db.salesMovementReport(fromText: '$year-05-10', toText: '$year-05-01'),
      throwsA(isA<ReportValidationException>()),
    );
    await expectLater(
      db.purchasesMovementReport(fromText: '$year-05-10', toText: '$year-05-01'),
      throwsA(isA<ReportValidationException>()),
    );
  });

  test('س-76/س-77 الإقفال والفك: المسودات والحاجز الثلاث طبقات والسجل',
      () async {
    final f = await buildFixture(db, funded: false);
    final marchId = await periodIdByMonth(db, 3);
    final generalId = await generalJournalId(db);
    final cashId = await accountIdByCode(db, '1111');
    final capitalId = await accountIdByCode(db, '311');

    // مسودتان فوق مارس: قيد عام وسند بغير طرف
    final draftMoveId = await db.createMoveDraft(
      journalId: generalId,
      dateText: '${f.year}-03-10',
      lines: [
        MoveLineDraft(accountId: cashId, debitMinor: 7000, creditMinor: 0),
        MoveLineDraft(accountId: capitalId, debitMinor: 0, creditMinor: 7000),
      ],
    );
    await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: '${f.year}-03-12',
      directAccountId: capitalId,
      cashBoxId: f.boxId,
      amountDocMinor: 3000,
    ));

    final drafts = await db.periodOpenDrafts(marchId);
    expect(drafts, hasLength(2), reason: 'س-20: القائمة تُعرض لطلب الحسم');
    expect(drafts.map((d) => d.docType).toSet(), {'move', 'voucher'});
    expect(drafts.every((d) => d.label.isNotEmpty), isTrue,
        reason: 'المسودة بلا رقم فلقب «مسودة #المعرف»');

    // الرفض الأول: مسودات بلا تأكيد صريح (س-20)
    await expectLater(
      db.closePeriod(marchId, draftsConfirmed: false),
      throwsA(isA<PeriodClosingException>()),
    );

    // الإقفال بتأكيد ترك المسودات معلقة
    await db.closePeriod(marchId, draftsConfirmed: true);
    final periods = await db.ledgerPeriods();
    expect(periods.singleWhere((p) => p.id == marchId).isOpen, isFalse);

    // الإقفال الثاني مرفوض (س-20: لا تُقفل مرتين)
    await expectLater(
      db.closePeriod(marchId, draftsConfirmed: true),
      throwsA(isA<PeriodClosingException>()),
    );

    // الحاجز الأول — المجال: ترحيل القيد المعلق في المقفلة مرفوض
    await expectLater(
      db.postMove(draftMoveId),
      throwsA(predicate((e) => e.toString().contains('مقفلة'))),
    );

    // الحاجز الأول — المجال: ترحيل فاتورة فوق المقفلة مرفوض — والبيع
    // خدمة كي لا يسبق فحص الاكتفاء المخزني عند الحفظ (المنع السالب الموحد)
    final serviceId = await db.insertItem(
        sku: 'SRV-1',
        name: 'صيانة',
        kind: 'service',
        baseUnitId: f.unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 12000,
        priceCurrencyId: 1);
    final draftInvoiceId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: '${f.year}-03-14',
      partyId: f.customerId,
      lines: [f.line(serviceId, 1, 12000)],
    ));
    await expectLater(
      db.postInvoice(draftInvoiceId),
      throwsA(predicate((e) => e.toString().contains('مقفلة'))),
    );

    // الحاجز الثالث — القاعدة: إدراج خام تجاوز المحرك عمداً (نمط القلب)
    await expectLater(
      db.customStatement(
        "INSERT INTO invoices (kind, invoice_date, fx_rate, state, uuid) "
        "VALUES ('invoice_sale', '${f.year}-03-18', 1000000, 'posted', "
        "'raw-closing-inv')",
      ),
      throwsA(predicate((e) => e.toString().contains('فترة مقفلة'))),
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO vouchers (kind, cash_box_id, voucher_date, fx_rate, "
        "state, uuid) VALUES ('receipt', ${f.boxId}, '${f.year}-03-19', "
        "1000000, 'posted', 'raw-closing-vch')",
      ),
      throwsA(predicate((e) => e.toString().contains('فترة مقفلة'))),
    );

    // الفك بلا سبب مرفوض — وبسبب نصي يمرّ ويوثق (س2)
    await expectLater(
      db.openPeriod(marchId, reason: '   '),
      throwsA(isA<PeriodClosingException>()),
    );
    await db.openPeriod(marchId, reason: 'تصحيح خطأ ترحيل بإذن المالك');
    final reopened = await db.ledgerPeriods();
    expect(reopened.singleWhere((p) => p.id == marchId).isOpen, isTrue);

    // والقيد المعلق يُرحَّل بعد الفك بلا أي عائق
    await db.postMove(draftMoveId);

    // أحداث السجل: إقفال وفك بلقطة السبب (D-090 معروض)
    final events = await db.customSelect(
      "SELECT action, payload FROM events WHERE action LIKE 'period_%' "
      'ORDER BY id',
    ).get();
    expect(events, hasLength(2));
    expect(events[0].data['action'], 'period_closed');
    expect(events[1].data['action'], 'period_opened');
    expect(events[1].data['payload'] as String, contains('تصحيح خطأ ترحيل'),
        reason: 'سبب الفك الإلزامي موثق في السجل');
  });

  test('حاجز القيد الخام في المقفلة: مسودة متوازنة ثم ترحيل خام يُحبط',
      () async {
    final f = await buildFixture(db, funded: false);
    final marchId = await periodIdByMonth(db, 3);
    final generalId = await generalJournalId(db);
    final cashId = await accountIdByCode(db, '1111');
    final capitalId = await accountIdByCode(db, '311');
    await db.closePeriod(marchId, draftsConfirmed: true);

    // مسودة خام متوازنة بسطرين — كي يحكم حاجز الإقفال لا حاجز التوازن
    await db.customStatement(
      "INSERT INTO moves (journal_id, date_text, state, number, uuid) "
      "VALUES ($generalId, '${f.year}-03-20', 'draft', '', 'raw-move-1')",
    );
    final moveId = (await db.customSelect(
      "SELECT id FROM moves WHERE uuid = 'raw-move-1'",
    ).getSingle()).data['id'] as int;
    await db.customStatement(
      "INSERT INTO move_lines (move_id, account_id, debit_minor, "
      "credit_minor, uuid) VALUES ($moveId, $cashId, 7000, 0, 'raw-l1'), "
      "($moveId, $capitalId, 0, 7000, 'raw-l2')",
    );
    await expectLater(
      db.customStatement(
        "UPDATE moves SET state = 'posted' WHERE id = $moveId",
      ),
      throwsA(predicate((e) => e.toString().contains('فترة مقفلة'))),
      reason: 'الحاجز الثالث يسبق أي ترحيل خام فوق المقفلة',
    );
  });

  test('ترحيلة 6→9 بقاعدة خام (F-011): حواجز الإقفال تولد فوق قائمة',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v9_mig_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate.db');
    // قاعدة v6 خام بنمط اختبار 6→8 المجرَّب — والسلسلة تمضي 7→8→9
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
    expect(migrated.schemaVersion, 23);

    // والإقفال يعمل فوق المهدَّر: إقفال مارس فإدراج خام يُحبط بحاجز v9
    final marchId = await periodIdByMonth(migrated, 3);
    await migrated.closePeriod(marchId, draftsConfirmed: true);
    final boxId = (await migrated.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final year = await seededYear(migrated);
    await expectLater(
      migrated.customStatement(
        "INSERT INTO vouchers (kind, cash_box_id, voucher_date, fx_rate, "
        "state, uuid) VALUES ('receipt', $boxId, '$year-03-19', 1000000, "
        "'posted', 'raw-mig-vch')",
      ),
      throwsA(predicate((e) => e.toString().contains('فترة مقفلة'))),
    );
  });

  test('س-84 تقرير المشتريات: شراء ومردود شراء والصافي مشتق', () async {
    final f = await buildFixture(db);
    final purchaseId =
        await f.purchaseCredit(lines: [f.line(f.oilId, 10, 10000)]);
    // مردود 3 من الشراء بسعره الأصلي — فالقيمة الدفترية الخارجة تساوي
    // قيمة السطر ولا فرق على 58 (س-05: المردود بسعر التكلفة ذاتها هنا)
    final returnId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchaseReturn,
      dateText: f.date,
      partyId: f.supplierId,
      warehouseId: f.warehouseId,
      originalInvoiceId: purchaseId,
      lines: [f.line(f.oilId, 3, 10000)],
    ));
    await db.postInvoice(returnId);

    final rows = await db.purchasesMovementReport(
      fromText: '${f.year}-01-01',
      toText: '${f.year}-12-31',
    );
    expect(rows, hasLength(1));
    expect(rows.single.qtyPurchasedBase, 10);
    expect(rows.single.purchasesValueBaseMinor, 100000);
    expect(rows.single.qtyReturnedBase, 3);
    expect(rows.single.returnsValueBaseMinor, 30000);
    expect(rows.single.netQtyBase, 7);
    expect(rows.single.netValueBaseMinor, 70000);
  });

}
