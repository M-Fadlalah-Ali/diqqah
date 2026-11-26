import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// س212 (دفعة 2 من خطة الجلسة والمستخدمين — D-215/U-005) — آلة
/// الحالتين وبوابة الجهاز: الراية المحفوظة بapp_meta فلا ثقب عودة
/// بعد موت العملية، وأفعال الثلاثة مسارات انتقال لا حالات (القفل
/// بفتح سريع لنفس المستخدم والتبديل قفلٌ ثم بلاطة أخرى والخروج
/// بلا مستأنف)، والانتقال مقفلة→نشطة بالتحقق حصراً والراية تفنجان
/// حواراً إلزامياً لصاحبها قبل إزالتها.
void main() {
  /// هاش حقيقي بتكرارات صغيرة — الصيغة الذاتية الوصف بنمط P2،
  /// والترقية الآلية ب threshold الاختبار 60 فلا ثقل اختباري.
  String hashOf(String password, {int iterations = 50}) {
    final salt = PasswordHasher.newSalt();
    final hash =
        PasswordHasher(iterations: iterations).hash(password, salt);
    return PasswordHasher.formatStored(salt, hash, iterations);
  }

  DiqqahDatabase newDb() =>
      DiqqahDatabase.inMemorySyncClose(passwordUpgradeIterations: 60);

  test('س212/D-215: قاعدة جديدة بلا راية — الحالة «نشط داخل الجلسة» '
      '(توافق تثبيتات س211 فلا إقلاع مقفلاً بعد الترقية)', () async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    expect(await db.sessionLocked(), isFalse,
        reason: 'الغائب نشط — لا راية قبل أول قفل');
  });

  test('س212/D-215: القفل فتح سريع لنفس المستخدم — الراية تُكتب '
      'والمستأنف يبقى والحدث session_locked بهوية الفاعل', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await db.lockSession();

    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), managerId,
        reason: 'القفل بفتح سريع لنفس المستخدم — المستأنف محفوظ');
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_locked')))
        .get();
    expect(events, hasLength(1));
    expect(events.first.userId, managerId);
  });

  test('س212/D-215: الخروج قفل بلا مستخدم مستأنف — الراية تُكتب '
      'والمستأنف يُمسى والحدث session_logged_out', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await db.logoutSession();

    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), isNull,
        reason: 'الخروج بلا مستأنف — بوابة الجهاز بلا بلاطة مختارة');
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_logged_out')))
        .get();
    expect(events, hasLength(1));
    expect(events.first.userId, managerId,
        reason: 'هوية الفاعل المنصرف في الحدث');
  });

  test('س212/D-215: الاستئناف بتحقق الكلمة حصراً — الخاطئة تُرفض '
      'برسالتها العربية والراية والحالة بلا مساس', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    await expectLater(
      db.resumeSession(userId: managerId, password: 'wrong-pass'),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('كلمة المرور غير صحيحة'))),
    );
    expect(await db.sessionLocked(), isTrue,
        reason: 'الرفض لا يفتح ثقب عودة');
    expect(await db.currentUserId(), managerId,
        reason: 'المستأنف كما كان');
    final resumed = await (db.select(db.events)
          ..where((t) => t.action.equals('session_resumed')))
        .get();
    expect(resumed, isEmpty, reason: 'الرفض بلا حدث استئناف');
  });

  test('س212/D-215: المعطل لا يستأنف جلسة — عقد verifyUserPassword '
      'ذاته يرفضه فلا بلاطة معطلة تفتح', () async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    final cashier =
        await (db.select(db.appUsers)..where((t) => t.login.equals('cashier')))
            .getSingle();
    await db.setUserActive(cashier.id, false);
    await db.lockSession();

    await expectLater(
      db.resumeSession(userId: cashier.id, password: 'init-pass'),
      throwsA(isA<StateError>()),
    );
    expect(await db.sessionLocked(), isTrue);
  });

  test('س212/D-215: الاستئناف الصحيح نصف الانتقال الأول — صاحب الجلسة '
      'يُعيَّن والراية باقية مقفلة فلا ثقب عودة قبل الحوار الإلزامي '
      '(وشملها صاحب الراية فيُعاد من البوابة لا من الرئيسية)', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    // الوليد أعري رايته مرفوعة (D-216) — الاستئناف عليه يثبت البقاء
    // مقفلاً حتى يعتريه الحوار الإلزامي ثم openSession.
    final cashierId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setCurrentUserId(managerId);
    await db.lockSession();

    final resumed = await db.resumeSession(
        userId: cashierId, password: 'init-pass');
    expect(resumed.id, cashierId);
    expect(await db.currentUserId(), cashierId);
    expect(await db.sessionLocked(), isTrue,
        reason: 'الراية باقية — الحوار الإلزامي قبل الإزالة حصراً');
    final resumedEvents = await (db.select(db.events)
          ..where((t) => t.action.equals('session_resumed')))
        .get();
    expect(resumedEvents, hasLength(1));
    expect(resumedEvents.first.userId, cashierId);

    // النصف الثاني: openSession بعد الحوار فتعود الحالة نشطة
    await db.openSession();
    expect(await db.sessionLocked(), isFalse);
  });

  test('س212/D-215: الدورة الكاملة قفل→استئناف→فتح ثم قفل ثانٍ — '
      'الآلة حالة لا سجل: آخر انتقال هو الحكم', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);

    await db.lockSession();
    expect(await db.sessionLocked(), isTrue);
    await db.resumeSession(userId: managerId, password: 'owner-pass');
    await db.openSession();
    expect(await db.sessionLocked(), isFalse);

    await db.lockSession();
    expect(await db.sessionLocked(), isTrue);
    await db.logoutSession();
    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), isNull);
  });

  test('س212/D-215: الراية المحفوظة بالقاعدة نفسها — موت العملية '
      'والفتح من جديد يعيد البوابة لا الجلسة (فلا ثقب عودة)', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_s212_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'session.db');

    final first = DiqqahDatabase(filePath: dbPath);
    final managerId = await first.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await first.setCurrentUserId(managerId);
    await first.lockSession();
    // موت العملية — الإغلاق القسري بلا أي فتح جلسة
    await first.close();

    final reopened = DiqqahDatabase(filePath: dbPath);
    addTearDown(reopened.close);
    expect(await reopened.sessionLocked(), isTrue,
        reason: 'الراية بapp_meta بالملف ذاته فلا إقلاع نشطاً');
    expect(await reopened.currentUserId(), managerId,
        reason: 'المستأنف باقٍ للفتح السريع');
    // والاستئناف بعد الإقلاع الجديد يعيد الانتقال كاملاً
    await reopened.resumeSession(userId: managerId, password: 'owner-pass');
    await reopened.openSession();
    expect(await reopened.sessionLocked(), isFalse);
  });
}
