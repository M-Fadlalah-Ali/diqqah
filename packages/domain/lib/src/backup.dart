import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'setup.dart';

/// تشفير النسخ الاحتياطية (F-012): AES-256-GCM.
///
/// D-060 (قرار المالك 2026-10-29 بلفظه «كلمة السر للبرنامج فقط»):
/// النسخ الجديدة تُشفَّر بمفتاح البرنامج حصراً — لا كلمة مرور للمستخدم —
/// فيفتح الملف داخل التطبيق نفسه وحده على أي جهاز (N-005 قائمة كما هي:
/// ثبّت ثم استعد بلا أي سؤال). الجيل القديم v1 المشتق من كلمة مرور
/// PBKDF2 — وترويسة الجيل الأسبق HESEBENC — يبقى مقروءاً بكلمته:
/// التزام دائم بأن تغيّر مصدر المفتاح لا يقطع طريق النسخ القديمة.
///
/// الصدق الموثق في السجلات: المفتاح داخل برنامج موزع للعموم قابل
/// للاستخراج التقني بالهندسة العكسية — فهذا التشفير «ستارة خصوصية
/// لا صندوق أمان»: يمنع الفتح العابر للملف خارج التطبيق ولا يصمد
/// أمام خصم تقني متفرغ. قراره المالك بهذا الوصف لا بغيره.
class BackupCipher {
  /// ترويسة النسخة المشفرة — «DIQQENC» (D-053: التسمية الموحدة).
  static final List<int> magic = utf8.encode('DIQQENC');

  /// ترويسة الجيل السابق «HESEBENC» — تُقرأ ولا تُكتب بعد إعادة التسمية:
  /// نسخ «حسيب» القديمة تبقى مفتوحة كما هي، والجديدة تُكتب بالترويسة
  /// الجديدة (توافق قراءة لا كتابة). الترويستان مختلفتا الطول — ثمانية
  /// وسبعة — وكلتاهما تليها بايتة الإصدار، فبنية ما بعدهما واحدة والإزاحة
  /// تُحسب من طول الترويسة المطابقة فعلاً (علة CI 2026-10-28).
  static final List<int> legacyMagic = utf8.encode('HESEBENC');

  /// إصدار التنسيق الجاري كتابته: 2 = مفتاح البرنامج (D-060).
  static const int formatVersion = 2;

  /// إصدار الجيل القديم بكلمة المرور (أيام D-050) — للقراءة حصراً.
  static const int legacyFormatVersion = 1;

  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _macLen = 16;

  /// سياق اشتقاق مفتاح الملف — ثابت يعزل هذا الاستعمال عن غيره.
  static final List<int> _hkdfInfo = utf8.encode('diqqah-backup-v2');

  /// مفتاح البرنامج الرئيسي (D-060) — 32 بايتة ثابتة داخل التطبيق، واحدة
  /// على كل الأجهزة، ومنها يُشتق مفتاح كل ملف بملحه العشوائي الخاص به
  /// (HKDF-SHA256). ثباته عبر الأجهزة هو ما يحفظ N-005: أي تثبيت للتطبيق
  /// يفتح أي نسخة أنتجها التطبيق أينما وُلدت.
  static const List<int> _masterKey = [
    104, 10, 149, 151, 247, 89, 196, 41, //
    126, 40, 28, 222, 145, 250, 119, 253, //
    183, 152, 202, 227, 113, 186, 40, 249, //
    136, 199, 89, 137, 19, 240, 136, 91, //
  ];

  /// تكرارات اشتقاق الجيل القديم v1 — لا تُستعمل إلا بقراءة النسخ القديمة.
  final int iterations;

  final AesGcm _aes;
  final Hkdf _hkdf;

  BackupCipher({this.iterations = 100000})
      : _aes = AesGcm.with256bits(),
        _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// يميز نوع الملف دون أي فك: مشفرة / SQLite خام / مجهول.
  static BackupKind identify(List<int> blob) {
    if (_startsWith(blob, magic) || _startsWith(blob, legacyMagic)) {
      return BackupKind.encrypted;
    }
    if (_startsWith(blob, utf8.encode('SQLite format 3'))) {
      return BackupKind.plainSqlite;
    }
    return BackupKind.unknown;
  }

  /// بايتة إصدار ملف مشفر (1 = قديم بكلمة مرور، 2 = مفتاح البرنامج)
  /// و0 لغير المشفر — تحدد مسار الفك قبل أي محاولة.
  static int encryptedVersion(List<int> blob) {
    if (_startsWith(blob, legacyMagic)) return blob[legacyMagic.length];
    if (_startsWith(blob, magic)) return blob[magic.length];
    return 0;
  }

  /// يشفّر بايتات قاعدة خام بمفتاح البرنامج (D-060) — الترويسة بإصدار 2.
  /// مفتاح كل ملف مشتق بملح عشوائي خاص به: نسختان لمحتوى واحد لا تتطابق
  /// بايتات، ووسم GCM يحقق «تحقق من سلامة الملف (وتشفيره إن وجد)» في
  /// F-013: أي عبث يُرفض قبل وصول بايت واحد للقاعدة الحية.
  Future<List<int>> encrypt(List<int> plain) async {
    final salt = _random(_saltLen);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      plain,
      secretKey: await _deriveProgramKey(salt),
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

  /// يفك نسخة الجيل الحالي v2 بوسم GCM — بلا أي كلمة مرور (D-060).
  /// نسخة v1 تُرفض بتوجيه صريح إلى حقل كلمة المرور.
  Future<List<int>> decrypt(List<int> blob) async {
    if (identify(blob) != BackupKind.encrypted) {
      throw const BackupCipherException('الملف ليس نسخة مشفرة أصلاً');
    }
    final version = encryptedVersion(blob);
    if (version != formatVersion) {
      throw BackupCipherException(version == legacyFormatVersion
          ? 'النسخة من الجيل القديم المحمي بكلمة مرور — '
              'أدخلها في حقل كلمة المرور ثم أعد المحاولة'
          : 'إصدار تنسيق غير معروف: $version');
    }
    return _decryptEnvelope(
      blob,
      await _deriveProgramKey(_saltOf(blob)),
      'فك التشفير فشل — الملف تالف',
    );
  }

  /// الجيل القديم v1 (PBKDF2 بكلمة مرور): للقراءة حصراً بعد D-060.
  /// نسخة v2 تُرفض بتوجيه معاكس — تُفتح بلا كلمة أصلاً.
  Future<List<int>> decryptWithPassword(List<int> blob, String password) async {
    if (identify(blob) != BackupKind.encrypted) {
      throw const BackupCipherException('الملف ليس نسخة مشفرة أصلاً');
    }
    final version = encryptedVersion(blob);
    if (version != legacyFormatVersion) {
      throw BackupCipherException(version == formatVersion
          ? 'هذه نسخة جديدة بمفتاح البرنامج — تُفتح مباشرة بلا كلمة مرور'
          : 'إصدار تنسيق غير معروف: $version');
    }
    return _decryptEnvelope(
      blob,
      await _deriveKey(password, _saltOf(blob)),
      'كلمة المرور خاطئة أو الملف تالف',
    );
  }

  /// توليد ملفات الجيل القديم v1 بكلمة مرور — للاختبارات والتوافق فقط؛
  /// المنتج لا يكتب v1 بعد D-060.
  Future<List<int>> encryptWithPassword(
      List<int> plain, String password) async {
    final salt = _random(_saltLen);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      plain,
      secretKey: await _deriveKey(password, salt),
      nonce: nonce,
    );
    final out = BytesBuilder();
    out.add(magic);
    out.addByte(legacyFormatVersion);
    out.add(salt);
    out.add(box.nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  /// الهيكل المشترك للجيلين: الترويسة (7 أو 8) ← بايتة الإصدار ← الملح
  /// (16) ← النونس (12) ← النص المشفر ← وسم GCM (16) — والإزاحة من طول
  /// الترويسة المطابقة فعلاً (علة CI 2026-10-28).
  Future<List<int>> _decryptEnvelope(
    List<int> blob,
    SecretKey key,
    String failureMessage,
  ) async {
    final headerLen =
        _startsWith(blob, legacyMagic) ? legacyMagic.length : magic.length;
    // علّة CI 2026-10-29 (Task 59): الإزاحة يجب أن تجاوز الترويسة وبايتة
    // الإصدار والملح معاً — «قرأه المستدعي» لا يقدّم أي مؤشر فعلي؛ وبلا
    // تخطي الملح تُقرأ النونس من أول الملح فيفشل وسم GCM في كل فك بالجيلين.
    var i = headerLen + 1 + _saltLen;
    final nonce = blob.sublist(i, i + _nonceLen);
    i += _nonceLen;
    final cipherText = blob.sublist(i, blob.length - _macLen);
    final mac = Mac(blob.sublist(blob.length - _macLen));
    try {
      return await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      throw BackupCipherException(failureMessage);
    }
  }

  List<int> _saltOf(List<int> blob) {
    final headerLen =
        _startsWith(blob, legacyMagic) ? legacyMagic.length : magic.length;
    return blob.sublist(headerLen + 1, headerLen + 1 + _saltLen);
  }

  /// مفتاح الملف من مفتاح البرنامج — HKDF-SHA256 بملح الملف العشوائي:
  /// اشتقاق سريع (لا يحتاج تكرارات PBKDF2) لأن السر في ثبات المفتاح
  /// الرئيسي داخل التطبيق لا في بطء الاشتقاق.
  Future<SecretKey> _deriveProgramKey(List<int> salt) {
    return _hkdf.deriveKey(
      secretKey: SecretKeyData(Uint8List.fromList(_masterKey)),
      nonce: salt,
      info: _hkdfInfo,
    );
  }

  /// اشتقاق الجيل القديم v1 — PBKDF2-HMAC-SHA256 بكلمة المستخدم.
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
