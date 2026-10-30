import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// أدوات بناء حسابات اختبار — بالمُنشئ النقي ذاته الذي تمرر به القراءات.
AccountInfo account({
  required int id,
  required String code,
  required String name,
  required AccountType type,
  NormalSide? normalSide,
  bool isLeaf = true,
  bool isActive = true,
}) =>
    AccountInfo(
      id: id,
      code: code,
      name: name,
      type: type,
      normalSide:
          normalSide ?? type.defaultNormalSide,
      parentId: null,
      isLeaf: isLeaf,
      isActive: isActive,
    );

TrialBalanceRawLine line(int accountId, int debit, int credit) =>
    TrialBalanceRawLine(
        accountId: accountId, debitMinor: debit, creditMinor: credit);

void main() {
  group('ميزان المراجعة النقي (س-71) — buildTrialBalance', () {
    final cash = account(
        id: 1, code: '1111', name: 'الصندوق الرئيسي', type: AccountType.asset);
    final receivable = account(
        id: 2, code: '112', name: 'العملاء', type: AccountType.asset);
    final payable = account(
        id: 3, code: '211', name: 'الموردون', type: AccountType.liability);
    final goodsRevenue = account(
        id: 4, code: '411', name: 'إيراد البضاعة', type: AccountType.income);
    final cogs = account(
        id: 5, code: '51', name: 'تكلفة المبيعات', type: AccountType.expense);
    final accounts = [cash, receivable, payable, goodsRevenue, cogs];

    test('التجميع بالاتجاه الطبيعي والمجاميع متوازنة والفرز بالكود', () {
      final report = buildTrialBalance([
        line(1, 545000, 5000), // الصندوق: ضخ وقبض داخل وعجز خارج
        line(2, 90000, 50000), // العملاء: بيع آجل وقبض جزئي
        line(3, 0, 100000), // الموردون: دائن
        line(4, 0, 90000), // إيراد البضاعة
        line(5, 60000, 0), // تكلفة المبيعات
      ], accounts);

      expect(report.isBalanced, isTrue,
          reason: 'مرحّل متوازن بالبناء (F-068) فالميزان متوازن');
      expect(report.totalDebitMinor, 755000);
      expect(report.totalCreditMinor, 755000);

      final byCode = {for (final r in report.rows) r.account.code: r};
      expect(byCode['1111']!.balanceMinor, 540000,
          reason: 'الأصل المدين طبيعته: مدين − دائن');
      expect(byCode['112']!.balanceMinor, 40000);
      expect(byCode['211']!.balanceMinor, 100000,
          reason: 'الخصم الدائن طبيعته: دائن − مدين');
      expect(byCode['411']!.balanceMinor, 90000);
      expect(byCode['51']!.balanceMinor, 60000);
      expect(
          report.rows.map((r) => r.account.code).toList(),
          ['1111', '112', '211', '411', '51'],
          reason: 'الفرز المعجمي للكود — نمط الفهرس');
    });

    test('حساب بلا حركة لا يُعرض وحساب غائب عن الدليل يُتجاهل صامتاً', () {
      final report = buildTrialBalance([
        line(1, 100, 0),
        line(1, 0, 0), // سطر أصفار لا يوقظ الحساب
        line(99, 50, 0), // حساب ليس بالدليل
      ], accounts);
      expect(report.rows, hasLength(1));
      expect(report.rows.first.account.code, '1111');
      expect(report.totalDebitMinor, 100);
    });

    test('رصيد عكسي يظهر سالباً لا يُقلب خفية', () {
      final report = buildTrialBalance([line(1, 100, 500)], accounts);
      expect(report.rows.first.balanceMinor, -400);
    });
  });

  group('الذمم النقية (س-73) — buildReceivablesPayables', () {
    test('الاتجاهان: مدين لنا ودائن لهم والصفر يخرج', () {
      final rows = buildReceivablesPayables([
        PartyControlRaw(
            partyId: 1, partyName: 'عميل أ', netDebitMinor: 40000),
        PartyControlRaw(
            partyId: 2, partyName: 'مورد ب', netDebitMinor: -100000),
        PartyControlRaw(partyId: 3, partyName: 'متزن', netDebitMinor: 0),
      ]);
      expect(rows, hasLength(2), reason: 'الصفر لا ذمة فلا صف');
      expect(rows[0].direction, PartyBalanceDirection.theyOweUs);
      expect(rows[0].amountMinor, 40000);
      expect(rows[1].direction, PartyBalanceDirection.weOweThem,
          reason: 'السالب على حساب السيطرة: نحن المدينون (05 §5)');
      expect(rows[1].amountMinor, 100000);
    });
  });

  group('المخزون النقي (س-74) — buildInventoryReport', () {
    test('المتوسط بالرسة المعتمدة وعلى صفر كميّة لا متوسط', () {
      final rows = buildInventoryReport([
        InventoryRawRow(
            itemId: 1,
            sku: 'OIL',
            name: 'زيت',
            warehouseName: 'المستودع الرئيسي',
            qtyBase: 3,
            totalValueMinor: 100000),
        InventoryRawRow(
            itemId: 2,
            sku: 'Z',
            name: 'صنف راكد',
            warehouseName: null,
            qtyBase: 0,
            totalValueMinor: 0),
      ]);
      expect(rows[0].avgCostBaseMinor, 33333,
          reason: '100000/3 بالنصف بعيداً عن الصفر');
      expect(rows[1].avgCostBaseMinor, isNull);
    });
  });

  group('مبيعات وحركة الأصناف النقية (س-75)', () {
    test('الصافي مشتق بيعاً − مردوداً كمّةً وقيمة', () {
      final rows = buildSalesMovementReport([
        SalesMovementRawRow(
            itemId: 1,
            sku: 'OIL',
            name: 'زيت',
            qtySoldBase: 6,
            salesValueBaseMinor: 90000,
            qtyReturnedBase: 2,
            returnsValueBaseMinor: 30000),
      ]);
      expect(rows.single.netQtyBase, 4);
      expect(rows.single.netValueBaseMinor, 60000);
    });
  });

  group('مدقق مدى التقرير', () {
    test('ISO الفاسد والمدى المقلوب يُرفضان والصحيح يمرّ', () {
      expect(validateReportRange('2026-13-01', '2026-12-31'),
          everyElement(isA<ReportRangeInvalidDate>()),
          reason: 'الشهر 13 فاسد (D-077)');
      final reversed = validateReportRange('2026-05-10', '2026-05-01');
      expect(reversed.single, isA<ReportRangeOrderInvalid>());
      expect(describeReportValidationError(reversed.single), contains('مقلوب'));
      expect(validateReportRange('2026-05-01', '2026-05-31'), isEmpty);
      expect(
          describeReportValidationError(
              const ReportRangeInvalidDate('x')),
          contains('YYYY-MM-DD'));
    });
  });

  group('مدققو الإقفال والفك (س-20) — validatePeriodClose/Open', () {
    test('الإقفال: مقفلة سابقاً ومسودات بلا تأكيد يُرفضان', () {
      final errors = validatePeriodClose(
          periodId: 7,
          startDateText: '2026-03-01',
          endDateText: '2026-03-31',
          isOpen: false,
          openDraftsCount: 2,
          draftsConfirmed: false);
      expect(errors, hasLength(2));
      expect(errors[0], isA<PeriodAlreadyClosed>());
      expect(errors[1], isA<PeriodHasOpenDrafts>());
      final described = errors.map(describePeriodClosingValidationError).join('؛ ');
      expect(described, contains('لا تُقفل مرتين'));
      expect(described, contains('مسودة'));
    });

    test('الإقفال: مفتوحة ومسودات مؤكدة الترك تمرّ', () {
      expect(
          validatePeriodClose(
              periodId: 7,
              startDateText: '2026-03-01',
              endDateText: '2026-03-31',
              isOpen: true,
              openDraftsCount: 1,
              draftsConfirmed: true),
          isEmpty);
    });

    test('الفك: المفتوحة والسبب الفارغ يُرفضان والسبب يصفُّهما', () {
      final errors = validatePeriodOpen(periodId: 7, isClosed: false, reason: '  ');
      expect(errors, hasLength(2));
      expect(errors[0], isA<PeriodNotClosed>());
      expect(errors[1], isA<PeriodOpenReasonMandatory>());
      expect(describePeriodClosingValidationError(errors[1]),
          contains('بسبب نصي إلزامي'));
      expect(
          validatePeriodOpen(
              periodId: 7, isClosed: true, reason: 'تصحيح خطأ بإذن المالك'),
          isEmpty);
    });
  });
}
