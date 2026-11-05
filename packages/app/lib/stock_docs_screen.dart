import 'package:flutter/material.dart';

import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'reports_screen.dart' show formatMinorAmount;

/// شاشة إذني المخزون — إدخال وإخراج (F-209/F-210، الدفعة 26 أولى م2
/// س85/D-189).
///
/// الشاشتان شكل واحد باتجاهين (نمط الإذنين التوأمين بالميثاق 03 §4):
/// - **الإدخال**: زيادة رصيد صنف بسبب نصي إلزامي، والمقابل افتراضه
///   43 «إيرادات أخرى» قابل التغيير من الحسابات المفعلة.
/// - **الإخراج**: نقصان رصيد صنف بسبب نصي إلزامي، والمقابل افتراضه
///   596 «خسائر التلف والأضرار» قابل التغيير، بحماية السالب F-042.
///
/// بلا مسودة (نمط س-18: الرفض قبل الكتابة حصراً) وزر «حفظ وترحيل»
/// يرحّل مباشرة، ورسالة المدقق بأول خطأ صادقة من سجل الوصاف الواحد
/// (نمط س-36)، والقيم بلا إدخال يدوي: الزيادة بتقييم زيادة الجرد
/// المقرر (D-186) والخروج بالمتوسط الحاكم بالامتصاص (F-047/D-067) —
/// فلا خانة تكلفة تعرض شبهة تسعير يدوي لا يملكه الإذن.
enum StockDocDirection { receipt, issue }

/// شاشة الإذن الواحد باتجاهه.
class StockDocScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final StockDocDirection direction;

  const StockDocScreen({
    super.key,
    required this.db,
    required this.direction,
  });

  @override
  State<StockDocScreen> createState() => _StockDocScreenState();
}

class _StockDocScreenState extends State<StockDocScreen> {
  List<WarehouseRow> _warehouses = [];
  List<Item> _items = [];
  List<AccountInfo> _accounts = [];
  List<StockDocListRow> _docs = [];
  Map<int, int> _availByItem = {};
  int? _warehouseId;
  int? _counterAccountId;
  int? _pickerItemId;
  late final TextEditingController _date;
  late final TextEditingController _reason;
  final TextEditingController _qty = TextEditingController();
  final List<StockDocLineDraft> _lines = [];
  String? _error;
  bool _busy = false;

  bool get _isReceipt => widget.direction == StockDocDirection.receipt;

  String get _title => _isReceipt ? 'إذن إدخال المخزون' : 'إذن إخراج المخزون';

  /// حساب المقابل الافتراضي بالكود المعتمد (03 §4): 43 للإدخال
  /// و596 للإخراج — قابل التغيير من الحسابات المفعلة حصراً.
  String get _defaultAccountCode => _isReceipt ? '43' : '596';

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: DateTime.now()
        .toIso8601String()
        .substring(0, 10));
    _reason = TextEditingController();
    _reload();
  }

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final warehouses = (await widget.db.warehousesOf())
        .where((w) => w.isActive)
        .toList();
    final items = (await widget.db.select(widget.db.items).get())
        .where((i) => i.isActive && i.kind == 'good')
        .toList();
    final accounts = (await widget.db.allLedgerAccounts())
        .where((a) => a.isActive && a.isLeaf)
        .toList();
    final docs = _isReceipt
        ? await widget.db.stockReceiptsOf()
        : await widget.db.stockIssuesOf();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _items = items;
      _accounts = accounts;
      _docs = docs;
      _warehouseId ??= warehouses.isEmpty ? null : warehouses.first.id;
      _counterAccountId ??= _defaultAccountId(accounts);
      _error = null;
    });
    await _reloadAvail();
  }

  /// المعرف الافتراضي للمقابل بالكود المعتمد — الغياب أول حساب مفعّل.
  int? _defaultAccountId(List<AccountInfo> accounts) {
    for (final a in accounts) {
      if (a.code == _defaultAccountCode) return a.id;
    }
    return accounts.isEmpty ? null : accounts.first.id;
  }

  /// المتاح لكل صنف بالمستودع المختار (نمط D-106 قراءة خالصة) —
  /// يعرض بالإخراج حمايةً ولاعلم المالك قبل الرفض لا بعده.
  Future<void> _reloadAvail() async {
    final w = _warehouseId;
    if (w == null) return;
    final avail = await widget.db.stockQuantitiesByItem(warehouseId: w);
    if (!mounted) return;
    setState(() => _availByItem = avail);
  }

  void _addLine() {
    final itemId = _pickerItemId;
    if (itemId == null) return;
    final item = _items.firstWhere((i) => i.id == itemId);
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (item.kind != 'good') {
      setState(() =>
          _error = 'الصنف خدمة بلا مخزون — إذنا المخزون بضاعة حصراً');
      return;
    }
    if (_lines.any((l) => l.itemId == item.id)) {
      setState(() =>
          _error = 'الصنف مكرر — الصنف الواحد سطراً واحداً فاجمع الكميتين');
      return;
    }
    if (qty <= 0) {
      setState(() => _error = 'الكمية يجب أن تكون موجبة بالوحدة الأساسية');
      return;
    }
    setState(() {
      _lines.add(StockDocLineDraft(itemId: item.id, qtyBase: qty));
      _qty.clear();
      _error = null;
    });
  }

  Future<void> _post() async {
    if (_busy || _warehouseId == null || _counterAccountId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      late final int docId;
      if (_isReceipt) {
        docId = await widget.db.stockReceiptPost(StockReceiptDraft(
          dateText: _date.text.trim(),
          warehouseId: _warehouseId!,
          reason: _reason.text,
          counterAccountId: _counterAccountId!,
          lines: List<StockDocLineDraft>.unmodifiable(_lines),
        ));
      } else {
        docId = await widget.db.stockIssuePost(StockIssueDraft(
          dateText: _date.text.trim(),
          warehouseId: _warehouseId!,
          reason: _reason.text,
          counterAccountId: _counterAccountId!,
          lines: List<StockDocLineDraft>.unmodifiable(_lines),
        ));
      }
      final table = _isReceipt ? 'stock_receipts' : 'stock_issues';
      final head = (await widget.db.customSelect(
        'SELECT number FROM $table WHERE id = ?',
        variables: [Variable.withInt(docId)],
      ).getSingle()).data['number'] as String;
      if (!mounted) return;
      setState(() {
        _lines.clear();
        _qty.clear();
        _reason.clear();
        _error = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(_isReceipt
              ? 'رُحّل $_title $head — والرصيد والقيد قيّدا فوراً'
              : 'رُحّل $_title $head — والرصيد نقص والقيد قيّد فوراً'),
        ));
      }
      await _reload();
    } on StockDocValidationException catch (e) {
      if (!mounted) return;
      setState(() => _error = firstStockDocError(e.errors));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPost =
        _warehouseId != null && _counterAccountId != null && !_busy;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
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
                        color:
                            Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
          DropdownButtonFormField<int>(
            initialValue: _warehouseId,
            decoration: InputDecoration(
                labelText: _isReceipt ? 'إلى مستودع' : 'من مستودع'),
            items: [
              for (final w in _warehouses)
                DropdownMenuItem<int>(value: w.id, child: Text(w.name)),
            ],
            onChanged: (value) {
              setState(() {
                _warehouseId = value;
                _error = null;
              });
              _reloadAvail();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _date,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
                labelText: 'التاريخ (YYYY-MM-DD)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'السبب (إلزامي)',
              helperText: _isReceipt
                  ? 'هدية مورد، بضاعة وجدت، تصحيح إدخال…'
                  : 'تالف، استهلاك داخلي، هدية…',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _counterAccountId,
            decoration: InputDecoration(
              labelText: _isReceipt
                  ? 'الحساب المقابل (افتراضه 43 إيرادات أخرى)'
                  : 'الحساب المقابل (افتراضه 596 خسائر التلف والأضرار)',
            ),
            items: [
              for (final a in _accounts)
                DropdownMenuItem<int>(value: a.id, child: Text(a.displayLabel)),
            ],
            onChanged: (value) => setState(() {
              _counterAccountId = value;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          Text('أضف أصناف الإذن (بالوحدة الأساسية)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _pickerItemId,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: [
              for (final item in _items)
                DropdownMenuItem<int>(
                    value: item.id,
                    child: Text(itemDisplayLabel(item.name, item.sku))),
            ],
            onChanged: (itemId) => setState(() => _pickerItemId = itemId),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'الكمية',
                      helperText: 'المتاح بالمستودع يظهر بجانب السطر'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickerItemId == null ? null : _addLine,
                icon: const Icon(Icons.add),
                label: const Text('أضف السطر'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_lines.isNotEmpty) ...[
            for (var i = 0; i < _lines.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                      '${_itemLabel(_lines[i].itemId)} × ${_lines[i].qtyBase}'),
                  subtitle: Text('المتاح بالمستودع: '
                      '${_availByItem[_lines[i].itemId] ?? 0}'),
                  trailing: IconButton(
                    tooltip: 'إزالة السطر',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() => _lines.removeAt(i)),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: canPost && _lines.isNotEmpty ? _post : null,
            icon: const Icon(Icons.check),
            label: const Text('حفظ وترحيل'),
          ),
          const Divider(height: 24),
          Text(_isReceipt ? 'آخر إذون الإدخال' : 'آخر إذون الإخراج',
              style: Theme.of(context).textTheme.titleMedium),
          for (final doc in _docs.take(10))
            ListTile(
              dense: true,
              leading: Icon(_isReceipt
                  ? Icons.archive_outlined
                  : Icons.unarchive_outlined),
              title: Text('${doc.number} — ${doc.warehouseName ?? '؟'}'),
              subtitle: Text(
                  '${doc.dateText} — ${doc.lineCount} صنف — الكمية '
                  '${doc.totalQtyBase} — القيمة '
                  '${formatMinorAmount(doc.totalValueMinor)} — السبب: '
                  '${doc.reason}'),
            ),
        ],
      ),
    );
  }

  String _itemLabel(int itemId) {
    for (final item in _items) {
      if (item.id == itemId) return itemDisplayLabel(item.name, item.sku);
    }
    return 'صنف #$itemId';
  }
}
