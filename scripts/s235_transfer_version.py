#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س235 — نقل الترقيم الموحد إلى 0.287.0+87 (بنمط s234_transfer_version):

الاصطفاح الرباعي مستمر: بُني b86 فالقادم b87 — b87 = 0.287 = +87 =
versionCode 2087. المواضع الحية الثلاثة: pubspec وكتالوج الإصدار
(kAppVersion بسطر سجل الس235 فوقه) وحارس s215."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBSPEC = os.path.join(ROOT, "packages", "app", "pubspec.yaml")
BACKUP_CENTER = os.path.join(ROOT, "packages", "app", "lib", "backup_center.dart")
S215 = os.path.join(ROOT, "packages", "app", "test", "s215_test.dart")

OLD = "0.286.0+86"
NEW = "0.287.0+87"

CATALOG_COMMENT = """/// س235: الترميم الموحد 0.287.0+87 — توحيد النمط الفوري على الشاشات
/// (بكلمة المالك «نعم احذف زر العرض وطبق النمط الجديد لتوحيد تجربة
/// المستخدم»): شريط المدى الفوري الموحد DiqqahInstantRangeBar (أزرار
/// التاريخ الخمسة بسطورها الصغيرة وحقلا من/إلى بديبونس وحرس زوج)
/// بسجل الفواتير والتقارير (الدخل واليومية والحركة) والسندات —
/// والميزانية بحقلها الأحادي الفوري — وقرار القصير ISO موثق D-238 —
/// محجوز لبناء b87 بأمر المالك (versionCode 2087).
"""


def main():
    s = io.open(PUBSPEC, encoding="utf-8").read()
    assert ("version: %s" % OLD) in s, "سطر الإصدار غير موجود"
    s = s.replace("version: %s" % OLD, "version: %s" % NEW, 1)
    s = s.replace(
        "# التشغيل القادم b86 فالإصدار 0.286.0+86 وversionCode 2086 — فالأرقام",
        "# التشغيل القادم b87 فالإصدار 0.287.0+87 وversionCode 2087 — فالأرقام",
        1)
    assert ("version: %s" % NEW) in s
    io.open(PUBSPEC, "w", encoding="utf-8").write(s)
    print("pubspec: %s" % NEW)

    s = io.open(BACKUP_CENTER, encoding="utf-8").read()
    old_decl = "const String kAppVersion = '%s';" % OLD
    assert old_decl in s
    # إزالة تعليق سجل س234 السابق (حلقة واحدة) ووضع سجل س235
    idx = s.index(old_decl)
    head = s[:idx]
    # التعليق السابق ينتهي بسطر محجوز… — نجد بدايته (سطر «/// س234:»)
    prev_start = head.rindex("/// س234:")
    head = head[:prev_start]
    s = head + CATALOG_COMMENT + old_decl.replace(OLD, NEW) + s[idx + len(old_decl):]
    io.open(BACKUP_CENTER, "w", encoding="utf-8").write(s)
    print("backup_center kAppVersion: %s" % NEW)

    s = io.open(S215, encoding="utf-8").read()
    for a, b in [
        ("expect(line, 'version: %s');" % OLD, "expect(line, 'version: %s');" % NEW),
        ("expect(kAppVersion, '%s');" % OLD, "expect(kAppVersion, '%s');" % NEW),
        ("%s" % OLD, "%s" % NEW),
    ]:
        s = s.replace(a, b)
    assert OLD not in s
    io.open(S215, "w", encoding="utf-8").write(s)
    print("s215: %s" % NEW)

    for path in (PUBSPEC, BACKUP_CENTER, S215):
        t = io.open(path, encoding="utf-8").read()
        assert OLD not in t, "بقايا ترقيم في %s" % path
    print("CLEAN — القديم غائب عن المواضع الحية الثلاثة")


if __name__ == "__main__":
    main()
