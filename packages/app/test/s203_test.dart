import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/company_profile.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/receivables_screen.dart';
import 'package:diqqah_app/settings_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات س203 (بأمر المالك «تابع إلى ب60»):
/// م0: تلميحات البلاطات بلا «متاحة الآن».
/// م2: صندوق الوصول السريع — التثبيت بالضغطة المطولة والإلغاء
///     بعلامة اللاصقة والحد أربعة والتخزين المحلي.
/// م3: «+» كشف حساب الطرف — السند بطرفه معبّأً: عميل يفتح القبض
///     ومورد يقلب النوع للصرف (خريطة الذمم 05 §5).
/// م4: بيانات المنشأة — app_meta بلا ترحيلة والحفظ والتحديث والفاسد
///     سقوط آمن، وبطاقة الإعدادات بنافذتها.
/// م5: «مردود من هذه الفاتورة» — من التفصيل للمرحّل بمعرّف الأصل
///     معبّأً حرفاً.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// بعد فتح الشاشات (درس س22..س26 الموثق) — والتنقل الحتمي س191.
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  Future<int> partyIdOf(DiqqahDatabase db, String kind) async {
    final row = await db
        .customSelect("SELECT id FROM parties WHERE kind = '$kind'")
        .getSingle();
    return row.data['id'] as int;
  }

  /// ضخّات التحميل الموحدة — محمّل البوابة ثم القراءات الأولى.
  Future<void> settleScreen(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// الزلقة اللحظية للبشّارة المعروضة — removeCurrentSnackBar من مصدر
  /// ScaffoldMessenger يزيل الحالية فوراً بلا حركة خروج ويُلقي لطابورها
  /// التالي إلى العرض لحظياً — فلا اعتماد على مضخات زمنية ولا طابورٌ
  /// يتراص على الرسالة التالية.
  ///
  /// درس الجولة #395 (حد صادق): مضخّات التصريف الزمنية pump(5s)
  /// أدّت إلى StateError لاحق على Icons.cancel بعد أن كانت chips()=4
  /// قبلها مباشرة — والآلية الدقيقة لم تُفهم فالنمط اللحظي يلغي الزمن
  /// كلياً بدل تفسير ما لم يُفهم (درس س163 روحاً: لا تخمين حيث يُمكن
  /// قطع التبعية).
  void popSnackbar(WidgetTester tester) {
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
  }

  group('س203 م0: تلميحات البلاطات بلا «متاحة الآن» — بأمر المالك '
      '«يظهر في شرح الأيقونة عبارة متاحة الآن ولا داعي لها»', () {
    testWidgets('التلميحات الثمانية عشر خالية من البادئة', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      final tips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '')
          .toList();
      expect(tips.length, 20,
          reason: 'بلاطة لكل تلميح — 18 وحدة + الإعدادات '
              '(س211: المستخدمون) (س212: شارة الجلسة قائمة أفعال '
              'D-215 بتلميحها)');
      for (final m in tips) {
        expect(m, isNot(contains('متاحة الآن')),
            reason: 'البادئة زالت والتلميح بلسان الوصف ذاته: $m');
      }
      // والوصف باقٍ بلا البادئة — عينة: بلاطة المبيعات
      expect(
        tips.any((m) => m.contains('فواتير البيع ومردودها بفلتر جهتهما')),
        isTrue,
        reason: 'الوصف بقى بعد نزع البادئة',
      );
    });
  });

  group('س203 م2: صندوق الوصول السريع — حد أربعة بضغطة مطولة', () {
    testWidgets('التثبيت والإلغاء والحد والتخزين المحلي', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      // الفارغ إرشاد لا صندوق ميت (F-162 روحاً) — ولا Wrap ثانٍ
      // حتى يُثبت (عرف Scrollable الواحد والشبكة.Wrap الواحدة)
      expect(find.textContaining('اضغط مطولاً'), findsOneWidget);
      expect(find.byKey(const Key('home_quick_access')), findsNothing);

      // التثبيت بالضغطة المطولة على بلاطة ظاهرة
      await tester.longPress(find.text('الأطراف'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('home_quick_access')), findsOneWidget,
          reason: 'اللاصقة ظهرت والصندوق بحِدوده');
      expect(find.textContaining('اضغط مطولاً'), findsNothing,
          reason: 'الإرشاد زال ما دام فيه مثبت');
      expect(find.text('الأطراف'), findsNWidgets(2),
          reason: 'بلاطة الشبكة ولاصقة الصندوق');
      // والتخزين المحلي كتب المفتاح (نمط D-104)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('home_quick_access'), ['parties']);

      // ثلاثة أخرى بالتمرير — الأصناف والصناديق والعملات
      Future<void> pinVisibleTile(String title) async {
        // زلقة بشّارة التثبيت السابقة لحظياً قبل الضغطة الجديدة —
        // فالطابور فارغ عند كل تثبيت ولا رسالة تنتظر من تحتها.
        popSnackbar(tester);
        await tester.scrollUntilVisible(
          find.text(title),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        await tester.longPress(find.text(title));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      await pinVisibleTile('الأصناف');
      await pinVisibleTile('الصناديق');
      await pinVisibleTile('العملات');

      int chips() => tester
          .widgetList<InputChip>(find.descendant(
              of: find.byKey(const Key('home_quick_access')),
              matching: find.byType(InputChip)))
          .length;
      expect(chips(), 4, reason: 'أربعة مثبتة');

      // الخامس يُرفض برسالة لا صمت — والحد فرض صارم
      await pinVisibleTile('التقارير اليومية');
      expect(find.textContaining('أربعة كحد'), findsOneWidget,
          reason: 'رسالة الامتلاء ظاهرة');
      expect(chips(), 4, reason: 'الخامس لم يدخل');

      // زلقة رسالة الحد لحظياً — فالإلغاء في الحالة ذاتها التي أقرت
      // chips()=4 بلا أي تقدم زمني بينهما.
      popSnackbar(tester);

      // الإلغاء بعلامة حذف اللاصقة.
      //
      // علة الجولة #396 الموثقة (حد صادق — نهاية سلسلة #392..#396):
      // الـStateError المتعقب عبر أربع جولات بعلته الزمنية المتحصّرة
      // لم يكن زمناً ولا طابوراً أصلاً — أيقونة الحذف الافتراضية
      // للـInputChip في M3 بـFlutter 3.47.9 هي «Icons.clear» حصراً
      // (input_chip.dart: resolvedDeleteIcon = deleteIcon ??
      // const Icon(Icons.clear, size: 18)) لا «Icons.cancel» الكلاسيكية
      // بـRawChip — فالباحث عن cancel يجد صفراً فينكسر «No element»
      // وإن كانت الرقائق الأربع حاضرة بحذافيرها (الاستقصاء الحي:
      // أربع أيقونات e168). الإنتاج سليم فلا مساس — والصواب هوية
      // الأيقونة بالاختبار حصراً.
      await tester.tap(find.byIcon(Icons.clear).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(chips(), 3, reason: 'أُلغي واحد');
      expect(find.textContaining('أُلغي التثبيت'), findsOneWidget);
      final prefsAfter = await SharedPreferences.getInstance();
      expect(prefsAfter.getStringList('home_quick_access')!.length, 3);
    });
  });

  group('س203 م3: «+» كشف حساب الطرف يفتح السند بطرفه معبّأً', () {
    testWidgets('العميل يفتح القبض بطرفه معبأً وبمطابقاته الحية',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      final custId = await partyIdOf(db, 'customer');
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => PartyStatementPage(
            db: db, partyId: custId, partyName: 'عميل الأمل'),
      ));
      await settleScreen(tester);

      // زر «سند جديد» على كشف الحساب (س203)
      await tester.tap(find.text('سند جديد'));
      await settleScreen(tester);

      expect(find.byType(VoucherEditScreen), findsOneWidget);
      // القبض عرف النموذج والطرف معبأ بعميل الكشف
      expect(find.text('سند قبض'), findsOneWidget,
          reason: 'العميل يفتح القبض — خريطة الذمم 05 §5');
      // بند المنسدل مركّب بالرقم والرصيد (D-106) — النص المحتوي ضمن
      // النموذج حصراً فلا يطابق الكشف خلفه بالشجرة (درس س-90 الحرفي)
      expect(
        find.descendant(
            of: find.byType(VoucherEditScreen),
            matching: find.textContaining('عميل الأمل')),
        findsOneWidget,
        reason: 'الطرف معبأ من الكشف لا يدخل يدوياً',
      );
      // ومطابقات فاتورة الدورة المفتوحة ظهرت فوراً لا بانتظار تغيير
      expect(find.textContaining('متبقٍ'), findsWidgets,
          reason: 'المطابقات بنيت فور التعبئة (س-163 روحاً)');
    });

    testWidgets('المورد يقلب النوع للصرف فلا نموذج فانتقائي ينكسر',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      final supId = await partyIdOf(db, 'supplier');
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => PartyStatementPage(
            db: db, partyId: supId, partyName: 'مورد الشرق'),
      ));
      await settleScreen(tester);

      await tester.tap(find.text('سند جديد'));
      await settleScreen(tester);

      expect(find.byType(VoucherEditScreen), findsOneWidget);
      // النوع قلب للصرف تلقائياً (مورد ← صرف) والطرف معبأ —
      // ولو لم يقلب لانكسر بناء القائمة (القيمة فانتقائية عن البنود)
      expect(find.text('سند دفع'), findsOneWidget,
          reason: 'المورد يفتح الصرف — خريطة الذمم 05 §5');
      expect(
        find.descendant(
            of: find.byType(VoucherEditScreen),
            matching: find.textContaining('مورد الشرق')),
        findsOneWidget,
        reason: 'الطرف معبأ من الكشف — بند مركّب بالرقم والرصيد (D-106)',
      );
    });
  });

  group('س203 م4: بيانات المنشأة — app_meta بلا ترحيلة', () {
    test('الغائب null والحفظ والتحديث والفاسد سقوط آمن', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);

      // الغائب null فتعيد الطباعة ترويستها القائمة حرفاً
      expect(await loadCompanyProfile(db), isNull);
      expect(await db.metaValueOf(kCompanyProfileMetaKey), isNull);

      // الحفظ والقراءة الكاملة
      await saveCompanyProfile(
        db,
        const CompanyProfile(
          name: 'متجر النور',
          phone: '0999111222',
          address: 'دمشق — سوق الحميدية',
          taxNumber: 'T-2026-77',
        ),
      );
      final p = await loadCompanyProfile(db);
      expect(p, isNotNull);
      expect(p!.name, 'متجر النور');
      expect(p.phone, '0999111222');
      expect(p.address, 'دمشق — سوق الحميدية');
      expect(p.taxNumber, 'T-2026-77');

      // التحديث زرعٌ فوق العرف — والحقل المتروك يسقط
      await saveCompanyProfile(db, const CompanyProfile(name: 'متجر النور'));
      final p2 = await loadCompanyProfile(db);
      expect(p2!.name, 'متجر النور');
      expect(p2.phone, isNull);
      expect(p2.address, isNull);

      // JSON الفاسد والاسم الفارغ — سقوط آمن بلا كسر
      await db.upsertMetaValue(kCompanyProfileMetaKey, 'not-json{{');
      expect(await loadCompanyProfile(db), isNull);
      await saveCompanyProfile(db, const CompanyProfile(name: '   '));
      expect(await loadCompanyProfile(db), isNull);
    });

    testWidgets('بطاقة الإعدادات بنافذتها: الاسم إلزامي والحفظ يُبشّر',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          db: db,
          dbPath: ':memory:',
          onRestored: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // البطاقة أول القائمة للمدير
      await tester.scrollUntilVisible(
        find.text('بيانات المنشأة'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('بيانات المنشأة'));
      await tester.pumpAndSettle();

      // الاسم إلزامي — الفراغ يُبشّر بالنقص والنافذة باقية
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('اسم المنشأة إلزامي'), findsOneWidget);
      expect(find.text('بيانات المنشأة'), findsWidgets,
          reason: 'النافذة باقية ما دام الاسم فارغاً');

      // زلقة بشّارة الاسم الإلزامي لحظياً — فلا يتراص الطابور على
      // بشّارة النجاح (النمط اللحظي نفسه بلا مضخات زمنية).
      popSnackbar(tester);

      // الحفظ الصحيح يغلق ويُبشّر ويخزن
      await tester.enterText(
          find.widgetWithText(TextField, 'اسم المنشأة (إلزامي)'),
          'متجر النور');
      await tester.enterText(
          find.widgetWithText(TextField, 'الهاتف'), '0999111222');
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('حُفظت بيانات المنشأة'), findsOneWidget);
      final saved = await loadCompanyProfile(db);
      expect(saved!.name, 'متجر النور');
      expect(saved.phone, '0999111222');
    });
  });

  group('س203 م5: «مردود من هذه الفاتورة» من التفصيل', () {
    testWidgets('للمرحّل حصراً ويفتح مردود الأصل بمعرّفه معبّأً حرفاً',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);
      await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      final saleRow = await db.customSelect(
        "SELECT id FROM invoices WHERE kind = 'sale' "
        "AND state <> 'draft' ORDER BY id LIMIT 1",
      ).getSingle();
      final saleId = saleRow.data['id'] as int;

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => InvoiceDetailScreen(db: db, invoiceId: saleId),
      ));
      await settleScreen(tester);

      // الزر للمرحّل (وعولته مدفوعة وجزئية) فالأصل المرجع مرحَّل
      expect(find.text('مردود من هذه الفاتورة'), findsOneWidget);
      await tester.tap(find.text('مردود من هذه الفاتورة'));
      await settleScreen(tester);

      expect(find.byType(InvoiceEditScreen), findsOneWidget);
      // النوع من زر الدخول حصراً — لا مبدّل بالنموذج (س-163)
      expect(find.text('النوع يُحدد من زر الدخول — لا مبدّل هنا'),
          findsOneWidget);
      // ومعرّف الأصل معبّأً حرفاً فلا إدخال يدوي لما هو مرئي أماماً
      expect(
        find.widgetWithText(
            TextField, 'معرف الفاتورة الأصلية (إلزامي للمردود)'),
        findsOneWidget,
      );
      expect(find.text('$saleId'), findsOneWidget,
          reason: 'معرّف الأصل معبّأ من التفصيل');
    });
  });
}
