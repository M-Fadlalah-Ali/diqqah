import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List;

import 'package:sqlite3/sqlite3.dart';

/// تشفير القاعدة المحلية — F-150 المقررة بالـSRS موعده م4، وقدَّمها قرار
/// المالك د-١..د-٤ (س147/D-210: «التنفيذ الآن — النمط ChaCha20-Poly1305 —
/// مفتاح الخزنة وحده بالجيل الأول — لا تصدير غير مشفر») — P0 بأمر المالك
/// «أوافق على توصياتك في النقاط الأربعة» (س148).
///
/// المعمارية الموثقة (توثيق drift 2.32+ الرسمي بصفحة التشفير):
/// - sqlite3 3.x بدمج SQLite3MultipleCiphers عبر خيارات البناء (hooks
///   user_defines بpubspec الواجهة) — `sqlcipher_flutter_libs` و
///   `sqlite3_flutter_libs` متقادمان بعد drift 2.32 فنُزِعا.
/// - النمط المعتمد «chacha20» بمعجم SQLite3MultipleCiphers = ChaCha20-
///   Poly1305 AEAD (وهو الافتراضي في الحزمة — يُثبَّت صراحة ب`PRAGMA
///   cipher` كي لا يتبدل بترقية مستقبلية).
/// - المفتاح: 32 بايت عشوائية (256-bit) من خزنة الجهاز بلا اشتقاق KDF —
///   صيغة المفتاح الخام `PRAGMA key = "x'64-hex'"` (توثيق MC والـ SQL
///   Pragmas الرسمي).
/// - الترحيل عند أول فتح للمثبتين فوق حزم سابقة (قاعدة نص صريح): لقطة
///   أمان بنمط snapshotBeforeUpgrade (D-197) ثم «VACUUM INTO ملف مؤقت ←
///   PRAGMA rekey ← إعادة تسمية» كما توثق drift حرفاً — وبفشل أي خطوة
///   تبقى القديمة سليمة (الأصل لا يُمس حتى إعادة التسمية الأخيرة).
/// - فحص debug بـ`PRAGMA cipher` (توثيق drift «Important notice») —
///   اتصال بلا دمج MC يفشل بصوت عالٍ فلا نص صريح صامت أبداً.

/// النمط المشفر المعتمد — قرار المالك د-٢ (س147/D-210): ChaCha20-Poly1305
/// AEAD بمعجم SQLite3MultipleCiphers. يُثبَّت قبل المفتاح على كل اتصال.
const String kDbCipherScheme = 'chacha20';

/// طول مفتاح القاعدة بالبايتات — 256-bit (س147: «المفتاح العشوائي
/// 256-bit بالخزنة»).
const int kDbKeyBytes = 32;

/// خزنة مفتاح القاعدة — الواجهة النقية (F-150: «المفتاح يولَّد ويُحفظ
/// في خزنة الجهاز (Keystore) لا في الكود»). التنفيذ المنصوي بواجهة
/// flutter_secure_storage (Keystore أندرويد / DPAPI ويندوز) يعيش في
/// حزمة الواجهة؛ الاختبارات تستعمل [FixedKeyVault].
abstract class DatabaseKeyVault {
  /// يعيد مفتاح القاعدة الخام (32 بايت) — يولَّد عشوائياً مرة واحدة عند
  /// أول نداء ويُحفظ في الخزنة، ثم يُعاد من الخزنة في كل فتح تالٍ.
  Future<Uint8List> loadOrCreateKey();
}

/// خزنة اختبارية ثابتة — مفتاح محدد لا خزنة منصة في الاختبارات.
class FixedKeyVault implements DatabaseKeyVault {
  final Uint8List _key;
  FixedKeyVault(this._key)
      : assert(_key.length == kDbKeyBytes, 'المفتاح 32 بايت حصراً');

  /// مفتاح اختباري مشتق من بذرة نصية (ثباتي عبر التشغيلات).
  factory FixedKeyVault.seed(String seed) {
    final out = Uint8List(kDbKeyBytes);
    final bytes = utf8.encode(seed);
    for (var i = 0; i < out.length; i++) {
      out[i] = bytes[i % bytes.length];
    }
    return FixedKeyVault(out);
  }

  @override
  Future<Uint8List> loadOrCreateKey() async => _key;
}

/// توليد مفتاح عشوائي 256-bit — مصدر العشوائية الآمن `Random.secure()`.
Uint8List generateDbKey([Random? rng]) {
  final out = Uint8List(kDbKeyBytes);
  final source = rng ?? Random.secure();
  for (var i = 0; i < out.length; i++) {
    out[i] = source.nextInt(256);
  }
  return out;
}

/// صيغة المفتاح الخام داخل الـ pragma — 64 خانة ست عشرية بلا اشتقاق KDF.
/// التوثيق: `PRAGMA key = "x'...'"` — أقواس مزدوجة خارجية ومفردة داخلية.
String dbKeyPragmaRaw(String keyHex) =>
    'PRAGMA key = "x\'$keyHex\'"';

/// تحويل بايتات المفتاح إلى الصيغة الست عشرية للـ pragma — تحويل يدوي
/// بلا حزمة خارجية (مكتبة قياسية حصراً — شرط بوابة الدفعة).
String dbKeyHexOf(Uint8List key) {
  final out = StringBuffer();
  for (final b in key) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// قراءة الصيغة الست عشرية إلى بايتات — فك مفتاح خزنة قائم (حرفان لكل
/// بايت حصراً وإلا رفض صوت عالٍ فلا مفتاح مشوه يفتح قاعدة بأخطاء غامضة).
Uint8List dbKeyFromHex(String keyHex) {
  if (keyHex.length != kDbKeyBytes * 2 ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(keyHex)) {
    throw StateError('مفتاح الخزنة ليس 64 خانة ست عشرية — الافتتاح محسوب');
  }
  final out = Uint8List(kDbKeyBytes);
  for (var i = 0; i < kDbKeyBytes; i++) {
    out[i] = int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// هل الملف قاعدة SQLite نص صريح؟ — القراءة بايتاتية من الترويسة حصراً
/// (درس س96 الموثق: فتح الملف الخام يجري نقطة فحص عند الإغلاق فتمحو
/// wal/shm قبل نسخها؛ قراءة الترويسة لا تفتح شيئاً). ملف مشفر بـMC لا
/// يحمل سحر «SQLite format 3» أصلاً فالنص الصريح وحده يمر.
bool fileIsPlaintextSqlite(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 100) return false;
    const magic = 'SQLite format 3';
    for (var i = 0; i < 15; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) return false;
    }
    return bytes[15] == 0;
  } catch (_) {
    return false;
  }
}

/// فحص debug لاتصال حامل تشفير — توثيق drift «Important notice» حرفاً:
/// `PRAGMA cipher` تُعاد غير فارغة على دمج MC حصراً (upstream SQLite
/// يعيدها فارغة). يُستدعى داخل assert فلا كلفة في الإصدار AOT (درس
/// س145 الموثق: رسائل assert تُقطع من بناء الإصدار).
bool debugCheckHasCipher(Database database) {
  return database.select('PRAGMA cipher;').isNotEmpty;
}

/// لقطة الأمان قبل التشفير — نمط snapshotBeforeUpgrade (D-197 — س96):
/// نسخ الملف وملفاته الجانبية (wal/shm) إلى لاحقة `.preenc` فأي مشكلة
/// لاحقة بالتشغيل المشفر تبقى اللقطة الأولى النقية قابلة للاسترجاع
/// بالبايتات.
///
/// القواعد (بعقد اللقطة الأصلية):
/// - قاعدة غائبة (أول تشغيل بلا ملف) — لا لقطة، فلا شيء يُخشى عليه.
/// - لقطة واحدة لكل ملف: إن وجدت `.preenc` فالأصل النقي الأول لا يُستبدل.
/// - فشل اللقطة ذاته لا يوقف الافتتاح أبداً — أقصى جهد لا حاجز (والترحيل
///   ذاته فشل آمن أصلاً: الأصل لا يُمس حتى إعادة التسمية الأخيرة).
Future<void> snapshotBeforeEncryption(String dbPath) async {
  final dbFile = File(dbPath);
  if (!await dbFile.exists()) return;
  if (await File('$dbPath.preenc').exists()) return;
  for (final suffix in const ['', '-wal', '-shm']) {
    final f = File('$dbPath$suffix');
    if (await f.exists()) {
      try {
        await f.copy('$dbPath.preenc$suffix');
      } catch (_) {
        // اللقطة أقصى جهد — فشل نسخ جانبي لا يعطل الافتتاح.
      }
    }
  }
}

/// تهريب علامة الاقتباس المفردة لمسارات SQL (النمط الموحد مع backup.dart).
String _sqlString(String path) => path.replaceAll("'", "''");

/// ترحيل قاعدة نص صريح إلى قاعدة مشفرة عند أول فتح — نمط drift الموثق
/// («Encrypting existing databases») حرفاً:
///   VACUUM INTO ملف مؤقت ← فتحه ← `PRAGMA rekey` بالمفتاح الخام ←
///   تحقق فتح بالمفتاح ← إعادة تسمية فوق المسار الأصلي.
///
/// الفشل الآمن بالتصميم: الأصل وملفاته الجانبية لا تُمس إلا بعد نجاح
/// التحقق كاملاً — وأي رمي في أي خطوة يمسح المؤقت ويترك الأصل سليماً
/// (الشاشة الحارسة D-197 تعرض الخطأ والقاعدة القديمة باقية).
///
/// يعيد صادقاً إذا جرى ترحيل فعلي، وكاذباً إن لم يوجد ما يُرحَّل (ملف
/// غائب = أول تشغيل، أو الملف مشفر أصلاً = تكرار آمن).
///
/// يرمي [StateError] إذا كانت البيئة بلا دمج تشفير (system sqlite3) —
/// فالـ rekey على غير MC لا يفعل شيئاً وترك القاعدة «مشفرة» زائفاً
/// هو النص الصريح الصامت ذاته الذي أُغلق هنا — فصوت عالٍ لا صمت.
Future<bool> migratePlainToEncrypted(
  String dbPath,
  String keyHex,
) async {
  final dbFile = File(dbPath);
  if (!await dbFile.exists()) return false;
  if (!fileIsPlaintextSqlite(dbPath)) return false; // مشفرة أصلاً أو غريبة

  final tmp = File('$dbPath.enc-migrate-tmp');
  if (await tmp.exists()) await tmp.delete();
  try {
    // ١) صورة متسقة من النص الصريح — الاتصال بلا مفتاح (MC يفتح النص
    // الصريح اتصالاً عادياً) وVACUUM INTO ذرية حتى والقاعدة بعمل.
    final plain = sqlite3.open(dbPath);
    try {
      plain.execute("VACUUM INTO '${_sqlString(tmp.path)}'");
    } finally {
      plain.close();
    }

    // ٢) إعادة تشفير الصورة في مكانها — `PRAGMA rekey` بالمفتاح الخام
    // (توثيق MC «Encrypting a plain unencrypted database in place»
    // وتوثيق drift بالجملة ذاتها). حارس البيئة أولاً: بلا دمج MC يكون
    // الـ rekey لا شيئاً والنمط فارغاً فالصوت عالٍ هنا قبل أي مساس.
    final enc = sqlite3.open(tmp.path);
    try {
      if (!debugCheckHasCipher(enc)) {
        throw StateError(
            'بيئة القاعدة بلا دمج تشفير (SQLite3MultipleCiphers) — '
            'الترحيل أُبطل فالقاعدة النص الصريح كما هي بلا مساس');
      }
      enc.execute('PRAGMA cipher = \'$kDbCipherScheme\'');
      enc.execute("PRAGMA rekey = \"x'$keyHex'\"");
    } finally {
      enc.close();
    }

    // ٣) تحقق حي على فتح جديد: الملف مشفر فعلاً والمفتاح الصحيح يقرأ
    // المخطط — فتح بلا مفتاح أو بمفتاح خاطئ يرفض فلا «مشفرة زائفة».
    final verify = sqlite3.open(tmp.path);
    try {
      verify.execute(dbKeyPragmaRaw(keyHex));
      verify.select('SELECT count(*) FROM sqlite_master');
    } finally {
      verify.close();
    }

    // ٤) الاستبدال: الأصل وملفاته الجانبية (محفوظة باللقطة .preenc)
    // تُمسح ثم المؤقت يتبنى المسار الأصلي — إعادة تسمية داخل المجلد نفسه.
    for (final suffix in const ['', '-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
    await tmp.rename(dbPath);
    return true;
  } catch (_) {
    // فشل آمن: المؤقت يُمسح والأصل وملفاته كما هي حرفاً.
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}

/// تصدير صورة صريحة (نص صريح) من قاعدة مشفرة — أساس النسخ الاحتياطي
/// بعد التشفير (P0-ج): النسخة بجيل v2 بمفتاح البرنامج D-060 لا تُمس —
/// لكن ما يُغلف الآن صورة نص صريح لا بايتات القاعدة المشفرة بمفتاح
/// الجهاز (كي تُفك النسخة على جهاز ثانٍ فمفتاح خزنته يخالف).
///
/// الآلية (توثيق MC «Remove encryption» + نمط drift): VACUUM INTO من
/// الاتصال المشفر الحي صورة مؤقتة ذرية (مشفرة بمفتاح الجهاز) ثم فتحها
/// بالمفتاح و`PRAGMA rekey = ''` فتُنزع التشفيرة في مكانها — والملف
/// الناتج نص صريح كامل يُغلف بجيل v2 باقياً حرفاً.
///
/// يرمي [StateError] على بيئة بلا دمج تشفير — نفس حارس الترحيل.
Future<void> decryptImageInPlace(
  String imagePath,
  String keyHex,
) async {
  final enc = sqlite3.open(imagePath);
  try {
    enc.execute(dbKeyPragmaRaw(keyHex));
    if (!debugCheckHasCipher(enc)) {
      throw StateError(
          'بيئة القاعدة بلا دمج تشفير (SQLite3MultipleCiphers) — '
          'تصدير الصورة الصريحة أُبطل فلا نسخة مشفرة بمفتاح جهاز');
    }
    enc.execute("PRAGMA rekey = ''");
  } finally {
    enc.close();
  }
  // تحقق حي على فتح جديد بلا مفتاح: الملف نص صريح فعلاً فيقرأ المخطط.
  final verify = sqlite3.open(imagePath);
  try {
    verify.select('SELECT count(*) FROM sqlite_master');
  } finally {
    verify.close();
  }
}
