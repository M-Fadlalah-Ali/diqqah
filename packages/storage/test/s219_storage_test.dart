import 'dart:io';

import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// جذر المستودع: الاختبارات تعمل من packages/storage في CI ومحلياً
/// بعرف الدورة — فالصعود درجتين يصل المستودع (نمط core_shell_boundary).
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${dir.path}/worklog.md').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('جذر المستودع غير موجود من ${Directory.current.path}');
}

/// س219 — قياس b73 الحي بكلمة المالك «استغرق الوقت من ضغط زر الدخول
/// حتى ظهور رسالة بيانات الدخول غير صحيحة تقريباً 4.69 خلال 6 محاولات
/// هل هذا طبيعي؟»: الرقم نفسه فسّره الكود — 600,000 تكراراً بنوى دارت
/// الخالصة (توصية OWASP لـPBKDF2-HMAC-SHA256 بعقد P2/09 §40) كانت
/// تُنفَّذ بعزل الواجهة ذاته فتجمّد الخيط الواجهي كاملاً ~4.7 ثانية
/// كل محاولة (عتبة ANR الإدخالية أندرويد 5 ثوانٍ — الهامش رفيع)،
/// وقاعدة البيانات الكبيرة لا علاقة لها إطلاقاً (جدول المستخدمين
/// صفوفٌ قليلة والكلفة حسابٌ حتمي بملح 16 بايتة — ثبات الزمن عبر
/// المحاولات الست شاهدُ ذلك). الدفعة بعقدَين:
///
/// 1. النواة الحسابية بعزل الخلفية حصراً ([PasswordHasher.
///    verifyStoredInBackground] و[hashInBackground] — عقد قابلية
///    الإرسال س218 بالمدار ذاته: الإغلاق قيم بسيطة قابلة للإرسال
///    حصراً) فخيط الواجهة يتنفس مهما كانت التكرارات.
/// 2. موازنة التوقيت: مسارات الرفض الثلاثة (اسم مجهول/معطل/كلمة
///    خاطئة) كانت تتفرق زمنياً — المجهول بالملي ثانية بلا تجزئة
///    والمعطل يُرد قبل الحساب فالرسالة الموحدة س216 كانت تُكسر
///    بالساعة (قناة تعداد توقيتية رغم النص الموحد) — فالرفضُ بكلفة
///    حسابية واحدة ([PasswordHasher.equalizingWorkInBackground])
///    يكتمل به العقد توقيتاً لا نصاً حصراً.
///
/// الاختبارات بتكرارات 100,000 كي يطغى الحساب الحتمي على ضجيج
/// الجولة، والحد الصادق بنمط م11/م18: زمن 600,000 الفعلي على الجهاز
/// المنخفض بيد المالك حصراً (القياس الحي عقد الدفعة 09 §40) —
/// والاختبار يحكم اتجاه التسريب النسبي لا الأرقام المطلقة.
void main() {
  const int iters = 100000;

  /// هاش حقيقي بتكرارات الاختبار — الصيغة الذاتية الوصف بنمط P2.
  String hashOf(String password, {int iterations = iters}) {
    final salt = PasswordHasher.newSalt();
    final hash =
        PasswordHasher(iterations: iterations).hash(password, salt);
    return PasswordHasher.formatStored(salt, hash, iterations);
  }

  DiqqahDatabase newDb() =>
      DiqqahDatabase.inMemorySyncClose(passwordUpgradeIterations: iters);

  const generic = 'بيانات الدخول غير صحيحة';

  Future<String?> failureOf(Future<dynamic> probe) async {
    try {
      await probe;
      return null;
    } catch (e) {
      return e is StateError ? e.message : 'غير متوقع: $e';
    }
  }

  test('س219: موازنة التوقيت — الفشل بلا حساب (اسم مجهول) بكلفة الفشل '
      'بحساب (كلمة خاطئة) ذاتها فلا قناة تعداد توقيتية تكسر الرسالة '
      'الموحدة س216', () async {
    final db = newDb();
    addTearDown(db.close);
    await db.createManager(
        name: 'المالك', login: 'owner', passwordHash: hashOf('owner-pass'));
    await db.lockSession();

    // كلمة خاطئة بحساب قائم — المسار المحسوب الكامل.
    final swWrong = Stopwatch()..start();
    final wrong = await failureOf(db.resumeSessionByLogin(
        login: 'owner', password: 'wrong-pass'));
    swWrong.stop();

    // اسم مجهول — كان يُرد بالملي ثانية قبل س219.
    final swGhost = Stopwatch()..start();
    final ghost = await failureOf(db.resumeSessionByLogin(
        login: 'ghost', password: 'owner-pass'));
    swGhost.stop();

    expect(wrong, generic);
    expect(ghost, generic, reason: 'عقد س216 باقياً: الرسالة واحدة');
    expect(
      swGhost.elapsedMicroseconds,
      greaterThanOrEqualTo(swWrong.elapsedMicroseconds * 0.4),
      reason: 'المجهول لا يفشل أسرع من الكلمة الخاطئة — اتجاه التسريب '
          'التوقيتي المغلق (المجهول ${swGhost.elapsedMilliseconds}ms '
          'المحسوب ${swWrong.elapsedMilliseconds}ms)',
    );
    // والرفض بلا حدث عقد س216 — عمل الموازنة أثرٌ صامت.
    final events = await (db.select(db.events)
          ..where((t) => t.action.equals('session_resumed')))
        .get();
    expect(events, isEmpty);
    expect(await db.currentUserId(), isNull,
        reason: 'الرفض لا يعيّن جلسة');
  });

  test('س219: المعطل حساباً حقيقياً بسجله ذاته — كلفة رفضه كلفة كلمة '
      'خاطئة بالنشط فلا ساعة تميّز معطلاً من كلمة خاطئة', () async {
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

    final swWrong = Stopwatch()..start();
    final wrong = await failureOf(db.resumeSessionByLogin(
        login: 'owner', password: 'wrong-pass'));
    swWrong.stop();

    final swEx = Stopwatch()..start();
    final exFailure = await failureOf(db.resumeSessionByLogin(
        login: 'ex', password: 'ex-pass'));
    swEx.stop();

    expect(wrong, generic);
    expect(exFailure, generic);
    expect(
      swEx.elapsedMicroseconds,
      greaterThanOrEqualTo(swWrong.elapsedMicroseconds * 0.4),
      reason: 'المعطل لا يُرد قبل الحساب — كلفة الرفض الثلاثة واحدة '
          '(المعطل ${swEx.elapsedMilliseconds}ms '
          'المحسوب ${swWrong.elapsedMilliseconds}ms)',
    );
  });

  test('س219: نواة العزل الخلفي مطابقة النواة المتزامنة حرفاً — '
      'hashInBackground وverifyStoredInBackground بالمتجهة ذاتها '
      'والسجل الفاسد يُرد بلا عمل', () async {
    final salt = PasswordHasher.newSalt();
    final syncHash = PasswordHasher(iterations: 200).hash('ك-س219', salt);
    final bgHash = await PasswordHasher.hashInBackground('ك-س219', salt,
        iterations: 200);
    expect(bgHash, syncHash,
        reason: 'الرياضيات واحدة — العزل ينفّذ [hash] نفسه');

    final stored = PasswordHasher.formatStored(salt, syncHash, 200);
    expect(
        await PasswordHasher.verifyStoredInBackground(stored, 'ك-س219'),
        isTrue);
    expect(await PasswordHasher.verifyStoredInBackground(stored, 'خطأ'),
        isFalse);
    expect(
        await PasswordHasher.verifyStoredInBackground('سجل-فاسد', 'ك-س219'),
        isFalse,
        reason: 'التفكيك هنا — الفاسد false بلا عمل إطلاقاً (عقد '
            'parseStored)');
  });

  test('س219: الحرس البنيوي — التخزين بلا تحقق متزامن ولا تجزئة متزامنة '
      'ومسارات الرفض الثلاثة بعمل الموازنة', () {
    final src = File(
            '${_repoRoot().path}/packages/storage/lib/src/database.dart')
        .readAsStringSync();
    // لا نداء متزامن للتحقق — 600,000 تكراراً بعزل الواجهة تجميد واجهة
    // (القياس الحي b73) فالاستدعاءات كلها بالخلفية.
    expect(src.contains('PasswordHasher.verifyStored('), isFalse,
        reason: 'عقد س219: لا التحقق المتزامن بالتخزين إطلاقاً');
    expect(
        'verifyStoredInBackground('.allMatches(src).length,
        greaterThanOrEqualTo(2),
        reason: 'verifyUserPassword وchangeOwnPassword بالتحقق الخلفي');
    // مسار المجهول بعمل الموازنة (قناة التعداد التوقيتية المغلقة).
    expect(src.contains('equalizingWorkInBackground('), isTrue,
        reason: 'المجهول بعمل الموازنة قبل الرمي العام');
    // والترقية الآلية بعزل الخلفية ذاته (تجميد ثانٍ كان ينتظر أول
    // دخول ناجح بإرث).
    expect(src.contains('hashInBackground('), isTrue,
        reason: 'الترقية بعزل الخلفية');
  });
}
