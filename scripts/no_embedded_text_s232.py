#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س232 (د12 — بوابة خروج المرحلة الأولى رقم 3): حارس النصوص المضمنة
بCI — يمنع رجوع النصوص العربية المضمنة إلى الشاشات الثلاث الكبرى،
ويمنع نموّ نصوص جديدة بغيرها فوق خط أساس مجمّد.

القاعدتان (بوابةٌ لا تفشل ليست بوابات):
  1) الشاشات الثلاث الكبرى (الفواتير والإعدادات والتقارير): صفر نصوص
     عربية مضمنة حتماً — كل نصها بفهرس l10n/strings_ar.dart حصراً.
  2) بقية ملفات packages/app/lib: لا تنمو فوق خط الأساس المجمّد
     بتاريخ 2026-11-28 (الاستخراج تدريجي بدفعات لاحقة بكلمة المالك —
     فالمنع من النمو يوقف تراكم الدين لا يلغي القائم). ومحرّك التفقيط
     (tafqit.dart) بيانات لغوية لا نصوص واجهة — خط أساسه مثبت مثله.

المحلل منقول حرفياً من محلل س198 (توازن الأقواس بفهم استيفاء Dart)
بإضافة تسجيل رموز النصوص — التعليقات لا تُحسب، والاستيفاءات المتشعبة
تُفحص كلها (نص داخل استيفاء داخل نص يُرى). والفحص على نصوص حد
packages/app/lib حصراً (بلا الاختبارات — التوقعات العربية فيها مشروعة،
وبلا l10n — الفهرس ذاته بيت النصوص).
"""
import io
import os
import re
import sys

APP_LIB = os.path.join("packages", "app", "lib")
ARABIC = re.compile(
    r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]")

ZERO = [
    "invoices_screen.dart",
    "settings_screen.dart",
    "reports_screen.dart",
]

# خط الأساس المجمّد 2026-11-28 (بعد دفعة س232): سقف العد لكل ملف.
BASELINE = {
    'app_theme.dart': 3,
    'assembly_screen.dart': 29,
    'backup_center.dart': 2,
    'backup_reminders.dart': 29,
    'backups_catalog_screen.dart': 44,
    'boxes_screen.dart': 21,
    'context_menu.dart': 2,
    'currencies_screen.dart': 63,
    'currency_display.dart': 2,
    'date_picker.dart': 6,
    'delivery_screen.dart': 33,
    'delivery_summary.dart': 13,
    'device_gate_screen.dart': 21,
    'diagnostics_screen.dart': 27,
    'drilldown.dart': 69,
    'first_run_screen.dart': 29,
    'follow_ups_screen.dart': 5,
    'gate_error_screen.dart': 7,
    'hijri_display.dart': 1,
    'home_screen.dart': 74,
    'import_screen.dart': 118,
    'input_formatters.dart': 2,
    'item_crop_screen.dart': 6,
    'item_images.dart': 2,
    'item_media.dart': 4,
    'items_screen.dart': 116,
    'ledger_screen.dart': 17,
    'list_display.dart': 1,
    'main.dart': 23,
    'native_pbkdf2.dart': 9,
    'orders_screen.dart': 162,
    'parties_screen.dart': 41,
    'periods_screen.dart': 68,
    'price_update_screen.dart': 36,
    'print_copies.dart': 48,
    'print_image_prefs.dart': 6,
    'print_service.dart': 12,
    'receivables_screen.dart': 28,
    'report_table.dart': 1,
    'restore_gate_screen.dart': 59,
    'roles_screen.dart': 36,
    'stock_counts_screen.dart': 80,
    'stock_docs_screen.dart': 36,
    'storage_manager_screen.dart': 48,
    'sync_work_screen.dart': 59,
    'tafqit.dart': 294,
    'transfers_screen.dart': 27,
    'ui_fonts.dart': 1,
    'unit_groups_screen.dart': 31,
    'users_screen.dart': 33,
    'vouchers_screen.dart': 131,
    'warehouses_screen.dart': 43,
}


class StrTok:
    def __init__(self, start, end, quote, triple, raw, parts):
        self.start = start
        self.end = end
        self.quote = quote
        self.triple = triple
        self.raw = raw
        self.parts = parts


class Lexer:
    """منقول من محلل س198 بتسجيل رموز النصوص بشجرتها."""

    def __init__(self, s):
        self.s = s
        self.i = 0
        self.n = len(s)

    def parse(self):
        toks = []
        while self.i < self.n:
            c = self.s[self.i]
            if c == "/" and self.s[self.i + 1:self.i + 2] == "/":
                self._skip_line_comment()
            elif c == "/" and self.s[self.i + 1:self.i + 2] == "*":
                self._skip_block_comment()
            elif self.s.startswith("'''", self.i) or self.s.startswith('"""', self.i):
                toks.append(self._string(self.s[self.i], triple=True, raw=False))
            elif c == "r" and self.i + 1 < self.n and self.s[self.i + 1] in ("'", '"'):
                self.i += 1
                q = self.s[self.i]
                tri = self.s.startswith(q * 3, self.i)
                toks.append(self._string(q, triple=tri, raw=True))
            elif c in ("'", '"'):
                toks.append(self._string(c, triple=False, raw=False))
            else:
                self.i += 1
        return toks

    def _skip_line_comment(self):
        while self.i < self.n and self.s[self.i] != "\n":
            self.i += 1

    def _skip_block_comment(self):
        self.i += 2
        while self.i + 1 < self.n:
            if self.s[self.i] == "*" and self.s[self.i + 1] == "/":
                self.i += 2
                return
            self.i += 1

    def _string(self, q, triple, raw):
        start = self.i - (1 if raw else 0)
        delim = q * 3 if triple else q
        self.i += len(delim)
        parts = []
        buf = []
        while True:
            if self.i >= self.n:
                raise SyntaxError("نص بلا إغلاق عند %d" % start)
            c = self.s[self.i]
            if c == "\n" and not triple:
                raise SyntaxError("نص مفرد السطر عبَر سطراً عند %d" % start)
            if not raw and c == "\\":
                buf.append(self.s[self.i:self.i + 2])
                self.i += 2
                continue
            if self.s.startswith(delim, self.i):
                if buf:
                    parts.append(("lit", "".join(buf)))
                self.i += len(delim)
                return StrTok(start, self.i, q, triple, raw, parts)
            if not raw and c == "$":
                nxt = self.s[self.i + 1] if self.i + 1 < self.n else ""
                if nxt == "{":
                    if buf:
                        parts.append(("lit", "".join(buf)))
                        buf = []
                    self.i += 2
                    inner = self._interp()
                    parts.append(("interp", self.s[start:self.i], inner))
                elif nxt.isalnum() or nxt == "_":
                    if buf:
                        parts.append(("lit", "".join(buf)))
                        buf = []
                    j = self.i + 1
                    while j < self.n and (self.s[j].isalnum() or self.s[j] == "_"):
                        j += 1
                    parts.append(("interp", self.s[self.i + 1:j], []))
                    self.i = j
                else:
                    buf.append(c)
                    self.i += 1
            else:
                buf.append(c)
                self.i += 1

    def _interp(self):
        inner = []
        depth = 1
        while depth:
            if self.i >= self.n:
                raise SyntaxError("استيفاء بلا إغلاق")
            ch = self.s[self.i]
            if ch == "\n":
                self.i += 1
            elif ch == "{":
                depth += 1
                self.i += 1
            elif ch == "}":
                depth -= 1
                self.i += 1
            elif ch in ("'", '"'):
                tri = self.s.startswith(ch * 3, self.i)
                inner.append(self._string(ch, triple=tri, raw=False))
            elif ch == "r" and self.i + 1 < self.n and self.s[self.i + 1] in ("'", '"'):
                self.i += 1
                q = self.s[self.i]
                tri = self.s.startswith(q * 3, self.i)
                inner.append(self._string(q, triple=tri, raw=True))
            elif ch == "/" and self.s[self.i + 1:self.i + 2] == "/":
                self._skip_line_comment()
            elif ch == "/" and self.s[self.i + 1:self.i + 2] == "*":
                self._skip_block_comment()
            else:
                self.i += 1
        return inner


def count_arabic(src):
    """عدّ النصوص العربية بكل الأعماق (المحتوى الحرفي حصراً)."""
    count = [0]

    def walk(toks):
        for t in toks:
            if any(p[0] == "lit" and ARABIC.search(p[1]) for p in t.parts):
                count[0] += 1
            for p in t.parts:
                if p[0] == "interp":
                    walk(p[2])

    walk(Lexer(src).parse())
    return count[0]


def main():
    problems = []
    seen = set()
    for root, dirs, files in os.walk(APP_LIB):
        dirs[:] = [d for d in dirs if d != "l10n"]
        for f in sorted(files):
            if not f.endswith(".dart"):
                continue
            rel = os.path.relpath(os.path.join(root, f), APP_LIB)
            rel = rel.replace(os.sep, "/")
            seen.add(rel)
            if rel in ZERO:
                continue
            n = count_arabic(io.open(os.path.join(root, f),
                                     encoding="utf-8").read())
            cap = BASELINE.get(rel, 0)
            if n > cap:
                problems.append(
                    "%s: نمت النصوص المضمنة إلى %d فوق خط الأساس %d —"
                    " استخرج الجديد إلى الفهرس أولاً" % (rel, n, cap))
    for rel in ZERO:
        path = os.path.join(APP_LIB, rel)
        if not os.path.exists(path):
            problems.append("%s: الشاشة غائبة عن مسارها!" % rel)
            continue
        n = count_arabic(io.open(path, encoding="utf-8").read())
        if n:
            problems.append(
                "%s: %d نصاً عربياً مضمناً — صفر حتماً بفهرس l10n" % (rel, n))
    for rel in BASELINE:
        if rel not in seen:
            problems.append("%s: بخط الأساس وغائب عن الشجرة — حدّث الحارس" % rel)
    if problems:
        print("حارس النصوص (س232): أحمر — %d علّة:" % len(problems))
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print("حارس النصوص (س232): CLEAN — الشاشات الثلاث صفراً، والبقية"
          " تحت خط الأساس (%d ملفاً بخط أساس، %d ملفاً إجمالاً)"
          % (len(BASELINE), len(seen)))


if __name__ == "__main__":
    main()
