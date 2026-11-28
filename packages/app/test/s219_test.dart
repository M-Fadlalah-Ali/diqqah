import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/device_gate_screen.dart';
import 'test_guard.dart';

/// جذر المستودع: الاختبارات تعمل من packages/app في CI ومحلياً
/// بعرف الدورة — فالصعود درجتين يصل المستودع (نمط s218 للتخزين).
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${dir.path}/worklog.md').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('جذر المستودع غير موجود من ${Directory.current.path}');
}

/// س219 — قياس b73 الحي بكلمة المالك («هل هذا طبيعي؟» على زمن فشل
/// الدخول): القياس فسّر الكود فكانت الدفعة بعقدَين — النواة الحسابية
/// للتجزئة والتحقق بعزل الخلفية حصراً (فلا تجميد واجهة 600,000
/// تكراراً كل محاولة وعتبة ANR الإدخالية أندرويد 5 ثوانٍ بقلب
/// العلة)، ومؤشرُ جريان بالبوابة يتحرك فعلاً بعد انتقال الحساب
/// خارج خيط الواجهة (قبلها كان أي مؤشر سيتجمّد مع الخيط المحجوب).
/// الواجهة هنا تحرس وجهها: المؤشر بالجريان وزواله بالانتصار،
/// والحرس البنيوي بلا تجزئة متزامنة بشاشات التطبيق الأربع —
/// والحسم التوقيتي للرفض الثلاثة بيد اختبارات التخزين s219.
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

  /// ضخّات الجاهزية بعد pumpWidget — نمط s216 الموثق.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('س219: مؤشر الجريان أثناء التحقق — يظهر لحظة الضغط '
      'ويزول بالجواب فلا زر ميت بلا صوت', (tester) async {
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

    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'بلا جريان قبل الفعل');

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'owner');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'wrong-pass');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'مؤشر الجريان أثناء التحقق — التجزئة بالعزل الخلفي '
            'فالمؤشر يتحرك فعلاً (س219)');

    // إتمام الفشل بنافذة واقعية نمط س217 الموثق — Isolate.run يعمل
    // بالنمطين، ثم ضخّات عودة بالمنطقة الزائفة لمعالجة الجواب.
    await tester.runAsync(() =>
        Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('بيانات الدخول غير صحيحة'), findsOneWidget,
        reason: 'عقد س216 باقياً: الرسالة العامة واحدة');
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'المؤشر زال بالجواب — لا جريان بعد اكتمال التحقق');
    expect(await db.sessionLocked(), isTrue,
        reason: 'الرفض لا يزيل الراية — عقد س212 باقياً');
  });

  testWidgets('س219: النجاح كله من البوابة بعزل الخلفية — الدخول '
      'يكمل بلا تجميد والانتقال نُادي بعقد س216', (tester) async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.lockSession();

    var unlocked = 0;
    await tester.pumpWidget(MaterialApp(home: DeviceGateScreen(
      db: db,
      hasherIterations: 50,
      onUnlocked: () => unlocked++,
    )));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدخول'), 'owner');
    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'owner-pass');
    await tester.pump();
    await tester.tap(find.text('دخول'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'النجاح يمر بالتحقق الخلفي ذاته فالمؤشر بالجريان');

    // قفزتان بنوافذ واقعية (نمط س217 الموثق — درس الجولة الحاكمة #443):
    // التحقق خلفياً ثم الترقية الآلية (السجل 50 دون عتبة 60 يُرقّى عند
    // أول دخول ناجح بعقد س219) — وزالة المؤشر بيد onUnlocked لا الشاشة
    // ذاتها (عقد س216 الموثق: فالضخ المباشر بلا انتقال يبقيه) فبلا
    // settleFrames هنا حصراً.
    await pumpIsolateHops(tester, hops: 2, settleFrames: false);

    expect(unlocked, 1,
        reason: 'الانتقال نُادي بopenSession اكتمالاً — الدخول كله '
            'بلا تجميد بعزل الخلفية (س219)');
    expect(await db.currentUserId(), managerId,
        reason: 'الجلسة صاحبها من التحقق الخلفي بعقد resumeSession');
    expect(await db.sessionLocked(), isFalse,
        reason: 'openSession أزال الراية — عقد س212 باقياً');
  });

  test('س219: الحرس البنيوي — لا تجزئة متزامنة بشاشات التطبيق الأربع '
      'ومؤشر الجريان بالبوابة (عقد العزل الخلفي بالمدار ذاته)', () {
    final root = _repoRoot().path;
    const screens = <String>[
      'device_gate_screen.dart',
      // س233 (D-230): شطر ملف الإعدادات — مالك تجزئة الكلمة صار ملف
      // الهوية (settings/identity_section.dart) فالحارس يتبعه.
      'settings/identity_section.dart',
      'users_screen.dart',
      'first_run_screen.dart',
    ];
    for (final name in screens) {
      final src =
          File('$root/packages/app/lib/$name').readAsStringSync();
      expect(src.contains('hashInBackground('), isTrue,
          reason: '$name بالتجزئة الخلفية حصراً — عقد س219');
      expect(RegExp(r'\.hash\(').hasMatch(src), isFalse,
          reason: '$name بلا تجزئة متزامنة إطلاقاً — 600,000 تكراراً '
              'بعزل الواجهة تجميد واجهة (القياس الحي b73)');
    }
    final gate = File(
            '$root/packages/app/lib/device_gate_screen.dart')
        .readAsStringSync();
    expect(gate.contains('LinearProgressIndicator'), isTrue,
        reason: 'مؤشر الجريان بالبوابة — ما بعد انتقال الحساب للخلفية');
  });
}
