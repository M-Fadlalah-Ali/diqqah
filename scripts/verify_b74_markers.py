#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 74 (b74 = v.0.274 — عقد س219: النواة
الحسابية للتجزئة والتحقق بعزل الخلفية وموازنة التوقيت ومؤشر البوابة) —
دِقّة (منهجية السجل الموثقة — نمط b37..b73).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.273.0+73» و«0.272.0+72» غائبان عن ثنائيتَي b74: كتالوج
       الإصدار انتقل بس219 إلى 0.274.0+74 (backup_center.dart) ولا
       مصدر شيفرة مشروعاً يحمل القديمة — وسطر التعليق التوثيقي
       بpubspec خارج الثنائي عرف التعليقات، و«0.271.0+71» انتقل بس218
       و«0.270.0+70» بس215 وهما قبلهما سالخان.
     - «0.2.3+60» غائبة تتابعاً (غابت بb60 بعيد إعادة التسمية D-213).

الحد الصادق الموثق (بنمط م11/م18 بس206 وبند 4 بس207 وس215 وس216 وس218):
جانب س219 بلا لسان ثنائي مميِّز أصلاً — البنّاءات الثلاث بالمجال
(hashInBackground وverifyStoredInBackground وequalizingWorkInBackground)
وموازنة التوقيت بالرفض الثلاثة كلها بنيوية شيفريات لا نصاً للمستخدم،
ومؤشر الجريان [LinearProgressIndicator] بلا لسان جديد بعقد اللسان
المرجعي — فهويته الثنائية نسخة الإصدار ذاتها واختبارات s219 البنيوية
(s219_storage_test وs219_test: الحرس البنيوي لا تحقق متزامن إطلاقاً
والموازنة بموضعها) تحكمها بنياً، ولسان س216 الدخول اليدوي باقٍ حضوراً
بالثنائيتين.

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.274.0+74» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س216: «بيانات الدخول غير صحيحة» (رسالة الفشل العامة — بوابة
    الجهاز) و«اسم الدخول» (عنوان الحقل اليدوي).
  - استمرارية س213: «session_idle_minutes» (مفتاح الخمول) و«من
    المستويات المعتمدة حصراً» (حرس المستويات).
  - استمرارية س212: «بوابة الجهاز».
  - استمرارية س211: «users.create».
  - استمرارية س210: «بحث بالطرف أو الرقم».
  - استمرارية س209: «نبض العمل».
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة».
  غياباً (في الثنائيتين معاً): «0.273.0+73» و«0.272.0+72»
  و«0.271.0+71» و«0.2.3+60».

الاستخدام:
  python3 scripts/verify_b74_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.274.0+74', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('بيانات الدخول غير صحيحة',
     'packages/app/lib/device_gate_screen.dart + packages/storage/lib/src/database.dart (س216 — استمرارية)'),
    ('اسم الدخول', 'packages/app/lib/device_gate_screen.dart (س216 — استمرارية)'),
    ('session_idle_minutes', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('من المستويات المعتمدة حصراً', 'packages/storage/lib/src/database.dart (س213 — استمرارية)'),
    ('بوابة الجهاز', 'packages/app/lib/device_gate_screen.dart (س212 — استمرارية)'),
    ('users.create', 'packages/storage/lib/src/database.dart (س211 — استمرارية)'),
    ('بحث بالطرف أو الرقم', 'packages/app/lib/invoices_screen.dart (س210 — استمرارية)'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 — استمرارية)'),
    ('نُسخ المعرّف إلى الحافظة', 'packages/app/lib/context_menu.dart (س207 — استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.273.0+73', 'كتالوج الإصدار انتقل بس219 إلى 0.274.0+74 — ولا مصدر مشروعاً يحملها'),
    ('0.272.0+72', 'انتقل بس218 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.271.0+71', 'انتقل بس216 وهو قبله سالخ — لا ثنائية تحمله'),
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
        description='التحقق البايتي لحزمتَي b74 (نمط b31..b73 الموثق)')
    ap.add_argument('--android', required=True,
                    help='مسار libapp.so من APK 0.274')
    ap.add_argument('--windows', required=True,
                    help='مسار app.so من حزمة ويندوز 0.274')
    args = ap.parse_args()
    ok_android = check(args.android, 'أندرويد libapp.so')
    ok_windows = check(args.windows, 'ويندوز app.so')
    if ok_android and ok_windows:
        total = len(MARKERS_PRESENT) + len(MARKERS_ABSENT)
        print(f'\nCLEAN {total}/{total} — العلامات كما وثّق سجل س219 حرفاً')
        return 0
    print('\nBREAK — علامة خارجة عن التوثيق؛ لا تُسلَّم الحزمة قبل الحسم')
    return 1


if __name__ == '__main__':
    sys.exit(main())
