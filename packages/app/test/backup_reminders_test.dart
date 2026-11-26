/// اختبار تذكيرات النسخ الذكية — الواجهة الأغنى (دفعة 2 من نظام
/// النسخ، تكليف 2026-11-13 §3/§8-8/§10-1): البناء النقي لصفوف التذكير
/// برسائلها الحية (عدد الأيام وتواريخ آخر نسخة ونسبة الحصة) وترتيب
/// الأولوية، ولوحة العرض بأزرار فعلها المحقونة — بمعزل عن المركز
/// والشاشة معاً (ValueNotifier مُدار بالاختبار لا singleton).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/backup_center.dart';
import 'package:diqqah_app/backup_reminders.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 10, 0);

  BackupHealth health({
    DateTime? lastAnyUtc,
    bool stale30 = false,
    bool attachments = false,
    DateTime? latestWithImagesUtc,
    double quota = 0,
    bool hourlyQuota = false,
    bool hourlyBattery = false,
    String? failure,
  }) =>
      BackupHealth(
        lastAnyUtc: lastAnyUtc,
        noBackupFor30Days: stale30,
        attachmentsStale: attachments,
        latestWithImagesUtc: latestWithImagesUtc,
        quotaUsedFraction: quota,
        hourlySkippedQuota: hourlyQuota,
        hourlySkippedBattery: hourlyBattery,
        failureMessage: failure,
        computedAtUtc: now,
      );

  group('بناء التذكيرات — نقي بلا واجهة', () {
    test('سليم: بلا أي صف — الحماية حديثة والحصة دون العتبة', () {
      final rs = buildBackupReminders(
          health(lastAnyUtc: now.subtract(const Duration(hours: 2))));
      expect(rs, isEmpty);
    });

    test('30 يوماً: الرسالة بعدد الأيام الحقيقي وتاريخ آخر نسخة', () {
      final rs = buildBackupReminders(health(
        lastAnyUtc: now.subtract(const Duration(days: 40)),
        stale30: true,
      ));
      expect(rs, hasLength(1));
      expect(rs.single.id, BackupReminderId.stale30);
      expect(rs.single.severity, BackupReminderSeverity.urgent);
      expect(rs.single.message, contains('40 يوماً'));
      expect(rs.single.message, contains('(2026-10-05)'));
      expect(rs.single.action, BackupReminderAction.createNowWithImages);
    });

    test('بلا أي نسخة: لغة الغياب الصريحة لا تاريخ فارغ', () {
      final rs = buildBackupReminders(health(stale30: true));
      expect(rs.single.message, contains('لم تُنشأ أي نسخة احتياطية بعد'));
    });

    test('المرفقات: تاريخ آخر نسخة تضمها في الرسالة', () {
      final rs = buildBackupReminders(health(
        lastAnyUtc: now,
        attachments: true,
        latestWithImagesUtc: DateTime.utc(2026, 11, 1),
      ));
      expect(rs.single.id, BackupReminderId.attachments);
      expect(rs.single.message, contains('2026-11-01'));
      expect(rs.single.actionLabel, 'أنشئ نسخة الآن (مع المرفقات)');
    });

    test('المرفقات بلا أي نسخة تضمها: لغة الغياب', () {
      final rs = buildBackupReminders(
          health(lastAnyUtc: now, attachments: true));
      expect(rs.single.message,
          contains('لم تدخل أي نسخة تضم المرفقات بعد'));
    });

    test('حصة 85%: تحذير عتبة 80% بالنسبة الحية', () {
      final rs =
          buildBackupReminders(health(lastAnyUtc: now, quota: 0.85));
      expect(rs.single.id, BackupReminderId.quotaWarn);
      expect(rs.single.message, contains('85%'));
      expect(rs.single.action, BackupReminderAction.openCatalog);
    });

    test('تخطي الساعية بالحصة (≥95%): يغني عن تحذير 80% المتكرر — صف واحد',
        () {
      final rs = buildBackupReminders(
          health(lastAnyUtc: now, quota: 0.96, hourlyQuota: true));
      expect(rs, hasLength(1));
      expect(rs.single.id, BackupReminderId.hourlyQuota);
      expect(rs.single.message, contains('96%'));
    });

    test('تخطي السارية بالبطارية: معلوماتي بلا زر', () {
      final rs = buildBackupReminders(
          health(lastAnyUtc: now, hourlyBattery: true));
      expect(rs.single.id, BackupReminderId.hourlyBattery);
      expect(rs.single.severity, BackupReminderSeverity.info);
      expect(rs.single.action, BackupReminderAction.none);
    });

    test('الفشل أول الصفوف ورسالته حرفية من الشارة', () {
      final rs = buildBackupReminders(
          health(lastAnyUtc: now, quota: 0.9, failure: 'انكسر قفل الملف'));
      expect(rs.first.id, BackupReminderId.failure);
      expect(rs.first.message, contains('انكسر قفل الملف'));
    });

    test('الترتيب الثابت بالأولوية الموثقة', () {
      final rs = buildBackupReminders(health(
        lastAnyUtc: now.subtract(const Duration(days: 35)),
        stale30: true,
        attachments: true,
        latestWithImagesUtc: DateTime.utc(2026, 10, 1),
        quota: 0.9,
        hourlyBattery: true,
        failure: 'خطأ',
      ));
      expect(rs.map((r) => r.id).toList(), [
        BackupReminderId.failure,
        BackupReminderId.stale30,
        BackupReminderId.attachments,
        BackupReminderId.quotaWarn,
        BackupReminderId.hourlyBattery,
      ]);
    });
  });

  group('لوحة التذكيرات — عرض', () {
    Widget wrap(BackupRemindersPanel panel) => MaterialApp(
          home: Scaffold(
            body: ListView(children: [panel]),
          ),
        );

    testWidgets('حالة سليمة: سطر أخضر هادئ بتاريخ آخر نسخة', (tester) async {
      final n = ValueNotifier<BackupHealth?>(
          health(lastAnyUtc: DateTime.utc(2026, 11, 14, 8)));
      await tester.pumpWidget(wrap(BackupRemindersPanel(
        healthListenable: n,
        onCreateNow: () async {},
        onOpenCatalog: () {},
      )));
      expect(find.textContaining('بحماية سليمة'), findsOneWidget);
      expect(find.textContaining('2026-11-14'), findsOneWidget);
      expect(find.text('أنشئ نسخة الآن'), findsNothing);
    });

    testWidgets('تذكير 30 يوماً: «أنشئ نسخة الآن» يستدعي الإنشاء',
        (tester) async {
      final n = ValueNotifier<BackupHealth?>(health(
        lastAnyUtc: now.subtract(const Duration(days: 33)),
        stale30: true,
      ));
      var created = 0;
      await tester.pumpWidget(wrap(BackupRemindersPanel(
        healthListenable: n,
        onCreateNow: () async {
          created++;
        },
        onOpenCatalog: () {},
      )));
      await tester.tap(find.text('أنشئ نسخة الآن'));
      await tester.pump();
      expect(created, 1);
    });

    testWidgets('تذكير المرفقات: زره المميز يستدعي الإنشاء ونصه بالتاريخ',
        (tester) async {
      final n = ValueNotifier<BackupHealth?>(health(
        lastAnyUtc: now,
        attachments: true,
        latestWithImagesUtc: DateTime.utc(2026, 11, 1),
      ));
      var created = 0;
      await tester.pumpWidget(wrap(BackupRemindersPanel(
        healthListenable: n,
        onCreateNow: () async {
          created++;
        },
        onOpenCatalog: () {},
      )));
      expect(find.textContaining('2026-11-01'), findsOneWidget);
      await tester.tap(find.text('أنشئ نسخة الآن (مع المرفقات)'));
      await tester.pump();
      expect(created, 1);
    });

    testWidgets('تحذير الحصة: «افتح الكتالوج» يستدعي الفتح', (tester) async {
      final n = ValueNotifier<BackupHealth?>(
          health(lastAnyUtc: now, quota: 0.82));
      var opened = 0;
      await tester.pumpWidget(wrap(BackupRemindersPanel(
        healthListenable: n,
        onCreateNow: () async {},
        onOpenCatalog: () {
          opened++;
        },
      )));
      await tester.tap(find.text('افتح الكتالوج'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('busy يعطّل زر الإنشاء — الضغط لا يستدعي', (tester) async {
      final n = ValueNotifier<BackupHealth?>(health(
        lastAnyUtc: now.subtract(const Duration(days: 31)),
        stale30: true,
      ));
      var created = 0;
      await tester.pumpWidget(wrap(BackupRemindersPanel(
        healthListenable: n,
        busy: true,
        onCreateNow: () async {
          created++;
        },
        onOpenCatalog: () {},
      )));
      await tester.tap(find.text('أنشئ نسخة الآن'));
      await tester.pump();
      expect(created, 0);
    });

    testWidgets('الشارة null (وضع الاختبار): اللوحة خفية تماماً',
        (tester) async {
      final n = ValueNotifier<BackupHealth?>(null);
      await tester.pumpWidget(wrap(BackupRemindersPanel(
        healthListenable: n,
        onCreateNow: () async {},
        onOpenCatalog: () {},
      )));
      expect(find.textContaining('النسخ الاحتياطي'), findsNothing);
      expect(find.textContaining('بحماية سليمة'), findsNothing);
    });

    testWidgets('اللوحة تتجدد لحظة تجدد الشارة — بلا إعادة بناء الشاشة',
        (tester) async {
      final n = ValueNotifier<BackupHealth?>(health(
        lastAnyUtc: DateTime.utc(2026, 11, 14, 8),
      ));
      await tester.pumpWidget(wrap(BackupRemindersPanel(
        healthListenable: n,
        onCreateNow: () async {},
        onOpenCatalog: () {},
      )));
      expect(find.textContaining('بحماية سليمة'), findsOneWidget);
      // الشارة تجددت (نسخة جديدة ثم تقادم طويل) — الصف يظهر فوراً.
      n.value = health(
        lastAnyUtc: now.subtract(const Duration(days: 45)),
        stale30: true,
      );
      await tester.pump();
      expect(find.textContaining('بحماية سليمة'), findsNothing);
      expect(find.textContaining('45 يوماً'), findsOneWidget);
    });
  });
}
