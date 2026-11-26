import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/warehouses_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات شاشة المستودعات — أول ملف اختبار مخصص لها (س208 — الدفعة 2
/// «الاتساق» بنص ملاحظة المالك المعتمدة: «عالج ملاحظتك حول قائمة
/// المستودع»): القائمة بنمط شاشة القائمة المرجعي — بطاقة بقائمة سياق
/// س207 بفعاليات المضيف القائمة حصراً ونسخ المعرّف، والحالة الفارغة
/// بلسان فعل، والهامش التكيفي م06.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26) — والحكم البايتي بالقاعدة لا بنصٍّ عائم (درس س35).
/// درس السرد الكسول (D-098/س35): ListView يبني الظاهر حصراً — وصول
/// الصف بالتمرير قبل لمسه، والضغط الطويل بشجرة نظيفة مستقلة (درس س207).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets(
      'س208: قائمة المستودعات تعرض المبذر نشطاً وسجل التحويلات '
      'فارغاً بلسان فعل، وإنشاء مستودع بالحوار يظهر بشارته وبالقاعدة',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المستودع المبذر بنشاطه الموثق
    expect(find.text('المستودع الرئيسي'), findsOneWidget);
    expect(find.text('نشط — يظهر في اختيارات الإدخال'), findsOneWidget);
    // س208: الحالة الفارغة بلسان فعل — زر التحويل فوقها ظاهر
    expect(
        find.text('لا تحويلات بعد — ابدأ بتحويل بين مستودعين'), findsOneWidget);

    // الإنشاء بالحوار — زر الشريط العلوي بعرف درس س36
    await tester.tap(find.text('مستودع جديد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextField, 'اسم المستودع'), 'مستودع الفرع');
    await tester.tap(find.text('إنشاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بطاقة النجاح بنمط الصناديق: تبقى حتى الإجراء التالي
    expect(
        find.textContaining('أُنشئ المستودع «مستودع الفرع»'), findsOneWidget);

    final rows = await db
        .customSelect(
          'SELECT name FROM warehouses WHERE is_deleted = 0 ORDER BY id',
        )
        .get();
    expect(rows, hasLength(2));
    expect(rows.last.data['name'], 'مستودع الفرع');
  });

  testWidgets(
      'س208: قائمة سياق س207 على سجل المستودع — فعاليات المضيف '
      'القائمة حصراً (إعادة التسمية ونسخ المعرّف) والتراجع لا مساس',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الوصول بالتمرير لا الافتراض (درس D-098) ثم الضغط الطويل
    // (درس س207: الضغط الطويل بشجرة نظيفة مستقلة)
    final whTile = find.text('المستودع الرئيسي');
    await tester.scrollUntilVisible(whTile, 200,
        scrollable: find.byType(Scrollable));
    await tester.pump();
    await tester.longPress(whTile);
    // درس الجلسة الموثق: القوائم لا تُقبل اللمس قبل اكتمال حركة
    // دخولها — ضغّات ثلاثة ثم استقرار.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('إعادة تسمية'), findsOneWidget);
    expect(find.text('نسخ المعرّف'), findsOneWidget);

    // اختيار إعادة التسمية يفتح حوار المضيف القائم — والتراجع لا مساس
    await tester.tap(find.text('إعادة تسمية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.textContaining('إعادة تسمية «المستودع الرئيسي»'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('إعادة تسمية «المستودع الرئيسي»'), findsNothing);
    final name = await db
        .customSelect(
          'SELECT name FROM warehouses WHERE is_deleted = 0 ORDER BY id',
        )
        .getSingle();
    expect(name.data['name'], 'المستودع الرئيسي');
  });

  testWidgets(
      'س208: تعطيل مستودع برصيد قائم يرفضه المحرك برسالته — '
      'والفارغ يُعطّل ويظهر بشارته والقاعدة تحكم نشاطيه', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    // مستودع فرع فارغ أولاً — يبقى الرئيسي نشطاً فلا حارس «آخر نشط»
    await tester.pumpWidget(MaterialApp(home: WarehousesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('مستودع جديد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم المستودع'), 'مستودع الفرع');
    await tester.tap(find.text('إنشاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المبذر برصيد قائم (8 وحدات زيت بعد الدورة المعروفة) — المحرك يمنع
    await tester.scrollUntilVisible(find.text('المستودع الرئيسي'), 200,
        scrollable: find.byType(Scrollable));
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('تعطيل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('برصيد قائم — تعطيله غير آمن'), findsOneWidget);

    // الفارغ يُعطّل ويظهر بشارته (الصدق أولاً)
    await tester.scrollUntilVisible(find.text('مستودع الفرع'), 200,
        scrollable: find.byType(Scrollable));
    await tester.pump();
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('تعطيل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('عُطّل المستودع «مستودع الفرع»'), findsNothing,
        reason: 'بطاقة النجاح أعلى القائمة وبناها الكسول لا يبنيها '
            'خارج النافذة بعد التمرير للفرع (درس D-098) — والحكم '
            'بالقاعدة تحت');
    expect(find.text('معطل — لا يظهر في اختيارات الإدخال'), findsOneWidget);

    final rows = await db
        .customSelect(
          'SELECT name, is_active FROM warehouses '
          'WHERE is_deleted = 0 ORDER BY id',
        )
        .get();
    expect(rows.first.data['is_active'], 1,
        reason: 'المبذر باقياً نشطاً — الرفض لا يبدل القائمة');
    expect(rows.last.data['is_active'], 0);
  });
}
