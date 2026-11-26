#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتي b44 — دِقّة (منهجية السجل الموثقة — نمط b37/b40/b42/b43).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً (كل علامة موقّفة على ملفها
     بالمصدر وتُتحقق حرفياً فيه قبل البحث بالثنائي).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. المميِّز محتوى لا أسماء دوال نقية (درس b39/b40 — المرمّز يسقط الأسماء).
  4. المميِّز بالعكس على المرجع الأحدث المتاح — وهو هنا b43 ذاته (ثنائيتا
     التشغيل 43 — مستخرجتان من حزم download/ القياسيتين): علامات س146
     الغائبة عنه حاضرة في b44 فتثبت أن ما بُني هو الجديد حاملاً الكتالوج،
     وما قبلها (استمرارية وس141 وس142 وس144) حاضرة بb43 أصلاً فلا تُفحص
     بالعكس عليه بل تُفحص حضوراً في b44 حصراً (استمرارية).

درسان مستجدّان موثقان (س146/b44):
  • مرشّحان رفضهما الفحص الحي بثنائيتَي b43 مع أنهما من ملفات س146:
    «محفوظة» (مشتركة مع شاشات أُخرى قديمة) و«خانات الوحدة الصغرى عدداً
    صحيحاً بين 0 و8» (سلسلة الحوار اليدوي القديم الباقية) — فالاختبار
    الحي بالعكس سابق لإثبات الأداة لا مجرد وصف لها.
  • بقايا الحوار اليدوي القديم بالواجهة لا تصلح مميِّزاً — والاختلاف
    الحقيقي عناوين الحوار الجديد وتلميح بحثه وسرد الكتالوج في بطاقة
    الشاشة وأسماء الكتالوج وأجزاؤه المنقّحة وتوسعة التققيط وتاريخ
    الإصدار.

أكتُبت لتشغيل إغلاق b44 (س146 تابع): استمرارية أساس 5 + مميِّزات س141
إحدى عشرة + مميِّزات س142 ثلاث + مميِّزات س144 سبع (الإصدار 0.2.3+39
انتقل من التمييز إلى الاستمرارية بحذفه بعد b44) + مميِّزات س146 عشر
(لاتينية 1 وعربية 9).

الاستخدام:
  python3 scripts/verify_b44_markers.py <b44_libapp.so> <b44_app.so> \
      [--ref-android <b43_libapp.so> --ref-windows <b43_app.so>] \
      [--repo <مسار المستودع>]
"""

import argparse
import sys

REPO_DEFAULT = "/home/z/my-project/diqqah"
APP = "packages/app/lib"
DOM = "packages/domain/lib/src"
STO = "packages/storage/lib/src"

# ── الاستمرارية: علامات أساس قديمة يجب أن تبقى ─────────────────────────────
CONTINUITY = [
    (f"{APP}/gate_error_screen.dart", "GateErrorScreen"),
    (f"{STO}/database.dart", "snapshotBeforeUpgrade"),
    ("packages/app/pubspec.yaml", "0.2.3"),
    (f"{APP}/home_screen.dart", "معطلة"),
    (f"{APP}/home_screen.dart", "طلبات الشراء والبيع"),
]

# ── مميِّزات س141: قالبا الافتتاحي والمتابعات ───────────────────────────────
S141 = [
    (f"{DOM}/import_core.dart", "party_balances"),
    (f"{DOM}/import_core.dart", "opening_full"),
    (f"{DOM}/import_core.dart", "DQ-1025"),
    (f"{DOM}/import_core.dart", "DQ-1026"),
    (f"{STO}/database.dart", "import_opening"),
    (f"{STO}/database.dart", "follow_ups_reviewed"),
    (f"{APP}/follow_ups_screen.dart", "لا متابعات الآن — كل شيء متابَع"),
    (f"{APP}/home_screen.dart", "افتح المتابعات"),
    (f"{APP}/import_screen.dart", "تاريخ القيد الافتتاحي"),
    (f"{APP}/follow_ups_screen.dart", "تعديل التاريخ من شاشة الفترات"),
    (f"{DOM}/import_core.dart", "رصيد أول المدة جهة واحدة"),
]

# ── مميِّزات س142: التشطيب ──────────────────────────────────────────────────
S142 = [
    (f"{APP}/import_screen.dart", "ما لا يُستورد بهذا المسار"),
    (f"{APP}/import_screen.dart", "اصطلاح الإشارات"),
    (f"{APP}/import_screen.dart", "هذا استيراد أرصدة لا ترحيل"),
]

# ── مميِّزات س144: الوحدة 3 «كميات المخزون الافتتاحية» (استمرارية الآن) ─────
S144 = [
    # الشريحة الخامسة بالواجهة (زر القالب الخامس)
    (f"{APP}/import_screen.dart", "كميات المخزون"),
    # مقابل الإذن الافتراضي 43 «إيرادات أخرى» (F-209) بالمعاينة
    (f"{APP}/import_screen.dart", "مقابل الإذن: 43 «إيرادات أخرى»"),
    # كود القالب الخامس (المحلل والتخطيط والتنفيذ والتخزين)
    (f"{DOM}/import_core.dart", "opening_qty"),
    # عنوان الاستيراد بالمنطق
    (f"{DOM}/import_core.dart", "استيراد كميات المخزون الافتتاحية"),
    # كود الصنف إلزامي بالوحدة 3 (الوحدة 5 لا تطلبه)
    (f"{DOM}/import_core.dart", "كود الصنف إلزامي (SKU)."),
    # حرس التخزين: لا إذن بلا مستودع نشط
    (f"{STO}/database.dart", "لا مستودع نشط لإذن إدخال كميات المخزون الافتتاحية."),
    # سرد إذن الإدخال F-209 بقيم الملف (تشغيلي حي — لا assert)
    (f"{STO}/database.dart", "إذن إدخال كميات المخزون الافتتاحية — بقيم الملف"),
]

# ── مميِّزات س146: كتالوج ISO 4217 المضمّن (مميِّز بالعكس على b43) ──────────
S146 = [
    # تاريخ الإصدار المحفور kAppVersion (بمصدره الموحد)
    (f"{APP}/backup_center.dart", "0.2.3+40"),
    # عنوان حوار الانتقاء من الكتالوج
    (f"{APP}/currencies_screen.dart", "عملة جديدة — من الكتالوج العالمي ISO 4217"),
    # تلميح البحث ثنائي اللغة
    (f"{APP}/currencies_screen.dart", "ابحث بالكود أو بالاسم (عربي/إنجليزي)"),
    # الاقتراح قابل للتعديل قبل الحفظ حصراً (D-194)
    (f"{APP}/currencies_screen.dart", "قابل للتعديل قبل الحفظ، وبعده لا تعديل (D-194)"),
    # سرد الإضافة من الكتالوج ببطاقة الشاشة
    (f"{APP}/currencies_screen.dart", "الاسم والرمز تُملآن تلقائياً"),
    # بطاقة لا نتائج بالكتالوج (المسار اليدوي المغلق)
    (f"{APP}/currencies_screen.dart", "لا نتائج بالكتالوج — عملات الدفع العالمية كلها"),
    # صف الكتالوج: الدينار الكويتي بدقته الثلاثية
    (f"{DOM}/iso4217_catalog.dart", "دينار كويتي"),
    # اسم الجزء المنقّح: هللة (الريال السعودي)
    (f"{DOM}/iso4217_catalog.dart", "هللة"),
    # توسعة التققيط: الريال السعودي بصيغه الكاملة (D-139)
    (f"{APP}/tafqit.dart", "ريال سعودي"),
    # توسعة التققيط: الليرة التركية المذكرة
    (f"{APP}/tafqit.dart", "ليرة تركية"),
]


def read_marker(repo: str, file_path: str, marker: str) -> str:
    """يقرأ العلامة من المصدر ويتحقق حضورها الحرفي فيه (قاعدة 1)."""
    with open(f"{repo}/{file_path}", encoding="utf-8") as f:
        src = f.read()
    if marker not in src:
        print(f"فشل: العلامة «{marker}» غير موجودة بالمصدر {file_path}")
        sys.exit(2)
    return marker


def encodings(marker: str):
    """البحث بالترميزين معاً (درس b31: العربية UTF-16LE بالثنائي)."""
    utf8 = marker.encode("utf-8")
    utf16 = marker.encode("utf-16-le")
    variants = [utf8]
    if utf16 != utf8:
        variants.append(utf16)
    return variants


def found(blob: bytes, marker: str) -> bool:
    return any(v in blob for v in encodings(marker))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("android")
    ap.add_argument("windows")
    ap.add_argument("--ref-android")
    ap.add_argument("--ref-windows")
    ap.add_argument("--repo", default=REPO_DEFAULT)
    args = ap.parse_args()

    with open(args.android, "rb") as f:
        android = f.read()
    with open(args.windows, "rb") as f:
        windows = f.read()
    ref_android = ref_windows = None
    if args.ref_android and args.ref_windows:
        with open(args.ref_android, "rb") as f:
            ref_android = f.read()
        with open(args.ref_windows, "rb") as f:
            ref_windows = f.read()

    groups = [
        ("استمرارية", CONTINUITY, False),
        ("مميِّزات س141", S141, False),
        ("مميِّزات س142", S142, False),
        ("مميِّزات س144", S144, False),
        ("مميِّزات س146", S146, True),
    ]
    total = 0
    failures = 0
    for label, markers, is_new in groups:
        for file_path, marker in markers:
            marker = read_marker(args.repo, file_path, marker)
            total += 1
            ok_a = found(android, marker)
            ok_w = found(windows, marker)
            if ok_a and ok_w:
                status = "حاضرة بالثنائيتين"
            else:
                status = f"أندرويد={'حاضرة' if ok_a else 'غائبة'} " \
                         f"ويندوز={'حاضرة' if ok_w else 'غائبة'}"
                failures += 1
            line = f"[{label}] {marker}: {status}"
            if is_new and ref_android is not None and ref_windows is not None:
                in_ref = found(ref_android, marker) or \
                    found(ref_windows, marker)
                line += f" | بالمرجع b43: {'حاضرة (ليست مميزاً!)' if in_ref else 'غائبة'}"
                if in_ref:
                    failures += 1
            print(line)

    print(f"\nالحصيلة: {total - failures}/{total} علامة سليمة")
    if failures:
        print(f"فشل: {failures} علامة")
        return 1
    print("CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
