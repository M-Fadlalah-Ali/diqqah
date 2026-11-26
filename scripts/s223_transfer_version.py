#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة الدفعة س223 — انتقال القيمة الموحد بنمط س221/س219 الموثق:
تعديل بايتي حصراً بمواضع محددة لا استبدالاً أعمى (درس الدفعة الموثق:
الاستبدال العام لمسّ تاريخياً واقتباس المالك بالتعليق — فالمواضع هنا
مُسَمّاة حرفاً)، ثم تحقق بلا بقايا تقنية والقديم غائب.

المواضع الثمانية المطلوبة:
  pubspec.yaml        : version: 0.275.0+75            (1 موضع)
  backup_center.dart  : kAppVersion = '0.275.0+75'      (1 موضع)
  s215_test.dart      : التعليق والسطران وقيم العرض     (6 مواضع)
  + تعليقا س223 بكتالوجَي pubspec وbackup_center، وإسناد الحارس بس223.
"""
import io
import sys

OLD = "0.275.0+75"
NEW = "0.276.0+76"

PUBSPEC_COMMENT = """# س223 (بأمر المالك «قم بتنفيذ المتبقي من د5 بالكامل ولا تنس
# الدفع والتوثيق والبناء 0.276» — دفعة إتمام قوائم المستندات): الحد
# المتدرج الموحد بنمط list_display.dart على بقية القوائم الموثقة —
# تبويبات السندات الثلاثة (عبر المساعد الموحد _tabList) وأرشيف
# الطلبات ومعاينات مستندات المخزون (الإذنان والتحويل والجرد — بدل
# السقف الصلب take(10) الذي كان يحجب الأقدم نهائياً) وأسطر كشف
# الحساب — القراءة كاملة لا مساس بها والحد بناء واجهة حصراً وزر
# التوسيع بعدّاد الباقي — محجوز لبناء b76 بأمر المالك حصراً.
"""

CATALOG_COMMENT = """/// س223: الترميز الموحد 0.276.0+76 — المتبقي من د5 منفَّذاً: الحد
/// المتدرج الموحد على تبويبات السندات الثلاثة وأرشيف الطلبات
/// ومعاينات مستندات المخزون وأسطر كشف الحساب (نمط list_display.dart
/// بعقد س221 — الحد بناء واجهة حصراً) — محجوز لبناء b76 بأمر المالك
/// حصراً.
"""


def transfer():
    changed = {}

    # pubspec.yaml — سطر القيمة حصراً + تعليق س223 قبله.
    path = "packages/app/pubspec.yaml"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src and "س223" not in src:
        old_line = "version: " + OLD
        assert src.count(old_line) == 1, f"{path}: موضع القيمة ليس واحداً"
        src = src.replace(old_line, PUBSPEC_COMMENT + "version: " + NEW)
    changed[path] = src

    # backup_center.dart — الثابت حصراً + تعليق س223 قبله.
    path = "packages/app/lib/backup_center.dart"
    src = io.open(path, encoding="utf-8").read()
    if "س223" not in src:
        old_const = "const String kAppVersion = '" + OLD + "';"
        assert src.count(old_const) == 1, f"{path}: الثابت ليس واحداً"
        src = src.replace(old_const,
                          CATALOG_COMMENT
                          + "const String kAppVersion = '" + NEW + "';")
    changed[path] = src

    # s215_test.dart — الحارس الصلب بقيمه الثماني وإسناد الانتقال.
    path = "packages/app/test/s215_test.dart"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src:
        src = src.replace("(القيمة انتقلت بس221)", "(القيمة انتقلت بس223)")
        src = src.replace(OLD, NEW)
        src = src.replace("diqqahVersionLine('0.275', '')",
                          "diqqahVersionLine('0.276', '')")
        src = src.replace("diqqahVersionLine('0.275', '75')",
                          "diqqahVersionLine('0.276', '76')")
        src = src.replace("v.0.275", "v.0.276")
    changed[path] = src

    for path, src in changed.items():
        with io.open(path, "w", encoding="utf-8") as f:
            f.write(src)


def verify():
    ok = True
    for path in ("packages/app/pubspec.yaml",
                 "packages/app/lib/backup_center.dart",
                 "packages/app/test/s215_test.dart"):
        src = io.open(path, encoding="utf-8").read()
        # الصدق: المواضع التقنية الحية (سطر pubspec وثابت الكتالوج
        # وقيم الحارس) بالقيمة الجديدة حصراً، والقديم بلا موضع حي —
        # وذكرُ التاريخ الموثق (س223: الترميز الموحد 0.275.0+75
        # بالتعليق) بقايا لا يُمسّ لا يُحسب علّة.
        live_old = src.count("version: " + OLD) \
            + src.count("kAppVersion = '" + OLD + "'") \
            + src.count("diqqahVersionLine('0.275'") \
            + src.count("v.0.275'")
        quoted = src.count("0.275") - live_old
        limit = 2 if path.endswith("backup_center.dart") else (
            1 if path.endswith("pubspec.yaml") else 0)
        print(f"{path}: مواضع حية قديمة {live_old} — تاريخ/اقتباس {quoted}")
        if live_old or quoted > limit or "0.276.0+76" not in src:
            ok = False
    print("CLEAN" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    if "--verify" in sys.argv:
        verify()
    else:
        transfer()
        verify()
