#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة الدفعة س219 — انتقال القيمة الموحد بنمط س218 الموثق:
تعديل بايتي حصراً بمواضع محددة لا استبدالاً أعمى (درس الدفعة: الاستبدال
العام لمسّ تاريخياً بس218 واقتباس المالك بالتعليق — فالمواضع هنا
مُسَمّاة حرفاً)، ثم تحقق بلا بقايا تقنية والقديم غائب.

المواضع الثمانية المطلوبة:
  pubspec.yaml        : version: 0.273.0+73            (1 موضع)
  backup_center.dart  : kAppVersion = '0.273.0+73'      (1 موضع)
  s215_test.dart      : التعليق والسطران وقيم العرض     (6 مواضع)
  + تعليقا س219 بكتالوجَي pubspec وbackup_center، وإسناد الحارس بس219.
"""
import io
import sys

OLD = "0.273.0+73"
NEW = "0.274.0+74"

PUBSPEC_COMMENT = """# س219 (بكلمة المالك «قمت بتثبيت 0.273 على الخليوي مع قاعدة البيانات
# الكبيرة… في شاشة الدخول استغرق الوقت من ضغط زر الدخول حتى ظهور رسالة
# بيانات الدخول غير صحيحة تقريباً 4.69 خلال 6 محاولات، هل هذا طبيعي؟»):
# التجزئة والتحقق بعزل الخلفية حصراً (hashInBackground و
# verifyStoredInBackground وequalizingWorkInBackground — 600,000 تكراراً
# بنوى دارت كانت تجمّد خيط الواجهة ~4.7 ثانية كل محاولة قريباً من عتبة
# ANR الإدخالية 5 ثوانٍ) وموازنةُ التوقيت بالرفض الثلاثة فلا قناة تعداد
# توقيتية ومؤشرُ جريان بالبوابة — محجوز لبناء b74 بأمر المالك حصراً.
"""

CATALOG_COMMENT = """/// س219: الترميز الموحد 0.274.0+74 — النواة الحسابية للتجزئة والتحقق
/// بعزل الخلفية وموازنة التوقيت بالرفض الثلاثة (عقد س219 بمدار
/// قابلية الإرسال س218) ومؤشر الجريان بالبوابة — محجوز لبناء b74
/// بأمر المالك حصراً.
"""


def transfer():
    changed = {}

    # pubspec.yaml — سطر القيمة حصراً + تعليق س219 قبله.
    path = "packages/app/pubspec.yaml"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src and "س219" not in src:
        old_line = "version: " + OLD
        assert src.count(old_line) == 1, f"{path}: موضع القيمة ليس واحداً"
        src = src.replace(old_line, PUBSPEC_COMMENT + "version: " + NEW)
    changed[path] = src

    # backup_center.dart — الثابت حصراً + تعليق س219 قبله.
    path = "packages/app/lib/backup_center.dart"
    src = io.open(path, encoding="utf-8").read()
    if "س219" not in src:
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
        src = src.replace("(القيمة انتقلت بس218)", "(القيمة انتقلت بس219)")
        src = src.replace(OLD, NEW)
        src = src.replace("0.273', ''", NEW.split("+")[0].rsplit(".", 1)[0]
                          + "', ''") if False else src
        src = src.replace("diqqahVersionLine('0.273', '')",
                          "diqqahVersionLine('0.274', '')")
        src = src.replace("diqqahVersionLine('0.273', '73')",
                          "diqqahVersionLine('0.274', '74')")
        src = src.replace("v.0.273", "v.0.274")
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
        # وذكرُ التاريخ الموثق (س218: الترميز الموحد 0.273.0+73 بالتعليق)
        # بقايا لا يُمسّ لا يُحسب علّة.
        live_old = src.count("version: " + OLD) \
            + src.count("kAppVersion = '" + OLD + "'") \
            + src.count("diqqahVersionLine('0.273'") \
            + src.count("v.0.273'")
        quoted = src.count("0.273") - live_old
        limit = 2 if path.endswith("backup_center.dart") else (
            1 if path.endswith("pubspec.yaml") else 0)
        print(f"{path}: مواضع حية قديمة {live_old} — تاريخ/اقتباس {quoted}")
        if live_old or quoted > limit or "0.274.0+74" not in src:
            ok = False
    print("CLEAN" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    if "--verify" in sys.argv:
        verify()
    else:
        transfer()
        verify()
