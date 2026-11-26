#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة الدفعة س225 — تحقق الترميز الموحد 0.277.0+77 (نمط
s221/s223_transfer_version): المواضع الثلاثة الحية متفقاً حرفاً —
pubspec.yaml وكتالوج الإصدار backup_center.dart وحارس س215 — والفشل
بوابة لا صمت."""
import io
import sys

PUBSPEC = "packages/app/pubspec.yaml"
CATALOG = "packages/app/lib/backup_center.dart"
GUARD = "packages/app/test/s215_test.dart"

VERSION = "0.277.0+77"

ok = True

pub = io.open(PUBSPEC, encoding="utf-8").read()
line = next(l for l in pub.splitlines() if l.startswith("version:"))
if line.strip() != f"version: {VERSION}":
    print(f"pubspec: {line.strip()!r} لا يساوي version: {VERSION}")
    ok = False

cat = io.open(CATALOG, encoding="utf-8").read()
if f"const String kAppVersion = '{VERSION}';" not in cat:
    print(f"backup_center: ثابت الإصدار ليس {VERSION}")
    ok = False

guard = io.open(GUARD, encoding="utf-8").read()
if f"version: {VERSION}" not in guard or f"'{VERSION}'" not in guard:
    print(f"s215_test: حارس الترميز غير محدّث إلى {VERSION}")
    ok = False

print("CLEAN — الترميز الموحد " + VERSION) if ok else sys.exit(1)
