/// تحويل الأصناف بين مستودعين (س-18/F-045 — المرحلة 2، دفعة 24).
///
/// الفحص البنيوي خالص هنا — لا قاعدة ولا واجهة (نمط الفواتير والسندات:
/// المدقق البنيوي بالمجال والفحوص المحركية بالتخزين على ما خُزّن لا على
/// ما قيل، والحاجز الثاني مُشغِّلات القاعدة).
///
/// الحدود الموثقة (س-18 بـ06):
/// - نفس المستودع على الطرفين مرفوض.
/// - التحويل بلا أسطر مرفوض وكل كمية موجبة حصراً بالوحدة الأساسية
///   (وحدات التعبئة دفعة تالية من م2 — الإدخال بالأساسية فقط).
/// - الصنف الواحد سطراً واحداً بتحويل واحد — الكفيتان تُجمَّعان عند
///   الإدخال فما رأى المستخدم سطراً هو ما يُحفظ حرفاً (نمط D-183
///   «المعاينة هي التنفيذ»).
/// - التاريخ بتقويم الميلاد ISO حصراً (D-077: لا إدخال هجري أبداً).
library;

/// سطر تحويل — الصنف والكمية بالوحدة الأساسية حصراً.
class TransferLineDraft {
  final int itemId;
  final int qtyBase;

  /// س113: لقطة الإدخال بالتعبئة (نمط الفواتير س89) — والفراغ إدخال
  /// بالأساسية كما اعتاد.
  final int? unitLevelId;
  final int? qtyDoc;
  final int? factorAtEntry;

  const TransferLineDraft({
    required this.itemId,
    required this.qtyBase,
    this.unitLevelId,
    this.qtyDoc,
    this.factorAtEntry,
  });
}

/// مسودة تحويل بين مستودعين — تُنشأ مرحّلةً مباشرة بلا مسودة (س-18:
/// الرفض قبل الترحيل حصراً؛ لا ذمة ولا صندوق في التحويل فلا مسودة
/// تحتاجها).
class StockTransferDraft {
  final String dateText;
  final int fromWarehouseId;
  final int toWarehouseId;
  final String? narration;
  final List<TransferLineDraft> lines;

  const StockTransferDraft({
    required this.dateText,
    required this.fromWarehouseId,
    required this.toWarehouseId,
    this.narration,
    required this.lines,
  });
}

/// أخطاء رفض التحويل — البنيوية والمحركية منبع واحد بسجل رسائل عربي
/// واحد (نمط تحويل الصناديق).
sealed class StockTransferValidationError {
  const StockTransferValidationError();
}

/// س113: مستوى التعبئة بالتحويل غير صالح — لا ينتمي لمجموعة الصنف
/// أو عاملُه لا يطابق الكمية المدخلة (نمط حرس الفواتير س89).
class StockTransferLevelInvalid extends StockTransferValidationError {
  final int lineIndex;
  final String itemLabel;

  const StockTransferLevelInvalid(this.lineIndex, this.itemLabel);
}

class StockTransferDateInvalid extends StockTransferValidationError {
  final String dateText;

  const StockTransferDateInvalid(this.dateText);
}

class StockTransferSameWarehouse extends StockTransferValidationError {
  const StockTransferSameWarehouse();
}

class StockTransferNoLines extends StockTransferValidationError {
  const StockTransferNoLines();
}

class StockTransferQtyInvalid extends StockTransferValidationError {
  final int lineIndex;

  const StockTransferQtyInvalid(this.lineIndex);
}

class StockTransferItemDuplicated extends StockTransferValidationError {
  final int lineIndex;

  const StockTransferItemDuplicated(this.lineIndex);
}

class StockTransferWarehouseMissing extends StockTransferValidationError {
  final int warehouseId;

  const StockTransferWarehouseMissing(this.warehouseId);
}

class StockTransferWarehouseInactive extends StockTransferValidationError {
  final String warehouseName;

  const StockTransferWarehouseInactive(this.warehouseName);
}

class StockTransferItemMissing extends StockTransferValidationError {
  final int itemId;
  final int lineIndex;

  const StockTransferItemMissing(this.itemId, this.lineIndex);
}

class StockTransferItemInactive extends StockTransferValidationError {
  final String itemLabel;
  final int lineIndex;

  const StockTransferItemInactive(this.itemLabel, this.lineIndex);
}

class StockTransferItemNotGood extends StockTransferValidationError {
  final String itemLabel;
  final int lineIndex;

  const StockTransferItemNotGood(this.itemLabel, this.lineIndex);
}

class StockTransferStockInsufficient extends StockTransferValidationError {
  final String itemLabel;
  final int onHandQty;
  final int requestedQty;
  final int lineIndex;

  const StockTransferStockInsufficient({
    required this.itemLabel,
    required this.onHandQty,
    required this.requestedQty,
    required this.lineIndex,
  });
}

/// الفحص البنيوي الخالص — قواعد س-18 التي لا تحتاج قاعدة بيانات.
List<StockTransferValidationError> validateStockTransferStructure(
    StockTransferDraft draft) {
  final errors = <StockTransferValidationError>[];
  if (!_isValidIsoDate(draft.dateText)) {
    errors.add(StockTransferDateInvalid(draft.dateText));
  }
  if (draft.fromWarehouseId == draft.toWarehouseId) {
    errors.add(const StockTransferSameWarehouse());
  }
  if (draft.lines.isEmpty) {
    errors.add(const StockTransferNoLines());
  }
  final seenItems = <int>{};
  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    if (line.qtyBase <= 0) {
      errors.add(StockTransferQtyInvalid(i));
    }
    if (!seenItems.add(line.itemId)) {
      errors.add(StockTransferItemDuplicated(i));
    }
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
/// من هنا لا تُصاغ بالواجهة (نمط التحول النقدي الموثق).
String describeStockTransferValidationError(
        StockTransferValidationError error) =>
    switch (error) {
      StockTransferLevelInvalid(:final lineIndex, :final itemLabel) =>
        'السطر ${lineIndex + 1}: مستوى التعبئة «$itemLabel» غير صالح — '
            'لا ينتمي لمجموعة الصنف أو الكمية المدخلة لا تطابق عامل '
            'المستوى',
      StockTransferDateInvalid(:final dateText) =>
        'تاريخ التحويل «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)',
      StockTransferSameWarehouse() =>
        'التحويل من المستودع إلى نفسه مرفوض — مستودعان مختلفان',
      StockTransferNoLines() => 'لا صنف في التحويل — أضف سطراً واحداً على الأقل',
      StockTransferQtyInvalid(:final lineIndex) =>
        'كمية السطر ${lineIndex + 1} يجب أن تكون موجبة — بالوحدة الأساسية',
      StockTransferItemDuplicated(:final lineIndex) =>
        'الصنف مكرر بالسطر ${lineIndex + 1} — الصنف الواحد سطراً واحداً '
            'فاجمع الكميتين بسطر واحد',
      StockTransferWarehouseMissing(:final warehouseId) =>
        'أحد مستودعي التحويل (المعرف $warehouseId) غير معروف',
      StockTransferWarehouseInactive(:final warehouseName) =>
        'المستودع «$warehouseName» معطل — يختفي من الاختيار',
      StockTransferItemMissing(:final itemId, :final lineIndex) =>
        'صنف السطر ${lineIndex + 1} (المعرف $itemId) غير معروف',
      StockTransferItemInactive(:final itemLabel, :final lineIndex) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} معطل — يختفي من الاختيار',
      StockTransferItemNotGood(:final itemLabel, :final lineIndex) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} خدمة بلا مخزون — '
            'التحويل بضاعة حصراً',
      StockTransferStockInsufficient(
        :final itemLabel,
        :final onHandQty,
        :final requestedQty,
      ) =>
        'رصيد الصنف «$itemLabel» بالمستودع المصدر $onHandQty والمطلوب '
            '$requestedQty — منع السالب',
    };

/// استثناء رفض التحويل — تحمل القائمة كاملة والعرض بأول وصف (نمط س-36).
class StockTransferValidationException implements Exception {
  final List<StockTransferValidationError> errors;

  const StockTransferValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق التحويل: '
      '${errors.map(describeStockTransferValidationError).join('؛ ')}';
}

/// أول وصف عربي للقائمة — أدوات الواجهة تعرضه حصراً (نمط «رسالة واحدة
/// أول خطأ»).
String firstStockTransferError(
    List<StockTransferValidationError> errors) =>
    errors.isEmpty
        ? 'لا خطأ'
        : describeStockTransferValidationError(errors.first);
