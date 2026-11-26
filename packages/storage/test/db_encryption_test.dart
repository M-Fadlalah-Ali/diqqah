import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List;

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// F-150/D-210 P0 (س148) — منطق التشفير النقي ببيئة الاختبار المعيارية:
/// sqlite3 النظام بلا دمج تشفير، فحارس البيئة الصوتي العالي يُختبر هنا
/// حرفاً (بلا MC لا ترحيل صامت ولا «مشفرة زائفة») والاكتمال الحي
/// بالترحيل والنسخ على دمج MC يعيش باختبارات حزمة الواجهة
/// (db_encryption_test.dart هناك).

void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_enc_test_');
  });
  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String pathOf(String name) => p.join(tempDir.path, name);

  group('المفتاح وصيغته (F-150: مفتاح عشوائي 256-bit لا في الكود)', () {
    test('generateDbKey يعيد 32 بايت ومفتاحان متواليان يخلفان', () {
      final a = generateDbKey();
      final b = generateDbKey();
      expect(a.length, kDbKeyBytes);
      expect(b.length, kDbKeyBytes);
      expect(a, isNot(equals(b)), reason: 'عشوائية آمنة لا تكرر المفتاح');
    });

    test('صيغة المفتاح الخام: 64 خانة ست عشرية وpragma مطابق للتوثيق', () {
      final key = Uint8List.fromList(
          List.generate(kDbKeyBytes, (i) => (i * 7 + 1) & 0xFF));
      final hexStr = dbKeyHexOf(key);
      expect(hexStr.length, kDbKeyBytes * 2);
      expect(dbKeyPragmaRaw(hexStr),
          "PRAGMA key = \"x'$hexStr'\"");
      // العينة من توثيق SQLCipher/MC للمفتاح الخام — نفس البنية.
      expect(dbKeyPragmaRaw('ABCD'), "PRAGMA key = \"x'ABCD'\"");
    });

    test('FixedKeyVault يعيد مفتاحه ثابتاً وبذرة النص ثباتية', () async {
      final v1 = FixedKeyVault.seed('device-one');
      final v2 = FixedKeyVault.seed('device-one');
      final v3 = FixedKeyVault.seed('device-two');
      expect(await v1.loadOrCreateKey(), await v2.loadOrCreateKey());
      expect(await v1.loadOrCreateKey(), isNot(await v3.loadOrCreateKey()));
    });
  });

  group('التحقق البايتي من النص الصريح (fileIsPlaintextSqlite)', () {
    test('قاعدة نص صريح تمر وملف عشوائي وقصير وغائب يرفض', () async {
      final plainPath = pathOf('plain.db');
      final raw = sqlite3.open(plainPath);
      raw.execute('CREATE TABLE t (x); INSERT INTO t VALUES (1);');
      raw.close();
      expect(fileIsPlaintextSqlite(plainPath), isTrue);

      final garbage = File(pathOf('garbage.db'));
      await garbage.writeAsBytes(
          List.generate(150, (i) => Random().nextInt(256)));
      expect(fileIsPlaintextSqlite(garbage.path), isFalse);

      final short = File(pathOf('short.db'));
      await short.writeAsBytes(List.filled(50, 0x41));
      expect(fileIsPlaintextSqlite(short.path), isFalse);

      expect(fileIsPlaintextSqlite(pathOf('missing.db')), isFalse);
    });
  });

  group('لقطة ما قبل التشفير (نمط preenc — D-197)', () {
    test('لقطة واحدة لا تُستبدل وتحمل الجوانب وغائب لا شيء', () async {
      final dbPath = pathOf('db.db');
      final raw = sqlite3.open(dbPath);
      raw.execute('CREATE TABLE t (x); INSERT INTO t VALUES (1);');
      raw.execute('PRAGMA wal_checkpoint;');
      raw.close();
      await File('$dbPath-wal').writeAsBytes(List.filled(8, 0x57));
      await File('$dbPath-shm').writeAsBytes(List.filled(8, 0x53));

      await snapshotBeforeEncryption(dbPath);
      expect(await File('$dbPath.preenc').readAsBytes(),
          await File(dbPath).readAsBytes(),
          reason: 'اللقطة بايتية مطابقة');
      expect(await File('$dbPath.preenc-wal').exists(), isTrue);
      expect(await File('$dbPath.preenc-shm').exists(), isTrue);

      // لقطة ثانية لا تستبدل الأولى النقية (عقد snapshotBeforeUpgrade).
      await File('$dbPath-wal').writeAsBytes(List.filled(8, 0x58));
      await snapshotBeforeEncryption(dbPath);
      expect(await File('$dbPath.preenc-wal').readAsBytes(),
          List.filled(8, 0x57));
    });

    test('قاعدة غائبة — لا لقطة ولا ملف', () async {
      await snapshotBeforeEncryption(pathOf('nothing.db'));
      expect(await File('${pathOf('nothing.db')}.preenc').exists(), isFalse);
    });
  });

  group('حارس البيئة الصوتي بالترحيل (بلا دمج MC)', () {
    test('بيئة بلا تشفير: النص الصريح يبقى سليماً والمؤقت يُمسح', () async {
      final dbPath = pathOf('legacy.db');
      final raw = sqlite3.open(dbPath);
      raw.execute('CREATE TABLE t (x); INSERT INTO t VALUES (42);');
      raw.close();

      final hasCipher =
          sqlite3.openInMemory().select('PRAGMA cipher;').isNotEmpty;
      if (hasCipher) {
        // بيئة بدمج MC (لو أُضيف لاحقاً لحزمة التخزين) — الترحيل ينجز
        // عمله فلا حارس يرمي هنا؛ الاختبار يتكيف بصدق مع بيئته.
        final migrated =
            await migratePlainToEncrypted(dbPath, 'aa' * kDbKeyBytes);
        expect(migrated, isTrue);
        expect(fileIsPlaintextSqlite(dbPath), isFalse);
        return;
      }

      await expectLater(
        migratePlainToEncrypted(dbPath, 'aa' * kDbKeyBytes),
        throwsA(isA<StateError>()),
      );
      // الأصل كما هو: نص صريح وبياناته مقروءة — فشل آمن بلا مساس.
      expect(fileIsPlaintextSqlite(dbPath), isTrue);
      final after = sqlite3.open(dbPath);
      expect(after.select('SELECT x FROM t').first.values.first, 42);
      after.close();
      expect(await File('$dbPath.enc-migrate-tmp').exists(), isFalse,
          reason: 'المؤقت يُمسح عند أي فشل');
    });

    test('ملف غائب أو غير سليم — لا ترحيل ولا رمي', () async {
      expect(await migratePlainToEncrypted(pathOf('missing.db'), 'aa' * 32),
          isFalse);
      final garbage = File(pathOf('garbage.db'));
      await garbage.writeAsBytes(List.generate(150, (i) => i & 0xFF));
      expect(
          await migratePlainToEncrypted(garbage.path, 'aa' * kDbKeyBytes),
          isFalse);
    });
  });
}
