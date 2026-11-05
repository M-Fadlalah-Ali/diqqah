import 'package:test/test.dart';
import 'package:drift/drift.dart' show Variable;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 32 (تاسعة م2) — الإقفال السنوي (س-21/F-077/D-068).
///
/// الدورة: شراء آجل 5×1,000 فبيع آجل 2×2,000 — الربح 2,000 (إيراد
/// 4,000 − تكلفة 2,000). ثم إقفال كل فترات السنة ثم الإقفال السنوي:
/// تصفير النتيجة إلى 331 وبذر السنة التالية بافتتاحيتها — وكل قيد
/// عبر المحرك الموحد (استثناء قيود الإغلاق بتاريخ الفترة المقفلة
/// موثق على المحرك حصراً).
void main() {
  late DiqqahDatabase db;
  late int unitId;
  late int itemId;
  late int warehouseId;
  late int supplierId;
  late int customerId;
  late String date;
  late int yearId;
  late String yearName;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    unitId = await db.insertUnit(name: 'قطعة');
    itemId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1);
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    supplierId = await db.insertParty(
        number: '0001', name: 'مورد الشرق', kind: 'supplier',
        defaultCurrencyId: 1);
    customerId = await db.insertParty(
        number: '0002', name: 'عميل الأمل', kind: 'customer',
        defaultCurrencyId: 1);
    final yearRows = await db.customSelect(
      'SELECT id, name FROM fiscal_years',
    ).getSingle();
    yearId = yearRows.data['id'] as int;
    yearName = yearRows.data['name'] as String;
    date = '$yearName-03-15';

    // الشراء الآجل 5,000: 113 مدين 5,000 / موردون دائن 5,000.
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: 5,
            unitPriceMinor: 1000),
      ],
    ));
    await db.postInvoice(purchase);
    // البيع الآجل 4,000: عملاء مدين 4,000 / 411 دائن 4,000، وتكلفة
    // الخروج بالمتوسط 2×1,000: 51 مدين 2,000 / 113 دائن 2,000.
    final sale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: itemId, unitId: unitId, qtyBase: 2,
            unitPriceMinor: 2000),
      ],
    ));
    await db.postInvoice(sale);
  });

  tearDown(() => db.close);

  Future<int> accountByCode(String code) async {
    final r = await db.customSelect(
      'SELECT id FROM accounts WHERE code = ?',
      variables: [driftVariable(code)],
    ).getSingle();
    return r.data['id'] as int;
  }

  Future<(int, int)> accountBalance(String code, {String? untilText}) async {
    final id = await accountByCode(code);
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(debit_minor),0) AS d, '
      'COALESCE(SUM(credit_minor),0) AS c FROM move_lines l '
      'JOIN moves m ON m.id = l.move_id '
      "WHERE m.state = 'posted' AND l.account_id = ?"
      '${untilText == null ? '' : ' AND m.date_text <= ?'}',
      variables: [
        driftVariable(id),
        if (untilText != null) driftVariable(untilText),
      ],
    ).getSingle();
    return (rows.data['d'] as int, rows.data['c'] as int);
  }

  Future<void> closeAllPeriods() async {
    final periods = await db.ledgerPeriods();
    for (final period in periods) {
      await db.closePeriod(period.id, draftsConfirmed: true);
    }
  }

  test('المعاينة قبل الإقفال: فترات مفتوحة تُرفض والزر غير جاهز — '
      'وفيها النتيجة قبلية 2,000 (س-21: مراجعة الميزان والنتيجة)',
      () async {
    final preview = await db.fiscalYearClosePreview(yearId);
    expect(preview.yearName, yearName);
    expect(preview.periodsCount, 12);
    expect(preview.openPeriodsCount, 12);
    expect(preview.isReady, isFalse);
    expect(preview.plan.netResultMinor, 2000,
        reason: '4,000 إيراد − 2,000 تكلفة');
    expect(preview.plan.incomeLines, hasLength(1));
    expect(preview.plan.expenseLines, hasLength(1));
  });

  test('الرفض: إقفال السنة بفترات مفتوحة مرفوض (س-21: «أقفلها أولاً»)',
      () async {
    expect(
      () => db.fiscalYearClose(yearId),
      throwsA(isA<YearCloseException>().having(
        (e) => e.errors,
        'errors',
        anyElement(isA<YearHasOpenPeriods>()),
      )),
    );
  });

  test('الإقفال الكامل: تصفير النتيجة إلى 331 و332 صفراً والسنة التالية '
      'مبذورة بافتتاحيتها المتوازنة — والميزان باقياً متوازناً (F-068)',
      () async {
    await closeAllPeriods();

    final preview = await db.fiscalYearClosePreview(yearId);
    expect(preview.isReady, isTrue);

    final result = await db.fiscalYearClose(yearId);
    expect(result.yearName, yearName);
    expect(result.netResultMinor, 2000);
    expect(result.closingMoveIds, hasLength(3),
        reason: 'إغلاق إيرادات وإغلاق مصروفات ونقل النتيجة');
    expect(result.openingMoveId, isNotNull);

    // حسابات النتيجة صفرت و331 حملت ربح السنة داخل سنة الإقفال
    // (س-21: تتراكم في 331) — والافتتاحية تحمل الرصيد ذاته للسنة
    // الجديدة فمجموع الدفتر عبر السنتين ضِعفه (سنتان منفصلتان).
    final (revD, revC) = await accountBalance('411');
    expect(revD, 4000);
    expect(revC, 4000);
    final (cogsD, cogsC) = await accountBalance('51');
    expect(cogsD, 2000);
    expect(cogsC, 2000);
    final (retD, retC) = await accountBalance('331',
        untilText: '$yearName-12-31');
    expect(retD, 0);
    expect(retC, 2000);
    final (resD, resC) = await accountBalance('332',
        untilText: '$yearName-12-31');
    // 332 بإجماليَيه لا صافيه: دائن 4,000 من إغلاق الإيرادات، ومدين
    // 4,000 من إغلاق المصروفات 2,000 ونقل النتيجة 2,000 — وصفره
    // الطبيعي بالفرق (س-21 نصاً).
    expect(resD, 4000);
    expect(resC, 4000);
    // و331 بالسنة الجديدة دائن 2,000 من الافتتاحية — التراكم يمضي.
    final (newRetD, newRetC) = await accountBalance('331',
        untilText: '${int.parse(yearName) + 1}-12-31');
    expect(newRetD, 0);
    expect(newRetC, 4000);
    final (newResD, newResC) = await accountBalance('332',
        untilText: '${int.parse(yearName) + 1}-12-31');
    // والقراءة تراكمية عبر السنتين: إجماليا 332 كما هما (دائن
    // الإيرادات ومدين المصروفات والنقل) — و332 بالسنة الجديدة وحدها
    // لا سطر لها (الافتتاحية لا تلمسها — صفر بعد الصافي).
    expect(newResD, 4000);
    expect(newResC, 4000);

    // السنة التالية مبذورة باثنتي عشرة فترة مفتوحة والسنة مقفلة.
    final years = await db.customSelect(
      'SELECT name, state FROM fiscal_years ORDER BY id',
    ).get();
    expect(years, hasLength(2));
    expect(years.last.data['name'], '${int.parse(yearName) + 1}');
    expect(years.last.data['state'], 'open');
    expect(years.first.data['state'], 'closed');
    final nextPeriods = await db.customSelect(
      'SELECT COUNT(*) AS n FROM periods WHERE fiscal_year_id = ? '
      "AND state = 'open'",
      variables: [driftVariable(result.nextYearId)],
    ).getSingle();
    expect(nextPeriods.data['n'], 12);

    // الافتتاحية: عملاء 4,000 ومخزون 3,000 مدينة وموردون 5,000
    // وأرباح محتجزة 2,000 دائنة — متوازنة 7,000/7,000.
    final openingLines = await db.customSelect(
      'SELECT a.code AS code, l.debit_minor AS d, l.credit_minor AS c '
      'FROM move_lines l JOIN moves m ON m.id = l.move_id '
      'JOIN accounts a ON a.id = l.account_id '
      'WHERE m.id = ? ORDER BY a.code',
      variables: [driftVariable(result.openingMoveId!)],
    ).get();
    expect(openingLines, hasLength(4));
    final byCode = {
      for (final r in openingLines)
        r.data['code'] as String: (
          r.data['d'] as int,
          r.data['c'] as int,
        ),
    };
    expect(byCode['112'], (4000, 0));
    expect(byCode['113'], (3000, 0));
    expect(byCode['211'], (0, 5000));
    expect(byCode['331'], (0, 2000));
    final debitSum = openingLines.fold<int>(0, (a, r) => a + r.data['d'] as int);
    final creditSum = openingLines.fold<int>(0, (a, r) => a + r.data['c'] as int);
    expect(debitSum, 7000);
    expect(creditSum, 7000);
    // و332 لا سطر لها بالافتتاحية (صفر بعد الصافي — س-21).
    expect(byCode.containsKey('332'), isFalse);

    // الميزان بعد الإقفال باقٍ متوازناً حرفاً (F-068).
    final (td, tc) = await db.trialBalanceTotalsOf();
    expect(td, tc);
  });

  test('بعد الإقفال: لا ترحيل في السنة المقفلة أبداً (07 §1.5) — '
      'وقيدٌ جديد بتاريخها يُرفض بحرس الفترة المقفلة', () async {
    await closeAllPeriods();
    await db.fiscalYearClose(yearId);

    final cashAccount = await accountByCode('1111');
    final capitalAccount = await accountByCode('311');
    final draftId = await db.createMoveDraft(
      journalId: (await db.customSelect(
        "SELECT id FROM journals WHERE code = 'general'",
      ).getSingle()).data['id'] as int,
      dateText: '$yearName-06-01',
      narration: 'محاولة بعد الإقفال',
      lines: [
        MoveLineDraft(accountId: cashAccount, debitMinor: 100),
        MoveLineDraft(accountId: capitalAccount, creditMinor: 100),
      ],
    );
    expect(
      () => db.postMove(draftId),
      throwsA(isA<LedgerValidationException>().having(
        (e) => e.errors,
        'errors',
        anyElement(isA<MoveClosedPeriod>()),
      )),
    );
    // والسنة الجديدة مفتوحة فالترحيل فيها مسارها العادي.
    final newDate = '${int.parse(yearName) + 1}-02-10';
    final draft2 = await db.createMoveDraft(
      journalId: (await db.customSelect(
        "SELECT id FROM journals WHERE code = 'general'",
      ).getSingle()).data['id'] as int,
      dateText: newDate,
      narration: 'قيد في السنة الجديدة',
      lines: [
        MoveLineDraft(accountId: cashAccount, debitMinor: 500),
        MoveLineDraft(accountId: capitalAccount, creditMinor: 500),
      ],
    );
    await db.postMove(draft2);
  });

  test('الإقفال المزدوج مرفوض، والسنة التالية موجودة فرفضٌ ثانٍ — '
      'والرقم لا يُحرق: التسلسل بأرقام قيود الإقفال الفعلية حصراً',
      () async {
    await closeAllPeriods();
    final first = await db.fiscalYearClose(yearId);
    expect(first.closingMoveIds, hasLength(3));

    // الإقفال الثاني مرفوض لأن السنة مقفلة أصلاً.
    expect(
      () => db.fiscalYearClose(yearId),
      throwsA(isA<YearCloseException>().having(
        (e) => e.errors,
        'errors',
        anyElement(isA<FiscalYearAlreadyClosed>()),
      )),
    );

    // الأرقام الصادرة لقيود الإقفال الثلاثة متتابعة بلا حرق (07 §1.9).
    final numbers = <int>[];
    for (final moveId in first.closingMoveIds) {
      final row = await db.customSelect(
        'SELECT number FROM moves WHERE id = ?',
        variables: [driftVariable(moveId)],
      ).getSingle();
      numbers.add(int.parse(row.data['number'] as String));
    }
    expect(numbers[1], numbers[0] + 1);
    expect(numbers[2], numbers[1] + 1);
    // وحدث السجل الموثق بقائمة اللقطة الكاملة.
    final event = await db.customSelect(
      "SELECT payload FROM events WHERE action = 'fiscal_year_closed' "
      'ORDER BY id DESC LIMIT 1',
    ).getSingle();
    expect((event.data['payload'] as String), contains('net_result_minor'));
  });
}

/// غلاف متغير drift لاختصار الاستدعاءات أعلاه.
dynamic driftVariable(Object value) => value is int
    ? Variable.withInt(value)
    : Variable.withString(value as String);
