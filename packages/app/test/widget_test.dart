import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/settings_screen.dart';

void main() {
  testWidgets('التدفق الكامل (س-01): أول تشغيل → إنشاء المدير → الشاشة الهيكلية',
      (tester) async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(DiqqahApp(db: db, hasherIterations: 2));
    await tester.pumpAndSettle();

    // F-014: شاشة إنشاء المدير إلزامية قبل أي شاشة أخرى
    expect(find.text('إنشاء المدير'), findsOneWidget);
    expect(find.text('الأطراف'), findsNothing);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'المالك');
    await tester.enterText(fields.at(1), 'owner');
    await tester.enterText(fields.at(2), 'secret123');

    await tester.tap(find.text('إنشاء المدير'));
    await tester.pumpAndSettle();

    // F-016: بعد التهيئة تُفتح الشاشة الهيكلية بقائمة وحدات معطلة
    expect(find.text('المالك'), findsNothing); // لا معلومات المستخدم على الشاشة
    expect(find.text('الأطراف'), findsOneWidget);
    expect(find.text('المزامنة'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(14)); // 13 وحدة + الإعدادات

    // F-015: device_id وُلد خلال التهيئة وأصبح في القاعدة
    expect(await db.deviceId(), hasLength(36));
  });

  testWidgets('قاعدة فيها مدير: الشاشة الهيكلية مباشرة — لا شاشة أولى',
      (tester) async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('إنشاء المدير'), findsNothing);
    expect(find.text('دِقَّة'), findsOneWidget); // AppBar الهيكلية
    expect(find.text('الأصناف'), findsOneWidget);
  });

  testWidgets('F-016/س-01: 13 وحدة معطلة والإعدادات وحدها متاحة — تفتح '
      'شاشة النسخ الاحتياطي (F-012 متاحة فوراً بعد التهيئة)', (tester) async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(tiles.length, 14); // 13 وحدة + الإعدادات
    final locked = tiles.where((t) => t.enabled != true).length;
    expect(locked, 13, reason: 'كل وحدات F-016 معطلة في م0');
    final open = tiles.where((t) => t.enabled == true).length;
    expect(open, 1, reason: 'الإعدادات وحدها متاحة — س-01');

    // الإعدادات بند 14 خارج الشاشة الافتراضية — تمرير ثم فتح
    await tester.scrollUntilVisible(
      find.text('الإعدادات'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    expect(find.text('النسخ الاحتياطي الكامل (F-012)'), findsOneWidget);
    expect(find.text('الاستعادة الكاملة (F-013)'), findsOneWidget);
  });

  testWidgets('F-012 + D-050: زر النسخ بكلمة مرور ينتج نسخة مشفرة في مجلد القاعدة',
      (tester) async {
    // IO متزامن — بيئة testWidgets الوهمية لا تكمل عمليات الملفات غير المتزامنة
    final tempDir = Directory.systemTemp.createTempSync('diqqah_settings_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase(filePath: dbPath);
    addTearDown(db.close);
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-001',
            name: 'بضاعة',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 0,
            salePriceMinor: 500,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-w-001',
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    // D-050: التشفير مشدود افتراضياً من م1 — النسخة بكلمة مرور
    await tester.enterText(
      find.widgetWithText(TextField, 'كلمة مرور النسخة المشفرة'),
      'سر-النسخة',
    );
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    // النسخ فيها IO حقيقي متسلسل (VACUUM ← قراءة ← كتابة) لا يكمله الوقت
    // الوهمي — نوازن ضخ الوقت الواقعي مع ضخ الإطارات حتى يظهر حوار النجاح.
    // علّة CI (2026-10-29): رصد «ظهور أي ملف» يلتقط المؤقت .tmp الذي يولده
    // VACUUM INTO — اسمه يطابق بادئة النسخة وهو خام دائماً قبل اكتمال
    // التشفير، فقرأه الاختبار على عدّاد CI البطيء وظنه الناتج. إشارة
    // الاكتمال الصحيحة حوار النجاح: لا يظهر إلا بعد كتابة الملف النهائي
    // وحذف المؤقت — نمط D-056 الذي سلم على CI نفسه.
    final successTitle = find.text('أُنشئت النسخة الاحتياطية');
    var shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة لم يظهر خلال مهلة الاختبار');

    final backups = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('diqqah-backup-'))
        .toList();
    expect(backups, hasLength(1));
    final bytes = backups.first.readAsBytesSync();
    // D-050: الافتراضي من م1 نسخة مشفرة لا خام
    expect(BackupCipher.identify(bytes), BackupKind.encrypted);
    // DoD F-012: الملف أُنتج من الزر — وبلا رسالة فشل على الشاشة
    expect(find.textContaining('تعذر إنشاء النسخة'), findsNothing);
  });

  testWidgets('D-050: النسخ بكلمة مرور فارغة يُوقف بتنبيه — والإلغاء الواعي '
      'للتشفير يفتح تحذيراً ثم ينتج نسخة خام', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_d050_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase(filePath: dbPath);
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    List<File> backups() => tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('diqqah-backup-'))
        .toList();

    // (أ) التشفير مشدود وكلمة المرور فارغة → تنبيه ولا ملف
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    expect(find.textContaining('أدخل كلمة مرور النسخة المشفرة'), findsOneWidget);
    expect(backups(), isEmpty, reason: 'بلا كلمة مرور لا تُنشأ نسخة');

    // (ب) الإلغاء الواعي: فك التشفير → تحذير صريح → تراجع أولاً لا شيء
    await tester.tap(find.text('تشفير النسخة بكلمة مرور'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'كلمة مرور النسخة المشفرة'),
        findsNothing); // حقل كلمة المرور يختفي
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    expect(find.text('نسخة بدون تشفير'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(backups(), isEmpty, reason: 'التراجع من التحذير لا ينتج شيئاً');

    // (ج) متابعة بدون تشفير بوعي → نسخة خام
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة بدون تشفير'));
    // إشارة الاكتمال حوار النجاح لا «ظهور أي ملف» — المؤقت .tmp يطابق
    // اسم النسخة وقد يُلتقط قبل اكتمال الكتابة أو يُرى معها معاً فتزدهم
    // hasLength — علّة CI 2026-10-29 وهششة كامنة في هذا الموضع.
    final successTitle = find.text('أُنشئت النسخة الاحتياطية');
    var shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة لم يظهر خلال مهلة الاختبار');
    expect(backups(), hasLength(1));
    expect(
      BackupCipher.identify(backups().single.readAsBytesSync()),
      BackupKind.plainSqlite,
    );
  });

  testWidgets('D-056: زرا التصفح والإخراج في شاشة الإعدادات — إصلاح قيد '
      'أندرويد على مسار data (استيراد منتقي النظام + تصدير نافذة المشاركة)',
      (tester) async {
    // IO متزامن — نفس نمط اختبار F-012 أعلاه
    final tempDir = Directory.systemTemp.createTempSync('diqqah_d056_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase(filePath: dbPath);
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    // زر التصفح بجوار حقل المسار (suffixIcon) — لا قنوات منصة في وجوده
    expect(find.byTooltip('اختيار ملف النسخة'), findsOneWidget);

    // زر الإخراج يظهر في حوار نجاح النسخة — وجوده لا يستدعي أي قناة منصة
    // D-050: النسخة مشفرة افتراضياً من م1 — كلمة مرور قبل الزر
    await tester.enterText(
      find.widgetWithText(TextField, 'كلمة مرور النسخة المشفرة'),
      'سر-النسخة',
    );
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    // نفس درس F-012 أعلاه: سلسلة IO حقيقية ثم دفع الحوار — حلقة توازن
    // (وقت واقعي ← إطار ← فحص) حتى يظهر الحوار، بلا توقيت مفترض (Task 50).
    final successTitle = find.text('أُنشئت النسخة الاحتياطية');
    var shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة لم يظهر خلال مهلة الاختبار');

    expect(find.text('أُنشئت النسخة الاحتياطية'), findsOneWidget);
    expect(find.text('إخراج النسخة'), findsOneWidget);
    expect(find.text('حسناً'), findsOneWidget);
  });

  testWidgets('F-013: الاستعادة بتأكيد مزدوج — والإلغاء في أي تأكيد لم يحدث شيئاً',
      (tester) async {
    // IO متزامن — بيئة testWidgets الوهمية لا تكمل عمليات الملفات غير المتزامنة
    final tempDir = Directory.systemTemp.createTempSync('diqqah_restore_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase(filePath: dbPath);
    addTearDown(db.close);
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-LIVE',
            name: 'بضاعة الحية',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 0,
            salePriceMinor: 1,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-w-live',
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'مسار ملف النسخة الاحتياطية'),
      p.join(tempDir.path, 'غير-موجود.db'),
    );
    // زر الاستعادة تحت الخط المرئي — حقل التشفير وصندوقه أضافا ارتفاعاً
    // فيكفي سحب أعمق (D-050: البطاقة أطول من م0)
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استعادة…'));
    await tester.pumpAndSettle();

    // التأكيد الأول — إلغاء
    expect(find.text('استعادة نسخة احتياطية؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('استعادة نسخة احتياطية؟'), findsNothing);

    // الثانية — إلغاء آمن أيضاً: لا حوار استبدال ولا لقطة ولا خطأ
    await tester.tap(find.text('استعادة…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();
    expect(find.text('التأكيد الأخير'), findsOneWidget);
    await tester.tap(find.text('إلغاء آمن'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.items).get();
    expect(rows, hasLength(1));
    expect(rows.first.sku, 'SKU-LIVE');
    final files = tempDir.listSync().whereType<File>().toList();
    expect(
      files.where((f) => p.basename(f.path).startsWith('diqqah-before-restore-')),
      isEmpty,
      reason: 'الإلغاء الآمن لا يلتقط لقطة ولا يمس شيئاً',
    );
  });
}
