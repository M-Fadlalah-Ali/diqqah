/// د1 (س169 — عقد المزامنة النقي وحزمة الخروج الموقعة): صيغة حزمة
/// الأحداث `.dsync` نص 08 §10 حرفاً + توقيع السجل الحدثي عند الخروج
/// (بند §37 الأول — سياق معزول `diqqah-sync-v1` امتداد عرف log_cipher
/// p3/F-010: مفتاح جذر مستقل عن النسخ والأحداث المحلية والصور،
/// والعزل بايتاتياً بالسياقين).
///
/// **نقية حصراً** (F-010): لا Flutter ولا Drift ولا شبكة — البناء والفك
/// والتحقق كلها دوال نقية تأخذ بايتات وترد بايتات، والمستهلك (الجسر
/// اليدوي س-23 ثم المهايئات) يوصلها بملفات الجهاز على مساره.
///
/// بنية الحزمة النصية (قبل التغليف) نص §10 حرفاً:
/// - سطر الترويسة JSON بترتيب مفاتيح ثابت: `format` و`formatVersion`
///   و`companyId` و`deviceId` و`lastSeq` و`eventCount` و`eventsSha256`
///   و`sigAlgo` و`sigSalt` و`signature` (خاتماً).
/// - ثم سلسلة الأحداث JSONL بترتيب `seq` التصاعدي، كل سطر حدثاً كاملاً
///   بلقطته (07 §2.3) وحمولته نصية واضحة — فشفافية الحزمة تحت الغلاف
///   هي أصل الفحص، والتشفير على مستوى الملف كله لا على مستوى السطر.
/// - بصمة الأحداث SHA-256 على بايتات كتلة الأحداث حصراً (سطورها مع
///   فواصلها)، والتوقيع HMAC-SHA256 على الترويسة قبل التوقيع + سطر
///   فارغ + كتلة الأحداث — فأي عبث بأي بايت من الاثنين يُكشف مفهرساً.
///
/// الغلاف الافتراضي: مفتاح البرنامج حصراً بلا كلمة مرور — مطابق لآلية
/// النسخ الاحتياطية النافذة (F-012/D-060، حسم س12): ترويسة `DIQQSYNC`
/// + بايتة إصدار 1 + ملح اشتقاق 16 + نونس 12 + نص مشفر + وسم GCM 16،
/// ومفتاحه من جذر المزامنة بسياق `diqqah-sync-enc-v1` المعزل. ولا
/// تُقبل حزمة غير مشفرة إلا بإلغاء واعٍ موثق — فلا مسار نصي خام هنا
/// أصلاً (المنتج لا يكتبه ولا يقرؤه).
///
/// التحقق عند الفك نص §10 حرفاً — الرفض برموز مفهرسة من السجل:
/// - الغلاف تالف أو ليس حزمة → DQ-1109 (envelope).
/// - التوقيع أو البصمة لا تجتزان → DQ-1110 (عبث أو تلف).
/// - البنية: إصدار/معرف صيغة أو حقل ناقص أو انكسار `seq` أو تكرار
///   `uuid` **داخل الحزمة** أو عدّاد لا يطابق → DQ-1111.
/// - حزمة من شركة أخرى → DQ-1112 (فحص المتلقي بحموله).
/// أما `uuid` المكرر **على ما عُرف لدى المتلقي** فلا رفض عليه: يُتجاهل
/// بهدوء عرف §10/§3 («إعادة دفع أو استيراد مزدوج يُتجاهل بأمان») —
/// والعقد النقي لذلك [filterKnownSyncEvents] المجرَّبة بس-23.
///
/// الصدق الموثق (روح D-060): مفتاح البرنامج داخل تطبيق موزع قابل
/// للاستخراج التقني — فالتوقيع HMAC شاهدُ عبثٍ وتلفٍ داخل منظومة
/// دِقَّة لا إنكار إسناد بمفتاح عام، والغلاف ستارة خصوصية لا صندوق
/// أمان. قرار المالك بنفس الوصف للنسخ الاحتياطية يمتد بطبيعة المفتاح
/// ذاته ولا يُدّعى عنه أكثر.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart' as cg;

/// ترويسة الغلاف — «DIQQSYNC» (بديل ترويسة النسخ DIQQENC فلا يلتبس
/// ملف مزامنة بنسخة احتياطية عند تمييز البايتات الأولى أبداً).
final List<int> syncEnvelopeMagic = utf8.encode('DIQQSYNC');

/// إصدار الغلاف الجاري كتابته.
const int syncEnvelopeVersion = 1;

/// سياق اشتقاق مفتاح التغليف — معزل عن سياق التوقيع وعن النسخ
/// (`diqqah-backup-v2`) وعن سجلات القاعدة (`diqqah-event-log-v1`).
final List<int> syncEncInfo = utf8.encode('diqqah-sync-enc-v1');

/// سياق توقيع الخروج — بند §37 الأول بالسياق المقترح الموثق حرفاً.
final List<int> syncSigInfo = utf8.encode('diqqah-sync-v1');

/// معرف الصيغة وإصدارها داخل الترويسة — لا حزمة بغيرهما تفتح.
const String syncFormatId = 'diqqah-dsync';
const int syncFormatVersion = 1;

/// خوارزمية التوقيع المعلنة في الترويسة — لا تخمين ولا بديل اليوم.
const String syncSigAlgo = 'hmac-sha256';

const int _saltLen = 16;
const int _nonceLen = 12;
const int _macLen = 16;

/// جذر المزامنة — 32 بايتة مستقلة عن جذر النسخ الاحتياطية وعن جذر
/// سجلات القاعدة (فصل النطاقات من الجذر لا من الاشتقاق حصراً — نمط
/// p3 الموثق). واحد على كل الأجهزة فالجسر يفتح ما بُني على أي جهاز.
const List<int> _syncRootKey = [
  88, 31, 202, 146, 5, 233, 71, 18, //
  240, 99, 154, 27, 130, 64, 8, 199, //
  45, 172, 96, 233, 14, 187, 52, 121, //
  167, 30, 205, 98, 63, 176, 141, 220, //
];

final cg.Hkdf _hkdf = cg.Hkdf(hmac: cg.Hmac.sha256(), outputLength: 32);
final cg.AesGcm _aes = cg.AesGcm.with256bits();

/// حدث مزامنة واحد — صورة صافِ لصف `events` (07 §2.3): التسلسل
/// المحلي الصاعد هو `seq` (آخر تسلسل بالحزمة هو `lastSeq`)، والحمولة
/// لقطة الكيان الكاملة نصاً واضحاً (فالتغليف على الحزمة كله، وإعادة
/// الختم بمفتاح المستقبل على مساره بعرف سجلات القاعدة p3)، والشركة
/// تحملها كل صف حداً بحد عرف د3/D-188 («كل حدث يحمل company_id») —
/// فحزمة الشركة الواحدة لا تحمل غيرها، وأي خلاف بين الصف والترويسة
/// رفضٌ بنيوي مفهرس (DQ-1111) لا قبول صامت.
class SyncEvent {
  final int seq;
  final String uuid;
  final int eventAt;

  /// صاحب العملية — يمر كما وقع (الخلفية البحتة بلا مستخدم).
  final int? userId;
  final String deviceId;
  final String entityType;
  final int? entityId;
  final String action;

  /// الشركة الحاملة للحدث — د3 (س170/D-188/م-٥): من البنية الموحدة
  /// [kDefaultCompanyId] للمتردّد الواحد، وإدارة التعدد النشطة
  /// بموضعها (F-112) والعزل يمتد للخادم عرف 08 §7.
  final String companyId;

  /// لقطة الكيان JSON نصاً — تُحمل كما هي ولا تُفحص هنا (المستند
  /// فاحصه المستقبل عند التطبيق، والحزمة ناقل مرتب موقّع حصراً).
  final String payloadJson;

  const SyncEvent({
    required this.seq,
    required this.uuid,
    required this.eventAt,
    required this.userId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.companyId,
    required this.payloadJson,
  });

  /// الترميز القياسي — ترتيب المفاتيح ثابت فهو جزء من العقد البايتي:
  /// البصمة والتوقيع فوق هذا الترتيب لا غيره.
  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'uuid': uuid,
        'event_at': eventAt,
        'user_id': userId,
        'device_id': deviceId,
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'company_id': companyId,
        'payload': payloadJson,
      };

  String toLine() => jsonEncode(toJson());

  static SyncEvent fromJson(Map<String, Object?> json) {
    return SyncEvent(
      seq: _requireInt(json, 'seq'),
      uuid: _requireText(json, 'uuid'),
      eventAt: _requireInt(json, 'event_at'),
      userId: _optionalInt(json, 'user_id'),
      deviceId: _requireText(json, 'device_id'),
      entityType: _requireText(json, 'entity_type'),
      entityId: _optionalInt(json, 'entity_id'),
      action: _requireText(json, 'action'),
      companyId: _requireText(json, 'company_id'),
      payloadJson: _requireText(json, 'payload'),
    );
  }
}

/// ترويسة الحزمة كما فُتحت — بقيمها المصرَّح بها لا المحسوبة.
class SyncBundleHeader {
  final String companyId;
  final String deviceId;
  final int lastSeq;
  final int eventCount;
  final String eventsSha256;
  final String sigAlgo;
  final String sigSaltHex;
  final String signatureHex;

  const SyncBundleHeader({
    required this.companyId,
    required this.deviceId,
    required this.lastSeq,
    required this.eventCount,
    required this.eventsSha256,
    required this.sigAlgo,
    required this.sigSaltHex,
    required this.signatureHex,
  });
}

/// حزمة مبنية — بايتاتها مغلفة جاهزة للنقل واسمها القياسي نص §10.
class SyncBundleFile {
  final String filename;
  final List<int> bytes;
  final SyncBundleHeader header;

  const SyncBundleFile({
    required this.filename,
    required this.bytes,
    required this.header,
  });
}

/// حزمة مفتوحة ومحكومة — الترويسة والأحداث بصافيها بعد كل الفحوص.
class SyncBundleContents {
  final SyncBundleHeader header;
  final List<SyncEvent> events;

  const SyncBundleContents({required this.header, required this.events});
}

/// اسم الملف القياسي نص §10 حرفاً:
/// `diqqah-sync-YYYYMMDD-HHMM-<device>-<lastseq>.dsync` — ومعرف
/// الجهاز يُطهَّر لمحارف أسماء الملفات الآمنة فلا نظام يرفض النقل.
String syncBundleFilename({
  required DateTime at,
  required String deviceId,
  required int lastSeq,
}) {
  String p2(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${at.year.toString().padLeft(4, '0')}${p2(at.month)}${p2(at.day)}'
      '-${p2(at.hour)}${p2(at.minute)}';
  final safeDevice =
      deviceId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'diqqah-sync-$stamp-$safeDevice-$lastSeq.dsync';
}

/// يبني الحزمة ويوقّعها ويغلّفها — «توقيع السجل الحدثي عند الخروج»
/// بند §37 الأول في موقعه: الخروج هو البناء، والتوقيع قبل التغليف.
///
/// الأحداث تُرتَّب صاعدةً بـseq داخل الحزمة مهما جاءت، وأي خلل بنيوي
/// بالمدخلات (تكرار seq أو uuid أو حقل فارغ) رفضٌ صوتي قبل كتابة
/// بايت — فلا حزمة معيبة تخرج من البناء أصلاً.
Future<SyncBundleFile> buildSyncBundle({
  required String companyId,
  required String deviceId,
  required List<SyncEvent> events,
  DateTime? exportedAt,
  Random? rng,
}) async {
  if (companyId.trim().isEmpty) {
    throw const SyncBundleStructureException('البناء: الشركة فارغة — لا حزمة بلا شركة');
  }
  if (deviceId.trim().isEmpty) {
    throw const SyncBundleStructureException('البناء: معرف الجهاز فارغ');
  }
  if (events.isEmpty) {
    throw const SyncBundleStructureException('البناء: لا أحداث في الحزمة — لا معنى لنقل فراغ');
  }
  final sorted = List<SyncEvent>.from(events)
    ..sort((a, b) => a.seq.compareTo(b.seq));
  final seenUuid = <String>{};
  for (var i = 0; i < sorted.length; i++) {
    final e = sorted[i];
    if (e.seq <= 0) {
      throw SyncBundleStructureException(
          'البناء: تسلسل غير موجب (${e.seq}) — seq يبدأ من 1');
    }
    if (i > 0 && e.seq != sorted[i - 1].seq + 1) {
      throw SyncBundleStructureException(
          'البناء: انكسار تسلسل seq (${sorted[i - 1].seq} ثم ${e.seq}) '
          '— التسلسل متصل بلا فجوة ولا تكرار');
    }
    if (e.uuid.trim().isEmpty || !seenUuid.add(e.uuid)) {
      throw SyncBundleStructureException(
          'البناء: uuid فارغ أو مكرر داخل الحزمة (${e.uuid})');
    }
    if (e.deviceId.trim().isEmpty ||
        e.entityType.trim().isEmpty ||
        e.action.trim().isEmpty) {
      throw const SyncBundleStructureException(
          'البناء: حقل حدث فارغ (device_id/entity_type/action)');
    }
    if (e.companyId.trim().isEmpty) {
      throw const SyncBundleStructureException(
          'البناء: حقل حدث فارغ (company_id)');
    }
    if (e.companyId != companyId) {
      throw SyncBundleStructureException(
          'البناء: حدث بشركة أخرى (${e.companyId}) لا تطابق ترويسة '
          'الحزمة ($companyId) — حزمة الشركة الواحدة لا تحمل غيرها');
    }
    if (e.eventAt < 0) {
      throw SyncBundleStructureException(
          'البناء: طابع زمني سالب (${e.eventAt})');
    }
  }

  final lines = sorted.map((e) => e.toLine()).toList();
  final eventsBlock = lines.isEmpty ? '' : '${lines.join('\n')}\n';
  final eventsBytes = utf8.encode(eventsBlock);
  final eventsSha = c.sha256.convert(eventsBytes).toString();

  final sigSalt = _random(_saltLen, rng);
  final headerPrefixJson = jsonEncode(<String, Object?>{
    'format': syncFormatId,
    'formatVersion': syncFormatVersion,
    'companyId': companyId,
    'deviceId': deviceId,
    'lastSeq': sorted.last.seq,
    'eventCount': sorted.length,
    'eventsSha256': eventsSha,
    'sigAlgo': syncSigAlgo,
    'sigSalt': _hex(sigSalt),
  });
  final sigBytes = await signSyncBundleText(
    headerPrefixJson: headerPrefixJson,
    eventsBlock: eventsBlock,
    sigSalt: sigSalt,
  );

  final headerLine = jsonEncode(<String, Object?>{
    'format': syncFormatId,
    'formatVersion': syncFormatVersion,
    'companyId': companyId,
    'deviceId': deviceId,
    'lastSeq': sorted.last.seq,
    'eventCount': sorted.length,
    'eventsSha256': eventsSha,
    'sigAlgo': syncSigAlgo,
    'sigSalt': _hex(sigSalt),
    'signature': _hex(sigBytes),
  });
  final plain = utf8.encode('$headerLine\n$eventsBlock');
  final blob = await sealSyncEnvelope(plain, rng: rng);

  final header = SyncBundleHeader(
    companyId: companyId,
    deviceId: deviceId,
    lastSeq: sorted.last.seq,
    eventCount: sorted.length,
    eventsSha256: eventsSha,
    sigAlgo: syncSigAlgo,
    sigSaltHex: _hex(sigSalt),
    signatureHex: _hex(sigBytes),
  );
  return SyncBundleFile(
    filename: syncBundleFilename(
      at: exportedAt ?? DateTime.now(),
      deviceId: deviceId,
      lastSeq: sorted.last.seq,
    ),
    bytes: blob,
    header: header,
  );
}

/// يوقّع نص حزمة (ترويسة بلا توقيع + كتلة أحداث) بملح معلوم — واجهة
/// الكاتب المجرّبة: البناء المعتمد [buildSyncBundle] يتحقق بنيوياً
/// قبل الاستدعاء، والمستقبل فاحصُ البنية أولاً فلا ثقة بماوقّع إلا
/// بعد اجتياز §10 كاملاً — فالموقّع المعيب يُرفض برمزه لا يمرّ.
Future<List<int>> signSyncBundleText({
  required String headerPrefixJson,
  required String eventsBlock,
  required List<int> sigSalt,
}) async {
  final key = await _deriveSyncKey(sigSalt, syncSigInfo);
  return c.Hmac(c.sha256, key)
      .convert(utf8.encode('$headerPrefixJson\n$eventsBlock'))
      .bytes;
}

/// يغلّف بايتات حزمة نصية بغلاف مفتاح البرنامج (F-012/D-060 بنمطه):
/// `DIQQSYNC` + إصدار 1 + ملح 16 + نونس 12 + نص مشفر + وسم GCM 16.
/// ظاهر للعام لأن ملف الحزمة يُكتب ويُقرأ على مسار الملفات، ولِـ
/// اختبارات العبث الدقيقة فوق المضمون لا الغلاف.
Future<List<int>> sealSyncEnvelope(List<int> plain, {Random? rng}) async {
  final salt = _random(_saltLen, rng);
  final key = await _deriveSyncKey(salt, syncEncInfo);
  final nonce = _random(_nonceLen, rng);
  final box = await _aes.encrypt(
    plain,
    secretKey: cg.SecretKeyData(Uint8List.fromList(key)),
    nonce: nonce,
  );
  final out = BytesBuilder()
    ..add(syncEnvelopeMagic)
    ..addByte(syncEnvelopeVersion)
    ..add(salt)
    ..add(box.nonce)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return out.toBytes();
}

/// يفك غلاف الحزمة إلى بايتاتها النصية — بلا أي فحص مضمون (المضمون
/// فحصه [openSyncBundle] ترتيباً حرفاً). أي عبث بالغلاف يكسر وسم GCM.
Future<List<int>> openSyncEnvelope(List<int> blob) async {
  if (!_startsWith(blob, syncEnvelopeMagic)) {
    throw const SyncBundleEnvelopeException(
        'الملف ليس حزمة مزامنة دِقَّة أصلاً (لا ترويسة DIQQSYNC)');
  }
  final version = blob[syncEnvelopeMagic.length];
  if (version != syncEnvelopeVersion) {
    throw SyncBundleEnvelopeException('إصدار غلاف حزمة غير معروف: $version');
  }
  final saltStart = syncEnvelopeMagic.length + 1;
  final salt = blob.sublist(saltStart, saltStart + _saltLen);
  final nonceStart = saltStart + _saltLen;
  final nonce = blob.sublist(nonceStart, nonceStart + _nonceLen);
  final ctStart = nonceStart + _nonceLen;
  final cipherText = blob.sublist(ctStart, blob.length - _macLen);
  final mac = cg.Mac(blob.sublist(blob.length - _macLen));
  try {
    final key = await _deriveSyncKey(salt, syncEncInfo);
    final clear = await _aes.decrypt(
      cg.SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: cg.SecretKeyData(Uint8List.fromList(key)),
    );
    return clear;
  } on cg.SecretBoxAuthenticationError {
    throw const SyncBundleEnvelopeException(
        'غلاف الحزمة تالف أو مُعبث به — وسم السلامة لم يجتز');
  } on RangeError {
    throw const SyncBundleEnvelopeException(
        'بنية الغلاف غير مكتملة — الملف غير سليم');
  }
}

/// يفتح الحزمة ويحكمها بالترتيب الحرفي: الغلاف ← الترويسة ← التوقيع
/// ← البصمة ← البنية ← الشركة. كل رفض برمزه المفهرس من السجل.
Future<SyncBundleContents> openSyncBundle(
  List<int> blob, {
  String? expectedCompanyId,
}) async {
  final plain = await openSyncEnvelope(blob);
  late final String text;
  try {
    text = utf8.decode(plain);
  } on FormatException {
    throw const SyncBundleStructureException(
        'مضمون الحزمة ليس UTF-8 سليماً — الملف غير سليم');
  }
  final nl = text.indexOf('\n');
  if (nl <= 0) {
    throw const SyncBundleStructureException(
        'بنية الحزمة: لا سطر ترويسة JSON أول الملف');
  }
  final headerLine = text.substring(0, nl);
  final eventsBlock = text.substring(nl + 1);

  late final Map<String, Object?> headerJson;
  try {
    final decoded = jsonDecode(headerLine);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException();
    }
    headerJson = decoded;
  } on FormatException {
    throw const SyncBundleStructureException(
        'ترويسة الحزمة ليست JSON سليماً');
  }
  if (headerJson['format'] != syncFormatId) {
    throw SyncBundleStructureException(
        'معرف الصيغة غير معروف: ${headerJson['format']}');
  }
  if (headerJson['formatVersion'] != syncFormatVersion) {
    throw SyncBundleStructureException(
        'إصدار صيغة الحزمة غير معروف: ${headerJson['formatVersion']}');
  }
  final sigHex = headerJson.remove('signature');
  if (sigHex is! String || sigHex.isEmpty) {
    throw const SyncBundleStructureException(
        'ترويسة بلا توقيع — الحزمة غير مكتملة');
  }
  for (final field in [
    'companyId',
    'deviceId',
    'lastSeq',
    'eventCount',
    'eventsSha256',
    'sigAlgo',
    'sigSalt',
  ]) {
    if (headerJson[field] == null) {
      throw SyncBundleStructureException('حقل ترويسة ناقص: $field');
    }
  }
  if (headerJson['sigAlgo'] != syncSigAlgo) {
    throw SyncBundleStructureException(
        'خوارزمية توقيع غير معروفة: ${headerJson['sigAlgo']}');
  }
  final sigSalt = _tryHex(headerJson['sigSalt'] as String);
  if (sigSalt == null || sigSalt.length != _saltLen) {
    throw const SyncBundleStructureException('ملح التوقيع غير سليم');
  }

  // التوقيع قبل البصمة: يحكم الترويسة والكتلة معاً بنفس البايتات التي
  // وقّعها كاتبها (ترتيب المفاتيح ثابت بعقد الصيغة فإعادة الترميز
  // مطابقة حرفاً — وأي خلل بنيوي بالترويسة انكشف قبل هذا الموضع).
  final headerPrefix = jsonEncode(headerJson);
  final sigKey = await _deriveSyncKey(sigSalt, syncSigInfo);
  final expected = c.Hmac(c.sha256, sigKey)
      .convert(utf8.encode('$headerPrefix\n$eventsBlock'))
      .bytes;
  final actualSig = _tryHex(sigHex);
  if (actualSig == null || !_constTimeEquals(actualSig, expected)) {
    throw const SyncBundleTamperException(
        'توقيع الحزمة لا يجتز — عبث أو مفتاح لا يطابق (DQ-1110)');
  }

  final eventsBytes = utf8.encode(eventsBlock);
  final digestOk = c.sha256.convert(eventsBytes).toString() ==
      headerJson['eventsSha256'] as String;
  if (!digestOk) {
    throw const SyncBundleTamperException(
        'بصمة أحداث الحزمة لا تجتز — محتوى مُعبث به أو تالف (DQ-1110)');
  }

  final expectedCount = headerJson['eventCount'];
  final expectedLast = headerJson['lastSeq'];
  if (expectedCount is! int || expectedLast is! int) {
    throw const SyncBundleStructureException(
        'عدّادا الترويسة ليسا عددين (eventCount/lastSeq)');
  }
  final rawLines = eventsBlock.isEmpty
      ? <String>[]
      : eventsBlock.split('\n')..removeWhere((l) => l.isEmpty);
  if (rawLines.isEmpty) {
    throw const SyncBundleStructureException('حزمة بلا أحداث — لا تُقبل');
  }
  if (rawLines.length != expectedCount) {
    throw SyncBundleStructureException(
        'عدد الأحداث لا يطابق الترويسة: ${rawLines.length} ≠ $expectedCount');
  }

  final events = <SyncEvent>[];
  final seenUuid = <String>{};
  var prevSeq = 0;
  for (var i = 0; i < rawLines.length; i++) {
    late final Map<String, Object?> row;
    try {
      final decoded = jsonDecode(rawLines[i]);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException();
      }
      row = decoded;
    } on FormatException {
      throw SyncBundleStructureException('سطر حدث ليس JSON سليماً: ${i + 1}');
    }
    final e = SyncEvent.fromJson(row);
    if (e.companyId != headerJson['companyId']) {
      throw SyncBundleStructureException(
          'حدث بشركة أخرى (${e.companyId}) لا تطابق ترويسة الحزمة '
          '(${headerJson['companyId']}) عند السطر ${i + 1} — رفض عرف د3/D-188');
    }
    if (e.seq <= 0 || (prevSeq != 0 && e.seq != prevSeq + 1)) {
      throw SyncBundleStructureException(
          'انكسار تسلسل seq عند السطر ${i + 1}: ${e.seq} بعد $prevSeq '
          '— التسلسل متصل بلا فجوة ولا تكرار ولا غير موجب');
    }
    if (!seenUuid.add(e.uuid)) {
      throw SyncBundleStructureException(
          'uuid مكرر داخل الحزمة (${e.uuid}) — بنية فاسدة لا استيراد مزدوج');
    }
    events.add(e);
    prevSeq = e.seq;
  }
  if (events.last.seq != expectedLast) {
    throw SyncBundleStructureException(
        'آخر تسلسل لا يطابق الترويسة: ${events.last.seq} ≠ $expectedLast');
  }

  final header = SyncBundleHeader(
    companyId: headerJson['companyId'] as String,
    deviceId: headerJson['deviceId'] as String,
    lastSeq: expectedLast,
    eventCount: expectedCount,
    eventsSha256: headerJson['eventsSha256'] as String,
    sigAlgo: syncSigAlgo,
    sigSaltHex: headerJson['sigSalt'] as String,
    signatureHex: sigHex,
  );
  if (expectedCompanyId != null &&
      header.companyId != expectedCompanyId) {
    throw SyncForeignCompanyException(
        'الحزمة من شركة أخرى (${header.companyId}) — والجهاز على '
        '$expectedCompanyId — فالرفض قبل أي إلحاق (عرف §10)');
  }
  return SyncBundleContents(header: header, events: events);
}

/// عقد الجسر اليدوي س-23: «الأحداث المكررة بنفس uuid تُتجاهل بأمان
/// فلا دمج مزدوج مهما تكرر الاستيراد» — يفصل القادم الجديد عن المكرر
/// على ما يعرفه المتلقي، والمكرر بهدوء لا برفض.
({List<SyncEvent> fresh, int ignored}) filterKnownSyncEvents(
  List<SyncEvent> incoming,
  Set<String> knownUuids,
) {
  final fresh = <SyncEvent>[];
  var ignored = 0;
  final seenHere = <String>{};
  for (final e in incoming) {
    if (knownUuids.contains(e.uuid) || !seenHere.add(e.uuid)) {
      ignored++;
    } else {
      fresh.add(e);
    }
  }
  return (fresh: fresh, ignored: ignored);
}

/// البند ④ بذرة العقد النقي (موعده الموثق «مرتبط بداية د1» — س167):
/// دمج مرابض أحداث أجهزة بالترتيب المرجعي المتفق — ترتيب وصول المرابض
/// يحاكي الترتيب المرجعي الواحد للخادم (08 §3) حتى د4، والمكرر بين
/// المرابض يُتجاهل بهدوء عرف س-23، والكل إلحاق فقط بلا فقد لأي نسخة
/// (append-only). العائد: المجرى المدموج بترتيبه المرجعي وعدد ما
/// تُوجِل بهدوء.
({List<SyncEvent> merged, int ignored}) mergeSyncStreams(
  List<List<SyncEvent>> streams,
) {
  final known = <String>{};
  final merged = <SyncEvent>[];
  var ignored = 0;
  for (final stream in streams) {
    final split = filterKnownSyncEvents(stream, known);
    merged.addAll(split.fresh);
    ignored += split.ignored;
    for (final e in split.fresh) {
      known.add(e.uuid);
    }
  }
  return (merged: merged, ignored: ignored);
}

/// قاعدة الحل المعلنة سلفاً (F-135 — 08 §3) على أحداث كيان واحد جاءت
/// من أجهزة متعددة: **آخر حدث بالترتيب المرجعي يفوز وكلا الحدثين يبقى
/// في السجل** (لا فقد لأي نسخة — فالمحتوى كله قابل للاسترجاع من
/// السجل إن كان الحذف آخراً). هوية الكيان عبر الأجهزة من uuid لقطته
/// بالحمولة لا من معرفه المحلي (entity_id id لكل جهاز) — والانتقاء
/// بيد المستدعي، والحسم هنا بعقد القاعدة لا اجتهاد لحظي.
SyncEvent referenceOrderWinner(Iterable<SyncEvent> eventsForEntity) {
  final list = eventsForEntity.toList();
  if (list.isEmpty) {
    throw const SyncBundleStructureException(
        'فائز التعارض: لا أحداث للكيان أصلاً');
  }
  return list.last;
}

Future<List<int>> _deriveSyncKey(List<int> salt, List<int> info) async {
  final derived = await _hkdf.deriveKey(
    secretKey: cg.SecretKeyData(Uint8List.fromList(_syncRootKey)),
    nonce: salt,
    info: info,
  );
  return derived.extractBytes();
}

List<int> _random(int length, [Random? rng]) {
  final random = rng ?? Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int>? _tryHex(String hex) {
  if (hex.isEmpty || hex.length % 2 != 0) return null;
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

/// مقارنة زمن ثابت للتوقيع — لا مفتاح توقيت يقرأ من حرف مطابق مبكراً.
bool _constTimeEquals(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

bool _startsWith(List<int> blob, List<int> prefix) {
  if (blob.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (blob[i] != prefix[i]) return false;
  }
  return true;
}

int _requireInt(Map<String, Object?> json, String field) {
  final v = json[field];
  if (v is! int) {
    throw SyncBundleStructureException('حقل حدث ناقص أو غير عددي: $field');
  }
  return v;
}

int? _optionalInt(Map<String, Object?> json, String field) {
  final v = json[field];
  if (v == null) return null;
  if (v is! int) {
    throw SyncBundleStructureException('حقل حدث غير عددي: $field');
  }
  return v;
}

String _requireText(Map<String, Object?> json, String field) {
  final v = json[field];
  if (v is! String) {
    throw SyncBundleStructureException('حقل حدث ناقص أو غير نصي: $field');
  }
  return v;
}

/// الغلاف: ليس حزمة، أو إصدار غلاف مجهول، أو وسم السلامة لم يجتز
/// — **DQ-1109**.
class SyncBundleEnvelopeException implements Exception {
  final String message;
  const SyncBundleEnvelopeException(this.message);
  @override
  String toString() => message;
}

/// المضمون مُعبث به: التوقيع أو البصمة لم يجتزا بعد فك غلاف سليم
/// — **DQ-1110**. هذا هو رفض «البايت المعبّث» المفهرس بنص معيار د1.
class SyncBundleTamperException implements Exception {
  final String message;
  const SyncBundleTamperException(this.message);
  @override
  String toString() => message;
}

/// البنية: معرف/إصدار صيغة، حقل ناقص، انكسار `seq`، تكرار `uuid`
/// داخل الحزمة، عدّاد لا يطابق، حدث فارغ — **DQ-1111**.
class SyncBundleStructureException implements Exception {
  final String message;
  const SyncBundleStructureException(this.message);
  @override
  String toString() => message;
}

/// حزمة من شركة أخرى — رفض المتلقي قبل أي إلحاق — **DQ-1112**.
class SyncForeignCompanyException implements Exception {
  final String message;
  const SyncForeignCompanyException(this.message);
  @override
  String toString() => message;
}
