import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'periods_screen.dart';

/// تنسيق عرض المبلغ بوحداته الصغرى كما تُخزن — فواصل آلاف للقراءة فقط
/// (عرضاً حصراً: أرقام السيناريوهات المعروفة تُرى كما هي لا محوَّلة —
/// D-092 معروض).
String formatMinorAmount(int amount) {
  final sign = amount < 0 ? '-' : '';
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return sign + grouped;
}

/// شاشة التقارير اليومية — دفعة م1 (6-ب): واجهات الدفعة السادسة
/// (س-79..س-85). التقارير الست قراءات لحظية من المرحّل حصراً — لا جداول
/// تجميع ولا أرقام مخزنة (D-089)، والفترات والإقفال شاشة قائمة بذاتها
/// منها (س-85) بصلاحية الإقفال إفصاحاً بطبقة الواجهة (D-090).
class ReportsScreen extends StatelessWidget {
  final DiqqahDatabase db;

  const ReportsScreen({super.key, required this.db});

  void _open(BuildContext context, Widget target) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير اليومية')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.balance_outlined),
            title: const Text('ميزان المراجعة'),
            subtitle: const Text(
                'أرصدة الحسابات من المرحّل لحظة الطلب — ومجموعاه متوازنان (F-068)'),
            onTap: () => _open(context, _TrialBalanceView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('تقرير الصناديق'),
            subtitle: const Text(
                'رصيد كل صندوق بمعادلة الصندوق ذاتها — والمعطل بشارته لا يُخفى'),
            onTap: () => _open(context, _CashBoxesView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('الذمم المدينة والدائنة'),
            subtitle: const Text('صافي كل طرف — هم يدينون لنا / نحن مدينون لهم'),
            onTap: () => _open(context, _ReceivablesPayablesView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('تقرير المخزون'),
            subtitle: const Text(
                'الكمية والقيمة الدفترية لكل صنف — والمتوسط عرضاً حصراً'),
            onTap: () => _open(context, _InventoryView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('مبيعات وحركة الأصناف'),
            subtitle: const Text('بيع ومردود بيع بمدى تاريخ — والصافي مشتق لا مخزن'),
            onTap: () => _open(
                context, _MovementView(db: db, sales: true)),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: const Text('تقرير المشتريات'),
            subtitle: const Text(
                'المستقل — شراء ومردود شراء بمدى تاريخ (وعد D-089، س-84)'),
            onTap: () => _open(
                context, _MovementView(db: db, sales: false)),
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('الفترات والإقفال'),
            subtitle: const Text(
                'إقفال فترة وما فيها يثبّت إلى الأبد — والفك طارئ بسبب نصي إلزامي'),
            onTap: () => _open(context, PeriodsScreen(db: db)),
          ),
        ],
      ),
    );
  }
}

/// عرض الحالة الجارية للقراءة — مؤشر انتظار بلا وعد مبكر (نمط الشاشات).
Widget _reportWait() => const Center(child: CircularProgressIndicator());

/// شريط «لا شيء بعد» الموحد — رسالة لا صمت (F-162 روحاً).
Widget _reportEmpty(String message) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );

/// ميزان المراجعة (س-71/س-80): المجمعان يُعرضان كما هما فلا يُطمَر خلل
/// ولو كان مستحيلاً — والرصيد باتجاهه الطبيعي والعكسي يظهر كما هو.
class _TrialBalanceView extends StatelessWidget {
  final DiqqahDatabase db;

  const _TrialBalanceView({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ميزان المراجعة')),
      body: FutureBuilder<TrialBalanceReport>(
        future: db.trialBalanceReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final report = snapshot.data!;
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        'مجموع المدين ${formatMinorAmount(report.totalDebitMinor)}'
                        ' — مجموع الدائن ${formatMinorAmount(report.totalCreditMinor)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.isBalanced
                            ? 'الميزان متوازن ✓ — مجموعا الجانبين متساويان (F-068)'
                            : 'الميزان غير متوازن — راجع فوراً!',
                        style: TextStyle(
                          color: report.isBalanced
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final row in report.rows)
                      ListTile(
                        title:
                            Text('${row.account.code} ${row.account.name}'),
                        subtitle: Text(
                            'مدين ${formatMinorAmount(row.debitSumMinor)}'
                            ' · دائن ${formatMinorAmount(row.creditSumMinor)}'),
                        trailing: Text(
                            'الرصيد ${formatMinorAmount(row.balanceMinor)}'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// تقرير الصناديق (س-72/س-81): الصندوق المعطل بشارة «معطل» ولا يُخفى —
/// الصدق أولاً.
class _CashBoxesView extends StatelessWidget {
  final DiqqahDatabase db;

  const _CashBoxesView({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير الصناديق')),
      body: FutureBuilder<List<CashBoxReportRow>>(
        future: db.cashBoxesReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return _reportEmpty('لا صناديق بعد');
          }
          return ListView(
            children: [
              for (final box in rows)
                ListTile(
                  title: Text(box.name),
                  subtitle: Text('حساب ${box.accountCode}'
                      ' · ${box.currencyCode}'
                      '${box.isActive ? '' : ' — معطل'}'),
                  trailing: Text(formatMinorAmount(box.balanceBaseMinor)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// تقرير الذمم (س-73/س-81): الاتجاهان كما يفهمهما صاحب المحل — والصفر
/// لا ذمة فلا صف.
class _ReceivablesPayablesView extends StatelessWidget {
  final DiqqahDatabase db;

  const _ReceivablesPayablesView({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الذمم المدينة والدائنة')),
      body: FutureBuilder<List<ReceivablesPayablesRow>>(
        future: db.receivablesPayablesReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return _reportEmpty('لا ذمم — كل الحسابات مصفاة');
          }
          return ListView(
            children: [
              for (final row in rows)
                ListTile(
                  title: Text(row.partyName),
                  subtitle: Text(row.direction == PartyBalanceDirection.theyOweUs
                      ? 'هم يدينون لنا'
                      : 'نحن مدينون لهم'),
                  trailing: Text(formatMinorAmount(row.amountMinor)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// تقرير المخزون (س-74/س-82): الكمية والقيمة من السجل والمتوسط عرضاً
/// حصراً بالرسة المعتمدة.
class _InventoryView extends StatelessWidget {
  final DiqqahDatabase db;

  const _InventoryView({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير المخزون')),
      body: FutureBuilder<List<InventoryReportRow>>(
        future: db.inventoryReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return _reportEmpty('لا مخزون بعد');
          }
          return ListView(
            children: [
              for (final row in rows)
                ListTile(
                  title: Text('${row.sku} ${row.name}'),
                  subtitle: Text(
                      'المستودع: ${row.warehouseName ?? 'غير محدد'}'
                      ' · المتوسط: ${row.avgCostBaseMinor == null ? '—' : formatMinorAmount(row.avgCostBaseMinor!)}'),
                  trailing: Text(
                      '${row.qtyBase} × ${formatMinorAmount(row.totalValueMinor)}'),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// صورة عرض موحدة لحركة صنف — تُبنى من صفوف البيع أو الشراء فتُقرأ
/// الدفعتان بلسان واحد.
class _MovementDisplay {
  final String title;
  final String subtitle;
  final String trailing;

  const _MovementDisplay(this.title, this.subtitle, this.trailing);
}

/// شاشة الحركة بمدى تاريخ (س-75/س-83 للمبيعات وس-84 للمشتريات): المدى
/// يُدقق قبل لمس القاعدة أصلاً، والمدى الغائب يعطي رسالة لا صمت.
class _MovementView extends StatefulWidget {
  final DiqqahDatabase db;

  /// صحيح: مبيعات وحركة الأصناف — كاذب: تقرير المشتريات المستقل.
  final bool sales;

  const _MovementView({required this.db, required this.sales});

  @override
  State<_MovementView> createState() => _MovementViewState();
}

class _MovementViewState extends State<_MovementView> {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  String? _error;
  List<_MovementDisplay>? _rows;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _rows = null;
    });
    try {
      final List<_MovementDisplay> out;
      if (widget.sales) {
        final rows = await widget.db.salesMovementReport(
          fromText: _from.text.trim(),
          toText: _to.text.trim(),
        );
        out = [
          for (final r in rows)
            _MovementDisplay(
              '${r.sku} ${r.name}',
              'بيع ${r.qtySoldBase} × ${formatMinorAmount(r.salesValueBaseMinor)}'
                  ' · مردود ${r.qtyReturnedBase} × ${formatMinorAmount(r.returnsValueBaseMinor)}',
              'الصافي ${r.netQtyBase} × ${formatMinorAmount(r.netValueBaseMinor)}',
            ),
        ];
      } else {
        final rows = await widget.db.purchasesMovementReport(
          fromText: _from.text.trim(),
          toText: _to.text.trim(),
        );
        out = [
          for (final r in rows)
            _MovementDisplay(
              '${r.sku} ${r.name}',
              'شراء ${r.qtyPurchasedBase} × ${formatMinorAmount(r.purchasesValueBaseMinor)}'
                  ' · مردود ${r.qtyReturnedBase} × ${formatMinorAmount(r.returnsValueBaseMinor)}',
              'الصافي ${r.netQtyBase} × ${formatMinorAmount(r.netValueBaseMinor)}',
            ),
        ];
      }
      if (!mounted) return;
      setState(() => _rows = out);
    } on ReportValidationException catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = e.errors.map(describeReportValidationError).join('؛ '));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.sales ? 'مبيعات وحركة الأصناف' : 'تقرير المشتريات';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _from,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                            labelText: 'من (YYYY-MM-DD)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _to,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                            labelText: 'إلى (YYYY-MM-DD)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _run, child: const Text('عرض')),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _rows == null
                ? const Center(child: Text('أدخل المدى ثم اضغط «عرض»'))
                : _rows!.isEmpty
                    ? _reportEmpty('لا حركة في هذا المدى')
                    : ListView(
                        children: [
                          for (final row in _rows!)
                            ListTile(
                              title: Text(row.title),
                              subtitle: Text(row.subtitle),
                              trailing: Text(row.trailing),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
