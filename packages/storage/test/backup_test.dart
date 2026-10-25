import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

import 'package:heseb_domain/heseb_domain.dart';
import 'package:heseb_storage/heseb_storage.dart';

void main() {
  late Directory tempDir;
  late HesebDatabase db;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('heseb_backup_test_');
    dbPath = p.join(tempDir.path, 'heseb.db');
    db = HesebDatabase(filePath: dbPath);
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-001',
            name: 'بضاعة الجهاز المصدر',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 1000,
            salePriceMinor: 1500,
            priceCurrencyId: 1,
            isActive: true,
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ItemsCompanion newItem(String sku, String name) => ItemsCompanion.insert(
        sku: sku,
        name: name,
        kind: 'good',
        baseUnitId: 1,
        purchasePriceMinor: 0,
        salePriceMinor: 100,
        priceCurrencyId: 1,
        isActive: true,
      );

  test('F-012: نسخة غير مشفرة = ملف SQLite خام واحد يحوي بيانات الجهاز الحي',
      () async {
    final target = p.join(tempDir.path, 'b1.db');
    await backupTo(db, target);

    final bytes = await File(target).readAsBytes();
    expect(BackupCipher.identify(bytes), BackupKind.plainSqlite);

    final raw = sql.sqlite3.open(target);
    final count = raw.select('SELECT COUNT(*) FROM items').first.values.first;
    raw.dispose();
    expect(count, 1);
  });

  test('F-012: نسخة مشفرة — ترويسة خاصة، وبلا كلمة المرور أو بخاطئة تُرفض',
      () async {
    final target = p.join(tempDir.path, 'b2.db');
    await backupTo(db, target, password: 'سر-قوي');

    final bytes = await File(target).readAsBytes();
    expect(BackupCipher.identify(bytes), BackupKind.encrypted);

    // بلا كلمة مرور: رفض صريح قبل أي لمس للقاعدة
    await expectLater(
      () async {
        final c = await prepareRestore(target, appSchemaVersion: 2);
        c.dispose();
      }(),
      throwsA(isA<CorruptBackupException>()),
    );
    // كلمة مرور خاطئة: رفض من وسم GCM
    await expectLater(
      () async {
        final c = await prepareRestore(target,
            password: 'الخاطئة', appSchemaVersion: 2);
        c.dispose();
      }(),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('F-013 (الفيصل الثاني): ملف تالف — فشل آمن والقاعدة الحية لم تُمس',
      () async {
    final target = p.join(tempDir.path, 'corrupt.db');
    await backupTo(db, target);
    final bytes = await File(target).readAsBytes();
    // البايت 15 هو خاتمة ترويسة SQLite ("...3\0") — عبثه يبقي التعرف
    // «خام سليم الشكل» لكن SQLite يرفض الملف قطعاً — مسار فشل آمن قاطع.
    bytes[15] ^= 0xFF;
    await File(target).writeAsBytes(bytes, flush: true);

    // «جهاز» حي ببيانات مختلفة — هو الذي سيُستبدل لو مرّ الملف التالف
    final otherPath = p.join(tempDir.path, 'device2.db');
    final other = HesebDatabase(filePath: otherPath);
    await other.into(other.items).insert(newItem('SKU-999', 'بضاعة الجهاز الآخر'));

    await expectLater(
      () async {
        final c = await prepareRestore(target, appSchemaVersion: 2);
        c.dispose();
      }(),
      throwsA(isA<CorruptBackupException>()),
    );

    // الفشل الآمن: بيانات الجهاز الحي كما هي حرفاً
    final rows = await other.select(other.items).get();
    expect(rows, hasLength(1));
    expect(rows.first.sku, 'SKU-999');
    await other.close();
  });

  test('F-013 (الفيصل الأول) + F-154: استعادة بتطابق 100% على جهاز آخر '
      'ولقطة ما قبل الاستعادة بتاريخها هي طريق الرجوع', () async {
    // معرّف المصدر يدخل النسخة — الاستعادة كاملة تشمل app_meta
    final sourceDeviceId = await db.deviceId();

    final target = p.join(tempDir.path, 'travel.db');
    await backupTo(db, target, password: 'سر-السفر');

    // جهاز الهدف: قاعدة أخرى بمستخدم وبيانات مختلفة
    final otherPath = p.join(tempDir.path, 'device2.db');
    final other = HesebDatabase(filePath: otherPath);
    await other.createManager(
        name: 'قديم', login: 'old', passwordHash: 'a:b');
    await other.into(other.items).insert(newItem('SKU-999', 'بضاعة قديمة'));
    final oldDeviceId = await other.deviceId();
    expect(oldDeviceId, isNot(sourceDeviceId));

    final candidate = await prepareRestore(target,
        password: 'سر-السفر', appSchemaVersion: other.schemaVersion);
    final snapshotPath = await applyRestore(
        db: other, candidate: candidate, currentDbPath: otherPath);
    candidate.dispose();

    // سطر الإحالة (F-154): اللقطة موجودة، مسماة بتاريخها، وتحوي بيانات
    // الجهاز القديمة — طريق الرجوع الوحيد سليم
    expect(File(snapshotPath).existsSync(), isTrue);
    expect(p.basename(snapshotPath), startsWith('heseb-before-restore-'));
    final snap = sql.sqlite3.open(snapshotPath);
    final snapSku = snap.select('SELECT sku FROM items').first.values.first;
    snap.dispose();
    expect(snapSku, 'SKU-999');

    // إعادة فتح جهاز الهدف — بيانات المصدر كاملة حرفاً (تطابق 100%)
    final restored = HesebDatabase(filePath: otherPath);
    final items = await restored.select(restored.items).get();
    expect(items, hasLength(1));
    expect(items.first.sku, 'SKU-001');
    expect(items.first.name, 'بضاعة الجهاز المصدر');
    expect(await restored.deviceId(), sourceDeviceId);
    expect(await restored.deviceId(), isNot(oldDeviceId));
    // نسخة المصدر بلا مستخدمين — بوابة F-014 ستعيد التهيئة، وهذا من
    // «كاملاً أو لا شيء»: المستخدمون جزء من الملف لا استثناء
    expect(await restored.hasAnyUser(), isFalse);
    await restored.close();
  });

  test('F-156: نسخة من مخطط أحدث تُرفض برسالة «حدّث التطبيق» قبل أي استبدال',
      () async {
    final newerPath = p.join(tempDir.path, 'newer.db');
    final raw = sql.sqlite3.open(newerPath);
    raw.execute('CREATE TABLE t (x INTEGER)');
    raw.execute('PRAGMA user_version = 3');
    raw.dispose();

    await expectLater(
      () async {
        final c = await prepareRestore(newerPath, appSchemaVersion: 2);
        c.dispose();
      }(),
      throwsA(isA<BackupNewerSchemaException>()),
    );
  });

  test('F-156: فتح قاعدة أحدث مخططاً من التطبيق نفسه يُرفض بحدّث التطبيق',
      () async {
    final newerPath = p.join(tempDir.path, 'newer-live.db');
    final raw = sql.sqlite3.open(newerPath);
    raw.execute('PRAGMA user_version = 9');
    raw.dispose();

    final newer = HesebDatabase(filePath: newerPath);
    await expectLater(
      newer.hasAnyUser(),
      throwsA(isA<HesebNewerSchemaException>()),
    );
    await newer.close();
  });

  test('استعادة مخطط أقدم تمر للترحيلات — v1 تفتح وتُرقّى آلياً إلى v2',
      () async {
    // قاعدة على هيئة v1: items فقط وuser_version=1 — محرك F-011 يرقّى
    final v1Path = p.join(tempDir.path, 'v1.db');
    final raw = sql.sqlite3.open(v1Path);
    raw.execute('''
      CREATE TABLE items (
        sku TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT,
        kind TEXT NOT NULL,
        base_unit_id INTEGER NOT NULL,
        purchase_price_minor INTEGER NOT NULL,
        sale_price_minor INTEGER NOT NULL,
        price_currency_id INTEGER NOT NULL,
        default_tax_id INTEGER,
        is_active INTEGER NOT NULL
      )
    ''');
    raw.execute('''
      INSERT INTO items VALUES
        ('SKU-OLD', 'صنف قديم', NULL, 'good', 1, 0, 500, 1, NULL, 1)
    ''');
    raw.execute('PRAGMA user_version = 1');
    raw.dispose();

    final oldDb = HesebDatabase(filePath: v1Path);
    final rows = await oldDb.select(oldDb.items).get();
    expect(rows, hasLength(1));
    expect(rows.first.sku, 'SKU-OLD');
    // جداول v2 زُرعت بالترحيلة
    expect(await oldDb.hasAnyUser(), isFalse);
    await oldDb.close();
  });
}
