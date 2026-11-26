import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/currencies_screen.dart';
import 'package:diqqah_app/currency_display.dart';

import 'test_guard.dart';

/// اختبارات س146/D-209 — كتالوج ISO 4217 المضمّن بشاشة العملات ورموز
/// العرض: البحث العربي والإنجليزي والانتقاء والتعبئة التلقائية (لا
/// حقول يدوية للكود والاسم أصلاً — المسار اليدوي مغلق بقرار المالك)،
/// والخانات معبأة باقتراح ISO قابلة للتعديل قبل الحفظ، والمحفوظة
/// سابقاً موسومة «محفوظة» بلا انتقاء، وزر الإضافة معطّل قبل اختيار.
///
/// نمط القاعدة `inMemorySyncClose` وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق).
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  const searchField = 'ابحث بالكود أو بالاسم (عربي/إنجليزي)';
  const minorField = 'خانات الوحدة الصغرى (0..8)';

  testWidgets('س146: البحث العربي «سعودي» يظهر SAR والانتقاء يضيفه '
      'بلا كتابة يدوية للحقلين', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: CurrenciesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('إضافة عملة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
        find.widgetWithText(TextField, searchField), 'سعودي');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('SAR'), findsOneWidget);
    expect(find.text('ريال سعودي'), findsOneWidget);

    await tester.tap(find.text('SAR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // الخانات معبأة باقتراح ISO (2) وحقل الكود والاسم غير موجودين
    // أصلاً — المسار اليدوي مغلق (D-209).
    expect(find.widgetWithText(TextField, minorField), findsOneWidget);
    expect(
        find.widgetWithText(TextField, 'الكود (ثلاثة أحرف لاتينية — مثال: EUR)'),
        findsNothing);
    expect(find.widgetWithText(TextField, 'اسم العملة'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, minorField), '2');
    await tester.tap(find.text('إضافة').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('أُضيفت العملة SAR — ريال سعودي'), findsOneWidget);
    expect(find.text('SAR — ريال سعودي'), findsOneWidget);

    // والحكم من القاعدة ذاتها: الاسم من الكتالوج والخانات المعتمدة.
    final rows = await db.currenciesOf();
    final sar = rows.firstWhere((r) => r.code == 'SAR');
    expect(sar.name, 'ريال سعودي');
    expect(sar.minorUnits, 2);
  });

  testWidgets('س146: البحث الإنجليزي «kuwait» يظهر KWD والخانات معبأة '
      'بثلاث خانات ISO قابلة للتعديل قبل الحفظ', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: CurrenciesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('إضافة عملة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
        find.widgetWithText(TextField, searchField), 'kuwait');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('KWD'), findsOneWidget);
    await tester.tap(find.text('KWD'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // الافتراض المعبأ من الكتالوج: 3 خانات (ISO) — ثم تعديلها إلى 2
    // قبل الحفظ فتُعتمد المعدلة (والتعديل بعد الحفظ مرفوض D-194).
    final field = find.widgetWithText(TextField, minorField);
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      '3',
      reason: 'الخانات معبأة باقتراح ISO تلقائياً',
    );
    await tester.enterText(field, '2');
    await tester.tap(find.text('إضافة').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final rows = await db.currenciesOf();
    final kwd = rows.firstWhere((r) => r.code == 'KWD');
    expect(kwd.name, 'دينار كويتي');
    expect(kwd.minorUnits, 2, reason: 'المعدل قبل الحفظ هو المعتمد');
  });

  testWidgets('س146: المحفوظة سابقاً (USD المزروعة) موسومة «محفوظة» '
      'بلا انتقاء وزر الإضافة معطّل قبل أي اختيار', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: CurrenciesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('إضافة عملة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
        find.widgetWithText(TextField, searchField), 'USD');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('محفوظة'), findsOneWidget);

    // الصف المعطّل لا ينتقي: فلا حقل الخانات يظهر بعد الضغط عليه.
    // الصف الأخير — الأول حقل البحث نفسه يحمل نص الاستعلام.
    await tester.tap(find.text('USD').last, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(TextField, minorField), findsNothing);

    // وزر الإضافة معطّل قبل أي اختيار.
    final addBtn = tester.widget<FilledButton>(find.ancestor(
      of: find.text('إضافة'),
      matching: find.byType(FilledButton),
    ).first);
    expect(addBtn.onPressed, isNull,
        reason: 'الإضافة معطّلة قبل انتقاء عملة من الكتالوج');
  });

  testWidgets('س146: رموز العرض من الكتالوج والتجاوز اليدوي أعلاها',
      (tester) async {
    // التجاوز المثبت م1 باقٍ حرفاً.
    expect(currencySymbol('SYP'), 'ل.س');
    expect(currencySymbol('usd'), r'$');
    // الكتالوج يغذي البقية وتُطبَّع الرموز.
    expect(currencySymbol('SAR'), 'ر.س');
    expect(currencySymbol('EUR'), '€');
    expect(currencySymbol('JPY'), '¥');
    // الغريب عن الكتالوج والتجاوز معاً بكوده حرفاً (نمط س50/D-156).
    expect(currencySymbol('XYZ'), 'XYZ');
    expect(currencySymbol(null), '');
    expect(currencySymbol('  '), '');
  });
}
