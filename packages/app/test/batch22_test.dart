import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/drilldown.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات الدفعة 22 — F-164: تنبيه حد الائتمان «البائع يرى ويقرر» —
/// رسالة لا منع عند ترحيل بيع آجل يتجاوز السقف (F-023)، ولافتة كشف
/// الطرف عند فتحه على تجاوز قائم.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// في التدفقات الحية (درس س22..س26 الموثق)، وعضو pumpWidget واحد لكل
/// اختبار (درس الجولة 183)، وأرقام الدورة المعروفة من seedKnownCycle:
/// ذمة «عميل الأمل» بعد الدورة 40,000 هم يدينون لنا.
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

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

  /// تعيين سقف ائتمان العميل المبذور على صفّه القائم (تحديث التفاصيل
  /// س-35/D-153 — لا طرفاً جديداً فتبقى أرقام الدورة المعروفة ثابتة).
  Future<void> setLimit(DiqqahDatabase db, int? limit) async {
    final party = (await db.select(db.parties).get())
        .firstWhere((p) => p.name == 'عميل الأمل');
    await db.updatePartyDetails(
      party,
      number: party.number,
      name: party.name,
      kind: party.kind,
      phone: party.phone,
      address: party.address,
      defaultCurrencyId: party.defaultCurrencyId,
      creditLimitBaseMinor: limit,
    );
  }

  /// تجهيز نموذج بيع آجل: 1×15,000 للعميل المبذور — الحصيلة بعد
  /// الفاتورة 55,000 على ذمة 40,000 (بأرقام الدورة المعروفة).
  Future<void> fillCreditSale(WidgetTester tester) async {
    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'),
        '2026-03-15');

    // الآجل بطرفه (س-07): من قائمة النقدية إلى «آجل» فيظهر خانة العميل
    await tester.tap(find.text('نقدي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('آجل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('العميل (الآجل يطلب طرفاً)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('عميل الأمل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // الصنف: قائمة الأصناف ثم البند الوحيد (س-108 سطر مركب)
    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('Z-100 زيت محلي').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.widgetWithText(TextField, 'الكمية'), '1');
    await tester.enterText(
        find.widgetWithText(TextField, 'سعر الوحدة بوحدة صغرى'), '15000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('F-164: ترحيل بيع آجل يتجاوز السقف ينذر بالأرقام — '
      'و«حفظ على أي حال» يُكمل لأن التنبيه لا منع', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // السقف 50,000 والذمة 40,000 — فاتورة 15,000 تجاوز بفائض 5,000
    await setLimit(db, 50000);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(
            db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await fillCreditSale(tester);

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // رسالة التجاوز بالأرقام كلها — والقرار للبائع («يرى ويقرر» س2)
    expect(find.text('تجاوز حد الائتمان'), findsOneWidget);
    expect(find.textContaining('بفائض'), findsOneWidget);
    expect(find.text('حفظ على أي حال'), findsOneWidget);
    expect(find.text('رجوع للتعديل'), findsOneWidget);

    await tester.tap(find.text('حفظ على أي حال'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final rows = await db.customSelect(
      "SELECT COUNT(*) AS n FROM invoices WHERE kind = 'sale' "
      "AND state <> 'draft' AND total_doc_minor = 15000",
      variables: [],
    ).getSingle();
    expect(rows.data['n'], 1,
        reason: 'التنبيه لا منع — الفاتورة رُحّلت بالاعتراف الصريح');
  });

  testWidgets('F-164: تحت السقف لا رسالة — الحفظ مباشر بلا حوار', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // سقف واسع: الحصيلة 55,000 تحته بمراحل فلا تنذر
    await setLimit(db, 200000);

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(
            db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await fillCreditSale(tester);

    await _scrollTo(tester, 'حفظ وترحيل');
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تجاوز حد الائتمان'), findsNothing,
        reason: 'لا تجاوز فلا رسالة — التنبيه للتجاوز حصراً');
    final rows = await db.customSelect(
      "SELECT COUNT(*) AS n FROM invoices WHERE kind = 'sale' "
      "AND state <> 'draft' AND total_doc_minor = 15000",
      variables: [],
    ).getSingle();
    expect(rows.data['n'], 1, reason: 'الحفظ تم مباشرة بلا حوار');
  });

  testWidgets('F-164: كشف الطرف على تجاوز قائم يرفع اللافتة — '
      'رسالة لا صمت (F-162)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    // الذمة القائمة 40,000 فوق سقف 30,000 — الكشف لا يُفتح صامتاً
    await setLimit(db, 30000);
    final customerId = (await db.customSelect(
      "SELECT id FROM parties WHERE name = 'عميل الأمل'",
    ).getSingle()).data['id'] as int;

    await tester.pumpWidget(MaterialApp(
        home: PartyStatementScreen(
            db: db, partyId: customerId, partyName: 'عميل الأمل')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تجاوز حد الائتمان'), findsOneWidget);
    expect(find.textContaining('بفائض'), findsOneWidget);
  });

  testWidgets('F-164: كشف الطرف تحت السقف بلا لافتة — التنبيه للتجاوز '
      'حصراً فلا يُربك المالك برسالةٍ لا معنى لها', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await setLimit(db, 200000);
    final customerId = (await db.customSelect(
      "SELECT id FROM parties WHERE name = 'عميل الأمل'",
    ).getSingle()).data['id'] as int;

    await tester.pumpWidget(MaterialApp(
        home: PartyStatementScreen(
            db: db, partyId: customerId, partyName: 'عميل الأمل')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تجاوز حد الائتمان'), findsNothing);
  });
}
