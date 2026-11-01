/// محرك صورة الصنف النقي — دفعة (10) «الصور والباركود» (س-123..س-124،
/// D-119/D-120/D-121/D-125).
///
/// الفصل المعماري F-010 نفسه: هذه الحزمة بلا Flutter ولا Drift، فمحرك
/// الإدخال الإلزامي يعيش هنا نقياً مختبراً بـ dart test، وحزمة الضغط
/// `image` نقية حصراً (D-125: «flutter_image_compress أو image — يُحسم
/// بالتجربة وقت التنفيذ» — الحسم: `image` لأنflutter_image_compress لا
/// يدعم Windows ولا يجري تحت F-010، و`image` نقية تعمل على المنصتين
/// وفي الاختبارات النقية بلا أي قناة منصة).
///
/// العقد الإلزامي (D-120): لا صورة تدخل التطبيق إلا عبر هذا المحرك —
/// تدوير EXIF ← إطار قص مربع (افتراضه الصورة كاملة داخله والتقريب
/// والإزاحة بيد المستخدم — D-121) ← تصغير لأقصى ضلع 512 نقطة ← ضغط
/// JPEG بجودة متوازنة (الهدف 30..60 كيلوبايت) ← حفظ «الأصل» + توليد
/// «المشتق المصغر» (~128 نقطة) لحظة الإدخال — تلقائي حصراً بلا خيار
/// يسكته المستخدم.
///
/// والمرسوم لا يُلتقط (D-119): لا SVG للصور الملتقطة، وJPEG حصراً
/// للناتج توافقاً مع PDF الطباعة بلا إعادة ضغط.
library;

import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:image/image.dart' as img;

/// أقصى ضلع للأصل المحفوظ (D-120).
const int kItemImageMaxSide = 512;

/// ضلع المشتق المصغر لسطور الفواتير (س-126).
const int kItemImageThumbSide = 128;

/// سقف التصغير المسبق قبل بناء اللوحة المربعة — ضبط الذاكرة: صورة
/// 4000×3000 من كاميرا الجوال تُصغَّر أولاً فلا تُبنى لوحة 4000² في
/// الذاكرة، والخسارة لا تُرى لأن الناتج النهائي 512 (والتقريب حتى 3×
/// يبقى فوق 340 نقطة مصدرية).
const int kItemImagePreScaleCap = 1024;

/// سقف حجم الأصل المستهدف بالبايت (س-123: الهدف 30..60 كيلوبايت).
const int kItemImageMaxBytes = 60 * 1024;

/// جودة JPEG الابتدائية وسلّم التنازل حتى الأرضية — الهدف توازن الحجم
/// والوضوح لا صرامة مطلقة: ما فاق السقف عند الأرضية يُقبل كما هو.
const int kItemImageQualityStart = 82;
const int kItemImageQualityStep = 12;
const int kItemImageQualityFloor = 40;

/// جودة المشتق المصغر — ثابتة فصغره مضمون البنية (~3..10 كيلوبايت).
const int kItemImageThumbQuality = 78;

/// لون الحشو الهادئ لمربعات الأصناف غير الممتلئة (س-123: حشو لون موحد
/// بدل عزل الخلفية الآلي المؤجل بقائمة الانتظار).
const List<int> kItemImagePaddingRgb = [255, 255, 255];

/// يُرمى عند فشل المحرك — رسالة عربية جاهزة للعرض لا يصوغها المستخدم.
class ItemImageException implements Exception {
  final String message;
  const ItemImageException(this.message);

  @override
  String toString() => message;
}

/// مستطيل القص المربع بإحداثيات «اللوحة المربعة» للصورة — لوحتها
/// مربع ضلعه أكبر بعدَي الصورة، والصورة كاملة بداخله موسّطة والحشو
/// الهادئ يملأ الفائض. الإفتراضي: الصورة كاملة (x=0, y=0, side=اللوحة).
class ItemImageCrop {
  final double x;
  final double y;
  final double side;

  const ItemImageCrop({
    required this.x,
    required this.y,
    required this.side,
  });
}

/// أبعاد الصورة بعد تدوير EXIF — لعرضها بإطار المعاينة المربع.
class ItemImageSize {
  final int width;
  final int height;

  const ItemImageSize({required this.width, required this.height});

  /// ضلع اللوحة المربعة التي تحوي الصورة كاملة (D-121).
  int get canvasSide => math.max(width, height);
}

/// قراءة أبعاد صورة خام بعد تدوير EXIF — لموضعها في إطار المعاينة.
/// صورة فاسدة تُرفض هنا قبل أي شاشة (س-123: صورة فاسدة تُرفض ولا
/// تُفسد البطاقة).
ItemImageSize inspectItemImage(List<int> raw) {
  final decoded = _decodeOrThrow(raw);
  return ItemImageSize(width: decoded.width, height: decoded.height);
}

/// يحسب مستطيل القص من حالة إطار المعاينة التفاعلي — دالة نقية
/// مختبرة بلا Flutter (إطار المعاينة مربع، واللوحة المربعة تُعرض به
/// بحشو «احتواء» فالطفح صفر عند التقريب الواحد).
///
/// [canvasSide] ضلع اللوحة (أكبر بعدَي الصورة)، [viewportSide] ضلع
/// الإطار المربع المعروض، [scale] تقريب المشاهد (1 = الصورة كاملة)،
/// و[tx]/[ty] إزاحة المشاهد بالنقاط المنطقية (سالبٌ يساراً/أعلاه).
ItemImageCrop computeItemCropRect({
  required int canvasSide,
  required double viewportSide,
  required double scale,
  required double tx,
  required double ty,
}) {
  if (canvasSide <= 0 || viewportSide <= 0 || scale <= 0) {
    throw const ItemImageException('قياسات إطار القص غير سليمة');
  }
  final fit = viewportSide / canvasSide;
  final z = scale < 1 ? 1.0 : scale;
  final visibleSide = viewportSide / (z * fit);
  final x = -tx / (z * fit);
  final y = -ty / (z * fit);
  // شبكة أمان إضافية: المستطيل داخل اللوحة دائماً حتى لو أُطيق
  // التحويل خارج حواف المشاهد.
  final maxX = (canvasSide - visibleSide).clamp(0.0, canvasSide.toDouble());
  final maxY = (canvasSide - visibleSide).clamp(0.0, canvasSide.toDouble());
  return ItemImageCrop(
    x: x.clamp(0.0, maxX),
    y: y.clamp(0.0, maxY),
    side: visibleSide.clamp(1.0, canvasSide.toDouble()),
  );
}

/// ناتج المحرك — الأصل والمشتق المصغر جاهزان للكتابة بجوار بعضهما
/// (س-123: أصل + مشتق بجوار بعضهما).
class ItemImageIngestResult {
  final List<int> originalJpeg;
  final List<int> thumbJpeg;
  final int quality;

  const ItemImageIngestResult({
    required this.originalJpeg,
    required this.thumbJpeg,
    required this.quality,
  });

  int get originalBytes => originalJpeg.length;

  int get thumbBytes => thumbJpeg.length;
}

/// المحرك الإلزامي (D-120): فك ← تدوير EXIF ← قص الإطار (أو الصورة
/// كاملة) ← لوحة مربعة بحشو هادئ ← 512 ← JPEG متوازن ≤60KB ← مشتق
/// 128. توقيع واحد بلا أي خيار يسكته المستخدم.
ItemImageIngestResult ingestItemImage(
  List<int> raw, {
  ItemImageCrop? crop,
}) {
  final decoded = _decodeOrThrow(raw);
  final image = img.bakeOrientation(decoded);

  final originalCanvasSide = math.max(image.width, image.height);
  // القص بإحداثيات اللوحة الأصلية إن زوّد المستخدم إطاره — والإفتراضي
  // الصورة كاملة داخل لوحتها (D-121).
  final effective = crop ??
      ItemImageCrop(
        x: 0,
        y: 0,
        side: originalCanvasSide.toDouble(),
      );
  if (effective.side <= 0 ||
      effective.x < -1 ||
      effective.y < -1 ||
      effective.x + effective.side > originalCanvasSide + 1) {
    throw const ItemImageException('إطار القص خارج حدود الصورة');
  }

  // تصغير مسبق للوحات الضخمة — ضبط الذاكرة لا الأداء المحاسبي.
  var work = image;
  if (originalCanvasSide > kItemImagePreScaleCap) {
    final k = kItemImagePreScaleCap / originalCanvasSide;
    work = img.copyResize(
      image,
      width: (image.width * k).round().clamp(1, kItemImagePreScaleCap),
      height: (image.height * k).round().clamp(1, kItemImagePreScaleCap),
      interpolation: img.Interpolation.cubic,
    );
  }
  final scaledCanvasSide = math.max(work.width, work.height);
  final kScaled = scaledCanvasSide / originalCanvasSide;

  // اللوحة المربعة بالحشو الهادئ ثم القص منها — الفائض موسّط.
  final square = img.Image(
      width: scaledCanvasSide, height: scaledCanvasSide);
  img.fill(
    square,
    color: img.ColorRgb8(
      kItemImagePaddingRgb[0],
      kItemImagePaddingRgb[1],
      kItemImagePaddingRgb[2],
    ),
  );
  img.compositeImage(
    square,
    work,
    dstX: (scaledCanvasSide - work.width) ~/ 2,
    dstY: (scaledCanvasSide - work.height) ~/ 2,
  );

  var cx = (effective.x * kScaled).round().clamp(0, scaledCanvasSide - 1);
  var cy = (effective.y * kScaled).round().clamp(0, scaledCanvasSide - 1);
  var cs = (effective.side * kScaled).round().clamp(
        1,
        scaledCanvasSide - math.min(cx, cy),
      );

  final cropped = img.copyCrop(
    square,
    x: cx,
    y: cy,
    width: cs,
    height: cs,
  );

  final original = img.copyResize(
    cropped,
    width: kItemImageMaxSide,
    height: kItemImageMaxSide,
    interpolation: img.Interpolation.cubic,
  );

  var quality = kItemImageQualityStart;
  var originalBytes = img.encodeJpg(original, quality: quality);
  while (originalBytes.length > kItemImageMaxBytes &&
      quality - kItemImageQualityStep >= kItemImageQualityFloor) {
    quality -= kItemImageQualityStep;
    originalBytes = img.encodeJpg(original, quality: quality);
  }

  final thumb = img.copyResize(
    original,
    width: kItemImageThumbSide,
    height: kItemImageThumbSide,
    interpolation: img.Interpolation.cubic,
  );
  final thumbBytes = img.encodeJpg(
    thumb,
    quality: kItemImageThumbQuality,
  );

  return ItemImageIngestResult(
    originalJpeg: originalBytes,
    thumbJpeg: thumbBytes,
    quality: quality,
  );
}

/// فك الصورة أو رفضها برسالة عربية واحدة — صورة فاسدة لا تعبر أبداً
/// (س-123) ولا يصل الفساد إلى ملفات القاعدة.
img.Image _decodeOrThrow(List<int> raw) {
  if (raw.isEmpty) {
    throw const ItemImageException('الملف فارغ — لا صورة فيه');
  }
  try {
    final decoded = img.decodeImage(Uint8List.fromList(raw));
    if (decoded != null && decoded.width > 0 && decoded.height > 0) {
      return decoded;
    }
  } catch (_) {
    // يُوحَّد القول في كل صورة فاسدة بالرسالة نفسها (س-123).
  }
  throw const ItemImageException(
      'تعذر قراءة الصورة — الملف تالف أو بصيغة غير مدعومة');
}
