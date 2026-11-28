#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س237 — المرحلة ج (D-235): رقعة واجهة محرر الفاتورة —
حقل الصنف الكتابي الفوري باقتراحات (Enter يثبت وينتقل للكمية ويجهز
سطراً تالياً) + نافذة الصنف غير الموجود (بطاقة صنف / صنف حر / إلغاء)
+ السطر الحر الموسوم بصرياً + ملاحظة السطر القابلة للتوسيع + خانتا
سياسات البيع — والبحث السريع متعدد الإدراج والباركود كما هما."""
import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, "packages", "app", "lib", "l10n", "strings_ar.dart")
SALES = os.path.join(ROOT, "packages", "app", "lib", "settings", "sales_section.dart")
SCREEN = os.path.join(ROOT, "packages", "app", "lib", "invoices_screen.dart")


def sub(s, old, new, where):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    return s.replace(old, new, 1)


L10N_KEYS = {
    'addNewItemCard': "  static const String addNewItemCard = 'إضافة بطاقة صنف';",
    'changeItemTooltip': "  static const String changeItemTooltip = 'تغيير الصنف';",
    'freeLineBadge': "  static const String freeLineBadge = 'سطر حر — بلا صنف ولا حركة مخزون';",
    'freeLineDescriptionLabel': "  static const String freeLineDescriptionLabel = 'وصف السطر الحر (إلزامي)';",
    'insertFreeLine': "  static const String insertFreeLine = 'إدراج صنف حر';",
    'itemNotFoundTitle': "  static const String itemNotFoundTitle = 'الصنف غير موجود';",
    'itemSearchHelper': "  static const String itemSearchHelper = 'اكتب ثم Enter لتثبيت أعلى المطابقات — أو اختر من الاقتراحات';",
    'itemSearchLabel': "  static const String itemSearchLabel = 'الصنف — اكتب الاسم أو الرمز';",
    'itemSkuRequired': "  static const String itemSkuRequired = 'رمز الصنف (إلزامي)';",
    'lineNoteLabel': "  static const String lineNoteLabel = 'ملاحظة السطر';",
    'lineNotesSettingBody': "  static const String lineNotesSettingBody = 'ملاحظة قصيرة لكل سطر بحقل صغير قابل للتوسيع — بيان سطر خالص لا أثر له بالقيد';",
    'lineNotesSettingTitle': "  static const String lineNotesSettingTitle = 'ملاحظات السطور بالفواتير';",
    'quickItemPriceLabel': "  static const String quickItemPriceLabel = 'سعر البيع (بوحدة صغرى)';",
    'salePriceInvalid': "  static const String salePriceInvalid = 'سعر البيع موجب إلزاماً';",
    'skuRequiredError': "  static const String skuRequiredError = 'رمز الصنف إلزامي';",
    'invoiceLinesCardTitle': "  static const String invoiceLinesCardTitle = 'سطور الفاتورة';",
    'freeLineSettingBody': "  static const String freeLineSettingBody = 'سطر بوصف وسعر يدوي بلا صنف ولا حركة مخزون — يدخل من نافذة الصنف غير الموجود عند البحث الصريح';",
    'freeLineSettingTitle': "  static const String freeLineSettingTitle = 'السطر الحر بالفواتير';",
}


def patch_l10n(s):
    if 'itemSearchLabel' in s:
        print("l10n: موجودة مسبقاً")
        return s
    anchor = "  // ===== البنوك (س236 — د10) ====="
    assert anchor in s
    section = "  // ===== سطور الفاتورة (س237 — المرحلة ج D-235) =====\n" + \
        "\n".join(sorted(L10N_KEYS.values()))
    return s.replace(anchor, section + "\n\n" + anchor, 1)


SALES_CARD = '''
        // ── س237 (المرحلة ج — D-235): بطاقة سطور الفاتورة — خانتا
        // سياسات البيع: السطر الحر وملاحظات السطور. ──
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(S.invoiceLinesCardTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(S.freeLineSettingTitle),
                  subtitle: Text(S.freeLineSettingBody),
                  value: _freeLine,
                  onChanged: (v) async {
                    await widget.db.setInvoiceFreeLineAllowed(v);
                    if (!mounted) return;
                    setState(() => _freeLine = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(S.lineNotesSettingTitle),
                  subtitle: Text(S.lineNotesSettingBody),
                  value: _lineNotes,
                  onChanged: (v) async {
                    await widget.db.setInvoiceLineNotesEnabled(v);
                    if (!mounted) return;
                    setState(() => _lineNotes = v);
                  },
                ),
              ],
            ),
          ),
        ),
'''


def patch_sales(s):
    if '_freeLine' in s:
        print("sales_section: مرقع مسبقاً")
        return s
    s = sub(s, """  Future<void> _loadHeldReserve() async {
    final on = await widget.db.heldInvoicesReserveQty();
    final over = await widget.db.invoiceDraftOverStock();
    if (!mounted) return;
    setState(() {
      _heldReserve = on;
      _draftOverStock = over;
    });
  }""",
            """  Future<void> _loadHeldReserve() async {
    final on = await widget.db.heldInvoicesReserveQty();
    final over = await widget.db.invoiceDraftOverStock();
    // س237 (المرحلة ج): خانتا سطور الفاتورة تُقرآن معهما.
    final free = await widget.db.invoiceFreeLineAllowed();
    final notes = await widget.db.invoiceLineNotesEnabled();
    if (!mounted) return;
    setState(() {
      _heldReserve = on;
      _draftOverStock = over;
      _freeLine = free;
      _lineNotes = notes;
    });
  }""",
            "تحميل الخيارات")
    s = sub(s, """  bool _draftOverStock = false;""",
            """  bool _draftOverStock = false;

  /// س237 (المرحلة ج — D-235): خانتا سطور الفاتورة — السطر الحر
  /// وملاحظات السطور (تقرؤهما شاشة التحرير فور فتحها).
  bool _freeLine = false;
  bool _lineNotes = false;""",
            "حقول الخيارين")
    # البطاقة بعد بطاقة المسودات (نلحقها قبل نهاية قائمة بناء القسم)
    m = re.search(r"(\n\s*)\]\s*,?\s*\n\s*\}\s*,\s*\n\s*\]\s*,?\s*\n\s*\}\s*,?\s*\n\}", s)
    if not m:
        # نبسط: نجد آخر Card( في البناء وندرج بعده
        m = re.search(r"(\n)(\s*)Card\(", s)
        assert m, "بنية القسم"
    # ندرج البطاقة قبل آخر عنصر بقائمة children: نجد آخر Card وأقواسه
    # الأسلوب الأمين: ندخل البطاقة بعد بطاقة المسودات — نجدها بعنوانها
    anchor = re.search(r"\n(\s*)// ── س164: بطاقة مسودات البيع", s)
    if not anchor:
        # نجعل الإدراج قبل إغلاق children بآخر Card
        anchor2 = re.search(r"\n(\s*)\]\s*\n(\s*)\),\n(\s*)\);\n\}", s)
        assert anchor2, "إغلاق البناء"
        s = s[:anchor2.start()] + SALES_CARD + s[anchor2.start():]
    else:
        s = s[:anchor.start()] + SALES_CARD + s[anchor.start():]
    return s


ITEM_DROPDOWN_RE = re.compile(
    r"            DropdownButtonFormField<int>\(\n"
    r"              initialValue: line\.itemId,\n"
    r"              isExpanded: true,\n"
    r"              decoration: const InputDecoration\(labelText: S\.itemLabel\),\n"
    r"              onTap: \(\) \{\n"
    r"                // س-119/D-114: النقر على الصنف يحدّث المتاح أولاً كي\n"
    r"                // لا تُعرض خريطة قديمة إن رُحّلت فاتورة والنموذج مفتوح\.\n"
    r"                _reloadStock\(\);\n"
    r"              \},\n"
    r"(?:.*?\n)*?"
    r"              onChanged: \(value\) => setState\(\(\) \{\n"
    r"                line\.itemId = value;\n"
    r"                line\.unitLevelId = null; // صنف آخر يعيد الوحدة للأساسية\n"
    r"                _fillDefaultPrice\(line\); // س-108: السعر الافتراضي يُعبأ\n"
    r"              \}\),\n"
    r"            \),\n", re.S)

NEW_ITEM_FIELD = """            // س237 (D-235 — المرحلة ج/حقل الصنف): الكتابة الفورية
            // داخل السطر بالاسم أو الرمز باقتراحات فورية — وEnter يثبت
            // أعلى المطابقات وينتقل للكمية ويجهز سطراً تالياً، والصريح
            // الغائب يفتح نافذة الصنف غير الموجود (خياراتها الثلاثة) —
            // والبحث السريع متعدد الإدراج والباركود كما هما.
            if (line.isFree)
              TextField(
                controller: line.description,
                decoration: const InputDecoration(
                    labelText: S.freeLineDescriptionLabel,
                    helperText: S.freeLineBadge),
                onSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(line.qtyFocus),
              )
            else if (line.itemId == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: line.itemQuery,
                    decoration: const InputDecoration(
                        labelText: S.itemSearchLabel,
                        helperText: S.itemSearchHelper),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _onItemQuerySubmitted(index),
                  ),
                  if (_itemSuggestions(line).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final it in _itemSuggestions(line))
                            ActionChip(
                              label: Text(
                                '${it.sku} ${it.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _fixItemLine(index, it),
                            ),
                        ],
                      ),
                    ),
                ],
              )
            else
              InputDecorator(
                decoration: InputDecoration(
                  labelText: S.itemLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: S.changeItemTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      line.itemId = null;
                      line.unitLevelId = null;
                      line.itemQuery.clear();
                    }),
                  ),
                ),
                child: Text(
                  '${_itemOf(line.itemId)!.sku} ${_itemOf(line.itemId)!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
"""

LINE_METHODS = '''
  /// س237: اقتراحات الصنف الفورية — تطابق الاسم أو الرمز احتواءً،
  /// خمسة أولاً (بترتيب المعرف — الأقدم أسهل الوصول).
  List<ItemRow> _itemSuggestions(_LineUi line) {
    final q = line.itemQuery.text.trim();
    if (q.isEmpty) return const [];
    final ql = q.toLowerCase();
    return _items
        .where((it) =>
            it.name.toLowerCase().contains(ql) ||
            it.sku.toLowerCase().contains(ql))
        .take(5)
        .toList();
  }

  /// س237: Enter يثبت الصنف — أعلى المطابقات، والغائب يفتح النافذة.
  void _onItemQuerySubmitted(int index) {
    final line = _lines[index];
    final s = _itemSuggestions(line);
    if (s.isNotEmpty) {
      _fixItemLine(index, s.first);
    } else {
      _itemNotFoundDialog(index);
    }
  }

  /// س237: تثبيت الصنف — ينتقل للكمية ويجهز سطراً تالياً إن كان
  /// الأخير (D-235: Enter يثبت وينتقل ويجهز).
  void _fixItemLine(int index, ItemRow it) {
    final line = _lines[index];
    setState(() {
      line.itemId = it.id;
      line.unitLevelId = null;
      line.itemQuery.clear();
      _fillDefaultPrice(line);
    });
    if (index == _lines.length - 1) _addLineFocused();
    FocusScope.of(context).requestFocus(line.qtyFocus);
  }

  /// س237: نافذة الصنف غير الموجود — عند البحث الصريح حصراً: إضافة
  /// بطاقة صنف (الاسم معبأ) أو إدراج صنف حر (إن نافذ خيار سياسات
  /// البيع) أو إلغاء (D-235).
  Future<void> _itemNotFoundDialog(int index) async {
    final line = _lines[index];
    final typed = line.itemQuery.text.trim();
    if (typed.isEmpty) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${S.itemNotFoundTitle}: $typed'),
        children: [
          SimpleDialogOption(
            value: 'card',
            child: Text(S.addNewItemCard),
          ),
          if (_freeLineAllowed)
            SimpleDialogOption(
              value: 'free',
              child: Text(S.insertFreeLine),
            ),
          SimpleDialogOption(
            value: 'cancel',
            child: Text(S.cancelLabel),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return;
    if (choice == 'free') {
      setState(() {
        line.isFree = true;
        line.description.text = typed;
        line.itemId = null;
        line.unitLevelId = null;
        line.itemQuery.clear();
      });
      FocusScope.of(context).requestFocus(line.qtyFocus);
      return;
    }
    await _quickItemCardDialog(index, typed);
  }

  /// س237: بطاقة الصنف السريعة — الاسم معبأ من البحث، والرمز إلزامي،
  /// وسعر البيع اختياري — تصنع الصنف وتثبته في السطر فوراً.
  Future<void> _quickItemCardDialog(int index, String typed) async {
    final sku = TextEditingController();
    final price = TextEditingController();
    addTearDown(sku.dispose);
    addTearDown(price.dispose);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.addNewItemCard),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: TextEditingController(text: typed)..readOnly = true,
              decoration: const InputDecoration(labelText: S.itemNameLabel),
            ),
            TextField(
              controller: sku,
              decoration: const InputDecoration(labelText: S.itemSkuRequired),
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: S.quickItemPriceLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(S.cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(S.saveLabel),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    final sale = parseGroupedInt(price.text.trim());
    final skuText = sku.text.trim();
    if (skuText.isEmpty) {
      setState(() => _saveError = [S.skuRequiredError]);
      return;
    }
    try {
      final firstUnit = (await widget.db.customSelect(
              'SELECT id FROM units WHERE is_deleted = 0 ORDER BY id LIMIT 1')
          .getSingle()).data['id'] as int;
      final id = await widget.db.insertItem(
        sku: skuText,
        name: typed,
        kind: 'good',
        baseUnitId: firstUnit,
        purchasePriceMinor: 0,
        salePriceMinor: sale,
        priceCurrencyId: 1,
      );
      await _loadItems();
      if (!mounted) return;
      _fixItemLine(index, _items.firstWhere((it) => it.id == id));
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.quick_item');
      if (!mounted) return;
      setState(() => _saveError = ['$e${dqTag(e)}']);
    }
  }

'''


def patch_screen(s):
    if 'itemQuery' in s:
        print("المحرر: مرقع مسبقاً")
        return s
    # ١) _LineUi: الحقول الجديدة
    s = sub(s, """class _LineUi {
  int? itemId;""",
            """class _LineUi {
  int? itemId;

  /// س237 (D-235 — المرحلة ج): السطر الحر — بوصفه وسعره اليدوي ولا
  /// صنف له ولا حركة مخزون (موسوم بصرياً ببطاقته).
  bool isFree = false;

  /// س237: كتابة الصنف الفورية — الاستعلام الحي بالاسم أو الرمز.
  final TextEditingController itemQuery = TextEditingController();
  final TextEditingController description = TextEditingController();
  final TextEditingController note = TextEditingController();
  final FocusNode itemFocus = FocusNode();

  /// س237: ملاحظة السطر — حقل صغير قابل للتوسيع.
  bool noteVisible = false;""",
            "حقول _LineUi")
    s = sub(s, """  void dispose() {
    qty.dispose();
    price.dispose();
    discount.dispose();
    qtyFocus.dispose();
    priceFocus.dispose();
    discountFocus.dispose();
  }""",
            """  void dispose() {
    qty.dispose();
    price.dispose();
    discount.dispose();
    qtyFocus.dispose();
    priceFocus.dispose();
    discountFocus.dispose();
    // س237: كتابة الصنف والوصف والملاحظة مع السطر.
    itemQuery.dispose();
    description.dispose();
    note.dispose();
    itemFocus.dispose();
  }""",
            "تنظيف _LineUi")

    # ٢) خيارا السياسات يقرآن عند الفتح
    s = sub(s, """  void _addLineFocused() {""",
            """  /// س237 (D-235): خانتا سياسات البيع — السطر الحر وملاحظات
  /// السطور تقرآن عند فتح النموذج.
  bool _freeLineAllowed = false;
  bool _lineNotesEnabled = false;

  Future<void> _loadLinePolicies() async {
    final free = await widget.db.invoiceFreeLineAllowed();
    final notes = await widget.db.invoiceLineNotesEnabled();
    if (!mounted) return;
    setState(() {
      _freeLineAllowed = free;
      _lineNotesEnabled = notes;
    });
  }

  void _addLineFocused() {""",
            "خيارا السياسات")

    # ٣) المسودة من السطور: الحرة والملاحظة
    s = sub(s, """        InvoiceLineDraft(
          itemId: l.itemId ?? 0,
          unitId: _baseUnitIdOf(l.itemId) ?? 0,""",
            """        InvoiceLineDraft(
          // س237: السطر الحر بلا صنف — صفر توكيدياً (المجمعات
          // تجريه والخطة تتخطاه) ووصفه وملاحظته مع السطر.
          itemId: l.isFree ? 0 : (l.itemId ?? 0),
          unitId: l.isFree ? 0 : (_baseUnitIdOf(l.itemId) ?? 0),""",
            "مسودة: الصنف صفر للحر")
    s = sub(s, """          unitPriceMinor: _parsed(l.price),
          discountMinor: _parsed(l.discount),
        ),
    ];""",
            """          unitPriceMinor: _parsed(l.price),
          discountMinor: _parsed(l.discount),
          isFree: l.isFree,
          description: l.isFree ? l.description.text : null,
          note: l.note.text.trim().isEmpty ? null : l.note.text.trim(),
        ),
    ];""",
            "مسودة: الحرة والملاحظة")

    # ٤) حقل الصنف: القائمة المنسدلة تصير الكتابة الفورية
    m = ITEM_DROPDOWN_RE.search(s)
    assert m, "كتلة قائمة الصنف غير موجودة"
    s = s[:m.start()] + NEW_ITEM_FIELD + s[m.end():]

    # ٥) الطرق الجديدة قبل _lineCard
    s = sub(s, "  Widget _lineCard(int index) {",
            LINE_METHODS + "  Widget _lineCard(int index) {",
            "موضع الطرق")

    # ٦) الملاحظة: حقل قابل للتوسيع بعد صف الكمية/السعر/الخصم —
    # ندرجه قبل زر الحذف (نجد زر الحذف للسطر)
    s = sub(s, """                IconButton(
                  tooltip: S.deleteLine,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _lines.length <= 1""",
            """                // س237 (D-235): ملاحظة السطر — حقل صغير قابل
                // للتوسيع (خيار سياسات البيع).
                if (_lineNotesEnabled)
                  IconButton(
                    tooltip: S.lineNoteLabel,
                    icon: Icon(line.noteVisible
                        ? Icons.sticky_note_2
                        : Icons.sticky_note_2_outlined),
                    onPressed: () => setState(
                        () => line.noteVisible = !line.noteVisible),
                  ),
                IconButton(
                  tooltip: S.deleteLine,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _lines.length <= 1""",
            "زر الملاحظة")
    s = sub(s, """                IconButton(
                  tooltip: S.deleteLine,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _lines.length <= 1""",
            """                // س237 (D-235): ملاحظة السطر — حقل صغير قابل
                // للتوسيع (خيار سياسات البيع).
                if (_lineNotesEnabled)
                  IconButton(
                    tooltip: S.lineNoteLabel,
                    icon: Icon(line.noteVisible
                        ? Icons.sticky_note_2
                        : Icons.sticky_note_2_outlined),
                    onPressed: () => setState(
                        () => line.noteVisible = !line.noteVisible),
                  ),
                IconButton(
                  tooltip: S.deleteLine,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _lines.length <= 1""",
            "زر الملاحظة ٢", count=0) if False else s

    # ٧) حقل الملاحظة تحت صف الكمية/السعر/الخصم — ندرجه بعد غلق الصف
    #    (نجد زر الحذف ونعلو لغلق الصف) — أدرجناه كزر أعلاه فالحقل الآن:
    s = sub(s, """            if (line.itemId != null)""",
            """            if (line.noteVisible)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextField(
                  controller: line.note,
                  decoration: const InputDecoration(
                      labelText: S.lineNoteLabel, isDense: true),
                ),
              ),
            if (line.itemId != null)""",
            "حقل الملاحظة")

    # ٨) قراءة الخيارين مع قراءات _load الأولى وتعيينهما بحالتها
    old_ses = (
        "    final session = await loadSession(widget.db);\n"
        "    if (!mounted) return;\n"
        "    setState(() {")
    new_ses = (
        "    final session = await loadSession(widget.db);\n"
        "    // س237 (المرحلة ج — D-235): خيارا سطور الفاتورة مع القراءات\n"
        "    // الأولى — السطر الحر وملاحظات السطور.\n"
        "    final freeLineAllowed = await widget.db.invoiceFreeLineAllowed();\n"
        "    final lineNotesEnabled = await widget.db.invoiceLineNotesEnabled();\n"
        "    if (!mounted) return;\n"
        "    setState(() {")
    s = sub(s, old_ses, new_ses, "قراءة الخيارين")
    old_res = (
        "      _reserveEnabled = reserveOn;\n"
        "      _reservedQty = reserved;")
    new_res = (
        "      _reserveEnabled = reserveOn;\n"
        "      _reservedQty = reserved;\n"
        "      // س237: الخياران مع أخويهما في الحالة.\n"
        "      _freeLineAllowed = freeLineAllowed;\n"
        "      _lineNotesEnabled = lineNotesEnabled;")
    s = sub(s, old_res, new_res, "تعيين الخيارين")

    return s


def main():
    s = io.open(L10N, encoding="utf-8").read()
    io.open(L10N, "w", encoding="utf-8").write(patch_l10n(s))
    print("l10n: %d مفتاحاً بقسم سطور الفاتورة" % len(L10N_KEYS))

    s = io.open(SALES, encoding="utf-8").read()
    io.open(SALES, "w", encoding="utf-8").write(patch_sales(s))
    print("sales_section: بطاقة سطور الفاتورة")

    s = io.open(SCREEN, encoding="utf-8").read()
    patched = patch_screen(s)  # يُحسب قبل الفتح — فالفتح للكتابة يقطع فوراً
    io.open(SCREEN, "w", encoding="utf-8").write(patched)
    print("المحرر: حقل الصنف الفوري والسطر الحر والملاحظة")


if __name__ == "__main__":
    main()
