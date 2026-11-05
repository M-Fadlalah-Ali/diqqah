import 'package:flutter/material.dart';

import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'reports_screen.dart' show formatMinorAmount;

/// شاشة مستند التجميع (F-211 — الدفعة 29 سادسة م2، س88).
///
/// مكونات من رصيد المستودع ← وحدات جاهزة بالوصفة بكمياتها؛ تكلفة
/// الناتج مجموع كلف المكونات المسحوبة؛ **بلا قيد محاسبي** — نقل قيمة
/// بين أصناف داخل 113 (الثابت F-178 محفوظ) بروح النقل بين المستودعات.
/// بلا مسودة (نمط س-18: الرفض قبل الكتابة حصراً)، والمعاينة الحية
/// بأسطر المكونات المطلوبة والمتاح والقيمة التقديرية تتجدد لحظة
/// الكتابة (نمط D-106/درس س79: الفرق الحي بonChanged) فالمعاينة هي
/// التنفيذ (D-183)، ورسالة المدقق بأول خطأ صادقة من سجل الوصاف الواحد
/// (نمط س-36)، والمكوّن الخدمي ظاهر بعِلمه بلا طلب ولا قيمة
/// (F-212/F-211 — الحد الصادق: قيمته من صميم البيع لا البناء).
class AssemblyScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const AssemblyScreen({super.key, required this.db});

  @override
  State<AssemblyScreen> createState() => _AssemblyScreenState();
}

class _AssemblyScreenState extends State<AssemblyScreen> {
  List<WarehouseRow> _warehouses = [];
  List<Item> _bundles = [];
  List<AssemblyListRow> _docs = [];
  AssemblyPreviewResult? _preview;
  int? _warehouseId;
  int? _bundleItemId;
  late final TextEditingController _date;
  final TextEditingController _qty = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
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
    final bundles = (await widget.db.select(widget.db.items).get())
        .where((i) => i.isActive && i.kind == 'bundle')
        .toList();
    final docs = await widget.db.assembliesOf();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _bundles = bundles;
      _docs = docs;
      _warehouseId ??= warehouses.isEmpty ? null : warehouses.first.id;
      _error = null;
    });
    await _reloadPreview();
  }

  /// المعاينة الحية — تتجدد لحظة الكتابة (درس س79: الفرق الحي ب
  /// onChanged لا بالبناء وحده) — قراءة خالصة فما يُرى هو ما سينفذ.
  Future<void> _reloadPreview() async {
    final bundle = _bundleItemId;
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (bundle == null || qty <= 0 || _warehouseId == null) {
      if (!mounted) return;
      setState(() => _preview = null);
      return;
    }
    final preview = await widget.db.assemblyPreview(
      dateText: _date.text.trim(),
      warehouseId: _warehouseId!,
      bundleItemId: bundle,
      qtyBundles: qty,
    );
    if (!mounted) return;
    setState(() => _preview = preview);
  }

  Future<void> _post() async {
    if (_busy ||
        _warehouseId == null ||
        _bundleItemId == null ||
        _preview == null ||
        _preview!.errors.isNotEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final docId = await widget.db.assemblyPost(AssemblyDraft(
        dateText: _date.text.trim(),
        warehouseId: _warehouseId!,
        bundleItemId: _bundleItemId!,
        qtyBundles: int.parse(_qty.text.trim()),
      ));
      final number = (await widget.db.customSelect(
        'SELECT number FROM assemblies WHERE id = ?',
        variables: [Variable.withInt(docId)],
      ).getSingle()).data['number'] as String;
      if (!mounted) return;
      setState(() {
        _qty.clear();
        _preview = null;
        _error = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('رُحّل مستند التجميع $number — المكونات نقصت '
              'والناتج دخل بقيمة مكوناته ومجموع قيمة المخزون مستقر '
              '(F-178)'),
        ));
      }
      await _reload();
    } on AssemblyValidationException catch (e) {
      if (!mounted) return;
      setState(() => _error = firstAssemblyError(e.errors));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final canPost = preview != null &&
        preview.errors.isEmpty &&
        !_busy &&
        _bundleItemId != null &&
        _warehouseId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('مستند التجميع')),
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
            decoration: const InputDecoration(labelText: 'من مستودع'),
            items: [
              for (final w in _warehouses)
                DropdownMenuItem<int>(value: w.id, child: Text(w.name)),
            ],
            onChanged: (value) {
              setState(() {
                _warehouseId = value;
                _error = null;
              });
              _reloadPreview();
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
          DropdownButtonFormField<int>(
            initialValue: _bundleItemId,
            decoration: const InputDecoration(
                labelText: 'الصنف التجميعي (صاحب الوصفة)'),
            items: [
              for (final item in _bundles)
                DropdownMenuItem<int>(
                    value: item.id,
                    child: Text(itemDisplayLabel(item.name, item.sku))),
            ],
            onChanged: (value) {
              setState(() {
                _bundleItemId = value;
                _error = null;
              });
              _reloadPreview();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'عدد الوحدات المنتجة',
              helperText: 'المكونات تُسحب بكميات الوصفة × هذا العدد',
            ),
            onChanged: (_) => _reloadPreview(),
          ),
          const SizedBox(height: 12),
          if (preview != null) ...[
            Text('معاينة التجميع — ما يُرى هو ما سينفذ',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final line in preview.lines)
              ListTile(
                dense: true,
                leading: Icon(line.isService
                    ? Icons.handyman_outlined
                    : Icons.inventory_2_outlined),
                title: Text(line.isService
                    ? '${line.label} — خدمة بلا سحب (قيمتها من البيع '
                        'لا البناء — F-212)'
                    : '${line.label} × ${line.qtyNeeded}'),
                subtitle: Text(line.isService
                    ? 'لا حركة ولا قيمة بنائية'
                    : 'المتاح: ${line.qtyAvailable} — القيمة التقديرية: '
                        '${formatMinorAmount(line.valueMinor)}'),
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_outlined),
              title: Text(
                  'الناتج: ${preview.bundleLabel ?? '؟'} × '
                  '${int.tryParse(_qty.text.trim()) ?? 0}'),
              subtitle: Text(
                  'قيمة الدخول (مجموع المكونات المسحوبة): '
                  '${formatMinorAmount(preview.totalValueMinor)} — بلا '
                  'قيد محاسبي (F-211)'),
            ),
            for (final e in preview.errors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(describeAssemblyValidationError(e),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
          ],
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: canPost ? _post : null,
            icon: const Icon(Icons.precision_manufacturing_outlined),
            label: const Text('ترحيل التجميع'),
          ),
          const Divider(height: 24),
          Text('آخر التجميعات',
              style: Theme.of(context).textTheme.titleMedium),
          for (final doc in _docs.take(10))
            ListTile(
              dense: true,
              leading: const Icon(Icons.precision_manufacturing_outlined),
              title: Text('${doc.number} — '
                  '${doc.bundleName != null ? itemDisplayLabel(doc.bundleName!, doc.bundleSku ?? '') : '؟'}'
                  ' × ${doc.qtyBase}'),
              subtitle: Text('${doc.assemblyDate} — ${doc.warehouseName ?? '؟'}'
                  ' — ${doc.lineCount} مكوّن — القيمة '
                  '${formatMinorAmount(doc.totalValueMinor)}'),
            ),
        ],
      ),
    );
  }
}
