import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart' show BackupCipher, BackupKind;
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// F-150/D-210 P0 (س148) — الاختبار الحي الكامل على دمج SQLite3MultipleCiphers
/// (hooks user_defines sqlite3mc — توثيق drift 2.32+):
/// - P0-ب: الفتح المشفر بالمفتاح العشوائي من الخزنة + حارس `PRAGMA cipher`
///   + إثبات بايتي أن الملف لم يعد نص صريح + الترحيل عند أول فتح بفشل آمن.
/// - P0-أ: إثبات المفهوم بالنمطين (chacha20 المعتمد د-٢ وتوافق sqlcipher
///   CBC+HMAC) مع قياس حي مطبوع — بيئة القياس عُدّة CI الحاكمة، والقياس
///   على جهاز منخفض المواصفات بيد المالك بعدها (حد صادق موثق بس148).
/// - P0-ج: النسخة تُفك على جهاز ثانٍ (مفتاح خزنته يخالف) — جيل v2 بمفتاح
///   البرنامج D-060 باقٍ حرفاً ولقطة الرجوع نص صريح كما كانت.
void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_enc_app_test_');
  });
  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String pathOf(String name) => p.join(tempDir.path, name);

  Future<void> insertProbe(DiqqahDatabase db, String value) async {
    await db.customStatement(
        "INSERT INTO app_meta (key, value) VALUES ('enc.probe', '$value')");
  }

  Future<String?> readProbe(DiqqahDatabase db) async {
    final rows = await db
        .customSelect(
            "SELECT value FROM app_meta WHERE key = 'enc.probe'")
        .get();
    return rows.isEmpty ? null : rows.first.data['value'] as String?;
  }

  group('P0-ب: الفتح المشفر والمفتاح من الخزنة', () {
    test('قاعدة جديدة مشفرة: PRAGMA cipher حاضرة والبايتات ليست نصاً صريحاً '
        'والفتح التالي بالمفتاح ذاته يقرأ البيانات', () async {
      final dbPath = pathOf('fresh.db');
      final db =
          DiqqahDatabase.fileSyncClose(filePath: dbPath, keyVault: FixedKeyVault.seed('k1'));
      await insertProbe(db, 'بيانات-عربية-مشفرة');
      // فحص debug بـ`PRAGMA cipher` — الحارس حي على الاتصال الفعلي.
      final cipher =
          await db.customSelect('PRAGMA cipher;').get();
      expect(cipher, isNotEmpty);
      await db.close();

      // الإثبات البايتي: الملف لم يعد يحمل سحر SQLite فليس نصاً صريحاً.
      expect(fileIsPlaintextSqlite(dbPath), isFalse);

      final reopened =
          DiqqahDatabase.fileSyncClose(filePath: dbPath, keyVault: FixedKeyVault.seed('k1'));
      expect(await readProbe(reopened), 'بيانات-عربية-مشفرة',
          reason: 'المفتاح الصحيح من الخزنة يفتح ويقرأ');
      await reopened.close();
    });

    test('ترحيل النص الصريح عند أول فتح: لقطة preenc والبيانات باقية '
        'والملف صار مشفراً (المثبتون فوق حزم سابقة)', () async {
      final dbPath = pathOf('legacy.db');
      // قاعدة الجيل السابق: نص صريح كما تُكتب بحزم ما قبل س148.
      final legacy = DiqqahDatabase.fileSyncClose(filePath: dbPath);
      await insertProbe(legacy, 'قيمة-الترحيل');
      await legacy.close();
      expect(fileIsPlaintextSqlite(dbPath), isTrue);

      final db =
          DiqqahDatabase.fileSyncClose(filePath: dbPath, keyVault: FixedKeyVault.seed('mig'));
      expect(await readProbe(db), 'قيمة-الترحيل',
          reason: 'الترحيل يحفظ البيانات كاملة');
      expect(fileIsPlaintextSqlite(dbPath), isFalse,
          reason: 'الملف صار مشفراً بعد أول فتح');
      expect(await File('$dbPath.preenc').exists(), isTrue,
          reason: 'لقطة الأمان قبل التشفير محفوظة');
      await db.close();
    });

    test('مفتاح خاطئ من خزنة أخرى: الفتح يرفض بصوت عالٍ', () async {
      final dbPath = pathOf('locked.db');
      final db = DiqqahDatabase.fileSyncClose(
          filePath: dbPath, keyVault: FixedKeyVault.seed('real-key'));
      await insertProbe(db, 'v');
      await db.close();

      final wrong = DiqqahDatabase.fileSyncClose(
          filePath: dbPath, keyVault: FixedKeyVault.seed('wrong-key'));
      await expectLater(wrong.customStatement('SELECT 1'),
          throwsA(isA<Exception>()),
          reason: 'القاعدة المشفرة لا تُفتح بمفتاح خزنة مختلف');
      try {
        await wrong.close();
      } catch (_) {}
    });
  });

  group('P0-ج: النسخ والاستعادة مع التشفير', () {
    test('نسخة تُفك على جهاز ثانٍ بمفتاح خزنة يخالف ويلقطة الرجوع نص صريح',
        () async {
      final dbPath = pathOf('cross.db');
      final db = DiqqahDatabase.fileSyncClose(
          filePath: dbPath, keyVault: FixedKeyVault.seed('device-one'));
      await insertProbe(db, 'بيانات-الجهاز-الأول');

      // النسخة بجيل v2 بمفتاح البرنامج D-060 — صورة صريحة تُغلف لا بايتات
      // القاعدة المشفرة بمفتاح الجهاز (درس النقاش المُسد بس147).
      final target = pathOf('cross-backup.v2');
      await backupTo(db, target);
      final blob = await File(target).readAsBytes();
      expect(BackupCipher.identify(blob), BackupKind.encrypted,
          reason: 'النسخة بغلاف v2 المعتاد');

      final candidate = await prepareRestore(target,
          appSchemaVersion: DiqqahDatabase.schemaVersionValue);
      final snapshotPath = await applyRestore(
        db: db,
        candidate: candidate,
        currentDbPath: dbPath,
        sourcePath: target,
      );
      candidate.dispose();

      expect(fileIsPlaintextSqlite(snapshotPath), isTrue,
          reason: 'لقطة ما قبل الاستعادة تبقى SQLite خام كما كانت — '
              'زر التراجع بالمسار القائم');

      // الجهاز الثاني: خزنته مفتاح يخالف — الاستعادة تُفتح نصاً صريحاً
      // فترحَّل إلى التشفير بمفتاح خزنته هو عند أول فتح.
      final second = DiqqahDatabase.fileSyncClose(
          filePath: dbPath, keyVault: FixedKeyVault.seed('device-two'));
      expect(await readProbe(second), 'بيانات-الجهاز-الأول',
          reason: 'فك النسخة على جهاز ثانٍ — معيار قبول P0-ج');
      expect(fileIsPlaintextSqlite(dbPath), isFalse,
          reason: 'الاستعادة تعيد التشفير محلياً عند أول فتح');
      expect(await File('$dbPath.preenc').exists(), isTrue);
      await second.close();
    });
  });

  group('P0-أ: إثبات المفهوم بالنمطين مع قياس حي', () {
    Future<void> runScheme(String scheme) async {
      final dbPath = pathOf('poc-$scheme.db');
      final keyHex = dbKeyHexOf(generateDbKey());

      // الإنشاء والإدراج — النمط يُثبَّت قبل المفتاح (توثيق MC).
      final sw = Stopwatch()..start();
      final w = sqlite3.open(dbPath);
      w.execute("PRAGMA cipher = '$scheme'");
      w.execute(dbKeyPragmaRaw(keyHex));
      w.execute(
          'CREATE TABLE poc (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
          'val TEXT NOT NULL)');
      for (var i = 0; i < 300; i++) {
        w.execute(
            "INSERT INTO poc (name, val) VALUES ('صنف-$i', 'قيمة-$i')");
      }
      final writeMs = sw.elapsedMilliseconds;
      sw
        ..reset()
        ..start();
      final scan = w.select(
          'SELECT count(*) AS c, sum(length(val)) AS s FROM poc');
      final scanMs = sw.elapsedMilliseconds;
      expect(scan.first['c'], 300);
      w.close();

      // الفتح التالي بالمفتاح الصحيح — الوقت الكلي للفتح حتى أول قراءة.
      sw
        ..reset()
        ..start();
      final r = sqlite3.open(dbPath);
      r.execute("PRAGMA cipher = '$scheme'");
      r.execute(dbKeyPragmaRaw(keyHex));
      final count = r.select('SELECT count(*) FROM poc').first.values.first;
      final openMs = sw.elapsedMilliseconds;
      expect(count, 300);
      r.close();

      // المفتاح الخاطئ يرفض عند أول قراءة (الاشتقاق JIT بالتوثيق).
      final w2 = sqlite3.open(dbPath);
      w2.execute("PRAGMA cipher = '$scheme'");
      w2.execute(dbKeyPragmaRaw('bb' * kDbKeyBytes));
      expect(
        () => w2.select('SELECT count(*) FROM sqlite_master'),
        throwsA(isA<SqliteException>()),
      );
      w2.close();

      // ignore: avoid_print
      print('P0-أ نمط $scheme: فتح+قراءة ${openMs}ms، إدراج 300 صف '
          '${writeMs}ms، فحص كامل ${scanMs}ms — عُدّة CI الحاكمة');
    }

    test('النمط المعتمد chacha20 (ChaCha20-Poly1305 AEAD — د-٢)', () async {
      await runScheme('chacha20');
    });

    test('النمط الثاني sqlcipher (توافق CBC+HMAC — مقارنة القياس)', () async {
      await runScheme('sqlcipher');
    });
  });
}
