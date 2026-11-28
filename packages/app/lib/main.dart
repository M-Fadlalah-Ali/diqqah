import 'dart:async' show unawaited;
import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:diqqah_domain/diqqah_domain.dart' show PasswordHasher;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'aging_prefs.dart';
import 'app_theme.dart';
import 'backup_center.dart';
import 'db_key_vault.dart';
import 'device_gate_screen.dart';
import 'gate_error_screen.dart';
import 'hijri_display.dart';
import 'first_run_screen.dart';
import 'home_screen.dart';
import 'item_images.dart';
import 'native_pbkdf2.dart';
import 'print_copies.dart';
import 'print_image_prefs.dart';
import 'restore_gate_screen.dart';
import 'session_guard.dart';
import 'ui_fonts.dart';
import 'dq_log.dart';

/// D-104 (دفعة 8 س39): تسجيل عائلتي الخط (ساحل/تجوال) وقراءة الخيار
/// المحفوظ قبل الإقلاع — والخطوط مدمجة حصراً (لا خطوط جهاز) بلفظ
/// المالك، وفشل كل خطوة محاط — إقلاع التطبيق أقدس من خط.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadFontChoice();
  await loadPrintImagePrefs();
  // س119: قوالب طباعة الفواتير ونسخة أمين المستودع — قراءتها عند
  // الإقلاع بالنمط ذاته (D-104/D-123) والفاسد يعيد الافتراضي لا يكسر.
  await loadPrintTemplatePrefs();
  // س-151/D-149 (دفعة 15): فوهج أعمار الذمم المخزنة — قراءتها عند
  // الإقلاع بنمط مفاتيح الصور، والفاسد يعيد الافتراضي لا يكسر.
  await loadAgingPrefs();
  // الدفعة 23 (F-167/D-183): خيار عرض الهجري بجانب الميلادي — قراءته
  // عند الإقلاع بالنمط ذاته، والافتراض مطفأ فلا شيء يتغير بلا طلب.
  await loadHijriDisplayPref();
  // س182 (م05 — نظام ألوان نهاري/ليلي/نظامي بأمر المالك): قراءة
  // الوضع المحفوظ قبل الإقلاع بنمط الخطوط — والفاسد يعيد «نظام» بلا كسر.
  await loadThemeMode();
  await preloadAppFonts();
  // س221 (دفعة سرعة الدخول — المؤجل س219 «تسريع التجزئة بتنفيذ أصلي»
  // بأمر المالك «ابدأ بتنفيذ الدفعات الخمسة بالتسلسل الذي عرضته»):
  // تثبيت النواة الأصيلة للتجزئة قبل أي شاشة — قناة المنصة بتحقق ذاتي
  // بمتجه معياري (لحظياً بتكرارات صغيرة ومهلة قصيرة فالإقلاع أقدس)،
  // وأي فشل أو قناة غائبة (ويندوز/الاختبارات) يبقي عزل الخلفية
  // الخالص بعقد س219 حرفاً.
  await NativePbkdf2Engine.probeAndInstall();
  runApp(const DiqqahApp());
}

/// إطار دِقَّة — واجهة واحدة تعمل على أندرويد وWindows (F-001).
///
/// س-135 (D-129 — دفعة 11): لغة التطبيق عربية فيثبت اتجاه الواجهة
/// من اليمين في كل الشاشات — القوائم والأسهم الراجعة وترتيب العناصر
/// تنعكس كالتقارير العربية تماماً بلفظ المالك «أولاً موافق» على
/// اقتراح المستشار. الوفدون من حزمة SDK الرسمية flutter_localizations
/// حصراً بلا حزمة خارجية (شرط البوابة)، واللغة المثبتة العربية
/// الوحيدة فيسمد الاتجاه على كل جهاز بلا خيارات ولا قوائم.
class DiqqahApp extends StatelessWidget {
  final DiqqahDatabase? db;

  /// تجاوز مسار القاعدة (اختبارات) — الإنتاج يشتقه من مجلد الدعم.
  final String? dbPath;

  /// عدد تكرارات PBKDF2 — حقن للاختبارات، الافتراضي الإنتاجي.
  final int hasherIterations;

  const DiqqahApp({super.key, this.db, this.dbPath, this.hasherIterations = PasswordHasher.secureIterations});

  @override
  Widget build(BuildContext context) {
    // D-104: خيار واحد يغيّر العرض والطباعة معاً (جواب المالك «واحد»)
    // — ValueListenableBuilder يعيد بناء الجذر فور تغيير الخيار من
    // الإعدادات فتتغير الشاشات والمطبوعات لحظياً دون إقلاع جديد.
    //
    // س182 (م05): المُنبِّه الثاني لوضع المظهر — نهاري/ليلي/نظام بأمر
    // المالك — بذات النمط: الجذر يعاد بناؤه فور تغيير الوضع من
    // الإعدادات فتتبدل الشاشة كلها بلا إقلاع جديد.
    // س213 (D-217): مستمع نشاط الجلسة على الجذر — اللمس والحركة
    // والعجلة على كل الطبقات تمدّ عدّ الحارس فلا قفل أثناء استخدام
    // حي. الحارس ذاته يبدأ بالرئيسية حصراً (جلسة نشطة) ويصمت
    // على البوابة والتهيئة والاستعادة.
    return SessionIdleGuard.pointerActivityListener(
      child: ValueListenableBuilder<String>(
        valueListenable: appThemeMode,
        builder: (context, modeKey, _) => ValueListenableBuilder<String>(
          valueListenable: appFontChoice,
          builder: (context, fontKey, _) => MaterialApp(
            title: 'دِقَّة',
            // س-135/D-129: الاتجاه العربي الموحد — القوائم والأسهم والشاشات
            // كلها من اليمين، وتتغير نصوص عناصر الواجهة الجاهزة لعربياً.
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // س182 (م05): الثيمان المعتمدان بالألوان الستة وخلفيتَي
            // #FFFFFF و#1E1E1E، والوضع من اختيار المظهر (نظام/نهاري/ليلي).
            theme: buildLightTheme(appFontFamily(fontKey)),
            darkTheme: buildDarkTheme(appFontFamily(fontKey)),
            themeMode: themeModeOf(modeKey),
            home: AppGate(
              db: db,
              dbPath: dbPath,
              hasherIterations: hasherIterations,
            ),
          ),
        ),
      ),
    );
  }
}

/// بوابة أول التشغيل (F-014، س-01): لا شاشة قبل إنشاء المدير —
/// بلا مستخدمين تُفتح شاشة التهيئة، وبمدير موجود تُفتح الهيكلية (F-016).
class AppGate extends StatefulWidget {
  final DiqqahDatabase? db;
  final String? dbPath;
  final int hasherIterations;

  const AppGate({
    super.key,
    this.db,
    this.dbPath,
    this.hasherIterations = PasswordHasher.secureIterations,
  });

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  DiqqahDatabase? _db;
  String? _dbPath;
  bool? _hasAnyUser;

  /// ق-ن1-أ (تكليف 2026-11-13 §5): بوابة معلقة بعد استعادة — يقرأها
  /// كل _resolve من مفتاح restore.gate الذي يزرعه applyRestore فلا
  /// تُعرض بيانات قبل دخول مدير النسخة المستعادة، ولا تنجو بإعادة
  /// التشغيل في منتصف البوابة (المفتاح بالقاعدة نفسها).
  bool _restoreGatePending = false;

  /// س212 (D-215): الحالة «مقفلة خارج الجلسة» — الراية session_locked
  /// بapp_meta تُقرأ في كل _resolve فالإقلاع على جلسة مقفلة يعرض
  /// بوابة الجهاز لا الرئيسية فلا ثقب عودة بعد موت العملية، وأفعال
  /// الثلاثة بالرئيسية تعيد كتابتها وتحمل البوابة بغلٍّ واحد هنا.
  bool _sessionLocked = false;

  /// د11 (س229/D-225 الجزء الأول): حارس الطباعة الواحدة لرمز استرداد
  /// الخزنة — مرة واحدة لكل إقلاع جذر على الأكثر، والراية القاطعة
  /// بخزنة الجهاز (لا هذه الراية) فلا يتكرر بكل بناء.
  bool _vaultRecoveryPromptTried = false;

  /// D-197 (دفعة التحصين الافتتاحي — س96): فشل الافتتاح المعروض بدل
  /// الدورة الأبدية — نصه الحقيقي كامل على شاشة الخطأ.
  String? _error;

  @override
  void initState() {
    super.initState();
    // س213: راية FLAG_SECURE على أندرويد — قانون لا خيار (سلوك
    // تطبيقات البنوك): لقطات الشاشة ومعاينة المستخدمة الأخيرة لبيانات
    // محاسبية لا تُعرض خارج التطبيق. الفشل مبتلع فلا يُسقط الافتتاح،
    // والاختبارات بلا قناة فتتخطاها سائغةً.
    applyAndroidFlagSecure();
    _resolve();
  }

  Future<void> _resolve() async {
    // D-197: كل خطوة افتتاح محاطة حرساً — درس العلة الميدانية
    // (تحديث b24→b26 فشلَ ولو أظهر دورة أبدية بلا كلمة): أي رمي
    // في أي مرحلة يظهر على شاشة الخطأ برسالته الحقيقية وزرَّي
    // إعادة المحاولة والمشاركة، فلا دورة بلا كلمة بعد اليوم.
    String stage = 'تهيئة مجلد التطبيق';
    try {
      final DiqqahDatabase db;
      final String dbPath;
      final injected = widget.db;
      if (injected != null) {
        // حقن الاختبارات — لا قنوات منصة هنا أبداً.
        db = injected;
        dbPath = widget.dbPath ?? 'diqqah.db';
      } else {
        // مسار الإنتاج (قرار موثق — جلسة م0 الثالثة): ملف القاعدة الوحيد
        // F-012 في مجلد الدعم الخاص بالتطبيق على المنصتين. وتبنّي ملف
        // الجيل السابق «heseb.db» عند أول فتح بعد التسمية (D-053).
        final dir = await getApplicationSupportDirectory();
        dbPath = p.join(dir.path, 'diqqah.db');
        stage = 'تبني قاعدة الجيل السابق';
        await adoptLegacyHesebDatabase(dbPath);
        stage = 'لقطة الأمان قبل ترقية المخطط';
        // D-197: أول فتح بعد ترقية يحمل ترحيلات على قاعدة حقيقية —
        // اللقطة تسبق مساسها فأي فشل لاحق يبقى قابلاً للاسترجاع.
        await snapshotBeforeUpgrade(
            dbPath, DiqqahDatabase.schemaVersionValue);
        stage = 'فتح قاعدة البيانات وترقية المخطط';
        // F-150/D-210 P0-ب (س148): خزنة الجهاز تُمرّر للفتح — المفتاح
        // العشوائي 256-bit يُحمل/يُولد من الخزنة (Keystore/DPAPI) ويُرحَّل
        // النص الصريح للمثبتين فوق حزم سابقة عند أول فتح (لقطة preenc
        // ثم VACUUM INTO ثم rekey ثم إعادة تسمية — فشل آمن بأي خطوة).
        db = DiqqahDatabase(filePath: dbPath, keyVault: SecureStorageKeyVault());
        // د-197: تسخين الاتصال هنا حصراً كي يقع تحميل المفتاح والترحيل
        // والتشفير تحت حرس هذه المرحلة بلا استثناء صامت لاحق.
        await db.customStatement('SELECT 1');
        // F-150/D-210 P1-ب (س149): مفتاح الملفات المصاحبة من خزنة الجهاز
        // (KEC مستقل عن مفتاح القاعدة) تحت حرس الافتتاح ذاته، ثم ترحيل
        // الصور النص الصريح القائمة دفعة واحدة — فشل ملف لا يوقف
        // الافتتاح (الأصل سليم بالبايتات) ويُسجل بصوت عالٍ للتابع.
        // حقن الاختبارات لا يمر هنا أصلاً — المفتاح مختبر بالوحدات
        // النقية والاختبارات الضيقة تضبطه يدوياً إن احتاجت.
        final imagesKek =
            await SecureStorageKeyVault.forImages().loadOrCreateKey();
        final imagesCipher = ImageFileCipher(imagesKek);
        ItemImagesStore.cipher = imagesCipher;
        final (migratedImages, failedImages) =
            await migratePlainImagesToEncrypted(
                Directory(imagesDirFor(dbPath)), imagesCipher);
        if (failedImages > 0) {
          try {
            await db.logError(
                code: 'DQ-1124',
                message: 'ترحيل الصور للتشفير: $migratedImages نجح '
                    'و$failedImages فشل — تُعاد المحاولة عند الافتتاح التالي',
                context: 'bootstrap');
          } catch (_) {}
        }
      }
      stage = 'فحص التهيئة';
      final hasAnyUser = await db.hasAnyUser();
      if (!mounted) return;
      // دفعة (10): جذر مسارات الصور هو مجلد القاعدة لا مجلد الصور نفسه —
      // لأعمدة القاعدة مسارات نسبية لمجلد القاعدة («images/item-N.jpg»)
      // والقراءة تضمها على الجذر (D-125)؛ ومجلد الصور نفسه يشتق منه
      // النسخ والاستعادة (imagesDirFor). الاختبارات تضبطه يدوياً.
      ItemImagesStore.root = p.dirname(dbPath);
      // تكليف 2026-11-13: فحص بوابة الاستعادة بعد فتح القاعدة — قبل
      // أي عرض بيانات (ق-ن1-أ).
      final gatePending = await db.restoreGate();
      // س212 (D-215): حالة الجلسة بعد فحص الاستعادة — الراية بالقاعدة
      // نفسها فقراءتها هنا تحكم وجه الإقلاع كله.
      final sessionLocked = await db.sessionLocked();
      final startCenter = widget.db == null;
      if (!mounted) return;
      setState(() {
        _db = db;
        _dbPath = dbPath;
        _hasAnyUser = hasAnyUser;
        _restoreGatePending = gatePending != null;
        _sessionLocked = sessionLocked;
        _error = null;
      });
      if (startCenter && BackupCenter.instance == null) {
        // س216: مركز النسخ خارج مسار الافتتاح المحجوب — لحاق النسخ
        // المستحقة (VACUUM INTO وبصمة وتشفير قاعدة كاملة) كان يجرى
        // قبل أن تتنفس أول إطار فذاك جذر «ثقل الدقائق الأولى» مع
        // علة عزل المحرك (س216 database.dart). الآن يبدأ بعد استقرار
        // أول إطار ومهلة قصيرة فالرئيسية تظهر فوراً والنسخ يجري
        // خلفياً بعزله (المحرك بعزل خلفي وحساب البايتات Isolate.run
        // بنمط س216). العقد القائم باقٍ حرفاً: نظامي فوق أي بوابة
        // (§7) وفشله أقصى جهد لا يعطل شيئاً واليدوي بالإعدادات
        // يبقى بلا مجدول.
        unawaited(Future(() async {
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(seconds: 3));
          try {
            await BackupCenter.start(db: db, dbPath: dbPath);
          } catch (_) {}
        }));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$stage: $e${dqTag(e)}';
        _hasAnyUser = null;
      });
    }
  }

  /// بعد استعادة ناجحة (F-013): القاعدة القديمة مغلقة والملف استُبدل —
  /// تعيد البوابة فتح قاعدة جديدة من الملف نفسه (الإنتاج)، ويقرأ حكم
  /// بوابة الاستعادة من المفتاح المزروع (ق-ن1-أ).
  void _onRestored() {
    if (widget.db != null) {
      // قاعدة محقونة (اختبارات) — إعادة البناء بيد صاحب الاختبار.
      return;
    }
    setState(() {
      _db = null;
      _dbPath = null;
      _hasAnyUser = null;
      _restoreGatePending = false;
      _sessionLocked = false;
    });
    _resolve();
  }

  /// س212 (D-215): وجه أفعال الثلاثة (القفل والتبديل والخروج) —
  /// الرئيسية نادت بالغلق بعد كتابة الراية بالقاعدة فتُعرض بوابة
  /// الجهاز فوراً، وبوابةُ الجهاز نادت بالفتح بعد إزالتها فتعود
  /// الرئيسية بصاحب الجلسة الجديد.
  void _setSessionLocked(bool locked) {
    setState(() => _sessionLocked = locked);
  }

  @override
  Widget build(BuildContext context) {
    // D-197: فشل الافتتاح شاشة لا دورة — الرسالة الحقيقية وزرّا
    // الإعادة والمشاركة، والتفاصيل في gate_error_screen.dart.
    final error = _error;
    if (error != null) {
      return GateErrorScreen(message: error, onRetry: _resolve);
    }
    final hasAnyUser = _hasAnyUser;
    if (hasAnyUser == null) {
      // افتتاح < 3 ثوانٍ (F-016): بلا أي عمل محاسبي على هذا المسار.
      // س216: لسان الصدق أثناء الافتتاح — أول فتح بعد تحديث يحمل
      // ترحيلة وفهارس لمرة واحدة، فالنص يفسر أي انتظار بدل صمتٍ
      // يوحي بالتوقف (رسالة أندرويد التي رآها المالك بالحياة b71).
      // س229 (توحيد الانطلاقة بالعمل الفني الجديد): خلفية الانطلاقة
      // الفحمية (30,30,30) ذاتها وأثر الهوية الفاتح — فلا وميض أبيض
      // بين انطلاقة النظام المشغلة بالعمل الجديد وأول إطار هنا.
      return Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                  color: kDarkIdentityBrown),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'يُفتح قاعدة بياناتك… أول فتح بعد التحديث يستغرق '
                  'وقتاً أطول مرة واحدة (تحسين المخطط والفهارس)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kDarkIdentityBrown),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final db = _db!;
    final dbPath = _dbPath ?? widget.dbPath ?? 'diqqah.db';
    if (!hasAnyUser) {
      return FirstRunScreen(
        db: db,
        hasherIterations: widget.hasherIterations,
        onSetupDone: () => setState(() => _hasAnyUser = true),
      );
    }
    if (_restoreGatePending) {
      return RestoreGateScreen(
        db: db,
        dbPath: dbPath,
        onCleared: () => setState(() => _restoreGatePending = false),
        // س136 (د-3): استعادة من داخل البوابة (تراجعاً أو اختيار نسخة
        // أخرى) تعيد بناء الجذر على القاعدة الجديدة — لا شاشة على قاعدة ميتة.
        onRestored: _onRestored,
      );
    }
    // س212 (D-215): الجلسة مقفلة — بوابة الجهاز هي الوجه حصراً
    // (ق-ن1-أ نفسه ترتيباً: بوابة الاستعادة أولاً إن كانت معلقة).
    if (_sessionLocked) {
      return DeviceGateScreen(
        db: db,
        hasherIterations: widget.hasherIterations,
        onUnlocked: () => _setSessionLocked(false),
      );
    }
    if (!_vaultRecoveryPromptTried) {
      // مرة واحدة لكل إقلاع — والراية القاطعة بخزنة الجهاز لا هنا.
      _vaultRecoveryPromptTried = true;
      _revealVaultRecoveryOnce();
    }
    return HomeScreen(
      db: db,
      dbPath: dbPath,
      onRestored: _onRestored,
      onLocked: () => _setSessionLocked(true),
    );
  }

  /// د11 (س229/D-225 الجزء الأول): الطباعة الواحدة لرمز استرداد الخزنة
  /// — عند أول دخول للرئيسية (بعد إعداد جديد أو أول إقلاع بعد التحديث):
  /// إن لم يُطبع بعد تُقرأ المواد (تُولَّد إن غابت — أول تشغيل حقيقي)
  /// ويُعرض الرمز مرة واحدة بحوار «سجّلته» (نسخ + إثبات) ثم يُوسم
  /// بالخزنة فلا يعود تلقائياً — ويعاد عرضه من الإعدادات متى شاء
  /// المالك (عرف الصدق الموثق بv3 ذاته). الإنتاج حصراً (قاعدة محقونة
  /// = اختبار فلا قناة خزنة هنا)، وكل فشل صامت موثق: الخزنة الغائبة
  /// تعني نسخاً بجيل v2 المنخفض الموثق بالفحص والإعدادات.
  Future<void> _revealVaultRecoveryOnce() async {
    if (widget.db != null) return; // اختبار محقون — لا خزنة هنا.
    try {
      final store = VaultBackupKeys();
      if (await store.recoveryRevealed()) return;
      final keys = await store.loadOrCreate();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('رمز استرداد نسخك — سجّله خارج الجهاز'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'نسخك الجديدة (جيل الخزنة v4) تُفك على هذا الجهاز '
                  'تلقائياً — وعلى جهاز آخر بهذا الرمز فقط. اكتبه ورقياً '
                  'الآن واحفظه خارج الجهاز: فقد الخزنة بلا رمز يعني '
                  'الرجوع لنسخك القديمة.\n'
                  'يبقى الرمز قابلاً للعرض من الإعدادات متى شئت.'),
              const SizedBox(height: 12),
              SelectableText(keys.recoveryCode,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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
              child: const Text('سجّلته'),
            ),
          ],
        ),
      );
      await store.markRecoveryRevealed();
    } catch (_) {
      // خزنة غائبة/فاشلة — انخفاض v2 موثق لا صمت استثناء هنا.
    }
  }
}
