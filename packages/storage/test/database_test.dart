import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:drift/drift.dart' show Value;

void main() {
  late DiqqahDatabase db;

  setUp(() {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('نسخة المخطط = 6 (F-011: كل تغيير مخطط إصدار وترحيلة — v6 دفعة قلب الدفتر: D-076..D-078)', () {
    expect(db.schemaVersion, 6);
  });

  test('إنشاء المخطط وإدراج صنف وقراءته — الجلسة الأولى سليمة بعد v2',
      () async {
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-001',
            name: 'بضاعة تجريبية',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 1000,
            salePriceMinor: 1500,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-item-001',
          ),
        );

    final rows = await db.select(db.items).get();
    expect(rows, hasLength(1));
    expect(rows.first.sku, 'SKU-001');
    expect(rows.first.salePriceMinor, 1500);
    expect(rows.first.isActive, isTrue);
  });

  test('category اختياري — أساس الرفع الجماعي F-165، وdefault_tax_id قيمة صفرية',
      () async {
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-002',
            name: 'صنف بلا تصنيف',
            kind: 'service',
            baseUnitId: 1,
            purchasePriceMinor: 0,
            salePriceMinor: 5000,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-item-002',
          ),
        );

    final row = await (db.select(db.items)
          ..where((t) => t.sku.equals('SKU-002')))
        .getSingle();
    expect(row.category, isNull);
    expect(row.defaultTaxId, isNull);
  });

  test('F-015: device_id يتولد مرة ويبقى ثابتاً عبر الاستدعاءات', () async {
    final first = await db.deviceId();
    final second = await db.deviceId();
    expect(first, second);
    expect(first.length, 36); // UUID v4
  });

  test('F-014/س-01: إنشاء المدير الأول — يزرع دور «مدير» ويربطه', () async {
    expect(await db.hasAnyUser(), isFalse);

    final id = await db.createManager(
      name: 'المالك',
      login: 'owner',
      passwordHash: 'salt123:hash456',
    );
    expect(id, greaterThan(0));
    expect(await db.hasAnyUser(), isTrue);

    final user = await (db.select(db.appUsers)
          ..where((t) => t.login.equals('owner')))
        .getSingle();
    expect(user.name, 'المالك');
    expect(user.isActive, isTrue);

    final role = await (db.select(db.roles)
          ..where((t) => t.id.equals(user.roleId)))
        .getSingle();
    expect(role.name, 'مدير');
  });

  test('دور «مدير» لا يتكرر — إنشاء مستخدم آخر يعيد استخدام الدور', () async {
    await db.createManager(name: 'الأول', login: 'a', passwordHash: 's:h');
    // مستخدم إضافي عبر المسار نفسه (القاعدة لا تمنعه — البوابة تمنعه، F-014)
    await db.createManager(name: 'الثاني', login: 'b', passwordHash: 's:h');
    expect(await db.select(db.roles).get(), hasLength(1));
  });

  test('login فريد — إدراج مكرر يرفض من القاعدة', () async {
    await db.createManager(name: 'الأول', login: 'owner', passwordHash: 's:h');
    expect(
      () => db.createManager(
          name: 'مكرر', login: 'owner', passwordHash: 's:h'),
      throwsA(anything),
    );
  });

  test('اصطلاح «كل جدول» (D-055): كل سجل جديد يحمل uuid عالمياً وأزمنة وحذفاً منطقياً',
      () async {
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    final user = await (db.select(db.appUsers)
          ..where((t) => t.login.equals('owner')))
        .getSingle();
    expect(user.uuid.length, 36); // UUID v4
    expect(user.createdAt, greaterThan(0));
    expect(user.updatedAt, greaterThan(0));
    expect(user.isDeleted, isFalse);

    final role = await (db.select(db.roles)
          ..where((t) => t.id.equals(user.roleId)))
        .getSingle();
    expect(role.uuid.length, 36);
    expect(role.createdAt, greaterThan(0));
    expect(role.isDeleted, isFalse);
  });

  test('السعر السالب لا يمنعه المخطط بل يمنعه المجال — التخزين صادق (س6)',
      () async {
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-003',
            name: 'فحص الإشارات',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: -250,
            salePriceMinor: 900,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-item-003',
          ),
        );
    final row = await (db.select(db.items)
          ..where((t) => t.sku.equals('SKU-003')))
        .getSingle();
    expect(row.purchasePriceMinor, -250);
  });

  group('جدول الأطراف — دفعة م1 (1): D-062..D-066 وس-29..س-35', () {
    Future<int> seed() => db.insertParty(
          number: '0053',
          name: 'محمد الخالدي',
          kind: 'customer',
          defaultCurrencyId: 1,
        );

    test('س-29: الرقم يخزن نصاً بأصفاره كما كُتب، والعملة معبأة، وحد الائتمان بلا سقف',
        () async {
      final id = await seed();
      final row = await (db.select(db.parties)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.number, '0053', reason: 'الأصفار محفوظة كما كُتبت (D-063)');
      expect(row.name, 'محمد الخالدي');
      expect(row.kind, 'customer');
      expect(row.defaultCurrencyId, 1, reason: 'معبأة لا فراغ (D-066)');
      expect(row.creditLimitBaseMinor, isNull,
          reason: 'بلا سقف فراغ مشروع (س-34)');
      expect(row.isActive, isTrue);
      expect(row.uuid, isNotEmpty, reason: 'اصطلاح «كل جدول» D-055');
      expect(row.createdAt, greaterThan(0));
      expect(row.isDeleted, isFalse);
    });

    test('التفرد الحرفي للرقم قيد تخزين — تكرار 0053 يرفض من القاعدة؛\n'
        'والتفرد بعد نزع الأصفار قاعدة مجال قبل الحفظ لا قيد SQL', () async {
      await seed();
      expect(
        () => db.insertParty(
              number: '0053',
              name: 'آخر',
              kind: 'customer',
              defaultCurrencyId: 1,
            ),
        throwsA(anything),
      );
    });

    test('س-32: تعديل الاسم بالمرجع — المعرّف ثابت والرقم لا مسار تحديث له',
        () async {
      final id = await seed();
      final before = await (db.select(db.parties)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      await db.updatePartyDetails(
        before,
        name: 'محمد المعدل',
        kind: 'both',
        defaultCurrencyId: 1,
        creditLimitBaseMinor: 5000,
      );
      final after = await (db.select(db.parties)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(after.id, id);
      expect(after.number, '0053');
      expect(after.name, 'محمد المعدل');
      expect(after.kind, 'both', reason: 'س-30: الطرف المزدوج صف واحد');
      expect(after.creditLimitBaseMinor, 5000, reason: 'س-34 يخزن بوحدات صغرى');
      expect(after.updatedAt,
          greaterThanOrEqualTo(before.updatedAt));
    });

    test('س-33: التعطيل بطي is_active بلا حذف — الصف باقٍ كامل بياناته',
        () async {
      final id = await seed();
      await db.setPartyActive(id, active: false);
      final rows = await db.select(db.parties).get();
      expect(rows, hasLength(1), reason: 'لا حذف فيزيائي ولا منطقي');
      expect(rows.single.isActive, isFalse);
      expect(rows.single.name, 'محمد الخالدي');
      await db.setPartyActive(id, active: true);
      expect(
          (await (db.select(db.parties)..where((t) => t.id.equals(id)))
                .getSingle())
              .isActive,
          isTrue,
          reason: 'إعادة التفعيل ممكنة متى شئت');
    });

    test('الهاتف والعنوان الفارغان يسجلان null — اختياريان (س-29)', () async {
      final id = await db.insertParty(
        number: '0002',
        name: 'بلا بيانات اتصال',
        kind: 'supplier',
        phone: '   ',
        defaultCurrencyId: 1,
      );
      final row = await (db.select(db.parties)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.phone, isNull);
      expect(row.address, isNull);
    });
  });

  group('جدول الأصناف والوحدات — دفعة م1 (2): D-073..D-075 وس-36..س-41', () {
    test('س-41: إضافة وحدة — الاسم مقلم، والاصطلاح كامل، وis_base ثابتة true (D-075)',
        () async {
      final id = await db.insertUnit(name: ' قطعة ');
      final row = await (db.select(db.units)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.name, 'قطعة', reason: 'الفراغات الطرفية تقلَم عند الحفظ');
      expect(row.isBase, isTrue, reason: 'بنية لم2 — ثابتة true في م1 (D-075)');
      expect(row.uuid, isNotEmpty);
      expect(row.createdAt, greaterThan(0));
      expect(row.isDeleted, isFalse);
    });

    test('تفرد اسم الوحدة حرفياً قيد تخزين — تكرار «قطعة» يرفض من القاعدة (D-074)',
        () async {
      await db.insertUnit(name: 'قطعة');
      expect(
        () => db.insertUnit(name: 'قطعة'),
        throwsA(anything),
      );
    });

    test('س-36: إدراج صنف بضاعة كامل — الكود مقلم، والتصنيف الفارغ null، والمعرف هو الهوية (D-073)',
        () async {
      final unitId = await db.insertUnit(name: 'قطعة');
      final id = await db.insertItem(
        sku: ' 100 ',
        name: ' زيت محلي ',
        category: '  ',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 250000,
        salePriceMinor: 275000,
        priceCurrencyId: 1,
      );
      final row = await (db.select(db.items)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.id, id, reason: 'D-073: المعرف الآلي هو الهوية الدائمة');
      expect(row.sku, '100', reason: 'الكود يقلَم لا يُمس جسمه');
      expect(row.name, 'زيت محلي');
      expect(row.category, isNull, reason: 'التصنيف الفارغ يسجل null');
      expect(row.kind, 'good');
      expect(row.baseUnitId, unitId, reason: 'F-031: الوحدة إلزامية بالاختيار');
      expect(row.purchasePriceMinor, 250000, reason: 'س7: وحدات صغرى صحيحة');
      expect(row.priceCurrencyId, 1, reason: 'D-066: لا فراغ للعملة');
      expect(row.isActive, isTrue);
      expect(row.uuid, isNotEmpty);
    });

    test('التفرد الحرفي للكود قيد تخزين — تكرار 100 يرفض من القاعدة؛\n'
        'و«0100» كود آخر مشروع بلا نزع أصفار (D-073)', () async {
      final unitId = await db.insertUnit(name: 'قطعة');
      await db.insertItem(
        sku: '100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 0,
        priceCurrencyId: 1,
      );
      expect(
        () => db.insertItem(
              sku: '100',
              name: 'آخر',
              kind: 'good',
              baseUnitId: unitId,
              purchasePriceMinor: 0,
              salePriceMinor: 0,
              priceCurrencyId: 1,
            ),
        throwsA(anything),
      );
      // «0100» حرفياً مختلف — كود مشروع (نزع الأصفار قرار أطراف خاص)
      await db.insertItem(
        sku: '0100',
        name: 'كود بأصفار',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 0,
        priceCurrencyId: 1,
      );
    });

    test('س-39: تعديل الصنف بالمرجع — الكود خارج التوقيع فلا مسار تحديث له (D-073)',
        () async {
      final unitId = await db.insertUnit(name: 'قطعة');
      final id = await db.insertItem(
        sku: '100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 250000,
        salePriceMinor: 275000,
        priceCurrencyId: 1,
      );
      final before = await (db.select(db.items)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      await db.updateItemDetails(
        before,
        name: 'زيت محلي فاخر',
        category: 'مواد غذائية',
        kind: 'service',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 300000,
        priceCurrencyId: 1,
      );
      final after = await (db.select(db.items)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(after.id, id);
      expect(after.sku, '100', reason: 'الكود لا يعدل بعد الحفظ');
      expect(after.name, 'زيت محلي فاخر');
      expect(after.category, 'مواد غذائية');
      expect(after.kind, 'service');
      expect(after.salePriceMinor, 300000);
      expect(after.updatedAt, greaterThanOrEqualTo(before.updatedAt));
    });

    test('س-40: التعطيل بطي is_active بلا حذف — الصف باقٍ كامل بياناته',
        () async {
      final unitId = await db.insertUnit(name: 'قطعة');
      final id = await db.insertItem(
        sku: '100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 0,
        priceCurrencyId: 1,
      );
      await db.setItemActive(id, active: false);
      final rows = await db.select(db.items).get();
      expect(rows, hasLength(1), reason: 'لا حذف فيزيائي ولا منطقي');
      expect(rows.single.isActive, isFalse);
      expect(rows.single.name, 'زيت محلي');
      await db.setItemActive(id, active: true);
      expect(
          (await (db.select(db.items)..where((t) => t.id.equals(id)))
                .getSingle())
              .isActive,
          isTrue,
          reason: 'إعادة التفعيل ممكنة متى شئت');
    });

    test('F-035: جدول item_barcode بنية جاهزة — يُنشأ وباركوده فريد وقيمة unit_id صفرية',
        () async {
      final unitId = await db.insertUnit(name: 'قطعة');
      final itemId = await db.insertItem(
        sku: '100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 0,
        priceCurrencyId: 1,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.into(db.itemBarcodes).insert(
            ItemBarcodesCompanion.insert(
              itemId: itemId,
              barcode: '6290000000001',
              uuid: 'uuid-bc-001',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final row = await db.select(db.itemBarcodes).getSingle();
      expect(row.unitId, isNull, reason: 'وحدة القراءة بنية م2');
      expect(
        () => db.into(db.itemBarcodes).insert(
              ItemBarcodesCompanion.insert(
                itemId: itemId,
                barcode: '6290000000001',
                uuid: 'uuid-bc-002',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            ),
        throwsA(anything),
        reason: 'الباركود فريد قيد تخزين',
      );
    });
  });

  test('ترحيلة 4→5: إعادة بناء items بإضافة id تُعيد بيانات القائمة كاملة '
      'وتُبنى units وitem_barcodes جديدين (D-073/F-011)', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v5_mig_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate.db');
    // قاعدة v4 خام: جدول items بالشكل القديم (sku مفتاح أساس، بلا id)
    // كما يولده drift قبل الدفعة، وuser_version=4 — والصفوف الأخرى
    // غير ضرورية للترحيلة المقصودة (createAll يبني الباقي).
    final raw = sqlite3.open(dbPath);
    raw.execute('CREATE TABLE "items" ('
        '"sku" TEXT NOT NULL PRIMARY KEY,'
        '"name" TEXT NOT NULL,'
        '"category" TEXT NULL,'
        '"kind" TEXT NOT NULL,'
        '"base_unit_id" INTEGER NOT NULL,'
        '"purchase_price_minor" INTEGER NOT NULL,'
        '"sale_price_minor" INTEGER NOT NULL,'
        '"price_currency_id" INTEGER NOT NULL,'
        '"default_tax_id" INTEGER NULL,'
        '"is_active" INTEGER NOT NULL DEFAULT 0,'
        '"uuid" TEXT NOT NULL,'
        '"created_at" INTEGER NOT NULL DEFAULT 0,'
        '"updated_at" INTEGER NOT NULL DEFAULT 0,'
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)');
    raw.execute("INSERT INTO items (sku, name, kind, base_unit_id, "
        "purchase_price_minor, sale_price_minor, price_currency_id, "
        "is_active, uuid) VALUES ('SKU-OLD', 'بضاعة قبل الترحيل', 'good', 1, "
        "250000, 275000, 1, 1, 'uuid-old-1')");
    raw.execute('PRAGMA user_version = 4');
    raw.dispose();

    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    // أول استخدام يثير الترقية 4→5 — createAll ثم إعادة البناء
    await migrated.select(migrated.items).get();
    expect(migrated.schemaVersion, 5);

    final rows = await migrated.select(migrated.items).get();
    expect(rows, hasLength(1), reason: 'بيانات القائمة حفظت كاملة');
    expect(rows.first.sku, 'SKU-OLD');
    expect(rows.first.name, 'بضاعة قبل الترحيل');
    expect(rows.first.purchasePriceMinor, 250000);
    expect(rows.first.id, greaterThan(0),
        reason: 'D-073: المعرّف الآلي فيبقى من الترحيلة');
    expect(rows.first.uuid, 'uuid-old-1', reason: 'الاصطلاح محفوظ بايتاً');

    // والجداول الجديدة تعمل فوراً — إدراج وحدة وصنف على المخطط الجديد
    final unitId = await migrated.insertUnit(name: 'قطعة');
    final newId = await migrated.insertItem(
      sku: 'SKU-NEW',
      name: 'صنف بعد الترحيل',
      kind: 'service',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 5000,
      priceCurrencyId: 1,
    );
    expect(newId, greaterThan(0));
    expect(await migrated.select(migrated.units).get(), hasLength(1));
  });
}
