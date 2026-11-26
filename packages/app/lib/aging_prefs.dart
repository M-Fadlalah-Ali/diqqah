/// فوهج أعمار الذمم القابلة للتهيئة — س-151/D-149 (دفعة 15).
///
/// بقرار دراسة محضر الخبراء (س46/D-140): «الفوهج إعدادات لا كود» —
/// الافتراض 30/60/90/120، والتخزين بمخزن الخيارات القائم
/// (shared_preferences — نمط مفاتيح الصور D-104/D-123) بقيمة
/// ValueNotifier فتتجدد الشاشة لحظياً بنمط الخط.
///
/// المخزون فهرس قائمة جاهزة لا قائمة أيام حرة — لماذا؟ القائمة
/// المنسدلة تطابق قيمتها بالهوية (==) لا بالمحتوى، فحفظ قائمة جديدة
/// بنفس الأيام لكن بهوية أخرى يفجّر تأكيد الدروبداون (القيمة يجب أن
/// تكون من بنودها) — فالقيم كلها من الثوابت الجاهزة حصراً وبفهرسها
/// تُحفظ وتُقرأ، وهذا أيضاً أبسط حرساً (فهرس بمجاله لا أربع أرقام
/// تُدقق).
library;

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// قوائم الفوهج الجاهزة — الافتراض الأول (30/60/90/120) بقرار
/// الدراسة (س46/D-140).
const List<List<int>> kAgingBucketPresets = [
  [30, 60, 90, 120],
  [15, 30, 60, 90],
  [30, 60, 90, 180],
];

/// لسان خيار الفوهج بالقائمة — الأيام مفصولة بشرطة مائلة.
String agingPresetLabel(List<int> thresholds) => thresholds.join('/');

const String _kAgingKey = 'aging_preset_index';

/// فهرس القائمة المعتمدة — الافتراض صفر (30/60/90/120).
final ValueNotifier<int> agingPresetIndex = ValueNotifier<int>(0);

/// الفوهج الجارية بالقائمة المعتمدة — من الثوابت حصراً فلا قائمة
/// حرة تُدقق ولا هوية تُطابَق.
List<int> get agingThresholds =>
    kAgingBucketPresets[agingPresetIndex.value.clamp(
        0, kAgingBucketPresets.length - 1)];

/// قراءة الفهرس المخزن عند الإقلاع — نمط loadFontChoice (D-104).
/// الغائب والفاسد وخارج المجال يعيد الافتراضي ولا يكسر الإقلاع أبداً —
/// والحرس D-197 (س96): فشل المخزن ذاته (منصة بلا إعدادات) لا يرمي
/// أبداً — درس العلة الميدانية: الإقلاع أقدس من تفضيل.
Future<void> loadAgingPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kAgingKey);
    if (raw == null ||
        raw < 0 ||
        raw >= kAgingBucketPresets.length) {
      return;
    }
    agingPresetIndex.value = raw;
  } catch (_) {
    // الافتراضي باقٍ — بلا كسر.
  }
}

/// حفظ فهرس مختار — خارج المجال يُرفض بلا مساس بالقائمة الجارية.
void saveAgingPreset(int index) {
  if (index < 0 || index >= kAgingBucketPresets.length) return;
  agingPresetIndex.value = index;
  SharedPreferences.getInstance().then((prefs) {
    prefs.setInt(_kAgingKey, index);
  });
}
