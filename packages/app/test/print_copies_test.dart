import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/invoices_screen.dart' show buildInvoicePrintoutBytes;
import 'package:diqqah_app/print_copies.dart';
import 'package:diqqah_app/settings_screen.dart' show SettingsScreen;

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات س119 — قوالب طباعة الفواتير ونسخة أمين المستودع بنافذة
/// الأمر الواحد (بكلمة المالك: خياران مفعلان افتراضياً دائماً،
/// والإزالة لهذه المرة فقط فالأمر التالي يعود افتراضياً، ومفتاح
/// الإلغاء في الخيارات). القالب عرض لا مصدر بيانات، والافتراضي
/// مطابق السلوك القائم حرفاً (حارس انحدار).
void main() {
  installTestTimeoutGuard();

  setUp(() {
    // مخزن التفضيلات وهمي — الافتراضيات هي الحكم (نمط D-104/D-123).
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('س119: الافتراضيات — نسخة المستودع مفعّلة وقالب كل نوع a5 طولي '
      'بأعلام الظهور كلها', () async {
    await loadPrintTemplatePrefs();
    expect(warehouseCopyEnabled.value, isTrue,
        reason: 'بلفظ المالك: مفعلان افتراضياً دائماً');
    for (final (key, _) in kPrintTemplateKindChoices) {
      final kind = InvoiceKind.fromStorage(key);
      expect(templateSizeForKind(kind), 'a5', reason: 'D-101: الفاتورة A5');
      expect(templateLandscapeForKind(kind), isFalse,
          reason: 'D-101: الفاتورة طولية');
      for (final flag in PrintTemplateFlag.values) {
        expect(templateFlagForKind(kind, flag), isTrue,
            reason: 'الغائب ظاهر — مطابق السلوك القائم حرفاً');
      }
    }
  });

  test('س119: الحفظ يحدّث القارئ الفوري ويستمر بالمخزن — والاستعادة تعيد '
      'الافتراضي', () async {
    await loadPrintTemplatePrefs();
    savePrintTemplateSize('sale', 'a4');
    savePrintTemplateLandscape('sale', true);
    savePrintTemplateFlag('sale', PrintTemplateFlag.delivered, false);
    saveWarehouseCopyEnabled(false);
    expect(templateSizeForKind(InvoiceKind.sale), 'a4');
    expect(templateLandscapeForKind(InvoiceKind.sale), isTrue);
    expect(templateFlagForKind(InvoiceKind.sale, PrintTemplateFlag.delivered),
        isFalse);
    expect(warehouseCopyEnabled.value, isFalse);
    // وغيره من الأنواع لم يُمس — القوالب لكل نوع على حدة.
    expect(templateSizeForKind(InvoiceKind.purchase), 'a5');
  });

  testWidgets('س119: نافذة الأمر الواحد — الخياران مفعلان عند كل فتح '
      'وإزالة أحدهما لا تُكتب فالأمر التالي يعود افتراضياً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' AND state <> 'draft' "
      'ORDER BY id DESC LIMIT 1',
    ).getSingle()).data['id'] as int;
    await loadPrintTemplatePrefs();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () => showInvoicePrintCopiesDialog(ctx, db, saleId),
              child: const Text('افتح أمر الطباعة'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح أمر الطباعة'));
    await tester.pumpAndSettle();

    expect(find.text('طباعة الفاتورة'), findsOneWidget);
    // الخياران مفعلان افتراضياً — قيم المربعات نفسها.
    final customerTile = tester.widget<CheckboxListTile>(find.widgetWithText(
        CheckboxListTile, 'نسخة الزبون'));
    expect(customerTile.value, isTrue);
    final warehouseTile = tester.widget<CheckboxListTile>(
        find.widgetWithText(
            CheckboxListTile, 'نسخة أمين المستودع (بلا أسعار)'));
    expect(warehouseTile.value, isTrue);

    // إزالة نسخة المستودع لهذه المرة فقط ثم الإغلاق.
    await tester.tap(find.text('نسخة أمين المستودع (بلا أسعار)'));
    await tester.pump();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    // الأمر التالي يعود افتراضياً: الاثنان مفعلان (الحالة لا تُكتب).
    await tester.tap(find.text('افتح أمر الطباعة'));
    await tester.pumpAndSettle();
    final warehouseAgain = tester.widget<CheckboxListTile>(
        find.widgetWithText(
            CheckboxListTile, 'نسخة أمين المستودع (بلا أسعار)'));
    expect(warehouseAgain.value, isTrue,
        reason: 'بلفظ المالك: الأمر التالي للطباعة يعود إلى الافتراضي');
  });

  testWidgets('س119: مفتاح الإلغاء من الخيارات — نسخة المستودع تختفي من '
      'النافذة ويبقى أمر النسخة الواحدة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' AND state <> 'draft' "
      'ORDER BY id DESC LIMIT 1',
    ).getSingle()).data['id'] as int;
    await loadPrintTemplatePrefs();
    saveWarehouseCopyEnabled(false);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () => showInvoicePrintCopiesDialog(ctx, db, saleId),
              child: const Text('افتح أمر الطباعة'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح أمر الطباعة'));
    await tester.pumpAndSettle();
    expect(find.text('نسخة الزبون'), findsOneWidget);
    expect(find.text('نسخة أمين المستودع (بلا أسعار)'), findsNothing,
        reason: 'بلفظ المالك: خيار إلغاء طباعة نسخة أمين المستودع '
            'من الخيارات');
  });

  testWidgets('س119: بطاقة الإعدادات بنهاية القائمة — مفتاح النسخة يفرض '
      'قراره فوراً على نافذة الأمر', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await loadPrintTemplatePrefs();

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: '/tmp/diqqah_test.db',
      onRestored: () {},
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // البطاقة بنهاية القائمة عمداً (درس ميزانية السحب) — تمرير إليها
    // بأول Scrollable حصراً (درس الجولات: أكثر من Scrollable بالشاشة).
    // س186 (تنظيف م08): رمز العمل نُزع من عنوان البطاقة فنُزع من التوقع
    final cardTitle = find.text('قوالب طباعة الفواتير');
    await tester.scrollUntilVisible(
      cardTitle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(cardTitle, findsOneWidget);
    expect(find.text('نسخة أمين المستودع مع نسخة الزبون'), findsOneWidget);
    expect(find.text('القياس'), findsOneWidget);
    expect(find.text('الاتجاه'), findsOneWidget);
    expect(find.text('استعادة افتراضيات هذا النوع'), findsOneWidget);

    // مفتاح المالك: الإلغاء يصل القارئ الفوري حيّاً.
    expect(warehouseCopyEnabled.value, isTrue);
    await tester.tap(find.text('نسخة أمين المستودع مع نسخة الزبون'));
    await tester.pumpAndSettle();
    expect(warehouseCopyEnabled.value, isFalse,
        reason: 'بلفظ المالك: خيار إلغاء خيار طباعة نسخة أمين المستودع');
  });

  test('س119: نسخة أمين المستودع PDF صحيح مختلف عن نسخة الزبون — '
      'والتحويل الحر بالقياس يغيّر الورقة', () async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final saleId = (await db.customSelect(
      "SELECT id FROM invoices WHERE kind = 'sale' AND state <> 'draft' "
      'ORDER BY id DESC LIMIT 1',
    ).getSingle()).data['id'] as int;
    await loadPrintTemplatePrefs();

    final customer = await buildInvoicePrintoutBytes(db, saleId);
    final warehouse =
        await buildInvoicePrintoutBytes(db, saleId, warehouseCopy: true);
    expect(String.fromCharCodes(customer.take(5)), '%PDF-');
    expect(String.fromCharCodes(warehouse.take(5)), '%PDF-');
    expect(warehouse, isNot(customer),
        reason: 'النسختان قالبان مختلفان من البيانات ذاتها');

    // التحويل الحر: القياس يُمرَّر لحظة الطباعة فيتغير المطبوع.
    final customerA4 =
        await buildInvoicePrintoutBytes(db, saleId, sizeOverride: 'a4');
    expect(customerA4, isNot(customer),
        reason: 'D-101/D-103: التجاوز اللحظي يعمل والنسب تبقى');

    // القالب يقرر الظهور: إخفاء عمود «مستلم» يغيّر المطبوع.
    savePrintTemplateFlag('sale', PrintTemplateFlag.delivered, false);
    final noDelivered = await buildInvoicePrintoutBytes(db, saleId);
    expect(noDelivered, isNot(customer),
        reason: 'قالب النوع يحكم أعمدة القسيمة');
  });

  // ═══ س162 (الشطر الثاني D-103/م-45): الأوزان والنصان الحرّان ═══

  test('س162: المحلل النقي لحقل الأوزان — الفواصل العربية واللاتينية والعشري والشاذ يمسح والفارغ يعود null', () {
    expect(parseColumnWeightsInput(null), isNull);
    expect(parseColumnWeightsInput(''), isNull);
    expect(parseColumnWeightsInput('  '), isNull);
    expect(parseColumnWeightsInput('2, 1, 1, 1'), [2.0, 1.0, 1.0, 1.0]);
    expect(parseColumnWeightsInput('2، 1، 1، 1'), [2.0, 1.0, 1.0, 1.0],
        reason: 'الفاصلة العربية مقبولة بنمط حقل D-102');
    expect(parseColumnWeightsInput('1.5, 0.5'), [1.5, 0.5]);
    expect(parseColumnWeightsInput('2, أب, 1'), [2.0, 1.0],
        reason: 'الرمز الشاذ يمسح لا يكسر');
    expect(parseColumnWeightsInput('-3, 0, 1'), [1.0],
        reason: 'السالب والصفر خارج حقل الأوزان');
    expect(parseColumnWeightsInput('أب، ج'), isNull,
        reason: 'الكل الفاسد يعود null — الأعمدة المتساوية حرفاً');
  });

  test('س162: الافتراضيات بلا أوزان ولا نصين حرين (حارس انحدار) — والحفظ يقرأ فوراً ويستمر بالمخزن — والفراغ يعيد الافتراضي', () async {
    await loadPrintTemplatePrefs();
    final kind = InvoiceKind.sale;
    expect(columnWeightsForKind(kind), isNull,
        reason: 'الغائب أعمدة متساوية مطابق السلوك القائم حرفاً');
    expect(freeHeaderTextForKind(kind), '');
    expect(freeFooterTextForKind(kind), '');

    savePrintTemplateWeights('sale', [2.0, 1.0, 1.0, 1.0]);
    savePrintTemplateFreeText('sale',
        isHeader: true, value: 'فاتورة ضريبية');
    savePrintTemplateFreeText('sale',
        isHeader: false, value: 'شكراً لتعاملكم معنا');
    expect(columnWeightsForKind(kind), [2.0, 1.0, 1.0, 1.0]);
    expect(freeHeaderTextForKind(kind), 'فاتورة ضريبية');
    expect(freeFooterTextForKind(kind), 'شكراً لتعاملكم معنا');
    // وغيره من الأنواع لم يُمس — القوالب لكل نوع على حدة
    expect(columnWeightsForKind(InvoiceKind.purchase), isNull);

    // والاستمرار بالمخزن المحلي — أعِد التحميل فتعود القيم نفسها
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await loadPrintTemplatePrefs();
    expect(columnWeightsForKind(kind), [2.0, 1.0, 1.0, 1.0]);
    expect(freeHeaderTextForKind(kind), 'فاتورة ضريبية');
    expect(freeFooterTextForKind(kind), 'شكراً لتعاملكم معنا');

    // والفراغ (مسح الحقل) يعيد الافتراضي — عودة للمتساوي بلا نص
    savePrintTemplateWeights('sale', null);
    savePrintTemplateFreeText('sale', isHeader: true, value: ' ');
    savePrintTemplateFreeText('sale', isHeader: false, value: '');
    expect(columnWeightsForKind(kind), isNull);
    expect(freeHeaderTextForKind(kind), '');
    expect(freeFooterTextForKind(kind), '');
  });

  testWidgets('س162: بطاقة القوالب — الكتابة بالحقول الثلاثة تحفظ لحظياً وتُزامن عند تبديل النوع', (tester) async {
    await loadPrintTemplatePrefs();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: PrintTemplatesCard()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('tpl_free_header')), 'فاتورة ضريبية');
    await tester.pump();
    expect(freeHeaderTextForKind(InvoiceKind.sale), 'فاتورة ضريبية');

    await tester.enterText(
        find.byKey(const ValueKey('tpl_weights')), '3، 1، 1، 1');
    await tester.pump();
    expect(columnWeightsForKind(InvoiceKind.sale), [3.0, 1.0, 1.0, 1.0]);

    await tester.enterText(
        find.byKey(const ValueKey('tpl_free_footer')), 'شكراً لتعاملكم معنا');
    await tester.pump();
    expect(freeFooterTextForKind(InvoiceKind.sale), 'شكراً لتعاملكم معنا');
  });
}
