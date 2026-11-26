#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 70 (b70 = v.0.270 — دفعة 3 من خطة
الجلسة والمستخدمين «الخمول والبيومتري وFLAG_SECURE وتنظيم الإعدادات» س213) —
دِقّة (منهجية السجل الموثقة — نمط b37..b68).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.268.0+68» و«0.269.0+69» غائبان عن ثنائيتَي b70: كتالوج الإصدار انتقل بس213
       إلى 0.270.0+70 (backup_center.dart) ولا مصدر شيفرة مشروعاً يحمل
       القديمة — وسطر التعليق التوثيقي بpubspec خارج الثنائي عرف
       التعليقات (فحص الحاجز بالجلسة).
     - «0.267.0+67» و«0.2.3+60» غائبتان تتابعاً بالانتقالات الموثقة
       س211 وb60 (D-213).

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.270.0+70» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س213 التخزين بمفتاح الخمول «session_idle_minutes» ورسالة حرس
    المستويات المغلقة «من المستويات المعتمدة حصراً» ومسار البصمة
    «device_gate_biometric» برسالة حرسه «الفتح بالبصمة لصاحب الجلسة
    المعلقة حصراً» (أسماء الأحداث الثلاثة بترميز س212 باقية).
  - س213 الواجهة بلسان البطاقة «الخمول وقفل الجهاز» ولسان المنسدلة
    «قفل الجلسة بعد خمول» ولسان القانون «تقفل الجلسة فوراً» وزر
    البوابة «فتح بالبصمة» ورسالة رفضها «لم يُكمل التحقق البيومتري —
    أدخل كلمة المرور» وشرح البوابة «بلاطة غيره بكلمته».
  - س213 تنظيم الإعدادات D-218 بترويسات الأقسام الخمسة حرفاً:
    «الهوية والصلاحيات» و«البيانات والأمان» و«سياسات البيع» و
    «العرض والمظهر» و«العمليات» (العمليات كلمة قصيرة فحكمها مع
    أقرانها الخمسة حضوراً مجتمعة — الحد الصادق بترويسة الأداة).
  - استمرارية س212: «بوابة الجهاز» و«فتح سريع» و«قفل وتبديل
    المستخدم» و«session_locked» و«must_change_password».
  - استمرارية س211: «users.create».
  - استمرارية س210: «بحث بالطرف أو الرقم».
  - استمرارية س209: «نبض العمل».
  غياباً (في الثنائيتين معاً): «0.268.0+68» و«0.267.0+67» و«0.2.3+60».

والحد الصادق الموثق: «العمليات» كلمة قصيرة قد تحملها عبارات أخرى
فحكمها حضورُ ترويسات الأقسام الخمسة معاً (بنمط «الخروج» الموثق س212)
— ودرس الجولة الموثق بالدفعة (الجديد — نمط س207): **الاقتطاع الثابت
بالتوليد** — AOT يطوى Platform.isAndroid زمن التوليد فمسار البصمة
كله يُقتطع من ثنائي ويندوز (بما فيهم سلاسل التخزين المستدعاة منه
حصراً) فعلامات البصمة الخمس تحكم ثنائي الأندرويد حصراً — وعلامات
البصمة نصوص لسان صريحة لا مستمدة — واختبارات s213 و
session_idle_storage_test تحكم السلوك قيمةً.

الاستخدام:
  python3 scripts/verify_b69_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.270.0+70', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('session_idle_minutes', 'packages/storage/lib/src/database.dart (س213 — مفتاح الخمول)'),
    ('من المستويات المعتمدة حصراً', 'packages/storage/lib/src/database.dart (س213 — حرس المستويات)'),
    ('الخمول وقفل الجهاز', 'packages/app/lib/settings_screen.dart (س213 — بطاقة الخمول)'),
    ('قفل الجلسة بعد خمول', 'packages/app/lib/settings_screen.dart (س213 — لسان المنسدلة)'),
    ('تقفل الجلسة فوراً', 'packages/app/lib/settings_screen.dart (س213 — لسان قانون المغادرة)'),
    ('الهوية والصلاحيات', 'packages/app/lib/settings_screen.dart (س213 — ترويسة القسم 1)'),
    ('البيانات والأمان', 'packages/app/lib/settings_screen.dart (س213 — ترويسة القسم 2)'),
    ('سياسات البيع', 'packages/app/lib/settings_screen.dart (س213 — ترويسة القسم 3)'),
    ('العرض والمظهر', 'packages/app/lib/settings_screen.dart (س213 — ترويسة القسم 4)'),
    ('العمليات', 'packages/app/lib/settings_screen.dart (س213 — ترويسة القسم 5 — كلمة قصيرة فحكمها مع أقرانها)'),
    ('بوابة الجهاز', 'packages/app/lib/device_gate_screen.dart (س212 استمرارية)'),
    ('فتح سريع', 'packages/app/lib/device_gate_screen.dart (س212 استمرارية)'),
    ('قفل وتبديل المستخدم', 'packages/app/lib/settings_screen.dart (س212 استمرارية)'),
    ('session_locked', 'packages/storage/lib/src/database.dart (س212 استمرارية — مفتاح الراية)'),
    ('must_change_password', 'packages/storage/lib/src/database.dart (س211 استمرارية — عمود v34)'),
    ('users.create', 'packages/domain/lib/src/permissions.dart (س211 استمرارية)'),
    ('بحث بالطرف أو الرقم', 'packages/app/lib/invoices_screen.dart (س210 استمرارية)'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 استمرارية)'),
]

# علامات البصمة الخمس — ثنائي الأندرويد حصراً (درس الجولة الموثق
# بالدفعة: الاقتطاع الثابت بالتوليد — AOT يطوى Platform.isAndroid
# على ويندوز فيثبت حارس _checkBiometric ويقتطع مسار البصمة كله من
# ثنائيتها بما فيهم سلاسل التخزين المستدعاة منه حصراً — والسلوك
# عينُ الحد الصادق بالدفعة «الويندوز بلا قناة أصلاً فالبوابة بلا
# زر بصة عنده» — والحكمة لسانُ الأندرويد حامل المسار حصراً بنمط
# درس س207 «بشّارة الاستيفاء مدموجة بالثنائي الأندرويدي»).
MARKERS_ANDROID_ONLY = [
    ('device_gate_biometric', 'packages/storage/lib/src/database.dart (س213 — مسار البصمة بالحدث)'),
    ('الفتح بالبصمة لصاحب الجلسة المعلقة حصراً', 'packages/storage/lib/src/database.dart (س213 — حرس المستأنف)'),
    ('فتح بالبصمة', 'packages/app/lib/device_gate_screen.dart (س213 — زر البوابة)'),
    ('لم يُكمل التحقق البيومتري — أدخل كلمة المرور', 'packages/app/lib/device_gate_screen.dart (س213 — رسالة الرفض)'),
    ('بلاطة غيره بكلمته', 'packages/app/lib/device_gate_screen.dart (س213 — شرح حصرية البصمة)'),
]

MARKERS_ABSENT = [
    ('0.269.0+69', 'الترميز المحجوز لتشغيل 69 الفاشل — لا ثنائية تحمله بنمط b45'),
    ('0.268.0+68', 'كتالوج الإصدار انتقل إلى 0.270.0+70 — ولا مصدر شيفرة يحملها'),
    ('0.267.0+67', 'ترميز س211 غاب بانتقال الإصدار بس212 ثم بس213'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.270')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.270')
    args = ap.parse_args()
    results: list = []
    ok = True
    ok = check(args.android, 'أندرويد libapp.so', results) and ok
    ok = check(args.windows, 'ويندوز app.so', results) and ok
    # علامات البصمة — الأندرويد حصراً (الاقتطاع الثابت بالتوليد)
    with open(args.android, 'rb') as f:
        blob = f.read()
    for text, where in MARKERS_ANDROID_ONLY:
        found = any(enc in blob for enc in encodings(text))
        results.append(f'[أندرويد libapp.so] حضور (حصراً): «{text}» → {"حاضر" if found else "غائب!"} ({where})')
        ok = ok and found
    for line in results:
        print(line)
    total = (len(MARKERS_PRESENT) + len(MARKERS_ABSENT)) * 2 + len(MARKERS_ANDROID_ONLY)
    print(f'المجموع: {total} فحصاً — {"CLEAN" if ok else "فشل"}')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
