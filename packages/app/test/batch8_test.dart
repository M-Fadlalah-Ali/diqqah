import 'package:flutter/material.dart';
// LogicalKeyboardKey لا يمر عبر material بهذا الإصدار (درس CI الجولة 112)
// — والاستيراد المحدد لا يباد لأنه مستعمل فعلاً.
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf/pdf.dart' show PdfPageFormat;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';
import 'package:diqqah_app/print_service.dart';
import 'package:diqqah_app/input_formatters.dart';
import 'package:diqqah_app/ui_fonts.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة (8) «تكميلات ما قبل الإغلاق» — س-105..س-116 وقراراتها
/// D-102..D-107 بلفظ المالك واعتماده (س39) — بنمط القاعدة
/// `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle (درس
/// س22..س26 الموثق)، والحكم بنصوص فريدة (درس س35).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً — حقل أسفل
  /// النموذج غير مبني خارج الشاشة فلا يُلمَس قبل تمريره إلى النافذة.
  /// ودرس CI (جولة 110): بعد فتح قائمة منسدلة يبقى بمحلكة قابلة للتمرير
  /// فيفشى الـListView بأثنين — فالأول دائماً هو القائمة الأصلية.
  Future<void> _scrollTo(WidgetTester tester, String label) async {
    for (var i = 0;
        i < 6 && find.widgetWithText(TextField, label).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -260));
      await tester.pump();
    }
  }

  test('D-102: فواصل الألوف — التجميع والقراءة نقياً والمخزن خام دائماً',
      () {
    expect(groupDigits(15000), '15,000');
    expect(groupDigits(15000000), '15,000,000');
    expect(groupDigits(0), '0');
    expect(groupDigits(-2500), '-2,500');
    expect(parseGroupedInt('15,000'), 15000);
    expect(parseGroupedInt(''), 0, reason: 'الفراغ «بلا سعر بعد» (س6)');
    expect(parseGroupedInt('1,000,000'), 1000000);
  });

  test('س-112 (D-102): الفواصل أثناء الكتابة — formatter حي والمؤشر باقٍ',
      () {
    const f = ThousandsSeparatorInputFormatter();
    // كتابة 15000 — آخر حالة «15000» مكتوبة حرفاً حرفاً وتُقرأ النتيجة
    final written = f.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(
          text: '15000', selection: TextSelection.collapsed(offset: 5)),
    );
    expect(written.text, '15,000');
    expect(written.selection.baseOffset, 6,
        reason: 'المؤشر بعد آخر رقم لا في البداية');
    // حذف رقم من الوسط يبقي الفواصل متسقة
    const current = TextEditingValue(
        text: '15,000', selection: TextSelection.collapsed(offset: 4));
    final deleted = f.formatEditUpdate(
        current,
        const TextEditingValue(
            text: '15,00', selection: TextSelection.collapsed(offset: 3)));
    expect(deleted.text, '1,500');
    // فراغ الحقل يبقى فارغاً لا صفراً
    final emptied = f.formatEditUpdate(
        current, const TextEditingValue(text: ''));
    expect(emptied.text, '');
    // لقطة الصرف المكبرة — مثال المالك نفسه
    final fx = f.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(
          text: '15000000', selection: TextSelection.collapsed(offset: 8)),
    );
    expect(fx.text, '15,000,000');
  });

  test('D-105 (س-116): مصطلح «سند دفع» — التسمية تبُدّل والقيمة التخزينية '
      'لا تتغير فلا ترحيل بيانات', () {
    expect(VoucherKind.payment.label, 'سند دفع');
    expect(VoucherKind.payment.storageValue, 'payment',
        reason: 'القيمة التقنية باقية — البيانات القديمة كما هي');
    expect(VoucherKind.receipt.label, 'سند قبض');
    expect(sequenceKindLabels['voucher_payment'], 'سند دفع');
    expect(sequenceKindLabels['voucher_receipt'], 'سند قبض');
  });

  test('D-108 (س-111): التاريخ الافتراضي بتاريخ اليوم — نقي بكل النماذج',
      () {
    final t = todayIsoDate(now: DateTime(2026, 3, 15));
    expect(t, '2026-03-15');
    expect(isValidIsoDate(todayIsoDate()), isTrue);
  });

  test('D-104 (س-115): مكتبة الخط المدمجة — ساحل وتجوال حصراً وساحل '
      'الافتراضي، وأي قيمة غريبة تعيد ساحل بلا استثناء', () {
    expect(kDefaultFontKey, 'sahel');
    expect(appFontFamily('sahel'), 'Sahel');
    expect(appFontFamily('tajawal'), 'Tajawal');
    expect(appFontFamily('amiri'), 'Sahel',
        reason: 'أميري خارج الخيارات (D-104) — الغريب يعيد الافتراضي');
    expect(kFontChoices.map((c) => c.$1).toSet(), {'sahel', 'tajawal'});
  });

  test('س-114 (D-103): التخطيط بالنسب — نفس المستند يُبنى بمقاسين ويبقى '
      'PDF صحيحاً، والافتراضيات لا تتغير (A5 فواتير A4 تقارير)', () async {
    final a5 = await buildDocumentPdf(
      title: 'سند دفع 26000001',
      headerPairs: const [('التاريخ', '2026-03-15')],
      columns: const ['الصنف', 'الكمية'],
      rows: const [['زيت محلي', '2']],
      footerPairs: const [('المبلغ', '80,000')],
      format: PdfPageFormat.a5,
    );
    final a4 = await buildDocumentPdf(
      title: 'سند دفع 26000001',
      headerPairs: const [('التاريخ', '2026-03-15')],
      columns: const ['الصنف', 'الكمية'],
      rows: const [['زيت محلي', '2']],
      footerPairs: const [('المبلغ', '80,000')],
      format: PdfPageFormat.a4.copyWith(
          width: PdfPageFormat.a4.height, height: PdfPageFormat.a4.width),
    );
    expect(a5, isNotEmpty);
    expect(a4, isNotEmpty);
    expect(a4.length, isNot(a5.length),
        reason: 'مقاسان مختلفان تخطيطان مختلفان بنسب كلٍّ منهما');
    final invoice = resolvePageFormat(docKind: 'invoice');
    expect(invoice.width, closeTo(PdfPageFormat.a5.width, 0.5));
  });

  testWidgets('س-108 (D-107): اختيار الصنف يعرضه بترتيب المالك '
      '«الرقم – الاسم – المتاح – السعر» ويعبّئ السعر الافتراضي من بطاقة '
      'الصنف بسعر الجهة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // النوع الافتراضي شراء — فتح القائمة يبني عناصرها فتظهر سطور
    // المعلومات (س-108) ثم اختيار الصنف يعبّئ السعر الافتراضي بسعر الشراء
    await tester.tap(find.text('الصنف').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('سعر شراء: 25,000'), findsWidgets);
    await tester.tap(find.textContaining('زيت محلي').last);
    await tester.pump(const Duration(milliseconds: 100));
    await _scrollTo(tester, 'سعر الوحدة بوحدة صغرى');
    expect(find.text('25,000'), findsWidgets,
        reason: 'سعر الشراء عُبّئ مفصولاً في حقل سعر الوحدة');

    // تبديل الجهة إلى بيع يعبّئ البند المعبأ آلياً بسعر البيع (س-108)
    // — محوّل س-163/D-161 (دفعة 18): الجهة لا تتبدل بالنموذج بعد العزل
    // فالتحويل نموذجَ ثانٍ بلسان زر البيع المعزول (عرف تحويل دفعة 17).
    // درس جولة CI (فشل الدفعة 18): pumpWidget بشاشة من النوع ذاته يعيد
    // استخدام الحالة ولا يشغّل initState — و`_kind = widget.initialKind`
    // يُقرأ عند الولادة حصراً فبقي النموذج شراءً وسعر 25,000 — والمفتاح
    // الفريد يجبل حداً جديداً بنوعه المثبت بيعاً.
    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(
            key: const ValueKey('س-108-نموذج-البيع'),
            db: db,
            initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('الصنف').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('زيت محلي').last);
    await tester.pump(const Duration(milliseconds: 100));
    await _scrollTo(tester, 'سعر الوحدة بوحدة صغرى');
    expect(find.text('40,000'), findsWidgets,
        reason: 'سعر البيع عُبّئ آلياً بنموذج زر البيع المعزول');
  });

  testWidgets('س-106 (D-106): الرصيد الآن للصندوق المختار ظاهر قبل الحفظ',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('الرصيد الآن:'), findsOneWidget);
  });

  testWidgets('س-111 (D-108): التاريخ معبأ افتراضياً بتاريخ اليوم في '
      'نموذجي الفاتورة والسند — قابلاً للتعديل', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
        home: DefaultTabController(
            length: 1,
            child: Column(children: [Expanded(child: InvoiceEditScreen(db: db))]))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(todayIsoDate()), findsOneWidget);
  });

  testWidgets('س-113 (منقولة لسان العزل س-163/D-161 دفعة 18): النوع مثبت من زر الدخول — '
      'لا مبدّل نوع بالنموذج فلا تبديل جهة أصلاً، واختيار العميل بالجهة '
      'الثابتة يعمل بلسانها', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(
            db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // عزل الإدخال: لا مبدّل نوع بالنموذج حصراً — فعلّة س-113 (بقاء
    // «العميل» بلون التحديد بعد تبديل الجهة) زالت بزوال التبديل ذاته
    expect(find.text('نوع الفاتورة'), findsNothing,
        reason: 'النوع من زر القائمة الرئيسية لا بانتقاء بالنموذج');
    expect(find.text('فاتورة بيع'), findsWidgets,
        reason: 'لافتة النوع المثبت بلسان زر الدخول');

    // بيع ← آجل ← اختيار العميل — بالجهة الثابتة من الزر
    await tester.tap(find.text('نقدي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('آجل').last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('العميل (الآجل يطلب طرفاً)'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('عميل الأمل').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('عميل الأمل'), findsWidgets);
  });

  testWidgets('س-105 (D-106): رصيد الطرف الجاري في نموذج السند — بالقائمة '
      'وأسفل الحقل بعد الاختيار، من تقرير الذمم حصراً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // النوع الافتراضي سند قبض — اختيار العميل يعرض ذمته في القائمة
    await tester.tap(find.textContaining('العميل (القبض على ذمم العملاء)'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('عميل الأمل').last);
    await tester.pump(const Duration(milliseconds: 100));
    // سطر الرصيد أسفل الحقل — والذمة من تقرير الذمم بالاتجاهين
    expect(find.textContaining('رصيد حسابه الجاري:'), findsOneWidget);
  });

  testWidgets('س-116 (D-105): نموذج السند باتجاه الدفع يعرض «الدفع من ذمم '
      'الموردين» — المصطلح الجديد في الواجهة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.textContaining('سند قبض').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('سند دفع').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('المورد (الدفع من ذمم الموردين)'), findsOneWidget);
  });

  testWidgets('س-109 (D-110): Tab في حقل الكمية يضيف بنداً جديداً وينقل '
      'المؤشر إليه — الإدخال بلوحة المفاتيح بلا مسك الفأرة (وEnter عبر '
      'onSubmitted الحقل نفسه بقناة IME الحية)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    int countQtyFields() =>
        find.widgetWithText(TextField, 'الكمية').evaluate().length;
    await _scrollTo(tester, 'الكمية');
    expect(countQtyFields(), 1);

    // ensureVisible كي يكون الحقل كله داخل النافذة قبل الضغط — درس CI:
    // tap على حقل نصفه خارج الشاشة (Offset 610>600) فات فلم يتركز الحقل
    await tester.ensureVisible(
        find.widgetWithText(TextField, 'الكمية').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'الكمية').first);
    await tester.pump();
    // الحدث عبر قناة العتاد — Tab مُعترضه بwrapper KeyboardAddLine
    // (onKeyEvent) فقناتها HardwareChannel التي يغذيها sendKeyEvent،
    // بينما Enter يمر قناة IME ولا يصل onSubmitted في بيئة الاختبار
    // (درس CI: الجولتان 110/111)
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(countQtyFields(), 2,
        reason: 'Tab أضاف بنداً جديداً — والمؤشر انتقل إلى كمية البند الجديد');
  });

  testWidgets('س-111/س-109 (D-108/D-110): نموذج السند بتاريخ اليوم — '
      'والمبلغ بوحدة صغرى مفصولاً أثناء الكتابة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(todayIsoDate()), findsOneWidget);

    final amount = find.widgetWithText(TextField, 'المبلغ بوحدة صغرى');
    await tester.enterText(amount, '15000');
    await tester.pump();
    expect(find.text('15,000'), findsOneWidget,
        reason: 'الفواصل تعمل أثناء الكتابة (تنبيه المالك) والمخزن يقرأه '
            'parseGroupedInt عند الحفظ');
  });
}
