/// اختبار نافذة التراجع عن الاستعادة — طبقة التخزين (د-3 — §25.7، س136):
/// التسليح بخط أساس سجل الأحداث، والحارس يغلق بأول كتابة ويسجل الحدث،
/// والاستبدال بكل استعادة جديدة، والفاسد كالغائب.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late DiqqahDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_window_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> closedEventsCount() async {
    final rows = await (db.select(db.events)
          ..where((t) => t.action.equals('rollback_window_closed')))
        .get();
    return rows.length;
  }

  group('نافذة التراجع — التسليح والحارس', () {
    test('maxEventId: صفر على سجل فارغ ويزيد مع كل حدث', () async {
      expect(await db.maxEventId(), 0);
      await db.recordSystemEvent('restore_performed');
      expect(await db.maxEventId(), 1);
      await db.recordSystemEvent('restore_summary_shown');
      expect(await db.maxEventId(), 2);
    });

    test('armRollbackWindow يسلّح بخط أساس الحاضر ويستبدل السابق', () async {
      await db.recordSystemEvent('restore_performed'); // id 1
      await db.armRollbackWindow(
          snapshotFileName: 'diqqah-before-restore-1.db');
      var w = await db.rollbackWindow();
      expect(w, isNotNull);
      expect(w!.snapshotFileName, 'diqqah-before-restore-1.db');
      expect(w.baselineEventId, 1);
      expect(w.closed, isFalse);

      // استعادة ثانية → النافذة تعود لآخر استعادة حصراً.
      await db.recordSystemEvent('restore_summary_shown'); // id 2
      await db.armRollbackWindow(
          snapshotFileName: 'diqqah-before-restore-2.db');
      w = await db.rollbackWindow();
      expect(w!.snapshotFileName, 'diqqah-before-restore-2.db');
      expect(w.baselineEventId, 2);
    });

    test('أول كتابة (حدث جديد) تغلق النافذة وتسجل الحدث وتدوم مغلقة',
        () async {
      await db.recordSystemEvent('restore_performed'); // id 1
      await db.armRollbackWindow(
          snapshotFileName: 'diqqah-before-restore-1.db');

      // بلا كتابة: النافذة مفتوحة بلا حدث إغلاق.
      var w = await db.rollbackWindow();
      expect(w!.closed, isFalse);
      expect(await closedEventsCount(), 0);

      // أول كتابة — حدث جديد يتجاوز خط الأساس.
      await db.recordSystemEvent('draft_created');
      w = await db.rollbackWindow();
      expect(w!.closed, isTrue);
      expect(await closedEventsCount(), 1);

      // القراءة الثانية لا تسجل ثانية (الإغلاق مرة واحدة).
      final again = await db.rollbackWindow();
      expect(again!.closed, isTrue);
      expect(await closedEventsCount(), 1);
    });

    test('حدث عند خط الأساس ذاته لا يغلق — ما بعده وحده كتابة', () async {
      await db.recordSystemEvent('restore_performed'); // id 1
      await db.armRollbackWindow(
          snapshotFileName: 'diqqah-before-restore-1.db');
      final w = await db.rollbackWindow();
      expect(w!.closed, isFalse); // maxEventId == baseline
    });

    test('مفتاح تالف كالغائب — null بلا سحر', () async {
      await db.customStatement(
          "INSERT INTO app_meta (key, value) VALUES "
          "('restore.rollback_window', 'not json')");
      expect(await db.rollbackWindow(), isNull);
    });

    test('لا نافذة أصلاً — null', () async {
      expect(await db.rollbackWindow(), isNull);
    });
  });
}
