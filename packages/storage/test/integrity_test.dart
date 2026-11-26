import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart' show Variable;

/// اختبارات فحص الثوابت الآلي (F-006، 07 §1.10، D-067) — دفعة إغلاق
/// النواة (س37). القاعدة سليمة بنهاية دورة معروفة = تقرير نظيف 7/7؛
/// ثم كل ثابت يُكسر عمداً (10 §4: الثابت الذي لم يُكسر غير مجرَّب) —
/// الكسر بطعن SQL مباشر تحت الحواجز لا عبر المحرك، فهذا ما يكشفه
/// الفحص: طعن خارجي لا رفض المحرك.
void main() {
  late DiqqahDatabase db;

  Future<int> accountIdByCode(String code) async {
    final rows = await db.customSelect(
      'SELECT id FROM accounts WHERE code = ?',
      variables: [Variable.withString(code)],
    ).get();
    return rows.first.data['id'] as int;
  }

  /// أرضية مشتركة: دورة كاملة معروفة (نمط س-51/س-66/درس F-042) — ضخ
  /// رأس مال، شراء آجل يبني المخزون، بيع خدمة نقدي، بيع بضاعة آجل —
  /// فيكون كل الثوابت السبعة سليمة بنهايتها.
  Future<void> seedCleanCycle() async {
    final rows =
        await db.customSelect('SELECT name, state FROM fiscal_years').get();
    final year = int.parse(rows.first.data['name'] as String);
    final date = '$year-03-15';
    final unitId = await db.insertUnit(name: 'قطعة');
    final oilId = await db.insertItem(
      sku: 'OIL-1',
      name: 'زيت',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 10000,
      salePriceMinor: 15000,
      priceCurrencyId: 1,
    );
    final serviceId = await db.insertItem(
      sku: 'SRV-1',
      name: 'خدمة',
      kind: 'service',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 20000,
      priceCurrencyId: 1,
    );
    final customerId = await db.insertParty(
      number: 'C-001',
      name: 'عميل الدورة',
      kind: 'customer',
      defaultCurrencyId: 1,
    );
    final supplierId = await db.insertParty(
      number: 'S-001',
      name: 'مورد الدورة',
      kind: 'supplier',
      defaultCurrencyId: 1,
    );
    final boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final warehouseId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;

    // ضخ رأس مال (س-66) — تمويل الصندوق
    final capital = await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: date,
      directAccountId: await accountIdByCode('311'),
      cashBoxId: boxId,
      amountDocMinor: 500000,
    ));
    await db.postVoucher(capital);

    // شراء آجل يبني المخزون (س-04) — 20 × 10,000
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId,
            unitId: unitId,
            qtyBase: 20,
            unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchase);

    // بيع خدمة نقدي (بلا مساس بالمخزون)
    final cashSale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      cashBoxId: boxId,
      lines: [
        InvoiceLineDraft(
            itemId: serviceId,
            unitId: unitId,
            qtyBase: 1,
            unitPriceMinor: 20000),
      ],
    ));
    await db.postInvoice(cashSale);

    // بيع بضاعة آجل (س-07) — 10 من مخزون 20 (درس F-042: لا بيع على صفر)
    final creditSale = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId,
            unitId: unitId,
            qtyBase: 10,
            unitPriceMinor: 15000),
      ],
    ));
    await db.postInvoice(creditSale);
  }

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    await seedCleanCycle();
  });

  tearDown(() async {
    await db.close();
  });

  test('الدورة المعروفة سليمة: الفحوص السبعة كلها نظيفة (7/7)', () async {
    final report = await db.integrityCheckReport();
    expect(report.isClean, isTrue,
        reason:
            'خروقات الدورة النظيفة: ${[for (final v in report.violations) v.toString()]}');
    expect(report.violations, isEmpty);
    expect(report.summary, 'الفحوص السبعة سليمة (7/7)');
  });

  test('T1 — قيد مرحّل غير متوازن مكسور بالطعن المباشر يُكشف', () async {
    // الطعن تحت الحواجز: السطر يُدرج أولاً بلا قيد أم (حالته ليست
    // مرحّلة فيسمح الإدراج) ثم القيد المرحّل يُبنى بعده بمعرف معلوم —
    // فلا انتقال حالة يمر بحرس التوازن أصلاً.
    await db.customStatement(
      "INSERT INTO move_lines (move_id, account_id, debit_minor, credit_minor, uuid) "
      "VALUES (900001, ${await accountIdByCode('1111')}, 1000, 0, 'tl-t1')",
    );
    await db.customStatement(
      "INSERT INTO moves (id, journal_id, date_text, state, number, uuid) "
      "VALUES (900001, 1, '2026-03-15', 'posted', 'قيد عام 2026/900001', 'mv-t1')",
    );
    final report = await db.integrityCheckReport();
    final t1 = report.violations.where((v) => v.checkCode == 'T1').toList();
    expect(t1, hasLength(1));
    expect(t1.single.detail, contains('900001'));
    expect(report.isClean, isFalse);
  });

  test('T2 — رصيد مخزون سالب مكسور بالإدراج المباشر يُكشف', () async {
    // حاجز السالب على UPDATE حصراً — الإدراج المباشر السالب يمرّ وهو
    // عين الخرق الذي يصطاده الفحص (طعن خارجي لا مسار محرك).
    // مستودع غير موجود كي لا يصطدم قيد UNIQUE (item، warehouse) برصيد
    // الدورة القائم — والفحص يقرأ السجل بلا انضمام فيمسكه.
    final itemRow = await db.customSelect(
      "SELECT id FROM items WHERE sku = 'OIL-1'",
    ).get();
    await db.customStatement(
      "INSERT INTO stock_balances (item_id, warehouse_id, qty_base, "
      "total_value_minor, uuid) VALUES (${itemRow.first.data['id']}, "
      "999999, -5, -50000, 'sb-t2')",
    );
    final report = await db.integrityCheckReport();
    final t2 = report.violations.where((v) => v.checkCode == 'T2').toList();
    expect(t2, hasLength(1));
    expect(t2.single.detail, contains('-5'));
  });

  test('T3 — حركة صندوق يتيمة (بمستند غير مرحّل) تُكشف', () async {
    // فك الارتباط لا الحذف: حركات الصندوق تُحال إلى معرف مستند غير
    // موجود — والحذف ممنوع بالحاجز، وقطع الرابط هو خرق N-009 نفسه.
    await db.customStatement(
      'UPDATE cash_movements SET ref_doc_id = 999999',
    );
    final report = await db.integrityCheckReport();
    final t3 = report.violations.where((v) => v.checkCode == 'T3').toList();
    expect(t3, hasLength(1));
    expect(t3.single.detail, contains('حركة صندوق'));
  });

  test('T4 — فاتورة مرحّلة بلا قيد مرتبط تُكشف', () async {
    // فاتورة تُبنى SQL خاماً مرحّلةً من البداية (بلا محرك فلا قيد
    // تولَّد لها حصراً) — ولا مساس بفواتير الدورة ولا بأي فحص آخر.
    await db.customStatement(
      "INSERT INTO invoices (kind, invoice_date, fx_rate, state, uuid) "
      "VALUES ('sale', '2026-01-01', 1, 'posted', 'inv-t4')",
    );
    final report = await db.integrityCheckReport();
    final t4 = report.violations.where((v) => v.checkCode == 'T4').toList();
    expect(t4, hasLength(1));
    expect(t4.single.detail, contains('بلا قيد مرتبط'));
  });

  test('M1 — رصيد صندوق في الدفتر يخالف حساب الصندوق بعد طعن الافتتاحي',
      () async {
    await db.customStatement(
      'UPDATE cash_boxes SET opening_balance_base_minor = '
      'opening_balance_base_minor + 5000',
    );
    final report = await db.integrityCheckReport();
    final m1 = report.violations.where((v) => v.checkCode == 'M1').toList();
    expect(m1, hasLength(1));
    expect(m1.single.detail, contains('لا يساوي الصندوق'));
  });

  test('M2 — قيمة المخزون تخرج عن حساب 113 بعد طعن القيمة', () async {
    await db.customStatement(
      'UPDATE stock_balances SET total_value_minor = total_value_minor + 700',
    );
    final report = await db.integrityCheckReport();
    final m2 = report.violations.where((v) => v.checkCode == 'M2').toList();
    expect(m2, hasLength(1));
    expect(m2.single.detail, contains('113'));
  });

  test('M3 — سطر ذمة بلا طرف على حساب السيطرة يُكشف', () async {
    // سطر مدين على 112 بلا طرف (party_id NULL) مع نظيره دائن على
    // الصندوق — القيد متوازن فلا يتحسس T1، والمطابقة الثالثة هي
    // التي تكشف التفكيك بين الدفتر والأطراف (D-067 عينها).
    await db.customStatement(
      "INSERT INTO move_lines (move_id, account_id, debit_minor, party_id, uuid) "
      "VALUES (900002, ${await accountIdByCode('112')}, 300, NULL, 'tl-m3a')",
    );
    await db.customStatement(
      "INSERT INTO move_lines (move_id, account_id, debit_minor, credit_minor, uuid) "
      "VALUES (900002, ${await accountIdByCode('1111')}, 0, 300, 'tl-m3b')",
    );
    await db.customStatement(
      "INSERT INTO moves (id, journal_id, date_text, state, number, uuid) "
      "VALUES (900002, 1, '2026-03-15', 'posted', 'قيد عام 2026/900002', 'mv-m3')",
    );
    final report = await db.integrityCheckReport();
    final m3 = report.violations.where((v) => v.checkCode == 'M3').toList();
    // خرقان لمساوِن من طعن واحد: السطر اليتيم بلا طرف، وانحراف التطابق
    // (مدين 300 على الدفتر لا يجمعه الأطراف) — كلاهما وجه M-067 الثالثة
    // والفحص أظهر الوجهين لا أراهما.
    expect(m3, hasLength(2));
    expect(
      m3.where((v) => v.detail.contains('بلا طرف')),
      hasLength(1),
    );
    expect(
      m3.where((v) => v.detail.contains('112') && v.detail.contains('لا يساوي')),
      hasLength(1),
    );
  });

  test('بذر الأدوار الأربعة (F-080): الأربعة مزروعة بأذوناتها الافتراضية',
      () async {
    final roles = await db.select(db.roles).get();
    final names = roles.map((r) => r.name).toSet();
    expect(names, containsAll(['مدير', 'محاسب', 'أمين مستودع', 'بائع']));
    final manager = roles.firstWhere((r) => r.name == 'مدير');
    expect(manager.permissions, '*');
    final seller = roles.firstWhere((r) => r.name == 'بائع');
    expect(seller.permissions, 'parties,invoices,vouchers');
  });

  test('إعادة البذر آمنة التكرار: الأدوار لا تتضاعف (نمط بذور v6/v7)',
      () async {
    final roles = await db.select(db.roles).get();
    expect(roles.where((r) => r.name == 'مدير'), hasLength(1));
    expect(roles.where((r) => r.name == 'بائع'), hasLength(1));
  });
}
