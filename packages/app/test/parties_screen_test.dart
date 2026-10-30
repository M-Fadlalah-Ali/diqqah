import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/parties_screen.dart';

/// اختبارات شاشة الأطراف — دفعة م1 (1) على السيناريوهات المعتمدة
/// س-29..س-35 (06 §1-ب) بقرارات D-062..D-066.
///
/// نمط القاعدة هنا `inMemorySyncClose` حصراً: drift يؤجل تنظيف تدفق watch
/// مؤقتاً زائفاً بعد آخر إلغاء اشتراك، وفحص ثوابت flutter_test («مؤقت ما زال
/// معلقاً بعد تفكيك الشجرة») يسبق teardowns فلا سبيل لإطلاقه بعد التفكيك —
/// وكان هذا جذر تعليق ساعات في س22..س25 حتى قُطع الطريق من مصدره بخيار
/// drift الموثق closeStreamsSynchronously (س26). الإغلاق نفسه إغلاق عادي
/// في الteardown — لا runAsync ولا رقصة ضخّات.
void main() {
  // مؤشر الكتابة الوامض يجعل pumpAndSettle تدور إلى مهلتها (10 دقائق لكل
  // موضع — علّة CI 2026-10-29: الوظيفة عالقت 40+ دقيقة بلا نتيجة). التثبيت
  // التجريبي للمؤشر يقضي على المصدر: لا وميض فلا إطارات لا نهائية.
  EditableText.debugDeterministicCursor = true;

  testWidgets('س-29: بطاقة طرف جديد — الرقم مقترح آلياً (0001)، والحفظ بلا '
      'اسم مرفوض برسالة، وبالحفظ يظهر «الاسم (الرقم)» بالقائمة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    // ضخّات محدودة لا pumpAndSettle: مؤشر الانتظار (سطر الشاشة 83) يظل
    // يتحرك حتى يصدر التدفق فلا تستقر pumpAndSettle قبله أبداً.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا أطراف بعد — أضف أول طرف بزر «إضافة طرف»'),
        findsOneWidget);

    await tester.tap(find.text('إضافة طرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // التوليد الآلي (D-063): مقترح 0001 قابل للتعديل قبل الحفظ حصراً
    final numberField =
        tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(numberField.controller!.text, '0001');
    expect(numberField.enabled, isTrue);

    // الاسم إلزامي وحده (س-29) — الحفظ بلا اسم مرفوض برسالة لا صمت
    // (نص الرسالة حرفياً — نص المساعدة تحت الحقل يحمل الكلمات نفسها)
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('الاسم إلزامي وحده — أدخل الاسم ثم احفظ (س-29)'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).at(1), 'محمد الخالدي');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // عاد للقائمة والطرف بصيغة «الاسم (الرقم)» (D-065/س-29)
    expect(find.text('محمد الخالدي (0001)'), findsOneWidget);
    final rows = await db.select(db.parties).get();
    expect(rows, hasLength(1));
    expect(rows.single.number, '0001');
    expect(rows.single.defaultCurrencyId, 1, reason: 'D-066: لا فراغ للعملة');
  });

  testWidgets('س-29: رقم مكرر بعد نزع الأصفار مرفوض برسالة تري صاحبه — '
      '«الرقم 53 مستخدم للطرف: محمد الخالدي (0053)»', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.insertParty(
      number: '0053',
      name: 'محمد الخالدي',
      kind: 'customer',
      defaultCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('إضافة طرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    // المقترح 0002 — يكتب 53 بدله فتصدقه قاعدة التفرد المطبَّع (D-063)
    await tester.enterText(find.byType(TextFormField).first, '53');
    await tester.enterText(find.byType(TextFormField).at(1), 'آخر');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('الرقم 53 مستخدم للطرف: محمد الخالدي (0053)'),
        findsOneWidget);
    expect(find.text('حفظ'), findsOneWidget,
        reason: 'بقي على البطاقة — لم يُحفظ المكرر');
    expect(await db.select(db.parties).get(), hasLength(1));
  });

  testWidgets('س-31/D-064: البحث الجامع المطبَّع — «خال 53» و«احمد» ونتيجة '
      'فارغة برسالة لا بصمت', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.insertParty(
      number: '0012',
      name: 'أحمد الغالي',
      kind: 'customer',
      phone: '0999',
      defaultCurrencyId: 1,
    );
    await db.insertParty(
      number: '0053',
      name: 'محمد الخالدي',
      kind: 'both',
      defaultCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('أحمد الغالي (0012)'), findsOneWidget);
    expect(find.text('محمد الخالدي (0053)'), findsOneWidget);

    // كلمات متفرقة تلتقي: «خال» في الاسم و«53» في الرقم بأي ترتيب
    await tester.enterText(find.byType(TextField).first, 'خال 53');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('محمد الخالدي (0053)'), findsOneWidget);
    expect(find.text('أحمد الغالي (0012)'), findsNothing);

    // التطبيع في البحث فقط: «احمد» بلا همزة تجيء بـ«أحمد»
    await tester.enterText(find.byType(TextField).first, 'احمد');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('أحمد الغالي (0012)'), findsOneWidget);
    expect(find.text('محمد الخالدي (0053)'), findsNothing);

    // النتيجة الفارغة رسالة (س-31)
    await tester.enterText(find.byType(TextField).first, 'غائب تماما');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا نتائج مطابقة للبحث'), findsOneWidget);
  });

  testWidgets('س-33: التعطيل بشارة والطرف يبقى بالقائمة — وزر الحذف غير '
      'موجود أصلاً — وإعادة التفعيل ممكنة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.insertParty(
      number: '0053',
      name: 'محمد الخالدي',
      kind: 'customer',
      defaultCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('محمد الخالدي (0053)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بطاقة التعديل أطول من الشاشة: زر التعطيل آخر الأبناء فيبني عند
    // التمرير فقط (قائمة Sliver كسولة حتى داخل مدى الذاكرة المؤقتة) —
    // سحبة تُدخله مدى البناء ثم يُلمس (فشل CI 2026-10-30: 0 widget قبل السحبة)
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // زر الحذف غير موجود أصلاً (س-33) — وبعد التمرير أقوى: كل الأبناء مبنيون
    expect(find.textContaining('حذف'), findsNothing);
    await tester.tap(find.text('تعطيل الطرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // عاد للقائمة — الطرف معطّل بشارة ولا يزال ظاهراً
    expect(find.text('معطّل'), findsOneWidget);
    expect(find.text('محمد الخالدي (0053)'), findsOneWidget);

    // إعادة التفعيل من البطاقة نفسها — وبالسحبة نفسها لزر أسفل الشاشة
    await tester.tap(find.text('محمد الخالدي (0053)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('إعادة تفعيل الطرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('معطّل'), findsNothing);
  });

  testWidgets('س-32: تعديل طرف — الرقم مقفل بلا حقل تعديل، والاسم يعدل '
      'بالمرجع فيبقى الرقم كما هو', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.insertParty(
      number: '0053',
      name: 'محمد الخالدي',
      kind: 'customer',
      defaultCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('محمد الخالدي (0053)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // الهوية الثابتة (D-063): لا حقل تعديل للرقم أصلاً في التعديل
    final numberField =
        tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(numberField.enabled, isFalse);
    expect(numberField.controller!.text, '0053');

    await tester.enterText(find.byType(TextFormField).at(1), 'محمد المعدل');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('محمد المعدل (0053)'), findsOneWidget);
    final row = await (db.select(db.parties)
          ..where((t) => t.number.equals('0053')))
        .getSingle();
    expect(row.name, 'محمد المعدل');
    expect(row.id, isNotNull);
  });

  testWidgets('س-30/س-34: الطرف المزدوج «الاثنان معاً» بصف واحد، وحد '
      'الائتمان يخزن والفراغ فيه بلا سقف', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('إضافة طرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // ملصق النوع المزدوج «عميل ومورد معاً» حرفاً من مجال الأطراف (لا
    // «الاثنان معاً» — نص التوثيق لا نص الواجهة — فشل CI 2026-10-30:
    // 0 widget) وقربه حقل الائتمان أسفل الشاشة: سحبة تُدخل الاثنين مدى
    // البناء ثم يُلمس الشريحة ويُكتب الحد
    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('عميل ومورد معاً'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField).at(1), 'شركة الرحمة');
    await tester.enterText(find.byType(TextFormField).last, '5000');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final rows = await db.select(db.parties).get();
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'both', reason: 'س-30: صف مرجعي واحد للدورتين');
    expect(rows.single.creditLimitBaseMinor, 5000,
        reason: 'س-34: يخزن بوحدات صغرى');
    // ملصق النوع في القائمة من مجال الأطراف — محصوراً ببلاط القائمة إذ قد
    // تكون شريحة بطاقة التعديل ما تزال بشجرتها في طور الخروج لحظة الفحص
    // (فشل CI 2026-10-30: وجد النص مرتين — العنوان الفرعي وشريحة البطاقة)
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.textContaining('عميل ومورد معاً'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('س-29/D-065: الاسم المطابق حرفياً لطرف قائم مرفوض برسالة تحمل '
      'الطرف القائم — و«احمد» غير «أحمد» (المنع حرفي)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.insertParty(
      number: '0001',
      name: 'أحمد',
      kind: 'customer',
      defaultCurrencyId: 1,
    );

    await tester.pumpWidget(MaterialApp(home: PartiesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('إضافة طرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField).at(1), 'أحمد');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text(
          'الاسم مطابق حرفياً لطرف قائم: أحمد (0001) — اختر اسماً آخر (D-065)'),
      findsOneWidget,
    );
    // عدّل الاسم إلى «احمد» بلا همزة — طرف مختلف مشروع (D-065 الحرفي)
    await tester.enterText(find.byType(TextFormField).at(1), 'احمد');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('احمد (0002)'), findsOneWidget);
  });
}
