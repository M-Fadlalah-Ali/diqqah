/// مجموعات التعبئة وأسعارها آلي — F-032/F-033/F-208 (الدفعة 27).
///
/// القرارات الحاكمة الموثقة:
/// - D-026: قوالب (قطعة/علبة/كرتونة) أمثلة مقترحة غير حصرية يضيف
///   المستخدم ما يشابه ومستوياته الأعلى، والعامل ثابت بعد وجود حركات
///   (وحدة جديدة بدل التعديل — F-033).
/// - D-187 (س84): مربع «آلي» وحده ببطاقة الصنف افتراضه مفعّل —
///   مفعّلاً يكون تسعير الوحدة الصغرى فقط متاحاً للكتابة والبقية
///   للقراءة تُشتق من الأساس بعوامل التحويل، وبتعطيله تتاح كل حقول
///   الأسعار للكتابة، وإعادة تفعيله بعد تسعير يدوي تعيد الاشتقاق
///   وتستبدل قيم المستويات الأعلى (أثر معلن).
/// - تقاطع F-165 باقٍ: الرفع الجماعي يرفع الأساس فيُعاد اشتقاق
///   المشتق آلياً (النسبة ذاتها تنتقل بذاتها) ويُضرب كل خانة غير
///   مشتقة بالنسبة نفسها — مع سطر تحذير بالمعاينة عند انكسار علاقة
///   السعر بالكمية.
library;

import 'invoice.dart' show roundHalfAwayFromZeroRatio;

/// مستوى تعبئة كما يخرج من نموذج الإدخال — اسم وعامل تحويل صحيح نحو
/// الوحدة الأساسية. العامل ≥2 حصراً: الأساسية عاملها 1 بذاتها (05)
/// ولا تُخزن مستوى.
class UnitGroupLevelSpec {
  final String name;
  final int factor;

  const UnitGroupLevelSpec({required this.name, required this.factor});
}

/// مسودة مجموعة تعبئة كاملة كما تخرج من نموذج الإنشاء قبل التحقق.
class UnitGroupSpec {
  final String name;
  final List<UnitGroupLevelSpec> levels;

  const UnitGroupSpec({required this.name, this.levels = const []});
}

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة: الواجهة وحدها
/// تقرر الصياغة المعروضة (فصل المجال عن العرض — نمط item.dart).
sealed class UnitGroupValidationError {
  const UnitGroupValidationError();
}

/// بلا اسم للمجموعة — الاسم إلزامي (F-032).
class UnitGroupNameRequired extends UnitGroupValidationError {
  const UnitGroupNameRequired();
}

/// اسم مجموعة مطابق حرفياً لمجموعة قائمة (D-074) — يحمل الاسم القائم.
class UnitGroupNameTaken extends UnitGroupValidationError {
  final String existingName;

  const UnitGroupNameTaken(this.existingName);
}

/// مجموعة بلا مستويات — لا معنى لمجموعة تعبئة لا تعبئ شيئاً (F-032:
/// «مجموعات تعبئة بمستويات متعددة»).
class UnitGroupLevelsMissing extends UnitGroupValidationError {
  const UnitGroupLevelsMissing();
}

/// مستوى بلا اسم (فهرسه [index] من الصفر) — الاسم إلزامي لكل مستوى.
class UnitGroupLevelNameRequired extends UnitGroupValidationError {
  final int index;

  const UnitGroupLevelNameRequired(this.index);
}

/// اسمان لمستويين متطابقان حرفياً داخل المجموعة ذاتها (D-074) — يحمل
/// الاسم المتكرر.
class UnitGroupLevelNameDuplicate extends UnitGroupValidationError {
  final String name;

  const UnitGroupLevelNameDuplicate(this.name);
}

/// عامل غير صحيح — ليس عدداً صحيحاً ≥2 (النص الخام يُحمل ليُعرض) أو
/// وحدة بلا عامل أصلاً.
class UnitGroupFactorInvalid extends UnitGroupValidationError {
  final String raw;
  final int index;

  const UnitGroupFactorInvalid(this.raw, this.index);
}

/// عاملا مستويين متساويان داخل المجموعة — وحدتان بحجم واحد دخلة مزدوجة
/// تحرق اختيار المستخدم فلا معنى لهما (علبة 12 وكرتونة 12 في مجموعة
/// واحدة رفض صريح).
class UnitGroupFactorDuplicate extends UnitGroupValidationError {
  final int factor;

  const UnitGroupFactorDuplicate(this.factor);
}

/// قراءة عامل من نص نموذج — عدد صحيح ≥2 حصراً بلا فواصل ولا كسور
/// (أعداد صحيحة حصراً في المال والكمية — روح س7). يعود null لكل ما
/// ليس عاملاً صحيحاً.
int? parseUnitGroupFactor(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (!RegExp(r'^\d+$').hasMatch(text)) return null;
  final value = int.parse(text);
  if (value < 2) return null;
  return value;
}

/// التحقق قبل الحفظ — يعيد قائمة الأخطاء (فارغة = سليم).
///
/// - [existingGroupNames] أسماء المجموعات القائمة مقلمةً حرفياً —
///   التفرد الحرفي بلا أي تطبيع (D-074)، و[excludeGroupId] غير مستخدم
///   هنا لأن الأسماء تُقارن نصياً في الواجهة قبل الاستدعاء بمعرفة
///   الذات (نمط validateItemDraft بالاستثناء الذاتي).
List<UnitGroupValidationError> validateUnitGroupSpec(
  UnitGroupSpec spec, {
  required Set<String> existingGroupNames,
}) {
  final errors = <UnitGroupValidationError>[];
  final name = spec.name.trim();
  if (name.isEmpty) {
    errors.add(const UnitGroupNameRequired());
  } else if (existingGroupNames.contains(name)) {
    errors.add(UnitGroupNameTaken(name));
  }

  final levels = spec.levels;
  if (levels.isEmpty) {
    errors.add(const UnitGroupLevelsMissing());
    return errors;
  }

  final namesSeen = <String>{};
  final factorsSeen = <int>{};
  for (var i = 0; i < levels.length; i++) {
    final levelName = levels[i].name.trim();
    if (levelName.isEmpty) {
      errors.add(UnitGroupLevelNameRequired(i));
      continue;
    }
    if (!namesSeen.add(levelName)) {
      errors.add(UnitGroupLevelNameDuplicate(levelName));
    }
  }
  for (var i = 0; i < levels.length; i++) {
    final raw = levels[i].factor;
    if (raw < 2) {
      errors.add(UnitGroupFactorInvalid('$raw', i));
      continue;
    }
    if (!factorsSeen.add(raw)) {
      errors.add(UnitGroupFactorDuplicate(raw));
    }
  }
  return errors;
}

/// اشتقاق سعر مستوى من سعر الأساس بعامل التحويل — F-208/D-187: «النتيجة
/// مطابقة للاشتقاق التسلسلي بخطوة واحدة لا خطأ متراكماً» — الضرب
/// الصحيح في الصحيح مطابقٌ فلا تقريب أصلاً (قاعدة س7 للتقريب تمر حيث
/// النسب في الرفع الجماعي لا هنا).
int derivedLevelPriceMinor({
  required int basePriceMinor,
  required int factor,
}) {
  assert(factor >= 1, 'عامل التحويل ≥1 (الأساسية 1 بذاتها)');
  return basePriceMinor * factor;
}

/// نتيجة حسم مستوى واحد في الترقية الجماعية — السعر الجديد وعلم
/// الانكسار.
class BulkLevelPriceOutcome {
  /// السعر الجديد للمستوى للحقل المستهدف.
  final int newLevelPriceMinor;

  /// هل انكسرت علاقة السعر بالكمية قبل الترقية؟ الآلي لا ينكسر أصلاً
  /// (مشتقٌ بالبناء) — والانكسار لليدوي حصراً.
  final bool relationBroken;

  const BulkLevelPriceOutcome({
    required this.newLevelPriceMinor,
    required this.relationBroken,
  });
}

/// حسم سعر مستوى واحد في الترقية الجماعية — تقاطع F-165 بF-208
/// (D-187) حصراً بلا أي لمس قاعدة:
///
/// - الآلي ([priceAuto] = true): المشتق يُعاد اشتقاقه من الأساس الجديد
///   بعامل التحويل — «النسبة ذاتها للأسعار الأخرى» تنتقل بذاتها بلا
///   حساب، وخطوة واحدة من الأساس الجديد لا تراكم تقريب.
/// - اليدوي: كل خانة مستهدفة تُضرب بالنسبة نفسها بقاعدة س7 (النصف
///   بعيداً عن الصفر بمنبع roundHalfAwayFromZeroRatio الواحد) —
///   والصفر ليس سعراً فلا يُرفع (س6).
/// - [relationBroken] لليدوي حصراً: سعر المستوى القديم لا يساوي الأساس
///   القديم × العامل — سطر تحذير بالمعاينة (المتطلب حرفاً).
BulkLevelPriceOutcome bulkLevelPriceOutcome({
  required int oldBasePriceMinor,
  required int newBasePriceMinor,
  required int factor,
  required bool priceAuto,
  required int oldLevelPriceMinor,
  required int percentBps,
}) {
  assert(factor >= 1, 'عامل التحويل ≥1');
  assert(percentBps > -10000 && percentBps <= 1000000,
      'النسبة بحدود (−100%، +10000%] — bps=$percentBps');

  if (priceAuto) {
    return BulkLevelPriceOutcome(
      newLevelPriceMinor: derivedLevelPriceMinor(
          basePriceMinor: newBasePriceMinor, factor: factor),
      relationBroken: false,
    );
  }

  final lifted = oldLevelPriceMinor <= 0
      ? oldLevelPriceMinor
      : roundHalfAwayFromZeroRatio(
          oldLevelPriceMinor * (10000 + percentBps), 10000);
  return BulkLevelPriceOutcome(
    newLevelPriceMinor: lifted,
    // الصفر ليس سعراً (س6 «بلا سعر بعد») فلا ينكسر — والانكسار لسعر
    // موجود يخالف عامل التحويل حصراً.
    relationBroken:
        oldLevelPriceMinor > 0 && oldLevelPriceMinor != oldBasePriceMinor * factor,
  );
}
