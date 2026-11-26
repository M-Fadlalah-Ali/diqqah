import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// س221 (تنفيذ المؤجل س219 «تسريع التجزئة بتنفيذ أصلي — قناة منصة أو
/// حزمة بتسريع أصلي» بأمر المالك «ابدأ بتنفيذ الدفعات الخمسة بالتسلسل
/// الذي عرضته»): محرك التجزئة الأصيل بقناة منصة حصراً على أندرويد
/// (PBKDF2-HMAC-SHA256 بمنفذ متسلسل جانب المنصة فخيط الواجهة لا يحجب
/// أبداً — عقد س219 البقاء حياً باقياً)، وبنفس التكرارات حرفاً — لا
/// خفض أمني بل محرك أسرع حصراً.
///
/// التثبيت بالتحقق الذاتي: متجه صغير (1000 تكراراً) يُحسب أصيلاً عبر
/// القناة وخالصاً بـ[PasswordHasher.pbkdf2Bytes] ويُقارن — المطابقة
/// تثبت [PasswordHasher.nativeCore]، وأي فشل (قناة غائبة على ويندوز
/// والاختبارات، أو مهلة، أو جواب مخالف للمتجه) يبقي الحقل فارغاً
/// فالنظام يبقى بعزل الخلفية الخالص بعقد س219 حرفاً — فلا مسار دخول
/// يتعطل ولا نتيجة أصيلة غير متحققة تُقبل أبداً.
///
/// القياس الحي بعد التثبيت بيد المالك حصراً (عرف م11/م18): الدخول
/// بالكلمة يجري أصيلاً وتحت الثانية على الجهاز المنخفض بالنتيجة،
/// و[installNote] لسان الحالة إن احتاج التشخيص لاحقاً.
class NativePbkdf2Engine {
  NativePbkdf2Engine._();

  /// القناة الأصيلة — الاسم والطريقة والمفاتيح عقد الجانب الكوتلن
  /// (MainActivity.kt): derive بوسائط password/salt/iterations/dkLen
  /// بترميز base64 حصراً والجواب base64، والعمل الثقيل بخيط عامل
  /// المنصة والجواب على الخيط الرئيسي بعقد MethodChannel.
  static const MethodChannel channel =
      MethodChannel('diqqah/security/pbkdf2');

  /// حالة التثبيت للتشخيص — true يعني الأصيلة عاملة بتحقق ذاتي ناجح.
  static bool installed = false;

  /// لسان حالة التثبيت — سبب عدم التثبيت إن حصل (للقياس الحي والتشخيص).
  static String installNote = 'لم يُجرَ التثبيت بعد';

  /// متجه التثبيت الذاتي — تكرارات صغيرة كي يكون التثبيت لحظياً عند
  /// الإقلاع، والملح نصٌّ سداسي بنمط الإنتاج (مدخل القناة النصي حرفاً).
  static const String probePassword = 'دِقَّة-تثبيت-س221';
  static const String probeSaltHex = '31323334353637383132333435363738';
  static const int probeIterations = 1000;

  /// التثبيت: تحقق ذاتي ثم ربط النواة — يُنادى مرة واحدة عند الإقلاع
  /// (main) قبل أي شاشة، ويعيد true إن ثبتت الأصيلة. المهلة قصيرة
  /// عمداً فالإقلاع أقدس من التجزئة والفشل يعني البديل الخالص لا كسراً.
  static Future<bool> probeAndInstall({
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    final expected = PasswordHasher.pbkdf2Bytes(
      utf8.encode(probePassword),
      utf8.encode(probeSaltHex),
      probeIterations,
      32,
    );
    final List<int> got;
    try {
      final answer = await channel
          .invokeMethod<String>('derive', <String, Object?>{
        'password': base64.encode(utf8.encode(probePassword)),
        'salt': base64.encode(utf8.encode(probeSaltHex)),
        'iterations': probeIterations,
        'dkLen': 32,
      })
          .timeout(timeout);
      if (answer == null) {
        throw const FormatException('جواب القناة فارغ');
      }
      got = base64.decode(answer);
    } on MissingPluginException {
      installed = false;
      installNote = 'قناة غائبة (ويندوز/الاختبارات) — الخالص س219';
      return false;
    } catch (_) {
      installed = false;
      installNote = 'فشل قناة الأصيلة — الخالص س219';
      return false;
    }
    if (!_bytesEqual(got, expected)) {
      installed = false;
      installNote = 'جواب أصيل مخالف للمتجه — أُبطل وأُبقي الخالص س219';
      return false;
    }
    PasswordHasher.nativeCore = _derive;
    installed = true;
    installNote = 'الأصيلة مثبتة بتحقق ذاتي (1000 تكراراً)';
    return true;
  }

  /// النواة المثبتة — نفس الرياضيات حرفاً عبر القناة، وأي فشل يرمي
  /// كي يهوي النادِ للبديل الخالص (شبكة أخيرة فوق التثبيت الذاتي).
  static Future<List<int>> _derive(
      List<int> password, List<int> salt, int iterations, int dkLen) async {
    final answer = await channel
        .invokeMethod<String>('derive', <String, Object?>{
      'password': base64.encode(password),
      'salt': base64.encode(salt),
      'iterations': iterations,
      'dkLen': dkLen,
    });
    if (answer == null) {
      throw StateError('جواب القناة الأصيلة فارغ');
    }
    return base64.decode(answer);
  }

  /// فك التثبيت — للاختبارات وحصراً فلا تلويث حالة ساكنة.
  static void uninstall() {
    PasswordHasher.nativeCore = null;
    installed = false;
    installNote = 'فُكّ التثبيت (اختبارات)';
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
