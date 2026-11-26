/// المبالغ في دِقَّة: أعداد صحيحة حصراً بوحدات صغرى (minor units) — لا كسور ولا أعداد عشرية.
///
/// هذا أساس قاعدتين معتمدتين في التوثيق:
/// - الكميات أعداد صحيحة بوحدة أساسية أدق (غرام) — 05، س7.
/// - التقريب بقاعدة «آخر خروج يمتص الفارق» (س7: 100,000 ÷ 3 = 33,333 + 33,333 + 33,334).
///
/// القلب صارم: المجال لا يعرف عمليات عشرية إطلاقاً، وكل تحويل عملة/وحدة يقع
/// في حدوده هذا (س2: حرية المرجعيات مع الأعداد الصحيحة ثابتة).
class Money {
  final int amountMinor;

  const Money(this.amountMinor);

  const Money.zero() : amountMinor = 0;

  /// الجمع محصور بالأعداد الصحيحة — لا تقريب ولا تحويل عائم في أي مسار.
  Money add(Money other) => Money(amountMinor + other.amountMinor);

  /// الطرح يرفض النتيجة السالبة افتراضياً — قاعدة السالب الموحدة (س6):
  /// «الرصيد السالب في الصناديق أو في المستودعات غير مسموح إلا بخيار
  /// مفعل بيد المسؤول». الخيار يُفتح بطبقة أعلى (إعدادات)، والمجال هنا
  /// هو القلب الصارم الذي لا يسمح بالسالب بلا تصريح.
  Money subtract(Money other) {
    final result = amountMinor - other.amountMinor;
    if (result < 0) {
      throw const NegativeBalanceException();
    }
    return Money(result);
  }

  bool get isZero => amountMinor == 0;

  bool get isNegative => amountMinor < 0;

  @override
  bool operator ==(Object other) =>
      other is Money && other.amountMinor == amountMinor;

  @override
  int get hashCode => amountMinor.hashCode;

  @override
  String toString() => 'Money($amountMinor)';
}

/// يُرمى عند محاولة طرح تنتج رصيداً سالباً بلا تصريح من المسؤول (س6).
class NegativeBalanceException implements Exception {
  const NegativeBalanceException();

  @override
  String toString() => 'الرصيد السالب غير مسموح — قاعدة السالب الموحدة';
}
