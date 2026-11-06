import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'hijri_display.dart';
import 'currencies_screen.dart';
import 'ui_fonts.dart';
import 'print_image_prefs.dart';

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
  if (bytes <= 0) return 'بلا صور بعد';
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} كيلوبايت';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} ميغابايت';
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
/// D-060 (قرار المالك 2026-10-29 بلفظه «كلمة السر للبرنامج فقط»):
/// مصدر مفتاح التشفير مفتاح البرنامج حصراً — حقل كلمة المرور زال من
/// النسخ الجديدة، والنسخة تُفتح داخل التطبيق نفسه وحده على أي جهاز.
/// حقل كلمة المرور في الاستعادة بقى لقراءة الجيل القديم v1 حصراً.
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

  /// بعد تبديل المستخدم الحالي (D-100): الرئيسية تعاد بناؤها بفرض
  /// صلاحيات الدور الجديد. اختياري — الاختبارات المباشرة لا تمرره.
  final VoidCallback? onSessionChanged;

  const SettingsScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
    this.onSessionChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _restorePath = TextEditingController();

  /// D-060: للنسخ القديمة v1 حصراً — الجديدة تُفتح بمفتاح البرنامج بلا كلمة.
  final _restorePassword = TextEditingController();

  /// بطاقة المستخدم الحالي (D-100): اختيار المستخدم وكلمة مروره.
  final _switchPassword = TextEditingController();

  bool _busy = false;

  /// D-050: التشفير الافتراضي للنسخ الاحتياطية من م1 — الإلغاء قرار واعٍ.
  bool _encryptBackup = true;

  // ── س-129/D-124 (دفعة 10): تضمين الصور في النسخ — افتراضه مفعّل،
  // وتحته سطر حجم مجلد الصور الحي لا صمت.
  bool _includeImages = true;
  int _imagesBytes = 0;
  int _imagesCount = 0;

  /// فحص الثوابت (F-006/D-099): آخر نتيجة وحالة التنفيذ.
  IntegrityReport? _integrityReport;
  bool _integrityBusy = false;

  /// المستخدمون النشطون واختيار التبديل — تُحمّل عند الفتح (بوابة
  /// الدرس الموثق: القوائم المنسدلة قيمها الابتدائية بعد التحميل).
  List<AppUser> _activeUsers = const [];
  int? _selectedUserId;

  /// ── بطاقة الترقيم (D-169 — س56): عرض عدّاد الترقيم بعد السنة —
  /// يُقرأ النافذ عند الفتح ويُحفظ مدققاً 3..8 في app_meta، ومعاينة
  /// حية قبل الحفظ، والأرقام الصادرة لا تُمسّ بالتغيير أبداً.
  final _counterWidthController = TextEditingController();
  int _counterWidth = kDefaultCounterWidth;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadImagesInfo();
    _loadCounterWidth();
  }

  /// قراءة العرض النافذ (D-169) عند الفتح وبعد كل استعادة.
  Future<void> _loadCounterWidth() async {
    final width = await widget.db.counterWidth();
    if (!mounted) return;
    setState(() {
      _counterWidth = width;
      _counterWidthController.text = '$width';
    });
  }

  /// المعاينة الحية — المدخل يعرض إن كان ضمن النطاق وإلا القيمة المحفوظة،
  /// والمثال رقم 1 من سنة اليوم دائماً (formatDocumentNumber نفسها التي
  /// يولّد بها المحرك فلا معاينة تخالف الواقع).
  String _counterWidthPreview() {
    final parsed = int.tryParse(_counterWidthController.text.trim());
    final width = (parsed != null && isValidCounterWidth(parsed))
        ? parsed
        : _counterWidth;
    return formatDocumentNumber(DateTime.now().year, 1, counterWidth: width);
  }

  /// حفظ العرض بعد تدقيقه — خارج 3..8 رفض برسالة عربية بلا كتابة
  /// (وحرس setCounterWidth ثانٍ في التخزين).
  Future<void> _saveCounterWidth() async {
    final parsed = int.tryParse(_counterWidthController.text.trim());
    if (parsed == null || !isValidCounterWidth(parsed)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('عدد الخانات يجب أن يكون بين $kCounterWidthMin '
            'و $kCounterWidthMax (D-169)'),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.db.setCounterWidth(parsed);
      if (!mounted) return;
      setState(() => _counterWidth = parsed);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حفظ عدد خانات العدّاد — يسري على الأرقام الجديدة'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _loadUsers() async {
    final users = await widget.db.select(widget.db.appUsers).get();
    if (!mounted) return;
    final active = users.where((u) => u.isActive).toList();
    setState(() {
      _activeUsers = active;
      _selectedUserId ??= active.isEmpty ? null : active.first.id;
    });
  }

  @override
  void dispose() {
    _restorePath.dispose();
    _restorePassword.dispose();
    _switchPassword.dispose();
    _counterWidthController.dispose();
    super.dispose();
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ الفحص — $e')),
      );
    } finally {
      if (mounted) setState(() => _integrityBusy = false);
    }
  }

  /// تبديل المستخدم الحالي بكلمة المرور (D-100) — لا جلسة بلا تحقق،
  /// وبعد النجاح تُخزَّن الجلسة وتُعاد الرئيسية بفرض صلاحيات الدور الجديد.
  Future<void> _switchUser() async {
    final userId = _selectedUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر المستخدم أولاً')),
      );
      return;
    }
    final user = await widget.db.verifyUserPassword(
      userId,
      _switchPassword.text,
    );
    if (!mounted) return;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('كلمة المرور غير صحيحة أو المستخدم معطل')),
      );
      return;
    }
    await widget.db.setCurrentUserId(user.id);
    _switchPassword.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم التبديل إلى: ${user.name}')),
    );
    widget.onSessionChanged?.call();
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

  /// D-050/D-060: النسخ الافتراضية مشفرة بمفتاح البرنامج — بلا أي كلمة،
  /// والإلغاء الواعي: من ألغى التشفير يُحذّر قبل إنشاء نسخة خام.
  Future<void> _backup() async {
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
      await backupTo(
        widget.db,
        target,
        encrypted: _encryptBackup,
        includeImages: _includeImages,
        imagesDir: Directory(imagesDirFor(widget.dbPath)),
      );
      if (!mounted) return;
      final imagesPath = imagesSiblingPath(target);
      final hasImagesFile = File(imagesPath).existsSync();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('أُنشئت النسخة الاحتياطية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_encryptBackup
                  ? 'ملف واحد للقاعدة كاملة — مشفرة بمفتاح البرنامج '
                      '(D-060): تُفتح داخل التطبيق نفسه فحسب على أي جهاز'
                  : 'ملف واحد للقاعدة كاملة — غير مشفرة'),
              const SizedBox(height: 8),
              // س-129: تصريح محتوى النسخة بالصور لا صمت أبداً.
              Text(hasImagesFile
                  ? 'النسخة تتضمن صور الأصناف ($_imagesCount ملفاً — '
                      'صور الأصناف: ${formatImagesBytes(_imagesBytes)}) في ملف ثانٍ '
                      'مغلّف بنفس المفتاح (س-129)'
                  : 'النسخة بلا صور — مجلد الصور فارغ أو غائب'),
              const SizedBox(height: 12),
              const Text('مسار النسخة:'),
              SelectableText(target),
              if (hasImagesFile) ...[
                const SizedBox(height: 8),
                const Text('ملف الصور:'),
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
    RestoreCandidate? candidate;
    try {
      candidate = await prepareRestore(
        path,
        password: _restorePassword.text.isEmpty ? null : _restorePassword.text,
        appSchemaVersion: widget.db.schemaVersion,
      );
      if (!mounted) return;
      // س-130/D-124: تصريح محتوى النسخة بالصور **قبل** أي تنفيذ —
      // فلا فجوة صامتة أبداً، والتراجع هنا لم يُمسّ شيئاً.
      final currentImages = Directory(imagesDirFor(widget.dbPath));
      final currentHasFiles = currentImages.existsSync() &&
          currentImages.listSync(recursive: true).any((e) => e is File);
      final declare = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('محتوى النسخة (س-130)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(candidate!.hasImages
                  ? 'النسخة تتضمن صور الأصناف '
                      '(${candidate.imagesFiles.length} ملفاً)'
                  : 'النسخة بلا صور'),
              if (!candidate.hasImages && currentHasFiles) ...[
                const SizedBox(height: 8),
                const Text(
                    'مجلد الصور الحالي سيُستبدل بفراغ — والصور القديمة '
                    'محفوظة في نسخة ما قبل الاستعادة (طريق الرجوع).'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('تراجع'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('متابعة'),
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
          title: const Text('تمت الاستعادة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('استُبدلت القاعدة كاملة. '
                  'نسخة ما قبل الاستعادة (طريق الرجوع) في:'),
              const SizedBox(height: 12),
              SelectableText(snapshotPath),
              if (File(imagesSiblingPath(snapshotPath)).existsSync()) ...[
                const SizedBox(height: 8),
                const Text('ولقطة صورها المرافقة:'),
                SelectableText(imagesSiblingPath(snapshotPath)),
              ],
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

  /// قيمة مفتاح طباعة الصور للعرض — من المخزن الحي (نمط الخط D-104).
  bool _printImageValue(String key) => printImageValueOf(key);

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
      await backupImagesTo(
        Directory(imagesDirFor(widget.dbPath)),
        target,
        encrypted: _encryptBackup,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('أُنشئت نسخة الصور'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ملف صور مستقل ($_imagesCount ملفاً — '
                  'صور الأصناف: ${formatImagesBytes(_imagesBytes)})'),
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
              child: const Text('إخراج النسخة'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } on CorruptBackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إنشاء نسخة الصور — $e')),
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
          title: const Text('استعادة صور من ملف مستقل؟'),
          content: const Text(
              'سيُستبدل مجلد الصور الحالي كاملاً بمحتوى الملف — '
              'بلا أي مساس بالبيانات. التراجع الآن لم يُمسّ شيئاً.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('استعادة الصور'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      final count = await restoreImagesFrom(
        path,
        Directory(imagesDirFor(widget.dbPath)),
      );
      if (!mounted) return;
      _loadImagesInfo();
      messenger.showSnackBar(SnackBar(
        content: Text('استُعيدت صور الأصناف ($count ملفاً) — بلا مساس بالبيانات'),
      ));
    } on CorruptBackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذرت استعادة الصور — $e')),
      );
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
                    'ملف واحد للقاعدة كاملة بلاحقة البرنامج الخاصة (.diqqah) — '
                    'يُستعاد كاملاً أو لا شيء. '
                    'يُحفظ في مجلد القاعدة نفسه. التشفير الافتراضي من م1 '
                    'بمفتاح البرنامج (D-050/D-060)، وإلغاؤه قرار واعٍ بتحذير.',
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
                    title: const Text('تشفير النسخة بمفتاح البرنامج'),
                    subtitle: const Text(
                        'الافتراضي من م1 (D-050/D-060) — لا يفتح النسخة إلا '
                        'التطبيق نفسه على أي جهاز'),
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
                    title: const Text('تضمين صور الأصناف'),
                    subtitle: Text(
                        'صور الأصناف: ${formatImagesBytes(_imagesBytes)}'
                        '${_imagesCount > 0 ? ' ($_imagesCount ملفاً)' : ''}'
                        ' — في ملف ثانٍ مجاور بنفس المفتاح (س-129)'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
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
          // ── بطاقة الترقيم (D-169 — س56): سنة برقمين فالعدّاد بلا فاصل،
          // وعرض العدّاد بعد السنة خانة إعداد المالك (3..8) بمعاينة حية —
          // والأرقام الصادرة لا تُمسّ فالتغيير للوثائق الجديدة حصراً.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ترقيم المستندات (D-169)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'الصيغة: سنة برقمين فالعدّاد مبطناً بلا فاصل — «26000001». '
                    'عدد خانات العدّاد بعد السنة من 3 إلى 8، والأرقام الصادرة '
                    'لا تتغير — فالتغيير للوثائق الجديدة حصراً.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _counterWidthController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'عدد خانات العدّاد بعد السنة (3–8)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  Text('معاينة: «فاتورة بيع ${_counterWidthPreview()}»'),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _saveCounterWidth,
                    child: const Text('حفظ عدد خانات العدّاد'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── بطاقة خيارات العرض (F-167/D-183 — الدفعة 23): مفتاح
          // الهجري بجانب الميلادي — عرض لا إدخال، والميلادي أساس
          // التخزين والإدخال دائماً (D-077/F-175: لا إدخال هجري أبداً).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'خيارات العرض (F-167)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'التاريخ الهجري بجانب الميلادي في القوائم والتقارير '
                    'والمطبوعات — بالتقويم الحسابي المعياري وقد يخالف '
                    'رؤية المحلّة بيوم أو يومين فهو عرض لا مرجع حكم. '
                    'الميلادي أساس التخزين والإدخال دائماً — لا إدخال هجري.',
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('التاريخ الهجري بجانب الميلادي'),
                    subtitle: Text(
                        'معاينة: ${displayDate(todayIsoDate())}'),
                    value: hijriDisplayEnabled.value,
                    onChanged: _busy
                        ? null
                        : (v) async {
                            await setHijriDisplayEnabled(v);
                            if (mounted) setState(() {});
                          },
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
                      labelText:
                          'كلمة المرور — للنسخ القديمة فقط (الجديدة تُفتح تلقائياً)',
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
          const SizedBox(height: 16),
          // فحص الثوابت بيد المالك (F-006، 07 §1.10، D-099 معروض) —
          // الفحص الكامل بعد الفحص الافتتاحي الصامت بالرئيسية.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'فحص الثوابت (F-006)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'الفحوص الأربعة ومطابقات الدفتر الثلاثة (D-067): '
                    'توازن القيود، وسلامة المخزون، ولا حركة يتيمة، وارتباط '
                    'الفواتير بقيودها، ومطابقة الصناديق والمخزون والذمم بالدفتر.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _integrityBusy ? null : _runIntegrityCheck,
                    child: Text(_integrityBusy ? 'جارٍ الفحص…' : 'فحص الآن'),
                  ),
                  if (_integrityReport != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _integrityReport!.summary,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _integrityReport!.isClean
                            ? Colors.green.shade700
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
          const SizedBox(height: 16),
          // المستخدم الحالي (F-080/D-100 معروض) — تبديل الجلسة بكلمة
          // المرور، والرئيسية تُعاد بفرض صلاحيات الدور الجديد.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'المستخدم الحالي (F-080)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تبديل الجلسة بكلمة المرور — والشاشة الهيكلية تُعرض '
                    'بصلاحيات دور المستخدم الجديد.',
                  ),
                  const SizedBox(height: 12),
                  if (_activeUsers.isEmpty)
                    const Text('لا مستخدمين نشطين')
                  else ...[
                    DropdownButton<int>(
                      isExpanded: true,
                      value: _selectedUserId,
                      items: [
                        for (final u in _activeUsers)
                          DropdownMenuItem(
                            value: u.id,
                            child: Text(u.name),
                          ),
                      ],
                      onChanged: (id) => setState(() => _selectedUserId = id),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _switchPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'كلمة مرور المستخدم المختار',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _busy ? null : _switchUser,
                      child: const Text('تبديل المستخدم'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── صور الأصناف في المطبوعات (س-127/س-128، D-123) ──
          // بلفظ المالك: «يمكن إلغاؤه افتراضياً ويحتاج تفعيله الدخول إلى
          // الإعدادات ثم اختيار أين نريد تفعيلها افتراضياً» — الافتراضي
          // معطل في كل المستندات، ومفاتيح التقارير مستقلة عن الفواتير.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'صور الأصناف في المطبوعات (D-123)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'معطلة افتراضياً في كل المستندات — فعّلها أين تشاء. '
                    'عمود صورة مربع بالاحتواء، وبلا صورة دائرة بأول حرف.',
                  ),
                  const SizedBox(height: 8),
                  for (final (key, label) in kPrintImageChoices)
                    SwitchListTile(
                      value: _printImageValue(key),
                      onChanged: (v) =>
                          setState(() => savePrintImagePref(key, v)),
                      title: Text(label),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
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
                  const Text(
                    'نسخة الصور المستقلة (D-124)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'مجلد الصور وحده في ملف `.diqqah.images` بنفس التغليف — '
                    'تُستعاد منفردة فتستبدل الصور بلا مساس بالبيانات.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _backupImagesStandalone,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('نسخ الصور'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _restoreImagesStandalone,
                          icon: const Icon(Icons.restore),
                          label: const Text('استعادة صور'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // الدفعة 34 (F-120/F-121، D-194): إدارة العملات وأسعار
          // الصرف — بند ظاهر لا مدفون (درس D-098)، والتعطيل بلا
          // حذف والأسعار المحفوظة لا تعدل أبداً.
          Card(
            child: ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('العملات وأسعار الصرف'),
              subtitle: const Text(
                  'إضافة عملات وتعطيل غير المستخدمة — وأسعار يومية '
                  'محفوظة لا تُعدل أبداً (F-120/F-121)'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => CurrenciesScreen(db: widget.db)),
                );
              },
            ),
          ),
          // خط التطبيق والطباعة (D-104، دفعة 8 س39) — خيار واحد يغيّر
          // العرض والطباعة معاً بلفظ المالك، والمكتبة مدمجة حصراً:
          // ساحل وتجوال لا غير — لا خطوط جهاز ولا تحميل خارجي.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'خط التطبيق والطباعة (D-104)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'خيار واحد يغيّر خط الشاشات والفواتير المطبوعة معاً '
                    'بعد لحظة. الخطوط مدمجة مع التطبيق حصراً — فمطبوعاتك '
                    'تظهر واحدة على كل الأجهزة، ولا يحتاج البرنامج أي اتصال.',
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      for (final (key, label) in kFontChoices)
                        ButtonSegment(value: key, label: Text(label)),
                    ],
                    selected: {appFontChoice.value},
                    onSelectionChanged: (selection) {
                      final key = selection.first;
                      appFontChoice.value = key;
                      saveFontChoice(key);
                    },
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
