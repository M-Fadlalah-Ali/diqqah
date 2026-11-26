import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// تجزئة كلمات المرور — PBKDF2-HMAC-SHA256 وفق معيار PKCS#5.
///
/// الافتراضي منذ P2 (09 §40): [secureIterations] = 600,000 تكراراً —
/// توصية OWASP Password Storage Cheat Sheet لـPBKDF2-HMAC-SHA256. سجلات
/// الإرث بصيغة «salt:hash» (قبل P2 — قرار Task 40 بـ50,000) تُقرأ
/// بـ[legacyIterations] كما كُتبت ولا تُفترض شيئاً غيره، وتُرقّى آلياً
/// عند أول دخول ناجح (verifyUserPassword بوحدة التخزين — نمط «الترحيل
/// عند أول فتح» الموثق P0/P1). الصيغة الجديدة ذاتية الوصف
/// «salt:hash:iterations» فلا قراءة تتفرض تكرارات لم يسجلها الكاتب.
/// الاختبارات تحقن قيماً صغيرة نمط hasherIterations الموثق — والقياس
/// الحي للكلفة بعقد الدفعة (09 §40 — الجهاز المنخفض بيد المالك حد P0).
/// س221 (تنفيذ المؤجل س219 «تسريع التجزئة بتنفيذ أصلي» بأمر المالك
/// «ابدأ بتنفيذ الدفعات الخمسة بالتسلسل الذي عرضته»): توقيع النواة
/// الأصيلة القابلة للتثبيت — قناة منصة بخيط عامل منفصل تُطبق نفس
/// الرياضيات المعيارية [PasswordHasher.pbkdf2Bytes] بنفس المدخلات
/// والنواتج حرفاً (لا خفض أمني — محرك أسرع حصراً) ويُثبت بالتحقق
/// الذاتي بمتجه معياري قبل الاستخدام (NativePbkdf2Engine بوحدة
/// التطبيق) وأي فشل أصيل في زمن العمل يهوي للبديل الخالص بعزل
/// الخلفية بعقد س219 فلا مسار دخول يتعطل أبداً.
typedef Pbkdf2NativeCore = Future<List<int>> Function(
    List<int> password, List<int> salt, int iterations, int dkLen);

class PasswordHasher {
  /// التكرارات الإنتاجية المعتمدة منذ P2 — توصية OWASP لـPBKDF2-HMAC-SHA256.
  static const int secureIterations = 600000;

  /// تكرارات سجلات الإرث المكتوبة قبل P2 بصيغة «salt:hash» (Task 40) —
  /// تُقرأ كما هي لا تُفترض غيرها، ولا تُكتب من جديد إلا بالترقية الآلية.
  static const int legacyIterations = 50000;

  /// سقف التكرارات المقبولة بالسجل الذاتي الوصف — فوقه السجل فاسد يُرد
  /// (لا تجزئة بعشرات الملايين من سجل مكتوب بيد التطبيق).
  static const int maxStoredIterations = 10000000;

  /// س221 — النواة الأصيلة المثبتة: فارغة يعني المسار الخالص بعزل
  /// الخلفية حصراً (ويندوز والاختبارات). التثبيت بيد NativePbkdf2Engine
  /// بالتطبيق بعد تحقق ذاتي بمتجه معياري، والمحاكاة بالاختبارات تحكم
  /// العقد الرباعية (الاستخدام والمطابقة والهوي والإغلاق الفشلي) —
  /// والنواة الساكنة تُعاد صفراً بعد كل اختبار فلا تلويث.
  static Pbkdf2NativeCore? nativeCore;

  final int iterations;

  const PasswordHasher({this.iterations = secureIterations});

  /// ملح عشوائي آمن 16 بايت بتمثيل سداسي (32 محرفاً).
  static String newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return _toHex(bytes);
  }

  /// يعيد البصمة السداسية — تُخزن مقترنة بملحها بصيغة «salt:hash».
  String hash(String password, String saltHex) {
    return _toHex(_pbkdf2(
      utf8.encode(password),
      utf8.encode(saltHex),
      iterations,
      32,
    ));
  }

  /// تحقق ثابت الزمن — لا يكشف عدد المحرفين المتطابقين بتوقيته.
  bool verify(String password, String saltHex, String expectedHex) {
    return _constantEquals(hash(password, saltHex), expectedHex);
  }

  /// تفكيك السجل المخزن بجيليه: «salt:hash» (إرث — تكراراته
  /// [legacyIterations] ضمنياً) و«salt:hash:iterations» (ذاتي الوصف منذ
  /// P2). الفاسد — الأجزاء الناقصة أو الفارغة أو التكرارات غير الصحيحة
  /// أو خارج المدى [1, maxStoredIterations] — يُرد null ولا يُحاول
  /// التحقق معه أبداً.
  static ({String salt, String hash, int iterations})? parseStored(
      String stored) {
    final parts = stored.split(':');
    if (parts.length == 2) {
      if (parts[0].isEmpty || parts[1].isEmpty) {
        return null;
      }
      return (
        salt: parts[0],
        hash: parts[1],
        iterations: legacyIterations,
      );
    }
    if (parts.length == 3) {
      final iters = int.tryParse(parts[2]);
      if (parts[0].isEmpty ||
          parts[1].isEmpty ||
          iters == null ||
          iters < 1 ||
          iters > maxStoredIterations) {
        return null;
      }
      return (salt: parts[0], hash: parts[1], iterations: iters);
    }
    return null;
  }

  /// صيغة التخزين الذاتية الوصف (P2) — الكاتب الوحيد للسجلات الجديدة.
  static String formatStored(
      String saltHex, String hashHex, int iterations) {
    return '$saltHex:$hashHex:$iterations';
  }

  /// التحقق من سجل مخزن بجيليه: التكرارات من المسجل — الإرث 50,000
  /// ضمنياً والجديد من جزئه الثالث — والوسيط الصريح يتجاوز المسجلاً إن
  /// مُرر (عقد المتجهات المعيارية بالاختبارات باقٍ حرفاً).
  static bool verifyStored(String stored, String password,
      {int? iterations}) {
    final parsed = parseStored(stored);
    if (parsed == null) {
      return false;
    }
    return PasswordHasher(iterations: iterations ?? parsed.iterations)
        .verify(password, parsed.salt, parsed.hash);
  }

  // ═════════════════════════════════════════════════════════════
  // س219 (قياس b73 الحي بكلمة المالك «استغرق الوقت من ضغط زر الدخول
  // حتى ظهور رسالة بيانات الدخول غير صحيحة تقريباً 4.69 خلال 6 محاولات
  // هل هذا طبيعي؟»): القياس الحي فسّره الكود — 600,000 تكراراً بنوى
  // دارت الخالصة تُنفَّذ بعزل الواجهة ذاته فتجمّد الخيط الواجهي كاملاً
  // ~4.7 ثانية كل محاولة (عتبة ANR الإدخالية أندرويد 5 ثوانٍ —
  // الهامش رفيع وجهاز أبطأ أو حمل خلفي يعبره). الفحص بنيوياً: كل
  // نداءات التجزئة والتحقق تعبر Isolate.run بإغلاقات تلتقط قيماً
  // بسيطة قابلة للإرسال حصراً (نصاً الكلمة والملح ورقم التكرارات
  // وسجل «salt:hash:iterations») — عقد قابلية الإرسال س218 بمدار
  // التجزئة، فخيط الواجهة يتنفس مهما كانت التكرارات.
  // ═════════════════════════════════════════════════════════════

  /// س219 — التجزئة بعزل خلفي: نفس الرياضيات حرفاً ([hash] نفسه يجري
  /// داخل العزل الآخر) والإغلاق يلتقط قيماً بسيطة قابلة للإرسال حصراً.
  ///
  /// س221 — الأصيلة المثبتة تُجرب أولاً: عملها الثقيل بخيط عامل المنصة
  /// عبر القناة فخيط الواجهة يتنفس في المسارين، وأي فشل أو نتيجة غائبة
  /// يهوي للعزل الخلفي الخالص بعقد س219 حرفاً (التحقق الذاتي بالتثبيت
  /// يعزل الأصيل المخالف مسبقاً — هنا شبكة أخيرة).
  static Future<String> hashInBackground(
      String password, String saltHex,
      {int? iterations}) async {
    final it = iterations ?? secureIterations;
    final core = nativeCore;
    if (core != null && it >= 1 && it <= maxStoredIterations) {
      try {
        return _toHex(await core(
            utf8.encode(password), utf8.encode(saltHex), it, 32));
      } catch (_) {
        // الهوي للبديل أدناه — عقد س219 باقياً.
      }
    }
    return Isolate.run(() =>
        PasswordHasher(iterations: it).hash(password, saltHex));
  }

  /// س219 — التحقق بعزل خلفي بنفس عقد السجل الذاتي الوصف: التفكيك
  /// هنا فسجلُ فاسد يُرد false بلا عمل إطلاقاً (عقد [parseStored])،
  /// والنواة الحسابية الثقيلة بالعزل الآخر.
  ///
  /// س221 — الأصيلة المثبتة تُجرب أولاً بنفس المدخلات حرفاً (كلمة
  /// وملح نصي سداسي وتكرارات المسجلة وطول اشتقاق 32) فالنتيجة مطابقة
  /// للخالصة، والمقارنة الثابتة الزمن [_constantEquals] بعقد التحقق،
  /// والإغلاق الفشلي: جواب أصيل مخالف = رفض لا قبول (والتثبيت الذاتي
  /// يعزل الأصيل المخالف أصلاً)، وأي فشل أصيل يهوي للعزل الخلفي الخالص.
  static Future<bool> verifyStoredInBackground(
      String stored, String password) async {
    final parsed = parseStored(stored);
    if (parsed == null) {
      return false;
    }
    final core = nativeCore;
    if (core != null &&
        parsed.iterations >= 1 &&
        parsed.iterations <= maxStoredIterations) {
      try {
        final derived = await core(utf8.encode(password),
            utf8.encode(parsed.salt), parsed.iterations, 32);
        return _constantEquals(_toHex(derived), parsed.hash);
      } catch (_) {
        // الهوي للبديل أدناه — عقد س219 باقياً.
      }
    }
    return Isolate.run(() =>
        PasswordHasher(iterations: parsed.iterations)
            .verify(password, parsed.salt, parsed.hash));
  }

  /// س219 — عمل الموازنة الزمنية: نفس نواة [pbkdf2Bytes] بكلمة وملح
  /// عابرَين يُرميان، بكلفة التكرارات الممررة ذاتها. وجهته أن الفشل
  /// بلا حساب (اسم مجهول) كان يُرد بالملي ثانية بينما الفشل بحساب
  /// (كلمة خاطئة) بثوانٍ فالرسالة الموحدة س216 كانت تُكسر بالساعة —
  /// قناة التعداد التوقيتية الموثقة بعيد الدفعة: الفشلان بكلفة واحدة
  /// فلا تمييز توقيتي يغري تجريب الأسماء (عقد س216 يكتمل توقيتاً لا
  /// نصاً حصراً).
  /// س221 — الأصيلة المثبتة تُجرب أولاً بكلفة التكرارات ذاتها (عقد
  /// الموازنة باقياً بالمسارين: القناة بخيط عامل المنصة والعزل الخالص)،
  /// وأي فشل أصيل يهوي للبديل أدناه.
  static Future<void> equalizingWorkInBackground(
      {required int iterations}) async {
    final core = nativeCore;
    if (core != null &&
        iterations >= 1 &&
        iterations <= maxStoredIterations) {
      try {
        await core(utf8.encode('دِقَّة-موازنة-س219'),
            utf8.encode('0' * 32), iterations, 32);
        return;
      } catch (_) {
        // الهوي للبديل أدناه — عقد س219 باقياً.
      }
    }
    return Isolate.run(() {
      PasswordHasher(iterations: iterations)
          .hash('دِقَّة-موازنة-س219', '0' * 32);
    });
  }

  /// PBKDF2 بمعماره المعياري: F(P, S, c, i) = U1 xor U2 xor ... xor Uc.
  /// النواة البايتية العامة — تخدم تجزئة كلمات المرور هنا وتشفير النسخ
  /// الاحتياطية في backup.dart (نفس الرياضيات المعيارية المعتمدة بالمتجهات
  /// أدناه في اختبارات هذا الملف).
  static List<int> pbkdf2Bytes(
      List<int> password, List<int> salt, int iterations, int dkLen) {
    final hmac = Hmac(sha256, password);
    final blocks = (dkLen / 32).ceil();
    final derived = <int>[];
    for (var block = 1; block <= blocks; block++) {
      // INT(i) بأربعة بايتات بالترتيب الكبير.
      var u = hmac
          .convert([...salt, block >> 24 & 0xff, block >> 16 & 0xff,
                    block >> 8 & 0xff, block & 0xff])
          .bytes;
      final f = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < u.length; j++) {
          f[j] ^= u[j];
        }
      }
      derived.addAll(f);
    }
    return derived.take(dkLen).toList(growable: false);
  }

  List<int> _pbkdf2(
      List<int> password, List<int> salt, int iterations, int dkLen) {
    return pbkdf2Bytes(password, salt, iterations, dkLen);
  }

  static String _toHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  static bool _constantEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// بوابة أول التشغيل (F-014، س-01): لا شاشة أخرى قبل وجود مدير.
class FirstRunGate {
  final bool hasAnyUser;

  const FirstRunGate({required this.hasAnyUser});

  /// تظهر شاشة إنشاء المدير إلزامياً؟
  bool get needsSetup => !hasAnyUser;
}
