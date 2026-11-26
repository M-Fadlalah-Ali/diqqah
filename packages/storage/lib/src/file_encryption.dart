import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data'
    show BytesBuilder, Uint8List;

import 'package:cryptography/cryptography.dart';

/// تشفير الملفات المصاحبة على الجهاز — صور الأصناف بمجلد `images/`
/// بجوار القاعدة — P1-ب (س149/D-210 بكلمة المالك «أوافق على توصياتك
/// في النقاط الأربعة»): كانت الصور نصاً صريحاً على القرص موثقاً بحدود
/// س148 الصادقة، فهنا تُشفَّر بنمط DEK/KEK والKEK بخزنة الجهاز:
///
/// - **KEK** (مفتاح تغليف المفاتيح): 32 بايتة عشوائية من خزنة الجهاز
///   (`SecureStorageKeyVault.forImages` — Keystore أندرويد / DPAPI
///   ويندوز، عين فلسفة P0-ب F-150: «المفتاح يولَّد ويُحفظ في خزنة
///   الجهاز لا في الكود»).
/// - **DEK** (مفتاح بيانات): عشوائي 256-bit لكل ملف حصراً — البيانات
///   تُشفَّر به حصراً (AES-256-GCM)، وهو نفسه يُغلَّف بمفتاح ملف مشتق
///   من KEK بHKDF-SHA256 بملح عشوائي خاص بالملف (فصل سياق
///   `diqqah-images-v1`) — فتدوير KEK مستقبلاً يعيد التغليف وحده
///   بلا مساس بالبيانات، وملفان بمحتوى واحد لا يتطابقان بايتات.
/// - وسم GCM في الغلاف والبيانات: أي عبث أو مفتاح غريب يُرفض قبل
///   إعادة بايت واحد («لا فجوة صامتة»).
///
/// التوافق الصادق: الملفات النص الصريح القائمة (أيام ما قبل س149)
/// تُرحَّل عند الافتتاح بمسار [migratePlainImagesToEncrypted] الذري
/// لكل ملف (كتابة مؤقتة ثم إعادة تسمية — الأصل لا يُمس حتى اللحظة
/// الأخيرة، فشل ملف لا يوقف البقية ولا الافتتاح)، ومسار الجمع
/// والاستعادة يقبل الشكلين فلا نسخة قديمة تنكسر.
class ImageFileCipher {
  /// بطاقة الملف المشفر — «DQIMGENC» أول 8 بايتات.
  static final List<int> magic = utf8.encode('DQIMGENC');

  /// إصدار التنسيق الجاري — يُقرأ ولا يُكتب غيره.
  static const int formatVersion = 1;

  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _macLen = 16;
  static const int _dekLen = 32;

  /// سياق اشتقاق مفتاح التغليف — يعزل ملفات الصور عن غيرها من
  /// استعمالات KEK ذاته.
  static final List<int> _hkdfInfo = utf8.encode('diqqah-images-v1');

  /// مفتاح تغليف المفاتيح — من خزنة الجهاز حصراً (F-150 روحاً).
  final Uint8List kek;

  final AesGcm _aes;
  final Hkdf _hkdf;

  ImageFileCipher(Uint8List inputKek)
      : kek = Uint8List.fromList(inputKek),
        _aes = AesGcm.with256bits(),
        _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32) {
    if (inputKek.length != _dekLen) {
      throw StateError('مفتاح KEK ليس 32 بايتة — الخزنة رفضت');
    }
  }

  /// هل البايتات ملف صورة مشفر بجيل هذا البرنامج؟ — فحص بطاقة حصراً
  /// بلا فتح ولا فك (درس س96: قراءة الترويسة لا تفتح شيئاً).
  static bool isEncryptedImage(List<int> bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// يشفّر بايتات صورة خام: DEK عشوائي لكل ملف ← تغليفه بمفتاح مشتق
  /// من KEK بHKDF بملح الملف ← تشفير البيانات بالـDEK.
  Future<List<int>> encrypt(List<int> plain, [Random? rng]) async {
    final dek = _random(_dekLen, rng);
    final salt = _random(_saltLen, rng);
    final wrapBox = await _aes.encrypt(
      dek,
      secretKey: await _wrapKey(salt),
      nonce: _aes.newNonce(),
    );
    final dataBox = await _aes.encrypt(
      plain,
      secretKey: SecretKeyData(dek),
      nonce: _aes.newNonce(),
    );
    final out = BytesBuilder()
      ..add(magic)
      ..addByte(formatVersion)
      ..add(salt)
      ..add(wrapBox.nonce)
      ..add(wrapBox.mac.bytes)
      ..add(wrapBox.cipherText)
      ..add(dataBox.nonce)
      ..add(dataBox.cipherText)
      ..add(dataBox.mac.bytes);
    return out.toBytes();
  }

  /// يفك ملف صورة مشفر — وسم غلاف DEK حاكم أولاً (مفتاح جهاز غريب أو
  /// KEK مفقود = رفض صريح واحد)، ثم وسم البيانات. البنية الشاذة بأي
  /// شكل رفض قبل أي استعمال.
  Future<List<int>> decrypt(List<int> blob) async {
    if (!isEncryptedImage(blob)) {
      throw const ImageCipherException('الملف ليس صورة مشفرة بجيل البرنامج');
    }
    final base = magic.length + 1;
    if (blob.length <
        base + _saltLen + _nonceLen + _macLen + _dekLen + _nonceLen + _macLen) {
      throw const ImageCipherException('بنية الملف المشفر تالف — أقصر من الحد');
    }
    var i = base;
    final salt = blob.sublist(i, i + _saltLen);
    i += _saltLen;
    final wrapNonce = blob.sublist(i, i + _nonceLen);
    i += _nonceLen;
    final wrapMac = Mac(blob.sublist(i, i + _macLen));
    i += _macLen;
    final wrappedDek = blob.sublist(i, i + _dekLen);
    i += _dekLen;
    Uint8List dek;
    try {
      final dekBytes = await _aes.decrypt(
        SecretBox(wrappedDek, nonce: wrapNonce, mac: wrapMac),
        secretKey: await _wrapKey(salt),
      );
      dek = Uint8List.fromList(dekBytes);
    } on SecretBoxAuthenticationError {
      throw const ImageCipherException(
          'مفتاح هذا الجهاز لا يفك الملف — KEK الخزنة يخالف أو الملف تالف');
    }
    final dataNonce = blob.sublist(i, i + _nonceLen);
    i += _nonceLen;
    final cipherText = blob.sublist(i, blob.length - _macLen);
    final dataMac = Mac(blob.sublist(blob.length - _macLen));
    try {
      return await _aes.decrypt(
        SecretBox(cipherText, nonce: dataNonce, mac: dataMac),
        secretKey: SecretKeyData(dek),
      );
    } on SecretBoxAuthenticationError {
      throw const ImageCipherException('فك بيانات الصورة فشل — الملف تالف');
    }
  }

  /// مفتاح تغليف الملف من KEK — HKDF-SHA256 بملح الملف العشوائي:
  /// اشتقاق سريع (السر في ثبات KEK بالخزنة لا في بطء الاشتقاق — عرف
  /// BackupCipher v2 ذاته).
  Future<SecretKey> _wrapKey(List<int> salt) => _hkdf.deriveKey(
        secretKey: SecretKeyData(kek),
        nonce: salt,
        info: _hkdfInfo,
      );

  static List<int> _random(int length, [Random? rng]) {
    final r = rng ?? Random.secure();
    return List<int>.generate(length, (_) => r.nextInt(256));
  }
}

/// يُرمى عند فشل فك ملف صورة مشفر أو تلف بنيته — رفض صريح لا صمت.
class ImageCipherException implements Exception {
  final String message;
  const ImageCipherException(this.message);

  @override
  String toString() => message;
}

/// ترحيل الصور النص الصريح القائمة إلى التشفير — دفعة عند الافتتاح
/// (P1-ب): لكل ملف في المجلد (تكرارياً): مشفر أصلاً أو فارغ أو أقصر
/// من البطاقة = يُترك كما هو؛ وإلا يُشفَّر لملف مؤقت `<name>.enc-tmp`
/// ثم إعادة تسمية فوق الأصل — **استبدال ذري داخل المجلد نفسه فالأصل
/// سليم بالبايتات حتى لحظة إعادة التسمية الأخيرة** (نمط ترحيل القاعدة
/// P0 نفسه روحاً).
///
/// يعيد زوج (المُرحَّل، الفاشل): فشل ملف واحد (محجوز/غير مقروء) لا
/// يوقف البقية ولا الافتتاح — الملف الفاشل يبقى نص صريح سليماً
/// وتُعاد محاولته في الافتتاح التالي. الجدار الثاني: ملف نص صريح
/// يبقى مقروءاً بجمع النسخ والعرض حتى يُرحَّل — فلا فقد ولا فجوة
/// يبتلعها صمت.
Future<(int, int)> migratePlainImagesToEncrypted(
  Directory dir,
  ImageFileCipher cipher,
) async {
  if (!await dir.exists()) return (0, 0);
  var migrated = 0;
  var failed = 0;
  final files = dir.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    try {
      // قراءة بطاقة حصراً أولاً (درس س96) — لا فك ولا تشفير لمشفر
      // أصلاً، والمخلفات الفارغة تُترك لحارس الجمع كما كانت.
      final raf = await f.open(mode: FileMode.read);
      List<int> head;
      try {
        head = await raf.read(ImageFileCipher.magic.length);
      } finally {
        await raf.close();
      }
      if (head.length < ImageFileCipher.magic.length) continue;
      if (ImageFileCipher.isEncryptedImage(head)) continue;
      final plain = await f.readAsBytes();
      if (plain.isEmpty) continue;
      final enc = await cipher.encrypt(plain);
      final tmp = File('${f.path}.enc-tmp');
      await tmp.writeAsBytes(enc, flush: true);
      await tmp.rename(f.path);
      migrated++;
    } catch (_) {
      // فشل آمن لكل ملف: المؤقت يُمسح إن كُتب والأصل كما هو حرفاً.
      try {
        final tmp = File('${f.path}.enc-tmp');
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      failed++;
    }
  }
  return (migrated, failed);
}
