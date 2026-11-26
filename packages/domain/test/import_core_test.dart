import 'dart:convert';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات دفعة استيراد البيانات الأولى — النواة (D-208/§25.11):
/// محلل المجال النقي والقوالب واستيراد الأطراف والأصناف.
///
/// العقد الموثق: الترميز صارم UTF-8 بابتلاع BOM (§25.4)، الفاصل فحص
/// بنيوي مرسى على عدد الأعمدة — فاصل واحد حصراً وإلا رفض بتوجيه عربي
/// (د-5)، القالب بترويسته المعرِّفة فغير المعروف رفض طبقة ملف،
/// وكل-أو-لا شيء بأي خطأ (§25.5)، والتحويل بشري ← minor بلا كسور
/// عائمة ولا تقريب صامت، وسياسة الموجود وصفيفات فقط في v1 (د-2).
void main() {
  const partiesLabels = 'الكود,الاسم,النوع,العملة,حد الائتمان';
  const itemsLabels =
      'كود الصنف,الاسم,الوحدة,عملة السعر,سعر الشراء,سعر البيع';

  List<int> bytesOf(List<String> lines, {bool bom = false}) {
    final body = lines.join('\n');
    final text = bom ? '$csvUtf8Bom$body' : body;
    return utf8.encode(text);
  }

  PartiesFileParse parseParties(List<String> rows) =>
      parsePartiesFile(bytesOf(['dq-import:parties,1', partiesLabels, ...rows]));

  ItemsFileParse parseItems(List<String> rows) =>
      parseItemsFile(bytesOf(['dq-import:items,1', itemsLabels, ...rows]));

  ImportCurrencyRef sypRef() => const ImportCurrencyRef(
      id: 1, code: 'SYP', minorUnits: 2);

  PartyUniquenessIndex emptyParties() => PartyUniquenessIndex.build(const []);

  group('طبقة الملف — الترميز والترويسة والفاصل (§25.4/د-5)', () {
    test('ملف أطراف سليم ثلاثة صفوف يُحلَّل كاملاً بلا رسائل', () {
      final parse = parseParties([
        'C001,علي أحمد,عميل,,',
        'C002,مؤمن يورو,عميل,USD,10000.5',
        'S-9,مورد الخضار,مورد,,',
      ]);
      expect(parse.isRejected, isFalse, reason: '${parse.errors}');
      expect(parse.rows, hasLength(3));
      expect(parse.rows[0].code, 'C001');
      expect(parse.rows[0].currencyCode, 'SYP', reason: 'الفراغ = الأساسية');
      expect(parse.rows[1].currencyCode, 'USD');
      expect(parse.rows[1].creditLimitRaw, '10000.5');
      expect(parse.rows[2].kindStorage, 'supplier');
    });

    test('BOM يُبتلع والملف يُقرأ (مرآة F-166)', () {
      final parse = parsePartiesFile(bytesOf(
        ['dq-import:parties,1', partiesLabels, 'C001,علي,عميل,,'],
        bom: true,
      ));
      expect(parse.isRejected, isFalse, reason: '${parse.errors}');
      expect(parse.rows, hasLength(1));
    });

    test('ترميز غير UTF-8 يُرفض برسالة الإنقاذ (DQ-1017) — لا تخمين',
        () {
      // بايتات Latin-1 بحرف غير UTF-8 سليم.
      final parse = parsePartiesFile([0xC1, 0xC2, 0xC3]);
      expect(parse.isRejected, isTrue);
      expect(parse.errors, hasLength(1));
      expect(parse.errors.single.dqCode, dqImportEncoding);
      expect(parse.errors.single.suggestedAction,
          contains('CSV UTF-8'));
    });

    test('قالب غير معروف يُرفض كخطأ طبقة الملف (DQ-1018)', () {
      final parse =
          parsePartiesFile(bytesOf(['dq-import:unknown,1', partiesLabels]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportTemplateUnknown);
    });

    test('ترويسة غائبة أصلاً تُرفض (DQ-1018)', () {
      final parse =
          parsePartiesFile(bytesOf(['C001,علي,عميل,,']));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportTemplateUnknown);
    });

    test('إصدار القالب المخالف يُرفض (DQ-1018)', () {
      final parse = parsePartiesFile(
          bytesOf(['dq-import:parties,2', partiesLabels]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportTemplateUnknown);
      expect(parse.errors.single.description, contains('v2'));
    });

    test('فاصل منقوطة يُكتشف ويُقرأ به مع الإشعار الصريح (د-5)', () {
      final text = '$csvUtf8Bom'
          'dq-import:parties,1\n'
          'الكود؛الاسم؛النوع؛العملة؛حد الائتمان\n'
          'C001؛علي أحمد؛عميل؛؛\n';
      final parse = parsePartiesFile(utf8.encode(text));
      expect(parse.isRejected, isFalse, reason: '${parse.errors}');
      expect(parse.semicolonUsed, isTrue,
          reason: 'إشعار «اكتُشف فاصل منقوطة، قُرئ به» يُعرض بالمعاينة');
      expect(parse.rows.single.code, 'C001');
    });

    test('فاصل لا فاصلة ولا منقوطة يُرفض بتوجيه عربي (د-5)', () {
      final parse = parsePartiesFile(bytesOf([
        'dq-import:parties,1',
        'الكود|الاسم|النوع|العملة|حد الائتمان',
        'C001|علي|عميل||',
      ]));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportSeparatorAmbiguous);
    });

    test('عدد أعمدة مخالف بصف واحد يكسر الفحص البنيوي كله (د-5)', () {
      final parse = parseParties([
        'C001,علي,عميل,,',
        'C002,سعيد,عميل', // أربعة أعمدة لا خمسة
      ]);
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportSeparatorAmbiguous);
    });

    test('حقل مقتبس يحمل فاصلة واقتباساً مزدوجاً بعرف RFC 4180', () {
      final parse = parseParties([
        'C001,"الاسم, مع فاصلة",عميل,,',
        'C002,"شركة ""الخير""",مورد,,',
      ]);
      expect(parse.isRejected, isFalse, reason: '${parse.errors}');
      expect(parse.rows[0].name, 'الاسم, مع فاصلة');
      expect(parse.rows[1].name, 'شركة "الخير"');
    });

    test('سطر فارغ بين الصفوف يُتجاهل والأرقام تبقى بأرقام الملف',
        () {
      final parse = parsePartiesFile(bytesOf([
        'dq-import:parties,1',
        partiesLabels,
        'C001,علي,عميل,,',
        '',
        'C002,سعيد,عميل,,',
      ]));
      expect(parse.isRejected, isFalse, reason: '${parse.errors}');
      expect(parse.rows, hasLength(2));
      expect(parse.rows[1].row, 5,
          reason: 'رقم السطر كما يراه المستخدم لا التسلسل بعد الإسقاط');
    });

    test('فوق العتبة اللينة 5000: تحذير زمني بلا رفض', () {
      final rows = [
        for (var i = 1; i <= 5001; i++) 'C$i,طرف $i,عميل,,',
      ];
      final parse = parseParties(rows);
      expect(parse.isRejected, isFalse);
      expect(parse.overSoftLimit, isTrue);
      expect(parse.totalDataRows, 5001);
    });

    test('فوق الحد الصلب 10000: رفض صريح (DQ-1024) بالرقم والحد',
        () {
      final rows = [
        for (var i = 1; i <= 10001; i++) 'C$i,طرف $i,عميل,,',
      ];
      final parse = parseParties(rows);
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.dqCode, dqImportRowLimit);
      expect(parse.errors.single.description, contains('10001'));
      expect(parse.errors.single.description, contains('10000'));
      expect(parse.errors.single.suggestedAction, contains('قسّم'));
    });
  });

  group('طبقة الصف — الإلزامي والصيغة (§25.5)', () {
    test('كود فارغ وكود بفراغ مرفوضان برقم الصف والعمود', () {
      final parse = parseParties([
        ',بلا كود,عميل,,',
        'ب كود فراغ,بفراغ,عميل,,',
      ]);
      expect(parse.isRejected, isTrue);
      expect(parse.errors, hasLength(2));
      expect(parse.errors[0].column, 1);
      expect(parse.errors[0].row, 3);
      expect(parse.errors[1].dqCode, dqImportRowInvalid);
    });

    test('الاسم فارغ أو بحروف تحكم خفية مرفوض (D-170)', () {
      final parse = parseParties([
        'C001,,عميل,,',
        'C002,خفي\x01ء,عميل,,',
      ]);
      expect(parse.isRejected, isTrue);
      expect(parse.errors[0].column, 2);
      expect(parse.errors[1].column, 2);
    });

    test('النوع بقيمة خارج المعروف مرفوض، والقيم الثلاث واللاتينية تقبل',
        () {
      final bad = parseParties(['C001,علي,شريك,,']);
      expect(bad.isRejected, isTrue);
      expect(bad.errors.single.column, 3);

      final good = parseParties([
        'C1,أ,عميل,,',
        'C2,ب,مورد,,',
        'C3,ج,عميل ومورد معاً,,',
        'C4,د,customer,,',
        'C5,هـ,supplier,,',
        'C6,و,both,,',
      ]);
      expect(good.isRejected, isFalse, reason: '${good.errors}');
      expect(good.rows.map((r) => r.kindStorage),
          everyElement(isIn(['customer', 'supplier', 'both'])));
    });

    test('عملة بصيغة غير ISO مرفوض والفراغ يعني SYP', () {
      final bad = parseParties(['C001,علي,عميل,SP,']);
      expect(bad.isRejected, isTrue);
      expect(bad.errors.single.column, 4);

      final good = parseParties(['C001,علي,عميل,usd,']);
      expect(good.isRejected, isFalse, reason: '${good.errors}');
      expect(good.rows.single.currencyCode, 'USD',
          reason: 'التقليم والتوحيد محدد المعنى لا تخمين');
    });

    test('حد ائتمان فاسد مرفوض والرقم العربي-الهندي يقبل', () {
      final bad = parseParties(['C001,علي,عميل,,12a3']);
      expect(bad.isRejected, isTrue);
      expect(bad.errors.single.column, 5);

      final good = parseParties(['C001,علي,عميل,,١٢٥٠']);
      expect(good.isRejected, isFalse, reason: '${good.errors}');
      expect(good.rows.single.creditLimitRaw, '١٢٥٠');
    });
  });

  group('طبقة الدفعة — تخطيط الأطراف (سياسة الموجود د-2)', () {
    PartyUniquenessIndex existingParties() => PartyUniquenessIndex.build([
          const ExistingParty(
              id: 10, number: 'C001', name: 'علي أحمد', isActive: true),
        ]);

    Map<String, ImportCurrencyRef> currencyIndex() => {
          'SYP': sypRef(),
          'USD': const ImportCurrencyRef(
              id: 2, code: 'USD', minorUnits: 2),
        };

    test('عملة غير معرفة برفض مرجعي (DQ-1021) برقم الصف', () {
      final plan = planPartiesImport(
        parseParties(['C009,يورو,عميل,EUR,']),
        currencies: currencyIndex(),
        existing: emptyParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isFalse);
      expect(plan.errors.single.dqCode, dqImportReferenceMissing);
      expect(plan.errors.single.column, 4);
    });

    test('التكرار الداخلي بالكود فادح رفض كلي (DQ-1022)', () {
      final plan = planPartiesImport(
        parseParties([
          'C001,علي,عميل,,',
          'C001,علي ثاني,عميل,,',
        ]),
        currencies: currencyIndex(),
        existing: emptyParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isFalse);
      expect(
          plan.errors.where((e) => e.dqCode == dqImportInternalDuplicate),
          hasLength(1),
          reason: 'الصف الأول مرجع التكرار والثاني يحمل الخطأ');
      expect(plan.errors.last.description, contains('صف 3'));
    });

    test('التكرار الداخلي بالاسم الحرفي فادح (D-065)', () {
      final plan = planPartiesImport(
        parseParties([
          'C001,علي,عميل,,',
          'C002,علي,عميل,,',
        ]),
        currencies: currencyIndex(),
        existing: emptyParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isFalse);
      expect(
          plan.errors
              .where((e) => e.dqCode == dqImportInternalDuplicate)
              .length,
          1);
    });

    test('اسم جديد يصطدم بطرف قائم مختلف الكود برفض تعارض (DQ-1023)',
        () {
      final plan = planPartiesImport(
        parseParties(['C777,علي أحمد,عميل,,']),
        currencies: currencyIndex(),
        existing: existingParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isFalse);
      expect(plan.errors.single.dqCode, dqImportConflictExisting);
      expect(plan.errors.single.description, contains('C001'));
    });

    test('سياسة إضافة جديد: الموجود يُتخطى والجديد يُنشأ والعدادات',
        () {
      final plan = planPartiesImport(
        parseParties([
          'C001,علي أحمد معدل,عميل,,',
          'C002,جديد,عميل,,',
        ]),
        currencies: currencyIndex(),
        existing: existingParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      expect(plan.creates, hasLength(1));
      expect(plan.creates.single.number, 'C002');
      expect(plan.skipped, hasLength(1));
      expect(plan.skipped.single.existingLabel, contains('C001'));
      expect(plan.differences, hasLength(1),
          reason: 'فرق الاسم يُعرض غير مُحدَّث بسبيه لا سحراً');
      expect(plan.differences.single.updated, isFalse);
      expect(plan.newCount, 1);
      expect(plan.existingCount, 1);
    });

    test('سياسة تحديث الموجود: الاسم يُحدَّث والفروق بالبشري', () {
      final plan = planPartiesImport(
        parseParties(['C001,علي المحدث,عميل,,']),
        currencies: currencyIndex(),
        existing: existingParties(),
        policy: ImportExistingPolicy.updateExisting,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      expect(plan.updates, hasLength(1));
      expect(plan.updates.single.partyId, 10);
      expect(plan.updates.single.newName, 'علي المحدث');
      expect(plan.differences.single.updated, isTrue);
    });

    test('حد الائتمان يتحول بدقة عملة الطرف بلا كسور عائمة', () {
      final plan = planPartiesImport(
        parseParties(['C005,دولاري,عميل,USD,10000.5']),
        currencies: currencyIndex(),
        existing: emptyParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      expect(plan.creates.single.creditLimitBaseMinor, 1000050);
      expect(plan.creates.single.currencyId, 2);
    });

    test('خانة كسرية تفوق دقة العملة رفض صريح لا تقريب صامت', () {
      final plan = planPartiesImport(
        parseParties(['C005,دولاري,عميل,USD,10000.555']),
        currencies: currencyIndex(),
        existing: emptyParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isFalse);
      expect(plan.errors.single.dqCode, dqImportRowInvalid);
      expect(plan.errors.single.description, contains('دقة العملة'));
    });

    test('حد ائتمان صفر أو سالب المعنى مرفوض والفراغ بلا سقف (س-34)',
        () {
      final zero = planPartiesImport(
        parseParties(['C005,صفر,عميل,,0']),
        currencies: currencyIndex(),
        existing: emptyParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(zero.isApprovable, isFalse);
      expect(zero.errors.single.description, contains('موجباً'));

      final blank = planPartiesImport(
        parseParties(['C005,بلا سقف,عميل,,']),
        currencies: currencyIndex(),
        existing: emptyParties(),
        policy: ImportExistingPolicy.addNew,
      );
      expect(blank.isApprovable, isTrue, reason: '${blank.errors}');
      expect(blank.creates.single.creditLimitBaseMinor, isNull);
    });
  });

  group('طبقة الدفعة — تخطيط الأصناف ووحداتها', () {
    Map<String, ImportCurrencyRef> currencyIndex() => {
          'SYP': sypRef(),
        };

    UnitUniquenessIndex unitsIndex() => UnitUniquenessIndex.build([
          const ExistingUnit(id: 5, name: 'قطعة', isActive: true),
        ]);

    ItemUniquenessIndex existingItems() => ItemUniquenessIndex.build([
          const ExistingItem(
              id: 20, sku: 'K101', name: 'زيت', isActive: true),
        ]);

    Map<int, ExistingItemImportRef> detailsFor(Iterable<ExistingItem> items) =>
        {
          for (final it in items)
            it.id: ExistingItemImportRef(
              id: it.id,
              sku: it.sku,
              name: it.name,
              unitName: 'علبة',
              purchasePriceMinor: 100000,
              salePriceMinor: 125000,
              priceCurrencyId: 1,
            ),
        };

    test('وحدة غائبة تُنشأ آلياً مرة واحدة وقائمة تُعاد بمعرّفها (§25.4)',
        () {
      final plan = planItemsImport(
        parseItems([
          'K1,صنف أ,كرتون,,1000,1500',
          'K2,صنف ب,قطعة,,2000,2500',
          'K3,صنف ج,كرتون,,3000,3500',
        ]),
        currencies: currencyIndex(),
        existing: ItemUniquenessIndex.build(const []),
        units: unitsIndex(),
        existingDetails: const <int, ExistingItemImportRef>{},
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      expect(plan.unitCreates, ['كرتون'],
          reason: 'الغائب يُنشأ مرة واحدة لا تكرار');
      expect(plan.creates[0].baseUnitId, -1,
          reason: 'معرّف الوحدة الجديدة يتولده التنفيذ');
      expect(plan.creates[1].baseUnitId, 5,
          reason: 'القائمة بالاسم تُعاد بمعرّفها');
      expect(plan.creates[2].baseUnitId, -1);
    });

    test('الأسعار تتحول بدقة العملة والفراغ يعني صفر «بلا سعر بعد»',
        () {
      final plan = planItemsImport(
        parseItems(['K1,صنف أ,قطعة,,1000.5,']),
        currencies: currencyIndex(),
        existing: ItemUniquenessIndex.build(const []),
        units: unitsIndex(),
        existingDetails: const <int, ExistingItemImportRef>{},
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      expect(plan.creates.single.purchasePriceMinor, 100050);
      expect(plan.creates.single.salePriceMinor, 0);
    });

    test('سياسة التحديث: فروق الأسعار بالبشري الحقيقي وفرق الوحدة '
        'غير مُحدَّث بسبيه', () {
      final plan = planItemsImport(
        parseItems(['K101,زيت محلي,كيس,,110000,140000']),
        currencies: currencyIndex(),
        existing: existingItems(),
        units: unitsIndex(),
        existingDetails: detailsFor(existingItems().bySkuKey('K101') == null
            ? const []
            : [existingItems().bySkuKey('K101')!]),
        policy: ImportExistingPolicy.updateExisting,
      );
      expect(plan.isApprovable, isTrue, reason: '${plan.errors}');
      expect(plan.updates, hasLength(1));
      final update = plan.updates.single;
      expect(update.newName, 'زيت محلي');
      expect(update.newPurchasePriceMinor, 11000000);
      expect(update.newSalePriceMinor, 14000000);
      final unitDiff = plan.differences
          .firstWhere((d) => d.columnKey == 'unit');
      expect(unitDiff.updated, isFalse);
      expect(unitDiff.oldValue, 'علبة');
      expect(unitDiff.newValue, 'كيس');
      expect(unitDiff.note, contains('لا تتغير'));
      final purchaseDiff = plan.differences
          .firstWhere((d) => d.columnKey == 'purchase_price');
      expect(purchaseDiff.oldValue, '1000',
          reason: 'القيمة القديمة بالبشري بدقة العملة لا placeholder');
      expect(purchaseDiff.newValue, '110000');
    });

    test('كود مكرر داخلياً بالأصناف فادح (DQ-1022) والباركود خارج v1',
        () {
      final plan = planItemsImport(
        parseItems([
          'K1,صنف أ,قط,,,',
          'K1,صنف ب,قط,,,',
        ]),
        currencies: currencyIndex(),
        existing: ItemUniquenessIndex.build(const []),
        units: unitsIndex(),
        existingDetails: const <int, ExistingItemImportRef>{},
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isFalse);
      expect(
          plan.errors.where((e) => e.dqCode == dqImportInternalDuplicate),
          hasLength(1));
    });

    test('اسم جديد يصطدم بصنف قائم برفض تعارض (DQ-1023)', () {
      final plan = planItemsImport(
        parseItems(['K999,زيت,قط,,,']),
        currencies: currencyIndex(),
        existing: existingItems(),
        units: unitsIndex(),
        existingDetails: const <int, ExistingItemImportRef>{},
        policy: ImportExistingPolicy.addNew,
      );
      expect(plan.isApprovable, isFalse);
      expect(plan.errors.single.dqCode, dqImportConflictExisting);
    });
  });

  group('القوالب والتقارير — ما نصدّره هو ما نستورده (مرآة F-166)', () {
    test('القالب الفارغ: BOM وترويسة معرِّفة وعناوين الأعمدة', () {
      final csv = buildEmptyTemplateCsv(ImportTemplateId.parties);
      expect(csv.startsWith(csvUtf8Bom), isTrue);
      final lines =
          csv.substring(csvUtf8Bom.length).split('\n').where((l) => l
              .trim()
              .isNotEmpty)
              .toList();
      expect(lines[0], 'dq-import:parties,1');
      expect(lines[1], 'الكود,الاسم,النوع,العملة,حد الائتمان');

      // القالب المنزّل يُقبل فوراً بلا صفوف؟ لا — بلا بيانات رفض صريح.
      final parse = parsePartiesFile(utf8.encode(csv));
      expect(parse.isRejected, isTrue);
      expect(parse.errors.single.description, contains('بلا صفوف'));
    });

    test('قالب الأصناف بأعمدته الستة', () {
      final csv = buildEmptyTemplateCsv(ImportTemplateId.items);
      expect(csv, contains('dq-import:items,1'));
      expect(csv, contains('كود الصنف,الاسم,الوحدة,عملة السعر,سعر الشراء,سعر البيع'));
    });

    test('تقرير الأخطاء يحمل الصف والعمود والرمز والوصف والإجراء',
        () {
      final csv = buildImportErrorReportCsv([
        const ImportError(
          row: 3,
          column: 1,
          value: '',
          dqCode: dqImportRowInvalid,
          description: 'الكود إلزامي.',
          suggestedAction: 'املأ الكود.',
        ),
      ]);
      expect(csv, contains('تقرير أخطاء الاستيراد'));
      expect(csv, contains('DQ-1020'));
      expect(csv, contains('املأ الكود.'));
      expect(csv.startsWith(csvUtf8Bom), isTrue,
          reason: 'بترميز UTF-8 مع BOM بعرف F-166');
    });

    test('تقرير الفروق يحمل الحكم المحْدَث والمُترك', () {
      final csv = buildImportDiffReportCsv([
        const ImportDifference(
          row: 4,
          columnKey: 'name',
          columnLabel: 'الاسم',
          oldValue: 'علي أحمد',
          newValue: 'علي',
          updated: true,
        ),
        const ImportDifference(
          row: 4,
          columnKey: 'unit',
          columnLabel: 'الوحدة',
          oldValue: 'قطعة',
          newValue: 'كيس',
          updated: false,
          note: 'حماية الأرصدة',
        ),
      ]);
      expect(csv, contains('سيُحدَّث'));
      expect(csv, contains('لن يُحدَّث'));
      expect(csv, contains('حماية الأرصدة'));
    });

    test('formatMinorHuman العكس المطابق للتحليل', () {
      expect(formatMinorHuman(125050, 2), '1250.5');
      expect(formatMinorHuman(125000, 2), '1250');
      expect(formatMinorHuman(5, 2), '0.05');
      expect(formatMinorHuman(7, 0), '7');
    });
  });
}
