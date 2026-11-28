// اختبارات س215 — الواجهة: الإصدار الموحد وحارسه البايتي ⑤ (والتثبيت
// الصلب انتقل إليه من s213 بنمط انتقاله الموثق)، مع البند 7 المعماري
// المعتمد «نواة واحدة قشرة لكل منصة» من جهة القشرة (اعتماد النواة
// الحزمتين والمدخل الواحد — والنقيّة البنيوية للنواة محكومة بأخيها
// core_shell_boundary_test بحزمة التخزين).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/backup_center.dart' show kAppVersion;
import 'package:diqqah_app/settings_screen.dart' show diqqahVersionLine;

void main() {
  test('س215 (القيمة انتقلت بس232): الترميم الموحد 0.288.0+88 — pubspec '
      'وكتالوج الإصدار معاً حرفاً (حارس ⑤ — والتثبيت الصلب انتقل إليه '
      'من s213 بنمط انتقاله)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((l) => l.startsWith('version:'));
    expect(line, 'version: 0.288.0+88');
    expect(kAppVersion, '0.288.0+88');
  });

  test('س215: سطر العرض بالبادئة المُشعرة — بنمط نسخ الإصدار الموثقة '
      '(بايتات المرجع كما هي والتحول أرقام الإصدار حصراً بس216)',
      () {
    expect(diqqahVersionLine('0.280', ''), 'دِقَّة v.0.280');
    expect(diqqahVersionLine('0.280', '80'), 'دِقَّة v.0.280',
        reason: 'لاحقة البناء لا تُعرض — versionCode لا نصاً');
  });

  test('البند 7: القشرة تعتمد النواة الحزمتين بعقد path — لا نسخ '
      'منبع', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('diqqah_domain:'), isTrue);
    expect(pubspec.contains('diqqah_storage:'), isTrue);
  });

  test('البند 7: المدخل الواحد runApp بلا مداخل منصات متفرعة', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('runApp('), isTrue);
    final stray = Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            f.uri.pathSegments.last.startsWith('main_'))
        .toList();
    expect(stray, isEmpty);
  });
}
