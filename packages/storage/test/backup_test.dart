import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// س216: عزل الخلفية يغلف أخطاء عبور العزل بDriftRemoteException
/// (سلوك drift الموثق بعزل المحرك createInBackground) — فالتحقق
/// بالسبب الجذري مهما كان الغلاف.
Object rootCauseOf(Object e) =>
    e is DriftRemoteException ? e.remoteCause : e;

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
    final candidate = await prepareRestore(target, appSchemaVersion: db.schemaVersion);
    candidate.dispose();

    // عبث بايت واحد داخل النص المشفر: رفض من وسم GCM قبل أي لمس للقاعدة
    final tampered = List<int>.from(bytes)..[bytes.length - 30] ^= 0xFF;
    final tamperedPath = p.join(tempDir.path, 'tampered.db');
    await File(tamperedPath).writeAsBytes(tampered, flush: true);
    await expectLater(
      () async {
        final c = await prepareRestore(tamperedPath, appSchemaVersion: db.schemaVersion);
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
        final c = await prepareRestore(legacyPath, appSchemaVersion: db.schemaVersion);
        c.dispose();
      }(),
      throwsA(isA<CorruptBackupException>()),
    );

    // بكلمتها: تُقرأ وتستكمل كل الفحوص — التزام القراءة الدائم
    final c = await prepareRestore(legacyPath,
        password: 'كلمة-القديمة', appSchemaVersion: db.schemaVersion);
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
        final c = await prepareRestore(target, appSchemaVersion: db.schemaVersion);
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
        await prepareRestore(target, appSchemaVersion: db.schemaVersion);
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
    // «أحدث من التطبيق» تُحاكى دائماً بإصدار التطبيق نفسه +1 — لا برقم ثابت
    // علّة CI 2026-10-29: الرقم 4 كان «المستقبل» حتى رفعه دفعة الأطراف إلى
    // 4 فصار الحاضر — والثابت الميت يكذب على الاختبار مع كل ترقية مخطط.
    // نفس الدرس عاد بدفعة (6): الرقم 9 كان صلباً هنا حتى رفعها المخطط إلى 9.
    raw.execute('PRAGMA user_version = ${db.schemaVersion + 1}');
    raw.dispose();

    await expectLater(
      () async {
        final c = await prepareRestore(newerPath, appSchemaVersion: db.schemaVersion);
        c.dispose();
      }(),
      throwsA(isA<BackupNewerSchemaException>()),
    );
  });

  test('F-156: فتح قاعدة أحدث مخططاً من التطبيق نفسه يُرفض بحدّث التطبيق',
      () async {
    final newerPath = p.join(tempDir.path, 'newer-live.db');
    final raw = sql.sqlite3.open(newerPath);
    // درس الاختبار الشقيق نفسه: «أحدث» بإصدار التطبيق +1 لا برقم ميت —
    // الرقم 9 كان صلباً حتى رفعته دفعة (6) المخطط إلى 9 فصار حاضراً.
    raw.execute('PRAGMA user_version = ${db.schemaVersion + 1}');
    raw.dispose();

    final newer = DiqqahDatabase(filePath: newerPath);
    await expectLater(
      newer.hasAnyUser(),
      throwsA(predicate((Object e) {
        final cause = rootCauseOf(e);
        return cause is DiqqahNewerSchemaException ||
            // س216: عبور العزل يفقد النوع المخصص فيصل بلسانه الموثق
            // حصراً — فالمطابقة بلسان DQ-1101 بعينه لا بلسان أخ D-1105.
            cause.toString() ==
                'القاعدة أحدث مخططاً من التطبيق — حدّث التطبيق';
      })),
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

  // ─── دفعة (10) «الصور والباركود» — س-129/س-130، D-124/D-125 ───

  /// مجلد صور بملفَي أصل ومشتق — يعيد مجلد الصور نفسه (اصطلاح
  /// backupTo/applyRestore: مجلد الصور ذاته ومسارات الحزمة نسبية إليه
  /// — 'item-1.jpg' — بينما أعمدة القاعدة نسبية لمجلد القاعدة
  /// 'images/item-1.jpg' — الاصطلاحان طبقتان مختلفتان موثقتان).
  Future<Directory> seedImagesDir(String name) async {
    final dir = Directory(p.join(tempDir.path, name, 'images'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'item-1.jpg'))
        .writeAsBytes(List.generate(2048, (i) => i % 256));
    await File(p.join(dir.path, 'item-1-thumb.jpg'))
        .writeAsBytes(List.generate(256, (i) => i % 256));
    return dir;
  }

  test('س-129 (D-124): النسخة الممتدة ملفان — ملف القاعدة كما وُلد وملف '
      'صور مجاور بنفس المفتاح، والاستعادة تعيد المجلد', () async {
    final imagesRoot = await seedImagesDir('with_images');
    final target = p.join(tempDir.path, 'backup-full.diqqah');
    await backupTo(
      db,
      target,
      imagesDir: imagesRoot,
      includeImages: true,
    );
    // ملفان: القاعدة كما وُلدت (VACUUM INTO — لا انتفاخ بالصور) + الصور.
    final dbFile = File(target);
    final imagesFile = File(imagesSiblingPath(target));
    expect(await dbFile.exists(), isTrue);
    expect(await imagesFile.exists(), isTrue,
        reason: 'س-129: ملف ثانٍ للصور مغلّف بنفس المفتاح');
    // ملف القاعدة لا يحمل الصور: حجمه يقارب قاعدة فارغة لا ميغابايتات.
    expect(await dbFile.length(), lessThan(1024 * 1024));

    // الاستعادة: تصريح المحتوى أولاً ثم تعيد المجلد كاملاً.
    final candidate = await prepareRestore(
      target,
      appSchemaVersion: db.schemaVersion,
    );
    expect(candidate.hasImages, isTrue,
        reason: 'س-130: النسخة تتضمن صور الأصناف — يُصرَّح قبل التنفيذ');
    expect(candidate.imagesFiles, hasLength(2));
    final restoreDir = Directory(p.join(tempDir.path, 'landing'));
    await restoreDir.create(recursive: true);
    final restoredImages = Directory(p.join(restoreDir.path, 'images'));
    await restoredImages.create(recursive: true);
    await File(p.join(restoredImages.path, 'stale.jpg'))
        .writeAsString('قديم');
    // قاعدة حية سليمة تُنشأ هنا (لا بايتات وهمية — SQLite يرفض الفاسد)
    // فتُستبدل بملف النسخة في applyRestore.
    final livePath = p.join(restoreDir.path, 'diqqah.db');
    final restoreDb = DiqqahDatabase(filePath: livePath);
    await restoreDb.customSelect('SELECT 1').get();
    final snapshotPath = await applyRestore(
      db: restoreDb,
      candidate: candidate,
      currentDbPath: livePath,
      imagesDir: restoredImages,
    );
    candidate.dispose();
    await restoreDb.close();
    // المجلد استُبدل بمحتوى النسخة: مسارات الحزمة نسبية لمجلد الصور
    // نفسه ('item-1.jpg') فلا ملف قديم متروك ولا تكرار مجلدات.
    expect(await File(p.join(restoredImages.path, 'item-1.jpg')).exists(),
        isTrue);
    expect(
        await File(p.join(restoredImages.path, 'item-1-thumb.jpg')).exists(),
        isTrue);
    expect(await File(p.join(restoredImages.path, 'stale.jpg')).exists(),
        isFalse);
    // س-130: نسخة ما قبل الاستعادة تلحق الصور ذاته.
    expect(
        await File(imagesSiblingPath(snapshotPath)).exists(), isTrue);
  });

  test('س-130 (D-124): النسخة بلا صور تُصرَّح كذلك وتُفرغ مجلد الصور '
      '— لا فجوة صامتة والصور القديمة في لقطة الرجوع', () async {
    await seedImagesDir('no_images_case');
    // النسخة أُنشئت بلا تضمين — الصور خارجها أصلاً (والمجلد البذري هنا
    // للتوثيق حصراً: النسخة بلا imagesDir فلا ملف صور أصلاً).
    final target = p.join(tempDir.path, 'backup-noimg.diqqah');
    await backupTo(db, target, includeImages: false);
    expect(await File(imagesSiblingPath(target)).exists(), isFalse,
        reason: 'بلا تضمين لا ملف صور أصلاً — لا يتيمة');

    final candidate = await prepareRestore(
      target,
      appSchemaVersion: db.schemaVersion,
    );
    expect(candidate.hasImages, isFalse,
        reason: 'س-130: «النسخة بلا صور» — تصريح صادق');
    final restoreDir = Directory(p.join(tempDir.path, 'landing2'));
    await restoreDir.create(recursive: true);
    final livePath = p.join(restoreDir.path, 'diqqah.db');
    final restoreDb = DiqqahDatabase(filePath: livePath);
    await restoreDb.customSelect('SELECT 1').get();
    final restoredImages = Directory(p.join(restoreDir.path, 'images'));
    await restoredImages.create(recursive: true);
    await File(p.join(restoredImages.path, 'old.jpg')).writeAsString('قديم');
    final snapshotPath = await applyRestore(
      db: restoreDb,
      candidate: candidate,
      currentDbPath: livePath,
      imagesDir: restoredImages,
    );
    candidate.dispose();
    await restoreDb.close();
    // عالم النسخة المنعكس بصدق: المجلد فارغ لا ملفات قديمة يتيمة،
    // ولقطة الرجوع تحفظ القديم.
    expect(restoredImages.listSync(), isEmpty);
    expect(
        await File(imagesSiblingPath(snapshotPath)).exists(), isTrue);
  });

  test('س-130 (D-124): نسخة الصور المستقلة — تُنشأ وتُستعاد منفردة '
      'بلا مساس بالبيانات', () async {
    final imagesRoot = await seedImagesDir('standalone');
    final target = p.join(tempDir.path, 'images-only.diqqah.images');
    await backupImagesTo(imagesRoot, target);
    expect(await File(target).exists(), isTrue);

    // استعادة منفردة في مجلد آخر — لا قاعدة ولا مساس بها — ومسارات
    // الحزمة نسبية لمجلد الصور نفسه.
    final landing = Directory(p.join(tempDir.path, 'images_landing'));
    final count = await restoreImagesFrom(target, landing);
    expect(count, 2);
    expect(
        await File(p.join(landing.path, 'item-1.jpg')).exists(), isTrue);
    // القاعدة لم تُلمس: الصنف باقٍ كما هو.
    final rows = await db.select(db.items).get();
    expect(rows, isNotEmpty);
  });

  test('س-130: ملف صور فاسد يُرفض قبل أي لمس — لا فجوة صامتة', () async {
    final imagesRoot = await seedImagesDir('corrupt_case');
    final target = p.join(tempDir.path, 'backup-corrupt.diqqah');
    await backupTo(db, target, includeImages: true, imagesDir: imagesRoot);
    // إفساد ملف الصور المجاور بعد النسخ.
    await File(imagesSiblingPath(target)).writeAsString('هذا ليس ملف صور');
    await expectLater(
      prepareRestore(target, appSchemaVersion: db.schemaVersion),
      throwsA(isA<CorruptBackupException>()),
      reason: 'فاسد يرفض الاستعادة كلها لا يُسكَت',
    );
  });

  test('س116 — الدورة الكاملة مُجرَّبة: إنشاء → إخراج → استعادة → '
      'تحقق سلامة ومحتوى (الفاصل التشغيلي للمرحلة أ)', () async {
    // (1) الإنشاء: بذرة أغنى — صنفان وعميل وفاتورة بيع مرحّلة وقسيمة.
    final customerId = await db.insertParty(
        number: '0002', name: 'عميل الدورة', kind: 'customer',
        defaultCurrencyId: 1);
    await db.into(db.items).insert(newItem('SKU-002', 'بضاعة ثانية'));
    final whId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final year = (await db.customSelect(
      'SELECT name FROM fiscal_years LIMIT 1',
    ).getSingle()).data['name'] as String;
    // شراء يدخل المخزون أولاً فلا منع سالب (F-042)، ثم بيع منه.
    await db.postInvoice(await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '$year-03-15',
      partyId: customerId,
      warehouseId: whId,
      lines: [
        InvoiceLineDraft(
            itemId: 1, unitId: 1, qtyBase: 10, unitPriceMinor: 1000),
      ],
    )));
    final sale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: '$year-03-15',
      partyId: customerId,
      warehouseId: whId,
      lines: [
        InvoiceLineDraft(
            itemId: 1, unitId: 1, qtyBase: 3, unitPriceMinor: 1500),
      ],
    ));
    await db.postInvoice(sale);

    // (2) الإخراج: نسخة مشفرة افتراضياً (D-060) ملف واحد خارج القاعدة.
    final target = p.join(tempDir.path, 'cycle.diqqah');
    await backupTo(db, target);
    final exported = File(target);
    expect(exported.existsSync(), isTrue);
    expect(exported.lengthSync(), greaterThan(0));
    expect(exported.lengthSync(), isNot(equals(File(dbPath).lengthSync())),
        reason: 'المغلّف المشفر ليس بايتات الملف الخام');

    // (3) الاستعادة: على جهاز آخر بقاعدة مختلفة — الفحوص قبل أي لمس.
    final otherPath = p.join(tempDir.path, 'device2.db');
    final other = DiqqahDatabase(filePath: otherPath);
    await other.createManager(
        name: 'قديم', login: 'old', passwordHash: 'a:b');
    final candidate = await prepareRestore(
        target, appSchemaVersion: other.schemaVersion);
    final snapshotPath = await applyRestore(
        db: other, candidate: candidate, currentDbPath: otherPath);
    candidate.dispose();

    // (4) تحقق السلامة: القاعدة المستعادة integrity_check = ok والمحتوى
    // مطابق حرفاً ووقف ما قبل الاستعادة موجوداً (F-154).
    expect(File(snapshotPath).existsSync(), isTrue);
    final restored = DiqqahDatabase(filePath: otherPath);
    final integrity = await restored.customSelect('PRAGMA integrity_check').get();
    expect(integrity.first.data['integrity_check'], 'ok');
    final items = await restored.select(restored.items).get();
    expect(items.map((i) => i.sku), containsAll(['SKU-001', 'SKU-002']));
    final moves = await restored.customSelect(
      "SELECT COUNT(*) AS c FROM stock_moves WHERE ref_doc_type = "
      "'invoice'",
    ).getSingle();
    expect(moves.data['c'], 2,
        reason: 'حركتا الفاتورتين: دخول شراء وخروج بيع (نمط الفواتير)');
    final balances = await restored.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE qty_base <> 0',
    ).get();
    expect(balances.single.data['qty_base'], 7,
        reason: '10 شراء − 3 بيع = 7 بالمخزونية بقيمة 7000');
    expect(balances.single.data['total_value_minor'], 7000);
    await restored.close();
  });

  // ═══ P1-أ/P1-ب (س149/D-210): القفل v3 ومفتاح الصور ═══

  Uint8List kekOf(String seed) {
    final bytes = Uint8List.fromList(seed.codeUnits);
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = bytes[i % bytes.length];
    }
    return out;
  }

  test('P1-أ: نسخة مقفلة v3 — تُفك بأسرار القفل ولا تُفك بلاها',
      () async {
    const lock = BackupLock(password: 'كلمة-المالك', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    final target = p.join(tempDir.path, 'locked.diqqah');
    await backupTo(db, target, lock: lock);
    final bytes = await File(target).readAsBytes();
    expect(bytes[7], BackupCipher.lockedFormatVersion);

    // بأسرار القفل: فتح كامل والفحوص تجري.
    final candidate = await prepareRestore(target,
        password: lock.password,
        recoveryCode: lock.recoveryCode,
        appSchemaVersion: db.schemaVersion);
    expect(candidate.schemaVersion, db.schemaVersion);
    candidate.dispose();

    // بالرمز وحده: فتح أيضاً — والكلمة الخاطئة رفض صريح، والفراغ رفض
    // برسالة الطلب — قبل أي لمس للقاعدة حصراً.
    final byCode = await prepareRestore(target,
        recoveryCode: lock.recoveryCode,
        appSchemaVersion: db.schemaVersion);
    byCode.dispose();
    await expectLater(
      prepareRestore(target,
          password: 'خاطئة', appSchemaVersion: db.schemaVersion),
      throwsA(isA<BackupCipherException>()),
    );
    await expectLater(
      prepareRestore(target, appSchemaVersion: db.schemaVersion),
      throwsA(isA<BackupCipherException>()),
    );
  });

  test('P1-أ: ملف الصور المجاور يُقفل بجيل v3 ذاته — ويفك بالمواد ذاتها',
      () async {
    const lock = BackupLock(password: 'كلمة-المالك', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    final imagesRoot = await seedImagesDir('locked_images');
    final target = p.join(tempDir.path, 'locked-full.diqqah');
    await backupTo(db, target,
        includeImages: true,
        imagesDir: imagesRoot,
        lock: lock,
        imagesCipher: ImageFileCipher(kekOf('جهاز-مشفّر')));
    // ملف الصور بجيل v3 أيضاً.
    final siblingBytes = await File(imagesSiblingPath(target)).readAsBytes();
    expect(siblingBytes[7], BackupCipher.lockedFormatVersion);
    // الاستعادة الكاملة بالمفتاح والقفل: ملفات الصور تعود — ومكتوبة
    // مشفرة على القرص بمفتاح الجهاز الهابط.
    final candidate = await prepareRestore(target,
        password: lock.password,
        appSchemaVersion: db.schemaVersion);
    final landing = Directory(p.join(tempDir.path, 'images_landing'));
    final landingDbPath = p.join(tempDir.path, 'landing.db');
    await applyRestore(
      db: db,
      candidate: candidate,
      currentDbPath: landingDbPath,
      imagesDir: landing,
      imagesCipher: ImageFileCipher(kekOf('جهاز-مشفّر')),
    );
    final restoredImg = File(p.join(landing.path, 'item-1.jpg'));
    expect(restoredImg.existsSync(), isTrue);
    final onDisk = await restoredImg.readAsBytes();
    expect(ImageFileCipher.isEncryptedImage(onDisk), isTrue);
    // الفك يعيد الأصل حرفاً — فلا تشويه صامت في محتوى الصور.
    expect(
        await ImageFileCipher(kekOf('جهاز-مشفّر')).decrypt(onDisk),
        equals(List.generate(2048, (i) => i % 256)));
  });

  test('P1-ب: الجمع بلا مفتاح على مجلد مشفر — رفض صوت عالٍ لا حزمة نص صريح صامتة',
      () async {
    final cipher = ImageFileCipher(kekOf('جهاز-مشفّر'));
    final dir = await seedImagesDir('enc_only');
    // تشفير كل ملفات المجلد كما يفعل الترحيل.
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final plain = await f.readAsBytes();
      await f.writeAsBytes(await cipher.encrypt(plain));
    }
    expect(
      () => collectImagesBundle(dir),
      throwsA(isA<StateError>()),
    );
    // بالمفتاح: الحزمة تحمل النص الصريح — تُفك على أي جهاز.
    final bundle = await collectImagesBundle(dir, cipher: cipher);
    expect(bundle, isNotNull);
  });

  test('P1-أ: قفل النسخة غير المشفرة — القفل لا يدخل مسار الإلغاء الواعي',
      () async {
    // D-050: الإلغاء الواعي يبقى خاماً بلا أي غلاف — القفل يخص المشفرة
    // حصراً فلا تعتيم مزدوج ولا غلاف على نص صريح واعٍ.
    const lock = BackupLock(password: 'كلمة-المالك', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
    final target = p.join(tempDir.path, 'plain-with-lock.diqqah');
    await backupTo(db, target, encrypted: false, lock: lock);
    final bytes = await File(target).readAsBytes();
    expect(BackupCipher.identify(bytes), BackupKind.plainSqlite);
  });
}
