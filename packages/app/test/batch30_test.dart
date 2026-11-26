import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 30 (سابعة م2) — لقطة الوحدة والعامل بأسطر الفواتير
/// (س-10/D-031، F-032).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26)، وقوائم الاختيار ليست TextField فبُنيتها بـInputDecorator
/// حول DropdownButton (نمط مُجدئ منفصل — درس س86)، والعريضة الكبيرة
/// لأزرار النموذج (درس س86: الإطار الافتراضي يقتص حافة الأفعال).
Finder _fieldByLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText == label));

Finder _dropdownByLabel(String label) => find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField && (w.decoration.labelText == label));

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// بذرة الدفعة: مجموعة تعبئة (علبة ×12 وكرتونة ×144) وصنف بمجموعته
/// وأسعار مستوياته المخزنة (لقطة الدفعة 27) وصنف ثان بلا مجموعة —
/// وسنة البذر تُقرأ لعرض تاريخ داخل فترتها (درس س-111/D-108: التاريخ
/// الافتراضي بتاريخ اليوم وهو خارج دورة البذور فالترحيل يُرفض).
Future<(DiqqahDatabase, int)> _seed() async {
  final db = DiqqahDatabase.inMemorySyncClose();
  final unitId = await db.insertUnit(name: 'قطعة');
  final gid = await db.insertUnitGroup(
    name: 'تعبئة الزيت',
    levels: [(name: 'علبة', factor: 12), (name: 'كرتونة', factor: 144)],
  );
  final itemId = await db.insertItem(
      sku: 'Z-100',
      name: 'زيت محلي',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 25000,
      salePriceMinor: 40000,
      priceCurrencyId: 1,
      unitGroupId: gid);
  await db.insertItem(
      sku: 'P-1',
      name: 'صنف بلا مجموعة',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 1000,
      salePriceMinor: 2000,
      priceCurrencyId: 1);
  await db.insertParty(
      number: '0001',
      name: 'مورد الشرق',
      kind: 'supplier',
      defaultCurrencyId: 1);
  final levels = await db.levelsOfGroup(gid);
  await db.saveItemLevelPrices(itemId, [
    (levelId: levels[0].id,
        salePriceMinor: 480000,
        purchasePriceMinor: 300000),
    (levelId: levels[1].id,
        salePriceMinor: 5760000,
        purchasePriceMinor: 3600000),
  ]);
  return (db, levels[0].id);
}

Future<int> _seededYear(DiqqahDatabase db) async {
  final yearRows =
      await db.customSelect('SELECT name FROM fiscal_years').get();
  return int.parse(yearRows.single.data['name'] as String);
}

Future<void> _pumpEdit(WidgetTester tester, DiqqahDatabase db) async {
  await tester.pumpWidget(MaterialApp(home: InvoiceEditScreen(db: db)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _chooseItem(WidgetTester tester, String itemText) async {
  await tester.tap(_dropdownByLabel('الصنف'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.textContaining(itemText).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _chooseUnit(WidgetTester tester, String unitText) async {
  await tester.tap(_dropdownByLabel('الوحدة'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(unitText).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-10: الصنف بمجموعة تعبئة تظهر ببطاقة سطره قائمة «الوحدة» '
      'بأساسها ومستوياتها — وصنف بلا مجموعة لا قائمة له (القائم باق)',
      (tester) async {
    _bigView(tester);
    final (db, _) = await _seed();
    addTearDown(db.close);

    await _pumpEdit(tester, db);
    await _chooseItem(tester, 'Z-100 زيت محلي');

    expect(_dropdownByLabel('الوحدة'), findsOneWidget);
    await _chooseUnit(tester, 'علبة ×12');
    expect(find.text('الوحدة: علبة ×12'), findsOneWidget);

    // والصنف بلا مجموعة: قائمة الوحدة غائبة كلياً (السلوك القائم باق).
    await _chooseItem(tester, 'P-1 صنف بلا مجموعة');
    expect(_dropdownByLabel('الوحدة'), findsNothing);
  });

  testWidgets('س-10: اختيار علبة يعبّئ سعرها المخزن بوسمه ويظهر المكافئ '
      'اللحظي، والترحيل من الشاشة يخزن اللقطة الثلاثية والرصيد على '
      'الأساسية', (tester) async {
    _bigView(tester);
    final (db, boxLevelId) = await _seed();
    addTearDown(db.close);
    final year = await _seededYear(db);

    await _pumpEdit(tester, db);
    await _chooseItem(tester, 'Z-100 زيت محلي');

    await _chooseUnit(tester, 'علبة ×12');

    // السعر المخزن للمستوى بوسم مصدره (نمط F-146/D-183 بلسان س-10)
    // — 25,000 أساساً × 12 = 300,000 بوحدة صغرى.
    expect(find.text('300,000'), findsOneWidget);
    expect(find.text('سعر علبة المخزن'), findsOneWidget);

    await tester.enterText(_fieldByLabel('الكمية'), '2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // الفرق الحي بonChanged (درس س79): الإجمالي بالمثال الحرفي
    // 2 × 300,000 = 600,000 — لا 24 × 300,000 — والمكافئ 24 قطعة.
    expect(find.text('إجمالي السطر: 600,000'), findsOneWidget);
    expect(find.text('المكافئ بالأساسية: 24 قطعة'), findsOneWidget);

    // تاريخ داخل فترة البذر المفتوحة — درس س-111/D-108 الموثق.
    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'),
        '$year-03-15');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // آجل بطرفه (س-04): صندوق البذور افتتاحيته صفر فالنقدي يرفضه حرس
    // منع السالب الموحد — والآجل ذمة مورد لا تحتاج نقداً.
    await tester.tap(find.text('نقدي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('آجل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('الآجل يطلب طرفاً'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('مورد الشرق').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    // المضخة تحت مدة الإخطار كي لا يبقى مؤقتاً حياً (نمط الضخّات).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));

    // الواقع المخزن: اللقطة الثلاثية كاملة والرصيد والقيمة على الأساسية.
    final line = await db.customSelect(
      'SELECT qty, qty_base, unit_level_id, factor_at_entry '
      'FROM invoice_lines',
    ).getSingle();
    expect(line.data['qty'], 2);
    expect(line.data['qty_base'], 24);
    expect(line.data['unit_level_id'], boxLevelId);
    expect(line.data['factor_at_entry'], 12);
    final bal = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances',
    ).getSingle();
    expect(bal.data['qty_base'], 24);
    expect(bal.data['total_value_minor'], 600000);
  });

  testWidgets('س-10: الرجوع للأساسية بعد مستوى يعيد السعر الافتراضي '
      'ويصمت المكافئ — والوحدة المعروضة عادت بلسانها القائم',
      (tester) async {
    _bigView(tester);
    final (db, _) = await _seed();
    addTearDown(db.close);

    await _pumpEdit(tester, db);
    await _chooseItem(tester, 'Z-100 زيت محلي');

    await _chooseUnit(tester, 'علبة ×12');
    expect(find.text('300,000'), findsOneWidget);

    await tester.enterText(_fieldByLabel('الكمية'), '2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('المكافئ بالأساسية: 24 قطعة'), findsOneWidget);

    // الرجوع للأساسية: سعرها الافتراضي (سعر شراء 25,000) والمكافئ صمت.
    await _chooseUnit(tester, 'قطعة (الأساسية)');
    expect(find.text('25,000'), findsOneWidget);
    expect(find.textContaining('المكافئ بالأساسية'), findsNothing);
    expect(find.text('الوحدة: قطعة (الأساسية)'), findsOneWidget);
  });
}
