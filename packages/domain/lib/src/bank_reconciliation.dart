/// د10 البنوك (D-224 — س236): مستند التسوية البنكية **بنمط تسوية
/// الصندوق** (س-17/F-067 حرفاً) — الصندوق هنا جارٍ بنكي (نوع الصندوق
/// الجارٍ من الترحيلة v38)، ورصيد كشف البنك المدخل يقارن بالرصيد
/// الدفتري للصندوق فالفرق عجزاً أو زيادة يقيد على 57 (س8 — الحساب
/// الواحد للعجز والزيادة)، وسبب نصي إلزامي للفرق، والفرق صفر لا يولّد
/// تسوية أصلاً (فالصندوقان يتطابقان دفترياً فلا مستند).
library;

import 'journal.dart' show isValidIsoDate;
import 'voucher.dart';

/// مسودة التسوية البنكية — الرصيدان بلقطة إنشاء المسودة (F-122/D-082:
/// عملة الصندوق هي عملة التسوية)، والاتجاه والمبلغ محسوبان من الفرق
/// لا مُدخلين (عقد «بنمط تسوية الصندوق»: العدد الفعلي يقارن بالدفتري).
class BankReconciliationDraft {
  final String dateText;
  final int cashBoxId;

  /// عملة الصندوق البنكي هي عملة التسوية.
  final int currencyId;
  final int fxRate;

  /// رصيد كشف البنك كما في الكشف (المدخل).
  final int statementBalanceDocMinor;

  /// الرصيد الدفتري للصندوق لحظة المسودة (اللقطة).
  final int bookBalanceDocMinor;

  /// سبب الفرق نصي إلزامي (س-17 عينه).
  final String reason;

  const BankReconciliationDraft({
    required this.dateText,
    required this.cashBoxId,
    this.currencyId = 1,
    this.fxRate = baseCurrencyFxRate,
    required this.statementBalanceDocMinor,
    required this.bookBalanceDocMinor,
    required this.reason,
  });

  /// فرق التسوية = الكشف ناقص الدفتري (موجب: البنك أكثر فزيادة).
  int get differenceDocMinor =>
      statementBalanceDocMinor - bookBalanceDocMinor;

  /// الاتجاه محسوب لا مُدخل — زيادة إن كان كشف البنك أكثر.
  CashAdjustmentDirection get direction => differenceDocMinor >= 0
      ? CashAdjustmentDirection.overage
      : CashAdjustmentDirection.shortage;

  /// المبلغ موجب ببنية المسودة (قيمة الفرق المطلقة).
  int get amountDocMinor => differenceDocMinor.abs();
}

/// أخطاء التسوية البنكية البنيوية — والمحركية في محرك التخزين.
sealed class BankReconciliationValidationError {
  const BankReconciliationValidationError();
}

class BankReconDateInvalid extends BankReconciliationValidationError {
  final String dateText;

  const BankReconDateInvalid(this.dateText);
}

class BankReconStatementBalanceInvalid extends BankReconciliationValidationError {
  const BankReconStatementBalanceInvalid();
}

class BankReconReasonRequired extends BankReconciliationValidationError {
  const BankReconReasonRequired();
}

/// الفرق صفر لا يولّد تسوية (الصندوقان متطابقان دفترياً).
class BankReconNoDifference extends BankReconciliationValidationError {
  const BankReconNoDifference();
}

/// الرصيد الدفتري اللقطة سالب (لا يحدث لصندوق سليم) — حرس بنية.
class BankReconBookBalanceInvalid extends BankReconciliationValidationError {
  const BankReconBookBalanceInvalid();
}

/// ─── الأنواع المحركية — تفحصها معاملة التخزين ───

class BankReconNoPeriod extends BankReconciliationValidationError {
  final String dateText;

  const BankReconNoPeriod(this.dateText);
}

class BankReconClosedPeriod extends BankReconciliationValidationError {
  final String dateText;

  const BankReconClosedPeriod(this.dateText);
}

class BankReconBoxMissing extends BankReconciliationValidationError {
  const BankReconBoxMissing();
}

/// الصندوق ليس جارياً بنكياً — التسوية البنكية للبنوك حصراً (نوع
/// الصندوق الجارٍ — الترحيلة v38).
class BankReconBoxNotBank extends BankReconciliationValidationError {
  final String boxName;

  const BankReconBoxNotBank(this.boxName);
}

class BankReconBoxInactive extends BankReconciliationValidationError {
  final String boxLabel;

  const BankReconBoxInactive(this.boxLabel);
}

class BankReconBoxCurrencyMismatch extends BankReconciliationValidationError {
  const BankReconBoxCurrencyMismatch();
}

class BankReconStateNotDraft extends BankReconciliationValidationError {
  final String stateLabel;

  const BankReconStateNotDraft(this.stateLabel);
}

class BankReconciliationValidationException implements Exception {
  final List<BankReconciliationValidationError> errors;

  const BankReconciliationValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق التسوية البنكية: '
      '${errors.map(describeBankReconValidationError).join('؛ ')}';
}

/// المدقق البنيوي لمسودة التسوية البنكية (س-17 عينه بقواعد الرصيدين).
List<BankReconciliationValidationError> validateBankReconciliationStructure(
    BankReconciliationDraft draft) {
  final errors = <BankReconciliationValidationError>[];
  if (!isValidIsoDate(draft.dateText)) {
    errors.add(BankReconDateInvalid(draft.dateText));
  }
  if (draft.statementBalanceDocMinor < 0) {
    errors.add(const BankReconStatementBalanceInvalid());
  }
  if (draft.bookBalanceDocMinor < 0) {
    errors.add(const BankReconBookBalanceInvalid());
  }
  if (draft.amountDocMinor == 0) {
    errors.add(const BankReconNoDifference());
  }
  if (draft.reason.trim().isEmpty) {
    errors.add(const BankReconReasonRequired());
  }
  return errors;
}

/// وصف خطأ التسوية البنكية بلسان المستخدم (عقد رسائل المجال 08).
String describeBankReconValidationError(BankReconciliationValidationError e) {
  switch (e) {
    case BankReconDateInvalid(:final dateText):
      return 'تاريخ التسوية فاسد «$dateText» — الصيغة المعتمدة YYYY-MM-DD';
    case BankReconStatementBalanceInvalid():
      return 'رصيد كشف البنك لا يكون سالباً';
    case BankReconBookBalanceInvalid():
      return 'الرصيد الدفتري للصندوق البنكي لا يكون سالباً';
    case BankReconNoDifference():
      return 'لا فرق بين كشف البنك والدفتري فلا تسوية تُنشأ';
    case BankReconReasonRequired():
      return 'سبب الفرق نصي إلزامي';
    case BankReconNoPeriod(:final dateText):
      return 'لا فترة مالية حاضنة للتاريخ $dateText';
    case BankReconClosedPeriod(:final dateText):
      return 'الفترة الحاضنة للتاريخ $dateText مقفلة';
    case BankReconBoxMissing():
      return 'الصندوق البنكي غير معروف (س-03)';
    case BankReconBoxNotBank(:final boxName):
      return 'الصندوق «$boxName» ليس جارياً بنكياً — التسوية البنكية للبنوك حصراً';
    case BankReconBoxInactive(:final boxLabel):
      return 'حساب الصندوق البنكي «$boxLabel» معطل (03 §6-3)';
    case BankReconBoxCurrencyMismatch():
      return 'عملة التسوية تخالف عملة صندوقها (D-086 معروض)';
    case BankReconStateNotDraft(:final stateLabel):
      return 'التسوية البنكية مرحّلة أصلاً ($stateLabel) — بلا رجوع ولا تعديل (07 §1.2)';
  }
}
