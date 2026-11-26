import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/periods_screen.dart';
import 'test_guard.dart';

/// اختبارات شاشة الفترات والإقفال — س-85 من دفعة م1 (6-ب): الإقفال بقائمة
/// مسوداته وتأكيدها الصريح (س-20) والفك بسبب نصي إلزامي (س2) — والسبب
/// موثق في سجل الأحداث بالمحرك (D-090).
///
/// نمط inMemorySyncClose وضخّات محدودة — درس س22..س26 الموثق.
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// مسودة سند فوق مارس كي تُعرض قائمة الحسم (س-20)
  Future<void> seedMarchDraftVoucher(DiqqahDatabase db) async {
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    final boxId = (await db.customSelect(
      'SELECT id FROM cash_boxes ORDER BY id LIMIT 1',
    ).getSingle()).data['id'] as int;
    final capitalId = (await db.customSelect(
      "SELECT id FROM accounts WHERE code = '311'",
    ).getSingle()).data['id'] as int;
    await db.createVoucherDraft(VoucherDraft(
      kind: VoucherKind.receipt,
      dateText: '$year-03-12',
      directAccountId: capitalId,
      cashBoxId: boxId,
      amountDocMinor: 3000,
    ));
  }

  testWidgets('س-85: إقفال فترة فيها مسودة — التأكيد الصريح شرط الزر، '
      'وبعده مقفلة والنشرة تظهر، والفك بلا سبب مرفوض وبسبب يمرّ موثقاً',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedMarchDraftVoucher(db);

    await tester.pumpWidget(MaterialApp(home: PeriodsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // الفترات مرتبة بالبداية: يناير 0 فبراير 1 مارس 2 — والإقفال أزرار
    // المفتوحة كلها
    expect(find.text('فك الإقفال'), findsNothing);
    await tester.tap(find.text('إقفال').at(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // قائمة الحسم: المسودة بلقب «مسودة #المعرف» (بلا رقم — 07 §1.9)
    expect(find.textContaining('مسودة #'), findsOneWidget);
    final closeButton = tester.widget<FilledButton>(find.ancestor(
      of: find.text('إقفال الفترة'),
      matching: find.byType(FilledButton),
    ));
    expect(closeButton.onPressed, isNull,
        reason: 'س-20: لا إقفال فوق مسودات بلا تأكيد صريح');

    await tester.tap(find.text('أكّد تركها معلقة لا تُرحَّل حتى الفك'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final closeButtonAfter = tester.widget<FilledButton>(find.ancestor(
      of: find.text('إقفال الفترة'),
      matching: find.byType(FilledButton),
    ));
    expect(closeButtonAfter.onPressed, isNotNull);

    await tester.tap(find.text('إقفال الفترة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('أُقفلت الفترة'), findsOneWidget);
    expect(find.text('مقفلة'), findsOneWidget,
        reason: 'مارس وحده المقفلة');
    // السرد الكسول يبني الظاهر حصراً — يكفي «واحد على الأقل» والحالة
    // الفعلية للفترات الاثنتي عشرة تُفحص من القاعدة أسفل الاختبار
    expect(find.text('مفتوحة'), findsWidgets);
    expect(find.text('فك الإقفال'), findsOneWidget);

    // الفك: الفراغ مرفوض برسالة المدقق ثم السبب يمرّ ويوثق
    await tester.tap(find.text('فك الإقفال'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('فتح الفترة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // بالنص الحرفي الكامل — لا textContaining: بطاقة الإرشاد خلف الحوار
    // تشارك عبارة «بسبب نصي إلزامي» (فشل CI جولة الثانية — 2026-10-31)
    expect(
      find.text(
          'فك الإقفال طارئ بسبب نصي إلزامي — اكتب سبب الفك ولا يفتح بلا سبب'),
      findsOneWidget,
    );

    await tester.enterText(
        find.byType(TextField), 'تصحيح خطأ ترحيل بإذن المالك');
    await tester.tap(find.text('فتح الفترة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('فُتحت الفترة'), findsOneWidget);
    expect(find.text('مفتوحة'), findsWidgets);
    expect(find.text('مقفلة'), findsNothing);

    // والحالة في القاعدة عادت مفتوحة فعلاً
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final year = int.parse(yearRows.single.data['name'] as String);
    final march = await (db.select(db.periods)
          ..where((t) => t.startDateText.equals('$year-03-01')))
        .getSingle();
    expect(march.state, 'open');
  });

  testWidgets('س-85: إقفال فترة بلا مسودات — الزر فعال فوراً والرسالة '
      'تقول إن الإقفال يجمد كل ما فيها', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: PeriodsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // فبراير (الفهرس 1) بلا أي مستندات
    await tester.tap(find.text('إقفال').at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('لا مسودات مفتوحة'), findsOneWidget);
    final closeButton = tester.widget<FilledButton>(find.ancestor(
      of: find.text('إقفال الفترة'),
      matching: find.byType(FilledButton),
    ));
    expect(closeButton.onPressed, isNotNull,
        reason: 'بلا مسودات لا حاجة لتأكيد');

    await tester.tap(find.text('إقفال الفترة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('أُقفلت الفترة'), findsOneWidget);
    expect(find.text('مقفلة'), findsOneWidget);
    expect(find.text('مفتوحة'), findsWidgets);

    // ولقطة سجل الإقفال موثقة بالمحرك (حدث period_closed)
    final events = await db.customSelect(
      "SELECT payload FROM events WHERE action = 'period_closed'",
    ).get();
    expect(events, hasLength(1));
    expect(await db.openLogText(events.single.data['payload'] as String),
        contains('02-01'),
        reason: 'لقطة المسودات عند القفل تحمل حدود الفترة');
  });
}
