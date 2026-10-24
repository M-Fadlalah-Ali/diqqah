import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heseb_storage/heseb_storage.dart';
import 'package:heseb_app/main.dart';

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

  testWidgets('القائمة الهيكلية كلها معطلة (F-016) — لا نقر يفتح شيئاً',
      (tester) async {
    final db = HesebDatabase.inMemory();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(HesebApp(db: db));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(tiles.length, 14); // 13 وحدة + الإعدادات
    for (final tile in tiles) {
      expect(tile.enabled, isFalse, reason: 'كل وحدات F-016 معطلة');
    }
  });
}
