import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/currency_display.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/parties_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة (17) — لفظ المالك الثماني بس50 «للنقاش قبل التنفيذ»
/// وكلمته بس51: الرقم القابل للتعديل فوق المعرف الخفي (س50/1، س-155/
/// D-153) والسداد نقدية/ذمة مع المدفوع والباقي (س50/4، س-156/D-154)
/// ورمز العملة مكان «بالأساسية» (س50/6، س-158/D-156) — والنقدي المرحّل
/// مسدّد بمجرد ترحيله (س-03/س-06) فالمغطى محصلته إجماليه لا صفر.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وبلا pumpAndSettle — درس
/// س22..س26 — والحكم بنصوص فريدة لا textContaining عائماً حيث أمكن.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  Future<String> cycleDate(DiqqahDatabase db) async {
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    return '${yearRows.single.data['name'] as String}-03-15';
  }

  Future<int> firstBoxId(DiqqahDatabase db) async {
    return (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
  }

  Future<int> firstWarehouseId(DiqqahDatabase db) async {
    return (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
  }

  // ═══ س50/6 (س-158/D-156): رمز العملة مكان اللفظ ═══

  test('رمز العملة من كودها — ل.س والدولار والغريب كوده والفارغ فارغ', () {
    expect(currencySymbol('SYP'), 'ل.س');
    expect(currencySymbol('USD'), r'$');
    expect(currencySymbol('syp'), 'ل.س', reason: 'حالة الكود لا تمنع');
    expect(currencySymbol(' usd '), r'$');
    expect(currencySymbol('EUR'), 'EUR',
        reason: 'الغريب يبقى بكوده حرفاً — لا اختلاق رمز');
    expect(currencySymbol(null), '');
    expect(currencySymbol(''), '');
    expect(kBaseCurrencySymbol, 'ل.س',
        reason: 'م1 أساسية واحدة SYP مزروعة (D-070/F-120)');
  });

  // ═══ س50/4 (س-156/D-154): المدفوع من محرك المطابقة ═══

  test('المغطى: الآجل بالمطابقات والنقدي المرحّل بمجمله والمسودة والغائب صفر',
      () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;
    final purchaseId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'purchase' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;

    // البيع الآجل 90,000 قُبض عليه 50,000 بالمطابقة — والمغلف بالمطابقات
    expect(await db.invoiceCoveredDocMinor(saleId), 50000);
    // والشراء الآجل 100,000 بلا سند عليه
    expect(await db.invoiceCoveredDocMinor(purchaseId), 0);

    // بيع نقدي 2×15,000 = 30,000 — المرحّل مسدّد بمجرد ترحيله (س-03)
    // — والصنف يُخزن أولاً بشراء نقدي من الصندوق المبيت بالبذرة
    // (منع السالب F-042 على المخزون والصندوق معاً)
    final date = await cycleDate(db);
    final boxId = await firstBoxId(db);
    final warehouseId = await firstWarehouseId(db);
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
        sku: 'Z-200',
        name: 'زيت نقدي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 15000,
        priceCurrencyId: 1);
    final stockedPurchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 5, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(stockedPurchaseId);
    final cashSaleId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 2, unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(cashSaleId);
    expect(await db.invoiceCoveredDocMinor(cashSaleId), 30000,
        reason: 'النقدي المرحّل مسدّد فوراً — لا مطابقة سند عليه');

    // والمسودة النقدية لم تتحرك بعد — المغطى صفر لا إجماليها
    final draftId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 1, unitPriceMinor: 15000),
      ],
    ));
    expect(await db.invoiceCoveredDocMinor(draftId), 0,
        reason: 'المسودة لم تُرحَّل فلم يُسدد شيء');

    // والغائب صفر لا استثناء — فلا تُكسر قسيمة عرضية
    expect(await db.invoiceCoveredDocMinor(99999), 0);
  });

  // ═══ تفاصيل الفاتورة بلسان المالك (س50/4 و5 و6) ═══

  testWidgets('تفاصيل الفاتورة الآجلة: السداد ذمة والمدفوع والباقي '
      'ولفظ «المبلغ» لسطرها ولا «بالأساسية»', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;

    await tester.pumpWidget(MaterialApp(
        home: InvoiceDetailScreen(db: db, invoiceId: saleId)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // التصنيف بلسان المالك: «نحن صنفنا الفواتير نقدية وذمة»
    expect(find.textContaining('السداد ذمة'), findsOneWidget);
    // والإجمالي برمز العملة لا لفظ «بالأساسية»
    expect(find.textContaining('الإجمالي 90,000 ل.س'), findsOneWidget);
    expect(find.textContaining('بالأساسية'), findsNothing);
    // والمدفوع والباقي بقراءة المحرك (قُبض 50,000 من 90,000)
    expect(find.textContaining('المدفوع 50,000'), findsOneWidget);
    expect(find.textContaining('الباقي 40,000'), findsOneWidget);
    // وسطر السطر بلسان س50/5 — «المبلغ» لا «صافي السطر»
    expect(find.text('المبلغ 90,000'), findsOneWidget);
    expect(find.textContaining('صافي السطر'), findsNothing);
  });

  testWidgets('تفاصيل الفاتورة النقدية: السداد نقدية والمدفوع إجماليها '
      'والباقي صفر', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final date = await cycleDate(db);
    final boxId = await firstBoxId(db);
    final warehouseId = await firstWarehouseId(db);
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
        sku: 'Z-300',
        name: 'زيت كاش',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 15000,
        priceCurrencyId: 1);
    // ضخ رأس المال كي يبيت الصندوق (منع السالب) ثم شراء نقدي يخزن
    // الصنف قبل بيعه — عرف الدورة المعروفة بنمط seedKnownCycle
    final capitalId = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '311'",
    ).getSingle()).data['id'] as int;
    final capital = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      directAccountId: capitalId,
      cashBoxId: boxId,
      amountDocMinor: 500000,
    ));
    await db.postVoucher(capital);
    final stockedPurchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 5, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(stockedPurchaseId);
    final cashSaleId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      cashBoxId: boxId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 2, unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(cashSaleId);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceDetailScreen(db: db, invoiceId: cashSaleId)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('السداد نقدية'), findsOneWidget);
    expect(find.textContaining('المدفوع 30,000'), findsOneWidget,
        reason: 'النقدي المرحّل مسدّد بمجرد ترحيله');
    expect(find.textContaining('الباقي 0'), findsOneWidget);
  });

  // ═══ س50/1 (س-155/D-153): التفرد في التعديل ═══

  testWidgets('تعديل رقم طرف إلى رقم آخر قائم مرفوض برسالته — وصفّه لا يتبدل',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.insertParty(
        number: '0001',
        name: 'عميل الأمل',
        kind: 'customer',
        defaultCurrencyId: 1);
    final secondId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    final second = await (db.select(db.parties)
          ..where((t) => t.id.equals(secondId)))
        .getSingle();

    await tester.pumpWidget(MaterialApp(
        home: PartyEditScreen(db: db, existing: second)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // خانة الرقم مفتوحة في التعديل — والدخول برقم الغير مرفوض
    await tester.enterText(find.byType(TextFormField).first, '0001');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('مستخدم للطرف'), findsOneWidget,
        reason: 'التفرد محروس في التعديل كما في الإضافة');
    final unchanged = await (db.select(db.parties)
          ..where((t) => t.id.equals(secondId)))
        .getSingle();
    expect(unchanged.number, '0002',
        reason: 'الرفض يبقي الصف كما هو — لا كتابة جزئية');
  });

  testWidgets('تعديل رقم طرف برقم جديد يُحفظ والمعاملات بمعرفه الخفي '
      '— وأزرار التعديل مفتوحة بلفظ المالك', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final id = await db.insertParty(
        number: '0053',
        name: 'محمد الخالدي',
        kind: 'customer',
        defaultCurrencyId: 1);
    final party = await (db.select(db.parties)
          ..where((t) => t.id.equals(id)))
        .getSingle();

    await tester
        .pumpWidget(MaterialApp(home: PartyEditScreen(db: db, existing: party)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextFormField).first, '0077');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final edited = await (db.select(db.parties)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(edited.number, '0077',
        reason: 'الرقم الظاهر تعدل — والمعرف نفسه لم يتبدل');
    expect(edited.id, id);
  });
}
