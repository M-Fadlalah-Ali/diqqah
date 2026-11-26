import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 23 — F-146 قراءتا الاقتراح وF-165 كتابة الترقية
/// الجماعية (D-183).
///
/// الحدود الموثقة: الاقتراح قراءة لا كتابة (القبول بشري بالواجهة)،
/// «الأكثر تداولاً» من المرحّل حصراً بعائلة الجهة ومنذ التاريخ، وآخر
/// سعر فعلي موجب حصراً والأحدث فوزاً، والترقية معاملة واحدة لا تمس
/// الحقل غير المستهدف ولا فواتير التاريخ (لقطاتها سليمة). وبذر الشراء
/// أولاً نمط archive_receipt: البيع المرحّل يطلب مخزوناً (F-042).
void main() {
  late DiqqahDatabase db;
  late String year;
  late String date;
  late int unitId;
  late int oilId;
  late int riceId;
  late int customerId;
  late int otherCustomerId;
  late int supplierId;
  late int warehouseId;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    year = int.parse((await db
            .customSelect('SELECT name FROM fiscal_years')
            .get())
        .single
        .data['name'] as String)
        .toString();
    date = '$year-03-15';
    unitId = await db.insertUnit(name: 'قطعة');
    oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    riceId = await db.insertItem(
        sku: 'R-200',
        name: 'أرز فاخر',
        category: 'أرز',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 30000,
        salePriceMinor: 50000,
        priceCurrencyId: 1);
    customerId = await db.insertParty(
        number: '0001',
        name: 'عميل الأمل',
        kind: 'customer',
        defaultCurrencyId: 1);
    otherCustomerId = await db.insertParty(
        number: '0002',
        name: 'عميل النور',
        kind: 'customer',
        defaultCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0003',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    // بذرة مخزون تغطي مبيعات الاختبار كلها (منع السالب F-042).
    final seedPurchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 100, unitPriceMinor: 25000),
        InvoiceLineDraft(
            itemId: riceId, unitId: unitId, qtyBase: 100, unitPriceMinor: 30000),
      ],
    ));
    await db.postInvoice(seedPurchase);
  });

  tearDown(() => db.close);

  Future<int> postSale({
    required int partyId,
    required int itemId,
    required int priceMinor,
    String? onDate,
  }) async {
    final id = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: onDate ?? date,
      partyId: partyId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId,
            unitId: unitId,
            qtyBase: 1,
            unitPriceMinor: priceMinor),
      ],
    ));
    await db.postInvoice(id);
    return id;
  }

  group('partyUsageCounts — المرحّل حصراً بعائلة الجهة ومنذ التاريخ', () {
    test('العد يعقد المردود مع البيع ويستبعد المسودة والبعيد زمنياً',
        () async {
      final firstSale =
          await postSale(partyId: customerId, itemId: oilId, priceMinor: 40000);
      await postSale(partyId: customerId, itemId: oilId, priceMinor: 41000);
      // مردود بيع لذات العميل بمرجعه الأصل (س-05/س-11: المرجع إلزاماً)
      // — تداول حقيقي يُعد.
      final returnId = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.saleReturn,
        dateText: date,
        partyId: customerId,
        warehouseId: warehouseId,
        originalInvoiceId: firstSale,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qtyBase: 1,
              unitPriceMinor: 40000),
        ],
      ));
      await db.postInvoice(returnId);
      // مسودة لا تُعد — الاقتراح من الواقع المرحّل حصراً.
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: date,
        partyId: customerId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qtyBase: 1,
              unitPriceMinor: 42000),
        ],
      ));
      // فاتورة قبل النافذة (داخل السنة المالية لكن قبل منذ-التاريخ) لا تُعد.
      await postSale(
          partyId: customerId,
          itemId: oilId,
          priceMinor: 39000,
          onDate: '$year-01-05');

      final counts = await db.partyUsageCounts(
          salesSide: true, sinceIso: date);
      expect(counts[customerId], 3,
          reason: 'بيعان + مردود — والمسودة والقديم خارجان');
      // الشراء المبذور على المورد لا يتسرب لعائلة البيع.
      expect(counts.containsKey(supplierId), isFalse);
    });

    test('عائلة الشراء ترى المورد لا العميل — والعكس صحيح', () async {
      await postSale(partyId: customerId, itemId: oilId, priceMinor: 40000);
      final purchaseCounts = await db.partyUsageCounts(
          salesSide: false, sinceIso: date);
      expect(purchaseCounts[supplierId], 1,
          reason: 'بذرة الشراء الواحدة على المورد');
      expect(purchaseCounts.containsKey(customerId), isFalse);
      final saleCounts = await db.partyUsageCounts(
          salesSide: true, sinceIso: date);
      expect(saleCounts.containsKey(supplierId), isFalse);
      expect(saleCounts[customerId], 1);
    });
  });

  group('lastPricesForParty — آخر سعر فعلي موجب والأحدث فوزاً', () {
    test('الأحدث يتقدم والمسودة والصفري لا يقترحان', () async {
      await postSale(partyId: customerId, itemId: oilId, priceMinor: 41000);
      await postSale(partyId: customerId, itemId: oilId, priceMinor: 42500);
      // سطر بلا سعر (س6: الصفر مشروع) في فاتورة فيها مدفوع — فلا قيد
      // بصافي صفر — والصفري لا يقترح، والمدفوع الأخير فوز.
      final freeSale = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: date,
        partyId: customerId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: riceId, unitId: unitId, qtyBase: 1, unitPriceMinor: 0),
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qtyBase: 1,
              unitPriceMinor: 42500),
        ],
      ));
      await db.postInvoice(freeSale);
      // مسودة بسعر — لا تُقرأ، الاقتراح من المرحّل حصراً.
      await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: date,
        partyId: customerId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qtyBase: 1,
              unitPriceMinor: 99999),
        ],
      ));

      final map =
          await db.lastPricesForParty(partyId: customerId, salesSide: true);
      expect(map[oilId]!.priceMinor, 42500, reason: 'الأحدث المرحّل فوز');
      expect(map[oilId]!.docLabel, contains(date));
      expect(map.containsKey(riceId), isFalse,
          reason: 'السعر الصفري لا يقترح (س6)');
    });

    test('طرف آخر لا يتسرب اقتراحه — والشراء لا يرى أسعار البيع', () async {
      await postSale(
          partyId: otherCustomerId, itemId: oilId, priceMinor: 45000);
      expect(
        (await db.lastPricesForParty(partyId: customerId, salesSide: true)),
        isEmpty,
      );
      expect(
        (await db.lastPricesForParty(
                partyId: otherCustomerId, salesSide: false))
            .containsKey(oilId),
        isFalse,
      );
      // وبذرة الشراء تظهر لسعر الشراء على المورد نفسه.
      expect(
        (await db.lastPricesForParty(partyId: supplierId, salesSide: false))
            .containsKey(oilId),
        isTrue,
      );
    });
  });

  group('applyBulkPriceUpdates — معاملة واحدة والحقل الغائب لا يُمس', () {
    test('ترقية بيع فقط تترك الشراء كما هو والعكس', () async {
      await db.applyBulkPriceUpdates([
        BulkPriceUpdateRow(
            itemId: oilId,
            newSalePriceMinor: 44000,
            newPurchasePriceMinor: null),
        BulkPriceUpdateRow(
            itemId: riceId,
            newSalePriceMinor: null,
            newPurchasePriceMinor: 33000),
      ]);
      final rows = await db.select(db.items).get();
      final oil = rows.firstWhere((r) => r.id == oilId);
      final rice = rows.firstWhere((r) => r.id == riceId);
      expect(oil.salePriceMinor, 44000);
      expect(oil.purchasePriceMinor, 25000, reason: 'الغائب لم يُمس');
      expect(rice.salePriceMinor, 50000, reason: 'الغائب لم يُمس');
      expect(rice.purchasePriceMinor, 33000);
    });
  });
}
