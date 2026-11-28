import 'dart:convert' show base64Decode;
import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/item_images.dart';
import 'package:diqqah_app/items_screen.dart';
import 'package:diqqah_app/print_image_prefs.dart';
import 'package:diqqah_app/print_service.dart';
import 'package:diqqah_app/reports_screen.dart';
import 'package:diqqah_app/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات دفعة (10) «الصور والباركود» — س-123..س-132 وقراراتها
/// D-118..D-126 بلفوظ المالك الحرفية من نقاش الجولات الأربع واعتماده
/// «التنفيذ الآن مع الباركود والحزم الثلاث / ابدأ التنفيذ» (س41).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة (درس س22..س26)،
/// ومجلد الصور جذر مؤقت لكل اختبار (D-125: ملفات بجوار القاعدة لا
/// دمج فيها)، وقارئ الكاميرا حقن اختباري فلا قناة منصة أبداً.
///
/// درس IO المتزامن (علّة CI 2026-11-01 — الجولة 128): بيئة testWidgets
/// الوهمية لا تكمل عمليات الملفات غير المتزامنة خارج runAsync — فكل
/// تهيئة المجلدات والملفات بـSync وكتابة الصور مُغلّفة بـrunAsync
/// (نمط widget_test الموثق)، والاستطلاع بزمن واقعي يُشبع السلاسل الحية.
///
/// نقاط المالك الحرفية التي أنجبت هذه الدفعة: «يهمني جداً جداً وجود
/// صورة الصنف في البطاقة والفاتورة بأنواعها عند الإدخال وعند الطباعة»
/// و«طبعاً صورة واحدة تكفي، لسنا في موقع على الانترنت» و«يمكن إلغاؤه
/// افتراضياً ويحتاج تفعيله الدخول إلى الإعدادات ثم اختيار أين نريد
/// تفعيلها افتراضياً» و«فكرة الصورة في تقرير جرد المواد أو حركة
/// المادة ضرورية».
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول: ListView يبني الظاهر حصراً — التمرير حتى يظهر
  /// النص المطلوب قبل لمسه (نمط batch9 الموثق) — والسقف 14 سحبة كي
  /// تكفي أعمق بطاقة (النسخة المستقلة أسفل الإعدادات بوجه الجولة 130).
  Future<void> _scrollToText(WidgetTester tester, String text) async {
    for (var i = 0; i < 14 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -260));
      await tester.pump();
    }
    final f = find.text(text);
    if (f.evaluate().isNotEmpty) {
      await tester.ensureVisible(f.last);
      await tester.pump();
    }
  }

  /// درس widget_test (F-012): سلسلة IO حقيقية داخل اختبار الواجهة
  /// تحتاج escape لزمن واقعي — استطلاع بـrunAsync وضخ حتى يتحقق الشرط
  /// (مهلة 60×50ms) — بلا pumpAndSettle لا مهلة كاملة.
  Future<bool> _waitUntil(
    WidgetTester tester,
    Future<bool> Function() condition,
  ) async {
    for (var i = 0; i < 60; i++) {
      if (await condition()) return true;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    return condition();
  }

  /// ضخّات محدودة موحدة مكان pumpAndSettle (درس الجولات المعلقة).
  Future<void> _pump(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
  }

  setUp(() {
    // مفاتيح الطباعة (نمط D-104) بمخزن وهمي — لا قنوات في الاختبارات،
    // والافتراضي معطل في كل المستندات (D-123) فلا قيم مسبقة.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// أصغر JPEG صالح (1×1) — حقن موحد لكل مسارات الإدخال.
  const jpeg1x1Base64 =
      '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkS'
      'Ew8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJ'
      'CQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
      'MjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEA'
      'AAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIh'
      'MUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6'
      'Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZ'
      'mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx'
      '8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
      'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAV'
      'YnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hp'
      'anN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPE'
      'xcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3'
      '+iiigD//2Q==';
  final jpeg1x1 = base64Decode(jpeg1x1Base64);

  /// IO متزامن حصراً — createTemp غير المتزامن داخل الزمن الوهمي لا
  /// يكتمل أبداً فعلِقت به سبعة اختبارات 10 دقائق (الجولة 128).
  Directory useTempImagesRoot() {
    final root = Directory.systemTemp.createTempSync('diqqah_b10_');
    ItemImagesStore.root = root.path;
    return root;
  }

  Future<Item> itemBySku(DiqqahDatabase db, String sku) async {
    return (db.select(db.items)..where((t) => t.sku.equals(sku)))
        .getSingle();
  }

  /// درس العزل (علّة CI الجولة 132): خرائط مفاتيح الطباعة ValueNotifier
  /// عامة على مستوى الملف فتسري تفعيلات اختبار على ما بعده (تفعيل sale
  /// بس-127 وصل س-128-ب) — كل اختبار مفاتيح يعيد الافتراضي أولاً كي
  /// يكون حكمه بذاته لا بإرث اختبار سابق (مخزن prefs وهمي أصلاً في setUp).
  void resetPrintImagePrefs() {
    for (final (key, _) in kPrintImageChoices) {
      savePrintImagePref(key, false);
    }
  }

  testWidgets('س-125 (D-122): النائب البصري — دائرة بأول حرف لمن بلا '
      'صورة، وصورة حقيقية لمن أدخلها', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: ItemImageBox(itemName: 'زيت محلي', size: 48),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('ز'), findsOneWidget,
        reason: 'بلا صورة: أول حرف الاسم بدل صورة مكسورة أو شاشة مكشحة');

    // ببايتات جاهزة: الصورة تُعرض ولا حرف
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ItemImageBox(
            itemName: 'زيت محلي',
            size: 48,
            pendingBytes: jpeg1x1,
          ),
        ),
      ),
    ));
    await _pump(tester);
    expect(find.text('ز'), findsNothing);
  });

  testWidgets('س-123 (D-120/D-121): من المعرض إلى المحرك الإلزامي — إطار '
      'مربع ثم حفظ يكتب الملفين ويثبت المسارين النسبيين', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final root = useTempImagesRoot();
    addTearDown(() => root.deleteSync(recursive: true));

    await tester.pumpWidget(MaterialApp(
      home: ItemEditScreen(
        db: db,
        // حقن الاختبار بدل منتقي المنصة — لا قناة أبداً
        onPickSource: ({required bool fromCamera}) async => jpeg1x1,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await _scrollToText(tester, 'من المعرض');
    await tester.tap(find.text('من المعرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // شاشة الإطار المربع (D-121) مفتوحة — والافتراضي الصورة كاملة
    expect(find.text('إطار صورة الصنف'), findsOneWidget);
    // درس السرد الكسول بوجه الجولة 130: زر التأكيد أسفل شاشة القص لا يُبنى
    // في ListView الكسول قبل التمرير — ensureVisible لا تجد ما لم يُبنَ
    // (StateError: No element) — scrollUntilVisible تسحب حتى يوجد ثم
    // تضعه كله في المرئي قبل اللمس
    await tester.scrollUntilVisible(
      find.text('تأكيد الإطار'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(find.text('تأكيد الإطار'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // العودة لأعلى البطاقة كي تُبنى حقول الكود والاسم والوحدة (درس
    // السرد الكسول) — وعلة الجولة 131: السحبة أثناء خروج شاشة القص
    // تصيب طبقتها الخارجة لا البطاقة (نمط علة س30 نفسه) — ضخّ كامل
    // لانتقال الرجوع أولاً ثم سحبات محدودة حتى يُبنى حقل الكود أعلى
    // البطاقة لا سحبتان عمياء لا أثر لهما.
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0;
        i < 8 && find.text('كود الصنف (الأساس)').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextFormField).at(0), 'P-1');
    await tester.enterText(find.byType(TextFormField).at(1), 'صنف مصوّر');
    await tester.tap(find.text('اختر الوحدة'));
    await _pump(tester);
    await tester.tap(find.text('قطعة').last);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('حفظ'));
    // استطلاع قاعدة البيانات حتى يكتمل الحفظ بملفاته (IO حقيقي —
    // بلا pumpAndSettle الذي يحرق مهلته على أي إطار مجدول)
    final saved = await _waitUntil(tester, () async {
      final rows = await db.select(db.items).get();
      return rows.any((r) => r.sku == 'P-1' && r.imageFile != null);
    });
    expect(saved, isTrue, reason: 'الحفظ بالصورة اكتمل خلال مهلة الاستطلاع');

    final row = await itemBySku(db, 'P-1');
    expect(row.imageFile, isNotNull);
    expect(row.imageThumb, isNotNull);
    final original = File(p.join(root.path, row.imageFile!));
    final thumb = File(p.join(root.path, row.imageThumb!));
    // المسار يُثبت على الصف بعد اكتمال الكتابة حصراً — الفحص متزامن
    // (exists غير المتزامن تعليق آخر من نفس العلة)
    expect(original.existsSync(), isTrue);
    expect(thumb.existsSync(), isTrue);
    expect(original.lengthSync(), greaterThan(0));
    expect(thumb.lengthSync(), greaterThan(0));
    // D-125: الصور بجوار القاعدة في مجلدها لا داخل ملف القاعدة
    expect(p.basename(p.dirname(row.imageFile!)), 'images');
  });

  testWidgets('س-124 (D-119): حذف الصورة بمطابقة يمسح الحقل والملفين — '
      'و«صورة واحدة تكفي» بلا معرض', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final root = useTempImagesRoot();
    addTearDown(() => root.deleteSync(recursive: true));

    final id = await db.insertItem(
      sku: 'P-2',
      name: 'صنف بصورة',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );
    // كتابة الملفين IO حقيقي — runAsync يهرب للزمن الواقعي (درس F-012)
    // — وتوقيع runAsync يعيد T? فالتأكيد بعد الانتظار (درس analyze الجولة 129)
    final paths = (await tester.runAsync(() => writeItemImagesFiles(
          itemId: id,
          original: jpeg1x1,
          thumb: jpeg1x1,
        )))!;
    await db.setItemImages(id, imageFile: paths.$1, imageThumb: paths.$2);

    final item = await itemBySku(db, 'P-2');
    await tester.pumpWidget(
        MaterialApp(home: ItemEditScreen(db: db, existing: item)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await _scrollToText(tester, 'حذف الصورة');
    expect(find.text('حذف الصورة'), findsOneWidget);
    await tester.tap(find.text('حذف الصورة'));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    // استطلاع حتى يكتمل الحفظ والمسح معاً — شرط القاعدة وحده سباق:
    // مسح الحقل يسبق مسح الملفين فتخرج قيمة حقيقية قبل زوال الملفات
    // (علّة سباق محتملة كُشفت بالمراجعة — الشرط يجمع القاعدة والملفات)
    final cleared = await _waitUntil(tester, () async {
      final r = await itemBySku(db, 'P-2');
      return r.imageFile == null &&
          r.imageThumb == null &&
          !File(p.join(root.path, paths.$1)).existsSync() &&
          !File(p.join(root.path, paths.$2)).existsSync();
    });
    expect(cleared, isTrue,
        reason: 'س-124: الحذف بمطابقة اكتمل خلال مهلة الاستطلاع');

    final row = await itemBySku(db, 'P-2');
    expect(row.imageFile, isNull);
    expect(row.imageThumb, isNull);
    expect(File(p.join(root.path, paths.$1)).existsSync(), isFalse,
        reason: 'س-124: لا ملفات يتيمة بعد الحذف');
    expect(File(p.join(root.path, paths.$2)).existsSync(), isFalse);
  });

  testWidgets('س-126 (D-118): مصغّر الصورة في بطاقة بند الفاتورة فور '
      'اختيار الصنف — المشتق المصغر لا الأصل', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final root = useTempImagesRoot();
    addTearDown(() => root.deleteSync(recursive: true));

    final oil = await itemBySku(db, 'Z-100');
    // كتابة الملفين IO حقيقي — runAsync يهرب للزمن الواقعي (درس F-012)
    // — وتوقيع runAsync يعيد T? فالتأكيد بعد الانتظار (درس analyze الجولة 129)
    final paths = (await tester.runAsync(() => writeItemImagesFiles(
          itemId: oil.id,
          original: jpeg1x1,
          thumb: jpeg1x1,
        )))!;
    await db.setItemImages(oil.id, imageFile: paths.$1, imageThumb: paths.$2);

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('الصنف').first);
    await _pump(tester);
    await tester.tap(find.textContaining('Z-100 زيت محلي').last);
    await tester.pump(const Duration(milliseconds: 100));

    // بطاقة البند تحمل موضع الصورة — والمصدر المشتق المصغر حصراً
    expect(find.byType(ItemImageBox), findsWidgets);
    final box =
        tester.widget<ItemImageBox>(find.byType(ItemImageBox).first);
    expect(box.imagePath, paths.$2,
        reason: 'س-126: المشتق المصغر حصراً — الأصل للطباعة لا للسطور');
  });

  test('س-127 (D-123): الطباعة بالصور معطلة افتراضياً في كل الأنواع '
      '— والتفعيل من الإعدادات وحدها، والعمود يدخل PDF بالاحتواء',
      () async {
    resetPrintImagePrefs();
    // الافتراضي معطل في الأنواع الأربعة والتقريرين (بلفظ المالك)
    for (final kind in InvoiceKind.values) {
      expect(printImagesForKind(kind), isFalse);
    }
    expect(printImageInventory.value, isFalse);
    expect(printImageMovement.value, isFalse);

    // التفعيل من الإعدادات — مفتاح النوع المستقل
    savePrintImagePref('sale', true);
    expect(printImagesForKind(InvoiceKind.sale), isTrue);
    expect(printImagesForKind(InvoiceKind.purchase), isFalse,
        reason: 'س-128: مفاتيح مستقلة لا تساقط');

    // العمود بالصور يدخل PDF (JPEG يدخل بلا إعادة ضغط D-119)
    final bytes = await buildDocumentPdf(
      title: 'فاتورة بيع تجريبية',
      headerPairs: const [],
      columns: const ['الصنف', 'الكمية'],
      rows: const [
        ['زيت محلي', '2'],
      ],
      rowLeadingImages: [jpeg1x1],
      rowPlaceholderLetters: const ['ز'],
      footerPairs: const [],
      format: resolvePageFormat(docKind: 'invoice'),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    // وبلا صور: الممر النصي القائم كما هو (الافتراضي المعطل)
    final plain = await buildDocumentPdf(
      title: 'فاتورة بيع تجريبية',
      headerPairs: const [],
      columns: const ['الصنف'],
      rows: const [
        ['زيت محلي'],
      ],
      footerPairs: const [],
      format: resolvePageFormat(docKind: 'invoice'),
    );
    expect(String.fromCharCodes(plain.take(4)), '%PDF');
  });

  testWidgets('س-128 (D-118) أ: تقرير المخزون بلا صور افتراضاً — المفتاح '
      'المعطل لا يضيف موضع صورة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db); // زيت 4 متاح — صف مخزون قائم
    useTempImagesRoot();

    // ضخّات محدودة لا pumpAndSettle (درس س22..س26 ودرس حلقة المستقبل)
    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    // س206: تنظيم م09 أطال القائمة فالبند أسفل الطيّة — الوصول بالتمرير (درس D-098).
    await _scrollToText(tester, 'تقرير المخزون');
    await tester.tap(find.text('تقرير المخزون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ItemImageBox), findsNothing,
        reason: 'الافتراضي معطل في التقريرين أيضاً (D-123) — بلا موضع '
            'صورة ولا قراءة ملفات بلا سبب');
  });

  testWidgets('س-128 (D-118) ب: تفعيل مفتاح المخزون وحده يجعل الصورة '
      'عموداً في التقرير — والنائب البصري لمن بلا صورة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db); // زيت 4 متاح — صف مخزون قائم
    useTempImagesRoot();

    // المفتاح المستقل — إعادة الضبط أولاً (درس العزل أعلاه) ثم تفعيل
    // المخزون وحده — بلا إعادة فتح ولا مكدس ملاح (درس الجولة 131:
    // تقسيم الطورين اختبارين مستقلين أضمن من الرجوع وإعادة الفتح)
    resetPrintImagePrefs();
    savePrintImagePref('inventory', true);
    expect(printImagesForKind(InvoiceKind.sale), isFalse,
        reason: 'مفتاح المخزون لا يُسوق بقية المفاتيح — استقلال D-123');

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(db: db)));
    await tester.pump();
    // س206: تنظيم م09 أطال القائمة فالبند أسفل الطيّة — الوصول بالتمرير (درس D-098).
    await _scrollToText(tester, 'تقرير المخزون');
    await tester.tap(find.text('تقرير المخزون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ItemImageBox), findsWidgets,
        reason: 'بلفظ المالك: «فكرة الصورة في تقرير جرد المواد أو حركة '
            'المادة ضرورية»');
    expect(find.text('ز'), findsWidgets,
        reason: 'الصنف بلا صورة يعرض النائب بأول حرف (س-125)');
  });

  test('س-129 (D-124): سطر حجم مجلد الصور بالصياغة الإنسانية — '
      'و«بلا صور بعد» لما فرغ', () {
    expect(formatImagesBytes(0), 'بلا صور بعد');
    expect(formatImagesBytes(512 * 1024), '512 كيلوبايت');
    expect(formatImagesBytes(4 * 1024 * 1024 + 200 * 1024), '4.2 ميغابايت');
  });

  testWidgets('س-129/س-130: شاشة الإعدادات — مربع التضمين بسطر الحجم '
      'وبطاقة النسخة المستقلة ظاهرتان', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    // IO متزامن حصراً — نمط widget_test (علّة createTemp الوهمية)
    final root = Directory.systemTemp.createTempSync('diqqah_b10_set_');
    addTearDown(() => root.deleteSync(recursive: true));
    final dbPath = p.join(root.path, 'diqqah.db');
    final imagesDir = Directory(p.join(root.path, 'images'));
    imagesDir.createSync(recursive: true);
    File(p.join(imagesDir.path, 'item-9.jpg'))
        .writeAsBytesSync(List.filled(2048, 7));

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      db: db,
      dbPath: dbPath,
      onRestored: () {},
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // س233: بطاقة النسخ الآلي وبطاقة فحص الثوابت (بقسمها الجديد) أزاحتا
    // بطاقة العرض أسفل — سحبٌ إلى مربع التضمين قبل التوقع (درس D-098).
    await _scrollToText(tester, 'تضمين صور الأصناف');
    expect(find.text('تضمين صور الأصناف'), findsOneWidget,
        reason: 'س-129: مربع التضمين افتراضه مفعّل بحجم المجلد ظاهراً');
    expect(find.textContaining('كيلوبايت'), findsWidgets,
        reason: 'سطر الحجم الحالي للمجلد لا صمت');
    // درس السرد الكسول بوجه الجولة 130: بطاقة النسخة المستقلة أسفل
    // الإعدادات لا تُبنى في ListView الكسول قبل التمرير — التوقع على
    // ما لم يُبنَ صفرٌ دائماً
    await _scrollToText(tester, 'نسخة الصور المستقلة');
    expect(find.text('نسخة الصور المستقلة'), findsOneWidget,
        reason: 'س-130: الأداة المكمّلة بجوار الأساس');
  });

  testWidgets('س-131 (D-126): قسم الباركود في البطاقة — إضافة وحذف '
      'والتفرد برسالة الصنف الحامل الحرفية', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    useTempImagesRoot();

    // صنف آخر حامل رمز — لرسالة التفرد بصيغة «الاسم (الكود)»
    final otherId = await db.insertItem(
      sku: 'P-9',
      name: 'صنف آخر',
      kind: 'good',
      baseUnitId: 1,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
      priceCurrencyId: 1,
    );
    await db.insertItemBarcode(itemId: otherId, barcode: '111222333');

    final oil = await itemBySku(db, 'Z-100');
    await tester.pumpWidget(
        MaterialApp(home: ItemEditScreen(db: db, existing: oil)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // إضافة رمز — Enter بقناة النص (درس CI: receiveAction) — والخانة
    // أسفل الطيّة فتُمرر أولاً (درس السرد الكسول)
    await _scrollToText(tester, 'رمز الباركود');
    await tester.enterText(
        find.widgetWithText(TextField, 'رمز الباركود'), '6290000000017');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('6290000000017'), findsOneWidget);

    // مكرر على نفس الصنف: رفض بهدوء الرسالة المعتمدة
    await tester.enterText(
        find.widgetWithText(TextField, 'رمز الباركود'), '6290000000017');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('الرمز مضاف لهذا الصنف مسبقاً'), findsOneWidget);

    // رمز صنف آخر: رسالة س-131 الحرفية «الرمز مستخدم للصنف: …»
    await tester.enterText(
        find.widgetWithText(TextField, 'رمز الباركود'), '111222333');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('الرمز مستخدم للصنف: صنف آخر (P-9)'), findsOneWidget);
  });

  testWidgets('س-132 (D-126): خانة بحث البنود — الرمز الكامل يجلب الصنف '
      'مباشرة (بلوتوث) ورمز غير مرتبط برسالته الحرفية', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    useTempImagesRoot();

    final oil = await itemBySku(db, 'Z-100');
    await db.insertItemBarcode(itemId: oil.id, barcode: '6290000000017');

    await tester.pumpWidget(
        MaterialApp(home: InvoiceEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // قارئ البلوتوث يكتب الرمز ويعطي Enter — بلا كاميرا أصلاً — والخانة
    // بعد البنود فتُمرر إليها أولاً (درس السرد الكسول)
    const quickLabel = 'بحث سريع بالاسم أو الكود أو الباركود';
    await _scrollToText(tester, quickLabel);
    await tester.enterText(
        find.widgetWithText(TextField, quickLabel),
        '6290000000017');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(TextField, quickLabel), findsOneWidget,
        reason: 'الخانة صُفّت بعد الجلب فجاهزة للرمز التالي');

    // رمز غير مرتبط: رسالة السيناريو الحرفية — قبل العودة لأعلى كي تبقى
    // الخانة مبنية (السرد الكسول)
    await tester.enterText(
        find.widgetWithText(TextField, quickLabel),
        '9999999999999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('رمز غير مرتبط بأي صنف'), findsOneWidget);

    // العودة لأعلى القائمة كي تُبنى بطاقة البند المعبأ بالرمز (درس س35:
    // التمرير بعمق أعمق من النموذج كله)
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Z-100 زيت محلي'), findsWidgets,
        reason: 'الرمز الكامل جلب الصنف للبند مباشرة');
  });
}
