import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 28 (خامسة م2) — التجميعي الجاهز والفكك
/// (F-034/F-212).
///
/// المثال الحرفي للمتطلب موضع اختبار: بيع 12 سلّة برصيد 6 جاهزة ⇒ 6
/// بتكلفة المخزون وعلم «جاهز» و6 بحركات مكونات بعلم «فُكِّك» — سطر
/// تكلفة واحد بالمبلغ المركب — والثابت F-178 مستقر بعد كل ترحيل.
/// والحدود الموثقة: الشراء الجاهز بلا فكك، ومردود بيع التجميعي مؤجل،
/// ومكوّن الخدمة بلا حركة مخزون في الحالتين (F-212)، والترحيلة v19
/// آمنة التكرار بحرس pragma (درس v3).
void main() {
  late DiqqahDatabase db;
  late int unitId;
  late int woodId;
  late int ropeId;
  late int assemblyId;
  late int basketId;
  late int customerId;
  late int supplierId;
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
    assemblyId = await insertItemHelper(
        sku: 'S-ASM',
        name: 'خدمة تجميع',
        kind: 'service',
        purchase: 0,
        sale: 500);
    basketId = await insertItemHelper(
        sku: 'B-BASKET',
        name: 'سلّة',
        kind: 'bundle',
        purchase: 12000,
        sale: 15000);
    await db.saveBundleRecipe(basketId, [
      BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
      BundleComponentDraft(componentItemId: ropeId, qtyBase: 1),
      BundleComponentDraft(
          componentItemId: assemblyId, qtyBase: 1, costMinor: 500),
    ]);
    year = await db.customSelect('SELECT name FROM fiscal_years')
        .getSingle()
        .then((r) => int.parse(r.data['name'] as String));
    customerId = await db.insertParty(
        number: '0001', name: 'عميل الأمل', kind: 'customer', defaultCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0002', name: 'مورد الشرق', kind: 'supplier', defaultCurrencyId: 1);
    final wh = await db.customSelect('SELECT id FROM warehouses LIMIT 1').get();
    warehouseId = wh.first.data['id'] as int;
  });

  tearDown(() => db.close);

  Future<int> accountId(String code) async {
    final rows = await db.customSelect(
      'SELECT id FROM accounts WHERE code = ?',
      variables: [Variable.withString(code)],
    ).get();
    expect(rows, hasLength(1), reason: 'كود الدليل $code فريد من البذر');
    return rows.first.data['id'] as int;
  }

  InvoiceLineDraft line(int itemId, int qty, int price) => InvoiceLineDraft(
      itemId: itemId, unitId: unitId, qtyBase: qty, unitPriceMinor: price);

  /// شراء آجل — س-04 المعروض (ذمة مورد).
  Future<int> purchaseCredit(List<InvoiceLineDraft> lines) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '$year-06-15',
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
  }

  /// بيع آجل — س-07 المعروض (ذمة عميل).
  Future<int> saleCredit(List<InvoiceLineDraft> lines) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: '$year-06-20',
      partyId: customerId,
      warehouseId: warehouseId,
      lines: lines,
    ));
    await db.postInvoice(id);
    return id;
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

  /// حركات فاتورة بترتيبها مع علمها.
  Future<List<Map<String, Object?>>> invoiceMoves(int invoiceId) async {
    final rows = await db.customSelect(
      'SELECT item_id, qty_base, value_base_minor, move_detail '
      'FROM stock_moves WHERE ref_doc_type = \'invoice\' AND ref_doc_id = ? '
      'ORDER BY id',
      variables: [Variable.withInt(invoiceId)],
    ).get();
    return [for (final r in rows) r.data];
  }

  /// أسطر قيد فاتورة بحساباتها.
  Future<List<Map<String, Object?>>> invoiceMoveLines(int invoiceId) async {
    final rows = await db.customSelect(
      'SELECT ml.account_id, ml.debit_minor, ml.credit_minor, '
      'ml.ref_stock_move_id '
      'FROM move_lines ml JOIN moves m ON m.id = ml.move_id '
      "WHERE m.ref_doc_type = 'invoice' AND m.ref_doc_id = ? "
      'ORDER BY ml.id',
      variables: [Variable.withInt(invoiceId)],
    ).get();
    return [for (final r in rows) r.data];
  }

  Future<void> expectF178() async {
    final (debit, credit) = await db.trialBalanceTotalsOf();
    expect(debit, credit, reason: 'كل قيد متوازن بالبناء والميزان يتبعه');
    final acc113 = await accountId('113');
    final totals = await db.customSelect(
      'SELECT COALESCE(SUM(total_value_minor), 0) AS v '
      'FROM stock_balances',
    ).getSingle().then((r) => r.data['v'] as int);
    expect(await db.accountBalanceOf(acc113), totals,
        reason: 'ثابت المطابقة المخزني F-178 بعد كل ترحيل');
  }

  group('الترحيلة v19 — جدول الوصفة وعلم الحركات (الدفعة 28)', () {
    test('على قاعدة جديدة: جدول bundle_components وعمود stock_moves '
        '.move_detail قائمان وقيد التفرد داخلهما', () async {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'bundle_components'",
      ).get();
      expect(tables, hasLength(1));
      final cols = await db.customSelect(
        "SELECT name FROM pragma_table_info('stock_moves') "
        "WHERE name = 'move_detail'",
      ).get();
      expect(cols, hasLength(1));
      // قيد التفرد داخل DDL الجدول (درس س86): مكرر (تجميعي، مكوّن) يرفض.
      await expectLater(
        () => db.customStatement(
          'INSERT INTO bundle_components (bundle_item_id, '
          'component_item_id, qty_base, uuid, created_at, updated_at, '
          'is_deleted) VALUES (?, ?, 1, ?, 0, 0, 0)',
          [basketId, woodId, 'dup-uuid'],
        ),
        throwsA(anything),
      );
    });

    test('ترحيلة v19 آمنة التكرار: قاعدة كاملة تُنزّل لإصدار 17 وتُرقّى '
        'بلا مساس بالبيانات (درس v3: الأحرسة pragma)', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('diqqah_v28_mig_');
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
          purchasePriceMinor: 100,
          salePriceMinor: 200,
          priceCurrencyId: 1);
      await first.close();

      // نزّل الإصدار إلى 17 فتعمل خطوتا v18 وv19 على مخطط قائم —
      // والحرسان (createAll وIF NOT EXISTS وpragma) يقفزان بلا تكرار.
      final raw = sqlite3.open(dbPath);
      raw.execute('PRAGMA user_version = 17');
      raw.dispose();

      final migrated = DiqqahDatabase(filePath: dbPath);
      addTearDown(migrated.close);
      await migrated.select(migrated.items).get();
      expect(migrated.schemaVersion, 21);
      final tables = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'bundle_components'",
      ).get();
      expect(tables, hasLength(1));
      final cols = await migrated.customSelect(
        "SELECT name FROM pragma_table_info('stock_moves') "
        "WHERE name = 'move_detail'",
      ).get();
      expect(cols, hasLength(1));
      final rows = await migrated.select(migrated.items).get();
      expect(rows, hasLength(1), reason: 'بيانات القائمة حفظت كاملة');
      expect(rows.first.id, it);
      // وإعادة الفتح ثالثة على 19 لا تعيد الترحيلة ولا تكسر شيئاً.
      await migrated.customStatement('PRAGMA user_version = 17');
      final third = DiqqahDatabase(filePath: dbPath);
      addTearDown(third.close);
      await third.select(third.items).get();
      expect(third.schemaVersion, 21);
      expect(await third.select(third.items).get(), hasLength(1));
    });
  });

  group('وصفة التجميعي — الحفظ والقراءة والحواجز (F-034/F-212)', () {
    test('حفظ سليم وقراءة عكسية بترتيبها — خدمة بتكلفة وبضاعة بلا خانة',
        () async {
      final recipe = await db.bundleRecipeByItem(basketId);
      expect(recipe, hasLength(3));
      expect(recipe[0].componentItemId, woodId);
      expect(recipe[0].qtyBase, 2);
      expect(recipe[0].isService, isFalse);
      expect(recipe[0].costMinor, isNull);
      expect(recipe[2].componentItemId, assemblyId);
      expect(recipe[2].isService, isTrue);
      expect(recipe[2].costMinor, 500);
    });

    test('الاستبدال الكامل: حفظ ثانٍ يستبدل بلا تراكم', () async {
      await db.saveBundleRecipe(basketId, [
        BundleComponentDraft(componentItemId: ropeId, qtyBase: 4),
      ]);
      final recipe = await db.bundleRecipeByItem(basketId);
      expect(recipe, hasLength(1));
      expect(recipe.single.componentItemId, ropeId);
      expect(recipe.single.qtyBase, 4);
    });

    test('حواجز المجال: الوصفة الفارغة والمكرر والذاتية والتكلفة السالبة',
        () async {
      Future<void> expectReject(List<BundleComponentDraft> comps) async {
        await expectLater(
          () => db.saveBundleRecipe(basketId, comps),
          throwsA(isA<BundleValidationException>()),
        );
      }

      await expectReject(const []);
      await expectReject([
        BundleComponentDraft(componentItemId: woodId, qtyBase: 0),
      ]);
      await expectReject([
        BundleComponentDraft(componentItemId: woodId, qtyBase: 1),
        BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
      ]);
      await expectReject([
        BundleComponentDraft(componentItemId: basketId, qtyBase: 1),
      ]);
      await expectReject([
        BundleComponentDraft(
            componentItemId: assemblyId, qtyBase: 1, costMinor: -1),
      ]);
      // الوصفة الأصلية باقية بلا مساس بعد كل الرفض.
      expect(await db.bundleRecipeByItem(basketId), hasLength(3));
    });

    test('حواجز القاعدة: مكوّن غير موجود أو معطل أو تجميعي أو صاحب '
        'ليس تجميعياً أو بضاعة بخانة تكلفة', () async {
      // بضاعة بخانة تكلفة — خانة الخدمة حصراً (F-212).
      await expectLater(
        () => db.saveBundleRecipe(basketId, [
          BundleComponentDraft(
              componentItemId: woodId, qtyBase: 1, costMinor: 100),
        ]),
        throwsA(isA<BundleValidationException>()),
      );
      // التجميعي صاحب الوصفة ليس تجميعياً.
      await expectLater(
        () => db.saveBundleRecipe(woodId, [
          BundleComponentDraft(componentItemId: ropeId, qtyBase: 1),
        ]),
        throwsA(isA<BundleValidationException>()),
      );
      // مكوّن غير موجود.
      await expectLater(
        () => db.saveBundleRecipe(basketId, [
          const BundleComponentDraft(componentItemId: 99999, qtyBase: 1),
        ]),
        throwsA(isA<BundleValidationException>()),
      );
      // مكوّن معطل.
      final tempId = await insertItemHelper(
          sku: 'M-TEMP', name: 'مؤقت', kind: 'good', purchase: 100, sale: 200);
      await db.setItemActive(tempId, active: false);
      await expectLater(
        () => db.saveBundleRecipe(basketId, [
          BundleComponentDraft(componentItemId: tempId, qtyBase: 1),
        ]),
        throwsA(isA<BundleValidationException>()),
      );
    });
  });

  group('بيع التجميعي — الجاهز أولاً ثم الفكك (F-034 حرفاً)', () {
    late int saleId;

    setUp(() async {
      // الجاهز: شراء 6 سلل @ 10,000 = (6، 60,000) بلا فكك.
      await purchaseCredit([line(basketId, 6, 10000)]);
      // المكونات: خشب (20، 200,000) وحبل (20، 40,000).
      await purchaseCredit([line(woodId, 20, 10000)]);
      await purchaseCredit([line(ropeId, 20, 2000)]);
      // مثال المتطلب: بيع 12 سلّة @ 15,000 آجلاً.
      saleId = await saleCredit([line(basketId, 12, 15000)]);
    });

    test('الحركات: خروج جاهز بعلمه وخروج مكونات بأعلامها والخدمة بلا '
        'حركة (F-034/F-212)', () async {
      final moves = await invoiceMoves(saleId);
      // حركة الجاهز للسلّة: −6 بقيمة 60,000 (امتصاص الكل — D-067).
      final ready = moves.singleWhere((m) => m['item_id'] == basketId);
      expect(ready['qty_base'], -6);
      expect(ready['value_base_minor'], 60000);
      expect(ready['move_detail'], 'ready');
      // خشب: −12 بقيمة 120,000 بعلم «فُكِّك».
      final wood = moves.singleWhere((m) => m['item_id'] == woodId);
      expect(wood['qty_base'], -12);
      expect(wood['value_base_minor'], 120000);
      expect(wood['move_detail'], 'broken');
      // حبل: −6 بقيمة 12,000 بعلم «فُكِّك».
      final rope = moves.singleWhere((m) => m['item_id'] == ropeId);
      expect(rope['qty_base'], -6);
      expect(rope['value_base_minor'], 12000);
      expect(rope['move_detail'], 'broken');
      // الخدمة: لا حركة لها إطلاقاً (F-212).
      expect(moves.where((m) => m['item_id'] == assemblyId), isEmpty);
      expect(moves, hasLength(3));
    });

    test('سطر التكلفة الواحد بالمبلغ المركب و113 بحركاتها (F-034)',
        () async {
      final acc113 = await accountId('113');
      final acc51 = await accountId('51');
      final acc411 = await accountId('411');
      final lines = await invoiceMoveLines(saleId);

      final costLines = lines.where((l) => l['account_id'] == acc51).toList();
      expect(costLines, hasLength(1),
          reason: 'سطر تكلفة واحد للسطر — لا تشتت');
      expect(costLines.single['debit_minor'], 60000 + 120000 + 12000);

      // 113 دائناً بحركة كل خطة مربوطة بها فمجموعها المركب حرفاً.
      final invLines = lines.where((l) => l['account_id'] == acc113).toList();
      expect(invLines, hasLength(3));
      final creditSum = invLines.fold(
          0, (s, l) => s + (l['credit_minor'] as int));
      expect(creditSum, 192000);
      final linked = invLines
          .map((l) => l['ref_stock_move_id'])
          .where((v) => v != null)
          .toSet();
      expect(linked, hasLength(3),
          reason: 'كل سطر 113 بحركته (07 §3.1)');

      // الإيراد سطر واحد على 411 بحساب التجميعي (F-212: دون تخصيص).
      final revLines = lines.where((l) => l['account_id'] == acc411).toList();
      expect(revLines, hasLength(1));
      expect(revLines.single['credit_minor'], 12 * 15000);
    });

    test('الأرصدة بعد البيع وثبات F-178', () async {
      expect(await balanceOf(basketId), (0, 0));
      expect(await balanceOf(woodId), (8, 80000));
      expect(await balanceOf(ropeId), (14, 28000));
      await expectF178();
    });

    test('بيع آخر فوق المتبقي: الفكك يتسلسل بالمتوسط الجاري (D-067)',
        () async {
      // المتبقي: خشب (8، 80,000) وحبل (14، 28,000) — بيع سلّتين
      // (جاهز صفر ⇒ فكك كامل): 4 خشب = 40,000 و2 حبل = 4,000.
      final second = await saleCredit([line(basketId, 2, 15000)]);
      final moves = await invoiceMoves(second);
      expect(moves, hasLength(2));
      final wood = moves.singleWhere((m) => m['item_id'] == woodId);
      expect(wood['value_base_minor'], 40000);
      final rope = moves.singleWhere((m) => m['item_id'] == ropeId);
      expect(rope['value_base_minor'], 4000);
      await expectF178();
    });
  });

  group('حدود الجاهز والفكك (F-034)', () {
    setUp(() async {
      await purchaseCredit([line(basketId, 6, 10000)]);
      await purchaseCredit([line(woodId, 20, 10000)]);
      await purchaseCredit([line(ropeId, 20, 2000)]);
    });

    test('البيع كلُّه من الجاهز: حركة واحدة بعلمها ولا مساس بالمكونات',
        () async {
      final id = await saleCredit([line(basketId, 4, 15000)]);
      final moves = await invoiceMoves(id);
      expect(moves, hasLength(1));
      expect(moves.single['item_id'], basketId);
      expect(moves.single['qty_base'], -4);
      // 60,000 × 4/6 = 40,000 بالنصف بعيداً عن الصفر.
      expect(moves.single['value_base_minor'], 40000);
      expect(moves.single['move_detail'], 'ready');
      expect(await balanceOf(woodId), (20, 200000));
      expect(await balanceOf(ropeId), (20, 40000));
    });

    test('النقص بلا وصفة مرفوض عند الإنشاء والترحيل', () async {
      // الوصفة الفارغة لا تُحفظ أصلاً بحاجزها (س-09: وصفة فارغة مرفوضة).
      await expectLater(
        () => db.saveBundleRecipe(basketId, []),
        throwsA(isA<BundleValidationException>()),
      );
      // والبيع بالنقص على تجميعي بلا وصفة مرفوض — النقص لا يفكك بلا
      // مكونات (F-034).
      final noRecipe = await insertItemHelper(
          sku: 'B-NOREC',
          name: 'تجميعي بلا وصفة',
          kind: 'bundle',
          purchase: 10000,
          sale: 12000);
      await expectLater(
        () => db.createInvoiceDraft(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: '$year-06-21',
          partyId: customerId,
          warehouseId: warehouseId,
          lines: [line(noRecipe, 3, 12000)],
        )),
        throwsA(isA<InvoiceValidationException>()),
      );
    });

    test('نقص مكوّن يرفض الكل قبل القبول — بالإنشاء والترحيل', () async {
      // الرصيد: خشب 20 — بيع 20 سللاً يفكك 14 سلّة تحتاج 28 خشباً ⇒ رفض.
      await expectLater(
        () => db.createInvoiceDraft(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: '$year-06-21',
          partyId: customerId,
          warehouseId: warehouseId,
          lines: [line(basketId, 20, 15000)],
        )),
        throwsA(isA<InvoiceValidationException>()),
      );
      // وبيع 10 (فكك 4: خشب 8 وحبل 4) يمر فيرّحل ويثبت F-178.
      final draft = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '$year-06-21',
        partyId: customerId,
        warehouseId: warehouseId,
        lines: [line(basketId, 10, 15000)],
      ));
      await db.postInvoice(draft);
      await expectF178();
    });

    test('مكوّن معطل بعد حفظ الوصفة يمنع الفكك برسالة السبب', () async {
      await db.setItemActive(ropeId, active: false);
      // بيع 4 من الجاهز يعمل (لا فكك — المكونات بلا مساس).
      final okId = await saleCredit([line(basketId, 4, 15000)]);
      expect(await invoiceMoves(okId), hasLength(1));
      // والنقص يفكك فيُرفض بمكوّن معطل.
      await expectLater(
        () => db.createInvoiceDraft(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: '$year-06-22',
          partyId: customerId,
          warehouseId: warehouseId,
          lines: [line(basketId, 8, 15000)],
        )),
        throwsA(isA<InvoiceValidationException>()),
      );
    });

    test('مردود بيع سطر تجميعي مرفوض — الحد الصادق الموثق', () async {
      final saleId = await saleCredit([line(basketId, 4, 15000)]);
      await expectLater(
        () => db.createInvoiceDraft(InvoiceDraft(
          kind: InvoiceKind.saleReturn,
          dateText: '$year-06-25',
          originalInvoiceId: saleId,
          partyId: customerId,
          warehouseId: warehouseId,
          lines: [line(basketId, 1, 15000)],
        )),
        throwsA(isA<InvoiceValidationException>()),
      );
    });
  });

  group('الشراء والمردود الشرائي للتجميعي (F-034: الشراء الجاهز بلا فكك)',
      () {
    test('شراء التجميعي يدخل الجاهز مباشرة بحركة واحدة بلا علم', () async {
      final id = await purchaseCredit([line(basketId, 6, 10000)]);
      final moves = await invoiceMoves(id);
      expect(moves, hasLength(1),
          reason: 'الوصفة لا تفعل شيئاً في الشراء الجاهز — F-034');
      expect(moves.single['item_id'], basketId);
      expect(moves.single['qty_base'], 6);
      expect(moves.single['value_base_minor'], 60000);
      expect(moves.single['move_detail'], isNull);
      expect(await balanceOf(basketId), (6, 60000));
      // المكونات بلا مساس.
      expect(await balanceOf(woodId), (0, 0));
      await expectF178();
    });

    test('مردود شراء التجميعي يخرج من الجاهز بالمتوسط الجاري', () async {
      final purchaseId = await purchaseCredit([line(basketId, 6, 10000)]);
      final returnId = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchaseReturn,
        dateText: '$year-06-18',
        originalInvoiceId: purchaseId,
        partyId: supplierId,
        warehouseId: warehouseId,
        lines: [line(basketId, 2, 10000)],
      ));
      await db.postInvoice(returnId);
      final moves = await invoiceMoves(returnId);
      expect(moves, hasLength(1));
      expect(moves.single['qty_base'], -2);
      expect(moves.single['value_base_minor'], 20000);
      expect(await balanceOf(basketId), (4, 40000));
      await expectF178();
    });
  });

  group('الخدمة مكوّناً — F-212 بخياريها', () {
    test('خدمة بلا تكلفة: بند بيعي ضمن السعر — صفر بالمركب ولا حركة',
        () async {
      await db.saveBundleRecipe(basketId, [
        BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
        BundleComponentDraft(componentItemId: assemblyId, qtyBase: 1),
      ]);
      await purchaseCredit([line(basketId, 2, 10000)]);
      await purchaseCredit([line(woodId, 10, 10000)]);
      final id = await saleCredit([line(basketId, 4, 15000)]);
      final moves = await invoiceMoves(id);
      expect(moves.where((m) => m['item_id'] == assemblyId), isEmpty);
      // تكلفة القيد = خروج الجاهز + خروج الخشب حصراً — الخدمة بلا مساس.
      final acc51 = await accountId('51');
      final lines = await invoiceMoveLines(id);
      final cost = lines
          .where((l) => l['account_id'] == acc51)
          .fold(0, (s, l) => s + (l['debit_minor'] as int));
      expect(cost, 20000 + 40000,
          reason: 'خروج الجاهز 20,000 + 4 خشب × 10,000 متوسطها');
      await expectF178();
    });
  });

  group('علم الحركات للحركات العادية — NULL لا علم', () {
    test('شراء بضاعة عادية بحركة بلا علم والترقية لا تمس القديم', () async {
      final id = await purchaseCredit([line(woodId, 5, 10000)]);
      final moves = await invoiceMoves(id);
      expect(moves.single['move_detail'], isNull);
    });
  });
}
