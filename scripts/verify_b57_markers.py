#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي لحزمتَي التشغيل 57 (b57 بحكم الأمر) — دِقّة
(منهجية السجل الموثقة — نمط b37..b56).

قواعد الأداة (دروس موثقة بالسجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً (كل علامة موقّفة على ملفها
     بالمصدر وتُتحقق حرفياً فيه قبل البحث بالثنائي) — لا تعليقات مصدرية
     ولا أسماء دوال نقية (درس b39/b40 — المرمّز يسقط الأسماء النقية).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. المميِّز بالعكس على المرجع الأحدث المتاح — وهو هنا b56 ذاته (ثنائيتا
     التشغيل 56 — استُخرجتا حياً من حزم download بالبصمتين — نمط الأسلاف
     فالمرجع أصيل):
     مميِّزات س181/س182 (رموز التنظيف الأربعة DQ-1119..1124 ومرشّح الإصدار
     0.2.3+57 وبطاقة المظهر وثلاثة أوضاعه ومنتقي التاريخ ومفتاح شبكة
     الرئيسية) الغائبة عنه حاضرة في b57 فتثبت أن ما بُني هو الجديد الحامل
     للثيم والأيقونات والمنتقي والتنظيف الكامل، وما قبله (استمرارية
     وس141..س178) حاضر بb56 أصلاً فلا يُفحص بالعكس عليه بل يُفحص حضوراً
     في b57 حصراً.

انتقالات موثقة (نمط الأسلاف):
  - مرشّح الإصدار «0.2.3+56» انتقل من الأداة بحذفه بعد b56 (نمط
    0.2.3+39/40/41/43/44/46/47/49/50/55/56) — وحلّ محله «0.2.3+57»
    بمجموعة الجديد.
  - مميِّزات س178 (بلاطة المزامنة) انتقلت إلى الاستمرارية بعد b56
    (نمط س164 بعد b54 وس170..س175 بعد b55) — ومميِّزات س179..س180
    إغلاق دفعات وثائقية/نصية فلا مميِّز ثنائي لها أصلاً.
  - المسبار الحي قبل التثبيت (نمط س168/س179 — scripts/probe_b57_markers.py):
    9 مرشحات صادقات (حاضرات بالمصدر وبثنائيتي b57 وغائبات عن ثنائيتي
    b56): رموز التنظيف DQ-1119/1122/1123/1124 ومرشّح الإصدار 0.2.3+57
    وبطاقة «المظهر» بلسانها ومساعدها و«اختيار التاريخ» ومفتاح الشبكة
    home_modules_grid ومفتاح تفضيل الوضع app_theme_mode.
  - درس b55 الموثق باقٍ عرفاً: وحدات محرك المزامنة النقية (د1..د5) لا
    يستوردها التطبيق بشيفرة حية فتُقتلع من الثنائي — فلا تُفحص مميزاتها
    على الثنائي (موصولها س-25).

الاستخدام:
  python3 scripts/verify_b57_markers.py <b57_libapp.so> <b57_app.so> \
      [--ref-android <b56_libapp.so> --ref-windows <b56_app.so>] \
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

# ── مميِّزات س141: قالبا الافتتاحي والمتابعات (استمرارية) ───────────────────
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

# ── مميِّزات س142: التشطيب (استمرارية) ──────────────────────────────────────
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

# ── مميِّزات س148: تشفير القاعدة المحلية (استمرارية) ────────────────────────
S148 = [
    (f"{APP}/db_key_vault.dart", "diqqah.db.key.v1"),
    (f"{STO}/db_encryption.dart", ".enc-migrate-tmp"),
    (f"{STO}/db_encryption.dart", ".preenc"),
    (f"{STO}/db_encryption.dart", "chacha20"),
    (f"{STO}/database.dart", "PRAGMA cipher = '"),
    (f"{STO}/db_encryption.dart", "بيئة القاعدة بلا دمج تشفير"),
    (f"{STO}/db_encryption.dart",
     "الترحيل أُبطل فالقاعدة النص الصريح كما هي بلا مساس"),
    (f"{STO}/db_encryption.dart",
     "تصدير الصورة الصريحة أُبطل فلا نسخة مشفرة بمفتاح جهاز"),
    (f"{STO}/db_encryption.dart", "مفتاح الخزنة ليس 64 خانة ست عشرية"),
    (f"{STO}/backup.dart",
     "صورة النسخة مشفرة بمفتاح جهاز ولا مفتاح معروف"),
    (f"{STO}/backup.dart", "الصورة ما زالت مشفرة بعد النزع"),
]

# ── مميِّزات س149: تغليف النسخ v3 وتشفير الملفات المصاحبة (استمرارية) ───────
S149 = [
    (f"{APP}/db_key_vault.dart", "diqqah.images.key.v1"),
    (f"{APP}/db_key_vault.dart", "diqqah.backup.pass.v1"),
    (f"{APP}/db_key_vault.dart", "diqqah.backup.recovery.v1"),
    (f"{STO}/file_encryption.dart", "DQIMGENC"),
    (f"{STO}/file_encryption.dart", "diqqah-images-v1"),
    (f"{STO}/file_encryption.dart",
     "مفتاح هذا الجهاز لا يفك الملف — KEK الخزنة يخالف أو الملف تالف"),
    (f"{DOM}/backup.dart",
     "النسخة مقفلة بكلمة مرور — أدخل كلمة المرور أو رمز "),
    (f"{DOM}/backup.dart",
     "كلمة المرور أو رمز الاسترداد خاطئ — تحقق ثم أعد المحاولة"),
    (f"{DOM}/backup.dart",
     "بنية النسخة المقفلة تالف — الملف غير سليم"),
    (f"{DOM}/backup.dart",
     "نوع سجل غير معروف بالنسخة المقفلة — الملف غير سليم"),
    (f"{APP}/settings_screen.dart", "قفل النسخ بكلمة مرور"),
    (f"{APP}/settings_screen.dart", "توليد رمز الاسترداد"),
    (f"{APP}/settings_screen.dart", "رمز الاسترداد — سجّله خارج الجهاز"),
    (f"{APP}/settings_screen.dart",
     "أو رمز الاسترداد على أي جهاز — فضع كلمة تعرفها وحداً"),
    (f"{STO}/backup_gfs.dart",
     "نسخة مقفلة بكلمة مرور ولا أسرار محمّلة للتحقق"),
    (f"{STO}/backup_gfs.dart",
     "نسخة مقفلة ولا أسرار محمّلة للتحقق"),
    (f"{APP}/main.dart", "ترحيل الصور للتشفير"),
]

# ── مميِّزات س150: هاش الدخول 600,000 (استمرارية) ───────────────────────────
S150 = [
    (f"{STO}/database.dart", "password_hash_iterations_upgraded"),
    (f"{STO}/database.dart", "from_iterations"),
    (f"{STO}/database.dart", "to_iterations"),
]

# ── مميِّزات س153: إحكام سجلي الأحداث والأخطاء + حاجز append-only
#    (استمرارية منذ b47) ────────────────────────────────────────────────────
S153 = [
    # لاتينية 6:
    (f"{DOM}/log_cipher.dart", "dq3log1:"),
    (f"{DOM}/log_cipher.dart", "diqqah-event-log-v1"),
    (f"{STO}/database.dart", "p3_log_salt"),
    (f"{STO}/database.dart", "trg_events_no_update"),
    (f"{STO}/database.dart", "trg_error_log_no_update"),
    (f"{APP}/diagnostics_screen.dart", "diagnostics_p3_status"),
    # عربية 8:
    (f"{DOM}/log_cipher.dart", "سجل مشفر تالف أو مُعبث به (DQ-1108)"),
    # س181: نصوص الحواجز القديمة (p3: ... append-only) استُبدلت بنصوصها
    # المرقّمة الجديدة — انتقلت بمجموعة الجديد تمييزاً لا استمرارية.
    (f"{APP}/diagnostics_screen.dart",
     "تشفير السجلات (p3): مفعّل — الحواجز 4/4 والملح قائم"),
    (f"{APP}/diagnostics_screen.dart",
     "تشفير السجلات (p3): غير مفعّل — الحواجز "),
    (f"{APP}/diagnostics_screen.dart",
     "تشفير السجلات (p3): غير مفعّل — الملح غائب"),
]

# ── مميِّزات س158: دفعة الخطوط D-212 (استمرارية منذ b48) ────────────────────
S158 = [
    (f"{APP}/ui_fonts.dart", "IBM Plex Sans Arabic"),
    (f"{APP}/ui_fonts.dart", "Noto Sans Arabic"),
    (f"{APP}/ui_fonts.dart", "Vazirmatn"),
    (f"{APP}/ui_fonts.dart", "IBMPlexSansArabic"),
    (f"{APP}/ui_fonts.dart", "NotoSansArabic"),
    (f"{APP}/settings_screen.dart",
     "خط التطبيق والطباعة"),
    (f"{APP}/settings_screen.dart",
     "الخطوط الأربعة مدمجة مع التطبيق حصراً"),
]

# ── مميِّزات س160: دفعة د0 (استمرارية منذ b49) ──────────────────────────────
S160 = [
    (f"{STO}/database.dart", "ix_move_lines_move_id"),
]

# ── مميِّزات س162: الطباعة والتنظيم والمندوب (استمرارية منذ b51) ─────────────
S162 = [
    # مفاتيح النموذج الثلاثة الجديدة بالواجهة (س162 الشطر الثاني)
    (f"{APP}/print_copies.dart", "tpl_free_header"),
    (f"{APP}/print_copies.dart", "tpl_free_footer"),
    (f"{APP}/print_copies.dart", "tpl_weights"),
    # لواحق مفاتيح التفضيلات الجديدة (print_tpl_*)
    (f"{APP}/print_copies.dart", "_free_header"),
    (f"{APP}/print_copies.dart", "_free_footer"),
    # بطاقة النصين الحرين ونِسب الأعمدة (س162 الشطر الثاني)
    (f"{APP}/print_copies.dart", "نص حر أعلى الورقة"),
    (f"{APP}/print_copies.dart", "نص حر أسفل الورقة"),
    (f"{APP}/print_copies.dart",
     "نِسب أعمدة الجدول — الأكبر وزناً أعرض عموداً"),
    # سطر شرائح العهدة وشريحة القصر (س162 المندوب)
    (f"{APP}/vouchers_screen.dart", "شرائح العهدة: "),
    (f"{APP}/vouchers_screen.dart", "تحصيلاتي"),
    # ألسنة الشرائح الأربع بالمجال (س162 المندوب — س105 بنص التوثيق)
    (f"{DOM}/voucher.dart", "حتى 7 أيام"),
    (f"{DOM}/voucher.dart", "8-15 يوماً"),
    (f"{DOM}/voucher.dart", "16-30 يوماً"),
    (f"{DOM}/voucher.dart", "فوق 30 يوماً"),
]

# ── مميِّزات س164: مسودات البيع والبوابات الخاصة والترحيلة v30
#    (استمرارية منذ b54) ─────────────────────────────────────────────────────
S164 = [
    # البوابة الفرعية ومفتاح المسودة الفوقية (س164 — الترحيلة v30)
    (f"{DOM}/permissions.dart", "invoices.post_others"),
    (f"{STO}/database.dart", "invoices.draft_over_stock"),
    # بطاقة مسودات البيع بخيارَيها (س164)
    (f"{APP}/settings_screen.dart", "مسودات البيع"),
    (f"{APP}/settings_screen.dart", "مسودات البيع تحجز الكمية"),
    # قسم «بوابات خاصة» بشاشة الأدوار (س164)
    (f"{APP}/roles_screen.dart", "بوابات خاصة"),
    (f"{APP}/roles_screen.dart",
     "الأدوار النمطية مزروعة بأذوناتها الافتراضية"),
    # نافذة «ترحيل المسودة؟» وأفعالها وإفصاح الرحّلة (س164)
    (f"{APP}/invoices_screen.dart", "ترحيل المسودة؟"),
    (f"{APP}/invoices_screen.dart", "تركها مسودة"),
    (f"{APP}/invoices_screen.dart", "ترحيل الآن"),
    (f"{APP}/invoices_screen.dart", "رُحّلت الفاتورة"),
]

# ── مميِّزات س170..س175: دفعات م4 الست (د3 الترقيم والعزل v31 ود4 المهايئ
#    PocketBase ود2 الجسر اليدوي ود5 الأرشفة والانضمام والإبطال ود6
#    المتابعات والترحيلة v32 والنافذة الواجهية) — استمرارية منذ b55
#    (انتقلت نمط أسلافها بعد b55؛ مرشّح الإصدار «0.2.3+55» حُذف نمط
#    الأسلاف) ────────────────────────────────────────────────────────────────
S170_175 = [
    # س170 (د3): العزل بالتخزين — ترحيلة v31 عمود events.company_id
    (f"{STO}/database.dart", "ALTER TABLE events ADD COLUMN company_id"),
    # س171 (د4): رمزا المهايئ بالسلطة الموحدة
    (f"{DOM}/error_codes.dart", "DQ-1113"),
    (f"{DOM}/error_codes.dart", "DQ-1114"),
    # س173 (د2): رمز الجسر بالسلطة الموحدة
    (f"{DOM}/error_codes.dart", "DQ-1115"),
    # س174 (د5): العضوية المستوردة بالتطبيق ورموزها الثلاثة
    (f"{DOM}/error_codes.dart", "DQ-1116"),
    (f"{DOM}/error_codes.dart", "DQ-1117"),
    (f"{DOM}/error_codes.dart", "DQ-1118"),
    (f"{DOM}/sync_membership.dart", "23456789ABCDEFGHJKMNPQRSTUVWXYZ"),
    (f"{DOM}/sync_membership.dart", "رمز انضمام غير سليم الشكل"),
    # س175 (د6): المتابعات اليومية ببنيها الثلاث
    (f"{DOM}/follow_ups.dart", "BelowMinimumItem"),
    (f"{DOM}/follow_ups.dart", "OverAmountCapBalance"),
    (f"{DOM}/follow_ups.dart", "OverTimeCapBalance"),
    # س175 (د6): الترحيلة v32 بعموديها
    (f"{STO}/database.dart", "ALTER TABLE items ADD COLUMN min_qty INTEGER NULL"),
    (f"{STO}/database.dart", "payment_term_days INTEGER NULL"),
    # س175 (د6): الاستعلامات الثلاثة فوق المصادر
    (f"{STO}/database.dart", "itemsBelowMinimum"),
    (f"{STO}/database.dart", "partiesOverCreditCap"),
    (f"{STO}/database.dart", "partiesOverPaymentTerm"),
    # س175 (د6): النافذة الواجهية للعمل الجماعي
    (f"{APP}/sync_work_screen.dart", "العمل الجماعي والمزامنة"),
    (f"{APP}/sync_work_screen.dart", "settings_sync_work"),
    (f"{APP}/sync_work_screen.dart", "join_code_issued"),
    (f"{APP}/sync_work_screen.dart", "sync_device_revoked"),
    # س175 (د6): خانتا الصنف والطرف الاختياريتان
    (f"{APP}/items_screen.dart", "الحد الأدنى (اختياري)"),
    (f"{APP}/parties_screen.dart", "مدة السداد بالأيام (اختياري)"),
]

# ── مميِّزات س178: بلاطة المزامنة (استمرارية منذ b56 — فتحت بس178 وسُحمت
#    بحزمة b56 فانتقلت نمط أسلافها) ─────────────────────────────────────────
S178 = [
    (f"{APP}/home_screen.dart",
     "متاحة الآن — رمز الانضمام وسجل الأجهزة وحالة الأرشفة السحابية"),
]

# ── مجموعة الجديد: مرشّح الإصدار + مميِّزات س181 (التنظيف الكامل — رموز
#    الحواجز الأربعة الجديدة وتسجيل 1123/1124 بالسلطة) ومميِّزات س182
#    (الثيم والأيقونات ومنتقي التاريخ — بطاقة المظهر ومساعدها ومفتاحا
#    الشبكة والوضع وزر التقويم) — مميِّز بالعكس على b56 حصراً (القائمة
#    مثبتة بالفحص الحي قبل التثبيت: 9 مرشحات كلها حاضرة بالمصدر وبثنائيتي
#    b57 وغائبة عن ثنائيتي b56 — المسبار scripts/probe_b57_markers.py
#    بنمط س168/س179) ─────────────────────────────────────────────────────────
S181_S182 = [
    # س181: رموز التنظيف الكامل — الحواجز الرباعية المُعادة ترميزاً والتسجيل
    (f"{DOM}/error_codes.dart", "DQ-1119"),
    (f"{DOM}/error_codes.dart", "DQ-1122"),
    (f"{DOM}/error_codes.dart", "DQ-1123"),
    (f"{DOM}/error_codes.dart", "DQ-1124"),
    # مرشّح الإصدار المحفور (مصدره الأحادي backup_center.dart — س175/س178)
    (f"{APP}/backup_center.dart", "0.2.3+57"),
    # س182: بطاقة «المظهر» بلسانها ومساعدها — الثلاثة أوضاع
    (f"{APP}/settings_screen.dart", "المظهر"),
    (f"{APP}/settings_screen.dart",
     "إعداد جهازك — التغيير فوري بلا إعادة تشغيل."),
    # س182: منتقي التاريخ بلسان نافذته
    (f"{APP}/date_picker.dart", "اختيار التاريخ"),
    # س182: مفتا الشبكة الأيقونية والوضع (ASCII يعبر المرمّز حرفاً)
    (f"{APP}/home_screen.dart", "home_modules_grid"),
    (f"{APP}/app_theme.dart", "app_theme_mode"),
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
        ("مميِّزات س149", S149, False),
        ("مميِّزات س150", S150, False),
        ("مميِّزات س153", S153, False),
        ("مميِّزات س158", S158, False),
        ("مميِّزات س160", S160, False),
        ("مميِّزات س162", S162, False),
        ("مميِّزات س164", S164, False),
        ("مميِّزات س170..س175", S170_175, False),
        ("مميِّزات س178 (استمرارية بعد b56)", S178, False),
        ("مميِّزات س181/س182 والإصدار (الجديد)", S181_S182, True),
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
                line += f" | بالمرجع b56: {'حاضرة (ليست مميزاً!)' if in_ref else 'غائبة (صادق)'}"
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
