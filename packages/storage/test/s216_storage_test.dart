import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// س216 — بند الدخول اليدوي وجذر الثقل بالتخزين: [resumeSessionByLogin]
/// برسالة الفشل العامة الواحدة حصراً (لا تعداد حسابات ولا تفرقة بين
/// اسم مجهول ومعطل وكلمة خاطئة — عرف المصادقة الكبيرة بأمر المالك)،
/// ولقطة ما قبل الترقية تقرأ ترويسة الملف 64 بايتة لا الملف كله.
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

  test('س216: الدخول اليدوي باسم الدخول — النجاح يعيّن صاحب الجلسة '
      'وسبقُ الحدث session_resumed والراية باقية حتى openSession',
      () async {
    final db = newDb();
    addTearDown(db.close);
    final managerId = await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.lockSession();

    final user = await db.resumeSessionByLogin(
        login: 'owner', password: 'owner-pass');

    expect(user.id, managerId);
    expect(await db.currentUserId(), managerId);
    expect(await db.sessionLocked(), isTrue,
        reason: 'الراية باقية — openSession نصفه الثاني حصراً');
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_resumed')))
        .get();
    expect(events, hasLength(1));
    expect(events.first.userId, managerId,
        reason: 'هوية الفاعل بالحدث بعد نجاح التحقق حصراً');
  });

  test('س216: كل الفشل رسالة عامة واحدة بالحرف — كلمة خاطئة واسم '
      'مجهول ومستخدم معطل بلا تفرقة إطلاقاً فلا معرفة وجودٍ من '
      'شاشة الدخول', () async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.createUser(
        name: 'سابق', login: 'ex', passwordHash: hashOf('ex-pass'));
    final ex = await (db.select(db.appUsers)
          ..where((t) => t.login.equals('ex')))
        .getSingle();
    await db.setUserActive(ex.id, false);
    await db.lockSession();

    const generic = 'بيانات الدخول غير صحيحة';
    Future<String?> failureOf(Future<dynamic> probe) async {
      try {
        await probe;
        return null;
      } catch (e) {
        return e is StateError ? e.message : 'غير متوقع: $e';
      }
    }

    expect(
      await failureOf(db.resumeSessionByLogin(
          login: 'owner', password: 'wrong-pass')),
      generic,
    );
    expect(
      await failureOf(db.resumeSessionByLogin(
          login: 'ghost', password: 'owner-pass')),
      generic,
      reason: 'المجهول برسالة الكلمة الخاطئة ذاته — لا استنتاج وجود',
    );
    expect(
      await failureOf(db.resumeSessionByLogin(
          login: 'ex', password: 'ex-pass')),
      generic,
      reason: 'المعطل برسالة المجهول ذاته — لا معرفة وجودٍ',
    );
    // والحالة بلا مساس بكل الرفض
    expect(await db.sessionLocked(), isTrue);
    expect(await db.currentUserId(), isNull,
        reason: 'الرفض لا يعيّن جلسة');
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_resumed')))
        .get();
    expect(events, isEmpty, reason: 'الرفض بلا حدث استئناف');
  });

  test('س216: المطابقة غير الحساسة لحالة اللاتينية مع تقليم الفراغات '
      '— والعربية بأصلها لا تتحول', () async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.lockSession();

    final user = await db.resumeSessionByLogin(
        login: '  OWNER ', password: 'owner-pass');
    expect(user.login, 'owner',
        reason: 'الجلسة بصاحب السجل الأصلي لا بنص الإدخال');
  });

  test('س216: لقطة ما قبل الترقية تقرأ الترويسة حصراً — إصدار أدنى '
      'فلقطة، ومطابق فلا لقطة، وغير معروف فلقطة كما هو', () async {
    final tmp = await Directory.systemTemp.createTemp('dq_s216');
    addTearDown(() => tmp.delete(recursive: true));
    Uint8List headerWith(int version) {
      final b = Uint8List(100);
      const magic = 'SQLite format 3';
      for (var i = 0; i < 15; i++) {
        b[i] = magic.codeUnitAt(i);
      }
      b[15] = 0;
      b[60] = (version >> 24) & 0xFF;
      b[61] = (version >> 16) & 0xFF;
      b[62] = (version >> 8) & 0xFF;
      b[63] = version & 0xFF;
      return b;
    }

    // إصدار أدنى من الهدف (34) — لقطة قبل مساس الترحيلة
    final older = p.join(tmp.path, 'older.db');
    await File(older).writeAsBytes(headerWith(34));
    await snapshotBeforeUpgrade(older, 35);
    expect(await File('$older.preup35').exists(), isTrue);

    // إصدار مطابق للهدف (35) — لا ترقية ماددة فلا لقطة
    final same = p.join(tmp.path, 'same.db');
    await File(same).writeAsBytes(headerWith(35));
    await snapshotBeforeUpgrade(same, 35);
    expect(await File('$same.preup35').exists(), isFalse);

    // غير معروف (ترويسة ناقصة كقاعدة مشفرة) — لقطة كما هو بعرف
    // «غير معروف يُحفظ» ولا يفتح الملف أصلاً
    final unknown = p.join(tmp.path, 'unknown.db');
    await File(unknown).writeAsBytes(Uint8List(40));
    await snapshotBeforeUpgrade(unknown, 35);
    expect(await File('$unknown.preup35').exists(), isTrue);
  });
}
