#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س234 — رقع التنفيذ: تكثيف أزرار السجل الأربعة (عمود الأثر كان يفيض
12px فوق سطر ذي فرعية سطرين) ووحدة بذرة الاختبار باسم فريد بتاريخ
الفاتورة (اختبار الفاتورتين يبذر مرتين بقاعدة واحدة فالاسم يتصادم).
يُشغَّل مرة واحدة: السمة الحاضرة تُتخطى."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREEN = os.path.join(ROOT, "packages", "app", "lib", "invoices_screen.dart")
TEST = os.path.join(ROOT, "packages", "app", "test", "s234_test.dart")


def main():
    # ١) أزرار السجل مكتنزة — بناء قائمة جديدة (لا تعديل أثناء الدوران)
    with io.open(SCREEN, encoding="utf-8") as f:
        text = f.read()
    if "iconSize: 20," in text:
        print("أزرار السجل: مكتنزة مسبقاً — تُتخطى")
    else:
        targets = ["invoice_post_${row.id}", "invoice_view_${row.id}",
                   "invoice_print_${row.id}", "invoice_copy_${row.id}"]
        out = []
        count = 0
        for line in text.split("\n"):
            if any(("key: ValueKey('%s')," % t) in line for t in targets):
                indent = line[:len(line) - len(line.lstrip())]
                out.append(indent + "iconSize: 20,")
                out.append(indent + "visualDensity: VisualDensity.compact,")
                out.append(indent + "constraints: const BoxConstraints(")
                out.append(indent + "    minWidth: 32, minHeight: 32),")
                count += 1
            out.append(line)
        assert count == 4, "أزرار السجل: %d" % count
        with io.open(SCREEN, "w", encoding="utf-8") as f:
            f.write("\n".join(out))
        print("أزرار السجل: %d مكتنزة" % count)

    # ٢) وحدة البذرة باسم فريد
    with io.open(TEST, encoding="utf-8") as f:
        t = f.read()
    old = "      final unitId = await db.insertUnit(name: 'قطعة');"
    new = ("      // اسم فريد بتاريخ الفاتورة — اختبار الفاتورتين يبذر مرتين.\n"
           "      final unitId = await db.insertUnit(name: 'قطعة $dateText');")
    if new in t:
        print("وحدة البذرة: فريدة مسبقاً — تُتخطى")
    else:
        assert old in t, "سطر وحدة البذرة غائب"
        with io.open(TEST, "w", encoding="utf-8") as f:
            f.write(t.replace(old, new, 1))
        print("وحدة البذرة: فريدة بتاريخ الفاتورة")


if __name__ == "__main__":
    main()
