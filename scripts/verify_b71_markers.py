#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 71 (b71 = v.0.271 — البند 7 المعماري
«نواة واحدة قشرة لكل منصة» ومعالجة الثقل الجذري للبيانات الضخمة س215) —
دِقّة (منهجية السجل الموثقة — نمط b37..b70).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.270.0+70» و«0.269.0+69» غائبان عن ثنائيتَي b71: كتالوج
       الإصدار انتقل بس215 إلى 0.271.0+71 (backup_center.dart) ولا
       مصدر شيفرة مشروعاً يحمل القديمة — وسطر التعليق التوثيقي
       بpubspec خارج الثنائي عرف التعليقات (فحص الحاجز بالجلسة)،
       و«0.269.0+69» ترميز تشغيل سالخ بفشله فلا ثنائية تحمله أصلاً
       (نمط الفجوات الموثق b45).
     - «0.2.3+60» غائبة تتابعاً (غابت بb60 بعيد إعادة التسمية D-213).

الحد الصادق الموثق (بنمط م11/م18 بس206 وبند 4 بس207): بنود س215 بلا
لسان ثنائي مميِّز أصلاً — البند 7 المعماري (وثيقة العمارة وحارسه
البنيوي core_shell_boundary_test.dart) والفهارس الستة عشر بترحيلة v35
كلها بنيوية شيفريات لا نصاً للمستخدم — فهويتهما الثنائية نسخة الإصدار
ذاتها واختبارات s215 (التخزينية الخمسة والواجهية الأربعة) تحكمها
بنياً وخطتا EXPLAIN تحكمان الفهارس عتاداً.

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.271.0+71» (pubspec وكتالوج الإصدار معاً حرفاً).
  - استمرارية س213: «session_idle_minutes» (مفتاح الخمول) و«من
    المستويات المعتمدة حصراً» (حرس المستويات).
  - استمرارية س212: «بوابة الجهاز».
  - استمرارية س211: «users.create».
  - استمرارية س210: «بحث بالطرف أو الرقم».
  - استمرارية س209: «نبض العمل».
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة».
  غياباً (في الثنائيتين معاً): «0.270.0+70» و«0.269.0+69» و«0.2.3+60».

الاستخدام:
  python3 scripts/verify_b71_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.271.0+71', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('session_idle_minutes', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('من المستويات المعتمدة حصراً', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('بوابة الجهاز', 'packages/app/lib/device_gate_screen.dart (س212 — استمرارية)'),
    ('users.create', 'packages/storage/lib/src/database.dart (س211 — استمرارية)'),
    ('بحث بالطرف أو الرقم', 'packages/app/lib/invoices_screen.dart (س210 — استمرارية)'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 — استمرارية)'),
    ('نُسخ المعرّف إلى الحافظة', 'packages/app/lib/context_menu.dart (س207 — استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.270.0+70', 'كتالوج الإصدار انتقل إلى 0.271.0+71 — ولا مصدر مشروعاً يحملها'),
    ('0.269.0+69', 'ترميز تشغيل سالخ بفشله — لا ثنائية تحمله (نمط b45)'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.271')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.271')
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
