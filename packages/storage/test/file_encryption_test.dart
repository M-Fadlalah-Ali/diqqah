import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات تشفير الملفات المصاحبة — P1-ب (س149/D-210): نمط DEK/KEK
/// والKEK بخزنة الجهاز (هنا مفتاح اختباري ثابت بلا خزنة منصة — عرف
/// FixedKeyVault نفسه في P0).
void main() {
  // KEK اختباري ثابت — الرياضيات واحدة والخزنة المنصوية لا تدخل.
  Uint8List kek(String seed) {
    final bytes = Uint8List.fromList(seed.codeUnits);
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = bytes[i % bytes.length];
    }
    return out;
  }

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diqqah_imgenc_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('P1-ب: دورة كاملة — تشفير بمفتاح الجهاز ثم فك يعيد الأصل', () async {
    final cipher = ImageFileCipher(kek('جهاز-الإنتاج'));
    final plain = List<int>.generate(4096, (i) => i & 0xFF);
    final enc = await cipher.encrypt(plain);
    // البطاقة أول ما يُعرف — لا ترويسة صور خام بعد التشفير.
    expect(ImageFileCipher.isEncryptedImage(enc), isTrue);
    final back = await cipher.decrypt(enc);
    expect(back, equals(plain));
  });

  test('P1-ب: نسختان لنفس الصورة تختلفان — DEK وملح ونونس عشوائيان', () async {
    final cipher = ImageFileCipher(kek('جهاز-الإنتاج'));
    final plain = List<int>.filled(1024, 7);
    final a = await cipher.encrypt(plain);
    final b = await cipher.encrypt(plain);
    expect(a, isNot(equals(b)));
    expect(await cipher.decrypt(a), equals(plain));
    expect(await cipher.decrypt(b), equals(plain));
  });

  test('P1-ب: KEK غريب يرفض قبل أي استعمال — وسم غلاف DEK حاكم', () async {
    final device = ImageFileCipher(kek('جهاز-الإنتاج'));
    final stranger = ImageFileCipher(kek('جهاز-آخر'));
    final enc = await device.encrypt(List<int>.filled(512, 9));
    expect(
      () => stranger.decrypt(enc),
      throwsA(isA<ImageCipherException>().having(
          (e) => e.toString(), 'msg', contains('لا يفك'))),
    );
  });

  test('P1-ب: بنية مقطوعة أو غريبة — رفض واحد لا صمت', () async {
    final cipher = ImageFileCipher(kek('جهاز'));
    final enc = await cipher.encrypt(List<int>.filled(256, 1));
    expect(() => cipher.decrypt(enc.sublist(0, 20)),
        throwsA(isA<ImageCipherException>()));
    final tampered = List<int>.of(enc);
    tampered[tampered.length - 5] ^= 0xFF; // وسم البيانات
    expect(() => cipher.decrypt(tampered),
        throwsA(isA<ImageCipherException>()));
    expect(ImageFileCipher.isEncryptedImage(Uint8List.fromList([0xFF, 0xD8])),
        isFalse); // JPEG خام لا بطاقة البرنامج
  });

  test('P1-ب: الترحيل عند الافتتاح — النص الصريح يُشفَّر ذرياً والمشفر يُترك',
      () async {
    final cipher = ImageFileCipher(kek('جهاز-الإنتاج'));
    final dir = Directory(p.join(tempDir.path, 'images'));
    await dir.create(recursive: true);
    final plain1 = List<int>.generate(300, (i) => i % 251);
    final plain2 = List<int>.generate(300, (i) => (i * 7) % 251);
    await File(p.join(dir.path, 'images', 'item-1.jpg'))
        .create(recursive: true);
    await File(p.join(dir.path, 'images', 'item-1.jpg'))
        .writeAsBytes(plain1);
    await File(p.join(dir.path, 'images', 'item-1-thumb.jpg'))
        .writeAsBytes(plain2);
    // ملف مشفر سلفاً — تكرار آمن لا يُمس.
    final already = await cipher.encrypt(plain1);
    await File(p.join(dir.path, 'images', 'item-2.jpg'))
        .writeAsBytes(already);
    // فارغ — يُترك لحارس الجمع كما هو.
    await File(p.join(dir.path, 'images', 'item-3.jpg')).writeAsBytes(const []);

    final first = await migratePlainImagesToEncrypted(dir, cipher);
    expect(first.$1, 2); // الاثنان النص الصريح فقط
    expect(first.$2, 0);

    // كل الملفات الآن مشفرة والنص يفك للأصل — والمشفر السابق لم يُمس.
    expect(
        await cipher
            .decrypt(await File(p.join(dir.path, 'images', 'item-1.jpg'))
                .readAsBytes()),
        equals(plain1));
    expect(
        await cipher
            .decrypt(await File(p.join(dir.path, 'images', 'item-1-thumb.jpg'))
                .readAsBytes()),
        equals(plain2));
    expect(
        ImageFileCipher.isEncryptedImage(
            await File(p.join(dir.path, 'images', 'item-2.jpg'))
                .readAsBytes()),
        isTrue);

    // التكرار: لا شيء يُرحَّل ثانية.
    final second = await migratePlainImagesToEncrypted(dir, cipher);
    expect(second.$1, 0);
    expect(second.$2, 0);

    // لا مخلفات مؤقتة.
    expect(
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.enc-tmp'))
            .length,
        0);
  });

  test('P1-ب: مجلد غائب صمتاً — والكيانات غير الملفية لا تدخل الترحيل',
      () async {
    final cipher = ImageFileCipher(kek('جهاز'));
    // مجلد غائب: صفر صفر — لا خطأ.
    final none = await migratePlainImagesToEncrypted(
        Directory(p.join(tempDir.path, 'لا-يوجد')), cipher);
    expect(none, (0, 0));

    // كيان يحمل اسم ملف وهو مجلد — لا ملف فلا يُفتح ولا يُعدّ فاشلاً
    // (whereType<File> حارس الدخول)، ويبقى بنيته كما وُلد.
    final dir = Directory(p.join(tempDir.path, 'images'));
    await dir.create(recursive: true);
    final blockedDir = Directory(p.join(dir.path, 'blocked.jpg'));
    await blockedDir.create();
    final plain = List<int>.generate(100, (i) => i);
    await File(p.join(dir.path, 'open.jpg')).writeAsBytes(plain);
    final (migrated, failed) =
        await migratePlainImagesToEncrypted(dir, cipher);
    expect(migrated, 1);
    expect(failed, 0);
    expect(blockedDir.existsSync(), isTrue);
    // الفرع الفاشل (فشل قراءة/حجز ملف وسط الترحيل) دفاعي بأقصى جهد
    // موثق — الملف يبقى نص صريح سليماً وتُعاد محاولته في الافتتاح التالي.
  });
}
