import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/app_theme.dart';
import 'package:diqqah_app/backup_center.dart' show kAppVersion;
import 'package:diqqah_app/context_menu.dart';
import 'package:diqqah_app/import_screen.dart';

import 'test_guard.dart';

/// اختبارات دفعة تنظيف ويندوز — س207 (بنود نقاش المالك المعتمد
/// 2026-11-22):
/// - **بند 1**: حفظ القوالب باسم على سطح المكتب — نافذة الحفظ المحقونة
///   تكتب المسار وتعرض بشّارته، والإلغاء لا شيء (عرف «إلغاء — لا شيء»).
/// - **بند 2**: قائمة السياق الموحدة — الزر الثانوي على سطح المكتب
///   يفتح قائمة بنود المضيف القائمة حصراً وتنفّذ فعاليته.
/// - **بند 3**: الضغطة الطويلة تفتح القائمة ذاتها — مصدر واحد لا
///   اثنان — والغلاف الفارغ لا يفتح قائمة أصلاً.
/// - **بند 4**: قواعد التلميح المركزية بالثيمين — تأخير 500ms وثلاث
///   ثوانٍ وفوق الأيقونة لا تحت فلا تلميح يغطي اسم ظاهر.
/// - **بند 5**: عبارة «السعر مكبَّر» بالإرشاد الرقمي غائبة بشاشة
///   العملات — تنظيف نصي لا مساس بالآلية الوظيفية حرفاً.
///
/// نمط القاعدة `inMemorySyncClose` وضخّات محدودة لا pumpAndSettle
/// عند مؤقتات دورية (درس س22..س26) — والقوائم المنسدلة بلا مؤقت دوري
/// فالاستقرار بضخّاتها الثلاث ثم pumpAndSettle آمن موثق بالجلسة.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('بند 1 — تنزيل القالب بسطح المكتب يحفظ بنافذة الحفظ '
      'المحقونة ويعرض بشّارة المسار', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    String? savedName;
    String? savedCsv;
    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        saveOverride: (fileName, csv) async {
          savedName = fileName;
          savedCsv = csv;
          return '/tmp/$fileName';
        },
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('تنزيل قالب فارغ'));
    await tester.pump();

    // الاسم بنمط الدالة الموثق والقيمة بترميزها المعتمد (BOM أولها).
    expect(savedName, 'diqqah-import-parties-v1.csv');
    expect(savedCsv, isNotNull);
    expect(savedCsv!.codeUnits.first, 0xFEFF,
        reason: 'BOM أول النص بعرف F-166');
    expect(savedCsv, contains('dq-import:parties,1'));
    expect(find.textContaining('حُفظ القالب: /tmp/'), findsOneWidget);
  });

  testWidgets('بند 1 — إلغاء نافذة الحفظ لا يعرض بشّارة الحفظ '
      '(إلغاء — لا شيء)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        saveOverride: (fileName, csv) async => null,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('تنزيل قالب فارغ'));
    await tester.pump();

    expect(find.textContaining('حُفظ القالب'), findsNothing);
  });

  testWidgets('بند 2 — الزر الثانوي يفتح قائمة بنود المضيف وتنفّذ '
      'فعاليته', (tester) async {
    var detailsOpened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (pageContext) {
          return RecordContextMenu(
            actions: [
              RecordContextAction(
                label: 'تفاصيل',
                icon: Icons.description_outlined,
                onSelected: () => detailsOpened = true,
              ),
              copyIdAction(pageContext, 7),
            ],
            child: const ListTile(title: Text('سجل تجريبي')),
          );
        }),
      ),
    ));
    await tester.pump();

    // الزر الثانوي — عرف سطح المكتب.
    await tester.tap(find.text('سجل تجريبي'),
        buttons: kSecondaryMouseButton);
    // إتمام حركة دخول القائمة بضخّات محدودة ثم استقرارها — فالroute
    // لا يستقبل اللمس قبل اكتمال الحركة (درس الجلسة الموثق).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل'), findsOneWidget);
    expect(find.text('نسخ المعرّف'), findsOneWidget);

    await tester
        .tap(find.byType(PopupMenuItem<RecordContextAction>).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(detailsOpened, isTrue,
        reason: 'فعالية المضيف القائمة حصراً نفّذت بنقرة البند');
  });

  testWidgets('بند 3 — الضغطة الطويلة تفتح القائمة ذاتها بمصدر واحد',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (pageContext) {
          return RecordContextMenu(
            actions: [
              RecordContextAction(
                label: 'تفاصيل',
                icon: Icons.description_outlined,
                onSelected: () {},
              ),
              copyIdAction(pageContext, 7),
            ],
            child: const ListTile(title: Text('سجل تجريبي')),
          );
        }),
      ),
    ));
    await tester.pump();

    // الضغطة الطويلة — عرف أندرويد، والقائمة ذاتها بمحتواها وترتيبها.
    await tester.longPress(find.text('سجل تجريبي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل'), findsOneWidget);
    expect(find.text('نسخ المعرّف'), findsOneWidget);
  });

  testWidgets('بند 2 — الغلاف الفارغ لا يفتح قائمة أصلاً',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RecordContextMenu(
          actions: const [],
          child: const ListTile(title: Text('بند بلا سياق')),
        ),
      ),
    ));
    await tester.pump();

    await tester.longPress(find.text('بند بلا سياق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(PopupMenuItem<Object>), findsNothing);
    expect(find.byType(PopupMenuEntry<Object>), findsNothing);
  });

  testWidgets('بند 2 — فعالية نسخ المعرّف تكتب الحافظة وتشرش البشّارة',
      (tester) async {
    // محاكاة قناة الحافظة — بيئة الاختبار بلا منصة فالقناة غير
    // المُجابة تعلّق المستقبل للأبد (درس الجلسة الموثق).
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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (pageContext) {
          return ListTile(
            title: Text('نسخ'),
            onTap: () => copyIdAction(pageContext, 7).onSelected(),
          );
        }),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('نسخ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final clip = await Clipboard.getData('text/plain');
    expect(clip?.text, '7');
    expect(mockClipboard, '7');
    expect(find.text('نُسخ المعرّف إلى الحافظة'), findsOneWidget);
  });

  test('بند 4 — قواعد التلميح المركزية بالثيمين', () {
    for (final theme in [
      buildLightTheme('test'),
      buildDarkTheme('test'),
    ]) {
      final tooltip = theme.tooltipTheme;
      expect(tooltip.waitDuration, const Duration(milliseconds: 500));
      expect(tooltip.showDuration, const Duration(seconds: 3));
      expect(tooltip.preferBelow, isFalse,
          reason: 'التلميح فوق الأيقونة فلا يغطي اسمها الظاهر');
      expect(kTooltipWaitDuration, const Duration(milliseconds: 500));
      expect(kTooltipShowDuration, const Duration(seconds: 3));
    }
  });

  test('بند 5 — عبارة السعر المكبَّر بالإرشاد الرقمي غائبة بشاشة '
      'العملات', () {
    final source = File('lib/currencies_screen.dart').readAsStringSync();
    // النص المعنى حرفاً: التسمية الإرشادية بالرقم — والعبارة بلسان
    // رسالة التحقق الوظيفية بحقل المدخل خارج البند.
    expect(source.contains('مكبَّر ×1,000,000'), isFalse,
        reason: 'التنظيف النصي المعتمد — والآلية الوظيفية باقية حرفاً');
  });

  test('الإصدار الموحد: pubspec يطابق كتالوج الإصدار (س207 — البنية '
      'بلا تثبيت صلب بعد انتقال التثبيت إلى اختبار س208)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((l) => l.startsWith('version:'));
    expect(line, 'version: $kAppVersion');
  });
}
