/// د4 (س171): العميل الشبكي الأول — بند §37 الثاني «تحقق TLS صارم»
/// بموضعه الموثق («مع أول عميل HTTP»): HttpClient بلا أي
/// `badCertificateCallback` يلغي التحقق — لا إلغاء ولا تهور. وإن لزمت
/// شهادة خاصة (خادم المنشأة بجذرها الخاص) فتُضاف إلى `SecurityContext`
/// عند البناء حرفاً بنص وثيقة التشفير «ما يجب ألا تفعله» بند 3: «ما
/// يجب ألا تفعله: تعطيل التحقق من الشهادات — وإن لزمت شهادة خاصة
/// تُضاف إلى SecurityContext».
///
/// فشل المصافحة أو الشهادة أو الشبكة يظهر استثناءً صريحاً مفهرساً
/// (DQ-1113) لا صمتاً ولا قيمة فارغة — فالصمت في المزامنة خطأ.
///
/// dart:io نقية Dart بلا Flutter ولا Drift (F-010 حرفها: بلا Flutter
/// ولا Drift — والمهمة النقية تبنيها وتخبرها في CI كما هي).
library;

import 'dart:io';

import 'sync_adapter.dart';

/// عميل النقل الحقيقي — TLS صارم بلا سطح تجاوز بأكمله.
class IoHttpTransport implements SyncTransport {
  /// مهلة الاتصال — فلا تعليق بلا شبكة (N-002: لا وظيفة تحتاج شبكة،
  /// والمزامنة مسار اختياري ففشلها سريع لا معلق).
  static const Duration connectionTimeout = Duration(seconds: 15);

  final HttpClient _client;

  /// سياق TLS اختياري — موضع إضافة شهادة الجذر الخاصة بخادم المنشأة
  /// (المسار المشروع الوحيد للشهادات الخاصة — بلا إلغاء تحقق أبداً).
  final SecurityContext? securityContext;

  IoHttpTransport({this.securityContext})
      : _client = HttpClient(context: securityContext) {
    _client.connectionTimeout = connectionTimeout;
  }

  @override
  Future<SyncHttpResponse> request(SyncHttpRequest request) async {
    final HttpClientRequest req =
        await _client.openUrl(request.method, request.url);
    request.headers.forEach(req.headers.set);
    if (request.body != null) {
      req.add(request.body!);
    }
    final HttpClientResponse response;
    try {
      response = await req.close();
    } on HandshakeException catch (e) {
      // فشل مصافحة TLS — شهادة غير موثوقة أو صانع متوسط: رفض صريح.
      throw SyncAdapterException('فشل مصافحة TLS — الشهادة غير موثوقة '
          'أو القناة اعتراضها: ${e.message}');
    } on SocketException catch (e) {
      throw SyncAdapterException('فشل الاتصال بالخادم: ${e.message}');
    } on HttpException catch (e) {
      throw SyncAdapterException('فشل الطلب الشبكي: ${e.message}');
    }
    final body = await response.fold<List<int>>(
        <int>[], (acc, chunk) => acc..addAll(chunk));
    return SyncHttpResponse(statusCode: response.statusCode, body: body);
  }
}

/// يبني سياق TLS جديداً بجذر شهادة خادم المنشأة (PEM) — السياق الجديد
/// يثق بالجذر المضاف حصراً فلا يُمَس السياق العام للتطبيق، وهذا هو
/// المسار المشروع الوحيد للشهادات الخاصة: إضافة جذر لا إلغاء تحقق.
/// ظاهر للعام لأن إعدادات الاتصال تُبنى من ملفات الجهاز على مسارها.
SecurityContext buildSecurityContextWithPem(List<int> pemBytes) {
  final context = SecurityContext();
  context.setTrustedCertificatesBytes(pemBytes);
  return context;
}
