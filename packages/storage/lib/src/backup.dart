import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

import 'database.dart';

/// النسخ الاحتياطي والاستعادة الكاملة (F-012/F-013/F-154/F-156 — س-01).
///
/// المبادئ المنعكسة من التوثيق:
/// - «ملف واحد كامل للقاعدة» (02): النسخة غير المشفرة ملف SQLite خام
///   تُنتج بـ VACUUM INTO — لقطة متسقة ذرية حتى والقاعدة تعمل.
/// - «يُستعاد كاملاً أو لا شيء» (02): الاستعادة تحقق أولاً ثم لقطة رجوع
///   آلية (F-154) ثم استبدال ذري بإعادة تسمية داخل المجلد نفسه.
/// - «تحقق من سلامة الملف (وتشفيره إن وجد) قبل استبدال القاعدة» (F-013):
///   لا بايت يلمس القاعدة الحية قبل اجتياز فك التغليف + ترويسة SQLite
///   + integrity_check + فحص نسخة المخطط (F-156).
/// - «نسخة ما قبل الاستعادة — تاريخ/وقت... طريق الرجوع الوحيد» (F-154):
///   تُلتقط آلياً في كل استعادة ويُعاد مسارها للشاشة (سطر الإحالة).

/// يُنشئ ملف نسخة احتياطية كاملة في `targetPath`.
///
/// [password] فارغة أو غائبة = ملف SQLite خام؛ وإلا فغلاف مشفر
/// AES-256-GCM (BackupCipher في حزمة المجال). الملف الهدف إن وُجد يُستبدل.
Future<void> backupTo(
  DiqqahDatabase db,
  String targetPath, {
  String? password,
  BackupCipher? cipher,
}) async {
  final temp = File('$targetPath.tmp');
  if (await temp.exists()) await temp.delete();
  // VACUUM INTO يرفض الوجهة الموجودة — التمييز هنا يكشف حاجز الملف مبكراً.
  await db.customStatement("VACUUM INTO '${_sqlString(temp.path)}'");
  try {
    final bytes = await temp.readAsBytes();
    final out = (password == null || password.isEmpty)
        ? bytes
        : await (cipher ?? BackupCipher()).encrypt(bytes, password);
    await File(targetPath).writeAsBytes(out, flush: true);
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}

/// مرشّح استعادة اجتاز كل الفحوص — ملف خام سليم جاهز للاستبدال.
///
/// يعيش على ملف مؤقت في مجلد النظام؛ استدعِ [RestoreCandidate.dispose]
/// بعد الانتهاء (نجاحاً أو فشلاً) ليمسح الأثر.
class RestoreCandidate {
  final String plainPath;
  final int schemaVersion;
  final Directory _tempDir;

  RestoreCandidate._(this.plainPath, this._tempDir, this.schemaVersion);

  void dispose() {
    try {
      _tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// يقرأ ملف نسخة ويتحقق منه كاملاً — بلا أي لمس للقاعدة الحية.
///
/// ترتيب الفحص (F-013/F-156): التعرف على النوع ← فك التشفير إن لزم
/// (وسم GCM = سلامة) ← ترويسة SQLite ضمنياً بالتعرف ← integrity_check
/// ← نسخة المخطط: الأحدث من التطبيق تُرفض بـ«حدّث التطبيق»، والأقدم
/// تمر ليمسكها محرك الترحيلات عند الفتح (F-011).
Future<RestoreCandidate> prepareRestore(
  String backupPath, {
  String? password,
  required int appSchemaVersion,
  BackupCipher? cipher,
}) async {
  final resolvedCipher = cipher ?? BackupCipher();
  final blob = await File(backupPath).readAsBytes();
  final List<int> plain;
  switch (BackupCipher.identify(blob)) {
    case BackupKind.plainSqlite:
      plain = blob;
      break;
    case BackupKind.encrypted:
      if (password == null || password.isEmpty) {
        throw const CorruptBackupException(
            'النسخة مشفرة بكلمة مرور — أدخلها ثم أعد المحاولة');
      }
      plain = await resolvedCipher.decrypt(blob, password);
      break;
    case BackupKind.unknown:
      throw const CorruptBackupException(
          'الملف ليس نسخة احتياطية معروفة — تحقق من الملف');
  }

  final tempDir = await Directory.systemTemp.createTemp('diqqah_restore_');
  final plainPath = p.join(tempDir.path, 'verified.db');
  await File(plainPath).writeAsBytes(plain, flush: true);
  final sqlite = sqlite3.open(plainPath);
  var sqliteClosed = false;
  void closeSqlite() {
    if (!sqliteClosed) {
      sqliteClosed = true;
      sqlite.dispose();
    }
  }

  try {
    final integrity = sqlite.select('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first != 'ok') {
      throw const CorruptBackupException('فحص سلامة الملف فشل — الملف تالف');
    }
    final version =
        sqlite.select('PRAGMA user_version').first.values.first as int;
    if (version > appSchemaVersion) {
      throw BackupNewerSchemaException(version);
    }
    closeSqlite();
    return RestoreCandidate._(plainPath, tempDir, version);
  } catch (e) {
    closeSqlite();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
    // SQLite نفسه رفض الملف (ترويسة سليمة الشكل ومحتوى فاسد) — يُوحد القول
    // في فشل آمن واحد قبل أي لمس للقاعدة الحية (F-013).
    if (e is SqliteException) {
      throw const CorruptBackupException(
          'فحص سلامة الملف فشل — الملف تالف');
    }
    rethrow;
  }
}

/// ينفذ الاستعادة بعد التحقق: لقطة رجوع آلية (F-154) ثم استبدال ذري.
///
/// يغلق الاتصال الحالي [db] — المتصل يعيد بناء قاعدة جديدة من
/// [currentDbPath] بعد نجاحها. يعيد مسار نسخة الرجوع (سطر الإحالة).
///
/// هوية القاعدة (D-054 — قرار المالك 2026-10-28): التطابق 100% يبقى
/// معياراً لكل بيانات القاعدة عدا `device_id` وحده — القاعدة المستعادة
/// تتبنى معرّف الجهاز الذي استقرت عليه (التقاطه قبل الغلق)، فيخرج
/// جهازان استقيا من نسخة واحدة بمعرّفين مختلفين، ويبقى معرّف نفس
/// الجهاز ثابتاً فوق قاعدته (F-015: يتولد مرة ويبقى).
Future<String> applyRestore({
  required DiqqahDatabase db,
  required RestoreCandidate candidate,
  required String currentDbPath,
}) async {
  // D-054: معرّف الجهاز المستقر عليه يُلتقط قبل الغلق — قد يُولد الآن
  // إن لم يوجد بعد (وإدراجه الأول يقع في اللقطة نفسها فلا يضيع).
  final landingDeviceId = await db.deviceId();
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}${two(now.second)}'
      '-${now.millisecond.toString().padLeft(3, '0')}';
  final snapshotPath = p.join(
    p.dirname(currentDbPath),
    'diqqah-before-restore-$stamp.db',
  );

  // لقطة ما قبل الاستعادة — متسقة ذرياً حتى والقاعدة في منتصف عمل.
  await db.customStatement("VACUUM INTO '${_sqlString(snapshotPath)}'");

  await db.close();
  for (final suffix in ['', '-wal', '-shm']) {
    final f = File('$currentDbPath$suffix');
    if (await f.exists()) await f.delete();
  }
  // الاستبدال الذري: نسخ لاسم مجاور ثم إعادة تسمية داخل المجلد نفسه.
  final staged = File('$currentDbPath.restoring');
  await File(candidate.plainPath).copy(staged.path);
  await staged.rename(currentDbPath);

  // D-054: اعتماد هوية الجهاز المستقر عليه في القاعدة المستعادة —
  // بالـ SQLite الخام لأن اتصال drift مُغلق، وفتح مطابق لما سيفعله
  // الفتح التالي. نسخة مخطط v1 بلا app_meta تُتخطى — الترحيلة 1→2
  // تبنيها ثم يولد deviceId() معرّفاً عند أول استعلام.
  final raw = sqlite3.open(currentDbPath);
  try {
    final hasMeta = raw.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='app_meta'",
    ).isNotEmpty;
    if (hasMeta) {
      final stmt = raw.prepare(
        "INSERT INTO app_meta (key, value) VALUES ('device_id', ?) "
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      );
      stmt.execute([landingDeviceId]);
      stmt.dispose();
    }
  } finally {
    raw.dispose();
  }
  return snapshotPath;
}

/// D-053: تبنّي ملف قاعدة الجيل السابق — أول فتح بعد التحديث يعيد
/// تسمية «heseb.db» (وسائر ملفاته wal/shm) إلى اسم الجديد بدل أن يُظن
/// أول تشغيل ويتولد أرشيف فارغ. إعادة تسمية داخل المجلد نفسه — لا
/// نسخ ولا تحويل، ولا شيء يُلمس إن غاب أي من الملفين.
Future<void> adoptLegacyHesebDatabase(String diqqahDbPath) async {
  final target = File(diqqahDbPath);
  if (await target.exists()) return;
  final legacy = File(p.join(p.dirname(diqqahDbPath), 'heseb.db'));
  if (!await legacy.exists()) return;
  for (final suffix in ['', '-wal', '-shm']) {
    final f = File('${legacy.path}$suffix');
    if (await f.exists()) {
      await f.rename('${target.path}$suffix');
    }
  }
}

/// يُرمى عند فشل فحوص ملف النسخة — لم يُمس القاعدة الحية (فشل آمن).
class CorruptBackupException implements Exception {
  final String message;
  const CorruptBackupException([this.message = 'النسخة تالفة أو ليست نسخة احتياطية']);

  @override
  String toString() => message;
}

/// نسخة من مخطط أحدث من التطبيق — تُرفض برسالة «حدّث التطبيق» (F-156).
class BackupNewerSchemaException implements Exception {
  final int backupSchemaVersion;
  const BackupNewerSchemaException(this.backupSchemaVersion);

  @override
  String toString() =>
      'النسخة من مخطط أحدث من التطبيق ($backupSchemaVersion) — حدّث التطبيق';
}

/// تهريب علامات الاقتباس المفردة فقط — المسارات توليد داخلي محكوم.
String _sqlString(String path) => path.replaceAll("'", "''");
