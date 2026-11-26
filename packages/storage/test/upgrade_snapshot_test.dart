// اختبارات دفعة التحصين الافتتاحي (س96/D-197) — لقطة الأمان قبل
// ترقية المخطط snapshotBeforeUpgrade: قاعدة غائبة، إصدار مطابق،
// إصدار أقدم، لقطة أولى لا تُستبدل بإعادة المحاولة، ملف لا يُقرأ،
// والملفات الجانبية wal/shm تُلتقط مع الأصل.
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:test/test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('diqqah_preup');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  /// قاعدة ملف كاملة المخطط (v23 بعد البناء) مغلقة — نمط حارس الترقية
  /// في database_test (تخفيض user_version يحاكي قاعدة إصدار أقدم).
  Future<String> createFullDb(String name) async {
    final path = '${tmp.path}/$name';
    final db = DiqqahDatabase(filePath: path);
    await db.customSelect('SELECT 1').get();
    await db.close();
    return path;
  }

  void setRawVersion(String path, int version) {
    final raw = sqlite3.open(path);
    try {
      raw.execute('PRAGMA user_version = $version');
    } finally {
      raw.dispose();
    }
  }

  test('قاعدة غائبة (أول تشغيل) — لا لقطة فلا شيء يُخشى عليه',
      () async {
    final path = '${tmp.path}/absent.db';
    await snapshotBeforeUpgrade(path, 23);
    expect(File('$path.preup23').existsSync(), isFalse);
  });

  test('إصدار الملف مطابق للهدف — لا ترقية ماددة فلا لقطة (لا '
      'انتفاخ يومي بالافتتاح العادي)', () async {
    final path = await createFullDb('same.db');
    await snapshotBeforeUpgrade(path, DiqqahDatabase.schemaVersionValue);
    expect(File('$path.preup23').existsSync(), isFalse);
  });

  test('إصدار أقدم من الهدف — لقطة مطابقة للبايتات قبل مساس الترحيلات',
      () async {
    final path = await createFullDb('old.db');
    setRawVersion(path, 14); // عين حالة جهاز المالك: b24 (v14) → v23

    await snapshotBeforeUpgrade(path, 23);

    final original = File(path).readAsBytesSync();
    final snapshot = File('$path.preup23').readAsBytesSync();
    expect(snapshot, equals(original));
  });

  test('إعادة المحاولة لا تستبدل اللقطة الأولى النقية أبداً — فشل '
      'التكرار على حالة نصف مُرحّلة لا يمس الأصل المحفوظ', () async {
    final path = await createFullDb('retry.db');
    setRawVersion(path, 14);
    await snapshotBeforeUpgrade(path, 23);

    // ما بعد المحاولة الأولى الفاشلة: القاعدة تغيرت واللقطة القديمة
    // موجودة — إعادة المحاولة يجب ألا تلمسها.
    File(path).writeAsBytesSync([0x00, 0x01, 0x02]);
    await snapshotBeforeUpgrade(path, 23);

    final pristine = File('$path.preup23').readAsBytesSync();
    expect(pristine, isNot(equals([0x00, 0x01, 0x02])));
    expect(pristine.length, greaterThan(1000)); // قاعدة كاملة محفوظة
  });

  test('ملف لا يُقرأ أصلاً — لقطة كما هو قبل أن يكشف الفتح السبب',
      () async {
    final path = '${tmp.path}/corrupt.db';
    final garbage = List<int>.generate(5000, (i) => (i * 37) % 256);
    File(path).writeAsBytesSync(garbage);

    await snapshotBeforeUpgrade(path, 23);

    final snapshot = File('$path.preup23').readAsBytesSync();
    expect(snapshot, equals(garbage));
  });

  test('الملفات الجانبية wal/shm تُلتقط مع الأصل — لقطة كاملة لا ناقصة',
      () async {
    final path = await createFullDb('sides.db');
    setRawVersion(path, 14);
    // جانبان وهما بجوار الأصل — يُحاكيان قاعدة أُغلقت قسرياً بلا نقطة
    // فحص (state الجهاز بعد تحديث أثناء كتابة).
    File('$path-wal').writeAsBytesSync([1, 2, 3, 4]);
    File('$path-shm').writeAsBytesSync([5, 6, 7, 8]);

    await snapshotBeforeUpgrade(path, 23);

    expect(File('$path.preup23').existsSync(), isTrue);
    expect(File('$path.preup23-wal').readAsBytesSync(), equals([1, 2, 3, 4]));
    expect(File('$path.preup23-shm').readAsBytesSync(), equals([5, 6, 7, 8]));
  });
}
