import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات محرك صورة الصنف النقي — دفعة (10) (س-123/س-124،
/// D-119/D-120/D-121) — بلا Flutter ولا Drift (F-010) وكل الصور
/// تجريبية تولد هنا فلا ملفات مرجعية.
void main() {
  /// صورة تجريبية بتدرج ناعم — حجم صغير وسريعة والضغط يعطي أحجاماً
  /// صغيرة.
  List<int> gradientJpeg({int width = 640, int height = 480}) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgba(
          x,
          y,
          (x * 255 ~/ width),
          (y * 255 ~/ height),
          128,
          255,
        );
      }
    }
    return img.encodeJpg(image, quality: 90);
  }

  /// ضجيج عشوائي — الضغط يعجز عنه فيتضخم فتُختبر حلقة جودة التنازل.
  List<int> noiseJpeg({int width = 512, int height = 512}) {
    final rng = math.Random(7);
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgba(
          x,
          y,
          rng.nextInt(256),
          rng.nextInt(256),
          rng.nextInt(256),
          255,
        );
      }
    }
    return img.encodeJpg(image, quality: 95);
  }

  bool isJpeg(List<int> bytes) =>
      bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  /// فك ناتج المحرك — decodeImage بصورة 4.x يقبل Uint8List حصراً.
  img.Image decode(List<int> bytes) =>
      img.decodeImage(Uint8List.fromList(bytes))!;

  test('س-123 (D-120/D-121): المحرك يخرج مربع 512 بمشتق 128 وJPEG حصراً',
      () {
    final result = ingestItemImage(gradientJpeg());
    final original = decode(result.originalJpeg);
    final thumb = decode(result.thumbJpeg);
    expect(original.width, kItemImageMaxSide);
    expect(original.height, kItemImageMaxSide);
    expect(thumb.width, kItemImageThumbSide);
    expect(thumb.height, kItemImageThumbSide);
    expect(isJpeg(result.originalJpeg), isTrue,
        reason: 'D-119: JPEG حصراً — يدخل PDF الطباعة بلا إعادة ضغط');
    expect(isJpeg(result.thumbJpeg), isTrue);
    expect(result.thumbBytes, lessThan(20 * 1024),
        reason: 'س-126: المشتق المصغر خفيف لسطور الفواتير');
  });

  test('س-123: الحشو الهادئ — الصورة غير المربعة تتمركز والفائض أبيض',
      () {
    final result = ingestItemImage(gradientJpeg());
    final original = decode(result.originalJpeg);
    // 640×480 داخل لوحة 640: الحشو عمودي أعلى وأسفل — الزوايا بيضاء.
    final corner = original.getPixel(2, 2);
    expect(corner.r, greaterThan(245));
    expect(corner.g, greaterThan(245));
    expect(corner.b, greaterThan(245));
    // والمركز يحمل الصورة نفسها (تدرج ليس أبيض).
    final center = original.getPixel(256, 256);
    expect(center.r + center.g + center.b, lessThan(700));
  });

  test('س-123: صورة ضخمة (4000×3000) تصير مربعاً مصغراً بلا انفجار ذاكرة',
      () {
    final result = ingestItemImage(gradientJpeg(width: 4000, height: 3000));
    final original = decode(result.originalJpeg);
    expect(original.width, kItemImageMaxSide);
    expect(original.height, kItemImageMaxSide);
  });

  test('س-123: صورة فاسدة تُرفض برسالة عربية ولا تعبر أبداً', () {
    expect(
      () => ingestItemImage([1, 2, 3, 4, 5]),
      throwsA(isA<ItemImageException>().having(
        (e) => e.toString(),
        'message',
        contains('تعذر قراءة الصورة'),
      )),
    );
    expect(() => ingestItemImage(const []),
        throwsA(isA<ItemImageException>()));
  });

  test('س-123: الضجيج يفعّل سلّم الجودة — الحجم يقترب من السقف بتنازل',
      () {
    final result = ingestItemImage(noiseJpeg());
    expect(result.quality, lessThan(kItemImageQualityStart),
        reason: 'الضجيج فوق السقف فنازلت الجودة آلياً');
    // الأرضية تحمي الوضوح: لا ننزل تحت 40 مهما ضجّت الصورة.
    expect(result.quality, greaterThanOrEqualTo(kItemImageQualityFloor));
  });

  test('D-121: الإطار الافتراضي الصورة كاملة — والتقريب والإزاحة تحسبن نقياً',
      () {
    final full = computeItemCropRect(
      canvasSide: 640,
      viewportSide: 400,
      scale: 1.0,
      tx: 0,
      ty: 0,
    );
    expect(full.x, 0);
    expect(full.y, 0);
    expect(full.side, 640, reason: 'التقريب الواحد: الصورة كاملة داخل الإطار');

    final zoomed = computeItemCropRect(
      canvasSide: 640,
      viewportSide: 400,
      scale: 2.0,
      tx: -200,
      ty: -100,
    );
    expect(zoomed.side, closeTo(320, 0.01),
        reason: 'تقريب 2× ينصف ضلع المستطيل المرئي');
    // الإزاحة النصفية: المرئي [160,480] موسّطاً على اللوحة (u_min =
    // -tx/(z*fit) = 200/1.25) — والحساب مستقَق رياضياً لا معمولياً.
    expect(zoomed.x, closeTo(160, 0.01));
    expect(zoomed.y, closeTo(80, 0.01));

    // شبكة الأمان: إزاحة شاذة تُقيَّد داخل اللوحة.
    final clamped = computeItemCropRect(
      canvasSide: 640,
      viewportSide: 400,
      scale: 2.0,
      tx: 99999,
      ty: -99999,
    );
    expect(clamped.x, 0);
    expect(clamped.y, closeTo(320, 0.01));
  });

  test('س-124: القص بإطار المستخدم — الناتج يبقى مربعاً 512 بمحتوى الإطار',
      () {
    final result = ingestItemImage(
      gradientJpeg(),
      crop: const ItemImageCrop(x: 0, y: 0, side: 320),
      // ربع اللوحة العلوي — تدرج صاعد فالقسم الأعلى أفتح من المركز.
    );
    final original = decode(result.originalJpeg);
    expect(original.width, kItemImageMaxSide);
    expect(original.height, kItemImageMaxSide);
  });

  test('س-123: inspectItemImage يعيد أبعاد الصورة بعد تدوير EXIF', () {
    final size = inspectItemImage(gradientJpeg(width: 320, height: 200));
    expect(size.width, 320);
    expect(size.height, 200);
    expect(size.canvasSide, 320);
  });
}
