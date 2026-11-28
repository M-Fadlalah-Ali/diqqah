/// قسم الأمان والجلسة بالإعدادات (س233 — D-230، المرحلة أ/1 من خارطة
/// الطريق الخماسية): بطاقة الخمول وقفل الجهاز (س213/D-217) وفحص
/// الثوابت (F-006/D-099) — شطر «البيانات والأمان» القائم (D-218) قسمين
/// فصار هذا القسم الثاني، والمتن بنصوص دفعاته حرفاً.
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart'
    show IntegrityReport;
import 'package:diqqah_storage/diqqah_storage.dart';

import '../app_theme.dart';
import '../dq_log.dart';
import '../l10n/app_strings.dart';

/// قسم الأمان والجلسة — الخمول للمدير وفحص الثوابت بيد المالك.
class SecuritySection extends StatefulWidget {
  final DiqqahDatabase db;

  /// س213 (D-217): «بيد المدير لا تفضيل شخصي — فلا يعطّله الكاشير»
  /// — بطاقة الخمول للمدير حصراً.
  final bool isManager;

  const SecuritySection({
    super.key,
    required this.db,
    required this.isManager,
  });

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  /// فحص الثوابت (F-006/D-099): آخر نتيجة وحالة التنفيذ.
  IntegrityReport? _integrityReport;
  bool _integrityBusy = false;

  /// س213 (D-217): مدة الخمول النافذة — تُقرأ عند الفتح (الغائب
  /// والفاسد يعودان الافتراض 10 بالتخزين ذاته) والكتابة فورية
  /// والحارس يقرؤها كل نبضة فالتغيير يسري حياً.
  int _idleMinutes = DiqqahDatabase.sessionIdleMinutesDefault;

  @override
  void initState() {
    super.initState();
    _loadIdleMinutes();
  }

  /// س213 (D-217): قراءة المدة النافذة عند الفتح وبعد كل استعادة.
  Future<void> _loadIdleMinutes() async {
    final minutes = await widget.db.sessionIdleMinutes();
    if (!mounted) return;
    setState(() => _idleMinutes = minutes);
  }

  /// فحص الثوابت الكامل بيد المالك (F-006/D-099) — سبعة فحوص قراءة
  /// خالصة والنتيجة تُعرض داخل البطاقة نفسها لا حواراً يُفقد.
  Future<void> _runIntegrityCheck() async {
    setState(() => _integrityBusy = true);
    try {
      final report = await widget.db.integrityCheckReport();
      if (!mounted) return;
      setState(() => _integrityReport = report);
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.integrity');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.integrityCheckFailed(e, dqTag(e)))),
      );
    } finally {
      if (mounted) setState(() => _integrityBusy = false);
    }
  }

  /// لسان المستويات بالعربية الصحيحة — واحدة مفردة والخمس عشرة
  /// تمييزُ مفرد، والبقية جمع (درس الدقة اللغوية بسجل العبارات).
  String _idleLabel(int minutes) {
    if (minutes == 1) return S.oneMinute;
    if (minutes == 15) return S.fifteenMinutes;
    return S.minutesCount(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── س213 (D-217): بطاقة الخمول — إعداد جهاز بيد المدير حصراً
        // فلا يعطّله الكاشير (تفضيل شخصي لا): المستويات المغلقة
        // 1/5/10/15/30 دقيقة والافتراض 10، وقفل مغادرة التطبيق
        // قانوناً لا خياراً — والقيمة النافذة يقرؤها الحارس كل نبضة
        // فالتغيير يسري حياً بلا إقلاع.
        if (widget.isManager) _sessionIdleCard(),
        if (widget.isManager) const SizedBox(height: 16),
        // فحص الثوابت بيد المالك (F-006، 07 §1.10، D-099 معروض) —
        // الفحص الكامل بعد الفحص الافتتاحي الصامت بالرئيسية.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.integrityChecksTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.integrityChecksBody,
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _integrityBusy ? null : _runIntegrityCheck,
                  child: Text(_integrityBusy ? S.checkingNow : S.checkNowAction),
                ),
                if (_integrityReport != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _integrityReport!.summary,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _integrityReport!.isClean
                          ? diqqahLanesOf(context).positive.fg
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  for (final v in _integrityReport!.violations)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $v'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// س213 (D-217): بطاقة الخمول وقفل الجهاز — للمدير حصراً («بيد
  /// المدير لا تفضيل شخصي — فلا يعطّله الكاشير» نص القرار):
  /// المنسدلة بالمستويات الخمسة المغلقة والكتابة فورية بالقاعدة
  /// (لا زر حفظ — القيمة النافذة يقرؤها الحارس كل نبضة فتسري حياً)،
  /// وقفل مغادرة التطبيق قانونٌ لا خيار فلا مفتاح له، وراية الشاشة
  /// FLAG_SECURE قناةُ الجذر بلا بند (قانون لا تفضيل).
  Widget _sessionIdleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.idleLockTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              S.idleLockBody,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              // نمط initialValue الموثق (boxes_screen) — القيمة الداخلية
              // للمُنشأ هي المعروضة، والحقل محمّل من حالة القارئ عند الفتح.
              initialValue: _idleMinutes,
              decoration: const InputDecoration(
                labelText: S.lockAfterIdle,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final minutes
                    in DiqqahDatabase.sessionIdleMinuteChoices)
                  DropdownMenuItem<int>(
                    value: minutes,
                    child: Text(_idleLabel(minutes)),
                  ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await widget.db.setSessionIdleMinutes(v);
                if (mounted) setState(() => _idleMinutes = v);
              },
            ),
          ],
        ),
      ),
    );
  }
}
