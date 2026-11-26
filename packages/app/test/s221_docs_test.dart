import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/list_display.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// س221 — دفعة قوائم المستندات (بأمر المالك «ابدأ بتنفيذ الدفعات
/// الخمسة بالتسلسل الذي عرضته»):
///
/// 1. عزل النوع بأمر المالك («النوع يعرض 7 خيارات نصفها للبيع ونصفها
///    للمشتريات دون تمييز ينبغي العزل»): الجهة المفتوحة لا ترى أنواع
///    الجهة الأخرى إطلاقاً — المبيعات ببيعها ومردوده والمشتريات بشرائها
///    ومردوده و«الكل» فيها جهتها كلها لا القاعدة كلها، والدخول الحيادي
///    (سجل الفواتير) جامع بألسنة معلّمة بالجهة.
/// 2. إعادة تشكيل القوائم (المساحة الموثقة 09: «صفحات/حدود عرض»):
///    حد عرض متدرج موحد — شحنة صفّاً وزر توسيع، والنقي
///    [listDisplayPage] بعقد الشريحة والبنية تحكم الاستعمال، والطباعة
///    والتصدير على العرض المطبَّق كاملاً بعقد F-166.
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

  group('س221: عزل النوع بجهة الأرشيف', () {
    testWidgets('المبيعات لا ترى أنواع الشراء إطلاقاً — والكل فيها '
        'المبيعات كلها لا القاعدة كلها', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester.pumpWidget(MaterialApp(
        home: InvoicesScreen(db: db, initialSide: InvoiceArchiveSide.sales),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('المبيعات كلها (البيع ومردوده)'));
      await tester.pumpAndSettle();

      // جهة المبيعات ببيعها ومردوده حصراً — لا شراء ولا مردود شراء.
      expect(find.text('فاتورة بيع'), findsOneWidget);
      expect(find.text('مردود بيع'), findsOneWidget);
      expect(find.text('فاتورة شراء'), findsNothing,
          reason: 'س221: العزل — جهة المبيعات لا ترى الشراء');
      expect(find.text('مردود شراء'), findsNothing,
          reason: 'س221: العزل — ولا مردود الشراء');
      expect(find.text('شرائي (الشراء ومردوده)'), findsNothing,
          reason: 'ولا مجمّع الجهة الأخرى');
      expect(find.text('كل الأنواع'), findsNothing,
          reason: '«الكل» بجهة المبيعات هي المبيعات كلها — لا نافذة '
              'على القاعدة كلها');
    });

    testWidgets('المشتريات لا ترى أنواع البيع إطلاقاً بنفس العزل',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester.pumpWidget(MaterialApp(
        home:
            InvoicesScreen(db: db, initialSide: InvoiceArchiveSide.purchases),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('المشتريات كلها (الشراء ومردوده)'));
      await tester.pumpAndSettle();

      expect(find.text('فاتورة شراء'), findsOneWidget);
      expect(find.text('مردود شراء'), findsOneWidget);
      expect(find.text('فاتورة بيع'), findsNothing,
          reason: 'س221: العزل — جهة المشتريات لا ترى البيع');
      expect(find.text('مردود بيع'), findsNothing);
      expect(find.text('بيعي (البيع ومردوده)'), findsNothing);
      expect(find.text('كل الأنواع'), findsNothing);
    });

    testWidgets('الدخول الحيادي (سجل الفواتير) جامع بألسنة معلّمة '
        'بالجهة فلا خيار بلا تمييز', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('كل الأنواع'));
      await tester.pumpAndSettle();

      // الخيارات السبعة بألسنتها المعلمة — مجموعتا الجهة فوق الأنواع
      // الفردية المعلومة بالجهة (س202 بالتمييز الجديد س221).
      expect(find.text('بيعي (البيع ومردوده)'), findsOneWidget);
      expect(find.text('شرائي (الشراء ومردوده)'), findsOneWidget);
      expect(find.text('فاتورة بيع — مبيعات'), findsOneWidget);
      expect(find.text('مردود بيع — مبيعات'), findsOneWidget);
      expect(find.text('فاتورة شراء — مشتريات'), findsOneWidget);
      expect(find.text('مردود شراء — مشتريات'), findsOneWidget);
    });
  });

  group('س221: حد العرض المتدرج (صفحات/حدود عرض — المساحة الموثقة)', () {
    test('النقي بعقد الشريحة — تحت الحد القائمة ذاتها وفوقه أول الحد '
        'حصراً', () {
      // تحت الحد فعلاً (50 < 60): القائمة ذاتها بلا نسخ — والدرس
      // الموثق بالجولة الحاكمة: الشحنة فوق الحد تعيد شريحة لا نفسها.
      final under = List<int>.generate(50, (i) => i);
      expect(listDisplayPage(under, limit: kListDisplayPageSize), same(under),
          reason: 'تحت الحد: القائمة ذاتها بلا نسخ');
      final all = List<int>.generate(150, (i) => i);
      final page = listDisplayPage(all, limit: 60);
      expect(page, hasLength(60));
      expect(page.first, 0);
      expect(page.last, 59, reason: 'أول الشحنة لا آخرها');
      expect(listDisplayPage(<int>[], limit: 60), isEmpty);
    });

    testWidgets('الأرشيف الطويل فوق الحد يبني أول شحنة وزر التوسيع '
        'بالعدّاد الباقي — والاستعلام كله محمّل (حد واجهة لا بيانات)',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final date = await cycleDate(db);
      final boxId = await firstBoxId(db);
      final warehouseId = await firstWarehouseId(db);
      final unitId = (await db.customSelect(
        'SELECT id FROM units ORDER BY id LIMIT 1',
      ).getSingle()).data['id'] as int;
      final oilId = (await db.customSelect(
        "SELECT id FROM items WHERE sku = 'Z-100'",
      ).getSingle()).data['id'] as int;
      // شحنة وثلث (80 مسودة بيع) فوق حد الـ60 — المسودات تُرى
      // بالأرشيف الافتراضي (بلا فلتر حالة) فلا ترحيل ولا مخزون.
      for (var i = 0; i < 80; i++) {
        await db.createInvoiceDraft(InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: date,
          cashBoxId: boxId,
          warehouseId: warehouseId,
          lines: [
            InvoiceLineDraft(
                itemId: oilId, unitId: unitId, qtyBase: 1,
                unitPriceMinor: 15000),
          ],
        ));
      }
      // منفذ عملاق كي تُبنى كل الصفوف وزر التوسيع — الشريحة البطيئة
      // تبني المرئي حصراً (درس الجولة الحاكمة الموثق: الزر خلف النافذة
      // غير مبنيّ أصلاً فلا يُجدَ بالفاحص).
      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // العدّاد من الاستعلام ذاته لا من افتراض — بذرة الدورة تحمل
      // فواتيرها فالشحنة فوق الحد بالباقي الفعلي (درس الجولة الحاكمة).
      final all = await db.invoicesListReport();
      expect(all.length, greaterThan(kListDisplayPageSize),
          reason: '80 مسودة فوق بذرة الدورة — فالشحنة فوق الحد فعلاً');
      final remaining = all.length - kListDisplayPageSize;

      // الشحنة الأولى ظاهرة وزر التوسيع بعدّاد الباقي بلسانه الموحد.
      expect(find.byType(ListTile), findsWidgets);
      expect(find.text('عرض المزيد — الباقي $remaining'), findsOneWidget);

      // والتوسيع يعرض البقية ويزيل الزر — الوجود كله متاح.
      await tester.tap(find.text('عرض المزيد — الباقي $remaining'));
      await tester.pumpAndSettle();
      expect(find.text('عرض المزيد — الباقي $remaining'), findsNothing,
          reason: 'الوجود كله تحت شحنة واحدة بعد التوسيع');
    });
  });
}
