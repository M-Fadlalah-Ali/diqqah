/// منطق كتالوج ISO 4217 — س146/D-209 — يدوي لا توليدي: التوليد للبيانات
/// حصراً (iso4217_catalog.dart بسكربت scripts/gen_iso4217_catalog.py)
/// وهنا دوال نقية للجلب والبحث تختبر بلا قاعدة ولا قنوات (نمط المجال).
library;

import 'iso4217_catalog.dart';

/// جلب صف الكتالوج بكود العملة — التطبيع بنمط normalizeCurrencyCode
/// الموحد (نزع الفراغات ورفع الحالة)، والغائب عن الكتالوج بلا صف.
/// الكود المشتت (لا ثلاثة أحرف) يعود بلا صف بلا استثناء.
IsoCurrency? isoCurrencyByCode(String raw) {
  final code = raw.trim().toUpperCase();
  if (code.length != 3) return null;
  for (final c in kIso4217Currencies) {
    if (c.code == code) return c;
  }
  return null;
}

/// البحث بالكتالوج للانتقاء بشاشة العملات — الاستعلام الفارغ يعود
/// بالكتالوج كاملاً، وإلا فترشيح بأي من: احتواء الكود (بلا حس للحالة)،
/// أو احتواء الاسم العربي، أو احتواء الاسم الإنجليزي (بلا حس للحالة).
/// الترتيب ملزم بالكود التصاعدي فنتائج الاستعلامات المتكافئة مستقرة.
List<IsoCurrency> isoCurrenciesSearch(String rawQuery) {
  final q = rawQuery.trim();
  if (q.isEmpty) return kIso4217Currencies;
  final codeProbe = q.toUpperCase();
  final lower = q.toLowerCase();
  return [
    for (final c in kIso4217Currencies)
      if (c.code.contains(codeProbe) ||
          c.nameAr.contains(q) ||
          c.nameEn.toLowerCase().contains(lower))
        c,
  ];
}
