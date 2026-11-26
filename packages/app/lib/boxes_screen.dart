import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'app_theme.dart' show diqqahLanesOf;
import 'reports_screen.dart' show formatMinorAmount;
import 'adaptive.dart';
import 'context_menu.dart';
import 'vouchers_screen.dart';
import 'dq_log.dart';

/// شاشة الصناديق — دفعة (6-ج) واجهات الإدخال (س-93، D-095 معروض):
/// القائمة من تقرير الصناديق لحظياً (الرصيد بمعادلة الصندوق ذاتها)،
/// وإنشاء صندوق يحصل آلياً على حسابه الورقي 111x التالي (D-086 معتمد)
/// وتعطيله آمن بلا أرصدة حصراً — والرسالة من المحرك برسالته لا
/// صياغة واجهة موازية.
class BoxesScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const BoxesScreen({super.key, required this.db});

  @override
  State<BoxesScreen> createState() => _BoxesScreenState();
}

class _BoxesScreenState extends State<BoxesScreen> {
  List<CashBoxReportRow>? _rows;
  List<String>? _errors;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await widget.db.cashBoxesReport();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _errors = null;
    });
  }

  void _openNew() {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
              builder: (_) => BoxEditScreen(db: widget.db)),
        )
        .then((created) {
          if (created == true) _reload();
        });
  }

  Future<void> _disable(CashBoxReportRow box) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعطيل الصندوق؟'),
        content: Text(
            'الصندوق «${box.name}» سيُعطل مع حسابه ${box.accountCode} — '
            'والتعطيل آمن بلا أرصدة حصراً'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('تعطيل')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.db.disableCashBox(box.boxId);
      if (!mounted) return;
      setState(() => _notice =
          'عُطّل الصندوق «${box.name}» وحسابه ${box.accountCode} معه');
      _reload();
    } catch (e) {
      await dqLog(widget.db, e, context: 'box.disable');
      if (!mounted) return;
      // رسالة المحرك برسالتها: «برصيد قائم — تعطيله غير آمن...»
      setState(() => _errors = ['$e${dqTag(e)}']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصناديق'),
        // مدخل السندات والتحويلات والتسويات — حركتها حركة الصناديق،
        // والوحدة ليست بنداً مستقلاً بالهيكلية (D-094 معروض).
        actions: [
          IconButton(
            tooltip: 'السندات والتحويلات والتسويات',
            icon: const Icon(Icons.receipt_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => VouchersScreen(db: widget.db)),
            ),
          ),
          // درس CI (س36): زر الإنشاء في AppBar لا FAB — فالزر دائماً
          // مضروباً في RTL لا يحجبه شيء ويبنيه الهيكل مباشرة.
          TextButton.icon(
            onPressed: _openNew,
            icon: const Icon(Icons.add),
            label: const Text('صندوق جديد'),
          ),
        ],
      ),
      body: ListView(
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
          if (_errors != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_errors!.join('\n'),
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer)),
              ),
            ),
          if (rows == null)
            const Center(child: CircularProgressIndicator())
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'لا صناديق بعد — أضف أول صندوق بزر «صندوق جديد»',
                  textAlign: TextAlign.center),
            )
          else
            for (final row in rows)
              // س208: النمط الموحد — بطاقة بقائمة سياق س207 بفعاليات
              // المضيف القائمة حصراً (التعطيل للنشط حصراً — عرف س-93)
              // ونسخ المعرّف، والرصيد والأدوات القائمة ترِد كما هي.
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: RecordContextMenu(
                  actions: [
                    if (row.isActive)
                      RecordContextAction(
                        label: 'تعطيل الصندوق',
                        icon: Icons.block_outlined,
                        onSelected: () => _disable(row),
                      ),
                    copyIdAction(context, row.boxId),
                  ],
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(row.name),
                    subtitle: Text('حساب ${row.accountCode}'
                        ' · ${row.currencyCode}'
                        '${row.isActive ? '' : ' — معطل'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatMinorAmount(row.balanceBaseMinor)),
                        if (row.isActive)
                          IconButton(
                            tooltip: 'تعطيل',
                            icon: const Icon(Icons.block_outlined),
                            onPressed: () => _disable(row),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// نموذج صندوق جديد (D-086 معتمد): الاسم والعملة — والحساب الورقي
/// 111x التالي ينشأ آلياً معه من المحرك، والاسم المكرر يُرفض برسالته.
class BoxEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const BoxEditScreen({super.key, required this.db});

  @override
  State<BoxEditScreen> createState() => _BoxEditScreenState();
}

class _BoxEditScreenState extends State<BoxEditScreen> {
  final TextEditingController _name = TextEditingController();
  int _currencyId = 1;
  List<CurrencyRow> _currencies = [];
  List<String>? _errors;
  bool _busy = false;

  /// بوابة التحميل — نمط initialValue الموثق.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final currencies = await widget.db.currenciesOf();
    if (!mounted) return;
    setState(() {
      _currencies = currencies;
      final base = currencies.where((c) => c.isBase).toList();
      _currencyId = base.isEmpty ? 1 : base.first.id;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _errors = ['اسم الصندوق إلزامي']);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      await widget.db.createCashBox(
        name: _name.text.trim(),
        currencyId: _currencyId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      await dqLog(widget.db, e, context: 'box.save');
      if (!mounted) return;
      // رسالة المحرك برسالتها: «اسم الصندوق «...» مستخدم سلفاً» أو
      // «عملة الصندوق غير معروفة» — بلا صياغة موازية (الصدق أولاً).
      setState(() {
        _errors = ['$e${dqTag(e)}'];
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text('صندوق جديد')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('صندوق جديد')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_errors != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_errors!.join('\n'),
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)),
                    ),
                  ),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'اسم الصندوق',
                      helperText:
                          'يُنشأ معه حسابه الورقي 111x التالي آلياً'),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _currencyId,
                  decoration: const InputDecoration(
                      labelText: 'العملة — وسند الصندوق بعملته حصراً'),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem<int>(
                          value: c.id,
                          child: Text('${c.code} ${c.name}')),
                  ],
                  onChanged: (value) =>
                      setState(() => _currencyId = value ?? 1),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('إنشاء الصندوق'),
                ),
              ],
            ),
    );
  }
}
