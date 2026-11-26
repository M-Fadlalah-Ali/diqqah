import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات مجال السندات النقي — دفعة م1 الخامسة (س-61..س-70) بأرقام
/// معروفة: التوزيع بالأقدمية، والمكافئ بلقطة الفاتورة، والفائض «رصيد
/// مقدّم»، والمدقق البنيوي بكل أنواعه.
void main() {
  group('التسلسل والترقيم', () {
    test('مفتاح التسلسل لكل نوع سند على نمط D-080', () {
      expect(voucherSequenceKind(VoucherKind.receipt), 'voucher_receipt');
      expect(voucherSequenceKind(VoucherKind.payment), 'voucher_payment');
    });

    test('أسماء النوع الكامل للعرض (م-44) مسجلة في قاموس التسلسلات', () {
      expect(sequenceKindLabels['voucher_receipt'], 'سند قبض');
      // D-105 (دفعة 8 س39): «سند دفع» حيث الإشارة إلى السند.
      expect(sequenceKindLabels['voucher_payment'], 'سند دفع');
      expect(sequenceKindLabels['box_transfer'], 'تحويل بين صناديق');
      expect(sequenceKindLabels['cash_adjustment'], 'تسوية صندوق');
    });

    test('رقم مستند بالصيغة الموحدة «سند قبض 26000001» (D-169)', () {
      expect(formatDocumentNumber(2026, 1), '26000001');
    });
  });

  group('الفائض والمطبَّق', () {
    test('الفائض غير المطابق «رصيد مقدّم» (س-12/س5): 80 ألف على فاتورة 60', () {
      const draft = VoucherDraft(
        kind: VoucherKind.receipt,
        dateText: '2026-03-01',
        partyId: 7,
        cashBoxId: 1,
        amountDocMinor: 80000,
        allocations: [VoucherAllocationDraft(invoiceId: 11, appliedDocMinor: 60000)],
      );
      expect(draft.appliedDocTotal, 60000);
      expect(draft.unappliedDocMinor, 20000);
    });

    test('المكافئ الأساسي للمطبَّق بلقطة الفاتورة (D-084)', () {
      // 60,000 ليرة: اللقطة الأساسية محايدة فالمكافئ هو المبلغ نفسه.
      expect(allocationBaseMinor(60000, fxRateScale), 60000);
      // 100.00 دولار (10000 وحدة صغرى) بلقطة 15,000: 150,000,000.
      expect(allocationBaseMinor(10000, 15000 * fxRateScale), 150000000);
    });
  });

  group('التوزيع الآلي بالأقدمية (02 §8/س-12)', () {
    test('المستحق أولاً ثم الأقدم — سند 70 ألف على 60 و40 و30', () {
      final out = proposeOldestAllocations(
        amountDocMinor: 70000,
        openInvoices: const [
          OpenInvoiceCandidate(
              invoiceId: 3, remainingDocMinor: 30000, dateText: '2026-03-10', number: '3'),
          OpenInvoiceCandidate(
              invoiceId: 1,
              remainingDocMinor: 60000,
              dateText: '2026-01-05',
              dueDateText: '2026-01-20',
              number: '1'),
          OpenInvoiceCandidate(
              invoiceId: 2,
              remainingDocMinor: 40000,
              dateText: '2026-02-01',
              dueDateText: '2026-02-28',
              number: '2'),
        ],
      );
      // الفاتورة 1 مستحقة أولى ثم 2 بالأقدمية فتأخذ 10 آلاف منها —
      // والباقي «رصيد مقدّم» بلا صفوف.
      expect(out, hasLength(2));
      expect(out[0].invoiceId, 1);
      expect(out[0].appliedDocMinor, 60000);
      expect(out[1].invoiceId, 2);
      expect(out[1].appliedDocMinor, 10000);
    });

    test('السند الأصغر من كل الفواتير يملأ الأولى حصراً', () {
      final out = proposeOldestAllocations(
        amountDocMinor: 25000,
        openInvoices: const [
          OpenInvoiceCandidate(
              invoiceId: 9, remainingDocMinor: 40000, dateText: '2026-01-01', number: '9'),
        ],
      );
      expect(out, hasLength(1));
      expect(out.single.invoiceId, 9);
      expect(out.single.appliedDocMinor, 25000);
    });

    test('سند بلا فواتير مفتوحة يقترح لا شيء — كله رصيد مقدّم', () {
      final out = proposeOldestAllocations(
        amountDocMinor: 50000,
        openInvoices: const [
          OpenInvoiceCandidate(
              invoiceId: 5, remainingDocMinor: 0, dateText: '2026-01-01', number: '5'),
        ],
      );
      expect(out, isEmpty);
    });

    test('المستحق الماضي يسبق الأحدث غير المستحق حتى لو أحدث تسجيله', () {
      final out = proposeOldestAllocations(
        amountDocMinor: 100000,
        openInvoices: const [
          OpenInvoiceCandidate(
              invoiceId: 20, remainingDocMinor: 50000, dateText: '2026-04-01', number: '20'),
          OpenInvoiceCandidate(
              invoiceId: 10,
              remainingDocMinor: 50000,
              dateText: '2026-03-01',
              dueDateText: '2026-03-15',
              number: '10'),
        ],
      );
      expect(out.first.invoiceId, 10);
    });
  });

  group('المدقق البنيوي للسند', () {
    VoucherDraft base({
      String? dateText,
      int? partyId = 1,
      int? directAccountId,
      int amountDocMinor = 50000,
      int fxRate = baseCurrencyFxRate,
      List<VoucherAllocationDraft> allocations = const [],
    }) =>
        VoucherDraft(
          kind: VoucherKind.receipt,
          dateText: dateText ?? '2026-03-01',
          partyId: partyId,
          directAccountId: directAccountId,
          cashBoxId: 1,
          amountDocMinor: amountDocMinor,
          fxRate: fxRate,
          allocations: allocations,
        );

    test('مسودة سليمة تعود بلا أخطاء', () {
      expect(validateVoucherDraftStructure(base()), isEmpty);
    });

    test('تاريخ فاسد', () {
      expect(validateVoucherDraftStructure(base(dateText: '2026/03/01')),
          contains(isA<VoucherDateInvalid>()));
    });

    test('مبلغ صفر مرفوض — الصفر لا مستند له', () {
      expect(validateVoucherDraftStructure(base(amountDocMinor: 0)),
          contains(isA<VoucherAmountInvalid>()));
    });

    test('لقطة غير موجبة مرفوضة (D-082)', () {
      expect(validateVoucherDraftStructure(base(fxRate: 0)),
          contains(isA<VoucherFxRateInvalid>()));
    });

    test('بلا طرف وبلا حساب مرفوض — والاثنان معاً مرفوضان (س-13/س-15)', () {
      expect(validateVoucherDraftStructure(base(partyId: null)),
          contains(isA<VoucherPartyAndAccountExclusive>()));
      expect(
          validateVoucherDraftStructure(base(partyId: 1, directAccountId: 9)),
          contains(isA<VoucherPartyAndAccountExclusive>()));
    });

    test('مطابقات على سند بغير طرف مرفوضة', () {
      expect(
          validateVoucherDraftStructure(base(
              partyId: null,
              directAccountId: 9,
              allocations: const [
                VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 10000)
              ])),
          contains(isA<VoucherAllocationWithDirectAccount>()));
    });

    test('مطبَّق صفر ومكرر مرفوضان', () {
      final errors = validateVoucherDraftStructure(base(allocations: const [
        VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 0),
        VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 10000),
      ]));
      expect(errors, contains(isA<VoucherAllocationAmountInvalid>()));
      expect(errors, contains(isA<VoucherAllocationDuplicated>()));
    });

    test('مجموع المطابقات فوق مبلغ السند مرفوض — والفائض مشروع تحته', () {
      expect(
          validateVoucherDraftStructure(base(allocations: const [
            VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 60000)
          ])),
          contains(isA<VoucherAllocationsExceedAmount>()));
      expect(
          validateVoucherDraftStructure(base(allocations: const [
            VoucherAllocationDraft(invoiceId: 3, appliedDocMinor: 40000)
          ])),
          isEmpty);
    });
  });

  group('المدقق البنيوي للتحويل (س-16)', () {
    test('نفس الصندوق على الطرفين مرفوض', () {
      const draft = CashTransferDraft(
          dateText: '2026-03-01', fromBoxId: 1, toBoxId: 1, amountDocMinor: 10000);
      expect(validateCashTransferStructure(draft),
          contains(isA<TransferSameBox>()));
    });

    test('مبلغ صفر ولقطة صالحة ترفض', () {
      const zero = CashTransferDraft(
          dateText: '2026-03-01', fromBoxId: 1, toBoxId: 2, amountDocMinor: 0);
      expect(
          validateCashTransferStructure(zero), contains(isA<TransferAmountInvalid>()));
    });

    test('تحويل سليم بلا أخطاء', () {
      const draft = CashTransferDraft(
          dateText: '2026-03-01', fromBoxId: 1, toBoxId: 2, amountDocMinor: 10000);
      expect(validateCashTransferStructure(draft), isEmpty);
    });
  });

  group('المدقق البنيوي للتسوية (س-17)', () {
    test('سبب فارغ مرفوض والفرق صفر مرفوض', () {
      const draft = CashAdjustmentDraft(
          dateText: '2026-03-01',
          cashBoxId: 1,
          direction: CashAdjustmentDirection.shortage,
          amountDocMinor: 0,
          reason: '  ');
      final errors = validateCashAdjustmentStructure(draft);
      expect(errors, contains(isA<AdjustmentReasonRequired>()));
      expect(errors, contains(isA<AdjustmentAmountInvalid>()));
    });

    test('عجز بسبب نصي سليم', () {
      const draft = CashAdjustmentDraft(
          dateText: '2026-03-01',
          cashBoxId: 1,
          direction: CashAdjustmentDirection.shortage,
          amountDocMinor: 5000,
          reason: 'عجز حصر فعلي');
      expect(validateCashAdjustmentStructure(draft), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // س105 — دفعة المندوب الرابعة: سقف العهدة — الخطأ المحمول بلسانه
  // (أرقام بوحدات صغرى من العملة الأساسية بعرف رسائل المدقق).
  // ═══════════════════════════════════════════════════════════════
  group('لسان سقف العهدة (س105 — دفعة المندوب الرابعة)', () {
    test('تجاوز السقف يحمل أرقامه الثلاثة بلسانه الصادق', () {
      const error = VoucherCustodyCapExceeded(
        custodyBaseMinor: 60000,
        capBaseMinor: 80000,
        incomingBaseMinor: 30000,
      );
      final text = describeVoucherValidationError(error);
      expect(text, contains('تجاوز سقف العهدة'));
      expect(text, contains('80000'), reason: 'السقف بالرسالة');
      expect(text, contains('60000'), reason: 'العهدة الحالية بالرسالة');
      expect(text, contains('30000'), reason: 'التحصيل الجديد بالرسالة');
      expect(text, contains('سلّم التحصيلات المعلقة'),
          reason: 'لسان الخلاص: التسليم لا السكوت');
    });
  });

// ═══ س162 — بقية فكرة المندوب: شرائح أعمار العهدة (نص س105 الموثق
// «توزيع الأعمار بشرائح (0-7/8-15/…)» — دوال نقية بلا حالة مخزنة) ═══

test('س162: شريحة العمر الحاوية — الحدود الأربع الثابتة بنص التوثيق', () {
  expect(custodyAgeSliceLabel(0), 'حتى 7 أيام');
  expect(custodyAgeSliceLabel(7), 'حتى 7 أيام');
  expect(custodyAgeSliceLabel(8), '8-15 يوماً');
  expect(custodyAgeSliceLabel(15), '8-15 يوماً');
  expect(custodyAgeSliceLabel(16), '16-30 يوماً');
  expect(custodyAgeSliceLabel(30), '16-30 يوماً');
  expect(custodyAgeSliceLabel(31), 'فوق 30 يوماً');
  expect(custodyAgeSliceLabel(90), 'فوق 30 يوماً');
});

test('س162: التوزيع — الشرائح غير الخالية بترتيبها الثابت بعدد ومجموع', () {
  final slices = custodyAgeSliceDistribution([
    (ageDays: 2, totalBaseMinor: 60000),
    (ageDays: 5, totalBaseMinor: 40000),
    (ageDays: 10, totalBaseMinor: 25000),
    (ageDays: 45, totalBaseMinor: 10000),
  ]);
  expect(slices, hasLength(3));
  expect(slices[0], ('حتى 7 أيام', 2, 100000));
  expect(slices[1], ('8-15 يوماً', 1, 25000));
  expect(slices[2], ('فوق 30 يوماً', 1, 10000));
  // والشائعة الغائبة (16-30) لا سطر لها — نمط F-016 إظهار الواقع
});

test('س162: التوزيع الشائع يعود فارغاً والمدخل الواحد شريحة وحدها', () {
  expect(custodyAgeSliceDistribution(const []), isEmpty);
  final one = custodyAgeSliceDistribution([(ageDays: 20, totalBaseMinor: 1)]);
  expect(one, [('16-30 يوماً', 1, 1)]);
});
}
