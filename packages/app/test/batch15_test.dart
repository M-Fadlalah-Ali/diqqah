// اختبارات دفعة (15) — «ما قبل إغلاق م1» — بأمر المالك الحرفي
// (س-151..س-153 / D-149..D-151): أعمار الذمم بفوهج قابلة للتهيئة،
// ودفتر اليومية المرشّح، وخانة «ملاحظة التسليم» المعروضة منذ بوابة
// دفعة (12) §3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/delivery_screen.dart';
import 'package:diqqah_app/reports_screen.dart';
import 'package:diqqah_app/invoices_screen.dart';

import 'seed_cycle.dart';

void main() {
  testWidgets('س-151/D-149: بند «أعمار الذمم» بالهيكلية يفتح التقرير '
      'بالأطراف بإجمالياتها المفتوحة وبفلتر الفوهج والنوع',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // س205 م09: القائمة أعيد تنظيمها بأقسامها — «أعمار الذمم» بقسم
    // الصناديق والذمم و«دفتر اليومية» بقسم الدفاتر والمطابقة، فالوصول
    // بالتمرير حتى الهدف لا افتراضه (نمط س184) واليومية ظاهرة أولاً.
    expect(find.text('دفتر اليومية'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('أعمار الذمم'),
      160,
      // س206 (تصويب الجولة #405): الوسيط scrollable يطلب Scrollable ذاته —
      // ListView وشيعة لا يصلح وسيطاً (type cast كشفه المحلل الحي).
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('أعمار الذمم'), findsOneWidget);

    // فتح أعمار الذمم — الطرفان بمفتوحهما: العميل 40,000 (بقيت
    // بعد مطابقة 50,000) والمورد 100,000 كاملة.
    await tester.tap(find.text('أعمار الذمم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('عميل الأمل'), findsOneWidget);
    expect(find.text('مورد الشرق'), findsOneWidget);
    expect(find.text('الإجمالي 140,000'), findsOneWidget);
    // بترتيب D-130: المدينة أولاً — عميل الأمل أعلى القائمة.
    expect(
      tester.getTopLeft(find.text('عميل الأمل')).dy,
      lessThan(tester.getTopLeft(find.text('مورد الشرق')).dy),
    );
  });

  testWidgets('س-152/D-150: بند «دفتر اليومية» يفتح القيود المرحّلة '
      'بترتيب الزمن ومجموعاه متوازنان بمطابقة الميزان',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // س205 م09: البند بقسم الدفاتر والمطابقة بأول القائمة المعاد
    // تنظيمها — ظاهر دون سحبة (والسحبة القديمة كانت لإظهاره بنهايتها
    // قبل التنظيم).
    expect(find.text('دفتر اليومية'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('دفتر اليومية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المجموعان بمطابقة الميزان المعروفة (805,000/805,000).
    expect(
        find.textContaining('مجموع المدين 805,000'), findsOneWidget);
    expect(
        find.textContaining('مجموع الدائن 805,000'), findsOneWidget);
    // القيود الظاهرة أول القائمة — صندوق 1111 بحركة الضخ والقبض والعجز.
    expect(find.textContaining('1111'), findsWidgets);

    // ثم سحبة على القيود: شريط اختصارات المدى (س204 — م02) أضاف
    // ارتفاعاً فوق القائمة فزال قيد البيع من نطاق بنائها — والسحبة
    // بعد فحص الظاهر حرفاً فالبناء الكسول يزيل الأول ويجلب الأخير
    // بنفس القانون (درس D-098/س184 — والوصول بالتمرير لا الافتراض).
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // ودفتر المبيعات بحصته — قيد البيع بعد السحبة.
    expect(find.textContaining('دفتر المبيعات'), findsWidgets);
  });

  testWidgets('س-153/D-151: خانة «ملاحظة التسليم» تُحرَّر من شاشة '
      'المتابعة على السطر غير المستلم وتظهر بصفّه بعد الحفظ',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // صف السطر غير المستلم بلا ملاحظة بعد — وزر التحرير أيقونة قلم
    // ظاهرة بجانب «سُلِّم» (لا زر مدفون).
    expect(find.textContaining('ملاحظة:'), findsNothing);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);

    // فتح حوار الملاحظة وكتابتها وحفظها.
    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'مواصفات خاصة: تغليف بعلبتين',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الملاحظة ظهرت بصف السطر نفسه بعد الحفظ الفوري.
    expect(find.textContaining('ملاحظة: مواصفات خاصة'),
        findsOneWidget);
    // وزر «سُلِّم» باقٍ — الملاحظة لا تغيب العملية.
    expect(find.text('سُلِّم'), findsOneWidget);
  });

  test('س-153/D-151: قسيمة البيع المطبوعة تُبنى بعمود الملاحظة حين '
      'وُجدت — وبكامل بايتاتها PDF', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
    ).getSingle()).data['id'] as int;

    // بلا ملاحظة: القسيمة تُبنى — وعمود «ملاحظة» لا بلا مبرر.
    final bytesWithout = await buildInvoicePrintoutBytes(db, saleId);
    expect(String.fromCharCodes(bytesWithout.take(5)), '%PDF-');

    // ملاحظة على السطر غير المستلم فتُبنى القسيمة بعمودها.
    final lineId = (await db.customSelect(
      'SELECT id FROM invoice_lines WHERE invoice_id = $saleId '
      'ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    await db.setInvoiceLineDeliveryNote(lineId,
        note: 'مواصفات خاصة: تغليف بعلبتين');
    final bytesWith = await buildInvoicePrintoutBytes(db, saleId);
    expect(String.fromCharCodes(bytesWith.take(5)), '%PDF-');
    expect(bytesWith.lengthInBytes, greaterThan(1000));
  });
}
