import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'print_service.dart';
import 'reports_screen.dart' show formatMinorAmount;

/// شاشة الفواتير — دفعة (6-ج) واجهات الإدخال (س-86..س-88، D-094 معروض):
/// الوحدة مفتوحة من الهيكلية بعد اعتماد المالك لبوابة (6-ب) بلفظه
/// «اعتمدها» (س36)، والقائمة قراءة لحظية من المرحّل حصراً (لا جداول
/// تجميع — D-089)، والمدى والفلتر تحسينان للعرض لا قراراً — والمدى
/// المُدخل يُدقق قبل لمس القاعدة (D-077).
class InvoicesScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const InvoicesScreen({super.key, required this.db});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();

  /// قيمة التخزين لنوع الفلتر — null يعني الكل.
  String? _kind;
  Future<List<InvoiceListRow>>? _rows;

  static final List<(String?, String)> _kindChoices = [
    (null, 'كل الأنواع'),
    (InvoiceKind.purchase.storageValue, InvoiceKind.purchase.label),
    (InvoiceKind.sale.storageValue, InvoiceKind.sale.label),
    (InvoiceKind.saleReturn.storageValue, InvoiceKind.saleReturn.label),
    (InvoiceKind.purchaseReturn.storageValue, InvoiceKind.purchaseReturn.label),
  ];

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
    // المدى الفاسد يرمي داخل الـFuture فيُعرض بلسان المدقق من الـFutureBuilder
    // — لا صمت ولا انهيار (D-077: المدقق حرس أول).
    setState(() {
      _rows = widget.db.invoicesListReport(
        fromText: _from.text.trim(),
        toText: _to.text.trim(),
        kindStorageValue: _kind,
      );
    });
  }

  void _openNew() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => InvoiceEditScreen(db: widget.db)),
    );
    if (created == true) _reload();
  }

  void _openDetail(int invoiceId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceDetailScreen(db: widget.db, invoiceId: invoiceId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الفواتير')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('فاتورة جديدة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _kind,
                        decoration:
                            const InputDecoration(labelText: 'النوع'),
                        items: [
                          for (final (value, label) in _kindChoices)
                            DropdownMenuItem<String>(
                                value: value, child: Text(label)),
                        ],
                        onChanged: (value) => setState(() => _kind = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _reload, child: const Text('عرض')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InvoiceListRow>>(
              future: _rows,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'لا فواتير بعد — أضف أول فاتورة بزر «فاتورة جديدة»',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final row in rows)
                      ListTile(
                        title: Text(row.displayLabel),
                        subtitle: Text(
                            '${row.invoiceDate}'
                            ' · ${row.counterpartLabel}'
                            ' · ${row.stateLabel}'),
                        trailing: Text(
                            '${formatMinorAmount(row.totalDocMinor)}'
                            ' ${row.currencyCode}'),
                        onTap: () => _openDetail(row.id),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// سطر بند في نموذج الإدخال — تحكمات النص أعضاء الحالة وتُفكك عند
/// التفكيك (عرف الشاشات)، والصنف والكمية والسعر والخصم حقوله.
class _LineUi {
  int? itemId;
  final TextEditingController qty = TextEditingController();
  final TextEditingController price = TextEditingController();
  final TextEditingController discount = TextEditingController();

  void dispose() {
    qty.dispose();
    price.dispose();
    discount.dispose();
  }
}

/// نموذج فاتورة موحد للأنواع الأربعة (س-86/س-87/س-88): «نقدي يطلب
/// صندوقاً والآجل يطلب طرفاً» — والنقدية استدلال من وجود الصندوق حرفاً
/// (InvoiceDraft.isCash)، والمردود يطلب أصلياً (س-05/س-11)، والإدخال
/// بالوحدة الأساسية حصراً في م1 (09 §2). المحرك حرس الحدود: مدقق
/// البنية قبل الكتابة وفحوص الترحيل بعدها والقاعدة ثالثاً — والواجهة
/// تعرض رسائل المدقق العربية كما هي فتُرى سبب الرفض لا خطأ غامضاً.
class InvoiceEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const InvoiceEditScreen({super.key, required this.db});

  @override
  State<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  InvoiceKind _kind = InvoiceKind.purchase;

  /// النقدية استدلال من الصندوق — هذا المبدّل يحدد أي الحقلين يظهر
  /// (صندوق أو طرف) ولا يغذّي المسودة بنوع مستقل أبداً.
  bool _isCash = true;
  int? _boxId;
  int? _partyId;
  int? _warehouseId;
  int _currencyId = 1;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _due = TextEditingController();
  final TextEditingController _fxRate = TextEditingController();
  final TextEditingController _discount = TextEditingController();
  final TextEditingController _original = TextEditingController();
  final TextEditingController _narration = TextEditingController();

  final List<_LineUi> _lines = [_LineUi()];

  List<CashBoxReportRow> _boxes = [];
  List<Party> _parties = [];
  List<WarehouseRow> _warehouses = [];
  List<CurrencyRow> _currencies = [];
  List<Item> _items = [];
  Map<int, String> _unitNames = {};

  List<String>? _errors;
  bool _busy = false;

  /// بوابة التحميل: النموذج لا يُبنى قبل اكتمال القوائم الأولية —
  /// فقيم الحقول الابتدائية (initialValue) جاهزة قبل أول بناء (درس
  /// إبادة DropdownButtonFormField.value في Flutter الجديد: النماذج
  /// القديمة كله بها initialValue وitems_screen نمطها الموثق).
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final boxes = (await widget.db.cashBoxesReport())
        .where((b) => b.isActive)
        .toList();
    final warehouses =
        (await widget.db.warehousesOf()).where((w) => w.isActive).toList();
    final parties = await widget.db.select(widget.db.parties).get();
    final currencies = await widget.db.currenciesOf();
    final items = await widget.db.select(widget.db.items).get();
    final units = await widget.db.select(widget.db.units).get();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _warehouses = warehouses;
      _parties = parties.where((p) => p.isActive).toList();
      _currencies = currencies;
      _items = items.where((i) => i.isActive).toList();
      _unitNames = {for (final u in units) u.id: u.name};
      // الافتراضي المعقول لصاحب المحل: أول صندوق وأول مستودع نشط.
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _warehouseId = _warehouses.isEmpty ? null : _warehouses.first.id;
      final base =
          _currencies.where((c) => c.isBase).toList();
      _currencyId = base.isEmpty ? 1 : base.first.id;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _date.dispose();
    _due.dispose();
    _fxRate.dispose();
    _discount.dispose();
    _original.dispose();
    _narration.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// الأطراف المناسبة لجهة الفاتورة: البيع ومردوده عملاء والشراء
  /// ومردوده موردون (خريطة الترحيل 05 §6 — الذمة على 112 أو 211).
  List<Party> get _sideParties => _parties
      .where((p) =>
          p.kind == (_kind.isSalesSide ? 'customer' : 'supplier'))
      .toList();

  /// الوحدة الأساسية للصنف المختار — إدخال م1 بها حصراً.
  int? _baseUnitIdOf(int? itemId) {
    if (itemId == null) return null;
    for (final i in _items) {
      if (i.id == itemId) return i.baseUnitId;
    }
    return null;
  }

  /// لقطة الصرف: الأساسية لقطتها المحايدة (D-082) وغيرها من الحقل
  /// — والفراغ صفر يلتقطه مدقق البنية برسالته (InvoiceFxRateInvalid).
  int get _fx => _currencyId == 1
      ? baseCurrencyFxRate
      : (int.tryParse(_fxRate.text.trim()) ?? 0);

  int _parsed(TextEditingController c) =>
      int.tryParse(c.text.trim()) ?? 0;

  InvoiceDraft _buildDraft() {
    final lines = [
      for (final l in _lines)
        InvoiceLineDraft(
          itemId: l.itemId ?? 0,
          unitId: _baseUnitIdOf(l.itemId) ?? 0,
          qtyBase: _parsed(l.qty),
          unitPriceMinor: _parsed(l.price),
          discountMinor: _parsed(l.discount),
        ),
    ];
    return InvoiceDraft(
      kind: _kind,
      dateText: _date.text.trim(),
      dueDateText:
          _due.text.trim().isEmpty ? null : _due.text.trim(),
      partyId: _isCash ? null : _partyId,
      cashBoxId: _isCash ? _boxId : null,
      warehouseId: _warehouseId,
      currencyId: _currencyId,
      fxRate: _fx,
      discountRate: _parsed(_discount),
      originalInvoiceId: _kind.isReturn
          ? (int.tryParse(_original.text.trim()))
          : null,
      narration:
          _narration.text.trim().isEmpty ? null : _narration.text.trim(),
      lines: lines,
    );
  }

  Future<void> _save({required bool post}) async {
    if (_busy) return;
    final draft = _buildDraft();
    // الحرس الأول بالواجهة — مدقق البنية النقي ذاته الذي يمسك المحرك
    // فتُعرض الأخطاء العربية ذاتها مرتين متسقتين لا اختلافَ بينهما.
    final structure = validateInvoiceDraftStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure) describeInvoiceValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final id = await widget.db.createInvoiceDraft(draft);
      if (post) {
        await widget.db.postInvoice(id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on InvoiceValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeInvoiceValidationError(err)
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
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text('فاتورة جديدة')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final showFx = _currencyId != 1;
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة جديدة')),
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
                  initialValue: _kind.storageValue,
                  decoration:
                      const InputDecoration(labelText: 'نوع الفاتورة'),
                  items: [
                    for (final k in InvoiceKind.values)
                      DropdownMenuItem<String>(
                          value: k.storageValue, child: Text(k.label)),
                  ],
                  onChanged: (value) => setState(() => _kind = InvoiceKind
                      .values
                      .firstWhere((k) => k.storageValue == value)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _date,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                            labelText: 'التاريخ (YYYY-MM-DD)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _due,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                            labelText: 'الاستحقاق (اختياري)'),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<bool>(
                  initialValue: _isCash,
                  decoration: const InputDecoration(
                      labelText: 'النقدية (نقدي يطلب صندوقاً — والآجل طرفاً)'),
                  items: const [
                    DropdownMenuItem<bool>(value: true, child: Text('نقدي')),
                    DropdownMenuItem<bool>(value: false, child: Text('آجل')),
                  ],
                  onChanged: (value) => setState(() => _isCash = value ?? true),
                ),
                if (_isCash)
                  DropdownButtonFormField<int>(
                    initialValue: _boxId,
                    decoration: const InputDecoration(
                        labelText: 'صندوق النقدية'),
                    items: [
                      for (final b in _boxes)
                        DropdownMenuItem<int>(
                            value: b.boxId,
                            child: Text('${b.name} (${b.currencyCode})')),
                    ],
                    onChanged: (value) => setState(() => _boxId = value),
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: _partyId,
                    decoration: InputDecoration(
                        labelText: _kind.isSalesSide
                            ? 'العميل (الآجل يطلب طرفاً)'
                            : 'المورد (الآجل يطلب طرفاً)'),
                    items: [
                      for (final p in _sideParties)
                        DropdownMenuItem<int>(
                            value: p.id,
                            child: Text('${p.number} ${p.name}')),
                    ],
                    onChanged: (value) => setState(() => _partyId = value),
                  ),
                DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(
                      labelText: 'المستودع (للبضاعة — الخدمة بلا مستودع)'),
                  items: [
                    for (final w in _warehouses)
                      DropdownMenuItem<int>(
                          value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (value) => setState(() => _warehouseId = value),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _currencyId,
                  decoration: const InputDecoration(
                      labelText: 'عملة المستند'),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem<int>(
                          value: c.id, child: Text('${c.code} ${c.name}')),
                  ],
                  onChanged: (value) => setState(() {
                    _currencyId = value ?? 1;
                  }),
                ),
                if (showFx)
                  TextField(
                    controller: _fxRate,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText:
                            'لقطة الصرف مكبرة ×1,000,000 (مثال: 15000000 = 15)'),
                  ),
                if (_kind.isReturn)
                  TextField(
                    controller: _original,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText:
                            'معرف الفاتورة الأصلية (إلزامي للمردود)'),
                  ),
                TextField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'خصم الفاتورة نسبةً 0..100 (اختياري)'),
                ),
                TextField(
                  controller: _narration,
                  decoration: const InputDecoration(
                      labelText: 'الوصف (اختياري)'),
                ),
                const SizedBox(height: 12),
                Text('البنود — الإدخال بالوحدة الأساسية حصراً (م1)',
                    style: Theme.of(context).textTheme.titleMedium),
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _lines.add(_LineUi())),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة بند'),
                  ),
                ),
                _totalsCard(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _save(post: true),
                        child: const Text('حفظ وترحيل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _save(post: false),
                        child: const Text('حفظ كمسودة'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    final unitId = _baseUnitIdOf(line.itemId);
    final unitName =
        unitId == null ? '' : (_unitNames[unitId] ?? '');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: line.itemId,
              decoration: const InputDecoration(labelText: 'الصنف'),
              items: [
                for (final it in _items)
                  DropdownMenuItem<int>(
                      value: it.id,
                      child: Text(
                          '${it.sku} ${it.name}'
                          '${it.kind == 'service' ? ' (خدمة)' : ''}')),
              ],
              onChanged: (value) => setState(() => line.itemId = value),
            ),
            if (unitName.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('الوحدة: $unitName (الأساسية)'),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.qty,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration:
                        const InputDecoration(labelText: 'الكمية'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'سعر الوحدة بوحدة صغرى'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.discount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'خصم السطر (اختياري)'),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف البند',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _lines.length <= 1
                      ? null
                      : () => setState(() {
                          _lines[index].dispose();
                          _lines.removeAt(index);
                        }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// المجاميع اللحظية بحساب المجال ذاته (computeInvoiceTotals) — تظهر
  /// حين تكتمل المدخلات فترى الإجمالي قبل الحفظ، وصمتها لا خطأ.
  Widget _totalsCard() {
    try {
      final totals = computeInvoiceTotals(_buildDraft());
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'المجموع ${formatMinorAmount(totals.subtotalDocMinor)}'
            ' · الخصم ${formatMinorAmount(totals.discountDocMinor)}'
            ' · الإجمالي ${formatMinorAmount(totals.totalDocMinor)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

/// تفاصيل فاتورة — قراءة حصراً (س-88): التسمية المعروضة بحساب المجال
/// (invoiceDisplayLabel) والحالة والسطور بأسعارها والمجاميع كما خُزنت.
/// ودفعة الإغلاق (س37): زرا الطباعة والمشاركة (D-016) — قسيمة A5
/// طولية (D-101 معروض) تُبنى من المستند وسطوره وخريطة أسماء الأصناف.
class InvoiceDetailScreen extends StatelessWidget {
  final DiqqahDatabase db;
  final int invoiceId;

  const InvoiceDetailScreen({
    super.key,
    required this.db,
    required this.invoiceId,
  });

  /// توليد قسيمة الفاتورة ومشاركتها بنافذة النظام — البيانات تُجلب
  /// هنا حصراً (لا تعتمد على حالة الشاشة)، والفشل رسالة لا صمت.
  Future<void> _sharePrintout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final invoice = await db.invoiceById(invoiceId);
      final lines = await db.invoiceLines(invoiceId);
      if (invoice == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('لا فاتورة بهذا المعرف')),
        );
        return;
      }
      final items = await db.select(db.items).get();
      final itemNames = <int, String>{
        for (final item in items) item.id: item.name,
      };
      final bytes = await buildDocumentPdf(
        title: invoiceDisplayLabel(invoice),
        headerPairs: [
          ('التاريخ', invoice.invoiceDate),
          ('الحالة', InvoiceState.fromStorage(invoice.state).label),
          if (invoice.narration != null && invoice.narration!.isNotEmpty)
            ('البيان', invoice.narration!),
        ],
        columns: const ['الصنف', 'الكمية', 'سعر الوحدة', 'صافي السطر'],
        rows: [
          for (final line in lines)
            [
              itemNames[line.itemId] ?? 'صنف #${line.itemId}',
              '${line.qtyBase}',
              formatMinorAmount(line.unitPriceMinor),
              formatMinorAmount(line.lineTotalDocMinor),
            ],
        ],
        footerPairs: [
          (
            'الإجمالي',
            '${formatMinorAmount(invoice.totalDocMinor)} '
                '(${invoice.currencyId == 1 ? 'بالأساسية' : 'بعملة المستند'})',
          ),
          ('المكافئ الأساسي', formatMinorAmount(invoice.totalBaseMinor)),
        ],
        format: resolvePageFormat(docKind: 'invoice'),
      );
      if (!context.mounted) return;
      await sharePdfBytes(
          bytes, '${invoiceDisplayLabel(invoice)}.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الفاتورة'),
        actions: [
          IconButton(
            tooltip: 'مشاركة PDF',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _sharePrintout(context),
          ),
          IconButton(
            tooltip: 'طباعة مباشرة',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              // نفس توليد المشاركة ثم حوار الطباعة — والمنصة غير
              // الداعمة تُغلف برسالتها (D-101 معروض).
              final invoice = await db.invoiceById(invoiceId);
              final lines = await db.invoiceLines(invoiceId);
              if (invoice == null || !context.mounted) return;
              final items = await db.select(db.items).get();
              final itemNames = <int, String>{
                for (final item in items) item.id: item.name,
              };
              final bytes = await buildDocumentPdf(
                title: invoiceDisplayLabel(invoice),
                headerPairs: [
                  ('التاريخ', invoice.invoiceDate),
                  ('الحالة', InvoiceState.fromStorage(invoice.state).label),
                  if (invoice.narration != null &&
                      invoice.narration!.isNotEmpty)
                    ('البيان', invoice.narration!),
                ],
                columns: const ['الصنف', 'الكمية', 'سعر الوحدة', 'صافي السطر'],
                rows: [
                  for (final line in lines)
                    [
                      itemNames[line.itemId] ?? 'صنف #${line.itemId}',
                      '${line.qtyBase}',
                      formatMinorAmount(line.unitPriceMinor),
                      formatMinorAmount(line.lineTotalDocMinor),
                    ],
                ],
                footerPairs: [
                  (
                    'الإجمالي',
                    '${formatMinorAmount(invoice.totalDocMinor)} '
                        '(${invoice.currencyId == 1 ? 'بالأساسية' : 'بعملة المستند'})',
                  ),
                  (
                    'المكافئ الأساسي',
                    formatMinorAmount(invoice.totalBaseMinor),
                  ),
                ],
                format: resolvePageFormat(docKind: 'invoice'),
              );
              if (!context.mounted) return;
              await printPdfBytes(context, bytes);
            },
          ),
        ],
      ),
      body: FutureBuilder<InvoiceDocument?>(
        future: db.invoiceById(invoiceId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final invoice = snapshot.data;
          if (invoice == null) {
            return const Center(child: Text('لا فاتورة بهذا المعرف'));
          }
          return FutureBuilder<List<InvoiceLineDocument>>(
            future: db.invoiceLines(invoiceId),
            builder: (context, linesSnapshot) {
              if (!linesSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final lines = linesSnapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  ListTile(
                    title: Text(invoiceDisplayLabel(invoice)),
                    subtitle: Text(
                        'التاريخ ${invoice.invoiceDate}'
                        ' · الحالة ${InvoiceState.fromStorage(invoice.state).label}'),
                  ),
                  ListTile(
                    title: Text('الإجمالي ${formatMinorAmount(invoice.totalDocMinor)}'
                        ' (${invoice.currencyId == 1 ? 'بالأساسية' : 'بعملة المستند'})'),
                    subtitle: Text(
                        'المكافئ الأساسي ${formatMinorAmount(invoice.totalBaseMinor)}'),
                  ),
                  const Divider(),
                  for (final line in lines)
                    ListTile(
                      title: Text(
                          'صنف #${line.itemId} — ${line.qtyBase} × ${formatMinorAmount(line.unitPriceMinor)}'),
                      subtitle: Text(
                          'صافي السطر ${formatMinorAmount(line.lineTotalDocMinor)}'),
                    ),
                  if (lines.isEmpty)
                    const ListTile(title: Text('لا بنود')),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
