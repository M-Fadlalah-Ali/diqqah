/// وسائط الصنف: الالتقاط والاختيار والمسح — دفعة (10) «الصور والباركود»
/// (س-123/س-124/س-132، D-125).
///
/// الحزم الخارجية الثلاث بإذن البوابة (D-125):
/// - image_picker — الالتقاط بالكاميرا والاختيار من المعرض.
/// - mobile_scanner — المسح بكاميرا الجوال (أندرويد حصراً عملياً؛
///   ويندوز يكتب الرمز بلوحة المفاتيح أو قارئ بلوتوث فهو مسار س-132
///   الأول بلا كاميرا أصلاً).
/// - والضغط في حزمة المجال النقية (`image`) — لا قنوات منصة في المحرك
///   (F-010) ولا حزمة ضغط ثالثة في الواجهة.
///
/// الفواصل الاختبارية: الاختبارات تمرر دوالها البديلة عبر معاملات
/// الشاشات فلا قناة منصة تُلمس (عرف الشاشات — نمط حقن الاختبارات).
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// هل تدعم المنصة الالتقاط بالكاميرا والمسح؟ — أندرويد وحده في هذه
/// المرحلة: ويندوز كاميرا image_picker غير مدعومة فيها (الاختيار من
/// المعرض يعمل على المنصتين)، والمسح بكاميرا الجوال هو السيناريو
/// المعتمد (س-132) وقارئ البلوتوث يغني عنه على المكتب.
bool get supportsCameraScan => Platform.isAndroid;

/// التقاط بالكاميرا أو اختيار من المعرض — يعيد بايتات الصورة الخام
/// أو null عند الإلغاء. الفشل يرمي برسالته فتُعرض رسالة عربية بلسان
/// س-123 («فشل الإذن أو الكاميرا برسالة عربية والبطاقة تعمل بلا صورة
/// أبداً»).
Future<List<int>?> pickItemSourceBytes({required bool fromCamera}) async {
  final picker = ImagePicker();
  // بلا أي تصغير أو إعادة ضغط هنا — الأصل الخام يذهب للمحرك الإلزامي
  // حصراً (D-120) فلا ضغط مزدوج ولا خيار يسكته المستخدم.
  final xfile = await picker.pickImage(
    source: fromCamera ? ImageSource.camera : ImageSource.gallery,
  );
  if (xfile == null) return null;
  return xfile.readAsBytes();
}

/// شاشة المسح بكاميرا الجوال (س-132) — تعيد الرمز النصي فحسب، والإذن
/// المرفوض أو الكاميرا الغائبة رسالة عربية لا انهيار (حالات س-132).
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  bool _done = false;

  void _emit(String code) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مسح باركود')),
      body: MobileScanner(
        // الرمز الأول يكفي — المسح المتتابع ليست حاجتنا هنا (زر لكل
        // مسار: قسم الباركود بالبطاقة واختيار البنود — س-132).
        onDetect: (capture) {
          for (final bar in capture.barcodes) {
            final value = bar.rawValue;
            if (value != null && value.trim().isNotEmpty) {
              _emit(value.trim());
              return;
            }
          }
        },
        errorBuilder: (context, error, child) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'تعذر فتح الكاميرا — تحقق من إذن الكاميرا أو أغلق تطبيقاً '
                  'يحتجزها ثم أعد المحاولة',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('رجوع'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// فتح شاشة المسح — يعيد الرمز أو null عند الإلغاء.
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(builder: (_) => const BarcodeScanScreen()),
  );
}
