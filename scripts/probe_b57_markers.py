#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""المسبار السلبي قبل تثبيت مجموعة الجديد لـ b57 (نمط س168/س179):
كل مرشّح يجب أن يكون حاضراً بمصدر b57 وغائباً عن ثنائيتَي b56.
"""
import sys

REPO = "/home/z/my-project/diqqah"
B56 = "/tmp/verify_b57/b56"
B57 = "/tmp/verify_b57/b57"

CANDIDATES = [
    ("packages/domain/lib/src/error_codes.dart", "DQ-1119"),
    ("packages/domain/lib/src/error_codes.dart", "DQ-1122"),
    ("packages/domain/lib/src/error_codes.dart", "DQ-1123"),
    ("packages/domain/lib/src/error_codes.dart", "DQ-1124"),
    ("packages/app/lib/backup_center.dart", "0.2.3+57"),
    ("packages/app/lib/settings_screen.dart", "المظهر"),
    ("packages/app/lib/settings_screen.dart", "نظام (يتبع الجهاز)"),
    ("packages/app/lib/settings_screen.dart", "إعداد جهازك — التغيير فوري بلا إعادة تشغيل."),
    ("packages/app/lib/date_picker.dart", "اختيار التاريخ"),
    ("packages/app/lib/settings_screen.dart", "app_theme_mode"),
    ("packages/app/lib/home_screen.dart", "home_modules_grid"),
    ("packages/app/lib/app_theme.dart", "الثيم نهاري"),
]


def encodings(m):
    u8 = m.encode("utf-8")
    u16 = m.encode("utf-16-le")
    return [u8] if u16 == u8 else [u8, u16]


def present(blob, m):
    return any(e in blob for e in encodings(m))


def main():
    with open(f"{B57}/libapp.so", "rb") as f:
        a57 = f.read()
    with open(f"{B57}/app.so", "rb") as f:
        w57 = f.read()
    with open(f"{B56}/libapp.so", "rb") as f:
        a56 = f.read()
    with open(f"{B56}/app.so", "rb") as f:
        w56 = f.read()

    bad = 0
    for path, marker in CANDIDATES:
        src = open(f"{REPO}/{path}", encoding="utf-8").read()
        in_src = marker in src
        in57 = present(a57, marker) or present(w57, marker)
        in56 = present(a56, marker) or present(w56, marker)
        verdict = "سليم" if (in_src and in57 and not in56) else "مرفوض"
        if verdict == "مرفوض":
            bad += 1
        print(f"[{verdict}] {marker[:44]} | مصدر={in_src} b57={in57} b56={in56}")
    print(f"\nالحصيلة: {len(CANDIDATES)-bad}/{len(CANDIDATES)} مرشحاً سليماً")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
