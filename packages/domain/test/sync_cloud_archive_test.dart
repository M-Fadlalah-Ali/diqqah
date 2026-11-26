import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات د5 — الأرشفة السحابية الدورية (F-137/م-31 — خارطة م4 §46
/// بكلمة المالك «تابع مع د5»): الإيقاع اليومي نص م-31 والاحتفاظ بآخر
/// 30 والتحصين «مسار الاستعادة واحد لا ثانٍ» نص معيار قبول د5.
void main() {
  final base = DateTime.utc(2026, 11, 19, 10, 0, 0);

  CloudArchiveRecord rec(int day, {int hour = 12, String dev = 'd1'}) =>
      CloudArchiveRecord(
        fileName: cloudArchiveFileName(
            deviceId: dev, atUtc: DateTime.utc(2026, 11, day, hour)),
        atUtc: DateTime.utc(2026, 11, day, hour),
        sizeBytes: 1000 + day,
        sha256Hex: 'sha-day$day-h$hour-d$dev',
        deviceId: dev,
      );

  group('التسمية والتحليل — ترميز D-207 بمعرف النوع المميز', () {
    test('الاسم القياسي diqqah-cloud-<device>-<UTC>.dqk يُحلَّل كما كُتب', () {
      final at = DateTime.utc(2026, 11, 19, 8, 5, 9);
      final name = cloudArchiveFileName(deviceId: '0aa2f1c4-99x', atUtc: at);
      expect(name, 'diqqah-cloud-0aa2f1c4-20261119T080509Z.dqk');
      final parsed = parseCloudArchiveFileName(name)!;
      expect(parsed.deviceTag, '0aa2f1c4');
      expect(parsed.atUtc, at);
    });

    test('معرف الجهاز يُطهَّر بمحارف الترميز الآمنة حصراً', () {
      final name = cloudArchiveFileName(
          deviceId: 'UUID-بأحرف غريبة!!', atUtc: base);
      final parsed = parseCloudArchiveFileName(name)!;
      expect(RegExp(r'^[a-z0-9]{1,16}$').hasMatch(parsed.deviceTag), isTrue);
    });

    test('أسماء المجدولة المحلية واليدوية ليست أرشيفاً سحابياً', () {
      expect(
          parseCloudArchiveFileName('diqqah-d-0aa2f1c4-20261119T080509Z.dqk'),
          isNull,
          reason: 'النوع d من المجدولة المحلية لا cloud');
      expect(
          parseCloudArchiveFileName('diqqah-backup-x.diqqah'), isNull);
      expect(parseCloudArchiveFileName('diqqah-cloud-x-20261119T080509Z.zip'),
          isNull);
    });

    test('الثوابت النصية: الاحتفاظ 30 والصيغة الجارية للنسخة v2', () {
      expect(cloudArchiveRetention, 30);
      expect(BackupCipher.formatVersion, 2);
      expect(cloudArchiveFileExtension, 'dqk');
    });
  });

  group('الاستحقاق اليومي نص م-31 بنمط اللحاق (ق-ن6)', () {
    final local = DateTime(2026, 11, 19, 13, 0); // يوم محلي كامل
    test('بلا اتصال: تأجيل موثق نص F-137 — لا استحقاق الآن', () {
      expect(
        cloudArchiveDue(
            nowUtc: base,
            nowLocal: local,
            lastSuccessUtc: null,
            connectivityAvailable: false),
        isFalse,
      );
    });

    test('أول تشغيل بلا نجاح سابق وباتصال: مستحق', () {
      expect(
        cloudArchiveDue(
            nowUtc: base,
            nowLocal: local,
            lastSuccessUtc: null,
            connectivityAvailable: true),
        isTrue,
      );
    });

    test('نجاح داخل اليوم المحلي الجاري: غير مستحق — اليومية حرفاً', () {
      final today = DateTime.utc(2026, 11, 19, 6, 30);
      expect(
        cloudArchiveDue(
            nowUtc: base,
            nowLocal: local,
            lastSuccessUtc: today,
            connectivityAvailable: true),
        isFalse,
      );
    });

    test('نجاح قبل بداية اليوم المحلي الجاري: مستحق', () {
      final yesterday = DateTime.utc(2026, 11, 18, 23, 59);
      expect(
        cloudArchiveDue(
            nowUtc: base,
            nowLocal: local,
            lastSuccessUtc: yesterday,
            connectivityAvailable: true),
        isTrue,
      );
    });

    test('انحراف ساعة للامام (نجاح مستقبلي) لا يستحق ولا يتراجع', () {
      final future = DateTime.utc(2026, 11, 19, 23, 0);
      expect(
        cloudArchiveDue(
            nowUtc: base,
            nowLocal: local,
            lastSuccessUtc: future,
            connectivityAvailable: true),
        isFalse,
      );
    });
  });

  group('الكتالوج السحابي — الصياغة والإسقاط الآمن', () {
    test('جولة JSON بترتيب المفاتيح الثابت — الأحدث أولاً', () {
      final reg = CloudArchiveRegistry(records: [rec(10), rec(15), rec(12)]);
      final restored = CloudArchiveRegistry.fromJson(reg.toJson());
      expect(restored.records, hasLength(3));
      expect(restored.newestFirst.map((r) => r.atUtc.day).toList(),
          [15, 12, 10]);
      expect(restored.latestUtc!.day, 15);
    });

    test('الإضافة تستبدل بملف مطابق لا تُكرر', () {
      final reg = CloudArchiveRegistry()..add(rec(10));
      reg.add(CloudArchiveRecord(
        fileName: rec(10).fileName,
        atUtc: rec(10).atUtc,
        sizeBytes: 9999,
        sha256Hex: 'sha-new',
        deviceId: rec(10).deviceId,
      ));
      expect(reg.records, hasLength(1));
      expect(reg.records.single.sizeBytes, 9999);
    });

    test('الكتالوج الفاسد يعود فارغاً — قابل لإعادة البناء من قائمة '
        'الخادم بنمط ق-ن5 (ولا أمناً فيه فلا فشل مقفل)', () {
      expect(CloudArchiveRegistry.fromJson('نص ليس JSON').records, isEmpty);
      expect(
          CloudArchiveRegistry.fromJson('{"records": [{"file": 5}]}').records,
          isEmpty);
    });

    test('صف بلا تاريخ UTC أو ببصمة فارغة يُسقط لا يُخمَّد', () {
      final bad = '{"records": ['
          '{"file":"a.dqk","at":"2026-11-19T10:00:00.000Z","size":1,'
          '"sha256":"","device":"d1"}]}';
      expect(CloudArchiveRegistry.fromJson(bad).records, isEmpty);
    });
  });

  group('خطة التقليم نص م-31 — آخر 30 نسخة', () {
    test('ثلاثون نسخة أو أقل: لا خطة', () {
      expect(planCloudArchivePrune(
          [for (var d = 1; d <= 30; d++) rec(d)]), isEmpty);
      expect(planCloudArchivePrune([rec(1)]), isEmpty);
    });

    test('ما تجاوز الثلاثين بالأقدم أولاً — والثلاثون الأحدث سليمة', () {
      final records = [for (var d = 1; d <= 35; d++) rec(d)];
      final plan = planCloudArchivePrune(records);
      expect(plan, hasLength(5));
      expect(plan.map((r) => r.atUtc.day).toList(), [1, 2, 3, 4, 5],
          reason: 'الأقدم أولاً لترتيب الحذف');
      final keep = records
          .map((r) => r.fileName)
          .toSet()
          .difference(plan.map((r) => r.fileName).toSet());
      expect(keep, hasLength(30));
    });
  });

  group('التحصين «مسار واحد لا ثانٍ» — بايتات مرشحة للرفع (DQ-1118)', () {
    test('نسخة مشفرة قياسية بإصدارها الجاري تجتاز — بنفس مُعرِّف بوابة '
        'الاستعادة F-013', () async {
      final cipher = BackupCipher();
      final payload = await cipher.encrypt([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(BackupCipher.identify(payload), BackupKind.encrypted);
      expect(BackupCipher.encryptedVersion(payload),
          BackupCipher.formatVersion);
      validateCloudArchivePayload(payload);
    });

    test('قاعدة SQLite خام تُرفض — لا مسار نصي خام للسحابة', () {
      final plain = 'SQLite format 3\0'.codeUnits;
      expect(
        () => validateCloudArchivePayload(plain),
        throwsA(isA<CloudArchivePayloadException>()
            .having((e) => e.toString(), 'msg', contains('DQ-1118'))),
      );
    });

    test('بايتات عشوائية وقصيرة تُرفض', () {
      expect(() => validateCloudArchivePayload([9, 9, 9]),
          throwsA(isA<CloudArchivePayloadException>()));
      expect(
          () => validateCloudArchivePayload(
              'لا-حزمة-ولا-نسخة'.codeUnits),
          throwsA(isA<CloudArchivePayloadException>()));
    });

    test('نسخة مشفرة بإصدار قديم (v1 بكلمة المرور) تُرفض — الصيغة '
        'الجارية حصراً نص التحصين', () {
      final legacy = [...BackupCipher.legacyMagic, 1, 9, 9, 9];
      expect(() => validateCloudArchivePayload(legacy),
          throwsA(isA<CloudArchivePayloadException>()));
    });

    test('الرمز مفهرس بالسجل وخريطة الاستثناءات — عقد الفهرسة', () {
      final code = dqCodeForDomainError(
          const CloudArchivePayloadException('x'));
      expect(code, 'DQ-1118');
      final entry = diqqahErrorCodeOf('DQ-1118')!;
      expect(entry.title, 'الأرشيف ليس نسخة قياسية مشفرة');
      // ولا تكرار بالسجل كله
      expect(
          diqqahErrorCodes.where((e) => e.code == 'DQ-1118'), hasLength(1));
    });
  });
}
