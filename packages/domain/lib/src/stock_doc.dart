/// إذنا المخزون — إدخال وإخراج (F-209/F-210 — المرحلة 2، الدفعة 26).
///
/// الفحص البنيوي خالص هنا — لا قاعدة ولا واجهة (نمط التحويل والجرد:
/// المدقق البنيوي بالمجال والفحوص المحركية بالتخزين على ما خُزّن لا
/// على ما قيل، والحاجز الثاني مُشغِّلات القاعدة والمحرك الموحد).
///
/// الحدود الموثقة (س80/س81 — F-209/F-210):
/// - المستندان يُنشآن مرحّلين بلا مسودة (نمط س-18: الرفض قبل الكتابة
///   حصراً) — الإذن فعلٌ آني لا وثيقة تعلق.
/// - «السبب» نصي إلزامي بلا مسوّغات: هدية مورد أو بضاعة وجدت أو تصحيح
///   إدخال (F-209)، وتالف أو استهلاك داخلي أو هدية (F-210) — القائمة
///   توضيحية غير حصرية والنص حر لكنه لا يمر فارغاً.
/// - المقابل افتراضاً 43 «إيرادات أخرى» للإدخال و596 «خسائر التلف
///   والأضرار» للإخراج — قابل التغيير لحظة الترحيل من الحسابات
///   المفعلة (03 §4) — والمعرف موجب بنيوياً والوجود والتفعيل بيد
///   التخزين على ما خُزّن.
/// - الأسطر بضاعة حصراً (الخدمة بلا مخزون — س-08) وكمية موجبة بالوحدة
///   الأساسية (وحدات التعبئة دفعة تالية من م2) والصنف الواحد سطراً
///   واحداً (نمط س-18: ما رآه المستخدم سطراً هو ما يُحفظ حرفاً).
/// - التاريخ بتقويم الميلاد ISO حصراً (D-077: لا إدخال هجري أبداً)،
///   والفترة المقفلة بيد المحرك الموحد وحاجز القاعدة (نمط الجرد).
library;

/// سطر إذن — الصنف والكمية بالوحدة الأساسية حصراً.
class StockDocLineDraft {
  final int itemId;
  final int qtyBase;

  /// س113: لقطة الإدخال بالتعبئة — معرف مستوى المجموعة والكمية المدخلة
  /// بوحدته وعامل اللقطة (نمط الفواتير س89/ترحيلة v21) — والفراغ إدخال
  /// بالأساسية كما اعتاد (القائمة القائمة بلا مساس).
  final int? unitLevelId;
  final int? qtyDoc;
  final int? factorAtEntry;

  /// س141 (الوحدة 5): قيمة سطر صريحة بوحدة الأساسية من ملف الأرصدة
  /// الافتتاحية — رصيد أول المدة قيمة تاريخية لا تقييم D-186 (زيادة
  /// الجرد تُقيَّن، والافتتاحي يُصدَّق) — فمسار الافتتاحي وحده يملؤه
  /// والإدخال الاعتيادي يتركه فارغاً فيقيَّم بعرف D-186 القائم.
  final int? valueBaseMinor;

  const StockDocLineDraft({
    required this.itemId,
    required this.qtyBase,
    this.unitLevelId,
    this.qtyDoc,
    this.factorAtEntry,
    this.valueBaseMinor,
  });
}

/// مسودة إذن إدخال المخزون (F-209) — يُنشأ مرحّلاً بلا مسودة.
class StockReceiptDraft {
  final String dateText;
  final int warehouseId;

  /// السبب النصي الإلزامي (هدية مورد، بضاعة وجدت، تصحيح إدخال — F-209).
  final String reason;

  /// حساب المقابل — افتراضه 43 من الواجهة وقابل التغيير من المفعّل.
  final int counterAccountId;

  final String? narration;
  final List<StockDocLineDraft> lines;

  const StockReceiptDraft({
    required this.dateText,
    required this.warehouseId,
    required this.reason,
    required this.counterAccountId,
    this.narration,
    required this.lines,
  });
}

/// مسودة إذن إخراج المخزون (F-210) — يُنشأ مرحّلاً بلا مسودة.
class StockIssueDraft {
  final String dateText;
  final int warehouseId;

  /// السبب النصي الإلزامي (تالف، استهلاك داخلي، هدية — F-210).
  final String reason;

  /// حساب المقابل — افتراضه 596 من الواجهة وقابل التغيير من المفعّل.
  final int counterAccountId;

  final String? narration;
  final List<StockDocLineDraft> lines;

  const StockIssueDraft({
    required this.dateText,
    required this.warehouseId,
    required this.reason,
    required this.counterAccountId,
    this.narration,
    required this.lines,
  });
}

/// أخطاء رفض إذنا المخزون — البنيوية والمحركية منبع واحد بسجل رسائل
/// عربي واحد (نمط التحويل: أنواع بيانات لا نصوص جاهزة). الفئة المختومة
/// واحدة للإذنين والاتجاه يُميَّز بحقل [direction] كي تصلح القائمة
/// لرفضي المستندَين بسجل وصاف واحد.
sealed class StockDocValidationError {
  /// 'receipt' إدخال / 'issue' إخراج — لتسمية الإذن في الرسالة.
  final String direction;

  const StockDocValidationError({required this.direction});

  String get docLabel =>
      direction == 'receipt' ? 'إذن الإدخال' : 'إذن الإخراج';
}

class StockDocDateInvalid extends StockDocValidationError {
  final String dateText;

  const StockDocDateInvalid(this.dateText, {required super.direction});
}

class StockDocReasonEmpty extends StockDocValidationError {
  const StockDocReasonEmpty({required super.direction});
}

class StockDocNoLines extends StockDocValidationError {
  const StockDocNoLines({required super.direction});
}

class StockDocQtyInvalid extends StockDocValidationError {
  final int lineIndex;

  const StockDocQtyInvalid(this.lineIndex, {required super.direction});
}

class StockDocItemDuplicated extends StockDocValidationError {
  final int lineIndex;

  const StockDocItemDuplicated(this.lineIndex, {required super.direction});
}

/// س113: مستوى التعبئة بالمستند غير صالح — لا ينتمي لمجموعة الصنف
/// أو عاملُه لا يطابق الكمية المدخلة (نمط حرس الفواتير س89).
class StockDocLevelInvalid extends StockDocValidationError {
  final int lineIndex;
  final String itemLabel;

  const StockDocLevelInvalid(this.lineIndex, this.itemLabel,
      {required super.direction});
}

class StockDocCounterAccountInvalid extends StockDocValidationError {
  final int accountId;

  const StockDocCounterAccountInvalid(this.accountId,
      {required super.direction});
}

class StockDocWarehouseMissing extends StockDocValidationError {
  final int warehouseId;

  const StockDocWarehouseMissing(this.warehouseId,
      {required super.direction});
}

class StockDocWarehouseInactive extends StockDocValidationError {
  final String warehouseName;

  const StockDocWarehouseInactive(this.warehouseName,
      {required super.direction});
}

class StockDocItemMissing extends StockDocValidationError {
  final int itemId;
  final int lineIndex;

  const StockDocItemMissing(this.itemId, this.lineIndex,
      {required super.direction});
}

class StockDocItemInactive extends StockDocValidationError {
  final String itemLabel;
  final int lineIndex;

  const StockDocItemInactive(this.itemLabel, this.lineIndex,
      {required super.direction});
}

class StockDocItemNotGood extends StockDocValidationError {
  final String itemLabel;
  final int lineIndex;

  const StockDocItemNotGood(this.itemLabel, this.lineIndex,
      {required super.direction});
}

class StockDocStockInsufficient extends StockDocValidationError {
  final String itemLabel;
  final int onHandQty;
  final int requestedQty;
  final int lineIndex;

  const StockDocStockInsufficient({
    required this.itemLabel,
    required this.onHandQty,
    required this.requestedQty,
    required this.lineIndex,
    required super.direction,
  });
}

class StockDocCounterAccountMissing extends StockDocValidationError {
  final int accountId;

  const StockDocCounterAccountMissing(this.accountId,
      {required super.direction});
}

class StockDocCounterAccountInactive extends StockDocValidationError {
  final String accountLabel;

  const StockDocCounterAccountInactive(this.accountLabel,
      {required super.direction});
}

/// الفحص البنيوي الخالص للإدخال — قواعد F-209 التي لا تحتاج قاعدة بيانات.
List<StockDocValidationError> validateStockReceiptStructure(
    StockReceiptDraft draft) {
  return _validateStructure(
    dateText: draft.dateText,
    reason: draft.reason,
    counterAccountId: draft.counterAccountId,
    lines: draft.lines,
    direction: 'receipt',
  );
}

/// الفحص البنيوي الخالص للإخراج — قواعد F-210 التي لا تحتاج قاعدة بيانات.
List<StockDocValidationError> validateStockIssueStructure(
    StockIssueDraft draft) {
  return _validateStructure(
    dateText: draft.dateText,
    reason: draft.reason,
    counterAccountId: draft.counterAccountId,
    lines: draft.lines,
    direction: 'issue',
  );
}

List<StockDocValidationError> _validateStructure({
  required String dateText,
  required String reason,
  required int counterAccountId,
  required List<StockDocLineDraft> lines,
  required String direction,
}) {
  final errors = <StockDocValidationError>[];
  if (!_isValidIsoDate(dateText)) {
    errors.add(StockDocDateInvalid(dateText, direction: direction));
  }
  if (reason.trim().isEmpty) {
    errors.add(StockDocReasonEmpty(direction: direction));
  }
  if (counterAccountId <= 0) {
    errors.add(
        StockDocCounterAccountInvalid(counterAccountId, direction: direction));
  }
  if (lines.isEmpty) {
    errors.add(StockDocNoLines(direction: direction));
  }
  final seenItems = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.qtyBase <= 0) {
      errors.add(StockDocQtyInvalid(i, direction: direction));
    }
    if (!seenItems.add(line.itemId)) {
      errors.add(StockDocItemDuplicated(i, direction: direction));
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
/// من هنا لا تُصاغ بالواجهة (نمط التحويل والجرد).
String describeStockDocValidationError(StockDocValidationError error) =>
    switch (error) {
      StockDocDateInvalid(:final dateText, :final docLabel) =>
        'تاريخ $docLabel «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)',
      StockDocReasonEmpty(:final docLabel) =>
        'سبب $docLabel إلزامي — اكتب السبب نصاً (هدية مورد، بضاعة وجدت، '
            'تصحيح إدخال، تالف، استهلاك داخلي…)',
      StockDocNoLines(:final docLabel) =>
        'لا صنف في $docLabel — أضف سطراً واحداً على الأقل',
      StockDocQtyInvalid(:final lineIndex, :final docLabel) =>
        'كمية السطر ${lineIndex + 1} في $docLabel يجب أن تكون موجبة — '
            'بالوحدة الأساسية',
      StockDocItemDuplicated(:final lineIndex) =>
        'الصنف مكرر بالسطر ${lineIndex + 1} — الصنف الواحد سطراً واحداً '
            'فاجمع الكميتين بسطر واحد',
      StockDocLevelInvalid(:final lineIndex, :final itemLabel) =>
        'السطر ${lineIndex + 1}: مستوى التعبئة «$itemLabel» غير صالح — '
            'لا ينتمي لمجموعة الصنف أو الكمية المدخلة لا تطابق عامل '
            'المستوى',
      StockDocCounterAccountInvalid(:final accountId, :final docLabel) =>
        'حساب المقابل في $docLabel (المعرف $accountId) غير صالح — '
            'اختر حساباً من الدليل',
      StockDocWarehouseMissing(:final warehouseId, :final docLabel) =>
        'مستودع $docLabel (المعرف $warehouseId) غير معروف',
      StockDocWarehouseInactive(:final warehouseName) =>
        'المستودع «$warehouseName» معطل — يختفي من الاختيار',
      StockDocItemMissing(:final itemId, :final lineIndex) =>
        'صنف السطر ${lineIndex + 1} (المعرف $itemId) غير معروف',
      StockDocItemInactive(:final itemLabel, :final lineIndex) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} معطل — يختفي من '
            'الاختيار',
      StockDocItemNotGood(:final itemLabel, :final lineIndex) =>
        'الصنف «$itemLabel» بالسطر ${lineIndex + 1} خدمة بلا مخزون — '
            'إذنا المخزون بضاعة حصراً',
      StockDocStockInsufficient(
        :final itemLabel,
        :final onHandQty,
        :final requestedQty,
        :final docLabel,
      ) =>
        'رصيد الصنف «$itemLabel» بالمستودع $onHandQty والمطلوب إخراجه '
            '$requestedQty — منع السالب ولا يمر $docLabel',
      StockDocCounterAccountMissing(:final accountId, :final docLabel) =>
        'حساب المقابل في $docLabel (المعرف $accountId) غير موجود بالدليل',
      StockDocCounterAccountInactive(:final accountLabel) =>
        'حساب المقابل «$accountLabel» غير مفعّل — الإذن من الحسابات '
            'المفعلة حصراً',
    };

/// استثناء رفض الإذن — تحمل القائمة كاملة والعرض بأول وصف (نمط س-36).
class StockDocValidationException implements Exception {
  final List<StockDocValidationError> errors;

  const StockDocValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق إذن المخزون: '
      '${errors.map(describeStockDocValidationError).join('؛ ')}';
}

/// أول وصف عربي للقائمة — أدوات الواجهة تعرضه حصراً (نمط «رسالة واحدة
/// أول خطأ»).
String firstStockDocError(List<StockDocValidationError> errors) =>
    errors.isEmpty
        ? 'لا خطأ'
        : describeStockDocValidationError(errors.first);
