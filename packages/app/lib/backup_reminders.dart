/// تذكيرات النسخ الذكية — الواجهة الأغنى (تكليف 2026-11-13 §3 و§8-8
/// و§10-1، دفعة 2 من نظام النسخ): لوحة صفوف داخل بطاقة النسخ المجدول
/// بالإعدادات، كل صف رسالة مبنية على حالة البيانات الفعلية (عدد
/// الأيام وتاريخ آخر نسخة ونسبة الحصة الحية) لا تذكيراً عاماً — ومعه
/// زر فعل مباشر: «أنشئ نسخة الآن (مع المرفقات)» أو «افتح الكتالوج».
///
/// فصل الطبقات (F-010): منطق الاستحقاق نقيٌّ بمجال بلا Flutter أصلاً
/// (noBackupFor30Days وattachmentsReminderDue — backup_schedule.dart)
/// وهذه الطبقة عرض خالص فوق شارة BackupHealth التي يحسبها المركز بعد
/// كل نسخة وكل إقلاع — فتتجدد اللوحة لحظة تجدد الشارة
/// (ValueListenableBuilder على notifier المركز).
///
/// والتواريخ تُعرض كما خُزنت UTC بعرف بطاقة الإعدادات القائمة (fmt
/// بسطر الدورات) — لا تحويل محلي خفي يختلف عن جارتها.
library;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'backup_center.dart';

/// هوية التذكير — والترتيب بالقائمة بترتيب الأولوية الموثق (الفشل
/// أولًا ثم انقطاع الحماية ثم المرفقات ثم الحصة فالبطارية).
enum BackupReminderId { failure, stale30, attachments, hourlyQuota, quotaWarn, hourlyBattery }

/// شدة التذكير تقرر لون الصف وأيقونته (ق-ن8: أحمر للفشل، برتقالي
/// للتذكيرات، معلوماتي لما لا يطلب فعلًا).
enum BackupReminderSeverity { urgent, warn, info }

/// فعل التذكير المباشر — زر واحد بحد أقصى لكل صف لا قائمة أزرار:
/// الإنشاء مع المرفقات (غنى نقطة الاستعادة) أو فتح الكتالوج (تصدير/
/// حذف/تحقق) أو بلا فعل للإعلامي الصرف.
enum BackupReminderAction { createNowWithImages, openCatalog, none }

/// صف تذكير جاهز للعرض — باني البناء النقي يملؤه بالرسائل الحية.
class BackupReminder {
  final BackupReminderId id;
  final BackupReminderSeverity severity;
  final String title;
  final String message;
  final BackupReminderAction action;
  final String actionLabel;

  const BackupReminder({
    required this.id,
    required this.severity,
    required this.title,
    required this.message,
    required this.action,
    required this.actionLabel,
  });
}

/// تاريخ يومي بلا تحويل محلي — عرف بطاقة الإعدادات القائمة.
String _fmtDay(DateTime? utc) {
  if (utc == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
}

/// نسبة مئوية صحيحة مقربة — لا كسور عشرية تخدش القراءة.
int _pct(double fraction) => (fraction * 100).round();

/// بناء صفوف التذكير من شارة الصحة — نقي قابل للاختبار بلا واجهة.
/// القاعدة: كل صف بياناته الحية في رسالته (§3: «رسالة مبنية على حالة
/// البيانات الفعلية»)؛ وتخطي السارية بالحصة (≥95%) يغني عن تحذير
/// عتبة 80% المتكرر في الحالة ذاتها — صف أقوى واحد خير من صفين
/// يقولان الشيء نفسه.
List<BackupReminder> buildBackupReminders(BackupHealth h) {
  final out = <BackupReminder>[];
  if (h.failureMessage != null) {
    out.add(BackupReminder(
      id: BackupReminderId.failure,
      severity: BackupReminderSeverity.urgent,
      title: 'فشل النسخ الاحتياطي',
      message:
          'فشل آخر محاولة نسخ: ${h.failureMessage} — راجع كتالوج النسخ '
          'لمعرفة آخر نسخة سليمة.',
      action: BackupReminderAction.openCatalog,
      actionLabel: 'افتح الكتالوج',
    ));
  }
  if (h.noBackupFor30Days) {
    out.add(BackupReminder(
      id: BackupReminderId.stale30,
      severity: BackupReminderSeverity.urgent,
      title: 'بلا نسخة احتياطية حديثة',
      message: h.lastAnyUtc == null
          ? 'لم تُنشأ أي نسخة احتياطية بعد — بياناتك بلا حماية.'
          : 'مرّ ${h.computedAtUtc.difference(h.lastAnyUtc!).inDays} يوماً '
              'على آخر نسخة (${_fmtDay(h.lastAnyUtc)}) — '
              'بياناتك بلا حماية حديثة.',
      action: BackupReminderAction.createNowWithImages,
      actionLabel: 'أنشئ نسخة الآن',
    ));
  }
  if (h.attachmentsStale) {
    out.add(BackupReminder(
      id: BackupReminderId.attachments,
      severity: BackupReminderSeverity.warn,
      title: 'المرفقات خارج آخر نسخة',
      message: h.latestWithImagesUtc == null
          ? 'صور الأصناف تغيّرت ولم تدخل أي نسخة تضم المرفقات بعد.'
          : 'صور الأصناف تغيّرت بعد آخر نسخة تضم المرفقات '
              '(${_fmtDay(h.latestWithImagesUtc)}).',
      action: BackupReminderAction.createNowWithImages,
      actionLabel: 'أنشئ نسخة الآن (مع المرفقات)',
    ));
  }
  if (h.hourlySkippedQuota) {
    out.add(BackupReminder(
      id: BackupReminderId.hourlyQuota,
      severity: BackupReminderSeverity.warn,
      title: 'الساعية متوقفة بحصة ممتلئة',
      message: 'تخطّت النسخة السارية: استهلاك الحصة بلغ '
          '${_pct(h.quotaUsedFraction)}% — تُستأنف تلقائياً متى تحرّر '
          'الحيز بتصدير القديم أو حذفه من الكتالوج.',
      action: BackupReminderAction.openCatalog,
      actionLabel: 'افتح الكتالوج',
    ));
  } else if (h.quotaUsedFraction >= kBackupQuotaWarnFraction) {
    out.add(BackupReminder(
      id: BackupReminderId.quotaWarn,
      severity: BackupReminderSeverity.warn,
      title: 'الحصة تقترب من السقف',
      message: 'استُهلك ${_pct(h.quotaUsedFraction)}% من سقف حصة مجلد '
          'النسخ — عند 95% تتوقف الساعية تلقائياً. صدّر ما يهمك واحذف '
          'القديم من الكتالوج.',
      action: BackupReminderAction.openCatalog,
      actionLabel: 'افتح الكتالوج',
    ));
  }
  if (h.hourlySkippedBattery) {
    out.add(BackupReminder(
      id: BackupReminderId.hourlyBattery,
      severity: BackupReminderSeverity.info,
      title: 'السارية بانتظار الشحن',
      message: 'تخطّت النسخة السارية: بطارية أندرويد تحت 20% — '
          'تُستأنف تلقائياً بعد الشحن. لا فعل مطلوباً منك.',
      action: BackupReminderAction.none,
      actionLabel: '',
    ));
  }
  return out;
}

/// لوحة التذكيرات — تُغرس داخل بطاقة النسخ المجدول بالإعدادات.
/// أفعالها محقونة لا استدعاء مباشر (الفصل يبقيها قابلة للاختبار
/// بمعزل عن الشاشة والمركز معاً): الإنشاء يمر بمسار النسخة اليدوية
/// القائم بمحركه وشروطه، والفتح بمسار الكتالوج القائم.
class BackupRemindersPanel extends StatelessWidget {
  final ValueListenable<BackupHealth?> healthListenable;
  final Future<void> Function() onCreateNow;
  final VoidCallback onOpenCatalog;

  /// تعطيل زر الإنشاء أثناء نسخة جارية — لا ازدحام عمليتين.
  final bool busy;

  const BackupRemindersPanel({
    super.key,
    required this.healthListenable,
    required this.onCreateNow,
    required this.onOpenCatalog,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackupHealth?>(
      valueListenable: healthListenable,
      builder: (context, h, _) {
        if (h == null) return const SizedBox.shrink();
        final reminders = buildBackupReminders(h);
        if (reminders.isEmpty) return _healthyRow(context, h);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in reminders) _reminderRow(context, r),
          ],
        );
      },
    );
  }

  /// الحالة السليمة سطر أخضر هادئ واحد — الشكر لا الضجيج (لا بطاقة
  /// فارغة تحسبها العين منطقة ميتة) — بزوق الإيجابي الدلالي (س186).
  Widget _healthyRow(BuildContext context, BackupHealth h) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: diqqahLanesOf(context).positive.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.onSurface),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'النسخ الاحتياطي بحماية سليمة — '
              'آخر نسخة ${_fmtDay(h.lastAnyUtc)}',
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reminderRow(BuildContext context, BackupReminder r) {
    final scheme = Theme.of(context).colorScheme;
    // أزقة دِقّة الدلالية (س186): العاجل سلبي أحمر، والتنبيه انتباه
    // أزرق، والمعلومة محايدة باهتة — لا برتقالي خام بعد اليوم.
    final lanes = diqqahLanesOf(context);
    final color = switch (r.severity) {
      BackupReminderSeverity.urgent => lanes.negative.bg,
      BackupReminderSeverity.warn => lanes.attention.bg,
      BackupReminderSeverity.info => lanes.neutral.bg,
    };
    final icon = switch (r.severity) {
      BackupReminderSeverity.urgent => Icons.error_outline,
      BackupReminderSeverity.warn => Icons.warning_amber,
      BackupReminderSeverity.info => Icons.info_outline,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(r.message, style: TextStyle(color: scheme.onSurface)),
          if (r.action != BackupReminderAction.none) ...[
            const SizedBox(height: 4),
            if (r.action == BackupReminderAction.createNowWithImages)
              FilledButton(
                onPressed: busy ? null : () => onCreateNow(),
                child: Text(r.actionLabel),
              )
            else
              TextButton(
                onPressed: onOpenCatalog,
                child: Text(r.actionLabel),
              ),
          ],
        ],
      ),
    );
  }
}
