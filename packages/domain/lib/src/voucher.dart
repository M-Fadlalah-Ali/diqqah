/// السندات والصناديق في دِقَّة — دفعة م1 الخامسة، المنطق النقي حصراً بلا
/// Flutter ولا Drift (F-010، 07 §1.8).
///
/// المرجع الحاكم الموثق (README-v2.01 §3):
/// - 05 §4.2: السند `voucher` kind(receipt/payment) برقمه وصندوقه ومبلغه،
///   وصفوف المطابقة `voucher_allocation` **تشغيلية جزء لا يتجزأ من السند
///   الذي ولّده** (م-21/D-042) — والمطابقة «يدوياً أو آلياً بالأقدمية مع
///   إمكانية التعديل» ويجوز أن يبقى سند بلا مطابقة = «رصيد مقدّم» (س5).
/// - 06 §4 (س-12..س-17): القبض الطرفي 111x مدين / 112 دائن والدفع الطرفي
///   211 مدين / 111x دائن، والقبض بغير طرف على حساب مباشر (311 ضخ رأس
///   مال — س-13) والدفع بغير طرف (321 مسحوبات أو 54x مصروفات — س-15)،
///   والتحويل بين الصناديق (س-16/F-068) وتسوية الصندوق على 57 (س-17/F-067).
/// - D-105 (دفعة 8 س39): مصطلح «سند دفع» في كل إشارة إلى السند بلفظ
///   المالك «تعديل سند الصرف فقط إلى سند دفع، وليس كل كلمة صرف إلى دفع
///   إلا إن كان المقصود بها الإشارة إلى سند الصرف» — والقيمة التخزينية
///   `payment` لا تتغير فلا ترحيل بيانات، والبيانات القديمة كما هي.
/// - 03 §3: كل صندوق جديد يُنشأ معه حساب ورقي (1112, 1113...) — تنفيذ
///   D-086، و03 §4: خريطة عمليات السندات حرفاً.
/// - F-123/D-085: فروق العملة المحققة عند السداد بقيد آلي — 55 خسائر
///   مديناً أو 44 أرباحاً دائناً، فتصفو ذمة الطرف بالأساسية حرفاً.
/// - F-063/D-084: «مدفوعة/جزئية» تُشتق آلياً بالمطابقات حصراً لا ضبطاً
///   يدوياً؛ والمطبَّق بعملة الفاتورة وبلقطتها، وآخر مطابقة لكل فاتورة
///   تمتص فارق التقريب (نمط D-067: لا غبار تقريب).
/// - 07 §1.9: الترقيم متصل بلا إعادة استخدام ولا فجوة — «سند قبض
///   2026/000001» باسم النوع الكامل (م-44) وأنواع تسلسل جديدة للسندات
///   والتحويل والتسوية.
///
/// سيناريوهات الدفعة س-61..س-70 (06 §1-و): مقترحة وبُنيت عليها حصراً —
/// بانتظار اعتماد المالك أو تعديلها (عرف الدفعات: الصدق أولاً).

import 'invoice.dart' show baseCurrencyFxRate, convertToBaseMinor;
import 'journal.dart' show isValidIsoDate;

export 'invoice.dart' show baseCurrencyFxRate, convertToBaseMinor, fxRateScale;

/// نوع السند (05 §4.2): قبض أو دفع — والاتجاه يحدد أرجل القيد وجهة حركة
/// الصندوق: القبض «داخل» والدفع «خارج» (س-12/س-14).
enum VoucherKind {
  receipt('receipt', 'سند قبض'),
  payment('payment', 'سند دفع');

  final String storageValue;
  final String label;

  const VoucherKind(this.storageValue, this.label);

  static VoucherKind fromStorage(String value) {
    for (final k in VoucherKind.values) {
      if (k.storageValue == value) return k;
    }
    throw ArgumentError('نوع سند غير معروف: $value');
  }

  bool get isReceipt => this == receipt;
}

/// مفتاح التسلسل السنوي لترقيم السندات (05 §5/نمط D-080): لكل نوع سند
/// تسلسله — والاسم الكامل في sequenceKindLabels (journal.dart).
String voucherSequenceKind(VoucherKind kind) => switch (kind) {
      VoucherKind.receipt => 'voucher_receipt',
      VoucherKind.payment => 'voucher_payment',
    };

/// اتجاه تسوية الصندوق (س-17/F-067): العجز مدين به على 57 والزيادة دائنة
/// به — الحساب الواحد للعجز والزيادة (س8).
enum CashAdjustmentDirection {
  shortage('shortage', 'عجز'),
  overage('overage', 'زيادة');

  final String storageValue;
  final String label;

  const CashAdjustmentDirection(this.storageValue, this.label);

  static CashAdjustmentDirection fromStorage(String value) {
    for (final d in CashAdjustmentDirection.values) {
      if (d.storageValue == value) return d;
    }
    throw ArgumentError('اتجاه تسوية غير معروف: $value');
  }
}

/// صف مطابقة خام كما يخرج من التوزيع الآلي أو التعديل اليدوي (05 §4.2).
///
/// - [invoiceId] فاتورة الطرف المرحّلة نفسه (سند قبض على بيعاته وسند دفع
///   على مشترياته) — وبعملة السند نفسها (D-084 معروض).
/// - [appliedDocMinor] المطبَّق **بعملة الفاتورة** — عمود تنفيذي
///   `applied_doc_minor` بجانب `applied_base_minor` المفاهيمي (05 §4.2
///   يعدد الجوهرية لا الحصرية — نمط D-079). والمكافئ الأساسي يُحسب
///   بلقطة الفاتورة عند الترحيل فتصفو الذمة حرفاً.
class VoucherAllocationDraft {
  final int invoiceId;
  final int appliedDocMinor;

  const VoucherAllocationDraft({
    required this.invoiceId,
    required this.appliedDocMinor,
  });
}

/// مسودة سند خام — ما يُدقق قبل أي كتابة (نمط الفواتير والقيود).
///
/// السند دائماً على صندوق (05 §4.2: `cash_box_id` إلزامي) وعملته عملة
/// صندوقه (س-03 نفسها)، والطرف والحساب المباشر حصريان: طرفي مطابَق
/// (س-12/س-14) أو بغير طرف على حساب مباشر (س-13/س-15).
class VoucherDraft {
  final VoucherKind kind;

  /// تاريخ العملية ISO «YYYY-MM-DD» (D-077 المعتمد).
  final String dateText;

  /// طرف السند الطرفي — العميل للقبض والمورد للدفع.
  final int? partyId;

  /// الحساب المباشر للسند بغير طرف: 311 ضخ رأس مال، 321 مسحوبات،
  /// 54x مصروف تشغيلي (س-13/س-15) — ويُرفض أن يكون حساب صندوق.
  final int? directAccountId;

  final int cashBoxId;

  /// عملة السند = عملة صندوقه — 1 الأساسية (D-066) و2 الدولار (D-070).
  final int currencyId;

  /// لقطة السعر لحظة السند (F-122/D-082) — الأساسية 1,000,000 دائماً.
  final int fxRate;

  /// المبلغ الكلي بوحدة صغرى من عملة السند — والفائض غير المطابق يبقى
  /// «رصيداً مقدّماً» على ذمة الطرف (س-12/س5).
  final int amountDocMinor;

  /// الوصف اختياري — وسبب التسوية الخاصة به إلزامي في مستند تسوية الصندوق.
  final String? narration;

  /// المطابقات المقترحة آلياً أو المعدلة يدوياً — تُثبت عند الترحيل.
  final List<VoucherAllocationDraft> allocations;

  const VoucherDraft({
    required this.kind,
    required this.dateText,
    this.partyId,
    this.directAccountId,
    required this.cashBoxId,
    this.currencyId = 1,
    this.fxRate = baseCurrencyFxRate,
    required this.amountDocMinor,
    this.narration,
    this.allocations = const [],
  });

  /// مجموع المطبَّق بعملة السند.
  int get appliedDocTotal {
    var total = 0;
    for (final a in allocations) {
      total += a.appliedDocMinor;
    }
    return total;
  }

  /// الفائض غير المطابق — «رصيد مقدّم» على الذمة (س-12/س5).
  int get unappliedDocMinor => amountDocMinor - appliedDocTotal;
}

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة (نمط الأطراف
/// والفواتير): الواجهة وحدها تقرر الصياغة المعروضة، و
/// [describeVoucherValidationError] تخدم الاختبارات وصفوف الفشل حصراً.
sealed class VoucherValidationError {
  const VoucherValidationError();
}

/// تاريخ السند ليس ISO «YYYY-MM-DD» صالحاً (D-077).
class VoucherDateInvalid extends VoucherValidationError {
  final String dateText;

  const VoucherDateInvalid(this.dateText);
}

/// مبلغ السند صفر أو سالب — الصفر لا قيمة له بمستند نقدي.
class VoucherAmountInvalid extends VoucherValidationError {
  const VoucherAmountInvalid();
}

/// لقطة السعر غير موجبة (D-082).
class VoucherFxRateInvalid extends VoucherValidationError {
  const VoucherFxRateInvalid();
}

/// سند بلا طرف وبلا حساب مباشر معاً، أو بالاثنين معاً — أحدهما حصراً
/// (س-12..س-15).
class VoucherPartyAndAccountExclusive extends VoucherValidationError {
  const VoucherPartyAndAccountExclusive();
}

/// المطابقات على سند بغير طرف — المطابقة صفة الطرفي حصراً.
class VoucherAllocationWithDirectAccount extends VoucherValidationError {
  const VoucherAllocationWithDirectAccount();
}

/// صف مطابقة بمبلغ صفر أو سالب.
class VoucherAllocationAmountInvalid extends VoucherValidationError {
  final int invoiceId;

  const VoucherAllocationAmountInvalid(this.invoiceId);
}

/// فاتورة واحدة في صفين بمطابقات السند — الصف الواحد لكل فاتورة.
class VoucherAllocationDuplicated extends VoucherValidationError {
  final int invoiceId;

  const VoucherAllocationDuplicated(this.invoiceId);
}

/// مجموع المطابقات تجاوز مبلغ السند — الفائض نتيجة السند لا المطابقة.
class VoucherAllocationsExceedAmount extends VoucherValidationError {
  final int appliedDocMinor;
  final int amountDocMinor;

  const VoucherAllocationsExceedAmount(this.appliedDocMinor, this.amountDocMinor);
}

/// ─── الأنواع المحركية — تفحصها معاملة التخزين على ما خُزّن (نمط الفواتير) ───

/// لا فترة حاضنة للتاريخ (07 §1.5).
class VoucherNoPeriod extends VoucherValidationError {
  final String dateText;

  const VoucherNoPeriod(this.dateText);
}

/// الفترة الحاضنة مقفلة — الترحيل فيها مجمد.
class VoucherClosedPeriod extends VoucherValidationError {
  final String dateText;

  const VoucherClosedPeriod(this.dateText);
}

/// صندوق السند غير معروف (س-03: «صندوق غير معرف»).
class VoucherBoxMissing extends VoucherValidationError {
  const VoucherBoxMissing();
}

/// حساب الصندوق معطل (03 §6-3) — يختفي من الاختيار ولا يقيد عليه.
class VoucherBoxInactive extends VoucherValidationError {
  final String boxLabel;

  const VoucherBoxInactive(this.boxLabel);
}

/// عملة السند تخالف عملة صندوقه — سند كل صندوق بعملته (D-086 معروض).
class VoucherBoxCurrencyMismatch extends VoucherValidationError {
  const VoucherBoxCurrencyMismatch();
}

/// الحساب المباشر غير موجود أو غير ورقي أو معطل (03 §1-2/§1-3).
class VoucherDirectAccountNotLedgerable extends VoucherValidationError {
  final String accountLabel;

  const VoucherDirectAccountNotLedgerable(this.accountLabel);
}

/// الحساب المباشر حساب صندوق — تحويل الصناديق مستنده لا سند (س-16).
class VoucherDirectAccountIsBox extends VoucherValidationError {
  final String accountLabel;

  const VoucherDirectAccountIsBox(this.accountLabel);
}

/// مطابقة على فاتورة غير موجودة.
class VoucherAllocationInvoiceUnknown extends VoucherValidationError {
  final int invoiceId;

  const VoucherAllocationInvoiceUnknown(this.invoiceId);
}

/// مطابقة على فاتورة مسودة — المطابقة للمرحّلة حصراً.
class VoucherAllocationInvoiceNotCommitted extends VoucherValidationError {
  final int invoiceId;
  final String stateLabel;

  const VoucherAllocationInvoiceNotCommitted(this.invoiceId, this.stateLabel);
}

/// مطابقة على فاتورة مغطاة كلياً — مدفوعة أصلاً (F-063).
class VoucherAllocationInvoicePaid extends VoucherValidationError {
  final int invoiceId;

  const VoucherAllocationInvoicePaid(this.invoiceId);
}

/// مطابقة على فاتورة لطرف آخر.
class VoucherAllocationWrongParty extends VoucherValidationError {
  final int invoiceId;

  const VoucherAllocationWrongParty(this.invoiceId);
}

/// مطابقة خاطئة الاتجاه: قبض على شراء أو دفع على بيع (س-12/س-14).
class VoucherAllocationWrongKind extends VoucherValidationError {
  final int invoiceId;

  const VoucherAllocationWrongKind(this.invoiceId);
}

/// مطابقة على فاتورة بعملة تخالف عملة السند (D-084 معروض).
class VoucherAllocationCurrencyMismatch extends VoucherValidationError {
  final int invoiceId;

  const VoucherAllocationCurrencyMismatch(this.invoiceId);
}

/// المطبَّق تجاوز متبقي الفاتورة بعد مطابقات السندات المرحّلة.
class VoucherAllocationExceedsRemaining extends VoucherValidationError {
  final int invoiceId;
  final String invoiceLabel;
  final int remainingDocMinor;

  const VoucherAllocationExceedsRemaining(
      this.invoiceId, this.invoiceLabel, this.remainingDocMinor);
}

/// السند مرحّل أصلاً — الآلة مسودة ← مرحّل بلا رجوع (07 §1.2).
class VoucherStateNotDraft extends VoucherValidationError {
  final String stateLabel;

  const VoucherStateNotDraft(this.stateLabel);
}

/// المدقق البنيوي قبل الحفظ (نمط الفواتير): البنية هنا، والفحوص
/// المحركية (وجود الصندوق ونشاط حسابه وعملته، ومرحّلية فواتير المطابقة
/// وانتماؤها للطرف وبقاؤها مفتوحة، والفترة المفتوحة) في محرك التخزين —
/// ويعيد قائمة الأخطاء فارغةً إذا سلمت المسودة بنيوياً.
List<VoucherValidationError> validateVoucherDraftStructure(VoucherDraft draft) {
  final errors = <VoucherValidationError>[];
  if (!isValidIsoDate(draft.dateText)) {
    errors.add(VoucherDateInvalid(draft.dateText));
  }
  if (draft.amountDocMinor <= 0) {
    errors.add(const VoucherAmountInvalid());
  }
  if (draft.fxRate <= 0) {
    errors.add(const VoucherFxRateInvalid());
  }
  final hasParty = draft.partyId != null;
  final hasDirect = draft.directAccountId != null;
  if (hasParty == hasDirect) {
    errors.add(const VoucherPartyAndAccountExclusive());
  }
  if (!hasParty && draft.allocations.isNotEmpty) {
    errors.add(const VoucherAllocationWithDirectAccount());
  }
  final seen = <int>{};
  for (final a in draft.allocations) {
    if (a.appliedDocMinor <= 0) {
      errors.add(VoucherAllocationAmountInvalid(a.invoiceId));
    }
    if (!seen.add(a.invoiceId)) {
      errors.add(VoucherAllocationDuplicated(a.invoiceId));
    }
  }
  if (draft.appliedDocTotal > draft.amountDocMinor) {
    errors.add(VoucherAllocationsExceedAmount(
        draft.appliedDocTotal, draft.amountDocMinor));
  }
  return errors;
}

/// مرشح فاتورة مفتوحة للتوزيع الآلي — المتبقي بعملة الفاتورة بعد مطابقات
/// السندات المرحّلة (المسودات مقترحات لا تُحسب).
class OpenInvoiceCandidate {
  final int invoiceId;
  final int remainingDocMinor;
  final String dateText;
  final String? dueDateText;
  final String number;

  const OpenInvoiceCandidate({
    required this.invoiceId,
    required this.remainingDocMinor,
    required this.dateText,
    this.dueDateText,
    required this.number,
  });
}

/// التوزيع الآلي بالأقدمية (02 §8/س-12): المستحق أولاً بتاريخ استحقاقه،
/// وغير المستحق تُؤخَّر به تاريخه (بلا استحقاق آخر ما يكون)، ثم التاريخ
/// ثم الرقم — **اقتراح معدَّل قبل الترحيل لا قرار نهائي** (06 §4)،
/// والمتبقي من السند بلا صفوف = «رصيد مقدّم».
List<VoucherAllocationDraft> proposeOldestAllocations({
  required int amountDocMinor,
  required List<OpenInvoiceCandidate> openInvoices,
}) {
  final sorted = [...openInvoices]..sort((a, b) {
      final dueA = a.dueDateText ?? '9999-12-31';
      final dueB = b.dueDateText ?? '9999-12-31';
      var r = dueA.compareTo(dueB);
      if (r != 0) return r;
      r = a.dateText.compareTo(b.dateText);
      if (r != 0) return r;
      return a.number.compareTo(b.number);
    });
  final out = <VoucherAllocationDraft>[];
  var left = amountDocMinor;
  for (final c in sorted) {
    if (left <= 0) break;
    if (c.remainingDocMinor <= 0) continue;
    final take = left < c.remainingDocMinor ? left : c.remainingDocMinor;
    out.add(VoucherAllocationDraft(invoiceId: c.invoiceId, appliedDocMinor: take));
    left -= take;
  }
  return out;
}

/// المكافئ الأساسي للمطبَّق بلقطة فاتورته (D-084/F-122) — الذمة تصفو
/// بالقيمة المسجلة لها لا بقيمة لقطة السند، والفرق بين اللقطتين فرق
/// صرف محقق يقيَّد على 44/55 في موضع القيد (F-123/D-085).
int allocationBaseMinor(int appliedDocMinor, int invoiceFxRate) =>
    convertToBaseMinor(appliedDocMinor, invoiceFxRate);

/// وصف عربي لصفوف الفشل حصراً — الواجهة حرية صياغتها المعروضة (F-162).
String describeVoucherValidationError(VoucherValidationError error) =>
    switch (error) {
      VoucherDateInvalid(:final dateText) =>
        'تاريخ السند «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)',
      VoucherAmountInvalid() => 'مبلغ السند يجب أن يكون أكبر من صفر',
      VoucherFxRateInvalid() => 'لقطة سعر السند يجب أن تكون موجبة',
      VoucherPartyAndAccountExclusive() =>
        'السند إما لطرف معروف وإما على حساب مباشر بغير طرف — ولا يجوز الاثنان معاً ولا تفويتهما',
      VoucherAllocationWithDirectAccount() =>
        'المطابقات للسند الطرفي حصراً — والسند بغير طرف يقيد كله على حسابه المباشر',
      VoucherAllocationAmountInvalid(:final invoiceId) =>
        'مطبَّق الفاتورة رقم $invoiceId يجب أن يكون أكبر من صفر',
      VoucherAllocationDuplicated(:final invoiceId) =>
        'الفاتورة رقم $invoiceId وردت في صفين — صف واحد لكل فاتورة',
      VoucherAllocationsExceedAmount(
        :final appliedDocMinor,
        :final amountDocMinor,
      ) =>
        'مجموع المطابقات $appliedDocMinor تجاوز مبلغ السند $amountDocMinor',
      VoucherNoPeriod(:final dateText) =>
        'تاريخ السند $dateText خارج كل الفترات — لا فترة حاضنة له',
      VoucherClosedPeriod(:final dateText) =>
        'فترة السند $dateText مقفلة — الترحيل فيها مجمد',
      VoucherBoxMissing() => 'صندوق السند غير معروف (س-03)',
      VoucherBoxInactive(:final boxLabel) =>
        'حساب الصندوق «$boxLabel» معطل — يختفي من الاختيار (03 §6-3)',
      VoucherBoxCurrencyMismatch() =>
        'عملة السند تخالف عملة صندوقه — سند كل صندوق بعملته',
      VoucherDirectAccountNotLedgerable(:final accountLabel) =>
        'الحساب المباشر «$accountLabel» غير صالح للقيد — ورقي مفعّل حصراً',
      VoucherDirectAccountIsBox(:final accountLabel) =>
        'الحساب المباشر «$accountLabel» حساب صندوق — التحويل بين الصناديق مستنده الخاص (س-16)',
      VoucherAllocationInvoiceUnknown(:final invoiceId) =>
        'مطابقة على فاتورة غير موجودة (رقم $invoiceId)',
      VoucherAllocationInvoiceNotCommitted(:final invoiceId, :final stateLabel) =>
        'مطابقة على فاتورة لا تزال مسودة (رقم $invoiceId، حالتها $stateLabel)',
      VoucherAllocationInvoicePaid(:final invoiceId) =>
        'الفاتورة رقم $invoiceId مغطاة كلياً — مطابقة إضافية عليها مرفوضة',
      VoucherAllocationWrongParty(:final invoiceId) =>
        'الفاتورة رقم $invoiceId لطرف آخر — المطابقة لفواتير الطرف نفسه',
      VoucherAllocationWrongKind(:final invoiceId) =>
        'اتجاه المطابقة خاطئ للفاتورة رقم $invoiceId — القبض على بيعاته والدفع على مشترياته',
      VoucherAllocationCurrencyMismatch(:final invoiceId) =>
        'الفاتورة رقم $invoiceId بعملة تخالف عملة السند',
      VoucherAllocationExceedsRemaining(
        :final invoiceLabel,
        :final remainingDocMinor,
      ) =>
        'مطبَّق الفاتورة «$invoiceLabel» تجاوز متبقيها $remainingDocMinor',
      VoucherStateNotDraft(:final stateLabel) =>
        'السند مرحّل أصلاً (حالته $stateLabel) — بلا رجوع ولا تعديل (07 §1.2)',
    };

/// رفض مدقق السند — يحمل الأخطاء النوعية المحمولة (نمط الفواتير).
class VoucherValidationException implements Exception {
  final List<VoucherValidationError> errors;

  const VoucherValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق السند: ${errors.map(describeVoucherValidationError).join('؛ ')}';
}

/// ─── التحويل بين الصناديق (س-16/F-068) ───

/// مسودة تحويل بين صندوقين (س-16): العملة الواحدة على الطرفين، والتحويل
/// بين عملتين مختلفتين مؤجل مع تعدد العملات (09 §4). قيدُه من دفتر
/// النقدية بحركة صندوق على كل طرف بمرجعية متبادلة.
class CashTransferDraft {
  final String dateText;
  final int fromBoxId;
  final int toBoxId;
  final int amountDocMinor;
  final int currencyId;
  final int fxRate;
  final String? narration;

  const CashTransferDraft({
    required this.dateText,
    required this.fromBoxId,
    required this.toBoxId,
    required this.amountDocMinor,
    this.currencyId = 1,
    this.fxRate = baseCurrencyFxRate,
    this.narration,
  });
}

/// أخطاء التحويل البنيوية — والمحركية (وجود الصندوقين وعملتهما ورصيد
/// المرسل والفترة) في محرك التخزين.
sealed class CashTransferValidationError {
  const CashTransferValidationError();
}

class TransferDateInvalid extends CashTransferValidationError {
  final String dateText;

  const TransferDateInvalid(this.dateText);
}

class TransferAmountInvalid extends CashTransferValidationError {
  const TransferAmountInvalid();
}

class TransferFxRateInvalid extends CashTransferValidationError {
  const TransferFxRateInvalid();
}

class TransferSameBox extends CashTransferValidationError {
  const TransferSameBox();
}

/// ─── الأنواع المحركية للتحويل — تفحصها معاملة التخزين ───

/// لا فترة حاضنة للتاريخ (07 §1.5).
class TransferNoPeriod extends CashTransferValidationError {
  final String dateText;

  const TransferNoPeriod(this.dateText);
}

/// الفترة الحاضنة مقفلة.
class TransferClosedPeriod extends CashTransferValidationError {
  final String dateText;

  const TransferClosedPeriod(this.dateText);
}

/// أحد الصندوقين غير معروف (س-03).
class TransferBoxMissing extends CashTransferValidationError {
  const TransferBoxMissing();
}

/// حساب أحد الصندوقين معطل (03 §6-3).
class TransferBoxInactive extends CashTransferValidationError {
  final String boxLabel;

  const TransferBoxInactive(this.boxLabel);
}

/// عملتا الصندوقين مختلفتان — التحويل بين عملتين مؤجل (09 §4/س-16).
class TransferCurrencyMismatch extends CashTransferValidationError {
  const TransferCurrencyMismatch();
}

/// رصيد صندوق المرسل لا يكفي — منع السالب الموحد (05 §7-2/س-16 §10.1).
class TransferSenderInsufficient extends CashTransferValidationError {
  final int balanceBaseMinor;
  final int amountBaseMinor;

  const TransferSenderInsufficient(this.balanceBaseMinor, this.amountBaseMinor);
}

/// التحويل مرحّل أصلاً — بلا رجوع ولا تعديل (07 §1.2).
class TransferStateNotDraft extends CashTransferValidationError {
  final String stateLabel;

  const TransferStateNotDraft(this.stateLabel);
}

/// المدقق البنيوي لمسودة التحويل (س-16: نفس الصندوق على الطرفين مرفوض).
List<CashTransferValidationError> validateCashTransferStructure(
    CashTransferDraft draft) {
  final errors = <CashTransferValidationError>[];
  if (!isValidIsoDate(draft.dateText)) {
    errors.add(TransferDateInvalid(draft.dateText));
  }
  if (draft.amountDocMinor <= 0) {
    errors.add(const TransferAmountInvalid());
  }
  if (draft.fxRate <= 0) {
    errors.add(const TransferFxRateInvalid());
  }
  if (draft.fromBoxId == draft.toBoxId) {
    errors.add(const TransferSameBox());
  }
  return errors;
}

String describeCashTransferValidationError(CashTransferValidationError error) =>
    switch (error) {
      TransferDateInvalid(:final dateText) =>
        'تاريخ التحويل «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)',
      TransferAmountInvalid() => 'مبلغ التحويل يجب أن يكون أكبر من صفر',
      TransferFxRateInvalid() => 'لقطة سعر التحويل يجب أن تكون موجبة',
      TransferSameBox() => 'التحويل من الصندوق إلى نفسه مرفوض — صندوقان مختلفان',
      TransferNoPeriod(:final dateText) =>
        'تاريخ التحويل $dateText خارج كل الفترات — لا فترة حاضنة له',
      TransferClosedPeriod(:final dateText) =>
        'فترة التحويل $dateText مقفلة — الترحيل فيها مجمد',
      TransferBoxMissing() => 'أحد صندوقي التحويل غير معروف (س-03)',
      TransferBoxInactive(:final boxLabel) =>
        'حساب الصندوق «$boxLabel» معطل — يختفي من الاختيار (03 §6-3)',
      TransferCurrencyMismatch() =>
        'التحويل بين صندوقين بعملتين مختلفتين مؤجل مع تعدد العملات (س-16)',
      TransferSenderInsufficient(:final balanceBaseMinor, :final amountBaseMinor) =>
        'رصيد صندوق المرسل $balanceBaseMinor لا يكفي عن مبلغ التحويل $amountBaseMinor — منع السالب (05 §7-2)',
      TransferStateNotDraft(:final stateLabel) =>
        'التحويل مرحّل أصلاً (حالته $stateLabel) — بلا رجوع ولا تعديل (07 §1.2)',
    };

class CashTransferValidationException implements Exception {
  final List<CashTransferValidationError> errors;

  const CashTransferValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق التحويل: ${errors.map(describeCashTransferValidationError).join('؛ ')}';
}

/// ─── تسوية الصندوق (س-17/F-067) ───

/// مسودة تسوية صندوق (س-17): إدخال العدد الفعلي يقارن بالدفتري والفرق
/// عجزاً أو زيادة يقيد على 57 (س8) — وسبب نصي إلزامي للفرق، والفرق صفر
/// لا يولّد تسوية أصلاً (فالمبلغ موجب إلزاماً بالبنية).
class CashAdjustmentDraft {
  final String dateText;
  final int cashBoxId;

  /// عملة الصندوق هي عملة التسوية — واللقطة لحظتها (F-122/D-082).
  final int currencyId;
  final int fxRate;
  final CashAdjustmentDirection direction;
  final int amountDocMinor;

  /// سبب الفرق نصي إلزامي (س-17).
  final String reason;

  const CashAdjustmentDraft({
    required this.dateText,
    required this.cashBoxId,
    this.currencyId = 1,
    this.fxRate = baseCurrencyFxRate,
    required this.direction,
    required this.amountDocMinor,
    required this.reason,
  });
}

/// أخطاء التسوية البنيوية — والمحركية في محرك التخزين.
sealed class CashAdjustmentValidationError {
  const CashAdjustmentValidationError();
}

class AdjustmentDateInvalid extends CashAdjustmentValidationError {
  final String dateText;

  const AdjustmentDateInvalid(this.dateText);
}

class AdjustmentAmountInvalid extends CashAdjustmentValidationError {
  const AdjustmentAmountInvalid();
}

class AdjustmentFxRateInvalid extends CashAdjustmentValidationError {
  const AdjustmentFxRateInvalid();
}

class AdjustmentReasonRequired extends CashAdjustmentValidationError {
  const AdjustmentReasonRequired();
}

/// ─── الأنواع المحركية للتسوية — تفحصها معاملة التخزين ───

/// لا فترة حاضنة للتاريخ (07 §1.5).
class AdjustmentNoPeriod extends CashAdjustmentValidationError {
  final String dateText;

  const AdjustmentNoPeriod(this.dateText);
}

/// الفترة الحاضنة مقفلة.
class AdjustmentClosedPeriod extends CashAdjustmentValidationError {
  final String dateText;

  const AdjustmentClosedPeriod(this.dateText);
}

/// صندوق التسوية غير معروف (س-03).
class AdjustmentBoxMissing extends CashAdjustmentValidationError {
  const AdjustmentBoxMissing();
}

/// حساب صندوق التسوية معطل (03 §6-3).
class AdjustmentBoxInactive extends CashAdjustmentValidationError {
  final String boxLabel;

  const AdjustmentBoxInactive(this.boxLabel);
}

/// عملة التسوية تخالف عملة صندوقها (D-086 معروض).
class AdjustmentBoxCurrencyMismatch extends CashAdjustmentValidationError {
  const AdjustmentBoxCurrencyMismatch();
}

/// التسوية مرحّلة أصلاً — بلا رجوع ولا تعديل (07 §1.2).
class AdjustmentStateNotDraft extends CashAdjustmentValidationError {
  final String stateLabel;

  const AdjustmentStateNotDraft(this.stateLabel);
}

/// المدقق البنيوي لمسودة التسوية (س-17: سبب نصي إلزامي للفرق).
List<CashAdjustmentValidationError> validateCashAdjustmentStructure(
    CashAdjustmentDraft draft) {
  final errors = <CashAdjustmentValidationError>[];
  if (!isValidIsoDate(draft.dateText)) {
    errors.add(AdjustmentDateInvalid(draft.dateText));
  }
  if (draft.amountDocMinor <= 0) {
    errors.add(const AdjustmentAmountInvalid());
  }
  if (draft.fxRate <= 0) {
    errors.add(const AdjustmentFxRateInvalid());
  }
  if (draft.reason.trim().isEmpty) {
    errors.add(const AdjustmentReasonRequired());
  }
  return errors;
}

String describeCashAdjustmentValidationError(
        CashAdjustmentValidationError error) =>
    switch (error) {
      AdjustmentDateInvalid(:final dateText) =>
        'تاريخ التسوية «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)',
      AdjustmentAmountInvalid() =>
        'فرق التسوية يجب أن يكون أكبر من صفر — والفرق صفر لا يولّد تسوية',
      AdjustmentFxRateInvalid() => 'لقطة سعر التسوية يجب أن تكون موجبة',
      AdjustmentReasonRequired() => 'سبب تسوية الصندوق إلزامي للفرق',
      AdjustmentNoPeriod(:final dateText) =>
        'تاريخ التسوية $dateText خارج كل الفترات — لا فترة حاضنة له',
      AdjustmentClosedPeriod(:final dateText) =>
        'فترة التسوية $dateText مقفلة — الترحيل فيها مجمد',
      AdjustmentBoxMissing() => 'صندوق التسوية غير معروف (س-03)',
      AdjustmentBoxInactive(:final boxLabel) =>
        'حساب الصندوق «$boxLabel» معطل — يختفي من الاختيار (03 §6-3)',
      AdjustmentBoxCurrencyMismatch() =>
        'عملة التسوية تخالف عملة صندوقها',
      AdjustmentStateNotDraft(:final stateLabel) =>
        'التسوية مرحّلة أصلاً (حالتها $stateLabel) — بلا رجوع ولا تعديل (07 §1.2)',
    };

class CashAdjustmentValidationException implements Exception {
  final List<CashAdjustmentValidationError> errors;

  const CashAdjustmentValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق التسوية: ${errors.map(describeCashAdjustmentValidationError).join('؛ ')}';
}
