import 'package:flutter_test/flutter_test.dart';

/// درس المهلة الحارسة (CI 2026-11-01 — جولات 124..128 لدفعة 10): ملف
/// dart_test.yaml بسقفه `timeout: 120s` لا يُطبَّق على testWidgets
/// إطلاقاً — مصدر flutter_test (widget_tester.dart) يمرر مهلة صريحة
/// لكل اختبار: `timeout: timeout ?? binding.defaultTestTimeout` فالمهلة
/// الصريحة على الاختبار تتفوق دائماً على إعدادات المجموعة، والافتراضي
/// 10 دقائق — أي اختبار معلّق احترق 10 دقائق كاملة بلا قصّة حية في
/// السجل (علتا 125/126 و127 ثم 128: سبعة اختبارات × 10 دقائق = 70
/// دقيقة لجولة واحدة).
///
/// الذراع الصحيحة الموثقة من المصدر: حقل `defaultTestTimeout` القابل
/// للضبط على الرابطة الآلية (binding.dart) — ويُستدعى هذا المُساعد أعلى
/// main() قبل أول testWidgets لأن المهلة تُلتقط لحظة تسجيل الاختبار لا
/// لحظة تشغيله.
///
/// dart_test.yaml يبقى سارياً للدوال النقية `test()` التي لا تمرر مهلة
/// صريحة — فالطبقتان معاً تحرسان كل اختبارات الحزمة.
void installTestTimeoutGuard() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(seconds: 120));
  }
}

/// س219 — نافذة عبور العزل بالواجهة (نمط س217 الموثق «Isolate.run يعمل
/// بالنمطين» ودرس الجولة الحاكمة #443 الموثق: رسالة العزل الخلفي لا
/// تُسلَّم بالمنطقة الزائفة حصراً — نافذة runAsync واقعية تُسلّمها ثم
/// ضخّات عودة بالمنطقة الزائفة لتشغيل الاستمرارية وردّ الواجهة). والقفزات
/// المتعددة (التحقق ثم الترقية الآلية بعقد س219 مثلاً) بنوافذ متتالية —
/// قفزة لكل نافذة فاستمرارية القفزة التالية لا تنطلق إلا بضخّ عودتها.
/// [settleFrames] تصفير الأنيميشن الباقي بعد اكتمال القفزات — وتُطفأ
/// حيث لا يزول المؤشر بالعقد ذاته (نجاح البوابة المضخوخة مباشرة بعقد
/// س216: زالة البوابة بيد onUnlocked لا الشاشة ذاتها فالمؤشر باق).
Future<void> pumpIsolateHops(
  WidgetTester tester, {
  int hops = 1,
  bool settleFrames = true,
}) async {
  for (var i = 0; i < hops; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  if (settleFrames) {
    await tester.pumpAndSettle();
  }
}
