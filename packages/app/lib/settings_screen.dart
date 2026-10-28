import 'dart:io' show Directory, Platform;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// Task 51: هوية الإصدار تُحقن زمن الترجمة من CI (--dart-define) —
/// مصدر الحقيقة pubspec.yaml، ويظهر السطر للمالك أسفل شاشة الإعدادات
/// فيعرف أي نسخة مثبتة عنده. فارغ في التطوير والاختبار فلا ضجيج ولا كسر.
const String kAppVersion = String.fromEnvironment('APP_VERSION');
const String kBuildNumber = String.fromEnvironment('BUILD_NUMBER');

/// D-058 (تعليمة المالك «0.2.01.X»): الصيغة المعروضة تحمل رقم الوثيقة
/// ورقم التجربة — pubspec يحمل «0.2.1» (semver يمنع الصفر البادئ) فالتبطين
/// إلى «01» خانتين هنا عند العرض فحسب.
String diqqahVersionLine(String version, String build) {
  if (version.isEmpty) return '';
  final parts = version.split('.');
  final display = parts.length == 3
      ? '${parts[0]}.${parts[1]}.${parts[2].padLeft(2, '0')}'
      : version;
  return build.isEmpty ? 'دِقَّة $display' : 'دِقَّة $display.$build';
}

/// D-057 (قرار المالك بعد نجاح تجربة الاستعادة 2026-10-29): منتقي الاستيراد
/// يفتح افتراضياً على مجلد «التنزيلات» — حيث تُخرج النسخة عادة، فيلزم النقر
/// لا التفتيش. تحديد مجلد التنزيلات مدعوم في منتقي ملفات النظام على سطح
/// المكتب (ويندوز/لينكس/ماك) حصراً؛ على أندرويد منتقي النظام (SAF) يدير
/// نقطة البداية بنفسه ويُتجاهل المسار — فيعاد null بلا أثر. وتعاد null
/// أيضاً حيثما تعذر تحديد المجلد فلا يُعطّل المنتقي أبداً.
String? defaultImportDirectory({String? userProfile, String? home}) {
  final candidates = <String>[
    if (userProfile != null && userProfile.isNotEmpty)
      p.join(userProfile, 'Downloads'),
    if (home != null && home.isNotEmpty) p.join(home, 'Downloads'),
  ];
  for (final dir in candidates) {
    if (Directory(dir).existsSync()) return dir;
  }
  return null;
}

/// شاشة الإعدادات — النسخ الاحتياطي الكامل والاستعادة (F-012/F-013، س-01).
///
/// «الإعدادات ونسخة الاحتياطي الأولى (F-012) متاحة فوراً بعد التهيئة» (س-01).
/// الاستعادة بتأكيد مزدوج وإلغاء آمن (F-013)، وبعدها سطر إحالة يري مكان
/// نسخة ما قبل الاستعادة (F-154).
///
/// D-050 (م-47): التشفير اختياري في م0 ثم إلزامي افتراضياً من م1 مع
/// «إلغاء واعٍ» — صندوق الاختيار مشدود افتراضياً، وإلغاؤه يفتح تحذيراً
/// صريحاً قبل إنشاء نسخة خام. هو أول بند يُفعّل عند فتح م1 (2026-10-29).
///
/// D-056 (قرار المالك بعد تجربة APK الأولى على أندرويد): قيد النظام على
/// مسار data — مجلد التطبيق محجوب عن كل تطبيق آخر فلا تصفح ولا كتابة
/// مسار يدوياً. الحل القياسي (سلوك واتساب ومديرات كلمات السر):
/// استيراد منتقي ملفات النظام (SAF)، وتصدير نافذة المشاركة لإخراج النسخة
/// إلى مكان يختاره المالك. النسخة تُنشأ في مجلد القاعدة كما هو عقد
/// F-012 — الزر وسيلة إخراج لا تغيير للعقد. على ويندوز يبقى المسار
/// اليدوي متاحاً كما كان.
class SettingsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// مسار ملف القاعدة الحي — منه يشتق مجلد النسخ ولقطات الرجوع.
  final String dbPath;

  /// بعد استعادة ناجحة: البوابة تعيد بناء القاعدة والشاشات من الملف الجديد.
  final VoidCallback onRestored;

  const SettingsScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backupPassword = TextEditingController();
  final _restorePath = TextEditingController();
  final _restorePassword = TextEditingController();

  bool _busy = false;

  /// D-050: التشفير الافتراضي للنسخ الاحتياطية من م1 — الإلغاء قرار واعٍ.
  bool _encryptBackup = true;

  @override
  void dispose() {
    _backupPassword.dispose();
    _restorePath.dispose();
    _restorePassword.dispose();
    super.dispose();
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
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر فتح منتقي الملفات — $e')),
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
        text: 'نسخة احتياطية دِقَّة',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إخراج النسخة — $e')),
      );
    }
  }

  /// D-050: النسخ الافتراضية مشفرة بكلمة مرور — فراغها يوقف بتنبيه لا
  /// بنسخة خام. والإلغاء الواعي: من ألغى التشفير يُحذّر قبل الإنشاء.
  Future<void> _backup() async {
    if (_encryptBackup && _backupPassword.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل كلمة مرور النسخة المشفرة — '
              'أو ألغِ التشفير بوعي من صندوق الاختيار'),
        ),
      );
      return;
    }
    if (!_encryptBackup) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('نسخة بدون تشفير'),
          content: const Text(
              'كل من يملك الملف سيقرأ القاعدة كاملة بدون كلمة مرور. '
              'إلغاء التشفير قرار واعٍ (D-050) — متابعة بدون تشفير؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('تراجع'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('متابعة بدون تشفير'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final target = p.join(
        p.dirname(widget.dbPath),
        'diqqah-backup-${_stamp()}.db',
      );
      final password =
          _encryptBackup ? _backupPassword.text : null;
      await backupTo(widget.db, target, password: password);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('أُنشئت النسخة الاحتياطية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(password == null
                  ? 'ملف واحد للقاعدة كاملة — غير مشفرة'
                  : 'ملف واحد للقاعدة كاملة — مشفرة بكلمة المرور'),
              const SizedBox(height: 12),
              const Text('مسار النسخة:'),
              SelectableText(target),
            ],
          ),
          actions: [
            // D-056: إخراج النسخة من مجلد التطبيق — جوهر الإصلاح الأندرويدي
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _exportBackup(target);
              },
              child: const Text('إخراج النسخة'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إنشاء النسخة — $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final path = _restorePath.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد مسار ملف النسخة أولاً')),
      );
      return;
    }

    // F-013: تأكيد مزدوج — والإلغاء في أي لحظة لم يحدث شيئاً (إلغاء آمن)
    final first = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية؟'),
        content: const Text(
            'ستُستبدل القاعدة الحالية كاملة بالنسخة المختارة — كاملاً أو لا شيء. '
            'تُلتقط نسخة رجوع آلية قبل الاستعادة، وهي طريق الرجوع الوحيد (F-154).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('التأكيد الأخير'),
        content: const Text('متأكد من الاستبدال الكامل للقاعدة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء آمن'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استعادة نهائية'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final candidate = await prepareRestore(
        path,
        password: _restorePassword.text.isEmpty ? null : _restorePassword.text,
        appSchemaVersion: widget.db.schemaVersion,
      );
      String snapshotPath;
      try {
        snapshotPath = await applyRestore(
          db: widget.db,
          candidate: candidate,
          currentDbPath: widget.dbPath,
        );
      } finally {
        candidate.dispose();
      }
      if (!mounted) return;
      // F-154: سطر الإحالة — أين نسخة الرجوع
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تمت الاستعادة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('استُبدلت القاعدة كاملة. '
                  'نسخة ما قبل الاستعادة (طريق الرجوع) في:'),
              const SizedBox(height: 12),
              SelectableText(snapshotPath),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.onRestored();
    } on BackupNewerSchemaException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } on BackupCipherException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on CorruptBackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذرت الاستعادة — $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'النسخ الاحتياطي الكامل (F-012)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ملف واحد للقاعدة كاملة — يُستعاد كاملاً أو لا شيء. '
                    'يُحفظ في مجلد القاعدة نفسه. التشفير الافتراضي من م1 '
                    'بقرار D-050، وإلغاؤه قرار واعٍ بتحذير.',
                  ),
                  const SizedBox(height: 4),
                  // D-050: صندوق الاختيار مشدود افتراضياً — النسخة بلا
                  // تشفير لا تُنشأ إلا بعد تحذير صريح (الإلغاء الواعي).
                  CheckboxListTile(
                    value: _encryptBackup,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _encryptBackup = v ?? true),
                    title: const Text('تشفير النسخة بكلمة مرور'),
                    subtitle: const Text(
                        'الافتراضي من م1 (D-050) — لا يقرأ النسخة إلا من يعرف كلمتها'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_encryptBackup) ...[
                    TextField(
                      controller: _backupPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'كلمة مرور النسخة المشفرة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _backup,
                    child: const Text('إنشاء نسخة احتياطية'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'الاستعادة الكاملة (F-013)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تحقق من سلامة الملف (وتشفيره إن وجد) قبل استبدال القاعدة، '
                    'بتأكيد مزدوج وإلغاء آمن. نسخة رجوع آلية تُلتقط قبل كل استعادة.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _restorePath,
                    decoration: InputDecoration(
                      labelText: 'مسار ملف النسخة الاحتياطية',
                      border: const OutlineInputBorder(),
                      // D-056: على أندرويد مسار data مخفي لا يُكتب يدوياً —
                      // التصفح من داخل التطبيق هو الطريق القياسي الوحيد.
                      helperText: 'على الهاتف استخدم زر التصفح بدل الكتابة اليدوية',
                      suffixIcon: IconButton(
                        tooltip: 'اختيار ملف النسخة',
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
                      labelText: 'كلمة المرور (إن كانت النسخة مشفرة)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _restore,
                    child: const Text('استعادة…'),
                  ),
                ],
              ),
            ),
          ),
          if (diqqahVersionLine(kAppVersion, kBuildNumber).isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              diqqahVersionLine(kAppVersion, kBuildNumber),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
