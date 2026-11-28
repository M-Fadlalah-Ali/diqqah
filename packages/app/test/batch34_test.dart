import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/currencies_screen.dart';
import 'package:diqqah_app/reports_screen.dart';
import 'package:diqqah_app/settings_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 34 — تعدد العملات الفعلي (F-120/F-121/F-124،
/// D-194): شاشة العملات وأسعار الصرف بمدققات المجال، وبند الإعدادات
/// الظاهر (درس D-098)، وبند تقرير مراكز العملات بشاشته وزرَي
/// التصدير (F-166).
///
/// نمط القاعدة `inMemorySyncClose` وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق)، والقائمة الكسولة تُسحَب قبل أي فحص لبند
/// بنهايتها (درس س35/س36).
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('الدفعة 34: شاشة العملات تعرض المزروعتين وتضيف عملة '
      'جديدة وتسجلاً سعرياً بقائمة الأسعار المجمدة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: CurrenciesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // المزروعتان من م1 (D-070) بالأساسية موسومة.
    expect(find.textContaining('SYP — ليرة سورية'), findsOneWidget);
    expect(find.textContaining('(الأساسية)'), findsOneWidget);
    expect(find.textContaining('USD — دولار أمريكي'), findsOneWidget);

    // إضافة عملة جديدة من الكتالوج — بحث إنجليزي ثم انتقاء والتعبئة
    // التلقائية (س146/D-209): لا حقول يدوية للكود والاسم أصلاً.
    await tester.tap(find.text('إضافة عملة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.widgetWithText(
          TextField, 'ابحث بالكود أو بالاسم (عربي/إنجليزي)'),
      'euro',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('EUR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // الخانات معبأة باقتراح ISO (2) — الإضافة مباشرة بلا كتابة يدوية.
    await tester.tap(find.text('إضافة').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('أُضيفت العملة EUR — يورو'), findsOneWidget);
    expect(find.text('EUR — يورو'), findsOneWidget);

    // قسم الأسعار أسفل القائمة المتنامية — سحبٌ هادئة حتى الظهور
    // (السرد الكسول لا يبني البعيد: درس س35/س36 الموثق).
    var rateCardSeen = false;
    for (var i = 0; i < 8 && !rateCardSeen; i++) {
      final label =
          find.text('العملة (غير الأساسية)');
      rateCardSeen = label.evaluate().isNotEmpty;
      if (!rateCardSeen) {
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    expect(rateCardSeen, isTrue, reason: 'بطاقة الأسعار ظاهرة');

    // تسجيل سعر دولاري: ensureVisible قبل النقر (درس س78 الموثق)،
    // وعنصر القائمة من الـoverlay حصراً بDescendant
    // (DropdownMenuItem لا يكون خارج القائمة المفتوحة قبل الاختيار).
    await tester.ensureVisible(
        find.widgetWithText(DropdownButtonFormField<int>,
            'العملة (غير الأساسية)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
        find.widgetWithText(DropdownButtonFormField<int>,
            'العملة (غير الأساسية)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final menuItems = find.descendant(
      of: find.byType(DropdownMenuItem<int>),
      matching: find.text('USD — دولار أمريكي'),
    );
    expect(menuItems, findsOneWidget,
        reason: 'قائمة الاختيار مفتوحة بعنصر الدولار');
    await tester.tap(menuItems);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    var rateFieldSeen = false;
    for (var i = 0; i < 6 && !rateFieldSeen; i++) {
      final field = find.widgetWithText(TextField,
          'السعر');
      rateFieldSeen = field.evaluate().isNotEmpty;
      if (!rateFieldSeen) {
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    expect(rateFieldSeen, isTrue);
    await tester.enterText(
      find.widgetWithText(TextField,
          'السعر'),
      '15000000',
    );
    var saveSeen = false;
    for (var i = 0; i < 6 && !saveSeen; i++) {
      final button = find.text('تسجيل السعر');
      saveSeen = button.evaluate().isNotEmpty;
      if (!saveSeen) {
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    await tester.tap(find.text('تسجيل السعر'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // الحكم من القاعدة ذاتها: السجل محفوظ يومه والقائمة المجمدة
    // (بطاقة النجاح أعلى القائمة الممرّرة للأسفل فغير مبنيّة بالكسول).
    final rates = await db.exchangeRatesOf(2);
    expect(rates, hasLength(1));
    expect(rates.first.rateToBase, 15000000);
    expect(rates.first.date, todayIsoDate());
    // والسجل المعروض بحقيقته: 15 لكل دولار (بنهاية القائمة مبنيّة).
    expect(find.text('15 لكل 1 من العملة'), findsOneWidget);
  });

  testWidgets('الدفعة 34: بند الإعدادات «العملات وأسعار الصرف» ظاهر '
      'ويفتح شاشتها (درس D-098)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah_batch34/dummy.db',
        onRestored: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // بند الدفعة بعد بطاقات الإعدادات القائمة — سحبٌ هادئة تكشفه
    // (السرد الكسول لا يبني البعيد). وس164: بطاقة «مسودات البيع»
    // بخياريها (الحجز ومسودة فوق المتاح) طلّت القائمة أكثر فميزانية
    // السحب 8→14 — والحرس باقٍ: البند بلسان الوصول بالتمرير لا
    // مدفون بشاشة أخرى (D-098).
    var found = false;
    for (var i = 0; i < 14 && !found; i++) {
      final matcher = find.text('العملات وأسعار الصرف');
      found = matcher.evaluate().isNotEmpty;
      if (!found) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    expect(found, isTrue, reason: 'البند ظاهر لا مدفون');

    // س233: درس السرد الكسول الثاني — الموجود بنطاق الكاش قد يكون خارج
    // الشاشة فلا يتلقى الضغطة؛ الإظهار قبل الضغط (عرف D-098).
    await tester.ensureVisible(find.text('العملات وأسعار الصرف'));
    await tester.pump();
    await tester.tap(find.text('العملات وأسعار الصرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('العملات وأسعار الصرف'), findsWidgets,
        reason: 'الشاشة فُتحت بعنوانها');
    expect(find.text('إضافة عملة'), findsOneWidget);
  });

  testWidgets('الدفعة 34: بند «مراكز العملات» بقائمة التقارير يفتح '
      'شاشته بصفوف المزروعين وزرَي الطباعة والتصدير (F-166)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // البند بنهاية القائمة — سحب حتى الظهور (نمط الدفعة 31).
    var found = false;
    for (var i = 0; i < 8 && !found; i++) {
      final matcher = find.text('مراكز العملات');
      found = matcher.evaluate().isNotEmpty;
      if (!found) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    expect(found, isTrue);

    await tester.tap(find.text('مراكز العملات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // صفوف العملتين المزروعتين بأرقامها الصفرية المخزنة وأزرار
    // التصدير والطباعة (لا تقرير بلا زر CSV).
    expect(find.textContaining('SYP — ليرة سورية'), findsOneWidget);
    expect(find.textContaining('USD — دولار أمريكي'), findsOneWidget);
    expect(find.text('تصدير CSV'), findsOneWidget);
    expect(find.text('طباعة / PDF'), findsOneWidget);
  });
}
