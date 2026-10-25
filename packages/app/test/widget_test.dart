import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;

import 'package:heseb_domain/heseb_domain.dart';
import 'package:heseb_storage/heseb_storage.dart';
import 'package:heseb_app/main.dart';
import 'package:heseb_app/settings_screen.dart';

void main() {
  testWidgets('التدفق الكامل (س-01): أول تشغيل → إنشاء المدير → الشاشة الهيكلية',
      (tester) async {
    final db = HesebDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(HesebApp(db: db, hasherIterations: 2));
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
    final db = HesebDatabase.inMemory();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(HesebApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('إنشاء المدير'), findsNothing);
    expect(find.text('حسيب'), findsOneWidget); // AppBar الهيكلية
    expect(find.text('الأصناف'), findsOneWidget);
  });

  testWidgets('F-016/س-01: 13 وحدة معطلة والإعدادات وحدها متاحة — تفتح '
      'شاشة النسخ الاحتياطي (F-012 متاحة فوراً بعد التهيئة)', (tester) async {
    final db = HesebDatabase.inMemory();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(HesebApp(db: db));
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

  testWidgets('F-012: زر النسخ في الإعدادات ينتج ملف نسخة في مجلد القاعدة',
      (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('heseb_settings_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'heseb.db');
    final db = HesebDatabase(filePath: dbPath);
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
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();

    final backups = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('heseb-backup-'))
        .toList();
    expect(backups, hasLength(1));
    final bytes = await backups.first.readAsBytes();
    expect(BackupCipher.identify(bytes), BackupKind.plainSqlite);
    // حوار النتيجة ظهر للمستخدم
    expect(find.text('أُنشئت النسخة الاحتياطية'), findsOneWidget);
  });

  testWidgets('F-013: الاستعادة بتأكيد مزدوج — والإلغاء في أي تأكيد لم يحدث شيئاً',
      (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('heseb_restore_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'heseb.db');
    final db = HesebDatabase(filePath: dbPath);
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
      files.where((f) => p.basename(f.path).startsWith('heseb-before-restore-')),
      isEmpty,
      reason: 'الإلغاء الآمن لا يلتقط لقطة ولا يمس شيئاً',
    );
  });
}
