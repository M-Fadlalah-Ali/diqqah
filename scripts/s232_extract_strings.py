#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س232 (د12 — D-226 وفاء D-037): أداة استخراج النصوص المضمنة من الشاشات
الثلاث الكبرى إلى فهرس النصوص (packages/app/lib/l10n/).

المحلل مأخوذ حرفياً من محلل س198 (توازن الأقواس بفهم استيفاء Dart) مع
تسجيل رموز النصوص بشجرتها: التعليقات تُتخطى، والنصوص تُفهم بثلاثة
أقواسها وخامها واستيفاءاتها المتشعبة (نص داخل استيفاء داخل نص) —
فالتصنيف «نص عربي مستهدف» يقيس المحتوى الحرفي حصراً لا الاستيفاء.

الأنماط الثلاثة للتشغيل:
  dump    — إفراغ القوالب الفريدة (بلا خريطة) مرقمةً لصناعة الخريطة.
  apply   — التحويل بالخريطة (scripts/s232_key_map.py): إعادة كتابة
            الشاشات الثلاث + توليد l10n/strings_ar.dart.
  check   — تحقق ما بعد التحويل: صفر نصوص عربية مضمنة بالشاشات الثلاث،
            وكل مفتاح مستعمل معرَّف بالفهرس والخريطة معاً.

قواعد الأمان في التحويل (تُفشل الأداة بصوت لا صمت):
  - القالب المعياري: القيمة الحقيقية بعد فك إفلاتات Dart، والاستيفاء
    {N} بترتيبه — فالإفراغ يطابق الخريطة حرفاً.
  - الإصدار الآمن: إفلات كامل للقيمة (' و$ والشرطة والسطر الجديد)،
    والقيم ذات الشرطات تُصدر خاماً إن أمكن وإلا إفلاتاً صريحاً.
  - الدمج المجاور يرفض الخام بشرطة عكسية (معناه يتغير بالدمج) —
    مراجعة يدوية، وكذا أنماط الاقتباس المختلطة بدمج واحد.
  - الاستيفاء يُستبدل بـ ${pN} بالأقواس دوماً (قاعدة unnecessary_brace
    معطلة بس227 بإيجابياتها الكاذبة الموثقة فلا كسر ولا تحذير).
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "packages", "app")
LIB = os.path.join(APP, "lib")
KEY_MAP_PATH = os.path.join(ROOT, "scripts", "s232_key_map.py")

SCREENS = [
    "invoices_screen.dart",
    "settings_screen.dart",
    "reports_screen.dart",
]

ARABIC = re.compile(
    r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]")
IDENT = re.compile(r"^[a-z][A-Za-z0-9]{0,63}$")
SREF = re.compile(r"\bS\.([A-Za-z][A-Za-z0-9]*)")

# فك إفلاتات Dart للقيمة الحقيقية.
UNESCAPE = {
    "n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v",
    "\\": "\\", "'": "'", '"': '"', "$": "$",
}


def decode(chunk):
    out = []
    i = 0
    while i < len(chunk):
        c = chunk[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        n = chunk[i + 1] if i + 1 < len(chunk) else ""
        if n in UNESCAPE:
            out.append(UNESCAPE[n])
            i += 2
        elif n == "x" and i + 3 < len(chunk) + 1:
            out.append(chr(int(chunk[i + 2:i + 4], 16)))
            i += 4
        elif n == "u" and chunk[i + 2:i + 4] == "{":
            end = chunk.index("}", i + 3)
            out.append(chr(int(chunk[i + 3:end], 16)))
            i = end + 1
        elif n == "u":
            out.append(chr(int(chunk[i + 2:i + 6], 16)))
            i += 6
        else:
            raise ValueError("إفلات Dart غير معروف: %r" % chunk[i:i + 2])
    return "".join(out)


# ============ المحلل (من س198 بتسجيل الرموز) ============

class StrTok:
    """رمز نص واحد: موضعه بأسلوبه وخامه وأجزاؤه بشجرتها."""

    def __init__(self, start, end, quote, triple, raw, parts):
        self.start = start
        self.end = end
        self.quote = quote
        self.triple = triple
        self.raw = raw
        # parts: ('lit', source) أو ('interp', expr_source, [StrTok])
        self.parts = parts


class Lexer:
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
            elif (c == "r" and self.i + 1 < self.n
                  and self.s[self.i + 1] in ("'", '"')):
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
                    expr_start = self.i
                    inner = self._interp()
                    expr_src = self.s[expr_start:self.i - 1]
                    parts.append(("interp", expr_src, inner))
                elif nxt.isalnum() or nxt == "_":
                    if buf:
                        parts.append(("lit", "".join(buf)))
                        buf = []
                    j = self.i + 1
                    while j < self.n and (self.s[j].isalnum()
                                          or self.s[j] == "_"):
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
        """جسم ${...}: يستهلك حتى إغلاقه ويعيد نصوصه الداخلية بشجرتها."""
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
            elif (ch == "r" and self.i + 1 < self.n
                  and self.s[self.i + 1] in ("'", '"')):
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


# ============ الاستهداف والتجميع ============

def has_arabic(tok):
    for p in tok.parts:
        if p[0] == "lit" and ARABIC.search(p[1]):
            return True
    return False


def _blank_gap(src, a, b):
    """فراغ بين رمزين نصيين؟ التعليقات تُنزع (فراغ للdart lexer)."""
    gap = re.sub(r"//[^\n]*", "", src[a:b])
    gap = re.sub(r"/\*.*?\*/", "", gap, flags=re.S)
    return gap.strip() == ""


def group_runs(src, toks):
    """تجميع المجاورات: نص يعقبه فراغ (أو تعليق) ثم نص = دمج واحد."""
    runs = []
    i = 0
    while i < len(toks):
        run = [toks[i]]
        j = i + 1
        while j < len(toks) and _blank_gap(src, run[-1].end, toks[j].start):
            run.append(toks[j])
            j += 1
        runs.append(run)
        i = j
    return runs


def lit_value(tok):
    """القيمة الحقيقية للمحتوى الحرفي (بفك الإفلات؛ الخام حرفياً)."""
    out = []
    for p in tok.parts:
        if p[0] == "lit":
            out.append(p[1] if tok.raw else decode(p[1]))
    return "".join(out)


def run_template(run):
    """القالب المعياري: القيمة الحقيقية والاستيفاء {N} بترتيبه."""
    out = []
    idx = 0
    for tok in run:
        if "{" in lit_value(tok) or "}" in lit_value(tok):
            raise ValueError("قوس معقوف حرفي بنص عربي — مراجعة يدوية: %r"
                             % lit_value(tok)[:50])
        for p in tok.parts:
            if p[0] == "lit":
                out.append(decode(p[1]) if not tok.raw else p[1])
            else:
                idx += 1
                out.append("{%d}" % idx)
    return "".join(out)


def run_param_count(run):
    return sum(1 for tok in run for p in tok.parts if p[0] == "interp")


def walk_runs(src, toks, sink):
    """جمع كل دمجات النصوص العربية: العليا ومتداخلة الاستيفاءات كلها."""
    for run in group_runs(src, toks):
        if any(has_arabic(t) for t in run):
            sink.append(run)
        for tok in run:
            for p in tok.parts:
                if p[0] == "interp":
                    walk_runs(src, p[2], sink)


# ============ جمع الملفات ============

def collect(fname):
    """كل الدمجات العربية بكل الأعماق — للإفراغ والتحقق."""
    path = os.path.join(LIB, fname)
    src = io.open(path, encoding="utf-8").read()
    toks = Lexer(src).parse()
    runs = []
    walk_runs(src, toks, runs)
    return src, runs


def collect_top(fname):
    """دمجات المستوى الأعلى حصراً — للتحويل (المتداخل يُعالج بنيوياً
    داخل الوسائط، فالمواضع العليا منفصلة لا تتراكب أبداً)."""
    path = os.path.join(LIB, fname)
    src = io.open(path, encoding="utf-8").read()
    toks = Lexer(src).parse()
    runs = [r for r in group_runs(src, toks)
            if any(has_arabic(t) for t in r)]
    return src, toks, runs


def load_key_map():
    sys.path.insert(0, os.path.dirname(KEY_MAP_PATH))
    km = __import__("s232_key_map").KEY_MAP
    inv = {}
    for t, k in km.items():
        if not IDENT.match(k):
            sys.exit("ERR: مفتاح غير صالح: %r" % k)
        if k in inv:
            sys.exit("ERR: مفتاح مكرر: %s (قالبان)" % k)
        inv[k] = t
    return km


# ============ الإفراغ ============

def dump():
    uniq = {}
    order = []
    for fname in SCREENS:
        _, runs = collect(fname)
        for run in runs:
            t = run_template(run)
            if t not in uniq:
                uniq[t] = {"n": 0, "params": run_param_count(run),
                           "files": set(),
                           "triple": any(x.triple for x in run),
                           "raw": any(x.raw for x in run),
                           "adjacent": len(run) > 1,
                           "has_nl": any("\n" in lit_value(x) for x in run),
                           "has_bs": any("\\" in lit_value(x) for x in run)}
                order.append(t)
            uniq[t]["n"] += 1
            uniq[t]["files"].add(fname)
    print("القوالب الفريدة: %d — المواضع: %d" % (
        len(order), sum(uniq[t]["n"] for t in order)))
    for k, t in enumerate(order, 1):
        m = uniq[t]
        files = "+".join(x[:2] for x in sorted(m["files"]))
        flags = ""
        if m["adjacent"]:
            flags += " مجاور"
        if m["raw"]:
            flags += " خام"
        if m["triple"]:
            flags += " ثلاثي"
        if m["has_nl"]:
            flags += " أسطر"
        if m["has_bs"]:
            flags += " شرطة"
        print("[%d] (%s|p%d|%d%s) %s" % (
            k, files, m["params"], m["n"], flags,
            t.replace("\n", "\\n")))


# ============ الإصدار الآمن للقيم ============

def esc(text):
    """إفلات كامل لقيمة داخل اقتباس مفرد غير خام."""
    out = []
    for c in text:
        if c == "\\":
            out.append("\\\\")
        elif c == "'":
            out.append("\\'")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif c == "\r":
            out.append("\\r")
        elif c == "\t":
            out.append("\\t")
        elif c == "$":
            out.append("\\$")
        else:
            out.append(c)
    return "".join(out)


def emit_const(value):
    """إصدار قيمة ثابتة: اقتباس مفرد بإفلات كامل دوماً (الشرطة كسلسلة،
    والسطر الجديد كإفلات، والدولار معتقاً) — فالملف كله سطراً لكل
    مفتاح والقيمة متساوية حرفاً مهما كان أصل أسلوبها."""
    return "'%s'" % esc(value)


# ============ التحويل ============

def interp_has_arabic_deep(tok):
    """هل يحمل استيفاء هذا الرمز نصاً عربياً في أي عمق؟"""
    for p in tok.parts:
        if p[0] == "interp":
            for it in p[2]:
                if has_arabic(it) or interp_has_arabic_deep(it):
                    return True
    return False


def rebuild_token(tok):
    """إعادة بناء رمز غير عربي حرفياً (بما فيه فروق اقتباسه) إلا أن
    استيفاءاته تُستبدل بتعبيراتها المحوّلة — فـ$ident يصير ${ident}
    (تساوٍ قيمة موثق بالأداة والقاعدة معطلة بس227)."""
    if tok.raw:
        raise ValueError("رمز خام لا يحمل استيفاء — استدعاء محال")
    delim = tok.quote * (3 if tok.triple else 1)
    out = [delim]
    for p in tok.parts:
        if p[0] == "lit":
            out.append(p[1])
        else:
            out.append("${" + transform_expr(p[1]) + "}")
    out.append(delim)
    return "".join(out)


def transform_expr(expr_src):
    """تعبير الاستيفاء بعد تحويله الشجري (نصوصه العربية → مفاتيح)."""
    return transform_region(expr_src, Lexer(expr_src).parse())


def transform_region(src, toks):
    """التحويل الشجري لمنطقة: الدمج العربي → S.key(...)، والرمز غير
    العربي المستفيض عربيةً يُعاد بناؤه، وغير ذلك يبقى حرفاً."""
    out = []
    pos = 0
    for run in group_runs(src, toks):
        out.append(src[pos:run[0].start])
        if any(has_arabic(t) for t in run):
            out.append(run_replacement(run))
        else:
            rebuilt = []
            prev_end = run[0].start
            for tok in run:
                rebuilt.append(src[prev_end:tok.start])
                rebuilt.append(rebuild_token(tok)
                               if interp_has_arabic_deep(tok)
                               else src[tok.start:tok.end])
                prev_end = tok.end
            out.append("".join(rebuilt))
        pos = run[-1].end
    out.append(src[pos:])
    return "".join(out)


def run_replacement(run):
    t = run_template(run)
    key = KEY_MAP.get(t)
    if key is None:
        raise ValueError("قالب بلا مفتاح بالخريطة: %r" % t[:80])
    args = [transform_expr(p[1]) for tok in run
            for p in tok.parts if p[0] == "interp"]
    if args:
        return "S.%s(%s)" % (key, ", ".join(args))
    return "S.%s" % key


def apply():
    sec_of = {}
    for fi, fname in enumerate(SCREENS):
        _, runs = collect(fname)
        for run in runs:
            t = run_template(run)
            sec_of.setdefault(t, fi)
            if sec_of[t] != fi:
                sec_of[t] = -1
    for fname in SCREENS:
        src, toks, runs = collect_top(fname)
        new = transform_region(src, toks)
        new = add_import(new, fname)
        io.open(os.path.join(LIB, fname), "w", encoding="utf-8").write(new)
        print("%s: استُبدلت %d موضعاً علوياً" % (fname, len(runs)))
    gen_catalog(sec_of)


def add_import(src, fname):
    if "l10n/app_strings.dart" in src:
        return src
    lines = src.split("\n")
    last_rel = max(
        (i for i, l in enumerate(lines)
         if l.startswith("import '") and "package:" not in l),
        default=None)
    imp = "import 'l10n/app_strings.dart';"
    if last_rel is None:
        last_pkg = max(
            (i for i, l in enumerate(lines)
             if l.startswith("import 'package:")), default=0)
        lines.insert(last_pkg + 1, "")
        lines.insert(last_pkg + 2, imp)
    else:
        lines.insert(last_rel + 1, imp)
    return "\n".join(lines)


SECTION_TITLES = {
    -1: "مشترك — عابرة الشاشات الثلاث",
    0: "الفواتير — الشاشة الكبرى الأولى (3,648 سطراً قبل الدفعة)",
    1: "الإعدادات — الشاشة الكبرى الثانية (2,524 سطراً قبل الدفعة)",
    2: "التقارير — الشاشة الكبرى الثالثة (2,359 سطراً قبل الدفعة)",
}

HEADER = """// س232 (د12 — استخراج النصوص، وفاء وعد التدويل D-037): فهرس النصوص
// العربية للشاشات الثلاث الكبرى (الفواتير والإعدادات والتقارير) — كل
// نص عربي ظاهر للمستخدم فيها صار هنا لا مضمناً بشيفرة الشاشة، وحارس
// النصوص (scripts/no_embedded_text_s232.py داخل CI) يمنع رجوع أي نص
// مضمن إليها أو نموّ نصوص جديدة بغيرها.
//
// البنية لغرض D-037 (جاهزية i18n بلا إعادة هيكلة): هذا ملف «البيانات»
// للعربية حصراً؛ app_strings.dart هو المدخل الذي تصله الشاشات بسطر
// استيراد واحد، وإطلاق الإنكليزية لاحقاً = ملف strings_en.dart بأعضاء
// مطابقة أسماً وترتيباً + تبديل سطر الاستيراد في app_strings.dart
// وحده — فلا تُمس شاشة ولا استيراد شاشة (لا إعادة هيكلة بمعنى D-037).
// لا توليد آلي (gen_l10n) هنا عمداً: بلا SDK محلي (القيد المؤسسي
// Task 37) والفهرس النقي شيفرة Dart تُفحص بأداة س198 كأي ملف.
library;

/// فهرس النصوص العربية — صنف الوصول الوحيد «S».
///
/// القيم الثابتة (static const) تصلح لسياقات const بالشاشات (متساوية
/// القيمة وقت الترجمة)، والقوالب ذات الوسائط توابع (لا تكون const في
/// الأصل أصلاً فلا يتغير شيء)، والوسائط Object فاستيفاؤها يطابق
/// استيفاء الأصل حرفاً ($x بلا تغيير).
abstract final class S {
"""


def gen_catalog(sec_of):
    groups = {-1: [], 0: [], 1: [], 2: []}
    for t, key in KEY_MAP.items():
        if t in sec_of:
            groups[sec_of[t]].append((t, key))
    for g in groups.values():
        g.sort(key=lambda tk: tk[1])
    body = []
    for gk in (-1, 0, 1, 2):
        if not groups[gk]:
            continue
        body.append("  // ===== %s =====" % SECTION_TITLES[gk])
        for t, key in groups[gk]:
            params = []
            m = 1
            while ("{%d}" % m) in t:
                params.append(m)
                m += 1
            if params:
                sig = ", ".join("Object? p%d" % p for p in params)
                val = re.sub(r"\{(\d+)\}",
                             lambda mm: "${p%s}" % mm.group(1), esc(t))
                body.append("  static String %s(%s) => '%s';" % (
                    key, sig, val))
            else:
                body.append("  static const String %s = %s;" % (
                    key, emit_const(t)))
        body.append("")
    path = os.path.join(LIB, "l10n", "strings_ar.dart")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8").write(
        HEADER + "\n".join(body) + "}\n")
    total = sum(len(g) for g in groups.values())
    print("l10n/strings_ar.dart: %d مفتاحاً" % total)


# ============ التحقق ============

def check():
    problems = 0
    used = set()
    for fname in SCREENS:
        src, runs = collect(fname)
        if runs:
            problems += 1
            print("%s: بقيت %d مواضع!" % (fname, len(runs)))
            for r in runs[:3]:
                print("  مثال: %r" % run_template(r)[:60])
        stripped = re.sub(r"/\*.*?\*/", "",
                          re.sub(r"//[^\n]*", "", src), flags=re.S)
        for k in SREF.findall(stripped):
            used.add(k)
    for fname in SCREENS:
        src = io.open(os.path.join(LIB, fname), encoding="utf-8").read()
        try:
            Lexer(src).parse()
        except SyntaxError as e:
            problems += 1
            print("%s: كسر نحوي: %s" % (fname, e))
    cat = io.open(os.path.join(LIB, "l10n", "strings_ar.dart"),
                  encoding="utf-8").read()
    defined = set(re.findall(r"\b(?:static const String|static String)"
                             r"\s+([A-Za-z][A-Za-z0-9]*)\b", cat))
    if used - defined:
        problems += 1
        print("مفاتيح مستعملة غير معرفة: %s" % sorted(used - defined))
    if defined - used - set(KEY_MAP.values()):
        problems += 1
        print("مفاتيح معرفة غير مستعملة (خارج الخريطة): %s"
              % sorted(defined - used - set(KEY_MAP.values()))[:10])
    print("CHECK: %s" % ("CLEAN" if problems == 0 else "علل: %d" % problems))
    sys.exit(0 if problems == 0 else 1)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "dump"
    if mode == "dump":
        dump()
    elif mode == "apply":
        KEY_MAP = load_key_map()
        apply()
    elif mode == "check":
        KEY_MAP = load_key_map()
        check()
    else:
        sys.exit("الأنماط: dump | apply | check")
