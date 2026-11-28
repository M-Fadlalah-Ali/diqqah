#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة الدفعة س229 — انتقال القيمة الموحد 0.278.0+78 ← 0.279.0+79
بنمط س221/س223/س225/س227 الموثق: تعديل بايتي حصراً بمواضع محددة لا
استبدالاً أعمى، ثم تحقق بلا بقايا حية والقديم غائب، والفشل بوابة
لا صمت (sys.exit)."""
import io
import sys

OLD = "0.278.0+78"
NEW = "0.279.0+79"

PUBSPEC_COMMENT = """# س229 (بأمر المالك «وحّد الانطلاقة / وابدأ د11 / وابن 0.279» —
# المرحلة الأولى دفعتها الثانية): د11 الجزء الأول «المفاتيح إلى
# الخزنة» — جيل النسخ v4 بمفاتيح الخزنة (جذر عشوائي 256-bit لكل
# جهاز عند أول تشغيل + رمز استرداد مطبوع مرة واحدة بنمط v3 — سجلان
# يغلّفان DEK: مفتاح الجهاز صامتاً والرمز على أي جهاز آخر فN-005
# يلتئم بلا كسر)، والقراءة الإرثية v1/v2/v3 حرفاً — وتوحيد
# الانطلاقة بالعمل الفني الديواني الجديد (الخلفية الفحمية
# 30,30,30 بالطبقتين وواجهة أندرويد 12+ وألوان شاشة الافتتاح) —
# محجوز لبناء b79 بأمر المالك حصراً بنمط الدفعات.
"""

CATALOG_COMMENT = """/// س229: الترميز الموحد 0.279.0+79 — المرحلة الأولى دفعتها الثانية:
/// د11 الجزء الأول (مفاتيح النسخ إلى الخزنة بجيل v4 ورمز استرداد
/// مطبوع مرة واحدة) وتوحيد الانطلاقة بالعمل الفني الجديد — محجوز
/// لبناء b79 بأمر المالك حصراً.
"""


def transfer():
    changed = {}

    # pubspec.yaml — سطر القيمة حصراً + تعليق س229 قبله.
    path = "packages/app/pubspec.yaml"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src and "س229" not in src:
        old_line = "version: " + OLD
        assert src.count(old_line) == 1, f"{path}: موضع القيمة ليس واحداً"
        src = src.replace(old_line, PUBSPEC_COMMENT + "version: " + NEW)
    changed[path] = src

    # backup_center.dart — الثابت حصراً + تعليق س229 قبله.
    path = "packages/app/lib/backup_center.dart"
    src = io.open(path, encoding="utf-8").read()
    if "س229" not in src:
        old_const = "const String kAppVersion = '" + OLD + "';"
        assert src.count(old_const) == 1, f"{path}: الثابت ليس واحداً"
        src = src.replace(old_const,
                          CATALOG_COMMENT
                          + "const String kAppVersion = '" + NEW + "';")
    changed[path] = src

    # s215_test.dart — الحارس الصلب بقيمه وإسناد الانتقال.
    path = "packages/app/test/s215_test.dart"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src:
        src = src.replace("(القيمة انتقلت بس227)", "(القيمة انتقلت بس229)")
        src = src.replace(OLD, NEW)
        src = src.replace("diqqahVersionLine('0.277', '')",
                          "diqqahVersionLine('0.278', '')")
        src = src.replace("diqqahVersionLine('0.277', '77')",
                          "diqqahVersionLine('0.278', '78')")
        src = src.replace("v.0.277", "v.0.278")
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
        # وذكرُ التاريخ الموثق بقايا لا يُمسّ لا يُحسب علّة.
        live_old = src.count("version: " + OLD) \
            + src.count("kAppVersion = '" + OLD + "'")
        if path.endswith("s215_test.dart"):
            # الحارس: لا بقايا ما قبل النقل (القيمة الكاملة القديمة
            # وقيم عرض ما قبلها 0.277) — وقيم العرض بالنسخة السابقة
            # (0.278) عرفُ نسخ الإصدار أربعاً بالضبط.
            stale = (src.count("0.278.0+78")
                     + src.count("diqqahVersionLine('0.277'")
                     + src.count("v.0.277"))
            prev = (src.count("diqqahVersionLine('0.278'")
                    + src.count("v.0.278"))
            print(f"{path}: بقايا ما قبل النقل {stale} — "
                  f"قيم العرض بالسابقة {prev}")
            if live_old or stale or prev != 4 or NEW not in src:
                ok = False
            continue
        quoted = src.count("0.278") - live_old
        limit = 2 if path.endswith("backup_center.dart") else (
            1 if path.endswith("pubspec.yaml") else 0)
        print(f"{path}: مواضع حية قديمة {live_old} — تاريخ/اقتباس {quoted}")
        if live_old or quoted > limit or NEW not in src:
            ok = False
    print("CLEAN — الترميز الموحد " + NEW) if ok else None
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    if "--verify" in sys.argv:
        verify()
    else:
        transfer()
        verify()
