import 'dart:io';

import 'package:drift/drift.dart' show Value;

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// س227 (المرحلة صفر د3 من خارطة طريق التقرير الاستشاري — بأمر المالك
/// «ابدأ التنفيذ» وباستثناء صريح لحد أدنى لكلمة المرور): قفل محاولات
/// الدخول المتدرج بالقاعدة — عداد على صف المستخدم (app_users) بمستويات
/// مغلقة بنمط مستويات الخمول (D-217): كل عتبة خمس محاولات فاشلة تقفل
/// بمدة مستواها وتصعد درجة حتى سقف 30 دقيقة، والنجاح يصفّر، والمجهول بلا
/// عداد (س216)، والفحص قبل التحقق لا يمس verifyUserPassword فبوابة
/// الاستعادة سليمة.
void main() {
  /// هاش حقيقي بتكرارات صغيرة — الصيغة الذاتية الوصف بنمط P2،
  /// والترقية الآلية بthreshold الاختبار 60 فلا ثقل اختباري.
  String hashOf(String password, {int iterations = 50}) {
    final salt = PasswordHasher.newSalt();
    final hash =
        PasswordHasher(iterations: iterations).hash(password, salt);
    return PasswordHasher.formatStored(salt, hash, iterations);
  }

  DiqqahDatabase newDb() =>
      DiqqahDatabase.inMemorySyncClose(passwordUpgradeIterations: 60);

  Future<void> failLogin(DiqqahDatabase db, {String login = 'owner'}) async {
    try {
      await db.resumeSessionByLogin(
          login: login, password: 'wrong-password');
      fail('محاولة فاشلة لا تنجح');
    } on StateError {
      // الرسالة العامة س216 — عدّادها في التخزين لا في الاستثناء.
    }
  }

  Future<void> expireLock(DiqqahDatabase db, int userId) async {
    await (db.update(db.appUsers)..where((t) => t.id.equals(userId))).write(
        const AppUsersCompanion(lockedUntil: Value(0)));
  }

  test('س227: قاعدة جديدة بلا قفل — المستخدم الجديد عدّاده صفر '
      'والبوابة سالكة', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    expect(await db.loginLockoutRemaining(managerId), isNull);
    final user = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(user.failedLoginAttempts, 0);
    expect(user.lockedUntil, 0);
  });

  test('س227: أربع محاولات فاشلة لا تقفل — والخامسة تقفل دقيقة '
      'ويسجل حدث login_lockout بحمولة العدد', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));

    for (var i = 0; i < 4; i++) {
      await failLogin(db);
    }
    expect(await db.loginLockoutRemaining(managerId), isNull,
        reason: 'دون العتبة لا قفل');
    final after4 = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(after4.failedLoginAttempts, 4);

    await failLogin(db);

    final remaining = await db.loginLockoutRemaining(managerId);
    expect(remaining, isNotNull, reason: 'العتبة الخامسة تقفل');
    expect(remaining! <= const Duration(minutes: 1), isTrue);
    expect(remaining > Duration.zero, isTrue);
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('login_lockout')))
        .get();
    expect(events, hasLength(1));
    expect(events.first.userId, managerId);
  });

  test('س227: المقفل يُرد قبل التحقق — حتى بكلمته الصحيحة (القفل '
      'يحرس الباب لا الكلمة) وبعد انقضائه يدخل وينجح التصفير', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));

    for (var i = 0; i < 5; i++) {
      await failLogin(db);
    }
    expect(await db.loginLockoutRemaining(managerId), isNotNull);

    // الكلمة الصحيحة تُرد بالقفل — الرسالة الحرفية للقفل لا العامة.
    try {
      await db.resumeSessionByLogin(
          login: 'owner', password: 'owner-pass');
      fail('المقفل لا يدخل ولو بكلمته الصحيحة');
    } on StateError catch (e) {
      expect(e.message.startsWith('الدخول مقفل مؤقتاً'), isTrue);
    }

    // انقضاء القفل (محاكاة مرور الدقيقة) — الدخول ينجح والعداد يُصفَّر.
    await expireLock(db, managerId);
    final user = await db.resumeSessionByLogin(
        login: 'owner', password: 'owner-pass');
    expect(user.id, managerId);
    final after = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(after.failedLoginAttempts, 0,
        reason: 'النجاح يصفّر العداد');
    expect(await db.loginLockoutRemaining(managerId), isNull);
  });

  test('س227: التصعيد متدرج — العتبة الثانية (المحاولة 10) تقفل '
      'خمس دقائق والعتبة الثالثة (15) خمس عشرة', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));

    // العتبة الأولى: دقيقة.
    for (var i = 0; i < 5; i++) {
      await failLogin(db);
    }
    expect(await db.loginLockoutRemaining(managerId), isNotNull);

    // انقضاء الأولى ثم خمس فاشلة أخرى — العتبة الثانية: 5 دقائق.
    await expireLock(db, managerId);
    for (var i = 0; i < 5; i++) {
      await failLogin(db);
    }
    final second = await db.loginLockoutRemaining(managerId);
    expect(second, isNotNull);
    expect(second! > const Duration(minutes: 1), isTrue);
    expect(second <= const Duration(minutes: 5), isTrue);

    // العتبة الثالثة: 15 دقيقة.
    await expireLock(db, managerId);
    for (var i = 0; i < 5; i++) {
      await failLogin(db);
    }
    final third = await db.loginLockoutRemaining(managerId);
    expect(third, isNotNull);
    expect(third! > const Duration(minutes: 5), isTrue);
    expect(third <= const Duration(minutes: 15), isTrue);
  });

  test('س227: المجهول بلا عداد — الرسالة العامة س216 ولا حدث ولا قفل',
      () async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));

    for (var i = 0; i < 6; i++) {
      try {
        await db.resumeSessionByLogin(
            login: 'ghost', password: 'whatever');
        fail('المجهول لا يدخل');
      } on StateError catch (e) {
        expect(e.message, 'بيانات الدخول غير صحيحة');
      }
    }

    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('login_lockout')))
        .get();
    expect(events, isEmpty, reason: 'لا قفل بحساب وهمي');
    // والحساب القائم لم يُمسّ عداده بمحاولات المجهول.
    final user = await (db.select(db.appUsers)
          ..where((t) => t.login.equals('owner')))
        .getSingle();
    expect(user.failedLoginAttempts, 0);
  });

  test('س227: مسار resumeSession بنمطه ذاته — الفشل يعدّ والنجاح يصفّر '
      'والمقفل يُرد قبل التحقق', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));

    try {
      await db.resumeSession(userId: managerId, password: 'nope');
      fail('كلمة خاطئة لا تدخل');
    } on StateError catch (e) {
      expect(e.message, 'كلمة المرور غير صحيحة أو المستخدم معطل');
    }
    final after1 = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(after1.failedLoginAttempts, 1);

    final resumed =
        await db.resumeSession(userId: managerId, password: 'owner-pass');
    expect(resumed.id, managerId);
    final after2 = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(after2.failedLoginAttempts, 0,
        reason: 'النجاح يصفّر مسارَي الدخول معاً');
  });

  test('س227: الترحيلة v36 حية — قاعدة قائمة بلا العمودين تُرحَّل '
      'والصفوف القائمة صفراً', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v36_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate36.db');

    // قاعدة v36 كاملة ثم إنزالها إلى v35 بنزع العمودين — فيثير
    // أول فتح تالٍ الترحيلة 35→36 بعرفها (نمط اختبار v34 حرفاً).
    final seed = DiqqahDatabase(filePath: dbPath);
    await seed.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await seed.close();
    final raw = sqlite3.open(dbPath);
    raw.execute('ALTER TABLE app_users DROP COLUMN failed_login_attempts');
    raw.execute('ALTER TABLE app_users DROP COLUMN locked_until');
    raw.execute('PRAGMA user_version = 35');
    raw.close();

    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    await migrated.select(migrated.appUsers).get();
    expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);
    final oldRows = await migrated.select(migrated.appUsers).get();
    expect(oldRows, hasLength(1));
    expect(oldRows.first.failedLoginAttempts, 0,
        reason: 'الصفوف القائمة صفراً — الافتراضي بلا كتابة');
    expect(oldRows.first.lockedUntil, 0);
  });

  test('س227 (د4): الترحيلة v37 حية — دور قائم يعتمد التقارير '
      'يلحق له البوابة الفرعية وأمين المستودع لا يمس', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v37_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate37.db');

    // قاعدة جديدة تُبذر بأدوارها النمطية ثم تُرَدّ لما قبل البوابة:
    // محاسب قديم النص (بلا reports.financials) وأمين مستودع بنصه
    // القائم «items,reports» — فيثير أول فتح الترحيلة 36→37.
    final seed = DiqqahDatabase(filePath: dbPath);
    await seed.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await seed.close();
    final raw = sqlite3.open(dbPath);
    raw.execute(
        "UPDATE roles SET permissions = 'parties,items,invoices,vouchers,"
        "boxes,reports,ledger,settings,invoices.post_others' "
        "WHERE name = 'محاسب'");
    raw.execute('PRAGMA user_version = 36');
    raw.close();

    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    await migrated.select(migrated.roles).get();
    expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);

    final accountant = await (migrated.select(migrated.roles)
          ..where((t) => t.name.equals('محاسب')))
        .getSingle();
    expect(accountant.permissions.contains('reports.financials'), isTrue,
        reason: 'عرف «من كان يعتمد يبقى يعتمد»');
    final keeper = await (migrated.select(migrated.roles)
          ..where((t) => t.name.equals('أمين مستودع')))
        .getSingle();
    expect(keeper.permissions, 'items,reports',
        reason: 'أمين المستودع مخصوص بالاسم — تقارير المخزون حصراً');
  });
}
