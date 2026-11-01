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
class ItemImagesStore {
  static String? root;

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

/// س-123/D-125: كتابة ملفَي الصورة (الأصل والمشتق بجوار بعضهما —
/// س-123) في مجلد الصور بجوار القاعدة، وتعيد المسارين النسبيين
/// المخزنين على الصف. جذر غائب (بضاعة التهيئة) يرفض برسالة عربية —
/// لا كتابة صامتة في مكان مجهول.
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
  final originalRel = itemImageRelativeName(itemId, thumb: false);
  final thumbRel = itemImageRelativeName(itemId, thumb: true);
  final originalFile = File(p.join(root, originalRel));
  await originalFile.create(recursive: true);
  await originalFile.writeAsBytes(original, flush: true);
  final thumbFile = File(p.join(root, thumbRel));
  await thumbFile.create(recursive: true);
  await thumbFile.writeAsBytes(thumb, flush: true);
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
