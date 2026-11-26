// اختبارات د1 (س169 — عقد المزامنة النقي وحزمة الخروج الموقعة):
// صيغة `.dsync` نص 08 §10 حرفاً + توقيع الخروج بند §37 الأول —
// بناء وفك ورفض البايت المعبّث برموز مفهرسة، والجسر اليدوي س-23
// يمر على الصيغة ذاتها بلا دمج مزدوج مهما تكرر الاستيراد.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// مصنع حدث قياسي — لقطة صغيرة لكن حقولها كاملة.
SyncEvent ev(int seq, String uuid,
    {String? payload,
    String deviceId = 'DESHT-01',
    String action = 'posted',
    String entityType = 'move',
    String? companyId}) {
  return SyncEvent(
    seq: seq,
    uuid: uuid,
    eventAt: 1760000000 + seq,
    userId: null,
    deviceId: deviceId,
    entityType: entityType,
    entityId: seq,
    action: action,
    companyId: companyId ?? kDefaultCompanyId,
    payloadJson: payload ?? 'لقطة حدث $seq عربية',
  );
}

/// سطر حدث JSON بالترميز القياسي (ترتيب المفاتيح بعقد الصيغة).
String evLine(int seq, String uuid, {String? payload, String companyId = 'main'}) {
  return jsonEncode(<String, Object?>{
    'seq': seq,
    'uuid': uuid,
    'event_at': 1760000000 + seq,
    'user_id': null,
    'device_id': 'DESHT-01',
    'entity_type': 'move',
    'entity_id': seq,
    'action': 'posted',
    'company_id': companyId,
    'payload': payload ?? 'لقطة حدث $seq عربية',
  });
}

/// يصنع حزمة موقّعة بمحتوى إرادي — واجهة كاتبٍ معيبٍ أو عدواني:
/// التوقيع صحيح رياضياً والمضمون مخالف لعقد §10، فالفاحص هو الحارس.
Future<List<int>> craftBundle({
  required Map<String, Object?> header,
  required List<String> lines,
  bool omitSignature = false,
  String? overrideSigSalt,
}) async {
  final salt = List<int>.generate(16, (i) => i + 1);
  final eventsBlock = lines.isEmpty ? '' : '${lines.join('\n')}\n';
  final full = <String, Object?>{
    ...header,
    'eventsSha256': sha256.convert(utf8.encode(eventsBlock)).toString(),
    'sigAlgo': syncSigAlgo,
    'sigSalt': overrideSigSalt ??
        salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  };
  final prefix = jsonEncode(full);
  final sig = await signSyncBundleText(
    headerPrefixJson: prefix,
    eventsBlock: eventsBlock,
    sigSalt: salt,
  );
  final headerLine = omitSignature
      ? prefix
      : jsonEncode(<String, Object?>{
          ...full,
          'signature': sig.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        });
  return sealSyncEnvelope(utf8.encode('$headerLine\n$eventsBlock'));
}

/// ترويسة قياسية سليمة لصناعة الحزم المصنوعة.
Map<String, Object?> baseHeader({int lastSeq = 2, int eventCount = 2}) {
  return <String, Object?>{
    'format': syncFormatId,
    'formatVersion': syncFormatVersion,
    'companyId': 'main',
    'deviceId': 'DESHT-01',
    'lastSeq': lastSeq,
    'eventCount': eventCount,
  };
}

void main() {
  test('الجولة: بناء ثم فك يعيد الأحداث حرفاً (عربي وتسلسل وترويسة)', () async {
    final file = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: [
        ev(1, 'u1', payload: '{"ملاحظة":"قيد افتتاحي عربي","amount":113}'),
        ev(2, 'u2'),
      ],
      exportedAt: DateTime(2026, 11, 19, 14, 35),
      rng: Random(20261119),
    );
    expect(
      file.filename,
      'diqqah-sync-20261119-1435-DESHT-01-2.dsync',
      reason: 'الاسم القياسي نص §10 حرفاً',
    );
    final opened =
        await openSyncBundle(file.bytes, expectedCompanyId: 'main');
    expect(opened.events.map((e) => e.uuid).toList(), ['u1', 'u2']);
    expect(opened.events.first.payloadJson,
        '{"ملاحظة":"قيد افتتاحي عربي","amount":113}');
    expect(opened.header.companyId, 'main');
    expect(opened.header.deviceId, 'DESHT-01');
    expect(opened.header.lastSeq, 2);
    expect(opened.header.eventCount, 2);
    expect(opened.header.sigAlgo, syncSigAlgo);
  });

  test('اسم الملف يطهّر معرف الجهاز لمحارف آمنة', () {
    expect(
      syncBundleFilename(
          at: DateTime(2026, 1, 2, 3, 4), deviceId: 'a b/c', lastSeq: 7),
      'diqqah-sync-20260102-0304-a_b_c-7.dsync',
    );
  });

  test('الفرز الصاعد داخل الحزمة مهما جاءت المدخلات', () async {
    final file = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: [ev(3, 'u3'), ev(1, 'u1'), ev(2, 'u2')],
      rng: Random(1),
    );
    final opened = await openSyncBundle(file.bytes);
    expect(opened.events.map((e) => e.seq).toList(), [1, 2, 3]);
  });

  test('حتمية البصمة: نفس الأحداث بنفس الترتيب بنفس sha256 مهما اختلف الملح',
      () async {
    List<SyncEvent> seed() =>
        List.generate(5, (i) => ev(i + 1, 'u${i + 1}'));
    final a = await buildSyncBundle(
        companyId: 'main', deviceId: 'D1', events: seed(), rng: Random(7));
    final b = await buildSyncBundle(
        companyId: 'main', deviceId: 'D1', events: seed(), rng: Random(9));
    final ha = await openSyncBundle(a.bytes);
    final hb = await openSyncBundle(b.bytes);
    expect(ha.header.eventsSha256, hb.header.eventsSha256);
    expect(a.bytes, isNot(b.bytes),
        reason: 'ملح ونونس عشوائيان لكل بناء — لا بايتات متكررة');
  });

  test('س-23 الجسر اليدوي: تصديران متداخلان والمكرر يُتجاهل بهدوء فلا دمج مزدوج',
      () async {
    final morning = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: List.generate(5, (i) => ev(i + 1, 'u${i + 1}')),
      rng: Random(2),
    );
    final first = await openSyncBundle(morning.bytes);
    final known = first.events.map((e) => e.uuid).toSet();

    final evening = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      // تسلسل متصل 3..8 فالتداخل 3..5 عمداً — إعادة تصدير متأخرة.
      events: List.generate(6, (i) => ev(i + 3, 'u${i + 3}')),
      rng: Random(3),
    );
    final second = await openSyncBundle(evening.bytes);
    final split = filterKnownSyncEvents(second.events, known);
    expect(split.fresh.map((e) => e.seq).toList(), [6, 7, 8],
        reason: 'الجديد فقط يُلحق — append-only بلا دمج مزدوج');
    expect(split.ignored, 3, reason: 'المكرر بهدوء لا برفض عرف §10');
  });

  test('المكرر يُتجاهل بهدوء: المعروف والمكرر سوا، والجديد يمر', () {
    final incoming = [ev(1, 'u1'), ev(2, 'u2'), ev(3, 'u1'), ev(4, 'u4')];
    final split = filterKnownSyncEvents(incoming, {'u1'});
    expect(split.fresh.map((e) => e.uuid).toList(), ['u2', 'u4']);
    expect(split.ignored, 2);
  });

  test('العبث ببايت داخل الغلاف يكسر وسم GCM — DQ-1109 لا قبول', () async {
    final file = await buildSyncBundle(
        companyId: 'main', deviceId: 'D1', events: [ev(1, 'u1')], rng: Random(4));
    final tampered = List<int>.from(file.bytes);
    tampered[tampered.length - 20] ^= 0x01; // وسط النص المشفر قبل الوسم
    await expectLater(
      openSyncBundle(tampered),
      throwsA(isA<SyncBundleEnvelopeException>()),
    );
  });

  test('ملف عشوائي ليس حزمة أصلاً — DQ-1109', () async {
    final junk = List<int>.generate(64, (i) => i * 7 % 256);
    await expectLater(
      openSyncBundle(junk),
      throwsA(isA<SyncBundleEnvelopeException>()),
    );
  });

  test('العبث بحمولة حدث بعد الفك والختم من جديد — البصمة ترفض DQ-1110',
      () async {
    final file = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: [ev(1, 'u1', payload: 'لقطة أصيلة 123')],
      rng: Random(5),
    );
    final text = utf8.decode(await openSyncEnvelope(file.bytes));
    final tamperedText = text.replaceFirst('أصيلة 123', 'أصيلة 999');
    final resealed = await sealSyncEnvelope(utf8.encode(tamperedText));
    await expectLater(
      openSyncBundle(resealed),
      throwsA(isA<SyncBundleTamperException>()),
    );
  });

  test('العبث بالترويسة بعد الفك والختم من جديد — التوقيع يرفض DQ-1110',
      () async {
    final file = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: [ev(1, 'u1'), ev(2, 'u2')],
      rng: Random(6),
    );
    final text = utf8.decode(await openSyncEnvelope(file.bytes));
    final nl = text.indexOf('\n');
    final header = text.substring(0, nl).replaceFirst('DESHT-01', 'DESHT-02');
    final resealed =
        await sealSyncEnvelope(utf8.encode('$header${text.substring(nl)}'));
    await expectLater(
      openSyncBundle(resealed),
      throwsA(isA<SyncBundleTamperException>()),
    );
  });

  test('معرف صيغة مجهول في حزمة موقّعة — DQ-1111', () async {
    final blob = await craftBundle(
      header: <String, Object?>{...baseHeader(), 'format': 'other-sync'},
      lines: [evLine(1, 'u1'), evLine(2, 'u2')],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('إصدار صيغة أحدث في حزمة موقّعة — DQ-1111', () async {
    final blob = await craftBundle(
      header: <String, Object?>{...baseHeader(), 'formatVersion': 2},
      lines: [evLine(1, 'u1'), evLine(2, 'u2')],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('عدد الأحداث لا يطابق الترويسة — DQ-1111', () async {
    final blob = await craftBundle(
      header: baseHeader(lastSeq: 2, eventCount: 5),
      lines: [evLine(1, 'u1'), evLine(2, 'u2')],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('آخر تسلسل لا يطابق الترويسة — DQ-1111', () async {
    final blob = await craftBundle(
      header: baseHeader(lastSeq: 7, eventCount: 2),
      lines: [evLine(1, 'u1'), evLine(2, 'u2')],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('انكسار تسلسل seq (فجوة وسط الحزمة) — DQ-1111', () async {
    final blob = await craftBundle(
      header: baseHeader(lastSeq: 4, eventCount: 3),
      lines: [evLine(1, 'u1'), evLine(2, 'u2'), evLine(4, 'u4')],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('uuid مكرر داخل الحزمة بنية فاسدة — DQ-1111', () async {
    final blob = await craftBundle(
      header: baseHeader(lastSeq: 2, eventCount: 2),
      lines: [evLine(1, 'u1'), evLine(2, 'u1')],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('ترويسة بلا توقيع — DQ-1111', () async {
    final blob = await craftBundle(
      header: baseHeader(),
      lines: [evLine(1, 'u1'), evLine(2, 'u2')],
      omitSignature: true,
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('حقل ترويسة ناقص (deviceId) — DQ-1111', () async {
    final header = <String, Object?>{...baseHeader()}..remove('deviceId');
    final blob = await craftBundle(
      header: header,
      lines: [evLine(1, 'u1'), evLine(2, 'u2')],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('ملح توقيع غير سليم — DQ-1111 قبل أي فحص توقيع', () async {
    final blob = await craftBundle(
      header: baseHeader(),
      lines: [evLine(1, 'u1'), evLine(2, 'u2')],
      overrideSigSalt: 'zz-غير-سداسي',
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('سطر حدث ليس JSON سليماً — DQ-1111', () async {
    final blob = await craftBundle(
      header: baseHeader(lastSeq: 2, eventCount: 2),
      lines: [evLine(1, 'u1'), '{broken-json'],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('حزمة موقّعة من شركة أخرى — DQ-1112 بيد المتلقي', () async {
    final file = await buildSyncBundle(
        companyId: 'main', deviceId: 'D1', events: [ev(1, 'u1')], rng: Random(8));
    await expectLater(
      openSyncBundle(file.bytes, expectedCompanyId: 'other'),
      throwsA(isA<SyncForeignCompanyException>()),
    );
    // وبالشركة الصحيحة يفتح عادي — الفحص بحمول المتلقي لا بالحزمة.
    final opened = await openSyncBundle(file.bytes, expectedCompanyId: 'main');
    expect(opened.header.companyId, 'main');
  });

  test('البناء يرفض صوتياً: فراغ وفجوة تسلسل وuuid فارغ', () async {
    await expectLater(
      buildSyncBundle(companyId: 'main', deviceId: 'D1', events: []),
      throwsA(isA<SyncBundleStructureException>()),
    );
    await expectLater(
      buildSyncBundle(
          companyId: 'main', deviceId: 'D1', events: [ev(1, 'u1'), ev(3, 'u3')]),
      throwsA(isA<SyncBundleStructureException>()),
    );
    await expectLater(
      buildSyncBundle(companyId: 'main', deviceId: 'D1', events: [ev(1, '')]),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('الرموز المفهرسة في السجل وخريطة الاستثناءات — عقد الفهرسة', () {
    expect(diqqahErrorCodeOf('DQ-1109'), isNotNull);
    expect(diqqahErrorCodeOf('DQ-1110'), isNotNull);
    expect(diqqahErrorCodeOf('DQ-1111'), isNotNull);
    expect(diqqahErrorCodeOf('DQ-1112'), isNotNull);
    expect(diqqahErrorCodeOf('DQ-1109')!.code, 'DQ-1109');
    expect(dqCodeForDomainError(SyncBundleEnvelopeException('x')), 'DQ-1109');
    expect(dqCodeForDomainError(SyncBundleTamperException('x')), 'DQ-1110');
    expect(dqCodeForDomainError(SyncBundleStructureException('x')), 'DQ-1111');
    expect(dqCodeForDomainError(SyncForeignCompanyException('x')), 'DQ-1112');
  });

  // ── البند ④ بذرة العقد النقي (موعده الموثق «مرتبط بداية د1» — س167) ──

  test('④ جهازان عدّلا المسودة نفسها قبل ترحيلها: آخر المرجعي يفوز وكلا الحدثين يبقى',
      () async {
    final streamA = [
      ev(1, 'a-create',
          deviceId: 'DESHT-01',
          action: 'created',
          payload: '{"uuid":"draft-abc","نوع":"مسودة بيع"}'),
      ev(2, 'a-edit',
          deviceId: 'DESHT-01',
          action: 'draft_edited',
          payload: '{"uuid":"draft-abc","لقطة":"تعديل جهاز أ"}'),
    ];
    final streamB = [
      ev(1, 'b-edit',
          deviceId: 'HATF-02',
          action: 'draft_edited',
          payload: '{"uuid":"draft-abc","لقطة":"تعديل هاتف ب"}'),
    ];
    final m = mergeSyncStreams([streamA, streamB]);
    expect(m.ignored, 0);
    expect(m.merged.map((e) => e.uuid).toList(),
        ['a-create', 'a-edit', 'b-edit'],
        reason: 'ترتيب المرابض يحاكي الترتيب المرجعي حتى د4');
    final winner = referenceOrderWinner(
        m.merged.where((e) => e.payloadJson.contains('draft-abc')));
    expect(winner.uuid, 'b-edit', reason: 'آخر حدث بالترتيب المرجعي يفوز F-135');
    expect(m.merged.where((e) => e.action == 'draft_edited').length, 2,
        reason: 'وكلا الحدثين يبقى في السجل — لا فقد لأي نسخة');
  });

  test('④ جهاز حذف المسودة وجهاز عدّلها: الحذف آخراً يفوز والتعديل باقٍ قابل للاسترجاع',
      () async {
    final streamA = [
      ev(1, 'x-create',
          deviceId: 'DESHT-01',
          action: 'created',
          payload: '{"uuid":"draft-xyz"}'),
      ev(2, 'x-edit',
          deviceId: 'DESHT-01',
          action: 'draft_edited',
          payload: '{"uuid":"draft-xyz","لقطة":"بعد التعديل"}'),
    ];
    final streamB = [
      ev(1, 'x-delete',
          deviceId: 'HATF-02',
          action: 'draft_deleted',
          payload: '{"uuid":"draft-xyz","حذف":true}'),
    ];
    final m = mergeSyncStreams([streamA, streamB]);
    final winner = referenceOrderWinner(
        m.merged.where((e) => e.payloadJson.contains('draft-xyz')));
    expect(winner.uuid, 'x-delete');
    expect(winner.action, 'draft_deleted');
    expect(m.merged.map((e) => e.uuid), contains('x-edit'),
        reason: 'المحتوى كله قابل للاسترجاع من السجل — الإلحاق لا الحذف');
  });

  test('④ ترحيلان متزامنان على المسودة نفسها: الحدثان باقيان والمكرر يُتجاهل',
      () async {
    final streamA = [
      ev(1, 'p-create',
          deviceId: 'DESHT-01',
          action: 'created',
          payload: '{"uuid":"draft-d"}'),
      ev(2, 'p-post-a',
          deviceId: 'DESHT-01',
          action: 'posted',
          payload: '{"uuid":"draft-d","ترحيل":"جهاز أ"}'),
    ];
    final streamB = [
      ev(1, 'p-post-b',
          deviceId: 'HATF-02',
          action: 'posted',
          payload: '{"uuid":"draft-d","ترحيل":"هاتف ب"}'),
    ];
    final m = mergeSyncStreams([streamA, streamB]);
    expect(m.merged.where((e) => e.action == 'posted').map((e) => e.uuid),
        ['p-post-a', 'p-post-b'],
        reason: 'الترحيلان باقيان append-only والحسم بترتيب الخادم لا بفقد');
    final winner = referenceOrderWinner(
        m.merged.where((e) => e.payloadJson.contains('"uuid":"draft-d"')));
    expect(winner.uuid, 'p-post-b', reason: 'آخر المرجعي يفوز');
    // إعادة استيراد مرضي أ بالكامل (استيراد مزدوج): لا تكرار ولا فقد.
    final again = mergeSyncStreams([m.merged, streamA]);
    expect(again.ignored, 2, reason: 'مكرر س-23 بهدوء');
    expect(again.merged.length, m.merged.length);
  });

  // ── د3: الشركة الحاملة على كل صف — الترويسة والصفوف متوافقة حداً بحد ──

  test('د3 الجولة تحمل company_id بكل صف وتقرأ كما كُتبت', () async {
    final file = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: [ev(1, 'u1'), ev(2, 'u2', companyId: 'main')],
      rng: Random(11),
    );
    final opened = await openSyncBundle(file.bytes);
    expect(opened.events.map((e) => e.companyId), ['main', 'main']);
    expect(opened.header.companyId, 'main');
  });

  test('د3 البناء يرفض حدثاً بشركة لا تطابق ترويسة الحزمة', () async {
    await expectLater(
      buildSyncBundle(
        companyId: 'main',
        deviceId: 'D1',
        events: [ev(1, 'u1', companyId: 'other')],
      ),
      throwsA(isA<SyncBundleStructureException>()),
      reason: 'حزمة الشركة الواحدة لا تحمل غيرها — D-188',
    );
  });

  test('د3 صف موقّع بشركة لا تطابق ترويسة الحزمة — DQ-1111 عند الفك',
      () async {
    final blob = await craftBundle(
      header: baseHeader(),
      lines: [
        evLine(1, 'u1', companyId: 'main'),
        evLine(2, 'u2', companyId: 'other'),
      ],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('د3 سطر حدث بلا company_id — DQ-1111 (حقل ناقص)', () async {
    final line = jsonDecode(evLine(1, 'u1')) as Map<String, Object?>;
    line.remove('company_id');
    final blob = await craftBundle(
      header: baseHeader(lastSeq: 1, eventCount: 1),
      lines: [jsonEncode(line)],
    );
    await expectLater(
      openSyncBundle(blob),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });
}
