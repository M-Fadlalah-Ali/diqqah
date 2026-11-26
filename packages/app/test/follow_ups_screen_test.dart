import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/follow_ups_screen.dart';
import 'package:diqqah_app/import_screen.dart';

import 'test_guard.dart';

/// اختبارات الواجهة لدفعة أرصدة أول المدة والمتابعات (س141 — د-7/§25.9):
/// شاشة المتابعات بمحمّلها المحقون وأفعالها المحقونة (نمط لوحة b39 —
/// ما يُختبر هو ما يُشغَّل)، وشاشة الاستيراد بأقسامها الأربعة وحقل
/// تاريخ الافتتاحي بتحققه الحي (DQ-1026/DQ-1025 — د-6).
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  FollowUpsSnapshot snapshotOf(FollowUpsInput input) =>
      FollowUpsSnapshot(input, buildFollowUps(input));

  group('شاشة المتابعات — لوحة فوق مصادرها بأفعال محقونة', () {
    testWidgets('المصادر الفارغة: الحالة الهادئة لا قائمة ميتة', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester.pumpWidget(MaterialApp(home: FollowUpsScreen(
        db: db,
        loadOverride: () async => snapshotOf(const FollowUpsInput()),
      )));
      await tester.pump();
      expect(find.text('المتابعات'), findsOneWidget);
      expect(find.text('لا متابعات الآن — كل شيء متابَع'), findsOneWidget);
    });

    testWidgets('البنود السبعة تُعرض بشداتها وأزرار أفعالها', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      final input = const FollowUpsInput(
        openingUndistributedBaseMinor: 250000,
        importEventsAwaitingReview: 1,
        partiesAutoCreated: 3,
        emergencyCopiesCount: 4,
        rollbackWindowOpen: true,
        fiscalYearStartText: '2026-01-01',
        quotaUsedFraction: 0.82,
      );
      await tester.pumpWidget(MaterialApp(home: FollowUpsScreen(
        db: db,
        loadOverride: () async => snapshotOf(input),
      )));
      await tester.pump();
      await tester.pump();
      expect(find.text('قيود افتتاحية تحتاج إعادة تصنيف'), findsOneWidget);
      expect(find.text('أُنشئ تلقائياً بالاستيراد — للمراجعة'), findsOneWidget);
      expect(find.text('نسخ طوارئ متراكمة وإدارة التخزين'), findsOneWidget);
      // أسفل الطية — سحب القائمة الكسولة قبل التحقق (درس س35/س36).
      for (var i = 0;
          i < 6 && find.text('نافذة التراجع عن الاستعادة مفتوحة').evaluate().isEmpty;
          i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
      }
      expect(find.text('نافذة التراجع عن الاستعادة مفتوحة'), findsOneWidget);
      expect(find.text('تاريخ بداية السنة المالية — للإقرار أو التعديل'),
          findsOneWidget);
      expect(find.text('تعديل التاريخ من شاشة الفترات'), findsOneWidget);
      // البند الأخير أعمق — سحب أخير له، والقائمة كسولة فلا تُعد
      // أزرار البطاقات كلها مبناة ب آن واحد (درس س35/س36).
      for (var i = 0;
          i < 6 && find.text('التخزين تجاوز عتبة التحذير').evaluate().isEmpty;
          i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
      }
      expect(find.text('التخزين تجاوز عتبة التحذير'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsAtLeastNWidgets(1));
    });

    testWidgets('تأكيد المراجعة يستدعي المحقون ثم يعيد التحميل', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      var confirmed = 0;
      var reloads = 0;
      var input = const FollowUpsInput(
          importEventsAwaitingReview: 1, partiesAutoCreated: 2);
      await tester.pumpWidget(MaterialApp(home: FollowUpsScreen(
        db: db,
        loadOverride: () async {
          reloads++;
          return snapshotOf(input);
        },
        onConfirmReview: () async {
          confirmed++;
          input = const FollowUpsInput(); // رُوجع كل شيء فلا متابعات.
        },
      )));
      await tester.pump();
      await tester.pump();
      expect(find.text('أُنشئ تلقائياً بالاستيراد — للمراجعة'),
          findsOneWidget);
      await tester.tap(find.text('راجع ثم أكّد'));
      await tester.pump();
      await tester.pump();
      expect(confirmed, 1);
      expect(reloads, greaterThan(1),
          reason: 'الفعل يعيد تحميل المصادر بعد الأثر');
      expect(find.text('لا متابعات الآن — كل شيء متابَع'), findsOneWidget);
    });
  });

  group('شاشة الاستيراد — القالبان الافتتاحيان (الوحدتان 4 و5)', () {
    testWidgets('أربعة أقسام وحقل التاريخ يظهر للافتتاحيين حصراً (د-6)',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester
          .pumpWidget(MaterialApp(home: ImportScreen(db: db)));
      await tester.pump();
      expect(find.text('الأطراف'), findsOneWidget);
      expect(find.text('الأصناف'), findsOneWidget);
      expect(find.text('أرصدة الذمم'), findsOneWidget);
      expect(find.text('الافتتاحي الكامل'), findsOneWidget);
      // حقل التاريخ غائب بالقالبين الأولين…
      expect(find.text('تاريخ القيد الافتتاحي (YYYY-MM-DD)'), findsNothing);
      await tester.tap(find.text('أرصدة الذمم'));
      await tester.pump();
      expect(find.text('تاريخ القيد الافتتاحي (YYYY-MM-DD)'),
          findsOneWidget);
      // …وافتراضه بداية أقدم فترة مفتوحة من القاعدة الحية.
      final field = find
          .widgetWithText(TextField, 'تاريخ القيد الافتتاحي (YYYY-MM-DD)');
      final controller = (tester.widget<TextField>(field)).controller!;
      expect(controller.text, await db.earliestOpenPeriodStartText());
    });

    testWidgets('التحقق الحي: تاريخ فاسد يعرض DQ-1026 لحظة الكتابة',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester
          .pumpWidget(MaterialApp(home: ImportScreen(db: db)));
      await tester.pump();
      await tester.tap(find.text('أرصدة الذمم'));
      await tester.pump();
      final field = find
          .widgetWithText(TextField, 'تاريخ القيد الافتتاحي (YYYY-MM-DD)');
      await tester.enterText(field, '2026-13-99');
      await tester.pump();
      expect(find.textContaining('(DQ-1026)'), findsOneWidget);
      await tester.enterText(field, '2026-01-01');
      await tester.pump();
      expect(find.textContaining('(DQ-1026)'), findsNothing);
    });

    testWidgets('س142 (§25.10): ما لا يُستورد يُقال صراحة بالواجهة دائماً',
        (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester
          .pumpWidget(MaterialApp(home: ImportScreen(db: db)));
      await tester.pump();
      // س186 (تنظيف م08): نُزع مرجع البند من نص الشاشة فنُزع من التوقع
      expect(find.text('ما لا يُستورد بهذا المسار (صراحة كاملة)'),
          findsOneWidget);
      expect(find.textContaining('دليل الحسابات: إعداد ثابت يدوياً'),
          findsOneWidget);
      expect(find.textContaining('استيراد أرصدة لا ترحيل تاريخي'),
          findsOneWidget);
    });

    testWidgets('س142 (§25.4): اصطلاح الإشارات موثق حيث يُدخل — '
        'للافتتاحيين حصراً', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await tester
          .pumpWidget(MaterialApp(home: ImportScreen(db: db)));
      await tester.pump();
      expect(find.textContaining('اصطلاح الإشارات'), findsNothing,
          reason: 'بالقالبين الأولين لا أرصدة فلا اصطلاح');
      await tester.tap(find.text('الافتتاحي الكامل'));
      await tester.pump();
      expect(find.textContaining('اصطلاح الإشارات'), findsOneWidget);
      expect(find.textContaining('سالب رصيد العميل رصيد دائن'),
          findsOneWidget);
    });
  });
}
