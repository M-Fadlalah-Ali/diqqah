import 'dart:convert';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الوحدة 3 «كميات المخزون الافتتاحية» بالتخزين — الدفعة
/// الثالثة (التشطيب — س142): إذن إدخال مخزون قياسي (F-209) بمعاملة
/// واحدة كل-أو-لا شيء عبر المحرك الموحد حصراً (07 §1.1) — 113 مديناً
/// بقيم الملف الصريحة ومقابله 43 الافتراضي لا 332 الافتتاحي (هذا إذن
/// مخزون لا قيد افتتاحِ ذمم)، والوحدات والأصناف تنشأ آلياً، والافتتاحي
/// أول المرحّل (د-6)، ولقطة أسعار القيم بسجلها (§25.4)، وكل رفض يتراجع
/// كله بما فيه العدّاد (07 §1.9).
void main() {
  late DiqqahDatabase db;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() => db.close());

  /// تاريخ اليوم ISO — قاعدة بلا قيود المرحلة تفتح فتراتها بأمان.
  String todayIso() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  List<int> qtyBytes(List<String> rows) => utf8.encode([
        'dq-import:opening_qty,1',
        'كود الصنف,الاسم,الكمية,القيمة,الوحدة,العملة,سعر الصرف',
        ...rows,
      ].join('\n'));

  Future<OpeningQtyImportPlan> planQty(List<String> rows,
      {String? date}) async {
    return db.planOpeningQtyImportFromDb(
      parseOpeningQtyFile(qtyBytes(rows)),
      openingDateText: date ?? todayIso(),
    );
  }

  group('الوحدة 3 — إذن إدخال قياسي بمعاملة واحدة عبر المحرك', () {
    test('إذن مرحّل: 113 مدين بقيم الملف ومقابله 43 الافتراضي — لا 332',
        () async {
      final plan = await planQty([
        'SKU1,صنف أول,10,5000,قطعة,SYP,',
        'SKU2,صنف ثانٍ,3,100,كرتون,USD,15000',
      ]);
      expect(plan.isApprovable, isTrue, reason: plan.errors.toString());
      final result = await db.executeOpeningQtyImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      expect(result.itemsCreated, 2);
      expect(result.unitsCreated, 2);
      expect(result.partiesCreated, 0);
      expect(result.boxesCreated, 0);
      expect(result.receiptNumber, isNotNull);
      expect(result.moveNumber, isNull,
          reason: 'الإذن يرحل قيده الخاص — لا قيد افتتاحِ ذمم منفصل');
      expect(result.debitBaseMinor, 150500000,
          reason: '5000.00 + (100.00 × 15000) = 1,505,000.00 ليرة');

      // الإذن: 113 مدين بقيمة الملف / 43 دائناً بالافتراضي (F-209)
      // — ولا 332 إطلاقاً: هذا إذن مخزون لا قيد افتتاحِ ذمم.
      final receiptMoveLines = await db.customSelect(
        "SELECT a.code AS code, l.debit_minor, l.credit_minor "
        "FROM move_lines l JOIN moves m ON m.id = l.move_id "
        "JOIN accounts a ON a.id = l.account_id "
        "WHERE m.ref_doc_type = 'stock_receipt'",
      ).get();
      final debit113 = receiptMoveLines
          .where((l) => l.data['code'] == '113')
          .fold(0, (s, l) => s + (l.data['debit_minor'] as int));
      expect(debit113, 150500000,
          reason: 'سطر 113 لكل صف ملف — والمجموع قيمة الملف كاملة');
      final credit43 = receiptMoveLines
          .where((l) => l.data['code'] == '43')
          .fold(0, (s, l) => s + (l.data['credit_minor'] as int));
      expect(credit43, 150500000);
      expect(receiptMoveLines.map((l) => l.data['code']),
          isNot(contains('332')),
          reason: 'المقابل 43 الافتراضي (F-209) لا 332 الافتتاحي');

      // قيم الإذن الصريحة على أسطره (لا تقييم D-186) بالأسطر اثنين.
      final receiptLines = await db.customSelect(
        'SELECT qty_base, value_base_minor FROM stock_receipt_lines '
        'ORDER BY qty_base',
      ).get();
      expect(receiptLines, hasLength(2));
      expect(receiptLines.first.data['qty_base'] as int, 3);
      expect(receiptLines.first.data['value_base_minor'] as int, 150000000,
          reason: '100 دولار × 15000 ليرة');
      expect(receiptLines.last.data['qty_base'] as int, 10);
      expect(receiptLines.last.data['value_base_minor'] as int, 500000);

      // أرصدة المخزون حملت الكميات والقيم بالمحرك الموحد.
      final balances = await db.customSelect(
        'SELECT qty_base, total_value_minor FROM stock_balances '
        'ORDER BY qty_base',
      ).get();
      expect(balances, hasLength(2));
      expect(balances.first.data['qty_base'] as int, 3);
      expect(balances.last.data['total_value_minor'] as int, 500000);

      // الميزان متوازن حرفاً بعد الإذن الافتتاحي.
      final tb = await db.trialBalanceReport();
      expect(tb.isBalanced, isTrue);

      // وحدث الاستيراد بنفس المعاملة (D-076) بعداداته.
      final events = await db.importEventsSince(0);
      expect(events, hasLength(1));
      expect(events.single.unit, 'opening_qty');
      expect(events.single.itemsCreated, 2);
      expect(events.single.unitsCreated, 2);
    });

    test('الاستيراد الثاني بعد الترحيل مرفوض DQ-1025 — الافتتاحي أول',
        () async {
      final first = await planQty(['SKU1,صنف أول,10,5000,قطعة,SYP,']);
      await db.executeOpeningQtyImport(
        first,
        eventBackupName: 'event-backup.dqk',
      );
      // إذن مرحّل بتاريخ اليوم فتاريخ اليوم نفسه لم يعد أسبق منه.
      final second = await planQty(['SKU2,صنف ثانٍ,5,2500,قطعة,SYP,']);
      expect(second.isApprovable, isFalse);
      expect(second.errors.any((e) => e.dqCode == 'DQ-1025'), isTrue);
    });

    test('لقطة سعر القيمة تسجل بتاريخ الافتتاحي (07 §1.7/§25.4)', () async {
      final plan = await planQty(['SKU1,صنف أول,3,100,كرتون,USD,15000']);
      await db.executeOpeningQtyImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      final rates = await db.exchangeRatesOf(2);
      expect(rates, isNotEmpty);
      expect(rates.last.rateToBase, 15000 * 1000000);
      expect(rates.last.date, todayIso());
    });

    test('كل-أو-لا شيء: اصطدام اسم بين المعاينة والاعتماد يرجع المعاملة '
        'كلها بما فيها الوحدات (07 §1.9)', () async {
      final plan = await planQty(['SKU1,صنف أول,10,5000,قطعة,SYP,']);
      expect(plan.isApprovable, isTrue);
      // صنف قائم بصنف الاسم نفسه يُزرع بين المعاينة والاعتماد.
      await db.insertItem(
        sku: 'OTHER',
        name: 'صنف أول',
        kind: 'good',
        baseUnitId: await db.insertUnit(name: 'وحدة زائدة'),
        purchasePriceMinor: 0,
        salePriceMinor: 0,
        priceCurrencyId: 1,
      );
      await expectLater(
        db.executeOpeningQtyImport(
          plan,
          eventBackupName: 'event-backup.dqk',
        ),
        throwsA(isA<ImportExecutionException>()),
      );
      // والتراجع كله: لا وحدة ولا صنف ولا إذن ولا حدث.
      final units = await db.customSelect(
        "SELECT id FROM units WHERE name = 'قطعة'",
      ).get();
      expect(units, isEmpty, reason: 'الوحدة رجعت بتراجع المعاملة');
      final items = await db.customSelect(
        "SELECT id FROM items WHERE sku = 'SKU1'",
      ).get();
      expect(items, isEmpty);
      final receipts = await db.customSelect(
        'SELECT id FROM stock_receipts',
      ).get();
      expect(receipts, isEmpty);
      final events = await db.importEventsSince(0);
      expect(events, isEmpty);
    });
  });
}
