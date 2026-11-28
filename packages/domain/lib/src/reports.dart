/// التقارير اليومية الخمسة — دفعة م1 السادسة (س-71..س-75، D-088..D-090
/// معروضة): «ميزان المراجعة» و«الصناديق» و«الذمم المدينة والدائنة»
/// و«المخزون» و«مبيعات وحركة الأصناف» (09 §2 نص م1-نواة).
///
/// قراءات نقية من المرحّل حصراً — لا جداول تجميع مخزنة: الأرصدة مشتقة
/// دائماً والسجل مصدراً (D-067)، فالتقرير يُبنى لحظة قراءته ولا يُخزَّن
/// أبداً. التجميع الخام من القاعدة (التخزين يحفظ ولا يقرر) والصياغة
/// والاتجاهات هنا بالمجال النقي (F-010) بدوال خالصة تُختبر بلا قاعدة.
///
/// - ميزان المراجعة متوازن بالبناء (F-068): أرجل المرحّل فقط، ومجموع
///   المدين يساوي مجموع الدائن حرفاً — والتقرير يعرضهما ليراهما المالك.
/// - الذمم بالاتجاهين (05 §5): رصيد مدين على حساب السيطرة «هم يدينون
///   لنا» (theyOweUs) ودائن «نحن مدينون لهم» (weOweThem) — فتظهر
///   الدفعة السابقة والرصيد المعاكس صحيحين دون أي حساب يدوي.
/// - المدى الزمني للسير بالمدى: نص ISO «YYYY-MM-DD» حصراً (D-077) وفرزه
///   المعجمي زمني صحيح — والمدقق هنا يرفض التاريخ الفاسد والمدى المقلوب
///   قبل أن يلمس القاعدة أصلاً.
/// - المشتريات المستقل (س-84، دفعة 6-ب) بمرآة الحركة البيعية ذاتها:
///   شراء ومردود شراء بمدى تاريخ والصافي مشتق — تنفيذ لوعد D-089
///   «تقرير المشتريات المستقل مع واجهات التقارير».
library;

import 'invoice.dart' show roundHalfAwayFromZeroRatio;
import 'journal.dart' show AccountInfo, NormalSide, isValidIsoDate;

// ═══════════════════════════════════════════════════════════════════
// 1. ميزان المراجعة (س-71) — التجميع الخام من القاعدة والصياغة هنا.
// ═══════════════════════════════════════════════════════════════════

/// سطر خام من أرجل المرحّل (المواد الخام كما تخرج من القاعدة).
class TrialBalanceRawLine {
  final int accountId;
  final int debitMinor;
  final int creditMinor;

  const TrialBalanceRawLine({
    required this.accountId,
    required this.debitMinor,
    required this.creditMinor,
  });
}

/// صف حساب في ميزان المراجعة — والميزان بالاتجاه الطبيعي للنوع (03 §2):
/// الأصول والمصروفات مدينتها وغيرها دائنها، والعكسية بطبيعتها المعلنة.
class TrialBalanceRow {
  final AccountInfo account;
  final int debitSumMinor;
  final int creditSumMinor;

  /// الرصيد باتجاه الطبيعي: موجب على جانبه الطبيعي وسالب على المعاكس
  /// (رصيد عكسي يظهر كما هو — لا يُقلب خفية).
  final int balanceMinor;

  const TrialBalanceRow({
    required this.account,
    required this.debitSumMinor,
    required this.creditSumMinor,
    required this.balanceMinor,
  });
}

/// ميزان المراجعة كاملاً — متوازن بالبناء على المرحّل حصراً (F-068)،
/// و`isBalanced` تُعرض للمالك كما هي فلا يُطمَر خلل ولو كان مستحيلاً.
class TrialBalanceReport {
  final List<TrialBalanceRow> rows;
  final int totalDebitMinor;
  final int totalCreditMinor;

  const TrialBalanceReport({
    required this.rows,
    required this.totalDebitMinor,
    required this.totalCreditMinor,
  });

  bool get isBalanced => totalDebitMinor == totalCreditMinor;
}

/// بناء الميزان: تجميع أرجل المرحّل لكل حساب، فحساب بلا حركة لا يُعرض،
/// والصفوف بترتيب الكود المعجمي (فرز ISO الصحيح لأكواد الدليل — نمط
/// LedgerAccountIndex)، والأرصدة بدالة المجال النقية ذاتها المستعملة
/// بالاختبارات (نمط س-50).
TrialBalanceReport buildTrialBalance(
  List<TrialBalanceRawLine> lines,
  List<AccountInfo> accounts,
) {
  final byId = {for (final a in accounts) a.id: a};
  final sums = <int, (int, int)>{};
  for (final line in lines) {
    final current = sums[line.accountId] ?? (0, 0);
    sums[line.accountId] =
        (current.$1 + line.debitMinor, current.$2 + line.creditMinor);
  }
  final rows = <TrialBalanceRow>[];
  for (final entry in sums.entries) {
    final account = byId[entry.key];
    if (account == null) continue;
    final (debitSum, creditSum) = entry.value;
    if (debitSum == 0 && creditSum == 0) continue;
    final balance = account.normalSide == NormalSide.debit
        ? debitSum - creditSum
        : creditSum - debitSum;
    rows.add(TrialBalanceRow(
      account: account,
      debitSumMinor: debitSum,
      creditSumMinor: creditSum,
      balanceMinor: balance,
    ));
  }
  rows.sort((a, b) => a.account.code.compareTo(b.account.code));
  var totalDebit = 0;
  var totalCredit = 0;
  for (final row in rows) {
    totalDebit += row.debitSumMinor;
    totalCredit += row.creditSumMinor;
  }
  return TrialBalanceReport(
    rows: rows,
    totalDebitMinor: totalDebit,
    totalCreditMinor: totalCredit,
  );
}

// ═══════════════════════════════════════════════════════════════════
// 2. الصناديق (س-72) — الصورة النقية التي يبنيها التخزين من رصيده.
// ═══════════════════════════════════════════════════════════════════

/// صف صندوق في تقرير الصناديق — الرصيد بالأساسية من معادلة الصندوق
/// ذاتها (الافتتاحي + الداخل − الخارج، والتحويل دخلاً للمستلم وخروجاً
/// للمرسل)، ونشاطه هو نشاط حسابه الورقي (تعطيل الحساب تعطيل للصندوق).
class CashBoxReportRow {
  final int boxId;
  final String name;

  /// س236 (د10 — نوع الصندوق الجارٍ من الترحيلة v38): 'cash' نقدي
  /// و'bank' جارٍ بنكي — والبنكي يحمل اسم بنكه ورقم حسابه (المعروضان).
  final String kind;
  final String? bankName;

  /// س236: رقم حساب البنك — بيان ثانٍ للصندوق البنكي.
  final String? accountNumber;

  /// س236: معرف العملة — التسوية البنكية تعمل بعملة صندوقها (D-086).
  final int currencyId;
  final String currencyCode;
  final String accountCode;
  final int balanceBaseMinor;
  final bool isActive;

  const CashBoxReportRow({
    required this.boxId,
    required this.name,
    this.kind = 'cash',
    this.bankName,
    this.accountNumber,
    this.currencyId = 1,
    required this.currencyCode,
    required this.accountCode,
    required this.balanceBaseMinor,
    required this.isActive,
  });

  bool get isBank => kind == 'bank';
}

// ═══════════════════════════════════════════════════════════════════
// 3. الذمم المدينة والدائنة (س-73) — بالاتجاهين (05 §5).
// ═══════════════════════════════════════════════════════════════════

/// اتجاه الذمة (05 §5): هم يدينون لنا أم نحن مدينون لهم — دفعة سابقة
/// أو مردود يقلب الاتجاه آلياً بلا حساب يدوي.
enum PartyBalanceDirection { theyOweUs, weOweThem }

/// الخام: صافي ذمة طرف على حسابَي السيطرة (112/211) بالأساسية —
/// موجبٌ رصيداً مديناً وسالبٌ دائناً (Σ مدين − Σ دائن).
class PartyControlRaw {
  final int partyId;
  final String partyName;
  final int netDebitMinor;

  const PartyControlRaw({
    required this.partyId,
    required this.partyName,
    required this.netDebitMinor,
  });
}

/// صف ذمة في التقرير — صافي الطرف على حسابَي السيطرة معاً (نمط كشف
/// الطرف F-024: القصة الكاملة لا تفصيل حسابين).
class ReceivablesPayablesRow {
  final int partyId;
  final String partyName;
  final PartyBalanceDirection direction;
  final int amountMinor;

  const ReceivablesPayablesRow({
    required this.partyId,
    required this.partyName,
    required this.direction,
    required this.amountMinor,
  });
}

/// صياغة الذمم: الصفر يخرج (لا ذمة ولا صف)، والموجب مدينٌ لنا والسالب
/// نحن المدينون بمقداره — والفرز باسم الطرف للعرض.
List<ReceivablesPayablesRow> buildReceivablesPayables(
  List<PartyControlRaw> raws,
) {
  final rows = <ReceivablesPayablesRow>[];
  for (final raw in raws) {
    if (raw.netDebitMinor == 0) continue;
    rows.add(ReceivablesPayablesRow(
      partyId: raw.partyId,
      partyName: raw.partyName,
      direction: raw.netDebitMinor > 0
          ? PartyBalanceDirection.theyOweUs
          : PartyBalanceDirection.weOweThem,
      amountMinor: raw.netDebitMinor.abs(),
    ));
  }
  rows.sort((a, b) => a.partyName.compareTo(b.partyName));
  return rows;
}

// ═══════════════════════════════════════════════════════════════════
// 4. المخزون (س-74) — الكمية والقيمة من stock_balances والمتوسط عرضاً.
// ═══════════════════════════════════════════════════════════════════

/// الخام: صف رصيد مخزون (صنف × مستودع) كما خرج من القاعدة.
class InventoryRawRow {
  final int itemId;
  final String sku;
  final String name;
  final String? warehouseName;
  final int qtyBase;
  final int totalValueMinor;

  const InventoryRawRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.warehouseName,
    required this.qtyBase,
    required this.totalValueMinor,
  });
}

/// صف المخزون — والمتوسط عرضاً حصراً (السجل مصدراً D-067: لا يُخزَّن
/// متوسط، يُشتق بالتقريب المعتمد النصف بعيداً عن الصفر عند العرض).
class InventoryReportRow {
  final int itemId;
  final String sku;
  final String name;
  final String? warehouseName;
  final int qtyBase;
  final int totalValueMinor;

  /// متوسط كلفة الوحدة للعرض — والصفر كميّة يعني لا متوسط (null).
  final int? avgCostBaseMinor;

  const InventoryReportRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.warehouseName,
    required this.qtyBase,
    required this.totalValueMinor,
    required this.avgCostBaseMinor,
  });
}

/// صياغة المخزون: المتوسط بالرسة المعتمدة ذاتها (roundHalfAwayFromZero)
/// والصفوف بترتيب الكود.
List<InventoryReportRow> buildInventoryReport(List<InventoryRawRow> raws) {
  final rows = <InventoryReportRow>[];
  for (final raw in raws) {
    rows.add(InventoryReportRow(
      itemId: raw.itemId,
      sku: raw.sku,
      name: raw.name,
      warehouseName: raw.warehouseName,
      qtyBase: raw.qtyBase,
      totalValueMinor: raw.totalValueMinor,
      avgCostBaseMinor: raw.qtyBase > 0
          ? roundHalfAwayFromZeroRatio(raw.totalValueMinor, raw.qtyBase)
          : null,
    ));
  }
  rows.sort((a, b) => a.sku.compareTo(b.sku));
  return rows;
}

// ═══════════════════════════════════════════════════════════════════
// 5. مبيعات وحركة الأصناف (س-75) — بيع ومردود بيع مرحّلان بمدى تاريخ.
// ═══════════════════════════════════════════════════════════════════

/// الخام: تجميع أسطر الفواتير المرحّلة لصنف بمدى تاريخ (البيع وردّه
/// بكمياته وقيمه بالأساسية — القيم المردودة بمقدارها الموجب كما تُخزن).
class SalesMovementRawRow {
  final int itemId;
  final String sku;
  final String name;
  final int qtySoldBase;
  final int salesValueBaseMinor;
  final int qtyReturnedBase;
  final int returnsValueBaseMinor;

  const SalesMovementRawRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.qtySoldBase,
    required this.salesValueBaseMinor,
    required this.qtyReturnedBase,
    required this.returnsValueBaseMinor,
  });
}

/// صف حركة صنف — والصافي مشتق هنا لا مخزن: بيع − مردود كمّةً وقيمة.
class SalesMovementRow {
  final int itemId;
  final String sku;
  final String name;
  final int qtySoldBase;
  final int salesValueBaseMinor;
  final int qtyReturnedBase;
  final int returnsValueBaseMinor;

  const SalesMovementRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.qtySoldBase,
    required this.salesValueBaseMinor,
    required this.qtyReturnedBase,
    required this.returnsValueBaseMinor,
  });

  int get netQtyBase => qtySoldBase - qtyReturnedBase;

  int get netValueBaseMinor => salesValueBaseMinor - returnsValueBaseMinor;
}

/// صياغة الحركة: صفوف بترتيب الكود — والصافي خاصية مشتقة تُحسب لحظة
/// العرض فلا رقمان مخزنان يختلفان أبداً.
List<SalesMovementRow> buildSalesMovementReport(
  List<SalesMovementRawRow> raws,
) {
  final rows = [
    for (final raw in raws)
      SalesMovementRow(
        itemId: raw.itemId,
        sku: raw.sku,
        name: raw.name,
        qtySoldBase: raw.qtySoldBase,
        salesValueBaseMinor: raw.salesValueBaseMinor,
        qtyReturnedBase: raw.qtyReturnedBase,
        returnsValueBaseMinor: raw.returnsValueBaseMinor,
      ),
  ];
  rows.sort((a, b) => a.sku.compareTo(b.sku));
  return rows;
}

// ═══════════════════════════════════════════════════════════════════
// 6. المشتريات — التقرير المستقل (س-84، دفعة 6-ب) — شراء ومردود شراء
//     بمدى تاريخ بمرآة الحركة البيعية (س-75) ذاتها، والصافي مشتق لا
//     مخزن: حركة الشراء ظاهرة في المخزون والميزان أصلاً (D-089)، وهذا
//     التقرير يجعلها مقروءة بذاتها بلا تفكيك القيود.
// ═══════════════════════════════════════════════════════════════════

/// الخام: تجميع أسطر الفواتير المرحّلة لصنف بمدى تاريخ (الشراء وردّه
/// بكمياته وقيمه بالأساسية — القيم المردودة بمقدارها الموجب كما تُخزن).
class PurchasesMovementRawRow {
  final int itemId;
  final String sku;
  final String name;
  final int qtyPurchasedBase;
  final int purchasesValueBaseMinor;
  final int qtyReturnedBase;
  final int returnsValueBaseMinor;

  const PurchasesMovementRawRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.qtyPurchasedBase,
    required this.purchasesValueBaseMinor,
    required this.qtyReturnedBase,
    required this.returnsValueBaseMinor,
  });
}

/// صف حركة شراء — والصافي مشتق هنا لا مخزن: شراء − مردود كمّةً وقيمة
/// (نمط الصافي البيعي ذاته — لا رقمان مخزنان يختلفان أبداً).
class PurchasesMovementRow {
  final int itemId;
  final String sku;
  final String name;
  final int qtyPurchasedBase;
  final int purchasesValueBaseMinor;
  final int qtyReturnedBase;
  final int returnsValueBaseMinor;

  const PurchasesMovementRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.qtyPurchasedBase,
    required this.purchasesValueBaseMinor,
    required this.qtyReturnedBase,
    required this.returnsValueBaseMinor,
  });

  int get netQtyBase => qtyPurchasedBase - qtyReturnedBase;

  int get netValueBaseMinor =>
      purchasesValueBaseMinor - returnsValueBaseMinor;
}

/// صياغة حركة الشراء: صفوف بترتيب الكود — بمرآة بناء الحركة البيعية
/// حرفاً فتقرأ الدفعتان بلسان واحد.
List<PurchasesMovementRow> buildPurchasesMovementReport(
  List<PurchasesMovementRawRow> raws,
) {
  final rows = [
    for (final raw in raws)
      PurchasesMovementRow(
        itemId: raw.itemId,
        sku: raw.sku,
        name: raw.name,
        qtyPurchasedBase: raw.qtyPurchasedBase,
        purchasesValueBaseMinor: raw.purchasesValueBaseMinor,
        qtyReturnedBase: raw.qtyReturnedBase,
        returnsValueBaseMinor: raw.returnsValueBaseMinor,
      ),
  ];
  rows.sort((a, b) => a.sku.compareTo(b.sku));
  return rows;
}

// ═══════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════
// مدقق المدى الزمني — الحرس الأول قبل أن يلمس التقرير القاعدة.
// ═══════════════════════════════════════════════════════════════════

sealed class ReportValidationError {
  const ReportValidationError();
}

/// تاريخ فاسد بغير ISO «YYYY-MM-DD» (D-077 — والميلادي أساس التخزين F-167).
class ReportRangeInvalidDate extends ReportValidationError {
  final String dateText;

  const ReportRangeInvalidDate(this.dateText);
}

/// مدى مقلوب: البداية بعد النهاية — لا صفوف ولا صمت، رفضٌ معلَّم.
class ReportRangeOrderInvalid extends ReportValidationError {
  final String fromText;
  final String toText;

  const ReportRangeOrderInvalid(this.fromText, this.toText);
}

/// مدقق مدى التقرير: صلاحية ISO للطرفين ثم ترتيبهما (الفرز المعجمي
/// للنص ISO زمني صحيح — D-077)؛ والفراغ مرفض فصلاً.
List<ReportValidationError> validateReportRange(
  String fromText,
  String toText,
) {
  final errors = <ReportValidationError>[];
  if (!isValidIsoDate(fromText)) {
    errors.add(ReportRangeInvalidDate(fromText));
  }
  if (!isValidIsoDate(toText)) {
    errors.add(ReportRangeInvalidDate(toText));
  }
  if (errors.isEmpty && fromText.compareTo(toText) > 0) {
    errors.add(ReportRangeOrderInvalid(fromText, toText));
  }
  return errors;
}

String describeReportValidationError(ReportValidationError error) =>
    switch (error) {
      ReportRangeInvalidDate(:final dateText) =>
        'تاريخ فاسد «$dateText» — الصيغة المعتمدة YYYY-MM-DD ميلادية حصراً',
      ReportRangeOrderInvalid(:final fromText, :final toText) =>
        'مدى مقلوب: البداية $fromText بعد النهاية $toText',
    };

/// رفض مدقق التقرير — يحمل الأخطاء النوعية المحمولة (نمط الأطراف).
class ReportValidationException implements Exception {
  final List<ReportValidationError> errors;

  const ReportValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق التقرير: ${errors.map(describeReportValidationError).join('؛ ')}';
}

// ═══════════════════════════════════════════════════════════════════
// 7. مطابقة دفتر المخزون (الدفعة 31 — ثامنة م2) — ربط المخزون بالدفتر
//     بصرياً (07 §3.1 محسوم س1: الجرد الدائم بالمتوسط المرجح، وD-012
//     محسومها): ثابت المطابقة D-067/§1.10 «رصيد حساب المخزون بالقيود ==
//     قيمة المخزون بالحركات» يُعرض للمالك كما هو فلا يُطمَر ميل ولو كان
//     مستحيلاً بنياً (نمط ميزان المراجعة F-068) — القراءة من أسطر القيود
//     المرحّلة المربوطة بحركاتها (move_lines.ref_stock_move_id — 07 §3.1
//     الالتزام المؤكد م-27) لا من أرصدة مخزنة ثانية.
// ═══════════════════════════════════════════════════════════════════

/// الخام: تجميع أسطر القيود المرحّلة الحاملة مرجع حركة مخزون لصنف —
/// قيمته الدفترية مدينُه − دائنُه (الصنف يُشتق من الحركة المرجَعة لا
/// من الحساب: الأسطر المربوطة هي عين ربط المخزون بالدفتر).
class InventoryLedgerRawRow {
  final int itemId;
  final String sku;
  final String name;
  final int debitMinor;
  final int creditMinor;

  const InventoryLedgerRawRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.debitMinor,
    required this.creditMinor,
  });
}

/// الخام: قيمة المخزون الفعلية لصنف من stock_balances مجمّعةً على
/// مستودعاته (مجموع القيمة الإجمالية D-067 — كلفة الوحدة عرضٌ لا مصدر).
class InventoryStockRawRow {
  final int itemId;
  final String sku;
  final String name;
  final int valueMinor;

  const InventoryStockRawRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.valueMinor,
  });
}

/// صف المطابقة لصنف — والميل مشتق هنا لا مخزن: الدفتري − المخزني،
/// والصنف بجهة واحدة فقط يظهر بطرف صفر فلا يخفى أي انفراد.
class InventoryReconciliationRow {
  final int itemId;
  final String sku;
  final String name;
  final int ledgerValueMinor;
  final int stockValueMinor;

  const InventoryReconciliationRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.ledgerValueMinor,
    required this.stockValueMinor,
  });

  int get driftMinor => ledgerValueMinor - stockValueMinor;

  bool get isMatched => driftMinor == 0;
}

/// تقرير المطابقة كاملاً — «متطابقة» تعني تطابق الثابت حرفاً على كل صنف
/// وعلى الإجمالي معاً (F-178)، وإلا فالميل ظاهر بالأرقام لا كلاماً.
class InventoryReconciliationReport {
  final List<InventoryReconciliationRow> rows;
  final int ledgerTotalMinor;
  final int stockTotalMinor;

  const InventoryReconciliationReport({
    required this.rows,
    required this.ledgerTotalMinor,
    required this.stockTotalMinor,
  });

  int get driftMinor => ledgerTotalMinor - stockTotalMinor;

  bool get isMatched => driftMinor == 0;
}

/// بناء المطابقة: الدمج بالصنف على الطرفين، والقيمة الدفترية مدينُه −
/// دائنُه (اتجاه 113 الطبيعي مدين — 03 §2)، والصفوف بترتيب الكود —
/// وبلا أي تدوير: القيم وحدات صغرى صحيحة كما خُزنت (D-067 فلا غبار).
InventoryReconciliationReport buildInventoryLedgerReconciliation(
  List<InventoryLedgerRawRow> ledgerRaws,
  List<InventoryStockRawRow> stockRaws,
) {
  final ledgerByItem = <int, InventoryLedgerRawRow>{
    for (final r in ledgerRaws) r.itemId: r,
  };
  final stockByItem = <int, InventoryStockRawRow>{
    for (final r in stockRaws) r.itemId: r,
  };
  final itemIds = <int>{...ledgerByItem.keys, ...stockByItem.keys};
  var ledgerTotal = 0;
  var stockTotal = 0;
  final rows = <InventoryReconciliationRow>[];
  for (final id in itemIds) {
    final ledger = ledgerByItem[id];
    final stock = stockByItem[id];
    final ledgerValue = ledger == null ? 0 : ledger.debitMinor - ledger.creditMinor;
    final stockValue = stock == null ? 0 : stock.valueMinor;
    ledgerTotal += ledgerValue;
    stockTotal += stockValue;
    rows.add(InventoryReconciliationRow(
      itemId: id,
      sku: (ledger?.sku ?? stock?.sku)!,
      name: (ledger?.name ?? stock?.name)!,
      ledgerValueMinor: ledgerValue,
      stockValueMinor: stockValue,
    ));
  }
  rows.sort((a, b) => a.sku.compareTo(b.sku));
  return InventoryReconciliationReport(
    rows: rows,
    ledgerTotalMinor: ledgerTotal,
    stockTotalMinor: stockTotal,
  );
}
