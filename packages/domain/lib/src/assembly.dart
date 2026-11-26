/// مستند التجميع (F-211 — الدفعة 29، سادسة م2، س88).
///
/// النص المعتمد الحاكم (س81 — F-211 بـ04 §17): مكونات من رصيد المستودع
/// ← سلل جاهزة بالوصفة بكمياتها؛ تكلفة الناتج مجموع كلف المكونات
/// المسحوبة؛ **بلا قيد محاسبي** — نقل قيمة بين أصناف داخل 113 (الثابت
/// F-178 محفوظ) بروح النقل بين المستودعات؛ فحص توفر المكونات (F-042)؛
/// وموضعه الشاشي داخل بطاقة المخزون زراً خامساً مع إذنَي الإدخال/الإخراج
/// والنقل والجرد — وخارج فاتورة الشراء حصراً (دمجه فيها مرفوض: خلط
/// بابي الشراء والإنتاج — س81).
///
/// الفحص البنيوي خالص هنا — لا قاعدة ولا واجهة (نمط إذني المخزون
/// والتحويل والجرد: المدقق البنيوي بالمجال والفحوص المحركية بالتخزين
/// على ما خُزّن لا على ما قيل).
///
/// الحدود الموثقة:
/// - المستند يُنشأ مرحّلاً مباشرة بلا مسودة (نمط س-18: الرفض قبل
///   الكتابة حصراً — والتجميع فعلٌ آني بلا ذمة وسيطة تحتاجها).
/// - الوصفة إلزامية: تجميعي بلا وصفة مرفوض (س-09: «وصفة فارغة
///   مرفوضة» روحاً — ولا جمّع بلا وصفة F-034).
/// - مكونات البضاعة تُسحب بالوصفة × عدد الوحدات المنتجة بالوحدة
///   الأساسية حصراً (لقطة الوحدة س-10 ببنيتها المحسومة دفعة تالية).
/// - **مكوّن الخدمة لا يُسحب في التجميع** (F-212 — حد صادق معروض مع
///   D-190): لا مخزون له ولا قيمة داخل 113، وقيمته من صميم البيع
///   لا البناء — فتظل قيمة الناتج مجموع كلف المكونات المسحوبة
///   المخزنية حصراً ويثبت F-178 حرفاً.
/// - التاريخ بتقويم الميلاد ISO حصراً (D-077)، وبلا حاجز فترة:
///   التجميع بلا قيد فأرصدته حالية لا تاريخية — عين قرار التحويل
///   الموثق D-185 (س78).
library;

/// مسودة مستند تجميع — تُرحَّل مباشرة بلا مسودة (نمط س-18).
///
/// [qtyBundles] عدد الوحدات المنتجة من الصنف التجميعي (عدد السلل
/// مثلًا) — موجبة حصراً، والمكونات تُسحب بكميات الوصفة × هذا العدد.
class AssemblyDraft {
  final String dateText;
  final int warehouseId;

  /// الصنف التجميعي صاحب الوصفة (F-211: الناتج بالوصفة بكمياتها).
  final int bundleItemId;

  /// عدد الوحدات المنتجة — موجب حصراً، وهو بالمخزونية (الأساسية)
  /// دائماً — والوصفة تُسحب بأعدادها بالأساسية نص F-211 ثابت.
  final int qtyBundles;

  /// س115: لقطة الناتج بالتعبئة — معرف مستوى مجموعة التجميعي والعدد
  /// المدخل بوحدته وعامل اللقطة (نمط الفواتير س89 والإذنين والتحويل
  /// س113) — والفراغ إدخال بالأساسية كما اعتاد، والوصفة بالأساسية
  /// نص F-211 ثابت لا مساس بها.
  final int? unitLevelId;
  final int? qtyDoc;
  final int? factorAtEntry;

  const AssemblyDraft({
    required this.dateText,
    required this.warehouseId,
    required this.bundleItemId,
    required this.qtyBundles,
    this.unitLevelId,
    this.qtyDoc,
    this.factorAtEntry,
  });
}

/// أخطاء رفض مستند التجميع — البنيوية والمحركية منبع واحد بسجل
/// رسائل عربي واحد ببادئة Assembly (درس تصادم الأسماء س79/س85:
/// أنواع بيانات لا نصوص جاهزة، وسجل وصاف لا صياغة واجهة موازية).
sealed class AssemblyValidationError {
  const AssemblyValidationError();
}

class AssemblyDateInvalid extends AssemblyValidationError {
  final String dateText;

  const AssemblyDateInvalid(this.dateText);
}

/// كمية الناتج صفر أو سالبة — لا تجميع بلا ناتج (منع الصفر الموحد).
class AssemblyQtyInvalid extends AssemblyValidationError {
  final int qtyBundles;

  const AssemblyQtyInvalid(this.qtyBundles);
}

class AssemblyWarehouseMissing extends AssemblyValidationError {
  final int warehouseId;

  const AssemblyWarehouseMissing(this.warehouseId);
}

class AssemblyWarehouseInactive extends AssemblyValidationError {
  final String warehouseName;

  const AssemblyWarehouseInactive(this.warehouseName);
}

class AssemblyBundleItemMissing extends AssemblyValidationError {
  final int bundleItemId;

  const AssemblyBundleItemMissing(this.bundleItemId);
}

class AssemblyBundleItemInactive extends AssemblyValidationError {
  final String bundleLabel;

  const AssemblyBundleItemInactive(this.bundleLabel);
}

/// الصنف المختار ليس تجميعياً — الوصفة شأن التجميعي حصراً (F-034).
class AssemblyBundleItemNotBundle extends AssemblyValidationError {
  final String bundleLabel;

  const AssemblyBundleItemNotBundle(this.bundleLabel);
}

/// تجميعي بلا وصفة — لا جمّع بلا وصفة (س-09/F-034).
class AssemblyRecipeRequired extends AssemblyValidationError {
  const AssemblyRecipeRequired();
}

class AssemblyComponentMissing extends AssemblyValidationError {
  final int index;
  final int componentItemId;

  const AssemblyComponentMissing(this.index, this.componentItemId);
}

class AssemblyComponentInactive extends AssemblyValidationError {
  final int index;
  final String componentLabel;

  const AssemblyComponentInactive(this.index, this.componentLabel);
}

/// تجميعي داخل وصفة تجميع — التداخل مرفوض كما في الوصفة ذاتها
/// (بضاعة أو خدمة حصراً — س80/الدفعة 28).
class AssemblyComponentIsBundle extends AssemblyValidationError {
  final int index;
  final String componentLabel;

  const AssemblyComponentIsBundle(this.index, this.componentLabel);
}

/// مكوّن بضاعة رصيده لا يكفي الكمية المطلوبة — منع السالب على
/// المكونات (F-042)، ويحمل المطلوب والمتاح.
class AssemblyComponentInsufficient extends AssemblyValidationError {
  final int index;
  final String componentLabel;
  final int neededQty;
  final int onHandQty;

  const AssemblyComponentInsufficient({
    required this.index,
    required this.componentLabel,
    required this.neededQty,
    required this.onHandQty,
  });
}

/// س115: مستوى التعبئة بعدد الناتج غير صالح — لا ينتمي لمجموعة
/// التجميعي أو العدد المدخل لا يطابق عامل المستوى (نمط حرس الفواتير
/// س89 والإذنين والتحويل س113) — والوصفة بالأساسية نص F-211 ثابت.
class AssemblyLevelInvalid extends AssemblyValidationError {
  final String bundleLabel;

  const AssemblyLevelInvalid(this.bundleLabel);
}

/// الفحص البنيوي الخالص — قواعد F-211 التي لا تحتاج قاعدة بيانات.
/// فحوص القاعدة (الوجود والتفعيل والنوع والاكتفاء) شأن التخزين على
/// ما خُزّن — وأنواعها أعلاه.
List<AssemblyValidationError> validateAssemblyStructure(
    AssemblyDraft draft) {
  final errors = <AssemblyValidationError>[];
  if (!_isValidIsoDate(draft.dateText)) {
    errors.add(AssemblyDateInvalid(draft.dateText));
  }
  if (draft.qtyBundles <= 0) {
    errors.add(AssemblyQtyInvalid(draft.qtyBundles));
  }
  if (draft.warehouseId <= 0) {
    errors.add(AssemblyWarehouseMissing(draft.warehouseId));
  }
  if (draft.bundleItemId <= 0) {
    errors.add(AssemblyBundleItemMissing(draft.bundleItemId));
  }
  return errors;
}

/// صورة تاريخ ISO بسيطة (YYYY-MM-DD) — نمط الميلاد الموحد (D-077):
/// التطابق البنيوي فقط، والفترة الزمنية بيد التخزين والواجهة.
bool _isValidIsoDate(String value) {
  final m = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(value.trim());
  if (m == null) return false;
  final parts = value.trim().split('-');
  final month = int.tryParse(parts[1]) ?? 0;
  final day = int.tryParse(parts[2]) ?? 0;
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

/// سجل الرسائل العربية الواحد — رسالة المالك الصادقة بأول خطأ تُعرض
/// من هنا لا تُصاغ بالواجهة (نمط إذني المخزون والتحويل والجرد).
String describeAssemblyValidationError(AssemblyValidationError error) =>
    switch (error) {
      AssemblyDateInvalid(:final dateText) =>
        'تاريخ التجميع «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)',
      AssemblyQtyInvalid(:final qtyBundles) =>
        'كمية الناتج «$qtyBundles» صفر أو سالبة — حدد عدد الوحدات '
            'المنتجة بالوحدة الأساسية',
      AssemblyWarehouseMissing(:final warehouseId) =>
        'مستودع التجميع (المعرف $warehouseId) غير معروف',
      AssemblyWarehouseInactive(:final warehouseName) =>
        'المستودع «$warehouseName» معطل — يختفي من الاختيار',
      AssemblyBundleItemMissing(:final bundleItemId) =>
        'الصنف التجميعي (المعرف $bundleItemId) غير معروف',
      AssemblyBundleItemInactive(:final bundleLabel) =>
        'الصنف «$bundleLabel» معطل — يختفي من الاختيار',
      AssemblyBundleItemNotBundle(:final bundleLabel) =>
        'الصنف «$bundleLabel» ليس تجميعياً — التجميع بأصنافه صاحبة '
            'الوصفة حصراً',
      AssemblyRecipeRequired() =>
        'الصنف التجميعي بلا وصفة مكونات — لا تجميع بلا وصفة '
            'فاكتب وصفته من بطاقة الصنف أولاً',
      AssemblyComponentMissing(:final index, :final componentItemId) =>
        'مكوّن الوصفة ${index + 1} (المعرف $componentItemId) غير معروف',
      AssemblyComponentInactive(:final index, :final componentLabel) =>
        'المكوّن ${index + 1} «$componentLabel» معطل — أصل وصفته أولاً',
      AssemblyComponentIsBundle(:final index, :final componentLabel) =>
        'المكوّن ${index + 1} «$componentLabel» تجميعي — لا تداخل '
            'تجميعي داخل وصفة (بضاعة أو خدمة حصراً)',
      AssemblyComponentInsufficient(
        :final index,
        :final componentLabel,
        :final neededQty,
        :final onHandQty,
      ) =>
        'المكوّن ${index + 1} «$componentLabel» رصيده بالمستودع '
            '$onHandQty والمطلوب $neededQty — منع السالب',
      AssemblyLevelInvalid(:final bundleLabel) =>
        'مستوى التعبئة للناتج «$bundleLabel» غير صالح — لا ينتمي '
            'لمجموعة الصنف أو العدد المدخل لا يطابق عامل المستوى '
            '— والوصفة بالأساسية ثابتة',
    };

/// استثناء رفض التجميع — تحمل القائمة كاملة والعرض بأول وصف (نمط س-36).
class AssemblyValidationException implements Exception {
  final List<AssemblyValidationError> errors;

  const AssemblyValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق مستند التجميع: '
      '${errors.map(describeAssemblyValidationError).join('؛ ')}';
}

/// أول وصف عربي للقائمة — أدوات الواجهة تعرضه حصراً (نمط «رسالة واحدة
/// أول خطأ»).
String firstAssemblyError(List<AssemblyValidationError> errors) =>
    errors.isEmpty
        ? 'لا خطأ'
        : describeAssemblyValidationError(errors.first);
