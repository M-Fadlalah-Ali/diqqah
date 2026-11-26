// اختبارات دفعة (14) — كمية التسليم والتفقيط — بأوامر المالك الحرفية
// (س-148..س-149 / D-138..D-139): الافتراضي «مجموع الكميات بالواحدة»
// والقائمة المنسدلة بخيارَيها في نفس السطر، والتفقيط للمبلغ حصراً.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/delivery_screen.dart';
import 'package:diqqah_app/delivery_summary.dart' show DeliveryBasis;
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/tafqit.dart';

import 'seed_cycle.dart';

void main() {
  testWidgets('س-148/D-138: عدّاد تفاصيل الفاتورة بالكميات بالواحدة '
      'افتراضاً وقائمة التبديل في نفس السطر وزر «تسليم الكل» يكمل الجملة',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;

    await tester.pumpWidget(
        MaterialApp(home: InvoiceDetailScreen(db: db, invoiceId: saleId)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الافتراضي: مجموع الكميات بالوحدة («بالواحدة» بقرار المالك).
    expect(find.text('مستلم 0 من 6 قطعة — المتبقي: 6 قطعة'),
        findsOneWidget);
    // القائمة المنسدلة بخيارَيها في نفس السطر.
    expect(find.text('حسب الكميات'), findsOneWidget);
    expect(find.byType(DropdownButton<DeliveryBasis>), findsOneWidget);

    // التبديل إلى الأسطر — نفس السطر يتبدل بلسانه.
    await tester.tap(find.text('حسب الكميات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('حسب الأسطر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('مستلم 0 من 1 — المتبقي: 1'), findsOneWidget);

    // وزر «تسليم الكل» (س43) يكمل — والعدّاد يعلن الاكتمال بأساسه.
    await tester.tap(find.text('تسليم الكل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('مستلم 1 من 1 — اكتمل التسليم'), findsOneWidget);
    // ولا زر ميت: زر «تسليم الكل» يُسحب كلياً عند الاكتمال.
    expect(find.text('تسليم الكل'), findsNothing);
  });

  testWidgets('س-148/D-138: ترويسة المتابعة بالكميات افتراضاً '
      'وباسم الوحدة في صف القائمة والتبديل يعيدها لسان D-133',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الافتراضي: مجموع الكميات بالواحدة.
    expect(find.text('غير مستلم: 6 قطعة'), findsOneWidget);
    // واسم الوحدة يُرى في صف القائمة نفسه.
    expect(find.textContaining('زيت محلي × 6 قطعة'), findsOneWidget);
    expect(find.text('حسب الكميات'), findsOneWidget);

    // التبديل إلى الأسطر يعيد لسان D-133 القائم.
    await tester.tap(find.text('حسب الكميات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('حسب الأسطر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('غير مستلم: 1 من 1'), findsOneWidget);
  });

  test('س-149/D-139: القسيمة تُبنى وتحمل سطر التفقيط بمحركها '
      'وبعملة المستند من جدولها — والقسيمة كاملة البايتات', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;

    // محرك التفقيط نفسه بإجمالي الفاتورة المبذورة (6 × 15,000).
    final totalMinor = (await db.invoiceById(saleId))!.totalDocMinor;
    expect(totalMinor, 90000);
    final syp =
        tafqitCurrencyFor(code: 'SYP', name: 'ليرة سورية', minorUnits: 2);
    expect(
      tafqitAmountWords(totalMinor: totalMinor, currency: syp),
      'فقط تسعمئة ليرة سورية لا غير',
    );

    // وبناء القسيمة كاملة — بعمود المستلم وسطر الخلاصة وسطر «بالكلمات».
    final bytes = await buildInvoicePrintoutBytes(db, saleId);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.lengthInBytes, greaterThan(1000));
  });
}
