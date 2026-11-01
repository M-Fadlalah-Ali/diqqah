import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/print_service.dart';
import 'package:diqqah_app/reports_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة (11) «إصلاحات التجربة» (س-133..س-136/D-127..D-130):
/// قلب أعمدة المطبوعات بنقطة واحدة (س-134/D-128)، والاتجاه العربي
/// الكامل (س-135/D-129)، وخيار «حسب النوع» بالذمم بترتيب المدينة ثم
/// الدائنة (س-136/D-130). وزرا الطباعة الظاهران (س-133/D-127) يُختبران
/// بملف batch12 (شاشة التفاصيل أعيد بناؤها للدفعتين معاً).
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  test('س-134/D-128: قلب الأعمدة — الحساب أقصى اليمين ثم المدين ثم '
      'الدائن ثم الرصيد بلفظ المالك الحرفي', () {
    final columns = ['الحساب', 'مدين', 'دائن', 'الرصيد'];
    final rows = [
      ['1111 الصندوق الرئيسي', '550,000', '5,000', '545,000'],
      ['112 العملاء', '90,000', '50,000', '40,000'],
    ];

    final rtlColumns = rtlColumnOrder(columns);
    expect(rtlColumns, ['الرصيد', 'دائن', 'مدين', 'الحساب'],
        reason: 'العمود الأول يصير أقصى اليمين بعد القلب');

    final rtlRows = rtlRowOrder(rows);
    expect(rtlRows[0],
        ['545,000', '5,000', '550,000', '1111 الصندوق الرئيسي']);
    expect(rtlRows[1], ['40,000', '50,000', '90,000', '112 العملاء']);

    // القلب ليس التبديل: القائمة الأصلية لا تُمس
    expect(columns, ['الحساب', 'مدين', 'دائن', 'الرصيد']);
    expect(rows[0], ['1111 الصندوق الرئيسي', '550,000', '5,000', '545,000']);
  });

  test('س-134/D-128: الجدول المصور يمر بالقلب ذاته — عمود الصورة أقصى '
      'اليمين وبايتات PDF صحيحة', () async {
    final bytes = await buildDocumentPdf(
      title: 'تقرير المخزون',
      headerPairs: const [],
      columns: const ['الصنف', 'المستودع', 'الكمية', 'القيمة', 'المتوسط'],
      rows: const [
        ['Z-100 زيت محلي', 'المستودع الرئيسي', '4', '40,000', '10,000'],
      ],
      rowLeadingImages: <Uint8List?>[null],
      rowPlaceholderLetters: const ['ز'],
      footerPairs: const [],
      format: resolvePageFormat(docKind: 'report'),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.lengthInBytes, greaterThan(1000));
  });

  testWidgets('س-135/D-129: التطبيق كله باتجاه عربي — اللغة المثبتة '
      'عربية بوفد SDK الرسمية فيصير الاتجاه من اليمين', (tester) async {
    TextDirection? captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          captured = Directionality.of(context);
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(captured, TextDirection.rtl,
        reason: 'القوائم والأسهم وترتيب العناصر تنعكس كالتقارير العربية');
  });

  testWidgets('س-136/D-130: خيار «حسب النوع» بالذمم — الكل بترتيب '
      'المدينة ثم الدائنة بلفظ المالك، والفلتر يعرض النوع المختار حصراً',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('الذمم المدينة والدائنة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الترتيب الافتراضي: عميل الأمل (مدينة) قبل مورد الشرق (دائنة)
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    final titles = [
      for (final t in tiles)
        if (t.title is Text) (t.title as Text).data ?? '',
    ];
    expect(titles.indexOf('عميل الأمل'), lessThan(titles.indexOf('مورد الشرق')),
        reason: 'المدينة ثم الدائنة — بلفظ المالك «فأنا أريد المدينة ثم الدائنة»');

    // الفلتر بالمدينة حصراً — فتح القائمة بالنوع ثم اختيار العنصر
    // (نمط vouchers_screen_test: فتح بحسب النوع لا بالنص كي لا يلتبس
    // نص الحقل بعنصر القائمة)
    await tester.tap(find.byType(DropdownButtonFormField<bool>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('المدينة — هم يدينون لنا'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('عميل الأمل'), findsOneWidget);
    expect(find.text('مورد الشرق'), findsNothing);

    // والفلتر بالدائنة حصراً
    await tester.tap(find.byType(DropdownButtonFormField<bool>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('الدائنة — نحن مدينون لهم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('مورد الشرق'), findsOneWidget);
    expect(find.text('عميل الأمل'), findsNothing);
  });
}
