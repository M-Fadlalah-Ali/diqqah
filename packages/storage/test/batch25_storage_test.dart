import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 25 (ثاني م2) — الجرد وتسوياته (س-19/F-046، س79/D-186).
///
/// الحدود الموثقة: الجلسة جارٍ ← مرحّل بترحيلة واحدة ولا تسوية جزئية
/// (الصفر عدّ شرعي)، والفروقات لحظة الترحيل ضد الأرصدة الآنية، والعجز
/// بالامتصاص 56/113 والزيادة بالمتوسط الحالي أو سعر الشراء عند رصيد
/// صفير (D-186) بزوج 113/43، والقيد قيدٌ مجمع بدفتر المخزون بمرجع
/// الجلسة، والجلسة المرحّلة لقطة لا تعدل (F-140)، والفترة المقفلة
/// ترفض، وثابت 113 يتحرك بقيمة الفروقات ذاتها (F-178).
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

  /// رصيد (كمية، قيمة) صف المستودع أو الأصفار عند الغياب.
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

  /// مجموع قيمة المخزون الكلية (ثابت 113 = مجموع total_value — F-178).
  Future<int> totalStockValue() async {
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(total_value_minor), 0) AS v FROM stock_balances',
    ).get();
    return rows.first.data['v'] as int;
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
    // بذرة مخزون بالمستودع الرئيسي: 10 زيت × 25000 = 250000
    // و20 أرز × 30000 = 600000 — المجموع 850000.
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: mainWhId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 25000),
        InvoiceLineDraft(
            itemId: riceId, unitId: unitId, qtyBase: 20, unitPriceMinor: 30000),
      ],
    ));
    await db.postInvoice(purchase);
  });

  tearDown(() => db.close);

  group('stockCountPost — التسوية العجزية والزائدية (س-19/03 §4)', () {
    test('جلسة الكل: عجز زيت وزيادة أرز — القيد المجمع والحركتان وثابت 113',
        () async {
      final sessionId = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      ));
      // البذر الآلي: سطرا الزيت والأرز حصراً (بلا عدّ بعد)
      var lines = await db.stockCountLinesOf(sessionId);
      expect(lines.length, 2);
      expect(lines.every((l) => l.countedQtyBase == null), isTrue);
      // عدّ متكرر: حفظ أول ثم تصحيح — الأخير هو الفاصل (س-19: حفظ متكرر)
      await db.stockCountSaveCounts(sessionId, {oilId: 12, riceId: 20});
      await db.stockCountSaveCounts(sessionId, {oilId: 9, riceId: 22});

      await db.stockCountPost(sessionId);

      // الأرصدة تطابق الواقع المعدود: زيت 9×25000 وأرز 22 قيمتها
      // 600000 + 2×30000 بالمتوسط الحالي (F-047/D-067)
      expect(await balanceOf(oilId, mainWhId), (9, 225000));
      expect(await balanceOf(riceId, mainWhId), (22, 660000));
      // ثابت 113: 850000 − 25000 عجز + 60000 زيادة = 885000 (F-178)
      expect(await totalStockValue(), 885000);

      // القيد المجمع بدفتر المخزون بمرجع الجلسة: أربعة أسطر متوازنة
      final moves = await db.customSelect(
        'SELECT m.id, m.number, m.state, m.narration, j.code AS journal '
        'FROM moves m JOIN journals j ON j.id = m.journal_id '
        "WHERE m.ref_doc_type = 'stock_count' AND m.ref_doc_id = ?",
        variables: [Variable.withInt(sessionId)],
      ).get();
      expect(moves.length, 1);
      expect(moves.single.data['journal'], 'stock');
      expect(moves.single.data['state'], 'posted');
      final moveId = moves.single.data['id'] as int;
      final ledgerLines = await db.customSelect(
        'SELECT a.code AS code, l.debit_minor AS debit, '
        'l.credit_minor AS credit, l.ref_stock_move_id AS ref '
        'FROM move_lines l JOIN accounts a ON a.id = l.account_id '
        'WHERE l.move_id = ? ORDER BY l.id',
        variables: [Variable.withInt(moveId)],
      ).get();
      var debit = 0, credit = 0;
      final pairs = <String, List<int>>{};
      for (final l in ledgerLines) {
        final code = l.data['code'] as String;
        debit += l.data['debit'] as int;
        credit += l.data['credit'] as int;
        pairs.putIfAbsent(code, () => []).add((l.data['debit'] as int) -
            (l.data['credit'] as int));
      }
      expect(debit, 85000, reason: '56 مدين 25000 و113 مدين 60000');
      expect(credit, 85000, reason: '113 دائن 25000 و43 دائن 60000');
      expect(pairs['56'], [25000], reason: 'عجز الجرد مدين بقيمة العجز');
      expect(pairs['43'], [-60000], reason: 'إيرادات أخرى دائنة بالزيادة');
      // سطرا 113 — أحدهما دائن بالعجز والآخر مدين بالزيادة، مربوطان بحركتيهما
      expect(pairs['113']!.length, 2);
      expect(pairs['113']!.fold<int>(0, (a, b) => a + b), 35000,
          reason: '113 مدين 60000 − دائن 25000 = 35000 صافي زيادة القيمة');
      final linkedRefs = await db.customSelect(
        'SELECT COUNT(*) AS c FROM move_lines WHERE move_id = ? '
        'AND ref_stock_move_id IS NOT NULL',
        variables: [Variable.withInt(moveId)],
      ).getSingle();
      expect(linkedRefs.data['c'], 2,
          reason: 'كل 113 مربوط بحركة مخزونه (نمط الفواتير)');

      // حركتا تسوية بمرجع الجلسة: نزول الزيت وصعود الأرز
      final stockMoves = await db.customSelect(
        'SELECT item_id, qty_base, from_warehouse_id, to_warehouse_id, '
        'value_base_minor FROM stock_moves '
        "WHERE ref_doc_type = 'stock_count' AND ref_doc_id = ? "
        'ORDER BY qty_base',
        variables: [Variable.withInt(sessionId)],
      ).get();
      expect(stockMoves.length, 2);
      expect(stockMoves[0].data['item_id'], oilId);
      expect(stockMoves[0].data['qty_base'], -1);
      expect(stockMoves[0].data['from_warehouse_id'], mainWhId);
      expect(stockMoves[0].data['value_base_minor'], 25000);
      expect(stockMoves[1].data['item_id'], riceId);
      expect(stockMoves[1].data['qty_base'], 2);
      expect(stockMoves[1].data['to_warehouse_id'], mainWhId);
      expect(stockMoves[1].data['value_base_minor'], 60000);

      // لقطة الترحيل على الأسطر: النظام الآني والفرق والاتجاه والقيمة
      lines = await db.stockCountLinesOf(sessionId);
      final oil = lines.firstWhere((l) => l.itemId == oilId);
      final rice = lines.firstWhere((l) => l.itemId == riceId);
      expect(oil.systemQtyBase, 10);
      expect(oil.diffQtyBase, -1);
      expect(oil.direction, 'deficit');
      expect(oil.valueBaseMinor, 25000);
      expect(rice.systemQtyBase, 20);
      expect(rice.diffQtyBase, 2);
      expect(rice.direction, 'surplus');
      expect(rice.valueBaseMinor, 60000);
      expect(rice.unitCostBaseMinor, 30000);

      // الحالة مرحّلة والحدثان بلقطتهما (07 §2.3)
      final head = await db.customSelect(
        'SELECT number, state FROM stock_counts WHERE id = ?',
        variables: [Variable.withInt(sessionId)],
      ).getSingle();
      expect(head.data['state'], 'posted');
      expect(head.data['number'], startsWith('${int.parse(year) % 100}'));
      for (final action in ['created', 'posted']) {
        final events = await db.customSelect(
          "SELECT COUNT(*) AS c FROM events WHERE entity_type = "
          "'stock_count' AND action = ? AND entity_id = ?",
          variables: [
            Variable.withString(action),
            Variable.withInt(sessionId),
          ],
        ).getSingle();
        expect(events.data['c'], 1, reason: 'حدث $action واحد بلقطته');
      }
    });

    test('العدّ الصفر يمتص القيمة كلها بلا غبار (D-067) وجلسة المجموعة '
        'بتصنيفها حصراً', () async {
      final sessionId = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.group,
        scopeCategory: 'زيوت',
      ));
      // بذر المجموعة: الزيت سطراً والأرز خارج تصنيفها
      final lines = await db.stockCountLinesOf(sessionId);
      expect(lines.length, 1);
      expect(lines.single.itemId, oilId);
      await db.stockCountSaveCounts(sessionId, {oilId: 0});
      await db.stockCountPost(sessionId);
      // الرف فارغ: القيمة كلها خرجت بالامتصاص — لا غبار معلق
      expect(await balanceOf(oilId, mainWhId), (0, 0));
      expect(await balanceOf(riceId, mainWhId), (20, 600000));
      expect(await totalStockValue(), 600000);
      // قيد العجز الكامل: 56 مدين 250000 / 113 دائن 250000
      final lines2 = await db.customSelect(
        'SELECT a.code AS code, l.debit_minor AS debit, '
        'l.credit_minor AS credit '
        'FROM move_lines l JOIN accounts a ON a.id = l.account_id '
        'JOIN moves m ON m.id = l.move_id '
        "WHERE m.ref_doc_type = 'stock_count' AND m.ref_doc_id = ?",
        variables: [Variable.withInt(sessionId)],
      ).get();
      expect(lines2.length, 2);
      expect(lines2.first.data['code'], '56');
      expect(lines2.first.data['debit'], 250000);
      expect(lines2.last.data['code'], '113');
      expect(lines2.last.data['credit'], 250000);
    });

    test('زيادة على رصيد صفير تُقيَّم بآخر سعر دخول معروف (D-186) '
        'و«صنف وجدناه» بحدوده', () async {
      final sugarId = await db.insertItem(
          sku: 'G-400',
          name: 'سكر ناعم',
          category: 'مواد غذائية',
          kind: 'good',
          baseUnitId: unitId,
          purchasePriceMinor: 5000,
          salePriceMinor: 7000,
          priceCurrencyId: 1);
      final sessionId = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      ));
      // البذر: الزيت والأرز حصراً — السكر بلا رصيد لا يبذر
      final lines = await db.stockCountLinesOf(sessionId);
      expect(lines.map((l) => l.itemId), [oilId, riceId]);
      // «صنف وجدناه»: السكر موجود على الرف 4 عبوات — والحدود:
      // عدّة صفر ترفض، والخدمة ترفض، والتكرار يرفض
      expect(
        () => db.stockCountAddFoundItem(sessionId,
            StockCountLineDraft(itemId: sugarId, countedQtyBase: 0)),
        throwsA(isA<StockCountValidationException>()),
      );
      expect(
        () => db.stockCountAddFoundItem(
            sessionId,
            StockCountLineDraft(itemId: serviceId, countedQtyBase: 1)),
        throwsA(isA<StockCountValidationException>()
            .having((e) => firstStockCountError(e.errors), 'msg',
                contains('بضاعة حصراً'))),
      );
      await db.stockCountAddFoundItem(sessionId,
          StockCountLineDraft(itemId: sugarId, countedQtyBase: 4));
      expect(
        () => db.stockCountAddFoundItem(sessionId,
            StockCountLineDraft(itemId: sugarId, countedQtyBase: 1)),
        throwsA(isA<StockCountValidationException>()
            .having((e) => firstStockCountError(e.errors), 'msg',
                contains('سطراً واحداً'))),
      );
      await db.stockCountSaveCounts(sessionId, {oilId: 10, riceId: 20});
      await db.stockCountPost(sessionId);
      // الزيادة من الصفر بسعر الشراء المسجل: 4 × 5000 = 20000 (D-186)
      expect(await balanceOf(sugarId, mainWhId), (4, 20000));
      expect(await totalStockValue(), 870000);
      final ledgerLines = await db.customSelect(
        'SELECT a.code AS code, l.debit_minor AS debit, '
        'l.credit_minor AS credit '
        'FROM move_lines l JOIN accounts a ON a.id = l.account_id '
        'JOIN moves m ON m.id = l.move_id '
        "WHERE m.ref_doc_type = 'stock_count' AND m.ref_doc_id = ? "
        'ORDER BY l.id',
        variables: [Variable.withInt(sessionId)],
      ).get();
      // زوج الزيادة وحده: زيت وأرز فروقهما صفري فلا سطر لهما
      expect(ledgerLines.length, 2);
      expect(ledgerLines.first.data['code'], '113');
      expect(ledgerLines.first.data['debit'], 20000);
      expect(ledgerLines.last.data['code'], '43');
      expect(ledgerLines.last.data['credit'], 20000);
    });

    test('لا تسوية جزئية ترفض — وبعد استكمال العدّ الفروقات الصفرية '
        'ترحّل بلا قيد إطلاقاً', () async {
      final sessionId = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      ));
      // عدّ الزيت وحده — الأرز بلا عدّ فالترحيل يرفض بالجلسة كلها
      await db.stockCountSaveCounts(sessionId, {oilId: 10});
      try {
        await db.stockCountPost(sessionId);
        fail('كان يجب أن يرفض');
      } on StockCountValidationException catch (e) {
        expect(firstStockCountError(e.errors), contains('لا تسوية جزئية'));
      }
      // لا حركة ولا قيد ولا تغيير أرصدة — والجلسة ما تزال جارياً
      expect(await balanceOf(oilId, mainWhId), (10, 250000));
      final moveCount = await db.customSelect(
        "SELECT COUNT(*) AS c FROM stock_moves WHERE ref_doc_type = "
        "'stock_count'",
      ).getSingle();
      expect(moveCount.data['c'], 0);
      final head = await db.customSelect(
        'SELECT state FROM stock_counts WHERE id = ?',
        variables: [Variable.withInt(sessionId)],
      ).getSingle();
      expect(head.data['state'], 'open');
      // استكمال العدّ بالفروقات الصفرية حصراً — ترحيل بلا قيد بأسطر
      await db.stockCountSaveCounts(sessionId, {riceId: 20});
      await db.stockCountPost(sessionId);
      final ledgerMoves = await db.customSelect(
        "SELECT COUNT(*) AS c FROM moves WHERE ref_doc_type = "
        "'stock_count' AND ref_doc_id = ?",
        variables: [Variable.withInt(sessionId)],
      ).getSingle();
      expect(ledgerMoves.data['c'], 0,
          reason: 'لا فرق مالي فلا قيد — والجلسة موثقة الحالة فقط');
      final lines = await db.stockCountLinesOf(sessionId);
      expect(lines.every((l) => l.direction == 'none'), isTrue);
    });

    test('الجلسة الجارية الوحيدة بالمستودع والرقم لا يحرق عند الرفض',
        () async {
      final first = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      ));
      // جلستان متوازيتان على مستودع واحد مرفوض — والرفض قبل العدّاد
      // فلا رقم يحرق (07 §1.9)
      expect(
        () => db.stockCountStart(StockCountStartDraft(
          dateText: date,
          warehouseId: mainWhId,
          scope: StockCountScope.all,
        )),
        throwsA(isA<StockCountValidationException>()
            .having((e) => firstStockCountError(e.errors), 'msg',
                contains('جلسة جرد جارٍ'))),
      );
      await db.stockCountSaveCounts(
          first, {oilId: 10, riceId: 20});
      await db.stockCountPost(first);
      // الجلسة التالية تأخذ الرقم 2 لا 3
      final second = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      ));
      final rows = await db.customSelect(
        'SELECT number FROM stock_counts WHERE id = ?',
        variables: [Variable.withInt(second)],
      ).getSingle();
      expect(rows.data['number'], endsWith('2'));
    });

    test('الجلسة المرحّلة لقطة لا تعدل ولا تحذف — مُشغّلات التجميد (F-140)',
        () async {
      final sessionId = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      ));
      await db.stockCountSaveCounts(sessionId, {oilId: 9, riceId: 20});
      await db.stockCountPost(sessionId);
      // تعديل محركي مرفوض بالمدقق
      expect(
        () => db.stockCountSaveCounts(sessionId, {oilId: 5}),
        throwsA(isA<StockCountValidationException>()
            .having((e) => firstStockCountError(e.errors), 'msg',
                contains('مرحّلة أصلاً'))),
      );
      // والحاجز الثاني بقاعدة البيانات: أي UPDATE أو DELETE خام يُحبط
      expect(
        () => db.customStatement(
            "UPDATE stock_counts SET narration = 'عبث' WHERE id = ?",
            [sessionId]),
        throwsA(anything),
      );
      expect(
        () => db.customStatement(
            'DELETE FROM stock_count_lines WHERE count_id = ?', [sessionId]),
        throwsA(anything),
      );
      // واللقطة باقية لم تُمس
      final head = await db.customSelect(
        'SELECT narration FROM stock_counts WHERE id = ?',
        variables: [Variable.withInt(sessionId)],
      ).getSingle();
      expect(head.data['narration'], isNull);
    });

    test('فترة مقفلة ترفض ترحيل الجلسة — القيد لا يُرحَّل فيها (س-19)',
        () async {
      final sessionId = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      ));
      await db.stockCountSaveCounts(sessionId, {oilId: 9, riceId: 20});
      final marchId = (await db.customSelect(
        'SELECT id FROM periods WHERE start_date_text = ? '
        'AND end_date_text >= ?',
        variables: [Variable.withString('$year-03-01'), Variable.withString(date)],
      ).getSingle()).data['id'] as int;
      await db.closePeriod(marchId, draftsConfirmed: true);
      try {
        await db.stockCountPost(sessionId);
        fail('كان يجب أن يرفض');
      } on Object catch (e) {
        expect('$e', contains('مقفلة'),
            reason: 'رسالة المدقق المحاسبي الموحدة (07 §1.5): '
                '«فترة التاريخ ... مقفلة — لا ترحيل فيها»');
      }
      // لا حركة ولا قيد ولا ترحيل حالة — الجلسة جارية تنتظر فتح الفترة
      expect(await balanceOf(oilId, mainWhId), (10, 250000));
      final head = await db.customSelect(
        'SELECT state FROM stock_counts WHERE id = ?',
        variables: [Variable.withInt(sessionId)],
      ).getSingle();
      expect(head.data['state'], 'open');
    });

    test('مستودع معطل يرفض الافتتاح والترحيل — وسجل الجلسات يقرأ مجمعه',
        () async {
      // مستودع فرع بلا رصيد — افتتاحه يمر بلا أسطر ويُرفض ترحيله
      final branchId = await db.warehouseCreate(name: 'مستودع الفرع');
      final empty = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: branchId,
        scope: StockCountScope.all,
      ));
      expect(
        () => db.stockCountPost(empty),
        throwsA(isA<StockCountValidationException>()
            .having((e) => firstStockCountError(e.errors), 'msg',
                contains('لا صنف في الجلسة'))),
      );
      // جلسة رئيسية مكتملة تعرض بالسجل بمجموعها
      final sessionId = await db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
        narration: 'جرد نهاية الربع',
      ));
      await db.stockCountSaveCounts(sessionId, {oilId: 9, riceId: 22});
      await db.stockCountPost(sessionId);
      final registry = await db.stockCountsOf();
      final row = registry.firstWhere((r) => r.id == sessionId);
      expect(row.warehouseName, 'المستودع الرئيسي');
      expect(row.state, 'posted');
      expect(row.lineCount, 2);
      expect(row.countedCount, 2);
      expect(row.deficitCount, 1);
      expect(row.surplusCount, 1);
      expect(row.deficitValueMinor, 25000);
      expect(row.surplusValueMinor, 60000);
      expect(row.narration, 'جرد نهاية الربع');
      // مستودع معطل لا يفتح عليه جلسة
      await db.warehouseSetActive(id: branchId, active: false);
      expect(
        () => db.stockCountStart(StockCountStartDraft(
          dateText: date,
          warehouseId: branchId,
          scope: StockCountScope.all,
        )),
        throwsA(isA<StockCountValidationException>()
            .having((e) => firstStockCountError(e.errors), 'msg',
                contains('معطل'))),
      );
    });
  });
/// س112 — إلغاء جلسة العد المفتوحة المهجورة: حذف منطقي بلا أثر
/// قيدي ولا مخزني، وتحرير المستودع لجلسة جديدة، والمرحّلة لا تُلغى.
group('stockCountCancel — إلغاء الجلسة المهجورة (س112)', () {
  test('إلغاء مفتوحة: تزول عن السجل وتحرر المستودع وأسطرها تُحذف منطقياً',
      () async {
    final sessionId = await db.stockCountStart(StockCountStartDraft(
      dateText: date,
      warehouseId: mainWhId,
      scope: StockCountScope.all,
    ));
    await db.stockCountSaveCounts(sessionId, {oilId: 7});
    // بلا إلغاء: جلسة ثانية لنفس المستودع مرفوضة (حرس الجلسة الواحدة).
    await expectLater(
      () => db.stockCountStart(StockCountStartDraft(
        dateText: date,
        warehouseId: mainWhId,
        scope: StockCountScope.all,
      )),
      throwsA(isA<StockCountValidationException>()),
    );
    await db.stockCountCancel(sessionId);
    // زالت عن سجل الجلسات (قراءة العرض تُخرج المحذوف منطقياً).
    final sessions = await db.stockCountsOf();
    expect(sessions.where((s) => s.id == sessionId), isEmpty);
    // وأسطرها محذوفة منطقياً (بلا أثر — الجلسة بلا ترحيل).
    final lines = await db.stockCountLinesOf(sessionId);
    expect(lines, isEmpty);
    // والمخزون لم يمس: الأرصدة بذرتها كما هي.
    expect(await balanceOf(oilId, mainWhId), (10, 250000));
    expect(await balanceOf(riceId, mainWhId), (20, 600000));
    expect(await totalStockValue(), 850000);
    // وتحرر المستودع: جلسة جديدة تُفتح بلا رفض.
    final newId = await db.stockCountStart(StockCountStartDraft(
      dateText: date,
      warehouseId: mainWhId,
      scope: StockCountScope.all,
    ));
    expect(newId, isPositive);
  });

  test('المرحّلة لا تُلغى — اللقطة التاريخية لا تمس (نمط F-140)',
      () async {
    final sessionId = await db.stockCountStart(StockCountStartDraft(
      dateText: date,
      warehouseId: mainWhId,
      scope: StockCountScope.all,
    ));
    await db.stockCountSaveCounts(sessionId, {oilId: 9, riceId: 22});
    await db.stockCountPost(sessionId);
    await expectLater(
      () => db.stockCountCancel(sessionId),
      throwsA(isA<StockCountValidationException>()),
    );
    // وبقيت بالسجل بحالتها المرحّلة.
    final sessions = await db.stockCountsOf();
    expect(sessions.where((s) => s.id == sessionId), hasLength(1));
  });

  test('جلسة غير معروفة تُرفض بالمعرف', () async {
    await expectLater(
      () => db.stockCountCancel(99999),
      throwsA(isA<StockCountValidationException>()),
    );
  });
});

/// س115 — الشطر الثاني من حدّا الدفعة 30: العدّ بالتعبئة بلقطة
/// المستوى (نمط الفواتير س89 والإذنين والتحويل س113) — والمخزون
/// والقيد على المخزونية كما هي، واللقطاء عرض لا حساب.
group('س115 — العدّ بالتعبئة (حدّا الدفعة 30 — الشطر الثاني)', () {
  late int gid;
  late int boxLevelId;
  late int otherLevelId;
  late int packedOilId;

  setUp(() async {
    gid = await db.insertUnitGroup(
      name: 'تعبئة الزيت المعبأ',
      levels: [(name: 'علبة', factor: 12)],
    );
    boxLevelId = (await db.levelsOfGroup(gid)).single.id;
    final otherGid = await db.insertUnitGroup(
        name: 'تعبئة أخرى', levels: [(name: 'طبق', factor: 6)]);
    otherLevelId = (await db.levelsOfGroup(otherGid)).single.id;
    packedOilId = await db.insertItem(
        sku: 'Z-200',
        name: 'زيت معبأ',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1,
        unitGroupId: gid);
    // بذر مخزون التجميعي: 2 علب × 30,000 = 24 قطعة × 25,000 = 600000
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: mainWhId,
      lines: [
        InvoiceLineDraft(
            itemId: packedOilId,
            unitId: unitId,
            qty: 2,
            unitLevelId: boxLevelId,
            qtyBase: 24,
            unitPriceMinor: 300000),
      ],
    ));
    await db.postInvoice(purchase);
  });

  test('ترحيلة v26 على قاعدة جديدة: أعمدة اللقطة على أسطر الجرد ورأس '
      'التجميع', () async {
    for (final table in const ['stock_count_lines', 'assemblies']) {
      final cols = await db.customSelect(
        "SELECT name FROM pragma_table_info('$table') "
        "WHERE name IN ('unit_level_id', 'qty_doc', 'factor_at_entry')",
      ).get();
      expect(cols.map((r) => r.data['name']), hasLength(3),
          reason: 'أعمدة اللقطة الثلاثة وُلدت على $table');
    }
  });

  test('ترحيلة v26 آمنة التكرار: قاعدة v24 ترقى مرّة واحدة بالشطرين '
      '(v25 وv26) والبيانات سليمة', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v115_mig_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate26.db');
    final seeded = DiqqahDatabase(filePath: dbPath);
    final u = await seeded.insertUnit(name: 'قطعة');
    await seeded.insertItem(
        sku: 'M-1',
        name: 'صنف ما قبل الترحيلة',
        kind: 'good',
        baseUnitId: u,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1);
    await seeded.close();
    // تخفيض user_version إلى 24: إعادة الفتح تجري 24→25→26 أمامنا —
    // والأعمدة موجودة أصلاً (onCreate كامل) فالحرس pragma يقفز آمناً.
    final raw = sqlite3.open(dbPath);
    raw.execute('PRAGMA user_version = 24');
    raw.dispose();
    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);
    for (final table in const [
      'stock_transfer_lines',
      'stock_receipt_lines',
      'stock_issue_lines',
      'stock_count_lines',
      'assemblies',
    ]) {
      final cols = await migrated.customSelect(
        "SELECT name FROM pragma_table_info('$table') "
        "WHERE name = 'unit_level_id'",
      ).get();
      expect(cols, hasLength(1), reason: 'عمود اللقطة حاضر على $table');
    }
  });

  test('عدّ بالتعبئة: 3 علب = 36 باللقطة والتسوية على المخزونية — '
      'زيادة 12 بقيمتها والمخزون بالمخزونية', () async {
    final sessionId = await db.stockCountStart(StockCountStartDraft(
      dateText: date,
      warehouseId: mainWhId,
      scope: StockCountScope.all,
    ));
    await db.stockCountSaveCounts(
        sessionId, {packedOilId: 36, oilId: 10, riceId: 20},
        levelsByItemId: {
          packedOilId: StockCountLevelSnapshot(
            unitLevelId: boxLevelId,
            qtyDoc: 3,
            factorAtEntry: 12,
          ),
        });
    final lines = await db.stockCountLinesOf(sessionId);
    final line = lines.firstWhere((l) => l.itemId == packedOilId);
    expect(line.countedQtyBase, 36);
    expect(line.unitLevelId, boxLevelId);
    expect(line.qtyDoc, 3);
    expect(line.factorAtEntry, 12);
    await db.stockCountPost(sessionId);
    // التسوية بالمخزونية: 36 − 24 = زيادة 12 × 25,000 = 300000
    final rows = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE item_id = ? AND warehouse_id = ?',
      variables: [Variable.withInt(packedOilId), Variable.withInt(mainWhId)],
    ).getSingle();
    expect(rows.data['qty_base'], 36);
    expect(rows.data['total_value_minor'], 900000);
  });

  test('إعادة العدّ بالأساسية تمحو اللقطة — آخر عدّ هو المعروض', () async {
    final sessionId = await db.stockCountStart(StockCountStartDraft(
      dateText: date,
      warehouseId: mainWhId,
      scope: StockCountScope.all,
    ));
    await db.stockCountSaveCounts(sessionId, {packedOilId: 36},
        levelsByItemId: {
          packedOilId: StockCountLevelSnapshot(
            unitLevelId: boxLevelId,
            qtyDoc: 3,
            factorAtEntry: 12,
          ),
        });
    await db.stockCountSaveCounts(sessionId, {packedOilId: 24});
    final line = (await db.stockCountLinesOf(sessionId))
        .firstWhere((l) => l.itemId == packedOilId);
    expect(line.countedQtyBase, 24);
    expect(line.unitLevelId, isNull);
    expect(line.qtyDoc, isNull);
    expect(line.factorAtEntry, isNull);
  });

  test('حرس المستوى: العامل المخالف ومستوى مجموعة أخرى وصنف بلا '
      'مجموعة كلها مرفوضة بلا كتابة', () async {
    final sessionId = await db.stockCountStart(StockCountStartDraft(
      dateText: date,
      warehouseId: mainWhId,
      scope: StockCountScope.all,
    ));
    // العامل المخالف: 3 × 12 لا يساوي 35.
    await expectLater(
      () => db.stockCountSaveCounts(sessionId, {packedOilId: 35},
          levelsByItemId: {
            packedOilId: StockCountLevelSnapshot(
              unitLevelId: boxLevelId,
              qtyDoc: 3,
              factorAtEntry: 12,
            ),
          }),
      throwsA(isA<StockCountValidationException>()
          .having((e) => e.errors, 'errors',
              contains(isA<StockCountLevelInvalid>()))),
    );
    // مستوى من مجموعة أخرى.
    await expectLater(
      () => db.stockCountSaveCounts(sessionId, {packedOilId: 36},
          levelsByItemId: {
            packedOilId: StockCountLevelSnapshot(
              unitLevelId: otherLevelId,
              qtyDoc: 3,
              factorAtEntry: 12,
            ),
          }),
      throwsA(isA<StockCountValidationException>()
          .having((e) => e.errors, 'errors',
              contains(isA<StockCountLevelInvalid>()))),
    );
    // صنف بلا مجموعة بمستوى تعبئة.
    await expectLater(
      () => db.stockCountSaveCounts(sessionId, {oilId: 10},
          levelsByItemId: {
            oilId: StockCountLevelSnapshot(
              unitLevelId: boxLevelId,
              qtyDoc: 1,
              factorAtEntry: 12,
            ),
          }),
      throwsA(isA<StockCountValidationException>()
          .having((e) => e.errors, 'errors',
              contains(isA<StockCountLevelInvalid>()))),
    );
    // لا كتابة إطلاقاً: العدّة ما تزال فارغة بعد الرفوض الثلاث.
    final line = (await db.stockCountLinesOf(sessionId))
        .firstWhere((l) => l.itemId == packedOilId);
    expect(line.countedQtyBase, isNull);
  });

  test('«صنف وجدناه» بالتعبئة: 1 علبة = 12 بلقطة محفوظة وزيادة من '
      'الصفر بسعر الشراء', () async {
    final sugarId = await db.insertItem(
        sku: 'G-500',
        name: 'سكر معبأ',
        category: 'مواد غذائية',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 5000,
        salePriceMinor: 7000,
        priceCurrencyId: 1,
        unitGroupId: gid);
    final sessionId = await db.stockCountStart(StockCountStartDraft(
      dateText: date,
      warehouseId: mainWhId,
      scope: StockCountScope.all,
    ));
    await db.stockCountAddFoundItem(sessionId,
        StockCountLineDraft(
      itemId: sugarId,
      countedQtyBase: 12,
      unitLevelId: boxLevelId,
      qtyDoc: 1,
      factorAtEntry: 12,
    ));
    final line = (await db.stockCountLinesOf(sessionId))
        .firstWhere((l) => l.itemId == sugarId);
    expect(line.countedQtyBase, 12);
    expect(line.unitLevelId, boxLevelId);
    expect(line.qtyDoc, 1);
    expect(line.factorAtEntry, 12);
    await db.stockCountSaveCounts(sessionId,
        {packedOilId: 24, oilId: 10, riceId: 20});
    await db.stockCountPost(sessionId);
    // الزيادة من الصفر بسعر الشراء المسجل: 12 × 5,000 = 60000 (D-186)
    final rows = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE item_id = ? AND warehouse_id = ?',
      variables: [Variable.withInt(sugarId), Variable.withInt(mainWhId)],
    ).getSingle();
    expect(rows.data['qty_base'], 12);
    expect(rows.data['total_value_minor'], 60000);
  });
});
}
