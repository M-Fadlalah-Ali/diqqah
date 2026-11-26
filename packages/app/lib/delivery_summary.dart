// أساس أرقام التسليم وسطر خلاصتها — دفعة (14) س-148/D-138 بقرار
// المالك الحرفي: «أرغب أن يكون الافتراضي مجموع الكميات بالواحدة مع
// خيار تبديل إلى الأسطر/الأقلام، وهذا الخيار موجود في نفس السطر
// قائمة منسدلة بخيارين».
//
// قاعدة الوحدة الموثقة (البوابة): وحدة واحدة فالعدد باسمها الحقيقي،
// ووحدات مختلفة فلا عدد مفبرك يجمع قلماً بعلبة — العرض بمجموعات
// الوحدات، فاسم البرنامج «دِقَّة». والقسيمة المطبوعة على الافتراضي
// (الكميات) دائماً — فالقائمة المنسدلة عرضُ شاشة لا سياسة مطبوع.
library;

/// أساس العد: الكميات (الافتراضي) أو الأسطر.
enum DeliveryBasis { quantities, lines }

String deliveryBasisLabel(DeliveryBasis basis) =>
    basis == DeliveryBasis.quantities ? 'الكميات' : 'الأسطر';

/// خيارات القائمة المنسدلة بترتيبها المعتمد.
const List<DeliveryBasis> deliveryBasisChoices = DeliveryBasis.values;

/// تجميع الكميات باسم الوحدة — «مجموع الكميات بالواحدة» بقرار المالك.
Map<String, int> quantitiesByUnit(Iterable<(int, String)> qtyUnitPairs) {
  final byUnit = <String, int>{};
  for (final (qty, unit) in qtyUnitPairs) {
    byUnit[unit] = (byUnit[unit] ?? 0) + qty;
  }
  return byUnit;
}

/// نص الكميات المجمعة — وحدة واحدة باسمها («6 قطعة»)، ومختلف
/// الوحدات بمجموعاتها («2 علبة · 5 قلم») بلا عدد مفبرك.
String groupedQuantitiesText(Map<String, int> byUnit) {
  if (byUnit.isEmpty) return '';
  return byUnit.entries.map((e) => '${e.value} ${e.key}').join(' · ');
}

/// الفرق بين مجموعتَي الكميات (الإجمالي والمستلم) — كمية المتبقي
/// بوحداتها.
Map<String, int> remainingQuantitiesByUnit(
  Map<String, int> totalByUnit,
  Map<String, int> deliveredByUnit,
) => {
      for (final e in totalByUnit.entries)
        e.key: e.value - (deliveredByUnit[e.key] ?? 0),
    };

/// سطر خلاصة التسليم لفاتورة واحدة — لسان «مستلم X من Y» المعتمد
/// (س-140/D-134) بأساس العد:
/// - الكميات ووحدة الفاتورة واحدة: «مستلم 12 من 17 قلم — المتبقي: 5 قلم».
/// - الكميات ووحداتها مختلفة: العدد بالأسطر وتفصيل المتبقي بوحداته
///   («مستلم 1 من 3 — المتبقي: 2 قلم · 1 علبة») لا جمع مفبرك.
/// - الأسطر: العدد بسطور الفاتورة («مستلم 1 من 3 — المتبقي: 2»).
String invoiceDeliverySummary({
  required int deliveredLines,
  required int totalLines,
  required Map<String, int> deliveredQtyByUnit,
  required Map<String, int> totalQtyByUnit,
  required DeliveryBasis basis,
}) {
  final remainingLines = totalLines - deliveredLines;
  final complete = remainingLines == 0;
  final count = 'مستلم $deliveredLines من $totalLines';
  if (basis == DeliveryBasis.quantities && totalQtyByUnit.length == 1) {
    final unit = totalQtyByUnit.keys.single;
    final out = 'مستلم ${deliveredQtyByUnit[unit] ?? 0} '
        'من ${totalQtyByUnit[unit]} $unit';
    return complete
        ? '$out — اكتمل التسليم'
        : '$out — المتبقي: ${remainingQuantitiesByUnit(totalQtyByUnit, deliveredQtyByUnit)[unit]} $unit';
  }
  if (basis == DeliveryBasis.quantities) {
    final remainingText = groupedQuantitiesText(
        remainingQuantitiesByUnit(totalQtyByUnit, deliveredQtyByUnit));
    return complete ? '$count — اكتمل التسليم' : '$count — المتبقي: $remainingText';
  }
  return complete ? '$count — اكتمل التسليم' : '$count — المتبقي: $remainingLines';
}

/// نص ترويسة شاشة «متابعة التسليم» — بأساس العد المعتمد: الكميات
/// بمجموعات وحداتها، والأسطر بالعدد المفلتر من الإجمالي (لسان
/// D-133 القائم باقياً على أساسه).
String deliveryHeaderCount({
  required DeliveryBasis basis,
  required int filteredLines,
  required int allLines,
  required Map<String, int> filteredQtyByUnit,
}) {
  if (basis == DeliveryBasis.quantities) {
    final text = groupedQuantitiesText(filteredQtyByUnit);
    return text.isEmpty ? 'لا شيء' : text;
  }
  return '$filteredLines من $allLines';
}
