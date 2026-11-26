import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/device_gate_screen.dart';
import 'test_guard.dart';

/// س216 — بوابة الجهاز بإدخال يدوي حصراً (نقض بلاطات U-005 بأمر
/// المالك «ما السبب في إبقائك على قائمة الأسماء في شاشة الدخول؟»):
/// لا تعداد أسماء ولا أسماء دخول على شاشة القفل، والفشل برسالة عامة
/// واحدة بلا تفرقة ولا نص استثناء خام، والبصمة للمعلق حصراً كما هي
/// (س213) والحوار الإلزامي لصاحب الراية (D-216) بعقد س212.
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

  /// ضخّات الجاهزية بعد pumpWidget — الجلسة والقوائم لحظية.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('س216: البوابة بلا تعداد — مستخدمان نشطان ولا اسم منهما '
      'ولا أسماء دخول تظهر، والحقان اليدويان حاضران', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.lockSession();

    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      onUnlocked: () {},
    )));
    await settle(tester);

    expect(find.text('المالك'), findsNothing,
        reason: 'لا بلاطات أسماء — الإدخال اليدوي حصراً (س216)');
    expect(find.text('كاشير'), findsNothing);
    expect(find.text('owner'), findsNothing,
        reason: 'أسماء الدخول لا تُعرض على شاشة القفل');
    expect(find.text('cashier'), findsNothing);
    expect(find.text('فتح سريع'), findsNothing,
        reason: 'بلاطات U-005 نقضت بس216 — لا مستأنف معروض بالاسم');
    expect(find.widgetWithText(TextField, 'اسم الدخول'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'كلمة المرور'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
  });

  testWidgets('س216: الدخول اليدوي الناجح من الإقلاع المقفل كله — '
      'الرئيسية تعود والراية تفنجان', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.lockSession();

    await tester.pumpWidget(DiqqahApp(db: db, hasherIterations: 50));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('بوابة الجهاز'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'owner');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'owner-pass');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    // س219: قفزتا التحقق والترقية الآلية بنوافذ واقعية (نمط س217 الموثق
    // — درس الجولة الحاكمة #443: رسالة العزل بنافذة لا بالمنطقة الزائفة)
    await pumpIsolateHops(tester, hops: 2);

    expect(find.text('بوابة الجهاز'), findsNothing);
    expect(find.text('الأطراف'), findsOneWidget);
    expect(await db.sessionLocked(), isFalse,
        reason: 'openSession بعقد س212 حصراً');
    expect(await db.currentUserId(), managerId);
  });

  testWidgets('س216: كلمة خاطئة واسم مجهول برسالة عامة واحدة — '
      'لا نص استثناء خام ولا تفرقة معلوماتية', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.lockSession();

    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      onUnlocked: () {},
    )));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'owner');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'wrong-pass');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    // س219: قفزة التحقق الخلفي بنافذة واقعية (نمط س217 — درس الجولة #443)
    await pumpIsolateHops(tester, hops: 1);

    expect(find.text('بيانات الدخول غير صحيحة'), findsOneWidget);
    expect(find.textContaining('كلمة المرور غير صحيحة'), findsNothing,
        reason: 'النص الخام لم يعد يعرض بالبوابة بعد س216');
    expect(find.text('بوابة الجهاز'), findsOneWidget);
    expect(await db.sessionLocked(), isTrue);

    // واسم مجهول برسالة العام ذاته بلا تفرقة
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'ghost');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    // س219: قفزة موازنة المجهول بنافذة واقعية (نمط س217 — درس #443)
    await pumpIsolateHops(tester, hops: 1);

    expect(find.text('بيانات الدخول غير صحيحة'), findsOneWidget,
        reason: 'المجهول كالكلمة الخاطئة ذاتها حرفاً');
    expect(await db.currentUserId(), isNull);
  });

  testWidgets('س216/D-216: صاحب الراية يدخل باسمه — الحوار الإلزامي '
      'غير القابل للرصد بعد التحقق والراية تفنجان ثم تُزال فلا ثقب عودة',
      (tester) async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    final cashierId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setCurrentUserId(cashierId);
    await db.lockSession();

    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      onUnlocked: () {},
    )));
    await settle(tester);

    // الدخول اليدوي باسم الكاشير بكلمته الأولية
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
    // س217 — درس #443) — وبلا settleFrames: نجاح البوابة المضخوخة
    // مباشرة يُبقي المؤشر بعقد س216 (زالته بيد onUnlocked لا الشاشة)
    await pumpIsolateHops(tester, hops: 2, settleFrames: false);

    // الجلسة بدأت بعد التغيير حصراً — س217 (درس التشغيل المحلي): توقع
    // «بوابة الجهاز» غائبة كان مستحيلاً بعقد الشاشة ذاته فالزالة بيد
    // الصاحب عبر onUnlocked (هنا فارغ) — والعقد الصحيح: الحوار
    // الإلزامي أُغلق بالنجاح والبوابة باقية بلا جلسة منقضية والراية
    // أزيلت بالتخزين (openSession بعقد س212).
    expect(find.text('غيّر كلمة مرورك لمتابعة الجلسة'), findsNothing,
        reason: 'الحوار غير قابل للرصد ولا يُعاد إلا بنجاح — والنجاح يغلقه');
    expect(find.text('بوابة الجهاز'), findsOneWidget,
        reason: 'البوابة باقية — زالتها بيد صاحب onUnlocked لا الشاشة ذاتها');
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

  testWidgets('س216: البصمة للمعلق حصراً كما هي — تظهر لحين المستأنف '
      'وتفتح الجلسة بعقد س213 بلا أي اسم معروض', (tester) async {
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

    // المستأنف موجود — الزر ظاهر ولا اسم لأحد على البوابة
    expect(find.text('فتح بالبصمة'), findsOneWidget);
    expect(find.textContaining('البصمة لصاحب الجلسة المعلقة حصراً'),
        findsOneWidget);
    expect(find.text('المالك'), findsNothing);
    expect(find.text('كاشير'), findsNothing);

    await tester.tap(find.text('فتح بالبصمة'));
    await tester.pump();
    // س219: المؤشر بالجريان لحظة النجاح يزول بيد onUnlocked لا الشاشة
    // (عقد س216 الموثق) — والضخ المباشر هنا بلا انتقال فلا
    // pumpAndSettle فوق مؤشر باقٍ بالعقد ذاته (درس الجولة #443)
    await tester.pump(const Duration(milliseconds: 300));

    expect(unlocked, 1);
    expect(await db.sessionLocked(), isFalse,
        reason: 'openSession بعقد س212 حصراً');
    expect(await db.currentUserId(), managerId,
        reason: 'البصمة للمستأنف ذاته — لا تبديل');
  });
}
