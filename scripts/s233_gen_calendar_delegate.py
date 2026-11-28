#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س233 (D-231 — المرحلة أ/2): مولد وفد التقويم الحاكم فوق MaterialLocalizations.

يقرأ الأعضاء المجردة لMaterialLocalizations من مصدر SDK المستخرج
(tools/flutter — بيئة الحكم 3.47.9 ذاتها) ويولد صنفاً ملفوفاً يمرر كل
عضو إلى الوفد الأساس GlobalMaterialLocalizations حرفاً بنوع عودته
الأصلي ومعامله، ويُستثنى مما يولَّد ما تتحكم به خيارات التقويم فيُكتب
يدوياً بالملف الناتج:
  - firstDayOfWeekIndex  (أول الأسبوع: السبت/الأحد/الاثنين)
  - formatMonthYear      (شهر رأس المنتقي بأسماء الأشهر المختارة)
  - formatFullDate       (التاريخ الطويل بأسماء الأشهر المختارة)

والأعضاء المهجورة في SDK تُمرَّر أيضاً مع تعليق تجاهل موثق
(deprecated_member_override) فلا يسقط الفحص بمعلوماته (درس س126:
flutter analyze يعدّ المعلومات قاتلة).

التوليد آلي حصراً (يد واحدة لا تلمس مئة عضو) — والملف الناتج شيفرة
Dart خالصة تُفحص بأداة س198 كأي ملف. إعادة التوليد تكتب فوق القالب
اليدوي فقط بمفاتيحه الثلاثة فتبقى متطابقة.
"""
import io
import os
import re
import sys

SDK_LOCALIZATIONS = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "..", "tools", "flutter", "packages", "flutter", "lib", "src",
    "material", "material_localizations.dart")
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "packages", "app", "lib", "calendar_localizations.dart")

# الأعضاء المكتوبة يدوياً — لا تُولَّد (تتحكم بها خيارات التقويم).
HAND_WRITTEN = {
    "firstDayOfWeekIndex",
    "formatMonthYear",
    "formatFullDate",
}

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"


def split_top_level(s, sep=","):
    """تقسيم بفواصل المستوى الأعلى حصراً (تعميق الأقواس محفوظ)."""
    parts = []
    buf = []
    depth = 0
    for ch in s:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    if "".join(buf).strip():
        parts.append("".join(buf))
    return parts


def parse_members(src):
    """يستخرج أعضاء الصنف المجرد MaterialLocalizations بتوقيعاتهم."""
    m = re.search(r"^abstract class MaterialLocalizations \{", src, re.M)
    if m is None:
        raise SystemExit("لم يوجد صنف MaterialLocalizations بمصدر SDK — "
                         "تحقق من مسار SDK")
    start = m.end()
    end = src.index("\n}", start)
    body = src[start:end]
    members = []
    buf = []
    deprecated = False
    annotation_depth = 0
    block_depth = 0
    skipped_blocks = 0
    for line in body.splitlines():
        stripped = line.strip()
        if block_depth > 0:
            # داخل جسم كتلي لعضو ملموس — الأعضاء الكتلية بSDK هذه كلها
            # ساكنة (static) فليست من واجهة النسخة، تُتخطى بأكملها.
            block_depth += stripped.count("{") - stripped.count("}")
            continue
        if stripped.endswith("{") and not stripped.endswith("=> {"):
            # بداية جسم كتلي — تُتخطى فقرته كلها (ساكنة بواجهة SDK هذه).
            block_depth = max(1, stripped.count("{") - stripped.count("}"))
            buf = []
            deprecated = False
            skipped_blocks += 1
            continue
        if stripped.startswith("@"):
            # وسم فوق العضو — وسم الحماية يُتخطى (التجاوز يورث وضعه)،
            # والمهجورة تُعلَّم للتجاهل الموثق؛ والوسم متعدد الأسطر
            # (@Deprecated('…') على أسطر) يُتخطى حتى إقفال أقواسه.
            annotation_depth = stripped.count("(") - stripped.count(")")
            if "Deprecated" in stripped:
                deprecated = True
            continue
        if annotation_depth > 0:
            annotation_depth += stripped.count("(") - stripped.count(")")
            if "Deprecated" in stripped:
                deprecated = True
            continue
        if stripped.startswith("static "):
            buf = []
            deprecated = False
            continue
        if not stripped or stripped.startswith("//") or stripped.startswith("///"):
            if not buf:
                continue
        buf.append(line)
        if stripped.endswith(";"):
            sig = " ".join("".join(buf).split())
            buf = []
            was_deprecated = deprecated
            deprecated = False
            sig = sig[:-1].strip()  # الفاصلة المنقوطة
            # عضو ملموس بجسم «=> expr» — يُجرد الجسم ويُمرَّر مثل سواه
            # (الصنف المُنجز بimplements لا يرث شيئاً فكل العضوات تُمرَّر).
            if "=>" in sig:
                sig = sig.split("=>", 1)[0].strip()
            if sig.startswith("assert("):
                # تحقق ثابت داخل الصنف (debugCheckHasMaterialLocalizations)
                # — ليس عضواً فلا يُمرَّر.
                continue
            # عضو getter: «Type get name»
            mg = re.match(r"^(.*?)\s+get\s+(" + IDENT + r")$", sig)
            if mg is not None:
                members.append({
                    "ret": mg.group(1).strip(),
                    "name": mg.group(2),
                    "params": None,
                    "deprecated": was_deprecated,
                })
                continue
            # عضو بمعاملات (أو خاصية بمنهج): «Type name(params)»
            mp = re.match(r"^(.*?)\s+(" + IDENT + r")\((.*)\)$", sig)
            if mp is not None:
                members.append({
                    "ret": mp.group(1).strip(),
                    "name": mp.group(2),
                    "params": mp.group(3).strip(),
                    "deprecated": was_deprecated,
                })
                continue
            # ما لم يفهم — يُرفض بصوت لا صمت (بوابة لا تفشل صامتة).
            raise SystemExit("عضو غير مفهوم بالمولد: %r" % sig)
    print("تخطي أجسام كتلية: %d" % skipped_blocks)
    return members


def param_name(part):
    """اسم المعامل من شطره (تُجرد القيمة الافتراضية والوسوم والنوع)."""
    p = part.split("=")[0].strip()
    p = re.sub(r"^(required|covariant)\s+", "", p)
    tokens = p.split()
    name = tokens[-1] if tokens else ""
    m = re.match(r"^(" + IDENT + r")$", name)
    if m is None:
        raise SystemExit("معامل غير مفهوم: %r" % part)
    return m.group(1)


def call_args(params):
    """أسماء معاملات التوقيع بحجج استدعاء سليمة — التوقيع المختلط
    (موضعي ثم مجموعة مسماة {…} أو اختيارية […] بالذيل) يُقسم أقساماً
    بمستوى أعلى ثم تُعالج كل مجموعة بنوعها فلا يُمرر مسمى موضعياً."""
    args = []
    for seg in split_top_level(params):
        seg = seg.strip()
        if seg.startswith("{"):
            inner = seg[1:-1].strip()
            if inner:
                for part in split_top_level(inner):
                    args.append((param_name(part), True))
        elif seg.startswith("["):
            inner = seg[1:-1].strip()
            if inner:
                for part in split_top_level(inner):
                    args.append((param_name(part), False))
        else:
            args.append((param_name(seg), False))
    return args


def member_override(m):
    lines = []
    lines.append("  @override")
    if m["deprecated"]:
        lines.append("  // SDK أهجر هذا العضو — التمرير باقٍ للتوافق "
                     "(تجاهل موثق على سطر العضو نفسه: تجاوزه واستعماله).")
        lines.append("  // ignore: deprecated_member_override, deprecated_member_use")
    if m["params"] is None:
        lines.append("  %s get %s => _base.%s;" % (m["ret"], m["name"], m["name"]))
        return "\n".join(lines)
    args = call_args(m["params"])
    positional = ", ".join(a for (a, named) in args if not named)
    named_args = ", ".join("%s: %s" % (a, a) for (a, named) in args if named)
    param_decl = m["params"]
    call_list = ", ".join(
        x for x in [positional.strip(), named_args] if x)
    lines.append("  %s %s(%s) => _base.%s(%s);" % (
        m["ret"], m["name"], param_decl, m["name"], call_list))
    return "\n".join(lines)


def main():
    with io.open(SDK_LOCALIZATIONS, encoding="utf-8") as f:
        src = f.read()
    members = parse_members(src)
    overrides = []
    for m in members:
        if m["name"] in HAND_WRITTEN:
            continue
        overrides.append(member_override(m))
    deprecated_n = sum(1 for m in members if m["deprecated"])
    print("أعضاء مجردة: %d (مهجورة: %d) — يُولَّد: %d (ويدوي: %s)" % (
        len(members), deprecated_n, len(overrides),
        ", ".join(sorted(HAND_WRITTEN))))
    header = """// مولَّد آلياً بscripts/s233_gen_calendar_delegate.py (س233 — D-231)
// من مصدر SDK المستخرج (Flutter 3.47.9 — بيئة الحكم ذاتها) — لا يُحرر
// يدوياً إلا القالب اليدوي بمفاتيحه الثلاثة. كل عضو يُمرَّر إلى الوفد
// الأساس حرفاً بنوع عودته الأصلي ومعامله.
library;

import 'dart:ui' show Locale;\n\nimport 'package:flutter/widgets.dart' show LocalizationsDelegate;
import 'package:flutter/material.dart'\n    show MaterialLocalizations, ScriptCategory,\n        TimeOfDay, TimeOfDayFormat;

import 'package:flutter_localizations/flutter_localizations.dart';

import 'calendar_prefs.dart';

/// اللف الحاكم لترجمة المادة فوق وفد الجذر العالمي: يتحكم خيارا التقويم
/// (أسماء الأشهر وأول الأسبوع — D-231) في منتقي التاريخ بشهر رأس
/// المنتقي وفهرس أول أيام الأسبوع وتاريخه الطويل، وكل ما عداها
/// بتمرير حرفي إلى وفد GlobalMaterialLocalizations العربي.
class DiqqahCalendarMaterialLocalizations
    implements MaterialLocalizations {
  DiqqahCalendarMaterialLocalizations(
    this._base, {
    required DiqqahMonthNames monthNames,
    required DiqqahWeekStart weekStart,
  })  : _monthNames = monthNames,
        _weekStart = weekStart;

  final MaterialLocalizations _base;
  final DiqqahMonthNames _monthNames;
  final DiqqahWeekStart _weekStart;

  // ═══ القالب اليدوي — مفاتيح التقويم الثلاثة (لا تُولَّد) ═══

  /// أول أيام الأسبوع بجدول المنتقي: فهرس أيام الأسبوع 0 = الأحد
  /// (عرف MaterialLocalizations) فالسبت 6 والاثنين 1.
  @override
  int get firstDayOfWeekIndex => diqqahWeekStartIndex(_weekStart);

  /// شهر رأس المنتقي بأسماء الأشهر المختارة — «تشرين الثاني 2026».
  @override
  String formatMonthYear(DateTime date) =>
      '${diqqahMonthName(date.month, names: _monthNames)} ${date.year}';

  /// التاريخ الطويل بأسماء الأشهر المختارة — «28 تشرين الثاني 2026».
  @override
  String formatFullDate(DateTime date) =>
      formatDiqqahLongDate(date, names: _monthNames);

  // ═══ التمرير الحرفي — مولَّد آلياً ═══

"""
    footer = """}

/// وفد التقويم الحاكم — يُبنى بقيم الخيارين الجاريتين فيرى الجديدَ جذرُ
/// التطبيق بإعادة بنائه (وفد جديد بكل بناء فإعادة تحميل بلا ثمن يذكر)،
/// ولا يدعم إلا العربية فلا ينزلق على لغة أخرى (عرف D-129).
class DiqqahCalendarMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const DiqqahCalendarMaterialLocalizationsDelegate({
    required this.monthNames,
    required this.weekStart,
  });

  final DiqqahMonthNames monthNames;
  final DiqqahWeekStart weekStart;

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ar';

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    final base = await GlobalMaterialLocalizations.delegate.load(locale);
    return DiqqahCalendarMaterialLocalizations(
      base,
      monthNames: monthNames,
      weekStart: weekStart,
    );
  }

  @override
  bool shouldReload(DiqqahCalendarMaterialLocalizationsDelegate old) => true;
}
"""
    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write(header + "\n".join(overrides) + "\n" + footer)
    print("كُتب: %s (%d عضواً ممرَّراً)" % (OUT, len(overrides)))


if __name__ == "__main__":
    main()
