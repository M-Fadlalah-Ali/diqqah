import 'dart:convert';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات الدفعة الثالثة من استيراد البيانات — التشطيب: الوحدة 3
/// «كميات المخزون الافتتاحية» (D-208/§25.2 — س142): سبعة أعمدة بمرآة
/// قسم المخزون بالوحدة 5، والكمية صحيحة أساسية موجبة والقيمة موجبة
/// غير صفرية بلقطة سعرها وتحويلها التام (لا تقريب صامت)، والافتتاحي
/// أول المرحّل (د-6)، والتكرار الداخلي فادح، والإرفاق والإنشاء الآلي
/// — والمقابل 43 الافتراضي (F-209) لا 332 الافتتاحي.
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

  List<int> qtyBytes(List<String> rows) => utf8.encode([
        'dq-import:opening_qty,1',
        'كود الصنف,الاسم,الكمية,القيمة,الوحدة,العملة,سعر الصرف',
        ...rows,
      ].join('\n'));

  group('القالب الخامس — الترويسة والأعمدة (§25.4)', () {
    test('سبعة أعمدة حرفاً والفارغ المولَّد بترويسته', () {
      final t = importTemplateOf(ImportTemplateId.openingQty)!;
      expect(t.columnCount, 7);
      expect(t.code, 'opening_qty');
      expect(t.markerLine, 'dq-import:opening_qty,1');
      final empty = buildEmptyTemplateCsv(ImportTemplateId.openingQty);
      expect(empty, contains('dq-import:opening_qty,1'));
      expect(empty, contains('كود الصنف'));
      expect(empty, contains('الوحدة'));
    });

    test('القالب المفتوح بوحدة أخرى رفض DQ-1018 — لا تلاعب بالوحدة', () {
      final bytes = utf8.encode([
        'dq-import:opening_full,1',
        'القسم,الكود,الاسم,النوع,الكمية,القيمة,الوحدة,العملة,سعر الصرف',
        'مخزون,SKU1,صنف أول,,10,5000,قطعة,SYP,',
      ].join('\n'));
      final parse = parseOpeningQtyFile(bytes);
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportTemplateUnknown);
    });

    test('الإصدار المخالف رفض DQ-1018 — تأمين مستقبلي رخيص', () {
      final bytes = utf8.encode([
        'dq-import:opening_qty,2',
        'كود الصنف,الاسم,الكمية,القيمة,الوحدة,العملة,سعر الصرف',
        'SKU1,صنف أول,10,5000,قطعة,SYP,',
      ].join('\n'));
      final parse = parseOpeningQtyFile(bytes);
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportTemplateUnknown);
    });

    test('الفاصل المنقوطة يُكتشف بإشعاره — د-5', () {
      final bytes = utf8.encode([
        'dq-import:opening_qty,1',
        'كود الصنف؛الاسم؛الكمية؛القيمة؛الوحدة؛العملة؛سعر الصرف',
        'SKU1؛صنف أول؛10؛5000؛قطعة؛SYP؛',
      ].join('\n'));
      final parse = parseOpeningQtyFile(bytes);
      expect(parse.semicolonUsed, isTrue);
      expect(parse.isRejected, isFalse, reason: parse.errors.toString());
    });

    test('الملف بلا صفوف بيانات رفض صريح — القالب الفارغ لا يُعتمد',
        () {
      final parse = parseOpeningQtyFile(qtyBytes(const []));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportRowInvalid);
      expect(parse.errors.single.description, contains('بلا صفوف بيانات'));
    });
  });

  group('تحليل الصفوف — معايير قسم المخزون (بلا تخمين)', () {
    test('الصف السليم يُحلل: أساسي ولأجنبي بلقطة سعره', () {
      final parse = parseOpeningQtyFile(qtyBytes([
        'SKU1,صنف أول,10,5000,قطعة,SYP,',
        'SKU2,صنف ثانٍ,3,100,كرتون,USD,15000',
      ]));
      expect(parse.isRejected, isFalse, reason: parse.errors.toString());
      expect(parse.rows, hasLength(2));
      expect(parse.rows.last.fxRateRaw, '15000');
    });

    test('الكود الفارغ أو خارج القائمة البيضاء رفض', () {
      final empty = parseOpeningQtyFile(qtyBytes([
        ',صنف بلا كود,10,5000,قطعة,SYP,',
      ]));
      expect(empty.isRejected, isTrue);
      expect(empty.errors.single.column, 1);
      expect(empty.errors.single.description, contains('إلزامي'));

      final bad = parseOpeningQtyFile(qtyBytes([
        'SKU 1,صنف بفراغ بالكود,10,5000,قطعة,SYP,',
      ]));
      expect(bad.isRejected, isTrue);
      expect(bad.errors.single.column, 1);
    });

    test('الاسم الفارغ رفض والاسم بمحارف تحكم خفية رفض (D-170)', () {
      final empty = parseOpeningQtyFile(qtyBytes([
        'SKU1,,10,5000,قطعة,SYP,',
      ]));
      expect(empty.isRejected, isTrue);
      expect(empty.errors.single.column, 2);

      final hidden = parseOpeningQtyFile(qtyBytes([
        'SKU1,صنف\u0000بمحرف خفي,10,5000,قطعة,SYP,',
      ]));
      expect(hidden.isRejected, isTrue);
      expect(hidden.errors.single.description, contains('تحكم'));
    });

    test('الكمية كسرية أو صفرية أو فاسدة مرفوضة — صحيح أساسي موجب حصراً',
        () {
      for (final qty in ['10.5', '0', 'عشرة']) {
        final parse = parseOpeningQtyFile(qtyBytes([
          'SKU1,صنف أول,$qty,5000,قطعة,SYP,',
        ]));
        expect(parse.isRejected, isTrue, reason: 'الكمية $qty');
        expect(parse.errors.single.column, 3);
        expect(parse.errors.single.description, contains('صحيح'));
      }
    });

    test('القيمة الصفرية أو السالبة أو الفاسدة مرفوضة — تاريخية صريحة',
        () {
      for (final value in ['0', '-5000', 'بلا']) {
        final parse = parseOpeningQtyFile(qtyBytes([
          'SKU1,صنف أول,10,$value,قطعة,SYP,',
        ]));
        expect(parse.isRejected, isTrue, reason: 'القيمة $value');
        expect(parse.errors.single.column, 4);
        expect(parse.errors.single.description, contains('موجبة'));
      }
    });

    test('الوحدة الفارغة مرفوضة — أساسية تنشأ آلياً إن غابت بالتطبيق',
        () {
      final parse = parseOpeningQtyFile(qtyBytes([
        'SKU1,صنف أول,10,5000,,SYP,',
      ]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.column, 5);
      expect(parse.errors.single.description, contains('إلزامية'));
    });

    test('الأساسية بسعر مرفوضة والأجنبية بلا سعر مرفوضة (F-121)', () {
      final withRate = parseOpeningQtyFile(qtyBytes([
        'SKU1,صنف أول,10,5000,قطعة,SYP,15000',
      ]));
      expect(withRate.isRejected, isTrue);
      expect(withRate.errors.single.column, 7);
      expect(withRate.errors.single.description, contains('مقياس الكل'));

      final noRate = parseOpeningQtyFile(qtyBytes([
        'SKU1,صنف أول,10,100,كرتون,USD,',
      ]));
      expect(noRate.isRejected, isTrue);
      expect(noRate.errors.single.description, contains('إلزامي'));
    });
  });

  group('التخطيط — الإرفاق والإنشاء الآلي والتحويل التام', () {
    OpeningQtyImportPlan plan(List<String> rows,
        {ItemUniquenessIndex? existing,
        Map<int, ExistingItemImportRef> details = const {},
        UnitUniquenessIndex? units,
        OpeningImportDateContext? context,
        Map<String, int> latest = const {}}) {
      return planOpeningQtyImport(
        parseOpeningQtyFile(qtyBytes(rows)),
        currencies: currencies,
        existingItems: existing ?? ItemUniquenessIndex.build(const []),
        existingItemDetails: details,
        units: units ?? UnitUniquenessIndex.build(const []),
        dateContext: context ?? dateContext(),
        latestRateByCurrency: latest,
      );
    }

    test('التحويل تام بلقطة الملف: 100 دولار بـ15000 ليرة حرفاً', () {
      final p = plan(['SKU1,صنف أول,10,100,كرتون,USD,15000']);
      expect(p.isApprovable, isTrue, reason: p.errors.toString());
      final line = p.inventoryLines.single;
      expect(line.valueBaseMinor, 150000000,
          reason: '100.00 دولار × 15000 = 1,500,000.00 ليرة');
      expect(line.qtyBase, 10);
      expect(line.currencyId, 2);
      expect(line.fxRate, 15000 * 1000000);
      expect(p.receiptValueBaseMinor, 150000000);
    });

    test('الباقي بالقسمة رفض صريح — لا تقريب صامت', () {
      final p = plan(['SKU1,صنف أول,10,100.01,كرتون,USD,15000.5']);
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportRowInvalid);
      expect(p.errors.single.description, contains('غير تام'));
    });

    test('حرس الطفح: قيمة تبلغ حد الأعداد رفض بلا رياضة تلف', () {
      final p = plan(['SKU1,صنف أول,10,999999999999999,كرتون,USD,999999999']);
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportRowInvalid);
    });

    test('الصنف والوحدة الغائبان يُنشآن آلياً مرة واحدة (§25.2)', () {
      final p = plan([
        'SKU1,صنف أول,10,5000,قطعة,SYP,',
        'SKU2,صنف ثانٍ,5,2500,قطعة,SYP,',
      ]);
      expect(p.isApprovable, isTrue, reason: p.errors.toString());
      expect(p.itemCreates.map((c) => c.sku), ['SKU1', 'SKU2']);
      expect(p.unitCreates, ['قطعة'],
          reason: 'الوحدة نفسها لا تنشأ مرتين');
      expect(p.inventoryLines, hasLength(2));
      expect(p.receiptValueBaseMinor, 750000);
    });

    test('الصنف القائم يُرفق به ووحدته المتباينة فرق معروض لا رفض', () {
      final existing = ItemUniquenessIndex.build([
        const ExistingItem(id: 5, sku: 'SKU1', name: 'صنف قائم',
            isActive: true),
      ]);
      final p = plan(['SKU1,صنف قائم,10,5000,كرتون,SYP,'],
          existing: existing,
          details: {
            5: const ExistingItemImportRef(
                id: 5, sku: 'SKU1', name: 'صنف قائم', unitName: 'قطعة',
                purchasePriceMinor: 0, salePriceMinor: 0,
                priceCurrencyId: 1),
          });
      expect(p.isApprovable, isTrue, reason: p.errors.toString());
      expect(p.itemCreates, isEmpty);
      expect(p.inventoryLines.single.itemId, 5);
      expect(p.differences.single.columnKey, 'unit');
      expect(p.differences.single.updated, isFalse);
    });

    test('التكرار الداخلي بالكود وبالاسم فادح DQ-1022', () {
      final bySku = plan([
        'SKU1,صنف أول,10,5000,قطعة,SYP,',
        'SKU1,صنف آخر,5,2500,قطعة,SYP,',
      ]);
      expect(bySku.isApprovable, isFalse);
      expect(bySku.errors.single.dqCode, dqImportInternalDuplicate);

      final byName = plan([
        'SKU1,صنف أول,10,5000,قطعة,SYP,',
        'SKU2,صنف أول,5,2500,قطعة,SYP,',
      ]);
      expect(byName.isApprovable, isFalse);
      expect(byName.errors.single.dqCode, dqImportInternalDuplicate);
    });

    test('الاسم المتصادم مع صنف قائم مرفوض DQ-1023', () {
      final existing = ItemUniquenessIndex.build([
        const ExistingItem(id: 9, sku: 'X999', name: 'صنف أول',
            isActive: true),
      ]);
      final p = plan(['SKU1,صنف أول,10,5000,قطعة,SYP,'],
          existing: existing);
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportConflictExisting);
    });

    test('عملة غير معرفة بالتطبيق رفض DQ-1021', () {
      final p = plan(['SKU1,صنف أول,10,100,كرتون,EUR,15000']);
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportReferenceMissing);
    });

    test('انحراف السعر عن آخر مسجل تحذير معاينة لا رفض (§25.4)', () {
      final p = plan(['SKU1,صنف أول,10,100,كرتون,USD,20000'],
          latest: {'USD': 15000 * 1000000});
      expect(p.isApprovable, isTrue);
      expect(p.warnings.single, contains('يباعد'));
    });

    test('تاريخ غير ISO أو بلا فترة مفتوحة — DQ-1026 برسالتين', () {
      final bad = plan(['SKU1,صنف أول,10,5000,قطعة,SYP,'],
          context: dateContext(date: '2026-1-1'));
      expect(bad.isApprovable, isFalse);
      expect(bad.errors.single.dqCode, dqImportOpeningDateInvalid);

      final closed = <PeriodInfo>[
        const PeriodInfo(
            id: 2, fiscalYearId: 1, startDateText: '2026-01-01',
            endDateText: '2026-12-31', isOpen: false),
      ];
      final noOpen = plan(['SKU1,صنف أول,10,5000,قطعة,SYP,'],
          context: dateContext(periods: closed));
      expect(noOpen.isApprovable, isFalse);
      expect(noOpen.errors.single.dqCode, dqImportOpeningDateInvalid);
      expect(noOpen.errors.single.description, contains('مقفلة'));
    });

    test('قيد مرحّل سابق للتاريخ — DQ-1025: الافتتاحي أول المرحّل', () {
      final p = plan(['SKU1,صنف أول,10,5000,قطعة,SYP,'],
          context: dateContext(earliestPosted: '2026-01-01'));
      expect(p.isApprovable, isFalse);
      expect(p.errors.single.dqCode, dqImportOpeningNotFirst);
    });
  });
}
