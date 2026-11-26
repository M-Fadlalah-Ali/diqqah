import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
import 'reports_screen.dart' show formatMinorAmount;

/// الترقية الجماعية للأسعار بالتصنيف — F-165 (الدفعة 23/D-183).
///
/// المواصفة حرفاً: شاشة تختار التصنيف والنسبة وتعرض معاينة قبل
/// التنفيذ؛ الأسعار الجديدة تُكتب على الأصناف (المرجعيات) والتقريب
/// للوحدة الصغرى بقاعدة س7؛ فواتير التاريخ بلقطات أسعارها لا تُمس.
///
/// حدود D-183 الموثقة:
/// - الحساب بمحرك المجال النقي `bulkPriceOutcome` حصراً — الشاشة تعرض
///   وتنقل لا تحسب، والكتابة بمسار التخزين الواحد `applyBulkPriceUpdates`
///   معاملةً واحدة.
/// - النشط حصراً: الأصناف المعطلة خارج الترقية والمعاينة (لا سعر لمن
///   لا يتداول)، والتصنيف الفارغ لا يدخل أي تصنيف.
/// - الحقل غير المستهدف لا يُمس إطلاقاً (Presence absent بالتخزين).
/// - الصفر ليس سعراً (س6) فلا يُرفع ويُرى في المعاينة كما هو.
class PriceUpdateScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const PriceUpdateScreen({super.key, required this.db});

  @override
  State<PriceUpdateScreen> createState() => _PriceUpdateScreenState();
}

class _PriceUpdateScreenState extends State<PriceUpdateScreen> {
  String? _category;
  BulkPriceTarget _target = BulkPriceTarget.sale;
  final TextEditingController _percent = TextEditingController();

  /// الأصناف النشطة محمّلة مرة عند الفتح — المعاينة على الذاكرة لا
  /// قاعدة، والتنفيذ يكتب بالقيم المعاينة ذاتها (لا انحراف بين ما رأى
  /// المالك وما كُتب).
  List<Item> _activeItems = const [];
  bool _loaded = false;

  /// مستويات المجموعات وأسعارها المخزنة — تقاطع F-165/D-187 (الدفعة 27):
  /// الآلي يُعاد اشتقاقه واليدوي يُضرب بالنسبة نفسها.
  Map<int, List<UnitGroupLevel>> _levelsByGroup = const {};
  Map<int, Map<int, (int, int)>> _levelPricesByItem = const {};

  /// صفوف المعاينة بعد آخر ضغطة «معاينة» — والتنفيذ منها حصراً.
  List<_PreviewRow> _preview = const [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final rows = await widget.db.select(widget.db.items).get();
    if (!mounted) return;
    final active = rows.where((r) => r.isActive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final levels = await widget.db.allUnitGroupLevels();
    final levelPrices = await widget.db
        .itemLevelPricesForItems(active.map((i) => i.id).toList());
    if (!mounted) return;
    setState(() {
      _activeItems = active;
      _levelsByGroup = levels;
      _levelPricesByItem = levelPrices;
      _loaded = true;
    });
  }

  /// التصنيفات المتاحة — النصوص غير الفارغة للأصناف النشطة مرتبة بلا
  /// تكرار (التصنيف نص اختياري أصلاً — 05).
  List<String> get _categories {
    final set = <String>{};
    for (final i in _activeItems) {
      final c = i.category?.trim() ?? '';
      if (c.isNotEmpty) set.add(c);
    }
    return set.toList()..sort();
  }

  List<Item> get _categoryItems => _category == null
      ? const []
      : _activeItems
          .where((i) => (i.category?.trim() ?? '') == _category)
          .toList();

  bool get _percentValid {
    final bps = parsePercentToBps(_percent.text);
    return bps != null && bps != 0;
  }

  /// بناء المعاينة — الحساب بمحرك المجال حصراً وصفوفه تُحفظ كما هي
  /// للتنفيذ فلا انحراف بين المعروض والمكتوب. ومستويات التعبئة
  /// (تقاطع F-165/D-187): الآلي يُعاد اشتقاقه من الأساس الجديد
  /// بخطوة واحدة، واليدوي يُضرب بالنسبة نفسها، والانكسار علم يُعرض.
  void _buildPreview() {
    final bps = parsePercentToBps(_percent.text);
    if (_category == null || bps == null || bps == 0) return;
    setState(() {
      _preview = [
        for (final item in _categoryItems)
          () {
            final out = bulkPriceOutcome(
              oldSalePriceMinor: item.salePriceMinor,
              oldPurchasePriceMinor: item.purchasePriceMinor,
              percentBps: bps,
              target: _target,
            );
            final groupLevels = item.unitGroupId == null
                ? const <UnitGroupLevel>[]
                : (_levelsByGroup[item.unitGroupId] ??
                    const <UnitGroupLevel>[]);
            final stored = _levelPricesByItem[item.id] ?? const {};
            final wantsSale = _target != BulkPriceTarget.purchase;
            final wantsPurchase = _target != BulkPriceTarget.sale;
            final levels = <_PreviewLevelRow>[
              for (final level in groupLevels)
                () {
                  final oldSale = stored[level.id]?.$1 ?? 0;
                  final oldPurchase = stored[level.id]?.$2 ?? 0;
                  final saleOut = wantsSale
                      ? bulkLevelPriceOutcome(
                          oldBasePriceMinor: item.salePriceMinor,
                          newBasePriceMinor: out.newSalePriceMinor,
                          factor: level.factor,
                          priceAuto: item.priceAuto,
                          oldLevelPriceMinor: oldSale,
                          percentBps: bps,
                        )
                      : null;
                  final purchaseOut = wantsPurchase
                      ? bulkLevelPriceOutcome(
                          oldBasePriceMinor: item.purchasePriceMinor,
                          newBasePriceMinor: out.newPurchasePriceMinor,
                          factor: level.factor,
                          priceAuto: item.priceAuto,
                          oldLevelPriceMinor: oldPurchase,
                          percentBps: bps,
                        )
                      : null;
                  return _PreviewLevelRow(
                    levelId: level.id,
                    name: level.name,
                    factor: level.factor,
                    oldSalePriceMinor: oldSale,
                    newSalePriceMinor:
                        saleOut?.newLevelPriceMinor ?? oldSale,
                    saleBroken: saleOut?.relationBroken ?? false,
                    oldPurchasePriceMinor: oldPurchase,
                    newPurchasePriceMinor:
                        purchaseOut?.newLevelPriceMinor ?? oldPurchase,
                    purchaseBroken: purchaseOut?.relationBroken ?? false,
                  );
                }(),
            ];
            return _PreviewRow(
              itemId: item.id,
              name: item.name,
              sku: item.sku,
              oldSalePriceMinor: item.salePriceMinor,
              oldPurchasePriceMinor: item.purchasePriceMinor,
              newSalePriceMinor: out.newSalePriceMinor,
              newPurchasePriceMinor: out.newPurchasePriceMinor,
              levels: levels,
            );
          }(),
      ];
    });
  }

  /// عدد الأصناف التي ستتغير فعلًا — الزائف لا يُعد (الصفر لا يتغير
  /// والحقل غير المستهدف لا يُعد تغييراً).
  int get _changedCount => _preview
      .where((r) =>
          r.newSalePriceMinor != r.oldSalePriceMinor ||
          r.newPurchasePriceMinor != r.oldPurchasePriceMinor)
      .length;

  Future<void> _execute() async {
    if (_preview.isEmpty || !_percentValid) return;
    final count = _changedCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الترقية الجماعية'),
        content: Text(
            'سيتم تعديل أسعار $count صنفاً من تصنيف «$_category» '
            'على $_targetLabel — المعاينة المعروضة هي ما سيُكتب حرفاً. '
            'فواتير التاريخ بلقطات أسعارها لا تُمس، ولا تراجع إلا بترقية '
            'معاكسة. ومستويات التعبئة: المشتق يُعاد اشتقاقه آلياً '
            'واليدوي يُضرب بالنسبة نفسها.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تنفيذ الترقية')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updates = [
      for (final r in _preview)
        if (r.newSalePriceMinor != r.oldSalePriceMinor ||
            r.newPurchasePriceMinor != r.oldPurchasePriceMinor)
          BulkPriceUpdateRow(
            itemId: r.itemId,
            newSalePriceMinor: (_target == BulkPriceTarget.sale ||
                    _target == BulkPriceTarget.both)
                ? r.newSalePriceMinor
                : null,
            newPurchasePriceMinor: (_target == BulkPriceTarget.purchase ||
                    _target == BulkPriceTarget.both)
                ? r.newPurchasePriceMinor
                : null,
            // مستويات التعبئة بقيمها المحسوبة ذاتها — والحقل غير
            // المستهدف لكل مستوى يُصان من صفه القائم بالتخزين.
            levels: [
              for (final l in r.levels)
                BulkLevelPriceUpdateRow(
                  levelId: l.levelId,
                  newSalePriceMinor: (_target == BulkPriceTarget.sale ||
                          _target == BulkPriceTarget.both)
                      ? l.newSalePriceMinor
                      : null,
                  newPurchasePriceMinor: (_target ==
                              BulkPriceTarget.purchase ||
                          _target == BulkPriceTarget.both)
                      ? l.newPurchasePriceMinor
                      : null,
                ),
            ],
          ),
    ];
    await widget.db.applyBulkPriceUpdates(updates);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('تمت ترقية أسعار ${updates.length} صنفاً — '
              'وفواتير التاريخ سليمة بلقطاتها')));
    await _loadItems();
    setState(() => _preview = const []);
  }

  String get _targetLabel => switch (_target) {
        BulkPriceTarget.sale => 'سعر البيع',
        BulkPriceTarget.purchase => 'سعر الشراء',
        BulkPriceTarget.both => 'سعري البيع والشراء',
      };

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    return Scaffold(
      appBar: AppBar(title: const Text('رفع أسعار جماعي')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
                  16,
                  diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
                  16),
              children: [
                if (categories.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'لا أصناف نشطة بتصنيف — التصنيف أساس الترقية '
                          'الجماعية. حرّر التصنيف في بطاقة الصنف '
                          'ثم عد لهذه الشاشة.'),
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                        labelText: 'التصنيف',
                        helperText:
                            'الأصناف النشطة ذات التصنيف الواحد حصراً — '
                            'والمعطلة خارج الترقية'),
                    items: [
                      for (final c in categories)
                        DropdownMenuItem<String>(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() {
                      _category = v;
                      _preview = const [];
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _percent,
                    keyboardType:
                        const TextInputType.numberWithOptions(signed: true),
                    inputFormatters: [
                      // النسبة إشارتها وعشريتها — والتحقق النقي يرفض
                      // ما عداه (مجال (−100%, +10000%] وخانتان).
                      _PercentInputFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: 'النسبة بالمئة (مثال: 2.5 أو -3)',
                      helperText: _percentValid
                          ? 'الصفر لا تغيير — والرفع والتخفيض يُرى أثرهما '
                              'بالمعاينة قبل أي كتابة'
                          : 'أدخل نسبة غير صفرية — أكتب خانتين عشريتين '
                              'كحد أقصى',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BulkPriceTarget>(
                    initialValue: _target,
                    decoration: const InputDecoration(
                        labelText: 'الهدف',
                        helperText: 'الحقل غير المستهدف لا يُمس إطلاقاً'),
                    items: [
                      for (final t in BulkPriceTarget.values)
                        DropdownMenuItem<BulkPriceTarget>(
                            value: t, child: Text(t.label)),
                    ],
                    onChanged: (v) => setState(() {
                      if (v != null) _target = v;
                      _preview = const [];
                    }),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed:
                        (_category != null && _percentValid)
                            ? _buildPreview
                            : null,
                    child: Text(
                        'معاينة (${_categoryItems.length} صنفاً في التصنيف)'),
                  ),
                ],
                if (_preview.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'المعاينة — ${_changedCount} صنفاً ستتغير أسعاره '
                    'من ${_categoryItems.length} بالتصنيف:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Table(
                        border: TableBorder.symmetric(
                            inside: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant)),
                        columnWidths: const {
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(2),
                          2: FlexColumnWidth(2),
                        },
                        children: [
                          const TableRow(children: [
                            Padding(
                                padding: EdgeInsets.all(6),
                                child: Text('الصنف',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Padding(
                                padding: EdgeInsets.all(6),
                                child: Text('القديم',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Padding(
                                padding: EdgeInsets.all(6),
                                child: Text('الجديد',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                          ]),
                          for (final r in _preview) ...[
                            TableRow(children: [
                              Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text('${r.name} (${r.sku})')),
                              Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                      _targetPricesLabel(r.oldSalePriceMinor,
                                          r.oldPurchasePriceMinor))),
                              Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                      _targetPricesLabel(
                                          r.newSalePriceMinor,
                                          r.newPurchasePriceMinor))),
                            ]),
                            // مستويات التعبئة أسفل صنفها — والانكسار
                            // سطر تحذير بالمعاينة (المتطلب حرفاً).
                            for (final l in r.levels)
                              TableRow(children: [
                                Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                      '— ${l.name} ×${l.factor}'
                                      '${l.brokenLabel(_target)}',
                                      style: const TextStyle(fontSize: 12),
                                    )),
                                Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                        _targetPricesLabel(
                                            l.oldSalePriceMinor,
                                            l.oldPurchasePriceMinor),
                                        style: const TextStyle(
                                            fontSize: 12))),
                                Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                        _targetPricesLabel(
                                            l.newSalePriceMinor,
                                            l.newPurchasePriceMinor),
                                        style: const TextStyle(
                                            fontSize: 12))),
                              ]),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _changedCount > 0 ? _execute : null,
                    child: Text('تنفيذ الترقية على $_changedCount صنفاً'),
                  ),
                ],
              ],
            ),
    );
  }

  /// لسان عمودي القديم/الجديد — الحقلان حين «كلاهما» وحدهما، وحقل
  /// الهدف الواحد فيما سوى.
  String _targetPricesLabel(int saleMinor, int purchaseMinor) =>
      switch (_target) {
        BulkPriceTarget.sale => formatMinorAmount(saleMinor),
        BulkPriceTarget.purchase => formatMinorAmount(purchaseMinor),
        BulkPriceTarget.both =>
          'بيع ${formatMinorAmount(saleMinor)} · شراء ${formatMinorAmount(purchaseMinor)}',
      };
}

/// صف معاينة — قيمته القديمة والجديدة معاً كما حسبها محرك المجال
/// لحظة المعاينة، والتنفيذ من هذه القيم حصراً فما رأى المالك هو ما
/// يُكتب حرفاً.
class _PreviewRow {
  final int itemId;
  final String name;
  final String sku;
  final int oldSalePriceMinor;
  final int oldPurchasePriceMinor;
  final int newSalePriceMinor;
  final int newPurchasePriceMinor;

  /// مستويات التعبئة للصنف — تقاطع F-165/D-187.
  final List<_PreviewLevelRow> levels;

  const _PreviewRow({
    required this.itemId,
    required this.name,
    required this.sku,
    required this.oldSalePriceMinor,
    required this.oldPurchasePriceMinor,
    required this.newSalePriceMinor,
    required this.newPurchasePriceMinor,
    this.levels = const [],
  });
}

/// صف معاينة مستوى تعبئة — القيم القديمة والجديدة وعلمان الانكسار
/// لكل حقل كما حسبها محرك المجال لحظة المعاينة.
class _PreviewLevelRow {
  final int levelId;
  final String name;
  final int factor;
  final int oldSalePriceMinor;
  final int newSalePriceMinor;
  final bool saleBroken;
  final int oldPurchasePriceMinor;
  final int newPurchasePriceMinor;
  final bool purchaseBroken;

  const _PreviewLevelRow({
    required this.levelId,
    required this.name,
    required this.factor,
    required this.oldSalePriceMinor,
    required this.newSalePriceMinor,
    required this.saleBroken,
    required this.oldPurchasePriceMinor,
    required this.newPurchasePriceMinor,
    required this.purchaseBroken,
  });

  /// سطر التحذير (المتطلب حرفاً): انكسار علاقة السعر بالكمية للحقل
  /// المستهدف حصراً.
  String brokenLabel(BulkPriceTarget target) {
    final broken = switch (target) {
      BulkPriceTarget.sale => saleBroken,
      BulkPriceTarget.purchase => purchaseBroken,
      BulkPriceTarget.both => saleBroken || purchaseBroken,
    };
    return broken ? ' — ⚠ انكسار علاقة السعر بالكمية' : '';
  }
}

/// مدقق حرف النسبة — إشارة وأرقام ونقطة عشرية بخانتين حصراً (ما عداه
/// يرفضه مدقق المجال parsePercentToBps بالرسالة، وهذا حرس الحروف
/// الأول نمط المدققين القائمين).
class _PercentInputFormatter extends TextInputFormatter {
  static final RegExp _allowed = RegExp(r'^[+-]?[0-9]*(\.[0-9]{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty || _allowed.hasMatch(text)) return newValue;
    return oldValue;
  }
}
