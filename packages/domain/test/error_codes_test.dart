import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:test/test.dart';

/// ═══ س107 (أساس الأخطاء — قرار المالك الخامس): اختبار طبقة الرموز ═══
///
/// العقد: السجل سلطة الترقيم الوحيدة — كل رمز بصيغة DQ-xxxx فريداً
/// لا يعاد، وكل مدخل باسمٍ ووجاهة غير فارغين، والبحث بالرمز حرفاً،
/// وكل استثناء مجالي معروف يُرقَّم برمزه الموثق، وغير المصنف يبقى
/// null فيتولاه DQ-0999 عند العرض.
void main() {
  group('سجل رموز DQ (س107)', () {
    test('الصيغة: كل رمز يطابق DQ-\\d{4}', () {
      for (final entry in diqqahErrorCodes) {
        expect(
          RegExp(r'^DQ-\d{4}$').hasMatch(entry.code),
          isTrue,
          reason: 'رمز بصيغة فاسدة: ${entry.code}',
        );
      }
    });

    test('التفرّد: لا رمز يعاد بالسجل', () {
      final codes = diqqahErrorCodes.map((e) => e.code).toSet();
      expect(codes.length, diqqahErrorCodes.length,
          reason: 'رمز مكرر بالسجل يكسر عقد التفسير');
    });

    test('كل مدخل باسم ووجاهة غير فارغين', () {
      for (final entry in diqqahErrorCodes) {
        expect(entry.title.trim(), isNotEmpty,
            reason: '${entry.code} بلا اسم');
        expect(entry.guidance.trim(), isNotEmpty,
            reason: '${entry.code} بلا وجاهة');
      }
    });

    test('النطاقات الستة للحواجز حاضرة عدداً', () {
      // كل نطاق وظيفي لا يقل عن أول رمزه.
      expect(
        diqqahErrorCodes.any((e) =>
            e.code.startsWith('DQ-01') && e.code.compareTo('DQ-0199') < 0),
        isTrue,
        reason: 'نطاق الدفتر 01xx غائب',
      );
      expect(
        diqqahErrorCodes.any((e) =>
            e.code.startsWith('DQ-02') && e.code.compareTo('DQ-0299') < 0),
        isTrue,
        reason: 'نطاق المخزون والفواتير 02xx غائب',
      );
      expect(
        diqqahErrorCodes.any((e) =>
            e.code.startsWith('DQ-03') && e.code.compareTo('DQ-0399') < 0),
        isTrue,
        reason: 'نطاق الصندوق والسندات 03xx غائب',
      );
      expect(
        diqqahErrorCodes.any((e) =>
            e.code.startsWith('DQ-04') && e.code.compareTo('DQ-0499') < 0),
        isTrue,
        reason: 'نطاق التحويل والجرد 04xx غائب',
      );
      expect(
        diqqahErrorCodes.any((e) =>
            e.code.startsWith('DQ-05') && e.code.compareTo('DQ-0599') < 0),
        isTrue,
        reason: 'نطاق الإذن والتجميع والصرف 05xx غائب',
      );
      expect(
        diqqahErrorCodes.any((e) =>
            e.code.startsWith('DQ-06') && e.code.compareTo('DQ-0699') < 0),
        isTrue,
        reason: 'نطاق الإقفال 06xx غائب',
      );
      expect(
        diqqahErrorCodes.any((e) => e.code.startsWith('DQ-10')),
        isTrue,
        reason: 'نطاق فحوص المجال 10xx غائب',
      );
      expect(
        diqqahErrorCodes.any((e) => e.code.startsWith('DQ-11')),
        isTrue,
        reason: 'نطاق البنية والتخزين 11xx غائب',
      );
    });

    test('البحث بالرمز حرفاً — موجودٌ وغائبٌ', () {
      final entry = diqqahErrorCodeOf('DQ-0101');
      expect(entry, isNotNull);
      expect(entry!.title, 'قيد غير متوازن');
      expect(diqqahErrorCodeOf('DQ-0000'), isNull);
      expect(diqqahErrorCodeOf('dq-0101'), isNull,
          reason: 'البحث حرفاً لا مطاوعة حالة');
    });

    test('الفاصلة الآمنة DQ-0999 بلسانها الموثق', () {
      expect(diqqahUnclassifiedError.code, 'DQ-0999');
      expect(diqqahUnclassifiedError.title, 'خطأ غير مصنف');
    });
  });

  group('خريطة استثناءات المجال (س107)', () {
    test('كل استثناء مجالي معروف برمزه الموثق', () {
      expect(dqCodeForDomainError(InvoiceValidationException([])), 'DQ-1001');
      expect(dqCodeForDomainError(VoucherValidationException([])), 'DQ-1002');
      expect(
          dqCodeForDomainError(CashTransferValidationException([])), 'DQ-1003');
      expect(dqCodeForDomainError(CashAdjustmentValidationException([])),
          'DQ-1004');
      expect(dqCodeForDomainError(const NegativeBalanceException()), 'DQ-1005');
      expect(dqCodeForDomainError(PeriodClosingException([])), 'DQ-1006');
      expect(dqCodeForDomainError(YearCloseException([])), 'DQ-1007');
      expect(dqCodeForDomainError(BundleValidationException([])), 'DQ-1008');
      expect(dqCodeForDomainError(AssemblyValidationException([])), 'DQ-1009');
      expect(
          dqCodeForDomainError(StockCountValidationException([])), 'DQ-1010');
      expect(dqCodeForDomainError(StockDocValidationException([])), 'DQ-1011');
      expect(
          dqCodeForDomainError(StockTransferValidationException([])),
          'DQ-1012');
      expect(dqCodeForDomainError(ReportValidationException([])), 'DQ-1013');
      expect(dqCodeForDomainError(BackupCipherException('')), 'DQ-1014');
      expect(dqCodeForDomainError(ItemImageException('')), 'DQ-1015');
    });

    test('غير المصنف يعيد null — الفاصلة للعرض لا للخريطة', () {
      expect(dqCodeForDomainError(Exception('غريب')), isNull);
      expect(dqCodeForDomainError('نص لا استثناء'), isNull);
      expect(dqCodeForDomainError(StateError('x')), isNull);
    });
  });
}
