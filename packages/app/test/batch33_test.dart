import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/reports_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات الدفعة 33 (عاشرة م2) — القوائم المالية الأساسية (F-096):
/// بندا «قائمة الدخل» و«الميزانية العمومية» بشاشتهما وبأرقام الدورة
/// المعروفة، والتصدير والطباعة بصفوف العرض ذاتها (F-166).
///
/// الدورة المعروفة (seedKnownCycle): ضخ 500,000 فشراء 100,000 فبيع
/// آجل 90,000 فقبض 50,000 فعجز 5,000 — النتيجة ربح 25,000 والميزانية
/// أصول 625,000 = خصوم 100,000 + حقوق 525,000.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  Future<int> seededYear(DiqqahDatabase db) async {
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    return int.parse(yearRows.single.data['name'] as String);
  }

  testWidgets('F-096: قائمة الدخل بمدى سنة البذور تعرض الإيراد والمصروفين '
      'وصافي الربح 25,000 بالفوتر', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final year = await seededYear(db);

    await tester.pumpWidget(MaterialApp(home: IncomeStatementView(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // المدى الافتراضي سنة اليوم — نضبطه لسنة البذور حصراً (درس
    // س-111/D-108: تاريخ اليوم خارج دورة البذور فالتقرير فارغ أصلاً).
    await tester.enterText(
        find.widgetWithText(TextField, 'من (YYYY-MM-DD)'),
        '$year-01-01');
    await tester.enterText(
        find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'),
        '$year-12-31');
    await tester.pump();
    await tester.tap(find.text('عرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('411'), findsOneWidget);
    expect(find.textContaining('صافي النتيجة'), findsOneWidget);
    expect(find.textContaining('ربح 25,000'), findsOneWidget);
    // التصدير والطباعة بصفوف العرض ذاتها (F-166).
    expect(find.text('تصدير CSV'), findsOneWidget);
    expect(find.text('طباعة / PDF'), findsOneWidget);
  });

  testWidgets('F-096: الميزانية العمومية إلى نهاية سنة البذور متوازنة '
      'بأرقام الدورة: أصول 625,000 وخصوم 100,000 وحقوق 525,000',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final year = await seededYear(db);

    await tester.pumpWidget(MaterialApp(home: BalanceSheetView(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextField, 'إلى تاريخ (YYYY-MM-DD)'),
        '$year-12-31');
    await tester.pump();
    await tester.tap(find.text('عرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('المعادلة متوازنة'), findsOneWidget);
    expect(find.textContaining('الأصول 625,000'), findsOneWidget);
    expect(find.textContaining('الخصوم 100,000'), findsOneWidget);
    // النتيجة الجارية سطراً ظاهراً قبل الإقفال — تحت طية السرد الكسول
    // فسحبٌ هادئ يبنيه أولاً (درس س35/س36 الموثق).
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('نتيجة الفترة الجارية'), findsOneWidget);
  });

  testWidgets('F-096: بندا القائمتين بقائمة التقارير بعد البنود القائمة '
      '(نمو بنهايتها — درس السرد الكسول الموثق)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('قائمة الدخل'), findsOneWidget);
    expect(find.text('الميزانية العمومية'), findsOneWidget);
  });
}
