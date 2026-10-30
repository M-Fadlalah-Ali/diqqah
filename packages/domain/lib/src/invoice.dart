import 'journal.dart';

/// الفواتير والمردودات في دِقَّة — دفعة م1 الرابعة، منطق نقي حصراً بلا
/// Flutter ولا Drift (F-010، 07 §1.8) — المستهلك الأول لمحرك قلب الدفتر.
///
/// المرجع الحاكم الموثق (README-v2.01 §3 وسيناريوهات 06 المعتمدة):
/// - س-03/س-04 (شراء) وس-06/س-07/س-08 (بيع): النقدي يطلب صندوقاً والآجل
///   يطلب طرفاً؛ الشراء النقدي بمورد اختياري؛ بيع الخدمة بلا مخزون ولا
///   تكلفة؛ ومنع السالب (مخزون وصندوق) يفحص قبل الحفظ وقبل الترحيل.
/// - س-05 (مردود شراء): مرجع الأصل إلزاماً؛ الخروج بالقيمة الدفترية
///   الجارية (المتوسط المرجح الموحد — D-067) والفرق عن ذمة المورد على
///   58 فروق التكلفة (03 §3).
/// - س-11 + تثبيت م-25 (مردود بيع): مرجع الأصل إلزاماً؛ دخول المخزون
///   بلقطة تكلفة خروج الأصل المخزنة في حركته، وأي فرق بينها وبين المتوسط
///   الجاري وقت المردود يقيد على 58.
/// - F-047/D-067: مصدر الترصيد القيمة الإجمالية (`total_value`) وكلفة
///   الوحدة مشتقة للعرض حصراً؛ تكلفة الخروج `round(total_value × qty_out /
///   qty_on_hand)` بالنصف بعيداً عن الصفر، والخروج بكل الكمية يمتص القيمة
///   كلها فلا غبار تقريب.
/// - F-122/D-070/D-082 (معروض): مستند بعملة غير الأساسية يخزن المبلغ
///   والعملة ولقطة السعر والمكافئ بالأساسية؛ اللقطة عدد صحيح مكبَّر بمقياس
///   10^6 للوحدة الصغرى الأساسية لكل وحدة صغرى من عملة المستند، والعملة
///   الأساسية تُخزن لقطتها 1,000,000 دائماً، والتحويل `round(doc × fx /
///   10^6)` بالنصف بعيداً عن الصفر (س7).
/// - س-60 (D-080 معروض): الفاتورة رقمها من تسلسل نوعها السنوي، وقيدُها
///   من تسلسل دفتر جهتها — بلا إعادة استخدام (07 §1.9).
///
/// سيناريوهات الدفعة س-51..س-60 (06 §1-ه): مقترحة من المستشار وبُنيت
/// دفعة الكود عليها بأمر المالك «اعتمد وانتقل إلى التالي» (س32،
/// 2026-10-30) — بانتظار اعتماد المالك أو تعديلها (عرف الدفعات:
/// الصدق أولاً).

/// نوع الفاتورة (05 §4.1) — وعرضه باسمه الكامل العربي (م-44 نفسه).
enum InvoiceKind {
  sale('sale', 'فاتورة بيع'),
  purchase('purchase', 'فاتورة شراء'),
  saleReturn('sale_return', 'مردود بيع'),
  purchaseReturn('purchase_return', 'مردود شراء');

  final String storageValue;
  final String label;

  const InvoiceKind(this.storageValue, this.label);

  static InvoiceKind fromStorage(String value) {
    for (final k in InvoiceKind.values) {
      if (k.storageValue == value) return k;
    }
    throw ArgumentError('نوع فاتورة غير معروف: $value');
  }

  /// مردودان يرجعان لأصل بيع، ومردودان لأصل شراء (س-05/س-11).
  bool get isSalesSide =>
      this == InvoiceKind.sale || this == InvoiceKind.saleReturn;

  /// هل هذا النوع مردوداً بمرجع أصل إلزاماً؟ (س-05/س-11).
  bool get isReturn =>
      this == InvoiceKind.saleReturn || this == InvoiceKind.purchaseReturn;
}

/// حالة الفاتورة (05 §4.1): مسودة ← مرحّلة، والنقدية «مدفوعة» فور
/// ترحيلها (س-03/س-06)؛ و«جزئية» تُشتق آلياً بالسندات دفعة (5) — لا ضبط
/// يدوي أبداً (F-063).
enum InvoiceState {
  draft('draft', 'مسودة'),
  posted('posted', 'مرحّلة'),
  paid('paid', 'مدفوعة'),
  partiallyPaid('partially_paid', 'جزئية');

  final String storageValue;
  final String label;

  const InvoiceState(this.storageValue, this.label);

  static InvoiceState fromStorage(String value) {
    for (final s in InvoiceState.values) {
      if (s.storageValue == value) return s;
    }
    throw ArgumentError('حالة فاتورة غير معروفة: $value');
  }

  bool get isCommitted => this == posted || this == paid || this == partiallyPaid;
}

/// مفتاح التسلسل السنوي لترقيم الفواتير (05 §5/D-080 معروض): لكل نوع
/// فاتورة تسلسله — والاسم الكامل في sequenceKindLabels (journal.dart).
String invoiceSequenceKind(InvoiceKind kind) => switch (kind) {
      InvoiceKind.sale => 'invoice_sale',
      InvoiceKind.purchase => 'invoice_purchase',
      InvoiceKind.saleReturn => 'invoice_sale_return',
      InvoiceKind.purchaseReturn => 'invoice_purchase_return',
    };

/// مقياس اللقطة الصرفية المكبَّرة (D-082 معروض): fx_rate يمثل «كم وحدة
/// صغرى من العملة الأساسية مقابل وحدة صغرى واحدة من عملة المستند»
/// مضروباً في 10^6. عملة الأساسية لقطتها 1,000,000 دائماً (تحويل محايد).
const int fxRateScale = 1000000;

/// لقطة عملة الأساسية — تحويل محايد تخزيناً لا حساباً (D-082 معروض).
const int baseCurrencyFxRate = fxRateScale;

/// التقريب لأقرب وحدة صغرى والنصف بعيداً عن الصفر (س7) — بسط ومقام
/// موجبان حصراً (المبالغ والكميات لا تتسالب في هذا المجال).
int roundHalfAwayFromZeroRatio(int numerator, int denominator) {
  assert(numerator >= 0, 'البسط غير سالب في قواعد س7');
  assert(denominator > 0, 'المقام موجب في قواعد س7');
  return (2 * numerator + denominator) ~/ (2 * denominator);
}

/// المكافئ بالوحدة الصغرى الأساسية لمبلغ بوحدة صغرى من عملة المستند
/// (F-122/D-082): `round(doc_minor × fx_rate / 10^6)` بالنصف بعيداً عن
/// الصفر. لقطة الأساسية (1,000,000) تعيد المبلغ نفسه.
int convertToBaseMinor(int docMinor, int fxRate) {
  assert(docMinor >= 0, 'مبلغ المستند غير سالب (س6)');
  assert(fxRate > 0, 'لقطة السعر موجبة (D-082)');
  return roundHalfAwayFromZeroRatio(docMinor * fxRate, fxRateScale);
}

/// تكلفة الخروج بالقيمة الإجمالية (F-047/D-067): `round(total_value ×
/// qty_out / qty_on_hand)` بالنصف بعيداً عن الصفر؛ والخروج بكل الكمية
/// يمتص القيمة كلها؛ وعلى مخزون فارغ (كمية صفر) لا قيمة تُخرج — صفر
/// كامل والفرق يقيَّد على 58 في مواضعه (س-56).
int wacExitValue(int totalValue, int onHand, int qtyOut) {
  assert(qtyOut >= 0, 'كمية الخروج غير سالبة');
  assert(totalValue >= 0, 'قيمة المخزون غير سالبة');
  if (qtyOut == 0) return 0;
  if (onHand <= 0) return 0;
  if (qtyOut >= onHand) return totalValue;
  return roundHalfAwayFromZeroRatio(totalValue * qtyOut, onHand);
}

/// نص رقم مستند بصيغة السنة المبطنة (07 §1.9 نفسها): «2026/000001».
String formatDocumentNumber(int year, int number) =>
    '$year/${number.toString().padLeft(6, '0')}';

/// سطر فاتورة خام كما يخرج من نموذج الإدخال (05 §4.1).
///
/// - م1 الإدخال بالوحدة الأساسية حصراً (09 §2): [unitId] وحدة أساسية
///   الصنف و[qtyBase] كمية بها — و`factor_at_entry` عمود بنية لم2 يُخزن
///   1 (05 §3.2).
/// - [unitPriceMinor] و[discountMinor] بوحدة صغرى من عملة المستند (س7)،
///   و[qtyBase] عدد صحيح بالوحدة الأساسية (غرام لا كيلو — 07 §2.1).
class InvoiceLineDraft {
  final int itemId;
  final int unitId;
  final int qtyBase;
  final int unitPriceMinor;
  final int discountMinor;

  /// بنية معطلة في م1 — صفر دائماً (05: tax_rate افتراضياً 0).
  final int taxRate;

  const InvoiceLineDraft({
    required this.itemId,
    required this.unitId,
    required this.qtyBase,
    this.unitPriceMinor = 0,
    this.discountMinor = 0,
    this.taxRate = 0,
  });

  /// قيمة السطر قبل خصم الفاتورة الكلي بوحدة صغرى من عملة المستند.
  int get grossDocMinor => qtyBase * unitPriceMinor - discountMinor;
}

/// مسودة فاتورة خام — ما يُدقق قبل أي كتابة (نمط القيود: MoveDraft).
class InvoiceDraft {
  final InvoiceKind kind;

  /// تاريخ العملية ISO «YYYY-MM-DD» (D-077 المعتمد).
  final String dateText;

  /// الاستحقاق اختياري (05: due_date?) — يغذي أعمار الذمم (F-065).
  final String? dueDateText;

  /// الطرف للآجل إلزاماً واختياري للنقدي (س-03: شراء نقدي من غير طرف
  /// مسجل ممكن) — وحساب السيطرة 112/211 يحمله في سطر القيد (م-14).
  final int? partyId;

  /// صندوق النقدي — وجوده هو تعريف النقدية (س-03/س-06: «نقدي يطلب
  /// صندوقاً») وغيابه مع وجود الطرف آجل (س-07: «آجل بلا صندوق»).
  final int? cashBoxId;

  /// مستودع البضاعة — المستودع الواحد في م1 (05 §3.3).
  final int? warehouseId;

  /// عملة المستند — 1 الأساسية (اصطلاح D-066/D-017) و2 الدولار (D-070).
  final int currencyId;

  /// لقطة السعر لحظة العملية (F-122/D-082) — الأساسية 1,000,000 دائماً.
  final int fxRate;

  /// خصم الفاتورة الكلي نسبةً 0..100 (س-06/س7): نسبة على المسودة تُترجم
  /// مبلغاً ويُقيَّد صافياً بلا حساب مستقل ولا يمس كلفة المخزون (05 §4.1).
  final int discountRate;

  /// مرجع الفاتورة الأصلية — للمردودين إلزاماً (س-05/س-11/F-056).
  final int? originalInvoiceId;

  /// سبب المردود نصي اختياري (س-05) والوصف اختياري لبقية الأنواع.
  final String? narration;

  final List<InvoiceLineDraft> lines;

  const InvoiceDraft({
    required this.kind,
    required this.dateText,
    this.dueDateText,
    this.partyId,
    this.cashBoxId,
    this.warehouseId,
    this.currencyId = 1,
    this.fxRate = baseCurrencyFxRate,
    this.discountRate = 0,
    this.originalInvoiceId,
    this.narration,
    required this.lines,
  });

  /// النقدية معرَّفة بوجود الصندوق (س-03/س-06) — لا حقل نوع دفع مستقل:
  /// «نقدي يطلب صندوقاً والآجل يطلب طرفاً» والاستدلال من الحقلين أوضح
  /// من تعداد ثالث قد يخالفهما.
  bool get isCash => cashBoxId != null;
}

/// حصيلة حساب مجاميع فاتورة (05 §4.1 «totals»):
///
/// - [subtotalDocMinor]: مجموع قيم الأسطر قبل خصم الفاتورة.
/// - [discountDocMinor]: ترجمة نسبة الخصم مبلغاً — بالنصف بعيداً عن
///   الصفر (س7).
/// - [totalDocMinor]: الصافي بوحدة صغرى من عملة المستند.
/// - [totalBaseMinor]: الصافي بوحدة الصغرى الأساسية (F-122).
/// - [lines]: لكل سطر صافيه بعد نصيبه من خصم الفاتورة (doc) ومكافؤه
///   الأساسي (base) — **التوزيع نسبي والسطر الأخير يمتص فارق التقريب**
///   (درس D-067: لا غبار تقريب — مجموع الأسطر يساوي الإجمالي حرفاً
///   فيتوازن القيد من البنية).
class InvoiceLineResult {
  final InvoiceLineDraft line;
  final int netDocMinor;
  final int baseMinor;

  const InvoiceLineResult({
    required this.line,
    required this.netDocMinor,
    required this.baseMinor,
  });
}

class InvoiceTotals {
  final List<InvoiceLineResult> lines;
  final int subtotalDocMinor;
  final int discountDocMinor;
  final int totalDocMinor;
  final int totalBaseMinor;

  const InvoiceTotals({
    required this.lines,
    required this.subtotalDocMinor,
    required this.discountDocMinor,
    required this.totalDocMinor,
    required this.totalBaseMinor,
  });
}

/// حساب مجاميع مسودة فاتورة — دالة نقية يعيد استخدامها محرك الترحيل
/// وبطاقة الإدخال (المعروض مطابق المؤزر حصراً).
///
/// تشترط مسودة سليمة البنية (كميات وأسعار وخصومات مررت بالمدقق) —
/// وتحصّن داخلياً: مقيام صفر لا يقسم (فاتورة صافيها صفر مرفوضة أصلاً
/// بالمدقق InvoiceZeroTotal).
InvoiceTotals computeInvoiceTotals(InvoiceDraft draft) {
  final gross = <int>[
    for (final l in draft.lines) l.qtyBase * l.unitPriceMinor - l.discountMinor,
  ];
  var subtotal = 0;
  for (final g in gross) {
    subtotal += g;
  }
  final discount = roundHalfAwayFromZeroRatio(subtotal * draft.discountRate, 100);
  final totalDoc = subtotal - discount;
  final totalBase = convertToBaseMinor(totalDoc, draft.fxRate);

  final results = <InvoiceLineResult>[];
  var discountGiven = 0;
  var baseGiven = 0;
  for (var i = 0; i < draft.lines.length; i++) {
    final last = i == draft.lines.length - 1;
    final int shareDoc;
    final int shareBase;
    if (last) {
      // السطر الأخير يمتص فارق التقريب (D-067) فتستوي المجاميع حرفاً.
      shareDoc = discount - discountGiven;
      shareBase = totalBase - baseGiven;
    } else {
      shareDoc = subtotal == 0
          ? 0
          : roundHalfAwayFromZeroRatio(gross[i] * discount, subtotal);
      shareBase = totalDoc == 0
          ? 0
          : roundHalfAwayFromZeroRatio(gross[i] * totalBase, totalDoc);
    }
    discountGiven += shareDoc;
    baseGiven += shareBase;
    results.add(InvoiceLineResult(
      line: draft.lines[i],
      netDocMinor: gross[i] - shareDoc,
      baseMinor: shareBase,
    ));
  }
  return InvoiceTotals(
    lines: results,
    subtotalDocMinor: subtotal,
    discountDocMinor: discount,
    totalDocMinor: totalDoc,
    totalBaseMinor: totalBase,
  );
}

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة (نمط الأطراف
/// والقيود): الواجهة وحدها تقرر الصياغة المعروضة، و
/// [describeInvoiceValidationError] تخدم الاختبارات وصفوف الفشل حصراً.
sealed class InvoiceValidationError {
  const InvoiceValidationError();
}

/// تاريخ ليس ISO «YYYY-MM-DD» صالحاً (D-077 المعتمد).
class InvoiceDateInvalid extends InvoiceValidationError {
  final String dateText;

  const InvoiceDateInvalid(this.dateText);
}

/// مردود بلا مرجع أصل — المرجع إلزاماً (س-05/س-11/F-056).
class InvoiceOriginalRequired extends InvoiceValidationError {
  const InvoiceOriginalRequired();
}

/// لا صندوق ولا طرف — «نقدي يطلب صندوقاً والآجل يطلب طرفاً»
/// (س-03/س-06/س-07/F-050).
class InvoiceMissingPaymentSide extends InvoiceValidationError {
  const InvoiceMissingPaymentSide();
}

/// عملة غير معرفة — المعروفة في م1: 1 الأساسية و2 الدولار (D-070).
class InvoiceCurrencyInvalid extends InvoiceValidationError {
  final int currencyId;

  const InvoiceCurrencyInvalid(this.currencyId);
}

/// لقطة سعر غير سالبة موجبة، أو عملة الأساسية بلقطة غير محايدة
/// (D-082 معروض: الأساسية دائماً 1,000,000).
class InvoiceFxRateInvalid extends InvoiceValidationError {
  final int fxRate;

  const InvoiceFxRateInvalid(this.fxRate);
}

/// فاتورة بلا أسطر (05 §7-1 روح «قيدان فأكثر» على مستوى المستند).
class InvoiceNoLines extends InvoiceValidationError {
  const InvoiceNoLines();
}

/// كمية سطر صفر أو سالبة (س-03: «كمية غير صحيحة صفر أو سالبة»).
class InvoiceLineQtyInvalid extends InvoiceValidationError {
  final int lineIndex;
  final int qtyBase;

  const InvoiceLineQtyInvalid(this.lineIndex, this.qtyBase);
}

/// سعر سطر سالب (س-06: «سعر أو خصم سالب» — والصفر مشروع «هدية»).
class InvoiceLinePriceInvalid extends InvoiceValidationError {
  final int lineIndex;

  const InvoiceLinePriceInvalid(this.lineIndex);
}

/// خصم سطر سالب أو يتجاوز قيمة السطر (س-06).
class InvoiceLineDiscountInvalid extends InvoiceValidationError {
  final int lineIndex;

  const InvoiceLineDiscountInvalid(this.lineIndex);
}

/// نسبة خصم الفاتورة خارج 0..100 (س-06: «يتجاوز إجماليها أو يجعله
/// سالباً» — النسبة المقيَّدة تحقق المنع حسابياً).
class InvoiceDiscountRateInvalid extends InvoiceValidationError {
  final int rate;

  const InvoiceDiscountRateInvalid(this.rate);
}

/// فاتورة صافيها صفر — لا قيد بلا مبالغ (سطر القيد بصفر مرفوض أصلاً:
/// MoveLineAmountInvalid) فتُرفض المستند قبل أن تولد قيداً مستحيلاً.
class InvoiceZeroTotal extends InvoiceValidationError {
  const InvoiceZeroTotal();
}

/// ─── أخطاء المحرك (تحتاج بيانات القاعدة — تبنيها التخزين من الحقل
/// والسياق): ───

/// فترة التاريخ مقفلة — لا ترحيل فيها (07 §1.5/س-03).
class InvoiceClosedPeriod extends InvoiceValidationError {
  final String dateText;

  const InvoiceClosedPeriod(this.dateText);
}

/// التاريخ خارج كل الفترات — فجوة زمنية (07 §1.5).
class InvoiceNoPeriod extends InvoiceValidationError {
  final String dateText;

  const InvoiceNoPeriod(this.dateText);
}

/// سطر بصنف غير موجود بالمعرف.
class InvoiceItemNotFound extends InvoiceValidationError {
  final int lineIndex;
  final int itemId;

  const InvoiceItemNotFound(this.lineIndex, this.itemId);
}

/// سطر بصنف معطل — «صنف معطل» مرفوض (س-03/س-06) ويحمل عرضه.
class InvoiceItemInactive extends InvoiceValidationError {
  final int lineIndex;
  final String itemLabel;

  const InvoiceItemInactive(this.lineIndex, this.itemLabel);
}

/// وحدة السطر ليست الوحدة الأساسية للصنف — م1 إدخال بالأساسية حصراً
/// (09 §2/س-36) ووحدات التعبئة م2 (س-10).
class InvoiceUnitMismatch extends InvoiceValidationError {
  final int lineIndex;
  final String itemLabel;

  const InvoiceUnitMismatch(this.lineIndex, this.itemLabel);
}

/// بضاعة بلا مستودع، أو مستودع غير معرف — «بضاعة بلا مستودع» مرفوضة
/// (س-03).
class InvoiceWarehouseMissing extends InvoiceValidationError {
  final int? warehouseId;

  const InvoiceWarehouseMissing(this.warehouseId);
}

/// طرف غير معرف للآجل (س-04: «بلا طرف مرفوضة»).
class InvoicePartyMissing extends InvoiceValidationError {
  final int partyId;

  const InvoicePartyMissing(this.partyId);
}

/// صندوق غير معرف للنقدي — «صندوق غير معرف» مرفوض (س-03).
class InvoiceBoxMissing extends InvoiceValidationError {
  final int cashBoxId;

  const InvoiceBoxMissing(this.cashBoxId);
}

/// عملة الصندوق لا تطابق عملة الفاتورة — كل صندوق عملته واحدة
/// (05 §3.3) فلا خلط عملات في صندوق ولا حركة بعملة غير عملة صندوقها.
class InvoiceBoxCurrencyMismatch extends InvoiceValidationError {
  final String boxLabel;
  final int boxCurrencyId;
  final int invoiceCurrencyId;

  const InvoiceBoxCurrencyMismatch(
      this.boxLabel, this.boxCurrencyId, this.invoiceCurrencyId);
}

/// مرجع مردود لأصل غير موجود.
class InvoiceOriginalNotFound extends InvoiceValidationError {
  final int originalInvoiceId;

  const InvoiceOriginalNotFound(this.originalInvoiceId);
}

/// مرجع مردود لأصل غير مرحّل — الأصل مستند مالي حي (س-05: الفاتورة
/// الأصلية تبقى مرحّلة كما هي).
class InvoiceOriginalNotPosted extends InvoiceValidationError {
  final int originalInvoiceId;
  final String originalState;

  const InvoiceOriginalNotPosted(this.originalInvoiceId, this.originalState);
}

/// نوع المردود لا يطابق نوع أصله: مردود بيع لأصل بيع ومردود شراء لأصل
/// شراء حصراً.
class InvoiceOriginalKindMismatch extends InvoiceValidationError {
  final int originalInvoiceId;
  final String expectedKindLabel;

  const InvoiceOriginalKindMismatch(this.originalInvoiceId, this.expectedKindLabel);
}

/// كمية مردود تتجاوز المتبقي من الأصل بعد مردوداته المرحّلة
/// (س-05/س-11/F-056: «لا يتجاوز المتبقي»).
class InvoiceReturnQtyExceedsRemaining extends InvoiceValidationError {
  final int lineIndex;
  final String itemLabel;
  final int remainingQty;

  const InvoiceReturnQtyExceedsRemaining(
      this.lineIndex, this.itemLabel, this.remainingQty);
}

/// كمية خروج تتجاوز رصيد الصنف في مستودعه — منع السالب يفحص قبل الحفظ
/// وقبل الترحيل (س-06/F-042).
class InvoiceStockInsufficient extends InvoiceValidationError {
  final int lineIndex;
  final String itemLabel;
  final int availableQty;

  const InvoiceStockInsufficient(
      this.lineIndex, this.itemLabel, this.availableQty);
}

/// رد نقدي أو شراء نقدي يفرغ الصندوق تحت الصفر — منع السالب الموحد
/// (05 §7-2/س-11 «منع السالب الموحد — س8»).
class InvoiceBoxInsufficient extends InvoiceValidationError {
  final String boxLabel;
  final int availableBaseMinor;

  const InvoiceBoxInsufficient(this.boxLabel, this.availableBaseMinor);
}

/// فاتورة شراء بسطر خدمة — خريطة العمليات (05 §6/03 §4) تحدد حسابات
/// شراء البضاعة حصراً، وشراء الخدمات يحتاج اختيار حساب مصروف فيُعرض
/// مع دفعة لاحقة (إفصاح نطاق D-079 معروض).
class InvoiceServiceInPurchase extends InvoiceValidationError {
  final int lineIndex;
  final String itemLabel;

  const InvoiceServiceInPurchase(this.lineIndex, this.itemLabel);
}

/// سطر بصنف تجميعي — التجميعي م2 (F-034/09 §2) ووصفته غير موجودة في
/// م1 أصلاً، فأي مسار يصل به مرفوض صريحاً لا صامتاً.
class InvoiceBundleUnsupported extends InvoiceValidationError {
  final int lineIndex;
  final String itemLabel;

  const InvoiceBundleUnsupported(this.lineIndex, this.itemLabel);
}

/// ترحيل فاتورة ليست مسودة — آلة الحالة (05 §4.1/F-052).
class InvoiceStateNotDraft extends InvoiceValidationError {
  final String currentState;

  const InvoiceStateNotDraft(this.currentState);
}

/// المدقق البنيوي (قبل أي كتابة) — يعيد قائمة الأخطاء (فارغة = سليم)
/// بترتيب التسلسل التدريجي المعتمد: التاريخ ثم المرجع (للمردود) ثم جهة
/// الدفع ثم العملة واللقطات ثم الأسطر سطراً سطراً (الكمية ثم السعر ثم
/// الخصم) ثم الخصم الكلي ثم الصافي. فحوص المخزون والصندوق والأصل
/// والفترة شأن المحرك (تحتاج القاعدة) — وأنواعه أعلاه.
List<InvoiceValidationError> validateInvoiceDraftStructure(
  InvoiceDraft draft, {
  bool requireBaseFxIdentity = true,
}) {
  final errors = <InvoiceValidationError>[];
  if (!isValidIsoDate(draft.dateText)) {
    errors.add(InvoiceDateInvalid(draft.dateText));
  }
  if (draft.kind.isReturn && draft.originalInvoiceId == null) {
    errors.add(const InvoiceOriginalRequired());
  }
  if (draft.cashBoxId == null && draft.partyId == null) {
    errors.add(const InvoiceMissingPaymentSide());
  }
  if (draft.currencyId != 1 && draft.currencyId != 2) {
    errors.add(InvoiceCurrencyInvalid(draft.currencyId));
  }
  if (draft.fxRate <= 0 ||
      (requireBaseFxIdentity &&
          draft.currencyId == 1 &&
          draft.fxRate != baseCurrencyFxRate)) {
    errors.add(InvoiceFxRateInvalid(draft.fxRate));
  }
  if (draft.lines.isEmpty) {
    errors.add(const InvoiceNoLines());
  }
  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    if (line.qtyBase <= 0) {
      errors.add(InvoiceLineQtyInvalid(i, line.qtyBase));
      continue;
    }
    if (line.unitPriceMinor < 0) {
      errors.add(InvoiceLinePriceInvalid(i));
      continue;
    }
    if (line.discountMinor < 0 ||
        line.discountMinor > line.qtyBase * line.unitPriceMinor) {
      errors.add(InvoiceLineDiscountInvalid(i));
    }
  }
  if (draft.discountRate < 0 || draft.discountRate > 100) {
    errors.add(InvoiceDiscountRateInvalid(draft.discountRate));
  }
  if (errors.isEmpty) {
    final totals = computeInvoiceTotals(draft);
    if (totals.totalDocMinor <= 0) {
      errors.add(const InvoiceZeroTotal());
    }
  }
  return errors;
}

/// الوصف العربي لأخطاء التحقق — يخدم الاختبارات ورسائل الفشل في جولة
/// التنفيذ حصراً؛ الواجهة حرية صياغتها (نمط س-36: رسالة واحدة أول خطأ).
String describeInvoiceValidationError(InvoiceValidationError error) {
  switch (error) {
    case InvoiceDateInvalid(:final dateText):
      return 'التاريخ «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)';
    case InvoiceOriginalRequired():
      return 'المردود بلا مرجع فاتورة أصل — المرجع إلزاماً (س-05/س-11)';
    case InvoiceMissingPaymentSide():
      return 'لا صندوق ولا طرف — النقدي يطلب صندوقاً والآجل يطلب طرفاً';
    case InvoiceCurrencyInvalid(:final currencyId):
      return 'عملة غير معرفة (المعرف $currencyId) — المعروفة الأساسية والدولار';
    case InvoiceFxRateInvalid(:final fxRate):
      return 'لقطة السعر «$fxRate» غير صالحة — موجبة، ولعملة الأساسية 1,000,000 دائماً';
    case InvoiceNoLines():
      return 'الفاتورة بلا أسطر — سطر واحد فأكثر';
    case InvoiceLineQtyInvalid(:final lineIndex, :final qtyBase):
      return 'السطر ${lineIndex + 1}: الكمية «$qtyBase» صفر أو سالبة';
    case InvoiceLinePriceInvalid(:final lineIndex):
      return 'السطر ${lineIndex + 1}: السعر سالب — والصفر مشروع';
    case InvoiceLineDiscountInvalid(:final lineIndex):
      return 'السطر ${lineIndex + 1}: الخصم سالب أو يتجاوز قيمة السطر';
    case InvoiceDiscountRateInvalid(:final rate):
      return 'نسبة خصم الفاتورة «$rate» خارج 0..100';
    case InvoiceZeroTotal():
      return 'صافي الفاتورة صفر — لا قيد بلا مبالغ';
    case InvoiceClosedPeriod(:final dateText):
      return 'فترة التاريخ «$dateText» مقفلة — لا ترحيل فيها (07 §1.5)';
    case InvoiceNoPeriod(:final dateText):
      return 'التاريخ «$dateText» خارج كل الفترات المالية المفتوحة';
    case InvoiceItemNotFound(:final lineIndex, :final itemId):
      return 'السطر ${lineIndex + 1}: لا صنف بالمعرف $itemId';
    case InvoiceItemInactive(:final lineIndex, :final itemLabel):
      return 'السطر ${lineIndex + 1}: الصنف «$itemLabel» معطل';
    case InvoiceUnitMismatch(:final lineIndex, :final itemLabel):
      return 'السطر ${lineIndex + 1}: وحدة السطر ليست الوحدة الأساسية للصنف «$itemLabel» — م1 بالأساسية حصراً';
    case InvoiceServiceInPurchase(:final lineIndex, :final itemLabel):
      return 'السطر ${lineIndex + 1}: الخدمة «$itemLabel» لا تُشترى بفاتورة شراء في هذه الدفعة — حساب المصروف يُعرض لاحقاً';
    case InvoiceBundleUnsupported(:final lineIndex, :final itemLabel):
      return 'السطر ${lineIndex + 1}: الصنف التجميعي «$itemLabel» من المرحلة 2 — لا بيع له في م1 (F-034)';
    case InvoiceWarehouseMissing(:final warehouseId):
      return 'بضاعة بلا مستودع معرف (المعرف ${warehouseId ?? 'فارغ'}) — س-03';
    case InvoicePartyMissing(:final partyId):
      return 'لا طرف بالمعرف $partyId — الفاتورة الآجلة تولد ذمة لا تعلق على مجهول (س-04)';
    case InvoiceBoxMissing(:final cashBoxId):
      return 'لا صندوق بالمعرف $cashBoxId — صندوق غير معرف مرفوض (س-03)';
    case InvoiceBoxCurrencyMismatch(
        :final boxLabel,
        :final boxCurrencyId,
        :final invoiceCurrencyId
      ):
      return 'الصندوق «$boxLabel» عملته ($boxCurrencyId) لا تطابق عملة الفاتورة ($invoiceCurrencyId) — كل صندوق عملته واحدة';
    case InvoiceOriginalNotFound(:final originalInvoiceId):
      return 'لا فاتورة أصل بالمعرف $originalInvoiceId';
    case InvoiceOriginalNotPosted(:final originalInvoiceId, :final originalState):
      return 'الأصل بالمعرف $originalInvoiceId حالته «$originalState» — المرجع لأصل مرحّل حصراً';
    case InvoiceOriginalKindMismatch(
        :final originalInvoiceId,
        :final expectedKindLabel
      ):
      return 'مردود لأصل بالمعرف $originalInvoiceId ليس $expectedKindLabel — نوع المردود يطابق أصله';
    case InvoiceReturnQtyExceedsRemaining(
        :final lineIndex,
        :final itemLabel,
        :final remainingQty
      ):
      return 'السطر ${lineIndex + 1}: كمية «$itemLabel» تتجاوز المتبقي ($remainingQty) بعد مردودات سابقة';
    case InvoiceStockInsufficient(
        :final lineIndex,
        :final itemLabel,
        :final availableQty
      ):
      return 'السطر ${lineIndex + 1}: كمية «$itemLabel» تتجاوز رصيد المستودع ($availableQty) — منع السالب (F-042)';
    case InvoiceBoxInsufficient(:final boxLabel, :final availableBaseMinor):
      return 'رصيد الصندوق «$boxLabel» ($availableBaseMinor) لا يكفي — منع السالب الموحد (05 §7-2)';
    case InvoiceStateNotDraft(:final currentState):
      return 'الفاتورة حالتها «$currentState» — الترحيل للمسودة حصراً (F-052)';
  }
}

/// رفض مدقق الفواتير — يحمل الأخطاء النوعية (نمط LedgerValidationException
/// للقيود) وأوصافها العربية تخدم صفوف فشل التنفيذ حصراً.
class InvoiceValidationException implements Exception {
  final List<InvoiceValidationError> errors;

  const InvoiceValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق الفواتير: ${errors.map(describeInvoiceValidationError).join('؛ ')}';
}
