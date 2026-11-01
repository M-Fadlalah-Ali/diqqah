import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart' show Variable;

/// اختبارات دفعة (12) متابعة التسليم (س-137..س-142/D-131..D-134) —
/// الترحيلة v13 (عمودا العلم والمورد) والحرس المحدَّث والقارئة
/// الجديدة بأرقام الدورة المعروفة: ضخ 500,000 فشراء 10×10,000 آجل
/// فبيع بسطرين (6×15,000 و4×20,000 = 170,000) آجل.
///
/// حدود الدفعة الصارمة موثقة اختباراً: علم العمل يُحدَّث على المرحّلة
/// بلا فك إقفال (الحرس المحدَّث يسمح به حصراً) وأي مساس بمال السطر
/// يرفض كما كان، والميزان متوازن قبل العلم وبعده (F-068).
Future<int> accountIdByCode(DiqqahDatabase db, String code) async {
  final rows = await db.customSelect(
    'SELECT id FROM accounts WHERE code = ?',
    variables: [Variable.withString(code)],
  ).get();
  expect(rows, hasLength(1));
  return rows.first.data['id'] as int;
}

void main() {
  late DiqqahDatabase db;
  late int year;
  late String date;
  late int unitId;
  late int oilId;
  late int sugarId;
  late int teaId;
  late int customerId;
  late int supplierId;
  late int boxId;
  late int warehouseId;
  late int saleId;
  late List<InvoiceLineDocument> saleLines;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    year = int.parse((await db
            .customSelect('SELECT name FROM fiscal_years')
            .get())
        .single
        .data['name'] as String);
    date = '$year-03-15';
    unitId = await db.insertUnit(name: 'قطعة');
    oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    sugarId = await db.insertItem(
        sku: 'G-200',
        name: 'سكر أحمر',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 12000,
        salePriceMinor: 20000,
        priceCurrencyId: 1);
    // صنف ثالث بلا شراء سابق — لاختبار فراغ اقتراح المورد
    teaId = await db.insertItem(
        sku: 'T-300',
        name: 'شاي أخضر',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 9000,
        salePriceMinor: 15000,
        priceCurrencyId: 1);
    customerId = await db.insertParty(
        number: '0001', name: 'عميل الأمل', kind: 'customer', defaultCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0002', name: 'مورد الشرق', kind: 'supplier', defaultCurrencyId: 1);
    boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;

    // ضخ رأس المال 500,000
    await db.postVoucher(await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      directAccountId: await accountIdByCode(db, '311'),
      cashBoxId: boxId,
      amountDocMinor: 500000,
    )));
    // شراء آجل: زيت 10×10,000 وسكر 10×5,000 من مورد الشرق (مصدر
    // اقتراح المورد للصنفين) — والشاي بلا شراء عمداً
    await db.postInvoice(await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 10000),
        InvoiceLineDraft(
            itemId: sugarId,
            unitId: unitId,
            qtyBase: 10,
            unitPriceMinor: 5000),
      ],
    )));
    // بيع آجل بسطرين: زيت 6×15,000 وسكر 4×20,000 = 170,000
    saleId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 6, unitPriceMinor: 15000),
        InvoiceLineDraft(
            itemId: sugarId,
            unitId: unitId,
            qtyBase: 4,
            unitPriceMinor: 20000),
      ],
    ));
    await db.postInvoice(saleId);
    saleLines = await db.invoiceLines(saleId);
    expect(saleLines, hasLength(2));
  });

  tearDown(() => db.close);

  test('س-141: ترحيلة v13 — العمودان على السطر من البذر والافتراضي '
      'غير مستلم بلفظ المالك «ما ليس محدد يكون غير مستلم»', () async {
    final cols = (await db.customSelect(
            "SELECT name FROM pragma_table_info('invoice_lines')")
          .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(cols, containsAll(['delivered', 'supplier_party_id']));
    // كل سطر بيع جديد يولد غير مستلم وبلا مورد
    for (final line in saleLines) {
      expect(line.delivered, isFalse, reason: 'الافتراضي غير مستلم');
      expect(line.supplierPartyId, isNull);
    }
  });

  test('س-139: قارئة غير المستلم تعرض سطري البيع الجديدين الأقدم أولاً '
      'والمسودة لا تدخل', () async {
    var rows = await db.undeliveredSaleLinesReport();
    expect(rows, hasLength(2));
    expect(rows[0].lineId, saleLines[0].id, reason: 'السطر الأول أقدم');
    expect(rows[0].invoiceNumber, '$year/000001');
    expect(rows[0].itemName, 'زيت محلي');
    expect(rows[1].itemName, 'سكر أحمر');
    expect(rows[0].partyName, 'عميل الأمل');

    // المسودة ليست بيعاً واقعياً — لا تدخل القائمة
    await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 1, unitPriceMinor: 15000),
      ],
    ));
    rows = await db.undeliveredSaleLinesReport();
    expect(rows, hasLength(2), reason: 'المسودة لا تدخل');
  });

  test('س-137/D-131: تحديد المربع يحفظ فوراً على المرحّلة — والقائمة '
      'تنقص سطراً — والميزان متوازن قبل العلم وبعده (F-068)', () async {
    final before = await db.trialBalanceReport();
    expect(before.isBalanced, isTrue);

    await db.setInvoiceLineDelivered(saleLines[0].id, delivered: true);
    final lines = await db.invoiceLines(saleId);
    expect(lines[0].delivered, isTrue);
    expect(lines[1].delivered, isFalse);

    final rows = await db.undeliveredSaleLinesReport();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'سكر أحمر');

    final after = await db.trialBalanceReport();
    expect(after.isBalanced, isTrue, reason: 'علم عمل لا محاسبة');
    expect(after.totalDebitMinor, before.totalDebitMinor);
    expect(after.totalCreditMinor, before.totalCreditMinor);
  });

  test('D-131: الحرس المحدَّث يسمح لعلم العمل ويمنع مال السطر كما كان '
      '— بلا فك إقفال', () async {
    // مال السطر ممنوع على المرحّلة كما كان (رسالة الحرس ذاتها)
    expect(
      () => db.customStatement(
          'UPDATE invoice_lines SET qty_base = 99 WHERE id = ?',
          [saleLines[0].id]),
      throwsA(anything),
    );
    expect(
      () => db.customStatement(
          'UPDATE invoice_lines SET unit_price_minor = 1 WHERE id = ?',
          [saleLines[0].id]),
      throwsA(anything),
    );
    // وعلم العمل والمورد يمران على السطر ذاته
    await db.setInvoiceLineDelivered(saleLines[0].id, delivered: true);
    await db.setInvoiceLineSupplier(saleLines[0].id, supplierPartyId: supplierId);
    final lines = await db.invoiceLines(saleId);
    expect(lines[0].delivered, isTrue);
    expect(lines[0].supplierPartyId, supplierId);
  });

  test('س-138/D-132: المورد المسؤول يُخزَّن على السطر ويظهر بقارئة '
      'المتابعة — والاقتراح من آخر شراء مرحّل للصنف وبلا شراء فراغ', () async {
    // للزيت والسكر شراء سابق فمورده هو المقترح؛ الشاي بلا شراء فnull
    expect(await db.latestSupplierPartyIdForItem(oilId), supplierId);
    expect(await db.latestSupplierPartyIdForItem(sugarId), supplierId);
    expect(await db.latestSupplierPartyIdForItem(teaId), isNull);

    await db.setInvoiceLineSupplier(saleLines[1].id, supplierPartyId: supplierId);
    final rows = await db.undeliveredSaleLinesReport();
    final sugarRow = rows.singleWhere((r) => r.itemName == 'سكر أحمر');
    expect(sugarRow.supplierPartyId, supplierId);
    expect(sugarRow.supplierName, 'مورد الشرق');

    // وإزالة المورد بتمرير null — اختيار المالك يُخزَّن كما هو
    await db.setInvoiceLineSupplier(saleLines[1].id, supplierPartyId: null);
    final after = await db.undeliveredSaleLinesReport();
    expect(
        after.singleWhere((r) => r.itemName == 'سكر أحمر').supplierPartyId,
        isNull);
  });

  test('س-142: السيناريو المعروف كاملاً — سطران فمستلم واحد فالقائمة '
      'سطر واحد بمورده، وفتح الفاتورة بالمعرف يعمل', () async {
    await db.setInvoiceLineDelivered(saleLines[0].id, delivered: true);
    await db.setInvoiceLineSupplier(saleLines[1].id, supplierPartyId: supplierId);

    final rows = await db.undeliveredSaleLinesReport();
    expect(rows, hasLength(1));
    expect(rows.single.invoiceId, saleId);
    expect(rows.single.supplierName, 'مورد الشرق');

    final invoice = await db.invoiceById(rows.single.invoiceId);
    expect(invoice, isNotNull);
    expect(invoice!.kind, 'sale');
  });
}
