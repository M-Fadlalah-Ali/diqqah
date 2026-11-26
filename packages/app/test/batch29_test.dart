import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/assembly_screen.dart';
import 'package:diqqah_app/warehouses_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 29 (سادسة م2) — شاشة مستند التجميع والزر الخامس
/// ببطاقة المخزون (F-211، س88).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26)، ورسالة المحرك برسالتها لا صياغة واجهة موازية،
/// والمعاينة الحية تتجدد لحظة الكتابة (درس س79: الفرق الحي بonChanged).
Future<void> _seedAssemblyGround(DiqqahDatabase db) async {
  // بذرة بالرئيسي: 100 خشب ×10000 و100 حبل ×2000 — ووصفة سلّة
  // (2 خشب + 1 حبل + خدمة بتكلفة 500) — نمط batch28/batch26.
  final yearRows = await db.customSelect('SELECT name FROM fiscal_years').get();
  final year = int.parse(yearRows.single.data['name'] as String);
  final date = '$year-06-15';
  final unitId = await db.insertUnit(name: 'قطعة');
  Future<int> item(String sku, String name, String kind, int purchase,
          int sale) =>
      db.insertItem(
          sku: sku,
          name: name,
          kind: kind,
          baseUnitId: unitId,
          purchasePriceMinor: purchase,
          salePriceMinor: sale,
          priceCurrencyId: 1);
  final woodId = await item('M-WOOD', 'خشب', 'good', 10000, 15000);
  final ropeId = await item('M-ROPE', 'حبل', 'good', 2000, 3000);
  final serviceId = await item('S-ASM', 'خدمة تجميع', 'service', 0, 500);
  final basketId = await item('B-BASKET', 'سلّة', 'bundle', 12000, 15000);
  await db.saveBundleRecipe(basketId, [
    BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
    BundleComponentDraft(componentItemId: ropeId, qtyBase: 1),
    BundleComponentDraft(
        componentItemId: serviceId, qtyBase: 1, costMinor: 500),
  ]);
  final supplierId = await db.insertParty(
      number: '0001', name: 'مورد الشرق', kind: 'supplier',
      defaultCurrencyId: 1);
  final mainId = (await db.customSelect(
    'SELECT id FROM warehouses ORDER BY id LIMIT 1',
  ).getSingle()).data['id'] as int;
  final purchase = await db.createInvoiceDraft(InvoiceDraft(
    kind: InvoiceKind.purchase,
    dateText: date,
    partyId: supplierId,
    warehouseId: mainId,
    lines: [
      InvoiceLineDraft(
          itemId: woodId, unitId: unitId, qtyBase: 100, unitPriceMinor: 10000),
      InvoiceLineDraft(
          itemId: ropeId, unitId: unitId, qtyBase: 100, unitPriceMinor: 2000),
    ],
  ));
  await db.postInvoice(purchase);
}

Future<void> _pumpAssemblyScreen(
  WidgetTester tester,
  DiqqahDatabase db,
) async {
  await tester.pumpWidget(MaterialApp(home: AssemblyScreen(db: db)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول (س35/س36) وعلاج الدفعة 26 المزدوج: سحبات مهدأة
  /// بالضخ ثم قفزة ensureVisible بلا زخم — ولا scrollUntilVisible.
  Future<void> _scrollTo(WidgetTester tester, String label) async {
    for (var i = 0; i < 12; i++) {
      if (find.text(label).evaluate().isNotEmpty) break;
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('بطاقة المخزون: زر التجميع خامس الأزرار ظاهراً لا مدفوناً '
      '(درس D-098) ويفتح شاشة التجميع بعنوانها', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('إذن إدخال مخزون'), findsOneWidget);
    expect(find.text('إذن إخراج مخزون'), findsOneWidget);
    expect(find.text('تحويل بين مستودعين'), findsOneWidget);
    expect(find.text('جرد المخزون'), findsOneWidget);
    expect(find.text('تجميع'), findsOneWidget);

    await tester.tap(find.text('تجميع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('مستند التجميع'), findsOneWidget);
  });

  testWidgets('تجميع كامل من الشاشة: المعاينة الحية بالمكونات ثم ترحيل '
      'بالرقم والناتج بقيمة مكوناته وF-178 مستقر (معيار الجاهزية حرفاً)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedAssemblyGround(db);

    await _pumpAssemblyScreen(tester, db);

    // اختيار الصنف التجميعي — الأول في القائمة سلّة.
    await tester.tap(find
        .widgetWithText(DropdownButtonFormField<int>, 'الصنف التجميعي '
            '(صاحب الوصفة)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('سلّة (B-BASKET)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // المعاينة الحية بعد اختيار الكمية — تتجدد لحظة الكتابة (درس س79).
    await tester.enterText(
        find.widgetWithText(TextField, 'عدد الوحدات المنتجة'), '10');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('خشب (M-WOOD) × 20'), findsOneWidget);
    expect(find.textContaining('حبل (M-ROPE) × 10'), findsOneWidget);
    expect(find.textContaining('خدمة تجميع'), findsOneWidget,
        reason: 'المكوّن الخدمي ظاهر بعِلمه (F-212/F-211)');
    expect(find.textContaining('220,000'), findsWidgets,
        reason: 'القيمة التقديرية مجموع المخزني حصراً');

    await _scrollTo(tester, 'ترحيل التجميع');
    await tester.tap(find.widgetWithText(FilledButton, 'ترحيل التجميع'));
    await tester.pump();
    // المضخة تحت مدة الإخطار (5 ثوانٍ) كيبقى ظاهراً للعين الزائفة
    // (نمط batch24..28) — ولا pumpAndSettle أبداً (درس س22..س26).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('رُحّل مستند التجميع'), findsOneWidget);

    // الواقع: خشب 80 بقيمة 800,000 وحبل 90 بـ180,000 وسلّة 10 بـ220,000
    // — ومجموع القيم 1,200,000 كما كان قبل التجميع (F-178) — والترتيب
    // بمعرف الصنف: الخشب أول المولّدات فأول الصفوف.
    final bal = await db.customSelect(
      'SELECT item_id, qty_base, total_value_minor FROM stock_balances '
      'ORDER BY item_id',
    ).get();
    expect(bal, hasLength(3));
    expect(bal[0].data['qty_base'], 80);
    expect(bal[0].data['total_value_minor'], 800000);
    expect(bal[1].data['qty_base'], 90);
    expect(bal[1].data['total_value_minor'], 180000);
    expect(bal[2].data['qty_base'], 10);
    expect(bal[2].data['total_value_minor'], 220000);
    final total = await db.customSelect(
      'SELECT COALESCE(SUM(total_value_minor), 0) AS v FROM stock_balances',
    ).getSingle();
    expect(total.data['v'], 1200000);
    final journal = await db.customSelect(
      "SELECT COUNT(*) AS c FROM moves WHERE ref_doc_type = 'assembly'",
    ).getSingle();
    expect(journal.data['c'], 0, reason: 'بلا قيد محاسبي (F-211)');
    // والسجل أظهر المستند.
    expect(find.textContaining('آخر التجميعات'), findsOneWidget);
    expect(find.textContaining('سلّة (B-BASKET) × 10'), findsOneWidget);
  });

  testWidgets('اكتفاء المكونات: المعاينة تعرض رسالة منع السالب الصادقة '
      '(F-042) وزر الترحيل معطل فلا يكتب شيئاً (المعاينة هي التنفيذ '
      'D-183)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedAssemblyGround(db);

    await _pumpAssemblyScreen(tester, db);

    await tester.tap(find
        .widgetWithText(DropdownButtonFormField<int>, 'الصنف التجميعي '
            '(صاحب الوصفة)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('سلّة (B-BASKET)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.widgetWithText(TextField, 'عدد الوحدات المنتجة'), '99');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المعاينة بطيئة البناء أسفل الطية (السرد الكسول — درس س35/س36):
    // الصعود المهدأ يبني أسطر الأخطاء وزر الترحيل معاً.
    for (var i = 0; i < 10; i++) {
      if (find.textContaining('منع السالب')
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.drag(find.byType(ListView).last,
          const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump(const Duration(milliseconds: 100));

    // رسالة المعاينة الصادقة بأول خطأ من سجل الوصاف الواحد (نمط س-36).
    expect(find.textContaining('منع السالب'), findsWidgets);

    await _scrollTo(tester, 'ترحيل التجميع');
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'ترحيل التجميع'));
    expect(button.onPressed, isNull,
        reason: 'الزر معطل بوجود خطأ المعاينة — ما يُرى هو ما سينفذ');
    await tester.tap(find.widgetWithText(FilledButton, 'ترحيل التجميع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final docs = await db.customSelect(
      'SELECT COUNT(*) AS c FROM assemblies',
    ).getSingle();
    expect(docs.data['c'], 0, reason: 'لا رأس بمعاينة رافضة');
  });

  testWidgets('س115: الناتج بالتعبئة من الشاشة — منسدل وحدة الناتج '
      'والمكافئ بالأساسية والمعاينة بالمخزونية واللقطاء محفوظة',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // بذرة نفس الأرضية + سلّة معبأة بمجموعة تعبئة (كرتونة ×12).
    final yearRows = await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    final date = '$year-06-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final gid = await db.insertUnitGroup(
        name: 'تعبئة السلال', levels: [(name: 'كرتونة', factor: 12)]);
    final cartonId = (await db.levelsOfGroup(gid)).single.id;
    Future<int> item(String sku, String name, String kind, int purchase,
            int sale,
            {int? unitGroupId}) =>
        db.insertItem(
            sku: sku,
            name: name,
            kind: kind,
            baseUnitId: unitId,
            purchasePriceMinor: purchase,
            salePriceMinor: sale,
            priceCurrencyId: 1,
            unitGroupId: unitGroupId);
    final woodId = await item('M-WOOD', 'خشب', 'good', 10000, 15000);
    final ropeId = await item('M-ROPE', 'حبل', 'good', 2000, 3000);
    final packedId = await item('B-PACKED', 'سلّة معبأة', 'bundle', 12000,
        15000, unitGroupId: gid);
    await db.saveBundleRecipe(packedId, [
      BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
      BundleComponentDraft(componentItemId: ropeId, qtyBase: 1),
    ]);
    final supplierId = await db.insertParty(
        number: '0001', name: 'مورد الشرق', kind: 'supplier',
        defaultCurrencyId: 1);
    final mainId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    await db.postInvoice(await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: mainId,
      lines: [
        InvoiceLineDraft(
            itemId: woodId, unitId: unitId, qtyBase: 100, unitPriceMinor: 10000),
        InvoiceLineDraft(
            itemId: ropeId, unitId: unitId, qtyBase: 100, unitPriceMinor: 2000),
      ],
    )));

    await _pumpAssemblyScreen(tester, db);
    await tester.tap(find
        .widgetWithText(DropdownButtonFormField<int>, 'الصنف التجميعي '
            '(صاحب الوصفة)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('سلّة معبأة (B-PACKED)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // منسدل وحدة الناتج ظهر للمجموعة — والأساسية افتراضاً.
    expect(find.text('وحدة الناتج'), findsOneWidget);
    await tester.tap(find.text('وحدة الناتج'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('كرتونة ×12').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // إدخال 2 كرتونة: المكافئ 24 والمعاينة بالمخزونية (درس س79) —
    // والمكونات بالوصفة × المخزونية نص F-211 ثابت.
    await tester.enterText(
        find.widgetWithText(TextField, 'عدد الوحدات المنتجة'), '2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('المكافئ بالأساسية: 24'), findsOneWidget);
    expect(find.textContaining('خشب (M-WOOD) × 48'), findsOneWidget);
    // بطاقة الناتج أسفل المعاينة — السرد الكسول يبني الظاهر حصراً
    // (درس س35/س36) فتُسحب ثم تُقرأ لقطتها.
    for (var i = 0; i < 6; i++) {
      if (find.textContaining('× 2 (بالمستوى) = 24').evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.textContaining('× 2 (بالمستوى) = 24'), findsOneWidget);

    await _scrollTo(tester, 'ترحيل التجميع');
    await tester.tap(find.widgetWithText(FilledButton, 'ترحيل التجميع'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('رُحّل مستند التجميع'), findsOneWidget);
    // واللقطاء محفوظة على الرأس والسجل يقرأها «2 (بالمستوى) = 24» —
    // وسجل التجميعات آخر القائمة فتُسحب إليه (السرد الكسول).
    final head = await db.customSelect(
      'SELECT qty_base, unit_level_id, qty_doc, factor_at_entry '
      'FROM assemblies',
    ).getSingle();
    expect(head.data['qty_base'], 24);
    expect(head.data['unit_level_id'], cartonId);
    expect(head.data['qty_doc'], 2);
    expect(head.data['factor_at_entry'], 12);
    for (var i = 0; i < 8; i++) {
      if (find.textContaining('× 2 (بالمستوى) = 24').evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.textContaining('× 2 (بالمستوى) = 24'), findsWidgets);
  });
}
