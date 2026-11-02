import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات دفعة (15) «ما قبل إغلاق م1» (س-151..س-153/D-149..D-151) —
/// أعمار الذمم ودفتر اليومية وخانة ملاحظة التسليم بأرقام الدورة
/// المعروفة: ضخ 500,000 فشراء 10×10,000 آجل فبيع 6×15,000 آجل فقبض
/// 50,000 بمطابقة فعجز 5,000 (نمط reports_flow_test حرفاً — الميزان
/// 805,000/805,000).
///
/// ضوابط التقريرَين: أعمار الذمم تُعمِّر الفواتير المفتوحة (المحرك
/// ذاته: posted/partially_paid ناقص المغطى بالمطابقات المرحّلة)
/// بتاريخ الاستحقاق وإلا تاريخ الفاتورة، ودفتر اليومية مجموعاه
/// متوازنان يطابقان الميزان (روح F-068)، والملاحظة تُحدَّث على
/// المرحّلة (علم عمل لا محاسبة — نمط D-131).
void main() {
  late DiqqahDatabase db;
  late String date;
  late int unitId;
  late int oilId;
  late int customerId;
  late int supplierId;
  late int boxId;
  late int warehouseId;
  late int saleId;
  late int purchaseId;

  /// تاريخ بنسبي عن اليوم — كنترول الفوهج بلا هشاشة تاريخ التشغيل.
  String isoFromToday(int days) {
    final d = DateTime.now().add(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> setDueDate(int invoiceId, String dueDate) async {
    await db.customStatement(
      'UPDATE invoices SET due_date = ? WHERE id = ?',
      [dueDate, invoiceId],
    );
  }

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    final yearRows = await db
        .customSelect('SELECT name FROM fiscal_years')
        .get();
    date = '${int.parse(yearRows.single.data['name'] as String)}-03-15';
    unitId = await db.insertUnit(name: 'قطعة');
    oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    customerId = await db.insertParty(
        number: '0001',
        name: 'عميل الأمل',
        kind: 'customer',
        defaultCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0002',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final capitalId = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '311'",
    ).getSingle()).data['id'] as int;

    // ضخ رأس المال 500,000 (سند قبض بغير طرف على 311).
    final capitalVoucher = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      directAccountId: capitalId,
      cashBoxId: boxId,
      amountDocMinor: 500000,
    ));
    await db.postVoucher(capitalVoucher);

    // شراء آجل 10×10,000 = 100,000 — ذمة دائنة مفتوحة كاملة.
    purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchaseId);

    // بيع آجل 6×15,000 = 90,000 — ذمة مدينة.
    saleId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 6, unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(saleId);

    // قبض 50,000 بمطابقة على فاتورة البيع — يبقى مفتوحاً 40,000.
    final receiptId = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      partyId: customerId,
      cashBoxId: boxId,
      amountDocMinor: 50000,
      allocations: [
        VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 50000),
      ],
    ));
    await db.postVoucher(receiptId);

    // عجز صندوق 5,000 على 57.
    final adjustmentId = await db.createCashAdjustmentDraft(
        CashAdjustmentDraft(
      dateText: date,
      cashBoxId: boxId,
      direction: CashAdjustmentDirection.shortage,
      amountDocMinor: 5000,
      reason: 'فرق جرد يومي',
    ));
    await db.postCashAdjustment(adjustmentId);
  });

  tearDown(() async {
    await db.close();
  });

  test('س-151/D-149: أعمار الذمم تعمّر الفواتير المفتوحة بمحرك '
      'المصالحة ذاته — المدينة أولاً (D-130) والفوهة بلسانها', () async {
    // كنترول الفوهج بتواريخ استحقاق معلومة نسبةً لليوم: الشراء متأخر
    // 45 يوماً (فوهة 31-60) والبيع لم يستحق (بعد 20 يوماً).
    await setDueDate(purchaseId, isoFromToday(-45));
    await setDueDate(saleId, isoFromToday(20));

    final report = await db.agingReport(thresholds: [30, 60, 90, 120]);

    // اللسان المحسوب من الفوهج — الفوهة الأولى غير المستحق.
    expect(report.thresholds, [30, 60, 90, 120]);
    expect(report.bucketLabels, hasLength(6));
    expect(report.bucketLabels[0], 'غير مستحق');
    expect(report.bucketLabels[1], 'حتى 30 يوماً');
    expect(report.bucketLabels[2], '31 حتى 60 يوماً');
    expect(report.bucketLabels[5], 'أكثر من 120 يوماً');

    // الترتيب بلفظ D-130: المدينة (عميل الأمل) ثم الدائنة (مورد الشرق).
    expect(report.parties, hasLength(2));
    final customer = report.parties.first;
    final supplier = report.parties.last;
    expect(customer.partyName, 'عميل الأمل');
    expect(customer.theyOweUs, isTrue);
    expect(supplier.partyName, 'مورد الشرق');
    expect(supplier.theyOweUs, isFalse);

    // العميل: المتبقي 40,000 (90,000 − 50,000 مطابقة) — غير مستحق
    // (استحقاقه بعد 20 يوماً فأيام تجاوزه سالبة والفوهة الأولى). 
    expect(customer.bucketMinor[0], 40000);
    expect(customer.totalMinor, 40000);
    expect(customer.invoices.single.remainingDocMinor, 40000);
    expect(customer.invoices.single.daysOver, lessThan(0),
        reason: 'تاريخ الفاتورة قديم لكن استحقاقه المستقبلي هو الحاكم');

    // المورد: 100,000 كاملة مفتوحة في فوهة 31-60.
    expect(supplier.bucketMinor[2], 100000);
    expect(supplier.totalMinor, 100000);
    expect(supplier.invoices.single.daysOver, inInclusiveRange(31, 60));

    // المجاميع: كل فوهة بمجموع صفوفها والإجمالي 140,000.
    expect(report.bucketTotalsMinor, [40000, 0, 100000, 0, 0, 0]);
    expect(report.totalMinor, 140000);
  });

  test('س-151/D-149: الفوهج القابلة للتهيئة تعيد التعمير بلسانها '
      'وفلتر النوع عرضٌ فوق القراءة لا حساب جديد', () async {
    await setDueDate(purchaseId, isoFromToday(-45));
    await setDueDate(saleId, isoFromToday(20));

    // فوهج مختلفة: 15/30/60/90 — تأخر 45 يوماً يقع في فوهة 31-60
    // (المؤشر 2) ذاتها لكن بلسان مختلف.
    final report = await db.agingReport(
        thresholds: [15, 30, 60, 90], kindStorageValue: null);
    expect(report.thresholds, [15, 30, 60, 90]);
    expect(report.bucketLabels[1], 'حتى 15 يوماً');
    expect(report.bucketLabels[2], '16 حتى 30 يوماً');
    expect(report.bucketLabels[3], '31 حتى 60 يوماً');
    final supplier = report.parties
        .firstWhere((p) => p.partyName == 'مورد الشرق');
    expect(supplier.bucketMinor[3], 100000);

    // فلتر المدينة حصراً — صف الشراء يغيب والعرض لا يغير الأرقام.
    final receivable = await db.agingReport(
        thresholds: [30, 60, 90, 120], kindStorageValue: 'sale');
    expect(receivable.parties, hasLength(1));
    expect(receivable.parties.single.partyName, 'عميل الأمل');
    expect(receivable.totalMinor, 40000);

    // وفلتر الدائنة حصراً.
    final payable = await db.agingReport(
        thresholds: [30, 60, 90, 120], kindStorageValue: 'purchase');
    expect(payable.parties, hasLength(1));
    expect(payable.parties.single.partyName, 'مورد الشرق');
    expect(payable.totalMinor, 100000);
  });

  test('س-151/D-149: الفاتورة المصفاة كلياً لا ذمة لها فلا صف — '
      'والمطابقات المرحّلة حصراً هي الغطاء', () async {
    // سداد باقي فاتورة البيع (40,000) بمطابقة مرحّلة — تفرغ فتغيب.
    final boxRows = await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).get();
    final boxId2 = boxRows.single.data['id'] as int;
    final clear = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      partyId: customerId,
      cashBoxId: boxId2,
      amountDocMinor: 40000,
      allocations: [
        VoucherAllocationDraft(invoiceId: saleId, appliedDocMinor: 40000),
      ],
    ));
    await db.postVoucher(clear);

    final report = await db.agingReport(thresholds: [30, 60, 90, 120]);
    expect(
      report.parties.where((p) => p.partyName == 'عميل الأمل'),
      isEmpty,
      reason: 'الذمة صفّت فلا صف لها — والصفر لا ذمة',
    );
    expect(report.totalMinor, 100000, reason: 'بقيت ذمة المورد وحدها');
  });

  test('س-152/D-150: دفتر اليومية بقيود المرحّل بترتيب الزمن ومجموعاه '
      'متوازنان يطابقان الميزان (روح F-068)', () async {
    final report = await db.journalBookReport();

    // خمسة قيود مرحّلة: ضخ رأس المال، شراء، بيع، قبض، عجز صندوق.
    expect(report.entries, hasLength(5));
    expect(report.totalDebitMinor, 805000);
    expect(report.totalCreditMinor, 805000);
    expect(report.isBalanced, isTrue);

    // الترتيب بترتيب الزمن (كلها بيوم واحد فالمعرف هو الحاسم).
    final ids = [for (final e in report.entries) e.moveId];
    expect(ids, equals([...ids]..sort()));

    // القيد البيعي بأسطره كاملة: 112 مدين و411 دائن و51 و113 بالتكلفة
    // (90,000 بيعية + 60,000 تكلفة = 150,000 لكل جانب).
    final salesEntries = [
      for (final e in report.entries)
        if (e.journalName.contains('المبيعات')) e,
    ];
    expect(salesEntries, hasLength(1));
    final saleEntry = salesEntries.single;
    final accountCodes = [
      for (final l in saleEntry.lines) l.accountCode,
    ];
    expect(accountCodes, containsAll(['112', '411', '51', '113']));
    final entryDebit = [
      for (final l in saleEntry.lines) l.debitMinor,
    ].fold(0, (a, b) => a + b);
    final entryCredit = [
      for (final l in saleEntry.lines) l.creditMinor,
    ].fold(0, (a, b) => a + b);
    expect(entryDebit, 150000);
    expect(entryCredit, 150000);
    expect(saleEntry.totalDebitMinor, 150000);
    expect(saleEntry.totalCreditMinor, 150000);

    // والطرف على سطر الذمة كما في المحرك (اصطلاح م-14).
    final partyLines = [
      for (final l in saleEntry.lines)
        if (l.partyName != null) l,
    ];
    expect(partyLines, isNotEmpty);
    expect(partyLines.first.partyName, 'عميل الأمل');
  });

  test('س-152/D-150: فلتر الدفتر والمدى قراءتان مفلترتان — والمدى '
      'الفاسد يُرفض قبل لمس القاعدة (D-077)', () async {
    // فلتر دفتر المبيعات — قيد البيع وحده (150,000 بجانبَيه).
    final sales = await db.journalBookReport(journalKind: 'sales');
    expect(sales.entries, hasLength(1));
    expect(sales.totalDebitMinor, 150000);

    // ودفتر الصندوق — القبضان وعجز التسوية.
    final cash = await db.journalBookReport(journalKind: 'cash');
    expect(cash.entries, hasLength(3));

    // مدى كامل يشمل يوم الدورة — القيود الخمسة كلها.
    final full = await db.journalBookReport(fromText: date, toText: date);
    expect(full.entries, hasLength(5));

    // مدى بعد الدورة — لا شيء برسالته لا صمتاً (المدى بجانبيه
    // معاً بعرف المدقق: أي مدى معلن يُدقق طرفاه — D-077).
    final after = await db.journalBookReport(
        fromText: isoFromToday(30), toText: isoFromToday(60));
    expect(after.entries, isEmpty);
    expect(after.totalDebitMinor, 0);
    expect(after.isBalanced, isTrue);

    // مدى مقلوب — رفض المدقق.
    expect(
      () => db.journalBookReport(fromText: date, toText: '2000-01-01'),
      throwsA(isA<ReportValidationException>()),
    );
  });

  test('س-153/D-151: خانة ملاحظة التسليم تُحدَّث على المرحّلة (علم '
      'عمل لا محاسبة نمط D-131) وتظهر بقارئة غير المستلم', () async {
    // السطر غير المستلم لفاتورة البيع المرحّلة.
    final undelivered = await db.undeliveredSaleLinesReport();
    expect(undelivered, hasLength(1));
    final lineId = undelivered.single.lineId;
    expect(undelivered.single.deliveryNote, isNull);

    // كتابة الملاحظة على سطر مرحّل — بلا فك إقفال.
    await db.setInvoiceLineDeliveryNote(lineId,
        note: '  مواصفات خاصة: تغليف بعلبتين  ');
    final lines = await db.invoiceLines(saleId);
    expect(lines.single.deliveryNote, 'مواصفات خاصة: تغليف بعلبتين',
        reason: 'الفراغ يُقص قبل التخزين');
    final afterWrite = await db.undeliveredSaleLinesReport();
    expect(afterWrite.single.deliveryNote, 'مواصفات خاصة: تغليف بعلبتين');

    // المسح: نص فارغ يمحو (null) ولا يخزّن فارغاً.
    await db.setInvoiceLineDeliveryNote(lineId, note: '   ');
    final afterClear = await db.invoiceLines(saleId);
    expect(afterClear.single.deliveryNote, isNull);

    // والسطر الغائب برسالته لا صمتاً.
    expect(
      () => db.setInvoiceLineDeliveryNote(999999, note: 'x'),
      throwsA(isA<StateError>()),
    );

    // والملاحظة علم عمل: مساس المال يبقى مرفوضاً على المرحّل.
    expect(
      () => db.customStatement(
        'UPDATE invoice_lines SET unit_price_minor = 1 WHERE id = ?',
        [lineId],
      ),
      throwsA(anything),
    );
  });
}
