import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/roles_screen.dart';

/// اختبارات شاشة الصلاحيات بوضع الكتابة الكامل — دفعة إغلاق النواة
/// (س37، F-080/D-100 معروض): الأدوار النمطية الأربعة مزروعة بأذوناتها،
/// وإنشاء أدوار مخصصة، وتعديل أذونات دور، وتعيين دور لمستخدم.
void main() {
  EditableText.debugDeterministicCursor = true;

  Future<void> open(WidgetTester tester, DiqqahDatabase db) async {
    await tester.pumpWidget(MaterialApp(home: RolesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('F-080: الأدوار الأربعة الافتراضية ظاهرة بأذوناتها — '
      'والمدير بمستخدمه', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    await open(tester, db);

    expect(find.text('مدير'), findsOneWidget);
    expect(find.text('محاسب'), findsOneWidget);
    expect(find.text('أمين مستودع'), findsOneWidget);
    expect(find.text('بائع'), findsOneWidget);
    // أذونات المدير النجمة بلخصها العربي
    expect(find.textContaining('الأذونات: كل الوحدات'), findsOneWidget);
    // درس السرد الكسول: المستخدمون أسفل الأدوار الأربعة خارج نافذة البناء
    // — تمرير قبل الفحص لا فحص الغائب.
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.textContaining('1 مستخدم'), findsOneWidget);
    expect(find.text('المالك'), findsOneWidget);
    expect(find.textContaining('دخوله: owner'), findsOneWidget);
  });

  testWidgets('D-100: إنشاء دور مخصص من الحوار بوحدتين — يظهر بالقائمة '
      'بأذوناته مرتبة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    await open(tester, db);

    await tester.tap(find.byTooltip('دور جديد'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الدور'), 'كاشير');
    await tester.tap(find.text('الأطراف'));
    await tester.pump();
    await tester.tap(find.text('الفواتير'));
    await tester.pump();
    await tester.tap(find.text('إنشاء الدور'));
    await tester.pumpAndSettle();

    expect(find.text('كاشير'), findsOneWidget);
    // الصياغة بترتيب مفاتيح الوحدات (parties قبل invoices) — والحكم بالنص
    // الحرفي الكامل لا textContaining جزئياً (درس س35: بائع يحمل الجزء نفسه)
    expect(find.text('0 مستخدم · الأذونات: الأطراف، الفواتير'),
        findsOneWidget);
  });

  testWidgets('D-100: تعديل أذونات دور قائم — أمين المستودع يضيف الأطراف '
      'فتظهر بأذوناته المحفوظة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    await open(tester, db);

    final roleTile = find.ancestor(
      of: find.text('أمين مستودع'),
      matching: find.byType(ListTile),
    ).first;
    await tester.tap(
      find.descendant(of: roleTile, matching: find.byTooltip('تعديل الأذونات')),
    );
    await tester.pumpAndSettle();

    // الأذونات الافتراضية معبأة (الأصناف والتقارير اليومية) — نضيف الأطراف
    await tester.tap(find.text('الأطراف'));
    await tester.pump();
    await tester.tap(find.text('حفظ الأذونات'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('الأذونات: الأطراف، الأصناف، التقارير اليومية'),
      findsOneWidget,
    );
  });

  testWidgets('D-100: تعيين دور لمستخدم — المالك يُحوَّل إلى دور «بائع» '
      'فتظهر بلسان قائمته', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');

    await open(tester, db);

    // درس السرد الكسول: بلاط المستخدمين أسفل الأدوار الأربعة غير مبنية
    // خارج النافذة — تمرير أولاً ثم مسك الزر
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    final userTile = find.ancestor(
      of: find.text('المالك'),
      matching: find.byType(ListTile),
    ).first;
    await tester.tap(
      find.descendant(of: userTile, matching: find.byTooltip('تغيير الدور')),
    );
    await tester.pumpAndSettle();

    // قائمة الأدوار تفتح — اختيار «بائع» (الظاهر الثاني بعد بند القائمة
    // المغلق) ثم تعيين
    await tester.tap(find.text('مدير').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بائع').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعيين'));
    await tester.pumpAndSettle();

    expect(find.textContaining('دور: بائع'), findsOneWidget);
  });
}
