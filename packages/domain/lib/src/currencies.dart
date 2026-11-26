/// تعدد العملات الفعلي — F-120/F-121/F-124 (الدفعة 34، D-194).
///
/// القرارات الحاكمة الموثقة:
/// - D-070 «الدولار من اليوم الأول»: الليرة أساساً والدولار بجانبها
///   منذ م1-نواة — عملة المستند ولقطة سعر يدوية لحظة العملية وصندوق
///   دولاري مستقل وفرق الصرف المحقق عند السداد (F-122/F-123 منفذة
///   بم1). البنية القائمة لا تُمس.
/// - D-194 (كلمة المالك «أريد إضافة تعدد العملات ل م2»): بنود م3
///   المنقولة إلى م2 وتنفذ هنا حصراً — إدارة العملات الكاملة (F-120)
///   وأسعار الصرف التاريخية (F-121) وتقرير مراكز العملات (F-124).
/// - F-120: تعريف عملات بعدد خانات الوحدة الصغرى لكل منها (SYP=2
///   معتمد D-017)؛ الأساسية واحدة لا ثانية لها أبداً. الإضافة تشريع
///   جديد والتعطيل بلا حذف (نمط المرجع الدائم 03 §6-3) بلا تعديل
///   بعد الحفظ.
/// - F-121: أسعار صرف تاريخية بعدد صحيح مكبَّر (اصطلاح fxRateScale
///   في invoice.dart) — «لا تعديل لسعر محفوظ أبداً»: اليوم المسجل
///   لا يقبل ثانية والسجل المحفوظ لا يُعدل ولا يُحذف (تجميد نمط
///   F-140 بطبقة قاعدة البيانات). ولقطة المستند اليدوية باقية
///   (D-070) — الجدول يملأ الافتراض فحسب لا يلغي الكتابة.
/// - F-124: تقرير مراكز العملات — كل عملة بصناديقها وفواتيرها
///   المفتوحة ومكافئها الأساسي المُخزَّن وآخر سعر مسجل. لا حساب
///   صرف جديد في التقرير: كل مكافئ معروض قيمة مخزنة حقيقة.
/// - الحد الصادق الموثق (D-194): لا تسعير مرجعي آلي ولا تعديل سعر
///   ولا حذف سجل — والأسعار المستقبلية مرفوضة (السعر يسجل لليوم
///   أو الماضي حصراً).
library;

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة: الواجهة وحدها
/// تقرر الصياغة المعروضة (فصل المجال عن العرض — نمط unit_group.dart
/// وitem.dart). البادئة Currency تُسبق الأنواع كالعادة (درس تصادم
/// الأسماء المولدة الموثق س78).
sealed class CurrencyValidationError {
  const CurrencyValidationError();
}

/// كود العملة ليس ثلاثة أحرف لاتينية A-Z (صيغة ISO 4217 الصارمة) —
/// يحمل النص الخام ليُعرض بلسانه.
class CurrencyCodeInvalid extends CurrencyValidationError {
  final String raw;

  const CurrencyCodeInvalid(this.raw);
}

/// كود عملة محفوظ سابقاً (بما فيه المعطل) — تفرد الكود مطلق مهما
/// كان مصيره لاحقاً لأن اللقطات التاريخية تحيل إليه.
class CurrencyCodeTaken extends CurrencyValidationError {
  final String code;

  const CurrencyCodeTaken(this.code);
}

/// بلا اسم للعملة — الاسم إلزامي.
class CurrencyNameRequired extends CurrencyValidationError {
  const CurrencyNameRequired();
}

/// عدد خانات الوحدة الصغرى خارج المدى 0..8 — الصفر عملة بلا كسور
/// (نمط عملات كاملة القيمة) والثمانية سقف التخزين العملي.
class CurrencyMinorUnitsInvalid extends CurrencyValidationError {
  final int value;

  const CurrencyMinorUnitsInvalid(this.value);
}

/// سعر الصرف ليس عدداً مكبَّراً موجباً — الصفر والسالب بلا معنى صرفي.
class CurrencyRateInvalid extends CurrencyValidationError {
  const CurrencyRateInvalid();
}

/// تاريخ السعر ليس ISO «YYYY-MM-DD» صالحاً (D-077 الاصطلاح الموحد).
class CurrencyRateDateInvalid extends CurrencyValidationError {
  final String raw;

  const CurrencyRateDateInvalid(this.raw);
}

/// تاريخ سعر مستقبلي — السعر يُسجل لليوم أو الماضي حصراً (D-194:
/// الحد الصادق — الجدول تاريخي ما بعد واقعي).
class CurrencyRateDateFuture extends CurrencyValidationError {
  final String raw;

  const CurrencyRateDateFuture(this.raw);
}

/// عملة الأساسية لا تُعطَّل ولا يُسجل لها سعر — هي مقياس الكل.
class CurrencyBaseProtected extends CurrencyValidationError {
  const CurrencyBaseProtected();
}

/// عملة محالة للتعطيل عليها مراجع قائمة — تحمل عدد المراجع ليعرضه
/// اللفظ، والعملة المرجعية تظل حية (نمط 03 §6-3 بلا حذف أبداً).
class CurrencyInUse extends CurrencyValidationError {
  final int references;

  const CurrencyInUse(this.references);
}

/// سعر صرف محفوظ كما يقرأ من الجدول — (العملة، اليوم) واحد لا
/// ثانية لهما والسعر المكبَّر باصطلاح fxRateScale الموحد.
class ExchangeRateEntry {
  final int currencyId;
  final String date;
  final int rateToBase;

  const ExchangeRateEntry({
    required this.currencyId,
    required this.date,
    required this.rateToBase,
  });
}

/// مسودة عملة جديدة كما تخرج من نموذج الإضافة قبل التحقق.
class CurrencySpec {
  final String code;
  final String name;
  final int minorUnits;

  const CurrencySpec({
    required this.code,
    required this.name,
    required this.minorUnits,
  });
}

/// تطبيع كود العملة: نزع الفراغات ورفع الحالة — يعود نصاً قد لا
/// يكون صالحاً (التحقق بعدُ هو الحكم).
String normalizeCurrencyCode(String raw) => raw.trim().toUpperCase();

/// صورة تاريخ ISO «YYYY-MM-DD» صالحة تقويماً — نمط الميلاد الموحد
/// (D-077) بنمط فحص stock_transfer.dart: ثلاث مقاطع أرقام وشهور 1..12
/// وأيام 1..31 (الشهور كلها تُقبل يوم 31 فالفاسد الدقيق يمر بلا
/// اختراع — الحكم النهائي لتاريخ المعاملة في محركها).
bool currencyDateValid(String raw) {
  final parts = raw.trim().split('-');
  if (parts.length != 3) return false;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return false;
  if (y < 2000 || y > 2100) return false;
  if (m < 1 || m > 12) return false;
  if (d < 1 || d > 31) return false;
  return parts[0].length == 4 && parts[1].length == 2 && parts[2].length == 2;
}

/// هل التاريخ [raw] (ISO صالح) بعد يوم [todayIso]؟ المقارنة نصية
/// سليمة لأن الصيغة الموحدة مرتبة معجمياً (D-077).
bool currencyDateAfter(String raw, String todayIso) =>
    raw.trim().compareTo(todayIso.trim()) > 0;

/// التحقق قبل الحفظ — يعيد قائمة الأخطاء (فارغة = سليم).
///
/// - [existingCodes] أكواد العملات القائمة (الحي منها والمعطل)
///   مطبَّعة بnormalizeCurrencyCode — التفرد مطلق لا استثناء للمعطل.
List<CurrencyValidationError> validateCurrencySpec(
  CurrencySpec spec, {
  required Set<String> existingCodes,
}) {
  final errors = <CurrencyValidationError>[];
  final code = normalizeCurrencyCode(spec.code);
  final name = spec.name.trim();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
    errors.add(CurrencyCodeInvalid(spec.code));
  } else if (existingCodes.contains(code)) {
    errors.add(CurrencyCodeTaken(code));
  }
  if (name.isEmpty) errors.add(const CurrencyNameRequired());
  if (spec.minorUnits < 0 || spec.minorUnits > 8) {
    errors.add(CurrencyMinorUnitsInvalid(spec.minorUnits));
  }
  return errors;
}

/// التحقق قبل تسجيل سعر صرف (F-121): السعر مكبَّر موجب والتاريخ ISO
/// صالح ليس مستقبلاً والعملة ليست الأساسية (مقياس الكل لا يقاس).
List<CurrencyValidationError> validateExchangeRateRecord({
  required int rateToBase,
  required String date,
  required String todayIso,
  required bool isBase,
}) {
  final errors = <CurrencyValidationError>[];
  if (rateToBase <= 0) errors.add(const CurrencyRateInvalid());
  if (!currencyDateValid(date)) {
    errors.add(CurrencyRateDateInvalid(date));
  } else if (currencyDateAfter(date, todayIso)) {
    errors.add(CurrencyRateDateFuture(date));
  }
  if (isBase) errors.add(const CurrencyBaseProtected());
  return errors;
}

/// سطر إدخال مركز عملة كما يخرج من التخزين — قيم مخزنة حقيقة لا
/// حساب جديد: رصيد الصندوق بالأساسية (من الدفتر) والمتبقي المفتوح
/// بعملة الفاتورة وبأساسها المخزن بلقطة الفاتورة ذاتها.
class CurrencyPositionInput {
  final int currencyId;
  final String code;
  final String name;
  final bool isBase;
  final int boxesCount;
  final int boxesBaseMinor;
  final int openInvoicesCount;
  final int openRemainderDocMinor;
  final int openRemainderBaseMinor;
  final int? latestRateToBase;
  final String? latestRateDate;

  const CurrencyPositionInput({
    required this.currencyId,
    required this.code,
    required this.name,
    required this.isBase,
    required this.boxesCount,
    required this.boxesBaseMinor,
    required this.openInvoicesCount,
    required this.openRemainderDocMinor,
    required this.openRemainderBaseMinor,
    this.latestRateToBase,
    this.latestRateDate,
  });
}

/// سطر مركز عملة معروض — المكافئ الأساسي مجموع القيم المخزنة
/// (صناديق الدفتر + متبقيات الفواتير بلقطاتها) بلا أي تحويل جديد.
class CurrencyPositionRow {
  final int currencyId;
  final String code;
  final String name;
  final bool isBase;
  final int boxesCount;
  final int boxesBaseMinor;
  final int openInvoicesCount;
  final int openRemainderDocMinor;
  final int openRemainderBaseMinor;
  final int totalBaseMinor;
  final int? latestRateToBase;
  final String? latestRateDate;

  const CurrencyPositionRow({
    required this.currencyId,
    required this.code,
    required this.name,
    required this.isBase,
    required this.boxesCount,
    required this.boxesBaseMinor,
    required this.openInvoicesCount,
    required this.openRemainderDocMinor,
    required this.openRemainderBaseMinor,
    required this.totalBaseMinor,
    this.latestRateToBase,
    this.latestRateDate,
  });
}

/// حساب مراكز العملات (F-124) — دالة نقية تختبر بلا قاعدة ولا قنوات:
/// لكل عملة صفها بمكافئها الأساسي المجموع، والأرقام السالبة المرتّبة
/// من الدفتر تمر كما هي (رصيد صندوق سالب واقع موثق بتقرير الصناديق).
List<CurrencyPositionRow> currencyPositionsCompute(
  List<CurrencyPositionInput> inputs,
) {
  return [
    for (final i in inputs)
      CurrencyPositionRow(
        currencyId: i.currencyId,
        code: i.code,
        name: i.name,
        isBase: i.isBase,
        boxesCount: i.boxesCount,
        boxesBaseMinor: i.boxesBaseMinor,
        openInvoicesCount: i.openInvoicesCount,
        openRemainderDocMinor: i.openRemainderDocMinor,
        openRemainderBaseMinor: i.openRemainderBaseMinor,
        totalBaseMinor: i.boxesBaseMinor + i.openRemainderBaseMinor,
        latestRateToBase: i.latestRateToBase,
        latestRateDate: i.latestRateDate,
      ),
  ];
}

/// عرض سعر مخزَّن مكبَّر كنص حقيقي مقرؤاً — 15000000000 → «15000»
/// و1000000 → «1» و15000000 → «15» بلا كسور زائدة؛ والفاصل نقطة
/// إن وجد كسر نصف خانة. البديل يعود فارغاً بلا قيمة.
String displayRateToBase(int? scaledRate) {
  if (scaledRate == null) return '';
  final whole = scaledRate ~/ fxRateScaleConst;
  final frac = scaledRate - whole * fxRateScaleConst;
  if (frac == 0) return '$whole';
  final fracText = frac
      .toString()
      .padLeft(6, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return '$whole.$fracText';
}

/// ثابت المكبَّر محلياً — القيمة نفسها المعتمدة في invoice.dart
/// (fxRateScale) بلا استيراد دائري: الوحدتان تتفقان بالثابت المعتمد
/// وحيد المصدر موثقاً هنا حرفاً.
const int fxRateScaleConst = 1000000;
