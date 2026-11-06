import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 30 (سابعة م2) — لقطة الوحدة والعامل (س-10/D-031،
/// F-032).
///
/// الحدود الموثقة: اللقطة الثلاثية على أسطر الفواتير (unit_id للأساسية
/// المرجعية + unit_level_id لمستوى التعبئة + factor_at_entry بعامل
/// المستوى وقت الإنشاء) مجمّدة بحرس تجميد أسطر المرحّل المحدث v21،
/// والقيمة والمخزون والقيد على qty_base كما هي — والسعر لوحدة
/// الاختيار فقيمة السطر qty × السعر (السير الموثق 06)، والمستوى من
/// مجموعة الصنف حصراً والتحويل بعامله الحالي (الترحيل على ما خُزّن —
/// فاتورة تُرحّل بعد تغيّر العامل تُرفض فتعاد مسودتها)، والإذنان
/// والتحويل والجرد والتجميع تبقى بالوحدة الأساسية (حد صادق معروض).
/// نمط القاعدة `inMemory` ووضع معرفات الحسابات بالكود لا بالثبوت
/// (نمط invoice_flow_test/ledger_test).
Future<int> accountIdByCode(DiqqahDatabase db, String code) async {
  final rows = await db.customSelect(
    'SELECT id FROM accounts WHERE code = ?',
    variables: [Variable.withString(code)],
  ).get();
  expect(rows, hasLength(1), reason: 'كود الدليل $code فريد من البذر');
  return rows.first.data['id'] as int;
}

/// أسطر قيد فاتورة بأعمدتها — نمط moveLinesOf الموثق.
Future<List<Map<String, Object?>>> moveLinesOf(
  DiqqahDatabase db,
  int moveId,
) async {
  final rows = await db.customSelect(
    'SELECT account_id, debit_minor, credit_minor '
    'FROM move_lines WHERE move_id = ? ORDER BY id',
    variables: [Variable.withInt(moveId)],
  ).get();
  return [for (final r in rows) r.data];
}

void main() {
  late DiqqahDatabase db;
  late int unitId;
  late int boxLevelId;
  late int cartonLevelId;
  late int otherLevelId;
  late int itemId;
  late int plainItemId;
  late int warehouseId;
  late int boxId;
  late int supplierId;
  late int customerId;
  late String date;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    unitId = await db.insertUnit(name: 'قطعة');
    final gid = await db.insertUnitGroup(
      name: 'تعبئة الزيت',
      levels: [(name: 'علبة', factor: 12), (name: 'كرتونة', factor: 144)],
    );
    final levels = await db.levelsOfGroup(gid);
    boxLevelId = levels[0].id;
    cartonLevelId = levels[1].id;
    final otherGid = await db.insertUnitGroup(
        name: 'تعبئة أخرى', levels: [(name: 'طبق', factor: 6)]);
    otherLevelId = (await db.levelsOfGroup(otherGid)).single.id;
    itemId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1,
        unitGroupId: gid);
    plainItemId = await db.insertItem(
        sku: 'P-1',
        name: 'صنف بلا مجموعة',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1);
    // أسعار المستويات المخزنة (لقطة الدفعة 27 — آلياً مشتقة).
    await db.saveItemLevelPrices(itemId, [
      (levelId: boxLevelId, salePriceMinor: 480000, purchasePriceMinor: 300000),
      (levelId: cartonLevelId,
          salePriceMinor: 5760000,
          purchasePriceMinor: 3600000),
    ]);
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
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

  /// سطر شراء بالتعبئة — كميات وحدة الاختيار والأساسية بعاملها.
  InvoiceLineDraft boxPurchaseLine({int qty = 2, int? levelId, int? qtyBase}) =>
      InvoiceLineDraft(
          itemId: itemId,
          unitId: unitId,
          qty: qty,
          unitLevelId: levelId ?? boxLevelId,
          qtyBase: qtyBase ?? qty * 12,
          unitPriceMinor: 300000);

  InvoiceLineDraft boxSaleLine({int qty = 1, int? qtyBase}) =>
      InvoiceLineDraft(
          itemId: itemId,
          unitId: unitId,
          qty: qty,
          unitLevelId: boxLevelId,
          qtyBase: qtyBase ?? qty * 12,
          unitPriceMinor: 480000);

  InvoiceLineDraft baseLine(int itemId_, int qty, int price) =>
      InvoiceLineDraft(
          itemId: itemId_, unitId: unitId, qtyBase: qty,
          unitPriceMinor: price);

  test('ترحيلة v21 على قاعدة جديدة: عمود اللقطة وثبات أعمدة القائمة '
      '(unit_id/factor_at_entry كالقائم)', () async {
    final cols = await db.customSelect(
      "SELECT name FROM pragma_table_info('invoice_lines') "
      "WHERE name IN ('unit_id', 'factor_at_entry', 'unit_level_id', 'qty', "
      "'qty_base')",
    ).get();
    expect(cols.map((r) => r.data['name']),
        containsAll(['unit_id', 'factor_at_entry', 'unit_level_id']));
  });

  test('ترحيلة v21 آمنة التكرار: قاعدة v20 تُرقّى بالعمود والمشغل المحدث '
      'والبيانات سليمة (نمط v19 الموثق)', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v30_mig_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate21.db');

    final seeded = DiqqahDatabase(filePath: dbPath);
    final u = await seeded.insertUnit(name: 'قطعة');
    final it = await seeded.insertItem(
        sku: 'M-1',
        name: 'صنف ما قبل الترحيلة',
        kind: 'good',
        baseUnitId: u,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1);
    final sup = await seeded.insertParty(
        number: '0001', name: 'مورد', kind: 'supplier',
        defaultCurrencyId: 1);
    final wh = (await seeded.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final yearRows =
        await seeded.customSelect('SELECT name FROM fiscal_years').get();
    final inv = await seeded.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '${int.parse(yearRows.single.data['name'] as String)}-03-15',
      partyId: sup,
      warehouseId: wh,
      lines: [
        InvoiceLineDraft(
            itemId: it, unitId: u, qtyBase: 5, unitPriceMinor: 1000),
      ],
    ));
    await seeded.postInvoice(inv);
    await seeded.close();

    // تخفيض user_version إلى 20: إعادة الفتح تُجري 20→21 أمامنا —
    // والعمود موجود أصلاً (onCreate كامل) فالحرس pragma يقفز آمناً،
    // والمشغل يعاد بناؤه DROP+CREATE بالصيغة المحدثة.
    final raw = sqlite3.open(dbPath);
    raw.execute('PRAGMA user_version = 20');
    raw.dispose();

    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    expect(migrated.schemaVersion, 23);
    final cols = await migrated.customSelect(
      "SELECT name FROM pragma_table_info('invoice_lines') "
      "WHERE name = 'unit_level_id'",
    ).get();
    expect(cols, hasLength(1));
    // بيانات الأصل سليمة حرفاً والسطر القائم بلا مستوى (الأساسية).
    final rows = await migrated.customSelect(
      'SELECT qty, qty_base, unit_level_id, factor_at_entry '
      'FROM invoice_lines',
    ).getSingle();
    expect(rows.data['qty'], 5);
    expect(rows.data['qty_base'], 5);
    expect(rows.data['unit_level_id'], isNull);
    expect(rows.data['factor_at_entry'], 1);
    // والمشغل المحدث حي: مساس اللقطة على المرحّل يُحبط.
    expect(
      () => migrated.customStatement(
          'UPDATE invoice_lines SET unit_level_id = 1'),
      throwsA(anything),
      reason: 'المشغل المحدث v21 يحرس العمود الجديد',
    );
  });

  test('شراء بالتعبئة: السطر بلقطته الثلاثية والمخزون والقيد على '
      'الأساسية — 2 علبة × 30,000 = 60,000 و24 قطعة بكلفة 2,500', () async {
    final inv = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [boxPurchaseLine()],
    ));
    await db.postInvoice(inv);

    final doc = await db.invoiceById(inv);
    final lines = await db.invoiceLines(inv);
    expect(doc!.totalDocMinor, 600000, reason: '2 × 30,000 — لا 24 × 30,000');
    expect(lines.single.qty, 2);
    expect(lines.single.qtyBase, 24);
    expect(lines.single.unitLevelId, boxLevelId);
    expect(lines.single.factorAtEntry, 12);
    expect(lines.single.unitId, unitId, reason: 'الوحدة المرجعية الأساسية');

    final bal = await db.stockBalanceOf(
        itemId: itemId, warehouseId: warehouseId);
    expect(bal.$1, 24);
    expect(bal.$2, 600000, reason: 'القيمة الإجمالية المستند لا الكمية × '
        'سعر الأساسية');
    expect(bal.$2 ~/ bal.$1, 25000, reason: 'كلفة الوحدة = سعر الشراء '
        'الأساسي المسجل');

    final acc113 = await accountIdByCode(db, '113');
    final acc211 = await accountIdByCode(db, '211');
    final jlines = await moveLinesOf(db, doc.moveId!);
    expect(
      jlines.where((l) => l['account_id'] == acc113).fold(
          0, (s, l) => s + (l['debit_minor'] as int)),
      600000,
    );
    expect(
      jlines.where((l) => l['account_id'] == acc211).fold(
          0, (s, l) => s + (l['credit_minor'] as int)),
      600000,
    );
  });

  test('بيع بالتعبئة: القيمة 1 علبة × 48,000 والخروج 12 قطعة بالامتصاص '
      'والقيد 51/113 بالتكلفة (D-067)', () async {
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [boxPurchaseLine()],
    ));
    await db.postInvoice(purchase);

    final sale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: [boxSaleLine()],
    ));
    await db.postInvoice(sale);

    final doc = await db.invoiceById(sale);
    final lines = await db.invoiceLines(sale);
    expect(doc!.totalDocMinor, 480000, reason: '1 × 48,000 — لا 12 × 48,000');
    expect(lines.single.qty, 1);
    expect(lines.single.qtyBase, 12);
    expect(lines.single.unitLevelId, boxLevelId);
    expect(lines.single.factorAtEntry, 12);

    final bal = await db.stockBalanceOf(
        itemId: itemId, warehouseId: warehouseId);
    expect(bal.$1, 12);
    expect(bal.$2, 300000);

    final acc411 = await accountIdByCode(db, '411');
    final acc51 = await accountIdByCode(db, '51');
    final acc113 = await accountIdByCode(db, '113');
    final jlines = await moveLinesOf(db, doc.moveId!);
    expect(
      jlines.where((l) => l['account_id'] == acc411).fold(
          0, (s, l) => s + (l['credit_minor'] as int)),
      480000,
    );
    expect(
      jlines.where((l) => l['account_id'] == acc51).fold(
          0, (s, l) => s + (l['debit_minor'] as int)),
      300000,
    );
    expect(
      jlines.where((l) => l['account_id'] == acc113).fold(
          0, (s, l) => s + (l['credit_minor'] as int)),
      300000,
    );

    // ولقطة الحدث الكاملة تحمل اللقطة الثلاثية (07 §2.3) — صيغة
    // jsonEncode المدمجة بلا فراغات.
    final snapRows = await db.customSelect(
      "SELECT payload FROM events WHERE entity_type = 'invoice' "
      'AND action = ? AND entity_id = ? ORDER BY id DESC',
      variables: [Variable.withString('posted'), Variable.withInt(sale)],
    ).get();
    final payload = snapRows.first.data['payload'] as String;
    expect(payload, contains('"unit_level_id":$boxLevelId'));
    expect(payload, contains('"qty":1'));
    expect(payload, contains('"factor_at_entry":12'));
  });

  test('مردود بيع بالتعبئة: 1 علبة تعيد 12 قطعة بلقطة تكلفة الأصل والفرق '
      'صفراً (م-25)', () async {
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [boxPurchaseLine()],
    ));
    await db.postInvoice(purchase);
    final sale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: [boxSaleLine()],
    ));
    await db.postInvoice(sale);

    final ret = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.saleReturn,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      originalInvoiceId: sale,
      lines: [boxSaleLine()],
    ));
    await db.postInvoice(ret);

    final doc = await db.invoiceById(ret);
    final lines = await db.invoiceLines(ret);
    expect(doc!.totalDocMinor, 480000);
    expect(lines.single.qty, 1);
    expect(lines.single.qtyBase, 12);
    expect(lines.single.unitLevelId, boxLevelId);

    final bal = await db.stockBalanceOf(
        itemId: itemId, warehouseId: warehouseId);
    expect(bal.$1, 24);
    expect(bal.$2, 600000, reason: 'الاستعادة بلقطة 2,500/قطعة فلا فرق '
        'تقريب ولا 58');

    final acc58 = await accountIdByCode(db, '58');
    final jlines = await moveLinesOf(db, doc.moveId!);
    expect(jlines.where((l) => l['account_id'] == acc58), isEmpty,
        reason: 'المتوسط الجاري يساوي لقطة الأصل فلا سطر فرق');
  });

  test('حرس المستوى: مستوى من مجموعة أخرى وصنف بلا مجموعة والتحويل '
      'المخالف كلها مرفوضة برسائلها المسماة قبل أي كتابة', () async {
    // مستوى مجموعة أخرى على صنف مجموعة الزيت.
    await expectLater(
      db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: date,
        partyId: supplierId,
        warehouseId: warehouseId,
        lines: [boxPurchaseLine(levelId: otherLevelId)],
      )),
      throwsA(isA<InvoiceValidationException>().having(
        (e) => e.errors, 'errors',
        contains(isA<InvoiceUnitLevelInvalid>()),
      )),
    );
    // صنف بلا مجموعة بمستوى تعبئة.
    await expectLater(
      db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: date,
        partyId: supplierId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: plainItemId,
              unitId: unitId,
              qty: 2,
              unitLevelId: boxLevelId,
              qtyBase: 24,
              unitPriceMinor: 1000),
        ],
      )),
      throwsA(isA<InvoiceValidationException>().having(
        (e) => e.errors, 'errors',
        contains(isA<InvoiceUnitLevelInvalid>()),
      )),
    );
    // التحويل المخالف: 2 × 12 لا يساوي 20.
    await expectLater(
      db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: date,
        partyId: supplierId,
        warehouseId: warehouseId,
        lines: [boxPurchaseLine(qtyBase: 20)],
      )),
      throwsA(isA<InvoiceValidationException>().having(
        (e) => e.errors, 'errors',
        contains(isA<InvoiceUnitFactorMismatch>()),
      )),
    );
    final docs = await db.customSelect(
      'SELECT COUNT(*) AS c FROM invoices',
    ).getSingle();
    expect(docs.data['c'], 0, reason: 'الرفض قبل الكتابة حصراً');
  });

  test('العامل تغيّر بعد المسودة قبل الترحيل: الترحيل يرفض على ما خُزّن '
      'ولا رقم يُحرق، وبإصلاح المسودة يمر بأول رقم (07 §1.9)', () async {
    final draft = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [boxPurchaseLine()],
    ));
    // المسودة لا تجمد (F-033) فالعامل حر — والترحيل بعده يفحص المخزن
    // ضد الحالي فيرفض الفاسد.
    await db.updateUnitGroupLevel(boxLevelId, factor: 18);
    await expectLater(
      db.postInvoice(draft),
      throwsA(isA<InvoiceValidationException>().having(
        (e) => e.errors, 'errors',
        contains(isA<InvoiceUnitFactorMismatch>()),
      )),
    );
    // المسودة حرة الحذف — الإصلاح بمسودة جديدة بالعامل الجديد:
    // 2 × 18 = 36 والسعر لوحدة الاختيار كما قُبض من المورد.
    await db.deleteInvoiceDraft(draft);
    final fixed = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [boxPurchaseLine(qtyBase: 36)],
    ));
    await db.postInvoice(fixed);
    final doc = await db.invoiceById(fixed);
    expect(doc!.number, endsWith('000001'),
        reason: 'الرفض لا يحرق الرقم (07 §1.9)');
    final lines = await db.invoiceLines(fixed);
    expect(lines.single.factorAtEntry, 18,
        reason: 'لقطة العامل وقت العملية بعامل المستوى الحالي');
  });

  test('الأساسية كما اعتاد م1 حرفاً: qty مخزنة تساوي qtyBase وبلا مستوى '
      'وعامل 1 — والقراءة القائمة كلها سليمة', () async {
    final inv = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [baseLine(plainItemId, 5, 1000)],
    ));
    await db.postInvoice(inv);
    final lines = await db.invoiceLines(inv);
    expect(lines.single.qty, 5);
    expect(lines.single.qtyBase, 5);
    expect(lines.single.unitLevelId, isNull);
    expect(lines.single.factorAtEntry, 1);
    expect(lines.single.lineTotalDocMinor, 5000);
  });

  test('التجميد على اللقطة: المرحّل لا يعدل مستواه ولا عامله ولا كميته '
      '(نمط F-140 بالمشغل المحدث v21)', () async {
    final inv = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [boxPurchaseLine()],
    ));
    await db.postInvoice(inv);
    final lineId = (await db.customSelect(
      'SELECT id FROM invoice_lines WHERE invoice_id = ?',
      variables: [Variable.withInt(inv)],
    ).getSingle()).data['id'] as int;
    for (final sql in [
      'UPDATE invoice_lines SET unit_level_id = $cartonLevelId '
          'WHERE id = $lineId',
      'UPDATE invoice_lines SET factor_at_entry = 144 '
          'WHERE id = $lineId',
      'UPDATE invoice_lines SET qty = 99 WHERE id = $lineId',
      'UPDATE invoice_lines SET qty_base = 99 WHERE id = $lineId',
      'UPDATE invoice_lines SET unit_price_minor = 1 WHERE id = $lineId',
    ]) {
      await expectLater(db.customStatement(sql), throwsA(anything),
          reason: 'حرس v21 يضم اللقطة كاملة: $sql');
    }
    // وخدمة علم التسليم باقية مسموحة (درس v13 — تحديث جزئي موثق).
    await db.customStatement(
        'UPDATE invoice_lines SET delivered = 1 WHERE id = $lineId');
  });
}
