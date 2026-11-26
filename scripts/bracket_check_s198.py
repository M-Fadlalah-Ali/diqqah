#!/usr/bin/env python3
# س198 — الفحص المكتبي لدفعة م12..م17: توازن الأقواس بفهم استيفاء
# Dart المتشعب (نمط أداة س186 الموثقة بسجل العمل) — بلا Flutter محلياً
# فالحكم النهائي بCI حصراً، وهذا الفحص حاجز مكتبي قبل الدفع.
# الاستخدام: python3 scripts/bracket_check_s198.py file1.dart file2.dart ...
import sys

OPEN = {'(': ')', '[': ']', '{': '}'}
CLOSE = {')': '(', ']': '[', '}': '{'}


class Checker:
    def __init__(self, s, name):
        self.s = s
        self.name = name
        self.i = 0
        self.n = len(s)
        self.stack = []
        self.line = 1

    def err(self, msg):
        print(f'{self.name}: BREAK عند السطر {self.line}: {msg}')
        sys.exit(1)

    def skip_line_comment(self):
        while self.i < self.n and self.s[self.i] != '\n':
            self.i += 1

    def skip_block_comment(self):
        self.i += 2
        while self.i + 1 < self.n:
            if self.s[self.i] == '\n':
                self.line += 1
            if self.s[self.i] == '*' and self.s[self.i + 1] == '/':
                self.i += 2
                return
            self.i += 1
        self.err('تعليق كتلي بلا إغلاق')

    def string(self, q, triple, raw=False):
        delim = q * 3 if triple else q
        self.i += len(delim)
        while True:
            if self.i >= self.n:
                self.err('نص بلا إغلاق')
            c = self.s[self.i]
            if c == '\n':
                if not triple:
                    self.err('نص مفرد السطر عبَر سطراً')
                self.line += 1
                self.i += 1
                continue
            if not raw and c == '\\':
                self.i += 2
                continue
            if self.s.startswith(delim, self.i):
                self.i += len(delim)
                return
            if not raw and c == '$':
                nxt = self.s[self.i + 1] if self.i + 1 < self.n else ''
                if nxt == '{':
                    self.i += 2
                    self.interpolation()
                elif nxt.isalnum() or nxt == '_':
                    while self.i + 1 < self.n and (
                            self.s[self.i + 1].isalnum()
                            or self.s[self.i + 1] == '_'):
                        self.i += 1
                    self.i += 1
                else:
                    self.i += 1
            else:
                self.i += 1

    def interpolation(self):
        depth = 1
        while depth:
            if self.i >= self.n:
                self.err('استيفاء بلا إغلاق')
            ch = self.s[self.i]
            if ch == '\n':
                self.line += 1
                self.i += 1
            elif ch == '{':
                depth += 1
                self.i += 1
            elif ch == '}':
                depth -= 1
                self.i += 1
            elif ch in ('\'', '"'):
                if self.s.startswith(ch * 3, self.i):
                    self.string(ch, triple=True)
                else:
                    self.string(ch, triple=False)
            elif ch == '/' and self.s[self.i + 1:self.i + 2] == '/':
                self.skip_line_comment()
            elif ch == '/' and self.s[self.i + 1:self.i + 2] == '*':
                self.skip_block_comment()
            else:
                self.i += 1

    def run(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c == '\n':
                self.line += 1
                self.i += 1
            elif c == '/' and self.s[self.i + 1:self.i + 2] == '/':
                self.skip_line_comment()
            elif c == '/' and self.s[self.i + 1:self.i + 2] == '*':
                self.skip_block_comment()
            elif self.s.startswith("'''", self.i) or self.s.startswith('"""', self.i):
                self.string(self.s[self.i], triple=True)
            elif (c == 'r' and self.i + 1 < self.n
                  and self.s[self.i + 1] in ('\'', '"')):
                self.i += 1
                self.string(self.s[self.i], triple=False, raw=True)
            elif c in ('\'', '"'):
                self.string(c, triple=False)
            elif c in OPEN:
                self.stack.append((OPEN[c], self.line))
                self.i += 1
            elif c in CLOSE:
                if not self.stack:
                    self.err(f'إغلاق غير مفتوح {c}')
                want, ln = self.stack.pop()
                if want != c:
                    self.err(f'تداخل الأقواس: فُتح بالسطر {ln} توقع {want} وجد {c}')
                self.i += 1
            else:
                self.i += 1
        if self.stack:
            self.err(f'أقواس بلا إغلاق: {self.stack[-5:]}')
        print(f'{self.name}: CLEAN ({self.line} سطراً)')


def main():
    files = sys.argv[1:]
    if not files:
        print('لا ملفات معطاة')
        sys.exit(2)
    for f in files:
        with open(f, encoding='utf-8') as fh:
            Checker(fh.read(), f).run()
    print(f'المجموع: {len(files)} ملفاً CLEAN')


if __name__ == '__main__':
    main()
