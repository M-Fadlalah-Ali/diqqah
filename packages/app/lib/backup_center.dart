/// مركز النسخ الاحتياطي (تكليف 2026-11-13) — منسّق الواجهة الوحيد
/// لمحرك GFS: مجدول الدورات ولحاق أول التشغيل (ق-ن6)، تخطي الساعية
/// ببطارية أندرويد <20% (ق-ن2)، سقف الحصة بالبايتات مع تقليم أقدم
/// الدورات التلقائية (ق-ن3)، الإشعارات داخل التطبيق حصراً (ق-ن8)
/// بشارات الواجهة لا إشعارات نظام ولا خدمة خلفية.
///
/// وضعه المعماري (ث-10): يبدأ من بوابة الافتتاح بعد فتح القاعدة
/// ويحيا فوق أي بوابة دخول لاحقة — فالنسخ التلقائي «نظامي يعمل بغض
/// النظر عن المستخدم المسجل» (§7) لا يهبط تحت بوابة أبداً.
library;

import 'dart:async';
import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:flutter/foundation.dart';

import 'db_key_vault.dart';
import 'device_status.dart';
import 'item_images.dart';

/// شارة سلامة النسخ المعروضة — قابلة للرصد من الرئيسية والإعدادات.
class BackupHealth {
  final DateTime? lastAnyUtc;
  final bool noBackupFor30Days;
  final bool attachmentsStale;

  /// أحدث نسخة تضم المرفقات — لسان رسالة تذكير المرفقات بالواجهة
  /// الأغنى (دفعة 2): تاريخ آخر احتواء لا عبارات عامة.
  final DateTime? latestWithImagesUtc;
  final double quotaUsedFraction;
  final bool hourlySkippedQuota;
  final bool hourlySkippedBattery;
  final String? failureMessage;
  final DateTime computedAtUtc;

  const BackupHealth({
    this.lastAnyUtc,
    this.noBackupFor30Days = false,
    this.attachmentsStale = false,
    this.latestWithImagesUtc,
    this.quotaUsedFraction = 0,
    this.hourlySkippedQuota = false,
    this.hourlySkippedBattery = false,
    this.failureMessage,
    required this.computedAtUtc,
  });

  bool get hasFailure => failureMessage != null;
}

/// عتبة البطارية لتخطي الساعية (تكليف §8-3) — أندرويد.
const int kHourlyBatteryFloorPercent = 20;

/// إصدار التطبيق الموحد — يُسجل بصفوف الكتالوج (appVersion) ويُعرض
/// بقسم إدارة التخزين. مصدر واحد لا نصوص متناثرة (س136) — وس205
/// صعد بالإصدار 0.262.0+62 (إصدار م06 التكيفي وبقية الرابعة من M3:
/// م07 جداول التقارير و م10 نموذج الفاتورة و م04 منتقي المردود
/// و م09 تنظيم التقارير) بنفس صيغة D-213: الترميز «0.N.0+run»
/// ببوابة patch=0 الصارمة وversionCode 62 للتثبيت المتصاعد فوق b61
/// بلا حذف — وسطر كتالوج الإصدار مرشّح التحقق البايتي ⑤ فلا انزلاق
/// علة س163. وسطر الواجهة المعروض ببادئة «v.» (كلمة المالك «أضف
/// قبل رقم الإصدار ما يوحي بأنه رقم الإصدار») بينما هذا الثابت
/// والحقن بالصيغة التقنية كما هي فحارس ⑤ سليم. والحزمة محجوزة
/// لبناء b62 بأمر المالك حصراً.
/// س207: الترميز الموحد 0.263.0+63 — دفعة تنظيف ويندوز (بنود نقاش
/// المالك المعتمد 2026-11-22: حفظ القوالب باسم بنافذة سطح المكتب،
/// وقائمة السياق الموحدة يمين/طويل بمصدر واحد، وقواعد التلميح
/// المركزية، والتنظيف النصي المعتمد) — محجوز لبناء b63 بأمر المالك
/// حصراً بنمط الدفعات (لا بناء بلا كلمته).
/// س208: الترميز الموحد 0.264.0+64 — الدفعة 2 «الاتساق» (نمط شاشة
/// القائمة الموحد على السندات والأدوار والصناديق والمستودعات بقائمة
/// تحققه الثمانية، وم06 التكيفي على الطلبات، وملف اختبار المستودعات
/// الأول بنص ملاحظة المالك المعتمدة، وقائمة سياق س207 على شاشات النمط
/// الجديدة) — محجوز لبناء b64 بأمر المالك حصراً بنمط الدفعات.
/// س209: الترميز الموحد 0.265.0+65 — الدفعة 3 (قانون عرض سطح المكتب
/// والرئيسية الست طبقات — بند 6 قواعد الصناعة بتفاصيل قرار المجلس
/// س207: سلم المسافات 4/8 وشبكة أعمدة وبطاقة لا أيقونة بحد التوسيط
/// ذاته وتباين AA حسابياً وطبقة نبض العمل من اللقطة القائمة والتذييل)
/// — محجوز لبناء b65 بأمر المالك حصراً بنمط الدفعات (لا بناء بلا
/// كلمته).
/// س211: دفعة 1 من خطة الجلسة والمستخدمين (D-216: إنشاء المستخدمين
/// بأقل امتياز وإلزام التغيير وشاشة المستخدمين) — محجوز بناء b67
/// بأمر المالك حصراً بنمط الدفعات.
/// س212: الترميز الموحد 0.268.0+68 — دفعة 2 من خطة الجلسة والمستخدمين
/// (D-215/U-005: آلة الحالتين وبوابة الجهاز ببلاطات المستخدمين
/// والراية المحفوظة بapp_meta فلا ثقب عودة بعد موت العملية) —
/// محجوز لبناء b68 بأمر المالك حصراً بنمط الدفعات.
/// س213: الترميز الموحد 0.269.0+69 حجزت لتشغيل 69 ففشل بعلّة بناء
/// ويندوز الموثقة (local_auth_windows وSTL1011) فاحتل الرقم وسالخ
/// بنمط الفجوات الموثق b45 — والترميز المنتِج بD-213:
/// الترميز الموحد 0.270.0+70 — دفعة 3 من خطة الجلسة والمستخدمين
/// (D-217 الخمول إعداد جهاز في «البيانات والأمان» بالمستويات المغلقة
/// 1/5/10/15/30 والقفل الفوري عند مغادرة التطبيق، والبيومتري للفتح
/// السريع للمعلق فقط، وFLAG_SECURE قانوناً بلا مفتاح، وتنظيم
/// الإعدادات D-218 بالخيار أ ترويسات الأقسام الخمسة) — محجوز
/// لبناء b70 بأمر المالك حصراً بنمط الدفعات.
/// س215: الترميز الموحد 0.271.0+71 — البند 7 المعماري المعتمد
/// «نواة واحدة قشرة لكل منصة» بأمر بدئه الملفظي (وثيقة العمارة
/// وحارسه البنيوي الآلي)، ومعالجة الثقل الجذري للبيانات الضخمة
/// (ترحيلة v35: ستة عشر فهرساً لطرق الوصول الحارة التي كشفها
/// اختبار القاعدة التجريبية الكبيرة س214) — محجوز لبناء b71
/// بأمر المالك حصراً بنمط الدفعات.
/// س216: الترميز الموحد 0.272.0+72 — جذر ثقل الدقائق الأولى بعزل
/// الخلفية (createInBackground للحلقة الإنتاجية، والنسخ لحاقاً بعد
/// أول إطار وحساب البايتات Isolate.run وقراءة ترويسة اللقطة 64
/// بايتة وPRAGMA synchronous=NORMAL ولسان الصدق بالانتظار)، وبند
/// الدخول اليدوي بنقض بلاطات U-005 ورسالة فشل عامة واحدة
/// (resumeSessionByLogin) — محجوز لبناء b72 بأمر المالك حصراً.
/// س218: الترميز الموحد 0.273.0+73 — إصلاح علة إرسال العزل الخلفي
/// المالِفية «object is unsendable - _AsyncCompleter» بأول فتح قاعدة
/// مشفرة: البناء كله ببنّاءتين علوية وإغلاق التشفير بنطاق علوي يلتقط
/// المفتاح حصراً (عقد قابلية الإرسال وحرسه البنيوي باختبار s218) —
/// محجوز لبناء b73 بأمر المالك حصراً.
/// س219: الترميز الموحد 0.274.0+74 — النواة الحسابية للتجزئة والتحقق
/// بعزل الخلفية وموازنة التوقيت بالرفض الثلاثة (عقد س219 بمدار
/// قابلية الإرسال س218) ومؤشر الجريان بالبوابة — محجوز لبناء b74
/// بأمر المالك حصراً.
/// س221: الترميز الموحد 0.275.0+75 — التنفيذ الأصلي للتجزئة (قناة
/// المنصة بالتحقق الذاتي والبديل الخالص بعزل الخلفية — المؤجل س219
/// منفَّذ) واتساق نبض العمل وعزل النوع بجهة الأرشيف وحد العرض
/// المتدرج — محجوز لبناء b75 بأمر المالك حصراً.
/// س223: الترميز الموحد 0.276.0+76 — المتبقي من د5 منفَّذاً: الحد
/// المتدرج الموحد على تبويبات السندات الثلاثة وأرشيف الطلبات
/// ومعاينات مستندات المخزون وأسطر كشف الحساب (نمط list_display.dart
/// بعقد س221 — الحد بناء واجهة حصراً) — محجوز لبناء b76 بأمر المالك
/// حصراً.
/// س225: الترميز الموحد 0.277.0+77 — الدفعة الأولى للحيوية بأمر
/// المالك (خ1 نبض العمل بألوان الأزقة وخ2 هوية الوحدات الثلاث وخ7
/// طبقات الليل وخ6 الحالات الفارغة الحية) والزيبرا المحايد على
/// جداول الشاشة بإجمالياتها المزدوجة والتحديد المتعدد الجماعي
/// بمسار البحث السريع — محجوز لبناء b77 بأمر المالك حصراً.
const String kAppVersion = '0.277.0+77';

class BackupCenter {
  /// النسخة الوحيدة بالعملية — تبدأ من بوابة الافتتاح بالإنتاج فقط
  /// (المسار المحقون للاختبارات لا يبدأ مركزاً كي تبقى الاختبارات
  /// نقية التحكم).
  static BackupCenter? instance;

  final DiqqahDatabase db;
  final String dbPath;
  GfsBackupStore? store;

  Timer? _timer;
  bool _paused = false;
  bool _running = false;

  /// سقف الحصة بالبايتات (ق-ن3) — قابل للضبط من الإعدادات (مدير).
  int quotaBytes = kDefaultBackupQuotaBytes;

  /// مزودات قابلة للحقن بالاختبار: الساعة والبطارية والقرار.
  DateTime Function() nowUtc = () => DateTime.now().toUtc();
  DateTime Function() nowLocal = () => DateTime.now();
  Future<int?> Function() battery = batteryLevel;

  final ValueNotifier<BackupHealth?> health = ValueNotifier(null);

  BackupCenter._({required this.db, required this.dbPath});

  /// الفتح: يهيئ المخزن، يجري لحاق أول التشغيل (نسخة واحدة لكل دورة
  /// مستحقة — §8-1)، ثم يوقت المضرب الدوري. مزودات الساعة والبطارية
  /// حقن الاختبار (scheduleTimer كاذبة) — الإنتاج يأخذ الافتراضات.
  static Future<BackupCenter> start({
    required DiqqahDatabase db,
    required String dbPath,
    int quotaBytes = kDefaultBackupQuotaBytes,
    DateTime Function()? nowUtcProvider,
    DateTime Function()? nowLocalProvider,
    Future<int?> Function()? batteryProvider,
    bool scheduleTimer = true,
    BackupSecretsStore? secretsStore,
    ImageFileCipher? imagesCipher,
  }) async {
    final center = BackupCenter._(db: db, dbPath: dbPath);
    center.quotaBytes = quotaBytes;
    if (nowUtcProvider != null) center.nowUtc = nowUtcProvider;
    if (nowLocalProvider != null) center.nowLocal = nowLocalProvider;
    if (batteryProvider != null) center.battery = batteryProvider;
    await center._initStore(
      secretsStore: secretsStore,
      imagesCipher: imagesCipher,
    );
    await center.runCatchUp();
    await center.refreshHealth();
    if (scheduleTimer) {
      center._timer = Timer.periodic(
          const Duration(minutes: 5), (_) => center._tick());
    }
    instance = center;
    return center;
  }

  /// P1-أ/P1-ب (س149): أسرار القفل تُحل من الخزنة عند كل إنشاء وتحقق
  /// (استدعاء حي لا لقطة)، ومفتاح الصور من ضبط الافتتاح. قراءة الخزنة
  /// الفاشلة (خزنة غائبة/اختبارات بلا قناة) = بلا قفل فالجدولة تعود
  /// لجيل v2 المشفر بمفتاح البرنامج — انخفاض موثق لا صمت ببيانات،
  /// واليدوي من الإعدادات يبقى يكشف حالة الخزنة بصوتها.
  Future<void> _initStore({
    BackupSecretsStore? secretsStore,
    ImageFileCipher? imagesCipher,
  }) async {
    final secrets = secretsStore ?? BackupSecretsStore();
    store = await GfsBackupStore.open(
      backupsDir: Directory('${Directory(dbPath).parent.path}'
          '${Platform.pathSeparator}backups'),
      dbDir: Directory(Directory(dbPath).parent.path),
      deviceIdFull: await db.deviceId(),
      schemaVersion: DiqqahDatabase.schemaVersionValue,
      appVersion: kAppVersion,
      loadLock: () async {
        try {
          return await secrets.loadLock();
        } catch (_) {
          return null;
        }
      },
      imagesCipher: imagesCipher ?? ItemImagesStore.cipher,
    );
  }

  /// لحاق أول التشغيل: كل دورة مستحقة تُنفَّذ مرة واحدة الآن ثم تهدأ —
  /// لا نعيد كل الفائت (§8-1) مهما طال الغياب.
  Future<void> runCatchUp() async {
    final due = dueAutoKinds(
      nowUtc: nowUtc(),
      nowLocal: nowLocal(),
      lastSuccess: store?.catalog.lastSuccess ?? {},
    );
    for (final kind in BackupScheduleKind.values) {
      if (due.contains(kind)) await _runKind(kind);
    }
  }

  Future<void> _tick() async {
    if (_paused || _running) return;
    // الساعية وحدها على المضرب — اليومية فما فوق حدودها التقويمية
    // يلتقطها لحاق الإقلاع، والمضرب يفحصها أيضاً للجلسة الطويلة العابرة
    // للمنتصف (جلسة عمل 24 ساعة بلا إقلاع جديد).
    final due = dueAutoKinds(
      nowUtc: nowUtc(),
      nowLocal: nowLocal(),
      lastSuccess: store?.catalog.lastSuccess ?? {},
    );
    for (final kind in BackupScheduleKind.values) {
      if (due.contains(kind)) await _runKind(kind);
    }
  }

  /// إيقاف المجدول أثناء العمليات الحرجية (§8-5): الاستعادة والترقية
  /// والإقفال والاستيراد الكبير — الحدثية نفسها تعمل، الدورية تنتظر.
  void pause() => _paused = true;
  void resume() {
    _paused = false;
    unawaited(refreshHealth());
  }

  Future<void> _runKind(BackupScheduleKind kind) async {
    if (_running || _paused || store == null) return;
    if (kind != BackupScheduleKind.hourly) {
      // الدورية التقويمية ببيانات فقط بلا استثناء (§1).
      await _create(kind, includeImages: false);
      return;
    }
    // الساعية: تخطي البطارية ثم تخطي 95% من الحصة (§8-3/§8-4).
    final battery = await this.battery();
    if (battery != null && battery < kHourlyBatteryFloorPercent) {
      final h = health.value;
      health.value = BackupHealth(
        lastAnyUtc: h?.lastAnyUtc,
        noBackupFor30Days: h?.noBackupFor30Days ?? false,
        attachmentsStale: h?.attachmentsStale ?? false,
        latestWithImagesUtc: h?.latestWithImagesUtc,
        quotaUsedFraction: h?.quotaUsedFraction ?? 0,
        hourlySkippedBattery: true,
        computedAtUtc: nowUtc(),
      );
      return;
    }
    final usage = await store!.usageBytes();
    if (quotaBytes > 0 &&
        usage / quotaBytes >= kBackupQuotaHourlySkipFraction) {
      await store!.trimToQuota(
          capBytes: quotaBytes, incomingBytes: 0);
      final after = await store!.usageBytes();
      if (quotaBytes > 0 && after / quotaBytes >= 0.95) {
        final h = health.value;
        health.value = BackupHealth(
          lastAnyUtc: h?.lastAnyUtc,
          noBackupFor30Days: h?.noBackupFor30Days ?? false,
          attachmentsStale: h?.attachmentsStale ?? false,
          latestWithImagesUtc: h?.latestWithImagesUtc,
          quotaUsedFraction: after / quotaBytes,
          hourlySkippedQuota: true,
          computedAtUtc: nowUtc(),
        );
        return;
      }
    }
    await _create(kind, includeImages: false);
  }

  Future<void> _create(BackupScheduleKind kind,
      {required bool includeImages}) async {
    _running = true;
    try {
      await store!.createScheduled(
        db,
        kind,
        includeImages: includeImages,
        imagesDir:
            includeImages ? Directory(imagesDirFor(dbPath)) : null,
      );
      await refreshHealth();
    } catch (e) {
      // الفشل إشعار واضح لا صمت (§8-8): شارة حمراء وسجل خطأ بالقاعدة.
      await db.logError(
          code: 'DQ-1123',
          message: 'فشل نسخة $kind: $e',
          context: 'backup_center');
      final h = health.value;
      health.value = BackupHealth(
        lastAnyUtc: h?.lastAnyUtc,
        noBackupFor30Days: h?.noBackupFor30Days ?? false,
        attachmentsStale: h?.attachmentsStale ?? false,
        latestWithImagesUtc: h?.latestWithImagesUtc,
        quotaUsedFraction: h?.quotaUsedFraction ?? 0,
        failureMessage: 'فشل نسخة ${kind.label}: $e',
        computedAtUtc: nowUtc(),
      );
    } finally {
      _running = false;
    }
  }

  /// السنوية عند الإقفال (§2): بيانات + مرفقات، دائمة لا تدور أبداً.
  Future<BackupCatalogEntry?> createAnnualBackup() =>
      _guardedCreate(BackupScheduleKind.annual, includeImages: true);

  /// الحدثية قبل إقفال السنة (§2): بيانات + مرفقات، آخر 5.
  Future<BackupCatalogEntry?> createYearCloseEventBackup() =>
      _guardedCreate(BackupScheduleKind.event, includeImages: true);

  Future<BackupCatalogEntry?> _guardedCreate(BackupScheduleKind kind,
      {required bool includeImages}) async {
    if (store == null) return null;
    final wasPaused = _paused;
    _paused = true; // أثناء الحدثية لا يزاحمها دوري (§8-5).
    try {
      final entry = await store!.createScheduled(
        db,
        kind,
        includeImages: includeImages,
        imagesDir:
            includeImages ? Directory(imagesDirFor(dbPath)) : null,
        atUtc: nowUtc(), // ساعة المركز المحقونة — أحداث متمايزة بالثانية.
      );
      await refreshHealth();
      return entry;
    } catch (_) {
      return null;
    } finally {
      _paused = wasPaused;
    }
  }

  /// تبني نسخة يدوية بالكتالوج بعد نجاحها — لإعادة ضبط تذكير المرفقات.
  Future<void> registerManualBackup(
      String path, bool includesImages) async {
    if (store == null) return;
    await store!.registerManual(path, includesImages: includesImages);
    await refreshHealth();
  }

  /// بعد استعادة ناجحة: تدوير لقطات ما قبل الاستعادة على آخر 5 —
  /// و[protectFileName] لقطةٌ مثبتة نافذةَ تراجعٍ مفتوحة (د-3-2، س136)
  /// فمستثناة من التدوير كلياً.
  Future<void> afterRestore({String? protectFileName}) async {
    if (store == null) return;
    await store!.rotateBeforeRestoreSnapshots(
        protectFileName: protectFileName);
    await refreshHealth();
  }

  /// إعادة حساب الشارات — ثلاثية القسم 6 بالتقرير: 30 يوماً، مرفقات
  /// متقادمة، حصة/فشل. تُستدعى عند الإقلاع وبعد كل نسخة وبعد الضبط.
  Future<void> refreshHealth() async {
    if (store == null) return;
    final now = nowUtc();
    final catalog = store!.catalog;
    final latestAny = catalog.latestAnyUtc();
    final imagesDir = Directory(imagesDirFor(dbPath));
    DateTime? latestImage;
    if (await imagesDir.exists()) {
      await for (final f in imagesDir.list()) {
        if (f is File) {
          final m = (await f.stat()).modified.toUtc();
          if (latestImage == null || m.isAfter(latestImage)) latestImage = m;
        }
      }
    }
    final usage = await store!.usageBytes();
    final prev = health.value;
    health.value = BackupHealth(
      lastAnyUtc: latestAny,
      noBackupFor30Days: noBackupFor30Days(
          nowUtc: now, latestAnyUtc: latestAny),
      attachmentsStale: attachmentsReminderDue(
        latestAttachmentChangeUtc: latestImage,
        latestWithImagesUtc: catalog.latestWithImagesUtc(),
      ),
      latestWithImagesUtc: catalog.latestWithImagesUtc(),
      quotaUsedFraction:
          quotaBytes > 0 ? usage / quotaBytes : 0,
      hourlySkippedQuota: prev?.hourlySkippedQuota ?? false,
      hourlySkippedBattery: prev?.hourlySkippedBattery ?? false,
      failureMessage: prev?.failureMessage,
      computedAtUtc: now,
    );
  }

  /// إيقاف نهائي عند طيّ الشاشة (الاستعادة تستدعيه قبل إغلاق القاعدة).
  Future<void> shutdown() async {
    _timer?.cancel();
    _timer = null;
    if (identical(instance, this)) instance = null;
  }
}
