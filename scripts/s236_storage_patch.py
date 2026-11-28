#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س236 — د10 البنوك (D-224): رقعة التخزين — الترحيلة v38 (نوع الصندوق
الجارٍ واسم البنك ورقم الحساب + جدول التسويات البنكية) ومحرك مستند
التسوية البنكية بنمط تسوية الصندوق حرفاً (إنشاء + ترحيل ب57 + حركة
صندوق + تسلسل bank_reconciliation) وقائمة التسويات وصفوف تقرير
الصناديق بالنوع واسم البنك."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "packages", "storage", "lib", "src", "database.dart")


def sub(s, old, new, where):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    assert old not in s.replace(old, "", 1) or new in s, "مكرر (%s)" % where
    return s.replace(old, new, 1)


BANK_RECON_TABLE = """    'CREATE TABLE IF NOT EXISTS "bank_reconciliations" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"cash_box_id" INTEGER NOT NULL, '
        '"reconciliation_date" TEXT NOT NULL, '
        '"currency_id" INTEGER NOT NULL DEFAULT 1, '
        '"fx_rate" INTEGER NOT NULL, '
        '"statement_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"book_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"direction" TEXT NOT NULL, '
        '"amount_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"amount_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"reason" TEXT NOT NULL DEFAULT \'\', '
        '"state" TEXT NOT NULL DEFAULT \'draft\', '
        '"move_id" INTEGER NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',"""


def main():
    s = io.open(DB, encoding="utf-8").read()
    if "bank_reconciliations" in s:
        print("التخزين: مرقع مسبقاً — تُتخطى")
        return

    # ١) رقم المخطط + توثيق v38 بعد توثيق v37
    s = sub(s, "static const int schemaVersionValue = 37;",
            "static const int schemaVersionValue = 38;", "رقم المخطط")
    s = sub(s,
            """  /// حرفاً: إلحاق بوابة القوائم المالية الفرعية reports.financials
  /// بكل دور قائم يعتمد التقارير (لا النجمة ولا أمين المستودع
  /// المخصوص بالاسم — «تقارير المخزون حصراً» بقرار المالك) عرف
  /// «من كان يعتمد يبقى يعتمد».
  static const int schemaVersionValue = 38;""",
            """  /// حرفاً: إلحاق بوابة القوائم المالية الفرعية reports.financials
  /// بكل دور قائم يعتمد التقارير (لا النجمة ولا أمين المستودع
  /// المخصوص بالاسم — «تقارير المخزون حصراً» بقرار المالك) عرف
  /// «من كان يعتمد يبقى يعتمد».
  /// وأحدثتها س236 (د10 البنوك D-224 بأمر المالك «نفذ د10»): v38 —
  /// ثلاثة أعمدة على cash_boxes بADD COLUMN بحرس pragma بنمط v31/v36
  /// (kind نقدي/جارٍ بنكي وbank_name وaccount_number لصناديق البنوك)
  /// وجدول bank_reconciliations خالصاً لمستند التسوية البنكية بنمط
  /// cash_adjustments حرفاً (مع رصيدي الكشف والدفتري اللقطة).
  static const int schemaVersionValue = 38;""",
            "توثيق v38")

    # ٢) كتلة الترحيلة v38 في onUpgrade بعد كتلة v37
    s = sub(s, """                [DateTime.now().millisecondsSinceEpoch],
              );
            }
          }
        },""",
            """                [DateTime.now().millisecondsSinceEpoch],
              );
            }
            // 37→38 (ومن إصدار أدنى مباشرة): س236 (د10 البنوك D-224):
            // أعمدة النوع والبنك على الصناديق بحرس pragma (آمنة التكرار
            // أي كان مسار الوصول) وجدول التسويات البنكية الخالص.
            if (version == 38) {
              final boxCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('cash_boxes')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!boxCols.contains('kind')) {
                await customStatement(
                    "ALTER TABLE cash_boxes ADD COLUMN "
                    "kind TEXT NOT NULL DEFAULT 'cash'");
              }
              if (!boxCols.contains('bank_name')) {
                await customStatement(
                    'ALTER TABLE cash_boxes ADD COLUMN '
                    'bank_name TEXT NULL');
              }
              if (!boxCols.contains('account_number')) {
                await customStatement(
                    'ALTER TABLE cash_boxes ADD COLUMN '
                    'account_number TEXT NULL');
              }
              await _createBankReconciliationTableTx();
            }
          }
        },""",
            "كتلة v38")

    # ٣) أعمدة النوع على إنشاء cash_boxes (onCreate)
    s = sub(s, """    'CREATE TABLE IF NOT EXISTS "cash_boxes" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"name" TEXT NOT NULL UNIQUE, '
        '"currency_id" INTEGER NOT NULL, '
        '"account_id" INTEGER NOT NULL, '""",
            """    'CREATE TABLE IF NOT EXISTS "cash_boxes" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"name" TEXT NOT NULL UNIQUE, '
        '"currency_id" INTEGER NOT NULL, '
        '"account_id" INTEGER NOT NULL, '
        // س236 (د10): النوع الجارٍ وبيتا البنك — النقدي افتراضاً
        // فالقائمة القديمة كلها نقدي بلا مساس.
        '"kind" TEXT NOT NULL DEFAULT \\'cash\\', '
        '"bank_name" TEXT NULL, '
        '"account_number" TEXT NULL, '""",
            "أعمدة النوع بإنشاء الصناديق")

    # ٤) جدول التسويات البنكية بإنشاء جداول السندات (بعد cash_adjustments)
    s = sub(s, """        '"state" TEXT NOT NULL DEFAULT \\'draft\\', '
        '"move_id" INTEGER NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
  ];""",
            """        '"state" TEXT NOT NULL DEFAULT 'draft', '
        '"move_id" INTEGER NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    // س236 (د10 — التسوية البنكية بنمط تسوية الصندوق حرفاً): برصيدي
    // الكشف والدفتري اللقطة والاتجاه والمبلغ محسوبين من الفرق.
""" + BANK_RECON_TABLE + """
  ];""",
            "جدول التسويات بإنشاء الجداول")

    # ٥) createCashBox: معاملات النوع والبنك (اختيارية فالمواضع القائمة
    #    كلها نقدي كما كانت)
    s = sub(s, """  Future<int> createCashBox({
    required String name,
    required int currencyId,
  }) async {""",
            """  Future<int> createCashBox({
    required String name,
    required int currencyId,

    /// س236 (د10 — النوع الجارٍ): 'cash' نقدي افتراضاً و'bank' جارٍ
    /// بنكي (ومعه اسم البنك ورقم الحساب — بيتان بيانيان للصندوق
    /// البنكي لا حقول إلزام فالاسم يكفي، والرقم لاحقاً).
    String kind = 'cash',
    String? bankName,
    String? accountNumber,
  }) async {""",
            "تواقيع createCashBox")
    s = sub(s, """    return transaction(
        () => _createCashBoxWithinTx(name: trimmed, currencyId: currencyId));""",
            """    if (kind != 'cash' && kind != 'bank') {
      throw StateError('نوع صندوق غير معروف: $kind');
    }
    return transaction(() => _createCashBoxWithinTx(
        name: trimmed,
        currencyId: currencyId,
        kind: kind,
        bankName: bankName?.trim(),
        accountNumber: accountNumber?.trim()));""",
            "استدعاء createCashBox")
    s = sub(s, """  Future<int> _createCashBoxWithinTx({
    required String name,
    required int currencyId,
  }) async {""",
            """  Future<int> _createCashBoxWithinTx({
    required String name,
    required int currencyId,
    String kind = 'cash',
    String? bankName,
    String? accountNumber,
  }) async {""",
            "تواقيع الشطر الداخلي")
    s = sub(s, """    await customStatement(
      'INSERT INTO cash_boxes (name, currency_id, account_id, '
      'opening_balance_base_minor, uuid, created_at, updated_at, is_deleted) '
      'VALUES (?, ?, ?, 0, ?, ?, ?, 0)',
      [trimmed, currencyId, accountId, const Uuid().v4(), now, now],
    );""",
            """    await customStatement(
      'INSERT INTO cash_boxes (name, currency_id, account_id, kind, '
      'bank_name, account_number, opening_balance_base_minor, uuid, '
      'created_at, updated_at, is_deleted) '
      "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 0)",
      [
        trimmed,
        currencyId,
        accountId,
        kind,
        kind == 'bank' ? (bankName == null || bankName.isEmpty ? null : bankName) : null,
        kind == 'bank' ? (accountNumber == null || accountNumber.isEmpty ? null : accountNumber) : null,
        const Uuid().v4(),
        now,
        now,
      ],
    );""",
            "إدراج الصندوق بالنوع")

    # ٦) تقرير الصناديق: النوع واسم البنك
    s = sub(s, """    'SELECT b.id AS box_id, b.name AS name, c.code AS currency_code, '
    'a.code AS account_code, a.is_active AS account_active '
    'FROM cash_boxes b '""",
            """    'SELECT b.id AS box_id, b.name AS name, b.kind AS kind, '
    'b.bank_name AS bank_name, b.account_number AS account_number, '
    'c.code AS currency_code, '
    'a.code AS account_code, a.is_active AS account_active '
    'FROM cash_boxes b '""",
            "استعلام تقرير الصناديق")
    s = sub(s, """    report.add(CashBoxReportRow(
      boxId: r.data['box_id'] as int,
      name: r.data['name'] as String,
      currencyCode: r.data['currency_code'] as String,""",
            """    report.add(CashBoxReportRow(
      boxId: r.data['box_id'] as int,
      name: r.data['name'] as String,
      // س236: النوع واسم البنك للصناديق الجارية البنكية.
      kind: (r.data['kind'] as String?) ?? 'cash',
      bankName: r.data['bank_name'] as String?,
      currencyCode: r.data['currency_code'] as String,""",
            "صف تقرير الصناديق")

    # ٧) محرك التسوية البنكية — يُدرج قبل cashBoxesReport
    s = sub(s, """Future<List<CashBoxReportRow>> cashBoxesReport() async {""",
            ENGINE + """
Future<List<CashBoxReportRow>> cashBoxesReport() async {""",
            "موضع المحرك")

    # ٨) صف قائمة التسويات البنكية بعد صف قائمة تسويات الصندوق
    anchor = "class CashAdjustmentListRow {"
    assert anchor in s
    idx = s.index(anchor)
    # أدرج الصف الجديد قبل الصنف القائم مباشرة
    s = s[:idx] + LIST_ROW + "\n" + s[idx:]

    io.open(DB, "w", encoding="utf-8").write(s)
    print("التخزين: الترحيلة v38 والمحرك والصفوف — رُقع كلها")


ENGINE = """
  // ═══ س236 (د10 البنوك D-224): مستند التسوية البنكية بنمط تسوية
  // الصندوق (س-17) حرفاً — للصناديق الجارية البنكية حصراً، ورصيد كشف
  // البنك المدخل يقارن بالدفتري فالفرق يقيد على 57 (س8). ═══

  /// إنشاء جدول التسويات البنكية (عند الإنشاء والترقية معاً — آمن
  /// التكرار بIF NOT EXISTS).
  Future<void> _createBankReconciliationTableTx() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS "bank_reconciliations" ('
      '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
      "'number' TEXT NOT NULL DEFAULT '', "
      '"cash_box_id" INTEGER NOT NULL, '
      '"reconciliation_date" TEXT NOT NULL, '
      '"currency_id" INTEGER NOT NULL DEFAULT 1, '
      '"fx_rate" INTEGER NOT NULL, '
      '"statement_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
      '"book_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
      '"direction" TEXT NOT NULL, '
      '"amount_doc_minor" INTEGER NOT NULL DEFAULT 0, '
      '"amount_base_minor" INTEGER NOT NULL DEFAULT 0, '
      "'reason' TEXT NOT NULL DEFAULT '', "
      "'state' TEXT NOT NULL DEFAULT 'draft', "
      '"move_id" INTEGER NULL, '
      '"uuid" TEXT NOT NULL, '
      '"created_at" INTEGER NOT NULL DEFAULT 0, '
      '"updated_at" INTEGER NOT NULL DEFAULT 0, '
      '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    );
  }

  /// س236: فحوص التسوية البنكية المحركية — الصندوق موجود **وجارٍ
  /// بنكي** (نوعه من v38) وحسابه نشط وعملته عملة التسوية.
  Future<List<BankReconciliationValidationError>> _collectBankReconErrors(
    BankReconciliationDraft draft, {
    required bool forPosting,
  }) async {
    final errors = validateBankReconciliationStructure(draft);
    if (errors.isNotEmpty) return errors;
    if (forPosting) {
      final period = findPeriodForDate(await ledgerPeriods(), draft.dateText);
      if (period == null) {
        return [BankReconNoPeriod(draft.dateText)];
      }
      if (period.isClosed) {
        return [BankReconClosedPeriod(draft.dateText)];
      }
    }
    final box = await _cashBoxByIdTx(draft.cashBoxId);
    if (box == null) {
      return [const BankReconBoxMissing()];
    }
    final row = (await customSelect(
            "SELECT kind, name FROM cash_boxes WHERE id = ? AND is_deleted = 0",
            variables: [Variable.withInt(draft.cashBoxId)])
        .get());
    if (row.isEmpty) {
      return [const BankReconBoxMissing()];
    }
    final kind = (row.first.data['kind'] as String?) ?? 'cash';
    if (kind != 'bank') {
      return [BankReconBoxNotBank(row.first.data['name'] as String)];
    }
    final account = await _accountByIdTx(box.accountId);
    if (account == null || !account.isActive) {
      return [BankReconBoxInactive(box.name)];
    }
    final boxCurrencyId = (await customSelect(
            'SELECT currency_id FROM cash_boxes WHERE id = ?',
            variables: [Variable.withInt(draft.cashBoxId)])
        .getSingle())
        .data['currency_id'] as int;
    if (boxCurrencyId != draft.currencyId) {
      return [const BankReconBoxCurrencyMismatch()];
    }
    return const [];
  }

  /// س236: إنشاء مسودة تسوية بنكية — الرصيد الدفتري يُلتقط لحظتها
  /// (لقطة المسودة F-122/D-082) والفرق محسوب لا مُدخل.
  Future<int> createBankReconciliationDraft(
      BankReconciliationDraft draft) async {
    return transaction(() async {
      final bookBalance =
          await _cashBoxBalanceDocTx(draft.cashBoxId, draft.fxRate);
      final effective = BankReconciliationDraft(
        dateText: draft.dateText,
        cashBoxId: draft.cashBoxId,
        currencyId: draft.currencyId,
        fxRate: draft.fxRate,
        statementBalanceDocMinor: draft.statementBalanceDocMinor,
        bookBalanceDocMinor: bookBalance,
        reason: draft.reason,
      );
      final errors = await _collectBankReconErrors(effective, forPosting: false);
      if (errors.isNotEmpty) {
        throw BankReconciliationValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT INTO bank_reconciliations (number, cash_box_id, "
        "reconciliation_date, currency_id, fx_rate, "
        "statement_balance_doc_minor, book_balance_doc_minor, direction, "
        "amount_doc_minor, amount_base_minor, reason, state, move_id, "
        "uuid, created_at, updated_at, is_deleted) "
        "VALUES ('', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft', NULL, ?, ?, ?, 0)",
        [
          effective.cashBoxId,
          effective.dateText,
          effective.currencyId,
          effective.fxRate,
          effective.statementBalanceDocMinor,
          effective.bookBalanceDocMinor,
          effective.direction.storageValue,
          effective.amountDocMinor,
          convertToBaseMinor(effective.amountDocMinor, effective.fxRate),
          effective.reason.trim(),
          const Uuid().v4(),
          now,
          now,
        ],
      );
      final id =
          (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
              .data['id'] as int;
      await _recordDocEventTx(
        entityType: 'bank_reconciliation',
        table: 'bank_reconciliations',
        entityId: id,
        action: 'created',
      );
      return id;
    });
  }

  /// س236: ترحيل التسوية البنكية بنمط ترحيل تسوية الصندوق حرفاً —
  /// العجز: 57 مدين / الصندوق دائن والزيادة: الصندوق مدين / 57 دائن
  /// (س8)، وحركة الصندوق بمصدرها والرقم من تسلسل bank_reconciliation.
  Future<int> postBankReconciliation(int bankReconId) async {
    return transaction(() async {
      final a = await _bankReconRowTx(bankReconId);
      if (a == null) {
        throw StateError('لا تسوية بنكية بالمعرف $bankReconId');
      }
      if (a['state'] != 'draft') {
        throw BankReconciliationValidationException(
            [BankReconStateNotDraft(a['state'] as String)]);
      }
      final draft = BankReconciliationDraft(
        dateText: a['reconciliation_date'] as String,
        cashBoxId: a['cash_box_id'] as int,
        currencyId: a['currency_id'] as int,
        fxRate: a['fx_rate'] as int,
        statementBalanceDocMinor: a['statement_balance_doc_minor'] as int,
        bookBalanceDocMinor: a['book_balance_doc_minor'] as int,
        reason: a['reason'] as String? ?? '',
      );
      final errors = await _collectBankReconErrors(draft, forPosting: true);
      if (errors.isNotEmpty) {
        throw BankReconciliationValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(draft.dateText);
      final number = formatDocumentNumber(
          year, await _advanceSequenceWithinTx('bank_reconciliation', year),
          counterWidth: await _counterWidth());
      final journalId = await _journalIdByCodeTx('cash');
      final acc57 = await _accountIdByCodeTx('57');
      final box = (await _cashBoxByIdTx(draft.cashBoxId))!;
      final totalDoc = draft.amountDocMinor;
      final totalBase = convertToBaseMinor(totalDoc, draft.fxRate);
      final isShortage = draft.direction == CashAdjustmentDirection.shortage;

      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: draft.dateText,
        narration:
            'تسوية بنكية — ${draft.direction.label}: ${draft.reason.trim()}',
        refDocType: 'bank_reconciliation',
        refDocId: bankReconId,
        lines: [
          if (isShortage)
            MoveLineDraft(
              accountId: acc57,
              debitMinor: totalBase,
              currencyId: 1,
              amountMinor: totalBase,
            )
          else
            MoveLineDraft(
              accountId: box.accountId,
              debitMinor: totalBase,
              currencyId: draft.currencyId,
              amountMinor: totalDoc,
              fxRate: draft.fxRate,
            ),
          if (isShortage)
            MoveLineDraft(
              accountId: box.accountId,
              creditMinor: totalBase,
              currencyId: draft.currencyId,
              amountMinor: totalDoc,
              fxRate: draft.fxRate,
            )
          else
            MoveLineDraft(
              accountId: acc57,
              creditMinor: totalBase,
              currencyId: 1,
              amountMinor: totalBase,
            ),
        ],
      ));
      await _postMoveWithinTx(moveId, sequenceKind: 'move_cash');

      await customStatement(
        "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
        "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, user_id, "
        "uuid, created_at, updated_at, is_deleted) "
        "VALUES (?, ?, ?, ?, ?, 'bank_reconciliation', ?, NULL, ?, ?, ?, 0)",
        [
          box.id,
          isShortage ? 'out' : 'in',
          totalDoc,
          totalBase,
          draft.fxRate,
          bankReconId,
          const Uuid().v4(),
          now,
          now,
        ],
      );

      await customStatement(
        "UPDATE bank_reconciliations SET state = 'posted', number = ?, "
        'move_id = ?, updated_at = ? WHERE id = ?',
        [number, moveId, now, bankReconId],
      );
      await _recordDocEventTx(
        entityType: 'bank_reconciliation',
        table: 'bank_reconciliations',
        entityId: bankReconId,
        action: 'posted',
      );
      return bankReconId;
    });
  }

  /// س236: صف التسوية البنكية داخل معاملة.
  Future<Map<String, Object?>?> _bankReconRowTx(int id) async {
    final rows = await customSelect(
      'SELECT * FROM bank_reconciliations WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(id)],
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// س236: رصيد الصندوق الدفتري بعملة كشفه — من رصيد الأساس الموحد
  /// (معادلة الصندوق ذاتها: الافتتاحي + الداخل − الخارج) بقسمة لقطة
  /// السعر بدالة التقريب ذاتها (F-122) — فالأساس مصدر الحقيقة الوحيد
  /// وعملة الأساس (fxRate = 10^6) تعيد الرصيد ذاته بالضبط.
  Future<int> _cashBoxBalanceDocTx(int boxId, int fxRate) async {
    final balanceBase = await _cashBoxBalanceTx(boxId);
    return roundHalfAwayFromZeroRatio(balanceBase * fxRateScale, fxRate);
  }

  /// س236: قائمة تسويات صندوق بنكي بترتيب أحدثها أولاً.
  Future<List<BankReconciliationListRow>> bankReconciliationsOf(
      {int? cashBoxId}) async {
    final where = cashBoxId == null
        ? 'WHERE r.is_deleted = 0'
        : 'WHERE r.is_deleted = 0 AND r.cash_box_id = ?';
    final args =
        cashBoxId == null ? const <Object?>[] : [Variable.withInt(cashBoxId)];
    final rows = await customSelect(
      'SELECT r.id AS id, r.number AS number, r.reconciliation_date AS date, '
      'r.direction AS direction, r.statement_balance_doc_minor AS stmt, '
      'r.book_balance_doc_minor AS book, r.amount_doc_minor AS amount, '
      'r.reason AS reason, r.state AS state, b.name AS box_name, '
      'c.code AS currency_code '
      'FROM bank_reconciliations r '
      'JOIN cash_boxes b ON b.id = r.cash_box_id '
      'JOIN currencies c ON c.id = r.currency_id '
      '$where ORDER BY r.id DESC LIMIT 200',
      variables: args,
    ).get();
    return [
      for (final r in rows)
        BankReconciliationListRow(
          id: r.data['id'] as int,
          number: r.data['number'] as String? ?? '',
          dateText: r.data['date'] as String,
          boxName: r.data['box_name'] as String,
          direction: CashAdjustmentDirection.fromStorage(
              r.data['direction'] as String),
          statementBalanceDocMinor: r.data['stmt'] as int,
          bookBalanceDocMinor: r.data['book'] as int,
          amountDocMinor: r.data['amount'] as int,
          reason: r.data['reason'] as String? ?? '',
          state: r.data['state'] as String,
          currencyCode: r.data['currency_code'] as String,
        ),
    ];
  }

"""

LIST_ROW = """/// س236 (د10): صف قائمة تسوية بنكية — لسان قائمة الصندوق البنكي.
class BankReconciliationListRow {
  final int id;
  final String number;
  final String dateText;
  final String boxName;
  final CashAdjustmentDirection direction;
  final int statementBalanceDocMinor;
  final int bookBalanceDocMinor;
  final int amountDocMinor;
  final String reason;
  final String state;
  final String currencyCode;

  const BankReconciliationListRow({
    required this.id,
    required this.number,
    required this.dateText,
    required this.boxName,
    required this.direction,
    required this.statementBalanceDocMinor,
    required this.bookBalanceDocMinor,
    required this.amountDocMinor,
    required this.reason,
    required this.state,
    required this.currencyCode,
  });

  String get displayLabel =>
      number.isEmpty ? 'تسوية بنكية' : 'تسوية بنكية $number';

  String get stateLabel => state == 'posted' ? 'مرحّلة' : 'مسودة';
}

"""


if __name__ == "__main__":
    main()
