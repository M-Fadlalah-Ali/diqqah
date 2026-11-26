#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 65 (b65 = v.0.265 — الدفعة 3 «قانون
عرض سطح المكتب والرئيسية الست طبقات» س209) — دِقّة (منهجية السجل الموثقة — نمط b37..b64).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.264.0+64» غائب عن ثنائيتَي b65: كتالوج الإصدار انتقل بس209
       إلى 0.265.0+65 (backup_center.dart) ولا مصدر شيفرة مشروعاً يحمل
       القديمة — وسطر التعليق التوثيقي بpubspec خارج الثنائي عرف
       التعليقات (فحص الحاجز بالجلسة).
     - «0.2.3+60» غائب تتابعاً (غابت بb60 بعيد إعادة التسمية D-213).
     - «السعر مكبَّر» غائب تتابعاً — التنظيف النصي المعتمد س207 باقٍ.

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.265.0+65» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س209 طبقة نبض العمل بألسنتها الخمسة الستاتيكية: «نبض
    العمل» (ترويسة الطبقة) و«متابعات نشطة» (الجامعة بفعلها)
    و«أصناف تحت الحد الأدنى» و«أطراف فوق سقفها المبلغي»
    و«أطراف تجاوزت مدة السداد» (التفصيلية الثلاث من لقطة
    المتابعات القائمة).
  - استمرارية س208: «طباعة السند» (سياق السندات) و«لا تحويلات بعد —
    ابدأ بتحويل بين مستودعين» (الحالة الفارغة بالمستودعات).
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة» (context_menu).
  غياباً (في الثنائيتين معاً): «0.264.0+64» و«0.2.3+60» و«السعر مكبَّر».

والحد الصادق الموثق: شبكة أعمدة البطاقات وسلم المسافات 4/8 وبطاقة
لا أيقونة بحد التوسيط وعرض النبض من قيود التخطيط — بنيوية بهوامش
وحدود بناء لا لسان ثنائي مميِّزاً لها أصلاً بنمط م06 وبند 4 بس207/س208 —
وهويتها الثنائية نسخة الإصدار ذاتها واختبارات s209 تحكم قياسها
قيمةً (العمود 188 والبت 412 على العريض). وسطر الإصدار العرضي
«دِقَّة v.0.265» بشارة استيفاء مدموجة بالثنائي الأندرويدي فلا نصاً
حرفاً لها هناك (درس س207 الموثق) — والكتالوج التقني 0.265.0+65 هو
العلامة الحاكمة للإصدار بالترميزين.

الاستخدام:
  python3 scripts/verify_b65_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.265.0+65', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 — ترويسة طبقة النبض)'),
    ('متابعات نشطة', 'packages/app/lib/home_screen.dart (س209 — البطاقة الجامعة بفعلها)'),
    ('أصناف تحت الحد الأدنى', 'packages/app/lib/home_screen.dart (س209 — من لقطة المتابعات)'),
    ('أطراف فوق سقفها المبلغي', 'packages/app/lib/home_screen.dart (س209 — من لقطة المتابعات)'),
    ('أطراف تجاوزت مدة السداد', 'packages/app/lib/home_screen.dart (س209 — من لقطة المتابعات)'),
    ('طباعة السند', 'packages/app/lib/vouchers_screen.dart (س208 استمرارية)'),
    ('لا تحويلات بعد — ابدأ بتحويل بين مستودعين',
     'packages/app/lib/warehouses_screen.dart (س208 استمرارية)'),
    ('نُسخ المعرّف إلى الحافظة', 'packages/app/lib/context_menu.dart (س207 استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.264.0+64', 'كتالوج الإصدار انتقل إلى 0.265.0+65 — ولا مصدر شيفرة يحملها'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.265')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.265')
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
