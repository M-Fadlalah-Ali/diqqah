// أدوات D-211 الجهازية — د0 (س160 — أولى خارطة م4 09 §46):
// اختبار الضغط الكامل على جهاز حقيقي بعينة م4 المعتمدة حرفاً
// (5,500 عميل و1,000 مورد و10,000 صنف و500,000 قيد مزدوج = مليون رجل).
//
// المصدر نص التقرير المعتمد للمالك (10 §10/الفئة 1): «استخدم حزمة
// integration_test الرسمية لتشغيل التطبيق كاملاً على جهاز حقيقي مع
// قاعدة بيانات محمّلة مسبقاً» — وأمر التشغيل الموثق بعده:
//   flutter drive --driver=test_driver/perf_driver.dart \
//     --target=integration_test/large_data_test.dart --profile
//
// ما يقيسه هذا الملف (الطبقة البيانية على العينة الكاملة):
//   فتح القاعدة المحمّلة — البحث عن طرف وصنف (<300ms) — ميزان
//   المراجعة (<1ث) — integrity_check=ok — الميزان المزدوج قيداً
//   قيداً — العدادات حرفاً.
//
// الحدود الصادقة (D-211 — لا يُدّعى آلياً أبداً):
//   (1) العتبات المطلقة تُطبع بالجدول وتُصدَّق المالكُ بتصديق مكتوب
//       عند البوابة — الأداة تطبع ولا تقرر جهازك.
//   (2) «زمن فتح التطبيق <3ث» بروتوكوله الميداني الموثق (بوابة
//       F-016 — خمس قيم لكل منصة بساعة الإيقاف) وهو مستند مستقل
//       لا يدخل هنا.
//   (3) عينة «سنة العمل الممتلئة» (>500MB بالمستندات والأحداث)
//       قياسها موضع د6 الأحمال الختامية بنص الخارطة (د0 تمهيدية).
//
// شرطان للعمل الصحيح: الجهاز على مصدر كهرباء (لا موفر طاقة) وبلا
// تطبيقات ثقيلة بالخلفية — وإلا فالقياس شاهد على الجهاز لا على
// التطبيق (نص بروتوكول F-016).
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

const int chunkMoves = 5000;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('د0 — العينة الكاملة عبر المسار القانوني ثم القياسات الثلاثة',
      (tester) async {
    final tempDir =
        await Directory.systemTemp.createTemp('diqqah_d0_device_');
    final dbPath = p.join(tempDir.path, 'diqqah_full_sample.db');

    // ═══ 1) التوليد الحتمي للعينة المعتمدة حرفاً (بذرة ثابتة). ═══
    final parties = generateHeavyParties(); // 6,500 = 5,500 + 1,000
    final items = generateHeavyItems(); // 10,000
    final moves = generateHeavyMoves(); // 500,000 قيد مزدوج
    // ignore: avoid_print
    print('د0 العينة: ${parties.length} طرفاً و${items.length} صنف '
        'و${moves.length} قيد (${moves.length * 2} رجل)');

    // ═══ 2) فتح القاعدة وبلع الأطراف والأصناف. ═══
    final openWatch = Stopwatch()..start();
    final db = DiqqahDatabase(filePath: dbPath);
    await db.customSelect('SELECT 1').get();
    openWatch.stop();
    // ignore: avoid_print
    print('د0 القياس — فتح القاعدة أول مرة: '
        '${openWatch.elapsedMilliseconds}ms');

    // حارس مخطط: الفهرس شرط القياس (v29) — غيابه يعني عينةً على
    // مخطط قبل د0 فقياسُها بلا معنى (م-٤: كل دفعة تُقاس على أداء
    // معلوم).
    final ix = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'ix_move_lines_move_id'").get();
    expect(ix, hasLength(1),
        reason: 'فهرس move_id (v29) شرط قياس العينة الكاملة');

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

    // ═══ 3) القيود بمسار القاعدة القانوني حصراً: مسودة ثم أسطر ثم ═══
    // ═══ ترحيل بUPDATE يحكّمه trg_moves_post_balance (DQ-0101/0102) ═══
    // ═══ — على دفعات مقيّدة الذاكرة بقراءتِ معرّفاتها بعد كل دفعة. ═══
    final journalId = (await db.select(db.journals).get()).first.id;
    final loadWatch = Stopwatch()..start();
    var maxMoveId = 0;
    for (var start = 0; start < moves.length; start += chunkMoves) {
      final end = (start + chunkMoves) < moves.length
          ? (start + chunkMoves)
          : moves.length;
      final chunk = moves.sublist(start, end);
      await db.batch((batch) {
        batch.insertAll(db.moves, [
          for (final m in chunk)
            MovesCompanion.insert(
              journalId: journalId,
              dateText: m.dateText,
              state: 'draft',
              number: m.number,
              uuid: 'uuid-${m.number}',
            ),
        ]);
      });
      final idRows = await db.customSelect(
          "SELECT id, number FROM moves WHERE number LIKE 'SH-%' "
          'AND id > ? ORDER BY id',
          variables: [Variable.withInt(maxMoveId)]).get();
      expect(idRows, hasLength(chunk.length),
          reason: 'دفعة ${start ~/ chunkMoves + 1}: كل قيد الدفعة '
              'لها معرّف مرجعي بالترتيب');
      await db.batch((batch) {
        for (final m in chunk) {
          final id = idByNumberOf(idRows, m.number);
          batch.insert(db.moveLines, MoveLinesCompanion.insert(
              moveId: id,
              accountId: m.debitAccountId,
              debitMinor: Value(m.amountMinor),
              creditMinor: const Value(0),
              uuid: 'uuid-${m.number}-d'));
          batch.insert(db.moveLines, MoveLinesCompanion.insert(
              moveId: id,
              accountId: m.creditAccountId,
              debitMinor: const Value(0),
              creditMinor: Value(m.amountMinor),
              uuid: 'uuid-${m.number}-c'));
        }
      });
      maxMoveId = idRows.last.data['id'] as int;
      if ((start ~/ chunkMoves) % 20 == 19) {
        // ignore: avoid_print
        print('د0 البلع: $end/$moves.length قيد — '
            '${loadWatch.elapsedMilliseconds}ms');
      }
    }
    final postWatch = Stopwatch()..start();
    await db.customStatement(
        "UPDATE moves SET state = 'posted' WHERE number LIKE 'SH-%'");
    postWatch.stop();
    loadWatch.stop();
    // ignore: avoid_print
    print('د0 القياس — الترحيل الكامل (زنادا التوازن بالمؤشر): '
        '${postWatch.elapsedMilliseconds}ms — البلع كله: '
        '${loadWatch.elapsedMilliseconds}ms');

    // ═══ 4) معايير السلامة الحاكمة (معايير النجاح الخمسة 1..2). ═══
    final ic = await db.customSelect('PRAGMA integrity_check').get();
    expect(ic.single.data['integrity_check'], 'ok',
        reason: 'معيار النجاح 1: سلامة البيانات بعد العينة الكاملة');
    final postedCount = await db.customSelect(
        "SELECT COUNT(*) AS c FROM moves WHERE state = 'posted'")
        .getSingle();
    expect(postedCount.data['c'], moves.length);
    final lineCount = await db.customSelect(
        'SELECT COUNT(*) AS c FROM move_lines').getSingle();
    expect(lineCount.data['c'], moves.length * 2);
    final expectedTotal = moves.fold<int>(0, (s, m) => s + m.amountMinor);
    final sums = await db.customSelect(
        'SELECT COALESCE(SUM(debit_minor),0) AS d, '
        'COALESCE(SUM(credit_minor),0) AS c FROM move_lines').getSingle();
    expect(sums.data['d'], expectedTotal, reason: 'الميزان متوازن');
    expect(sums.data['c'], expectedTotal, reason: 'الميزان متوازن');

    // ═══ 5) القياسات الثلاثة للتقرير — تُطبع ولا تُقرر (البوابة ═══
    // ═══ بتصديق المالك المكتوب حصراً — D-211). ═══
    final partyExactWatch = Stopwatch()..start();
    await db.customSelect(
        "SELECT id FROM parties WHERE number = 'C002750'").getSingle();
    partyExactWatch.stop();
    final partySearchWatch = Stopwatch()..start();
    final partyHits = await db.customSelect(
        "SELECT id FROM parties WHERE name LIKE '%عميل رقم 2700%'").get();
    partySearchWatch.stop();
    final itemSearchWatch = Stopwatch()..start();
    await db.customSelect(
        "SELECT id FROM items WHERE sku = 'P008000'").getSingle();
    itemSearchWatch.stop();
    final balanceWatch = Stopwatch()..start();
    final grouped = await db.customSelect(
        'SELECT account_id, SUM(debit_minor) AS d, SUM(credit_minor) AS c '
        'FROM move_lines GROUP BY account_id').get();
    balanceWatch.stop();
    expect(partyHits, isNotEmpty);
    expect(grouped.length, greaterThanOrEqualTo(2));
    // حارس الانحدار المتساهل بالجهاز (نمط س156) — أضعاف أبطأ من
    // العتبة فتفرّق العلة الكبيرة عن ضجيج الجهاز.
    expect(partySearchWatch.elapsed, lessThan(const Duration(seconds: 10)),
        reason: 'البحث بالجهاز استغرق ${partySearchWatch.elapsed}');
    expect(balanceWatch.elapsed, lessThan(const Duration(seconds: 30)),
        reason: 'الميزان بالجهاز استغرق ${balanceWatch.elapsed}');

    // ═══ 6) جدول البوابة — يُنسخ كما هو إلى التصديق المكتوب. ═══
    // ignore: avoid_print
    print('════ جدول بوابة د0 (العينة الكاملة — تصديق المالك) ════');
    // ignore: avoid_print
    print('بحث طرف بالرقم: ${partyExactWatch.elapsedMilliseconds}ms '
        '(العتبة <300ms) — بحث بالاسم: '
        '${partySearchWatch.elapsedMilliseconds}ms');
    // ignore: avoid_print
    print('بحث صنف بالكود: ${itemSearchWatch.elapsedMilliseconds}ms '
        '(العتبة <300ms)');
    // ignore: avoid_print
    print('ميزان المراجعة (تجميع مليون رجل): '
        '${balanceWatch.elapsedMilliseconds}ms (العتبة <1000ms)');
    // ignore: avoid_print
    print('فتح القاعدة: ${openWatch.elapsedMilliseconds}ms — الترحيل: '
        '${postWatch.elapsedMilliseconds}ms — integrity_check=ok');
    // ignore: avoid_print
    print('«فتح التطبيق <3ث» بروتوكوله الميداني المستقل (بوابة F-016) '
        '— وعينة سنة العمل الممتلئة موضعها د6 بنص الخارطة');

    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 45)));
}

/// معرف القيد برقمه من صفوف الدفعة المُعادة (بنائها ترتيب الإدراج).
int idByNumberOf(List<QueryRow> rows, String number) {
  for (final r in rows) {
    if ((r.data['number'] as String) == number) {
      return r.data['id'] as int;
    }
  }
  throw StateError('معرف القيد $number غائب عن دفعته — فجوة بلع');
}
