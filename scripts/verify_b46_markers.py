#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتي b46 — دِقّة (منهجية السجل الموثقة — نمط b37..b45).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً (كل علامة موقّفة على ملفها
     بالمصدر وتُتحقق حرفياً فيه قبل البحث بالثنائي).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. المميِّز محتوى لا أسماء دوال نقية (درس b39/b40 — المرمّز يسقط الأسماء).
  4. المميِّز بالعكس على المرجع الأحدث المتاح — وهو هنا b45 ذاته (ثنائيتا
     التشغيل 45 — **نُزّلتا حياً بالAPI** بأرقام س148 الموثقة 14175380552
     أندرويد و14175045942 ويندوز وبصمتا الحزمتين مطابقتان لوثائق س148
     حرفاً e116a3fe…/bca6839… — نمط س146 فالمرجع أصيل): مميِّزات س149
     (تغليف النسخ v3 وتشفير الملفات المصاحبة DEK/KEK) ومميِّزات س150
     (رفع تكرارات هاش الدخول 600,000) الغائبة عنه حاضرة في b46 فتثبت أن
     ما بُني هو الجديد حامل P1/P2 معاً، وما قبله (استمرارية وس141 وس142
     وس144 وس146 وس148) حاضر بb45 أصلاً فلا يُفحص بالعكس عليه بل يُفحص
     حضوراً في b46 حصراً (استمرارية).

درس مستجدّ موثق (س148/b45): مرشّح الإصدار «0.2.3+41» انتقل من الأداة
بحذفه بعد b45 (نمط 0.2.3+39 و0.2.3+40) — وكذلك مرشّحا «needsUnlock»
اسم دالٍ نقية فسقطها المرمّز (قاعدة 3) فلم يصلا الأداة أصلاً.

أكتُبت لتشغيل إغلاق b46 (س151): استمرارية أساس 5 + مميِّزات س141 إحدى
عشرة + مميِّزات س142 ثلاث + مميِّزات س144 سبع + مميِّزات س146 تسع +
مميِّزات س148 إحدى عشرة (بعد حذف مرشّح الإصدار 0.2.3+41) + مميِّزات س149
سبع عشرة (لاتينية 5 وعربية 12) + مميِّزات س150 أربع (الإصدار 0.2.3+43
واسم حدث الترقية ومفتاحا الحمولة) — سطح س150 المجمَّع صغير صادقاً:
الدفعة منطق هاشر حصراً وبلا نصوص واجهة جديدة، والحدودية موثقة بالسجل.

الاستخدام:
  python3 scripts/verify_b46_markers.py <b46_libapp.so> <b46_app.so> \
      [--ref-android <b45_libapp.so> --ref-windows <b45_app.so>] \
      [--repo <مسار المستودع>]
"""

import argparse
import sys

REPO_DEFAULT = "/home/z/my-project/diqqah"
APP = "packages/app/lib"
DOM = "packages/domain/lib/src"
STO = "packages/storage/lib/src"

# ── الاستمرارية: علامات أساس قديمة يجب أن تبقى ─────────────────────────────
CONTINUITY = [
    (f"{APP}/gate_error_screen.dart", "GateErrorScreen"),
    (f"{STO}/database.dart", "snapshotBeforeUpgrade"),
    ("packages/app/pubspec.yaml", "0.2.3"),
    (f"{APP}/home_screen.dart", "معطلة"),
    (f"{APP}/home_screen.dart", "طلبات الشراء والبيع"),
]

# ── مميِّزات س141: قالبا الافتتاحي والمتابعات ───────────────────────────────
S141 = [
    (f"{DOM}/import_core.dart", "party_balances"),
    (f"{DOM}/import_core.dart", "opening_full"),
    (f"{DOM}/import_core.dart", "DQ-1025"),
    (f"{DOM}/import_core.dart", "DQ-1026"),
    (f"{STO}/database.dart", "import_opening"),
    (f"{STO}/database.dart", "follow_ups_reviewed"),
    (f"{APP}/follow_ups_screen.dart", "لا متابعات الآن — كل شيء متابَع"),
    (f"{APP}/home_screen.dart", "افتح المتابعات"),
    (f"{APP}/import_screen.dart", "تاريخ القيد الافتتاحي"),
    (f"{APP}/follow_ups_screen.dart", "تعديل التاريخ من شاشة الفترات"),
    (f"{DOM}/import_core.dart", "رصيد أول المدة جهة واحدة"),
]

# ── مميِّزات س142: التشطيب ──────────────────────────────────────────────────
S142 = [
    (f"{APP}/import_screen.dart", "ما لا يُستورد بهذا المسار"),
    (f"{APP}/import_screen.dart", "اصطلاح الإشارات"),
    (f"{APP}/import_screen.dart", "هذا استيراد أرصدة لا ترحيل"),
]

# ── مميِّزات س144: الوحدة 3 «كميات المخزون الافتتاحية» (استمرارية) ──────────
S144 = [
    (f"{APP}/import_screen.dart", "كميات المخزون"),
    (f"{APP}/import_screen.dart", "مقابل الإذن: 43 «إيرادات أخرى»"),
    (f"{DOM}/import_core.dart", "opening_qty"),
    (f"{DOM}/import_core.dart", "استيراد كميات المخزون الافتتاحية"),
    (f"{DOM}/import_core.dart", "كود الصنف إلزامي (SKU)."),
    (f"{STO}/database.dart",
     "لا مستودع نشط لإذن إدخال كميات المخزون الافتتاحية."),
    (f"{STO}/database.dart",
     "إذن إدخال كميات المخزون الافتتاحية — بقيم الملف"),
]

# ── مميِّزات س146: كتالوج ISO 4217 (استمرارية) ──────────────────────────────
S146 = [
    (f"{APP}/currencies_screen.dart",
     "عملة جديدة — من الكتالوج العالمي ISO 4217"),
    (f"{APP}/currencies_screen.dart",
     "ابحث بالكود أو بالاسم (عربي/إنجليزي)"),
    (f"{APP}/currencies_screen.dart",
     "قابل للتعديل قبل الحفظ، وبعده لا تعديل (D-194)"),
    (f"{APP}/currencies_screen.dart", "الاسم والرمز تُملآن تلقائياً"),
    (f"{APP}/currencies_screen.dart",
     "لا نتائج بالكتالوج — عملات الدفع العالمية كلها"),
    (f"{DOM}/iso4217_catalog.dart", "دينار كويتي"),
    (f"{DOM}/iso4217_catalog.dart", "هللة"),
    (f"{APP}/tafqit.dart", "ريال سعودي"),
    (f"{APP}/tafqit.dart", "ليرة تركية"),
]

# ── مميِّزات س148: تشفير القاعدة المحلية (استمرارية — 11 بعد حذف الإصدار) ───
S148 = [
    # مفتاح التخزين بالخزنة (flutter_secure_storage — F-150/د-٣)
    (f"{APP}/db_key_vault.dart", "diqqah.db.key.v1"),
    # لاحقة ملف ترحيل التشفير المؤقت (db_encryption.dart)
    (f"{STO}/db_encryption.dart", ".enc-migrate-tmp"),
    # لاحقة لقطة ما قبل التشفير (نمط preenc — D-197)
    (f"{STO}/db_encryption.dart", ".preenc"),
    # النمط المشفر المعتمد د-٢ (ChaCha20-Poly1305 AEAD بمعجم MC)
    (f"{STO}/db_encryption.dart", "chacha20"),
    # تثبيت النمط قبل المفتاح بsetup الفتح (توثيق MC)
    (f"{STO}/database.dart", "PRAGMA cipher = '"),
    # حرس البيئة الصوتي بالترحيل (StateError حي — لا assert)
    (f"{STO}/db_encryption.dart", "بيئة القاعدة بلا دمج تشفير"),
    # رسالة إبطال الترحيل (StateError حي)
    (f"{STO}/db_encryption.dart",
     "الترحيل أُبطل فالقاعدة النص الصريح كما هي بلا مساس"),
    # رسالة إبطال تصدير الصورة (StateError حي)
    (f"{STO}/db_encryption.dart",
     "تصدير الصورة الصريحة أُبطل فلا نسخة مشفرة بمفتاح جهاز"),
    # حرس صيغة المفتاح بالخزنة (StateError حي)
    (f"{STO}/db_encryption.dart", "مفتاح الخزنة ليس 64 خانة ست عشرية"),
    # حارس النسخ: صورة مشفرة بلا مفتاح معروف = إبطال لا تعتيم مزدوج
    (f"{STO}/backup.dart",
     "صورة النسخة مشفرة بمفتاح جهاز ولا مفتاح معروف"),
    # حرس ما بعد النزع (StateError حي)
    (f"{STO}/backup.dart", "الصورة ما زالت مشفرة بعد النزع"),
]

# ── مميِّزات س149: تغليف النسخ v3 وتشفير الملفات المصاحبة (مميِّز بالعكس
#    على b45) ────────────────────────────────────────────────────────────────
S149 = [
    # مفتاح KEK للصور بالخزنة — مستقل عن مفتاح القاعدة (P1-ب)
    (f"{APP}/db_key_vault.dart", "diqqah.images.key.v1"),
    # مفتاحا كلمة القفل ورمز الاسترداد المخزنان (P1-أ بالواجهة)
    (f"{APP}/db_key_vault.dart", "diqqah.backup.pass.v1"),
    (f"{APP}/db_key_vault.dart", "diqqah.backup.recovery.v1"),
    # بطاقة الملف المشفر — السحر الثماني البايتي (file_encryption.dart)
    (f"{STO}/file_encryption.dart", "DQIMGENC"),
    # سياق HKDF لعزل مفتاح الصور عن كل استعمال آخر
    (f"{STO}/file_encryption.dart", "diqqah-images-v1"),
    # رفض فك ملف بمفتاح جهاز آخر (ImageCipherException حية)
    (f"{STO}/file_encryption.dart",
     "مفتاح هذا الجهاز لا يفك الملف — KEK الخزنة يخالف أو الملف تالف"),
    # استثناءات القفل v3 بالمجال النقي (BackupCipherException حية)
    (f"{DOM}/backup.dart",
     "النسخة مقفلة بكلمة مرور — أدخل كلمة المرور أو رمز "),
    (f"{DOM}/backup.dart",
     "كلمة المرور أو رمز الاسترداد خاطئ — تحقق ثم أعد المحاولة"),
    (f"{DOM}/backup.dart",
     "بنية النسخة المقفلة تالف — الملف غير سليم"),
    (f"{DOM}/backup.dart",
     "نوع سجل غير معروف بالنسخة المقفلة — الملف غير سليم"),
    # بطاقة قفل النسخ بالإعدادات (الواجهة)
    (f"{APP}/settings_screen.dart", "قفل النسخ بكلمة مرور"),
    (f"{APP}/settings_screen.dart", "توليد رمز الاسترداد"),
    (f"{APP}/settings_screen.dart", "رمز الاسترداد — سجّله خارج الجهاز"),
    (f"{APP}/settings_screen.dart",
     "أو رمز الاسترداد على أي جهاز — فضع كلمة تعرفها وحداً"),
    # سببا الرفض الحيان بتحقق GFS عند مقفلة بلا أسرار محمّلة
    (f"{STO}/backup_gfs.dart",
     "نسخة مقفلة بكلمة مرور ولا أسرار محمّلة للتحقق"),
    (f"{STO}/backup_gfs.dart",
     "نسخة مقفلة ولا أسرار محمّلة للتحقق"),
    # رسالة ترحيل الصور للتشفير عند الافتتاح (DQ-IMAGES — bootstrap)
    (f"{APP}/main.dart", "ترحيل الصور للتشفير"),
]

# ── مميِّزات س150: رفع تكرارات هاش الدخول إلى 600,000 (مميِّز بالعكس على
#    b45) — سطح مجمَّع صغير صادق: الدفعة منطق هاشر بلا نصوص واجهة جديدة ────
S150 = [
    # تاريخ الإصدار المحفور kAppVersion (بمصدره الموحد)
    (f"{APP}/backup_center.dart", "0.2.3+43"),
    # اسم حدث الترقية بنظام الأحداث (بذرة m4)
    (f"{STO}/database.dart", "password_hash_iterations_upgraded"),
    # مفتاحا حمولة الحدث «من وإلى»
    (f"{STO}/database.dart", "from_iterations"),
    (f"{STO}/database.dart", "to_iterations"),
]


def read_marker(repo: str, file_path: str, marker: str) -> str:
    """يقرأ العلامة من المصدر ويتحقق حضورها الحرفي فيه (قاعدة 1)."""
    with open(f"{repo}/{file_path}", encoding="utf-8") as f:
        src = f.read()
    if marker not in src:
        print(f"فشل: العلامة «{marker}» غير موجودة بالمصدر {file_path}")
        sys.exit(2)
    return marker


def encodings(marker: str):
    """البحث بالترميزين معاً (درس b31: العربية UTF-16LE بالثنائي)."""
    utf8 = marker.encode("utf-8")
    utf16 = marker.encode("utf-16-le")
    variants = [utf8]
    if utf16 != utf8:
        variants.append(utf16)
    return variants


def found(blob: bytes, marker: str) -> bool:
    return any(v in blob for v in encodings(marker))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("android")
    ap.add_argument("windows")
    ap.add_argument("--ref-android")
    ap.add_argument("--ref-windows")
    ap.add_argument("--repo", default=REPO_DEFAULT)
    args = ap.parse_args()

    with open(args.android, "rb") as f:
        android = f.read()
    with open(args.windows, "rb") as f:
        windows = f.read()
    ref_android = ref_windows = None
    if args.ref_android and args.ref_windows:
        with open(args.ref_android, "rb") as f:
            ref_android = f.read()
        with open(args.ref_windows, "rb") as f:
            ref_windows = f.read()

    groups = [
        ("استمرارية", CONTINUITY, False),
        ("مميِّزات س141", S141, False),
        ("مميِّزات س142", S142, False),
        ("مميِّزات س144", S144, False),
        ("مميِّزات س146", S146, False),
        ("مميِّزات س148", S148, False),
        ("مميِّزات س149", S149, True),
        ("مميِّزات س150", S150, True),
    ]
    total = 0
    failures = 0
    for label, markers, is_new in groups:
        for file_path, marker in markers:
            marker = read_marker(args.repo, file_path, marker)
            total += 1
            ok_a = found(android, marker)
            ok_w = found(windows, marker)
            if ok_a and ok_w:
                status = "حاضرة بالثنائيتين"
            else:
                status = f"أندرويد={'حاضرة' if ok_a else 'غائبة'} " \
                         f"ويندوز={'حاضرة' if ok_w else 'غائبة'}"
                failures += 1
            line = f"[{label}] {marker}: {status}"
            if is_new and ref_android is not None and ref_windows is not None:
                in_ref = found(ref_android, marker) or \
                    found(ref_windows, marker)
                line += f" | بالمرجع b45: {'حاضرة (ليست مميزاً!)' if in_ref else 'غائبة'}"
                if in_ref:
                    failures += 1
            print(line)

    print(f"\nالحصيلة: {total - failures}/{total} علامة سليمة")
    if failures:
        print(f"فشل: {failures} علامة")
        return 1
    print("CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
