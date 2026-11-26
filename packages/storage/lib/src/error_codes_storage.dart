/// س107 (أساس الأخطاء — قرار المالك الخامس): خريطة استثناءات التخزين
/// إلى رموزها DQ-xxxx — نطاق DQ-11xx (البنية والتخزين).
///
/// ملف مستقل لا database.dart لسبب بنيوي: backup.dart يستورد
/// database.dart (محرك القاعدة) فإعادة الاستثناءين الاحتياطيين من
/// database.dart لوفت دورة استيراد — والملف الثالث يستورد الاثنين
/// فلا دورة، وهو العقد الموحد للتخزين. يكمل خريطة المجال
/// (error_codes.dart بالمجال النقي — سلطة الترقيم) فهذا توصيلُها
/// لاستثناءات هذا المستوى. غير المصنف يعيد null فيتولى العرضُ
/// الفاصلة الآمنة DQ-0999.
library;

import 'package:drift/isolate.dart' show DriftRemoteException;

import 'backup.dart';
import 'backup_gfs.dart';
import 'database.dart';

String? dqCodeForStorageError(Object error) {
  // س216: عزل الخلفية يغلف أخطاء عبور العزل بDriftRemoteException
  // (سلوك drift الموثق بعزل المحرك createInBackground) — فالخريطة
  // تقرأ السبب الجذري مهما كان الغلاف كي لا يهب رمزٌ دقيق إلى
  // الفاصلة الآمنة DQ-0999 لأن الخطأ عبر العزل.
  final root =
      error is DriftRemoteException ? error.remoteCause : error;
  // س216: عبور العزل البعيد يفقد نوع الاستثناء المخصص فيصل بلسانه
  // الموثق حصراً (سلوك drift البعيد الموثق بالجولة #429/#431) —
  // فالمطابقة بالنوع أو باللسان الموثق بحرفه (ينفرد عن أخ D-1105
  // بنصه المختلف) كي لا يهب رمزٌ دقيق للفاصلة الآمنة DQ-0999.
  if (root is DiqqahNewerSchemaException ||
      root.toString() ==
          'القاعدة أحدث مخططاً من التطبيق — حدّث التطبيق') {
    return 'DQ-1101';
  }
  if (root is UnitGroupFactorFrozenException) return 'DQ-1102';
  if (root is LedgerValidationException) return 'DQ-1103';
  if (root is CorruptBackupException) return 'DQ-1104';
  if (root is BackupNewerSchemaException) return 'DQ-1105';
  if (root is GfsBackupException) return 'DQ-1123';
  return null;
}
