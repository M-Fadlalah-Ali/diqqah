/// محرك الطباعة والتصدير (D-016، دفعة إغلاق النواة س37 — محدث بدفعة 8 س39).
///
/// الطباعة وعدٌ معتمد قديم بقي في النواة (09 §2 حرفاً): «PDF وطباعة
/// بمقاسي A4/A5 (طولي/عرضي) لكل مستندات المرحلة وتقاريرها بتحويل
/// تلقائي للتخطيط بين القياسين وافتراضيات قياس لكل نوع مستند، ومشاركة
/// الملف عبر أدوات النظام».
///
/// البناء هنا نقي حصراً: الدوال تستلم بيانات جاهزة (سلاسل وأرقاماً
/// موسومة) وتعيد بايتات PDF — يختبرها flutter_test بلا قنوات منصة،
/// والأفعال (المشاركة/الطباعة) منفصلة أدناه بتعليقها للاختبار.
///
/// D-101: افتراضيات القياس لكل نوع — الفواتير والسندات A5 طولياً
/// (قسيمة كاونتر)، والتقارير A4 عرضياً (جداول أعمدة) — مع تجاوز
/// صريح بالمعاملين حيث يختار المالك غير الافتراضي.
///
/// D-103 (دفعة 8 س39) — مبدأ النسب المئوية بلفظ المالك: «في موضوع
/// تصميم الفاتورة أرى أن نعتمد مبدأ النسب المئوية لا القياسات
/// والأبعاد المحددة، فلو تغير قياس الورق تبقى النسب ثابتة» — فكل
/// قياسات التخطيط مشتقة من عرض الصفحة وارتفاعها لا قيم مطلقة، والأحجام
/// النصية نسب الارتفاع بسقف قراءة (لا يتلاشى الحرف ولا يتضخم) —
/// الافتراضيات (A5/A4) لا تتغير، والافتراضيات ثابتة الآن وتخصيص
/// الفاتورة بالنسب بيد المستخدم مؤجل (قائمة الانتظار 09 §8).
///
/// D-104 (دفعة 8 س39) — الخط: ساحل افتراضياً للطباعة (ومع العرض
/// خيار واحد) وتجوال خيار آخر، من مكتبة مدمجة حصراً — لا خطوط جهاز
/// ولا تحميل خارجي — بلفظ المالك وأميري خرج من الخيارات فحُذفت
/// أصوله. رخصتا MIT/OFL مرفقتان مع الأصول.
library;

import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'ui_fonts.dart';

/// الخطوط المحملة لكل مفتاح خيار — تحميل مرة واحدة المخزّنة كي لا
/// تُقرأ الأصول كل طباعة.
final Map<String, (pw.Font, pw.Font)> _fontCache = {};

/// بايتات أصول العلامة (شعار الترويسة والخاتمة) — تحميل مرة واحدة
/// والغائب null مخزّناً فلا محاولة كل طباعة.
final Map<String, Uint8List?> _brandCache = {};

/// شعار العلامة صورة لا نص (س50/3 بلفظ المالك «ألا يوجد علاج؟» —
/// س-157/D-155): علة التشوه أن خط ساحل المدمج بتمثيل مكتبة pdf
/// يرسم الحركات (الكسرة والشدّة في «دِقّة») في غير موضعها، والشاشة
/// بمحرك تشكيل كامل فسليمة — فالعلاج الجذري: الاسم يُرسم مرة واحدة
/// بمحرك تشكيل كامل ويدخل الورقة صورة عالية الوضوح فحروفه وحركاته
/// ثابتة لا تفسّر ولا تُرسم عند كل طباعة، بساحل التطبيق نفسه. الغائب
/// (أصل فاسد مثلاً) يعود للسطر النصي بلا حركات كي لا تُكسر الطباعة.
Future<Uint8List?> brandAsset(String key) async {
  if (_brandCache.containsKey(key)) return _brandCache[key];
  Uint8List? bytes;
  try {
    final data = await rootBundle.load('assets/brand/$key.png');
    bytes = data.buffer.asUint8List();
  } catch (_) {
    bytes = null; // فاسد لا يكسر الطباعة أبداً — النص البديل مكانه
  }
  _brandCache[key] = bytes;
  return bytes;
}

/// تحميل زوج الخط (عادي، عريض) لمفتاح الخيار — مدمج حصراً من الأصول،
/// وأي مفتاح غريب يعيد ساحل (نمط القراءة الافتراضية الموثق).
Future<(pw.Font, pw.Font)> _fontsFor(String fontKey) async {
  final cached = _fontCache[fontKey];
  if (cached != null) return cached;
  final family = appFontFamily(fontKey);
  final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/$family-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/$family-Bold.ttf'));
  final pair = (regular, bold);
  _fontCache[fontKey] = pair;
  return pair;
}

/// خط الطباعة بالخيار الحي من الإعدادات — الشاشات تمرره من المُنبِّه،
/// والافتراضي ساحل.
String get activeFontKey => appFontChoice.value;

/// افتراضيات القياس لكل نوع مستند (D-101 معروض) — والمفاتيح بأسماء
/// الأنواع المعروفة: فواتير وسندات A5 طولي، تقارير A4 عرضي.
PdfPageFormat defaultPageFormatFor(String docKind) {
  switch (docKind) {
    case 'invoice':
    case 'voucher':
      return PdfPageFormat.a5; // طولي
    default: // تقارير
      return PdfPageFormat.a4.copyWith(
          width: PdfPageFormat.a4.height, height: PdfPageFormat.a4.width);
  }
}

/// تجاوز القياس صراحة — «a4»/«a5» مع اتجاه اختياري، وأي قيمة غريبة
/// تعيد الافتراضي للنوع (لا استثناء في قراءة عرضية).
PdfPageFormat resolvePageFormat({
  required String docKind,
  String? sizeOverride,
  bool? landscapeOverride,
}) {
  final base = defaultPageFormatFor(docKind);
  PdfPageFormat format;
  switch (sizeOverride) {
    case 'a4':
      format = PdfPageFormat.a4;
      break;
    case 'a5':
      format = PdfPageFormat.a5;
      break;
    default:
      format = base;
  }
  final landscape = landscapeOverride ?? base.width > base.height;
  if (landscape && format.width < format.height) {
    format = format.copyWith(width: format.height, height: format.width);
  } else if (!landscape && format.width > format.height) {
    format = format.copyWith(width: format.height, height: format.width);
  }
  return format;
}

/// قياسات التخطيط النسبية (D-103) — كل قيمة دالة في مقاس الصفحة:
/// الهوامش والحواشي من العرض، والأحجام النصية من الارتفاع بسقف قراءة
/// (min/max) كي تبقى النسبة ثابتة على أي ورق والحرف مقروءاً دائماً.
class _PdfMetrics {
  final double margin;
  final double labelWidth;
  final double boxPadding;
  final double boxGap;
  final double titleSize;
  final double brandSize;
  final double headerTextSize;
  final double tableHeaderSize;
  final double tableCellSize;
  final double footerStampSize;
  final double smallGap;

  const _PdfMetrics._({
    required this.margin,
    required this.labelWidth,
    required this.boxPadding,
    required this.boxGap,
    required this.titleSize,
    required this.brandSize,
    required this.headerTextSize,
    required this.tableHeaderSize,
    required this.tableCellSize,
    required this.footerStampSize,
    required this.smallGap,
  });

  factory _PdfMetrics.fromPage(PdfPageFormat f) {
    double clampAbs(double v, double min, double max) =>
        v < min ? min : (v > max ? max : v);
    return _PdfMetrics._(
      margin: clampAbs(f.width * 0.05, 14, 40),
      labelWidth: f.width * 0.22,
      boxPadding: clampAbs(f.width * 0.022, 5, 12),
      boxGap: clampAbs(f.height * 0.014, 6, 16),
      titleSize: clampAbs(f.height * 0.026, 12, 20),
      brandSize: clampAbs(f.height * 0.013, 7, 10),
      headerTextSize: clampAbs(f.height * 0.017, 8, 11),
      tableHeaderSize: clampAbs(f.height * 0.015, 7, 10),
      tableCellSize: clampAbs(f.height * 0.015, 7, 10),
      footerStampSize: clampAbs(f.height * 0.011, 6, 8),
      smallGap: clampAbs(f.height * 0.006, 3, 8),
    );
  }
}

/// قلب ترتيب أعمدة الجدول إلى العربية (س-134، D-128 — دفعة 11) —
/// الدالة النقية الوحيدة التي يمرر بها البنّاءان كل جدول: علة المالك
/// «التقارير تصدر بدون مراعاة الاتجاه العربي في الأعمدة» جذرها أن
/// بنّاء الجداول بمكتبة pdf يبني الأعمدة يساراً←يميناً رغم كون النص
/// عربياً والاتجاه rtl حوله — فالعلاج بنقطة واحدة هنا: قلب القائمة
/// قبل البناء فيصير العمود الأول (الحساب/الصنف/الطرف) أقصى اليمين
/// ثم المدين ثم الدائن ثم الرصيد بلفظه الحرفي — ويخرج منه كل مطبوعات
/// البرنامج (الفواتير والسندات والتقارير الست) بلا مساس بأي نداء.
List<String> rtlColumnOrder(List<String> columns) =>
    columns.reversed.toList(growable: false);

/// قلب خلايا كل صف بنفس الدالة العلوية — تركيب الأعمدة المقلوبة.
List<List<String>> rtlRowOrder(List<List<String>> rows) => [
      for (final row in rows) row.reversed.toList(growable: false),
    ];

/// صف ترويسة أو خلاصة — سطر «تسمية: قيمة» بمساحة تسمية نسبية.
List<pw.Widget> _pairLines(
  List<(String, String)> pairs,
  pw.Font regular,
  pw.Font bold,
  double fontSize,
  double labelWidth,
) => [
      for (final (label, value) in pairs)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: labelWidth,
                child: pw.Text('$label:',
                    style: pw.TextStyle(font: bold, fontSize: fontSize)),
              ),
              pw.Expanded(
                child: pw.Text(value,
                    style: pw.TextStyle(font: regular, fontSize: fontSize)),
              ),
            ],
          ),
        ),
    ];

/// البنّاء العام الموحد لكل مستندات المرحلة وتقاريرها — عنوان ومجموعة
/// أزواج ترويسة (تسمية: قيمة) وجدول أعمدة وأسطر وسطور خلاصة، كله RTL
/// بخط المكتبة المدمجة المختار، والتخطيط كله بنسب الصفحة (D-103)،
/// والأعمدة الرقمية تمتد يساراً لا تُقطع.
Future<Uint8List> buildDocumentPdf({
  required String title,
  required List<(String, String)> headerPairs,
  required List<String> columns,
  required List<List<String>> rows,
  required List<(String, String)> footerPairs,
  required PdfPageFormat format,
  String? fontKey,

  /// س-127/س-128 (دفعة 10، D-123): صور بنود الصف الأول — يُمرر غير null
  /// حصراً حين مفتاح نوع المستند مفعّل من الإعدادات (الافتراضي معطل
  /// في كل المستندات بلفظ المالك). العمود مربع قبل اسم الصنف بنمط
  /// النسب (D-103)، والاحتواء لا القص (D-121)، وبلا صورة يعرض النائب
  /// البصري بأول حرف (س-125/D-122).
  List<Uint8List?>? rowLeadingImages,

  /// أول حرف اسم الصنف لكل صف — حرف النائب البصري بالحالات بلا صورة.
  List<String>? rowPlaceholderLetters,

  /// س-140 (D-134 — دفعة 12): سطر خلاصة تحت الجدول مباشرة — عمود
  /// «مستلم» بقسيمة البيع يلخصه «مستلم X من Y» توضيحاً للزبون لا
  /// يغيّر أرقاماً. null في المطبوعات الأخرى فلا شيء يظهر.
  String? summaryText,
  /// س50/8 (س-160/D-158): سطر التفقيط المستقل بلا تسمية — عرف الشيكات
  /// وفواتير البرمجيات العربية: «فقط ... لا غير» يقف وحده لا يسبقه
  /// لفظ «بالكلمات» يضاعف الكلام. null في المطبوعات الأخرى فلا شيء.
  String? standoutLine,
}) async {
  final key = fontKey ?? activeFontKey;
  final (regular, bold) = await _fontsFor(key);
  final m = _PdfMetrics.fromPage(format);
  final headerBrand = await brandAsset('wordmark-header');
  final footerBrand = await brandAsset('wordmark-footer');

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.all(m.margin),
      build: (context) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: bold, fontSize: m.titleSize)),
            pw.SizedBox(height: m.smallGap),
            if (headerBrand != null)
              pw.Center(
                child: pw.Image(pw.MemoryImage(headerBrand),
                    height: m.brandSize * 2.6),
              )
            else
              pw.Text('دِقَّة — نظام المحاسبة العربي',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: regular, fontSize: m.brandSize)),
            pw.SizedBox(height: m.boxGap),
            if (headerPairs.isNotEmpty) ...[
              pw.Container(
                padding: pw.EdgeInsets.all(m.boxPadding),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: _pairLines(
                        headerPairs, regular, bold, m.headerTextSize, m.labelWidth)),
              ),
              pw.SizedBox(height: m.boxGap),
            ],
            if (rows.isEmpty)
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(vertical: m.boxGap),
                child: pw.Text('لا أسطر',
                    textAlign: pw.TextAlign.center,
                    style:
                        pw.TextStyle(font: regular, fontSize: m.headerTextSize)),
              )
            else if (rowLeadingImages != null)
              _imageTable(
                columns: columns,
                rows: rows,
                images: rowLeadingImages,
                letters: rowPlaceholderLetters,
                regular: regular,
                bold: bold,
                imageColWidth: m.tableCellSize * 4.2,
                headerSize: m.tableHeaderSize,
                cellSize: m.tableCellSize,
              )
            else
              pw.TableHelper.fromTextArray(
                // س-134/D-128: القلب هنا نقطة الإصلاح الوحيدة — أعمدة
                // الجدول النصي تمرر مقلوبة فيصير الأول أقصى اليمين.
                headers: rtlColumnOrder(columns),
                data: rtlRowOrder(rows),
                border: pw.TableBorder.all(color: PdfColors.grey400),
                headerStyle: pw.TextStyle(
                    font: bold, fontSize: m.tableHeaderSize),
                cellStyle: pw.TextStyle(
                    font: regular, fontSize: m.tableCellSize),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignment: pw.Alignment.centerRight,
                oddRowDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey50),
              ),
            // س-140/D-134: سطر خلاصة «مستلم X من Y» تحت الجدول مباشرة
            // — عرضٌ توضيحي للزبون لا رقم محاسبي.
            if (summaryText != null && summaryText.isNotEmpty) ...[
              pw.Padding(
                padding: pw.EdgeInsets.only(top: m.smallGap),
                child: pw.Text(summaryText,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        font: bold, fontSize: m.tableCellSize)),
              ),
              pw.SizedBox(height: m.boxGap),
            ],
            pw.SizedBox(height: m.boxGap),
            if (footerPairs.isNotEmpty)
              pw.Container(
                padding: pw.EdgeInsets.all(m.boxPadding),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: _pairLines(
                      footerPairs, regular, bold, m.headerTextSize, m.labelWidth),
                ),
              ),
            if (standoutLine != null && standoutLine.isNotEmpty) ...[
              pw.SizedBox(height: m.smallGap),
              pw.Text(standoutLine,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: bold, fontSize: m.headerTextSize)),
            ],
            pw.Spacer(),
            if (footerBrand != null)
              pw.Center(
                // الأصل نفسه مرسوم بدرج الرمادي عند توليده — فلا
                // فلتر ألوان على الصورة ولا اعتماد على مزايا المكتبة.
                child: pw.Image(pw.MemoryImage(footerBrand),
                    height: m.footerStampSize * 2.6),
              )
            else
              pw.Text('طُبع من دقة',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: regular,
                      fontSize: m.footerStampSize,
                      color: PdfColors.grey600)),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

/// جدول الطباعة بعمود الصورة (س-127/س-128، دفعة 10) — العمود مربع
/// بعرض نسبي من قياس الصفحة (D-103)، والصورة فيه بالاحتواء لا
/// القص (D-121)، وبلا صورة دائرة النائب بأول حرف (س-125/D-122).
/// ارتفاع الصف ثابت بعرض العمود فلا يتفاضل الجدول (س-127).
/// س-134/D-128 (دفعة 11): عمود الصورة أقصى **اليمين** بقلب التركيب
/// ذاته — الأعمدة النصية تمرر مقلوبة الدالة النقية وخلية الصورة
/// تُلحق آخراً فيركب الصف من اليمين: [الأعمدة المقلوبة…، الصورة].
pw.Widget _imageTable({
  required List<String> columns,
  required List<List<String>> rows,
  required List<Uint8List?>? images,
  required List<String>? letters,
  required pw.Font regular,
  required pw.Font bold,
  required double imageColWidth,
  required double headerSize,
  required double cellSize,
}) {
  pw.Widget imageCell(int index) {
    final side = imageColWidth - 6;
    final bytes = images != null && index < images.length
        ? images[index]
        : null;
    if (bytes != null && bytes.isNotEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Center(
          child: pw.SizedBox(
            width: side,
            height: side,
            child: pw.Image(
              pw.MemoryImage(bytes),
              fit: pw.BoxFit.contain, // D-121: احتواء لا قص ولا تمدد
            ),
          ),
        ),
      );
    }
    final letter = letters != null && index < letters.length
        ? letters[index]
        : '؟';
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Center(
        child: pw.Container(
          width: side,
          height: side,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey200,
            shape: pw.BoxShape.circle,
          ),
          child: pw.Text(
            letter.isEmpty ? '؟' : letter.characters.first,
            style: pw.TextStyle(
              font: bold,
              fontSize: cellSize * 1.3,
              color: PdfColors.grey700,
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget textCell(String text, {required bool header}) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            font: header ? bold : regular,
            fontSize: header ? headerSize : cellSize,
          ),
        ),
      );

  // س-134/D-128: الأعمدة النصية مقلوبة والصورة آخر خلية (أقصى اليمين)
  // — وعرض العمود الثابت يُفهرس بموضعه الجديد آخر الجدول.
  final orderedColumns = rtlColumnOrder(columns);
  final orderedRows = rtlRowOrder(rows);
  final imageColIndex = orderedColumns.length; // آخر عمود = أقصى اليمين
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400),
    columnWidths: {imageColIndex: pw.FixedColumnWidth(imageColWidth)},
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (final c in orderedColumns) textCell(c, header: true),
          textCell('الصورة', header: true),
        ],
      ),
      for (var i = 0; i < orderedRows.length; i++)
        pw.TableRow(
          decoration: i.isOdd
              ? const pw.BoxDecoration(color: PdfColors.grey50)
              : null,
          children: [
            for (final cell in orderedRows[i]) textCell(cell, header: false),
            imageCell(i),
          ],
        ),
    ],
  );
}

/// تعقيم اسم ملف المشاركة (س-154/D-152 — دفعة 16، علّة المالك الحية
/// 2026-11-02): تسمية العرض المعتمدة للفواتير والسندات (م-44/D-071)
/// تحمل المائل `/` بين السنة والرقم — «فاتورة بيع 2026/000003» —
/// والنظام الملفي في كل المنصات يفسره فاصل مجلد فيتولد مسار
/// «cache/فاتورة بيع 2026/000003.pdf» بمجلد لا وجود له فتقعد
/// PathNotFoundException (errno = 2) وتُمنع مشاركة طباعة فاتورة
/// المالك كما بلغ بصورته. العلاج بنقطة واحدة كما عادة الدوال النقية
/// (نمط rtlColumnOrder): كل اسم ملف مشاركة يمر من هنا قبل كتابته —
/// محارف المسار المحجوزة في المنصات الثلاث `\ / : * ? " < > |`
/// ومحارف التحكم تصير شرطة، والمتواليات تنقل لشرطة واحدة، وأطراف
/// النقطة والشرطة والفراغ تنظف (فلا ملف مخفي بنقطة أولى ولا اسم
/// ينتهي بشرطة)، والخالي يعود «مستند». تسمية العرض على الشاشات
/// وداخل الورقة المطبوعة كما هي بلا مساس — العلة في حدّ الملف
/// لا في الصيغة المعتمدة.
String safeFileName(String name) {
  var out = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .trim();
  out = out
      .replaceAll(RegExp(r'^[.\-]+'), '')
      .replaceAll(RegExp(r'[.\s\-]+$'), '');
  return out.isEmpty ? 'مستند' : out;
}

/// مشاركة ملف PDF بنافذة النظام (نمط D-056 المعتمد للنسخ الاحتياطية:
/// إخراج الملف من مجلد التطبيق إلى مكان يختاره المالك) — يُكتب ملف
/// مؤقت بمجلد التخزين المؤقت ويُشارك باسمه، والاسم يعقَّم بـ
/// safeFileName حصراً قبل الكتابة (س-154/D-152) فلا مائل تسمية
/// العرض ولا محرف مسار يمرر للنظام الملفي.
Future<void> sharePdfBytes(
  Uint8List bytes,
  String fileName,
) async {
  final dir = await getTemporaryDirectory();
  final safeName = safeFileName(fileName);
  final file = File(p.join(dir.path, safeName));
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/pdf')],
    subject: safeName,
    text: 'مستند من دِقَّة',
  );
}

/// مشاركة ملف CSV بنافذة النظام (F-166 — الدفعة 20) — نفس مسار PDF
/// المعتمد: ملف مؤقت بمجلد التخزين المؤقت واعتمام الاسم بـsafeFileName
/// حصراً قبل الكتابة (س-154/D-152)، والنوع text/csv. النص الوارد يحمل
/// BOM ضمنه (من buildCsvSnapshot) فتُكتب البايتات بعربي سليم في Excel.
Future<void> shareCsvBytes(
  String csv,
  String fileName,
) async {
  final dir = await getTemporaryDirectory();
  final safeName = safeFileName(fileName);
  final file = File(p.join(dir.path, safeName));
  await file.writeAsString(csv, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv')],
    subject: safeName,
    text: 'مستند من دِقَّة',
  );
}

/// الطباعة المباشرة بحوار الطباعة — حيثما لا تدعم المنصة تُغلف بلطف
/// برسالة عربية (D-101 معروض: التصدير والمشاركة أولًا على كل منصة،
/// والطباعة المباشرة ميزة المنصة الداعمة).
Future<void> printPdfBytes(
  BuildContext context,
  Uint8List bytes,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('الطباعة المباشرة غير مدعومة على هذه المنصة — '
          'استخدم «مشاركة PDF» لحفظه أو إرساله — $e'),
    ));
  }
}
