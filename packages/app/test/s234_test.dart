// اختبارات س234 — المرحلة ب (0.286) من خارطة الطريق الخماسية: سجل
// الفواتير بأزراره الثلاثة لكل سجل (D-234/1) وأزرار تاريخه الخمسة
// بسطرها الصغير الفعلي (D-234/2) وفلاتره الثلاثة بسطر واحد بالتطبيق
// الفوري ومسح الفلاتر (D-234/3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/calendar_prefs.dart';
import 'package:diqqah_app/date_picker.dart';
import 'package:diqqah_app/invoices_screen.dart';

import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('س234/D-234: النقي — السنة السابقة والسطر الصغير', () {
    test('السنة السابقة كاملة: أولها إلى آخرها', () {
      final (f, t) = diqqahRangeShortcutDates(
        DiqqahRangePreset.previousYear,
        today: DateTime(2026, 11, 28),
      );
      expect(f, '2025-01-01');
      expect(t, '2025-12-31');
    });

    test('الشهر السابق مفعّل دائماً — قوس السنة بيناير', () {
      // يناير الجديد: الشهر الماضي كانون الأول السابق كاملاً.
      final (f, t) = diqqahRangeShortcutDates(
        DiqqahRangePreset.lastMonth,
        today: DateTime(2027, 1, 15),
      );
      expect(f, '2026-12-01');
      expect(t, '2026-12-31');
    });

    test('السطر الصغير: بلا سنة قرب الشهرين وسنوات الزوج الأخير وحدها',
        () {
      final today = DateTime(2026, 11, 28);
      expect(
          diqqahPresetSmallLine(DiqqahRangePreset.today, today: today),
          '28 نوفمبر');
      expect(
          diqqahPresetSmallLine(DiqqahRangePreset.thisMonth, today: today),
          'نوفمبر');
      expect(
          diqqahPresetSmallLine(DiqqahRangePreset.lastMonth, today: today),
          'أكتوبر');
      expect(
          diqqahPresetSmallLine(DiqqahRangePreset.thisYear, today: today),
          '2026');
      expect(
          diqqahPresetSmallLine(DiqqahRangePreset.previousYear,
              today: today),
          '2025');
    });

    test('السطر الصغير بالشامية المختارة — ويناير بلغة كانون الأول', () {
      expect(
          diqqahPresetSmallLine(DiqqahRangePreset.thisMonth,
              today: DateTime(2026, 11, 28),
              names: DiqqahMonthNames.shami),
          'تشرين الثاني');
      expect(
          diqqahPresetSmallLine(DiqqahRangePreset.lastMonth,
              today: DateTime(2027, 1, 15),
              names: DiqqahMonthNames.shami),
          'كانون الأول');
    });
  });

  group('س234/D-234: الواجهة — الخمسة والتطبيق الفوري والمسح والأزرار', () {
    /// بذرة فاتورة شراء مرحّلة بتاريخ معطى — نمط seed_cycle محلياً
    /// (دفعة 6-ب) بقائمة الواجهة: الشراء لا يحتاج رصيداً فحارس
    /// «منع السالب» يمر (والبيع في الأرضية المعروفة يسبقه شراء).
    Future<int> seedPurchase(DiqqahDatabase db, String dateText) async {
      // اسم فريد بتاريخ الفاتورة — اختبار الفاتورتين يبذر مرتين.
      final unitId = await db.insertUnit(name: 'قطعة $dateText');
      final itemId = await db.insertItem(
        sku: 'S-234-$dateText',
        name: 'صنف س234',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1,
      );
      final partyId = await db.insertParty(
        number: '234-$dateText',
        name: 'طرف س234',
        kind: 'both',
        defaultCurrencyId: 1,
      );
      final warehouseId = (await db.customSelect(
        'SELECT id FROM warehouses ORDER BY id LIMIT 1',
      ).getSingle()).data['id'] as int;
      final id = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: dateText,
        partyId: partyId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: itemId, unitId: unitId, qtyBase: 1, unitPriceMinor: 2000),
        ],
      ));
      await db.postInvoice(id);
      return id;
    }

    String iso(DateTime x) =>
        DateTime(x.year, x.month, x.day).toIso8601String().substring(0, 10);

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('أزرار التاريخ الخمسة بسطر واحد بسطورها الصغيرة — وزر عرض '
        'رُفع ومسح الفلاتر حاضر', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedPurchase(db, iso(DateTime.now()));

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await settle(tester);

      for (final label in [
        'اليوم',
        'هذا الشهر',
        'الشهر الماضي',
        'هذا العام',
        'السنة السابقة',
      ]) {
        expect(find.text(label), findsOneWidget,
            reason: 'زر $label حاضر بأزرار التاريخ الخمسة');
      }
      // السطور الصغيرة الفعلية فوق الأزرار — بأسماء الأشهر الدولية
      // الافتراضية (خيار D-231) وبلا سنة قرب الشهرين.
      final now = DateTime.now();
      expect(find.text('${now.day} ${diqqahMonthName(now.month)}'),
          findsOneWidget);
      expect(find.text(diqqahMonthName(now.month)), findsWidgets);
      expect(find.text(diqqahMonthName(now.month == 1 ? 12 : now.month - 1)),
          findsOneWidget);
      expect(find.text('${now.year}'), findsOneWidget);
      expect(find.text('${now.year - 1}'), findsOneWidget);
      // زر عرض رُفع — لا نص «عرض» بالشاشة أصلاً.
      expect(find.text('عرض'), findsNothing,
          reason: 'التطبيق الفوري بلا زر عرض (D-234/3)');
      expect(find.byKey(const ValueKey('invoices_clear_filters')),
          findsOneWidget);
    });

    testWidgets('التطبيق الفوري للاختصار: الحقلان يمتلئان والقائمة تصفّي '
        'والمختار يتلون — والتحرير اليدوي يفرغ التلوين', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedPurchase(db, iso(DateTime.now()));
      final lastMonthRange =
          diqqahRangeShortcutDates(DiqqahRangePreset.lastMonth);
      await seedPurchase(db, lastMonthRange.$1);

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await settle(tester);
      expect(find.textContaining('فاتورة شراء'), findsNWidgets(2));

      // الضغط على «الشهر الماضي» يطبق فوراً: يملا الحقلين ويحمل.
      await tester.tap(find.text('الشهر الماضي'));
      await settle(tester);
      // القيمة تُقرأ بالمتحكم — القيمة ليست Textاً والوسم هو النص.
      final fromField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'من (YYYY-MM-DD)'));
      final toField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'));
      expect(fromField.controller!.text, lastMonthRange.$1,
          reason: 'الحقل «من» امتلأ بحد الشهر الماضي');
      expect(toField.controller!.text, lastMonthRange.$2);
      expect(find.textContaining('فاتورة شراء'), findsOneWidget,
          reason: 'فاتورة الشهر الماضي وحدها في المدى');
      // المختار يتلون: الفاتورة الممتلئة تحمل نصه.
      expect(
          find.descendant(
              of: find.byType(FilledButton),
              matching: find.text('الشهر الماضي')),
          findsOneWidget,
          reason: 'تلوين المحدد (D-234/2)');

      // التحرير اليدوي يفرغ التلوين بتأخير قصير — والزوج يُفرَّغ معاً
      // (كلاهما أو لا: الناقص انتظار كتابة لا تطبيق).
      await tester.enterText(
          find.widgetWithText(TextField, 'من (YYYY-MM-DD)'), '');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(
          find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'), '');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(FilledButton),
              matching: find.text('الشهر الماضي')),
          findsNothing,
          reason: 'التحرير اليدوي يفرغ التلوين');
      expect(find.textContaining('فاتورة شراء'), findsNWidgets(2),
          reason: 'بلا مدى: القائمة كلها');
    });

    testWidgets('البحث بتأخير قصير بلا ضغطة — ثم مسح الفلاتر يرجع '
        'البداية النظيفة', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedPurchase(db, iso(DateTime.now()));

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await settle(tester);

      // قبل التأخير القصير لا يطبق شيء (القاعدة الزمنية بثوبها الجديد).
      await tester.enterText(
          find.widgetWithText(TextField, 'بحث بالطرف أو الرقم'), 'طرف');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('فاتورة شراء'), findsOneWidget);

      // مسح الفلاتر من البداية النظيفة — بضغطة واحدة.
      await tester.tap(find.byKey(const ValueKey('invoices_clear_filters')));
      await settle(tester);
      expect(find.widgetWithText(TextField, 'بحث بالطرف أو الرقم'),
          findsOneWidget);
      final search = tester.widget<TextField>(
          find.widgetWithText(TextField, 'بحث بالطرف أو الرقم'));
      expect(search.controller!.text, '',
          reason: 'المسح يفرغ البحث (والديبونس ملغى فلا عودة متأخرة)');
      expect(find.textContaining('فاتورة شراء'), findsOneWidget);
    });

    testWidgets('الأزرار الثلاثة لكل سجل بمفاتيحها المستقلة — والافتراضي '
        'الزر الأول بنقر الصف', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final id = await seedPurchase(db, iso(DateTime.now()));

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await settle(tester);

      // القائمة السياقية الموروثة رُفعت — والأزرار الثلاثة بمفاتيحها.
      expect(find.byKey(ValueKey('invoice_view_$id')), findsOneWidget);
      expect(find.byKey(ValueKey('invoice_print_$id')), findsOneWidget);
      expect(find.byKey(ValueKey('invoice_copy_$id')), findsOneWidget);

      // الافتراضي الزر الأول: نقر الصف يفتح التفاصيل — وزر العرض كذلك.
      await tester.tap(find.textContaining('فاتورة شراء'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceDetailScreen), findsOneWidget,
          reason: 'نقر الصف عرض التفاصيل (الافتراضي الزر الأول)');
    });
  });
}
