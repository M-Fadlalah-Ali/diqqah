// اختبارات س233 — المرحلة أ (0.285) من خارطة الطريق الخماسية بجولات
// المالك الثلاث: خيارا التقويم (D-231 — أسماء الأشهر وأول الأسبوع
// بوفد ترجمة حاكم وسطر تاريخ المطبوعات الطويل)، وبطاقة النسخ الآلي
// (D-232 — المفتاح الرئيسي والخانات والمرشحة والموعد القادم)، وشاشة
// البدء المتحركة بحدّها الأدنى نصف ثانية ومؤشرا الحالة الصغيران
// بالرئيسية (D-233).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_app/auto_backup_prefs.dart';
import 'package:diqqah_app/calendar_localizations.dart';
import 'package:diqqah_app/calendar_prefs.dart';
import 'package:diqqah_app/hijri_display.dart';
import 'package:diqqah_app/main.dart' show AppGate, DiqqahApp;
import 'package:diqqah_app/settings_screen.dart';
import 'package:diqqah_app/splash_screen.dart';

import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('س233/D-231: التقويم — أسماء الأشهر وأول الأسبوع', () {
    test('الصيغة الطويلة بالأسماء المختارة شامية ودولية', () {
      expect(formatDiqqahLongDate(DateTime(2026, 11, 28),
          names: DiqqahMonthNames.shami), '28 تشرين الثاني 2026');
      expect(
          formatDiqqahLongDate(DateTime(2026, 1, 1),
              names: DiqqahMonthNames.shami),
          '1 كانون الثاني 2026');
      expect(formatDiqqahLongDate(DateTime(2026, 11, 28),
          names: DiqqahMonthNames.international), '28 نوفمبر 2026');
      expect(
          formatDiqqahLongDate(DateTime(2026, 12, 31),
              names: DiqqahMonthNames.international),
          '31 ديسمبر 2026');
    });

    test('اسم الشهر الفاسد يعيد الأول بلا رمي (قراءة عرضية)', () {
      expect(diqqahMonthName(0, names: DiqqahMonthNames.shami),
          'كانون الثاني');
      expect(diqqahMonthName(13, names: DiqqahMonthNames.international),
          'يناير');
    });

    test('فهرس أول الأسبوع بعرف MaterialLocalizations: أحد 0 سبت 6 اثنين 1',
        () {
      expect(
          diqqahWeekStartIndex(DiqqahWeekStart.sunday), 0);
      expect(
          diqqahWeekStartIndex(DiqqahWeekStart.saturday), 6);
      expect(diqqahWeekStartIndex(DiqqahWeekStart.monday), 1);
    });

    test('سطر تاريخ المطبوعات: طويل بالأسماء المختارة والهجري بجانبه', () {
      expect(printDateLine('2026-11-28',
          names: DiqqahMonthNames.shami, hijri: false),
          '28 تشرين الثاني 2026');
      // الهجري حين يُفعَّل: الطويلة ثم اللاحقة — بكسر بادئة دقيق.
      final withHijri = printDateLine('2026-11-28',
          names: DiqqahMonthNames.international, hijri: true);
      expect(withHijri.startsWith('28 نوفمبر 2026 (هـ '), isTrue,
          reason: 'الصيغة الطويلة ثم الهجري — نمط displayDate ذاته');
      expect(withHijri.endsWith(')'), isTrue);
      // المدخل الفاسد يعود كما كان بلا اختراع (عرف displayDate).
      expect(printDateLine('not-a-date'), 'not-a-date');
    });

    testWidgets('وفد الترجمة الحاكم: شهر المنتقي وتاريخه الطويل وأول أسبوعه '
        'بالاختيار — وكل ما عداه بتمرير حرفي للوفد العالمي', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        // س233: الوفد الحاكم أولاً — المفوّضون الأوائل لهم الأسبقية.
        localizationsDelegates: [
          const DiqqahCalendarMaterialLocalizationsDelegate(
            monthNames: DiqqahMonthNames.shami,
            weekStart: DiqqahWeekStart.monday,
          ),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ));
      await tester.pumpAndSettle();
      final loc = Localizations.of<MaterialLocalizations>(
          captured, MaterialLocalizations)!;
      expect(loc.formatMonthYear(DateTime(2026, 11, 28)), 'تشرين الثاني 2026');
      expect(
          loc.formatFullDate(DateTime(2026, 11, 28)), '28 تشرين الثاني 2026');
      expect(loc.firstDayOfWeekIndex, 1, reason: 'الاثنين المختار');
      // التمرير الحرفي: عضو من الوفد العالمي يعمل كما هو.
      expect(loc.okButtonLabel, isNotEmpty);
      expect(loc.backButtonTooltip, isNotEmpty);
      expect(loc.datePickerHelpText, isNotEmpty);
    });

    testWidgets('الافتراض الدولية والسبت: سلوك القائم قبل الخيارين حرفاً',
        (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        // س233: الوفد الحاكم أولاً — المفوّضون الأوائل لهم الأسبقية.
        localizationsDelegates: const [
          DiqqahCalendarMaterialLocalizationsDelegate(
            monthNames: DiqqahMonthNames.international,
            weekStart: DiqqahWeekStart.saturday,
          ),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ));
      await tester.pumpAndSettle();
      final loc = Localizations.of<MaterialLocalizations>(
          captured, MaterialLocalizations)!;
      expect(loc.formatMonthYear(DateTime(2026, 11, 28)), 'نوفمبر 2026');
      expect(loc.firstDayOfWeekIndex, 6, reason: 'السبت الافتراض');
    });
  });

  group('س233/D-232: النسخ الآلي — السياسة والمرشحة', () {
    test('الافتراض: المفتاح مفعّل وكل الخانات مفعلة (سلوك المحرك القائم)',
        () {
      expect(autoBackupEnabled.value, isTrue);
      expect(
          autoBackupKindAllowed(BackupScheduleKind.hourly), isTrue);
      expect(autoBackupKindAllowed(BackupScheduleKind.daily), isTrue);
      expect(autoBackupKindAllowed(BackupScheduleKind.weekly), isTrue);
      expect(autoBackupKindAllowed(BackupScheduleKind.monthly), isTrue);
      expect(autoBackupAnnualAtClose.value, isTrue);
    });

    test('المرشحة: بلا مفتاح لا دورة، وبلا خانة لا دورتها', () async {
      autoBackupEnabled.value = false;
      addTearDown(() => autoBackupEnabled.value = true);
      expect(autoBackupKindAllowed(BackupScheduleKind.daily), isFalse,
          reason: 'المفتاح الرئيسي مطفأ فلا دورة أصلاً');
      autoBackupEnabled.value = true;
      await setAutoBackupKind(BackupScheduleKind.daily, false);
      addTearDown(() => setAutoBackupKind(BackupScheduleKind.daily, true));
      expect(autoBackupKindAllowed(BackupScheduleKind.daily), isFalse);
      expect(autoBackupKindAllowed(BackupScheduleKind.hourly), isTrue,
          reason: 'خانة الساعي باقية فساعيتها تجري');
    });

    test('الخيارات تُخزَّن وتُقرأ (نمط مخزن الاختبار)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auto_backup_enabled': false,
        'auto_backup_kinds': 'd,m',
        'auto_backup_annual_at_close': false,
      });
      await loadAutoBackupPrefs();
      expect(autoBackupEnabled.value, isFalse);
      expect(autoBackupKinds.value,
          {BackupScheduleKind.daily, BackupScheduleKind.monthly});
      expect(autoBackupAnnualAtClose.value, isFalse);
      // المنبّهات مشتركة عبر اختبارات الملف — إعادة الافتراضات بعهد
      // التفكيك فلا يتسرب إيقاف التخزين إلى بطاقة الدفعة ومؤشراتها.
      addTearDown(() {
        autoBackupEnabled.value = true;
        autoBackupKinds.value = const {
          BackupScheduleKind.hourly,
          BackupScheduleKind.daily,
          BackupScheduleKind.weekly,
          BackupScheduleKind.monthly,
        };
        autoBackupAnnualAtClose.value = true;
      });
    });

    testWidgets('بطاقة النسخ الآلي: المفتاح والخانات الثلاث والكشف المتقدم '
        'والتنبيه البارز عند الإيقاف — وبألسنة الغياب الصادقة بلا مركز',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final managerId = await db.createManager(
          name: 'المالك', login: 'owner', passwordHash: 's:h');
      await db.setCurrentUserId(managerId);

      await tester.pumpWidget(MaterialApp(home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah_s233/dummy.db',
        onRestored: () {},
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // الوصول بالتمرير (درس D-098 — البطاقة أول قسم النسخ).
      for (var i = 0;
          i < 14 &&
              find.byKey(const ValueKey('settings_auto_backup'))
                  .evaluate()
                  .isEmpty;
          i++) {
        await tester.drag(
            find.byType(ListView).first, const Offset(0, -300));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('settings_auto_backup')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('settings_auto_backup_master')),
          findsOneWidget);
      // الخانات الثلاث ظاهرة والمتقدمة خلف الكشف.
      expect(find.byKey(const ValueKey('settings_auto_backup_hourly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('settings_auto_backup_daily')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('settings_auto_backup_monthly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('settings_auto_backup_weekly')),
          findsNothing,
          reason: 'الأسبوعي خلف «خيارات متقدمة»');
      // ألسنة الحالة بلا مركز (اختبار): الغياب الصادق لا صمت مفسر.
      expect(find.textContaining('آخر نسخة ناجحة'), findsOneWidget);
      expect(find.textContaining('الموعد القادم'), findsOneWidget);
      expect(find.textContaining('الحصة'), findsOneWidget);

      // الكشف المتقدم يظهر الأسبوعي والسنوي — الإظهار قبل الضغط (قد يكون
      // زر الكشف خارج الشاشة ببناء الكاش) ثم السحب إليهما أولاً (بطاقة
      // النسخ الآلي أعلى القسم وصفوفهما أسفل البطاقة فخارج نطاق البناء
      // الأولي — درسا السرد الكسول عينهما).
      await tester.ensureVisible(find.text('خيارات متقدمة'));
      await tester.pump();
      await tester.tap(find.text('خيارات متقدمة'));
      await tester.pump();
      for (var i = 0;
          i < 10 &&
              find.byKey(const ValueKey('settings_auto_backup_weekly'))
                  .evaluate()
                  .isEmpty;
          i++) {
        await tester.drag(
            find.byType(ListView).first, const Offset(0, -200));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('settings_auto_backup_weekly')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('settings_auto_backup_annual')),
          findsOneWidget);

      // الإيقاف يعرض التنبيه البارز — والإظهار قبل الضغط ثالثاً (المفتاح
      // أعلى البطاقة والسحب الأخضر هبط بعيداً عنه).
      Future<void> tapMaster() async {
        await tester.ensureVisible(
            find.byKey(const ValueKey('settings_auto_backup_master')));
        await tester.pump();
        await tester.tap(
            find.byKey(const ValueKey('settings_auto_backup_master')));
        await tester.pump();
      }

      await tapMaster();
      expect(
          find.byKey(const ValueKey('settings_auto_backup_off_warning')),
          findsOneWidget,
          reason: 'تنبيه التذكير البارز عند إيقاف النسخ الآلي');
      // إعادة التفعيل يخفيه.
      await tapMaster();
      expect(
          find.byKey(const ValueKey('settings_auto_backup_off_warning')),
          findsNothing);
    });
  });

  group('س233/D-233: شاشة البدء ومؤشرا الحالة', () {
    testWidgets('الحد الأدنى نصف ثانية: لا كشف قبله ولو اكتمل الافتتاح — '
        'ولو بعد تجاوزه', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester.pumpWidget(MaterialApp(
          home: AppGate(
              db: db,
              splashMinimum: const Duration(milliseconds: 500))));
      await tester.pump();
      // الافتتاح بالذاكرة أسرع من نصف الثانية — الشاشة باقية بعده.
      expect(find.byType(DiqqahSplash), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(DiqqahSplash), matching: find.text('دِقَّة')),
          findsOneWidget,
          reason: 'اسم التطبيق بشاشة البدء');
      expect(
          find.descendant(
              of: find.byType(DiqqahSplash),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(DiqqahSplash), findsOneWidget,
          reason: 'قبل مرور نصف الثانية لا كشف');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(DiqqahSplash), findsNothing,
          reason: 'بعد مرور الحد الأدنى الكشف حاصل');
      expect(find.text('إنشاء المدير'), findsOneWidget);
    });

    testWidgets('الحقن الاختباري بالصفر: لا انتظار أصلاً (عرف الحقن)',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester.pumpWidget(
          MaterialApp(home: AppGate(db: db, splashMinimum: Duration.zero)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DiqqahSplash), findsNothing);
      expect(find.text('إنشاء المدير'), findsOneWidget);
    });

    testWidgets('مؤشرا الحالة بتذييل الرئيسية: النسخ يعمل بلا مركز — '
        'والمزامنة صامتة بلا دفتر انضمام — والإيقاف يظهر بالرقاقة',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');
      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('النسخ الآلي: يعمل'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('النسخ الآلي: يعمل'), findsOneWidget,
          reason: 'رقاقة النسخ داخل طبقة التذييل القائمة');
      expect(find.text('المزامنة: مفعلة'), findsNothing,
          reason: 'صمت غير المفعلة — لا رقاقة بلا دفتر انضمام');
      expect(find.byKey(const ValueKey('home_status_chips')), findsOneWidget);

      // إيقاف النسخ الآلي يقلب الرقاقة فوراً (الخيار حي بلا إقلاع).
      autoBackupEnabled.value = false;
      addTearDown(() => autoBackupEnabled.value = true);
      await tester.pump();
      expect(find.text('النسخ الآلي: متوقف'), findsOneWidget);
      // التذييل باقٍ بست طبقاته (س209) — الرقاقات داخل طبقته القائمة.
      expect(find.byKey(const ValueKey('home_footer')), findsOneWidget);
    });
  });
}
