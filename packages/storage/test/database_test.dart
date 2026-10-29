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

  test('نسخة المخطط = 4 (F-011: كل تغيير مخطط إصدار وترحيلة — v4 جدول الأطراف دفعة م1 (1))', () {
    expect(db.schemaVersion, 4);
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
}
