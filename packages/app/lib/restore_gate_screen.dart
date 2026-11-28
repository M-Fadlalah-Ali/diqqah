/// بوابة الاستعادة (تكليف 2026-11-13 §5/§6 — قرار ق-ن1-أ): بعد كل
/// استعادة تُمسح الجلسة قسراً ويزرع applyRestore مفتاح البوابة، فلا
/// تُعرض أي بيانات قبل دخول بمدير نشط من النسخة المستعادة ذاتها —
/// 5 محاولات ثم قفل بمخرجَي اختيار نسخة أخرى أو إعادة محاولة لاحقاً.
///
/// هذا قفل رحلة لا قفل خزانة: نموذج التهديد هو عابر يفتح جهازاً
/// يجده مضبوقاً (D-060)، والخصم التقني المتفرغ خارج عهدتها أصلاً —
/// فالقاعدة نص صريح والقرار R-18 مؤجل مستقل.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'backup_center.dart';
import 'db_key_vault.dart';
import 'item_images.dart';
import 'session.dart';
import 'dq_log.dart';
import 'app_theme.dart';

/// تنفيذ الاستعادة المشترك (الإعدادات/الكتالوج/البوابة المقفلة/التراجع) —
/// تأكيد مزدوج ثم التهيئة والفحص والاستبدال الذري بترتيب F-013/F-154
/// القائم، مع تمرير المصدر للبوابة (§5-3) وإيقاف المجدول (§8-5).
///
/// د-3 (§25.7، س136): قبل أي لمس تُقرأ حالة نافذة التراجع القائمة —
/// فإن كانت مفتوحة ثُبّتت لقطتها من تدوير آخر-5 (د-3-2) — وبعد النجاح
/// تُدوَّر اللقطات بالتثبيت ثم يُوقَف المركز على القاعدة القديمة ليعود
/// مبدأً على الجديدة مع الإقلاع (لا استئناف فوق قاعدة قديمة).
Future<bool> runRestoreFlow(
  BuildContext context, {
  required DiqqahDatabase db,
  required String dbPath,
  required String backupPath,
  required void Function() onRestored,
  String? password,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('تأكيد الاستعادة'),
      content: Text(
          'سيُستبدل ملف القاعدة الحالي كاملاً بنسخة '
          '${p.basename(backupPath)}.\n'
          'تُلتقط لقطة رجوع آلية قبل الاستبدال، والجلسة الحالية تُمسح '
          'ويُطلب دخول بمدير من النسخة المستعادة.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة')),
      ],
    ),
  );
  if (confirmed != true) return false;
  BackupCenter.instance?.pause();
  // د-3-2: النافذة المفتوحة تُقرأ قبل أي مساس بقاعدة قديمة تُغلق —
  // لقطتها مثبتة من التدوير أثناء الفجوة حتى نافذة الاستعادة الجديدة.
  RollbackWindowState? openWindow;
  try {
    final w = await db.rollbackWindow();
    if (w != null && !w.closed) openWindow = w;
  } catch (_) {}
  try {
    // P1-أ (س149): الجيل المقفل v3 يُفك بأسرار خزنة هذا الجهاز أولاً —
    // وفشلها يعيد المحاولة بما كتبه المالك (الكلمة أو رمز الاسترداد —
    // كلتاهما تُجرّبان). v1/v2 بمساريهما القديمين حرفاً. قراءة الخزنة
    // الفاشلة (قناة غائبة بالاختبارات) = بلا أسرار — فشل الفك اللاحق
    // يعرض رسالته الصريحة لا استثناء خزنة يطغى عليه.
    // د11 (س229/D-225 الجزء الأول): وجيل الخزنة v4 يُفك بمفتاح هذا
    // الجهاز صامتاً كذلك — ونسخة جهاز آخر يُطلب رمزها بحوار الطلب
    // (الحقل يقبل الكلمة أو الرمز — بوسم GCM حاكم).
    BackupLock? stored;
    if (password == null || password.isEmpty) {
      try {
        stored = await BackupSecretsStore().loadLock();
      } catch (_) {
        stored = null;
      }
    }
    // س230 (د11 الجزء الثاني): مواد خزنة هذا الجهاز تُحل دائماً — كلمة
    // المستخدم المكتوبة للمصدر لا للقطة الرجوع (اللقطة تُغلَّف بخزنة
    // الجهاز ذاته — v5 بالجذر الحي — فتسافر سجلاتها ويعمل التراجع)،
    // والجذر الحي لتحقق سجلات النسخة وإعادة ختمها بجذر الجهاز بعد
    // الاستعادة (خاتماً لا قارئاً فقط).
    BackupVaultKeys? storedVault;
    try {
      storedVault = await VaultBackupKeys().load();
    } catch (_) {
      storedVault = null;
    }
    final liveLogRoot = await loadLiveLogRootOrNull();
    RestoreCandidate candidate;
    try {
      candidate = await prepareRestore(
        backupPath,
        password: password ?? stored?.password,
        recoveryCode: password ?? stored?.recoveryCode,
        vaultRootKey: storedVault?.rootKey,
        localLogRootKey: liveLogRoot,
        appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      );
    } on BackupCipherException {
      if (password != null && password.isNotEmpty) rethrow;
      // نسخة جهاز آخر (v4/v5 أو مقفلة v3/v6) — طلب الرمز/الكلمة بحوار
      // واحد ثم إعادة المحاولة بها حصراً لا فوق أسرار الخزنة.
      final typed = await _promptRestoreSecret(context);
      if (typed == null || typed.isEmpty) rethrow;
      candidate = await prepareRestore(
        backupPath,
        password: typed,
        recoveryCode: typed,
        vaultRootKey: storedVault?.rootKey,
        localLogRootKey: liveLogRoot,
        appSchemaVersion: DiqqahDatabase.schemaVersionValue,
      );
    }
    try {
      await applyRestore(
        db: db,
        candidate: candidate,
        currentDbPath: dbPath,
        imagesDir: Directory(imagesDirFor(dbPath)),
        sourcePath: backupPath,
        vaultKeys: storedVault,
        logRootKey: liveLogRoot,
        imagesCipher: ItemImagesStore.cipher,
      );
      // تدوير لقطات ما قبل الاستعادة (آخر 5) مع تثبيت مثبت النافذة
      // المفتوحة (د-3-2) — ثم إيقاف المركز على القاعدة القديمة.
      try {
        await BackupCenter.instance?.afterRestore(
            protectFileName: openWindow?.snapshotFileName);
      } catch (_) {}
      await BackupCenter.instance?.shutdown();
      if (!context.mounted) return true;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تمت الاستعادة'),
          content: const Text(
              'استُبدلت القاعدة بنسخة ناجحة التحقق.\n'
              'سيُطلب الآن دخول بمدير من النسخة المستعادة.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('متابعة')),
          ],
        ),
      );
      onRestored();
      return true;
    } finally {
      candidate.dispose();
    }
  } on CorruptBackupException catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('$e${dqTag(e)}')));
    }
    return false;
  } on BackupNewerSchemaException catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('$e${dqTag(e)}')));
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذرت الاستعادة — $e${dqTag(e)}')));
    }
    return false;
  } finally {
    // المجدول يعود مع الإقلاع الجديد — إيقافٌ صريح أعلاه فيبدأ من جديد.
  }
}

/// د11 (س229/D-225 الجزء الأول وس230 للثاني): حوار طلب سر فك نسخة من
/// جهاز آخر — نسخة الخزنة (v4/v5) من غير هذا الجهاز أو مقفلة (v3/v6)
/// بلا أسرار محلية: حقل واحد يقبل رمز الاسترداد أو كلمة المرور
/// (كلتاهما تُجرّبان بوسم GCM حاكم بprepareRestore) — والإلغاء يرمي
/// الأصل فتظهر رسالته الصريحة لا صمتاً ولا أثراً.
Future<String?> _promptRestoreSecret(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('سر فك النسخة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'هذه النسخة من جهاز آخر أو مقفلة بكلمة مرور — أدخل رمز '
              'الاسترداد المطبوع عند أول تشغيل (أو كلمة المرور '
              'للمقفلة) ثم أعد المحاولة.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'رمز الاسترداد أو كلمة المرور',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('فك النسخة'),
        ),
      ],
    ),
  ).then((v) {
    controller.dispose();
    return v;
  });
}

/// شاشة البوابة ذاتها.
class RestoreGateScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final String dbPath;
  final VoidCallback onCleared;

  /// د-3 (س136): بعد استعادة ناجحة من داخل البوابة نفسها (تراجعاً
  /// أو اختيار نسخة أخرى) تُعاد بنية الجذر — القاعدة القديمة مغلقة
  /// والملف استُبدل فلا تُترك الشاشة على قاعدة ميتة.
  final VoidCallback? onRestored;

  const RestoreGateScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onCleared,
    this.onRestored,
  });

  @override
  State<RestoreGateScreen> createState() => _RestoreGateScreenState();
}

class _RestoreGateScreenState extends State<RestoreGateScreen> {
  RestoreGateState? _gate;
  List<(AppUser, Role)> _managers = const [];
  int? _selectedUserId;
  final _password = TextEditingController();
  bool _busy = false;
  String? _notice;

  /// د-3 (§25.7، س136): زر «تراجع» لحظي بعد كل استعادة — متاح بوجود
  /// لقطة ما قبل الاستعادة المزروعة بالبوابة والملف حاضر فعلاً على
  /// القرص، ويستدعي مسار الاستعادة المشترك ذاته (تأكيده المزدوج
  /// وبوابة مديره — لا مسار خاص).
  bool _rollbackAvailable = false;
  String? _rollbackSnapshotName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gate = await widget.db.restoreGate();
    // د-3: توفّر التراجع = لقطة مزروعة بالبوابة وملفها حاضر لا اسمٌ يتيم.
    var rollbackAvailable = false;
    final snap = gate?.snapshot;
    if (snap != null && snap.isNotEmpty) {
      try {
        rollbackAvailable = await File(
                p.join(p.dirname(widget.dbPath), snap))
            .exists();
      } catch (_) {
        rollbackAvailable = false;
      }
    }
    final managers = <(AppUser, Role)>[];
    try {
      final users = await widget.db.select(widget.db.appUsers).get();
      for (final u in users) {
        if (u.isDeleted || !u.isActive) continue;
        final role = await widget.db.roleOf(u);
        if (role == null) continue;
        // §5-5: مدير من النسخة المستعادة — النجمة (كامل الوحدات
        // بمثابه — حرس المجال roleCanManageBackups).
        if (RolePermissions(role.permissions).isAll) {
          managers.add((u, role));
        }
      }
    } catch (e) {
      await dqLog(widget.db, e, context: 'restore.load');
    }
    if (!mounted) return;
    setState(() {
      _gate = gate;
      _managers = managers;
      _selectedUserId =
          managers.isEmpty ? null : managers.first.$1.id;
      _rollbackAvailable = rollbackAvailable;
      _rollbackSnapshotName = rollbackAvailable ? snap : null;
    });
  }

  /// د-3: التراجع عن الاستعادة — غلاف فوق «نسخة ما قبل الاستعادة» عبر
  /// مسار الاستعادة المشترك ذاته: تأكيده المزدوج وبوابة مديره القائمة
  /// لا مسار خاص، والاستعادة الجديدة تزرع بوابتها ولقطتها الخاصة
  /// (النافذة تعود لآخر استعادة — نتيجة إعادة استخدام المسار).
  Future<void> _rollback() async {
    final snap = _rollbackSnapshotName;
    if (snap == null) return;
    await runRestoreFlow(
      context,
      db: widget.db,
      dbPath: widget.dbPath,
      backupPath: p.join(p.dirname(widget.dbPath), snap),
      onRestored: () {
        // البوابة تُعاد بنيًا على القاعدة الجديدة بمفتاحها المزروع —
        // إعادة البناء بيد الجذر (onRestored) فلا شاشة على قاعدة ميتة.
        widget.onRestored?.call();
      },
    );
  }

  Future<void> _tryLogin() async {
    final gate = _gate;
    if (gate == null || gate.locked || _busy) return;
    final userId = _selectedUserId;
    if (userId == null || _password.text.isEmpty) {
      setState(() => _notice = 'اختر مديراً وادخل كلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final user = await widget.db.verifyUserPassword(
          userId, _password.text);
      if (!mounted) return;
      if (user == null) {
        final attempts = await widget.db.bumpRestoreGateAttempts();
        final reloaded = await widget.db.restoreGate();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _notice = attempts >= 5
              ? 'استُنفدت المحاولات الخمس — البوابة مقفلة'
              : 'كلمة المرور غير صحيحة أو المستخدم معطل '
                  '(محاولة $attempts من 5)';
          _gate = reloaded;
        });
        return;
      }
      await _completeLogin(user);
    } catch (e) {
      await dqLog(widget.db, e, context: 'restore.login');
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = 'تعذر التحقق — $e${dqTag(e)}';
        });
      }
    }
  }

  /// اجتياز البوابة: جلسة جديدة + فحص سلامة + ملخص مصفّى + أحداث
  /// تدقيق (§5-7/§6) ثم مسح المفتاح فلا سؤال ثانية بعدها.
  Future<void> _completeLogin(AppUser user) async {
    await widget.db.setCurrentUserId(user.id);
    final gate = _gate;
    // فحص السلامة — شارة الجميع (§6): أخضر/أحمر.
    String integrity = 'ok';
    try {
      final rows = await widget.db
          .customSelect('PRAGMA integrity_check')
          .get();
      integrity =
          rows.isEmpty ? 'ok' : '${rows.first.data.values.first}';
    } catch (e) {
      await dqLog(widget.db, e, context: 'restore.integrity');
      integrity = 'unknown';
    }
    final facts = await widget.db.restoreSummaryFacts();
    final deviceName = await widget.db.deviceName();
    final session = await loadSession(widget.db);
    final canSeeDetails = session != null &&
        session.permissions.allows('reports');
    await widget.db.recordSystemEvent(
      'restore_performed',
      userId: user.id,
      payload: {
        'source': gate?.source ?? '',
        'result': 'success',
        'device': deviceName ?? '',
        'integrity': integrity,
      },
    );
    final shownFields = [
      'last_document',
      'users_count',
      'invoices_count',
      'integrity_badge',
      if (canSeeDetails) 'details_full',
    ];
    await widget.db.recordSystemEvent(
      'restore_summary_shown',
      userId: user.id,
      payload: {'fields': shownFields},
    );
    // د-3 (§25.7، س136): تسليح نافذة التراجع بعد أحداث التدقيق — خط
    // الأساس يسبق أول كتابة حقيقية فأول حدث بعده يغلق النافذة (الحارس
    // سجل الأحداث). بلا لقطة مزروعة لا نافذة ولا زر — بصدق.
    final snap = gate?.snapshot ?? '';
    if (snap.isNotEmpty) {
      try {
        await widget.db.armRollbackWindow(snapshotFileName: snap);
      } catch (_) {
        // فشل التسليح لا يمنع الاجتياز — النافذة رفاهية حماية لا شرط عمل.
      }
    }
    await widget.db.clearRestoreGate();
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RestoreSummaryDialog(
        facts: facts,
        integrity: integrity,
        backupAt: gate?.at,
        sourceName:
            gate == null || gate.source.isEmpty ? null : p.basename(gate.source),
        deviceName: deviceName,
        canSeeDetails: canSeeDetails,
        onDone: () {
          Navigator.pop(context);
          widget.onCleared();
        },
      ),
    );
  }

  Future<void> _reloadGate() async {
    final gate = await widget.db.restoreGate();
    if (!mounted) return;
    setState(() => _gate = gate);
  }

  Future<void> _retryLater() async {
    await widget.db.resetRestoreGateAttempts();
    _password.clear();
    await _reloadGate();
    if (mounted) {
      setState(() => _notice = null);
    }
  }

  Future<void> _pickAnotherBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.paths.single;
      if (path == null || !mounted) return;
      await runRestoreFlow(
        context,
        db: widget.db,
        dbPath: widget.dbPath,
        backupPath: path,
        onRestored: () {
          // القاعدة القديمة مغلقة والملف استُبدل — البوابة تُعاد بناءً
          // على الجديدة بمفتاحها المزروع (إصلاح س136: كانت تترك الشاشة
          // على قاعدة ميتة حتى إعادة تشغيل اليد).
          widget.onRestored?.call();
        },
      );
    } catch (e) {
      await dqLog(widget.db, e, context: 'restore.pick');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح المنتقي — $e${dqTag(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = _gate;
    final locked = gate?.locked ?? false;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة الاستعادة'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    locked
                        ? 'استُنفدت محاولات الدخول الخمس بعد الاستعادة.\n'
                            'اختر نسخة أخرى للاستعادة، أو أعد المحاولة لاحقاً.'
                        : 'استُعيدت القاعدة من نسخة احتياطية.\n'
                            'ادخل بمدير نشط من النسخة المستعادة للمتابعة.',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // د-3 (§25.7، س136): زر «تراجع» لحظي بعد كل استعادة —
              // يستعيد لقطة ما قبل الاستعادة بمسار الاستعادة ذاته،
              // ومتاح حتى أول عملية كتابة (حارس سجل الأحداث) — والقاعدة
              // خلف البوابة لا تقبل كتابة قبل الاجتياز أصلاً.
              if (_rollbackAvailable) ...[
                Card(
                  color: cs.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('نافذة التراجع عن الاستعادة مفتوحة',
                            style: TextStyle(
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                            'الاستعادة الأخيرة كانت من '
                            '${_gate?.source.isEmpty ?? true ? 'ملف خارجي' : p.basename(_gate!.source)}.\n'
                            'لقطة ما قبل الاستعادة ${_rollbackSnapshotName ?? ''} '
                            'مثبتة — التراجع متاح حتى أول عملية كتابة.',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _rollback,
                          icon: const Icon(Icons.undo),
                          label: const Text('تراجع عن الاستعادة'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (!locked) ...[
                if (_managers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        'لا مدير نشط في النسخة المستاعدة — استخدم '
                        '«اختيار نسخة أخرى» أو «إعادة المحاولة لاحقاً» '
                        'بعد تفعيل مدير بأداة خارجية.'),
                  )
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _selectedUserId,
                    decoration: const InputDecoration(
                        labelText: 'المستخدم (مدير النسخة)'),
                    items: [
                      for (final (u, _) in _managers)
                        DropdownMenuItem(
                            value: u.id, child: Text(u.name)),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedUserId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'كلمة المرور'),
                    onSubmitted: (_) => _tryLogin(),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _managers.isEmpty ? null : _tryLogin,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('دخول'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _pickAnotherBackup,
                  icon: const Icon(Icons.restore),
                  label: const Text('استعادة نسخة أخرى'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _retryLater,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('إعادة المحاولة لاحقاً'),
                ),
              ],
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_notice!,
                      style: TextStyle(color: cs.error)),
                ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _pickAnotherBackup,
                icon: const Icon(Icons.folder_open),
                label: const Text('اختيار نسخة أخرى'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ملخص ما بعد الاستعادة (§6) — سطر واحد مبسّط، مصفّى بالصلاحيات،
/// بشارة سلامة للجميع وزر تفاصيل لصاحب التقارير.
class _RestoreSummaryDialog extends StatelessWidget {
  final RestoreSummaryFacts facts;
  final String integrity;
  final DateTime? backupAt;
  final String? sourceName;
  final String? deviceName;
  final bool canSeeDetails;
  final VoidCallback onDone;

  const _RestoreSummaryDialog({
    required this.facts,
    required this.integrity,
    required this.backupAt,
    required this.sourceName,
    required this.deviceName,
    required this.canSeeDetails,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = integrity == 'ok'
        ? diqqahLanesOf(context).positive.fg
        : cs.error;
    final badgeLabel =
        integrity == 'ok' ? 'سلامة القاعدة: سليمة' : 'سلامة القاعدة: غير مؤكدة';
    return AlertDialog(
      title: const Text('تمت الاستعادة بنجاح'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.circle, color: badgeColor, size: 12),
              const SizedBox(width: 8),
              Expanded(child: Text(badgeLabel)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'آخر مستند: ${facts.lastDocumentDateText ?? 'لا مستندات'}\n'
            'عدد المستخدمين: ${facts.usersCount}\n'
            'إجمالي الفواتير: ${facts.invoicesCount}',
          ),
          if (canSeeDetails) ...[
            const Divider(),
            Text(
              'تاريخ النسخة: ${backupAt?.toIso8601String() ?? 'غير معروف'}\n'
              'مصدر النسخة: ${sourceName ?? 'غير معروف'}\n'
              'جهاز المصدر: ${deviceName ?? 'غير مسمّى'}\n'
              'إصدار المخطط: ${DiqqahDatabase.schemaVersionValue}',
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: onDone,
          child: const Text('متابعة'),
        ),
      ],
    );
  }
}
