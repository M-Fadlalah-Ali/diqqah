import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// شاشة الأصناف (F-030/F-031 — دفعة م1 الثانية، س-36..س-41).
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
      appBar: AppBar(title: const Text('الأصناف')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewItem,
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('إضافة صنف'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث بالاسم أو الكود أو التصنيف',
                border: OutlineInputBorder(),
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
                    return ListTile(
                      leading: Icon(
                        item.isActive
                            ? Icons.inventory_2_outlined
                            : Icons.inventory_2,
                      ),
                      title: Text(itemDisplayLabel(item.name, item.sku)),
                      subtitle: Text(
                        kind.label + (category == null ? '' : ' · $category'),
                      ),
                      trailing: item.isActive
                          ? null
                          : const Chip(
                              label: Text('معطّل'),
                              visualDensity: VisualDensity.compact,
                            ),
                      onTap: () => _openItem(item),
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

  const ItemEditScreen({super.key, required this.db, this.existing});

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _purchase = TextEditingController();
  final _sale = TextEditingController();
  late ItemKind _kind;
  int? _unitId;
  List<Unit> _units = const [];

  /// العملة الأساسية حصراً حتى تُبنى جدول العملات (D-017/D-066 الاصطلاح).
  static const int _baseCurrencyId = 1;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    if (item != null) {
      _sku.text = item.sku;
      _name.text = item.name;
      _category.text = item.category ?? '';
      _purchase.text = item.purchasePriceMinor.toString();
      _sale.text = item.salePriceMinor.toString();
      _kind = ItemKind.fromStorage(item.kind);
      _unitId = item.baseUnitId;
    } else {
      _kind = ItemKind.good;
    }
    _loadUnits();
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _category.dispose();
    _purchase.dispose();
    _sale.dispose();
    super.dispose();
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

  /// قراءة سعر: الفراغ صفر مشروع «بلا سعر بعد» (س-36)، وإدخال شاذ
  /// (فائض طول مثلاً رغم قيد الأرقام) يعود -1 فيلتقطه مدقق المجال (س6).
  int _parsePrice(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? -1;
  }

  ExistingItem _asExisting(Item item) => ExistingItem(
        id: item.id,
        sku: item.sku,
        name: item.name,
        isActive: item.isActive,
      );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
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
      if (_isEdit) {
        await widget.db.updateItemDetails(
          widget.existing!,
          name: draft.name.trim(),
          category: draft.category.trim(),
          kind: _kind.storageValue,
          baseUnitId: draft.baseUnitId,
          purchasePriceMinor: draft.purchasePriceMinor,
          salePriceMinor: draft.salePriceMinor,
          priceCurrencyId: _baseCurrencyId,
        );
      } else {
        await widget.db.insertItem(
          sku: draft.sku.trim(),
          name: draft.name.trim(),
          category: draft.category.trim(),
          kind: _kind.storageValue,
          baseUnitId: draft.baseUnitId,
          purchasePriceMinor: draft.purchasePriceMinor,
          salePriceMinor: draft.salePriceMinor,
          priceCurrencyId: _baseCurrencyId,
        );
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
              helperText: 'اختر أدق تجزئة تقيس بها (غرام لا كيلو — F-031)؛ '
                  'والمطابق حرفياً لوحدة قائمة مرفوض (D-074)',
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
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _sku,
            enabled: !_isEdit,
            decoration: InputDecoration(
              labelText: 'كود الصنف (الأساس)',
              helperText: _isEdit
                  ? 'الكود لا يُعدَّل بعد الحفظ — الفواتير ترتبط بمعرّفه '
                      'الثابت (D-073)'
                  : 'إلزامي — اكتب كودك كما تعرف صنفك (D-073)',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'الاسم *',
              helperText: 'الاسم إلزامي وحده (س-36) — والمطابق حرفياً '
                  'لصنف قائم مرفوض (D-074)',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'التصنيف (اختياري)',
              helperText: 'أساس الرفع الجماعي للأسعار لاحقاً (F-165)',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<ItemKind>(
            segments: [
              for (final kind in const [ItemKind.good, ItemKind.service])
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
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
                        ? 'لا وحدات بعد — أضف وحدة قياس أولاً (F-031)'
                        : 'تُخزن بها كل الكميات أعداداً صحيحة حصراً (F-031)',
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'سعر الشراء',
              helperText: 'عدد صحيح بالوحدة الصغرى للعملة (س7) — '
                  'اتركه فارغاً إن لم تحدد سعراً بعد',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sale,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'سعر البيع',
              helperText: 'الافتراضي في بنود الفواتير — قابل للتعديل '
                  'في كل بند (س-08)',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            enabled: false,
            initialValue: 'ليرة سورية (الأساسية)',
            decoration: const InputDecoration(
              labelText: 'عملة السعر',
              helperText: 'معبأة بالافتراضية ولا تُحفظ فارغة '
                  '(D-066 الاصطلاح) — التغيير يُفتح مع دفعة العملات',
            ),
          ),
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
    ItemNameRequired() => 'الاسم إلزامي وحده — أدخل الاسم ثم احفظ (س-36)',
    ItemSkuRequired() =>
      'الكود إلزامي — اكتب كود الصنف ثم احفظ (F-030/D-073)',
    ItemSkuTaken(:final duplicateSku, :final existingLabel) =>
      'الكود $duplicateSku مستخدم للصنف: $existingLabel',
    ItemNameTaken(:final existingLabel) =>
      'الاسم مطابق حرفياً لصنف قائم: $existingLabel — اختر اسماً آخر '
          '(D-074)',
    ItemUnitMissing() =>
      'الوحدة الأساسية إلزامية — اختر من القائمة أو أضف وحدة (F-031)',
    ItemCurrencyMissing() =>
      'عملة السعر لا تُحفظ فارغة — أعد اختيار العملة (D-066)',
    ItemPriceInvalid() =>
      'السعر عدد موجب إن أُدخل — والفراغ يعني بلا سعر بعد (س6)',
    UnitNameRequired() => 'اسم الوحدة إلزامي (F-031)',
    UnitNameTaken(:final existingName) =>
      'الاسم مطابق حرفياً لوحدة قائمة: $existingName — اختر اسماً آخر '
          '(D-074)',
  };
}
