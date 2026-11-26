import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/home_screen.dart';
import 'package:diqqah_app/items_screen.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/settings_screen.dart';
import 'package:diqqah_app/backup_center.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// س198 — دفعة الصقل م12..م17 من تقرير فحص الواجهات وفق M3
/// (بأمر المالك «تابع في م12 م13 م14 م15 م16 م17»):
///
/// - م12: لافتة واحدة للأعلى أولوية والبقية خلف مدخل التنبيهات بشارة
///   عدد — الأولوية نقيّة تُختبر بـhomeAlerts واللابتة الواحدة بحية
///   الرئيسية.
/// - م13: بحث الأصناف على نمط العائلة الممتلئة بعنوان دائم لا إطار
///   محدد ولا نص إرشادي وحيد.
/// - م14: المحاذاة كلها على العائلة الاتجاهية لا الفيزيائية —
///   بنماذج الفواتير والسندات والتفاصيل.
/// - م15: منسدل «أساس العد» بعنوانه الدائم (DropdownButtonFormField).
/// - م16: خيارات قائمة الأصناف سطران بنيويان بلا قص، والحقل المغلق
///   بسطره المركب س-108 كما جرت جولات CI.
/// - م17: بطاقات الإعدادات الثلاث سطر تلخيص + كشف تدريجي «كيف يعمل؟»
///   والتفصيل كامل حرفاً خلفه.
///
/// ضخّات محدودة لا pumpAndSettle إلا عند الحوار (درس س22..س26).
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  Future<BuildContext?> ctxOf(WidgetTester tester) async {
    BuildContext? captured;
    // درس الجولة #376: pumpWidget وpump محراستان فلا تُناديان بلا
    // await وإن كان المساعد دالة عادية — فصار المساعد بذاته async.
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        captured = c;
        return const SizedBox.shrink();
      }),
    ));
    await tester.pump();
    return captured;
  }

  group('م12: قائمة تنبيهات الرئيسية بأولويتها (نقي)', () {
    testWidgets('الترتيب: فشل النسخ ثم الخرق ثم التحذيرات الوقائية — '
        'والمتابعات أُزيلت بعقد س221 (نبض العمل مصدره الواحد)', (tester) async {
      final ctx = await ctxOf(tester);
      expect(ctx, isNotNull);
      final h = BackupHealth(
        failureMessage: 'علّة تجريبية موثقة',
        noBackupFor30Days: true,
        attachmentsStale: true,
        computedAtUtc: DateTime.utc(2026, 11, 20),
      );
      expect(h.hasFailure, isTrue);
      final alerts = homeAlerts(
        context: ctx!,
        health: h,
        violationsCount: 2,
      );
      expect(alerts, hasLength(4),
          reason: 'س221: بند المتابعات أُزيل بقرار المالك');
      expect(alerts[0].message, contains('فشل النسخ الاحتياطي'));
      expect(alerts[0].priority, 0);
      expect(alerts[0].actionLabel, 'التفاصيل');
      expect(alerts[1].message, contains('الفحص الافتتاحي وجد 2'));
      expect(alerts[1].priority, 1);
      expect(alerts[1].actionLabel, 'إغلاق');
      expect(alerts[2].message, contains('لم تُنشأ نسخة احتياطية منذ 30 يوماً'));
      expect(alerts[2].priority, 3);
      expect(alerts[2].actionLabel, 'نسخ الآن');
      expect(alerts[3].message, contains('صور الأصناف تغيرت'));
      expect(alerts[3].priority, 3);
      expect(alerts[3].actionLabel, 'نسخ');
      for (var i = 1; i < alerts.length; i++) {
        expect(alerts[i].priority, greaterThanOrEqualTo(alerts[i - 1].priority),
            reason: 'الأولويات لا تتراجع');
      }
    });

    testWidgets('الفراغ الهادئ بلا مدخل تنبيهات — ولا بند متابعات '
        'بعقد س221 (نبض العمل مصدره الواحد)', (tester) async {
      final ctx = (await ctxOf(tester))!;
      expect(homeAlerts(context: ctx), isEmpty,
          reason: 'بلا مصادر لا تنبيهات — الصمت الهادئ عرف س198');
    });

    testWidgets('س221: المتابعات وحدها لا تُظهر لافتة — نبض العمل هو '
        'المصدر الواحد وبطاقة الأصناف ظاهرة بالوجود', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final unitId = await db.insertUnit(name: 'قطعة');
      await db.insertItem(
        sku: 'M-1',
        name: 'صنف تحت الحد',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 0,
        priceCurrencyId: 1,
        minQty: 5,
      );
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(db: db, dbPath: ':memory:', onRestored: () {}),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // س221: بند المتابعات أُزيل من اللافتات بقرار المالك فلا لافتة
      // ولا كومة — والنبض هو المصدر الواحد بالوجود لا بالوعد.
      expect(find.textContaining('متابعة تحتاج انتباهك'), findsNothing,
          reason: 'س221: بند اللافتة أُزيل فلا لسان متكرر');
      expect(find.byType(MaterialBanner), findsNothing,
          reason: 'بلا مصادر نسخ ولا خرق فلا لافتة أصلاً');
      expect(find.text('نبض العمل'), findsOneWidget,
          reason: 'المصدر الواحد: بطاقة النبض بالوجود');
      expect(find.text('أصناف تحت الحد الأدنى'), findsOneWidget);
      expect(find.text('متابعات نشطة'), findsOneWidget);
    });
  });

  group('م13: بحث الأصناف على نمط العائلة الممتلئة', () {
    testWidgets('عنوان دائم بأيقونة البحث وبلا إطار محدد',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final unitId = await db.insertUnit(name: 'قطعة');
      await db.insertItem(
        sku: 'S-1',
        name: 'صنف الفحص',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1,
      );
      await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final field = find.byWidgetPredicate(
          (w) => w is TextField &&
              w.decoration?.labelText == 'بحث بالاسم أو الكود أو التصنيف');
      expect(field, findsOneWidget,
          reason: 'م13: عنوان دائم لا نص إرشادي وحيد');
      final tf = tester.widget<TextField>(field);
      expect(tf.decoration!.border, isNot(isA<OutlineInputBorder>()),
          reason: 'م13: على النمط الممتلئ الافتراضي لا الإطار المحدد');
      expect(tf.decoration!.prefixIcon, isNotNull,
          reason: 'أيقونة البحث المسبقة باقية');
    });
  });

  group('م14: المحاذاة الاتجاهية لا الفيزيائية', () {
    Future<DiqqahDatabase> _seedInvoice(WidgetTester tester) async {
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
        priceCurrencyId: 1,
      );
      await db.insertItem(
        sku: 'P-1',
        name: 'صنف بلا مجموعة',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1,
      );
      await db.insertParty(
          number: '0001',
          name: 'مورد الشرق',
          kind: 'supplier',
          defaultCurrencyId: 1);
      return db;
    }

    testWidgets('زر «إضافة بند» بنموذج الفاتورة على بداية السطر '
        'الاتجاهية لا اليسار الفيزيائي', (tester) async {
      final db = await _seedInvoice(tester);
      await tester.pumpWidget(
          MaterialApp(home: InvoiceEditScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // درس الجولة #376: جسم النموذج ListView كسول — «إضافة بند»
      // بعد البطاقة قد يكون خارج مدى البناء فلا يُجدى finder بلا سحب
      // (نمط D-098/س184: الوصول بالتمرير لا الافتراض).
      await tester.scrollUntilVisible(
        find.text('إضافة بند'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      // درس الجولة #381 (أول تشغيل حي للاختبار — كان معتقاً خلف الفيض
      // ب#376 والمحلل ب#377 والبنية ب#378..#381): أقرب Align فوق نص
      // «إضافة بند» ليس غلافنا الاتجاهي بل محاذاة نمط الزر ذاتها —
      // ButtonStyleButton يغلف محتواه داخلياً بـAlign(alignment:
      // Alignment.center) من نمطه الافتراضي فهي أول ما يُصعد إليه —
      // فالأمين الصعود إلى الزر أولاً (بsubtype فالزر _TextButtonWithIcon)
      // ثم أول Align فوقه وهو غلافنا (نمط م15 بذات الملف: byWidgetPredicate).
      final addBtn = find.ancestor(
          of: find.text('إضافة بند'),
          matching: find.byWidgetPredicate((w) => w is TextButton)).first;
      final addAlign = find.ancestor(
          of: addBtn, matching: find.byType(Align)).first;
      expect(tester.widget<Align>(addAlign).alignment,
          AlignmentDirectional.centerStart,
          reason: 'م14: العناصر الثانوية لبداية السطر العربية دومًا');
    });

    testWidgets('كتلة معلومات السطر بعد اختيار الصنف كلها اتجاهية — '
        'وإجمالي السطر من العائلة ذاتها', (tester) async {
      final db = await _seedInvoice(tester);
      await tester.pumpWidget(
          MaterialApp(home: InvoiceEditScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField &&
          w.decoration.labelText == 'الصنف'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Z-100 زيت محلي').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final totalAlign = find.ancestor(
          of: find.textContaining('إجمالي السطر'),
          matching: find.byType(Align)).first;
      expect(tester.widget<Align>(totalAlign).alignment,
          AlignmentDirectional.centerStart,
          reason: 'م14: كتلة السطر الاتجاهية كاملة');
      final unitAlign = find.ancestor(
          of: find.textContaining('الوحدة:'),
          matching: find.byType(Align)).first;
      expect(tester.widget<Align>(unitAlign).alignment,
          AlignmentDirectional.centerStart);
    });
  });

  group('م15: منسدل أساس العد بعنوانه الدائم', () {
    testWidgets('عداد التسليم بتفاصيل الفاتورة بحقل عنوانه «أساس العد»',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      final saleId = (await db.customSelect(
        "SELECT id FROM invoices WHERE kind = 'sale' ORDER BY id LIMIT 1",
      ).getSingle()).data['id'] as int;
      await tester.pumpWidget(MaterialApp(
          home: InvoiceDetailScreen(db: db, invoiceId: saleId)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final basisField = find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField &&
          w.decoration.labelText == 'أساس العد');
      expect(basisField, findsOneWidget,
          reason: 'م15: المنسدل العاري صار حقلاً بعنوان دائم');
      expect(find.text('حسب الكميات'), findsOneWidget,
          reason: 'القيمة الافتراضية الكميات باقية');
    });
  });

  group('م16: خيارات قائمة الأصناف سطران بنيويان بلا قص', () {
    testWidgets('الاسم علوية ومعلوماته سطراً فرعياً — والحقل المغلق '
        'بسطره المركب س-108 كما جرت جولات CI', (tester) async {
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
        priceCurrencyId: 1,
      );
      await db.insertItem(
        sku: 'P-1',
        name: 'صنف بلا مجموعة',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 1000,
        salePriceMinor: 2000,
        priceCurrencyId: 1,
      );
      await db.insertParty(
          number: '0001',
          name: 'مورد الشرق',
          kind: 'supplier',
          defaultCurrencyId: 1);
      await tester.pumpWidget(
          MaterialApp(home: InvoiceEditScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField &&
          w.decoration.labelText == 'الصنف'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // القائمة المفتوحة: العنوان نص مستقل بلا لحاق معلوماته —
      // والسطر الفرعي نص مستقل آخر فلا قص يفقد المتاح أو السعر.
      expect(find.text('Z-100 زيت محلي'), findsOneWidget,
          reason: 'م16: العنوان نصاً مستقلاً بلا لحاق معلوماته');
      expect(find.text('P-1 صنف بلا مجموعة'), findsOneWidget);
      expect(find.textContaining('المتاح'), findsNWidgets(2),
          reason: 'م16: المتاح بسطر فرعي مستقل بلا قص');
      // الاختيار بنمط batch30 القائم — العنوان الحي بالقائمة.
      await tester.tap(find.text('Z-100 زيت محلي'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // الحقل المغلق بسطره المركب بعلامة اللحاق « — » عقد س-108.
      expect(find.textContaining('Z-100 زيت محلي — '), findsOneWidget,
          reason: 'م16: لسان الحقل المغلق س-108 باقٍ حرفاً');
    });
  });

  group('م17: بطاقات الإعدادات سطر تلخيص وكشف تدريجي', () {
    testWidgets('بطاقة النسخ الكامل بلا جلسة: التلخيص ظاهر والتفصيل '
        'خلف «كيف يعمل؟» وحرفاً خلفه ثم يُخفى', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah-m17-full-test.db',
        onRestored: () {},
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // بلا جلسة: بطاقة المجدول محجوبة بصلاحيتها والاستيراد بالمديرية
      // — فكشف بطاقة النسخ الكامل وحدها على المسرح.
      expect(find.text('كيف يعمل؟'), findsOneWidget);
      expect(find.textContaining('يُحفظ في مجلد القاعدة نفسه'), findsNothing,
          reason: 'م17: التفصيل الكثيف خلف التوسعة لا ظاهراً دائماً');
      expect(find.textContaining('ملف واحد للقاعدة كاملة بلاحقة البرنامج'),
          findsOneWidget,
          reason: 'سطر التلخيص ظاهر دائماً');
      await tester.tap(find.text('كيف يعمل؟'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('يُحفظ في مجلد القاعدة نفسه'),
          findsOneWidget,
          reason: 'الحقيقة كاملة خلف التوسعة حرفاً');
      expect(find.text('إخفاء الشرح'), findsOneWidget);
      await tester.tap(find.text('إخفاء الشرح'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('يُحفظ في مجلد القاعدة نفسه'), findsNothing);
    });

    testWidgets('بطاقة النسخ المجدول بجلسة مدير: دوريات النسخ وشروطها '
        'كلها خلف توسعتها', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final managerId = await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 'test-hash');
      await db.setCurrentUserId(managerId);
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah-m17-sched-test.db',
        onRestored: () {},
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final schedCard = find.ancestor(
          of: find.textContaining('النسخ الاحتياطي المجدول'),
          matching: find.byType(Card)).first;
      // س213 (D-218): البطاقة تحت أول نافذة البناء بعد إعادة التنظيم —
      // سحب حتى البناء فتأكيد وصول بنمط D-098 قبل الفحص والنقر.
      var schedShown = false;
      for (var i = 0; i < 30 && !schedShown; i++) {
        schedShown =
            find.textContaining('النسخ الاحتياطي المجدول').evaluate().isNotEmpty;
        if (!schedShown) {
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await tester.pump();
        }
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('النسخ الاحتياطي المجدول'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: schedCard, matching: find.text('كيف يعمل؟')),
          findsOneWidget);
      expect(find.textContaining('ساعية كل ساعة عمل'), findsNothing,
          reason: 'م17: فقرة الدوريات خلف التوسعة لا فوق الأفعال');
      await tester.tap(
          find.descendant(of: schedCard, matching: find.text('كيف يعمل؟')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('ساعية كل ساعة عمل'), findsOneWidget,
          reason: 'التفصيل كامل حرفاً خلف التوسعة');
    });

    testWidgets('بطاقة الاستيراد بجلسة مدير: شروط المعاملة خلف توسعتها '
        'بلسان الوصول بالتمرير (درس D-098)', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final managerId = await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 'test-hash');
      await db.setCurrentUserId(managerId);
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah-m17-import-test.db',
        onRestored: () {},
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // السرد الكسول: بطاقة الاستيراد أسفل بطاقة المجدول الطويلة —
      // سحب حتى كشفها بنمط batch34 المجرَّب.
      var found = false;
      // س213 (D-218): بطاقة الاستيراد انتقلت إلى قسم «العمليات»
      // قرب آخر القائمة — حلقة أعمق بنمط D-098.
      for (var i = 0; i < 30 && !found; i++) {
        found = find.text('استيراد البيانات').evaluate().isNotEmpty;
        if (!found) {
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
      expect(found, isTrue, reason: 'بطاقة الاستيراد كشفت بالسحب');
      // درس الجولة #376: كشف العنوان لا يعني أن الزر داخل نافذة
      // الاختبار — قياس مستطيل الزر وسحب مقيس حتى يدخل النافذة ثم
      // النقر بمنتصفه (نمط س196: النقر خارجها يبتلع بلا تحذير).
      final importButton = find.descendant(
          of: find.ancestor(
              of: find.text('استيراد البيانات'),
              matching: find.byType(Card)),
          matching: find.text('كيف يعمل؟'));
      var tappable = false;
      for (var i = 0; i < 10 && !tappable; i++) {
        if (importButton.evaluate().isNotEmpty) {
          final rect = tester.getRect(importButton);
          tappable = rect.center.dy < 560;
        }
        if (!tappable) {
          await tester.drag(find.byType(ListView), const Offset(0, -200));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
      expect(tappable, isTrue,
          reason: 'زر التوسعة داخل نافذة الاختبار قبل النقر');
      expect(find.textContaining('كل-أو-لا شيء'), findsNothing,
          reason: 'م17: شروط المعاملة خلف التوسعة لا ظاهرة دائماً');
      await tester.tap(importButton, warnIfMissed: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // والتفصيل الموسع أسفل النافذة بكسل القائمة — سحب حتى يُبنى
      // (نمط batch34 المجرّب) ثم الحكم عليه.
      var detailed = false;
      for (var i = 0; i < 10 && !detailed; i++) {
        detailed =
            find.textContaining('كل-أو-لا شيء').evaluate().isNotEmpty;
        if (!detailed) {
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
      expect(detailed, isTrue, reason: 'التفصيل كامل خلف التوسعة');
    });
  });
}
