/// اختبارات P1-أ/P1-ب (س149/D-210) بطبقة الواجهة: أسرار قفل النسخ
/// بالخزنة القابلة للحقن، وكتابة الصور المشفرة، وعرض الملف المشفر.
/// الخزنة المنصوية لا تدخل الاختبارات — صندوق ذاكرة عرف الحقن.
library;

import 'dart:convert' show base64Decode;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_domain/diqqah_domain.dart' show BackupLock;
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_app/db_key_vault.dart';
import 'package:diqqah_app/item_images.dart';

/// صندوق أسرار بذاكرة — عرف الحقن، بلا قناة منصة.
class MemorySecretsBox implements SecureSecretsBox {
  final Map<String, String> store = {};
  @override
  Future<String?> read(String key) async => store[key];
  @override
  Future<void> write(String key, String value) async => store[key] = value;
  @override
  Future<void> delete(String key) async => store.remove(key);
}

Uint8List kekOf(String seed) {
  final bytes = Uint8List.fromList(seed.codeUnits);
  final out = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    out[i] = bytes[i % bytes.length];
  }
  return out;
}

/// أصغر JPEG صالح (1×1) — حقن موحد (نمط batch10).
const jpeg1x1Base64 =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkS'
    'Ew8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJ'
    'CQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
    'MjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEA'
    'AAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIh'
    'MUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6'
    'Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZ'
    'mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx'
    '8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
    'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAV'
    'YnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hp'
    'anN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPE'
    'xcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3'
    '+iiigD//2Q==';

/// JPEG مشفر مسبقاً — يُحسب مرة بreal zone قبل الاختبارات كي لا
/// يعتمد الودجت على تشفير غير متزامن تحت الزمن الوهمي (درس الجولة 128).
Uint8List? encJpegMain;

Future<void> main() async {
  encJpegMain = Uint8List.fromList(await ImageFileCipher(kekOf('جهاز-الاختبار'))
      .encrypt(base64Decode(jpeg1x1Base64)));
  setUp(() {
    ItemImagesStore.root = null;
    ItemImagesStore.cipher = null;
  });

  tearDown(() {
    ItemImagesStore.root = null;
    ItemImagesStore.cipher = null;
  });

  group('P1-أ: أسرار قفل النسخ — BackupSecretsStore بصندوق حقن', () {
    test('الفراغ = بلا قفل، والحفظ يعود كاملاً، والإزالة تمحي', () async {
      final box = MemorySecretsBox();
      final store = BackupSecretsStore(box: box);
      expect(await store.loadLock(), isNull);

      const lock = BackupLock(
          password: 'كلمة-المالك', recoveryCode: 'ABCD-EFGH-JK2M-NP4Q');
      await store.saveLock(lock);
      final back = await store.loadLock();
      expect(back, isNotNull);
      expect(back!.password, lock.password);
      expect(back.recoveryCode, lock.recoveryCode);

      await store.clearLock();
      expect(await store.loadLock(), isNull);
    });

    test('القفل النصفي لا يقبل — نقص أحد السرّين = بلا قفل', () async {
      final box = MemorySecretsBox();
      final store = BackupSecretsStore(box: box);
      await box.write('diqqah.backup.pass.v1', 'كلمة-وحدها');
      expect(await store.loadLock(), isNull,
          reason: 'سر واحد بلا رفيقه = بلا قفل فلا نسخة v3 بمادة واحدة');
      await box.write('diqqah.backup.pass.v1', '');
      expect(await store.loadLock(), isNull);
    });
  });

  group('P1-ب: كتابة الصور المشفرة وعرضها', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('diqqah_p1_app_');
      ItemImagesStore.root = root.path;
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('المفتاح مضبوط: الكتابة مشفرة على القرص والفك يعيد الأصل',
        () async {
      final cipher = ImageFileCipher(kekOf('جهاز-الاختبار'));
      ItemImagesStore.cipher = cipher;
      final jpeg = base64Decode(jpeg1x1Base64);
      final (rel, thumbRel) = await writeItemImagesFiles(
          itemId: 7, original: jpeg, thumb: jpeg);

      final onDisk = await File(
              '${root.path}${Platform.pathSeparator}$rel')
          .readAsBytes();
      expect(ImageFileCipher.isEncryptedImage(onDisk), isTrue,
          reason: 'العالم على القرص لا يرى نص الصور الصريح');
      expect(await cipher.decrypt(onDisk), equals(jpeg));
      final thumbOnDisk = await File(
              '${root.path}${Platform.pathSeparator}$thumbRel')
          .readAsBytes();
      expect(await cipher.decrypt(thumbOnDisk), equals(jpeg));
    });

    test('المفتاح فارغ (اختبارات ضيقة): الكتابة خام حرفاً — التوافق القائم',
        () async {
      final jpeg = base64Decode(jpeg1x1Base64);
      final (rel, _) =
          await writeItemImagesFiles(itemId: 8, original: jpeg, thumb: jpeg);
      final onDisk = await File(
              '${root.path}${Platform.pathSeparator}$rel')
          .readAsBytes();
      expect(ImageFileCipher.isEncryptedImage(onDisk), isFalse);
      expect(onDisk, equals(jpeg));
    });

    testWidgets('الملف المشفر يُعرض بعد الفك — ومفتاح غريب يعيد النائب',
        (tester) async {
      // الملف على القرص مشفر فعلاً (مكتب ببايتات مُشفَّرة مسبقاً —
      // IO متزامن حصراً هنا، درس الجولة 128) وحقن المحمّل يقدّم ناتج
      // الفك — والحمل الحقيقي (قراءة + فك) مغطى بالاختبارات النقية.
      final cipher = ImageFileCipher(kekOf('جهاز-الاختبار'));
      final jpeg = base64Decode(jpeg1x1Base64);
      final enc = encJpegMain ?? await cipher.encrypt(jpeg);
      final dir = Directory(
          '${ItemImagesStore.root}${Platform.pathSeparator}images');
      dir.createSync(recursive: true);
      final rel = 'images/item-9.jpg';
      File('${dir.path}${Platform.pathSeparator}item-9.jpg')
          .writeAsBytesSync(enc);
      expect(
          ImageFileCipher.isEncryptedImage(
              File('${dir.path}${Platform.pathSeparator}item-9.jpg')
                  .readAsBytesSync()),
          isTrue);

      // فك سليم: الصورة تُعرض (لا حرف نائب).
      ItemImagesStore.debugImageLoader = (abs) async => jpeg;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ItemImageBox(
                itemName: 'زيت محلي', size: 48, imagePath: rel),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ز'), findsNothing,
          reason: 'فك سليم = صورة حقيقية لا النائب');
      expect(find.byType(Image), findsOneWidget);

      // فك فاشل (مفتاح جهاز آخر): النائب يظهر — لا كراش ولا صورة مكسورة.
      ItemImagesStore.debugImageLoader = (abs) async => null;
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: Center(
            child: ItemImageBox(
                itemName: 'زيت محلي', size: 48, imagePath: rel),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ز'), findsOneWidget,
          reason: 'مفتاح غريب = النائب حصراً (عرف س-123)');
      expect(find.byType(Image), findsNothing);
    });
  });
}
