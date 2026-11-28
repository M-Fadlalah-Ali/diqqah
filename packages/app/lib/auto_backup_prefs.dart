/// خيارات النسخ الآلي (س233 — D-232، المرحلة أ/3 من خارطة الطريق
/// الخماسية): المفتاح الرئيسي وخانات الدورات (ساعي/يومي/شهري وخانتا
/// متقدمة أسبوعي/سنوي) — سياسة أجهزة فوق محرك GFS القائم لا محرك
/// جديد ولا ترحيلة.
///
/// البنية بنمط خيارات العرض القائم (D-104 للخطوط وF-167 للهجري):
/// مفاتيح بالإعدادات المشتركة (تخزين أجهز لا قاعدة) بمنبِّهات قيمة،
/// قراءة محمية يعيد فاشلها الافتراض بلا كسر إقلاع (حرس D-197).
///
/// والافتراض مفعَّل بكل الخانات: سلوك المحرك القائم قبل الخيارات
/// حرفاً (الدورات الأربع المجدولة كلها تجري — لحاق أول التشغيل والمضرب
/// الدوري — والسنوية تُنشأ عند إقفال السنة)، فلا يتغير شيء بلا طلب —
/// والإيقاف أو إخلاء خانة يوقف دورتها بالمرشحة (backup_center.dart)
/// فوراً عند أقرب لحاق أو نبضة.
library;

import 'package:diqqah_domain/diqqah_domain.dart' show BackupScheduleKind;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kAutoBackupEnabledKey = 'auto_backup_enabled';
const String _kAutoBackupKindsKey = 'auto_backup_kinds';
const String _kAutoBackupAnnualAtCloseKey = 'auto_backup_annual_at_close';

/// المفتاح الرئيسي — الافتراض مفعّل (النسخ نظامي يعمل بغض النظر عن
/// المستخدم المسجل — §7 عقد المحرك القائم).
final ValueNotifier<bool> autoBackupEnabled = ValueNotifier<bool>(true);

/// الدورات المفعلة — الافتراض الدورات المجدولة الأربع كلها (سلوك
/// المحرك القائم حرفاً: الساعية واليومية والأسبوعية والشهرية).
final ValueNotifier<Set<BackupScheduleKind>> autoBackupKinds =
    ValueNotifier<Set<BackupScheduleKind>>(const {
  BackupScheduleKind.hourly,
  BackupScheduleKind.daily,
  BackupScheduleKind.weekly,
  BackupScheduleKind.monthly,
});

/// النسخة السنوية عند إقفال السنة — خانة متقدمة، افتراضها مفعّل
/// (السلوك القائم: السنوية تُنشأ بعد نجاح الإقفال دائماً) — والحدثية
/// قبل الإقفال شبكة أمان لا تحكمها هذه الخانة أبداً.
final ValueNotifier<bool> autoBackupAnnualAtClose =
    ValueNotifier<bool>(true);

/// هل تجري هذه الدورة التلقائية؟ — المفتاح الرئيسي والخانة معاً:
/// بلا مفتاح لا دورة، وبلا خانة لا دورتها. نقية فتُختبر بلا قنوات.
bool autoBackupKindAllowed(BackupScheduleKind kind) =>
    autoBackupEnabled.value && autoBackupKinds.value.contains(kind);

String _encodeKinds(Set<BackupScheduleKind> kinds) =>
    [for (final k in kinds) k.symbol].join(',');

Set<BackupScheduleKind> _decodeKinds(String? raw) {
  if (raw == null || raw.isEmpty) return autoBackupKinds.value;
  final parsed = <BackupScheduleKind>{};
  for (final symbol in raw.split(',')) {
    final kind = BackupScheduleKind.fromSymbol(symbol);
    if (kind != null && kind.isScheduled) parsed.add(kind);
  }
  return parsed.isEmpty ? autoBackupKinds.value : parsed;
}

/// قراءة الخيارات عند الإقلاع — نمط loadFontChoice حرفاً: الفاشل يعيد
/// الافتراض ولا يكسر الإقلاع أبداً.
Future<void> loadAutoBackupPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    autoBackupEnabled.value = prefs.getBool(_kAutoBackupEnabledKey) ?? true;
    autoBackupKinds.value = _decodeKinds(prefs.getString(_kAutoBackupKindsKey));
    autoBackupAnnualAtClose.value =
        prefs.getBool(_kAutoBackupAnnualAtCloseKey) ?? true;
  } catch (_) {
    // الافتراض باقٍ — بلا كسر.
  }
}

/// حفظ المفتاح الرئيسي — المنبِّه لحظياً فتسري المرشحة من أقرب لحاق.
Future<void> setAutoBackupEnabled(bool enabled) async {
  autoBackupEnabled.value = enabled;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoBackupEnabledKey, enabled);
  } catch (_) {
    // الخيار حي بالذاكرة — نمط saveFontChoice.
  }
}

/// حفظ خانة دورة واحدة — إضافة أو إزالة بالمعطى.
Future<void> setAutoBackupKind(BackupScheduleKind kind, bool enabled) async {
  final next = {...autoBackupKinds.value};
  if (enabled) {
    next.add(kind);
  } else {
    next.remove(kind);
  }
  autoBackupKinds.value = next;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAutoBackupKindsKey, _encodeKinds(next));
  } catch (_) {
    // الخيار حي بالذاكرة.
  }
}

/// حفظ خانة السنوية المتقدمة — تحكم النسخة السنوية عند الإقفال.
Future<void> setAutoBackupAnnualAtClose(bool enabled) async {
  autoBackupAnnualAtClose.value = enabled;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoBackupAnnualAtCloseKey, enabled);
  } catch (_) {
    // الخيار حي بالذاكرة.
  }
}
