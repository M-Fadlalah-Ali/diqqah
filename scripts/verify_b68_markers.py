#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 68 (b68 = v.0.268 — دفعة 2 من خطة
الجلسة والمستخدمين «آلة الحالتين وبوابة الجهاز» س212) —
دِقّة (منهجية السجل الموثقة — نمط b37..b67).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.267.0+67» غائب عن ثنائيتَي b68: كتالوج الإصدار انتقل بس212
       إلى 0.268.0+68 (backup_center.dart) ولا مصدر شيفرة مشروعاً يحمل
       القديمة — وسطر التعليق التوثيقي بpubspec خارج الثنائي عرف
       التعليقات (فحص الحاجز بالجلسة).
     - «0.266.0+66» غائب تتابعاً (كان ترميز س210 المنشورة — والإصدار
       انتقل بس211 ثم بس212).
     - «تبديل المستخدم» كنص حرفي للزر القديم غائب: الزر المباشر
       (منسدلة وكلمة غيرك) انزال بوعي بالدفعة الثانية والتبديل عبر
       الآلة بلسان «قفل وتبديل المستخدم» — وبحرس: «تبديل المستخدم»
       بند قائمة شارة الجلسة الجديد حاضر والفرق بينهما بلسان الزر
       الكامل «قفل وتبديل المستخدم» (فالعينة المقصودة لسان البطاقة).

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.268.0+68» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س212 التخزين بمفتاح الراية «session_locked» و«current_user_id»
    (المستأنف المحفوظ) وأحداث الآلة الثلاثة: «session_locked» و
    «session_logged_out» و«session_resumed» (أسماء الأحداث بسطر
    recordSystemEvent حصراً).
  - س212 رسالة الرفض العربية الموثقة: «كلمة المرور غير صحيحة»
    (resumeSession بعقد verifyUserPassword).
  - س212 الواجهة بألسنتها: «بوابة الجهاز» (عنوان الشاشة الجديدة) و
    «الجلسة مقفلة» (لسان الحالة بالبوابة) و«فتح سريع» (لسان بلاطة
    المستأنف) و«غيّر كلمة مرورك لمتابعة الجلسة» (الحوار الإلزامي
    المنقول للبوابة) و«قفل وتبديل المستخدم» (زر الآلة بالإعدادات) و
    «قفل الجلسة» و«خروج» (بندا شارة الجلسة — والخروج كلمة شائعة
    فحكمه مع أقرانه بالقائمة حاضرين).
  - استمرارية س211: «users.create» و«must_change_password» و
    «مستخدم جديد» و«تغيير كلمة مروري».
  - استمرارية س210: «بحث بالطرف أو الرقم» (بحث م11 بالأرشيف).
  - استمرارية س209: «نبض العمل».
  غياباً (في الثنائيتين معاً): «0.267.0+67» و«0.266.0+66» و«0.2.3+60».

والحد الصادق الموثق: «الخروج» كلمة شائعة بالواجهة فليست مميِّزاً
وحدها (نمط المرشّحين المرفوضين الموثق س159 — حكمها بحضور بندي
القائمة معاً) — والحوار الإلزامي بنمط س211 الموثق (مدموج بالثنائي
الأندرويدي فلا نصاً حرفاً لها هناك — درس س207) فالعلامة الحاكمة
لسانُ البوابة والحالة والفتح السريع بالترميزين — واختبارات s212
وsession_machine_storage_test تحكم السلوك قيمةً.

الاستخدام:
  python3 scripts/verify_b68_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.268.0+68', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('session_locked', 'packages/storage/lib/src/database.dart (س212 — مفتاح الراية وحدث القفل)'),
    ('session_logged_out', 'packages/storage/lib/src/database.dart (س212 — حدث الخروج)'),
    ('session_resumed', 'packages/storage/lib/src/database.dart (س212 — حدث الاستئناف)'),
    ('current_user_id', 'packages/storage/lib/src/database.dart (س211 — المستأنف المحفوظ)'),
    ('كلمة المرور غير صحيحة', 'packages/storage/lib/src/database.dart (س212 — رسالة الرفض)'),
    ('بوابة الجهاز', 'packages/app/lib/device_gate_screen.dart (س212 — عنوان الشاشة)'),
    ('الجلسة مقفلة', 'packages/app/lib/device_gate_screen.dart (س212 — لسان الحالة)'),
    ('فتح سريع', 'packages/app/lib/device_gate_screen.dart (س212 — لسان بلاطة المستأنف)'),
    ('غيّر كلمة مرورك لمتابعة الجلسة', 'packages/app/lib/device_gate_screen.dart (س212 — الحوار الإلزامي)'),
    ('قفل وتبديل المستخدم', 'packages/app/lib/settings_screen.dart (س212 — زر الآلة)'),
    ('قفل الجلسة', 'packages/app/lib/home_screen.dart (س212 — بند الشارة)'),
    ('خروج', 'packages/app/lib/home_screen.dart (س212 — بند الشارة — كلمة شائعة فحكمها مع أقرانها)'),
    ('users.create', 'packages/domain/lib/src/permissions.dart (س211 استمرارية)'),
    ('must_change_password', 'packages/storage/lib/src/database.dart (س211 استمرارية — عمود v34)'),
    ('مستخدم جديد', 'packages/app/lib/users_screen.dart (س211 استمرارية)'),
    ('تغيير كلمة مروري', 'packages/app/lib/settings_screen.dart (س211 استمرارية — البطاقة)'),
    ('بحث بالطرف أو الرقم', 'packages/app/lib/invoices_screen.dart (س210 استمرارية)'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.267.0+67', 'كتالوج الإصدار انتقل إلى 0.268.0+68 — ولا مصدر شيفرة يحملها'),
    ('0.266.0+66', 'ترميز س210 غاب بانتقال الإصدار بس211 ثم بس212'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.268')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.268')
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
