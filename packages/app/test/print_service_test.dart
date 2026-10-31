import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pdf/pdf.dart' show PdfPageFormat;

import 'package:diqqah_app/print_service.dart';

/// اختبارات محرك الطباعة (D-016، دفعة إغلاق النواة س37) — التوليد نقي
/// بلا قنوات منصة: بايتات PDF صحيحة الترويج بالخط العربي المضمّن،
/// وافتراضيات القياس لكل نوع (D-101 معروض) بدوالها النقية.
void main() {
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
      columns: const ['الصنف', 'الكمية', 'سعر الوحدة', 'صافي السطر'],
      rows: const [
        ['زيت محلي', '10', '15,000', '150,000'],
        ['خدمة', '1', '20,000', '20,000'],
      ],
      footerPairs: const [
        ('الإجمالي', '170,000 (بالأساسية)'),
        ('المكافئ الأساسي', '170,000'),
      ],
      format: resolvePageFormat(docKind: 'invoice'),
    );
    expect(bytes, isA<Uint8List>());
    expect(bytes.lengthInBytes, greaterThan(1000),
        reason: 'الخط المضمّن والمحتوى يجعلان الملف حقيقياً');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
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
}
