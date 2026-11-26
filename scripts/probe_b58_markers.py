#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""المسبار السلبي قبل تثبيت مجموعة الجديد لـ b58 (نمط س168/س179/س185):
كل مرشّح يجب أن يكون حاضراً بمصدر b58 وثنائيتي b58 وغائباً عن ثنائيتَي b57.
"""
import sys

REPO = "/home/z/my-project/diqqah"
B57 = "/tmp/verify_b58/b57"
B58 = "/tmp/verify_b58/b58"

CANDIDATES = [
    # س198 م12: لافتة التنبيهات الموحدة
    ("packages/app/lib/home_screen.dart", "تنبيهات أخرى"),
    # س198 م15: منسدل أساس العد
    ("packages/app/lib/invoices_screen.dart", "أساس العد"),
    # س198 م17: كشوف الإعدادات
    ("packages/app/lib/settings_screen.dart", "كيف يعمل؟"),
    ("packages/app/lib/settings_screen.dart", "إخفاء الشرح"),
    # مرشّح الإصدار
    ("packages/app/lib/backup_center.dart", "0.2.3+58"),
    # س186 م08: نصوص التنظيف الكامل خارج السبع
    ("packages/app/lib/roles_screen.dart",
     "الأدوار النمطية مزروعة بأذوناتها الافتراضية: "),
    ("packages/app/lib/parties_screen.dart",
     "الاسم إلزامي وحده — والمطابق حرفياً لطرف قائم مرفوض"),
    ("packages/app/lib/parties_screen.dart",
     "اتركه فارغاً ليكون الطرف بلا سقف — "),
    ("packages/app/lib/currencies_screen.dart",
     "حصراً: الاسم والرمز تُملآن تلقائياً "),
    ("packages/app/lib/import_screen.dart",
     "ما لا يُستورد بهذا المسار (صراحة كاملة)"),
]


def encodings(m):
    u8 = m.encode("utf-8")
    u16 = m.encode("utf-16-le")
    return [u8] if u16 == u8 else [u8, u16]


def present(blob, m):
    return any(e in blob for e in encodings(m))


def main():
    with open(f"{B58}/libapp.so", "rb") as f:
        a58 = f.read()
    with open(f"{B58}/app.so", "rb") as f:
        w58 = f.read()
    with open(f"{B57}/libapp.so", "rb") as f:
        a57 = f.read()
    with open(f"{B57}/app.so", "rb") as f:
        w57 = f.read()

    bad = 0
    for path, marker in CANDIDATES:
        src = open(f"{REPO}/{path}", encoding="utf-8").read()
        in_src = marker in src
        in58 = present(a58, marker) or present(w58, marker)
        in57 = present(a57, marker) or present(w57, marker)
        verdict = "سليم" if (in_src and in58 and not in57) else "مرفوض"
        if verdict == "مرفوض":
            bad += 1
        print(f"[{verdict}] {marker[:44]} | مصدر={in_src} b58={in58} b57={in57}")
    print(f"\nالحصيلة: {len(CANDIDATES)-bad}/{len(CANDIDATES)} مرشحاً سليماً")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
