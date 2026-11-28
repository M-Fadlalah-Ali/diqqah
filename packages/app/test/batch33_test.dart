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
    // س235: التطبيق الفوري بديبونس قصير بلا زر عرض.
    await tester.pump(const Duration(milliseconds: 600));
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
    // س235: التطبيق الفوري بديبونس قصير بلا زر عرض.
    await tester.pump(const Duration(milliseconds: 600));
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

  testWidgets('F-096: بندا القائمتين بقائمة التقارير بقسم القوائم '
      'المالية (س205 م09 — إعادة التنظيم بأقسامها)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // س227 (المرحلة صفر د4): البندان خلف بوابة القوائم المالية
    // (reports.financials) يراهما صاحب الجلسة المصرَّح لها — والمدير
    // النجمة يراهما — فالاختبار يدخل مديراً أولاً بعقد س205 كما كان
    // (بلا جلسة البندان مخفيان بعقد الفشل المغلق).
    if (await db.currentUserId() == null) {
      var userId = await db.hasAnyUser()
          ? (await db.select(db.appUsers).get()).first.id
          : await db.createManager(
              name: 'المالك', login: 'owner', passwordHash: 's:h');
      await db.setCurrentUserId(userId);
    }

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // س205 م09: القائمتان بأولهما بقسم القوائم المالية — ظاهرتان
    // دون سحبة (والدرس القديم «نمو بنهايتها» زال بإعادة التنظيم).
    expect(find.text('قائمة الدخل'), findsOneWidget);
    expect(find.text('الميزانية العمومية'), findsOneWidget);
  });
}
