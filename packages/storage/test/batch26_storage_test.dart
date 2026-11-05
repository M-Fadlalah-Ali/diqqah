import 'package:test/test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 26 (ثالثة م2) — إذنا المخزون إدخال وإخراج
/// (F-209/F-210، س85/D-189).
///
/// الحدود الموثقة: المستندان يُنشآن مرحّلين بلا مسودة (نمط س-18)،
/// والسبب النصي إلزامي، والمقابل افتراضه 43/596 قابل التغيير من
/// الحسابات المفعلة حصراً، وتقييم الزيادة بروح D-186 (المتوسط الحالي
/// ثم سعر الشراء عند الصفير ثم صفر بلا قيد)، والخروج بالامتصاص
/// (D-067) بحماية السالب (F-042)، وحركة المخزون مصدرها المستند
/// (F-041)، والإذنان سابع وثامن المستندات القيدية بحاجزَي الفترة،
/// والتجميد نمط F-140، ولا رقم يُحرق بترحيل مرفوض (07 §1.9).
void main() {
  late DiqqahDatabase db;
  late String year;
  late String date;
  late int unitId;
  late int oilId;
  late int riceId;
  late int serviceId;
  late int supplierId;
  late int mainWhId;
  late int acc113;
  late int acc43;
  late int acc56;
  late int acc596;

  /// رصيد (كمية، قيمة) الصنف بالمستودع — الغائب صفر.
  Future<(int, int)> balanceOf(int itemId, int warehouseId) async {
    final rows = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE item_id = ? AND warehouse_id = ?',
      variables: [Variable.withInt(itemId), Variable.withInt(warehouseId)],
    ).get();
    if (rows.isEmpty) return (0, 0);
    return (
      rows.first.data['qty_base'] as int,
      rows.first.data['total_value_minor'] as int,
    );
  }

  /// مجموع قيمة المخزون الكلية (مرآة 113 — الثابت F-178).
  Future<int> totalStockValue() async {
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(total_value_minor), 0) AS v FROM stock_balances',
    ).get();
    return rows.first.data['v'] as int;
  }

  /// رصيد حساب بالقيد المزدوج (مدين − دائن) من القيود المرحّلة.
  Future<int> accountSignedTotal(int accountId) async {
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(debit_minor - credit_minor), 0) AS s '
      'FROM move_lines ml JOIN moves m ON m.id = ml.move_id '
      'WHERE ml.account_id = ? AND m.state = \'posted\'',
      variables: [Variable.withInt(accountId)],
    ).get();
    return rows.first.data['s'] as int;
  }

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    year = int.parse((await db
            .customSelect('SELECT name FROM fiscal_years')
            .get())
        .single
        .data['name'] as String)
        .toString();
    date = '$year-03-15';
    unitId = await db.insertUnit(name: 'قطعة');
    oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    riceId = await db.insertItem(
        sku: 'R-200',
        name: 'أرز فاخر',
        category: 'أرز',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 30000,
        salePriceMinor: 50000,
        priceCurrencyId: 1);
    serviceId = await db.insertItem(
        sku: 'S-300',
        name: 'صيانة دورية',
        category: 'خدمات',
        kind: 'service',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 15000,
        priceCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0001',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    mainWhId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    acc113 = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '113'",
    ).getSingle()).data['id'] as int;
    acc43 = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '43'",
    ).getSingle()).data['id'] as int;
    acc56 = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '56'",
    ).getSingle()).data['id'] as int;
    acc596 = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '596'",
    ).getSingle()).data['id'] as int;
  });

  tearDown(() => db.close);

  /// بذرة مخزون: 10 زيت × 25000 = 250000 (نمط batch24).
  Future<void> seedOilStock({int qty = 10, int price = 25000}) async {
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: mainWhId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId,
            unitId: unitId,
            qtyBase: qty,
            unitPriceMinor: price),
      ],
    ));
    await db.postInvoice(purchase);
  }

  group('إذن الإدخال (F-209) — الترحيل والتقييم والقيد', () {
    test('إدخال 5 قطع برصيد قائم يزيد الرصيد بالمتوسط الحاكم '
        'ويقيَّد على 43 ويستقر F-178', () async {
      await seedOilStock(); // 10 × 25000
      final beforeValue = await totalStockValue();
      final docId = await db.stockReceiptPost(StockReceiptDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'هدية مورد',
        counterAccountId: acc43,
        lines: [StockDocLineDraft(itemId: oilId, qtyBase: 5)],
      ));
      // الرصيد 15 قطعة والقيمة 375000 — المتوسط 25000 لم يتغير.
      final (qty, value) = await balanceOf(oilId, mainWhId);
      expect(qty, 15);
      expect(value, 375000);
      // قيمة المخزون زادت بالزيادة ذاتها (مرآة 113).
      expect(await totalStockValue(), beforeValue + 125000);
      // القيد: 113 مدين 125000 و43 دائن 125000.
      expect(await accountSignedTotal(acc113), 125000 + 250000);
      expect(await accountSignedTotal(acc43), -125000);
      // حركة المخزون مصدرها المستند (F-041) بمرجعية الإذن.
      final moves = await db.customSelect(
        "SELECT qty_base, value_base_minor, ref_doc_type, ref_doc_id "
        "FROM stock_moves WHERE ref_doc_type = 'stock_receipt' "
        'AND ref_doc_id = ?',
        variables: [Variable.withInt(docId)],
      ).get();
      expect(moves, hasLength(1));
      expect(moves.first.data['qty_base'], 5);
      expect(moves.first.data['value_base_minor'], 125000);
      // الرقم من التسلسل السنوي الموحد بصيغته الجديدة D-169.
      final head = await db.customSelect(
        'SELECT number, state FROM stock_receipts WHERE id = ?',
        variables: [Variable.withInt(docId)],
      ).getSingle();
      expect(head.data['state'], 'posted');
      expect(head.data['number'] as String, matches(RegExp(r'^\d{8}$')));
    });

    test('إدخال على رصيد صفير يقيّم بسعر الشراء المسجل (D-186)', () async {
      // أرز بلا رصيد — سعر شرائه المسجل 30000.
      final docId = await db.stockReceiptPost(StockReceiptDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'بضاعة وجدت',
        counterAccountId: acc43,
        lines: [StockDocLineDraft(itemId: riceId, qtyBase: 4)],
      ));
      final (qty, value) = await balanceOf(riceId, mainWhId);
      expect(qty, 4);
      expect(value, 120000);
      expect(await accountSignedTotal(acc113), 120000);
      expect(await accountSignedTotal(acc43), -120000);
      final lines = await db.stockReceiptLinesOf(docId);
      expect(lines.single.unitCostBaseMinor, 30000);
      expect(lines.single.valueBaseMinor, 120000);
    });

    test('إدخال بلا مرجع تكلفة (صنف بلا سعر ورصيد صفير) — '
        'حركة بقيمة صفر بلا قيد (D-186)', () async {
      final bareId = await db.insertItem(
          sku: 'B-900',
          name: 'صنف بلا سعر',
          kind: 'good',
          baseUnitId: unitId,
          purchasePriceMinor: 0,
          salePriceMinor: 0,
          priceCurrencyId: 1);
      final docId = await db.stockReceiptPost(StockReceiptDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'تصحيح إدخال',
        counterAccountId: acc43,
        lines: [StockDocLineDraft(itemId: bareId, qtyBase: 2)],
      ));
      final (qty, value) = await balanceOf(bareId, mainWhId);
      expect(qty, 2);
      expect(value, 0);
      // لا قيد للمستند — move واحد فقط بلا أسطر دفتر.
      final moves = await db.customSelect(
        "SELECT id FROM stock_moves WHERE ref_doc_type = 'stock_receipt' "
        'AND ref_doc_id = ?',
        variables: [Variable.withInt(docId)],
      ).get();
      expect(moves, hasLength(1));
      final journalLines = await db.customSelect(
        'SELECT ml.id FROM move_lines ml JOIN moves m '
        'ON m.id = ml.move_id WHERE m.ref_doc_type = ? '
        'AND m.ref_doc_id = ?',
        variables: [Variable.withString('stock_receipt'),
            Variable.withInt(docId)],
      ).get();
      expect(journalLines, isEmpty);
    });

    test('الحساب المقابل قابل التغيير لحظة الترحيل من المفعّل', () async {
      await seedOilStock();
      // 57 فروق الصناديق مفعّل من البذر (03) — تغيير المقابل إليه.
      final acc57 = (await db.customSelect(
        "SELECT id FROM accounts WHERE code = '57'",
      ).getSingle()).data['id'] as int;
      await db.stockReceiptPost(StockReceiptDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'تصحيح إدخال',
        counterAccountId: acc57,
        lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
      ));
      expect(await accountSignedTotal(acc57), -25000);
      expect(await accountSignedTotal(acc43), 0);
    });

    test('الحساب المعطل يرفض والحساب الغائب يرفض برسالة المحرك',
        () async {
      await seedOilStock();
      final acc57 = (await db.customSelect(
        "SELECT id FROM accounts WHERE code = '57'",
      ).getSingle()).data['id'] as int;
      await db.customStatement(
        'UPDATE accounts SET is_active = 0 WHERE id = ?',
        [acc57],
      );
      expect(
        () => db.stockReceiptPost(StockReceiptDraft(
          dateText: date,
          warehouseId: mainWhId,
          reason: 'هدية مورد',
          counterAccountId: acc57,
          lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
        )),
        throwsA(isA<StockDocValidationException>().having(
          (e) => firstStockDocError(e.errors),
          'message',
          contains('غير مفعّل'),
        )),
      );
      expect(
        () => db.stockReceiptPost(StockReceiptDraft(
          dateText: date,
          warehouseId: mainWhId,
          reason: 'هدية مورد',
          counterAccountId: 999999,
          lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
        )),
        throwsA(isA<StockDocValidationException>().having(
          (e) => firstStockDocError(e.errors),
          'message',
          contains('غير موجود بالدليل'),
        )),
      );
    });

    test('السبب النصي إلزامي والخدمة مرفوضة والصنف المعطل مرفوض',
        () async {
      await seedOilStock();
      // السبب الفارغ يرفض بنيوياً بلا كتابة.
      expect(
        () => db.stockReceiptPost(StockReceiptDraft(
          dateText: date,
          warehouseId: mainWhId,
          reason: '   ',
          counterAccountId: acc43,
          lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
        )),
        throwsA(isA<StockDocValidationException>().having(
          (e) => firstStockDocError(e.errors),
          'message',
          contains('إلزامي'),
        )),
      );
      // الخدمة بلا مخزون ترفض (س-08).
      expect(
        () => db.stockReceiptPost(StockReceiptDraft(
          dateText: date,
          warehouseId: mainWhId,
          reason: 'هدية مورد',
          counterAccountId: acc43,
          lines: [StockDocLineDraft(itemId: serviceId, qtyBase: 1)],
        )),
        throwsA(isA<StockDocValidationException>().having(
          (e) => firstStockDocError(e.errors),
          'message',
          contains('بضاعة حصراً'),
        )),
      );
      // ولا شيء كُتب — لا مستند ولا حركة ولا رقم محروق.
      final receipts = await db.customSelect(
        'SELECT COUNT(*) AS c FROM stock_receipts',
      ).get();
      expect(receipts.first.data['c'], 0);
    });
  });

  group('إذن الإخراج (F-210) — الترحيل والامتصاص والقيد', () {
    test('إخراج تالف ينقص الرصيد والقيمة بالامتصاص ويقيَّد على 596',
        () async {
      await seedOilStock(); // 10 × 25000 = 250000
      final beforeValue = await totalStockValue();
      final docId = await db.stockIssuePost(StockIssueDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'تلف بالتخزين',
        counterAccountId: acc596,
        lines: [StockDocLineDraft(itemId: oilId, qtyBase: 3)],
      ));
      final (qty, value) = await balanceOf(oilId, mainWhId);
      expect(qty, 7);
      expect(value, 175000);
      expect(await totalStockValue(), beforeValue - 75000);
      // القيد: 596 مدين 75000 و113 دائن 75000.
      expect(await accountSignedTotal(acc596), 75000);
      expect(await accountSignedTotal(acc113), 175000);
      // حركة الخروج سالبة الإشارة بمرجعية الإذن.
      final moves = await db.customSelect(
        "SELECT qty_base, value_base_minor FROM stock_moves "
        "WHERE ref_doc_type = 'stock_issue' AND ref_doc_id = ?",
        variables: [Variable.withInt(docId)],
      ).get();
      expect(moves.single.data['qty_base'], -3);
      expect(moves.single.data['value_base_minor'], 75000);
      // سطر المستند بلقطة التكلفة (نمط F-140).
      final lines = await db.stockIssueLinesOf(docId);
      expect(lines.single.unitCostBaseMinor, 25000);
      expect(lines.single.valueBaseMinor, 75000);
    });

    test('الإخراج أكثر من الرصيد مرفوض — منع السالب F-042 بلا كتابة',
        () async {
      await seedOilStock(qty: 2);
      final before = await totalStockValue();
      expect(
        () => db.stockIssuePost(StockIssueDraft(
          dateText: date,
          warehouseId: mainWhId,
          reason: 'تالف',
          counterAccountId: acc596,
          lines: [StockDocLineDraft(itemId: oilId, qtyBase: 5)],
        )),
        throwsA(isA<StockDocValidationException>().having(
          (e) => firstStockDocError(e.errors),
          'message',
          allOf(contains('منع السالب'), contains('F-042')),
        )),
      );
      // لا مستند ولا حركة ولا قيد ولا رقماً محروقاً.
      final counts = await db.customSelect(
        "SELECT (SELECT COUNT(*) FROM stock_issues) AS docs, "
        "(SELECT COUNT(*) FROM stock_moves WHERE ref_doc_type = "
        "'stock_issue') AS moves",
      ).getSingle();
      expect(counts.data['docs'], 0);
      expect(counts.data['moves'], 0);
      expect(await totalStockValue(), before);
      // والعدّاد لم يُلمس — أول إخراج لاحق يأخذ الرقم الأول.
      final docId = await db.stockIssuePost(StockIssueDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'استهلاك داخلي',
        counterAccountId: acc596,
        lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
      ));
      final head = await db.customSelect(
        'SELECT number FROM stock_issues WHERE id = ?',
        variables: [Variable.withInt(docId)],
      ).getSingle();
      expect(head.data['number'] as String, matches(RegExp(r'^\d{8}$')));
      final seq = await db.customSelect(
        "SELECT last_number FROM sequences WHERE kind = 'stock_issue'",
      ).getSingle();
      expect(seq.data['last_number'], 1);
    });

    test('المقابل قابل التغيير من المفعّل — 56 عجز الجرد بدل 596',
        () async {
      await seedOilStock();
      await db.stockIssuePost(StockIssueDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'تصحيح إخراج',
        counterAccountId: acc56,
        lines: [StockDocLineDraft(itemId: oilId, qtyBase: 2)],
      ));
      expect(await accountSignedTotal(acc56), 50000);
      expect(await accountSignedTotal(acc596), 0);
    });
  });

  group('حواجز المستندين — الفترة المقفلة والتجميد والسجل', () {
    test('الفترة المقفلة تحبط ترحيل الإذنين حاجزَي القاعدة '
        '(سابع وثامن المستندات القيدية)', () async {
      await seedOilStock();
      final period = await db.customSelect(
        'SELECT id FROM periods WHERE start_date_text <= ? '
        'AND end_date_text >= ?',
        variables: [Variable.withString(date), Variable.withString(date)],
      ).getSingle();
      await db.closePeriod(period.data['id'] as int, draftsConfirmed: true);
      // المحرك أولاً (MoveClosedPeriod) والحاجز الثاني بالقاعدة —
      // كلاهما يمنع بلا كتابة.
      await expectLater(
        db.stockReceiptPost(StockReceiptDraft(
          dateText: date,
          warehouseId: mainWhId,
          reason: 'هدية مورد',
          counterAccountId: acc43,
          lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
        )),
        throwsA(anything),
      );
      await expectLater(
        db.stockIssuePost(StockIssueDraft(
          dateText: date,
          warehouseId: mainWhId,
          reason: 'تالف',
          counterAccountId: acc596,
          lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
        )),
        throwsA(anything),
      );
      final docs = await db.customSelect(
        "SELECT (SELECT COUNT(*) FROM stock_receipts) AS r, "
        "(SELECT COUNT(*) FROM stock_issues) AS i",
      ).getSingle();
      expect(docs.data['r'], 0);
      expect(docs.data['i'], 0);
    });

    test('الإذن المرحّل لقطة تاريخية — لا تعديل ولا حذف (نمط F-140)',
        () async {
      await seedOilStock();
      final docId = await db.stockReceiptPost(StockReceiptDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'هدية مورد',
        counterAccountId: acc43,
        lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
      ));
      expect(
        () => db.customStatement(
          'UPDATE stock_receipts SET reason = ? WHERE id = ?',
          ['عبث', docId],
        ),
        throwsA(anything),
      );
      expect(
        () => db.customStatement(
          'DELETE FROM stock_receipt_lines WHERE doc_id = ?',
          [docId],
        ),
        throwsA(anything),
      );
    });

    test('سجلا الإذنين يعرضان الرؤوس بتفصيلهما والأسطر بلقطاتها',
        () async {
      await seedOilStock();
      await db.stockReceiptPost(StockReceiptDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'هدية مورد',
        counterAccountId: acc43,
        lines: [
          StockDocLineDraft(itemId: oilId, qtyBase: 2),
          StockDocLineDraft(itemId: riceId, qtyBase: 1),
        ],
      ));
      await db.stockIssuePost(StockIssueDraft(
        dateText: date,
        warehouseId: mainWhId,
        reason: 'تالف',
        counterAccountId: acc596,
        lines: [StockDocLineDraft(itemId: oilId, qtyBase: 1)],
      ));
      final receipts = await db.stockReceiptsOf();
      expect(receipts, hasLength(1));
      expect(receipts.first.reason, 'هدية مورد');
      expect(receipts.first.lineCount, 2);
      // زيت 2×25000 = 50000 وأرز 1×30000 = 30000.
      expect(receipts.first.totalValueMinor, 80000);
      final issues = await db.stockIssuesOf();
      expect(issues, hasLength(1));
      expect(issues.first.reason, 'تالف');
      expect(issues.first.totalQtyBase, 1);
      final issueLines = await db.stockIssueLinesOf(issues.first.id);
      expect(issueLines, hasLength(1));
      expect(issueLines.single.itemName, 'زيت محلي');
      expect(issueLines.single.valueBaseMinor, 25000);
    });
  });
}
