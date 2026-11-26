// اختبارات د0 — الأداء والأحمال التمهيدية (س160 — أولى خارطة م4 09 §46).
//
// الترحيلة v29: فهرس ix_move_lines_move_id على move_lines — المرشح
// الموثق س156 صار مخططاً بقرار م-٤ («د0 تسبق فكل دفعة تُقاس على أداء
// معلوم»). التغطية:
//   (1) القاعدة الجديدة تولد والفهرس حاضر (onCreate).
//   (2) القاعدة القائمة v28 تُرقّى 28→29 بالفهرس بلا مساس بالبيانات —
//       وآمنة التكرار بلا مساس عند إعادة الفتح (نمط batch28).
//   (3) خطة التنفيذ تعلن استعمال الفهرس لفحص التوازن (EXPLAIN QUERY PLAN).
//   (4) القياس المطبوع لا الحاكم (نمط س156): ترحيل عينتين مستقلتين —
//       بالفهرس ثم بغَيابه — فأثر الفهرس موثق بالجولة لا بالادعاء،
//       والعتبات المطلقة (<3ث/<300ms/<1ث) جهاز حقيقي عند البوابات
//       حصراً (D-211 — أدوات integration_test الجهازية بأمر flutter drive).
//
// الحاكم: integrity_check=ok والميزان متوازن قيداً قيداً عتاد القاعدة
// ذاته (زنادا DQ-0101/0102) — عرف الفئة 1 الشطر التخزيني (س156).
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late Directory tempDir;
  late DiqqahDatabase db;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_d0_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// حضور الفهرس بالقاعدة المفتوحة ذاتها.
  Future<int> indexCount(DiqqahDatabase target) async {
    final rows = await target.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'ix_move_lines_move_id'").get();
    return rows.length;
  }

  /// بلع أطراف وأصناف العينة بمسار القاعدة القانوني (نمط س156).
  Future<void> seedHeavyReference(double scale) async {
    final parties = generateHeavyParties(scale: scale);
    final items = generateHeavyItems(scale: scale);
    await db.batch((batch) {
      batch.insertAll(db.parties, [
        for (final s in parties)
          PartiesCompanion.insert(
            number: s.number,
            name: s.name,
            kind: s.kindStorage,
            defaultCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-${s.number}',
          ),
      ]);
      batch.insertAll(db.items, [
        for (final s in items)
          ItemsCompanion.insert(
            sku: s.sku,
            name: s.name,
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 1000,
            salePriceMinor: 1500,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-${s.sku}',
          ),
      ]);
    });
  }

  /// عينة قيود كاملة بمسار القاعدة القانوني حصراً: مسودة ثم أسطر ثم
  /// ترحيل بUPDATE يحكّمه trg_moves_post_balance (DQ-0101/0102) —
  /// ويقرأ الأعداد ببادئة الرقم المعطاة.
  Future<int> loadAndPostMoves(
      List<HeavyMoveSeed> moves, String numberPrefix, String uuidPrefix) async {
    final journalId = (await db.select(db.journals).get()).first.id;
    await db.batch((batch) {
      batch.insertAll(db.moves, [
        for (final m in moves)
          MovesCompanion.insert(
            journalId: journalId,
            dateText: m.dateText,
            state: 'draft',
            number: numberPrefix == 'SH-'
                ? m.number
                : m.number.replaceFirst('SH-', numberPrefix),
            uuid: 'uuid-$uuidPrefix-${m.number}',
          ),
      ]);
    });
    final rows = await db.customSelect(
        "SELECT id, number FROM moves WHERE number LIKE '$numberPrefix%'")
        .get();
    final idByNumber = <String, int>{
      for (final r in rows) r.data['number'] as String: r.data['id'] as int,
    };
    await db.batch((batch) {
      for (final m in moves) {
        final number = numberPrefix == 'SH-'
            ? m.number
            : m.number.replaceFirst('SH-', numberPrefix);
        final id = idByNumber[number]!;
        batch.insert(db.moveLines, MoveLinesCompanion.insert(
            moveId: id,
            accountId: m.debitAccountId,
            debitMinor: Value(m.amountMinor),
            creditMinor: const Value(0),
            uuid: 'uuid-$uuidPrefix-${m.number}-d'));
        batch.insert(db.moveLines, MoveLinesCompanion.insert(
            moveId: id,
            accountId: m.creditAccountId,
            debitMinor: const Value(0),
            creditMinor: Value(m.amountMinor),
            uuid: 'uuid-$uuidPrefix-${m.number}-c'));
      }
    });
    await db.customStatement(
        "UPDATE moves SET state = 'posted' WHERE number LIKE '$numberPrefix%'");
    return rows.length;
  }

  group('د0 — ترحيلة v29 فهرس move_id على move_lines', () {
    test('القاعدة الجديدة تولد والفهرس حاضر والإصدار 29 حرفاً', () async {
      expect(db.schemaVersion, DiqqahDatabase.schemaVersionValue);
      expect(await indexCount(db), 1,
          reason: 'الفهرس من أول إنشاء (onCreate) لا من ترحيلة');
      // سلامة الإنشاء كاملاً: القاعدة صالحة والدليل مبذور.
      final ic = await db.customSelect('PRAGMA integrity_check').get();
      expect(ic.single.data['integrity_check'], 'ok');
    });

    test('نص الفهرس على الأعمدة المعتمدة حرفاً: move_lines (move_id)',
        () async {
      final rows = await db.customSelect(
          "SELECT tbl_name, sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'ix_move_lines_move_id'").getSingle();
      expect(rows.data['tbl_name'], 'move_lines');
      final ddl = rows.data['sql'] as String;
      expect(ddl, contains('move_id'),
          reason: 'العمود المؤرَّس move_id لا غير');
    });

    test('ترحيلة v29 على قاعدة v28: الفهرس يعود والبيانات باقية '
        'وآمنة التكرار عند إعادة الفتح (نمط batch28)', () async {
      // قاعدة حية ببيانات: طرف وصنف وقيد مزدوج مرحَّل.
      final accounts = await db.select(db.accounts).get();
      final leaves = accounts.where((a) => a.isLeaf && a.isActive).toList();
      await seedHeavyReference(0.001);
      final moves = generateHeavyMoves(
        scale: 0.001,
        debitAccountId: leaves.first.id,
        creditAccountId: leaves.last.id,
      );
      final posted = await loadAndPostMoves(moves, 'SH-', 'pre');
      expect(posted, 500, reason: 'مقياس 0.001 = 500 قيد مزدوج');
      expect(await indexCount(db), 1);

      // الهبوط لصيغة v28: حذف الفهرس وإزالة الإصدار — أي ما ستراه
      // أجهزة المالك الحقيقية عند أول فتح فوق b48 (شكل v28 الحرفي:
      // مخطط كامل بلا فهرس).
      await db.close();
      final raw = sql.sqlite3.open(dbPath);
      raw.execute('DROP INDEX ix_move_lines_move_id');
      raw.execute('PRAGMA user_version = 28');
      raw.dispose();

      // إعادة الفتح تثير الترقية 28→29: الفرع يبني الفهرس ولا مساس
      // بغيره (CREATE INDEX IF NOT EXISTS حصراً — لا جداول ولا أعمدة).
      final migrated = DiqqahDatabase(filePath: dbPath);
      addTearDown(migrated.close);
      await migrated.select(migrated.parties).get();
      expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);
      expect(await indexCount(migrated), 1,
          reason: 'ترحيلة v29 أعادت الفهرس للقاعدة القائمة');
      final ic = await migrated.customSelect('PRAGMA integrity_check').get();
      expect(ic.single.data['integrity_check'], 'ok');

      // البيانات كاملة بعد الترقية حرفاً — الترحيلة لا تمس سوى الفهرس.
      final partyCount =
          await migrated.customSelect('SELECT COUNT(*) AS c FROM parties')
              .getSingle();
      expect(partyCount.data['c'], 7, reason: 'مقياس 0.001: 6 عملاء ومورد');
      final lineCount =
          await migrated.customSelect('SELECT COUNT(*) AS c FROM move_lines')
              .getSingle();
      expect(lineCount.data['c'], 1000);
      final expectedTotal =
          moves.fold<int>(0, (s, m) => s + m.amountMinor);
      final sums = await migrated.customSelect(
          'SELECT COALESCE(SUM(debit_minor),0) AS d, '
          'COALESCE(SUM(credit_minor),0) AS c FROM move_lines').getSingle();
      expect(sums.data['d'], expectedTotal, reason: 'الميزان متوازن');
      expect(sums.data['c'], expectedTotal, reason: 'الميزان متوازن');

      // إعادة الفتح ثانية: آمنة التكرار بلا إعادة ترحيلة ولا مساس.
      await migrated.close();
      final again = DiqqahDatabase(filePath: dbPath);
      addTearDown(again.close);
      await again.select(again.parties).get();
      expect(again.schemaVersion, DiqqahDatabase.schemaVersionValue);
      expect(await indexCount(again), 1);
    });

    test('خطة فحص التوازن تعلن الفهرس: EXPLAIN QUERY PLAN ببحث المؤشر',
        () async {
      final accounts = await db.select(db.accounts).get();
      final leaves = accounts.where((a) => a.isLeaf && a.isActive).toList();
      await seedHeavyReference(0.01);
      final moves = generateHeavyMoves(
        scale: 0.01,
        debitAccountId: leaves.first.id,
        creditAccountId: leaves.last.id,
      );
      await loadAndPostMoves(moves, 'SH-', 'plan');
      final plan = await db.customSelect(
          'EXPLAIN QUERY PLAN SELECT COALESCE(SUM(debit_minor),0) '
          'FROM move_lines WHERE move_id = ?',
          variables: [Variable.withInt(1)]).get();
      final details =
          plan.map((r) => r.data['detail'].toString()).join(' | ');
      // ignore: avoid_print
      print('خطة فحص التوازن: $details');
      expect(details, contains('ix_move_lines_move_id'),
          reason: 'زنادا التوازن (DQ-0101/0102) يبحثان بالمؤشر لا بمسح '
              'كامل — وعلة O(N²) الموثقة س156 منتهية بالمخطط');
    });
  });

  group('د0 — القياس المطبوع لأثر الفهرس (لا حاكم — نمط س156)', () {
    test('ترحيل عينتين مستقلتين: بالفهرس ثم بغَيابه — الأثر بالأرقام',
        () async {
      final accounts = await db.select(db.accounts).get();
      final leaves = accounts.where((a) => a.isLeaf && a.isActive).toList();
      final debitAcc = leaves.first.id;
      final creditAcc = leaves.last.id;
      expect(await indexCount(db), 1);

      await seedHeavyReference(0.02);

      // العينة أ — بالفهرس (وضع v29 الطبيعي): 10,000 قيد مزدوج.
      final withIndexWatch = Stopwatch()..start();
      final setA = generateHeavyMoves(
          scale: 0.02,
          debitAccountId: debitAcc,
          creditAccountId: creditAcc);
      expect(setA, hasLength(10000));
      final postedA = await loadAndPostMoves(setA, 'SH-', 'with');
      withIndexWatch.stop();
      expect(postedA, 10000);

      // العينة ب — بغَياب الفهرس (شكل v28 الموثق س156): 5,000 قيد
      // مزدوج على جدول أسطر أكبر فالأثر أوضح — ثم الفهرس يعاد
      // فلا قاعدة تُترك خارج مخططها.
      await db.customStatement('DROP INDEX ix_move_lines_move_id');
      final withoutIndexWatch = Stopwatch()..start();
      final setB = generateHeavyMoves(
          scale: 0.01,
          debitAccountId: debitAcc,
          creditAccountId: creditAcc);
      expect(setB, hasLength(5000));
      final postedB = await loadAndPostMoves(setB, 'SB-', 'without');
      withoutIndexWatch.stop();
      expect(postedB, 5000);
      await db.customStatement(
          'CREATE INDEX IF NOT EXISTS ix_move_lines_move_id '
          'ON move_lines (move_id)');
      expect(await indexCount(db), 1,
          reason: 'الفهرس يعاد بعد القياس فلا مخطط ناقص');

      // ignore: avoid_print
      print('د0 القياس: ترحيل 10,000 قيد بالفهرس '
          '${withIndexWatch.elapsedMilliseconds}ms — ترحيل 5,000 قيد '
          'بغَيابه ${withoutIndexWatch.elapsedMilliseconds}ms');
      // حارسان متساهلان بالCI (العتبات المطلقة جهاز حقيقي حصراً —
      // D-211/س156): الانحدار فوقهما علة لا أثر مقصود.
      expect(withIndexWatch.elapsed, lessThan(const Duration(seconds: 10)),
          reason: 'الترحيل بالفهرس استغرق ${withIndexWatch.elapsed}');
      expect(withoutIndexWatch.elapsed, lessThan(const Duration(seconds: 90)),
          reason: 'الترحيل بغَياب الفهرس استغرق ${withoutIndexWatch.elapsed} '
              '— حد القياس لا عتبة جهاز');

      // معيار النجاح 1 والعدادات والميزان المزدوج على الجمع كله.
      final ic = await db.customSelect('PRAGMA integrity_check').get();
      expect(ic.single.data['integrity_check'], 'ok');
      final postedCount = await db.customSelect(
          "SELECT COUNT(*) AS c FROM moves WHERE state = 'posted'")
          .getSingle();
      expect(postedCount.data['c'], 15000);
      final lineCount = await db.customSelect(
          'SELECT COUNT(*) AS c FROM move_lines').getSingle();
      expect(lineCount.data['c'], 30000);
      final expectedTotal = setA.fold<int>(0, (s, m) => s + m.amountMinor) +
          setB.fold<int>(0, (s, m) => s + m.amountMinor);
      final sums = await db.customSelect(
          'SELECT COALESCE(SUM(debit_minor),0) AS d, '
          'COALESCE(SUM(credit_minor),0) AS c FROM move_lines').getSingle();
      expect(sums.data['d'], expectedTotal);
      expect(sums.data['c'], expectedTotal);
    });
  });
}
