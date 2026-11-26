/// التاريخ الهجري خيار عرض بجانب الميلادي — F-167 (الدفعة 23/D-183).
///
/// بقرار D-077/F-175: الميلادي أساس التخزين والإدخال والتوثيق حصراً
/// ولا إدخال هجري أبداً — فهذا الملف عرضاً حصراً: مفتاح مخزن الخيارات
/// القائم (نمط مفاتيح الصور D-104 وفوهج الأعمار D-149) بقيمة
/// ValueNotifier، ودالة عرض مركزية تطبّق محوّل المجال النقي
/// `hijriFromIsoDate` (التقويم الحسابي المعياري الموثق D-183).
///
/// الصدق أولاً: المدخل الفاسد والغائب يعود كما هو بلا اختراع، والهجري
/// الحسابي قد يخالف رؤية المحلّة بيوم أو يومين فهو عرض لا مرجع حكم.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

const String _kHijriKey = 'hijri_display_enabled';

/// حالة الخيار الجارية — الافتراض مطفأ (الميلادي وحده كما كان دائماً).
final ValueNotifier<bool> hijriDisplayEnabled = ValueNotifier<bool>(false);

/// قراءة الخيار المخزن عند الإقلاع — نمط loadFontChoice (D-104).
/// الغائب والفاسد يعيد الافتراضي ولا يكسر الإقلاع أبداً — والحرس
/// D-197 (س96): فشل المخزن ذاته لا يرمي أبداً.
Future<void> loadHijriDisplayPref() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    hijriDisplayEnabled.value = prefs.getBool(_kHijriKey) ?? false;
  } catch (_) {
    // الافتراضي باقٍ — بلا كسر.
  }
}

/// حفظ الخيار — المخزن فوراً والقيمة الجارية لحظياً.
Future<void> setHijriDisplayEnabled(bool enabled) async {
  hijriDisplayEnabled.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kHijriKey, enabled);
}

/// التاريخ المعروض — الميلادي وحده افتراضاً، و«ميلادي (هـ 1448-05-23)»
/// حين يُفعَّل الخيار. المدخل الفاسد يعود كما هو بلا اختراع، والخيار
/// بتمريره صريحاً يخدم الاختبار دون قراءة الحالة الجارية.
String displayDate(String isoDateText, {bool? hijri}) {
  final enabled = hijri ?? hijriDisplayEnabled.value;
  if (!enabled) return isoDateText;
  final hijriText = hijriFromIsoDate(isoDateText);
  if (hijriText == null) return isoDateText;
  return '$isoDateText (هـ $hijriText)';
}
