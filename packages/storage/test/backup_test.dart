import 'dart:io';

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
    tempDir = await Directory.systemTemp.createTemp('diqqah_backup_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
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
            uuid: 'uuid-src-001',
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
        uuid: 'uuid-$sku',
      );

  test('F-012: نسخة غير مشفرة (بعد الإلغاء الواعي) = ملف SQLite خام واحد يحوي بيانات الجهاز الحي',
      () async {
    final target = p.join(tempDir.path, 'b1.db');
    await backupTo(db, target, encrypted: false);

    final bytes = await File(target).readAsBytes();
    expect(BackupCipher.identify(bytes), BackupKind.plainSqlite);

    final raw = sql.sqlite3.open(target);
    final count = raw.select('SELECT COUNT(*) FROM items').first.values.first;
    raw.dispose();
    expect(count, 1);
  });

  test('F-012 + D-060: النسخة الافتراضية مشفرة بمفتاح البرنامج — تُفتح بلا أي كلمة، والعبث يُرفض قبل أي لمس',
      () async {
    final target = p.join(tempDir.path, 'b2.db');
    await backupTo(db, target); // الافتراضي: مشفرة (D-050/D-060)

    final bytes = await File(target).readAsBytes();
    expect(BackupCipher.identify(bytes), BackupKind.encrypted);
    expect(bytes[7], BackupCipher.formatVersion); // الجيل v2 بمفتاح البرنامج

    // بلا كلمة مرور ولا حقل: تُفتح مباشرة — N-005 بهذا أقوى (D-060)
    final candidate = await prepareRestore(target, appSchemaVersion: 3);
    candidate.dispose();

    // عبث بايت واحد داخل النص المشفر: رفض من وسم GCM قبل أي لمس للقاعدة
    final tampered = List<int>.from(bytes)..[bytes.length - 30] ^= 0xFF;
    final tamperedPath = p.join(tempDir.path, 'tampered.db');
    await File(tamperedPath).writeAsBytes(tampered, flush: true);
    await expectLater(
      () async {
        final c = await prepareRestore(tamperedPath, appSchemaVersion: 3);
        c.dispose();
      }(),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('D-060: الجيل القديم v1 بكلمة مرور يبقى مقروءاً بكلمته — وفراغ الكلمة رفض آمن',
      () async {
    // توليد ملف v1 (أيام D-050): قاعدة خام مغلّفة بكلمة مرور
    final rawPath = p.join(tempDir.path, 'raw.db');
    await backupTo(db, rawPath, encrypted: false);
    final rawBytes = await File(rawPath).readAsBytes();
    final legacyBlob =
        await BackupCipher().encryptWithPassword(rawBytes, 'كلمة-القديمة');
    final legacyPath = p.join(tempDir.path, 'legacy-v1.db');
    await File(legacyPath).writeAsBytes(legacyBlob, flush: true);
    expect(BackupCipher.encryptedVersion(legacyBlob), 1);

    // بلا كلمة مرور: توجيه صريح لمسار الجيل القديم — قبل أي لمس للقاعدة
    await expectLater(
      () async {
        final c = await prepareRestore(legacyPath, appSchemaVersion: 3);
        c.dispose();
      }(),
      throwsA(isA<CorruptBackupException>()),
    );

    // بكلمتها: تُقرأ وتستكمل كل الفحوص — التزام القراءة الدائم
    final c = await prepareRestore(legacyPath,
        password: 'كلمة-القديمة', appSchemaVersion: 3);
    c.dispose();
  });

  test('F-013 (الفيصل الثاني): ملف تالف — فشل آمن والقاعدة الحية لم تُمس',
      () async {
    final target = p.join(tempDir.path, 'corrupt.db');
    // خام صرياً — علّة CI 2026-10-29 كشفتها أول دفعة D-050/D-060: الافتراضي
    // صار مشفراً فصار البايت 15 داخل الملح ويرفضه وسم GCM قبل بلوغ SQLite،
    // وهذا الاختبار لبوابة سلامة SQLite الثانية حصراً (بوابة GCM غطاها
    // اختبار العبث في «F-012 + D-060» قبله) — فالخام هنا مقصود لا سهو.
    await backupTo(db, target, encrypted: false);
    final bytes = await File(target).readAsBytes();
    // البايت 15 هو خاتمة ترويسة SQLite ("...3\0") — عبثه يبقي التعرف
    // «خام سليم الشكل» لكن SQLite يرفض الملف قطعاً — مسار فشل آمن قاطع.
    bytes[15] ^= 0xFF;
    await File(target).writeAsBytes(bytes, flush: true);

    // «جهاز» حي ببيانات مختلفة — هو الذي سيُستبدل لو مرّ الملف التالف
    final otherPath = p.join(tempDir.path, 'device2.db');
    final other = DiqqahDatabase(filePath: otherPath);
    await other.into(other.items).insert(newItem('SKU-999', 'بضاعة الجهاز الآخر'));

    await expectLater(
      () async {
        final c = await prepareRestore(target, appSchemaVersion: 3);
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

  test('F-013 (الفيصل الأول) + F-154 + D-054: استعادة بتطابق 100% على جهاز آخر '
      'مع تبني هوية الجهاز المستقر عليه، ولقطة ما قبل الاستعادة بتاريخها '
      'هي طريق الرجوع', () async {
    // معرّف المصدر يدخل ملف النسخة — واعتماد معرّف الجهاز المستقر عليه
    // يقع بعد الاستبدال مباشرة (D-054)
    final sourceDeviceId = await db.deviceId();

    final target = p.join(tempDir.path, 'travel.db');
    await backupTo(db, target); // مشفرة بمفتاح البرنامج افتراضياً (D-060)

    // جهاز الهدف: قاعدة أخرى بمستخدم وبيانات مختلفة
    final otherPath = p.join(tempDir.path, 'device2.db');
    final other = DiqqahDatabase(filePath: otherPath);
    await other.createManager(
        name: 'قديم', login: 'old', passwordHash: 'a:b');
    await other.into(other.items).insert(newItem('SKU-999', 'بضاعة قديمة'));
    final oldDeviceId = await other.deviceId();
    expect(oldDeviceId, isNot(sourceDeviceId));

    final candidate =
        await prepareRestore(target, appSchemaVersion: other.schemaVersion);
    final snapshotPath = await applyRestore(
        db: other, candidate: candidate, currentDbPath: otherPath);
    candidate.dispose();

    // سطر الإحالة (F-154): اللقطة موجودة، مسماة بتاريخها، وتحوي بيانات
    // الجهاز القديمة — طريق الرجوع الوحيد سليم
    expect(File(snapshotPath).existsSync(), isTrue);
    expect(p.basename(snapshotPath), startsWith('diqqah-before-restore-'));
    final snap = sql.sqlite3.open(snapshotPath);
    final snapSku = snap.select('SELECT sku FROM items').first.values.first;
    snap.dispose();
    expect(snapSku, 'SKU-999');

    // إعادة فتح جهاز الهدف — بيانات المصدر كاملة حرفاً، والهوية للجهاز
    // المستقر عليه: التطابق 100% لكل شيء عدا device_id وحده (D-054)
    final restored = DiqqahDatabase(filePath: otherPath);
    final items = await restored.select(restored.items).get();
    expect(items, hasLength(1));
    expect(items.first.sku, 'SKU-001');
    expect(items.first.name, 'بضاعة الجهاز المصدر');
    expect(await restored.deviceId(), oldDeviceId);
    expect(await restored.deviceId(), isNot(sourceDeviceId));
    // نسخة المصدر بلا مستخدمين — بوابة F-014 ستعيد التهيئة، وهذا من
    // «كاملاً أو لا شيء»: المستخدمون جزء من الملف لا استثناء
    expect(await restored.hasAnyUser(), isFalse);
    await restored.close();
  });

  test('D-054: استعادة على الجهاز نفسه — هوية الجهاز لا تتغير (ثبات F-015)',
      () async {
    final selfDeviceId = await db.deviceId();
    final target = p.join(tempDir.path, 'self.db');
    await backupTo(db, target);

    final candidate =
        await prepareRestore(target, appSchemaVersion: 3);
    await applyRestore(db: db, candidate: candidate, currentDbPath: dbPath);
    candidate.dispose();

    final restored = DiqqahDatabase(filePath: dbPath);
    expect(await restored.deviceId(), selfDeviceId);
    expect(await restored.hasAnyUser(), isFalse); // نسخة المصدر بلا مستخدمين
    await restored.close();
  });

  test('F-156: نسخة من مخطط أحدث تُرفض برسالة «حدّث التطبيق» قبل أي استبدال',
      () async {
    final newerPath = p.join(tempDir.path, 'newer.db');
    final raw = sql.sqlite3.open(newerPath);
    raw.execute('CREATE TABLE t (x INTEGER)');
    raw.execute('PRAGMA user_version = 4');
    raw.dispose();

    await expectLater(
      () async {
        final c = await prepareRestore(newerPath, appSchemaVersion: 3);
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

    final newer = DiqqahDatabase(filePath: newerPath);
    await expectLater(
      newer.hasAnyUser(),
      throwsA(isA<DiqqahNewerSchemaException>()),
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

    final oldDb = DiqqahDatabase(filePath: v1Path);
    final rows = await oldDb.select(oldDb.items).get();
    expect(rows, hasLength(1));
    expect(rows.first.sku, 'SKU-OLD');
    // جداول v2 زُرعت بالترحيلة
    expect(await oldDb.hasAnyUser(), isFalse);
    await oldDb.close();

    // تعبئة ترحيلة v3 (D-055): الصنف القديم يحمل uuid عالمياً وأزمنة وحذفاً منطقياً
    final backfill = sql.sqlite3.open(v1Path);
    final old = backfill.select(
        "SELECT uuid, created_at, is_deleted FROM items WHERE sku = 'SKU-OLD'").first;
    backfill.dispose();
    expect((old.values[0] as String).length, 36);
    expect(old.values[1], greaterThan(0));
    expect(old.values[2], 0);
  });

  test('D-053: أول فتح بعد التسمية يتبنى ملف «heseb.db» القديم — لا أرشيف فارغ',
      () async {
    // مجلد معزول خاص بهذا السيناريو (علة CI 2026-10-28): setUp فتح قاعدة
    // على tempDir/diqqah.db — وحضور قاعدة جديدة يمنع التبنّي بالتصميم
    // (سلوك الحارس لا خطأ فيه)، فيجب أن يكون المسار الجديد غائباً كلياً.
    final dir = p.join(tempDir.path, 'adopt');
    await Directory(dir).create(recursive: true);
    final legacyPath = p.join(dir, 'heseb.db');
    final newPath = p.join(dir, 'diqqah.db');

    // قاعدة الجيل السابق على هيئة v1 — بأصناف فعلية وuser_version=1
    // كما في ملفات «حسيب» الحقيقية (الملف الواقعي يحمل نسخة مخططه)
    final raw = sql.sqlite3.open(legacyPath);
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
    raw.execute(
        "INSERT INTO items VALUES ('SKU-LEGACY', 'صنف الجيل السابق', NULL, 'good', 1, 0, 100, 1, NULL, 1)");
    raw.execute('PRAGMA user_version = 1');
    raw.dispose();

    await adoptLegacyHesebDatabase(newPath);

    // إعادة تسمية داخل المجلد نفسه: الجديد حاضر والقديم زال
    expect(await File(newPath).exists(), isTrue);
    expect(await File(legacyPath).exists(), isFalse);

    // الفتح يمر بالترحيلات كاملة (v1 ← 3) وتبقى بيانات الجيل السابق
    final adopted = DiqqahDatabase(filePath: newPath);
    final rows = await adopted.select(adopted.items).get();
    expect(rows, hasLength(1));
    expect(rows.first.sku, 'SKU-LEGACY');
    expect(rows.first.uuid.length, 36); // تعبئة الترحيلة
    await adopted.close();

    // حضور قاعدة جديدة حاضرة يمنع التبنّي — لا شيء يُمس
    final secondDir = p.join(tempDir.path, 'second');
    await Directory(secondDir).create(recursive: true);
    final secondPath = p.join(secondDir, 'diqqah.db');
    await File(secondPath).writeAsString('الجديدة');
    await File(p.join(secondDir, 'heseb.db')).writeAsString('القديمة');
    await adoptLegacyHesebDatabase(secondPath);
    expect(await File(secondPath).readAsString(), 'الجديدة');
  });
}
