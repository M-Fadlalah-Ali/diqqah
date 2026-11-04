import 'package:flutter/material.dart';

import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'reports_screen.dart' show formatMinorAmount;

/// شاشة التحويل بين مستودعين — س-18/F-045 (الدفعة 24 أولى م2).
///
/// النموذج: من مستودع نشط إلى مستودع نشط + أسطر أصناف بكمياتها
/// بالوحدة الأساسية (وحدات التعبئة دفعة تالية من م2) + التاريخ
/// افتراضه اليوم قابلاً للتعديل (س-111/D-108). زر «حفظ وترحيل»
/// يرحّل مباشرة — بلا مسودة (س-18: الرفض قبل الكتابة حصراً) — ورسالة
/// المدقق بأول خطأ صادقة (نمط س-36 «رسالة واحدة أول خطأ») من سجل
/// الوصاف الواحد لا صياغة واجهة موازية. والسجل أعلى القائمة يعرض
/// آخر التحويلات بالأرقام الموحدة.
class TransfersScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const TransfersScreen({super.key, required this.db});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  List<WarehouseRow> _warehouses = [];
  List<Item> _items = [];
  List<StockTransferListRow> _transfers = [];
  Map<int, int> _availByItem = {};
  int? _fromId;
  int? _toId;
  int? _pickerItemId;
  late final TextEditingController _date;
  final TextEditingController _qty = TextEditingController();
  final List<TransferLineDraft> _lines = [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: DateTime.now()
        .toIso8601String()
        .substring(0, 10));
    _reload();
  }

  @override
  void dispose() {
    _date.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final warehouses = (await widget.db.warehousesOf())
        .where((w) => w.isActive)
        .toList();
    final items =
        (await widget.db.select(widget.db.items).get())
            .where((i) => i.isActive && i.kind == 'good')
            .toList();
    final transfers = await widget.db.stockTransfersOf();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _items = items;
      _transfers = transfers;
      _fromId ??= warehouses.isEmpty ? null : warehouses.first.id;
      _toId ??= warehouses.length > 1 ? warehouses[1].id : null;
      _error = null;
    });
    await _reloadAvail();
  }

  /// المتاح لكل صنف من المستودع المصدر المختار (نمط D-106 قراءة خالصة).
  Future<void> _reloadAvail() async {
    final from = _fromId;
    if (from == null) return;
    final avail = await widget.db.stockQuantitiesByItem(warehouseId: from);
    if (!mounted) return;
    setState(() => _availByItem = avail);
  }

  void _addLine() {
    final itemId = _pickerItemId;
    if (itemId == null) return;
    final item = _items.firstWhere((i) => i.id == itemId);
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (item.kind != 'good') {
      setState(() => _error = 'الصنف خدمة بلا مخزون — التحويل بضاعة حصراً');
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
    if (_fromId == _toId && _fromId != null) {
      setState(() =>
          _error = 'التحويل من المستودع إلى نفسه مرفوض — مستودعان مختلفان');
      return;
    }
    setState(() {
      _lines.add(TransferLineDraft(itemId: item.id, qtyBase: qty));
      _qty.clear();
      _error = null;
    });
  }

  Future<void> _post() async {
    final from = _fromId;
    final to = _toId;
    if (from == null || to == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = StockTransferDraft(
      dateText: _date.text.trim(),
      fromWarehouseId: from,
      toWarehouseId: to,
      lines: List<TransferLineDraft>.unmodifiable(_lines),
    );
    try {
      final id = await widget.db.stockTransferPost(draft);
      final head = (await widget.db.customSelect(
        'SELECT number FROM stock_transfers WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).getSingle()).data['number'] as String;
      if (!mounted) return;
      setState(() {
        _lines.clear();
        _qty.clear();
        _error = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
              'رُحّل التحويل $head — ورصيد الطرفين تحدث فوراً'),
        ));
      }
      await _reload();
    } on StockTransferValidationException catch (e) {
      if (!mounted) return;
      setState(() => _error = firstStockTransferError(e.errors));
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
        _fromId != null && _toId != null && _fromId != _toId && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('تحويل بين مستودعين')),
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
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _fromId,
                  decoration:
                      const InputDecoration(labelText: 'من مستودع'),
                  items: [
                    for (final w in _warehouses)
                      DropdownMenuItem<int>(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _fromId = value;
                      _error = null;
                    });
                    _reloadAvail();
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_back),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _toId,
                  decoration:
                      const InputDecoration(labelText: 'إلى مستودع'),
                  items: [
                    for (final w in _warehouses)
                      DropdownMenuItem<int>(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (value) =>
                      setState(() {
                        _toId = value;
                        _error = null;
                      }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _date,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
                labelText: 'التاريخ (YYYY-MM-DD)'),
          ),
          const SizedBox(height: 12),
          Text('أضف أصناف التحويل (بالوحدة الأساسية)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _pickerItemId,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: [
              for (final item in _items)
                DropdownMenuItem<int>(
                    value: item.id, child: Text(itemDisplayLabel(item.name, item.sku))),
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
                      helperText: 'المتاح بالمصدر يظهر بجانب السطر'),
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
                  subtitle: Text('المتاح بالمصدر: '
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
          Text('آخر التحويلات',
              style: Theme.of(context).textTheme.titleMedium),
          for (final transfer in _transfers.take(10))
            ListTile(
              dense: true,
              leading: const Icon(Icons.swap_horiz),
              title: Text(
                  '${transfer.number} — ${transfer.fromName ?? '؟'} ← '
                  '${transfer.toName ?? '؟'}'),
              subtitle: Text(
                  '${transfer.transferDate} — ${transfer.lineCount} صنف — '
                  'القيمة ${formatMinorAmount(transfer.totalValueMinor)}'),
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
