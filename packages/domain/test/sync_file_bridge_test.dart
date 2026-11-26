// اختبارات د2 (س173 — المهايئ الثالث: الملف المشفر اليدوي F-133 —
// بكلمة المالك الحرفية «تابع ب: د2»): الجسر اليدوي س-23 والمزوّد
// الثالث بتنفيذ واحد يخدم الاثنين — تقسيم §10 عند 50MB بأجزاء مرقمة
// والاستيراد كاملاً بالترتيب والرفض المفهرس (بصمة/uuid/seq/شركة) —
// فوق حزمة د1 حرفاً فكل ملف حزمة موقعة كاملة لا صيغة جديدة.
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// مصنع حدث قياسي — لقطة صغيرة لكن حقولها كاملة (نمط sync_bundle_test).
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
    payloadJson: payload ?? 'لقطة حدث $seq عربية للجسر',
  );
}

/// يولّد أحداث إرسال متصلة التسلسل بأزواج uuid فريدة — ومعرف الجهاز
/// بالـuuid فلا تصادم بين مولّدَي جهازين (الواقع uuid عالمية).
List<SyncEvent> genEvents(int from, int count, {String? deviceId}) =>
    [
      for (var i = 0; i < count; i++)
        ev(from + i, '${deviceId ?? 'DESHT-01'}-$from-${i + 1}',
            deviceId: deviceId ?? 'DESHT-01'),
    ];

void main() {
  test('الإرسال المتسع ملف واحد بلا علامة أجزاء — واسمه §10 القياسي', () async {
    final bundles = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 6),
      exportedAt: DateTime(2026, 11, 19, 14, 35),
      rng: Random(20261119),
    );
    expect(bundles, hasLength(1),
        reason: 'ستة أحداث صغيرة تتسع للحد الافتراضي 50MB');
    expect(bundles.single.filename,
        'diqqah-sync-20261119-1435-DESHT-01-6.dsync',
        reason: 'بلا علامة أجزاء — الحزمة الواحدة اسمها القياسي حرفاً');
    final opened = await openSyncBundle(bundles.single.bytes);
    expect(opened.events.map((e) => e.uuid), genEvents(1, 6).map((e) => e.uuid));
    expect(opened.header.lastSeq, 6);
  });

  test('التقسيم نص §10: أجزاء مرقمة بأسمائها وكل جزء حزمة سليمة مستقلة '
      'والاستيراد الكامل يعيد الأصل حرفاً', () async {
    final source = genEvents(1, 30);
    final bundles = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: source,
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    expect(bundles.length, greaterThan(1),
        reason: 'الحد الصغير يقسم الأحداث الثلاثين أجزاءً');
    final n = bundles.length;
    for (var i = 0; i < n; i++) {
      expect(bundles[i].filename, endsWith('.part${i + 1}of$n.dsync'),
          reason: 'علامة part i/N بالاسم نص §10');
      expect(bundles[i].filename, contains('-30.'),
          reason: 'الأساس يحمل آخر تسلسل للإرسال كله لا للجزء');
      // كل جزء حزمة كاملة تفتح مستقلة بمحرك د1 — توقيع وغلاف وبنية.
      final opened = await openSyncBundle(bundles[i].bytes);
      expect(opened.header.companyId, 'main');
      expect(opened.header.deviceId, 'DESHT-01');
      expect(opened.events, isNotEmpty);
    }
    // والاستيراد كاملاً بالترتيب يعيد الأصل حرفاً.
    final imported = await importSyncFileParts(
      parts: [
        for (final b in bundles) SyncFilePart(filename: b.filename, bytes: b.bytes),
      ],
    );
    expect(imported.wasSplit, isTrue);
    expect(imported.partCount, n);
    expect(imported.events.map((e) => e.uuid), source.map((e) => e.uuid));
    expect(imported.events.map((e) => e.payloadJson),
        source.map((e) => e.payloadJson));
    expect(imported.firstSeq, 1);
    expect(imported.lastSeq, 30);
    expect(imported.companyId, 'main');
    expect(imported.deviceId, 'DESHT-01');
  });

  test('ثوابت §10 البايتية: الحد 50MB والغلاف 53 بايتاً موثقان حرفاً', () {
    expect(syncFilePartLimitBytes, 50 * 1024 * 1024);
    expect(syncFilePartLimitBytes, 52428800);
    // ترويسة DIQQSYNC ثمانية + إصدار بايتة + ملح 16 + نونس 12 + وسم 16
    expect(utf8.encode('DIQQSYNC'), hasLength(8));
    expect(8 + 1 + 16 + 12 + 16, 53);
  });

  test('الاستيراد الناقص مرفوض DQ-1115 — الحزمة المقسمة تستورد كاملة', () async {
    final bundles = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 12),
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    expect(bundles.length, greaterThan(1));
    final parts = [
      for (final b in bundles) SyncFilePart(filename: b.filename, bytes: b.bytes),
    ];
    await expectLater(
      importSyncFileParts(parts: parts.sublist(0, parts.length - 1)),
      throwsA(isA<SyncFilePartsException>()),
    );
    // والرمز المفهرس في السلطة الموحدة DQ-1115.
    try {
      await importSyncFileParts(parts: parts.sublist(0, parts.length - 1));
      fail('لا بُد من الرفض');
    } on SyncFilePartsException catch (e) {
      expect(dqCodeForDomainError(e), 'DQ-1115');
    }
  });

  test('رقم الجزء المكرر مرفوض — كل رقم مرة واحدة 1..N', () async {
    final bundles = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 12),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    final n = bundles.length;
    final dup = SyncFilePart(
      filename: bundles.first.filename,
      bytes: bundles.first.bytes,
    );
    final second = SyncFilePart(
      filename: bundles[1 % n].filename,
      bytes: bundles[1 % n].bytes,
    );
    await expectLater(
      importSyncFileParts(parts: [dup, second]),
      throwsA(isA<SyncFilePartsException>()),
    );
  });

  test('خليط الأجزاء والحزم المفردة مرفوض', () async {
    final bundles = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 12),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    final lone = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-02',
      events: genEvents(100, 2),
      rng: Random(20261119),
    );
    await expectLater(
      importSyncFileParts(parts: [
        SyncFilePart(filename: bundles.first.filename, bytes: bundles.first.bytes),
        SyncFilePart(filename: lone.single.filename, bytes: lone.single.bytes),
      ]),
      throwsA(isA<SyncFilePartsException>()),
    );
  });

  test('أجزاء من أساسين مختلفين مرفوضة — الأجزاء شطر إرسال واحد', () async {
    final a = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 12),
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    final b = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(101, 12),
      exportedAt: DateTime(2026, 11, 19, 9, 6),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    await expectLater(
      importSyncFileParts(parts: [
        SyncFilePart(filename: a.first.filename, bytes: a.first.bytes),
        SyncFilePart(filename: b.first.filename, bytes: b.first.bytes),
      ]),
      throwsA(isA<SyncFilePartsException>()),
    );
  });

  test('تضارب الجهاز بين الأجزاء مرفوض حتى بتسلسل متلوٍ — الأجزاء جهاز واحد', () async {
    // جزءان حقيقيان من جهازين مختلفين بنفس الشركة وتسلسل متلوٍ،
    // وأسماؤهما مصنوعة بعلامات واحدة — الفاحص يرفض التضارب.
    final first = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 5),
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
    );
    final second = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-02',
      events: genEvents(6, 5),
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
    );
    const base = 'diqqah-sync-20261119-0905-FAKE-10';
    await expectLater(
      importSyncFileParts(parts: [
        SyncFilePart(
            filename: '$base.part1of2.dsync', bytes: first.bytes),
        SyncFilePart(
            filename: '$base.part2of2.dsync', bytes: second.bytes),
      ]),
      throwsA(isA<SyncFilePartsException>()),
    );
  });

  test('انكسار التلوّي بين الأجزاء مرفوض — التجاور بلا فجوة نص §10', () async {
    final first = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 5),
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
    );
    final second = await buildSyncBundle(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(20, 5),
      rng: Random(20261119),
    );
    const base = 'diqqah-sync-20261119-0905-DESHT-01';
    await expectLater(
      importSyncFileParts(parts: [
        SyncFilePart(filename: '$base.part1of2.dsync', bytes: first.bytes),
        SyncFilePart(filename: '$base.part2of2.dsync', bytes: second.bytes),
      ]),
      throwsA(isA<SyncFilePartsException>()),
    );
  });

  test('حزمة من شركة أخرى مرفوضة على الجسر — DQ-1112 قبل أي إلحاق', () async {
    final foreign = await buildSyncBundle(
      companyId: 'other-co',
      deviceId: 'DESHT-01',
      events: [
        ev(1, 'fx1', companyId: 'other-co'),
        ev(2, 'fx2', companyId: 'other-co'),
      ],
      rng: Random(20261119),
    );
    await expectLater(
      importSyncFileParts(
        parts: [SyncFilePart(filename: foreign.filename, bytes: foreign.bytes)],
        expectedCompanyId: 'main',
      ),
      throwsA(isA<SyncForeignCompanyException>()),
    );
    // وعلى أجزاء مقسمة كذلك — الفحص لكل جزء نص §10.
    final foreignParts = await exportSyncFileBundles(
      companyId: 'other-co',
      deviceId: 'DESHT-01',
      events: [
        ev(1, 'fy1', companyId: 'other-co'),
        ev(2, 'fy2', companyId: 'other-co'),
        ev(3, 'fy3', companyId: 'other-co'),
        ev(4, 'fy4', companyId: 'other-co'),
        ev(5, 'fy5', companyId: 'other-co'),
        ev(6, 'fy6', companyId: 'other-co'),
      ],
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    await expectLater(
      importSyncFileParts(
        parts: [
          for (final b in foreignParts)
            SyncFilePart(filename: b.filename, bytes: b.bytes),
        ],
        expectedCompanyId: 'main',
      ),
      throwsA(isA<SyncForeignCompanyException>()),
    );
  });

  test('حدث واحد أعلى من ميزانية الجزء مرفوض صوتاً — الحدث لا يُشطر أبداً', () async {
    final huge = [
      ev(1, 'big1', payload: 'س' * 1200),
      ev(2, 'big2'),
    ];
    await expectLater(
      exportSyncFileBundles(
        companyId: 'main',
        deviceId: 'DESHT-01',
        events: huge,
        rng: Random(20261119),
        maxPartBytes: 2560,
      ),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('حد التقسيم دون العتبة المشروعة مرفوض صوتاً', () async {
    await expectLater(
      exportSyncFileBundles(
        companyId: 'main',
        deviceId: 'DESHT-01',
        events: genEvents(1, 2),
        rng: Random(20261119),
        maxPartBytes: 100,
      ),
      throwsA(isA<SyncBundleStructureException>()),
    );
  });

  test('حزم مفردة متعددة بلا علامات تُستورد مستقلة وتدمج بترتيب الملفات', () async {
    final a = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: genEvents(1, 4),
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
    );
    final b = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-02',
      events: genEvents(1, 3, deviceId: 'DESHT-02'),
      exportedAt: DateTime(2026, 11, 19, 9, 6),
      rng: Random(20261119),
    );
    final imported = await importSyncFileParts(parts: [
      SyncFilePart(filename: a.single.filename, bytes: a.single.bytes),
      SyncFilePart(filename: b.single.filename, bytes: b.single.bytes),
    ]);
    expect(imported.wasSplit, isFalse);
    expect(imported.partCount, 2, reason: 'عدد الملفات المستقلة');
    expect(imported.events, hasLength(7));
    expect(imported.firstSeq, 1);
    expect(imported.lastSeq, 4, reason: 'أعلى تسلسل بالمدموج');
  });

  test('س-23 كاملاً على النسختين: استيراد يلحق الفريد والمكرر يُعدّ بهدوء '
      'والاتجاهان سليمان', () async {
    // جهاز أ يرسل ثلاثين حدثاً مقسمة.
    final source = genEvents(1, 30, deviceId: 'DESHT-A');
    final bundles = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-A',
      events: source,
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    final parts = [
      for (final b in bundles) SyncFilePart(filename: b.filename, bytes: b.bytes),
    ];

    // الجهاز ب يستورد أول مرة: الكل فريد يُلحق append-only.
    final firstImport = await importSyncFileParts(parts: parts);
    final bKnown = <String>{};
    final firstSplit =
        filterKnownSyncEvents(firstImport.events, bKnown);
    expect(firstSplit.fresh, hasLength(30));
    expect(firstSplit.ignored, 0);
    for (final e in firstSplit.fresh) {
      bKnown.add(e.uuid);
    }

    // وإعادة الاستيراد ذاته: الكل مكرر يُعدّ بهدوء — لا دمج مزدوج.
    final secondImport = await importSyncFileParts(parts: parts);
    final secondSplit =
        filterKnownSyncEvents(secondImport.events, bKnown);
    expect(secondSplit.fresh, isEmpty);
    expect(secondSplit.ignored, 30);

    // والجهاز أ يستورد إرسال ب (خمسة أحداث محلية لب): فريدة عنده كلها.
    final bOwn = genEvents(1, 5, deviceId: 'DESHT-B');
    final bBundle = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-B',
      events: bOwn,
      rng: Random(20261119),
    );
    final aImport = await importSyncFileParts(
      parts: [
        SyncFilePart(
            filename: bBundle.single.filename, bytes: bBundle.single.bytes),
      ],
    );
    final aKnown = source.map((e) => e.uuid).toSet();
    final aSplit = filterKnownSyncEvents(aImport.events, aKnown);
    expect(aSplit.fresh, hasLength(5));
    expect(aSplit.ignored, 0);
    expect(aImport.deviceId, 'DESHT-B');
  });

  test('الاسم القياسي للأجزاء يطهّر معرف الجهاز ويحمل آخر تسلسل للإرسال كله', () async {
    final bundles = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'مكتب الاستقبال/الأمين 01',
      events: genEvents(40, 10),
      exportedAt: DateTime(2026, 11, 19, 9, 5),
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    final n = bundles.length;
    expect(n, greaterThan(1));
    for (var i = 0; i < n; i++) {
      expect(bundles[i].filename,
          startsWith('diqqah-sync-20261119-0905-'),
          reason: 'الأساس القياسي بصمته الزمنية');
      expect(bundles[i].filename, endsWith('.part${i + 1}of$n.dsync'));
      expect(bundles[i].filename, contains('-49.'),
          reason: 'آخر seq للإرسال كله (49) بالأساس لا للجزء');
      expect(
        bundles[i].filename,
        isNot(contains(RegExp(r'[\u0600-\u06FF]'))),
        reason: 'التطهير لمحارف أسماء الملفات — العربي لا يدخل الاسم',
      );
    }
  });

  test('جزء واحد بحمولة حدية يمر — والحد الأدنى المشروع يمنع ميزانية سالبة', () async {
    // حد أدنى مشروع (2560): ميزانية موجبة تستوعب حدثاً قصيراً.
    final tiny = await exportSyncFileBundles(
      companyId: 'main',
      deviceId: 'DESHT-01',
      events: [ev(1, 't1', payload: 'ح')],
      rng: Random(20261119),
      maxPartBytes: 2560,
    );
    expect(tiny, hasLength(1));
    final opened = await openSyncBundle(tiny.single.bytes);
    expect(opened.events.single.uuid, 't1');
  });
}
