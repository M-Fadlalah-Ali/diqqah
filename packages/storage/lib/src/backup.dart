import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data'
    show ByteData, BytesBuilder, Endian, Uint8List;

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
/// D-060 (قرار المالك «كلمة السر للبرنامج فقط»): [encrypted] صادقة
/// افتراضياً (D-050) فتُغلف النسخة بمفتاح البرنامج حصراً — تُفتح داخل
/// التطبيق نفسه وحده على أي جهاز، بلا أي كلمة. كاذبة = ملف SQLite خام
/// بعد الإلغاء الواعي. الملف الهدف إن وُجد يُستبدل.
///
/// س-129/D-124 (دفعة 10): [includeImages] يضمّن صور الأصناف في ملف
/// ثانٍ مجاور (`<target>.images`) مغلّف بنفس المفتاح — ملف القاعدة
/// نفسه لا يُلمس أبداً فلا انتفاخ ولا كسر للذرية (VACUUM INTO/س-01).
/// مجلد الصور غائب أو فارغ = لا ملف صور أصلاً فيتصريح الاستعادة
/// «بلا صور» بصدق.
Future<void> backupTo(
  DiqqahDatabase db,
  String targetPath, {
  bool encrypted = true,
  BackupCipher? cipher,
  bool includeImages = false,
  Directory? imagesDir,
}) async {
  final temp = File('$targetPath.tmp');
  if (await temp.exists()) await temp.delete();
  // VACUUM INTO يرفض الوجهة الموجودة — التمييز هنا يكشف حاجز الملف مبكراً.
  await db.customStatement("VACUUM INTO '${_sqlString(temp.path)}'");
  try {
    final bytes = await temp.readAsBytes();
    final out = encrypted
        ? await (cipher ?? BackupCipher()).encrypt(bytes)
        : bytes;
    await File(targetPath).writeAsBytes(out, flush: true);
  } finally {
    if (await temp.exists()) await temp.delete();
  }
  // س-129: ملف الصور المجاور بنفس مفتاح التشفير — بعد نجاح ملف القاعدة
  // حصراً كي لا يبقى ملف صور يتيمة لنسخة فشلت.
  if (includeImages && imagesDir != null) {
    final bundle = collectImagesBundle(imagesDir);
    if (bundle != null) {
      final resolved = cipher ?? BackupCipher();
      final wrapped = encrypted ? await resolved.encrypt(bundle) : bundle;
      await File(imagesSiblingPath(targetPath))
          .writeAsBytes(wrapped, flush: true);
    }
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

  /// س-130 (دفعة 10): هل النسخة تتضمن صور الأصناف؟ — يُقرأ من ملف
  /// الصور المجاور إن وُجد، ويُصرّح به قبل الاستعادة لا بعدها فلا
  /// فجوة صامتة أبداً.
  final bool hasImages;

  /// ملفات الصور المحمولة داخل النسخة (مسار نسبي، بايتات) — مستخرجة
  /// إلى الذاكرة قبل أي لمس للقاعدة الحية (فحص قبل استبدال). والكمية
  /// محدودة بناتج المحرك (30..60KB للأصل) فالاحتفاظ بالذاكرة مقبول.
  final List<(String, List<int>)> imagesFiles;

  RestoreCandidate._(
    this.plainPath,
    this._tempDir,
    this.schemaVersion, {
    this.hasImages = false,
    this.imagesFiles = const [],
  });

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
///
/// D-060: الجيل الجاري v2 يُفك بمفتاح البرنامج بلا أي كلمة — [password]
/// لقراءة الجيل القديم v1 حصراً (نسخ أيام D-050 وما قبله)، وفراغه على
/// v1 رفض آمن قبل أي لمس.
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
      if (BackupCipher.encryptedVersion(blob) >=
          BackupCipher.formatVersion) {
        // الجيل الجاري: مفتاح البرنامج — بلا أي كلمة (D-060)
        plain = await resolvedCipher.decrypt(blob);
      } else if (password == null || password.isEmpty) {
        throw const CorruptBackupException(
            'النسخة من الجيل القديم المحمي بكلمة مرور — '
            'أدخلها في حقل كلمة المرور ثم أعد المحاولة');
      } else {
        plain = await resolvedCipher.decryptWithPassword(blob, password);
      }
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
    // س-130 (دفعة 10): ملف الصور المجاور إن وُجد يُفحص ويُفك **قبل**
    // أي لمس للقاعدة الحية — فاسد يرفض الاستعادة كلها لا يُسكَت
    // («لا فجوة صامتة» D-124)، وسليم يحمل ملفاته في الذاكرة.
    final sibling = File(imagesSiblingPath(backupPath));
    var hasImages = false;
    var imagesFiles = const <(String, List<int>)>[];
    if (await sibling.exists()) {
      imagesFiles = await _decodeImagesBlob(
        await sibling.readAsBytes(),
        resolvedCipher,
      );
      hasImages = imagesFiles.isNotEmpty;
    }
    return RestoreCandidate._(
      plainPath,
      tempDir,
      version,
      hasImages: hasImages,
      imagesFiles: imagesFiles,
    );
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
///
/// س-130/D-124 (دفعة 10): [imagesDir] مجلد صور القاعدة الحية —
/// تُلتقط لقطة صور مرافقة لنسخة الرجوع (`<snapshot>.images`) ثم
/// يُستبدل المجلد بمحتوى النسخة: نسخة بصور تُستبدل بملفاتها، ونسخة
/// بلا صور يُفرَّغ المجلد (عالم النسخة المنعكس بصدق — والصور القديمة
/// محفوظة في لقطة ما قبل الاستعادة دائماً). null = لا مساس بالصور
/// (الاستدعاءات القديمة والاختبارات الضيقة).
Future<String> applyRestore({
  required DiqqahDatabase db,
  required RestoreCandidate candidate,
  required String currentDbPath,
  Directory? imagesDir,
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

  // س-130: لقطة الصور المرافقة — طريق الرجوع يحفظ الصور ذاته (D-124).
  // خام غير مشفرة كنسخة القاعدة نفسها: صيغة الحزمة ذاتها بلا غلاف مفتاح.
  if (imagesDir != null) {
    final bundle = collectImagesBundle(imagesDir);
    if (bundle != null) {
      await File(imagesSiblingPath(snapshotPath))
          .writeAsBytes(bundle, flush: true);
    }
  }

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

  // س-130: استبدال مجلد الصور بعد نجاح القاعدة — بنسخة الصور أو
  // بالفراغ (تصريح الاستعادة سبق وأخبر المالك بذلك قبل التنفيذ).
  if (imagesDir != null) {
    await replaceImagesDir(
      imagesDir,
      candidate.hasImages ? candidate.imagesFiles : const [],
    );
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

// ═══════════════════════════════════════════════════════════════════
// صور الأصناف — دفعة (10) «الصور والباركود» (س-129/س-130، D-124/D-125).
//
// المعمارية: الصور ملفات بجوار ملف القاعدة لا مدموغة فيه (حماية «ملف
// واحد كامل» وذرية الاستعادة)، والنسخ الاحتياطي يضمّنها في ملف ثانٍ
// مجاور بلاحقة `.images` — حزمة مضغوطة (zlib من المكتبة القياسية بلا
// حزمة خارجية جديدة) مغلّفة بنفس مفتاح التشفير BackupCipher. صيغة
// الحزمة الداخلية خاصة بالبرنامج: بطاقة تعريف + عدّاد + (طول مسار،
// مسار نسبي، طول بيانات، بيانات) — وسلامة المحتوى كلها ضمانة تغليف
// GCM نفسه فلا حاجة بصمات لكل ملف.
// ═══════════════════════════════════════════════════════════════════

/// مجلد صور الأصناف بجوار ملف القاعدة — المصدر الوحيد للاشتقاق (D-125).
String imagesDirFor(String dbPath) => p.join(p.dirname(dbPath), 'images');

/// ملف صور نسخة قاعدة — نفس الاسم الأساسي بلاحقة `.images` (س-129:
/// النسخة الممتدة ملفان)، ونسخة ما قبل الاستعادة تأخذ الاسم النمطي
/// ذاته فتُستعاد كزوج لاحقاً بلا أي تعليمات.
String imagesSiblingPath(String backupPath) => '$backupPath.images';

/// الاسم النسبي لملفَي صورة صنف — بمعرّف الصنف الدائم (هوية لا تتغير
/// — D-073) فلا حاجة لتوليد أسماء عشوائية ولا تصادم بين الأصناف.
String itemImageRelativeName(int itemId, {required bool thumb}) =>
    thumb ? 'images/item-$itemId-thumb.jpg' : 'images/item-$itemId.jpg';

/// بطاقة تعريف الحزمة: «DQIMG01\0».
final List<int> _imagesMagic = utf8.encode('DQIMG01') + const [0x00];

/// يبني حزمة صور مضغوطة من خريطة (مسار نسبي ← بايتات).
Uint8List buildImagesBundle(Map<String, List<int>> files) {
  final entries = files.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final out = BytesBuilder();
  out.add(_imagesMagic);
  final countBytes = ByteData(4)..setUint32(0, entries.length, Endian.big);
  out.add(countBytes.buffer.asUint8List());
  for (final e in entries) {
    final pathBytes = utf8.encode(e.key);
    if (pathBytes.length > 0xFFFF) {
      throw const CorruptBackupException('مسار صورة طويل عن الحد');
    }
    final lenBytes = ByteData(2)..setUint16(0, pathBytes.length, Endian.big);
    out.add(lenBytes.buffer.asUint8List());
    out.add(pathBytes);
    final dataBytes = ByteData(4)..setUint32(0, e.value.length, Endian.big);
    out.add(dataBytes.buffer.asUint8List());
    out.add(e.value);
  }
  // الضغط من المكتبة القياسية حصراً — لا حزمة خارجية جديدة بيد المالك.
  return Uint8List.fromList(ZLibCodec().encode(out.toBytes()));
}

/// يفك حزمة صور إلى خريطتها — أي انحراف عن البطاقة أو الطول يرمي
/// رفضاً آمناً واحداً (لا فجوة صامتة D-124).
Map<String, List<int>> parseImagesBundle(List<int> plain) {
  for (var i = 0; i < _imagesMagic.length; i++) {
    if (i >= plain.length || plain[i] != _imagesMagic[i]) {
      throw const CorruptBackupException(
          'ملف الصور ليس حزمة صور دِقَّة — تحقق من الملف');
    }
  }
  var pos = _imagesMagic.length;
  List<int> take(int n) {
    if (pos + n > plain.length) {
      throw const CorruptBackupException('حزمة الصور مقطوعة — الملف تالف');
    }
    final v = plain.sublist(pos, pos + n);
    pos += n;
    return v;
  }

  final countData = ByteData.sublistView(Uint8List.fromList(take(4)));
  final count = countData.getUint32(0, Endian.big);
  if (count > 100000) {
    throw const CorruptBackupException('حزمة الصور شاذة العدد — الملف تالف');
  }
  final out = <String, List<int>>{};
  for (var i = 0; i < count; i++) {
    final pathLen =
        ByteData.sublistView(Uint8List.fromList(take(2))).getUint16(0, Endian.big);
    final path = utf8.decode(take(pathLen));
    final dataLen =
        ByteData.sublistView(Uint8List.fromList(take(4))).getUint32(0, Endian.big);
    if (dataLen > 64 * 1024 * 1024) {
      throw const CorruptBackupException('ملف صورة ضخم شاذاً — الحزمة تالف');
    }
    out[path] = take(dataLen);
  }
  return out;
}

/// يجمع مجلد الصور في حزمة مضغوطة — null إن غاب المجلد أو فرغ فلا
/// ملف صور يتيمة (تصريح الاستعادة «بلا صور» بصدق س-130).
List<int>? collectImagesBundle(Directory? dir) {
  if (dir == null || !dir.existsSync()) return null;
  final files = <String, List<int>>{};
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
    final bytes = entity.readAsBytesSync();
    if (bytes.isEmpty) continue;
    files[rel] = bytes;
  }
  if (files.isEmpty) return null;
  return buildImagesBundle(files);
}

/// يستبدل محتوى مجلد الصور بالملفات المعطاة — الفراغ مشروع (عالم
/// النسخة المنعكس بصدق) ونسخة ما قبل الاستعادة محفوظة دائماً قبلها.
Future<int> replaceImagesDir(
  Directory dir,
  List<(String, List<int>)> files,
) async {
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
  for (final (rel, bytes) in files) {
    final safe = rel.replaceAll('\\', '/');
    if (safe.contains('..') || p.isAbsolute(safe)) {
      throw const CorruptBackupException('مسار صورة غير سليم داخل الحزمة');
    }
    final target = File(p.join(dir.path, safe));
    await target.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }
  return files.length;
}

/// فك غلاف ملف صور (مشفر بمفتاح البرنامج أو خام مضغوط) — أي شكل غريب
/// رفض آمن واحد (فحص قبل أي لمس — F-013 روحاً).
Future<List<(String, List<int>)>> _decodeImagesBlob(
  List<int> blob,
  BackupCipher cipher,
) async {
  List<int> plain;
  switch (BackupCipher.identify(blob)) {
    case BackupKind.encrypted:
      // ملفات الصور من الجيل الجاري حصراً — مفتاح البرنامج بلا كلمة.
      plain = await cipher.decrypt(blob);
      break;
    case BackupKind.plainSqlite:
      throw const CorruptBackupException(
          'ملف الصور يحمل قاعدة لا صور — تحقق من الملف المختار');
    case BackupKind.unknown:
      plain = blob; // خام مضغوط — يفحصه فك zlib أدناه
      break;
  }
  try {
    final Map<String, List<int>> parsed = parseImagesBundle(
      ZLibCodec().decode(plain),
    );
    return [
      for (final e in parsed.entries) (e.key, e.value),
    ];
  } on CorruptBackupException {
    rethrow;
  } catch (_) {
    throw const CorruptBackupException(
        'ملف صور النسخة تالف — تعذر فك حزم الصور');
  }
}

/// س-130: نسخة صور مستقلة — أداة مكمّلة لا بديل (D-124): مجلد الصور
/// وحده في ملف `.diqqah.images` بنفس التغليف، وتُستعاد منفردة فتستبدل
/// مجلد الصور بلا مساس بالبيانات.
Future<void> backupImagesTo(
  Directory imagesDir,
  String targetPath, {
  bool encrypted = true,
  BackupCipher? cipher,
}) async {
  final bundle = collectImagesBundle(imagesDir);
  if (bundle == null) {
    throw const CorruptBackupException('لا صور بعد — مجلد الصور فارغ أو غائب');
  }
  final wrapped = encrypted
      ? await (cipher ?? BackupCipher()).encrypt(bundle)
      : bundle;
  await File(targetPath).writeAsBytes(wrapped, flush: true);
}

/// س-130: استعادة صور من ملف مستقل — تستبدل مجلد الصور بلا مساس
/// بالبيانات، وتعيد عدد الملفات المستعادة للتصريح بالنجاح.
Future<int> restoreImagesFrom(
  String imagesFilePath,
  Directory imagesDir, {
  BackupCipher? cipher,
}) async {
  final blob = await File(imagesFilePath).readAsBytes();
  final files = await _decodeImagesBlob(blob, cipher ?? BackupCipher());
  return replaceImagesDir(imagesDir, files);
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
