// اختبار الحارس البنيوي للبند 7 المعماري المعتمد (نقاش المالك
// 2026-11-22 — «نواة واحدة قشرة لكل منصة» — وبدأ بتنفيذه بأمر المالك
// اللفظي 2026-11-24 س215): القاعدة المعمارية قيد آلي لا وثيقة حصراً —
// (1) نواة المجال (diqqah_domain) نقية: بلا Flutter ولا dart:ui
//     (عرف F-010: «بلا Flutter ولا Drift» — ترويسة pubspec).
// (2) نواة التخزين (diqqah_storage) نقية الاعتماد بذات الحدّ:
//     Drift/SQLite وحدهما فوق المجال — بلا Flutter ولا dart:ui.
// (3) القشرة (diqqah_app) تعتمد النواةَ الحزمتين حصراً في
//     dependencies — لا نسخة منطق موازية ولا نواة ثانية.
// (4) المدخل الواحد: main.dart بشرحّ runApp واحد للمنصتين
//     (أندرويد وWindows) — القشرة فوق النواة ذاتها لا شيفرة
//     دخول متفرعة.
// أي انزلاق مستقبلاً (استيراد flutter في النواة أو نواة ثانية)
// يُكشف هنا قبل الدفع عرف الدورة.
import 'dart:io';

import 'package:test/test.dart';

/// جذر المستودع: الاختبارات تعمل من packages/storage في CI
/// ومحلياً بعرف الدورة — فالصعود درجتين يصل المستودع.
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${dir.path}/worklog.md').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('جذر المستودع غير موجود من ${Directory.current.path}');
}

/// ملفات dart لحزمة ما — بلا مولدات (.g.dart) ولا مجلدات أخرى.
List<File> _dartFilesOf(String packageLibPath) {
  final dir = Directory(packageLibPath);
  expect(dir.existsSync(), isTrue,
      reason: 'مجلد lib للحزمة غائب: $packageLibPath');
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();
}

void _expectNoFlutterImports(List<File> files, String coreName) {
  final forbidden = <String, String>{};
  for (final f in files) {
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.contains('package:flutter/') || l.contains('dart:ui')) {
        forbidden['${f.path}:${i + 1}'] = l.trim();
      }
    }
  }
  expect(forbidden, isEmpty,
      reason: 'نواة $coreName يجب أن تبقى نقية بلا Flutter ولا dart:ui '
          '(F-010 والبند 7 المعماري) — الانزلاقات: $forbidden');
}

void main() {
  test('البند 7 (1): نواة المجال diqqah_domain بلا Flutter ولا dart:ui',
      () {
    final root = _repoRoot();
    _expectNoFlutterImports(
        _dartFilesOf('${root.path}/packages/domain/lib'), 'المجال');
    final pubspec =
        File('${root.path}/packages/domain/pubspec.yaml').readAsStringSync();
    // حرس إعلان الاعتماد لا الكلمة: التعليقات التاريخية تذكر الاسم
    // (flutter_image_compress بدرس F-010) فالحكم على سطر الاعتماد
    // حصراً (درس الجولة #427).
    expect(pubspec.contains(RegExp(r'^\s*flutter\s*:', multiLine: true)),
        isFalse,
        reason: 'pubspec المجال لا يعلن flutter أصلاً (F-010)');
  });

  test('البند 7 (2): نواة التخزين diqqah_storage بلا Flutter ولا dart:ui',
      () {
    final root = _repoRoot();
    _expectNoFlutterImports(
        _dartFilesOf('${root.path}/packages/storage/lib'), 'التخزين');
  });

  test('البند 7 (3): القشرة تعتمد النواة الحزمتين ولا نواة ثانية', () {
    final root = _repoRoot();
    final pubspec =
        File('${root.path}/packages/app/pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('diqqah_domain:'), isTrue,
        reason: 'القشرة تعتمد نواة المجال (وحدة المنبع لا النسخ)');
    expect(pubspec.contains('diqqah_storage:'), isTrue,
        reason: 'القشرة تعتمد نواة التخزين (وحدة المنبع لا النسخ)');
  });

  test('البند 7 (4): المدخل الواحد runApp بالمدخل الرئيسي للمنصتين', () {
    final root = _repoRoot();
    final main = File('${root.path}/packages/app/lib/main.dart')
        .readAsStringSync();
    expect(main.contains('runApp('), isTrue,
        reason: 'مدخل التشغيل الواحد للمنصتين (لا شيفرة دخول متفرعة)');
    // ولا مداخل بديلة للمنصات بجواره — القشرة فوق النواة ذاتها.
    final libDir = Directory('${root.path}/packages/app/lib');
    final strayEntries = libDir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            f.uri.pathSegments.last.startsWith('main_'))
        .toList();
    expect(strayEntries, isEmpty,
        reason: 'لا مداخل منصات متفرعة — المدخل main.dart وحده');
  });
}
