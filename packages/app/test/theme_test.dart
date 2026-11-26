import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/app_theme.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/settings_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';
import 'test_guard.dart';

/// س182 (م05/م02 — بأمر المالك): اختبارات نظام الألوان نهاري/ليلي/نظامي
/// بالألوان الستة المعتمدة، وبطاقة المظهر بالإعدادات، وزر التقويم
/// الطرفي لحقول التاريخ.
///
/// س186 (بقية م05): اختبارات الأزقة الدلالية السبعة — اشتقاقها من
/// الأدوار الثلاثة المعتمدة، وتباين WCAG 4.5:1 بالوضعين، وخريطة أنواع
/// الفواتير (الأصل معبأ والمردود مخطط)، والسقوط الآمن بلا طبقة.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('س182 (م05): طبقة الثيم — الألوان الستة والخلفيتان والترجمة', () {
    test('الثيم النهاري: الأدوار الثلاثة المعتمدة فوق خلفية بيضاء', () {
      final light = buildLightTheme('Sahel');
      expect(light.scaffoldBackgroundColor, kLightBackground);
      expect(light.colorScheme.primary, kLightIdentityBrown);
      expect(light.colorScheme.error, kLightRed);
      expect(light.colorScheme.secondary, kLightBlue);
      // س203: البني للهوية حصراً بأمر المالك «البني للهوية فقط لا غير»
      expect(kLightIdentityBrown, const Color(0xFF8B5A3C));
      // القيم الحرفية بلسان المالك — لا اجتهاد فوق اعتماده
      expect(kLightBackground, const Color(0xFFFFFFFF));
      expect(kLightGreen, const Color(0xFF21452C));
      expect(kLightRed, const Color(0xFF781C1C));
      expect(kLightBlue, const Color(0xFF1F4061));
    });

    test('الثيم الليلي: الأدوار الثلاثة المعتمدة فوق الخلفية الداكنة', () {
      final dark = buildDarkTheme('Sahel');
      expect(dark.scaffoldBackgroundColor, kDarkBackground);
      expect(dark.colorScheme.primary, kDarkIdentityBrown);
      expect(dark.colorScheme.error, kDarkRed);
      expect(dark.colorScheme.secondary, kDarkBlue);
      // س203: قرين الليل للهوية البنية
      expect(kDarkIdentityBrown, const Color(0xFFD4A57E));
      expect(kDarkBackground, const Color(0xFF1E1E1E));
      expect(kDarkGreen, const Color(0xFF8ACCA1));
      expect(kDarkRed, const Color(0xFFEDB0B0));
      expect(kDarkBlue, const Color(0xFFA2C2E2));
    });

    test('ترجمة مفاتيح الوضع — والغريب يعيد «نظام» بلا استثناء', () {
      expect(themeModeOf(kThemeModeSystem), ThemeMode.system);
      expect(themeModeOf(kThemeModeLight), ThemeMode.light);
      expect(themeModeOf(kThemeModeDark), ThemeMode.dark);
      expect(themeModeOf('قيمة غريبة'), ThemeMode.system);
      // الافتراضي «نظام» — يتبع الجهاز بلا فرض
      expect(appThemeMode.value, kThemeModeSystem);
    });
  });

  group('س182 (م05): بطاقة المظهر بالإعدادات', () {
    testWidgets('ثلاثة أوضاع ظاهرة والتبديل إلى الليلي فوري بلا إقلاع',
        (tester) async {
      appThemeMode.value = kThemeModeSystem;
      addTearDown(() => appThemeMode.value = kThemeModeSystem);

      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      // س191: تنقّل حتمي بلا نقرة الرئيسية — دفع مسار الإعدادات عبر
      // الـNavigator الحي مباشرة: هشاشة نقر البلاطة عقب السحب موثقة
      // بالجولات #365..#368 (يفتح تارة ويُبتلع تارة بلا تحذير) ومقصد
      // هذا الاختبار بطاقةُ المظهر ذاتها لا بوابة البلاطة (وبوابات
      // البلاطات محكومة بواجهة الشامل).
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(
            db: db,
            dbPath: ':memory:',
            onRestored: () {},
          )));
      await tester.pumpAndSettle();

      // س194 (الجذر النهائي بإحصاء س192 الحي): قائمة الإعدادات كسولة
      // البناء (SliverChildListDelegate) فبطاقة المظهر لا تُبنى حتى
      // يقرب التمرير منها — وensureVisible يشترط الوجود أولاً فلا
      // يصلح هنا أصلاً — وscrollUntilVisible يسحب حتى يبني الكسول
      // ويكشفه. والسكرولable الأول هنا قائمة الإعدادات ذاتها لأن
      // الرئيسية خلف مسار معتم صارت خلف الكواليس.
      await tester.scrollUntilVisible(
        find.text('المظهر'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('نهاري'), findsOneWidget);
      expect(find.text('ليلي'), findsOneWidget);
      expect(appThemeMode.value, kThemeModeSystem);
      expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.system,
          reason: 'الوضع الافتراضي «نظام» يتبع الجهاز');

      // التبديل إلى الليلي — فوري: المُنبِّه يعيد بناء الجذر لا إقلاع.
      // س196: كشف بالسحب (يبني الكسول) ثم النقر عند منتصف الجزء المرئي
      // من الخيار لا عند مركزه المطلق — فسحب الكشف يوقف عند أول تقاطع
      // ومركزه قد يبقى تحت الحافة (درس #365) — وأي سحب إضافي عمىً يقذف
      // أو يمزق الكسول (درسا #372 و#373) — فلا سحب إلا لحاجة مرئية
      // مقيسة بحلقة صغيرة الاتجاهين.
      await tester.scrollUntilVisible(
        find.text('ليلي'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      var optionRect = tester.getRect(find.text('ليلي'));
      var nudges = 0;
      while ((optionRect.bottom <= 8 || optionRect.top >= 592) &&
          nudges < 4) {
        final dy = optionRect.top >= 592 ? -120.0 : 120.0;
        await tester.timedDrag(find.byType(Scrollable).first,
            Offset(0, dy), const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        optionRect = tester.getRect(find.text('ليلي'));
        nudges++;
      }
      final visibleTop = math.max(optionRect.top, 4.0);
      final visibleBottom = math.min(optionRect.bottom, 596.0);
      await tester.tapAt(Offset(
          optionRect.center.dx, (visibleTop + visibleBottom) / 2));
      await tester.pump();
      expect(appThemeMode.value, kThemeModeDark);
      expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark,
          reason: 'س182: التبديل فوري بلا إقلاع جديد');
      expect(
          tester
              .widget<MaterialApp>(find.byType(MaterialApp))
              .darkTheme!
              .scaffoldBackgroundColor,
          const Color(0xFF1E1E1E),
          reason: 'خلفية الليل المعتمدة بلسان المالك');
    });
  });

  group('س182 (م02): منتقي التاريخ بحقول التاريخ', () {
    testWidgets('شريط مدى السندات يحمل زر التقويم لكل حقل تاريخ',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      // فتح السندات من شبكة الهيكلية (س182: بلاطة لا بند قائمة)
      await tester.scrollUntilVisible(
        find.text('السندات'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // س190: تسوية قبل النقر — ذات الهشاشة الموثقة أعلاه.
      await tester.pumpAndSettle();
      await tester.tap(find.text('السندات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(VouchersScreen), findsOneWidget);

      // حقلا «من/إلى» بشريط المدى الموحد — زرا تقويم طرفيان (م02)
      expect(find.byIcon(Icons.edit_calendar_outlined), findsNWidgets(2),
          reason: 'س182: كل حقل تاريخ يحمل زر التقويم — والكتابة اليدوية '
              'خيار ثانٍ باقٍ');
    });
  });

  group('س186 (بقية م05): الأزقة الدلالية السبعة', () {
    // قنوات اللون بالصيغة غير المتقادمة (درس س126: المعلومات قاتلة
    // بالمحلل — والتوصية الحرفية (*.r * 255.0).round().clamp(0, 255)).
    int chR(Color c) => (c.r * 255.0).round().clamp(0, 255);
    int chG(Color c) => (c.g * 255.0).round().clamp(0, 255);
    int chB(Color c) => (c.b * 255.0).round().clamp(0, 255);

    // تباين WCAG النسبي بين لونين — عقد الأزقة حدُّه 4.5:1.
    double luminanceOf(Color c) {
      double f(int v) {
        final s = v / 255.0;
        return s <= 0.03928
            ? s / 12.92
            : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * f(chR(c)) + 0.7152 * f(chG(c)) + 0.0722 * f(chB(c));
    }

    double contrastOf(Color a, Color b) {
      final la = luminanceOf(a);
      final lb = luminanceOf(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    test('الأدوار الثلاثة زوقٌ بإيجابي وسلبي وانتباه — بألوان المالك حرفاً',
        () {
      final light = buildLightTheme('Sahel').extension<DiqqahLanes>()!;
      expect(light.positive.fg, kLightGreen);
      expect(light.negative.fg, kLightRed);
      expect(light.attention.fg, kLightBlue);
      final dark = buildDarkTheme('Sahel').extension<DiqqahLanes>()!;
      expect(dark.positive.fg, kDarkGreen);
      expect(dark.negative.fg, kDarkRed);
      expect(dark.attention.fg, kDarkBlue);
    });

    test('تعبئة الزوق صبغة 10% من الدور فوق الخلفية — والحد أقوى 34%', () {
      final light = buildLightTheme('Sahel').extension<DiqqahLanes>()!;
      final lightBg = light.positive.bg;
      // النهار: التعبئة أفتح من الدور الغامق (صبغة فوق أبيض)
      expect(chR(lightBg), greaterThan(chR(kLightGreen)));
      expect(chB(lightBg), greaterThan(chB(kLightGreen)));
      expect(chB(light.positive.border), lessThan(chB(lightBg)));
      final dark = buildDarkTheme('Sahel').extension<DiqqahLanes>()!;
      final darkBg = dark.positive.bg;
      // الليل: التعبئة أدكن من الخلفية قليلاً (صبغة فوق داكن)
      expect(chR(darkBg), greaterThan(chR(kDarkBackground)));
      expect(chG(darkBg), greaterThan(chG(kDarkBackground)));
      expect(chB(darkBg), greaterThan(chB(kDarkBackground)));
    });

    test('تباين نص كل زوق معبأ فوق تعبئته ≥ 4.5:1 بالوضعين', () {
      final light = buildLightTheme('Sahel').extension<DiqqahLanes>()!;
      final dark = buildDarkTheme('Sahel').extension<DiqqahLanes>()!;
      for (final lanes in [light, dark]) {
        for (final lane in [
          lanes.positive,
          lanes.negative,
          lanes.attention,
          lanes.neutral,
        ]) {
          final ratio = contrastOf(lane.fg, lane.bg);
          expect(ratio, greaterThan(4.5),
              reason: 'الزوق ${lane.fg} فوق ${lane.bg} تباينه $ratio');
        }
      }
    });

    test('س202: حاوية الخطأ الليلية الهادئة — تون داكن قرب الخلفية '
        'ولسانها فوقها بتباين ≥ 4.5:1 (بأمر المالك «عدل الأحمر كما اقترحت»)',
        () {
      final dark = buildDarkTheme('Sahel');
      expect(dark.colorScheme.errorContainer, kDarkErrorContainer);
      expect(dark.colorScheme.onErrorContainer, kDarkOnErrorContainer);
      expect(kDarkErrorContainer, const Color(0xFF421D17));
      expect(kDarkOnErrorContainer, const Color(0xFFE8C0BB));
      // الشريط الليلي (شريط المتابعة/التنبيه) يقرأ هذا الزوج فلا يلمع
      // أحمر صريحاً فوق خلفية الليل، والنص مقروء حرساً.
      final ratio = contrastOf(kDarkOnErrorContainer, kDarkErrorContainer);
      expect(ratio, greaterThan(4.5),
          reason: 'زوج الحاوية الليلية الهادئة تباينه $ratio');
      // الحاوية أهدأ من قرين M3 الصريح (#8C1D18) — غرتها فوق خلفية
      // الليل أقل فلا لمعان أحمر صريح.
      final bannerBg = contrastOf(kDarkErrorContainer, kDarkBackground);
      final loud = contrastOf(const Color(0xFF8C1D18), kDarkBackground);
      expect(bannerBg, lessThan(loud),
          reason: 'الهادئ أهدأ من الصريح — $bannerBg مقابل $loud');
    });

    test('المخططات الثلاثة مردودة بلا تعبئة وإطارها بلون دورها كاملاً', () {
      final lanes = buildLightTheme('Sahel').extension<DiqqahLanes>()!;
      expect(lanes.positiveOutline.fg, kLightGreen);
      expect(lanes.negativeOutline.fg, kLightRed);
      expect(lanes.attentionOutline.fg, kLightBlue);
      for (final lane in [
        lanes.positiveOutline,
        lanes.negativeOutline,
        lanes.attentionOutline,
      ]) {
        expect(lane.outlined, isTrue, reason: 'المخطط موسوم');
        expect(lane.bg, const Color(0x00000000), reason: 'بلا تعبئة');
        expect(lane.border, lane.fg, reason: 'الإطار بلون الدور كاملاً');
      }
    });

    testWidgets('خريطة أنواع الفواتير: الأصل معبأ والمردود مخطط اتجاهه',
        (tester) async {
      DiqqahLane? sale;
      DiqqahLane? purchase;
      DiqqahLane? saleReturn;
      DiqqahLane? purchaseReturn;
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme('Sahel'),
        home: Builder(builder: (context) {
          sale = invoiceKindLane(context, InvoiceKind.sale);
          purchase = invoiceKindLane(context, InvoiceKind.purchase);
          saleReturn = invoiceKindLane(context, InvoiceKind.saleReturn);
          purchaseReturn =
              invoiceKindLane(context, InvoiceKind.purchaseReturn);
          return const SizedBox();
        }),
      ));
      expect(sale!.fg, kLightGreen, reason: 'البيع دائن لنا أخضر معبأ');
      expect(sale!.outlined, isFalse);
      expect(purchase!.fg, kLightRed, reason: 'الشراء مدين علينا أحمر معبأ');
      expect(purchase!.outlined, isFalse);
      expect(saleReturn!.outlined, isTrue,
          reason: 'مردود البيع عودة سلبية مخططة حمراء');
      expect(saleReturn!.fg, kLightRed);
      expect(purchaseReturn!.outlined, isTrue,
          reason: 'مردود الشراء عودة إيجابية مخططة خضراء');
      expect(purchaseReturn!.fg, kLightGreen);
    });

    testWidgets('السقوط الآمن: ثيم بلا أزقة يعطي أزقة من مخططه فلا كسر',
        (tester) async {
      DiqqahLanes? captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          captured = diqqahLanesOf(context);
          return const SizedBox();
        }),
      ));
      expect(captured, isNotNull, reason: 'بلا امتداد ولا كسر');
      expect(captured!.positive.fg, isNot(equals(captured!.negative.fg)));
    });
  });

  group('س203: البني للهوية فقط لا غير — بأمر المالك', () {
    // نفس قنوات الس186 — نسخة محلية لهذه المجموعة
    int chR(Color c) => (c.r * 255.0).round().clamp(0, 255);
    int chG(Color c) => (c.g * 255.0).round().clamp(0, 255);
    int chB(Color c) => (c.b * 255.0).round().clamp(0, 255);

    double luminanceOf(Color c) {
      double f(int v) {
        final s = v / 255.0;
        return s <= 0.03928
            ? s / 12.92
            : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * f(chR(c)) + 0.7152 * f(chG(c)) + 0.0722 * f(chB(c));
    }

    double contrastOf(Color a, Color b) {
      final la = luminanceOf(a);
      final lb = luminanceOf(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    test('البني هوية لا دلالة: primary بُنّي والأخضر الدلالي باقٍ بالأزقة',
        () {
      final light = buildLightTheme('Sahel');
      // primary بُنّي والأخضر المعتمد بعيد عنه — لا أخضر تفاعلاً عاماً
      expect(light.colorScheme.primary, kLightIdentityBrown);
      expect(light.colorScheme.primary, isNot(kLightGreen));
      final dark = buildDarkTheme('Sahel');
      expect(dark.colorScheme.primary, kDarkIdentityBrown);
      expect(dark.colorScheme.primary, isNot(kDarkGreen));
      // الأزقة الإيجابية أخضر معتمد حرفاً — الدلالة لم تُمس
      final lightLanes = light.extension<DiqqahLanes>()!;
      expect(lightLanes.positive.fg, kLightGreen);
      final darkLanes = dark.extension<DiqqahLanes>()!;
      expect(darkLanes.positive.fg, kDarkGreen);
    });

    test('تباين زوج الهوية البنية ≥ 4.5:1 بالوضعين', () {
      // النهار: البني فوق الأبيض والنص الأبيض فوق البني
      final dayText = contrastOf(kLightIdentityBrown, kLightBackground);
      expect(dayText, greaterThan(4.5),
          reason: 'البني النهاري فوق الخلفية $dayText');
      final dayOnPrimary = contrastOf(kLightBackground, kLightIdentityBrown);
      expect(dayOnPrimary, greaterThan(4.5),
          reason: 'onPrimary فوق البني النهاري $dayOnPrimary');
      // الليل: البني الفاتح فوق الداكن ونص الداكن فوق البني
      final nightText = contrastOf(kDarkIdentityBrown, kDarkBackground);
      expect(nightText, greaterThan(4.5),
          reason: 'البني الليلي فوق الخلفية $nightText');
      final nightOnPrimary = contrastOf(kDarkBackground, kDarkIdentityBrown);
      expect(nightOnPrimary, greaterThan(4.5),
          reason: 'onPrimary فوق البني الليلي $nightOnPrimary');
    });

    test('صقل M3: البطاقات مسطحة بزوايا موحدة بالوضعين', () {
      final light = buildLightTheme('Sahel');
      // عبر dynamic — نوع البارامتر تتبدل إلغابيته بين إصدارات Flutter
      // والقراءة سليمة بالحالتين.
      expect((light.cardTheme as dynamic).elevation, 0);
      expect((light.cardTheme as dynamic).shape, isA<ShapeBorder>());
      final dark = buildDarkTheme('Sahel');
      expect((dark.cardTheme as dynamic).elevation, 0);
      expect((dark.cardTheme as dynamic).shape, isA<ShapeBorder>());
    });
  });
}
