// اختبارات س235 — توحيد النمط الفوري على الشاشات (بكلمة المالك «نعم
// احذف زر العرض وطبق النمط الجديد لتوحيد تجربة المستخدم»): شريط المدى
// الفوري الموحد DiqqahInstantRangeBar بسجل الفواتير والتقارير
// (الدخل واليومية والحركة) والسندات — والميزانية بحقلها الأحادي
// الفوري — وقرار القصير ISO موثق D-238.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/date_picker.dart';
import 'package:diqqah_app/reports_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  group('س235: التوحيد — الشريط الفوري بلا زر عرض على الشاشات', () {
    testWidgets('قائمة الدخل: الخمسة بسطورها الصغيرة — و«هذا العام» يطبق '
        'فوراً فيظهر دخل الأرضية المعروفة', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: IncomeStatementView(db: db)));
      await settle(tester);

      // زر عرض رُفع — والخمسة حاضرون بسطورهم الصغيرة الفعلية.
      expect(find.text('عرض'), findsNothing,
          reason: 'التطبيق الفوري بلا زر عرض (توحيد النمط بس235)');
      for (final label in [
        'اليوم',
        'هذا الشهر',
        'الشهر الماضي',
        'هذا العام',
        'السنة السابقة',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final now = DateTime.now();
      expect(find.text('${now.year - 1}'), findsOneWidget,
          reason: 'سطر السنة السابقة الصغير برقمه وحده');

      // «هذا العام» يطبق فوراً: سنة البذور هي سنة اليوم فالدخل ظاهر.
      await tester.tap(find.text('هذا العام'));
      await settle(tester);
      expect(
          find.descendant(
              of: find.byType(FilledButton),
              matching: find.text('هذا العام')),
          findsOneWidget,
          reason: 'تلوين المختار');
      expect(find.textContaining('25,000'), findsOneWidget,
          reason: 'صافي الأرضية المعروفة يظهر بمدى سنة البذور');
    });

    testWidgets('السندات: التبويب الأول على الشريط الفوري — و«الشهر '
        'الماضي» يعيد القائمة فلا سند آذار فيه', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
      await settle(tester);

      expect(find.text('عرض'), findsNothing);
      expect(find.text('السنة السابقة'), findsOneWidget);

      // الشهر الماضي يطبق فوراً — سند البذرة بآذار خارج تشرين الثاني.
      final range =
          diqqahRangeShortcutDates(DiqqahRangePreset.lastMonth);
      await tester.tap(find.text('الشهر الماضي'));
      await settle(tester);
      final from = tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'من (YYYY-MM-DD)'))
          .controller!
          .text;
      expect(from, range.$1, reason: 'الشريط الموحد يملأ الحقلين');
      expect(find.textContaining('سند قبض 26000001'), findsNothing,
          reason: 'القائمة أُعيدت بمدى الشهر الماضي فوراً');
    });

    testWidgets('الميزانية: الحقل الأحادي فوري بديبونس قصير — ولا أزرار '
        'الخمسة (ليس مدى)', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: BalanceSheetView(db: db)));
      await settle(tester);

      // ليس مدى فلا أزرار الخمسة — وزر العرض رُفع.
      expect(find.text('عرض'), findsNothing);
      expect(find.text('هذا العام'), findsNothing);
      expect(find.text('اليوم'), findsNothing);

      // الكتابة تُطبَّق بتأخير قصير — والمدى المعروف يظهر الميزانية.
      final now = DateTime.now();
      await tester.enterText(find.byType(TextField).at(0),
          '${now.year}-12-31');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      // وسم القسم المثبت بنمط batch33 (الإجماليات تحت طية القائمة
      // الكسولة فسطر القسم الظاهر أوضح شاهد على إعادة التحميل).
      expect(find.textContaining('الأصول 625,000'), findsOneWidget,
          reason: 'الحقل الأحادي فوري بديبونس قصير بلا ضغطة');
    });

    testWidgets('الشريط على الضيّق معزولاً: تمرير أفقي ولا فيض — '
        'والخمسة كلها داخل التمرير', (tester) async {
      // س235: الشريط وحده على سطح 360 — (تخطيط تقرير الدخل الكامل على
      // الضيق يفيض من قبل هذه الدفعة فليس موضعها؛ موضع الشريط حده).
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final from = TextEditingController();
      final to = TextEditingController();
      addTearDown(from.dispose);
      addTearDown(to.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: DiqqahInstantRangeBar(
                from: from, to: to, onReload: () {}),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'لا فيض على الضيق — الأزرار تمر أفقياً');
      expect(find.byType(SingleChildScrollView), findsOneWidget,
          reason: 'التمرير الأفقي عند الضيق حصراً (عقد D-234/2 بس235)');
      expect(
          find.descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.text('السنة السابقة')),
          findsOneWidget);
    });
  });
}
