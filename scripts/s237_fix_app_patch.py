#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س237 — مصحح s237_app_patch.py: احتساب النص قبل فتح الملف للكتابة
(الفتح ب"w" يقطع فوراً فالفشل بعد الفتح يمحو الملف) + مراسي قراءة
الخيارين الصحيحة في _load."""
import io

P = 'scripts/s237_app_patch.py'

S = io.open(P, encoding='utf-8').read()

OLD_MAIN = (
    '    s = io.open(SCREEN, encoding="utf-8").read()\n'
    '    io.open(SCREEN, "w", encoding="utf-8").write(patch_screen(s))\n'
    '    print("المحرر: حقل الصنف الفوري والسطر الحر والملاحظة")')
NEW_MAIN = (
    '    s = io.open(SCREEN, encoding="utf-8").read()\n'
    '    patched = patch_screen(s)  # يُحسب قبل الفتح — فالفتح للكتابة يقطع فوراً\n'
    '    io.open(SCREEN, "w", encoding="utf-8").write(patched)\n'
    '    print("المحرر: حقل الصنف الفوري والسطر الحر والملاحظة")')
assert OLD_MAIN in S, "main"
S = S.replace(OLD_MAIN, NEW_MAIN, 1)

OLD8 = (
    '    # ٨) قراءة الخيارين عند الفتح: نجد initState أو _loadItems الاستدعاء\n'
    '    m = re.search(r"(\\n\\s*)_loadItems\\(\\);", s)\n'
    '    assert m, "استدعاء تحميل الأصناف"\n'
    '    s = s[:m.end()] + "\\n    _loadLinePolicies();" + s[m.end():]\n'
    '\n'
    '    return s')

NEW8 = '''    # ٨) قراءة الخيارين مع قراءات _load الأولى وتعيينهما بحالتها
    old_ses = (
        "    final session = await loadSession(widget.db);\\n"
        "    if (!mounted) return;\\n"
        "    setState(() {")
    new_ses = (
        "    final session = await loadSession(widget.db);\\n"
        "    // س237 (المرحلة ج — D-235): خيارا سطور الفاتورة مع القراءات\\n"
        "    // الأولى — السطر الحر وملاحظات السطور.\\n"
        "    final freeLineAllowed = await widget.db.invoiceFreeLineAllowed();\\n"
        "    final lineNotesEnabled = await widget.db.invoiceLineNotesEnabled();\\n"
        "    if (!mounted) return;\\n"
        "    setState(() {")
    s = sub(s, old_ses, new_ses, "قراءة الخيارين")
    old_res = (
        "      _reserveEnabled = reserveOn;\\n"
        "      _reservedQty = reserved;")
    new_res = (
        "      _reserveEnabled = reserveOn;\\n"
        "      _reservedQty = reserved;\\n"
        "      // س237: الخياران مع أخويهما في الحالة.\\n"
        "      _freeLineAllowed = freeLineAllowed;\\n"
        "      _lineNotesEnabled = lineNotesEnabled;")
    s = sub(s, old_res, new_res, "تعيين الخيارين")

    return s'''

assert OLD8 in S, "old8"
S = S.replace(OLD8, NEW8, 1)

io.open(P, 'w', encoding='utf-8').write(S)
print('script fixed properly')
