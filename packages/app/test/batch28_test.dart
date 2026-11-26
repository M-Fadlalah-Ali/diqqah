import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/items_screen.dart';
import 'package:diqqah_app/invoices_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 28 (خامسة م2) — التجميعي الجاهز والفكك
/// (F-034/F-212): نوع التجميعي ببطاقة الصنف ومحرر وصفته بخياري خدمة
/// الوصفة (F-212)، وعلامة التجميعي ومتاحه «الجاهز» بقائمة اختيار
/// الفواتير (F-034).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26)، ورسالة واحدة أول خطأ (نمط س-36).
Finder _fieldByLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText == label));

Finder _dropdownByLabel(String label) => find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField && (w.decoration.labelText == label));

void _bigView(WidgetTester tester) {
  // عريضة بما يكفي لأزرار AppBar الحافة (درس الاختبار: الإطار الافتراضي
  // 800×600 يقتص حافة الأفعال).
  tester.view.physicalSize = const Size(1600, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _drainSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 600));
}

/// أرضية الوصفة: وحدة وثلاثة أصناف (خشب وحبل بضاعة وتجميع خدمة) —
/// ومرشّحو المكونات كلهم نشطون بلا تجميعي.
Future<DiqqahDatabase> _ground() async {
  final db = DiqqahDatabase.inMemorySyncClose();
  final unitId = await db.insertUnit(name: 'قطعة');
  Future<void> item(String sku, String name, String kind) => db.insertItem(
        sku: sku,
        name: name,
        kind: kind,
        baseUnitId: unitId,
        purchasePriceMinor: 10000,
        salePriceMinor: 15000,
        priceCurrencyId: 1,
      );
  await item('M-WOOD', 'خشب', 'good');
  await item('M-ROPE', 'حبل', 'good');
  await item('S-ASM', 'تجميع', 'service');
  return db;
}

/// فتح بطاقة صنف جديدة واختيار الوحدة والنوع تجميعي.
Future<void> _openBundleCard(WidgetTester tester, DiqqahDatabase db) async {
  await tester.pumpWidget(MaterialApp(home: ItemEditScreen(db: db)));
  await tester.pump();
  await tester.enterText(_fieldByLabel('كود الصنف (الأساس)'), 'B-100');
  await tester.enterText(_fieldByLabel('الاسم *'), 'سلّة هدايا');
  await tester.tap(_dropdownByLabel('الوحدة الأساسية *'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('قطعة').last);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('تجميعي').first);
  await tester.pump();
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('بطاقة الصنف: النوع الثالث «تجميعي» ظاهر واختياره يفتح قسم '
      'الوصفة (F-034)', (tester) async {
    _bigView(tester);
    final db = await _ground();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: ItemEditScreen(db: db)));
    await tester.pump();
    // النوع الثالث ظاهر لا مدفون (درس D-098).
    expect(find.text('تجميعي'), findsOneWidget);
    expect(find.text('وصفة المكونات'), findsNothing,
        reason: 'القسم شأن التجميعي حصراً — البضاعة بلا وصفة');

    await _openBundleCard(tester, db);
    expect(find.text('وصفة المكونات'), findsOneWidget);
    expect(find.text('إضافة مكوّن'), findsOneWidget);
    // والبضاعة لا تري القسم عند عودتها.
    await tester.tap(find.text('بضاعة').first);
    await tester.pump();
    expect(find.text('وصفة المكونات'), findsNothing);
    await tester.tap(find.text('تجميعي').first);
    await tester.pump();
    expect(find.text('وصفة المكونات'), findsOneWidget);
  });

  testWidgets('الوصفة: مكوّن بضاعة بكميته وخدمة بتكلفتها يُحفظان والقراءة '
      'العكسية سليمة (F-034/F-212)', (tester) async {
    _bigView(tester);
    final db = await _ground();
    addTearDown(db.close);

    await _openBundleCard(tester, db);

    // المكوّن الأول: خشب بضاعة ×2 بلا خانة تكلفة.
    await tester.tap(find.text('إضافة مكوّن'));
    await tester.pump();
    await tester.tap(_dropdownByLabel('المكوّن').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('خشب').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(_fieldByLabel('الكمية لكل وحدة'), '2');
    await tester.pump();
    expect(_fieldByLabel('تكلفة الخدمة (اختياري)'), findsNothing,
        reason: 'خانة التكلفة لخدمة الوصفة حصراً (F-212)');

    // المكوّن الثاني: خدمة التجميع بكمية وتكلفة — والخانة تظهر له.
    await tester.tap(find.text('إضافة مكوّن'));
    await tester.pump();
    await tester.tap(_dropdownByLabel('المكوّن').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('تجميع').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_fieldByLabel('تكلفة الخدمة (اختياري)'), findsOneWidget);
    await tester.enterText(_fieldByLabel('الكمية لكل وحدة').last, '1');
    await tester.enterText(_fieldByLabel('تكلفة الخدمة (اختياري)'), '500');
    await tester.pump();

    await tester.tap(find.text('حفظ'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // القراءة العكسية من القاعدة — الوصفة بخطوطها الثلاثة (خشب وحبل
    // والخدمة: خشب وحبل بلا تكلفة والخدمة بـ500).
    final items = await db.select(db.items).get();
    final bundle = items.singleWhere((i) => i.sku == 'B-100');
    expect(bundle.kind, 'bundle');
    final recipe = await db.bundleRecipeByItem(bundle.id);
    expect(recipe, hasLength(2));
    final wood = recipe.firstWhere((r) => r.sku == 'M-WOOD');
    expect(wood.qtyBase, 2);
    expect(wood.costMinor, isNull);
    final asm = recipe.firstWhere((r) => r.sku == 'S-ASM');
    expect(asm.isService, isTrue);
    expect(asm.costMinor, 500);
  });

  testWidgets('صف الوصفة بلا مكوّن يرفض الحفظ برسالة أول خطأ — ولا صنف '
      'يُكتب بوصفة مكسورة (نمط س-36)', (tester) async {
    _bigView(tester);
    final db = await _ground();
    addTearDown(db.close);

    await _openBundleCard(tester, db);
    await tester.tap(find.text('إضافة مكوّن'));
    await tester.pump();
    await tester.enterText(_fieldByLabel('الكمية لكل وحدة'), '2');
    await tester.pump();

    await tester.tap(find.text('حفظ'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('اختَر المكوّن في كل صف'), findsOneWidget);
    // ولا صنف كُتب — الرفض قبل الكتابة حصراً.
    final items = await db.select(db.items).get();
    expect(items.where((i) => i.sku == 'B-100'), isEmpty);
    await _drainSnackbar(tester);
  });

  testWidgets('قائمة اختيار الفواتير: التجميعي بعلامته ومتاحه «الجاهز» '
      '(F-034)', (tester) async {
    _bigView(tester);
    final db = await _ground();
    addTearDown(db.close);

    // سلّة تجميعية بوصفة وشراء جاهز 4 — والمتاح يظهر من قاعدة الحاضر.
    final unitId = (await db.select(db.units).get()).first.id;
    final woodId = (await db.select(db.items).get())
        .singleWhere((i) => i.sku == 'M-WOOD')
        .id;
    final basketId = await db.insertItem(
        sku: 'B-200',
        name: 'سلّة شوكولا',
        kind: 'bundle',
        baseUnitId: unitId,
        purchasePriceMinor: 12000,
        salePriceMinor: 18000,
        priceCurrencyId: 1);
    await db.saveBundleRecipe(basketId, [
      BundleComponentDraft(componentItemId: woodId, qtyBase: 2),
    ]);
    final yearRows = await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    final supplierId = await db.insertParty(
        number: '0001', name: 'مورد الشرق', kind: 'supplier', defaultCurrencyId: 1);
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '$year-03-15',
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: basketId, unitId: unitId, qtyBase: 4, unitPriceMinor: 12000),
      ],
    ));
    await db.postInvoice(purchase);

    await tester.pumpWidget(MaterialApp(
      home: InvoiceEditScreen(db: db, initialKind: InvoiceKind.sale),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(_dropdownByLabel('الصنف').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('(تجميعي)'), findsWidgets,
        reason: 'التجميعي بعلامته في القائمة لا صمتاً');
    expect(find.textContaining('المتاح (الجاهز)'), findsWidgets,
        reason: 'المتاح عنده «الجاهز» بلفظها — رصيده الجاهز (F-034)');
    expect(find.textContaining('المتاح (الجاهز): 4'), findsOneWidget);
  });
}
