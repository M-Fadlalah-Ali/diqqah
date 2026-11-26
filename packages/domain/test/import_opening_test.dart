import 'dart:convert';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات الدفعة الثانية من استيراد البيانات — أرصدة أول المدة
/// (D-208/§25.11 — س141): قالبا الوحدتين 4 و5 وترويستهما بالشرطة
/// السفلية (درس س141)، والأرصدة الموقّعة، ولقطة السعر ودقة التحويل
/// التام (لا تقريب صامت — الباقي رفض والطفح حرس)، وفحصا تاريخ
/// الافتتاحي (DQ-1025/DQ-1026 — د-6)، والقسم يحكم أعمدة الأرصدة
/// الكاملة بلا تخمين.
void main() {
  final currencies = <String, ImportCurrencyRef>{
    'SYP': const ImportCurrencyRef(id: 1, code: 'SYP', minorUnits: 2),
    'USD': const ImportCurrencyRef(id: 2, code: 'USD', minorUnits: 2),
  };

  final openPeriods = <PeriodInfo>[
    const PeriodInfo(
        id: 1, fiscalYearId: 1, startDateText: '2026-01-01',
        endDateText: '2026-12-31', isOpen: true),
  ];

  OpeningImportDateContext dateContext({String date = '2026-01-01',
      List<PeriodInfo>? periods, String? earliestPosted}) =>
      OpeningImportDateContext(
        openingDateText: date,
        periods: periods ?? openPeriods,
        earliestPostedDateText: earliestPosted,
      );

  List<int> partyBalancesBytes(List<String> rows) => utf8.encode([
        'dq-import:party_balances,1',
        'الكود,الاسم,النوع,الرصيد,العملة,سعر الصرف',
        ...rows,
      ].join('\n'));

  List<int> openingFullBytes(List<String> rows) => utf8.encode([
        'dq-import:opening_full,1',
        'القسم,الكود,الاسم,النوع,الكمية,القيمة,الوحدة,العملة,سعر الصرف',
        ...rows,
      ].join('\n'));

  group('القوالب الجديدة — الترويسة والأعمدة (§25.4)', () {
    test('ترويسة القالبين بالشرطة السفلية تُقبل — الكود بنية لا نص حر',
        () {
      final parse = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل,1500,SYP,',
      ]));
      expect(parse.isRejected, isFalse, reason: 'party_balances تُقرأ');
      final full = parseOpeningFullFile(openingFullBytes([
        'ذمم,C001,علي,عميل,,1000,,SYP,',
      ]));
      expect(full.isRejected, isFalse, reason: 'opening_full تُقرأ');
    });

    test('القالب المفتوح بوحدة أخرى رفض DQ-1018 — لا تлаعب بالوحدة', () {
      final parse = parsePartyBalancesFile(openingFullBytes([
        'ذمم,C001,علي,عميل,,1000,,SYP,',
      ]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportTemplateUnknown);
    });

    test('الإصدار المخالف رفض DQ-1018 — تأمين مستقبلي رخيص', () {
      final bytes = utf8.encode([
        'dq-import:party_balances,2',
        'الكود,الاسم,النوع,الرصيد,العملة,سعر الصرف',
        'C001,علي,عميل,1500,SYP,',
      ].join('\n'));
      final parse = parsePartyBalancesFile(bytes);
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportTemplateUnknown);
    });

    test('القالبان ستة وتسعة أعمدة حرفاً والفارغ المولَّد بترويسته',
        () {
      expect(importTemplateOf(ImportTemplateId.partyBalances)!.columnCount,
          6);
      expect(importTemplateOf(ImportTemplateId.openingFull)!.columnCount, 9);
      final empty = buildEmptyTemplateCsv(ImportTemplateId.partyBalances);
      expect(empty, contains('dq-import:party_balances,1'));
      expect(empty, contains('سعر الصرف'));
      final emptyFull = buildEmptyTemplateCsv(ImportTemplateId.openingFull);
      expect(emptyFull, contains('dq-import:opening_full,1'));
      expect(emptyFull, contains('القسم'));
    });

    test('الفاصل المنقوطة يُكتشف بإشعاره — د-5 بالقالبين الجديدين', () {
      final bytes = utf8.encode([
        'dq-import:party_balances,1',
        'الكود؛الاسم؛النوع؛الرصيد؛العملة؛سعر الصرف',
        'C001؛علي؛عميل؛1500؛SYP؛',
      ].join('\n'));
      final parse = parsePartyBalancesFile(bytes);
      expect(parse.semicolonUsed, isTrue);
      expect(parse.isRejected, isFalse);
    });

    test('الملف بلا صفوف بيانات رفض صريح — القالب الفارغ لا يُعتمد', () {
      final parse = parsePartyBalancesFile(partyBalancesBytes(const []));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportRowInvalid);
      expect(parse.errors.single.description, contains('بلا صفوف بيانات'));
    });
  });

  group('تحليل أرصدة الذمم — الوحدة 4 (§25.2)', () {
    test('الصف السليم يُحلل: عميل موجب ومورد بالدولار بلقطة سعره', () {
      final parse = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل,1500,SYP,',
        'S001,مصنع,مورد,100,USD,15000',
      ]));
      expect(parse.isRejected, isFalse);
      expect(parse.rows, hasLength(2));
      expect(parse.rows.last.fxRateRaw, '15000');
    });

    test('الرصيد السالب مقبول — عميل برصيد دائن (§25.4)', () {
      final parse = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل,-2500,SYP,',
      ]));
      expect(parse.isRejected, isFalse);
      expect(parse.rows.single.balanceRaw, '-2500');
    });

    test('الرصيد الصفر مرفوض — لا أثر محاسبي له', () {
      final parse = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل,0,SYP,',
      ]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportRowInvalid);
    });

    test('«عميل ومورد معاً» مرفوض صراحة — الرصيد جهة واحدة', () {
      final parse = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل ومورد معاً,1500,SYP,',
      ]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.description, contains('جهة واحدة'));
    });

    test('العملة الأساسية بسعر مرفوضة والأجنبية بلا سعر مرفوضة', () {
      final withRate = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل,1500,SYP,15000',
      ]));
      expect(withRate.isRejected, isTrue);
      expect(withRate.errors.single.dqCode, dqImportRowInvalid);
      final noRate = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل,100,USD,',
      ]));
      expect(noRate.isRejected, isTrue);
      expect(noRate.errors.single.description, contains('إلزامي'));
    });

    test('السعر الفاسد أو فائق دقة اللقطة (6 خانات) مرفوض', () {
      final parse = parsePartyBalancesFile(partyBalancesBytes([
        'C001,علي,عميل,100,USD,0.0000001',
      ]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportRowInvalid);
    });
  });

  group('تخطيط أرصدة الذمم — التحويل التام والإرفاق (د-1/د-6)', () {
    PartyBalancesImportPlan plan(List<String> rows,
        {PartyUniquenessIndex? existing,
        Map<String, String> kinds = const {},
        OpeningImportDateContext? context,
        Map<String, int> latest = const {}}) {
      return planPartyBalancesImport(
        parsePartyBalancesFile(partyBalancesBytes(rows)),
        currencies: currencies,
        existing: existing ?? PartyUniquenessIndex.build(const []),
        dateContext: context ?? dateContext(),
        existingKindByNumberKey: kinds,
        latestRateByCurrency: latest,
      );
    }

    test('التحويل تام بلقطة الملف: 100 دولار بـ15000 ليرة حرفاً', () {
      final p = plan(['C001,علي,عميل,100,USD,15000']);
      expect(p.isApprovable, isTrue);
      final line = p.lines.single;
      expect(line.docMinor, 10000, reason: '100.00 دولار');
      expect(line.fxRate, 15000 * 1000000);
      expect(line.baseMinor, 150000000, reason: '1,500,000.00 ليرة');
      expect(line.debit, isTrue, reason: 'عميل موجب مدين (112)');
    });

    test('الباقي بالقسمة رفض صريح — لا تقريب صامت', () {
      final p = plan(['C001,علي,عميل,0.01,USD,15000.5']);
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportRowInvalid);
      expect(p.errors.single.description, contains('غير تام'));
    });

    test('حرس الطفح: قيمة تبلغ حد الأعداد رفض بلا رياضة تلف', () {
      final p = plan(['C001,علي,عميل,999999999999999,USD,999999999']);
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportRowInvalid);
    });

    test('الطرف القائم يُرفق به وفرق نوعه المتباين يُعرض لا يرفض', () {
      final existing = PartyUniquenessIndex.build([
        const ExistingParty(id: 7, number: 'C001', name: 'علي القديم',
            isActive: true),
      ]);
      final p = plan(['C001,علي,عميل,1500,SYP,'],
          existing: existing, kinds: {partyNumberKey('C001'): 'supplier'});
      expect(p.isApprovable, isTrue);
      expect(p.lines.single.partyId, 7);
      expect(p.partyCreates, isEmpty);
      expect(p.differences.single.columnKey, 'kind');
      expect(p.differences.single.updated, isFalse);
    });

    test('الطرف الغائب يُنشأ آلياً والاسم المتصادم مرفوض DQ-1023', () {
      final p = plan(['C001,علي,عميل,1500,SYP,']);
      expect(p.partyCreates.single.number, 'C001');
      expect(p.lines.single.partyId, isNull);

      final existing = PartyUniquenessIndex.build([
        const ExistingParty(id: 9, number: 'X999', name: 'علي',
            isActive: true),
      ]);
      final conflict = plan(['C001,علي,عميل,1500,SYP,'], existing: existing);
      expect(conflict.isApprovable, isFalse);
      expect(conflict.errors.single.dqCode, dqImportConflictExisting);
    });

    test('التكرار الداخلي بالكود فادح DQ-1022', () {
      final p = plan([
        'C001,علي,عميل,1500,SYP,',
        'C001,علي الثاني,عميل,500,SYP,',
      ]);
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportInternalDuplicate);
    });

    test('تاريخ غير ISO أو بلا فترة مفتوحة — DQ-1026 برسالتين', () {
      final bad = plan(['C001,علي,عميل,1500,SYP,'],
          context: dateContext(date: '2026-1-1'));
      expect(bad.isApprovable, isFalse);
      expect(bad.errors.single.dqCode, dqImportOpeningDateInvalid);

      final closed = <PeriodInfo>[
        const PeriodInfo(
            id: 2, fiscalYearId: 1, startDateText: '2026-01-01',
            endDateText: '2026-12-31', isOpen: false),
      ];
      final noOpen = plan(['C001,علي,عميل,1500,SYP,'],
          context: dateContext(periods: closed));
      expect(noOpen.isApprovable, isFalse);
      expect(noOpen.errors.single.dqCode, dqImportOpeningDateInvalid);
      expect(noOpen.errors.single.description, contains('مقفلة'));
    });

    test('قيد مرحّل سابق للتاريخ — DQ-1025: الافتتاحي أول المرحّل', () {
      final p = plan(['C001,علي,عميل,1500,SYP,'],
          context: dateContext(earliestPosted: '2026-01-01'));
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportOpeningNotFirst);
    });

    test('المقابل 332 يمسك التوازن والسالب المعكوس تحذير مراجعة', () {
      final p = plan([
        'C001,علي,عميل,1000,SYP,',
        'C002,سامر,عميل,-400,SYP,',
        'S001,مصنع,مورد,300,SYP,',
      ]);
      expect(p.isApprovable, isTrue);
      expect(p.debitBaseMinor, 100000);
      expect(p.creditBaseMinor, 70000);
      expect(p.counterpartBaseMinor, 30000, reason: '332 دائناً بالفرق');
      expect(p.warnings, isNotEmpty, reason: 'الرصيد السالب يحذَّر لا يرفض');
      expect(p.totalsByCurrencyDocMinor()['SYP'], 170000);
    });

    test('انحراف السعر عن آخر مسجل تحذير معاينة لا رفض (§25.4)', () {
      final p = plan(['C001,علي,عميل,100,USD,20000'],
          latest: {'USD': 15000 * 1000000});
      expect(p.isApprovable, isTrue);
      expect(p.warnings.single, contains('يباعد'));
    });
  });

  group('الأرصدة الكاملة — الوحدة 5 (القسم يحكم الأعمدة)', () {
    test('الأقسام الثلاثة تُحلل بقيمها بلا تخمين', () {
      final parse = parseOpeningFullFile(openingFullBytes([
        'ذمم,C001,علي,عميل,,1000,,SYP,',
        'مخزون,SKU1,صنف أول,,10,5000,قطعة,SYP,',
        'نقد,USD,,,,5000,,USD,15000',
      ]));
      expect(parse.isRejected, isFalse, reason: parse.errors.toString());
      expect(parse.rows, hasLength(3));
      expect(parse.rows.map((r) => r.section).toSet(),
          {'parties', 'inventory', 'cash'});
    });

    test('القسم المجهول مرفوض وأعمدة القسم الخطأ مرفوضة صراحة', () {
      final unknown = parseOpeningFullFile(openingFullBytes([
        'أصول,C001,علي,,,,,SYP,',
      ]));
      expect(unknown.isRejected, isTrue);
      expect(unknown.errors.first.dqCode, dqImportRowInvalid);

      final wrongColumn = parseOpeningFullFile(openingFullBytes([
        'ذمم,C001,علي,عميل,10,1000,,SYP,',
      ]));
      expect(wrongColumn.isRejected, isTrue);
      expect(wrongColumn.errors.first.description,
          contains('لقسم المخزون حصراً'));
    });

    test('الكمية كسرية مرفوضة وقيمة المخزون السالبة مرفوضة', () {
      final frac = parseOpeningFullFile(openingFullBytes([
        'مخزون,SKU1,صنف أول,,10.5,5000,قطعة,SYP,',
      ]));
      expect(frac.isRejected, isTrue);
      expect(frac.errors.first.description, contains('عدد صحيح'));

      final negative = parseOpeningFullFile(openingFullBytes([
        'مخزون,SKU1,صنف أول,,10,-5000,قطعة,SYP,',
      ]));
      expect(negative.isRejected, isTrue);
    });

    test('النقد: الكود عملة إلزامية مطابقة وتكرارها فادح', () {
      final mismatch = parseOpeningFullFile(openingFullBytes([
        'نقد,USD,,,,5000,,EUR,15000',
      ]));
      expect(mismatch.isRejected, isTrue);
      expect(mismatch.errors.first.description, contains('لا يختلفان'));
    });

    test('الصنف والوحدة يُنشآن آلياً والقيمة بالأساسية بلقطة سعرها', () {
      final p = planOpeningFullImport(
        parseOpeningFullFile(openingFullBytes([
          'مخزون,SKU1,صنف أول,,10,100,قطعة,USD,15000',
        ])),
        currencies: currencies,
        existingParties: PartyUniquenessIndex.build(const []),
        existingPartyKindByNumberKey: const {},
        existingItems: ItemUniquenessIndex.build(const []),
        existingItemDetails: const {},
        units: UnitUniquenessIndex.build(const []),
        dateContext: dateContext(),
      );
      expect(p.isApprovable, isTrue);
      expect(p.itemCreates.single.sku, 'SKU1');
      expect(p.itemCreates.single.baseUnitId, -1,
          reason: 'الوحدة من خطة الإنشاء');
      expect(p.unitCreates, ['قطعة']);
      expect(p.inventoryLines.single.valueBaseMinor, 150000000,
          reason: '100 دولار × 15000 = 1,500,000 ليرة (150M minor)');
      expect(p.inventoryLines.single.qtyBase, 10);
    });

    test('الصنف القائم يُرفق به ووحدته المتباينة فرق معروض، والنقد '
        'بجميع عملاته يمسك الميزان مع 332', () {
      final existingItems = ItemUniquenessIndex.build([
        const ExistingItem(id: 5, sku: 'SKU1', name: 'صنف قائم',
            isActive: true),
      ]);
      final p = planOpeningFullImport(
        parseOpeningFullFile(openingFullBytes([
          'ذمم,C001,علي,عميل,,1000,,SYP,',
          'مخزون,SKU1,صنف قائم,,10,5000,كرتون,SYP,',
          'نقد,SYP,,,,250000,,,',
          'نقد,USD,,,,100,,USD,15000',
        ])),
        currencies: currencies,
        existingParties: PartyUniquenessIndex.build(const []),
        existingPartyKindByNumberKey: const {},
        existingItems: existingItems,
        existingItemDetails: {
          5: const ExistingItemImportRef(
              id: 5, sku: 'SKU1', name: 'صنف قائم', unitName: 'قطعة',
              purchasePriceMinor: 0, salePriceMinor: 0, priceCurrencyId: 1),
        },
        units: UnitUniquenessIndex.build(const []),
        dateContext: dateContext(),
      );
      expect(p.isApprovable, isTrue, reason: p.errors.toString());
      expect(p.inventoryLines.single.itemId, 5);
      expect(p.differences.single.columnKey, 'unit');
      expect(p.receiptValueBaseMinor, 500000, reason: 'إذن الإدخال بقيمه');
      expect(p.cashLines, hasLength(2));
      expect(p.cashBaseMinor, 25000000 + 150000000);
      // قيد الذمم والنقد: مدين (ذمم 1000 + نقد 1,750,000 ليرة) ودائن
      // صفر والباقي مقابل 332 دائناً — فيمتسك القيد بمجموعه (07 §1.1).
      expect(p.counterpartBaseMinor, 175100000);
    });
  });
}
