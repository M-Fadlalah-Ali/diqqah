import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/periods_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات الدفعة 32 (تاسعة م2) — الإقفال السنوي (س-21/F-077/D-068):
/// بند «الإقفال السنوي» بشاشة الفترات، والمعاينة بالنتيجة قبلية
/// والأخطاء، والتنفيذ بتأكيد صريح ثم ملخص النتيجة.
///
/// الدورة المعروفة (seedKnownCycle): ضخ 500,000 فشراء 100,000 فبيع
/// آجل 90,000 فقبض 50,000 فعجز 5,000 — النتيجة ربح 25000.
/// نمط القاعدة `inMemorySyncClose` وضخّات محدودة لا pumpAndSettle.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  Future<void> pumpYears(WidgetTester tester, DiqqahDatabase db) async {
    await tester.pumpWidget(MaterialApp(home: YearCloseScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('س-21: بند الإقفال السنوي بشاشة الفترات يفتح معاينة نهاية '
      'السنة — وفترات مفتوحة تعرض رسالة الرفض والزر معطل (لا تنفيذ '
      'بغير جاهز)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: PeriodsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('الإقفال السنوي'), findsOneWidget);
    await tester.tap(find.text('الإقفال السنوي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المعاينة: النتيجة قبلية ربح 25000 (90,000 − 60,000 تكلفة −
    // 5,000 عجز) والميزان متوازن ورسالة الفترات المفتوحة ظاهرة.
    expect(find.textContaining('النتيجة قبلية'), findsOneWidget);
    expect(find.textContaining('ربح 25000'), findsOneWidget);
    expect(find.textContaining('الميزان متوازن'), findsOneWidget);
    expect(find.textContaining('فترة مفتوحة'), findsOneWidget,
        reason: 'س-21: أي فترة مفتوحة تطلب إقفالها أولاً');
    expect(find.text('ترحيل الإقفال السنوي'), findsOneWidget);
    // الزر معطل قبل التأكيد والجاهزية معاً.
    final button = tester.widget<FilledButton>(
        find.ancestor(
            of: find.text('ترحيل الإقفال السنوي'),
            matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('س-21: بعد إقفال كل الفترات — التأكيد الصريح يرحّل الإقفال '
      'ويلخص النتيجة، والسنة مقفلة والسنة التالية مبذورة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    // إقفال فترات السنة كلها (المسودات: لا شيء في هذه الدورة).
    final periods = await db.ledgerPeriods();
    for (final period in periods) {
      await db.closePeriod(period.id, draftsConfirmed: true);
    }

    await pumpYears(tester, db);
    // الجاهزية: لا رسالة رفض والميزان متوازن والزر ينتظر التأكيد فقط.
    expect(find.textContaining('فترة مفتوحة'), findsNothing);
    expect(find.textContaining('الميزان متوازن'), findsOneWidget);

    await tester.tap(find.textContaining('أكّد الإقفال السنوي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('ترحيل الإقفال السنوي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // ملخص النتيجة بالأرقام — والإقفال واقع في القاعدة.
    expect(find.textContaining('أُقفلت السنة'), findsOneWidget);
    expect(find.textContaining('ربح 25000'), findsOneWidget);
    final yearRow = await db.customSelect(
      'SELECT name, state FROM fiscal_years ORDER BY id',
    ).get();
    expect(yearRow.first.data['state'], 'closed');
    expect(yearRow.last.data['state'], 'open');
    final seededYear = yearRow.first.data['name'] as String;
    final netRow = await db.customSelect(
      "SELECT SUM(l.credit_minor) - SUM(l.debit_minor) AS v "
      'FROM move_lines l JOIN moves m ON m.id = l.move_id '
      "JOIN accounts a ON a.id = l.account_id WHERE a.code = '331' "
      "AND m.date_text <= '$seededYear-12-31'",
    ).getSingle();
    // 331 داخل سنة الإقفال: دائن 25,000 (نقل النتيجة) — س-21.
    expect(netRow.data['v'], 25000);
  });
}
