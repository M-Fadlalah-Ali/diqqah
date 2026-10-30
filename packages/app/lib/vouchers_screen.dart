import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'reports_screen.dart' show formatMinorAmount;

/// شاشة السندات والصناديق المالية — دفعة (6-ج) واجهات الإدخال
/// (س-89..س-94، D-094..D-096 معروض): ثلاث تبويبات قراءة لحظية من
/// المرحّل (السندات الطرفية وغير الطرفية، التحويلات، التسويات) ونماذج
/// إنشاء يفوض الحكم كله للمحرك — المدقق البنيوي ثم الفحوص المحركية
/// ثم حواجز القاعدة (منع السالب الموحد) — والواجهة تعرض رسائل المدقق
/// العربية كما هي.
class VouchersScreen extends StatelessWidget {
  final DiqqahDatabase db;

  const VouchersScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('السندات'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'السندات'),
              Tab(text: 'التحويلات'),
              Tab(text: 'التسويات'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VouchersTab(db: db),
            _TransfersTab(db: db),
            _AdjustmentsTab(db: db),
          ],
        ),
      ),
    );
  }
}

/// شريط المدى الموحد للتبويبات — نفس نمط شاشات التقارير (D-077 حرس
/// أول برسالة المدقق قبل لمس القاعدة).
class _RangeBar extends StatelessWidget {
  final TextEditingController from;
  final TextEditingController to;
  final VoidCallback onShow;

  const _RangeBar({
    required this.from,
    required this.to,
    required this.onShow,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: from,
              keyboardType: TextInputType.datetime,
              decoration:
                  const InputDecoration(labelText: 'من (YYYY-MM-DD)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: to,
              keyboardType: TextInputType.datetime,
              decoration:
                  const InputDecoration(labelText: 'إلى (YYYY-MM-DD)'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onShow, child: const Text('عرض')),
        ],
      ),
    );
  }
}

/// بناء القائمة القرائية الموحد للتبويبات الثلاثة — رسالة المدقق تظهر
/// لا صمتاً، والفراغ رسالة إرشاد لا شاشة خاوية (F-162 روحاً).
Widget _tabList<T>(BuildContext context, AsyncSnapshot<List<T>> snapshot,
    String emptyMessage, Widget Function(T row) builder) {
  if (snapshot.hasError) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('${snapshot.error}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    );
  }
  if (!snapshot.hasData) {
    return const Center(child: CircularProgressIndicator());
  }
  final rows = snapshot.data!;
  if (rows.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(emptyMessage, textAlign: TextAlign.center),
      ),
    );
  }
  return ListView(children: [for (final row in rows) builder(row)]);
}

/// تبويب السندات (قبض/صرف — س-12..س-15) — القائمة الطرفية وغير الطرفية
/// معاً والمميزان بحقليهما.
class _VouchersTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _VouchersTab({required this.db});

  @override
  State<_VouchersTab> createState() => _VouchersTabState();
}

class _VouchersTabState extends State<_VouchersTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  Future<List<VoucherListRow>>? _rows;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _rows = widget.db
          .vouchersListReport(fromText: _from.text.trim(), toText: _to.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-voucher',
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
                builder: (_) => VoucherEditScreen(db: widget.db)),
          );
          if (created == true) _reload();
        },
        icon: const Icon(Icons.receipt_outlined),
        label: const Text('سند جديد'),
      ),
      body: Column(
        children: [
          _RangeBar(from: _from, to: _to, onShow: _reload),
          Expanded(
            child: FutureBuilder<List<VoucherListRow>>(
              future: _rows,
              builder: (context, snapshot) => _tabList<VoucherListRow>(
                context,
                snapshot,
                'لا سندات بعد — أضف أول سند بزر «سند جديد»',
                (row) => ListTile(
                  title: Text(row.displayLabel),
                  subtitle: Text('${row.voucherDate}'
                      ' · ${row.counterpartLabel}'
                      ' · ${row.boxName}'
                      ' · ${row.stateLabel}'),
                  trailing: Text(
                      '${formatMinorAmount(row.amountDocMinor)}'
                      ' ${row.currencyCode}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// تبويب التحويلات بين الصناديق (س-16/D-087 معتمد) — القيد بسطرين
/// «صندوق المستلم مدين / صندوق المرسل دائن» والقراءة تعرض الطرفين.
class _TransfersTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _TransfersTab({required this.db});

  @override
  State<_TransfersTab> createState() => _TransfersTabState();
}

class _TransfersTabState extends State<_TransfersTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  Future<List<BoxTransferListRow>>? _rows;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _rows = widget.db
          .boxTransfersListReport(fromText: _from.text.trim(), toText: _to.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-transfer',
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
                builder: (_) => TransferEditScreen(db: widget.db)),
          );
          if (created == true) _reload();
        },
        icon: const Icon(Icons.swap_horiz),
        label: const Text('تحويل جديد'),
      ),
      body: Column(
        children: [
          _RangeBar(from: _from, to: _to, onShow: _reload),
          Expanded(
            child: FutureBuilder<List<BoxTransferListRow>>(
              future: _rows,
              builder: (context, snapshot) => _tabList<BoxTransferListRow>(
                context,
                snapshot,
                'لا تحويلات بعد — أضف أول تحويل بزر «تحويل جديد»',
                (row) => ListTile(
                  title: Text(row.displayLabel),
                  subtitle: Text('${row.transferDate}'
                      ' · من ${row.fromBoxName}'
                      ' · إلى ${row.toBoxName}'
                      ' · ${row.stateLabel}'),
                  trailing: Text(
                      '${formatMinorAmount(row.amountDocMinor)}'
                      ' ${row.currencyCode}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// تبويب تسويات الصناديق (س-17/F-067) — الاتجاه والسبب الظاهران بالصف.
class _AdjustmentsTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _AdjustmentsTab({required this.db});

  @override
  State<_AdjustmentsTab> createState() => _AdjustmentsTabState();
}

class _AdjustmentsTabState extends State<_AdjustmentsTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  Future<List<CashAdjustmentListRow>>? _rows;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _rows = widget.db.cashAdjustmentsListReport(
          fromText: _from.text.trim(), toText: _to.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-adjustment',
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
                builder: (_) => AdjustmentEditScreen(db: widget.db)),
          );
          if (created == true) _reload();
        },
        icon: const Icon(Icons.balance),
        label: const Text('تسوية جديدة'),
      ),
      body: Column(
        children: [
          _RangeBar(from: _from, to: _to, onShow: _reload),
          Expanded(
            child: FutureBuilder<List<CashAdjustmentListRow>>(
              future: _rows,
              builder: (context, snapshot) =>
                  _tabList<CashAdjustmentListRow>(
                context,
                snapshot,
                'لا تسويات بعد — أضف أول تسوية بزر «تسوية جديدة»',
                (row) => ListTile(
                  title: Text(row.displayLabel),
                  subtitle: Text('${row.adjustmentDate}'
                      ' · ${row.boxName}'
                      ' · ${row.directionLabel}'
                      ' · السبب: ${row.reason}'
                      ' · ${row.stateLabel}'),
                  trailing: Text(
                      '${formatMinorAmount(row.amountDocMinor)}'
                      ' ${row.currencyCode}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة حقل مطابقة — تحكم نصي لكل فاتورة مفتوحة يعبئه المستخدم
/// أو المقترح الآلي بالأقدمية.
class _AllocationUi {
  final int invoiceId;
  final String label;
  final int remainingDocMinor;
  final TextEditingController applied = TextEditingController();

  _AllocationUi({
    required this.invoiceId,
    required this.label,
    required this.remainingDocMinor,
  });

  void dispose() {
    applied.dispose();
  }
}

/// نموذج سند قبض/صرف (س-89/س-90): الطرفي بمطابقاته «يدوياً أو آلياً
/// بالأقدمية مع إمكانية التعديل» (05 §4.2/م-21) والفائض غير المطابق
/// «رصيد مقدَّم» على الذمة (س-12/س5)؛ وبغير طرف على حساب مباشر (311
/// ضخ رأس مال — 321 مسحوبات — 54x مصروف) بلا دخول الإيرادات (س-13/س-15).
class VoucherEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const VoucherEditScreen({super.key, required this.db});

  @override
  State<VoucherEditScreen> createState() => _VoucherEditScreenState();
}

class _VoucherEditScreenState extends State<VoucherEditScreen> {
  VoucherKind _kind = VoucherKind.receipt;
  bool _partyVoucher = true;
  int? _boxId;
  int? _partyId;
  int? _directAccountId;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _narration = TextEditingController();

  List<CashBoxReportRow> _boxes = [];
  List<Party> _parties = [];
  List<AccountInfo> _accounts = [];
  List<CurrencyRow> _currencies = [];

  /// لقطة صرف السند لغير الأساسية — الافتراضي لقطة الأساسية المحايدة
  /// (D-082)، وحقلها يظهر إذا كانت عملة الصندوق غير الأساسية.
  final TextEditingController _fx = TextEditingController();

  List<_AllocationUi> _allocations = [];
  List<String>? _errors;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    final parties = await widget.db.select(widget.db.parties).get();
    final accounts = await widget.db.allLedgerAccounts();
    final currencies = await widget.db.currenciesOf();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _parties = parties.where((p) => p.isActive).toList();
      _accounts = accounts.where((a) => a.isActive && a.isLeaf).toList();
      _currencies = currencies;
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
    });
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _narration.dispose();
    _fx.dispose();
    for (final a in _allocations) {
      a.dispose();
    }
    super.dispose();
  }

  /// عملة الصندوق المختار — سند الصندوق بعملته حصراً (D-086 معتمد).
  CashBoxReportRow? get _box {
    for (final b in _boxes) {
      if (b.boxId == _boxId) return b;
    }
    return null;
  }

  CurrencyRow _currencyOf(CashBoxReportRow box) {
    for (final c in _currencies) {
      if (c.code == box.currencyCode) return c;
    }
    return _currencies.first;
  }

  /// الحسابات المباشرة المتاحة — الورقية النشطة دون حسابات الصناديق
  /// (111x): المحرك يمنعها برسالته فلا تُعرض أصلاً (س-13/س-15).
  List<AccountInfo> get _directChoices => _accounts
      .where((a) => !a.code.startsWith('111') && a.isLeaf && a.isActive)
      .toList();

  /// أطراف جهة السند: القبض عملاء والصرف موردون (خريطة الذمم 05 §5).
  List<Party> get _sideParties => _parties
      .where((p) =>
          p.kind == (_kind.isReceipt ? 'customer' : 'supplier'))
      .toList();

  /// الفواتير المفتوحة للطرف بعملة الصندوق — وحقول المطابقة تُبنى
  /// من جديد عند كل تحميل (المسودات مقترحات لا تُحسب).
  Future<void> _reloadOpenInvoices() async {
    final box = _box;
    if (!_partyVoucher || _partyId == null || box == null) {
      if (mounted) {
        setState(() {
          for (final a in _allocations) {
            a.dispose();
          }
          _allocations = [];
        });
      }
      return;
    }
    final currency = _currencyOf(box);
    final open = await widget.db.openInvoicesForParty(
      kind: _kind,
      partyId: _partyId!,
      currencyId: currency.id,
    );
    if (!mounted) return;
    setState(() {
      for (final a in _allocations) {
        a.dispose();
      }
      _allocations = [
        for (final c in open)
          _AllocationUi(
            invoiceId: c.invoiceId,
            label: '${c.number} — متبقٍ ${formatMinorAmount(c.remainingDocMinor)}'
                ' (${c.dateText})',
            remainingDocMinor: c.remainingDocMinor,
          ),
      ];
    });
  }

  /// المقترح الآلي بالأقدمية (proposeOldestAllocations عبر المرحّل) —
  /// يعبئ الحقول ويبقى كل حقل قابلاً للتعديل (م-21: يدوياً أو آلياً
  /// مع إمكانية التعديل).
  Future<void> _proposeAutomatically() async {
    final box = _box;
    if (_partyId == null || box == null) return;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;
    final currency = _currencyOf(box);
    final proposed = await widget.db.proposeVoucherAllocations(
      kind: _kind,
      partyId: _partyId!,
      currencyId: currency.id,
      amountDocMinor: amount,
    );
    if (!mounted) return;
    for (final a in _allocations) {
      a.applied.clear();
    }
    for (final p in proposed) {
      for (final a in _allocations) {
        if (a.invoiceId == p.invoiceId) {
          a.applied.text = '${p.appliedDocMinor}';
        }
      }
    }
    setState(() {});
  }

  int get _appliedTotal {
    var total = 0;
    for (final a in _allocations) {
      total += int.tryParse(a.applied.text.trim()) ?? 0;
    }
    return total;
  }

  int get _amountValue => int.tryParse(_amount.text.trim()) ?? 0;

  /// لقطة صرف السند — عملة الصندوق الأساسية لقطتها المحايدة (D-082)
  /// وغيرها من الحقل، والفراغ صفر يلتقطه المدقق برسالته.
  int get _fxValue {
    final box = _box;
    if (box == null) return baseCurrencyFxRate;
    return _currencyOf(box).isBase
        ? baseCurrencyFxRate
        : (int.tryParse(_fx.text.trim()) ?? 0);
  }

  VoucherDraft _buildDraft() {
    return VoucherDraft(
      kind: _kind,
      dateText: _date.text.trim(),
      partyId: _partyVoucher ? _partyId : null,
      directAccountId: _partyVoucher ? null : _directAccountId,
      cashBoxId: _boxId ?? 0,
      currencyId: _box == null ? 1 : _currencyOf(_box!).id,
      fxRate: _fxValue,
      amountDocMinor: _amountValue,
      narration:
          _narration.text.trim().isEmpty ? null : _narration.text.trim(),
      allocations: [
        for (final a in _allocations)
          VoucherAllocationDraft(
            invoiceId: a.invoiceId,
            appliedDocMinor: int.tryParse(a.applied.text.trim()) ?? 0,
          ),
      ],
    );
  }

  Future<void> _save({required bool post}) async {
    if (_busy) return;
    final draft = _buildDraft();
    final structure = validateVoucherDraftStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure) describeVoucherValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final id = await widget.db.createVoucherDraft(draft);
      if (post) {
        await widget.db.postVoucher(id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on VoucherValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeVoucherValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = ['$e'];
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final directChoices = _directChoices;
    final box = _box;
    final unapplied = _amountValue - _appliedTotal;
    return Scaffold(
      appBar: AppBar(title: const Text('سند جديد')),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _errors!)
                            Text(e,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer)),
                        ],
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  value: _kind.storageValue,
                  decoration: const InputDecoration(labelText: 'نوع السند'),
                  items: [
                    for (final k in VoucherKind.values)
                      DropdownMenuItem<String>(
                          value: k.storageValue, child: Text(k.label)),
                  ],
                  onChanged: (value) => setState(() {
                    _kind = VoucherKind.values
                        .firstWhere((k) => k.storageValue == value);
                    _partyId = null;
                  }),
                ),
                DropdownButtonFormField<bool>(
                  value: _partyVoucher,
                  decoration: const InputDecoration(
                      labelText: 'الجهة (طرفية أو بغير طرف)'),
                  items: const [
                    DropdownMenuItem<bool>(value: true, child: Text('طرفي')),
                    DropdownMenuItem<bool>(
                        value: false, child: Text('بغير طرف — حساب مباشر')),
                  ],
                  onChanged: (value) =>
                      setState(() => _partyVoucher = value ?? true),
                ),
                if (_partyVoucher)
                  DropdownButtonFormField<int>(
                    value: _partyId,
                    decoration: InputDecoration(
                        labelText: _kind.isReceipt
                            ? 'العميل (القبض على ذمم العملاء)'
                            : 'المورد (الصرف من ذمم الموردين)'),
                    items: [
                      for (final p in _sideParties)
                        DropdownMenuItem<int>(
                            value: p.id,
                            child: Text('${p.number} ${p.name}')),
                    ],
                    onChanged: (value) {
                      setState(() => _partyId = value);
                      _reloadOpenInvoices();
                    },
                  )
                else
                  DropdownButtonFormField<int>(
                    value: _directAccountId,
                    decoration: const InputDecoration(
                        labelText: 'الحساب المباشر (311 ضخ — 321 مسحوبات — 54x مصروف)'),
                    items: [
                      for (final a in directChoices)
                        DropdownMenuItem<int>(
                            value: a.id,
                            child: Text('${a.code} ${a.name}')),
                    ],
                    onChanged: (value) =>
                        setState(() => _directAccountId = value),
                  ),
                DropdownButtonFormField<int>(
                  value: _boxId,
                  decoration: const InputDecoration(
                      labelText: 'الصندوق — وعمله سند العملة'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) {
                    setState(() => _boxId = value);
                    _reloadOpenInvoices();
                  },
                ),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration:
                      const InputDecoration(labelText: 'التاريخ (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'المبلغ بوحدة صغرى'),
                ),
                if (box != null && !_currencyOf(box).isBase)
                  TextField(
                    controller: _fx,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText:
                            'لقطة الصرف مكبرة ×1,000,000 (مثال: 15000000 = 15)'),
                  ),
                if (_partyVoucher) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _proposeAutomatically,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('اقتراح المطابقة آلياً بالأقدمية'),
                    ),
                  ),
                  if (_allocations.isEmpty && _partyId != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          'لا فواتير مفتوحة لهذا الطرف بعملة الصندوق — المبلغ كله «رصيد مقدَّم»'),
                    ),
                  for (final a in _allocations)
                    ListTile(
                      dense: true,
                      title: Text(a.label),
                      subtitle: TextField(
                        controller: a.applied,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                            labelText: 'المطبَّق بوحدة صغرى'),
                      ),
                    ),
                  if (_allocations.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'المطبَّق ${formatMinorAmount(_appliedTotal)}'
                          ' — الفائض (رصيد مقدَّم) ${formatMinorAmount(unapplied < 0 ? 0 : unapplied)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                ],
                TextField(
                  controller: _narration,
                  decoration:
                      const InputDecoration(labelText: 'الوصف (اختياري)'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => _save(post: true),
                  child: const Text('حفظ وترحيل'),
                ),
              ],
            ),
    );
  }
}

/// نموذج تحويل بين صندوقين (س-91/س-16): قيد سطرين بلا وسيط (D-087
/// معتمد) والعملة واحدة على الطرفين — وحاجز القاعدة يمنع سالب المرسل
/// (منع السالب الموحد 05 §7-2) برسالته العربية.
class TransferEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const TransferEditScreen({super.key, required this.db});

  @override
  State<TransferEditScreen> createState() => _TransferEditScreenState();
}

class _TransferEditScreenState extends State<TransferEditScreen> {
  int? _fromBoxId;
  int? _toBoxId;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _narration = TextEditingController();

  /// لقطة صرف التحويل لغير الأساسية — الصندوقان بعملتهما الواحدة
  /// (D-087 معتمد) واللقطة لحظة العملية (F-122/D-082).
  final TextEditingController _fx = TextEditingController();

  List<CashBoxReportRow> _boxes = [];
  List<CurrencyRow> _currencies = [];
  List<String>? _errors;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    final currencies = await widget.db.currenciesOf();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _currencies = currencies;
      _fromBoxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _toBoxId = _boxes.length < 2 ? null : _boxes[1].boxId;
    });
  }

  CashBoxReportRow? get _fromBox {
    for (final b in _boxes) {
      if (b.boxId == _fromBoxId) return b;
    }
    return null;
  }

  CurrencyRow _currencyOf(CashBoxReportRow box) {
    for (final c in _currencies) {
      if (c.code == box.currencyCode) return c;
    }
    return _currencies.first;
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _narration.dispose();
    _fx.dispose();
    super.dispose();
  }

  CashTransferDraft _buildDraft() {
    final from = _fromBox;
    return CashTransferDraft(
      dateText: _date.text.trim(),
      fromBoxId: _fromBoxId ?? 0,
      toBoxId: _toBoxId ?? 0,
      // العملة الواحدة على الطرفين من عملة صندوق «من» — والتحويل بين
      // عملتين مؤجل (D-087 معتمد) فيمسكه المدقق برسالته.
      currencyId: from == null ? 1 : _currencyOf(from).id,
      fxRate: from == null
          ? baseCurrencyFxRate
          : (_currencyOf(from).isBase
              ? baseCurrencyFxRate
              : (int.tryParse(_fx.text.trim()) ?? 0)),
      amountDocMinor: int.tryParse(_amount.text.trim()) ?? 0,
      narration:
          _narration.text.trim().isEmpty ? null : _narration.text.trim(),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final draft = _buildDraft();
    final structure = validateCashTransferStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure)
              describeCashTransferValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final id = await widget.db.createCashTransferDraft(draft);
      await widget.db.postCashTransfer(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CashTransferValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeCashTransferValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = ['$e'];
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحويل بين صناديق')),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _errors!)
                            Text(e,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer)),
                        ],
                      ),
                    ),
                  ),
                DropdownButtonFormField<int>(
                  value: _fromBoxId,
                  decoration: const InputDecoration(
                      labelText: 'من صندوق (المرسل)'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) => setState(() => _fromBoxId = value),
                ),
                DropdownButtonFormField<int>(
                  value: _toBoxId,
                  decoration: const InputDecoration(
                      labelText: 'إلى صندوق (المستلم)'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) => setState(() => _toBoxId = value),
                ),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration:
                      const InputDecoration(labelText: 'التاريخ (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'المبلغ بوحدة صغرى'),
                ),
                if (_fromBox != null && !_currencyOf(_fromBox!).isBase)
                  TextField(
                    controller: _fx,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText:
                            'لقطة الصرف مكبرة ×1,000,000 (مثال: 15000000 = 15)'),
                  ),
                TextField(
                  controller: _narration,
                  decoration:
                      const InputDecoration(labelText: 'الوصف (اختياري)'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('حفظ وترحيل'),
                ),
              ],
            ),
    );
  }
}

/// نموذج تسوية صندوق (س-92/س-17): عجزاً أو زيادةً على 57 (الحساب
/// الواحد — س8) بسبب نصي إلزامي — والفراغ يرفضه المدقق برسالته ذاتها
/// (درس س2: الحكم بالنص الحرفي لرسالة المدقق).
class AdjustmentEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const AdjustmentEditScreen({super.key, required this.db});

  @override
  State<AdjustmentEditScreen> createState() => _AdjustmentEditScreenState();
}

class _AdjustmentEditScreenState extends State<AdjustmentEditScreen> {
  int? _boxId;
  CashAdjustmentDirection _direction = CashAdjustmentDirection.shortage;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  List<CashBoxReportRow> _boxes = [];
  List<String>? _errors;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
    });
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  CashAdjustmentDraft _buildDraft() {
    return CashAdjustmentDraft(
      dateText: _date.text.trim(),
      cashBoxId: _boxId ?? 0,
      direction: _direction,
      amountDocMinor: int.tryParse(_amount.text.trim()) ?? 0,
      reason: _reason.text,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final draft = _buildDraft();
    final structure = validateCashAdjustmentStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure)
              describeCashAdjustmentValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final id = await widget.db.createCashAdjustmentDraft(draft);
      await widget.db.postCashAdjustment(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CashAdjustmentValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors)
            describeCashAdjustmentValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = ['$e'];
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسوية صندوق')),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _errors!)
                            Text(e,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer)),
                        ],
                      ),
                    ),
                  ),
                DropdownButtonFormField<int>(
                  value: _boxId,
                  decoration:
                      const InputDecoration(labelText: 'الصندوق'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) => setState(() => _boxId = value),
                ),
                DropdownButtonFormField<String>(
                  value: _direction.storageValue,
                  decoration: const InputDecoration(
                      labelText: 'اتجاه الفرق (عجزاً أو زيادةً — على 57)'),
                  items: [
                    for (final d in CashAdjustmentDirection.values)
                      DropdownMenuItem<String>(
                          value: d.storageValue, child: Text(d.label)),
                  ],
                  onChanged: (value) => setState(() {
                    _direction = CashAdjustmentDirection.values
                        .firstWhere((d) => d.storageValue == value);
                  }),
                ),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration:
                      const InputDecoration(labelText: 'التاريخ (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'قيمة الفرق بوحدة صغرى'),
                ),
                TextField(
                  controller: _reason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'سبب الفرق (إلزامي — يوثق بالمستند)'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('حفظ وترحيل'),
                ),
              ],
            ),
    );
  }
}
