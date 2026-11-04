/// جرد المخزون — جلسة عدّ فعلية وتسوية فروقاتها (س-19/F-046 — المرحلة 2،
/// دفعة 25).
///
/// الفحص البنيوي خالص هنا — لا قاعدة ولا واجهة (نمط التحويل والفواتير:
/// المدقق البنيوي بالمجال والفحوص المحركية بالتخزين على ما خُزّن لا على
/// ما قيل، والحاجز الثاني مُشغِّلات القاعدة والثالث حاجز الفترة).
///
/// الحدود الموثقة (س-19 بـ06):
/// - الجلسة لمستودع واحد بنطاق «كل الأصناف» أو «مجموعة تصنيف»، بحالة
///   «جارٍ» يُحفظ عدُّها متكرراً ثم تُرحَّل بترحيلة واحدة — لا مسودة
///   قيدية: الجلسة وثيقة عدّ والمحاسبة لحظة الترحيل حصراً.
/// - لا تسوية جزئية: لا ترحيل إلا وكل أسطر الجلسة مُعدّة (الصفر عدّ
///   شرعي يعني «الرف فارغ» — الغائب عن العدّ هو الذي يحجب الترحيل).
///   والوثيقة نصّت على المجموعة لأنها الحالة الخطرة، والقاعدة نفسها
///   تطبق على نطاق «الكل» بالمعنى ذاته — الجلسة إعلان «عُدّ كل ما
///   في نطاقها».
/// - الفروقات تُحسب لحظة الترحيل ضد الأرصدة الآنية لا ضد لقطة عدّ
///   قديم (الأرصدة حالية دائماً — درس التحويل)، فما بيع أو دخل أثناء
///   الجلسة يدخل الحساب لا يهرب.
/// - التاريخ بتقويم الميلاد ISO حصراً (D-077: لا إدخال هجري أبداً)،
///   وهو تاريخ بدء الجلسة ولا يُعدل بعد الإنشاء.
library;

/// نطاق جلسة الجرد — كل الأصناف أو مجموعة تصنيف (س-19).
enum StockCountScope {
  /// كل الأصناف التي يحملها المستودع.
  all,

  /// مجموعة تصنيف واحدة حصراً — [category] نص التصنيف المطابق.
  group,
}

/// لسان النطاق للعرض — سجل واحد لا صياغة واجهة موازية.
String stockCountScopeLabel(StockCountScope scope) =>
    scope == StockCountScope.all ? 'كل الأصناف' : 'مجموعة تصنيف';

/// سطر عدّ — الصنف والكمية المعدودة بالوحدة الأساسية حصراً
/// (الإدخال بالأساسية في م2 حتى تأتي وحدات التعبئة D-026).
class StockCountLineDraft {
  final int itemId;
  final int countedQtyBase;

  const StockCountLineDraft({required this.itemId, required this.countedQtyBase});
}

/// مسودة افتتاح جلسة جرد — تُنشأ بحالة «جارٍ» وتُزرع أسطرها آلياً من
/// أرصدة المستودع داخل النطاق (الصنف برصيد قائم سطرٌ إلزامي العدّ).
class StockCountStartDraft {
  final String dateText;
  final int warehouseId;
  final StockCountScope scope;

  /// نص التصنيف للمجموعة — إلزامي بنطاق group وبلا معنى بنطاق all.
  final String? scopeCategory;
  final String? narration;

  const StockCountStartDraft({
    required this.dateText,
    required this.warehouseId,
    required this.scope,
    this.scopeCategory,
    this.narration,
  });
}

/// أخطاء رفض الجرد — البنيوية والمحركية منبع واحد بسجل رسائل عربي
/// واحد (نمط التحويل: أسماء الأنواع مسبوقة بنوع المستند درساً بتصادم
/// تحويل الصناديق).
sealed class StockCountValidationError {
  const StockCountValidationError();
}

class StockCountDateInvalid extends StockCountValidationError {
  final String dateText;

  const StockCountDateInvalid(this.dateText);
}

class StockCountWarehouseMissing extends StockCountValidationError {
  final int warehouseId;

  const StockCountWarehouseMissing(this.warehouseId);
}

class StockCountWarehouseInactive extends StockCountValidationError {
  final String warehouseName;

  const StockCountWarehouseInactive(this.warehouseName);
}

class StockCountScopeCategoryMissing extends StockCountValidationError {
  const StockCountScopeCategoryMissing();
}

class StockCountNoLines extends StockCountValidationError {
  const StockCountNoLines();
}

/// جلسة جارٍ سابقة للمستودع نفسه — جلستان متوازيتان على مستودع واحد
/// معناهما عدّان متضاربان لرفوف واحدة، فيمنع الثاني حتى يحسم الأول.
class StockCountOpenSessionExists extends StockCountValidationError {
  final String warehouseName;

  const StockCountOpenSessionExists(this.warehouseName);
}

/// عدّة سالبة — المعدود كمية موجبة أو صفر (الصفر «الرف فارغ» شرعي).
class StockCountCountedInvalid extends StockCountValidationError {
  final int lineIndex;

  const StockCountCountedInvalid(this.lineIndex);
}

class StockCountItemMissing extends StockCountValidationError {
  final int itemId;
  final int lineIndex;

  const StockCountItemMissing(this.itemId, this.lineIndex);
}

class StockCountItemInactive extends StockCountValidationError {
  final String itemLabel;
  final int lineIndex;

  const StockCountItemInactive(this.itemLabel, this.lineIndex);
}

class StockCountItemNotGood extends StockCountValidationError {
  final String itemLabel;
  final int lineIndex;

  const StockCountItemNotGood(this.itemLabel, this.lineIndex);
}

/// صنف مكتشف خارج نطاق المجموعة — يضاف لنطاق التصنيف ذاته لا غيره.
class StockCountItemOutsideScope extends StockCountValidationError {
  final String itemLabel;
  final String scopeCategory;
  final int lineIndex;

  const StockCountItemOutsideScope({
    required this.itemLabel,
    required this.scopeCategory,
    required this.lineIndex,
  });
}

/// الصنف الواحد سطراً واحداً بالجلسة (نمط التحويل D-183).
class StockCountItemDuplicated extends StockCountValidationError {
  final int lineIndex;

  const StockCountItemDuplicated(this.lineIndex);
}

/// لا تسوية جزئية — سطر بلا عدّ يحجب ترحيل الجلسة كلها (س-19).
class StockCountLineNotCounted extends StockCountValidationError {
  final String itemLabel;
  final int lineIndex;

  const StockCountLineNotCounted(this.itemLabel, this.lineIndex);
}

/// الجلسة مرحّلة أصلاً — الآلة جارٍ ← مرحّل بلا رجوع (نمط 07 §1.2).
class StockCountAlreadyPosted extends StockCountValidationError {
  const StockCountAlreadyPosted();
}

class StockCountNotFound extends StockCountValidationError {
  final int sessionId;

  const StockCountNotFound(this.sessionId);
}

/// الفحص البنيوي الخالص لافتتاح الجلسة — ما لا يحتاج قاعدة بيانات.
List<StockCountValidationError> validateStockCountStartStructure(
    StockCountStartDraft draft) {
  final errors = <StockCountValidationError>[];
  if (!_isValidIsoDate(draft.dateText)) {
    errors.add(StockCountDateInvalid(draft.dateText));
  }
  if (draft.warehouseId <= 0) {
    errors.add(StockCountWarehouseMissing(draft.warehouseId));
  }
  if (draft.scope == StockCountScope.group &&
      (draft.scopeCategory == null || draft.scopeCategory!.trim().isEmpty)) {
    errors.add(const StockCountScopeCategoryMissing());
  }
  return errors;
}

/// الفحص البنيوي لعدّات محفوظة أو سطر مكتشف — العدّة موجبة أو صفر
/// حصراً (الصفر عدّ شرعي)، والمفاتيح معرفات أصناف بلا تكرار.
List<StockCountValidationError> validateStockCountCounts(
    Map<int, int> counts) {
  final errors = <StockCountValidationError>[];
  var i = 0;
  for (final entry in counts.entries) {
    if (entry.value < 0) {
      errors.add(StockCountCountedInvalid(i));
    }
    i++;
  }
  return errors;
}

/// الفحص البنيوي لسطر «صنف وجدناه» — وجوده فعلاً يعني عدّة موجبة.
List<StockCountValidationError> validateStockCountFoundLine(
    StockCountLineDraft line) {
  final errors = <StockCountValidationError>[];
  if (line.countedQtyBase <= 0) {
    errors.add(const StockCountCountedInvalid(0));
  }
  return errors;
}

/// صورة تاريخ ISO بسيطة (YYYY-MM-DD) — نمط الميلاد الموحد (D-077).
bool _isValidIsoDate(String value) {
  final m = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(value.trim());
  if (m == null) return false;
  final parts = value.trim().split('-');
  final month = int.tryParse(parts[1]) ?? 0;
  final day = int.tryParse(parts[2]) ?? 0;
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

/// سجل الرسائل العربية الواحد — رسالة المالك الصادقة بأول خطأ تُعرض
/// من هنا لا تُصاغ بالواجهة (نمط التحول النقدي الموثق).
String describeStockCountValidationError(StockCountValidationError error) =>
    switch (error) {
      StockCountDateInvalid(:final dateText) =>
        'تاريخ الجلسة «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)',
      StockCountWarehouseMissing(:final warehouseId) =>
        'مستودع الجرد (المعرف $warehouseId) غير معروف (س-19)',
      StockCountWarehouseInactive(:final warehouseName) =>
        'المستودع «$warehouseName» معطل — لا جلسة جرد عليه (س-18: '
            'مستودع معطل يرفض)',
      StockCountScopeCategoryMissing() =>
        'نطاق «مجموعة تصنيف» يطلب نص التصنيف — اختر التصنيف أولاً',
      StockCountNoLines() =>
        'لا صنف في الجلسة — المستودع بلا أرصدة داخل النطاق ولم يُضف '
            'صنف مكتشف',
      StockCountOpenSessionExists(:final warehouseName) =>
        'للمستودع «$warehouseName» جلسة جرد جارٍ — أحسمها بترحيلها '
            'قبل فتح جلسة أخرى عليه (س-19: عدّان متضاربان مرفوض)',
      StockCountCountedInvalid(:final lineIndex) =>
        'عدّة السطر ${lineIndex + 1} يجب أن تكون صفراً أو أكثر — '
            'الصفر يعني «الرف فارغ»',
      StockCountItemMissing(:final itemId, :final lineIndex) =>
        'صنف السطر ${lineIndex + 1} (المعرف $itemId) غير معروف',
      StockCountItemInactive(:final itemLabel, :final lineIndex) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} معطل — يختفي '
            'من العدّ',
      StockCountItemNotGood(:final itemLabel, :final lineIndex) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} خدمة بلا مخزون — '
            'الجرد بضاعة حصراً (س-08)',
      StockCountItemOutsideScope(
        :final itemLabel,
        :final scopeCategory,
        :final lineIndex,
      ) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} خارج تصنيف '
            '«$scopeCategory» — جلسة المجموعة بأصنافها حصراً (س-19)',
      StockCountItemDuplicated(:final lineIndex) =>
        'الصنف مكرر بالسطر ${lineIndex + 1} — الصنف الواحد سطراً واحداً',
      StockCountLineNotCounted(:final itemLabel, :final lineIndex) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} لم يُعدّ — لا تسوية '
            'جزئية: عدّ كل أسطر الجلسة قبل الترحيل (س-19)',
      StockCountAlreadyPosted() =>
        'الجلسة مرحّلة أصلاً — اللقطة التاريخية لا تعدل (نمط F-140)',
      StockCountNotFound(:final sessionId) =>
        'جلسة الجرد (المعرف $sessionId) غير معروفة',
    };

/// استثناء رفض الجرد — يحمل القائمة كاملة والعرض بأول وصف (نمط س-36).
class StockCountValidationException implements Exception {
  final List<StockCountValidationError> errors;

  const StockCountValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق الجرد: '
      '${errors.map(describeStockCountValidationError).join('؛ ')}';
}

/// أول وصف عربي للقائمة — أدوات الواجهة تعرضه حصراً (نمط «رسالة واحدة
/// أول خطأ»).
String firstStockCountError(List<StockCountValidationError> errors) =>
    errors.isEmpty
        ? 'لا خطأ'
        : describeStockCountValidationError(errors.first);
