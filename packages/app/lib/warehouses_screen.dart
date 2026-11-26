import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'app_theme.dart' show diqqahLanesOf;
import 'reports_screen.dart' show formatMinorAmount;
import 'adaptive.dart';
import 'context_menu.dart';
import 'assembly_screen.dart';
import 'stock_counts_screen.dart';
import 'stock_docs_screen.dart';
import 'transfers_screen.dart';
import 'dq_log.dart';

/// شاشة المستودعات — أولى م2 «تعدد المستودعات والتحويل بينها» (دفعة 24
/// س77/D-185): القائمة من warehousesOf لحظياً والإدارة بها (إضافة وإعادة
/// تسمية وتفعيل/تعطيل) — **بلا حذف أبداً** فالمرجع المحاسبي المرتبط
/// بحركات لا يُحذف — ورسالة المحرك برسالتها لا صياغة واجهة موازية
/// (نمط الصناديق). ومدخل التحويل زر ظاهر أعلى الشاشة لا مدفون (درس
/// D-098: الزر المدفون لا يلمحه المالك)، وسجل التحويلات أسفلها.
class WarehousesScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const WarehousesScreen({super.key, required this.db});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  List<WarehouseRow>? _warehouses;
  List<StockTransferListRow>? _transfers;
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final warehouses = await widget.db.warehousesOf();
    final transfers = await widget.db.stockTransfersOf();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _transfers = transfers;
      _error = null;
      // _notice لا تُمسح هنا — نمط الصناديق: بطاقة النجاح تبقى حتى
      // الإجراء التالي، وإلا ومضت وأفلتت قبل أن يراها المالك.
    });
  }

  Future<void> _openNew() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مستودع جديد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم المستودع'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('تراجع')),
          FilledButton(
            onPressed: () {
              final err = warehouseNameError(controller.text);
              if (err != null) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(SnackBar(content: Text(err)));
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    if (created != true) return;
    try {
      final id = await widget.db.warehouseCreate(name: controller.text);
      if (!mounted) return;
      setState(() => _notice = 'أُنشئ المستودع «${controller.text.trim()}»');
      _reload();
      assert(id > 0, 'معرف المستودع موجب');
    } catch (e) {
      if (!mounted) return;
      await dqLog(widget.db, e, context: 'warehouse.add');
      // رسالة المحرك برسالتها: «مستخدم سلفاً...»
      setState(() => _error = '$e${dqTag(e)}');
    }
  }

  Future<void> _rename(WarehouseRow warehouse) async {
    final controller = TextEditingController(text: warehouse.name);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إعادة تسمية «${warehouse.name}»'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'الاسم الجديد'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('تراجع')),
          FilledButton(
            onPressed: () {
              final err = warehouseNameError(controller.text);
              if (err != null) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(SnackBar(content: Text(err)));
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await widget.db.warehouseRename(
          id: warehouse.id, name: controller.text);
      if (!mounted) return;
      setState(() =>
          _notice = 'عُدّل اسم المستودع إلى «${controller.text.trim()}»');
      _reload();
    } catch (e) {
      await dqLog(widget.db, e, context: 'warehouse.rename');
      if (!mounted) return;
      setState(() => _error = '$e${dqTag(e)}');
    }
  }

  Future<void> _setActive(WarehouseRow warehouse, bool active) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('تعطيل المستودع؟'),
          content: Text(
              'المستودع «${warehouse.name}» سيُعطل ويختفي من اختيارات '
              'الإدخال — والتعطيل آمن بلا رصيد حصراً '
              'وبلا حذف أبداً'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('تراجع')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('تعطيل')),
          ],
        ),
      );
      if (confirmed != true) {
        _reload();
        return;
      }
    }
    try {
      await widget.db.warehouseSetActive(id: warehouse.id, active: active);
      if (!mounted) return;
      setState(() => _notice = active
          ? 'فُعّل المستودع «${warehouse.name}»'
          : 'عُطّل المستودع «${warehouse.name}»');
      _reload();
    } catch (e) {
      if (!mounted) return;
      await dqLog(widget.db, e, context: 'warehouse.toggle');
      // رسالة المحرك برسالتها: «آخر مستودع نشط...» أو «برصيد قائم...»
      // — والرفض لا يبدل القائمة فلا إعادة تحميل تمسح الرسالة.
      setState(() => _error = '$e${dqTag(e)}');
    }
  }

  Future<void> _openTransferDetails(StockTransferListRow transfer) async {
    final lines = await widget.db.stockTransferLinesOf(transfer.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('التحويل ${transfer.number}'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  '${transfer.fromName ?? '؟'} ← ${transfer.toName ?? '؟'}'
                  ' — ${transfer.transferDate}'),
              const SizedBox(height: 8),
              ...[
                for (final line in lines)
                  ListTile(
                    dense: true,
                    title: Text(itemDisplayLabel(
                        line.itemName ?? '؟', line.sku ?? '')),
                    subtitle: Text('الكمية ${line.qtyBase} — القيمة '
                        '${formatMinorAmount(line.valueBaseMinor)}'),
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

  @override
  Widget build(BuildContext context) {
    final warehouses = _warehouses;
    final transfers = _transfers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المستودعات'),
        // درس CI (س36): زر الإنشاء في AppBar لا FAB
        actions: [
          TextButton.icon(
            onPressed: _openNew,
            icon: const Icon(Icons.add),
            label: const Text('مستودع جديد'),
          ),
        ],
      ),
      body: warehouses == null || transfers == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // س208 (الدفعة 2 — الاتساق): الهامش الأفقي التكيفي م06 —
              // العريض يتوسّط والضيّق هامشه الأساسي حرفاً.
              padding: EdgeInsets.fromLTRB(
                  diqqahAdaptiveHorizontalMargin(context), 12,
                  diqqahAdaptiveHorizontalMargin(context), 12),
              children: [
                if (_notice != null)
                  Card(
                    color: diqqahLanesOf(context).positive.bg,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_notice!),
                    ),
                  ),
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
                // مدخل التحويل ظاهر لا مدفون (درس D-098) — ومدخل الجرد
                // إلى جانبه (الدفعة 25 س-19/F-046) — وإذنا المخزون
                // الدفعة 26 (F-209/F-210): بطاقة المخزون أزرارها
                // إدخال وإخراج ونقل وجرد — والتجميع خامساً الدفعة 29
                // (F-211 آخر م2 — س88).
                FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute<void>(
                          builder: (_) => StockDocScreen(
                              db: widget.db,
                              direction: StockDocDirection.receipt)))
                    .then((_) => _reload()),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('إذن إدخال مخزون'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute<void>(
                          builder: (_) => StockDocScreen(
                              db: widget.db,
                              direction: StockDocDirection.issue)))
                    .then((_) => _reload()),
                  icon: const Icon(Icons.unarchive_outlined),
                  label: const Text('إذن إخراج مخزون'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute<void>(
                          builder: (_) =>
                              TransfersScreen(db: widget.db)))
                    .then((_) => _reload()),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('تحويل بين مستودعين'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute<void>(
                          builder: (_) =>
                              StockCountsScreen(db: widget.db)))
                    .then((_) => _reload()),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('جرد المخزون'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute<void>(
                          builder: (_) => AssemblyScreen(db: widget.db)))
                    .then((_) => _reload()),
                  icon: const Icon(Icons.precision_manufacturing_outlined),
                  label: const Text('تجميع'),
                ),
                const SizedBox(height: 12),
                ...[
                  for (final warehouse in warehouses)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      // س208: قائمة سياق س207 على سجل المستودع — فعاليات
                      // المضيف القائمة حصراً (إعادة التسمية) ونسخ المعرّف،
                      // ومفتاح التفعيل القائم ترِد كما هي.
                      child: RecordContextMenu(
                        actions: [
                          RecordContextAction(
                            label: 'إعادة تسمية',
                            icon: Icons.edit_outlined,
                            onSelected: () => _rename(warehouse),
                          ),
                          copyIdAction(context, warehouse.id),
                        ],
                        child: ListTile(
                          leading: Icon(
                            warehouse.isActive
                                ? Icons.warehouse_outlined
                                : Icons.inventory_2_outlined,
                          ),
                          title: Text(warehouse.name),
                          subtitle: Text(warehouse.isActive
                              ? 'نشط — يظهر في اختيارات الإدخال'
                              : 'معطل — لا يظهر في اختيارات الإدخال',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'إعادة تسمية',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _rename(warehouse),
                              ),
                              Switch(
                                value: warehouse.isActive,
                                onChanged: (value) =>
                                    _setActive(warehouse, value),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                const Divider(height: 24),
                Text('سجل التحويلات',
                    style: Theme.of(context).textTheme.titleMedium),
                if (transfers.isEmpty)
                  // س208: الحالة الفارغة بلسان فعل — زر التحويل فوقها ظاهر.
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'لا تحويلات بعد — ابدأ بتحويل بين مستودعين'),
                  ),
                ...[
                  for (final transfer in transfers)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      // س208: قائمة سياق س207 — فعاليات المضيف القائمة
                      // حصراً (تفاصيل التحويل) ونسخ المعرّف.
                      child: RecordContextMenu(
                        actions: [
                          RecordContextAction(
                            label: 'تفاصيل التحويل',
                            icon: Icons.description_outlined,
                            onSelected: () =>
                                _openTransferDetails(transfer),
                          ),
                          copyIdAction(context, transfer.id),
                        ],
                        child: ListTile(
                          onTap: () =>
                              _openTransferDetails(transfer),
                          leading: const Icon(Icons.swap_horiz),
                          title: Text(
                              '${transfer.number} — '
                              '${transfer.fromName ?? '؟'} ← '
                              '${transfer.toName ?? '؟'}'),
                          subtitle: Text(
                              '${transfer.transferDate} — '
                              '${transfer.lineCount} صنف — الكمية '
                              '${transfer.totalQtyBase} — القيمة '
                              '${formatMinorAmount(transfer.totalValueMinor)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
