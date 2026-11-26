#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 75 (b75 = v.0.275 — عقد س221: الدفعات
الخمس بأمر المالك — النواة الأصيلة للتجزئة واتساق نبض العمل وعزل النوع
بجهة الأرشيف وحد العرض المتدرج) — دِقّة (منهجية السجل الموثقة — نمط
b31..b74).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي، ولا
     تعليقات ولا أسماء دوال (المرمّز يسقط الأسماء النقية — درس b39/b40).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.274.0+74» غائبة عن ثنائيتَي b75: كتالوج الإصدار انتقل بس221
       إلى 0.275.0+75 (أداة الدفعة s221_transfer_version.py بمواضع
       حية مُسَمَّاة) ولا مصدر شيفرة مشروعاً يحمل القديمة — وسطر
       التعليق التوثيقي بpubspec خارج الثنائي عرف التعليقات.
     - «0.273.0+73» و«0.272.0+72» و«0.271.0+71» انتقلت بس219 وس218
       وس216 تتابعاً وهما سالخة، و«0.2.3+60» غابت بb60 (D-213).
     - «افتح المتابعات» غائبة: الشريط الأحمر للمتابعات أُزيل بس221
       بد3 بقرار المالك الموثق (نبض العمل المصدر الواحد — الباراميتر
       والقيمة واللسان لا أثر لهم)، وكان اللسان حياً بhome_screen
       حتى س221 (actionLabel اللافتة المزالة) وgrep الحي صفر موضع.

الحد الصادق الموثق (بنمط م11/م18 بس206 وبند 4 بس207..س221):
جانب س221 البنيوي بلا لسان ثنائي مميِّز كاملاً — منفذ المنصة المتسلسل
والتحقق الذاتي بمتجه معياري وإعادة توجيه المدخلات اليومية الثلاثة
(أفعال محقونة لا ألسنة) ومستمع صحة النسخ هيكلية شيفريات لا نصاً
للمستخدم — فهويته الثنائية: نسخة الإصدار ذاتها + اسم قناة المنصة
الحي + اختبارات s221 البنيوية (s221_test وs221_pulse_test وs221_docs_test)
التي تحكمها بنياً، ولسان س216 الدخول اليدوي باقٍ حضوراً بالثنائيتين.

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.275.0+75» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س221 د2: «diqqah/security/pbkdf2» (اسم قناة المنصة الحي —
    native_pbkdf2.dart، والجانب الكوتلن خارج libapp.so بحد صادق).
  - س221 د5: «عرض المزيد — الباقي » (زر حد العرض المتدرج —
    list_display.dart) و«المبيعات كلها (البيع ومردوده)» (لسان الجهة
    بعد العزل — invoices_screen.dart).
  - س216: «بيانات الدخول غير صحيحة» (رسالة الفشل العامة — بوابة
    الجهاز) و«اسم الدخول» (عنوان الحقل — users_screen).
  - استمرارية س213: «session_idle_minutes» (مفتاح الخمول) و«من
    المستويات المعتمدة حصراً» (حرس المستويات).
  - استمرارية س212: «بوابة الجهاز».
  - استمرارية س211: «users.create».
  - استمرارية س210: «بحث بالطرف أو الرقم».
  - استمرارية س209: «نبض العمل».
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة».
  غياباً (في الثنائيتين معاً): «0.274.0+74» و«0.273.0+73»
  و«0.272.0+72» و«0.271.0+71» و«0.2.3+60» و«افتح المتابعات».

الاستخدام:
  python3 scripts/verify_b75_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.275.0+75', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('diqqah/security/pbkdf2',
     'packages/app/lib/native_pbkdf2.dart (س221 د2 — قناة المنصة الحية)'),
    ('عرض المزيد — الباقي ',
     'packages/app/lib/list_display.dart (س221 د5 — حد العرض المتدرج)'),
    ('المبيعات كلها (البيع ومردوده)',
     'packages/app/lib/invoices_screen.dart (س221 د5 — لسان الجهة بعد العزل)'),
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

MARKERS_ABSENT = [
    ('0.274.0+74', 'كتالوج الإصدار انتقل بس221 إلى 0.275.0+75 — ولا مصدر مشروعاً يحملها'),
    ('0.273.0+73', 'انتقل بس219 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.272.0+72', 'انتقل بس218 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.271.0+71', 'انتقل بس216 وهو قبله سالخ — لا ثنائية تحمله'),
    ('0.2.3+60', 'التسمية القديمة غابت بb60 (D-213) وتظل غائبة'),
    ('افتح المتابعات', 'الشريط الأحمر أُزيل بس221 بد3 (نبض العمل المصدر الواحد) — واللسان المزال لا ثنائية تحمله'),
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
        description='التحقق البايتي لحزمتَي b75 (نمط b31..b74 الموثق)')
    ap.add_argument('--android', required=True,
                    help='مسار libapp.so من APK 0.275')
    ap.add_argument('--windows', required=True,
                    help='مسار app.so من حزمة ويندوز 0.275')
    args = ap.parse_args()
    ok_android = check(args.android, 'أندرويد libapp.so')
    ok_windows = check(args.windows, 'ويندوز app.so')
    if ok_android and ok_windows:
        total = len(MARKERS_PRESENT) + len(MARKERS_ABSENT)
        print(f'\nCLEAN {total}/{total} — العلامات كما وثّق سجل س221 حرفاً')
        return 0
    print('\nBREAK — علامة خارجة عن التوثيق؛ لا تُسلَّم الحزمة قبل الحسم')
    return 1


if __name__ == '__main__':
    sys.exit(main())
