/// اختبار سياسة GFS النقية (تكليف 2026-11-13 — ق-ن3..ق-ن6، D-207):
/// التسمية والكتالوج والرتابة والتدوير وسقف الحصة واللحاق والتذكيران.
library;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:test/test.dart';

BackupCatalogEntry entry(
  BackupScheduleKind kind,
  DateTime at, {
  int size = 100,
  bool images = false,
  String file = '',
}) =>
    BackupCatalogEntry(
      fileName: file.isEmpty
          ? scheduledBackupFileName(
              kind: kind, deviceTag: 'a1b2c3d4', atUtc: at)
          : file,
      kind: kind,
      atUtc: at,
      sizeBytes: size,
      deviceTag: 'a1b2c3d4',
      includesImages: images,
      folderId: 'backups',
    );

void main() {
  group('التسمية D-207 — diqqah-<type>-<device>-<UTC>.dqk', () {
    test('الترميز والتحليل دورة كاملة', () {
      final at = DateTime.utc(2026, 11, 13, 10, 15, 30);
      final name = scheduledBackupFileName(
          kind: BackupScheduleKind.hourly,
          deviceTag: 'a1b2c3d4',
          atUtc: at);
      expect(name, 'diqqah-h-a1b2c3d4-20261113T101530Z.dqk');
      final parsed = parseScheduledBackupFileName(name);
      expect(parsed, isNotNull);
      expect(parsed!.kind, BackupScheduleKind.hourly);
      expect(parsed.deviceTag, 'a1b2c3d4');
      expect(parsed.atUtc, at);
    });

    test('كل رموز الأنواع مميزة متبادلة', () {
      final symbols = BackupScheduleKind.values.map((k) => k.symbol).toList();
      expect(symbols.toSet().length, symbols.length);
    });

    test('أسماء غير صالحة تُرفض (null لا استثناء)', () {
      expect(parseScheduledBackupFileName('diqqah-h-a1-20261113.dqk'), isNull);
      expect(parseScheduledBackupFileName('not-a-backup.txt'), isNull);
      expect(
          parseScheduledBackupFileName(
              'diqqah-h-a1b2c3d4-20261131T101530Z.dqk'),
          isNull); // يوم مستحيل بالختم
      expect(parseScheduledBackupFileName('diqqah-x-a1b2c3d4-20261113T101530Z.dqk'),
          isNull); // رمز مجهول
    });

    test('رمز الجهاز: ثمانية محارف نظيفة فقط', () {
      expect(backupDeviceTag('123e4567-e89b-12d3-a456-426614174000'),
          '123e4567');
      expect(backupDeviceTag('AB-99'), 'ab99');
    });
  });

  group('الكتالوج الجانبي (ق-ن5)', () {
    test('JSON دورة كاملة', () {
      final c = BackupCatalog();
      c.addEntry(entry(BackupScheduleKind.daily,
          DateTime.utc(2026, 11, 13, 4, 0, 0)));
      c.recordSuccess(BackupScheduleKind.daily,
          DateTime.utc(2026, 11, 13, 4, 0, 0));
      final back = BackupCatalog.fromJson(c.toJson());
      expect(back.entries.length, 1);
      expect(back.lastSuccess[BackupScheduleKind.daily],
          DateTime.utc(2026, 11, 13, 4, 0, 0));
    });

    test('نص فاسد يعود كتالوجاً فارغاً (المسح يعيد البناء)', () {
      final c = BackupCatalog.fromJson('{ لا json');
      expect(c.entries, isEmpty);
    });

    test('صف JSON بنوع مجهول يُسقط صراحة', () {
      const text =
          '{"version":1,"lastSuccess":{},"entries":[{"file":"x","kind":"zz",'
          '"at":"2026-11-13T00:00:00Z","device":"","folder":"b"}]}';
      expect(BackupCatalog.fromJson(text).entries, isEmpty);
    });

    test('حارس الرتابة (تكليف §8-2): النجاح لا يتراجع أبدياً', () {
      final c = BackupCatalog();
      final newer = DateTime.utc(2026, 11, 13, 12);
      final older = DateTime.utc(2026, 11, 12, 12);
      c.recordSuccess(BackupScheduleKind.daily, newer);
      c.recordSuccess(BackupScheduleKind.daily, older);
      expect(c.lastSuccess[BackupScheduleKind.daily], newer);
    });

    test('latestAnyUtc أقصى كل الأنواع — مقياس الثلاثين يوماً', () {
      final c = BackupCatalog();
      c.recordSuccess(BackupScheduleKind.hourly,
          DateTime.utc(2026, 11, 12, 8));
      c.addEntry(entry(
          BackupScheduleKind.monthly, DateTime.utc(2026, 11, 13, 6)));
      expect(c.latestAnyUtc(), DateTime.utc(2026, 11, 13, 6));
    });
  });

  group('خطة التدوير (ق-ن4: لا حذف إلا بعد نجاح وتحقق الجديدة)', () {
    test('16 ساعية → الأقدم خارج الحد يُحذف', () {
      final ofKind = [
        for (var i = 0; i < 16; i++)
          entry(BackupScheduleKind.hourly,
              DateTime.utc(2026, 11, 13, 15 - i)),
      ]..sort((a, b) => b.atUtc.compareTo(a.atUtc)); // الأحدث أولاً.
      final plan = planRotation(BackupScheduleKind.hourly, ofKind);
      expect(plan.length, 1);
      // 16 نسخة اليوم ذاته 15:00..00:00 → الأقدم (00:00) خارج حد 15.
      expect(plan.single.atUtc, DateTime.utc(2026, 11, 13, 0));
    });

    test('السنوية واليدوية لا تدوران آلياً أبداً (تكليف §2)', () {
      final annual = [
        for (var i = 0; i < 30; i++)
          entry(BackupScheduleKind.annual, DateTime.utc(2026, 1, 1 + i % 28)),
      ]..sort((a, b) => b.atUtc.compareTo(a.atUtc));
      expect(planRotation(BackupScheduleKind.annual, annual), isEmpty);
      final manual = [
        for (var i = 0; i < 30; i++)
          entry(BackupScheduleKind.manual, DateTime.utc(2026, 1, 1 + i % 28)),
      ]..sort((a, b) => b.atUtc.compareTo(a.atUtc));
      expect(planRotation(BackupScheduleKind.manual, manual), isEmpty);
    });

    test('6 حدثية → واحدة خارج حد الخمسة', () {
      final ofKind = [
        for (var i = 0; i < 6; i++)
          entry(BackupScheduleKind.event, DateTime.utc(2026, 11, 13, 20 - i)),
      ]..sort((a, b) => b.atUtc.compareTo(a.atUtc));
      expect(planRotation(BackupScheduleKind.event, ofKind).length, 1);
    });
  });

  group('سقف الحصة بالبايتات (ق-ن3: 2GB افتراضياً)', () {
    test('تقليم أقدم التلقائية حصراً حتى تحت السقف — والأرضية تسري (د-4)',
        () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 13, 1),
            size: 400),
        entry(BackupScheduleKind.daily, DateTime.utc(2026, 11, 12),
            size: 300),
        entry(BackupScheduleKind.weekly, DateTime.utc(2026, 11, 7),
            size: 200),
        entry(BackupScheduleKind.weekly, DateTime.utc(2026, 11, 8),
            size: 200),
        entry(BackupScheduleKind.annual, DateTime.utc(2026, 1, 1),
            size: 500),
        entry(BackupScheduleKind.manual, DateTime.utc(2026, 11, 1),
            size: 500),
      ];
      final plan = planCapTrim(
          usageBytes: 900, capBytes: 1000, incomingBytes: 250, entries: entries);
      // المطلوب حذف ≥150: أقدم الأسبوعية (Nov 7) وحدها تكفي — وأحدث
      // الأسبوعية (Nov 8) أرضية لا تُمس تحت ضغط السقف (د-4/س136)،
      // والساعية واليومية بsingleton أرضية كذلك.
      expect(plan.length, 1);
      expect(plan.single.kind, BackupScheduleKind.weekly);
      expect(plan.single.atUtc, DateTime.utc(2026, 11, 7));
      expect(plan.single.sizeBytes, 200);
    });

    test('السنوية واليدوية والحدثية لا تُمس بالسقف ولو ضاق', () {
      final entries = [
        entry(BackupScheduleKind.annual, DateTime.utc(2026, 1, 1), size: 900),
        entry(BackupScheduleKind.manual, DateTime.utc(2026, 1, 2), size: 900),
        entry(BackupScheduleKind.event, DateTime.utc(2026, 1, 3), size: 900),
      ];
      final plan = planCapTrim(
          usageBytes: 2700, capBytes: 1000, incomingBytes: 0, entries: entries);
      expect(plan, isEmpty);
    });
  });

  group('اللحاق والتقويم (ق-ن6: نسخة واحدة عند أول تشغيل لاحق)', () {
    test('بلا تاريخ: كل الدورات مستحقة فوراً', () {
      final due = dueAutoKinds(
          nowUtc: DateTime.utc(2026, 11, 13, 10),
          nowLocal: DateTime(2026, 11, 13, 12),
          lastSuccess: {});
      expect(
          due, containsAll([BackupScheduleKind.hourly, BackupScheduleKind.daily,
              BackupScheduleKind.weekly, BackupScheduleKind.monthly]));
    });

    test('الساعية: 59 دقيقة لا تستحق و61 دقيقة تستحق', () {
      final now = DateTime.utc(2026, 11, 13, 10, 0);
      bool dueFor(String iso) => dueAutoKinds(
              nowUtc: now,
              nowLocal: DateTime(2026, 11, 13, 12),
              lastSuccess: {
            BackupScheduleKind.hourly: DateTime.parse(iso),
          }).contains(BackupScheduleKind.hourly);
      expect(dueFor('2026-11-13T09:01:00Z'), isFalse);
      expect(dueFor('2026-11-13T08:59:00Z'), isTrue);
    });

    test('اليومية: حد بداية اليوم المحلي لا ساعة الإغلاق', () {
      // آخر يومية أمس 23:59 محلياً والآن اليوم 00:05 → مستحقة.
      final due = dueAutoKinds(
          nowUtc: DateTime.utc(2026, 11, 12, 21, 5),
          nowLocal: DateTime(2026, 11, 13, 0, 5),
          lastSuccess: {
            BackupScheduleKind.daily: DateTime.utc(2026, 11, 12, 20, 59),
          });
      expect(due, contains(BackupScheduleKind.daily));
      // آخر يومية اليوم ذاته 01:00 والآن 12:00 → غير مستحقة.
      final notDue = dueAutoKinds(
          nowUtc: DateTime.utc(2026, 11, 13, 9),
          nowLocal: DateTime(2026, 11, 13, 12),
          lastSuccess: {
            BackupScheduleKind.daily: DateTime.utc(2026, 11, 13, 1),
          });
      expect(notDue.contains(BackupScheduleKind.daily), isFalse);
    });

    test('الأسبوعية: حد السبت المحلي', () {
      // السبت 2026-11-07 محلياً؛ آخر أسبوعية الجمعة قبلها → مستحقة يوم
      // الأحد 2026-11-08 (لحاق أول تشغيل بعد فوات موعد السبت).
      final due = dueAutoKinds(
          nowUtc: DateTime.utc(2026, 11, 8, 8),
          nowLocal: DateTime(2026, 11, 8, 10),
          lastSuccess: {
            BackupScheduleKind.weekly: DateTime.utc(2026, 11, 6, 6),
          });
      expect(due, contains(BackupScheduleKind.weekly));
      // وأسبوعية بعد السبت (الأحد صباحاً) → غير مستحقة.
      final notDue = dueAutoKinds(
          nowUtc: DateTime.utc(2026, 11, 8, 8),
          nowLocal: DateTime(2026, 11, 8, 10),
          lastSuccess: {
            BackupScheduleKind.weekly: DateTime.utc(2026, 11, 7, 5),
          });
      expect(notDue.contains(BackupScheduleKind.weekly), isFalse);
    });

    test('الشهرية: حد أول الشهر المحلي', () {
      final due = dueAutoKinds(
          nowUtc: DateTime.utc(2026, 11, 1, 6),
          nowLocal: DateTime(2026, 11, 1, 8),
          lastSuccess: {
            BackupScheduleKind.monthly: DateTime.utc(2026, 10, 31, 20),
          });
      expect(due, contains(BackupScheduleKind.monthly));
    });

    test('السنوية ليست دورة تقويمية (حدث إقفال وحده)', () {
      final due = dueAutoKinds(
          nowUtc: DateTime.utc(2026, 11, 13, 10),
          nowLocal: DateTime(2026, 11, 13, 12),
          lastSuccess: {
            BackupScheduleKind.annual: DateTime.utc(2020, 1, 1),
          });
      expect(due.contains(BackupScheduleKind.annual), isFalse);
    });
  });

  group('التذكيران (§10-1 و§3)', () {
    test('الثلاثون يوماً: 29 لا و30 نعم ولا نسخة إطلاقاً نعم', () {
      final now = DateTime.utc(2026, 11, 13);
      expect(
          noBackupFor30Days(
              nowUtc: now, latestAnyUtc: DateTime.utc(2026, 11, 14)),
          isFalse);
      expect(
          noBackupFor30Days(
              nowUtc: now, latestAnyUtc: DateTime.utc(2026, 10, 14)),
          isTrue);
      expect(noBackupFor30Days(nowUtc: now, latestAnyUtc: null), isTrue);
    });

    test('مرفقات تغيرت بعد آخر نسخة تضمها → التذكير مستحق', () {
      expect(
          attachmentsReminderDue(
              latestAttachmentChangeUtc: DateTime.utc(2026, 11, 10),
              latestWithImagesUtc: DateTime.utc(2026, 11, 1)),
          isTrue);
      expect(
          attachmentsReminderDue(
              latestAttachmentChangeUtc: DateTime.utc(2026, 11, 1),
              latestWithImagesUtc: DateTime.utc(2026, 11, 10)),
          isFalse);
      expect(
          attachmentsReminderDue(
              latestAttachmentChangeUtc: null,
              latestWithImagesUtc: null),
          isFalse); // لا مرفقات أصلاً → لا تذكير
      expect(
          attachmentsReminderDue(
              latestAttachmentChangeUtc: DateTime.utc(2026, 11, 10),
              latestWithImagesUtc: null),
          isTrue); // مرفقات ولا نسخة تضمها قط
    });
  });

  group('بصمة SHA-256 النقية (ق-ن4)', () {
    test('متجه معياري: الفراغ', () {
      expect(sha256HexOf(<int>[]),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });
  });

  group('ثوابت التكليف', () {
    test('حدود الاحتفاظ بالنص', () {
      expect(backupRetentionLimits[BackupScheduleKind.hourly], 15);
      expect(backupRetentionLimits[BackupScheduleKind.daily], 8);
      expect(backupRetentionLimits[BackupScheduleKind.weekly], 5);
      expect(backupRetentionLimits[BackupScheduleKind.monthly], 12);
      expect(backupRetentionLimits[BackupScheduleKind.event], 5);
      expect(backupRetentionLimits[BackupScheduleKind.annual], isNull);
      expect(backupRetentionLimits[BackupScheduleKind.manual], isNull);
      expect(kDefaultBackupQuotaBytes, 2 * 1024 * 1024 * 1024);
    });
  });

  group('الموعد القادم (س233 — D-232: بطاقة النسخ الآلي)', () {
    final all = {
      BackupScheduleKind.hourly,
      BackupScheduleKind.daily,
      BackupScheduleKind.weekly,
      BackupScheduleKind.monthly,
    };

    test('بلا دورات مفعلة: null (المفتاح الرئيسي مطفأ أو الخانات مفرغة)',
        () {
      final next = nextAutoDueUtc(
          nowUtc: DateTime.utc(2026, 11, 28, 10),
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: const {},
          enabledKinds: const {});
      expect(next, isNull);
    });

    test('بلا تاريخ: الموعد القادم هو الآن (لحاق الدخول)', () {
      final nowUtc = DateTime.utc(2026, 11, 28, 10);
      final next = nextAutoDueUtc(
          nowUtc: nowUtc,
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: const {},
          enabledKinds: all);
      expect(next, nowUtc);
    });

    test('الساعية: آخر نجاح قبل نصف ساعة فالموعد بعد نصف ساعة', () {
      final next = nextAutoDueUtc(
          nowUtc: DateTime.utc(2026, 11, 28, 10),
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: {
            BackupScheduleKind.hourly: DateTime.utc(2026, 11, 28, 9, 30),
            BackupScheduleKind.daily: DateTime.utc(2026, 11, 28, 1),
            BackupScheduleKind.weekly: DateTime.utc(2026, 11, 24),
            BackupScheduleKind.monthly: DateTime.utc(2026, 11, 2),
          },
          enabledKinds: {BackupScheduleKind.hourly});
      expect(next, DateTime.utc(2026, 11, 28, 10, 30));
    });

    test('الساعية المتأخرة: القيمة ماضية فمعناها مستحقة الآن', () {
      final next = nextAutoDueUtc(
          nowUtc: DateTime.utc(2026, 11, 28, 10),
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: {
            BackupScheduleKind.hourly: DateTime.utc(2026, 11, 28, 7),
          },
          enabledKinds: {BackupScheduleKind.hourly});
      expect(next, DateTime.utc(2026, 11, 28, 8));
      expect(next!.isBefore(DateTime.utc(2026, 11, 28, 10)), isTrue);
    });

    test('اليومية: آخر نجاح اليوم فالموعد بداية الغد المحلي', () {
      final next = nextAutoDueUtc(
          nowUtc: DateTime.utc(2026, 11, 28, 9),
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: {
            BackupScheduleKind.daily: DateTime.utc(2026, 11, 28, 1),
          },
          enabledKinds: {BackupScheduleKind.daily});
      expect(next, DateTime(2026, 11, 29).toUtc());
    });

    test('الأسبوعية: آخر نجاح بأسبوعها فالموعد السبت التالي', () {
      // 2026-11-28 سبت؛ أسبوعه يبدأ 2026-11-28 والقادم 2026-12-05.
      final next = nextAutoDueUtc(
          nowUtc: DateTime.utc(2026, 11, 28, 10),
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: {
            BackupScheduleKind.weekly: DateTime.utc(2026, 11, 28, 6),
          },
          enabledKinds: {BackupScheduleKind.weekly});
      expect(next, DateTime(2026, 12, 5).toUtc());
    });

    test('الشهرية: آخر نجاح بشهرها فالموعد أول الشهر القادم', () {
      final next = nextAutoDueUtc(
          nowUtc: DateTime.utc(2026, 11, 28, 10),
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: {
            BackupScheduleKind.monthly: DateTime.utc(2026, 11, 2),
          },
          enabledKinds: {BackupScheduleKind.monthly});
      expect(next, DateTime(2026, 12, 1).toUtc());
    });

    test('الدورة المفرغة خارج الحساب والمعطلة لا تحسب', () {
      // اليومية مفرغة والساعية معطلة فالموعد الشهرية وحدها.
      final next = nextAutoDueUtc(
          nowUtc: DateTime.utc(2026, 11, 28, 10),
          nowLocal: DateTime(2026, 11, 28, 12),
          lastSuccess: {
            BackupScheduleKind.daily: DateTime.utc(2026, 11, 2),
            BackupScheduleKind.monthly: DateTime.utc(2026, 11, 2),
          },
          enabledKinds: {BackupScheduleKind.monthly});
      expect(next, DateTime(2026, 12, 1).toUtc());
    });
  });
}
