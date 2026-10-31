/// محرك الطباعة والتصدير (D-016، دفعة إغلاق النواة س37).
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
/// D-101 معروض: افتراضيات القياس لكل نوع — الفواتير والسندات A5
/// طولياً (قسيمة كاونتر)، والتقارير A4 عرضياً (جداول أعمدة) — مع
/// تجاوز صريح بالمعاملين حيث يختار المالك غير الافتراضي.
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

/// خط الطباعة العربي المضمّن — أميري (رخصة OFL) يحمل التشكيل العربي
/// الكامل، والتحميل مرة واحدة المخزّنة كي لا تُقرأ الأصول كل طباعة.
pw.Font? _amiriRegular;
pw.Font? _amiriBold;

Future<void> _ensureFonts() async {
  if (_amiriRegular != null) return;
  final regular =
      await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
  _amiriRegular = pw.Font.ttf(regular);
  _amiriBold = pw.Font.ttf(bold);
}

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

/// البنّاء العام الموحد لكل مستندات المرحلة وتقاريرها — عنوان ومجموعة
/// أزواج ترويسة (تسمية: قيمة) وجدول أعمدة وأسطر وسطور خلاصة، كله RTL
/// بخط أميري المضمّن، والأعمدة الرقمية تمتد يساراً لا تُقطع.
Future<Uint8List> buildDocumentPdf({
  required String title,
  required List<(String, String)> headerPairs,
  required List<String> columns,
  required List<List<String>> rows,
  required List<(String, String)> footerPairs,
  required PdfPageFormat format,
}) async {
  await _ensureFonts();
  final regular = _amiriRegular!;
  final bold = _amiriBold!;

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  final headerWidgets = <pw.Widget>[
    for (final (label, value) in headerPairs)
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text('$label:',
                  style: pw.TextStyle(font: bold, fontSize: 10)),
            ),
            pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(font: regular, fontSize: 10)),
            ),
          ],
        ),
      ),
  ];

  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: bold, fontSize: 15)),
            pw.SizedBox(height: 4),
            pw.Text('دِقَّة — نظام المحاسبة لمحلك',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: regular, fontSize: 8)),
            pw.SizedBox(height: 10),
            if (headerPairs.isNotEmpty) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: headerWidgets),
              ),
              pw.SizedBox(height: 10),
            ],
            if (rows.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 12),
                child: pw.Text('لا أسطر',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: regular, fontSize: 10)),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: columns,
                data: rows,
                border: pw.TableBorder.all(color: PdfColors.grey400),
                headerStyle: pw.TextStyle(font: bold, fontSize: 9),
                cellStyle: pw.TextStyle(font: regular, fontSize: 9),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignment: pw.Alignment.centerRight,
                oddRowDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey50),
              ),
            pw.SizedBox(height: 12),
            if (footerPairs.isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final (label, value) in footerPairs)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                        child: pw.Row(
                          children: [
                            pw.SizedBox(
                              width: 110,
                              child: pw.Text('$label:',
                                  style:
                                      pw.TextStyle(font: bold, fontSize: 10)),
                            ),
                            pw.Expanded(
                              child: pw.Text(value,
                                  style:
                                      pw.TextStyle(font: regular, fontSize: 10)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            pw.Spacer(),
            pw.Text('طُبع من دِقَّة',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    font: regular, fontSize: 7, color: PdfColors.grey600)),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

/// مشاركة ملف PDF بنافذة النظام (نمط D-056 المعتمد للنسخ الاحتياطية:
/// إخراج الملف من مجلد التطبيق إلى مكان يختاره المالك) — يُكتب ملف
/// مؤقت بمجلد التخزين المؤقت ويُشارك باسمه.
Future<void> sharePdfBytes(
  Uint8List bytes,
  String fileName,
) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/pdf')],
    subject: fileName,
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
