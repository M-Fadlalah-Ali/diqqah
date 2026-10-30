import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/roles_screen.dart';

/// اختبارات شاشة الصلاحيات — دفعة (6-ج) على السيناريو المعروض س-94
/// (D-097 معروض): عرض قراءة حصراً للأدوار والمستخدمين — الجداول جاهزة
/// من م0 (roles/app_users) والمدير الأول يزرع دوره عند التهيئة (س-01).
void main() {
  EditableText.debugDeterministicCursor = true;

  testWidgets('D-097: الأدوار والمستخدمون ظاهرة قراءةً — والدور المزروع '
      '«مدير» بعدد مستخدميه', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(MaterialApp(home: RolesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('مدير'), findsOneWidget);
    expect(find.textContaining('1 مستخدم'), findsOneWidget);
    expect(find.text('المالك'), findsOneWidget);
    expect(find.textContaining('دخوله: owner'), findsOneWidget);
  });

  testWidgets('D-093 إفصاحاً: لافتة «العرض قراءة حصراً» ظاهرة — ولا زر '
      'إنشاء أدوار في الشاشة أصلاً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(MaterialApp(home: RolesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('العرض قراءة حصراً'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: 'شاشة عرض لا إنشاء — الإدارة التفصيلية دفعة تالية بيد المالك');
  });
}
