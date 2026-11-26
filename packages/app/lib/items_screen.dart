import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
import 'input_formatters.dart';
import 'item_images.dart';
import 'price_update_screen.dart';
import 'unit_groups_screen.dart';
import 'item_media.dart';
import 'item_crop_screen.dart';
import 'reports_screen.dart' show formatMinorAmount;
import 'dq_log.dart';
import 'context_menu.dart';

/// شاشة الأصناف (F-030/F-031 — دفعة م1 الثانية، س-36..س-41).
///
/// - س-107 (دفعة 8/D-102): كل سطر في القائمة يعرض سعر البيع مفصولاً
///   (والصفر «بلا سعر بعد» لا يُعرض) — فتُقرأ القائمة عيناً السوق.
///
/// - القائمة تعرض الجميع بصيغة «الاسم (الكود)» مرتبة معجمياً بالاسم
///   (D-074) — والمعطّل بشارة لا يُخفى: إعادة التفعيل ممكنة متى شئت
///   (س-40)، وزر الحذف غير موجود أصلاً في أي بطاقة.
/// - البحث خانة واحدة جامعة (الاسم والكود والتصنيف) بكلمات متفرقة تلتقي
///   وتطبيع عربي في البحث فقط (D-064/س-38)، والنتيجة الفارغة رسالة لا
///   صمت (س-38).
/// - الوحدة الأساسية إلزامية بالاختيار (F-031): قائمة وحدات ينموها
///   المستخدم بنفسه من البطاقة (س-41) — وحدات التعبئة المتعددة م2
///   (F-032) والإدخال في م1 بالوحدة الأساسية فقط.
class ItemsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const ItemsScreen({super.key, required this.db});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  String _query = '';

  // التدفق يُنشأ مرة واحدة لعمر الحالة لا عند كل بناء (علّة CI 2026-10-29
  // س23): تمرير تدفق جديد في build يعيد StreamBuilder الاشتراك عند كل إعادة
  // بناء فيحلّق الجلب والتحديث بلا نهاية — النمط الممنوع الموثق.
  late final Stream<List<Item>> _itemsStream = widget.db
      .select(widget.db.items)
      .watch()
      .map(
        (rows) => [...rows]..sort((a, b) => a.name.compareTo(b.name)),
      );

  void _openNewItem() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditScreen(db: widget.db),
      ),
    );
  }

  void _openItem(Item item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditScreen(db: widget.db, existing: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأصناف'),
        actions: [
          // الدفعة 27 (F-032/D-026): إدارة مجموعات التعبئة — قوالب
          // غير حصرية والمستخدم يعرّف وحداته ومستوياته الأعلى.
          IconButton(
            tooltip: 'مجموعات التعبئة',
            icon: const Icon(Icons.layers_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => UnitGroupsScreen(db: widget.db),
                ),
              );
            },
          ),
          // الدفعة 23 (F-165/D-183): الترقية الجماعية للأسعار بالتصنيف —
          // معاينة قبل التنفيذ وفواتير التاريخ بلقطاتها سليمة.
          IconButton(
            tooltip: 'رفع أسعار جماعي بالتصنيف',
            icon: const Icon(Icons.trending_up_outlined),
            onPressed: () {
              // القائمة تتغذى من watch() فتتجدد ذاتياً بعد الترقية
              // بلا إعادة تحميل يدوي (نمط الدفق الموثق أعلاه).
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PriceUpdateScreen(db: widget.db),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewItem,
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('إضافة صنف'),
      ),
      body: DiqqahAdaptiveCenter(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              // س198 (م13 من تقرير فحص الواجهات وفق M3): كان الحقل
              // الوحيد بالشاشات السبع على OutlineInputBorder بينما
              // البقية على النمط الممتلئ الافتراضي، وعلى النص الإرشادي
              // وحده لا عنوان دائم — فتوحّد على نمط العائلة بعنوان
              // دائم وأيقونة البحث المسبقة الباقية كما هي.
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'بحث بالاسم أو الكود أو التصنيف',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Item>>(
              stream: _itemsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!;
                final visible = all
                    .where(
                      (i) => ItemSearchFields(
                        name: i.name,
                        sku: i.sku,
                        category: i.category ?? '',
                      ).matchesQuery(_query),
                    )
                    .toList();
                if (visible.isEmpty) {
                  // النتائج الفارغة برسالة لا بصمت (س-38)
                  return Center(
                    child: Text(
                      all.isEmpty
                          ? 'لا أصناف بعد — أضف أول صنف بزر «إضافة صنف»'
                          : 'لا نتائج مطابقة للبحث',
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    final kind = ItemKind.fromStorage(item.kind);
                    final category = item.category;
                    // س207 (بند 2): قائمة السياق الموحدة — فعالياتها
                    // القائمة حصراً بنمط الفواتير.
                    return RecordContextMenu(
                      actions: [
                        RecordContextAction(
                          label: 'فتح الصنف',
                          icon: Icons.inventory_2_outlined,
                          onSelected: () => _openItem(item),
                        ),
                        copyIdAction(context, item.id),
                      ],
                      child: ListTile(
                      leading: Icon(
                        item.isActive
                            ? Icons.inventory_2_outlined
                            : Icons.inventory_2,
                      ),
                      title: Text(itemDisplayLabel(item.name, item.sku)),
                      subtitle: Text(
                        kind.label +
                            (category == null ? '' : ' · $category') +
                            // س-107: سعر البيع مفصولاً بجانب النوع.
                            (item.salePriceMinor > 0
                                ? ' · سعر بيع: '
                                    '${formatMinorAmount(item.salePriceMinor)}'
                                : ''),
                      ),
                      trailing: item.isActive
                          ? null
                          : const Chip(
                              label: Text('معطّل'),
                              visualDensity: VisualDensity.compact,
                            ),
                      onTap: () => _openItem(item),
                    ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}

/// بطاقة صنف — إضافة أو تعديل (F-030/F-031، س-36/س-39).
///
/// - الكود لا يقترح آلياً (D-073: كود الصنف كلمة المالك والباركود لا
///   تسلسل — عكس رقم الطرف المقترح)، ولا يعدل بعد الحفظ — الهوية الثابتة
///   (المعرف) بها ترتبط الفواتير لاحقاً.
/// - الاسم إلزامي وحده (س-36) ومنع تكراره الحرفي صارم (D-074).
/// - الوحدة الأساسية إلزامية بالاختيار من القائمة (F-031) — وإضافة وحدة
///   جديدة من البطاقة نفسها (س-41) تختار فوراً.
/// - الأسعار بوحدات صغرى صحيحة (س7)، والصفر «بلا سعر بعد» مشروع والسالب
///   مرفوض (س6). العملة معبأة بالأساسية ولا تُحفظ فارغة (D-066 الاصطلاح).
/// - التجميعي خارج الشريحة في م1 (F-034 م2) — بضاعة وخدمة حصراً.
class ItemEditScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final Item? existing;

  /// فواصل الاختبارات حصراً — الإنتاج يستدعي مسارات المنصة الحقيقية
  /// (image_picker/mobile_scanner) بلا قنوات في الاختبارات (نمط الحقن).
  final Future<List<int>?> Function({required bool fromCamera})? onPickSource;
  final Future<String?> Function()? onScanBarcode;

  const ItemEditScreen({
    super.key,
    required this.db,
    this.existing,
    this.onPickSource,
    this.onScanBarcode,
  });

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

/// صف وصفة التجميعي في المحرر — المكوّن وكميته وتكلفة الخدمة إن قُيمت
/// (F-034/F-212، الدفعة 28) — ومتحكماته تُصفّى مع الصف عند إزالته.
class _RecipeRow {
  int? itemId;
  final TextEditingController qty = TextEditingController();
  final TextEditingController cost = TextEditingController();

  _RecipeRow({this.itemId, String qty = '', String cost = ''}) {
    this.qty.text = qty;
    this.cost.text = cost;
  }

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _purchase = TextEditingController();
  final _sale = TextEditingController();

  /// الحد الأدنى المحدد — د6 (س175) المتابعات اليومية (س74/D-184):
  /// الفراغ بلا حد فلا متابعة، والموجب حصراً (الحرس بالتخزين).
  final _minQty = TextEditingController();
  late ItemKind _kind;
  int? _unitId;
  List<Unit> _units = const [];

  // ── وصفة التجميعي (F-034/F-212، الدفعة 28) ──
  /// مرشّحو المكونات: الأصناف النشطة بلا تجميعي (بضاعة أو خدمة حصراً —
  /// لا تداخل وصفة) وبلا الصنف ذاته.
  List<Item> _recipeCandidates = const [];

  /// صفوف الوصفة قبل الحفظ — المكوّن وكميته وتكلفة الخدمة إن قُيمت.
  final List<_RecipeRow> _recipeRows = [];

  // ── مجموعات التعبئة وأسعارها آلي (F-032/F-208، D-026/D-187) ──
  List<UnitGroup> _groups = const [];
  int? _unitGroupId;

  /// مربع «آلي» — افتراضه مفعّل (D-187): الوحدة الصغرى للكتابة
  /// والمستويات للقراءة تُشتق، وتعطيله يتاح كل الخانات.
  bool _priceAuto = true;
  List<UnitGroupLevel> _levels = const [];

  /// معرّف المستوى ← متحكما (بيع، شراء) — خانة مستقلة لكل مستوى.
  final Map<int, (TextEditingController, TextEditingController)>
      _levelPriceCtrls = {};

  /// العملة الأساسية حصراً حتى تُبنى جدول العملات (D-017/D-066 الاصطلاح).
  static const int _baseCurrencyId = 1;

  bool _saving = false;

  // ── صورة الصنف (س-123/س-124، D-120/D-121/D-125) ──
  /// معاينة الإدخال قبل الحفظ — لا ملف يُكتب إلا عند الحفظ فلا ملفات
  /// يتيمة عند الإلغاء (س-124).
  List<int>? _pendingOriginal;
  List<int>? _pendingThumb;
  bool _imageBusy = false;

  /// طلب حذف صورة قائمة (وضع التعديل) — ينفذ عند الحفظ مع مسح الملفين.
  bool _deleteImage = false;

  // ── الباركود (س-131/س-132، D-126) ──
  final _barcodeController = TextEditingController();

  /// رموز الصنف القائمة (وضع التعديل — من الجدول الجاهز F-035).
  List<ItemBarcode> _barcodes = const [];

  /// رموز الصنف الجديد قبل أول حفظ (وضع الإضافة) — تُفحص وتُدرج عند
  /// الحفظ فلا رمز يتيم لصنف لم يُحفظ.
  final List<String> _pendingBarcodes = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    if (item != null) {
      _sku.text = item.sku;
      _name.text = item.name;
      _category.text = item.category ?? '';
      // مفصولاً (D-102): العرض والحفظ مفصولان — والصفر يبقى فارغاً.
      _purchase.text =
          item.purchasePriceMinor > 0 ? groupDigits(item.purchasePriceMinor) : '';
      _sale.text =
          item.salePriceMinor > 0 ? groupDigits(item.salePriceMinor) : '';
      _minQty.text = item.minQty != null ? '${item.minQty}' : '';
      _kind = ItemKind.fromStorage(item.kind);
      _unitId = item.baseUnitId;
      _unitGroupId = item.unitGroupId;
      _priceAuto = item.priceAuto;
    } else {
      _kind = ItemKind.good;
    }
    _loadUnits();
    _loadUnitGroups();
    _loadRecipeCandidates();
    if (_isEdit) {
      _loadBarcodes();
      if (_kind == ItemKind.bundle) {
        _loadExistingRecipe();
      }
    }
  }

  /// مرشّحو المكونات — الأصناف النشطة بلا تجميعي وبلا الصنف ذاته
  /// (بضاعة أو خدمة حصراً — F-034/F-212).
  Future<void> _loadRecipeCandidates() async {
    final rows = await widget.db.select(widget.db.items).get();
    if (!mounted) return;
    setState(() {
      _recipeCandidates = rows
          .where((r) =>
              r.isActive && r.kind != 'bundle' && r.id != widget.existing?.id)
          .toList();
    });
  }

  /// الوصفة القائمة في وضع التعديل — صفوف المحرر بلقطة الجدول.
  Future<void> _loadExistingRecipe() async {
    final rows =
        await widget.db.bundleRecipeByItem(widget.existing!.id);
    if (!mounted) return;
    setState(() {
      _recipeRows
        ..clear()
        ..addAll([
          for (final r in rows)
            _RecipeRow(
              itemId: r.componentItemId,
              qty: groupDigits(r.qtyBase),
              cost: (r.costMinor ?? 0) > 0 ? groupDigits(r.costMinor!) : '',
            ),
        ]);
    });
  }

  /// رموز الصنف القائمة — قسم الباركود في وضع التعديل (س-131).
  Future<void> _loadBarcodes() async {
    final rows =
        await widget.db.barcodesOfItem(widget.existing!.id);
    if (!mounted) return;
    setState(() => _barcodes = rows);
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _category.dispose();
    _purchase.dispose();
    _sale.dispose();
    _minQty.dispose();
    _barcodeController.dispose();
    for (final ctrls in _levelPriceCtrls.values) {
      ctrls.$1.dispose();
      ctrls.$2.dispose();
    }
    for (final row in _recipeRows) {
      row.dispose();
    }
    super.dispose();
  }

  /// اسم الصنف الحالي للنائب البصري — الجديد من الحقل قبل حفظه.
  String get _currentItemName {
    final fromCard = _name.text.trim();
    if (fromCard.isNotEmpty) return fromCard;
    return widget.existing?.name ?? 'صنف';
  }

  /// مسارَي الصورة القائمة (وضع التعديل) — للحذف عند الاستبدال (س-124).
  (String?, String?) get _existingImagePaths =>
      (widget.existing?.imageFile, widget.existing?.imageThumb);

  bool get _hasExistingImage =>
      _existingImagePaths.$1 != null || _existingImagePaths.$2 != null;

  /// كتابة الملفين وتثبيت المسارين النسبيين على الصف (س-123/D-125).
  Future<void> _writeImagesFor(int itemId) async {
    final paths = await writeItemImagesFiles(
      itemId: itemId,
      original: _pendingOriginal!,
      thumb: _pendingThumb!,
    );
    await widget.db.setItemImages(
      itemId,
      imageFile: paths.$1,
      imageThumb: paths.$2,
    );
  }

  /// قائمة الوحدات تُحمّل مرة وتُحدَّث بعد كل إضافة وحدة — لا تدفق هنا
  /// (إضافة حصراً في م1: لا تعديل ولا حذف لوحدة يغير القائمة من خلفية
  /// أخرى — D-075).
  Future<void> _loadUnits() async {
    final rows =
        await widget.db.select(widget.db.units).get();
    if (!mounted) return;
    setState(() => _units = rows);
  }

  // ── مجموعات التعبئة وأسعارها آلي (F-032/F-208، D-026/D-187) ──

  Future<void> _loadUnitGroups() async {
    final groups = await widget.db.allUnitGroups();
    if (!mounted) return;
    setState(() => _groups = groups);
    if (_unitGroupId != null) {
      await _reloadLevels();
    }
  }

  /// مستويات المجموعة المختارة وأسعارها المخزنة — الوضع الجديد يبدأ
  /// بلا أسعار مخزنة فالآلي يشتق من الأساس فوراً.
  Future<void> _reloadLevels() async {
    final gid = _unitGroupId;
    for (final ctrls in _levelPriceCtrls.values) {
      ctrls.$1.dispose();
      ctrls.$2.dispose();
    }
    _levelPriceCtrls.clear();
    if (gid == null) {
      _levels = const [];
      if (mounted) setState(() {});
      return;
    }
    final levels = await widget.db.levelsOfGroup(gid);
    final stored = _isEdit
        ? await widget.db.itemLevelPriceMap(widget.existing!.id)
        : const <int, (int, int)>{};
    if (!mounted) return;
    setState(() {
      _levels = levels;
      for (final level in levels) {
        final saved = stored[level.id];
        _levelPriceCtrls[level.id] = (
          TextEditingController(
              text: (saved?.$1 ?? 0) > 0 ? groupDigits(saved!.$1) : ''),
          TextEditingController(
              text: (saved?.$2 ?? 0) > 0 ? groupDigits(saved!.$2) : ''),
        );
      }
    });
    if (_priceAuto) _syncDerivedControllers();
  }

  void _switchGroup(int? groupId) {
    setState(() => _unitGroupId = groupId);
    _reloadLevels();
  }

  /// الاشتقاق اللحظي (D-187): الآلي يترك الوحدة الصغرى للكتابة
  /// والمستويات للقراءة تُشتق من الأساس بالعامل — يُعاد الحساب لحظة
  /// كل كتابة بالأساس (الفرق الحي بonChanged — درس س79) وبتعطيل
  /// الآلي تتاح الخانات كما كُتبت.
  void _syncDerivedControllers() {
    if (!_priceAuto) return;
    final sale = _parsePrice(_sale);
    final purchase = _parsePrice(_purchase);
    for (final level in _levels) {
      final ctrls = _levelPriceCtrls[level.id];
      if (ctrls == null) continue;
      final s = derivedLevelPriceMinor(
          basePriceMinor: sale < 0 ? 0 : sale, factor: level.factor);
      final p = derivedLevelPriceMinor(
          basePriceMinor: purchase < 0 ? 0 : purchase, factor: level.factor);
      ctrls.$1.text = s > 0 ? groupDigits(s) : '';
      ctrls.$2.text = p > 0 ? groupDigits(p) : '';
    }
  }

  void _togglePriceAuto(bool value) {
    setState(() {
      _priceAuto = value;
      if (value) {
        // أثر معلن (D-187): إعادة التفعيل بعد تسعير يدوي تعيد
        // الاشتقاق وتستبدل قيم المستويات الأعلى.
        _syncDerivedControllers();
      }
    });
    if (value) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text(
                'الآلي مفعّل — قيم المستويات تُشتق من الأساس وتُستبدل '
                'عند الحفظ')));
    }
  }

  /// سعر مستوى يدوي يصل الحفظ — السالب حُرس قبل الحفظ فاستيفاء أمان.
  int _levelPriceSaved(TextEditingController c) {
    final v = _parsePrice(c);
    return v < 0 ? 0 : v;
  }

  // ── محرر وصفة التجميعي (F-034/F-212، الدفعة 28) ──

  void _addRecipeRow() {
    setState(() => _recipeRows.add(_RecipeRow()));
  }

  void _removeRecipeRow(int index) {
    setState(() {
      _recipeRows[index].dispose();
      _recipeRows.removeAt(index);
    });
  }

  /// المكوّن الخدمي؟ — خانة التكلفة لخدمة الوصفة بالخيارين حصراً (F-212).
  bool _recipeRowIsService(_RecipeRow row) {
    final id = row.itemId;
    if (id == null) return false;
    final match = _recipeCandidates.where((c) => c.id == id).toList();
    return match.isNotEmpty && match.single.kind == 'service';
  }

  /// مرشّحو الصف: بلا مكرر عبر الصفوف — المكوّن مرة واحدة بالوصفة
  /// (س-09 روحاً والمكرر مرفوض بالمدقق) فلا يُعرض المستخدم حرفاً ممنوعاً.
  List<Item> _recipeRowCandidates(int index) {
    final usedElsewhere = <int>{
      for (var i = 0; i < _recipeRows.length; i++)
        if (i != index && _recipeRows[i].itemId != null)
          _recipeRows[i].itemId!,
    };
    return _recipeCandidates
        .where((c) =>
            !usedElsewhere.contains(c.id) || c.id == _recipeRows[index].itemId)
        .toList();
  }

  Widget _recipeRowCard(int index) {
    final row = _recipeRows[index];
    final isService = _recipeRowIsService(row);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: row.itemId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المكوّن'),
              items: [
                for (final it in _recipeRowCandidates(index))
                  DropdownMenuItem<int>(
                    value: it.id,
                    child: Text(
                      '${it.sku} ${it.name}'
                      '${it.kind == 'service' ? ' (خدمة)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => row.itemId = value),
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: row.qty,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'الكمية لكل وحدة',
                      helperText: 'بوحدة الصنف الأساسية',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isService)
                  Expanded(
                    child: TextFormField(
                      controller: row.cost,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'تكلفة الخدمة (اختياري)',
                        helperText: 'فارغة = بند بيعي ضمن السعر',
                        isDense: true,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'إزالة المكوّن',
                  onPressed: _saving ? null : () => _removeRecipeRow(index),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// مدقق الوصفة قبل الحفظ — رسالة واحدة أول خطأ (نمط س-36) والرفض
  /// قبل الكتابة حصراً فلا صنف يُحفظ بوصفة مكسورة.
  String? _recipeRowsValidationError() {
    final seen = <int>{};
    for (final row in _recipeRows) {
      if (row.itemId == null) {
        return 'اختَر المكوّن في كل صف — أو أزِل الصف الفارغ';
      }
      if (seen.contains(row.itemId)) {
        return 'المكوّن نفسه لا يتكرر بالوصفة — الصف الواحد بكميته الكلية';
      }
      seen.add(row.itemId!);
      final qty = parseGroupedInt(row.qty.text.trim(), fallback: -1);
      if (qty <= 0) {
        return 'كمية المكوّن موجبة حصراً — والفراغ ليس كمية';
      }
      final costText = row.cost.text.trim();
      if (costText.isNotEmpty) {
        final cost = parseGroupedInt(costText, fallback: -1);
        if (cost < 0) {
          return 'تكلفة الخدمة عدد موجب إن أُدخلت — والفراغ بند بيعي';
        }
      }
    }
    return null;
  }

  /// قراءة سعر: الفراغ صفر مشروع «بلا سعر بعد» (س-36)، وإدخال شاذ
  /// (فائض طول مثلاً رغم قيد الأرقام) يعود -1 فيلتقطه مدقق المجال (س6).
  int _parsePrice(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return 0;
    return parseGroupedInt(text, fallback: -1);
  }

  ExistingItem _asExisting(Item item) => ExistingItem(
        id: item.id,
        sku: item.sku,
        name: item.name,
        isActive: item.isActive,
      );

  /// س-123/س-124: دخول الصورة من الكاميرا أو المعرض — لا صورة تدخل إلا
  /// عبر المحرك الإلزامي (D-120) بإطارها المربع (D-121)، وفشل الإذن أو
  /// الكاميرا أو صورة فاسدة رسالة عربية والبطاقة تعمل بلا صورة أبداً.
  Future<void> _pickImage({required bool fromCamera}) async {
    if (_imageBusy || _saving) return;
    final picker = widget.onPickSource ?? pickItemSourceBytes;
    try {
      final raw = await picker(fromCamera: fromCamera);
      if (raw == null || !mounted) return; // إلغاء المستخدم — لم يحدث شيء
      setState(() => _imageBusy = true);
      // فاسد يُرفض هنا قبل أي شاشة (س-123: صورة فاسدة تُرفض ولا تُفسد
      // البطاقة) — والأبعاد المُدرّاة تسبق شاشة الإطار فلا فك مزدوج.
      final size = inspectItemImage(raw);
      if (!mounted) return;
      final crop = await Navigator.of(context).push<ItemImageCrop>(
        MaterialPageRoute<ItemImageCrop>(
          builder: (_) => ItemCropScreen(
            rawBytes: raw,
            imageWidth: size.width,
            imageHeight: size.height,
          ),
        ),
      );
      if (crop == null || !mounted) {
        if (mounted) setState(() => _imageBusy = false);
        return;
      }
      final result = ingestItemImage(raw, crop: crop);
      if (!mounted) return;
      setState(() {
        _pendingOriginal = result.originalJpeg;
        _pendingThumb = result.thumbJpeg;
        _deleteImage = false;
        _imageBusy = false;
      });
    } on ItemImageException catch (e) {
      await dqLog(widget.db, e, context: 'item.image');
      if (!mounted) return;
      setState(() => _imageBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('${e.toString()}${dqTag(e)}')));
    } catch (e) {
      await dqLog(widget.db, e, context: 'item.image');
      if (!mounted) return;
      setState(() => _imageBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('تعذر تجهيز الصورة — $e${dqTag(e)}')),
        );
    }
  }

  /// س-124: الحذف بمطابقة — للقائمة يمسح الحقل، والملفان يمسحان عند
  /// الحفظ (وضع التعديل) فلا يتيمة ولا بقاء بصمة قديمة.
  void _requestImageDelete() {
    setState(() {
      _pendingOriginal = null;
      _pendingThumb = null;
      _deleteImage = true;
    });
  }

  /// س-131: إضافة رمز — التفرد برسالة الصنف الحامل الحرفية، وقارئ
  /// البلوتوث يكتب في الخانة مباشرة بلا كاميرا أصلاً (س-132).
  Future<void> _addBarcode() async {
    final code = _barcodeController.text.trim();
    if (code.isEmpty || _saving) return;
    final holder = await widget.db.barcodeHolder(code);
    if (!mounted) return;
    if (holder != null &&
        (widget.existing == null || holder.itemId != widget.existing!.id)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('الرمز مستخدم للصنف: ${holder.displayLabel}'),
        ));
      return;
    }
    if (_isEdit) {
      if (_barcodes.any((b) => b.barcode.trim() == code)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
              const SnackBar(content: Text('الرمز مضاف لهذا الصنف مسبقاً')));
        return;
      }
      await widget.db
          .insertItemBarcode(itemId: widget.existing!.id, barcode: code);
      if (!mounted) return;
      setState(() => _barcodeController.clear());
      await _loadBarcodes();
      return;
    }
    if (_pendingBarcodes.contains(code)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('الرمز مضاف لهذا الصنف مسبقاً')));
      return;
    }
    setState(() {
      _pendingBarcodes.add(code);
      _barcodeController.clear();
    });
  }

  /// س-131: حذف رمز من قسم الباركود — وضع التعديل مباشرة والجديد من
  /// قائمة الانتظار.
  Future<void> _deleteBarcode(ItemBarcode b) async {
    await widget.db.deleteItemBarcode(b.id);
    if (!mounted) return;
    await _loadBarcodes();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // س-131: رموز الصنف الجديد تُفحص قبل الإدراج — مكرر يرفض الحفظ
      // كله برسالة الصنف الحامل ويبقى النموذج كما هو (إلغاء آمن).
      if (!_isEdit && _pendingBarcodes.isNotEmpty) {
        for (final code in _pendingBarcodes) {
          final holder = await widget.db.barcodeHolder(code);
          if (!mounted) return;
          if (holder != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text('الرمز مستخدم للصنف: ${holder.displayLabel}'),
              ));
            return;
          }
        }
      }
      // د6 (س175): الحد الأدنى المحدد — الفراغ بلا حد، والحرس الموجب
      // بالتخزين يخزّن الصفر والسالب null فلا حد بلا معنى.
      final minQty = _minQty.text.trim().isEmpty
          ? null
          : int.tryParse(_minQty.text.trim());
      final draft = ItemDraft(
        sku: _sku.text,
        name: _name.text,
        category: _category.text,
        kind: _kind,
        baseUnitId: _unitId ?? 0,
        purchasePriceMinor: _parsePrice(_purchase),
        salePriceMinor: _parsePrice(_sale),
        currencyId: _baseCurrencyId,
      );
      final rows = await widget.db.select(widget.db.items).get();
      final errors = validateItemDraft(
        draft,
        existing: ItemUniquenessIndex.build(rows.map(_asExisting)),
        excludeItemId: widget.existing?.id,
      );
      if (errors.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(itemErrorText(errors.first)),
              duration: const Duration(seconds: 4),
            ),
          );
        return;
      }
      // س6: سعر المستوى اليدوي لا يصل سالباً — والفراغ صفر مشروع.
      if (!_priceAuto) {
        for (final level in _levels) {
          final ctrls = _levelPriceCtrls[level.id]!;
          if (_parsePrice(ctrls.$1) < 0 || _parsePrice(ctrls.$2) < 0) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                content: Text('سعر مستوى التعبئة عدد موجب إن أُدخل — '
                    'والفراغ يعني بلا سعر بعد'),
                duration: Duration(seconds: 4),
              ));
            return;
          }
        }
      }
      // وصفة التجميعي (F-034/F-212): المدقق ما قبل الكتابة حصراً فلا
      // صنف يُحفظ بوصفة مكسورة — رسالة واحدة أول خطأ (نمط س-36).
      if (_kind == ItemKind.bundle) {
        final recipeError = _recipeRowsValidationError();
        if (recipeError != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(recipeError),
              duration: const Duration(seconds: 4),
            ));
          return;
        }
      }
      int? savedItemId;
      if (_isEdit) {
        savedItemId = widget.existing!.id;
        // س-155/D-153 (دفعة 17): الكود يعدل بلفظ المالك (س50/1 «تمام»)
        // — والفواتير كلها بمعرفه الخفي، والتفرد الحرفي دُقق أعلاه
        // بالمدقق المستثنياً النفس (س-39).
        await widget.db.updateItemDetails(
          widget.existing!,
          sku: draft.sku.trim(),
          name: draft.name.trim(),
          category: draft.category.trim(),
          kind: _kind.storageValue,
          baseUnitId: draft.baseUnitId,
          purchasePriceMinor: draft.purchasePriceMinor,
          salePriceMinor: draft.salePriceMinor,
          priceCurrencyId: _baseCurrencyId,
          // المجموعة والمربع الآلي يُكتبان صريحين — الإلغاء يمسح
          // الربط بقيمة null الصريحة لا بالمرور (نمط _keepCurrent).
          unitGroupId: _unitGroupId,
          priceAuto: _priceAuto,
          minQty: minQty,
        );
      } else {
        savedItemId = await widget.db.insertItem(
          sku: draft.sku.trim(),
          name: draft.name.trim(),
          category: draft.category.trim(),
          kind: _kind.storageValue,
          baseUnitId: draft.baseUnitId,
          purchasePriceMinor: draft.purchasePriceMinor,
          salePriceMinor: draft.salePriceMinor,
          priceCurrencyId: _baseCurrencyId,
          unitGroupId: _unitGroupId,
          priceAuto: _priceAuto,
          minQty: minQty,
        );
        // س-131: رموز الصنف الجديد تُدرج بعد نجاح الإدراج حصراً.
        for (final code in _pendingBarcodes) {
          await widget.db
              .insertItemBarcode(itemId: savedItemId, barcode: code);
        }
      }
      // أسعار المستويات (F-208/D-187): الآلي يكتب الاشتقاق المحسوب
      // بمحرك المجال — فإعادة التفعيل بعد يدوي تستبدل القيم فعلاً —
      // واليدوي يكتب ما كتبه المالك.
      if (_unitGroupId != null && _levels.isNotEmpty) {
        final saleBase = _parsePrice(_sale);
        final purchaseBase = _parsePrice(_purchase);
        await widget.db.saveItemLevelPrices(
          savedItemId,
          [
            for (final level in _levels)
              (
                levelId: level.id,
                salePriceMinor: _priceAuto
                    ? derivedLevelPriceMinor(
                        basePriceMinor: saleBase < 0 ? 0 : saleBase,
                        factor: level.factor)
                    : _levelPriceSaved(_levelPriceCtrls[level.id]!.$1),
                purchasePriceMinor: _priceAuto
                    ? derivedLevelPriceMinor(
                        basePriceMinor: purchaseBase < 0 ? 0 : purchaseBase,
                        factor: level.factor)
                    : _levelPriceSaved(_levelPriceCtrls[level.id]!.$2),
              ),
          ],
        );
      }
      // وصفة التجميعي (F-034/F-212): تُكتب بعد الصنف — والتجميعي حصراً.
      if (_kind == ItemKind.bundle) {
        await widget.db.saveBundleRecipe(savedItemId, [
          for (final row in _recipeRows)
            BundleComponentDraft(
              componentItemId: row.itemId!,
              qtyBase: parseGroupedInt(row.qty.text.trim()),
              costMinor: row.cost.text.trim().isEmpty
                  ? null
                  : parseGroupedInt(row.cost.text.trim()),
            ),
        ]);
      }
      // س-123/س-124: ملفات الصورة بعد نجاح الصف — الاستبدال يحذف
      // الملفين القديمين ويحفظ الجديدين (لا ملفات يتيمة)، والحذف
      // يمسح الحقل والملفين معاً.
      if (_isEdit && _deleteImage && _hasExistingImage) {
        await widget.db.clearItemImages(savedItemId);
        await deleteItemImagesFiles(
            _existingImagePaths.$1, _existingImagePaths.$2);
      } else if (_pendingOriginal != null && _pendingThumb != null) {
        if (_hasExistingImage) {
          await deleteItemImagesFiles(
              _existingImagePaths.$1, _existingImagePaths.$2);
        }
        await _writeImagesFor(savedItemId);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// س-40: التعطيل والتفعيل — وزر الحذف غير موجود أصلاً في البطاقة.
  Future<void> _toggleActive() async {
    final item = widget.existing;
    if (item == null || _saving) return;
    await widget.db.setItemActive(item.id, active: !item.isActive);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// س-41: إضافة وحدة قياس جديدة من البطاقة — تختار فوراً بعد الحفظ.
  ///
  /// فحوص mounted المزدوجة قبل كل استخدام للسياق بعد انتظار (نمط lint
  /// الصارم): شاشة الحوار بحمّاله وحالة الشاشة بحمّالها — وانتقال واحد
  /// من أيٍّ منهما بعد await يرفع «استخدام سياق بعد انتظار».
  Future<void> _addUnit() async {
    final controller = TextEditingController();
    Unit? created;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('وحدة قياس أساسية جديدة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم الوحدة *',
              helperText: 'اختر أدق تجزئة تقيس بها (غرام لا كيلو)؛ '
                  'والمطابق حرفياً لوحدة قائمة مرفوض',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                final rows =
                    await widget.db.select(widget.db.units).get();
                if (!mounted || !dialogContext.mounted) return;
                final errors = validateUnitName(
                  controller.text,
                  existing: UnitUniquenessIndex.build(rows
                      .map((u) => ExistingUnit(
                            id: u.id,
                            name: u.name,
                            isActive: true,
                          ))),
                );
                if (errors.isNotEmpty) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(itemErrorText(errors.first)),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  return;
                }
                final id = await widget.db
                    .insertUnit(name: controller.text);
                if (!mounted) return;
                final saved =
                    await (widget.db.select(widget.db.units)
                          ..where((t) => t.id.equals(id)))
                        .getSingle();
                created = saved;
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('إضافة'),
            ),
          ],
        );
      },
    );
    if (created != null) {
      await _loadUnits();
      if (!mounted) return;
      setState(() => _unitId = created!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.existing;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'بطاقة صنف' : 'بطاقة صنف جديدة'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16,
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16),
        children: [
          TextFormField(
            controller: _sku,
            // س-155/D-153 (دفعة 17): الخانة مفتوحة في التعديل أيضاً بلفظ
            // المالك (س50/1 «تمام») — والمدقق أعلاه يرفض المكرر حرفياً.
            decoration: InputDecoration(
              labelText: 'كود الصنف (الأساس)',
              helperText: _isEdit
                  ? 'الكود قابل للتعديل — والفواتير مربوطة بمعرفه الخفي لا بالكود'
                  : 'إلزامي — اكتب كودك كما تعرف صنفك',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'الاسم *',
              helperText: 'الاسم إلزامي وحده — والمطابق حرفياً '
                  'لصنف قائم مرفوض',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'التصنيف (اختياري)',
              helperText: 'أساس الرفع الجماعي للأسعار لاحقاً',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<ItemKind>(
            segments: [
              for (final kind in const [
                ItemKind.good,
                ItemKind.service,
                ItemKind.bundle,
              ])
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {_kind},
            onSelectionChanged: _saving
                ? null
                : (selection) =>
                    setState(() => _kind = selection.first),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _unitId,
                  decoration: InputDecoration(
                    labelText: 'الوحدة الأساسية *',
                    helperText: _units.isEmpty
                        ? 'لا وحدات بعد — أضف وحدة قياس أولاً'
                        : 'تُخزن بها كل الكميات أعداداً صحيحة حصراً',
                  ),
                  hint: const Text('اختر الوحدة'),
                  items: [
                    for (final unit in _units)
                      DropdownMenuItem<int>(
                        value: unit.id,
                        child: Text(unit.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _unitId = value),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: IconButton.filledTonal(
                  tooltip: 'إضافة وحدة قياس',
                  onPressed: _addUnit,
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _purchase,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorInputFormatter()],
            onChanged: (_) {
              _syncDerivedControllers(); // اشتقاق المستويات آلياً (D-187)
              setState(() {}); // المعاينة اللحظية (D-102)
            },
            decoration: InputDecoration(
              labelText: 'سعر الشراء',
              helperText: 'عدد صحيح بالوحدة الصغرى للعملة — '
                  'اتركه فارغاً إن لم تحدد سعراً بعد',
              // D-102: معاينة مفصولة أسفل الحقل — الإدخال يبقى رقماً
              // والفواصل طبقة عرض حتى أثناء الكتابة.
              helperStyle: Theme.of(context).textTheme.bodySmall,
              suffixText: parseGroupedInt(_purchase.text) > 0
                  ? 'تعادل ${formatMinorAmount(parseGroupedInt(_purchase.text))}'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sale,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorInputFormatter()],
            onChanged: (_) {
              _syncDerivedControllers(); // اشتقاق المستويات آلياً (D-187)
              setState(() {}); // المعاينة اللحظية (D-102)
            },
            decoration: InputDecoration(
              labelText: 'سعر البيع',
              helperText: 'الافتراضي في بنود الفواتير — قابل للتعديل '
                  'في كل بند',
              suffixText: parseGroupedInt(_sale.text) > 0
                  ? 'تعادل ${formatMinorAmount(parseGroupedInt(_sale.text))}'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          // ── الحد الأدنى المحدد — د6 (س175) المتابعات اليومية
          //    (س74/D-184 بلفظ المالك): يظهر باللوحة إذا نزل المتاح
          //    عبر المستودعات دون هذا الحد — والسلع حصراً.
          TextFormField(
            controller: _minQty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'الحد الأدنى (اختياري)',
              helperText: 'على السلع حصراً — يظهر ببند المتابعات اليومية '
                  'إذا نزل المتاح دون الحد',
            ),
          ),
          const SizedBox(height: 16),
          // ── مجموعة التعبئة وأسعارها آلي (F-032/F-208، D-026/D-187) ──
          DropdownButtonFormField<int?>(
            initialValue: _unitGroupId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'مجموعة التعبئة (اختياري)',
              helperText: 'وحدات التعبئة أعلى الأساسية بعوامل ثابتة '
                  '— تُدار من زر «مجموعات التعبئة» بشاشة '
                  'الأصناف',
            ),
            items: [
              const DropdownMenuItem<int?>(
                  value: null, child: Text('بلا مجموعة تعبئة')),
              for (final g in _groups)
                DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
            ],
            onChanged: _saving ? null : _switchGroup,
          ),
          if (_levels.isNotEmpty) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('آلي'),
              subtitle: Text(_priceAuto
                  ? 'الوحدة الصغرى للكتابة والمستويات للقراءة تُشتق '
                      'بالأساس × العامل'
                  : 'كل خانات الأسعار للكتابة — خانة مستقلة لكل مستوى'),
              value: _priceAuto,
              onChanged: _saving ? null : _togglePriceAuto,
            ),
            for (final level in _levels)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        '${level.name} ×${level.factor}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _levelPriceCtrls[level.id]!.$1,
                        enabled: !_priceAuto && !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          ThousandsSeparatorInputFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'بيع',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _levelPriceCtrls[level.id]!.$2,
                        enabled: !_priceAuto && !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          ThousandsSeparatorInputFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'شراء',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            enabled: false,
            initialValue: 'ليرة سورية (الأساسية)',
            decoration: const InputDecoration(
              labelText: 'عملة السعر',
              helperText: 'معبأة بالافتراضية ولا تُحفظ فارغة '
                  '— التغيير يُفتح مع دفعة العملات',
            ),
          ),
          // ── وصفة المكونات (F-034/F-212، الدفعة 28) — التجميعي حصراً ──
          if (_kind == ItemKind.bundle) ...[
            const SizedBox(height: 24),
            Text('وصفة المكونات',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'بيع التجميعي يسحب من رصيده الجاهز أولاً ويكمل النقص بفكك '
              'مكوناته بكمياتها — والمكوّن بضاعة أو خدمة حصراً '
              'لا تجميعي، وخدمة الوصفة تكلفتها اختيارية (فارغة '
              'بند بيعي ضمن السعر وبقيمة تدخل مجموع كلف الوصفة)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _recipeRows.length; i++)
              _recipeRowCard(i),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _saving ? null : _addRecipeRow,
                icon: const Icon(Icons.add),
                label: const Text('إضافة مكوّن'),
              ),
            ),
          ],
          // ── صورة الصنف (س-123/س-124، D-120/D-121/D-122/D-125) ──
          const SizedBox(height: 24),
          Text('صورة الصنف', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'التقاط أو اختيار يمرّ المحرك الإلزامي تلقائياً: إطار مربع '
            '(الصورة كاملة افتراضياً) ثم تصغير وضغط خفيف، ومشتق مصغر '
            'لسطور الفواتير — ولا خيار يسكته',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _imageBusy
                  ? const SizedBox(
                      width: 72,
                      height: 72,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ItemImageBox(
                      imagePath: _deleteImage
                          ? null
                          : widget.existing?.imageFile,
                      pendingBytes: _pendingOriginal,
                      itemName: _currentItemName,
                      size: 72,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (supportsCameraScan)
                      OutlinedButton.icon(
                        onPressed: _imageBusy || _saving
                            ? null
                            : () => _pickImage(fromCamera: true),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('التقاط'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _imageBusy || _saving
                          ? null
                          : () => _pickImage(fromCamera: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('من المعرض'),
                    ),
                    if (_pendingOriginal != null || _hasExistingImage)
                      OutlinedButton.icon(
                        onPressed:
                            _imageBusy || _saving ? null : _requestImageDelete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('حذف الصورة'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // ── الباركود (س-131/س-132، D-126 — جدول جاهز من اليوم الأول
          // F-035) ──
          const SizedBox(height: 24),
          Text('الباركود', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'أكثر من رمز للصنف ممكن — والتفرد مضمون. قارئ البلوتوث '
            'يكتب في الخانة مباشرة، والمسح بكاميرا الجوال بزره',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _barcodeController,
            decoration: InputDecoration(
              labelText: 'رمز الباركود',
              hintText: 'اكتب الرمز أو امسحه ثم أضف',
              // س206 (م11 — طابور توحيد المكونات الموثق بس198): كان
              // الحقل على الإطار المحدد بينما العائلة الممتلئة الافتراضية
              // — فنُزع الإطار والعنوان الدائم والإرشاد الثانوي باقيان.
              suffixIcon: supportsCameraScan
                  ? IconButton(
                      tooltip: 'مسح بالكاميرا',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed:
                          _saving ? null : () async {
                            final scan = widget.onScanBarcode ?? scanBarcode;
                            final code = await scan();
                            if (code == null || !mounted) return;
                            _barcodeController.text = code;
                            await _addBarcode();
                          },
                    )
                  : null,
            ),
            onSubmitted: (_) => _addBarcode(),
          ),
          const SizedBox(height: 8),
          if (_isEdit)
            if (_barcodes.isEmpty)
              const Text('لا رموز بعد لهذا الصنف')
            else
              ...[
                for (final b in _barcodes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(b.barcode),
                    trailing: IconButton(
                      tooltip: 'حذف الرمز',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _saving ? null : () => _deleteBarcode(b),
                    ),
                  ),
              ]
          else
            if (_pendingBarcodes.isEmpty)
              const Text('لا رموز بعد — تُحفظ مع الصنف أول مرة')
            else
              ...[
                for (final code in _pendingBarcodes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(code),
                    trailing: IconButton(
                      tooltip: 'إزالة الرمز',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _pendingBarcodes.remove(code)),
                    ),
                  ),
              ],
          if (_isEdit) ...[
            const SizedBox(height: 24),
            // س-40: زر تعطيل/تفعيل — وزر الحذف غير موجود أصلاً في البطاقة
            OutlinedButton.icon(
              onPressed: _saving ? null : _toggleActive,
              icon: Icon(
                item!.isActive ? Icons.block : Icons.check_circle_outline,
              ),
              label: Text(
                item.isActive ? 'تعطيل الصنف' : 'إعادة تفعيل الصنف',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// صياغة رسائل الرفض المعروضة — نطق س-36 حرفاً في كود مكرر، وD-074 في
/// الاسم المطابق، والبقية بصيغها المعتمدة في السيناريوهات.
String itemErrorText(ItemValidationError error) {
  return switch (error) {
    ItemNameRequired() => 'الاسم إلزامي وحده — أدخل الاسم ثم احفظ',
    ItemSkuRequired() =>
      'الكود إلزامي — اكتب كود الصنف ثم احفظ',
    ItemSkuTaken(:final duplicateSku, :final existingLabel) =>
      'الكود $duplicateSku مستخدم للصنف: $existingLabel',
    ItemNameTaken(:final existingLabel) =>
      'الاسم مطابق حرفياً لصنف قائم: $existingLabel — اختر اسماً آخر',
    ItemUnitMissing() =>
      'الوحدة الأساسية إلزامية — اختر من القائمة أو أضف وحدة',
    ItemCurrencyMissing() =>
      'عملة السعر لا تُحفظ فارغة — أعد اختيار العملة',
    ItemPriceInvalid() =>
      'السعر عدد موجب إن أُدخل — والفراغ يعني بلا سعر بعد',
    ItemNameControlChars() =>
      'الاسم يحمل محارف تحكم غير مرئية — أعد كتابته بلا لصق خارجي',
    ItemSkuInvalidFormat(:final sku) =>
      'الكود $sku يقبل الحروف والأرقام و - _ . حصراً — بلا مسافات ولا '
          'رموز أخرى',
    UnitNameRequired() => 'اسم الوحدة إلزامي',
    UnitNameTaken(:final existingName) =>
      'الاسم مطابق حرفياً لوحدة قائمة: $existingName — اختر اسماً آخر'
          '',
  };
}
