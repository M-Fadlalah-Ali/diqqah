/// قسم الهوية والصلاحيات بالإعدادات (س233 — D-230، المرحلة أ/1 من خارطة
/// الطريق الخماسية): بيانات المنشأة (س203) وبطاقة المستخدم الحالي
/// (س211/س212) — المتن بنصوص دفعاته حرفاً، والقسم أول الأقسام بترتيب
/// D-218 القائم.
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart' show PasswordHasher;
import 'package:diqqah_storage/diqqah_storage.dart';

import '../company_profile.dart';
import '../dq_log.dart';
import '../l10n/app_strings.dart';

/// قسم الهوية والصلاحيات — بيانات المنشأة للمدير حصراً وبطاقة الجلسة.
class IdentitySection extends StatefulWidget {
  final DiqqahDatabase db;

  /// س212 (D-215): نداء الغلق للتبديل — الزر يكتب الراية ثم ينادي به
  /// فتعيد بوابة الإقلاع الجذر على بوابة الجهاز.
  final VoidCallback? onSessionLocked;

  /// س211 (D-216): تكرارات الهاش — الافتراض العتبة الآمنة والاختبارات
  /// تحقن الصغيرة بنمط first_run.
  final int hasherIterations;

  /// هل الجلسة مدير كل الصلاحيات؟ (بوابة بطاقة بيانات المنشأة).
  final bool isManager;

  const IdentitySection({
    super.key,
    required this.db,
    this.onSessionLocked,
    this.hasherIterations = PasswordHasher.secureIterations,
    required this.isManager,
  });

  @override
  State<IdentitySection> createState() => _IdentitySectionState();
}

class _IdentitySectionState extends State<IdentitySection> {
  AppUser? _currentUser;

  /// قسم سريع الخطوات (قفل/كلمة) — لا عمليات مشغلة فيه.
  final bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final user = await widget.db.currentUser();
    if (!mounted) return;
    setState(() => _currentUser = user);
  }

  /// س212 (D-215): التبديل عبر آلة الحالتين حصراً — الزر يكتب
  /// الراية بlockSession (التبديل قفلٌ ثم بلاطة أخرى بالبوابة:
  /// فتح سريع لنفس المستخدم أو بلاطة غيره) ثم ينادي نداء الغلق
  /// فتعود بوابة الجهاز — فلا تبديل مباشر يتجاوز الآلة بعد اليوم
  /// ولا جلسة بلا تحقق بمدخلين اثنين.
  Future<void> _lockForSwitch() async {
    await widget.db.lockSession();
    if (!mounted) return;
    widget.onSessionLocked?.call();
  }

  /// س211 (D-216): حوار تغيير الكلمة الذاتي الطوعي — لصاحب الجلسة
  /// بالكلمة الحالية من حقل الحوار حصراً (لا جلسة بلا تحقق D-100).
  /// **والإلزامي انتقل س212 إلى بوابة الجهاز** (بعد التحقق بالبوابة
  /// حصراً — device_gate_screen) فلا مدخلان للحوار الإلزامي.
  /// والنجاح فنجانُ الراية وحدث التدقيق بالتخزين حصراً — والفشل
  /// برسالته داخل الحوار فلا إلزام يتيمة.
  Future<bool?> _showPasswordChangeDialog() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    Future<void> submit(BuildContext dialogContext,
        StateSetter setDialogState) async {
      final subject = (await widget.db.currentUser())?.id;
      if (subject == null) {
        setDialogState(() => error = S.noSessionUser);
        return;
      }
      if (current.text.isEmpty) {
        setDialogState(
            () => error = S.currentPasswordRequired);
        return;
      }
      if (next.text.isEmpty) {
        setDialogState(() => error = S.newPasswordRequired);
        return;
      }
      if (next.text != confirm.text) {
        setDialogState(() => error = S.passwordConfirmMismatch);
        return;
      }
      try {
        final salt = PasswordHasher.newSalt();
        // س219: التجزئة بعزل الخلفية — 600,000 تكراراً بنوى دارت كانت
        // تجمّد خيط الواجهة كلمّا حُفظت كلمة (القياس الحي b73) والعقد
        // الإرسالي س218 بالمدار ذاته: الإغلاق قيم بسيطة حصراً.
        final hash = await PasswordHasher.hashInBackground(
            next.text, salt,
            iterations: widget.hasherIterations);
        await widget.db.changeOwnPassword(
          userId: subject,
          currentPassword: current.text,
          newPasswordHash: PasswordHasher.formatStored(
              salt, hash, widget.hasherIterations),
        );
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop(true);
        }
      } catch (e) {
        await dqLog(widget.db, e, context: 'settings.password');
        setDialogState(() => error = '$e${dqTag(e)}');
      }
    }

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text(S.changePasswordTitle),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: S.currentPasswordField,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: S.newPasswordField,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: S.confirmPasswordField,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(S.cancelAction),
            ),
            FilledButton(
              onPressed: () => submit(dialogContext, setDialogState),
              child: const Text(S.saveNewPassword),
            ),
          ],
        ),
      ),
    );
  }

  /// س211: تغيير كلمة مرور صاحب الجلسة طوعاً — من بطاقة المستخدم الحالي.
  Future<void> _changeOwnPassword() async {
    final changed = await _showPasswordChangeDialog();
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(S.passwordChanged)),
      );
    }
  }

  // ═══ س203: بيانات المنشأة والطباعة التجارية ═══

  /// بطاقة بيانات المنشأة — للمدير حصراً: هوية المنشأة سِمة إدارية
  /// تُسافر بالنسخ الاحتياطية وتظهر أول المطبوعات حين حُفظت.
  Widget _companyDataCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.storefront_outlined),
        title: const Text(S.companyDataTitle),
        subtitle: const Text(
            S.companyDataBody),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openCompanyDataDialog,
      ),
    );
  }

  /// نافذة بيانات المنشأة — قراءة الحالي أولاً فالحقول معبأة بما
  /// محفوظ حرفاً، والاسم إلزامي للحفظ فلا هوية بلا اسم، والفشل
  /// برسالة لا صمت.
  Future<void> _openCompanyDataDialog() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final tax = TextEditingController();
    try {
      final current = await loadCompanyProfile(widget.db);
      if (current != null) {
        name.text = current.name;
        phone.text = current.phone ?? '';
        address.text = current.address ?? '';
        tax.text = current.taxNumber ?? '';
      }
    } catch (_) {
      // قراءة الحالي ليست شرط فتح النافذة — حقول فارغة تكفي.
    }
    if (!mounted) return;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text(S.companyDataTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: S.companyNameRequired),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: S.phoneLabel),
                ),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: S.addressLabel),
                ),
                TextField(
                  controller: tax,
                  decoration: const InputDecoration(
                      labelText: S.taxNumberOptional),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text(S.cancelAction),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(S.companyNameMandatory)),
                        );
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        await saveCompanyProfile(
                          widget.db,
                          CompanyProfile(
                            name: name.text.trim(),
                            phone: phone.text.trim().isEmpty
                                ? null
                                : phone.text.trim(),
                            address: address.text.trim().isEmpty
                                ? null
                                : address.text.trim(),
                            taxNumber: tax.text.trim().isEmpty
                                ? null
                                : tax.text.trim(),
                          ),
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  S.companyDataSaved)),
                        );
                      } catch (e) {
                        setDialogState(() => busy = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(S.saveFailed(e))),
                        );
                      }
                    },
              child: const Text(S.saveAction),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // س203: بيانات المنشأة — هوية صاحب العمل التي تظهر أول
        // المطبوعات (الطباعة التجارية)، للمدير حصراً فالمنشأة
        // هويّة إدارية لا يدخلها منوِّب.
        if (widget.isManager) _companyDataCard(),
        if (widget.isManager) const SizedBox(height: 16),
        // ── س213 (D-218): المستخدم الحالي بقسم الهوية والصلاحيات —
        // بطاقة الجلسة أقرب بيانات إلى صاحبها (المحتوى بنص س212 حرفاً
        // وبلا مساس ببنية الحقوق).
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.currentUser,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                if (_currentUser != null)
                  Text(
                    '${_currentUser!.name} (${_currentUser!.login})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                // س212 (D-215): التبديل قفلٌ ثم بلاطة أخرى — الراية
                // تُكتب بالقاعدة ثم بوابة الجهاز هي الوجه فلا تبديل
                // مباشر يتجاوز الآلة بعد اليوم.
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _lockForSwitch,
                  icon: const Icon(Icons.lock_person_outlined),
                  label: const Text(S.lockSwitchUser),
                ),
                const SizedBox(height: 8),
                // س211 (D-216): تغيير الكلمة الذاتي طوعي لصاحب
                // الجلسة — والإلزامي ببوابة الجهاز لصاحب الراية.
                OutlinedButton.icon(
                  onPressed: _busy ? null : _changeOwnPassword,
                  icon: const Icon(Icons.password_outlined),
                  label: const Text(S.changeMyPassword),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
