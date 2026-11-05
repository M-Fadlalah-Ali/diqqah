import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/reports_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات الدفعة 31 (ثامنة م2) — ربط المخزون بالدفتر: بند «مطابقة
/// دفتر المخزون» بشاشته وشارة الثابت (07 §3.1/D-067/F-178).
///
/// الدورة المعروفة (seedKnownCycle): ضخ 500,000 فشراء 100,000 فبيع
/// 90,000 فقبض 50,000 فعجز 5,000 — المخزون 40,000 قيوداً وحركات معاً.
/// نمط القاعدة `inMemorySyncClose` وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق).
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('الدفعة 31: قائمة التقارير تحمل بند المطابقة ويفتح شاشته '
      'بشارة الثابت المتطابق وأرقام الدورة المعروفة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // البند الجديد خلف القائمة القائمة (نمو بنهايتها — درس س35/س36
    // الموثق: السرد الكسول لا يبني البعيد فسحبٌ هادئة تكشفه أولاً).
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('مطابقة دفتر المخزون'), findsOneWidget);

    await tester.tap(find.text('مطابقة دفتر المخزون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // شارة الثابت (F-178) بالأرقام: القيود 40,000 والمخزون 40,000 —
    // والسلسلة الفريدة للبطاقة لا تشترك مع نص الصف («بالقيود»).
    expect(find.textContaining('المطابقة صحيحة'), findsOneWidget);
    expect(find.textContaining('المخزون: 40,000'), findsOneWidget);
    // الصف المطابق بعِلمه — لا ميل ولا تحذير.
    expect(find.textContaining('مطابق'), findsWidgets);
    expect(find.textContaining('ميل'), findsNothing);
  });

  testWidgets('الدفعة 31: شاشة المطابقة تقرأ مباشرة من القاعدة وتعرض '
      'الإجماليين أسفل الأفعال بصفوف العرض ذاتها (F-166)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
      home: LedgerReconView(db: db),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بطاقة الثابت والصفان: أزرار التصدير والطباعة ظاهرة (لا تقرير
    // بلا زر CSV) والإجماليان ببطاقة الشارة لا صفٍّ ثانٍ.
    expect(find.text('تصدير CSV'), findsOneWidget);
    expect(find.text('طباعة / PDF'), findsOneWidget);
    expect(find.textContaining('إجمالي بالقيود'), findsNothing,
        reason: 'الإجماليان بالشارة نصاً مقحماً لا footer مستقل بالقائمة');
    expect(find.textContaining('المطابقة صحيحة'), findsOneWidget);
  });
}
