// اختبارات د6 (س175 — الاستيعاب الواجهي والأحمال الختامية بنص خارطة
// م4 §46): ترحيلة v32 «المتابعات اليومية» — عمودا الحد الأدنى على
// الأصناف ومدة السداد على الأطراف (س74/D-184 بلفظ المالك) بADD COLUMN
// بحرس pragma (نمط 30→31). التغطية:
//   (1) القاعدة الجديدة تولد بالعمودين والإصدار 32 حرفاً.
//   (2) القاعدة القائمة v31 (بشكلها الحرفي بلا العمودين وببياناتها)
//       ترقى 31→32 فالصفوف القائمة تملأ null بلا إعادة بناء ولا مساس،
//       وآمنة التكرار بلا مساس عند إعادة الفتح.
//   (3) حرس الموجب: الصفر والسالب يُخزَّنان null فلا حد بلا معنى.
//   (4) الاستعلامات الثلاثة فوق المصادر: تحت الحد الأدنى (بالسلع
//       حصراً والمتاح عبر المستودعات) وفوق السقف المبلغي (لسان F-164
//       بالتمام ليس تجاوزاً) وفوق السقف الزمني (مدة السداد بمرساة
//       الأعمار س-151/D-149 والباقي المفتوح).
//   (5) مفاتيح سجلات العمل الجماعي الثلاثة: حفظ وقراءة وجولة ثانية.
// الحاكم: integrity_check=ok والبيانات باقية حرفاً (عرف الفئة 1).
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late Directory tempDir;
  late DiqqahDatabase db;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_d6_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> insertRawItem(
      DiqqahDatabase target, String sku, String name, String kind,
      {int? minQty}) async {
    await target.customStatement(
      'INSERT INTO items (sku, name, kind, base_unit_id, '
      'purchase_price_minor, sale_price_minor, price_currency_id, '
      'min_qty, is_active, uuid, created_at, updated_at, is_deleted) '
      'VALUES (?1, ?2, ?3, 1, 0, 0, 1, ?4, 1, ?5, 0, 0, 0)',
      [sku, name, kind, minQty, 'item-uuid-$sku'],
    );
  }

  Future<int> insertRawParty(DiqqahDatabase target, String name,
      {int? creditLimit, int? termDays}) async {
    await target.customStatement(
      'INSERT INTO parties (number, name, kind, default_currency_id, '
      'credit_limit_base_minor, payment_term_days, is_active, uuid, '
      'created_at, updated_at, is_deleted) '
      'VALUES (?1, ?1, \'customer\', 1, ?2, ?3, 1, ?4, 0, 0, 0)',
      [
        name,
        creditLimit,
        termDays,
        'party-uuid-$name',
      ],
    );
    final row = await target.customSelect(
      'SELECT id FROM parties WHERE name = ?1',
      variables: [Variable.withString(name)],
    ).get();
    return row.single.data['id'] as int;
  }

  /// قيد مرحّل لطرف — بالمسار المشروع عبر الحواجز (مسودة ثم أسطر ثم ترحيل).
  Future<void> insertPostedPartyMove(
      DiqqahDatabase target, int partyId, int debit, int credit) async {
    // بالمسار المشروع عبر الحواجز: قيد مسودة ثم أسطره ثم الترحيل
    // (DQ-0105 تمنع أسطرَ المرحّل حصراً).
    await target.customStatement(
      'INSERT INTO moves (journal_id, date_text, state, number, uuid) '
      'VALUES (1, \'2026-06-01\', \'draft\', \'ق1\', ?1)',
      ['move-uuid-$partyId-$debit-$credit'],
    );
    final mv = await target.customSelect(
      'SELECT id FROM moves ORDER BY id DESC LIMIT 1',
    ).get();
    final moveId = mv.single.data['id'] as int;
    await target.customStatement(
      'INSERT INTO move_lines (move_id, account_id, debit_minor, '
      'credit_minor, party_id, uuid) VALUES '
      '(?1, 1, ?2, ?3, ?4, ?5), (?1, 1, ?3, ?2, NULL, ?6)',
      [
        moveId,
        debit,
        credit,
        partyId,
        'line-uuid-$partyId-$debit-$credit',
        'line2-uuid-$partyId-$debit-$credit',
      ],
    );
    await target.customStatement(
      "UPDATE moves SET state = 'posted' WHERE id = ?1",
      [moveId],
    );
  }

  /// فاتورة بيع مرحّلة مفتوحة — مرساتها الاستحقاق وإلا التاريخ.
  Future<void> insertPostedSaleInvoice(
      DiqqahDatabase target, int partyId, String dateText,
      {String? dueDate, int totalDoc = 1000}) async {
    await target.customStatement(
      'INSERT INTO invoices (kind, number, party_id, invoice_date, '
      'due_date, currency_id, fx_rate, total_doc_minor, state, uuid) '
      "VALUES ('sale', 'ف-1', ?1, ?2, ?3, 1, 1, ?4, 'posted', ?5)",
      [
        partyId,
        dateText,
        dueDate,
        totalDoc,
        'inv-uuid-$partyId-$dateText',
      ],
    );
  }

  test('القاعدة الجديدة تولد بعمودَي د6 والإصدار 32 حرفاً', () async {
    expect(db.schemaVersion, DiqqahDatabase.schemaVersionValue,
        reason: 'د6 (س175): ترحيلة المتابعات اليومية');
    final itemCols = (await db.customSelect(
            "SELECT name FROM pragma_table_info('items')")
          .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(itemCols, contains('min_qty'),
        reason: 'العمود من أول إنشاء (onCreate)');
    final partyCols = (await db.customSelect(
            "SELECT name FROM pragma_table_info('parties')")
          .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(partyCols, contains('payment_term_days'));
    final ic = await db.customSelect('PRAGMA integrity_check').get();
    expect(ic.single.data['integrity_check'], 'ok');
  });

  test('ترحيلة v32 على قاعدة v31 بشكلها الحرفي: الصفوف القائمة تملأ '
      'null بلا إعادة بناء ولا مساس وآمنة التكرار', () async {
    // بيانات قائمة بشكل v31: طرف وصنف قبل نزع العمودين.
    final partyId = await insertRawParty(db, 'طرف قديم');
    await insertRawItem(db, 'OLD-1', 'صنف قديم', 'good');

    // الهبوط لشكل v31 الحرفي: نزع المشغلات الناظمة للجدولين ثم إسقاط
    // العمودين وإزالة الإصدار — أي ما ستراه أجهزة المالك الحقيقية
    // عند أول فتح فوق قاعدة س174.
    await db.close();
    final raw = sql.sqlite3.open(dbPath);
    final triggers = raw.select(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND (tbl_name = 'items' OR tbl_name = 'parties')");
    for (final t in triggers) {
      raw.execute('DROP TRIGGER "${t['name']}"');
    }
    raw.execute('ALTER TABLE items DROP COLUMN min_qty');
    raw.execute('ALTER TABLE parties DROP COLUMN payment_term_days');
    raw.execute('PRAGMA user_version = 31');
    raw.dispose();

    // إعادة الفتح تثير الترقية 31→32: العمودان يعودان والصفوف القائمة
    // تملأ null (لا إعادة بناء ولا مساس).
    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue,
        reason: 'سلسلة الترقية كاملة والمخطط الجاري ديناميكي');
    final party = await migrated.customSelect(
      'SELECT payment_term_days FROM parties WHERE id = ?1',
      variables: [Variable.withInt(partyId)],
    ).get();
    expect(party.single.data['payment_term_days'], isNull,
        reason: 'الصف القائم يملأ null بلا كتابة');
    final oldItem = await migrated.customSelect(
      "SELECT min_qty FROM items WHERE sku = 'OLD-1'",
    ).get();
    expect(oldItem.single.data['min_qty'], isNull);
    final ic = await migrated.customSelect('PRAGMA integrity_check').get();
    expect(ic.single.data['integrity_check'], 'ok');

    // إعادة الفتح ثانية: آمنة التكرار بلا إعادة ترحيلة ولا مساس.
    await migrated.close();
    final again = DiqqahDatabase(filePath: dbPath);
    addTearDown(again.close);
    expect(again.schemaVersion, DiqqahDatabase.schemaVersionValue);
    final kept = await again.customSelect(
      "SELECT name FROM parties WHERE id = ?1",
      variables: [Variable.withInt(partyId)],
    ).get();
    expect(kept.single.data['name'], 'طرف قديم',
        reason: 'البيانات باقية حرفاً');
  });

  test('حرس الموجب: الصفر والسالب يُخزَّنان null — الحد الموجب حصراً',
      () async {
    final itemId = await db.insertItem(
      sku: 'MIN-TEST',
      name: 'صنف الحد',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: 0,
    );
    var row = await db.customSelect(
      'SELECT min_qty FROM items WHERE id = ?1',
      variables: [Variable.withInt(itemId)],
    ).get();
    expect(row.single.data['min_qty'], isNull,
        reason: 'الصفر بلا معنى للمتابعة فلا حد أدنى صفر');

    await db.updateItemDetails(
      await (db.select(db.items)..where((t) => t.id.equals(itemId)))
          .getSingle(),
      sku: 'MIN-TEST',
      name: 'صنف الحد',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: -5,
    );
    row = await db.customSelect(
      'SELECT min_qty FROM items WHERE id = ?1',
      variables: [Variable.withInt(itemId)],
    ).get();
    expect(row.single.data['min_qty'], isNull, reason: 'السالب كالصفر');

    await db.updateItemDetails(
      await (db.select(db.items)..where((t) => t.id.equals(itemId)))
          .getSingle(),
      sku: 'MIN-TEST',
      name: 'صنف الحد',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: 12,
    );
    row = await db.customSelect(
      'SELECT min_qty FROM items WHERE id = ?1',
      variables: [Variable.withInt(itemId)],
    ).get();
    expect(row.single.data['min_qty'], 12, reason: 'الموجب يُخزَّن كما هو');

    final partyId = await insertRawParty(db, 'طرف المدة');
    await db.updatePartyDetails(
      await (db.select(db.parties)..where((t) => t.id.equals(partyId)))
          .getSingle(),
      number: 'طرف المدة',
      name: 'طرف المدة',
      kind: 'customer',
      defaultCurrencyId: 1,
      creditLimitBaseMinor: null,
      paymentTermDays: 0,
    );
    var prow = await db.customSelect(
      'SELECT payment_term_days FROM parties WHERE id = ?1',
      variables: [Variable.withInt(partyId)],
    ).get();
    expect(prow.single.data['payment_term_days'], isNull,
        reason: 'مدة صفر بلا معنى');
    await db.updatePartyDetails(
      await (db.select(db.parties)..where((t) => t.id.equals(partyId)))
          .getSingle(),
      number: 'طرف المدة',
      name: 'طرف المدة',
      kind: 'customer',
      defaultCurrencyId: 1,
      creditLimitBaseMinor: null,
      paymentTermDays: 30,
    );
    prow = await db.customSelect(
      'SELECT payment_term_days FROM parties WHERE id = ?1',
      variables: [Variable.withInt(partyId)],
    ).get();
    expect(prow.single.data['payment_term_days'], 30);
  });

  test('استعلام تحت الحد الأدنى: السلع حصراً والمتاح عبر المستودعات '
      'والنقص الأشد أولاً', () async {
    // المستودع الرئيسي مزرَع بالتهيئة — والفرعي جديد بنا.
    final w1Row = await db
        .customSelect("SELECT id FROM warehouses WHERE name = 'المستودع الرئيسي'")
        .get();
    final w1 = w1Row.single.data['id'] as int;
    final w2 = await db.warehouseCreate(name: 'المستودع الفرعي');
    final belowA = await db.insertItem(
      sku: 'A',
      name: 'ألف تحت الحد',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: 10,
    );
    final enough = await db.insertItem(
      sku: 'B',
      name: 'باء فوق الحد',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: 5,
    );
    await db.insertItem(
      sku: 'C',
      name: 'جيم بلا مخزون أصلاً',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: 3,
    );
    await db.insertItem(
      sku: 'D',
      name: 'دال خدمة بلا مخزون',
      kind: 'service',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
      minQty: 2,
    );
    await db.insertItem(
      sku: 'E',
      name: 'هاء بلا حد',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );
    // المتاح عبر مستودعين: 4+7=11 فوق حده (5) فلا متابعة.
    for (final (wid, qty) in [(w1, 4), (w2, 7)]) {
      await db.customStatement(
        'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
        'total_value_minor, uuid, created_at, updated_at, is_deleted) '
        'VALUES (?1, ?2, ?3, 0, ?4, 0, 0, 0)',
        [enough, wid, qty, 'sb-uuid-$enough-$wid'],
      );
    }
    // ألف بمستودع واحد 4 تحت حده (10).
    await db.customStatement(
      'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
      'total_value_minor, uuid, created_at, updated_at, is_deleted) '
      'VALUES (?1, ?2, 4, 0, ?3, 0, 0, 0)',
      [belowA, w1, 'sb-uuid-$belowA'],
    );
    final rows = await db.itemsBelowMinimum();
    expect(rows.map((r) => r.sku).toList(), ['A', 'C'],
        reason: 'ألف بالنقص الأشد ثم جيم بلا مخزون — والبقية صامتة');
    expect(rows.first.availableQty, 4);
    expect(rows.first.minimumQty, 10);
    expect(rows.last.availableQty, 0,
        reason: 'الغائب عن المخزون متاحه صفر لا خطأ');
  });

  test('استعلام فوق السقف المبلغي: التجاوز أشد من السقف والدين قائم',
      () async {
    final over = await insertRawParty(db, 'فوق السقف',
        creditLimit: 1000);
    final atCap = await insertRawParty(db, 'عند السقف تماماً',
        creditLimit: 1000);
    final below = await insertRawParty(db, 'دون السقف',
        creditLimit: 1000);
    final noCap = await insertRawParty(db, 'بلا سقف س-34');
    final negative = await insertRawParty(db, 'نحن المدينون',
        creditLimit: 1000);
    await insertPostedPartyMove(db, over, 1500, 0);
    await insertPostedPartyMove(db, atCap, 1000, 0);
    await insertPostedPartyMove(db, below, 500, 0);
    await insertPostedPartyMove(db, noCap, 5000, 0);
    await insertPostedPartyMove(db, negative, 0, 200);

    final rows = await db.partiesOverCreditCap();
    expect(rows.map((r) => r.partyName).toList(), ['فوق السقف'],
        reason: 'التمام للسقف ليس تجاوزاً (F-164) والسقف الفراغي لا '
            'ينذر (س-34) والدين السالب صامت');
    expect(rows.single.netDebitBaseMinor, 1500);
    expect(rows.single.capBaseMinor, 1000);
  });

  test('استعلام فوق السقف الزمني: مدة السداد بمرساة الأعمار والباقي '
      'المفتوح — والتغطية السندية تسقط المسدد والغائب بلا مدة صامت',
      () async {
    final nowLocal = DateTime(2026, 11, 19);
    final overdue = await insertRawParty(db, 'متأخر عن المدة',
        termDays: 30);
    final fresh = await insertRawParty(db, 'حديث العهد',
        termDays: 30);
    final noTerm = await insertRawParty(db, 'بلا مدة');
    final covered = await insertRawParty(db, 'سدَّد سنداً كاملاً',
        termDays: 30);
    final dueAnchor = await insertRawParty(db, 'الاستحقاق مرساة',
        termDays: 10);

    await insertPostedSaleInvoice(db, overdue, '2026-06-01');
    await insertPostedSaleInvoice(db, fresh, '2026-11-19');
    await insertPostedSaleInvoice(db, noTerm, '2026-01-01');
    await insertPostedSaleInvoice(db, covered, '2026-01-01');
    // الاستحقاق مرساة: تاريخ قريب باستحقاق قديم فالعمر من الاستحقاق.
    await insertPostedSaleInvoice(db, dueAnchor, '2026-11-01',
        dueDate: '2026-09-01');

    // تغطية سند مرحّل كاملة لفاتورة السدَّد — بالمسار المشروع عبر
    // الحواجز: سند مسودة ثم المطابقة ثم الترحيل (DQ-0305 تمنع
    // مطابات المرحّل حصراً) — الباقي صفر فلا مفتوح.
    await db.customStatement(
      'INSERT INTO vouchers (kind, party_id, cash_box_id, voucher_date, '
      'currency_id, fx_rate, amount_doc_minor, state, uuid) '
      "VALUES ('receipt', ?1, 1, '2026-07-01', 1, 1, 1000, 'draft', ?2)",
      [covered, 'voucher-uuid-$covered'],
    );
    final vrow = await db.customSelect(
      'SELECT id FROM vouchers ORDER BY id DESC LIMIT 1',
    ).get();
    final irow = await db.customSelect(
      'SELECT id FROM invoices WHERE party_id = ?1',
      variables: [Variable.withInt(covered)],
    ).get();
    await db.customStatement(
      'INSERT INTO voucher_allocations (voucher_id, invoice_id, '
      'applied_doc_minor, applied_base_minor, uuid) '
      'VALUES (?1, ?2, 1000, 1000, ?3)',
      [
        vrow.single.data['id'] as int,
        irow.single.data['id'] as int,
        'alloc-uuid-$covered',
      ],
    );
    await db.customStatement(
      "UPDATE vouchers SET state = 'posted' WHERE id = ?1",
      [vrow.single.data['id'] as int],
    );

    final rows = await db.partiesOverPaymentTerm(nowLocal: nowLocal);
    expect(rows.map((r) => r.partyName).toList(),
        ['متأخر عن المدة', 'الاستحقاق مرساة'],
        reason: 'الأشد تجاوزاً أولاً — والباقي صامت: الحديث لم تُدّ '
            'مدته، وبلا مدة لا سقف زمني، والمغطى سنداً بلا فاتورة '
            'مفتوحة');
    final dueRow = rows.last;
    expect(dueRow.oldestAnchorText, '2026-09-01',
        reason: 'المرساة الاستحقاق لا التاريخ');
    expect(dueRow.oldestAgeDays, 79,
        reason: 'من 2026-09-01 إلى 2026-11-19: 30+31+18=79 يوماً');
    expect(dueRow.termDays, 10);
    final overdueRow = rows.first;
    expect(overdueRow.oldestAnchorText, '2026-06-01');
    expect(overdueRow.oldestAgeDays, 171,
        reason: 'من 2026-06-01 إلى 2026-11-19 بالأيام الكاملة');
  });

  test('مفاتيح سجلات العمل الجماعي: حفظ وقراءة وجولة ثانية والغائب '
      'null', () async {
    expect(await db.joinCodeBookText(), isNull,
        reason: 'null قبل أول إصدار');
    expect(await db.deviceRegistryText(), isNull);
    expect(await db.cloudArchiveStateText(), isNull);

    await db.saveJoinCodeBookText('{"version":1,"records":[]}');
    await db.saveDeviceRegistryText('{"version":1,"devices":[]}');
    await db.saveCloudArchiveStateText('{"lastSuccess":null}');

    expect(await db.joinCodeBookText(), '{"version":1,"records":[]}');
    expect(await db.deviceRegistryText(), '{"version":1,"devices":[]}');
    expect(await db.cloudArchiveStateText(), '{"lastSuccess":null}');

    await db.saveJoinCodeBookText('{"version":1,"records":[{"code":"X"}]}');
    expect(await db.joinCodeBookText(),
        '{"version":1,"records":[{"code":"X"}]}',
        reason: 'الكتابة الثانية تستبدل لا تكرر');
    final ic = await db.customSelect('PRAGMA integrity_check').get();
    expect(ic.single.data['integrity_check'], 'ok');
  });
}
