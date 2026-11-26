// اختبارات د4 (س171 — المهايئ الأول بحسم م-٣ على التوصية الموثقة):
// عقد F-130 حرفاً — دفع مرتب بلا نصف أحداث، سحب مرتب قابل للاستئناف،
// رفض uuid المكرر بهدوء، مؤشرات وتفريغ أولي كامل — وTLS إلزامي بلا
// استثناء (بند §37 الثاني) والصلاحيات بالرفض الصريح F-136 — بناقل
// مصنوع والتحقق الحي على الخادم الحقيقي بيد المالك (س-25/D-211).
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// مصنع حدث قياسي للنقل.
SyncEvent ev(int seq, String uuid, {String? companyId}) => SyncEvent(
      seq: seq,
      uuid: uuid,
      eventAt: 1760000000 + seq,
      userId: null,
      deviceId: 'DESHT-01',
      entityType: 'move',
      entityId: seq,
      action: 'posted',
      companyId: companyId ?? kDefaultCompanyId,
      payloadJson: 'لقطة حدث $seq',
    );

/// ناقل مصنوع مبرمج الردود — يرصد كل طلب حرفاً.
class FakeTransport implements SyncTransport {
  final List<SyncHttpRequest> requests = <SyncHttpRequest>[];
  SyncHttpResponse Function(SyncHttpRequest request)? handler;
  Object? throwOnNext;

  @override
  Future<SyncHttpResponse> request(SyncHttpRequest request) async {
    requests.add(request);
    if (throwOnNext != null) {
      throw throwOnNext!;
    }
    return handler!(request);
  }

  SyncHttpResponse json(Map<String, Object?> body, [int status = 200]) =>
      SyncHttpResponse(statusCode: status, body: utf8.encode(jsonEncode(body)));

  SyncHttpResponse batch(List<int> statuses) => json(<String, Object?>{
        'batch': [
          for (final s in statuses)
            s == 200
                ? <String, Object?>{'status': 200}
                : <String, Object?>{
                    'status': s,
                    'body': <String, Object?>{
                      'data': <String, Object?>{
                        'uuid': <String, Object?>{'code': 'validation_not_unique'}
                      }
                    }
                  }
        ]
      });
}

/// رد سحب نمطي بصيغة PocketBase.
Map<String, Object?> page(List<SyncEvent> events) => <String, Object?>{
      'items': [for (final e in events) adapterRecord(e)],
      'page': 1,
      'perPage': events.length,
      'totalItems': events.length,
    };

Map<String, Object?> adapterRecord(SyncEvent e) =>
    PocketBaseSyncAdapter.recordJsonStatic(e);

PocketBaseSyncAdapter makeAdapter(FakeTransport transport) {
  return PocketBaseSyncAdapter(
    transport: transport,
    baseUrl: Uri.parse('https://sync.desht.local'),
    authToken: 'session-token-1',
    deviceId: 'DESHT-01',
    companyId: 'main',
  );
}

void main() {
  test('TLS إلزامي بلا استثناء: العنوان غير الآمن مرفوض قبل أي بايت', () {
    expect(
      () => PocketBaseSyncAdapter(
        transport: FakeTransport(),
        baseUrl: Uri.parse('http://192.168.1.10:8090'),
        authToken: 't',
        deviceId: 'D1',
        companyId: 'main',
      ),
      throwsA(isA<SyncAdapterException>()),
      reason: 'لا badCertificateCallback ولا http — نص 08 §6 وبند §37 الثاني',
    );
  });

  test('البناء يرفض رمز جلسة فارغاً — لا مزامنة بلا هوية', () {
    expect(
      () => PocketBaseSyncAdapter(
        transport: FakeTransport(),
        baseUrl: Uri.parse('https://sync.desht.local'),
        authToken: '',
        deviceId: 'D1',
        companyId: 'main',
      ),
      throwsA(isA<SyncAdapterException>()),
    );
  });

  test('push دفعة ذرية مرتبة: كل حدث طلب بترتيبه داخل الطلبات', () async {
    final transport = FakeTransport();
      transport.handler = (r) => transport.batch([200, 200, 200]);
    final adapter = makeAdapter(transport);
    final outcome = await adapter
        .push([ev(1, 'u1'), ev(2, 'u2'), ev(3, 'u3')]);
    expect(outcome.ok, isTrue);
    expect(outcome.pushed, 3);
    expect(outcome.ignoredDuplicates, 0);
    expect(transport.requests.single.method, 'POST');
    expect(transport.requests.single.url.path, '/api/batch');
    final body = jsonDecode(
        utf8.decode(transport.requests.single.body!)) as Map<String, Object?>;
    final urls = (body['requests'] as List)
        .whereType<Map<String, Object?>>()
        .map((r) => r['url'])
        .toList();
    expect(urls.length, 3);
    expect(body['requests'] as List, hasLength(3));
    final seqs = (body['requests'] as List)
        .whereType<Map<String, Object?>>()
        .map((r) => (r['body'] as Map<String, Object?>)['seq'])
        .toList();
    expect(seqs, [1, 2, 3], reason: 'الدفع مرتب بلا نصف أحداث — F-130');
    final companies = (body['requests'] as List)
        .whereType<Map<String, Object?>>()
        .map((r) => (r['body'] as Map<String, Object?>)['company_id'])
        .toList();
    expect(companies, ['main', 'main', 'main'],
        reason: 'شركة كل حدث تحملها للخادم — د3/D-188');
  });

  test('push فشل الدفعة الذرية: بلا نصف أحداث ورفض صريح DQ-1114', () async {
    final transport = FakeTransport();
      transport.handler = (r) => transport.json(<String, Object?>{'code': 'x'}, 400);
    final adapter = makeAdapter(transport);
    await expectLater(
      adapter.push([ev(1, 'u1'), ev(2, 'u2')]),
      throwsA(isA<SyncAdapterException>()),
    );
    try {
      await adapter.push([ev(1, 'u1')]);
      fail('لا صمت على فشل الدفعة');
    } on SyncAdapterException catch (e) {
      expect(e.serverRefused, isTrue);
      expect(dqCodeForDomainError(e), 'DQ-1114');
    }
  });

  test('push المكرر يُتجاهل بهدوء: pushed وignored بالتفصيل', () async {
    final transport = FakeTransport();
      transport.handler = (r) => transport.batch([200, 400, 200]);
    final adapter = makeAdapter(transport);
    final outcome = await adapter
        .push([ev(1, 'u1'), ev(2, 'dup'), ev(3, 'u3')]);
    expect(outcome.ok, isTrue);
    expect(outcome.pushed, 2);
    expect(outcome.ignoredDuplicates, 1,
        reason: 'رفض uuid المكرر بهدوء — F-130/§10');
  });

  test('رفض الصلاحيات صريح: 403 يستثنى مفهرساً ولا صمت (F-136)', () async {
    final transport = FakeTransport();
      transport.handler = (r) => transport.json(<String, Object?>{}, 403);
    final adapter = makeAdapter(transport);
    try {
      await adapter.push([ev(1, 'u1')]);
      fail('لا صمت على رفض الخادم');
    } on SyncAdapterException catch (e) {
      expect(e.serverRefused, isTrue);
      expect(dqCodeForDomainError(e), 'DQ-1114');
    }
  });

  test('فشل النقل مفهرس DQ-1113: الشبكة تسقط استثناءً لا صمتاً', () async {
    final transport = FakeTransport()..throwOnNext = SocketException('شبكة');
    final adapter = makeAdapter(transport);
    try {
      await adapter.push([ev(1, 'u1')]);
      fail('لا صمت على فشل النقل');
    } on SyncAdapterException catch (e) {
      expect(e.serverRefused, isFalse);
      expect(dqCodeForDomainError(e), 'DQ-1113');
    }
  });

  test('pull مرتب قابل للاستئناف: المؤشر يعاد والصفحات متتابعة بلا فقد',
      () async {
    final transport = FakeTransport();
    var call = 0;
    transport.handler = (r) {
      call++;
      if (call == 1) return transport.json(page([ev(1, 'a'), ev(2, 'b')]));
      return transport.json(page([ev(3, 'c')]));
    };
    final adapter = makeAdapter(transport);
    final first = await adapter.pull(afterSeq: 0, limit: 2);
    expect(first.events.map((e) => e.seq), [1, 2]);
    expect(first.nextCursor, 2);
    expect(first.hasMore, isTrue);
    final second = await adapter.pull(afterSeq: first.nextCursor, limit: 2);
    expect(second.events.map((e) => e.seq), [3]);
    expect(second.nextCursor, 3);
    expect(second.hasMore, isFalse);
    // طلب الاستئناف يحمل المؤشر بعقد الفلتر (ترميز عنوان dart: علامة + للمسافة).
    final secondUrl = transport.requests[1].url.toString();
    expect(secondUrl, contains('seq+%3E+2'));
    expect(secondUrl, contains('sort=seq'));
    expect(secondUrl, contains("company_id%3D%27main%27"),
        reason: 'العزل بالشركة على الخادم — د3/D-188');
  });

  test('pull فارغة تعيد المؤشر كما هو — استئناف آمن', () async {
    final transport = FakeTransport();
    transport.handler = (r) => transport.json(page([]));
    final adapter = makeAdapter(transport);
    final batch = await adapter.pull(afterSeq: 7);
    expect(batch.events, isEmpty);
    expect(batch.nextCursor, 7);
    expect(batch.hasMore, isFalse);
  });

  test('التفريغ الأولي كامل: سحب من الصفر حتى النهاية بالترتيب (س-24)',
      () async {
    final transport = FakeTransport();
    var call = 0;
    transport.handler = (r) {
      call++;
      if (call == 1) return transport.json(page([ev(1, 'a'), ev(2, 'b'), ev(3, 'c')]));
      return transport.json(page([ev(4, 'd')]));
    };
    final adapter = PocketBaseSyncAdapter(
      transport: transport,
      baseUrl: Uri.parse('https://sync.desht.local'),
      authToken: 'session-token-1',
      deviceId: 'DESHT-01',
      companyId: 'main',
      pullPageSize: 3,
    );
    final dump = await adapter.initialDump();
    expect(dump.map((e) => e.seq), [1, 2, 3, 4]);
    final cursors = transport.requests
        .map((r) => Uri.parse(r.url.toString()).queryParameters['filter'])
        .toList();
    expect(cursors.first, contains('seq > 0'),
        reason: 'التفريغ من الصفر حصراً');
    expect(cursors.last, contains('seq > 3'));
  });

  test('الخادم يسحب حدثاً من شركة أخرى — انتهاك العزل رفض صريح', () async {
    final transport = FakeTransport();
      transport.handler = (r) => transport.json(page([ev(1, 'x', companyId: 'other')]));
    final adapter = makeAdapter(transport);
    await expectLater(
      adapter.pull(afterSeq: 0),
      throwsA(isA<SyncAdapterException>()),
    );
  });

  test('حقل السجل يحمل كل أركان الحدث وشركته — عقد النقل د3', () {
    final e = ev(5, 'u5');
    final record = PocketBaseSyncAdapter.recordJsonStatic(e);
    expect(record['company_id'], 'main');
    expect(record['device_id'], 'DESHT-01');
    expect(record['uuid'], 'u5');
    expect(record['seq'], 5);
    final back = PocketBaseSyncAdapter.recordFromJsonStatic(record);
    expect(back.seq, e.seq);
    expect(back.uuid, e.uuid);
    expect(back.companyId, e.companyId);
    expect(back.deviceId, e.deviceId);
    expect(back.entityType, e.entityType);
    expect(back.action, e.action);
    expect(back.eventAt, e.eventAt);
    expect(back.payloadJson, e.payloadJson);
  });

  test('العميل الحقيقي TLS صارم: سياق بجذر خاص يبنى من PEM بلا تجاوز',
      () {
    const pem = '''-----BEGIN CERTIFICATE-----
MIIDFzCCAf+gAwIBAgIUPA8+xDLGxeKqE/EhIth9RX/Z+DwwDQYJKoZIhvcNAQEL
BQAwGzEZMBcGA1UEAwwQZGlxcWFoLXRlc3Qtcm9vdDAeFw0yNjExMTkwNTIwMjFa
Fw00NjExMTQwNTIwMjFaMBsxGTAXBgNVBAMMEGRpcXFhaC10ZXN0LXJvb3QwggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDF/H/yAaGxRMePDLrwNfDec1Ih
ynmnhDiqnTkEInbL5T3epykQy0mTCIxaXIERMunFAJmHv3ow8AcLtBJt+NlEJCDx
WT3rFuusnYUH8eoMZyulfTyUFOQkPeEz03c9/n52cbrAS7rXMGf9ogJL//Eb1M38
zPZDiNOsNBbAl5RWgQUtejhXvuavOupwcpjy45fYRWZu29ZPKzRAOFirCnpz0HUB
/pCd0kttyL8AiW5VI5C72JHEstGBqWGJX5Jiz0tBzBZJvV5y0JkWeJLMZkHp0eNj
jShG5Y0I67sr68RtGqsqdaCvvFeI8TBl+1Wq1NmxPxbcl0WVdeIwyUSvT31VAgMB
AAGjUzBRMB0GA1UdDgQWBBQbxOSKMJb8V9YSAzvhedX1LRMvOjAfBgNVHSMEGDAW
gBQbxOSKMJb8V9YSAzvhedX1LRMvOjAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3
DQEBCwUAA4IBAQBbnpUeE0/bLRWLQUKZdSPWUAcgjQlYo1qQClAuEcH/rd/quJFQ
jtXxFaslG1Gs0mHbCKoRJl5t70IzAASt3lxyiECP3rNFdajHgxSvkYIJ5rzCJwaS
Mos6e+Lrhu8yfmXm1EmfqXEb9x0ZyskSEdWPYhu8h2LnkmsNa6nJUGG/Lx1GChOE
ZeoXSQhaMTwNUjNHiuIBmdwiZeKDi5Q7JslSSH2v1E8pmx5ZY0hSFacc6chOASmy
q8H4mKHJW9ndU80tpDDg+/Aacr00UZvgV5jPz0CIiltP7sdP8IEjLjIDUWjfUN20
KlnfakAnlvGpRIKA+RZGa2o1xIAoD7XKMP8z
-----END CERTIFICATE-----''';
    // المسار المشروع للشهادة الخاصة: إضافة جذر إلى سياق جديد لا إلغاء
    // تحقق — وثيقة التشفير «ما يجب ألا تفعله» بند 3 حرفاً.
    final context = buildSecurityContextWithPem(utf8.encode(pem));
    final transport = IoHttpTransport(securityContext: context);
    expect(transport, isA<SyncTransport>());
    // والسياق العام للتطبيق لم يُمس — السياق الجديد بجذر المنشأة حصراً.
    expect(context, isNot(same(SecurityContext.defaultContext)));
  });

  test('المؤشرات: /api/health يعلن الوصول والانقطاع بلا استثناء', () async {
    final transport = FakeTransport();
      transport.handler = (r) => transport.json(<String, Object?>{'status': 'ok'});
    final adapter = makeAdapter(transport);
    final up = await adapter.status();
    expect(up.serverReachable, isTrue);
    expect(up.adapterId, 'pocketbase');
    transport.throwOnNext = SocketException('انقطاع');
    final down = await adapter.status();
    expect(down.serverReachable, isFalse,
        reason: 'شريط الحالة يعلن الانقطاع لا يفشل — س-25');
  });

  test('الرموز المفهرسة في السجل وخريطة الاستثناءات بالوجهين', () {
    expect(diqqahErrorCodeOf('DQ-1113'), isNotNull);
    expect(diqqahErrorCodeOf('DQ-1114'), isNotNull);
    expect(
      dqCodeForDomainError(
          SyncAdapterException('نقل', serverRefused: false)),
      'DQ-1113',
    );
    expect(
      dqCodeForDomainError(
          SyncAdapterException('رفض', serverRefused: true)),
      'DQ-1114',
    );
  });
}
