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
///
/// P1-أ (س149/D-210 بكلمة المالك «أوافق على توصياتك في النقاط الأربعة»):
/// الجيل الثالث v3 يغلف مفتاح البيانات بكلمة مستخدم **اختيارية** ورمز
/// استرداد — النسخ بلا كلمة تبقى تُكتب بجيل v2 كما هي (لا تدوير صيغة
/// بلا علة)، والمقفلة تُكتب v3 بلا سجل مفتاح البرنامج عمداً: إبقاؤه
/// يجعل الكلمة ستارة فوق قفل مفتوح فلا معنى لها — فالمقفلة تُفك بكلمة
/// المرور أو رمز الاسترداد على أي جهاز، وقارئ v3 يقرأ v1/v2 كما تؤمن
/// (التزام دائم بأن تغيّر مصدر المفتاح لا يقطع طريق النسخ القديمة).
///
/// د11 (س229/D-225 الجزء الأول بكلمة المالك «ابدأ د11»): الجيل الرابع
/// v4 للنسخ غير المقفلة — **مفاتيح الخزنة** بدل مفتاح البرنامج
/// المضمّن (G-02 الأول): جذر عشوائي 32 بايتة لكل جهاز يولَّد في خزنة
/// الجهاز عند أول تشغيل (Keystore أندرويد / DPAPI ويندوز — VaultBackupKeys
/// بالواجهة بنمط SecureStorageKeyVault)، ومعه رمز استرداد بنمط v3
/// القائم يُطبع مرة واحدة عند أول تشغيل — والنسخ غير المقفلة تُكتب
/// v4 ببنية v3 عينها (DEK لكل ملف مغلَّف بسجلين): سجل مفتاح الخزنة
/// (فتح صامت على الجهاز ذاته) وسجل رمز الاسترداد (الفتح على أي جهاز
/// آخر) — فسيناريو «فتح النسخة على أي جهاز» (N-005) يلتئم بالرمز
/// بلا كسر (خلاف المحضر الاستشاري المحسوم بد11). مفتاح البرنامج
/// المضمّن يبقى **قارئاً حصراً** لنسخ v2 القديمة، والمقفلة v3 تبقى
/// v3 بلا سجل مفتاح خزنة عمداً (علة v3 ذاتها: الكلمة فوق قفل مفتوح
/// لا معنى لها).
///
/// د11 الجزء الثاني (س230/D-225 — مفاتيح السجلات، إغلاق ما تبقى من
/// G-02): جذر سجلات الأحداث والأخطاء ينتقل من المضمّن بالشيفرة إلى
/// خزنة الجهاز (جذر عشوائي 256-bit لكل جهاز بنمط p3 ذاته)، ويُغلق
/// المضمّن قارئاً إرثياً حصراً (سجلات ما قبل س230 مقروءة للأبد —
/// عقد القراءة الإرثية عينه الموثق بمفتاح البرنامج). **وسفر الجذر
/// عبر الأجهزة**: النسخة تحمل سجلاً رابعاً نوع 4 تحت DEK — جذر
/// السجلات مُشفَّراً بمفتاح الملف العشوائي — فمن يملك فك النسخة
/// (مفتاح جهازه أو الرمز أو كلمة القفل) يملك فك سجلاتها، ومع
/// الاستعادة يُعاد ختم السجلات بجذر الجهاز المستقر عليه فبذرة
/// المزامنة m4 تُقرأ بعد الاستعادة حرفاً. الأجيال الجديدة: v5
/// (الخزنة + سجل السجلات) وv6 (المقفلة + سجل السجلات) — والقديمة
/// v1..v4 تُقرأ حرفاً بعقدها القائم.
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

  /// إصدار الجيل المقفل بكلمة المستخدم ورمز الاسترداد (P1-أ س149) —
  /// يُكتب حصراً حين يُعيّن المالك قفل النسخ، ويُقرأ مع v1/v2.
  static const int lockedFormatVersion = 3;

  /// إصدار الجيل الرابع بمفاتيح الخزنة (د11 — س229/D-225 الجزء
  /// الأول): النسخ غير المقفلة تُكتب به حين تتوفر مواد الخزنة —
  /// DEK مغلّف بسجلين (مفتاح الخزنة + رمز الاسترداد)، ويُقرأ مع
  /// v1/v2/v3 (خيار المواد بجهاز القارئ).
  static const int vaultFormatVersion = 4;

  /// إصدار جيل الخزنة بحامل مفتاح السجلات (س230 — د11 الجزء الثاني):
  /// سجلا الخزنة (مفتاح الجهاز + الرمز) **وسجل رابع نوع 4** يحمل جذر
  /// سجلات الجهاز مشفراً بDEK الملف — يُكتب حين يحضر الجذر، وغيابه
  /// يعيد الكتابة v4 بعقد الانخفاض الموثق (أحداث مختومة إرثياً فلا
  /// سجل لها) — ويُقرأ مع كل الأجيال.
  static const int vaultLogFormatVersion = 5;

  /// إصدار الجيل المقفل بحامل مفتاح السجلات (س230): سجلا القفل
  /// (الكلمة + الرمز) وسجل رابع نوع 4 تحت DEK — المقفلة حاضرةَ
  /// الجذر تُكتب v6 (سجلاتها مسافرة معها فتُقرأ عبر الأجهزة) وغائبته
  /// تعود v3 حرفاً. لولا هذا السجل لكسر جيل الخزنة للسجلات استعادة
  /// المقفلة على جهاز آخر — علة مؤجلة حُسمت من يوم الجذر.
  static const int lockedLogFormatVersion = 6;

  /// إصدار الجيل القديم بكلمة المرور (أيام D-050) — للقراءة حصراً.
  static const int legacyFormatVersion = 1;

  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _macLen = 16;

  /// طول مفتاح البيانات DEK بالبايتات — 256-bit عشوائي لكل ملف مقفل.
  static const int _dekLen = 32;

  /// أنواع سجلات التغليف بجيل v3: 1 = كلمة المستخدم، 2 = رمز الاسترداد.
  /// لا سجل مفتاح البرنامج بالجيل المقفل تصميماً (راجع توثيق الصنف).
  static const int _recPassword = 1;
  static const int _recRecovery = 2;

  /// نوع سجل تغليف DEK بمفتاح الخزنة بجيل v4 (د11): جذر الجهاز
  /// العشوائي من خزنته — الفتح الصامت على الجهاز ذاته حصراً.
  static const int _recVaultKey = 3;

  /// نوع سجل مفتاح السجلات (س230 — د11 الجزء الثاني): جذر سجلات
  /// الجهاز (32 بايتة) مشفراً بDEK الملف نفسه — لا يُشتق من نص
  /// فلا ملح، والمفتاح عشوائي لكل ملف فلا إعادة استخدام: نونس (12)
  /// + وسم GCM (16) + جذر مشفر (32) = 60 بايتة بعد بايتة النوع.
  static const int _recLogKey = 4;

  /// طول سجل مفتاح السجلات: النوع (1) + النونس (12) + الوسم (16) +
  /// الجذر المشفر (32) = 61 بايتة ثابتة (بلا ملح — الشرح أعلاه).
  static const int _logRecordLen = 1 + _nonceLen + _macLen + _dekLen;

  /// طول سجل التغليف الواحد: النوع (1) + الملح (16) + النونس (12) +
  /// وسم GCM (16) + DEK المشفر (32) = 77 بايتة ثابتة.
  static const int _recordLen = 1 + _saltLen + _nonceLen + _macLen + _dekLen;

  /// سياق اشتقاق مفتاح الملف — ثابت يعزل هذا الاستعمال عن غيره.
  static final List<int> _hkdfInfo = utf8.encode('diqqah-backup-v2');

  /// سياق اشتقاق مفتاح سجل الخزنة بجيل v4 — معزل عن مفتاح البرنامج
  /// (v2) وعن سجلات القاعدة والمزامنة (فصل النطاقات من الاشتقاق).
  static final List<int> _vaultHkdfInfo =
      utf8.encode('diqqah-backup-vault-v1');

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

  /// هل النسخة مقفلة (v3 — أو v6 بسجل السجلات س230) وتحتاج كلمة
  /// مرور أو رمز استرداد لفكها؟ — نداء قبل prepareRestore كي يمرّر
  /// المستدعى أسرار الخزنة أو يطلبها.
  static bool needsUnlock(List<int> blob) {
    if (identify(blob) != BackupKind.encrypted) return false;
    final ver = encryptedVersion(blob);
    return ver == lockedFormatVersion || ver == lockedLogFormatVersion;
  }

  /// هل النسخة من جيل الخزنة (v4 — أو v5 بسجل السجلات س230)؟ — تُفك
  /// هنا بمفتاح هذا الجهاز صامتاً، وعلى جهاز آخر برمز الاسترداد
  /// المطبوع مرة واحدة: النداء قبل prepareRestore كي يمرر المستدعى
  /// مفتاح خزنته أو يطلب الرمز.
  static bool isVaulted(List<int> blob) {
    if (identify(blob) != BackupKind.encrypted) return false;
    final ver = encryptedVersion(blob);
    return ver == vaultFormatVersion || ver == vaultLogFormatVersion;
  }

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

  // ═══════════════════════════════════════════════════════════════
  // الجيل المقفل v3 — P1-أ (س149/D-210).
  //
  // البنية: الترويسة DIQQENC (7) ← بايتة الإصدار 3 ← عدّاد السجلات (1)
  // ← سجلات التغليف (77 بايتة لكل سجل: النوع 1 + الملح 16 + النونس 12
  // + وسم GCM 16 + DEK مشفر 32) ← نونس البيانات (12) ← النص المشفر
  // ← وسم GCM للبيانات (16).
  //
  // النمط DEK/KEK الموثق بمستوى النسخ أيضاً: مفتاح بيانات عشوائي 32
  // بايتة لكل ملف، تُشفّر البيانات به حصراً، ويُغلّف بسجلات مستقلة
  // بمفاتيح اشتقاق منفصلة: PBKDF2-HMAC-SHA256 (100,000 تكرار — عرف
  // النسخ القائم) لكلمة المستخدم ورمز الاسترداد، والرمز يُطبّع قبل
  // الاشتقاق (أحرف كبيرة وبلا شرطات ولا فراغات) فكتابته بأي هيئة
  // تعمل. وسم GCM في كل سجل هو المُحقّق: خاطئ = رفض السجل لا القبول.
  // ═══════════════════════════════════════════════════════════════

  /// يكتب نسخة مقفلة (v3 — أو v6 بسجل السجلات س230): البيانات بمفتاح
  /// عشوائي لكل ملف، والمفتاح مغلّف بسجلين — كلمة المستخدم ورمز
  /// الاسترداد — بلا سجل مفتاح البرنامج عمداً (توثيق الصنف: الكلمة
  /// فوق قفل مفتوح لا معنى لها). و[logRootKey] الحاضر (س230 — د11
  /// الجزء الثاني) يكتب سجلاً رابعاً نوع 4 يحمل جذر سجلات الجهاز تحت
  /// DEK فنسخة جهاز آخر تُستعاد بسجلاتها حية — وغيابه يعيد الكتابة
  /// v3 بعقد الانخفاض الموثق (أحداث مختومة إرثياً فلا سجل لها).
  Future<List<int>> encryptLocked(
    List<int> plain, {
    required String password,
    required String recoveryCode,
    List<int>? logRootKey,
    Random? rng,
  }) async {
    final dek = _random(_dekLen, rng);
    // سجل كلمة المستخدم — ملح ونونس مستقلان لكل سجل.
    final pwSalt = _random(_saltLen, rng);
    final pwBox = await _aes.encrypt(
      dek,
      secretKey: await _deriveKey(password, pwSalt),
      nonce: _aes.newNonce(),
    );
    // سجل رمز الاسترداد — بالمُطبَّع فأي هيئة كتابة تعمل عند الفك.
    final recSalt = _random(_saltLen, rng);
    final recBox = await _aes.encrypt(
      dek,
      secretKey: await _deriveKey(_normalizeRecovery(recoveryCode), recSalt),
      nonce: _aes.newNonce(),
    );
    // البيانات — بمفتاح الملف العشوائي لا بأي مفتاح مشتق من أسرار.
    final dataBox = await _aes.encrypt(
      plain,
      secretKey: SecretKeyData(Uint8List.fromList(dek)),
      nonce: _aes.newNonce(),
    );
    final out = BytesBuilder();
    out.add(magic);
    final withLog = logRootKey != null && logRootKey.isNotEmpty;
    out.addByte(
        withLog ? lockedLogFormatVersion : lockedFormatVersion);
    out.addByte(2); // سجلا التغليف حصراً: الكلمة والرمز.
    out.addByte(_recPassword);
    out.add(pwSalt);
    out.add(pwBox.nonce);
    out.add(pwBox.mac.bytes);
    out.add(pwBox.cipherText);
    out.addByte(_recRecovery);
    out.add(recSalt);
    out.add(recBox.nonce);
    out.add(recBox.mac.bytes);
    out.add(recBox.cipherText);
    if (withLog) {
      out.add(await _packLogRecord(logRootKey, dek));
    }
    out.add(dataBox.nonce);
    out.add(dataBox.cipherText);
    out.add(dataBox.mac.bytes);
    return out.toBytes();
  }

  /// بايتات سجل مفتاح السجلات (س230): النوع 4 + نونس + وسم + الجذر
  /// مشفراً بDEK الملف — البطاقة الموحدة لكاتبين v5/v6 وقارئ الأجيال.
  Future<List<int>> _packLogRecord(
      List<int> logRootKey, List<int> dek) async {
    final box = await _aes.encrypt(
      logRootKey,
      secretKey: SecretKeyData(Uint8List.fromList(dek)),
      nonce: _aes.newNonce(),
    );
    final out = BytesBuilder();
    out.addByte(_recLogKey);
    out.add(box.nonce);
    out.add(box.mac.bytes);
    out.add(box.cipherText);
    return out.toBytes();
  }

  /// يفك نسخة مقفلة (v3 — أو v6 بسجل السجلات س230) — بالمواد المتاحة:
  /// كلمة المرور و/أو رمز الاسترداد. كل سجل يُجرّب بمادته المطابقة ووسم
  /// GCM حاكم؛ أول فك ناجح لـDEK يفتح البيانات وسجل السجلات تحته.
  /// لا مواد = رسالة الطلب، وكل المواد خاطئة = رفض واحد صريح قبل أي
  /// لمس للقاعدة (روح F-013). يعاد (النص الصريح، جذر سجلات النسخة —
  /// null بجيل v3 الذي لا يحمله).
  Future<(List<int>, List<int>?)> decryptLockedWithLogRoot(
    List<int> blob, {
    String? password,
    String? recoveryCode,
  }) async {
    if (identify(blob) != BackupKind.encrypted) {
      throw const BackupCipherException('الملف ليس نسخة مشفرة أصلاً');
    }
    final version = encryptedVersion(blob);
    if (version != lockedFormatVersion && version != lockedLogFormatVersion) {
      throw BackupCipherException(version == formatVersion
          ? 'هذه نسخة بمفتاح البرنامج — تُفتح مباشرة بلا كلمة مرور'
          : version == vaultFormatVersion || version == vaultLogFormatVersion
              ? 'هذه نسخة من جيل الخزنة (v4/v5) — تُفك بمفتاح هذا الجهاز '
                  'أو برمز الاسترداد'
              : 'إصدار تنسيق غير معروف: $version');
    }
    final (dataOffset, records, logRecord) = _readWrapRecords(
      blob,
      allowedKinds: const {_recPassword, _recRecovery},
      expectLogRecord: version == lockedLogFormatVersion,
      structureError: 'بنية النسخة المقفلة تالفة — الملف غير سليم',
      kindError: 'نوع سجل غير معروف بالنسخة المقفلة — الملف غير سليم',
    );
    final dek = await _unwrapDek(records,
        password: password, recoveryCode: recoveryCode);
    if (dek == null) {
      throw BackupCipherException(
          (password == null || password.isEmpty) &&
                  (recoveryCode == null || recoveryCode.isEmpty)
              ? 'النسخة مقفلة بكلمة مرور — أدخل كلمة المرور أو رمز '
                  'الاسترداد ثم أعد المحاولة'
              : 'كلمة المرور أو رمز الاسترداد خاطئ — تحقق ثم أعد المحاولة');
    }
    final logRoot = logRecord == null
        ? null
        : await _unpackLogRecord(logRecord, dek);
    // قسم البيانات بعد السجلات (وسجل السجلات إن حضر): نونس (12) ← نص
    // مشفر ← وسم (16).
    return (
      await _decryptTail(
          blob, dataOffset, dek, 'فك التشفير فشل — الملف تالف'),
      logRoot,
    );
  }

  /// يفك نسخة مقفلة إلى نصها الصريح حصراً — المفوّض بالقديم (س149)
  /// حرفاً، والجذر المحمول يُطلب من [decryptLockedWithLogRoot] (س230).
  Future<List<int>> decryptLocked(
    List<int> blob, {
    String? password,
    String? recoveryCode,
  }) async {
    final (plain, _) = await decryptLockedWithLogRoot(blob,
        password: password, recoveryCode: recoveryCode);
    return plain;
  }

  /// فك سجل مفتاح السجلات (س230) من أجزائه بDEK الملف — الجذر
  /// 32 بايتة حصراً (بنية الشاذة رفض كامل لا تخمين صامت).
  Future<List<int>> _unpackLogRecord(
      ({List<int> nonce, List<int> mac, List<int> cipherText}) rec,
      SecretKey dek) async {
    final List<int> root;
    try {
      root = await _aes.decrypt(
        SecretBox(rec.cipherText, nonce: rec.nonce, mac: Mac(rec.mac)),
        secretKey: dek,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupCipherException(
          'بنية سجل السجلات تالفة — الملف غير سليم');
    }
    if (root.length != _dekLen) {
      throw const BackupCipherException(
          'بنية سجل السجلات تالفة — الملف غير سليم');
    }
    return root;
  }

  /// تجربة سجلات التغليف بالمواد المتاحة — أول DEK يفك بوسم GCM سليم
  /// يعاد. فشل سجل لا يمنع تجربة التالي (كلمة خاطئة + رمز صحيح = نجاح).
  /// د11 (س229): مادة ثالثة — جذر الخزنة لسجل نوع 3 بجيل v4 (مفتاح
  /// بايتاتي مشتق HKDF لا نص PBKDF2 — فصل المادة عن النص حصراً).
  Future<SecretKey?> _unwrapDek(
    List<(int, List<int>, List<int>, List<int>, List<int>)> records, {
    String? password,
    String? recoveryCode,
    List<int>? vaultRootKey,
  }) async {
    for (final (kind, salt, nonce, mac, wrapped) in records) {
      try {
        final SecretKey key;
        if (kind == _recVaultKey) {
          if (vaultRootKey == null || vaultRootKey.isEmpty) continue;
          key = await _deriveVaultKey(vaultRootKey, salt);
        } else {
          final material = kind == _recPassword ? password : recoveryCode;
          if (material == null || material.isEmpty) continue;
          final keyText = kind == _recRecovery
              ? _normalizeRecovery(material)
              : material;
          key = await _deriveKey(keyText, salt);
        }
        final dekBytes = await _aes.decrypt(
          SecretBox(wrapped, nonce: nonce, mac: Mac(mac)),
          secretKey: key,
        );
        return SecretKeyData(Uint8List.fromList(dekBytes));
      } on SecretBoxAuthenticationError {
        continue; // مادة خاطئة لهذا السجل — التالي.
      }
    }
    return null;
  }

  /// يكتب نسخة من جيل الخزنة v4 (د11 — س229/D-225 الجزء الأول):
  /// بنية v3 عينها بسجلين مختلفين — سجل مفتاح الخزنة (الجذر العشوائي
  /// لهذا الجهاز من خزنته — يفتح هنا صامتاً) وسجل رمز الاسترداد
  /// (المطبوع مرة واحدة — يفتح على أي جهاز آخر فسيناريو N-005 يلتئم
  /// بلا كسر). البيانات بمفتاح عشوائي لكل ملف لا بأي مفتاح مشتق
  /// من الأسرار — نمط DEK/KEK الموثق بجيل v3 حرفاً.
  Future<List<int>> encryptVaulted(
    List<int> plain, {
    required List<int> vaultRootKey,
    required String recoveryCode,
    List<int>? logRootKey,
    Random? rng,
  }) async {
    final dek = _random(_dekLen, rng);
    // سجل مفتاح الخزنة — ملح ونونس مستقلان (نمط سجلات v3).
    final vaultSalt = _random(_saltLen, rng);
    final vaultBox = await _aes.encrypt(
      dek,
      secretKey: await _deriveVaultKey(vaultRootKey, vaultSalt),
      nonce: _aes.newNonce(),
    );
    // سجل رمز الاسترداد — بالمطبّع فأي هيئة كتابة تعمل عند الفك.
    final recSalt = _random(_saltLen, rng);
    final recBox = await _aes.encrypt(
      dek,
      secretKey: await _deriveKey(_normalizeRecovery(recoveryCode), recSalt),
      nonce: _aes.newNonce(),
    );
    // البيانات — بمفتاح الملف العشوائي لا بأي مفتاح مشتق من أسرار.
    final dataBox = await _aes.encrypt(
      plain,
      secretKey: SecretKeyData(Uint8List.fromList(dek)),
      nonce: _aes.newNonce(),
    );
    final out = BytesBuilder();
    out.add(magic);
    // س230 (د11 الجزء الثاني): الجذر الحاضر يرفع الجيل إلى v5 بسجل
    // رابع نوع 4 يحمل جذر السجلات تحت DEK — والغائب يبقي v4 حرفاً
    // (انخفاض موثق: أحداث مختومة إرثياً فلا سجل لها بالملف).
    final withLog = logRootKey != null && logRootKey.isNotEmpty;
    out.addByte(withLog ? vaultLogFormatVersion : vaultFormatVersion);
    out.addByte(2); // سجلا التغليف حصراً: مفتاح الخزنة ورمز الاسترداد.
    out.addByte(_recVaultKey);
    out.add(vaultSalt);
    out.add(vaultBox.nonce);
    out.add(vaultBox.mac.bytes);
    out.add(vaultBox.cipherText);
    out.addByte(_recRecovery);
    out.add(recSalt);
    out.add(recBox.nonce);
    out.add(recBox.mac.bytes);
    out.add(recBox.cipherText);
    if (withLog) {
      out.add(await _packLogRecord(logRootKey, dek));
    }
    out.add(dataBox.nonce);
    out.add(dataBox.cipherText);
    out.add(dataBox.mac.bytes);
    return out.toBytes();
  }

  /// يفك نسخة جيل الخزنة (v4 — أو v5 بسجل السجلات س230) — بالمواد المتاحة: مفتاح خزنة هذا الجهاز
  /// (الجهاز ذاته يفتح صامتاً) و/أو رمز الاسترداد (جهاز آخر) — ويعاد مع
  /// النص جذر سجلات النسخة (null بجيل v4 الذي لا يحمله).
  /// يُجرَّب بمادته ووسم GCM حاكم؛ أول فك ناجح لـDEK يفتح البيانات —
  /// لا مواد = رسالة الطلب بلسان الجيل، وكل المواد خاطئة = رفض واحد
  /// صريح قبل أي لمس للقاعدة (روح F-013 عينها).
  Future<(List<int>, List<int>?)> decryptVaultedWithLogRoot(
    List<int> blob, {
    List<int>? vaultRootKey,
    String? recoveryCode,
  }) async {
    if (identify(blob) != BackupKind.encrypted) {
      throw const BackupCipherException('الملف ليس نسخة مشفرة أصلاً');
    }
    final version = encryptedVersion(blob);
    if (version != vaultFormatVersion && version != vaultLogFormatVersion) {
      throw BackupCipherException(
          version == lockedFormatVersion || version == lockedLogFormatVersion
              ? 'هذه نسخة مقفلة بكلمة مرور — تُفك بالكلمة أو رمز الاسترداد'
              : version == formatVersion
                  ? 'هذه نسخة بمفتاح البرنامج — تُفتح مباشرة بلا كلمة مرور'
                  : 'إصدار تنسيق غير معروف: $version');
    }
    final (dataOffset, records, logRecord) = _readWrapRecords(
      blob,
      allowedKinds: const {_recVaultKey, _recRecovery},
      expectLogRecord: version == vaultLogFormatVersion,
      structureError: 'بنية نسخة الخزنة تالفة — الملف غير سليم',
      kindError: 'نوع سجل غير معروف بنسخة الخزنة — الملف غير سليم',
    );
    final dek = await _unwrapDek(
      records,
      vaultRootKey: vaultRootKey,
      recoveryCode: recoveryCode,
    );
    if (dek == null) {
      final hasVault = vaultRootKey != null && vaultRootKey.isNotEmpty;
      final hasCode = recoveryCode != null && recoveryCode.isNotEmpty;
      throw BackupCipherException(!hasVault && !hasCode
          ? 'النسخة من جيل الخزنة (v4/v5) — تُفك هنا بمفتاح هذا الجهاز '
              'وبرمز الاسترداد على جهاز آخر — أدخل الرمز ثم أعد المحاولة'
          : 'مفتاح الخزنة لا يطابق والرمز المدخل خاطئ — تحقق ثم أعد المحاولة');
    }
    final logRoot = logRecord == null
        ? null
        : await _unpackLogRecord(logRecord, dek);
    return (
      await _decryptTail(
          blob, dataOffset, dek, 'فك التشفير فشل — الملف تالف'),
      logRoot,
    );
  }

  /// يفك نسخة جيل الخزنة إلى نصها الصريح حصراً — مفوّض س229 حرفاً،
  /// والجذر المحمول يُطلب من [decryptVaultedWithLogRoot] (س230).
  Future<List<int>> decryptVaulted(
    List<int> blob, {
    List<int>? vaultRootKey,
    String? recoveryCode,
  }) async {
    final (plain, _) = await decryptVaultedWithLogRoot(blob,
        vaultRootKey: vaultRootKey, recoveryCode: recoveryCode);
    return plain;
  }

  /// فك موحد بكل الأجيال بالمواد المتاحة (س230 — منبع واحد للمستدعين
  /// الأربعة: الاستعادة وملف الصور وتحقيقَي المستودع): v1 بكلمة
  /// المرور حصراً، v2 بمفتاح البرنامج، المقفلة v3/v6 بالكلمة أو
  /// الرمز، وخزنة v4/v5 بمفتاح هذا الجهاز أو الرمز — ويعاد مع النص
  /// جذر سجلات النسخة إن حمله الملف (v5/v6) وإلا null. لا مواد
  /// للجيل الطالب = رسالة طلبه بلسانه، والمواد الخاطئة = رفض واحد
  /// صريح (وسم GCM حاكم) لا صمت ولا تخمين جيل.
  Future<(List<int>, List<int>?)> decryptAny(
    List<int> blob, {
    String? password,
    String? recoveryCode,
    List<int>? vaultRootKey,
  }) async {
    if (identify(blob) != BackupKind.encrypted) {
      throw const BackupCipherException('الملف ليس نسخة مشفرة أصلاً');
    }
    switch (encryptedVersion(blob)) {
      case legacyFormatVersion:
        if (password == null || password.isEmpty) {
          throw const BackupCipherException(
              'النسخة من الجيل القديم المحمي بكلمة مرور — '
              'أدخلها في حقل كلمة المرور ثم أعد المحاولة');
        }
        return (await decryptWithPassword(blob, password), null);
      case formatVersion:
        return (await decrypt(blob), null);
      case lockedFormatVersion:
      case lockedLogFormatVersion:
        return await decryptLockedWithLogRoot(blob,
            password: password, recoveryCode: recoveryCode);
      case vaultFormatVersion:
      case vaultLogFormatVersion:
        return await decryptVaultedWithLogRoot(blob,
            vaultRootKey: vaultRootKey, recoveryCode: recoveryCode);
      default:
        throw BackupCipherException(
            'إصدار تنسيق غير معروف: ${encryptedVersion(blob)}');
    }
  }

  /// قراءة سجلات التغليف المشتركة بين الجيلين المقفل (v3/v6) والخزنة
  /// (v4/v5 — د11 وس230) — منبع واحد لا تكرار: كل سجل 77 بايتة
  /// (النوع 1 + الملح 16 + النونس 12 + وسم GCM 16 + DEK مغلَّفاً 32)،
  /// والعدّاد بعد بايتة الإصدار، والأنواع المقبولة بمعرفة الجيل
  /// المستدعي. [expectLogRecord] (س230) يجعل سجل مفتاح السجلات
  /// (نوع 4، 61 بايتة) واجباً بعد سجلات التغليف قبل قسم البيانات.
  /// يعاد (إزاحة قسم البيانات، السجلات، أجزاء سجل السجلات إن حضر)
  /// — وأي بنية ناقصة أو نوع شاذ رفض كامل (لا تخمين صامت) برسالة
  /// الجيل المستدعي.
  (int, List<(int, List<int>, List<int>, List<int>, List<int>)>,
          ({List<int> nonce, List<int> mac, List<int> cipherText})?)
      _readWrapRecords(
    List<int> blob, {
    required Set<int> allowedKinds,
    required bool expectLogRecord,
    required String structureError,
    required String kindError,
  }) {
    final headerLen = magic.length;
    var i = headerLen + 1;
    final count = blob[i];
    i += 1;
    if (i + count * _recordLen > blob.length - _nonceLen - _macLen) {
      throw BackupCipherException(structureError);
    }
    final records = <(int, List<int>, List<int>, List<int>, List<int>)>[];
    for (var r = 0; r < count; r++) {
      final kind = blob[i];
      final salt = blob.sublist(i + 1, i + 1 + _saltLen);
      final nonce =
          blob.sublist(i + 1 + _saltLen, i + 1 + _saltLen + _nonceLen);
      final macStart = i + 1 + _saltLen + _nonceLen;
      final mac = blob.sublist(macStart, macStart + _macLen);
      final wrapped = blob.sublist(macStart + _macLen, i + _recordLen);
      if (!allowedKinds.contains(kind)) {
        throw BackupCipherException(kindError);
      }
      records.add((kind, salt, nonce, mac, wrapped));
      i += _recordLen;
    }
    // سجل مفتاح السجلات (س230 — د11 الجزء الثاني) بأجيال v5/v6 بعد
    // سجلات التغليف حصراً: النوع (1) + نونس (12) + وسم (16) + جذر
    // مشفر (32) = 61 بايتة، قبل قسم البيانات مباشرة.
    ({List<int> nonce, List<int> mac, List<int> cipherText})? logRecord;
    if (expectLogRecord) {
      if (i + _logRecordLen > blob.length - _nonceLen - _macLen) {
        throw BackupCipherException(structureError);
      }
      if (blob[i] != _recLogKey) {
        throw BackupCipherException(kindError);
      }
      logRecord = (
        nonce: blob.sublist(i + 1, i + 1 + _nonceLen),
        mac: blob.sublist(
            i + 1 + _nonceLen, i + 1 + _nonceLen + _macLen),
        cipherText: blob.sublist(
            i + 1 + _nonceLen + _macLen, i + _logRecordLen),
      );
      i += _logRecordLen;
    }
    return (i, records, logRecord);
  }

  /// قسم البيانات بعد سجلات التغليف مباشرة: نونس (12) ← نص مشفر ←
  /// وسم GCM (16) — فك واحد بوسم حاكم برسالة الجيل المستدعي.
  Future<List<int>> _decryptTail(
    List<int> blob,
    int offset,
    SecretKey dek,
    String failureMessage,
  ) async {
    final nonce = blob.sublist(offset, offset + _nonceLen);
    final cipherText = blob.sublist(offset + _nonceLen, blob.length - _macLen);
    final mac = Mac(blob.sublist(blob.length - _macLen));
    try {
      return await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: dek,
      );
    } on SecretBoxAuthenticationError {
      throw BackupCipherException(failureMessage);
    }
  }

  /// مفتاح سجل الخزنة من جذر الجهاز — HKDF-SHA256 بملح السجل الخاص
  /// وسياق معزول عن مفتاح البرنامج (v2) وعن كل مسار آخر (فصل
  /// النطاقات من الاشتقاق — نمط p3 الموثق).
  Future<SecretKey> _deriveVaultKey(List<int> rootKey, List<int> salt) {
    return _hkdf.deriveKey(
      secretKey: SecretKeyData(Uint8List.fromList(rootKey)),
      nonce: salt,
      info: _vaultHkdfInfo,
    );
  }

  /// توليد رمز استرداد قابل للكتابة اليدوية — 4 مجموعات × 4 محارف من
  /// ألفباء بلا متشابهات (لا 0/O ولا 1/I/L) مفصولة بشرطات، ونحو 78
  /// بتّاً عشوائياً من Random.secure().
  static String generateRecoveryCode([Random? rng]) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = rng ?? Random.secure();
    String group() =>
        List.generate(4, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    return [group(), group(), group(), group()].join('-');
  }

  /// تطبيع رمز الاسترداد قبل الاشتقاق وفحصه: أحرف كبيرة وبلا شرطات
  /// ولا فراغات — فالكتابة اليدوية بأي هيئة تصل للمفتاح ذاته.
  static String _normalizeRecovery(String code) => code
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-]'), '');

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

  static List<int> _random(int length, [Random? rng]) {
    final random = rng ?? Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

/// نوع ملف النسخة الاحتياطية — يُحدد مسار التحقق في الاستعادة.
enum BackupKind { encrypted, plainSqlite, unknown }

/// أسرار قفل النسخة الاحتياطية — P1-أ (س149/D-210): كلمة المستخدم
/// الاختيارية ورمز الاسترداد المولّد معها، يُحفظان بخزنة الجهاز
/// (BackupSecretsStore بالواجهة) ويُمرّران للنسخ الجديدة فتُكتب
/// بجيل v3 المقفل. خزنة بلا سرّين معاً = بلا قفل (نسخ v2 كما كانت).
class BackupLock {
  final String password;
  final String recoveryCode;

  const BackupLock({required this.password, required this.recoveryCode});
}

/// مواد مفاتيح النسخ من خزنة الجهاز — د11 (س229/D-225 الجزء الأول):
/// جذر عشوائي 32 بايتة لكل جهاز يولَّد عند أول تشغيل ويُحفظ بخزنة
/// الجهاز (VaultBackupKeys بالواجهة بنمط SecureStorageKeyVault)، ومعه
/// رمز استرداد بنمط v3 القائم يُطبع مرة واحدة — فالنسخ غير المقفلة
/// تُكتب بجيل v4: DEK لكل ملف مغلَّف بسجلين (مفتاح الخزنة هنا صامتاً،
/// ورمز الاسترداد على أي جهاز آخر) — وسيناريو «فتح النسخة على أي
/// جهاز» يلتئم بالرمز بلا كسر (خلاف المحضر الاستشاري المحسوم بد11).
class BackupVaultKeys {
  /// جذر الخزنة — 32 بايتة عشوائية لكل جهاز (لا مفتاح مشترك عاماً
  /// بعد اليوم: G-02 الأول).
  final List<int> rootKey;

  /// رمز الاسترداد المطبوع مرة واحدة عند أول تشغيل — نمط v3 حرفاً
  /// (يبقى قابلاً للعرض من الخزنة بعرف الصدق الموثق ذاته).
  final String recoveryCode;

  const BackupVaultKeys({required this.rootKey, required this.recoveryCode});
}

/// يُرمى عند فشل فك التشفير أو تلف الغلاف (F-013: تحقق قبل أي لمس).
class BackupCipherException implements Exception {
  final String message;
  const BackupCipherException(this.message);

  @override
  String toString() => message;
}
