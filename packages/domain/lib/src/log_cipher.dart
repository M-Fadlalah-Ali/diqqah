import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// p3 (س146 — خط التشفير المرحلة الثالثة بجدول المستند «تشفير قاعدة
/// بيانات تطبيق المحاسبة» الخامس): تشفير سجلات الأحداث والأخطاء.
///
/// سجل الأحداث (جدول `events` — D-067) هو بذرة المزامنة m4، وسجل
/// الأخطاء (`error_log` — س107) يحمل ما كشفته الاستثناءات من سياق
/// تشغيلي — وكلاهما حتى س146 كان نصاً صريحاً داخل القاعدة، فيقرأه
/// أي أداة SQLite بلا حاجز. هذه الوحدة تسد ذلك بنمط الوثيقة المعتمد:
///
/// - **AES-256-GCM لكل سجل** (المعادلة «أو لكل سطر» بنص الوثيقة):
///   نونس عشوائي 12 بايتة لكل سجل فلا نمط متكرر يُلاحظ بين سجلات
///   متشابهة (بند «IV فريد لكل صفحة»)، ووسم GCM يكشف أي عبث ببايت
///   واحد قبل اكتمال الفك.
/// - **HKDF-SHA256** بملح القاعدة العشوائي (`p3_log_salt` بـapp_meta
///   يُزرع أول مرة) وسياق اشتقاق ثابت يعزل مفتاح السجلات عن كل
///   استخدام آخر — اختراق مسار لا يعطي الآخر.
/// - **جذر هذا الجهاز من الخزنة — د11 الجزء الثاني (س230/D-225):
///   وفاء بند P1/P2 بالجدول وإغلاق G-02 للسجلات.** الجذر يُحقن
///   [LogCipher] بجذر عشوائي 256-bit لكل جهاز يولَّد بخزنة الجهاز
///   عند أول تشغيل (Keystore أندرويد / DPAPI ويندوز — بذات افتراضات
///   خزنة القاعدة P0-ب س148)، ويسافر مغلَّفاً بالنسخة الاحتياطية
///   (سجل نوع 4 تحت DEK — BackupCipher س230) مع إعادة ختم سجلات
///   النسخة بجذر الجهاز المستقر عند الاستعادة — فبذرة المزامنة m4
///   تُقرأ على الجهاز ذاته بعد الاستعادة حرفاً (الخلاف المحسوم بد11).
///   غياب الجذر (خزنة فاشلة) = الجذر الإرثي المضمّن انخفاضاً موثقاً
///   بنمط مواد النسخ عينه — لا صمت استثناء.
/// - **الجذر الإرثي المضمّن قارئاً حصراً**: العقد القائم من اليوم
///   الأول — تغيّر مصدر المفتاح لا يقطع طريق السجلات القديمة — فكل
///   غلاف خُتم بالجذر المضمّن قبل س230 يظل مقروءًا على أي جهاز،
///   ووسم GCM الحاكم يرفض الالتباس (جذر خطأ = فك فاشل = استثناء
///   سلامة لا نص ملفّق).
/// - **التوافق الرجعي بالبادئة حصراً**: الغلاف المعتمد `dq3log1:`
///   ثم base64(نونس + نص مشفر + وسم). ما لا يبدأ بالبادئة يُعاد
///   كما هو (سجلات ما قبل v28 المقروءة قبل إحكامها) — فلا قراءة
///   تنكسر.
class LogCipher {
  /// بادئة الغلاف المعتمد نصاً — تفصل المشفر عن النص الخام القديم
  /// بلا أي تخمين، وهي الحارس الوحيد لمسار التوافق الرجعي. ASCII
  /// خالص فمساواته بالبايتات وثابتة بالترميزين.
  static const String envelopePrefix = 'dq3log1:';

  /// سياق اشتقاق مفتاح السجلات — ثابت يعزل هذا الاستعمال عن مفتاح
  /// النسخ الاحتياطية (diqqah-backup-v2) وعن أي مسار مستقبلي.
  static final List<int> _hkdfInfo = utf8.encode('diqqah-event-log-v1');

  /// الجذر الإرثي المضمّن (جذر س146 قبل س230) — **قارئاً حصراً** بعد
  /// د11 الجزء الثاني: السجلات الجديدة تُختم بجذر الجهاز، والقديمة
  /// المختومة بهذا الجذر تُقرأ على أي جهاز (عقد القراءة الإرثية عينه
  /// الموثق بمفتاح البرنامج لنسخ v2). 32 بايتة مستقلة عن جذر النسخ
  /// الاحتياطية (فصل النطاقات من الجذر لا من الاشتقاق حصراً).
  static const List<int> _legacyRootKey = [
    31, 214, 87, 8, 176, 99, 34, 130, //
    90, 141, 240, 67, 25, 108, 201, 6, //
    152, 62, 121, 189, 5, 74, 223, 16, //
    88, 45, 131, 246, 173, 96, 15, 224, //
  ];

  /// جذر هذا الجهاز — null = الجذر الإرثي (انخفاض موثق: خزنة غائبة).
  final List<int>? _rootKey;

  /// جذر الختم والقراءة الأول — جذر الجهاز حاضراً والإرثي غائباً.
  ///
  /// جذر قصير أو شاذ يُرفض صوتاً عالياً (لا مشفر بمفتاح مبتور): 32
  /// بايتة حصراً بنمط توليد generateDbKey عينه.
  LogCipher([List<int>? rootKey])
      : _rootKey = (rootKey == null || rootKey.isEmpty)
            ? null
            : (rootKey.length == 32
                ? List<int>.unmodifiable(rootKey)
                : throw ArgumentError(
                    'جذر السجلات 32 بايتة حصراً — الطول ${rootKey.length} شاذ'));

  /// الجذر الأول للختم والفك — جذر الجهاز أو الإرثي المضمّن.
  List<int> get _primaryRoot => _rootKey ?? _legacyRootKey;

  static const int _nonceLen = 12;
  static const int _macLen = 16;

  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// ذاكرة اشتقاق — HKDF اشتقاق سريع (لا PBKDF2)، والمفتاح الواحد
  /// لجذر وملح واحد يُشتق مرة لا مع كل سجل.
  final Map<String, Future<List<int>>> _derivedCache = {};

  /// مفتاح السجلات من الجذر بملح القاعدة — HKDF-SHA256 بسياق ثابت.
  Future<List<int>> deriveKey(String saltHex) =>
      _deriveFor(_primaryRoot, saltHex);

  Future<List<int>> _deriveFor(List<int> root, String saltHex) {
    final cacheKey =
        '${root.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'
        ':$saltHex';
    return _derivedCache.putIfAbsent(cacheKey, () async {
      final derived = await _hkdf.deriveKey(
        secretKey: SecretKeyData(Uint8List.fromList(root)),
        nonce: utf8.encode(saltHex),
        info: _hkdfInfo,
      );
      return derived.extractBytes();
    });
  }

  /// يشفّر نص سجل (حمولة JSON حدث أو رسالة خطأ) ويعيد الغلاف
  /// المعتمد — نونس جديد عشوائي مع كل نداء فسجلا حكما متطابقان
  /// لا تتطابق بايتاتهما. الختم بجذر الجهاز حصراً (الجذر الإرثي
  /// إن غاب — انخفاض موثق لا مفتاحان معاً).
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
  /// (توافق قراءة لسجلات ما قبل الإحكام). الفك بالجذر الأول ثم
  /// الإرثي المضمّن قارئاً (سجلات ما قبل س230)، وأي عبث ببايت واحد
  /// يكسر وسم GCM فتُرمى [LogCipherIntegrityException] قبل تسليم نص.
  Future<String> open(String envelope, String saltHex) async {
    if (!envelope.startsWith(envelopePrefix)) {
      return envelope;
    }
    try {
      return await _openWith(envelope, saltHex, _primaryRoot);
    } on LogCipherIntegrityException {
      if (identical(_primaryRoot, _legacyRootKey) ||
          _bytesEqual(_primaryRoot, _legacyRootKey)) {
        rethrow;
      }
      return _openWith(envelope, saltHex, _legacyRootKey);
    }
  }

  /// فك الغلاف بجذور مرشحة بالترتيب (س230 — مسار الاستعادة) — أول
  /// GCM سليم يفتح: جذر النسخة المحمول بالملف ثم جذر هذا الجهاز
  /// (لقطة رجوع على الجهاز ذاته)، والجذر الإرثي المضمّن يُجرَّب
  /// أخيراً دائماً بعقد القراءة الإرثية نفسه. نفاد الجذور = استثناء
  /// سلامة واحد صريح (لا نص ملفّق ولا سكوت).
  Future<String> openWithRoots(
    String envelope,
    String saltHex,
    List<List<int>?> roots,
  ) async {
    if (!envelope.startsWith(envelopePrefix)) {
      return envelope;
    }
    final ordered = <List<int>>[];
    void add(List<int>? root) {
      if (root == null || root.isEmpty) return;
      if (root.length != 32) {
        throw ArgumentError('جذر السجلات 32 بايتة حصراً');
      }
      if (!ordered.any((r) => _bytesEqual(r, root))) {
        ordered.add(root);
      }
    }

    for (final root in roots) {
      add(root);
    }
    add(_legacyRootKey); // القراءة الإرثية عقد دائم — أخيراً حصراً.
    LogCipherIntegrityException? lastError;
    for (final root in ordered) {
      try {
        return await _openWith(envelope, saltHex, root);
      } on LogCipherIntegrityException catch (e) {
        lastError = e; // جذر خطأ لهذا السجل — التالي بالترتيب.
      }
    }
    throw lastError ?? const LogCipherIntegrityException();
  }

  Future<String> _openWith(
      String envelope, String saltHex, List<int> root) async {
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
        secretKey: SecretKeyData(await _deriveFor(root, saltHex)),
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const LogCipherIntegrityException();
    } on FormatException {
      throw const LogCipherIntegrityException();
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
