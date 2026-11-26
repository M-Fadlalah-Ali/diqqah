#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""المسبار السلبي قبل تثبيت مجموعة الجديد لـ b59 (نمط س168/س179/س185/س201):
كل مرشّح يجب أن يكون حاضراً بمصدر b59 وثنائيتَي b59 وغائباً عن ثنائيتَي b58.

الاستخدام:
  python3 scripts/probe_b59_markers.py \
      [--b59-dir /tmp/verify_b59/b59 --b58-dir /tmp/verify_b59/b58 \
       --repo /home/z/my-project/diqqah]
"""
import argparse
import os
import sys

REPO_DEFAULT = "/home/z/my-project/diqqah"

# مرشحات س202 — نصوص حية جديدة بكل ملف على حدة (قاعدة 1: من السطر
# الشيفري حصراً — ولا أسماء دوال: درس b39/b40).
CANDIDATES = [
    # س202 م2: بلاطتا الجهة بلسان مرحلتيهما
    ("packages/app/lib/home_screen.dart",
     "فواتير البيع ومردودها بفلتر جهتهما"),
    ("packages/app/lib/home_screen.dart",
     "فواتير الشراء ومردودها بفلتر جهتهما"),
    # س202 م2: مجموعتا الجهة بمنسدل الأرشيف
    ("packages/app/lib/invoices_screen.dart", "بيعي (البيع ومردوده)"),
    ("packages/app/lib/invoices_screen.dart", "شرائي (الشراء ومردوده)"),
    # س202 م2: لسان شارة النوع بعد المسار الجديد
    ("packages/app/lib/invoices_screen.dart",
     "النوع يُحدد من زر الدخول — لا مبدّل هنا"),
    # مرشّح الإصدار
    ("packages/app/lib/backup_center.dart", "0.2.3+59"),
]


def encodings(m):
    u8 = m.encode("utf-8")
    u16 = m.encode("utf-16-le")
    return [u8] if u16 == u8 else [u8, u16]


def present(blob, m):
    return any(e in blob for e in encodings(m))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--b59-dir", default="/tmp/verify_b59/b59")
    ap.add_argument("--b58-dir", default="/tmp/verify_b59/b58")
    ap.add_argument("--repo", default=REPO_DEFAULT)
    args = ap.parse_args()

    blobs59 = []
    for name in ("libapp.so", "app.so"):
        with open(os.path.join(args.b59_dir, name), "rb") as f:
            blobs59.append(f.read())
    blobs58 = []
    for name in ("libapp.so", "app.so"):
        with open(os.path.join(args.b58_dir, name), "rb") as f:
            blobs58.append(f.read())

    bad = 0
    for path, marker in CANDIDATES:
        src = open(os.path.join(args.repo, path), encoding="utf-8").read()
        in_src = marker in src
        in59 = any(present(b, marker) for b in blobs59)
        in58 = any(present(b, marker) for b in blobs58)
        verdict = "سليم" if (in_src and in59 and not in58) else "مرفوض"
        if verdict == "مرفوض":
            bad += 1
        print(f"[{verdict}] {marker[:44]} | مصدر={in_src} b59={in59} b58={in58}")
    print(f"\nالحصيلة: {len(CANDIDATES)-bad}/{len(CANDIDATES)} مرشحاً سليماً")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
