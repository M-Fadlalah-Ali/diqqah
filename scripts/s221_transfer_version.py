#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة الدفعة س221 — انتقال القيمة الموحد بنمط س218/س219 الموثق:
تعديل بايتي حصراً بمواضع محددة لا استبدالاً أعمى (درس الدفعة الموثق:
الاستبدال العام لمسّ تاريخياً واقتباس المالك بالتعليق — فالمواضع هنا
مُسَمّاة حرفاً)، ثم تحقق بلا بقايا تقنية والقديم غائب.

المواضع الثمانية المطلوبة:
  pubspec.yaml        : version: 0.274.0+74            (1 موضع)
  backup_center.dart  : kAppVersion = '0.274.0+74'      (1 موضع)
  s215_test.dart      : التعليق والسطران وقيم العرض     (6 مواضع)
  + تعليقا س221 بكتالوجَي pubspec وbackup_center، وإسناد الحارس بس221.
"""
import io
import sys

OLD = "0.274.0+74"
NEW = "0.275.0+75"

PUBSPEC_COMMENT = """# س221 (بأمر المالك «ابدأ بتنفيذ الدفعات الخمسة بالتسلسل الذي
# عرضته» — دفعة سرعة الدخول والنبض والقوائم): التنفيذ الأصلي للتجزئة
# (المؤجل س219 — قناة منصة PBKDF2-HMAC-SHA256 بمنفذ متسلسل جانب
# المنصة والتحقق الذاتي بمتجه معياري والبديل الخالص بعزل الخلفية
# بعقد س219 حرفاً — بنفس الـ600,000 تكراراً لا خفض أمني) واتساق
# نبض العمل (إزالة الشريط الأحمر وبطاقات النبض الثلاث بأوجهها
# الحقيقية وعلاج خطأ مسار المدخلات اليومية) وعزل النوع بجهة
# الأرشيف وحد العرض المتدرج للقوائم — محجوز لبناء b75 بأمر المالك
# حصراً.
"""

CATALOG_COMMENT = """/// س221: الترميز الموحد 0.275.0+75 — التنفيذ الأصلي للتجزئة (قناة
/// المنصة بالتحقق الذاتي والبديل الخالص بعزل الخلفية — المؤجل س219
/// منفَّذ) واتساق نبض العمل وعزل النوع بجهة الأرشيف وحد العرض
/// المتدرج — محجوز لبناء b75 بأمر المالك حصراً.
"""


def transfer():
    changed = {}

    # pubspec.yaml — سطر القيمة حصراً + تعليق س221 قبله.
    path = "packages/app/pubspec.yaml"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src and "س221" not in src:
        old_line = "version: " + OLD
        assert src.count(old_line) == 1, f"{path}: موضع القيمة ليس واحداً"
        src = src.replace(old_line, PUBSPEC_COMMENT + "version: " + NEW)
    changed[path] = src

    # backup_center.dart — الثابت حصراً + تعليق س221 قبله.
    path = "packages/app/lib/backup_center.dart"
    src = io.open(path, encoding="utf-8").read()
    if "س221" not in src:
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
        src = src.replace("(القيمة انتقلت بس219)", "(القيمة انتقلت بس221)")
        src = src.replace(OLD, NEW)
        src = src.replace("diqqahVersionLine('0.274', '')",
                          "diqqahVersionLine('0.275', '')")
        src = src.replace("diqqahVersionLine('0.274', '74')",
                          "diqqahVersionLine('0.275', '75')")
        src = src.replace("v.0.274", "v.0.275")
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
        # وذكرُ التاريخ الموثق (س219: الترميز الموحد 0.274.0+74
        # بالتعليق) بقايا لا يُمسّ لا يُحسب علّة.
        live_old = src.count("version: " + OLD) \
            + src.count("kAppVersion = '" + OLD + "'") \
            + src.count("diqqahVersionLine('0.274'") \
            + src.count("v.0.274'")
        quoted = src.count("0.274") - live_old
        limit = 2 if path.endswith("backup_center.dart") else (
            1 if path.endswith("pubspec.yaml") else 0)
        print(f"{path}: مواضع حية قديمة {live_old} — تاريخ/اقتباس {quoted}")
        if live_old or quoted > limit or "0.275.0+75" not in src:
            ok = False
    print("CLEAN" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    if "--verify" in sys.argv:
        verify()
    else:
        transfer()
        verify()
