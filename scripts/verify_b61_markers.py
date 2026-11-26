#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 61 (b61 = v.0.261 — س204) — دِقّة
(منهجية السجل الموثقة — نمط b37..b60).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.260.0+60» غائب عن ثنائيتَي b61: كتالوج الإصدار انتقل بD-213
       إلى 0.261.0+61 (backup_center.dart:65) ولا مصدر مشروعاً يحمل
       القديمة (فحص الحاجز بالجلسة) — فالغياب انتقال كامل.
     - «0.2.3+60» غائبان تتابعاً (غابا بb60 بعيد إعادة التسمية).

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.261.0+61» (pubspec وكتالوج الإصدار معاً حرفاً).
  - م01: «المجموع» (بطاقة المجاميع المعنونة — invoices_screen)
        و«الصندوق — وعمله سند العملة» و«لقطة الصرف مكبرة ×1,000,000»
        (vouchers_screen — بحقلَيها بنبض الجولة #401).
  - م02: «هذا الشهر» و«هذا العام» و«اليوم» (رقائق اختصارات المدى —
        date_picker الدفعة الجديدة).
  - م03: «حوّل المتبقي لفاتورة أولاً» (رسالة الطلبات بلغة المستخدم —
        orders_screen).
  غياباً (في الثنائيتين معاً): «0.260.0+60» و«0.2.3+60».

الاستخدام:
  python3 scripts/verify_b61_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.261.0+61', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart:65'),
    ('المجموع', 'packages/app/lib/invoices_screen.dart (بطاقة المجاميع المعنونة — س204 م01)'),
    ('الصندوق — وعمله سند العملة', 'packages/app/lib/vouchers_screen.dart (لسان منسدل الصندوق)'),
    ('لقطة الصرف مكبرة ×1,000,000', 'packages/app/lib/vouchers_screen.dart (لسان حقل اللقطة)'),
    ('هذا الشهر', 'packages/app/lib/date_picker.dart (رقائق م02 — الدفعة الجديدة)'),
    ('هذا العام', 'packages/app/lib/date_picker.dart (رقائق م02 — الدفعة الجديدة)'),
    ('اليوم', 'packages/app/lib/date_picker.dart (رقائق م02 — الدفعة الجديدة)'),
    ('حوّل المتبقي لفاتورة أولاً', 'packages/app/lib/orders_screen.dart (م03 بلغة المستخدم)'),
]

MARKERS_ABSENT = [
    ('0.260.0+60', 'كتالوج الإصدار انتقل إلى 0.261.0+61 — ولا مصدر مشروعاً يحملها'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.261')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.261')
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
