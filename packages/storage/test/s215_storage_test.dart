// اختبارات س215 — الثقل الجذري للبيانات الضخمة (ترحيلة v35: فهارس
// طرق الوصول الحارة) بأمر المالك «معالجة الثقل الجذري للبيانات
// الضخمة (فهارس واستعلامات الرئيسية)»:
// (1) القاعدة الجديدة تولد بالفهارس الستة عشر من أول إنشاء
//     (onCreate) بعرف فهرس move_id (v29/د0) — «بأدائها النهائي
//     لا بفجوة».
// (2) القاعدة القائمة (v34 = b70 لدى المالك) ترقى 34→35 فتُبنى
//     الفهارس بترحيلة مخططية واحدة بلا مساس بالبيانات — محاكاة
//     تخفيض user_version بعرف upgrade_snapshot (نمطه الموثق)،
//     وعمود س211 must_change_password باقٍ عبر الترحيلة.
// (3) الدليل الوظيفي: خطة الاستعلام EXPLAIN تحمل اسم الفهرس في
//     مساري T4 (EXISTS على moves بربط ref_doc_type/ref_doc_id) و
//     رصيد الحساب (WHERE account_id) — فالفهرس عتاد لا نص.
// (4) آمنة التكرار: إعادة الفتح بعد نفس الإصدار لا تكسر ولا تُضيف
//     (IF NOT EXISTS بعرف الفهارس الموثقة).
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

/// الفهارس الستة عشر البنيوية للدفعة — بأسمائها الحرفية بالشيفرة.
const kHotDataIndexes = <String>[
  'ix_move_lines_account',
  'ix_move_lines_party',
  'ix_moves_ref',
  'ix_moves_date_text',
  'ix_invoices_deleted_date',
  'ix_invoices_party',
  'ix_invoice_lines_invoice',
  'ix_invoice_lines_item',
  'ix_stock_moves_ref',
  'ix_stock_moves_item',
  'ix_cash_movements_box',
  'ix_events_entity',
  'ix_vouchers_date',
  'ix_stock_transfer_lines_doc',
  'ix_stock_count_lines_doc',
  'ix_assembly_lines_doc',
];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('diqqah_s215');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  Future<List<String>> indexNamesOf(DiqqahDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name IS NOT NULL",
    ).get();
    return rows.map((r) => r.data['name'] as String).toSet().toList()..sort();
  }

  void setRawVersion(String path, int version) {
    final raw = sqlite3.open(path);
    try {
      raw.execute('PRAGMA user_version = $version');
    } finally {
      raw.dispose();
    }
  }

  test('س215 (1): القاعدة الجديدة تولد بالفهارس الستة عشر من أول '
      'إنشاء — وبإصدار v35', () async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);
    expect(db.schemaVersion, DiqqahDatabase.schemaVersionValue);
    expect(DiqqahDatabase.schemaVersionValue, 35);
    final names = await indexNamesOf(db);
    for (final ix in kHotDataIndexes) {
      expect(names, contains(ix),
          reason: 'الفهرس الحار $ix غائب عن قاعدة الإنشاء الكامل');
    }
    // وفهرس د0 القائم باقٍ بجواره (استمرارية س160).
    expect(names, contains('ix_move_lines_move_id'));
  });

  test('س215 (2): القاعدة القائمة v34 ترقى 34→35 فتُبنى الفهارس '
      'بترحيلة مخططية واحدة — وعمود س211 وبيانات البذرة باقية', () async {
    final path = '${tmp.path}/legacy34.db';
    // قاعدة كاملة المخطط (v35 بعد البناء) ثم تخفيض الإصدار إلى 34
    // وإسقاط الفهارس الجديدة — عين حالة قاعدة المالك b70 قبل الدفعة.
    final db = DiqqahDatabase(filePath: path);
    await db.customSelect('SELECT 1').get();
    await db.close();
    final raw = sqlite3.open(path);
    try {
      for (final ix in kHotDataIndexes) {
        raw.execute('DROP INDEX IF EXISTS "$ix"');
      }
    } finally {
      raw.dispose();
    }
    setRawVersion(path, 34);
    // إعادة الفتح: الترحيلة 34→35 تبني الفهارس كلها.
    final migrated = DiqqahDatabase(filePath: path);
    addTearDown(migrated.close);
    final names = await indexNamesOf(migrated);
    for (final ix in kHotDataIndexes) {
      expect(names, contains(ix),
          reason: 'الترحيلة 34→35 لم تبنِ الفهرس الحار $ix');
    }
    // وعمود الترحيلة السابقة (س211) باقٍ — فv35 ترحيلة لا تمس غيرها.
    final userCols = (await migrated
            .customSelect("SELECT name FROM pragma_table_info('app_users')")
            .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(userCols, contains('must_change_password'));
    // والبيانات البنيوية الأخرى لم تُمس: حسابات البذرة موجودة.
    final accounts = await migrated
        .customSelect('SELECT COUNT(*) AS n FROM accounts')
        .get();
    expect((accounts.first.data['n'] as int), greaterThan(0));
  });

  test('س215 (3): خطة الاستعلام تحمل الفهرس — T4 (EXISTS على moves '
      'بربط المستند) يبحث بمؤشر لا بمسح كامل', () async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);
    final plan = await db.customSelect(
      "EXPLAIN QUERY PLAN SELECT i.number FROM invoices i "
      "WHERE i.state IN ('posted', 'paid', 'partially_paid') "
      "AND NOT EXISTS ("
      "  SELECT 1 FROM moves m WHERE m.ref_doc_type = 'invoice' "
      "  AND m.ref_doc_id = i.id AND m.state = 'posted')",
    ).get();
    final details =
        plan.map((r) => '${r.data['detail']}').join('\n');
    expect(details, contains('ix_moves_ref'),
        reason: 'خطة T4 لم تستخدم فهرس ربط المستند: $details');
  });

  test('س215 (3-ب): خطة رصيد الحساب (WHERE account_id على move_lines) '
      'يبحث بمؤشر لا بمسح كامل', () async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);
    final plan = await db.customSelect(
      'EXPLAIN QUERY PLAN SELECT COALESCE(SUM(debit_minor), 0), '
      'COALESCE(SUM(credit_minor), 0) '
      'FROM move_lines WHERE account_id = 1 AND is_deleted = 0',
    ).get();
    expect(plan, isNotEmpty);
    final details =
        plan.map((r) => '${r.data['detail']}').join('\n');
    expect(details, contains('ix_move_lines_account'),
        reason: 'خطة رصيد الحساب لم تستخدم فهرس الحساب: $details');
  });

  test('س215 (4): آمنة التكرار — إعادة الفتح بالإصدار ذاته لا تكسر '
      'والفهارس باقية', () async {
    final path = '${tmp.path}/again.db';
    final first = DiqqahDatabase(filePath: path);
    await first.customSelect('SELECT 1').get();
    await first.close();
    final second = DiqqahDatabase(filePath: path);
    addTearDown(second.close);
    final names = await indexNamesOf(second);
    for (final ix in kHotDataIndexes) {
      expect(names, contains(ix));
    }
  });
}
