import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/invoices_screen.dart';
import 'package:diqqah_app/settings_screen.dart';
import 'package:diqqah_app/vouchers_screen.dart';

import 'seed_cycle.dart';
import 'test_guard.dart';

/// اختبارات بوابة «المندوب يعلق» (س101 — كلمة المالك: «زاوية البائع
/// يبيع فوراً والمندوب يعلق، وأعطاء كل واحد صلاحيات مختلفة»):
/// فواتير المندوب بعد س164: زرا «حفظ وترحيل» و«حفظ كمسودة» بيده
/// كيد البائع (التعليق ملغى بنقاط المالك) وحدث هوية المنشئ على كل
/// مسودة وبوابة «ترحيل مسودات الآخرين» للمعتمِد، وس102:
/// أن يكون بيع المندوب يحجز الكمية أم فقط مسودة»: بطاقة الخيار
/// بالإعدادات وإظهار المحجوز بلسان المتاح في نموذج البيع (F-016).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle —
/// درس س22..س26 الموثق — وأرقام الدورة من البذرة المعروفة.
void main() {
  // المهلة الحارسة 120ث قبل أي تسجيل اختبار — dart_test.yaml لا يسري
  // على testWidgets (درس الجولات 124..128 الموثق في test_guard.dart).
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// درس السرد الكسول (س35/س36): ListView يبني الظاهر حصراً — تمرير
  /// قبل لمس الزر أسفل النموذج.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    for (var i = 0; i < 10 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
    }
  }

  /// س104: التمرير بنموذج السند — بأول ListView حصراً فالنموذج نفسه
  /// هو الأول بشجرة البناء مهما أقحمت المنسدلات القوائم الداخلية.
  Future<void> scrollVoucherTo(WidgetTester tester, String label) async {
    for (var i = 0; i < 10 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -260));
      await tester.pump();
    }
  }

  /// مستخدم بدور من الأدوار المزروعة — createManager ثم تحويل الدور
  /// (واجهات التخزين العلنية لا اختراق مباشر)، والجلسة عليه.
  Future<int> sessionAsRole(
    DiqqahDatabase db, {
    required String name,
    required String login,
    required String roleName,
  }) async {
    final userId =
        await db.createManager(name: name, login: login, passwordHash: 's:h');
    // عرف بذرة الواجهة: بحث بلا متغيرات فتبقى حزمة الواجهة بلا اعتماد
    // drift مباشر — والأدوار المزروعة أسماؤها ثابتة معلومة.
    final roleId = (await db
            .customSelect(
              "SELECT id FROM roles WHERE name = '$roleName'",
            )
            .getSingle())
        .data['id'] as int;
    await db.updateUserRole(userId, roleId);
    await db.setCurrentUserId(userId);
    return userId;
  }

  /// أرضية مخزون ومسودة بيع معلقة بهوية مندوب — لاختبارات الاعتماد.
  /// الوحدة والصنف والطرفان كلها من بذرة الدورة (هي نفسها تزرع «قطعة»
  /// و«Z-100» و0001 و0002 — الاحتكاك عرفها) فلا صفوف مكررة.
  Future<int> seedPendingSale(DiqqahDatabase db,
      {required int repUserId, required String repName}) async {
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-03-15';
    final unitId = (await db
            .customSelect(
              "SELECT id FROM units WHERE name = 'قطعة'",
            )
            .getSingle())
        .data['id'] as int;
    final oilId = (await db
            .customSelect(
              "SELECT id FROM items WHERE sku = 'Z-100'",
            )
            .getSingle())
        .data['id'] as int;
    final customerId = (await db
            .customSelect(
              "SELECT id FROM parties WHERE number = '0001'",
            )
            .getSingle())
        .data['id'] as int;
    final supplierId = (await db
            .customSelect(
              "SELECT id FROM parties WHERE number = '0002'",
            )
            .getSingle())
        .data['id'] as int;
    final warehouseId = (await db
            .customSelect(
              'SELECT id FROM warehouses ORDER BY id LIMIT 1',
            )
            .getSingle())
        .data['id'] as int;
    final purchaseId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.purchase,
      dateText: date,
      partyId: supplierId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 10, unitPriceMinor: 10000),
      ],
    ));
    await db.postInvoice(purchaseId);
    final draftId = await db.createInvoiceDraft(InvoiceDraft(
      kind: InvoiceKind.sale,
      dateText: date,
      partyId: customerId,
      warehouseId: warehouseId,
      lines: [
        InvoiceLineDraft(
            itemId: oilId, unitId: unitId, qtyBase: 2, unitPriceMinor: 15000),
      ],
    ));
    await db.recordInvoiceSubmission(draftId,
        userId: repUserId, userName: repName, roleName: kSalesRepRoleName);
    return draftId;
  }

  testWidgets(
      'س164: مندوب يفتح نموذج فاتورة — زرا «حفظ وترحيل» و«حفظ كمسودة» '
      'بيده كيد البائع (التعليق ملغى) وإفصاح المسودة ظاهر، والحفظ مسودة '
      'بلا رقم وبحدث هوية المنشئ باسمه', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await sessionAsRole(db,
        name: 'سالم المندوب', login: 'salem', roleName: 'مندوب');

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بيع نقدي مكتمل بنمط س-88 — الصندوق والمستودع مختاران افتراضياً،
    // وحقول الأعلى مبنية أولاً فيُدخل فيها قبل التمرير (درس السرد الكسول)
    await tester.enterText(
        find.widgetWithText(TextField, 'التاريخ (YYYY-MM-DD)'), '2026-03-15');
    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('Z-100 زيت محلي').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.widgetWithText(TextField, 'الكمية'), '2');
    await tester.enterText(
        find.widgetWithText(TextField, 'سعر الوحدة بوحدة صغرى'), '15000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // درس السرد الكسول: الزران أسفل النموذج الطويل — تمرير قبل الفحص
    await scrollTo(tester, 'حفظ وترحيل');
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();

    // زرا الحفظ بيده وإفصاح المسودة ظاهر — ولا لسان دورٍ ولا تعليق
    expect(find.text('حفظ وترحيل'), findsOneWidget);
    expect(find.text('حفظ كمسودة'), findsOneWidget);
    expect(find.textContaining('بدور «مندوب»'), findsNothing);
    expect(find.textContaining('المسودة المحفوظة لا تمس المخزون'),
        findsOneWidget,
        reason: 'إفصاح المسودة لكل الأيدي (F-016)');

    await tester.tap(find.text('حفظ كمسودة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المسودة حُفظت: بلا رقم وبلا مساس بالمخزون والدفتر
    final drafts = await db
        .customSelect(
          "SELECT id, state, number FROM invoices "
          "WHERE kind = 'sale' AND state = 'draft'",
        )
        .get();
    expect(drafts, hasLength(1),
        reason: 'مسودة المندوب باقية مسودةً — الترحيل بيده أو بيد البوابة');
    final draftId = drafts.single.data['id'] as int;
    expect(drafts.single.data['number'], isEmpty,
        reason: 'الترقيم لحظة الترحيل حصراً (07 §1.9)');

    // وحدث هوية المنشئ باسمه ودوره (فصل الأيدي)
    final submission = await db.invoiceSubmissionOf(draftId);
    expect(submission, isNotNull);
    expect(submission!.userName, 'سالم المندوب');
    expect(submission.roleName, 'مندوب');
  });

  testWidgets(
      'س164: مدير يفتح الأرشيف — زر الترحيل على المسودة يرحّل '
      'بالمحرك ذاته فتنال رقمها وتغادر المسودات', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    final draftId =
        await seedPendingSale(db, repUserId: repId, repName: 'سالم المندوب');
    // جلسة المدير (النجمة تشمل بوابة ترحيل مسودات الآخرين)
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // زر الترحيل على المسودة — والنقر يفتح نافذة القرار
    expect(find.byTooltip('ترحيل'), findsOneWidget);
    await tester.tap(find.byTooltip('ترحيل'));
    await tester.pumpAndSettle();
    expect(find.text('ترحيل المسودة؟'), findsOneWidget);

    await tester.tap(find.text('ترحيل الآن').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المحرك ذاته: مرحّلة برقمها ولا مسودة بيع بعد
    final posted = await db.invoiceById(draftId);
    expect(posted, isNotNull);
    expect(posted!.state, isNot('draft'));
    expect(posted.number, isNotEmpty);
    final restDrafts = await db
        .customSelect(
          "SELECT id FROM invoices WHERE state = 'draft'",
        )
        .get();
    expect(restDrafts, isEmpty);
  });

  testWidgets(
      'س101: بائع كما هو — زرا «حفظ وترحيل» و«حفظ كمسودة» معاً '
      'وبلا لسان معلقة (البائع يبيع فوراً بكلمة المالك)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await sessionAsRole(db,
        name: 'فهد البائع', login: 'fahad', roleName: 'بائع');

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // درس السرد الكسول: الزران أسفل النموذج الطويل — تمرير قبل الفحص
    await scrollTo(tester, 'حفظ وترحيل');
    await tester.ensureVisible(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();

    expect(find.text('حفظ وترحيل'), findsOneWidget);
    expect(find.text('حفظ كمسودة'), findsOneWidget);
    expect(find.text('حفظ وإرسال للاعتماد'), findsNothing);
    expect(find.textContaining('بدور «مندوب»'), findsNothing);
  });

  testWidgets(
      'س164: مندوب في الأرشيف — لا زر ترحيل على المسودات (بلا بوابة ترحيل مسودات الآخرين ومسودته تُرحَّل من التفاصيل بيده)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    await seedPendingSale(db, repUserId: repId, repName: 'سالم المندوب');
    await db.setCurrentUserId(repId);
    // حوّل المستخدم إلى دور المندوب
    final roleId = (await db
            .customSelect(
              "SELECT id FROM roles WHERE name = 'مندوب'",
            )
            .getSingle())
        .data['id'] as int;
    await db.updateUserRole(repId, roleId);

    await tester.pumpWidget(MaterialApp(home: InvoicesScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المسودة ظاهرة بلسانها ولا زر ترحيل لمن لا بوابة له
    expect(find.textContaining('مسودة'), findsWidgets);
    expect(find.byTooltip('ترحيل'), findsNothing);
  });

  // ═══ س102: خيار المالك «بيع المندوب يحجز الكمية أم مسودة فقط» ═══

  testWidgets(
      'س164: بطاقة «مسودات البيع» بالإعدادات — مفتاح الحجز مطفأ '
      'افتراضاً والتفعيل يكتب القاعدة فيسري على كل مستخدميها', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    expect(await db.heldInvoicesReserveQty(), isFalse,
        reason: 'الافتراض المطفأ: مسودة فقط (سلوك القائم)');

    await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
            db: db,
            dbPath: '/tmp/diqqah-held-reserve-test.db',
            onRestored: () {})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // درس السرد الكسول: البطاقة أسفل قائمة طويلة — تمرير قبل الفحص
    await scrollTo(tester, 'مسودات البيع تحجز الكمية');
    await tester.ensureVisible(find.text('مسودات البيع تحجز الكمية'));
    await tester.pumpAndSettle();
    expect(find.text('مسودات البيع تحجز الكمية'), findsOneWidget);

    await tester.tap(find.text('مسودات البيع تحجز الكمية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await db.heldInvoicesReserveQty(), isTrue,
        reason: 'إعداد منشأة في القاعدة لا جهاز');
  });

  testWidgets(
      'س102: بإعداد الحجز يظهر «محجوز» بلسان المتاح في نموذج '
      'البيع — حجز المسودة حاضر بالعرض لا مخفي (F-016)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    // أرضية س164: شراء 10 مرحّل + مسودة بيع 2 — المتاح المعروض 8
    await seedPendingSale(db, repUserId: repId, repName: 'سالم المندوب');
    await db.setHeldInvoicesReserveQty(true);
    await sessionAsRole(db,
        name: 'فهد البائع', login: 'fahad', roleName: 'بائع');

    await tester.pumpWidget(MaterialApp(
        home: InvoiceEditScreen(db: db, initialKind: InvoiceKind.sale)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('الصنف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // بذرة الدورة تزرع رصيداً سابقاً فصار المتاح بعد الحجز 14: معلقة
    // المندوب 2 تحجز وترسم بلسان واحد «المتاح: 14 (محجوز 2)» (F-016)
    expect(find.textContaining('(محجوز 2)'), findsWidgets,
        reason: 'المحجوز حاضر بالعرض لا مخفي');
    expect(find.textContaining('المتاح: 14 (محجوز 2)'), findsOneWidget,
        reason: 'المتاح بعد الحجز والمحجوز معروضان معاً بلسان واحد');
  });

  // ═══════════════════════════════════════════════════════════════
  // س104 — دفعة المندوب الثالثة (كلمة المالك: «ابدأ بدفعة المندوب 3»):
  // القبض المعلق بحساب الطريق — نموذج المندوب وأدوات المعتمد والعهدة.
  // ═══════════════════════════════════════════════════════════════

  /// أرضية تحصيل معلق بمحرك حقيقي — بهوية مندوب معروف، وترجع معرف السند.
  /// س162: اسم الصندوق اختياري — الغائب «صندوق الاعتماد» مطابق القائم
  /// حرفاً، والتحصيلان بجلسة واحدة يحتاجان اسمن لا تتصادم (حرس التفرد).
  Future<int> seedHeldReceipt(DiqqahDatabase db,
      {required int repUserId,
      required String repName,
      String boxName = 'صندوق الاعتماد'}) async {
    final yearRows =
        await db.customSelect('SELECT name FROM fiscal_years').get();
    final date = '${yearRows.single.data['name'] as String}-04-10';
    final customerId = (await db
            .customSelect(
              "SELECT id FROM parties WHERE number = '0001'",
            )
            .getSingle())
        .data['id'] as int;
    final boxId = await db.createCashBox(name: boxName, currencyId: 1);
    return db.createHeldVoucher(
      VoucherDraft(
        kind: VoucherKind.receipt,
        dateText: date,
        partyId: customerId,
        cashBoxId: boxId,
        currencyId: 1,
        fxRate: baseCurrencyFxRate,
        amountDocMinor: 60000,
      ),
      userId: repUserId,
      userName: repName,
      roleName: kSalesRepRoleName,
    );
  }

  testWidgets(
      'س104: مندوب يفتح نموذج السند — لا منسدلَي النوع والجهة '
      'أصلاً (قبض طرفي حصراً) ولسان دوره ظاهر وزر وحيد «حفظ وإرسال '
      'للاعتماد» يعلّق التحصيل بحساب الطريق بلا رقم وبلا حركة صندوق',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await sessionAsRole(db,
        name: 'سالم المندوب', login: 'salem', roleName: 'مندوب');

    // عميل جديد بلا فواتير مفتوحة — مسار «رصيد مقدَّم» نظيف بلا مطابقات
    // (ويُدخل قبل فتح النموذج فقائمة الأطراف تحمّله من أول قراءة).
    await db.insertParty(
        number: '9001',
        name: 'عميل الطريق',
        kind: 'customer',
        defaultCurrencyId: 1);

    await tester.pumpWidget(MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بوابة لا تُعرض: منسدلا النوع والجهة غائبان — القبض الطرفي فرض مسبق
    expect(find.text('نوع السند'), findsNothing);
    expect(find.text('الجهة (طرفية أو بغير طرف)'), findsNothing);
    expect(find.text('حفظ وترحيل'), findsNothing);
    expect(find.textContaining('بدور «مندوب»'), findsOneWidget);
    expect(find.text('حفظ وإرسال للاعتماد'), findsOneWidget);

    // العميل والمبلغ — والفائض بلا فواتير مفتوحة «رصيد مقدَّم»
    await tester.tap(find.text('العميل (القبض على ذمم العملاء)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('9001 عميل الطريق').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
        find.widgetWithText(TextField, 'المبلغ بوحدة صغرى'), '60000');
    await tester.pump();

    await scrollVoucherTo(tester, 'حفظ وإرسال للاعتماد');
    await tester.ensureVisible(find.text('حفظ وإرسال للاعتماد').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وإرسال للاعتماد').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // التحصيل معلّق: بلا رقم وبلا حركة صندوق وحدث تقديم باسمه
    final held = await db
        .customSelect(
          "SELECT id, number, state FROM vouchers "
          "WHERE kind = 'receipt' AND state = 'held'",
        )
        .get();
    expect(held, hasLength(1),
        reason: 'قبض المندوب معلّق في الطريق — لا ترحيل بيده');
    expect(held.single.data['number'], isEmpty,
        reason: 'الترقيم لحظة الاعتماد حصراً');
    final movements = await db
        .customSelect(
          "SELECT COUNT(*) c FROM cash_movements WHERE ref_doc_type = 'voucher' "
          "AND ref_doc_id = ${held.single.data['id']}",
        )
        .getSingle();
    expect(movements.data['c'], 0, reason: 'الصندوق لم يُمس بعد');
    final sub = await db.voucherSubmissionOf(held.single.data['id'] as int);
    expect(sub, isNotNull);
    expect(sub!.userName, 'سالم المندوب');
    expect(sub.roleName, 'مندوب');
  });

  testWidgets(
      'س104: مدير يفتح شاشة السندات — بطاقة العهدة باسم المانح '
      'وزرا الاعتماد والرفض على المعلق حصراً، والاعتماد يمنح الرقم '
      'ويدخل الصندوق ويخلو العهدة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    final heldId =
        await seedHeldReceipt(db, repUserId: repId, repName: 'سالم المندوب');
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بطاقة العهدة للمعتمد — باسم المانح ومبلغه، والصف بلسان المعلق
    expect(find.text('تحصيلات في الطريق — عهدة المندوبين'), findsOneWidget);
    expect(find.textContaining('سالم المندوب — 1 تحصيلات'), findsOneWidget);
    expect(find.textContaining('معلّق في الطريق'), findsOneWidget);
    // زرا الاعتماد والرفض على المعلق — والاعتماد بنافذة قرار واعية
    expect(find.byTooltip('اعتماد وتسليم للصندوق'), findsOneWidget);
    expect(find.byTooltip('رفض وعكس القيد'), findsOneWidget);
    await tester.tap(find.byTooltip('اعتماد وتسليم للصندوق'));
    await tester.pumpAndSettle();
    expect(find.text('اعتماد التحصيل وتسليمه للصندوق؟'), findsOneWidget);
    await tester.tap(find.text('اعتماد وتسليم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المحرك ذاته: مرحّل برقمه وحركة نقد داخل والعهدة خلت
    final v = await db.voucherById(heldId);
    expect(v!.state, 'posted');
    expect(v.number, isNotEmpty);
    final movement = await db
        .customSelect(
          "SELECT kind FROM cash_movements WHERE ref_doc_type = 'voucher' "
          'AND ref_doc_id = $heldId',
        )
        .getSingle();
    expect(movement.data['kind'], 'in');
    expect(await db.heldReceiptCustody(), isEmpty);
  });

  testWidgets(
      'س104: الرفض بنافذة السبب يعكس قيد الطريق ويعيد الفاتورة '
      'والعهدة تخرج — وحالة السند rejected لا محذوفة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    final heldId =
        await seedHeldReceipt(db, repUserId: repId, repName: 'سالم المندوب');
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('رفض وعكس القيد'));
    await tester.pumpAndSettle();
    expect(find.text('رفض التحصيل المعلق؟'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'السبب (اختياري)'), 'لم يصل النقد');
    await tester.tap(find.text('رفض وعكس القيد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // المحرك ذاته: مرفوض وعُكس قيد الطريق ولا حركة نقد والعهدة خلت
    final v = await db.voucherById(heldId);
    expect(v!.state, 'rejected');
    final movements = await db
        .customSelect(
          "SELECT COUNT(*) c FROM cash_movements WHERE ref_doc_type = 'voucher' "
          'AND ref_doc_id = $heldId',
        )
        .getSingle();
    expect(movements.data['c'], 0, reason: 'الرفض لا يدخل الصندوق أصلاً');
    expect(await db.heldReceiptCustody(), isEmpty);
  });

  testWidgets(
      'س104: بائع يفتح نموذج السند كما هو — منسدلا النوع والجهة '
      'وزر «حفظ وترحيل» وبلا لسان تعليق (قبضه مباشر بعرف الرئيسية)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await sessionAsRole(db,
        name: 'فهد البائع', login: 'fahad', roleName: 'بائع');

    await tester.pumpWidget(MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // عقد البائع القائم سليم: خياراته كلها ظاهرة وبلا لسان معلقة
    expect(find.text('نوع السند'), findsOneWidget);
    expect(find.text('الجهة (طرفية أو بغير طرف)'), findsOneWidget);
    expect(find.text('حفظ وترحيل'), findsOneWidget);
    expect(find.text('حفظ وإرسال للاعتماد'), findsNothing);
    expect(find.textContaining('بدور «مندوب»'), findsNothing);
  });

  // ═══════════════════════════════════════════════════════════════
  // س105 — دفعة المندوب الرابعة: سقف العهدة وأعمارها — بطاقة الإعداد
  // وبطاقة العهدة بالأعمار والمتباح ولسان النموذج قبل فصل المحرك.
  // ═══════════════════════════════════════════════════════════════

  testWidgets(
      'س105: بطاقة «تحصيلات المندوب» بالإعدادات — الفراغ بلا سقف '
      'والحفظ يكتب القاعدة بوحداته الصغرى فيسري على كل مستخدميها',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    expect(await db.heldReceiptCustodyCap(), 0,
        reason: 'الغائب بلا سقف — سلوك س104 القائم افتراضاً');

    await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
            db: db,
            dbPath: '/tmp/diqqah-custody-cap-test.db',
            onRestored: () {})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // درس السرد الكسول: البطاقة أسفل قائمة طويلة — تمرير قبل الفحص
    await scrollTo(tester, 'حفظ سقف العهدة');
    await tester.ensureVisible(find.text('حفظ سقف العهدة'));
    await tester.pumpAndSettle();
    expect(find.text('تحصيلات المندوب'), findsOneWidget);

    // لوازم الإدخال الرقمي تمسح الشاذّ («ألف» تُمسح فارغةً فيصل الفراغ)
    // والحفظ على الفراغ «بلا سقف» بلا كتابة — وحرس parseGrouped ثانٍ
    // بالشيفرة لمن يملك المحرك دون اللوازم (دفاعان لا واحد)
    await tester.enterText(
        find.widgetWithText(TextField, 'سقف العهدة بوحدة صغرى (فارغ: بلا سقف)'),
        'ألف');
    await tester.tap(find.text('حفظ سقف العهدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('حُفظ — بلا سقف عهدة'), findsOneWidget);
    expect(await db.heldReceiptCustodyCap(), 0,
        reason: 'الفراغ بلا سقف — لا حدّ يُخترع');

    // القيمة السليمة مفصولة الفواصل — تُكتب بوحداتها الصغرى (ونص
    // النتيجة الأول أزاح الزر — درس السرد الكسول: إظهار قبل اللمسة)
    await tester.enterText(
        find.widgetWithText(TextField, 'سقف العهدة بوحدة صغرى (فارغ: بلا سقف)'),
        '80,000');
    await tester.ensureVisible(find.text('حفظ سقف العهدة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ سقف العهدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await db.heldReceiptCustodyCap(), 80000,
        reason: 'إعداد منشأة في القاعدة لا جهاز');
    expect(find.textContaining('حُفظ السقف: 80,000'), findsOneWidget);
  });

  testWidgets(
      'س105: بطاقة العهدة بأعمارها وسقفها — «أقدمها منذ» من طوابع '
      'التقديم و«المتباح تحت السقف» من الإعداد المعتمد', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    await seedHeldReceipt(db, repUserId: repId, repName: 'سالم المندوب');
    await db.setHeldReceiptCustodyCap(100000);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // العهدة بلسانها الجديد: العدد والمجموع والأقدم والمتباح
    expect(find.textContaining('سالم المندوب — 1 تحصيلات بمجموع 60,000'),
        findsOneWidget);
    expect(find.textContaining('أقدمها منذ أقل من يوم'), findsOneWidget);
    expect(find.textContaining('المتباح تحت السقف 40,000'), findsOneWidget,
        reason: 'السقف 100,000 والعهدة 60,000');
  });

  testWidgets(
      'س105: نموذج المندوب بلسان المتباح قبل الفصل — والحفظ فوق '
      'السقف يُرفض بالمحرك برسالته الصادقة لا سكوت واجهة', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    // عهدة قائمة 60,000 وسقف 80,000 — فالمتباح 20,000
    await seedHeldReceipt(db, repUserId: repId, repName: 'سالم المندوب');
    await db.setHeldReceiptCustodyCap(80000);
    await db.updateUserRole(
        repId,
        (await db.customSelect("SELECT id FROM roles WHERE name = 'مندوب'")
                .getSingle())
            .data['id'] as int);
    await db.setCurrentUserId(repId);

    // عميل جديد بلا فواتير — مسار «رصيد مقدَّم» نظيف بعرف س104
    await db.insertParty(
        number: '9002',
        name: 'عميل السقف',
        kind: 'customer',
        defaultCurrencyId: 1);

    await tester.pumpWidget(MaterialApp(home: VoucherEditScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // لسان المتباح ظاهر قبل الفصل (F-016)
    expect(find.textContaining('سقف العهدة 80,000 — المتباح لتحصيل جديد 20,000'),
        findsOneWidget);

    await tester.tap(find.text('العميل (القبض على ذمم العملاء)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('9002 عميل السقف').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
        find.widgetWithText(TextField, 'المبلغ بوحدة صغرى'), '30000');
    await tester.pump();

    await scrollVoucherTo(tester, 'حفظ وإرسال للاعتماد');
    await tester.ensureVisible(find.text('حفظ وإرسال للاعتماد').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ وإرسال للاعتماد').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // رسالة المحرك الصادقة بالأرقام الثلاثة — ولا معلَّق جديد كتب
    expect(find.textContaining('تجاوز سقف العهدة'), findsOneWidget);
    final held = await db.customSelect(
      "SELECT COUNT(*) c FROM vouchers WHERE kind = 'receipt' "
      "AND state = 'held'",
    ).getSingle();
    expect(held.data['c'], 1,
        reason: 'عهدته القائمة وحدها — الجديد فوق السقف رُفض قبل أي كتابة');
  });

  // ═══ س162 — بقية فكرة المندوب: شرائح الأعمار والقصر «تحصيلاتي» ═══
  // بنص س105 الموثق «توزيع الأعمار بشرائح (0-7/8-15/…)» وس104 «عرض فوق
  // القراءة مؤجل بترتيب المالك» — والغائب مطابق القائم حرفاً.

  testWidgets(
      'س162: قراءتا المحرك — voucherIdsSubmittedBy بهوية آخر تقديم '
      'وheldReceiptCustodyEntries بطابع كل تحصيل', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repA = await db.createManager(
        name: 'عامر', login: 'amer', passwordHash: 's:h');
    final repB = await db.createManager(
        name: 'بسام', login: 'basam', passwordHash: 's:h');
    final heldA = await seedHeldReceipt(db,
        repUserId: repA, repName: 'عامر', boxName: 'صندوق الاعتماد أ');
    final heldB = await seedHeldReceipt(db,
        repUserId: repB, repName: 'بسام', boxName: 'صندوق الاعتماد ب');

    // القصر: كل مانح يرى تحصيله هو حصراً — وآخر تقديم فوزاً (عرف س101)
    final idsA = await db.voucherIdsSubmittedBy(repA);
    final idsB = await db.voucherIdsSubmittedBy(repB);
    expect(idsA, {heldA});
    expect(idsB, {heldB});
    expect(idsA.contains(heldB), isFalse,
        reason: 'القصر بهوية التقديم لا بالدور — عرف س105');

    // الشرائح: مدخل لكل تحصيل بطابعه — والفارغ بعهدة خالية
    final entries = await db.heldReceiptCustodyEntries();
    expect(entries, hasLength(2));
    expect(entries.every((e) => e.submittedAtMs != null), isTrue,
        reason: 'كل معلّق بالمسار المعتمد له حدث تقديم بطابعه');
    expect(entries.map((e) => e.voucherId).toSet(), {heldA, heldB});
  });

  testWidgets(
      'س162: شاشة السندات — سطر الشرائح بالبطاقة للمعتمد، وفلتر '
      '«تحصيلاتي» يقصر القائمة على تقديمات الجلسة والغائب يعيد الكل',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    final repId = await db.createManager(
        name: 'سالم المندوب', login: 'salem', passwordHash: 's:h');
    await seedHeldReceipt(db, repUserId: repId, repName: 'سالم المندوب');
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(managerId);

    await tester.pumpWidget(MaterialApp(home: VouchersScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // بطاقة العهدة بسطر الشرائح — تحصيل واحد حديث فشريحته «حتى 7 أيام»
    expect(find.textContaining('شرائح العهدة:'), findsOneWidget);
    expect(find.textContaining('حتى 7 أيام'), findsOneWidget);

    // القصر «تحصيلاتي»: الجلسة مالك لم يقدم شيئاً فالقائمة تخلو،
    // والإيقاف يعيد القائمة كاملة (عرض فوق القراءة — لا حالة مخزنة)
    await tester.tap(find.text('تحصيلاتي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('لا سندات'), findsOneWidget);
    await tester.tap(find.text('تحصيلاتي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('معلّق في الطريق'), findsOneWidget);
  });
}
