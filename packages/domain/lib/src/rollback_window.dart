/// نافذة التراجع عن الاستعادة — السياسة النقية (د-3 — §25.7، س136).
///
/// بعد كل استعادة تُفتح نافذة تراجع تُتاح فيها لقطة ما قبل الاستعادة
/// عبر مسار الاستعادة ذاته (لا مسار خاص)، وتُغلق بأول عملية كتابة —
/// والحارس **سجل الأحداث**: النافذة تسلَّح بخط أساس (آخر معرّف حدث لحظة
/// تسليحها)، وأول حدث جديد يتجاوزه كتابةٌ أغلقتها فيُسجَّل الحدث.
///
/// هذه الوحدة نقية حصراً بلا dart:io بلا Flutter (F-010): الحالة نموذج
/// بيانات وصياغة JSON والحارس دالة نقية — أما التخزين بمفتاح app_meta
/// وتسجيل حدث الإغلاق فمحرك التخزين وحده.
library;

import 'dart:convert';

/// حالة نافذة التراجع — تُخزَّن بمفتاح `restore.rollback_window` في
/// app_meta (مفاتيح نظام معفاة من اصطلاح المزامنة D-055)، وتُستبدل بكل
/// استعادة جديدة فالنافذة تعود لآخر استعادة حصراً (كل استعادة — أصلية
/// أو تراجعاً — تفتح نافذتها الخاصة بلقطتها الخاصة بنتيجة إعادة
/// استخدام المسار — موثقة سلوكاً).
class RollbackWindowState {
  /// اسم ملف لقطة ما قبل الاستعادة المثبتة (`diqqah-before-restore-*.db`)
  /// — داخل مجلد القاعدة، ويُستعاد بها بمسار الاستعادة ذاته.
  final String snapshotFileName;

  /// لحظة تسليح النافذة (اجتياز البوابة بعد الاستعادة) — UTC.
  final DateTime openedAtUtc;

  /// خط الأساس: آخر معرّف حدث بسجل الأحداث لحظة التسليح — ما بعده كتابة.
  final int baselineEventId;

  /// هل أُغلقت النافذة؟ الإغلاق نهائي لا يُعاد فتحه — الاستعادة الجديدة
  /// تفتح نافذة جديدة كلياً.
  final bool closed;

  const RollbackWindowState({
    required this.snapshotFileName,
    required this.openedAtUtc,
    required this.baselineEventId,
    required this.closed,
  });

  Map<String, Object?> toJsonMap() => <String, Object?>{
        'snapshot': snapshotFileName,
        'opened_at': openedAtUtc.toIso8601String(),
        'baseline': baselineEventId,
        'closed': closed,
      };

  String toJson() => jsonEncode(toJsonMap());

  /// الحالة من نص JSON — فاسد أو ناقص أو تاريخ غير UTC يعود null
  /// (الفاسد كالغائب — عرف D-169: لا سحر ولا استثناء).
  static RollbackWindowState? tryParse(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map<String, Object?>) return null;
      final snapshot = '${root['snapshot'] ?? ''}';
      final opened = DateTime.tryParse('${root['opened_at'] ?? ''}');
      final baseline = (root['baseline'] as num?)?.toInt();
      if (snapshot.isEmpty ||
          opened == null ||
          !opened.isUtc ||
          baseline == null) {
        return null;
      }
      return RollbackWindowState(
        snapshotFileName: snapshot,
        openedAtUtc: opened,
        baselineEventId: baseline,
        closed: root['closed'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// النافذة نفسها مقفلة — بلا مساس ببقية الحقول.
  RollbackWindowState withClosed() => RollbackWindowState(
        snapshotFileName: snapshotFileName,
        openedAtUtc: openedAtUtc,
        baselineEventId: baselineEventId,
        closed: true,
      );
}

/// حارس أول كتابة (25.7): هل أغلقَ الحدثُ ذو المعرف [maxEventId]
/// النافذةَ [state]؟ النافذة المفتوحة تُغلق بأول حدث يتجاوز خط أساسها،
/// والمقفلة سلفاً مقفلة مهما قرأ القراء.
bool rollbackWindowClosedByWrite(RollbackWindowState state, int maxEventId) {
  if (state.closed) return true;
  return maxEventId > state.baselineEventId;
}
