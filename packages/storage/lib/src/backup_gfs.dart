/// منفذ جدولة النسخ GFS — طبقة الملفات (تكليف 2026-11-13). السياسة
/// النقية بمِلء المجال (backup_schedule.dart) وهنا قراءة الأقراص
/// وكتابتها وحدها: إنشاء النسخ وتحقيقها والتدوير وسقف الحصة والكتالوج
/// الجانبي القابل لإعادة البناء بالمسح (ق-ن5).
///
/// مواضع البناء:
/// - النسخ المجدولة (h/d/w/m) والسنوية والحدثية: مجلد `<dbDir>/backups`
///   بترميز D-207 `diqqah-<type>-<device>-<UTC>.dqk`.
/// - النسخ اليدوية القائمة (D-061) ولقطات ما قبل الاستعادة وpreup
///   بمجلد القاعدة ذاته وتسميتها القائمة — الكشف بالمسح لا تسمية جديدة.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'backup.dart';
import 'database.dart';
import 'file_encryption.dart';

/// نتيجة تحقيق نسخة بالتدرج (ق-ن4).
class GfsVerifyOutcome {
  final bool ok;
  final BackupVerifyState state;
  final String? sha256Hex;
  final int? schemaVersion;
  final String? reason;

  const GfsVerifyOutcome({
    required this.ok,
    required this.state,
    this.sha256Hex,
    this.schemaVersion,
    this.reason,
  });
}

/// سجلُ لقطة ممسوحة (preup/قبل-استعادة/يدوية غير مسجلة) — عرض الكتالوج
/// يريها بجانب الصفوف المدارة، ولا تدخل تدوير النسخ المدارة.
class ScannedSnapshotRow {
  final String fileName;
  final int sizeBytes;
  final DateTime modifiedUtc;
  final String typeLabel;

  const ScannedSnapshotRow({
    required this.fileName,
    required this.sizeBytes,
    required this.modifiedUtc,
    required this.typeLabel,
  });
}

/// مستودع GFS — يفتح مرة مع القاعدة ويحيا معها.
///
/// P1-أ/P1-ب (س149): [loadLock] مصدر أسرار قفل النسخ (خزنة الجهاز
/// بالواجهة) — النسخ الجديدة تُكتب v3 مقفلة إن وُجد القفل، والتحقق
/// الحي للنسخ المقفلة يفك بأسراره ذاتها؛ و[imagesCipher] مفتاح الجهاز
/// لملفات الصور الحية في الجمع. فارغاهما = السلوك القائم v2/الخام حرفاً.
///
/// د11 (س229/D-225 الجزء الأول): [loadVaultKeys] مصدر مواد مفاتيح الخزنة
/// (جذر عشوائي لكل جهاز + رمز الاسترداد) — بلا قفل تُكتب النسخ الجديدة
/// **بجيل الخزنة v4** (سجل مفتاح الخزنة هنا صامتاً + سجل الرمز على أي
/// جهاز آخر)، والتحقق الحي يفك بمفتاح الخزنة ذاته. غيابه بلا قفل =
/// انخفاض v2 موثق لا صمت (نمط عرف س149 نفسه).
class GfsBackupStore {
  final Directory backupsDir;
  final Directory dbDir;
  final String deviceIdFull;
  final int schemaVersion;
  final String appVersion;
  final Future<BackupLock?> Function()? loadLock;
  final Future<BackupVaultKeys?> Function()? loadVaultKeys;
  final ImageFileCipher? imagesCipher;

  BackupCatalog catalog = BackupCatalog();

  GfsBackupStore._({
    required this.backupsDir,
    required this.dbDir,
    required this.deviceIdFull,
    required this.schemaVersion,
    required this.appVersion,
    this.loadLock,
    this.loadVaultKeys,
    this.imagesCipher,
  });

  /// الفتح: يضمن مجلد النسخ، يحمل الكتالوج، ويعيد بناء ما غاب عنه
  /// بالمسح (ق-ن5: الكتالوج صورة قابلة للتجديد لا سجل مقدس).
  static Future<GfsBackupStore> open({
    required Directory backupsDir,
    required Directory dbDir,
    required String deviceIdFull,
    required int schemaVersion,
    required String appVersion,
    Future<BackupLock?> Function()? loadLock,
    Future<BackupVaultKeys?> Function()? loadVaultKeys,
    ImageFileCipher? imagesCipher,
  }) async {
    final store = GfsBackupStore._(
      backupsDir: backupsDir,
      dbDir: dbDir,
      deviceIdFull: deviceIdFull,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      loadLock: loadLock,
      loadVaultKeys: loadVaultKeys,
      imagesCipher: imagesCipher,
    );
    await backupsDir.create(recursive: true);
    final file = File(p.join(backupsDir.path, kBackupCatalogFileName));
    if (await file.exists()) {
      store.catalog = BackupCatalog.fromJson(await file.readAsString());
    }
    await store.rebuildByScan();
    return store;
  }

  String get deviceTag => backupDeviceTag(deviceIdFull);

  // ── الكتالوج ──────────────────────────────────────────────────

  Future<void> saveCatalog() async {
    final file = File(p.join(backupsDir.path, kBackupCatalogFileName));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(catalog.toJson(), flush: true);
    await tmp.rename(file.path); // استبدال ذري داخل المجلد نفسه.
  }

  /// إعادة البناء بالمسح: الملفات الجديدة تدخل بلا تحقق معلوم،
  /// والموجودة في الكتالوج بصيغة مطابقة تحتفظ بحقائقها، والمفقود يسقط.
  Future<void> rebuildByScan() async {
    final scanned = <String>{};
    await for (final f in backupsDir.list()) {
      final name = p.basename(f.path);
      if (f is! File || name == kBackupCatalogFileName) continue;
      final parsed = parseScheduledBackupFileName(name);
      if (parsed == null) continue;
      scanned.add(name);
      final known = catalog.entries
          .where((e) => e.fileName == name && e.folderId == 'backups')
          .firstOrNull;
      if (known == null) {
        catalog.addEntry(BackupCatalogEntry(
          fileName: name,
          kind: parsed.kind,
          atUtc: parsed.atUtc,
          sizeBytes: await f.length(),
          deviceTag: parsed.deviceTag,
          includesImages: await File(p.join(backupsDir.path,
                  imagesSiblingBase(name)))
              .exists(),
          appVersion: appVersion,
          folderId: 'backups',
        ));
      }
    }
    // إسقاط صفوف مجدولة مفقودة الملف (حذفت خارجياً).
    catalog.entries.removeWhere((e) =>
        e.folderId == 'backups' &&
        e.kind != BackupScheduleKind.manual &&
        !scanned.contains(e.fileName));
    await saveCatalog();
  }

  /// الاسم الأساسي لملف الصور المرافق — زاوية س-129 القائمة
  /// (`<target>.images`) مع لاحقة dqk الجديدة.
  static String imagesSiblingBase(String backupFileName) =>
      '$backupFileName.images';

  String _pathOf(String folderId, String fileName) =>
      p.join(folderId == 'backups' ? backupsDir.path : dbDir.path, fileName);

  // ── التحقق المتدرج (ق-ن4) ─────────────────────────────────────

  /// السريع: فك (وسم GCM سلامة مضمّنة) + ترويسة SQLite + بصمة SHA-256
  /// للنص الصريح. يعمل بالذاكرة — قراءة واحدة.
  Future<GfsVerifyOutcome> verifyQuick(String path) async {
    try {
      final blob = await File(path).readAsBytes();
      final Uint8List plain;
      switch (BackupCipher.identify(blob)) {
        case BackupKind.plainSqlite:
          plain = blob;
        case BackupKind.encrypted:
          final ver = BackupCipher.encryptedVersion(blob);
          if (ver == BackupCipher.lockedFormatVersion) {
            final lock = await loadLock?.call();
            if (lock == null) {
              return const GfsVerifyOutcome(
                  ok: false,
                  state: BackupVerifyState.failed,
                  reason: 'نسخة مقفلة بكلمة مرور ولا أسرار محمّلة للتحقق');
            }
            plain = Uint8List.fromList(await BackupCipher().decryptLocked(
              blob,
              password: lock.password,
              recoveryCode: lock.recoveryCode,
            ));
          } else if (ver == BackupCipher.vaultFormatVersion) {
            // د11: جيل الخزنة — يُفك بمفتاح هذا الجهاز حصراً هنا
            // (التحقق الحي مسألة الجهاز ذاته؛ ورمز الاسترداد مسار
            // الاستعادة اليدوية لا التحقيق الدوري).
            final vault = await loadVaultKeys?.call();
            if (vault == null) {
              return const GfsVerifyOutcome(
                  ok: false,
                  state: BackupVerifyState.failed,
                  reason: 'نسخة بجيل الخزنة v4 ولا مواد خزنة محمّلة للتحقق');
            }
            plain = Uint8List.fromList(await BackupCipher().decryptVaulted(
              blob,
              vaultRootKey: vault.rootKey,
            ));
          } else if (ver == BackupCipher.formatVersion) {
            plain = Uint8List.fromList(
                await BackupCipher().decrypt(blob));
          } else {
            return const GfsVerifyOutcome(
                ok: false,
                state: BackupVerifyState.failed,
                reason: 'نسخة من الجيل القديم المحمي بكلمة مرور — '
                    'تُحقَّق بمسار الاستعادة لا هنا');
          }
        case BackupKind.unknown:
          return const GfsVerifyOutcome(
              ok: false,
              state: BackupVerifyState.failed,
              reason: 'ليس ملف نسخة معروفاً');
      }
      if (!_isSqliteHeader(plain)) {
        return const GfsVerifyOutcome(
            ok: false,
            state: BackupVerifyState.failed,
            reason: 'ترويسة SQLite مفقودة بعد الفك');
      }
      return GfsVerifyOutcome(
        ok: true,
        state: BackupVerifyState.quick,
        sha256Hex: sha256HexOf(plain),
        schemaVersion: _userVersionFromPlain(plain),
      );
    } catch (e) {
      return GfsVerifyOutcome(
          ok: false, state: BackupVerifyState.failed, reason: '$e');
    }
  }

  /// الكامل: السريع + فتح نسخة مؤقتة وintegrity_check (اليومية فما
  /// فوق والحدثية والسنوية وقبل أي حذف — ق-ن4).
  Future<GfsVerifyOutcome> verifyFull(String path) async {
    final quick = await verifyQuick(path);
    if (!quick.ok) return quick;
    final tmp = File(
        p.join(Directory.systemTemp.createTempSync('diqqah_verify_').path,
            'v.db'));
    try {
      final blob = await File(path).readAsBytes();
      final Uint8List plain;
      switch (BackupCipher.identify(blob)) {
        case BackupKind.plainSqlite:
          plain = blob;
        case BackupKind.encrypted:
          final ver = BackupCipher.encryptedVersion(blob);
          if (ver == BackupCipher.lockedFormatVersion) {
            final lock = await loadLock?.call();
            if (lock == null) {
              return GfsVerifyOutcome(
                  ok: false,
                  state: BackupVerifyState.failed,
                  reason: 'نسخة مقفلة ولا أسرار محمّلة للتحقق');
            }
            plain = Uint8List.fromList(await BackupCipher().decryptLocked(
              blob,
              password: lock.password,
              recoveryCode: lock.recoveryCode,
            ));
          } else if (ver == BackupCipher.vaultFormatVersion) {
            // د11: جيل الخزنة — بمفتاح هذا الجهاز حصراً هنا كذلك.
            final vault = await loadVaultKeys?.call();
            if (vault == null) {
              return GfsVerifyOutcome(
                  ok: false,
                  state: BackupVerifyState.failed,
                  reason: 'نسخة بجيل الخزنة v4 ولا مواد خزنة محمّلة للتحقق');
            }
            plain = Uint8List.fromList(await BackupCipher().decryptVaulted(
              blob,
              vaultRootKey: vault.rootKey,
            ));
          } else {
            plain = Uint8List.fromList(await BackupCipher().decrypt(blob));
          }
        case BackupKind.unknown:
          return quick; // محال — السريع رفضه.
      }
      await tmp.writeAsBytes(plain, flush: true);
      final db = sqlite3.open(tmp.path);
      try {
        final rows = db.select('PRAGMA integrity_check');
        final ok = rows.isNotEmpty && '${rows.first[0]}' == 'ok';
        return GfsVerifyOutcome(
          ok: ok,
          state: ok ? BackupVerifyState.full : BackupVerifyState.failed,
          sha256Hex: quick.sha256Hex,
          schemaVersion: quick.schemaVersion,
          reason: ok ? null : 'integrity_check أبلغ عن خلل',
        );
      } finally {
        db.dispose();
      }
    } catch (e) {
      return GfsVerifyOutcome(
          ok: false, state: BackupVerifyState.failed, reason: '$e');
    } finally {
      try {
        tmp.parent.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// «SQLite format 3» أول 16 بايتة (سحر الملف الرسمي) — بمقارنة
  /// بايتية صريحة بلا فك ترميز.
  static const List<int> _sqliteMagic = <int>[
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, // 'SQLite '
    0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, // 'format '
    0x33, 0x00, // '3' + NUL
  ];

  static bool _isSqliteHeader(List<int> plain) {
    if (plain.length < 16) return false;
    for (var i = 0; i < 16; i++) {
      if (plain[i] != _sqliteMagic[i]) return false;
    }
    return true;
  }

  /// user_version بالإزاحة 60 (صيغة الملف الرسمية) من النص الصريح.
  static int? _userVersionFromPlain(Uint8List plain) {
    if (plain.length < 64) return null;
    final b = ByteData.sublistView(plain, 60, 64);
    return b.getUint32(0, Endian.big);
  }

  // ── الإنشاء والتدوير ──────────────────────────────────────────

  /// إنشاء نسخة مجدولة/سنوية/حدثية بالترميز الجديد + التحقيق بطبقتها
  /// + التدوير بعد نجاحها (ق-ن4: قبل أي حذف تحقق كامل للجديدة).
  Future<BackupCatalogEntry> createScheduled(
    DiqqahDatabase db,
    BackupScheduleKind kind, {
    bool includeImages = false,
    Directory? imagesDir,
    DateTime? atUtc,
  }) async {
    final at = (atUtc ?? DateTime.now().toUtc());
    final fileName = scheduledBackupFileName(
        kind: kind, deviceTag: deviceTag, atUtc: at);
    final target = p.join(backupsDir.path, fileName);
    // P1-أ/P1-ب (س149): أسرار القفل ومفتاح الصور تُحل عند الإنشاء —
    // قفل موجود = النسخة وملف صورها بجيل v3 المقفل.
    // د11 (س229): بلا قفل ومواد خزنة حاضرة = جيل v4 (الأولوية
    // v3 ثم v4 ثم v2 — انخفاض v2 موثق لا صمت).
    final lock = await loadLock?.call();
    final vaultKeys =
        lock == null ? await loadVaultKeys?.call() : null;
    final sha = await backupTo(
      db,
      target,
      encrypted: true,
      includeImages: includeImages,
      imagesDir: imagesDir,
      lock: lock,
      vaultKeys: vaultKeys,
      imagesCipher: imagesCipher,
    );
    // التحقق بطبقة النوع: الساعية سريعة والبقية كاملة (ق-ن4).
    final verify = kind == BackupScheduleKind.hourly
        ? await verifyQuick(target)
        : await verifyFull(target);
    final entry = BackupCatalogEntry(
      fileName: fileName,
      kind: kind,
      atUtc: at,
      sizeBytes: await File(target).length(),
      sha256Hex: sha,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      deviceTag: deviceTag,
      includesImages: includeImages &&
          await File(
                  p.join(backupsDir.path, imagesSiblingBase(fileName)))
              .exists(),
      verifyState: verify.ok ? verify.state : BackupVerifyState.failed,
      folderId: 'backups',
    );
    if (!verify.ok) {
      // الفاشلة لا تُسجل نجاحاً ولا تدور حذفاً — تُسجل صفاً فاشلاً صراحة.
      catalog.addEntry(entry);
      await saveCatalog();
      throw GfsBackupException('فشل تحقق النسخة الجديدة: ${verify.reason}');
    }
    catalog.addEntry(entry);
    catalog.recordSuccess(kind, at);
    await saveCatalog();
    await _rotate(kind);
    return entry;
  }

  /// تسجيل نسخة يدوية (تسمية D-061 القائمة بمجلد القاعدة) بعد إنشائها
  /// بمسارها — الكتالوج يتبناها بتحقق سريع.
  Future<BackupCatalogEntry> registerManual(
    String path, {
    required bool includesImages,
    DateTime? at,
  }) async {
    final atTime = (at ?? DateTime.now().toUtc());
    final name = p.basename(path);
    final verify = await verifyQuick(path);
    final entry = BackupCatalogEntry(
      fileName: name,
      kind: BackupScheduleKind.manual,
      atUtc: atTime,
      sizeBytes: await File(path).length(),
      sha256Hex: verify.sha256Hex,
      schemaVersion: verify.schemaVersion,
      appVersion: appVersion,
      deviceTag: deviceTag,
      includesImages: includesImages,
      verifyState: verify.ok ? verify.state : BackupVerifyState.failed,
      folderId: 'db',
    );
    catalog.addEntry(entry);
    await saveCatalog();
    return entry;
  }

  /// التدوير: حذف الزائد عن الحد بعد نجاح الجديدة — وإن كانت الجديدة
  /// ساعية (تحقق سريع) فقبل أي حذف نرقّيها كاملة (ق-ن4: القاعدة الصلبة).
  Future<void> _rotate(BackupScheduleKind kind) async {
    final ofKind = catalog.entriesFor(kind);
    final plan = planRotation(kind, ofKind);
    if (plan.isEmpty) return;
    final newest = ofKind.first;
    if (newest.verifyState != BackupVerifyState.full) {
      final full = await verifyFull(_pathOf('backups', newest.fileName));
      if (!full.ok) return; // لا حذف أبداً بلا تحقق كامل سليم.
      catalog.addEntry(
          newest.copyWith(verifyState: BackupVerifyState.full));
      await saveCatalog();
    }
    for (final victim in plan) {
      await _deleteFileQuietly('backups', victim.fileName);
    }
    await saveCatalog();
  }

  /// حصة مجلد النسخ بالبايتات (ق-ن3) — ملفات .dqk حصراً.
  Future<int> usageBytes() async {
    var total = 0;
    await for (final f in backupsDir.list()) {
      if (f is File && f.path.endsWith('.$kScheduledBackupExtension')) {
        total += await f.length();
      }
    }
    return total;
  }

  /// تقليم السقف: خطة المجال ثم حذف — قبل إنشاء الجديدة (المساحة) أو
  /// بعدها (التدوير). يعيد ما حذف فعلاً.
  Future<int> trimToQuota({
    required int capBytes,
    required int incomingBytes,
  }) async {
    final usage = await usageBytes();
    final plan = planCapTrim(
      usageBytes: usage,
      capBytes: capBytes,
      incomingBytes: incomingBytes,
      entries: catalog.entries,
    );
    for (final victim in plan) {
      await _deleteFileQuietly('backups', victim.fileName);
    }
    return plan.length;
  }

  /// حذف نسخة بقرار المالك (مدير بتأكيد مزدوج — د-4): ملفها وصورتها
  /// وصفها. السنوية لا تُحذف آلياً قط — لكن اليدوية المتأكدة مسموحة.
  /// **الأرضية النظامية (د-4، س136)**: آخر نسخة من كل نوع — أي نوع
  /// حاضر بالكتالوج — لا تُحذف من داخل التطبيق مطلقاً: الحارس هنا
  /// حائط صلب تحت أي واجهة، فالواجهة تخفي الفعل عن المحمية وتدقق
  /// قبل الاستدعاء، وهذا الحرس يدقق بعدُ.
  Future<void> deleteBackupManually(
      {required String fileName, required String folderId}) async {
    if (protectedFloorFileNames(catalog.entries).contains(fileName)) {
      throw const GfsBackupException(
          'آخر نسخة من نوعها محمية بالأرضية النظامية — '
          'لا تُحذف من داخل التطبيق');
    }
    await _deleteFileQuietly(folderId, fileName);
    catalog.removeEntry(fileName: fileName, folderId: folderId);
    await saveCatalog();
  }

  Future<void> _deleteFileQuietly(String folderId, String fileName) async {
    final base = _pathOf(folderId, fileName);
    for (final suffix in const ['.images']) {
      final f = File('$base$suffix');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    final f = File(base);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    catalog.removeEntry(fileName: fileName, folderId: folderId);
  }

  // ── لقطات الحدث القائمة (كشف بالمسح لا تدوير) ─────────────────

  /// لقطات preup/قبل-الاستعادة/النسخ اليدوية غير المسجلة بمجلد القاعدة —
  /// تُعرض بالكتالوج (تكليف §8-10/§8-9: أبقِها وأظهرها).
  Future<List<ScannedSnapshotRow>> scanSnapshots() async {
    final rows = <ScannedSnapshotRow>[];
    await for (final f in dbDir.list()) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      final stat = await f.stat();
      String? label;
      if (RegExp(r'\.preup\d+').hasMatch(name)) {
        label = 'قبل ترقية المخطط';
      } else if (beforeRestoreSnapshotPattern.hasMatch(name)) {
        label = 'قبل استعادة';
      } else if (manualBackupNamePattern.hasMatch(name)) {
        final known = catalog.entries
            .where((e) => e.fileName == name && e.folderId == 'db')
            .isNotEmpty;
        if (!known) label = 'يدوية';
      }
      if (label != null) {
        rows.add(ScannedSnapshotRow(
          fileName: name,
          sizeBytes: stat.size,
          modifiedUtc: stat.modified.toUtc(),
          typeLabel: label,
        ));
      }
    }
    rows.sort((a, b) => b.modifiedUtc.compareTo(a.modifiedUtc));
    return rows;
  }

  /// تدوير لقطات ما قبل الاستعادة على آخر 5 (تكليف §2 — الحدثية) —
  /// يستدعى بعد نجاح استعادة جديدة (لقطتها الجديدة هي «الجديدة»). 
  /// د-3-2 (§25.7، س136): [protectFileName] لقطةٌ مثبتة نافذةَ تراجعٍ
  /// مفتوحة فمستثناة من التدوير ولو كانت أقدم المحذوفين — فالنافذة
  /// المفتوحة لا تُفقد لقطتها بحذف صامت، وبعد إغلاقها تعود للتدوير
  /// عرفاً لا استثناء.
  Future<int> rotateBeforeRestoreSnapshots(
      {int keep = 5, String? protectFileName}) async {
    final snaps = <ScannedSnapshotRow>[];
    await for (final f in dbDir.list()) {
      if (f is File &&
          beforeRestoreSnapshotPattern.hasMatch(p.basename(f.path))) {
        final stat = await f.stat();
        snaps.add(ScannedSnapshotRow(
          fileName: p.basename(f.path),
          sizeBytes: stat.size,
          modifiedUtc: stat.modified.toUtc(),
          typeLabel: 'قبل استعادة',
        ));
      }
    }
    snaps.sort((a, b) => b.modifiedUtc.compareTo(a.modifiedUtc)); // الأحدث أولاً.
    // د-3-2: المثبتة نافذةَ تراجعٍ مفتوحة خارج العدّ كلياً — لا تُحذف
    // ولو تراكمت عن الحد، وبقية الحد تسري على غيرها.
    if (protectFileName != null) {
      snaps.removeWhere((s) => s.fileName == protectFileName);
    }
    if (snaps.length <= keep) return 0;
    final victims = snaps.sublist(keep);
    // ق-ن4: قبل أي حذف — تحقق كامل لأحدث لقطة (الجديدة).
    final newestPath = p.join(dbDir.path, snaps.first.fileName);
    final full = await verifyFull(newestPath);
    if (!full.ok) return 0;
    for (final v in victims) {
      final f = File(p.join(dbDir.path, v.fileName));
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
      final img = File(p.join(dbDir.path, imagesSiblingBase(v.fileName)));
      if (await img.exists()) {
        try {
          await img.delete();
        } catch (_) {}
      }
    }
    return victims.length;
  }
}

/// استثناء منفذ GFS — فشل تحقق أو إنشاء يُلقى بعد تسجيل الصف الفاشل.
class GfsBackupException implements Exception {
  final String message;
  const GfsBackupException(this.message);
  @override
  String toString() => message;
}
