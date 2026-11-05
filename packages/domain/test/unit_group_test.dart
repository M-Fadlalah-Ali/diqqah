import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات الدفعة 27 (رابعة م2) — مجموعات التعبئة وأسعارها آلي
/// (F-032/F-033/F-208، D-026/D-187).
///
/// الحدود الموثقة: القوالب مقترحة غير حصرية (D-026)، والعامل صحيح ≥2
/// نحو الأساسية (الأساسية 1 بذاتها)، والآلي افتراضه مفعّل ويترك
/// الوحدة الصغرى للكتابة والمستويات تُشتق بخطوة واحدة لا تراكم
/// تقريب (D-187)، والرفع الجماعي يعيد اشتقاق المشتق ويضرب اليدوي
/// بالنسبة نفسها مع علم الانكسار (تقاطع F-165)، والصفر ليس سعراً
/// فلا ينكسر ولا يُرفع (س6).
void main() {
  group('قراءة العامل من النص (parseUnitGroupFactor)', () {
    test('عدد صحيح ≥2 يُقبل والتقليم قبل القراءة', () {
      expect(parseUnitGroupFactor('12'), 12);
      expect(parseUnitGroupFactor(' 2 '), 2);
      expect(parseUnitGroupFactor('144'), 144);
    });

    test('كل ما ليس عاملاً صحيحاً يُرفض: أقل من 2 أو نص أو كسر أو فراغ',
        () {
      expect(parseUnitGroupFactor('1'), isNull, reason: 'الأساسية 1 بذاتها');
      expect(parseUnitGroupFactor('0'), isNull);
      expect(parseUnitGroupFactor('-3'), isNull);
      expect(parseUnitGroupFactor('1.5'), isNull);
      expect(parseUnitGroupFactor('abc'), isNull);
      expect(parseUnitGroupFactor(''), isNull);
      expect(parseUnitGroupFactor('1 2'), isNull);
    });
  });

  group('التحقق قبل الحفظ (validateUnitGroupSpec)', () {
    Set<String> namesOf(List<String> names) => names.toSet();

    test('اسم المجموعة إلزامي والمطابق حرفياً مرفوض (D-074)', () {
      final errors = validateUnitGroupSpec(
        const UnitGroupSpec(name: '  ', levels: [
          UnitGroupLevelSpec(name: 'علبة', factor: 12),
        ]),
        existingGroupNames: const {},
      );
      expect(errors, contains(isA<UnitGroupNameRequired>()));

      final taken = validateUnitGroupSpec(
        const UnitGroupSpec(name: 'تعبئة عامة', levels: [
          UnitGroupLevelSpec(name: 'علبة', factor: 12),
        ]),
        existingGroupNames: namesOf(['تعبئة عامة']),
      );
      final takenMatcher = isA<UnitGroupNameTaken>()
          .having((e) => e.existingName, 'existingName', 'تعبئة عامة');
      expect(taken.single, takenMatcher);
    });

    test('مجموعة بلا مستويات مرفوضة (F-032: مستويات متعددة)', () {
      final errors = validateUnitGroupSpec(
        const UnitGroupSpec(name: 'فارغة'),
        existingGroupNames: const {},
      );
      expect(errors.single, isA<UnitGroupLevelsMissing>());
    });

    test('اسم مستوى فارغ أو مكرر داخل المجموعة مرفوض (D-074)', () {
      final missing = validateUnitGroupSpec(
        const UnitGroupSpec(name: 'م', levels: [
          UnitGroupLevelSpec(name: '  ', factor: 12),
        ]),
        existingGroupNames: const {},
      );
      expect(missing.single, isA<UnitGroupLevelNameRequired>());

      final dup = validateUnitGroupSpec(
        const UnitGroupSpec(name: 'م', levels: [
          UnitGroupLevelSpec(name: 'علبة', factor: 12),
          UnitGroupLevelSpec(name: 'علبة', factor: 24),
        ]),
        existingGroupNames: const {},
      );
      final dupMatcher = isA<UnitGroupLevelNameDuplicate>()
          .having((e) => e.name, 'name', 'علبة');
      expect(dup.single, dupMatcher);
    });

    test('العامل <2 مرفوض والعاملان المتساويان داخل المجموعة مرفوضان',
        () {
      final small = validateUnitGroupSpec(
        const UnitGroupSpec(name: 'م', levels: [
          UnitGroupLevelSpec(name: 'علبة', factor: 1),
        ]),
        existingGroupNames: const {},
      );
      expect(small.single, isA<UnitGroupFactorInvalid>());

      final dupFactor = validateUnitGroupSpec(
        const UnitGroupSpec(name: 'م', levels: [
          UnitGroupLevelSpec(name: 'علبة', factor: 12),
          UnitGroupLevelSpec(name: 'كرتونة', factor: 12),
        ]),
        existingGroupNames: const {},
      );
      final dupFactorMatcher = isA<UnitGroupFactorDuplicate>()
          .having((e) => e.factor, 'factor', 12);
      expect(dupFactor.single, dupFactorMatcher);
    });

    test('مجموعة سليمة تمر بلا أخطاء — قوالب غير حصرية (D-026)', () {
      final errors = validateUnitGroupSpec(
        const UnitGroupSpec(name: 'تعبئة عصائر', levels: [
          UnitGroupLevelSpec(name: 'علبة', factor: 6),
          UnitGroupLevelSpec(name: 'كرتونة', factor: 48),
        ]),
        existingGroupNames: const {'تعبئة عامة'},
      );
      expect(errors, isEmpty);
    });
  });

  group('الاشتقاق بخطوة واحدة (derivedLevelPriceMinor — F-208/D-187)', () {
    test('مثال المتطلب: أساس 1,000 وعلبة عاملها 12 ⇒ 12,000 بلا كتابة',
        () {
      expect(
          derivedLevelPriceMinor(basePriceMinor: 1000, factor: 12), 12000);
    });

    test('الضرب الصحيح في الصحيح مطابق فلا تقريب ولا تراكم', () {
      expect(
          derivedLevelPriceMinor(basePriceMinor: 7, factor: 144), 1008);
      expect(
          derivedLevelPriceMinor(basePriceMinor: 12345, factor: 1000),
          12345000);
      expect(derivedLevelPriceMinor(basePriceMinor: 0, factor: 12), 0,
          reason: 'الصفر بلا سعر بعد يشتق صفراً (س6)');
    });
  });

  group('حسم مستوى في الترقية الجماعية (bulkLevelPriceOutcome — تقاطع F-165)',
      () {
    test('الآلي: المشتق يُعاد اشتقاقه من الأساس الجديد — النسبة تنتقل '
        'بذاتها ولا علم انكسار', () {
      final out = bulkLevelPriceOutcome(
        oldBasePriceMinor: 1000,
        newBasePriceMinor: 1100, // +10%
        factor: 12,
        priceAuto: true,
        oldLevelPriceMinor: 12000,
        percentBps: 1000,
      );
      expect(out.newLevelPriceMinor, 13200);
      expect(out.relationBroken, isFalse);
    });

    test('اليدوي: كل خانة تُضرب بالنسبة نفسها بقاعدة س7', () {
      final out = bulkLevelPriceOutcome(
        oldBasePriceMinor: 1000,
        newBasePriceMinor: 1100,
        factor: 12,
        priceAuto: false,
        oldLevelPriceMinor: 12000,
        percentBps: 1000,
      );
      expect(out.newLevelPriceMinor, 13200);
      expect(out.relationBroken, isFalse,
          reason: '12,000 = 1,000 × 12 فالعلاقة سليمة');
    });

    test('الانكسار: سعر يدوي مخالف للعامل يرفع علم الانكسار ويُضرب كما هو',
        () {
      final out = bulkLevelPriceOutcome(
        oldBasePriceMinor: 1000,
        newBasePriceMinor: 1100,
        factor: 12,
        priceAuto: false,
        oldLevelPriceMinor: 13000, // ≠ 12,000
        percentBps: 1000,
      );
      expect(out.relationBroken, isTrue);
      expect(out.newLevelPriceMinor, 14300);
    });

    test('الصفر ليس سعراً (س6): لا يُرفع ولا ينكسر', () {
      final out = bulkLevelPriceOutcome(
        oldBasePriceMinor: 1000,
        newBasePriceMinor: 1100,
        factor: 12,
        priceAuto: false,
        oldLevelPriceMinor: 0,
        percentBps: 1000,
      );
      expect(out.newLevelPriceMinor, 0);
      expect(out.relationBroken, isFalse,
          reason: '«بلا سعر بعد» ليست انكسار علاقة');
    });

    test('التخفيض بالنصف بعيداً عن الصفر — مثال كسري بس7', () {
      final out = bulkLevelPriceOutcome(
        oldBasePriceMinor: 1000,
        newBasePriceMinor: 990, // −1%
        factor: 12,
        priceAuto: false,
        oldLevelPriceMinor: 12005,
        percentBps: -100,
      );
      // 12005 × 0.99 = 11884.95 ⇒ مقرباً 11885 (النصف بعيداً عن الصفر)
      expect(out.newLevelPriceMinor, 11885);
    });
  });
}
