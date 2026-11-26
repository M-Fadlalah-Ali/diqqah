import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/backup_center.dart' as catalog show kAppVersion;
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/currencies_screen.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/parties_screen.dart';
import 'package:diqqah_app/transfers_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات س210 — الدفعة 4 «تعميم قانون العرض على بقية الشاشات
/// وانتقال أرشيف الفواتير للقاعدة الزمنية الموحدة مع بحث م11»
/// بأمر المالك حرفاً:
/// - **القانون معمّم** (بندي القانون الأول والرابع — adaptive.dart):
///   الشاشات المركبة بحاوية DiqqahAdaptiveCenter والقوائم بهامش
///   التكيف الأفقي بقيمته الأساسية المحفوظة — فالقياس الهندسي على
///   العريض 1600 بدقة 1.0 بنمط batch27/28/30 الموثق (س206): البت
///   الأيسر للمحتوى 400 بالضبط (نصف الفائض 800)، وعلى الضيّق
///   (سطح الاختبار الافتراضي 800 ≤ الحد) القيم الأصلية حرفاً
///   فلا موضع مختبر يتحرك (الحد الصادق للقانون الموثق س205/س209).
/// - **القاعدة الزمنية الموحدة للأرشيف** (قرار س208 الموثق —
///   «الجاهز لحظي والمكتوب بزر عرض» بامتداد D-077): الاختيار
///   الجاهز بالمنسدلات يعيد التحميل لحظياً بنمط الطلبات، والحقل
///   المكتوب والمدى ينتظران زر «عرض».
/// - **بحث م11** (نمط بحث الأطراف س206 حرفاً): العنوان الدائم
///   والأيقونة المسبقة، والرشّح بألسنة العرض الثلاثة بتطبيع المجال
///   الموثق D-064، والمطبوع والمصدّر صورة العرض ذاتها (F-166).
/// - **الإصدار**: التثبيت الصلب انتقل من s209 إليه بنمط انتقاله
///   من s208 إلى s209.
///
/// الوصول بالتمرير لا الافتراض (درس D-098) وضخّات محدودة لا
/// pumpAndSettle على القوائم (درس س22..س26) والقوائم المنسدلة لا
/// تستقبل اللمس قبل اكتمال حركة دخولها (درس س207 الموثق).
void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// ضخّات الجاهزية المعتمدة بعد pumpWidget — المستقبلات اللحظية
/// تكتمل بضخّات الزمن الثابتة (نمط اختبارات الفواتير الموثق).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('س210 — تعميم قانون العرض على بقية الشاشات', () {
    testWidgets('الأطراف على العريض 1600: حاوية القانون توسّط المحتوى '
        '— البت الأيسر لحقل البحث 400 بالضبط (نصف الفائض)', (tester) async {
      _bigView(tester);
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
      await _settle(tester);

      final search = tester.getRect(
          find.widgetWithText(TextField, 'بحث بالاسم أو الرقم أو الهاتف'));
      expect(search.left, 412,
          reason: 'بندي القانون الأول: الحاوية 800 والفائض 800 فنصف '
              'الفائض 400 + هامش القانون الداخلي 12 = 412 بالضبط '
              '(القياس الهندسي الموثق س209 — البت 412)');
    });

    testWidgets('الأطراف على الضيّق 800 (حد القانون): القيم الأصلية '
        'حرفاً — البت الأيسر 12 فلا موضع مختبر يتحرك', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
      await _settle(tester);

      final search = tester.getRect(
          find.widgetWithText(TextField, 'بحث بالاسم أو الرقم أو الهاتف'));
      expect(search.left, 12,
          reason: 'الضيّق عند الحد وأدنه يمرر الابن كما هو — '
              'الهامش الأساسي 12 الموثق');
    });

    testWidgets('أرشيف الفواتير على العريض 1600: قسم الفلاتر بهامش '
        'القانون — البت الأيسر لحقل البحث 400 بالضبط', (tester) async {
      _bigView(tester);
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await _settle(tester);

      final search = tester
          .getRect(find.widgetWithText(TextField, 'بحث بالطرف أو الرقم'));
      expect(search.left, 400,
          reason: 'قسم الفلاتر بهامش التكيف الأفقي بندي القانون الأول '
              '(آلية م06 الموثقة للقوائم — نصف الفائض 400 بالضبط '
              'والضيّق بقيمته الأصلية 12)');
    });

    testWidgets('دخان العريض 1600 على القوائم المموّهة بالهامش: '
        'التحويلات والعملات تبنى بلا فيض ولا استثناء', (tester) async {
      _bigView(tester);
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: TransfersScreen(db: db)));
      await _settle(tester);
      await tester.pumpWidget(MaterialApp(home: CurrenciesScreen(db: db)));
      await _settle(tester);
      expect(tester.takeException(), isNull,
          reason: 'القانون على العريض بنية موثوقة — لا فيض RenderFlex');
    });
  });

  group('س210 — القاعدة الزمنية الموحدة على أرشيف الفواتير', () {
    testWidgets('الاختيار الجاهز بالمنسدلة يعيد التحميل لحظياً بنمط '
        'الطلبات — المسودات فارغة بلا ضغطة عرض والمرحّلة تعود',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await _settle(tester);
      // دورة البذرة: فاتورتان مرحّلتان حصراً (الشراء والبيع).
      expect(find.textContaining('فاتورة شراء 26000001'), findsOneWidget);
      expect(find.textContaining('فاتورة بيع 26000001'), findsOneWidget);

      // درس س207: القوائم المنسدلة لا تستقبل اللمس قبل اكتمال الحركة
      // — واللمس على الحقل ذاته لا ملصقه العائم (الصمّ على الهدف).
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      // ضخّات الفتح الكاملة — القائمة لا تستقبل اللمس قبل اكتمال حركة
      // دخولها (درس س207 الموثق: IgnorePointer حتى isCompleted).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('المسودات').last);
      // الاختيار الجاهز يعيد التحميل لحظياً — لا زر عرض بينهما (س210).
      // وضخّات أطول لانقضاء حركة إغلاق القائمة قبل لمس لاحق (درس س207
      // بامتداده: IgnorePointer حتى اكتمال الخروج).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.text('لا فواتير بعد — أضف أول فاتورة بزر «فاتورة جديدة»'),
          findsOneWidget,
          reason: 'المنسدلة الجاهزة لحظية — المسودات لا دورة بذرة فيها');

      // والعودة للمرحّلة لحظياً كذلك — فاتورتا الدورة تعودان.
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('المرحّلة').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('فاتورة شراء 26000001'), findsOneWidget,
          reason: 'الشراء المرحّل يعود لحظياً بلا ضغطة عرض (س210)');
      expect(find.textContaining('فاتورة بيع 26000001'), findsNothing,
          reason: 'البيع بعد قبض نصفه حالته المشتقة «جزئية» لا «مرحّلة» '
              '(لسان س-86 الموثق) فلا يمر بفلتر المرحّلة أصلاً');
    });

    testWidgets('بحث م11: المكتوب ينتظر زر «عرض» (D-077) والرشّح '
        'بتطبيع المجال D-064 — «امل» تلتقي «الأمل»', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await _settle(tester);

      // النمط م11: العنوان الدائم والأيقونة المسبقة بنمط بحث الأطراف.
      expect(find.text('بحث بالطرف أو الرقم'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);

      // الكتابة وحدها لا تعيد التحميل — القاعدة الزمنية الموحدة.
      await tester.enterText(
          find.widgetWithText(TextField, 'بحث بالطرف أو الرقم'), 'امل');
      await _settle(tester);
      expect(find.textContaining('فاتورة شراء 26000001'), findsOneWidget,
          reason: 'الكتابة لا تُطبَّق — الجاهز لحظي والمكتوب بزر عرض');

      // زر العرض يُطبّق البحث بتطبيع المجال — الأمل بلا همزة تلتقي.
      await tester.tap(find.text('عرض'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('فاتورة بيع 26000001'), findsOneWidget,
          reason: 'بيع «عميل الأمل» يطابق «امل» بعد التطبيع (D-064)');
      expect(find.textContaining('فاتورة شراء 26000001'), findsNothing,
          reason: 'شراء «مورد الشرق» خارج المطابقة — والعرض صورة '
              'القائمة فالمطبوع والمصدّر معها (F-166)');

      // والفراغ المُرشَّح بلسانه الموثق — لا نتائج مطابقة.
      await tester.enterText(
          find.widgetWithText(TextField, 'بحث بالطرف أو الرقم'),
          'لا شيء بهذا الاسم');
      await tester.tap(find.text('عرض'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('لا نتائج مطابقة للبحث ضمن العرض الحالي'),
          findsOneWidget);
    });
  });

  group('س210 — الإصدار', () {
    test('حارس المطابقة: pubspec↔كتالوج الإصدار بتساوي (س210 — '
        'والتثبيت الصلب انتقل من s210 إلى s211 بنمط انتقاله الموثق)',
        () {
      // التثبيت الصلب انتقل من s210 إلى s211 بنمط انتقاله من
      // s208 إلى s209 إلى s210 — فs210 صار حارس مطابقة
      // pubspec↔الكتالوج بلا تثبيت صلب.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final line = pubspec
          .split('\n')
          .firstWhere((l) => l.startsWith('version:'));
      final pinned = line.split('+').last.trim();
      expect(catalog.kAppVersion.split('+').last, pinned,
          reason: 'versionCode واحد بpubspec والكتالوج');
    });
  });
}
