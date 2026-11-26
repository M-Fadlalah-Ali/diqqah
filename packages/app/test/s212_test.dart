import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/home_screen.dart';
import 'package:diqqah_app/settings_screen.dart' show SettingsScreen;
import 'package:diqqah_app/backup_center.dart' show kAppVersion;
import 'test_guard.dart';

/// س212 — دفعة 2 من خطة الجلسة والمستخدمين (D-215/U-005): آلة
/// الحالتين وبوابة الجهاز — الراية المحفوظة بapp_meta فالإقلاع على
/// جلسة مقفلة يعرض بوابة الجهاز لا الرئيسية، وبلاطات المستخدمين
/// النشطين والفتح السريع للمستأنف، والحوار الإلزامي لصاحب الراية،
/// وأفعال الثلاثة بشارة الرئيسية والتبديل عبر الآلة بالإعدادات،
/// والإصدار الموحد.
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

  Future<void> pumpApp(WidgetTester tester, DiqqahDatabase db) async {
    await tester
        .pumpWidget(DiqqahApp(db: db, hasherIterations: 50));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// ضخّات الجاهزية بعد pumpWidget — الجلسة والقوائم لحظية.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  /// درس D-098: الوصول بالتمرير حتى الهدف لا افتراضه — بطاقة
  /// المستخدم الحالي منتصف قائمة الإعدادات لا رأسها.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    for (var i = 0; i < 12 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
  }

  testWidgets('س212/D-215: الإقلاع على جلسة مقفلة يعرض بوابة الجهاز لا '
      'الرئيسية — فلا ثقب عودة بعد موت العملية', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await pumpApp(tester, db);

    expect(find.text('بوابة الجهاز'), findsOneWidget);
    // فلا بيانات ولا وحدات خلف البوابة
    expect(find.text('الأطراف'), findsNothing);
    // س216: الإدخال اليدوي حصراً — حقلا اسم الدخول والكلمة بلا بلاطات
    expect(find.widgetWithText(TextField, 'اسم الدخول'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'كلمة المرور'), findsOneWidget);
    expect(find.text('فتح سريع'), findsNothing,
        reason: 'بلاطات U-005 نقضت بس216 — لا تعداد أسماء بالبوابة');
  });

  testWidgets('س212/D-215: الإقلاع على جلسة نشطة (بلا راية) يعود '
      'بالرئيسية كما كانت — توافق تثبيتات س211', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));

    await pumpApp(tester, db);

    expect(find.text('بوابة الجهاز'), findsNothing);
    expect(find.text('الأطراف'), findsOneWidget);
  });

  testWidgets('س216 (نقض بلاطات U-005 بأمر المالك): بوابة الجهاز بلا '
      'تعداد أسماء — مستخدمان نشطان ولا اسم ولا كلمة دخول منهما تظهر '
      'والمعطل غائب أصلاً', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.createUser(
        name: 'سابق', login: 'ex', passwordHash: hashOf('ex-pass'));
    final ex =
        await (db.select(db.appUsers)..where((t) => t.login.equals('ex')))
            .getSingle();
    await db.setUserActive(ex.id, false);
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await pumpApp(tester, db);

    expect(find.text('المالك'), findsNothing,
        reason: 'لا بلاطات أسماء — الإدخال اليدوي حصراً (س216)');
    expect(find.text('كاشير'), findsNothing);
    expect(find.text('owner'), findsNothing,
        reason: 'أسماء الدخول لا تُعرض على شاشة القفل');
    expect(find.text('cashier'), findsNothing);
    expect(find.text('سابق'), findsNothing);
    // والحقان اليدويان حاضران
    expect(find.widgetWithText(TextField, 'اسم الدخول'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'كلمة المرور'), findsOneWidget);
  });

  testWidgets('س216: الدخول اليدوي باسم الدخول والكلمة — الجلسة تعود '
      'بالرئيسية بعد الدخول والراية تفنجان', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await pumpApp(tester, db);

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'owner');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'owner-pass');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    // س219: قفزتا التحقق والترقية الآلية بنوافذ واقعية (نمط س217 الموثق
    // — درس الجولة الحاكمة #443)
    await pumpIsolateHops(tester, hops: 2);

    expect(find.text('بوابة الجهاز'), findsNothing);
    expect(find.text('الأطراف'), findsOneWidget);
    expect(await db.sessionLocked(), isFalse,
        reason: 'openSession بعد الحوار أو وجوهه حصراً');
    expect(await db.currentUserId(), managerId);
  });

  testWidgets('س216: كلمة البوابة الخاطئة برسالة العامة حصراً '
      'والبوابة باقية والراية مقفلة', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await pumpApp(tester, db);

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'owner');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'wrong-pass');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    // س219: قفزة التحقق الخلفي بنافذة واقعية (نمط س217 — درس #443)
    await pumpIsolateHops(tester, hops: 1);

    expect(find.text('بيانات الدخول غير صحيحة'), findsOneWidget,
        reason: 'الرسالة العامة حصراً — لا تفرقة كلمة/مستخدم (س216)');
    expect(find.textContaining('كلمة المرور غير صحيحة'), findsNothing,
        reason: 'نص الاستثناء الخام لم يعد يعرض بالبوابة');
    expect(find.text('بوابة الجهاز'), findsOneWidget);
    expect(await db.sessionLocked(), isTrue);
  });

  testWidgets('س212/D-216: صاحب الراية لا يدخل جلسه قبل كلمة جديدة — '
      'الحوار الإلزامي غير القابل للرصد بعد التحقق والراية تفنجان ثم '
      'تُزال فلا ثقب عودة', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    final cashierId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await pumpApp(tester, db);

    // التبديل = قفلٌ ثم دخول باسم آخر — إدخال اسم الكاشير بكلمته الأولية
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'cashier');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'init-pass');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    // س219: قفزتا التحقق والترقية الآلية بنوافذ واقعية (نمط س217 — #443)
    // — وبلا settleFrames: الحوار الإلزامي مفتوح والمؤشر خلفه باقٍ
    // بالعقد (زالته بيد onUnlocked لا الشاشة) فالاستقرار مهلة لا تنتهي
    await pumpIsolateHops(tester, hops: 2, settleFrames: false);

    // الحوار الإلزامي ظهر — بلا حقل حالي ولا إلغاء
    expect(find.text('غيّر كلمة مرورك لمتابعة الجلسة'), findsOneWidget);
    expect(find.text('كلمة المرور الحالية'), findsNothing);
    // والراية باقية مقفلة فلا ثقب عودة قبل الاكتمال
    expect(await db.sessionLocked(), isTrue);
    expect(find.text('الأطراف'), findsNothing);

    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور الجديدة'), 'new-pass');
    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور الجديدة'),
        'new-pass');
    await tester.pump();
    await tester.tap(find.text('حفظ الكلمة الجديدة'));
    await tester.pump();
    // س219: قفزتا التجزئة الخلفية والتحقق بالحوار بنوافذ واقعية (نمط
    // س217 — درس #443) — والإقلاع بـDiqqahApp فالانتقال بيد AppGate
    await pumpIsolateHops(tester, hops: 2);

    // الجلسة بدأت بعد التغيير حصراً والراية أزيلت — والوليد أعري
    // بلا أي وحدة فلا بلاطة له بالشبكة (لسانه شارة الجلسة لا الأطراف)
    expect(find.text('بوابة الجهاز'), findsNothing);
    expect(find.textContaining('كاشير'), findsWidgets);
    expect(await db.sessionLocked(), isFalse);
    expect(await db.currentUserId(), cashierId);
    final cashier = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(cashierId)))
        .getSingle();
    expect(cashier.mustChangePassword, isFalse,
        reason: 'النجاح فنجانُ الراية حصراً');
    // س219: التحقق المباشر بعزل الخلفية — البدء بالمنطقة الزائفة ثم
    // نوافذ واقعية لكل قفزة (درس الجولتين #443/#444 — لفّ النداء بـrunAsync
    // كله يعلق بعد سياقات الحوار فالبدء الزائف والنوافذ هي النمط الناضب)
    final fut = db.verifyUserPassword(cashierId, 'new-pass');
    await pumpIsolateHops(tester, hops: 2, settleFrames: false);
    expect(await fut, isNotNull);
  });

  testWidgets('س212/D-215: أفعال الثلاثة بشارة الرئيسية — القفل يكتب '
      'الراية والمستأنف يبقى والخروج يمسّيه ونداء الغلق يُنادى',
      (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    var lockCalls = 0;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(
      db: db,
      dbPath: 'diqqah.db',
      onRestored: () {},
      onLocked: () => lockCalls++,
    )));
    await settle(tester);

    // القفل: الراية تُكتب والمستأنف يبقى (فتح سريع لنفس المستخدم)
    await tester.tap(find.byTooltip('الجلسة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قفل الجلسة'));
    await tester.pumpAndSettle();
    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), managerId);
    expect(lockCalls, 1);

    // فك القفل يدوياً ثم الخروج: بلا مستأنف — وس219: الاستئناف بعزل
    // الخلفية — البدء بالمنطقة الزائفة ثم نوافذ واقعية للقفزتين (التحقق
    // ثم الترقية الآلية — درس الجولتين #443/#444 الموثق)
    final resumeFut =
        db.resumeSession(userId: managerId, password: 'owner-pass');
    await pumpIsolateHops(tester, hops: 2, settleFrames: false);
    await resumeFut;
    await db.openSession();
    await tester.tap(find.byTooltip('الجلسة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خروج'));
    await tester.pumpAndSettle();
    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), isNull);
    expect(lockCalls, 2);
  });

  testWidgets('س212/D-215: التبديل عبر الآلة بالإعدادات — زر «قفل '
      'وتبديل المستخدم» يكتب الراية وينادي الغلق فبوابة الجهاز هي '
      'الوجه (لا تبديل مباشر يتجاوز الآلة)', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    var lockCalls = 0;
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: '/tmp/diqqah_s212/dummy.db',
      onRestored: () {},
      hasherIterations: 50,
      onSessionLocked: () => lockCalls++,
    )));
    await settle(tester);

    await scrollTo(tester, 'المستخدم الحالي');
    expect(find.text('المستخدم الحالي'), findsOneWidget);
    await tester.ensureVisible(find.text('قفل وتبديل المستخدم'));
    await tester.pump();
    expect(find.text('قفل وتبديل المستخدم'), findsOneWidget);
    // فلا مدخل التبديل المباشر القديم
    expect(find.text('تبديل المستخدم'), findsNothing);
    expect(find.text('كلمة مرور المستخدم المختار'), findsNothing);

    await tester.tap(find.text('قفل وتبديل المستخدم'));
    await tester.pumpAndSettle();

    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), managerId,
        reason: 'القفل بفتح سريع لنفس المستخدم');
    expect(lockCalls, 1);
    // وزر الكلمة الذاتي الطوعي باقٍ بجانبه
    expect(find.text('تغيير كلمة مروري'), findsOneWidget);
  });

  test('س212: حارس مطابقة pubspec وكتالوج الإصدار — التثبيت الصلب '
      'انتقل إلى s213 بنمط انتقاله الموثق', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((l) => l.startsWith('version:'));
    final version =
        line.substring('version:'.length).trim();
    expect(version, kAppVersion,
        reason: 'المصدران مصدرٌ واحد — pubspec والكتالوج متطابقان');
  });
}
