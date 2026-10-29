import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  group('رقم الطرف (D-063) — نزع الأصفار الزائدة', () {
    test('«0053» و«53» مفتاح واحد', () {
      expect(partyNumberKey('0053'), '53');
      expect(partyNumberKey('53'), '53');
      expect(partyNumberKey('  0053 '), '53');
      expect(partyNumberKey('000'), '0');
      expect(partyNumberKey(''), '');
    });

    test('غير الرقمي يبقى كما هو بلا مساس', () {
      expect(partyNumberKey('A-12'), 'A-12');
      expect(isNumericPartyNumber('A-12'), isFalse);
      expect(isNumericPartyNumber('53'), isTrue);
      expect(isNumericPartyNumber('0'), isTrue);
      expect(isNumericPartyNumber(''), isFalse);
    });
  });

  group('الترتيب الرقمي الذكي (س-29: 1، 2، 10 لا 1، 10، 2)', () {
    test('يرتب عددياً ويلحق غير الرقمي آخراً بترتيبه المعجمي', () {
      final numbers = ['10', '1', 'A-12', '2', '53', '9'];
      final sorted = [...numbers]..sort(comparePartyNumbers);
      expect(sorted, ['1', '2', '9', '10', '53', 'A-12']);
    });

    test('الأصفار الزائدة لا تغير الترتيب ولا الهوية', () {
      final numbers = ['0053', '7', '0070'];
      final sorted = [...numbers]..sort(comparePartyNumbers);
      expect(sorted, ['7', '0053', '0070']);
      expect(comparePartyNumbers('0053', '53'), 0);
    });
  });

  group('التوليد الآلي (D-063/س-29 — نمط 0007)', () {
    test('بلا أطراف رقمية يبدأ التسلسل من 0001', () {
      expect(suggestNextPartyNumber([]), '0001');
      expect(suggestNextPartyNumber(['A-12']), '0001');
    });

    test('يولّد التالي معبأ بأصفار حتى أربعة مواضع', () {
      expect(suggestNextPartyNumber(['0006']), '0007');
      expect(suggestNextPartyNumber(['53', '0007']), '0054');
      expect(suggestNextPartyNumber(['999', '1000']), '1001');
    });

    test('لا فائض مهما طال الرقم', () {
      expect(suggestNextPartyNumber(['99999999999999999999']),
          '100000000000000000000');
    });
  });

  group('تطبيع البحث (D-064) — في البحث فقط لا المخزون', () {
    test('الهمزات والى والتاء المربوطة والتشكيل تتوحد', () {
      expect(normalizeArabicForSearch('أَحْمَد'), 'احمد');
      expect(normalizeArabicForSearch('إبراهيم'), 'ابراهيم');
      expect(normalizeArabicForSearch('آخر'), 'اخر');
      expect(normalizeArabicForSearch('مصطفى'), 'مصطفي');
      expect(normalizeArabicForSearch('فاطمة'), 'فاطمه');
      expect(normalizeArabicForSearch('عَلِيٌّ'), 'علي');
      expect(normalizeArabicForSearch('ABC'), 'abc');
    });

    test('نقية: المدخل لا يتغير بايتاً', () {
      final original = 'أَحْمَد';
      final out = normalizeArabicForSearch(original);
      expect(original, 'أَحْمَد');
      expect(out, isNot(same(original)));
    });
  });

  group('البحث الجامع (س-31) — كلمات متفرقة تلتقي بأي ترتيب', () {
    const خالدي = PartySearchFields(
      name: 'محمد الخالدي',
      number: '0053',
      phone: '0933',
    );

    test('«خال 53» تجيء بالطرف — بالترتيبين', () {
      expect(خالدي.matchesQuery('خال 53'), isTrue);
      expect(خالدي.matchesQuery('53 خال'), isTrue);
    });

    test('كل كلمة قد تجد موضعها في حقل مختلف', () {
      expect(خالدي.matchesQuery('محمد 0933'), isTrue);
      expect(خالدي.matchesQuery('0053 خالدي'), isTrue);
    });

    test('كلمة غائبة تُفشل المطابقة كلها', () {
      expect(خالدي.matchesQuery('خال 53 زيد'), isFalse);
    });

    test('البحث مطبَّع: «احمد» تجد «أحمد»', () {
      const غالي = PartySearchFields(name: 'أحمد الغالي', number: '0012');
      expect(غالي.matchesQuery('احمد'), isTrue);
      expect(غالي.matchesQuery('أحمد'), isTrue);
    });

    test('الخانة الفارغة تجيء بالجميع', () {
      expect(خالدي.matchesQuery(''), isTrue);
      expect(خالدي.matchesQuery('   '), isTrue);
    });
  });

  group('منع تكرار الاسم حرفياً (D-065) — المقارنة بلا تطبيع', () {
    test('«احمد» و«أحمد» طرفان مختلفان — التطبيع للبحث حصراً', () {
      final index = PartyUniquenessIndex.build([
        const ExistingParty(id: 1, number: '0001', name: 'أحمد', isActive: true),
      ]);
      final errors = validatePartyDraft(
        const PartyDraft(
            number: '0002', name: 'احمد', kind: PartyKind.customer),
        existing: index,
      );
      expect(errors, isEmpty);
    });

    test('المطابق الحرفي مرفوض والرسالة تحمل الطرف القائم بالاسم والرقم', () {
      final index = PartyUniquenessIndex.build([
        const ExistingParty(
            id: 1, number: '0053', name: 'محمد الخالدي', isActive: true),
      ]);
      final errors = validatePartyDraft(
        const PartyDraft(
            number: '0002', name: 'محمد الخالدي ', kind: PartyKind.customer),
        existing: index,
      );
      expect(errors, hasLength(1));
      final taken = errors.single as PartyNameTaken;
      expect(taken.existingLabel, 'محمد الخالدي (0053)');
    });

    test('المعطل يبقى محجوز الاسم والرقم — التعطيل لا يحذف (س-33)', () {
      final index = PartyUniquenessIndex.build([
        const ExistingParty(
            id: 2, number: '0012', name: 'أحمد الغالي', isActive: false),
      ]);
      final errors = validatePartyDraft(
        const PartyDraft(
            number: '0012', name: 'أحمد الغالي', kind: PartyKind.customer),
        existing: index,
      );
      expect(errors.whereType<PartyNameTaken>(), isNotEmpty);
      expect(errors.whereType<PartyNumberTaken>(), isNotEmpty);
    });
  });

  group('التحقق قبل الحفظ (س-29/س-35)', () {
    final index = PartyUniquenessIndex.build([
      const ExistingParty(
          id: 1, number: '0053', name: 'محمد الخالدي', isActive: true),
      const ExistingParty(
          id: 2, number: '0012', name: 'أحمد الغالي', isActive: false),
    ]);

    test('بلا اسم مرفوض — الاسم إلزامي وحده (س-29)', () {
      final errors = validatePartyDraft(
        const PartyDraft(number: '0002', name: '   ', kind: PartyKind.customer),
        existing: index,
      );
      expect(errors.whereType<PartyNameRequired>(), isNotEmpty);
    });

    test('رقم فارغ مرفوض — مستحيل عملاً بالتوليد وحارس تكاملي', () {
      final errors = validatePartyDraft(
        const PartyDraft(number: '   ', name: 'زيد', kind: PartyKind.customer),
        existing: index,
      );
      expect(errors.whereType<PartyNumberRequired>(), isNotEmpty);
    });

    test('«53» مرفوض لأن «0053» قائم — والرسالة تري صاحبها بنمط س-29', () {
      final errors = validatePartyDraft(
        const PartyDraft(
            number: '53', name: 'آخر', kind: PartyKind.customer),
        existing: index,
      );
      expect(errors, hasLength(1));
      final taken = errors.single as PartyNumberTaken;
      expect(taken.duplicateKey, '53');
      expect(taken.existingLabel, 'محمد الخالدي (0053)');
    });

    test('العملة صفراً أو سالباً مرفوضة — لا فراغ للعملة (D-066)', () {
      for (final bad in const [0, -1]) {
        final errors = validatePartyDraft(
          PartyDraft(
              number: '0002',
              name: 'زيد',
              kind: PartyKind.customer,
              currencyId: bad),
          existing: index,
        );
        expect(errors.whereType<PartyCurrencyMissing>(), isNotEmpty);
      }
    });

    test('حد الائتمان: الصفر والسالب مرفوضان والفراغ «بلا سقف» مشروع (س-34)', () {
      final zero = validatePartyDraft(
        const PartyDraft(
            number: '0002',
            name: 'زيد',
            kind: PartyKind.customer,
            creditLimitBaseMinor: 0),
        existing: index,
      );
      expect(zero.whereType<PartyCreditLimitInvalid>(), isNotEmpty);

      final negative = validatePartyDraft(
        const PartyDraft(
            number: '0002',
            name: 'زيد',
            kind: PartyKind.customer,
            creditLimitBaseMinor: -5),
        existing: index,
      );
      expect(negative.whereType<PartyCreditLimitInvalid>(), isNotEmpty);

      final without = validatePartyDraft(
        const PartyDraft(number: '0002', name: 'زيد', kind: PartyKind.customer),
        existing: index,
      );
      expect(without, isEmpty);

      final withLimit = validatePartyDraft(
        const PartyDraft(
            number: '0002',
            name: 'زيد',
            kind: PartyKind.customer,
            creditLimitBaseMinor: 5000),
        existing: index,
      );
      expect(withLimit, isEmpty);
    });

    test('التعديل يستثني صاحبه من فحص التكرار ويصطدم بغيره (س-32)', () {
      final self = validatePartyDraft(
        const PartyDraft(
            number: '0053',
            name: 'محمد الخالدي',
            kind: PartyKind.both,
            currencyId: 1),
        existing: index,
        excludePartyId: 1,
      );
      expect(self, isEmpty);

      final clash = validatePartyDraft(
        const PartyDraft(
            number: '0053',
            name: 'محمد الخالدي',
            kind: PartyKind.both,
            currencyId: 1),
        existing: index,
        excludePartyId: 2,
      );
      expect(clash.whereType<PartyNumberTaken>(), isNotEmpty);
      expect(clash.whereType<PartyNameTaken>(), isNotEmpty);
    });
  });

  test('صيغة العرض المعتمدة «الاسم (الرقم)» (D-065/س-29)', () {
    expect(partyDisplayLabel('محمد الخالدي', '0053'), 'محمد الخالدي (0053)');
  });

  test('N-003/س-31: البحث الجامع صحيح عند 5,000 طرف — حد الزمن المعتمد '
      '(<100ms) يقاس على الجهاز المرجعي عند تسليم الدفعة، والحد هنا متساهل '
      'حارساً للانحدار فقط', () {
    final fields = List.generate(5000, (i) {
      return PartySearchFields(
        name: 'طرف رقم $i',
        number: (i + 1).toString().padLeft(4, '0'),
      );
    });
    final watch = Stopwatch()..start();
    final hits = fields.where((f) => f.matchesQuery('رقم 4999')).toList();
    watch.stop();
    expect(hits, hasLength(1));
    expect(hits.single.number, '4999');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)),
        reason: 'الفلترة في الذاكرة عند 5,000 طرف أضعاف أسرع من الحد — '
            'الارتفاع عن الحد المتساهل علة انحدار لا بطء طبيعي');
  });

  test('نوع الطرف: التخزين والقراءة والملصق (س-30)', () {
    expect(PartyKind.customer.storageValue, 'customer');
    expect(PartyKind.supplier.label, 'مورد');
    expect(PartyKind.fromStorage('both'), PartyKind.both);
    expect(
        () => PartyKind.fromStorage('unknown'), throwsArgumentError);
  });
}
