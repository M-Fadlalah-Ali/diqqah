/// اختبار نافذة التراجع والأرضية على كتالوج النسخ (د-3/د-4 — §25.7/§25.8،
/// س136): لافتة النافذة المفتوحة بزر التراجع، ورسالة «لا تراجع بعد الآن»
/// بعد أول كتابة، وحماية أرضية النسخة الوحيدة/الأحدث من الحذف،
/// والتأكيد المزدوج للحذف المُدار.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/backups_catalog_screen.dart';

import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  const password = 'cat-123';

  late Directory tempDir;
  late String dbPath;
  late DiqqahDatabase db;
  late GfsBackupStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_cat_rb_t_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase.fileSyncClose(
        filePath: dbPath,
        passwordUpgradeIterations: PasswordHasher.legacyIterations);
    final hasher =
        PasswordHasher(iterations: PasswordHasher.legacyIterations);
    final salt = PasswordHasher.newSalt();
    final stored = '$salt:${hasher.hash(password, salt)}';
    final userId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: stored);
    await db.setCurrentUserId(userId); // جلسة مدير — حرس المجال مفتوح.
    store = await GfsBackupStore.open(
      backupsDir: Directory(p.join(tempDir.path, 'backups')),
      dbDir: tempDir,
      deviceIdFull: await db.deviceId(),
      schemaVersion: DiqqahDatabase.schemaVersionValue,
      appVersion: 'test',
    );
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// ساعتان: الأقدم (9:00) قابلة للحذف، والأحدث (10:00) أرضية.
  /// الأسماء تُحسب بمعرّف الجهاز الفعلي (يولَّد عشوائياً) لا بالافتراض.
  late String olderName;
  late String newestName;

  Future<void> seedTwoHourlies() async {
    final tag = backupDeviceTag(await db.deviceId());
    olderName = scheduledBackupFileName(
        kind: BackupScheduleKind.hourly,
        deviceTag: tag,
        atUtc: DateTime.utc(2026, 11, 14, 9));
    newestName = scheduledBackupFileName(
        kind: BackupScheduleKind.hourly,
        deviceTag: tag,
        atUtc: DateTime.utc(2026, 11, 14, 10));
    await store.createScheduled(db, BackupScheduleKind.hourly,
        atUtc: DateTime.utc(2026, 11, 14, 9));
    await store.createScheduled(db, BackupScheduleKind.hourly,
        atUtc: DateTime.utc(2026, 11, 14, 10));
  }

  /// نمط widget_test الموثق (درس CI الجولة 128): I/O الملفات الحقيقي
  /// داخل المنطقة الزائفة يكتمل بنوافذ runAsync متتالية مع ضخ حتى
  /// يتحقق الشرط — مهلة 60×50ms — لا نافذة واحدة ولا pumpAndSettle.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: BackupsCatalogScreen(
            db: db, dbPath: dbPath, onRestored: () {})));
    for (var i = 0; i < 60; i++) {
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('نافذة مفتوحة → لافتة بزر تراجع وبيان سريانها',
      (tester) async {
    await tester.runAsync(() => seedTwoHourlies());
    final snapshotName = 'diqqah-before-restore-20261114-080000-000.db';
    db.customStatement(
        "VACUUM INTO '${p.join(tempDir.path, snapshotName)}'");
    await db.armRollbackWindow(snapshotFileName: snapshotName);

    await open(tester);

    expect(find.text('نافذة التراجع مفتوحة'), findsOneWidget);
    expect(find.text('تراجع عن آخر استعادة'), findsOneWidget);
    expect(find.textContaining('أول عملية كتابة'), findsOneWidget);
    // اللقطة المثبتة تُوسم على صفها في لقطات الحدث.
    expect(find.textContaining('مثبتة'), findsOneWidget);
  });

  testWidgets('أول كتابة أغلقت النافذة → الرسالة الصريحة بلا زر',
      (tester) async {
    await tester.runAsync(() => seedTwoHourlies());
    final snapshotName = 'diqqah-before-restore-20261114-080000-000.db';
    db.customStatement(
        "VACUUM INTO '${p.join(tempDir.path, snapshotName)}'");
    await db.armRollbackWindow(snapshotFileName: snapshotName);
    await db.recordSystemEvent('draft_created'); // أول كتابة

    await open(tester);

    expect(find.textContaining('لا تراجع بعد الآن'), findsOneWidget);
    expect(find.text('تراجع عن آخر استعادة'), findsNothing);
  });

  testWidgets('بلا نافذة أصلاً → لا لافتة إطلاقاً', (tester) async {
    await tester.runAsync(() => seedTwoHourlies());
    await open(tester);
    expect(find.text('نافذة التراجع مفتوحة'), findsNothing);
    expect(find.textContaining('لا تراجع بعد الآن'), findsNothing);
  });

  testWidgets('أرضية النسخة الأحدث: بلا فعل حذف وبوسم حماية على صفها',
      (tester) async {
    await tester.runAsync(() => seedTwoHourlies());
    await open(tester);

    // سحب واحد حتى أسفل القائمة مع الاستقرار الكامل — القائمة الكسولة
    // (درس س125) وزخم السحب يجب أن يهدأ قبل النقر (pumpAndSettle).
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(newestName).first);
    // استقرار انزلاق حوار السفلى كاملاً قبل النقر داخله — منتصف
    // الانزلاق يجعل إحداثيات النقر خارج حدود الشجرة (درس هذه الجلسة).
    await tester.pumpAndSettle();
    expect(find.text('حذف (مدير)'), findsNothing);
    // الحماية بلاطين الصف وبقائمة الأفعال معاً.
    expect(find.textContaining('محمية'), findsNWidgets(2));
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();

    // فتح أفعال الأقدم: الحذف متاح — الموضع مستقر من السحب الأول.
    await tester.tap(find.textContaining(olderName).first);
    await tester.pumpAndSettle();
    expect(find.text('حذف (مدير)'), findsOneWidget);
  });

  testWidgets('الحذف المُدار بتأكيد مزدوج: المحرَّم لا يُحذف قبل الاثنين',
      (tester) async {
    await tester.runAsync(() => seedTwoHourlies());
    await open(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(olderName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف (مدير)'));
    await tester.pumpAndSettle();

    // التأكيد الأول: توثيق الحذف — والملف ما يزال حاضراً.
    expect(find.text('حذف نسخة احتياطية'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    // التأكيد النهائي: بعده فقط ينفَّذ.
    expect(find.text('تأكيد نهائي'), findsOneWidget);
    expect(File(p.join(tempDir.path, 'backups', olderName)).existsSync(),
        isTrue);
    await tester.tap(find.text('نعم، احذف الآن'));
    // التنفيذ I/O ملفي حقيقي — استطلاع بنوافذ runAsync حتى يزول الملف
    // (نمط widget_test الموثق — درس CI الجولة 128).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (!File(p.join(tempDir.path, 'backups', olderName))
          .existsSync()) break;
    }

    expect(File(p.join(tempDir.path, 'backups', olderName)).existsSync(),
        isFalse);
    // الأرضية باقية لم تُمس.
    expect(
        File(p.join(tempDir.path, 'backups', newestName)).existsSync(),
        isTrue);
  });
}
