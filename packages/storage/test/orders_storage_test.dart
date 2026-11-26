// اختبارات تخزين الطلبات (س121 — 07 §3.2/D-026): الجداول والحواجز
// والترقيم والوفاء المحسوب والتحويل لفاتورة — والترحيلة v26→v27
// واقعيةَ المسار (إسقاط المخطط الجديد ثم إعادة الفتح).
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  /// بذر مصغر: وحدة وصنف وزبون ومورد وسنة مفتوحة.
  Future<(DiqqahDatabase, int, int, int, int, int, int)> seed() async {
    final db = DiqqahDatabase.inMemorySyncClose();
    await db.deviceId();
    final year = int.parse(
        (await db.customSelect('SELECT name FROM fiscal_years').get())
            .first
            .data['name'] as String);
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final customerId = await db.insertParty(
        number: '0001',
        name: 'عميل الأمل',
        kind: 'customer',
        defaultCurrencyId: 1);
    final supplierId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    return (db, year, unitId, oilId, customerId, supplierId, warehouseId);
  }

  OrderLineDraft line(int itemId, int qty, {int price = 40000}) =>
      OrderLineDraft(
          itemId: itemId,
          unitId: 1,
          qty: qty,
          qtyBase: qty,
          unitPriceMinor: price);

  OrderDraft saleOrderDraft(int partyId, int itemId,
          {int qty = 10, String date = '2026-03-15'}) =>
      OrderDraft(
          direction: OrderDirection.sale,
          orderDate: date,
          partyId: partyId,
          lines: [line(itemId, qty)]);

  test('الإنشاء كمسودة: بلا رقم وحدث created بلقطة والقائمة تُقرأ',
      () async {
    final (db, year, unitId, oilId, customerId, _, warehouseId) = await seed();
    addTearDown(db.close);

    final id = await db.createOrderDraft(saleOrderDraft(customerId, oilId));
    final list = await db.listOrders();
    expect(list, hasLength(1));
    expect(list.first.state, 'draft');
    expect(list.first.number, '');
    expect(list.first.partyName, 'عميل الأمل');
    expect(list.first.linesCount, 1);
    expect(list.first.totalQtyBase, 10);

    final events = await db.customSelect(
      "SELECT action, payload FROM events WHERE entity_type = 'order' "
      'AND entity_id = ?',
      variables: [Variable.withInt(id)],
    ).get();
    expect(events, hasLength(1));
    expect(events.first.data['action'], 'created');
    expect(await db.openLogText(events.first.data['payload'] as String),
        contains('"direction":"sale"'));
  });

  test('التأكيد يرقم بتسلسل السنة: 26000001 ثم 26000002 — ولكل اتجاه عداده',
      () async {
    final (db, year, unitId, oilId, customerId, supplierId, warehouseId) = await seed();
    addTearDown(db.close);
    expect(year, 2026);

    final a = await db.createOrderDraft(saleOrderDraft(customerId, oilId));
    final numberA = await db.confirmOrder(a);
    expect(numberA, '26000001');
    final b = await db.createOrderDraft(saleOrderDraft(customerId, oilId));
    expect(await db.confirmOrder(b), '26000002');
    final c = await db.createOrderDraft(
        saleOrderDraft(supplierId, oilId)
            .copyWithDirection(OrderDirection.purchase));
    final numberC = await db.confirmOrder(c);
    expect(numberC, '26000001'); // عداد الشراء مستقل عن البيع

    final rows = await db.customSelect(
      'SELECT kind, last_number FROM sequences WHERE kind LIKE '
      "'order_%' ORDER BY kind",
    ).get();
    expect(rows, hasLength(2));
  });

  test('الإنشاء بلا أسطر أو بلا طرف يرفض بفحص المحرك — وحرس التأكيد'
      ' (DQ-0705) دفاع ثانٍ على أي مسار آخر', () async {
    final (db, year, unitId, oilId, customerId, _, warehouseId) = await seed();
    addTearDown(db.close);

    expect(
        () => db.createOrderDraft(OrderDraft(
            direction: OrderDirection.sale,
            orderDate: '2026-03-15',
            partyId: customerId)),
        throwsA(isA<OrderValidationException>().having(
            (e) => e.errors.first, 'lines', isA<OrderLinesRequired>())));

    expect(
        () => db.createOrderDraft(OrderDraft(
            direction: OrderDirection.sale,
            orderDate: '2026-03-15',
            partyId: null,
            lines: [line(oilId, 5)])),
        throwsA(isA<OrderValidationException>()
            .having((e) => e.errors.first, 'party', isA<OrderPartyRequired>())));

    // حرس التأكيد الثانوي: أمر مُبذَر بأسطر عبر SQL مباشرة (تدفّق
    // خارج النموذج) يُرفض لحظة التأكيد بنص الحاجز — الحاجز الثاني
    // بعد فحص المحرك (07 §2.2).
    await db.customStatement(
      "INSERT INTO orders (direction, number, party_id, order_date, "
      "currency_id, state, uuid) VALUES ('sale', '', ?, '2026-03-15', "
      "1, 'draft', ?)",
      [customerId, 'bare-1'],
    );
    final bareId = (await db.customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle()).data['id'] as int;
    expect(
        () => db.confirmOrder(bareId),
        throwsA(isA<OrderValidationException>().having(
            (e) => e.errors.first, 'lines', isA<OrderLinesRequired>())));
  });

  test('التجميد: لا تعديل ولا إضافة سطر ولا حذف بعد التأكيد بنصوص DQ',
      () async {
    final (db, year, unitId, oilId, customerId, _, warehouseId) = await seed();
    addTearDown(db.close);
    final id = await db.createOrderDraft(saleOrderDraft(customerId, oilId));
    await db.confirmOrder(id);

    // تعديل الرأس — حاجز DQ-0702
    expect(
        () => db.customStatement(
            "UPDATE orders SET narration = 'سرقة' WHERE id = ?", [id]),
        throwsA(isA<SqliteException>().having((e) => e.message, 'msg', contains('DQ-0702'))));
    // إضافة سطر — حاجز DQ-0701
    expect(
        () => db.customStatement(
            'INSERT INTO order_lines (order_id, item_id, unit_id, qty, '
            'qty_base, uuid) VALUES (?, ?, 1, 1, 1, ?)',
            [id, oilId, 'x']),
        throwsA(isA<SqliteException>().having((e) => e.message, 'msg', contains('DQ-0701'))));
    // حذف سطر — حاجز DQ-0701
    expect(
        () => db.customStatement('DELETE FROM order_lines WHERE order_id = ?',
            [id]),
        throwsA(isA<SqliteException>().having((e) => e.message, 'msg', contains('DQ-0701'))));
    // حذف الأمر — حاجز DQ-0704
    expect(
        () => db.customStatement('DELETE FROM orders WHERE id = ?', [id]),
        throwsA(isA<SqliteException>().having((e) => e.message, 'msg', contains('DQ-0704'))));
    // والفحص الصريح بأصحّ لسان
    expect(() => db.updateOrderDraft(id, saleOrderDraft(customerId, oilId)),
        throwsA(isA<OrderValidationException>()));
    expect(() => db.deleteOrderDraft(id),
        throwsA(isA<OrderValidationException>()));
  });

  test('آلة الحالات بالحواجز: قفزة المسودة للإغلاق ولا رجوع من النهائي',
      () async {
    final (db, year, unitId, oilId, customerId, _, warehouseId) = await seed();
    addTearDown(db.close);
    final id = await db.createOrderDraft(saleOrderDraft(customerId, oilId));

    // قفزة مسودة ← إغلاق — حاجز DQ-0703
    expect(
        () => db.customStatement(
            "UPDATE orders SET state = 'closed' WHERE id = ?", [id]),
        throwsA(isA<SqliteException>().having((e) => e.message, 'msg', contains('DQ-0703'))));
    // الإلغاء من المسودة مسموح فلا رجوع منه بعدها — حاجز DQ-0703
    await db.cancelOrder(id);
    expect(
        () => db.customStatement(
            "UPDATE orders SET state = 'confirmed' WHERE id = ?", [id]),
        throwsA(isA<SqliteException>().having((e) => e.message, 'msg', contains('DQ-0703'))));
    // وإلغاء الملغاة رفض المحرك (لا انتقال)
    expect(
        () => db.cancelOrder(id),
        throwsA(isA<OrderValidationException>()
            .having((e) => e.errors.first, 't', isA<OrderTransitionInvalid>())));
  });

  test('حرس الإغلاق: المؤكد غير الموفى يرفض — والموفى كاملاً يُغلق',
      () async {
    final (db, year, unitId, oilId, customerId, supplierId, warehouseId) =
        await seed();
    addTearDown(db.close);
    final id = await db.createOrderDraft(saleOrderDraft(customerId, oilId));
    await db.confirmOrder(id);

    // المتبقي 10 — الإغلاق مرفوض بنوع الخط الموثق
    expect(
        () => db.closeOrder(id),
        throwsA(isA<OrderValidationException>().having((e) => e.errors.first,
            'close', isA<OrderCloseIncomplete>())));

    // فاتورة شراء بلا مرجع أمر تورّد المخزون، ثم فاتورة بيع من الأمر
    // (الزبون آجل — بلا صندوق) تفي بالتزامها ثم يُغلق الأمر.
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: '2026-03-15',
        partyId: supplierId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qty: 10,
              qtyBase: 10,
              unitPriceMinor: 25000),
        ]));
    await db.postInvoice(purchaseId);

    final invoiceId = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-16',
        partyId: customerId,
        warehouseId: warehouseId,
        orderId: id,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qty: 10,
              qtyBase: 10,
              unitPriceMinor: 40000),
        ]));
    final preview = await db.prepareOrderConversion(id);
    expect(preview.remainingQtyBaseOf(oilId), 0); // المسودة تحسباً

    await db.postInvoice(invoiceId);
    await db.closeOrder(id);

    final row = await db.customSelect(
      "SELECT state, number FROM orders WHERE id = ?",
      variables: [Variable.withInt(id)],
    ).getSingle();
    expect(row.data['state'], 'closed');
    // حدثا التأكيد والإغلاق بلقطاتهما
    final events = await db.customSelect(
      "SELECT action FROM events WHERE entity_type = 'order' AND entity_id = ? "
      'ORDER BY id',
      variables: [Variable.withInt(id)],
    ).get();
    expect(events.map((e) => e.data['action']).toList(),
        ['created', 'confirmed', 'closed']);
  });

  test('حرسا التحويل: الأمر غير المؤكد مرفوض والتجاوز للمتبقي مرفوض',
      () async {
    final (db, year, unitId, oilId, customerId, supplierId, warehouseId) =
        await seed();
    addTearDown(db.close);
    final draftId = await db.createOrderDraft(saleOrderDraft(customerId, oilId));

    // فاتورة على مسودة — مرفوضة
    expect(
        () => db.createInvoiceDraft(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: customerId,
            warehouseId: warehouseId,
            orderId: draftId,
            lines: [
              InvoiceLineDraft(
                  itemId: oilId,
                  unitId: unitId,
                  qty: 1,
                  qtyBase: 1,
                  unitPriceMinor: 40000),
            ])),
        throwsA(isA<InvoiceValidationException>().having((e) => e.errors.first,
            'not-confirmed', isA<InvoiceOrderNotConfirmed>())));

    await db.confirmOrder(draftId);
    // والمردود لا يأخذ مرجع أمر أصلاً — فمرجعٌ على مردود يمر بالحرس
    // ذاته (المؤكد حصراً) — والتجاوز مرفوض بنمط المردود عن الأصل
    expect(
        () => db.createInvoiceDraft(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: customerId,
            warehouseId: warehouseId,
            orderId: draftId,
            lines: [
              InvoiceLineDraft(
                  itemId: oilId,
                  unitId: unitId,
                  qty: 11,
                  qtyBase: 11,
                  unitPriceMinor: 40000),
            ])),
        throwsA(isA<InvoiceValidationException>().having(
            (e) => e.errors.first,
            'exceeds',
            isA<InvoiceOrderQtyExceedsRemaining>())));

    // فاتورة أولى بـ6 تُرحَّل فالمتبقي 4 — والثانية بـ5 تُرفض عند
    // الإنشاء (المتبقي محسوب من حي الفواتير)، والسادسة الثانية بـ4
    // تمر ثم تُرحَّل فلا تحسب نفسها مرتين.
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: '2026-03-15',
        partyId: supplierId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qty: 20,
              qtyBase: 20,
              unitPriceMinor: 25000),
        ]));
    await db.postInvoice(purchaseId);

    final first = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-16',
        partyId: customerId,
        warehouseId: warehouseId,
        orderId: draftId,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qty: 6,
              qtyBase: 6,
              unitPriceMinor: 40000),
        ]));
    expect(
        () => db.createInvoiceDraft(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-16',
            partyId: customerId,
            warehouseId: warehouseId,
            orderId: draftId,
            lines: [
              InvoiceLineDraft(
                  itemId: oilId,
                  unitId: unitId,
                  qty: 5,
                  qtyBase: 5,
                  unitPriceMinor: 40000),
            ])),
        throwsA(isA<InvoiceValidationException>()));
    final second = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-16',
        partyId: customerId,
        warehouseId: warehouseId,
        orderId: draftId,
        lines: [
          InvoiceLineDraft(
              itemId: oilId,
              unitId: unitId,
              qty: 4,
              qtyBase: 4,
              unitPriceMinor: 40000),
        ]));
    // ترحيل الأولى: فحص الترحيل يستثني الفاتورة ذاتها فلا تحسب مرتين
    await db.postInvoice(first);
    await db.postInvoice(second);
    final remaining = await db.orderFulfilledQtyByItem(draftId);
    expect(remaining[oilId], 10);
    await db.closeOrder(draftId);
  });

  test('الترحيلة v26→v27 واقعية: إسقاط الجديد ثم إعادة الففتح يبنيه كله',
      () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    await db.deviceId();
    // محاكاة قاعدة v26: إسقاط جداول الطلبات ومشغلاتها وعمود المرجع
    // من الفواتير (SQLite ≥3.35 يدعم DROP COLUMN) ثم تخفيض الإصدار.
    await db.customStatement('DROP TABLE IF EXISTS order_lines');
    await db.customStatement('DROP TABLE IF EXISTS orders');
    await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_order_lines_frozen_insert');
    await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_order_lines_frozen_update');
    await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_order_lines_frozen_delete');
    await db.customStatement('DROP TRIGGER IF EXISTS trg_orders_frozen');
    await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_orders_transition_guard');
    await db.customStatement('DROP TRIGGER IF EXISTS trg_orders_no_delete');
    await db.customStatement('ALTER TABLE invoices DROP COLUMN order_id');
    await db.customStatement('PRAGMA user_version = 26');
    await db.close();

    // إعادة الفتح تجري الترحيلة 26→27 فتبني الجداول والعمود والمشغلات
    final migrated = DiqqahDatabase.inMemorySyncClose();
    addTearDown(migrated.close);
    await migrated.deviceId();

    final tables = await migrated.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND "
      "name IN ('orders', 'order_lines')",
    ).get();
    expect(tables, hasLength(2));
    final cols = await migrated.customSelect(
      "SELECT name FROM pragma_table_info('invoices')",
    ).get();
    expect(cols.map((c) => c.data['name']), contains('order_id'));
    final triggers = await migrated.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND "
      "name LIKE 'trg_order%'",
    ).get();
    expect(triggers, hasLength(6));
    // والأمر يعمل فوق القاعدة المرقية
    final year = int.parse(
        (await migrated.customSelect('SELECT name FROM fiscal_years').get())
            .first
            .data['name'] as String);
    final unitId = await migrated.insertUnit(name: 'قطعة');
    final oilId = await migrated.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    final customerId = await migrated.insertParty(
        number: '0001',
        name: 'عميل الأمل',
        kind: 'customer',
        defaultCurrencyId: 1);
    final id = await migrated.createOrderDraft(OrderDraft(
        direction: OrderDirection.sale,
        orderDate: '$year-03-15',
        partyId: customerId,
        lines: [
          OrderLineDraft(
              itemId: oilId, unitId: unitId, qty: 5, qtyBase: 5),
        ]));
    final number = await migrated.confirmOrder(id);
    expect(number, '${year % 100}000001');
  });

  test('فلترا القائمة: بالاتجاه وبالحالة', () async {
    final (db, year, unitId, oilId, customerId, supplierId, warehouseId) = await seed();
    addTearDown(db.close);
    final saleId =
        await db.createOrderDraft(saleOrderDraft(customerId, oilId));
    await db.confirmOrder(saleId);
    final purchaseId = await db.createOrderDraft(
        saleOrderDraft(supplierId, oilId)
            .copyWithDirection(OrderDirection.purchase));
    await db.createOrderDraft(saleOrderDraft(customerId, oilId));

    expect((await db.listOrders(direction: OrderDirection.purchase)).first.id,
        purchaseId);
    final confirmed =
        await db.listOrders(state: OrderState.confirmed);
    expect(confirmed, hasLength(1));
    expect(confirmed.first.id, saleId);
    expect(await db.listOrders(), hasLength(3));
  });
}

extension on OrderDraft {
  /// مساعدة الاختبار — نفس المسودة باتجاه آخر.
  OrderDraft copyWithDirection(OrderDirection direction) => OrderDraft(
      direction: direction,
      orderDate: orderDate,
      partyId: partyId,
      warehouseId: warehouseId,
      expectedDate: expectedDate,
      currencyId: currencyId,
      narration: narration,
      lines: lines);
}
