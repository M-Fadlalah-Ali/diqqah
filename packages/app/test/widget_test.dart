import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/parties_screen.dart';
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

  testWidgets('F-016: الأطراف فُتحت بدفعة م1 (1) مع الإعدادات — والبقية معطلة؛\n'
      'وفتح الأطراف يفتح شاشتها والبحث فيها يعمل', (tester) async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(tiles.length, 14); // 13 وحدة + الإعدادات
    final locked = tiles.where((t) => t.enabled != true).length;
    expect(locked, 12,
        reason: 'الأطراف فُتحت بدفعة م1 (1) — والبقية (11 وحدة) معطلة');
    final open = tiles.where((t) => t.enabled == true).length;
    expect(open, 2, reason: 'الأطراف (دفعة م1 (1)) والإعدادات (س-01)');

    // الأطراف فوق الخط الافتراضي — تمرير ثم فتح ثم رجوع
    await tester.scrollUntilVisible(
      find.text('الأطراف'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('الأطراف'));
    // ضخّات محدودة لا pumpAndSettle: مؤشر انتظار شاشة الأطراف (StreamBuilder)
    // يتحرك حتى يصدر التدفق فلا تستقر قبله (علّة CI 2026-10-29 — تعليق 40+ د).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا أطراف بعد — أضف أول طرف بزر «إضافة طرف»'),
        findsOneWidget);
    expect(find.byType(PartiesScreen), findsOneWidget);
  });

  testWidgets('F-012 + D-050 + D-060: زر النسخ ينتج نسخة مشفرة بمفتاح البرنامج في مجلد القاعدة',
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

    // D-060: التشفير مشدود افتراضياً — النسخة بمفتاح البرنامج بلا أي كلمة:
    // لا حقل كلمة مرور أصلاً، والنقر على الزر يكفي.
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
    // D-061: النسخة بلاحقة البرنامج الخاصة لا .db
    expect(p.basename(backups.first.path), endsWith('.diqqah'));
    final bytes = backups.first.readAsBytesSync();
    // D-050/D-060: الافتراضي من م1 نسخة مشفرة بمفتاح البرنامج لا خام —
    // وبايتة الإصدار 2 تثبت الجيل الجديد حصراً
    expect(BackupCipher.identify(bytes), BackupKind.encrypted);
    expect(bytes[7], BackupCipher.formatVersion);
    // DoD F-012: الملف أُنتج من الزر — وبلا رسالة فشل على الشاشة
    expect(find.textContaining('تعذر إنشاء النسخة'), findsNothing);
  });

  testWidgets('D-050 + D-060: الإلغاء الواعي للتشفير يفتح تحذيراً — والتراجع '
      'لا ينتج شيئاً ثم النسخة الخام ثم المشفرة بمفتاح البرنامج', (tester) async {
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

    // (أ) الإلغاء الواعي: فك التشفير → تحذير صريح → تراجع أولاً لا شيء
    // (D-060: صندوق التشفير بلا أي حقل كلمة مرور بعده)
    await tester.tap(find.text('تشفير النسخة بمفتاح البرنامج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    expect(find.text('نسخة بدون تشفير'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(backups(), isEmpty, reason: 'التراجع من التحذير لا ينتج شيئاً');

    // (ب) متابعة بدون تشفير بوعي → نسخة خام
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

    // (ج) رجوع التشفير بوعي → نسخة مشفرة بمفتاح البرنامج (جيل v2)
    await tester.tap(find.text('حسناً')); // إغلاق حوار النجاح أولاً
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشفير النسخة بمفتاح البرنامج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة الثانية لم يظهر');
    expect(backups(), hasLength(2));
    final encryptedBlob = backups()
        .map((f) => f.readAsBytesSync())
        .firstWhere(
            (b) => BackupCipher.identify(b) == BackupKind.encrypted);
    expect(encryptedBlob[7], BackupCipher.formatVersion);
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
    // D-060: النسخة مشفرة بمفتاح البرنامج افتراضياً — بلا أي حقل كلمة
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
