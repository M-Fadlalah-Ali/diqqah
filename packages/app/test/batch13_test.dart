import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/reports_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة (13) الروابط التفرعية (س-143..س-147/D-135..D-137):
/// الحساب في الميزان يفتح كشف حسابه المطابق لصفه، واسم الصنف في
/// المخزون يفتح ورقة الصنف منها حركة المادة، والطرف في الذمم يفتح
/// ورقته منها كشف حسابه المطابق لصف الذمم.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-146/D-137: النقر على الحساب في ميزان المراجعة يفتح كشف '
      'حسابه — وملخصه يطابق صف الميزان (40,000 للعملاء)', (tester) async {
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

    // صف العملاء 112 — النقر عليه يفتح الكشف
    await tester.tap(find.textContaining('112 '));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('كشف حساب'), findsOneWidget);
    // ملخص الكشف يطابق صف الميزان: مدين 90,000 ودائن 50,000 ورصيد 40,000
    // — بنصوص شاشة الكشف الفريدة (شاشة الميزان أسفل التكديس تبقى
    // مرئية أثناء انتقال الدفع فنصوصها العامة قد تُعدّ معروضة)
    expect(find.textContaining('مجموع المدين 90,000'), findsOneWidget);
    expect(find.textContaining('الرصيد النهائي 40,000'), findsOneWidget);
  });

  testWidgets('س-144/D-136: اسم الصنف في تقرير المخزون يفتح ورقة الصنف '
      'ومنها «حركة المادة» — دخول الشراء وخروج البيع', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('تقرير المخزون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Z-100 زيت محلي'), findsOneWidget);
    await tester.tap(find.textContaining('Z-100 زيت محلي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // ورقة الصنف بخياراتها الخمسة (س-144)
    expect(find.text('بطاقة الصنف — فتح للتعديل'), findsOneWidget);
    expect(find.text('حركة المادة'), findsOneWidget);
    expect(find.text('مبيعاته — معزولة على الصنف'), findsOneWidget);
    expect(find.text('مشترياته — معزولة على الصنف'), findsOneWidget);
    expect(find.text('رصيده في المخزون'), findsOneWidget);

    await tester.tap(find.text('حركة المادة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('حركة المادة'), findsWidgets);
    expect(find.textContaining('دخول 10'), findsOneWidget);
    expect(find.textContaining('خروج 6'), findsOneWidget);
  });

  testWidgets('س-147: الطرف في الذمم يفتح ورقته ومنها كشف حسابه المطابق '
      'لصف الذمم (40,000 هم يدينون)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('الذمم المدينة والدائنة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('عميل الأمل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // ورقة الطرف بخياراتها (س-147)
    expect(find.text('بطاقة الطرف — فتح للتعديل'), findsOneWidget);
    expect(find.text('فواتيره'), findsOneWidget);
    expect(find.text('سنداته'), findsOneWidget);
    expect(find.text('كشف حسابه'), findsOneWidget);

    await tester.tap(find.text('كشف حسابه'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('كشف حساب الطرف'), findsOneWidget);
    expect(find.textContaining('الصافي النهائي 40,000'), findsOneWidget);
  });
}
