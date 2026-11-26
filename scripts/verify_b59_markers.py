#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 59 (b59 بحكم الأمر) — دِقّة
(منهجية السجل الموثقة — نمط b37..b58).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً (كل علامة موقّفة على ملفها
     بالمصدر وتُتحقق حرفياً فيه قبل البحث بالثنائي — درس b39/b40).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. المميِّز بالعكس على المرجع الأحدث المتاح — وهو هنا b58 ذاته (ثنائيتا
     التشغيل 58 — استُخرجتا حياً من أثرتَي التشغيل 58 المودعة):
     مميِّزات س202 (بلاطتا الجهة بلسان مرحلتيهما ومجموعتا المنسدل ولسان
     شارة النوع الجديد ومرشّح الإصدار 0.2.3+59) الغائبة عن b58 حاضرة في
     b59 فتثبت أن ما بُني هو الجديد الحامل للدفعة، وما قبله (الاستمرارية
     وس141..س186/س198) حاضر بb58 أصلاً فلا يُفحص بالعكس عليه بل يُفحص
     حضوراً في b59 حصراً.

انتقالات موثقة (نمط الأسلاف):
  - مرشّح الإصدار «0.2.3+58» انتقل من الأداة بحذفه بعد b58 (نمط
    0.2.3+39/40/41/43/44/46/47/49/50/55/56/57/58) — وحلّ محله «0.2.3+59»
    بمجموعة الجديد — والانتقال موثق فحصاً: «0.2.3+58» غائب عن ثنائيتَي
    b59 (البادم المشفر الجديد أُسقط السلسلة غير المرجعية).
  - علامة الاستمرارية «طلبات الشراء والبيع» (home_screen) انتقلت إلى
    «الطلبات» بأمر المالك (تصحيح التسميتين س202) — ونمط الانتقال:
    العلامة تُستبدل بلسانها الجديد الحي بالشيفرة (حاضرة بb58 ضمن السلسلة
    القديمة كجزء منها وبb59 بنصها الجديد فالحضور فيها بالثنائيتين).
  - الحدود الصادقة للمميِّز الثنائي بb59: م1 (تصفية صفوف التوزيع
    الصفرية بvouchers_screen) بنية شيفرة لا نص مستخدم — ولا مميِّز
    ثنائي لها أصلاً (نمط م14/م16 الموثق بس201) — وم3 (التسميتان
    «الوحدات»/«الطلبات») نصاها حاضران بb58 أصلاً بسياقات أخرى فلا
    تمييزاً لهما (والتوجيه بالمفتاح بنية شيفرة) — وم4 (شارة القرص
    الثابتة) بنية ويدجت لا نص — وم5 (الحاوية الليلية الهادئة) ألوان
    لا نصوص.
  - المسبار الحي قبل التثبيت (نمط س168/س179/س185/س201 —
    scripts/probe_b59_markers.py): 6 مرشحات صادقات.

الاستخدام:
  python3 scripts/verify_b59_markers.py <b59_libapp.so> <b59_app.so> \
      [--ref-android <b58_libapp.so> --ref-windows <b58_app.so>] \
      [--repo <مسار المستودع>]
"""

import argparse
import importlib.util
import os
import sys

REPO_DEFAULT = "/home/z/my-project/diqqah"
_SCRIPTS = os.path.dirname(os.path.abspath(__file__))


def _load_b58_tool():
    """يحمّل أداة b58 لوراثة مجموعات الاستمرارية بنمطها الموثق — أداة
    السجل الواحدة لا نسخ متفرقة تُنسى تسويغها."""
    path = os.path.join(_SCRIPTS, "verify_b58_markers.py")
    spec = importlib.util.spec_from_file_location("verify_b58_markers", path)
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

    b58 = _load_b58_tool()

    # وراثة مجموعات b58 كلها بنفس ترتيبها، ثم الانتقالات الموثقة:
    # علامة البلاطة المعاد تسميتها تخرج من الاستمرارية (نصها القديم
    # زال بالشيفرة) ومرشّح الإصدار القديم يخرج من مجموعة الجديد.
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
    renamed = (f"{b58.APP}/home_screen.dart", "طلبات الشراء والبيع")
    old_version = ("packages/app/lib/backup_center.dart", "0.2.3+58")

    continuity = []
    dropped = []
    for _, markers in b58_groups:
        for item in markers:
            if item == renamed or item == old_version:
                dropped.append(item)
                continue
            continuity.append(item)

    # انتقال التسمية س202 الموثق: النص القديم «طلبات الشراء والبيع» ما
    # تزال شيفرة حية بعنوان شاشة الأوامر ذاتها (الاختصار بلسان البلاطة
    # حصراً وعنوان الشاشة الكامل) — فالتثبيت على orders_screen يبقى،
    # واللسان الجديد «الطلبات» تثبت على home_screen (حاضر بb58 كجزء
    # السلسلة القديمة فلا مميِّزاً بجداره — فحص حضور لا عكس).
    continuity.append(("packages/app/lib/orders_screen.dart",
                       "طلبات الشراء والبيع"))
    continuity.append((f"{b58.APP}/home_screen.dart", "الطلبات"))

    candidates = [
        # س202 م2: بلاطتا الجهة بلسان مرحلتيهما
        (f"{b58.APP}/home_screen.dart",
         "فواتير البيع ومردودها بفلتر جهتهما"),
        (f"{b58.APP}/home_screen.dart",
         "فواتير الشراء ومردودها بفلتر جهتهما"),
        # س202 م2: مجموعتا الجهة بمنسدل الأرشيف
        (f"{b58.APP}/invoices_screen.dart", "بيعي (البيع ومردوده)"),
        (f"{b58.APP}/invoices_screen.dart", "شرائي (الشراء ومردوده)"),
        # س202 م2: لسان شارة النوع بعد المسار الجديد
        (f"{b58.APP}/invoices_screen.dart",
         "النوع يُحدد من زر الدخول — لا مبدّل هنا"),
        # مرشّح الإصدار
        ("packages/app/lib/backup_center.dart", "0.2.3+59"),
    ]

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

    # الانتقال الموثق: الإصدار القديم غائب عن b59 حصراً إن توفر المرجع.
    if ref_android is not None and ref_windows is not None:
        for item in dropped:
            total += 1
            in59 = found(android, item[1]) or found(windows, item[1])
            if item == old_version:
                # المرجع b58 يحمل الإصدار القديم وb59 زاله — نمط الحذف.
                in_ref = found(ref_android, item[1]) or \
                    found(ref_windows, item[1])
                ok = (not in59) and in_ref
                status = "انتقال سليم (غائب عن b59 وحاضر بالمرجع)" if ok \
                    else f"مرفوض (b59={in59} مرجع={in_ref})"
                if not ok:
                    failures += 1
                print(f"[انتقال الإصدار] {item[1]}: {status}")
            else:
                # إعادة التسمية س202: النص القديم باقٍ بعنوان شاشة
                # الأوامر (تثبيته أعلاه استمراريةً على orders_screen)
                # فلا انتقال غياباً — واللسان الجديد تثبت حضوراً.
                ok = True
                print(f"[انتقال التسمية] {item[1]}: "
                      "انتقال سليم (إعادة تثبيت بالشاشة وحضور اللسان الجديد)")

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
        line = f"[جديد س202] {marker}: {status}"
        if ref_android is not None and ref_windows is not None:
            in_ref = found(ref_android, marker) or \
                found(ref_windows, marker)
            line += f" | بالمرجع b58: {'حاضرة (ليست مميزاً!)' if in_ref else 'غائبة (صادق)'}"
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
