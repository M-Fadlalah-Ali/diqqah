/// اختبار نافذة التراجع عن الاستعادة والتنظيف الذكي (د-3/د-8 — §25.7/§25.8،
/// س136): حالة النافذة وحارس أول كتابة بخط أساس سجل الأحداث، واقتراح
/// التنظيف الذي يعرض لا يحذف ويُبقي الأرضية.
library;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:test/test.dart';

BackupCatalogEntry entry(
  BackupScheduleKind kind,
  DateTime at, {
  int size = 100,
}) =>
    BackupCatalogEntry(
      fileName: scheduledBackupFileName(
          kind: kind, deviceTag: 'a1b2c3d4', atUtc: at),
      kind: kind,
      atUtc: at,
      sizeBytes: size,
      deviceTag: 'a1b2c3d4',
      includesImages: false,
      folderId: 'backups',
    );

void main() {
  group('حالة النافذة — RollbackWindowState', () {
    final state = RollbackWindowState(
      snapshotFileName: 'diqqah-before-restore-20261114-080000-000.db',
      openedAtUtc: DateTime.utc(2026, 11, 14, 8, 0, 0),
      baselineEventId: 42,
      closed: false,
    );

    test('الJSON دورة كاملة', () {
      final parsed = RollbackWindowState.tryParse(state.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.snapshotFileName, state.snapshotFileName);
      expect(parsed.openedAtUtc, state.openedAtUtc);
      expect(parsed.baselineEventId, 42);
      expect(parsed.closed, isFalse);
    });

    test('نص فاسد أو غير JSON → null (الفاسد كالغائب)', () {
      expect(RollbackWindowState.tryParse('not json'), isNull);
      expect(RollbackWindowState.tryParse('{"snapshot":42}'), isNull);
      expect(RollbackWindowState.tryParse('[]'), isNull);
    });

    test('withClosed يغلق بلا مساس ببقية الحقول', () {
      final closed = state.withClosed();
      expect(closed.closed, isTrue);
      expect(closed.snapshotFileName, state.snapshotFileName);
      expect(closed.baselineEventId, state.baselineEventId);
    });
  });

  group('حارس أول كتابة — rollbackWindowClosedByWrite', () {
    RollbackWindowState open(int baseline) => RollbackWindowState(
          snapshotFileName: 'diqqah-before-restore-1.db',
          openedAtUtc: DateTime.utc(2026, 11, 14, 8),
          baselineEventId: baseline,
          closed: false,
        );

    test('حدث يتجاوز خط الأساس → كتابة أغلقت النافذة', () {
      expect(rollbackWindowClosedByWrite(open(42), 43), isTrue);
      expect(rollbackWindowClosedByWrite(open(42), 100), isTrue);
    });

    test('لا حدث جديداً (نفس الخط أو أقل) → النافذة باقية', () {
      expect(rollbackWindowClosedByWrite(open(42), 42), isFalse);
      expect(rollbackWindowClosedByWrite(open(42), 42), isFalse);
      expect(rollbackWindowClosedByWrite(open(42), 0), isFalse);
    });

    test('النافذة المقفلة سلفاً مقفلة لا يغيرها القراء', () {
      final closed = open(42).withClosed();
      expect(rollbackWindowClosedByWrite(closed, 42), isTrue);
      expect(rollbackWindowClosedByWrite(closed, 999), isTrue);
    });
  });

  group('التنظيف الذكي — planSmartCleanup (يقترح لا يحذف)', () {
    test('تحت عتبة التحذير 80% → لا اقتراح', () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 8),
            size: 300),
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 9),
            size: 300),
      ];
      // الاستعمال 600 من سقف 1000 = 60% < 80% → لا ازدحام.
      expect(
          planSmartCleanup(
              entries: entries, usageBytes: 600, capBytes: 1000),
          isEmpty);
    });

    test('فوق العتبة → الأقدم أولاً حتى تحت العتبة والأرضية محمية', () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 7),
            size: 200),
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 8),
            size: 200),
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 9),
            size: 200),
        entry(BackupScheduleKind.daily, DateTime.utc(2026, 11, 13),
            size: 200),
      ];
      // الاستعمال 800 من سقف 1000 = 80%+ → الهدف العودة تحت 800.
      // المطلوب حذف > 0: أقدم الساعية (200) وحدَها تكفي.
      final plan = planSmartCleanup(
          entries: entries, usageBytes: 800, capBytes: 1000);
      expect(plan, hasLength(1));
      expect(plan.single.atUtc, DateTime.utc(2026, 11, 14, 7));
    });

    test('الأرضية توقف الاقتراح: ما عداها لا يبلغ العتبة فتتوقف صادقة',
        () {
      final entries = [
        entry(BackupScheduleKind.hourly, DateTime.utc(2026, 11, 14, 8),
            size: 500),
        entry(BackupScheduleKind.daily, DateTime.utc(2026, 11, 13),
            size: 500),
      ];
      // الاستعمال 1000 من سقف 1000 → هدف 800 — لكن الاثنتين أرضية
      // (كل نوع بنسخته الوحيدة) فلا اقتراح إطلاقاً.
      expect(
          planSmartCleanup(
              entries: entries, usageBytes: 1000, capBytes: 1000),
          isEmpty);
    });

    test('السنوية واليدوية والحدثية خارج الاقتراح كلياً', () {
      final entries = [
        entry(BackupScheduleKind.annual, DateTime.utc(2026, 1, 1),
            size: 900),
        entry(BackupScheduleKind.manual, DateTime.utc(2026, 1, 2),
            size: 900),
        entry(BackupScheduleKind.event, DateTime.utc(2026, 1, 3),
            size: 900),
      ];
      expect(
          planSmartCleanup(
              entries: entries, usageBytes: 2700, capBytes: 1000),
          isEmpty);
    });
  });
}
