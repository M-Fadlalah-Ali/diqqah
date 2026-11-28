#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س233 — إضافة مفاتيح نصوص الدفعة إلى فهرس l10n/strings_ar.dart:
مفاتيح شاشة البدء ومؤشرات الرئيسية (قسم جديد) ومفاتيح الإعدادات
(ضمن قسمها، بإدراج ألفبائي) — القيم حرفاً من نص الخطة وقرارها D-231
وD-232 وD-233. يعمل مرة واحدة: المفتاح الموجود يُتخطى بلا تكرار."""
import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "packages", "app", "lib", "l10n", "strings_ar.dart")

# قسم جديد: شاشة البدء والرئيسية (س233 — D-233)
SPLASH_HOME_SECTION = """
  // ===== شاشة البدء والرئيسية (س233 — D-233 المرحلة أ/4) =====
  static const String homeBackupActive = 'النسخ الآلي: يعمل';
  static const String homeBackupFailed = 'فشلت آخر نسخة آلية';
  static const String homeBackupPaused = 'النسخ الآلي: متوقف';
  static const String homeSyncActive = 'المزامنة: مفعلة';
  static const String splashAppName = 'دِقَّة';
  static const String splashStageAppDir = 'تهيئة مجلد التطبيق';
  static const String splashStageLegacyAdopt = 'تبني قاعدة الجيل السابق';
  static const String splashStageLogRootVault =
      'حمل جذر السجلات وفتح الخزنة';
  static const String splashStageOpenDatabase =
      'فتح قاعدة البيانات وترقية المخطط — أول فتح بعد التحديث يستغرق '
      'وقتاً أطول مرة واحدة (تحسين المخطط والفهارس)';
  static const String splashStageSetupCheck = 'فحص التهيئة';
  static const String splashStageUpgradeSnapshot =
      'لقطة الأمان قبل ترقية المخطط';
"""

# مفاتيح قسم الإعدادات الجديدة (س233 — D-230/D-231/D-232)
SETTINGS_KEYS = [
    ("autoBackupAdvanced", "  static const String autoBackupAdvanced = "
     "'خيارات متقدمة';"),
    ("autoBackupDaily", "  static const String autoBackupDaily = 'يومي';"),
    ("autoBackupDueNow", "  static const String autoBackupDueNow = "
     "'مستحقة الآن — لحاق الدخول';"),
    ("autoBackupFirstDailyHint", "  static const String "
     "autoBackupFirstDailyHint = 'عند التفعيل تُنشأ أول نسخة يومية عند "
     "الدخول إلزاماً';"),
    ("autoBackupHourly", "  static const String autoBackupHourly = "
     "'ساعي';"),
    ("autoBackupLastSuccess", "  static String autoBackupLastSuccess("
     "Object? p1) => 'آخر نسخة ناجحة: ${p1}';"),
    ("autoBackupMonthly", "  static const String autoBackupMonthly = "
     "'شهري';"),
    ("autoBackupNextDue", "  static String autoBackupNextDue(Object? p1) "
     "=> 'الموعد القادم: ${p1}';"),
    ("autoBackupOffWarning", "  static const String autoBackupOffWarning "
     "= 'النسخ الآلي متوقف — لا تُنشأ نسخ تلقائية حتى تفعيله';"),
    ("autoBackupQuota", "  static String autoBackupQuota(Object? p1, "
     "Object? p2) => 'الحصة: ${p1} من ${p2}';"),
    ("autoBackupTitle", "  static const String autoBackupTitle = "
     "'النسخ الآلي';"),
    ("autoBackupWeekly", "  static const String autoBackupWeekly = "
     "'أسبوعي';"),
    ("autoBackupWorksWhileRunning", "  static const String "
     "autoBackupWorksWhileRunning = 'يعمل أثناء تشغيل التطبيق';"),
    ("autoBackupYearly", "  static const String autoBackupYearly = "
     "'سنوي عند إقفال السنة';"),
    ("backupRestoreTitle", "  static const String backupRestoreTitle = "
     "'النسخ والاستعادة';"),
    ("monthNamesInternational", "  static const String "
     "monthNamesInternational = 'دولية';"),
    ("monthNamesLabel", "  static const String monthNamesLabel = "
     "'أسماء الأشهر';"),
    ("monthNamesShami", "  static const String monthNamesShami = "
     "'شامية';"),
    ("securitySessionTitle", "  static const String securitySessionTitle "
     "= 'الأمان والجلسة';"),
    ("weekStartLabel", "  static const String weekStartLabel = "
     "'أول الأسبوع';"),
    ("weekStartMonday", "  static const String weekStartMonday = "
     "'الاثنين';"),
    ("weekStartSaturday", "  static const String weekStartSaturday = "
     "'السبت';"),
    ("weekStartSunday", "  static const String weekStartSunday = "
     "'الأحد';"),
]

KEY_RE = re.compile(r"^\s*static (?:const )?String ([A-Za-z0-9_]+)")


def main():
    text = io.open(PATH, encoding="utf-8").read()
    if "splashAppName" in text:
        print("مفاتيح س233 موجودة مسبقاً — تُتخطى")
        return

    # ١) القسم الجديد قبل إغلاق الصنف مباشرة (آخر قسم هو التقارير).
    closing = text.rindex("}")
    text = text[:closing].rstrip() + "\n" + SPLASH_HOME_SECTION + "}\n"
    print("قسم شاشة البدء والرئيسية: أُضيف")

    # ٢) مفاتيح الإعدادات — إدراج ألفبائي داخل قسمها (بين ترويسة
    #    الإعدادات وترويسة التقارير أو إغلاق القسم الجديد).
    lines = text.split("\n")
    sec_start = None
    sec_end = None
    for i, line in enumerate(lines):
        if "===== الإعدادات" in line:
            sec_start = i
        elif sec_start is not None and line.strip().startswith("// ====="):
            sec_end = i
            break
    if sec_start is None:
        raise SystemExit("قسم الإعدادات غير موجود بالفهرس")
    if sec_end is None:
        sec_end = len(lines)

    block = lines[sec_start:sec_end]
    existing = set()
    for line in block:
        m = KEY_RE.match(line)
        if m:
            existing.add(m.group(1))

    for (name, decl) in SETTINGS_KEYS:
        if name in existing:
            continue
        inserted = False
        for i, line in enumerate(block):
            m = KEY_RE.match(line)
            if m and m.group(1) > name:
                block.insert(i, decl)
                inserted = True
                break
        if not inserted:
            block.append(decl)
        existing.add(name)

    text = "\n".join(lines[:sec_start] + block + lines[sec_end:])
    io.open(PATH, "w", encoding="utf-8").write(text)
    print("مفاتيح الإعدادات الجديدة: %d مفتاحاً أُدرجت ألفبائياً"
          % len(SETTINGS_KEYS))


if __name__ == "__main__":
    main()
