/// قسم النسخ والاستعادة بالإعدادات (س233 — D-230، المرحلة أ/1 من خارطة
/// الطريق الخماسية): بطاقة النسخ الآلي الجديدة (D-232) أول القسم، فوق
/// بطاقة النسخ المجدول القائمة (تكليف 2026-11-13 §2/§8-7) فالنسخة
/// الكاملة (F-012/F-013/D-050/D-060/د11) والاستعادة ونسخة الصور
/// المستقلة (س-130/D-124) — المتن بنصوص دفعاته حرفاً، والقسم شطر
/// «البيانات والأمان» القائم (D-218).
library;

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart' show diqqahLanesOf;
import '../auto_backup_prefs.dart';
import '../backup_center.dart';
import '../backup_reminders.dart';
import '../backups_catalog_screen.dart';
import '../db_key_vault.dart';
import '../device_status.dart';
import '../dq_log.dart';
import '../item_images.dart';
import '../l10n/app_strings.dart';
import 'explanation_disclosure.dart';
import '../storage_manager_screen.dart';
import '../session.dart';

/// اختيار مسار نسخة حرة — ثغرة CI #40/#41 (2026-10-29): الختم بدقة
/// الثانية وD-061 بلاحقة موحدة `.diqqah` يعني أن نسختين متتاليتين في
/// نفس الثانية (نمط الاختبارات والسكربتات لا الإنسان) تولدان الاسم
/// نفسه، وكانت الثانية تدمر الأولى بصمت بإعادة الكتابة فوقها. اللواحق
/// -2 و-3... تفرد الاسم عند التصادم حصراً دون مساس بالصيغة الاعتيادية،
/// والتعرف على النسخة أصلاً من بصمة محتواها لا من اسمها (D-061).
/// الدالة نقية بلا نظام ملفات — الوجود يُمرر إليها ليثبتها الاختبار النقي.
String freeBackupPath(
  String dirPath,
  String stamp,
  bool Function(String path) exists,
) {
  var target = p.join(dirPath, 'diqqah-backup-$stamp.diqqah');
  var n = 2;
  while (exists(target)) {
    target = p.join(dirPath, 'diqqah-backup-$stamp-$n.diqqah');
    n++;
  }
  return target;
}

/// حجم مجلد الصور بالصياغة الإنسانية — نقية للاختبار (س-129: سطر
/// الحجم الحالي للمجلد تحت مربع التضمين). الفراغ «بلا صور بعد».
String formatImagesBytes(int bytes) {
  if (bytes <= 0) return S.noImagesYet;
  final kb = bytes / 1024;
  if (kb < 1024) {
    return S.kilobytesCount(kb.toStringAsFixed(kb < 10 ? 1 : 0));
  }
  final mb = kb / 1024;
  return S.megabytesCount(mb.toStringAsFixed(1));
}

/// قسم النسخ والاستعادة — الآلي أولاً ثم التفاصيل كلها.
class BackupSection extends StatefulWidget {
  final DiqqahDatabase db;

  /// مسار ملف القاعدة الحي — منه يشتق مجلد النسخ ولقطات الرجوع.
  final String dbPath;

  /// بعد استعادة ناجحة: البوابة تعيد بناء القاعدة والشاشات من الملف الجديد.
  final VoidCallback onRestored;

  /// جلسة القارئ — بوابة أزرار الإدارة بالبطاقات (مدير حصراً).
  final SessionInfo? session;

  const BackupSection({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
    required this.session,
  });

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  final _restorePath = TextEditingController();

  /// D-060: للنسخ القديمة v1 حصراً — الجديدة تُفتح بمفتاح البرنامج بلا كلمة.
  final _restorePassword = TextEditingController();

  bool _busy = false;

  /// D-050: التشفير الافتراضي للنسخ الاحتياطية من م1 — الإلغاء قرار واعٍ.
  bool _encryptBackup = true;

  // ── س-129/D-124 (دفعة 10): تضمين الصور في النسخ — افتراضه مفعّل،
  // وتحته سطر حجم مجلد الصور الحي لا صمت.
  bool _includeImages = true;
  int _imagesBytes = 0;
  int _imagesCount = 0;

  // ── P1-أ (س149/D-210): قفل النسخ بكلمة مستخدم اختيارية ورمز استرداد —
  // يُحمل من خزنة الجهاز عند الفتح، والقفل موجود = النسخ الجديدة v3.
  final BackupSecretsStore _secrets = BackupSecretsStore();
  BackupLock? _backupLock;
  final _lockPass1 = TextEditingController();
  final _lockPass2 = TextEditingController();

  // ── د11 (س229/D-225 الجزء الأول): مواد مفاتيح الخزنة — جذر الجهاز
  // العشوائي ورمز الاسترداد المطبوع مرة واحدة: بلا قفل تُكتب النسخ
  // الجديدة بجيل v4 (تُفك هنا صامتاً وبرمز الاسترداد على جهاز آخر).
  // فشل قراءة الخزنة = بلا مواد فتنخفض النسخ v2 موثقة (عرف س149 عينه).
  final VaultBackupKeys _vaultStore = VaultBackupKeys();
  BackupVaultKeys? _vaultKeys;

  @override
  void initState() {
    super.initState();
    _loadImagesInfo();
    _loadBackupLock();
    _loadVaultKeys();
  }

  @override
  void dispose() {
    _restorePath.dispose();
    _restorePassword.dispose();
    _lockPass1.dispose();
    _lockPass2.dispose();
    super.dispose();
  }

  /// P1-أ: حالة القفل من الخزنة — صامتة على الغياب (بلا قفل حالة
  /// طبيعية لا عيب)، وفشل قراءة الخزنة (قناة غائبة بالاختبارات أو
  /// خزنة خاطئة) = بلا قفل عرضاً — البطاقة تظهر الحالة كما هي ولا
  /// ينهي الافتتاح، والإنشاء اليدوي يجرب المسار الصريح عند الحاجة.
  Future<void> _loadBackupLock() async {
    BackupLock? lock;
    try {
      lock = await _secrets.loadLock();
    } catch (_) {
      lock = null;
    }
    if (!mounted) return;
    setState(() => _backupLock = lock);
  }

  /// د11: مواد الخزنة عند الفتح — تولَّد إن غابت (أول تشغيل بهذه
  /// الشاشة أو قبل أول نسخة) فبطاقة الرمز تظهر فوراً، وقراءتها الفاشلة
  /// (قناة غائبة بالاختبارات) = بلا مواد فتنخفض النسخ v2 موثقة (نمط
  /// _loadBackupLock عينه — صامتة لا تكسر الافتتاح).
  Future<void> _loadVaultKeys() async {
    BackupVaultKeys? keys;
    try {
      keys = await _vaultStore.loadOrCreate();
    } catch (_) {
      keys = null;
    }
    if (!mounted) return;
    setState(() => _vaultKeys = keys);
  }

  /// حجم مجلد الصور الحي — يُقرأ عند الفتح وبعد كل استعادة (onRestored
  /// يعيد بناء الشاشة فتُقرأ من جديد).
  void _loadImagesInfo() {
    final dir = Directory(imagesDirFor(widget.dbPath));
    var bytes = 0;
    var count = 0;
    if (dir.existsSync()) {
      for (final e in dir.listSync(recursive: true)) {
        if (e is File) {
          bytes += e.lengthSync();
          count++;
        }
      }
    }
    if (mounted) {
      setState(() {
        _imagesBytes = bytes;
        _imagesCount = count;
      });
    }
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// D-056: استيراد بالتصفح — منتقي النظام يرى كل مكان (التنزيلات،
  /// Drive، مديرات الملفات) بلا صلاحيات تخزين وبلا كتابة مسار يدوياً.
  /// D-057: نقطة البداية مجلد التنزيلات حيث تدعمها المنصة.
  Future<void> _pickBackupFile() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        initialDirectory: defaultImportDirectory(
          userProfile: Platform.environment['USERPROFILE'],
          home: Platform.environment['HOME'],
        ),
      );
      final path = result?.paths.single;
      if (path == null) return; // إلغاء المستخدم — لم يحدث شيء
      if (!mounted) return;
      setState(() => _restorePath.text = path);
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.pick');
      messenger.showSnackBar(
        SnackBar(content: Text(S.filePickerFailed(e, dqTag(e)))),
      );
    }
  }

  /// D-056: تصدير النسخة بنافذة المشاركة — تخرجها من مجلد التطبيق
  /// المحجوب إلى مكان يختاره المالك (تنزيلات/سحابة/رسالة لنفسه).
  Future<void> _exportBackup(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Share.shareXFiles(
        [XFile(path)],
        subject: p.basename(path),
        text: S.backupDefaultName,
      );
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.export');
      messenger.showSnackBar(
        SnackBar(content: Text(S.backupExportFailed(e, dqTag(e)))),
      );
    }
  }

  /// D-050/D-060: النسخ الافتراضية مشفرة بمفتاح البرنامج — بلا أي كلمة،
  /// والإلغاء الواعي: من ألغى التشفير يُحذَّر قبل إنشاء نسخة خام.
  Future<void> _backup() => _createManualBackup(includeImages: _includeImages);

  // ── P1-أ (س149/D-210): إدارة قفل النسخ — تعيين/عرض الرمز/إزالة ──

  /// تعيين القفل: كلمة (8 محارف فأكثر بتأكيدها) + توليد رمز استرداد
  /// عشوائي يُعرض للنسخ الخارجي ثم يُحفظ بالخزنة — وبعده النسخ الجديدة
  /// تُكتب بجيل v3 المقفل حصراً.
  Future<void> _setBackupLock() async {
    _lockPass1.clear();
    _lockPass2.clear();
    final formKey = GlobalKey<FormState>();
    final set = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.lockBackupWithPassword),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  S.lockBackupExplainer),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lockPass1,
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 8) ? S.eightCharsHint : null,
                decoration: const InputDecoration(
                  labelText: S.passwordWithHint,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lockPass2,
                obscureText: true,
                validator: (v) => (v != _lockPass1.text) ? S.confirmMismatchShort : null,
                decoration: const InputDecoration(
                  labelText: S.confirmPassword,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.revertAction),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text(S.generateRecoveryCode),
          ),
        ],
      ),
    );
    if (set != true || !mounted) return;
    // الرمز يُولد عشوائياً ويُعرض ليعينه المالك خارج الجهاز — وبعدها
    // يبقى قابلاً للعرض من الخزنة (عرف BackupSecretsStore الصادق).
    final recovery = BackupCipher.generateRecoveryCode();
    final lock = BackupLock(password: _lockPass1.text, recoveryCode: recovery);
    try {
      await _secrets.saveLock(lock);
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.lock');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(S.vaultLockFailed(e, dqTag(e)))),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _backupLock = lock);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.recoveryCodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                S.recoveryCodeBody),
            const SizedBox(height: 12),
            SelectableText(recovery,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: recovery));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(S.recoveryCodeCopied)),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text(S.copyAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(S.recordedIt),
          ),
        ],
      ),
    );
  }

  /// عرض رمز الاسترداد المخزن — القفل قائم فقط.
  Future<void> _viewRecoveryCode() async {
    final lock = _backupLock;
    if (lock == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.recoveryCodeLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(S.recoveryCodeShort),
            const SizedBox(height: 12),
            SelectableText(lock.recoveryCode,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lock.recoveryCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(S.recoveryCodeCopied)),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text(S.copyAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(S.okAction),
          ),
        ],
      ),
    );
  }

  /// د11: قراءة الخزنة عند الاستعادة — استدعاء حي لا لقطة (نمط loadLock
  /// بالمستودع): فاشلة = null فمسار الجيل يطلب الرمز المكتوب.
  Future<BackupVaultKeys?> _tryLoadVault() async {
    try {
      return await _vaultStore.load();
    } catch (_) {
      return null;
    }
  }

  /// د11: عرض رمز استرداد الخزنة — يعيد طباعته عند الطلب (أما الطباعة
  /// التلقائية فمرة واحدة عند أول تشغيل من جذر الإقلاع — main.dart)،
  /// بعرف الصدق ذاته: يبقى قابلاً للعرض والنسخ من هنا دائماً.
  Future<void> _viewVaultRecoveryCode() async {
    final keys = _vaultKeys;
    if (keys == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.vaultRecoveryCode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                S.vaultRecoveryCodeBody),
            const SizedBox(height: 12),
            SelectableText(keys.recoveryCode,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: keys.recoveryCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(S.recoveryCodeCopied)),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text(S.copyAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(S.okAction),
          ),
        ],
      ),
    );
  }

  /// إزالة القفل: النسخ الجديدة تعود لجيل الخزنة v4 (مفتاح هذا الجهاز
  /// ورمز الاسترداد) — والمقفلة القائمة تبقى بكلمتها ورمزها (تُفك بهما
  /// لا بشيء من هنا).
  Future<void> _clearBackupLock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.removeLockTitle),
        content: const Text(
            S.removeLockExplainer),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.revertAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(S.removeLockAction),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _secrets.clearLock();
    if (!mounted) return;
    setState(() => _backupLock = null);
  }

  /// إنشاء النسخة اليدوية — مسار واحد لزر البطاقة القائم (يتبع مربعيها)
  /// ولزر «أنشئ نسخة الآن» بالتذكيرات الذكية (مع المرفقات دائماً — غنى
  /// نقطة الاستعادة: تذكير 30 يوماً وتذكير المرفقات كلاهما يريد أوسع
  /// نسخة والقرار الافتراضي الأماني لا التقتير).
  Future<void> _createManualBackup({required bool includeImages}) async {
    if (!_encryptBackup) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(S.unencryptedBackup),
          content: const Text(
              S.unencryptedWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(S.revertAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(S.continueUnencrypted),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // D-061: لاحقة النسخة الخاصة بالبرنامج — بطاقة تعريف للإنسان
      // والنظام؛ والتعرف الحقيقي عند الاستعادة من بصمة المحتوى.
      // freeBackupPath يمنع الاكتساب الصامت فوق نسخة قائمة عند تطابق
      // الختم في نفس الثانية — علّة CI #40/#41 (2026-10-29).
      final target = freeBackupPath(
        p.dirname(widget.dbPath),
        _stamp(),
        (path) => File(path).existsSync(),
      );
      // س-129/D-124: الصور ملف ثانٍ مجاور بنفس المفتاح — ملف القاعدة
      // كما وُلد لا يُلمس (VACUUM INTO/س-01) فلا انتفاخ ولا كسر ذرية.
      // P1-أ/P1-ب (س149): قفل الخزنة موجود = النسخة وملف صورها بجيل
      // v3 المقفل، ومفتاح الصور يفك الملفات المشفرة عند الجمع.
      // د11 (س229): وبلا قفل ومواد الخزنة حاضرة = جيل v4 (فتح صامت
      // هنا وبرمز الاسترداد على جهاز آخر — N-005 يلتئم).
      // د11 الجزء الثاني (س230): والجذر الحي حاضراً يرتفع الجيل إلى
      // السجل الرابع (v6 مع القفل / v5 بلا) فتسافر سجلات القاعدة معها.
      final liveLogRoot = await loadLiveLogRootOrNull();
      await backupTo(
        widget.db,
        target,
        encrypted: _encryptBackup,
        includeImages: includeImages,
        imagesDir: Directory(imagesDirFor(widget.dbPath)),
        lock: _encryptBackup ? _backupLock : null,
        vaultKeys:
            _encryptBackup && _backupLock == null ? _vaultKeys : null,
        logRootKey: _encryptBackup ? liveLogRoot : null,
        imagesCipher: ItemImagesStore.cipher,
      );
      // تكليف 2026-11-13: تبنّي النسخة اليدوية بالكتالوج الجانبي —
      // تذكير المرفقات الذكي يقرأ أحدث نسخة تضمها فوراً.
      await BackupCenter.instance
          ?.registerManualBackup(target, includeImages);
      if (!mounted) return;
      final imagesPath = imagesSiblingPath(target);
      final hasImagesFile = File(imagesPath).existsSync();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(S.backupCreated),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(!_encryptBackup
                  ? S.backupFilePlain
                  : _backupLock != null
                      ? S.backupFileLocked(liveLogRoot != null ? 'v6' : 'v3')
                      : _vaultKeys != null
                          ? S.backupFileVaulted(liveLogRoot != null ? 'v5' : 'v4')
                          : S.backupFileProgramKey),
              const SizedBox(height: 8),
              // س-129: تصريح محتوى النسخة بالصور لا صمت أبداً.
              Text(hasImagesFile
                  ? S.backupIncludesImages(_imagesCount, formatImagesBytes(_imagesBytes))
                  : S.backupNoImages),
              const SizedBox(height: 12),
              const Text(S.backupPathLabel),
              SelectableText(target),
              if (hasImagesFile) ...[
                const SizedBox(height: 8),
                const Text(S.imagesFileLabel),
                SelectableText(imagesPath),
              ],
            ],
          ),
          actions: [
            // D-056: إخراج النسخة من مجلد التطبيق — جوهر الإصلاح الأندرويدي
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _exportBackup(
                    hasImagesFile ? imagesPath : target);
              },
              child: const Text(S.exportBackupAction),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(S.okAction),
            ),
          ],
        ),
      );
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.backup');
      messenger.showSnackBar(
        SnackBar(content: Text(S.backupCreateFailed(e, dqTag(e)))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final path = _restorePath.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(S.chooseBackupPathFirst)),
      );
      return;
    }

    // F-013: تأكيد مزدوج — والإلغاء في أي لحظة لم يحدث شيئاً (إلغاء آمن)
    final first = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(S.restoreBackupTitle),
        content: const Text(
            S.restoreBackupBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(S.continueAction),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(S.finalConfirmTitle),
        content: const Text(S.replaceAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.safeCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(S.finalRestore),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    RestoreCandidate? candidate;
    try {
      // P1-أ (س149): الجيل المقفل v3 يُفك بأسرار خزنة هذا الجهاز أولاً
      // (نفس الجهاز يفتح صامتاً) — وفشلها أو غيابها يعيد المحاولة بما
      // كتبه المالك (الحقل يقبل الكلمة أو رمز الاسترداد، وكلتاهما
      // تُجرّبان بوسم GCM حاكم). v1/v2 بمساريهما القديمين حرفاً.
      // د11 (س229): وجيل الخزنة v4 يُفك بمفتاح هذا الجهاز صمتاً —
      // وعلى جهاز آخر يكتب المالك رمز الاسترداد بالحقل ذاته.
      final typed = _restorePassword.text.isEmpty ? null : _restorePassword.text;
      final stored = typed == null ? await _secrets.loadLock() : null;
      // س230: مواد خزنة هذا الجهاز تُحل دائماً — كلمة المستخدم للمصدر
      // لا للقطة الرجوع: اللقطة تُغلَّف بخزنة الجهاز ذاته (v5 بالجذر)
      // فتسافر سجلاتها معها ويعمل التراجع على أي جهاز بالرمز.
      final storedVault = await _tryLoadVault();
      final liveLogRoot = await loadLiveLogRootOrNull();
      try {
        candidate = await prepareRestore(
          path,
          password: typed ?? stored?.password,
          recoveryCode: typed ?? stored?.recoveryCode,
          vaultRootKey: storedVault?.rootKey,
          localLogRootKey: liveLogRoot,
          appSchemaVersion: widget.db.schemaVersion,
        );
      } on BackupCipherException {
        if (typed == null && stored == null && storedVault == null) rethrow;
        if (typed == null) rethrow; // القفل المخزن خالف — بلا بديل مكتوب
        // إعادة المحاولة بما كتبه المالك وحده لا فوق أسرار الخزنة.
        candidate = await prepareRestore(
          path,
          password: typed,
          recoveryCode: typed,
          vaultRootKey: storedVault?.rootKey,
          localLogRootKey: liveLogRoot,
          appSchemaVersion: widget.db.schemaVersion,
        );
      }
      if (!mounted) return;
      // س-130/D-124: تصريح محتوى النسخة بالصور **قبل** أي تنفيذ —
      // فلا فجوة صامتة أبداً، والتراجع هنا لم يُمسّ شيئاً.
      final currentImages = Directory(imagesDirFor(widget.dbPath));
      final currentHasFiles = currentImages.existsSync() &&
          currentImages.listSync(recursive: true).any((e) => e is File);
      final declare = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(S.backupContentTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(candidate!.hasImages
                  ? S.restoreIncludesImages(candidate.imagesFiles.length)
                  : S.restoreNoImages),
              if (!candidate.hasImages && currentHasFiles) ...[
                const SizedBox(height: 8),
                const Text(
                    S.restoreImagesWillEmpty),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(S.revertAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(S.continueAction),
            ),
          ],
        ),
      );
      if (declare != true) {
        candidate.dispose();
        return; // إلغاء آمن — لم يُمسّ شيئاً
      }
      String snapshotPath;
      try {
        snapshotPath = await applyRestore(
          db: widget.db,
          candidate: candidate,
          currentDbPath: widget.dbPath,
          imagesDir: currentImages,
          vaultKeys: storedVault,
          logRootKey: liveLogRoot,
          imagesCipher: ItemImagesStore.cipher,
        );
      } finally {
        candidate.dispose();
      }
      if (!mounted) return;
      _loadImagesInfo();
      // F-154: سطر الإحالة — أين نسخة الرجوع
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(S.restoreDone),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(S.restoreRollbackAt),
              const SizedBox(height: 12),
              SelectableText(snapshotPath),
              if (File(imagesSiblingPath(snapshotPath)).existsSync()) ...[
                const SizedBox(height: 8),
                const Text(S.restoreRollbackImagesAt),
                SelectableText(imagesSiblingPath(snapshotPath)),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(S.continueAction),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.onRestored();
    } on BackupNewerSchemaException catch (e) {
      await dqLog(widget.db, e, context: 'settings.restore');
      messenger.showSnackBar(
          SnackBar(content: Text('${e.toString()}${dqTag(e)}')));
    } on BackupCipherException catch (e) {
      await dqLog(widget.db, e, context: 'settings.restore');
      messenger.showSnackBar(
          SnackBar(content: Text('${e.message}${dqTag(e)}')));
    } on CorruptBackupException catch (e) {
      await dqLog(widget.db, e, context: 'settings.restore');
      messenger.showSnackBar(
          SnackBar(content: Text('${e.message}${dqTag(e)}')));
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.restore');
      messenger.showSnackBar(SnackBar(
          content: Text(S.restoreFailed(e, dqTag(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// س-130: نسخة الصور المستقلة — مجلد الصور وحده في ملف بنفس التغليف.
  Future<void> _backupImagesStandalone() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dirPath = p.dirname(widget.dbPath);
      // اسم مستقل عن نسخ القاعدة — واللواحق -2 و-3 تفرد الاسم عند
      // التصادم (نمط freeBackupPath — علّة CI #40/#41).
      var target = p.join(dirPath, 'diqqah-images-${_stamp()}.diqqah.images');
      var n = 2;
      while (File(target).existsSync()) {
        target =
            p.join(dirPath, 'diqqah-images-${_stamp()}-$n.diqqah.images');
        n++;
      }
      // P1-أ/P1-ب (س149): نفس قفل النسخ ومفتاح الصور — أداة الصور
      // المستقلة لا تنفلت من عالم الجيل المقفل.
      await backupImagesTo(
        Directory(imagesDirFor(widget.dbPath)),
        target,
        encrypted: _encryptBackup,
        lock: _encryptBackup ? _backupLock : null,
        imagesCipher: ItemImagesStore.cipher,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(S.imagesBackupCreated),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.imagesFileStandalone(_imagesCount, formatImagesBytes(_imagesBytes))),
              const SizedBox(height: 12),
              SelectableText(target),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _exportBackup(target);
              },
              child: const Text(S.exportBackupAction),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(S.okAction),
            ),
          ],
        ),
      );
    } on CorruptBackupException catch (e) {
      await dqLog(widget.db, e, context: 'settings.images_backup');
      messenger.showSnackBar(
          SnackBar(content: Text('${e.message}${dqTag(e)}')));
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.images_backup');
      messenger.showSnackBar(
        SnackBar(content: Text(S.imagesBackupFailed(e, dqTag(e)))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// س-130: استعادة صور من ملف مستقل — تستبدل مجلد الصور بلا مساس
  /// بالبيانات، وتصرّح بالعدد لا تسكت.
  Future<void> _restoreImagesStandalone() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        initialDirectory: defaultImportDirectory(
          userProfile: Platform.environment['USERPROFILE'],
          home: Platform.environment['HOME'],
        ),
      );
      final path = result?.paths.single;
      if (path == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(S.restoreImagesTitle),
          content: const Text(
              S.restoreImagesBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(S.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(S.restoreImagesAction),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() => _busy = true);
      // P1-أ/P1-ب (س149): مواد الفك كما في الاستعادة الكاملة — القفل
      // المخزن صامتاً ثم المكتوب، والكتابة بمفتاح هذا الجهاز.
      // د11 (س229): ونسخ الخزنة v4 بمفتاح هذا الجهاز (أو برمز
      // الاسترداد المكتوب من جهاز آخر).
      final typed = _restorePassword.text.isEmpty ? null : _restorePassword.text;
      final stored = typed == null ? await _secrets.loadLock() : null;
      final storedVault = typed == null ? await _tryLoadVault() : null;
      final count = await restoreImagesFrom(
        path,
        Directory(imagesDirFor(widget.dbPath)),
        password: typed ?? stored?.password,
        recoveryCode: typed ?? stored?.recoveryCode,
        vaultRootKey: storedVault?.rootKey,
        imagesCipher: ItemImagesStore.cipher,
      );
      if (!mounted) return;
      _loadImagesInfo();
      messenger.showSnackBar(SnackBar(
        content: Text(S.imagesRestored(count)),
      ));
    } on CorruptBackupException catch (e) {
      await dqLog(widget.db, e, context: 'settings.images_restore');
      messenger.showSnackBar(
          SnackBar(content: Text('${e.message}${dqTag(e)}')));
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.images_restore');
      messenger.showSnackBar(
        SnackBar(content: Text(S.imagesRestoreFailed(e, dqTag(e)))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// فتح كتالوج النسخ — مسار واحد لزر البطاقة وأزرار التذكيرات الذكية.
  void _openBackupsCatalog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BackupsCatalogScreen(
          db: widget.db,
          dbPath: widget.dbPath,
          onRestored: widget.onRestored,
        ),
      ),
    );
  }

  /// بطاقة النسخ المجدول: تذكيرات ذكية بواجهة أغنى (دفعة 2 — تكليف
  /// §3: صفوف ببيانات حية وأفعال مباشرة فوق شارة المركز)، حالة كل
  /// دورة، حصة المجلد بسقفها القابل للضبط (مدير)، ومدخل الكتالوج
  /// (قائمة/تحقق/استعادة/تصدير/حذف).
  Widget _scheduledBackupsCard() {
    final center = BackupCenter.instance;
    final catalog = center?.store?.catalog;
    final lastSuccess = catalog?.lastSuccess ?? const {};
    final manager = widget.session?.permissions.isAll ?? false;
    String fmt(DateTime? t) => t == null
        ? S.notCreatedYet
        : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.scheduledBackupTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            // س198 (م17): سطر التلخيص والكشف التدريجي — دوريات النسخ
            // وشروطها كلها باقية حرفاً خلف التوسعة.
            ExplanationDisclosure(
              summary: S.scheduledBackupBody,
              details: S.scheduledBackupPeriods,
            ),
            const SizedBox(height: 8),
            // التذكيرات الذكية — الواجهة الأغنى (دفعة 2، تكليف §3):
            // صفوف ببيانات حية (الأيام والتواريخ والنسب) وأفعال مباشرة،
            // تتجدد لحظة تجدد شارة المركز بعد كل نسخة وإقلاع وضبط.
            if (center != null)
              BackupRemindersPanel(
                healthListenable: center.health,
                onCreateNow: () => _createManualBackup(includeImages: true),
                onOpenCatalog: _openBackupsCatalog,
                busy: _busy,
              ),
            for (final kind in BackupScheduleKind.values)
              if (kind.isScheduled || kind == BackupScheduleKind.annual)
                Text(
                    '${kind.label}: ${fmt(lastSuccess[kind])}'),
            const SizedBox(height: 8),
            Text(center == null
                ? S.trialModeDeferred
                : S.backupQuotaGb((center.quotaBytes / (1024 * 1024 * 1024)).toStringAsFixed(0))),
            if (manager && center != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final gb in const [1, 2, 4, 8])
                    ChoiceChip(
                      label: Text('${gb}GB'),
                      selected: center.quotaBytes == gb * 1024 * 1024 * 1024,
                      onSelected: (_) {
                        setState(() {});
                        center.quotaBytes = gb * 1024 * 1024 * 1024;
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _openBackupsCatalog,
              icon: const Icon(Icons.list_alt),
              label: const Text(S.backupsCatalogTitle),
            ),
            const SizedBox(height: 8),
            // د-4/د-8 (§25.8، س136): قسم إدارة التخزين — شاشة مستقلة
            // بنفسها (ليست بطاقة داخل الإعدادات) والمُدخل بنمط التشخيص.
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StorageManagerScreen(
                      db: widget.db,
                      dbPath: widget.dbPath,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text(S.storageManagerTitle),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // تكليف 2026-11-13 (§2/§8-7): بوابة وحدة backup القابلة للمنح تحكم
    // بطاقتي الجدولة — المجدولة القائمة والآلية الجديدة (سياستها جدولة
    // النسخ بيد صاحب الوحدة) — والنسخة الكاملة والاستعادة بلا بوابة
    // كما كانا (F-012 متاحة فوراً بعد التهيئة — س-01).
    final canBackup = widget.session?.permissions.allows('backup') ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── س233 (D-232 — المرحلة أ/3): بطاقة النسخ الآلي أول القسم —
        // المفتاح الرئيسي وخانات الدورات وعرض الحالة الحية.
        if (canBackup) ...[
          _AutoBackupCard(
            onCreateNow: () => _createManualBackup(includeImages: true),
            busy: _busy,
          ),
          const SizedBox(height: 16),
        ],
        if (canBackup) _scheduledBackupsCard(),
        const SizedBox(height: 16),
        // ── النسخة الكاملة (F-012/D-050/D-060/د11) — المتن حرفاً.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.fullBackupTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                // س198 (م17): سطر التلخيص والكشف التدريجي — الشرح
                // الكامل بلاحقة البرنامج وشروط التشفير خلف التوسعة.
                ExplanationDisclosure(
                  summary: S.fullBackupBody,
                  details: S.fullBackupBodyLong,
                ),
                const SizedBox(height: 4),
                // D-050: صندوق الاختيار مشدود افتراضياً — النسخة بلا
                // تشفير لا تُنشأ إلا بعد تحذير صريح (الإلغاء الواعي).
                // D-060: المفتاح من البرنامج حصراً — لا كلمة مرور.
                CheckboxListTile(
                  value: _encryptBackup,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _encryptBackup = v ?? true),
                  title: const Text(S.programKeyEncryption),
                  subtitle: const Text(
                      S.programKeyDefault),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                // س-129/D-124 (دفعة 10): تضمين الصور في ملف ثانٍ —
                // افتراضه مفعّل وتحته سطر حجم المجلد الحي لا صمت.
                CheckboxListTile(
                  value: _includeImages,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _includeImages = v ?? true),
                  title: const Text(S.includeItemImages),
                  subtitle: Text(
                      S.itemImagesSummary(formatImagesBytes(_imagesBytes), _imagesCount > 0 ? S.filesCountSuffix(_imagesCount) : '')),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                // ── P1-أ (س149/D-210): قفل النسخ بكلمة مستخدم اختيارية
                // ورمز استرداد — بلا قفل الجيل v4 بمفاتيح الخزنة (د11)
                // وبقفل الجيل v3 المقفل بكلمة المالك نفسها.
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                        _backupLock != null
                            ? Icons.lock
                            : Icons.lock_open,
                        size: 18,
                        color: _backupLock != null
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _backupLock != null
                            ? S.v3LockedSummary
                            : _vaultKeys != null
                                ? S.v4VaultSummary
                                : S.v2PlainSummary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_backupLock == null)
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _setBackupLock,
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text(S.lockBackupWithPassword),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _viewRecoveryCode,
                          icon: const Icon(Icons.key, size: 18),
                          label: const Text(S.showRecoveryCode),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _clearBackupLock,
                          icon: const Icon(Icons.lock_open, size: 18),
                          label: const Text(S.removeLockAction),
                        ),
                      ),
                    ],
                  ],
                ),
                // ── د11 (س229/D-225 الجزء الأول): بطاقة رمز الخزنة —
                // إعادة عرض الرمز المطبوع مرة واحدة عند أول تشغيل
                // (بعرف الصدق: يبقى قابلاً للعرض والنسخ دائماً).
                if (_vaultKeys != null) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                            S.vaultRecoverySummary),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : _viewVaultRecoveryCode,
                        icon: const Icon(Icons.key, size: 18),
                        label: const Text(S.showCodeAction),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _backup,
                  child: const Text(S.createBackupAction),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── الاستعادة (F-013) ونسخ الصور المستقلة — المتن بنصوصهما حرفاً.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.fullRestoreAction,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.fullRestoreBody,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _restorePath,
                  decoration: InputDecoration(
                    labelText: S.backupFilePathLabel,
                    border: const OutlineInputBorder(),
                    // D-056: على أندرويد مسار data مخفي لا يُكتب يدوياً —
                    // التصفح من داخل التطبيق هو الطريق القياسي الوحيد.
                    helperText: S.mobileBrowseHint,
                    suffixIcon: IconButton(
                      tooltip: S.chooseBackupFile,
                      icon: const Icon(Icons.folder_open),
                      onPressed: _busy ? null : _pickBackupFile,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _restorePassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText:
                        S.passwordOrCodeHint,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _busy ? null : _restore,
                  child: const Text(S.restoreEllipsis),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── نسخة صور مستقلة (س-130، D-124) — أداة مكمّلة لا بديل:
        // مجلد الصور وحده في ملف، تُستعاد منفردة بلا مساس بالبيانات.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.standaloneImagesBackup,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.standaloneImagesBody,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _backupImagesStandalone,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text(S.copyImagesAction),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _restoreImagesStandalone,
                        icon: const Icon(Icons.restore),
                        label: const Text(S.restoreImagesShort),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// س233 (D-232 — المرحلة أ/3): بطاقة النسخ الآلي — المفتاح الرئيسي
/// وخانات ساعي/يومي/شهري وخانتا متقدمة أسبوعي/سنوي، وعرض حي لآخر
/// نسخة ناجحة والموعد القادم والحصة، ونص صدق «يعمل أثناء تشغيل
/// التطبيق»، وتنبيه بارز عند الإيقاف — والسياسة تخزين أجهزة
/// (auto_backup_prefs) تراها مرشحة المركز لحظياً.
class _AutoBackupCard extends StatefulWidget {
  final VoidCallback onCreateNow;
  final bool busy;

  const _AutoBackupCard({required this.onCreateNow, required this.busy});

  @override
  State<_AutoBackupCard> createState() => _AutoBackupCardState();
}

class _AutoBackupCardState extends State<_AutoBackupCard> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final center = BackupCenter.instance;
    final lanes = diqqahLanesOf(context);
    String fmtDay(DateTime? t) => t == null
        ? S.notCreatedYet
        : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    String fmtClock(DateTime? t) => t == null
        ? S.notCreatedYet
        : '${fmtDay(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final catalog = center?.store?.catalog;
    final health = center?.health.value;
    final quotaUsed = (health != null && center != null)
        ? center.quotaBytes * health.quotaUsedFraction
        : null;
    return Card(
      key: const ValueKey('settings_auto_backup'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.autoBackupTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            // المفتاح الرئيسي — وعند الإيقاف تنبيه التذكير البارز (خطة
            // المرحلة أ/3 حرفاً: لا نسخ تلقائية حتى التفعيل).
            ValueListenableBuilder<bool>(
              valueListenable: autoBackupEnabled,
              builder: (context, enabled, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const ValueKey('settings_auto_backup_master'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(S.autoBackupTitle),
                    subtitle: Text(S.autoBackupWorksWhileRunning),
                    value: enabled,
                    onChanged: widget.busy
                        ? null
                        : (v) => setAutoBackupEnabled(v),
                  ),
                  if (!enabled)
                    Padding(
                      key: const ValueKey(
                          'settings_auto_backup_off_warning'),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18, color: lanes.attention.fg),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              S.autoBackupOffWarning,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: lanes.attention.fg),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // خانات الدورات — ساعي/يومي/شهري ظاهرة، وأسبوعي/سنوي خلف
            // كشف «خيارات متقدمة»، وعند التفعيل أول نسخة يومية عند
            // الدخول إلزاماً (لحاق أول التشغيل القائم §8-1).
            ValueListenableBuilder<Set<BackupScheduleKind>>(
              valueListenable: autoBackupKinds,
              builder: (context, kinds, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (kind, label, key) in const [
                    (BackupScheduleKind.hourly, S.autoBackupHourly,
                        'settings_auto_backup_hourly'),
                    (BackupScheduleKind.daily, S.autoBackupDaily,
                        'settings_auto_backup_daily'),
                    (BackupScheduleKind.monthly, S.autoBackupMonthly,
                        'settings_auto_backup_monthly'),
                  ])
                    CheckboxListTile(
                      key: ValueKey(key),
                      value: kinds.contains(kind),
                      onChanged: widget.busy
                          ? null
                          : (v) => setAutoBackupKind(kind, v ?? true),
                      title: Text(label),
                      subtitle: kind == BackupScheduleKind.daily
                          ? const Text(S.autoBackupFirstDailyHint)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _advancedOpen = !_advancedOpen),
                      icon: Icon(_advancedOpen
                          ? Icons.expand_less
                          : Icons.expand_more),
                      label: Text(S.autoBackupAdvanced),
                    ),
                  ),
                  if (_advancedOpen)
                    for (final (kind, label, key) in const [
                      (BackupScheduleKind.weekly, S.autoBackupWeekly,
                          'settings_auto_backup_weekly'),
                    ])
                      CheckboxListTile(
                        key: ValueKey(key),
                        value: kinds.contains(kind),
                        onChanged: widget.busy
                            ? null
                            : (v) => setAutoBackupKind(kind, v ?? true),
                        title: Text(label),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                  if (_advancedOpen)
                    ValueListenableBuilder<bool>(
                      valueListenable: autoBackupAnnualAtClose,
                      builder: (context, annualAtClose, _) =>
                          CheckboxListTile(
                        key: const ValueKey(
                            'settings_auto_backup_annual'),
                        value: annualAtClose,
                        onChanged: widget.busy
                            ? null
                            : (v) =>
                                setAutoBackupAnnualAtClose(v ?? true),
                        title: const Text(S.autoBackupYearly),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            // العرض الحي — آخر نسخة ناجحة والموعد القادم (بمعاون المجال
            // nextAutoDueUtc) والحصة المستعملة من سقفها؛ والمركز غائب
            // (اختبارات) فألسنة الغياب الصادقة.
            ListenableBuilder(
              listenable: Listenable.merge([
                autoBackupEnabled,
                autoBackupKinds,
                center?.health,
              ]),
              builder: (context, _) {
                final last = catalog?.latestAnyUtc();
                final next = (center == null || catalog == null)
                    ? null
                    : nextAutoDueUtc(
                        nowUtc: center.nowUtc(),
                        nowLocal: center.nowLocal(),
                        lastSuccess: catalog.lastSuccess,
                        enabledKinds: autoBackupKinds.value,
                      );
                final nextText = next == null
                    ? S.notCreatedYet
                    : !next.isAfter(center?.nowUtc() ??
                        DateTime.now().toUtc())
                        ? S.autoBackupDueNow
                        : fmtClock(next);
                final quotaText = center == null
                    ? S.autoBackupQuota('—', '—')
                    : S.autoBackupQuota(
                        ((quotaUsed ?? 0) / (1024 * 1024 * 1024))
                            .toStringAsFixed(1),
                        (center.quotaBytes / (1024 * 1024 * 1024))
                            .toStringAsFixed(0));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(S.autoBackupLastSuccess(fmtDay(last))),
                    const SizedBox(height: 4),
                    Text(S.autoBackupNextDue(nextText)),
                    const SizedBox(height: 4),
                    Text(quotaText),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
