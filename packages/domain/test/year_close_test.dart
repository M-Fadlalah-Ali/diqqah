import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات الإقفال السنوي — الدفعة 32 (تاسعة م2) على نص س-21/F-077
/// حرفاً بأرقام الدورة المعروفة نفسها (500,000 ضخ ف100,000 شراء نقدي
/// ف90,000 بيع آجل ف50,000 قبض فعجز 5,000 — النتيجة ربح 25,000).
///
/// المجال النقي حصراً: الخطة من الأرصدة الخام ولا قاعدة ولا واجهة.
int _id = 0;

YearCloseAccountBalance bal(
  String code,
  AccountType type,
  NormalSide side, {
  int debit = 0,
  int credit = 0,
  bool isLeaf = true,
}) =>
    YearCloseAccountBalance(
      accountId: ++_id,
      code: code,
      name: 'حساب $code',
      type: type,
      normalSide: side,
      isLeaf: isLeaf,
      debitMinor: debit,
      creditMinor: credit,
    );

/// دورة الدورة المعروفة كاملة الأرصدة بعد انتهاء السنة.
(List<YearCloseAccountBalance>, int, int) knownCycle() {
  final box = bal('1111', AccountType.asset, NormalSide.debit, debit: 545000);
  final receivables =
      bal('112', AccountType.asset, NormalSide.debit, debit: 40000);
  final stock = bal('113', AccountType.asset, NormalSide.debit, debit: 40000);
  final creditors =
      bal('211', AccountType.liability, NormalSide.credit, credit: 100000);
  final capital =
      bal('311', AccountType.equity, NormalSide.credit, credit: 500000);
  final retained =
      bal('331', AccountType.equity, NormalSide.credit);
  final result = bal('332', AccountType.equity, NormalSide.credit);
  final revenue =
      bal('411', AccountType.income, NormalSide.credit, credit: 90000);
  final cogs = bal('51', AccountType.expense, NormalSide.debit, debit: 60000);
  final shortage =
      bal('56', AccountType.expense, NormalSide.debit, debit: 5000);
  final parent =
      bal('4', AccountType.income, NormalSide.credit, isLeaf: false);
  return (
    [box, receivables, stock, creditors, capital, retained, result, revenue,
        cogs, shortage, parent],
    result.accountId,
    retained.accountId,
  );
}

void main() {
  test('س-21 ربح: تصفير الإيرادات مديناً والمصروفات دائناً والصافي '
      '25,000 إلى 331 دائناً — والافتتاحية متوازنة', () {
    final (balances, resultId, retainedId) = knownCycle();
    final plan = buildYearClosePlan(
      balances: balances,
      resultAccountId: resultId,
      retainedAccountId: retainedId,
    );

    // الإيراد 411 برصيده الدائن 90,000 يُدين — والمصروفان يُدائنان.
    expect(plan.incomeLines, hasLength(1));
    expect(plan.incomeLines.single.debitMinor, 90000);
    expect(plan.expenseLines, hasLength(2));
    expect([for (final l in plan.expenseLines) l.creditMinor].fold(0, (a, b) => a + b),
        65000);
    expect(plan.incomeTotalMinor, 90000);
    expect(plan.expenseTotalMinor, 65000);
    expect(plan.netResultMinor, 25000,
        reason: '90,000 إيراد − 60,000 تكلفة − 5,000 عجز');

    // الافتتاحية: الصندوق 545,000 والذمم 40,000 والمخزون 40,000 مدينة
    // والموردون 100,000 ورأس المال 500,000 و331 دائنة بربح السنة.
    expect(plan.openingLines, hasLength(6));
    int debitOf(String code) => plan.openingLines
        .where((l) => balances.any((b) => b.code == code && b.accountId == l.accountId))
        .fold(0, (a, l) => a + l.debitMinor);
    int creditOf(String code) => plan.openingLines
        .where((l) => balances.any((b) => b.code == code && b.accountId == l.accountId))
        .fold(0, (a, l) => a + l.creditMinor);
    expect(debitOf('1111'), 545000);
    expect(debitOf('112'), 40000);
    expect(debitOf('113'), 40000);
    expect(creditOf('211'), 100000);
    expect(creditOf('311'), 500000);
    expect(creditOf('331'), 25000,
        reason: '331 القديمة صفر + ربح السنة 25,000 (س-21: تتراكم في 331)');
    expect(plan.openingBalanced, isTrue);
    // و332 لا سطر لها بالافتتاحية — صفر بعد الصافي.
    expect(
        plan.openingLines.any((l) =>
            balances.any((b) => b.accountId == l.accountId && b.code == '332')),
        isFalse);
  });

  test('س-21 خسارة: الصافي سالب فينتقل 331 مديناً بالعكس (س-21 نصاً)', () {
    _id = 0;
    final revenue =
        bal('411', AccountType.income, NormalSide.credit, credit: 30000);
    final cogs = bal('51', AccountType.expense, NormalSide.debit, debit: 40000);
    final retained = bal('331', AccountType.equity, NormalSide.credit);
    final result = bal('332', AccountType.equity, NormalSide.credit);
    final plan = buildYearClosePlan(
      balances: [revenue, cogs, retained, result],
      resultAccountId: result.accountId,
      retainedAccountId: retained.accountId,
    );
    expect(plan.incomeTotalMinor, 30000);
    expect(plan.expenseTotalMinor, 40000);
    expect(plan.netResultMinor, -10000);
    // 331 بالافتتاحية مدين 10,000 — العجز المحمول (رصيد معدل سالب).
    final retainedLine = plan.openingLines
        .singleWhere((l) => l.accountId == retained.accountId);
    expect(retainedLine.debitMinor, 10000);
    expect(retainedLine.creditMinor, 0);
    // التوازن هنا لا يتحقق بالعمد: هذه الأرصدة مصغّرة بلا أصولٍ تعادلها
    // — والاختبار الكامل للتوازن بحالة الدورة المعروفة أعلاه (F-068).
    expect(plan.openingBalanced, isFalse);
  });

  test('س-21 صفر نتيجة: لا قيد صافٍ ولا سطر لـ331 الصفرية', () {
    _id = 0;
    final revenue =
        bal('411', AccountType.income, NormalSide.credit, credit: 50000);
    final cogs = bal('51', AccountType.expense, NormalSide.debit, debit: 50000);
    final retained = bal('331', AccountType.equity, NormalSide.credit);
    final result = bal('332', AccountType.equity, NormalSide.credit);
    final plan = buildYearClosePlan(
      balances: [revenue, cogs, retained, result],
      resultAccountId: result.accountId,
      retainedAccountId: retained.accountId,
    );
    expect(plan.netResultMinor, 0);
    expect(plan.incomeLines, hasLength(1));
    expect(plan.expenseLines, hasLength(1));
    expect(plan.openingLines, isEmpty,
        reason: 'لا أرصدة ميزانية ولا نتيجة — لا افتتاحية أصلاً');
  });

  test('العكسية 42 ضمن الإيرادات تُدائن برصيدها المدين و332 يدين بمقدارها '
      '(الاشتمال لا تكرار العينة — نص س-21)', () {
    _id = 0;
    final revenue =
        bal('411', AccountType.income, NormalSide.credit, credit: 100000);
    final returns =
        bal('42', AccountType.income, NormalSide.debit, debit: 8000);
    final retained = bal('331', AccountType.equity, NormalSide.credit);
    final result = bal('332', AccountType.equity, NormalSide.credit);
    final plan = buildYearClosePlan(
      balances: [revenue, returns, retained, result],
      resultAccountId: result.accountId,
      retainedAccountId: retained.accountId,
    );
    expect(plan.incomeLines, hasLength(2));
    final revenueLine =
        plan.incomeLines.singleWhere((l) => l.accountId == revenue.accountId);
    final returnsLine =
        plan.incomeLines.singleWhere((l) => l.accountId == returns.accountId);
    expect(revenueLine.debitMinor, 100000);
    expect(returnsLine.creditMinor, 8000,
        reason: '42 عينتها مدين ورصيدها مدين فتصفَّر دائناً');
    expect(plan.incomeTotalMinor, 92000);
    expect(plan.netResultMinor, 92000);
  });

  test('العكسية 53 ضمن المصروفات تُدين برصيدها الدائن — والمصروف العادي '
      'يُدائن', () {
    _id = 0;
    final cogs = bal('51', AccountType.expense, NormalSide.debit, debit: 60000);
    final purchaseReturns =
        bal('53', AccountType.expense, NormalSide.credit, credit: 4000);
    final retained = bal('331', AccountType.equity, NormalSide.credit);
    final result = bal('332', AccountType.equity, NormalSide.credit);
    final plan = buildYearClosePlan(
      balances: [cogs, purchaseReturns, retained, result],
      resultAccountId: result.accountId,
      retainedAccountId: retained.accountId,
    );
    expect(plan.expenseLines, hasLength(2));
    final cogsLine =
        plan.expenseLines.singleWhere((l) => l.accountId == cogs.accountId);
    final returnsLine = plan.expenseLines
        .singleWhere((l) => l.accountId == purchaseReturns.accountId);
    expect(cogsLine.creditMinor, 60000);
    expect(returnsLine.debitMinor, 4000);
    expect(plan.expenseTotalMinor, 56000);
    expect(plan.netResultMinor, -56000);
  });

  test('الحساب الأب (غير الورقي) بلا سطر — والحساب الصفري بلا سطر', () {
    _id = 0;
    final parent =
        bal('41', AccountType.income, NormalSide.credit, isLeaf: false,
            credit: 90000);
    final zeroRevenue =
        bal('412', AccountType.income, NormalSide.credit);
    final retained = bal('331', AccountType.equity, NormalSide.credit);
    final result = bal('332', AccountType.equity, NormalSide.credit);
    final plan = buildYearClosePlan(
      balances: [parent, zeroRevenue, retained, result],
      resultAccountId: result.accountId,
      retainedAccountId: retained.accountId,
    );
    expect(plan.incomeLines, isEmpty,
        reason: 'الأب مجمع أبنائه ولا يقيد (03 §1-2) والورقي الصفري بلا أثر');
    expect(plan.netResultMinor, 0);
  });
}
