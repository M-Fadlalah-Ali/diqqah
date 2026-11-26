/// اختبار بوابة الاستعادة (تكليف 2026-11-13 §5/§6 — قرار ق-ن1-أ):
/// خمس محاولات فاشلة تقفل البوابة، والنجاح يعرض ملخصاً مصفّى بشارة
/// سلامة ويكتب حدثي التدقيق ويمسح المفتاح.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/restore_gate_screen.dart';

import 'test_guard.dart';

void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار (test_guard — درس 124..128).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  const password = 'gate-123';

  /// بذر مدير بكلمة مرور حقيقية (PBKDF2 بذات تكرارات التحقق الافتراضية)
  /// وزرع مفتاح البوابة كما يزرعه applyRestore بعد استعادة.
  Future<DiqqahDatabase> seededDb() async {
    final db = DiqqahDatabase.inMemorySyncClose(
        passwordUpgradeIterations: PasswordHasher.legacyIterations);
    final hasher =
        PasswordHasher(iterations: PasswordHasher.legacyIterations);
    final salt = PasswordHasher.newSalt();
    final stored = '$salt:${hasher.hash(password, salt)}';
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: stored);
    await db.customStatement(
        "INSERT INTO app_meta (key, value) VALUES ('restore.gate', ?)",
        ['{"at":"2026-11-13T08:00:00.000Z","source":"b.dqk",'
            '"attempts":0,"locked":false}']);
    return db;
  }

  Future<void> open(WidgetTester tester, DiqqahDatabase db) async {
    await tester.pumpWidget(MaterialApp(
        home: RestoreGateScreen(
            db: db, dbPath: 'diqqah.db', onCleared: () {})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('كلمة خاطئة خمس مرات → القفل بمخرجَي نسخة أخرى وإعادة محاولة',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);

    await open(tester, db);

    for (var i = 0; i < 5; i++) {
      await tester.enterText(find.byType(TextField), 'wrong!');
      await tester.tap(find.text('دخول'));
      await tester.pump();
      // س219: التحقق بعزل الخلفية — ضخّ أولاً كي يُرسَم الانشغال ثم
      // استطلاع بنوافذ واقعية حتى يعود زر الدخول أو يظهر القفل (نمط
      // س217 الموثق ودرس الجولتين #443/#444: الاستطلاع بلا ضخّ أول
      // يخرج لحظياً قبل رسم الانشغال فالضغطة التالية بلا هدف)
      for (var j = 0;
          j < 60 &&
              find.text('دخول').evaluate().isEmpty &&
              find.textContaining('استُنفدت').evaluate().isEmpty;
          j++) {
        await tester.runAsync(() =>
            Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('استُنفدت محاولات الدخول الخمس'),
        findsOneWidget);
    expect(find.text('استعادة نسخة أخرى'), findsOneWidget);
    expect(find.text('إعادة المحاولة لاحقاً'), findsOneWidget);
    final gate = await db.restoreGate();
    expect(gate!.locked, isTrue);
    expect(gate.attempts, 5);
  });

  testWidgets('النجاح: ملخص مصفّى بشارة سلامة وحدثا تدقيق ومفتاح ممسوح',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);

    await open(tester, db);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('دخول'));
    // س219: التحقق بعزل الخلفية — استطلاع بنوافذ واقعية حتى ملخص النجاح
    // (نمط الملف الموثق — لا pumpAndSettle ولا نافذة واحدة — درس #443)
    var shown = false;
    for (var i = 0; i < 60 && !shown; i++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      shown = find.text('تمت الاستعادة بنجاح').evaluate().isNotEmpty;
    }
    expect(shown, isTrue,
        reason: 'ملخص النجاح لم يظهر خلال مهلة النوافذ الواقعية');

    expect(find.text('تمت الاستعادة بنجاح'), findsOneWidget);
    expect(find.textContaining('سلامة القاعدة'), findsOneWidget);
    expect(find.textContaining('عدد المستخدمين: 1'), findsOneWidget);
    expect(find.textContaining('إجمالي الفواتير: 0'), findsOneWidget);

    await tester.tap(find.text('متابعة'));
    await tester.pump(const Duration(milliseconds: 200));

    // §5-7/§6: حدثا التدقيق كلاهما، والبوابة ممسوحة، والجلسة للمدير.
    expect(await db.restoreGate(), isNull);
    expect(await db.currentUserId(), isNotNull);
    final events = await (db.select(db.events)
          ..where((t) => t.entityType.equals('system')))
        .get();
    expect(events.map((e) => e.action).toSet(),
        containsAll(['restore_performed', 'restore_summary_shown']));
    final summaryEvent =
        events.firstWhere((e) => e.action == 'restore_summary_shown');
    expect(await db.openLogText(summaryEvent.payload),
        contains('last_document'));
  });
}
