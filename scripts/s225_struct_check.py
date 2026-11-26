#!/usr/bin/env python3
"""فحص بنيوي سريع لملفات دارت المعدلة (س225) — توازن الأقواس خارج
السلاسل والتعليقات، واكتشاف الغلظ قبل جولة CI. ليس محللاً كاملاً."""
import sys

FILES = [
    "packages/app/lib/empty_state.dart",
    "packages/app/lib/app_theme.dart",
    "packages/app/lib/report_table.dart",
    "packages/app/lib/reports_screen.dart",
    "packages/app/lib/home_screen.dart",
    "packages/app/lib/invoices_screen.dart",
    "packages/app/lib/vouchers_screen.dart",
    "packages/app/lib/orders_screen.dart",
    "packages/app/lib/ledger_screen.dart",
    "packages/app/lib/stock_docs_screen.dart",
    "packages/app/lib/backup_center.dart",
    "packages/app/test/s215_test.dart",
]

def check(path):
    src = open(path, encoding="utf-8").read()
    stack = []
    line = 1
    i = 0
    n = len(src)
    in_line_comment = in_block_comment = in_string = False
    quote = ''
    problems = []
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            if in_line_comment:
                in_line_comment = False
            i += 1
            continue
        if in_line_comment:
            i += 1
            continue
        if in_block_comment:
            if src.startswith('*/', i):
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if c == '\\':
                i += 2
                continue
            if c == quote:
                # لسان الاقتراب ${...} داخل السلسلة يفتح قوساً معالجاً
                if src.startswith('${', i):
                    stack.append(('{', line))
                    stack.append(('$', line))
                    i += 2
                    in_string = False
                    # نعود لمسار القوس العادي؛ إغلاق السلسلة بعده بقالب ' النهائي
                    continue
                in_string = False
            i += 1
            continue
        if src.startswith('//', i):
            in_line_comment = True
            i += 2
            continue
        if src.startswith('/*', i):
            in_block_comment = True
            i += 2
            continue
        if c in ("'", '"'):
            in_string = True
            quote = c
            i += 1
            continue
        if c in "([{":
            stack.append((c, line))
        elif c in ")]}":
            if not stack:
                problems.append(f"{path}:{line}: إغلاق بلا فتح '{c}'")
            else:
                op, ol = stack.pop()
                pairs = {'(': ')', '[': ']', '{': '}'}
                if pairs.get(op) != c:
                    problems.append(
                        f"{path}:{line}: '{c}' يقابل '{op}' من سطر {ol}")
        i += 1
    if stack:
        problems.append(f"{path}: أقواس غير مقفولة: {stack[-5:]}")
    return problems

all_probs = []
for f in FILES:
    all_probs.extend(check(f))
if all_probs:
    print("مشاكل:")
    for p in all_probs:
        print(" -", p)
    sys.exit(1)
print("CLEAN — توازن الأقواس سليم في", len(FILES), "ملفاً")
