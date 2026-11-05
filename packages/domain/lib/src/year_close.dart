/// الإقفال السنوي — الدفعة 32 (تاسعة م2) على النص المعتمد حرفاً:
/// س-21 (06) وF-077 وD-068 و07 §1.5 و03 §4.
///
/// المنطق النقي حصراً (F-010) — المحرك والمستندات بالتخزين، والصياغة
/// هنا بلا قاعدة ولا واجهة. نص س-21:
/// - الإدخال: مراجعة ميزان المراجعة والنتيجة قبلية؛ تأكيد الإقفال بعد
///   إقفال كل فترات السنة — **أي فترة مفتوحة تطلب إقفالها أولاً**.
/// - عند الترحيل: قيد إغلاق الإيرادات (كل حساب إيرادٍ يُصفَّر بالجانب
///   المعاكس لعينته — والعكسية 42 ضمنهم) مقابل 332 جاري النتيجة؛ قيد
///   إغلاق المصروفات (كل حساب مصروفٍ يُصفَّر بالجانب المعاكس — والعكسية
///   53 ضمنها) مقابل 332؛ ثم الصافي: ربح ← 332 مدين / 331 الأرباح
///   المحتجزة دائن (خسارة بالعكس) (03 §4).
/// - توليد الأرصدة الافتتاحية للسنة الجديدة على الحسابات الميزانية
///   (1x/2x/3x) — والنتيجة قدمت إلى 331 فتدخل الافتتاحية ضمن حقوقها.
/// - بعد الترحيل: السنة «مقفلة» ولا ترحيل فيها أبداً؛ نتائج السنوات
///   تتراكم في 331.
///
/// القاعدة الميكانيكية المعلنة: التصفير بالجانب **المعاكس لعينة الحساب**
/// — فالإيراد العادي (عينته دائن) يُدين برصيده، والعكسية 42 (عينتها
/// مدين) تُدائن برصيدها — وهذا هو المعنى المحاسبي الوحيد الصحيح
/// لـ«بما فيها العكسية 42/53» نص س-21: الاشتمال لا تكرار العينة.
/// وإقفالُ سنةٍ لا يزيل أثرَ حركاتِها من الدفتر — يُجمد فتراتها ويصفّر
/// حسابات النتيجة فينتقل رصيدها إلى 331 حيث يتراكم (F-077).

import 'journal.dart';

/// رصيد حساب خام للإقفال — مدينُه ودائنُه كما خرجا من أسطر المرحّل،
/// والعينة باتجاهها الطبيعي المعلن (03 §1-4: العكسية طبيعتها معاكسة
/// لنوعها).
class YearCloseAccountBalance {
  final int accountId;
  final String code;
  final String name;
  final AccountType type;
  final NormalSide normalSide;
  final bool isLeaf;
  final int debitMinor;
  final int creditMinor;

  const YearCloseAccountBalance({
    required this.accountId,
    required this.code,
    required this.name,
    required this.type,
    required this.normalSide,
    required this.isLeaf,
    required this.debitMinor,
    required this.creditMinor,
  });

  /// الرصيد الطبيعي: موجب على جانب العينة والسالب عكسه مشروع (س-50).
  int get naturalBalanceMinor =>
      normalSide == NormalSide.debit
          ? debitMinor - creditMinor
          : creditMinor - debitMinor;
}

/// أخطاء رفض الإقفال السنوي — محمولة بيانات والوصف بالواجهة (نمط
/// المدققين)، و[describeYearCloseValidationError] تخدم الاختبارات.
sealed class YearCloseValidationError {
  const YearCloseValidationError();
}

/// السنة المطلوبة غائبة عن المعرف.
class FiscalYearNotFound extends YearCloseValidationError {
  final int yearId;

  const FiscalYearNotFound(this.yearId);
}

/// السنة مقفلة أصلاً — الإقفال مرة واحدة بلا إقفال مزدوج (س-20 روحاً).
class FiscalYearAlreadyClosed extends YearCloseValidationError {
  final String yearName;

  const FiscalYearAlreadyClosed(this.yearName);
}

/// أي فترة مفتوحة في السنة تطلب إقفالها أولاً (س-21 نصاً).
class YearHasOpenPeriods extends YearCloseValidationError {
  final String yearName;
  final int openCount;

  const YearHasOpenPeriods(this.yearName, this.openCount);
}

/// السنة التالية موجودة أصلاً — لا بذر مزدوج ولا سنة فوق سنة قائمة.
class NextFiscalYearExists extends YearCloseValidationError {
  final String nextYearName;

  const NextFiscalYearExists(this.nextYearName);
}

/// حساب من حسابَي النتيجة (332/331) غائب عن الدليل — بيانات الإعداد
/// هي مصدرهما (03 §1: الدليل إعداد لا كود) والإقفال بلا أحدهما مرفوض.
class YearCloseAccountMissing extends YearCloseValidationError {
  final String code;

  const YearCloseAccountMissing(this.code);
}

String describeYearCloseValidationError(YearCloseValidationError error) =>
    switch (error) {
      FiscalYearNotFound(:final yearId) =>
        'لا سنة مالية بالمعرف $yearId',
      FiscalYearAlreadyClosed(:final yearName) =>
        'السنة $yearName مقفلة أصلاً — الإقفال مرة واحدة (س-20 روحاً)',
      YearHasOpenPeriods(:final yearName, :final openCount) =>
        'السنة $yearName بها $openCount فترة مفتوحة — أقفلها أولاً (س-21)',
      NextFiscalYearExists(:final nextYearName) =>
        'السنة التالية $nextYearName موجودة أصلاً — لا بذر مزدوج',
      YearCloseAccountMissing(:final code) =>
        'الحساب $code غائب عن الدليل — الإقفال يحتاجه (03 §4)',
    };

/// رفض الإقفال السنوي — يحمل الأخطاء النوعية (نمط الاستثناءات الموثق).
class YearCloseException implements Exception {
  final List<YearCloseValidationError> errors;

  const YearCloseException(this.errors);

  @override
  String toString() =>
      'رفض الإقفال السنوي: '
      '${errors.map(describeYearCloseValidationError).join('؛ ')}';
}

/// سطر خطة إقفال — جهة واحدة على حساب واحد (سطر القيد جهة واحدة).
class YearCloseLine {
  final int accountId;
  final int debitMinor;
  final int creditMinor;

  const YearCloseLine({
    required this.accountId,
    this.debitMinor = 0,
    this.creditMinor = 0,
  });
}

/// خطة الإقفال السنوي كاملة — ثلاثة قيود مقترحة وافتتاحية السنة
/// الجديدة، كلها مسودات خام تُرحَّل عبر المحرك الموحد ذاته حصراً.
class YearClosePlan {
  /// أسطر تصفير الإيرادات على حساباتها (بدون 332).
  final List<YearCloseLine> incomeLines;

  /// أسطر تصفير المصروفات على حساباتها (بدون 332).
  final List<YearCloseLine> expenseLines;

  /// أسطر الافتتاحية للحسابات الميزانية (بدون 332 — صفر بعد الصافي).
  final List<YearCloseLine> openingLines;

  /// صافي السنة: موجب ربح وسالب خسارة والصفر لا قيد صافٍ (س-21).
  final int netResultMinor;

  /// مجموع ما جرى إلى 332 دائناً من الإيرادات (صافي ما بعد العكسية 42).
  final int incomeTotalMinor;

  /// مجموع ما جرى إلى 332 مديناً من المصروفات (صافي ما بعد العكسية 53).
  final int expenseTotalMinor;

  const YearClosePlan({
    required this.incomeLines,
    required this.expenseLines,
    required this.openingLines,
    required this.netResultMinor,
    required this.incomeTotalMinor,
    required this.expenseTotalMinor,
  });

  /// الافتتاحية متوازنة بالبناء متى كان الميزان متوازناً (F-068) —
  /// تُعرض للمالك كما هي فلا يُطمَر خلل (نمط ميزان المراجعة).
  bool get openingBalanced {
    var debit = 0;
    var credit = 0;
    for (final line in openingLines) {
      debit += line.debitMinor;
      credit += line.creditMinor;
    }
    return debit == credit;
  }
}

/// بناء خطة الإقفال من الأرصدة الخام — نقية ومعمولة بلا قاعدة:
/// - تصفير كل حساب نتيجةٍ ورقيٍّ برصيدٍ غير صفري بالجانب المعاكس
///   لعينته (الإيراد العادي يُدين والعكسية 42 تُدائن — والمصروف العادي
///   يُدائن والعكسية 53 تُدين).
/// - 332 يحمل ما قوبل به التصفير: دائنٌ بالإيرادات ومدينٌ بالمصروفات.
/// - الصافي إلى 331: ربح 332 مدين/331 دائن، خسارة بالعكس، صفر بلا سطر.
/// - الافتتاحية: أرصدة الحسابات الميزانية الورقية (أصول/خصوم/حقوق)
///   باتجاهها الطبيعي — و331 بعد إدخال صافي السنة، و332 مستبعدة (صفر).
YearClosePlan buildYearClosePlan({
  required List<YearCloseAccountBalance> balances,
  required int resultAccountId,
  required int retainedAccountId,
}) {
  YearCloseLine zeroLine(YearCloseAccountBalance account) {
    // التصفير معاكسٌ لجانب الرصيد الفعلي لا لعينة النوع: رصيدٌ مدين
    // يُدائن ورصيدٌ دائن يُدين — فالعكسية 42 (عينتها مدين) برصيدها
    // المدين تُدائن، والإيراد العادي برصيده الدائن يُدين، وحتى الرصيد
    // الشاذ (إيرادٌ عادي بميزان مدين) يُصفَّر على عينته المدينة لا
    // بالقسر على النوع — عين القاعدة المحاسبية ذاتها (03 §1-4).
    final balance = account.naturalBalanceMinor;
    final amount = balance.abs();
    final balanceIsDebit = account.normalSide == NormalSide.debit
        ? balance > 0
        : balance < 0;
    return balanceIsDebit
        ? YearCloseLine(accountId: account.accountId, creditMinor: amount)
        : YearCloseLine(accountId: account.accountId, debitMinor: amount);
  }

  final incomeLines = <YearCloseLine>[];
  final expenseLines = <YearCloseLine>[];
  var incomeCredit = 0; // ما دخل 332 دائناً من الإيرادات
  var incomeDebit = 0; // ما دخل 332 مديناً من العكسية
  var expenseDebit = 0; // ما دخل 332 مديناً من المصروفات
  var expenseCredit = 0; // ما دخل 332 دائناً من العكسية

  for (final account in balances) {
    if (!account.isLeaf) continue;
    if (account.accountId == resultAccountId ||
        account.accountId == retainedAccountId) {
      continue;
    }
    if (account.naturalBalanceMinor == 0) continue;
    switch (account.type) {
      case AccountType.income:
        final line = zeroLine(account);
        incomeLines.add(line);
        // 332 يقابل التصفير بالجانب المعاكس لسطر الحساب.
        if (line.debitMinor > 0) {
          incomeCredit += line.debitMinor;
        } else {
          incomeDebit += line.creditMinor;
        }
      case AccountType.expense:
        final line = zeroLine(account);
        expenseLines.add(line);
        if (line.creditMinor > 0) {
          expenseDebit += line.creditMinor;
        } else {
          expenseCredit += line.debitMinor;
        }
      case AccountType.asset:
      case AccountType.liability:
      case AccountType.equity:
        break; // الميزانية تُعالج بالافتتاحية دونها
    }
  }

  // صافي ما قوبل به من كل جهة — وهو مُدخل 332 الصافي.
  final incomeTotalMinor = incomeCredit - incomeDebit;
  final expenseTotalMinor = expenseDebit - expenseCredit;
  final netResultMinor = incomeTotalMinor - expenseTotalMinor;

  final openingLines = <YearCloseLine>[];
  for (final account in balances) {
    if (!account.isLeaf) continue;
    // الافتتاحية على الحسابات الميزانية حصراً (س-21: 1x/2x/3x) —
    // حسابات النتيجة صفرت بإقفالها فلا افتتاحية لها أصلاً.
    switch (account.type) {
      case AccountType.income:
      case AccountType.expense:
        continue;
      case AccountType.asset:
      case AccountType.liability:
      case AccountType.equity:
        break;
    }
    if (account.accountId == resultAccountId) continue;
    var natural = account.naturalBalanceMinor;
    if (account.accountId == retainedAccountId) {
      natural += netResultMinor;
    }
    if (natural == 0) continue;
    // الافتتاحية بجانب الرصيد المعدل فعله: الرصيد الطبيعي موجبٌ على
    // العينة بالتعريف ذاته (س-50) فبعينتها، وسالبٌ (عجز متراكم أو رصيد
    // شاذ) فبالجانب المعاكس بمقداره.
    final amount = natural.abs();
    final onNormalSide = natural > 0;
    final isDebitNormal = account.normalSide == NormalSide.debit;
    openingLines.add(
      onNormalSide
          ? YearCloseLine(
              accountId: account.accountId,
              debitMinor: isDebitNormal ? amount : 0,
              creditMinor: isDebitNormal ? 0 : amount,
            )
          : YearCloseLine(
              accountId: account.accountId,
              debitMinor: isDebitNormal ? 0 : amount,
              creditMinor: isDebitNormal ? amount : 0,
            ),
    );
  }

  return YearClosePlan(
    incomeLines: incomeLines,
    expenseLines: expenseLines,
    openingLines: openingLines,
    netResultMinor: netResultMinor,
    incomeTotalMinor: incomeTotalMinor,
    expenseTotalMinor: expenseTotalMinor,
  );
}

/// صورة معاينة الإقفال السنوي للشاشة — كلها قراءة لا كتابة (D-183:
/// ما يُرى هو ما سينفذ)، والأخطاء إن وُجدت فالزر معطل عندها. حاضنة
/// نقية يملؤها التخزين من قراءاته (نمط التقارير).
class YearClosePreview {
  final String yearName;
  final String startDateText;
  final String endDateText;
  final bool yearClosed;
  final int periodsCount;
  final int openPeriodsCount;
  final (int, int) trialTotals;
  final YearClosePlan plan;

  const YearClosePreview({
    required this.yearName,
    required this.startDateText,
    required this.endDateText,
    required this.yearClosed,
    required this.periodsCount,
    required this.openPeriodsCount,
    required this.trialTotals,
    required this.plan,
  });

  bool get isReady =>
      !yearClosed && openPeriodsCount == 0 && plan.openingBalanced;
}

/// نتيجة الإقفال المنفذ — أرقام قيوده للسجل والعرض.
class YearCloseResult {
  final String yearName;
  final String nextYearName;
  final List<int> closingMoveIds;
  final int? openingMoveId;
  final int netResultMinor;
  final int nextYearId;

  const YearCloseResult({
    required this.yearName,
    required this.nextYearName,
    required this.closingMoveIds,
    required this.openingMoveId,
    required this.netResultMinor,
    required this.nextYearId,
  });
}
