import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// تجزئة كلمات المرور — PBKDF2-HMAC-SHA256 وفق معيار PKCS#5.
///
/// عدد التكرارات الافتراضي 50,000: توازن أمان/زمن على جهاز محلي متوسط
/// لعملية تحدث مرة واحدة (إنشاء المدير) ثم كل دخول. لا متطلب صريح
/// في التوثيق للرقم — قرار تنفيذ موثق في worklog (Task 40).
class PasswordHasher {
  final int iterations;

  const PasswordHasher({this.iterations = 50000});

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

  /// التحقق من سجل مخزن بصيغة «salt:hash».
  static bool verifyStored(String stored, String password,
      {int iterations = 50000}) {
    final parts = stored.split(':');
    if (parts.length != 2) {
      return false;
    }
    return PasswordHasher(iterations: iterations)
        .verify(password, parts[0], parts[1]);
  }

  /// PBKDF2 بمعماره المعياري: F(P, S, c, i) = U1 xor U2 xor ... xor Uc.
  List<int> _pbkdf2(
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
