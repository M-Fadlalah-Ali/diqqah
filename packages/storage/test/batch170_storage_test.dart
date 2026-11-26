// اختبارات د3 (س170 — الترقيم متعدد الأجهزة وتعدد الشركات بموضع
// م-٥/D-188): ترحيلة v31 «كل حدث يحمل company_id» — عمود واحد بdefault
// الشركة الافتراضية الواحدة (F-111) بADD COLUMN بحرس pragma (درس v3).
// التغطية:
//   (1) القاعدة الجديدة تولد بالعمود والإصدار 31 حرفاً والإدراج يملأ
//       الافتراضية بلا كتابة صريحة.
//   (2) القاعدة القائمة v30 (بشكلها الحرفي بلا العمود وببياناتها)
//       ترقى 30→31 فالصفوف القائمة تملأ 'main' بلا إعادة بناء ولا
//       مساس، وآمنة التكرار بلا مساس عند إعادة الفتح.
// الحاكم: integrity_check=ok والبيانات باقية حرفاً (عرف الفئة 1).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late Directory tempDir;
  late DiqqahDatabase db;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_d3_test_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase(filePath: dbPath);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> insertEvent(DiqqahDatabase target, String uuid) async {
    await target.into(target.events).insert(
          EventsCompanion.insert(
            eventAt: 1760000000,
            deviceId: 'DESHT-01',
            entityType: 'move',
            entityId: const Value(1),
            action: 'posted',
            payload: 'لقطة حدث عربية',
            uuid: uuid,
          ),
        );
  }

  test('القاعدة الجديدة تولد بعمود company_id والإصدار الجاري 32 '
      'والإدراج يمتلئ بالافتراضية', () async {
    // د6 (س175): ترحيلة v32 المتابعات اليومية رفعت الثابت — company_id
    // بلا مساس وافتراضيتها كما هي.
    expect(db.schemaVersion, DiqqahDatabase.schemaVersionValue);
    final cols = await db.customSelect(
        "SELECT name, dflt_value FROM pragma_table_info('events')").get();
    final company = cols
        .where((r) => r.data['name'] == 'company_id')
        .toList();
    expect(company.length, 1, reason: 'العمود من أول إنشاء (onCreate)');
    expect(company.single.data['dflt_value'], "'main'",
        reason: 'الافتراضية ضمن DDL drift ذاته');
    await insertEvent(db, 'evt-1');
    final row = await db.select(db.events).getSingle();
    expect(row.companyId, 'main',
        reason: 'الشركة الافتراضية الواحدة F-111 بلا كتابة صريحة');
    final ic = await db.customSelect('PRAGMA integrity_check').get();
    expect(ic.single.data['integrity_check'], 'ok');
  });

  test('ترحيلة v31 على قاعدة v30 بشكلها الحرفي: الصفوف تملأ main بلا '
      'إعادة بناء ولا مساس وآمنة التكرار', () async {
    await insertEvent(db, 'evt-1');
    await insertEvent(db, 'evt-2');

    // الهبوط لشكل v30 الحرفي: نزع المشغلات الناظمة للجدول ثم إسقاط
    // العمود وإزالة الإصدار — أي ما ستراه أجهزة المالك الحقيقية عند
    // أول فتح فوق قاعدة س164.
    await db.close();
    final raw = sql.sqlite3.open(dbPath);
    final triggers = raw.select(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND (tbl_name = 'events' OR sql LIKE '%events%')");
    for (final t in triggers) {
      raw.execute('DROP TRIGGER "${t['name']}"');
    }
    raw.execute('ALTER TABLE events DROP COLUMN company_id');
    raw.execute('PRAGMA user_version = 30');
    raw.dispose();

    // إعادة الفتح تثير الترقية 30→31: العمود يعود والصفوف القائمة
    // تملأ بالافتراضية (لا إعادة بناء ولا مساس بغيره).
    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    final rows = await migrated.select(migrated.events).get();
    // د6 (س175): سلسلة الترقية 30→31→32 كاملة والمخطط الجاري 32.
    expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);
    expect(rows.length, 2, reason: 'البيانات باقية حرفاً');
    for (final r in rows) {
      expect(r.companyId, 'main',
          reason: 'الصف القائم يمتلئ بالافتراضية بلا كتابة');
      expect(r.uuid, anyOf('evt-1', 'evt-2'));
    }
    final ic = await migrated.customSelect('PRAGMA integrity_check').get();
    expect(ic.single.data['integrity_check'], 'ok');

    // إعادة الفتح ثانية: آمنة التكرار بلا إعادة ترحيلة ولا مساس.
    await migrated.close();
    final again = DiqqahDatabase(filePath: dbPath);
    addTearDown(again.close);
    final againRows = await again.select(again.events).get();
    expect(again.schemaVersion, DiqqahDatabase.schemaVersionValue);
    expect(againRows.length, 2);
    for (final r in againRows) {
      expect(r.companyId, 'main');
    }
  });

  test('إدراج بقيمة صريحة يُكتب كما هي — الطريق لإدارة التعدد F-112',
      () async {
    await db.into(db.events).insert(
          EventsCompanion.insert(
            eventAt: 1760000000,
            deviceId: 'HATF-02',
            entityType: 'move',
            entityId: const Value(2),
            action: 'posted',
            payload: 'لقطة شركة أخرى',
            uuid: 'evt-3',
            companyId: const Value('branch-co'),
          ),
        );
    final row = await (db.select(db.events)
          ..where((t) => t.uuid.equals('evt-3')))
        .getSingle();
    expect(row.companyId, 'branch-co',
        reason: 'الكتابة الصريحة تمر كما هي — والعزل للخادم مع د4');
  });
}
