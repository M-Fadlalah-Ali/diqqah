#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""المسبار السلبي قبل تثبيت مجموعة الجديد لـ b60 (نمط س168/س179/س185/
س201/س202): كل مرشّح يجب أن يكون حاضراً بمصدر b60 وثنائيتَي b60
وغائباً عن ثنائيتَي b59.

الاستخدام:
  python3 scripts/probe_b60_markers.py \
      [--b60-dir /tmp/verify_b60/b60 --b59-dir /tmp/verify_b60/b59 \
       --repo /home/z/my-project/diqqah]
"""
import argparse
import os
import sys

REPO_DEFAULT = "/home/z/my-project/diqqah"

# مرشحات س203 — نصوص حية جديدة بكل ملف على حدة (قاعدة 1: من السطر
# الشيفري حصراً — ولا أسماء دوال: درس b39/b40).
CANDIDATES = [
    # س203 م2: الوصول السريع — الإرشاد ورسالة الحد والتثبيت والإلغاء
    ("packages/app/lib/home_screen.dart",
     "اضغط مطولاً على أي بلاطة لتثبيتها هنا — الحد أربعة"),
    ("packages/app/lib/home_screen.dart",
     "الوصول السريع أربعة كحدٍّ أقصى — ألغِ واحداً أولاً"),
    ("packages/app/lib/home_screen.dart", "ثُبّت في الوصول السريع"),
    ("packages/app/lib/home_screen.dart", "أُلغي التثبيت"),
    # س203 م5: «مردود من هذه الفاتورة» من التفصيل
    ("packages/app/lib/invoices_screen.dart", "مردود من هذه الفاتورة"),
    # س203 م4: بيانات المنشأة — البطاقة والنافذة والحفظ
    ("packages/app/lib/settings_screen.dart", "بيانات المنشأة"),
    ("packages/app/lib/settings_screen.dart",
     "حُفظت بيانات المنشأة — تظهر أول المطبوعات"),
    ("packages/app/lib/settings_screen.dart", "اسم المنشأة (إلزامي)"),
    # س203 م4: الطباعة التجارية — سطر الرقم الضريبي بالترويسة
    ("packages/app/lib/print_service.dart", "الرقم الضريبي: "),
    # مرشّح الإصدار — بالتسمية الجديدة D-213 (كلمة المالك «0.260
    # دون الإضافات الأخرى»): pubspec 0.260.0+60 وكتالوج الإصدار به حرفاً
    ("packages/app/lib/backup_center.dart", "0.260.0+60"),
]


def encodings(m):
    u8 = m.encode("utf-8")
    u16 = m.encode("utf-16-le")
    return [u8] if u16 == u8 else [u8, u16]


def present(blob, m):
    return any(e in blob for e in encodings(m))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--b60-dir", default="/tmp/verify_b60/b60")
    ap.add_argument("--b59-dir", default="/tmp/verify_b60/b59")
    ap.add_argument("--repo", default=REPO_DEFAULT)
    args = ap.parse_args()

    blobs60 = []
    for name in ("libapp.so", "app.so"):
        with open(os.path.join(args.b60_dir, name), "rb") as f:
            blobs60.append(f.read())
    blobs59 = []
    for name in ("libapp.so", "app.so"):
        with open(os.path.join(args.b59_dir, name), "rb") as f:
            blobs59.append(f.read())

    bad = 0
    for path, marker in CANDIDATES:
        src = open(os.path.join(args.repo, path), encoding="utf-8").read()
        in_src = marker in src
        in60 = any(present(b, marker) for b in blobs60)
        in59 = any(present(b, marker) for b in blobs59)
        verdict = "سليم" if (in_src and in60 and not in59) else "مرفوض"
        if verdict == "مرفوض":
            bad += 1
        print(f"[{verdict}] {marker[:44]} | مصدر={in_src} b60={in60} b59={in59}")
    print(f"\nالحصيلة: {len(CANDIDATES)-bad}/{len(CANDIDATES)} مرشحاً سليماً")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
