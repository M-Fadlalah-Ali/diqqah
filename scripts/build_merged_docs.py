#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""توليد النسخة المجمّعة لوثائق الحزمة v2.01 (D-013/D-019/D-023).

السكربت المعتمد لتوليد docs/diqqah-docs-merged-v2.01.md من الملفات
المنفصلة الإحدى عشرة في docs/diqqah-v2.01/ — الملفات المنفصلة تبقى
المرجع الوحيد وهذا الملف أرشيف قراءة يعاد توليده بعد كل تحديث.

الاستخدام:
    python3 scripts/build_merged_docs.py

التحقق المدمج:
    - 11 قسماً بمصادرها بترتيب القراءة المعلن (README ثم 01 → 10).
    - حضور قيود بطاقة الأطراف D-060..D-066 كلها.
    - حضور قرارات جولة المراجعة D-067..D-072 كلها (س28 — 2026-10-30).
    - حضور قرارات دفعة الأصناف D-073..D-075 كلها (س29 — 2026-10-30).
    - حضور قسما «1-ب إدارة الأطراف» (س-29..س-35) و«1-ج إدارة الأصناف والوحدات» (س-36..س-41).
    - حضور علامات الجولة: م1-نواة وtotal_value_minor وD-068/D-069 في 09.
    - تطابق الترويسة مع تاريخ اليوم وسلامة الكتابة بايتياً (UTF-8).
"""

from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs" / "diqqah-v2.01"
OUT = ROOT / "docs" / "diqqah-docs-merged-v2.01.md"

SOURCES = [
    "README-v2.01.md",
    "01-vision-and-scope-v2.01.md",
    "02-terminology-v2.01.md",
    "03-chart-of-accounts-v2.01.md",
    "04-srs-v2.01.md",
    "05-data-model-v2.01.md",
    "06-workflows-v2.01.md",
    "07-tryton-principles-v2.01.md",
    "08-sync-strategy-v2.01.md",
    "09-release-plan-v2.01.md",
    "10-test-plan-v2.01.md",
]

HEADER = """# «دِقَّة» (Diqqah) — الحزمة الكاملة المجمّعة — v2.01

| البند | القيمة |
|---|---|
| طبيعة هذا الملف | نسخة قراءة مجمّعة وُلِّدت آلياً من ملفات الحزمة v2.01 — وفق D-013 (نسخة مجمّعة عند الطلب) |
| المصدر الرسمي | ملفات الحزمة المنفصلة الإحدى عشرة في `diqqah-docs/` — تبقى المرجع الوحيد (D-019)؛ هذا الملف أرشيف قراءة لا يُحدَّث، وأي تحديث يُصدر في الملفات المنفصلة بإصدار جديد (D-023) ثم يعاد توليد المجمّعة |
| تاريخ التوليد | {today} |
| ترتيب الأقسام | README ثم الوثائق 01 → 10 بترتيب القراءة المعلن |

---

---

---

---

---

---

---


"""


def section(filename: str) -> str:
    content = (DOCS / filename).read_text(encoding="utf-8").rstrip("\n")
    bar = "=" * 60
    return (
        f"<!-- {bar}\n"
        f"     الملف المصدري: {filename}\n"
        f"     {bar} -->\n\n"
        f"{content}\n\n---"
    )


def main() -> None:
    parts = [section(name) for name in SOURCES]
    merged = HEADER.format(today=date.today().isoformat()) + "\n\n".join(parts) + "\n"

    # التحقق المدمج — أي فشل يوقف التوليد قبل الكتابة
    assert merged.count("<!-- " + "=" * 60) == 11, "الأقسام الإحدى عشرة"
    for d in range(60, 67):
        assert f"D-0{d}" in merged, f"قيود بطاقة الأطراف D-0{d} غائبة"
    for d in range(67, 73):
        assert f"D-0{d}" in merged, f"قرارات جولة المراجعة D-0{d} غائبة (س28)"
    for d in range(73, 76):
        assert f"D-0{d}" in merged, f"قرارات دفعة الأصناف D-0{d} غائبة (س29)"
    assert "م1-نواة" in merged and "م1-تحسينات" in merged, "تقسيم م1 (D-069)"
    assert "total_value_minor" in merged, "تصميم القيمة الإجمالية (D-067)"
    assert "1/1/2027" in merged, "موعد التدوير الحتمي (D-068)"
    assert "1-ب. إدارة الأطراف" in merged, "قسم الأطراف في 06"
    assert "1-ج. إدارة الأصناف والوحدات" in merged, "قسم الأصناف في 06 (دفعة م1 (2))"
    assert "انتقل إلى الأصناف" in merged, "أمر المالك بلفظه (س29)"
    for s in range(29, 36):
        assert f"س-{s}" in merged, f"السيناريو س-{s} غائب"
    for s in range(36, 42):
        assert f"س-{s}" in merged, f"السيناريو س-{s} غائب (دفعة الأصناف)"
    assert "معتمدة من المالك بلفظه" in merged, "حالة الاعتماد"

    OUT.write_text(merged, encoding="utf-8", newline="\n")
    size = OUT.stat().st_size
    print(f"تولد المدموج: {OUT} — {size} بايت — 11 قسماً — القيود سليمة")


if __name__ == "__main__":
    main()
