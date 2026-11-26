/// قسم إدارة التخزين — شاشة مستقلة (د-4/د-8 — §25.8، س136).
///
/// تعرض ستة صفوف: قاعدة البيانات، المرفقات، النسخ حسب نوعها، السجلات،
/// الملفات المؤقتة، التطبيق — مع الأرضية النظامية الموثقة: آخر نسخة من
/// كل نوع لا تُحذف من داخل التطبيق مطلقاً وما عداها حذف مديري بتأكيد
/// مزدوج، وسجل الأحداث append-only مستثنى من الحذف في v1.
///
/// «التنظيف الذكي» هنا اقتراح معروض لا حذف: عند بلوغ منطقة التحذير
/// (80% من السقف — عين العتبة القائمة بلوحة التذكيرات) يقترح حذف
/// الأقدم من القابلة للتدوير مع الإبقاء على الأرضية، والتنفيذ بعرض
/// القائمة واعتمادها بتأكيد مزدوج — لا حذف صامت أبداً.
///
/// الحذف الفردي لكل نسخة مساره كتالوج النسخ (تحقق/استعادة/تصدير/حذف)
/// — هذا القسم نظرة التخزين الكلية لا تكرار لأفعال الصفوف.
library;

import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'adaptive.dart';
import 'backup_center.dart';
import 'session.dart';

class StorageManagerScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final String dbPath;

  const StorageManagerScreen({
    super.key,
    required this.db,
    required this.dbPath,
  });

  @override
  State<StorageManagerScreen> createState() => _StorageManagerScreenState();
}

class _StorageManagerScreenState extends State<StorageManagerScreen> {
  bool _loading = true;
  bool _manager = false;

  int _dbBytes = 0;
  int _imagesBytes = 0;
  int _eventsCount = 0;
  int _eventsPayloadBytes = 0;
  int _errorLogCount = 0;
  int _tempCount = 0;
  int _tempBytes = 0;

  final Map<BackupScheduleKind, (int, int)> _byKind = {};
  int _snapshotsCount = 0;
  int _snapshotsBytes = 0;

  int _usageBytes = 0;
  int _capBytes = kDefaultBackupQuotaBytes;
  List<BackupCatalogEntry> _cleanupPlan = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final session = await loadSession(widget.db);
    final store = BackupCenter.instance?.store ??
        await GfsBackupStore.open(
          backupsDir: Directory(
              p.join(Directory(widget.dbPath).parent.path, 'backups')),
          dbDir: Directory(Directory(widget.dbPath).parent.path),
          deviceIdFull: await widget.db.deviceId(),
          schemaVersion: DiqqahDatabase.schemaVersionValue,
          appVersion: kAppVersion,
        );

    // قاعدة البيانات + جانبياتها (wal/shm) — ملف القاعدة الوحيد F-012.
    var dbBytes = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      final f = File('${widget.dbPath}$suffix');
      if (await f.exists()) dbBytes += await f.length();
    }

    // المرفقات — مجلد الصور بجوار القاعدة (D-125).
    var imagesBytes = 0;
    final imagesDir = Directory(imagesDirFor(widget.dbPath));
    if (await imagesDir.exists()) {
      await for (final f in imagesDir.list(recursive: true)) {
        if (f is File) imagesBytes += await f.length();
      }
    }

    // النسخ حسب نوعها من الكتالوج + لقطات ما قبل الاستعادة الممسوحة.
    final byKind = <BackupScheduleKind, (int, int)>{};
    for (final e in store.catalog.entries) {
      final cur = byKind[e.kind] ?? (0, 0);
      byKind[e.kind] = (cur.$1 + 1, cur.$2 + e.sizeBytes);
    }
    final snapshots = await store.scanSnapshots();
    var snapshotsBytes = 0;
    for (final s in snapshots) {
      snapshotsBytes += s.sizeBytes;
    }

    // السجلات — سجل الأحداث (append-only) وسجل الأخطاء: عدّ وحمولة
    // تقديرية لا حذف — الاستثناء موثق في v1 (07 §2.3).
    final evRows = await widget.db.customSelect(
      'SELECT COUNT(*) AS c, COALESCE(SUM(LENGTH(payload)), 0) AS p '
      'FROM events',
    ).get();
    final eventsCount = (evRows.first.data['c'] as int? ?? 0);
    final eventsPayload = (evRows.first.data['p'] as int? ?? 0);
    final errors = await widget.db.errorLogCount();

    // الملفات المؤقتة بمجلد القاعدة — أعلام المسارات العابرة حصراً،
    // ولا مساس بملفات القاعدة أو اللقطات أو النسخ.
    var tempCount = 0;
    var tempBytes = 0;
    final dbDir = Directory(Directory(widget.dbPath).parent.path);
    if (await dbDir.exists()) {
      await for (final f in dbDir.list()) {
        if (f is! File) continue;
        final name = p.basename(f.path);
        if (name.endsWith('.tmp') || name.endsWith('.restoring')) {
          tempCount++;
          tempBytes += await f.length();
        }
      }
    }

    final usage = await store.usageBytes();
    final cap = BackupCenter.instance?.quotaBytes ??
        kDefaultBackupQuotaBytes;
    final plan = planSmartCleanup(
        entries: store.catalog.entries,
        usageBytes: usage,
        capBytes: cap);

    if (!mounted) return;
    setState(() {
      _manager = session?.permissions.isAll ?? false;
      _dbBytes = dbBytes;
      _imagesBytes = imagesBytes;
      _byKind
        ..clear()
        ..addAll(byKind);
      _snapshotsCount = snapshots.length;
      _snapshotsBytes = snapshotsBytes;
      _eventsCount = eventsCount;
      _eventsPayloadBytes = eventsPayload;
      _errorLogCount = errors;
      _tempCount = tempCount;
      _tempBytes = tempBytes;
      _usageBytes = usage;
      _capBytes = cap;
      _cleanupPlan = plan;
      _loading = false;
    });
  }

  String _fmt(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)}KB';
    }
    return '${bytes}B';
  }

  Future<void> _showCleanupProposal() async {
    if (_cleanupPlan.isEmpty) return;
    final freed =
        _cleanupPlan.fold<int>(0, (sum, e) => sum + e.sizeBytes);
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تنظيف ذكي — اقتراح حذف'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'يُقترح حذف ${_cleanupPlan.length} نسخة '
                  '(تحرير ${_fmt(freed)}) — الأقدم من القابلة للتدوير، '
                  'والأرضية (آخر نسخة من كل نوع) باقية:'),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _cleanupPlan.length,
                  itemBuilder: (_, i) {
                    final e = _cleanupPlan[i];
                    return Text(
                        '• ${e.kind.label} — ${_formatUtc(e.atUtc)} — '
                        '${_fmt(e.sizeBytes)}',
                        style: const TextStyle(fontSize: 12));
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('متابعة')),
        ],
      ),
    );
    if (go != true) return;
    // التأكيد النهائي (د-4: حذف مديري بتأكيد مزدوج) — بعده فقط ينفَّذ.
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد نهائي'),
        content: Text(
            'الحذف نهائي لا يُرجع — احذف ${_cleanupPlan.length} نسخة '
            'نهائياً؟ الأرضية باقية مهما حدث.'),
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
    if (sure != true) return;
    final store = BackupCenter.instance?.store;
    if (store == null) return;
    var deleted = 0;
    var skipped = 0;
    for (final e in _cleanupPlan) {
      try {
        await store.deleteBackupManually(
            fileName: e.fileName, folderId: e.folderId);
        deleted++;
      } on GfsBackupException {
        skipped++; // أرضية ظهرت بين العرض والتنفيذ — لا حذف صامت.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(skipped == 0
              ? 'حُذفت $deleted نسخة بالتنظيف الذكي'
              : 'حُذفت $deleted وتخطّي $skipped (أرضية)')));
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة التخزين')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  diqqahAdaptiveHorizontalMargin(context),
                  12,
                  diqqahAdaptiveHorizontalMargin(context),
                  12),
              children: [
                Card(
                  color: cs.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'الأرضية النظامية: آخر نسخة من كل نوع لا تُحذف '
                      'من داخل التطبيق مطلقاً — وما عداها حذف مدير بتأكيد '
                      'مزدوج. سجل الأحداث append-only مستثنى من الحذف في v1.',
                      style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
                    ),
                  ),
                ),
                _rowCard(
                  title: 'قاعدة البيانات',
                  icon: Icons.storage,
                  value: _fmt(_dbBytes),
                  hint: 'ملف القاعدة الوحيد مع جانبياته (wal/shm)',
                ),
                _rowCard(
                  title: 'المرفقات (الصور)',
                  icon: Icons.image,
                  value: _fmt(_imagesBytes),
                  hint: 'مجلد الصور بجوار القاعدة — تضمّنه النسخة ذات '
                      '«مع المرفقات»',
                ),
                _rowCard(
                  title: 'النسخ الاحتياطية حسب النوع',
                  icon: Icons.backup,
                  value:
                      '${_byKind.values.fold<int>(0, (s, e) => s + e.$1)} نسخة — '
                      '${_fmt(_usageBytes)} من ${_fmt(_capBytes)}',
                  hint: [
                    for (final kind in BackupScheduleKind.values)
                      if (_byKind.containsKey(kind))
                        '${kind.label}: ${_byKind[kind]!.$1} '
                            '(${_fmt(_byKind[kind]!.$2)})',
                    if (_snapshotsCount > 0)
                      'لقطات ما قبل الاستعادة: $_snapshotsCount '
                          '(${_fmt(_snapshotsBytes)})',
                  ].join(' • '),
                ),
                _rowCard(
                  title: 'السجلات',
                  icon: Icons.receipt_long,
                  value:
                      'أحداث: $_eventsCount (${_fmt(_eventsPayloadBytes)}) — '
                      'أخطاء: $_errorLogCount',
                  hint: 'append-only — مستثنى من الحذف في v1',
                ),
                _rowCard(
                  title: 'الملفات المؤقتة',
                  icon: Icons.cleaning_services,
                  value: _tempCount == 0
                      ? 'لا ملفات'
                      : '${_tempCount} ملفاً — ${_fmt(_tempBytes)}',
                  hint: 'أعلام المسارات العابرة (.tmp/.restoring)',
                ),
                _rowCard(
                  title: 'التطبيق',
                  icon: Icons.info_outline,
                  value: kAppVersion,
                  hint: 'مخطط القاعدة '
                      '${DiqqahDatabase.schemaVersionValue} — إدارة التخزين '
                      'v1',
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('التنظيف الذكي',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          _cleanupPlan.isEmpty
                              ? 'لا ازدحام — الاستعمال تحت عتبة التحذير '
                                  '(80% من السقف) فلا اقتراح حذف.'
                              : 'الاستعمال فوق عتبة التحذير — يقترح حذف '
                                  '${_cleanupPlan.length} نسخة (تحرير '
                                  '${_fmt(_cleanupPlan.fold<int>(0, (s, e) => s + e.sizeBytes))}) '
                                  'مع الإبقاء على الأرضية — عرضٌ قبل التنفيذ '
                                  'بلا حذف صامت.',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        if (_cleanupPlan.isNotEmpty)
                          _manager
                              ? FilledButton.icon(
                                  onPressed: _showCleanupProposal,
                                  icon: const Icon(Icons.auto_delete),
                                  label: const Text('عرض اقتراح الحذف'),
                                )
                              : Text(
                                  'التنظيف لمدير حصراً (حرس المجال)',
                                  style: TextStyle(color: cs.error),
                                ),
                        const SizedBox(height: 4),
                        Text(
                          'الحذف الفردي لكل نسخة (تحقق/استعادة/تصدير/حذف) '
                          'مساره كتالوج النسخ — هذا القسم نظرة كلية.',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _rowCard({
    required String title,
    required IconData icon,
    required String value,
    required String hint,
  }) =>
      Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(hint, style: const TextStyle(fontSize: 12)),
          trailing: Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      );

  String _formatUtc(DateTime utc) =>
      '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')} UTC';
}
