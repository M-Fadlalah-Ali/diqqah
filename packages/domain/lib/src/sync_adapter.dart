/// د4 (س171 — المهايئ الأول بحسم م-٣ بكلمة المالك «و4» على التوصية
/// الموثقة §46): عقد واجهة المزامنة المشترك F-130 (D-010) ومهايئ
/// PocketBase ذاتي الاستضافة (D-014/F-132) — «يعمل بشبكة المنشأة حتى
/// مع انقطاع الإنترنت العام وسيطرة كاملة N-007».
///
/// **العقد المشترك F-130 حرفاً** (08 §5) — أربعة التزامات:
/// 1. دفع مرتب بلا نصف أحداث — الدفعة ذرية على الخادم (المسار الدفعي)
///    فإما كلها أو لا شيء.
/// 2. سحب مرتب قابل للاستئناف — بمؤشر `seq` يعاد مع كل دفعة.
/// 3. رفض `uuid` المكرر بهدوء — عرف §10/س-23 فلا دمج مزدوج.
/// 4. مؤشرات لكل جهاز مع إمكانية تفريغ أولي كامل — سحب من الصفر
///    بالترتيب المرجعي (س-24).
///
/// **قاعدة الخيار**: مزوّد نشط واحد في كل وقت وتبديله قرار مالك موثق
/// كحدث لا سلوكاً صامتاً — والمهايئ لا يقرر شيئاً بنفسه.
///
/// **الأمان (08 §6/بند §37 الثاني)**: HTTPS حصراً بلا استثناء — لا
/// `badCertificateCallback` يلغي التحقق أبداً وإن لزمت شهادة خاصة
/// (خادم المنشأة) فتُضاف إلى `SecurityContext` عند بناء العميل حرفاً
/// بنص وثيقة التشفير «ما يجب ألا تفعله» بند 3 — والعميل الحقيقي
/// `IoHttpTransport` (sync_http_transport.dart) يجسد ذلك.
///
/// **الصلاحيات F-136**: الخادم بصفة المرجع يرفض المخالف صراحةً
/// (401/403) والجهاز يفرض بصمت بمصفوفته المحلية (س164) — فلا يثق
/// أحد بطرفٍ آخر، والرفض الصريح استثناء مفهرس لا صمت.
///
/// **حد صادق**: التحقق الحي بالخادم الحقيقي وأجهزة المالك بتصديق
/// مكتوب (س-25 معيار الجاهزية §5 — D-211) — وما هنا العقدُ النقي
/// والمحرك المجرَّب بناقل مصنوع، لا زعم اتصال حي.
library;

import 'dart:convert';

import 'sync_bundle.dart';

/// نتيجة الدفع — تفصيل ما استقر وما تُوجِل بهدوء وما فشل صراحةً.
class PushOutcome {
  final int pushed;
  final int ignoredDuplicates;

  /// فشل صريح — الدفعة لم تستقر (بلا نصف أحداث) والرسالة من الخادم.
  final String? failureMessage;
  final bool serverRefused;

  const PushOutcome({
    required this.pushed,
    required this.ignoredDuplicates,
    this.failureMessage,
    this.serverRefused = false,
  });

  bool get ok => failureMessage == null;
}

/// دفعة سحب واحدة — مرتبة صاعدة بseq ومؤشر الاستئناف معها.
class PullBatch {
  final List<SyncEvent> events;

  /// مؤشر الاستئناف: آخر seq مسحوب، أو المارّ إن كانت الدفعة فارغة.
  final int nextCursor;
  final bool hasMore;

  const PullBatch({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });
}

/// مؤشرات المهايئ — شريط الحالة (س-25: «آخر مزامنة + عدد معلق» دائماً).
class SyncAdapterStatus {
  final String adapterId;
  final String deviceId;
  final String companyId;
  final bool serverReachable;

  const SyncAdapterStatus({
    required this.adapterId,
    required this.deviceId,
    required this.companyId,
    required this.serverReachable,
  });
}

/// عقد المهايئ — أي مزوّد يحققه يصلح والتبديل إعدادات لا إعادة بناء.
abstract class SyncAdapter {
  String get adapterId;

  /// دفع مرتب بلا نصف أحداث — الأحداث تمر بترتيبها والدفعة ذرية.
  Future<PushOutcome> push(List<SyncEvent> events);

  /// سحب مرتب قابل للاستئناف — من بعد [afterSeq] حصراً.
  Future<PullBatch> pull({required int afterSeq, int? limit});

  /// التفريغ الأولي كامل (س-24) — سحب من الصفر حتى النهاية بالترتيب.
  Future<List<SyncEvent>> initialDump();

  /// مؤشرات الجهاز — شريط الحالة.
  Future<SyncAdapterStatus> status();
}

/// طلب نقل — نقية كاملة فوق الشبكة الحية.
class SyncHttpRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int>? body;

  const SyncHttpRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
  });
}

/// رد نقل — الحالة والبايتات، والحكم بيد المهايئ لا النقل.
class SyncHttpResponse {
  final int statusCode;
  final List<int> body;

  const SyncHttpResponse({required this.statusCode, required this.body});

  String get bodyText => utf8.decode(body, allowMalformed: true);
}

/// النقل المجرد — المهايئ نقياً فوقه والعميل الحقيقي ينفذها.
abstract class SyncTransport {
  Future<SyncHttpResponse> request(SyncHttpRequest request);
}

/// استثناء المهايئ المفهرس: رفض خادم صريح (401/403 ورفض العملية) →
/// **DQ-1114**، وفشل نقل/شبكة/مصافحة TLS → **DQ-1113** — ولا صمت
/// في أي منها (لا سكوت عرف الدورة).
class SyncAdapterException implements Exception {
  final String message;

  /// true = الخادم رفض صراحةً (DQ-1114) — false = فشل نقل (DQ-1113).
  final bool serverRefused;

  const SyncAdapterException(this.message, {this.serverRefused = false});

  @override
  String toString() => message;
}

/// مهايئ PocketBase ذاتي الاستضافة — نقياً فوق [SyncTransport]:
/// - الدفع بالمسار الدفعي `/api/batch` ذريةً فلا نصف أحداث، وسجل كل
///   حدث سجلاً بالمجموعة بترتيبه، والمكرر (فهرس التفرد بالخادم على
///   uuid) يُعدّ بهدوء لا برفض.
/// - السحب بفلتر `(company_id='…' && seq > cursor)` مرتباً بseq
///   وصفحات قابلة للاستئناف — والعزل بالشركة على الخادم عرف 08 §7
///   (د3/D-188) فلا شركة ترى غير أحداثها.
/// - الرمز الحامل على كل طلب (F-136): الرفض 401/403 صريح مفهرس.
class PocketBaseSyncAdapter implements SyncAdapter {
  static const String eventsCollection = 'diqqah_events';

  @override
  String get adapterId => 'pocketbase';

  final SyncTransport transport;
  final Uri baseUrl;
  final String authToken;
  final String deviceId;
  final String companyId;
  final int pullPageSize;

  PocketBaseSyncAdapter({
    required this.transport,
    required this.baseUrl,
    required this.authToken,
    required this.deviceId,
    required this.companyId,
    this.pullPageSize = 500,
  }) {
    // TLS إلزامي بلا استثناء — الحارس قبل أي بايت على الشبكة.
    if (baseUrl.scheme != 'https') {
      throw SyncAdapterException(
          'TLS إلزامي بلا استثناء (08 §6/بند §37 الثاني) — العنوان '
          'غير الآمن مرفوض: $baseUrl');
    }
    if (authToken.trim().isEmpty) {
      throw SyncAdapterException('رمز الجلسة فارغ — لا مزامنة بلا هوية');
    }
  }

  Map<String, String> get _headers => <String, String>{
        'Authorization': authToken,
        'Content-Type': 'application/json',
      };

  /// جسم الدفعة الذرية — كل حدث طلب إدراج بترتيبه داخل الطلبات.
  String batchBody(List<SyncEvent> events) {
    final requests = events
        .map((e) => <String, Object?>{
              'method': 'POST',
              'url': '/api/collections/$eventsCollection/records',
              'body': recordJsonStatic(e),
            })
        .toList();
    return jsonEncode(<String, Object?>{'requests': requests});
  }

  /// جسم سجل PocketBase — الحقول بعقد المهايئ وشركة كل حدث تحملها.
  /// ثابتٌ لا يتعلق بالهيئ لأن السجل عقد نقل لا حالة مهيئ.
  static Map<String, Object?> recordJsonStatic(SyncEvent e) =>
      <String, Object?>{
        'uuid': e.uuid,
        'seq': e.seq,
        'company_id': e.companyId,
        'device_id': e.deviceId,
        'entity_type': e.entityType,
        'entity_id': e.entityId,
        'action': e.action,
        'event_at': e.eventAt,
        'user_id': e.userId,
        'payload': e.payloadJson,
      };

  static SyncEvent recordFromJsonStatic(Map<String, Object?> json) =>
      SyncEvent(
        seq: json['seq'] as int,
        uuid: json['uuid'] as String,
        eventAt: json['event_at'] as int,
        userId: json['user_id'] as int?,
        deviceId: json['device_id'] as String,
        entityType: json['entity_type'] as String,
        entityId: json['entity_id'] as int?,
        action: json['action'] as String,
        companyId: json['company_id'] as String,
        payloadJson: json['payload'] as String,
      );

  bool _isDuplicateMarker(String body) =>
      body.contains('not_unique') ||
      body.contains('validation_not_unique') ||
      body.contains('unique');

  @override
  Future<PushOutcome> push(List<SyncEvent> events) async {
    if (events.isEmpty) {
      return const PushOutcome(pushed: 0, ignoredDuplicates: 0);
    }
    final SyncHttpResponse response;
    try {
      response = await transport.request(SyncHttpRequest(
        method: 'POST',
        url: baseUrl.resolve('/api/batch'),
        headers: _headers,
        body: utf8.encode(batchBody(events)),
      ));
    } on SyncAdapterException {
      rethrow;
    } catch (e) {
      throw SyncAdapterException('فشل النقل أثناء الدفع: $e');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SyncAdapterException(
          'الخادم رفض الدفع صراحةً (${response.statusCode}) — '
          'الصلاحيات بصفة المرجع (F-136)',
          serverRefused: true);
    }
    if (response.statusCode != 200) {
      throw SyncAdapterException(
          'الدفعة الذرية لم تستقر (HTTP ${response.statusCode}) — '
          'بلا نصف أحداث: ${response.bodyText.substring(0, response.bodyText.length.clamp(0, 300))}',
          serverRefused: true);
    }
    // فك ردود الطلبات الداخلية: نجاح = مُدرج، ورفض التفرد = مكرر
    // يُتجاهل بهدوء، وغير ذلك فشل صريح (الدفعة ذرية فلا نصف).
    var pushed = 0;
    var ignored = 0;
    late final Object decoded;
    try {
      decoded = jsonDecode(response.bodyText);
    } on FormatException {
      throw SyncAdapterException('رد الدفعة ليس JSON سليماً');
    }
    if (decoded is! Map<String, Object?> ||
        decoded['batch'] is! List) {
      throw SyncAdapterException('بنية رد الدفعة غير معروفة');
    }
    for (final item in decoded['batch'] as List) {
      if (item is Map<String, Object?> &&
          (item['status'] == 200 || item['status'] == 204)) {
        pushed++;
      } else if (item is Map<String, Object?> &&
          item['status'] == 400 &&
          _isDuplicateMarker(jsonEncode(item['body'] ?? item))) {
        ignored++;
      } else {
        throw SyncAdapterException(
            'رفض الخادم سجلاً بالدفعة صراحةً — '
            'بلا نصف أحداث: ${jsonEncode(item)}',
            serverRefused: true);
      }
    }
    return PushOutcome(
        pushed: pushed, ignoredDuplicates: ignored);
  }

  Uri _pullUri(int afterSeq, int limit) => baseUrl
      .resolve('/api/collections/$eventsCollection/records')
      .replace(queryParameters: <String, String>{
    'filter': "(company_id='$companyId' && seq > $afterSeq)",
    'sort': 'seq',
    'perPage': '$limit',
  });

  @override
  Future<PullBatch> pull({required int afterSeq, int? limit}) async {
    final size = (limit ?? pullPageSize).clamp(1, pullPageSize);
    final SyncHttpResponse response;
    try {
      response = await transport.request(
          SyncHttpRequest(method: 'GET', url: _pullUri(afterSeq, size),
              headers: _headers));
    } on SyncAdapterException {
      rethrow;
    } catch (e) {
      throw SyncAdapterException('فشل النقل أثناء السحب: $e');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SyncAdapterException(
          'الخادم رفض السحب صراحةً (${response.statusCode}) — '
          'الصلاحيات بصفة المرجع (F-136)',
          serverRefused: true);
    }
    if (response.statusCode != 200) {
      throw SyncAdapterException('السحب فشل (HTTP ${response.statusCode})',
          serverRefused: true);
    }
    late final Map<String, Object?> page;
    try {
      page = jsonDecode(response.bodyText) as Map<String, Object?>;
    } on FormatException {
      throw SyncAdapterException('رد السحب ليس JSON سليماً');
    }
    final items = (page['items'] as List? ?? const [])
        .whereType<Map<String, Object?>>()
        .map(recordFromJsonStatic)
        .toList();
    for (final e in items) {
      if (e.companyId != companyId) {
        throw SyncAdapterException(
            'الخادم سحب حدثاً من شركة أخرى (${e.companyId}) — '
            'انتهاك العزل D-188',
            serverRefused: true);
      }
    }
    final next =
        items.isEmpty ? afterSeq : items.last.seq;
    return PullBatch(
      events: items,
      nextCursor: next,
      hasMore: items.length == size,
    );
  }

  @override
  Future<List<SyncEvent>> initialDump() async {
    final all = <SyncEvent>[];
    var cursor = 0;
    while (true) {
      final batch = await pull(afterSeq: cursor);
      all.addAll(batch.events);
      if (!batch.hasMore) break;
      cursor = batch.nextCursor;
    }
    return all;
  }

  @override
  Future<SyncAdapterStatus> status() async {
    var reachable = false;
    try {
      final response = await transport.request(SyncHttpRequest(
          method: 'GET',
          url: baseUrl.resolve('/api/health'),
          headers: _headers));
      reachable = response.statusCode == 200;
    } catch (_) {
      reachable = false;
    }
    return SyncAdapterStatus(
      adapterId: adapterId,
      deviceId: deviceId,
      companyId: companyId,
      serverReachable: reachable,
    );
  }
}
