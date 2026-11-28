// اختبارات د11 (س229/D-225 الجزء الأول) — توصيل جيل الخزنة v4 بطبقة
// التخزين: الكتابة بأولوية v3 ثم v4 ثم v2 (الانخفاض موثق)، والاستعادة
// بمفتاح الجهاز صامتاً أو برمز الاسترداد على جهاز آخر (N-005 يلتئم)،
// ولقطة ما قبل الاستعادة بجيل الخزنة، والتحقق الحي لمستودع GFS.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late Directory tempDir;
  late DiqqahDatabase db;
  late String dbPath;

  final rootA =
      List<int>.generate(32, (i) => (i * 13 + 29) % 256);
  final rootB =
      List<int>.generate(32, (i) => (i * 17 + 3) % 256);
  const code = 'ABCD-2345-FGHI-6789';
  final vaultA = BackupVaultKeys(rootKey: rootA, recoveryCode: code);
  final cipher = BackupCipher(iterations: 500);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_v4_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
    await db.customStatement('SELECT 1');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('د11: backupTo بماللخزنة وبلا قفل = جيل v4 — والاستعادة بمفتاح '
      'الجهاز ذاته صامتة (بلا أي كلمة)', () async {
    final target = p.join(tempDir.path, 'v4.dqk');
    await backupTo(db, target, vaultKeys: vaultA, cipher: cipher);
    final blob = await File(target).readAsBytes();
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.vaultFormatVersion);
    expect(BackupCipher.isVaulted(blob), isTrue);
    final candidate = await prepareRestore(
      target,
      vaultRootKey: rootA,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    expect(candidate.schemaVersion, DiqqahDatabase.schemaVersionValue);
    candidate.dispose();
  });

  test('د11: جهاز آخر يستعيد بالرمز وحده — N-005 يلتئم بلا كسر',
      () async {
    final target = p.join(tempDir.path, 'cross.dqk');
    await backupTo(db, target, vaultKeys: vaultA, cipher: cipher);
    // بلا مفتاح خزنة (جهاز جديد) — الرمز المكتوب يفتح.
    final candidate = await prepareRestore(
      target,
      recoveryCode: code,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    candidate.dispose();
    // وبمفتاح خزنة الجهاز الآخر يفشل الصامت وينجح بالرمز معاً.
    final candidate2 = await prepareRestore(
      target,
      vaultRootKey: rootB,
      recoveryCode: 'abcd2345fghi6789',
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    candidate2.dispose();
  });

  test('د11: بلا مواد = رفض صريح بلسان الجيل قبل أي لمس للقاعدة',
      () async {
    final target = p.join(tempDir.path, 'locked.dqk');
    await backupTo(db, target, vaultKeys: vaultA, cipher: cipher);
    await expectLater(
      prepareRestore(
        target,
        appSchemaVersion: DiqqahDatabase.schemaVersionValue,
        cipher: cipher,
      ),
      throwsA(isA<BackupCipherException>()
          .having((e) => e.message, 'message', contains('رمز الاسترداد'))),
    );
  });

  test('د11: الأولوية — القفل v3 يتقدم على مواد الخزنة (الكلمة فوق قفل '
      'مفتوح لا معنى لها)، وبمواد الخزنة معاً تُكتب v3 لا v4', () async {
    final target = p.join(tempDir.path, 'prio.dqk');
    const lock = BackupLock(
        password: 'كلمة-القفل-8محارف', recoveryCode: code);
    await backupTo(db, target,
        lock: lock, vaultKeys: vaultA, cipher: cipher);
    final blob = await File(target).readAsBytes();
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.lockedFormatVersion,
        reason: 'v3 المقفل أولوية على v4 — لا سجل مفتاح تحت كلمة');
    final candidate = await prepareRestore(
      target,
      password: lock.password,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    candidate.dispose();
  });

  test('د11: غياب القفل والمواد معاً = v2 بمفتاح البرنامج — الانخفاض '
      'الموثق (سلوك س149 القائم حرفاً)', () async {
    final target = p.join(tempDir.path, 'v2.dqk');
    await backupTo(db, target, cipher: cipher);
    final blob = await File(target).readAsBytes();
    expect(BackupCipher.encryptedVersion(blob),
        BackupCipher.formatVersion);
    final candidate = await prepareRestore(
      target,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    candidate.dispose();
  });

  test('د11: applyRestore يغلّف لقطة ما قبل الاستعادة بجيل v4 — والتراجع '
      'يعمل بمفتاح الخزنة الصامت (د-3)', () async {
    // نسخة خارجية خام (جهاز آخر بلا خزنة) — أبسط مدخل للاستعادة.
    final ext = p.join(tempDir.path, 'external.dqk');
    await backupTo(db, ext, cipher: cipher);
    final candidate = await prepareRestore(
      ext,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    final snapshot = await applyRestore(
      db: db,
      candidate: candidate,
      currentDbPath: dbPath,
      vaultKeys: vaultA,
    );
    candidate.dispose();
    final snapBlob = await File(snapshot).readAsBytes();
    expect(BackupCipher.isVaulted(snapBlob), isTrue,
        reason: 'اللقطة بجيل الخزنة لا نص SQLite صريح');
    // زر التراجع: prepareRestore بمفتاح الخزنة يفتحها صامتاً.
    final rollback = await prepareRestore(
      snapshot,
      vaultRootKey: rootA,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    rollback.dispose();
    // والقاعدة المستعادة تفتح وتعمل (الجهاز يفتح قاعدة سليمة).
    final db2 = DiqqahDatabase(filePath: dbPath);
    await db2.customStatement('SELECT 1');
    await db2.close();
  });

  test('د11: مستودع GFS — createScheduled بمواد الخزنة يكتب v4 والتحقق '
      'الحي يفك بمفتاح الخزنة، وبلا مواد رسالة صريحة لا صمت', () async {
    final backupsDir =
        Directory(p.join(tempDir.path, 'backups'));
    final store = await GfsBackupStore.open(
      backupsDir: backupsDir,
      dbDir: Directory(tempDir.path),
      deviceIdFull: 'test-device-v4',
      schemaVersion: DiqqahDatabase.schemaVersionValue,
      appVersion: '0.279.0+79',
      loadVaultKeys: () async => vaultA,
    );
    final entry = await store.createScheduled(
      db,
      BackupScheduleKind.manual,
      atUtc: DateTime.utc(2026, 11, 28, 12),
    );
    final file = File(p.join(backupsDir.path, entry.fileName));
    expect(BackupCipher.isVaulted(await file.readAsBytes()), isTrue);
    final ok = await store.verifyQuick(file.path);
    expect(ok.ok, isTrue, reason: ok.reason ?? '');

    // وبلا مواد خزنة (خزنة فاشلة) — التحقق يرفض بلسان الجيل لا صمتاً.
    final bare = await GfsBackupStore.open(
      backupsDir: backupsDir,
      dbDir: Directory(tempDir.path),
      deviceIdFull: 'test-device-v4',
      schemaVersion: DiqqahDatabase.schemaVersionValue,
      appVersion: '0.279.0+79',
    );
    final refused = await bare.verifyQuick(file.path);
    expect(refused.ok, isFalse);
    expect(refused.reason, contains('v4'));
  });

  // ── س230 (د11 الجزء الثاني — سفر جذر السجلات وإعادة الختم) ─────────

  // جذور سجلات الأجهزة — مستقلة عن جذور النسخ أعلاه (فصل النطاقات).
  final logRootA =
      List<int>.generate(32, (i) => (i * 5 + 41) % 256);
  final logRootB =
      List<int>.generate(32, (i) => (i * 19 + 71) % 256);
  final vaultB = BackupVaultKeys(rootKey: rootB, recoveryCode: code);

  test('س230: بانية القاعدة بجذر السجلات — الختم بجذر الجهاز والقراءة '
      'الإرثية للإرثي معاً (DQ-1108 حارس)', () async {
    final aPath = p.join(tempDir.path, 'rootA.db');
    final dbA = DiqqahDatabase(filePath: aPath, logRootKey: logRootA);
    await dbA.customStatement('SELECT 1');
    await dbA.recordSystemEvent('settings_changed', payload: {'k': 'س230'});
    final row = (await dbA
            .customSelect('SELECT payload FROM events ORDER BY id')
            .get())
        .first
        .data['payload'] as String;
    expect(row.startsWith(LogCipher.envelopePrefix), isTrue,
        reason: 'ختم بجذر الجهاز — البادئة حاضرة');
    // الجهاز ذاته يفتح — والجذر الآخر لا يفتح (وسم GCM حاكم).
    expect(await dbA.openLogText(row), contains('س230'));
    final salt = await dbA.p3LogSalt();
    await expectLater(
      LogCipher(logRootB).open(row, salt),
      throwsA(isA<LogCipherIntegrityException>()),
    );
    await dbA.close();
  });

  test('س230: سفر الجذر عبر الأجهزة وإعادة الختم بجذر المستقر عليه — '
      'بذرة المزامنة تُقرأ بعد الاستعادة حرفاً (الخلاف المحسوم بد11)',
      () async {
    // الجهاز أ: قاعدة بسجلات مختومة بجذره، ونسخة v5 يحمل الجذر معها.
    final aPath = p.join(tempDir.path, 'deviceA.db');
    final dbA = DiqqahDatabase(filePath: aPath, logRootKey: logRootA);
    await dbA.customStatement('SELECT 1');
    await dbA.recordSystemEvent('settings_changed', payload: {'v': 1});
    final target = p.join(tempDir.path, 'a-v5.dqk');
    await backupTo(dbA, target,
        vaultKeys: vaultA, logRootKey: logRootA, cipher: cipher);
    expect(
        BackupCipher.encryptedVersion(await File(target).readAsBytes()),
        BackupCipher.vaultLogFormatVersion);
    await dbA.close();

    // الجهاز ب (قاعدة الاختبار القائمة): يستعيد بالرمز (بلا مفتاح خزنة
    // أ) — والجذر المسافر يُستخرج مع النص.
    final candidate = await prepareRestore(
      target,
      recoveryCode: code,
      localLogRootKey: logRootB,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    expect(candidate.logRootKey, equals(logRootA),
        reason: 'سجل السجلات يسافر تحت DEK ويُستخرج عند الفك');
    await applyRestore(
      db: db,
      candidate: candidate,
      currentDbPath: dbPath,
      vaultKeys: vaultB,
      logRootKey: logRootB,
    );
    candidate.dispose();

    // القاعدة المستعادة على ب: سجلاتها مختومة بجذر ب الآن — تُقرأ هنا
    // (بذرة المزامنة m4 حية)، والحواجز معادة الإنشاء (إلحاق محكوم).
    final dbB = DiqqahDatabase(filePath: dbPath, logRootKey: logRootB);
    await dbB.customStatement('SELECT 1');
    final payload = ((await dbB
            .customSelect('SELECT payload FROM events ORDER BY id')
            .get())
        .first
        .data['payload'] as String);
    expect(payload.startsWith(LogCipher.envelopePrefix), isTrue);
    // الحمولة فُتحت بجذر الجهاز المستقر عليه — إعادة الختم عملت حرفاً
    // (كانت مختومة بجذر أ داخل النسخة، وdbB يفتحها بجذره هو).
    expect(await dbB.openLogText(payload), '{"v":1}',
        reason: 'بذرة المزامنة m4 تُقرأ بعد الاستعادة بجذر الجهاز ذاته');
    await expectLater(
      dbB.customStatement(
          "UPDATE events SET payload = 'x' WHERE id = (SELECT MIN(id) FROM events)"),
      throwsA(isA<Exception>()),
      reason: 'حاجز الإلحاق معاد إنشاؤه بعد الختم (DQ-1119)',
    );
    // ولقطة الرجوع v5 بجذر ب — التراجع يعمل بمفتاح خزنة ب صامتاً
    // وبالجذر المستقر عليه (الجذر ذاته فلا ختم جديد).
    final snapshots = Directory(tempDir.path)
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('diqqah-before-restore'))
        .toList();
    expect(snapshots, isNotEmpty);
    final snapBlob = await snapshots.first.readAsBytes();
    expect(BackupCipher.encryptedVersion(snapBlob),
        BackupCipher.vaultLogFormatVersion,
        reason: 'اللقطة تُغلَّف بخزنة الجهاز مع الجذر المسافر (v5)');
    final rollback = await prepareRestore(
      snapshots.first.path,
      vaultRootKey: rootB,
      localLogRootKey: logRootB,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    expect(rollback.logRootKey, equals(logRootB));
    rollback.dispose();
    await dbB.close();
  });

  test('س230: الجذر الواحد يتخطى الختم — سجلات الجهاز ذاته لا تُمس بايتاً',
      () async {
    final aPath = p.join(tempDir.path, 'same.db');
    final dbA = DiqqahDatabase(filePath: aPath, logRootKey: logRootA);
    await dbA.customStatement('SELECT 1');
    await dbA.recordSystemEvent('user_login', payload: {'n': 1});
    final before = ((await dbA
            .customSelect('SELECT payload FROM events ORDER BY id')
            .get())
        .first
        .data['payload'] as String);
    final target = p.join(tempDir.path, 'same-v5.dqk');
    await backupTo(dbA, target,
        vaultKeys: vaultA, logRootKey: logRootA, cipher: cipher);
    final candidate = await prepareRestore(
      target,
      vaultRootKey: rootA,
      localLogRootKey: logRootA,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    await applyRestore(
      db: dbA,
      candidate: candidate,
      currentDbPath: aPath,
      vaultKeys: vaultA,
      logRootKey: logRootA,
    );
    candidate.dispose();
    final dbAgain = DiqqahDatabase(filePath: aPath, logRootKey: logRootA);
    await dbAgain.customStatement('SELECT 1');
    final after = ((await dbAgain
            .customSelect('SELECT payload FROM events ORDER BY id')
            .get())
        .first
        .data['payload'] as String);
    expect(after, equals(before),
        reason: 'جذر النسخة = جذر الجهاز فلا ختم — البايتات كما وُلدت');
    await dbAgain.close();
  });

  test('س230: سجلات بجذر مجهول لا يسافر تُرفض قبل أي لمس للقاعدة الحية '
      '(روح F-013) — وبجذر جهازها تمر', () async {
    // نسخة v4 (محاكاة 0.279: الجذر لم يكن يسافر) من قاعدة مختومة بجذر أ.
    final aPath = p.join(tempDir.path, 'orphan.db');
    final dbA = DiqqahDatabase(filePath: aPath, logRootKey: logRootA);
    await dbA.customStatement('SELECT 1');
    await dbA.recordSystemEvent('settings_changed', payload: {'o': 1});
    final target = p.join(tempDir.path, 'orphan-v4.dqk');
    await backupTo(dbA, target, vaultKeys: vaultA, cipher: cipher);
    await dbA.close();
    // على جهاز آخر (جذر ب محلي): لا جذر مسافر بالملف — رفض صريح واحد.
    await expectLater(
      prepareRestore(
        target,
        vaultRootKey: rootA,
        localLogRootKey: logRootB,
        appSchemaVersion: DiqqahDatabase.schemaVersionValue,
        cipher: cipher,
      ),
      throwsA(isA<CorruptBackupException>().having(
          (e) => e.message, 'message', contains('لا تُفتح'))),
    );
    // وعلى الجهاز ذاته (جذره المحلي جذر أ): السجلات تُقرأ فتمر.
    final ok = await prepareRestore(
      target,
      vaultRootKey: rootA,
      localLogRootKey: logRootA,
      appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      cipher: cipher,
    );
    expect(ok.logRootKey, isNull, reason: 'v4 لا يحمل سجل سجلات');
    ok.dispose();
  });
}
