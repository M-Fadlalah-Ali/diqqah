// سائق القياس الجهازي — د0 (س160) بأمر التقرير المعتمد حرفاً
// (10 §10/الفئة 1): «flutter drive --driver=test_driver/perf_driver.dart
// --target=integration_test/large_data_test.dart --profile».
// السائق القياسي للحزمة الرسمية بلا تخصيص — فالقياسات تُطبع بالمخرجات
// وتُصدَّق المالك بتصديق مكتوب عند البوابة (D-211).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
