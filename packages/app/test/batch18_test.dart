import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/invoices_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة (18) — عزل إدخال الفواتير بأزرار الأنواع الأربعة
/// (س-163/D-161 على معاينة س-162/D-160 المعتمدة بلفظ المالك
/// «اعتمد الدفعات الأربعة وقم بتنفيذ اقتراحك للفواتير» — س52):
/// البطاقة بالرئيسية بأزرارها الأربعة، وزر البيع يفتح النموذج بنوعه
/// المثبت بلا مبدّل نوع، والحفظ عبر الزر يكتب فاتورة بيع بتسلسل نوعها
/// (س-60/D-080) وتُرحَّل نقدياً مدفوعة (س-03/س-06).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-163: بطاقة الفواتير بالرئيسية بأزرار الأنواع الأربعة '
      'ولسانها «اختر النوع بالضغط — لا قائمة انتقاء» — وزر البيع يفتح '
      'النموذج بنوعه المثبت بلا مبدّل نوع', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // البطاقة بلسان المعاينة المعتمدة (س-162) وأزرارها الأربعة
    expect(find.text('اختر النوع بالضغط — لا قائمة انتقاء'), findsOneWidget);
    expect(find.text('فاتورة بيع'), findsOneWidget);
    expect(find.text('فاتورة شراء'), findsOneWidget);
    expect(find.text('مردود بيع'), findsOneWidget);
    expect(find.text('مردود شراء'), findsOneWidget);
    expect(find.text('سجل الفواتير'), findsOneWidget);

    // زر البيع يفتح النموذج بنوعه المثبت — لا مبدّل نوع بالنموذج
    await tester.tap(find.text('فاتورة بيع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(InvoiceEditScreen), findsOneWidget);
    expect(find.text('نوع الفاتورة'), findsNothing,
        reason: 'النوع من زر الدخول حصراً — لا انتقاء بالنموذج (س-163)');
    expect(find.text('النوع يُحدد من زر القائمة الرئيسية'), findsOneWidget);
  });

  testWidgets('س-163: زر البيع بالرئيسية ← نموذج بيع نقدي ← حفظ وترحيل — '
      'الفاتورة مخزونة بيعاً بتسلسل نوعها ومدفوعة (س-03/س-06)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // الدخول من الزر المعزول لا من نموذج موحد بانتقاء نوع
    await tester.tap(find.text('فاتورة بيع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('نوع الفاتورة'), findsNothing);

    // التاريخ من فترات الدورة
    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'), '2026-03-15');

    // الصنف الوحيد بالدورة — والسعر الافتراضي بسعر البيع (س-108)
    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('Z-100 زيت محلي').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // بيع نقدي 2×15,000 = 30,000 (النقدي افتراضياً والصندوق والمستودع
    // مختاران افتراضياً — عرف س-88)
    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية'), '2');
    await tester.enterText(
        find.widgetWithText(TextField, 'سعر الوحدة بوحدة صغرى'), '15000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // درس السرد الكسول (س35/س36): تمرير زر الحفظ إلى النافذة حصراً
    for (var i = 0;
        i < 10 && find.text('حفظ وترحيل').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الفاتورة الجديدة بيعٌ نقدي مرحّل مدفوع — عبر زر الرئيسية لا غير
    final inv = await db.customSelect(
      "SELECT state, total_doc_minor FROM invoices "
      "WHERE kind = 'sale' AND state <> 'draft'",
      variables: [],
    ).get();
    expect(inv.length, 2, reason: 'فاتورة الدورة الآجلة والجديدة عبر الزر');
    final newOne = inv
        .singleWhere((r) => (r.data['total_doc_minor'] as int) == 30000);
    expect(newOne.data['state'], 'paid',
        reason: 'البيع النقدي مدفوع فور ترحيله (س-03/س-06)');

    // وتسلسل النوع المستقل: البيع الجديد 2026/000002 بعد فاتورة الدورة
    // (التسمية المعروضة تركيب «فاتورة بيع» + الرقم — م-44/D-071)
    final seq = await db.customSelect(
      "SELECT number FROM invoices WHERE kind = 'sale' "
      "AND total_doc_minor = 30000",
      variables: [],
    ).getSingle();
    expect(seq.data['number'], '2026/000002',
        reason: 'التسلسل السنوي لكل نوع (س-60/D-080) — العزل بالترقيم');
  });
}
