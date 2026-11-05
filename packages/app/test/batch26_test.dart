import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/stock_docs_screen.dart';
import 'package:diqqah_app/warehouses_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 26 (ثالثة م2) — شاشتا إذني المخزون (F-209/F-210،
/// س85/D-189).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26)، ورسالة المحرك برسالتها لا صياغة واجهة موازية،
/// والإخطار يبقى والرفض لا يعيد التحميل (درس س78 الموثق).
Future<int> _seedStockGround(DiqqahDatabase db) async {
  // بذرة مخزون بالرئيسي: 10 زيت × 25000 = 250000 (نمط batch24/25).
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

Future<void> _pumpDocScreen(
  WidgetTester tester,
  DiqqahDatabase db,
  StockDocDirection direction,
) async {
  await tester.pumpWidget(
      MaterialApp(home: StockDocScreen(db: db, direction: direction)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً — والعنصر
  /// البعيد غير مبنيّ أصلاً فلا يجده المحل. ودرس الدفعة 26 المزدوج:
  /// (1) زخم السحب الباليستي يحرك الهدف بين الإيجاد والضغط فيُفوَّت —
  /// فكل سحبة تُهدأ بمضخة طويلة قبل الفحص التالي، (2) وبعد الظهور قفزة
  /// ensureVisible فورية تستقر على الهدف بلا تحريك. ولا scrollUntilVisible:
  /// سباقه الداخلي يرمي «No element» حين يهرب العنصر المبني.
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

  testWidgets('شاشة المستودعات: زرا الإذنين ظاهران لا مدفونان (درس D-098) '
      'ويفتحان شاشتيهما بعنوان الاتجاه', (tester) async {
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

    await tester.tap(find.text('إذن إدخال مخزون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('إذن إدخال المخزون'), findsOneWidget);
    // سجل آخر الإذنين أسفل قائمة طويلة — السرد الكسول يبني الظاهر حصراً
    // (درس س35/س36) فالوصول إليه بقفزة فورية بلا زخم.
    await _scrollTo(tester, 'آخر إذون الإدخال');
    expect(find.text('آخر إذون الإدخال'), findsOneWidget);
  });

  testWidgets('إذن إدخال كامل من الشاشة: سبب إلزامي وسطر وترحيل ونجاح '
      'بالرقم والرصيد والقيد على 43 صارا الواقع', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedStockGround(db);

    await _pumpDocScreen(tester, db, StockDocDirection.receipt);

    await tester.enterText(
        find.widgetWithText(TextField, 'السبب (إلزامي)'), 'هدية مورد');
    // اختيار الصنف من القائمة — أول صنف بالقائمة هو زيت محلي
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('زيت محلي (Z-100)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية'), '5');
    await tester.tap(find.text('أضف السطر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('× 5'), findsOneWidget);

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ وترحيل'));
    await tester.pump();
    // المضخة تحت مدة الإخطار (5 ثوانٍ) كيبقى ظاهراً للعين الزائفة
    // (نمط batch24/25) — ولا pumpAndSettle أبداً (درس س22..س26).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    // الدفعة رُحّلت — الإخطار برسالة الشاشة ذاتها (لا «الـ» في العنوان)
    expect(find.textContaining('رُحّل إذن إدخال'), findsOneWidget);

    // الواقع: الرصيد 15 والقيمة 375000 والقيد 113/43.
    final mainId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final bal = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE warehouse_id = $mainId',
    ).getSingle();
    expect(bal.data['qty_base'], 15);
    expect(bal.data['total_value_minor'], 375000);
    final journal = await db.customSelect(
      "SELECT COUNT(*) AS c FROM moves WHERE ref_doc_type = "
      "'stock_receipt' AND state = 'posted'",
    ).getSingle();
    expect(journal.data['c'], 1);
    // والسجل أظهر الإذن.
    expect(find.textContaining('هدية مورد'), findsWidgets);
  });

  testWidgets('إذن بلا سبب يرفض برسالة المدقق الصادقة ولا يكتب شيئاً '
      '(نمط س-36 «رسالة واحدة أول خطأ»)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedStockGround(db);

    await _pumpDocScreen(tester, db, StockDocDirection.receipt);

    // بلا سبب — السطر وحده لا يكفي
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('زيت محلي (Z-100)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '2');
    await tester.tap(find.text('أضف السطر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    // بطاقة الرفض أعلى القائمة — والقائمة مطلية لأسفلها بعد الضغط
    // فيصير العنصر العلوي غير مبنيّ (السرد الكسول — درس الدفعة 26):
    // الصعود أولاً يبنيها ثم يظهرها.
    await tester.drag(find.byType(ListView).last, const Offset(0, 900));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('سبب إذن الإدخال إلزامي'), findsOneWidget);
    final docs = await db.customSelect(
      'SELECT COUNT(*) AS c FROM stock_receipts',
    ).getSingle();
    expect(docs.data['c'], 0);
  });

  testWidgets('إذن إخراج بأكثر من المتاح يرفض برسالة منع السالب الصادقة '
      '(F-042) ولا يكتب شيئاً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await _seedStockGround(db);

    await _pumpDocScreen(tester, db, StockDocDirection.issue);

    expect(find.text('إذن إخراج المخزون'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'السبب (إلزامي)'), 'تالف بالتخزين');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('زيت محلي (Z-100)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '99');
    await tester.tap(find.text('أضف السطر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    // بطاقة الرفض أعلى القائمة والقائمة مطلية لأسفلها — الصعود يبنيها
    // (السرد الكسول — درس الدفعة 26).
    await tester.drag(find.byType(ListView).last, const Offset(0, 900));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('منع السالب'), findsOneWidget);
    final docs = await db.customSelect(
      'SELECT COUNT(*) AS c FROM stock_issues',
    ).getSingle();
    expect(docs.data['c'], 0);
  });
}
