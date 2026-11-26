import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_app/native_pbkdf2.dart';

/// س221 — تثبيت محرك التجزئة الأصيل بالتحقق الذاتي (عقد native_pbkdf2):
/// القناة المحاكاة تطبق الرياضيات الخالصة ذاتها فالتثبيت ينجح والتحقق
/// الحي بعده يمر بالقناة المثبتة بنتيجة مطابقة، والجواب المخالف أو
/// القناة الغائبة (ويندوز/الاختبارات) يبقيان الخالص س219 حرفاً —
/// والحالة الساكنة تُعاد بعد كل اختبار فلا تلويث.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// معالج القناة المحاكى — يقلّد الجانب الأصيل بالرياضيات الخالصة.
  void mockChannel(Future<Object?>? Function(MethodCall call)? handler) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativePbkdf2Engine.channel, handler);
  }

  tearDown(() {
    mockChannel(null);
    NativePbkdf2Engine.uninstall();
  });

  testWidgets('س221: التثبيت الذاتي الناجح — متجه مطابق يثبت النواة '
      'والتحقق الحي بعدها يمر بالقناة', (tester) async {
    mockChannel((call) async {
      expect(call.method, 'derive');
      final args = call.arguments as Map<Object?, Object?>;
      final password = utf8.decode(base64.decode(args['password'] as String));
      final salt = utf8.decode(base64.decode(args['salt'] as String));
      final derived = PasswordHasher.pbkdf2Bytes(
          utf8.encode(password), utf8.encode(salt),
          args['iterations'] as int, args['dkLen'] as int);
      return base64.encode(derived);
    });
    expect(await NativePbkdf2Engine.probeAndInstall(), isTrue);
    expect(NativePbkdf2Engine.installed, isTrue);
    expect(PasswordHasher.nativeCore, isNotNull);

    final salt = PasswordHasher.newSalt();
    final viaNative = await PasswordHasher.hashInBackground(
        'م-س221', salt,
        iterations: 100);
    expect(viaNative, PasswordHasher(iterations: 100).hash('م-س221', salt),
        reason: 'التحقق الحي عبر القناة المثبتة بنتيجة مطابقة للخالصة');
  });

  testWidgets('س221: جواب أصيل مخالف للمتجه يُبطل التثبيت — الخالص '
      'س219 يبقى حاكماً (الإغلاق الفشلي)', (tester) async {
    mockChannel((call) async => base64.encode(List<int>.filled(32, 7)));
    expect(await NativePbkdf2Engine.probeAndInstall(), isFalse);
    expect(NativePbkdf2Engine.installed, isFalse);
    expect(PasswordHasher.nativeCore, isNull);
    expect(NativePbkdf2Engine.installNote, contains('مخالف'));
  });

  testWidgets('س221: القناة الغائبة (ويندوز/الاختبارات) تُبقي الخالص '
      'س219 حرفاً — بلا تثبيت وبلا كسر', (tester) async {
    // بلا معالج محاكى — والمنداء بنافذة واقعية نمط س217 الموثق: جواب
    // المحرك الحقيقي (المغلف الفارغ ← MissingPluginException) يصل
    // بحدث واقعي لا بالزائفة فلا تعليق بلا ضخّ (درس الجولة الحاكمة
    // #448 الموثق: تعليق 10 دقائق بنافذة الزائفة على نداء قناة
    // بلا معالج).
    final ok =
        await tester.runAsync(() => NativePbkdf2Engine.probeAndInstall());
    expect(ok, isFalse);
    expect(NativePbkdf2Engine.installed, isFalse);
    expect(PasswordHasher.nativeCore, isNull);
    expect(NativePbkdf2Engine.installNote, contains('غائبة'));
  });
}
