import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/backup_center.dart' show kAppVersion;
import 'package:diqqah_app/boxes_screen.dart';
import 'package:diqqah_app/context_menu.dart';
import 'package:diqqah_app/orders_screen.dart';
import 'package:diqqah_app/roles_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات س208 — الدفعة 2 «الاتساق» (بنود نقاش المالك المعتمد +
/// القرارات الست الموثقة بالجلسة): قائمة السياق الموحدة س207 على شاشات
/// النمط الجديدة (السندات والأدوار والصناديق — والمستودعات باختبارها
/// المخصص warehouses_screen_test) وم06 التكيفي على الطلبات — ثغرة
/// التكيف الموثقة تنقضي، وتوحيد قاعدة الفلترة الموثقة بالنمط.
///
/// نسخ المعرّف بمحاكاة قناة الحافظة الموثقة (درس س207: «القناة غير
/// المُجابة تعلّق المستقبل للأبد»)، والضغط الطويل بشجرة نظيفة مستقلة
/// وضخّات الحركة الثلاث قبل لمس القائمة المنبثقة (درس الجلسة الموثق:
/// القوائم لا تستقبل اللمس قبل اكتمال حركة دخولها)، والوصول بالتمرير
/// لا الافتراض (درس D-098) — والفحص على العرض الواسع بدقة 1.0 بنمط
/// batch27/28/30 الموثق (س206).
void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('س208-1: قائمة سياق س207 على سند القائمة — طباعة السند '
      'ونسخ المعرّف والبشّارة الموثقة', (tester) async {
    // محاكاة قناة الحافظة — بيئة الاختبار بلا منصة فالقناة غير
    // المُجابة تعلّق المستقبل للأبد (درس الجلسة الموثق س207).
    String? mockClipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          mockClipboard = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return mockClipboard == null ? null : {'text': mockClipboard};
      }
      return null;
    });

    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // تبويب السندات نشط افتراضياً — أول صف هو سند الضخ المبذر
    await tester.longPress(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('طباعة السند'), findsOneWidget);
    expect(find.text('نسخ المعرّف'), findsOneWidget);

    await tester.tap(find.text('نسخ المعرّف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('نُسخ المعرّف إلى الحافظة'), findsOneWidget);
    expect(mockClipboard, isNotNull);
  });

  testWidgets('س208-2: قائمة سياق س207 على دور الأدوار — أذونات الدور '
      'تفتح حوار المضيف القائم والإلغاء لا مساس', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: RolesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.longPress(find.text('مدير'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('أذونات الدور'), findsOneWidget);
    expect(find.text('نسخ المعرّف'), findsOneWidget);

    await tester.tap(find.text('أذونات الدور'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('أذونات الدور «مدير»'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('أذونات الدور «مدير»'), findsNothing);
  });

  testWidgets('س208-3: قائمة سياق س207 على صندوق القائمة — التعطيل '
      'للنشط حصراً ويفتح تأكيد المضيف والتراجع لا مساس', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: BoxesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.longPress(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تعطيل الصندوق'), findsOneWidget);
    expect(find.text('نسخ المعرّف'), findsOneWidget);

    await tester.tap(find.text('تعطيل الصندوق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تعطيل الصندوق؟'), findsOneWidget);

    await tester.tap(find.text('تراجع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تعطيل الصندوق؟'), findsNothing);
    final active = await db.customSelect(
      'SELECT is_active FROM accounts WHERE id = '
      "(SELECT account_id FROM cash_boxes WHERE name = 'الصندوق الرئيسي')",
    ).getSingle();
    expect(active.data['is_active'], 1);
  });

  testWidgets('س208-4: م06 التكيفي على قائمة السندات والطلبات — العريض '
      'يتوسّط بهامش نصف الفائض (1600 - 800) / 2 = 400', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    // (أ) قائمة السندات على العريض — بطاقة الصف تبدأ من 400
    _bigView(tester);
    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.getRect(find.byType(RecordContextMenu).first).left, 400);

    // (ب) الطلبات — ثغرة م06 الموثقة تنقضي: المسودة تُبذر بالقاعدة
    // مباشرةً بنمط _seedSaleDraft الموثق س123-1 — فالقياس للتكيف
    // البصري لا لإنشاء النموذج، والبذر الحتمي أصوب عرف الجلسات.
    tester.view.reset();
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    final unitId = await db
        .customSelect('SELECT id FROM units ORDER BY id LIMIT 1')
        .getSingle();
    final oilId = await db
        .customSelect('SELECT id FROM items ORDER BY id LIMIT 1')
        .getSingle();
    final customerId = await db
        .customSelect("SELECT id FROM parties WHERE kind = 'customer' "
            'ORDER BY id LIMIT 1')
        .getSingle();
    final warehouseId = await db
        .customSelect('SELECT id FROM warehouses ORDER BY id LIMIT 1')
        .getSingle();
    await db.createOrderDraft(OrderDraft(
      direction: OrderDirection.sale,
      partyId: customerId.data['id'] as int,
      warehouseId: warehouseId.data['id'] as int,
      orderDate: '$year-03-15',
      expectedDate: '$year-03-20',
      narration: 'أمر دورة الاختبار',
      lines: [
        OrderLineDraft(
            itemId: oilId.data['id'] as int,
            unitId: unitId.data['id'] as int,
            qty: 10,
            qtyBase: 10,
            unitPriceMinor: 40000),
      ],
    ));

    _bigView(tester);
    await tester.pumpWidget(
        MaterialApp(home: OrdersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RecordContextMenu), findsWidgets,
        reason: 'القائمة تعرض المسودة المبذرة قبل القياس');
    expect(
        tester.getRect(find.byType(RecordContextMenu).first).left, 400);
  });

  test('الإصدار الموحد: pubspec يطابق كتالوج الإصدار (س208 — البنية '
      'بلا تثبيت صلب — انتقل التثبيت الصلب إلى s209 بنمط انتقاله '
      'من s207 إلى s208)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((l) => l.startsWith('version:'));
    expect(line, 'version: $kAppVersion');
  });
}
