import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// س211 (D-216) — دفعة 1 من خطة الجلسة والمستخدمين: إنشاء المستخدمين
/// بأقل امتياز وإلزام تغيير الكلمة وحمايات التعطيل الثلاث وتغيير
/// الكلمة الذاتي — حمايات التخزين الحارسة قبل الواجهة.
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

  test('س211/D-216: دور الولادة الأعرى «مستخدم» مزروع بأذوناته الفارغة — '
      'وقاعدة قائمة تضمنه أول فتح بلا ترحيلة', () async {
    final db = newDb();
    addTearDown(db.close);
    // beforeOpen يضمن الأدوار النمطية — والسادس الأعرى بينها
    final bare = await (db.select(db.roles)
          ..where((t) => t.name.equals(kBareUserRoleName)))
        .getSingleOrNull();
    expect(bare, isNotNull, reason: 'الوليد الأعرى مزروع أول فتح');
    expect(bare!.permissions, isEmpty,
        reason: 'الصيغة الفارغة صالحة موثقة — بلا أي وحدة');
    expect(RolePermissions(bare.permissions).allows('invoices'), isFalse);
    expect(RolePermissions(bare.permissions).allows('users'), isFalse);
  });

  test('س211/D-216: createUser يولد أعرياً — دور «مستخدم» بلا أي وحدة '
      'والراية مرفوعة والحساب نشط وكلمته تتحقق', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    final newId = await db.createUser(
      name: 'كاشير أول',
      login: 'cashier',
      passwordHash: hashOf('init-pass'),
    );
    expect(newId, greaterThan(managerId));

    final user = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(newId)))
        .getSingle();
    expect(user.isActive, isTrue);
    expect(user.mustChangePassword, isTrue,
        reason: 'إلزام التغيير عند أول جلسة — راية الولادة');
    final role = await db.roleOf(user);
    expect(role, isNotNull);
    expect(role!.name, kBareUserRoleName,
        reason: 'الولادة بدور الأعرى لا بدور المانح');
    expect(RolePermissions(role.permissions).keys, isEmpty,
        reason: 'السقف الإذني للوليد صفر بنيوياً');

    // وكلمته الأولية تتحقق بعقد التحقق (ولا راية على المدير البذري)
    final verified =
        await db.verifyUserPassword(newId, 'init-pass');
    expect(verified, isNotNull);
    final manager = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(manager.mustChangePassword, isFalse,
        reason: 'الراية تُرفع عند الولادة الجديدة حصراً');
  });

  test('س211/D-216: تفرد الدخول قيد القاعدة ذاته — التكرار يُرفض استثناءً',
      () async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.createUser(
        name: 'أول', login: 'cashier', passwordHash: 's:h');
    await expectLater(
      db.createUser(
          name: 'ثانٍ', login: 'cashier', passwordHash: 's:h'),
      throwsA(isA<Exception>()),
    );
  });

  test('س211/D-216: الحماية الأولى — الجلسة الحالية لا تُعطَّل بيدها',
      () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await db.setCurrentUserId(managerId);
    await expectLater(
      db.setUserActive(managerId, false),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('لا تعطيل للجلسة الحالية'),
      )),
    );
    final manager = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(manager.isActive, isTrue, reason: 'الرفض بلا كتابة');
  });

  test('س211/D-216: الحماية الثالثة — مستخدم كامل الوحدات لا يُمس بيدٍ '
      'غير كاملة الوحدات (سقف التصعيد)', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    final bareId = await db.createUser(
        name: 'أعرى', login: 'bare', passwordHash: 's:h');
    // الجلسة للأعرى — فيحاول تعطيل المدير
    await db.setCurrentUserId(bareId);
    await expectLater(
      db.setUserActive(managerId, false),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('بكامل الوحدات بيدٍ غير كاملة الوحدات'),
      )),
    );
    final manager = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(manager.isActive, isTrue);
    // واليد الكاملة تعطّل الأعرى بلا مانع — ثم تفعيله عادته
    await db.setCurrentUserId(managerId);
    await db.setUserActive(bareId, false);
    final afterOff = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(bareId)))
        .getSingle();
    expect(afterOff.isActive, isFalse);
    await db.setUserActive(bareId, true);
    final afterOn = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(bareId)))
        .getSingle();
    expect(afterOn.isActive, isTrue);
  });

  test('س211/D-216: الحماية الثانية — آخر مستخدم نشط لا يُعطَّل '
      'حتى بجلسة عاطلة (جلسة أثرية لا تجيب)', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    final firstId = await db.createUser(
        name: 'أول', login: 'u1', passwordHash: 's:h');
    final secondId = await db.createUser(
        name: 'ثانٍ', login: 'u2', passwordHash: 's:h');
    // جلسة أثرية بمفتاح ميت — لا صاحبها فالحماية الذاتية لا تحرس
    // والعدّ الحارس الوحيد بقايا
    await db.setCurrentUserId(9999);
    await db.setUserActive(firstId, false);
    await db.setUserActive(secondId, false);
    await expectLater(
      db.setUserActive(managerId, false),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('آخر مستخدم نشط'),
      )),
    );
    final manager = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(manager.isActive, isTrue,
        reason: 'لا إقفال خارجي للبرنامج كله');
  });

  test('س211/D-216: التدقيق — الأحداث الثلاثة بنظام الأحداث بهوية الفاعل',
      () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك',
        login: 'owner',
        passwordHash: hashOf('owner-pass'));
    await db.setCurrentUserId(managerId);
    final newId = await db.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: hashOf('init-pass'));
    await db.setUserActive(newId, false);
    await db.setUserActive(newId, true);
    await db.changeOwnPassword(
      userId: managerId,
      currentPassword: 'owner-pass',
      newPasswordHash: hashOf('new-pass'),
    );

    final actions = (await db.select(db.events).get())
        .where((e) => e.action.startsWith('user_'))
        .map((e) => e.action)
        .toList();
    expect(actions, contains('user_created'));
    expect(actions, contains('user_active_toggled'));
    expect(actions, contains('user_password_changed'));
    expect(actions.where((a) => a == 'user_active_toggled'), hasLength(2));
  });

  test('س211/D-216: تغيير الكلمة الذاتي — الحالية الخاطئة تُرفض '
      'والناجح يفنجان الراية وتتحقق الجديدة', () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('old-pass'));
    await db.setCurrentUserId(managerId);

    await expectLater(
      db.changeOwnPassword(
        userId: managerId,
        currentPassword: 'wrong-pass',
        newPasswordHash: hashOf('new-pass'),
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('كلمة المرور الحالية غير صحيحة'),
      )),
    );

    await db.changeOwnPassword(
      userId: managerId,
      currentPassword: 'old-pass',
      newPasswordHash: hashOf('new-pass'),
    );
    final manager = await (db.select(db.appUsers)
          ..where((t) => t.id.equals(managerId)))
        .getSingle();
    expect(manager.mustChangePassword, isFalse);
    // القديمة ماتت والجديدة حية
    expect(await db.verifyUserPassword(managerId, 'old-pass'), isNull);
    expect(await db.verifyUserPassword(managerId, 'new-pass'), isNotNull);
  });

  test('س211/D-216: الترحيلة v34 حية — قاعدة قائمة بلا الراية تُرحَّل '
      'والصفوف القائمة صفراً والجديدة رايتها مرفوعة', () async {
    final tempDir = Directory.systemTemp.createTempSync('diqqah_v34_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final dbPath = p.join(tempDir.path, 'migrate34.db');

    // قاعدة v34 كاملة بصف قديم (المدير البذري) ثم إنزالها إلى v33
    // بنزع العمود الجديد — فيثير أول فتح تالٍ الترحيلة 33→34 بعرفها
    final seed = DiqqahDatabase(filePath: dbPath);
    await seed.createManager(
        name: 'المالك', login: 'owner', passwordHash: 's:h');
    await seed.close();
    final raw = sqlite3.open(dbPath);
    raw.execute(
        'ALTER TABLE app_users DROP COLUMN must_change_password');
    raw.execute('PRAGMA user_version = 33');
    raw.close();

    final migrated = DiqqahDatabase(filePath: dbPath);
    addTearDown(migrated.close);
    await migrated.select(migrated.appUsers).get();
    expect(migrated.schemaVersion, DiqqahDatabase.schemaVersionValue);
    final oldRows = await migrated.select(migrated.appUsers).get();
    expect(oldRows, hasLength(1));
    expect(oldRows.first.mustChangePassword, isFalse,
        reason: 'الصفوف القائمة صفراً — الافتراضي بلا كتابة');

    // والولادة الجديدة على المُرحَّلة رايتها مرفوعة
    final newId = await migrated.createUser(
        name: 'كاشير', login: 'cashier', passwordHash: 's:h');
    final created = await (migrated.select(migrated.appUsers)
          ..where((t) => t.id.equals(newId)))
        .getSingle();
    expect(created.mustChangePassword, isTrue);
  });
}
