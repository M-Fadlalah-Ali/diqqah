#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 67 (b67 = v.0.267 — دفعة 1 من خطة
الجلسة والمستخدمين «إنشاء المستخدمين وإدارتهم بأقل امتياز» س211) —
دِقّة (منهجية السجل الموثقة — نمط b37..b66).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً — كل علامة هنا موقّفة على
     ملفها وجرى التحقق الحرفي منها بالمصدر قبل البحث بالثنائي.
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. انتقالات الإلغاء موثقة بأساسها:
     - «0.266.0+66» غائب عن ثنائيتَي b67: كتالوج الإصدار انتقل بس211
       إلى 0.267.0+67 (backup_center.dart) ولا مصدر شيفرة مشروعاً يحمل
       القديمة — وسطر التعليق التوثيقي بpubspec خارج الثنائي عرف
       التعليقات (فحص الحاجز بالجلسة).
     - «0.264.0+64» غائب تتابعاً (كان ترميز الدفعات الموازية س208
       المنشورة — والإصدار انتقل بس211).

العلامات:
  حضوراً (في الثنائيتين معاً):
  - مرشّح الإصدار «0.267.0+67» (pubspec وكتالوج الإصدار معاً حرفاً).
  - س211 التخزين بالأحداث الثلاثة: «user_created» و
    «user_active_toggled» و«user_password_changed» (أسماء الأحداث
    بسطر recordSystemEvent حصراً) و«must_change_password» (اسم العمود
    بحرس الترحيلة v34).
  - س211 البوابتان الفرعيتان بمفتاحيهما الشيفريين: «users.create»
    و«users.deactivate» (permissions.dart).
  - س211 حمايات التخزين برسائلها العربية الموثقة: «لا تعطيل للجلسة
    الحالية» و«آخر مستخدم نشط» و«بكامل الوحدات بيدٍ غير كاملة».
  - س211 الواجهة بألسنتها: «مستخدم جديد» (زر الشاشة الجديدة) و
    «تغيير كلمة مروري» (بطاقة المستخدم الحالي).
  - استمرارية س210: «بحث بالطرف أو الرقم» (بحث م11 بالأرشيف).
  - استمرارية س209: «نبض العمل».
  - استمرارية س207: «نُسخ المعرّف إلى الحافظة» (context_menu).
  غياباً (في الثنائيتين معاً): «0.266.0+66» و«0.264.0+64» و«0.2.3+60».

والحد الصادق الموثق: دور الولادة الأعرى «مستخدم» كلمة شائعة فليس
مميِّزاً ثنائياً أصلاً (نمط المرشّحين المرفوضين الموثق س159) — وهويته
الثنائية بحمولته الشيفرة «users.create» وبوابة التعطيل وحمايات رسائل
الرفض العربية الثلاث — والتوليد الآلي للأدوار بensureDefaultRoles
بنيوي شيفري بلا لسان ثنائي مستقل بنمط م06 وبند 4 — واختبارات s211
وusers_admin_storage_test تحكم سلوكه قيمةً. وسطر الإصدار العرضي
«دِقَّة v.0.267» بشارة استيفاء مدموجة بالثنائي الأندرويدي فلا نصاً
حرفاً لها هناك (درس س207 الموثق) — والكتالوج التقني 0.267.0+67 هو
العلامة الحاكمة للإصدار بالترميزين.

الاستخدام:
  python3 scripts/verify_b67_markers.py --android <libapp.so> --windows <app.so>
"""
import argparse
import sys

MARKERS_PRESENT = [
    # (النص، الملف الموثق عليه)
    ('0.267.0+67', 'packages/app/pubspec.yaml + packages/app/lib/backup_center.dart'),
    ('user_created', 'packages/storage/lib/src/database.dart (س211 — حدث الولادة)'),
    ('user_active_toggled', 'packages/storage/lib/src/database.dart (س211 — حدث الحالة)'),
    ('user_password_changed', 'packages/storage/lib/src/database.dart (س211 — حدث الكلمة)'),
    ('must_change_password', 'packages/storage/lib/src/database.dart (س211 — عمود v34)'),
    ('users.create', 'packages/domain/lib/src/permissions.dart (س211 — بوابة الإنشاء)'),
    ('users.deactivate', 'packages/domain/lib/src/permissions.dart (س211 — بوابة الحالة)'),
    ('لا تعطيل للجلسة الحالية', 'packages/storage/lib/src/database.dart (س211 — الحماية الأولى)'),
    ('آخر مستخدم نشط', 'packages/storage/lib/src/database.dart (س211 — الحماية الثانية)'),
    ('بكامل الوحدات بيدٍ غير كاملة', 'packages/storage/lib/src/database.dart (س211 — الحماية الثالثة)'),
    ('مستخدم جديد', 'packages/app/lib/users_screen.dart (س211 — زر الشاشة)'),
    ('تغيير كلمة مروري', 'packages/app/lib/settings_screen.dart (س211 — بطاقة الجلسة)'),
    ('بحث بالطرف أو الرقم', 'packages/app/lib/invoices_screen.dart (س210 استمرارية)'),
    ('نبض العمل', 'packages/app/lib/home_screen.dart (س209 استمرارية)'),
    ('نُسخ المعرّف إلى الحافظة', 'packages/app/lib/context_menu.dart (س207 استمرارية)'),
]

MARKERS_ABSENT = [
    ('0.266.0+66', 'كتالوج الإصدار انتقل إلى 0.267.0+67 — ولا مصدر شيفرة يحملها'),
    ('0.264.0+64', 'ترميز الدفعات الموازية س208 غاب بانتقال الإصدار بس211'),
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
    ap.add_argument('--android', required=True, help='مسار libapp.so من APK 0.267')
    ap.add_argument('--windows', required=True, help='مسار app.so من حزمة ويندوز 0.267')
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
