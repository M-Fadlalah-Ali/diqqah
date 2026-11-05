import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 33 (عاشرة م2) — القوائم المالية الأساسية (F-096
/// من أنواع الحسابات و07 §1.6): قائمة الدخل بمدى تاريخ والميزانية
/// العمومية إلى تاريخ، والتأسيس بعد الإقفال من الافتتاحية فلا ازدواج.
///
/// الدورة: شراء آجل 5,000 فبيع آجل 2×2,000 — الأصول 7,000 (ذمم 4,000
/// ومخزون 3,000) والخصوم 5,000 وحقوق النتيجة الجارية 2,000.
void main() {
  late DiqqahDatabase db;
  late int unitId;
  late int itemId;
  late int warehouseId;
  late int supplierId;
  late int customerId;
  late String yearName;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    unitId = await db.insertUnit(name: 'قطعة');
    itemId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1);
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    supplierId = await db.insertParty(
        number: '0001', name: 'مورد الشرق', kind: 'supplier',
        defaultCurrencyId: 1);
    customerId = await db.insertParty(
        number: '0002', name: 'عميل الأمل', kind: 'customer',
        defaultCurrencyId: 1);
    final yearRows = await db.customSelect(
      'SELECT name FROM fiscal_years',
    ).getSingle();
    yearName = yearRows.data['name'] as String;

    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '$yearName-03-15',
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: 5,
            unitPriceMinor: 1000),
      ],
    ));
    await db.postInvoice(purchase);
    final sale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: '$yearName-04-10',
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: 2,
            unitPriceMinor: 2000),
      ],
    ));
    await db.postInvoice(sale);
  });

  tearDown(() => db.close);

  test('قائمة الدخل بمدى سنة البذور: إيراد 4,000 وتكلفة 2,000 وصافي '
      'ربح 2,000 — والمدى الغائب رسالة لا صمت (مدى داخل السنة)', () async {
    final statement = await db.incomeStatementReport(
        fromText: '$yearName-01-01', toText: '$yearName-12-31');
    expect(statement.totalRevenueMinor, 4000);
    expect(statement.totalExpenseMinor, 2000);
    expect(statement.netResultMinor, 2000);
    expect(statement.revenueRows.single.code, '411');
    expect(statement.expenseRows.single.code, '51');

    // مدى يقتص شهر البيع: الإيراد والتكلفة بقيد البيع ذاته (04-10)
    // فيجتمعان بالمدى المقتص — الصافي 2,000 كما هو بالسنة كاملة
    // (الشراء لا أثر نتيجياً له — أثره مخزون وذمة حصراً).
    final after = await db.incomeStatementReport(
        fromText: '$yearName-04-01', toText: '$yearName-04-30');
    expect(after.totalRevenueMinor, 4000);
    expect(after.totalExpenseMinor, 2000);
    expect(after.netResultMinor, 2000);

    // مدى مقلوب مرفوض قبل لمس القاعدة (D-077).
    expect(
      () => db.incomeStatementReport(
          fromText: '$yearName-12-31', toText: '$yearName-01-01'),
      throwsA(isA<ReportValidationException>()),
    );
  });

  test('الميزانية قبل الإقفال: الأصول 7,000 والخصوم 5,000 والجارية '
      '2,000 — والمعادلة متوازنة', () async {
    final sheet = await db.balanceSheetReport(
        asOfText: '$yearName-12-31');
    expect(sheet.totalAssetsMinor, 7000);
    expect(sheet.totalLiabilitiesMinor, 5000);
    expect(sheet.currentResultMinor, 2000);
    expect(sheet.totalEquityMinor, 2000);
    expect(sheet.isBalanced, isTrue);
  });

  test('بعد الإقفال السنوي: الميزانية إلى تاريخ السنة المقفلة تعرض '
      'النتيجة في 331 والمعادلة متوازنة — وإلى ما بعد الإقفال تتأسس من '
      'الافتتاحية فلا ازدواج (الذمم 4,000 لا 8,000)', () async {
    final periods = await db.ledgerPeriods();
    for (final period in periods) {
      await db.closePeriod(period.id, draftsConfirmed: true);
    }
    final result = await db.fiscalYearClose((await db.customSelect(
      'SELECT id FROM fiscal_years',
    ).getSingle()).data['id'] as int);

    // إلى نهاية السنة المقفلة: قيود الإغلاق داخل المدى فالجارية صفر
    // والنتيجة في 331 — والمعادلة متوازنة (معيار F-077).
    final atYearEnd = await db.balanceSheetReport(
        asOfText: '$yearName-12-31');
    expect(atYearEnd.currentResultMinor, 0);
    expect(atYearEnd.totalAssetsMinor, 7000);
    expect(atYearEnd.totalEquityMinor, 2000);
    expect(atYearEnd.isBalanced, isTrue);

    // إلى منتصف السنة التالية: التأسيس من الافتتاحية لا من التراكم —
    // فالذمم 4,000 والقائمة متوازنة.
    final nextYear = int.parse(yearName) + 1;
    final nextSheet = await db.balanceSheetReport(
        asOfText: '$nextYear-06-30');
    expect(nextSheet.totalAssetsMinor, 7000);
    expect(nextSheet.totalLiabilitiesMinor, 5000);
    expect(nextSheet.totalEquityMinor, 2000);
    expect(nextSheet.currentResultMinor, 0);
    expect(nextSheet.isBalanced, isTrue);
    final receivablesRow = nextSheet.assetRows
        .singleWhere((r) => r.code == '112');
    expect(receivablesRow.magnitudeMinor, 4000);
    ignore(result);
  });

  test('تاريخ فاسد بالقائمة يرفض قبل لمس القاعدة (D-077)', () async {
    expect(
      () => db.balanceSheetReport(asOfText: '2026/01/01'),
      throwsA(isA<ReportValidationException>()),
    );
  });
}

void ignore(Object? _) {}
