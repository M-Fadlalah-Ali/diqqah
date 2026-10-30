import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';

import 'seed_cycle.dart';

/// اختبارات شاشة الفواتير — دفعة (6-ج) على السيناريوهات المعروضة
/// س-86..س-88 (06 §1-ط، D-094..D-096 معروض) بأرقام الدورة المعروفة
/// (ضخ 500,000 فشراء 10×10,000 آجل فبيع 6×15,000 آجل فقبض 50,000
/// فتسوية عجز 5,000).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle —
/// درس س22..س26 الموثق — والحكم بنصوص بطاقات فريدة لا textContaining
/// عائماً (درس س35: النص خلف الشاشة المدفوعة).
  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً — زر أسفل
  /// النموذج غير مبني خارج الشاشة فلا يُلمَس قبل تمريره إلى النافذة.
  Future<void> _scrollTo(WidgetTester tester, String label) async {
    for (var i = 0;
        i < 6 && find.text(label).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
  }

void main() {
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-86: قائمة الفواتير تعرض المرحّلة بأرقامها المعروفة '
      'وحالاتها المشتقة — والشراء آجلاً «مرحّلة» والبيع بعد قبض نصفه «جزئية»',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // أرقام الدورة المعروفة: كل نوع بتسلسله فكلاهما 2026/000001 (D-080)
    expect(find.textContaining('فاتورة شراء 2026/000001'), findsOneWidget);
    expect(find.textContaining('فاتورة بيع 2026/000001'), findsOneWidget);
    // الحالات المشتقة بالمطابقات حصراً (D-084): الشراء لم يُقبض ولم يُصرف
    // فمرحّلة، والبيع قُبض نصفه فجزئية
    expect(find.textContaining('مرحّلة'), findsWidgets);
    expect(find.textContaining('جزئية'), findsOneWidget);
  });

  testWidgets('س-87: حفظ فارغ يُرفض بمدقق البنية برسالته العربية — '
      'والمستند لا يُكتب', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await _scrollTo(tester, 'حفظ كمسودة');
    await tester.tap(find.text('حفظ كمسودة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // بطاقة الأخطاء أعلى القائمة — والتمرير إلى الزر فكّ إدراجها من
    // الشجرة الكسولة (درس س35/س36) فتُعاد إلى النافذة قبل فحصها
    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // مدقق البنية النقي يعرض رسالته كما هي — الكمية صفر في البند الأول
    expect(find.textContaining('الكمية «0» صفر أو سالبة'), findsWidgets);

    // ولا مستند كُتب
    final rows = await db.customSelect('SELECT COUNT(*) AS n FROM invoices')
        .getSingle();
    expect(rows.data['n'], 2, reason: 'المدقق منع الكتابة — قائمة الدورة فقط');
  });

  testWidgets('س-88: نموذج بيع نقدي مكتمل يُرحَّل — وقيد البيع ومدفوعته '
      'في القاعدة بأرقامه المعروفة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // النوع: من فاتورة شراء إلى فاتورة بيع — والقائمة المنبثقة بعناصرها
    await tester.tap(find.text('فاتورة شراء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('فاتورة بيع').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // التاريخ من فترات الدورة
    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'), '2026-03-15');

    // الصنف: قائمة الأصناف ثم البند الوحيد
    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Z-100 زيت محلي').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // الكمية والسعر — بيع نقدي 2×15,000 = 30,000 (النقدي افتراضياً
    // والصندوق والمستودع مختاران افتراضياً)
    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية'), '2');
    await tester.enterText(
        find.widgetWithText(TextField, 'سعر الوحدة بوحدة صغرى'), '15000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // القيد البيعي ثلاثي الأرجل والصندوق دائن بالبيع النقدي والمستند
    // «مدفوعة» فوراً (س-03/س-06: النقدية غير المردودة «paid» فوراً)
    final inv = await db.customSelect(
      "SELECT state, total_doc_minor FROM invoices "
      "WHERE kind = 'sale' AND state <> 'draft'",
      variables: [],
    ).get();
    expect(inv.length, 2, reason: 'فواتير الدورة الآجلة والنقدية الجديدة');
    final newOne = inv.singleWhere((r) =>
        (r.data['total_doc_minor'] as int) == 30000);
    expect(newOne.data['state'], 'paid');
  });
}
