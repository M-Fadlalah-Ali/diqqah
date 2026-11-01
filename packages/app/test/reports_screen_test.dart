import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/reports_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات شاشة التقارير — دفعة م1 (6-ب) على السيناريوهات المعروضة
/// س-79..س-84 (06 §1-ح) بقرارات D-091..D-093، وبأرقام الدورة المعروفة
/// نفسها من reports_flow_test (ضخ 500,000 فشراء 100,000 فبيع 90,000
/// فقبض 50,000 فعجز 5,000).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle —
/// درس س22..س26 الموثق: المؤشر الوامض وتدفقات drift يمنعان الاستقرار
/// أبداً، والإغلاق عادي في الteardown بلا رقصة ضخّات.
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-79/س-80: قائمة التقارير تفتح ميزان المراجعة بمجموعيه '
      '805,000/805,000 وبشارة التوازن وبأرصدة الدورة المعروفة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // الوحدة الست والإقفال ظاهرة بقائمة واحدة
    expect(find.text('ميزان المراجعة'), findsOneWidget);
    expect(find.text('تقرير المشتريات'), findsOneWidget);
    expect(find.text('الفترات والإقفال'), findsOneWidget);

    await tester.tap(find.text('ميزان المراجعة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المجمعان كما هما (F-068) — نص واحد يحمل الرقمين معاً
    expect(find.textContaining('805,000'), findsOneWidget);
    expect(find.textContaining('الميزان متوازن'), findsOneWidget);
    // أرصدة الصفوف المعروفة: الصندوق 545,000 والعملاء 40,000 والمخزون
    // 40,000 وموردون 100,000 ورأس المال 500,000
    expect(find.textContaining('1111'), findsOneWidget);
    expect(find.textContaining('545,000'), findsOneWidget);
    expect(find.textContaining('40,000'), findsNWidgets(2));
    expect(find.textContaining('100,000'), findsNWidgets(3),
        reason: 'مدين المخزون ودائن الموردين ورصيدهما');
    expect(find.textContaining('500,000'), findsNWidgets(2),
        reason: 'دائن رأس المال ورصيده');
    // والحساب الغائب لا صف له (لا 42 ولا 58 في هذه الدورة)
    expect(find.textContaining('58 '), findsNothing);
  });

  testWidgets('س-81: تقرير الصناديق برصيد 545,000 وعمله وحسابه الورقي',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('تقرير الصناديق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('545,000'), findsOneWidget,
        reason: '500,000 ضخ + 50,000 قبض − 5,000 عجز');
    expect(find.textContaining('1111'), findsOneWidget);
    expect(find.textContaining('SYP'), findsOneWidget);
    expect(find.text('حساب 1111 · SYP'), findsOneWidget,
        reason: 'الصندوق نشط — لا لاحقة « — معطل» في بطاقته');
  });

  testWidgets('س-81: الذمم بالاتجاهين — «هم يدينون لنا» 40,000 و«نحن '
      'مدينون لهم» 100,000', (tester) async {
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

    expect(find.text('عميل الأمل'), findsOneWidget);
    expect(find.text('هم يدينون لنا'), findsOneWidget);
    expect(find.textContaining('40,000'), findsOneWidget);
    expect(find.text('مورد الشرق'), findsOneWidget);
    expect(find.text('نحن مدينون لهم'), findsOneWidget);
    expect(find.textContaining('100,000'), findsOneWidget);
  });

  testWidgets('س-82: المخزون 4×40,000 ومتوسط العرض 10,000', (tester) async {
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

    expect(find.textContaining('Z-100'), findsOneWidget);
    expect(find.textContaining('4 × 40,000'), findsOneWidget);
    expect(find.textContaining('10,000'), findsOneWidget,
        reason: 'المتوسط عرضاً بالرسة المعتمدة');
  });

  testWidgets('س-83: الحركة البيعية بمدى صحيح تعطي 6×90,000، والمدى '
      'المقلوب رفضه قبل القاعدة، والمدى الغائب رسالة لا صمت', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final year = await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('مبيعات وحركة الأصناف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // مدى صحيح يشمل مارس
    await tester.enterText(
        find.byType(TextField).at(0), '$year-01-01');
    await tester.enterText(
        find.byType(TextField).at(1), '$year-12-31');
    await tester.tap(find.text('عرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Z-100'), findsOneWidget);
    expect(find.textContaining('بيع 6 × 90,000'), findsOneWidget);
    expect(find.textContaining('الصافي 6 × 90,000'), findsOneWidget);

    // المدى المقلوب يُرفض قبل لمس القاعدة برسالة مدقق المجال
    await tester.enterText(
        find.byType(TextField).at(0), '$year-05-10');
    await tester.enterText(
        find.byType(TextField).at(1), '$year-05-01');
    await tester.tap(find.text('عرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('مقلوب'), findsOneWidget);

    // مدى غائب: صفر صفوف برسالة لا خطأ (س-75)
    await tester.enterText(
        find.byType(TextField).at(0), '$year-01-01');
    await tester.enterText(
        find.byType(TextField).at(1), '$year-01-02');
    await tester.tap(find.text('عرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا حركة في هذا المدى'), findsOneWidget);
  });

  testWidgets('س-84: تقرير المشتريات المستقل — شراء 10×100,000 بصافيه',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final year = await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('تقرير المشتريات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.byType(TextField).at(0), '$year-01-01');
    await tester.enterText(
        find.byType(TextField).at(1), '$year-12-31');
    await tester.tap(find.text('عرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Z-100'), findsOneWidget);
    expect(find.textContaining('شراء 10 × 100,000'), findsOneWidget);
    expect(find.textContaining('الصافي 10 × 100,000'), findsOneWidget);
    expect(find.textContaining('مردود 0'), findsOneWidget,
        reason: 'لا مردود شراء في هذه الدورة — العمود ظاهر بصفره');
  });
}
