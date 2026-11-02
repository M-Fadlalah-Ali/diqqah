import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;

import 'package:pdf/pdf.dart' show PdfPageFormat;

import 'package:diqqah_app/print_service.dart';

/// اختبارات محرك الطباعة (D-016، دفعة إغلاق النواة س37) — التوليد نقي
/// بلا قنوات منصة: بايتات PDF صحيحة الترويج بالخط العربي المضمّن،
/// وافتراضيات القياس لكل نوع (D-101 معروض) بدوالها النقية.
void main() {
  // التوليد النقي يستدعي rootBundle لتحميل الخط المضمّن — والربط لازم
  // مهيّأ في الاختبار النقي (درس CI: Binding has not yet been initialized).
  TestWidgetsFlutterBinding.ensureInitialized();

  test('افتراضيات القياس (D-101): الفواتير والسندات A5 طولي والتقارير A4 عرضي',
      () {
    final invoice = resolvePageFormat(docKind: 'invoice');
    expect(invoice.width, lessThan(invoice.height),
        reason: 'الفاتورة A5 طولية');
    expect(invoice.width, closeTo(PdfPageFormat.a5.width, 0.5));

    final voucher = resolvePageFormat(docKind: 'voucher');
    expect(voucher.width, lessThan(voucher.height), reason: 'السند A5 طولي');

    final report = resolvePageFormat(docKind: 'report');
    expect(report.width, greaterThan(report.height),
        reason: 'التقرير A4 عرضي');
    expect(report.width, closeTo(PdfPageFormat.a4.height, 0.5));
  });

  test('التجاوز الصريح: A4 طولي بأمر النداء يقلب الاتجاه الافتراضي', () {
    final forced = resolvePageFormat(
      docKind: 'report',
      sizeOverride: 'a4',
      landscapeOverride: false,
    );
    expect(forced.width, lessThan(forced.height));
    // وغياب التجاوز يعيد الافتراضي
    final def = resolvePageFormat(docKind: 'report');
    expect(def.width, greaterThan(def.height));
  });

  test('توليد مستند بجدول (نمط فاتورة): بايتات PDF صحيحة غير فارغة',
      () async {
    final bytes = await buildDocumentPdf(
      title: 'فاتورة بيع 2026/000001',
      headerPairs: const [
        ('التاريخ', '2026-03-15'),
        ('الحالة', 'مرحّلة'),
        ('البيان', 'بيع بضاعة للعميل'),
      ],
      columns: const ['الصنف', 'الكمية', 'سعر الوحدة', 'المبلغ'],
      rows: const [
        ['زيت محلي', '10', '15,000', '150,000'],
        ['خدمة', '1', '20,000', '20,000'],
      ],
      footerPairs: const [
        ('الإجمالي', '170,000 ل.س'),
        ('المدفوع', '170,000 ل.س'),
        ('الباقي', '0 ل.س'),
      ],
      standoutLine: 'فقط مئة وسبعون ألف ليرة سورية لا غير',
      format: resolvePageFormat(docKind: 'invoice'),
    );
    expect(bytes, isA<Uint8List>());
    expect(bytes.lengthInBytes, greaterThan(1000),
        reason: 'الخط المضمّن والمحتوى يجعلان الملف حقيقياً');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  /// س50/3 (س-157/D-155 — دفعة 17): شعار العلامة صورة من الأصول —
  /// حروف «دِقّة» وحركاتها مرسومة مسبقاً لا تفسّر عند كل طباعة.
  test('شعار العلامة من الأصول بايتات PNG صحيحة — ترويسة وخاتمة', () async {
    final header = await brandAsset('wordmark-header');
    final footer = await brandAsset('wordmark-footer');
    expect(header, isNotNull, reason: 'أصل الترويسة مزروع بالأصول');
    expect(footer, isNotNull, reason: 'أصل الخاتمة مزروع بالأصول');
    // توقيع PNG: 89 50 4E 47
    expect(header!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
    expect(footer!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
  });

  /// س50/8 (س-160/D-158 — دفعة 17): سطر التفقيط المستقل — يُبنى الورقة
  /// به بلا تسمية، وغيابه لا يضر (المطبوعات الأخرى لا سطر لها).
  test('سطر التفقيط المستقل بلا تسمية يُبنى PDF صحيحاً — وغيابه مسكوت', () async {
    final withLine = await buildDocumentPdf(
      title: 'فاتورة بيع 2026/000001',
      headerPairs: const [('السداد', 'نقدية')],
      columns: const ['الصنف', 'المبلغ'],
      rows: const [['زيت', '30,000']],
      footerPairs: const [
        ('الإجمالي', '30,000 ل.س'),
        ('المدفوع', '30,000 ل.س'),
        ('الباقي', '0 ل.س'),
      ],
      standoutLine: 'فقط ثلاثون ألف ليرة سورية لا غير',
      format: resolvePageFormat(docKind: 'invoice'),
    );
    final withoutLine = await buildDocumentPdf(
      title: 'تقرير عام',
      headerPairs: const [],
      columns: const ['الحساب'],
      rows: const [['الصندوق']],
      footerPairs: const [],
      format: resolvePageFormat(docKind: 'report'),
    );
    expect(String.fromCharCodes(withLine.take(5)), '%PDF-');
    expect(String.fromCharCodes(withoutLine.take(5)), '%PDF-');
    expect(withLine, isNot(withoutLine));
  });

  test('توليد قسيمة سند بلا جدول: ترويسة وخلاصة فقط — PDF صحيح', () async {
    final bytes = await buildDocumentPdf(
      title: 'سند قبض 2026/000001',
      headerPairs: const [
        ('التاريخ', '2026-03-15'),
        ('النوع', 'سند قبض'),
        ('الجهة', 'عميل الأمل'),
        ('الصندوق', 'الصندوق الرئيسي'),
      ],
      columns: const [],
      rows: const [],
      footerPairs: const [('المبلغ', '30,000 SYP')],
      format: resolvePageFormat(docKind: 'voucher'),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('توليد تقرير بجدول عريض A4 عرضي — PDF صحيح بأحجام مختلفة عن A5',
      () async {
    final reportBytes = await buildDocumentPdf(
      title: 'ميزان المراجعة',
      headerPairs: const [],
      columns: const ['الحساب', 'مدين', 'دائن', 'الرصيد'],
      rows: const [
        ['1111 الصندوق الرئيسي', '520,000', '0', '520,000'],
        ['211 الموردون', '0', '200,000', '200,000'],
      ],
      footerPairs: const [
        ('مجموع المدين', '805,000'),
        ('مجموع الدائن', '805,000'),
        ('الحالة', 'الميزان متوازن ✓ (F-068)'),
      ],
      format: resolvePageFormat(docKind: 'report'),
    );
    final invoiceBytes = await buildDocumentPdf(
      title: 'فاتورة بيع 2026/000001',
      headerPairs: const [('التاريخ', '2026-03-15')],
      columns: const ['الصنف', 'الكمية'],
      rows: const [['زيت', '10']],
      footerPairs: const [],
      format: resolvePageFormat(docKind: 'invoice'),
    );
    expect(String.fromCharCodes(reportBytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(invoiceBytes.take(5)), '%PDF-');
    // مقاسا الصفحة مختلفان فيتميز المحتوى (التحويل التلقائي بين
    // القياسين موثق D-016) — الأرقام داخل البايتات تحمل أبعاد الصفحة.
    expect(reportBytes, isNot(invoiceBytes));
  });

  // ═══ س-154/D-152 (دفعة 16): تعقيم اسم ملف المشاركة ═══
  // علّة المالك الحية 2026-11-02: تسمية العرض «فاتورة بيع 2026/000003»
  // تحمل المائل ففسره النظام الملفي فاصل مجلد وقعدت المشاركة
  // بـPathNotFoundException (errno = 2).

  test('تعقيم اسم المشاركة: مائل تسمية العرض المعتمدة يصير شرطة — لا فاصل مسار', () {
    final safe = safeFileName('فاتورة بيع 2026/000003.pdf');
    expect(safe, 'فاتورة بيع 2026-000003.pdf');
    expect(safe.contains('/'), isFalse,
        reason: 'علّة المالك: المائل في الاسم يولّد مجلداً وهمياً');
    expect(safe.contains('\\'), isFalse);
    // والسندات بصيغة التسمية ذاتها
    expect(safeFileName('سند قبض 2026/000001.pdf'), 'سند قبض 2026-000001.pdf');
  });

  test('تعقيم اسم المشاركة: محارف المسار المحجوزة كلها شرطة والمتواليات تنقل لشرطة واحدة', () {
    expect(safeFileName(r'a\\b:c*d?e"f<g>h|i.pdf'), 'a-b-c-d-e-f-g-h-i.pdf');
    expect(safeFileName('تقرير // خاص.pdf'), 'تقرير - خاص.pdf');
    expect(safeFileName('كشف حساب/مصرف الشام/2026.pdf'),
        'كشف حساب-مصرف الشام-2026.pdf');
  });

  test('تعقيم اسم المشاركة: الأطراف تنظف والخالي يعود «مستند»', () {
    expect(safeFileName(' تقرير - '), 'تقرير');
    expect(safeFileName('...تقرير.pdf'), 'تقرير.pdf',
        reason: 'النقطة الأولى تصير الملف مخفياً على يونكس');
    expect(safeFileName('///'), 'مستند');
  });

  test('الكتابة الفعلية بالاسم المعقم تنجح على مسار حقيقي — محاكاة علّة المالك نفسها', () async {
    final tmp = await Directory.systemTemp.createTemp('diqqah_share_test');
    final label = 'فاتورة بيع 2026/000003.pdf';
    final file = File(p.join(tmp.path, safeFileName(label)));
    await file.writeAsBytes(Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]));
    expect(file.existsSync(), isTrue,
        reason: 'الاسم المعقم يكتب بلا PathNotFoundException');
    expect(p.basename(file.path), 'فاتورة بيع 2026-000003.pdf');
    await tmp.delete(recursive: true);
  });
}
