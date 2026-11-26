import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/adaptive.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/main.dart' show DiqqahApp;
import 'package:diqqah_app/report_table.dart';
import 'package:diqqah_app/reports_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات س205 — الدفعة الثالثة من فحص الواجهات وفق M3 وبقية
/// الرابعة بأمر المالك الحرفي «تابع في م06 التكيفي ثم بقية الرابعة»:
/// - **م06 التكيفي لويندوز**: التوسيط التكيفي بعرضه الأقصى على
///   العريض والمرور الحرفي على الضيّق — ولا Scrollable ثانٍ ولا
///   إعادة بناء (درس الجولة #358).
/// - **م07 جداول التقارير**: الجدول الموحد بترويسته وخلاياه المنسجمة
///   وسلاسل صفوف المستند ذاتها (عرف F-166) ونقر الصف بعرفه القائم.
/// - **م09 تنظيم التقارير**: الأقسام الخمسة الدلالية وبنودها الثلاثة
///   عشر بلسانها.
/// - **م10 نموذج الفاتورة**: حقول الرأس المزدوجة بنمط التاريخ
///   والاستحقاق القائم.
/// - **م04 منتقي المردود**: مرشحو الأصل وبذرة النموذج بالمتبقي
///   بحساب المحرك ذاته.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('م06: التوسيط التكيفي', () {
    testWidgets('العريض فوق الحد يتوسّط بغلاف الحد الأقصى', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: DiqqahAdaptiveCenter(
            child: Container(key: const Key('probe'), width: 100, height: 40),
          ),
        ),
      ));

      expect(find.byType(Center), findsOneWidget);
      final constrained = tester.widget<ConstrainedBox>(find.ancestor(
        of: find.byKey(const Key('probe')),
        matching: find.byType(ConstrainedBox),
      ));
      expect(constrained.constraints.maxWidth, kDiqqahAdaptiveMaxWidth);
    });

    testWidgets('الضيّق وحدّه مرورٌ حرفي بلا غلاف', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(600, 800)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: DiqqahAdaptiveCenter(
            child: Container(key: const Key('probe'), width: 100, height: 40),
          ),
        ),
      ));

      // على الضيّق لا Center ولا ConstrainedBox من العامل ذاته.
      final centers = find.byType(Center).evaluate().length;
      expect(centers, 0);
      final constrained = find.ancestor(
        of: find.byKey(const Key('probe')),
        matching: find.byType(ConstrainedBox),
      );
      expect(constrained, findsNothing);
    });

    testWidgets('الهامش التكيفي: الضيّق أساسي والعريض نصف الفائض',
        (tester) async {
      double margin = -1;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(builder: (context) {
            margin = diqqahAdaptiveHorizontalMargin(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(margin, (1200 - kDiqqahAdaptiveMaxWidth) / 2);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(800, 800)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(builder: (context) {
            margin = diqqahAdaptiveHorizontalMargin(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(margin, kDiqqahAdaptiveBaseMargin);
    });

    testWidgets('الرئيسية على العريض تتوسّط — الشبكة لا تلتصق بالطرف',
        (tester) async {
      // س206 (تصويب الجولة #405): API السطح الموثق بنمط _bigView —
      // setSurfaceSize لم يحمل عرض 1600 إلى MediaQuery (بقي 800×600
      // فأخذ الغلاف مسار الضيّق والدليل كشفه زائل) — وtester.view
      // بدقة 1.0 هو الحاسم بنمط batch27/28/30.
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      final rect =
          tester.getRect(find.byKey(const Key('home_modules_grid')));
      expect(rect.width, lessThanOrEqualTo(kDiqqahAdaptiveMaxWidth));
      expect(rect.left, greaterThan(200),
          reason: 'م06: المحتوى موسَّط بعرضه الأقصى — لا امتداد من طرف لطرف');
    });
  });

  group('م07: الجدول الموحد', () {
    testWidgets('ترويسته وخلاياه ونقر الصف بعرفه', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: DiqqahReportTable(
              columns: const ['الصنف', 'الكمية', 'القيمة'],
              rows: const [
                ['Z-100 زيت', '4', '160,000'],
                ['Z-200 سكر', '2', '20,000'],
              ],
              numericColumns: const {1, 2},
              onRowTap: (index) => tapped = index,
            ),
          ),
        ),
      ));

      expect(find.text('الصنف'), findsOneWidget);
      expect(find.text('الكمية'), findsOneWidget);
      expect(find.text('القيمة'), findsOneWidget);
      expect(find.text('Z-100 زيت'), findsOneWidget);
      expect(find.text('160,000'), findsOneWidget);

      await tester.tap(find.text('Z-200 سكر'));
      expect(tapped, 1, reason: 'النقر بفهرس الصف — عرف كل اسم مدخلاً');
    });

    testWidgets('ميزان المراجعة جدولاً — الترويسة أعمدةً لا لساناً ملموماً',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('ميزان المراجعة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      // الترويسة بعمودها — النص التام لا سلسلة ملمومة بالسطر.
      expect(find.text('مدين'), findsOneWidget);
      expect(find.text('دائن'), findsOneWidget);
      expect(find.text('الرصيد'), findsOneWidget);
      // وخلايا الصفوف سلاسل صفوف المستند ذاتها (عرف F-166).
      expect(find.text('545,000'), findsOneWidget);
    });
  });

  group('م09: تنظيم التقارير', () {
    testWidgets('الأقسام الخمسة بنودها الثلاثة عشر بلسانها', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('القوائم المالية'), findsOneWidget);
      expect(find.text('الدفاتر والمطابقة'), findsOneWidget);
      expect(find.text('الصناديق والذمم'), findsOneWidget);
      // البدء برأس القائمة وميزانها — ثم نزول بالتمرير لأقسام ما بعد الطيّة.
      expect(find.text('ميزان المراجعة'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('المخزون والحركة'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('المخزون والحركة'), findsOneWidget);
      // البدء بنهاية القائمة ونهايتها — والوسطى مختبرة بدفعاتها
      // (batch15/31/33/34 بالوصول ذاته).
      await tester.scrollUntilVisible(
        find.text('الفترات والإقفال'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('الفترات والإقفال'), findsOneWidget);
    });
  });

  group('م10: حقول الرأس المزدوجة', () {
    testWidgets('المستودع والعملة بصف واحد بنمط التاريخ والاستحقاق',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final unitId = await db.insertUnit(name: 'قطعة');
      await db.insertItem(
          sku: 'Z-100',
          name: 'زيت محلي',
          kind: 'good',
          baseUnitId: unitId,
          purchasePriceMinor: 25000,
          salePriceMinor: 40000,
          priceCurrencyId: 1);

      await tester
          .pumpWidget(MaterialApp(home: InvoiceEditScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final warehouse = tester.getTopLeft(find
          .text('المستودع (للبضاعة — الخدمة بلا مستودع)'));
      final currency = tester.getTopLeft(find.text('عملة المستند'));
      expect(warehouse.dy, currency.dy,
          reason: 'م10: الحقلان بصف واحد — نمط التاريخ والاستحقاق القائم');
    });
  });

  group('م04: منتقي المردود', () {
    testWidgets('الورقة بمرشحي الأصل والبذرة تملأ النموذج بالمتبقي',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final saleId = (await db.customSelect(
        "SELECT id FROM invoices WHERE kind = 'sale' "
        "AND state <> 'draft' ORDER BY id LIMIT 1",
      ).getSingle()).data['id'] as int;

      await tester.pumpWidget(MaterialApp(
          home: InvoiceEditScreen(
              db: db, initialKind: InvoiceKind.saleReturn)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // زر المنتقي طرفي حقل الأصل — والورقة بمرشحي البيع المرحّل.
      await tester.tap(find.byTooltip('منتقي المردود'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('فاتورة $saleId'), findsOneWidget);
      await tester.tap(find.textContaining('فاتورة $saleId'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));

      // البذرة: معرف الأصل معبأ والسطر بالمتبقي كاملاً (بيع 6×15,000
      // بلا مردودات فمتبقيه 6) بسعر الأصل المرجعي.
      expect(find.text('$saleId'), findsOneWidget,
          reason: 'معرف الأصل حقل الإلزام معبأً من البذرة');
      expect(find.text('6'), findsOneWidget,
          reason: 'كمية السطر بالمتبقي — حساب المحرك ذاته');
      // س206 (تصويب الجولة #405): النقدية لا تُمس بعرف البذرة (خيار صاحب
      // النموذج موثقاً بس205) — فحقل الطرف بلسان «نقدي يطلب صندوقاً —
      // والآجل طرفاً» يظهر بالآجل حصراً فنُبدّل الدفع لنقرأ طرف الأصل.
      await tester.tap(find.text('نقدي'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('آجل').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('عميل الأمل'), findsWidgets,
          reason: 'طرف الأصل في منتقي الطرف');
    });

    test('البذرة النقية بالمتبقي — الموفى لا يُبذر', () {
      final seed = InvoiceReturnSeed(
        originalId: 7,
        originalKind: InvoiceKind.sale,
        currencyId: 1,
        lines: [
          const InvoiceReturnSeedLine(
              itemId: 1,
              itemSku: 'Z-100',
              itemName: 'زيت',
              origQtyBase: 10,
              returnedQtyBase: 4,
              remainingQtyBase: 6,
              unitPriceMinor: 15000),
          const InvoiceReturnSeedLine(
              itemId: 2,
              itemSku: 'Z-200',
              itemName: 'سكر',
              origQtyBase: 5,
              returnedQtyBase: 5,
              remainingQtyBase: 0,
              unitPriceMinor: 9000),
        ],
      );
      final seeded = [
        for (final l in seed.lines)
          if (l.remainingQtyBase > 0) l,
      ];
      expect(seeded.length, 1);
      expect(seeded.single.remainingQtyBase, 6);
      expect(InvoiceKind.saleReturn.expectedOriginalKind, InvoiceKind.sale);
      expect(InvoiceKind.purchaseReturn.expectedOriginalKind,
          InvoiceKind.purchase);
      expect(InvoiceKind.sale.expectedOriginalKind, isNull);
    });
  });
}
