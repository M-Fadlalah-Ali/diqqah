/// مواضع صورة الصنف ونائبها البصري — دفعة (10) «الصور والباركود»
/// (س-123..س-126، D-121/D-122/D-125).
///
/// - «الصور ملفات بجوار ملف القاعدة لا مدموغة فيه» (D-125): هذه الوحدة
///   تحمل جذر المجلد وتكتب الملفين وتحذفهما — والقاعدة تحمل المسارين
///   النسبيين حصراً فتعمل بعد الاستعادة على أي جهاز.
/// - «احتواء لا قص ولا تمدد» عند العرض (D-121): مربع 1:1 والصورة فيه
///   بالاحتواء، والحشو الهادئ خلفها.
/// - النائب البصري (D-122): دائرة ملونة بأول حرف من اسم الصنف — غياب
///   الصورة حالة طبيعية جميلة لا عيب ظاهر، ولا شاشة مكشحة ولا صورة
///   مكسورة أبداً (س-125).
library;

import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:path/path.dart' as p;

/// جذر مجلد الصور الحي — تضبطه بوابة التطبيق من مسار القاعدة (الإنتاج
/// والاختبارات يضبطانه كل واحد بطريقه فلا قناة منصة في البناء).
///
/// P1-ب (س149/D-210): [cipher] مفتاح الجهاز لملفات الصور — يضبطه
/// الافتتاح بعد تحميل KEK الخزنة (SecureStorageKeyVault.forImages)
/// وبعده الترحيل الدفعي. فارغه = كتابة وقراءة خام حرفاً (الاختبارات
/// الضيقة والمسار القديم) — والإنتاج لا يضبطه فارغاً أبداً.
class ItemImagesStore {
  static String? root;

  /// مفتاح تشفير ملفات الصور على القرص (P1-ب) — null = خام (اختبارات).
  static ImageFileCipher? cipher;

  /// بديل التحميل للاختبارات — درس الجولة 128 الموثق: الإدخال/الإخراج
  /// غير المتزامن لا يكتمل بالزمن الوهمي فاختبارات الودجات تحقن محمّلاً
  /// جاهزاً، والحمل الحقيقي (قراءة + فك) مغطى بالاختبارات النقية.
  /// null = المسار الحقيقي حصراً (الإنتاج لا يضبطه أبداً).
  static Future<Uint8List?> Function(String abs)? debugImageLoader;

  /// المسار المطلق لملف من مساره النسبي المخزن — جذر غائب يعيد null
  /// فتعرض المواضع النائب البصري بلا محاولة فتح.
  static String? resolve(String? relativePath) {
    final r = root;
    if (r == null || relativePath == null || relativePath.isEmpty) {
      return null;
    }
    return p.join(r, relativePath);
  }

  /// هل يوجد ملف صورة فعلي لهذا المسار النسبي؟ — غياب الملف حالة
  /// طبيعية تُعرض بالنائب لا خطأ (س-130: نسخة بلا صور بلا بيان ناقص).
  static bool exists(String? relativePath) {
    final abs = resolve(relativePath);
    return abs != null && File(abs).existsSync();
  }
}

/// أول حرف من اسم الصنف للنائب البصري — تقليم الفراغات وأول رمز حرفي
/// (اسم فارغ = علامة استفهام فلا دائرة فارغة أبداً).
String itemAvatarLetter(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '؟';
  return trimmed.characters.first;
}

/// لوحة ألوان النائب الهادئة — توزيع ثابت بدالة تجزئة الاسم فالصنف
/// الواحد لونه نفسه في كل المواضع (تمييز بصري مستقر لا قوس قزح).
const List<Color> _avatarPalette = [
  Color(0xFF1565C0), // أزرق
  Color(0xFF2E7D32), // أخضر
  Color(0xFF6A1B9A), // بنفسجي
  Color(0xFFE65100), // برتقالي داكن
  Color(0xFF00838F), // فيروزي
  Color(0xFFAD1457), // وردي داكن
  Color(0xFF4527A0), // نيلي
  Color(0xFF9E9D24), // زيتوني
];

Color itemAvatarColor(String name) {
  final key = name.trim();
  var h = 0;
  for (final rune in key.runes) {
    h = (h * 31 + rune) & 0x7FFFFFFF;
  }
  return _avatarPalette[h % _avatarPalette.length];
}

/// موضع صورة الصنف الموحد — مربع 1:1 بالاحتواء (D-121) أو دائرة النائب
/// الملونة بأول حرف (D-122). ملف غائب أو فاسد لا يكسر شيئاً: errorBuilder
/// يعيد النائب نفسه (س-123: صورة فاسدة لا تُفسد البطاقة).
class ItemImageBox extends StatelessWidget {
  /// المسار النسبي المخزن (image_file أو image_thumb).
  final String? imagePath;

  /// بايتات جاهزة قبل الحفظ (معاينة الإدخال في البطاقة) — تتفوق على
  /// المسار إن وُجدت.
  final List<int>? pendingBytes;

  final String itemName;
  final double size;

  const ItemImageBox({
    super.key,
    this.imagePath,
    this.pendingBytes,
    required this.itemName,
    required this.size,
  });

  Widget _placeholder(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: itemAvatarColor(itemName),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          itemAvatarLetter(itemName),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pending = pendingBytes;
    if (pending != null && pending.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Image.memory(
          Uint8List.fromList(pending),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _placeholder(context),
        ),
      );
    }
    final abs = ItemImagesStore.resolve(imagePath);
    if (abs == null || !File(abs).existsSync()) {
      return _placeholder(context);
    }
    // P1-ب (س149): تمييز البطاقة حصراً قبل أي فك — ملف نص صريح يعود
    // لمسار Image.file القائم حرفاً (الاختبارات القائمة بلا مساس)،
    // والمشفر يفك بذاكرة بمفتاح الجهاز. فشل البطاقة = النائب (س-123:
    // صورة فاسدة لا تُفسد البطاقة).
    bool encrypted;
    try {
      final raf = File(abs).openSync();
      try {
        final head = raf.readSync(ImageFileCipher.magic.length);
        encrypted = head.length == ImageFileCipher.magic.length &&
            ImageFileCipher.isEncryptedImage(head);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return _placeholder(context);
    }
    if (encrypted) {
      return _EncryptedImage(
        abs: abs,
        size: size,
        placeholder: _placeholder,
      );
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Image.file(
        File(abs),
        // D-121: احتواء لا قص ولا تمدد — والمصدر مربع أصلاً فلا فائض.
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(context),
      ),
    );
  }
}

/// عرض ملف صورة مشفر (P1-ب): فك بالذاكرة بمفتاح الجهاز ثم Image.memory.
/// فشل الفك (KEC يخالف/ملف تالف) أو غياب المفتاح = النائب حصراً —
/// لا كراش ولا صورة مكسورة أبداً (عرف س-123).
class _EncryptedImage extends StatefulWidget {
  final String abs;
  final double size;
  final Widget Function(BuildContext) placeholder;

  const _EncryptedImage({
    required this.abs,
    required this.size,
    required this.placeholder,
  });

  @override
  State<_EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<_EncryptedImage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_EncryptedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.abs != widget.abs) {
      _future = _load();
    }
  }

  Future<Uint8List?> _load() async {
    final loader = ItemImagesStore.debugImageLoader;
    if (loader != null) return loader(widget.abs); // حقن الاختبار حصراً.
    final cipher = ItemImagesStore.cipher;
    if (cipher == null) return null; // مفتاح غائب — النائب لا تخمين.
    final raw = await File(widget.abs).readAsBytes();
    if (!ImageFileCipher.isEncryptedImage(raw)) return Uint8List.fromList(raw);
    final plain = await cipher.decrypt(raw);
    return Uint8List.fromList(plain);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done ||
              !snap.hasData ||
              snap.data == null) {
            return widget.placeholder(context);
          }
          return Image.memory(
            snap.data!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => widget.placeholder(context),
          );
        },
      ),
    );
  }
}

/// س-123/D-125: كتابة ملفَي الصورة (الأصل والمشتق بجوار بعضهما —
/// س-123) في مجلد الصور بجوار القاعدة، وتعيد المسارين النسبيين
/// المخزنين على الصف. جذر غائب (بضاعة التهيئة) يرفض برسالة عربية —
/// لا كتابة صامتة في مكان مجهول.
///
/// P1-ب (س149): المفتاح مضبوط = الكتابة مشفرة بمفتاح الجهاز حصراً
/// فالعالم على القرص لا يرى نص الصور الصريح؛ فارغه = كتابة خام
/// حرفاً (الاختبارات الضيقة) — والإنتاج لا يتركه فارغاً.
Future<(String, String)> writeItemImagesFiles({
  required int itemId,
  required List<int> original,
  required List<int> thumb,
}) async {
  final root = ItemImagesStore.root;
  if (root == null || root.isEmpty) {
    throw const ItemImagesPathException(
        'مجلد الصور غير مهيأ — أعد فتح التطبيق ثم أعد المحاولة');
  }
  final cipher = ItemImagesStore.cipher;
  final originalRel = itemImageRelativeName(itemId, thumb: false);
  final thumbRel = itemImageRelativeName(itemId, thumb: true);
  final originalFile = File(p.join(root, originalRel));
  await originalFile.create(recursive: true);
  await originalFile
      .writeAsBytes(cipher == null ? original : await cipher.encrypt(original),
          flush: true);
  final thumbFile = File(p.join(root, thumbRel));
  await thumbFile.create(recursive: true);
  await thumbFile
      .writeAsBytes(cipher == null ? thumb : await cipher.encrypt(thumb),
          flush: true);
  return (originalRel, thumbRel);
}

/// س-124: مسح الملفين القديمين عند الحذف أو الاستبدال — أفضل جهد
/// بلا انهيار على ملف غائب (الحالة الطبيعية أولاً).
Future<void> deleteItemImagesFiles(String? imageFile, String? imageThumb) async {
  final root = ItemImagesStore.root;
  if (root == null || root.isEmpty) return;
  for (final rel in [imageFile, imageThumb]) {
    final abs = ItemImagesStore.resolve(rel);
    if (abs == null) continue;
    final f = File(abs);
    if (f.existsSync()) {
      try {
        await f.delete();
      } catch (_) {
        // ملف محجوز بعملية أخرى — لا يكسر الحفظ ولا يترك الحقل خاطئاً.
      }
    }
  }
}

/// يُرمى حين يغيب جذر مجلد الصور — رسالة عربية واحدة.
class ItemImagesPathException implements Exception {
  final String message;
  const ItemImagesPathException(this.message);

  @override
  String toString() => message;
}
