import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'item_images.dart';
import 'item_media.dart';
import 'print_image_prefs.dart';
import 'print_service.dart';
import 'input_formatters.dart';
import 'reports_screen.dart' show formatMinorAmount;

/// قراءة بايتات صورة صنف للمطبوع — المسار النسبي مع جذر المجلد، والغائب
/// null فتعرض الصورة النائب البصري (س-127: بلا صورة يعرض النائب).
Future<Uint8List?> loadItemImageBytes(String? relativePath) async {
  final abs = ItemImagesStore.resolve(relativePath);
  if (abs == null || !File(abs).existsSync()) return null;
  try {
    return await File(abs).readAsBytes();
  } catch (_) {
    return null; // فاسد لا يكسر الطباعة أبداً — النائب مكانه
  }
}

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
///
/// D-110 (دفعة 8 س39): عقد التركيز لكل حقل كي يعمل الإدخال بلوحة
/// المفاتيح — Enter في أي حقل من البنود يضيف بنداً جديداً وينقل
/// المؤشر إليه، وTab ينتقل داخل البند وفي آخره يضيف بلا قفزة خارج
/// البطاقة، والسهم السفلي يضيف (س-109).
class _LineUi {
  int? itemId;

  /// هل عُبّئ السعر آلياً من بطاقة الصنف (س-108) — للمتابعة بعد
  /// تبديل جهة الفاتورة بالتعبئة الصحيحة لا كسر ما كتبه المستخدم يدوياً.
  bool priceAutoFilled = false;
  final TextEditingController qty = TextEditingController();
  final TextEditingController price = TextEditingController();
  final TextEditingController discount = TextEditingController();
  final FocusNode qtyFocus = FocusNode();
  final FocusNode priceFocus = FocusNode();
  final FocusNode discountFocus = FocusNode();

  void dispose() {
    qty.dispose();
    price.dispose();
    discount.dispose();
    qtyFocus.dispose();
    priceFocus.dispose();
    discountFocus.dispose();
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

  /// فهرس الباركودات (س-132 — D-126): البحث السريع والمطابقة الكاملة
  /// بقارئ البلوتوث.
  Map<int, List<String>> _barcodesByItem = {};

  /// خانة بحث بنود الفواتير السريعة (س-132): تطابق الاسم والكود
  /// والباركود، والرمز الكامل يجلب الصنف مباشرة.
  final TextEditingController _quickSearch = TextEditingController();

  /// المتاح لكل صنف من المستودع المختار (D-106 قراءة خالصة — س-108).
  Map<int, int> _stockAvail = {};

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
    // س-111 (D-108): التاريخ معبأ افتراضياً بتاريخ اليوم قابلاً للتعديل
    // — بلفظ المالك «حقل التاريخ في الفواتير أو السندات أو التقارير
    // يملأ افتراضياً بتاريخ اليوم» — ويذهب جذرو درس س-90.
    _date.text = todayIsoDate();
    // س-120 (D-115): المجاميع وإجمالي السطر تتجدد مع كل ضغطة —
    // مستمعو الحقول يستدعون _touch فتُعاد البطاقات لحظياً.
    _discount.addListener(_touch);
    for (final l in _lines) {
      _listenLine(l);
    }
    _load();
  }

  /// تحديث لحظي أثناء الكتابة (س-120/D-115) — كانت بطاقة المجاميع
  /// تتجدد عند تغيّرات القوائم حصراً لا مع كل ضغطة في الحقول.
  void _touch() {
    if (mounted) setState(() {});
  }

  void _listenLine(_LineUi l) {
    l.qty.addListener(_touch);
    l.price.addListener(_touch);
    l.discount.addListener(_touch);
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
    // س-132: فهرس الباركودات للبحث السريع — قراءة واحدة عند الفتح،
    // والإضافة من البطاقات تتجدد بفتح جديد للنموذج.
    final barcodes = await widget.db.barcodeIndexByItem();
    // المتاح لكل صنف من المستودع المختار (س-108/D-106 قراءة خالصة) —
    // إصلاح علة س-119 (D-114): القراءة كانت قبل تعيين المستودع الافتراضي
    // فتُقرأ خريطة فارغة أولَ فتح وتبقى حتى تبديل المستودع يدوياً —
    // صار التعيين قبل القراءة فيرى المالك متاح ما رحّله فور فتح النموذج
    // (بلفظه «لم يحدث التطبيق الكمية المتاحة» بعد فاتورة الشراء).
    final wid =
        _warehouseId ?? (warehouses.isEmpty ? null : warehouses.first.id);
    final avail = wid == null
        ? const <int, int>{}
        : await widget.db.stockQuantitiesByItem(warehouseId: wid);
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _warehouses = warehouses;
      _parties = parties.where((p) => p.isActive).toList();
      _currencies = currencies;
      _items = items.where((i) => i.isActive).toList();
      _unitNames = {for (final u in units) u.id: u.name};
      _barcodesByItem = barcodes;
      _stockAvail = avail;
      // الافتراضي المعقول لصاحب المحل: أول صندوق وأول مستودع نشط —
      // والمستودع المعين قبل قراءة المتاح (إصلاح س-119/D-114 أعلاه).
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _warehouseId = wid;
      final base =
          _currencies.where((c) => c.isBase).toList();
      _currencyId = base.isEmpty ? 1 : base.first.id;
      _loaded = true;
    });
  }

  /// تحديث خريطة المتاح بعد تبديل المستودع (س-108/D-106).
  Future<void> _reloadStock() async {
    final wid = _warehouseId;
    if (wid == null) return;
    final avail = await widget.db.stockQuantitiesByItem(warehouseId: wid);
    if (!mounted) return;
    setState(() => _stockAvail = avail);
  }

  @override
  void dispose() {
    _date.dispose();
    _due.dispose();
    _fxRate.dispose();
    _discount.dispose();
    _original.dispose();
    _narration.dispose();
    _quickSearch.dispose();
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
      : parseGroupedInt(_fxRate.text.trim());

  int _parsed(TextEditingController c) => parseGroupedInt(c.text.trim());

  /// السعر الافتراضي من بطاقة الصنف بحسب جهة الفاتورة (س-108/D-107):
  /// بيع ومردوده ← سعر البيع، شراء ومردوده ← سعر الشراء — و«بلا سعر
  /// بعد» (الصفر س6) يبقى الحقل فارغاً لا صفراً. المعبأ آلياً وُسم
  /// فتُعاد التعبئة الصحيحة عند تبديل جهة الفاتورة لا كسر ما كُتب يدوياً.
  void _fillDefaultPrice(_LineUi line) {
    final item = _itemOf(line.itemId);
    if (item == null) return;
    final minor =
        _kind.isSalesSide ? item.salePriceMinor : item.purchasePriceMinor;
    line.price.text = minor > 0 ? groupDigits(minor) : '';
    line.priceAutoFilled = minor > 0;
  }

  /// إعادة تعبئة أسعار البنود المعباة آلياً بعد تبديل جهة الفاتورة —
  /// فسعر الجهة الجديدة هو المتوقع، وما كتبه المستخدم يدوياً لا يُلمس.
  void _refillAutoPrices() {
    for (final l in _lines) {
      if (l.itemId != null && l.priceAutoFilled) {
        _fillDefaultPrice(l);
      }
    }
  }

  /// إجمالي السطر الخام — الكمية × السعر − خصم السطر (س-120/D-115)
  /// قبل نصيبه من خصم الفاتورة الكلي، ويُعرض لحظياً في بطاقة البند.
  int _lineGrossMinor(_LineUi line) =>
      _parsed(line.qty) * _parsed(line.price) - _parsed(line.discount);

  /// إضافة بند جديد وتركيز حقل الكمية فيه (س-109/D-110) — الإدخال
  /// بلوحة المفاتيح كاملاً بلا مسك الفأرة عند نهاية كل بند.
  void _addLineFocused() {
    setState(() {
      _lines.add(_LineUi());
    });
    _listenLine(_lines.last);
    // بعد إعادة البناء — التأجيل يعطي الإطار فرصة التركيب.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_lines.last.qtyFocus);
      }
    });
  }

  /// تعيين صنف بند بأي مسار (القائمة أو البحث السريع) — تعبئة السعر
  /// الافتراضي س-108 سارية في كل المسارات.
  void _setLineItem(_LineUi line, int itemId) {
    setState(() {
      line.itemId = itemId;
      _fillDefaultPrice(line);
    });
  }

  /// البنود ذات الصنف الفارغ — مسار البحث السريع يملأ الأول أولاً.
  _LineUi? get _firstEmptyLine {
    for (final l in _lines) {
      if (l.itemId == null) return l;
    }
    return null;
  }

  /// س-132: خانة بحث البنود — الرمز الكامل يجلب الصنف مباشرة (قارئ
  /// البلوتوث يكتب الرمز ويعطي Enter بلا كاميرا أصلاً)، ورمز غير
  /// مرتبط برسالته الحرفية، والبحث الجزئي يبقى للاقتراحات.
  void _applyQuickSearch({required bool fromSubmit}) {
    final q = _quickSearch.text.trim();
    if (q.isEmpty) return;
    final exact = itemIdByExactBarcode(q, _barcodesByItem);
    if (exact == null) {
      if (fromSubmit && _quickSuggestions(q).isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
              const SnackBar(content: Text('رمز غير مرتبط بأي صنف')));
      }
      setState(() {}); // لا مطابقة كاملة — الاقتراحات تبقى معروضة
      return;
    }
    var target = _firstEmptyLine;
    if (target == null) {
      _addLineFocused();
      target = _lines.last;
    }
    _setLineItem(target, exact);
    _quickSearch.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(target!.qtyFocus);
      }
    });
  }

  /// اقتراحات البحث الجزئي — الاسم والكود والباركود (س-132) بحد أعلى
  /// للقائمة كي لا تطغى على النموذج.
  List<Item> _quickSuggestions(String query) {
    if (query.trim().isEmpty) return const [];
    final out = <Item>[];
    for (final it in _items) {
      if (ItemSearchFields(
        name: it.name,
        sku: it.sku,
        category: it.category ?? '',
        barcodes: _barcodesByItem[it.id] ?? const [],
      ).matchesQuery(query)) {
        out.add(it);
        if (out.length >= 5) break;
      }
    }
    return out;
  }

  /// مسح باركود من خانة البحث (أندرويد — س-132): الرمز يعود فالمطابقة
  /// تجري كسرها البلوتوث ذاتها، وغير المرتبط برسالته.
  Future<void> _scanFromQuickSearch() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    _quickSearch.text = code;
    _applyQuickSearch(fromSubmit: true);
  }

  Item? _itemOf(int? itemId) {
    if (itemId == null) return null;
    for (final i in _items) {
      if (i.id == itemId) return i;
    }
    return null;
  }

  CashBoxReportRow? _boxOf(int? boxId) {
    if (boxId == null) return null;
    for (final b in _boxes) {
      if (b.boxId == boxId) return b;
    }
    return null;
  }

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
      // س-117/D-112: النسبة تُقرأ عشرية وتُخزن ×100 (3.5 → 350).
      discountRate: parsePercentRate100(_discount.text),
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
                  onChanged: (value) => setState(() {
                    final next = InvoiceKind.values
                        .firstWhere((k) => k.storageValue == value);
                    if (next == _kind) return;
                    _kind = next;
                    // علة س-113 (إصلاح، دفعة 8): تبديل الجهة يصفّر الطرف كي
                    // لا يبقى «العميل» معروضاً بلون التحديد في قائمة
                    // الموردين — والصندوق باقٍ بلا مساس.
                    _partyId = null;
                    _refillAutoPrices();
                  }),
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
                if (_isCash) ...[
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
                  ),
                  // س-106 (D-106): الرصيد الآن من تقرير الصناديق ذاته —
                  // يرى البائع قبل الحفظ أن الصندوق لا يكفي، بلا جداول
                  // جديدة ولا تخزين (روح D-088/D-089).
                  if (_boxOf(_boxId) != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'الرصيد الآن: '
                        '${formatMinorAmount(_boxOf(_boxId)!.balanceBaseMinor)}'
                        ' (بالأساسية)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ] else
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
                  onChanged: (value) {
                    setState(() => _warehouseId = value);
                    _reloadStock();
                  },
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
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
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
                // س-110 (D-109): خصم الفاتورة في التذييل إلى جانب المجاميع
                // — بلفظ المالك «الخصم في التذييل» — فالقراءة الطبيعية:
                // المجموع ← الخصم ← الصافي، والمدققات كما هي.
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
                    onPressed: _addLineFocused,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة بند'),
                  ),
                ),
                // س-110 (D-109): حقل الخصم إلى جانب بطاقة المجاميع في
                // التذييل — نسبة لا مبلغ فلا فواصل ألوف (D-102).
                // س-117 (D-112): الفاصلة العشرية مقبولة حتى خانتين
                // (3.5% مثال المالك) — ولا تناقض مع منع فواصل الألوف
                // عن النسب فهما فاصلتان مختلفتان.
                // س-132: خانة بحث بنود الفواتير — الاسم والكود والباركود،
                // والرمز الكامل يجلب الصنف مباشرة (قارئ بلوتوث بلا
                // كاميرا أصلاً)، وزر المسح بكاميرا الجوال على أندرويد.
                // موضعها بعد البنود كي لا تزيح حقول النماذج المعروفة
                // عن مواضعها المجرَّبة (درس كسر CI).
                TextField(
                  controller: _quickSearch,
                  decoration: InputDecoration(
                    labelText:
                        'بحث سريع بالاسم أو الكود أو الباركود (س-132)',
                    helperText: 'الرمز الكامل يجلب الصنف مباشرة — قارئ '
                        'البلوتوث يكتب فيه ويعطي Enter',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: supportsCameraScan
                        ? IconButton(
                            tooltip: 'مسح باركود',
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanFromQuickSearch,
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) =>
                      _applyQuickSearch(fromSubmit: true),
                ),
                for (final suggestion in _quickSuggestions(_quickSearch.text))
                  ListTile(
                    dense: true,
                    leading: ItemImageBox(
                      imagePath: suggestion.imageThumb,
                      itemName: suggestion.name,
                      size: 36,
                    ),
                    title: Text('${suggestion.sku} ${suggestion.name}'),
                    subtitle: Text(_itemSubtitle(suggestion)),
                    onTap: () {
                      var target = _firstEmptyLine;
                      if (target == null) {
                        _addLineFocused();
                        target = _lines.last;
                      }
                      _setLineItem(target, suggestion.id);
                      _quickSearch.clear();
                    },
                  ),
                TextField(
                  controller: _discount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [const PercentDecimalInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'خصم الفاتورة نسبةً 0..100 (اختياري)'),
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

  /// سطر معلومات الصنف في قائمة الاختيار (س-108/D-107) — بترتيب
  /// المالك المعتمد حرفاً: «رقم الصنف – الاسم – الكمية – السعر»،
  /// والسعر بنوعه («سعر بيع» في البيع و«سعر شراء» في الشراء) مفصولاً
  /// (D-102)، والمتاح من المستودع المختار لحظياً (D-106).
  String _itemSubtitle(Item it) {
    final minor =
        _kind.isSalesSide ? it.salePriceMinor : it.purchasePriceMinor;
    final priceText =
        minor > 0 ? formatMinorAmount(minor) : 'بلا سعر بعد';
    final priceLabel = _kind.isSalesSide ? 'سعر بيع' : 'سعر شراء';
    final avail = _stockAvail[it.id] ?? 0;
    return it.kind == 'service'
        ? '$priceLabel: $priceText'
        : 'المتاح: ${groupDigits(avail)} · $priceLabel: $priceText';
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
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الصنف'),
              onTap: () {
                // س-119/D-114: النقر على الصنف يحدّث المتاح أولاً كي
                // لا تُعرض خريطة قديمة إن رُحّلت فاتورة والنموذج مفتوح.
                _reloadStock();
              },
              items: [
                for (final it in _items)
                  DropdownMenuItem<int>(
                    value: it.id,
                    // س-108: سطر واحد مركّب بترتيب المالك «رقم الصنف –
                    // الاسم – المتاح – السعر» — عمود سطرين افاض حقل القائمة
                    // المغلقة (درس CI: RenderFlex overflowed by 16 pixels)
                    // فصار سطراً واحداً يلتف مقصوصاً لا يفاض.
                    child: Text(
                      '${it.sku} ${it.name}'
                      '${it.kind == 'service' ? ' (خدمة)' : ''}'
                      ' — ${_itemSubtitle(it)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                line.itemId = value;
                _fillDefaultPrice(line); // س-108: السعر الافتراضي يُعبأ
              }),
            ),
            if (line.itemId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // س-126 (D-118): مصغر الصورة بجوار اسم الصنف فور
                    // اختياره — المشتق المصغر حصراً لا الأصل (أداء
                    // القوائم الطويلة).
                    ItemImageBox(
                      imagePath: _itemOf(line.itemId)?.imageThumb,
                      itemName: _itemOf(line.itemId)!.name,
                      size: 44,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                _itemSubtitle(_itemOf(line.itemId)!),
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                          ),
                          if (unitName.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('الوحدة: $unitName (الأساسية)'),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              // س-120 (D-115): إجمالي السطر لحظياً — الكمية × السعر
                              // − خصم السطر، ويتجدد مع كل ضغطة (مستمعو الحقول أعلاه).
                              'إجمالي السطر: ${formatMinorAmount(_lineGrossMinor(line))}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  // س-109 (D-110): Enter ينقل للحقل التالي، وTab/السهم
                  // السفلي يضيفان بنداً جديداً بلا قفزة خارج البطاقة.
                  child: KeyboardAddLine(
                    onAdd: _addLineFocused,
                    child: TextField(
                      controller: line.qty,
                      focusNode: line.qtyFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        // الكميات من أهل الفواصل أيضاً (تنبيه المالك:
                        // «الفاصلة أيضاً تشمل الكميات والمبالغ»).
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration:
                          const InputDecoration(labelText: 'الكمية'),
                      onSubmitted: (_) => FocusScope.of(context)
                          .requestFocus(line.priceFocus),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KeyboardAddLine(
                    onAdd: _addLineFocused,
                    child: TextField(
                      controller: line.price,
                      focusNode: line.priceFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                          labelText: 'سعر الوحدة بوحدة صغرى'),
                      onSubmitted: (_) => FocusScope.of(context)
                          .requestFocus(line.discountFocus),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KeyboardAddLine(
                    onAdd: _addLineFocused,
                    child: TextField(
                      controller: line.discount,
                      focusNode: line.discountFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                          labelText: 'خصم السطر (اختياري)'),
                      onSubmitted: (_) => _addLineFocused(),
                    ),
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

  /// صور بنود الفاتورة إن كان مفتاح نوعها مفعّلاً (س-127/D-123) —
  /// والافتراضي معطل فلا قراءة ملفات أبداً بلا مفتاح، والغائب/الفاسد
  /// null فيعرض النائب البصري بالمطبوع (س-125).
  Future<(List<Uint8List?>?, List<String>?)> _printoutImages(
    InvoiceDocument invoice,
    List<InvoiceLineDocument> lines,
    Map<int, Item> itemById,
  ) async {
    if (!printImagesForKind(InvoiceKind.fromStorage(invoice.kind))) {
      return (null, null);
    }
    final images = <Uint8List?>[];
    final letters = <String>[];
    for (final line in lines) {
      images.add(await loadItemImageBytes(itemById[line.itemId]?.imageFile));
      letters.add(itemById[line.itemId]?.name ?? 'صنف');
    }
    return (images, letters);
  }

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
      final itemById = {for (final item in items) item.id: item};
      final (rowImages, rowLetters) =
          await _printoutImages(invoice, lines, itemById);
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
              itemById[line.itemId]?.name ?? 'صنف #${line.itemId}',
              '${line.qtyBase}',
              formatMinorAmount(line.unitPriceMinor),
              formatMinorAmount(line.lineTotalDocMinor),
            ],
        ],
        rowLeadingImages: rowImages,
        rowPlaceholderLetters: rowLetters,
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
              final itemById = {for (final item in items) item.id: item};
              final (rowImages, rowLetters) =
                  await _printoutImages(invoice, lines, itemById);
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
                      itemById[line.itemId]?.name ?? 'صنف #${line.itemId}',
                      '${line.qtyBase}',
                      formatMinorAmount(line.unitPriceMinor),
                      formatMinorAmount(line.lineTotalDocMinor),
                    ],
                ],
                rowLeadingImages: rowImages,
                rowPlaceholderLetters: rowLetters,
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
