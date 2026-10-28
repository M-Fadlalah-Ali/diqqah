// D-058: سطر الإصدار في شاشة الإعدادات — الصيغة الموثقة «0.2.01.X»
// (0: دون النسخة الأولى | 2: جيل الوثائق | 01: طبعة الوثائق | X: التجربة).
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/settings_screen.dart' show diqqahVersionLine;

void main() {
  test('سطر الإصدار: إصدار ورقم تجربة — الصيغة الموثقة 0.2.01.X', () {
    expect(diqqahVersionLine('0.2.1', '11'), 'دِقَّة 0.2.01.11');
  });

  test('طبعة من خانتين أصلاً لا تزد خانة (0.2.10 تبقى كما هي)', () {
    expect(diqqahVersionLine('0.2.10', '7'), 'دِقَّة 0.2.10.7');
  });

  test('سطر الإصدار: بلا رقم تجربة تظهر الطبعة موثقة الخانتين', () {
    expect(diqqahVersionLine('0.2.1', ''), 'دِقَّة 0.2.01');
  });

  test('سطر الإصدار: بلا إصدار يخفى السطر كاملاً (بيئة التطوير/الاختبار)', () {
    expect(diqqahVersionLine('', ''), '');
    expect(diqqahVersionLine('', '11'), '');
  });
}
