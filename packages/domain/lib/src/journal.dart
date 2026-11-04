/// قلب الدفتر في دِقَّة — دفعة م1 الثالثة، المنطق النقي حصراً بلا Flutter
/// ولا Drift (F-010، 07 §1.8).
///
/// المرجع الحاكم الموثق (README-v2.01 §3):
/// - 07 §1.1: كل حدث مالي قيد متوازن عبر محرك ترحيل واحد — ولا مسار يعدل
///   الأرصدة خارج المحرك («أي كود يريد تغيير رصيد فهو لا يعدل رصيداً بل
///   يمرر حداً للمحرك»).
/// - 07 §1.2/§1.3: آلة حالات صريحة (مسودة ← مرحّل) بانتقال محروس، وما
///   رُحّل لا يعدل ولا يُحذف أبداً — التصحيح بقيد عكس جديد يحمل مرجع الأصل.
/// - 07 §2.2: التوازن يفرض مرتين — بالمحرك هنا، وبمشغِّلات SQLite في
///   التخزين (نمط D-067: القيد يُنشأ مسودة فلا يُفحص التوازن إدراجاً
///   إدراجاً، وعند الانتقال إلى «مرحّل» يفحصه المُشغِّل).
/// - 07 §1.6 + وثيقة 03: الدليل إعداد لا كود — البيانات أدناه حرفية من
///   03 §3 كما اعتمدها المالك (م-10/m-11/م-13/م-15)، ويعاد ترقيمها أو
///   تسميتها من الشاشة دون أن تتأثر التقارير المبنية من أنواع الحسابات.
/// - 07 §1.9 (D-071): الترقيم متصل داخل الجهاز بلا إعادة استخدام، والعرض
///   باسم النوع الكامل بلا بادئات مختصرة (م-44): «قيد عام 26000001»
///   بالصيغة الجديدة D-169 (والصادرة قبلها «2026/000001» بيانات).
/// - 05 §2/§7: المبالغ وحدات صغرى صحيحة، ولا حذف فيزيائي لقيود المرحّل،
///   وأي تعديل حقول محاسبية على مسودة يوثَّق في سجل الأحداث.
///
/// سيناريوهات الدفعة س-42..س-50 (06 §1-د): مقترحة وبُنيت عليها حصراً —
/// بانتظار اعتماد المالك أو تعديلها (عرف دفعة الأصناف: الصدق أولاً).

/// جانب السطر القيدي.
enum NormalSide { debit, credit }

/// أنواع الحسابات الخمسة واتجاهها الطبيعي (03 §2) — التقارير من النوع لا
/// من الاسم أو الكود (07 §1.6).
enum AccountType {
  asset('أصول'),
  liability('خصوم'),
  equity('حقوق ملكية'),
  income('إيرادات'),
  expense('مصروفات');

  final String label;
  const AccountType(this.label);

  /// الاتجاه الطبيعي للنوع (03 §2): الأصول والمصروفات مدينتها؛ وغيرها
  /// دائنها. الحساب العكسي يبعد عنه بمصطلح `normalSide` المستقل عن النوع.
  NormalSide get defaultNormalSide =>
      this == AccountType.asset || this == AccountType.expense
          ? NormalSide.debit
          : NormalSide.credit;
}

/// نوع الدفتر (05 §3.4): كل قيد يصدر عن دفتر من هذه.
enum JournalKind {
  sales('فاتورة بيع'),
  purchase('فاتورة شراء'),
  cash('دفتر نقدية'),
  stock('دفتر مخزون'),
  general('قيد عام');

  final String label;
  const JournalKind(this.label);
}

/// حالة القيد — آلة حالات صريحة (07 §1.2): مسودة ← مرحّل بلا رجوع.
enum MoveState { draft, posted }

/// مواصفة حساب في الدليل الافتراضي — بيانات إعداد تُزرع عند أول تثبيت
/// (03 §1: «الدليل إعداد لا كود»)، حرفاً من جدول 03 §3 المعتمد.
class AccountSpec {
  final String code;
  final String name;
  final AccountType type;

  /// الاتجاه الطبيعي للحساب — المعلن إذا اختلفت طبيعة الحساب عن نوعه
  /// (عكسية: 42 مدين، 32/321 مدين، 53 دائن)؛ والفراغ يرجع لاتجاه النوع.
  final NormalSide? normalSide;

  /// كود الأب — الجذر بلا أب. الاتجاه الهرمي من جدول 03 كما هو.
  final String? parentCode;

  /// الحساب الورقي وحده يقيد (03 §1-2)؛ الأب يعرض مجمّع أبنائه.
  final bool isLeaf;

  /// الجاهز معطّل يُفعَّل إعداداً عند حاجة قراره المؤجل (03 §1-5).
  final bool isActive;

  const AccountSpec({
    required this.code,
    required this.name,
    required this.type,
    this.normalSide,
    required this.parentCode,
    required this.isLeaf,
    this.isActive = true,
  });

  NormalSide get effectiveNormalSide => normalSide ?? type.defaultNormalSide;
}

/// الدليل الافتراضي الكامل — 58 حساباً حرفاً من 03 §3 (م-10 الأكواد
/// والأسماء كما هي، م-11 تكفي 54x، م-13 زيادة الجرد على 43، م-15/D-040
/// التوسيع من اليوم الأول؛ والجاهز معطّل: 121/213/214/44/52/55).
const List<AccountSpec> defaultChartOfAccounts = [
  AccountSpec(code: '1', name: 'الأصول', type: AccountType.asset, parentCode: null, isLeaf: false),
  AccountSpec(code: '11', name: 'الأصول المتداولة', type: AccountType.asset, parentCode: '1', isLeaf: false),
  AccountSpec(code: '111', name: 'الصناديق النقدية', type: AccountType.asset, parentCode: '11', isLeaf: false),
  AccountSpec(code: '1111', name: 'الصندوق الرئيسي', type: AccountType.asset, parentCode: '111', isLeaf: true),
  AccountSpec(code: '112', name: 'العملاء (ذمم مدينة)', type: AccountType.asset, parentCode: '11', isLeaf: true),
  AccountSpec(code: '113', name: 'المخزون', type: AccountType.asset, parentCode: '11', isLeaf: true),
  AccountSpec(code: '114', name: 'ذمم مدينة أخرى', type: AccountType.asset, parentCode: '11', isLeaf: true),
  AccountSpec(code: '115', name: 'مصروفات مدفوعة مقدماً', type: AccountType.asset, parentCode: '11', isLeaf: true),
  AccountSpec(code: '12', name: 'الأصول غير المتداولة', type: AccountType.asset, parentCode: '1', isLeaf: false),
  AccountSpec(
      code: '121',
      name: 'الأصول الثابتة',
      type: AccountType.asset,
      parentCode: '12',
      isLeaf: true,
      isActive: false),
  AccountSpec(code: '2', name: 'الخصوم', type: AccountType.liability, parentCode: null, isLeaf: false),
  AccountSpec(code: '21', name: 'الخصوم المتداولة', type: AccountType.liability, parentCode: '2', isLeaf: false),
  AccountSpec(code: '211', name: 'الموردون (ذمم دائنة)', type: AccountType.liability, parentCode: '21', isLeaf: true),
  AccountSpec(code: '212', name: 'التزامات أخرى', type: AccountType.liability, parentCode: '21', isLeaf: true),
  AccountSpec(
      code: '213',
      name: 'مصروفات مستحقة',
      type: AccountType.liability,
      parentCode: '21',
      isLeaf: true,
      isActive: false),
  AccountSpec(
      code: '214',
      name: 'قروض قصيرة الأجل',
      type: AccountType.liability,
      parentCode: '21',
      isLeaf: true,
      isActive: false),
  AccountSpec(code: '3', name: 'حقوق الملكية', type: AccountType.equity, parentCode: null, isLeaf: false),
  AccountSpec(code: '31', name: 'رأس المال', type: AccountType.equity, parentCode: '3', isLeaf: false),
  AccountSpec(code: '311', name: 'رأس المال', type: AccountType.equity, parentCode: '31', isLeaf: true),
  AccountSpec(code: '32', name: 'المسحوبات', type: AccountType.equity, normalSide: NormalSide.debit, parentCode: '3', isLeaf: false),
  AccountSpec(code: '321', name: 'المسحوبات الشخصية', type: AccountType.equity, normalSide: NormalSide.debit, parentCode: '32', isLeaf: true),
  AccountSpec(code: '33', name: 'النتيجة', type: AccountType.equity, parentCode: '3', isLeaf: false),
  AccountSpec(code: '331', name: 'الأرباح المحتجزة', type: AccountType.equity, parentCode: '33', isLeaf: true),
  AccountSpec(
      code: '332',
      name: 'جاري النتيجة (الافتتاح والإقفال)',
      type: AccountType.equity,
      parentCode: '33',
      isLeaf: true),
  AccountSpec(code: '4', name: 'الإيرادات', type: AccountType.income, parentCode: null, isLeaf: false),
  AccountSpec(code: '41', name: 'إيرادات النشاط', type: AccountType.income, parentCode: '4', isLeaf: false),
  AccountSpec(code: '411', name: 'مبيعات البضائع', type: AccountType.income, parentCode: '41', isLeaf: true),
  AccountSpec(code: '412', name: 'إيرادات الخدمات', type: AccountType.income, parentCode: '41', isLeaf: true),
  AccountSpec(
      code: '42',
      name: 'مردودات ومسموحات المبيعات',
      type: AccountType.income,
      normalSide: NormalSide.debit,
      parentCode: '4',
      isLeaf: true),
  AccountSpec(code: '43', name: 'إيرادات أخرى', type: AccountType.income, parentCode: '4', isLeaf: true),
  AccountSpec(
      code: '44',
      name: 'أرباح فروق العملة',
      type: AccountType.income,
      parentCode: '4',
      isLeaf: true,
      isActive: false),
  AccountSpec(code: '5', name: 'المصروفات', type: AccountType.expense, parentCode: null, isLeaf: false),
  AccountSpec(code: '51', name: 'تكلفة المبيعات', type: AccountType.expense, parentCode: '5', isLeaf: true),
  AccountSpec(
      code: '52',
      name: 'محجوز — آلية تكلفة مستقبلية',
      type: AccountType.expense,
      parentCode: '5',
      isLeaf: true,
      isActive: false),
  AccountSpec(
      code: '53',
      name: 'مردودات المشتريات ومسموحاتها',
      type: AccountType.expense,
      normalSide: NormalSide.credit,
      parentCode: '5',
      isLeaf: true),
  AccountSpec(code: '54', name: 'مصروفات تشغيلية', type: AccountType.expense, parentCode: '5', isLeaf: false),
  AccountSpec(code: '541', name: 'الرواتب والأجور', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '542', name: 'الإيجارات', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '543', name: 'الكهرباء والطاقة', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '544', name: 'الاتصالات والإنترنت', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '545', name: 'النقل والشحن', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '546', name: 'الصيانة والإصلاح', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '547', name: 'عمولات وحوالات', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '548', name: 'مصروفات إدارية أخرى', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(code: '549', name: 'الرسوم والرخص الحكومية', type: AccountType.expense, parentCode: '54', isLeaf: true),
  AccountSpec(
      code: '55',
      name: 'خسائر فروق العملة',
      type: AccountType.expense,
      parentCode: '5',
      isLeaf: true,
      isActive: false),
  AccountSpec(code: '56', name: 'عجز الجرد', type: AccountType.expense, parentCode: '5', isLeaf: true),
  AccountSpec(code: '57', name: 'فروق الصناديق', type: AccountType.expense, parentCode: '5', isLeaf: true),
  AccountSpec(code: '58', name: 'فروق التكلفة', type: AccountType.expense, parentCode: '5', isLeaf: true),
  AccountSpec(code: '59', name: 'أقسام المصروفات الموسعة', type: AccountType.expense, parentCode: '5', isLeaf: false),
  AccountSpec(code: '591', name: 'التسويق والإعلان', type: AccountType.expense, parentCode: '59', isLeaf: true),
  AccountSpec(code: '592', name: 'التغليف والتعبئة', type: AccountType.expense, parentCode: '59', isLeaf: true),
  AccountSpec(code: '593', name: 'القرطاسية والمطبوعات', type: AccountType.expense, parentCode: '59', isLeaf: true),
  AccountSpec(code: '594', name: 'الضيافة والنظافة', type: AccountType.expense, parentCode: '59', isLeaf: true),
  AccountSpec(code: '595', name: 'الأتعاب المهنية والاستشارات', type: AccountType.expense, parentCode: '59', isLeaf: true),
  AccountSpec(code: '596', name: 'خسائر التلف والأضرار', type: AccountType.expense, parentCode: '59', isLeaf: true),
  AccountSpec(code: '597', name: 'مصاريف بنكية', type: AccountType.expense, parentCode: '59', isLeaf: true),
  AccountSpec(code: '598', name: 'مصروفات أخرى متنوعة', type: AccountType.expense, parentCode: '59', isLeaf: true),
];

/// مواصفة دفتر افتراضي — الدفاتر الخمسة (05 §3.4) تُزرع منذ اليوم الأول
/// بنيةً جاهزة؛ م1-نواة يستعمل `general` للقيود اليدوية وبقية الدفاتر
/// مع مستنداتها في دفعاتها (الفواتير دفعة 4، والصندوق دفعة 5).
class JournalSpec {
  final String code;
  final String name;
  final JournalKind kind;

  const JournalSpec({required this.code, required this.name, required this.kind});
}

const List<JournalSpec> defaultJournals = [
  JournalSpec(code: 'sales', name: 'دفتر المبيعات', kind: JournalKind.sales),
  JournalSpec(code: 'purchase', name: 'دفتر المشتريات', kind: JournalKind.purchase),
  JournalSpec(code: 'cash', name: 'دفتر النقدية', kind: JournalKind.cash),
  JournalSpec(code: 'stock', name: 'دفتر المخزون', kind: JournalKind.stock),
  JournalSpec(code: 'general', name: 'دفتر القيد العام', kind: JournalKind.general),
];

/// نوع التسلسل المركزي للقيود اليدوية (05 §5): لكل نوع مستند تسلسله
/// السنوي — والقيود اليدوية من دفتر القيد العام نوعها هذا حصراً؛ ترقيم
/// قيود الفواتير والسندات المولدة يحسم بدفعتها ويعرض (D-076 معروض).
const String ledgerMoveSequenceKind = 'move_general';

/// نوع تسلسل قيود المستندات المولدة — بدفتر جهتها (D-080 معروض):
/// قيود الفواتير والمردودات من دفاتر المبيعات/المشتريات بأنواعها، وأنواع
/// النقدية والمخزون بنية جاهزة لدفعة السندات (5) وتسويات المخزون (م2).
String moveSequenceKindForJournal(String journalKind) => switch (journalKind) {
      'sales' => 'move_sales',
      'purchase' => 'move_purchase',
      'cash' => 'move_cash',
      'stock' => 'move_stock',
      _ => ledgerMoveSequenceKind,
    };

/// الاسم الكامل لكل نوع تسلسل (م-44/D-071 — بلا بادئات مختصرة): يغذي
/// formatSequenceLabel للعرض «قيد مبيعات 26000001» و«فاتورة بيع
/// 26000001» بالصيغة الجديدة D-169. أنواع الفواتير الأربعة في
/// invoice.dart الدنيا.
const Map<String, String> sequenceKindLabels = {
  'move_general': 'قيد عام',
  'move_sales': 'قيد مبيعات',
  'move_purchase': 'قيد مشتريات',
  'move_cash': 'قيد نقدية',
  'move_stock': 'قيد مخزون',
  'invoice_sale': 'فاتورة بيع',
  'invoice_purchase': 'فاتورة شراء',
  'invoice_sale_return': 'مردود بيع',
  'invoice_purchase_return': 'مردود شراء',
  // دفعة السندات والصندوق (5) — أسماء النوع الكامل للعرض (م-44)
  'voucher_receipt': 'سند قبض',
  // D-105 (دفعة 8 س39): «سند دفع» حيث الإشارة إلى السند — بلفظ المالك
  // والقيمة التخزينية voucher_payment لا تتغير فلا ترحيل بيانات.
  'voucher_payment': 'سند دفع',
  'box_transfer': 'تحويل بين صناديق',
  'stock_transfer': 'تحويل بين مستودعات',
  'stock_count': 'جلسة جرد',
  'cash_adjustment': 'تسوية صندوق',
};

/// صورة حساب قائم للفهرسة والتحقق — بلا أي اعتماد تخزين أو واجهة.
class AccountInfo {
  final int id;
  final String code;
  final String name;
  final AccountType type;
  final NormalSide normalSide;
  final int? parentId;
  final bool isLeaf;
  final bool isActive;

  const AccountInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.normalSide,
    required this.parentId,
    required this.isLeaf,
    required this.isActive,
  });

  /// «الاسم (الكود)» — صيغة العرض المعتمدة على نمط الأطراف والأصناف.
  String get displayLabel => '$name ($code)';
}

/// فهرس الحسابات القائمة: بالمعرف وبالكود — أدوات المدقق.
class LedgerAccountIndex {
  final Map<int, AccountInfo> _byId;
  final Map<String, AccountInfo> _byCode;

  const LedgerAccountIndex._(this._byId, this._byCode);

  factory LedgerAccountIndex.build(Iterable<AccountInfo> accounts) {
    final byId = <int, AccountInfo>{};
    final byCode = <String, AccountInfo>{};
    for (final account in accounts) {
      byId[account.id] = account;
      byCode.putIfAbsent(account.code, () => account);
    }
    return LedgerAccountIndex._(byId, byCode);
  }

  AccountInfo? byId(int id) => _byId[id];

  AccountInfo? byCode(String code) => _byCode[code];

  /// الورقية النشطة حصراً — المرشحان لاختيار القيد (03 §1-2/§1-3) بترتيب
  /// الكود المعجمي (1، 11، 111، 1111 — فرز ISO الصحيح لأكواد الدليل).
  List<AccountInfo> leafActive() {
    final leaves =
        _byId.values.where((a) => a.isLeaf && a.isActive).toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    return leaves;
  }
}

/// فترة مالية حاضنة (05 §3.4/07 §1.5) — الصورة النقية لفحص الترحيل.
class PeriodInfo {
  final int id;
  final int fiscalYearId;
  final String startDateText;
  final String endDateText;
  final bool isOpen;

  const PeriodInfo({
    required this.id,
    required this.fiscalYearId,
    required this.startDateText,
    required this.endDateText,
    required this.isOpen,
  });

  bool contains(String dateText) =>
      dateText.compareTo(startDateText) >= 0 &&
      dateText.compareTo(endDateText) <= 0;
}

/// صيغة تواريخ العملية (D-077 معروض): نص ISO «YYYY-MM-DD» حصراً — فرزها
/// المعجمي زمني صحيح، والميلادي أساس التخزين والإدخال حصراً (F-167).
bool isValidIsoDate(String value) {
  if (value.length != 10 || value[4] != '-' || value[7] != '-') return false;
  for (var i = 0; i < 10; i++) {
    if (i == 4 || i == 7) continue;
    final c = value.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8, 10));
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

/// السنة الميلادية من تاريخ ISO — مفتاح التسلسل السنوي (07 §1.9).
int yearOfIsoDate(String value) => int.parse(value.substring(0, 4));

/// تاريخ اليوم بصيغة ISO المحلية للتعبئة الافتراضية (D-108، دفعة 8 س39
/// — س-111): «حقل التاريخ في الفواتير أو السندات أو التقارير يملأ
/// افتراضياً بتاريخ اليوم» — نقية بتاريخ الجهاز وقابلة للتعديل دائماً،
/// والمدقق يمنع التاريخ خارج الدورة المفتوحة كما هو.
String todayIsoDate({DateTime? now}) {
  final t = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// الفترة الحاضنة لتاريخ ما — أول فترة تقع ضمن حدودها (الفترات شطرها
/// غير متقاطع بحكم توليدها؛ الأول بترتيبها يفوز لو تكرر الإدخال).
PeriodInfo? findPeriodForDate(List<PeriodInfo> periods, String dateText) {
  for (final period in periods) {
    if (period.contains(dateText)) return period;
  }
  return null;
}

/// سطر قيد خام كما يخرج من نموذج الإدخال — المبالغ وحدات صغرى صحيحة
/// (07 §2.1) والسطر جهة واحدة (مدين أو دائن) لا الاثنان معاً.
class MoveLineDraft {
  final int accountId;

  /// طرف ذمم اختياري (05 §3.4: `party_id?` — حساب السيطرة 112/211 يحمل
  /// تفصيل الذمم، اصطلاح م-14).
  final int? partyId;

  final int debitMinor;
  final int creditMinor;

  /// بنية العملات الجاهزة (F-174) — تُملأ من قيود المستندات المولدة
  /// (الفواتير دفعة 4/D-082 معروض): عملة السطر ومبلغه بعملة المستند
  /// ولقطة السعر؛ القيود اليدوية تتركها فارغة (عملة الأساسية بلا لقطة
  /// كما هي سليم v6).
  final int? currencyId;
  final int? amountMinor;
  final int? fxRate;

  /// ربط سطر المخزون (113) بحركته (07 §3.1/م-27 مؤكد) — يُملأ من محرك
  /// الفواتير عند ترحيلها ولا يملؤه أي مسار يدوي.
  final int? refStockMoveId;

  const MoveLineDraft({
    required this.accountId,
    this.partyId,
    this.debitMinor = 0,
    this.creditMinor = 0,
    this.currencyId,
    this.amountMinor,
    this.fxRate,
    this.refStockMoveId,
  });
}

/// مسودة قيد خام — ما يُدقق قبل أي كتابة.
class MoveDraft {
  final int journalId;

  /// تاريخ العملية ISO «YYYY-MM-DD».
  final String dateText;

  /// الوصف اختياري — البطاقة تقترحه وترحّل حريته.
  final String? narration;

  /// مرجع المستند المولد للقيد (05 §3.4: `ref_doc_type/ref_doc_id`) —
  /// القيد اليدوي بلا مرجع، والقيد العكس يُحيل بقيد الأصل (07 §1.3).
  final String? refDocType;
  final int? refDocId;

  final List<MoveLineDraft> lines;

  const MoveDraft({
    required this.journalId,
    required this.dateText,
    this.narration,
    this.refDocType,
    this.refDocId,
    required this.lines,
  });
}

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة (نمط الأطراف
/// D-062..D-066): الواجهة وحدها تقرر الصياغة المعروضة، و[describeMoveValidationError]
/// تخدم الاختبارات وصفوف الفشل حصراً.
sealed class MoveValidationError {
  const MoveValidationError();
}

/// سطر على حساب غير موجود أو غير ورقي أو معطّل (03 §1-2/§1-3).
class MoveAccountNotLedgerable extends MoveValidationError {
  final int lineIndex;
  final String accountLabel;

  const MoveAccountNotLedgerable(this.lineIndex, this.accountLabel);
}

/// سطر بلا جانب — لا مدين ولا دائن.
class MoveLineEmptySide extends MoveValidationError {
  final int lineIndex;

  const MoveLineEmptySide(this.lineIndex);
}

/// سطر على الجانبين معاً — السطر جهة واحدة.
class MoveLineBothSides extends MoveValidationError {
  final int lineIndex;

  const MoveLineBothSides(this.lineIndex);
}

/// مبلغ سالب أو صفر في جانب من جانبي السطر — الصفر لا قيمة له بالسطر.
class MoveLineAmountInvalid extends MoveValidationError {
  final int lineIndex;

  const MoveLineAmountInvalid(this.lineIndex);
}

/// قيد بأسطر أقل من اثنين (05 §7-1).
class MoveTooFewLines extends MoveValidationError {
  const MoveTooFewLines();
}

/// قيد غير متوازن — يحمل الطرفين للعرض: «مجموع المدين 500 لا يساوي
/// مجموع الدائن 400».
class MoveUnbalanced extends MoveValidationError {
  final int debitTotalMinor;
  final int creditTotalMinor;

  const MoveUnbalanced(this.debitTotalMinor, this.creditTotalMinor);
}

/// تاريخ القيد ليس ISO «YYYY-MM-DD» صالحاً (D-077 الاصطلاح).
class MoveDateInvalid extends MoveValidationError {
  final String dateText;

  const MoveDateInvalid(this.dateText);
}

/// لا فترة حاضنة للتاريخ — فجوة زمنية خارج كل الفترات (07 §1.5).
class MoveNoPeriod extends MoveValidationError {
  final String dateText;

  const MoveNoPeriod(this.dateText);
}

/// الفترة الحاضنة مقفلة — الترحيل فيها مجمد (07 §1.5: لا ترحيل في فترة
/// مقفلة ولا تعديل في مستنداتها).
class MoveClosedPeriod extends MoveValidationError {
  final String dateText;

  const MoveClosedPeriod(this.dateText);
}

/// المدقق الأول: قواعد المسودة قبل الحفظ (س-43..س-45) — يعيد قائمة
/// الأخطاء (فارغة = سليم) بترتيب التسلسل التدريجي المعتمد: التاريخ ثم
/// الأسطر سطراً سطراً (الحساب ثم الجانب ثم المبلغ) ثم العدد ثم التوازن.
///
/// - الحساب يفحص بالمعرف: غير موجود أو غير ورقي أو معطّل رفض.
/// - [index] يبنى مرة ويشارك في الاستدعاءات المتتالية.
List<MoveValidationError> validateMoveDraft(
  MoveDraft draft, {
  required LedgerAccountIndex index,
}) {
  final errors = <MoveValidationError>[];
  if (!isValidIsoDate(draft.dateText)) {
    errors.add(MoveDateInvalid(draft.dateText));
  }
  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    final account = index.byId(line.accountId);
    if (account == null || !account.isLeaf || !account.isActive) {
      final label = account?.displayLabel ?? 'معرّف ${line.accountId}';
      errors.add(MoveAccountNotLedgerable(i, label));
      continue;
    }
    if (line.debitMinor < 0 || line.creditMinor < 0) {
      errors.add(MoveLineAmountInvalid(i));
      continue;
    }
    final debit = line.debitMinor;
    final credit = line.creditMinor;
    if (debit == 0 && credit == 0) {
      errors.add(MoveLineEmptySide(i));
    } else if (debit > 0 && credit > 0) {
      errors.add(MoveLineBothSides(i));
    }
  }
  if (draft.lines.length < 2) {
    errors.add(const MoveTooFewLines());
  }
  if (draft.lines.length >= 2 && errors.isEmpty) {
    var debitTotal = 0;
    var creditTotal = 0;
    for (final line in draft.lines) {
      debitTotal += line.debitMinor;
      creditTotal += line.creditMinor;
    }
    if (debitTotal != creditTotal) {
      errors.add(MoveUnbalanced(debitTotal, creditTotal));
    }
  }
  return errors;
}

/// المدقق الحاكم عند الترحيل: قواعد المسودة كاملة + الزمن المحاسبي
/// (07 §1.5) — التاريخ داخل فترة موجودة مفتوحة. القيد غير المسودة يرفض
/// من التخزين قبل وصوله هنا (آلة الحالة 07 §1.2).
List<MoveValidationError> validateMoveForPosting(
  MoveDraft draft, {
  required LedgerAccountIndex index,
  required List<PeriodInfo> periods,
}) {
  final errors = validateMoveDraft(draft, index: index);
  if (isValidIsoDate(draft.dateText)) {
    final period = findPeriodForDate(periods, draft.dateText);
    if (period == null) {
      errors.add(MoveNoPeriod(draft.dateText));
    } else if (!period.isOpen) {
      errors.add(MoveClosedPeriod(draft.dateText));
    }
  }
  return errors;
}

/// الوصف العربي لأخطاء التحقق — يخدم الاختبارات ورسائل الفشل في جولة
/// التنفيذ حصراً؛ الواجهة حرية صياغتها (نمط س-36: رسالة واحدة أول خطأ).
String describeMoveValidationError(MoveValidationError error) {
  switch (error) {
    case MoveAccountNotLedgerable(:final lineIndex, :final accountLabel):
      return 'السطر ${lineIndex + 1}: «$accountLabel» ليس حساباً ورقياً '
          'مفعّلاً — القيد على الحسابات الطرفية وحدها (03 §1-2)';
    case MoveLineEmptySide(:final lineIndex):
      return 'السطر ${lineIndex + 1}: بلا جانب — أدخل المبلغ مديناً أو دائناً';
    case MoveLineBothSides(:final lineIndex):
      return 'السطر ${lineIndex + 1}: على الجانبين معاً — السطر جهة واحدة';
    case MoveLineAmountInvalid(:final lineIndex):
      return 'السطر ${lineIndex + 1}: المبلغ صفر أو سالب';
    case MoveTooFewLines():
      return 'القيد بسطر واحد — قيدان فأكثر (05 §7-1)';
    case MoveUnbalanced(
        :final debitTotalMinor,
        :final creditTotalMinor
      ):
      return 'قيد غير متوازن: مجموع المدين $debitTotalMinor لا يساوي '
          'مجموع الدائن $creditTotalMinor';
    case MoveDateInvalid(:final dateText):
      return 'التاريخ «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)';
    case MoveNoPeriod(:final dateText):
      return 'التاريخ «$dateText» خارج كل الفترات المالية المفتوحة';
    case MoveClosedPeriod(:final dateText):
      return 'فترة التاريخ «$dateText» مقفلة — لا ترحيل فيها (07 §1.5)';
  }
}

/// صورة سطر مرحّل للقراءة والحساب — بلا اعتماد تخزين.
class LedgerLine {
  final int moveId;
  final int accountId;
  final int debitMinor;
  final int creditMinor;

  const LedgerLine({
    required this.moveId,
    required this.accountId,
    required this.debitMinor,
    required this.creditMinor,
  });
}

/// بناء مسودة قيد عكس لقيد مرحّل (07 §1.3): الأسطر نفسها بجانبين
/// متقابلين، والوصف الافتراضي «عكس قيد ...» ومرجع الأصل محفوظ —
/// تُنشأ مسودةً وترحّل عبر المحرك نفسه (س-48) فلا مسار خاص بلا فحص.
MoveDraft buildReversalMoveDraft({
  required int journalId,
  required List<LedgerLine> originalLines,
  required String originalLabel,
  required String reversalDateText,
  required int originalMoveId,
  String? narration,
}) {
  final lines = originalLines
      .map((line) => MoveLineDraft(
            accountId: line.accountId,
            partyId: null,
            debitMinor: line.creditMinor,
            creditMinor: line.debitMinor,
          ))
      .toList();
  return MoveDraft(
    journalId: journalId,
    dateText: reversalDateText,
    narration: narration ?? 'عكس قيد $originalLabel',
    refDocType: 'move',
    refDocId: originalMoveId,
    lines: lines,
  );
}

/// رصيد حساب ورقي بالاتجاه الطبيعي من أسطر قيود مرحّلة (س-50): موجب على
/// جانبه الطبيعي، والسالب رصيد عكسي مشروع (قاعدة 03 §1-4: الحسابات
/// العكسية طبيعتها معاكسة لنوعها).
int computeAccountBalance(
  Iterable<LedgerLine> lines,
  AccountInfo account,
) {
  var debit = 0;
  var credit = 0;
  for (final line in lines) {
    if (line.accountId != account.id) continue;
    debit += line.debitMinor;
    credit += line.creditMinor;
  }
  return account.normalSide == NormalSide.debit ? debit - credit : credit - debit;
}

/// مجاميع ميزان المراجعة الافتراضي: مجموع المدين ومجموع الدائن للمرحّل
/// كله — توازنه بالبناء مستحيل الخرق إلا عبر الحاجزين (07 §2.2)؛ فحصه
/// في الاختبار (س-50) وفي ثوابت الفحص الآلي عند الفتح (07 §1.10).
(int debitTotalMinor, int creditTotalMinor) trialBalanceTotals(
  Iterable<LedgerLine> lines,
) {
  var debit = 0;
  var credit = 0;
  for (final line in lines) {
    debit += line.debitMinor;
    credit += line.creditMinor;
  }
  return (debit, credit);
}

/// الرقم التالي في تسلسل مركزي (07 §1.9): الرقم المُصدَر لا يُعاد أبداً —
/// الآلية تصدّر عند الترحيل حصراً فلا يُلمس العدّاد بلا قيد يُرحّل.
int nextSequenceNumber(int lastNumber) => lastNumber + 1;

// ── صيغة الترقيم (D-169 — س56 بلفظ المالك) ──────────────────────────
// «سنة برقمين فالعدّاد مبطناً بلا فاصل»: 2026 بعرض 6 = «26000001»،
// وبعرض 5 = «2600001» (مثال المالك نفسه). عرض العدّاد بعد السنة
// خانة إعداد يحددها المالك من الإعدادات (3..8 خانات) وتُخزَّن app_meta.

/// عرض العدّاد الافتراضي بعد السنة (D-169): ست خانات كسعة الصيغة
/// السابقة نفسها (حتى 999,999 وثيقة في السنة) — وهو ما يعود عند غياب
/// الإعداد أو تلفه (القاعدة الموثقة: التالف كالغياب بلا سحر).
const int kDefaultCounterWidth = 6;

/// أدنى عرض عدّاد مسموح للمالك (D-169).
const int kCounterWidthMin = 3;

/// أعلى عرض عدّاد مسموح للمالك (D-169).
const int kCounterWidthMax = 8;

/// هل عرض العدّاد ضمن النطاق المعتمد (D-169)؟
bool isValidCounterWidth(int width) =>
    width >= kCounterWidthMin && width <= kCounterWidthMax;

/// نص رقم المستند المُصدَر عند الترحيل (07 §1.9 — الصيغة الجديدة D-169):
/// السنة برقمين فالعدّاد مبطناً بأصفار بعرض [counterWidth] **بلا فاصل**.
/// الرقم الصافي أرقاماً يسقط مشاكل الحدود كلها دفعة واحدة: لا فاصل مسار
/// في أسماء الملفات (علّة المشاركة الحية س-154/D-152 من جذرها) ولا روابط
/// ولا حقن Excel ولا التباس تواريخ — وهو عرف الترقيم العددي الصريح.
/// الفيض موثق سلفاً: إن تجاوز العدّادُ العرضَ طال الرقم ولا يلتف أبداً
/// فلا رقم يُعاد (F-053/F-054) — وفرز المطابقات بالسنة والعدّاد
/// المستخلصَين لا بالنص الخام (D-169 — قاعدة 02 §8 باقية بمعناها).
/// والقيمة الخارجة عن النطاق تعامل كالغياب فتعود الافتراضية — نفس قاعدة
/// قارئ الإعداد في التخزين. **الأرقام الصادرة قبل D-169 بصيغة
/// «2026/000001» بيانات أعمال لا تُمسّ** — هذه الدالة للتوليد حصراً،
/// فالعرض يبني تسميته من الرقم المخزن كما هو.
String formatDocumentNumber(int year, int number,
    {int counterWidth = kDefaultCounterWidth}) {
  assert(counterWidth > 0, 'عرض العدّاد موجب');
  final width = isValidCounterWidth(counterWidth)
      ? counterWidth
      : kDefaultCounterWidth;
  final yy = (year % 100).toString().padLeft(2, '0');
  return '$yy${number.toString().padLeft(width, '0')}';
}

/// الصيغة المعروضة للرقم (م-44/D-071 — الاسم الكامل بلا بادئة مختصرة)
/// بصيغة D-169: «قيد عام 26000001».
String formatSequenceLabel(String kindLabel, int year, int number,
        {int counterWidth = kDefaultCounterWidth}) =>
    '$kindLabel ${formatDocumentNumber(year, number, counterWidth: counterWidth)}';
