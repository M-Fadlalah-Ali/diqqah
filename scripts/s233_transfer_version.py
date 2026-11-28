#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س233 — نقل الترقيم الموحد إلى 0.285.0+85 (بنمط s232_transfer_version):

الاصطفاح الرباعي مستمر بعد س231 (رقم البناء من عداد تشغيل مسار «بناء
الحزم» — آخر تشغيل b84 فالقادم b85): b85 = 0.285 = +85 = versionCode 2085.

المواضع الحية الأربعة:
  1. pubspec.yaml (version: + تعليق سطر الترقيم)
  2. kAppVersion بbackup_center.dart
  3. حارس s215_test.dart (توقعات القيمتين)
  4. تعليق كتالوج الإصدار بbackup_center.dart (سطر س233)

بأمر الخطة «الجودة والبناء → 0.285.0+85» (D-229 بوابات المرحلة أ).
"""
import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBSPEC = os.path.join(ROOT, "packages", "app", "pubspec.yaml")
BACKUP_CENTER = os.path.join(ROOT, "packages", "app", "lib", "backup_center.dart")
S215 = os.path.join(ROOT, "packages", "app", "test", "s215_test.dart")

OLD = "0.284.0+84"
NEW = "0.285.0+85"

CATALOG_COMMENT = """/// س233: الترميم الموحد 0.285.0+85 — المرحلة أ من خارطة الطريق
/// الخماسية بجولات المالك الثلاث (D-229): الأقسام الستة للإعدادات
/// بشطر الملف (D-230)، وخيارا أسماء الأشهر وأول الأسبوع بوفد ترجمة
/// حاكم على منتقي التاريخ وسطر تاريخ المطبوعات الطويل (D-231)، وبطاقة
/// النسخ الآلي بمفتاحها الرئيسي وخاناتها السبع ومرشحة المركز (D-232)،
/// وشاشة البدء المتحركة بحدّها الأدنى نصف ثانية ومؤشرا الحالة الصغيران
/// بالرئيسية (D-233) — محجوز لبناء b85 بأمر الخطة (versionCode 2085).
"""


def main():
    # ١) pubspec: السطر الحي + تعليق الترقيم
    s = io.open(PUBSPEC, encoding="utf-8").read()
    assert ("version: %s" % OLD) in s, "سطر الإصدار غير موجود"
    s = s.replace("version: %s" % OLD, "version: %s" % NEW, 1)
    s = re.sub(
        r"# التشغيل القادم b84 فالإصدار 0\.284\.0\+84 وversionCode 2084 — فالأرقام",
        "# التشغيل القادم b85 فالإصدار 0.285.0+85 وversionCode 2085 — فالأرقام",
        s, count=1)
    assert NEW in s and OLD not in s.replace("0.284.00.84", ""), "ترقيم pubspec"
    io.open(PUBSPEC, "w", encoding="utf-8").write(s)
    print("pubspec: %s" % NEW)

    # ٢) كتالوج الإصدار: الثابت + سطر السجل + تعليق س233 فوق الثابت
    s = io.open(BACKUP_CENTER, encoding="utf-8").read()
    assert ("const String kAppVersion = '%s';" % OLD) in s
    s = s.replace("const String kAppVersion = '%s';" % OLD,
                  CATALOG_COMMENT + "const String kAppVersion = '%s';" % NEW, 1)
    io.open(BACKUP_CENTER, "w", encoding="utf-8").write(s)
    print("backup_center kAppVersion: %s" % NEW)

    # ٣) حارس s215: التوقعات
    s = io.open(S215, encoding="utf-8").read()
    assert ("expect(line, 'version: %s');" % OLD) in s
    s = s.replace("expect(line, 'version: %s');" % OLD,
                  "expect(line, 'version: %s');" % NEW, 1)
    s = s.replace("expect(kAppVersion, '%s');" % OLD,
                  "expect(kAppVersion, '%s');" % NEW, 1)
    s = s.replace("الترميز الموحد %s" % OLD, "الترميم الموحد %s" % NEW, 1)
    io.open(S215, "w", encoding="utf-8").write(s)
    print("s215: %s" % NEW)

    # فحص القديم غائب
    for path in (PUBSPEC, BACKUP_CENTER, S215):
        t = io.open(path, encoding="utf-8").read()
        assert "version: %s" % OLD not in t, "بقايا ترقيم في %s" % path
    print("CLEAN — القديم غائب عن المواضع الحية الثلاثة")


if __name__ == "__main__":
    main()
