import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/orders_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات شاشة طلبات البيع والشراء — س123 (الواجهة) على أساس س121
/// (المجال والتخزين وحرسا التحويل — 09 §18): القائمة بفلتريها والنموذج
/// بمسودته والتفصيل بأفعاله المحروسة والتحويل النافذ المبذر والطباعة.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26) — والحكم بنصوص فريدة لا اشتراكات عائمة (درس س35)،
/// والأرقام المعروفة من دورة seedKnownCycle.
Future<(int, int, int, int, int)> _idsOf(DiqqahDatabase db) async {
  final unit = await db.customSelect(
      'SELECT id FROM units ORDER BY id LIMIT 1').getSingle();
  final item = await db.customSelect(
      'SELECT id FROM items ORDER BY id LIMIT 1').getSingle();
  final customer = await db.customSelect(
      "SELECT id FROM parties WHERE kind = 'customer' "
      'ORDER BY id LIMIT 1').getSingle();
  final supplier = await db.customSelect(
      "SELECT id FROM parties WHERE kind = 'supplier' "
      'ORDER BY id LIMIT 1').getSingle();
  final warehouse = await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1').getSingle();
  return (
    unit.data['id'] as int,
    item.data['id'] as int,
    customer.data['id'] as int,
    supplier.data['id'] as int,
    warehouse.data['id'] as int,
  );
}

/// أمر بيع مسودة جاهز بأرقام الدورة — زيت محلي 10 × 40,000
/// (والكمية قابلة للضبط: التحويل النافذ يحتاج كميةً ضمن رصيد المستودع
/// المتاح — منع السالب F-042 يحرس فاتورة التحويل كما تحرس كل فاتورة).
Future<int> _seedSaleDraft(DiqqahDatabase db, {int qty = 10}) async {
  final yearRows =
      await db.customSelect('SELECT name FROM fiscal_years').get();
  final year = int.parse(yearRows.single.data['name'] as String);
  final (unitId, oilId, customerId, _, warehouseId) = await _idsOf(db);
  return db.createOrderDraft(OrderDraft(
    direction: OrderDirection.sale,
    partyId: customerId,
    warehouseId: warehouseId,
    orderDate: '$year-03-15',
    expectedDate: '$year-03-20',
    narration: 'أمر دورة الاختبار',
    lines: [
      OrderLineDraft(
          itemId: oilId,
          unitId: unitId,
          qty: qty,
          qtyBase: qty,
          unitPriceMinor: 40000),
    ],
  ));
}

/// أمر شراء مسودة — مورد الشرق 5 × 25,000.
Future<int> _seedPurchaseDraft(DiqqahDatabase db) async {
  final yearRows =
      await db.customSelect('SELECT name FROM fiscal_years').get();
  final year = int.parse(yearRows.single.data['name'] as String);
  final (unitId, oilId, _, supplierId, warehouseId) = await _idsOf(db);
  return db.createOrderDraft(OrderDraft(
    direction: OrderDirection.purchase,
    partyId: supplierId,
    warehouseId: warehouseId,
    orderDate: '$year-03-16',
    lines: [
      OrderLineDraft(
          itemId: oilId,
          unitId: unitId,
          qty: 5,
          qtyBase: 5,
          unitPriceMinor: 25000),
    ],
  ));
}

void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('س123-1: قائمة الطلبات تعرض الأمرين بتسميهما وحالتيهما '
      'وفلتر الاتجاه يعزل الأوامر', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await _seedSaleDraft(db);
    final purchaseId = await _seedPurchaseDraft(db);
    await db.confirmOrder(purchaseId);

    await tester.pumpWidget(MaterialApp(home: OrdersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المسودة بنادِها والمرقّم برقمه — والحالتان ظاهرتان بشهادتهما.
    expect(find.text('مسودة أمر بيع'), findsOneWidget);
    expect(find.text('أمر شراء رقم 26000001'), findsOneWidget);
    expect(find.text('مسودة'), findsOneWidget);
    expect(find.text('مؤكدة'), findsOneWidget);

    // فلتر الاتجاه: أمر بيع يعزل بيعه — والعد بالعناوين لا بالعدّادات.
    await tester.tap(find.text('كل الاتجاهات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('أمر بيع').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('مسودة أمر بيع'), findsOneWidget);
    expect(find.text('أمر شراء رقم 26000001'), findsNothing);
  });

  testWidgets('س123-2: نموذج الأمر ينشئ مسودة — والطرف بأهليته '
      '(أمر بيع يطلب زبوناً) والكمية بمكافئها', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
        home: OrderEditScreen(
            db: db, direction: OrderDirection.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الطرف بأهليته: الزبون حاضر والمورد لا يصلح لأمر بيع.
    await tester.tap(find.text('الزبون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('0001 عميل الأمل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // الصنف والكمية — السعر المرجعي يُعبأ آلياً من سعر البيع (40,000).
    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('Z-100 زيت محلي').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية'), '10');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // السعر المرجعي المعبأ آلياً ظاهر بالحقل — تسعير وقت الأمر.
    expect(find.text('40,000'), findsOneWidget);

    // حلقة التمرير الموثقة — نموذج الأمر طويل فالزر أسفله غير مبني
    // قبل تمريره إليه (درس السرد الكسول س35/س36).
    for (var i = 0;
        i < 14 && find.text('حفظ كمسودة').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('حفظ كمسودة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final orders = await db.customSelect(
        'SELECT state, party_id, number FROM orders WHERE is_deleted = 0')
        .get();
    expect(orders.length, 1, reason: 'مسودة واحدة بلا رقم');
    expect(orders.single.data['state'], 'draft');
    expect(orders.single.data['number'], '');
    final lines = await db.customSelect(
        'SELECT qty, qty_base FROM order_lines WHERE is_deleted = 0').get();
    expect(lines.single.data['qty'], 10);
    expect(lines.single.data['qty_base'], 10);
  });

  testWidgets('س123-3: التأكيد من التفصيل يصدر الرقم السنوي — '
      'والأمر المؤكد يعرض خلاصة وفائه وزر تحويله', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final orderId = await _seedSaleDraft(db);

    await tester.pumpWidget(MaterialApp(
        home: OrderDetailScreen(db: db, orderId: orderId)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // أفعال المسودة الأربعة ظاهرة — والإغلاق والتحويل ليسا لها.
    expect(find.text('تأكيد وإصدار الرقم'), findsOneWidget);
    expect(find.text('تحويل لفاتورة'), findsNothing);

    // نافذة التأكيد الواعية ثم الإصدار.
    await tester.tap(find.text('تأكيد وإصدار الرقم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('تأكيد وإصدار الرقم').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('أُصدر رقمه 26000001'), findsOneWidget);

    final order = await db.customSelect(
        'SELECT state, number FROM orders WHERE id = $orderId').getSingle();
    expect(order.data['state'], 'confirmed');
    expect(order.data['number'], '26000001');

    // المؤكدة: خلاصة الوفاء بالأرقام الحية وزر التحويل — والإغلاق
    // معطل بنص سببه (المتبقي أكبر من صفر).
    expect(find.textContaining('خلاصة الوفاء'), findsOneWidget);
    expect(find.text('تحويل لفاتورة'), findsOneWidget);
    expect(find.textContaining('الإغلاق معطل'), findsOneWidget);
    final closeBtn = find.widgetWithText(OutlinedButton, 'إغلاق الأمر');
    expect(closeBtn, findsOneWidget);
    final outBtn = tester.widget<OutlinedButton>(closeBtn);
    expect(outBtn.onPressed, isNull,
        reason: 'لا إغلاق والمتبقي أكبر من صفر — DQ-0706 بالواجهة');
  });

  testWidgets('س123-4: التحويل النافذ يبذر نموذج الفاتورة بالمتبقي '
      'بأسعار الأمر — والفاتورة المحفوظة مرجعة للأمر بلا تجاوز',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // الكمية 4 = رصيد المستودع المتاح بعد دورة البذرة (اشترى 10 وباع
    // 6) — فاتورة التحويل مسودة تحرسها منع السالب F-042 كغيرها.
    final orderId = await _seedSaleDraft(db, qty: 4);
    await db.confirmOrder(orderId);

    await tester.pumpWidget(MaterialApp(
        home: OrderDetailScreen(db: db, orderId: orderId)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // النافذة: المتبقي الحي ثم فتح النموذج المبذر — والنص مرتين
    // (خلاصة الوفاء خلف النافذة وداخلها فالقاضي بالحاضرين لا بالواحد).
    await tester.tap(find.text('تحويل لفاتورة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('تحويل الأمر لفاتورة'), findsOneWidget);
    expect(find.textContaining('المتبقي 4'), findsWidgets);
    await tester.tap(find.text('فتح نموذج الفاتورة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // النموذج المبذر: عنوانه بأمره وكمية السطر المتبقي بسعر الأمر
    // المرجعي — بذرة قابلة للتعديل قبل الترحيل.
    expect(find.text('فاتورة من أمر 26000001'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'الكمية'), findsOneWidget);
    final qtyField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'الكمية'));
    expect(qtyField.controller!.text, '4');
    final priceField = tester.widget<TextField>(find.widgetWithText(
        TextField, 'سعر الوحدة بوحدة صغرى'));
    expect(priceField.controller!.text, '40,000');

    // التاريخ داخل سنة الدورة كي يمر ترحيلُ المسودات لا — حفظ مسودة
    // كافٍ والتحقق بمرجع الأمر وكميته الأساسية.
    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'),
        '2026-03-16');
    // حلقة التمرير الموثقة (درس السرد الكسول س35/س36): القائمة تُبنى
    // للظاهر حصراً فالزر أسفل النموذج غير مبني قبل تمريره إليه.
    for (var i = 0;
        i < 14 && find.text('حفظ كمسودة').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('حفظ كمسودة'));
    // الاستقرار الكامل بعد التمرير الحركي لـensureVisible — الضغطة على
    // هدفاً متحركاً تفوته (اصطلاح اختبارات الفواتير pumpAndSettle حرفاً).
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ كمسودة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final inv = await db.customSelect(
        'SELECT id, order_id, kind, state FROM invoices '
        'WHERE order_id IS NOT NULL').get();
    expect(inv.length, 1, reason: 'فاتورة واحدة مرجعة للأمر');
    expect(inv.single.data['order_id'], orderId);
    expect(inv.single.data['kind'], 'sale');
    expect(inv.single.data['state'], 'draft');
    final line = await db.customSelect(
        'SELECT qty_base FROM invoice_lines '
        'WHERE invoice_id = ${inv.single.data['id']}').getSingle();
    expect(line.data['qty_base'], 4);
  });

  test('س123-5: طباعة الأمر تولد بايتات PDF سليمة بألسنة الأمر — '
      'والمسودة بنادِها والمرقّم برقمه', () async {
    final head = OrderListRow(
      id: 1,
      direction: 'sale',
      number: '26000001',
      partyId: 7,
      partyName: 'عميل الأمل',
      warehouseId: 1,
      orderDate: '2026-03-15',
      expectedDate: '2026-03-20',
      currencyId: 1,
      state: 'confirmed',
      linesCount: 2,
      totalQtyBase: 15,
    );
    final lines = [
      OrderLineRow(
          id: 1,
          orderId: 1,
          itemId: 1,
          itemSku: 'Z-100',
          itemName: 'زيت محلي',
          unitId: 1,
          factorAtEntry: 1,
          qty: 10,
          qtyBase: 10,
          unitPriceMinor: 40000),
      OrderLineRow(
          id: 2,
          orderId: 1,
          itemId: 1,
          itemSku: 'Z-100',
          itemName: 'زيت محلي',
          unitId: 1,
          unitLevelId: 1,
          factorAtEntry: 5,
          qty: 1,
          qtyBase: 5,
          unitPriceMinor: 200000),
    ];
    final bytes = await buildOrderPdf(
      head: head,
      lines: lines,
      unitNames: const {1: 'قطعة'},
      levelNames: const {1: 'كرتونة'},
      warehouseName: 'المستودع الرئيسي',
    );
    expect(bytes.length, greaterThan(1000));
    // ترويج PDF الصحيح — بايتات تبدأ بالترويج القياسي.
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');

    // ألسنة العرض النقية — التسمية والصفوف قبل دخول المطبوع.
    expect(orderDisplayLabel(head), 'أمر بيع رقم 26000001');
    expect(orderStateLabelOf('confirmed'), 'مؤكدة');
    expect(orderDirectionLabelOf('purchase'), 'أمر شراء');
    final rows = orderPdfRows(
        lines: lines,
        unitNames: const {1: 'قطعة'},
        levelNames: const {1: 'كرتونة'});
    expect(rows.length, 2);
    expect(rows[0][3], '10', reason: 'الكمية بالوحدة الأساسية');
    expect(rows[1][2], 'كرتونة', reason: 'وحدة السطر بلقطته');
    expect(rows[1][3], '1');
    expect(rows[0][4], '40,000');
    expect(rows[0][5], '400,000');
  });
}
