import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/warehouses_screen.dart';
import 'package:diqqah_app/transfers_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 24 (أولى م2) — شاشة المستودعات والتحويل بينها
/// (س-18/F-045، س77/D-185).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// في التدفقات الحية (درس س22..س26)، ورسالة المحرك برسالتها لا صياغة
/// واجهة موازية، والمستودع الرئيسي مزروع ببذرة القاعدة الافتراضية.
Future<void> _seedTransferGround(DiqqahDatabase db) async {
  // مستودع الفرع بجانب الرئيسي المزروع، وبذرة مخزون بالرئيسي:
  // 10 زيت × 25000 = 250000 (نمط batch23_storage).
  final branchId = await db.warehouseCreate(name: 'مستودع الفرع');
  final yearRows = await db.customSelect('SELECT name FROM fiscal_years').get();
  final year = int.parse(yearRows.single.data['name'] as String);
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
  final supplierId = await db.insertParty(
      number: '0001',
      name: 'مورد الشرق',
      kind: 'supplier',
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
          itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 25000),
    ],
  ));
  await db.postInvoice(purchase);
  assert(branchId > 0);
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً — العنصر
  /// أسفل النافذة غير مبني فلا يُلمَس قبل تمريره.
  Future<void> _scrollTo(WidgetTester tester, String label) async {
    for (var i = 0;
        i < 6 && find.text(label).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
  }

  testWidgets('شاشة المستودعات: الرئيسي المبذر ظاهر وزر التحويل ظاهر '
      'لا مدفون (درس D-098)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('المستودع الرئيسي'), findsOneWidget);
    expect(find.textContaining('نشط — يظهر في اختيارات الإدخال'),
        findsOneWidget);
    expect(find.text('تحويل بين مستودعين'), findsOneWidget);
    expect(find.text('لا تحويلات بعد'), findsOneWidget);
  });

  testWidgets('إنشاء مستودع جديد من الحوار يظهر بالقائمة — والتسمية '
      'الفارغة ترفض برسالة المدقق', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('مستودع جديد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الاسم الفارغ يرفض قبل الإغلاق (نمط الحوار حارس المدقق)
    await tester.tap(find.text('إنشاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('اسم المستودع إلزامي'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم المستودع'), 'مستودع الفرع');
    await tester.tap(find.text('إنشاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('أُنشئ المستودع «مستودع الفرع»'),
        findsOneWidget);
    expect(find.text('مستودع الفرع'), findsOneWidget);
  });

  testWidgets('تعطيل آخر مستودع نشط يرفض برسالة المحرك (نمط 03 §6-3)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // مفتاح التعطيل على المستودع الوحيد النشط
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('تعطيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('آخر مستودع نشط'), findsOneWidget);
    // والمستودع يبقى نشطاً — لا صمت ولا انضبار
    expect(find.textContaining('نشط — يظهر في اختيارات الإدخال'),
        findsOneWidget);
  });

  testWidgets('شاشة التحويل: بذرة الرئيسي والفرع وشراء 10×25000 — '
      'تحويل 3 زيت يرحّل برقم موحد ورسالة نجاح ويظهر بالسجل',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedTransferGround(db);

    await tester.pumpWidget(MaterialApp(home: TransfersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الافتراض المعقول: أول مستودع نشط مصدراً وثانيه مستلماً
    expect(find.textContaining('المستودع الرئيسي'), findsWidgets);

    // اختيار الصنف بالمنتقي — والسرد أولاً إذا غاب عن النافذة
    await _scrollTo(tester, 'الصنف');
    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('زيت محلي (Z-100)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية'), '3');
    await tester.tap(find.text('أضف السطر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('× 3'), findsOneWidget);

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('رُحّل التحويل'), findsOneWidget);
    expect(find.textContaining('رصيد الطرفين تحدث فوراً'), findsOneWidget);

    // السجل أسفل الشاشة يعرض التحويل بقيده الموحد
    final rows = await db.customSelect(
      'SELECT number FROM stock_transfers',
    ).get();
    expect(rows.length, 1);
    expect((rows.single.data['number'] as String).length, greaterThan(3));
    // والرصيد انتقل: المصدر 7×175000 والفرع 3×75000 (القيمة كما هي)
    final mainId = (await db.customSelect(
      "SELECT id FROM warehouses WHERE name = 'المستودع الرئيسي'",
    ).getSingle()).data['id'] as int;
    final branchId = (await db.customSelect(
      "SELECT id FROM warehouses WHERE name = 'مستودع الفرع'",
    ).getSingle()).data['id'] as int;
    final mainBal = (await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE warehouse_id = $mainId',
    ).getSingle());
    final branchBal = (await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE warehouse_id = $branchId',
    ).getSingle());
    expect(mainBal.data['qty_base'], 7);
    expect(mainBal.data['total_value_minor'], 175000);
    expect(branchBal.data['qty_base'], 3);
    expect(branchBal.data['total_value_minor'], 75000);
  });
}
