import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 21 — F-168: فلتر الاستلام على قائمة الفواتير.
///
/// الحالات الثلاث محسوبة من عمود العلم القائم v13 بلا ترحيلة جديدة:
/// «غير مستلم» (كل الأسطر غير مستلمة أو لا أسطر) و«جزئي» (بعض
/// الأسطر مستلمة — الحالة التي تخفيها الثنائية كذباً) و«مكتمل
/// الاستلام» (كل الأسطر مستلمة). والعدّادان بالصف هما أساس لسان
/// القائمة والمطبوع والCSV فلا إعادة حساب ولا انحراف.
void main() {
  late DiqqahDatabase db;
  late String date;
  late int unitId;
  late int oilId;
  late int customerId;
  late int supplierId;
  late int warehouseId;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    final year = int.parse((await db
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
    customerId = await db.insertParty(
        number: '0001', name: 'عميل الأمل', kind: 'customer', defaultCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0002', name: 'مورد الشرق', kind: 'supplier', defaultCurrencyId: 1);
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
  });

  tearDown(() => db.close);

  test('F-168: فلتر الاستلام الثلاثي على القائمة — والجزئي حالة '
      'مستقلة لا تختفي بثنائية الفلتر', () async {
    // شراء مخزون 10 وحدات يُغطي المبيعات الثلاثة (5 وحدات) —
    // والشراء نفسه غير مستلم (العلم لم يُعلَّم عليه بعد).
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchaseId);

    // بيع غير مستلم — سطر واحد لم يُسلَّم.
    final saleA = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 1, unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(saleA);

    // بيع جزئي — سطران والأول مستلم (الحالة التي كانت ستُختفي).
    final saleB = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 1, unitPriceMinor: 15000),
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 2, unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(saleB);
    final saleBLines = await db.invoiceLines(saleB);
    await db.setInvoiceLineDelivered(saleBLines.first.id, delivered: true);

    // بيع مكتمل — سطره الوحيد مستلم.
    final saleC = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 1, unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(saleC);
    final saleCLines = await db.invoiceLines(saleC);
    await db.setInvoiceLineDelivered(saleCLines.single.id, delivered: true);

    // ═══ بلا فلتر: الأربع كلها بعدّاديهما ═══
    final all = await db.invoicesListReport();
    expect(all, hasLength(4));
    final rowA = all.singleWhere((r) => r.id == saleA);
    expect(rowA.linesTotal, 1);
    expect(rowA.linesUndelivered, 1);
    expect(rowA.receiptLabel, 'غير مستلم');

    // ═══ غير مستلم: الشراء والبيع الأول ═══
    final undelivered =
        await db.invoicesListReport(receiptFilter: 'undelivered');
    expect(undelivered, hasLength(2));
    expect(undelivered.map((r) => r.id), containsAll([purchaseId, saleA]));

    // ═══ جزئي: البيع الثاني وحده بلسانه الحرفي ═══
    final partial = await db.invoicesListReport(receiptFilter: 'partial');
    expect(partial, hasLength(1));
    expect(partial.single.id, saleB);
    expect(partial.single.receiptLabel, 'جزئي: مستلم 1 من 2');

    // ═══ مكتمل الاستلام: البيع الثالث وحده ═══
    final received = await db.invoicesListReport(receiptFilter: 'received');
    expect(received, hasLength(1));
    expect(received.single.id, saleC);
    expect(received.single.receiptLabel, 'مكتمل الاستلام');
  });

  test('F-168: فلتر الاستلام يجمع مع فلتر النوع — حصر مزدوج بلا تعارض',
      () async {
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchaseId);
    final purchaseLines = await db.invoiceLines(purchaseId);
    await db.setInvoiceLineDelivered(purchaseLines.single.id, delivered: true);

    final saleId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 1, unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(saleId);

    // الشراء مكتمل الاستلام والبيع غير مستلم — الحصر المزدوج يفصل.
    final purchaseReceived = await db.invoicesListReport(
        kindStorageValue: 'purchase', receiptFilter: 'received');
    expect(purchaseReceived, hasLength(1));
    expect(purchaseReceived.single.id, purchaseId);

    final saleUndelivered = await db.invoicesListReport(
        kindStorageValue: 'sale', receiptFilter: 'received');
    expect(saleUndelivered, isEmpty,
        reason: 'البيع غير مستلم فلا يمر بفلتر مكتمل الاستلام');
  });
}
