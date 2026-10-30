/// الأصناف والوحدات في دِقَّة — منطق نقي حصراً بلا Flutter ولا Drift (F-010، 07 §1.8).
///
/// دفعة م1 الثانية (06 §1-ج، س-36..س-41) على المتطلبات F-030/F-031/F-035.
///
/// القرارات الحاكمة الموثقة (README-v2.01 §3):
/// - D-073: هوية الصنف معرّفه الآلي `id` (الفواتير لاحقاً تحيل به)، و
///   `sku` نص فريد **لا يعدل بعد الحفظ** — «الأساس هو الرقم» روح D-062
///   معكوسةً على الأصناف: كود الصنف هو ما يقوله الباعة حين يسألون عن
///   «الصنف رقم كذا»، فتثبيته كرقم الطرف هو الاتساق المالك. والتفرد هنا
///   حرفي بلا نزع أصفار — نزع الأصفار والترتيب الرقمي والتوليد الآلي
///   قرارات أطراف خاصة (D-063) لا تصح إسقاطها على كود متنوع («A-12»
///   كود مشروع كما هو).
/// - D-074: منع تكرار الاسم المطابق حرفياً للأصناف والوحدات — تمديد
///   روح D-065: الصنفان المتشابهان في الاسم مدخلة مزدوجة تحرق التقارير
///   والكلفة لاحقاً. والعرض «الاسم (الكود)» نفسه.
/// - D-066 الاصطلاح: عملة السعر لا تخزن فارغة أبداً — معبأة بالافتراضية
///   دوماً (المعتمد نفسه في الأطراف، وسطر party.dart الموثق يقرره
///   للأصناف من البداية).
///
/// الحدود الصادقة (09 §2): التجميعي ووحدات التعبئة م2 (F-032/F-034) —
/// م1 الإدخال بالوحدة الأساسية فقط، والوحدة هنا «وحدة أساسية» باسمها
/// وإلزاميتها (F-031) لا مجموعة تعبئة.

/// نوع الصنف (05 §3.2): بضاعة تخزونية، أو خدمة بلا مخزون، أو تجميعي —
/// `bundle` بنية مخطط جاهزة والواجهة في م1 تعرض البضاعة والخدمة حصراً
/// (F-034 م2).
enum ItemKind {
  good('good', 'بضاعة'),
  service('service', 'خدمة'),
  bundle('bundle', 'تجميعي');

  final String storageValue;
  final String label;

  const ItemKind(this.storageValue, this.label);

  static ItemKind fromStorage(String value) {
    for (final k in ItemKind.values) {
      if (k.storageValue == value) return k;
    }
    throw ArgumentError('نوع صنف غير معروف: $value');
  }
}

/// صيغة العرض المعتمدة في القوائم (D-074/س-36): «الاسم (الكود)».
String itemDisplayLabel(String name, String sku) => '$name ($sku)';

/// مفتاح تفرد الكود (D-073): تقليم الفراغات الطرفية حصراً — بلا نزع
/// أصفار ولا ترتيب رقمي (قرارات أطراف D-063 خاصة بالتسلسل الرقمي للطرف
/// لا بكود صنف متنوع).
String itemSkuKey(String raw) => raw.trim();

/// حقول الصنف القابلة للبحث الجامع (س-38، D-064 نفسه): الاسم والكود
/// والتصنيف — والتطبيع العربي للبحث حصراً دالة الأطراف النقية ذاتها.
class ItemSearchFields {
  final String name;
  final String sku;
  final String category;

  const ItemSearchFields({
    required this.name,
    required this.sku,
    this.category = '',
  });

  /// مطابقة «كلمات متفرقة تلتقي» (D-064): كل كلمة مكتوبة تجد موضعها في
  /// الاسم أو الكود أو التصنيف بأي ترتيب — «زيت 100» تجيء بـ«زيت محلي
  /// (100)» فيكفي. الخانة الفارغة تجيء بالجميع.
  bool matchesQuery(String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .map(normalizeArabicForSearch)
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return true;
    final nameN = normalizeArabicForSearch(name);
    final skuN = normalizeArabicForSearch(sku);
    final categoryN = normalizeArabicForSearch(category);
    for (final token in tokens) {
      final hit =
          nameN.contains(token) || skuN.contains(token) || categoryN.contains(token);
      if (!hit) return false;
    }
    return true;
  }
}

/// صورة صنف قائم للتحقق والفهرسة — بلا أي اعتماد تخزين أو واجهة.
class ExistingItem {
  final int id;
  final String sku;
  final String name;
  final bool isActive;

  const ExistingItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.isActive,
  });

  /// مفتاح التفرد الحرفي بعد تقليم الفراغات (D-073).
  String get skuKey => itemSkuKey(sku);

  /// العرض المعتمد «الاسم (الكود)» — تحمله رسائل الرفض تري صاحبها (س-36).
  String get displayLabel => itemDisplayLabel(name, sku);
}

/// مسودة صنف كما تخرج من نموذج الإدخال قبل التحقق — قيم خام غير مقلمة.
class ItemDraft {
  final String sku;
  final String name;
  final String category;

  /// good / service في م1 (التجميعي م2 — F-034).
  final ItemKind kind;

  /// معرّف الوحدة الأساسية — إلزامي (F-031: تُختار من قائمة الوحدات،
  /// والصفر أو السالب يعني «لم تُختر»).
  final int baseUnitId;

  /// الأسعار بوحدات صغرى صحيحة حصراً (س7) — الصفر مشروع «بلا سعر بعد»،
  /// والسالب مرفوض (س6: لا سعر سالب).
  final int purchasePriceMinor;
  final int salePriceMinor;

  /// عملة السعر — معبأة مسبقاً بالعملة الأساسية ولا تصل التخزين صفراً
  /// (D-066 الاصطلاح؛ القيمة 1 هي الأساسية D-017 حتى تُبنى جدول
  /// العملات في دفعته).
  final int currencyId;

  const ItemDraft({
    required this.sku,
    required this.name,
    this.category = '',
    required this.kind,
    required this.baseUnitId,
    this.purchasePriceMinor = 0,
    this.salePriceMinor = 0,
    this.currencyId = 1,
  });
}

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة: الواجهة وحدها
/// تقرر الصياغة المعروضة (فصل المجال عن العرض).
sealed class ItemValidationError {
  const ItemValidationError();
}

/// بلا اسم — الاسم إلزامي وحده (س-36، نمط س-29).
class ItemNameRequired extends ItemValidationError {
  const ItemNameRequired();
}

/// بلا كود — الكود إلزامي (F-030) وهو الأساس الذي يُنادى به الصنف (D-073).
class ItemSkuRequired extends ItemValidationError {
  const ItemSkuRequired();
}

/// كود مكرر — يحمل الكود المكرر وعرض الصنف القائم:
/// «الكود 101 مستخدم للصنف: زيت (101)» (س-36).
class ItemSkuTaken extends ItemValidationError {
  final String duplicateSku;
  final String existingLabel;

  const ItemSkuTaken(this.duplicateSku, this.existingLabel);
}

/// اسم مطابق حرفياً لصنف قائم (D-074 — منع لا تنبيه، تمديد D-065).
class ItemNameTaken extends ItemValidationError {
  final String existingLabel;

  const ItemNameTaken(this.existingLabel);
}

/// بلا وحدة أساسية — الوحدة إلزامية بالاختيار من قائمة الوحدات (F-031).
class ItemUnitMissing extends ItemValidationError {
  const ItemUnitMissing();
}

/// عملة تصل صفراً أو سالباً (D-066: لا فراغ للعملة بل تعبئة الافتراضية).
class ItemCurrencyMissing extends ItemValidationError {
  const ItemCurrencyMissing();
}

/// سعر سالب مُدخل — الشراء أو البيع (س6: لا سعر سالب؛ والصفر مشروع).
class ItemPriceInvalid extends ItemValidationError {
  const ItemPriceInvalid();
}

/// فهرس التفرد للأصناف القائمة: بالكود الحرفي بعد تقليم الفراغات حصراً
/// (D-073) وبالاسم الحرفي بعد تقليم الفراغات حصراً بلا أي تطبيع (D-074).
class ItemUniquenessIndex {
  final Map<String, ExistingItem> _bySku;
  final Map<String, ExistingItem> _byLiteralName;

  const ItemUniquenessIndex._(this._bySku, this._byLiteralName);

  factory ItemUniquenessIndex.build(Iterable<ExistingItem> items) {
    final bySku = <String, ExistingItem>{};
    final byName = <String, ExistingItem>{};
    for (final item in items) {
      // أول صنف يفوز بالفهرسة — الفهرس أداة تحقق لا إصلاح تاريخ.
      bySku.putIfAbsent(item.skuKey, () => item);
      final nameKey = item.name.trim();
      if (nameKey.isNotEmpty) byName.putIfAbsent(nameKey, () => item);
    }
    return ItemUniquenessIndex._(bySku, byName);
  }

  ExistingItem? bySkuKey(String rawSku) => _bySku[itemSkuKey(rawSku)];

  ExistingItem? byLiteralName(String rawName) => _byLiteralName[rawName.trim()];
}

/// التحقق قبل الحفظ (س-36/س-39) — يعيد قائمة الأخطاء (فارغة = سليم).
///
/// - [excludeItemId] للتعديل: يستثني الصنف من فحص التكرار ضد نفسه.
/// - الكود لا يعدل بعد الحفظ أصلاً (D-073) فمصدره في التعديل يظل كما هو
///   والبطاقة تقفل حقلَه — كما الرقم في الأطراف (س-32).
/// - المعطل يبقى في الفهرس: التعطيل لا يحذف أصلاً (س-40) فاسمه وكوده
///   محجوزان ما دام الصف حياً.
List<ItemValidationError> validateItemDraft(
  ItemDraft draft, {
  required ItemUniquenessIndex existing,
  int? excludeItemId,
}) {
  final errors = <ItemValidationError>[];
  final name = draft.name.trim();
  final sku = draft.sku.trim();

  if (name.isEmpty) errors.add(const ItemNameRequired());
  if (sku.isEmpty) errors.add(const ItemSkuRequired());
  if (draft.baseUnitId <= 0) errors.add(const ItemUnitMissing());
  if (draft.currencyId <= 0) errors.add(const ItemCurrencyMissing());
  if (draft.purchasePriceMinor < 0 || draft.salePriceMinor < 0) {
    errors.add(const ItemPriceInvalid());
  }

  if (sku.isNotEmpty) {
    final holder = existing.bySkuKey(sku);
    if (holder != null && holder.id != excludeItemId) {
      errors.add(ItemSkuTaken(sku, holder.displayLabel));
    }
  }
  if (name.isNotEmpty) {
    final holder = existing.byLiteralName(name);
    if (holder != null && holder.id != excludeItemId) {
      errors.add(ItemNameTaken(holder.displayLabel));
    }
  }
  return errors;
}

/// صورة وحدة قائمة للتحقق — المقياس الوحيد في م1: الاسم الحرفي فريد
/// (D-074) ولا وحدة بلا اسم (F-031).
class ExistingUnit {
  final int id;
  final String name;
  final bool isActive;

  const ExistingUnit({
    required this.id,
    required this.name,
    required this.isActive,
  });
}

/// بلا اسم للوحدة — إضافة وحدة باسم فارغ مرفوضة (س-41/F-031).
class UnitNameRequired extends ItemValidationError {
  const UnitNameRequired();
}

/// اسم وحدة مطابق حرفياً لوحدة قائمة (D-074) — يحمل عرض الوحدة القائمة.
class UnitNameTaken extends ItemValidationError {
  final String existingName;

  const UnitNameTaken(this.existingName);
}

/// فهرس أسماء الوحدات الحرفي (D-074) — المعطل غير موجود في الوحدات: م1
/// إضافة حصراً بلا تعطيل (قرار D-075: البساطة لا تضيف مساراً لا يستخدم).
class UnitUniquenessIndex {
  final Map<String, ExistingUnit> _byLiteralName;

  const UnitUniquenessIndex._(this._byLiteralName);

  factory UnitUniquenessIndex.build(Iterable<ExistingUnit> units) {
    final byName = <String, ExistingUnit>{};
    for (final unit in units) {
      final nameKey = unit.name.trim();
      if (nameKey.isNotEmpty) byName.putIfAbsent(nameKey, () => unit);
    }
    return UnitUniquenessIndex._(byName);
  }

  ExistingUnit? byLiteralName(String rawName) => _byLiteralName[rawName.trim()];
}

/// التحقق قبل إضافة وحدة (س-41) — اسم مقلم غير فارغ وفريد حرفياً.
List<ItemValidationError> validateUnitName(
  String rawName, {
  required UnitUniquenessIndex existing,
}) {
  final errors = <ItemValidationError>[];
  final name = rawName.trim();
  if (name.isEmpty) {
    errors.add(const UnitNameRequired());
  } else {
    final holder = existing.byLiteralName(name);
    if (holder != null) {
      errors.add(UnitNameTaken(holder.name));
    }
  }
  return errors;
}
