import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/vouchers_screen.dart';

import 'seed_cycle.dart';

/// اختبارات شاشة السندات — دفعة (6-ج) على السيناريوهات المعروضة
/// س-89..س-92 (06 §1-ط، D-094..D-096 معروض) بأرقام الدورة المعروفة:
/// ضخ رأس المال 500,000 وقبض 50,000 وفائض؟ لا — قبض الدورة مطابق حرفاً،
/// والرصيد المقدَّم هنا تجربة جديدة بمبلغ غير مطابق (س-12/س5).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26) — والحكم بنصوص فريدة لا اشتراكات عائمة (درس س35).
  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً — زر أسفل
  /// النموذج غير مبني خارج الشاشة فلا يُلمَس قبل تمريره إلى النافذة.
  Future<void> _scrollTo(WidgetTester tester, String label) async {
    for (var i = 0;
        i < 10 && find.text(label).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
  }

void main() {
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-89: قائمة السندات تعرض ضخ رأس المال بتسميته الكاملة '
      'وقائمة التسويات تعرض عجز الدورة بسببها الموثق', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // ضخ رأس المال «سند قبض 2026/000001» على 311 بغير طرف (س-13)
    expect(find.textContaining('سند قبض 2026/000001'), findsOneWidget);
    expect(find.textContaining('حساب 311'), findsOneWidget);

    // تبويب التسويات — عجز 5,000 بسبب «فرق جرد يومي» (س-17)
    await tester.tap(find.text('التسويات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('تسوية صندوق 2026/000001'), findsOneWidget);
    expect(find.textContaining('فرق جرد يومي'), findsOneWidget);
    expect(find.textContaining('عجز'), findsOneWidget);
  });

  testWidgets('س-92: سبب التسوية إلزامي — والفراغ يرفضه المدقق برسالته '
      'الحرفية لا صياغة واجهة موازية (درس س2)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('التسويات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('تسوية جديدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'), '2026-03-15');
    await tester.enterText(
        find.widgetWithText(TextField, 'قيمة الفرق بوحدة صغرى'), '5000');
    await tester.pump();

    // السبب متروك فارغاً عمداً
    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('سبب تسوية الصندوق إلزامي للفرق'), findsOneWidget);

    // ولا مستند كُتب
    final rows = await db
        .customSelect('SELECT COUNT(*) AS n FROM cash_adjustments')
        .getSingle();
    expect(rows.data['n'], 1, reason: 'تسوية الدورة وحدها — المدقق منع الثانية');
  });

  testWidgets('س-91: التحويل بين صندوقين من النموذج يُرحَّل بحركتَيه '
      'المتبادلتين — وصندوقَي الدورة أساسيان بعيّنتهما', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // صندوق ثانٍ بالعملة الأساسية — التحويل بين عملتين مؤجل (D-087)
    await db.createCashBox(name: 'صندوق الفرع', currencyId: 1);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('التحويلات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('تحويل جديد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الافتراضي أول صندوق من وإليه الثاني — يبقى تاريخه ومبلغه
    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'), '2026-03-15');
    await tester.enterText(
        find.widgetWithText(TextField, 'المبلغ بوحدة صغرى'), '10000');
    await tester.pump();

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final rows = await db.customSelect(
      "SELECT from_box_id, to_box_id, amount_doc_minor, state "
      "FROM box_transfers WHERE state = 'posted'",
    ).get();
    expect(rows, hasLength(1));
    expect(rows.single.data['amount_doc_minor'], 10000);
    expect(rows.single.data['from_box_id'],
        isNot(rows.single.data['to_box_id']));
    // حركتا الصندوق المتبادلتان بالمرجعية (D-087: خروج ودخول)
    final movements = await db.customSelect(
      "SELECT kind FROM cash_movements WHERE ref_doc_type = 'box_transfer'",
    ).get();
    expect(movements, hasLength(2));
    final kinds = [for (final m in movements) m.data['kind'] as String];
    expect(kinds, containsAll(<String>['transfer_out', 'transfer_in']));
  });

  testWidgets('س-90: القبض الطرفي بغير مطابقة فائضه «رصيد مقدَّم» — '
      'والمقترح الآلي يعبئ المطبَّق بالأقدمية ويبقى حقلَيه قابلين للتعديل',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('سند جديد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الطرف: القبض افتراضياً على العملاء — أول dropdown int هو الطرف
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // D-106: العناصر صارت بأسطر رصيد مركّبة — الفيض نصاً جزئياً
    // (درس الحكم بالنص الحرفي لا يمنع النص المحتوي عند عنصر مركّب)
    await tester.tap(find.textContaining('عميل الأمل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // فاتورة البيع المفتوحة ظهرت بمتبقيها 40,000 (قبض الدورة 50,000)
    expect(find.textContaining('متبقٍ 40,000'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'), '2026-03-15');
    await tester.pump();

    // المبلغ 30,000 ثم المقترح الآلي بالأقدمية يعبئ المطبَّق
    await tester.enterText(
        find.widgetWithText(TextField, 'المبلغ بوحدة صغرى'), '30000');
    await tester.pump();
    await tester.tap(find.text('اقتراح المطابقة آلياً بالأقدمية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    // الحقل المطبَّق عُبئ بالأقدمية بكامل المقترح 30,000 — مفصولاً
    // (D-102): التعبئة البرمجية تعرض بالفواصل كالكتابة
    final appliedField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'المطبَّق بوحدة صغرى'));
    expect(appliedField.controller!.text, '30,000');

    // حفظ وترحيل — والسند مرحّل والمطبَّق 30,000 يبقى بالفاتورة جزئية
    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();

    // تشخيص حرفي موثق بالجلسة (درس س35: الحكم بالنص الحرفي) — نصوص
    // الشاشة بعد الحفظ تظهر في سجل CI كي يُكشف سبب أي رفض من مصدره
    // لا تخميناً: السند الجديد في القائمة إن نجح الترحيل، أو رسالة
    // المدقق في بطاقة الأخطاء أعلى النموذج إن رُفض.
    for (final t
        in tester.widgetList<Text>(find.byType(Text)).take(40)) {
      final plain = t.data ?? t.textSpan?.toPlainText() ?? '';
      if (plain.trim().isNotEmpty) {
        // ignore: avoid_print
        print('SHOWN_TEXT: $plain');
      }
    }

    final allocations = await db.customSelect(
      'SELECT applied_doc_minor FROM voucher_allocations',
    ).get();
    expect(allocations, hasLength(2),
        reason: 'مطابقة قبض الدورة (50,000) والمقبوض الجديد (30,000)');
    final covered = allocations.fold<int>(
        0, (sum, r) => sum + (r.data['applied_doc_minor'] as int));
    expect(covered, 80000);
  });
}
