#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""مولّد كتالوج العملات ISO 4217 المضمّن — س146/D-209.

التشغيل: python3 scripts/gen_iso4217_catalog.py
المتطلبات: pip install babel (المولَّد بbabel 2.18/CLDR 45 — 2026-11-15)

المصادر:
- قائمة العملات النشطة: ISO 4217 (عملات الدفع النقدي حصراً — بلا أكواد
  الأموال BOV/CLF/MXV.. وبلا المعادن XAU/XAG.. وبلا الأكواد الخاصة
  XDR/XTS/XXX وبلا المتقادمة).
- الأسماء العربية والإنجليزية والرموز: CLDR عبر Babel (locale ar/en)
  بتطبيع الرمز: نزع بادئة الحروف اللاتينية (JP¥→¥) ونزع النقطة الختامية
  (ر.س.→ر.س).
- الخانات الافتراضية (دقة الفواصل العشرية): دقة CLDR (get_currency_precision
  — KWD/BHD/OMR/TND/JOD/IQD/LYD=3 وJPY/KRW=0 والباقي 2) مع تجاوزات
  معتمدة: SYP=2 (الوحدة الصغرى ISO والاعتماد المثبت D-017).
- أسماء الجزء العربية: جدول منقَّح يدوياً للشائع — الغائب سلوك عام
  موثق بالتققيط («وX من المئة»).

الناتج: packages/domain/lib/src/iso4217_catalog.dart — توليد آلي كامل،
لا تحرير يدوي عليه. مسار التحديث عند تغيّرات ISO: تشغيل هذا السكربت
ثم مراجعة الفروق بالgit.
"""

from babel.numbers import (
    get_currency_name,
    get_currency_symbol,
    get_currency_precision,
)

# عملات الدفع النشطة وفق ISO 4217 (2026-11) — بلا أكواد الأموال والمعادن
# والاختبار (BOV/CHE/CHW/CLF/COU/MXV/SUC/USN/UYI/UYW/XAU/XAG/XPD/XPT/
# XDR/XTS/XXX/XSU/XUA/XBD) وبلا المتقادم (CUC/MRO/STD/SLL/ZWL/VEF..).
ACTIVE_CODES = [
    "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
    "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BRL",
    "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHF", "CLP", "CNY",
    "COP", "CRC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD", "EGP",
    "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL", "GHS", "GIP", "GMD",
    "GNF", "GTQ", "GYD", "HKD", "HNL", "HTG", "HUF", "IDR", "ILS", "INR",
    "IQD", "IRR", "ISK", "JMD", "JOD", "JPY", "KES", "KGS", "KHR", "KMF",
    "KPW", "KRW", "KWD", "KYD", "KZT", "LAK", "LBP", "LKR", "LRD", "LSL",
    "LYD", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP", "MRU", "MUR",
    "MVR", "MWK", "MXN", "MYR", "MZN", "NAD", "NGN", "NIO", "NOK", "NPR",
    "NZD", "OMR", "PAB", "PEN", "PGK", "PHP", "PKR", "PLN", "PYG", "QAR",
    "RON", "RSD", "RUB", "RWF", "SAR", "SBD", "SCR", "SDG", "SEK", "SGD",
    "SHP", "SLE", "SOS", "SRD", "SSP", "STN", "SYP", "SZL", "THB", "TJS",
    "TMT", "TND", "TOP", "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD",
    "UYU", "UZS", "VED", "VES", "VND", "VUV", "WST", "XAF", "XCD", "XOF",
    "XPF", "YER", "ZAR", "ZMW", "ZWG",
]

# أسماء الجزء العربية المنقَّحة يدوياً — الشائع حصراً، والغائب بلا جزء
# مسمّى فيتقط بسلوكه العام. عملات الدقة صفر لا جزء لها أصلاً.
SUBUNITS_AR = {
    "SAR": "هللة",
    "AED": "فلس",
    "QAR": "درهم",
    "OMR": "بيسة",
    "BHD": "فلس",
    "KWD": "فلس",
    "IQD": "فلس",
    "JOD": "فلس",
    "YER": "فلس",
    "EGP": "قرش",
    "SYP": "قرش",
    "LBP": "قرش",
    "SDG": "قرش",
    "LYD": "درهم",
    "DZD": "سنتيم",
    "TND": "ملّيم",
    "MAD": "سنتيم",
    "TRY": "كوروش",
    "USD": "سنت",
    "EUR": "سنت",
    "GBP": "بنس",
    "CAD": "سنت",
    "AUD": "سنت",
    "NZD": "سنت",
    "HKD": "سنت",
    "SGD": "سنت",
    "ZAR": "سنت",
    "CHF": "سنتيم",
    "INR": "بيسة",
    "PKR": "بيسة",
}


# تجاوزات الخانات الاعتمادة — CLDR يعطي SYP=0 عملياً بينما الوحدة
# الصغرى ISO=2 والاعتماد المثبت بالمشروع D-017 «SYP=2» — فالكتالوج
# يعكس الاعتماد لا الاستعمال العملي (والعملة الأساسية مزروعة أصلاً
# بقيمها فلا تضاف من الكتالوج أبداً).
PRECISION_OVERRIDES = {
    "SYP": 2,
}


def normalize_symbol(raw: str) -> str:
    s = raw.strip()
    # نزع علامات الاتجاه المحصورة داخل الرمز (ل.س.\u200f → ل.س.)
    s = s.replace("\u200f", "").replace("\u200e", "").strip()
    # نزع بادئة الحروف اللاتينية: JP¥→¥، CN¥→¥، US$→$
    i = 0
    while i < len(s) and "A" <= s[i] <= "Z":
        i += 1
    if 0 < i < len(s):
        s = s[i:]
    # نزع النقطة الختامية العرفية بالرموز العربية: ر.س.→ر.س
    while s.endswith("."):
        s = s[:-1]
    return s


def dart_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("$", r"\$")
    )


def main() -> None:
    rows = []
    for code in ACTIVE_CODES:
        name_ar = get_currency_name(code, locale="ar").strip()
        name_en = get_currency_name(code, locale="en").strip()
        symbol = normalize_symbol(get_currency_symbol(code, locale="ar"))
        precision = get_currency_precision(code)
        precision = PRECISION_OVERRIDES.get(code, precision)
        if not name_ar:
            raise SystemExit(f"{code}: اسم عربي فارغ بالـCLDR — راجع يدوياً")
        if not name_en:
            raise SystemExit(f"{code}: اسم إنجليزي فارغ")
        if precision is None or precision < 0 or precision > 3:
            raise SystemExit(f"{code}: دقة شاذة {precision}")
        rows.append(
            (
                code,
                name_ar,
                name_en,
                symbol,
                precision,
                SUBUNITS_AR.get(code),
            )
        )

    codes = [r[0] for r in rows]
    if len(codes) != len(set(codes)):
        raise SystemExit("تكرار كود بالقائمة النشطة")
    if not (155 <= len(rows) <= 165):
        raise SystemExit(f"عدد العملات خارج المدى المتوقع: {len(rows)}")

    rows.sort(key=lambda r: r[0])

    lines = []
    lines.append("// كتالوج العملات ISO 4217 المضمّن — س146/D-209.")
    lines.append("//")
    lines.append("// توليد آلي بالسكربت scripts/gen_iso4217_catalog.py")
    lines.append("// (Babel 2.18 — CLDR 45 — 2026-11-15) — لا تحرير يدوي")
    lines.append("// عليه: التحديث عند تغيّرات ISO بإعادة التشغيل ومراجعة الفروق.")
    lines.append("//")
    lines.append("// - العملات: ISO 4217 نشطة بعملات الدفع حصراً")
    lines.append("//   (بلا أكواد الأموال والمعادن والاختبار والمتقادمة).")
    lines.append("// - nameAr/nameEn/symbol: CLDR (locale ar/en) بتطبيع الرمز")
    lines.append("//   (نزع بادئة الحروف اللاتينية والنقطة الختامية).")
    lines.append("// - minorUnits: دقة الفواصل العشرية الافتراضية من CLDR")
    lines.append("//   (تعكس ISO عملياً) مع تجاوز معتمد SYP=2 — الاقتراح")
    lines.append("//   المعرض للمستخدم قابل للتعديل قبل الحفظ (D-209)")
    lines.append("//   وبعد الحفظ لا تعديل (D-194).")
    lines.append("// - subunitAr: اسم الجزء العربي المنقَّح يدوياً للشائع،")
    lines.append("//   والغائب سلوك عام موثق بالتققيط («وX من المئة»).")
    lines.append("//")
    lines.append("// المصفوفة مرتبة بالكود تصاعدياً وتُفحص سلامتها بالاختبارات")
    lines.append("// (domain/test/iso4217_catalog_test.dart).")
    lines.append("library;")
    lines.append("")
    lines.append("/// صف كتالوج ISO 4217 — قيم ثابتة لا تتغير بعد التوليد.")
    lines.append("class IsoCurrency {")
    lines.append("  /// الكود الحرفي ثلاثي A-Z (ISO 4217 alpha-3).")
    lines.append("  final String code;")
    lines.append("")
    lines.append("  /// الاسم العربي المعروض (CLDR — عربي).")
    lines.append("  final String nameAr;")
    lines.append("")
    lines.append("  /// الاسم الإنجليزي الرسمي (CLDR — إنجليزي) للبحث ثنائي اللغة.")
    lines.append("  final String nameEn;")
    lines.append("")
    lines.append("  /// الرمز المعروض المطبَّع — والغائب يعرض الكود حرفاً")
    lines.append("  /// (نمط currency_display الموثق س50/D-156).")
    lines.append("  final String symbol;")
    lines.append("")
    lines.append("  /// دقة الفواصل العشرية الافتراضية = الوحدة الصغرى ISO")
    lines.append("  /// (0..3 ضمن المدى الأوسع 0..8 بالتحقق F-120).")
    lines.append("  final int minorUnits;")
    lines.append("")
    lines.append("  /// اسم الجزء العربي للتققيط — للشائع المنقَّح حصراً.")
    lines.append("  final String? subunitAr;")
    lines.append("")
    lines.append("  const IsoCurrency({")
    lines.append("    required this.code,")
    lines.append("    required this.nameAr,")
    lines.append("    required this.nameEn,")
    lines.append("    required this.symbol,")
    lines.append("    required this.minorUnits,")
    lines.append("    this.subunitAr,")
    lines.append("  });")
    lines.append("}")
    lines.append("")
    lines.append(
        f"/// الكتالوج الكامل — {len(rows)} عملة دفع نشطة (ISO 4217)."
    )
    lines.append("const List<IsoCurrency> kIso4217Currencies = [")
    for code, ar, en, sym, prec, sub in rows:
        parts = [
            f"code: '{dart_escape(code)}'",
            f"nameAr: '{dart_escape(ar)}'",
            f"nameEn: '{dart_escape(en)}'",
            f"symbol: '{dart_escape(sym)}'",
            f"minorUnits: {prec}",
        ]
        if sub is not None:
            parts.append(f"subunitAr: '{dart_escape(sub)}'")
        lines.append("  IsoCurrency(" + ", ".join(parts) + "),")
    lines.append("];")
    lines.append("")

    out_path = "packages/domain/lib/src/iso4217_catalog.dart"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"وُلِّد {out_path}: {len(rows)} عملة")
    # عينات مرجعية للمراجعة اليدوية السريعة
    for probe in ("SAR", "USD", "KWD", "JPY", "EUR", "TRY", "TND"):
        r = next(x for x in rows if x[0] == probe)
        print(" ", r)


if __name__ == "__main__":
    main()
