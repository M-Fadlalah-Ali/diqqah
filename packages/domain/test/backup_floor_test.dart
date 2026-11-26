/// اختبار الأرضية النظامية (د-4 — §25.8، س136): آخر نسخة من كل نوع لا
/// تُحذف من داخل التطبيق مطلقاً — حارس الملفات المحمية وتقليم السقف
/// لا يمس الأرضية تحت ضغط الحصة.
library;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:test/test.dart';

BackupCatalogEntry entry(
  BackupScheduleKind kind,
  DateTime at, {
  int size = 100,
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
      includesImages: false,
      folderId: 'backups',
    );

void main() {
  group('حارس الأرضية — protectedFloorFileNames', () {
    test('أحدث نسخة من كل نوع حاضرة محمية', () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 8)),
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 9)),
        entry(BackupScheduleKind.daily, DateTime.utc(2026, 11, 13)),
        entry(BackupScheduleKind.annual, DateTime.utc(2026, 1, 1)),
        entry(BackupScheduleKind.manual, DateTime.utc(2026, 11, 2)),
        entry(BackupScheduleKind.event, DateTime.utc(2026, 11, 3)),
      ];
      final floors = protectedFloorFileNames(entries);
      // أحدث الساعية + اليومية الوحيدة + السنوية + اليدوية + الحدثية = 5.
      expect(floors, hasLength(5));
      expect(
          floors.contains(scheduledBackupFileName(
              kind: BackupScheduleKind.hourly,
              deviceTag: 'a1b2c3d4',
              atUtc: DateTime.utc(2026, 11, 14, 9))),
          isTrue); // أحدث الساعية — الأرضية.
      expect(
          floors.contains(scheduledBackupFileName(
              kind: BackupScheduleKind.hourly,
              deviceTag: 'a1b2c3d4',
              atUtc: DateTime.utc(2026, 11, 14, 8))),
          isFalse); // الأقدم منها ليست أرضية.
      expect(
          floors.contains(scheduledBackupFileName(
              kind: BackupScheduleKind.daily,
              deviceTag: 'a1b2c3d4',
              atUtc: DateTime.utc(2026, 11, 13))),
          isTrue);
      expect(
          floors.contains(scheduledBackupFileName(
              kind: BackupScheduleKind.annual,
              deviceTag: 'a1b2c3d4',
              atUtc: DateTime.utc(2026, 1, 1))),
          isTrue);
      expect(
          floors.contains(scheduledBackupFileName(
              kind: BackupScheduleKind.manual,
              deviceTag: 'a1b2c3d4',
              atUtc: DateTime.utc(2026, 11, 2))),
          isTrue);
      expect(
          floors.contains(scheduledBackupFileName(
              kind: BackupScheduleKind.event,
              deviceTag: 'a1b2c3d4',
              atUtc: DateTime.utc(2026, 11, 3))),
          isTrue);
    });

    test('النوع الوحيد بنسخته الوحيدة هي الأرضية كلها', () {
      final entries = [
        entry(BackupScheduleKind.manual, DateTime.utc(2026, 11, 2)),
      ];
      expect(protectedFloorFileNames(entries),
          {scheduledBackupFileName(
              kind: BackupScheduleKind.manual,
              deviceTag: 'a1b2c3d4',
              atUtc: DateTime.utc(2026, 11, 2))});
    });

    test('كتالوج فارغ → أرضية فارغة', () {
      expect(protectedFloorFileNames(const []), isEmpty);
    });
  });

  group('تقليم السقف والأرضية (د-4: الأرضية تسري تحت ضغط الحصة)', () {
    test('كل تلقائية بنسخة واحدة → خطة فارغة ولو فاض السقف', () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 9),
            size: 900),
        entry(BackupScheduleKind.daily, DateTime.utc(2026, 11, 13),
            size: 900),
        entry(BackupScheduleKind.weekly, DateTime.utc(2026, 11, 8),
            size: 900),
      ];
      final plan = planCapTrim(
          usageBytes: 2700, capBytes: 1000, incomingBytes: 0,
          entries: entries);
      expect(plan, isEmpty);
    });

    test('الأقدم فقط يُحذف والأحدث محمية ولو لم يبلغ السقف بعدُ', () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 8),
            size: 400),
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 9),
            size: 400),
        entry(BackupScheduleKind.daily, DateTime.utc(2026, 11, 13),
            size: 300),
      ];
      final plan = planCapTrim(
          usageBytes: 1100, capBytes: 1000, incomingBytes: 0,
          entries: entries);
      // المطلوب حذف ≥100: أقدم الساعية (400) تكفي — وأحدث الساعية
      // واليومية الوحيدة أرضية لا تُمس.
      expect(plan, hasLength(1));
      expect(plan.single.atUtc, DateTime.utc(2026, 11, 14, 8));
    });

    test('الأرضية تنتصر على السقف: ما أمكن حذفه يُحذف وما دونها لا', () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 8),
            size: 300),
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 9),
            size: 700),
        entry(BackupScheduleKind.daily, DateTime.utc(2026, 11, 13),
            size: 1000),
      ];
      final plan = planCapTrim(
          usageBytes: 2000, capBytes: 1000, incomingBytes: 0,
          entries: entries);
      // حذف أقدم الساعية (300) يُنزل إلى 1700 — لم يبلغ السقف — لكن
      // البقية أرضية (أحدث الساعية واليومية الوحيدة) فتتوقف الخطة صادقة.
      expect(plan, hasLength(1));
      expect(plan.single.sizeBytes, 300);
    });
  });
}
