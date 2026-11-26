import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// ═══ اختبار مسار الجهاز الحقيقي — علة الجهاز الموثقة (س97، جذر D-197) ═══
///
/// العلة الميدانية: تحديث جهاز المالك من b24 (v14) إلى b26 (v23) علّق
/// الافتتاح بدورة أبدية — ولوق المالك الأول (الرسالة النصية الحرفية)
/// حسم الرمي: «SqliteException(1): no such table: main.stock_receipts —
/// Causing statement: CREATE TRIGGER trg_stock_receipts_closed_period_insert
/// ...». الجذر: خطوة v16 تعيد بناء حواجز الإقفال وقائمة الحواجز تتضمن
/// جدولا الإذنين (v17) الذي لم تولَّد بعد على مسار يبدأ من ≥10 — وخطوة v9
/// الباذرة لا تُعاد على تلك المسارات (درس س79 عولج لجداول الجرد فقط).
///
/// هذا الاختبار يبني قاعدة على هيئة v14 الوافية — قاعدة إنتاج كاملة
/// (شكل v23) تُنتزع منها كل كائنات v15..v23 وأعمدتها الجديدة ثم
/// user_version=14 مع بيانات مالك واقعية — ثم يفتحها بمحرك الترحيل
/// نفسه فتجري الخطوات v15→v23 كاملة كما على الجهاز حرفاً:
/// أي ثقب ترتيب مستقبلي في الحواجز يفشل هنا فوراً بنفس لسان الجهاز.
///
/// الوافية الموثقة (انحيازان مقصودان لا أثر لهما على المسار):
/// (1) مُشغّلا تجميد stock_moves/invoice_lines تُطرح قبل انتزاع
///     أعمدتهما الجديدة لأن شكل v23 منهما يحيل أعمدة لم تولد بعد —
///     وجهاز v14 حامل شكلهما القديم — والترحيل لا يمسهما ثم تعيد
///     v21 بناء مُشغّل الأسطر بنشكله الحالي (نمط v21 الموثق).
/// (2) حواجز الإقفال الثمانية عشر تُطرح كلها — والجهاز حامل حواجز
///     خمسة جداول من زمن v9 — والترحيل DROP+CREATE يعيد بناءها كلها
///     أي كان ما حمله الجهاز (درس v9 الموثق).
///
/// الشكل v14 == شكل v23 ناقص كائنات v15..v23: خطوات v15..v23 لم تضف
/// أعمدة إلا الأربعة المنتزعة هنا (v18 بitems وv19 بstock_moves و
/// v21 بinvoice_lines) ولم تمس جدولا قائماً بإعادة بناء — فالانتزاع
/// يولد شكل v14 حرفاً (توثيق س85/س93/س94).

/// كائنات v15..v23 الجديدة كلها — جداول ومُشغّلات تجميد الفئات الأربع
/// (التحويل/الجرد/الإذنان/التجميع) وأسعار الصرف وجداول التعبئة
/// والمكونات (createAll) — على أسماء البواني الموثقة (v15/v16/v17/
/// v20/v23 و DriftDatabase).
const _v15PlusTables = <String>[
  'stock_transfers',
  'stock_transfer_lines',
  'stock_counts',
  'stock_count_lines',
  'stock_receipts',
  'stock_receipt_lines',
  'stock_issues',
  'stock_issue_lines',
  'assemblies',
  'assembly_lines',
  'exchange_rate',
  'unit_groups',
  'unit_group_levels',
  'item_level_prices',
  'bundle_components',
];

final _v15PlusTriggers = <String>[
  // v15 — التحويل المخزني وجدولاها
  'trg_stock_transfers_frozen_delete',
  'trg_stock_transfers_frozen_update',
  'trg_stock_transfer_lines_frozen_delete',
  'trg_stock_transfer_lines_frozen_update',
  // v16 — الجرد وأسطره
  'trg_stock_counts_frozen_delete',
  'trg_stock_counts_frozen_update',
  'trg_stock_count_lines_frozen_delete',
  'trg_stock_count_lines_frozen_update',
  // v17 — إذنا المخزون وأسطرهما
  'trg_stock_receipts_frozen_delete',
  'trg_stock_receipts_frozen_update',
  'trg_stock_receipt_lines_frozen_delete',
  'trg_stock_receipt_lines_frozen_update',
  'trg_stock_issues_frozen_delete',
  'trg_stock_issues_frozen_update',
  'trg_stock_issue_lines_frozen_delete',
  'trg_stock_issue_lines_frozen_update',
  // v20 — مستند التجميع وأسطره
  'trg_assemblies_frozen_delete',
  'trg_assemblies_frozen_update',
  'trg_assembly_lines_frozen_delete',
  'trg_assembly_lines_frozen_update',
  // v23 — أسعار الصرف
  'trg_exchange_rate_frozen_delete',
  'trg_exchange_rate_frozen_update',
  // حواجز الإقفال الثمانية عشر (DROP+CREATE بالترحيل أي كان حمل الجهاز)
  for (final t in const [
    'moves',
    'invoices',
    'vouchers',
    'box_transfers',
    'cash_adjustments',
    'stock_counts',
    'stock_receipts',
    'stock_issues',
  ]) ...[
    'trg_${t}_closed_period_insert',
    'trg_${t}_closed_period_post',
  ],
];

/// يبني قاعدة على هيئة v14 الوافية ببيانات مالك واقعية — ويخدم الاختبارين.
Future<String> buildLegacyV14Database(String dirPath) async {
  final dbPath = p.join(dirPath, 'diqqah.db');

  // 1) قاعدة إنتاج كاملة على الملف (createAll + البواني + البذر) —
  //    ثم إغلاقها ليعمل الانتزاع على ملف ساكن بلا اتصال.
  final boot = DiqqahDatabase(filePath: dbPath);
  await boot.customSelect('SELECT 1').get();
  await boot.close();

  // 2) الانتزاع خاماً — كل كائن v15..v23 وأعمدة v15..v23 الجديدة.
  final raw = sqlite3.open(dbPath);
  final statements = <String>[
    for (final t in _v15PlusTables) 'DROP TABLE IF EXISTS $t',
    for (final trg in _v15PlusTriggers) 'DROP TRIGGER IF EXISTS $trg',
    'DROP INDEX IF EXISTS ux_stock_count_lines_session_item',
    // انحياز الوافية (1): شكل v23 من المُشغّلَين يحيل أعمدة v19/v21 —
    // تُطرح هنا وجهاز v14 حامل شكله القديم، والترحيل يعيد البناء.
    'DROP TRIGGER IF EXISTS trg_stock_moves_frozen_update',
    'ALTER TABLE stock_moves DROP COLUMN move_detail',
    'DROP TRIGGER IF EXISTS trg_invoice_lines_frozen_update',
    'ALTER TABLE invoice_lines DROP COLUMN unit_level_id',
    // أعمدة v18 على items — لا مُشغّل يحيلها فانتزاع مباشر.
    'ALTER TABLE items DROP COLUMN unit_group_id',
    'ALTER TABLE items DROP COLUMN price_auto',
    'PRAGMA user_version = 14',
  ];
  for (final sql in statements) {
    raw.execute(sql);
  }

  // 3) بيانات مالك واقعية على الشكل v14 — مستخدم مدير وأصناف وفاتورة
  //    مسودة بسطرين وجهاز معرَّف — كلها على عرف إدخالات raw بالاختبارات.
  raw.execute(
    "INSERT INTO app_meta (key, value) VALUES ('device_id', "
    "'legacy-device-2026')",
  );
  final roleId =
      (raw.select('SELECT id FROM roles ORDER BY id LIMIT 1').first)['id']
          as int;
  raw.execute(
    "INSERT INTO app_users (name, login, password_hash, role_id, "
    "is_active, uuid, created_at, updated_at, is_deleted) VALUES "
    "('المدير القديم', 'owner', 'salt:legacy-hash', $roleId, 1, "
    "'uuid-user-legacy', 0, 0, 0)",
  );
  for (final (sku, name) in const [
    ('SKU-LEGACY-1', 'بضاعة الجهاز الأولى'),
    ('SKU-LEGACY-2', 'بضاعة الجهاز الثانية'),
  ]) {
    raw.execute(
      "INSERT INTO items (sku, name, kind, base_unit_id, "
      "purchase_price_minor, sale_price_minor, price_currency_id, "
      "is_active, uuid) VALUES ('$sku', '$name', 'good', 1, 250000, "
      "275000, 1, 1, 'uuid-$sku')",
    );
  }
  raw.execute(
    "INSERT INTO invoices (kind, number, party_id, cash_box_id, "
    "warehouse_id, invoice_date, due_date, currency_id, fx_rate, "
    "discount_rate, subtotal_doc_minor, discount_doc_minor, "
    "total_doc_minor, total_base_minor, state, move_id, narration, uuid) "
    "VALUES ('sale', '2026-000001', 1, 1, 1, '2026-01-10', '2026-01-20', "
    "1, 100, 0, 550000, 0, 550000, 550000, 'draft', 0, 'فاتورة الجهاز "
    "القديمة', 'uuid-inv-legacy')",
  );
  final invoiceId =
      (raw.select('SELECT MAX(id) AS m FROM invoices').first)['m'] as int;
  for (final (item, qty) in const [(1, 2), (2, 1)]) {
    raw.execute(
      'INSERT INTO invoice_lines (invoice_id, item_id, unit_id, '
      'factor_at_entry, qty, qty_base, unit_price_minor, discount_minor, '
      'tax_rate, line_total_doc_minor, line_total_base_minor, delivered, '
      'supplier_party_id, delivery_note, uuid) VALUES ($invoiceId, $item, '
      '1, 1, $qty, $qty, 275000, 0, 0, ${qty * 275000}, ${qty * 275000}, '
      "0, NULL, NULL, 'uuid-inv-line-$item')",
    );
  }
  raw.close();
  return dbPath;
}

void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('diqqah_v14_device_');
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'مسار الجهاز الحقيقي v14→v24 — الحاجز لا يسبق جدوله على أي مسار '
    '(علة الجهاز الموثقة س97) وترحيلة أساس الأخطاء س107',
    () async {
      final dbPath = await buildLegacyV14Database(tempDir.path);

      // شكل ما قبل الفتح: v14 فعلاً وجداول الإذنين غائبة — شرط العلة.
      final pre = sqlite3.open(dbPath);
      expect(pre.select('PRAGMA user_version').first['user_version'], 14);
      final preTables = pre
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      expect(preTables, isNot(contains('stock_receipts')));
      expect(preTables, isNot(contains('stock_issues')));
      pre.close();

      // الفتح بمحرك الترحيل نفسه — هنا انفجر الجهاز بـ«no such table:
      // main.stock_receipts» (حاجز v16 على جدول v17) — فلا رمي ولا
      // دوران: الترحيل v15→v23 يكمل على هيئة الجهاز الوافية.
      final db = DiqqahDatabase(filePath: dbPath);
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      expect(db.schemaVersion, DiqqahDatabase.schemaVersionValue);

      // أ) جدولا الإذنين وُلدا والحاجزان الأربعة عليهما قائمة فعلاً —
      //    توقيع إصلاح العلة (قبل الإصلاح الفتح يرمي قبل هذا السطر).
      final barriers = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name IN "
        "('trg_stock_receipts_closed_period_insert', "
        "'trg_stock_receipts_closed_period_post', "
        "'trg_stock_issues_closed_period_insert', "
        "'trg_stock_issues_closed_period_post')",
      ).get();
      expect(barriers, hasLength(4));
      // ومُشغّلا تجميد الإذن قائمان من بذر الخطوة لا من بقايا.
      final frozen = await db.customSelect(
        "SELECT COUNT(*) c FROM sqlite_master WHERE type='trigger' AND "
        "name IN ('trg_stock_receipts_frozen_update', "
        "'trg_stock_receipts_frozen_delete')",
      ).getSingle();
      expect(frozen.data['c'], 2);

      // ب) بيانات المالك كما هي — الترحيلة لم تلمس صفاً قائماً:
      expect(
        (await db
                .customSelect('SELECT COUNT(*) c FROM app_users')
                .getSingle())
            .data['c'],
        1,
      );
      expect(
        (await db.customSelect('SELECT COUNT(*) c FROM items').getSingle())
            .data['c'],
        2,
      );
      expect(
        (await db
                .customSelect("SELECT name FROM items WHERE sku = 'SKU-LEGACY-1'")
                .getSingle())
            .data['name'],
        'بضاعة الجهاز الأولى',
      );
      expect(
        (await db.customSelect('SELECT COUNT(*) c FROM invoices').getSingle())
            .data['c'],
        1,
      );
      expect(
        (await db
                .customSelect('SELECT COUNT(*) c FROM invoice_lines')
                .getSingle())
            .data['c'],
        2,
      );
      expect(
        (await db
                .customSelect('SELECT COUNT(*) c FROM accounts')
                .getSingle())
            .data['c'],
        // س104: 58 الدليل المعتمد + 116 «تحصيلات في الطريق» المبذور
        // قبل كل فتح (بذر بيان لا مخطط — فيدخل بمسار الجهاز أيضاً).
        59,
      );
      expect(
        (await db
                .customSelect('SELECT COUNT(*) c FROM journals')
                .getSingle())
            .data['c'],
        5,
      );
      expect(
        (await db
                .customSelect('SELECT COUNT(*) c FROM periods')
                .getSingle())
            .data['c'],
        12,
      );
      // ومعرف الجهاز من app_meta يعود كما هو (F-015 بالبقاء التام).
      expect(
        (await db
                .customSelect(
                  "SELECT value FROM app_meta WHERE key = 'device_id'",
                )
                .getSingle())
            .data['value'],
        'legacy-device-2026',
      );

      // ج) الحاجز حي فعلاً فوق بيانات الجهاز: فترة تُقفل ثم إدراج خام
      //    مرحّل داخلها يُحبط بلسان الحاجز (نمط القلب الموثق — إدراج
      //    متجاوز للمحرك عمداً).
      final journalId = (await db
              .customSelect('SELECT id FROM journals ORDER BY id LIMIT 1')
              .getSingle())
          .data['id'] as int;
      final period = await db
          .customSelect(
            'SELECT id, start_date_text FROM periods WHERE is_deleted = 0 '
            'ORDER BY id LIMIT 1',
          )
          .getSingle();
      final periodId = period.data['id'] as int;
      final periodStart = period.data['start_date_text'] as String;
      await db.customStatement(
        'UPDATE periods SET state = ? WHERE id = ?',
        ['closed', periodId],
      );
      var blocked = '';
      try {
        await db.customStatement(
          "INSERT INTO moves (journal_id, date_text, state, number, uuid) "
          "VALUES (?, ?, 'posted', '', 'uuid-barrier-fire')",
          [journalId, periodStart],
        );
        fail('الحاجز لم يُحبط إدراج الخام في الفترة المقفلة');
      } on Exception catch (e) {
        blocked = e.toString();
      }
      expect(blocked, contains('فترة مقفلة'));
      // وس107: الحاجز المرمي مرقّم — الرمز DQ-0601 نصاً بلسان الجهاز.
      expect(blocked, contains('DQ-0601'));

      // هـ) س107: جدول error_log وُلد بمسار الجهاز والتسجيل يعمل فوقه
      //    والحواجز المعاد تعريفها حاملة رموزها الجديدة نصاً.
      await db.logError(
          code: 'DQ-0999', message: 'اختبار مسار الجهاز', context: 's107');
      final logged = await db.recentErrors();
      expect(logged, hasLength(1));
      expect(logged.first['code'], 'DQ-0999');
      expect(logged.first['context'], 's107');
      final frozenSql = await db.customSelect(
        "SELECT sql FROM sqlite_master WHERE name = "
        "'trg_moves_posted_frozen'",
      ).getSingle();
      expect(
        (frozenSql.data['sql'] as String).contains('DQ-0103'),
        isTrue,
        reason: 'إعادة التعريف DROP+CREATE بالترحيلة تحدّث نص الحاجز',
      );

      // د) إعادة الفتح على القاعدة المرحّلة نفسها — بلا إعادة ترحيل ولا
      //    رمي (حالة الجهاز بعد نجاح الترقية ثم التشغيل الثاني).
      await db.close();
      final reopened = DiqqahDatabase(filePath: dbPath);
      addTearDown(reopened.close);
      await reopened.customSelect('SELECT 1').get();
      expect(
        (await reopened
                .customSelect('SELECT COUNT(*) c FROM items')
                .getSingle())
            .data['c'],
        2,
      );
    },
  );
}
