// اختبارات س236 — د10 البنوك (D-224): النوع الجارٍ للصناديق (الترحيلة
// v38: kind/bank_name/account_number) ومستند التسوية البنكية بنمط تسوية
// الصندوق (رصيد كشف البنك يقارن بالدفتري فالفرق على 57) وشاشتها.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/bank_recon_screen.dart';
import 'package:diqqah_app/boxes_screen.dart';

import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();

  group('س236/النطاق: مسودة التسوية البنكية النقية', () {
    test('الاتجاه والمبلغ محسوبان من الفرق لا مُدخلان', () {
      final surplus = BankReconciliationDraft(
        dateText: '2026-11-28',
        cashBoxId: 1,
        statementBalanceDocMinor: 12000,
        bookBalanceDocMinor: 10000,
        reason: 'رسوم بنكية',
      );
      expect(surplus.direction, CashAdjustmentDirection.overage);
      expect(surplus.amountDocMinor, 2000);

      final shortage = BankReconciliationDraft(
        dateText: '2026-11-28',
        cashBoxId: 1,
        statementBalanceDocMinor: 9000,
        bookBalanceDocMinor: 10000,
        reason: 'عمولة',
      );
      expect(shortage.direction, CashAdjustmentDirection.shortage);
      expect(shortage.amountDocMinor, 1000);
    });

    test('المدقق البنيوي: الفرق صفر لا تسوية والسبب إلزامي والسالب مرفوض',
        () {
      final noDiff = validateBankReconciliationStructure(
          BankReconciliationDraft(
        dateText: '2026-11-28',
        cashBoxId: 1,
        statementBalanceDocMinor: 10000,
        bookBalanceDocMinor: 10000,
        reason: 'سبب',
      ));
      expect(noDiff.single, isA<BankReconNoDifference>());

      final noReason = validateBankReconciliationStructure(
          BankReconciliationDraft(
        dateText: '2026-11-28',
        cashBoxId: 1,
        statementBalanceDocMinor: 9000,
        bookBalanceDocMinor: 10000,
        reason: '  ',
      ));
      expect(noReason.single, isA<BankReconReasonRequired>());

      final negative = validateBankReconciliationStructure(
          BankReconciliationDraft(
        dateText: '2026-11-28',
        cashBoxId: 1,
        statementBalanceDocMinor: -5,
        bookBalanceDocMinor: 10000,
        reason: 'سبب',
      ));
      expect(negative.single, isA<BankReconStatementBalanceInvalid>());

      final good = validateBankReconciliationStructure(
          BankReconciliationDraft(
        dateText: '2026-11-28',
        cashBoxId: 1,
        statementBalanceDocMinor: 9000,
        bookBalanceDocMinor: 10000,
        reason: 'سبب',
      ));
      expect(good, isEmpty);
    });
  });

  group('س236/التخزين: الترحيلة v38 ومحرك التسوية البنكية', () {
    test('المخطط 38: أعمدة النوع والبنك وجدول التسويات البنكية موجودة',
        () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final cols = (await db.customSelect(
              "SELECT name FROM pragma_table_info('cash_boxes')")
          .get())
          .map((r) => r.data['name'] as String)
          .toSet();
      expect(cols.containsAll(['kind', 'bank_name', 'account_number']), isTrue,
          reason: 'أعمدة الترحيلة v38 كلها حاضرة');
      final tables = (await db.customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'bank_reconciliations'")
          .get());
      expect(tables, isNotEmpty, reason: 'جدول التسويات البنكية موجود');
      final ver = (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .first as int;
      expect(ver, 38, reason: 'رقم المخطط 38');
    });

    test('إنشاء صندوق جارٍ بنكي ببيته — والنقدي افتراضاً', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createCashBox(
          name: 'بنك الاتحاد',
          currencyId: 1,
          kind: 'bank',
          bankName: 'الاتحاد',
          accountNumber: '001-234');
      await db.createCashBox(name: 'درج المحل', currencyId: 1);
      final rows = await db.cashBoxesReport();
      final bank = rows.firstWhere((r) => r.name == 'بنك الاتحاد');
      expect(bank.isBank, isTrue);
      expect(bank.bankName, 'الاتحاد');
      expect(bank.accountNumber, '001-234');
      final cash = rows.firstWhere((r) => r.name == 'درج المحل');
      expect(cash.isBank, isFalse, reason: 'النقدي الافتراض كما كان');
      expect(cash.bankName, isNull);
    });

    test('التسوية البنكية كاملة: العجز يقيد على 57 والرصيد يصير رصيد الكشف',
        () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final boxId = await db.createCashBox(
          name: 'بنك الاتحاد',
          currencyId: 1,
          kind: 'bank',
          bankName: 'الاتحاد');

      // دخل الصندوق البنكي: قبض 50,000 على رأس المال (311).
      final capitalId = (await db.customSelect(
        "SELECT id FROM accounts WHERE code = '311'",
      ).getSingle()).data['id'] as int;
      final voucher = await db.createVoucherDraft(VoucherDraft(
        kind: VoucherKind.receipt,
        dateText: '2026-11-20',
        directAccountId: capitalId,
        cashBoxId: boxId,
        amountDocMinor: 50000,
      ));
      await db.postVoucher(voucher);
      final book = await db.bankBoxBookBalanceDocMinor(boxId);
      expect(book, 50000, reason: 'الرصيد الدفتري بعملة الكشف (الأساس)');

      // كشف البنك: 45,000 — الفرق عجز 5,000 يقيد على 57 (بنمط الصندوق).
      final id = await db.createBankReconciliationDraft(
          BankReconciliationDraft(
        dateText: '2026-11-28',
        cashBoxId: boxId,
        statementBalanceDocMinor: 45000,
        bookBalanceDocMinor: 50000,
        reason: 'رسوم حوالات',
      ));
      await db.postBankReconciliation(id);

      final rows = await db.bankReconciliationsOf(cashBoxId: boxId);
      expect(rows, hasLength(1));
      final row = rows.first;
      expect(row.state, 'posted');
      expect(row.direction, CashAdjustmentDirection.shortage);
      expect(row.amountDocMinor, 5000);
      expect(row.number, isNotEmpty, reason: 'رقم تسلسل bank_reconciliation');
      expect(row.statementBalanceDocMinor, 45000);

      // بنمط تسوية الصندوق: القيد يوازن الصندوق على رصيد الكشف.
      final after = await db.bankBoxBookBalanceDocMinor(boxId);
      expect(after, 45000,
          reason: 'العجز 5,000 خرج من الصندوق (57) فرصيده صار كالكشف');

      // القيد: 57 مدين / الصندوق دائن (بنمط س-17 حرفاً).
      final move = (await db.customSelect(
        "SELECT ml.account_id AS acc, ml.debit_minor AS d, ml.credit_minor AS c "
        "FROM move_lines ml JOIN moves m ON m.id = ml.move_id "
        "WHERE m.ref_doc_type = 'bank_reconciliation' AND m.ref_doc_id = $id",
      ).get());
      expect(move, hasLength(2));
      final acc57 = (await db.customSelect(
        "SELECT id FROM accounts WHERE code = '57'",
      ).getSingle()).data['id'] as int;
      final debit57 = move.firstWhere((r) => r.data['acc'] == acc57);
      expect(debit57.data['d'], 5000);
    });

    test('التسوية البنكية للصندوق النقدي مرفوضة — للبنوك حصراً', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final cashBox = await db.createCashBox(name: 'درج المحل', currencyId: 1);
      try {
        await db.createBankReconciliationDraft(BankReconciliationDraft(
          dateText: '2026-11-28',
          cashBoxId: cashBox,
          statementBalanceDocMinor: 9000,
          bookBalanceDocMinor: 10000,
          reason: 'سبب',
        ));
        fail('كان يجب رفض التسوية البنكية على صندوق نقدي');
      } on BankReconciliationValidationException catch (e) {
        expect(e.errors.single, isA<BankReconBoxNotBank>());
      }
    });
  });

  group('س236/الواجهة: النموذج والقائمة وشاشة التسوية', () {
    testWidgets('نموذج الصندوق: «جارٍ بنكي» يظهر حقلي البنك وينشئ بنكاً',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createCashBox(name: 'درج المحل', currencyId: 1);

      await tester.pumpWidget(MaterialApp(home: BoxesScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('صندوق جديد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('اسم البنك'), findsNothing,
          reason: 'النقدي افتراضاً فحقلا البنك خافيان');

      await tester.enterText(find.widgetWithText(TextField, 'اسم الصندوق'),
          'بنك الاتحاد');
      // القائمة المنسدلة تفتح أولاً ثم يُختار البند (نمط batch21).
      await tester.tap(find.text('النوع — نقدي أو جارٍ بنكي (حساب بنك)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('جارٍ بنكي').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('اسم البنك'), findsOneWidget,
          reason: 'الجاري البنكي يظهر حقلَي بنكه');
      await tester.enterText(find.widgetWithText(TextField, 'اسم البنك'),
          'الاتحاد');

      await tester.tap(find.text('إنشاء الصندوق'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // القائمة: الصندوق البنكي بأيقونته وبنكه وزر تسويته.
      expect(find.text('بنك الاتحاد'), findsOneWidget);
      expect(find.textContaining('بنك الاتحاد · حساب'), findsOneWidget,
          reason: 'بيان البنك بالعنوان الفرعي (اسم البنك بادئة الصف)');
      expect(find.byIcon(Icons.account_balance_outlined), findsOneWidget);
      expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget,
          reason: 'زر التسوية البنكية للصندوق البنكي حصراً');
    });

    testWidgets('شاشة التسوية البنكية: الفرق المحسوب والترحيل بقائمة سابقاتها',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final boxId = await db.createCashBox(
          name: 'بنك الاتحاد',
          currencyId: 1,
          kind: 'bank',
          bankName: 'الاتحاد');

      // الدفتري: قبض 60,000 — والكشف: 57,000 — عجز 3,000 على 57.
      final capitalId = (await db.customSelect(
        "SELECT id FROM accounts WHERE code = '311'",
      ).getSingle()).data['id'] as int;
      final v = await db.createVoucherDraft(VoucherDraft(
        kind: VoucherKind.receipt,
        dateText: '2026-11-20',
        directAccountId: capitalId,
        cashBoxId: boxId,
        amountDocMinor: 60000,
      ));
      await db.postVoucher(v);

      final boxes = await db.cashBoxesReport();
      final bank = boxes.firstWhere((b) => b.boxId == boxId);
      await tester.pumpWidget(
          MaterialApp(home: BankReconScreen(db: db, box: bank)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('الرصيد الدفتري'), findsOneWidget);
      expect(find.textContaining('60,000'), findsOneWidget,
          reason: 'الدفتري معلن بشاشته');

      await tester.enterText(
          find.widgetWithText(TextField, 'رصيد كشف البنك (بوحدة صغرى)'),
          '57000');
      await tester.pump();
      // الفرق المحسوب لحظياً: عجز 3,000 — بلون مساره.
      expect(find.textContaining('عجز: 3,000'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'سبب الفرق (إلزامي)'),
          'رسوم حوالات');
      await tester.tap(find.text('حفظ وترحيل التسوية'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final rows = await db.bankReconciliationsOf(cashBoxId: boxId);
      expect(rows, hasLength(1));
      expect(rows.first.state, 'posted');
      expect(rows.first.amountDocMinor, 3000);
      final after = await db.bankBoxBookBalanceDocMinor(boxId);
      expect(after, 57000, reason: 'الصندوق وازن كشفه');
    });
  });
}
