import 'dart:math';

import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// خاصية الميزان المولَّدة — س167 بقرار المالك الحرفي «أوافق على
/// اقتراحك بالنسبة للاختبارات» (من نقاش الاختبارات المقترح: «توليد
/// فواتير وسندات عشوائية — خصومات، عملات، كسور — بمُعطى واحد صارم:
/// مدين = دائن بالأعداد الصغيرة حصراً»).
///
/// البذرة مثبتة (20261119) فالعشوائية هنا حتمية قابلة لإعادة الإنتاج
/// حرفاً: أي فشل يعيد إنتاجه في أي بيئة بالأرقام نفسها. المولد يغطي
/// مواضع التقريب التي لا تبلغها الأمثلة اليدوية: توزيع خصم الفاتورة
/// على الأسطر (السطر الأخير يمتص الفارق — D-067)، وتحويل العملة
/// الأساسية، وخروج المتوسط المرجح بالقيمة، ومدقق القيود بجانبه
/// الواحد، ومدقق السندات بحصريّته.
///
/// سقف المبالغ مضبوط بوعي: مجموع الأسطر يبقى دون 10^13 حتى يبقى
/// الضرب الداخلي (subtotal × rate حتى 10^17) بعيداً عن طوق int64.
Random seeded() => Random(20261119);

String _isoDate(Random r) {
  const pool = [
    '2026-08-14', '2026-09-02', '2026-09-21', '2026-10-05',
    '2026-10-19', '2026-11-01', '2026-11-09', '2026-11-15',
  ];
  return pool[r.nextInt(pool.length)];
}

InvoiceLineDraft _randomLine(Random r, int itemId) {
  // حظيرة المولد داخل طوق int64 للمحرك نفسه: أعلى مجموع خام ≈ 2.5×10^9
  // (8 أسطر × 250 غراماً × 1.25 مليون وحدة صغرى) — فلا بسطٌ داخلي يلامس
  // الحد (أعلى ضرب: سطر × خصم ≈ 8×10^17 آمن)، ومثله محرك القيود.
  final qty = 1 + r.nextInt(250);
  // سعر بكثافة واقعية وأحياناً أعلى قليلاً — والصفر مشروع (س6).
  final int price;
  if (r.nextInt(10) == 0) {
    price = r.nextInt(1000) * 1000; // آلاف صغيرة
  } else if (r.nextInt(20) == 0) {
    price = 1000000 + r.nextInt(250000); // فوق المليون
  } else {
    price = 1 + r.nextInt(1250000);
  }
  final gross = qty * price;
  // الخصم من قيمة السطر بمقياس المحرك ذاته (فئة 0.01٪ حتى 100٪).
  final discount =
      r.nextInt(4) == 0 ? (gross * r.nextInt(10001)) ~/ 10000 : 0;
  return InvoiceLineDraft(
    itemId: itemId,
    unitId: itemId,
    qtyBase: qty,
    unitPriceMinor: price,
    discountMinor: discount,
  );
}

InvoiceDraft _randomInvoiceDraft(Random r) {
  final count = 1 + r.nextInt(8);
  int rate = switch (r.nextInt(10)) {
    0 => 0,
    1 => 10000, // 100٪ — صافي صفر مشروع سلوكياً هنا فالمحسوب النقي
    2 => 350, // 3.5٪ (س-117)
    3 => 1250, // 12.5٪
    _ => r.nextInt(10001),
  };
  if (rate == 10000 && r.nextInt(4) != 0) rate = r.nextInt(10000);
  return InvoiceDraft(
    kind: InvoiceKind.sale,
    dateText: _isoDate(r),
    partyId: 1 + r.nextInt(50),
    currencyId: r.nextInt(4) == 0 ? 2 : 1,
    fxRate: switch (r.nextInt(6)) {
      0 => 650000,
      1 => 850000,
      2 => 1250000,
      3 => 1470000,
      _ => baseCurrencyFxRate,
    },
    discountRate: rate,
    lines: [for (var i = 0; i < count; i++) _randomLine(r, i + 1)],
  );
}

/// تفكيك مبلغ إلى أجزاء موجبة حصراً بعدد معلوم — انقسام تسلسلي محكوم:
/// كل جزء حصة عشوائية حتى سقفٍ يترك لشركائه حقهم، فلا ضرب أصلاً ولا
/// يكسر طوق، والمجموع مطابق حرفاً.
List<int> _positiveParts(Random r, int total, int count) {
  final parts = List<int>.filled(count, 1);
  var remain = total - count;
  for (var i = 0; i < count - 1; i++) {
    final maxTake = remain ~/ (count - i);
    // الحصة العشوائية مقيدة بـ 2^31 حتى لا تلامس nextInt حدَّها، والباقي
    // يصب في آخر جزء فالمجموع مطابق حرفاً مهما بلغ المبلغ.
    final take = maxTake <= 0
        ? 0
        : r.nextInt(maxTake < (1 << 31) ? maxTake + 1 : (1 << 31));
    parts[i] += take;
    remain -= take;
  }
  parts[count - 1] += remain;
  return parts..shuffle(r);
}

AccountInfo _acc(int id, String code, AccountType type) => AccountInfo(
      id: id,
      code: code,
      name: 'حساب $code',
      type: type,
      normalSide: type.defaultNormalSide,
      parentId: null,
      isLeaf: true,
      isActive: true,
    );

LedgerAccountIndex _smallIndex() => LedgerAccountIndex.build([
      _acc(1, '112', AccountType.asset), // ذمم العملاء
      _acc(2, '411', AccountType.income), // مبيعات
      _acc(3, '1111', AccountType.asset), // الصندوق
    ]);

void main() {
  test('خاصية التوزيع — 400 مسودة عشوائية (بذرة ثابتة): مجموع صافي '
      'الأسطر = الصافي حرفاً والسطر الأخير يمتص التقريب', () {
    final r = seeded();
    for (var caseNo = 0; caseNo < 400; caseNo++) {
      final draft = _randomInvoiceDraft(r);
      final t = computeInvoiceTotals(draft);

      // الحوادث العليا كعقدها الموثق (05 §4.1).
      var grossSum = 0;
      for (final l in draft.lines) {
        grossSum += l.grossDocMinor;
      }
      expect(t.subtotalDocMinor, grossSum, reason: 'حالة $caseNo: المجموع الخام');
      expect(
        t.discountDocMinor,
        roundHalfAwayFromZeroRatio(
            t.subtotalDocMinor * draft.discountRate, 10000),
        reason: 'حالة $caseNo: النسبة ×100 (س-117) والنصف بعيداً عن الصفر',
      );
      expect(t.discountDocMinor, inInclusiveRange(0, t.subtotalDocMinor),
          reason: 'حالة $caseNo: الخصم لا يتجاوز المجموع');
      expect(t.totalDocMinor, t.subtotalDocMinor - t.discountDocMinor,
          reason: 'حالة $caseNo: الصافي = الخام − الخصم');
      expect(t.totalBaseMinor, convertToBaseMinor(t.totalDocMinor, draft.fxRate),
          reason: 'حالة $caseNo: الأساسي بتحويل لقطة السعر (F-122)');

      // النواة: توزيع الأسطر يستوي مع المجاميع حرفاً — لا فلس يتيم.
      var netSum = 0;
      var baseSum = 0;
      for (final lr in t.lines) {
        netSum += lr.netDocMinor;
        baseSum += lr.baseMinor;
        expect(lr.netDocMinor, greaterThanOrEqualTo(0),
            reason: 'حالة $caseNo: سطر صافٍ سالب مستحيل');
        expect(lr.baseMinor, greaterThanOrEqualTo(0),
            reason: 'حالة $caseNo: سطر أساسي سالب مستحيل');
      }
      expect(netSum, t.totalDocMinor,
          reason: 'حالة $caseNo: مدين = دائن بالأعداد الصغيرة حصراً '
              '(استواء التوزيع على الصافي)');
      expect(baseSum, t.totalBaseMinor,
          reason: 'حالة $caseNo: استواء التوزيع على الأساسي');

      if (draft.discountRate == 0) {
        for (var i = 0; i < t.lines.length; i++) {
          expect(t.lines[i].netDocMinor, draft.lines[i].grossDocMinor,
              reason: 'حالة $caseNo: بلا خصم فكل سطر بخامه');
        }
      }
      expect(draft.fxRate == baseCurrencyFxRate
              ? t.totalBaseMinor == t.totalDocMinor
              : true,
          isTrue,
          reason: 'حالة $caseNo: لقطة الأساسية هوية تامة');
    }
  });

  test('رتابة الخصم على مسودة واحدة عبر سلّم نسب — والنسبة الكاملة '
      'تُصفّر كل الأسطر لا تحجبها', () {
    final r = seeded()..nextInt(100); // تقدّم البذرة بلا دلالة
    final draft = _randomInvoiceDraft(r);
    var lastDiscount = 0;
    for (final rate in const [0, 250, 350, 1000, 5000, 7500, 10000]) {
      final t = computeInvoiceTotals(
        InvoiceDraft(
          kind: draft.kind,
          dateText: draft.dateText,
          partyId: draft.partyId,
          currencyId: draft.currencyId,
          fxRate: draft.fxRate,
          discountRate: rate,
          lines: draft.lines,
        ),
      );
      expect(t.discountDocMinor, greaterThanOrEqualTo(lastDiscount),
          reason: 'نسبة $rate: الخصم رتيب غير متناقص');
      lastDiscount = t.discountDocMinor;
      if (rate == 10000) {
        expect(t.totalDocMinor, 0, reason: 'النسبة الكاملة صافي صفر');
        expect(t.lines.map((l) => l.netDocMinor), everyElement(0),
            reason: 'كل أسطر النسبة الكاملة صفرية لا سالبة');
      }
    }
  });

  test('خاصية التحويل الأساسي — الهوية عند اللقطة الأساسية والرتابة '
      'وحدُّ خطأ التقريب بنصف وحدة', () {
    final r = seeded();
    const rates = [650000, 850000, 1000000, 1250000, 1470000];
    for (var caseNo = 0; caseNo < 300; caseNo++) {
      // حتى 2^40 تقريباً — nextInt مقيدة بـ 2^32 فالمبالغ تُبنى بمقطعتين.
      final x1 = 1 + r.nextInt(1 << 20) * (1 << 20) + r.nextInt(1 << 20);
      final x2 = x1 + r.nextInt(1 << 20); // زوج مرتب: الرتابة على مرتبَيه
      final fx = rates[r.nextInt(rates.length)];
      final c1 = convertToBaseMinor(x1, fx);
      final c2 = convertToBaseMinor(x2, fx);
      if (fx == baseCurrencyFxRate) {
        expect(c1, x1, reason: 'حالة $caseNo: الهوية عند الأساسية');
        expect(c2, x2, reason: 'حالة $caseNo: الهوية عند الأساسية');
      }
      final exact1 = x1 * fx / 1000000;
      final exact2 = x2 * fx / 1000000;
      expect((c1 - exact1).abs(), lessThanOrEqualTo(0.51),
          reason: 'حالة $caseNo: لا خطأ يتجاوز نصف وحدة — والهامش الضئيل '
              'خطأ تمثيل double للقسمة لا للمحرك');
      expect((c2 - exact2).abs(), lessThanOrEqualTo(0.51),
          reason: 'حالة $caseNo: لا خطأ يتجاوز نصف وحدة');
      expect(c1, lessThanOrEqualTo(c2),
          reason: 'حالة $caseNo: رتابة غير متناقصة على الزوج المرتب');
    }
  });

  test('خاصية خروج المتوسط المرجح — الحدود الثلاثة والإغلاق الحرفي '
      'عند نفاد الكمية (س-56)', () {
    final r = seeded();
    for (var caseNo = 0; caseNo < 250; caseNo++) {
      // حتى 10^12 بمقطعتين — nextInt مقيدة بـ 2^32.
      final totalValue =
          r.nextInt(1 << 20) * 1000000 + r.nextInt(1000000);
      final onHand = 1 + r.nextInt(5000);
      final qtyOut = r.nextInt(onHand + 50);
      final exit = wacExitValue(totalValue, onHand, qtyOut);
      expect(exit, inInclusiveRange(0, totalValue),
          reason: 'حالة $caseNo: الخروج داخل قيمة المخزون');
      if (qtyOut == 0) {
        expect(exit, 0, reason: 'حالة $caseNo: لا خروج فلا قيمة');
      }
      if (qtyOut >= onHand) {
        expect(exit, totalValue,
            reason: 'حالة $caseNo: خروج الكل يمتص القيمة كلها');
      }
      // الإغلاق الحرفي: خروج جزء ثم باقي الكمية يبلغ القيمة كلها.
      if (qtyOut < onHand && qtyOut > 0) {
        final rest = wacExitValue(totalValue - exit, onHand - qtyOut,
            onHand - qtyOut);
        expect(exit + rest, totalValue,
            reason: 'حالة $caseNo: الجزء ثم التصفية = القيمة كاملة');
      }
    }
  });

  test('خاصية القيود — 300 قيد عشوائي متوازن تجتاز المدقق، وأي خلل '
      'جانبٍ أو توازن أو حساب يُعلن بنوعه لا بصمت', () {
    final r = seeded();
    final index = _smallIndex();
    const leafIds = [1, 2, 3];
    for (var caseNo = 0; caseNo < 300; caseNo++) {
      // حتى 10^11 بمقطعتين — nextInt مقيدة بـ 2^32.
      final total =
          20 + r.nextInt(1 << 20) * 100000 + r.nextInt(100000);
      final debitCount = 2 + r.nextInt(4);
      final creditCount = 2 + r.nextInt(4);
      final lines = <MoveLineDraft>[
        for (final part
            in _positiveParts(r, total, debitCount))
          MoveLineDraft(
              accountId: leafIds[r.nextInt(3)],
              debitMinor: part,
              partyId: r.nextInt(3) == 0 ? 1 + r.nextInt(30) : null),
        for (final part in _positiveParts(r, total, creditCount))
          MoveLineDraft(accountId: leafIds[r.nextInt(3)], creditMinor: part),
      ];
      final draft = MoveDraft(
        journalId: 5,
        dateText: _isoDate(r),
        narration: 'قيد خاصية $caseNo',
        lines: lines,
      );
      expect(validateMoveDraft(draft, index: index), isEmpty,
          reason: 'حالة $caseNo: المتوازن المولَّد سليم بنية');

      final unbalanced = MoveDraft(
        journalId: draft.journalId,
        dateText: draft.dateText,
        lines: [
          for (final l in draft.lines)
            l == draft.lines.first
                ? MoveLineDraft(
                    accountId: l.accountId,
                    debitMinor: l.debitMinor + 1,
                    creditMinor: l.creditMinor)
                : l,
        ],
      );
      final errors = validateMoveDraft(unbalanced, index: index);
      expect(errors.whereType<MoveUnbalanced>(), hasLength(1),
          reason: 'حالة $caseNo: الخلل الواحد يعلن مرة');
    }
  });

  test('أطراف القيد المرفوضة تعلن بنوعها — الجانب المزدوج والفارغ '
      'والسالب والحساب الغريب وقصر الأسطر', () {
    final index = _smallIndex();
    MoveDraft move(List<MoveLineDraft> lines) => MoveDraft(
        journalId: 5, dateText: '2026-11-01', lines: lines);

    expect(validateMoveDraft(move([MoveLineDraft(accountId: 1, debitMinor: 7)]),
            index: index),
        everyElement(isA<MoveTooFewLines>()));
    expect(
        validateMoveDraft(
            move([
              MoveLineDraft(accountId: 1, debitMinor: 5, creditMinor: 5),
              MoveLineDraft(accountId: 2, creditMinor: 5),
            ]),
            index: index),
        everyElement(isA<MoveLineBothSides>()));
    expect(
        validateMoveDraft(
            move([
              MoveLineDraft(accountId: 1),
              MoveLineDraft(accountId: 2, creditMinor: 5),
            ]),
            index: index),
        everyElement(isA<MoveLineEmptySide>()));
    expect(
        validateMoveDraft(
            move([
              MoveLineDraft(accountId: 1, debitMinor: -1),
              MoveLineDraft(accountId: 2, creditMinor: 5),
            ]),
            index: index),
        everyElement(isA<MoveLineAmountInvalid>()));
    expect(
        validateMoveDraft(
            move([
              MoveLineDraft(accountId: 99, debitMinor: 5),
              MoveLineDraft(accountId: 2, creditMinor: 5),
            ]),
            index: index),
        everyElement(isA<MoveAccountNotLedgerable>()));
    expect(
        validateMoveDraft(
            move([
              MoveLineDraft(accountId: 1, debitMinor: 6),
              MoveLineDraft(accountId: 2, creditMinor: 5),
            ]),
            index: index),
        everyElement(isA<MoveUnbalanced>()));
  });

  test('خاصية السندات — 200 سند عشوائي سليم تجتاز المدقق، والمطابقات '
      'الرديئة والمبالغ الصفرية والطرفية المزدوجة تُعلن بنوعها', () {
    final r = seeded();
    for (var caseNo = 0; caseNo < 200; caseNo++) {
      final kind = r.nextBool() ? VoucherKind.receipt : VoucherKind.payment;
      final byParty = r.nextBool();
      final draft = VoucherDraft(
        kind: kind,
        dateText: _isoDate(r),
        partyId: byParty ? 1 + r.nextInt(50) : null,
        directAccountId: byParty ? null : (kind == VoucherKind.payment ? 51 : 41),
        cashBoxId: 1 + r.nextInt(5),
        amountDocMinor: 1 + r.nextInt(1000000000),
        narration: 'سند خاصية $caseNo',
      );
      expect(validateVoucherDraftStructure(draft), isEmpty,
          reason: 'حالة $caseNo: السند المولَّد سليم البنية');
      expect(draft.appliedDocTotal, 0,
          reason: 'حالة $caseNo: بلا مطابقات فالمطبَّق صفر');
    }

    VoucherDraft voucher(VoucherDraft base, {int? amount, int? party, int? direct,
        String? date, List<VoucherAllocationDraft>? allocations}) =>
        VoucherDraft(
          kind: base.kind,
          dateText: date ?? base.dateText,
          partyId: party ?? base.partyId,
          directAccountId: direct ?? base.directAccountId,
          cashBoxId: base.cashBoxId,
          amountDocMinor: amount ?? base.amountDocMinor,
          allocations: allocations ?? base.allocations,
        );

    final good = VoucherDraft(
        kind: VoucherKind.receipt,
        dateText: '2026-11-01',
        partyId: 7,
        cashBoxId: 1,
        amountDocMinor: 1000);
    expect(validateVoucherDraftStructure(voucher(good, amount: 0)),
        everyElement(isA<VoucherAmountInvalid>()));
    expect(
        validateVoucherDraftStructure(
            voucher(good, party: null, direct: 51)),
        everyElement(isA<VoucherPartyAndAccountExclusive>()));
    expect(validateVoucherDraftStructure(voucher(good, date: '2026/11/01')),
        everyElement(isA<VoucherDateInvalid>()));
    expect(
        validateVoucherDraftStructure(voucher(good,
            allocations: [VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 0)])),
        everyElement(isA<VoucherAllocationAmountInvalid>()));
    expect(
        validateVoucherDraftStructure(voucher(good,
            allocations: [
              VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 100),
              VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 100),
            ])),
        everyElement(isA<VoucherAllocationDuplicated>()));
    expect(
        validateVoucherDraftStructure(voucher(good,
            allocations: [VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 1500)])),
        everyElement(isA<VoucherAllocationsExceedAmount>()));
    final withDirect = VoucherDraft(
        kind: VoucherKind.payment,
        dateText: '2026-11-01',
        directAccountId: 51,
        cashBoxId: 1,
        amountDocMinor: 500);
    expect(
        validateVoucherDraftStructure(VoucherDraft(
            kind: withDirect.kind,
            dateText: withDirect.dateText,
            directAccountId: 51,
            cashBoxId: 1,
            amountDocMinor: 500,
            allocations: [VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 100)])),
        everyElement(isA<VoucherAllocationWithDirectAccount>()));
  });
}
