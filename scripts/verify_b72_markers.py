#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 72 (b72 = v.0.272 — جذر ثقل الدقائق
الأولى بالعزل الخلفي وبند الدخول اليدوي س216) —
دِقّة (منهجية السجل الموثقة — نمط b37..b71).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.271.0+71» و«0.270.0+70» غائبان عن ثنائيتَي b72: كتالوج
       الإصدار انتقل بس216 إلى 0.272.0+72 (backup_center.dart) ولا
       مصدر شيفرة مشروعاً يحمل القديمة — وسطر التعليق التوثيقي
       بpubspec خارج الثنائي عرف التعليقات (فحص الحاجز بالجلسة)،
       و«0.270.0+70» كذلك انتقل بس215 وهو قبله سالخ.
     - «0.269.0+69» ترميز تشغيل سالخ بفشله فلا ثنائية تحمله أصلاً
       (نمط الفجوات الموثق b45).
     - «0.2.3+60» غائبة تتابعاً (غابت بb60 بعيد إعادة التسمية D-213).

الحد الصادق الموثق (بنمط م11/م18 بس206 وبند 4 بس207 وس215): جانب الثقل
بس216 بلا لسان ثنائي مميِّز أصلاً — عزل الخلفية createInBackground
وحساب البايتات Isolate.run وقراءة الترويسة 64 بايتة وPRAGMA
synchronous=NORMAL وتأجيل مركز النسخ كلها بنيوية شيفريات لا نصاً
للمستخدم — فهويته الثنائية نسخة الإصدار ذاتها واختبارات s216 التخزينية
(دخول الدخول اليدوي والرسالة العامة ولقطة الترويسة) تحكمها بنياً،
ولسان الدخول اليدوي نص للمستخدم فحاضرة بالثنائيتين («بيانات الدخول
غير صحيحة» و«اسم الدخول»).

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.272.0+72» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س216: «بيانات الدخول غير صحيحة» (رسالة الفشل العامة — بوابة
    الجهاز) و«اسم الدخول» (عنوان الحقل اليدوي).
  - استمرارية س213: «session_idle_minutes» (مفتاح الخمول) و«من
    المستويات المعتمدة حصراً» (حرس المستويات).
  - استمرارية س212: «بوابة الجهاز».
  - استمرارية س211: «users.create».
  - استمرارية س210: «بحث بالطرف أو الرقم».
  - استمرارية س209: «نبض العمل».
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة».
  غياباً (في الثنائيتين معاً): «0.271.0+71» و«0.270.0+70» و«0.2.3+60».

الاستخدام:
  python3 scripts/verify_b72_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.272.0+72', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('بيانات الدخول غير صحيحة',
     'packages/app/lib/device_gate_screen.dart + packages/storage/lib/src/database.dart (س216)'),
    ('اسم الدخول', 'packages/app/lib/device_gate_screen.dart (س216)'),
    ('session_idle_minutes', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('من المستويات المعتمدة حصراً', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('بوابة الجهاز', 'packages/app/lib/device_gate_screen.dart (س212 — استمرارية)'),
    ('users.create', 'packages/storage/lib/src/database.dart (س211 — استمرارية)'),
    ('بحث بالطرف أو الرقم', 'packages/app/lib/invoices_screen.dart (س210 — استمرارية)'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 — استمرارية)'),
    ('نُسخ المعرّف إلى الحافظة', 'packages/app/lib/context_menu.dart (س207 — استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.271.0+71', 'كتالوج الإصدار انتقل بس216 إلى 0.272.0+72 — ولا مصدر مشروعاً يحملها'),
    ('0.270.0+70', 'انتقل بس215 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.2.3+60', 'التسمية القديمة غابت بb60 (D-213) وتظل غائبة'),
]

ENCODINGS = ('utf-8', 'utf-16-le')


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def marker_bytes(text):
    return {enc: text.encode(enc) for enc in ENCODINGS}


def check(binary_path, label):
    data = read_bytes(binary_path)
    print(f'\n== {label}: {binary_path} ({len(data)} بايت)')
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


def main():
    ap = argparse.ArgumentParser(
        description='التحقق البايتي لحزمتَي b72 (نمط b31..b71 الموثق)')
    ap.add_argument('--android', required=True,
                    help='مسار libapp.so من APK 0.272')
    ap.add_argument('--windows', required=True,
                    help='مسار app.so من حزمة ويندوز 0.272')
    args = ap.parse_args()
    ok_android = check(args.android, 'أندرويد libapp.so')
    ok_windows = check(args.windows, 'ويندوز app.so')
    if ok_android and ok_windows:
        total = len(MARKERS_PRESENT) + len(MARKERS_ABSENT)
        print(f'\nCLEAN {total}/{total} — العلامات كما وثّق سجل س216 حرفاً')
        return 0
    print('\nBREAK — علامة خارجة عن التوثيق؛ لا تُسلَّم الحزمة قبل الحسم')
    return 1


if __name__ == '__main__':
    sys.exit(main())
