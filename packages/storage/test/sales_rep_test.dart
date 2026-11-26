import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:drift/drift.dart' show Variable, Value;
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

/// اختبارات دور «مندوب» وبوابة تعليق الفواتير (س101 — كلمة المالك:
/// «زاوية البائع يبيع فوراً والمندوب يعلق، وأعطاء كل واحد صلاحيات
/// مختلفة»): بذر الدور الخامس وضمانه قبل الفتح، وحدث التقديم بهوية
/// المانِح وقراءته بالأحدث فوزاً، وعزل حرس المسودة، وفلتر الحالة
/// بالأرشيف. وس102 — بكلمة المالك: «أريد أن يكون الخيار بيد المستخدم
/// إما أن يكون بيع المندوب يحجز الكمية أم فقط مسودة»: إعداد الحجز
/// في app_meta، وخريطة الحجز المحسوبة من المعلّقات، وخصم الحجز من
/// فحص الاكتفاء بالإنشاء والترحيل واستثناء الفاتورة قيد الاعتماد.
void main() {
  test('الدور الخامس «مندوب» مزروع عند الإنشاء بأذوناته الافتراضية '
      '— والأدوار الأربعة الأولى كما هي', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final roles = await db.select(db.roles).get();
    final rep = roles.where((r) => r.name == 'مندوب');
    expect(rep, hasLength(1));
    // س104 بكلمة المالك «ابدأ بدفعة المندوب 3»: تكتمل يد المندوب بوحدة
    // السندات — قبضه معلق بالوسيط (createHeldVoucher) لا مباشرة.
    expect(rep.single.permissions, 'parties,invoices,vouchers');
    // فاحص الفراغ لا يعيد الزرع فوق القائم
    await db.ensureDefaultRoles();
    expect(
        (await db.select(db.roles).get()).where((r) => r.name == 'مندوب'),
        hasLength(1));
  });

  test('ضمان الأدوار (beforeOpen) يعيد زرع المحذوف بلا مساس بأذونات '
      'القائم المعدلة — بذر صفوف بيان لا مخطط', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // المالك عدّل أذونات «بائع» وحُذف «مندوب» — حالة افتُرِحت للفحص
    final seller = await (db.select(db.roles)
          ..where((r) => r.name.equals('بائع')))
        .getSingle();
    await db.updateRolePermissions(seller.id, 'parties');
    await db.customStatement("DELETE FROM roles WHERE name = 'مندوب'");
    await db.ensureDefaultRoles();
    final roles = await db.select(db.roles).get();
    expect(roles.where((r) => r.name == 'مندوب'), hasLength(1),
        reason: 'النمطي المحذوف يعود قبل الفتح');
    expect(roles.where((r) => r.name == 'بائع'), hasLength(1));
    // والقائم بأذوناته المعدلة كما حفظها المالك لا الافتراضي
    expect(roles.firstWhere((r) => r.name == 'بائع').permissions, 'parties');
  });

  test('حدث التقديم يُكتب بهوية المانِح ويُقرأ بالأحدث فوزاً — '
      'والغائب null والمسودة القديمة بلا حدث null', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-03-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final supplierId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    // أرضية مخزون: شراء مرحّل 10×10,000 كي يمر حرس السالب بمسودة البيع
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

    expect(await db.invoiceSubmissionOf(999999), isNull,
        reason: 'فاتورة غائبة برسالتها لا صمت');
    final draftId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: await db.insertParty(
          number: '0001',
          name: 'عميل الأمل',
          kind: 'customer',
          defaultCurrencyId: 1),
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 2, unitPriceMinor: 40000),
      ],
    ));
    // مسودة بلا حدث تقديم — null (مسودة صاحب صلاحية لا يعلق)
    expect(await db.invoiceSubmissionOf(draftId), isNull);

    await db.recordInvoiceSubmission(draftId,
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    final first = await db.invoiceSubmissionOf(draftId);
    expect(first, isNotNull);
    expect(first!.userId, 7);
    expect(first.userName, 'سالم');
    expect(first.roleName, 'مندوب');

    // تقديم متعاقب (من قام بمراجعة وأعاد الإرسال بدور آخر) — الأحدث فوزاً
    await db.recordInvoiceSubmission(draftId,
        userId: 9, userName: 'وليد', roleName: 'مندوب');
    final latest = await db.invoiceSubmissionOf(draftId);
    expect(latest!.userId, 9);
    expect(latest.userName, 'وليد');
  });

  test('المرحّلة لا تُقدَّم — حرس المسودة يرفض التقديم برسالته', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-03-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final supplierId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 5, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchaseId);
    expect(
      () => db.recordInvoiceSubmission(purchaseId,
          userId: 7, userName: 'سالم', roleName: 'مندوب'),
      throwsA(isA<InvoiceValidationException>()),
    );
  });

  test('فلتر الحالة بالأرشيف: المسودات وحدها تظهر — والمرحّلة لا تختفي '
      'بلا فلتر (س101 لسان المعتمد)', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-03-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final supplierId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    // مرحّلة ومسودة معاً
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 5, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchaseId);
    await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: await db.insertParty(
          number: '0001',
          name: 'عميل الأمل',
          kind: 'customer',
          defaultCurrencyId: 1),
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 2, unitPriceMinor: 40000),
      ],
    ));
    expect(await db.invoicesListReport(), hasLength(2));
    final drafts = await db.invoicesListReport(stateFilter: 'draft');
    expect(drafts, hasLength(1));
    expect(drafts.single.state, 'draft');
    expect(drafts.single.number, isEmpty,
        reason: 'المسودة بلا رقم — الترقيم لحظة الترحيل');
    // أي قيمة أخرى تُسقط كأنها لا فلتر
    expect(await db.invoicesListReport(stateFilter: 'ghost'), hasLength(2));
  });

  test('رقم ووحدة الاستعلام من الستة — لا كسر لأعمدة الفلاتر الخمسة '
      '(حرس ترتيب المتغيرات)', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // استدعاء بكل الفلاتر معاً يمر بلا استثناء SQL
    final rows = await db.invoicesListReport(
      fromText: '2000-01-01',
      toText: '2100-01-01',
      kindStorageValue: 'sale',
      partyId: null,
      receiptFilter: 'undelivered',
      stateFilter: 'draft',
    );
    expect(rows, isEmpty);
  });

  // ═══ س102: خيار المالك «بيع المندوب يحجز الكمية أم مسودة فقط» ═══

  /// أرضية مشهد الحجز: وحدة وبضاعة وطرفان ومستودع ورصيد شراء مرحّل
  /// [stockQty] — نمط أرضيات س101 فوقها (بذرة القاعدة تزرع المستودع).
  Future<({int unitId, int itemId, int customerId, int supplierId,
      int warehouseId, String date})> seedReserveScene(
    DiqqahDatabase db, {
    int stockQty = 10,
  }) async {
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-03-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final supplierId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    final customerId = await db.insertParty(
        number: '0001',
        name: 'عميل الأمل',
        kind: 'customer',
        defaultCurrencyId: 1);
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId,
            unitId: unitId,
            qtyBase: stockQty,
            unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchaseId);
    return (
      unitId: unitId,
      itemId: oilId,
      customerId: customerId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      date: date
    );
  }

  /// معلقة بيع بهوية مندوب — أرضية الحجز نفسها.
  Future<int> seedHeldSale(
    DiqqahDatabase db, {
    required int customerId,
    required int warehouseId,
    required String date,
    required int itemId,
    required int unitId,
    required int qtyBase,
  }) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: qtyBase,
            unitPriceMinor: 40000),
      ],
    ));
    await db.recordInvoiceSubmission(id,
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    return id;
  }

  test('س102: إعداد الحجز — الغائب مطفأ (سلوك س101) والضبط يُقرأ قيمةً '
      'قيمةً في app_meta لا جهاز', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    expect(await db.heldInvoicesReserveQty(), isFalse,
        reason: 'الافتراض المطفأ: مسودة فقط لا مساس بالكمية');
    await db.setHeldInvoicesReserveQty(true);
    expect(await db.heldInvoicesReserveQty(), isTrue);
    await db.setHeldInvoicesReserveQty(false);
    expect(await db.heldInvoicesReserveQty(), isFalse);
  });

  test('س164: إعداد «مسودة أكبر من المتاح» — الغائب مطفأ والضبط قيمةً '
      'قيمةً في app_meta لا جهاز', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    expect(await db.invoiceDraftOverStock(), isFalse,
        reason: 'الافتراض المطفأ: فحص الاكتفاء بالإنشاء باقٍ');
    await db.setInvoiceDraftOverStock(true);
    expect(await db.invoiceDraftOverStock(), isTrue);
    await db.setInvoiceDraftOverStock(false);
    expect(await db.invoiceDraftOverStock(), isFalse);
  });

  test('س164: «مسودة أكبر من المتاح» مطفأً — حفظ مسودة فوق المتاح يُرفض '
      'بفحص الاكتفاء القائم (السلوك القائم لا يُمس افتراضاً)', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final s = await seedReserveScene(db, stockQty: 4);
    try {
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: s.date,
        partyId: s.customerId,
        warehouseId: s.warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: s.itemId, unitId: s.unitId, qtyBase: 5,
              unitPriceMinor: 40000),
        ],
      ));
      fail('كان يجب رفض المسودة فوق المتاح والإعداد مطفأ');
    } on InvoiceValidationException catch (e) {
      expect(e.errors.whereType<InvoiceStockInsufficient>(), hasLength(1));
    }
  });

  test('س164: «مسودة أكبر من المتاح» مفعّلاً — المسودة 6 فوق متاح 4 تُحفظ '
      'بلا فحص (التزام غير معلن) وبقية فحوص البنية باقية، والترحيل يُرفض '
      'صادقاً «من رحّل أولاً غلب» فتُرحّل 4 أو تُحذف', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final s = await seedReserveScene(db, stockQty: 4);
    await db.setInvoiceDraftOverStock(true);
    // الحفظ يمر بلا فحص مخزوني — والمسودة بلا رقم (الترقيم لحظة الترحيل)
    final overId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 6,
            unitPriceMinor: 40000),
      ],
    ));
    final rows = await db.customSelect(
      'SELECT number, state FROM invoices WHERE id = ?',
      variables: [Variable.withInt(overId)],
    ).get();
    expect(rows.single.data['number'], '',
        reason: 'الترقيم لحظة الترحيل حصراً (07 §1.9) — والمسودة بلا رقم');
    expect(rows.single.data['state'], 'draft');
    // والترحيل يُرفض صادقاً — الفحص الحاكم لحظة الترحيل لا الحفظ
    try {
      await db.postInvoice(overId);
      fail('كان يجب رفض ترحيل المسودة فوق المتاح');
    } on InvoiceValidationException catch (e) {
      expect(e.errors.whereType<InvoiceStockInsufficient>(), hasLength(1));
    }
    // وبقية فحوص الإنشاء باقية مع الخيار: بضاعة بلا مستودع تُرفض حرفاً
    try {
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: s.date,
        partyId: s.customerId,
        lines: [
          InvoiceLineDraft(
              itemId: s.itemId, unitId: s.unitId, qtyBase: 1,
              unitPriceMinor: 40000),
        ],
      ));
      fail('كان يجب رفض المسودة بلا مستودع ولو مع الخيار');
    } on InvoiceValidationException catch (e) {
      expect(e.errors.whereType<InvoiceWarehouseMissing>(), hasLength(1));
    }
  });

  test('س164: «مسودة أكبر من المتاح» مع الحجز — المسودة الفوقية تحجز '
      'كامل كميتها (الإفراط حجزٌ لا بيع) فيُرفض ترحيل غيرها بالمتاح '
      'المعلن، وترحيلها بعد التوريد يمر', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final s = await seedReserveScene(db, stockQty: 4);
    await db.setInvoiceDraftOverStock(true);
    await db.setHeldInvoicesReserveQty(true);
    final overId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 6,
            unitPriceMinor: 40000),
      ],
    ));
    // الحجز كامل كميتها الفوقية — 6 لا 4
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 6},
        reason: 'الإفراط حجزٌ لا بيع — اتجاه أمان س102 ذاته');
    // بيع غيرها 1 يُحفظ التزاماً غير معلن — الحفظ بالخيار بلا فحص —
    // وترحيله يُرفض بالمتاح المعلن صفراً (4−6 سالب تصفَّر للإعلان):
    // الحاكم لحظة الترحيل «من رحّل أولاً غلب» والحجز يغلب الإفراط.
    final otherId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 1,
            unitPriceMinor: 40000),
      ],
    ));
    try {
      await db.postInvoice(otherId);
      fail('كان يجب رفض ترحيل بيع غير المسودة والحجز يغلب');
    } on InvoiceValidationException catch (e) {
      final stock =
          e.errors.whereType<InvoiceStockInsufficient>().toList();
      expect(stock, hasLength(1));
      expect(stock.single.availableQty, 0,
          reason: 'الرسالة صادقة: المتاح بعد الحجز لا الرصيد الخام');
    }
    // والالتزام المرفوض الترحيل باقٍ مسودة يحجز كميته — 6+1=7 حجزاً
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 7});
    // التوريد ثم ترحيل الفوقية يمر — 4 + 4 = 8 والبيع 6 يبقى 2
    final supplyId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: s.date,
      partyId: s.supplierId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 4,
            unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(supplyId);
    await db.postInvoice(overId);
    expect(
        (await db.stockBalanceOf(itemId: s.itemId, warehouseId: s.warehouseId))
            .$1,
        2);
  });

  test('س164: ترحيلة v30 — البوابة تلحق بمن كان يعتمد سلفاً عرف «من كان '
      'يعتمد يبقى يعتمد»: المحاسب والأدوار المخصصة حاملة الفواتير تلحق، '
      'والبائع والمندوب لا (حجبهما بالاسم س101)، والنجمة والفارغة لا '
      'تُمسان، والحامل للبوابة يُسقط آمناً', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v30_gate_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate30.db');
    final seeded = DiqqahDatabase(filePath: dbPath);
    // محاكاة حالة ما قبل v30: أدوار بأذونات الجيل 29 حرفاً
    await seeded.customStatement(
        "UPDATE roles SET permissions = 'parties,items,invoices,vouchers,"
        "boxes,reports,ledger,settings' WHERE name = 'محاسب'");
    await seeded.customStatement(
        "INSERT INTO roles (name, permissions, uuid, created_at, updated_at,"
        " is_deleted) VALUES ('مشرف', 'parties,invoices', 'uuid-sup-30', 0,"
        ' 0, 0)');
    await seeded.close();
    // تخفيض user_version إلى 29: إعادة الفتح تجري 29→30 أمامنا
    final raw = sqlite3.open(dbPath);
    raw.execute('PRAGMA user_version = 29');
    raw.dispose();
    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);
    final perms = await migrated.customSelect(
      'SELECT name, permissions FROM roles ORDER BY id',
    ).get();
    String permsOf(String name) => perms
        .map((r) => r.data)
        .firstWhere((r) => r['name'] as String == name)['permissions']
        as String;
    expect(permsOf('محاسب'), contains('invoices.post_others'),
        reason: 'من كان يعتمد يبقى يعتمد');
    expect(permsOf('مشرف'), contains('invoices.post_others'),
        reason: 'دور مخصص حامل الوحدة يلحق');
    expect(permsOf('بائع'), isNot(contains('invoices.post_others')),
        reason: 'حجب الأدوار البيعية بالاسم — والمنح بيد المالك');
    expect(permsOf('مندوب'), isNot(contains('invoices.post_others')));
    expect(permsOf('مدير'), '*',
        reason: 'النجمة لا تُمس — تشمل البوابة أصلاً');
    expect(permsOf('أمين مستودع'), isNot(contains('invoices.post_others')),
        reason: 'بلا وحدة الفواتير فلا بوابة');
  });

  test('س164: خريطة الحجز من مسودات البيع كلها (الحجز بتابع المسودة لا التعليق) — والمرحّل والمحذوف والخدمة ومستودع آخر لا يحجزون', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final s = await seedReserveScene(db);
    final svcId = await db.insertItem(
        sku: 'S-900',
        name: 'تركيب منزلي',
        kind: 'service',
        baseUnitId: s.unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 5000,
        priceCurrencyId: 1);
    // معلقة: بضاعة 2 + خدمة 3 — تحجز البضاعة وحدها
    final heldId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 2,
            unitPriceMinor: 40000),
        InvoiceLineDraft(
            itemId: svcId, unitId: s.unitId, qtyBase: 3,
            unitPriceMinor: 5000),
      ],
    ));
    await db.recordInvoiceSubmission(heldId,
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 2},
        reason: 'الخدمة لا مخزون لها فلا حجز عليها (س-08)');
    // المسودة العادية بلا حدث تحجز الآن (س164) — الحجز بتابع المسودة
    await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 1,
            unitPriceMinor: 40000),
      ],
    ));
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 3});
    // المرحّل لا يحجز: بيع مباشر 3 وترحيل — والحجز باقٍ 3 (المسودتان)
    final directId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 3,
            unitPriceMinor: 40000),
      ],
    ));
    await db.postInvoice(directId);
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 3});
    // مستودع آخر يحجز بحسابه وحده — بذرة رصيد له أولاً (حرس السالب
    // بالإنشاء قائم دائماً لا بالإعداد)
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.customStatement(
      'INSERT INTO warehouses (name, is_active, uuid, created_at, '
      'updated_at, is_deleted) VALUES (?, 1, ?, ?, ?, 0)',
      ['مستودع الفرع', 'uuid-wid2-test', now, now],
    );
    final wid2 = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id DESC LIMIT 1',
    ).getSingle()).data['id'] as int;
    final purchase2 = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: s.date,
      partyId: s.supplierId,
      warehouseId: wid2,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 5,
            unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchase2);
    await seedHeldSale(db,
        customerId: s.customerId,
        warehouseId: wid2,
        date: s.date,
        itemId: s.itemId,
        unitId: s.unitId,
        qtyBase: 4);
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 3});
    expect(await db.heldSaleReservationsByItem(warehouseId: wid2),
        {s.itemId: 4});
    // والحذف يفك الحجز — قراءة محسوبة لا حالة تُنسى
    await db.customStatement(
        'UPDATE invoices SET is_deleted = 1 WHERE id = ?', [heldId]);
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 1},
        reason: 'حذف المعلقة يفك حجزها — ومسودة العادية باقية بحجزها');
  });

  test('س102: بالإعداد المعتمد يحجز المعلق — بيع مباشر 5 فوق متاح 4 '
      'يُرفض بالمتاح المعلن، والبيع 4 يمر، واعتماد المعلقة نفسها يمر '
      'لاعفائها من حجزها القديم', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final s = await seedReserveScene(db, stockQty: 10);
    await db.setHeldInvoicesReserveQty(true);
    final heldId = await seedHeldSale(db,
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        date: s.date,
        itemId: s.itemId,
        unitId: s.unitId,
        qtyBase: 6);
    // البيع المباشر 5 > 10−6=4 يُرفض والخطأ يقول المتاح بعد الحجز
    try {
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: s.date,
        partyId: s.customerId,
        warehouseId: s.warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: s.itemId, unitId: s.unitId, qtyBase: 5,
              unitPriceMinor: 40000),
        ],
      ));
      fail('كان يجب رفض البيع فوق الحجز');
    } on InvoiceValidationException catch (e) {
      final stock =
          e.errors.whereType<InvoiceStockInsufficient>().toList();
      expect(stock, hasLength(1));
      expect(stock.single.availableQty, 4,
          reason: 'الرسالة صادقة: المتاح بعد الحجز لا الرصيد الخام');
    }
    // والبيع 4 يمر إنشاءً وترحيلاً — الرصيد 6
    final directId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 4,
            unitPriceMinor: 40000),
      ],
    ));
    await db.postInvoice(directId);
    expect(
        (await db.stockBalanceOf(itemId: s.itemId, warehouseId: s.warehouseId))
            .$1,
        6);
    // اعتماد المعلقة 6 يمر — حجزها استُثني (تحرر إلى خصم فعلي)
    await db.postInvoice(heldId);
    expect(
        (await db.stockBalanceOf(itemId: s.itemId, warehouseId: s.warehouseId))
            .$1,
        0);
  });

  test('س102: بالإعداد المطفأ لا حجز — البيع 5 يمر فوق معلقة 6 '
      '(سلوك س101: من رحّل أولاً غلب)، واعتماد المعلقة يُرفض صادقاً '
      'لنقص الرصيد — والنتيجة موثقة لا مختقاة', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final s = await seedReserveScene(db, stockQty: 10);
    final heldId = await seedHeldSale(db,
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        date: s.date,
        itemId: s.itemId,
        unitId: s.unitId,
        qtyBase: 6);
    // الإعداد مطفأ: البيع المباشر 5 يمر (الفحص على الرصيد الخام)
    final directId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: s.date,
      partyId: s.customerId,
      warehouseId: s.warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: s.itemId, unitId: s.unitId, qtyBase: 5,
            unitPriceMinor: 40000),
      ],
    ));
    await db.postInvoice(directId);
    expect(
        (await db.stockBalanceOf(itemId: s.itemId, warehouseId: s.warehouseId))
            .$1,
        5);
    // واعتماد المعلقة 6 يُرفض — النتيجة الصادقة لمبيع غلب الحجز
    expect(() => db.postInvoice(heldId),
        throwsA(isA<InvoiceValidationException>()));
  });

  test('س102: معلقة ثانية لا تتراكم فوق الحجز — 5 فوق متاح 4 تُرفض '
      'بالإنشاء، ومعلقة 4 تمر فيصير الحجز الكلي 10', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final s = await seedReserveScene(db, stockQty: 10);
    await db.setHeldInvoicesReserveQty(true);
    await seedHeldSale(db,
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        date: s.date,
        itemId: s.itemId,
        unitId: s.unitId,
        qtyBase: 6);
    expect(
        () => db.createInvoiceDraft(InvoiceDraft(
              kind: InvoiceKind.sale,
              dateText: s.date,
              partyId: s.customerId,
              warehouseId: s.warehouseId,
              lines: [
                InvoiceLineDraft(
                    itemId: s.itemId, unitId: s.unitId, qtyBase: 5,
                    unitPriceMinor: 40000),
              ],
            )),
        throwsA(isA<InvoiceValidationException>()),
        reason: 'لا تراكم مطالبات فوق المخزون بالحجز');
    final held2 = await seedHeldSale(db,
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        date: s.date,
        itemId: s.itemId,
        unitId: s.unitId,
        qtyBase: 4);
    expect(held2, greaterThan(0));
    expect(await db.heldSaleReservationsByItem(warehouseId: s.warehouseId),
        {s.itemId: 10});
  });

  test('س102: حجز التجميعي على الجاهز — معلق 8 من جاهز 10 يدفع بيع 9 '
      'إلى الفكك فتُرفض الوصفة الفارغة، وبالإعداد المطفأ الجاهز يكفي '
      'ويخرج 9 جاهزة', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-03-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final bundleId = await db.insertItem(
        sku: 'B-700',
        name: 'سلة هدايا',
        kind: 'bundle',
        baseUnitId: unitId,
        purchasePriceMinor: 30000,
        salePriceMinor: 50000,
        priceCurrencyId: 1);
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final supplierId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    final customerId = await db.insertParty(
        number: '0001',
        name: 'عميل الأمل',
        kind: 'customer',
        defaultCurrencyId: 1);
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: bundleId,
            unitId: unitId,
            qtyBase: 10,
            unitPriceMinor: 30000),
      ],
    ));
    await db.postInvoice(purchaseId);
    await db.setHeldInvoicesReserveQty(true);
    await seedHeldSale(db,
        customerId: customerId,
        warehouseId: warehouseId,
        date: date,
        itemId: bundleId,
        unitId: unitId,
        qtyBase: 8);
    // بيع 9 > 10−8=2 جاهز → فكك بلا وصفة → رفض صادق
    expect(
        () => db.createInvoiceDraft(InvoiceDraft(
              kind: InvoiceKind.sale,
              dateText: date,
              partyId: customerId,
              warehouseId: warehouseId,
              lines: [
                InvoiceLineDraft(
                    itemId: bundleId, unitId: unitId, qtyBase: 9,
                    unitPriceMinor: 50000),
              ],
            )),
        throwsA(isA<InvoiceValidationException>()));
    // والإعداد المطفأ: الجاهز 10 يكفي 9 مباشرة (سلوك الدفعة 28 القائم)
    await db.setHeldInvoicesReserveQty(false);
    final directId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: bundleId, unitId: unitId, qtyBase: 9,
            unitPriceMinor: 50000),
      ],
    ));
    await db.postInvoice(directId);
    expect(
        (await db.stockBalanceOf(
                itemId: bundleId, warehouseId: warehouseId))
            .$1,
        1,
        reason: 'خرجت 9 جاهزة بلا فكك — لا حجز بالإعداد المطفأ');
  });

  // س104 — دفعة المندوب الثالثة: اختبارات القبض المعلق بالوسيط والعهدة.
  runHeldCollectionTests();
}

// ═══════════════════════════════════════════════════════════════════
// س104 — دفعة المندوب الثالثة (كلمة المالك: «ابدأ بدفعة المندوب 3»):
// القبض المعلق بالحساب الوسيط «تحصيلات في الطريق» (116) وبعهدة المندوب.
// ═══════════════════════════════════════════════════════════════════

/// أرضية القبض المعلق: بذرة دورة معروفة — صندوق أساسي بمبلغ افتتاحي،
/// عميل بفاتورة بيع مرحّلة بقيمة 60,000 — يعاد بناؤها لكل اختبار.
class _HoldFixture {
  final int date;
  final int customerId;
  final int saleInvoiceId;
  final int boxId;

  const _HoldFixture({
    required this.date,
    required this.customerId,
    required this.saleInvoiceId,
    required this.boxId,
  });
}

Future<_HoldFixture> _holdFixture(DiqqahDatabase db) async {
  final yearRows =
      await db.customSelect('SELECT name FROM fiscal_years').get();
  final date = '${yearRows.single.data['name'] as String}-04-10';
  final unitId = await db.insertUnit(name: 'قطعة');
  final oilId = await db.insertItem(
      sku: 'Z-100',
      name: 'زيت محلي',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 25000,
      salePriceMinor: 30000,
      priceCurrencyId: 1);
  final warehouseId = (await db.customSelect(
    'SELECT id FROM warehouses ORDER BY id LIMIT 1',
  ).getSingle()).data['id'] as int;
  final supplierId = await db.insertParty(
      number: '0002',
      name: 'مورد الشرق',
      kind: 'supplier',
      defaultCurrencyId: 1);
  // أرضية مخزون: شراء مرحّل 10×10,000 ثم بيع مرحّل 2×30,000 = 60,000
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
  final customerId = await db.insertParty(
      number: '0001',
      name: 'عميل الأمل',
      kind: 'customer',
      defaultCurrencyId: 1);
  final saleId = await db.createInvoiceDraft(InvoiceDraft(
    kind: InvoiceKind.sale,
    dateText: date,
    partyId: customerId,
    warehouseId: warehouseId,
    lines: [
      InvoiceLineDraft(
          itemId: oilId, unitId: unitId, qtyBase: 2, unitPriceMinor: 30000),
    ],
  ));
  await db.postInvoice(saleId);
  final boxId = await db.createCashBox(name: 'الصندوق المعتمد', currencyId: 1);
  return _HoldFixture(
      date: 0,
      customerId: customerId,
      saleInvoiceId: saleId,
      boxId: boxId);
}

Future<VoucherDraft> _holdDraft(
  DiqqahDatabase db,
  _HoldFixture f, {
  int amount = 60000,
  List<VoucherAllocationDraft>? allocations,
}) async {
  final yearRows =
      await db.customSelect('SELECT name FROM fiscal_years').get();
  final date = '${yearRows.single.data['name'] as String}-04-10';
  return VoucherDraft(
    kind: VoucherKind.receipt,
    dateText: date,
    partyId: f.customerId,
    cashBoxId: f.boxId,
    currencyId: 1,
    fxRate: baseCurrencyFxRate,
    amountDocMinor: amount,
    allocations: allocations ??
        [VoucherAllocationDraft(invoiceId: f.saleInvoiceId, appliedDocMinor: amount)],
  );
}

void runHeldCollectionTests() {
  test('حساب الطريق 116 مبذور بالبذرة الأولى وضمانه يعيد المحذوف '
      'والقائم بالكود لا يُمس — بذر بيان لا مخطط', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final acc = await (db.select(db.accounts)
          ..where((t) => t.code.equals('116')))
        .getSingle();
    expect(acc.name, 'تحصيلات في الطريق (عهدة المندوبين)');
    expect(acc.type, 'asset');
    expect(acc.normalSide, 'debit');
    expect(acc.isLeaf, true);
    expect(acc.isActive, true);
    // المالك يعيد تسميته ويحذفه — الضمان يعيده بالكود والقائم لم يُمس بالاسم
    await (db.update(db.accounts)
          ..where((t) => t.code.equals('116')))
        .write(const AccountsCompanion().copyWith(name: const Value('حسابي الخاص')));
    await db.customStatement("DELETE FROM accounts WHERE code = '116'");
    await db.ensureTransitAccount();
    final restored = await (db.select(db.accounts)
          ..where((t) => t.code.equals('116')))
        .getSingleOrNull();
    expect(restored, isNotNull);
    expect(restored!.name, 'تحصيلات في الطريق (عهدة المندوبين)');
  });

  test('التحصيل المعلق يُقيد لحظة الحفظ على حساب الطريق: مدين 116 '
      'كامل المبلغ / دائن 112 بالمطابقة — وتصفو ذمة العميل بوقوع القبض '
      'ولا صندوق ولا رقم ولا حركة نقد', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    final id = await db.createHeldVoucher(await _holdDraft(db, f),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    final v = await db.voucherById(id);
    expect(v!.state, 'held');
    expect(v.number, isEmpty, reason: 'الترقيم لحظة الاعتماد حصراً (07 §1.9)');
    expect(v.moveId, isNotNull, reason: 'قيد الطريق مقيد لحظة الحفظ');
    // قيد الطريق: مدين 116 بكل المبلغ / دائن 112 بالمطابقة
    final lines = await db.customSelect(
      'SELECT ml.account_id AS aid, a.code AS code, ml.debit_minor AS d, '
      'ml.credit_minor AS c, ml.party_id AS pid FROM move_lines ml '
      'JOIN accounts a ON a.id = ml.account_id '
      'WHERE ml.move_id = ? ORDER BY ml.id',
      variables: [Variable.withInt(v.moveId!)],
    ).get();
    final transitLine = lines.firstWhere((r) => r.data['code'] == '116');
    expect(transitLine.data['d'], 60000);
    expect(transitLine.data['c'], 0);
    final partyLine = lines.firstWhere((r) => r.data['code'] == '112');
    expect(partyLine.data['c'], 60000);
    expect(partyLine.data['pid'], f.customerId);
    // ذمة العميل صفت بوقوع القبض — الفاتورة «مدفوعة» قبل أي اعتماد
    final inv = await db.invoiceById(f.saleInvoiceId);
    expect(inv!.state, 'paid');
    // لا حركة نقد — الصندوق لم يُمس
    final movements = await db.customSelect(
      "SELECT COUNT(*) c FROM cash_movements WHERE ref_doc_type = 'voucher' "
      'AND ref_doc_id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle();
    expect(movements.data['c'], 0);
    // أحداث الحفظ: created + submitted_for_approval بهوية المانِح
    expect(await db.voucherSubmissionOf(id), isNotNull);
    final sub = await db.voucherSubmissionOf(id);
    expect(sub!.userName, 'سالم');
    expect(sub.roleName, 'مندوب');
  });

  test('التغطية تشمل المعلق: مطالبة ثانية فوق المتبقي تُرفض — '
      'التحصيل وقع بيد المندوب فلا يُطالَب به ثانية', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    await db.createHeldVoucher(await _holdDraft(db, f, amount: 40000),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    // مطالبة ثانية بـ30,000 فوق متبقٍ 20,000 — ترفض بلسان المدقق
    await expectLater(
      db.createHeldVoucher(
          await _holdDraft(db, f, amount: 30000,
              allocations: [
                VoucherAllocationDraft(
                    invoiceId: f.saleInvoiceId, appliedDocMinor: 30000),
              ]),
          userId: 7,
          userName: 'سالم',
          roleName: 'مندوب'),
      throwsA(isA<VoucherValidationException>()),
    );
    // والباقي 20,000 يمر
    final second = await db.createHeldVoucher(
        await _holdDraft(db, f, amount: 20000,
            allocations: [
              VoucherAllocationDraft(
                  invoiceId: f.saleInvoiceId, appliedDocMinor: 20000),
            ]),
        userId: 7,
        userName: 'سالم',
        roleName: 'مندوب');
    expect((await db.voucherById(second))!.state, 'held');
  });

  test('حراس التعليق: سند الدفع يُرفض والقبض بغير طرف يُرفض — '
      'بلا لسان خطأ غامض', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-04-10';
    // سند دفع بالمبلغ — لا يُعلَّق بيد المندوب
    await expectLater(
      db.createHeldVoucher(
        VoucherDraft(
          kind: VoucherKind.payment,
          dateText: date,
          partyId: f.customerId,
          cashBoxId: f.boxId,
          amountDocMinor: 1000,
        ),
        userId: 7,
        userName: 'سالم',
        roleName: 'مندوب',
      ),
      throwsA(isA<VoucherValidationException>()),
    );
    // قبض بغير طرف على حساب مباشر — لا يمر بحساب الطريق
    await expectLater(
      db.createHeldVoucher(
        VoucherDraft(
          kind: VoucherKind.receipt,
          dateText: date,
          directAccountId: (await db.customSelect(
                  "SELECT id FROM accounts WHERE code = '311'")
              .get())
              .single
              .data['id'] as int,
          cashBoxId: f.boxId,
          amountDocMinor: 1000,
        ),
        userId: 7,
        userName: 'سالم',
        roleName: 'مندوب',
      ),
      throwsA(isA<VoucherValidationException>()),
    );
  });

  test('الاعتماد يسلّم للصندوق: رقم من تسلسل القبض وقيد صندوق مدين 1111 '
      'دائن 116 وحركة نقد داخل ورصيد الصندوق زاد والعهدة خرجت', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    final id = await db.createHeldVoucher(await _holdDraft(db, f),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    final custodyBefore = await db.heldReceiptCustody();
    expect(custodyBefore, hasLength(1));
    expect(custodyBefore.single.totalBaseMinor, 60000);
    final boxRow = await db.customSelect(
      'SELECT balance FROM (SELECT cb.id, '
      'COALESCE((SELECT SUM(CASE WHEN cm.kind IN (\'in\',\'transfer_in\') '
      'THEN cm.amount_base_minor ELSE -cm.amount_base_minor END) '
      'FROM cash_movements cm WHERE cm.cash_box_id = cb.id), 0) AS balance '
      'FROM cash_boxes cb WHERE cb.id = ?)',
      variables: [Variable.withInt(f.boxId)],
    ).getSingle();
    final balanceBefore = boxRow.data['balance'] as int;

    await db.approveHeldVoucher(id);

    final v = await db.voucherById(id);
    expect(v!.state, 'posted');
    expect(v.number, isNotEmpty, reason: 'الرقم لحظة الاعتماد (07 §1.9)');
    // قيد الصندوق: مدين حساب الصندوق / دائن 116 — وقيد الطريق باقٍ
    final approvalLines = await db.customSelect(
      'SELECT a.code AS code, ml.debit_minor AS d, ml.credit_minor AS c '
      'FROM move_lines ml JOIN accounts a ON a.id = ml.account_id '
      'WHERE ml.move_id = ? ORDER BY ml.id',
      variables: [Variable.withInt(v.moveId!)],
    ).get();
    expect(approvalLines.map((r) => r.data['code']), containsAll(['116', '1112']));
    final movement = await db.customSelect(
      "SELECT kind FROM cash_movements WHERE ref_doc_type = 'voucher' "
      'AND ref_doc_id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle();
    expect(movement.data['kind'], 'in');
    final boxAfter = await db.customSelect(
      'SELECT COALESCE((SELECT SUM(CASE WHEN cm.kind IN (\'in\',\'transfer_in\') '
      'THEN cm.amount_base_minor ELSE -cm.amount_base_minor END) '
      'FROM cash_movements cm WHERE cm.cash_box_id = cb.id), 0) AS balance '
      'FROM cash_boxes cb WHERE cb.id = ?',
      variables: [Variable.withInt(f.boxId)],
    ).getSingle();
    expect(boxAfter.data['balance'] as int, balanceBefore + 60000);
    // والعهدة خرجت — لا معلق بعده
    expect(await db.heldReceiptCustody(), isEmpty);
  });

  test('الرفض يعكس قيد الطريق حرفاً: دائن 116 ومدين 112 وذمة العميل '
      'تعود «مرحّلة» وحالة السند rejected ولا يحذف', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    final id = await db.createHeldVoucher(await _holdDraft(db, f),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    await db.rejectHeldVoucher(id,
        userId: 9, userName: 'وليد', roleName: 'مدير', reason: 'لم يصل النقد');
    final v = await db.voucherById(id);
    expect(v!.state, 'rejected');
    // العكس: دائن 116 كامل المبلغ ومدين 112 بالمطابقة
    final reversalLines = await db.customSelect(
      'SELECT a.code AS code, ml.debit_minor AS d, ml.credit_minor AS c '
      'FROM move_lines ml JOIN accounts a ON a.id = ml.account_id '
      "JOIN moves m ON m.id = ml.move_id WHERE m.narration LIKE 'عكس تحصيل%' "
      'ORDER BY ml.id',
    ).get();
    final transitRev = reversalLines.firstWhere((r) => r.data['code'] == '116');
    expect(transitRev.data['c'], 60000);
    final partyRev = reversalLines.firstWhere((r) => r.data['code'] == '112');
    expect(partyRev.data['d'], 60000);
    // ذمة العميل عادت — الفاتورة مرحّلة مفتوحة من جديد
    final inv = await db.invoiceById(f.saleInvoiceId);
    expect(inv!.state, 'posted');
    // والعهدة خرجت والمرفض لا يحذف (حاجز غير المسودة)
    expect(await db.heldReceiptCustody(), isEmpty);
    await expectLater(db.deleteVoucherDraft(id), throwsA(anything));
  });

  test('عهدة مندوبين: صفان باسمَي مقدمَي التحصيل — والمرفوض والمعتمد '
      'يخرجان من العهدة ويبقى المعلق', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-04-10';
    // مندوبان بتحصيلَين: سالم 40,000 مطابقاً وخالد 20,000 رصيداً مقدماً
    final first = await db.createHeldVoucher(
        await _holdDraft(db, f, amount: 40000,
            allocations: [
              VoucherAllocationDraft(
                  invoiceId: f.saleInvoiceId, appliedDocMinor: 40000),
            ]),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    final second = await db.createHeldVoucher(
        VoucherDraft(
          kind: VoucherKind.receipt,
          dateText: date,
          partyId: f.customerId,
          cashBoxId: f.boxId,
          currencyId: 1,
          fxRate: baseCurrencyFxRate,
          amountDocMinor: 20000,
          allocations: const [],
        ),
        userId: 8, userName: 'خالد', roleName: 'مندوب');
    var custody = await db.heldReceiptCustody();
    expect(custody, hasLength(2));
    final total = custody.fold<int>(0, (s, r) => s + r.totalBaseMinor);
    expect(total, 60000);
    // اعتماد الأول يخرجه والرفض الثاني يخرجه فتخلو العهدة
    await db.approveHeldVoucher(first);
    await db.rejectHeldVoucher(second,
        userId: 9, userName: 'وليد', roleName: 'مدير');
    custody = await db.heldReceiptCustody();
    expect(custody, isEmpty);
  });

  test('حرس الحالة: الترحيل العادي على المعلق يُرفض والاعتماد على غير '
      'المعلق يُرفض — وفلتر الحالة بالقائمة يعرض المعلق حصراً', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    final id = await db.createHeldVoucher(await _holdDraft(db, f),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    // postVoucher العادي على المعلق — مساره الاعتماد حصراً
    await expectLater(db.postVoucher(id), throwsA(anything));
    await expectLater(db.approveHeldVoucher(999999), throwsA(anything));
    // فلتر الحالة: المعلقة حصراً ثم المرحّلة بعد الاعتماد
    var held = await db.vouchersListReport(stateFilter: 'held');
    expect(held, hasLength(1));
    expect(held.single.state, 'held');
    expect(held.single.displayLabel, contains('معلّق في الطريق'));
    await db.approveHeldVoucher(id);
    held = await db.vouchersListReport(stateFilter: 'held');
    expect(held, isEmpty, reason: 'المعتمد خرج من الطريق');
    final posted = await db.vouchersListReport(stateFilter: 'posted');
    expect(posted, hasLength(1));
    expect(posted.single.state, 'posted');
  });

  // ═══════════════════════════════════════════════════════════════
  // س105 — دفعة المندوب الرابعة: سقف العهدة وأعمارها (إعداد app_meta
  // بلا ترحيلة والفرض عند التعليق حصراً والقراءة المحسوبة تُلحق
  // طابعي أقدم التقديم وأحدثه).
  // ═══════════════════════════════════════════════════════════════

  test('س105: سقف العهدة إعداد منشأة — الغائب والفاسد بلا سقف '
      'والسالب يُرفض والحفظ والقراءة رحلة ذهاب وعودة والصفر قيمة '
      'ظاهرة', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // الغائب بلا سقف — سلوك س104 القائم افتراضاً
    expect(await db.heldReceiptCustodyCap(), 0);
    // الحفظ والقراءة رحلة ذهاب وعودة
    await db.setHeldReceiptCustodyCap(80000);
    expect(await db.heldReceiptCustodyCap(), 80000);
    // الصفر قيمة ظاهرة بلسان «بلا سقف» لا مفتاحاً محذوفاً
    await db.setHeldReceiptCustodyCap(0);
    final row = await db.customSelect(
      "SELECT value FROM app_meta WHERE key = 'vouchers.custody_cap_minor'",
    ).getSingle();
    expect(row.data['value'], '0');
    expect(await db.heldReceiptCustodyCap(), 0);
    // الفاسد كالغائب (D-169) — لا حدّ يُخترع من فساد
    await db.customStatement(
      "UPDATE app_meta SET value = 'ألف ليلة' "
      "WHERE key = 'vouchers.custody_cap_minor'",
    );
    expect(await db.heldReceiptCustodyCap(), 0);
    // السالب رفض صادق قبل أي كتابة
    expect(() => db.setHeldReceiptCustodyCap(-5), throwsArgumentError);
  });

  test('س105: السقف يُفرض عند التعليق حصراً — التجاوز يُرفض بلسانه '
      'بأرقامه الثلاثة والاعتماد يُفرغ العهدة فيمر التالي', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    await db.setHeldReceiptCustodyCap(80000);
    // أول تحصيل 60,000 تحت سقف 80,000 — يمر
    final first = await db.createHeldVoucher(await _holdDraft(db, f),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    expect(first, greaterThan(0));
    // ثانٍ 30,000 — العهدة 60,000 + الجديد 30,000 = 90,000 فوق 80,000
    // (بلا مطابقات — الفاتورة مغطاة كلياً بالتعليق فحرسها يسبق السقف
    // والمقصود بوابة السقف ذاتها)
    try {
      await db.createHeldVoucher(
          await _holdDraft(db, f, amount: 30000, allocations: const []),
          userId: 7, userName: 'سالم', roleName: 'مندوب');
      fail('لازم يُرفض تجاوز السقف');
    } on VoucherValidationException catch (e) {
      final err = e.errors.single;
      expect(err, isA<VoucherCustodyCapExceeded>());
      final cap = err as VoucherCustodyCapExceeded;
      expect(cap.custodyBaseMinor, 60000, reason: 'عهدته الحالية');
      expect(cap.capBaseMinor, 80000, reason: 'سقف المنشأة');
      expect(cap.incomingBaseMinor, 30000, reason: 'الجديد محولاً للأساسية');
      expect(describeVoucherValidationError(err), contains('تجاوز سقف العهدة'));
    }
    // الاعتماد يُخرج من العهدة فيمر التحصيل التالي — الفرض عند
    // التعليق حصراً فلا يمنع السقفُ اعتماداً ولا رفضاً
    await db.approveHeldVoucher(first);
    expect(await db.heldCustodyTotalOf(7), 0);
    final second = await db.createHeldVoucher(
        await _holdDraft(db, f, amount: 30000,
            allocations: const []),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    expect(second, greaterThan(0), reason: 'بعد التسليم صار التحت السقف');
  });

  test('س105: السقف لكل مانح بعينه — عهدة سالم لا تحصّل على بلال '
      'ولا تمنعه، وحساب العهدة بهوية آخر تقديم لا بالمستخدم الحالي',
      () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    await db.setHeldReceiptCustodyCap(80000);
    // سالم يملك عهدة 60,000
    await db.createHeldVoucher(await _holdDraft(db, f, amount: 60000),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    // بلال يحصّل بفرع آخر — عهدته صفر فراقته 80,000 كاملة فيمر 60,000
    final bilal = await db.createHeldVoucher(
        await _holdDraft(db, f, amount: 60000,
            allocations: const []),
        userId: 9, userName: 'بلال', roleName: 'مندوب');
    expect(bilal, greaterThan(0));
    // وبلال فوق السقف هو أيضاً — عهدته 60,000 والجديد 30,000
    try {
      await db.createHeldVoucher(
          await _holdDraft(db, f, amount: 30000, allocations: const []),
          userId: 9, userName: 'بلال', roleName: 'مندوب');
      fail('لازم يُرفض تجاوز بلال للسقف');
    } on VoucherValidationException catch (e) {
      final cap = e.errors.single as VoucherCustodyCapExceeded;
      expect(cap.custodyBaseMinor, 60000,
          reason: 'عهدة بلال هو لا عهدة سالم (120,000 لو جمعا)');
    }
  });

  test('س105: أعمار العهدة من طوابع التقديم — أقدم الصف وأحدثه '
      'بالقراءة المحسوبة والاعتماد يُخرج الأقدم فيصير الباقي هو '
      'الأقدم والأحدث', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final f = await _holdFixture(db);
    // تحصيلان لسالم بفرق زمني محسوس — الأول أقدم
    final older = await db.createHeldVoucher(await _holdDraft(db, f),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final newer = await db.createHeldVoucher(
        await _holdDraft(db, f, amount: 20000, allocations: const []),
        userId: 7, userName: 'سالم', roleName: 'مندوب');
    var custody = await db.heldReceiptCustody();
    expect(custody, hasLength(1));
    var row = custody.single;
    expect(row.count, 2);
    expect(row.totalBaseMinor, 80000);
    final olderStamp = (await db.voucherSubmissionOf(older))!.submittedAtMs;
    final newerStamp = (await db.voucherSubmissionOf(newer))!.submittedAtMs;
    expect(olderStamp, lessThan(newerStamp));
    expect(row.oldestSubmittedAtMs, olderStamp);
    expect(row.newestSubmittedAtMs, newerStamp);
    // الاعتماد يُخرج الأقدم فيصير الثاني هو الأقدم والأحدث معاً
    await db.approveHeldVoucher(older);
    custody = await db.heldReceiptCustody();
    row = custody.single;
    expect(row.count, 1);
    expect(row.oldestSubmittedAtMs, newerStamp);
    expect(row.newestSubmittedAtMs, newerStamp);
  });
}
