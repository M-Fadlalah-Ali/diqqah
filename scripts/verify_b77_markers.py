#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 77 (b77 = v.0.277 — عقد س225: الدفعة
الأولى للحيوية بأمر المالك — النبض بألوان الأزقة وهوية الوحدات الثلاث
وطبقات الليل والحالات الفارغة الحية — والزيبرا المحايد بإجمالياتها
المزدوجة — والتحديد المتعدد الجماعي بديل لوح الفئة) — دِقّة (منهجية
السجل الموثقة — نمط b31..b76).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي، ولا
     تعليقات ولا أسماء دوال (المرمّز يسقط الأسماء النقية — درس b39/b40).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها: «0.276.0+76» غائبة عن ثنائيتَي
     b77 (كتالوج الإصدار انتقل بس225 بأداة الدفعة s225_transfer_version.py
     ولا مصدر شيفرة مشروعاً يحمل القديمة) وما قبلها انتقلت تتابعاً —
     و«افتح المتابعات» غائبة بعرف س221 بد3 (استمرار غياب b75/b76).
  4. الحد الصادق لهوية س225 الثنائية: خ1 وخ2 وخ7 بنيةُ ألوانٍ لا نصاً
     للمستخدم (أزقة الأزقة وعائلات الأقراص وسلالم الحاويات فلا لسان
     ثنائي لها) — فهويتها: نسخة الإصدار ذاتها + لسانا التحديد المتعدد
     الجديدان + لسانا س225 النصيان الآخران + اختبارات s225_test
     البنيوية التي تحكمها بنياً — والكوتلن لم يُمسّ بالدفعة فclasses.dex
     بختمه ذاته (استمرارية الأصيلة) والقناة باقية فيه حرفاً.

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.277.0+77» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س221 د2 (استمرارية): «diqqah/security/pbkdf2» (اسم قناة المنصة
    الحي — native_pbkdf2.dart).
  - س221 د5 (استمرارية): «عرض المزيد — الباقي » و«المبيعات كلها
    (البيع ومردوده)».
  - س225 (الجديدة): «إضافة المحدد» و«تحديد كل النتائج» (لسانا
    التحديد المتعدد — invoices_screen.dart) و«إجمالي الفوهج» (سطر
    الإجماليات داخل جدول الأعمار — reports_screen.dart) و«لا إذون
    بعد» (لسان فراغ الإذون الجديد — stock_docs_screen.dart).
  - س216: «بيانات الدخول غير صحيحة» و«اسم الدخول».
  - استمرارية س213: «session_idle_minutes» و«من المستويات المعتمدة حصراً».
  - استمرارية س212: «بوابة الجهاز».
  - استمرارية س211: «users.create».
  - استمرارية س210: «بحث بالطرف أو الرقم».
  - استمرارية س209: «نبض العمل».
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة».
  حضوراً (في classes.dex حصراً — الأصيلة الكوتلن):
  - «diqqah/security/pbkdf2» (عرف b75 — الأصيلة داخل الأثر).
  غياباً (في الثنائيتين معاً): «0.276.0+76» و«0.275.0+75»
  و«0.274.0+74» و«0.273.0+73» و«0.272.0+72» و«0.271.0+71»
  و«0.2.3+60» و«افتح المتابعات».

الاستخدام:
  python3 scripts/verify_b77_markers.py --android <libapp.so> --dex <classes.dex> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.277.0+77', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('diqqah/security/pbkdf2',
     'packages/app/lib/native_pbkdf2.dart (س221 د2 — قناة المنصة الحية — استمرارية)'),
    ('إضافة المحدد',
     'packages/app/lib/invoices_screen.dart (س225 — زر صبّ المحدد — الجديدة)'),
    ('تحديد كل النتائج',
     'packages/app/lib/invoices_screen.dart (س225 — تحديد نتائج المرشّح — الجديدة)'),
    ('إجمالي الفوهج',
     'packages/app/lib/reports_screen.dart (س225 — إجماليات الجدول بخط مزدوج — الجديدة)'),
    ('لا إذون بعد',
     'packages/app/lib/stock_docs_screen.dart (س225 خ6 — لسان فراغ الإذون — الجديدة)'),
    ('عرض المزيد — الباقي ',
     'packages/app/lib/list_display.dart (س221 د5 — زر حد العرض المتدرج — استمرارية)'),
    ('المبيعات كلها (البيع ومردوده)',
     'packages/app/lib/invoices_screen.dart (س221 د5 — لسان الجهة بعد العزل — استمرارية)'),
    ('بيانات الدخول غير صحيحة',
     'packages/app/lib/device_gate_screen.dart (س216 — استمرارية)'),
    ('اسم الدخول',
     'packages/app/lib/users_screen.dart (س216 — استمرارية)'),
    ('session_idle_minutes', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('من المستويات المعتمدة حصراً', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('بوابة الجهاز', 'packages/app/lib/device_gate_screen.dart (س212 — استمرارية)'),
    ('users.create', 'packages/app/lib/users_screen.dart (س211 — استمرارية)'),
    ('بحث بالطرف أو الرقم', 'packages/app/lib/invoices_screen.dart (س210 — استمرارية)'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 — استمرارية)'),
    ('نُسخ المعرّف إلى الحافظة', 'packages/app/lib/context_menu.dart (س207 — استمرارية)'),
]

MARKERS_DEX = [
    ('diqqah/security/pbkdf2',
     'packages/app/android/.../MainActivity.kt (س221 د2 — الأصيلة داخل الأثر — عرف b75)'),
]

MARKERS_ABSENT = [
    ('0.276.0+76', 'كتالوج الإصدار انتقل بس225 إلى 0.277.0+77 — ولا مصدر مشروعاً يحملها'),
    ('0.275.0+75', 'انتقل بس223 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.274.0+74', 'انتقل بس221 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.273.0+73', 'انتقل بس219 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.272.0+72', 'انتقل بس218 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.271.0+71', 'انتقل بس216 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.2.3+60', 'التسمية القديمة غابت بb60 (D-213) وتظل غائبة'),
    ('افتح المتابعات', 'الشريط الأحمر أُزيل بس221 بد3 — واللسان المزال لا ثنائية تحمله'),
]

ENCODINGS = ('utf-8', 'utf-16-le')


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def marker_bytes(text):
    return {enc: text.encode(enc) for enc in ENCODINGS}


def check(data, label):
    print(f'\n== {label} ({len(data)} بايت)')
    ok = True
    for text, source in MARKERS_PRESENT:
        encs = marker_bytes(text)
        found = [enc for enc, b in encs.items() if b in data]
        if found:
            print(f'  PRESENT [{found[0]}] «{text[:40]}» — {source}')
        else:
            print(f'  MISSING «{text[:40]}» — {source}')
            ok = False
    for text, reason in MARKERS_ABSENT:
        encs = marker_bytes(text)
        hit = [enc for enc, b in encs.items() if b in data]
        if hit:
            print(f'  UNEXPECTED PRESENT [{hit[0]}] «{text[:40]}» — {reason}')
            ok = False
        else:
            print(f'  ABSENT  «{text[:40]}» — {reason}')
    return ok


def check_dex(data):
    print(f'\n== classes.dex ({len(data)} بايت)')
    ok = True
    for text, source in MARKERS_DEX:
        found = text.encode('utf-8') in data
        if found:
            print(f'  PRESENT [utf-8] «{text}» — {source}')
        else:
            print(f'  MISSING «{text}» — {source}')
            ok = False
    return ok


def main():
    ap = argparse.ArgumentParser(
        description='التحقق البايتي لحزمتَي b77 (نمط b31..b76 الموثق)')
    ap.add_argument('--android', required=True,
                    help='مسار libapp.so من APK 0.277')
    ap.add_argument('--dex', required=True,
                    help='مسار classes.dex من APK 0.277 (عرف b75)')
    ap.add_argument('--windows', required=True,
                    help='مسار data/app.so من حزمة ويندوز 0.277')
    args = ap.parse_args()
    ok = True
    ok &= check(read_bytes(args.android), 'أندرويد libapp.so')
    ok &= check(read_bytes(args.windows), 'ويندوز data/app.so')
    ok &= check_dex(read_bytes(args.dex))
    total = (len(MARKERS_PRESENT) * 2 + len(MARKERS_ABSENT) * 2
             + len(MARKERS_DEX))
    print(f'\nالنتيجة: {"CLEAN" if ok else "FAIL"} — '
          f'{total} مسباراً بنمط b31..b76')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
