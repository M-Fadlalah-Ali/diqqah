/// الترقية الجماعية للأسعار بالتصنيف — F-165 (الدفعة 23/D-183).
///
/// المواصفة (04 §F-165): شاشة تختار التصنيف والنسبة وتعرض معاينة قبل
/// التنفيذ؛ الأسعار الجديدة تُكتب على الأصناف (المرجعيات) والتقريب
/// للوحدة الصغرى بقاعدة س7؛ فواتير التاريخ بلقطات أسعارها لا تُمس.
///
/// قواعد D-183 الموثقة:
/// - النسبة بنقاط الأساس (bps = النسبة × 100) أعداد صحيحة حصراً — لا
///   كسور عائمة في المال إطلاقاً، والمجال (−100%, +10000%] أي
///   −10000 < bps ≤ 1000000.
/// - السعر الصفر ليس سعراً (س6 «بلا سعر بعد») فلا يُرفع — يبقى صفراً
///   بلسان `_fillDefaultPrice` ذاته.
/// - التقريب لأقرب وحدة صغرى والنصف بعيداً عن الصفر بمساعد س7 الواحد
///   `roundHalfAwayFromZeroRatio` (منبع واحد لا مضاعفة).
/// - ما لا يستهدفه المالك يمرّ كما هو — «كلاهما» وحده يمس الحقلين.
library;

import 'invoice.dart' show roundHalfAwayFromZeroRatio;

/// هدف الترقية — سعر البيع أو الشراء أو كلاهما.
enum BulkPriceTarget {
  sale('sale', 'سعر البيع'),
  purchase('purchase', 'سعر الشراء'),
  both('both', 'كلاهما');

  final String storageValue;
  final String label;

  const BulkPriceTarget(this.storageValue, this.label);
}

/// نتيجة الترقية لصنف واحد — الجديد للحقلين (المستهدف مقرّب س7
/// والغير مستهدف مروراً كما هو).
class BulkPriceOutcome {
  final int newSalePriceMinor;
  final int newPurchasePriceMinor;

  const BulkPriceOutcome({
    required this.newSalePriceMinor,
    required this.newPurchasePriceMinor,
  });
}

/// حساب الترقية لصنف واحد — نقي حصراً: القديم والنسبة يدخلان والجديد
/// يخرج بلا أي لمس قاعدة. السعر الصفر لا يُرفع (س6)، والنسبة ببسط
/// `(10000 + bps)` على مقام 10000 بالنصف بعيداً عن الصفر (س7).
BulkPriceOutcome bulkPriceOutcome({
  required int oldSalePriceMinor,
  required int oldPurchasePriceMinor,
  required int percentBps,
  required BulkPriceTarget target,
}) {
  assert(percentBps > -10000 && percentBps <= 1000000,
      'النسبة بحدود (−100%، +10000%] — bps=$percentBps');

  int lift(int oldMinor) =>
      oldMinor <= 0
          ? oldMinor
          : roundHalfAwayFromZeroRatio(oldMinor * (10000 + percentBps), 10000);

  final sale = (target == BulkPriceTarget.sale ||
          target == BulkPriceTarget.both)
      ? lift(oldSalePriceMinor)
      : oldSalePriceMinor;
  final purchase = (target == BulkPriceTarget.purchase ||
          target == BulkPriceTarget.both)
      ? lift(oldPurchasePriceMinor)
      : oldPurchasePriceMinor;
  return BulkPriceOutcome(
      newSalePriceMinor: sale, newPurchasePriceMinor: purchase);
}

/// تحويل نص النسبة إلى نقاط أساس — أعداد صحيحة حصراً بلا double
/// (درس المال: لا كسور عائمة إطلاقاً). يقبل إشارة وعشرياً بخانتين
/// كحد أقصى: «2.5» ← 250، «-3» ← −300، «2.55» ← 255، «2.555» رفض.
/// يعود فارغاً لكل ما ليس نسبة في مجالها (−100, +10000].
int? parsePercentToBps(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final m = RegExp(r'^([+-]?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
  if (m == null) return null;
  final sign = m.group(1) == '-' ? -1 : 1;
  final whole = int.parse(m.group(2)!);
  final fracText = m.group(3) ?? '';
  final frac = fracText.isEmpty
      ? 0
      : int.parse(fracText.padRight(2, '0'));
  final bps = sign * (whole * 100 + frac);
  if (bps <= -10000 || bps > 1000000) return null;
  return bps;
}
