import 'dart:async' show Timer;
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'item_images.dart';
import 'app_theme.dart';
import 'adaptive.dart';
import 'dq_log.dart';
import 'item_media.dart';
import 'print_copies.dart';
import 'print_image_prefs.dart';
import 'print_service.dart';
import 'input_formatters.dart';
import 'reports_screen.dart' show formatMinorAmount;
import 'drilldown.dart' show showItemSheet;
import 'session.dart';
import 'tafqit.dart';
import 'delivery_summary.dart';
import 'currency_display.dart';
import 'date_picker.dart';
import 'context_menu.dart';
import 'hijri_display.dart';
import 'list_display.dart';
import 'empty_state.dart';
import 'l10n/app_strings.dart';

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

/// زوق نوع الفاتورة من الأزقة الدلالية (س186 — بقية م05): الهوى اتجاهُ
/// محاسبة والعبءُ عودةٌ — البيع دائن لنا أخضر معبأ، والشراء مدين
/// علينا أحمر معبأ، والمردودان قرينا اتجاهيهما مخططان بلا تعبئة
/// فيفرّق الإطارُ المردودَ عن أصله بلا عائلة لونية خام جديدة
/// (عقد س182: لا لون خارج الأدوار المعتمدة).
DiqqahLane invoiceKindLane(BuildContext context, InvoiceKind kind) {
  final lanes = diqqahLanesOf(context);
  return switch (kind) {
    InvoiceKind.sale => lanes.positive,
    InvoiceKind.purchase => lanes.negative,
    InvoiceKind.saleReturn => lanes.negativeOutline,
    InvoiceKind.purchaseReturn => lanes.positiveOutline,
  };
}

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
    ? S.receivedLabel
    : kind == InvoiceKind.sale
        ? S.awaitingDelivery
        : S.awaitingReceipt;

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
  int invoiceId, {
  bool warehouseCopy = false,
  String? sizeOverride,
  bool? landscapeOverride,
}) async {
  final invoice = await db.invoiceById(invoiceId);
  if (invoice == null) {
    throw StateError(S.noInvoiceWithId);
  }
  final lines = await db.invoiceLines(invoiceId);
  final items = await db.select(db.items).get();
  final itemById = {for (final item in items) item.id: item};
  // س-148/D-138 (دفعة 14): أسماء الوحدات — الخلاصة «بالواحدة».
  final units = await db.select(db.units).get();
  final unitNameById = {for (final u in units) u.id: u.name};
  // س-10 (الدفعة 30): أسماء مستويات التعبئة — الخلاصة «بالواحدة»
  // بوحدة اللقطة لكل سطر.
  final groupLevels = await db.select(db.unitGroupLevels).get();
  final levelNameById = {for (final l in groupLevels) l.id: l.name};
  final kind = InvoiceKind.fromStorage(invoice.kind);
  final isSale = kind == InvoiceKind.sale;

  // س119 (قوالب الطباعة ونسخة أمين المستودع — بكلمة المالك): القالب
  // يقرر ما يظهر بالورقة لا ما يُحسب — وأعلام الظهور من تفضيلات النوع
  // والغائب كلها ظاهر مطابقاً السلوك القائم حرفاً (حارس انحدار)،
  // والقياس والاتجاه من قالب النوع مع تجاوز لحظي بنافذة النسختين
  // (التحويل الحر D-101). ونسخة أمين المستودع قالب كمّي مشتق لا
  // محفوظ: رقم الصنف واسمه والكمية بلا أسعار ولا مجاميع قيمية ولا تفقيط —
  // بمجموع الكميات بوحداته (جمع وحدات مختلفة ممنوع) وخانتَي توقيع
  // ومعرفات المصدر (المستند والتاريخ والطرف) فهي مرجعة لفاتورة الأم
  // لا مستند يتيم — وعنوانها يميزها «بلا أسعار» كي لا تدور بين
  // الأيدي وثيقة سعرية (عرف Packing Slip: Odoo وQuickBooks وTryton).
  final showDelivered =
      templateFlagForKind(kind, PrintTemplateFlag.delivered);
  final showNotesFlag =
      templateFlagForKind(kind, PrintTemplateFlag.deliveryNotes);
  final showTafqit = templateFlagForKind(kind, PrintTemplateFlag.tafqit);
  // س162 (الشطر الثاني D-103/م-45): أوزان أعمدة النوع — وحرس الطول
  // عند النداء (طول الأوزان يجب أن يطابق أعمدة القسيمة الفعلية).
  final tplWeights = columnWeightsForKind(kind);

  // س-153/D-151 (دفعة 15): عمود «ملاحظة» بقسيمة البيع حصراً حين
  // وُجدت ملاحظة على أسطر غير مستلمة — فلا عمود فارغ يعمّم الضجيج.
  // س119: عمود «ملاحظة» تحت رأي قالب النوع أيضاً — واللسان القائم
  // باقٍ (فواتير البيع حصراً وحين وُجدت ملاحظة أصلاً).
  final hasDeliveryNotes = showNotesFlag &&
      isSale &&
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
        itemById[line.itemId]?.name ?? S.itemWithNumber(line.itemId),
    ];
  }

  // س-140/D-134: عمود «مستلم» — «سُلِّم» للمحدد بفواتير البيع
  // ولسان الاستلام للأنواع الأخرى (تعميم الدفعة 21/F-168)، وسطر
  // الخلاصة تحت الجدول بكل الأنواع.
  // س-153/D-151 (دفعة 15): وعمود «ملاحظة» بقسيمة البيع حصراً حين
  // وُجدت ملاحظة تسليم على أسطرها — فلا عمود فارغ يعمّم الضجيج.
  final columns = <String>[
    S.itemLabel,
    S.quantityLabel,
    S.unitPriceLabel,
    // س50/5 (س-161/D-159 دفعة 17): «المبلغ» — عرف البرمجيات
    // الشهيرة لعمود مبلغ السطر، و«الإجمالي» باق للتذييل كله.
    S.amountLabel,
    // الدفعة 21 (F-168): «مستلم» بكل الأنواع بعد تعميم العلم —
    // وس119: بإمكان قالب النوع إخفاؤه من الإعدادات.
    if (showDelivered) S.receivedLabel,
    if (hasDeliveryNotes) S.noteLabel,
  ];
  final rows = [
    for (final line in lines)
      [
        itemById[line.itemId]?.name ?? S.itemWithNumber(line.itemId),
        // س-10 (الدفعة 30): الكمية بوحدة الاختيار — والسعر لوحتها فلا
        // يُعرض بالأساسية رقمٌ لا يلتقي سعرُه (وبالأساسية مطابق القائم).
        '${line.qty}',
        formatMinorAmount(line.unitPriceMinor),
        formatMinorAmount(line.lineTotalDocMinor),
        if (showDelivered)
          line.delivered
              ? (isSale ? S.deliveredShort : S.receivedLabel)
              : (isSale ? S.awaitingDelivery : S.awaitingReceipt),
        if (hasDeliveryNotes) line.deliveryNote ?? '—',
      ],
  ];
  String? summary;
  // الدفعة 21 (F-168): سطر خلاصة «مستلم X من Y» بكل الأنواع بعد
  // تعميم العلم — وس119: بإمكان قالب النوع إخفاءه مع عموده.
  if (lines.isNotEmpty && showDelivered) {
    // س-148/D-138: الافتراضي «مجموع الكميات بالواحدة» بقاعدة الوحدة
    // الموثقة — والقسيمة المطبوعة على الافتراضي دائماً (القائمة
    // المنسدلة عرضُ شاشة لا سياسة مطبوع).
    final totalQty = quantitiesByUnit([
      for (final l in lines)
        (
          l.qty,
          l.unitLevelId == null
              ? (unitNameById[l.unitId] ?? '')
              : (levelNameById[l.unitLevelId] ?? '')
        ),
    ]);
    final deliveredQty = quantitiesByUnit([
      for (final l in lines)
        if (l.delivered)
          (
            l.qty,
            l.unitLevelId == null
                ? (unitNameById[l.unitId] ?? '')
                : (levelNameById[l.unitLevelId] ?? '')
          ),
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
  final docSuffix = docSymbol.isEmpty ? S.inDocumentCurrency : docSymbol;
  final baseSymbol = currencySymbol(baseCode);
  // س-156/D-154 (دفعة 17): المدفوع من محرك المطابقة ذاته — فواتير
  // السندات المرحّلة بوحدات المستند (س50/4 بلفظ المالك:
  // «في الخاتمة تكتب الدفعة والباقي»).
  final covered = await db.invoiceCoveredDocMinor(invoiceId);

  // ── س119: نسخة أمين المستودع — قالب كمّي مشتق لا محفوظ ──
  // بلا أسعار ولا مجاميع قيمية ولا تفقيط ولا سطر «مستلم» — الصنف
  // والكمية بوحدتها ومجموع الكميات بوحداته (quantitiesByUnit — جمع
  // وحدات مختلفة ممنوع)، وخانتَي التوقيع، ومعرفات المصدر بالترويسة
  // (المستند والتاريخ والطرف) فهي مرجعة لفاتورة الأم.
  if (warehouseCopy) {
    String? partyName;
    if (invoice.partyId != null) {
      final parties = await db.select(db.parties).get();
      for (final party in parties) {
        if (party.id == invoice.partyId) partyName = party.name;
      }
    }
    String unitNameOf(line) => line.unitLevelId == null
        ? (unitNameById[line.unitId] ?? '')
        : (levelNameById[line.unitLevelId] ?? '');
    final totals = quantitiesByUnit([
      for (final l in lines) (l.qty, unitNameOf(l)),
    ]);
    final totalsText = [
      for (final e in totals.entries) '${e.value} ${e.key}',
    ].join(' · ');
    return buildDocumentPdf(
      db: db,
      title: S.deliveryNoteKeeperCopyTitle,
      headerPairs: [
        (S.documentLabel, invoiceDisplayLabel(invoice)),
        (S.dateLabel, printDateLine(invoice.invoiceDate)),
        (S.partyLabel, partyName ?? '—'),
        if (invoice.narration != null && invoice.narration!.isNotEmpty)
          (S.descriptionLabel, invoice.narration!),
      ],
      columns: const [S.itemNumberLabel, S.itemNameLabel, S.quantityLabel],
      rows: [
        for (final line in lines)
          [
            (itemById[line.itemId]?.sku ?? '').isEmpty
                ? '—'
                : itemById[line.itemId]!.sku,
            itemById[line.itemId]?.name ?? S.itemWithNumber(line.itemId),
            '${line.qty} ${unitNameOf(line)}'.trim(),
          ],
      ],
      rowLeadingImages: rowImages,
      rowPlaceholderLetters: rowLetters,
      footerPairs: [
        (S.totalQuantities, totalsText.isEmpty ? '0' : totalsText),
        (S.delivererLabel, '................'),
        (S.receiverLabel, '................'),
      ],
      format: resolvePageFormat(
        docKind: 'invoice',
        sizeOverride: sizeOverride ?? templateSizeForKind(kind),
        landscapeOverride:
            landscapeOverride ?? templateLandscapeForKind(kind),
      ),
    );
  }

  return buildDocumentPdf(
    db: db,
    title: invoiceDisplayLabel(invoice),
    headerPairs: [
      (S.dateLabel, displayDate(invoice.invoiceDate)),
      // س-156/D-154: لسان المالك — «نحن صنفنا الفواتير نقدية وذمة
      // فلتكتب كذلك» (س50/4): السداد بالتصنيف المعتمد عند الإدخال
      // (النقدي بصندوقه والآجل بطرفه — لا صندوق ولا طرف مرفوضان
      // بالمحرك)، والمسودة تُنادى بمسودتها كي لا تُباع ورقة غير
      // مرحّلة بلا إنذار.
      (S.paymentLabel, invoice.cashBoxId != null ? S.cashLabel : S.onAccountLabel),
      if (invoice.state == 'draft') (S.statusLabel, S.draftLabel),
      if (invoice.narration != null && invoice.narration!.isNotEmpty)
        (S.descriptionLabel, invoice.narration!),
    ],
    columns: columns,
    rows: rows,
    rowLeadingImages: rowImages,
    rowPlaceholderLetters: rowLetters,
    summaryText: summary,
    footerPairs: [
      (
        S.totalLabel,
        '${formatMinorAmount(invoice.totalDocMinor)} $docSuffix',
      ),
      // س-159/D-157 (دفعة 17): المكافئ بغير عملة الأساس حصراً — بعملة
      // الأساس كان يكرر سطر الإجمالي بلا فائدة (س50/7 «لا بأس»)،
      // وتسميته برمز الأساس لا بلفظ «المكافئ الأساسي».
      if (invoice.currencyId != 1)
        (
          S.equivalentIn(baseSymbol),
          formatMinorAmount(invoice.totalBaseMinor),
        ),
      // س-156/D-154: المدفوع والباقي بقراءة المحرك — وبرمز العملة.
      (
        S.paidLabel,
        '${formatMinorAmount(covered)} $docSuffix',
      ),
      (
        S.remainingLabel,
        '${formatMinorAmount(invoice.totalDocMinor - covered)} $docSuffix',
      ),
    ],
    // س-160/D-158 (دفعة 17): التفقيط سطراً مستقلاً بلا تسمية — عرف
    // الشيكات وفواتير البرمجيات العربية (س50/8 «تمام»): «فقط ...
    // لا غير» يقف وحده لا يسبقه لفظ يضاعف الكلام. وسقوط العملة من
    // الجدول يسقط السطر سكوتاً لا بلفظ مفبرك (عهد س-149 باقٍ) —
    // وس119: بإمكان قالب النوع إخفاء السطر من الإعدادات.
    standoutLine: !showTafqit
        ? null
        : currencyFields == null
            ? null
            : tafqitAmountWords(
                totalMinor: invoice.totalDocMinor,
                currency: tafqitCurrencyFor(
                  code: currencyFields['code'] as String,
                  name: currencyFields['name'] as String,
                  minorUnits: currencyFields['minorUnits'] as int,
                ),
              ),
    // س119: القياس والاتجاه من قالب النوع — الافتراضي a5 طولي
    // مطابق القائم حرفاً، والتجاوز اللحظي من نافذة النسختين.
    format: resolvePageFormat(
      docKind: 'invoice',
      sizeOverride: sizeOverride ?? templateSizeForKind(kind),
      landscapeOverride:
          landscapeOverride ?? templateLandscapeForKind(kind),
    ),
    // س162 (الشطر الثاني D-103/م-45): أوزان الأعمدة والنصان الحرّان
    // من قالب النوع — وحرس الطول: الأوزان لا تُطبق إلا بطولها مطابقاً
    // أعمدة القسيمة الفعلية (تغير الأعلام أو غياب الملاحظات يعيدها
    // للمتساوي حرفاً)، والنص الفراغ لا يطبع شيئاً. ونسخة أمين
    // المستودع قالب كمّي ثابت لا تدخلها الأوزان ولا النصوص الحرة.
    columnWeights: (tplWeights != null && tplWeights.length == columns.length)
        ? tplWeights
        : null,
    freeHeaderText: freeHeaderTextForKind(kind),
    freeFooterText: freeFooterTextForKind(kind),
  );
}

/// شاشة الفواتير — دفعة (6-ج) واجهات الإدخال (س-86..س-88، D-094 معروض):
/// الوحدة مفتوحة من الهيكلية بعد اعتماد المالك لبوابة (6-ب) بلفظه
/// «اعتمدها» (س36)، والقائمة قراءة لحظية من المرحّل حصراً (لا جداول
/// تجميع — D-089)، والمدى والفلتر تحسينان للعرض لا قراراً — والمدى
/// المُدخل يُدقق قبل لمس القاعدة (D-077).
/// جهة الأرشيف (س202 — بأمر المالك «قم بتنفيذ المطلوب 1-5»): بلاطتا
/// «المبيعات»/«المشتريات» بالرئيسية تفتحان الأرشيف بجهته — البيع
/// ومردوده معاً أو الشراء ومردوده معاً — والفراغ مدخل الأرشيف المحايد
/// بكل الأنواع (مرجع الاختبارات والروابط الأخرى).
enum InvoiceArchiveSide {
  sales(S.salesLabel, S.salesAndReturns),
  purchases(S.purchasesLabel, S.purchasesAndReturns);

  /// اسم الجهة بلسان البلاطة — عنوان الشاشة به.
  final String title;

  /// لسان الجهة بورقة الإدخال.
  final String laneLabel;

  const InvoiceArchiveSide(this.title, this.laneLabel);
}

/// قيمة فلتر الجهة بالمنسدل — المجموعتان المقبولتان بreport التخزين
/// حرفاً (س202)، فوراء كل منهما نوعاها معاً.
const String kSideFilterSales = 'sales';
const String kSideFilterPurchases = 'purchases';

class InvoicesScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// س202: الجهة المبدئية من بلاطة الرئيسية — تضبط الفلتر عند الفتح
  /// وتحوّل ورقة الإدخال إلى نوعَي الجهة حصراً، والفراغ الأرشيف المحايد.
  final InvoiceArchiveSide? initialSide;

  const InvoicesScreen({super.key, required this.db, this.initialSide});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();

  /// س210 (بحث م11 — بأمر المالك «انتقال أرشيف الفواتير للقاعدة
  /// الزمنية الموحدة مع بحث م11»): حقل البحث المكتوب ينتظر زر
  /// «عرض» بعرف D-077 (الجاهز لحظي والمكتوب بزر عرض — قرار س208
  /// الموثق)، والنمط م11 بعنوانه الدائم وأيقونته المسبقة بنمط بحث
  /// الأطراف س206 حرفاً.
  final TextEditingController _search = TextEditingController();

  /// قيمة البحث المطبّقة لحظة آخر إعادة تحميل (عرض أو اختيار جاهز)
  /// — فالعرض المطبوع والمصدّر صورة العرض ذاتها (عرف F-166).
  String _appliedQuery = '';

  /// قيمة التخزين لنوع الفلتر — null يعني الكل.
  String? _kind;

  /// س221 — حد العرض المتدرج للقائمة (إعادة تشكيل قوائم المستندات):
  /// شحنة [kListDisplayPageSize] صفّاً ثم توسيع بضغطة، ويصفر مع كل
  /// استعلام جديد فالفلتر المنعش يبدأ من أعلى القائمة.
  int _displayLimit = kListDisplayPageSize;

  /// الدفعة 21 (F-168): قيمة فلتر الاستلام — null الكل وإلا
  /// 'undelivered' أو 'partial' أو 'received'.
  String? _receipt;

  /// س164: فلتر الحالة — null الكل وإلا 'draft' (المسودات) أو
  /// 'posted' (المرحّلة) — لسان صاحب البوابة الذي يبحث عن مسودات
  /// الآخرين (التعليق ملغى س164).
  String? _state;

  /// س235: شريط المدى الفوري الموحد — المصدر الواحد لأزرار التاريخ
  /// الخمسة وحقلي من/إلى بحرسيه (التلوين والديبونس) — والمسح الشامل
  /// يفرّغه بمفتاحه (clear) فلا تكرار تحميل.
  final GlobalKey<DiqqahInstantRangeBarState> _rangeBarKey =
      GlobalKey<DiqqahInstantRangeBarState>();

  /// س234 (المرحلة ب/3): ديبونس البحث — زر «عرض» رُفع فالكتابة
  /// تُطبَّق بتأخير قصير (نصف ثانية بلا ضغط آخر حرف).
  Timer? _applyDebounce;

  /// س101: خيارات فلتر الحالة — الثلاثية المألوفة.
  static final List<(String?, String)> _stateChoices = [
    (null, S.allStatuses),
    ('draft', S.draftsLabel),
    ('posted', S.postedLabel),
  ];

  /// س164: جلسة صاحب الأرشيف — أصحاب بوابة «ترحيل مسودات الآخرين»
  /// يرون زر الترحيل على المسودات، والفراغ (فشل قراءة أو لا دور) لا زر
  /// — الترحيل عملٌ مال فسقوطه مغلق لا مفتوح، ومسودة صاحب اليد
  /// تُرحَّل بيده من التفاصيل بلا بوابة (فصل الأيدي).
  SessionInfo? _session;

  bool get _canPostOthers => _session?.canPostOthersInvoices ?? false;
  /// الدفعة 21 (F-168): الصفوف المعروضة حالياً — بطاقة أزرار الطباعة
  /// والتصدير في الشريط العلوي تقرؤها، فالمطبوع والمصدّر صورة العرض
  /// ذاتها (عرف F-166).
  List<InvoiceListRow>? _listRows;

  Future<List<InvoiceListRow>>? _rows;

  /// س221 (عزل النوع بأمر المالك «النوع يعرض 7 خيارات نصفها للبيع
  /// ونصفها للمشتريات دون تمييز ينبغي العزل»): خيارات النوع بجهة
  /// الأرشيف — الجهة المفتوحة لا ترى أنواع الجهة الأخرى إطلاقاً
  /// (المبيعات ببيعها ومردوده والمشتريات بشرائها ومردوده، و«الكل»
  /// فيها جهتها كلها لا القاعدة كلها)، والدخول الحيادي (سجل الفواتير)
  /// يبقى جامعاً بألسنة معلّمة بالجهة فلا خيار بلا تمييز.
  List<(String?, String)> get _kindChoices => switch (widget.initialSide) {
        InvoiceArchiveSide.sales => [
          (kSideFilterSales, S.salesAllFilter),
          (InvoiceKind.sale.storageValue, InvoiceKind.sale.label),
          (InvoiceKind.saleReturn.storageValue, InvoiceKind.saleReturn.label),
        ],
        InvoiceArchiveSide.purchases => [
          (kSideFilterPurchases, S.purchasesAllFilter),
          (InvoiceKind.purchase.storageValue, InvoiceKind.purchase.label),
          (InvoiceKind.purchaseReturn.storageValue,
              InvoiceKind.purchaseReturn.label),
        ],
        null => [
          (null, S.allTypes),
          (kSideFilterSales, S.salesTypeFilter),
          (kSideFilterPurchases, S.purchasesTypeFilter),
          (InvoiceKind.sale.storageValue, S.salesInvoiceType),
          (InvoiceKind.saleReturn.storageValue, S.salesReturnType),
          (InvoiceKind.purchase.storageValue, S.purchaseInvoiceType),
          (InvoiceKind.purchaseReturn.storageValue, S.purchaseReturnType),
        ],
      };

  /// الدفعة 21 (F-168): خيارات فلتر الاستلام — ثلاث حالات لا اثنتان
  /// لأن الثنائية تخفي الجزئي (فاتورة سُلّم نصفها تظهر «غير مستلم»
  /// كذباً).
  static final List<(String?, String)> _receiptChoices = [
    (null, S.allLabel),
    ('undelivered', S.notReceived),
    ('partial', S.partialLabel),
    ('received', S.fullyReceived),
  ];

  @override
  void initState() {
    super.initState();
    // س202: بلاطة الجهة تفتح الأرشيف بفلتر جهتها من أول لحظة — المبيعات
    // تُرى ببيعها ومردودها والمشتريات بشرائها ومردودها بلا تبديل يدوي.
    _kind = switch (widget.initialSide) {
      InvoiceArchiveSide.sales => kSideFilterSales,
      InvoiceArchiveSide.purchases => kSideFilterPurchases,
      null => null,
    };
    _reload();
    _loadSession();
    // س234 (المرحلة ب/3): التطبيق الفوري — البحث يستمع للكتابة
    // فيطبقها بتأخير قصير (والمدى بشريطه الموحد س235).
    _search.addListener(_onSearchTyped);
  }

  @override
  void dispose() {
    _applyDebounce?.cancel();
    _from.dispose();
    _to.dispose();
    _search.dispose();
    super.dispose();
  }

  /// س234: الكتابة بالبحث — تأخير قصير ثم التحميل (الديبونس بلا ضغط).
  void _onSearchTyped() {
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _reload();
    });
  }


  /// س234 (المرحلة ب/3): مسح الفلاتر — البحث والمدى والنوع والاستلام
  /// والحالة إلى سذاجتها الأولى (النوع بجهة الدخول إن دخل ببلاطة
  /// جهة) ثم التحميل — فالبداية النظيفة بضغطة واحدة بلا تفكيك يدوي.
  void _clearFilters() {
    _applyDebounce?.cancel();
    // س235: الشريط الموحد يفرّغ حقليه وتلوينه بلا تحميل (clear)
    // — والشاشة تفرغ ما عندها وتحمل مرة واحدة.
    _rangeBarKey.currentState?.clear();
    _search.clear();
    setState(() {
      _kind = switch (widget.initialSide) {
        InvoiceArchiveSide.sales => kSideFilterSales,
        InvoiceArchiveSide.purchases => kSideFilterPurchases,
        null => null,
      };
      _receipt = null;
      _state = null;
    });
    _reload();
  }

  void _reload() {
    // المدى الفاسد يرمي داخل الـFuture فيُعرض بلسان المدقق من الـFutureBuilder
    // — لا صمت ولا انهيار (D-077: المدقق حرس أول).
    setState(() {
      // س210 (بحث م11): البحث المكتوب يُطبّق لحظة إعادة التحميل حصراً
      // — الكتابة وحدها لا تعيد شيئاً (القاعدة الزمنية الموحدة).
      _appliedQuery = _search.text.trim();
      // س221: استعلام جديد فالحد المتدرج يصفر — البدء من أعلى القائمة.
      _displayLimit = kListDisplayPageSize;
      // س202: مجموعتا الجهة تمرّان بفلتر الجهة لا بنوع مفرد — والنوع
      // الفردي يمرّ حرفاً كما كان.
      final isSide = _kind == kSideFilterSales || _kind == kSideFilterPurchases;
      _rows = widget.db.invoicesListReport(
        fromText: _from.text.trim(),
        toText: _to.text.trim(),
        kindStorageValue: isSide ? null : _kind,
        sideFilter: isSide ? _kind : null,
        // الدفعة 21 (F-168): فلتر الاستلام يمرّ للقاعدة مع البقية.
        receiptFilter: _receipt,
        // س101: فلتر الحالة — معلّقات المندوبين بلسان المعتمد.
        stateFilter: _state,
      );
    });
  }

  /// س101: قراءة الجلسة مرة واحدة — من يملك الاعتماد يرى زره.
  Future<void> _loadSession() async {
    final s = await loadSession(widget.db);
    if (!mounted) return;
    setState(() => _session = s);
  }

  /// س164: نافذة تأكيد الترحيل — الترحيل يمس المخزون والدفتر
  /// والذمة فالقرار بضغطة واعية لا بصمت زر.
  Future<bool> _confirmApprove(InvoiceListRow row) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.postDraftTitle),
        content: Text(
          S.postDraftBody(row.displayLabel, formatMinorAmount(row.totalDocMinor), row.currencyCode),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(S.keepAsDraft),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(S.postNow),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  /// س164: الترحيل من الأرشيف — المحرك ذاته (postInvoice) فلا مسار
  /// موازٍ، والخطأ بلسان مدققه والنجاح تحديثاً للقائمة.
  Future<void> _approve(InvoiceListRow row) async {
    if (!await _confirmApprove(row)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.db.postInvoice(row.id);
      final posted = await widget.db.invoiceById(row.id);
      messenger.showSnackBar(SnackBar(
        content: Text(posted == null || posted.number.isEmpty
            ? S.invoicePosted
            : S.postedWithNumber(posted.number)),
      ));
      _reload();
      // س119: الترحيل من الأرشيف يفتح أمر الطباعة بنسختَيه أيضاً.
      if (!mounted) return;
      await showInvoicePrintCopiesDialog(context, widget.db, row.id);
    } on InvoiceValidationException catch (e) {
      await dqLog(widget.db, e, context: 'invoices.post');
      // الرمز DQ-1001 للسجل والمرجع لا نص المستخدم (س204 — م03).
      messenger.showSnackBar(SnackBar(
        content: Text(
          S.postRejected(
            [for (final err in e.errors) describeInvoiceValidationError(err)]
                .join(' · ')
          ),
        ),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoices.post');
      messenger.showSnackBar(SnackBar(
        content: Text(S.postFailed(e, dqTag(e))),
      ));
    }
  }

  void _openNew() async {
    // عزل الإدخال من الأرشيف أيضاً (س-163/D-161): أزرار تُحدد النوع بالضغط
    // لا قائمة منسدلة — نمط القائمة الرئيسية ذاته، واختيار النوع هنا
    // يفتح النموذج بنوعه المثبت.
    // س202: ورقة الاختيار بإدراك الجهة — من بلاطة المبيعات نوعاها حصراً
    // (البيع ثم مردوده) ومن المشتريات نوعاها، والبلا المحايد الأربعة
    // عرف س-163 — والضغط الصريح لا يزال هو التحديد لا انتقاء بالنموذج.
    final kinds = <List<InvoiceKind>>[
      switch (widget.initialSide) {
        InvoiceArchiveSide.sales => [
            InvoiceKind.sale,
            InvoiceKind.saleReturn,
          ],
        InvoiceArchiveSide.purchases => [
            InvoiceKind.purchase,
            InvoiceKind.purchaseReturn,
          ],
        null => [
            InvoiceKind.sale,
            InvoiceKind.purchase,
          ],
      },
      if (widget.initialSide == null)
        [InvoiceKind.saleReturn, InvoiceKind.purchaseReturn],
    ];
    final kind = await showModalBottomSheet<InvoiceKind>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // س202: ورقة الجهة بلسان جهتها والمعايد بلسانه القائم.
              Text(
                widget.initialSide == null
                    ? S.newInvoiceChooseType
                    : S.newInvoiceOfType(widget.initialSide!.laneLabel),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < kinds.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(children: [
                  for (final k in kinds[i]) ...[
                    if (k != kinds[i].first) const SizedBox(width: 10),
                    _sheetKindButton(sheetContext, k),
                  ],
                ]),
              ],
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    final created = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
          builder: (_) => InvoiceEditScreen(db: widget.db, initialKind: kind)),
    );
    if (created == true) {
      _reload();
    } else if (created is int) {
      // س119: أمر الطباعة الواحد بعد إضافة/ترحيل الفاتورة — النسختان
      // مفعلتان افتراضياً والإزالة لهذه المرة فقط (الحالة لا تُكتب).
      _reload();
      if (!mounted) return;
      await showInvoicePrintCopiesDialog(context, widget.db, created);
    }
  }

  /// زر نوع بقائمة الأرشيف السفلية — بزوق نوعه الدلالي وأيقونته عرف
  /// الرئيسية، والمردود مخطط الإطار بلا تعبئة (س186).
  Widget _sheetKindButton(BuildContext sheetContext, InvoiceKind kind) {
    final lane = invoiceKindLane(sheetContext, kind);
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: lane.bg,
          side: BorderSide(color: lane.border),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => Navigator.of(sheetContext).pop(kind),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(invoiceKindIcon(kind), color: lane.fg),
            const SizedBox(height: 6),
            Text(kind.label,
                style:
                    TextStyle(color: lane.fg, fontWeight: FontWeight.bold)),
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
      await dqLog(widget.db, e, context: 'invoice.quick_print');
      messenger.showSnackBar(
        SnackBar(content: Text(S.printFailed(e, dqTag(e)))),
      );
    }
  }

  /// س210 (بحث م11): مطابقة صف الأرشيف بالاستعلام على ألسنة العرض
  /// الثلاثة (الطرف والرقم والنوع) بتطبيع المجال الموثق D-064 —
  /// عرضٌ حصر فلا مساس بالمجال والتخزين حرفاً.
  static bool _matchesArchiveQuery(InvoiceListRow row, String query) {
    final q = normalizeArabicForSearch(query);
    return normalizeArabicForSearch(row.counterpartLabel).contains(q) ||
        normalizeArabicForSearch(row.number).contains(q) ||
        normalizeArabicForSearch(row.displayLabel).contains(q);
  }

  /// الدفعة 21 (F-168): أعمدة أرشيف الفواتير وصفوفه تجميعاً واحداً —
  /// المطبوع والمصدّر صورة العرض ذاتها فلا انحراف (عرف F-166 الموثق).
  static const List<String> _archiveColumns = [
    S.typeLabel,
    S.numberLabel,
    S.dateLabel,
    S.partyOrBoxLabel,
    S.statusLabel,
    S.receiptLabel,
    S.amountLabel,
  ];

  static List<List<String>> _archiveRows(List<InvoiceListRow> rows) => [
        for (final row in rows)
          [
            row.kindValue.label,
            row.number.isEmpty ? '—' : row.number,
            // الدفعة 23 (F-167/D-183): الهجري بجانب الميلادي حين يُفعَّل
            // الخيار — عرض لا إدخال والميلادي أساس التخزين دائماً.
            displayDate(row.invoiceDate),
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
        db: widget.db,
        title: S.invoicesLog,
        headerPairs: const [],
        columns: _archiveColumns,
        rows: _archiveRows(rows),
        footerPairs: [
          (S.invoicesCount, '${rows.length}'),
        ],
        format: resolvePageFormat(docKind: 'report'),
      );
      await sharePdfBytes(bytes, S.invoicesLogPdf);
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.archive_print');
      messenger.showSnackBar(
        SnackBar(content: Text(S.printFailed(e, dqTag(e)))),
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
        title: S.invoicesLog,
        columns: _archiveColumns,
        rows: _archiveRows(rows),
        footer: [(S.invoicesCount, '${rows.length}')],
      );
      await shareCsvBytes(csv, S.invoicesLogCsv);
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.archive_csv');
      messenger.showSnackBar(
        SnackBar(content: Text(S.exportFailed(e, dqTag(e)))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // س202: عنوان الجهة بلسان بلاطتها — المبيعات/المشتريات من البلاطتين
        // والأرشيف المحايد بلسانه القائم.
        title: Text(widget.initialSide?.title ?? S.invoicesTitle),
        actions: [
          // الدفعة 21 (F-168): طباعة القائمة المفلترة وتصديرها CSV —
          // في الشريط العلوي سطراً مستقلاً لا حشواً بصف فلاتر (درس س67)،
          // وتعطيلهما بلا صفوف فلا زر ميت (عرف زر تسليم الكل).
          IconButton(
            tooltip: S.printList,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: (_listRows == null || _listRows!.isEmpty)
                ? null
                : _printList,
          ),
          IconButton(
            tooltip: S.exportCsv,
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
        label: const Text(S.newInvoice),
      ),
      body: Column(
        children: [
          Padding(
            // س210 (قانون العرض): هامش التكيف الأفقي على قسم الفلاتر
            // — القائمة بعرفها الموثق والقسم بحد القانون ذاته.
            padding: EdgeInsets.fromLTRB(
                diqqahAdaptiveHorizontalMargin(context), 12,
                diqqahAdaptiveHorizontalMargin(context), 4),
            child: Column(
              children: [
                // س234 (المرحلة ب/3): البحث ومسح الفلاتر بسطر واحد —
                // البحث يطبَّق بتأخير قصير (لا زر عرض بعد اليوم) والمسح
                // بداية نظيفة بضغطة واحدة.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: S.searchPartyOrNumber,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('invoices_clear_filters'),
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text(S.clearFiltersLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // س235: شريط المدى الفوري الموحد — أزرار التاريخ
                // الخمسة بسطورها الصغيرة وتلوين المختار وحقلا من/إلى
                // بديبونسهما وحرس زواجهما (المصدر الواحد بdate_picker).
                DiqqahInstantRangeBar(
                  key: _rangeBarKey,
                  from: _from,
                  to: _to,
                  onReload: _reload,
                ),
                const SizedBox(height: 8),
                // س234 (المرحلة ب/3): الفلاتر الثلاثة بسطر واحد —
                // النوع والاستلام والحالة — وزر «عرض» رُفع فالتطبيق
                // فوري بالاختيار (نمط الطلبات الموثق س208 يسري هنا).
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _kind,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: S.typeLabel),
                        items: [
                          for (final (value, label) in _kindChoices)
                            DropdownMenuItem<String>(
                                value: value, child: Text(label)),
                        ],
                        // س234: التطبيق الفوري — الاختيار الجاهز يحمل
                        // لحظته فلا زر عرض أصلاً (عقد D-234).
                        onChanged: (value) {
                          _kind = value;
                          _reload();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _receipt,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: S.receiptLabel),
                        items: [
                          for (final (value, label) in _receiptChoices)
                            DropdownMenuItem<String>(
                                value: value, child: Text(label)),
                        ],
                        onChanged: (value) {
                          _receipt = value;
                          _reload();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _state,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: S.statusLabel),
                        items: [
                          for (final (value, label) in _stateChoices)
                            DropdownMenuItem<String>(
                                value: value, child: Text(label)),
                        ],
                        onChanged: (value) {
                          _state = value;
                          _reload();
                        },
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
                // س210 (بحث م11): البحث المطبّق يُرشّح ألسنة العرض الثلاثة
                // بتطبيع المجال الموثق D-064 — والرشّح هنا لا في الاستعلام
                // فالمدى والفلاتر يبقيان حصتهما (عرضٌ لا قرار).
                final q = _appliedQuery;
                final visible = q.isEmpty
                    ? rows
                    : rows
                        .where((r) => _matchesArchiveQuery(r, q))
                        .toList();
                // الدفعة 21 (F-168): بطاقة الشريط العلوي تقرأ الصفوف
                // المعروضة ذاتها — والمطبوع والمصدّر صورة العرض.
                _listRows = visible;
                if (visible.isEmpty) {
                  return Center(
                    // س225 (خ6): حالة الفراغ الحية — القرص البني
                    // الهويّي بدل النص العائم، واللسان القائم حرفاً.
                    child: DiqqahEmptyState(
                      icon: rows.isEmpty
                          ? Icons.receipt_long_outlined
                          : Icons.search_off,
                      message: rows.isEmpty
                          ? S.noInvoicesYet
                          : S.noSearchResults,
                    ),
                  );
                }
                return ListView(
                  padding: EdgeInsets.symmetric(
                      horizontal: diqqahAdaptiveHorizontalMargin(context)),
                  children: [
                    // س210 (بحث م11): القائمة تصيّر المُرشَّح حصراً —
                    // فالعرض المطبوع والمصدّر صورة العرض ذاتها (F-166).
                    for (final row in listDisplayPage(visible,
                        limit: _displayLimit))
                      // س234 (D-234 — المرحلة ب/1): الأزرار الثلاثة لكل
                      // سجل بمفاتيح مستقلة — عرض وطباعة ونسخ الرقم —
                      // والافتراضي الزر الأول (نقر الصف عرض)، والقائمة
                      // السياقية الموروثة (س207) رُفعت من هنا بقرار
                      // الخطة «إلغاء السلوك الموروث» (فعالياتها الثلاث
                      // هي الأزرار الثلاثة ذاتها فلا فعل ضائع).
                      ListTile(
                        key: ValueKey('invoice_row_${row.id}'),
                        title: Text(row.displayLabel),
                        subtitle: Text(
                            '${displayDate(row.invoiceDate)}'
                            ' · ${row.counterpartLabel}'
                            ' · ${row.stateLabel}'
                            // الدفعة 21 (F-168): حالة الاستلام بالصف —
                            // لسان القائمة هو ذاته لسان المطبوع والCSV.
                            ' · ${row.receiptLabel}'),
                        // س234 (D-234 — المرحلة ب/1): أثر السجل صف
                        // واحد مثبت بنمط الأصل — الأزرار الثلاثة مكتنزة
                        // والمبلغ آخر الصف (فلا عمود يفيض أبداً).
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // س164: زر الترحيل على المسودات لأصحاب
                            // البوابة حصراً — نفس المحرك لا مسار موازٍ.
                            if (row.state == 'draft' && _canPostOthers)
                              IconButton(
                                key: ValueKey('invoice_post_${row.id}'),
                                tooltip: S.postAction,
                                icon: const Icon(Icons.task_alt_outlined),
                                onPressed: () => _approve(row),
                              ),
                            IconButton(
                              key: ValueKey('invoice_view_${row.id}'),
                              tooltip: S.invoiceDetailsTitle,
                              icon: const Icon(Icons.visibility_outlined),
                              onPressed: () => _openDetail(row.id),
                            ),
                            IconButton(
                              key: ValueKey('invoice_print_${row.id}'),
                              tooltip: S.quickPrint,
                              icon: const Icon(Icons.print_outlined),
                              onPressed: () => _quickPrint(context, row.id),
                            ),
                            IconButton(
                              key: ValueKey('invoice_copy_${row.id}'),
                              tooltip: kCopyIdLabel,
                              icon: const Icon(kCopyIdIcon),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: '${row.id}'));
                                if (!mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(const SnackBar(
                                      content: Text(kCopiedSnack)));
                              },
                            ),
                            const SizedBox(width: 4),
                            Text(
                                '${formatMinorAmount(row.totalDocMinor)}'
                                ' ${row.currencyCode}'),
                          ],
                        ),
                        // الافتراضي الزر الأول: نقر الصف عرض التفاصيل.
                        onTap: () => _openDetail(row.id),
                      ),
                    if (visible.length > _displayLimit)
                      listDisplayExpandButton(
                        context: context,
                        remaining: visible.length - _displayLimit,
                        onExpand: () => setState(() =>
                            _displayLimit += kListDisplayPageSize),
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

/// ورقة منتقي المردود (م04 — س205): مرشحو الأصل ببحثٍ حي على القائمة
/// المحمّلة — الرقم أو التاريخ أو اسم الطرف — وكل مرشح بسطره برقمه
/// وتاريخه وطرفه وإجماله بعملة المستند، والاختيار يعيد معرف الأصل
/// للنموذج فيبذره. لا قراءة داخل البناء — المرشحون محمّلون سلفاً
/// (درس لا Future داخل build).
class _ReturnPickerSheet extends StatefulWidget {
  final List<InvoiceReturnCandidate> candidates;
  final String searchHint;

  const _ReturnPickerSheet({
    required this.candidates,
    required this.searchHint,
  });

  @override
  State<_ReturnPickerSheet> createState() => _ReturnPickerSheetState();
}

class _ReturnPickerSheetState extends State<_ReturnPickerSheet> {
  String _query = '';

  List<InvoiceReturnCandidate> get _visible {
    final q = _query.trim();
    if (q.isEmpty) return widget.candidates;
    return [
      for (final c in widget.candidates)
        if ('${c.id}'.contains(q) ||
            c.invoiceDate.contains(q) ||
            (c.partyName ?? '').contains(q))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: 480,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            S.returnNoMatchingOrigin,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final c in visible)
                            ListTile(
                              leading: const Icon(
                                  Icons.receipt_long_outlined),
                              title: Text(
                                  S.invoiceOfNumber(c.id, c.invoiceDate)),
                              subtitle: Text(c.partyName ?? S.noParty),
                              trailing: Text(
                                  formatMinorAmount(c.totalDocMinor)),
                              onTap: () =>
                                  Navigator.of(context).pop(c.id),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
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

  /// س237 (D-235 — المرحلة ج): السطر الحر — بوصفه وسعره اليدوي ولا
  /// صنف له ولا حركة مخزون (موسوم بصرياً ببطاقته).
  bool isFree = false;

  /// س237: كتابة الصنف الفورية — الاستعلام الحي بالاسم أو الرمز.
  final TextEditingController itemQuery = TextEditingController();
  final TextEditingController description = TextEditingController();
  final TextEditingController note = TextEditingController();
  final FocusNode itemFocus = FocusNode();

  /// س237: ملاحظة السطر — حقل صغير قابل للتوسيع.
  bool noteVisible = false;

  /// مستوى التعبئة المختار للسطر — null للوحدة الأساسية (س-10/D-031:
  /// لقطة الوحدة والعامل في السطر). تغيير الصنف يعيده للأساسية.
  int? unitLevelId;

  /// وسم مصدر السعر حين جاء اقتراح «آخر سعر فعلي» (F-146/D-183) —
  /// يُعرض صغيراً ليصدر الاقتراح من أين جاء، ويصمت حين عدّله الإنسان
  /// أو جاء من المرجعي كالعادة.
  String? priceSource;

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
    // س237: كتابة الصنف والوصف والملاحظة مع السطر.
    itemQuery.dispose();
    description.dispose();
    note.dispose();
    itemFocus.dispose();
  }
}

/// نموذج فاتورة موحد للأنواع الأربعة (س-86/س-87/س-88): «نقدي يطلب
/// صندوقاً والآجل يطلب طرفاً» — والنقدية استدلال من وجود الصندوق حرفاً
/// (InvoiceDraft.isCash)، والمردود يطلب أصلياً (س-05/س-11)، والإدخال
/// بالوحدة الأساسية حصراً في م1 (09 §2). المحرك حرس الحدود: مدقق
/// البنية قبل الكتابة وفحوص الترحيل بعدها والقاعدة ثالثاً — والواجهة
/// تعرض رسائل المدقق العربية كما هي فتُرى سبب الرفض لا خطأ غامضاً.

/// حقيقة تنبيه F-164 المعروضة في النافذة — أرقام جاهزة للعرض لا حسابات.
class _CreditWarning {
  final String partyName;
  final int limitMinor;
  final int netAfterMinor;
  final int excessMinor;

  const _CreditWarning({
    required this.partyName,
    required this.limitMinor,
    required this.netAfterMinor,
    required this.excessMinor,
  });
}

class InvoiceEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// عزل الإدخال (س-163/D-161): النوع يُحدد بزر القائمة الرئيسية ولا
  /// مبدّل نوع بالنموذج — والافتراضي شراء عرف النموذج الموحد قبل الأزرار
  /// (فتح برمجي مباشر كالاختبارات والأرشيف يمرره صريحاً).
  final InvoiceKind initialKind;

  /// س123: بذرة التحويل النافذ من أمر مؤكد (07 §3.2/D-026) — النافذة
  /// بشاشة الطلبات تفتح النموذج معبأً بالمتبقي من الأمر بأسعاره
  /// المرجعية فتخرج الفاتورة مرجعةً لأمرها (`order_id` بالمسودة) ولا
  /// سطر فيها يتجاوز متبقيه (حرسا التخزين). الغائب فاتورة حرة كما
  /// كانت كلها قبل س123 فلا مساس بالقائم حرفاً.
  final OrderConversionPreview? conversionSeed;

  /// س203: بذرة «مردود من هذه الفاتورة» — معرّف الأصل معبّأً في حقل
  /// الإلزام للمردود (س-05/س-11) فلا يدخل المالك يدوياً ما هو مرئي
  /// أمامه. الغائب فراغ كالقديم حرفاً.
  final int? initialOriginalInvoiceId;

  const InvoiceEditScreen({
    super.key,
    required this.db,
    this.initialKind = InvoiceKind.purchase,
    this.initialOriginalInvoiceId,
    this.conversionSeed,
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

  /// اقتراحات الإدخال (F-146/D-183): الطرف الأكثر تداولاً (يُحمّل مرة
  /// واحدة عند الفتح من المرحّل) وآخر سعر فعلي لكل صنف مع الطرف المختار
  /// (يُحمّل عند تعيينه ويُمسح مع تغيّره) — اقتراح بقبول بشري لا قرار.
  int? _mostActivePartyId;
  Map<int, LastPriceSuggestion> _lastPrices = {};

  final List<_LineUi> _lines = [_LineUi()];

  List<CashBoxReportRow> _boxes = [];
  List<Party> _parties = [];
  List<WarehouseRow> _warehouses = [];
  List<CurrencyRow> _currencies = [];
  List<Item> _items = [];
  Map<int, String> _unitNames = {};

  /// س-10 (الدفعة 30): مستويات التعبئة وأسعارها لأصناف النموذج —
  /// قائمة الوحدة بالسطر وتعبئة سعر وحدة الاختيار (سعر المخزن لقطة
  /// الدفعة 27 وغيابه اشتقاق لحظي من الأساسية بعامل المستوى).
  List<UnitGroupLevel> _groupLevels = const [];
  Map<int, Map<int, (int, int)>> _levelPrices = {};
  Map<int, String> _levelNameById = {};

  /// فهرس الباركودات (س-132 — D-126): البحث السريع والمطابقة الكاملة
  /// بقارئ البلوتوث.
  Map<int, List<String>> _barcodesByItem = {};

  /// خانة بحث بنود الفواتير السريعة (س-132): تطابق الاسم والكود
  /// والباركود، والرمز الكامل يجلب الصنف مباشرة.
  final TextEditingController _quickSearch = TextEditingController();

  // ── س225: التحديد المتعدد الجماعي (بديل لوح الفئة بأمر المالك
  // «أطلب منك بديلاً عنها أن تتاح الفرصة للمستخدم أن يختار أكثر من
  // مادة بالنقر عليها في ويندوز أو النقر الطويل للتحديد المتعدد
  // في اندرويد») ──
  //
  // العقد:
  // - الدخول للوضع: لمسة طويلة على اقتراح (أندرويد) أو نقر مع Ctrl
  //   (ويندوز) — وShift+نقر يمدّ التحديد لمجال متتالٍ (عرف المنصتين).
  // - النقر التبعي داخل الوضع يضيف وينقص، وخارجه المسار الواحد
  //   القائم حرفاً (س-132) فلا سلوك قديم ينكسر.
  // - «إضافة المحدد» يصبّ المحدد أسطراً بكمية 1 وسعرها الافتراضي
  //   بترتيب الاختيار ذاته، والتركيز يجري على كمية أول مضاف فتمرّ
  //   الكميات بالتوالي (عقد س-109/D-110 باقٍ: الكمية بوحدة الاختيار
  //   والتركيز الآلي) — الجرد سريع باللمس والتدقيق الكمي بعده.
  // - محايد الطبعات: يخدم المحل والشركة معاً بلا شرط نسخة، ومكرر
  //   الصنف القائم يوسم «موجود» ويُضاف تعمداً إن اختير.
  final List<int> _quickSelected = <int>[];
  bool _quickSelectMode = false;
  int? _lastSelectIndex;

  /// الصنف المقترح مسجلٌّ أصلاً بسطر من أسطر النموذج — وسم إفصاح لا
  /// منع: التكرار المتعمد بالتحديد مشروع (نمط أرجّاع الأصناف).
  bool _itemAlreadyInLines(int itemId) =>
      _lines.any((l) => l.itemId == itemId);


  /// المتاح لكل صنف من المستودع المختار (D-106 قراءة خالصة — س-108).
  Map<int, int> _stockAvail = {};

  /// س102: خيار حجز المعلّقات وخريطته — بالإعداد المعتمد تُخصم حجوزات
  /// فواتير المندوب المعلّقة من العرض فيرى البائع والمندوب الحقيقة:
  /// المتاح (بعد الحجز) ومحجوز (مطالبات المعلّقات). الغائب صفر ولا
  /// عرض بلا إعداد (سلوك س101 القائم باقٍ مطفأً افتراضاً).
  bool _reserveEnabled = false;
  Map<int, int> _reservedQty = const {};

  List<String>? _errors;
  bool _busy = false;

  /// بوابة التحميل: النموذج لا يُبنى قبل اكتمال القوائم الأولية —
  /// فقيم الحقول الابتدائية (initialValue) جاهزة قبل أول بناء (درس
  /// إبادة DropdownButtonFormField.value في Flutter الجديد: النماذج
  /// القديمة كله بها initialValue وitems_screen نمطها الموثق).
  bool _loaded = false;

  /// س164: جلسة صاحب النموذج — بهويتها يُسجل حدثُ إنشاء المسودة
  /// (فصل الأيدي: مسودة كل يد بيدِها)، والفراغ سقوط آمن بعرف
  /// الرئيسية (السلوك القديم بلا دور).
  SessionInfo? _session;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ معبأ افتراضياً بتاريخ اليوم قابلاً للتعديل
    // — بلفظ المالك «حقل التاريخ في الفواتير أو السندات أو التقارير
    // يملأ افتراضياً بتاريخ اليوم» — ويذهب جذرو درس س-90.
    _date.text = todayIsoDate();
    // س203: معرّف الأصل المعبأ من «مردود من هذه الفاتورة» — للحقل
    // المرئي بالمردود حصراً والغائب فراغ كالقديم حرفاً.
    if (widget.initialOriginalInvoiceId != null) {
      _original.text = '${widget.initialOriginalInvoiceId}';
    }
    // س-120 (D-115): المجاميع وإجمالي السطر تتجدد مع كل ضغطة —
    // مستمعو الحقول يستدعون _touch فتُعاد البطاقات لحظياً.
    _discount.addListener(_touch);
    for (final l in _lines) {
      _listenLine(l);
    }
    _load();
  }

  /// س123: تطبيق بذرة التحويل — يُنادى بعد جاهزية القوائم (_load)
  /// لأن بذر الأسطر يحتاج أصنافها موجودة بالقوائم المحمّلة. النوع
  /// باتجاه الأمر (بيع من بيع وشراء من شراء — لا انعكاس اتجاه)،
  /// والطرف والمستودع والعملة من رأس الأمر، والأسطر بالمتبقي مجمعةً
  /// بالصنف (الصنف بسطرين يصير سطراً واحداً — عرف الوفاء المحسوب)
  /// بالمكافئ الأساسي ووحدة الإدخال للواجهة تختار — لا اقتران مستوى
  /// تعبئة في التحويل الآني (حد الدفعة الموثق س121). والأسعار من
  /// أسعار الأمر المرجعية قيمَ قابلة للتعديل قبل الترحيل بلفظ الدفعة
  /// الموثق، وما موفي صنفٌ كاملاً فلا سطر له بالنموذج (الأمانة:
  /// ما ليس له متبقٍ لا يمر عبر التحويل).
  void _applyConversionSeed() {
    final seed = widget.conversionSeed;
    if (seed == null) return;
    final dir = OrderDirection.fromStorage(seed.order.direction);
    _kind = dir == OrderDirection.sale
        ? InvoiceKind.sale
        : InvoiceKind.purchase;
    _isCash = false;
    // الطرف حاضر بقائمة الأطراف وإلا مسحٌ آمن — فالطرف المعطل بعد
    // تأكيد أمره لا يكسر قائمة النموذج (القيمة خارج القائمة علة
    // Dropdown معروفة).
    final pid = seed.order.partyId;
    _partyId =
        pid != null && _parties.any((p) => p.id == pid) ? pid : null;
    if (seed.order.warehouseId != null) {
      _warehouseId = seed.order.warehouseId;
    }
    _currencyId = seed.order.currencyId;
    final remainingByItem = <int, int>{};
    final priceByItem = <int, int>{};
    for (final l in seed.lines) {
      final rem = seed.remainingQtyBaseOf(l.itemId);
      if (rem <= 0) continue; // الموفي كاملاً لا يُبذر
      remainingByItem[l.itemId] = rem;
      if (!priceByItem.containsKey(l.itemId) && l.unitPriceMinor > 0) {
        priceByItem[l.itemId] = l.unitPriceMinor;
      }
    }
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    final seedItems = remainingByItem.keys
        .where((id) => _items.any((it) => it.id == id))
        .toList();
    for (final itemId in seedItems) {
      final line = _LineUi()
        ..itemId = itemId
        ..unitLevelId = null; // لا اقتران مستوى تعبئة في التحويل الآني
      line.qty.text = groupDigits(remainingByItem[itemId]!);
      final p = priceByItem[itemId] ?? 0;
      if (p > 0) {
        line.price.text = groupDigits(p);
        line.priceSource =
            S.orderReferencePrice(seed.order.number);
      }
      _lines.add(line);
      _listenLine(line);
    }
    if (_lines.isEmpty) {
      // أمر موفى كاملاً فُتحت نافذته — نموذج فارغ عادي والتحويل الحقيقي
      // حرسه الإغلاق (لا فاتورة على متبقٍ صفري).
      final line = _LineUi();
      _lines.add(line);
      _listenLine(line);
    }
  }

  /// م04 منتقي المردود (س205 — الدفعة الثالثة من فحص الواجهات وفق M3
  /// بأمر المالك «تابع في م06 التكيفي ثم بقية الرابعة»): أصل المردود
  /// من سجله لا من معرفه — نافذة مرشحي الأصل (المرحّل بنوعه المطلوب
  /// حصراً: بيع لمردود البيع وشراء لمردود الشراء) وبحثٌ على القائمة
  /// المحمّلة، والاختيار يبذر النموذج ببذرة الأصل بنمط بذرة التحويل
  /// (س123): المعرف والطرف والمستودع والعملة والأسطر بالمتبقي بعد
  /// مردودات المرحّل (حساب المحرك ذاته) وأسعار الأصل قابلة للتعديل.
  /// **والمسار القائم باقٍ حرفاً**: اليدوي خيار ثانٍ (عرف م02)،
  /// وفتح المردود من تفاصيل الأصل (س203) كما هو، وحرس المحرك
  /// (كمية السطر فوق المتبقي) حارسه الحقيقي بعد التعبئة.
  Future<void> _openReturnPicker() async {
    final expectedKind = _kind == InvoiceKind.saleReturn
        ? InvoiceKind.sale
        : InvoiceKind.purchase;
    final candidates = await widget.db
        .invoiceReturnCandidatesOf(expectedKind.storageValue);
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ReturnPickerSheet(
        candidates: candidates,
        searchHint: expectedKind == InvoiceKind.sale
            ? S.searchSalesInvoiceOrCustomer
            : S.searchPurchaseInvoiceOrSupplier,
      ),
    );
    if (picked == null || !mounted) return;
    final seed = await widget.db.invoiceReturnSeedOf(
      originalInvoiceId: picked,
      returnKind: _kind,
    );
    if (!mounted) return;
    if (seed == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            S.returnSeedFailed),
      ));
      return;
    }
    _applyReturnSeed(seed);
  }

  /// بذرة المردود من الأصل المنتقى — النقدية لا تُمسّ (خيار صاحب
  /// النموذج: مردود نقدي يدخل صندوقه وآجل بذمته) والطرف بحاضر
  /// قائمة الأطراف وإلا مسحٌ آمن (علم بذرة التحويل س123).
  void _applyReturnSeed(InvoiceReturnSeed seed) {
    final pid = seed.partyId;
    setState(() {
      _original.text = '${seed.originalId}';
      _partyId =
          pid != null && _parties.any((p) => p.id == pid) ? pid : null;
      if (seed.warehouseId != null) {
        _warehouseId = seed.warehouseId;
      }
      _currencyId = seed.currencyId;
      for (final l in _lines) {
        l.dispose();
      }
      _lines.clear();
      for (final sl in seed.lines) {
        if (!_items.any((it) => it.id == sl.itemId)) continue;
        final line = _LineUi()
          ..itemId = sl.itemId
          ..unitLevelId = null; // الإدخال بالأساسية كما هو بالتحويل
        line.qty.text = groupDigits(sl.remainingQtyBase);
        if (sl.unitPriceMinor > 0) {
          line.price.text = groupDigits(sl.unitPriceMinor);
          line.priceSource = S.originReferencePrice;
        }
        _lines.add(line);
        _listenLine(line);
      }
      if (_lines.isEmpty) {
        // أصله موفى بمردودات المرحّل كله — نموذج فارغ عادي وحرس
        // المحرك ذو الفحص الحي (كمية السطر فوق المتبقي) حارسه.
        final line = _LineUi();
        _lines.add(line);
        _listenLine(line);
      }
    });
    _prefillFxFromLedger(_currencyId);
    _reloadStock();
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
    // س-10 (الدفعة 30): مستويات المجموعات وأسعار الأصناف بها — قراءة
    // واحدة عند الفتح كأخواتها (درس لا Future داخل build).
    final groupLevels =
        await widget.db.select(widget.db.unitGroupLevels).get();
    final levelPrices = await widget.db
        .itemLevelPricesForItems([for (final i in items) i.id]);
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
    // س102: خيار الحجز وخريطته مع القراءات الأولى — من البذرة نفسها
    // فلا Future داخل build (درس القوائم الأولية الموثق أعلاه).
    final reserveOn = await widget.db.heldInvoicesReserveQty();
    final reserved = reserveOn && wid != null
        ? await widget.db.heldSaleReservationsByItem(warehouseId: wid)
        : const <int, int>{};
    // اقتراح «الأكثر تداولاً» (F-146/D-183): من المرحّل بعائلة الجهة
    // خلال آخر 90 يوماً — قراءة لا كتابة والقبول بضغطة.
    final sinceIso = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String()
        .substring(0, 10);
    final usage = await widget.db.partyUsageCounts(
        salesSide: _kind.isSalesSide, sinceIso: sinceIso);
    // س101: الجلسة مع القراءات الأولى — من في الدخول يحدد زرّي الحفظ.
    final session = await loadSession(widget.db);
    // س237 (المرحلة ج — D-235): خيارا سطور الفاتورة مع القراءات
    // الأولى — السطر الحر وملاحظات السطور.
    final freeLineAllowed = await widget.db.invoiceFreeLineAllowed();
    final lineNotesEnabled = await widget.db.invoiceLineNotesEnabled();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _warehouses = warehouses;
      _parties = parties.where((p) => p.isActive).toList();
      _currencies = currencies;
      _items = items.where((i) => i.isActive).toList();
      _unitNames = {for (final u in units) u.id: u.name};
      _groupLevels = groupLevels;
      _levelPrices = levelPrices;
      _levelNameById = {
        for (final l in groupLevels) l.id: l.name,
      };
      _barcodesByItem = barcodes;
      _stockAvail = avail;
      _reserveEnabled = reserveOn;
      _reservedQty = reserved;
      // س237: الخياران مع أخويهما في الحالة.
      _freeLineAllowed = freeLineAllowed;
      _lineNotesEnabled = lineNotesEnabled;
      // الافتراضي المعقول لصاحب المنشأة: أول صندوق وأول مستودع نشط —
      // والمستودع المعين قبل قراءة المتاح (إصلاح س-119/D-114 أعلاه).
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _warehouseId = wid;
      final base =
          _currencies.where((c) => c.isBase).toList();
      _currencyId = base.isEmpty ? 1 : base.first.id;
      _mostActivePartyId = suggestMostActiveParty(usage);
      _session = session;
      _loaded = true;
    });
    // س123: بذرة التحويل بعد جاهزية القوائم — النوع والطرف والمستودع
    // والعملة والأسطر، ثم قراءة المتاح والحجز بالمستودع المبذور (القراءة
    // الأولى كانت بقدر الافتراضي قبل البذرة) ولقطة الصرف بعملته.
    if (widget.conversionSeed != null) {
      setState(() => _applyConversionSeed());
      await _reloadStock();
      await _prefillFxFromLedger(_currencyId);
    }
  }

  /// تحديث خريطة المتاح بعد تبديل المستودع (س-108/D-106) — وس102:
  /// وخريطة الحجز معها فلا يرى المستخدم حجوزات مستودع غريب.
  Future<void> _reloadStock() async {
    final wid = _warehouseId;
    if (wid == null) return;
    final avail = await widget.db.stockQuantitiesByItem(warehouseId: wid);
    final reserveOn = await widget.db.heldInvoicesReserveQty();
    final reserved = reserveOn
        ? await widget.db.heldSaleReservationsByItem(warehouseId: wid)
        : const <int, int>{};
    if (!mounted) return;
    setState(() {
      _stockAvail = avail;
      _reserveEnabled = reserveOn;
      _reservedQty = reserved;
    });
  }

  /// إعادة تحميل آخر الأسعار الفعلية للطرف المختار (F-146/D-183) —
  /// تُستدعى عند تعيين الطرف أو مسحه، وبلا طرف تكون الخريطة فارغة في
  /// يُقترح المرجعي كالعادة. قراءة لا كتابة.
  Future<void> _reloadLastPrices() async {
    final pid = _partyId;
    if (pid == null) {
      if (mounted) setState(() => _lastPrices = {});
      return;
    }
    final prices = await widget.db.lastPricesForParty(
        partyId: pid, salesSide: _kind.isSalesSide);
    if (!mounted) return;
    setState(() => _lastPrices = prices);
  }

  /// اسم الطرف من قائمة الجهة — وسم الاقتراح وحده لا منطق.
  String? _partyName(int? id) {
    if (id == null) return null;
    for (final p in _parties) {
      if (p.id == id) return p.name;
    }
    return null;
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

  /// مستويات مجموعة الصنف — مرشّحو قائمة الوحدة بالسطر (س-10).
  List<UnitGroupLevel> _levelsOfItem(int? itemId) {
    final gid = _itemOf(itemId)?.unitGroupId;
    if (gid == null) return const [];
    return _groupLevels.where((l) => l.groupId == gid).toList();
  }

  /// عامل مستوى التعبئة من الحمولة الأولية — والأساسية 1 (المستويات
  /// لا تُحذف نمط المراجع 03 §6-3 فالغائب فقط بيانات تالفة يعامل
  /// كالأساسية حفاظاً على المسار).
  int _factorOfLevel(int levelId) {
    for (final l in _groupLevels) {
      if (l.id == levelId) return l.factor;
    }
    return 1;
  }

  /// لقطة الصرف: الأساسية لقطتها المحايدة (D-082) وغيرها من الحقل
  /// — والفراغ صفر يلتقطه مدقق البنية برسالته (InvoiceFxRateInvalid).
  int get _fx => _currencyId == 1
      ? baseCurrencyFxRate
      : parseGroupedInt(_fxRate.text.trim());

  /// تعبئة لقطة الصرف من آخر سعر مسجل بالجدول (F-121/D-194) — الجدول
  /// يملأ الافتراض فحسب: الحقل المكتوب يدوياً لا يُمس (D-070 اللقطة
  /// اليدوية باقية) وبلا سجل يبقى الحقل فارغاً ليدخله المالك.
  Future<void> _prefillFxFromLedger(int currencyId) async {
    if (currencyId == 1) return;
    if (_fxRate.text.trim().isNotEmpty) return;
    final rate = await widget.db.latestExchangeRate(currencyId);
    if (!mounted || rate == null) return;
    if (_fxRate.text.trim().isNotEmpty) return;
    setState(() => _fxRate.text = '${rate.rateToBase}');
  }

  int _parsed(TextEditingController c) => parseGroupedInt(c.text.trim());

  /// السعر الافتراضي: آخر سعر فعلي مع الطرف يقدَّم على المرجعي (F-146/
  /// D-183) بلسان س-108/D-107 ذاته: بيع ومردوده ← اتجاه البيع، شراء
  /// ومردوده ← اتجاه الشراء — و«بلا سعر بعد» (الصفر س6) يبقى الحقل
  /// فارغاً لا صفراً. ومصدر الاقتراح يوسم على السطر ليُرى لا يُخفى،
  /// وبعد تعديل الإنسان يبقى رقمه هو رقمه (قبول بشري دائماً).
  void _fillDefaultPrice(_LineUi line) {
    final item = _itemOf(line.itemId);
    if (item == null) return;
    final reference =
        _kind.isSalesSide ? item.salePriceMinor : item.purchasePriceMinor;
    final last = _lastPrices[line.itemId];
    final minor = suggestLinePriceMinor(
        lastActualPriceMinor: last?.priceMinor,
        referencePriceMinor: reference);
    line.price.text = minor > 0 ? groupDigits(minor) : '';
    line.priceSource =
        (last != null && last.priceMinor > 0 && minor == last.priceMinor)
            ? S.lastPriceWithParty(_partyName(_partyId) ?? S.partyLabel, last.docLabel)
            : null;
  }

  /// تعبئة سعر وحدة الاختيار (س-10): من أسعار المستويات المخزنة (لقطة
  /// الدفعة 27 — آلياً مشتقة ويدوياً مكتوبة)، وغيابها اشتقاق لحظي من
  /// الأساسية بعامل المستوى بمحرك المجال ذاته (D-187) — واقتراحٌ
  /// بقبول بشري كالسعر الافتراضي، والتعديل بعده رقم الإنسان هو رقمه
  /// (لقطة السعر في سطر المستند كما هي بلا مساس — D-187).
  void _fillLevelPrice(_LineUi line) {
    final levelId = line.unitLevelId;
    if (levelId == null) {
      _fillDefaultPrice(line);
      return;
    }
    final factor = _factorOfLevel(levelId);
    final stored = _levelPrices[line.itemId]?[levelId];
    final item = _itemOf(line.itemId);
    final baseMinor = _kind.isSalesSide
        ? (item?.salePriceMinor ?? 0)
        : (item?.purchasePriceMinor ?? 0);
    final minor = stored != null
        ? (_kind.isSalesSide ? stored.$1 : stored.$2)
        : derivedLevelPriceMinor(basePriceMinor: baseMinor, factor: factor);
    line.price.text = minor > 0 ? groupDigits(minor) : '';
    line.priceSource = stored != null
        ? S.storedPriceOf(_levelNameById[levelId] ?? S.levelLabel)
        : S.derivedFromBase(factor);
  }

  /// إجمالي السطر الخام — الكمية بوحدة الاختيار × سعرها − خصم السطر
  /// (س-120/D-115 وس-10: السعر لوحدة الاختيار) — وبالأساسية مطابق
  /// القائم، ويُعرض لحظياً في بطاقة البند.
  int _lineGrossMinor(_LineUi line) =>
      _parsed(line.qty) * _parsed(line.price) - _parsed(line.discount);

  /// إضافة بند جديد وتركيز حقل الكمية فيه (س-109/D-110) — الإدخال
  /// بلوحة المفاتيح كاملاً بلا مسك الفأرة عند نهاية كل بند.

  /// س237 (D-235 — المرحلة ج): خانتا سياسات البيع — السطر الحر
  /// وملاحظات السطور (تُقرآن مع قراءات _load الأولى).
  bool _freeLineAllowed = false;
  bool _lineNotesEnabled = false;

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
  /// الافتراضي س-108 سارية في كل المسارات، وتغيير الصنف يعيد الوحدة
  /// للأساسية (س-10: مستوى مجموعةٍ آخر لا يصح على صنفٍ آخر).
  void _setLineItem(_LineUi line, int itemId) {
    setState(() {
      line.itemId = itemId;
      line.unitLevelId = null;
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
              const SnackBar(content: Text(S.barcodeNotLinked)));
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

  /// س225 — إدخال/إخمار صنف من وضع التحديد، وفهرس آخر لمسة يحفظ
  /// لتمديد المجال بShift على ويندوز.
  void _toggleQuickSelect(int itemId, int index) {
    setState(() {
      if (_quickSelected.contains(itemId)) {
        _quickSelected.remove(itemId);
      } else {
        _quickSelected.add(itemId); // ترتيب الاختيار هو ترتيب الصبّ
      }
      _lastSelectIndex = index;
    });
  }

  /// س225 — تمديد التحديد لمجال متتالٍ بShift+نقر (ويندوز).
  void _selectRangeTo(int index, List<Item> suggestions) {
    final last = _lastSelectIndex;
    if (last == null ||
        index < 0 ||
        index >= suggestions.length ||
        last >= suggestions.length) {
      return;
    }
    final lo = last <= index ? last : index;
    final hi = last <= index ? index : last;
    setState(() {
      for (var i = lo; i <= hi; i++) {
        final id = suggestions[i].id;
        if (!_quickSelected.contains(id)) _quickSelected.add(id);
      }
      _lastSelectIndex = index;
    });
  }

  /// س225 — خروج الوضع ومحو التحديد، بلا أثر إذا كان خاملاً.
  void _exitQuickSelect() {
    if (!_quickSelectMode && _quickSelected.isEmpty) return;
    setState(() {
      _quickSelectMode = false;
      _quickSelected.clear();
      _lastSelectIndex = null;
    });
  }

  /// س225 — «تحديد كل النتائج»: اقتراحات المرشّح الحالي كلها (حد
  /// س-132 القائم باقٍ — خمسة أقصى القائمة لا أقل منه).
  void _selectAllQuickSuggestions(List<Item> suggestions) {
    setState(() {
      for (final it in suggestions) {
        if (!_quickSelected.contains(it.id)) _quickSelected.add(it.id);
      }
    });
  }

  /// س225 — صبّ المحدد أسطراً: كل صنف بترتيب اختياره، يملأ أول سطر
  /// فارغ أولاً ثم يضيف الجديد، بكمية 1 وسعره الافتراضي (س-108)،
  /// والتركيز بعد البناء على كمية أول مضاف فتمرّ الكميات بالتوالي —
  /// والخروج من الوضع ومحو خانة البحث بعده بعرف المسار الواحد.
  void _addSelectedToLines() {
    if (_quickSelected.isEmpty) return;
    _LineUi? firstAdded;
    setState(() {
      for (final id in _quickSelected) {
        var target = _firstEmptyLine;
        if (target == null) {
          final line = _LineUi();
          _lines.add(line);
          _listenLine(line);
          target = line;
        }
        target.itemId = id;
        target.unitLevelId = null; // تغيير الصنف يعيد الوحدة للأساسية
        _fillDefaultPrice(target);
        target.qty.text = '1';
        firstAdded ??= target;
      }
      _quickSelectMode = false;
      _quickSelected.clear();
      _lastSelectIndex = null;
    });
    _quickSearch.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // س225 (درس الجولة #457): الإسناد داخل إغلاق setState يقتل
      // الترقية الصفرية للمُلتقَط في الإغلاق المؤجل — فالالتقاط المحلي
      // غير المُسند بعدها هو ما يروّج فلا ولا `!` ولا تردية تحليل.
      final added = firstAdded;
      if (added != null) {
        FocusScope.of(context).requestFocus(added.qtyFocus);
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

  CashBoxReportRow? _boxOf(int? boxId) {
    if (boxId == null) return null;
    for (final b in _boxes) {
      if (b.boxId == boxId) return b;
    }
    return null;
  }

  InvoiceDraft _buildDraft() {
    // س237 (D-235): الأسطر الفارغة المجهزة (لا صنف ولا كمية ولا
    // حر — سطر Enter التالي بعينه) لا تدخل المسودة متى وجد محتوى —
    // فجهيز السطر التالي إعداد واجهة لا بند فاتورة — وبالنموذج
    // الفارغ كله يبقى سطره فيُرفض برسالته المعهودة (س-87 كما كان).
    final hasContent = _lines.any((l) =>
        l.isFree ||
        l.itemId != null ||
        _parsed(l.qty) != 0 ||
        _parsed(l.price) != 0);
    final lines = [
      for (final l in _lines)
        if (!hasContent ||
            l.isFree ||
            l.itemId != null ||
            _parsed(l.qty) != 0 ||
            _parsed(l.price) != 0)
          InvoiceLineDraft(
            // س237: السطر الحر بلا صنف — صفر توكيدياً (المجمعات
            // تجريه والخطة تتخطاه) ووصفه وملاحظته مع السطر.
            itemId: l.isFree ? 0 : (l.itemId ?? 0),
            unitId: l.isFree ? 0 : (_baseUnitIdOf(l.itemId) ?? 0),
            // س-10 (الدفعة 30): بالتعبئة الكمية بوحدة المستوى والأساسية
            // بعاملها واللقطة بالمستوى، وبالأساسية ما اعتاد م1 حرفاً
            // (qty = null فتساوي qtyBase).
            qty: l.unitLevelId == null ? null : _parsed(l.qty),
            unitLevelId: l.unitLevelId,
            qtyBase: _parsed(l.qty) *
                (l.unitLevelId == null
                    ? 1
                    : _factorOfLevel(l.unitLevelId!)),
            unitPriceMinor: _parsed(l.price),
            discountMinor: _parsed(l.discount),
            isFree: l.isFree,
            description: l.isFree ? l.description.text : null,
            note: l.note.text.trim().isEmpty ? null : l.note.text.trim(),
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
      // س123: مرجع أمر التحويل — من البذرة حصراً ففاتورة الأزرار
      // الأربعة والأرشيف حرة كما كانت (الغائب null فلا مساس).
      orderId: widget.conversionSeed?.order.id,
      narration:
          _narration.text.trim().isEmpty ? null : _narration.text.trim(),
      lines: lines,
    );
  }

  // ═══ F-164: تنبيه حد الائتمان — «البائع يرى ويقرر» (رسالة لا منع) ═══

  /// فحص السقف قبل الترحيل — نطاقه الصادق: **بيع آجل** (طرف بلا صندوق)
  /// لطرف له سقف معرف. فالشراء ذمّتُنا على المورد لا ائتمانُ عميل،
  /// والنقدي لا ذمة له، والمسودة لا تولد ذمة أصلاً. الرصيد من تقرير
  /// الذمم ذاته (منبع س-105/D-106 الواحد — لا حساب موازٍ).
  Future<_CreditWarning?> _creditLimitWarning(InvoiceDraft draft) async {
    if (draft.kind != InvoiceKind.sale) return null;
    if (draft.partyId == null || draft.cashBoxId != null) return null;
    Party? party;
    for (final p in _parties) {
      if (p.id == draft.partyId) party = p;
    }
    if (party == null || party.creditLimitBaseMinor == null) return null;
    final rows = await widget.db.receivablesPayablesReport();
    var net = 0;
    for (final r in rows) {
      if (r.partyId == party.id) {
        net = r.direction == PartyBalanceDirection.theyOweUs
            ? r.amountMinor
            : -r.amountMinor;
      }
    }
    // الإجمالي بمحرك المجال النقي ذاته — الرقم المُخزَّن لاحقاً حرفاً
    // (بالخصم الموزع ومكافئ الأساس) لا تقديرٌ موازٍ له.
    final totals = computeInvoiceTotals(draft);
    final excess = creditLimitExcessBaseMinor(
      creditLimitBaseMinor: party.creditLimitBaseMinor,
      netDebitBaseMinor: net,
      invoiceTotalBaseMinor: totals.totalBaseMinor,
    );
    if (excess == null) return null;
    return _CreditWarning(
      partyName: party.name,
      limitMinor: party.creditLimitBaseMinor!,
      netAfterMinor: net + totals.totalBaseMinor,
      excessMinor: excess,
    );
  }

  /// نافذة الرسالة: الأرقام كلها معروضة (الحصيلة والسقف والفائض) —
  /// و«حفظ على أي حال» مفتاحٌ صريح بالقرار، والرجوع يترك النموذج كما هو.
  Future<bool> _confirmCreditLimit(_CreditWarning w) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.creditLimitExceededTitle),
        content: Text(
          S.creditLimitExceededBody(w.partyName, formatMinorAmount(w.netAfterMinor), formatMinorAmount(w.limitMinor), formatMinorAmount(w.excessMinor)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(S.backToEdit),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(S.saveAnyway),
          ),
        ],
      ),
    );
    return proceed == true;
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
    // F-164: تنبيه حد الائتمان عند الترحيل حصراً — المسودة لا تولد ذمة
    // أصلاً، والرسالة لا منع: «البائع يرى ويقرر» (الوجه اللين، س2).
    if (post) {
      final warning = await _creditLimitWarning(draft);
      if (warning != null) {
        if (!mounted) return;
        final proceed = await _confirmCreditLimit(warning);
        if (!proceed) return; // «رجوع للتعديل» — لا كتابة ولا انشغال
      }
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final id = await widget.db.createInvoiceDraft(draft);
      if (post) {
        await widget.db.postInvoice(id);
      } else if (_session != null) {
        // س164: حدث هوية المنشئ على كل مسودة (كانت تقديم المعلقات
        // س101) — تدقيقٌ وبوابةُ فصل الأيدي لا شرطُ حفظ: فشلُه لا
        // يُفشل المسودة المحفوظة أصلاً (المسودة هي المستند)، والترحيل
        // يتحقق بحالة الفاتورة لا بحدثه — والغائب «غير معروف» صادق
        // والبوابة تحكمه.
        try {
          await widget.db.recordInvoiceSubmission(id,
              userId: _session!.user.id,
              userName: _session!.user.name,
              roleName: _session!.role.name);
        } catch (e) {
          await dqLog(widget.db, e, context: 'invoice.submission');
        }
      }
      if (!mounted) return;
      // س119: الترحيل يعيد معرف الفاتورة كي يفتح أمرَ الطباعة بنسختَيه
      // عند المنادي، والمسودة والإرسال للاعتماد يعيدان true كالقائم.
      Navigator.of(context).pop(post ? id : true);
    } on InvoiceValidationException catch (e) {
      await dqLog(widget.db, e, context: 'invoice.save');
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeInvoiceValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.save');
      if (!mounted) return;
      setState(() {
        _errors = ['$e${dqTag(e)}'];
        _busy = false;
      });
    }
  }

  /// س123: عنوان النموذج — المبذّر من أمر يُعرف بعنوانه «فاتورة من
  /// أمر رقمها» فيرى المالك سياقه لا نموذجاً يتما، والحر فاتورة جديدة.
  String get _editTitle => widget.conversionSeed == null
      ? S.newInvoice
      : S.invoiceFromOrder(widget.conversionSeed!.order.number);

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(_editTitle)),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final showFx = _currencyId != 1;
    return Scaffold(
      appBar: AppBar(title: Text(_editTitle)),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          // م06 التكيفي لويندوز (س205): العريض يتوسّط بعرضه الأقصى
          // والضيّق بهامشه الأساسي كما كان حرفاً.
          : ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: diqqahAdaptiveHorizontalMargin(context),
                  vertical: 12),
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
                // النوع من زر الدخول (بلاطة الرئيسية ثم ورقة الأرشيف —
                // س202) فلا انزلاق جهة بعد كتابة الأسطر، وعلة س-113
                // (الطرف القديم بعد تبديل الجهة) زالت بزوال التبديل ذاته،
                // والتعبئة الآلية والترحيل تلتزم نوع الدخول من أول سطر.
                Builder(builder: (laneContext) {
                  final lane = invoiceKindLane(laneContext, _kind);
                  // لافتة النوع بزوقه الدلالي (س186): الأصل معبأ والمردود
                  // مخطط الإطار بلا تعبئة.
                  return Card(
                    color: lane.bg,
                    shape: lane.outlined
                        ? RoundedRectangleBorder(
                            side: BorderSide(color: lane.border))
                        : null,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(invoiceKindIcon(_kind), color: lane.fg),
                      title: Text(_kind.label,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: lane.fg)),
                      subtitle: const Text(
                          S.typeFromEntryButton),
                    ),
                  );
                }),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _date,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                            labelText: S.dateWithFormatHint,
                            suffixIcon:
                                calendarPickerSuffix(context, _date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _due,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                            labelText: S.dueDateOptional,
                            suffixIcon:
                                calendarPickerSuffix(context, _due)),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<bool>(
                  initialValue: _isCash,
                  decoration: const InputDecoration(
                      labelText: S.cashCreditExplainer),
                  items: const [
                    DropdownMenuItem<bool>(value: true, child: Text(S.cashOption)),
                    DropdownMenuItem<bool>(value: false, child: Text(S.creditOption)),
                  ],
                  onChanged: (value) => setState(() => _isCash = value ?? true),
                ),
                if (_isCash) ...[
                  DropdownButtonFormField<int>(
                    initialValue: _boxId,
                    decoration: const InputDecoration(
                        labelText: S.cashBoxLabel),
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
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        S.balanceNow(formatMinorAmount(_boxOf(_boxId)!.balanceBaseMinor), kBaseCurrencySymbol),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ] else ...[
                  // اقتراح «الأكثر تداولاً» (F-146/D-183): رقاقة قبول
                  // بضغطة فوق القائمة — والقائمة تبقى يدوية كاملة،
                  // والاقتراح من المرحّل خلال آخر 90 يوماً لا قرار.
                  if (_partyId == null && _mostActivePartyId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ActionChip(
                          avatar: const Icon(Icons.tips_and_updates_outlined,
                              size: 18),
                          label: Text(
                              S.suggestionMostUsed(_partyName(_mostActivePartyId!) ?? '')),
                          onPressed: () {
                            setState(
                                () => _partyId = _mostActivePartyId);
                            _reloadLastPrices();
                          },
                        ),
                      ),
                    ),
                  DropdownButtonFormField<int>(
                    initialValue: _partyId,
                    decoration: InputDecoration(
                        labelText: _kind.isSalesSide
                            ? S.customerNeedsParty
                            : S.supplierNeedsParty),
                    items: [
                      for (final p in _sideParties)
                        DropdownMenuItem<int>(
                            value: p.id,
                            child: Text('${p.number} ${p.name}')),
                    ],
                    onChanged: (value) {
                      setState(() => _partyId = value);
                      // إعادة تحميل آخر الأسعار للطرف الجديد (F-146).
                      _reloadLastPrices();
                    },
                  ),
                ],
                // م10 نموذج الفاتورة (س205 — الدفعة الثالثة من فحص
                // الواجهات وفق M3): حقول الرأس المزدوجة بنمط التاريخ
                // والاستحقاق القائم (صفاً عمودين) — فالنموذج الطويل
                // المتراكَم رأسياً يُختصر نصفَ ارتفاعه بلا مساس بأي
                // لسان ولا فحص؛ والصف والنقدية بطاقة رأسه كما هي.
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _warehouseId,
                        decoration: const InputDecoration(
                            labelText:
                                S.warehouseForGoods),
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
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _currencyId,
                        decoration: const InputDecoration(
                            labelText: S.documentCurrency),
                        items: [
                          for (final c in _currencies)
                            DropdownMenuItem<int>(
                                value: c.id,
                                child: Text('${c.code} ${c.name}')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _currencyId = value ?? 1;
                          });
                          _prefillFxFromLedger(_currencyId);
                        },
                      ),
                    ),
                  ],
                ),
                // م10 (س205): لقطة الصرف وأصل المردود جنباً إلى جنب
                // حين يحضران معاً — وواحدُهما حاضر فهو بعرضه الكامل.
                Row(
                  children: [
                    if (showFx)
                      Expanded(
                        child: TextField(
                          controller: _fxRate,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            ThousandsSeparatorInputFormatter()
                          ],
                          decoration: const InputDecoration(
                              labelText:
                                  S.exchangeRateScaleHint),
                        ),
                      ),
                    if (showFx && _kind.isReturn)
                      const SizedBox(width: 8),
                    if (_kind.isReturn)
                      Expanded(
                        child: TextField(
                          controller: _original,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          // س206 (تصويب الجولة #404 — علّة س205 الموروثة):
                          // const InputDecoration لا تحتمل نداء توقيع
                          // الحالة _openReturnPicker (invalid_constant
                          // بعمود 42 كشفه المحلل على أول دفع للدفعة) —
                          // فالـconst مرفوع عن التزيين وحده والأيقونة
                          // الثابتة ولسان الزر باقيان بلا مساس بالسلوك.
                          decoration: InputDecoration(
                            labelText:
                                S.originInvoiceIdRequired,
                            // م04 منتقي المردود (س205): زر المنتقي طرفي
                            // الحقل — فتح أصل المردود من سجله لا كتابة
                            // معرفه يدوياً، واليدوي خيار ثانٍ باقٍ حرفاً
                            // (عرف م02: اليدوي خيار ثانٍ).
                            suffixIcon: IconButton(
                              tooltip: S.returnPicker,
                              icon: const Icon(Icons.fact_check_outlined),
                              onPressed: _openReturnPicker,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // س-110 (D-109): خصم الفاتورة في التذييل إلى جانب المجاميع
                // — بلفظ المالك «الخصم في التذييل» — فالقراءة الطبيعية:
                // المجموع ← الخصم ← الصافي، والمدققات كما هي.
                TextField(
                  controller: _narration,
                  decoration: const InputDecoration(
                      labelText: S.descriptionOptional),
                ),
                const SizedBox(height: 12),
                Text(S.linesBaseUnitOnly,
                    style: Theme.of(context).textTheme.titleMedium),
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addLineFocused,
                    icon: const Icon(Icons.add),
                    label: const Text(S.addLine),
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
                        S.quickSearchNameCodeBarcode,
                    helperText: S.fullCodeBluetoothHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: supportsCameraScan
                        ? IconButton(
                            tooltip: S.clearBarcode,
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanFromQuickSearch,
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) =>
                      _applyQuickSearch(fromSubmit: true),
                ),
                // س225 — شريط وضع التحديد المتعدد: يظهر بندخول الوضع
                // حصراً، والعدّاد و«تحديد كل النتائج» و«إلغاء»
                // و«إضافة المحدد» بالعقد الموثق أعلاه.
                if (_quickSelectMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(S.selectedCount(_quickSelected.length),
                            style:
                                Theme.of(context).textTheme.labelLarge),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _selectAllQuickSuggestions(
                              _quickSuggestions(_quickSearch.text)),
                          child: const Text(S.selectAllResults),
                        ),
                        TextButton(
                          onPressed: _exitQuickSelect,
                          child: const Text(S.cancelAction),
                        ),
                        FilledButton.icon(
                          onPressed: _quickSelected.isEmpty
                              ? null
                              : _addSelectedToLines,
                          icon: const Icon(Icons.playlist_add),
                          label: const Text(S.addSelected),
                        ),
                      ],
                    ),
                  ),
                for (final entry in _quickSuggestions(_quickSearch.text)
                    .asMap()
                    .entries)
                  ListTile(
                    dense: true,
                    // س225: بلاطة التحديد تتوهج بدور المخطط (عرف M3).
                    selected: _quickSelectMode &&
                        _quickSelected.contains(entry.value.id),
                    leading: ItemImageBox(
                      imagePath: entry.value.imageThumb,
                      itemName: entry.value.name,
                      size: 36,
                    ),
                    title: Text('${entry.value.sku} ${entry.value.name}'),
                    subtitle: Text(_itemSubtitle(entry.value)),
                    trailing: _quickSelectMode
                        ? Icon(
                            _quickSelected.contains(entry.value.id)
                                ? Icons.check_box_outlined
                                : Icons.check_box_outline_blank,
                            color:
                                Theme.of(context).colorScheme.primary,
                          )
                        : (_itemAlreadyInLines(entry.value.id)
                            ? Text(S.inStockShort,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant))
                            : null),
                    // المسار الواحد القائم حرفاً خارج وضع التحديد وبلا
                    // مماسات — والوضع يدخل باللمس الطويل أو Ctrl.
                    onTap: () {
                      if (_quickSelectMode) {
                        if (HardwareKeyboard.instance.isShiftPressed &&
                            _lastSelectIndex != null) {
                          _selectRangeTo(
                              entry.key,
                              _quickSuggestions(
                                  _quickSearch.text));
                        } else {
                          _toggleQuickSelect(
                              entry.value.id, entry.key);
                        }
                        return;
                      }
                      if (HardwareKeyboard.instance.isControlPressed) {
                        setState(() {
                          _quickSelectMode = true;
                          if (!_quickSelected
                              .contains(entry.value.id)) {
                            _quickSelected.add(entry.value.id);
                          }
                          _lastSelectIndex = entry.key;
                        });
                        return;
                      }
                      var target = _firstEmptyLine;
                      if (target == null) {
                        _addLineFocused();
                        target = _lines.last;
                      }
                      _setLineItem(target, entry.value.id);
                      _quickSearch.clear();
                    },
                    onLongPress: () => _toggleQuickSelect(
                        entry.value.id, entry.key),
                  ),
                TextField(
                  controller: _discount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [const PercentDecimalInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: S.invoiceDiscountPercentHint),
                ),
                _totalsCard(),
                const SizedBox(height: 8),
                // س164: إفصاح المسودة قبل الحفظ — حفظُها لا يمس
                // المخزون والدفتر والذمة حتى تُرحَّل، وترحيلها بيده
                // من التفاصيل أو بيد من مُنح بوابة ترحيل مسودات
                // الآخرين (إظهار الواقع F-016).
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      S.draftExplainer(_reserveEnabled && _kind == InvoiceKind.sale ? S.draftHoldsStockNote : ''),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Row(
                  children: [
                    // س164: زرا الحفظ لكل الأدوار — التعليق ملغى فكل
                    // يد ترحّل ما تحفظه فوراً أو تُرجّئه مسودةً
                    // (فصل الأيدي على المحفوظ: ترحيلُه بيده من
                    // التفاصيل أو بيد البوابة).
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _save(post: true),
                        child: const Text(S.saveAndPost),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _save(post: false),
                        child: const Text(S.saveAsDraft),
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
        minor > 0 ? formatMinorAmount(minor) : S.noPriceYet;
    final priceLabel = _kind.isSalesSide ? S.salePriceLabel : S.purchasePriceLabel;
    final avail = _stockAvail[it.id] ?? 0;
    // التجميعي مخزوني برصيد جاهز (F-034) — فالمتاح عنده «الجاهز»
    // بلفظها، والبضاعة كما هي بحرفها القائم (D-106/س-108).
    final availLabel = it.kind == 'bundle' ? S.availableReady : S.availableLabel;
    // س102: بالإعداد المعتمد وبالبيع حصراً يظهر المحجوز حقيقةً (F-016):
    // «المتاح: 4 (محجوز 6)» — فيعلم البائع لماذا رُفض فوق المتاح،
    // ويعلم المندوب أن فاتورته المعلّقة تحجز فعلاً.
    final rsv = (_reserveEnabled && _kind == InvoiceKind.sale)
        ? (_reservedQty[it.id] ?? 0)
        : 0;
    final availText = rsv > 0
        ? S.availableWithReserved(groupDigits(avail), groupDigits(rsv))
        : groupDigits(avail);
    return it.kind == 'service'
        ? '$priceLabel: $priceText'
        : '$availLabel: $availText · $priceLabel: $priceText';
  }


  /// س237: اقتراحات الصنف الفورية — تطابق الاسم أو الرمز احتواءً،
  /// خمسة أولاً (بترتيب المعرف — الأقدم أسهل الوصول).
  List<Item> _itemSuggestions(_LineUi line) {
    final q = line.itemQuery.text.trim();
    // الفراغ يعرض الخمسة الأوائل — فالاقتراح فوري من أول نظرة
    // (وبضغطة على الرقاقة يثبت الصنف بلا قائمة تفتح).
    if (q.isEmpty) return _items.take(5).toList();
    final ql = q.toLowerCase();
    return _items
        .where((it) =>
            it.name.toLowerCase().contains(ql) ||
            it.sku.toLowerCase().contains(ql))
        .take(5)
        .toList();
  }

  /// س237: Enter يثبت الصنف — أعلى المطابقات، والغائب يفتح النافذة.
  void _onItemQuerySubmitted(int index) {
    final line = _lines[index];
    final s = _itemSuggestions(line);
    if (s.isNotEmpty) {
      _fixItemLine(index, s.first);
    } else {
      _itemNotFoundDialog(index);
    }
  }

  /// س237: تثبيت الصنف — ينتقل للكمية ويجهز سطراً تالياً إن كان
  /// الأخير (D-235: Enter يثبت وينتقل ويجهز).
  void _fixItemLine(int index, Item it) {
    final line = _lines[index];
    setState(() {
      line.itemId = it.id;
      line.unitLevelId = null;
      line.itemQuery.clear();
      _fillDefaultPrice(line);
    });
    if (index == _lines.length - 1) _addLineFocused();
    FocusScope.of(context).requestFocus(line.qtyFocus);
  }

  /// س237: نافذة الصنف غير الموجود — عند البحث الصريح حصراً: إضافة
  /// بطاقة صنف (الاسم معبأ) أو إدراج صنف حر (إن نافذ خيار سياسات
  /// البيع) أو إلغاء (D-235).
  Future<void> _itemNotFoundDialog(int index) async {
    final line = _lines[index];
    final typed = line.itemQuery.text.trim();
    if (typed.isEmpty) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${S.itemNotFoundTitle}: $typed'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('card'),
            child: Text(S.addNewItemCard),
          ),
          if (_freeLineAllowed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('free'),
              child: Text(S.insertFreeLine),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text(S.cancelAction),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return;
    if (choice == 'free') {
      setState(() {
        line.isFree = true;
        line.description.text = typed;
        line.itemId = null;
        line.unitLevelId = null;
        line.itemQuery.clear();
      });
      FocusScope.of(context).requestFocus(line.qtyFocus);
      return;
    }
    await _quickItemCardDialog(index, typed);
  }

  /// س237: بطاقة الصنف السريعة — الاسم معبأ من البحث، والرمز إلزامي،
  /// وسعر البيع اختياري — تصنع الصنف وتثبته في السطر فوراً.
  Future<void> _quickItemCardDialog(int index, String typed) async {
    final sku = TextEditingController();
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.addNewItemCard),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: TextEditingController(text: typed),
              readOnly: true,
              decoration: const InputDecoration(labelText: S.itemNameLabel),
            ),
            TextField(
              controller: sku,
              decoration: const InputDecoration(labelText: S.itemSkuRequired),
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: S.quickItemPriceLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(S.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(S.saveAction),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) {
      sku.dispose();
      price.dispose();
      return;
    }
    final sale = parseGroupedInt(price.text.trim());
    final skuText = sku.text.trim();
    if (skuText.isEmpty) {
      setState(() => _errors = [S.skuRequiredError]);
      return;
    }
    try {
      final firstUnit = (await widget.db.customSelect(
              'SELECT id FROM units WHERE is_deleted = 0 ORDER BY id LIMIT 1')
          .getSingle()).data['id'] as int;
      final id = await widget.db.insertItem(
        sku: skuText,
        name: typed,
        kind: 'good',
        baseUnitId: firstUnit,
        purchasePriceMinor: 0,
        salePriceMinor: sale,
        priceCurrencyId: 1,
      );
      await _load();
      if (!mounted) return;
      _fixItemLine(index, _items.firstWhere((it) => it.id == id));
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.quick_item');
      if (!mounted) return;
      setState(() => _errors = ['$e${dqTag(e)}']);
    } finally {
      sku.dispose();
      price.dispose();
    }
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
            // س237 (D-235 — المرحلة ج/حقل الصنف): الكتابة الفورية
            // داخل السطر بالاسم أو الرمز باقتراحات فورية — وEnter يثبت
            // أعلى المطابقات وينتقل للكمية ويجهز سطراً تالياً، والصريح
            // الغائب يفتح نافذة الصنف غير الموجود (خياراتها الثلاثة) —
            // والبحث السريع متعدد الإدراج والباركود كما هما.
            if (line.isFree)
              TextField(
                controller: line.description,
                decoration: const InputDecoration(
                    labelText: S.freeLineDescriptionLabel,
                    helperText: S.freeLineBadge),
                onSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(line.qtyFocus),
              )
            else if (line.itemId == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // س237: الاقتراحات الفورية فوق الحقل لا تحته — فحقل
                  // الصنف بقاع النموذج تجعل ما تحته خارج الطية (درس
                  // الاختبارات: النقر على ما وراء الطية صمت لا إصابة)،
                  // وفوقه مرئي دائماً بلا تمرير — والخمسة الأوائل مع
                  // الفراغ فالاختيار من أول نظرة.
                  if (_itemSuggestions(line).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final it in _itemSuggestions(line))
                            ActionChip(
                              label: Text(
                                '${it.sku} ${it.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _fixItemLine(index, it),
                            ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: line.itemQuery,
                    decoration: const InputDecoration(
                        // الوسم القائم «الصنف» بعينه — فالتدفق القائم
                        // (نقرة الوسم ثم الاقتراح) يسري كما هو.
                        labelText: S.itemLabel,
                        helperText: S.itemSearchHelper),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _onItemQuerySubmitted(index),
                  ),
                ],
              )
            else
              InputDecorator(
                decoration: InputDecoration(
                  labelText: S.itemLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: S.changeItemTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      line.itemId = null;
                      line.unitLevelId = null;
                      line.itemQuery.clear();
                    }),
                  ),
                ),
                child: Text(
                  '${_itemOf(line.itemId)!.sku} ${_itemOf(line.itemId)!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (line.noteVisible)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextField(
                  controller: line.note,
                  decoration: const InputDecoration(
                      labelText: S.lineNoteLabel, isDense: true),
                ),
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
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                                _itemSubtitle(_itemOf(line.itemId)!),
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                          ),
                          if (unitName.isNotEmpty)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                  line.unitLevelId == null
                                      ? S.unitBase(unitName)
                                      : S.unitWithFactor(_levelNameById[line.unitLevelId] ?? '', _factorOfLevel(line.unitLevelId!)),
                                  style: Theme.of(context).textTheme.bodySmall),
                            ),
                          if (line.unitLevelId != null &&
                              _parsed(line.qty) > 0)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                // س-10 (السير الموثق 06): السعر يُدخل لوحدة
                                // الاختيار مع عرض مكافئ الأساسية — والفرق
                                // الحي بonChanged (درس س79).
                                S.equivalentInBase(groupDigits(_parsed(line.qty) * _factorOfLevel(line.unitLevelId!)), unitName),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              // س-120 (D-115): إجمالي السطر لحظياً — الكمية × السعر
                              // − خصم السطر، ويتجدد مع كل ضغطة (مستمعو الحقول أعلاه).
                              S.lineTotal(formatMinorAmount(_lineGrossMinor(line))),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (line.itemId != null &&
                _levelsOfItem(line.itemId).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: DropdownButtonFormField<int?>(
                  // س-10 (الدفعة 30): قائمة الوحدة — الأساسية ومستوياها،
                  // واختيار المستوى يعبّئ سعره ويظهر المكافئ اللحظي.
                  initialValue: line.unitLevelId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: S.unitLabel),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(
                          S.baseUnitSuffix(_unitNames[_baseUnitIdOf(line.itemId)] ?? S.baseLabel)),
                    ),
                    for (final lv in _levelsOfItem(line.itemId))
                      DropdownMenuItem<int?>(
                        value: lv.id,
                        child: Text('${lv.name} ×${lv.factor}'),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    line.unitLevelId = value;
                    _fillLevelPrice(line);
                  }),
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
                      decoration: InputDecoration(
                        labelText: S.quantityLabel,
                        // س-10: الكمية بوحدة الاختيار حينها — واسمها على
                        // الحقل ليُدخل بها لا بالأساسية.
                        helperText: line.unitLevelId == null
                            ? null
                            : S.inUnit(_levelNameById[line.unitLevelId] ?? ''),
                      ),
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
                      decoration: InputDecoration(
                        labelText: S.unitPriceMinorUnit,
                        // F-146/D-183: وسم مصدر الاقتراح يُرى لا يُخفى،
                        // ويصمت بأول تعديل بشري فالرقم بعده رقمه هو.
                        helperText: line.priceSource,
                        helperMaxLines: 2,
                      ),
                      onChanged: (_) {
                        if (line.priceSource != null) {
                          setState(() => line.priceSource = null);
                        }
                      },
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
                          labelText: S.lineDiscountOptional),
                      onSubmitted: (_) => _addLineFocused(),
                    ),
                  ),
                ),
                // س237 (D-235): ملاحظة السطر — حقل صغير قابل
                // للتوسيع (خيار سياسات البيع).
                if (_lineNotesEnabled)
                  IconButton(
                    tooltip: S.lineNoteLabel,
                    icon: Icon(line.noteVisible
                        ? Icons.sticky_note_2
                        : Icons.sticky_note_2_outlined),
                    onPressed: () => setState(
                        () => line.noteVisible = !line.noteVisible),
                  ),
                IconButton(
                  tooltip: S.deleteLine,
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
  ///
  /// س204 (م01 مرحلته الأولى — عناوين المبالغ ومعاينات «تعادل»):
  /// كل مبلغ بعنوانه الظاهر (عنوان صغير وقيمة كبيرة — نمط M3)،
  /// والإجمالي بأبرز دور مطبعي، والعملة برمزها المعتمد (س50/6)،
  /// والتعادل بالأساسية بغير عملة الأساس حصراً (س-159/D-157) بقيمة
  /// totalBaseMinor المحسوبة بالمجال ذاته لا إعادة حساب في العرض.
  Widget _totalsCard() {
    try {
      final totals = computeInvoiceTotals(_buildDraft());
      final docMatches =
          _currencies.where((c) => c.id == _currencyId).toList();
      final docSymbol =
          docMatches.isEmpty ? '' : currencySymbol(docMatches.first.code);
      final showBase = _currencyId != 1;
      final labelStyle = Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.sumLabel, style: labelStyle),
                        Text(
                          '${formatMinorAmount(totals.subtotalDocMinor)} $docSymbol',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.discountLabel, style: labelStyle),
                        Text(
                          '${formatMinorAmount(totals.discountDocMinor)} $docSymbol',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(S.totalLabel, style: labelStyle),
              Text(
                '${formatMinorAmount(totals.totalDocMinor)} $docSymbol',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (showBase)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    S.equalsInBase(formatMinorAmount(totals.totalBaseMinor), kBaseCurrencySymbol),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
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

  /// س-10 (الدفعة 30): أسماء مستويات التعبئة — الخلاصة «بالواحدة»
  /// بوحدة اللقطة لكل سطر.
  Map<int, String> _levelNameById = {};

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

  /// س164: جلسة الصاحب وصورة آخر تقديم (هوية المنشئ) — فصل الأيدي:
  /// صاحب المسودة يرى زر الترحيل على مسودته، وصاحب البوابة على
  /// مسودات كل الأيدي (إفصاح لا حجب F-016).
  SessionInfo? _session;
  InvoiceSubmissionInfo? _submission;

  bool get _canPostOthers => _session?.canPostOthersInvoices ?? false;
  bool get _isCreator =>
      _session != null &&
      _submission != null &&
      _submission!.userId == _session!.user.id;
  bool get _canPostDraft => _canPostOthers || _isCreator;

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
      // س-10 (الدفعة 30): أسماء المستويات لتجميع أسطر التعبئة بوحدتها.
      final groupLevels =
          await widget.db.select(widget.db.unitGroupLevels).get();
      final suggestions = <int, int>{};
      for (final line in lines) {
        final s = await widget.db
            .latestSupplierPartyIdForItem(line.itemId);
        if (s != null) suggestions[line.itemId] = s;
      }
      // س101: الجلسة وآخر تقديم معلق — زر الاعتماد بلسان دوره، والمانح
      // بلسانه على المسودة.
      final session = await loadSession(widget.db);
      final submission = invoice == null
          ? null
          : await widget.db.invoiceSubmissionOf(widget.invoiceId);
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
        _levelNameById = {for (final l in groupLevels) l.id: l.name};
        _covered = covered;
        _docSuffix = docSymbol.isEmpty ? S.inDocumentCurrency : docSymbol;
        _baseSymbol = currencySymbol(baseCode);
        _session = session;
        _submission = submission;
        _loaded = true;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.detail_load');
      if (!mounted) return;
      setState(() {
        _error = '$e${dqTag(e)}';
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
      await dqLog(widget.db, e, context: 'invoice.deliver');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.deliveryFlagFailed(e))),
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
      await dqLog(widget.db, e, context: 'invoice.deliver_all');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.deliveryFlagFailed(e))),
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
      await dqLog(widget.db, e, context: 'invoice.supplier');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.responsibleSupplierFailed(e))),
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
      await dqLog(widget.db, e, context: 'invoice.print');
      messenger.showSnackBar(
        SnackBar(content: Text(S.printFailed(e, dqTag(e)))),
      );
    }
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final invoice = await widget.db.invoiceById(widget.invoiceId);
      if (invoice == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text(S.noInvoiceWithId)),
        );
        return;
      }
      final bytes =
          await buildInvoicePrintoutBytes(widget.db, widget.invoiceId);
      await sharePdfBytes(bytes, '${invoiceDisplayLabel(invoice)}.pdf');
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.share');
      messenger.showSnackBar(
        SnackBar(content: Text(S.printFailed(e, dqTag(e)))),
      );
    }
  }

  /// س164: الترحيل من التفاصيل — المحرك ذاته، والنجاح يعيد
  /// قراءة الشاشة فيظهر الرقم والحالة المرحّلة.
  Future<void> _approve() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.db.postInvoice(widget.invoiceId);
      messenger.showSnackBar(SnackBar(
        content: Text(S.postedWithNumber((await widget.db.invoiceById(widget.invoiceId))?.number ?? '')),
      ));
      await _load();
      // س119: الترحيل من التفاصيل يفتح أمر الطباعة بنسختَيه أيضاً.
      if (!mounted) return;
      await showInvoicePrintCopiesDialog(
          context, widget.db, widget.invoiceId);
    } on InvoiceValidationException catch (e) {
      await dqLog(widget.db, e, context: 'invoice.post');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(
          S.postRejectedWithReason(
            [for (final err in e.errors) describeInvoiceValidationError(err)]
                .join(' · ')
          , dqTag(e)),
        ),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      await dqLog(widget.db, e, context: 'invoice.post');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(S.postFailed(e, dqTag(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text(S.invoiceDetailsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text(S.invoiceDetailsTitle)),
        body: Center(child: Text(_error!)),
      );
    }
    final invoice = _invoice;
    if (invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(S.invoiceDetailsTitle)),
        body: const Center(child: Text(S.noInvoiceWithId)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text(S.invoiceDetailsTitle)),
      // م06 التكيفي لويندوز (س205): العريض يتوسّط بعرضه الأقصى.
      body: ListView(
        padding: EdgeInsets.symmetric(
            horizontal: diqqahAdaptiveHorizontalMargin(context),
            vertical: 12),
        children: [
          // س-133/D-127: زرا الإخراج ظاهران بنصهما أعلى التفاصيل —
          // هذا ظهور الطباعة الذي طلبته كلمة المالك.
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _print,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text(S.printOrPdf),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text(S.sharePdf),
                ),
              ),
            ],
          ),
          // س203: «مردود من هذه الفاتورة» — لكل أصل مُرحَّل حصراً
          // (المرحّلة وأولادها مدفوعة وجزئية فالأصل المرجع في المحرك
          // مرحَّل — س-05/س-11) ولبيعٍ وشراء أصليين فلا مردوداً على
          // مردود — يفتح النموذج بجهة الأصل ومعرّفه معبّأً حرفاً.
          if (invoice.state != 'draft' &&
              (invoice.kind == 'sale' ||
                  invoice.kind == 'purchase'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () {
                  final returnKind = invoice.kind == 'sale'
                      ? InvoiceKind.saleReturn
                      : InvoiceKind.purchaseReturn;
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => InvoiceEditScreen(
                      db: widget.db,
                      initialKind: returnKind,
                      initialOriginalInvoiceId: invoice.id,
                    ),
                  ));
                },
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text(S.returnFromThisInvoice),
              ),
            ),
          // س164: شريط المسودة فوق التفاصيل — لسان حالة المسودة
          // بهوية منشئها، وزر الترحيل للبوابة أو لصاحب اليد
          // بنفس المحرك.
          if (invoice.state == 'draft')
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _submission == null
                          ? S.draftBanner
                          : S.draftSavedBy(_submission!.userName, _submission!.roleName),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_canPostDraft) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : _approve,
                        icon: const Icon(Icons.task_alt_outlined),
                        label: const Text(S.postAction),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ListTile(
            title: Text(invoiceDisplayLabel(invoice)),
            subtitle: Text(
                S.dateAndPayment(invoice.invoiceDate, invoice.cashBoxId != null ? S.cashLabel : S.onAccountLabel, invoice.state == 'draft' ? S.draftSuffix : '')),
          ),
          ListTile(
            title: Text(S.totalWithAmount(formatMinorAmount(invoice.totalDocMinor), _docSuffix)),
            subtitle: Text(
                S.paidAndRemaining(invoice.currencyId != 1 ? S.equivalentTrailing(_baseSymbol, formatMinorAmount(invoice.totalBaseMinor)) : '', formatMinorAmount(_covered), formatMinorAmount(invoice.totalDocMinor - _covered))),
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
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _deliverAll,
                  icon: const Icon(Icons.done_all_outlined),
                  label: const Text(S.deliverAll),
                ),
              ),
            ),
          const Divider(),
          for (final line in _lines) _lineTile(line),
          if (_lines.isEmpty) const ListTile(title: Text(S.noLines)),
        ],
      ),
    );
  }

  /// س-10 (الدفعة 30): وحدة سطر الفاتورة بلقطته — مستوى التعبئة عند
  /// الإدخال بها والأساسية وإلا، فتتجمع الكميات بوحدة كل سطر لا
  /// بالأساسية كلها (نمط D-138 «بالواحدة» على لقطة السطر).
  String _lineUnitLabel(InvoiceLineDocument l) => l.unitLevelId == null
      ? (_unitNames[l.unitId] ?? '')
      : (_levelNameById[l.unitLevelId] ?? '');

  /// س-148/D-138: عدّاد التسليم وقائمة التبديل في نفس السطر —
  /// النص بأساس العد المختار والقائمة بخيارَيها (الكميات/الأسطر).
  Widget _deliveryCounterRow() {
    final deliveredQty = quantitiesByUnit([
      for (final l in _lines)
        if (l.delivered) (l.qty, _lineUnitLabel(l)),
    ]);
    final totalQty = quantitiesByUnit(
        [for (final l in _lines) (l.qty, _lineUnitLabel(l))]);
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
        // س198 (م15 من تقرير فحص الواجهات وفق M3): كان المنسدل عارياً
        // بلا عنوان ولا تسمية وصولية فيقرأه قارئ الشاشة قيمةً بلا اسم
        // — فصار DropdownButtonFormField بعنوان «أساس العد» الدائم
        // بعرض محدود لا يزيح نص العدّاد (نمط حقول النموذج ذاتها).
        // والعرض 232 وعلامة isExpanded درس الجولة #376: بـ190 فيض
        // أفقي 14 بكسلاً بقيمة «حسب الكميات» وأيقونتها (نمط درس
        // س-108 RenderFlex)، وisExpanded يقص القيمة الطويلة لا فيض.
        SizedBox(
          width: 232,
          child: DropdownButtonFormField<DeliveryBasis>(
            initialValue: _deliveryBasis,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: S.countingBasis),
            items: [
              for (final b in deliveryBasisChoices)
                DropdownMenuItem(
                    value: b, child: Text(S.byBasis(deliveryBasisLabel(b)))),
            ],
            onChanged: (b) {
              if (b != null) setState(() => _deliveryBasis = b);
            },
          ),
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
    final itemName = item?.name ?? S.itemWithNumber(line.itemId);
    final title =
        '$itemName — ${line.qty} × ${formatMinorAmount(line.unitPriceMinor)}';
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
                  S.amountWith(formatMinorAmount(line.lineTotalDocMinor))),
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
              alignment: AlignmentDirectional.centerStart,
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
                  labelText: S.responsibleSupplier,
                  border: InputBorder.none,
                ),
                items: [
                  const DropdownMenuItem<int>(
                      value: null, child: Text(S.noSupplier)),
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
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        S.suggestedLastPurchase(p.name),
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
