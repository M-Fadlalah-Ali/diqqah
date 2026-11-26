/// اختبار نافذة التراجع على بوابة الاستعادة (د-3 — §25.7، س136):
/// زر «تراجع» لحظي بعد كل استعادة بوجود لقطة مزروعة، وغيابه بلاها،
/// وتسليح النافذة عند اجتياز البوابة، والتراجع نفسه بمسار الاستعادة
/// ذاته (تأكيد مزدوج ثم استعادة جديدة بلقطة جديدة).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/restore_gate_screen.dart';

import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  const password = 'gate-123';

  late Directory tempDir;
  late String dbPath;
  late DiqqahDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_gate_rb_t_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase.fileSyncClose(
        filePath: dbPath,
        passwordUpgradeIterations: PasswordHasher.legacyIterations);
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// بذر مدير نشط وزرع بوابة بلقطة ما قبل الاستعادة (كما يزرعها
  /// applyRestore بعد دفعة س136) مع إنشاء ملف اللقطة ذاته.
  Future<String> seedGateWithSnapshot() async {
    final hasher =
        PasswordHasher(iterations: PasswordHasher.legacyIterations);
    final salt = PasswordHasher.newSalt();
    final stored = '$salt:${hasher.hash(password, salt)}';
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: stored);
    final snapshotName = 'diqqah-before-restore-20261114-080000-000.db';
    db.customStatement(
        "VACUUM INTO '${p.join(tempDir.path, snapshotName)}'");
    await db.customStatement(
        "INSERT INTO app_meta (key, value) VALUES ('restore.gate', ?)",
        ['{"at":"2026-11-14T08:00:00.000Z","source":"b.dqk",'
            '"attempts":0,"locked":false,'
            '"snapshot":"$snapshotName"}']);
    return snapshotName;
  }

  /// نمط widget_test الموثق (درس CI الجولة 128): I/O الملفات الحقيقي
  /// (فحص ملف اللقطة في _load) يكتمل بنوافذ runAsync متتالية مع ضخ
  /// حتى يظهر زر التراجع أو نموذج الدخول — مهلة 60×50ms.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RestoreGateScreen(
            db: db,
            dbPath: dbPath,
            onCleared: () {},
            onRestored: () {})));
    for (var i = 0; i < 60; i++) {
      await tester.pump();
      final ready = find.text('المستخدم (مدير النسخة)').evaluate().isNotEmpty ||
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      if (ready) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('لقطة مزروعة → زر التراجع ظاهر بنافذتها الموثقة',
      (tester) async {
    final snapshotName = await seedGateWithSnapshot();
    await open(tester);

    expect(find.text('نافذة التراجع عن الاستعادة مفتوحة'), findsOneWidget);
    expect(find.text('تراجع عن الاستعادة'), findsOneWidget);
    expect(find.textContaining(snapshotName), findsOneWidget);
  });

  testWidgets('بوابة بلا لقطة (الجيل القديم) → لا زر تراجع إطلاقاً',
      (tester) async {
    final hasher =
        PasswordHasher(iterations: PasswordHasher.legacyIterations);
    final salt = PasswordHasher.newSalt();
    final stored = '$salt:${hasher.hash(password, salt)}';
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: stored);
    await db.customStatement(
        "INSERT INTO app_meta (key, value) VALUES ('restore.gate', ?)",
        ['{"at":"2026-11-14T08:00:00.000Z","source":"b.dqk",'
            '"attempts":0,"locked":false}']);
    await open(tester);

    expect(find.text('تراجع عن الاستعادة'), findsNothing);
  });

  testWidgets('اجتياز البوابة يسلّح النافذة بخط أساس سجل الأحداث',
      (tester) async {
    final snapshotName = await seedGateWithSnapshot();
    await open(tester);

    // درس س125 الموثق: القائمة الكسولة فما تحت الخط لا يُبنى — بطاقة
    // التراجع تُنزل زر الدخول فالتمرير الصريح قبل النقر واجب.
    await tester.scrollUntilVisible(find.text('دخول'), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('دخول'));
    // س219: التحقق بعزل الخلفية — استطلاع بنوافذ واقعية حتى زر المتابعة
    // (نمط الملف الموثق — درس CI الجولة 128 ودرس الجولة الحاكمة #443)
    var armed = false;
    for (var i = 0; i < 60 && !armed; i++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      armed = find.text('متابعة').evaluate().isNotEmpty;
    }
    expect(armed, isTrue,
        reason: 'ملخص الاجتياز لم يظهر خلال مهلة النوافذ الواقعية');
    await tester.tap(find.text('متابعة'));
    await tester.pump(const Duration(milliseconds: 200));

    final w = await db.rollbackWindow();
    expect(w, isNotNull);
    expect(w!.snapshotFileName, snapshotName);
    expect(w.closed, isFalse);
    expect(w.baselineEventId, greaterThan(0));
    // خط الأساس يسبق أي كتابة قادمة: حدث جديد بعده يغلق فعلاً.
    await db.recordSystemEvent('draft_created');
    final closed = await db.rollbackWindow();
    expect(closed!.closed, isTrue);
  });

  testWidgets('التراجع يمشي مسار الاستعادة ذاته: تأكيد مزدوج ثم لقطة جديدة',
      (tester) async {
    final snapshotName = await seedGateWithSnapshot();
    await open(tester);

    await tester.tap(find.text('تراجع عن الاستعادة'));
    await tester.pump(const Duration(milliseconds: 300));

    // تأكيد الاستعادة الأول (المسار المشترك القائم — لا مسار خاص)
    // — واسم اللقطة يظهر بموضعين: بطاقة النافذة وحوار التأكيد.
    expect(find.text('تأكيد الاستعادة'), findsOneWidget);
    expect(find.textContaining(snapshotName), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, 'استعادة'));
    // prepareRestore وapplyRestore I/O ملفي حقيقي — استطلاع بنوافذ
    // runAsync حتى يظهر حوار النجاح (نمط widget_test الموثق —
    // درس CI الجولة 128: لا pumpAndSettle ولا نافذة واحدة).
    var shown = false;
    for (var i = 0; i < 60 && !shown; i++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      shown = find.text('تمت الاستعادة').evaluate().isNotEmpty;
    }
    expect(shown, isTrue,
        reason: 'حوار نجاح التراجع لم يظهر خلال مهلة الاختبار');
    await tester.tap(find.text('متابعة'));
    await tester.pump(const Duration(milliseconds: 200));

    // الاستعادة الجديدة تزرع بوابتها بلقطتها الخاصة (تعود لآخر استعادة).
    final fresh = DiqqahDatabase.fileSyncClose(filePath: dbPath);
    final gate = await fresh.restoreGate();
    expect(gate, isNotNull);
    expect(gate!.snapshot, isNotNull);
    expect(gate.snapshot, isNot(snapshotName));
    expect(
        beforeRestoreSnapshotPattern.hasMatch(gate.snapshot!), isTrue);
    await fresh.close();
  });
}
