import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  group('تكلفة الخروج بالقيمة الإجمالية (F-047/D-067) — لا غبار تقريب', () {
    test('الخروج الجزئي يقرب بالنصف بعيداً عن الصفر', () {
      // 100 وحدة قيمة على 3 قطع: الواحدة 33.33 → 33
      expect(wacExitValue(100, 3, 1), 33);
      // 25 على 2: 12.5 → 13 (النصف بعيداً عن الصفر — س7)
      expect(wacExitValue(25, 2, 1), 13);
      expect(wacExitValue(250000, 10, 4), 100000,
          reason: 'مثال س-53: 250,000 على 10 والخروج 4 = 100,000 تام');
    });
    test('الخروج بكل الكمية يمتص القيمة كلها', () {
      expect(wacExitValue(150000, 6, 6), 150000);
      expect(wacExitValue(7, 3, 3), 7);
      expect(wacExitValue(7, 3, 5), 7, reason: 'الطلب فوق الرصيد يمثل الكل — '
          'والرفض شأن المدقق قبل الوصول لما');
    });
    test('على مخزون فارغ لا قيمة تُخرج — صفر كامل والفرق على 58 (س-56)', () {
      expect(wacExitValue(0, 0, 2), 0);
      expect(wacExitValue(50000, 0, 3), 0);
      expect(wacExitValue(100, 3, 0), 0);
    });
  });

  group('التحويل للعملة الأساسية (F-122/D-082) — لقطة مكبّرة 10^6', () {
    test('لقطة الأساسية محايدة تخزيناً', () {
      expect(convertToBaseMinor(250000, baseCurrencyFxRate), 250000);
      expect(baseCurrencyFxRate, 1000000);
    });
    test('الدولار: 100.00 دولار بسعر 15,000 = 1,500,000 ليرة', () {
      const usdFx = 15000 * fxRateScale; // 15,000,000,000
      expect(convertToBaseMinor(10000, usdFx), 150000000,
          reason: '10,000 وحدة صغرى (100 دولار) × 15,000 / 10^6');
    });
    test('التقريب للنصف بعيداً عن الصفر', () {
      // 1 وحدة صغرى بسعر 12.5 → 12.5 → 13
      expect(convertToBaseMinor(1, 12500000), 13);
      // 1 بسعر 12.4 → 12
      expect(convertToBaseMinor(1, 12400000), 12);
    });
  });

  group('مجاميع الفاتورة وتوزيع الخصم (س7/س-06) — السطر الأخير يمتص', () {
    test('خصم سطرية فقط بلا خصم فاتورة', () {
      final draft = InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-15',
        partyId: 1,
        lines: const [
          InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 2, unitPriceMinor: 40000, discountMinor: 5000),
          InvoiceLineDraft(itemId: 2, unitId: 1, qtyBase: 1, unitPriceMinor: 15000),
        ],
      );
      final totals = computeInvoiceTotals(draft);
      expect(totals.subtotalDocMinor, 90000,
          reason: '75,000 (زيت بعد خصمه) + 15,000 (تغليف)');
      expect(totals.discountDocMinor, 0);
      expect(totals.totalDocMinor, 90000);
      expect(totals.lines[0].netDocMinor, 75000);
      expect(totals.lines[1].netDocMinor, 15000);
      expect(totals.totalBaseMinor, 90000);
    });
    test('خصم فاتورة 10% على مجاميع كسرية — المجموع يستوي حرفاً', () {
      // 30,003 + 9,999 = 40,002؛ خصم 10% = 4,000 (4,000.2 → 4,000)
      final draft = InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: '2026-03-15',
        partyId: 1,
        discountRate: 1000,
        lines: const [
          InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 3, unitPriceMinor: 10001),
          InvoiceLineDraft(itemId: 2, unitId: 1, qtyBase: 1, unitPriceMinor: 9999),
        ],
      );
      final totals = computeInvoiceTotals(draft);
      expect(totals.subtotalDocMinor, 40002);
      expect(totals.discountDocMinor, 4000);
      expect(totals.totalDocMinor, 36002);
      // السطر الأول النسبي: 30,003×4,000/40,002 = 3,000.15 → 3,000
      // والسطر الأخير يمتص: 4,000 − 3,000 = 1,000
      expect(totals.lines[0].netDocMinor, 27003);
      expect(totals.lines[1].netDocMinor, 8999);
      var sum = 0;
      for (final l in totals.lines) {
        sum += l.netDocMinor;
      }
      expect(sum, totals.totalDocMinor,
          reason: 'لا غبار تقريب — مجموع الأسطر يساوي الصافي حرفاً');
      var sumBase = 0;
      for (final l in totals.lines) {
        sumBase += l.baseMinor;
      }
      expect(sumBase, totals.totalBaseMinor);
      // نصيب السطر الأساسي توزيع نسبي لا محايد (علة س32): زيت 27,003
      expect(totals.lines[0].baseMinor, 27003);
      expect(totals.lines[1].baseMinor, 8999);
    });
    test('س-117 (D-112): الخصم العشري 3.5% — مخزناً ×100 والمقام 10,000',
        () {
      // مثال المالك حرفاً «ألا أستطيع إدخال خصم 3.5٪؟» — 30,000 × 3.5%
      // = 1,050 خصماً والصافي 28,950.
      final draft = InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-15',
        partyId: 1,
        discountRate: 350,
        lines: const [
          InvoiceLineDraft(
              itemId: 1, unitId: 1, qtyBase: 2, unitPriceMinor: 15000),
        ],
      );
      final totals = computeInvoiceTotals(draft);
      expect(totals.subtotalDocMinor, 30000);
      expect(totals.discountDocMinor, 1050);
      expect(totals.totalDocMinor, 28950);
      expect(totals.lines[0].netDocMinor, 28950);
      // العرض الإنساني للنسبة المخزنة — بلا أصفار زائدة
      expect(formatPercentRate(350), '3.5');
      expect(formatPercentRate(1000), '10');
      expect(formatPercentRate(275), '2.75');
      expect(formatPercentRate(10000), '100');
      expect(formatPercentRate(0), '0');
      // والحدود: 100% سليمة وما بعدها مرفوضة
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            discountRate: 10000,
            lines: const [
              InvoiceLineDraft(
                  itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 100),
            ])),
        isNot(contains(isA<InvoiceDiscountRateInvalid>())),
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            discountRate: 10050,
            lines: const [
              InvoiceLineDraft(
                  itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 100),
            ])),
        contains(isA<InvoiceDiscountRateInvalid>()),
      );
    });
    test('هدية بسعر صفر لا تفسد التوزيع', () {
      final draft = InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-15',
        cashBoxId: 1,
        lines: const [
          InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 2, unitPriceMinor: 10000),
          InvoiceLineDraft(itemId: 2, unitId: 1, qtyBase: 1, unitPriceMinor: 0),
        ],
      );
      final totals = computeInvoiceTotals(draft);
      expect(totals.totalDocMinor, 20000);
      expect(totals.lines[1].netDocMinor, 0);
    });
  });

  group('المدقق البنيوي (س-51..س-55) — التسلسل التدريجي بأخطاء محمولة', () {
    InvoiceDraft base({InvoiceKind kind = InvoiceKind.sale}) => InvoiceDraft(
          kind: kind,
          dateText: '2026-03-15',
          partyId: 1,
          lines: const [
            InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 2, unitPriceMinor: 40000),
          ],
        );

    test('الفاتورة السليمة تفحص بلا أخطاء', () {
      expect(validateInvoiceDraftStructure(base()), isEmpty);
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
          kind: InvoiceKind.purchase,
          dateText: '2026-03-15',
          cashBoxId: 1,
          lines: const [
            InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 3, unitPriceMinor: 25000),
          ],
        )),
        isEmpty,
      );
    });
    test('التاريخ أولاً ثم المرجع للمردود ثم جهة الدفع', () {
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale, dateText: '15/03/2026', partyId: 1, lines: const [])),
        contains(isA<InvoiceDateInvalid>()),
      );
      final noSide = base();
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: noSide.kind,
            dateText: noSide.dateText,
            lines: noSide.lines)),
        contains(isA<InvoiceMissingPaymentSide>()),
        reason: 'لا صندوق ولا طرف — النقدي يطلب صندوقاً والآجل يطلب طرفاً',
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.saleReturn,
            dateText: '2026-03-15',
            partyId: 1,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 40000),
            ])),
        contains(isA<InvoiceOriginalRequired>()),
      );
    });
    test('العملة واللقطة: الأساسية 1,000,000 دائماً والدولار موجبة', () {
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            currencyId: 3,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 100),
            ])),
        contains(isA<InvoiceCurrencyInvalid>()),
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            fxRate: 2,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 100),
            ])),
        contains(isA<InvoiceFxRateInvalid>()),
        reason: 'عملة الأساسية لقطتها 1,000,000 حصراً (D-082 معروض)',
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            currencyId: 2,
            fxRate: 15000 * fxRateScale,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 10000),
            ])),
        isEmpty,
      );
    });
    test('الأسطر: لا أسطر، كمية فاسدة، سعر سالب، خصم فاسد، خصم كلي فاسد', () {
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale, dateText: '2026-03-15', partyId: 1, lines: const [])),
        contains(isA<InvoiceNoLines>()),
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 0, unitPriceMinor: 100),
            ])),
        contains(isA<InvoiceLineQtyInvalid>()),
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: -5),
            ])),
        contains(isA<InvoiceLinePriceInvalid>()),
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 2, unitPriceMinor: 100, discountMinor: 201),
            ])),
        contains(isA<InvoiceLineDiscountInvalid>()),
      );
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            discountRate: 10050,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 100),
            ])),
        contains(isA<InvoiceDiscountRateInvalid>()),
      );
    });
    test('الصافي صفر مرفوض — لا قيد بلا مبالغ', () {
      expect(
        validateInvoiceDraftStructure(InvoiceDraft(
            kind: InvoiceKind.sale,
            dateText: '2026-03-15',
            partyId: 1,
            lines: const [
              InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 0),
            ])),
        contains(isA<InvoiceZeroTotal>()),
      );
    });
    test('النقدية معرَّفة بوجود الصندوق لا بتعداد ثالث', () {
      final cash = InvoiceDraft(
          kind: InvoiceKind.sale,
          dateText: '2026-03-15',
          cashBoxId: 2,
          partyId: 1,
          lines: const [
            InvoiceLineDraft(itemId: 1, unitId: 1, qtyBase: 1, unitPriceMinor: 100),
          ]);
      expect(cash.isCash, isTrue, reason: 'نقدي بطرف معروف مشروع (س-03 نفسها)');
    });
  });

  group('الترقيم (D-080 معروض) — تسلسل لكل نوع وأسماء كاملة (م-44)', () {
    test('مفاتيح التسلسل الأربعة وأسماؤها', () {
      expect(invoiceSequenceKind(InvoiceKind.sale), 'invoice_sale');
      expect(invoiceSequenceKind(InvoiceKind.purchase), 'invoice_purchase');
      expect(invoiceSequenceKind(InvoiceKind.saleReturn), 'invoice_sale_return');
      expect(
          invoiceSequenceKind(InvoiceKind.purchaseReturn),
          'invoice_purchase_return');
      expect(sequenceKindLabels['invoice_sale'], 'فاتورة بيع');
      expect(sequenceKindLabels['move_sales'], 'قيد مبيعات');
      expect(sequenceKindLabels['move_purchase'], 'قيد مشتريات');
      expect(sequenceKindLabels['move_general'], 'قيد عام');
    });
    test('صيغة الرقم الجديدة D-169 (سنة رقمين + عدّاد مبطن بلا فاصل)', () {
      expect(formatDocumentNumber(2026, 1), '26000001');
      expect(formatDocumentNumber(2026, 123456), '26123456');
    });
    test('أوصاف الأخطاء تحمل أرقامها وأصحابها', () {
      expect(
        describeInvoiceValidationError(
            const InvoiceStockInsufficient(0, 'زيت (Z-100)', 10)),
        contains('زيت (Z-100)'),
      );
      expect(
        describeInvoiceValidationError(
            const InvoiceReturnQtyExceedsRemaining(1, 'زيت (Z-100)', 2)),
        contains('المتبقي (2)'),
      );
      expect(
        describeInvoiceValidationError(const InvoiceBoxInsufficient('الصندوق الرئيسي', 0)),
        contains('الصندوق الرئيسي'),
      );
    });
  });

  group('لقطة الوحدة والعامل (س-10/D-031، الدفعة 30)', () {
    test('قيمة السطر بالتعبئة: كمية المستوى × سعر وحدة الاختيار حصراً — '
        'لا qtyBase × السعر (المثال الحرفي للسير 06)', () {
      final line = InvoiceLineDraft(
        itemId: 1,
        unitId: 1,
        qty: 3,
        unitLevelId: 7,
        qtyBase: 36,
        unitPriceMinor: 12000,
      );
      expect(line.grossDocMinor, 36000, reason: '3 علب × 12,000 — و36 × '
          '12,000 كان ليعطي 432,000 كذباً');
      final totals = computeInvoiceTotals(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-15',
        cashBoxId: 2,
        lines: [line],
      ));
      expect(totals.subtotalDocMinor, 36000);
      expect(totals.totalDocMinor, 36000);
      expect(totals.lines.single.line.qtyBase, 36,
          reason: 'المحرك المخزني على الأساسية كما هي');
    });

    test('بالأساسية مطابق القائم حرفاً: qty فارغة فالقيمة qtyBase × السعر', () {
      final line = InvoiceLineDraft(
          itemId: 1, unitId: 1, qtyBase: 36, unitPriceMinor: 1000);
      expect(line.grossDocMinor, 36000);
    });

    test('كمية المستوى صفر أو سالبة مرفوضة بمدقق البنية برسالة الكمية', () {
      final errors = validateInvoiceDraftStructure(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-15',
        cashBoxId: 2,
        lines: [
          InvoiceLineDraft(
              itemId: 1,
              unitId: 1,
              qtyBase: 24,
              qty: 0,
              unitLevelId: 7,
              unitPriceMinor: 1000),
        ],
      ));
      expect(errors, contains(isA<InvoiceLineQtyInvalid>()));
    });

    test('خصم السطر يتقاس على القيمة بالتعبئة لا على qtyBase × السعر', () {
      // قيمة السطر 3 × 12,000 = 36,000 — خصم 40,000 يتجاوزها رغم أن
      // 36 × 12,000 = 432,000 كان سيمرّه لو بقي الضرب القديم.
      final errors = validateInvoiceDraftStructure(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-03-15',
        cashBoxId: 2,
        lines: [
          InvoiceLineDraft(
              itemId: 1,
              unitId: 1,
              qtyBase: 36,
              qty: 3,
              unitLevelId: 7,
              unitPriceMinor: 12000,
              discountMinor: 40000),
        ],
      ));
      expect(errors, contains(isA<InvoiceLineDiscountInvalid>()));
    });

    test('أوصاف أخطاء الوحدة تحمل السطر والمستوى والعامل (رسائل صادقة)', () {
      expect(
        describeInvoiceValidationError(
            const InvoiceUnitLevelInvalid(0, 'زيت (Z-100)')),
        contains('لا يعود لمجموعة الصنف'),
      );
      expect(
        describeInvoiceValidationError(
            const InvoiceUnitFactorMismatch(0, 'زيت (Z-100)', 2, 12, 36)),
        contains('2 × 12'),
        reason: 'الرسالة تُظهر الكمية والعامل والمخالفة معاً',
      );
      expect(
        describeInvoiceValidationError(
            const InvoiceUnitFactorMismatch(0, 'زيت (Z-100)', 2, 12, 36)),
        contains('36'),
      );
    });
  });
}
