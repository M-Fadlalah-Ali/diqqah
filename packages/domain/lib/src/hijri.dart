/// التقويم الهجري الحسابي المعياري — F-167 (الدفعة 23/D-183): خيار عرض
/// بجانب الميلادي لا غير.
///
/// المنهج الموثق (D-183):
/// - «التقويم الهجري المدني الحسابي المعياري» — نفس اصطلاح ICU/CLDR
///   باسم `islamic`: البداية 1 محرم 1هـ = JDN 1948440، والدورة
///   الثلاثينية 10631 يوماً، والكبيس (355 يوماً) حيث
///   `(11y + 14) mod 30 < 11`، والشهور الفردية 30 والزوجية 29 وذي
///   الحجة 30 في الكبيسة.
/// - الصدق أولاً: هذا تقويم حسابي معياري قد يخالف رؤية المحلّة بيوم
///   أو يومين — فهو عرض بجانب الميلادي لا مرجع حكم ولا توثيق شرعي،
///   والميلادي أساس التخزين والإدخال والتوثيق حصراً (D-077/F-175:
///   لا إدخال هجري أبداً).
///
/// منطق نقي حصراً بلا Flutter ولا Drift (F-010) — وحدات الاختبار
/// تحفظ المراسي الموثقة والدورة والتحويل عكسياً.
library;

/// اليوم اليولياني الرقم (JDN) لتاريخ ميلادي — صيغ الأعداد الصحيحة
/// المعيارية للتقويم الميلادي البroléptique. مدخلات يوم حقيقي مدققة.
int jdnFromGregorian(int year, int month, int day) {
  assert(year >= 1 && month >= 1 && month <= 12 && day >= 1,
      'تاريخ ميلادي حقيقي مطلوب');
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day +
      (153 * m + 2) ~/ 5 +
      365 * y +
      y ~/ 4 -
      y ~/ 100 +
      y ~/ 400 -
      32045;
}

/// هل السنة الهجرية كبيسة (355 يوماً) بقاعدة الدورة المعيارية؟
bool isHijriLeapYear(int hijriYear) {
  assert(hijriYear >= 1, 'سنة هجرية موجبة');
  return (11 * hijriYear + 14) % 30 < 11;
}

/// طول السنة الهجرية بالأيام — 355 كبيسة و354 بسيطة.
int hijriYearLength(int hijriYear) =>
    isHijriLeapYear(hijriYear) ? 355 : 354;

/// طول الشهر الهجري بالأيام — الفردية 30 والزوجية 29 وذي الحجة 30
/// في الكبيسة.
int hijriMonthLength(int hijriYear, int hijriMonth) {
  assert(hijriMonth >= 1 && hijriMonth <= 12, 'شهر هجري 1..12');
  if (hijriMonth == 12) return isHijriLeapYear(hijriYear) ? 30 : 29;
  return hijriMonth.isOdd ? 30 : 29;
}

/// أجزاء الهجري من يوم يولياني رقمي — (سنة، شهر، يوم) بمشي بنيوي
/// على الدورة الثلاثينية لا بصيغ سحرية معتمة.
(int, int, int) hijriPartsFromJdn(int jdn) {
  final days = jdn - 1948440; // صفر = 1 محرم 1هـ
  assert(days >= 0, 'قبل بداية التقويم الهجري لا تحويل');
  final cycles = days ~/ 10631;
  var rem = days - cycles * 10631;
  var yearInCycle = 1;
  while (rem >= hijriYearLength(yearInCycle)) {
    rem -= hijriYearLength(yearInCycle);
    yearInCycle++;
  }
  final year = cycles * 30 + yearInCycle;
  var month = 1;
  while (rem >= hijriMonthLength(year, month)) {
    rem -= hijriMonthLength(year, month);
    month++;
  }
  return (year, month, rem + 1);
}

/// النمط الصارم لنص التاريخ الميلادي ISO «YYYY-MM-DD» (D-077) —
/// أربعة أرقام واثنا عشر شهراً ويوم حقيقي بالسنين الكبيسة الميلادية.
final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

bool isRealGregorianDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return false;
  const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var len = lengths[month - 1];
  if (month == 2 &&
      (year % 4 == 0 && year % 100 != 0 || year % 400 == 0)) {
    len = 29;
  }
  return day <= len;
}

/// التاريخ الهجري الحسابي المعياري لنص ميلادي ISO — نصاً «YYYY-MM-DD»
/// هجرية، أو فارغاً للمدخل غير الصالح (لا اختراع لتاريخ لم يُفهم —
/// الصدق أولاً).
String? hijriFromIsoDate(String isoDateText) {
  final m = _isoDatePattern.firstMatch(isoDateText.trim());
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  if (!isRealGregorianDate(year, month, day)) return null;
  final (hy, hm, hd) = hijriPartsFromJdn(jdnFromGregorian(year, month, day));
  return '${hy.toString().padLeft(4, '0')}'
      '-${hm.toString().padLeft(2, '0')}'
      '-${hd.toString().padLeft(2, '0')}';
}
