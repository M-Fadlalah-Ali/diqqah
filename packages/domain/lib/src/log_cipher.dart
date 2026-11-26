import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// p3 (س146 — خط التشفير المرحلة الثالثة بجدول المستند «تشفير قاعدة
/// بيانات تطبيق المحاسبة» الخامس): تشفير سجلات الأحداث والأخطاء.
///
/// سجل الأحداث (جدول `events` — D-067) هو بذرة المزامنة m4، وسجل
/// الأخطاء (`error_log` — س107) يحمل ما كشفته الاستثناءات من سياق
/// تشغيلي — وكلاهما حتى اليوم نص صريح داخل القاعدة، فيقرأه أي أداة
/// SQLite بلا حاجز. هذه الوحدة تسد ذلك بنمط الوثيقة المعتمد:
///
/// - **AES-256-GCM لكل سجل** (المعادلة «أو لكل سطر» بنص الوثيقة):
///   نونس عشوائي 12 بايتة لكل سجل فلا نمط متكرر يُلاحظ بين سجلات
///   متشابهة (بند «IV فريد لكل صفحة»)، ووسم GCM يكشف أي عبث ببايت
///   واحد قبل اكتمال الفك.
/// - **HKDF-SHA256** بملح القاعدة العشوائي (`p3_log_salt` بـapp_meta
///   يُزرع أول مرة) وسياق اشتقاق ثابت يعزل مفتاح السجلات عن كل
///   استخدام آخر — اختراق مسار لا يعطي الآخر.
/// - **مفتاح الجذر مؤقتاً مضمّن** — الحد الصادق نفسه الموثق بـD-060
///   للنسخ الاحتياطية («ستارة خصوصية لا صندوق أمان»): التشفير يغلق
///   القراءة العابر للقاعدة خارج التطبيق ويكشف العبث، والترقية إلى
///   مفتاح من الخزنة الآمنة (Keystore/Keychain/DPAPI — بنود P1/P2
///   بالجدول) هي الخطوة اللاحقة المعتمدة حين يفتح بند الخزنة.
/// - **التوافق الرجعي بالبادئة حصراً**: الغلاف المعتمد `dq3log1:` ثم
///   base64(نونس + نص مشفر + وسم). ما لا يبدأ بالبادئة يُعاد كما هو
///   (سجلات ما قبل v28 المقروءة قبل إحكامها) — فلا قراءة تنكسر.
class LogCipher {
  /// بادئة الغلاف المعتمد نصاً — تفصل المشفر عن النص الخام القديم
  /// بلا أي تخمين، وهي الحارس الوحيد لمسار التوافق الرجعي. ASCII
  /// خالص فمساواته بالبايتات وثابتة بالترميزين.
  static const String envelopePrefix = 'dq3log1:';

  /// سياق اشتقاق مفتاح السجلات — ثابت يعزل هذا الاستعمال عن مفتاح
  /// النسخ الاحتياطية (diqqah-backup-v2) وعن أي مسار مستقبلي.
  static final List<int> _hkdfInfo = utf8.encode('diqqah-event-log-v1');

  /// مفتاح الجذر المؤقت المضمّن — 32 بايتة مستقلة عن مفتاح النسخ
  /// الاحتياطية (فصل النطاقات من الجذر لا من الاشتقاق حصراً).
  static const List<int> _rootKey = [
    31, 214, 87, 8, 176, 99, 34, 130, //
    90, 141, 240, 67, 25, 108, 201, 6, //
    152, 62, 121, 189, 5, 74, 223, 16, //
    88, 45, 131, 246, 173, 96, 15, 224, //
  ];

  static const int _nonceLen = 12;
  static const int _macLen = 16;

  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// ذاكرة اشتقاق — HKDF اشتقاق سريع (لا PBKDF2)، والمفتاح الواحد
  /// لملح القاعدة الواحد يُشتق مرة لا مع كل سجل.
  final Map<String, Future<List<int>>> _derivedCache = {};

  /// مفتاح السجلات من الجذر بملح القاعدة — HKDF-SHA256 بسياق ثابت.
  Future<List<int>> deriveKey(String saltHex) {
    return _derivedCache.putIfAbsent(saltHex, () async {
      final derived = await _hkdf.deriveKey(
        secretKey: SecretKeyData(Uint8List.fromList(_rootKey)),
        nonce: utf8.encode(saltHex),
        info: _hkdfInfo,
      );
      return derived.extractBytes();
    });
  }

  /// يشفّر نص سجل (حمولة JSON حدث أو رسالة خطأ) ويعيد الغلاف
  /// المعتمد — نونس جديد عشوائي مع كل نداء فسجلا حكما متطابقان
  /// لا تتطابق بايتاتهما.
  Future<String> seal(String plaintext, String saltHex) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKeyData(await deriveKey(saltHex)),
      nonce: nonce,
    );
    final body = BytesBuilder()
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return envelopePrefix + base64Encode(body.toBytes());
  }

  /// يفك الغلاف إلى نصه الأصلي — وما لا يحمل البادئة يُعاد كما هو
  /// (توافق قراءة لسجلات ما قبل الإحكام). أي عبث ببايت واحد يكسر
  /// وسم GCM فتُرمى [LogCipherIntegrityException] قبل تسليم نص.
  Future<String> open(String envelope, String saltHex) async {
    if (!envelope.startsWith(envelopePrefix)) {
      return envelope;
    }
    try {
      final raw = base64Decode(envelope.substring(envelopePrefix.length));
      if (raw.length < _nonceLen + _macLen) {
        throw const LogCipherIntegrityException();
      }
      final nonce = raw.sublist(0, _nonceLen);
      final mac = Mac(raw.sublist(raw.length - _macLen));
      final cipherText = raw.sublist(_nonceLen, raw.length - _macLen);
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: SecretKeyData(await deriveKey(saltHex)),
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const LogCipherIntegrityException();
    } on FormatException {
      throw const LogCipherIntegrityException();
    }
  }

  /// ملح جديد 16 بايتة — يُستدعى من التخزين عند زرع `p3_log_salt`
  /// أول مرة (مسار العتاد: randomblob بالSQL بديل مكافئ هناك).
  static List<int> newSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }
}

/// يُرمى عند فشل وسم GCM أو تلف الغلاف — دليل عبث أو تلف بالسجل
/// (رمز الخريطة DQ-1108). لا يُبلَع صامتاً عند القراءات الحاكمة،
/// وقراءات العرض تُبلعه بعرف «الفاسد كالغائب» الموثق D-169.
class LogCipherIntegrityException implements Exception {
  const LogCipherIntegrityException();

  @override
  String toString() => 'LogCipherIntegrityException: '
      'سجل مشفر تالف أو مُعبث به (DQ-1108)';
}
