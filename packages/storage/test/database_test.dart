import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late DiqqahDatabase db;

  setUp(() {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('نسخة المخطط = 3 (F-011: كل تغيير مخطط إصدار وترحيلة — v3 اصطلاح كل جدول D-055)', () {
    expect(db.schemaVersion, 3);
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
}
