import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/adaptive.dart';
import 'package:diqqah_app/app_theme.dart';
import 'package:diqqah_app/main.dart' show DiqqahApp;
// كتالوج الإصدار بالبادئة — نسخة العرض المحقونة من settings_screen
// بلسانها المختلف (فارغ التطوير) فلا التباس بين الثابتين.
import 'package:diqqah_app/backup_center.dart' as catalog show kAppVersion;
import 'package:diqqah_app/settings_screen.dart'
    show diqqahVersionLine, kAppVersion, kBuildNumber;

import 'test_guard.dart';

/// اختبارات س209 — الدفعة 3 «قانون عرض سطح المكتب والرئيسية الست
/// طبقات» (بند 6 من بنود المالك العشرة «قواعد الصناعة» — وُقفت س207
/// بأن تفاصيلها بيد مجلس المستشارين فالتفصيل قراره الموثق بالدفعة،
/// بأمر المالك «تابع دفعة 3»):
/// - **الست طبقات**: الترويسة والتنبيهات (قائمتان حرفاً) ونبض العمل
///   الوصول السريع (قائمة حرفاً) وشبكة
///   الوحدات (بطاقات لا أيقونة على العريض حصراً) والتذييل (سطر
///   الإصدار بدالة العرض القائمة D-213).
///   وبالوجود لا بالوعد: بداية السنة غير المصدقة متابعة قائمة على
///   القاعدة النظيفة فالبطاقة الجامعة ظاهرة أولاً بالوجود،
///   والتفصيلية الثلاث بعدّاداتها الصفرية غائبة (الصمت الهادئ).
/// - **قانون العرض**: شبكة أعمدة محسوبة من المتاح وWrap بلا Scrollable
///   ثانٍ (درس س182 الموثق)، والبطاقة تُفعَّل حيث يُفعَّل التوسيط
///   بالضبط (فوق 800) فلا مساس بأي موضع مختبر على الضيّق، وسلم
///   المسافات 4/8، وتباين AA محكوم حسابياً WCAG لا بعين الفاحص.
///
/// الوصول بالتمرير لا الافتراض (درس D-098) والعريض بدقة 1.0 بنمط
/// batch27/28/30 الموثق (س206) — والضيّق بسطح الاختبار الافتراضي
/// 800×600 (حد م06 القائم فالبدائل بالتطبيق صفراً).
void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// بذرة صنف تحت الحد الأدنى — نمط s198 الموثق: وحدة + صنف بحد أدنى
/// 5 وبلا رصيد فمتابعة التخزين تنشأ والعدادات تعيش.
Future<void> _seedBelowMinimum(DiqqahDatabase db) async {
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
}

void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('س209: الست طبقات على العريض (1600 — فوق حد التوسيط)', () {
    testWidgets('نبض العمل من اللقطة والشبكة بطاقات والتذييل بمفتاحه',
        (tester) async {
      _bigView(tester);
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');
      await _seedBelowMinimum(db);

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      // الطبقة 3 — نبض العمل: حاضرة بالوجود (متابعة الصنف تحت الحد)
      // ولسانها الجامع والتفصيلي وعدّاد الواحد من اللقطة.
      expect(find.byKey(const Key('home_pulse')), findsOneWidget);
      expect(find.text('نبض العمل'), findsOneWidget);
      expect(find.text('متابعات نشطة'), findsOneWidget);
      expect(find.text('أصناف تحت الحد الأدنى'), findsOneWidget);

      // الطبقة 5 — شبكة الوحدات بطاقات لا أيقونة: الوصف الظاهر
      // (ما كان تلميحاً حصراً) وعدد البطاقات الوحدات التسع عشرة
      // (س211/D-216: بلاطة «المستخدمون» نهايتها).
      expect(
          find.text('فواتير البيع ومردودها بفلتر جهتهما'), findsOneWidget);
      final gridCards = find.descendant(
          of: find.byKey(const Key('home_modules_grid')),
          matching: find.byType(Card));
      expect(gridCards, findsNWidgets(19));

      // شبكة أعمدة محسوبة: عمود البطاقة 188 بالضبط (800 - 24 هامشاً
      // - 24 فجوات ثلاثة على الأربعة) وبطاقة النبض 384 بالضبط
      // (776 - 8 فجوة على الاثنين) — والبت الأيسر 412 (نصف الفائض
      // 400 + هامش القانون 12) بنمط القياس الهندسي الموثق س208.
      final firstCard = tester.getRect(gridCards.first);
      expect(firstCard.width, 188);
      final pulseRect = tester.getRect(find.byKey(const Key('home_pulse')));
      expect(pulseRect.left, 412);
      expect(pulseRect.width, 776);

      // الطبقة 6 — التذييل: المفتاح حاضر بنيوياً والنص فارغ بالتطوير
      // والاختبار بعرف نسخة العرض المحقونة من CI (D-213) فلا ضجيج.
      expect(find.byKey(const Key('home_footer')), findsOneWidget);
      expect(find.textContaining('دِقَّة v.'), findsNothing);
    });
  });

  group('س209: الضيّق كما كان حرفاً (800 — حد التوسيط ذاته)', () {
    testWidgets('بلاطاتها الأيقونية القائمة ولا نبض نظيفاً ولا بطاقة',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      // الطبقة 3 بالوجود لا بالوعد: قاعدة نظيفة تحمل متابعة بداية
      // السنة غير المصدقة فالبطاقة الجامعة ظاهرة — والتفصيلية
      // الثلاث بعدّاداتها الصفرية غائبة (الصمت الهادئ عرف س198).
      expect(find.byKey(const Key('home_pulse')), findsOneWidget);
      expect(find.text('نبض العمل'), findsOneWidget);
      expect(find.text('متابعات نشطة'), findsOneWidget);
      expect(find.text('أصناف تحت الحد الأدنى'), findsNothing);

      // الطبقة 5 على الضيّق بلاطاتها القائمة حرفاً (س182 بأمر
      // المالك): لا Card داخل الشبكة ولا وصف مرحلة ظاهر — فلا
      // موضع مختبر يتحرك على حد م06 القائم.
      final tiles = tester.widgetList<InkWell>(find.descendant(
          of: find.byKey(const Key('home_modules_grid')),
          matching: find.byType(InkWell)));
      expect(tiles.length, 19); // + المستخدمون (س211/D-216)
      expect(
          find.descendant(
              of: find.byKey(const Key('home_modules_grid')),
              matching: find.byType(Card)),
          findsNothing);
      expect(find.text('فواتير البيع ومردودها بفلتر جهتهما'), findsNothing);

      // والطبقة 6 بمفتاحها البنيوي والنص فارغ التطوير (D-213).
      expect(find.byKey(const Key('home_footer')), findsOneWidget);
    });

    testWidgets('نبض الضيّق بالوجود: عدّاد اللقطة يظهر ببطاقته',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');
      await _seedBelowMinimum(db);

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      // المصنف تحت الحد نبضه ظاهر حتى على الضيّق — بالوجود لا
      // بالوعد، ولافتة المتابعات أُزيلت بعقد س221 (نبض العمل
      // المصدر الواحد بقرار المالك).
      expect(find.byKey(const Key('home_pulse')), findsOneWidget);
      expect(find.text('أصناف تحت الحد الأدنى'), findsOneWidget);
      expect(find.textContaining('متابعة تحتاج انتباهك'), findsNothing,
          reason: 'س221: بند اللافتة أُزيل — نبض العمل مصدره الواحد');
    });
  });

  group('س209: قانون العرض — تباين AA حسابياً وسلم المسافات', () {
    /// نسبة التباين WCAG 2.1 — الحساب من سطوع المادة لا من العين.
    double contrastRatio(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    void expectAA(Color fg, Color bg, String label, ThemeMode mode) {
      final ratio = contrastRatio(fg, bg);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'AA للنص العادي: «$label» ($mode) بنسبة '
              '${ratio.toStringAsFixed(2)}:1');
    }

    test('أزواج أدوار الثيم المستعملة بالرئيسية كلها فوق 4.5:1 بالوضعين',
        () {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        final scheme = (mode == ThemeMode.light
                ? buildLightTheme('TestFont')
                : buildDarkTheme('TestFont'))
            .colorScheme;
        // النص الأساسي والثانوي على السطح (البطاقات والتذييل).
        expectAA(scheme.onSurface, scheme.surface, 'onSurface/surface', mode);
        expectAA(scheme.onSurfaceVariant, scheme.surface,
            'onSurfaceVariant/surface', mode);
        // قرص الأيقونة وعدّاد النبض (المصدر الواحد المشترك).
        expectAA(scheme.onSecondaryContainer, scheme.secondaryContainer,
            'onSecondaryContainer/secondaryContainer', mode);
        // لافتات التنبيه (س198) وشارة المتابعات (س141).
        expectAA(scheme.onErrorContainer, scheme.errorContainer,
            'onErrorContainer/errorContainer', mode);
        expectAA(scheme.onError, scheme.error, 'onError/error', mode);
        // أزرار الفعل النصية بلسان primary على السطح.
        expectAA(scheme.primary, scheme.surface, 'primary/surface', mode);
      }
    });

    test('سلم المسافات 4/8 وأعمدة الشبكة الأربعة بقيمه الموثقة', () {
      expect(kDiqqahSpacingXs, 4);
      expect(kDiqqahSpacingS, 8);
      expect(kDiqqahSpacingM, 12);
      expect(kDiqqahSpacingL, 16);
      expect(kDiqqahSpacingXl, 24);
      for (final v in [
        kDiqqahSpacingXs,
        kDiqqahSpacingS,
        kDiqqahSpacingM,
        kDiqqahSpacingL,
        kDiqqahSpacingXl,
      ]) {
        expect(v % 4, 0, reason: 'كل فراغ مضاعف 4 (بنود القانون)');
      }
      expect(kDiqqahModuleGridColumns, 4);
    });

    test('سطر الإصدار العرضي D-213 — البادئة المُشعرة وفراغ التطوير', () {
      // بصيغة CI: disp = «0.265» بشطرين فالعرض المُشعر.
      expect(diqqahVersionLine('0.265', '65'), 'دِقَّة v.0.265');
      // بصيغة التطوير: نسخة العرض فارغة فلا سطر أصلاً (لا ضجيج ولا كسر).
      expect(diqqahVersionLine('', ''), isEmpty);
      // والثابتان المحقونان فارغان بالاختبار (حقن CI حصراً).
      expect(kAppVersion, isEmpty);
      expect(kBuildNumber, isEmpty);
    });
    test('الإصدار الموحد: pubspec يطابق كتالوج الإصدار (س209 — البنية '
        'بلا تثبيت صلب — انتقل التثبيت الصلب إلى s210 بنمط انتقاله '
        'من s208 إلى s209)', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final line = pubspec
          .split('\n')
          .firstWhere((l) => l.startsWith('version:'));
      expect(line, 'version: ${catalog.kAppVersion}');
    });
  });
}
