import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/hijri_display.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/price_update_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات الدفعة 23 (D-183): F-165 الترقية الجماعية بالتصنيف (معاينة
/// قبل التنفيذ والصفر ليس سعراً) وF-146 اقتراحات الإدخال (آخر سعر فعلي
/// بوسم مصدره ورقاقة الأكثر تداولاً) وF-167 عرض الهجري بجانب الميلادي.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// في التدفقات الحية (درس س22..س26)، وعضو pumpWidget واحد لكل اختبار
/// (درس الجولة 183)، وأرقام الدورة المعروفة من seedKnownCycle.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// تعيين تصنيف الصنف المبذور (تحديث التفاصيل س-35/D-153 — لا صنفاً
  /// جديداً فتبقى أرقام الدورة المعروفة ثابتة).
  Future<void> setCategory(DiqqahDatabase db, String category) async {
    final item = (await db.select(db.items).get())
        .firstWhere((i) => i.name == 'زيت محلي');
    await db.updateItemDetails(
      item,
      sku: item.sku,
      name: item.name,
      category: category,
      kind: item.kind,
      baseUnitId: item.baseUnitId,
      purchasePriceMinor: item.purchasePriceMinor,
      salePriceMinor: item.salePriceMinor,
      priceCurrencyId: item.priceCurrencyId,
    );
  }

  /// التحول من النقدية إلى الآجل بنمط batch22 المعتمد.
  Future<void> switchToCredit(WidgetTester tester) async {
    await tester.tap(find.text('نقدي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('آجل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// اختيار الطرف ثم الصنف بنمط batch22.
  Future<void> pickPartyAndItem(WidgetTester tester) async {
    await tester.tap(find.text('العميل (الآجل يطلب طرفاً)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('عميل الأمل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('Z-100 زيت محلي').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  test('F-167: displayDate — الميلادي وحده افتراضاً والهجري بجانبه '
      'حين يُفعَّل، والفاسد يمر بلا اختراع', () async {
    SharedPreferences.setMockInitialValues({});
    await loadHijriDisplayPref();
    expect(hijriDisplayEnabled.value, isFalse,
        reason: 'الافتراض مطفأ — لا شيء يتغير بلا طلب');
    expect(displayDate('2026-11-04'), '2026-11-04');

    await setHijriDisplayEnabled(true);
    expect(displayDate('2026-11-04'), '2026-11-04 (هـ 1448-05-23)');
    expect(displayDate('بلا تاريخ'), 'بلا تاريخ',
        reason: 'المدخل الفاسد يعود كما هو بلا اختراع');
    expect(displayDate('2026-02-30'), '2026-02-30',
        reason: 'تاريخ زائف يمر كما هو لا يُخترع له هجري');

    // إرجاع الحالة الجارية لمن يأتي بعدي — الاختبار لا يلوث إخوانه.
    await setHijriDisplayEnabled(false);
  });

  testWidgets('F-165: المعاينة قبل التنفيذ والتنفيذ يكتب المعاين حرفاً '
      'والحقل غير المستهدف لا يُمس', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await setCategory(db, 'زيوت');

    await tester.pumpWidget(MaterialApp(
        home: PriceUpdateScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('التصنيف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('زيوت').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextField, 'النسبة بالمئة (مثال: 2.5 أو -3)'),
        '2.5');
    await tester.pump();

    await tester.tap(find.text('معاينة (1 صنفاً في التصنيف)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 40,000 × 1.025 = 41,000 بالتمام — والمعاينة معروضة قبل أي كتابة.
    expect(find.textContaining('41,000'), findsWidgets);
    expect(find.text('تنفيذ الترقية على 1 صنفاً'), findsOneWidget);

    await tester.tap(find.text('تنفيذ الترقية على 1 صنفاً'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('تأكيد الترقية الجماعية'), findsOneWidget);
    await tester.tap(find.text('تنفيذ الترقية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final rows = await db.customSelect(
      "SELECT sale_price_minor, purchase_price_minor FROM items "
      "WHERE name = 'زيت محلي'",
      variables: [],
    ).getSingle();
    expect(rows.data['sale_price_minor'], 41000,
        reason: 'الترقية كُتبت بالمعاين حرفاً');
    expect(rows.data['purchase_price_minor'], 25000,
        reason: 'الحقل غير المستهدف لا يُمس إطلاقاً');
  });

  testWidgets('F-165: الصفر ليس سعراً فلا يُعد تغييراً — والزر يعدّ '
      'المتغيرين حصراً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await setCategory(db, 'زيوت');
    // صنف خدمة بلا سعر (س6: الصفر مشروع) بالتصنيف ذاته.
    final unitId = (await db.customSelect(
      'SELECT id FROM units ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    await db.insertItem(
        sku: 'S-900',
        name: 'صيانة عدّاد',
        category: 'زيوت',
        kind: 'service',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 0,
        priceCurrencyId: 1);

    await tester.pumpWidget(MaterialApp(
        home: PriceUpdateScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('التصنيف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('زيوت').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextField, 'النسبة بالمئة (مثال: 2.5 أو -3)'),
        '10');
    await tester.pump();

    await tester.tap(find.text('معاينة (2 صنفاً في التصنيف)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // الزر يعدّ المتغيرَين حصراً — والصفر بقي صفراً فخارج العدّ.
    expect(find.text('تنفيذ الترقية على 1 صنفاً'), findsOneWidget);
  });

  testWidgets('F-146: آخر سعر فعلي مع الطرف يقدَّم على المرجعي '
      'بوسم مصدر يُرى لا يُخفى', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(
            db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await switchToCredit(tester);
    await pickPartyAndItem(tester);

    // آخر سعر مرحّل مع عميل الأمل 15,000 يُقدَّم على المرجعي 40,000 —
    // ووسم المصدر يظهر ليُعرف من أين جاء الاقتراح (الصدق أولاً).
    expect(
        find.widgetWithText(
            TextField, 'سعر الوحدة بوحدة صغرى'),
        findsOneWidget);
    final priceField = tester.widget<TextField>(find.widgetWithText(
        TextField, 'سعر الوحدة بوحدة صغرى'));
    expect(priceField.controller!.text, '15,000',
        reason: 'آخر سعر فعلي 15,000 لا المرجعي 40,000');
    expect(find.textContaining('آخر سعر مع عميل الأمل'), findsOneWidget);
  });

  testWidgets('F-146: رقاقة «الأكثر تداولاً» تُقبل بضغطة — والقائمة '
      'تبقى يدوية كاملة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // تداول اليوم داخل نافذة التسعين — بذرة الدورة بتاريخ مارس خارجها
    // بحق (النافذة قرار D-183: الاقتراح من النشاط القريب لا الأثرياء).
    final unitId = (await db.customSelect(
      'SELECT id FROM units ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final oilId = (await db.customSelect(
      "SELECT id FROM items WHERE name = 'زيت محلي'",
    ).getSingle()).data['id'] as int;
    final customerId = (await db.customSelect(
      "SELECT id FROM parties WHERE name = 'عميل الأمل'",
    ).getSingle()).data['id'] as int;
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final todaySale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: todayIsoDate(),
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId,
            unitId: unitId,
            qtyBase: 1,
            unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(todaySale);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(
            db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await switchToCredit(tester);

    // عميل الأمل هو الوحيد المتداول المرحّل في الدورة — الرقاقة تقترحه.
    expect(find.textContaining('اقتراح: عميل الأمل'), findsOneWidget);
    await tester.tap(find.textContaining('اقتراح: عميل الأمل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // القبول بضغطة: الطرف انتُقي والرقاقة صمتت (لا اقتراح بعد الاختيار).
    expect(find.textContaining('اقتراح: عميل الأمل'), findsNothing);
    expect(find.text('0001 عميل الأمل'), findsOneWidget);
  });
}
