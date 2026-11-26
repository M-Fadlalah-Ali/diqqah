/// كتالوج النسخ (تكليف §8-7): قائمة النسخ كلها — المدارة والممسوحة
/// (يدوية/قبل-استعادة/preup) بتاريخها ونوعها وحجمها وحالة تحققها
/// ومسارها — وأزرار: تحقق (ب طبقة النوع)، استعادة (مدير بتأكيد مزدوج)،
/// تصدير (نافذة المشاركة D-056)، حذف (مدير بتأكيد).
library;

import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'adaptive.dart';
import 'backup_center.dart';
import 'app_theme.dart';
import 'restore_gate_screen.dart' show runRestoreFlow;
import 'session.dart';
import 'dq_log.dart';

/// شارة لافتة النافذة المفتوحة بالكتالوج.
const String _rollbackBannerTitle = 'نافذة التراجع مفتوحة';

/// رسالة انتهاء النافذة — لفظ §25.7 الموثق حرفاً.
const String _rollbackClosedMessage =
    'لا تراجع بعد الآن — تصحيح أو استعادة واعية';

class BackupsCatalogScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final String dbPath;
  final void Function() onRestored;

  const BackupsCatalogScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
  });

  @override
  State<BackupsCatalogScreen> createState() => _BackupsCatalogScreenState();
}

class _BackupsCatalogScreenState extends State<BackupsCatalogScreen> {
  GfsBackupStore? _store;
  List<ScannedSnapshotRow> _snapshots = const [];
  bool _loading = true;

  /// د-3 (س136): حالة نافذة التراجع — مفتوحة زرٌ، مغلقة رسالة صريحة،
  /// غائبة لا لافتة إطلاقاً.
  RollbackWindowState? _window;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final store = BackupCenter.instance?.store ??
        await GfsBackupStore.open(
          backupsDir: Directory(p.join(
              Directory(widget.dbPath).parent.path, 'backups')),
          dbDir: Directory(Directory(widget.dbPath).parent.path),
          deviceIdFull: await widget.db.deviceId(),
          schemaVersion: DiqqahDatabase.schemaVersionValue,
          appVersion: kAppVersion,
        );
    final snaps = await store.scanSnapshots();
    // الحارس يقيّم هنا: أول كتابة تتجاوز خط الأساس تُغلق وتسجل الحدث.
    RollbackWindowState? window;
    try {
      window = await widget.db.rollbackWindow();
    } catch (e) {
      await dqLog(widget.db, e, context: 'backups.reload');
      window = null;
    }
    if (!mounted) return;
    setState(() {
      _store = store;
      _snapshots = snaps;
      _window = window;
      _loading = false;
    });
  }

  /// أسماء أرضية النسخ المحمية (د-4) — آخر نسخة من كل نوع لا تُحذف
  /// من داخل التطبيق مطلقاً.
  Set<String> _floorNames() =>
      protectedFloorFileNames(_store?.catalog.entries ?? const []);

  Future<void> _verify(BackupCatalogEntry entry) async {
    final store = _store;
    if (store == null) return;
    final outcome = entry.kind == BackupScheduleKind.hourly ||
            entry.kind == BackupScheduleKind.manual
        ? await store.verifyQuick(_pathOf(entry))
        : await store.verifyFull(_pathOf(entry));
    store.catalog.addEntry(entry.copyWith(
      verifyState: outcome.ok ? outcome.state : BackupVerifyState.failed,
      sha256Hex: outcome.sha256Hex ?? entry.sha256Hex,
      schemaVersion: outcome.schemaVersion ?? entry.schemaVersion,
    ));
    await store.saveCatalog();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(outcome.ok
            ? 'التحقق ناجح (${outcome.state == BackupVerifyState.full ? 'كامل' : 'سريع'})'
            : 'فشل التحقق: ${outcome.reason ?? ''}')));
  }

  String _pathOf(BackupCatalogEntry e) => p.join(
      e.folderId == 'backups'
          ? _store!.backupsDir.path
          : _store!.dbDir.path,
      e.fileName);

  Future<void> _restore(BackupCatalogEntry entry) async {
    final session = await loadSession(widget.db);
    if (session == null || !session.permissions.isAll) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('الاستعادة لمدير حصراً (حرس المجال)')));
      }
      return;
    }
    await runRestoreFlow(
      context,
      db: widget.db,
      dbPath: widget.dbPath,
      backupPath: _pathOf(entry),
      onRestored: widget.onRestored,
    );
  }

  Future<void> _export(BackupCatalogEntry entry) async {
    try {
      await Share.shareXFiles(
        [XFile(_pathOf(entry))],
        subject: entry.fileName,
        text: 'نسخة احتياطية دِقَّة',
      );
    } catch (e) {
      await dqLog(widget.db, e, context: 'backups.export');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذر إخراج النسخة — $e${dqTag(e)}')));
      }
    }
  }

  Future<void> _delete(BackupCatalogEntry entry) async {
    final session = await loadSession(widget.db);
    if (session == null || !session.permissions.isAll) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('حذف النسخ لمدير حصراً (حرس المجال)')));
      }
      return;
    }
    // الأرضية النظامية (د-4): آخر نسخة من كل نوع لا تُحذف من داخل
    // التطبيق مطلقاً — الحرس هنا قبل الحائط الصلب بالمخزن.
    if (_floorNames().contains(entry.fileName)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'آخر نسخة من نوعها محمية بالأرضية النظامية — لا تُحذف من داخل التطبيق')));
      }
      return;
    }
    // التأكيد الأول — تعميم نمط السنوية القائم.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف نسخة احتياطية'),
        content: Text(entry.kind == BackupScheduleKind.annual
            ? 'هذه نسخة سنوية دائمة — حذفها بقرارك المباشر وحده.\n'
                'صدرها خارج الجهاز قبل الحذف إن لم تفعل.'
            : 'سيُحذف ملف ${entry.fileName} نهائياً.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true || _store == null) return;
    // التأكيد الثاني (د-4: حذف مديري بتأكيد مزدوج) — بعده فقط ينفَّذ.
    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد نهائي'),
        content: const Text(
            'الحذف نهائي لا يُرجع — لا نسخة بعده ولا استعادة له.\n'
            'تأكيد الحذف نهائياً؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('نعم، احذف الآن')),
        ],
      ),
    );
    if (finalConfirmed != true) return;
    try {
      await _store!.deleteBackupManually(
          fileName: entry.fileName, folderId: entry.folderId);
    } on GfsBackupException catch (e) {
      await dqLog(widget.db, e, context: 'backups.delete');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e${dqTag(e)}')));
      }
    }
    await _reload();
  }

  /// د-3: التراجع عن آخر استعادة من الكتالوج — مدير حرس المجال ثم
  /// مسار الاستعادة المشترك ذاته (تأكيده المزدوج وبوابة مديره).
  Future<void> _rollbackLastRestore() async {
    final session = await loadSession(widget.db);
    if (session == null || !session.permissions.isAll) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('الاستعادة لمدير حصراً (حرس المجال)')));
      }
      return;
    }
    final snap = _window?.snapshotFileName ?? '';
    if (snap.isEmpty) return;
    await runRestoreFlow(
      context,
      db: widget.db,
      dbPath: widget.dbPath,
      backupPath: p.join(
          Directory(widget.dbPath).parent.path, snap),
      onRestored: widget.onRestored,
    );
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    return Scaffold(
      appBar: AppBar(title: const Text('كتالوج النسخ الاحتياطي')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: EdgeInsets.symmetric(
                    horizontal: diqqahAdaptiveHorizontalMargin(context)),
                children: [
                  // د-3 (§25.7، س136): لافتة النافذة — مفتوحة زرٌ معلن،
                  // مغلقة الرسالة الصريحة بلا زر، وغائبة لا لافتة إطلاقاً.
                  if (window != null && !window.closed) ...[
                    _rollbackBanner(context, window),
                    const SizedBox(height: 4),
                  ],
                  if (window != null && window.closed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Card(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_rollbackClosedMessage),
                        ),
                      ),
                    ),
                  for (final e in _store?.catalog.entries ?? [])
                    _entryTile(e),
                  if (_snapshots.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('لقطات الحدث القائمة (تُعرض ولا تُدار)',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                  for (final s in _snapshots) _snapshotTile(s),
                ],
              ),
            ),
    );
  }

  /// لافتة النافذة المفتوحة: بيان السريان وزر التراجع عن آخر استعادة.
  Widget _rollbackBanner(BuildContext context, RollbackWindowState window) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        color: cs.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_rollbackBannerTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'متاحة حتى أول عملية كتابة — الزر يستعيد لقطة ما قبل '
                  'الاستعادة بمسار الاستعادة ذاته (تأكيد مزدوج وبوابة مدير).',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _rollbackLastRestore,
                icon: const Icon(Icons.undo),
                label: const Text('تراجع عن آخر استعادة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryTile(BackupCatalogEntry e) {
    final floor = _floorNames().contains(e.fileName);
    final verifyLabel = switch (e.verifyState) {
      BackupVerifyState.full => 'تحقق كامل',
      BackupVerifyState.quick => 'تحقق سريع',
      BackupVerifyState.failed => 'فشل تحقق',
      BackupVerifyState.none => 'بلا تحقق',
    };
    // أزقة دِقَّة الدلالية (س186): كامل إيجابي وسريع انتباه وفاشل سلبي
    // وبلا تحقق محايد — لا درجات خام.
    final verifyColor = switch (e.verifyState) {
      BackupVerifyState.full => diqqahLanesOf(context).positive.fg,
      BackupVerifyState.quick => diqqahLanesOf(context).attention.fg,
      BackupVerifyState.failed => diqqahLanesOf(context).negative.fg,
      BackupVerifyState.none => diqqahLanesOf(context).neutral.fg,
    };
    return ListTile(
      leading: Icon(
        e.kind == BackupScheduleKind.annual
            ? Icons.event_repeat
            : Icons.backup,
        color: verifyColor,
      ),
      title: Text('${e.kind.label} — ${e.fileName}'),
      subtitle: Text(
          '${_formatUtc(e.atUtc)} • ${(e.sizeBytes / 1024).toStringAsFixed(0)}KB'
          '${e.includesImages ? ' • مع المرفقات' : ''}'
          '${e.deviceTag.isNotEmpty ? ' • جهاز ${e.deviceTag}' : ''}'
          ' • $verifyLabel'
          '${e.appVersion != null && e.appVersion!.isNotEmpty ? ' • ${e.appVersion}' : ''}'
          '${floor ? ' • آخر نسخة من نوعها — محمية (الأرضية النظامية)' : ''}'),
      isThreeLine: true,
      onTap: () => _showActions(e),
    );
  }

  Widget _snapshotTile(ScannedSnapshotRow s) {
    // د-3-2: اللقطة المثبتة نافذةَ تراجعٍ مفتوحة تُوسم على صفها.
    final pinned = _window != null &&
        !_window!.closed &&
        _window!.snapshotFileName == s.fileName;
    return ListTile(
      leading: Icon(
        pinned ? Icons.push_pin : Icons.history,
        color: pinned ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text('${s.typeLabel} — ${s.fileName}'),
      subtitle: Text(
          '${_formatUtc(s.modifiedUtc)} • ${(s.sizeBytes / 1024).toStringAsFixed(0)}KB'
          '${pinned ? ' — مثبتة (نافذة التراجع مفتوحة)' : ' — لقطة قائمة تُستعاد من مسارها'}'),
    );
  }

  Future<void> _showActions(BackupCatalogEntry e) async {
    final floor = _floorNames().contains(e.fileName);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fact_check),
              title: const Text('تحقق'),
              onTap: () {
                Navigator.pop(sheet);
                _verify(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('استعادة (مدير)'),
              onTap: () {
                Navigator.pop(sheet);
                _restore(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('تصدير خارج الجهاز'),
              onTap: () {
                Navigator.pop(sheet);
                _export(e);
              },
            ),
            if (floor)
              ListTile(
                enabled: false,
                leading: const Icon(Icons.push_pin),
                title: const Text(
                    'آخر نسخة من نوعها — محمية (الأرضية النظامية)'),
                subtitle: const Text(
                    'لا تُحذف من داخل التطبيق مطلقاً — د-4'),
              )
            else
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف (مدير)'),
                onTap: () {
                  Navigator.pop(sheet);
                  _delete(e);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('إغلاق'),
              onTap: () => Navigator.pop(sheet),
            ),
          ],
        ),
      ),
    );
  }

  String _formatUtc(DateTime utc) =>
      '${utc.year}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')} UTC';
}
