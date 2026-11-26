// الحمل الكامل بمستخدمي 15–20 — N-008/D-021 (د6 — س175 — الاستيعاب
// الواجهي والأحمال الختامية بنص خارطة م4 §46 ومعيار قبولها «معيار
// الجاهزية الكامل نص §5»).
//
// **الشطر الآلي الموثق**: محاكاة نقية حصراً (F-010 — بلا Flutter ولا
// Drift ولا شبكة) لطرف المزامنة كاملاً بأعلى نطاق الموثق: عشرون
// مستخدماً على عشرين جهازاً (الحد الأعلى نص N-008 حرفاً) يولّد كل
// منهم مجرى أحداث مرقّماً ويصدّره بحزمة د1 الموقعة المشفرة،
// والاستقبال بمحرك الاستيراد د2، والدمج بالعقد النقي د1 (البند ④
// mergeSyncStreams) وقاعدة الحل F-135 على التعارض — والقياس
// بالساعة داخل الحافظة بميزانية سخية تحمي الجولة من رشح CI.
//
// **الحد الصادق عرف D-211**: القياس الجهازي الحقيقي (الضغط على أجهزة
// والانقطاع في منتصف الدورة وس-25 على خادم حي) بيد المالك بتصديق
// مكتوب عند بوابة الإصدار — لا هنا؛ وهذه الحافظة تشهد سلامة الأنبوب
// وترتيبه المرجعي وعدم فقد أي نسخة تحت الحمل الكامل حصراً.
library;

import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// نطاق الحمل الكامل نص N-008 حرفاً: 15–20 مستخدماً — والتنفيذ
/// بالحد الأعلى عشرين فما يمر على العشرين يمر على دونها.
const int kFullLoadUsers = 20;

/// أحداث كل مستخدم — حجم لفتة واقعية معقولة (فاتورة وسند ومتابعة
/// كل ثلاثين حدثاً) بمجموع 600 حدث للجولة الكاملة.
const int kEventsPerUser = 30;

/// ميزانية الوقت بالثواني — سخية لتباين CI (والسقف النظامي 120ث
/// بdart_test.yaml): الأنبوب كاملاً تحت ميزانية واحدة فالانكسار
/// البنيوي يُرفض قبل القياس أصلاً.
const int kPipelineBudgetSeconds = 90;

/// لقطة حدث واقعية — حقل كامل بما تحمله د3 من شركة، والحمولة JSON
/// عربية نمط المستندات.
SyncEvent loadEvent({
  required int seq,
  required String uuid,
  required String deviceId,
  required int userId,
  String entityType = 'move',
  String action = 'posted',
}) =>
    SyncEvent(
      seq: seq,
      uuid: uuid,
      eventAt: 1763550000 + seq,
      userId: userId,
      deviceId: deviceId,
      entityType: entityType,
      entityId: seq,
      action: action,
      companyId: kDefaultCompanyId,
      payloadJson: jsonEncode({
        'type': entityType,
        'number': '2026/$userId/$seq',
        'device': deviceId,
        'note': 'حدث الحمل الكامل للمستخدم $userId تسلسل $seq',
      }),
    );

/// مجرى مستخدم واحد — التسلسل متصل 1..N بجهازه ومعرفه.
List<SyncEvent> userStream(int userId) => [
      for (var i = 1; i <= kEventsPerUser; i++)
        loadEvent(
          seq: i,
          uuid: 'load-u$userId-s$i',
          deviceId: 'LOAD-D$userId',
          userId: userId,
        ),
    ];

void main() {
  test('N-008/D-021: الحمل الكامل بمستخدمي 15–20 — عشرون مستخدماً '
      'يصدّرون ويُستقبل ويُدمج بلا فقد ولا كسر ترتيب وبضمن الميزانية',
      () async {
    final clock = Stopwatch()..start();

    // 1) الإرسال: كل مستخدم يصدّر مجراه بحزمة د1 موقعة مشفرة —
    //    بذرة لكل جهاز فالحتمية كاملة وقابلة لإعادة الإنتاج.
    final perDevice = <int, List<SyncBundleFile>>{};
    for (var u = 1; u <= kFullLoadUsers; u++) {
      final bundles = await exportSyncFileBundles(
        companyId: kDefaultCompanyId,
        deviceId: 'LOAD-D$u',
        events: userStream(u),
        exportedAt: DateTime(2026, 11, 19, 10, u),
        rng: Random(20261100 + u),
      );
      expect(bundles, hasLength(1),
          reason: 'ثلاثون حدثاً صغيرة تتسع ملفاً واحداً للجهاز $u');
      perDevice[u] = bundles;
    }
    final exportSeconds = clock.elapsedMilliseconds / 1000;
    expect(exportSeconds, lessThan(kPipelineBudgetSeconds.toDouble()),
        reason: 'إرسال العشرين كله تحت الميزانية');

    // 2) الاستقبال: الخادم يستورد كل حزمة بمحرك د2 — التوقيع
    //    والغلاف والبنية تُحسم هنا لكل جهاز.
    final received = <int, List<SyncEvent>>{};
    for (var u = 1; u <= kFullLoadUsers; u++) {
      final imported = await importSyncFileParts(
        parts: [
          for (final b in perDevice[u]!)
            SyncFilePart(filename: b.filename, bytes: b.bytes),
        ],
        expectedCompanyId: kDefaultCompanyId,
      );
      expect(imported.deviceId, 'LOAD-D$u');
      expect(imported.firstSeq, 1);
      expect(imported.lastSeq, kEventsPerUser);
      received[u] = imported.events;
    }

    // 3) الدمج بالعقد النقي (البند ④): الستّمائة بلا فقد ولا تكرار
    //    — وكل جهاز يحفظ ترتيبه المرجعي 1..30 داخل المجرى المدموج.
    final merged = mergeSyncStreams([
      for (var u = 1; u <= kFullLoadUsers; u++) received[u]!,
    ]);
    expect(merged.ignored, 0,
        reason: 'لا uuid مشتركة بين الأجهزة فلا شيء يُهمل بهدوء');
    expect(merged.merged, hasLength(kFullLoadUsers * kEventsPerUser),
        reason: 'لا فقد لأي نسخة — append-only نص F-135');
    for (var u = 1; u <= kFullLoadUsers; u++) {
      final deviceEvents =
          merged.merged.where((e) => e.deviceId == 'LOAD-D$u').toList();
      expect([for (final e in deviceEvents) e.seq],
          [for (var i = 1; i <= kEventsPerUser; i++) i],
          reason: 'ترتيب الجهاز $u المرجعي محفوظ داخل الدمج');
    }
    expect(
        merged.merged.every((e) => e.companyId == kDefaultCompanyId),
        isTrue,
        reason: 'العزل الشركةي على كل حدث (د3/D-188)');

    // 4) الجسر اليدوي فوق الحمل ذاته: مجرى كامل يمر بالتقسيم
    //    والاستيراد — الجسر يخدم ما يخدمه الخادم (مجرى جهاز واحد
    //    كاملاً — التسلسل متصل داخل الجهاز حصراً والدمج فوق المرابض).
    final bridgeBundles = await exportSyncFileBundles(
      companyId: kDefaultCompanyId,
      deviceId: 'LOAD-D1',
      events: userStream(1),
      exportedAt: DateTime(2026, 11, 19, 11, 0),
      rng: Random(77),
      maxPartBytes: 3200,
    );
    expect(bridgeBundles.length, greaterThan(1),
        reason: 'الحد الصغير يقسم مجرى الحمل أجزاءً مرقمة');
    final bridgeImported = await importSyncFileParts(
      parts: [
        for (final b in bridgeBundles)
          SyncFilePart(filename: b.filename, bytes: b.bytes),
      ],
      expectedCompanyId: kDefaultCompanyId,
    );
    expect(bridgeImported.wasSplit, isTrue);
    expect(bridgeImported.events.map((e) => e.uuid),
        userStream(1).map((e) => e.uuid),
        reason: 'الجسر يعيد مجرى الحمل حرفاً');

    final totalSeconds = clock.elapsedMilliseconds / 1000;
    expect(totalSeconds, lessThan(kPipelineBudgetSeconds.toDouble()),
        reason: 'الأنبوب كاملاً (إرسال واستقبال ودمج وجسر) تحت الميزانية');
  });

  test('N-008/D-021: التعارض تحت الحمل بقاعدة F-135 — آخر حدث بالترتيب '
      'المرجعي يفوز وكلا النسختين تبقى في السجل', () {
    // مستخدمان كتبا على الكيان ذاته أثناء الحمل — نسختان uuid مختلفتان.
    final a = loadEvent(
        seq: 1, uuid: 'conflict-a', deviceId: 'LOAD-D1', userId: 1);
    final b = loadEvent(
        seq: 1,
        uuid: 'conflict-b',
        deviceId: 'LOAD-D2',
        userId: 2,
        action: 'edited');
    final streamA = [a, for (var i = 2; i <= 5; i++) loadEvent(seq: i, uuid: 'a$i', deviceId: 'LOAD-D1', userId: 1)];
    final streamB = [b, for (var i = 2; i <= 5; i++) loadEvent(seq: i, uuid: 'b$i', deviceId: 'LOAD-D2', userId: 2)];
    final merged = mergeSyncStreams([streamA, streamB]);
    expect(merged.ignored, 0);
    expect(merged.merged, hasLength(10),
        reason: 'كلا الحدثين يبقى — لا فقد لأي نسخة نص F-135');
    // فائز الكيان بالترتيب المرجعي = الأخير، والحسم بعقد القاعدة.
    final winner = referenceOrderWinner(
        merged.merged.where((e) => e.entityType == 'move' && e.entityId == 1));
    expect(winner.uuid, 'conflict-b',
        reason: 'آخر حدث بالترتيب المرجعي يفوز — لا اجتهاد لحظي');
  });

  test('N-008/D-021: عزل الشركة يحرس الحمل — حزمة شركة غريبة تُرفض '
      'بالاستقبال (DQ-1111)', () async {
    final foreign = await exportSyncFileBundles(
      companyId: 'branch-x',
      deviceId: 'LOAD-FOREIGN',
      events: [
        SyncEvent(
          seq: 1,
          uuid: 'foreign-1',
          eventAt: 1763550000,
          userId: null,
          deviceId: 'LOAD-FOREIGN',
          entityType: 'move',
          entityId: 1,
          action: 'posted',
          companyId: 'branch-x',
          payloadJson: 'لقطة شركة أخرى',
        ),
      ],
      rng: Random(20261119),
    );
    expect(
      () => importSyncFileParts(
        parts: [
          SyncFilePart(
              filename: foreign.single.filename, bytes: foreign.single.bytes),
        ],
        expectedCompanyId: kDefaultCompanyId,
      ),
      throwsA(isA<SyncForeignCompanyException>()),
      reason: 'الشركة الغريبة رفض مفهرس نص د3 — لا دمج صامت',
    );
  });
}
