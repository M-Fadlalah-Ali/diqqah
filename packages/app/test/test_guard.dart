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
