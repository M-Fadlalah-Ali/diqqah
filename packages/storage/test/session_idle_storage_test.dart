import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// س213 (دفعة 3 من خطة الجلسة والمستخدمين — D-217/U-005) — الخمول
/// إعداد جهاز بالمستويات المغلقة 1/5/10/15/30 والافتراض 10 (حسم
/// F-147 الموثق)، والقفل بحمله المصدر (يدوي/خمول/مغادرة)، والفتح
/// السريع بالبصمة للمعلق حصراً بحراسه (المستأنف ذاته والنشط وبلا
/// راية إلزام) — والراية باقية مقفلة حتى openSession فلا ثقب عودة.
void main() {
  String hashOf(String password, {int iterations = 50}) {
    final salt = PasswordHasher.newSalt();
    final hash =
        PasswordHasher(iterations: iterations).hash(password, salt);
    return PasswordHasher.formatStored(salt, hash, iterations);
  }

  DiqqahDatabase newDb() =>
      DiqqahDatabase.inMemorySyncClose(passwordUpgradeIterations: 60);

  test('س213/D-217: قاعدة جديدة بلا مفتاح — الافتراض 10 دقائق '
      '(حسم F-147) والمستويات الخمسة المغلقة', () async {
    final db = newDb();
    addTearDown(db.close);
    expect(await db.sessionIdleMinutes(), 10);
    expect(DiqqahDatabase.sessionIdleMinuteChoices, [1, 5, 10, 15, 30]);
    expect(DiqqahDatabase.sessionIdleMinutesDefault, 10);
    expect(DiqqahDatabase.sessionLockVias,
        ['manual', 'idle', 'app_left']);
  });

  test('س213/D-217: المستويات الخمسة تُكتب وتُقرأ دائرة كاملة '
      '— إعداد جهاز بapp_meta فلا ترحيلة', () async {
    final db = newDb();
    addTearDown(db.close);
    for (final minutes in DiqqahDatabase.sessionIdleMinuteChoices) {
      await db.setSessionIdleMinutes(minutes);
      expect(await db.sessionIdleMinutes(), minutes);
    }
  });

  test('س213/D-217: القيمة خارج المستويات ترفض برسالتها العربية '
      'والقيمة الفاسدة تعود الافتراض 10 (الفاسد لا يكسر)', () async {
    final db = newDb();
    addTearDown(db.close);
    for (final bad in [0, 2, 7, 45, 60, -1]) {
      await expectLater(
        db.setSessionIdleMinutes(bad),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('من المستويات المعتمدة حصراً'),
        )),
      );
    }
    await db.upsertMetaValue(
        DiqqahDatabase.sessionIdleMinutesMetaKey, 'not-a-number');
    expect(await db.sessionIdleMinutes(), 10);
    await db.upsertMetaValue(
        DiqqahDatabase.sessionIdleMinutesMetaKey, '7');
    expect(await db.sessionIdleMinutes(), 10,
        reason: '7 خارج المستويات المغلقة — الافتراض يعود');
  });

  test('س213/D-217: القفل الخمولي via:idle — الحدث يحمل المصدر '
      'والمستأنف يبقى فتح سريع لنفس المستخدم', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await db.lockSession(via: 'idle');

    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), managerId);
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_locked')))
        .get();
    expect(events, hasLength(1));
    expect(events.first.userId, managerId);
    final payload = jsonDecode(
            await db.openLogText(events.first.payload))
        as Map<String, Object?>;
    expect(payload['via'], 'idle');
    expect(payload['resumable_user_id'], managerId);
  });

  test('س213: القفل الفوري عند المغادرة via:app_left — نفس عقد '
      'الراية (مكتوبة أولاً فلا ثقب عودة بموت العملية)', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await db.lockSession(via: 'app_left');

    expect(await db.sessionLocked(), isTrue);
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_locked')))
        .get();
    final payload = jsonDecode(
            await db.openLogText(events.first.payload))
        as Map<String, Object?>;
    expect(payload['via'], 'app_left');
  });

  test('س213: الفتح بالبصمة للمعلق حصراً — نجاحاً: المستأنف هو '
      'ذاته والراية باقية مقفلة حتى openSession والحدث بمساره '
      'device_gate_biometric', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession(via: 'idle');

    final user =
        await db.resumeSessionBiometric(userId: managerId);

    expect(user.id, managerId);
    expect(await db.sessionLocked(), isTrue,
        reason: 'النصف الأول حصراً — openSession بعده حصراً');
    expect(await db.currentUserId(), managerId);
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_resumed')))
        .get();
    expect(events, hasLength(1));
    final payload = jsonDecode(
            await db.openLogText(events.first.payload))
        as Map<String, Object?>;
    expect(payload['via'], 'device_gate_biometric');
  });

  test('س213: لا بصة تفتح غير المستأنف — بلاطة أخرى بكلمتها حصراً '
      'برسالة عربية والراية بلا مساس', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    final cashierId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await expectLater(
      db.resumeSessionBiometric(userId: cashierId),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('لصاحب الجلسة المعلقة حصراً'),
      )),
    );
    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), managerId,
        reason: 'لا بصة تُبدّل مستخدماً — التبديل بلاطته بكلمته');
  });

  test('س213/U-005: المعطل ليس مهيأً على الجهاز — البصمة ترد '
      'برسالتها ولو كان مستأنفاً', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();
    // التعطيل المباشر بالصف — حارس setUserActive يمنع تعطيل الجلسة
    // الحالية بيدها، ودرس الحالة هنا ما بعد التعطيل (المستأنف سابق).
    await (db.update(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .write(const AppUsersCompanion(isActive: Value(false)));

    await expectLater(
      db.resumeSessionBiometric(userId: managerId),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('معطل أو غير مهيأ'),
      )),
    );
  });

  test('س213/D-216: صاحب راية الإلزام لا يدخل بالبصمة — حواره '
      'يحتاج كلمة متحققة فالكلمة هي المسار برسالتها', () async {
    final db = newDb();
    addTearDown(db.close);
    // المدير هنا حضورُ نظامٍ لا فعلاً — المستأنف الكاشير صاحب الراية
    // (درس الحوار الإلزامي) فلا حامل اسمٍ غير مستعمل بالاختبار.
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    final cashierId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    // المستأنف صاحب الراية (مستأنف معلق يقفل — درس الحوار الإلزامي)
    await db.setCurrentUserId(cashierId);
    await db.lockSession();

    await expectLater(
      db.resumeSessionBiometric(userId: cashierId),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('بتحقق الكلمة حصراً'),
      )),
    );
    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), cashierId);
  });
}
