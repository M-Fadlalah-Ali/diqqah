#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س234 — نقل الترقيم الموحد إلى 0.286.0+86 (بنمط s233_transfer_version):

الاصطفاح الرباعي مستمر: بُني b85 فالقادم b86 (عداد مسار «بناء الحزم») —
b86 = 0.286 = +86 = versionCode 2086.

المواضع الحية الأربعة:
  1. pubspec.yaml (version: + تعليق سطر الترقيم)
  2. kAppVersion بbackup_center.dart (+ سطر سجل الس234 فوق الثابت)
  3. حارس s215_test.dart (توقعات القيمتين)
بأمر المالك «تابع بتنفيذ المرحلة ب» وبناء الخطة (D-229: 0.286 للمرحلة ب).
"""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBSPEC = os.path.join(ROOT, "packages", "app", "pubspec.yaml")
BACKUP_CENTER = os.path.join(ROOT, "packages", "app", "lib", "backup_center.dart")
S215 = os.path.join(ROOT, "packages", "app", "test", "s215_test.dart")

OLD = "0.285.0+85"
NEW = "0.286.0+86"

CATALOG_COMMENT = """/// س234: الترميم الموحد 0.286.0+86 — المرحلة ب من خارطة الطريق
/// الخماسية بجولات المالك الثلاث (D-229): سجل الفواتير بأزراره الثلاثة
/// لكل سجل (D-234/1) وأزرار تاريخه الخمسة بسطرها الصغير الفعلي وتلوين
/// المختار والتمرير الأفقي عند الضيق (D-234/2) وفلاتره الثلاثة بسطر
/// واحد بالتطبيق الفوري ومسح الفلاتر (D-234/3) — وتوثيق تأجيل د13
/// بقرار D-237 — محجوز لبناء b86 بأمر المالك (versionCode 2086).
"""


def main():
    s = io.open(PUBSPEC, encoding="utf-8").read()
    assert ("version: %s" % OLD) in s, "سطر الإصدار غير موجود"
    s = s.replace("version: %s" % OLD, "version: %s" % NEW, 1)
    s = s.replace(
        "# التشغيل القادم b85 فالإصدار 0.285.0+85 وversionCode 2085 — فالأرقام",
        "# التشغيل القادم b86 فالإصدار 0.286.0+86 وversionCode 2086 — فالأرقام",
        1)
    assert ("version: %s" % NEW) in s
    io.open(PUBSPEC, "w", encoding="utf-8").write(s)
    print("pubspec: %s" % NEW)

    s = io.open(BACKUP_CENTER, encoding="utf-8").read()
    assert ("const String kAppVersion = '%s';" % OLD) in s
    s = s.replace("const String kAppVersion = '%s';" % OLD,
                  CATALOG_COMMENT + "const String kAppVersion = '%s';" % NEW, 1)
    io.open(BACKUP_CENTER, "w", encoding="utf-8").write(s)
    print("backup_center kAppVersion: %s" % NEW)

    s = io.open(S215, encoding="utf-8").read()
    assert ("expect(line, 'version: %s');" % OLD) in s
    s = s.replace("expect(line, 'version: %s');" % OLD,
                  "expect(line, 'version: %s');" % NEW, 1)
    s = s.replace("expect(kAppVersion, '%s');" % OLD,
                  "expect(kAppVersion, '%s');" % NEW, 1)
    s = s.replace("الترميم الموحد %s" % OLD, "الترميم الموحد %s" % NEW, 1)
    if "الترميم الموحد %s" % NEW not in s:
        # س233 كتبت «الترميم» بلا ميم؟ — مرساة أوسع احتياطاً
        s = s.replace("الموحد %s" % OLD, "الموحد %s" % NEW, 1)
    io.open(S215, "w", encoding="utf-8").write(s)
    print("s215: %s" % NEW)

    for path in (PUBSPEC, BACKUP_CENTER, S215):
        t = io.open(path, encoding="utf-8").read()
        assert ("version: %s" % OLD) not in t and "'%s'" % OLD not in t, \
            "بقايا ترقيم في %s" % path
    print("CLEAN — القديم غائب عن المواضع الحية الثلاثة")


if __name__ == "__main__":
    main()
