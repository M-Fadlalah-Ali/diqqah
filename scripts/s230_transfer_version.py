#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة الدفعة س230 — انتقال القيمة الموحد 0.279.0+79 ← 0.280.0+80
بنمط س221/س223/س225/س227/س229 الموثق: تعديل بايتي حصراً بمواضع محددة
لا استبدالاً أعمى، ثم تحقق بلا بقايا حية والقديم غائب، والفشل بوابة
لا صمت (sys.exit)."""
import io
import sys

OLD = "0.279.0+79"
NEW = "0.280.0+80"

PUBSPEC_COMMENT = """# س230 (المرحلة الأولى دفعتها الثالثة — د11 الجزء الثاني
# «مفاتيح السجلات إلى الخزنة»): جذر سجلات الأحداث والأخطاء بجذر عشوائي
# 256-bit لكل جهاز بخزنته عند أول تشغيل (بواني القاعدة logRootKey —
# بلا حالة كونية)، والمضمّن القائم يُغلق قارئاً إرثياً حصراً، والجذر
# يسافر مغلَّفاً بالنسخة (سجل نوع 4 تحت DEK بأجيال v5/v6) مع تحقق
# سجلات النسخة قبل أي لمس وإعادة ختمها بجذر الجهاز المستقر عليه عند
# الاستعادة — فبذرة المزامنة m4 تُقرأ بعد الاستعادة حرفاً (G-02
# يُغلق للسجلات) — محجوز لبناء b80 بأمر المالك حصراً بنمط الدفعات.
"""

CATALOG_COMMENT = """/// س230: الترميم الموحد 0.280.0+80 — د11 الجزء الثاني (مفاتيح
/// السجلات إلى الخزنة: جذر لكل جهاز يسافر بالنسخة وإعادة ختم عند
/// الاستعادة والقارئ الموحد للأجيال الستة) — محجوز لبناء b80 بأمر
/// المالك حصراً.
"""


def transfer():
    changed = {}

    # pubspec.yaml — سطر القيمة حصراً + تعليق س230 قبله.
    path = "packages/app/pubspec.yaml"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src and "س230" not in src:
        old_line = "version: " + OLD
        assert src.count(old_line) == 1, f"{path}: موضع القيمة ليس واحداً"
        src = src.replace(old_line, PUBSPEC_COMMENT + "version: " + NEW)
    changed[path] = src

    # backup_center.dart — الثابت حصراً + تعليق س230 قبله (لا يُشترط
    # غياب «س230» كله: تعليقات الدفعة تحمل الوسم — المرساة الثابت
    # القديم نفسه، فالإعادة لا تعيد الإدراج).
    path = "packages/app/lib/backup_center.dart"
    src = io.open(path, encoding="utf-8").read()
    old_const = "const String kAppVersion = '" + OLD + "';"
    if src.count(old_const) == 1:
        src = src.replace(
            old_const,
            CATALOG_COMMENT + "const String kAppVersion = '" + NEW + "';")
    changed[path] = src

    # s215_test.dart — الحارس الصلب بقيمه وإسناد الانتقال.
    path = "packages/app/test/s215_test.dart"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src:
        src = src.replace("(القيمة انتقلت بس229)", "(القيمة انتقلت بس230)")
        src = src.replace(OLD, NEW)
        src = src.replace("diqqahVersionLine('0.278', '')",
                          "diqqahVersionLine('0.279', '')")
        src = src.replace("diqqahVersionLine('0.278', '78')",
                          "diqqahVersionLine('0.279', '79')")
        src = src.replace("v.0.278", "v.0.279")
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
            # وقيم عرض ما قبلها 0.278) — وقيم العرض بالنسخة السابقة
            # (0.279) عرفُ نسخ الإصدار أربعاً بالضبط.
            stale = (src.count("0.279.0+79")
                     + src.count("diqqahVersionLine('0.278'")
                     + src.count("v.0.278"))
            prev = (src.count("diqqahVersionLine('0.279'")
                    + src.count("v.0.279"))
            print(f"{path}: بقايا ما قبل النقل {stale} — "
                  f"قيم العرض بالسابقة {prev}")
            if live_old or stale or prev != 4 or NEW not in src:
                ok = False
            continue
        quoted = src.count("0.279") - live_old
        limit = 2 if path.endswith("backup_center.dart") else (
            1 if path.endswith("pubspec.yaml") else 0)
        print(f"{path}: مواضع حية قديمة {live_old} — تاريخ/اقتباس {quoted}")
        if live_old or quoted > limit or NEW not in src:
            ok = False
    print("CLEAN — الترميم الموحد " + NEW) if ok else None
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    if "--verify" in sys.argv:
        verify()
    else:
        transfer()
        verify()
