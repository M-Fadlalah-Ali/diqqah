// Task 51: سطر الإصدار في شاشة الإعدادات — منطق التركيب والإخفاء.
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/settings_screen.dart' show diqqahVersionLine;

void main() {
  test('سطر الإصدار: إصدار وبناء معلومان', () {
    expect(diqqahVersionLine('2.1.0', '11'), 'دِقَّة 2.1.0 (بناء 11)');
  });

  test('سطر الإصدار: بلا رقم بناء يظهر الإصدار وحده', () {
    expect(diqqahVersionLine('2.1.0', ''), 'دِقَّة 2.1.0');
  });

  test('سطر الإصدار: بلا إصدار يخفى السطر كاملاً (بيئة التطوير/الاختبار)', () {
    expect(diqqahVersionLine('', ''), '');
    expect(diqqahVersionLine('', '11'), '');
  });
}
