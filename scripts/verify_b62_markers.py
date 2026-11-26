#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 62 (b62 = v.0.262 — س205 وس206 معاً) — دِقّة
(منهجية السجل الموثقة — نمط b37..b61).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.261.0+61» غائب عن ثنائيتَي b62: كتالوج الإصدار انتقل بD-213
       إلى 0.262.0+62 (backup_center.dart:67) ولا مصدر مشروعاً يحمل
       القديمة (فحص الحاجز بالجلسة).
     - «0.2.3+60» غائب تتابعاً (غاب بb60 بعيد إعادة التسمية D-213).

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.262.0+62» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س205 م04 منتقي المردود: «تعذر تجهيز بذرة المردود — الأصل مرحّل
    بنوعه المطلوب حصراً» و«معرف الفاتورة الأصلية (إلزامي للمردود)»
    (invoices_screen).
  - استمرارية س204: «المجموع» (م01) و«هذا الشهر» (م02).
  غياباً (في الثنائيتين معاً): «0.261.0+61» و«0.2.3+60».

والحد الصادق الموثق: م11 وم18 بس206 بنيويان شيفريان (عنوان دائم وإطار
مزال ومحاذاة اتجاهية) — لا لسان ثنائي لهما أصلاً فلا مميِّز ثنائي لهما
(نمط م14/م16 بس201) — وهويتهما الثنائية نسخة الإصدار ذاتها.

الاستخدام:
  python3 scripts/verify_b62_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.262.0+62', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart:67'),
    ('تعذر تجهيز بذرة المردود — الأصل مرحّل بنوعه المطلوب حصراً',
     'packages/app/lib/invoices_screen.dart (م04 منتقي المردود — س205)'),
    ('معرف الفاتورة الأصلية (إلزامي للمردود)',
     'packages/app/lib/invoices_screen.dart (م04 منتقي المردود — س205)'),
    ('المجموع', 'packages/app/lib/invoices_screen.dart (بطاقة المجاميع — س204 م01 استمرارية)'),
    ('هذا الشهر', 'packages/app/lib/date_picker.dart (رقائق م02 — س204 استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.261.0+61', 'كتالوج الإصدار انتقل إلى 0.262.0+62 — ولا مصدر مشروعاً يحملها'),
    ('0.2.3+60', 'التسمية القديمة غابت بb60 (D-213) وتظل غائبة'),
]


def encodings(text: str):
    return [text.encode('utf-8'), text.encode('utf-16-le')]


def check(binary_path: str, label: str, results: list) -> bool:
    with open(binary_path, 'rb') as f:
        blob = f.read()
    ok = True
    for text, where in MARKERS_PRESENT:
        found = any(enc in blob for enc in encodings(text))
        results.append(f'[{label}] حضور: «{text}» → {"حاضر" if found else "غائب!"} ({where})')
        ok = ok and found
    for text, why in MARKERS_ABSENT:
        found = any(enc in blob for enc in encodings(text))
        results.append(f'[{label}] غياب: «{text}» → {"غائب صحيح" if not found else "حاضر — انتقال مكسور!"} ({why})')
        ok = ok and not found
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.262')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.262')
    args = ap.parse_args()
    results: list = []
    ok = True
    ok = check(args.android, 'أندرويد libapp.so', results) and ok
    ok = check(args.windows, 'ويندوز app.so', results) and ok
    for line in results:
        print(line)
    total = (len(MARKERS_PRESENT) + len(MARKERS_ABSENT)) * 2
    print(f'المجموع: {total} فحصاً — {"CLEAN" if ok else "فشل"}')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
