import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'input_formatters.dart';
import 'item_images.dart';
import 'price_update_screen.dart';
import 'item_media.dart';
import 'item_crop_screen.dart';
import 'reports_screen.dart' show formatMinorAmount;

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
      _kind = ItemKind.fromStorage(item.kind);
      _unitId = item.baseUnitId;
    } else {
      _kind = ItemKind.good;
    }
    _loadUnits();
    if (_isEdit) {
      _loadBarcodes();
    }
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
    _barcodeController.dispose();
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
      if (!mounted) return;
      setState(() => _imageBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      if (!mounted) return;
      setState(() => _imageBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('تعذر تجهيز الصورة — $e')),
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
        );
        // س-131: رموز الصنف الجديد تُدرج بعد نجاح الإدراج حصراً.
        for (final code in _pendingBarcodes) {
          await widget.db
              .insertItemBarcode(itemId: savedItemId, barcode: code);
        }
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
            // س-155/D-153 (دفعة 17): الخانة مفتوحة في التعديل أيضاً بلفظ
            // المالك (س50/1 «تمام») — والمدقق أعلاه يرفض المكرر حرفياً.
            decoration: InputDecoration(
              labelText: 'كود الصنف (الأساس)',
              helperText: _isEdit
                  ? 'الكود قابل للتعديل — والفواتير مربوطة بمعرفه الخفي لا بالكود'
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
            inputFormatters: [ThousandsSeparatorInputFormatter()],
            onChanged: (_) => setState(() {}), // المعاينة اللحظية (D-102)
            decoration: InputDecoration(
              labelText: 'سعر الشراء',
              helperText: 'عدد صحيح بالوحدة الصغرى للعملة (س7) — '
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
            onChanged: (_) => setState(() {}), // المعاينة اللحظية (D-102)
            decoration: InputDecoration(
              labelText: 'سعر البيع',
              helperText: 'الافتراضي في بنود الفواتير (س-108) — قابل للتعديل '
                  'في كل بند (س-08)',
              suffixText: parseGroupedInt(_sale.text) > 0
                  ? 'تعادل ${formatMinorAmount(parseGroupedInt(_sale.text))}'
                  : null,
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
          // ── صورة الصنف (س-123/س-124، D-120/D-121/D-122/D-125) ──
          const SizedBox(height: 24),
          Text('صورة الصنف', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'التقاط أو اختيار يمرّ المحرك الإلزامي تلقائياً: إطار مربع '
            '(الصورة كاملة افتراضياً) ثم تصغير وضغط خفيف، ومشتق مصغر '
            'لسطور الفواتير — ولا خيار يسكته (D-120)',
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
            'أكثر من رمز للصنف ممكن — والتفرد مضمون (س-131). قارئ البلوتوث '
            'يكتب في الخانة مباشرة، والمسح بكاميرا الجوال بزره (س-132)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _barcodeController,
            decoration: InputDecoration(
              labelText: 'رمز الباركود',
              hintText: 'اكتب الرمز أو امسحه ثم أضف',
              border: const OutlineInputBorder(),
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
    ItemNameControlChars() =>
      'الاسم يحمل محارف تحكم غير مرئية — أعد كتابته بلا لصق خارجي (D-170)',
    ItemSkuInvalidFormat(:final sku) =>
      'الكود $sku يقبل الحروف والأرقام و - _ . حصراً — بلا مسافات ولا '
          'رموز أخرى (D-171)',
    UnitNameRequired() => 'اسم الوحدة إلزامي (F-031)',
    UnitNameTaken(:final existingName) =>
      'الاسم مطابق حرفياً لوحدة قائمة: $existingName — اختر اسماً آخر '
          '(D-074)',
  };
}
