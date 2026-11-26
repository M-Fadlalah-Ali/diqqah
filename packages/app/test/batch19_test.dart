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


  /// تكليف 2026-11-13: بطاقة «النسخ المجدول» الجديدة أعلى الإعدادات
  /// تُخرج بطاقة الترقيم من أول نافذة البناء — درس السرد الكسول
  /// (س35/س36): تمرير قبل الفحص لا فحص الغائب.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    // س213 (D-218): بطاقة الترقيم انتقلت إلى قسم «العمليات» آخر
    // القائمة — حلقة أعمق بنمط D-098 لتغطي الموضع الجديد.
    for (var i = 0; i < 30 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
  }

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

    await scrollTo(tester, 'ترقيم المستندات');
    expect(find.text('ترقيم المستندات'), findsOneWidget);
    // الافتراضي 6 نافذ والمعاينة به (رقم 1 من سنة اليوم بعرض 6)
    expect(find.textContaining('معاينة: «فاتورة بيع 26000001»'),
        findsOneWidget);

    // ═══ الحالة الأولى: الرفض — قبل وجود أي إشعار في الحياة ═══
    // درس الجولتين 163/164 الموثق: الإشعار عائده 4 ثوان ويغطي أسفل
    // الشاشة فيبتلع نقرات ما بعده (سلسلة Overlay/AbsorbPointer في نتيجة
    // الاصطدام بسجل الجولة 164) — فالرفض يُختبر أولًا والإبراز قبل كل
    // نقرة عرف الجولة 160.
    await tester.enterText(
        find.widgetWithText(TextField, 'عدد خانات العدّاد بعد السنة (3–8)'),
        '9');
    await tester.pump();
    await tester.ensureVisible(find.text('حفظ عدد خانات العدّاد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ عدد خانات العدّاد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('بين 3 و 8'), findsOneWidget);
    expect(await db.counterWidth(), 6,
        reason: 'الرفض بلا كتابة — الافتراضي باقٍ');

    // ═══ الحالة الثانية: حفظ 5 — بعد انقضاء إشعار الرفض حتماً ═══
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('بين 3 و 8'), findsNothing,
        reason: 'حارس: إشعار الرفض انقضى فلا يغطي الزر');
    await tester.enterText(
        find.widgetWithText(TextField, 'عدد خانات العدّاد بعد السنة (3–8)'),
        '5');
    await tester.pump();
    expect(find.textContaining('فاتورة بيع 2600001'), findsOneWidget,
        reason: 'المعاينة الحية بمثال المالك «2600001»');
    await tester.ensureVisible(find.text('حفظ عدد خانات العدّاد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ عدد خانات العدّاد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await db.counterWidth(), 5,
        reason: 'الضبط مخزون في app_meta ويقرؤه التوليد عند كل ترحيل');
  });
}
