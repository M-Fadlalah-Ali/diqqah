import 'package:test/test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 24 (أولى م2) — تعدد المستودعات والتحويل بينها
/// (س-18/F-045، س77/D-185).
///
/// الحدود الموثقة: التحويل يُنشأ مرحّلاً بلا مسودة (الرفض قبل الكتابة
/// حصراً)، وحركتا مخزون متقابلتان بلا قيد (05 §6) والقيمة تنتقل كما
/// هي بالمتوسط الجاري المتسلسل للمصدر (D-067) فمجموع قيمة المخزون
/// ثابت، ومنع السالب بالمصدر (F-042)، وآخر مستودع نشط لا يُعطَّل ولا
/// المستودع برصيد قائم (نمط 03 §6-3)، ولا حذف أبداً.
void main() {
  late DiqqahDatabase db;
  late String year;
  late String date;
  late int unitId;
  late int oilId;
  late int riceId;
  late int serviceId;
  late int supplierId;
  late int mainWhId;
  late int branchWhId;

  /// رصيد (كمية، قيمة) صف المستودع أو الأصفار عند الغياب.
  Future<(int, int)> balanceOf(int itemId, int warehouseId) async {
    final rows = await db.customSelect(
      'SELECT qty_base, total_value_minor FROM stock_balances '
      'WHERE item_id = ? AND warehouse_id = ?',
      variables: [Variable.withInt(itemId), Variable.withInt(warehouseId)],
    ).get();
    if (rows.isEmpty) return (0, 0);
    return (
      rows.first.data['qty_base'] as int,
      rows.first.data['total_value_minor'] as int,
    );
  }

  /// مجموع قيمة المخزون الكلية (ثابت 113 = مجموع total_value — F-178).
  Future<int> totalStockValue() async {
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(total_value_minor), 0) AS v '
      'FROM stock_balances',
    ).get();
    return rows.first.data['v'] as int;
  }

  setUp(() async {
    db = DiqqahDatabase.inMemory();
    year = int.parse((await db
            .customSelect('SELECT name FROM fiscal_years')
            .get())
        .single
        .data['name'] as String)
        .toString();
    date = '$year-03-15';
    unitId = await db.insertUnit(name: 'قطعة');
    oilId = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);
    riceId = await db.insertItem(
        sku: 'R-200',
        name: 'أرز فاخر',
        category: 'أرز',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 30000,
        salePriceMinor: 50000,
        priceCurrencyId: 1);
    serviceId = await db.insertItem(
        sku: 'S-300',
        name: 'صيانة دورية',
        category: 'خدمات',
        kind: 'service',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 15000,
        priceCurrencyId: 1);
    supplierId = await db.insertParty(
        number: '0001',
        name: 'مورد الشرق',
        kind: 'supplier',
        defaultCurrencyId: 1);
    mainWhId = (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    branchWhId = await db.warehouseCreate(name: 'مستودع الفرع');
    // بذرة مخزون بالمستودع الرئيسي: 10 زيت × 25000 = 250000
    // و20 أرز × 30000 = 600000 (منع السالب F-042 يطلب أرضية).
    final purchase = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: mainWhId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 25000),
        InvoiceLineDraft(
            itemId: riceId, unitId: unitId, qtyBase: 20, unitPriceMinor: 30000),
      ],
    ));
    await db.postInvoice(purchase);
  });

  tearDown(() => db.close);

  group('إدارة المستودعات — الإضافة والتسمية والتعطيل', () {
    test('إنشاء مستودع جديد يظهر نشطاً وتكرار الاسم يرفض', () async {
      final warehouses = await db.warehousesOf();
      expect(warehouses.map((w) => w.name),
          containsAll(['المستودع الرئيسي', 'مستودع الفرع']));
      expect(
        () => db.warehouseCreate(name: 'مستودع الفرع'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('مستخدم سلفاً'))),
      );
      // الفراغ المحيط يُطهَّر والاسم الفارغ يرفض
      expect(() => db.warehouseCreate(name: '   '),
          throwsA(isA<StateError>()));
    });

    test('إعادة التسمية: الغير مكرر يقبل والمكرر يرفض والذاتي يمر', () async {
      await db.warehouseRename(
          id: branchWhId, name: 'مستودع المعرض');
      final after = await db.warehousesOf();
      expect(after.map((w) => w.name), contains('مستودع المعرض'));
      // التسمية الذاتية تمر (الاستثناء الذاتي نمط D-153)
      await db.warehouseRename(id: branchWhId, name: 'مستودع المعرض');
      // الاسم المكرر يرفض
      expect(
        () => db.warehouseRename(id: branchWhId, name: 'المستودع الرئيسي'),
        throwsA(isA<StateError>()),
      );
    });

    test('آخر مستودع نشط لا يُعطَّل والرصيد القائم يحجب التعطيل', () async {
      // المستودعان نشطان — تعطيل الرئيسي (برصيد قائم) يرفض بالرصيد أولاً
      expect(
        () => db.warehouseSetActive(id: mainWhId, active: false),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('برصيد قائم'))),
      );
      // تعطيل الفرع (بلا رصيد) يمر ثم يبقى الرئيسي وحده آخر نشط فيُحجب
      await db.warehouseSetActive(id: branchWhId, active: false);
      expect(
        () => db.warehouseSetActive(id: mainWhId, active: false),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('آخر مستودع نشط'))),
      );
      // إعادة التفعيل تمر
      await db.warehouseSetActive(id: branchWhId, active: true);
      final active = await db.warehousesOf();
      expect(active.where((w) => w.isActive).length, 2);
    });
  });

  group('stockTransferPost — التحويل بين مستودعين (س-18)', () {
    test('تحويل جزئي: أرصدة الطرفين تتحدث فوراً والقيمة تنتقل كما هي',
        () async {
      final (mainQty0, mainValue0) = await balanceOf(oilId, mainWhId);
      expect(mainQty0, 10);
      expect(mainValue0, 250000);
      expect(await balanceOf(oilId, branchWhId), (0, 0));

      final transferId = await db.stockTransferPost(StockTransferDraft(
        dateText: date,
        fromWarehouseId: mainWhId,
        toWarehouseId: branchWhId,
        lines: [TransferLineDraft(itemId: oilId, qtyBase: 3)],
      ));

      final (mainQty, mainValue) = await balanceOf(oilId, mainWhId);
      final (branchQty, branchValue) = await balanceOf(oilId, branchWhId);
      expect(mainQty, 7);
      expect(mainValue, 175000, reason: '3 × 25000 تخرج بقيمتها الكاملة');
      expect(branchQty, 3);
      expect(branchValue, 75000,
          reason: 'القيمة تنتقل كما هي — 3 × 25000 بلا فروق');
      // ثابت 113: مجموع القيمة ثابت قبل وبعد (F-178)
      expect(await totalStockValue(), 850000);
      // الحركتان المتقابلتان بلا قيد: مرجعيتهما stock_transfer
      final moves = await db.customSelect(
        'SELECT qty_base, from_warehouse_id, to_warehouse_id, '
        'value_base_minor FROM stock_moves '
        "WHERE ref_doc_type = 'stock_transfer' AND ref_doc_id = ? "
        'ORDER BY qty_base',
        variables: [Variable.withInt(transferId)],
      ).get();
      expect(moves.length, 2);
      expect(moves[0].data['qty_base'], -3);
      expect(moves[0].data['from_warehouse_id'], mainWhId);
      expect(moves[1].data['qty_base'], 3);
      expect(moves[1].data['to_warehouse_id'], branchWhId);
      // رقم التسلسل السنوي بالصيغة الموحدة D-169: سنة رقمين + عدّاد
      final head = await db.customSelect(
        'SELECT number, state FROM stock_transfers WHERE id = ?',
        variables: [Variable.withInt(transferId)],
      ).getSingle();
      expect(head.data['number'],
          startsWith('${int.parse(year) % 100}'));
      expect(head.data['state'], 'posted');
      // حدث posted بلقطة كاملة (07 §2.3)
      final events = await db.customSelect(
        "SELECT COUNT(*) AS c FROM events "
        "WHERE entity_type = 'stock_transfer' AND action = 'posted' "
        'AND entity_id = ?',
        variables: [Variable.withInt(transferId)],
      ).getSingle();
      expect(events.data['c'], 1);
      // قيد الدفتر لا قيد له (بلا قيد محاسبي — 05 §6)
      final ledgerRefs = await db.customSelect(
        "SELECT COUNT(*) AS c FROM moves WHERE ref_doc_type = "
        "'stock_transfer'",
      ).getSingle();
      expect(ledgerRefs.data['c'], 0);
    });

    test('تحويل الكلية يمتص القيمة كلها فلا غبار تقريب (D-067)', () async {
      await db.stockTransferPost(StockTransferDraft(
        dateText: date,
        fromWarehouseId: mainWhId,
        toWarehouseId: branchWhId,
        lines: [TransferLineDraft(itemId: riceId, qtyBase: 20)],
      ));
      // المصدر صفَر بكمية وقيمة — لا غبار معلق
      expect(await balanceOf(riceId, mainWhId), (0, 0));
      expect(await balanceOf(riceId, branchWhId), (20, 600000));
      expect(await totalStockValue(), 850000);
    });

    test('كمية أكبر من رصيد المصدر ترفض والرصيد لا يتغير', () async {
      final before = await balanceOf(oilId, mainWhId);
      try {
        await db.stockTransferPost(StockTransferDraft(
          dateText: date,
          fromWarehouseId: mainWhId,
          toWarehouseId: branchWhId,
          lines: [TransferLineDraft(itemId: oilId, qtyBase: 11)],
        ));
        fail('كان يجب أن يرفض');
      } on StockTransferValidationException catch (e) {
        final msg = firstStockTransferError(e.errors);
        expect(msg, contains('منع السالب'));
      }
      expect(await balanceOf(oilId, mainWhId), before);
      // والعدّاد لم يصدر رقماً فلا فجوة: التحويل التالي يأخذ الرقم 1
      final id2 = await db.stockTransferPost(StockTransferDraft(
        dateText: date,
        fromWarehouseId: mainWhId,
        toWarehouseId: branchWhId,
        lines: [TransferLineDraft(itemId: oilId, qtyBase: 1)],
      ));
      final rows = await db.customSelect(
        'SELECT number FROM stock_transfers WHERE id = ?',
        variables: [Variable.withInt(id2)],
      ).getSingle();
      expect(rows.data['number'], endsWith('1'),
          reason: 'رقم مُرفوض لا يُحرق — التراجع يشمل العدّاد (07 §1.9)');
    });

    test('نفس المستودع ومعطل الطرفين والخدمة والصفر ترفض برسائل س-18',
        () async {
      // نفس المستودع (بنيوي — المجال)
      expect(
        () => db.stockTransferPost(StockTransferDraft(
          dateText: date,
          fromWarehouseId: mainWhId,
          toWarehouseId: mainWhId,
          lines: [TransferLineDraft(itemId: oilId, qtyBase: 1)],
        )),
        throwsA(isA<StockTransferValidationException>()
            .having((e) => firstStockTransferError(e.errors), 'msg',
                contains('نفسه'))),
      );
      // مستودع معطل كطرف
      await db.warehouseCreate(name: 'مستودع مغلق');
      final closedId = (await db.customSelect(
        "SELECT id FROM warehouses WHERE name = 'مستودع مغلق'",
      ).getSingle()).data['id'] as int;
      await db.warehouseSetActive(id: closedId, active: false);
      try {
        await db.stockTransferPost(StockTransferDraft(
          dateText: date,
          fromWarehouseId: mainWhId,
          toWarehouseId: closedId,
          lines: [TransferLineDraft(itemId: oilId, qtyBase: 1)],
        ));
        fail('كان يجب أن يرفض');
      } on StockTransferValidationException catch (e) {
        expect(firstStockTransferError(e.errors), contains('معطل'));
      }
      // صنف خدمة بلا مخزون (س-08)
      try {
        await db.stockTransferPost(StockTransferDraft(
          dateText: date,
          fromWarehouseId: mainWhId,
          toWarehouseId: branchWhId,
          lines: [TransferLineDraft(itemId: serviceId, qtyBase: 1)],
        ));
        fail('كان يجب أن يرفض');
      } on StockTransferValidationException catch (e) {
        expect(firstStockTransferError(e.errors), contains('بضاعة حصراً'));
      }
      // كمية صفر (بنيوي — بالوحدة الأساسية موجبة)
      expect(
        () => db.stockTransferPost(StockTransferDraft(
          dateText: date,
          fromWarehouseId: mainWhId,
          toWarehouseId: branchWhId,
          lines: [TransferLineDraft(itemId: oilId, qtyBase: 0)],
        )),
        throwsA(isA<StockTransferValidationException>()),
      );
    });

    test('التحويلان يتسلسلان رقماً والسجل يقرأهما بأسماء المستودعات',
        () async {
      await db.stockTransferPost(StockTransferDraft(
        dateText: date,
        fromWarehouseId: mainWhId,
        toWarehouseId: branchWhId,
        lines: [TransferLineDraft(itemId: oilId, qtyBase: 1)],
      ));
      await db.stockTransferPost(StockTransferDraft(
        dateText: date,
        fromWarehouseId: mainWhId,
        toWarehouseId: branchWhId,
        lines: [TransferLineDraft(itemId: riceId, qtyBase: 2)],
      ));
      final list = await db.stockTransfersOf();
      expect(list.length, 2);
      // الأحدث أولاً (ترتيب الهبوط)
      expect(list.first.number, endsWith('2'));
      expect(list.first.fromName, 'المستودع الرئيسي');
      expect(list.first.toName, 'مستودع الفرع');
      expect(list.first.lineCount, 1);
      expect(list.first.totalQtyBase, 2);
      final lines = await db.stockTransferLinesOf(list.first.id);
      expect(lines.single.itemName, 'أرز فاخر');
      expect(lines.single.qtyBase, 2);
      expect(lines.single.valueBaseMinor, 60000);
    });
  });

  group('س113 — الإدخال بالتعبئة بالتحويل: اللقطة الثلاثية والحرس', () {
    late int gid;
    late int levelId;

    setUp(() async {
      gid = await db.insertUnitGroup(name: 'تعبئة التحويل',
          levels: [(name: 'علبة', factor: 12)]);
      levelId = (await db.levelsOfGroup(gid)).first.id;
      await db.customStatement(
          'UPDATE items SET unit_group_id = ? WHERE id = ?', [gid, oilId]);
      // بذرة تكفي التعبئة: 40 زيت إضافية للرئيسي.
      final purchase = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: date,
        partyId: supplierId,
        warehouseId: mainWhId,
        lines: [InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 40, unitPriceMinor: 25000)],
      ));
      await db.postInvoice(purchase);
    });

    test('تحويل 3 علب = 36 أساسية بحركة اللقطة محفوظة والقيمة بالأرقام'
        ' القائمة', () async {
      final id = await db.stockTransferPost(StockTransferDraft(
        dateText: date,
        fromWarehouseId: mainWhId,
        toWarehouseId: branchWhId,
        lines: [TransferLineDraft(
          itemId: oilId,
          qtyBase: 36,
          unitLevelId: levelId,
          qtyDoc: 3,
          factorAtEntry: 12,
        )],
      ));
      final line = await db.customSelect(
        'SELECT qty_base, unit_level_id, qty_doc, factor_at_entry '
        'FROM stock_transfer_lines WHERE transfer_id = ?',
        variables: [Variable.withInt(id)],
      ).getSingle();
      expect(line.data['qty_base'], 36);
      expect(line.data['unit_level_id'], levelId);
      expect(line.data['qty_doc'], 3);
      expect(line.data['factor_at_entry'], 12);
      final (mainQty, _) = await balanceOf(oilId, mainWhId);
      final (branchQty, _) = await balanceOf(oilId, branchWhId);
      expect(mainQty, 14);
      expect(branchQty, 36);
    });

    test('مستوى لا ينتمي لمجموعة الصنف يرفض بلا كتابة (الرفض قبل '
        'الترحيل حصراً)', () async {
      final otherGid = await db.insertUnitGroup(name: 'مجموعة أخرى',
          levels: [(name: 'صندوق', factor: 24)]);
      final otherLevel = (await db.levelsOfGroup(otherGid)).first.id;
      await expectLater(
        () => db.stockTransferPost(StockTransferDraft(
          dateText: date,
          fromWarehouseId: mainWhId,
          toWarehouseId: branchWhId,
          lines: [TransferLineDraft(
            itemId: oilId,
            qtyBase: 36,
            unitLevelId: otherLevel,
            qtyDoc: 3,
            factorAtEntry: 12,
          )],
        )),
        throwsA(isA<StockTransferValidationException>()),
      );
      // والعامل المخالف عن الكمية المدخلة يرفض كذلك.
      await expectLater(
        () => db.stockTransferPost(StockTransferDraft(
          dateText: date,
          fromWarehouseId: mainWhId,
          toWarehouseId: branchWhId,
          lines: [TransferLineDraft(
            itemId: oilId,
            qtyBase: 36,
            unitLevelId: levelId,
            qtyDoc: 4,
            factorAtEntry: 12,
          )],
        )),
        throwsA(isA<StockTransferValidationException>()),
      );
    });
  });
}
