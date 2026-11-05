import 'package:test/test.dart';
// النمط الموثق: الاستيراد بلا بادئة — `sqlite3` هنا كائن عام توفره
// الحزمة (نمط database_test) لا بادئة مكتبة.
import 'package:sqlite3/sqlite3.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

/// اختبارات الدفعة 27 (رابعة م2) — مجموعات التعبئة وأسعارها آلي
/// (F-032/F-033/F-208، D-026/D-187).
///
/// الحدود الموثقة: المرجع إضافة وتسمية لا حذف (نمط المراجع 03 §6-3)،
/// والعامل يتجمد بعد حركات حقيقية (مسودة لا تجمد — F-033) والمسار
/// الوحيد وحدة جديدة، والآلي افتراضه مفعّل (D-187)، والترقية الجماعية
/// تكتب المستويات المحسوبة مع صيانة الحقل غير المستهدف من صفه القائم
/// (تقاطع F-165/D-187)، والترحيلة v18 آمنة التكرار بحرس pragma
/// (درس v3).
void main() {
  late DiqqahDatabase db;
  late int unitId;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    unitId = await db.insertUnit(name: 'قطعة');
  });

  tearDown(() => db.close);

  Future<int> seedItem({
    String sku = 'Z-100',
    String category = 'زيوت',
    int? unitGroupId,
    bool priceAuto = true,
    int sale = 40000,
    int purchase = 25000,
  }) {
    return db.insertItem(
        sku: sku,
        name: 'صنف $sku',
        category: category,
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: purchase,
        salePriceMinor: sale,
        priceCurrencyId: 1,
        unitGroupId: unitGroupId,
        priceAuto: priceAuto);
  }

  test('ترحيلة v18 على قاعدة جديدة: الجداول الثلاثة وعمودا items والافتراض '
      'مفعّل (D-187)', () async {
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('unit_groups', 'unit_group_levels', 'item_level_prices')",
    ).get();
    expect(tables.map((r) => r.data['name']), hasLength(3));

    final cols = await db.customSelect(
      "SELECT name FROM pragma_table_info('items') "
      "WHERE name IN ('unit_group_id', 'price_auto')",
    ).get();
    expect(cols.map((r) => r.data['name']),
        containsAll(['unit_group_id', 'price_auto']));

    // الصنف الجديد بلا تحديد: آلي مفعّل وبلا مجموعة (افتراض D-187).
    final id = await seedItem();
    final row = await db.customSelect(
      'SELECT price_auto, unit_group_id FROM items WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle();
    expect(row.data['price_auto'], 1);
    expect(row.data['unit_group_id'], isNull);
  });

  test('ترحيلة v18 آمنة التكرار: قاعدة v17 تُرقّى بأعمدتها والقائمة تولد '
      'آلياً مفعلاً (درس v3)', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v27_mig_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate18.db');

    final seeded = DiqqahDatabase(filePath: dbPath);
    final u = await seeded.insertUnit(name: 'قطعة');
    await seeded.insertItem(
        sku: 'M-1',
        name: 'صنف ما قبل الترحيلة',
        kind: 'good',
        baseUnitId: u,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1);
    await seeded.close();

    // تخفيض user_version إلى 17: إعادة الفتح تُجري 17→18 أمامنا —
    // والأعمدة موجودة أصلاً (onCreate كامل) فالحرس pragma يقفز آمناً.
    final raw = sqlite3.open(dbPath);
    raw.execute('PRAGMA user_version = 17');
    raw.dispose();

    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    expect(migrated.schemaVersion, 21);
    final tables = await migrated.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('unit_groups', 'unit_group_levels', 'item_level_prices')",
    ).get();
    expect(tables, hasLength(3));
    // الصف القائم تولد آلياً مفعلاً وبلا مجموعة — لا تهجير قيم.
    final row = await migrated.customSelect(
      'SELECT price_auto, unit_group_id FROM items',
    ).getSingle();
    expect(row.data['price_auto'], 1);
    expect(row.data['unit_group_id'], isNull);
    // والمسارات الجديدة تعمل بعد الترحيلة مباشرة.
    final gid = await migrated.insertUnitGroup(name: 'بعد الترحيلة',
        levels: [(name: 'علبة', factor: 12)]);
    expect(await migrated.levelsOfGroup(gid), hasLength(1));
  });

  test('مجموعة تعبئة: إدراج بمستوياتها وقراءتها مرتبة بالعامل — والاسم '
      'الحرفي فريد (D-074) وتفرد المستوى داخل المجموعة', () async {
    final gid = await db.insertUnitGroup(
      name: 'تعبئة عامة',
      levels: [(name: 'كرتونة', factor: 144), (name: 'علبة', factor: 12)],
    );
    final levels = await db.levelsOfGroup(gid);
    expect([for (final l in levels) (l.name, l.factor)],
        [('علبة', 12), ('كرتونة', 144)], reason: 'مرتبة بالعامل تصاعدياً');

    await expectLater(db.insertUnitGroup(name: 'تعبئة عامة'), throwsA(anything),
        reason: 'الاسم الفريد حرفياً حرس ثانوي');
    await expectLater(
        db.insertUnitGroupLevel(
            groupId: gid, name: 'علبة', factor: 24),
        throwsA(anything),
        reason: 'تفرد اسم المستوى داخل المجموعة');
  });

  test('ربط الصنف بالمجموعة ومربع الآلي يُخزنان ويُقرآن، وأسعار المستويات '
      'استبدال كامل بمعاملة (F-032/F-208)', () async {
    final gid = await db.insertUnitGroup(name: 'تعبئة',
        levels: [(name: 'علبة', factor: 12), (name: 'كرتونة', factor: 144)]);
    final levels = await db.levelsOfGroup(gid);
    final id = await seedItem(unitGroupId: gid, priceAuto: false);

    final items = await db.select(db.items).get();
    final saved = items.singleWhere((i) => i.id == id);
    expect(saved.unitGroupId, gid);
    expect(saved.priceAuto, isFalse);

    await db.saveItemLevelPrices(id, [
      (levelId: levels[0].id, salePriceMinor: 480000, purchasePriceMinor: 300000),
      (levelId: levels[1].id, salePriceMinor: 5760000, purchasePriceMinor: 3600000),
    ]);
    final map = await db.itemLevelPriceMap(id);
    expect(map[levels[0].id], (480000, 300000));
    expect(map[levels[1].id], (5760000, 3600000));

    // الاستبدال الكامل: حفظ جديد بمستوى واحد يمحو القديم (نمط اللقطة).
    await db.saveItemLevelPrices(
        id, [(levelId: levels[0].id, salePriceMinor: 490000, purchasePriceMinor: 0)]);
    final after = await db.itemLevelPriceMap(id);
    expect(after, hasLength(1));
    expect(after[levels[0].id], (490000, 0));
  });

  test('F-033: العامل حر قبل الحركات، والمسودة لا تجمد، والفاتورة المرحّلة '
      'تجمّد — والتسمية والوحدة الجديدة تمران بعد التجمد', () async {
    final gid = await db.insertUnitGroup(name: 'تجميد',
        levels: [(name: 'علبة', factor: 12)]);
    final levelId = (await db.levelsOfGroup(gid)).single.id;
    final id = await seedItem(unitGroupId: gid);

    expect(await db.unitGroupHasMovements(gid), isFalse);
    // حر قبل الحركات.
    await db.updateUnitGroupLevel(levelId, factor: 24);
    await db.updateUnitGroupLevel(levelId, factor: 12);

    final supplierId = await db.insertParty(
        number: '0001', name: 'مورد', kind: 'supplier', defaultCurrencyId: 1);
    final whId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;

    // المسودة لا تجمد (الحركة حقيقية لا مسودة).
    final draft = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: '2026-03-15',
      partyId: supplierId,
      warehouseId: whId,
      lines: [
        InvoiceLineDraft(
            itemId: id, unitId: unitId, qtyBase: 5, unitPriceMinor: 25000),
      ],
    ));
    expect(await db.unitGroupHasMovements(gid), isFalse,
        reason: 'المسودة ليست حركة');

    await db.postInvoice(draft);
    expect(await db.unitGroupHasMovements(gid), isTrue);

    await expectLater(
        db.updateUnitGroupLevel(levelId, factor: 30),
        throwsA(isA<UnitGroupFactorFrozenException>()));
    // التسمية تمر (لا تمس التاريخ).
    await db.updateUnitGroupLevel(levelId, name: 'علبة كبيرة');
    // والمسار الوحيد: وحدة جديدة.
    final newLevel = await db.insertUnitGroupLevel(
        groupId: gid, name: 'كرتونة', factor: 144);
    expect(newLevel, greaterThan(0));
  });

  test('الترقية الجماعية بالمستويات (تقاطع F-165/D-187): المستوى المكتوب '
      'يُستبدل والحقل غير المستهدف يُصان من صفه القائم', () async {
    final gid = await db.insertUnitGroup(name: 'ترقية',
        levels: [(name: 'علبة', factor: 12)]);
    final levelId = (await db.levelsOfGroup(gid)).single.id;
    final id = await seedItem(sale: 1000, purchase: 800, unitGroupId: gid);
    await db.saveItemLevelPrices(id, [
      (levelId: levelId, salePriceMinor: 12000, purchasePriceMinor: 777),
    ]);

    // ترقية البيع حصراً: مستوى البيع يُستبدل وشراء المستوى اليدوي (777)
    // يُصان من صفه القائم فلا قيمة يدوية تضيع.
    await db.applyBulkPriceUpdates([
      BulkPriceUpdateRow(
        itemId: id,
        newSalePriceMinor: 1100,
        levels: [
          BulkLevelPriceUpdateRow(levelId: levelId, newSalePriceMinor: 13200),
        ],
      ),
    ]);
    expect(await db.itemLevelPriceMap(id), {
      levelId: (13200, 777),
    });
    final items = await db.select(db.items).get();
    expect(items.singleWhere((i) => i.id == id).salePriceMinor, 1100);
    expect(items.singleWhere((i) => i.id == id).purchasePriceMinor, 800,
        reason: 'الحقل غير المستهدف لا يُمس إطلاقاً');

    // ترقية «كلاهما»: الحقلان يُكتبان.
    await db.applyBulkPriceUpdates([
      BulkPriceUpdateRow(
        itemId: id,
        newSalePriceMinor: 1210,
        newPurchasePriceMinor: 880,
        levels: [
          BulkLevelPriceUpdateRow(
              levelId: levelId, newSalePriceMinor: 14520, newPurchasePriceMinor: 10560),
        ],
      ),
    ]);
    expect(await db.itemLevelPriceMap(id), {
      levelId: (14520, 10560),
    });
  });

  test('خريطة أسعار المستويات لأصناف متعددة — أساس معاينة الرفع الجماعي',
      () async {
    final gid = await db.insertUnitGroup(name: 'خريطة',
        levels: [(name: 'علبة', factor: 12)]);
    final levelId = (await db.levelsOfGroup(gid)).single.id;
    final a = await seedItem(sku: 'A-1', unitGroupId: gid);
    final b = await seedItem(sku: 'B-2', unitGroupId: gid);
    await db.saveItemLevelPrices(
        a, [(levelId: levelId, salePriceMinor: 100, purchasePriceMinor: 50)]);

    final map = await db.itemLevelPricesForItems([a, b]);
    expect(map[a]![levelId], (100, 50));
    expect(map.containsKey(b), isFalse, reason: 'بلا صفوف فلا مدخل');
    expect(await db.itemLevelPricesForItems(const []), isEmpty);
  });
}
