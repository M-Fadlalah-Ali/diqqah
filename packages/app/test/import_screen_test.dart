import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/import_screen.dart';
import 'package:diqqah_app/settings_screen.dart';

import 'test_guard.dart';

/// اختبارات شاشة استيراد البيانات — الدفعة الأولى من ثلاث
/// (D-208/§25.3، س140): بند الإعدادات بمسار «استيراد البيانات»،
/// المعاينة بعداداتها، والرفض الكلي بالأخطاء، والإشعار الدائم
/// للفاصل المنقوطة (د-5)، وإشعار نافذة التراجع قبل الاعتماد (§25.7)،
/// والاعتماد بالنسخة الحدثية المحقونة ثم المعاملة الواحدة.
///
/// نمط القاعدة `inMemorySyncClose` وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26)، والمنتقي ممرٌ محقون بنمط المزودات المحقونة
/// (الساعة والبطارية بالمركز) — ما يُختبر هو مسار ما بعد المنتقي
/// حرفاً.
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// تمرير حتى نصٍ أسفل قائمة الإعدادات الطويلة (الدرس الموثق س35/س36).
  Future<void> scrollToText(WidgetTester tester, String label) async {
    for (var i = 0; i < 40 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
    }
  }

  /// إظهار نصٍ غير مُبنى أسفل الطية بالقائمة الكسولة — غير المبني لا
  /// يوجد للباحث أصلاً (الدرس الموثق س35/س36): سحبٌ ثم ضخّات قبل النقر.
  Future<void> ensureInView(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
    }
    if (finder.evaluate().isNotEmpty) {
      // المبني بالتخزين المؤقت موجودٌ للباحث وقد يظل خارج الشاشة —
      // الإظهار الفعلي قبل النقر.
      await tester.ensureVisible(finder.first);
      await tester.pump();
    }
  }

  List<int> partiesCsv(List<String> rows) => utf8.encode([
        'dq-import:parties,1',
        'الكود,الاسم,النوع,العملة,حد الائتمان',
        ...rows,
      ].join('\n'));

  /// س142 — القالب الخامس «كميات المخزون الافتتاحية» (الوحدة 3).
  List<int> openingQtyCsv(List<String> rows) => utf8.encode([
        'dq-import:opening_qty,1',
        'كود الصنف,الاسم,الكمية,القيمة,الوحدة,العملة,سعر الصرف',
        ...rows,
      ].join('\n'));

  testWidgets('الشاشة تعرض بندَي القالبين وزرَي القالب والملف',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: ImportScreen(db: db)));
    await tester.pump();

    expect(find.text('استيراد البيانات'), findsOneWidget);
    expect(find.text('الأطراف'), findsOneWidget);
    expect(find.text('الأصناف'), findsOneWidget);
    expect(find.text('كميات المخزون'), findsOneWidget,
        reason: 'القالب الخامس — الوحدة 3 (س142)');
    expect(find.text('تنزيل قالب فارغ'), findsOneWidget);
    expect(find.text('اختيار ملف CSV'), findsOneWidget);
  });

  testWidgets('ملف سليم يعرض العدادات والمعاينة ويعتمد بنسخة حدثية '
      'محقونة ثم يكتب الأطراف وحدث الاستيراد', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        createEventBackup: () async => 'event-test-001.diqqah',
        pickOverride: () async => (
          name: 'parties.csv',
          bytes: partiesCsv([
            'C001,علي أحمد,عميل,,',
            'C002,مؤمن,عميل,USD,10000.5',
            'S003,مورد الخضار,مورد,,',
          ]),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('اختيار ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // س142: بطاقتا «ما لا يُستورد» والاصطلاح أطلّتا القائمة فأسطر
    // المعاينة تحت الطية — الإظهار قبل التحقق (الدرس الموثق س35/س36).
    await ensureInView(tester, find.textContaining('C001 — علي أحمد'));
    // العدادات الثلاث بالمعاينة (§25.3.1) — والقيم المحولة تُعرض.
    expect(find.text('جديد: 3'), findsOneWidget);
    expect(find.text('موجود: 0'), findsOneWidget);
    expect(find.text('أخطاء: 0'), findsOneWidget);
    expect(find.textContaining('C001 — علي أحمد'), findsOneWidget);
    expect(find.textContaining('S003 — مورد الخضار'), findsOneWidget);
    // لا إشعار منقوطة بملف فاصلة.
    expect(find.textContaining('اكتُشف فاصل منقوطة'), findsNothing);

    // الاعتماد: النسخة الحدثية ثم المعاملة الواحدة — والزر أسفل
    // الطية فإظهاره قبل النقر (الدرس الموثق س35/س36).
    await ensureInView(tester, find.textContaining('اعتماد الاستيراد'));
    await tester.tap(find.textContaining('اعتماد الاستيراد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('أُتمّ الاستيراد'), findsOneWidget);
    expect(find.textContaining('جديد: 3'), findsWidgets);

    await tester.tap(find.text('حسناً'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final parties = await db.customSelect(
        'SELECT number FROM parties ORDER BY number').get();
    expect(parties.map((r) => r.data['number']),
        ['C001', 'C002', 'S003']);
    final events = await db.customSelect(
        "SELECT payload FROM events WHERE action = "
        "'import_performed'").get();
    expect(events, hasLength(1));
    final payload = jsonDecode(
            await db.openLogText(events.single.data['payload'] as String))
        as Map<String, Object?>;
    expect(payload['event_backup'], 'event-test-001.diqqah');
    // والشاشة عادت لوضع البداية — ما بعد النجاح بلا بقايا معاينة.
    expect(find.textContaining('C001 — علي أحمد'), findsNothing);
  });

  testWidgets('ملف بأخطاء يرفض كلياً ويعرض التقرير بلا زر اعتماد',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        pickOverride: () async => (
          name: 'bad.csv',
          bytes: partiesCsv([
            ',بلا كود,عميل,,',
            'C001,سليم,عميل,,',
          ]),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('اختيار ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // س142: تقرير الأخطاء أسفل الطية بعد بطاقتي التشطيب — الإظهار أولاً.
    await ensureInView(tester, find.textContaining('تنزيل تقرير الأخطاء'));
    expect(find.textContaining('الرفض كلي'), findsOneWidget);
    expect(find.text('أخطاء: 1'), findsOneWidget);
    expect(find.textContaining('تنزيل تقرير الأخطاء'), findsOneWidget);
    expect(find.textContaining('اعتماد الاستيراد'), findsNothing,
        reason: 'كل-أو-لا شيء: لا اعتماد بأي خطأ');

    // ولم يُكتب شيء.
    final parties = await db.customSelect('SELECT id FROM parties').get();
    expect(parties, isEmpty);
  });

  testWidgets('فاصل منقوطة يعرض إشعاره الدائم بالمعاينة ويُقرأ به (د-5)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    final text = '\uFEFF'
        'dq-import:parties,1\n'
        'الكود؛الاسم؛النوع؛العملة؛حد الائتمان\n'
        'C001؛علي؛عميل؛؛\n';
    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        pickOverride: () async =>
            (name: 'semicolon.csv', bytes: utf8.encode(text)),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('اختيار ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('اكتُشف فاصل منقوطة، قُرئ به'),
        findsOneWidget);
    expect(find.text('جديد: 1'), findsOneWidget);
  });

  testWidgets('نافذة التراجع المفتوحة تُشعر قبل الاعتماد والاستيراد '
      'يكمل (§25.7)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.armRollbackWindow(snapshotFileName: 'pre-restore.diqqah');

    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        createEventBackup: () async => 'event-test-002.diqqah',
        pickOverride: () async => (
          name: 'parties.csv',
          bytes: partiesCsv(['C010,نور,عميل,,']),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('اختيار ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await ensureInView(tester, find.textContaining('اعتماد الاستيراد'));
    await tester.tap(find.textContaining('اعتماد الاستيراد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // إشعار النافذة الصريح قبل أي كتابة.
    expect(find.text('نافذة التراجع مفتوحة'), findsOneWidget);
    await tester.tap(find.text('متابعة الاستيراد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('أُتمّ الاستيراد'), findsOneWidget);
    final parties = await db.customSelect(
        "SELECT number FROM parties WHERE number = 'C010'").get();
    expect(parties, hasLength(1));
    // والنافذة أُغلقت بأول كتابة استيراد.
    final after = await db.rollbackWindow();
    expect(after?.closed, isTrue);
  });

  testWidgets('الاعتماد بلا نسخة حدثية ناجحة مسدود برسالته بلغة '
      'المستخدم — والرمز DQ-1107 للسجل لا النص (س204 — م03)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        createEventBackup: () async => null,
        pickOverride: () async => (
          name: 'parties.csv',
          bytes: partiesCsv(['C010,نور,عميل,,']),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('اختيار ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await ensureInView(tester, find.textContaining('اعتماد الاستيراد'));
    await tester.tap(find.textContaining('اعتماد الاستيراد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('لا اعتماد بلا نسخة حدثية'), findsOneWidget,
        reason: 'الرسالة بلغة المستخدم (س204 — م03) والرمز للسجل');
    expect(find.textContaining('DQ-1107'), findsNothing,
        reason: 'لا رموز داخل نص المستخدم (س204 — م03)');
    final parties = await db.customSelect('SELECT id FROM parties').get();
    expect(parties, isEmpty, reason: 'لا اعتماد بلا نسخة (§25.6)');
  });

  testWidgets('الوحدة 3 «كميات المخزون»: معاينة واعتماد بإذن إدخال '
      'مقابله 43 (F-209) وحدث الاستيراد — لا 332 الافتتاحي (س142)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        db: db,
        createEventBackup: () async => 'event-test-003.diqqah',
        pickOverride: () async => (
          name: 'opening_qty.csv',
          bytes: openingQtyCsv([
            'SKU1,صنف أول,10,5000,قطعة,SYP,',
          ]),
        ),
      ),
    ));
    await tester.pump();

    // اختيار القالب الخامس — وحقل تاريخ الافتتاحي يظهر للقالب الافتتاحي.
    await tester.tap(find.text('كميات المخزون'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('تاريخ القيد الافتتاحي (YYYY-MM-DD)'), findsOneWidget);

    // بطاقة الاصطلاح (§25.4) تظهر للقالب الافتتاحي فتدفع زر الملف تحت
    // الطية بالقائمة الكسولة — التمرير المحقون قبل الضغط (الدرس س35/س36).
    await ensureInView(tester, find.text('اختيار ملف CSV'));
    await tester.tap(find.text('اختيار ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // عدادات المعاينة تحت الطية بعد بطاقتي البعيد — التمرير المحقون قبل
    // الإثبات (القائمة الكسولة لا تبني ما تحت الطية — درس س35/س36).
    await ensureInView(tester, find.text('جديد: 1'));
    expect(find.text('جديد: 1'), findsOneWidget);
    await ensureInView(tester, find.text('وحدات تُنشأ: 1'));
    expect(find.text('وحدات تُنشأ: 1'), findsOneWidget);
    // بطاقة التوازن أسفل الطية بالقائمة الكسولة — الإظهار قبل الإثبات
    // (الدرس الموثق س35/س36).
    await ensureInView(tester, find.textContaining('توازن الافتتاحي'));
    expect(find.textContaining('توازن الافتتاحي'), findsOneWidget);
    expect(find.textContaining('مقابل الإذن: 43'), findsOneWidget,
        reason: 'F-209: المقابل 43 الافتراضي لا 332');
    expect(find.textContaining('مقابل 332'), findsNothing);

    await ensureInView(
        tester, find.textContaining('اعتماد الأرصدة الافتتاحية'));
    await tester.tap(find.textContaining('اعتماد الأرصدة الافتتاحية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('أُتمّ استيراد الأرصدة الافتتاحية'), findsOneWidget);
    expect(find.textContaining('إذن إدخال رقم'), findsOneWidget);
    await tester.tap(find.text('ميزان المراجعة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('الميزان متوازن'), findsOneWidget);
    await tester.tap(find.text('حسناً'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // القاعدة: صنف ووحدة وإذن بقيمه الصريحة ومقابله 43 وحدث الاستيراد.
    final items = await db.customSelect(
        "SELECT sku FROM items WHERE sku = 'SKU1'").get();
    expect(items, hasLength(1));
    final receipts = await db.customSelect(
        'SELECT id FROM stock_receipts').get();
    expect(receipts, hasLength(1));
    final counter = await db.customSelect(
      "SELECT a.code AS code, l.credit_minor "
      "FROM move_lines l JOIN moves m ON m.id = l.move_id "
      "JOIN accounts a ON a.id = l.account_id "
      "WHERE m.ref_doc_type = 'stock_receipt' AND l.credit_minor > 0",
    ).get();
    expect(counter.single.data['code'] as String, '43');
    final events = await db.customSelect(
        "SELECT payload FROM events WHERE action = "
        "'import_performed'").get();
    expect(events, hasLength(1));
    final payload = jsonDecode(
            await db.openLogText(events.single.data['payload'] as String))
        as Map<String, Object?>;
    expect(payload['unit'], 'opening_qty');
    expect(payload['event_backup'], 'event-test-003.diqqah');
  });

  testWidgets('بند الإعدادات «استيراد البيانات» للمدير يفتح الشاشة',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final userId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(userId);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah_import_test/dummy.db',
        onRestored: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await scrollToText(tester, 'استيراد البيانات');
    expect(find.text('استيراد البيانات'), findsOneWidget);
    await ensureInView(tester, find.text('فتح شاشة الاستيراد'));
    await tester.tap(find.text('فتح شاشة الاستيراد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('اختيار ملف CSV'), findsOneWidget);
  });
}
