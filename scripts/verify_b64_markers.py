#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 64 (b64 = v.0.264 — الدفعة 2 «الاتساق»
س208) — دِقّة (منهجية السجل الموثقة — نمط b37..b63).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.263.0+63» غائب عن ثنائيتَي b64: كتالوج الإصدار انتقل بس208
       إلى 0.264.0+64 (backup_center.dart) ولا مصدر شيفرة مشروعاً يحمل
       القديمة — وسطر التعليق التوثيقي بpubspec خارج الثنائي عرف
       التعليقات (فحص الحاجز بالجلسة).
     - «0.2.3+60» غائب تتابعاً (غابت بb60 بعيد إعادة التسمية D-213).
     - «السعر مكبَّر» غائب تتابعاً — التنظيف النصي المعتمد س207 باقٍ.

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.264.0+64» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س208 قوائم سياق س207 على شاشات النمط الجديدة: «طباعة السند»
    و«طباعة التحويل» و«طباعة التسوية» (vouchers بالتبويبات الثلاثة)
    و«أذونات الدور» (roles) و«تعطيل الصندوق» (boxes) و«تفاصيل
    التحويل» (warehouses) — فعاليات المضيف القائمة حصراً.
  - س208 الحالات الفارغة الجديدة بلسان فعل: «لا تحويلات بعد — ابدأ
    بتحويل بين مستودعين» (warehouses) و«لا أدوار بعد — أضف أول دور
    بزر «دور جديد»» (roles) و«لا صناديق بعد — أضف أول صندوق بزر
    «صندوق جديد»» (boxes).
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة» (context_menu)
    و«diqqah-import-» (بند 1 حفظ القالب).
  - استمرارية س205: «تعذر تجهيز بذرة المردود — الأصل مرحّل بنوعه
    المطلوب حصراً» (م04) و«هذا الشهر» (م02).
  غياباً (في الثنائيتين معاً): «0.263.0+63» و«0.2.3+60» و«السعر مكبَّر».

والحد الصادق الموثق: م06 التكيفي على الطلبات (القائمة والتفصيل)
وكسل قائمة السندات builder — بنيويان بهوامش وحدود بناء لا لسان ثنائي
مميِّزاً لهما أصلاً بنمط بند 4 بس207 — وهويتهما الثنائية نسخة الإصدار
ذاتها واختبارات s208 تحكم قياسَهما قيمةً (البت 400 على العريض).

الاستخدام:
  python3 scripts/verify_b64_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.264.0+64', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('diqqah-import-',
     'packages/app/lib/import_screen.dart (بند 1 حفظ القالب — س207 استمرارية)'),
    ('نُسخ المعرّف إلى الحافظة',
     'packages/app/lib/context_menu.dart (س207 استمرارية)'),
    ('طباعة السند',
     'packages/app/lib/vouchers_screen.dart (س208 — سياق تبويب السندات)'),
    ('طباعة التحويل',
     'packages/app/lib/vouchers_screen.dart (س208 — سياق تبويب التحويلات)'),
    ('طباعة التسوية',
     'packages/app/lib/vouchers_screen.dart (س208 — سياق تبويب التسويات)'),
    ('أذونات الدور',
     'packages/app/lib/roles_screen.dart (س208 — سياق صف الدور)'),
    ('تعطيل الصندوق',
     'packages/app/lib/boxes_screen.dart (س208 — سياق صف الصندوق)'),
    ('تفاصيل التحويل',
     'packages/app/lib/warehouses_screen.dart (س208 — سياج سجل التحويلات)'),
    ('لا تحويلات بعد — ابدأ بتحويل بين مستودعين',
     'packages/app/lib/warehouses_screen.dart (س208 — الحالة الفارغة بلسان فعل)'),
    ('لا أدوار بعد — أضف أول دور بزر «دور جديد»',
     'packages/app/lib/roles_screen.dart (س208 — الحالة الفارغة بلسان فعل)'),
    ('لا صناديق بعد — أضف أول صندوق بزر «صندوق جديد»',
     'packages/app/lib/boxes_screen.dart (س208 — الحالة الفارغة بلسان فعل)'),
    ('تعذر تجهيز بذرة المردود — الأصل مرحّل بنوعه المطلوب حصراً',
     'packages/app/lib/invoices_screen.dart (م04 منتقي المردود — س205 استمرارية)'),
    ('هذا الشهر', 'packages/app/lib/date_picker.dart (رقائق م02 — س204 استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.263.0+63', 'كتالوج الإصدار انتقل إلى 0.264.0+64 — ولا مصدر شيفرة يحملها'),
    ('0.2.3+60', 'التسمية القديمة غابت بb60 (D-213) وتظل غائبة'),
    ('السعر مكبَّر', 'التنظيف النصي المعتمد (بند 5 — س207) باقٍ'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.264')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.264')
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
