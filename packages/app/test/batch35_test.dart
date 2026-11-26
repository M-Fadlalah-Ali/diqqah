/// س125 — تفعيل الذمم والدفتر المحاسبي — اختبارات الواجهة بأمر المالك
/// الحرفي «بعد الانتهاء نتوجه إلى تفعيل الذمم والدفتر المحاسبي» بعد
/// إغلاق b36 بأمره «قم ببناء b36».
///
/// البلاطتان خرجتا من مفرغهما بالهيكلية (المعطلات 3←1: المزامنة حصراً)
/// وشاشتان جديدتان بقراءة خالصة فوق البنية المنجزة م1 — لا ترحيلة
/// ولا مساس بالقلب المحاسبي (عين روح الطلبات س121/س123).
///
/// القراءة فوق الدورة المعروفة من seedKnownCycle (أرقام reports_flow_test
/// الموثقة: ضخ 500,000 فشراء 100,000 فبيع 90,000 فقبض 50,000 فعجز 5,000)
/// — نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// — درس س22..س26 الموثق: المؤشر الوامض وتدفقات drift يمنعان الاستقرار
/// أبداً، والإغلاق عادي في الteardown بلا رقصة ضخّات.
library;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/ledger_screen.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/receivables_screen.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('س125: شاشة الذمم تعرض أرصدة الأطراف بالمدينة أولاً بلسان '
      'الس-73 الموثق — والضغط على الطرف يفتح كشف حسابه بخلاصته',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
      MaterialApp(home: ReceivablesScreen(db: db)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // التبويبان ظاهران بلسانهما
    expect(find.text('أرصدة الأطراف'), findsOneWidget);
    expect(find.text('أعمار الذمم'), findsOneWidget);

    // أطراف الدورة المعروفة ظاهرة بأرصدتها — العميل بعد القبض
    // والمورد بما عليه من الشراء (المصدر واحد مع تقرير التقارير).
    expect(find.text('عميل الأمل'), findsWidgets,
        reason: 'العميل ظاهر بذمته بعد دورة البيع والقبض');
    expect(find.text('مورد الشرق'), findsWidgets,
        reason: 'المورد ظاهر بذمته بعد دورة الشراء');
    expect(find.text('مدينة — هم يدينون لنا'), findsWidgets,
        reason: 'لسان الاتجاه المدين الموثق س-73: هم يدينون لنا');
    expect(find.text('دائنة — نحن مدينون لهم'), findsWidgets,
        reason: 'لسان الاتجاه الدائن الموثق س-73: نحن مدينون لهم');

    // الضغط على الطرف يفتح كشف حسابه بخلاصته
    await tester.tap(find.text('عميل الأمل').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('كشف حساب — عميل الأمل'), findsOneWidget,
        reason: 'كشف حساب الطرف مفتوح باسمه');
    expect(find.textContaining('الصافي'), findsWidgets,
        reason: 'الخلاصة بصيغة الذمم الموثقة: مدين − دائن');
    expect(find.textContaining('مدين'), findsWidgets);
  });

  testWidgets('س125: تبويب أعمار الذمم بفوهج الافتراض المحفوظ (30/60/90/120) '
      'والإجمالي — المفهرس مشترك مع التقارير فلسانهما واحد', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
      MaterialApp(home: ReceivablesScreen(db: db)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('أعمار الذمم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('فوهج الأعمار'), findsOneWidget);
    expect(find.text('30/60/90/120'), findsOneWidget,
        reason: 'الافتراض الأول من الثوابت الجاهزة (س46/D-140)');
    expect(find.textContaining('الإجمالي:'), findsOneWidget);
  });

  testWidgets('س125: شاشة الدفتر المحاسبي تعرض دليل الحسابات بأنواعه '
      'والضغط على حساب ورقة يفتح كشف حسابه برصيده الختامي',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: LedgerScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // خلاصة الدليل ظاهرة والدورة تزرع الدليل الافتراضي كاملاً —
    // والقائمة كسولة فما تحت الخط لا يُبنى (درس الاختبار الموثق):
    // التأكيد على صفوف ظاهرة لا على أكواد بعيدة.
    expect(find.textContaining('دليل الحسابات — '), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets,
        reason: 'صفوف الدليل ظاهرة بأكوادها وأسمائها وأنواعها');

    // أول حساب ورقة ظاهر يفتح كشفه — والدورة تحرك القيود فله أسطر
    final firstLeaf =
        find.byWidgetPredicate((w) => w is ListTile && w.onTap != null).first;
    await tester.tap(firstLeaf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('كشف الحساب — '), findsOneWidget);
    expect(find.textContaining('الرصيد الختامي'), findsOneWidget,
        reason: 'الرصيد الختامي على جانبه الطبيعي لا يُقلب خفية');
    expect(find.textContaining('مدين:'), findsWidgets);
    expect(find.textContaining('دائن:'), findsWidgets);
  });

  testWidgets('س125: بلاطتا الذمم والدفتر مفتوحتان بالهيكلية وفتحهما '
      'يفتح شاشتيهما — نمط D-198 الموثق بضخّات محدودة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // بلاطة الذمم بالقائمة بعد الطلبات — تمرير حتى الظهور ثم فتحها
    // (نمط D-198: ضخّات محدودة لا pumpAndSettle بعد الفتح).
    await tester.scrollUntilVisible(
      find.text('الذمم'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('الذمم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ReceivablesScreen), findsOneWidget,
        reason: 'الذمم فُتحت بشاشتها الجديدة س125');
    expect(find.text('أرصدة الأطراف'), findsOneWidget);

    // رجوع ثم فتح بلاطة الدفتر بنفس النمط — الرجوع بحالة الملاح
    // مباشرة (المطبوعات Material لا Cupertino فلا pageBack).
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(
      find.text('الدفتر المحاسبي'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('الدفتر المحاسبي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LedgerScreen), findsOneWidget,
        reason: 'الدفتر المحاسبي فُتح بشاشته الجديدة س125');
    expect(find.textContaining('دليل الحسابات — '), findsOneWidget);
  });
}
