import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'invoice_flow_test.dart' show buildFixture;

/// ═══ س107 (أساس الأخطاء — قرار المالك الخامس): اختبارات الطبقة ═══
///
/// (1) جدول error_log قائم على كل مسار والتسجيل أقصى جهد لا يفشل
/// تدفقاً أبداً. (2) الحواجز القائمة ترمي رسائلها المرقّمة DQ-xxxx
/// حرفاً — الترقيم ظاهر للمستخدم لا ميتاً بالمخطط. (3) خريطة
/// استثناءات التخزين DQ-11xx توصل سلطة الترقيم بالمجال.
void main() {
  group('سجل الأخطاء error_log (س107)', () {
    test('قاعدة جديدة: الجدول قائم والتسجيل والقراءة بالأحدث أولاً',
        () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();

      await db.logError(
          code: 'DQ-0201',
          message: 'رصيد مخزون سالب مرفوض',
          context: 'invoice.post');
      await db.logError(code: 'DQ-0103', message: 'القيد المرحّل لا يعدل');

      expect(await db.errorLogCount(), 2);
      final rows = await db.recentErrors();
      expect(rows.length, 2);
      // الأحدث أولاً: آخر تسجيل (DQ-0103) قبل الأول.
      expect(rows.first['code'], 'DQ-0103');
      expect(rows.first['context'], isNull);
      expect(rows.last['code'], 'DQ-0201');
      expect(rows.last['context'], 'invoice.post');
      expect(rows.last['created_at'], greaterThan(0));
    });

    test('التسجيل أقصى جهد: سقوط الجدول لا يفشل التسجيل ولا يرمي',
        () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();

      // إسقاط الجدول يكسر INSERT — والعقد الموثق: لا رمي أبداً
      // (errorLogCount قراءة حية لا تتعهد بالسقوط — حدٌّ موثق).
      await db.customStatement('DROP TABLE error_log');
      await db.logError(code: 'DQ-0999', message: 'بعد السقوط');
    });

    test('الحد: recentErrors(limit) يقصّ السجل الأقدم', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      for (var i = 0; i < 7; i++) {
        await db.logError(code: 'DQ-0999', message: 'سجل $i');
      }
      final rows = await db.recentErrors(limit: 3);
      expect(rows.length, 3);
      expect(rows.first['message'], 'سجل 6');
      expect(rows.last['message'], 'سجل 4');
    });
  });

  group('الحواجز المرقّمة ترمي رموزها (س107)', () {
    test('حاجز تجميد القيد المرحّل يحمل (DQ-0103) بنصه', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      final f = await buildFixture(db);
      // شراء مرحّل = قيد مرحّل بمصدره.
      await f.purchaseCredit(lines: [f.line(f.oilId, 5, 25000)]);

      // قيد مرحّل: تعديل أي حقل مجمد يرمي الحاجز برمزه.
      final moveId = await db.customSelect(
              "SELECT id FROM moves WHERE state = 'posted' LIMIT 1")
          .getSingle();
      expect(moveId.data, isNotNull);
      await expectLater(
        db.customStatement(
            'UPDATE moves SET narration = ? WHERE id = ?',
            ['عبث', moveId.data['id']]),
        throwsA(predicate((e) =>
            e is SqliteException && e.message.contains('DQ-0103'))),
      );
    });

    test('حاجز منع حذف الفاتورة المرحّلة يحمل (DQ-0208) بنصه', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      final f = await buildFixture(db);
      await f.purchaseCredit(lines: [f.line(f.oilId, 5, 25000)]);
      final invId = await f.saleCredit(lines: [
        f.line(f.oilId, 2, 40000),
      ]);
      await expectLater(
        db.customStatement(
            'DELETE FROM invoices WHERE id = ?',
            [invId]),
        throwsA(predicate((e) =>
            e is SqliteException && e.message.contains('DQ-0208'))),
      );
    });

    test('حواجز الإقفال المرقّمة حيّة بعد الترحيلة (DQ-0601)', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      // تعريف المشغلات في القاعدة الجديدة يحمل الرمز نصاً.
      final sql = await db.customSelect(
              "SELECT sql FROM sqlite_master WHERE name = "
              "'trg_moves_closed_period_insert'")
          .getSingle();
      expect((sql.data['sql'] as String).contains('DQ-0601'), isTrue);
    });
  });

  group('خريطة استثناءات التخزين DQ-11xx (س107)', () {
    test('كل استثناء تخزين معروف برمزه الموثق', () {
      expect(dqCodeForStorageError(const DiqqahNewerSchemaException()),
          'DQ-1101');
      expect(dqCodeForStorageError(const UnitGroupFactorFrozenException()),
          'DQ-1102');
      expect(
          dqCodeForStorageError(const CorruptBackupException()), 'DQ-1104');
      expect(dqCodeForStorageError(const BackupNewerSchemaException(99)),
          'DQ-1105');
    });

    test('غير المصنف null — والفاصلة الآمنة من سجل المجال', () {
      expect(dqCodeForStorageError(Exception('غريب')), isNull);
      expect(diqqahUnclassifiedError.code, 'DQ-0999');
      // والرمزان المتفق عليهما بين الطبقتين موجودان بالسجل الموحد.
      expect(diqqahErrorCodeOf('DQ-1101'), isNotNull);
      expect(diqqahErrorCodeOf('DQ-1104'), isNotNull);
    });
  });
}
