import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/date_picker.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/orders_screen.dart';
import 'package:diqqah_app/reports_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات س204 — الدفعة الثانية من فحص الواجهات وفق M3 بأمر المالك
/// «أقفل م4 وابدأ الدفعة الثانية من m3»:
/// - **م01 مرحلته الأولى**: عناوين المبالغ ببطاقة مجاميع نموذج الفاتورة
///   (كل مبلغ بعنوانه والإجمالي بأبرز دور مطبعي وبعملة برمزها) ومعاينات
///   «تعادل» بالأساسية في الفاتورة والسند بحساب المجال ذاته — وبعملة
///   الأساس لا معاينة (س-159/D-157 بنفس العرف).
/// - **م02 اختصارات المدى**: رقائق الملء السريع بأشرطة من/إلى — تملأ
///   الحقلين حصراً وزر «عرض» القائم هو الفعّال (عرف D-077 باقٍ حرفاً).
/// - **م03 رسائل الخطأ بلغة المستخدم**: لا رموز DQ داخل جُمل الرسائل
///   الوجهية — الرمز للسجل والمرجع، وعقد dqTag اللاحق س107 باقٍ حرفاً.
///
/// الحد الصادق للدفعة: التحويلات والتسويات بلا معاينة تعادل (لا لقطة
/// صرف بصيغتهما القائمة)، واليومية والحركة والأرشيف بأسلاك الاختصارات
/// ذاتها المختبرة هنا على السندات والدخل واليومية.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('م02: تواريخ الاختصارات النقية', () {
    test('الأربع بلسانها من يوم مرجعي مثبت — مارس 2026', () {
      final today = DateTime(2026, 3, 15);
      expect(diqqahRangeShortcutDates(DiqqahRangePreset.today, today: today),
          ('2026-03-15', '2026-03-15'));
      expect(
          diqqahRangeShortcutDates(DiqqahRangePreset.thisMonth,
              today: today),
          ('2026-03-01', '2026-03-15'));
      expect(
          diqqahRangeShortcutDates(DiqqahRangePreset.lastMonth,
              today: today),
          ('2026-02-01', '2026-02-28'));
      expect(
          diqqahRangeShortcutDates(DiqqahRangePreset.thisYear, today: today),
          ('2026-01-01', '2026-03-15'));
    });

    test('فبراير الكبيسة وحدّ السنة — لا حساب شهور يدوي', () {
      final leap = diqqahRangeShortcutDates(DiqqahRangePreset.lastMonth,
          today: DateTime(2024, 3, 10));
      expect(leap, ('2024-02-01', '2024-02-29'));
      final boundary = diqqahRangeShortcutDates(DiqqahRangePreset.lastMonth,
          today: DateTime(2026, 1, 5));
      expect(boundary, ('2025-12-01', '2025-12-31'));
    });
  });

  testWidgets('س235: أزرار السندات الخمسة تملأ من/إلى وتطبق '
      'فوراً — بلا زر عرض', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('هذا الشهر'), findsOneWidget);

    await tester.tap(find.text('هذا الشهر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final expected = diqqahRangeShortcutDates(DiqqahRangePreset.thisMonth);
    final from = tester
        .widget<TextField>(
            find.widgetWithText(TextField, 'من (YYYY-MM-DD)'))
        .controller!
        .text;
    final to = tester
        .widget<TextField>(
            find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'))
        .controller!
        .text;
    expect(from, expected.$1, reason: 'الملء بصيغة المنتقي ذاتها (س182)');
    expect(to, expected.$2);
    // س235: التطبيق فوري — القائمة تعاد بمدى الزر فالسند المزروع
    // (آذار) خارج هذا الشهر (تشرين الثاني) فلا يظهر.
    expect(find.textContaining('سند قبض 26000001'), findsNothing,
        reason: 'الزر يطبق لحظته: قائمة الشهر الحالي لا سند آذار فيه');
  });

  testWidgets('س235: قائمة الدخل بأزرارها — «هذا العام» يملأ من أول '
      'السنة إلى اليوم ويطبق فوراً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(
        MaterialApp(home: IncomeStatementView(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('هذا العام'), findsOneWidget);
    await tester.tap(find.text('هذا العام'));
    await tester.pump();

    final expected = diqqahRangeShortcutDates(DiqqahRangePreset.thisYear);
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'من (YYYY-MM-DD)'))
          .controller!
          .text,
      expected.$1,
    );
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'))
          .controller!
          .text,
      expected.$2,
    );
  });

  testWidgets('س235: دفتر اليومية من قائمة التقارير بأزراره — '
      '«اليوم» يملأ الحقلين بيوم واحد ويطبق فوراً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // س205 م09: القائمة أعيد تنظيمها بأقسامها — «دفتر اليومية» بقسم
    // الدفاتر والمطابقة بأوله فظاهر دون سحبة (والسحبة القديمة كانت
    // لإظهار البند بنهاية القائمة قبل التنظيم).
    await tester.tap(find.text('دفتر اليومية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('اليوم'), findsOneWidget);
    await tester.tap(find.text('اليوم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final expected = diqqahRangeShortcutDates(DiqqahRangePreset.today);
    // س235: حقلا الشريط الموحد بوسميه الموحدين (وسما اليومية القديمان
    // رُفعا مع صف الحقول القديم).
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'من (YYYY-MM-DD)'))
          .controller!
          .text,
      expected.$1,
    );
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'))
          .controller!
          .text,
      expected.$2,
    );
  });

  testWidgets('م01: بطاقة المجاميع بمبالغها المعنونة وبعملة الأساس — '
      'ولا معاينة تعادل بعملة الأساس (س-159 بنفس العرف)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final unitId = await db.insertUnit(name: 'قطعة');
    await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 25000,
        salePriceMinor: 40000,
        priceCurrencyId: 1);

    await tester
        .pumpWidget(MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // بطاقة المجاميع كسول البناء داخل ListView — الوصول بالتمرير
    // (نمط D-098/س184: الوصول بالتمرير لا الافتراض).
    await tester.scrollUntilVisible(
      find.text('الإجمالي'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));

    // عناوين المبالغ الثلاثة ظاهرة كلٌّ بعنوانه (س204 — م01)
    expect(find.text('المجموع'), findsOneWidget);
    expect(find.text('الخصم'), findsOneWidget);
    expect(find.text('الإجمالي'), findsOneWidget);
    // والعملة برمزها المعتمد (س50/6: بالأساسية ل.س مباشرة)
    expect(find.textContaining('ل.س'), findsWidgets);
    // وبعملة الأساس لا معاينة تعادل — المكافئ = المبلغ
    expect(find.textContaining('بالأساسية'), findsNothing);
  });

  testWidgets('م01: بعملة غير الأساسية معاينة التعادل بالأساسية — '
      'بقيمة totalBaseMinor من المجال ذاته لا إعادة حساب',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final usdId = (await db.customSelect(
            "SELECT id FROM currencies WHERE code = 'USD'")
        .getSingle()).data['id'] as int;
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    // سعر اليوم الواحد (F-121: اليوم بلا سجل ثانٍ)
    await db.exchangeRateRecord(
        currencyId: usdId,
        date: '$year-03-01',
        rateToBase: 15000000);

    await tester
        .pumpWidget(MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>,
        'عملة المستند'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('USD').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(
      find.textContaining('بالأساسية'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));

    // الإجمالي صفر والمعاينة ظاهرة بعملة الأساسية برمزها المعتمد
    // (س50/6: الدولار برمزه $) — والقيمة من المجال المحسوبة
    expect(find.textContaining('تعادل'), findsOneWidget);
    expect(find.textContaining('بالأساسية'), findsOneWidget);
    // ورمز عملة المستند دولار على القيم
    expect(find.textContaining(r'$'), findsWidgets);
  });

  testWidgets('م01: نموذج السند بصندوق دولار يعاين تعادل المبلغ '
      'بالأساسية لحظة الكتابة — بالحساب المجالي بلقطة السند',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final usdId = (await db.customSelect(
            "SELECT id FROM currencies WHERE code = 'USD'")
        .getSingle()).data['id'] as int;
    final usdBoxId = await db.createCashBox(
        name: 'صندوق الدولار', currencyId: usdId);
    expect(usdBoxId, greaterThan(0));
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    await db.exchangeRateRecord(
        currencyId: usdId,
        date: '$year-03-01',
        rateToBase: 15000000);

    await tester
        .pumpWidget(MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // منسدل الصندوق — الوصول بالتمرير (درس الجولة #376) وفتحه بضغطة
    // على الحقل كله لا على لسانه العائم: ضغطة اللسان تصيب زخرفة الحقل
    // فلا يفتح المنسدل (نمط «عملة المستند» أعلاه — درس #399).
    final fundField = find.widgetWithText(
        DropdownButtonFormField<int>, 'الصندوق — وعمله سند العملة');
    await tester.scrollUntilVisible(
      fundField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(fundField);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // عنصر القائمة من الـoverlay حصراً بنوعه الحامل <int> (درس س93:
    // فلا يتقاطع مع ما خلفه بالشجرة) — وbyType بمطابقة النوع الفعلي
    // فDropdownMenuItem المجرد <dynamic> لا يطابق DropdownMenuItem<int>
    // أبداً (علّة الجولة #399 الموثقة).
    await tester.tap(find.descendant(
        of: find.byType(DropdownMenuItem<int>),
        matching: find.textContaining('صندوق الدولار')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // لقطة الصرف تعبأت من آخر سعر مسجل (F-121/D-194) — فالعين
    // على المبلغ بعد استقرار التعبئة
    await tester.enterText(
        find.widgetWithText(TextField, 'المبلغ بوحدة صغرى'), '1000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1000 وحدة صغرى دولار × 15 = 15,000 وحدة صغرى ليرة — بالمحرك
    // convertToBaseMinor ذاته (fxRateScale=1,000,000) — و«لحظة
    // الكتابة» بعلة الجولة #401 المصلحة: حقل المبلغ بنبض
    // onChanged → setState فالكتابة تعيد البناء فتُرى المعاينة.
    expect(find.textContaining('تعادل 15,000'), findsOneWidget);
    expect(find.textContaining('ل.س بالأساسية'), findsOneWidget);
  });

  group('م03: رسائل الخطأ بلغة المستخدم', () {
    test('لسان أخطاء الطلبات خالٍ من رموز DQ — الرمز للسجل والمرجع',
        () {
      final closeMsg = orderValidationErrorText(const OrderCloseIncomplete());
      expect(closeMsg, isNot(contains('DQ-')));
      expect(closeMsg, contains('حوّل المتبقي لفاتورة أولاً'));
      final frozenMsg = orderValidationErrorText(const OrderFrozen());
      expect(frozenMsg, isNot(contains('DQ-')));
      expect(frozenMsg, contains('التصحيح بالإلغاء وإعادة الأمر'));
    });
  });
}
