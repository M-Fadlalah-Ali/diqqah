import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات دفعة استيراد البيانات الأولى — النواة بالتخزين
/// (D-208/§25.11): التخطيط من قراءات القاعدة الحية، والتنفيذ بمعاملة
/// واحدة كل-أو-لا شيء، وحدث الاستيراد بنفس المعاملة، والنسخة الحدثية
/// شرط الاعتماد، وإغلاق نافذة التراجع بأول كتابة استيراد (§25.7).
void main() {
  late DiqqahDatabase db;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() => db.close);

  List<int> partiesBytes(List<String> rows) => utf8.encode([
        'dq-import:parties,1',
        'الكود,الاسم,النوع,العملة,حد الائتمان',
        ...rows,
      ].join('\n'));

  List<int> itemsBytes(List<String> rows) => utf8.encode([
        'dq-import:items,1',
        'كود الصنف,الاسم,الوحدة,عملة السعر,سعر الشراء,سعر البيع',
        ...rows,
      ].join('\n'));

  group('التخطيط من القاعدة الحية', () {
    test('مرجع العملات يضم المزروعتين والفراغ يعني الأساسية', () async {
      final index = await db.importCurrencyIndex();
      expect(index, contains('SYP'));
      expect(index, contains('USD'));
      expect(index['SYP']!.minorUnits, 2, reason: 'D-017');
    });

    test('الأطراف القائمة بالقاعدة يظهرها التخطيط بالتخطي أو التحديث',
        () async {
      await db.insertParty(
          number: 'C001', name: 'علي أحمد', kind: 'customer',
          defaultCurrencyId: 1);
      final parse = parsePartiesFile(partiesBytes([
        'C001,علي المحدث,عميل,,',
        'C002,جديد,عميل,,',
      ]));
      final skip = await db.planPartiesImportFromDb(
        parse,
        policy: ImportExistingPolicy.addNew,
      );
      expect(skip.isApprovable, isTrue, reason: '${skip.errors}');
      expect(skip.creates, hasLength(1));
      expect(skip.skipped.single.existingLabel, contains('C001'));

      final update = await db.planPartiesImportFromDb(
        parse,
        policy: ImportExistingPolicy.updateExisting,
      );
      expect(update.updates, hasLength(1));
      expect(update.updates.single.newName, 'علي المحدث');
    });

    test('الأصناف القائمة بتفاصيلها الحية: فروق الأسعار بالبشري '
        'وحارس وحدة الصنف', () async {
      final unitId = await db.insertUnit(name: 'علبة');
      final itemId = await db.insertItem(
          sku: 'K101', name: 'زيت', kind: 'good',
          baseUnitId: unitId, purchasePriceMinor: 100000,
          salePriceMinor: 125000, priceCurrencyId: 1);
      final parse = parseItemsFile(itemsBytes([
        'K101,زيت محلي,كيس,,110000,140000',
      ]));
      final plan = await db.planItemsImportFromDb(
        parse,
        policy: ImportExistingPolicy.updateExisting,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      expect(plan.updates, hasLength(1));
      expect(plan.updates.single.itemId, itemId);
      final unitDiff =
          plan.differences.firstWhere((d) => d.columnKey == 'unit');
      expect(unitDiff.oldValue, 'علبة',
          reason: 'القديم من القاعدة الحية لا من الخيال');
      expect(unitDiff.updated, isFalse);
      final purchaseDiff = plan.differences
          .firstWhere((d) => d.columnKey == 'purchase_price');
      expect(purchaseDiff.oldValue, '1000');
      expect(purchaseDiff.newValue, '110000');
    });
  });

  group('تنفيذ الأطراف — معاملة واحدة وحدث الاستيراد', () {
    test('إنشاء أطراف بعدادات حقيقية وحدث بنفس المعاملة', () async {
      final plan = await db.planPartiesImportFromDb(
        parsePartiesFile(partiesBytes([
          'C001,علي,عميل,,',
          'C002,مؤمن,عميل,USD,10000.5',
          'S003,مورد,مورد,,',
        ])),
        policy: ImportExistingPolicy.addNew,
      );
      final result = await db.executePartiesImport(
        plan,
        eventBackupName: 'event-20261114-120000.diqqah',
      );
      expect(result.created, 3);
      expect(result.updated, 0);
      expect(result.skipped, 0);

      final parties = await db.customSelect(
          'SELECT number, name, kind, default_currency_id, '
          'credit_limit_base_minor FROM parties ORDER BY number').get();
      expect(parties, hasLength(3));
      final usd = parties.firstWhere(
          (r) => r.data['number'] == 'C002');
      expect(usd.data['default_currency_id'], 2,
          reason: 'عملة الطرف الدولار');
      expect(usd.data['credit_limit_base_minor'], 1000050,
          reason: 'التحويل بدقة العملة 10000.5 ← 1000050');

      final events = await db.customSelect(
          "SELECT action, payload FROM events WHERE action = "
          "'import_performed'").get();
      expect(events, hasLength(1),
          reason: 'لا عملية بلا حدث — الحدث بنفس المعاملة');
      final payload =
          jsonDecode(await db.openLogText(events.single.data['payload'] as String))
              as Map<String, Object?>;
      expect(payload['unit'], 'parties');
      expect(payload['separator'], ',');
      expect(payload['policy'], 'إضافة جديد');
      expect(payload['created'], 3);
      expect(payload['event_backup'], 'event-20261114-120000.diqqah');
    });

    test('اصطدام بالحية بين المعاينة والاعتماد يرجع المعاملة كلها '
        '(DQ-1106) — كل-أو-لا شيء', () async {
      // خطة صفين حرّين لحظة التخطيط.
      final parse1 = parsePartiesFile(partiesBytes([
        'C005,سعيد,عميل,,',
        'C006,نور,عميل,,',
      ]));
      final plan = await db.planPartiesImportFromDb(
        parse1,
        policy: ImportExistingPolicy.addNew,
      );
      await db.insertParty(
          number: 'C006', name: 'متدخل', kind: 'customer',
          defaultCurrencyId: 1);

      await expectLater(
        () => db.executePartiesImport(
          plan,
          eventBackupName: 'event.diqqah',
        ),
        throwsA(isA<ImportExecutionException>()),
      );

      // لم يُكتب شيء: الجزء المكتوب قبل الاصطدام رجع بالمعاملة.
      final parties = await db.customSelect(
          'SELECT name FROM parties WHERE number = '
          "'C005'").get();
      expect(parties, isEmpty);
      final events = await db.customSelect(
          "SELECT id FROM events WHERE action = "
          "'import_performed'").get();
      expect(events, isEmpty);
      // والمتدخل نفسه لم يمسه شيء.
      final c6 = await db.customSelect(
          'SELECT name FROM parties WHERE number = '
          "'C006'").get();
      expect(c6.single.data['name'], 'متدخل');
    });

    test('تحديث الاسم وصفيّات v1 حصراً — النوع والعملة وحد الائتمان '
        'لا يمسها هذا المسار (د-2)', () async {
      final id = await db.insertParty(
          number: 'C001', name: 'علي', kind: 'customer',
          defaultCurrencyId: 2, creditLimitBaseMinor: 500000);
      final plan = await db.planPartiesImportFromDb(
        parsePartiesFile(partiesBytes([
          'C001,علي المحدث,مورد,SYP,9000000',
        ])),
        policy: ImportExistingPolicy.updateExisting,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      final result = await db.executePartiesImport(
        plan,
        eventBackupName: 'event.diqqah',
      );
      expect(result.updated, 1);
      final row = await db.customSelect(
          'SELECT name, kind, default_currency_id, '
          'credit_limit_base_minor FROM parties WHERE id = ?', variables: [
        Variable.withInt(id),
      ]).get();
      expect(row.single.data['name'], 'علي المحدث');
      expect(row.single.data['kind'], 'customer',
          reason: 'النوع لا يُحدَّث بالاستيراد في v1');
      expect(row.single.data['default_currency_id'], 2,
          reason: 'عملة الطرف لا تتغير بالاستيراد في v1');
      expect(row.single.data['credit_limit_base_minor'], 500000,
          reason: 'حد الائتمان لا يُحدَّث بالاستيراد في v1');
    });
  });

  group('تنفيذ الأصناف — الوحدات الآلية والتحديثات الوصفية', () {
    test('وحدة غائبة تُنشأ آلياً والأصناف تُدرج بها بلا تكرار', () async {
      final plan = await db.planItemsImportFromDb(
        parseItemsFile(itemsBytes([
          'K1,صنف أ,كرتون,,1000,1500',
          'K2,صنف ب,قطعة,,2000,2500',
          'K3,صنف ج,كرتون,,3000,3500',
        ])),
        policy: ImportExistingPolicy.addNew,
      );
      final result = await db.executeItemsImport(
        plan,
        eventBackupName: 'event.diqqah',
      );
      expect(result.created, 3);
      final units = await db.customSelect(
          'SELECT name FROM units ORDER BY name').get();
      expect(units.map((u) => u.data['name']),
          unorderedEquals(['كرتون', 'قطعة']),
          reason: 'الوحدة الغائبة واحدة لا تكرار (§25.4)');
      final items = await db.customSelect(
          'SELECT sku, base_unit_id, kind FROM items ORDER BY sku').get();
      expect(items, hasLength(3));
      expect(items.first.data['kind'], 'good',
          reason: 'الاستيراد v1 بضاعة حصراً — حد موثق');
    });

    test('تحديث الصنف بالاسم والسعرين وحدهما وفرق الوحدة محروس',
        () async {
      final unitId = await db.insertUnit(name: 'علبة');
      final itemId = await db.insertItem(
          sku: 'K101', name: 'زيت', kind: 'good',
          baseUnitId: unitId, purchasePriceMinor: 100000,
          salePriceMinor: 125000, priceCurrencyId: 1);
      final plan = await db.planItemsImportFromDb(
        parseItemsFile(itemsBytes(['K101,زيت محلي,علبة,,110000,140000'])),
        policy: ImportExistingPolicy.updateExisting,
      );
      final result = await db.executeItemsImport(
        plan,
        eventBackupName: 'event.diqqah',
      );
      expect(result.updated, 1);
      final row = await db.customSelect(
          'SELECT name, purchase_price_minor, sale_price_minor, '
          'base_unit_id FROM items WHERE id = ?', variables: [
        Variable.withInt(itemId),
      ]).get();
      expect(row.single.data['name'], 'زيت محلي');
      expect(row.single.data['purchase_price_minor'], 11000000);
      expect(row.single.data['sale_price_minor'], 14000000);
      expect(row.single.data['base_unit_id'], unitId,
          reason: 'وحدة الصنف القائم لا تتغير بالاستيراد (حماية الأرصدة)');
    });
  });

  group('السلامة — النافذة والحداثة', () {
    test('الاستيراد كتابة تغلق نافذة التراجع المفتوحة (§25.7/26.1)',
        () async {
      await db.armRollbackWindow(snapshotFileName: 'pre-restore.diqqah');
      final open = await db.rollbackWindow();
      expect(open?.closed, isFalse);

      final plan = await db.planPartiesImportFromDb(
        parsePartiesFile(partiesBytes(['C001,علي,عميل,,'])),
        policy: ImportExistingPolicy.addNew,
      );
      await db.executePartiesImport(
        plan,
        eventBackupName: 'event.diqqah',
      );

      final after = await db.rollbackWindow();
      expect(after?.closed, isTrue,
          reason: 'أول كتابة استيراد تتجاوز خط الأساس فتغلق النافذة');
      final closedEvents = await db.customSelect(
          "SELECT id FROM events WHERE action = "
          "'rollback_window_closed'").get();
      expect(closedEvents, hasLength(1));
    });
  });
}
