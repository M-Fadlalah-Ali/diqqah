import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات القوائم المالية الأساسية — الدفعة 33 (عاشرة م2) على نص
/// F-096 و07 §1.6 حرفاً بأرقام الدورة المعروفة نفسها (500,000 ضخ
/// ف100,000 شراء آجل ف90,000 بيع آجل ف50,000 قبض فعجز 5,000).
int _id = 0;

AccountInfo acc(
  String code,
  AccountType type, {
  NormalSide? side,
  bool isLeaf = true,
}) =>
    AccountInfo(
      id: ++_id,
      code: code,
      name: 'حساب $code',
      type: type,
      normalSide: side ?? type.defaultNormalSide,
      parentId: null,
      isLeaf: isLeaf,
      isActive: true,
    );

LedgerLine line(int accountId, int debit, int credit) => LedgerLine(
      moveId: 1,
      accountId: accountId,
      debitMinor: debit,
      creditMinor: credit,
    );

/// أرصدة الدورة المعروفة بعد انتهاء سنتها المفتوحة.
(List<LedgerLine>, List<AccountInfo>) knownCycle() {
  final box = acc('1111', AccountType.asset);
  final receivables = acc('112', AccountType.asset);
  final stock = acc('113', AccountType.asset);
  final creditors = acc('211', AccountType.liability);
  final capital = acc('311', AccountType.equity);
  final retained = acc('331', AccountType.equity);
  final result = acc('332', AccountType.equity);
  final revenue = acc('411', AccountType.income);
  final cogs = acc('51', AccountType.expense);
  final shortage = acc('56', AccountType.expense);
  final lines = [
    line(box.id, 545000, 0),
    line(receivables.id, 40000, 0),
    line(stock.id, 40000, 0),
    line(creditors.id, 0, 100000),
    line(capital.id, 0, 500000),
    line(revenue.id, 0, 90000),
    line(cogs.id, 60000, 0),
    line(shortage.id, 5000, 0),
  ];
  return (
    lines,
    [box, receivables, stock, creditors, capital, retained, result,
        revenue, cogs, shortage],
  );
}

void main() {
  test('قائمة الدخل بالدورة المعروفة: إيراد 90,000 ومصروفان 65,000 '
      'والصافي ربح 25,000 — والأب بلا صف (07 §1.6 من الأنواع)', () {
    final (lines, accounts) = knownCycle();
    final statement = buildIncomeStatement(lines, accounts);
    expect(statement.revenueRows, hasLength(1));
    expect(statement.revenueRows.single.amountMinor, 90000);
    expect(statement.expenseRows, hasLength(2));
    expect(statement.totalRevenueMinor, 90000);
    expect(statement.totalExpenseMinor, 65000);
    expect(statement.netResultMinor, 25000);
    // الصفوف بترتيب الكود.
    expect(
        [for (final r in statement.expenseRows) r.code], ['51', '56']);
  });

  test('العكسية 42 تظهر سالبة تخفض الإيراد — والعكسية 53 سالبة تخفض '
      'المصروف (نمط 03 §1-4)', () {
    _id = 0;
    final revenue = acc('411', AccountType.income);
    final returns = acc('42', AccountType.income, side: NormalSide.debit);
    final cogs = acc('51', AccountType.expense);
    final purchaseReturns =
        acc('53', AccountType.expense, side: NormalSide.credit);
    final statement = buildIncomeStatement([
      line(revenue.id, 0, 100000),
      line(returns.id, 8000, 0),
      line(cogs.id, 60000, 0),
      line(purchaseReturns.id, 0, 4000),
    ], [revenue, returns, cogs, purchaseReturns]);
    expect(statement.totalRevenueMinor, 92000);
    expect(statement.totalExpenseMinor, 56000);
    expect(statement.netResultMinor, 36000);
    expect(
        statement.revenueRows
            .singleWhere((r) => r.code == '42')
            .amountMinor,
        -8000);
    expect(
        statement.expenseRows
            .singleWhere((r) => r.code == '53')
            .amountMinor,
        -4000);
  });

  test('الميزانية العمومية قبل الإقفال: الأصول 625,000 والخصوم 100,000 '
      'والحقوق 500,000 والنتيجة الجارية 25,000 — فالمعادلة متوازنة',
      () {
    final (lines, accounts) = knownCycle();
    final sheet = buildBalanceSheet(lines, accounts);
    expect(sheet.totalAssetsMinor, 625000);
    expect(sheet.totalLiabilitiesMinor, 100000);
    expect(sheet.totalEquityMinor, 525000,
        reason: 'رأس المال 500,000 + النتيجة الجارية 25,000');
    expect(sheet.currentResultMinor, 25000);
    expect(sheet.isBalanced, isTrue);
    // و331/332 صفرتا فلا صف لهما قبل الإقفال.
    expect(sheet.equityRows.any((r) => r.code == '331'), isFalse);
  });

  test('الميزانية بعد الإقفال السنوي: النتيجة في 331 فالجارية صفر — '
      'والمعادلة باقية متوازنة (معيار F-077: مطابقة الحساب اليدوي)',
      () {
    _id = 0;
    final box = acc('1111', AccountType.asset);
    final receivables = acc('112', AccountType.asset);
    final stock = acc('113', AccountType.asset);
    final creditors = acc('211', AccountType.liability);
    final capital = acc('311', AccountType.equity);
    final retained = acc('331', AccountType.equity);
    final lines = [
      line(box.id, 545000, 0),
      line(receivables.id, 40000, 0),
      line(stock.id, 40000, 0),
      line(creditors.id, 0, 100000),
      line(capital.id, 0, 500000),
      line(retained.id, 0, 25000),
    ];
    final sheet = buildBalanceSheet(lines, [
      box, receivables, stock, creditors, capital, retained,
    ]);
    expect(sheet.totalAssetsMinor, 625000);
    expect(sheet.totalLiabilitiesMinor, 100000);
    expect(sheet.totalEquityMinor, 525000,
        reason: 'رأس المال 500,000 + الأرباح المحتجزة 25,000');
    expect(sheet.currentResultMinor, 0);
    expect(sheet.isBalanced, isTrue);
    final retainedRow = sheet.equityRows.singleWhere((r) => r.code == '331');
    expect(retainedRow.amountMinor, 25000);
  });

  test('المسحوبات 321 تُعرض بالجانب المدين وتخفض حقوق الملكية '
      '(03 §1-4: العكسية بطبيعتها المعلنة)', () {
    _id = 0;
    final box = acc('1111', AccountType.asset);
    final withdrawals =
        acc('321', AccountType.equity, side: NormalSide.debit);
    final capital = acc('311', AccountType.equity);
    final sheet = buildBalanceSheet([
      line(box.id, 80000, 0),
      line(withdrawals.id, 20000, 0),
      line(capital.id, 0, 100000),
    ], [box, withdrawals, capital]);
    expect(sheet.totalEquityMinor, 80000,
        reason: '100,000 رأس مال − 20,000 مسحوبات');
    final row = sheet.equityRows.singleWhere((r) => r.code == '321');
    expect(row.isDebitSide, isTrue);
    expect(row.magnitudeMinor, 20000);
    expect(sheet.isBalanced, isTrue);
  });

  test('الميزان غير المتوازن مستحيل بنياً — والقائمة تعرض ما هي عليه '
      'فلا طمر (نمط شارة الميزان F-068): صياغة بحالة صمّاء تكشف الحكم',
      () {
    _id = 0;
    final box = acc('1111', AccountType.asset);
    final capital = acc('311', AccountType.equity);
    // سطر واحد لا مقابل له — غير وارد عبر المحرك، والصياغة تعرضه
    // كما هو فالقائمة ليست مصدر توازن بل مرآة له.
    final sheet = buildBalanceSheet([
      line(box.id, 100000, 0),
    ], [box, capital]);
    expect(sheet.isBalanced, isFalse);
    expect(sheet.totalAssetsMinor, 100000);
    expect(sheet.totalEquityMinor, 0);
  });
}
