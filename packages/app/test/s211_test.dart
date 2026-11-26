import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/users_screen.dart';
import 'package:diqqah_app/settings_screen.dart' show SettingsScreen;
import 'package:diqqah_app/backup_center.dart'
    show kAppVersion;
import 'test_guard.dart';

/// س211 — دفعة 1 من خطة الجلسة والمستخدمين (D-216): شاشة المستخدمين
/// بالوحدة والبوابتين، والولادة بأقل امتياز، وحمايات التخزين الثلاث
/// معروضة برسائلها، وإلزام تغيير الكلمة بعد التبديل، وتغيير الكلمة
/// الذاتي الطوعي، والإصدار الموحد.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  String hashOf(String password, {int iterations = 50}) {
    final salt = PasswordHasher.newSalt();
    final hash =
        PasswordHasher(iterations: iterations).hash(password, salt);
    return PasswordHasher.formatStored(salt, hash, iterations);
  }

  DiqqahDatabase newDb() =>
      DiqqahDatabase.inMemorySyncClose(passwordUpgradeIterations: 60);

  /// درس D-098: الوصول بالتمرير حتى الهدف لا افتراضه — والبلاطة
  /// الجديدة نهاية القائمة لا تُزيح بنداً ولا ميزانية سحب.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    for (var i = 0; i < 12 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
  }

  Future<void> openUsers(WidgetTester tester, DiqqahDatabase db) async {
    await tester.pumpWidget(MaterialApp(
        home: UsersScreen(db: db, hasherIterations: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('س211/D-216: بلاطة المستخدمين بالرئيسية — آخر القائمة عرف '
      'D-098 بوحدتها المانحة', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    // الوحدة بالمفاتيح المعروفة والبلاطة بنهاية القائمة
    expect(moduleKeys.contains('users'), isTrue);
    expect(moduleKeys.last, 'users');
    expect(moduleLabels['users'], 'المستخدمون');
  });

  testWidgets('س211/D-216: إنشاء مستخدم من الحوار — يظهر بالقائمة أعرياً '
      'بودار «مستخدم» ورايته الظاهرة', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(
        (await db.currentUser())!.id);

    await openUsers(tester, db);

    await tester.tap(find.byTooltip('مستخدم جديد'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'الاسم الظاهر'), 'كاشير أول');
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'cashier');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور الأولية'), 'init-pass');
    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور'), 'init-pass');
    await tester.pump();
    await tester.tap(find.text('إنشاء المستخدم'));
    // س219: التجزئة الخلفية بعزل منفصل — نافذة واقعية للتسليم ثم ضخّات
    // عودة (نمط س217 الموثق — درس الجولة الحاكمة #443)
    await pumpIsolateHops(tester, hops: 1);

    expect(find.text('كاشير أول'), findsOneWidget);
    expect(find.textContaining('دخوله: cashier'), findsOneWidget);
    expect(find.textContaining('دور: $kBareUserRoleName'), findsOneWidget);
    expect(find.textContaining('يُلزَم بتغيير كلمته'), findsOneWidget);

    // والوليد أعري فعلاً بالقاعدة
    final rows = await db.select(db.appUsers).get();
    final created = rows.firstWhere((u) => u.login == 'cashier');
    expect(created.mustChangePassword, isTrue);
    final role = await db.roleOf(created);
    expect(role!.permissions, isEmpty);
  });

  testWidgets('س211/D-216: بوابة القراءة الخالصة — من مُنح الوحدة وحدها '
      'يرى القائمة بلا زر إنشاء ولا زر حالة', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    final viewerId = await db.createUser(
        name: 'مشرف', login: 'viewer', passwordHash: 's:h');
    final roleId = await db.createRole(
        name: 'عارف مستخدمين', permissions: 'users');
    await db.updateUserRole(viewerId, roleId);
    await db.setCurrentUserId(viewerId);

    await openUsers(tester, db);

    // زر الإنشاء معطلاً (الفشل المغلق — لا فعل قبل صلاحية) —
    // byTooltip يعين Tooltip فالأيقونة بسلفه
    final addIcon = find.ancestor(
        of: find.byTooltip('مستخدم جديد'),
        matching: find.byType(IconButton)).first;
    expect(
        tester.widget<IconButton>(addIcon).onPressed, isNull);
    // وأزرار الحالة على الصفين معطلة — المدير بما هو نجمة لا يُمس
    // بيد الأعرى والتخزين حارسه الثالث
    final toggles = find.ancestor(
        of: find.byTooltip('تعطيل المستخدم'),
        matching: find.byType(IconButton));
    expect(toggles, findsNWidgets(2));
    for (final w in tester.widgetList<IconButton>(toggles)) {
      expect(w.onPressed, isNull);
    }
    // والجلسة الحالية هو المشرف لا المالك — سقف التصعيد حي
    expect((await db.currentUser())!.id, viewerId);
    expect(managerId, isNot(viewerId));
  });

  testWidgets('س211/D-216: التعطيل والتفعيل بالشاشة — رسالة الرفض العربية '
      'لحماية الجلسة الحالية تظهر كما يصوغها التخزين', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.createUser(
        name: 'كاشير أول', login: 'cashier', passwordHash: 's:h');
    final managerId = (await db.currentUser())!.id;
    await db.setCurrentUserId(managerId);

    await openUsers(tester, db);

    // زر التعطيل على صف الكاشير حصراً — صف الجلسة محمي بالتخزين
    final cashierRow = find.ancestor(
        of: find.text('كاشير أول'), matching: find.byType(ListTile)).first;
    await tester.tap(find.descendant(
        of: cashierRow, matching: find.byTooltip('تعطيل المستخدم')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('— معطل'), findsOneWidget);
    final rows = await db.select(db.appUsers).get();
    expect(
        rows.firstWhere((u) => u.login == 'cashier').isActive, isFalse);
  });

  testWidgets('س211/D-216 مع س212/D-215: مدخل التبديل المباشر القديم '
      '(منسدلة وكلمة غيرك) انزال بوعي بالدفعة الثانية — التبديل عبر '
      'الآلة بز «قفل وتبديل المستخدم» وزر الكلمة الذاتي باقٍ',
      (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: '/tmp/diqqah_s208/dummy.db',
      onRestored: () {},
      hasherIterations: 50,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await scrollTo(tester, 'المستخدم الحالي');
    expect(find.text('المستخدم الحالي'), findsOneWidget);
    // المدخل المباشر القديم زال — التبديل قفلٌ ثم بلاطة البوابة (D-215)
    expect(find.text('تبديل المستخدم'), findsNothing);
    expect(find.text('كلمة مرور المستخدم المختار'), findsNothing);
    expect(find.text('قفل وتبديل المستخدم'), findsOneWidget);
    // وزر الكلمة الذاتي الطوعي باقٍ بجانبه (D-216 الضابط الثالث:
    // الإلزامي انتقل لبوابة الجهاز — s212 تحكمه)
    await tester.ensureVisible(find.text('تغيير كلمة مروري'));
    await tester.pump();
    expect(find.text('تغيير كلمة مروري'), findsOneWidget);
    // والجلسة لم تتأثر بضغطة قراءة — لا راية قبل الزر
    expect(await db.sessionLocked(), isFalse);
    expect(await db.currentUserId(), managerId);
  });

  testWidgets('س211/D-216: تغيير الكلمة الذاتي الطوعي — بالحالية من حقل '
      'الحوار حصراً والخاطئة تُرفض برسالته', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: '/tmp/diqqah_s208/own.db',
      onRestored: () {},
      hasherIterations: 50,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await scrollTo(tester, 'المستخدم الحالي');
    await tester.ensureVisible(find.text('تغيير كلمة مروري'));
    await tester.pump();
    await tester.tap(find.text('تغيير كلمة مروري'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('تغيير كلمة المرور'), findsOneWidget);

    // الرفض الأول: الحالية الخاطئة — برسالته داخل الحوار بلا إغلاق
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور الحالية'), 'wrong-pass');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور الجديدة'),
        'owner-pass-2');
    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور الجديدة'),
        'owner-pass-2');
    await tester.pump();
    await tester.tap(find.text('حفظ الكلمة الجديدة'));
    await tester.pump();
    // س219: قفزتا التجزئة الخلفية بالشاشة والتحقق بتغيير الكلمة بنوافذ
    // واقعية (نمط س217 الموثق — درس الجولة الحاكمة #443)
    await pumpIsolateHops(tester, hops: 2);
    expect(
        find.textContaining('كلمة المرور الحالية غير صحيحة'),
        findsOneWidget);

    // الرفض الثاني: التأكيد غير المطابق
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور الحالية'), 'owner-pass');
    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور الجديدة'),
        'other-pass');
    await tester.pump();
    await tester.tap(find.text('حفظ الكلمة الجديدة'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('التأكيد لا يطابق'), findsOneWidget);

    // النجاح: الحالية صحيحة والتأكيد مطابق
    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور الجديدة'),
        'owner-pass-2');
    await tester.pump();
    await tester.tap(find.text('حفظ الكلمة الجديدة'));
    await tester.pump();
    // س219: ثلاث قفزات بنوافذ واقعية (نمط س217 — درس #443): التجزئة
    // بالشاشة ثم التحقق ثم الترقية الآلية (50 دون 60) عند أول نجاح
    await pumpIsolateHops(tester, hops: 3);
    expect(find.text('تغيير كلمة المرور'), findsNothing);
    expect(find.textContaining('تم تغيير كلمة المرور'), findsOneWidget);
    // س219: التحقق المباشر بعزل الخلفية — البدء بالمنطقة الزائفة ثم
    // نوافذ واقعية لكل قفزة (نمط س217 الموثق — درس الجولة الحاكمة #443
    // ودرس الجولة #444: لفّ النداء بـrunAsync كله يعلق بعد سياقات الحوار
    // — البدء الزائف والنوافذ هي النمط الذي يكتمل حرفاً)
    final fut = db.verifyUserPassword(managerId, 'owner-pass-2');
    await pumpIsolateHops(tester, hops: 2, settleFrames: false);
    final upgraded = await fut;
    expect(upgraded, isNotNull);
    final rejectFut = db.verifyUserPassword(managerId, 'owner-pass');
    await pumpIsolateHops(tester, hops: 2, settleFrames: false);
    final rejected = await rejectFut;
    expect(rejected, isNull);
  });

  test('حارس المطابقة: pubspec↔كتالوج الإصدار بتساوي (س211 — '
      'والتثبيت الصلب انتقل من s211 إلى s212 بنمط انتقاله الموثق)', () {
    // التثبيت الصلب انتقل من s211 إلى s212 بنمط انتقاله من
    // s209 إلى s210 إلى s211 — فs211 صار حارس مطابقة
    // pubspec↔الكتالوج بلا تثبيت صلب.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((l) => l.startsWith('version:'));
    final pinned = line.split('+').last.trim();
    expect(kAppVersion.split('+').last, pinned,
        reason: 'versionCode واحد بpubspec والكتالوج');
  });
}
