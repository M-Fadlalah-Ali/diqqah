import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
// س223: الحد المتدرج الموحد لقوائم المستندات (المتبقي من د5).
import 'list_display.dart';
import 'reports_screen.dart' show formatMinorAmount;
import 'dq_log.dart';
import 'date_picker.dart';

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

  /// س223 — الحد المتدرج لسجل جلسات الجرد (المتبقي من د5 بنمط
  /// list_display.dart): كان السقف الصلب take(10) يحجب الأقدم نهائياً
  /// والقراءة كاملة فالحد بناء واجهة حصراً والوجود كله متاح بالتوسع
  /// المتكرر.
  int _displayLimit = kListDisplayPageSize;

  /// الجلسة الجارية المعروضة — تُلتقط من السجل عند التحميل (الجلسة
  /// الواحدة بالمستودع مضمونة بالمحرك).
  int? _openSessionId;
  StockCountListRow? _openSession;
  List<StockCountLineRow> _lines = [];
  final Map<int, TextEditingController> _counted = {};
  Map<int, int> _availByItem = {};

  /// س115: مستويات التعبئة لأصناف الجلسة ذات المجموعة واختيار السطر
  /// (نمط الفواتير س89 والإذنين والتحويل س113) — والغائب الأساسية.
  final Map<int, List<UnitGroupLevel>> _levelsByItem = {};
  final Map<int, int?> _levelChoice = {};
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
    final levels = <int, List<UnitGroupLevel>>{};
    final choices = <int, int?>{};
    if (open != null) {
      lines = await widget.db.stockCountLinesOf(open.id);
      avail = await widget.db.stockQuantitiesByItem(warehouseId: open.warehouseId);
      for (final line in lines) {
        controllers[line.itemId] = TextEditingController(
            text: line.qtyDoc?.toString() ??
                line.countedQtyBase?.toString() ?? '');
        // س115: مستويات صنف واختياره المحفوظ — والغائب عدّ بالأساسية.
        final item = _itemOf(lines, line.itemId);
        final gid = item?.unitGroupId;
        if (gid != null) {
          levels[line.itemId] = await widget.db.levelsOfGroup(gid);
        }
        choices[line.itemId] = line.unitLevelId;
      }
    }
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _items = items;
      _sessions = sessions;
      // س223: إعادة تحميل فالحد المتدرج يصفر — البدء من الأحدث.
      _displayLimit = kListDisplayPageSize;
      _openSession = open;
      _openSessionId = open?.id;
      _lines = lines;
      _availByItem = avail;
      _error = null;
      _levelsByItem
        ..clear()
        ..addAll(levels);
      _levelChoice
        ..clear()
        ..addAll(choices);
      for (final old in _counted.values) {
        old.dispose();
      }
      _counted
        ..clear()
        ..addAll(controllers);
    });
  }

  /// صنف من أسطر الجلسة بمعرفه — لمستويات مجموعته (س115).
  Item? _itemOf(List<StockCountLineRow> lines, int itemId) {
    for (final i in _items) {
      if (i.id == itemId) return i;
    }
    return null;
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

  /// العدّة بالمخزونية من المدخل ومستوى السطر المختار (س115) —
  /// NULL إن كان المدخل فارغاً أو ليس رقماً.
  int? _countedBaseOf(int itemId) {
    final text = _counted[itemId]?.text.trim() ?? '';
    if (text.isEmpty) return null;
    final qty = int.tryParse(text);
    if (qty == null) return null;
    final levelId = _levelChoice[itemId];
    if (levelId == null) return qty;
    final levels = _levelsByItem[itemId] ?? const <UnitGroupLevel>[];
    for (final l in levels) {
      if (l.id == levelId) return qty * l.factor;
    }
    return qty;
  }

  /// حفظ العدّات المدخلة — العدّة الفارغة لا تُرسل (لم يُعدّ)، والصفر
  /// يُرسل كما هو (الرف فارغ شرعي). وس115: اللقطة بالمستوى المختار
  /// تُرسل مع العدّة (نمط الإذنين والتحويل س113).
  Future<void> _saveCounts() async {
    final sessionId = _openSessionId;
    if (sessionId == null || _busy) return;
    final counts = <int, int>{};
    final snapshots = <int, StockCountLevelSnapshot>{};
    for (final entry in _counted.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      final value = int.tryParse(text);
      if (value == null || value < 0) {
        setState(() =>
            _error = 'عدّة السطر «$text» ليست رقماً صحيحاً — صفر أو أكثر');
        return;
      }
      final levelId = _levelChoice[entry.key];
      if (levelId == null) {
        counts[entry.key] = value;
        continue;
      }
      final levels = _levelsByItem[entry.key] ?? const <UnitGroupLevel>[];
      UnitGroupLevel? level;
      for (final l in levels) {
        if (l.id == levelId) level = l;
      }
      if (level == null) {
        counts[entry.key] = value;
        continue;
      }
      counts[entry.key] = value * level.factor;
      snapshots[entry.key] = StockCountLevelSnapshot(
        unitLevelId: level.id,
        qtyDoc: value,
        factorAtEntry: level.factor,
      );
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
      await widget.db.stockCountSaveCounts(sessionId, counts,
          levelsByItemId: snapshots);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('حُفظت عدّات ${counts.length} سطراً — '
            'الفرق يُحسم لحظة الترحيل'),
      ));
      await _reload();
    } on StockCountValidationException catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.save');
      if (!mounted) return;
      setState(() =>
          _error = '${firstStockCountError(e.errors)}${dqTag(e)}');
    } catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.save');
      if (!mounted) return;
      setState(() => _error = '$e${dqTag(e)}');
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
      // الفروقات على الشاشة ثم تُرحَّل) — العدّة بالمخزونية من
      // المستوى المختار (س115).
      final diffs = <_DiffSummary>[];
      for (final line in _lines) {
        final countedBase = _countedBaseOf(line.itemId);
        if (countedBase == null) continue;
        final system = _availByItem[line.itemId] ?? 0;
        if (countedBase == system) continue;
        diffs.add(_DiffSummary(
          label: itemDisplayLabel(
              line.itemName ?? '؟', line.sku ?? ''),
          system: system,
          counted: countedBase,
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
      await dqLog(widget.db, e, context: 'stock_count.post');
      if (!mounted) return;
      setState(() =>
          _error = '${firstStockCountError(e.errors)}${dqTag(e)}');
    } catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.post');
      if (!mounted) return;
      setState(() => _error = '$e${dqTag(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// س112: إلغاء الجلسة المفتوحة المهجورة — نافذة قرار صريحة (روح
  /// نوافذ س104) ثم حذف منطقي بلا أثر قيدي ولا مخزني إطلاقاً.
  Future<void> _cancelSession() async {
    final sessionId = _openSessionId;
    if (sessionId == null || _busy) return;
    final head = _openSession?.number ?? '';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('إلغاء جلسة الجرد'),
          content: SizedBox(
            width: 320,
            child: Text('تُلغى الجلسة $head وتُحذف بعدّاتها بلا أثر — '
                'فلم يُرحَّل منها شيء، ويستطيع المستودع جلسة جديدة بعد '
                'الإلغاء. هل تؤكد؟'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('رجوع')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('إلغاء الجلسة')),
          ],
        ),
      );
      if (confirmed != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await widget.db.stockCountCancel(sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Text('أُلغيت جلسة الجرد $head — بلا أثر قيدي ولا مخزني'),
      ));
      await _reload();
    } on StockCountValidationException catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.cancel');
      if (!mounted) return;
      setState(() =>
          _error = '${firstStockCountError(e.errors)}${dqTag(e)}');
    } catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.cancel');
      if (!mounted) return;
      setState(() => _error = '$e${dqTag(e)}');
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
                    // س115: لقطة العدّ بالتعبئة ظاهرة بالتفصيل (نمط
                    // بطاقة السطر س113: «3 (بالمستوى) = 36»).
                    subtitle: Text(line.direction == null
                        ? (line.unitLevelId == null
                            ? 'بلا عدّ بعد'
                            : 'المعدود ${line.qtyDoc} (بالمستوى) = '
                                '${line.countedQtyBase}')
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
              padding: EdgeInsets.fromLTRB(
                  diqqahAdaptiveHorizontalMargin(context),
                  12,
                  diqqahAdaptiveHorizontalMargin(context),
                  12),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
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
                          // س115: منسدل وحدة العدّ لأصناف المجموعة —
                          // والأساسية افتراضاً والمكافئ بالأساسية لحظة
                          // الكتابة (درس س79، نمط الإذنين والتحويل س113).
                          if ((_levelsByItem[line.itemId] ??
                                  const <UnitGroupLevel>[])
                              .isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<int?>(
                                    initialValue: _levelChoice[line.itemId],
                                    decoration: const InputDecoration(
                                        labelText: 'وحدة العدّ',
                                        helperText:
                                            'الأساسية أو مستوى مجموعة الصنف',
                                        isDense: true),
                                    items: [
                                      const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text('الأساسية')),
                                      for (final l in _levelsByItem[line.itemId]!)
                                        DropdownMenuItem<int?>(
                                            value: l.id,
                                            child: Text('${l.name} ×${l.factor}')),
                                    ],
                                    onChanged: (v) => setState(() =>
                                        _levelChoice[line.itemId] = v),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                        _levelChoice[line.itemId] == null
                                            ? ''
                                            : 'المكافئ بالأساسية: '
                                                '${_countedBaseOf(line.itemId) ?? '—'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                      // س112: إلغاء الجلسة المهجورة — بنافذة قرار صريحة
                      // فالجلسة بلا ترحيل لا أثر لها ولا لأسطرها.
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _cancelSession,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('إلغاء الجلسة'),
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
                // س223 (المتبقي من د5): الحد المتدرج الموحد بدل السقف
                // الصلب take(10) — القراءة كاملة والحد بناء واجهة حصراً
                // فالأقدم متاح بالتوسع بدل حجبه نهائياً.
                for (final s
                    in listDisplayPage(_sessions, limit: _displayLimit))
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
                if (_sessions.length > _displayLimit)
                  listDisplayExpandButton(
                    context: context,
                    remaining: _sessions.length - _displayLimit,
                    onExpand: () => setState(
                        () => _displayLimit += kListDisplayPageSize),
                  ),
              ],
            ),
    );
  }

  String _liveDiff(int itemId) {
    // س115: الفرق بالمخزونية من المستوى المختار لا من المدخل الخام.
    final countedBase = _countedBaseOf(itemId);
    if (countedBase == null) return 'بلا عدّ';
    final system = _availByItem[itemId] ?? 0;
    final diff = countedBase - system;
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
      await dqLog(widget.db, e, context: 'stock_count.create');
      if (mounted) {
        setState(() =>
            _error = '${firstStockCountError(e.errors)}${dqTag(e)}');
      }
    } catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.create');
      if (mounted) setState(() => _error = '$e${dqTag(e)}');
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
              decoration: InputDecoration(
                  labelText: 'تاريخ الجلسة (YYYY-MM-DD)',
                  suffixIcon: calendarPickerSuffix(context, _date)),
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

  /// س115: مستويات مجموعة الصنف المختار واختيار الوحدة (نمط
  /// الإذنين س113) — والفراغ عدّ بالأساسية كما اعتاد.
  List<UnitGroupLevel> _levels = [];
  int? _levelId;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _loadLevels(int? itemId) async {
    if (itemId == null) {
      if (mounted) setState(() { _levels = []; _levelId = null; });
      return;
    }
    final item = widget.candidates.firstWhere((i) => i.id == itemId);
    final gid = item.unitGroupId;
    final levels = gid == null
        ? <UnitGroupLevel>[]
        : await widget.db.levelsOfGroup(gid);
    if (!mounted) return;
    setState(() {
      _levels = levels;
      _levelId = null;
    });
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
      // س115: العدّ بالتعبئة بلقطة المستوى (نمط الفواتير س89) —
      // والأساسية هي المخزونية دائماً.
      int countedBase = qty;
      int? levelId;
      int? factorAtEntry;
      if (_levelId != null) {
        final level = _levels.firstWhere((l) => l.id == _levelId);
        levelId = level.id;
        factorAtEntry = level.factor;
        countedBase = qty * level.factor;
      }
      await widget.db.stockCountAddFoundItem(widget.sessionId,
          StockCountLineDraft(
        itemId: itemId,
        countedQtyBase: countedBase,
        unitLevelId: levelId,
        qtyDoc: levelId == null ? null : qty,
        factorAtEntry: factorAtEntry,
      ));
      if (mounted) Navigator.of(context).pop();
    } on StockCountValidationException catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.add');
      if (mounted) {
        setState(() =>
            _error = '${firstStockCountError(e.errors)}${dqTag(e)}');
      }
    } catch (e) {
      await dqLog(widget.db, e, context: 'stock_count.add');
      if (mounted) setState(() => _error = '$e${dqTag(e)}');
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
              onChanged: (value) async {
                setState(() => _itemId = value);
                await _loadLevels(value);
              },
            ),
            // س115: وحدة العدّ للمكتشف — والأساسية افتراضاً والمكافئ
            // بالأساسية لحظة الكتابة (درس س79).
            if (_levels.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: _levelId,
                decoration: const InputDecoration(
                    labelText: 'وحدة العدّ',
                    helperText: 'الأساسية أو مستوى مجموعة الصنف'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('الأساسية')),
                  for (final l in _levels)
                    DropdownMenuItem<int?>(
                        value: l.id, child: Text('${l.name} ×${l.factor}')),
                ],
                onChanged: (v) => setState(() => _levelId = v),
              ),
              if (_levelId != null && _qty.text.trim().isNotEmpty)
                Text(
                    'المكافئ بالأساسية: '
                    '${(int.tryParse(_qty.text.trim()) ?? 0) * _levels.firstWhere((l) => l.id == _levelId).factor}'),
            ],
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
