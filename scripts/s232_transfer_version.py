#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س232 — انتقال القيمة الموحد 0.280.0+80 ← 0.284.0+84 (تجاوز موثق
للأرقام الثلاثة 0.281–0.283) بنمط س221..س230 الموثق: تعديل بمواضع
محددة لا استبدالاً أعمى، ثم تحقق بلا بقايا حية والقديم غائب عن
المواضع الحية، والفشل بوابة لا صمت (sys.exit)."""
import io
import sys

OLD = "0.280.0+80"
NEW = "0.284.0+84"

PUBSPEC_COMMENT = """# س232 (المرحلة الأولى دفعتها الرابعة — د12 «استخراج النصوص» وفاء
# D-037): البنية اللغوية (فهرس l10n بمدخل لغة بسطر واحد) واستخراج نصوص
# الشاشات الثلاث الكبرى (الفواتير والإعدادات والتقارير — 506 مفاتيح)
# وحارس نصوص بCI يمنع رجوع المضمن والنمو — وتوثيق تجاوز الترقيم: بعد
# درس س231 (رقم البناء يُقرأ من رقم تشغيل المسار لا من لاحقة pubspec)
# يُعاد اصطفاح minor مع صيغة D-213 (minor = 200 + رقم التشغيل):
# التشغيل القادم b84 فالإصدار 0.284.0+84 وversionCode 2084 — فالأرقام
# 0.281 و0.282 و0.283 تجاوزت عن قصد لا سهواً: لا إصدارات صدرت بها
# ولا مواد أُغلقت عليها (لاحقة +80 كانت منزاحة عن عداد التشغيل منذ
# جولات س227 الثلاث الفاشلة فاستُهلكت أرقام بلا إصدارات) — محجوز
# لبناء b84 بأمر المالك حصراً بنمط الدفعات.
"""

CATALOG_COMMENT = """/// س232: الترميم الموحد 0.284.0+84 — د12 استخراج النصوص (فهرس l10n
/// للشاشات الثلاث الكبرى وحارس CI) — والأرقام 0.281–0.283 تجاوزت
/// عمداً لإعادة اصطفاح minor مع عداد التشغيل (b84 = 0.284 =
/// versionCode 2084 — درس س231) — محجوز لبناء b84 بأمر المالك حصراً.
"""


def transfer():
    changed = {}

    # pubspec.yaml — سطر القيمة حصراً + تعليق س232 قبله.
    path = "packages/app/pubspec.yaml"
    src = io.open(path, encoding="utf-8").read()
    if OLD in src and "س232" not in src:
        old_line = "version: " + OLD
        assert src.count(old_line) == 1, f"{path}: موضع القيمة ليس واحداً"
        src = src.replace(old_line, PUBSPEC_COMMENT + "version: " + NEW)
    changed[path] = src

    # backup_center.dart — الثابت حصراً + تعليق س232 قبله.
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
        src = src.replace("(القيمة انتقلت بس230)", "(القيمة انتقلت بس232)")
        src = src.replace(OLD, NEW)
        src = src.replace("diqqahVersionLine('0.279', '')",
                          "diqqahVersionLine('0.280', '')")
        src = src.replace("diqqahVersionLine('0.279', '79')",
                          "diqqahVersionLine('0.280', '80')")
        src = src.replace("v.0.279", "v.0.280")
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
        live_old = src.count("version: " + OLD) \
            + src.count("kAppVersion = '" + OLD + "'")
        if path.endswith("s215_test.dart"):
            stale = (src.count(OLD)
                     + src.count("diqqahVersionLine('0.279'")
                     + src.count("v.0.279"))
            prev = (src.count("diqqahVersionLine('0.280'")
                    + src.count("v.0.280"))
            print(f"{path}: بقايا ما قبل النقل {stale} — "
                  f"قيم العرض بالسابقة {prev}")
            if live_old or stale or prev != 4 or NEW not in src:
                ok = False
            continue
        quoted = src.count("0.280") - live_old
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
