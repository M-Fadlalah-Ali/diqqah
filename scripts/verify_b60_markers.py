#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 60 (b60 بحكم الأمر) — دِقّة
(منهجية السجل الموثقة — نمط b37..b59).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً (كل علامة موقّفة على ملفها
     بالمصدر وتُتحقق حرفياً فيه قبل البحث بالثنائي — درس b39/b40).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. المميِّز بالعكس على المرجع الأحدث المتاح — وهو هنا b59 ذاته (ثنائيتا
     التشغيل 59): مميِّزات س203 (صندوق الوصول السريع بلساناته و«مردود
     من هذه الفاتورة» وبيانات المنشأة والطباعة التجارية ومرشّح الإصدار
     0.2.3+60) الغائبة عن b59 حاضرة في b60 فتثبت أن ما بُني هو الجديد
     الحامل للدفعة، وما قبله (الاستمرارية وس141..س186/س198/س202) حاضر
     بb59 أصلاً فلا يُفحص بالعكس عليه بل يُفحص حضوراً في b60 حصراً.

  **D-213 (2026-11-21 — إعادة تسمية الإصدارات بكلمة المالك «b60 أول
  إصدار ينتقل ليصبح 0.260 دون الإضافات الأخرى»): مرشّح الإصدار هنا
  «0.260.0+60» (pubspec وكتالوج الإصدار معاً حرفاً) — والانتقال
  الجديد للتسمية: مرشّح النظام القديم «0.2.3+60» غائب عن ثنائيتَي
  b60 حصراً (لا مرجعاً له بالعكس إذ لم يُبن قط بحزمة — وحد صادق
  موثق بالأداة: انتقال الإلغاء قبل البناء).

انتقالات موثقة (نمط الأسلاف):
  - **إصلاح س203 بأداة الحقبة (2026-11-21)**: مرشّح الاستمرارية الموروث
    «0.2.3» على pubspec (بب58.CONTINUITY) انتقل مع D-213 فلا سطراً
    بالمصدر الآن — فتُسقَط من الاستمرارية بنمط old_version_58 ذاته
    ويحكم غيابه الثنائي انتقالاً كاملاً بالمرجع أدناه — فلا فشل
    أداةَ بإعادة التسمية (الخطوة ⑤ بأداة البناء سليمة حصراً).
  - مرشّح الإصدار «0.2.3+59» انتقل من الأداة بحذفه بعد b59 (نمط
    0.2.3+39/40/41/43/44/46/47/49/50/55/56/57/58/59) — وحلّ محله
    «0.2.3+60» بمجموعة الجديد — والانتقال موثق فحصاً: «0.2.3+59»
    غائب عن ثنائيتَي b60.
  - **انتقال الإزالة س203 (بأمر المالك «يظهر في شرح الأيقونة عبارة
    متاحة الآن ولا داعي لها»): البادئة «متاحة الآن — » زالت من تلميحات
    البلاطات الثماني عشر — فهي حاضرة بمرجع b59 وغائبة عن b60 حصراً:
    أول انتقال إزالةٍ بنمط عكس الحذف الموثق للإصدار.
  - الحدود الصادقة للمميِّز الثنائي بb60: م1 (البني للهوية) ألوانٌ لا
    نصوص فلا مميِّز ثنائي لها أصلاً (نمط م5 بس202) — وم3 («+» كشف
    الحساب بinitialPartyId) بنية بارامتر ولسان الزر «سند جديد» حاضر
    بb59 أصلاً (لسان FAB السندات) فلا تمييزاً له — وم6 (صقل M3:
    cardTheme ونقل الجلسة إلى AppBar) بنية ثيم وويدجت لا نص مستخدم —
    والجلسة نفسها نصوصها ('$user.name (دورها)') مركبة وقت التشغيل فلا
    لسان ثابتاً يُميَّز.

الاستخدام:
  python3 scripts/verify_b60_markers.py <b60_libapp.so> <b60_app.so> \
      [--ref-android <b59_libapp.so> --ref-windows <b59_app.so>] \
      [--repo <مسار المستودع>]
"""

import argparse
import importlib.util
import os
import sys

REPO_DEFAULT = "/home/z/my-project/diqqah"
_SCRIPTS = os.path.dirname(os.path.abspath(__file__))


def _load_b59_tool():
    """يحمّل أداة b59 لوراثة سلسلتها بنمطها الموثق — أداة السجل الواحدة
    لا نسخ متفرقة تُنسى تسويغها."""
    path = os.path.join(_SCRIPTS, "verify_b59_markers.py")
    spec = importlib.util.spec_from_file_location("verify_b59_markers", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def encodings(marker: str):
    utf8 = marker.encode("utf-8")
    utf16 = marker.encode("utf-16-le")
    return [utf8] if utf16 == utf8 else [utf8, utf16]


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

    b59 = _load_b59_tool()
    b58 = b59._load_b58_tool()

    # وراثة سلسلة b59 كاملة بنفس بنائها: مجموعات b58 ناقص انتقالاته
    # الموثقة، ثم تثبيتا التسمية، ثم مميِّزات س202 نفسها استمراريةً —
    # ناقص مرشّح الإصدار القديم (0.2.3+59) فهو انتقال b60.
    b58_groups = [
        ("استمرارية", b58.CONTINUITY),
        ("مميِّزات س141", b58.S141),
        ("مميِّزات س142", b58.S142),
        ("مميِّزات س144", b58.S144),
        ("مميِّزات س146", b58.S146),
        ("مميِّزات س148", b58.S148),
        ("مميِّزات س149", b58.S149),
        ("مميِّزات س150", b58.S150),
        ("مميِّزات س153", b58.S153),
        ("مميِّزات س158", b58.S158),
        ("مميِّزات س160", b58.S160),
        ("مميِّزات س162", b58.S162),
        ("مميِّزات س164", b58.S164),
        ("مميِّزات س170..س175", b58.S170_175),
        ("مميِّزات س178 (استمرارية بعد b56)", b58.S178),
        ("مميِّزات س181/س182 (استمرارية بعد b57)", b58.S181_S182),
    ]
    renamed_58 = (f"{b58.APP}/home_screen.dart", "طلبات الشراء والبيع")
    old_version_58 = ("packages/app/lib/backup_center.dart", "0.2.3+58")
    # D-213 (س203): مرشّح الصيغة القديمة على pubspec نفسه («0.2.3» —
    # وراثة CONTINUITY بb58) انتقل مع إعادة التسمية فلا سطراً به الآن —
    # فتُسقَط من الاستمرارية بنمط old_version_58 ويحكم غيابه الثنائي
    # انتقالاً كاملاً بالمرجع أدناه.
    old_version_pubspec_58 = ("packages/app/pubspec.yaml", "0.2.3")

    b59_candidates = [
        (f"{b58.APP}/home_screen.dart",
         "فواتير البيع ومردودها بفلتر جهتهما"),
        (f"{b58.APP}/home_screen.dart",
         "فواتير الشراء ومردودها بفلتر جهتهما"),
        (f"{b58.APP}/invoices_screen.dart", "بيعي (البيع ومردوده)"),
        (f"{b58.APP}/invoices_screen.dart", "شرائي (الشراء ومردوده)"),
        (f"{b58.APP}/invoices_screen.dart",
         "النوع يُحدد من زر الدخول — لا مبدّل هنا"),
    ]

    continuity = []
    for _, markers in b58_groups:
        for item in markers:
            if item in (renamed_58, old_version_58,
                        old_version_pubspec_58):
                continue
            continuity.append(item)
    continuity.append(("packages/app/lib/orders_screen.dart",
                       "طلبات الشراء والبيع"))
    continuity.append((f"{b58.APP}/home_screen.dart", "الطلبات"))
    continuity.extend(b59_candidates)

    # انتقال الإزالة س203: تلميح بلاطة المزامنة الموروث (بb58.S178) كان
    # بالبادئة «متاحة الآن — » فنُزعت بأمر المالك عن التلميحات الثماني
    # عشر — فمرشّحه يُعاد بلسانه الجديد حرفاً (بلا البادئة) ولا يُسقَط
    # فالحضور محكوم بالثنائيتين والغياب القديم بالمرجع انتقالاً أدناه.
    _removed_prefix = "متاحة الآن — "
    continuity = [
        (f, m[len(_removed_prefix):] if m.startswith(_removed_prefix)
         else m)
        for f, m in continuity
    ]

    # مميِّزات س203 — حاضرة بثنائيتَي b60 وغائبة عن المرجع b59
    candidates = [
        # م2: الوصول السريع بلساناته الأربع
        (f"{b58.APP}/home_screen.dart",
         "اضغط مطولاً على أي بلاطة لتثبيتها هنا — الحد أربعة"),
        (f"{b58.APP}/home_screen.dart",
         "الوصول السريع أربعة كحدٍّ أقصى — ألغِ واحداً أولاً"),
        (f"{b58.APP}/home_screen.dart", "ثُبّت في الوصول السريع"),
        (f"{b58.APP}/home_screen.dart", "أُلغي التثبيت"),
        # م5: «مردود من هذه الفاتورة»
        (f"{b58.APP}/invoices_screen.dart", "مردود من هذه الفاتورة"),
        # م4: بيانات المنشأة والطباعة التجارية
        ("packages/app/lib/settings_screen.dart", "بيانات المنشأة"),
        ("packages/app/lib/settings_screen.dart",
         "حُفظت بيانات المنشأة — تظهر أول المطبوعات"),
        ("packages/app/lib/settings_screen.dart", "اسم المنشأة (إلزامي)"),
        ("packages/app/lib/print_service.dart", "الرقم الضريبي: "),
        # مرشّح الإصدار — بالتسمية الجديدة D-213
        ("packages/app/lib/backup_center.dart", "0.260.0+60"),
    ]

    # انتقالات b60 الموثقة — غائبة عن b60 وحاضرة بالمرجع b59 حصراً
    transitions = [
        ("packages/app/lib/backup_center.dart", "0.2.3+59",
         "انتقال الإصدار"),
        # D-213 إعادة التسمية: مرشّح النظام القديم لتشغيل 60 لم يُبن قط
        # بحزمة (التسمية انتقلت قبل البناء) فغائبه عن b60 كافٍ بلا مرجع
        # — ومحكمته تحكم بعد المرجع كون الانتقال إلغاء قبل البناء.
        ("packages/app/lib/backup_center.dart", "0.2.3+60",
         "انتقال التسمية D-213"),
        # D-213 س203: سطر pubspec بالصيغة القديمة «0.2.3» غائب عن b60
        # وحاضرة بالمرجع b59 (0.2.3+59 تحويها حرفاً) — انتقال كامل الأركان
        ("packages/app/pubspec.yaml", "0.2.3",
         "انتقال الإصدار D-213"),
        # م0 بأمر المالك: البادئة زالت من التلميحات فلا «متاحة الآن» ثنائياً
        (f"{b58.APP}/home_screen.dart", "متاحة الآن — ",
         "انتقال الإزالة س203"),
    ]

    # انتقالات بلا مرجع — إلغاءٌ قبل البناء فلا مرجعاً له بالعكس
    REF_OPTIONAL_KINDS = {"انتقال التسمية D-213"}

    total = 0
    failures = 0
    for file_path, marker in continuity:
        marker = b58.read_marker(args.repo, file_path, marker)
        total += 1
        ok_a = found(android, marker)
        ok_w = found(windows, marker)
        if ok_a and ok_w:
            print(f"[استمرارية] {marker}: حاضرة بالثنائيتين")
        else:
            print(f"[استمرارية] {marker}: أندرويد="
                  f"{'حاضرة' if ok_a else 'غائبة'} وويندوز="
                  f"{'حاضرة' if ok_w else 'غائبة'}")
            failures += 1

    for file_path, marker, kind in transitions:
        # الانتقالات عمداً غائبة عن المصدر (إزالة/ترحيل إصدار) فلا
        # read_marker عليها — نمط dropped بأداة b59 حرفاً.
        total += 1
        in60 = found(android, marker) or found(windows, marker)
        if ref_android is None or ref_windows is None:
            # بلا مرجع: الغائب عن b60 يكفي حضوراً بالمصدر (المرجع متاح
            # حصراً بجلسة التسليم فالعكس كامل الأركان عندها).
            ok = not in60
            status = "غائبة عن b60 (بلا مرجع)" if ok \
                else f"مرفوض (حاضرة بb60!) {in60}"
        else:
            in_ref = found(ref_android, marker) or found(ref_windows, marker)
            if kind in REF_OPTIONAL_KINDS:
                # إلغاء قبل البناء: غيابه عن b60 كافٍ ولا حضور بالمرجع
                # مطلوباً (نمطه: التسمية انتقلت قبل أن تُبن بحزمة قط).
                ok = not in60
                status = "انتقال سليم (غائبة عن b60 — إلغاء قبل البناء)" \
                    if ok else f"مرفوض (حاضرة بb60!) {in60}"
            else:
                ok = (not in60) and in_ref
                status = "انتقال سليم (غائبة عن b60 وحاضرة بالمرجع)" if ok \
                    else f"مرفوض (b60={in60} مرجع={in_ref})"
        if not ok:
            failures += 1
        print(f"[{kind}] {marker}: {status}")

    for file_path, marker in candidates:
        marker = b58.read_marker(args.repo, file_path, marker)
        total += 1
        ok_a = found(android, marker)
        ok_w = found(windows, marker)
        if ok_a and ok_w:
            status = "حاضرة بالثنائيتين"
        else:
            status = f"أندرويد={'حاضرة' if ok_a else 'غائبة'} " \
                     f"ويندوز={'حاضرة' if ok_w else 'غائبة'}"
            failures += 1
        line = f"[جديد س203] {marker}: {status}"
        if ref_android is not None and ref_windows is not None:
            in_ref = found(ref_android, marker) or \
                found(ref_windows, marker)
            line += f" | بالمرجع b59: {'حاضرة (ليست مميزاً!)' if in_ref else 'غائبة (صادق)'}"
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
