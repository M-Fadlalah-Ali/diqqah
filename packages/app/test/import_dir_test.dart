// D-057 — نقطة بداية منتقي الاستيراد: مجلد التنزيلات حيث تدعمه المنصة.
//
// الدالة نقية (تستقبل المسارات ولا تلمس بيئة الاختبار) — فتُختبر بحقن
// مجلدات مؤقتة: وجود التنزيلات تحت USERPROFILE أو HOME، وغيابهما،
// وترتيب الأولوية. أندرويد SAF يدير نقطة البداية بنفسه فتعاد null
// حين لا يوجد أي مرشح — وهذا غطاؤه حالة «لا مجلدات موجودة».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;

// س140: الدالة نُقلت إلى device_status.dart بلا مساس سلوكها
// (منبع واحد لشاشتي الاستيراد والإعدادات بلا دورة استيراد).
import 'package:diqqah_app/device_status.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('diqqah_d057_t_');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test('D-057: التنزيلات تحت USERPROFILE تُعاد نقطة بداية (ويندوز)', () {
    final downloads = Directory(p.join(temp.path, 'Downloads'))
      ..createSync();
    expect(
      defaultImportDirectory(userProfile: temp.path, home: null),
      downloads.path,
    );
  });

  test('D-057: التنزيلات تحت HOME تُعاد (لينكس/ماك)', () {
    final downloads = Directory(p.join(temp.path, 'Downloads'))
      ..createSync();
    expect(
      defaultImportDirectory(userProfile: null, home: temp.path),
      downloads.path,
    );
  });

  test('D-057: الأولوية لمرشح USERPROFILE عند وجود الاثنين', () {
    final profileDownloads = Directory(
      p.join(temp.path, 'profile', 'Downloads'),
    )..createSync(recursive: true);
    final homeDownloads = Directory(
      p.join(temp.path, 'home', 'Downloads'),
    )..createSync(recursive: true);
    expect(
      defaultImportDirectory(
        userProfile: p.join(temp.path, 'profile'),
        home: p.join(temp.path, 'home'),
      ),
      profileDownloads.path,
    );
    expect(homeDownloads.path, isNotEmpty); // حماية من تحذير المتغير المهمل
  });

  test('D-057: لا تنزيلات موجودة → null بلا رمي (أندرويد/إلغاء آمن)', () {
    expect(
      defaultImportDirectory(userProfile: temp.path, home: temp.path),
      isNull,
    );
    expect(defaultImportDirectory(userProfile: null, home: null), isNull);
    expect(defaultImportDirectory(userProfile: '', home: ''), isNull);
  });
}
