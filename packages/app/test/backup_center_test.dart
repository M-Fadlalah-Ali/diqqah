/// اختبار مركز النسخ (تكليف 2026-11-13): اللحاق بنسخة واحدة، تخطي
/// السارية ببطارية منخفضة (ق-ن2)، السنوية لا تدور أبداً، وشارات
/// الصحة (30 يوماً/المرفقات) — كلها بحقن الساعة والبطارية.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/backup_center.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late DiqqahDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_center_t_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase.fileSyncClose(filePath: dbPath);
  });

  tearDown(() async {
    await BackupCenter.instance?.shutdown();
    BackupCenter.instance = null;
    try {
      await db.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Directory backupsDir() => Directory(p.join(tempDir.path, 'backups'));

  List<String> dqkFiles() => backupsDir().existsSync()
      ? backupsDir()
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((n) => n.endsWith('.dqk'))
          .toList()
      : const <String>[];

  /// بذر الكتالوج قبل بدء المركز — يمر عبر المخزن نفسه فيقرأه المركز.
  Future<void> seedCatalog(Map<BackupScheduleKind, DateTime> success) async {
    final seed = await GfsBackupStore.open(
      backupsDir: backupsDir(),
      dbDir: tempDir,
      deviceIdFull: await db.deviceId(),
      schemaVersion: DiqqahDatabase.schemaVersionValue,
      appVersion: 'test',
    );
    for (final e in success.entries) {
      seed.catalog.recordSuccess(e.key, e.value);
    }
    await seed.saveCatalog();
  }

  Future<BackupCenter> startCenter({
    required DateTime nowUtc,
    required DateTime nowLocal,
    Future<int?> Function()? battery,
  }) =>
      BackupCenter.start(
        db: db,
        dbPath: dbPath,
        nowUtcProvider: () => nowUtc,
        nowLocalProvider: () => nowLocal,
        batteryProvider: battery ?? (() async => null),
        scheduleTimer: false,
      );

  test('اللحاق: اليومية والسارية محدّثتان لا تُنسخان — الأسبوعية والشهرية فقط',
      () async {
    final nowUtc = DateTime.utc(2026, 11, 13, 10, 0);
    final nowLocal = DateTime(2026, 11, 13, 12, 0); // الجمعة
    // السارية قبل 30 دقيقة واليومية اليوم ذاته 00:05 محلياً: بلا نسخ
    // جديدة لهما؛ الأسبوعية والشهرية بلا تاريخ: نسخة واحدة لكل منهما
    // (اللحاق لا يعوّض الفائت أبداً — §8-1).
    await seedCatalog({
      BackupScheduleKind.hourly: DateTime.utc(2026, 11, 13, 9, 30),
      BackupScheduleKind.daily: DateTime.utc(2026, 11, 13, 0, 5),
    });
    await startCenter(
      nowUtc: nowUtc,
      nowLocal: nowLocal,
      battery: () async => 100,
    );
    final names = dqkFiles();
    expect(names.where((n) => n.startsWith('diqqah-h-')).length, 0);
    expect(names.where((n) => n.startsWith('diqqah-d-')).length, 0);
    expect(names.where((n) => n.startsWith('diqqah-w-')).length, 1);
    expect(names.where((n) => n.startsWith('diqqah-m-')).length, 1);
  });

  test('ق-ن2: بطارية 15% تتخطى السارية بلا فشل — ولا تنسخ شيئاً آخر', () async {
    final center = await startCenter(
      nowUtc: DateTime.utc(2026, 11, 13, 10),
      nowLocal: DateTime(2026, 11, 13, 12),
      battery: () async => 15,
    );
    expect(dqkFiles().where((n) => n.startsWith('diqqah-h-')).length, 0);
    expect(center.health.value?.hourlySkippedBattery, isTrue);
  });

  test('السارية المستحقة ببطارية سليمة تُنسخ فعلاً', () async {
    await startCenter(
      nowUtc: DateTime.utc(2026, 11, 13, 10),
      nowLocal: DateTime(2026, 11, 13, 12),
      battery: () async => 80,
    );
    expect(dqkFiles().where((n) => n.startsWith('diqqah-h-')).length, 1);
  });

  test('السنوية لا تدور أبداً: ست نسخ كلها باقية بأسماء متمايزة', () async {
    // ساعة تتقدم دقيقة لكل استدعاء — سنويات متتالية بأختام متمايزة
    // (الإقفال الفعلي مرة بالسنة فالتمييز محقون للاختبار حصراً).
    var minute = 0;
    final center = await BackupCenter.start(
      db: db,
      dbPath: dbPath,
      nowUtcProvider: () => DateTime.utc(2026, 11, 13, 10, ++minute),
      nowLocalProvider: () => DateTime(2026, 11, 13, 12),
      batteryProvider: () async => 80,
      scheduleTimer: false,
    );
    for (var i = 0; i < 6; i++) {
      await center.createAnnualBackup();
    }
    expect(dqkFiles().where((n) => n.startsWith('diqqah-y-')).length, 6);
    expect(
        center.store!.catalog.entriesFor(BackupScheduleKind.annual).length,
        6);
  });

  test('شارة الصحة: بلا أي نسخة في الكتالوج → تذكير 30 يوماً مستحق',
      () async {
    final center = await startCenter(
      nowUtc: DateTime.utc(2026, 11, 13, 10),
      nowLocal: DateTime(2026, 11, 13, 12),
      battery: () async => 80,
    );
    // نسخ اليوم موجودة → لا تذكير (center مستعمل في الفرع الثاني).
    expect(center.health.value?.noBackupFor30Days, isFalse);
    // كتالوج أُفرغ (محاكاة قاعدة بلا تاريخ نسخ) → التذكير مستحق فور
    // إعادة الحساب — نفس الحساب الذي يجريه المركز بعد كل نسخة.
    center.store!.catalog = BackupCatalog();
    await center.refreshHealth();
    expect(center.health.value?.noBackupFor30Days, isTrue);
  });

  test('دفعة 2: الشارة تحمل أحدث نسخة تضم المرفقات — لسان الواجهة الأغنى',
      () async {
    // مجلد صور فيه ملف واحد فعلي — وإلا فلا ملف مجاور فلا علم
    // includesImages على صف الكتالوج (التحقق على ما خُزّن لا ما قيل).
    final imagesDir = Directory(p.join(tempDir.path, 'images'));
    await imagesDir.create();
    await File(p.join(imagesDir.path, 'item-01.png'))
        .writeAsBytes(List.filled(16, 0xFF));
    final center = await startCenter(
      nowUtc: DateTime.utc(2026, 11, 13, 10),
      nowLocal: DateTime(2026, 11, 13, 12),
      battery: () async => 80,
    );
    // الدورية بيانات فقط → لا نسخة تضم المرفقات بعد.
    expect(center.health.value?.latestWithImagesUtc, isNull);
    // السنوية عند الإقفال تضم المرفقات → تاريخها في الشارة فوراً —
    // نفس المسار الذي يغذي رسالة تذكير المرفقات بتاريخها الحي.
    await center.createAnnualBackup();
    expect(center.health.value?.latestWithImagesUtc, isNotNull);
    expect(center.health.value?.latestWithImagesUtc,
        center.store!.catalog.latestWithImagesUtc());
  });
}
