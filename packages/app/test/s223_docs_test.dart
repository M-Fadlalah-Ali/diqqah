import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/vouchers_screen.dart';
import 'package:diqqah_app/orders_screen.dart';
import 'package:diqqah_app/ledger_screen.dart';
import 'package:diqqah_app/stock_docs_screen.dart';
import 'package:diqqah_app/list_display.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// س223 — المتبقي من د5 (بأمر المالحرفي الحرفي «قم بتنفيذ المتبقي من
/// د5 بالكامل ولا تنس الدفع والتوثيق والبناء 0.276»):
///
/// حد العرض المتدرج الموحد (نمط list_display.dart بعقد س221) على بقية
/// قوائم المستندات الموثقة بالخريطة: تبويبات السندات الثلاثة (عبر
/// المساعد الموحد _tabList) وأرشيف الطلبات ومعاينات مستندات المخزون
/// (الإذنان — وبدل السقف الصلب take(10) الذي كان يحجب الأقدم نهائياً)
/// وأسطر كشف الحساب — والقراءة كاملة لا مساس بها والحد بناء واجهة
/// حصراً وزر التوسيع بعدّاد الباقي فالوجود كله متاح بالتوسع المتكرر،
/// والطباعة على العرض المطبَّق كاملاً بعقد F-166/D-016 — الحد للشاشة
/// لا للورقة.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  Future<String> cycleDate(DiqqahDatabase db) async {
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    return '${yearRows.single.data['name'] as String}-03-15';
  }

  Future<int> firstBoxId(DiqqahDatabase db) async {
    return (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
  }

  Future<int> firstWarehouseId(DiqqahDatabase db) async {
    return (await db.customSelect(
      'SELECT id FROM warehouses ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
  }

  Future<int> capitalId(DiqqahDatabase db) async {
    return (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '311'",
    ).getSingle()).data['id'] as int;
  }

  /// شحنة سندات معلّقة فوق الحد — القائمة الطرفية تبقى معلّقة (لا
  /// postVoucher) فلا قيوداً ولا مساساً بالأرقام المعروفة للبذرة.
  Future<void> seedHeldReceipts(
      DiqqahDatabase db, String date, int boxId, int capital, int count) async {
    for (var i = 0; i < count; i++) {
      await db.createVoucherDraft(VoucherDraft(
        kind: VoucherKind.receipt,
        dateText: date,
        directAccountId: capital,
        cashBoxId: boxId,
        amountDocMinor: 1000,
      ));
    }
  }

  group('س223: حد العرض المتدرج على تبويبات السندات (المساعد الموحد)', () {
    testWidgets('شحنة حية فوق الحد تُظهر زر التوسيع بالعدّاد الباقي '
        'والتوسيع يعرض البقية — والقراءة كاملة (حد واجهة لا بيانات)',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final date = await cycleDate(db);
      final boxId = await firstBoxId(db);
      final capital = await capitalId(db);
      await seedHeldReceipts(db, date, boxId, capital, 70);

      // منفذ عملاق كي تُبنى الصفوف وزر التوسيع — الشريحة البطيئة تبني
      // المرئي حصراً (درس الجولة الحاكمة الموثق س221).
      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // العدّاد من الاستعلام ذاته لا من افتراض — البذرة تحمل سنداتها
      // المرحّلة فالشحنة فوق الحد بالباقي الفعلي.
      final all = await db.vouchersListReport();
      expect(all.length, greaterThan(kListDisplayPageSize),
          reason: '70 معلّقة فوق سندات البذرة — فالشحنة فوق الحد فعلاً');
      final remaining = all.length - kListDisplayPageSize;

      expect(find.text('عرض المزيد — الباقي $remaining'), findsOneWidget);
      await tester.tap(find.text('عرض المزيد — الباقي $remaining'));
      await tester.pumpAndSettle();
      expect(find.text('عرض المزيد — الباقي $remaining'), findsNothing,
          reason: 'الوجود كله تحت الشحنات بعد التوسيع');
    });

    testWidgets('إعادة التصفية تصفر الحد المتدرج — البدء من أعلى '
        'القائمة مع كل استعلام جديد (عقد س221 بس223)',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final date = await cycleDate(db);
      final boxId = await firstBoxId(db);
      final capital = await capitalId(db);
      await seedHeldReceipts(db, date, boxId, capital, 70);

      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final all = await db.vouchersListReport();
      final remaining = all.length - kListDisplayPageSize;

      // توسيع أول: الزر يزول فالوجود كله مبنيّ.
      await tester.tap(find.text('عرض المزيد — الباقي $remaining'));
      await tester.pumpAndSettle();

      // تصفية «المرحّلة»: سندات البذرة المرحّلة حصراً — تحت الحد فلا
      // زر، وإعادة التصفية تعيد الحد صفراً من أعلى القائمة.
      await tester.tap(find.text('كل الحالات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('المرحّلة'));
      await tester.pumpAndSettle();
      expect(find.textContaining('عرض المزيد'), findsNothing,
          reason: 'المرحّلة من البذرة تحت الحد — لا زر توسيع');

      // العودة لـ«كل الحالات»: الحد مصفَّر فالزر بالعدّاد ذاته عائداً
      // — دليل إعادة الضبط بالاستعلام الجديد لا استمرار التوسيع القديم.
      await tester.tap(find.text('المرحّلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('كل الحالات'));
      await tester.pumpAndSettle();
      expect(find.text('عرض المزيد — الباقي $remaining'), findsOneWidget,
          reason: 'الحد صفر بعد إعادة التصفية — لا استمرار للتوسيع القديم');
    });
  });

  group('س223: حد العرض المتدرج على أرشيف الطلبات', () {
    testWidgets('شحنة أوامر فوق الحد تُظهر الزر بالعدّاد والتوسيع يعرض '
        'البقية — والأوامر مسودات بلا قيد (الأمر لا يُقيد)',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final date = await cycleDate(db);
      final customerId = (await db.customSelect(
        "SELECT id FROM parties WHERE number = '0001'",
      ).getSingle()).data['id'] as int;
      final unitId = (await db.customSelect(
        'SELECT id FROM units ORDER BY id LIMIT 1',
      ).getSingle()).data['id'] as int;
      final oilId = (await db.customSelect(
        "SELECT id FROM items WHERE sku = 'Z-100'",
      ).getSingle()).data['id'] as int;
      // 70 مسودة بيع فوق حد الـ60 — مسودات حرة بلا ترحيل (الأمر لا
      // يُقيد) لكن المدقق بيطرفاً وسطراً (OrderPartyRequired
      // وOrderLinesRequired بعقد س121).
      for (var i = 0; i < 70; i++) {
        await db.createOrderDraft(OrderDraft(
          direction: OrderDirection.sale,
          orderDate: date,
          partyId: customerId,
          lines: [
            OrderLineDraft(
                itemId: oilId, unitId: unitId, qty: 1, qtyBase: 1,
                unitPriceMinor: 15000),
          ],
        ));
      }

      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: OrdersScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final all = await db.listOrders();
      expect(all.length, greaterThan(kListDisplayPageSize));
      final remaining = all.length - kListDisplayPageSize;

      expect(find.text('عرض المزيد — الباقي $remaining'), findsOneWidget);
      await tester.tap(find.text('عرض المزيد — الباقي $remaining'));
      await tester.pumpAndSettle();
      expect(find.text('عرض المزيد — الباقي $remaining'), findsNothing,
          reason: 'الوجود كله متاح بالتوسع');
    });
  });

  group('س223: حد العرض المتدرج على أسطر كشف الحساب', () {
    testWidgets('كشف بحساب شحنت قيودُه فوق الحد يبني أول شحنة وزر '
        'التوسيع — والتوسيع يعرض الأسطر كلها', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final date = await cycleDate(db);
      final boxId = await firstBoxId(db);
      final capital = await capitalId(db);
      // 70 سند قبض مرحّل بغير طرف على 311 — كل ترحيل سطراً دائناً
      // بحساب 311 فكشفه فوق الحد فعلاً.
      for (var i = 0; i < 70; i++) {
        final id = await db.createVoucherDraft(VoucherDraft(
          kind: VoucherKind.receipt,
          dateText: date,
          directAccountId: capital,
          cashBoxId: boxId,
          amountDocMinor: 1000,
        ));
        await db.postVoucher(id);
      }

      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: LedgerScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.textContaining('311 — '));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final report = await db.accountStatementReport(capital);
      expect(report.entries.length, greaterThan(kListDisplayPageSize));
      final remaining = report.entries.length - kListDisplayPageSize;

      expect(find.text('عرض المزيد — الباقي $remaining'), findsOneWidget,
          reason: 'أسطر الكشف فوق الحد — الزر بعدّاد الباقي');
      await tester.tap(find.text('عرض المزيد — الباقي $remaining'));
      await tester.pumpAndSettle();
      expect(find.text('عرض المزيد — الباقي $remaining'), findsNothing,
          reason: 'أسطر الكشف كلها مبنيّة بعد التوسيع');
    });
  });

  group('س223: معاينة إذون المخزون — السقف الصلب take(10) انقضى', () {
    testWidgets('الشحنة فوق الحد تُظهر زر التوسيع والأقدم يُبنى بالتوسع '
        '— لا حجب نهائياً كما كان السقف الصلب', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final date = await cycleDate(db);
      final warehouseId = await firstWarehouseId(db);
      final oilId = (await db.customSelect(
        "SELECT id FROM items WHERE sku = 'Z-100'",
      ).getSingle()).data['id'] as int;
      final accounts = await db.allLedgerAccounts();
      final activeLeaf = accounts
          .where((a) => a.isActive && a.isLeaf)
          .toList();
      var counterId = 0;
      for (final a in activeLeaf) {
        if (a.code == '43') counterId = a.id;
      }
      if (counterId == 0) counterId = activeLeaf.first.id;
      // 70 إذن إدخال مرحّل (الأحدث أولاً بالسجل) — القراءة كاملة
      // والسقف الصلب القديم كان يعرض آخر 10 حصراً.
      for (var i = 0; i < 70; i++) {
        await db.stockReceiptPost(StockReceiptDraft(
          dateText: date,
          warehouseId: warehouseId,
          reason: 'هدية مورد — شحنة س223 رقم ${i + 1}',
          counterAccountId: counterId,
          lines: [
            StockDocLineDraft(itemId: oilId, qtyBase: 1),
          ],
        ));
      }

      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: StockDocScreen(db: db, direction: StockDocDirection.receipt),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      final docs = await db.stockReceiptsOf();
      expect(docs.length, greaterThan(kListDisplayPageSize));
      final remaining = docs.length - kListDisplayPageSize;

      expect(find.text('عرض المزيد — الباقي $remaining'), findsOneWidget,
          reason: 'المعاينة فوق الحد — الزر بدل السقف الصلب القديم');
      await tester.tap(find.text('عرض المزيد — الباقي $remaining'));
      await tester.pumpAndSettle();
      expect(find.text('عرض المزيد — الباقي $remaining'), findsNothing,
          reason: 'الأقدم متاح بالتوسع — لا حجب نهائياً');
    });
  });

  group('س223: الحارس — تحت الحد لا زر توسيع', () {
    testWidgets('قائمة البذرة وحدها (تحت الحد) بلا زر — النمط لا يضيف '
        'ضجيجاً على القوائم الصغيرة', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ListTile), findsWidgets);
      expect(find.textContaining('عرض المزيد'), findsNothing,
          reason: 'سندات البذرة تحت الحد — لا زر توسيع');
    });
  });
}
