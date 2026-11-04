import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات التقويم الهجري الحسابي المعياري — F-167/الدفعة 23 (D-183):
/// المراسي الموثقة، وبنية الدورة الثلاثينية، والتحويل عكسياً، ورفض
/// المدخل الفاسد بلا اختراع.
void main() {
  group('المراسي الموثقة للمدني الحسابي', () {
    test('1 محرم 1429 = 2008-01-10', () {
      expect(hijriFromIsoDate('2008-01-10'), '1429-01-01');
    });

    test('1 محرم 1430 = 2008-12-29', () {
      expect(hijriFromIsoDate('2008-12-29'), '1430-01-01');
    });

    test('1 محرم 1431 = 2009-12-18', () {
      expect(hijriFromIsoDate('2009-12-18'), '1431-01-01');
    });
  });

  group('بنية الدورة الثلاثينية', () {
    test('إحدى عشرة سنة كبيسة في كل دورة — والطول 10631 يوماً', () {
      var leaps = 0;
      var days = 0;
      for (var y = 1; y <= 30; y++) {
        if (isHijriLeapYear(y)) leaps++;
        days += hijriYearLength(y);
      }
      expect(leaps, 11);
      expect(days, 10631);
    });

    test('طول الشهور: الفردية 30 والزوجية 29 وذي الحجة بالكبيسة', () {
      for (var m = 1; m <= 12; m++) {
        expect(hijriMonthLength(5, m), m.isOdd || m == 12 ? 30 : 29,
            reason: 'سنة 5 كبيسة فذي الحجة 30');
      }
      expect(hijriMonthLength(4, 12), 29, reason: 'سنة 4 بسيطة');
      for (var m = 1; m <= 11; m++) {
        expect(
            hijriMonthLength(4, m), m.isOdd ? 30 : 29,
            reason: 'الشهر $m لا يتأثر بالكبيسة');
      }
    });
  });

  group('التحويل عكسياً على عينة كثيفة', () {
    test('هجري من ميلادي ثم JDN يعيد اليوم ذاته على 1900..2100', () {
      var checked = 0;
      for (var jdn = jdnFromGregorian(1900, 1, 1);
          jdn <= jdnFromGregorian(2100, 12, 31);
          jdn += 3) {
        final (hy, hm, hd) = hijriPartsFromJdn(jdn);
        // الرجوع بالبنية: مجموع أطوال السنوات والشهور السابقة + اليوم.
        var days = 0;
        for (var y = 1; y < hy; y++) {
          days += hijriYearLength(y);
        }
        for (var m = 1; m < hm; m++) {
          days += hijriMonthLength(hy, m);
        }
        days += hd - 1;
        expect(days + 1948440, jdn, reason: 'عكس التحويل عند JDN $jdn');
        checked++;
      }
      expect(checked, greaterThan(20000), reason: 'عينة كثيفة حقيقية');
    });

    test('شهر لا يزيد على 12 ويوم لا يزيد على طوله بلا استثناء', () {
      for (var jdn = jdnFromGregorian(1950, 1, 1);
          jdn <= jdnFromGregorian(2050, 12, 31);
          jdn += 7) {
        final (hy, hm, hd) = hijriPartsFromJdn(jdn);
        expect(hm, inInclusiveRange(1, 12));
        expect(hd, inInclusiveRange(1, hijriMonthLength(hy, hm)));
        expect(hy, inInclusiveRange(1369, 1474),
            reason: 'مجال 1950..2050 هجرياً 1369..1473');
      }
    });
  });

  group('رفض المدخل الفاسد بلا اختراع', () {
    test('نصوص فاسدة تعود فارغة', () {
      expect(hijriFromIsoDate(''), isNull);
      expect(hijriFromIsoDate('2026/11/04'), isNull, reason: 'الشرطات حصراً');
      expect(hijriFromIsoDate('2026-13-01'), isNull, reason: 'شهر زائف');
      expect(hijriFromIsoDate('2026-02-30'), isNull, reason: 'يوم زائف');
      expect(hijriFromIsoDate('2025-02-29'), isNull, reason: '2025 ليست كبيسة');
      expect(hijriFromIsoDate('abc'), isNull);
      expect(hijriFromIsoDate('2026-11-4'), isNull, reason: 'بلا حشو صفر');
    });

    test('سنين كبيسة ميلادية يقبل 29 فبراير', () {
      expect(hijriFromIsoDate('2024-02-29'), isNotNull);
      expect(hijriFromIsoDate('2000-02-29'), isNotNull);
      expect(hijriFromIsoDate('1900-02-28'), isNotNull,
          reason: '1900 ليست كبيسة فالـ29 زائف');
      expect(hijriFromIsoDate('1900-02-29'), isNull);
    });

    test('تاريخ اليوم المعروف يعطي سنة هجرية في مجالها', () {
      final h = hijriFromIsoDate('2026-11-04');
      expect(h, isNotNull);
      final hy = int.parse(h!.split('-').first);
      expect(hy, inInclusiveRange(1447, 1448),
          reason: 'نوفمبر 2026 يقف بين رجب وشعبان 1448');
    });
  });
}
