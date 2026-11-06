import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة 34 — تعدد العملات الفعلي (F-120/F-121/F-124،
/// D-194) على ترحيلة v23.
///
/// الحدود الموثقة: إضافة العملات حصراً بلا تعديل بعد الحفظ وتفردها
/// مطلق بالحي والمعطل، والتعطيل بحرستيه (الأساسية والمرجعية)،
/// والسعر بيوم واحد لا يقبل ثانية والسجل المحفوظ مجمد لا تعديل
/// ولا حذف (نمط F-140)، ولا سعر مستقبلي (D-194)، ومراكز العملات
/// بالقيم المخزنة حصراً — والبنية القائمة من م1 (لقطات المستندات
/// وفرق الصرف) لا تُمس.
void main() {
  late DiqqahDatabase db;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() => db.close);

  group('ترحيلة v23 — جدول أسعار الصرف', () {
    test('على قاعدة جديدة: جدول exchange_rate مبني بتفرّده وتجميده '
        '(نمط F-140)', () async {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'exchange_rate'",
      ).get();
      expect(tables, hasLength(1), reason: 'جدول الأسعار مبني');

      final eurId = await db.currenciesAdd(
          code: 'EUR', name: 'يورو', minorUnits: 2);
      await db.exchangeRateRecord(
          currencyId: eurId, date: '2026-11-05', rateToBase: 16000000000);

      // اليوم المسجل لا يقبل ثانية — والسجل المحفوظ لا يُعدل ولا
      // يُحذف إطلاقاً (F-121).
      await expectLater(
        () => db.exchangeRateRecord(
            currencyId: eurId, date: '2026-11-05', rateToBase: 16500000000),
        throwsA(anything),
        reason: 'سعر اليوم المحفوظ لا يقبل ثانية',
      );
      await expectLater(
        () => db.customStatement('UPDATE exchange_rate SET rate_to_base = 1'),
        throwsA(anything),
        reason: 'السجل المحفوظ لا يُعدل (تجميد نمط F-140)',
      );
      await expectLater(
        () => db.customStatement('DELETE FROM exchange_rate'),
        throwsA(anything),
        reason: 'السجل المحفوظ لا يُحذف',
      );
    });

    test('ترحيلة v23 آمنة التكرار: قاعدة ملف تُفتح وتُغلق وتُعاد '
        'فالبيانات باقية والمخطط 23', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('diqqah_v34_mig_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dbPath = '${tempDir.path}/c34.db';

      final first = DiqqahDatabase(filePath: dbPath);
      await first.currenciesAdd(
          code: 'EUR', name: 'يورو', minorUnits: 2);
      await first.exchangeRateRecord(
          currencyId: 2, date: '2026-11-05', rateToBase: 16000000000);
      await first.close;

      final second = DiqqahDatabase(filePath: dbPath);
      addTearDown(second.close);
      await second.customSelect('SELECT id FROM currencies').get();
      expect(second.schemaVersion, 23);
      final rates = await second.exchangeRatesOf(2);
      expect(rates, hasLength(1), reason: 'السجل باقٍ من الجولة الأولى');
      // وإعادة ثانية على القائمة نفسها لا تكسر شيئاً (آمنة التكرار).
      await second.exchangeRateRecord(
          currencyId: 2, date: '2026-11-06', rateToBase: 16100000000);
      final rates2 = await second.exchangeRatesOf(2);
      expect(rates2, hasLength(2));
    });
  });

  group('إدارة العملات (F-120)', () {
    test('إضافة عملة سليمة: تُقرأ بأكودها مطبعة وبخاناتها', () async {
      final id = await db.currenciesAdd(
          code: ' eur ', name: ' يورو ', minorUnits: 2);
      expect(id, greaterThan(2));
      final currencies = await db.currenciesOf();
      final eur = currencies.where((c) => c.code == 'EUR').toList();
      expect(eur, hasLength(1));
      expect(eur.first.name, 'يورو');
      expect(eur.first.minorUnits, 2);
      expect(eur.first.isBase, isFalse);
    });

    test('تفرد الكود مطلق: المطابق حرفياً والملون والتقلييم رفض',
        () async {
      await db.currenciesAdd(
          code: 'EUR', name: 'يورو', minorUnits: 2);
      for (final dup in ['EUR', ' eur ', 'Eur']) {
        await expectLater(
          () => db.currenciesAdd(code: dup, name: 'ثانية', minorUnits: 2),
          throwsA(anything),
          reason: 'الكود «$dup» محفوظ سلفاً',
        );
      }
    });

    test('المدقق البنيوي في المجال يرفض قبل الكتابة', () async {
      for (final bad in [
        ('EU', 'قصير'),
        ('EURO', 'طويل'),
        ('E1R', 'بأرقام'),
      ]) {
        await expectLater(
          () => db.currenciesAdd(
              code: bad.$1, name: 'س', minorUnits: 2),
          throwsA(anything),
          reason: 'الكود «${bad.$1}» ${bad.$2} مرفوض',
        );
      }
      await expectLater(
        () => db.currenciesAdd(code: 'EUR', name: '  ', minorUnits: 2),
        throwsA(anything),
        reason: 'الاسم إلزامي',
      );
      await expectLater(
        () => db.currenciesAdd(code: 'EUR', name: 'س', minorUnits: 9),
        throwsA(anything),
        reason: 'خانات الوحدة الصغرى 0..8',
      );
    });

    test('تعطيل عملة غير مستخدمة يخفيها من القائمة — بلا حذف', () async {
      final id = await db.currenciesAdd(
          code: 'EUR', name: 'يورو', minorUnits: 2);
      await db.currenciesDeactivate(id);
      final live = await db.currenciesOf();
      expect(live.where((c) => c.code == 'EUR'), isEmpty,
          reason: 'المعطلة تختفي من القائمة الحية');
      final raw = await db.customSelect(
        'SELECT is_deleted FROM currencies WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).getSingle();
      expect(raw.data['is_deleted'], 1,
          reason: 'التعطيل علامة لا حذف أبداً (نمط 03 §6-3)');
    });

    test('حرسا التعطيل: الأساسية ممنوعة والمرجعية مرفوضة', () async {
      // الأساسية الأولى من البذر (SYP).
      final currencies = await db.currenciesOf();
      final base = currencies.firstWhere((c) => c.isBase);
      await expectLater(
        () => db.currenciesDeactivate(base.id),
        throwsA(anything),
        reason: 'عملة الأساسية مقياس الكل — لا تُعطَّل',
      );
      // عملة عليها مرجع (صندوق بعملتها) ترفض التعطيل.
      final eurId = await db.currenciesAdd(
          code: 'EUR', name: 'يورو', minorUnits: 2);
      await db.createCashBox(name: 'صندوق اليورو', currencyId: eurId);
      await expectLater(
        () => db.currenciesDeactivate(eurId),
        throwsA(anything),
        reason: 'العملة المرجعية لا تُعطَّل (اللقطات تحيل إليها)',
      );
    });
  });

  group('أسعار الصرف التاريخية (F-121)', () {
    late int eurId;

    setUp(() async {
      eurId = await db.currenciesAdd(
          code: 'EUR', name: 'يورو', minorUnits: 2);
    });

    test('تسجيل سعر سليم: يقرأ بالأحدث أولاً وآخر سعر يملأ الافتراض',
        () async {
      await db.exchangeRateRecord(
          currencyId: eurId, date: '2026-11-03', rateToBase: 15800000000);
      await db.exchangeRateRecord(
          currencyId: eurId, date: '2026-11-06', rateToBase: 16200000000);
      final rates = await db.exchangeRatesOf(eurId);
      expect(rates, hasLength(2));
      expect(rates.first.date, '2026-11-06',
          reason: 'الأحدث أولاً');
      expect(rates.first.rateToBase, 16200000000);
      final latest = await db.latestExchangeRate(eurId);
      expect(latest!.date, '2026-11-06');
      expect(latest.rateToBase, 16200000000);
    });

    test('الحدود: يوم محفوظ وسعر صفري وتاريخ مستقبل وتاريخ فاسد '
        'وأساسية — كلها ترفض برسائلها', () async {
      await db.exchangeRateRecord(
          currencyId: eurId, date: '2026-11-05', rateToBase: 16000000000);
      await expectLater(
        () => db.exchangeRateRecord(
            currencyId: eurId, date: '2026-11-05', rateToBase: 16100000000),
        throwsA(anything),
        reason: 'سعر اليوم المحفوظ لا يقبل ثانية',
      );
      await expectLater(
        () => db.exchangeRateRecord(
            currencyId: eurId, date: '2026-11-06', rateToBase: 0),
        throwsA(anything),
        reason: 'الصفر بلا معنى صرفي',
      );
      await expectLater(
        () => db.exchangeRateRecord(
            currencyId: eurId, date: '2027-01-01', rateToBase: 16000000000),
        throwsA(anything),
        reason: 'لا سعر مستقبلي (D-194: الحد الصادق)',
      );
      await expectLater(
        () => db.exchangeRateRecord(
            currencyId: eurId, date: '2026/11/06', rateToBase: 16000000000),
        throwsA(anything),
        reason: 'الصيغة الموحدة حصراً (D-077)',
      );
      await expectLater(
        () => db.exchangeRateRecord(
            currencyId: 1, date: '2026-11-06', rateToBase: 1000000),
        throwsA(anything),
        reason: 'عملة الأساسية لا تقاس',
      );
    });
  });

  group('مراكز العملات (F-124)', () {
    test('الأساسية والعملتان الزرعتان تظهران وصندوق دولاري وفاتورة '
        'مفتوحة تجمعان بالمخزن لا بحساب جديد', () async {
      final unitId = await db.insertUnit(name: 'قطعة');
      final itemId = await db.insertItem(
          sku: 'C-100',
          name: 'بضاعة العملات',
          kind: 'good',
          baseUnitId: unitId,
          purchasePriceMinor: 1000,
          salePriceMinor: 2000,
          priceCurrencyId: 1);
      final warehouseId = (await db.customSelect(
        'SELECT id FROM warehouses ORDER BY id LIMIT 1',
      ).getSingle()).data['id'] as int;
      final customerId = await db.insertParty(
          number: '0001', name: 'عميل العملات', kind: 'customer',
          defaultCurrencyId: 1);
      final supplierId = await db.insertParty(
          number: '0002', name: 'مورد العملات', kind: 'supplier',
          defaultCurrencyId: 1);
      await db.createCashBox(name: 'صندوق الدولار', currencyId: 2);
      await db.exchangeRateRecord(
          currencyId: 2, date: '2026-11-05', rateToBase: 15000000000);

      // فاتورة شراء تمهيدية بالأساسية فالمخزون يسمح بالبيع (F-042).
      final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.purchase,
        dateText: '2026-11-04',
        partyId: supplierId,
        warehouseId: warehouseId,
        lines: [
          InvoiceLineDraft(
              itemId: itemId, unitId: unitId, qtyBase: 3,
              unitPriceMinor: 1000),
        ],
      ));
      await db.postInvoice(purchaseId);

      // فاتورة بيع دولارية مرحّلة مفتوحة: 1 قطعة × 10,000 وحدة صغرى
      // (= 100 دولار) بلقطة 15,000 ليرة للدولار — المكافئ المخزن
      // 150,000,000 وحدة صغرى أساسية.
      const usdFx = 15000 * fxRateScale;
      final invoiceId = await db.createInvoiceDraft(InvoiceDraft(
        kind: InvoiceKind.sale,
        dateText: '2026-11-05',
        partyId: customerId,
        warehouseId: warehouseId,
        currencyId: 2,
        fxRate: usdFx,
        lines: [
          InvoiceLineDraft(
              itemId: itemId, unitId: unitId, qtyBase: 1,
              unitPriceMinor: 10000),
        ],
      ));
      await db.postInvoice(invoiceId);

      final positions = await db.currencyPositions();
      expect(positions, hasLength(2),
          reason: 'الأساسية والدولار — لا غير من البذر');
      final syp = positions.first;
      expect(syp.code, 'SYP');
      expect(syp.isBase, isTrue);
      final usd = positions.last;
      expect(usd.code, 'USD');
      expect(usd.isBase, isFalse);
      expect(usd.boxesCount, 1,
          reason: 'صندوق الدولار الجديد بعملته');
      expect(usd.openInvoicesCount, 1);
      expect(usd.openRemainderDocMinor, 10000,
          reason: 'المتبقي بعملة الفاتورة من المخزن (100.00 دولار)');
      expect(usd.openRemainderBaseMinor, 150000000,
          reason: 'المكافئ الأساسي بلقطة الفاتورة ذاتها (1.5 مليون ليرة)');
      expect(usd.latestRateToBase, 15000000000);
      expect(usd.latestRateDate, '2026-11-05');

      // والحساب النقي يجمع القيم المخزنة حصراً.
      final rows = currencyPositionsCompute(positions);
      expect(rows.last.totalBaseMinor, 150000000);
    });

    test('العملة المعطلة تختفي من المراكز والمستخدمة تظل', () async {
      final eurId = await db.currenciesAdd(
          code: 'EUR', name: 'يورو', minorUnits: 2);
      await db.currenciesDeactivate(eurId);
      final positions = await db.currencyPositions();
      expect(positions.where((p) => p.code == 'EUR'), isEmpty,
          reason: 'المعطلة خارج المراكز');
      expect(positions.map((p) => p.code), containsAll(['SYP', 'USD']));
    });
  });
}
