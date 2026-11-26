// اختبارات د6 (س175 — الاستيعاب الواجهي والأحمال الختامية بنص خارطة
// م4 §46): النافذة الواجهية للانضمام والأرشفة والإبطال المُحالة من
// د5 + المتابعات اليومية بلوحة «يحتاج انتباهك» (س74/D-184/F-146).
//
// **الحد الصادق ما يُختبر هنا**: السجلان المحليان بأفعالهما (الإصدار
// والإبطال والمسح وإعادة الثقة) ولسان الحد الصادق (لا مزوّد مضبوطاً
// ولا رفع زائف) — والفرض الخادمي موضع المهايئ والخادم بعقد F-136
// بتصديق مكتوب عرف D-211 لا هنا.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/follow_ups_screen.dart';
import 'package:diqqah_app/settings_screen.dart';
import 'package:diqqah_app/sync_work_screen.dart';

import 'test_guard.dart';

void main() {
  installTestTimeoutGuard();

  testWidgets('د6: بطاقة الإعدادات «العمل الجماعي والمزامنة» بنهاية '
      'القائمة تفتح شاشتها بلسان المعضات الثلاث (درس D-098/س107)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah_d6/dummy.db',
        onRestored: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // بند الدفعة بنهاية القائمة — سحبٌ هادئة تكشفه (السرد الكسول لا
    // يبني البعيد) والحرس باقٍ: البند بلسان الوصول بالتمرير لا مدفون.
    var found = false;
    for (var i = 0; i < 40 && !found; i++) {
      final matcher = find.text('العمل الجماعي والمزامنة');
      found = matcher.evaluate().isNotEmpty;
      if (!found) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pump();
      }
    }
    expect(found, isTrue, reason: 'البند ظاهر لا مدفون');

    await tester.tap(find.text('العمل الجماعي والمزامنة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('هذا الجهاز'), findsOneWidget);
    expect(find.text('رمز الانضمام'), findsOneWidget);
    expect(find.text('سجل الأجهزة'), findsOneWidget);
    expect(find.text('الأرشفة السحابية الدورية'),
        findsOneWidget);
  });

  testWidgets('د6: الحد الصادق الحي — لا مزوّد مضبوطاً ولا رفع زائف '
      'والأرشفة بانتظار الاتصال تأجيل موثق لا رفض', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(
        home: SyncWorkScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('لا مزوّد مضبوطاً بعد'), findsOneWidget);
    expect(find.textContaining('الرفع الفعلي يتطلب مزوّد مزامنة مضبوطاً'),
        findsOneWidget);
    expect(find.textContaining('بانتظار الاتصال'), findsOneWidget,
        reason: 'غياب الاتصال تأجيل موثق نص F-137 لا رفض ولا صمت');
    expect(find.text('لا رموز مصدرة بعد.'), findsOneWidget);
    expect(find.text('لا أجهزة مسجلة بعد.'), findsOneWidget);
  });

  testWidgets('د6: المدير يصدر رمز انضمام — صيغة XXXX-XXXX وبلا ملتبس '
      'وبالسجل حالة «بانتظار الاستهلاك» (م-32)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final userId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(userId);

    await tester.pumpWidget(MaterialApp(
        home: SyncWorkScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('sync_issue_code')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // الرمز بالعرض بصيغته البشرية — ثمانية محارف بفاصل.
    expect(find.textContaining('-'), findsWidgets,
        reason: 'صيغة XXXX-XXXX معروضة');
    expect(find.text('بانتظار الاستهلاك'), findsOneWidget);
    expect(find.textContaining('صالح 24 ساعة واستهلاك واحد'), findsOneWidget);

    // الكتاب بالقاعدة كنص JSON سليم والأبجدية بلا ملتبس.
    final bookText = await db.joinCodeBookText();
    expect(bookText, isNotNull);
    final book = JoinCodeBook.fromJson(bookText!);
    expect(book.records, hasLength(1));
    final code = book.records.single.code;
    expect(code.length, joinCodeLength);
    for (final ch in code.split('')) {
      expect(joinCodeAlphabet.contains(ch), isTrue,
          reason: 'كل محرف من الأبجدية الآمنة بلا ملتبس');
    }
    // والقرار موثق كحدث بذيل الرمز حصراً.
    final events = await db.customSelect(
        "SELECT payload FROM events WHERE action = 'join_code_issued'").get();
    expect(events, hasLength(1));
    // الحمولة بنص السجل الحدثي المشفر (p3) — تُفك بأداة القراءة الواحدة
    // لا jsonDecode مباشرة (عرف log_cipher F-010).
    final payload = jsonDecode(
            await db.openLogText(events.single.data['payload'] as String))
        as Map<String, Object?>;
    expect(payload['code_tail'], code.substring(code.length - 4));
    expect(payload.containsKey('code'), isFalse,
        reason: 'الرمز كاملاً لا يُكتب بالسجل — الذيل حصراً');
  });

  testWidgets('د6: إبطال جهاز نص م-33 — قلب حالة لا حذف والسبب موثق '
      'والصف يبقى بتاريخه', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final userId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(userId);

    // جهازان مسجلان سلفاً بالسجل المحلي.
    final registry = SyncDeviceRegistry()
      ..register(deviceId: 'SELLER-01', atUtc: DateTime.utc(2026, 11, 1))
      ..register(deviceId: 'SELLER-02', atUtc: DateTime.utc(2026, 11, 2));
    await db.saveDeviceRegistryText(registry.toJson());

    await tester.pumpWidget(MaterialApp(
        home: SyncWorkScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('SELLER-01'), findsOneWidget);
    expect(find.text('SELLER-02'), findsOneWidget);

    // إبطال الأول بحوار السبب.
    await tester.tap(find.byKey(const ValueKey('sync_revoke_SELLER-01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('إبطال الجهاز «SELLER-01»'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first, 'فقد الغائب — جهاز مفقود');
    await tester.tap(find.text('إبطال').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // الصف يبقى بتاريخه وسببه — لا حذف نص م-33 حرفاً.
    expect(find.text('SELLER-01'), findsOneWidget);
    expect(find.textContaining('فقد الغائب'), findsOneWidget);
    expect(find.textContaining('أُبطل'), findsOneWidget,
        reason: 'لحظة الإبطال ظاهرة بلسان م-33');

    // السجل بالقاعدة محدث والقرار موثق كحدث.
    final saved = SyncDeviceRegistry.fromJson(
        (await db.deviceRegistryText())!);
    final revoked = saved.byId('SELLER-01')!;
    expect(revoked.status, SyncDeviceStatus.revoked);
    expect(revoked.revokedAtUtc, isNotNull);
    expect(revoked.revokeReason, 'فقد الغائب — جهاز مفقود');
    expect(saved.byId('SELLER-02')!.status, SyncDeviceStatus.active,
        reason: 'الأخر بلا مساس');
    final events = await db.customSelect(
        "SELECT payload FROM events WHERE action = 'sync_device_revoked'")
        .get();
    expect(events, hasLength(1));
    expect(jsonDecode(await db.openLogText(events.single.data['payload']
            as String)) as Map<String, Object?>,
        contains('device'),
        reason: 'القرار موثق كحدث بحمولته المفكوكة بأداة القراءة');
  });

  testWidgets('د6: «مسح عند أول اتصال» على المُبطَل حصراً وإعادة الثقة '
      'تنطفئ العلم (م-33)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    final userId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(userId);

    final registry = SyncDeviceRegistry()
      ..register(deviceId: 'LOST-01', atUtc: DateTime.utc(2026, 11, 1))
      ..revoke(deviceId: 'LOST-01', atUtc: DateTime.utc(2026, 11, 3));
    await db.saveDeviceRegistryText(registry.toJson());

    await tester.pumpWidget(MaterialApp(
        home: SyncWorkScreen(db: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('sync_wipe_LOST-01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('مسح عند أول اتصال مفعّل'), findsOneWidget);

    // إعادة الثقة تنطفئ معها العلم القديم نص m-33.
    await tester.tap(find.byKey(const ValueKey('sync_retrust_LOST-01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('مسح عند أول اتصال مفعّل'), findsNothing);

    final saved = SyncDeviceRegistry.fromJson(
        (await db.deviceRegistryText())!);
    final trusted = saved.byId('LOST-01')!;
    expect(trusted.status, SyncDeviceStatus.active);
    expect(trusted.wipeOnFirstContact, isFalse,
        reason: 'العلم القديم ينطفئ مع إعادة الثقة فلا أمر قديم ناصب');
    expect(trusted.joinedAtUtc, isNotNull,
        reason: 'لحظة الانضمام الباقية بعقد م-33');
  });

  testWidgets('د6: المتابعات اليومية بلوحة «يحتاج انتباهك» — البنود '
      'الثلاثة تظهر بلوحة القائمة ولسانها المعتمد (س74/D-184)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    final input = FollowUpsInput(
      belowMinimumItems: [
        BelowMinimumItem(
            sku: 'MIN-1',
            name: 'سكر ناعم',
            availableQty: 2,
            minimumQty: 10),
      ],
      overAmountCapBalances: [
        OverAmountCapBalance(
            partyName: 'عميل متأخر',
            balanceMinor: 1500000,
            capMinor: 1000000),
      ],
      overTimeCapBalances: [
        OverTimeCapBalance(
            partyName: 'ذمة متقادمة',
            oldestAgeDays: 90,
            termDays: 30),
      ],
    );
    final snapshot = FollowUpsSnapshot(input, buildFollowUps(input));

    await tester.pumpWidget(MaterialApp(
      home: FollowUpsScreen(
        db: db,
        loadOverride: () async => snapshot,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('أصناف انخفضت عن الحد الأدنى المحدد'),
        findsOneWidget);
    expect(find.textContaining('سكر ناعم'), findsOneWidget);
    expect(find.textContaining('أرصدة تجاوزت سقفها الأعلى مبلغاً'),
        findsOneWidget);
    expect(find.textContaining('عميل متأخر'), findsOneWidget);
    expect(find.textContaining('ذمم تجاوزت مدة السداد المحددة'),
        findsOneWidget);
    expect(find.textContaining('ذمة متقادمة'), findsOneWidget);
    // الأفعال المحقونة بلوحة القائمة بلسانها.
    expect(find.text('أصناف المخزون'), findsOneWidget);
    expect(find.text('كشوف الأطراف'), findsOneWidget);
    expect(find.text('أعمار الذمم'), findsOneWidget);
  });
}
