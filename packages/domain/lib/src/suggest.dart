/// اقتراحات الإدخال من البيانات المحلية — F-146 جزءها الأول (الدفعة
/// 23/D-183) على حدود س2:9: «اقتراح بقبول بشري، محلي من بياناته،
/// ولا يقرر حيث المال».
///
/// ما هو في هذه الوحدة: قاعدة اختيار الاقتراح النقية — الحتمية كاملة.
/// ما ليس هنا: أي كتابة أو قرار — الاقتراح يُعرض ويُقبل بضغطة أو
/// يُهمل، واللوحة «يحتاج انتباهك» م4–م5 والطبقة المحاوِرة بقائمة
/// الانتظار (حدود F-146 الموثقة).
library;

/// اختيار الطرف الأكثر تداولاً من عدادات الاستخدام — الأكثر عدداً
/// حصراً، وعند التساوي الأصغر معرفاً (حتمية لا ترتيب قاعدة عرضي)،
/// والخلو بلا اقتراح.
int? suggestMostActiveParty(Map<int, int> usageCounts) {
  int? best;
  var bestCount = 0;
  final ids = usageCounts.keys.toList()..sort();
  for (final id in ids) {
    final count = usageCounts[id] ?? 0;
    if (count > bestCount) {
      bestCount = count;
      best = id;
    }
  }
  return best;
}

/// سعر سطر الفاتورة المقترح — آخر سعر فعلي مع هذا الطرف يقدَّم على
/// السعر المرجعي، والصفر ليس سعراً (س6 «بلا سعر بعد») فلا اقتراح
/// بلا سعر: المرجعي هو المخرج حينئذٍ حتى لو كان صفراً. القبول بشري
/// دائماً: الحقل حُرّه بعد الاقتراح ولا يُعاد اقتراحه خفية.
int suggestLinePriceMinor({
  required int? lastActualPriceMinor,
  required int referencePriceMinor,
}) =>
    (lastActualPriceMinor != null && lastActualPriceMinor > 0)
        ? lastActualPriceMinor
        : referencePriceMinor;
