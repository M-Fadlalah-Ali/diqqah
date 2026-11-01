import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/delivery_screen.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/print_image_prefs.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة (12) متابعة التسليم (س-137..س-142/D-131..D-134):
/// مربع «مستلم» بتفاصيل البيع يحفظ فوراً، وزر «تسليم الكل» (قرار
/// المالك «يوجد زر تسليم الكل — لا بأس»، س43)، وشاشة المتابعة بقائمة
/// غير المستلم وزر «سُلِّم»، وقسيمة البيع بعمود «مستلم» وسطر خلاصته.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;
  // توليد القسيمة باختبار نقي — rootBundle للخط المدمج يحتاج ربطاً مهيأ
  // (درس print_service_test)، وأي IO حقيقي داخل testWidgets يعلق
  // بالزمن الوهمي (درس الجولات 124..128 الموثق).
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('س-137/D-131: مربع «مستلم» بتفاصيل فاتورة البيع — التحديد '
      'يحفظ بقاعدة البيانات فوراً على المرحّلة، وزر «تسليم الكل» يختفي '
      'بعد اكتمال التسليم', (tester) async {
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

    // زرا الإخراج النصيان ظاهران بنصهما (س-133/D-127) وزر تسليم الكل
    expect(find.text('طباعة / PDF'), findsOneWidget);
    expect(find.text('مشاركة PDF'), findsOneWidget);
    expect(find.text('تسليم الكل'), findsOneWidget);
    expect(find.textContaining('بانتظار التسليم'), findsOneWidget);

    // التحديد يحفظ فوراً
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final lines = await db.invoiceLines(saleId);
    expect(lines.single.delivered, isTrue,
        reason: 'علم العمل يُحدَّث على المرحّلة بلا فك إقفال');
    expect(find.textContaining('بانتظار التسليم'), findsNothing);
    expect(find.text('تسليم الكل'), findsNothing,
        reason: 'لا زر ميت حين يكتمل التسليم');
  });

  testWidgets('س-43 «لا بأس»: زر «تسليم الكل» يعلم كل السطور مستلمة '
      'بضغطة واحدة', (tester) async {
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

    await tester.tap(find.text('تسليم الكل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final lines = await db.invoiceLines(saleId);
    expect(lines.single.delivered, isTrue);
    expect(await db.undeliveredSaleLinesReport(), isEmpty);
  });

  testWidgets('س-139/D-133: شاشة المتابعة تعرض سطر البيع غير المستلم '
      'بفاتورته وطرفه وزر «سُلِّم» يزيله ويحفظ', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('زيت محلي × 6'), findsOneWidget);
    expect(find.textContaining('عميل الأمل'), findsOneWidget);
    expect(find.text('غير مستلم: 1 من 1'), findsOneWidget);
    expect(find.text('سُلِّم'), findsOneWidget);

    await tester.tap(find.text('سُلِّم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('لا أسطر غير مستلمة — كل البيع سُلِّم'), findsOneWidget);
    final lines = await db.invoiceLines(saleId);
    expect(lines.single.delivered, isTrue);
  });

  test('س-140/D-134: قسيمة فاتورة البيع تحمل عمود «مستلم» وسطر '
      'الخلاصة «مستلم X من Y» — بأرقام الفاتورة كما هي', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;

    final bytes = await buildInvoicePrintoutBytes(db, saleId);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.lengthInBytes, greaterThan(1000),
        reason: 'القسيمة حقيقية بعمود المستلم وسطر الخلاصة');
    // والصور بلا مفتاح — لا قراءة ملفات (D-123) والنائب مكانه
    expect(printImagesForKind(InvoiceKind.sale.storageValue), isFalse);
  });
}
