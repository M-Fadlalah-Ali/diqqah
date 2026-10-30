import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/boxes_screen.dart';

import 'seed_cycle.dart';

/// اختبارات شاشة الصناديق — دفعة (6-ج) على السيناريو المعروض س-93
/// (06 §1-ط، D-095 معروض) بأرقام الدورة المعروفة: الصندوق المبذر
/// برصيده 545,000 بعد الدورة، والحساب الآلي 1112 للصندوق الجديد
/// (D-086 معتمد)، والتعطيل آمن بلا أرصدة حصراً (03 §6-3).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26) — والحكم بالبطاقة الفريدة «حساب 1111 · SYP» (درس
/// س35: النص خلف الشاشة المدفوعة لا يُلمَس نصاً عائماً).
  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً — زر أسفل
  /// النموذج غير مبني خارج الشاشة فلا يُلمَس قبل تمريره إلى النافذة.
  Future<void> _scrollTo(WidgetTester tester, String label) async {
    for (var i = 0;
        i < 6 && find.text(label).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
  }

void main() {
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-93: القائمة تعرض الصندوق المبذر ببطاقة حسابه ورصيد '
      'الدورة المعروفة 545,000', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: BoxesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // البطاقة الفريدة الموثقة — لا اشتراك نصي عائم (درس س35)
    expect(find.textContaining('حساب 1111 · SYP'), findsOneWidget);
    expect(find.textContaining('545,000'), findsOneWidget);
  });

  testWidgets('D-086: صندوق جديد يحصل آلياً على حسابه الورقي التالي 1112 '
      'بعملته — والاسم المكرر يرفضه المحرك برسالته', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);

    await tester.pumpWidget(MaterialApp(home: BoxesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('صندوق جديد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // اسم مكرر أولاً — رسالة المحرك كما هي
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الصندوق'), 'الصندوق الرئيسي');
    await _scrollTo(tester, 'إنشاء الصندوق');
    await tester.tap(find.text('إنشاء الصندوق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('مستخدم سلفاً'), findsOneWidget);

    // اسم جديد بالعملة الأساسية (المختارة افتراضياً) — والحساب آلي
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم الصندوق'), 'صندوق الفرع');
    await _scrollTo(tester, 'إنشاء الصندوق');
    await tester.tap(find.text('إنشاء الصندوق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final rows = await db.customSelect(
      'SELECT b.name AS name, a.code AS code FROM cash_boxes b '
      'JOIN accounts a ON a.id = b.account_id ORDER BY b.id',
    ).get();
    expect(rows, hasLength(2));
    expect(rows.last.data['name'], 'صندوق الفرع');
    expect(rows.last.data['code'], '1112',
        reason: 'D-086: الحساب الورقي التالي 1112 آلياً');
  });

  testWidgets('03 §6-3: تعطيل صندوق برصيد قائم يرفضه المحرك برسالته — '
      'والفارغ يُعطل فيظهر بشارته', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await db.createCashBox(name: 'صندوق فارغ', currencyId: 1);

    await tester.pumpWidget(MaterialApp(home: BoxesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // تعطيل الصندوق المبذر برصيد 545,000 — المحرك يمنع برسالته
    final mainBoxTile = find.text('الصندوق الرئيسي').first;
    await tester.scrollUntilVisible(mainBoxTile, 200,
        scrollable: find.byType(Scrollable));
    await tester.tap(
        find.byTooltip('تعطيل').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('تعطيل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('برصيد قائم — تعطيله غير آمن'), findsOneWidget);

    // الصندوق الفارغ يُعطل ويظهر بشارته (الصدق أولاً)
    await tester.scrollUntilVisible(
        find.text('صندوق فارغ'), 200,
        scrollable: find.byType(Scrollable));
    await tester.tap(find.byTooltip('تعطيل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('تعطيل').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final active = await db.customSelect(
      'SELECT is_active FROM accounts WHERE id = '
      "(SELECT account_id FROM cash_boxes WHERE name = 'صندوق فارغ')",
    ).getSingle();
    expect(active.data['is_active'], 0);
    expect(find.textContaining('— معطل'), findsOneWidget);
  });
}
