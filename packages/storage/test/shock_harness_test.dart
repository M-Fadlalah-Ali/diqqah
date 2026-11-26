// اختبارات الحافظات الآلية للصدمة — الشطر التخزيني (س156، D-211).
//
// الفئة 5: حافظة الملفات التالف الموحدة — عبث بايت واحد بالنسخ المشفرة
// والقاعدة الخام واللغم الحدثي والقص والفراغ، والاستعادة المقتولة
// بمحاكاة الفجوة بين اللقطة والاستبدال ثم التعافي باللقطة ذاتها.
// الفئة 7 (الشطر التخزيني): الإجراء المتعطل برسالة وتعارض كتابة
// باتصالين يُكشف صوتاً. الفئة 1 (الشطر التخزيني): عينة الضغط بمقياس
// CI الموثق 0.1 — العينة الكاملة >500MB قياسات جهاز حقيقي حصراً.
//
// المرساة قائم سلفاً فالاعتماد يُسنده (نص س155): F-013 الملف التالف،
// F-156 مخطط أحدث وأقدم، لقطة الترقية الذرية، النسخة المقفلة v3،
// ووسوم GCM بbackup_test/integrity_test/upgrade_snapshot_test.
//
// الحاكم: معايير نجاح الصدمة الخمسة (10 §10) — integrity_check=ok
// بعد كل صدمة، والذرية، والتعافي، والرسائل الواضحة، والأداء بحارس
// انحدار متساهل بالCI (نمط party_test — العتبات المطلقة جهاز حقيقي).
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
    tempDir = await Directory.systemTemp.createTemp('diqqah_shock_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-001',
            name: 'بضاعة عينة الصدمة',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 1000,
            salePriceMinor: 1500,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-shock-001',
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String q(String path) => path.replaceAll("'", "''");

  /// نسخة احتياطية افتراضية (v2 مشفرة بمفتاح البرنامج — D-060).
  Future<String> makeBackup(String name) async {
    final target = p.join(tempDir.path, name);
    await backupTo(db, target);
    return target;
  }

  /// رفض بوابة الاستعادة لملف تالف — مع البقاء صوتاً بلا فساد صامت.
  Future<void> expectRestoreRejects(String path, String why) async {
    Object? rejection;
    try {
      await prepareRestore(path, appSchemaVersion: db.schemaVersion);
    } catch (e) {
      rejection = e;
    }
    expect(rejection, isNotNull, reason: '$why: التالف نجح في البوابة فجوة');
    expect(rejection.toString(), isNotEmpty,
        reason: '$why: الرفض بلا رسالة — رسالة غامضة ممنوعة (معيار 5)');
  }

  /// القاعدة الحية لم تُمس بعد كل صدمة — معيار سلامة البيانات.
  Future<void> expectLiveDbIntact() async {
    final ic = await db.customSelect('PRAGMA integrity_check').get();
    expect(ic.single.data['integrity_check'], 'ok',
        reason: 'القاعدة الحية سليمة بعد الصدمة');
    final items = await db.select(db.items).get();
    expect(items.where((i) => i.sku == 'SKU-001'), isNotEmpty,
        reason: 'مادة العينة الحية باقية');
  }

  group('الفئة 5 — حافظة الملفات التالف الموحدة', () {
    test('عبث بايت واحد وسط النسخة المشفرة: وسم GCM يرفض والحي سليم',
        () async {
      final target = await makeBackup('v2-middle.diqqah');
      final bytes = await File(target).readAsBytes();
      final mid = bytes.length ~/ 2;
      final corrupted = CorruptedArtifacts.flipByteAt(bytes, mid);
      expect(corrupted[mid] == bytes[mid], isFalse,
          reason: 'عقلنة التلف: البايت تغيّر فعلاً');
      final corruptPath = p.join(tempDir.path, 'v2-middle-corrupt.diqqah');
      await File(corruptPath).writeAsBytes(corrupted);
      await expectRestoreRejects(corruptPath, 'عبث وسط النسخة');
      await expectLiveDbIntact();
    });

    test('عبث البايت الأول (الترويسة): رفض التعرف لا تخمين', () async {
      final target = await makeBackup('v2-head.diqqah');
      final bytes = await File(target).readAsBytes();
      final corruptPath = p.join(tempDir.path, 'v2-head-corrupt.diqqah');
      await File(corruptPath)
          .writeAsBytes(CorruptedArtifacts.flipByteAt(bytes, 0));
      await expectRestoreRejects(corruptPath, 'عبث الترويسة');
      await expectLiveDbIntact();
    });

    test('القص: نصف الملف مقطوع يُرفض — قصور النقل لا فساد صامت',
        () async {
      final target = await makeBackup('v2-half.diqqah');
      final bytes = await File(target).readAsBytes();
      final corruptPath = p.join(tempDir.path, 'v2-half-corrupt.diqqah');
      await File(corruptPath)
          .writeAsBytes(CorruptedArtifacts.truncateHalf(bytes));
      await expectRestoreRejects(corruptPath, 'قص النصف');
      await expectLiveDbIntact();
    });

    test('الملف الفارغ صفر البايتات يُرفض', () async {
      final corruptPath = p.join(tempDir.path, 'empty.diqqah');
      await File(corruptPath)
          .writeAsBytes(CorruptedArtifacts.emptyBytes());
      await expectRestoreRejects(corruptPath, 'الملف الفارغ');
      await expectLiveDbIntact();
    });

    test('قاعدة خام ببايت مقلوب بنطاق مؤشرات الخلايا: sqlite ذاته '
        'يكشف والبوابة ترفض', () async {
      // قاعدة خام حقيقية بمحتوى يملأ صفحات — العقلنة أولاً أن sqlite
      // نفسها تعلن الفساد قبل البوابة (المرجع أصيل لا ادعاء).
      final rawPath = p.join(tempDir.path, 'raw-corrupt.db');
      final raw = sql.sqlite3.open(rawPath);
      raw.execute('CREATE TABLE t(a TEXT, b INTEGER)');
      raw.execute('BEGIN');
      for (var i = 0; i < 500; i++) {
        raw.execute("INSERT INTO t VALUES ('بيان الخلية $i', $i)");
      }
      raw.execute('COMMIT');
      raw.close();
      final bytes = await File(rawPath).readAsBytes();
      expect(bytes.length, greaterThan(512),
          reason: 'القاعدة خام بعدد صفحات يابسة للعقلنة');
      // أول مؤشر خلية بعد الترويسة الـ100 — نطاق بنية لا فراغ.
      final corruptPath = p.join(tempDir.path, 'raw-corrupt-flipped.db');
      await File(corruptPath)
          .writeAsBytes(CorruptedArtifacts.flipByteAt(bytes, 105));
      final rawCheck = sql.sqlite3.open(corruptPath);
      final verdict =
          rawCheck.select('PRAGMA integrity_check').first.values.first;
      rawCheck.close();
      expect(verdict, isNot('ok'),
          reason: 'عقلنة الحافظة: sqlite ذاته يكشف العبث البنيوي');
      await expectRestoreRejects(corruptPath, 'قاعدة خام مفلطح البنية');
      await expectLiveDbIntact();
    });

    test('لغم سجل الأحداث p3: بايت مقلوب بالسجل المختوم → DQ-1108 '
        'لا نص ملفق ولا انهيار', () async {
      final cipher = LogCipher();
      const salt = '0123456789abcdef0123456789abcdef';
      final sealed =
          await cipher.seal('{"entity":"move","amount":123}', salt);
      final sealedBytes = utf8.encode(sealed);
      final corruptedBytes = CorruptedArtifacts.flipByteAt(
          sealedBytes, sealedBytes.length ~/ 2);
      Object? rejection;
      try {
        await cipher.open(utf8.decode(corruptedBytes), salt);
      } catch (e) {
        rejection = e;
      }
      expect(rejection, isA<LogCipherIntegrityException>(),
          reason: 'اللغم برمز الصدمة المعروف لا استثناء خام');
      expect(rejection.toString(), contains('DQ-1108'),
          reason: 'الرمز الموثق بالرسالة — لا غموض');
    });

    test('الاستعادة المقتولة: الفجوة بين اللقطة والاستبدال تُترك '
        'بقايا آتة واللقطة مرجع الاستعادة والتعافي يتم بمر البوابة ذاته',
        () async {
      final target = await makeBackup('killed-src.diqqah');
      final candidate =
          await prepareRestore(target, appSchemaVersion: db.schemaVersion);

      // محاكاة applyRestore حتى ما قبل الاستبدال ثم «القتل»:
      // لقطة الرجوع أولاً (VACUUM INTO — عين ما تفعله الاستعادة).
      final snapshotPath =
          p.join(tempDir.path, 'diqqah-before-restore-SIM.db');
      await db.customStatement("VACUUM INTO '${q(snapshotPath)}'");
      await db.close();
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) await f.delete();
      }
      // الملف الوسيط يُنسخ ثم يموت التشغيل قبل إعادة التسمية.
      await File(candidate.plainPath).copy('$dbPath.restoring');

      // البقايا آتة: الوسيط موجود بلا أثر فساد، واللقطة سليمة خاماً.
      expect(await File('$dbPath.restoring').exists(), isTrue,
          reason: 'بقايا القتل موجودة — والنظام القادم لا يخدعها');
      final rawSnapshot = sql.sqlite3.open(snapshotPath);
      expect(
          rawSnapshot.select('PRAGMA integrity_check').first.values.first,
          'ok',
          reason: 'لقطة ما قبل الاستعادة — طريق الرجوع الوحيد — سليمة');
      rawSnapshot.close();

      // التعافي: اللقطة تمر بوابة الاستعادة ذاتها ثم الاستبدال الذري.
      final db2 = DiqqahDatabase(filePath: dbPath);
      final recovery = await prepareRestore(snapshotPath,
          appSchemaVersion: db2.schemaVersion);
      await applyRestore(
          db: db2, candidate: recovery, currentDbPath: dbPath);
      final db3 = DiqqahDatabase(filePath: dbPath);
      final items = await db3.select(db3.items).get();
      expect(items.where((i) => i.sku == 'SKU-001'), isNotEmpty,
          reason: 'التعافي أعاد حالة ما قبل الصدمة حرفاً');
      final gate = await db3.customSelect(
          "SELECT value FROM app_meta WHERE key = 'restore.gate'").get();
      expect(gate, isNotEmpty,
          reason: 'بوابة الاستعادة مزروعة بعد الاستعادة (عرف D-054)');
      await db3.close();
      db = DiqqahDatabase(filePath: dbPath);
      await expectLiveDbIntact();
    });
  });

  group('الفئة 7 — التزامن (الشطر التخزيني)', () {
    test('الإجراء المتعطل: النسخ داخل معاملة مفتوحة يُرفض برسالة '
        'والمعاملة تُدار لا تنكسر', () async {
      var blocked = false;
      var blockedMessage = '';
      await db.transaction(() async {
        await db.into(db.items).insert(
              ItemsCompanion.insert(
                sku: 'SKU-B1',
                name: 'قبل التعطيل',
                kind: 'good',
                baseUnitId: 1,
                purchasePriceMinor: 0,
                salePriceMinor: 100,
                priceCurrencyId: 1,
                isActive: true,
                uuid: 'uuid-b1',
              ),
            );
        try {
          await backupTo(db, p.join(tempDir.path, 'inside-tx.diqqah'));
        } catch (e) {
          blocked = true;
          blockedMessage = e.toString();
        }
        await db.into(db.items).insert(
              ItemsCompanion.insert(
                sku: 'SKU-B2',
                name: 'بعد التعطيل',
                kind: 'good',
                baseUnitId: 1,
                purchasePriceMinor: 0,
                salePriceMinor: 100,
                priceCurrencyId: 1,
                isActive: true,
                uuid: 'uuid-b2',
              ),
            );
      });
      expect(blocked, isTrue,
          reason: 'VACUUM داخل معاملة يرفض SQLite — الإجراء يُعطَّل '
              'برسالة لا صمتاً (10 §10 بند 7)');
      expect(blockedMessage, isNotEmpty, reason: 'الرسالة صريحة');
      final skus =
          (await db.select(db.items).get()).map((i) => i.sku).toSet();
      expect(skus, containsAll(['SKU-B1', 'SKU-B2']),
          reason: 'المعاملة استكملت بعد التعطيل المُدار — الذرية سليمة');
      await expectLiveDbIntact();
    });

    test('تعارض كتابة باتصالين: الكاتب الثاني يُرفض صوتاً (SQLITE_BUSY) '
        'والقاعدة سليمة بلا فساد', () async {
      final second = sql.sqlite3.open(dbPath);
      await db.customStatement('BEGIN IMMEDIATE');
      var secondRejected = false;
      var secondMessage = '';
      try {
        second.execute('BEGIN IMMEDIATE');
      } catch (e) {
        secondRejected = true;
        secondMessage = e.toString();
      }
      expect(secondRejected, isTrue,
          reason: 'كاتب ثانٍ على القاعدة ذاتها يُكشف صوتاً لا صمتاً');
      expect(secondMessage, isNotEmpty);
      await db.customStatement('ROLLBACK');
      // تحرر القفل: الثاني يكتب الآن بلا تعارض — التسلسل لا الفساد.
      second.execute('BEGIN IMMEDIATE');
      second.execute("CREATE TABLE IF NOT EXISTS shock_probe (a)");
      second.execute('ROLLBACK');
      second.close();
      final ic = await db.customSelect('PRAGMA integrity_check').get();
      expect(ic.single.data['integrity_check'], 'ok',
          reason: 'السلامة بعد التعارض — معيار النجاح الأول');
    });
  });

  group('الفئة 1 — الشطر التخزيني لعينة الضغط (مقياس CI الموثق 0.1)', () {
    test('القاعدة تبتلع 550 عميلاً و100 مورد و1,000 صنف و50,000 قيد '
        'مزدوج بسلامة كاملة وعدادات حرفاً', () async {
      final accounts = await db.select(db.accounts).get();
      final leaves =
          accounts.where((a) => a.isLeaf && a.isActive).toList();
      expect(leaves.length, greaterThanOrEqualTo(2),
          reason: 'الدليل المزروع يحمل ورقية كافية للعينة');
      final debitAcc = leaves.first.id;
      final creditAcc = leaves.last.id;
      final journalId = (await db.select(db.journals).get()).first.id;

      final parties = generateHeavyParties(scale: 0.1);
      final items = generateHeavyItems(scale: 0.1);
      final moves = generateHeavyMoves(
        scale: 0.1,
        debitAccountId: debitAcc,
        creditAccountId: creditAcc,
      );
      expect(parties, hasLength(650));
      expect(items, hasLength(1000));
      expect(moves, hasLength(50000));

      final watch = Stopwatch()..start();
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
        batch.insertAll(db.moves, [
          for (final m in moves)
            MovesCompanion.insert(
              journalId: journalId,
              dateText: m.dateText,
              // المسودة أولاً: عرف القاعدة نفسها — الأسطر للمرحّل
              // ممنوعة (DQ-0105) فالبلع بمسار القاعدة القانوني:
              // مسودة ثم أسطر ثم ترحيل بUPDATE يحكّمه trg_moves_post_balance
              // (DQ-0101/0102) فيتحقق توازن العينة عتاد القاعدة ذاته.
              state: 'draft',
              number: m.number,
              uuid: 'uuid-${m.number}',
            ),
        ]);
      });
      final moveIdRows = await db.customSelect(
          "SELECT id, number FROM moves WHERE number LIKE 'SH-%'").get();
      expect(moveIdRows, hasLength(50000),
          reason: 'كل قيد العينة له معرّف مرجعي بالرقم');
      final idByNumber = <String, int>{
        for (final r in moveIdRows)
          r.data['number'] as String: r.data['id'] as int,
      };
      await db.batch((batch) {
        for (final m in moves) {
          final id = idByNumber[m.number]!;
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
      // د0 (س160): الفهرس صار مخططاً — ترحيلة v29 تبني ix_move_lines_move_id
      // من أول إنشاء ومن الترقية، فما كان محلياً بالاختبار حصراً (أداة
      // قياس س156 — اكتشاف O(N²) الموثق بسجل العمل) هو اليوم عتاد
      // القاعدة ذاته والترحيل أدناه على فحص توازن بالمؤشر حرفاً —
      // وغَيابُ الفهرس يُثبت الاختبارُ نفسُه بالانحدار المطبوع
      // (المرشح انتهى بموضعه د0 أولى خارطة م4).
      final ixBefore = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'ix_move_lines_move_id'").get();
      expect(ixBefore, hasLength(1),
          reason: 'فهرس move_id مخطط v29 حاضر قبل الترحيل');
      // الترحيل: عتاد القاعدة يحكّم توازن كل قيد قبل القبول.
      await db.customStatement(
          "UPDATE moves SET state = 'posted' WHERE number LIKE 'SH-%'");
      watch.stop();
      // ignore: avoid_print
      print('عينة الضغط مقياس 0.1: 50,000 قيد و100,000 رجل كتبت في '
          '${watch.elapsedMilliseconds}ms');

      // معيار النجاح 1: سلامة البيانات بعد الصدمة.
      final ic = await db.customSelect('PRAGMA integrity_check').get();
      expect(ic.single.data['integrity_check'], 'ok');

      // العدادات حرفاً.
      final partyCount = await db.customSelect(
          'SELECT COUNT(*) AS c FROM parties').getSingle();
      expect(partyCount.data['c'], 650);
      final itemCount = await db.customSelect(
          "SELECT COUNT(*) AS c FROM items WHERE sku LIKE 'P%'").getSingle();
      expect(itemCount.data['c'], 1000,
          reason: 'بذرة الصدمة SKU-001 خارج العينات المولدة حصراً');
      final moveCount = await db.customSelect(
          'SELECT COUNT(*) AS c FROM moves WHERE state = ' + "'posted'").getSingle();
      expect(moveCount.data['c'], 50000,
          reason: 'الترحيل عتاد القاعدة قبِل العينة كاملة');
      final lineCount = await db.customSelect(
          'SELECT COUNT(*) AS c FROM move_lines').getSingle();
      expect(lineCount.data['c'], 100000);

      // الميزان المزدوج: مجموع SQL يساوي حساب dart حرفاً — لا غبار.
      final expectedTotal = moves.fold<int>(0, (s, m) => s + m.amountMinor);
      final sums = await db.customSelect(
          'SELECT COALESCE(SUM(debit_minor),0) AS d, '
          'COALESCE(SUM(credit_minor),0) AS c FROM move_lines').getSingle();
      expect(sums.data['d'], expectedTotal);
      expect(sums.data['c'], expectedTotal);

      // معيار النجاح 4 بحارس انحدار: البحث والتجميع أضعاف أسرع من
      // الحد المتساهل — والارتفاع عنه علة انحدار (العتبات المطلقة
      // <300ms/<1s على العينة الثقيلة جهاز حقيقي عند البوابات حصراً).
      final searchWatch = Stopwatch()..start();
      final hits = await db.customSelect(
          "SELECT id FROM parties WHERE name LIKE '%رقم 550%'").get();
      searchWatch.stop();
      expect(hits, isNotEmpty, reason: 'العميل 550 موجود بالعينة');
      expect(searchWatch.elapsed, lessThan(const Duration(seconds: 10)),
          reason: 'البحث عند عينة CI استغرق ${searchWatch.elapsed}');
      final balanceWatch = Stopwatch()..start();
      final grouped = await db.customSelect(
          'SELECT account_id, SUM(debit_minor) AS d, SUM(credit_minor) AS c '
          'FROM move_lines GROUP BY account_id').get();
      balanceWatch.stop();
      expect(grouped.length, greaterThanOrEqualTo(2));
      expect(balanceWatch.elapsed, lessThan(const Duration(seconds: 10)),
          reason: 'تجميع الميزان عند عينة CI استغرق ${balanceWatch.elapsed}');
      // ignore: avoid_print
      print('القياسات: بحث ${searchWatch.elapsedMilliseconds}ms — '
          'ميزان ${balanceWatch.elapsedMilliseconds}ms');

      // أرضية الحجم: العينة المقيّسة فوق عشر MegaBytes — والعينة
      // الكاملة >500MB قياسها جهاز حقيقي حصراً (حد صادق موثق).
      var totalBytes = 0;
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) totalBytes += await f.length();
      }
      // ignore: avoid_print
      print('حجم القاعدة بالعينة المقيّسة: $totalBytes بايت');
      expect(totalBytes, greaterThan(5 * 1024 * 1024),
          reason: 'أرضية العينة المقيّسة (القياس المرجعي ~9.4MB) — '
              'وأقل من الأرضية يعني بلعاً ناقصاً. حد صادق: عينة القيود '
              'المجردة كاملة المقياس ~100MB، و">500MB" من التقرير المعتمد '
              'بعينة سنة العمل الممتلئة بالمستندات والأحداث عند م4 حصراً');
    });
  });
}
