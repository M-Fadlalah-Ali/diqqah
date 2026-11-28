// اختبارات دفعة التحصين الافتتاحي (س96/D-197) بأمر المالك الحرفي
// «ابدأ تنفيذ الإصلاح» — العلة الميدانية: تحديث b24→b26 على جهاز
// المالك علّق الافتتاح في دورة تدوير أبدية بلا كلمة، لأن بوابة
// الافتتاح القديمة بلا حرس فأي رمي في أي مرحلة قتل العملية بصمت.
// العقد الجديد: شاشة خطأ بالرسالة الحقيقية وزرّا إعادة ومشاركة،
// ولقطة أمان قبل الترحيلات، وحرس التفضيلات — كلٌّ باختباره هنا
// وباختبار التخزين upgrade_snapshot_test.dart.
//
// درس الجولة الأولى بالCI: تسليم قنوات المنصة في بيئة الاختبار لا
// يُسلَّم بمضختين ثابتتين — فالمحاكاة الحتمية لقناة المسار (رميٌ
// مصنوع) ومضخةٌ متكررة حتى الظهور لا توقيتٌ مضغوط يُخمَّن.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/main.dart';

/// قناة مسار بيئة الإنتاج — محاكاتها ترمي عين ما ترميه المنصة الغائبة
/// فحرس المرحلة الأولى يمسكه حتماً بلا اعتماد على تسليم المحرك.
const MethodChannel kPathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

/// مضخة متكررة حتى ظهور المُوادِّع أو نفاد المضخات — بلا اعتماد على
/// عدد مضخات ثابت يُخمَّن توقيت تسليمه.
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('لم يظهر المطلوب خلال مضخات المهلة');
}

void main() {
  testWidgets(
      'D-197: فشل الافتتاح يعرض شاشة الخطأ بالرسالة الحقيقية بدل '
      'الدورة الأبدية — ولا مؤشر دوران باقٍ بعد الفشل', (tester) async {
    // بلا قنوات منصة يفشل أول افتتاح حتماً — وهي عين حالة الجهاز حين
    // يفشل فتح القاعدة: رميٌ بلا حرس قديماً فدورة أبدية؛ اليوم شاشة
    // بالرسالة.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kPathProviderChannel, (call) async {
      throw MissingPluginException(
          'محاكاة فشل منصة — D-197: لا مجلد دعم');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kPathProviderChannel, null));

    // س233 (D-233): شاشة البدء بحدّها الأدنى حق الإنتاج — شاشة
    // الخطأ تُختبر بالصفر فتظهر فور فشل الافتتاح لا بعد نصف ثانية.
    await tester.pumpWidget(
        const DiqqahApp(splashMinimum: Duration.zero));
    await pumpUntil(tester, find.byKey(const ValueKey('gate_error_screen')));

    expect(find.byKey(const ValueKey('gate_error_screen')), findsOneWidget);
    // الرسالة الحقيقية معروضة للتحديد والنسخ — لا «خطأ» عامة، ومرحلة
    // الفشل موسومة بالرسالة.
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('تهيئة مجلد التطبيق'), findsOneWidget);
    expect(find.textContaining('MissingPluginException'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // زرّا الإعادة والمشاركة حاضران.
    expect(find.byKey(const ValueKey('gate_retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('gate_share')), findsOneWidget);
    // لا استثناء خارج الحرس — كل الرمي محاط وهذا هو الإصلاح ذاته.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'D-197: زر إعادة المحاولة يعيد الافتتاح كاملاً — وتكرار الفشل '
      'يبقى على شاشة الخطأ بلا انهيار ولا دورة', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kPathProviderChannel, (call) async {
      throw MissingPluginException('محاكاة فشل منصة — D-197');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kPathProviderChannel, null));

    // س233 (D-233): حقن الصفر — شاشة البدء بحدّها الأدنى حق الإنتاج.
    await tester.pumpWidget(
        const DiqqahApp(splashMinimum: Duration.zero));
    await pumpUntil(tester, find.byKey(const ValueKey('gate_error_screen')));

    await tester.tap(find.byKey(const ValueKey('gate_retry')));
    await pumpUntil(tester, find.byKey(const ValueKey('gate_error_screen')));

    // الفشل تكرر (المحاكاة ترمي دائماً) والشاشة باقية والاستثناء محاط
    // — لا انهيار ولا دورة.
    expect(find.byKey(const ValueKey('gate_error_screen')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'البوابة السليمة (حارس انحدار): قاعدة محقونة بلا مستخدمين تفتح '
      'شاشة التهيئة — لا شاشة خطأ في المسار الصحيح أبداً', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);

    await tester.pumpWidget(
      DiqqahApp(db: db, dbPath: 'gate_test.db', hasherIterations: 10),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('gate_error_screen')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // شاشة أول التشغيل (F-014) — البوابة حسمت: لا مستخدمين فتهيئة.
    expect(find.text('أول تشغيل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
