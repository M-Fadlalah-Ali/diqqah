import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 29 (سادسة م2) — مستند التجميع (F-211، س88).
///
/// معيار الجاهزية المعتمد (04): «تجميع 10 سلل ينقص مكوناتها ويضيف 10
/// جاهزة بتكلفة المكونات وتستقر قيمة 113» — موضع اختبار حرفاً مع
/// الثابت F-178 بعد كل ترحيل. والحدود الصادقة الموثقة: التجميع بلا
/// قيد محاسبي (نقل قيمة داخل 113 بروح النقل D-185 فبلا حاجز فترة)،
/// والمكوّن الخدمي لا يُسحب (F-212/F-211 — قيمته من البيع لا البناء
/// معروضاً مع D-190)، والرفض لا يحرق رقماً (07 §1.9)، والتجميد
/// نمط F-140.
void main() {
  late DiqqahDatabase db;
  late int unitId;
  late int woodId;
  late int ropeId;
  late int serviceId;
  late int basketId;
  late int warehouseId;
  late int year;

  Future<int> insertItemHelper({
    required String sku,
    required String name,
    required String kind,
    required int purchase,
    required int sale,
  }) {
    return db.insertItem(
      sku: sku,
      name: name,
      kind: kind,
      baseUnitId: unitId,
      purchasePriceMinor: purchase,
      salePriceMinor: sale,
      priceCurrencyId: 1,
    );
  }

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    unitId = await db.insertUnit(name: 'قطعة');
    woodId = await insertItemHelper(
        sku: 'M-WOOD', name: 'خشب', kind: 'good', purchase: 10000, sale: 15000);
    ropeId = await insertItemHelper(
        sku: 'M-ROPE', name: 'حبل', kind: 'good', purchase: 2000, sale: 3000);
    serviceId = await insertItemHelper(
        sku: 'S-ASM', name: 'خدمة تجميع', kind: 'service',
        purchase: 0, sale: 500);
    basketId = await insertItemHelper(
        sku: 'B-BASKET', name: 'سلّة', kind: 'bundle',
        purchase: 12000, sale: 15000);
    await db.saveBundleRecipe(basketId, [
      BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
      BundleComponentDraft(componentItemId: ropeId, qtyBase: 1),
      BundleComponentDraft(
          componentItemId: serviceId, qtyBase: 1, costMinor: 500),
    ]);
    year = await db.customSelect('SELECT name FROM fiscal_years')
        .getSingle()
        .then((r) => int.parse(r.data['name'] as String));
    await db.insertParty(
        number: '0002', name: 'مورد الشرق', kind: 'supplier',
        defaultCurrencyId: 1);
    final wh = await db.customSelect('SELECT id FROM warehouses LIMIT 1').get();
    warehouseId = wh.first.data['id'] as int;
  });

  tearDown(() => db.close);

  /// شراء آجل بذر مخزون — س-04 المعروض (نمط batch28).
  Future<void> purchase(int itemId, int qty, int price) async {
    final supplier = (await db.customSelect(
      "SELECT id FROM parties WHERE kind = 'supplier' LIMIT 1",
    ).getSingle()).data['id'] as int;
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '$year-06-15',
      partyId: supplier,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: qty,
            unitPriceMinor: price),
      ],
    ));
    await db.postInvoice(id);
  }

  Future<(int, int)> balanceOf(int itemId) async {
    final rows = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE item_id = ? AND warehouse_id = ?',
      variables: [Variable.withInt(itemId), Variable.withInt(warehouseId)],
    ).get();
    if (rows.isEmpty) return (0, 0);
    final d = rows.first.data;
    return (d['qty_base'] as int, d['total_value_minor'] as int);
  }

  Future<int> stockValueTotal() async {
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(total_value_minor), 0) AS v FROM stock_balances',
    ).getSingle();
    return rows.data['v'] as int;
  }

  Future<int> journalCount() async {
    final rows = await db.customSelect(
      "SELECT COUNT(*) AS c FROM moves WHERE ref_doc_type = 'assembly'",
    ).getSingle();
    return rows.data['c'] as int;
  }

  Future<void> expectF178() async {
    final (debit, credit) = await db.trialBalanceTotalsOf();
    expect(debit, credit, reason: 'كل قيد متوازن بالبناء والميزان يتبعه');
    final acc113 = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '113'",
    ).getSingle()).data['id'] as int;
    final totals = await stockValueTotal();
    expect(await db.accountBalanceOf(acc113), totals,
        reason: 'ثابت المطابقة المخزني F-178 بعد كل ترحيل');
  }

  group('الترحيلة v20 — جدولا التجميع والتجميد (الدفعة 29)', () {
    test('على قاعدة جديدة: جدولا assemblies وassembly_lines قائمان '
        'والتجميد نمط F-140 يرفض التعديل والحذف', () async {
      for (final table in ['assemblies', 'assembly_lines']) {
        final tables = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = ?",
          variables: [Variable.withString(table)],
        ).get();
        expect(tables, hasLength(1), reason: 'جدول $table مبني');
      }
      await db.customStatement(
        "INSERT INTO assemblies (number, assembly_date, warehouse_id, "
        "bundle_item_id, qty_base, total_value_minor, state, uuid) "
        "VALUES ('X', '$year-06-20', ?, ?, 1, 0, 'posted', 'u1')",
        [warehouseId, basketId],
      );
      await db.customStatement(
        "INSERT INTO assembly_lines (assembly_id, item_id, qty_base, "
        "uuid) VALUES (1, ?, 1, 'u2')",
        [woodId],
      );
      await expectLater(
        () => db.customStatement('UPDATE assemblies SET qty_base = 9'),
        throwsA(anything),
        reason: 'الرأس مجمّد — لا تعديل (نمط F-140)',
      );
      await expectLater(
        () => db.customStatement('DELETE FROM assemblies'),
        throwsA(anything),
        reason: 'الرأس لا يُحذف — لقطة تاريخية',
      );
      await expectLater(
        () => db.customStatement(
            'UPDATE assembly_lines SET value_base_minor = 1'),
        throwsA(anything),
        reason: 'السطر مجمّد كذلك',
      );
    });

    test('ترحيلة v20 آمنة التكرار: قاعدة كاملة تُنزّل لإصدار 18 وتُرقّى '
        'بلا مساس بالبيانات (درس v3: الأحرسة pragma)', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('diqqah_v29_mig_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dbPath = p.join(tempDir.path, 'migrate.db');

      // قاعدة كاملة بالمخطط الحالي مع بيانات حية تُحفظ بعد الدورة.
      final first = DiqqahDatabase(filePath: dbPath);
      final u = await first.insertUnit(name: 'قطعة');
      final it = await first.insertItem(
          sku: 'OLD-1',
          name: 'قديم',
          kind: 'good',
          baseUnitId: u,
          purchasePriceMinor: 700,
          salePriceMinor: 900,
          priceCurrencyId: 1);
      final supplier = await first.insertParty(
          number: '0002', name: 'مورد', kind: 'supplier',
          defaultCurrencyId: 1);
      final wh = await first.customSelect(
          'SELECT id FROM warehouses LIMIT 1').getSingle();
      final inv = await first.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: '$year-06-15',
        partyId: supplier,
        warehouseId: wh.data['id'] as int,
        lines: [
          InvoiceLineDraft(
              itemId: it, unitId: u, qtyBase: 3, unitPriceMinor: 700),
        ],
      ));
      await first.postInvoice(inv);
      await first.close();

      // نزّل الإصدار إلى 18 فتعمل خطوتا v19 وv20 على مخطط قائم —
      // والأحرسة (createAll وIF NOT EXISTS وpragma) تقفز بلا تكرار.
      final raw = sqlite3.open(dbPath);
      raw.execute('PRAGMA user_version = 18');
      raw.dispose();

      final migrated = DiqqahDatabase(filePath: dbPath);
      addTearDown(migrated.close);
      await migrated.select(migrated.items).get();
      expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);
      final bal = await migrated.customSelect(
        'SELECT qty_base, total_value_minor FROM stock_balances '
        'WHERE item_id = ?',
        variables: [Variable.withInt(it)],
      ).getSingle();
      expect(bal.data['qty_base'], 3, reason: 'البيانات الحية لا تُمس');
      expect(bal.data['total_value_minor'], 2100);
      for (final table in ['assemblies', 'assembly_lines']) {
        final tables = await migrated.customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = ?",
          variables: [Variable.withString(table)],
        ).get();
        expect(tables, hasLength(1), reason: '$table يُبنى بالترقية');
      }
    });
  });

  group('معيار الجاهزية المعتمد حرفاً — تجميع 10 سلل (F-211)', () {
    setUp(() async {
      await purchase(woodId, 100, 10000); // قيمة 1,000,000
      await purchase(ropeId, 100, 2000); // قيمة 200,000
    });

    test('تجميع 10 سلل: ينقص المكونات ويضيف 10 جاهزة بتكلفة المكونات '
        'وتستقر قيمة 113 (الثابت F-178) وبلا قيد محاسبي إطلاقاً', () async {
      final before = await stockValueTotal();
      final journalBefore = await journalCount();

      final id = await db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 10,
      ));
      expect(id, greaterThan(0));

      // الواقع المخزني: خشب 100-20=80 بقيمة 800,000 وحبل 100-10=90
      // بقيمة 180,000 وسلّة 10 بقيمة 220,000 (2×10000+1×2000)×10.
      final wood = await balanceOf(woodId);
      expect(wood, (80, 800000));
      final rope = await balanceOf(ropeId);
      expect(rope, (90, 180000));
      final basket = await balanceOf(basketId);
      expect(basket, (10, 220000), reason: 'الناتج بتكلفة مكوناته حصراً');

      // الثابت F-178: المجموع قبل وبعد واحد — نقل قيمة لا خلق قيمة.
      expect(await stockValueTotal(), before);

      // بلا قيد محاسبي (F-211): لا صف قيد بمرجع التجميع وحساب 113
      // لم يتغير — عين النقل بين المستودعات.
      expect(await journalCount(), journalBefore);
      final acc113 = (await db.customSelect(
        "SELECT id FROM accounts WHERE code = '113'",
      ).getSingle()).data['id'] as int;
      expect(await db.accountBalanceOf(acc113), 1200000,
          reason: 'قيمة 113 من مشتريات البذر وحدها — التجميع لا يمسها');
      await expectF178();

      // حركات المخزون بمرجع التجميع: خروج لكل مكون بضاعٍ (اثنان)
      // ودخول واحد للناتج — والخدمة بلا حركة (F-212).
      final moves = await db.customSelect(
        'SELECT item_id, qty_base, value_base_minor, move_detail '
        "FROM stock_moves WHERE ref_doc_type = 'assembly' ORDER BY id",
      ).get();
      expect(moves, hasLength(3),
          reason: 'خروج لكل مكون بضاعٍ ودخول للناتج — والخدمة بلا حركة');
      expect((moves[0].data['qty_base'] as int), -20);
      expect((moves[1].data['qty_base'] as int), -10);
      expect((moves[2].data['item_id'] as int), basketId);
      expect((moves[2].data['qty_base'] as int), 10);
      expect((moves[2].data['value_base_minor'] as int), 220000);
      // علم الحركات عادي (NULL) — علم «جاهز/فُكِّك» شأن بيع الفكك.
      for (final m in moves) {
        expect(m.data['move_detail'], isNull);
      }
      // لقطة الأسطر: سطرا مكونات البضاعة بقيمهما — والخدمة بلا سطر.
      final lines = await db.assemblyLinesOf(id);
      expect(lines, hasLength(2), reason: 'المكون الخدمي بلا سطر (F-212)');
      expect(lines[0].itemId, woodId);
      expect(lines[0].qtyBase, 20);
      expect(lines[0].valueBaseMinor, 200000);
      expect(lines[1].itemId, ropeId);
      expect(lines[1].qtyBase, 10);
      expect(lines[1].valueBaseMinor, 20000);
    });

    test('الرقم من تسلسل سنوي مستقل داخل المعاملة والرفض لا يحرق رقماً '
        '(07 §1.9)', () async {
      // رفض أولاً: تجميعي آخر بلا وصفة — ثم نجاح فيحمل الرقم الأول.
      final plain = await insertItemHelper(
          sku: 'M-PLAIN', name: 'صنف عادي', kind: 'good',
          purchase: 100, sale: 150);
      await expectLater(
        () => db.assemblyPost(AssemblyDraft(
          dateText: '$year-06-20',
          warehouseId: warehouseId,
          bundleItemId: plain,
          qtyBundles: 1,
        )),
        throwsA(isA<AssemblyValidationException>()),
      );
      final id = await db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-21',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 2,
      ));
      final number = (await db.customSelect(
        'SELECT number FROM assemblies WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).getSingle()).data['number'] as String;
      // صيغة الرقم الصافي أرقاماً (س56/D-152): بادئة السنة بخانتين ثم
      // العدّاد بست خانات افتراضاً — '26' + '000001'.
      expect(number, '${year % 100}000001',
          reason: 'الرفض لا يحرق رقماً فالنجاح الأول يحمل عدّاد 1');
      // والتسلسل مستقل: سطر تسلسل واحد للتجميع وحده.
      final seq = await db.customSelect(
        "SELECT last_number FROM sequences WHERE kind = 'assembly'",
      ).getSingle();
      expect(seq.data['last_number'], 1,
          reason: 'الرفض لا يحرق — عدّاد التسلسل الواحد على 1');
    });

    test('المكوّن الخدمي لا يُسحب ولا يُقوّم — قيمة الناتج من المخزني '
        'حصراً (F-212/F-211 الحد الصادق)', () async {
      final id = await db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 4,
      ));
      // (2×10000 + 1×2000)×4 = 88,000 بلا تكلفة الخدمة 500×4=2,000.
      final basket = await balanceOf(basketId);
      expect(basket, (4, 88000),
          reason: 'تكلفة الخدمة لا تدخل قيمة البناء — من البيع لا البناء');
      final serviceMoves = await db.customSelect(
        "SELECT COUNT(*) AS c FROM stock_moves WHERE item_id = ? "
        "AND ref_doc_type = 'assembly'",
        variables: [Variable.withInt(serviceId)],
      ).getSingle();
      expect(serviceMoves.data['c'], 0,
          reason: 'الخدمة بلا حركة مخزون في الحالتين (F-212)');
      final serviceLines = await db.assemblyLinesOf(id);
      expect(
          serviceLines.where((l) => l.itemId == serviceId), isEmpty);
    });

    test('المعاينة هي التنفيذ (D-183): أسطر المعاينة بقيم الترحيل عينها',
        () async {
      final preview = await db.assemblyPreview(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 10,
      );
      expect(preview.errors, isEmpty);
      expect(preview.bundleLabel, contains('سلّة'));
      expect(preview.lines, hasLength(3),
          reason: 'مكونا البضاعة والخدمة بعلمها ظاهران');
      final wood = preview.lines.firstWhere((l) => l.itemId == woodId);
      expect(wood.qtyNeeded, 20);
      expect(wood.qtyAvailable, 100);
      expect(wood.valueMinor, 200000);
      final service =
          preview.lines.firstWhere((l) => l.itemId == serviceId);
      expect(service.isService, isTrue);
      expect(service.qtyNeeded, 0);
      expect(service.valueMinor, 0);
      expect(preview.totalValueMinor, 220000,
          reason: 'القيمة التقديرية مجموع المخزني حصراً');
    });

    test('المعاينة الرافضة تحمل أخطاء الاكتفاء كاملةً لا تخفيها (F-042) — '
        'والمكوّن الكافي بلا خطأ', () async {
      final preview = await db.assemblyPreview(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 60,
      );
      expect(preview.errors.whereType<AssemblyComponentInsufficient>(),
          hasLength(1), reason: 'الخشب وحده ناقص (120>100)');
      expect(
          describeAssemblyValidationError(preview.errors.first),
          contains('منع السالب'));
      // والقيمة التقديرية بالمتصاص الكامل للناقص والتقسيم للكافي
      // (روح D-067): خشب 1,000,000 كاملاً + حبل 200,000×60/100=120,000
      // — لكن هي تقدير لا تنفذ لأن الأخطاء تحجب الترحيل.
      expect(preview.totalValueMinor, 1120000);
    });

    test('اكتفاء المكونات منع السالب (F-042): تجميع أكثر من المتاح يرفض '
        'بالأخطاء كاملة ولا يكتب شيئاً ولا رقم يُحرق', () async {
      final before = await stockValueTotal();
      final movesBefore = await db.customSelect(
        "SELECT COUNT(*) AS c FROM stock_moves WHERE "
        "ref_doc_type = 'assembly'",
      ).getSingle();
      await expectLater(
        () => db.assemblyPost(AssemblyDraft(
          dateText: '$year-06-20',
          warehouseId: warehouseId,
          bundleItemId: basketId,
          qtyBundles: 60,
        )),
        throwsA(isA<AssemblyValidationException>().having(
          (e) => e.errors.whereType<AssemblyComponentInsufficient>(),
          'خطأ الاكتفاء',
          // الخشب وحده ناقص (120>100) — والحبل يكفي (60≤100): رسالة
          // أول خطأ واحدة والأخطاء محصورة بالمنقص حصراً.
          hasLength(1),
        )),
      );
      expect(await stockValueTotal(), before, reason: 'لا كتابة قيمة');
      final movesAfter = await db.customSelect(
        "SELECT COUNT(*) AS c FROM stock_moves WHERE "
        "ref_doc_type = 'assembly'",
      ).getSingle();
      expect(movesAfter.data['c'], movesBefore.data['c']);
      final docs = await db.customSelect(
        'SELECT COUNT(*) AS c FROM assemblies',
      ).getSingle();
      expect(docs.data['c'], 0, reason: 'لا رأس بترحيل مرفوض');
    });

    test('تجميعي بلا وصفة يرفض (س-09 روحاً) — والوصفة القائمة شرط', () async {
      final bare = await insertItemHelper(
          sku: 'B-BARE', name: 'تجميعي أجرى', kind: 'bundle',
          purchase: 5000, sale: 7000);
      await expectLater(
        () => db.assemblyPost(AssemblyDraft(
          dateText: '$year-06-20',
          warehouseId: warehouseId,
          bundleItemId: bare,
          qtyBundles: 1,
        )),
        throwsA(isA<AssemblyValidationException>().having(
          (e) => e.errors.first, 'أول خطأ',
          isA<AssemblyRecipeRequired>(),
        )),
      );
    });

    test('مستودع معطل وصنف غير تجميعي يرفضان على ما خُزّن', () async {
      final inactive = await db.warehouseCreate(name: 'فرع مغلق');
      await db.warehouseSetActive(id: inactive, active: false);
      await expectLater(
        () => db.assemblyPost(AssemblyDraft(
          dateText: '$year-06-20',
          warehouseId: inactive,
          bundleItemId: basketId,
          qtyBundles: 1,
        )),
        throwsA(isA<AssemblyValidationException>().having(
          (e) => e.errors.first, 'أول خطأ',
          isA<AssemblyWarehouseInactive>(),
        )),
      );
      await expectLater(
        () => db.assemblyPost(AssemblyDraft(
          dateText: '$year-06-20',
          warehouseId: warehouseId,
          bundleItemId: woodId,
          qtyBundles: 1,
        )),
        throwsA(isA<AssemblyValidationException>().having(
          (e) => e.errors.first, 'أول خطأ',
          isA<AssemblyBundleItemNotBundle>(),
        )),
      );
    });

    test('بلا حاجز فترة: تجميع داخل فترة مقفلة يمر — الأرصدة حالية لا '
        'تاريخية (عين قرار التحويل D-185، والتجميع بلا قيد F-211)',
        () async {
      final periods = await db.ledgerPeriods();
      final period = periods.firstWhere((p) => p.contains('$year-06-20'));
      await db.closePeriod(period.id, draftsConfirmed: true);
      final id = await db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 1,
      ));
      expect(id, greaterThan(0), reason: 'لا حاجز فترة على بلا القيد');
      final basket = await balanceOf(basketId);
      expect(basket, (1, 22000));
    });
  });

  group('السجل والقراءات', () {
    setUp(() async {
      await purchase(woodId, 100, 10000);
      await purchase(ropeId, 100, 2000);
    });

    test('assembliesOf بأسمائه المحسوبة والأحدث أولاً — ولقطة الأسطر '
        'بقيمها المخزنة (F-140)', () async {
      await db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 3,
      ));
      await db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-22',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 2,
      ));
      final docs = await db.assembliesOf();
      expect(docs, hasLength(2));
      expect(docs.first.assemblyDate, '$year-06-22',
          reason: 'الأحدث أولاً');
      expect(docs.first.qtyBase, 2);
      expect(docs.first.totalValueMinor, 44000);
      expect(docs.first.warehouseName, isNotNull);
      expect(docs.first.bundleName, 'سلّة');
      expect(docs.first.lineCount, 2);
      expect(docs.first.state, 'posted');
      final lines = await db.assemblyLinesOf(docs.last.id);
      expect(lines, hasLength(2));
      expect(lines[0].itemName, 'خشب');
      expect(lines[0].qtyBase, 6);
      expect(lines[0].valueBaseMinor, 60000);
      expect(lines[1].itemName, 'حبل');
      expect(lines[1].qtyBase, 3);
      expect(lines[1].valueBaseMinor, 6000);
    });

    test('حدث posted بلقطة كاملة في سجل الأحداث (07 §2.3)', () async {
      final id = await db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: basketId,
        qtyBundles: 1,
      ));
      final events = await db.customSelect(
        "SELECT entity_type, entity_id, action FROM events "
        "WHERE entity_type = 'assembly' ORDER BY id DESC LIMIT 1",
      ).getSingle();
      expect(events.data['entity_id'], id);
      expect(events.data['action'], 'posted');
    });
  });

/// س115 — الشطر الثاني من حدّا الدفعة 30: الناتج بالتعبئة بلقطة
/// المستوى على رأس التجميع (نمط الفواتير س89 والإذنين والتحويل
/// س113) — والوصفة بالأساسية نص F-211 ثابت لا مساس بها.
group('س115 — التجميع بالتعبئة (حدّا الدفعة 30 — الشطر الثاني)', () {
  late int gid;
  late int cartonLevelId;
  late int packedBasketId;

  setUp(() async {
    gid = await db.insertUnitGroup(
        name: 'تعبئة السلال', levels: [(name: 'كرتونة', factor: 12)]);
    cartonLevelId = (await db.levelsOfGroup(gid)).single.id;
    packedBasketId = await db.insertItem(
        sku: 'B-PACKED',
        name: 'سلّة معبأة',
        kind: 'bundle',
        baseUnitId: unitId,
        purchasePriceMinor: 12000,
        salePriceMinor: 15000,
        priceCurrencyId: 1,
        unitGroupId: gid);
    await db.saveBundleRecipe(packedBasketId, [
      BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
      BundleComponentDraft(componentItemId: ropeId, qtyBase: 1),
    ]);
    await purchase(woodId, 100, 10000);
    await purchase(ropeId, 100, 2000);
  });

  test('تجميع بالتعبئة: 2 كرتونة = 24 باللقطة المحفوظة والوصفة '
      'بالأساسية ثابتة وثابت 113 باقٍ', () async {
    final before = await stockValueTotal();
    final id = await db.assemblyPost(AssemblyDraft(
      dateText: '$year-06-20',
      warehouseId: warehouseId,
      bundleItemId: packedBasketId,
      qtyBundles: 24,
      unitLevelId: cartonLevelId,
      qtyDoc: 2,
      factorAtEntry: 12,
    ));
    // الرأس حمل اللقطة الثلاثية.
    final head = await db.customSelect(
      'SELECT qty_base, unit_level_id, qty_doc, factor_at_entry '
      'FROM assemblies WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle();
    expect(head.data['qty_base'], 24);
    expect(head.data['unit_level_id'], cartonLevelId);
    expect(head.data['qty_doc'], 2);
    expect(head.data['factor_at_entry'], 12);
    // الوصفة بالأساسية كما هي: خشب 48 وحبل 24 — والناتج 24 بقيمة
    // مكوناته (480,000 + 48,000 = 528,000 بكلفة 22,000).
    expect(await balanceOf(woodId), (52, 520000));
    expect(await balanceOf(ropeId), (76, 152000));
    expect(await balanceOf(packedBasketId), (24, 528000));
    expect(await stockValueTotal(), before, reason: 'الثابت F-178 باقٍ');
    // والسجل يقرأ اللقطة للعرض («2 (بالمستوى) = 24»).
    final docs = await db.assembliesOf();
    final row = docs.firstWhere((d) => d.id == id);
    expect(row.qtyBase, 24);
    expect(row.unitLevelId, cartonLevelId);
    expect(row.qtyDoc, 2);
    expect(row.factorAtEntry, 12);
  });

  test('حرس المستوى: العامل المخالف مرفوض بلا كتابة — والمعاينة تعرض '
      'الخطأ ذاته قبل الترحيل (D-183)', () async {
    // 2 × 12 لا يساوي 20.
    await expectLater(
      () => db.assemblyPost(AssemblyDraft(
        dateText: '$year-06-20',
        warehouseId: warehouseId,
        bundleItemId: packedBasketId,
        qtyBundles: 20,
        unitLevelId: cartonLevelId,
        qtyDoc: 2,
        factorAtEntry: 12,
      )),
      throwsA(isA<AssemblyValidationException>()
          .having((e) => e.errors, 'errors',
              contains(isA<AssemblyLevelInvalid>()))),
    );
    final preview = await db.assemblyPreview(
      dateText: '$year-06-20',
      warehouseId: warehouseId,
      bundleItemId: packedBasketId,
      qtyBundles: 20,
      unitLevelId: cartonLevelId,
      qtyDoc: 2,
      factorAtEntry: 12,
    );
    expect(preview.errors.whereType<AssemblyLevelInvalid>(), isNotEmpty,
        reason: 'المعاينة هي التنفيذ — الخطأ يُرى قبل الرفض');
    // ولا مستند كُتب بعد الرفض (الرفض قبل الكتابة حصراً — نمط س-18).
    final count = await db.customSelect(
      'SELECT COUNT(*) AS c FROM assemblies',
    ).getSingle();
    expect(count.data['c'], 0);
  });

  test('الأساسية كما اعتاد: التجميع بلا لقطة يخزن NULL — والقائمة '
      'القائمة بلا مساس', () async {
    final id = await db.assemblyPost(AssemblyDraft(
      dateText: '$year-06-20',
      warehouseId: warehouseId,
      bundleItemId: packedBasketId,
      qtyBundles: 1,
    ));
    final head = await db.customSelect(
      'SELECT unit_level_id, qty_doc, factor_at_entry FROM assemblies '
      'WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle();
    expect(head.data['unit_level_id'], isNull);
    expect(head.data['qty_doc'], isNull);
    expect(head.data['factor_at_entry'], isNull);
  });
});
}
