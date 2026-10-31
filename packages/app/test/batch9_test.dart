import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';
import 'package:diqqah_app/reports_screen.dart';
import 'package:diqqah_app/input_formatters.dart';

import 'seed_cycle.dart';

/// اختبارات دفعة (9) «تكميلات التجربة الأولى» — س-117..س-122 وقراراتها
/// D-112..D-117 بلفظ المالك واعتماده «ابدأ التنفيذ» (س40) — بنمط
/// القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle إلا
/// للقوائم المنسدلة (درس س22..س26)، والحكم بنصوص فريدة (درس س35).
///
/// نقاط المالك الحرفية التي أنجبت هذه الدفعة: «ألا أستطيع إدخال خصم
/// 3.5٪؟» و«التاريخ في التقارير غير محدد» و«لم يحدث التطبيق الكمية
/// المتاحة» و«افتقدت في الفواتير إجمالي السطر» و«رصيد الصندوق في
/// السندات غير موجود».
void main() {
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول: ListView يبني الظاهر حصراً — التمرير حتى يظهر
  /// النص المطلوب قبل لمسه، وتحصين ensureVisible قبل الضغط (درس ج4).
  Future<void> _scrollToText(WidgetTester tester, String text) async {
    for (var i = 0; i < 10 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -260));
      await tester.pump();
    }
    final f = find.text(text);
    if (f.evaluate().isNotEmpty) {
      await tester.ensureVisible(f.last);
      await tester.pump();
    }
  }

  test('D-112: قارئ النسبة ×100 ومنسّق الفاصلة العشرية نقياً', () {
    expect(parsePercentRate100('3.5'), 350);
    expect(parsePercentRate100('2.75'), 275);
    expect(parsePercentRate100('10'), 1000);
    expect(parsePercentRate100('100'), 10000);
    expect(parsePercentRate100(''), 0, reason: 'الفراغ بلا خصم');
    expect(parsePercentRate100('3,5'), 350, reason: 'الفاصلة العربية توحَّد');
    expect(parsePercentRate100('3٫5'), 350, reason: 'الأرابيزك ديسيمال توحَّد');
    const f = PercentDecimalInputFormatter();
    final typed = f.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(
          text: '3,5', selection: TextSelection.collapsed(offset: 3)),
    );
    expect(typed.text, '3.5', reason: 'الفاصلة توحَّد إلى نقطة');
    final secondDot = f.formatEditUpdate(
      const TextEditingValue(text: '3.5'),
      const TextEditingValue(
          text: '3.5.', selection: TextSelection.collapsed(offset: 4)),
    );
    expect(secondDot.text, '3.5', reason: 'فاصلة ثانية تُسقط');
    final garbage = f.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(
          text: 'abc12', selection: TextSelection.collapsed(offset: 5)),
    );
    expect(garbage.text, '12', reason: 'لصق شاذ يُسقط غير الرقم');
  });

  testWidgets('س-117 (D-112): خصم 3.5% يُدخل بالمثال الحرفي ويُخزن ×100 '
      'والمجاميع صحيحة لحظياً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // اختيار الصنف
    await tester.tap(find.text('الصنف').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('زيت محلي').last);
    await tester.pump(const Duration(milliseconds: 100));

    // الكمية والسعر — وبطاقة السطر تعرض إجماليه لحظياً (س-120)
    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية').first, '2');
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'سعر الوحدة بوحدة صغرى').first,
        '15,000');
    await tester.pump();
    expect(find.textContaining('إجمالي السطر: 30,000'), findsOneWidget);

    // الخصم العشري 3.5 — مثال المالك الذي فتح هذه الدفعة
    await _scrollToText(tester, 'خصم الفاتورة نسبةً 0..100 (اختياري)');
    await tester.enterText(
        find.widgetWithText(TextField, 'خصم الفاتورة نسبةً 0..100 (اختياري)'),
        '3.5');
    await tester.pump();

    // التمرير للحفظ يبني بطاقة المجاميع الملاصقة — فتُفحص لحظيتها
    await _scrollToText(tester, 'حفظ وترحيل');
    expect(find.textContaining('الخصم 1,050'), findsOneWidget);
    expect(find.textContaining('الإجمالي 28,950'), findsOneWidget);

    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();

    // المخزن ×100: 3.5% مخزنة 350 — والقراءة من القاعدة لا الشاشة
    final row = (await db.customSelect(
      "SELECT discount_rate FROM invoices WHERE state <> 'draft'",
    ).getSingle()).data;
    expect(row['discount_rate'], 350);
  });

  testWidgets('س-118 (D-113): افتراضيات مدى التقارير — «من» أول مستند '
      'مرحّل إن كان أحدث من أول السنة و«إلى» اليوم', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db); // أول مستند <السنة>-03-15 — أحدث من 1/1

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.tap(find.text('مبيعات وحركة الأصناف'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    final year = DateTime.now().year;
    expect(find.text('$year-03-15'), findsOneWidget,
        reason: '«من» تاريخ أول المدة لأنه ليس بداية العام — بلفظ المالك');
    expect(find.text(todayIsoDate()), findsOneWidget,
        reason: '«إلى» تاريخ اليوم الحالي');
  });

  testWidgets('س-118 (D-113) فرع: بلا مستندات «من» أول السنة الحالية',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.tap(find.text('مبيعات وحركة الأصناف'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('${DateTime.now().year}-01-01'), findsOneWidget,
        reason: 'لا مستندات فيقع الافتراض على أول العام');
  });

  testWidgets('س-119 (D-114): المتاح ظاهر منذ أول فتح بعد ترحيل الشراء '
      '— إصلاح علة المالك بلا تبديل مستودع يدوي', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db); // شراء 10 رحّل فبيع 6 — المتاح 4

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // فتح القائمة مباشرة — كانت العلة تُظهر خريطة فارغة أول فتح
    await tester.tap(find.text('الصنف').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('المتاح: 4'), findsWidgets,
        reason: 'المخزون المترحل مرئي من أول فتح (كان صفراً بالعلة)');
  });

  testWidgets('س-120 (D-115): إجمالي السطر يتجدد لحظياً مع كل ضغطة',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('الصنف').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('زيت محلي').last);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية').first, '2');
    await tester.pump();
    expect(find.textContaining('إجمالي السطر: 0'), findsOneWidget,
        reason: 'السعر فارغ فالإجمالي صفر — لحظياً لا متجمداً');

    await tester.enterText(
        find.widgetWithText(TextField, 'سعر الوحدة بوحدة صغرى').first,
        '15,000');
    await tester.pump();
    expect(find.textContaining('إجمالي السطر: 30,000'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'خصم السطر (اختياري)').first,
        '1,000');
    await tester.pump();
    expect(find.textContaining('إجمالي السطر: 29,000'), findsOneWidget,
        reason: 'خصم السطر ينقصه لحظياً');
  });

  testWidgets('س-121 (D-116): «الرصيد الآن» تحت الصندوق بنموذج السند',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db); // الصندوق 545,000 بعد الدورة

    await tester.pumpWidget(MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('الرصيد الآن: 545,000'), findsOneWidget,
        reason: 'رصيد الصندوق قبل الحفظ — بلفظ المالك «غير موجود» أصلاً');
  });

  testWidgets('س-122 (D-117): رصيدا الصندوقين بنموذج التحويل', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await db.createCashBox(name: 'صندوق ثانٍ', currencyId: 1);

    await tester.pumpWidget(MaterialApp(home: TransferEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('الرصيد الآن:'), findsNWidgets(2),
        reason: 'المرسل والمستلم كلاهما برصيده — إضافة المستشار المعتمدة');
    expect(find.textContaining('الرصيد الآن: 545,000'), findsOneWidget);
    expect(find.textContaining('الرصيد الآن: 0'), findsOneWidget);
  });
}
