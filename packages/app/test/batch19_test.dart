import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/settings_screen.dart';

import 'test_guard.dart';

/// اختبارات دفعة (19) — صيغة الترقيم الجديدة D-169 (س56 بلفظ المالك
/// «الصيغة التي اقترحتها أنا عليك»): بطاقة «ترقيم المستندات» بالإعدادات
/// بمعاينتها الحية وحفظها المدقق 3..8 — الافتراضي 6 ومثال المالك بعرض 5
/// «2600001» — والخارج عن النطاق يُرفض برسالة عربية بلا كتابة.
///
/// الضخ المباشر للشاشة (نمط batch18 مع invoices_screen) — والقاعدة
/// `inMemorySyncClose` حصراً وضخّات محدودة (درس س22..س26).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('D-169: بطاقة الترقيم بالإعدادات — الافتراضي 6 بمعاينته، '
      'وحفظ 5 يسري على القاعدة، والخارج عن النطاق يُرفض برسالة عربية',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah_batch19/dummy.db',
        onRestored: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ترقيم المستندات (D-169)'), findsOneWidget);
    // الافتراضي 6 نافذ والمعاينة به (رقم 1 من سنة اليوم بعرض 6)
    expect(find.textContaining('معاينة: «فاتورة بيع 26000001»'),
        findsOneWidget);

    // حفظ عرض 5 — مثال المالك نفسه — والمعاينة الحية قبله
    await tester.enterText(
        find.widgetWithText(TextField, 'عدد خانات العدّاد بعد السنة (3–8)'),
        '5');
    await tester.pump();
    expect(find.textContaining('فاتورة بيع 2600001'), findsOneWidget,
        reason: 'المعاينة الحية بمثال المالك «2600001»');
    await tester.tap(find.text('حفظ عدد خانات العدّاد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await db.counterWidth(), 5,
        reason: 'الضبط مخزون في app_meta ويقرؤه التوليد عند كل ترحيل');

    // الخارج عن النطاق (9) يُرفض برسالة عربية بلا كتابة
    await tester.enterText(
        find.widgetWithText(TextField, 'عدد خانات العدّاد بعد السنة (3–8)'),
        '9');
    await tester.pump();
    await tester.tap(find.text('حفظ عدد خانات العدّاد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('بين 3 و 8'), findsOneWidget);
    expect(await db.counterWidth(), 5,
        reason: 'الرفض بلا مساس بالقيمة المحفوظة');
  });
}
