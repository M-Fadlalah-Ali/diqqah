/// الأصناف التجميعية بوصفة مكونات — F-034/F-212 (الدفعة 28، خامسة م2).
///
/// النص المعتمد الحاكم (س81 — F-034 حرفاً):
/// - بيع التجميعي عند الترحيل يسحب **من رصيده الجاهز أولاً** — رصيد
///   التجميعي مفتوح بالشراء الجاهز أو مستند التجميع (F-211) — **ويكمل
///   النقص بفكك مكوناته بكمياتها**.
/// - تكلفة السطر مركبة: ما خرج جاهزاً بتكلفته المخزنية (المتوسط الحاكم
///   F-047/D-067) وما فُكك بمجموع كلف مكوناته — والتفصيل بعلم
///   «جاهز/فُكِّك» في الحركات.
/// - الشراء بسطر واحد يدخل الجاهز مباشرة **بلا فكك** — الوصفة تعمل
///   عند الفك (بيع) والجمّع (F-211) ولا تفعل شيئاً في الشراء الجاهز.
/// - مثال المتطلب الحرفي: بيع 12 سلّة برصيد 6 جاهزة ⇒ 6 بتكلفة
///   المخزون و6 بحركات مكونات — والثابت F-178 مستقر بعد كل ترحيل.
///
/// مكوّن الخدمة (F-212 — س80، خيارا المالك بخانة واحدة):
/// - بلا مخزون دائماً وبلا حركة مخزون في الحالتين.
/// - تكلفة فارغة = بند بيعي ضمن السعر (ربحه ضمن هامش التجميعي كله).
/// - تكلفة بقيمة (خدمة تشترى من طرف خارجي) = تدخل مجموع كلف الوصفة —
///   فترفع التكلفة المركبة للسطر.
///
/// الحد المحاسبي الصادق الموثق (بانتظار كلمة المالك — D-190 مقترح):
/// القيد المحمول على 51/113 بالقيم المخزنية حصراً (خروج الجاهز + خروج
/// مكونات البضاعة) كي يستقر F-178 بلا مساس — وتكلفة الخدمة تُحمل على
/// التكلفة المركبة في المجال (compositeCostMinor) ولحساب الهامش،
/// ومعالجة دائنها في القيد (الاقتراح: 211 ذمة الخدمة الخارجية) تُعرض
/// على المالك فتُنفذ بكلمته.
library;

import 'invoice.dart' show wacExitValue;

/// ─── مسودات الوصفة ───

/// مكوّن في وصفة تجميعي كما يخرج من نموذج الإدخال: الصنف وكميته
/// بالوحدة الأساسية لكل وحدة تجميعية واحدة، وتكلفة الخدمة اختيارياً
/// (F-212 — للخدمة بالخيارين؛ للبضاعة كلفتها من مخزونها لا من الخانة).
class BundleComponentDraft {
  final int componentItemId;

  /// كمية المكوّن بالوحدة الأساسية داخل وحدة التجميعي الواحدة (س-09:
  /// «كميات كل مكون») — موجبة حصراً.
  final int qtyBase;

  /// تكلفة المكوّن الخدمي بوحدات صغرى أساسية — null أو صفر = بند بيعي
  /// ضمن السعر (F-212). للبضاعة يجب أن تكون null (كلفتها من المتوسط
  /// الحاكم لمخزونها لحظة الفك — F-034).
  final int? costMinor;

  const BundleComponentDraft({
    required this.componentItemId,
    required this.qtyBase,
    this.costMinor,
  });
}

/// وصفة تجميعي كاملة كما تخرج من نموذج الإدخال قبل التحقق.
class BundleRecipeDraft {
  final int bundleItemId;
  final List<BundleComponentDraft> components;

  const BundleRecipeDraft({
    required this.bundleItemId,
    required this.components,
  });
}

/// ─── أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة
/// (نمط الفواتير والمجموعات) ───

sealed class BundleValidationError {
  const BundleValidationError();
}

/// وصفة بلا مكونات — «وصفة فارغة مرفوضة» (س-09) ولا بيع بالفكك بلا
/// وصفة (F-034: النقص يفكك مكوناته بكمياتها).
class BundleRecipeEmpty extends BundleValidationError {
  const BundleRecipeEmpty();
}

/// كمية مكوّن صفر أو سالبة (منع السالب الموحد — س6).
class BundleComponentQtyInvalid extends BundleValidationError {
  final int index;
  final int qtyBase;

  const BundleComponentQtyInvalid(this.index, this.qtyBase);
}

/// المكوّن نفسه مرتين بالوصفة — مدخلة مزدوجة تحرق الكلفة (روح D-074).
class BundleComponentDuplicate extends BundleValidationError {
  final int index;
  final int componentItemId;

  const BundleComponentDuplicate(this.index, this.componentItemId);
}

/// التجميعي مكوّناً في وصفته — دائرة ذاتية مستحيلة.
class BundleSelfComponent extends BundleValidationError {
  final int index;
  final int componentItemId;

  const BundleSelfComponent(this.index, this.componentItemId);
}

/// تكلفة المكوّن غير صالحة: سالبة (س6)، أو بضاعة بخانة تكلفة (كلفة
/// البضاعة من مخزونها الحاكم لا من الخانة — F-034/F-212).
class BundleComponentCostInvalid extends BundleValidationError {
  final int index;
  final int? costMinor;

  const BundleComponentCostInvalid(this.index, this.costMinor);
}

/// ─── أخطاء القاعدة (تبنيها التخزين من معطياته) ───

/// لا صنف بالمعرف لمكوّن الوصفة.
class BundleComponentNotFound extends BundleValidationError {
  final int index;
  final int componentItemId;

  const BundleComponentNotFound(this.index, this.componentItemId);
}

/// مكوّن معطل بالوصفة — «صنف معطل» مرفوض (نمط س-03).
class BundleComponentInactive extends BundleValidationError {
  final int index;
  final String componentLabel;

  const BundleComponentInactive(this.index, this.componentLabel);
}

/// تجميعي داخل وصفة تجميعي — التداخل مرفوض في هذه الدفعة (بضاعة أو
/// خدمة حصراً — والوصفة المتداخلة تحتاج حسم توسيع آلي يُعرض لاحقاً).
class BundleComponentIsBundle extends BundleValidationError {
  final int index;
  final String componentLabel;

  const BundleComponentIsBundle(this.index, this.componentLabel);
}

/// صاحب الوصفة غير صالح: لا صنف بهذا المعرف.
class BundleOwnerNotFound extends BundleValidationError {
  final int bundleItemId;

  const BundleOwnerNotFound(this.bundleItemId);
}

/// صاحب الوصفة صنف معطل.
class BundleOwnerInactive extends BundleValidationError {
  final String ownerLabel;

  const BundleOwnerInactive(this.ownerLabel);
}

/// صاحب الوصفة ليس تجميعياً — الوصفة شأن التجميعي حصراً (F-034).
class BundleOwnerNotBundle extends BundleValidationError {
  final String ownerLabel;

  const BundleOwnerNotBundle(this.ownerLabel);
}

/// الوصفة العربي لأخطاء التحقق — يخدم الاختبارات وصفوف الفشل حصراً؛
/// الواجهة حرية الصياغة (نمط س-36).
String describeBundleValidationError(BundleValidationError error) {
  switch (error) {
    case BundleRecipeEmpty():
      return 'الوصفة بلا مكونات — وصفة فارغة مرفوضة';
    case BundleComponentQtyInvalid(:final index, :final qtyBase):
      return 'المكوّن ${index + 1}: الكمية «$qtyBase» صفر أو سالبة';
    case BundleComponentDuplicate(:final index, :final componentItemId):
      return 'المكوّن ${index + 1}: الصنف $componentItemId مكرر بالوصفة';
    case BundleSelfComponent(:final index, :final componentItemId):
      return 'المكوّن ${index + 1}: التجميعي $componentItemId لا يكون '
          'مكوّناً من نفسه';
    case BundleComponentCostInvalid(:final index, :final costMinor):
      return 'المكوّن ${index + 1}: التكلفة «$costMinor» سالبة — أو '
          'بضاعة بخانة تكلفة وكلفة البضاعة من مخزونها';
    case BundleComponentNotFound(:final index, :final componentItemId):
      return 'المكوّن ${index + 1}: لا صنف بالمعرف $componentItemId';
    case BundleComponentInactive(:final index, :final componentLabel):
      return 'المكوّن ${index + 1}: الصنف «$componentLabel» معطل';
    case BundleComponentIsBundle(:final index, :final componentLabel):
      return 'المكوّن ${index + 1}: «$componentLabel» تجميعي — لا تداخل '
          'تجميعي داخل وصفة (بضاعة أو خدمة حصراً)';
    case BundleOwnerNotFound(:final bundleItemId):
      return 'لا صنف بالمعرف $bundleItemId — الوصفة لصنف قائم';
    case BundleOwnerInactive(:final ownerLabel):
      return 'الصنف «$ownerLabel» معطل — لا وصفة لصنف معطل';
    case BundleOwnerNotBundle(:final ownerLabel):
      return 'الصنف «$ownerLabel» ليس تجميعياً — الوصفة شأن التجميعي '
          'حصراً';
  }
}

/// رفض مدقق الوصفة — يحمل الأخطاء النوعية (نمط InvoiceValidationException).
class BundleValidationException implements Exception {
  final List<BundleValidationError> errors;

  const BundleValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق الوصفة: ${errors.map(describeBundleValidationError).join('؛ ')}';
}

/// المدقق البنيوي للوصفة (قبل أي كتابة — حرس المجال الأول): التفريغ
/// ثم الأسطر سطراً سطراً (الكمية ثم التكلفة ثم التكرار والذاتية).
/// فحوص القاعدة (الوجود والتفعيل والنوع) شأن التخزين — وأنواعها أعلاه.
List<BundleValidationError> validateBundleRecipeStructure(
  BundleRecipeDraft draft,
) {
  final errors = <BundleValidationError>[];
  if (draft.components.isEmpty) {
    errors.add(const BundleRecipeEmpty());
    return errors;
  }
  final seen = <int>{};
  for (var i = 0; i < draft.components.length; i++) {
    final c = draft.components[i];
    if (c.qtyBase <= 0) {
      errors.add(BundleComponentQtyInvalid(i, c.qtyBase));
      continue;
    }
    if (c.costMinor != null && c.costMinor! < 0) {
      errors.add(BundleComponentCostInvalid(i, c.costMinor));
      continue;
    }
    if (seen.contains(c.componentItemId)) {
      errors.add(BundleComponentDuplicate(i, c.componentItemId));
      continue;
    }
    seen.add(c.componentItemId);
    if (c.componentItemId == draft.bundleItemId) {
      errors.add(BundleSelfComponent(i, c.componentItemId));
    }
  }
  return errors;
}

/// ─── مخطط بيع التجميعي — الجاهز أولاً ثم الفك (F-034 حرفاً) ───

/// مدخل مخطط البيع لكل مكون كما تقدمه التخزين من قاعدة الحاضر:
/// كمية الوصفة لكل وحدة تجميعية وتكلفة الخدمة إن كانت خدمة، ورصيد
/// البضاعة وقيمته الحاليان في المستودع (للخدمة صفران دائماً — F-212).
class BundleComponentStockInput {
  final int itemId;
  final bool isService;
  final int qtyPerBundle;

  /// تكلفة الخدمة لكل وحدة تجميعية (F-212) — للبضاعة null دائماً.
  final int? serviceCostMinor;

  /// رصيد البضاعة وقيَمه في المستودع لحظة التخطيط — تُقدَّم من محرك
  /// الفواتير فتطابق كتابة الترحيل حرفاً (نمط _StockSim).
  final int stockQty;
  final int stockValue;

  const BundleComponentStockInput({
    required this.itemId,
    required this.isService,
    required this.qtyPerBundle,
    this.serviceCostMinor,
    this.stockQty = 0,
    this.stockValue = 0,
  });
}

/// خطة مكون واحد عند الفك: البضاعة تخرج بكميتها وقيَمها الحاوية،
/// والخدمة بلا حركة وتكلفتها لكل وحدة تحمل على المركب (F-212).
class BundleSaleComponentPlan {
  final int itemId;
  final bool isService;

  /// كمية خروج البضاعة (صفر للخدمة — لا حركة مخزون في الحالتين).
  final int qtyOut;

  /// قيمة خروج البضاعة بالمتوسط الحاكم، أو تكلفة الخدمة المحمولة
  /// (التكلفة × الكمية المفككة — F-212).
  final int valueMinor;

  const BundleSaleComponentPlan({
    required this.itemId,
    required this.isService,
    required this.qtyOut,
    required this.valueMinor,
  });
}

/// خطة بيع سطر تجميعي كاملة — الجاهز والفكك وتكاليفها الثلاثة:
///
/// - [inventoryCostMinor]: خروج الجاهز + خروج مكونات البضاعة — هي
///   القيمة المخزنية المحمولة على القيد (51 مدين / 113 دائن بحركاتها)
///   كي يستقر F-178.
/// - [serviceCostMinor]: مجموع تكاليف الخدمات المفككة — بالمجال
///   والتكلفة المركبة (F-212)، ومعالجة قيدها مقترحة على المالك (D-190).
/// - [compositeCostMinor]: المركب الحرفي لسطر التكلفة الواحد
///   (F-034: «سطر تكلفة واحد بالمبلغ المركب») — مجموع الاثنين.
class BundleSalePlan {
  final int saleQty;

  /// ما خرج جاهزاً من رصيد التجميعي، وما فُكك من مكوناته.
  final int readyQty;
  final int brokenQty;

  /// قيمة خروج الجاهز بالمتوسط الحاكم (F-047/D-067) — والخروج بكل
  /// الرصيد يمتص قيمته كلها.
  final int readyValueMinor;
  final List<BundleSaleComponentPlan> components;

  int get inventoryCostMinor {
    var sum = readyValueMinor;
    for (final c in components) {
      if (!c.isService) sum += c.valueMinor;
    }
    return sum;
  }

  int get serviceCostMinor {
    var sum = 0;
    for (final c in components) {
      if (c.isService) sum += c.valueMinor;
    }
    return sum;
  }

  int get compositeCostMinor => inventoryCostMinor + serviceCostMinor;

  const BundleSalePlan({
    required this.saleQty,
    required this.readyQty,
    required this.brokenQty,
    required this.readyValueMinor,
    required this.components,
  });
}

/// ─── أخطاء اكتفاء الفك — تضيفها التخزين إلى أخطاء الفاتورة ───

sealed class BundleSaleError {
  const BundleSaleError();
}

/// بيع يزيد على الجاهز بلا وصفة — لا نقص يُفكك بلا مكونات (س-09:
/// «وصفة فارغة مرفوضة» روحاً).
class BundleSaleRecipeRequired extends BundleSaleError {
  const BundleSaleRecipeRequired();
}

/// مكوّن بضاعة رصيده لا يكفي الكمية المفككة — منع السالب على
/// المكونات (س-09/F-042)، ويحمل المطلوب والمتاح.
class BundleSaleComponentInsufficient extends BundleSaleError {
  final int componentItemId;
  final int neededQty;
  final int availableQty;

  const BundleSaleComponentInsufficient({
    required this.componentItemId,
    required this.neededQty,
    required this.availableQty,
  });
}

/// حصيلة التخطيط — الخطة والأخطاء معاً (نمط المدققين: القائمة فارغة =
/// سليم والخطة كاملة القيم فالكتابة تكرر المحاكاة حرفاً).
class BundleSalePlanOutcome {
  final BundleSalePlan plan;
  final List<BundleSaleError> errors;

  const BundleSalePlanOutcome({required this.plan, required this.errors});
}

/// مخطط بيع التجميعي — دالة نقية تعيد الخطة وأخطاء الاكتفاء:
///
/// - الجاهز أولاً: خروج `min(البيع, رصيد التجميعي)` بتكلفته المخزنية
///   الحاكمية، والخروج بكل الرصيد يمتص القيمة كلها (D-067).
/// - النقص يفكك: كل مكون بضاعة يحتاج `كمية الوصفة × المفكك` من رصيد
///   الحاضر المقدم — ويخرج بالمتوسط المتسلسل (D-067) بالنصف بعيداً
///   عن الصفر (س7).
/// - مكون الخدمة بلا حركة: تكلفتها × المفكك تدخل المركب إن قُيمت
///   (F-212) وصفراً إن كانت بنداً بيعياً.
/// - البيع كلُّه من الجاهز لا يمس المكونات ولا يطلب وصفة — والنقص
///   بلا وصفة خطأ [BundleSaleRecipeRequired].
BundleSalePlanOutcome planBundleSaleBreakdown({
  required int saleQtyBase,
  required int bundleReadyQty,
  required int bundleReadyValue,
  required List<BundleComponentStockInput> components,
}) {
  assert(saleQtyBase > 0, 'كمية البيع موجبة حصراً');
  assert(bundleReadyQty >= 0, 'رصيد الجاهز غير سالب');
  assert(bundleReadyValue >= 0, 'قيمة الجاهز غير سالبة');

  final readyQty =
      saleQtyBase <= bundleReadyQty ? saleQtyBase : bundleReadyQty;
  final brokenQty = saleQtyBase - readyQty;
  final readyValue =
      wacExitValue(bundleReadyValue, bundleReadyQty, readyQty);

  final plans = <BundleSaleComponentPlan>[];
  final errors = <BundleSaleError>[];

  if (brokenQty > 0 && components.isEmpty) {
    errors.add(const BundleSaleRecipeRequired());
  }

  for (final c in components) {
    if (c.isService) {
      // F-212: بلا حركة مخزون في الحالتين — والتكلفة × المفكك تُحمَل
      // على المركب إن قُيمت (الفراغ = بند بيعي ضمن السعر).
      final cost = (c.serviceCostMinor ?? 0) * brokenQty;
      plans.add(BundleSaleComponentPlan(
        itemId: c.itemId,
        isService: true,
        qtyOut: 0,
        valueMinor: cost,
      ));
      continue;
    }
    if (brokenQty == 0) continue; // لا فكك — المكونات بلا مساس
    final needed = c.qtyPerBundle * brokenQty;
    if (needed > c.stockQty) {
      errors.add(BundleSaleComponentInsufficient(
        componentItemId: c.itemId,
        neededQty: needed,
        availableQty: c.stockQty,
      ));
      continue;
    }
    final exit = wacExitValue(c.stockValue, c.stockQty, needed);
    plans.add(BundleSaleComponentPlan(
      itemId: c.itemId,
      isService: false,
      qtyOut: needed,
      valueMinor: exit,
    ));
  }

  return BundleSalePlanOutcome(
    plan: BundleSalePlan(
      saleQty: saleQtyBase,
      readyQty: readyQty,
      brokenQty: brokenQty,
      readyValueMinor: readyValue,
      components: plans,
    ),
    errors: errors,
  );
}
