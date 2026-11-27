#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة الدفعة س227 — انتقال القيمة الموحد 0.277.0+77 ← 0.278.0+78
بنمط س221/س223/س225 الموثق: تعديل بايتي حصراً بمواضع محددة لا
استبدالاً أعمى، ثم تحقق بلا بقايا حية والقديم غائب، والفشل بوابة
لا صمت (sys.exit)."""
import io
import sys

OLD = "0.277.0+77"
NEW = "0.278.0+78"

PUBSPEC_COMMENT = """# س227 (بأمر المالك «حسب خارطة الطريق سنبدأ المرحلة صفر بقراراتها
# الثمانية مع استثناء حد أدنى لكلمة السر 8 محارف ابدأ التنفيذ» —
# المرحلة صفر من خارطة طريق التقرير الاستشاري): دفعة الأمن والحضور —
# تدوير الخاتم إلى أسرار GitHub وبوابة فحص أسرار (د2)، وقفل محاولات
# الدخول المتدرج بلا حد أدنى للكلمة باستثناء صريح (د3)، وبوابة
# القوائم المالية الفرعية reports.financials (د4 — ترحيلتا v36/v37)،
# ولقطة ما قبل الاستعادة مغلَّفة v2 وallowBackup=false (د5)، وتفعيل
# flutter_lints بمعايرة موثقة (د1)، والأيقونة والانطلاقة بالهوية (د6)،
# والثلاثي الجذري README/LICENSE/CHANGELOG (د7)، وقرارات الوحدات
# المؤجلة D-219..D-222 (د8) — محجوز لبناء b78 بأمر المالك حصراً
# بنمط الدفعات.
"""

CATALOG_COMMENT = """/// س227: الترميز الموحد 0.278.0+78 — المرحلة صفر من خارطة طريق
/// التقرير الاستشاري: الأمن والحضور (تدوير الخاتم وبوابة الأسرار
/// وقفل الدخول المتدرج وبوابة القوائم المالية ولقطة v2 وallowBackup
/// واللينت والأيقونة والثلاثي الجذري وقرارات الوحدات) — محجوز لبناء
/// b78 بأمر المالك حصراً.
"""


def transfer():
    changed = {}

    # pubspec.yaml — سطر القيمة حصراً + تعليق س227 قبله.
    path = "packages/app/pubspec.yaml"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src and "س227" not in src:
        old_line = "version: " + OLD
        assert src.count(old_line) == 1, f"{path}: موضع القيمة ليس واحداً"
        src = src.replace(old_line, PUBSPEC_COMMENT + "version: " + NEW)
    changed[path] = src

    # backup_center.dart — الثابت حصراً + تعليق س227 قبله.
    path = "packages/app/lib/backup_center.dart"
    src = io.open(path, encoding="utf-8").read()
    if "س227" not in src:
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
        src = src.replace("(القيمة انتقلت بس225)", "(القيمة انتقلت بس227)")
        src = src.replace(OLD, NEW)
        src = src.replace("diqqahVersionLine('0.276', '')",
                          "diqqahVersionLine('0.277', '')")
        src = src.replace("diqqahVersionLine('0.276', '76')",
                          "diqqahVersionLine('0.277', '77')")
        src = src.replace("v.0.276", "v.0.277")
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
            # وقيم عرض ما قبلها 0.276) — وقيم العرض بالنسخة السابقة
            # (0.277) عرفُ نسخ الإصدار أربعاً بالضبط.
            stale = (src.count("0.277.0+77")
                     + src.count("diqqahVersionLine('0.276'")
                     + src.count("v.0.276"))
            prev = (src.count("diqqahVersionLine('0.277'")
                    + src.count("v.0.277"))
            print(f"{path}: بقايا ما قبل النقل {stale} — "
                  f"قيم العرض بالسابقة {prev}")
            if live_old or stale or prev != 4 or NEW not in src:
                ok = False
            continue
        quoted = src.count("0.277") - live_old
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
