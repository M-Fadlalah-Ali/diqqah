/// اختبار منفذ GFS وآلة بوابة الاستعادة (تكليف 2026-11-13:
/// ق-ن4 التدرج، ق-ن5 الكتالوج الجانبي، §5-4/5-5 البوابة، §6 الملخص).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late DiqqahDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_gfs_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<GfsBackupStore> openStore() => GfsBackupStore.open(
        backupsDir: Directory(p.join(tempDir.path, 'backups')),
        dbDir: tempDir,
        deviceIdFull: '123e4567-e89b-12d3-a456-426614174000',
        schemaVersion: DiqqahDatabase.schemaVersionValue,
        appVersion: 'test',
      );

  group('ق-ن4: التحقق المتدرج', () {
    test('الساعية: فك + ترويسة + بصمة SHA-256 متطابقة مع الإنشاء', () async {
      final store = await openStore();
      final entry = await store.createScheduled(
        db,
        BackupScheduleKind.hourly,
        atUtc: DateTime.utc(2026, 11, 13, 10),
      );
      expect(entry.verifyState, BackupVerifyState.quick);
      final path = p.join(tempDir.path, 'backups', entry.fileName);
      final q = await store.verifyQuick(path);
      expect(q.ok, isTrue);
      expect(q.sha256Hex, entry.sha256Hex);
      expect(q.schemaVersion, DiqqahDatabase.schemaVersionValue);
    });

    test('اليومية: تحقق كامل integrity_check ناجح', () async {
      final store = await openStore();
      final entry = await store.createScheduled(
        db,
        BackupScheduleKind.daily,
        atUtc: DateTime.utc(2026, 11, 13, 10),
      );
      expect(entry.verifyState, BackupVerifyState.full);
      final path = p.join(tempDir.path, 'backups', entry.fileName);
      final f = await store.verifyFull(path);
      expect(f.ok, isTrue);
      expect(f.state, BackupVerifyState.full);
    });

    test('عبث بايت → يرفض السريع والكامل بلا استثناء (وسم GCM)', () async {
      final store = await openStore();
      final entry = await store.createScheduled(
        db,
        BackupScheduleKind.daily,
        atUtc: DateTime.utc(2026, 11, 13, 10),
      );
      final path = p.join(tempDir.path, 'backups', entry.fileName);
      final bytes = await File(path).readAsBytes();
      bytes[bytes.length - 3] ^= 0x40;
      await File(path).writeAsBytes(bytes, flush: true);
      final q = await store.verifyQuick(path);
      expect(q.ok, isFalse);
      expect(q.state, BackupVerifyState.failed);
      final f = await store.verifyFull(path);
      expect(f.ok, isFalse);
    });

    test('ملف ليس نسخة → فشل صريح لا انهيار', () async {
      final junk = p.join(tempDir.path, 'junk.dqk');
      await File(junk).writeAsBytes(List.filled(64, 65), flush: true);
      final store = await openStore();
      final q = await store.verifyQuick(junk);
      expect(q.ok, isFalse);
    });
  });

  group('ق-ن5: الكتالوج الجانبي وإعادة البناء بالمسح', () {
    test('التسمية D-207 على القرص + الصف بالكتالوج', () async {
      final store = await openStore();
      final entry = await store.createScheduled(
        db,
        BackupScheduleKind.weekly,
        atUtc: DateTime.utc(2026, 11, 13, 10, 15, 30),
      );
      expect(entry.fileName,
          'diqqah-w-123e4567-20261113T101530Z.dqk');
      expect(
          await File(
                  p.join(tempDir.path, 'backups', entry.fileName))
              .exists(),
          isTrue);
      expect(store.catalog.entriesFor(BackupScheduleKind.weekly).length, 1);
      expect(
          store.catalog.lastSuccess[BackupScheduleKind.weekly],
          DateTime.utc(2026, 11, 13, 10, 15, 30));
    });

    test('إعادة فتح تعيد البناء: ملف محذوف خارجياً يسقط وغريب يدخل بلا تحقق',
        () async {
      final store = await openStore();
      final e1 = await store.createScheduled(db, BackupScheduleKind.hourly,
          atUtc: DateTime.utc(2026, 11, 13, 9));
      // حذف خارجي + ملف مجهول التسمية بديل.
      File(p.join(tempDir.path, 'backups', e1.fileName)).deleteSync();
      final stray = p.join(
          tempDir.path, 'backups', 'diqqah-h-123e4567-20261113T093000Z.dqk');
      await File(stray).writeAsBytes(List.filled(32, 1), flush: true);
      final reloaded = await openStore();
      expect(
          reloaded.catalog.entries
              .where((e) => e.fileName == e1.fileName)
              .isEmpty,
          isTrue);
      final strayEntry = reloaded.catalog.entries
          .where((e) => e.fileName == p.basename(stray))
          .first;
      expect(strayEntry.verifyState, BackupVerifyState.none);
    });

    test('الرتابة عبر الجلسات: النجاح المسجل لا يتراجع بإعادة الفتح',
        () async {
      final store = await openStore();
      store.catalog.recordSuccess(
          BackupScheduleKind.daily, DateTime.utc(2026, 11, 13, 8));
      await store.saveCatalog();
      final reloaded = await openStore();
      reloaded.catalog.recordSuccess(
          BackupScheduleKind.daily, DateTime.utc(2026, 11, 12, 8));
      expect(reloaded.catalog.lastSuccess[BackupScheduleKind.daily],
          DateTime.utc(2026, 11, 13, 8));
    });
  });

  group('التدوير بعد نجاح الجديدة (ق-ن4: لا حذف قبل تحقق كامل)', () {
    test('16 ساعية على القرص → الأقدم يسقط ويبقى 15', () async {
      final store = await openStore();
      for (var i = 15; i >= 0; i--) {
        await store.createScheduled(
          db,
          BackupScheduleKind.hourly,
          atUtc: DateTime.utc(2026, 11, 13, 15 - i),
        );
      }
      final files = Directory(p.join(tempDir.path, 'backups'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dqk'))
          .map((f) => p.basename(f.path))
          .toList();
      expect(files.length, 15);
      expect(files.contains('diqqah-h-123e4567-20261113T000000Z.dqk'),
          isFalse); // الأقدم حُذف.
      expect(files.contains('diqqah-h-123e4567-20261113T150000Z.dqk'),
          isTrue); // الأحدث بقي.
      expect(store.catalog.entriesFor(BackupScheduleKind.hourly).length, 15);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('ق-ن3: تقليم السقف يمس التلقائية فوق الأرضية حصراً (د-4)',
        () async {
      final store = await openStore();
      await store.createScheduled(db, BackupScheduleKind.annual,
          atUtc: DateTime.utc(2026, 1, 1));
      await store.createScheduled(db, BackupScheduleKind.hourly,
          atUtc: DateTime.utc(2026, 11, 13, 9));
      await store.createScheduled(db, BackupScheduleKind.hourly,
          atUtc: DateTime.utc(2026, 11, 13, 10));
      await store.createScheduled(db, BackupScheduleKind.daily,
          atUtc: DateTime.utc(2026, 11, 13, 11));
      final usage = await store.usageBytes();
      final annualName = store.catalog
          .entriesFor(BackupScheduleKind.annual)
          .first
          .fileName;
      // سقف يضيق حتى لا يتسع للكل: التقليم يسقط الأقدم التلقائية فقط —
      // وأحدث الساعية واليومية الوحيدة أرضية لا تُمس تحت ضغط السقف
      // (د-4/س136) فالسنوية تبقى وما فوق الأرضية وحده يُحذف.
      final deleted = await store.trimToQuota(
          capBytes: usage, incomingBytes: 1);
      expect(deleted, greaterThan(0));
      expect(
          File(p.join(tempDir.path, 'backups', annualName)).existsSync(),
          isTrue);
      expect(deleted, 1); // أقدم الساعية وحدها — البقية أرضية.
      final hourly = store.catalog.entriesFor(BackupScheduleKind.hourly);
      expect(hourly, hasLength(1));
      expect(hourly.single.atUtc, DateTime.utc(2026, 11, 13, 10));
    });
  });

  group('اليدوية واللقطات الممسوحة (تكليف §8-9/§8-10)', () {
    test('registerManual يتبنى نسخة D-061 بتحقق سريع', () async {
      final target = p.join(
          tempDir.path, 'diqqah-backup-20261113-100000-000.diqqah');
      await backupTo(db, target);
      final store = await openStore();
      final entry =
          await store.registerManual(target, includesImages: false);
      expect(entry.kind, BackupScheduleKind.manual);
      expect(entry.folderId, 'db');
      expect(entry.verifyState, BackupVerifyState.quick);
    });

    test('scanSnapshots يري لقطات preup/قبل-استعادة الموجودة', () async {
      // س216: العزل الخلفي يجعل customStatement غير متزامناً فعلاً —
      // فالانتظار إلزامي (كان يعمل بلا انتظار لأن التنفيذ على العزل
      // الرئيسي كان متزامناً — نمط مزيل السبق الموثق).
      await db.customStatement(
          "VACUUM INTO '${p.join(tempDir.path, 'diqqah.db.preup27')}'");
      await db.customStatement(
          "VACUUM INTO '${p.join(tempDir.path, 'diqqah-before-restore-1.db')}'");
      final store = await openStore();
      final rows = await store.scanSnapshots();
      expect(
          rows.where((r) => r.typeLabel == 'قبل ترقية المخطط').length, 1);
      expect(rows.where((r) => r.typeLabel == 'قبل استعادة').length, 1);
    });

    test('rotateBeforeRestoreSnapshots يبقي آخر 5 بعد تحقق كامل', () async {
      for (var i = 0; i < 7; i++) {
        // س216: الانتظار إلزامي بعزل الخلفية (فوق).
        await db.customStatement(
            "VACUUM INTO '${p.join(tempDir.path, 'diqqah-before-restore-$i.db')}'");
      }
      final store = await openStore();
      final deleted = await store.rotateBeforeRestoreSnapshots();
      expect(deleted, 2);
      final remaining = Directory(tempDir.path)
          .listSync()
          .whereType<File>()
          .where((f) =>
              beforeRestoreSnapshotPattern.hasMatch(p.basename(f.path)))
          .length;
      expect(remaining, 5);
      // الأحدث (6) بقي والأقدم (0/1) سقط.
      expect(
          File(p.join(tempDir.path, 'diqqah-before-restore-6.db'))
              .existsSync(),
          isTrue);
      expect(
          File(p.join(tempDir.path, 'diqqah-before-restore-0.db'))
              .existsSync(),
          isFalse);
    });
  });

  group('§5-4/§5-5: البوابة وحقائق الملخص', () {
    test('applyRestore يمسح الجلسة ويزرع البوابة ويحفظ المصدر', () async {
      // جلسة قائمة قبل الاستعادة + مستخدم مدير للبوابة بعدها.
      final roles = await db.select(db.roles).get();
      final managerRole = roles.firstWhere((r) => r.name == 'مدير');
      await db.into(db.appUsers).insert(AppUsersCompanion.insert(
            name: 'المالك',
            login: 'owner',
            passwordHash: 'x:y',
            roleId: managerRole.id,
            isActive: true,
            uuid: 'uuid-owner-1',
          ));
      await db.setCurrentUserId(managerRole.id);
      expect(await db.currentUserId(), managerRole.id);

      final target = p.join(tempDir.path, 'diqqah-backup-src.diqqah');
      await backupTo(db, target);
      final candidate = await prepareRestore(
        target,
        appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      );
      await applyRestore(
        db: db,
        candidate: candidate,
        currentDbPath: dbPath,
        sourcePath: target,
      );
      candidate.dispose();

      // الإقلاع التالي يفتح القاعدة المستعادة — نعيد فتحها كما يفعل.
      db = DiqqahDatabase(filePath: dbPath);
      expect(await db.currentUserId(), isNull);
      final gate = await db.restoreGate();
      expect(gate, isNotNull);
      expect(gate!.source, target);
      expect(gate.attempts, 0);
      expect(gate.locked, isFalse);
    });

    test('آلة المحاولات: الخامسة تقفل والإعادة تصفّر والمسح يزيل', () async {
      final target = p.join(tempDir.path, 'diqqah-backup-src2.diqqah');
      await backupTo(db, target);
      final candidate = await prepareRestore(
        target,
        appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      );
      await applyRestore(
        db: db,
        candidate: candidate,
        currentDbPath: dbPath,
        sourcePath: target,
      );
      candidate.dispose();
      db = DiqqahDatabase(filePath: dbPath);

      var n = 0;
      for (var i = 0; i < 5; i++) {
        n = await db.bumpRestoreGateAttempts();
      }
      expect(n, 5);
      expect((await db.restoreGate())!.locked, isTrue);
      // البوابة المقفلة لا تزيد محاولات أكثر (كل زيادة لا أثر).
      expect(await db.bumpRestoreGateAttempts(), 6);
      await db.resetRestoreGateAttempts();
      final after = await db.restoreGate();
      expect(after!.locked, isFalse);
      expect(after.attempts, 0);
      await db.clearRestoreGate();
      expect(await db.restoreGate(), isNull);
    });

    test('recordSystemEvent يكتب حدثاً بنمط الأحداث القائم', () async {
      await db.recordSystemEvent('restore_performed',
          userId: 7, payload: {'source': 'x.dqk', 'result': 'success'});
      final rows = await (db.select(db.events)
            ..where((t) => t.entityType.equals('system')))
          .get();
      expect(rows.length, 1);
      expect(rows.single.action, 'restore_performed');
      expect(rows.single.userId, 7);
    });

    test('اسم الجهاز يُكتب ويُقرأ والفراغ يسقط null', () async {
      expect(await db.deviceName(), isNull);
      await db.setDeviceName('جهاز المحاسبة-1');
      expect(await db.deviceName(), 'جهاز المحاسبة-1');
    });

    test('حقائق الملخص: مستخدم واحد بلا مستندات', () async {
      final roles = await db.select(db.roles).get();
      final managerRole = roles.firstWhere((r) => r.name == 'مدير');
      await db.into(db.appUsers).insert(AppUsersCompanion.insert(
            name: 'المالك',
            login: 'owner',
            passwordHash: 'x:y',
            roleId: managerRole.id,
            isActive: true,
            uuid: 'uuid-owner-2',
          ));
      final facts = await db.restoreSummaryFacts();
      expect(facts.usersCount, 1);
      expect(facts.invoicesCount, 0);
      expect(facts.lastDocumentDateText, isNull);
    });
  });

  group('متجهات إضافية', () {
    test('backupTo يعيد بصمة النص الصريح (ق-ن4)', () async {
      final target = p.join(tempDir.path, 'b-sha.diqqah');
      final sha = await backupTo(db, target);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sha), isTrue);
      // والبصمة تطابق تحقيق النسخة ذاتها.
      final store = await openStore();
      final q = await store.verifyQuick(target);
      expect(q.sha256Hex, sha);
    });
  });

  group('الأرضية النظامية وتثبيت اللقطة (د-3/د-4 — س136)', () {
    test('deleteBackupManually يرفض آخر نسخة من نوعها (الأرضية)', () async {
      final store = await openStore();
      final older = await store.createScheduled(db,
          BackupScheduleKind.hourly, atUtc: DateTime.utc(2026, 11, 14, 8));
      final newest = await store.createScheduled(db,
          BackupScheduleKind.hourly, atUtc: DateTime.utc(2026, 11, 14, 9));
      // حذف الأرضية (أحدث الساعية) رفض حائط صلب.
      await expectLater(
        store.deleteBackupManually(
            fileName: newest.fileName, folderId: 'backups'),
        throwsA(isA<GfsBackupException>()),
      );
      // وما عداها يحذف فعلاً: الملف يزول والصف يسقط.
      await store.deleteBackupManually(
          fileName: older.fileName, folderId: 'backups');
      expect(
          File(p.join(tempDir.path, 'backups', older.fileName))
              .existsSync(),
          isFalse);
      expect(store.catalog.entries
          .where((e) => e.fileName == older.fileName), isEmpty);
    });

    test('اليدوية الوحيدة أرضية رفضاً، والسنوية كذلك حتى هي', () async {
      final store = await openStore();
      final target = p.join(tempDir.path,
          'diqqah-backup-20261114-080000-000.diqqah');
      await backupTo(db, target);
      await store.registerManual(target, includesImages: false);
      await expectLater(
        store.deleteBackupManually(
            fileName: p.basename(target), folderId: 'db'),
        throwsA(isA<GfsBackupException>()),
      );
    });

    test('rotateBeforeRestoreSnapshots يستثني اللقطة المثبتة (د-3-2)',
        () async {
      for (var i = 0; i < 7; i++) {
        // س216: الانتظار إلزامي بعزل الخلفية (فوق).
        await db.customStatement(
            "VACUUM INTO '${p.join(tempDir.path, 'diqqah-before-restore-$i.db')}'");
      }
      final store = await openStore();
      // تثبيت الأقدم (0) بنافذة مفتوحة: من آخر-5 المحذوفين هو وحده.
      final deleted = await store.rotateBeforeRestoreSnapshots(
          protectFileName: 'diqqah-before-restore-0.db');
      expect(deleted, 1);
      expect(
          File(p.join(tempDir.path, 'diqqah-before-restore-0.db'))
              .existsSync(),
          isTrue); // المثبتة باقية ولو كانت أقدم الخمسة الزائدين.
      expect(
          File(p.join(tempDir.path, 'diqqah-before-restore-1.db'))
              .existsSync(),
          isFalse);
    });

    test('applyRestore يزرع لقطة ما قبل الاستعادة بمفتاح البوابة',
        () async {
      final target = p.join(tempDir.path, 'diqqah-backup-src3.diqqah');
      await backupTo(db, target);
      final candidate = await prepareRestore(
        target,
        appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      );
      await applyRestore(
        db: db,
        candidate: candidate,
        currentDbPath: dbPath,
        sourcePath: target,
      );
      candidate.dispose();
      db = DiqqahDatabase(filePath: dbPath);
      final gate = await db.restoreGate();
      expect(gate, isNotNull);
      // د-3: الاسم بالنمط القائم والملف حاضر بمجلد القاعدة — هو لقطة
      // ما قبل الاستعادة التي ستثبتها نافذة التراجع بعد اجتياز البوابة.
      expect(gate!.snapshot, isNotNull);
      expect(
          beforeRestoreSnapshotPattern.hasMatch(gate.snapshot!), isTrue);
      expect(
          File(p.join(tempDir.path, gate.snapshot!)).existsSync(), isTrue);
    });
  });

  group('P1-أ (س149): النسخ المجدولة المقفلة والتحقق بأسرار الخزنة', () {
    Future<GfsBackupStore> openLockedStore({
      Future<BackupLock?> Function()? loadLock,
    }) =>
        GfsBackupStore.open(
          backupsDir: Directory(p.join(tempDir.path, 'backups')),
          dbDir: tempDir,
          deviceIdFull: '123e4567-e89b-12d3-a456-426614174000',
          schemaVersion: DiqqahDatabase.schemaVersionValue,
          appVersion: 'test',
          loadLock: loadLock,
        );

    test('قفل موجود: النسخة المجدولة تُكتب v3 والتحقق الكامل ينجح بأسراره',
        () async {
      const lock = BackupLock(
          password: 'كلمة-الجدولة', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
      final store = await openLockedStore(loadLock: () async => lock);
      final entry = await store.createScheduled(
        db,
        BackupScheduleKind.daily,
        atUtc: DateTime.utc(2026, 11, 16, 9),
      );
      final path = p.join(tempDir.path, 'backups', entry.fileName);
      final bytes = await File(path).readAsBytes();
      expect(bytes[7], BackupCipher.lockedFormatVersion);
      final full = await store.verifyFull(path);
      expect(full.ok, isTrue);
      expect(full.state, BackupVerifyState.full);
      expect(full.schemaVersion, DiqqahDatabase.schemaVersionValue);
    });

    test('بلا أسرار محمّلة: النسخة المقفلة يرفض التحقق صراحةً — لا صمت',
        () async {
      // الإنشاء بقفل موجود = v3، والتحقق بمستودع فُتح بلا أسرار
      // (خزنة ضائعة مثلاً) = رفض صريح لا فشل غامض ولا سكات.
      const lock = BackupLock(
          password: 'كلمة-الجدولة', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
      final creator = await openLockedStore(loadLock: () async => lock);
      final entry = await creator.createScheduled(
        db,
        BackupScheduleKind.daily,
        atUtc: DateTime.utc(2026, 11, 16, 10),
      );
      final path = p.join(tempDir.path, 'backups', entry.fileName);
      expect((await File(path).readAsBytes())[7],
          BackupCipher.lockedFormatVersion);
      final blind = await openLockedStore(loadLock: () async => null);
      final q = await blind.verifyQuick(path);
      expect(q.ok, isFalse);
      expect(q.state, BackupVerifyState.failed);
      expect(q.reason, contains('مقفلة'));
    });

    test('النسخ المجدولة بلا قفل تبقى v2 — السلوك القائم حرفاً', () async {
      final store = await openStore();
      final entry = await store.createScheduled(
        db,
        BackupScheduleKind.daily,
        atUtc: DateTime.utc(2026, 11, 16, 11),
      );
      final path = p.join(tempDir.path, 'backups', entry.fileName);
      final bytes = await File(path).readAsBytes();
      expect(bytes[7], BackupCipher.formatVersion);
      expect(await store.verifyQuick(path), isA<GfsVerifyOutcome>()
          .having((v) => v.ok, 'ok', isTrue));
    });
  });
}
