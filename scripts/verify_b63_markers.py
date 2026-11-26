#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 63 (b63 = v.0.263 — دفعة تنظيف ويندوز
س207) — دِقّة (منهجية السجل الموثقة — نمط b37..b62).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.262.0+62» غائب عن ثنائيتَي b63: كتالوج الإصدار انتقل بس207
       إلى 0.263.0+63 (backup_center.dart) ولا مصدر مشروعاً يحمل
       القديمة (فحص الحاجز بالجلسة).
     - «0.2.3+60» غائب تتابعاً (غاب بb60 بعيد إعادة التسمية D-213).
     - «السعر مكبَّر» غائب تتابعاً — التنظيف النصي المعتمد بنود المالك
       (بند 5 من النقاش): العبارة أُزيلت من موضعيها بشاشة العملات
       والآلية الوظيفية باقية حرفاً.

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.263.0+63» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س207 بند 1 حفظ القالب باسم: «diqqah-import-» — الجزء الثابت
    الأول ببناء اسم ملف القالب (import_screen). ولطرف الدقة: بشّارة
    «حُفظ القالب: » حاضرة بالثنائي الويندوز حصراً — سلوك AOT الأندرويدي
    يدمج سلاسل الاستيفاء فلا نص مستقل حرفاً لها هناك (درس الجلسة
    الموثق) — والعلامة المعتمدة حاضرة بالترميزين معاً.
  - س207 بند 2 قائمة السياق الموحدة: «نُسخ المعرّف إلى الحافظة»
    (context_menu) و«تفاصيل الأمر» (orders) و«فتح الصنف» (items)
    و«فتح الطرف» (parties) — و«تفاصيل الفاتورة» لا تصلح علامةً فنصها
    سابق الحضور بشاشة الفواتير (سبعة مواضع قديمة).
  - استمرارية س205: «تعذر تجهيز بذرة المردود — الأصل مرحّل بنوعه
    المطلوب حصراً» (م04) و«المجموع» (م01) و«هذا الشهر» (م02).
  غياباً (في الثنائيتين معاً): «0.262.0+62» و«0.2.3+60» و«السعر مكبَّر».

والحد الصادق الموثق: بند 4 (قواعد التلميح المركزية) بنيوي بالثيم —
قيم مدد وموضع ظهور لا لسان ثنائي مميِّزاً لها أصلاً — وهويته الثنائية
نسخة الإصدار ذاتها واختبارات s207 تحكم قيمه قيمةً.

الاستخدام:
  python3 scripts/verify_b63_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.263.0+63', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('diqqah-import-',
     'packages/app/lib/import_screen.dart (بند 1 — اسم ملف القالب — س207)'),
    ('نُسخ المعرّف إلى الحافظة',
     'packages/app/lib/context_menu.dart (بند 2 — قائمة السياق — س207)'),
    ('تفاصيل الأمر',
     'packages/app/lib/orders_screen.dart (بند 2 — قائمة السياق — س207)'),
    ('فتح الصنف',
     'packages/app/lib/items_screen.dart (بند 2 — قائمة السياق — س207)'),
    ('فتح الطرف',
     'packages/app/lib/parties_screen.dart (بند 2 — قائمة السياق — س207)'),
    ('تعذر تجهيز بذرة المردود — الأصل مرحّل بنوعه المطلوب حصراً',
     'packages/app/lib/invoices_screen.dart (م04 منتقي المردود — س205 استمرارية)'),
    ('المجموع', 'packages/app/lib/invoices_screen.dart (بطاقة المجاميع — س204 م01 استمرارية)'),
    ('هذا الشهر', 'packages/app/lib/date_picker.dart (رقائق م02 — س204 استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.262.0+62', 'كتالوج الإصدار انتقل إلى 0.263.0+63 — ولا مصدر مشروعاً يحملها'),
    ('0.2.3+60', 'التسمية القديمة غابت بb60 (D-213) وتظل غائبة'),
    ('السعر مكبَّر', 'التنظيف النصي المعتمد (بند 5 — س207) — والآلية الوظيفية باقية'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.263')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.263')
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
