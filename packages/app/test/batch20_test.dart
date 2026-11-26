import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/parties_screen.dart';
import 'package:diqqah_app/reports_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات الدفعة 20 — D-174 (قائمة بيضاء رقم الطرف) وF-166 (تصدير
/// CSV على كل تقرير).
///
/// D-174: الرقم الجديد أو المتغير خارج القائمة (حروف وأرقام و - _ .
/// حصراً — بلا فراغ بحسم المالك س64) يُرفض برسالة عربية تحمل الرقم،
/// والقائم غير المتغير يمر كما هو (الاستثناء الذاتي نمط D-153) فلا
/// يُحبس تعديل طرف قديم برقم ما قبل D-174، والنظافة D-170 تجرد العلامات
/// غير المرئية على حدود الحقل.
///
/// F-166: زر التصدير على التقرير بجوار الطباعة — والصفوف ذاتها التي
/// تُطبع هي التي تُصدَّر (صورة للعرض لا إعادة حساب) وباني CSV نقي
/// مختبراً في حزمة المجال (csv_test.dart). نمط القاعدة `inMemorySyncClose`
/// حصراً وضخّات محدودة لا pumpAndSettle (درس س22..س26 الموثق — تدفقات
/// drift الحية لا تستقر أبداً).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('D-174: تعديل اسم طرف قديم برقم ما قبل القائمة يمر '
      '(الاستثناء الذاتي D-153) — بلا رفض ولا تغيير للرقم', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final id = await db.insertParty(
        number: 'A 12',
        name: 'طرف قديم',
        kind: 'customer',
        defaultCurrencyId: 1);
    final party = await (db.select(db.parties)
          ..where((t) => t.id.equals(id)))
        .getSingle();

    // الضخ المباشر للبطاقة (نمط batch17 المجرب) — عضو واحد لكل اختبار
    // (درس الجولة 183: عضو ثانٍ بعد pop الجذر لا يُعتمد عليه).
    await tester.pumpWidget(
        MaterialApp(home: PartyEditScreen(db: db, existing: party)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'الاسم *'), 'طرف قديم معدل');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    final edited = await (db.select(db.parties)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(edited.name, 'طرف قديم معدل');
    expect(edited.number, 'A 12',
        reason: 'الاستثناء الذاتي: الرقم القائم قبل D-174 يبقى كما هو');
  });

  testWidgets('D-174: تغيير رقم طرف قائم لخارج القائمة يُرفض برسالته '
      'بلا كتابة — وإلى داخلها فيُحفظ', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final id = await db.insertParty(
        number: 'A 12',
        name: 'طرف قديم',
        kind: 'customer',
        defaultCurrencyId: 1);
    final party = await (db.select(db.parties)
          ..where((t) => t.id.equals(id)))
        .getSingle();

    await tester.pumpWidget(
        MaterialApp(home: PartyEditScreen(db: db, existing: party)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // ═══ الرفض أولًا قبل أي إشعار (درس الجولتين 163/164 الموثق) ═══
    await tester.enterText(
        find.widgetWithText(TextFormField, 'رقم الطرف (الأساس)'), 'B 13');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('يقبل الحروف والأرقام'), findsOneWidget,
        reason: 'رسالة D-174 تحمل الرقم المرفوض ولسان القائمة');
    final rejected = await (db.select(db.parties)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(rejected.number, 'A 12', reason: 'الرفض بلا كتابة');

    // ═══ الرقم إلى داخل القائمة فيُحفظ ═══
    await tester.enterText(
        find.widgetWithText(TextFormField, 'رقم الطرف (الأساس)'), 'B-13');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final saved = await (db.select(db.parties)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(saved.number, 'B-13');
  });

  testWidgets('D-174: الطرف الجديد برقم خارج القائمة يُرفض — '
      'وبداخله يُحفظ', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('إضافة طرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'رقم الطرف (الأساس)'), 'X Y');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'الاسم *'), 'عميل تجريبي');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('يقبل الحروف والأرقام'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'رقم الطرف (الأساس)'), 'X-Y');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('عميل تجريبي (X-Y)'), findsOneWidget);
  });

  testWidgets('F-166: زر «تصدير CSV» ظاهر على تقرير ميزان المراجعة '
      'بجوار «طباعة / PDF» — والوصل مضمون بالمصرّف (onCsv required)',
      (tester) async {
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

    expect(find.text('تصدير CSV'), findsOneWidget);
    expect(find.text('طباعة / PDF'), findsOneWidget);
  });
}
