/// إقفال الفترات وفكّها — دفعة م1 السادسة (06 §6/س-20 «أساس م1»،
/// D-088..D-090 معروضة): «الإقفال هو ما يجعل الأرقام القديمة موثوقة
/// إلى الأبد: فترة مقفلة تعني أن كل ما فيها مثبّت لا حركة تعود إليه».
///
/// الحدود المعتمدة لهذه الدفعة:
/// - الإقفال والفك حالة الفترة وحدها (`state: open/closed`) + حدثا سجل
///   موثقان (`period_closed`/`period_opened`) — والفك طوارئ بسبب نصي
///   إلزامي (س2: باب فتح الإقفال).
/// - المرحّل مجمد أصلاً بلا تعديل (07 §1.3) والتقارير التاريخية من
///   المرحّل فلا تتأثر بالفك — لذلك لقطة «كما قُفل» الختامية (س-20 كامل
///   م2) لا حاجة لها هنا وتؤجل مع الإقفال السنوي (س-21 م2/D-090 معروض).
/// - المسودات فوق شهر مقفل تبقى معلقة لا تُرحَّل حتى الفك (05 §3.4 نمط
///   period_id عند الترحيل) — والإقفال يعرض قائمة المسودات ويطلب حسمها
///   بتأكيد صريح (س-20: «ترحيلها قبل الإقفال أو تركها معلقة»).
/// - الإقفال صلاحية مدير حصراً وفكّه موثق (07 §1.5) — تنفيذ الصلاحية
///   بطبقة الواجهة (جداول الأدوار جاهزة من م0) والمحرك يوثق من وفكَّ
///   لماذا بلقطة السجل.
library;

/// خطأ مدقق الإقفال/الفك — أنواع محمولة بيانات لا نصوص جاهزة (نمط
/// الأطراف والفواتير).
sealed class PeriodClosingValidationError {
  const PeriodClosingValidationError();
}

/// فترة مقفلة سابقاً لا تُقفل مرتين (س-20 رفض صريح).
class PeriodAlreadyClosed extends PeriodClosingValidationError {
  final int periodId;
  final String startDateText;
  final String endDateText;

  const PeriodAlreadyClosed(this.periodId, this.startDateText, this.endDateText);
}

/// فكُّ فترة مفتوحة بلا معنى — الفك للمقفلة حصراً.
class PeriodNotClosed extends PeriodClosingValidationError {
  final int periodId;

  const PeriodNotClosed(this.periodId);
}

/// مسودات في الفترة لم يُحسم أمرها — القائمة تُعرض ويُطلب الحسم: ترحيلها
/// قبل الإقفال أو تركها معلقة لا تُرحَّل حتى الفك (س-20). التأكيد صريح
/// معلَم (`draftsConfirmed`) لا صمت يُقفل فوقها.
class PeriodHasOpenDrafts extends PeriodClosingValidationError {
  final int periodId;
  final int draftsCount;

  const PeriodHasOpenDrafts(this.periodId, this.draftsCount);
}

/// فكُّ الإقفال بلا سبب نصي — مرفوض (س2: باب فتح الإقفال بسبب إلزامي).
class PeriodOpenReasonMandatory extends PeriodClosingValidationError {
  final int periodId;

  const PeriodOpenReasonMandatory(this.periodId);
}

/// مدقق الإقفال: فترة مفتوحة حصراً، والمسودات إن وُجدت فبتأكيد صريح.
List<PeriodClosingValidationError> validatePeriodClose({
  required int periodId,
  required String startDateText,
  required String endDateText,
  required bool isOpen,
  required int openDraftsCount,
  required bool draftsConfirmed,
}) {
  final errors = <PeriodClosingValidationError>[];
  if (!isOpen) {
    errors.add(PeriodAlreadyClosed(periodId, startDateText, endDateText));
  }
  if (openDraftsCount > 0 && !draftsConfirmed) {
    errors.add(PeriodHasOpenDrafts(periodId, openDraftsCount));
  }
  return errors;
}

/// مدقق الفك: فترة مقفلة حصراً وسبب نصي إلزامي (الفراغ أو الفراغات
/// المبيّضة مرفوضة).
List<PeriodClosingValidationError> validatePeriodOpen({
  required int periodId,
  required bool isClosed,
  required String reason,
}) {
  final errors = <PeriodClosingValidationError>[];
  if (!isClosed) {
    errors.add(PeriodNotClosed(periodId));
  }
  if (reason.trim().isEmpty) {
    errors.add(PeriodOpenReasonMandatory(periodId));
  }
  return errors;
}

String describePeriodClosingValidationError(
  PeriodClosingValidationError error,
) =>
    switch (error) {
      PeriodAlreadyClosed(:final startDateText, :final endDateText) =>
        'فترة مقفلة سابقاً ($startDateText..$endDateText) — لا تُقفل مرتين',
      PeriodNotClosed() => 'الفترة مفتوحة أصلًا — الفك للمقفلة حصراً',
      PeriodHasOpenDrafts(:final draftsCount) =>
        'في الفترة $draftsCount مسودة غير محسومة — '
            'رحّلها أو أكّد تركها معلقة لا تُرحَّل حتى الفك',
      PeriodOpenReasonMandatory() =>
        'فك الإقفال طارئ بسبب نصي إلزامي — اكتب سبب الفك ولا يفتح بلا سبب',
    };

/// رفض مدقق الإقفال — يحمل الأخطاء النوعية (نمط استثناءات المحرك).
class PeriodClosingException implements Exception {
  final List<PeriodClosingValidationError> errors;

  const PeriodClosingException(this.errors);

  @override
  String toString() =>
      'رفض مدقق الإقفال: ${errors.map(describePeriodClosingValidationError).join('؛ ')}';
}

/// مسودة داخل فترة قائمة — قائمة س-20 المعروضة لطلب الحسم قبل الإقفال
/// (المستندات القيدية الخمسة: قيد عام وفاتورة وسند وتحويل وتسوية).
class PeriodDraftInfo {
  final String docType;
  final int docId;

  /// رقم المستند المُصدَر أو «مسودة #المعرف» — والمسودة بلا رقم أصلاً
  /// (الترقيم لحظة الترحيل حصراً — 07 §1.9).
  final String label;
  final String dateText;

  const PeriodDraftInfo({
    required this.docType,
    required this.docId,
    required this.label,
    required this.dateText,
  });
}
