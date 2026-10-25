import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'setup.dart';

/// تشفير النسخ الاحتياطية (F-012): AES-256-GCM بمفتاح PBKDF2-HMAC-SHA256.
///
/// القرار التنفيذي (جلسة م0 الثالثة — موثق في worklog): النسخة غير المشفرة
/// تبقى ملف SQLite خاماً (ملف واحد للقاعدة كاملة — يُفتح بأي أداة)،
/// والمشفرة تغلفه بترويسة ثابتة تكشف نفسها دون كلمة المرور. وسم GCM
/// يحقق «تحقق من سلامة الملف (وتشفيره إن وجد)» في F-013: أي عبث
/// أو كلمة مرور خاطئة يرفض قبل وصول بايت واحد للقاعدة الحية.
class BackupCipher {
  /// ترويسة النسخة المشفرة — «HESEBENC».
  static final List<int> magic = utf8.encode('HESEBENC');

  static const int formatVersion = 1;
  static const int _saltLen = 16;
  static const int _macLen = 16;

  /// تكرارات اشتقاق مفتاح النسخة — تحدث مرة عند النسخ ومرة عند الاستعادة
  /// لا في كل عملية، فالرقم الأعلى من تجزئة الدخول مقبول زمنياً.
  final int iterations;

  final AesGcm _aes;

  BackupCipher({this.iterations = 100000}) : _aes = AesGcm.with256bits();

  /// يميز نوع الملف دون أي فك: مشفرة / SQLite خام / مجهول.
  static BackupKind identify(List<int> blob) {
    if (_startsWith(blob, magic)) return BackupKind.encrypted;
    if (_startsWith(blob, utf8.encode('SQLite format 3'))) {
      return BackupKind.plainSqlite;
    }
    return BackupKind.unknown;
  }

  /// يشفّر بايتات قاعدة خام ويعيد الغلاف كاملاً بالترويسة.
  Future<List<int>> encrypt(List<int> plain, String password) async {
    final salt = _random(_saltLen);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      plain,
      secretKey: await _deriveKey(password, salt),
      nonce: nonce,
    );
    final out = BytesBuilder();
    out.add(magic);
    out.addByte(formatVersion);
    out.add(salt);
    out.add(box.nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  /// يفك الغلاف ويتحقق بوسم GCM — فشل الوسم يعني كلمة مرور خاطئة أو ملفاً تالفاً.
  Future<List<int>> decrypt(List<int> blob, String password) async {
    if (identify(blob) != BackupKind.encrypted) {
      throw const BackupCipherException('الملف ليس نسخة مشفرة أصلاً');
    }
    var i = magic.length;
    final version = blob[i];
    if (version != formatVersion) {
      throw BackupCipherException('إصدار تنسيق غير معروف: $version');
    }
    i += 1;
    final salt = blob.sublist(i, i + _saltLen);
    i += _saltLen;
    final nonce = blob.sublist(i, i + _nonceLen);
    i += _nonceLen;
    final cipherText = blob.sublist(i, blob.length - _macLen);
    final mac = Mac(blob.sublist(blob.length - _macLen));
    try {
      return await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: await _deriveKey(password, salt),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupCipherException('كلمة المرور خاطئة أو الملف تالف');
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) async {
    final key = PasswordHasher.pbkdf2Bytes(
        utf8.encode(password), salt, iterations, 32);
    return SecretKeyData(Uint8List.fromList(key));
  }

  static bool _startsWith(List<int> blob, List<int> prefix) {
    if (blob.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (blob[i] != prefix[i]) return false;
    }
    return true;
  }

  static List<int> _random(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

/// نوع ملف النسخة الاحتياطية — يُحدد مسار التحقق في الاستعادة.
enum BackupKind { encrypted, plainSqlite, unknown }

/// يُرمى عند فشل فك التشفير أو تلف الغلاف (F-013: تحقق قبل أي لمس).
class BackupCipherException implements Exception {
  final String message;
  const BackupCipherException(this.message);

  @override
  String toString() => message;
}
