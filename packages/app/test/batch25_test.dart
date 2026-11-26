import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/stock_counts_screen.dart';
import 'package:diqqah_app/warehouses_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 25 (ثاني م2) — شاشة الجرد وتسوياته (س-19/F-046، س79).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26)، ورسالة المحرك برسالتها لا صياغة واجهة موازية،
/// والإخطار يبقى والرفض لا يعيد التحميل (درس س78 الموثق)، والمستودع
/// الرئيسي مزروع ببذرة القاعدة الافتراضية.
Future<int> _seedCountGround(DiqqahDatabase db) async {
  // بذرة مخزون بالرئيسي: 10 زيت × 25000 = 250000 (نمط batch24).
  final yearRows = await db.customSelect('SELECT name FROM fiscal_years').get();
  final year = int.parse(yearRows.single.data['name'] as String);
  final date = '$year-03-15';
  final unitId = await db.insertUnit(name: 'قطعة');
  final oilId = await db.insertItem(
      sku: 'Z-100',
      name: 'زيت محلي',
      category: 'زيوت',
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
  return oilId;
}

Future<int> _mainWarehouseId(DiqqahDatabase db) async {
  return (await db.customSelect(
    'SELECT id FROM warehouses ORDER BY id LIMIT 1',
  ).getSingle()).data['id'] as int;
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً.
  Future<void> _scrollTo(WidgetTester tester, String label) async {
    for (var i = 0;
        i < 6 && find.text(label).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
  }

  Future<void> _pumpCounts(WidgetTester tester, DiqqahDatabase db) async {
    await tester.pumpWidget(MaterialApp(home: StockCountsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('شاشة المستودعات: زر «جرد المخزون» ظاهر لا مدفون (درس D-098) '
      'ويفتح شاشة الجرد', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تحويل بين مستودعين'), findsOneWidget);
    expect(find.text('جرد المخزون'), findsOneWidget);

    await tester.tap(find.text('جرد المخزون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('جلسة جرد جديدة'), findsOneWidget);
    expect(find.text('لا جلسات بعد'), findsOneWidget);
  });

  testWidgets('جلسة كاملة من الشاشة: فتح وعدّ 9 وحفظ والفرق ظاهر '
      'وترحيل بتأكيد ونجاح بالرقم والأرصدة صارت الواقع المعدود',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedCountGround(db);

    await _pumpCounts(tester, db);
    await tester.tap(find.text('جلسة جرد جديدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // النطاق «كل الأصناف» افتراضياً والمستودع الرئيسي مختاراً
    await tester.tap(find.text('فتح الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('جارٍ'), findsWidgets);
    expect(find.textContaining('زيت محلي (Z-100)'), findsOneWidget);
    expect(find.textContaining('بالنظام: 10'), findsOneWidget);

    // عدّ 9 — الفرق الآني «عجز 1» يظهر قبل الحفظ (س-19: تُراجع الفروقات)
    await tester.enterText(find.widgetWithText(TextField, 'المعدود'), '9');
    await tester.pump();
    expect(find.textContaining('عجز 1'), findsOneWidget);

    await tester.tap(find.text('حفظ العدّ'));
    await tester.pump();
    // إخطار الافتتاح (4 ثوانٍ) ما يزال معروضاً فإخطار الحفظ في طابور
    // ScaffoldMessenger — تُضخ الساعة الوهمية خروجه ثم دخول البديل
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('حُفظت عدّات'), findsOneWidget);

    await _scrollTo(tester, 'ترحيل الجلسة');
    await tester.tap(find.text('ترحيل الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // ديالوج التأكيد يعرض ملخص الفروقات قبل التنفيذ (المعاينة هي التنفيذ)
    expect(find.textContaining('ستُسوّى الفروقات'), findsOneWidget);
    expect(find.textContaining('النظام 10 / المعدود 9'), findsOneWidget);
    await tester.tap(find.text('ترحيل').last);
    await tester.pump();
    // إخطار الحفظ (3 ثوانٍ) يسبق إخطار الترحيل بالطابور نفسه
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('رُحّلت جلسة الجرد'), findsOneWidget);
    // والسجل يعرضها مرحّلة
    expect(find.textContaining('مرحّلة'), findsWidgets);

    // الأرصدة صارت الواقع المعدود: 9 × 25000 = 225000
    final mainId = await _mainWarehouseId(db);
    final bal = (await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE warehouse_id = $mainId',
    ).getSingle());
    expect(bal.data['qty_base'], 9);
    expect(bal.data['total_value_minor'], 225000);
    // والقيد المجمع بدفتر المخزون موجود بمرجع الجلسة
    final ledger = await db.customSelect(
      "SELECT COUNT(*) AS c FROM moves WHERE ref_doc_type = 'stock_count'",
    ).getSingle();
    expect(ledger.data['c'], 1);
  });

  testWidgets('ترحيل جلسة بعدّ ناقص يرفض برسالة المدقق ويبقى الإخطار '
      'والجلسة جارٍ (درس س78: الرفض لا يبدل القائمة)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedCountGround(db);

    await _pumpCounts(tester, db);
    await tester.tap(find.text('جلسة جرد جديدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('فتح الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    // بلا أي عدّ — الترحيل يرفض بلا تسوية جزئية
    await _scrollTo(tester, 'ترحيل الجلسة');
    await tester.tap(find.text('ترحيل الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('لم يُعدّ 1 سطراً'), findsOneWidget);
    // المستخدم يصرّ على الترحيل فيرفضه المدقق برسالته الصادقة
    await tester.tap(find.text('ترحيل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('لا تسوية جزئية'), findsOneWidget);
    // والجلسة ما تزال جارية — لا انضبار ولا مسح للقائمة
    expect(find.textContaining('جارٍ'), findsWidgets);
    final head = await db.customSelect(
      'SELECT state FROM stock_counts',
    ).getSingle();
    expect(head.data['state'], 'open');
  });

  testWidgets('س112: إلغاء الجلسة المهجورة بنافذة قرار صريحة — بلا أثر '
      'والمستودع يستقبل جلسة جديدة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedCountGround(db);

    await _pumpCounts(tester, db);
    await tester.tap(find.text('جلسة جرد جديدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('فتح الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    await _scrollTo(tester, 'إلغاء الجلسة');
    await tester.tap(find.text('إلغاء الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // نافذة القرار الصريحة تعرض الحقيقة: بلا أثر ولم يُرحَّل منها شيء.
    expect(find.text('إلغاء جلسة الجرد'), findsOneWidget);
    expect(find.textContaining('بلا أثر'), findsOneWidget);
    await tester.tap(find.text('إلغاء الجلسة').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('أُلغيت جلسة الجرد'), findsOneWidget);
    // وبلا أثر: البذرة كما هي والسجل بلا جلسات مفتوحة.
    final mainId = await _mainWarehouseId(db);
    final bal = (await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE warehouse_id = $mainId',
    ).getSingle());
    expect(bal.data['qty_base'], 10);
    expect(bal.data['total_value_minor'], 250000);
    final open = await db.customSelect(
      "SELECT COUNT(*) AS c FROM stock_counts WHERE state = 'open' "
      'AND is_deleted = 0',
    ).getSingle();
    expect(open.data['c'], 0);
  });

  testWidgets('س115: العدّ بالتعبئة من الشاشة — منسدل وحدة العدّ والمكافئ '
      'بالأساسية واللقطاء محفوظة والتسوية بالمخزونية',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // بذرة: زيت عادي 10 + زيت معبأ بمجموعة تعبئة رصيده 24 (2 علب).
    final yearRows = await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    final date = '$year-03-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final gid = await db.insertUnitGroup(
        name: 'تعبئة الزيت', levels: [(name: 'علبة', factor: 12)]);
    final boxId = (await db.levelsOfGroup(gid)).single.id;
    final supplierId = await db.insertParty(
        number: '0001', name: 'مورد الشرق', kind: 'supplier',
        defaultCurrencyId: 1);
    final mainId = await _mainWarehouseId(db);
    final oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final packedId = await db.insertItem(
        sku: 'Z-200',
        name: 'زيت معبأ',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1,
        unitGroupId: gid);
    await db.postInvoice(await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: mainId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 25000),
        InvoiceLineDraft(
            itemId: packedId,
            unitId: unitId,
            qty: 2,
            unitLevelId: boxId,
            qtyBase: 24,
            unitPriceMinor: 300000),
      ],
    )));

    await _pumpCounts(tester, db);
    await tester.tap(find.text('جلسة جرد جديدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('فتح الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    // سطر المعبأ وحده بمنسدل وحدة العدّ — والأساسية افتراضاً.
    expect(find.text('وحدة العدّ'), findsOneWidget);
    expect(find.text('الأساسية'), findsOneWidget);
    await tester.tap(find.text('وحدة العدّ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('علبة ×12').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // عدّ 3 علب: المكافئ 36 والفرق الآني زيادة 12 بالمخزونية (درس س79).
    await tester.enterText(
        find.widgetWithText(TextField, 'المعدود').at(1), '3');
    await tester.pump();
    expect(find.text('المكافئ بالأساسية: 36'), findsOneWidget);
    expect(find.textContaining('زيادة 12'), findsOneWidget);
    // وزيت العادي عدّه بالمخزونية كما اعتاد.
    await tester.enterText(
        find.widgetWithText(TextField, 'المعدود').at(0), '10');
    await tester.pump();

    await tester.tap(find.text('حفظ العدّ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('حُفظت عدّات'), findsOneWidget);
    // اللقطة محفوظة بعد إعادة التحميل: المدخل 3 بالعلبة والمكافئ 36.
    expect(find.text('المكافئ بالأساسية: 36'), findsOneWidget);

    await _scrollTo(tester, 'ترحيل الجلسة');
    await tester.tap(find.text('ترحيل الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    // ملخص الترحيل بالمخزونية: النظام 24 / المعدود 36 — لا 3.
    expect(find.textContaining('ستُسوّى الفروقات'), findsOneWidget);
    expect(find.textContaining('النظام 24 / المعدود 36'), findsOneWidget);
    await tester.tap(find.text('ترحيل').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('رُحّلت جلسة الجرد'), findsOneWidget);

    // والأرصدة بالمخزونية: 36 قطعة بقيمة 900000 (زيادة 12 × 25000).
    final bal = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE item_id = $packedId AND warehouse_id = $mainId',
    ).getSingle();
    expect(bal.data['qty_base'], 36);
    expect(bal.data['total_value_minor'], 900000);
  });
}
