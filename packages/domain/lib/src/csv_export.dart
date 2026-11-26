/// تصدير التقارير CSV (F-166 — الدفعة 20) — بناء نقي حصراً بلا Flutter
/// ولا قاعدة بيانات (F-010، 07 §1.8): صورة نصية للعرض الحالي تُجمَّع من
/// الصفوف ذاتها التي تُعرض وتُرسل للطباعة، فأرقام الملف أرقام الشاشة
/// حرفاً ولا إعادة حساب — العرف الموثق في 02 و04: «زر تصدير على كل
/// تقرير ينتج ملف CSV بترميز UTF-8 مع BOM لعرض عربي سليم في Excel —
/// صورة للعرض الحالي لا إعادة حساب».
///
/// الفاصل فاصلة (RFC 4180) والأسطر `\n`، والحقل الذي يحمل فاصلة أو
/// تنصيصاً أو نهاية سطر يُقتبس ويُضاعف التنصيص داخله. والترميز UTF-8
/// مع BOM (يُلحق أول النص كي يفتح الملف في Excel بعربي سليم).
library;

/// علامة BOM (زورد الترتيب) تُلحق أول الملف — عرف F-166 الموثق كي يقرأ
/// Excel العربية سليمة بلا فكّ مشوّه.
const String csvUtf8Bom = '\uFEFF';

/// تهريب حقل CSV واحد: ما يحمل فاصلة أو تنصيصاً أو نهاية سطر يُقتبس
/// ويُضاعف التنصيص الداخلي — والباقي يمر كما هو بلا علامات زائدة.
String csvEscapeField(String field) {
  final needsQuotes = field.contains(',') ||
      field.contains('"') ||
      field.contains('\n') ||
      field.contains('\r');
  if (!needsQuotes) return field;
  return '"${field.replaceAll('"', '""')}"';
}

/// بناء نص CSV لصورة تقرير كاملة: سطر العنوان ثم سطر فارغ ثم ترويسة
/// الأعمدة ثم الصفوف بترتيبها المعروض ثم خلاصة التذييل زوجاً زوجاً —
/// البنية نفسها التي يحملها المطبوع (العنوان/الأعمدة/الصفوف/التذييل).
String buildCsvSnapshot({
  required String title,
  required List<String> columns,
  required List<List<String>> rows,
  List<(String, String)> footer = const [],
}) {
  final buffer = StringBuffer(csvUtf8Bom);
  buffer.writeln(csvEscapeField(title));
  buffer.writeln();
  buffer.writeln([for (final column in columns) csvEscapeField(column)].join(','));
  for (final row in rows) {
    buffer
        .writeln([for (final cell in row) csvEscapeField(cell)].join(','));
  }
  for (final pair in footer) {
    buffer.writeln('${csvEscapeField(pair.$1)},${csvEscapeField(pair.$2)}');
  }
  return buffer.toString();
}
