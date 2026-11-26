#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""التحقق البايتي البنائي داخل تشغيل «بناء الحزم» — البند ⑤ (س168).

المنهجية الموثقة (نمط verify_bNN — دروس السجل):
  1. العلامة تُستخرج من السطر الشيفري حصراً: كل علامة موقّفة على ملفها
     بالمصدر وتُتحقق حرفياً فيه قبل البحث بالثنائي (درس b39/b40 — المرمّز
     يسقط الأسماء النقية فلا تعليقات ولا أسماء دوال).
  2. نصوص AOT العربية تُخزن UTF-16LE فالبحث بالترميزين معاً (درس b31).
  3. الإصدار يُقرأ من pubspec.yaml لحظة الفحص (مصدر واحد للحقيقة —
     علة س163 الموثقة: كتالوج الإصدار الشيفري اختل عن pubspec فصار هذا
     الفحص حارساً بنائياً — أي اختلاف يُسقط التشغيل أحمر بلا صمت).

ما يفحصه (على الثنائي المبني الواحد — يُستدعى من مهام أندرويد وويندوز في
build.yml بعد البناء):
  أ. مرشّح الإصدار الكامل من pubspec (مثل 0.2.3+50): يجب أن يُوجد حرفياً
     في مصدر الواجهة (كتالوج الإصدار) ثم في الثنائي بالترميزين.
  ب. أساس الاستمرارية الدائم: علامات قائمة لن تنتقل (سطور شيفرة حية
     تمثل بوابات ومعرفات لا تتغير بكل دفعة) — حضورها بالثنائي إثبات
     أن الثنائي يحمل الشيفرة نفسها.

الحد الصادق: هذه الأداة حارس مستمر لا أداة حقبة — الأداة الكاملة
للحقبة (المميِّز بالعكس على المرجع الأحدث) تُجدد عند كل بناء نمط
verify_b51_markers.py وتجرى محلياً على الأثرتين النازلتين.

الاستخدام:
  python3 scripts/verify_build_markers.py --binary <الثنائي> \
      --label <اسم> [--repo <مسار المستودع>]
"""

import argparse
import glob
import os
import sys

# درس التشغيل 53 الموثق: بايثون الويندوز يطبع بcp1252 فانهار على الطباعة
# العربية قبل أي تحقق (UnicodeEncodeError) — والمتحقق لا يفشل إلا على
# علاماته لا على تجميل مخرجاته فالضبط هنا: utf-8 مع تعويض الداخلي.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO_DEFAULT = "/home/z/my-project/diqqah"
APP = "packages/app/lib"
DOM = "packages/domain/lib/src"
STO = "packages/storage/lib/src"

# ── أساس الاستمرارية الدائم (سطور شيفرة حية لا تنتقل بكل دفعة) ──────────────
# س202: علامة «طلبات الشراء والبيع» انتقلت تثبيتاً من home_screen إلى
# orders_screen (بلاطتها صارت «الطلبات» بأمر المالك وعنوان شاشة الأوامر
# الكامل باقٍ حرفاً) — ونمط الانتقال الموثق: العلامة تُستبدل بلسانها
# الجديد الحي بالشيفرة.
DURABLE = [
    (f"{APP}/gate_error_screen.dart", "GateErrorScreen"),
    (f"{APP}/home_screen.dart", "معطلة"),
    (f"{APP}/home_screen.dart", "الطلبات"),
    (f"{APP}/orders_screen.dart", "طلبات الشراء والبيع"),
    (f"{STO}/database.dart", "snapshotBeforeUpgrade"),
    (f"{STO}/database.dart", "ix_move_lines_move_id"),
    (f"{STO}/database.dart", "invoices.draft_over_stock"),
    (f"{DOM}/permissions.dart", "invoices.post_others"),
    (f"{APP}/print_copies.dart", "tpl_weights"),
    (f"{APP}/ui_fonts.dart", "IBM Plex Sans Arabic"),
]


def read_version(repo: str) -> str:
    """يقرأ الإصدار الكامل من pubspec.yaml (مصدر واحد للحقيقة)."""
    pub = os.path.join(repo, "packages", "app", "pubspec.yaml")
    with open(pub, encoding="utf-8") as f:
        for line in f:
            if line.startswith("version:"):
                v = line.split("version:", 1)[1].strip()
                if not v:
                    break
                return v
    print("فشل: سطر version غير موجود في packages/app/pubspec.yaml")
    sys.exit(2)


def encodings(marker: str):
    """البحث بالترميزين معاً (درس b31: العربية UTF-16LE بالثنائي)."""
    utf8 = marker.encode("utf-8")
    utf16 = marker.encode("utf-16-le")
    return [utf8] if utf16 == utf8 else [utf8, utf16]


def found(blob: bytes, marker: str) -> bool:
    return any(v in blob for v in encodings(marker))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", required=True)
    ap.add_argument("--label", default="الثنائي")
    ap.add_argument("--repo", default=REPO_DEFAULT)
    args = ap.parse_args()

    with open(args.binary, "rb") as f:
        blob = f.read()

    version = read_version(args.repo)
    print(f"الإصدار من pubspec: {version} — الثنائي: {args.label} "
          f"({len(blob)} بايت)")

    failures = 0
    total = 0

    # أ. مرشّح الإصدار: يجب أن يُوجد حرفياً بمصدر الواجهة (كتالوج
    #    الإصدار) ثم بالثنائي — علة س163 حارساً بنائياً.
    hits = sorted(
        p for p in glob.glob(os.path.join(args.repo, APP, "**", "*.dart"),
                             recursive=True)
        if version in open(p, encoding="utf-8").read()
    )
    total += 1
    if not hits:
        print(f"فشل: مرشّح الإصدار {version} غائب عن مصدر الواجهة كله — "
              f"كتالوج الإصدار اختل عن pubspec (علّة س163) "
              f"فالتشغيل يُسقط فوراً بلا استكمال")
        return 1
    else:
        rel = [os.path.relpath(p, args.repo) for p in hits]
        ok_bin = found(blob, version)
        status = "حاضرة بالثنائي" if ok_bin else "غائبة عن الثنائي"
        print(f"[الإصدار] {version}: بالمصدر {rel} — {status}")
        if not ok_bin:
            failures += 1
        total += 1
        # الإصدار الأساسي (قبل +) من pubspec نفسه
        base = version.split("+")[0]
        ok_base = found(blob, base)
        print(f"[الإصدار الأساسي] {base}: "
              f"{'حاضرة بالثنائي' if ok_base else 'غائبة عن الثنائي'}")
        if not ok_base:
            failures += 1

    # ب. أساس الاستمرارية الدائم.
    for file_path, marker in DURABLE:
        src = os.path.join(args.repo, file_path)
        with open(src, encoding="utf-8") as f:
            text = f.read()
        if marker not in text:
            print(f"فشل: العلامة «{marker}» غير موجودة بالمصدر {file_path}")
            sys.exit(2)
        total += 1
        ok = found(blob, marker)
        print(f"[الأساس] {marker}: "
              f"{'حاضرة بالثنائي' if ok else 'غائبة عن الثنائي'}")
        if not ok:
            failures += 1

    print(f"\nالحصيلة ({args.label}): {total - failures}/{total} علامة سليمة")
    if failures:
        print(f"فشل: {failures} علامة — التشغيل يُسقط أحمر (لا سكوت)")
        return 1
    print("CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
