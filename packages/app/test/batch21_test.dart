import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات الدفعة 21 — F-168: فلتر الاستلام على سجل الفواتير وتعميم
/// مربع «مستلم» لكل الأنواع وطباعة القائمة وتصديرها CSV.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق — تدفقات drift الحية لا تستقر أبداً)، وعضو
/// pumpWidget واحد لكل اختبار (درس الجولة 183)، ولا ضغط لزر مشاركة
/// حقيقي (درس print_service_test: أي IO حقيقي داخل testWidgets يعلق).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('F-168: فلتر الاستلام بالأرشيف — لسان الحالة بالصف '
      'والفلترة تحسم المكتمل من غير المستلم', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // البذرة تعيد رقم السنة لا معرف الفاتورة (نمط batch12 المجرب):
    // معرف فاتورة البيع الوحيدة يُقرأ من القاعدة.
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;
    final saleLines = await db.invoiceLines(saleId);
    await db.setInvoiceLineDelivered(saleLines.first.id, delivered: true);

    await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // القائمة تعرض لسانَي الحالتين: البيع مكتمل (سطره الوحيد مستلم)
    // والشراء غير مستلم — لسان القائمة هو ذاته لسان المطبوع والCSV.
    expect(find.textContaining('مكتمل الاستلام'), findsWidgets);
    expect(find.textContaining('غير مستلم'), findsWidgets);

    // ═══ الفلتر «مكتمل الاستلام» يبقي البيع ويُسقط الشراء ═══
    await tester.tap(find.text('الكل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('مكتمل الاستلام').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('عرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('فاتورة شراء'), findsNothing,
        reason: 'الشراء غير مستلم فلا يمر بفلتر مكتمل الاستلام');
    expect(find.textContaining('فاتورة بيع'), findsOneWidget);
  });

  testWidgets('F-168: مربع «مستلم» بفواتير الشراء بعد التعميم — '
      'بانتظار الاستلام ثم التحديد يحفظ فوراً على المرحّلة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final purchaseId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'purchase'",
    ).getSingle()).data['id'] as int;

    await tester.pumpWidget(MaterialApp(
        home: InvoiceDetailScreen(db: db, invoiceId: purchaseId)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Checkbox), findsOneWidget,
        reason: 'تعميم الدفعة 21: المربع بفواتير الشراء كما البيع');
    expect(find.text('بانتظار الاستلام'), findsOneWidget,
        reason: 'لسان الاستلام للأنواع غير البيعية (المنبع الموحد)');
    expect(find.text('المورد المسؤول'), findsNothing,
        reason: 'خانة المورد باقت للبيع حصراً بعهدها D-132');

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    final line = (await db.invoiceLines(purchaseId)).single;
    expect(line.delivered, isTrue,
        reason: 'التحديد يحفظ فوراً على المرحّلة (D-131)');
  });

  testWidgets('F-168: زرا «طباعة القائمة» و«تصدير CSV» بالشريط العلوي '
      'للأرشيف — والمطبوع والمصدَّر صورة العرض ذاتها', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('طباعة القائمة'), findsOneWidget);
    expect(find.byTooltip('تصدير CSV'), findsOneWidget);
  });
}
