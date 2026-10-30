import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/items_screen.dart';

/// اختبارات شاشة الأصناف — دفعة م1 (2) على السيناريوهات س-36..س-41
/// (06 §1-ج) بقرارات D-073..D-075.
///
/// نمط القاعدة هنا `inMemorySyncClose` حصراً والإغلاق العادي في الteardown،
/// والضخّات محدودة لا pumpAndSettle (نمط parties_screen_test الموثق س22..س26)
/// ومؤشر الكتابة مثبت — كلها دروس CI 2026-10-29/30 حرفاً.
void main() {
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-36: بطاقة صنف جديد — التحقق يتقدم رسالةً رسالة (الاسم ثم '
      'الكود ثم الوحدة)، وإضافة وحدة من البطاقة تختار فوراً، وبالحفظ يظهر '
      '«الاسم (الكود)» بالقائمة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا أصناف بعد — أضف أول صنف بزر «إضافة صنف»'),
        findsOneWidget);

    await tester.tap(find.text('إضافة صنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بلا شيء: أول خطأ الاسم (ترتيب مدقق المجال — س-36)
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('الاسم إلزامي وحده — أدخل الاسم ثم احفظ (س-36)'),
      findsOneWidget,
    );

    // باسم فقط: الكود المطلوب ثاني الترتيب (F-030/D-073)
    await tester.enterText(find.byType(TextFormField).at(1), 'زيت محلي');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('الكود إلزامي — اكتب كود الصنف ثم احفظ (F-030/D-073)'),
      findsOneWidget,
    );

    // باسم وكود: الوحدة إلزامية بالاختيار (F-031)
    await tester.enterText(find.byType(TextFormField).first, '100');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('الوحدة الأساسية إلزامية — اختر من القائمة أو أضف وحدة (F-031)'),
      findsOneWidget,
    );

    // س-41: إضافة وحدة من البطاقة نفسها ثم تختار فوراً
    await tester.tap(find.byTooltip('إضافة وحدة قياس'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'قطعة',
    );
    await tester.tap(find.text('إضافة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // عاد للقائمة والصنف بصيغة «الاسم (الكود)» (D-074/س-36)
    expect(find.text('زيت محلي (100)'), findsOneWidget);
    final rows = await db.select(db.items).get();
    expect(rows, hasLength(1));
    expect(rows.single.sku, '100');
    expect(rows.single.kind, 'good', reason: 'البضاعة الافتراضية');
    expect(rows.single.baseUnitId, greaterThan(0),
        reason: 'F-031: الوحدة اختيرت من القائمة الجديدة');
    expect(rows.single.priceCurrencyId, 1,
        reason: 'D-066 الاصطلاح: لا فراغ للعملة');
  });

  testWidgets('س-36: كود مكرر مرفوض برسالة تري صاحبه — «الكود 100 مستخدم '
      'للصنف: زيت محلي (100)»', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final unitId = await db.insertUnit(name: 'قطعة');
    await db.insertItem(
      sku: '100',
      name: 'زيت محلي',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('إضافة صنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    // الوحدة تُختار أولاً كي تظهر رسالة التفرد (ترتيب المدقق: الوحدة
    // قبل التفرد) — «قطعة» بلا تعارض مع نصوص البطاقة
    await tester.tap(find.text('اختر الوحدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('قطعة').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField).first, '100');
    await tester.enterText(find.byType(TextFormField).at(1), 'آخر');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('الكود 100 مستخدم للصنف: زيت محلي (100)'),
      findsOneWidget,
    );
    expect(find.text('حفظ'), findsOneWidget,
        reason: 'بقي على البطاقة — لم يُحفظ المكرر');
    expect(await db.select(db.items).get(), hasLength(1));
  });

  testWidgets('س-41/D-074: وحدة باسم مطابق حرفياً مرفوضة من حوار الإضافة '
      '— والحوار يبقى مفتوحاً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.insertUnit(name: 'قطعة');

    await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('إضافة صنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('إضافة وحدة قياس'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'قطعة',
    );
    await tester.tap(find.text('إضافة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('الاسم مطابق حرفياً لوحدة قائمة: قطعة — اختر اسماً آخر (D-074)'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'الحوار لم يُغلق — لم تُحفظ المكررة');
    expect(await db.select(db.units).get(), hasLength(1));
  });

  testWidgets('س-38/D-064: البحث الجامع المطبَّع — «زيت 100» و«غذائيه» '
      'ونتيجة فارغة برسالة لا بصمت', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final unitId = await db.insertUnit(name: 'قطعة');
    await db.insertItem(
      sku: '100',
      name: 'زيت محلي',
      category: 'مواد غذائية',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );
    await db.insertItem(
      sku: '200',
      name: 'أرز بسمتي',
      kind: 'service',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('زيت محلي (100)'), findsOneWidget);
    expect(find.text('أرز بسمتي (200)'), findsOneWidget);

    // كلمات متفرقة تلتقي: «زيت» في الاسم و«100» في الكود بأي ترتيب
    await tester.enterText(find.byType(TextField).first, 'زيت 100');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('زيت محلي (100)'), findsOneWidget);
    expect(find.text('أرز بسمتي (200)'), findsNothing);

    // التطبيع في البحث فقط: «غذائيه» بتاء مفتوحة تجيء بالتصنيف
    await tester.enterText(find.byType(TextField).first, 'غذائيه');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('زيت محلي (100)'), findsOneWidget);
    expect(find.text('أرز بسمتي (200)'), findsNothing);

    // النتيجة الفارغة رسالة (س-38)
    await tester.enterText(find.byType(TextField).first, 'غائب تماما');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا نتائج مطابقة للبحث'), findsOneWidget);
  });

  testWidgets('س-39/س-40: تعديل صنف — الكود مقفل بلا حقل تعديل، والاسم '
      'يعدل، والتعطيل بشارة بلا حذف وإعادة التفعيل ممكنة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final unitId = await db.insertUnit(name: 'قطعة');
    await db.insertItem(
      sku: '100',
      name: 'زيت محلي',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('زيت محلي (100)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الهوية الثابتة (D-073): لا حقل تعديل للكود أصلاً في التعديل
    final skuField =
        tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(skuField.enabled, isFalse);
    expect(skuField.controller!.text, '100');

    // زر الحذف غير موجود أصلاً (س-40) — وبالسحبة أقوى: كل الأبناء مبنيون
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('حذف'), findsNothing);

    // س-39: الاسم يعدل ويحفظ — والكود باقٍ كما هو
    await tester.enterText(find.byType(TextFormField).at(1), 'زيت ممتاز');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('زيت ممتاز (100)'), findsOneWidget);

    // س-40: فتح البطاقة ثانية ثم التعطيل — بشارة وبلا حذف
    await tester.tap(find.text('زيت ممتاز (100)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('تعطيل الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // عاد للقائمة — الصنف معطّل بشارة ولا يزال ظاهراً
    expect(find.text('معطّل'), findsOneWidget);
    expect(find.text('زيت ممتاز (100)'), findsOneWidget);

    // إعادة التفعيل من البطاقة نفسها — وبالسحبة نفسها لزر أسفل الشاشة
    await tester.tap(find.text('زيت ممتاز (100)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('إعادة تفعيل الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('معطّل'), findsNothing);
  });

  testWidgets('س-37: صنف خدمة يخزن بلا مخزون لاحقاً — شريحة «خدمة» تكفي', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // «جلسة» لا «خدمة» كي لا يتعارض اسم الوحدة مع ملصق الشريحة في الفاحص
    await db.insertUnit(name: 'جلسة');

    await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('إضافة صنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('اختر الوحدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('جلسة').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField).first, 'S-01');
    await tester.enterText(find.byType(TextFormField).at(1), 'صيانة مبرد');
    await tester.tap(find.text('خدمة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('صيانة مبرد (S-01)'), findsOneWidget);
    final rows = await db.select(db.items).get();
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'service',
        reason: 'F-030: الخدمة صنف بلا أثر مخزون لاحقاً');
  });

  testWidgets('س-36/D-074: الاسم المطابق حرفياً لصنف قائم مرفوض برسالة تحمل '
      'الصنف القائم — و«زيت» غير «زيت» بالتطبيع لا بالحرف (المنع حرفي)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final unitId = await db.insertUnit(name: 'قطعة');
    await db.insertItem(
      sku: '100',
      name: 'زيت محلي',
      kind: 'good',
      baseUnitId: unitId,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: ItemsScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('إضافة صنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    // الوحدة تُختار أولاً كي تظهر رسالة التفرد (ترتيب المدقق) — لا
    // إضافة وحدة من الحوار هنا فالوحدة في القاعدة
    await tester.tap(find.text('اختر الوحدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('قطعة').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField).first, '101');
    await tester.enterText(find.byType(TextFormField).at(1), 'زيت محلي');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text(
          'الاسم مطابق حرفياً لصنف قائم: زيت محلي (100) — اختر اسماً آخر (D-074)'),
      findsOneWidget,
    );
    // عدّل الاسم إلى «زيت محليّ» بشدة — صنف مختلف مشروع (D-074 الحرفي)
    await tester.enterText(find.byType(TextFormField).at(1), 'زيت محليّ');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('زيت محليّ (101)'), findsOneWidget);
  });
}
