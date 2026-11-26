import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'dq_log.dart';
import 'app_theme.dart';
import 'adaptive.dart';
import 'delivery_summary.dart';
import 'input_formatters.dart';
import 'invoices_screen.dart';
import 'date_picker.dart';
import 'context_menu.dart';
import 'print_service.dart';
// س223: الحد المتدرج الموحد لقوائم المستندات (المتبقي من د5).
import 'list_display.dart';
import 'empty_state.dart';
import 'reports_screen.dart' show formatMinorAmount;

/// طلبات البيع والشراء — الواجهة (س123 — الدفعة الثانية لتفعيل الطلبات
/// بنفس أمر المالك الحرفي «أريد تفعيل طلبات البيع والشراء»).
///
/// الأساس الكامل س121 (ترحيلة v27 والمجال والتخزين وحرسا التحويل على
/// الفواتير — 09 §18) والواجهة هنا تستهلكه لا تعيد بناءه: القائمة
/// بفلتري الاتجاه والحالة، والنموذج مسودةَ الأمر (الترقيم لحظة التأكيد
/// حصراً — 07 §1.9)، والتفصيل بأفعاله محروسِة بآلة الحالات (مسودة
/// فتأكيد أو إلغاء أو حذف، ومؤكد فتحويل أو إغلاق أو إلغاء، والنهائي
/// لا فعل عليه)، والتحويل النافذ يفتح نموذج الفاتورة معبأً بالمتبقي
/// من الأمر بأسعاره المرجعية فتخرج الفاتورة مرجعةً لأمرها
/// (`invoices.order_id`) بلا سطر يتجاوز متبقاه — والحرسان طبقة طبقة
/// (الواجهة تعطل ما انتقاله مرفوض والتخزين يرفض ما خالفه).
///
/// الحدود الصادقة الموثقة س121 باقية: الأمر لا يُقيد ولا يحرك مخزوناً
/// أبداً — الفاتورة وحدها المستند المالي، والأسعار على الأمر مرجعية
/// وقت الأمر لا إلزامية، والتحويل يبذر النموذج بالمكافئ الأساسي ووحدة
/// الإدخال للواجهة تختار — لا اقتران مستوى تعبئة في التحويل الآني.
///
/// ═══ ألسنة العرض المشتركة ═══

/// تسمية الاتجاه من قيمته التخزينية — والقيمة التالفة لسان نائب لا
/// استثناء في قراءة عرضية.
String orderDirectionLabelOf(String storageValue) {
  for (final d in OrderDirection.values) {
    if (d.storageValue == storageValue) return d.label;
  }
  return 'أمر';
}

/// تسمية الحالة من قيمتها التخزينية (نمط move_detail الموثق v19:
/// القيم إنجليزية والعرض بترجمتها).
String orderStateLabelOf(String storageValue) {
  for (final s in OrderState.values) {
    if (s.storageValue == storageValue) return s.label;
  }
  return storageValue;
}

/// زوق حالة الأمر من الأزقة الدلالية (س186 — بقية م05) — مسودة محايدة
/// باهتة (التزام غير معلن)، مؤكدة انتباه أزرق (التزام معلن)، مغلقة
/// إيجابي أخضر (وفّى)، ملغاة سلبي أحمر (عُفيت).
DiqqahLane orderStateLaneOf(BuildContext context, String storageValue) {
  final lanes = diqqahLanesOf(context);
  switch (storageValue) {
    case 'draft':
      return lanes.neutral;
    case 'confirmed':
      return lanes.attention;
    case 'closed':
      return lanes.positive;
    case 'cancelled':
      return lanes.negative;
    default:
      return lanes.neutral;
  }
}

/// نص خط التحقق النقي للعرض — الواجهة وحدها تقرر الصياغة (فصل المجال
/// عن العرض، نمط describeInvoiceValidationError في اللسان لا الموضع:
/// المجال النقي لا يعرف شيئاً عن حزم فوقه بعرف F-010).
String orderValidationErrorText(OrderValidationError e) {
  switch (e.runtimeType) {
    case OrderLinesRequired:
      return 'أسطر الأمر فارغة — لا أمر بلا صنف واحد على الأقل';
    case OrderPartyRequired:
      return 'طرف الأمر مطلوب — أمر بيع لزبون وأمر شراء لمورد';
    case OrderQtyInvalid:
      return 'كمية السطر ${(e as OrderQtyInvalid).lineIndex} غير صالحة — '
          'موجبة ومتسقة مع مكافئها الأساسي';
    case OrderTransitionInvalid:
      final t = e as OrderTransitionInvalid;
      return 'لا ينتقل الأمر من «${t.from.label}» إلى «${t.to.label}» '
          '— الانتقالات: مسودة فتأكيد أو إلغاء، ومؤكد فإغلاق أو إلغاء';
    case OrderCloseIncomplete:
      // الرمز DQ-0706 للسجل والمرجع لا نص المستخدم (س204 — م03).
      return 'لا يُغلق الأمر والمتبقي أكبر من صفر — حوّل المتبقي '
          'لفاتورة أولاً';
    case OrderNotConvertible:
      return 'التحويل من الأمر المؤكد حصراً — وحالة هذا الأمر '
          '«${(e as OrderNotConvertible).state.label}»';
    case OrderFrozen:
      // الرمز DQ-0702 للسجل والمرجع لا نص المستخدم (س204 — م03).
      return 'الأمر مؤكد مجمّد — التصحيح بالإلغاء وإعادة الأمر';
    default:
      return 'رفض مدقق الطلبات — راجع الحقول';
  }
}

/// ألسنة أخطاء مدقق الطلبات دفعةً — للعرض في بطاقة الأخطاء بالنموذج.
List<String> orderValidationErrorsText(OrderValidationException e) =>
    [for (final err in e.errors) orderValidationErrorText(err)];

/// عَلَم أمر بيع أو شراء بلون اتجاهه — عرف بطاقة الفواتير (البيع
/// يميناً بلون اللافتة) والشراء بآخره.
IconData orderDirectionIconOf(String storageValue) =>
    storageValue == OrderDirection.purchase.storageValue
        ? Icons.shopping_cart_outlined
        : Icons.local_mall_outlined;

/// تسمية الأمر في القائمة والطباعة — المرقّم برقمه والمسودة بنادِها
/// (لا رقم يُصدر بلا أمر مؤكد مكتوب — 07 §1.9).
String orderDisplayLabel(OrderListRow o) {
  final dir = orderDirectionLabelOf(o.direction);
  return o.number.isEmpty ? 'مسودة $dir' : '$dir رقم ${o.number}';
}

/// ═══ الطباعة — مستند الأمر (س123) ═══
///
/// الأمر وثيقة التزام تشغيلية فتُطبع بأسعاره المرجعية مع إفصاح صريح
/// بأن الفاتورة هي المستند المالي — كي لا تدور الورقة بين الأيدي
/// وثيقةً محاسبية وهي ليست (عرف ترويسة نسخة أمين المستودع س119).
/// القياس A5 طولي عرف الفواتير والسندات (D-101) وقالب القياسات
/// س119 خاص بالفواتير حصراً — أمر الطباعة هنا ثابت الافتراض.

/// صفوف جدول الأمر للمطبوع — منسقة نصاً هنا فالاختبار النقي يقرأها
/// بلا بايتات، والطباعة تمررها للبنّاء العام كما هي.
List<List<String>> orderPdfRows({
  required List<OrderLineRow> lines,
  required Map<int, String> unitNames,
  required Map<int, String> levelNames,
}) {
  final rows = <List<String>>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final unitLabel = l.unitLevelId == null
        ? (unitNames[l.unitId] ?? '')
        : (levelNames[l.unitLevelId] ?? '');
    final priceText = l.unitPriceMinor > 0
        ? formatMinorAmount(l.unitPriceMinor)
        : '—';
    final valueText = l.unitPriceMinor > 0
        ? formatMinorAmount(l.qty * l.unitPriceMinor)
        : '—';
    rows.add([
      '${i + 1}',
      '${l.itemSku ?? ''} ${l.itemName ?? ''}'.trim(),
      unitLabel,
      groupDigits(l.qty),
      priceText,
      valueText,
    ]);
  }
  return rows;
}

/// توليد PDF مستند الأمر — عنوان بلسان الأمر (المرقّم برقمه والمسودة
/// بنادِها) وترويسة معرفاته وجدول أسطره وخاتمة الكميات المجمعة
/// بوحداتها (جمع وحدات مختلفة ممنوع — درس ميزانية السحب س119).
Future<Uint8List> buildOrderPdf({
  DiqqahDatabase? db,
  required OrderListRow head,
  required List<OrderLineRow> lines,
  required Map<int, String> unitNames,
  required Map<int, String> levelNames,
  String? warehouseName,
}) async {
  final dir = orderDirectionLabelOf(head.direction);
  final title = head.number.isEmpty ? 'مسودة $dir' : '$dir رقم ${head.number}';
  final headerPairs = <(String, String)>[
    ('الطرف', head.partyName ?? '—'),
    ('التاريخ', head.orderDate),
    if (head.expectedDate != null && head.expectedDate!.isNotEmpty)
      ('التوريد المتوقع', head.expectedDate!),
    ('الحالة', orderStateLabelOf(head.state)),
    if (warehouseName != null) ('المستودع', warehouseName),
  ];
  final qtyByUnit = quantitiesByUnit([
    for (final l in lines)
      (
        l.qty,
        l.unitLevelId == null
            ? (unitNames[l.unitId] ?? 'الأساسية')
            : (levelNames[l.unitLevelId] ?? 'الأساسية')
      ),
  ]);
  return buildDocumentPdf(
    db: db,
    title: title,
    headerPairs: headerPairs,
    columns: const [
      'م',
      'الصنف',
      'الوحدة',
      'الكمية',
      'السعر المرجعي',
      'قيمة السطر',
    ],
    rows: orderPdfRows(
        lines: lines, unitNames: unitNames, levelNames: levelNames),
    footerPairs: [
      ('عدد الأسطر', '${lines.length}'),
      if (qtyByUnit.isNotEmpty)
        ('مجموع الكميات', groupedQuantitiesText(qtyByUnit)),
      ('الأسعار', 'مرجعية وقت الأمر — الفاتورة هي المستند المالي'),
    ],
    format: resolvePageFormat(docKind: 'invoice'),
  );
}

/// ═══ شاشة القائمة ═══

/// شاشة طلبات البيع والشراء — القائمة بفلتري الاتجاه والحالة (حرسا
/// التخزين listOrders نفسُهما) وبطاقة كل أمر بمعرفاته وحالته، والنقر
/// يفتح التفصيل بأفعاله. الفتح من بلاطة الرئيسية خلف صلاحية «orders»
/// («طلبات الشراء والبيع» — المفتاح جاهز بالصلاحيات منذ اليوم الأول
/// F-080) كما أخواتها من الشاشات.
class OrdersScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const OrdersScreen({super.key, required this.db});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  /// فلترا القائمة — القيمة التخزينية وnull الكل (عرف فلتر الأرشيف).
  OrderDirection? _direction;
  OrderState? _state;

  static final List<(OrderDirection?, String)> _directionChoices = [
    (null, 'كل الاتجاهات'),
    (OrderDirection.sale, OrderDirection.sale.label),
    (OrderDirection.purchase, OrderDirection.purchase.label),
  ];

  static final List<(OrderState?, String)> _stateChoices = [
    (null, 'كل الحالات'),
    (OrderState.draft, OrderState.draft.label),
    (OrderState.confirmed, OrderState.confirmed.label),
    (OrderState.closed, OrderState.closed.label),
    (OrderState.cancelled, OrderState.cancelled.label),
  ];

  Future<List<OrderListRow>>? _rows;

  /// س223 — الحد المتدرج لأرشيف الطلبات (المتبقي من د5 بنمط
  /// list_display.dart): شحنة [kListDisplayPageSize] صفّاً ثم توسيع
  /// بضغطة ويصفر مع كل استعلام جديد فالفلتر المنعش يبدأ من أعلى
  /// القائمة.
  int _displayLimit = kListDisplayPageSize;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      // س223: استعلام جديد فالحد المتدرج يصفر — البدء من أعلى القائمة.
      _displayLimit = kListDisplayPageSize;
      _rows = widget.db
          .listOrders(direction: _direction, state: _state)
          .then((rows) {
        // عرف الفشل المغلق: القائمة الفارغة «لا أوامر بعد» لا صمت شاشة.
        return rows;
      });
    });
  }

  /// فتح نموذج أمر جديد — الاتجاه يُختار من ورقة سفلية بنمط بطاقة
  /// الفواتير («اختر النوع بالضغط لا قائمة انتقاء») ثم يثبت بالنموذج
  /// فلا مبدّل اتجاه داخلي (عزل الإدخال س-163).
  Future<void> _newOrder() async {
    final direction = await showModalBottomSheet<OrderDirection>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('أمر جديد — اختر الاتجاه بالضغط'),
            ),
            ListTile(
              leading: const Icon(Icons.local_mall_outlined),
              title: Text(OrderDirection.sale.label),
              subtitle: const Text('التزام بيع لزبون — يُحوَّل لفاتورة بيع'),
              onTap: () => Navigator.of(ctx).pop(OrderDirection.sale),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: Text(OrderDirection.purchase.label),
              subtitle:
                  const Text('التزام شراء من مورد — يُحوَّل لفاتورة شراء'),
              onTap: () => Navigator.of(ctx).pop(OrderDirection.purchase),
            ),
          ],
        ),
      ),
    );
    if (direction == null || !mounted) return;
    await _openEdit(direction: direction);
  }

  Future<void> _openEdit({
    required OrderDirection direction,
    int? orderId,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => OrderEditScreen(
                db: widget.db,
                direction: direction,
                orderId: orderId,
              )),
    );
    if (saved == true) _reload();
  }

  Future<void> _openDetail(int orderId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
          builder: (_) => OrderDetailScreen(db: widget.db, orderId: orderId)),
    );
    // العودة من التفصيل تُحدّث القائمة — الأفعال فيه تغيّر الحالات
    // (تأكيد وإلغاء وإغلاق وتحويل) فتُرى القائمة واقعها بعد العودة.
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الشراء والبيع')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newOrder,
        icon: const Icon(Icons.add),
        label: const Text('أمر جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<OrderDirection?>(
                  initialValue: _direction,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'الاتجاه'),
                  items: [
                    for (final (v, label) in _directionChoices)
                      DropdownMenuItem<OrderDirection?>(
                          value: v, child: Text(label)),
                  ],
                  onChanged: (v) {
                    setState(() => _direction = v);
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<OrderState?>(
                  initialValue: _state,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                  items: [
                    for (final (v, label) in _stateChoices)
                      DropdownMenuItem<OrderState?>(
                          value: v, child: Text(label)),
                  ],
                  onChanged: (v) {
                    setState(() => _state = v);
                    _reload();
                  },
                ),
              ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<OrderListRow>>(
              future: _rows,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                          'تعذر قراءة الطلبات: ${snap.error}${dqTag(snap.error!)}'),
                    ),
                  );
                }
                final rows = snap.data ?? const <OrderListRow>[];
                if (rows.isEmpty) {
                  // س225 (خ6): حالة الفراغ الحية — القرص البني الهويّي
                  // ولسان الشاشة القائم حرفاً.
                  return Center(
                    child: DiqqahEmptyState(
                      icon: Icons.assignment_outlined,
                      message: 'لا أوامر بعد — ابدأ بـ«أمر جديد»',
                    ),
                  );
                }
                // س223 (المتبقي من د5): الشحنة من الاستعلام الكامل حصراً
                // — النمط الموحد بعقد الشريحة.
                final shown = listDisplayPage(rows, limit: _displayLimit);
                final remaining = rows.length - shown.length;
                return ListView.builder(
                  // س208 (الدفعة 2 — الاتساق): الهامش الأفقي التكيفي م06
                  // — العريض يتوسّط والضيّق هامشه الأساسي حرفاً — وثغرة
                  // م06 الموثقة على الطلبات تنقضي هنا.
                  // س223 (المتبقي من د5): الحد المتدرج الموحد بنمط
                  // list_display.dart — القراءة كاملة كما هي والحد بناء
                  // واجهة حصراً (عقد س221) وزر التوسيع بعدّاد الباقي.
                  padding: EdgeInsets.fromLTRB(
                      diqqahAdaptiveHorizontalMargin(context), 4,
                      diqqahAdaptiveHorizontalMargin(context), 88),
                  itemCount:
                      shown.length + (remaining > 0 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= shown.length) {
                      return listDisplayExpandButton(
                        context: context,
                        remaining: remaining,
                        onExpand: () => setState(
                            () => _displayLimit += kListDisplayPageSize),
                      );
                    }
                    final o = shown[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      // س207 (بند 2): قائمة السياق الموحدة — فعالياتها
                      // القائمة حصراً بنمط الفواتير.
                      child: RecordContextMenu(
                        actions: [
                          RecordContextAction(
                            label: 'تفاصيل الأمر',
                            icon: Icons.description_outlined,
                            onSelected: () => _openDetail(o.id),
                          ),
                          copyIdAction(context, o.id),
                        ],
                        child: ListTile(
                        leading: Icon(orderDirectionIconOf(o.direction)),
                        title: Text(orderDisplayLabel(o)),
                        subtitle: Text(
                          '${o.partyName ?? '—'} · ${o.orderDate} · '
                          'أسطر ${o.linesCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Builder(builder: (chipContext) {
                          final lane = orderStateLaneOf(chipContext, o.state);
                          return Chip(
                            label: Text(orderStateLabelOf(o.state)),
                            backgroundColor: lane.bg,
                            labelStyle: TextStyle(
                                color: lane.fg,
                                fontWeight: FontWeight.bold),
                            visualDensity: VisualDensity.compact,
                          );
                        }),
                        onTap: () => _openDetail(o.id),
                      ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ═══ نموذج الأمر (مسودة) ═══

/// سطر النموذج قبل الحفظ — لقطة الوحدة ثلاثية الأركان بنمط v21
/// (الأساسية أو مستوى تعبئة، والكمية بوحدة الإدخال ومكافؤها محسوبان
/// بالواجهة قبل الاستدعاء كما في الفواتير — المجال يتحقق لا يحسب).
class _OrderLineUi {
  int? itemId;
  int? unitLevelId;

  /// وسم مصدر السعر المرجعي حين عُبّئ آلياً من المرجعي أو المستوى
  /// المخزن — يُعرض صغيراً فيصدر الاقتراح من أين جاء (عرف س-108).
  String? priceSource;

  final TextEditingController qty = TextEditingController();
  final TextEditingController price = TextEditingController();
  final FocusNode qtyFocus = FocusNode();

  void dispose() {
    qty.dispose();
    price.dispose();
    qtyFocus.dispose();
  }
}

/// نموذج مسودة أمر — الإنشاء والتعديل (المسودة حرة والمرقّم مجمّد
/// بالفحص الصريح والحاجز معاً فالتعديل من التفصيل لا يفتح إلا مسودة).
/// الاتجاه يثبت بالفتح لا مبدّل داخلي (عزل الإدخال)، والترقيم ليس
/// هنا — لحظة التأكيد حصراً (07 §1.9).
class OrderEditScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final OrderDirection direction;

  /// معرف الأمر للتعديل — غايته إنشاء جديد.
  final int? orderId;

  const OrderEditScreen({
    super.key,
    required this.db,
    required this.direction,
    this.orderId,
  });

  @override
  State<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen> {
  late OrderDirection _direction = widget.direction;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _expected = TextEditingController();
  final TextEditingController _narration = TextEditingController();

  int? _partyId;
  int? _warehouseId;
  int _currencyId = 1;

  final List<_OrderLineUi> _lines = [_OrderLineUi()];

  List<Party> _parties = [];
  List<WarehouseRow> _warehouses = [];
  List<CurrencyRow> _currencies = [];
  List<Item> _items = [];
  Map<int, String> _unitNames = {};
  List<UnitGroupLevel> _groupLevels = const [];
  Map<int, Map<int, (int, int)>> _levelPrices = {};
  Map<int, String> _levelNameById = {};

  List<String>? _errors;
  bool _busy = false;

  /// بوابة التحميل — النموذج لا يُبنى قبل اكتمال القوائم الأولية
  /// (درس القوائم الأولية الموثق: قيم القوائم الجاهزة قبل أول بناء).
  bool _loaded = false;

  /// عنوان النموذج بلسان الاتجاه والوضع.
  String get _title => widget.orderId == null
      ? '${_direction.label} — جديد'
      : '${_direction.label} — تعديل مسودة';

  @override
  void initState() {
    super.initState();
    _date.text = todayIsoDate();
    _load();
  }

  @override
  void dispose() {
    _date.dispose();
    _expected.dispose();
    _narration.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// جهة الأمر بأهليتها — أمر بيع لزبون وأمر شراء لمورد (DQ-0702
  /// بلسان المجال)، و«عميل ومورد معاً» يصلح للاتجاهين.
  bool _partyFitsDirection(Party p) {
    if (p.kind == PartyKind.both.storageValue) return true;
    return _direction == OrderDirection.sale
        ? p.kind == PartyKind.customer.storageValue
        : p.kind == PartyKind.supplier.storageValue;
  }

  Future<void> _load() async {
    final parties = await widget.db.select(widget.db.parties).get();
    final warehouses =
        (await widget.db.warehousesOf()).where((w) => w.isActive).toList();
    final currencies = await widget.db.currenciesOf();
    final items = await widget.db.select(widget.db.items).get();
    final units = await widget.db.select(widget.db.units).get();
    final groupLevels =
        await widget.db.select(widget.db.unitGroupLevels).get();
    final levelPrices = await widget.db
        .itemLevelPricesForItems([for (final i in items) i.id]);
    if (!mounted) return;
    setState(() {
      _parties = parties.where((p) => p.isActive).toList();
      _warehouses = warehouses;
      _currencies = currencies;
      _items = items.where((i) => i.isActive).toList();
      _unitNames = {for (final u in units) u.id: u.name};
      _groupLevels = groupLevels;
      _levelPrices = levelPrices;
      _levelNameById = {for (final l in groupLevels) l.id: l.name};
      final base = _currencies.where((c) => c.isBase).toList();
      _currencyId = base.isEmpty ? 1 : base.first.id;
      _warehouseId = _warehouses.isEmpty ? null : _warehouses.first.id;
      _loaded = true;
    });
    // التعديل يعبأ من الأمر المخزن بعد جاهزية القوائم — فقيم القوائم
    // تُقرأ لا تُمس والحقول تأخذ لقطة الأمر كما هي.
    if (widget.orderId != null) await _fillFromOrder(widget.orderId!);
  }

  Future<void> _fillFromOrder(int orderId) async {
    final detail = await widget.db.getOrderWithLines(orderId);
    if (!mounted || detail == null) return;
    final (head, lines) = detail;
    setState(() {
      _direction = OrderDirection.fromStorage(head.direction);
      _partyId = head.partyId;
      _warehouseId = head.warehouseId;
      _currencyId = head.currencyId;
      _date.text = head.orderDate;
      _expected.text = head.expectedDate ?? '';
      _narration.text = head.narration ?? '';
      for (final l in _lines) {
        l.dispose();
      }
      _lines.clear();
      if (lines.isEmpty) {
        final ui = _OrderLineUi();
        _lines.add(ui);
      } else {
        for (final l in lines) {
          final ui = _OrderLineUi()
            ..itemId = l.itemId
            ..unitLevelId = l.unitLevelId;
          ui.qty.text = groupDigits(l.qty);
          if (l.unitPriceMinor > 0) {
            ui.price.text = groupDigits(l.unitPriceMinor);
          }
          _lines.add(ui);
        }
      }
    });
  }

  Item? _itemOf(int? itemId) {
    if (itemId == null) return null;
    for (final i in _items) {
      if (i.id == itemId) return i;
    }
    return null;
  }

  int? _baseUnitIdOf(int? itemId) => _itemOf(itemId)?.baseUnitId;

  List<UnitGroupLevel> _levelsOfItem(int? itemId) {
    final gid = _itemOf(itemId)?.unitGroupId;
    if (gid == null) return const [];
    return _groupLevels.where((l) => l.groupId == gid).toList();
  }

  /// عامل مستوى التعبئة — والأساسية 1 (المستويات لا تُحذف نمط المراجع
  /// 03 §6-3 فالغائب بيانات تالفة يعامل كالأساسية حفاظاً على المسار).
  int _factorOfLevel(int levelId) {
    for (final l in _groupLevels) {
      if (l.id == levelId) return l.factor;
    }
    return 1;
  }

  int _parsedQty(_OrderLineUi l) => parseGroupedInt(l.qty.text.trim());

  /// مكافئ السطر الأساسي — بالأساسية الكمية ذاتها وبمستوى التعبئة
  /// مضاعفةُ الكمية بالمعامل (حصة التخزين والمقارنة حصراً).
  int _qtyBaseOf(_OrderLineUi l) =>
      _parsedQty(l) * (l.unitLevelId == null ? 1 : _factorOfLevel(l.unitLevelId!));

  /// السعر المرجعي الافتراضي لوحدة الاختيار — عرف س-108 بسانه: بيع
  /// وأمر بيع ← سعر البيع المرجعي، شراء وأمر شراء ← سعر الشراء،
  /// وبالمستوى سعرُه المخزن وغيابه اشتقاق من الأساسية بعامله.
  void _fillReferencePrice(_OrderLineUi line) {
    final item = _itemOf(line.itemId);
    if (item == null) return;
    final levelId = line.unitLevelId;
    if (levelId != null) {
      final factor = _factorOfLevel(levelId);
      final stored = _levelPrices[item.id]?[levelId];
      final baseMinor = _direction == OrderDirection.sale
          ? item.salePriceMinor
          : item.purchasePriceMinor;
      final minor = stored != null
          ? (_direction == OrderDirection.sale ? stored.$1 : stored.$2)
          : derivedLevelPriceMinor(basePriceMinor: baseMinor, factor: factor);
      line.price.text = minor > 0 ? groupDigits(minor) : '';
      line.priceSource = stored != null
          ? 'سعر ${_levelNameById[levelId] ?? 'المستوى'} المخزن'
          : 'مشتق من الأساسية ×$factor';
      return;
    }
    final minor = _direction == OrderDirection.sale
        ? item.salePriceMinor
        : item.purchasePriceMinor;
    line.price.text = minor > 0 ? groupDigits(minor) : '';
    line.priceSource = null;
  }

  void _setLineItem(_OrderLineUi line, int itemId) {
    setState(() {
      line.itemId = itemId;
      line.unitLevelId = null;
      _fillReferencePrice(line);
    });
  }

  void _addLine() {
    setState(() {
      _lines.add(_OrderLineUi());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_lines.last.qtyFocus);
      }
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
  }

  /// بناء المسودة من النموذج — قيم خام للمجال يتحقق قبل أي كتابة،
  /// والعملة أسعارَ مرجعية لا قيداً (الأمر لا يُقيد أبداً).
  OrderSpec _buildSpec() {
    final lines = <OrderLineSpec>[
      for (final l in _lines)
        if (l.itemId != null && _parsedQty(l) > 0)
          OrderLineSpec(
            itemId: l.itemId!,
            unitId: _baseUnitIdOf(l.itemId) ?? 0,
            unitLevelId: l.unitLevelId,
            factorAtEntry: l.unitLevelId == null
                ? 1
                : _factorOfLevel(l.unitLevelId!),
            qty: _parsedQty(l),
            qtyBase: _qtyBaseOf(l),
            unitPriceMinor: parseGroupedInt(l.price.text.trim()),
          ),
    ];
    return OrderSpec(
      direction: _direction,
      partyId: _partyId,
      warehouseId: _warehouseId,
      orderDate: _date.text.trim(),
      expectedDate:
          _expected.text.trim().isEmpty ? null : _expected.text.trim(),
      lines: lines,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final spec = _buildSpec();
    // الحرس الأول بالواجهة — مدقق المجال النقي ذاته الذي يمسك التخزين
    // فتُعرض الأخطاء العربية ذاتها مرتين متسقتين لا اختلاف بينهما.
    final structure = validateOrderSpec(spec);
    if (structure.isNotEmpty) {
      setState(() {
        _errors = [for (final e in structure) orderValidationErrorText(e)];
      });
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final draft = OrderDraft(
        direction: _direction,
        partyId: spec.partyId,
        warehouseId: spec.warehouseId,
        orderDate: spec.orderDate,
        expectedDate: spec.expectedDate,
        currencyId: _currencyId,
        narration:
            _narration.text.trim().isEmpty ? null : _narration.text.trim(),
        lines: [
          for (final l in spec.lines)
            OrderLineDraft(
              itemId: l.itemId,
              unitId: l.unitId,
              unitLevelId: l.unitLevelId,
              factorAtEntry: l.factorAtEntry,
              qty: l.qty,
              qtyBase: l.qtyBase,
              unitPriceMinor: l.unitPriceMinor,
            ),
        ],
      );
      if (widget.orderId == null) {
        await widget.db.createOrderDraft(draft);
      } else {
        await widget.db.updateOrderDraft(widget.orderId!, draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on OrderValidationException catch (e) {
      await dqLog(widget.db, e, context: 'order.save');
      if (!mounted) return;
      setState(() {
        _errors = orderValidationErrorsText(e);
        _busy = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.save');
      if (!mounted) return;
      setState(() {
        _errors = ['$e${dqTag(e)}'];
        _busy = false;
      });
    }
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    final baseUnitId = _baseUnitIdOf(line.itemId);
    final baseUnitName =
        baseUnitId == null ? '' : (_unitNames[baseUnitId] ?? '');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          DropdownButtonFormField<int>(
            initialValue: line.itemId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: [
              for (final it in _items)
                DropdownMenuItem<int>(
                  value: it.id,
                  child: Text('${it.sku} ${it.name}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) _setLineItem(line, value);
            },
          ),
          if (line.itemId != null &&
              _levelsOfItem(line.itemId).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: DropdownButtonFormField<int?>(
                initialValue: line.unitLevelId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الوحدة'),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                        '${_unitNames[baseUnitId] ?? 'الأساسية'} (الأساسية)'),
                  ),
                  for (final lv in _levelsOfItem(line.itemId))
                    DropdownMenuItem<int?>(
                      value: lv.id,
                      child: Text('${lv.name} ×${lv.factor}'),
                    ),
                ],
                onChanged: (value) => setState(() {
                  line.unitLevelId = value;
                  _fillReferencePrice(line);
                }),
              ),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: line.qty,
                focusNode: line.qtyFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                decoration: const InputDecoration(labelText: 'الكمية'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: line.price,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                decoration: const InputDecoration(
                    labelText: 'السعر المرجعي (اختياري)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          if (line.itemId != null)
            Align(
              // س206 (م18 — طابور م14 الموثق بس198): كانت الثلاثة بأوامر
              // الشاشة خارج نطاقه فتوحّدت على العائلة الاتجاهية فالبداية
              // العربية دومًا (نمط م14 حرفاً).
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'المكافئ بالأساسية: ${groupDigits(_qtyBaseOf(line))} '
                '$baseUnitName'
                '${line.priceSource != null ? ' · ${line.priceSource}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Row(children: [
              Expanded(
                child: Text(
                  'قيمة السطر المرجعية: '
                  '${formatMinorAmount(_parsedQty(line) * parseGroupedInt(line.price.text.trim()))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: _lines.length <= 1
                    ? null
                    : () => _removeLine(index),
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final fittingParties =
        _parties.where(_partyFitsDirection).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
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
                          for (final e in _errors!) Text('• $e'),
                        ],
                      ),
                    ),
                  ),
                DropdownButtonFormField<int>(
                  initialValue: _partyId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _direction == OrderDirection.sale
                        ? 'الزبون'
                        : 'المورد',
                  ),
                  items: [
                    for (final p in fittingParties)
                      DropdownMenuItem<int>(
                        value: p.id,
                        child: Text('${p.number} ${p.name}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _partyId = value),
                ),
                DropdownButtonFormField<int?>(
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المستودع'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('بلا تحديد')),
                    for (final w in _warehouses)
                      DropdownMenuItem<int?>(
                          value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _warehouseId = value),
                ),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _date,
                      decoration: InputDecoration(
                          labelText: 'تاريخ الأمر (YYYY-MM-DD)',
                          suffixIcon:
                              calendarPickerSuffix(context, _date)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _expected,
                      decoration: const InputDecoration(
                          labelText: 'التوريد المتوقع (اختياري)'),
                    ),
                  ),
                ]),
                DropdownButtonFormField<int>(
                  initialValue: _currencyId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'عملة الأسعار المرجعية'),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem<int>(
                          value: c.id, child: Text('${c.code} ${c.name}')),
                  ],
                  onChanged: (value) =>
                      setState(() => _currencyId = value ?? 1),
                ),
                TextField(
                  controller: _narration,
                  decoration: const InputDecoration(
                      labelText: 'الملاحظة (اختياري)'),
                ),
                const SizedBox(height: 8),
                Text('الأسطر',
                    style: Theme.of(context).textTheme.titleSmall),
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة بند'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(widget.orderId == null
                      ? 'حفظ كمسودة'
                      : 'حفظ التعديل'),
                ),
                const SizedBox(height: 4),
                Text(
                  'الأمر مسودة التزام تشغيلي — لا قيد ولا حركة مخزون. '
                  'الترقيم لحظة التأكيد حصراً.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}

/// ═══ شاشة التفصيل ═══

/// تفصيل الأمر — معرفاته وأسطره وأفعاله محروسِة آلةَ الحالات: المسودة
/// تعديل وتأكيد وإلغاء وحذف، والمؤكدة تحويل وإغلاق وإلغاء، والنهائي
/// (مغلقة وملغاة) عرضٌ حصراً. وللمؤكدة خلاصة الوفاء المحسوبة
/// (المطلوب والمنفَّذ والمتبقي بالصنف) وزر التحويل النافذ.
class OrderDetailScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final int orderId;

  const OrderDetailScreen({
    super.key,
    required this.db,
    required this.orderId,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderListRow? _head;
  List<OrderLineRow> _lines = [];
  OrderConversionPreview? _preview;
  Map<int, String> _unitNames = {};
  Map<int, String> _levelNames = {};
  String? _warehouseName;
  bool _busy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.db.getOrderWithLines(widget.orderId);
      if (detail == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'الأمر غير موجود أو محذوف';
        });
        return;
      }
      final (head, lines) = detail;
      final units = await widget.db.select(widget.db.units).get();
      final levels =
          await widget.db.select(widget.db.unitGroupLevels).get();
      String? whName;
      if (head.warehouseId != null) {
        final whs = await widget.db.warehousesOf();
        for (final w in whs) {
          if (w.id == head.warehouseId) whName = w.name;
        }
      }
      OrderConversionPreview? preview;
      if (head.state == OrderState.confirmed.storageValue) {
        // الوفاء محسوب لا مخزن — يُقرأ لحظة العرض من فواتير الأمر
        // الحية، والمؤكدة حصراً فلا استثناء للأطراف النهائية.
        preview = await widget.db.prepareOrderConversion(widget.orderId);
      }
      if (!mounted) return;
      setState(() {
        _head = head;
        _lines = lines;
        _preview = preview;
        _unitNames = {for (final u in units) u.id: u.name};
        _levelNames = {for (final l in levels) l.id: l.name};
        _warehouseName = whName;
        _loading = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.detail');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e${dqTag(e)}';
      });
    }
  }

  OrderState? get _state {
    final h = _head;
    if (h == null) return null;
    try {
      return OrderState.fromStorage(h.state);
    } catch (_) {
      return null;
    }
  }

  /// وحدة سطر الأمر بلسان لقطته — المستوى عند الإدخال به والأساسية
  /// وإلا (نمط وحدة سطر الفاتورة الموثق).
  String _lineUnitLabel(OrderLineRow l) => l.unitLevelId == null
      ? (_unitNames[l.unitId] ?? '')
      : (_levelNames[l.unitLevelId] ?? '');

  /// اسم الصنف بأسطر الأمر — الصنف بسطرين اسمان متجاوران.
  String _itemNameOf(int itemId) {
    for (final l in _lines) {
      if (l.itemId == itemId) {
        return '${l.itemSku ?? ''} ${l.itemName ?? ''}'.trim();
      }
    }
    return 'الصنف $itemId';
  }

  /// ═══ الأفعال — كلها بنوافذ تأكيد واعية (لا انتقال بصمت زر) ═══

  Future<void> _confirm() async {
    final h = _head;
    if (h == null || _busy) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الأمر؟'),
        content: Text(
          '${orderDisplayLabel(h)} للطرف «${h.partyName ?? '—'}» بـ'
          '${_lines.length} سطر.\n'
          'التأكيد يعلن الالتزام ويمنح الأمر رقمه السنوي — والأمر '
          'المؤكد مجمّد لا يعدل إلا بحالته، ولا يُحذف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد وإصدار الرقم'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final number = await widget.db.confirmOrder(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('أُكد الأمر وأُصدر رقمه $number'),
      ));
    } on OrderValidationException catch (e) {
      await dqLog(widget.db, e, context: 'order.confirm');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(orderValidationErrorsText(e).join('؛ ') +
            dqTag(e)),
      ));
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.confirm');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e${dqTag(e)}')));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _cancel() async {
    final h = _head;
    if (h == null || _busy) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الأمر؟'),
        content: Text(
          '${orderDisplayLabel(h)} — الإلغاء نهاية نهائية لا رجوع '
          'منها. وفواتيرُ تحويلٍ صادرة سابقاً تبقى قائمةً بذاتها '
          '(مستندات مستقلة — لا عكس آلي).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('إلغاء الأمر'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.db.cancelOrder(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أُلغي الأمر')));
    } on OrderValidationException catch (e) {
      await dqLog(widget.db, e, context: 'order.cancel');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(orderValidationErrorsText(e).join('؛ ') + dqTag(e))));
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.cancel');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e${dqTag(e)}')));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _close() async {
    final h = _head;
    if (h == null || _busy) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إغلاق الأمر؟'),
        content: Text(
          '${orderDisplayLabel(h)} وفّى كاملاً بفواتيره — الإغلاق '
          'نهاية نهائية تعلن اكتمال الوفاء فلا تحويل ولا فاتورة '
          'جديدة عليه بعدها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('إغلاق الأمر'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.db.closeOrder(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أُغلق الأمر — اكتمل الوفاء')));
    } on OrderValidationException catch (e) {
      await dqLog(widget.db, e, context: 'order.close');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(orderValidationErrorsText(e).join('؛ ') + dqTag(e))));
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.close');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e${dqTag(e)}')));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _delete() async {
    final h = _head;
    if (h == null || _busy) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المسودة؟'),
        content: const Text(
          'المسودة التزام غير معلن فحذفها لا أثر له — والمرقّم '
          'لا يُحذف أبدًا (الحذف للمسودة حصراً).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.db.deleteOrderDraft(widget.orderId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on OrderValidationException catch (e) {
      await dqLog(widget.db, e, context: 'order.delete');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(orderValidationErrorsText(e).join('؛ ') + dqTag(e))));
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.delete');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e${dqTag(e)}')));
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// ═══ التحويل النافذ (س123) ═══
  ///
  /// نافذة المتبقي ثم نموذج الفاتورة المبذر — النافذة تُرى المتبقي
  /// الحقيقي محسوباً من فواتير الأمر الحية (الوفاء محسوب لا مخزن)،
  /// والفتح يبذر نموذج الفاتورة بنوع الأمر واتجاهه وطرفه ومستودعه
  /// وعملته وبأسطر المتبقي بأسعاره المرجعية — فتخرج الفاتورة مرجعةً
  /// لأمرها ولا سطر فيها يتجاوز متبقاه (حرسا التخزين DQ-0707 وما
  /// بعده والواجهة عطّلت ما لا يجوز).

  Future<void> _convert() async {
    final h = _head;
    if (h == null || _busy) return;
    if (_state != OrderState.confirmed) {
      // الرمز DQ-0707 للسجل والمرجع لا نص المستخدم (س204 — م03).
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'التحويل من الأمر المؤكد حصراً — المسودة التزام '
            'غير معلن والمغلقة وفّى كاملاً والملغاة عُفيت'),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      final preview =
          await widget.db.prepareOrderConversion(widget.orderId);
      if (!mounted) return;
      setState(() => _busy = false);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تحويل الأمر لفاتورة'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  '${orderDisplayLabel(h)} — المتبقي من كل صنف محسوب '
                  'من فواتير الأمر الحية:',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final f in preview.fulfilment)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_itemNameOf(f.itemId)),
                    subtitle: Text(
                        'المطلوب ${groupDigits(f.orderedQtyBase)} · '
                        'المنفَّذ ${groupDigits(f.fulfilledQtyBase)} · '
                        'المتبقي ${groupDigits(f.remainingQtyBase)} '
                        '(مكافئ أساسي)'),
                    trailing: f.remainingQtyBase <= 0
                        ? Icon(Icons.check_circle_outline,
                            color: diqqahLanesOf(context).positive.fg)
                        : Icon(Icons.pending_outlined,
                            color: diqqahLanesOf(context).attention.fg),
                  ),
                const SizedBox(height: 4),
                Text(
                  'سيُفتح نموذج الفاتورة معبأً بالمتبقي بأسعار الأمر '
                  'المرجعية — قيم قابلة للتعديل قبل الترحيل، والفاتورة '
                  'الصادرة مرجعة لأمرها ولا سطر فيها يتجاوز متبقيه. '
                  'الأوامر الموفاة كاملاً بلا سطر متبقٍ تُغلق حصراً.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('فتح نموذج الفاتورة'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
            builder: (_) => InvoiceEditScreen(
                  db: widget.db,
                  // النوع باتجاه الأمر من رأسه — بيع من بيع وشراء من
                  // شراء (لا انعكاس اتجاه في التحويل).
                  initialKind:
                      h.direction == OrderDirection.purchase.storageValue
                          ? InvoiceKind.purchase
                          : InvoiceKind.sale,
                  conversionSeed: preview,
                )),
      );
      // العودة من النموذج تُحدّث الوفاء المحسوب — فواتير جديدة مرجعة
      // للأمر غيّرت المتبقي فتُرى خلاصته واقعها.
      _reload();
    } on OrderValidationException catch (e) {
      await dqLog(widget.db, e, context: 'order.convert');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(orderValidationErrorsText(e).join('؛ ') + dqTag(e))));
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.convert');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e${dqTag(e)}')));
    }
  }

  Future<void> _editDraft() async {
    final h = _head;
    if (h == null || _busy) return;
    final dir = OrderDirection.fromStorage(h.direction);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => OrderEditScreen(
                db: widget.db,
                direction: dir,
                orderId: widget.orderId,
              )),
    );
    if (saved == true) _reload();
  }

  /// ═══ الطباعة ═══

  Future<void> _print() async {
    final h = _head;
    if (h == null || _busy) return;
    try {
      final bytes = await buildOrderPdf(
        db: widget.db,
        head: h,
        lines: _lines,
        unitNames: _unitNames,
        levelNames: _levelNames,
        warehouseName: _warehouseName,
      );
      if (!mounted) return;
      await printPdfBytes(context, bytes);
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.print');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الطباعة: $e${dqTag(e)}')));
    }
  }

  Future<void> _share() async {
    final h = _head;
    if (h == null || _busy) return;
    try {
      final bytes = await buildOrderPdf(
        db: widget.db,
        head: h,
        lines: _lines,
        unitNames: _unitNames,
        levelNames: _levelNames,
        warehouseName: _warehouseName,
      );
      if (!mounted) return;
      final dir = orderDirectionLabelOf(h.direction);
      final label = h.number.isEmpty ? 'مسودة $dir' : '$dir ${h.number}';
      await sharePdfBytes(bytes, 'أمر-$label.pdf');
    } catch (e) {
      await dqLog(widget.db, e, context: 'order.share');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر المشاركة: $e${dqTag(e)}')));
    }
  }

  /// ═══ البناء ═══

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('الأمر')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final head = _head;
    if (head == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الأمر')),
        body: Center(child: Text(_error ?? 'الأمر غير موجود')),
      );
    }
    final state = _state;
    final isDraft = state == OrderState.draft;
    final isConfirmed = state == OrderState.confirmed;
    final isTerminal = state?.isTerminal ?? false;
    final preview = _preview;
    final fullyFulfilled =
        preview == null || isOrderFullyFulfilled(preview.fulfilment);
    return Scaffold(
      appBar: AppBar(title: Text(orderDisplayLabel(head))),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // س208: الهامش الأفقي التكيفي م06 على تفصيل الأمر —
              // العريض يتوسّط والضيّق هامشه الأساسي حرفاً.
              padding: EdgeInsets.fromLTRB(
                  diqqahAdaptiveHorizontalMargin(context), 12,
                  diqqahAdaptiveHorizontalMargin(context), 12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(orderDirectionIconOf(head.direction)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              orderDirectionLabelOf(head.direction),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium,
                            ),
                          ),
                          Chip(
                            label: Text(orderStateLabelOf(head.state)),
                            backgroundColor:
                                orderStateLaneOf(context, head.state).bg,
                            labelStyle: TextStyle(
                                color:
                                    orderStateLaneOf(context, head.state).fg,
                                fontWeight: FontWeight.bold),
                            visualDensity: VisualDensity.compact,
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _infoRow('الطرف', head.partyName ?? '—'),
                        _infoRow('التاريخ', head.orderDate),
                        if (head.expectedDate != null &&
                            head.expectedDate!.isNotEmpty)
                          _infoRow('التوريد المتوقع', head.expectedDate!),
                        if (_warehouseName != null)
                          _infoRow('المستودع', _warehouseName!),
                        _infoRow('عدد الأسطر', '${_lines.length}'),
                        if (head.narration != null &&
                            head.narration!.isNotEmpty)
                          _infoRow('الملاحظة', head.narration!),
                        if (isTerminal)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              state == OrderState.closed
                                  ? 'الأمر مغلقة — وفّى كاملاً بفواتيره '
                                      'فلا فعل عليه.'
                                  : 'الأمر ملغاة — نهاية نهائية لا فعل '
                                      'عليها.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (isConfirmed && preview != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('خلاصة الوفاء (محسوبة من فواتير الأمر)',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall),
                          const SizedBox(height: 6),
                          for (final f in preview.fulfilment)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${_itemNameOf(f.itemId)} — المطلوب '
                                '${groupDigits(f.orderedQtyBase)} · '
                                'المنفَّذ ${groupDigits(f.fulfilledQtyBase)} '
                                '· المتبقي ${groupDigits(f.remainingQtyBase)} '
                                '(مكافئ أساسي)',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text('الأسطر',
                    style: Theme.of(context).textTheme.titleSmall),
                for (final l in _lines)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(
                          '${l.itemSku ?? ''} ${l.itemName ?? ''}'
                              .trim()),
                      subtitle: Text(
                        'الكمية ${groupDigits(l.qty)} ${_lineUnitLabel(l)}'
                        '${l.unitLevelId != null ? ' (المكافئ ${groupDigits(l.qtyBase)} بالأساسية)' : ''}'
                        '${l.unitPriceMinor > 0 ? ' · السعر المرجعي ${formatMinorAmount(l.unitPriceMinor)}' : ''}',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (isDraft)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.task_alt_outlined),
                        label: const Text('تأكيد وإصدار الرقم'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _editDraft,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('تعديل'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _cancel,
                        icon: const Icon(Icons.block_outlined),
                        label: const Text('إلغاء'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error),
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('حذف المسودة'),
                      ),
                    ],
                  ),
                if (isConfirmed)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _convert,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('تحويل لفاتورة'),
                      ),
                      OutlinedButton.icon(
                        onPressed: fullyFulfilled ? _close : null,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('إغلاق الأمر'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _cancel,
                        icon: const Icon(Icons.block_outlined),
                        label: const Text('إلغاء'),
                      ),
                    ],
                  ),
                if (isConfirmed && !fullyFulfilled)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      // الرمز DQ-0706 للسجل والمرجع لا نص المستخدم
                      // (س204 — م03).
                      'الإغلاق معطل — لا يُغلق الأمر والمتبقي أكبر من '
                      'صفر. حوّل المتبقي لفاتورة أولاً.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _print,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة الأمر'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('مشاركة PDF'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'الأمر وثيقة التزام تشغيلية — لا قيد ولا حركة مخزون '
                  'حتى فاتورته، والفاتورة هي المستند المالي.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}
