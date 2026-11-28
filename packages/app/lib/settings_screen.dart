import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'adaptive.dart';
import 'company_profile.dart';
import 'hijri_display.dart';
import 'app_theme.dart';
import 'currencies_screen.dart';
import 'input_formatters.dart';
import 'print_copies.dart';
import 'ui_fonts.dart';
import 'print_image_prefs.dart';
import 'backup_center.dart';
import 'db_key_vault.dart';
import 'item_images.dart';
import 'backup_reminders.dart';
import 'backups_catalog_screen.dart';
import 'diagnostics_screen.dart';
import 'sync_work_screen.dart' show SyncWorkCard;
import 'storage_manager_screen.dart';
import 'import_screen.dart';
import 'device_status.dart';
import 'session.dart';
import 'dq_log.dart';

/// Task 51: هوية الإصدار تُحقن زمن الترجمة من CI (--dart-define) —
/// مصدر الحقيقة pubspec.yaml، ويظهر السطر للمالك أسفل شاشة الإعدادات
/// فيعرف أي نسخة مثبتة عنده. فارغ في التطوير والاختبار فلا ضجيج ولا كسر.
const String kAppVersion = String.fromEnvironment('APP_VERSION');
const String kBuildNumber = String.fromEnvironment('BUILD_NUMBER');

/// D-213 (كلمة المالك 2026-11-21 «b60 ينتقل ليصبح 0.260 دون الإضافات
/// الأخرى»): الإصدارات الجديدة شطران «0.2N» فالعرض بالإصدار وحده بلا
/// لاحقة البناء (الرقم التشغيلي داخل الحزمة versionCode لا نصاً) —
/// وبالبادئة المُشعرة «v.» بكلمة المالك اللاحقة «أضف قبل رقم الإصدار
/// ما يوحي بأنه رقم الإصدار v.0.260» فالعرض «دِقَّة v.0.260» يُقرأ
/// مُشعراً لا رقماً مجرداً — والبادئة عرضية حصراً: APP_VERSION
/// وكتالوج الإصدار والمرشّح البايتي ⑤ بالصيغة التقنية كما هي فحارس
/// البناء لا ينزلق.
/// والصيغة القديمة الثلاثية (D-058) بلسانها التاريخي: التبطين ومرقّ
/// البناء كما كانت.
String diqqahVersionLine(String version, String build) {
  if (version.isEmpty) return '';
  final parts = version.split('.');
  if (parts.length == 2) return 'دِقَّة v.$version';
  final display =
      '${parts[0]}.${parts[1]}.${parts[2].padLeft(2, '0')}';
  return build.isEmpty ? 'دِقَّة $display' : 'دِقَّة $display.$build';
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

  /// س212 (D-215): نداء الغلق للتبديل عبر آلة الحالتين — الزر
  /// «قفل وتبديل المستخدم» يكتب الراية بالقاعدة بlockSession ثم
  /// ينادي به فتعيد بوابة الإقلاع الجذر على بوابة الجهاز (التبديل
  /// قفلٌ ثم بلاطة أخرى — فلا تبديل مباشر يتجاوز الآلة بعد اليوم).
  /// اختياري — الاختبارات المباشرة لا تمرره.
  final VoidCallback? onSessionLocked;

  /// س211 (D-216): تكرارات الهاش لتغيير الكلمة الذاتي والولادة —
  /// الافتراض العتبة الآمنة والاختبارات تحقن الصغيرة بنمط first_run.
  final int hasherIterations;

  const SettingsScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
    this.onSessionLocked,
    this.hasherIterations = PasswordHasher.secureIterations,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  /// المستخدم الحالي بحملة البطاقة — فحص حضور الجلسة حصراً بعد
  /// س212 (البلاطة والكلمة انتقلا إلى بوابة الجهاز فلا منسدلة هنا).
  AppUser? _currentUser;

  /// فحص الثوابت (F-006/D-099): آخر نتيجة وحالة التنفيذ.
  IntegrityReport? _integrityReport;
  bool _integrityBusy = false;

  /// ── بطاقة الترقيم (D-169 — س56): عرض عدّاد الترقيم بعد السنة —
  /// يُقرأ النافذ عند الفتح ويُحفظ مدققاً 3..8 في app_meta، ومعاينة
  /// حية قبل الحفظ، والأرقام الصادرة لا تُمسّ بالتغيير أبداً.
  final _counterWidthController = TextEditingController();
  int _counterWidth = kDefaultCounterWidth;

  /// س102 ثم س164: خيار حجز كميات مسودات البيع — يُقرأ النافذ عند
  /// الفتح من app_meta (نمط عرض العدّاد)، والغائب مطفأ (السلوك القائم).
  bool _heldReserve = false;

  /// س164: خيار «مسودة أكبر من المتاح» — يُقرأ النافذ عند الفتح
  /// (نمط أخيه أعلاه)، والغائب مطفأ (فحص الإنشاء القائم باقٍ).
  bool _draftOverStock = false;

  /// س105: سقف عهدة المندوبين — يُقرأ النافذ عند الفتح (نمط العدّاد
  /// D-169)، والفراغ أو الصفر بلا سقف (سلوك س104 القائم افتراضاً).
  final _custodyCapController = TextEditingController();
  String? _custodyCapResult;

  /// س213 (D-217): مدة الخمول النافذة — تُقرأ عند الفتح (الغائب
  /// والفاسد يعودان الافتراض 10 بالتخزين ذاته) والكتابة فورية
  /// والحارس يقرؤها كل نبضة فالتغيير يسري حياً.
  int _idleMinutes = DiqqahDatabase.sessionIdleMinutesDefault;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadImagesInfo();
    _loadCounterWidth();
    _loadHeldReserve();
    _loadCustodyCap();
    _loadIdleMinutes();
    _loadSession();
    _loadBackupLock();
    _loadVaultKeys();
  }

  /// س213 (D-217): قراءة المدة النافذة عند الفتح وبعد كل استعادة.
  Future<void> _loadIdleMinutes() async {
    final minutes = await widget.db.sessionIdleMinutes();
    if (!mounted) return;
    setState(() => _idleMinutes = minutes);
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

  /// تكليف 2026-11-13 §7: جلسة القارئ — بوابة بطاقة النسخ المجدولة
  /// (وحدة backup) وبوابة أزرار الإدارة بالبطاقات (مدير حصراً).
  SessionInfo? _session;

  Future<void> _loadSession() async {
    final session = await loadSession(widget.db);
    if (!mounted) return;
    setState(() => _session = session);
  }

  /// س105: قراءة السقف النافذ عند الفتح وبعد كل استعادة — الوحّدة
  /// الصغرى معروضة مفصولة (D-102) والصفر فراغاً بلسان «بلا سقف».
  Future<void> _loadCustodyCap() async {
    final cap = await widget.db.heldReceiptCustodyCap();
    if (!mounted) return;
    setState(() {
      _custodyCapController.text = cap > 0 ? groupDigits(cap) : '';
      _custodyCapResult = null;
    });
  }

  /// حفظ السقف بعد تدقيقه — الفراغ صفر (بلا سقف) والمشوّه رفضٌ بلسان
  /// عربي بلا كتابة (وحرز التخزين ثانٍ بالسالب — نمط العدّاد D-169).
  Future<void> _saveCustodyCap() async {
    final text = _custodyCapController.text.trim();
    final cap = text.isEmpty ? 0 : parseGroupedInt(text, fallback: -1);
    if (cap < 0) {
      setState(() => _custodyCapResult =
          'قيمة غير صالحة — أدخل عدداً صحيحاً بوحدة صغرى من العملة '
          'الأساسية أو اتركه فارغاً لإلغاء السقف');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.db.setHeldReceiptCustodyCap(cap);
      if (!mounted) return;
      setState(() {
        _custodyCapController.text = cap > 0 ? groupDigits(cap) : '';
        _custodyCapResult = cap > 0
            ? 'حُفظ السقف: ${groupDigits(cap)} بوحدة صغرى — تجاوزه يمنع '
                'تحصيلاً جديداً حتى تسليم المعلَّق'
            : 'حُفظ — بلا سقف عهدة (السلوك القائم بلا حدّ)';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// قراءة خيارَي مسودات البيع النافذَين عند الفتح وبعد كل استعادة
  /// (onRestored يعيد بناء الشاشة فتُقرأ من جديد) — نمط _loadCounterWidth ذاته.
  Future<void> _loadHeldReserve() async {
    final on = await widget.db.heldInvoicesReserveQty();
    final over = await widget.db.invoiceDraftOverStock();
    if (!mounted) return;
    setState(() {
      _heldReserve = on;
      _draftOverStock = over;
    });
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
            'و $kCounterWidthMax'),
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
    final user = await widget.db.currentUser();
    if (!mounted) return;
    setState(() => _currentUser = user);
  }

  @override
  void dispose() {
    _restorePath.dispose();
    _restorePassword.dispose();
    _lockPass1.dispose();
    _lockPass2.dispose();
    _counterWidthController.dispose();
    _custodyCapController.dispose();
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
      await dqLog(widget.db, e, context: 'settings.integrity');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ الفحص — $e${dqTag(e)}')),
      );
    } finally {
      if (mounted) setState(() => _integrityBusy = false);
    }
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
        setDialogState(() => error = 'لا صاحب جلسة لتغيير كلمته');
        return;
      }
      if (current.text.isEmpty) {
        setDialogState(
            () => error = 'الكلمة الحالية إلزامية — لا جلسة بلا تحقق');
        return;
      }
      if (next.text.isEmpty) {
        setDialogState(() => error = 'الكلمة الجديدة إلزامية — لا فراغات');
        return;
      }
      if (next.text != confirm.text) {
        setDialogState(() => error = 'التأكيد لا يطابق الكلمة الجديدة');
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
          title: const Text('تغيير كلمة المرور'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الحالية',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور الجديدة',
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
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => submit(dialogContext, setDialogState),
              child: const Text('حفظ الكلمة الجديدة'),
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
        const SnackBar(content: Text('تم تغيير كلمة المرور')),
      );
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
        SnackBar(content: Text('تعذر فتح منتقي الملفات — $e${dqTag(e)}')),
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
      await dqLog(widget.db, e, context: 'settings.export');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إخراج النسخة — $e${dqTag(e)}')),
      );
    }
  }

  /// D-050/D-060: النسخ الافتراضية مشفرة بمفتاح البرنامج — بلا أي كلمة،
  /// والإلغاء الواعي: من ألغى التشفير يُحذّر قبل إنشاء نسخة خام.
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
        title: const Text('قفل النسخ بكلمة مرور'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'النسخ الجديدة تُكتب بجيل v3 المقفل: تُفك بكلمة المرور '
                  'أو رمز الاسترداد على أي جهاز — فضع كلمة تعرفها وحداً '
                  'وسجّل الرمز خارج الجهاز. نسخك القديمة تبقى كما هي.'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lockPass1,
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 8) ? '8 محارف فأكثر' : null,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور (8 محارف فأكثر)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lockPass2,
                obscureText: true,
                validator: (v) => (v != _lockPass1.text) ? 'التأكيد يخالف' : null,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('توليد رمز الاسترداد'),
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
            content: Text('فشل حفظ القفل بالخزنة — لم يُعيّن — $e${dqTag(e)}')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _backupLock = lock);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رمز الاسترداد — سجّله خارج الجهاز'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'يفك النسخ المقفلة عندما تُنسى الكلمة أو على جهاز ثانٍ. '
                'اكتبه ورقياً الآن — وبقيته بالخزنة قابل للعرض من هذه '
                'البطاقة في أي وقت.'),
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
                const SnackBar(content: Text('نُسخ الرمز للحافظة')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('سجّلته'),
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
        title: const Text('رمز الاسترداد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('يفك النسخ المقفلة عند نسيان الكلمة أو على جهاز ثانٍ.'),
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
                const SnackBar(content: Text('نُسخ الرمز للحافظة')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسناً'),
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
        title: const Text('رمز استرداد الخزنة (جيل v4)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'يفك نسخ الجيل الرابع على جهاز آخر غير هذا: ثبّت التطبيق '
                'ثم اكتب هذا الرمز بحقل كلمة المرور عند الاستعادة.\n'
                'اكتبه ورقياً خارج الجهاز — نسخ هذا الجهاز تُفك صامتة بلا '
                'أي رمز.'),
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
                const SnackBar(content: Text('نُسخ الرمز للحافظة')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسناً'),
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
        title: const Text('إزالة قفل النسخ؟'),
        content: const Text(
            'النسخ الجديدة تُكتب بمفتاح هذا الجهاز (جيل الخزنة v4): '
            'تُفك هنا صمتاً وبرمز الاسترداد على جهاز آخر. '
            'النسخ المقفلة القائمة تبقى بكلمة مرورها ورمز استردادها '
            'ولا تتأثر بشيء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إزالة القفل'),
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
          title: const Text('نسخة بدون تشفير'),
          content: const Text(
              'كل من يملك الملف سيقرأ القاعدة كاملة بدون كلمة مرور. '
              'إلغاء التشفير قرار واعٍ — متابعة بدون تشفير؟'),
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
      // P1-أ/P1-ب (س149): قفل الخزنة موجود = النسخة وملف صورها بجيل
      // v3 المقفل، ومفتاح الصور يفك الملفات المشفرة عند الجمع.
      // د11 (س229): وبلا قلم ومواد الخزنة حاضرة = جيل v4 (فتح صامت
      // هنا وبرمز الاسترداد على جهاز آخر — N-005 يلتئم).
      await backupTo(
        widget.db,
        target,
        encrypted: _encryptBackup,
        includeImages: includeImages,
        imagesDir: Directory(imagesDirFor(widget.dbPath)),
        lock: _encryptBackup ? _backupLock : null,
        vaultKeys:
            _encryptBackup && _backupLock == null ? _vaultKeys : null,
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
          title: const Text('أُنشئت النسخة الاحتياطية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(!_encryptBackup
                  ? 'ملف واحد للقاعدة كاملة — غير مشفرة'
                  : _backupLock != null
                      ? 'ملف واحد للقاعدة كاملة — مقفلة بكلمة مرورك '
                          '(جيل v3): تُفك بكلمة المرور أو رمز الاسترداد '
                          'على أي جهاز'
                      : _vaultKeys != null
                          ? 'ملف واحد للقاعدة كاملة — مشفرة بمفتاح هذا '
                              'الجهاز (جيل v4): تُفك هنا صمتاً وبرمز '
                              'الاسترداد على جهاز آخر'
                          : 'ملف واحد للقاعدة كاملة — مشفرة بمفتاح '
                              'البرنامج (جيل v2): تُفتح داخل التطبيق نفسه '
                              'فحسب على أي جهاز'),
              const SizedBox(height: 8),
              // س-129: تصريح محتوى النسخة بالصور لا صمت أبداً.
              Text(hasImagesFile
                  ? 'النسخة تتضمن صور الأصناف ($_imagesCount ملفاً — '
                      'صور الأصناف: ${formatImagesBytes(_imagesBytes)}) في ملف ثانٍ '
                      'مغلّف بنفس المفتاح'
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
      await dqLog(widget.db, e, context: 'settings.backup');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إنشاء النسخة — $e${dqTag(e)}')),
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
            'تُلتقط نسخة رجوع آلية قبل الاستعادة، وهي طريق الرجوع الوحيد.'),
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
      // P1-أ (س149): الجيل المقفل v3 يُفك بأسرار خزنة هذا الجهاز أولاً
      // (نفس الجهاز يفتح صامتاً) — وفشلها أو غيابها يعيد المحاولة بما
      // كتبه المالك (الحقل يقبل الكلمة أو رمز الاسترداد، وكلتاهما
      // تُجرّبان بوسم GCM حاكم). v1/v2 بمساريهما القديمين حرفاً.
      // د11 (س229): وجيل الخزنة v4 يُفك بمفتاح هذا الجهاز صمتاً —
      // وعلى جهاز آخر يكتب المالك رمز الاسترداد بالحقل ذاته.
      final typed = _restorePassword.text.isEmpty ? null : _restorePassword.text;
      final stored = typed == null ? await _secrets.loadLock() : null;
      final storedVault = typed == null ? await _tryLoadVault() : null;
      try {
        candidate = await prepareRestore(
          path,
          password: typed ?? stored?.password,
          recoveryCode: typed ?? stored?.recoveryCode,
          vaultRootKey: storedVault?.rootKey,
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
          title: const Text('محتوى النسخة'),
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
          vaultKeys: storedVault,
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
          content: Text('تعذرت الاستعادة — $e${dqTag(e)}')));
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
      await dqLog(widget.db, e, context: 'settings.images_backup');
      messenger.showSnackBar(
          SnackBar(content: Text('${e.message}${dqTag(e)}')));
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.images_backup');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إنشاء نسخة الصور — $e${dqTag(e)}')),
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
        content: Text('استُعيدت صور الأصناف ($count ملفاً) — بلا مساس بالبيانات'),
      ));
    } on CorruptBackupException catch (e) {
      await dqLog(widget.db, e, context: 'settings.images_restore');
      messenger.showSnackBar(
          SnackBar(content: Text('${e.message}${dqTag(e)}')));
    } catch (e) {
      await dqLog(widget.db, e, context: 'settings.images_restore');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذرت استعادة الصور — $e${dqTag(e)}')),
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

  /// لسان المستويات بالعربية الصحيحة — واحدة مفردة والخمس عشرة
  /// تمييزُ مفرد، والبقية جمع (درس الدقة اللغوية بسجل العبارات).
  String _idleLabel(int minutes) {
    if (minutes == 1) return 'دقيقة واحدة';
    if (minutes == 15) return '15 دقيقة';
    return '$minutes دقائق';
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
              'الخمول وقفل الجهاز',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'إذا بقي التطبيق بلا لمس ومفاتيح مدة الخمول المختارة تقفل '
              'الجلسة وتعود بوابة الجهاز — والفتح السريع لبلاطة المستأنف '
              'بالكلمة أو البصمة. مغادرة التطبيق (إخفاء النافذة أو '
              'خلفيتها) تقفل الجلسة فوراً — قاعدة لا خيار. الإعداد '
              'لجهاز المنشأة بيد المدير حصراً فلا يعطّله الكاشير.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              // نمط initialValue الموثق (boxes_screen) — القيمة الداخلية
              // للمُنشأ هي المعروضة، والحقل محمّل من حالة القارئ عند الفتح.
              initialValue: _idleMinutes,
              decoration: const InputDecoration(
                labelText: 'قفل الجلسة بعد خمول',
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
              onChanged: _busy
                  ? null
                  : (v) async {
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

  /// استيراد البيانات (D-208/§25.3 — س140): بطاقة البند وبابها
  /// الوحيد لشاشة الاستيراد — الأطراف والأصناف في دفعة النواة.
  Widget _importDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'استيراد البيانات',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            // س198 (م17 من تقرير فحص الواجهات وفق M3): سطر تلخيص
            // ظاهر والشرح الكثيف خلف توسعة «كيف يعمل؟» — فتبقى
            // الحقيقة كاملة والمساحة هادئة فوق الفعل.
            _ExplanationDisclosure(
              summary: 'الأطراف والأصناف بقوالب CSV المعتمدة ومعاينة '
                  'قبل الاعتماد، والتفصيل خلف التوسعة.',
              details: 'بيانات الانتقال على القوالب المعتمدة: '
                  'الأطراف والأصناف — CSV بترميز UTF-8 بقالب معرّف، '
                  'ومعاينة وعدادات قبل الاعتماد، ونسخة حدثية تلقائية قبله، '
                  'ومعاملة واحدة كل-أو-لا شيء.',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImportScreen(db: widget.db),
                  ),
                );
              },
              icon: const Icon(Icons.import_export),
              label: const Text('فتح شاشة الاستيراد'),
            ),
          ],
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
    final manager = _session?.permissions.isAll ?? false;
    String fmt(DateTime? t) => t == null
        ? 'لم تُنشأ بعد'
        : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'النسخ الاحتياطي المجدول (ساعي/يومي/أسبوعي/شهري)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            // س198 (م17): سطر التلخيص والكشف التدريجي — دوريات النسخ
            // وشروطها كلها باقية حرفاً خلف التوسعة.
            _ExplanationDisclosure(
              summary: 'النسخ تلقائية بكل دورية تختارها، والتفصيل '
                  'بالدوريات وشروطها خلف التوسعة.',
              details: 'ساعية كل ساعة عمل، ويومية عند أول تشغيل يلي اليوم، '
                  'وأسبوعية أول تشغيل يلي السبت، وشهرية أول تشغيل يلي أول '
                  'الشهر — نسخة واحدة عند اللحاق بلا تعويض الفائت. الدورية '
                  'بيانات فقط؛ المرفقات باليدوية والسنوية والحدثية.',
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
                ? 'المجرد غير مبدأ هذه الجلسة (وضع اختبار) — النسخ '
                    'اليدوي أعلاه يعمل كاملاً.'
                : 'حصة مجلد النسخ: '
                    '${(center.quotaBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)}GB'),
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
              label: const Text('كتالوج النسخ (تحقق/استعادة/تصدير/حذف)'),
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
              label: const Text('إدارة التخزين (العرض والتنظيف الذكي)'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ س203: بيانات المنشأة والطباعة التجارية ═══

  /// بطاقة بيانات المنشأة — للمدير حصراً: هوية المنشأة سِمة إدارية
  /// تُسافر بالنسخ الاحتياطية وتظهر أول المطبوعات حين حُفظت.
  Widget _companyDataCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.storefront_outlined),
        title: const Text('بيانات المنشأة'),
        subtitle: const Text(
            'الاسم والهاتف والعنوان والرقم الضريبي — تظهر أول المطبوعات'),
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
          title: const Text('بيانات المنشأة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'اسم المنشأة (إلزامي)'),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'الهاتف'),
                ),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                TextField(
                  controller: tax,
                  decoration: const InputDecoration(
                      labelText: 'الرقم الضريبي (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('اسم المنشأة إلزامي')),
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
                                  'حُفظت بيانات المنشأة — تظهر أول المطبوعات')),
                        );
                      } catch (e) {
                        setDialogState(() => busy = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تعذر الحفظ — $e')),
                        );
                      }
                    },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16,
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16),
        children: [
          // ── س213 (D-218 الخيار أ): ترويسات الأقسام الخمسة داخل القائمة
          // ذاتها — بلا صفحات فئات ولا جانب كاشف (الخيار ب مؤجل بوعي
          // بقرار D-218 مع تذكير تنفيذه). الأقسام بترتيب القرار:
          // الهوية والصلاحيات، البيانات والأمان، سياسات البيع،
          // العرض والمظهر، العمليات.
          _SettingsSectionHeader('الهوية والصلاحيات'),
          // س203: بيانات المنشأة — هوية صاحب العمل التي تظهر أول
          // المطبوعات (الطباعة التجارية)، للمدير حصراً فالمنشأة
          // هويّة إدارية لا يدخلها منوِّب.
          if (_session?.permissions.isAll ?? false) _companyDataCard(),
          const SizedBox(height: 16),
          // ── س213 (D-218): المستخدم الحالي انتقل من وسط القائمة إلى
          // قسم الهوية والصلاحيات — بطاقة الجلسة أقرب بيانات إلى صاحبها
          // (المحتوى بنص س212 حرفاً وبلا مساس ببنية الحقوق).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'المستخدم الحالي',
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
                    label: const Text('قفل وتبديل المستخدم'),
                  ),
                  const SizedBox(height: 8),
                  // س211 (D-216): تغيير الكلمة الذاتي طوعي لصاحب
                  // الجلسة — والإلزامي ببوابة الجهاز لصاحب الراية.
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _changeOwnPassword,
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('تغيير كلمة مروري'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── 2. البيانات والأمان: الخمول (س213/D-217) والنسخ
          // والاستعادة وفحص الثوابت.
          _SettingsSectionHeader('البيانات والأمان'),
          // ── س213 (D-217): بطاقة الخمول — إعداد جهاز بيد المدير حصراً
          // فلا يعطّله الكاشير (تفضيل شخصي لا): المستويات المغلقة
          // 1/5/10/15/30 دقيقة والافتراض 10، وقفل مغادرة التطبيق
          // قانوناً لا خياراً — والقيمة النافذة يقرؤها الحارس كل نبضة
          // فالتغيير يسري حياً بلا إقلاع.
          if (_session?.permissions.isAll ?? false) _sessionIdleCard(),
          const SizedBox(height: 16),
          // تكليف 2026-11-13 (§2/§8-7): بطاقة النسخ المجدول — خلف وحدة
          // backup القابلة للمنح؛ الكتالوج داخلها والأزرار الإدارية
          // للمدير حصراً (حرس المجال roleCanManageBackups).
          if (_session?.permissions.allows('backup') ?? false)
            _scheduledBackupsCard(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'النسخ الاحتياطي الكامل',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  // س198 (م17): سطر التلخيص والكشف التدريجي — الشرح
                  // الكامل بلاحقة البرنامج وشروط التشفير خلف التوسعة.
                  _ExplanationDisclosure(
                    summary: 'ملف واحد للقاعدة كاملة بلاحقة البرنامج '
                        'الخاصة، يُستعاد كاملاً أو لا شيء — والتفصيل '
                        'خلف التوسعة.',
                    details: 'ملف واحد للقاعدة كاملة بلاحقة البرنامج الخاصة '
                        '(.diqqah) — يُستعاد كاملاً أو لا شيء. '
                        'يُحفظ في مجلد القاعدة نفسه. التشفير الافتراضي '
                        'بمفتاح البرنامج، وإلغاؤه قرار واعٍ بتحذير.',
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
                        'الافتراضي — لا يفتح النسخة إلا '
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
                        ' — في ملف ثانٍ مجاور بنفس المفتاح'),
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
                              ? 'النسخ مقفلة بكلمة مرور (جيل v3) — تُفك '
                                  'بالكلمة أو رمز الاسترداد'
                              : _vaultKeys != null
                                  ? 'النسخ بمفتاح هذا الجهاز (جيل الخزنة '
                                      'v4) — تُفك هنا صمتاً وبرمز '
                                      'الاسترداد على جهاز آخر — القفل '
                                      'بكلمة اختياري فوقها'
                                  : 'النسخ بلا كلمة مرور (جيل v2 بمفتاح '
                                      'البرنامج) — القفل اختياري',
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
                            label: const Text('قفل النسخ بكلمة مرور'),
                          ),
                        )
                      else ...[
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _busy ? null : _viewRecoveryCode,
                            icon: const Icon(Icons.key, size: 18),
                            label: const Text('عرض رمز الاسترداد'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _busy ? null : _clearBackupLock,
                            icon: const Icon(Icons.lock_open, size: 18),
                            label: const Text('إزالة القفل'),
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
                              'رمز استرداد الخزنة — يُطلب مرة واحدة عند أول '
                              'تشغيل، ويعاد عرضه من هنا (يفك نسخ v4 على '
                              'جهاز آخر)'),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _viewVaultRecoveryCode,
                          icon: const Icon(Icons.key, size: 18),
                          label: const Text('عرض الرمز'),
                        ),
                      ],
                    ),
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
          // ── س213 (D-218): الاستعادة ونسخ الصور المستقلة وفحص الثوابت
          // انتقلت إلى قسم البيانات والأمان — المتن بنصوصها حرفاً.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الاستعادة الكاملة',
                    style: Theme.of(context).textTheme.titleMedium,
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
                          'كلمة المرور أو رمز الاسترداد — للنسخ القديمة '
                          'والمقفلة ونسخ جهاز آخر (نسخ هذا الجهاز '
                          'تُفتح تلقائياً)',
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
          // ── نسخة صور مستقلة (س-130، D-124) — أداة مكمّلة لا بديل:
          // مجلد الصور وحده في ملف، تُستعاد منفردة بلا مساس بالبيانات.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'نسخة الصور المستقلة',
                    style: Theme.of(context).textTheme.titleMedium,
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
          // فحص الثوابت بيد المالك (F-006، 07 §1.10، D-099 معروض) —
          // الفحص الكامل بعد الفحص الافتتاحي الصامت بالرئيسية.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'فحص الثوابت',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'الفحوص الأربعة ومطابقات الدفتر الثلاثة: '
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
          const SizedBox(height: 16),
          // ── 3. سياسات البيع: مسودات البيع وتحصيلات المندوب —
          // خيارا المنشأة في القاعدة (D-218).
          _SettingsSectionHeader('سياسات البيع'),
          // ── س164: بطاقة مسودات البيع — خيارا المنشأة معاً: الحجز
          // (س102 بمفتاحه الباق حرفاً) صار بتابع المسودة بعد إلغاء
          // التعليق، و«مسودة أكبر من المتاح» نقطة المالك الخامسة:
          // تُحفظ المسودة التزاماً غير معلن والحاكم لحظة الترحيل.
          // إعدادا منشأة في القاعدة (app_meta) لا جهاز، والحجز محسوب
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'مسودات البيع',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'مسودة البيع التزام غير معلن: لا تمس المخزون والدفتر والذمة '
                    'حتى تُرحَّل، وترحيلها بيده أو بيد من مُنح بوابة ترحيل '
                    'مسودات الآخرين. الخياران هنا قرار منشأة يسري على '
                    'كل مستخدمي القاعدة.',
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('مسودات البيع تحجز الكمية'),
                    subtitle: const Text(
                        'مفعّل: كميات كل مسودة بيع تحجز فلا يبيعها سواها '
                        'والمتاح يُخصم بها حتى الترحيل أو الحذف. '
                        'مطفأ: مسودة فقط لا مساس بالكمية (السلوك القائم).'),
                    value: _heldReserve,
                    onChanged: _busy
                        ? null
                        : (v) async {
                            await widget.db.setHeldInvoicesReserveQty(v);
                            if (mounted) setState(() => _heldReserve = v);
                          },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('السماح بحفظ مسودة أكبر من المتاح'),
                    subtitle: const Text(
                        'مفعّل: تُحفظ مسودة البيع ولو فاقت كمياتها الرصيد '
                        '(وعند تفعيل الحجز تحجز كامل كميتها) والحاكم لحظة '
                        'الترحيل — من رحّل أولاً غلب. '
                        'مطفأ: فحص الاكتفاء عند الحفظ باقٍ (السلوك القائم).'),
                    value: _draftOverStock,
                    onChanged: _busy
                        ? null
                        : (v) async {
                            await widget.db.setInvoiceDraftOverStock(v);
                            if (mounted) setState(() => _draftOverStock = v);
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── س105: بطاقة سقف عهدة المندوبين — دفعة المندوب الرابعة:
          // ما يحمله المندوب الواحد من تحصيلات معلقة له سقفٌ من المنشأة
          // لا سكوت شيفرة، إعداد قاعدةٍ (app_meta) فيسري على كل مستخدميها
          // (عرف س102)، والفرض عند التعليق بالمحرك ذاته لا الواجهة.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تحصيلات المندوب',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تحصيل المندوب يُحفظ معلّقاً في «تحصيلات في الطريق» حتى '
                    'اعتماده وتسليمه للصندوق. السقف هنا: أقصى ما '
                    'يحمله المندوب الواحد من معلّق بوحدة صغرى من العملة '
                    'الأساسية — تجاوزه يمنع تحصيلاً جديداً حتى التسليم. '
                    'الفراغ أو الصفر: بلا سقف (السلوك القائم).',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _custodyCapController,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsSeparatorInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'سقف العهدة بوحدة صغرى (فارغ: بلا سقف)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _saveCustodyCap,
                    child: const Text('حفظ سقف العهدة'),
                  ),
                  if (_custodyCapResult != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_custodyCapResult!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── 4. العرض والمظهر: التاريخ الهجري وصور المطبوعات والخط
          // والمظهر — عرضٌ لا سياسات (D-218).
          _SettingsSectionHeader('العرض والمظهر'),
          // ── بطاقة خيارات العرض (F-167/D-183 — الدفعة 23): مفتاح
          // الهجري بجانب الميلادي — عرض لا إدخال، والميلادي أساس
          // التخزين والإدخال دائماً (D-077/F-175: لا إدخال هجري أبداً).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'خيارات العرض',
                    style: Theme.of(context).textTheme.titleMedium,
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
                  Text(
                    'صور الأصناف في المطبوعات',
                    style: Theme.of(context).textTheme.titleMedium,
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
          // خط التطبيق والطباعة (D-104 دفعة 8 س39 — مُحدّث بD-212 س158) —
          // خيار واحد يغيّر العرض والطباعة معاً بلفظ المالك، والمكتبة
          // مدمجة حصراً بأربع عائلات: ساحل وIBM Plex Sans Arabic
          // وNoto Sans Arabic وVazirmatn — لا خطوط جهاز ولا تحميل
          // خارجي، وتجوال خرج بD-212 وترحّل محفوظه إلى ساحل، والاثنان
          // الراكنان (Rubik وReadex Pro) بقائمة الانتظار 09 §8.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'خط التطبيق والطباعة',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'خيار واحد يغيّر خط الشاشات والفواتير المطبوعة معاً '
                    'بعد لحظة. الخطوط الأربعة مدمجة مع التطبيق حصراً — '
                    'فمطبوعاتك تظهر واحدة على كل الأجهزة، ولا يحتاج '
                    'البرنامج أي اتصال.',
                  ),
                  const SizedBox(height: 4),
                  // منتقي الشرائح الأربع (D-212) — شفرات اختيار بقائمة
                  // طولية فلا تفيض الشاشة الضيقة بأربعة أسماء كاملة،
                  // والمعيّن بعلامة الاختيار حي من المُنبّه ذاته.
                  Column(
                    children: [
                      for (final (key, label) in kFontChoices)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          trailing: Icon(
                            appFontChoice.value == key
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          onTap: () {
                            appFontChoice.value = key;
                            saveFontChoice(key);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // س182 (م05 — بأمر المالك «انشئ نظام ألوان نهاري/ليلي/نظام»):
          // بطاقة المظهر — ثلاثة أوضاع (نظام/نهاري/ليلي) بأثر فوري بلا
          // إقلاع (المُنبّه يعيد بناء الجذر)، والافتراضي «نظام» يتبع
          // الجهاز. الخيار محفوظ بنمط الخطوط (D-104) والمحل كما هو.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'المظهر',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'نهاري بخلفية بيضاء وليلي بخلفية داكنة، والنظام يتبع '
                    'إعداد جهازك — التغيير فوري بلا إعادة تشغيل.',
                  ),
                  const SizedBox(height: 4),
                  // منتقي الأوضاع الثلاثة (س182) — بنمط منتقي الخطوط:
                  // قائمة طولية والمعيّن بعلامة الاختيار حي من المُنبّه.
                  Column(
                    children: [
                      for (final (key, label, icon) in kThemeModeChoices)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(icon),
                          title: Text(label),
                          trailing: Icon(
                            appThemeMode.value == key
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          onTap: () {
                            appThemeMode.value = key;
                            saveThemeMode(key);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ── 5. العمليات: الترقيم والعملات والقوالب والمزامنة
          // والاستيراد والتشخيص (D-218) — والتشخيص أخيرة القائمة
          // بعرف درس D-098/س107 باقياً.
          _SettingsSectionHeader('العمليات'),
          // ── بطاقة الترقيم (D-169 — س56): سنة برقمين فالعدّاد بلا فاصل،
          // وعرض العدّاد بعد السنة خانة إعداد المالك (3..8) بمعاينة حية —
          // والأرقام الصادرة لا تُمسّ فالتغيير للوثائق الجديدة حصراً.
          // س213 (D-218): انتقلت إلى قسم العمليات — المتن حرفاً.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ترقيم المستندات',
                    style: Theme.of(context).textTheme.titleMedium,
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
          // الدفعة 34 (F-120/F-121، D-194): إدارة العملات وأسعار
          // الصرف — بند ظاهر لا مدفون (درس D-098)، والتعطيل بلا
          // حذف والأسعار المحفوظة لا تعدل أبداً.
          Card(
            child: ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('العملات وأسعار الصرف'),
              subtitle: const Text(
                  'إضافة عملات وتعطيل غير المستخدمة — وأسعار يومية '
                  'محفوظة لا تُعدل أبداً'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => CurrenciesScreen(db: widget.db)),
                );
              },
            ),
          ),
          // ── س119: بطاقة قوالب طباعة الفواتير — بعد بطاقة التشخيص
          // في نهاية القائمة (الوجه الثاني للدرس: الجديد نهاية القائمة
          // فلا تُزيح بنداً ولا ميزانية سحب). فيها مفتاح إلغاء نسخة
          // أمين المستودع وقالب كل نوع بالقياس والاتجاه والأعلام.
          const PrintTemplatesCard(),
          // ── د6 (س175): بطاقة العمل الجماعي والمزامنة — نهاية القائمة
          // (درس D-098/س107: الجديد بنهاية القائمة فلا تُزيح بنداً ولا
          // ميزانية سحب): النافذة الواجهية للانضمام والأرشفة والإبطال
          // المُحالة من د5 بحدّها الصادق الموثق.
          SyncWorkCard(db: widget.db),
          const SizedBox(height: 16),
          // استيراد البيانات (D-208/§25.3 — س140): بند الإعدادات بمسار
          // «استيراد البيانات» — للمدير حصراً في v1: استيراد الانتقال
          // عملية كبرى بمعاملة واحدة تسبقها نسخة حدثية، والاستيراد
          // الكبير بالحرس المديري عرف §8-5. س213 (D-218): قسم العمليات.
          if (_session?.permissions.isAll ?? false) _importDataCard(),
          const SizedBox(height: 16),
          // ── س107: بطاقة التشخيص ومرجع الأخطاء — نهاية القائمة عمداً
          // فلا تُزيح بندَ دفعات سابقة (درس ميزانية السحب D-098/س102).
          // قراءة لا إجراء: هوية النافذة وذيل سجل الأخطاء والمرجع الحي.
          // س213 (D-218): بآخر العمليات وأخيرة القائمة — الموضع الأخير
          // بعرف الدرس باقٍ لا يتزحزح.
          Card(
            child: ListTile(
              key: const ValueKey('settings_diagnostics'),
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('التشخيص ومرجع الأخطاء'),
              subtitle: const Text(
                  'هوية النافذة وآخر أخطاء القاعدة المرقّمة DQ-xxxx '
                  'وشرحها — لمشاركتها مع من يفحص المشكلة.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DiagnosticsScreen(db: widget.db),
                  ),
                );
              },
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

/// س213 (D-218 الخيار أ): ترويسة قسم داخل قائمة الإعدادات ذاتها —
/// بلا صفحات فئات ولا جانب كاشف (الخيار ب مؤجل بوعي بقرار D-218
/// مع تذكير تنفيذه): لسان قصير بلون الثيم يفصل الأقسام الخمسة
/// بترتيب القرار، والبطاقات تصل بنصّها فاختباراتها لا تنقلب.
class _SettingsSectionHeader extends StatelessWidget {
  final String title;
  const _SettingsSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

/// س198 (م17 من تقرير فحص الواجهات وفق M3): كشف تدريجي للشرح الكثيف
/// ببطاقات الإعدادات الثلاث — سطر تلخيص ظاهر دائماً فوق فعل التوسعة
/// «كيف يعمل؟»، والتفصيل الكامل خلفه حرفاً فلا حقيقة ضاعت ولا فقرة
/// ثابتة تُطيل البطاقة فوق أفعالها.
class _ExplanationDisclosure extends StatefulWidget {
  final String summary;
  final String details;

  const _ExplanationDisclosure({
    required this.summary,
    required this.details,
  });

  @override
  State<_ExplanationDisclosure> createState() =>
      _ExplanationDisclosureState();
}

class _ExplanationDisclosureState extends State<_ExplanationDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.summary),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
            label: Text(_open ? 'إخفاء الشرح' : 'كيف يعمل؟'),
          ),
        ),
        if (_open)
          Text(widget.details,
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
