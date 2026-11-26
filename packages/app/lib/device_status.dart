/// قناة حالة الجهاز — قناة منصة يدوية صغيرة (قرار ق-ن2): نسبة البطارية
/// لأندرويد حصراً، بلا أي تبعية خارجية (شرط بوابة الدفعات — pubspec
/// لا حزمة بطارية). ويندوز بلا قناة: الاستدعاء يرمي فيُلتقط ويعود
/// null فيتخطى الشرط بلا فشل — «لا تُعطّل النسخ أبداً» بلفظ القرار.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const MethodChannel _channel = MethodChannel('diqqah/device_status');

/// نسبة البطارية 0..100 — null عند غياب القناة أو فشلها (تخطٍ آمن).
Future<int?> batteryLevel() async {
  try {
    final v = await _channel.invokeMethod<int>('batteryLevel');
    if (v == null) return null;
    if (v < 0) return 0;
    if (v > 100) return 100;
    return v;
  } catch (_) {
    return null; // ويندوز/منصة بلا قناة/أي عطل — الشرط يتخطى.
  }
}
/// D-057 (قرار المالك بعد نجاح تجربة الاستعادة 2026-10-29): منتقي
/// الاستيراد يفتح افتراضياً على مجلد «التنزيلات» — حيث تُخرج النسخة
/// عادة، فيلزم النقر لا التفتيش. تحديد مجلد التنزيلات مدعوم في منتقي
/// ملفات النظام على سطح المكتب (ويندوز/لينكس/ماك) حصراً؛ على أندرويد
/// منتقي النظام (SAF) يدير نقطة البداية بنفسه ويُتجاهل المسار — فيعاد
/// null بلا أثر. وتعاد null أيضاً حيثما تعذر تحديد المجلد فلا يُعطّل
/// المنتقي أبداً.
///
/// (دفعة استيراد البيانات — س140: نُقلت هنا من settings_screen.dart
/// بلا مساس سلوكها، كي تشاركها شاشة الاستيراد والإعدادات بمنبع واحد
/// لا بمضاعفة — وبلا دورة استيراد بين الشاشتين.)
String? defaultImportDirectory({String? userProfile, String? home}) {
  final candidates = <String>[
    if (userProfile != null && userProfile.isNotEmpty)
      p.join(userProfile, 'Downloads'),
    if (home != null && home.isNotEmpty) p.join(home, 'Downloads'),
  ];
  for (final dir in candidates) {
    if (Directory(dir).existsSync()) return dir;
  }
  return null;
}
