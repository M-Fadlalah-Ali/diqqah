import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// أدوات الاختبار: دليل مصغّر ثابت المعرفات + فترات جاهزة.
AccountInfo acc(int id, String code,
    {required AccountType type,
    NormalSide? side,
    bool leaf = true,
    bool active = true}) {
  return AccountInfo(
    id: id,
    code: code,
    name: 'حساب $code',
    type: type,
    normalSide: side ?? type.defaultNormalSide,
    parentId: null,
    isLeaf: leaf,
    isActive: active,
  );
}

LedgerAccountIndex smallIndex() {
  final accounts = [
    acc(1, '321', type: AccountType.equity, side: NormalSide.debit),
    acc(2, '1111', type: AccountType.asset),
    acc(3, '113', type: AccountType.asset),
    acc(4, '1', type: AccountType.asset, leaf: false), // أب
    acc(5, '42', type: AccountType.income, side: NormalSide.debit),
    acc(6, '112', type: AccountType.asset),
  ];
  return LedgerAccountIndex.build(accounts);
}

MoveDraft draft({
  String date = '2026-10-30',
  List<MoveLineDraft> lines = const [],
}) {
  return MoveDraft(
    journalId: 5,
    dateText: date,
    narration: 'قيد اختبار',
    lines: lines,
  );
}

MoveLineDraft line(int accountId,
        {required int debit, required int credit, int? partyId}) =>
    MoveLineDraft(
        accountId: accountId, debitMinor: debit, creditMinor: credit, partyId: partyId);

void main() {
  group('الدليل الافتراضي (03 §3) — بيانات الإعداد المعتمدة', () {
    test('58 حساباً بأكواد وأسماء موثقة — لا أكثر ولا أقل', () {
      expect(defaultChartOfAccounts, hasLength(58));
      final codes = defaultChartOfAccounts.map((a) => a.code).toSet();
      expect(codes, hasLength(58), reason: 'لا تكرار بالأكواد');
      expect(
        codes,
        containsAll([
          '1', '1111', '112', '113', '121', '211', '311', '321', '331',
          '332', '411', '412', '42', '43', '44', '51', '53', '549', '55',
          '56', '57', '58', '598',
        ]),
      );
    });

    test('كل أب موجود قبل أبنائه — البذر يصلح أباً', () {
      final seen = <String>{};
      for (final spec in defaultChartOfAccounts) {
        if (spec.parentCode != null) {
          expect(seen, contains(spec.parentCode),
              reason: 'الأب ${spec.parentCode} يسبق ابنه ${spec.code}');
        }
        seen.add(spec.code);
      }
    });

    test('المعلن الورقي يطابق المحسوب من الأبناء — لا تناقض بالبيانات', () {
      final parents = defaultChartOfAccounts
          .where((a) => a.parentCode != null)
          .map((a) => a.parentCode!)
          .toSet();
      for (final spec in defaultChartOfAccounts) {
        expect(spec.isLeaf, isNot(parents.contains(spec.code)),
            reason: '${spec.code}: الورقية المعلنة تطابق غياب الأبناء');
      }
    });

    test('الحسابات العكسية الثلاثة بطبيعتها المعاكسة لنوعها (03 §1-4)', () {
      AccountSpec byCode(String code) => defaultChartOfAccounts
          .firstWhere((a) => a.code == code, orElse: () => throw StateError(code));
      expect(byCode('42').effectiveNormalSide, NormalSide.debit,
          reason: '42 مردودات المبيعات income مدينها');
      expect(byCode('321').effectiveNormalSide, NormalSide.debit,
          reason: '321 المسحوبات equity مدينها');
      expect(byCode('53').effectiveNormalSide, NormalSide.credit,
          reason: '53 مردودات المشتريات expense دائنها');
    });

    test('الجاهز معطّل منذ اليوم الأول (03 §1-5): 121/213/214/44/52/55', () {
      final inactive = defaultChartOfAccounts
          .where((a) => !a.isActive)
          .map((a) => a.code)
          .toSet();
      expect(inactive, {'121', '213', '214', '44', '52', '55'});
    });

    test('الدفاتر الخمسة (05 §3.4) بأكوادها', () {
      expect(defaultJournals, hasLength(5));
      expect(defaultJournals.map((j) => j.code).toSet(),
          {'sales', 'purchase', 'cash', 'stock', 'general'});
    });
  });

  group('الترقيم (07 §1.9/D-071 — الصيغة الكاملة م-44)', () {
    test('الرقم التالي يتقدم ولا يعاد أبداً', () {
      expect(nextSequenceNumber(0), 1);
      expect(nextSequenceNumber(6), 7);
    });

    test('الصيغة «قيد عام 2026/000001» — مبطنة 6 مواضع', () {
      expect(formatSequenceLabel('قيد عام', 2026, 1), 'قيد عام 2026/000001');
      expect(formatSequenceLabel('قيد عام', 2026, 12345),
          'قيد عام 2026/012345');
      expect(formatSequenceLabel('قيد عام', 2026, 1234567),
          'قيد عام 2026/1234567');
    });
  });

  group('التواريخ ISO (D-077)', () {
    test('الصالح يقبل والناقص يرفض', () {
      expect(isValidIsoDate('2026-10-30'), isTrue);
      expect(isValidIsoDate('2026-01-01'), isTrue);
      expect(isValidIsoDate('2026-10-3'), isFalse);
      expect(isValidIsoDate('30/10/2026'), isFalse);
      expect(isValidIsoDate('2026-13-01'), isFalse);
      expect(isValidIsoDate('2026-00-10'), isFalse);
      expect(isValidIsoDate(''), isFalse);
    });

    test('سنة ISO للمفتاح السنوي للترقيم', () {
      expect(yearOfIsoDate('2026-10-30'), 2026);
    });

    test('الفترة الحاضنة أول من يضم التاريخ', () {
      final periods = [
        const PeriodInfo(
            id: 1,
            fiscalYearId: 1,
            startDateText: '2026-01-01',
            endDateText: '2026-01-31',
            isOpen: true),
        const PeriodInfo(
            id: 2,
            fiscalYearId: 1,
            startDateText: '2026-02-01',
            endDateText: '2026-02-28',
            isOpen: false),
      ];
      expect(findPeriodForDate(periods, '2026-01-15')?.id, 1);
      expect(findPeriodForDate(periods, '2026-02-20')?.id, 2);
      expect(findPeriodForDate(periods, '2026-03-01'), isNull);
      expect(findPeriodForDate(periods, '2025-12-31'), isNull);
    });
  });

  group('مدقق المسودة (س-44/س-45) — التسلسل التدريجي', () {
    test('قيد متوازن سطرين يُقبل', () {
      // مسحوبات المالك: 321 مدين / 1111 دائن (مثال 03 §4)
      final errors = validateMoveDraft(
        draft(lines: [
          line(1, debit: 50000, credit: 0),
          line(2, debit: 0, credit: 50000),
        ]),
        index: smallIndex(),
      );
      expect(errors, isEmpty);
    });

    test('غير متوازن يرفض بحاملي الطرفين', () {
      final errors = validateMoveDraft(
        draft(lines: [
          line(2, debit: 50000, credit: 0),
          line(3, debit: 0, credit: 40000),
        ]),
        index: smallIndex(),
      );
      expect(errors, hasLength(1));
      final error = errors.first as MoveUnbalanced;
      expect(error.debitTotalMinor, 50000);
      expect(error.creditTotalMinor, 40000);
      expect(describeMoveValidationError(error), contains('50000'));
    });

    test('سطر واحد يرفض (05 §7-1)', () {
      final errors = validateMoveDraft(
        draft(lines: [line(2, debit: 50000, credit: 0)]),
        index: smallIndex(),
      );
      expect(errors, contains(const MoveTooFewLines()));
    });

    test('سطر على الجانبين معاً يرفض', () {
      final errors = validateMoveDraft(
        draft(lines: [
          line(2, debit: 100, credit: 100),
          line(3, debit: 100, credit: 100),
        ]),
        index: smallIndex(),
      );
      expect(errors.whereType<MoveLineBothSides>(), hasLength(2));
    });

    test('سطر بلا جانب يرفض', () {
      final errors = validateMoveDraft(
        draft(lines: [
          line(2, debit: 100, credit: 0),
          line(3, debit: 0, credit: 0),
        ]),
        index: smallIndex(),
      );
      expect(errors.whereType<MoveLineEmptySide>(), hasLength(1));
    });

    test('مبلغ سالب يرفض قبل فحص الأطراف', () {
      final errors = validateMoveDraft(
        draft(lines: [
          line(2, debit: -100, credit: 0),
          line(3, debit: 0, credit: -100),
        ]),
        index: smallIndex(),
      );
      expect(errors.whereType<MoveLineAmountInvalid>(), hasLength(2));
    });

    test('الحساب الأب (غير الورقي) يرفض بعرضه «الاسم (الكود)»', () {
      final errors = validateMoveDraft(
        draft(lines: [
          line(4, debit: 100, credit: 0), // الأب «1»
          line(3, debit: 0, credit: 100),
        ]),
        index: smallIndex(),
      );
      expect(errors, hasLength(1));
      final error = errors.first as MoveAccountNotLedgerable;
      expect(error.accountLabel, 'حساب 1 (1)');
      expect(describeMoveValidationError(error), contains('ورقياً'));
    });

    test('الحساب المفعَّل صفر (معطّل) يرفض', () {
      final index = LedgerAccountIndex.build([
        acc(7, '541', type: AccountType.expense, active: false),
        acc(2, '1111', type: AccountType.asset),
      ]);
      final errors = validateMoveDraft(
        draft(lines: [
          line(7, debit: 100, credit: 0),
          line(2, debit: 0, credit: 100),
        ]),
        index: index,
      );
      expect(errors.whereType<MoveAccountNotLedgerable>(), hasLength(1));
    });

    test('حساب غير موجود بالفهرس يرفض', () {
      final errors = validateMoveDraft(
        draft(lines: [
          line(99, debit: 100, credit: 0),
          line(2, debit: 0, credit: 100),
        ]),
        index: smallIndex(),
      );
      expect(errors.whereType<MoveAccountNotLedgerable>(), hasLength(1));
    });

    test('تاريخ غير ISO يرفض أول ترتيب المدقق', () {
      final errors = validateMoveDraft(
        draft(
          date: '10/30/2026',
          lines: [
            line(2, debit: 100, credit: 0),
            line(3, debit: 0, credit: 100),
          ],
        ),
        index: smallIndex(),
      );
      expect(errors, hasLength(1));
      expect(errors.first, isA<MoveDateInvalid>());
    });
  });

  group('المدقق الحاكم عند الترحيل (س-49) — الزمن المحاسبي', () {
    final openPeriods = [
      const PeriodInfo(
          id: 1,
          fiscalYearId: 1,
          startDateText: '2026-01-01',
          endDateText: '2026-01-31',
          isOpen: true),
      const PeriodInfo(
          id: 2,
          fiscalYearId: 1,
          startDateText: '2026-02-01',
          endDateText: '2026-02-28',
          isOpen: false),
    ];

    final balanced = draft(lines: [
      line(1, debit: 100, credit: 0),
      line(2, debit: 0, credit: 100),
    ]);

    test('فترة مفتوحة يُقبل', () {
      expect(
        validateMoveForPosting(draft(date: '2026-01-20', lines: balanced.lines),
            index: smallIndex(), periods: openPeriods),
        isEmpty,
      );
    });

    test('فترة مقفلة يرفض (07 §1.5: لا ترحيل فيها)', () {
      final errors = validateMoveForPosting(
          draft(date: '2026-02-20', lines: balanced.lines),
          index: smallIndex(),
          periods: openPeriods);
      expect(errors, hasLength(1));
      expect(errors.first, isA<MoveClosedPeriod>());
      expect(describeMoveValidationError(errors.first), contains('مقفلة'));
    });

    test('خارج كل الفترات يرفض', () {
      final errors = validateMoveForPosting(
          draft(date: '2026-03-15', lines: balanced.lines),
          index: smallIndex(),
          periods: openPeriods);
      expect(errors.first, isA<MoveNoPeriod>());
    });
  });

  group('القيد العكس (07 §1.3/س-48)', () {
    test('الأسطر تتقابل جانباً بجانب ومرجع الأصل محفوظ', () {
      final original = [
        const LedgerLine(
            moveId: 9, accountId: 2, debitMinor: 70000, creditMinor: 0),
        const LedgerLine(
            moveId: 9, accountId: 4, debitMinor: 0, creditMinor: 70000),
      ];
      final reversal = buildReversalMoveDraft(
        journalId: 5,
        originalLines: original,
        originalLabel: '2026/000001',
        reversalDateText: '2026-10-30',
        originalMoveId: 9,
      );
      expect(reversal.journalId, 5);
      expect(reversal.refDocType, 'move');
      expect(reversal.refDocId, 9);
      expect(reversal.narration, 'عكس قيد 2026/000001');
      expect(reversal.lines, hasLength(2));
      expect(reversal.lines[0].accountId, 2);
      expect(reversal.lines[0].debitMinor, 0);
      expect(reversal.lines[0].creditMinor, 70000);
      expect(reversal.lines[1].accountId, 4);
      expect(reversal.lines[1].debitMinor, 70000);
      expect(reversal.lines[1].creditMinor, 0);
      // العكس نفسه متوازن — يمر بالمدقق نفسه
      expect(
        validateMoveDraft(reversal, index: smallIndex()),
        isEmpty,
      );
    });

    test('وصف مخصص يحمل العبارة المعطاة', () {
      final reversal = buildReversalMoveDraft(
        journalId: 5,
        originalLines: const [
          LedgerLine(moveId: 9, accountId: 2, debitMinor: 1, creditMinor: 0),
          LedgerLine(moveId: 9, accountId: 4, debitMinor: 0, creditMinor: 1),
        ],
        originalLabel: '2026/000007',
        reversalDateText: '2026-11-01',
        originalMoveId: 9,
        narration: 'عكس خطأ إدخال رقم الصندوق',
      );
      expect(reversal.narration, 'عكس خطأ إدخال رقم الصندوق');
    });
  });

  group('الأرصدة والميزان (س-50)', () {
    test('رصيد الحساب المدين الطبيعي = المدين − الدائن', () {
      final account = acc(2, '1111', type: AccountType.asset);
      final balance = computeAccountBalance([
        const LedgerLine(moveId: 1, accountId: 2, debitMinor: 500, creditMinor: 0),
        const LedgerLine(moveId: 2, accountId: 2, debitMinor: 0, creditMinor: 200),
      ], account);
      expect(balance, 300);
    });

    test('رصيد الحساب الدائن الطبيعي = الدائن − المدين', () {
      final account = acc(6, '211', type: AccountType.liability);
      final balance = computeAccountBalance([
        const LedgerLine(moveId: 1, accountId: 6, debitMinor: 100, creditMinor: 900),
      ], account);
      expect(balance, 800);
    });

    test('الرصيد السالب مشروع للعكسية — يظل على جانبه الطبيعي', () {
      final account =
          acc(5, '42', type: AccountType.income, side: NormalSide.debit);
      final balance = computeAccountBalance([
        const LedgerLine(moveId: 1, accountId: 5, debitMinor: 100, creditMinor: 400),
      ], account);
      expect(balance, -300);
    });

    test('ميزان المراجعة الافتراضي يتوازن بالبناء', () {
      final (debit, credit) = trialBalanceTotals([
        const LedgerLine(moveId: 1, accountId: 2, debitMinor: 1000, creditMinor: 0),
        const LedgerLine(moveId: 1, accountId: 3, debitMinor: 0, creditMinor: 400),
        const LedgerLine(moveId: 1, accountId: 6, debitMinor: 0, creditMinor: 600),
      ]);
      expect(debit, 1000);
      expect(credit, 1000);
    });
  });
}
