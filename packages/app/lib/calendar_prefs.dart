/// خيارا التقويم المعتمدان (س233 — D-231، المرحلة أ/2 من خارطة الطريق
/// الخماسية): أسماء الأشهر (شامية/دولية) وأول الأسبوع (السبت/الأحد/
/// الاثنين) — بجوار خيار التاريخ الهجري القائم ببطاقة «العرض والمظهر».
///
/// البنية بنمط خيارات العرض القائم حرفاً (D-104 للخطوط وF-167/D-183
/// للهجري): مفتاحان بالإعدادات المشتركة (تخزين أجهزة لا قاعدة فلا
/// ترحيلة) بمنبِّهَي قيمة، قراءة محمية يعيد فاشلها الافتراض بلا كسر
/// إقلاع (حرس D-197)، وتطبيقهما:
/// - منتقي التاريخ: بوفد الترجمة الحاكم (calendar_localizations.dart)
///   فيصار شهر رأس المنتقي بالأسماء المختارة وأول أيام أسبوع الجدول
///   بالاختيار — يشمل حقلي من/إلى بكل التقارير إذ منتقيها هو ذاته.
/// - المطبوعات: سطر التاريخ بالصيغة الطويلة بأسماء الأشهر المختارة
///   (formatDiqqahLongDate).
///
/// والافتراض الدولية والسبت: سلوك القائم قبل الخيارين حرفاً (قناة ar
/// العالمية تبدأ الأسبوع سبتاً وتسمي الشهور بالدولية) فلا يتغير شيء
/// بلا طلب — والاختيار بيد صاحب الجهاز من الإعدادات.
///
/// أسماء الأشهر بيانات تقويمية لا نصوص واجهة (نمط محرك التفقيط
/// tafqit.dart بخط أساس حارس النصوص المثبت): محورها تقويمي لا شاشة،
/// وتربطها المرحلة د-2 (D-236) باللغة المختارة عند تعددها.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kMonthNamesPrefsKey = 'calendar_month_names';
const String _kWeekStartPrefsKey = 'calendar_week_start';

/// أسماء الأشهر المعتمدة — شامية (التقويم الشامي المتداول بسورية) أو
/// دولية (المعربة العالمية الشائعة بقنوات ar العامة).
enum DiqqahMonthNames { shami, international }

/// أول أيام الأسبوع بجدولة المنتقي وعرض التقويم.
enum DiqqahWeekStart { saturday, sunday, monday }

/// الخياران الجاريان — الافتراض سلوك القائم (دولية/سبت).
final ValueNotifier<DiqqahMonthNames> calendarMonthNames =
    ValueNotifier<DiqqahMonthNames>(DiqqahMonthNames.international);
final ValueNotifier<DiqqahWeekStart> calendarWeekStart =
    ValueNotifier<DiqqahWeekStart>(DiqqahWeekStart.saturday);

/// أسماء الأشهر الشامية الاثنا عشر — كانون الثاني أولاً.
const List<String> kShamiMonthNames = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

/// أسماء الأشهر الدولية الاثنا عشر — يناير أولاً.
const List<String> kInternationalMonthNames = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// اسم الشهر (1..12) بالاختيار المعطى — وكل مدخل فاسد يعيد الافتراض
/// الدولي (الشهر 1) بلا رمي (قراءة عرضية لا حكم).
String diqqahMonthName(int month, {DiqqahMonthNames? names}) {
  final choice = names ?? calendarMonthNames.value;
  final list = choice == DiqqahMonthNames.shami
      ? kShamiMonthNames
      : kInternationalMonthNames;
  if (month < 1 || month > 12) return list[0];
  return list[month - 1];
}

/// التاريخ الطويل بالصيغة المعتمدة «28 تشرين الثاني 2026» — بأسماء
/// الأشهر المختارة. نقية بلا قنوات فتُختبر مباشرة (نمط s204).
String formatDiqqahLongDate(DateTime date, {DiqqahMonthNames? names}) =>
    '${date.day} ${diqqahMonthName(date.month, names: names)} ${date.year}';

/// فهرس أول أيام الأسبوع بعرف MaterialLocalizations (0 = الأحد):
/// السبت 6 والأحد 0 والاثنين 1 — وكل قيمة فاسدة تعيد سبت الافتراض.
int diqqahWeekStartIndex(DiqqahWeekStart? start) {
  switch (start ?? calendarWeekStart.value) {
    case DiqqahWeekStart.saturday:
      return 6;
    case DiqqahWeekStart.sunday:
      return 0;
    case DiqqahWeekStart.monday:
      return 1;
  }
}

/// قراءة الخيارين عند الإقلاع — نمط loadHijriDisplayPref حرفاً: الفاشل
/// يعيد الافتراض ولا يكسر الإقلاع أبداً.
Future<void> loadCalendarPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getString(_kMonthNamesPrefsKey);
    if (names == DiqqahMonthNames.shami.name) {
      calendarMonthNames.value = DiqqahMonthNames.shami;
    }
    final week = prefs.getString(_kWeekStartPrefsKey);
    if (week == DiqqahWeekStart.sunday.name) {
      calendarWeekStart.value = DiqqahWeekStart.sunday;
    } else if (week == DiqqahWeekStart.monday.name) {
      calendarWeekStart.value = DiqqahWeekStart.monday;
    }
  } catch (_) {
    // الافتراض باقٍ — بلا كسر.
  }
}

/// حفظ اختيار أسماء الأشهر — المنبِّه لحظياً والمخزن أحسن الجهد.
Future<void> setCalendarMonthNames(DiqqahMonthNames names) async {
  calendarMonthNames.value = names;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMonthNamesPrefsKey, names.name);
  } catch (_) {
    // الخيار حي بالذاكرة — نمط saveFontChoice.
  }
}

/// حفظ اختيار أول الأسبوع — بالنمط ذاته.
Future<void> setCalendarWeekStart(DiqqahWeekStart start) async {
  calendarWeekStart.value = start;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWeekStartPrefsKey, start.name);
  } catch (_) {
    // الخيار حي بالذاكرة.
  }
}
