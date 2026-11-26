import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/orders_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات س202 (بأمر المالك «قم بتنفيذ المطلوب 1-5»):
/// م1: تصفية صفوف التوزيع الصفرية — علّة الدفع الجزئي الموثقة (دفع 325
///     فأُلزم إعادة الإدخال مرات لأن الصفوف غير الممسوسة كانت تُرسل
///     فيرفضها حرس المجال «أكبر من صفر»).
/// م2: بلاطتا المبيعات والمشتريات وفلتر الجهة — الأرشيف بجهته من أول
///     لحظة وورقة الإدخال بنوعَي الجهة، والمعايد الأرشيف المحايد
///     بورقته الرباعية حارس توافق المداخل الأخرى.
/// م3: التوجيه بالمفتاح لا بالنص — التسميتان المختصرتان «الوحدات»
///     و«الطلبات» تفتحان شاشتيهما بعنوانيهما الكاملين.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق).
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  group('س202 م1: تصفية صفوف التوزيع الصفرية — علّة الدفع الجزئي', () {
    test('الصفرية تُصفى والموجبة تبقى بترتيبها وبقيمها', () {
      final rows = liveVoucherAllocations([
        (11, 0),
        (12, 32500),
        (13, 0),
        (14, 750),
      ]);
      expect(rows, hasLength(2),
          reason: 'الصفان الملموسان حصراً — والصفرية لا تُرسل');
      expect(rows[0].invoiceId, 12);
      expect(rows[0].appliedDocMinor, 32500);
      expect(rows[1].invoiceId, 14);
      expect(rows[1].appliedDocMinor, 750);
    });

    test('الكل صفرية ← مسودة بلا توزيعات فلا رفض «أكبر من صفر»', () {
      expect(liveVoucherAllocations([(21, 0), (22, 0)]), isEmpty);
    });

    test('السالب يُصفى مع الصفر — والحرس المجالي باقٍ على ما يعبر', () {
      final rows = liveVoucherAllocations([(31, -500), (32, 100)]);
      expect(rows, hasLength(1));
      expect(rows.single.invoiceId, 32);
      expect(rows.single.appliedDocMinor, 100);
    });

    test('الفراغ يعيد الفراغ — السند بلا مطابقات بلسانه القائم', () {
      expect(liveVoucherAllocations(const []), isEmpty);
    });
  });

  group('س202 م2: فلتر الجهة بالأرشيف وورقة الإدخال بإدراك الجهة', () {
    testWidgets('بلاطة المبيعات تفتح الأرشيف بفلتر جهته — البيع ظاهر '
        'والشراء غائب والمنسدل بجهته من أول لحظة', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await seedKnownCycle(db);

      await tester.pumpWidget(MaterialApp(
          home:
              InvoicesScreen(db: db, initialSide: InvoiceArchiveSide.sales)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('المبيعات'), findsOneWidget,
          reason: 'عنوان الجهة بلسان بلاطتها (س202)');
      expect(find.text('المبيعات كلها (البيع ومردوده)'), findsOneWidget,
          reason: 'الفلتر مضبوط بجهة البلاطة قبل أي لمس — واللسان بجهة '
              'الأرشيف بعقد س221 (عزل النوع: «الكل» فيها جهتها كلها)');
      expect(find.textContaining('فاتورة بيع 26000001'), findsOneWidget);
      expect(find.textContaining('فاتورة شراء 26000001'), findsNothing,
          reason: 'جهة المبيعات لا تُرى بالشراء — فلتر الجهة من التخزين');
    });

    testWidgets('ورقة الإدخال بجهة المشتريات نوعاها حصراً', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);

      await tester.pumpWidget(MaterialApp(
          home: InvoicesScreen(
              db: db, initialSide: InvoiceArchiveSide.purchases)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('المشتريات'), findsOneWidget);

      await tester.tap(find.text('فاتورة جديدة'));
      await tester.pumpAndSettle();
      expect(find.text('فاتورة شراء'), findsOneWidget);
      expect(find.text('مردود شراء'), findsOneWidget);
      expect(find.text('فاتورة بيع'), findsNothing,
          reason: 'ورقة الجهة نوعاها حصراً — المشتريات بشرائها ومردودها');
      expect(find.text('مردود بيع'), findsNothing);
    });

    testWidgets('الأرشيف المحايد بورقته الرباعية — حارس توافق المداخل '
        'الأخرى (روابط الطرف والاختبارات القائمة)', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);

      await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('فاتورة جديدة'));
      await tester.pumpAndSettle();
      expect(find.text('فاتورة بيع'), findsOneWidget);
      expect(find.text('فاتورة شراء'), findsOneWidget);
      expect(find.text('مردود بيع'), findsOneWidget);
      expect(find.text('مردود شراء'), findsOneWidget,
          reason: 'بلا جهة الأنواع الأربعة عرف س-163 باقياً حرفاً');
    });
  });

  group('س202 م3: بلاطتا الجهة بالرئيسية والتوجيه بالمفتاح لا بالنص', () {
    testWidgets('بلاطة المشتريات تفتح أرشيفها بجهته — ولا أثر للبطاقة '
        'المسحوبة ولا زر السجل', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      expect(find.text('المبيعات'), findsOneWidget);
      expect(find.text('المشتريات'), findsOneWidget);
      expect(find.text('سجل الفواتير'), findsNothing);
      expect(find.text('اختر النوع بالضغط — لا قائمة انتقاء'), findsNothing);

      await tester.tap(find.text('المشتريات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(InvoicesScreen), findsOneWidget);
      // نص البلاطة تحت الطريق المصرَّع ما يزال بالشجرة — فالعنوان
      // محصور بشريط الشاشة العلوية لا find.text طائلاً (درس الجولة #386).
      expect(
          find.descendant(
              of: find.byType(AppBar),
              matching: find.text('المشتريات')),
          findsOneWidget,
          reason: 'عنوان جهة المشتريات بلسان بلاطتها (س202)');
    });

    testWidgets('التسمية المختصرة «الطلبات» تفتح شاشة الأوامر بعنوانها '
        'الكامل — والتوجيه بالمفتاح لا بنص الواجهة', (tester) async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

      await tester.pumpWidget(DiqqahApp(db: db));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('الطلبات'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('الطلبات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(OrdersScreen), findsOneWidget);
      expect(find.text('طلبات الشراء والبيع'), findsOneWidget,
          reason: 'عنوان الشاشة الكامل باقٍ — الاختصار بلسان البلاطة حصراً');
    });
  });
}
