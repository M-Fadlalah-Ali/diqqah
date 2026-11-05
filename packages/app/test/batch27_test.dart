import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/items_screen.dart';
import 'package:diqqah_app/price_update_screen.dart';
import 'package:diqqah_app/unit_groups_screen.dart';

import 'test_guard.dart';

/// اختبارات الدفعة 27 (رابعة م2) — مجموعات التعبئة وأسعارها آلي
/// (F-032/F-033/F-208، D-026/D-187).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26)، والمثال الحرفي للمتطلب موضع اختبار: أساس 1,000
/// وعلبة عاملها 12 ⇒ العلبة تقرأ 12,000 بلا كتابة (F-208).
Finder _fieldByLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText == label));

/// قوائم الاختيار ليست TextField — بُنيتها بـInputDecorator حول
/// DropdownButton (نمط مُجدئ منفصل).
Finder _dropdownByLabel(String label) => find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField && (w.decoration?.labelText == label));

void _bigView(WidgetTester tester) {
  // عريضة بما يكفي لأزرار AppBar الحافة (درس الاختبار: الإطار الافتراضي
  // 800×600 يقتص حافة الأفعال).
  tester.view.physicalSize = const Size(1600, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// تصريف الإخطار المعلق قبل نهاية الاختبار (مؤقت SnackBar لا يُترك
/// حياً — نمط الضخّات المحدودة).
Future<void> _drainSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<DiqqahDatabase> _ground() async {
  final db = DiqqahDatabase.inMemorySyncClose();
  await db.insertUnit(name: 'قطعة');
  await db.insertUnitGroup(name: 'تعبئة عامة',
      levels: [(name: 'علبة', factor: 12)]);
  return db;
}

/// فتح بطاقة صنف جديدة واختيار الوحدة والمجموعة وإدخال أساس البيع
/// 1,000 — أرضية اختبارات الآلي (D-187).
Future<void> _openCardWithGroup(WidgetTester tester, DiqqahDatabase db,
    {String sale = '1000'}) async {
  await tester.pumpWidget(MaterialApp(home: ItemEditScreen(db: db)));
  await tester.pump();
  await tester.enterText(_fieldByLabel('كود الصنف (الأساس)'), 'Z-100');
  await tester.enterText(_fieldByLabel('الاسم *'), 'زيت محلي');
  await tester.tap(_dropdownByLabel('الوحدة الأساسية *'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('قطعة').last);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(_dropdownByLabel('مجموعة التعبئة (اختياري)'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('تعبئة عامة').last);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(_fieldByLabel('سعر البيع'), sale);
  await tester.pump();
}

void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  testWidgets('بطاقة صنف: الآلي مفعّل افتراضاً والمستويات للقراءة تُشتق '
      'لحظياً — أساس 1,000 وعلبة 12 ⇒ 12,000 (F-208/D-187)',
      (tester) async {
    _bigView(tester);
    final db = await _ground();
    addTearDown(db.close);

    await _openCardWithGroup(tester, db);

    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.value, isTrue, reason: 'D-187: افتراض مربع «آلي» مفعّل');
    expect(find.text('12,000'), findsOneWidget,
        reason: 'المثال الحرفي للمتطلب — بلا كتابة بالمستوى');
    final levelField = tester.widget<TextField>(_fieldByLabel('بيع'));
    expect(levelField.enabled, isFalse,
        reason: 'آلياً: الوحدة الصغرى للكتابة والمستويات للقراءة');
    // والاشتقاق لحظي: تغيير الأساس يحدّث المشتق فوراً (درس س79).
    await tester.enterText(_fieldByLabel('سعر البيع'), '2000');
    await tester.pump();
    expect(find.text('24,000'), findsOneWidget);
  });

  testWidgets('تعطيل الآلي يتاح كل الخانات وإعادة تفعيله تستبدل المستويات '
      'بالاشتقاق — أثر معلن (D-187)', (tester) async {
    _bigView(tester);
    final db = await _ground();
    addTearDown(db.close);

    await _openCardWithGroup(tester, db);

    // تعطيل الآلي: الخانة تتاح للتسعير اليدوي.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(tester.widget<TextField>(_fieldByLabel('بيع')).enabled, isTrue);
    await tester.enterText(_fieldByLabel('بيع'), '9999');
    await tester.pump();

    // إعادة التفعيل: الاشتقاق يستبدل القيمة اليدوية (أثر معلن).
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(find.text('12,000'), findsOneWidget);
    expect(find.text('9,999'), findsNothing);
    expect(find.textContaining('تُشتق من الأساس'), findsOneWidget,
        reason: 'الأثر المعلن يُعرض لا يُخفى');
    await _drainSnackbar(tester);
  });

  testWidgets('شاشة المجموعات: الإنشاء بقوالب مقترحة (D-026) والحفظ والعرض '
      'بمستوياته', (tester) async {
    _bigView(tester);
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: UnitGroupsScreen(db: db)));
    await tester.pump();
    await tester.tap(find.text('إضافة مجموعة'));
    // انتقال المسار يحتاج ضخّاً أطول من مدته حتى يستقر البناء مكانه
    // (درس هذا الاختبار: +82px انزياح باقٍ عند 400ms).
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));

    // القالبان مقترحان ويمكن تعديلهما (غير حصرية — D-026).
    expect(find.text('علبة'), findsWidgets);
    expect(find.text('كرتونة'), findsWidgets);

    await tester.enterText(_fieldByLabel('اسم المجموعة *'), 'تعبئة عامة');
    await tester.tap(find.text('حفظ'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تعبئة عامة'), findsOneWidget);
    expect(find.text('علبة ×12 · كرتونة ×144'), findsOneWidget);
  });

  testWidgets('عامل غير صحيح يُرفض برسالة موضعية قبل أي كتابة', (tester) async {
    _bigView(tester);
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: UnitGroupsScreen(db: db)));
    await tester.pump();
    await tester.tap(find.text('إضافة مجموعة'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(_fieldByLabel('اسم المجموعة *'), 'خاطئة');
    await tester.enterText(_fieldByLabel('العامل').first, '1');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('عامل المستوى 1 عدد صحيح ≥2 — «1» غير مقبول'),
        findsOneWidget,
        reason: 'الرسالة الموضعية تحمل موضع الصف والقيمة المرفوضة');
    expect(find.text('حفظ'), findsOneWidget,
        reason: 'الرفض قبل الكتابة — ما زلنا في المحرر');
    await _drainSnackbar(tester);
  });

  testWidgets('الرفع الجماعي (F-165): مستوى الآلي يُعاد اشتقاقه بالمعاينة '
      'واليدوي المخالف يرفع علم الانكسار — والتنفيذ يكتب ما عُرض '
      '(تقاطع D-187)', (tester) async {
    _bigView(tester);
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final unitId = await db.insertUnit(name: 'قطعة');
    final gid = await db.insertUnitGroup(name: 'تعبئة عامة',
        levels: [(name: 'علبة', factor: 12)]);
    final levelId = (await db.levelsOfGroup(gid)).single.id;

    final oil = await db.insertItem(
        sku: 'Z-100',
        name: 'زيت محلي',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 1000,
        priceCurrencyId: 1,
        unitGroupId: gid,
        priceAuto: true);
    await db.saveItemLevelPrices(
        oil, [(levelId: levelId, salePriceMinor: 12000, purchasePriceMinor: 0)]);

    final rice = await db.insertItem(
        sku: 'R-200',
        name: 'أرز فاخر',
        category: 'زيوت',
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: 0,
        salePriceMinor: 5000,
        priceCurrencyId: 1,
        unitGroupId: gid,
        priceAuto: false);
    await db.saveItemLevelPrices(
        rice, [(levelId: levelId, salePriceMinor: 9999, purchasePriceMinor: 0)]);

    await tester.pumpWidget(MaterialApp(home: PriceUpdateScreen(db: db)));
    await tester.pump();
    await tester.tap(_dropdownByLabel('التصنيف'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('زيوت').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
        _fieldByLabel('النسبة بالمئة (مثال: 2.5 أو -3)'), '10');
    await tester.pump();
    // زر المعاينة بنصه الكامل — «معاينة» وحدها تطابق رسالة المساعدة
    // أيضاً (درس هذا الاختبار: المُجدئ الكامل لا الجزئي).
    await tester.tap(find.text('معاينة (2 صنفاً في التصنيف)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // الآلي: 1,100 × 12 = 13,200 بخطوة واحدة (نسبة الأساس تنتقل بذاتها).
    expect(find.text('13,200'), findsOneWidget);
    // اليدوي المخالف: 9,999 ≠ 5,000 × 12 ⇒ علم الانكسار بالمعاينة.
    expect(find.textContaining('انكسار علاقة السعر بالكمية'), findsOneWidget);
    // سطر المستوى السليم نصه الظاهر بلا تحذير، والمنكسر نصه أطول بعلمه.
    expect(find.text('— علبة ×12'), findsOneWidget);

    // التنفيذ يكتب ما عُرض حرفاً.
    await tester.tap(find.textContaining('تنفيذ الترقية على'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('تنفيذ الترقية'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await _drainSnackbar(tester);

    expect(await db.itemLevelPriceMap(oil), {
      levelId: (13200, 0),
    }, reason: 'الآلي كُتب مشتقاً');
    expect(await db.itemLevelPriceMap(rice), {
      levelId: (10999, 0),
    }, reason: 'اليدوي ضُرب بالنسبة نفسها بس7 (9,999×1.1=10,998.9)');
    final items = await db.select(db.items).get();
    expect(items.singleWhere((i) => i.id == oil).salePriceMinor, 1100);
    expect(items.singleWhere((i) => i.id == rice).salePriceMinor, 5500);
  });
}
