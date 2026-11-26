/// اختبار قسم إدارة التخزين المستقل (د-4/د-8 — §25.8، س136): الصفوف
/// الستة، والأرضية موثقة نصاً، والتنظيف الذكي يقترح لا يحذف — والتنفيذ
/// بتأكيد مزدوج يبقي الأرضية.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/backup_center.dart';
import 'package:diqqah_app/storage_manager_screen.dart';

import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  const password = 'mgr-123';

  late Directory tempDir;
  late String dbPath;
  late DiqqahDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_storage_t_');
    dbPath = p.join(tempDir.path, 'diqqah.db');
    db = DiqqahDatabase.fileSyncClose(
        filePath: dbPath,
        passwordUpgradeIterations: PasswordHasher.legacyIterations);
    final hasher =
        PasswordHasher(iterations: PasswordHasher.legacyIterations);
    final salt = PasswordHasher.newSalt();
    final stored = '$salt:${hasher.hash(password, salt)}';
    final userId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: stored);
    await db.setCurrentUserId(userId);
  });

  tearDown(() async {
    await BackupCenter.instance?.shutdown();
    BackupCenter.instance = null;
    try {
      await db.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// نمط widget_test الموثق (درس CI الجولة 128): I/O الملفات الحقيقي
  /// داخل المنطقة الزائفة يكتمل بنوافذ runAsync متتالية مع ضخ حتى
  /// يتحقق الشرط — مهلة 60×50ms.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: StorageManagerScreen(db: db, dbPath: dbPath)));
    for (var i = 0; i < 60; i++) {
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('الصفوف الستة كلها ظاهرة والأرضية موثقة نصاً',
      (tester) async {
    await open(tester);
    expect(find.text('قاعدة البيانات'), findsOneWidget);
    expect(find.text('المرفقات (الصور)'), findsOneWidget);
    expect(find.text('النسخ الاحتياطية حسب النوع'), findsOneWidget);
    expect(find.text('السجلات'), findsOneWidget);
    expect(find.text('الملفات المؤقتة'), findsOneWidget);
    expect(find.text('التطبيق'), findsOneWidget);
    expect(find.textContaining('الأرضية النظامية'), findsOneWidget);
    // العبارة تظهر بالتنبيه العلوي وبسطر السجلات معاً.
    expect(find.textContaining('append-only'), findsWidgets);
  });

  testWidgets('بلا ازدحام → لا اقتراح حذف', (tester) async {
    await tester.runAsync(() => BackupCenter.start(
          db: db,
          dbPath: dbPath,
          quotaBytes: 1024 * 1024 * 1024, // سقف كبير — الاستعمال لا يقاربه.
          batteryProvider: () async => 100,
          scheduleTimer: false,
        ));
    await open(tester);
    // بطاقة التنظيف أسفل الصفوف — التمرير أولاً (القائمة الكسولة س125).
    await tester.scrollUntilVisible(find.textContaining('لا ازدحام'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('لا ازدحام'), findsOneWidget);
    expect(find.text('عرض اقتراح الحذف'), findsNothing);
  });

  testWidgets('ازدحام → اقتراح معروض بلا حذف صامت، والتنفيذ بتأكيد مزدوج',
      (tester) async {
    // سقف صغير يجعل النسخ الواقعية فوق العتبة — والساعتان تعطيان
    // أرضية ساعية محمية وأقدم قابلة للحذف.
    var minute = 0;
    await tester.runAsync(() => BackupCenter.start(
          db: db,
          dbPath: dbPath,
          quotaBytes: 10000, // 10KB — كل نسخة واقعية أكبر منه.
          nowUtcProvider: () => DateTime.utc(2026, 11, 14, 10, ++minute),
          nowLocalProvider: () => DateTime(2026, 11, 14, 12),
          batteryProvider: () async => 100,
          scheduleTimer: false,
        ));
    // نسختان ساعتان صريحتان: أقدم قابلة وأحدث أرضية.
    final store = BackupCenter.instance!.store!;
    await tester.runAsync(() async {
      await store.createScheduled(db, BackupScheduleKind.hourly,
          atUtc: DateTime.utc(2026, 11, 14, 9));
      await store.createScheduled(db, BackupScheduleKind.hourly,
          atUtc: DateTime.utc(2026, 11, 14, 10));
    });

    final before = store.catalog.entries.length;
    await open(tester);

    // الاقتراح ظاهر بأسمائه (عدد وحجم) — ولم يُحذف شيء بحذف صامت
    // — والتمرير أولاً (بطاقة التنظيف أسفل الصفوف).
    // سحب حتى أسفل القائمة مع الاستقرار — بطاقة التنظيف آخر عنصر.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('عرض اقتراح الحذف'), findsOneWidget);
    expect(store.catalog.entries.length, before);

    await tester.tap(find.text('عرض اقتراح الحذف'));
    await tester.pump(const Duration(milliseconds: 300));

    // قائمة الاقتراح: تفاصيل مرئية وزر متابعة.
    expect(find.text('تنظيف ذكي — اقتراح حذف'), findsOneWidget);
    await tester.tap(find.text('متابعة'));
    await tester.pump(const Duration(milliseconds: 300));

    // التأكيد النهائي.
    expect(find.text('تأكيد نهائي'), findsOneWidget);
    await tester.tap(find.text('نعم، احذف الآن'));
    // التنفيذ I/O ملفي حقيقي — استطلاع بنوافذ runAsync حتى يكتمل حذف
    // المقترح كله (النمط الموثق — درس CI الجولة 128) — والأرضية
    // الباقية ساعية واحدة هي الدليل.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (store.catalog.entriesFor(BackupScheduleKind.hourly).length ==
          1) break;
    }
    await tester.pump(const Duration(milliseconds: 200));

    // الأقدم سقط والأرضية باقية — وأرضية الساعية هي نسخة اللحاق
    // (بتوقيتها الواقعي — اللحاق لا يأخذ الساعة المحقونة) فهي الأحدث
    // بعد صريحتَي الاختبار اللتين حُذفتا فوق الأرضية.
    final after = store.catalog.entries;
    expect(after.length, lessThan(before));
    final hourly = store.catalog.entriesFor(BackupScheduleKind.hourly);
    expect(hourly, hasLength(1));
    expect(hourly.single.atUtc.isAfter(DateTime.utc(2026, 11, 14, 10)),
        isTrue);
  });
}
