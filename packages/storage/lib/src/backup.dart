import 'dart:convert' show jsonEncode, utf8;
import 'dart:io';
import 'dart:isolate' show Isolate;
import 'dart:typed_data'
    show ByteData, BytesBuilder, Endian, Uint8List;

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

import 'database.dart';
import 'db_encryption.dart';
import 'file_encryption.dart';

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

/// يُنشئ ملف نسخة احتياطية كاملة في `targetPath` ويعيد بصمة SHA-256
/// لنصه الصريح (ق-ن4 — تُحسب مرة عند الإنشاء وتقارن عند كل تحقق).
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
///
/// P1-أ (س149/D-210): [lock] غير فارغة = النسخة تُكتب **بجيل v3
/// المقفل** بكلمة المستخدم ورمز الاسترداد (لا سجل مفتاح البرنامج —
/// توثيق BackupCipher)، وملف الصور المجاور بنفس القفل. فارغة = جيل
/// v2 بمفتاح البرنامج كما كان. P1-ب: [imagesCipher] مفتاح الجهاز
/// لملفات الصور الحية — الجمع يفك الملفات المشفرة فتحمل النسخة نص
/// الصور الصريح داخل غلافها (تُفك على أي جهاز).
///
/// د11 (س229/D-225 الجزء الأول): [vaultKeys] مواد مفاتيح الخزنة —
/// بلا قفل (الجيل الأعلى أولوية: v3 ثم v4 ثم v2) تُكتب النسخة وملف
/// صورها المجاور **بجيل v4**: DEK مغلّف بسجل مفتاح الخزنة (فتح صامت
/// على الجهاز ذاته) وسجل رمز الاسترداد (الفتح على أي جهاز آخر —
/// N-005 يلتئم بالرمز بلا كسر). غياب القفل والمواد معاً = v2 بمفتاح
/// البرنامج (انخفاض موثق لا صمت — نمط عرف س149 ذاته بالخزنة الفاشلة).
///
/// د11 الجزء الثاني (س230/D-225): [logRootKey] جذر سجلات هذا الجهاز
/// من خزنته — حاضراً ترفع النسخة وملف صورها إلى جيل السجل الرابع
/// (v6 مع قفل / v5 بلا قفل): سجل نوع 4 تحت DEK يحمل الجذر فسجلات
/// النسخة تسافر معها وتُقرأ عبر الأجهزة، وغائباً تعود النسخة بجيلها
/// القائم (v3/v4) بعقد الانخفاض الموثق (أحداث مختومة إرثياً فلا
/// سجل لها — والقارئ الجديد يفتح الأجيال كلها).
Future<String> backupTo(
  DiqqahDatabase db,
  String targetPath, {
  bool encrypted = true,
  BackupCipher? cipher,
  bool includeImages = false,
  Directory? imagesDir,
  BackupLock? lock,
  BackupVaultKeys? vaultKeys,
  List<int>? logRootKey,
  ImageFileCipher? imagesCipher,
}) async {
  final temp = File('$targetPath.tmp');
  if (await temp.exists()) await temp.delete();
  // VACUUM INTO يرفض الوجهة الموجودة — التمييز هنا يكشف حاجز الملف مبكراً.
  await db.customStatement("VACUUM INTO '${_sqlString(temp.path)}'");
  // F-150/D-210 P0-ج (س148): القاعدة المشفرة بمفتاح الجهاز تنتج صورة
  // VACUUM INTO مشفرة بمفتاح الجهاز ذاته — تُنزع تشفيرتها هنا
  // (PRAGMA rekey = '' بتوثيق MC «Remove encryption») كي تُغلف بجيل v2
  // بمفتاح البرنامج D-060 باقياً حرفاً فتُفك النسخة على أي جهاز ثانٍ
  // (مفتاح خزنته يخالف) — البند الذي أسده نقاش التشفير بالدليل.
  if (!fileIsPlaintextSqlite(temp.path)) {
    final keyHex = db.dbKeyHex;
    if (keyHex == null) {
      throw StateError(
          'صورة النسخة مشفرة بمفتاح جهاز ولا مفتاح معروف للاتصال — '
          'النسخ أُبطل بصوت عالٍ فلا تعتيم مزدوج صامت يكسر N-005');
    }
    await decryptImageInPlace(temp.path, keyHex);
    if (!fileIsPlaintextSqlite(temp.path)) {
      throw StateError('الصورة ما زالت مشفرة بعد النزع — النسخ أُبطل');
    }
  }
  String plainSha256;
  try {
    final bytes = await temp.readAsBytes();
    // س216 (ثقل الدقائق الأولى — جذر النسخ على العزل الواجهي): البصمة
    // والتشفير حسابٌ بايتاتي ثقيل (sha256 وAES-GCM على قاعدة السنة
    // كاملة بعشرات الميغابايتات) فلم يعد على عزل الواجهة حصراً —
    // Isolate.run يحمله بعزل خلفي فالإطارات تتنفس أثناء كل نسخة
    // ساعية أو يدوية. BackupCipher نقية البايتات (AES-GCM/HKDF بلا
    // قاعدة ولا ملف ولا عناصر غير قابلة للإرسال) فتُبنى داخل العزل
    // بعينها، والبايتات تمر بنسخة نقل رخيصة، والقفل حقلا نصّان
    // يُرسلان أصلاً — ولا مساس بالناتج حرفاً: نفس الخوارزمية
    // والمفتاح والملح فالبصمة كما كانت بالبايت.
    final cipherIterations =
        cipher?.iterations ?? BackupCipher().iterations;
    final lockPassword = lock?.password;
    final lockRecovery = lock?.recoveryCode;
    // د11: مواد الخزنة حقولاً خاماً تعبر العزل (نمط القفل بعينه —
    // BackupCipher نقية البايتات فتُبنى داخل العزل بعينها).
    final vaultRoot = (lockPassword == null || lockRecovery == null) &&
            vaultKeys != null
        ? vaultKeys.rootKey
        : null;
    final vaultRecovery = vaultKeys?.recoveryCode;
    // د11 الجزء الثاني (س230): الجذر الحي يعبر العزل كالقفل بعينه —
    // بايتات خام فحسب، والنسخة تُرفع لجيل السجل الرابع إن حضر.
    final logRoot = logRootKey;
    final (hash, out) = await Isolate.run(() async {
      final hash = sha256HexOf(bytes);
      if (!encrypted) return (hash, List<int>.from(bytes));
      final resolved = BackupCipher(iterations: cipherIterations);
      final List<int> encryptedOut;
      if (lockPassword != null && lockRecovery != null) {
        encryptedOut = await resolved.encryptLocked(
          bytes,
          password: lockPassword,
          recoveryCode: lockRecovery,
          logRootKey: logRoot,
        );
      } else if (vaultRoot != null && vaultRecovery != null) {
        // د11: بلا قفل وماللخزنة حاضرة — جيل الخزنة v4 (أو v5 بالجذر).
        encryptedOut = await resolved.encryptVaulted(
          bytes,
          vaultRootKey: vaultRoot,
          recoveryCode: vaultRecovery,
          logRootKey: logRoot,
        );
      } else {
        // انخفاض v2 موثق أعلاه (مواد غائبة/ناقصة).
        encryptedOut = await resolved.encrypt(bytes);
      }
      return (hash, encryptedOut);
    });
    plainSha256 = hash;
    await File(targetPath).writeAsBytes(out, flush: true);
  } finally {
    if (await temp.exists()) await temp.delete();
  }
  // س-129: ملف الصور المجاور بنفس غلاف التشفير — بعد نجاح ملف القاعدة
  // حصراً كي لا يبقى ملف صور يتيمة لنسخة فشلت. P1-أ: نفس القفل v3/v2.
  // د11: وبمواد الخزنة بلا قفل — جيل v4 عينه (نفس الأولوية حرفاً).
  if (includeImages && imagesDir != null) {
    final bundle = await collectImagesBundle(imagesDir, cipher: imagesCipher);
    if (bundle != null) {
      final resolved = cipher ?? BackupCipher();
      final wrapped = encrypted
          ? (lock != null
              ? await resolved.encryptLocked(
                  bundle,
                  password: lock.password,
                  recoveryCode: lock.recoveryCode,
                  logRootKey: logRootKey,
                )
              : vaultKeys != null
                  ? await resolved.encryptVaulted(
                      bundle,
                      vaultRootKey: vaultKeys.rootKey,
                      recoveryCode: vaultKeys.recoveryCode,
                      logRootKey: logRootKey,
                    )
                  : await resolved.encrypt(bundle))
          : bundle;
      await File(imagesSiblingPath(targetPath))
          .writeAsBytes(wrapped, flush: true);
    }
  }
  return plainSha256;
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

  /// س230 (د11 الجزء الثاني): جذر سجلات الأحداث والأخطاء المحمول
  /// بالنسخة (سجل نوع 4 تحت DEK بأجيال v5/v6 — null بغيرها) —
  /// يستهلكه التنفيذ بإعادة الختم بجذر الجهاز المستقر عليه.
  final List<int>? logRootKey;

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
    this.logRootKey,
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
///
/// P1-أ (س149): الجيل المقفل v3 يُفك بكلمة المرور أو رمز الاسترداد —
/// [recoveryCode] يكمل [password]، والمستدعى يمرر أسرار خزنة الجهاز
/// أولاً (نفس الجهاز يفتح صامتاً) أو ما كتبه المستخدم (الحقل يقبل
/// الكلمة أو الرمز فكلاهما يُجرّب بوسم GCM حاكم). v1/v2 كما كانت حرفاً.
///
/// د11 (س229/D-225 الجزء الأول): الجيل الرابع v4 بمفاتيح الخزنة —
/// [vaultRootKey] مفتاح خزنة هذا الجهاز: حاضراً يُفك صامتاً (نفس
/// الجهاز)، وغائباً يُطلب رمز الاسترداد المكتوب (جهاز آخر — فسيناريو
/// N-005 يلتئم بالرمز بلا كسر). v1/v2/v3 بمساراتها القائمة حرفاً.
///
/// د11 الجزء الثاني (س230/D-225): القارئ الموحد decryptAny بكل
/// الأجيل (v1..v6) — ومع النص يُستخرج **جذر سجلات النسخة** إن حمله
/// الملف (v5/v6) فيحمله المرشّح للختم بجذر هذا الجهاز عند التنفيذ،
/// و[localLogRootKey] جذر سجلات هذا الجهاز (لقطة الرجوع على الجهاز
/// ذاته تُقرأ به) يُستعمل معه في تحقق السجلات أدناه: كل غلاف مختوم
/// لا يُفتح بجذوره (جذر النسخة ثم جذر الجهاز ثم الإرثي المضمّن)
/// رفض صريح قبل أي لمس للقاعدة الحية (روح F-013) — فلا تنكسر
/// بذرة المزامنة m4 بعد الاستعادة بلا صوت.
Future<RestoreCandidate> prepareRestore(
  String backupPath, {
  String? password,
  String? recoveryCode,
  List<int>? vaultRootKey,
  List<int>? localLogRootKey,
  required int appSchemaVersion,
  BackupCipher? cipher,
}) async {
  final resolvedCipher = cipher ?? BackupCipher();
  final blob = await File(backupPath).readAsBytes();
  final List<int> plain;
  List<int>? logRootKey;
  switch (BackupCipher.identify(blob)) {
    case BackupKind.plainSqlite:
      plain = blob;
      break;
    case BackupKind.encrypted:
      // س230: القارئ الموحد — منبع واحد للأجيال الستة بموادها.
      final (decrypted, carriedLogRoot) = await resolvedCipher.decryptAny(
        blob,
        password: password,
        recoveryCode: recoveryCode,
        vaultRootKey: vaultRootKey,
      );
      plain = decrypted;
      logRootKey = carriedLogRoot;
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
    // س230 (د11 الجزء الثاني): تحقق سجلات الأحداث والأخطاء قبل أي
    // لمس للقاعدة الحية — لا فجوة صامتة وبذرة المزامنة لا تنكسر
    // بعد الاستعادة بصمت (التفصيل بالمساعدة أدناه).
    await _verifyBackupLogRows(sqlite,
        logRootKey: logRootKey, localLogRootKey: localLogRootKey);
    closeSqlite();
    // س-130 (دفعة 10): ملف الصور المجاور إن وُجد يُفحص ويُفك **قبل**
    // أي لمس للقاعدة الحية — فاسد يرفض الاستعادة كلها لا يُسكَت
    // («لا فجوة صامتة» D-124)، وسليم يحمل ملفاته في الذاكرة.
    final sibling = File(imagesSiblingPath(backupPath));
    var hasImages = false;
    var imagesFiles = const <(String, List<int>)>[];
    if (await sibling.exists()) {
      // س230: مفتاح الخزنة يُمرَّر هنا أيضاً — توثيق المساعدة «نفس مواد
      // ملف القاعدة عينها» صار حرفياً: نسخ v4/v5 بصور تُفك صامتة على
      // الجهاز ذاته (كانت تسأل الرمز — ورطة س229 كامنة يسدها هذا
      // التمرير في نفس المسار).
      imagesFiles = await _decodeImagesBlob(
        await sibling.readAsBytes(),
        resolvedCipher,
        password: password,
        recoveryCode: recoveryCode,
        vaultRootKey: vaultRootKey,
      );
      hasImages = imagesFiles.isNotEmpty;
    }
    return RestoreCandidate._(
      plainPath,
      tempDir,
      version,
      hasImages: hasImages,
      imagesFiles: imagesFiles,
      logRootKey: logRootKey,
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
///
/// P1-ب (س149): [imagesCipher] مفتاح الجهاز — اللقطة تُجمع بفك الملفات
/// المشفرة (نصاً داخل غلافها)، والاستبدال يكتب مشفراً بمفتاح هذا
/// الجهاز فالعالم على القرص مشفر بعد الاستعادة أيضاً.
Future<String> applyRestore({
  required DiqqahDatabase db,
  required RestoreCandidate candidate,
  required String currentDbPath,
  Directory? imagesDir,
  String? sourcePath,
  BackupVaultKeys? vaultKeys,
  List<int>? logRootKey,
  ImageFileCipher? imagesCipher,
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
  // F-150/D-210 P0-ج (س148): صورة الاتصال المشفر تأتي مشفرة بمفتاح
  // الجهاز فتُنزع تشفيرتها أولاً ثم —
  // س227 (المرحلة صفر د5 من خارطة طريق التقرير الاستشاري بأمر المالك
  // «ابدأ التنفيذ»): اللقطة الناتجة تُغَلَّف فوراً بجيل النسخ v2
  // (مفتاح البرنامج بلا كلمة — D-060) بدل نص SQLite صريح على القرص:
  // زر التراجع بprepareRestore نفسه يعمل حرفاً (يتعرف v2 ويفكه بلا
  // كلمة — سلوك الكتالوج والبوابة والتدوير بلا تغيير: المسح بالاسم
  // وقيمة restore.gate كما هي) — فتُسد فتحة اللقطة النصية الشقيقة
  // للقاعدة المشفرة بلا كسر سيناريو الرجوع.
  //
  // د11 (س229/D-225 الجزء الأول): وماللخزنة حاضرة تُغلَّف اللقطة
  // بجيل الخزنة v4 عينه (فتح صامت على الجهاز ذاته وبرمز الاسترداد
  // على جهاز آخر) — زر التراجع يمرر مفتاح خزنته بprepareRestore
  // فيفتحها صامتاً، والغائب = v2 كما كانت حرفاً.
  final snapshotKey = db.dbKeyHex;
  if (snapshotKey != null && !fileIsPlaintextSqlite(snapshotPath)) {
    await decryptImageInPlace(snapshotPath, snapshotKey);
  }
  final snapshotPlain = await File(snapshotPath).readAsBytes();
  final snapshotSealed = vaultKeys != null
      ? await BackupCipher().encryptVaulted(
          snapshotPlain,
          vaultRootKey: vaultKeys.rootKey,
          recoveryCode: vaultKeys.recoveryCode,
          logRootKey: logRootKey,
        )
      : await BackupCipher().encrypt(snapshotPlain);
  final snapshotTmp = File('$snapshotPath.wrap-tmp');
  await snapshotTmp.writeAsBytes(snapshotSealed, flush: true);
  await snapshotTmp.rename(snapshotPath);

  // س-130: لقطة الصور المرافقة — طريق الرجوع يحفظ الصور ذاته (D-124).
  // س227: الحزمة مغلَّفة بالجيل ذاته — _decodeImagesBlob يفك الجيل
  // الجاري بلا كلمة فالتراجع يعمل كما كان، والصور لم تعد نصاً صريحاً
  // بجوار نسخة القاعدة على القرص. د11: وv4 عينه بماللخزنة.
  if (imagesDir != null) {
    final bundle = await collectImagesBundle(imagesDir, cipher: imagesCipher);
    if (bundle != null) {
      final resolved = BackupCipher();
      final sealedBundle = vaultKeys != null
          ? await resolved.encryptVaulted(
              bundle,
              vaultRootKey: vaultKeys.rootKey,
              recoveryCode: vaultKeys.recoveryCode,
              logRootKey: logRootKey,
            )
          : await resolved.encrypt(bundle);
      await File(imagesSiblingPath(snapshotPath))
          .writeAsBytes(sealedBundle, flush: true);
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
      // تكليف 2026-11-13 §5-4: مسح current_user_id قسراً — الجلسة
      // لا تنجو من الاستعادة؛ البوابة تطلب دخولاً بمدير من النسخة ذاتها.
      raw.prepare("DELETE FROM app_meta WHERE key = 'current_user_id'")
          .execute();
      // §5-5/ق-ن1(أ): زرع مفتاح البوابة — يقرأه الإقلاع التالي فيعرض
      // بوابة الاستعادة (5 محاولات ثم رفض بمخرج اختيار نسخة أخرى).
      // د-3 (§25.7، س136): معه اسم لقطة ما قبل الاستعادة — عينها التي
      // يعرض عليها زر «تراجع» فتستعاد بمر المسار ذاته لا مسار خاص.
      final gate = jsonEncode(<String, Object?>{
        'at': DateTime.now().toUtc().toIso8601String(),
        'source': sourcePath ?? '',
        'attempts': 0,
        'locked': false,
        'snapshot': p.basename(snapshotPath),
      });
      final stmt = raw.prepare(
        "INSERT INTO app_meta (key, value) VALUES ('device_id', ?) "
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      );
      stmt.execute([landingDeviceId]);
      final gateStmt = raw.prepare(
        "INSERT INTO app_meta (key, value) VALUES ('restore.gate', ?) "
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      );
      gateStmt.execute([gate]);
      stmt.dispose();
      gateStmt.dispose();
    }
    // س230 (د11 الجزء الثاني — الخلاف المحسوم بد11): إعادة ختم سجلات
    // الأحداث والأخطاء بجذر هذا الجهاز بعد الاستبدال — جذر النسخة
    // يفتح (والإرثي المضمّن قارئاً دائماً) وجذر الجهاز يختم فبذرة
    // المزامنة m4 تُقرأ بعد الاستعادة حرفاً (التفصيل بالمساعدة).
    await _resealLogRoots(raw,
        sourceLogRoot: candidate.logRootKey, targetLogRoot: logRootKey);
  } finally {
    raw.dispose();
  }

  // س-130: استبدال مجلد الصور بعد نجاح القاعدة — بنسخة الصور أو
  // بالفراغ (تصريح الاستعادة سبق وأخبر المالك بذلك قبل التنفيذ).
  // P1-ب: الكتابة مشفرة بمفتاح هذا الجهاز فالعالم على القرص مشفر.
  if (imagesDir != null) {
    await replaceImagesDir(
      imagesDir,
      candidate.hasImages ? candidate.imagesFiles : const [],
      cipher: imagesCipher,
    );
  }
  return snapshotPath;
}

/// س230 (د11 الجزء الثاني): ملح سجلات النسخة من القاعدة الخام
/// (app_meta — المفتاح نفسه p3LogSaltMetaKey) — null إن غاب الجدول
/// أو المفتاح أو القيمة (ما قبل v28 بلا سجلات مختومة أصلاً).
String? _rawP3LogSalt(Database raw) {
  final hasMeta = raw.select(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='app_meta'")
      .isNotEmpty;
  if (!hasMeta) return null;
  final rows =
      raw.select('SELECT value FROM app_meta WHERE key = ?', [p3LogSaltMetaKey]);
  if (rows.isEmpty) return null;
  final value = rows.first[0] as String?;
  if (value == null || value.isEmpty) return null;
  return value;
}

/// س230 (د11 الجزء الثاني): تحقق سجلات النسخة قبل أي لمس للقاعدة الحية
/// (روح F-013) — كل غلاف مختوم بسجلي الأحداث والأخطاء يجب أن يُفتح
/// بجذوره المرشحة: جذر النسخة المحمول بالملف (v5/v6) ثم جذر هذا
/// الجهاز (لقطة رجوع تُستعاد على الجهاز ذاته) ثم الإرثي المضمّن
/// (قارئاً دائماً — LogCipher.openWithRoots يجرّبه أخيراً حصراً).
/// سجل لا يُفتح بها جميعاً = نسخة مهربة أو تالفة فرفض صريح واحد
/// قبل أي استبدال — لا فجوة صامتة تنكسر بها بذرة المزامنة m4
/// بعد الاستعادة بصمت.
Future<void> _verifyBackupLogRows(
  Database raw, {
  List<int>? logRootKey,
  List<int>? localLogRootKey,
}) async {
  final salt = _rawP3LogSalt(raw);
  if (salt == null) return; // ما قبل v28: لا سجلات مختومة أصلاً.
  final checker = LogCipher();
  final roots = <List<int>?>[logRootKey, localLogRootKey];
  Future<void> openOrReject(String envelope) async {
    try {
      // الغرض الفتح حصراً — وسم GCM حاكم والناتج يُهمل.
      await checker.openWithRoots(envelope, salt, roots);
    } on LogCipherIntegrityException {
      throw const CorruptBackupException(
          'سجلات النسخة لا تُفتح بمفاتيحها — الملف غير سليم');
    }
  }

  if (raw.select(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events'")
      .isNotEmpty) {
    for (final row in raw.select('SELECT id, payload FROM events')) {
      final payload = row['payload'] as String?;
      if (payload == null ||
          !payload.startsWith(LogCipher.envelopePrefix)) {
        continue;
      }
      await openOrReject(payload);
    }
  }
  if (raw.select(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='error_log'")
      .isNotEmpty) {
    for (final row
        in raw.select('SELECT id, message, context FROM error_log')) {
      final message = row['message'] as String?;
      if (message != null && message.startsWith(LogCipher.envelopePrefix)) {
        await openOrReject(message);
      }
      final context = row['context'] as String?;
      if (context != null && context.startsWith(LogCipher.envelopePrefix)) {
        await openOrReject(context);
      }
    }
  }
}

/// س230 (د11 الجزء الثاني — الخلاف المحسوم بد11): إعادة ختم سجلات
/// الأحداث والأخطاء بجذر هذا الجهاز بعد الاستعادة — جذر النسخة
/// المحمول (أو الإرثي المضمّن قارئاً دائماً) يفتح، وجذر الجهاز
/// المستقر عليه يختم، فبذرة المزامنة m4 تُقرأ بعد الاستعادة حرفاً.
/// سقوط الحواجز ثم الختم ثم إنشاؤها بنمط الترحيلات القائم (س107:
/// الدروب قبل CREATE فالإعادة تعريف موثقة) — والسجل بلا بادئة (ما
/// قبل v28 داخل قاعدة ملحة — شاذ نادر) يُترك كما هو (يفتحه المرور
/// الصريح)، والجذر الواحد (جذر النسخة = جذر الجهاز — كلاهما الإرثي
/// بالغائبين) يتخطى الختم كله فلا عمل بلا أثر على الجهاز ذاته.
Future<void> _resealLogRoots(
  Database raw, {
  required List<int>? sourceLogRoot,
  required List<int>? targetLogRoot,
}) async {
  final salt = _rawP3LogSalt(raw);
  if (salt == null) return; // ما قبل v28: تُختمها ترحيلة v28 عند الفتح.
  if (_sameRoot(sourceLogRoot, targetLogRoot)) return; // الجذر ذاته.
  final opener = LogCipher();
  final sealer = LogCipher(targetLogRoot);
  // جذور الفتح بالترتيب: جذر النسخة المحمول (v5/v6) ثم الجذر الهدف —
  // نسخة خام أو لقطة رجوع على الجهاز ذاته تحمل سجلات مختومة بجذره
  // المحلي (لا سجل جذر بالملف الخام) — ثم الإرثي المضمّن أخيراً دائماً.
  final sourceRoots = <List<int>?>[sourceLogRoot, targetLogRoot];
  for (final sql in DiqqahDatabase.logGuardsDropSql) {
    raw.execute(sql);
  }
  try {
    if (raw.select(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events'")
        .isNotEmpty) {
      final rows = raw.select('SELECT id, payload FROM events');
      if (rows.isNotEmpty) {
        final update =
            raw.prepare('UPDATE events SET payload = ? WHERE id = ?');
        try {
          for (final row in rows) {
            final payload = row['payload'] as String?;
            if (payload == null ||
                !payload.startsWith(LogCipher.envelopePrefix)) {
              continue;
            }
            final opened =
                await opener.openWithRoots(payload, salt, sourceRoots);
            update.execute([await sealer.seal(opened, salt), row['id']]);
          }
        } finally {
          update.dispose();
        }
      }
    }
    if (raw.select(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='error_log'")
        .isNotEmpty) {
      final rows = raw.select('SELECT id, message, context FROM error_log');
      if (rows.isNotEmpty) {
        final update = raw.prepare(
            'UPDATE error_log SET message = ?, context = ? WHERE id = ?');
        try {
          for (final row in rows) {
            final message = row['message'] as String?;
            final context = row['context'] as String?;
            final oldMessage = (message != null &&
                    message.startsWith(LogCipher.envelopePrefix))
                ? message
                : null;
            final oldContext = (context != null &&
                    context.startsWith(LogCipher.envelopePrefix))
                ? context
                : null;
            if (oldMessage == null && oldContext == null) continue;
            update.execute([
              oldMessage == null
                  ? message
                  : await sealer
                      .seal(await opener.openWithRoots(oldMessage, salt, sourceRoots), salt),
              oldContext == null
                  ? context
                  : await sealer
                      .seal(await opener.openWithRoots(oldContext, salt, sourceRoots), salt),
              row['id'],
            ]);
          }
        } finally {
          update.dispose();
        }
      }
    }
  } finally {
    for (final sql in DiqqahDatabase.logGuardsCreateSql) {
      raw.execute(sql);
    }
  }
}

/// س230: تطابق جذور بايتاتياً — الغائبان معاً (كلاهما الإرثي
/// المضمّن) متطابقان فلا ختم لعمل بلا أثر.
bool _sameRoot(List<int>? a, List<int>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

/// D-197 (دفعة التحصين الافتتاحي — س96): لقطة الأمان قبل ترقية المخطط.
///
/// الدرس من العلة الميدانية (تحديث b24→b26 على جهاز المالك): أول فتح
/// بعد ترقية يحمل ترحيلاتٍ على قاعدة حقيقية — ولو رمى أحد المسار
/// لِما ظهر شيء: البوابة القديمة بلا حرس فكانت دورة أبدية. هذه
/// اللقطة أقصى جهد قبل مساس الترحيلات: نسخ الملف وملفاته الجانبية
/// (wal/shm) إلى لاحقة `preup<الإصدار الهدف>` — فأي ترقية فاشلة
/// تصير قابلة للاسترجاع حرفياً بالبايتات الأولى النقية.
///
/// القواعد:
/// - قاعدة غائبة (أول تشغيل بلا ملف) — لا لقطة، فلا شيء يُخشى عليه.
/// - إصدار الملف مطابق للهدف أو أعلى — لا ترقية ماددة فلا لقطة (لا
///   انتفاخ يومي في كل افتتاح عادي).
/// - إصدار أدنى من الهدف أو الملف لا يُقرأ أصلاً — لقطة كما هو قبل
///   أن يكشف فتح drift الخطأ.
/// - لقطة واحدة لكل إصدار هدف: إن وجدت `preup<N>` فهي الأولى النقية
///   من أول محاولة — محاولات الفشل المتكررة لا تستبدلها أبداً (والترحيلات
///   آمنة التكرار فإعادة المحاولة على الحالة النصف مُرحّلة محسوبة).
/// - فشل اللقطة ذاته لا يوقف الافتتاح أبداً — أقصى جهد لا حاجز.
Future<void> snapshotBeforeUpgrade(
    String dbPath, int targetSchemaVersion) async {
  final dbFile = File(dbPath);
  if (!await dbFile.exists()) return;
  final stamp = '.preup$targetSchemaVersion';
  if (await File('$dbPath$stamp').exists()) return;
  // القراءة بايتاتية من الترويسة حصراً — درس الجولة الأولى بالCI
  // (س96): فتح الملف الخام لقراءة user_version يجري نقطة فحص عند
  // الإغلاق فتمحو wal/shm قبل نسخها فاللقطة تفقدهما. قراءة الترويسة
  // لا تفتح شيئاً ولا تلمس الملف ولا جانبيه فالنسخ كما هو حرفاً.
  final version = _headerUserVersion(dbPath);
  if (version != null &&
      (version == 0 || version >= targetSchemaVersion)) {
    return;
  }
  for (final suffix in const ['', '-wal', '-shm']) {
    final f = File('$dbPath$suffix');
    if (await f.exists()) {
      try {
        await f.copy('$dbPath$stamp$suffix');
      } catch (_) {
        // اللقطة أقصى جهد — فشل نسخ جانبي لا يعطل الافتتاح.
      }
    }
  }
}

/// إصدار user_version من ترويسة ملف SQLite بايتاتيًا — الإزاحة 60
/// (عدد صحيح كبير النهاية 4 بايتات وفق صيغة الملف الرسمية) وسحر
/// الترويسة «SQLite format 3\0» حارس الصلاحية. ملف قصير أو غير
/// صالح أو غير مقروء يعيد null فاللقطات تجري على «غير معروف»
/// ولا يُفتح الملف أصلاً.
int? _headerUserVersion(String path) {
  try {
    // س216: قراءة أول 64 بايتة حصراً (ترويسة SQLite) لا الملف كله —
    // النمط السابق readAsBytesSync كان يقرأ قاعدة كاملة (أشهر بيانات
    // بعشرات الميغابايتات) إلى الذاكرة عند كل افتتاح بعد ترقية كي
    // يقرأ 4 بايتات عند الإزاحة 60، والمصحح يفتح الملف عشوائياً
    // ويقرأ الترويسة وحدها فلا قدم كامل على العزل الواجهي.
    final raf = File(path).openSync();
    final Uint8List bytes;
    try {
      bytes = raf.readSync(64);
    } finally {
      raf.closeSync();
    }
    if (bytes.length < 64) return null;
    final magic = 'SQLite format 3';
    for (var i = 0; i < 15; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) return null;
    }
    if (bytes[15] != 0) return null;
    return (bytes[60] << 24) | (bytes[61] << 16) | (bytes[62] << 8) | bytes[63];
  } catch (_) {
    return null;
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
///
/// P1-ب (س149): [cipher] مفتاح الجهاز — الملفات المشفرة على القرص
/// تُفك هنا فتحمل الحزمة نص الصور الصريح (وتُغلف بحجم النسخة كما
/// هي)، والملفات النص الصريح المتبقية (فاشل ترحيل) تدخل كما هي —
/// ومشفر بلا مفتاح رفض صوت عالٍ لا اسكات (روح P0-ج).
Future<List<int>?> collectImagesBundle(
  Directory? dir, {
  ImageFileCipher? cipher,
}) async {
  if (dir == null || !dir.existsSync()) return null;
  final files = <String, List<int>>{};
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
    final bytes = entity.readAsBytesSync();
    if (bytes.isEmpty) continue;
    if (ImageFileCipher.isEncryptedImage(bytes)) {
      if (cipher == null) {
        throw StateError(
            'ملف صور مشفر بلا مفتاح فك معروف — الجمع أُبطل بصوت عالٍ '
            'فلا حزمة نص صريح صامتة (P1-ب)');
      }
      files[rel] = await cipher.decrypt(bytes);
    } else {
      files[rel] = bytes;
    }
  }
  if (files.isEmpty) return null;
  return buildImagesBundle(files);
}

/// يستبدل محتوى مجلد الصور بالملفات المعطاة — الفراغ مشروع (عالم
/// النسخة المنعكس بصدق) ونسخة ما قبل الاستعادة محفوظة دائماً قبلها.
/// P1-ب (س149): [cipher] مفتاح الجهاز — الكتابة مشفرة فالعالم على
/// القرص مشفر بعد الاستعادة أيضاً؛ فارغه = كتابة خام (الاختبارات
/// الضيقة والمسار القديم حرفاً).
Future<int> replaceImagesDir(
  Directory dir,
  List<(String, List<int>)> files, {
  ImageFileCipher? cipher,
}) async {
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
    final out = cipher != null ? await cipher.encrypt(bytes) : bytes;
    await target.writeAsBytes(out, flush: true);
  }
  return files.length;
}

/// فك غلاف ملف صور (مشفر بمفتاح البرنامج أو مقفل أو خام مضغوط) —
/// أي شكل غريب رفض آمن واحد (فحص قبل أي لمس — F-013 روحاً).
/// P1-أ (س149): ملف الصور المقفل يُفك بكلمة المرور أو رمز الاسترداد
/// ذاتيهما اللذين فكا ملف القاعدة (نفس مواد prepareRestore).
/// د11 (س229): وملف الصور بجيل الخزنة v4 يُفك بمفتاح هذا الجهاز
/// أو برمز الاسترداد — نفس مواد ملف القاعدة عينها.
/// س230 (د11 الجزء الثاني): القارئ الموحد decryptAny — الأجيل كلها
/// (وv5/v6 بسجل السجلات حاضرة) بمواد ملف القاعدة ذاتها.
Future<List<(String, List<int>)>> _decodeImagesBlob(
  List<int> blob,
  BackupCipher cipher, {
  String? password,
  String? recoveryCode,
  List<int>? vaultRootKey,
}) async {
  List<int> plain;
  switch (BackupCipher.identify(blob)) {
    case BackupKind.encrypted:
      // س230: الجذر المحمول يسافر بالنسخة لا بصورها — يُتجاهل هنا.
      final (decoded, _) = await cipher.decryptAny(
        blob,
        password: password,
        recoveryCode: recoveryCode,
        vaultRootKey: vaultRootKey,
      );
      plain = decoded;
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
/// مجلد الصور بلا مساس بالبيانات. P1-أ/P1-ب: نفس القفل ومفتاح الصور.
/// د11 (س229): ونفس أولوية الأجيال — قفل v3 ثم مواد خزنة v4 ثم v2.
Future<void> backupImagesTo(
  Directory imagesDir,
  String targetPath, {
  bool encrypted = true,
  BackupCipher? cipher,
  BackupLock? lock,
  BackupVaultKeys? vaultKeys,
  ImageFileCipher? imagesCipher,
}) async {
  final bundle = await collectImagesBundle(imagesDir, cipher: imagesCipher);
  if (bundle == null) {
    throw const CorruptBackupException('لا صور بعد — مجلد الصور فارغ أو غائب');
  }
  final List<int> wrapped;
  if (encrypted) {
    final resolved = cipher ?? BackupCipher();
    wrapped = lock != null
        ? await resolved.encryptLocked(
            bundle,
            password: lock.password,
            recoveryCode: lock.recoveryCode,
          )
        : vaultKeys != null
            ? await resolved.encryptVaulted(
                bundle,
                vaultRootKey: vaultKeys.rootKey,
                recoveryCode: vaultKeys.recoveryCode,
              )
            : await resolved.encrypt(bundle);
  } else {
    wrapped = bundle;
  }
  await File(targetPath).writeAsBytes(wrapped, flush: true);
}

/// س-130: استعادة صور من ملف مستقل — تستبدل مجلد الصور بلا مساس
/// بالبيانات، وتعيد عدد الملفات المستعادة للتصريح بالنجاح.
Future<int> restoreImagesFrom(
  String imagesFilePath,
  Directory imagesDir, {
  BackupCipher? cipher,
  String? password,
  String? recoveryCode,
  List<int>? vaultRootKey,
  ImageFileCipher? imagesCipher,
}) async {
  final blob = await File(imagesFilePath).readAsBytes();
  final files = await _decodeImagesBlob(
    blob,
    cipher ?? BackupCipher(),
    password: password,
    recoveryCode: recoveryCode,
    vaultRootKey: vaultRootKey,
  );
  return replaceImagesDir(imagesDir, files, cipher: imagesCipher);
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
