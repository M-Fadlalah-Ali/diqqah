import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'reports_screen.dart' show formatMinorAmount;

/// شاشة الجرد وتسوياته — س-19/F-046 (الدفعة 25 ثاني م2).
///
/// الجلسة: مستودع نشط بنطاق «كل الأصناف» أو «مجموعة تصنيف»، تُنشأ بحالة
/// «جارٍ» فتُبذر أسطرها آلياً من أرصدة المستودع داخل النطاق، ويُحفظ
/// العدّ متكرراً، وتُراجع الفروقات على الشاشة (الرصيد الآني بجانب
/// العدّة — نمط D-106)، ثم «ترحيل الجلسة» بديالوج تأكيد يعرض ملخص
/// الفروقات فتُرحَّل بترحيلة واحدة — لا تسوية جزئية (س-19). ورسالة
/// المدقق بأول خطأ من سجل الوصاف الواحد تبقى حتى الإجراء التالي
/// والرفض لا يبدل القائمة (درس س78 الموثق).
class StockCountsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const StockCountsScreen({super.key, required this.db});

  @override
  State<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends State<StockCountsScreen> {
  List<WarehouseRow> _warehouses = [];
  List<Item> _items = [];
  List<StockCountListRow> _sessions = [];

  /// الجلسة الجارية المعروضة — تُلتقط من السجل عند التحميل (الجلسة
  /// الواحدة بالمستودع مضمونة بالمحرك).
  int? _openSessionId;
  StockCountListRow? _openSession;
  List<StockCountLineRow> _lines = [];
  final Map<int, TextEditingController> _counted = {};
  Map<int, int> _availByItem = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    for (final c in _counted.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    final warehouses = (await widget.db.warehousesOf())
        .where((w) => w.isActive)
        .toList();
    final items = (await widget.db.select(widget.db.items).get())
        .where((i) => i.isActive && i.kind == 'good')
        .toList();
    final sessions = await widget.db.stockCountsOf();
    final open = sessions
        .where((s) => s.state == 'open')
        .toList()
        .firstOrNull;
    List<StockCountLineRow> lines = [];
    Map<int, int> avail = {};
    final controllers = <int, TextEditingController>{};
    if (open != null) {
      lines = await widget.db.stockCountLinesOf(open.id);
      avail = await widget.db.stockQuantitiesByItem(warehouseId: open.warehouseId);
      for (final line in lines) {
        controllers[line.itemId] = TextEditingController(
            text: line.countedQtyBase?.toString() ?? '');
      }
    }
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _items = items;
      _sessions = sessions;
      _openSession = open;
      _openSessionId = open?.id;
      _lines = lines;
      _availByItem = avail;
      _error = null;
      for (final old in _counted.values) {
        old.dispose();
      }
      _counted
        ..clear()
        ..addAll(controllers);
    });
  }

  Future<void> _startSession() async {
    if (_busy) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _StartSessionDialog(
          db: widget.db, warehouses: _warehouses, items: _items),
    );
    if (created != true) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 4),
      content: Text('فُتحت جلسة الجرد — عدّ كل الأسطر ثم رحّلها'),
    ));
  }

  /// حفظ العدّات المدخلة — العدّة الفارغة لا تُرسل (لم يُعدّ)، والصفر
  /// يُرسل كما هو (الرف فارغ شرعي).
  Future<void> _saveCounts() async {
    final sessionId = _openSessionId;
    if (sessionId == null || _busy) return;
    final counts = <int, int>{};
    for (final entry in _counted.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      final value = int.tryParse(text);
      if (value == null || value < 0) {
        setState(() =>
            _error = 'عدّة السطر «$text» ليست رقماً صحيحاً — صفر أو أكثر');
        return;
      }
      counts[entry.key] = value;
    }
    if (counts.isEmpty) {
      setState(() => _error = 'لا عدّة محفوظة — أدخل عدّ سطراً واحداً على الأقل');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.db.stockCountSaveCounts(sessionId, counts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('حُفظت عدّات ${counts.length} سطراً — '
            'الفرق يُحسم لحظة الترحيل'),
      ));
      await _reload();
    } on StockCountValidationException catch (e) {
      if (!mounted) return;
      setState(() => _error = firstStockCountError(e.errors));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFoundItem() async {
    final sessionId = _openSessionId;
    if (sessionId == null || _busy) return;
    final session = _openSession;
    if (session == null) return;
    final existing = _lines.map((l) => l.itemId).toSet();
    final candidates = _items.where((i) {
      if (existing.contains(i.id)) return false;
      if (session.scope == 'group') return i.category == session.scopeCategory;
      return true;
    }).toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _FoundItemDialog(db: widget.db, sessionId: sessionId, candidates: candidates),
    );
    await _reload();
  }

  Future<void> _postSession() async {
    final sessionId = _openSessionId;
    final session = _openSession;
    if (sessionId == null || session == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // ملخص الفروقات الآني للمراجعة قبل الترحيل (س-19: تُراجع
      // الفروقات على الشاشة ثم تُرحَّل)
      final diffs = <_DiffSummary>[];
      for (final line in _lines) {
        final text = _counted[line.itemId]?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final counted = int.tryParse(text);
        if (counted == null) continue;
        final system = _availByItem[line.itemId] ?? 0;
        if (counted == system) continue;
        diffs.add(_DiffSummary(
          label: itemDisplayLabel(
              line.itemName ?? '؟', line.sku ?? ''),
          system: system,
          counted: counted,
        ));
      }
      final uncounted = _lines
          .where((l) =>
              (_counted[l.itemId]?.text.trim().isEmpty ?? true))
          .length;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ترحيل جلسة الجرد'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(uncounted > 0
                    ? 'لم يُعدّ $uncounted سطراً — الترحيل يرفض (لا تسوية جزئية)'
                    : diffs.isEmpty
                        ? 'لا فروقات — ترحيل بلا قيد'
                        : 'ستُسوّى الفروقات التالية ضد الأرصدة الآنية:'),
                const SizedBox(height: 8),
                ...[
                  for (final d in diffs)
                    Text('• ${d.label}: النظام ${d.system} / المعدود '
                        '${d.counted} — الفرق ${d.counted - d.system}',
                        style: Theme.of(dialogContext).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('رجوع للتعديل')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('ترحيل')),
          ],
        ),
      );
      if (confirmed != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await widget.db.stockCountPost(sessionId);
      final head = _openSession?.number ?? '';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('رُحّلت جلسة الجرد $head — الأرصدة تطابق '
            'الواقع المعدود والقيد بميزان الدفتر'),
      ));
      await _reload();
    } on StockCountValidationException catch (e) {
      if (!mounted) return;
      setState(() => _error = firstStockCountError(e.errors));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSessionDetails(StockCountListRow session) async {
    final lines = await widget.db.stockCountLinesOf(session.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('الجلسة ${session.number}'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${session.warehouseName} — ${session.countDate} — '
                  '${session.state == 'posted' ? 'مرحّلة' : 'جارٍ'}'),
              const SizedBox(height: 8),
              ...[
                for (final line in lines)
                  ListTile(
                    dense: true,
                    title: Text(itemDisplayLabel(
                        line.itemName ?? '؟', line.sku ?? '')),
                    subtitle: Text(line.direction == null
                        ? 'بلا عدّ بعد'
                        : 'النظام ${line.systemQtyBase} / المعدود '
                            '${line.countedQtyBase} — ${_directionLabel(line.direction!)}'
                            ' بقيمة ${formatMinorAmount(line.valueBaseMinor)}'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  static String _directionLabel(String direction) => switch (direction) {
        'deficit' => 'عجز',
        'surplus' => 'زيادة',
        _ => 'بلا فرق',
      };

  @override
  Widget build(BuildContext context) {
    final session = _openSession;
    return Scaffold(
      appBar: AppBar(title: const Text('جرد المخزون')),
      body: _sessions.isEmpty && session == null && _warehouses.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)),
                    ),
                  ),
                if (session == null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _startSession,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('جلسة جرد جديدة'),
                  )
                else ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الجلسة ${session.number} — جارٍ',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('${session.warehouseName} — '
                              '${stockCountScopeLabel(session.scope == 'group'
                                  ? StockCountScope.group
                                  : StockCountScope.all)}'
                              '${session.scope == 'group' ? ' «${session.scopeCategory}»' : ''}'
                              ' — ${session.countDate}'),
                        ],
                      ),
                    ),
                  ),
                  Text('عدّ كل الأسطر — الصفر يعني «الرف فارغ»',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final line in _lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(itemDisplayLabel(
                                line.itemName ?? '؟', line.sku ?? '')),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                                'بالنظام: ${_availByItem[line.itemId] ?? 0}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _counted[line.itemId],
                              keyboardType: TextInputType.number,
                              // الفرق الحي يُبنى لحظة الكتابة (نمط D-106:
                              // القراءة الحية بجانب الإدخال)
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                  labelText: 'المعدود',
                                  isDense: true),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                                _liveDiff(line.itemId),
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _saveCounts,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('حفظ العدّ'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _addFoundItem,
                        icon: const Icon(Icons.add),
                        label: const Text('صنف وجدناه'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _postSession,
                        icon: const Icon(Icons.check),
                        label: const Text('ترحيل الجلسة'),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Text('سجل جلسات الجرد',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('لا جلسات بعد'),
                  ),
                for (final s in _sessions.take(10))
                  ListTile(
                    dense: true,
                    leading: Icon(s.state == 'posted'
                        ? Icons.fact_check
                        : Icons.pending_outlined),
                    title: Text('${s.number} — ${s.warehouseName} — '
                        '${s.state == 'posted' ? 'مرحّلة' : 'جارٍ'}'),
                    subtitle: Text(
                        '${s.countDate} — ${s.countedCount}/${s.lineCount} '
                        'معدود — عجز ${s.deficitCount} وزيادة '
                        '${s.surplusCount}'),
                    onTap: () => _openSessionDetails(s),
                  ),
              ],
            ),
    );
  }

  String _liveDiff(int itemId) {
    final text = _counted[itemId]?.text.trim() ?? '';
    if (text.isEmpty) return 'بلا عدّ';
    final counted = int.tryParse(text);
    if (counted == null) return '—';
    final system = _availByItem[itemId] ?? 0;
    final diff = counted - system;
    if (diff == 0) return 'مطابق';
    return diff < 0 ? 'عجز ${-diff}' : 'زيادة $diff';
  }
}

class _DiffSummary {
  final String label;
  final int system;
  final int counted;

  const _DiffSummary({
    required this.label,
    required this.system,
    required this.counted,
  });
}

/// ديالوج افتتاح الجلسة — المستودع والنطاق والتاريخ (اليوم افتراضاً
/// س-111/D-108)، والمجموعة بمنتقي تصنيف من أصناف القائمة.
class _StartSessionDialog extends StatefulWidget {
  final DiqqahDatabase db;
  final List<WarehouseRow> warehouses;
  final List<Item> items;

  const _StartSessionDialog({
    required this.db,
    required this.warehouses,
    required this.items,
  });

  @override
  State<_StartSessionDialog> createState() => _StartSessionDialogState();
}

class _StartSessionDialogState extends State<_StartSessionDialog> {
  int? _warehouseId;
  StockCountScope _scope = StockCountScope.all;
  String? _category;
  late final TextEditingController _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.warehouses.isEmpty ? null : widget.warehouses.first.id;
    _date = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  List<String> get _categories => widget.items
      .map((i) => i.category)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();

  Future<void> _create() async {
    final warehouseId = _warehouseId;
    if (warehouseId == null) {
      setState(() => _error = 'اختر المستودع أولاً');
      return;
    }
    if (_scope == StockCountScope.group &&
        (_category == null || _category!.trim().isEmpty)) {
      setState(() => _error = 'نطاق «مجموعة تصنيف» يطلب التصنيف أولاً');
      return;
    }
    try {
      await widget.db.stockCountStart(StockCountStartDraft(
        dateText: _date.text.trim(),
        warehouseId: warehouseId,
        scope: _scope,
        scopeCategory: _scope == StockCountScope.group ? _category : null,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } on StockCountValidationException catch (e) {
      if (mounted) setState(() => _error = firstStockCountError(e.errors));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('جلسة جرد جديدة'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            DropdownButtonFormField<int>(
              initialValue: _warehouseId,
              decoration: const InputDecoration(labelText: 'المستودع'),
              items: [
                for (final w in widget.warehouses)
                  DropdownMenuItem<int>(value: w.id, child: Text(w.name)),
              ],
              onChanged: (value) => setState(() => _warehouseId = value),
            ),
            // RadioGroup الواجهة الحالية (3.32+) — بلا خصائص مهجورة
            RadioGroup<StockCountScope>(
              groupValue: _scope,
              onChanged: (value) => setState(() {
                _scope = value!;
                _error = null;
              }),
              child: const Column(
                children: [
                  RadioListTile<StockCountScope>(
                    title: Text('كل الأصناف'),
                    value: StockCountScope.all,
                  ),
                  RadioListTile<StockCountScope>(
                    title: Text('مجموعة تصنيف'),
                    value: StockCountScope.group,
                  ),
                ],
              ),
            ),
            if (_scope == StockCountScope.group)
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'التصنيف'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem<String>(value: c, child: Text(c)),
                ],
                onChanged: (value) => setState(() {
                  _category = value;
                  _error = null;
                }),
              ),
            TextField(
              controller: _date,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                  labelText: 'تاريخ الجلسة (YYYY-MM-DD)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _create, child: const Text('فتح الجلسة')),
      ],
    );
  }
}

/// ديالوج «صنف وجدناه» — منتقي داخل النطاق بعدّة موجبة.
class _FoundItemDialog extends StatefulWidget {
  final DiqqahDatabase db;
  final int sessionId;
  final List<Item> candidates;

  const _FoundItemDialog({
    required this.db,
    required this.sessionId,
    required this.candidates,
  });

  @override
  State<_FoundItemDialog> createState() => _FoundItemDialogState();
}

class _FoundItemDialogState extends State<_FoundItemDialog> {
  int? _itemId;
  final TextEditingController _qty = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final itemId = _itemId;
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (itemId == null) {
      setState(() => _error = 'اختر الصنف أولاً');
      return;
    }
    if (qty <= 0) {
      setState(() => _error = 'عدّة الصنف الموجود فعلاً موجبة حصراً');
      return;
    }
    try {
      await widget.db.stockCountAddFoundItem(widget.sessionId,
          StockCountLineDraft(itemId: itemId, countedQtyBase: qty));
      if (mounted) Navigator.of(context).pop();
    } on StockCountValidationException catch (e) {
      if (mounted) setState(() => _error = firstStockCountError(e.errors));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('صنف وجدناه'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            DropdownButtonFormField<int>(
              initialValue: _itemId,
              decoration: const InputDecoration(labelText: 'الصنف'),
              items: [
                for (final item in widget.candidates)
                  DropdownMenuItem<int>(
                      value: item.id,
                      child: Text(itemDisplayLabel(item.name, item.sku))),
              ],
              onChanged: (value) => setState(() => _itemId = value),
            ),
            TextField(
              controller: _qty,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'العدّة الموجودة'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _add, child: const Text('أضف للجلسة')),
      ],
    );
  }
}
