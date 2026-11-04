import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'print_service.dart';
import 'input_formatters.dart';
import 'reports_screen.dart' show formatMinorAmount;
import 'currency_display.dart';
import 'hijri_display.dart';

/// طباعة سند أو تحويل أو تسوية (D-016، دفعة إغلاق النواة س37) — قسيمة
/// A5 طولية (D-101 معروض) ببيانات الصف المعروضة حصراً، ومشاركتها
/// بنافذة النظام، والفشل رسالة لا صمت.
Future<void> _printVoucherDoc(
  BuildContext context, {
  required String title,
  required List<(String, String)> headerPairs,
  required String amountLabel,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildDocumentPdf(
      title: title,
      headerPairs: headerPairs,
      columns: const [],
      rows: const [],
      footerPairs: [('المبلغ', amountLabel)],
      format: resolvePageFormat(docKind: 'voucher'),
    );
    if (!context.mounted) return;
    await sharePdfBytes(bytes, '$title.pdf');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر توليد الطباعة — $e')),
    );
  }
}

/// زر طباعة صف السند — بجوار المبلغ في نفس السطر.
Widget _voucherPrintTrailing({
  required VoidCallback onPrint,
  required String amountText,
}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'طباعة / PDF',
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: onPrint,
        ),
        Text(amountText),
      ],
    );

/// شاشة السندات والصناديق المالية — دفعة (6-ج) واجهات الإدخال
/// (س-89..س-94، D-094..D-096 معروض): ثلاث تبويبات قراءة لحظية من
/// المرحّل (السندات الطرفية وغير الطرفية، التحويلات، التسويات) ونماذج
/// إنشاء يفوض الحكم كله للمحرك — المدقق البنيوي ثم الفحوص المحركية
/// ثم حواجز القاعدة (منع السالب الموحد) — والواجهة تعرض رسائل المدقق
/// العربية كما هي.
///
/// درس CI (س36): زر الإنشاء زرٌّ واحد في Scaffold الأم يتبدل نصه وعمله
/// بالتبويب النشط — لا FAB داخل كل تبويب فتتكدس الأزرار في
/// PageView ويتحجب بعضها بعضاً في الاختبارات ولا يُضرب.
/// ودفعة الإغلاق (س37): زر طباعة / PDF بكل صف (D-016).
class VouchersScreen extends StatefulWidget {
  final DiqqahDatabase db;
  const VouchersScreen({super.key, required this.db});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  final GlobalKey<_VouchersTabState> _voucherTabKey =
      GlobalKey<_VouchersTabState>();
  final GlobalKey<_TransfersTabState> _transfersTabKey =
      GlobalKey<_TransfersTabState>();
  final GlobalKey<_AdjustmentsTabState> _adjustmentsTabKey =
      GlobalKey<_AdjustmentsTabState>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openCreate() async {
    final Widget target = switch (_tabs.index) {
      0 => VoucherEditScreen(db: widget.db),
      1 => TransferEditScreen(db: widget.db),
      _ => AdjustmentEditScreen(db: widget.db),
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
    // بعد العودة من النموذج تُحدّث قائمة التبويب المنشئ حصراً
    switch (_tabs.index) {
      case 0:
        _voucherTabKey.currentState?.reload();
      case 1:
        _transfersTabKey.currentState?.reload();
      default:
        _adjustmentsTabKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('السندات'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'السندات'),
            Tab(text: 'التحويلات'),
            Tab(text: 'التسويات'),
          ],
        ),
      ),
      // زر واحد لا ثلاثة — والنص يتبدل بالتبويب (درس CI أعلاه)
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: _openCreate,
          icon: const Icon(Icons.add_circle_outline),
          label: Text(switch (_tabs.index) {
            0 => 'سند جديد',
            1 => 'تحويل جديد',
            _ => 'تسوية جديدة',
          }),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _VouchersTab(key: _voucherTabKey, db: widget.db),
          _TransfersTab(key: _transfersTabKey, db: widget.db),
          _AdjustmentsTab(key: _adjustmentsTabKey, db: widget.db),
        ],
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

/// تبويب السندات (قبض/دفع — س-12..س-15، D-105) — القائمة الطرفية وغير الطرفية
/// معاً والمميزان بحقليهما.
class _VouchersTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _VouchersTab({super.key, required this.db});

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

  /// إعادة التحميل من الأم (بعد العودة من نموذج إنشاء)
  void reload() => _reload();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
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
                  trailing: _voucherPrintTrailing(
                    amountText:
                        '${formatMinorAmount(row.amountDocMinor)}'
                        ' ${row.currencyCode}',
                    onPrint: () => _printVoucherDoc(
                      context,
                      title: row.displayLabel,
                      headerPairs: [
                        ('التاريخ', row.voucherDate),
                        ('النوع', VoucherKind.fromStorage(row.kind).label),
                        ('الحالة', row.stateLabel),
                        ('الجهة', row.counterpartLabel),
                        ('الصندوق', row.boxName),
                        if (row.narration != null &&
                            row.narration!.isNotEmpty)
                          ('البيان', row.narration!),
                      ],
                      amountLabel:
                          '${formatMinorAmount(row.amountDocMinor)} '
                              '${row.currencyCode}',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// تبويب التحويلات بين الصناديق (س-16/D-087 معتمد) — القيد بسطرين
/// «صندوق المستلم مدين / صندوق المرسل دائن» والقراءة تعرض الطرفين.
class _TransfersTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _TransfersTab({super.key, required this.db});

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

  /// إعادة التحميل من الأم (بعد العودة من نموذج إنشاء)
  void reload() => _reload();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
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
                  trailing: _voucherPrintTrailing(
                    amountText:
                        '${formatMinorAmount(row.amountDocMinor)}'
                        ' ${row.currencyCode}',
                    onPrint: () => _printVoucherDoc(
                      context,
                      title: row.displayLabel,
                      headerPairs: [
                        ('التاريخ', row.transferDate),
                        ('الحالة', row.stateLabel),
                        ('من صندوق', row.fromBoxName),
                        ('إلى صندوق', row.toBoxName),
                      ],
                      amountLabel:
                          '${formatMinorAmount(row.amountDocMinor)} '
                              '${row.currencyCode}',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// تبويب تسويات الصناديق (س-17/F-067) — الاتجاه والسبب الظاهران بالصف.
class _AdjustmentsTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _AdjustmentsTab({super.key, required this.db});

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

  /// إعادة التحميل من الأم (بعد العودة من نموذج إنشاء)
  void reload() => _reload();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
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
                  trailing: _voucherPrintTrailing(
                    amountText:
                        '${formatMinorAmount(row.amountDocMinor)}'
                        ' ${row.currencyCode}',
                    onPrint: () => _printVoucherDoc(
                      context,
                      title: row.displayLabel,
                      headerPairs: [
                        ('التاريخ', row.adjustmentDate),
                        ('الحالة', row.stateLabel),
                        ('الصندوق', row.boxName),
                        ('الاتجاه', row.directionLabel),
                        ('السبب', row.reason),
                      ],
                      amountLabel:
                          '${formatMinorAmount(row.amountDocMinor)} '
                              '${row.currencyCode}',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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

/// نموذج سند قبض/دفع (س-89/س-90، D-105): الطرفي بمطابقاته «يدوياً أو آلياً
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

  /// بوابة التحميل — فقيم الحقول الابتدائية جاهزة قبل أول بناء
  /// (نمط items_screen الموثق بالـinitialValue).
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ الافتراضي بتاريخ اليوم قابلاً للتعديل —
    // ويذهب جذر درس س-90 (حفظ بتاريخ فارغ) — والنماذج الثلاثة.
    _date.text = todayIsoDate();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    final parties = await widget.db.select(widget.db.parties).get();
    final accounts = await widget.db.allLedgerAccounts();
    final currencies = await widget.db.currenciesOf();
    // أرصدة الأطراف الجارية (س-105/D-106) — قراءة خالصة من تقرير الذمم.
    final balances = await widget.db.receivablesPayablesReport();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _parties = parties.where((p) => p.isActive).toList();
      _accounts = accounts.where((a) => a.isActive && a.isLeaf).toList();
      _currencies = currencies;
      _partyBalances
        ..clear()
        ..addEntries([for (final r in balances) MapEntry(r.partyId, r)]);
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _loaded = true;
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

  /// أطراف جهة السند: القبض عملاء والدفع موردون (خريطة الذمم 05 §5).
  List<Party> get _sideParties => _parties
      .where((p) =>
          p.kind == (_kind.isReceipt ? 'customer' : 'supplier'))
      .toList();

  /// رصيد الطرف الجاري (س-105/D-106) — من تقرير الذمم ذاته (المرحّل
  /// حصراً) — بالاتجاهين: هم يدينون لنا أو نحن ندن له.
  final Map<int, ReceivablesPayablesRow> _partyBalances = {};

  /// صياغة الرصيد المعروضة: «50,000 لنا» أو «نحن ندن له بـ20,000» —
  /// والطرف بلا ذمة صف «بلا ذمة بعد» (الصفر يخرج من التقرير أصلاً).
  String _partyBalanceText(int partyId) {
    final row = _partyBalances[partyId];
    if (row == null) return 'بلا ذمة بعد';
    return switch (row.direction) {
      PartyBalanceDirection.theyOweUs =>
        'لنا ${formatMinorAmount(row.amountMinor)}',
      PartyBalanceDirection.weOweThem =>
        'نحن ندن له بـ${formatMinorAmount(row.amountMinor)}',
    };
  }

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
                ' (${displayDate(c.dateText)})',
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
    // D-102: الحقل مفصول أثناء الكتابة — والقراءة تنزع الفواصل
    // (كسر CI س39: int.tryParse على «30,000» صفر فتوقف المقترح بلا تعبئة)
    final amount = parseGroupedInt(_amount.text.trim());
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
          // مفصولاً (D-102): التعبئة البرمجية تعرض بالفواصل كالكتابة.
          a.applied.text = groupDigits(p.appliedDocMinor);
        }
      }
    }
    setState(() {});
  }

  int get _appliedTotal {
    var total = 0;
    for (final a in _allocations) {
      total += parseGroupedInt(a.applied.text.trim());
    }
    return total;
  }

  int get _amountValue => parseGroupedInt(_amount.text.trim());

  /// لقطة صرف السند — عملة الصندوق الأساسية لقطتها المحايدة (D-082)
  /// وغيرها من الحقل، والفراغ صفر يلتقطه المدقق برسالته.
  int get _fxValue {
    final box = _box;
    if (box == null) return baseCurrencyFxRate;
    return _currencyOf(box).isBase
        ? baseCurrencyFxRate
        : (parseGroupedInt(_fx.text.trim()));
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
            // D-102: الحقل مفصول — والقراءة تنزع الفواصل (كسر CI جولة
            // 114: رسالة المدقق الحرفية «مطبَّق الفاتورة رقم 2 يجب أن
            // يكون أكبر من صفر» كشفتها بطاقة الرسائل المعادة للنافذة)
            appliedDocMinor: parseGroupedInt(a.applied.text.trim()),
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
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text('سند جديد')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
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
                  initialValue: _kind.storageValue,
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
                  initialValue: _partyVoucher,
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
                    initialValue: _partyId,
                    decoration: InputDecoration(
                        labelText: _kind.isReceipt
                            ? 'العميل (القبض على ذمم العملاء)'
                            : 'المورد (الدفع من ذمم الموردين)'
                                ' — D-105'),
                    items: [
                      for (final p in _sideParties)
                        DropdownMenuItem<int>(
                            value: p.id,
                            child: Text(
                                '${p.number} ${p.name} — '
                                '${_partyBalanceText(p.id)}')),
                    ],
                    onChanged: (value) {
                      setState(() => _partyId = value);
                      _reloadOpenInvoices();
                    },
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: _directAccountId,
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
                  initialValue: _boxId,
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
                if (_box != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      // س-121 (D-116): رصيد الصندوق المختار قبل الحفظ —
                      // بنفس سطر الفاتورة النقدية (س-105/D-106) — بلفظ
                      // المالك «رصيد الصندوق في السندات غير موجود»،
                      // ويتجدد مع تبديل الصندوق (القائمة محملة بأرصدتها).
                      'الرصيد الآن: ${formatMinorAmount(_box!.balanceBaseMinor)} $kBaseCurrencySymbol',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'المبلغ بوحدة صغرى'),
                ),
                if (_partyVoucher && _partyId != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'رصيد حسابه الجاري: ${_partyBalanceText(_partyId!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (box != null && !_currencyOf(box).isBase)
                  TextField(
                    controller: _fx,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
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
                          ThousandsSeparatorInputFormatter()
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

  /// بوابة التحميل — نمط initialValue الموثق.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ الافتراضي — نموذج التحويل.
    _date.text = todayIsoDate();
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
      _loaded = true;
    });
  }

  CashBoxReportRow? get _fromBox {
    for (final b in _boxes) {
      if (b.boxId == _fromBoxId) return b;
    }
    return null;
  }

  CashBoxReportRow? get _toBox {
    for (final b in _boxes) {
      if (b.boxId == _toBoxId) return b;
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
              : parseGroupedInt(_fx.text.trim())),
      amountDocMinor: parseGroupedInt(_amount.text.trim()),
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
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text('تحويل بين صناديق')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
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
                  initialValue: _fromBoxId,
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
                if (_fromBox != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      // س-122 (D-117): رصيد الصندوقين قبل التحويل —
                      // إضافة المستشار المعتمدة ببوابة دفعة (9).
                      'الرصيد الآن: ${formatMinorAmount(_fromBox!.balanceBaseMinor)} $kBaseCurrencySymbol',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                DropdownButtonFormField<int>(
                  initialValue: _toBoxId,
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
                if (_toBox != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      // س-122 (D-117): رصيد المستلم قبل التحويل —
                      // موازن سطر المرسل أعلاه.
                      'الرصيد الآن: ${formatMinorAmount(_toBox!.balanceBaseMinor)} $kBaseCurrencySymbol',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'المبلغ بوحدة صغرى'),
                ),
                if (_fromBox != null && !_currencyOf(_fromBox!).isBase)
                  TextField(
                    controller: _fx,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
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

  /// بوابة التحميل — نمط initialValue الموثق.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ الافتراضي — نموذج التسوية.
    _date.text = todayIsoDate();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _loaded = true;
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
      amountDocMinor: parseGroupedInt(_amount.text.trim()),
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
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text('تسوية صندوق')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
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
                  initialValue: _boxId,
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
                  initialValue: _direction.storageValue,
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
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
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
