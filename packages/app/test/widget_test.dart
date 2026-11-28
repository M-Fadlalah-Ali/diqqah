import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/main.dart';
import 'package:diqqah_app/items_screen.dart';
import 'package:diqqah_app/parties_screen.dart';
import 'package:diqqah_app/settings_screen.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/boxes_screen.dart';
import 'package:diqqah_app/roles_screen.dart';
import 'package:diqqah_app/unit_groups_screen.dart';
import 'package:diqqah_app/currencies_screen.dart';
import 'package:diqqah_app/sync_work_screen.dart';
import 'test_guard.dart';

void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  // تثبيت المؤشر الوامض تجريبياً — F-016 يفتح شاشة بحقل بحث، والوميض مصدر
  // إطارات لا نهائية لأي ضخّ غير محدود (النمط نفسه الموثق في parties_screen_test)
  EditableText.debugDeterministicCursor = true;
  testWidgets('التدفق الكامل (س-01): أول تشغيل → إنشاء المدير → الشاشة الهيكلية',
      (tester) async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(DiqqahApp(db: db, hasherIterations: 2));
    await tester.pumpAndSettle();

    // F-014: شاشة إنشاء المدير إلزامية قبل أي شاشة أخرى
    expect(find.text('إنشاء المدير'), findsOneWidget);
    expect(find.text('الأطراف'), findsNothing);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'المالك');
    await tester.enterText(fields.at(1), 'owner');
    await tester.enterText(fields.at(2), 'secret123');

    await tester.tap(find.text('إنشاء المدير'));
    // س219: التجزئة الخلفية بعزل منفصل — نافذة واقعية للتسليم ثم ضخّات
    // عودة (نمط س217 الموثق — درس الجولة الحاكمة #443)
    await pumpIsolateHops(tester, hops: 1);

    // س116: بعد ولادة المدير بطاقة «سير أول استخدام» الموجّهة — لا
    // هيكلية قبل زرها، والخطوة الأولى النسخة الاحتياطية (طقس §0/4).
    expect(find.text('سير أول استخدام'), findsOneWidget);
    expect(find.textContaining('النسخة الاحتياطية الأولى'), findsOneWidget);
    expect(find.textContaining('المستودعات والعملات'), findsOneWidget);
    expect(find.textContaining('الأصناف والأطراف'), findsOneWidget);
    expect(find.textContaining('الفترة وأول فاتورة'), findsOneWidget);
    // زر البدء أسفل البطاقات الأربع — السرد الكسول (س35/س36) فتُسحب.
    for (var i = 0;
        i < 4 && find.text('ابدأ الاستخدام').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
    await tester.tap(find.text('ابدأ الاستخدام'));
    await tester.pumpAndSettle();

    // F-016: بعد التهيئة تُفتح الشاشة الهيكلية بشبكة وحدات
    expect(find.text('المالك'), findsNothing); // لا معلومات المستخدم على الشاشة
    expect(find.text('الأطراف'), findsOneWidget);
    expect(find.text('المزامنة'), findsOneWidget);
    // دفعة (18) — س-163/D-161: الفواتير خرجت من القائمة إلى بطاقتها
    // بأزرار الأنواع ثم سُحبت البطاقة بكلمته س202 فصارت بلاطتا
    // المبيعات والمشتريات أول الشبكة — س141: المتابعات بلاطتها.
    // س182 (بأمر المالك «اعتمد مبدأ الأيقونات في الواجهة مباشرة لا
    // القائمة»): الوحدات صارت شبكة بلاطات أيقونية بدل قائمة Tile —
    // Wrap بلا Scrollable ثانٍ فيبقى عرف التمرير واحداً — و18 بلاطة
    // (Tooltip لكل بلاطة بوصف مرحلتها — والمبيعات والمشتريات أولها س202).
    // س209: طبقة النبض Wrap ثانية بالوجود (بداية السنة غير المصدقة
    // متابعة قائمة على القاعدة النظيفة) — فالشبكة بمفتاحها لا بالنوع
    // فلا التباس بين الWrapين، والدرس باقٍ: لا Scrollable ثانٍ داخل
    // التمرير (النبض Wrap فوق الشبكة لا Scrollable أصلاً) — و19 بلاطة
    // ببلاطة «المستخدمون» نهايتها س211/D-216 — وس212: شارة الجلسة
    // صارت قائمة أفعال D-215 بتلميحها فالعشرون (19 بلاطة + الجلسة).
    expect(find.byKey(const Key('home_modules_grid')), findsOneWidget);
    expect(find.byType(Tooltip), findsNWidgets(20));

    // F-015: device_id وُلد خلال التهيئة وأصبح في القاعدة
    expect(await db.deviceId(), hasLength(36));
  });

  testWidgets('قاعدة فيها مدير: الشاشة الهيكلية مباشرة — لا شاشة أولى',
      (tester) async {
    final db = DiqqahDatabase.inMemory();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('إنشاء المدير'), findsNothing);
    expect(find.text('دِقَّة'), findsOneWidget); // AppBar الهيكلية
    expect(find.text('الأصناف'), findsOneWidget);
  });

  testWidgets('F-016: الأطراف والأصناف والوحدات والمستودعات والتقارير اليومية فُتحت بدفعاتها مع الإعدادات — والبقية معطلة؛\n'
      'وفتح الأطراف يفتح شاشتها والبحث فيها يعمل', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    // الإغلاق العادي يكفي — القاعدة بنمط inMemorySyncClose (س26) فلا مؤقت
    // يُجدول عند إلغاء تدفق watch عند تفكيك الشجرة، ولا runAsync ولا ضخّات.
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // س182: بلاطات الشبكة — 19 بلاطة (18 وحدة + الإعدادات — س208: والمستخدمون نهايتها): بلاطتا
    // الفواتير الجهويتان دخلتا الشبكة أولها بكلمته س202
    // («التراجع عنه إلى أيقونتين كالبقية») وبطاقة الأنواع سُحبت
    // والمعطّل بلاطة بلا فتح (onTap=null).
    final tiles = tester.widgetList<InkWell>(find.descendant(
        of: find.byKey(const Key('home_modules_grid')),
        matching: find.byType(InkWell)));
    expect(tiles.length, 19); // 18 وحدة (المبيعات والمشتريات أولها — س202، والمستخدمون نهايتها — س211/D-216) + الإعدادات
    final locked = tiles.where((t) => t.onTap == null).length;
    expect(locked, 0,
        reason: 'المبيعات والمشتريات (س202) والأطراف والأصناف والتقارير اليومية (دفعات م1 1..6-ب) '
            'والصناديق والصلاحيات (دفعة 6-ج) والسندات (دفعة الإغلاق س37) '
            'ومتابعة التسليم (دفعة 12/D-133) والمستودعات (الدفعة 24 '
            'أولى م2/س77/D-185) والوحدات والعملات (D-198 س98) والطلبات '
            '(س123) والذمم والدفتر المحاسبي (س125) — '
            'والمزامنة فُتحت آخر المعطلات بكلمة المالك «لا زالت بلاطة '
            'المزامنة غير مفعلة في نسخة b55» (س178) فلا معطلات بعد — '
            'وبطاقة الفواتير سُحبت بدفعة س202 فصارت البلاطتان أول الشبكة');
    final open = tiles.where((t) => t.onTap != null).length;
    expect(open, 19, // + المستخدمون (س211/D-216)
        reason: 'المبيعات والمشتريات (س202) والأطراف والأصناف والوحدات والمستودعات '
            'والسندات ومتابعة التسليم والطلبات (س123) '
            'والذمم والدفتر المحاسبي (س125) '
            'والصناديق والعملات والصلاحيات والإعدادات '
            'والمتابعات (س141 — د-7) '
            'والمزامنة (س178 — نافذة العمل الجماعي س175)');

    // الأطراف فوق الخط الافتراضي — تمرير ثم فتح ثم رجوع
    await tester.scrollUntilVisible(
      find.text('الأطراف'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('الأطراف'));
    // ضخّات محدودة لا pumpAndSettle: مؤشر انتظار شاشة الأطراف (StreamBuilder)
    // يتحرك حتى يصدر التدفق فلا تستقر قبله (علّة CI 2026-10-29 — تعليق 40+ د).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا أطراف بعد — أضف أول طرف بزر «إضافة طرف»'),
        findsOneWidget);
    expect(find.byType(PartiesScreen), findsOneWidget);
  });

  testWidgets('D-198 (س98): بلاطتا «الوحدات» (وحدات القياس والتعبئة سابقاً '
      'باختصار س202) و«العملات» مفتوحتان بالهيكلية '
      'وفتحهما يفتح شاشتيهما — نفس الشاشتين المدخلتين من الأصناف والإعدادات',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // بلاطة الوحدات تسمى «الوحدات» بأمر المالك س202 («تصحيح إلى وحدات»)
    // — تمرير حتى الظهور ثم فتحها
    // (نمط اختبار الأطراف: ضخّات محدودة لا pumpAndSettle بعد الفتح).
    await tester.scrollUntilVisible(
      find.text('الوحدات'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('الوحدات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UnitGroupsScreen), findsOneWidget,
        reason: 'الوحدات فُتحت بشاشة مجموعات التعبئة نفسها');
    expect(find.text('مجموعات التعبئة'), findsOneWidget);

    // رجوع ثم فتح بلاطة العملات بنفس النمط — الرجوع بحالة الملاح
    // مباشرة (المطبوعات Material لا Cupertino فلا pageBack).
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('العملات'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('العملات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CurrenciesScreen), findsOneWidget,
        reason: 'العملات فُتحت بشاشة الإعدادات نفسها (درس D-098: بند ظاهر لا مدفون)');
    expect(find.text('إضافة عملة'), findsOneWidget);
  });

  testWidgets('س178 (تفعيل المزامنة بكلمة المالك «لا زالت بلاطة المزامنة '
      'غير مفعلة في نسخة b55»): بلاطة المزامنة مفتوحة بالهيكلية وتفتح '
      'نافذة العمل الجماعي ذاتها المدخلة من الإعدادات (س175)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // البلاطة قبل الإعدادات آخر القائمة — تمرير حتى الظهور ثم فتحها
    // (نمط اختبار D-198: ضخّات محدودة لا pumpAndSettle بعد الفتح —
    // مؤقت شاشة العضوية يتحرك حتى تصدر القراءة).
    await tester.scrollUntilVisible(
      find.text('المزامنة'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('المزامنة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SyncWorkScreen), findsOneWidget,
        reason: 'المزامنة تُفتح بنافذة العمل الجماعي ذاتها (س175) — '
            'لا شاشة ثانية');
    expect(find.text('هذا الجهاز'), findsOneWidget);
    expect(find.text('رمز الانضمام'), findsOneWidget);
    expect(find.text('سجل الأجهزة'), findsOneWidget);
  });

  testWidgets('دفعة م1 (2): فتح الأصناف من الشاشة الهيكلية يفتح شاشتها — '
      'وفراغها رسالة إرشاد لا صمت', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('الأصناف'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('الأصناف'));
    // ضخّات محدودة لا pumpAndSettle — نمط شاشة الأطراف الموثق (س23)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('لا أصناف بعد — أضف أول صنف بزر «إضافة صنف»'),
        findsOneWidget);
    expect(find.byType(ItemsScreen), findsOneWidget);
  });

  testWidgets('دفعة (6-ج) بأمر المالك «تنفيذها كلها معاً» (س36): الفواتير '
      'والصناديق والصلاحيات تنفتح من الهيكلية بشاشاتها وفراغاتها المرسلة',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // الفواتير — بلاطتا المبيعات والمشتريات أول الشبكة (س202 بأمر
    // المالك «التراجع عنه إلى أيقونتين كالبقية») وبطاقة الأنواع سُحبت:
    // بلاطة المبيعات تفتح الأرشيف بجهته وفراغه رسالة إرشاد لا صمت
    // (F-162 روحاً).
    expect(find.text('المبيعات'), findsOneWidget);
    expect(find.text('المشتريات'), findsOneWidget);
    expect(find.text('سجل الفواتير'), findsNothing,
        reason: 'الأرشيف ذاب في البلاطتين — لا زر سجل مستقل بالرئيسية');
    await tester.tap(find.text('المبيعات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(InvoicesScreen), findsOneWidget);
    // نص البلاطة تحت الطريق المصرَّع ما يزال بالشجرة — فالعنوان
    // محصور بشريط الشاشة العلوية لا find.text طائلاً (درس الجولة #386).
    expect(
        find.descendant(
            of: find.byType(AppBar),
            matching: find.text('المبيعات')),
        findsOneWidget,
        reason: 'عنوان الجهة بلسان بلاطتها (س202)');
    expect(find.textContaining('لا فواتير بعد'), findsOneWidget);
    // س-135/D-129: توطين الواجهة عربياً غيّر تلميح زر الرجوع —
    // pageBack يبحث عن «Back» الإنجليزية فلم يجدها، والنمط الموحد
    // find.backButton() بعدها إعادة بناء كاملة.
    await tester.tap(find.backButton());
    await tester.pumpAndSettle();

    // زر «فاتورة جديدة» بالأرشيف يفتح ورقة نوعَي الجهة حصراً (س202) —
    // والضغط الصريح يفتح النموذج بنوعه المثبت — لا مبدّل نوع بالنموذج (س-163)
    await tester.tap(find.text('المبيعات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('فاتورة جديدة'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة بيع'), findsOneWidget);
    expect(find.text('مردود بيع'), findsOneWidget);
    expect(find.text('فاتورة شراء'), findsNothing,
        reason: 'ورقة الجهة نوعاها حصراً — المبيعات ببيعها ومردودها (س202)');
    await tester.tap(find.text('فاتورة بيع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(InvoiceEditScreen), findsOneWidget);
    expect(find.text('نوع الفاتورة'), findsNothing);
    // درس جولة CI (فشل الدفعة 18): لسان الورقة بالشاشة التحتية ما يزال
    // مبنياً لحظة الفحص (لمعان الانتقال) — والنطاق شاشة النموذج ذاتها
    // فهو الحارس الحقيقي: النموذج لا يعرض لسان الورقة أصلاً.
    expect(
        find.descendant(
            of: find.byType(InvoiceEditScreen),
            matching:
                find.text('فاتورة جديدة — اختر النوع بالضغط')),
        findsNothing);
    // زر الرجوع اثنان الآن: النموذج فوق الأرشيف (له زره) فوق الرئيسية
    // (بلا زر) — فالنقر محصور بنطاق النموذج لا find.backButton الطائلاً
    // (درس الجولة #387).
    await tester.tap(find.descendant(
        of: find.byType(InvoiceEditScreen),
        matching: find.backButton()));
    await tester.pumpAndSettle();
    // الرجوع من النموذج يهبط بالأرشيف لا بالرئيسية — المسار الجديد
    // (الرئيسية ← الأرشيف ← ورقة الجهة ← النموذج — س202) — فرجوعٌ ثانٍ
    // من الأرشيف إلى الرئيسية قبل فتح الصناديق (درس الجولة #388).
    await tester.tap(find.backButton());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('الصناديق'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('الصناديق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(BoxesScreen), findsOneWidget);
    expect(find.textContaining('حساب 1111 · SYP'), findsOneWidget);
    // س-135/D-129: توطين الواجهة عربياً غيّر تلميح زر الرجوع —
    // pageBack يبحث عن «Back» الإنجليزية فلم يجدها، والنمط الموحد
    // find.backButton() بعدها إعادة بناء كاملة.
    await tester.tap(find.backButton());
    await tester.pumpAndSettle();

    // الصلاحيات — عرض قراءة حصراً (D-097)
    await tester.scrollUntilVisible(
      find.text('الصلاحيات'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('الصلاحيات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RolesScreen), findsOneWidget);
    // س164 غيّرت اللسان: «الأدوار النمطية» بلا «الأربعة» مع البوابة
    // الملحقة وقابليتها للمنح حتى للبائع.
    expect(find.textContaining('الأدوار النمطية مزروعة بأذوناتها'),
        findsOneWidget);
  });

  testWidgets('F-012 + D-050 + D-060: زر النسخ ينتج نسخة مشفرة بمفتاح البرنامج في مجلد القاعدة',
      (tester) async {
    // IO متزامن — بيئة testWidgets الوهمية لا تكمل عمليات الملفات غير المتزامنة
    final tempDir = Directory.systemTemp.createTempSync('diqqah_settings_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase.fileSyncClose(filePath: dbPath);
    addTearDown(db.close);
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-001',
            name: 'بضاعة',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 0,
            salePriceMinor: 500,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-w-001',
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    // D-060: التشفير مشدود افتراضياً — النسخة بمفتاح البرنامج بلا أي كلمة:
    // لا حقل كلمة مرور أصلاً، والنقر على الزر يكفي.
    // س213 (D-218): إعادة تنظيم الإعدادات أزاحت البطاقة تحت أول
    // نافذة البناء — تأكيد وصول بنمط D-098 قبل النقر.
    // س233: بطاقة النسخ الآلي أطالت القائمة فخرج الزر من نطاق البناء
    // الكسول — سحبٌ حتى يُبنى ثم إظهار (درس D-098 والسرد الكسول).
    for (var i = 0;
        i < 12 && find.text('إنشاء نسخة احتياطية').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    // النسخ فيها IO حقيقي متسلسل (VACUUM ← قراءة ← كتابة) لا يكمله الوقت
    // الوهمي — نوازن ضخ الوقت الواقعي مع ضخ الإطارات حتى يظهر حوار النجاح.
    // علّة CI (2026-10-29): رصد «ظهور أي ملف» يلتقط المؤقت .tmp الذي يولده
    // VACUUM INTO — اسمه يطابق بادئة النسخة وهو خام دائماً قبل اكتمال
    // التشفير، فقرأه الاختبار على عدّاد CI البطيء وظنه الناتج. إشارة
    // الاكتمال الصحيحة حوار النجاح: لا يظهر إلا بعد كتابة الملف النهائي
    // وحذف المؤقت — نمط D-056 الذي سلم على CI نفسه.
    final successTitle = find.text('أُنشئت النسخة الاحتياطية');
    var shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة لم يظهر خلال مهلة الاختبار');

    final backups = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('diqqah-backup-'))
        .toList();
    expect(backups, hasLength(1));
    // D-061: النسخة بلاحقة البرنامج الخاصة لا .db
    expect(p.basename(backups.first.path), endsWith('.diqqah'));
    final bytes = backups.first.readAsBytesSync();
    // D-050/D-060: الافتراضي من م1 نسخة مشفرة بمفتاح البرنامج لا خام —
    // وبايتة الإصدار 2 تثبت الجيل الجديد حصراً
    expect(BackupCipher.identify(bytes), BackupKind.encrypted);
    expect(bytes[7], BackupCipher.formatVersion);
    // DoD F-012: الملف أُنتج من الزر — وبلا رسالة فشل على الشاشة
    expect(find.textContaining('تعذر إنشاء النسخة'), findsNothing);
  });

  testWidgets('D-050 + D-060: الإلغاء الواعي للتشفير يفتح تحذيراً — والتراجع '
      'لا ينتج شيئاً ثم النسخة الخام ثم المشفرة بمفتاح البرنامج', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_d050_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase.fileSyncClose(filePath: dbPath);
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    List<File> backups() => tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('diqqah-backup-'))
        .toList();

    // (أ) الإلغاء الواعي: فك التشفير → تحذير صريح → تراجع أولاً لا شيء
    // (D-060: صندوق التشفير بلا أي حقل كلمة مرور بعده)
    // س213 (D-218): تأكيد وصول البطاقة بعد إعادة التنظيم بنمط D-098.
    // س233: نفس درس السحب أعلاه — الوصول بالتمرير قبل الإظهار.
    for (var i = 0;
        i < 12 &&
            find.text('تشفير النسخة بمفتاح البرنامج').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('تشفير النسخة بمفتاح البرنامج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشفير النسخة بمفتاح البرنامج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    expect(find.text('نسخة بدون تشفير'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(backups(), isEmpty, reason: 'التراجع من التحذير لا ينتج شيئاً');

    // (ب) متابعة بدون تشفير بوعي → نسخة خام
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة بدون تشفير'));
    // إشارة الاكتمال حوار النجاح لا «ظهور أي ملف» — المؤقت .tmp يطابق
    // اسم النسخة وقد يُلتقط قبل اكتمال الكتابة أو يُرى معها معاً فتزدهم
    // hasLength — علّة CI 2026-10-29 وهششة كامنة في هذا الموضع.
    final successTitle = find.text('أُنشئت النسخة الاحتياطية');
    var shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة لم يظهر خلال مهلة الاختبار');
    expect(backups(), hasLength(1));
    expect(
      BackupCipher.identify(backups().single.readAsBytesSync()),
      BackupKind.plainSqlite,
    );

    // (ج) رجوع التشفير بوعي → نسخة مشفرة بمفتاح البرنامج (جيل v2)
    await tester.tap(find.text('حسناً')); // إغلاق حوار النجاح أولاً
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشفير النسخة بمفتاح البرنامج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة الثانية لم يظهر');
    expect(backups(), hasLength(2));
    final encryptedBlob = backups()
        .map((f) => f.readAsBytesSync())
        .firstWhere(
            (b) => BackupCipher.identify(b) == BackupKind.encrypted);
    expect(encryptedBlob[7], BackupCipher.formatVersion);
  });

  testWidgets('D-056: زرا التصفح والإخراج في شاشة الإعدادات — إصلاح قيد '
      'أندرويد على مسار data (استيراد منتقي النظام + تصدير نافذة المشاركة)',
      (tester) async {
    // IO متزامن — نفس نمط اختبار F-012 أعلاه
    final tempDir = Directory.systemTemp.createTempSync('diqqah_d056_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase.fileSyncClose(filePath: dbPath);
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    // سيل النسخ أولًا (زرها أعلى الشاشة) — ودرس دفعة 19: بطاقة الترقيم
    // (D-169) أزاحت بطاقة الاستعادة تحت الطي والقابل عنصرُ شجرةٍ غير
    // مبني فلا يجده الباحث — سحبٌ لإظهارها قبل فحص زر التصفح في آخر
    // الاختبار.
    // زر الإخراج يظهر في حوار نجاح النسخة — وجوده لا يستدعي أي قناة منصة
    // D-060: النسخة مشفرة بمفتاح البرنامج افتراضياً — بلا أي حقل كلمة
    // س213 (D-218): تأكيد وصول البطاقة بعد إعادة التنظيم بنمط D-098.
    // س233: بطاقة النسخ الآلي أطالت القائمة فخرج الزر من نطاق البناء
    // الكسول — سحبٌ حتى يُبنى ثم إظهار (درس D-098 والسرد الكسول).
    for (var i = 0;
        i < 12 && find.text('إنشاء نسخة احتياطية').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('إنشاء نسخة احتياطية'));

    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    // نفس درس F-012 أعلاه: سلسلة IO حقيقية ثم دفع الحوار — حلقة توازن
    // (وقت واقعي ← إطار ← فحص) حتى يظهر الحوار، بلا توقيت مفترض (Task 50).
    final successTitle = find.text('أُنشئت النسخة الاحتياطية');
    var shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      shown = successTitle.evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue, reason: 'حوار نجاح النسخة لم يظهر خلال مهلة الاختبار');

    expect(find.text('أُنشئت النسخة الاحتياطية'), findsOneWidget);
    expect(find.text('إخراج النسخة'), findsOneWidget);
    expect(find.text('حسناً'), findsOneWidget);
    // إغلاق الحوار ثم سحب لإظهار بطاقة الاستعادة (درس دفعة 19 أعلاه —
    // وبطاقة خيارات العرض F-167 الدفعة 23 أزاحتها أعمق فيكفي سحب أعمق
    // — وبطاقة سقف العهدة س105 أزاحتها أعمق بعد فيسحب أعمق)
    await tester.tap(find.text('حسناً'));
    await tester.pumpAndSettle();
    // س213 (D-218): بطاقة الاستعادة انتقلت إلى قسم البيانات والأمان
    // فالسحبة الثابتة القديمة بلا مرجع — تأكيد وصول بنمط D-098 حصراً.
    await tester.ensureVisible(find.byTooltip('اختيار ملف النسخة'));
    await tester.pumpAndSettle();
    // زر التصفح بجوار حقل المسار (suffixIcon) — لا قنوات منصة في وجوده
    expect(find.byTooltip('اختيار ملف النسخة'), findsOneWidget);
  });

  testWidgets('F-013: الاستعادة بتأكيد مزدوج — والإلغاء في أي تأكيد لم يحدث شيئاً',
      (tester) async {
    // IO متزامن — بيئة testWidgets الوهمية لا تكمل عمليات الملفات غير المتزامنة
    final tempDir = Directory.systemTemp.createTempSync('diqqah_restore_t_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'diqqah.db');
    final db = DiqqahDatabase.fileSyncClose(filePath: dbPath);
    addTearDown(db.close);
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            sku: 'SKU-LIVE',
            name: 'بضاعة الحية',
            kind: 'good',
            baseUnitId: 1,
            purchasePriceMinor: 0,
            salePriceMinor: 1,
            priceCurrencyId: 1,
            isActive: true,
            uuid: 'uuid-w-live',
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(db: db, dbPath: dbPath, onRestored: () {}),
    ));
    await tester.pumpAndSettle();

    // درس دفعة 19 ثم س213 (D-218): مواضع البطاقات بإعادة التنظيم
    // بلا مرجع للسحب الثابتة — سحب حتى البناء فتأكيد وصول بنمط D-098
    for (var i = 0;
        i < 30 &&
            find.widgetWithText(TextField, 'مسار ملف النسخة الاحتياطية')
                .evaluate()
                .isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.widgetWithText(TextField, 'مسار ملف النسخة الاحتياطية'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'مسار ملف النسخة الاحتياطية'),
      p.join(tempDir.path, 'غير-موجود.db'),
    );
    await tester.ensureVisible(find.text('استعادة…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استعادة…'));
    await tester.pumpAndSettle();

    // التأكيد الأول — إلغاء
    expect(find.text('استعادة نسخة احتياطية؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('استعادة نسخة احتياطية؟'), findsNothing);

    // الثانية — إلغاء آمن أيضاً: لا حوار استبدال ولا لقطة ولا خطأ
    await tester.tap(find.text('استعادة…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();
    expect(find.text('التأكيد الأخير'), findsOneWidget);
    await tester.tap(find.text('إلغاء آمن'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.items).get();
    expect(rows, hasLength(1));
    expect(rows.first.sku, 'SKU-LIVE');
    final files = tempDir.listSync().whereType<File>().toList();
    expect(
      files.where((f) => p.basename(f.path).startsWith('diqqah-before-restore-')),
      isEmpty,
      reason: 'الإلغاء الآمن لا يلتقط لقطة ولا يمس شيئاً',
    );
  });
}
