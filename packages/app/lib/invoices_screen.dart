import 'dart:io' show File;

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
import 'drilldown.dart' show showItemSheet;
import 'tafqit.dart';
import 'delivery_summary.dart';
import 'currency_display.dart';

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

/// لون كل نوع بالأزرار المعزولة ولافتة النموذج — عرف المعاينة المعتمدة
/// (س-163/D-161): بيع أخضر وشراء برتقالي ومردود بيع أزرق ومردود شراء وردي.
/// (النوع MaterialColor لا Color خلافاً — الدرجات shade50/300/700 على
/// عائلة المادة حصراً — درس CI جولة 160)
MaterialColor invoiceKindColor(InvoiceKind kind) => switch (kind) {
      InvoiceKind.sale => Colors.green,
      InvoiceKind.purchase => Colors.orange,
      InvoiceKind.saleReturn => Colors.indigo,
      InvoiceKind.purchaseReturn => Colors.pink,
    };

/// أيقونة كل نوع — البيع ورقته والشراء عربة والمردودان سهم الرجوع بجهتيهما.
IconData invoiceKindIcon(InvoiceKind kind) => switch (kind) {
      InvoiceKind.sale => Icons.receipt_outlined,
      InvoiceKind.purchase => Icons.shopping_cart_outlined,
      InvoiceKind.saleReturn => Icons.redo_outlined,
      InvoiceKind.purchaseReturn => Icons.undo_outlined,
    };

/// لسان حالة سطر الاستلام بتفاصيل الفاتورة (الدفعة 21/F-168 — تعميم
/// مربع «مستلم» D-131 على كل الأنواع بكلمة المالك): لسان البيع المعتمد
/// باقٍ حرفاً والأنواع الأخرى بلسان الاستلام لا التسليم.
String receiptLineStatusFor(InvoiceKind kind, bool delivered) => delivered
    ? 'مستلم'
    : kind == InvoiceKind.sale
        ? 'بانتظار التسليم'
        : 'بانتظار الاستلام';

/// بناء قسيمة الفاتورة — نقطة واحدة لكل مسارات إخراج الفاتورة (س-133/
/// D-127، دفعة 11): زر التفاصيل النصي وزر القائمة السريع والمشاركة كلها
/// تستدعيها فلا يختلف مطبوع عن مطبوع. البيانات تُجلب هنا حصراً من
/// القاعدة، والصور بمفتاحها المفعّل (D-123)، وعمود «مستلم» بسطر
/// خلاصته «مستلم X من Y» — كان بقسيمة البيع حصراً (س-140/D-134 دفعة
/// 12) فعّم لكل الأنواع بالدفعة 21 (F-168) مع تعميم العلم بكلمة
/// المالك —
/// عِلماً توضيحياً للزبون لا يمس أرقام الفاتورة بحال. لسان العمود
/// كلمات لا رموز: خط الطباعة المدمج لا يحمل رسمة الصحّ ✓ فما كان
/// ليعرضها — و«سُلِّم» أوضح للزبون من رمز أصلاً.
Future<Uint8List> buildInvoicePrintoutBytes(
  DiqqahDatabase db,
  int invoiceId,
) async {
  final invoice = await db.invoiceById(invoiceId);
  if (invoice == null) {
    throw StateError('لا فاتورة بهذا المعرف');
  }
  final lines = await db.invoiceLines(invoiceId);
  final items = await db.select(db.items).get();
  final itemById = {for (final item in items) item.id: item};
  // س-148/D-138 (دفعة 14): أسماء الوحدات — الخلاصة «بالواحدة».
  final units = await db.select(db.units).get();
  final unitNameById = {for (final u in units) u.id: u.name};
  final kind = InvoiceKind.fromStorage(invoice.kind);
  final isSale = kind == InvoiceKind.sale;

  // س-153/D-151 (دفعة 15): عمود «ملاحظة» بقسيمة البيع حصراً حين
  // وُجدت ملاحظة على أسطر غير مستلمة — فلا عمود فارغ يعمّم الضجيج.
  final hasDeliveryNotes = isSale &&
      lines.any((l) =>
          l.deliveryNote != null && l.deliveryNote!.trim().isNotEmpty);

  // الصور بمفتاحها المستقل (س-127/D-123) — الافتراضي معطل فلا قراءة ملفات.
  List<Uint8List?>? rowImages;
  List<String>? rowLetters;
  if (printImagesForKind(kind)) {
    rowImages = [
      for (final line in lines)
        await loadItemImageBytes(itemById[line.itemId]?.imageFile),
    ];
    rowLetters = [
      for (final line in lines)
        itemById[line.itemId]?.name ?? 'صنف #${line.itemId}',
    ];
  }

  // س-140/D-134: عمود «مستلم» — «سُلِّم» للمحدد بفواتير البيع
  // ولسان الاستلام للأنواع الأخرى (تعميم الدفعة 21/F-168)، وسطر
  // الخلاصة تحت الجدول بكل الأنواع.
  // س-153/D-151 (دفعة 15): وعمود «ملاحظة» بقسيمة البيع حصراً حين
  // وُجدت ملاحظة تسليم على أسطرها — فلا عمود فارغ يعمّم الضجيج.
  final columns = <String>[
    'الصنف',
    'الكمية',
    'سعر الوحدة',
    // س50/5 (س-161/D-159 دفعة 17): «المبلغ» — عرف البرمجيات
    // الشهيرة لعمود مبلغ السطر، و«الإجمالي» باق للتذييل كله.
    'المبلغ',
    // الدفعة 21 (F-168): «مستلم» بكل الأنواع بعد تعميم العلم.
    'مستلم',
    if (hasDeliveryNotes) 'ملاحظة',
  ];
  final rows = [
    for (final line in lines)
      [
        itemById[line.itemId]?.name ?? 'صنف #${line.itemId}',
        '${line.qtyBase}',
        formatMinorAmount(line.unitPriceMinor),
        formatMinorAmount(line.lineTotalDocMinor),
        line.delivered
            ? (isSale ? 'سُلِّم' : 'مستلم')
            : (isSale ? 'بانتظار التسليم' : 'بانتظار الاستلام'),
        if (hasDeliveryNotes) line.deliveryNote ?? '—',
      ],
  ];
  String? summary;
  // الدفعة 21 (F-168): سطر خلاصة «مستلم X من Y» بكل الأنواع بعد
  // تعميم العلم — كان بقسيمة البيع حصراً (س-140/D-134).
  if (lines.isNotEmpty) {
    // س-148/D-138: الافتراضي «مجموع الكميات بالواحدة» بقاعدة الوحدة
    // الموثقة — والقسيمة المطبوعة على الافتراضي دائماً (القائمة
    // المنسدلة عرضُ شاشة لا سياسة مطبوع).
    final totalQty = quantitiesByUnit(
        [for (final l in lines) (l.qtyBase, unitNameById[l.unitId] ?? '')]);
    final deliveredQty = quantitiesByUnit([
      for (final l in lines)
        if (l.delivered) (l.qtyBase, unitNameById[l.unitId] ?? ''),
    ]);
    summary = invoiceDeliverySummary(
      deliveredLines: lines.where((l) => l.delivered).length,
      totalLines: lines.length,
      deliveredQtyByUnit: deliveredQty,
      totalQtyByUnit: totalQty,
      basis: DeliveryBasis.quantities,
    );
  }

  // س-149/D-139: عملة المستند من جدولها — التفقيط باسمها وصيغها.
  final currencies = await db.currenciesOf();
  Map<String, dynamic>? currencyFields;
  String baseCode = 'SYP';
  for (final c in currencies) {
    if (c.id == invoice.currencyId) {
      currencyFields = {
        'code': c.code,
        'name': c.name,
        'minorUnits': c.minorUnits,
      };
    }
    if (c.id == 1) baseCode = c.code;
  }
  // س-158/D-156 (دفعة 17): الرمز مكان اللفظ (س50/6 بلفظ المالك:
  // «بالأساسية تُستبدل برمز العملة — ل.س تُكتب مباشرة أو $») — الرمز
  // من جدول العملات لا لفظ ثابت، والغريب الكود يبقى كوده حرفاً.
  final docSymbol = currencySymbol(currencyFields?['code'] as String?);
  final docSuffix = docSymbol.isEmpty ? 'بعملة المستند' : docSymbol;
  final baseSymbol = currencySymbol(baseCode);
  // س-156/D-154 (دفعة 17): المدفوع من محرك المطابقة ذاته — فواتير
  // السندات المرحّلة بوحدات المستند (س50/4 بلفظ المالك:
  // «في الخاتمة تكتب الدفعة والباقي»).
  final covered = await db.invoiceCoveredDocMinor(invoiceId);

  return buildDocumentPdf(
    title: invoiceDisplayLabel(invoice),
    headerPairs: [
      ('التاريخ', invoice.invoiceDate),
      // س-156/D-154: لسان المالك — «نحن صنفنا الفواتير نقدية وذمة
      // فلتكتب كذلك» (س50/4): السداد بالتصنيف المعتمد عند الإدخال
      // (النقدي بصندوقه والآجل بطرفه — لا صندوق ولا طرف مرفوضان
      // بالمحرك)، والمسودة تُنادى بمسودتها كي لا تُباع ورقة غير
      // مرحّلة بلا إنذار.
      ('السداد', invoice.cashBoxId != null ? 'نقدية' : 'ذمة'),
      if (invoice.state == 'draft') ('الحالة', 'مسودة'),
      if (invoice.narration != null && invoice.narration!.isNotEmpty)
        ('البيان', invoice.narration!),
    ],
    columns: columns,
    rows: rows,
    rowLeadingImages: rowImages,
    rowPlaceholderLetters: rowLetters,
    summaryText: summary,
    footerPairs: [
      (
        'الإجمالي',
        '${formatMinorAmount(invoice.totalDocMinor)} $docSuffix',
      ),
      // س-159/D-157 (دفعة 17): المكافئ بغير عملة الأساس حصراً — بعملة
      // الأساس كان يكرر سطر الإجمالي بلا فائدة (س50/7 «لا بأس»)،
      // وتسميته برمز الأساس لا بلفظ «المكافئ الأساسي».
      if (invoice.currencyId != 1)
        (
          'المكافئ ب$baseSymbol',
          formatMinorAmount(invoice.totalBaseMinor),
        ),
      // س-156/D-154: المدفوع والباقي بقراءة المحرك — وبرمز العملة.
      (
        'المدفوع',
        '${formatMinorAmount(covered)} $docSuffix',
      ),
      (
        'الباقي',
        '${formatMinorAmount(invoice.totalDocMinor - covered)} $docSuffix',
      ),
    ],
    // س-160/D-158 (دفعة 17): التفقيط سطراً مستقلاً بلا تسمية — عرف
    // الشيكات وفواتير البرمجيات العربية (س50/8 «تمام»): «فقط ...
    // لا غير» يقف وحده لا يسبقه لفظ يضاعف الكلام. وسقوط العملة من
    // الجدول يسقط السطر سكوتاً لا بلفظ مفبرك (عهد س-149 باقٍ).
    standoutLine: currencyFields == null
        ? null
        : tafqitAmountWords(
            totalMinor: invoice.totalDocMinor,
            currency: tafqitCurrencyFor(
              code: currencyFields['code'] as String,
              name: currencyFields['name'] as String,
              minorUnits: currencyFields['minorUnits'] as int,
            ),
          ),
    format: resolvePageFormat(docKind: 'invoice'),
  );
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

  /// الدفعة 21 (F-168): قيمة فلتر الاستلام — null الكل وإلا
  /// 'undelivered' أو 'partial' أو 'received'.
  String? _receipt;

  /// الدفعة 21 (F-168): الصفوف المعروضة حالياً — بطاقة أزرار الطباعة
  /// والتصدير في الشريط العلوي تقرؤها، فالمطبوع والمصدّر صورة العرض
  /// ذاتها (عرف F-166).
  List<InvoiceListRow>? _listRows;

  Future<List<InvoiceListRow>>? _rows;

  static final List<(String?, String)> _kindChoices = [
    (null, 'كل الأنواع'),
    (InvoiceKind.purchase.storageValue, InvoiceKind.purchase.label),
    (InvoiceKind.sale.storageValue, InvoiceKind.sale.label),
    (InvoiceKind.saleReturn.storageValue, InvoiceKind.saleReturn.label),
    (InvoiceKind.purchaseReturn.storageValue, InvoiceKind.purchaseReturn.label),
  ];

  /// الدفعة 21 (F-168): خيارات فلتر الاستلام — ثلاث حالات لا اثنتان
  /// لأن الثنائية تخفي الجزئي (فاتورة سُلّم نصفها تظهر «غير مستلم»
  /// كذباً).
  static final List<(String?, String)> _receiptChoices = [
    (null, 'الكل'),
    ('undelivered', 'غير مستلم'),
    ('partial', 'جزئي'),
    ('received', 'مكتمل الاستلام'),
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
        // الدفعة 21 (F-168): فلتر الاستلام يمرّ للقاعدة مع البقية.
        receiptFilter: _receipt,
      );
    });
  }

  void _openNew() async {
    // عزل الإدخال من الأرشيف أيضاً (س-163/D-161): أربعة أزرار تُحدد النوع
    // بالضغط لا قائمة منسدلة — نمط القائمة الرئيسية ذاته، واختيار النوع
    // هنا يفتح النموذج بنوعه المثبت.
    final kind = await showModalBottomSheet<InvoiceKind>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('فاتورة جديدة — اختر النوع بالضغط',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: [
                _sheetKindButton(sheetContext, InvoiceKind.sale),
                const SizedBox(width: 10),
                _sheetKindButton(sheetContext, InvoiceKind.purchase),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _sheetKindButton(sheetContext, InvoiceKind.saleReturn),
                const SizedBox(width: 10),
                _sheetKindButton(sheetContext, InvoiceKind.purchaseReturn),
              ]),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => InvoiceEditScreen(db: widget.db, initialKind: kind)),
    );
    if (created == true) _reload();
  }

  /// زر نوع بقائمة الأرشيف السفلية — بلون نوعه وأيقونته عرف الرئيسية.
  Widget _sheetKindButton(BuildContext sheetContext, InvoiceKind kind) {
    final color = invoiceKindColor(kind);
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: color.shade50,
          side: BorderSide(color: color.shade300),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => Navigator.of(sheetContext).pop(kind),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(invoiceKindIcon(kind), color: color.shade700),
            const SizedBox(height: 6),
            Text(kind.label,
                style:
                    TextStyle(color: color.shade700, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _openDetail(int invoiceId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceDetailScreen(db: widget.db, invoiceId: invoiceId),
      ),
    );
  }

  /// س-133 (D-127، دفعة 11): الطباعة السريعة من القائمة مباشرة —
  /// كانت الطباعة أيقونتين مدفونتين بأعلى التفاصيل فلم يجدها المالك
  /// بلفظه «طباعة الفاتورة غير متاحة» — فالقسيمة الواحدة الآن بضغطة
  /// من كل صف، والفشل رسالة لا صمت.
  Future<void> _quickPrint(BuildContext context, int invoiceId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildInvoicePrintoutBytes(widget.db, invoiceId);
      if (!context.mounted) return;
      await printPdfBytes(context, bytes);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  /// الدفعة 21 (F-168): أعمدة أرشيف الفواتير وصفوفه تجميعاً واحداً —
  /// المطبوع والمصدّر صورة العرض ذاتها فلا انحراف (عرف F-166 الموثق).
  static const List<String> _archiveColumns = [
    'النوع',
    'الرقم',
    'التاريخ',
    'الطرف / الصندوق',
    'الحالة',
    'الاستلام',
    'المبلغ',
  ];

  static List<List<String>> _archiveRows(List<InvoiceListRow> rows) => [
        for (final row in rows)
          [
            row.kindValue.label,
            row.number.isEmpty ? '—' : row.number,
            row.invoiceDate,
            row.counterpartLabel,
            row.stateLabel,
            row.receiptLabel,
            '${formatMinorAmount(row.totalDocMinor)} ${row.currencyCode}',
          ],
      ];

  /// الدفعة 21 (F-168): طباعة القائمة المعروضة بفلاترها كلها — قسيمة
  /// عرضية بنمط التقارير، والفشل رسالة لا صمت.
  Future<void> _printList() async {
    final rows = _listRows;
    if (rows == null || rows.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildDocumentPdf(
        title: 'سجل الفواتير',
        headerPairs: const [],
        columns: _archiveColumns,
        rows: _archiveRows(rows),
        footerPairs: [
          ('عدد الفواتير', '${rows.length}'),
        ],
        format: resolvePageFormat(docKind: 'report'),
      );
      await sharePdfBytes(bytes, 'سجل الفواتير.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  /// الدفعة 21 (F-168): تصدير القائمة المعروضة CSV — باني المجال النقي
  /// (UTF-8 مع BOM) وملف مؤقت باسم معقّم (D-152)، والفشل رسالة لا صمت.
  Future<void> _exportCsv() async {
    final rows = _listRows;
    if (rows == null || rows.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = buildCsvSnapshot(
        title: 'سجل الفواتير',
        columns: _archiveColumns,
        rows: _archiveRows(rows),
        footer: [('عدد الفواتير', '${rows.length}')],
      );
      await shareCsvBytes(csv, 'سجل الفواتير.csv');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد التصدير — $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الفواتير'),
        actions: [
          // الدفعة 21 (F-168): طباعة القائمة المفلترة وتصديرها CSV —
          // في الشريط العلوي سطراً مستقلاً لا حشواً بصف فلاتر (درس س67)،
          // وتعطيلهما بلا صفوف فلا زر ميت (عرف زر تسليم الكل).
          IconButton(
            tooltip: 'طباعة القائمة',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: (_listRows == null || _listRows!.isEmpty)
                ? null
                : _printList,
          ),
          IconButton(
            tooltip: 'تصدير CSV',
            icon: const Icon(Icons.table_view_outlined),
            onPressed: (_listRows == null || _listRows!.isEmpty)
                ? null
                : _exportCsv,
          ),
        ],
      ),
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
                // الدفعة 21 (F-168): فلتر الاستلام سطراً مستقلاً — درس
                // س67: لا حشر عنصر بصف فيه Expanded فتنضغط القوائم
                // المنسدلة وتنكسر الاختبارات.
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _receipt,
                        decoration: const InputDecoration(
                            labelText: 'الاستلام'),
                        items: [
                          for (final (value, label) in _receiptChoices)
                            DropdownMenuItem<String>(
                                value: value, child: Text(label)),
                        ],
                        onChanged: (value) =>
                            setState(() => _receipt = value),
                      ),
                    ),
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
                // الدفعة 21 (F-168): بطاقة الشريط العلوي تقرأ الصفوف
                // المعروضة ذاتها — والمطبوع والمصدّر صورة العرض.
                _listRows = rows;
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
                            ' · ${row.stateLabel}'
                            // الدفعة 21 (F-168): حالة الاستلام بالصف —
                            // لسان القائمة هو ذاته لسان المطبوع والCSV.
                            ' · ${row.receiptLabel}'),
                        // س-133/D-127: زر الطباعة السريع بجانب المبلغ —
                        // يطبع القسيمة الواحدة بلا فتح التفاصيل.
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'طباعة',
                              icon: const Icon(Icons.print_outlined),
                              onPressed: () => _quickPrint(context, row.id),
                            ),
                            Text(
                                '${formatMinorAmount(row.totalDocMinor)}'
                                ' ${row.currencyCode}'),
                          ],
                        ),
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

  /// عزل الإدخال (س-163/D-161): النوع يُحدد بزر القائمة الرئيسية ولا
  /// مبدّل نوع بالنموذج — والافتراضي شراء عرف النموذج الموحد قبل الأزرار
  /// (فتح برمجي مباشر كالاختبارات والأرشيف يمرره صريحاً).
  final InvoiceKind initialKind;

  const InvoiceEditScreen({
    super.key,
    required this.db,
    this.initialKind = InvoiceKind.purchase,
  });

  @override
  State<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  late InvoiceKind _kind = widget.initialKind;

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
  /// بعد» (الصفر س6) يبقى الحقل فارغاً لا صفراً. وبعد عزل الإدخال
  /// (س-163/D-161) النوع ثابت من زر الدخول فلا إعادة تعبئة عند تبديل
  /// جهة — لا تبديل أصلاً — فأُزيل وسم «المعبأ آلياً» وعيدُه معه.
  void _fillDefaultPrice(_LineUi line) {
    final item = _itemOf(line.itemId);
    if (item == null) return;
    final minor =
        _kind.isSalesSide ? item.salePriceMinor : item.purchasePriceMinor;
    line.price.text = minor > 0 ? groupDigits(minor) : '';
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
                // عزل الإدخال (س-163/D-161): لا مبدّل نوع بالنموذج حصراً —
                // النوع من زر القائمة الرئيسية فلا انزلاق جهة بعد كتابة
                // الأسطر، وعلة س-113 (الطرف القديم بعد تبديل الجهة) زالت
                // بزوال التبديل ذاته، والتعبئة الآلية والترحيل تلتزم نوع
                // الدخول من أول سطر.
                Card(
                  color: invoiceKindColor(_kind).shade50,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(invoiceKindIcon(_kind),
                        color: invoiceKindColor(_kind).shade700),
                    title: Text(_kind.label,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: invoiceKindColor(_kind).shade700)),
                    subtitle: const Text(
                        'النوع يُحدد من زر القائمة الرئيسية'),
                  ),
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
                        ' $kBaseCurrencySymbol',
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

/// تفاصيل فاتورة — دفعة (11) ودفعة (12) معاً:
///
/// س-133 (D-127، دفعة 11): زرا «طباعة / PDF» و«مشاركة PDF» ظاهران بنصهما
/// أعلى التفاصيل — كانت أيقونتين صغيرتين بلا نص فلم يجدهما المالك بلفظه
/// «طباعة الفاتورة غير متاحة»، والقسيمة واحدة للجميع من نقطة واحدة
/// (buildInvoicePrintoutBytes).
///
/// س-137 (D-131، دفعة 12): عمود «مستلم» بسطور الفاتورة — مربع واحد
/// بلفظ المالك «أفضل عمود بعنوان "مستلم" تحته في كل سطر مربع يحدد عند
/// التسليم، وما ليس محدد يكون غير مستلم، أظن هذا يكفي» — التحديد يحفظ
/// بقاعدة البيانات فوراً ويتحدث على المرحّلة بلا فك إقفال (علم عمل لا
/// محاسبة). الدفعة 21 (F-168 بكلمة المالك): عمّم المربع لكل الأنواع
/// — بيعاً وشراءً ومردودات — ليكون فلتر الاستلام بالأرشيف ذا معنى
/// لكل النوع، وخانة المورد المسؤول باقت للبيع حصراً (D-132).
///
/// س-138 (D-132، دفعة 12): المورد المسؤول بكل سطر — اختيار يدوي من
/// الموردين مع اقتراح من آخر فاتورة شراء مرحّلة للصنف، والاختيار يُخزَّن
/// على السطر لا يُخمَّن لحظة العرض.
///
/// زر «تسليم الكل» (قرار المالك «يوجد زر تسليم الكل — لا بأس»، س43):
/// تعليم كل سطور الفاتورة مستلمة بضغطة — تسهيل البيع الذي يُسلَّم
/// دفعة واحدة. وبأمره ذاته بقت خانة «ملاحظة التسليم» خارج الدفعة.
class InvoiceDetailScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final int invoiceId;

  const InvoiceDetailScreen({
    super.key,
    required this.db,
    required this.invoiceId,
  });

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  InvoiceDocument? _invoice;
  List<InvoiceLineDocument> _lines = [];
  Map<int, Item> _itemById = {};

  /// س-148/D-138 (دفعة 14): أساس عدّاد التسليم — الافتراضي الكميات
  /// بالواحدة بقائمة منسدلة في نفس السطر بقرار المالك، وأسماء الوحدات
  /// لتجميعها.
  DeliveryBasis _deliveryBasis = DeliveryBasis.quantities;
  Map<int, String> _unitNames = {};

  /// الموردون النشطون لخانة «المورد المسؤول» (س-138/D-132).
  List<Party> _suppliers = [];

  /// س-156/D-154 (دفعة 17): المدفوع من محرك المطابقة، ورمزا العملتين
  /// (المستند والأساس) من جدولهما — لسان نقدية/ذمة والمدفوع والباقي.
  int _covered = 0;
  String _docSuffix = '';
  String _baseSymbol = kBaseCurrencySymbol;

  /// اقتراح المورد لكل صنف — من آخر شراء مرحّل (قراءة عند التحميل
  /// حصراً؛ من يختار يُخزَّن فلا يعاد الاقتراح فوق اختيار).
  Map<int, int> _supplierSuggestion = {};

  bool _loaded = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// التحميل الأول — كل بيانات الشاشة دفعة واحدة (درس السرد الكسول:
  /// لا Future يُنشأ داخل build).
  Future<void> _load() async {
    try {
      final invoice = await widget.db.invoiceById(widget.invoiceId);
      final lines = invoice == null
          ? const <InvoiceLineDocument>[]
          : await widget.db.invoiceLines(widget.invoiceId);
      final items = await widget.db.select(widget.db.items).get();
      final parties = await widget.db.select(widget.db.parties).get();
      // س-156/D-154: المغطى بالمحرك ورمز العملتين من جدولهما.
      final covered = invoice == null
          ? 0
          : await widget.db.invoiceCoveredDocMinor(widget.invoiceId);
      final currencies = await widget.db.currenciesOf();
      String baseCode = 'SYP';
      String docCode = '';
      for (final c in currencies) {
        if (c.id == 1) baseCode = c.code;
        if (invoice != null && c.id == invoice.currencyId) docCode = c.code;
      }
      final docSymbol = currencySymbol(docCode);
      // س-148/D-138: أسماء الوحدات لتجميع عدّاد التسليم «بالواحدة».
      final units = await widget.db.select(widget.db.units).get();
      final suggestions = <int, int>{};
      for (final line in lines) {
        final s = await widget.db
            .latestSupplierPartyIdForItem(line.itemId);
        if (s != null) suggestions[line.itemId] = s;
      }
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _lines = lines;
        _itemById = {for (final it in items) it.id: it};
        _suppliers = parties
            .where((p) => p.kind == 'supplier' && p.isActive)
            .toList();
        _supplierSuggestion = suggestions;
        _unitNames = {for (final u in units) u.id: u.name};
        _covered = covered;
        _docSuffix = docSymbol.isEmpty ? 'بعملة المستند' : docSymbol;
        _baseSymbol = currencySymbol(baseCode);
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loaded = true;
      });
    }
  }

  /// إعادة قراءة السطور بعد تحديث علم التسليم أو المورد — الشاشة تعرض
  /// ما خُزّن حصراً.
  Future<void> _reloadLines() async {
    final lines = await widget.db.invoiceLines(widget.invoiceId);
    if (!mounted) return;
    setState(() => _lines = lines);
  }

  bool get _isSale =>
      _invoice != null &&
      InvoiceKind.fromStorage(_invoice!.kind) == InvoiceKind.sale;

  bool get _hasUndelivered => _lines.any((l) => !l.delivered);

  /// س-137/D-131: تحديد المربع يحفظ فوراً — لا علم مؤقت يضيع بإغلاق
  /// الشاشة، والرسالة عند الفشل لا صمت.
  Future<void> _toggleDelivered(InvoiceLineDocument line, bool value) async {
    setState(() => _busy = true);
    try {
      await widget.db.setInvoiceLineDelivered(line.id, delivered: value);
      await _reloadLines();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث علم التسليم — $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// زر «تسليم الكل» (س43 «لا بأس»): تعليم كل السطور غير المستلمة
  /// بضغطة واحدة.
  Future<void> _deliverAll() async {
    setState(() => _busy = true);
    try {
      for (final line in _lines.where((l) => !l.delivered)) {
        await widget.db.setInvoiceLineDelivered(line.id, delivered: true);
      }
      await _reloadLines();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث علم التسليم — $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// س-138/D-132: اختيار المورد يُخزَّن على السطر فوراً.
  Future<void> _setSupplier(InvoiceLineDocument line, int? partyId) async {
    setState(() => _busy = true);
    try {
      await widget.db.setInvoiceLineSupplier(line.id, supplierPartyId: partyId);
      await _reloadLines();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ المورد المسؤول — $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes =
          await buildInvoicePrintoutBytes(widget.db, widget.invoiceId);
      if (!mounted) return;
      await printPdfBytes(context, bytes);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final invoice = await widget.db.invoiceById(widget.invoiceId);
      if (invoice == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('لا فاتورة بهذا المعرف')),
        );
        return;
      }
      final bytes =
          await buildInvoicePrintoutBytes(widget.db, widget.invoiceId);
      await sharePdfBytes(bytes, '${invoiceDisplayLabel(invoice)}.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
        body: Center(child: Text(_error!)),
      );
    }
    final invoice = _invoice;
    if (invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
        body: const Center(child: Text('لا فاتورة بهذا المعرف')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // س-133/D-127: زرا الإخراج ظاهران بنصهما أعلى التفاصيل —
          // هذا ظهور الطباعة الذي طلبته كلمة المالك.
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _print,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('طباعة / PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('مشاركة PDF'),
                ),
              ),
            ],
          ),
          ListTile(
            title: Text(invoiceDisplayLabel(invoice)),
            subtitle: Text(
                'التاريخ ${invoice.invoiceDate}'
                // س-156/D-154 (دفعة 17): لسان المالك — نقدية/ذمة (س50/4)،
                // والمسودة تُنادى بمسودتها.
                ' · السداد ${invoice.cashBoxId != null ? 'نقدية' : 'ذمة'}'
                "${invoice.state == 'draft' ? ' · مسودة' : ''}"),
          ),
          ListTile(
            title: Text('الإجمالي ${formatMinorAmount(invoice.totalDocMinor)}'
                ' $_docSuffix'),
            subtitle: Text(
                '${invoice.currencyId != 1 ? 'المكافئ ب$_baseSymbol ${formatMinorAmount(invoice.totalBaseMinor)} · ' : ''}'
                'المدفوع ${formatMinorAmount(_covered)}'
                ' · الباقي ${formatMinorAmount(invoice.totalDocMinor - _covered)}'),
          ),
          // س-148/D-138 (دفعة 14): عدّاد التسليم «مستلم X من Y»
          // بأساسه الافتراضي (الكميات بالواحدة) وقائمة التبديل
          // بخيارَيها في نفس السطر — بقرار المالك الحرفي.
          // الدفعة 21 (F-168): بكل الأنواع بعد تعميم العلم.
          if (_lines.isNotEmpty) _deliveryCounterRow(),
          // زر «تسليم الكل» (س43 «لا بأس») — يظهر ما دام سطر غير مستلم
          // ويُسحب كلياً من الشاشة عند اكتمال التسليم (لا زر ميت معطل).
          // الدفعة 21 (F-168): بكل الأنواع بعد تعميم العلم.
          if (_lines.isNotEmpty && _hasUndelivered)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _deliverAll,
                  icon: const Icon(Icons.done_all_outlined),
                  label: const Text('تسليم الكل'),
                ),
              ),
            ),
          const Divider(),
          for (final line in _lines) _lineTile(line),
          if (_lines.isEmpty) const ListTile(title: Text('لا بنود')),
        ],
      ),
    );
  }

  /// س-148/D-138: عدّاد التسليم وقائمة التبديل في نفس السطر —
  /// النص بأساس العد المختار والقائمة بخيارَيها (الكميات/الأسطر).
  Widget _deliveryCounterRow() {
    final deliveredQty = quantitiesByUnit([
      for (final l in _lines)
        if (l.delivered) (l.qtyBase, _unitNames[l.unitId] ?? ''),
    ]);
    final totalQty = quantitiesByUnit(
        [for (final l in _lines) (l.qtyBase, _unitNames[l.unitId] ?? '')]);
    final text = invoiceDeliverySummary(
      deliveredLines: _lines.where((l) => l.delivered).length,
      totalLines: _lines.length,
      deliveredQtyByUnit: deliveredQty,
      totalQtyByUnit: totalQty,
      basis: _deliveryBasis,
    );
    return Row(
      children: [
        Expanded(child: Text(text)),
        DropdownButton<DeliveryBasis>(
          value: _deliveryBasis,
          items: [
            for (final b in deliveryBasisChoices)
              DropdownMenuItem(
                  value: b, child: Text('حسب ${deliveryBasisLabel(b)}')),
          ],
          onChanged: (b) {
            if (b != null) setState(() => _deliveryBasis = b);
          },
        ),
      ],
    );
  }

  /// سطر الفاتورة — بعمود «مستلم» في كل الأنواع (الدفعة 21/F-168)
  /// وخانة المورد في البيع حصراً (س-137/س-138) وباسم الصنف لا رقمه
  /// (المبدأ المؤسسي س-143: كل اسم مدخلاً — والنقر يفتح ورقة الصنف
  /// بدفعة 13).
  Widget _lineTile(InvoiceLineDocument line) {
    final item = _itemById[line.itemId];
    final itemName = item?.name ?? 'صنف #${line.itemId}';
    final title =
        '$itemName — ${line.qtyBase} × ${formatMinorAmount(line.unitPriceMinor)}';
    final isSale = _isSale;
    final kind = _invoice == null
        ? InvoiceKind.sale
        : InvoiceKind.fromStorage(_invoice!.kind);
    final suggestion = isSale ? _supplierSuggestion[line.itemId] : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            ListTile(
              title: Text(title),
              subtitle: Text(
                  'المبلغ ${formatMinorAmount(line.lineTotalDocMinor)}'),
              // س-137/D-131: مربع «مستلم» الواحد — غير محدد افتراضاً
              // لكل سطر، والتحديد يحفظ فوراً. الدفعة 21 (F-168): بكل
              // الأنواع بعد تعميم العلم بكلمة المالك.
              trailing: Checkbox(
                value: line.delivered,
                onChanged: _busy
                    ? null
                    : (value) => _toggleDelivered(line, value ?? false),
              ),
              // س-144/D-136: سطر الفاتورة من مواضع ورقة الصنف الخمسة.
              onTap: () =>
                  showItemSheet(context, widget.db, line.itemId, itemName),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  // الدفعة 21 (F-168): لسان الحالة من المنبع الموحد —
                  // البيع بلفظه المعتمد والأنواع الأخرى بلسان الاستلام.
                  receiptLineStatusFor(kind, line.delivered),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            // س-138/D-132: خانة المورد المسؤول بفواتير البيع حصراً —
            // عهدها D-132 ولم يمسه تعميم الدفعة 21.
            if (isSale)
              DropdownButtonFormField<int>(
                initialValue: line.supplierPartyId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المورد المسؤول',
                  border: InputBorder.none,
                ),
                items: [
                  const DropdownMenuItem<int>(
                      value: null, child: Text('بلا مورد')),
                  for (final p in _suppliers)
                    DropdownMenuItem<int>(value: p.id, child: Text(p.name)),
                ],
                onChanged:
                    _busy ? null : (value) => _setSupplier(line, value),
              ),
            // س-138/D-132: الاقتراح من آخر شراء مرحّل — عرضاً لا كتابة،
            // ومن اختار فاختياره هو المخزّن.
            if (isSale &&
                line.supplierPartyId == null &&
                suggestion != null) ...[
              for (final p in _suppliers)
                if (p.id == suggestion)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        'مقترح (آخر شراء): ${p.name}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
