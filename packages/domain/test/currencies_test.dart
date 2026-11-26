import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات الدفعة 34 — تعدد العملات الفعلي (F-120/F-121/F-124،
/// D-194).
///
/// الحدود الموثقة: الكود ثلاثة أحرف لاتينية A-Z مطبَّعة، وتفرده مطلق
/// بالحي والمعطل (اللقطات تحيل إلى الكود)، وخانات الوحدة الصغرى
/// 0..8، والسعر مكبَّر موجب بتاريخ ISO صالح غير مستقبل (D-194: الحد
/// الصادق)، وعملة الأساسية مقياس الكل لا تُسجل لها أسعار ولا تُعطَّل،
/// والليرة أساساً والدولار بجانبها من م1 لا يُمسان (D-070).
void main() {
  group('تطبيع الكود (normalizeCurrencyCode)', () {
    test('نزع الفراغات ورفع الحالة', () {
      expect(normalizeCurrencyCode(' eur '), 'EUR');
      expect(normalizeCurrencyCode('Usd'), 'USD');
      expect(normalizeCurrencyCode('SAR'), 'SAR');
    });
  });

  group('التحقق قبل الحفظ (validateCurrencySpec)', () {
    test('عملة سليمة تعود بلا أخطاء', () {
      final errors = validateCurrencySpec(
        const CurrencySpec(code: 'eur', name: 'يورو', minorUnits: 2),
        existingCodes: {'USD'},
      );
      expect(errors, isEmpty);
    });

    test('الكود ليس ثلاثة أحرف لاتينية يُرفض: أقصر وأطول وأرقام وعربي',
        () {
      for (final bad in ['EU', 'EURO', 'E1R', 'يور', '', 'E.R']) {
        final errors = validateCurrencySpec(
          CurrencySpec(code: bad, name: 'س', minorUnits: 2),
          existingCodes: {},
        );
        expect(errors.whereType<CurrencyCodeInvalid>().length, 1,
            reason: 'الكود «$bad» مرفوض');
      }
    });

    test('الكود المحفوظ حرفياً مرفوض — والتقليم قبل المقارنة', () {
      final errors = validateCurrencySpec(
        const CurrencySpec(code: ' usd ', name: 'دولار', minorUnits: 2),
        existingCodes: {'USD'},
      );
      final taken = errors.whereType<CurrencyCodeTaken>().toList();
      expect(taken.length, 1);
      expect(taken.first.code, 'USD');
    });

    test('الاسم إلزامي وخانات الوحدة الصغرى بين 0 و8', () {
      final nameless = validateCurrencySpec(
        const CurrencySpec(code: 'EUR', name: '   ', minorUnits: 2),
        existingCodes: {},
      );
      expect(nameless.whereType<CurrencyNameRequired>().length, 1);

      for (final bad in [-1, 9]) {
        final errors = validateCurrencySpec(
          CurrencySpec(code: 'EUR', name: 'يورو', minorUnits: bad),
          existingCodes: {},
        );
        final invalid = errors.whereType<CurrencyMinorUnitsInvalid>().toList();
        expect(invalid.length, 1, reason: 'القيمة $bad مرفوضة');
        expect(invalid.first.value, bad);
      }
      for (final good in [0, 2, 8]) {
        final errors = validateCurrencySpec(
          CurrencySpec(code: 'EUR', name: 'يورو', minorUnits: good),
          existingCodes: {},
        );
        expect(errors.whereType<CurrencyMinorUnitsInvalid>(), isEmpty);
      }
    });

    test('عدة أخطاء معاً تُجمع لا تُقتطع', () {
      final errors = validateCurrencySpec(
        const CurrencySpec(code: 'x', name: '', minorUnits: 99),
        existingCodes: {},
      );
      expect(errors.length, 3);
    });
  });

  group('صلاحية تاريخ السعر (currencyDateValid)', () {
    test('الصيغة الموحدة YYYY-MM-DD الصالحة تُقبل', () {
      expect(currencyDateValid('2026-11-06'), isTrue);
      expect(currencyDateValid(' 2026-01-31 '), isTrue);
    });

    test('كل ما ليس تاريخاً موحداً يُرفض بلا اختراع', () {
      for (final bad in [
        '2026/11/06',
        '06-11-2026',
        '2026-11-6',
        '2026-13-01',
        '2026-00-10',
        '2026-11-00',
        '2026-11-32',
        'abc-11-06',
        '',
        '2026-11',
      ]) {
        expect(currencyDateValid(bad), isFalse, reason: '«$bad» مرفوض');
      }
    });
  });

  group('التحقق قبل تسجيل سعر (validateExchangeRateRecord)', () {
    test('سعر سليم لعملة غير أساسية بتاريخ اليوم يعود بلا أخطاء', () {
      expect(
        validateExchangeRateRecord(
          rateToBase: 15000000000,
          date: '2026-11-06',
          todayIso: '2026-11-06',
          isBase: false,
        ),
        isEmpty,
      );
    });

    test('السعر الصفري والسالب يرفضان (CurrencyRateInvalid)', () {
      for (final bad in [0, -1]) {
        final errors = validateExchangeRateRecord(
          rateToBase: bad,
          date: '2026-11-06',
          todayIso: '2026-11-06',
          isBase: false,
        );
        expect(errors.whereType<CurrencyRateInvalid>().length, 1);
      }
    });

    test('التاريخ المستقبلي مرفوض (D-194: الحد الصادق) والماضي يمر', () {
      final future = validateExchangeRateRecord(
        rateToBase: 15000000000,
        date: '2026-11-07',
        todayIso: '2026-11-06',
        isBase: false,
      );
      expect(future.whereType<CurrencyRateDateFuture>().length, 1);

      final past = validateExchangeRateRecord(
        rateToBase: 15000000000,
        date: '2026-11-05',
        todayIso: '2026-11-06',
        isBase: false,
      );
      expect(past, isEmpty);
    });

    test('عملة الأساسية لا تُسجل لها أسعار (CurrencyBaseProtected)', () {
      final errors = validateExchangeRateRecord(
        rateToBase: 1000000,
        date: '2026-11-06',
        todayIso: '2026-11-06',
        isBase: true,
      );
      expect(errors.whereType<CurrencyBaseProtected>().length, 1);
    });
  });

  group('عرض السعر المخزَّن (displayRateToBase)', () {
    test('المكبَّر يعود لحقيقته بلا كسور زائدة', () {
      expect(displayRateToBase(15000 * 1000000), '15000');
      expect(displayRateToBase(1000000), '1');
      expect(displayRateToBase(15000000), '15');
      expect(displayRateToBase(15500000), '15.5');
      expect(displayRateToBase(15125250), '15.12525');
      expect(displayRateToBase(null), '');
    });
  });

  group('مراكز العملات بالحساب النقي (currencyPositionsCompute)', () {
    test('المكافئ الإجمالي مجموع القيم المخزنة حصراً — صناديق ومتبقيات',
        () {
      final rows = currencyPositionsCompute([
        const CurrencyPositionInput(
          currencyId: 1,
          code: 'SYP',
          name: 'ليرة سورية',
          isBase: true,
          boxesCount: 1,
          boxesBaseMinor: 25000000,
          openInvoicesCount: 0,
          openRemainderDocMinor: 0,
          openRemainderBaseMinor: 0,
        ),
        CurrencyPositionInput(
          currencyId: 2,
          code: 'USD',
          name: 'دولار أمريكي',
          isBase: false,
          boxesCount: 1,
          boxesBaseMinor: 37000000,
          openInvoicesCount: 2,
          openRemainderDocMinor: 350 * 100,
          openRemainderBaseMinor: 5250000 + 1500000,
          latestRateToBase: 15000000000,
          latestRateDate: '2026-11-05',
        ),
      ]);
      expect(rows.length, 2);
      expect(rows[0].totalBaseMinor, 25000000);
      expect(rows[0].latestRateToBase, isNull);
      // المكافئ = الصناديق + المتبقيات المخزنة — لا تحويل جديد.
      expect(rows[1].totalBaseMinor, 37000000 + 5250000 + 1500000);
      expect(rows[1].openRemainderDocMinor, 35000);
      expect(rows[1].latestRateDate, '2026-11-05');
    });
  });
}
