/// القوائم المالية الأساسية — الدفعة 33 (عاشرة م2) على النص المعتمد:
/// F-096 «ميزانية عمومية + قائمة دخل من أنواع الحسابات» و07 §1.6
/// «التقارير تُبنى من أنواع الحسابات لا من أسمائها أو أكوادها» —
/// إعادة تسمية أو ترقيم لا تكسر أي قائمة.
///
/// المنطق النقي حصراً (F-010) — التجميع الخام من القاعدة والصياغة هنا
/// (نمط التقارير D-089: قراءة من المرحّل بلا جداول تجميع مخزنة).
///
/// - قائمة الدخل بمدى تاريخ: الإيرادات بعينتها (دائن − مدين فالعكسية
///   42 سالبة تخفض الإيراد) والمصروفات بعينتها (مدين − دائن فالعكسية
///   53 سالبة تخفض المصروف) — والصافي مشتق لا مخزن.
/// - الميزانية العمومية «إلى تاريخ»: الأصول بعينتها والخصوم والحقوق
///   بعينتها، والنتيجة الجارية (من حسابات الإيراد والمصروف حتى ذاك
///   التاريخ) تُدرج سطراً بحقوق الملكية حين تختلف عن الصفر — فتوازن
///   المعادلة قبل الإقفال وبعده معاً: بعد الإقفال السنوي تصفُو حسابات
///   النتيجة فينتقل الصافي إلى 331 وتوازن القائمة بلا سطر جارٍ
///   (معيار F-077: «سنة مقفلة تنتج قوائم مطابقة للحساب اليدوي»).

import 'journal.dart';

/// صف قائمة الدخل — حسابٌ نتيجي بمبلغه بعينته.
class IncomeStatementRow {
  final int accountId;
  final String code;
  final String name;
  final int amountMinor;

  const IncomeStatementRow({
    required this.accountId,
    required this.code,
    required this.name,
    required this.amountMinor,
  });
}

/// قائمة الدخل كاملة — الصافي مشتق لا مخزن (نمط الصافي بالتقارير).
class IncomeStatement {
  final List<IncomeStatementRow> revenueRows;
  final List<IncomeStatementRow> expenseRows;
  final int totalRevenueMinor;
  final int totalExpenseMinor;

  const IncomeStatement({
    required this.revenueRows,
    required this.expenseRows,
    required this.totalRevenueMinor,
    required this.totalExpenseMinor,
  });

  /// موجب ربح وسالب خسارة (03 §4).
  int get netResultMinor => totalRevenueMinor - totalExpenseMinor;
}

/// بناء قائمة الدخل من أسطر المرحّل وفهرس الحسابات — والأسطر المارة
/// هنا مصفّاة بمدى التاريخ قبل الاستدعاء (التخزين يصفّي ولا يقرر).
IncomeStatement buildIncomeStatement(
  Iterable<LedgerLine> lines,
  List<AccountInfo> accounts,
) {
  final byId = <int, (int, int)>{};
  for (final line in lines) {
    final (d, c) = byId[line.accountId] ?? (0, 0);
    byId[line.accountId] = (d + line.debitMinor, c + line.creditMinor);
  }
  final revenueRows = <IncomeStatementRow>[];
  final expenseRows = <IncomeStatementRow>[];
  var totalRevenue = 0;
  var totalExpense = 0;
  for (final account in accounts) {
    if (!account.isLeaf) continue;
    final (debit, credit) = byId[account.id] ?? (0, 0);
    if (debit == 0 && credit == 0) continue;
    switch (account.type) {
      case AccountType.income:
        // عينة الإيراد دائن — والعكسية 42 سالبة تخفضه.
        final amount = credit - debit;
        revenueRows.add(IncomeStatementRow(
          accountId: account.id,
          code: account.code,
          name: account.name,
          amountMinor: amount,
        ));
        totalRevenue += amount;
      case AccountType.expense:
        // عينة المصروف مدين — والعكسية 53 سالبة تخفضه.
        final amount = debit - credit;
        expenseRows.add(IncomeStatementRow(
          accountId: account.id,
          code: account.code,
          name: account.name,
          amountMinor: amount,
        ));
        totalExpense += amount;
      case AccountType.asset:
      case AccountType.liability:
      case AccountType.equity:
        break; // الميزانية دونها — قائمة الدخل نتيجية حصراً
    }
  }
  int byCode(IncomeStatementRow a, IncomeStatementRow b) =>
      a.code.compareTo(b.code);
  revenueRows.sort(byCode);
  expenseRows.sort(byCode);
  return IncomeStatement(
    revenueRows: revenueRows,
    expenseRows: expenseRows,
    totalRevenueMinor: totalRevenue,
    totalExpenseMinor: totalExpense,
  );
}

/// صف الميزانية العمومية — حسابٌ ميزاني بمقداره وجانبه الفعلي.
class BalanceSheetRow {
  final int accountId;
  final String code;
  final String name;

  /// موجب دائن وسالب مدين بالعرض: الأصول مدينتها فتظهر بمقدارها على
  /// الجانب المدين، والخصوم والحقوق دائنتها — والعكسية بطبيعتها
  /// المعلنة (03 §1-4) فالمسحوبات 321 مدينة.
  final int amountMinor;

  const BalanceSheetRow({
    required this.accountId,
    required this.code,
    required this.name,
    required this.amountMinor,
  });

  bool get isDebitSide => amountMinor < 0;

  int get magnitudeMinor => amountMinor.abs();
}

/// الميزانية العمومية كاملة — والمعادلة عرضٌ للمالك كما هي.
class BalanceSheet {
  final List<BalanceSheetRow> assetRows;
  final List<BalanceSheetRow> liabilityRows;
  final List<BalanceSheetRow> equityRows;

  /// النتيجة الجارية حتى تاريخ القائمة — من حسابات النتيجة ذاتها،
  /// موجب ربح (حقوقاً) وسالب خسارة. الصفر بعد الإقفال السنوي.
  final int currentResultMinor;

  const BalanceSheet({
    required this.assetRows,
    required this.liabilityRows,
    required this.equityRows,
    required this.currentResultMinor,
  });

  int get totalAssetsMinor {
    var total = 0;
    for (final row in assetRows) {
      total += row.magnitudeMinor;
    }
    return total;
  }

  int get totalLiabilitiesMinor {
    var total = 0;
    for (final row in liabilityRows) {
      total += row.amountMinor;
    }
    return total;
  }

  int get totalEquityMinor {
    var total = 0;
    for (final row in equityRows) {
      total += row.amountMinor;
    }
    total += currentResultMinor;
    return total;
  }

  /// المعادلة المحاسبية كما تُقرأ يدوياً: الأصول = الخصوم + حقوق
  /// الملكية (بنتيجتها الجارية) — توازنها بالبناء متى كان الميزان
  /// متوازناً (F-068) وتُعرض للمالك كما هي فلا يُطمَر خلل.
  bool get isBalanced =>
      totalAssetsMinor == totalLiabilitiesMinor + totalEquityMinor;
}

/// بناء الميزانية العمومية من أسطر المرحّل حتى تاريخ ما (الأسطر
/// مصفّاة قبل الاستدعاء) — الحسابات الميزانية بعينتها والنتيجة
/// الجارية من حسابات النتيجة ذاتها.
BalanceSheet buildBalanceSheet(
  Iterable<LedgerLine> lines,
  List<AccountInfo> accounts,
) {
  final byId = <int, (int, int)>{};
  for (final line in lines) {
    final (d, c) = byId[line.accountId] ?? (0, 0);
    byId[line.accountId] = (d + line.debitMinor, c + line.creditMinor);
  }
  final assetRows = <BalanceSheetRow>[];
  final liabilityRows = <BalanceSheetRow>[];
  final equityRows = <BalanceSheetRow>[];
  var incomeNet = 0;
  var expenseNet = 0;
  for (final account in accounts) {
    if (!account.isLeaf) continue;
    final (debit, credit) = byId[account.id] ?? (0, 0);
    switch (account.type) {
      case AccountType.asset:
        if (debit == 0 && credit == 0) continue;
        // عينة الأصل مدين: الموجب يعرض مديناً (سالب بإشارة الصف).
        final amount = debit - credit;
        assetRows.add(BalanceSheetRow(
          accountId: account.id,
          code: account.code,
          name: account.name,
          amountMinor: -amount,
        ));
      case AccountType.liability:
        if (debit == 0 && credit == 0) continue;
        final amount = credit - debit;
        liabilityRows.add(BalanceSheetRow(
          accountId: account.id,
          code: account.code,
          name: account.name,
          amountMinor: amount,
        ));
      case AccountType.equity:
        if (debit == 0 && credit == 0) continue;
        // الحقوق دائنتها عينةً — والعكسية (المسحوبات 321) مدينتها
        // فتُعرض بالجانب المدين (إشارتها سالبة) وهي خفضٌ للحقوق
        // بعين القاعدة المحاسبية (03 §1-4).
        final isDebitNormal = account.normalSide == NormalSide.debit;
        final natural =
            isDebitNormal ? debit - credit : credit - debit;
        equityRows.add(BalanceSheetRow(
          accountId: account.id,
          code: account.code,
          name: account.name,
          amountMinor: isDebitNormal ? -natural : natural,
        ));
      case AccountType.income:
        incomeNet += credit - debit;
      case AccountType.expense:
        expenseNet += debit - credit;
    }
  }
  int byCode(BalanceSheetRow a, BalanceSheetRow b) =>
      a.code.compareTo(b.code);
  assetRows.sort(byCode);
  liabilityRows.sort(byCode);
  equityRows.sort(byCode);
  return BalanceSheet(
    assetRows: assetRows,
    liabilityRows: liabilityRows,
    equityRows: equityRows,
    currentResultMinor: incomeNet - expenseNet,
  );
}
