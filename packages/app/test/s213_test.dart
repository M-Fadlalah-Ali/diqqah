import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/device_gate_screen.dart' show DeviceGateScreen;
import 'package:diqqah_app/settings_screen.dart' show SettingsScreen;
import 'package:diqqah_app/backup_center.dart' show kAppVersion;
import 'test_guard.dart';

/// س213 — دفعة 3 من خطة الجلسة والمستخدمين (D-217/D-218): الخمول
/// إعداد جهاز بالمستويات المغلقة والقفل الفوري عند مغادرة التطبيق،
/// والبيومتري للفتح السريع للمعلق فقط بحقن الاختبارات (عرف
/// saveOverride — ما يُختبر هو ما يُشغَّل حرفاً)، وتنظيم الإعدادات
/// بالخيار أ ترويسات الأقسام الخمسة داخل القائمة ذاتها، والإصدار
/// الموحد.
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

  /// ضخّات الجاهزية بعد pumpWidget.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  /// درس D-098: الوصول بالتمرير حتى الهدف لا افتراضه.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    for (var i = 0;
        i < 16 &&
            find.text(label).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
    }
  }

  testWidgets('س213/D-218: ترويسات الأقسام الخمسة داخل القائمة ذاتها '
      'بترتيب القرار — بلا صفحات فئات ولا جانب كاشف (الخيار ب مؤجل)',
      (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: '/tmp/diqqah_s213/dummy.db',
      onRestored: () {},
      hasherIterations: 50,
    )));
    await settle(tester);

    for (final header in [
      'الهوية والصلاحيات',
      'البيانات والأمان',
      'سياسات البيع',
      'العرض والمظهر',
      'العمليات',
    ]) {
      await scrollTo(tester, header);
      expect(find.text(header), findsOneWidget, reason: 'ترويسة $header');
    }
  });

  testWidgets('س213/D-217: بطاقة الخمول للمدير حصراً — المنسدلة '
      'بالافتراض 10 والتغيير إلى 5 يُكتب بالقاعدة فوراً', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: '/tmp/diqqah_s213/dummy.db',
      onRestored: () {},
      hasherIterations: 50,
    )));
    await settle(tester);

    await scrollTo(tester, 'الخمول وقفل الجهاز');
    expect(find.text('الخمول وقفل الجهاز'), findsOneWidget);
    // الافتراض 10 دقائق (حسم F-147 الموثق)
    expect(find.text('10 دقائق'), findsOneWidget);
    // نص القانون: المغادرة قفل فوري لا خيار
    expect(find.textContaining('مغادرة التطبيق'), findsOneWidget);
    expect(find.textContaining('قاعدة لا خيار'), findsOneWidget);

    // التغيير إلى 5 دقائق — يُكتب بالقاعدة لحظياً (لا زر حفظ)
    await tester.ensureVisible(find.text('قفل الجلسة بعد خمول'));
    await tester.pump();
    await tester.tap(find.text('10 دقائق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 دقائق').last);
    await tester.pumpAndSettle();

    expect(await db.sessionIdleMinutes(), 5);
    expect(find.text('5 دقائق'), findsOneWidget);
  });

  testWidgets('س213/D-217: البطاقة غائبة عن الكاشير — إعداد جهاز '
      'بيد المدير لا تفضيل شخصي فلا يعطّله الكاشير', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    final cashierId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setCurrentUserId(cashierId);

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: '/tmp/diqqah_s213/dummy.db',
      onRestored: () {},
      hasherIterations: 50,
    )));
    await settle(tester);

    await scrollTo(tester, 'المستخدم الحالي');
    expect(find.text('المستخدم الحالي'), findsOneWidget);
    expect(find.text('الخمول وقفل الجهاز'), findsNothing,
        reason: 'المدير حصراً — نص القرار');
    // والبلاعة الأخرى بقسمها معروضة (النسخ والاستعادة بلا بوابة
    // الإدارة) — الترويسة سالمٌة أما البطاقة الإدارية فحدها خفية.
  });

  testWidgets('س213/D-217: القفل الفوري عند مغادرة التطبيق — hidden '
      'يكتب الراية بمصدره app_left ويعرض بوابة الجهاز (وinactive لا '
      'يقفل — حوار نظام لا مغادرة)', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await pumpApp(tester, db);
    expect(find.text('الأطراف'), findsOneWidget);

    // inactive: حوار نظام أو انتقال عابر — لا قفل
    tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('بوابة الجهاز'), findsNothing);
    expect(await db.sessionLocked(), isFalse);

    // hidden داخل نافذة النبض (درس الجولة الموثق بالدفعة: التصوير
    // خارج نافذة pump لا يولّد إطاراً للبناء المُعلّق — فالتصوير
    // بالمؤقت داخل elapse بنمط الاختبار الخمولي المحكوم).
    Timer(const Duration(milliseconds: 50), () {
      tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.hidden);
    });
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // الحكم على أثر الآلة: الراية مكتوبة بمصدرها والحدث وحيد —
    // وتبديل الوجه بعد القفل مسارٌ واحد محكوم بـAppGate: اختبار
    // الخمول بهذه الجلسة يحكمه بالضخ الكامل، واختبارات s212 تحكمه
    // بالقفل اليدوي — فلا إعادة تداول لمسارٍ واحد هنا.
    expect(await db.sessionLocked(), isTrue);
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_locked')))
        .get();
    expect(events, hasLength(1), reason: 'inactive لم يضف قفلاً');
    final payloadText = await db.openLogText(events.first.payload);
    expect(payloadText, contains('"via":"app_left"'));
  });

  testWidgets('س213/D-217: الخمول يقفل بعد المدة الافتراضية 10 — '
      'والنشاط يمدّ العدّ (اللمس والحركة شاهد على الجلسة)',
      (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await pumpApp(tester, db);

    // 9 دقائق خمول — أقل من العتبة فلا قفل
    await tester.pump(const Duration(minutes: 9));
    await tester.pumpAndSettle();
    expect(find.text('بوابة الجهاز'), findsNothing);

    // نشاط حي: لمسة وحركة عند نقطة محايدة تُلغى (cancel) فلا فعل
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(24, 12));
    await gesture.cancel();
    await tester.pump();

    // 9 دقائق أخرى — المُنقضى منذ اللمسة 9 دقائق فلا قفل بعدُ
    await tester.pump(const Duration(minutes: 9));
    await tester.pumpAndSettle();
    expect(find.text('بوابة الجهاز'), findsNothing,
        reason: 'النشاط مدّ العدّ — لا قفل عند 18 دقيقة');

    // دقيقتان أخريان — المُنقضى منذ اللمسة 11 دقيقة ≥ 10 فالقفل
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();

    expect(find.text('بوابة الجهاز'), findsOneWidget);
    expect(await db.sessionLocked(), isTrue);
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_locked')))
        .get();
    expect(events, hasLength(1));
    final payloadText =
        await db.openLogText(events.first.payload);
    expect(payloadText, contains('"via":"idle"'));
  });

  testWidgets('س213 (بس216: بلا بلاطات): زر البصمة للمعلق حصراً — '
      'يظهر لحين المستأنف بلا أي اسم معروض والفتح بالحقن يزيل الراية '
      'بopenSession', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    // الكاشير حساب ثانٍ بلا حامل اسم — لا يعرض ولا يذكر بالبوابة
    await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    var unlocked = 0;
    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      biometricAvailability: () async => true,
      biometricAuthenticate: () async => true,
      onUnlocked: () => unlocked++,
    )));
    await settle(tester);

    // المستأنف موجود — الزر ظاهر ولا اسم لأحد على البوابة (س216)
    expect(find.text('فتح بالبصمة'), findsOneWidget);
    expect(find.textContaining('البصمة لصاحب الجلسة المعلقة حصراً'),
        findsOneWidget);
    expect(find.text('المالك'), findsNothing);
    expect(find.text('كاشير'), findsNothing);

    await tester.tap(find.text('فتح بالبصمة'));
    await tester.pump();
    // س219: المؤشر بالجريان لحظة النجاح يزول بيد onUnlocked لا الشاشة
    // (عقد س216 الموثق) — والضخ المباشر هنا بلا انتقال فلا
    // pumpAndSettle فوق مؤشر باقٍ بالعقد ذاته (درس الجولة الحاكمة #443)
    await tester.pump(const Duration(milliseconds: 300));

    expect(unlocked, 1);
    expect(await db.sessionLocked(), isFalse,
        reason: 'openSession بعقد س212 حصراً');
    expect(await db.currentUserId(), managerId,
        reason: 'البصمة للمستأنف ذاته — لا تبديل');
    // الانتقال البصري للوجه يحكمه AppGate بعرف س212 (اختباراته
    // المحكمة) — هنا الضخ المباشر للبوابة فالحكم على الآلة والراية.
  });

  testWidgets('س213: رفض التحقق البيومتري برسالته والبوابة باقية '
      'والراية مقفلة والكلمة هي المسار', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      biometricAvailability: () async => true,
      biometricAuthenticate: () async => false,
      onUnlocked: () {},
    )));
    await settle(tester);

    await tester.tap(find.text('فتح بالبصمة'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('لم يُكمل التحقق البيومتري — أدخل كلمة المرور'),
        findsOneWidget);
    expect(find.text('بوابة الجهاز'), findsOneWidget);
    expect(await db.sessionLocked(), isTrue);
  });

  testWidgets('س213/D-216: صاحب راية الإلزام لا زر بصمة له — حواره '
      'يحتاج كلمة متحققة فالكلمة هي المسار ولو كان حساس الجهاز فعالاً',
      (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    // الولادة العريى ترفع الراية (D-216) فالكاشير صاحبها
    final cashierId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setCurrentUserId(cashierId);
    await db.lockSession();

    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      biometricAvailability: () async => true,
      biometricAuthenticate: () async => true,
      onUnlocked: () {},
    )));
    await settle(tester);

    // س216: لا بلاطات ولا «فتح سريع» — والحوار الإلزامي يحتاج كلمة
    // متحققة فالبصمة مخفية عن صاحب الراية
    expect(find.text('فتح سريع'), findsNothing);
    expect(find.text('فتح بالبصمة'), findsNothing,
        reason: 'البصمة تتجاوز التحقق الكلمي الذي يحتاجه الحوار الإلزامي');
    // والكلمة متاحة كمسراها القائم
    expect(find.text('دخول'), findsOneWidget);
  });

  testWidgets('س213: بلا حساس بيومتري على الجهاز — لا زر ولا شرح '
      'والكلمة هي المسار الوحيد', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      biometricAvailability: () async => false,
      onUnlocked: () {},
    )));
    await settle(tester);

    expect(find.text('فتح بالبصمة'), findsNothing);
    expect(find.textContaining('البصمة لصاحب الجلسة المعلقة حصراً'),
        findsNothing);
    expect(find.text('دخول'), findsOneWidget);
  });

  // التثبيت الصلب انتقل من s213 إلى s215 بنمط انتقاله الموثق —
  // فبقي هنا حارسُ مطابقة pubspec↔الكتالوج بلا تثبيت صلب.
  test('مطابقة pubspec↔كتالوج الإصدار (س213 — حارس المطابقة بعد '
      'انتقال التثبيت الصلب إلى s215)', () {
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
