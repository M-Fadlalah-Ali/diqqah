/// جدولة النسخ الاحتياطي GFS — السياسة النقية (تكليف المالك 2026-11-13
/// بقراراته ق-ن1..ق-ن8). هذه الوحدة نقية حصراً بلا dart:io بلا Flutter
/// (F-010): التسمية والحدود واللحاق والاحتفاظ وسقف الحصة والكتالوج
/// نموذجَ بيانات وصياغة JSON — أما قراءة الملفات وكتابتها فمحرك التخزين
/// (backup_gfs.dart) وحده.
///
/// القرارات المنعكسة هنا حرفاً:
/// - ق-ن4: تحقق متدرج — الساعية فك+ترويسة+SHA-256؛ اليومية فما فوق
///   والحدثية والسنوية وبقبل أي حذف: integrity_check كامل.
/// - ق-ن5: الكتالوج JSON جانبي بترميز الأسماء قابل لإعادة البناء
///   بالمسح — لا يُخزَّن داخل القاعدة (ثباته عبر الاستعادة).
/// - ق-ن6: اليومية لحاق أول تشغيل — لا «عند الإغلاق» (أندرويد غير موثوق).
/// - ق-ن3: سقف حصة بايتات ثابت (2GB افتراضياً) بلا نسبة ديناميكية.
/// - قرار التسمية (D-207): diqqah-<type>-<device>-<UTC>.dqk.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// نوع دورة النسخة — لا يسمى BackupKind لأن الاسم محجوز لمُعرِّف صيغة
/// الملف بمِلء المجال (BackupCipher.identify — backup.dart).
enum BackupScheduleKind {
  hourly,
  daily,
  weekly,
  monthly,
  annual,
  event,
  manual;

  /// رمز النوع بترميز أسماء الملفات (قرار التسمية D-207).
  String get symbol => switch (this) {
        BackupScheduleKind.hourly => 'h',
        BackupScheduleKind.daily => 'd',
        BackupScheduleKind.weekly => 'w',
        BackupScheduleKind.monthly => 'm',
        BackupScheduleKind.annual => 'y',
        BackupScheduleKind.event => 'e',
        BackupScheduleKind.manual => 'b',
      };

  /// التسمية العربية للعرض.
  String get label => switch (this) {
        BackupScheduleKind.hourly => 'ساعية',
        BackupScheduleKind.daily => 'يومية',
        BackupScheduleKind.weekly => 'أسبوعية',
        BackupScheduleKind.monthly => 'شهرية',
        BackupScheduleKind.annual => 'سنوية',
        BackupScheduleKind.event => 'حدثية',
        BackupScheduleKind.manual => 'يدوية',
      };

  /// هل نوع من الدورات التلقائية المجدولة (اللحاق يفحصها)؟ السنوية
  /// حدثية الإقفال لا دورة تقويمية، واليدوية قرار مستخدم — كلاهما خارج
  /// التقويم.
  bool get isScheduled => this == BackupScheduleKind.hourly ||
      this == BackupScheduleKind.daily ||
      this == BackupScheduleKind.weekly ||
      this == BackupScheduleKind.monthly;

  /// هل يُحذف آلياً بالتدوير؟ السنوية واليدوية لا تُمسّا آلياً أبداً
  /// (تكليف §2)؛ الأنواع الأخرى تدور على حدها.
  bool get isAutoRotated => this != BackupScheduleKind.annual &&
      this != BackupScheduleKind.manual;

  static BackupScheduleKind? fromSymbol(String s) =>
      BackupScheduleKind.values
          .where((k) => k.symbol == s)
          .firstOrNull;
}

/// حدود الاحتفاظ بالأنواع الدوارة (تكليف §2) — السنوية واليدوية بلا حد.
const Map<BackupScheduleKind, int> backupRetentionLimits = {
  BackupScheduleKind.hourly: 15,
  BackupScheduleKind.daily: 8,
  BackupScheduleKind.weekly: 5,
  BackupScheduleKind.monthly: 12,
  BackupScheduleKind.event: 5,
};

/// سقف حصة مجلد النسخ بايتات (ق-ن3: 2GB افتراضياً قابل للتعديل من
/// الإعدادات — قرار صاحب التطبيق). عتبة التحذير 80% وعتبة تخطي
/// الساعية 95% (تكليف §8).
const int kDefaultBackupQuotaBytes = 2 * 1024 * 1024 * 1024;
const double kBackupQuotaWarnFraction = 0.80;
const double kBackupQuotaHourlySkipFraction = 0.95;

/// لاحقة ملفات النسخ المجدولة الجديدة — قرار التسمية D-207. النسخ
/// اليدوية القائمة تبقى بلاحقة `.diqqah` (D-061) والقارئ يقبل الصيغتين.
const String kScheduledBackupExtension = 'dqk';

/// ختم UTC مضغوط بصيغة أسماء الملفات: `20261113T101530Z`.
String formatBackupUtcStamp(DateTime atUtc) {
  assert(atUtc.isUtc, 'ختم النسخ يُخزَّن UTC حصراً (تكليف §8-2)');
  String two(int n) => n.toString().padLeft(2, '0');
  return '${atUtc.year.toString().padLeft(4, '0')}'
      '${two(atUtc.month)}${two(atUtc.day)}'
      'T${two(atUtc.hour)}${two(atUtc.minute)}${two(atUtc.second)}Z';
}

/// تحليل ختم UTC مضغوط — null إن أعيد التحرير صياغة غير صالحة.
DateTime? parseBackupUtcStamp(String stamp) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$')
      .firstMatch(stamp);
  if (m == null) return null;
  final dt = DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
  // إعادة التنسيق تطابق الحرفية — يمنع التواريخ المستحيلة بالختم ذاته.
  return formatBackupUtcStamp(dt) == stamp ? dt : null;
}

/// رمز الجهاز بأسماء الملفات — ثمانية محارف نظيفة من معرّف الجهاز
/// (المعرّف الكامل بUUID؛ الرمز القصير يكفي التمييز البشري والكتالوج
/// يحمل الاسم الكامل للعرض محلياً، وما بعد م4 يحمل أسماء الأجهزة الأخرى).
String backupDeviceTag(String deviceId) {
  final clean = deviceId.replaceAll(
      RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
  return clean.length > 8 ? clean.substring(0, 8) : clean;
}

/// اسم ملف نسخة مجدولة: `diqqah-<type>-<device>-<UTC>.dqk` (D-207).
String scheduledBackupFileName({
  required BackupScheduleKind kind,
  required String deviceTag,
  required DateTime atUtc,
}) =>
    'diqqah-${kind.symbol}-$deviceTag-'
    '${formatBackupUtcStamp(atUtc)}.$kScheduledBackupExtension';

/// اسم ملف الكتالوج الجانبي — أخو الملفات في مجلد النسخ ذاته.
const String kBackupCatalogFileName = 'diqqah-backup-catalog.json';

/// ملف نسخة مجدولة مُحلَّل.
class ParsedBackupFileName {
  final BackupScheduleKind kind;
  final String deviceTag;
  final DateTime atUtc;
  const ParsedBackupFileName(
      {required this.kind, required this.deviceTag, required this.atUtc});
}

/// تحليل اسم ملف مجدول بالترميز الجديد — null لغيره (يدوية/preup/قبل
/// استعادة لها ترميزها القائم ويُمسكها كشف المسح لا هذا المحلل).
ParsedBackupFileName? parseScheduledBackupFileName(String fileName) {
  final m = RegExp(
          r'^diqqah-([hdwmyeb])-([a-z0-9]{1,16})-(\d{8}T\d{6}Z)\.dqk$')
      .firstMatch(fileName);
  if (m == null) return null;
  final kind = BackupScheduleKind.fromSymbol(m.group(1)!);
  final atUtc = parseBackupUtcStamp(m.group(3)!);
  if (kind == null || atUtc == null) return null;
  return ParsedBackupFileName(
      kind: kind, deviceTag: m.group(2)!, atUtc: atUtc);
}

/// نمط أسماء النسخ اليدوية القائمة (D-061) — للكشف بالمسح.
final RegExp manualBackupNamePattern =
    RegExp(r'^diqqah-backup-.+\.diqqah$');

/// نمط لقطات ما قبل الاستعادة القائمة — كشف بالمسح (تُبقى آخر 5).
final RegExp beforeRestoreSnapshotPattern =
    RegExp(r'^diqqah-before-restore-.+\.db$');

/// حالة تحقق النسخة بالتدرج المعتمد (ق-ن4).
enum BackupVerifyState { none, quick, full, failed }

extension BackupVerifyStateName on BackupVerifyState {
  String get wire => switch (this) {
        BackupVerifyState.none => 'none',
        BackupVerifyState.quick => 'quick',
        BackupVerifyState.full => 'full',
        BackupVerifyState.failed => 'failed',
      };
  static BackupVerifyState fromWire(String s) => switch (s) {
        'quick' => BackupVerifyState.quick,
        'full' => BackupVerifyState.full,
        'failed' => BackupVerifyState.failed,
        _ => BackupVerifyState.none,
      };
}

/// صف الكتالوج — النسخة الواحدة بكل حقائقها التشغيلية (تكليف §8-6).
class BackupCatalogEntry {
  final String fileName;
  final BackupScheduleKind kind;
  final DateTime atUtc;
  final int sizeBytes;
  final String? sha256Hex;
  final int? schemaVersion;
  final String? appVersion;
  final String deviceTag;
  final bool includesImages;
  final BackupVerifyState verifyState;

  /// مجلد النسخة — تُحسم عند التحميل لا تُخزَّن (مسارات الأجهزة تختلف).
  final String folderId;

  const BackupCatalogEntry({
    required this.fileName,
    required this.kind,
    required this.atUtc,
    required this.sizeBytes,
    this.sha256Hex,
    this.schemaVersion,
    this.appVersion,
    required this.deviceTag,
    required this.includesImages,
    this.verifyState = BackupVerifyState.none,
    required this.folderId,
  });

  BackupCatalogEntry copyWith({
    BackupVerifyState? verifyState,
    String? sha256Hex,
    int? schemaVersion,
    int? sizeBytes,
  }) =>
      BackupCatalogEntry(
        fileName: fileName,
        kind: kind,
        atUtc: atUtc,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        sha256Hex: sha256Hex ?? this.sha256Hex,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        appVersion: appVersion,
        deviceTag: deviceTag,
        includesImages: includesImages,
        verifyState: verifyState ?? this.verifyState,
        folderId: folderId,
      );

  Map<String, Object?> toJson() => {
        'file': fileName,
        'kind': kind.symbol,
        'at': atUtc.toIso8601String(),
        'size': sizeBytes,
        'sha256': sha256Hex,
        'schema': schemaVersion,
        'app': appVersion,
        'device': deviceTag,
        'images': includesImages,
        'verify': verifyState.wire,
        'folder': folderId,
      };

  /// الصف من JSON — null عند أي حقل فاسد أو نوع مجهول (الصف يُسقط
  /// صراحة لا يُخمَّد: الكتالوج قابل لإعادة البناء بالمسح أصلاً).
  static BackupCatalogEntry? fromJson(Map<String, Object?> json) {
    final kind = BackupScheduleKind.fromSymbol('${json['kind']}');
    final at = DateTime.tryParse('${json['at']}');
    final fileName = '${json['file']}';
    if (kind == null || at == null || fileName.isEmpty) return null;
    if (!at.isUtc) return null;
    return BackupCatalogEntry(
      fileName: fileName,
      kind: kind,
      atUtc: at,
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      sha256Hex: json['sha256'] == null ? null : '${json['sha256']}',
      schemaVersion: (json['schema'] as num?)?.toInt(),
      appVersion: json['app'] == null ? null : '${json['app']}',
      deviceTag: '${json['device']}',
      includesImages: json['images'] == true,
      verifyState: BackupVerifyStateName.fromWire('${json['verify']}'),
      folderId: '${json['folder']}',
    );
  }
}

/// الكتالوج الجانبي (ق-ن5) — مصدر «آخر تشغيل ناجح» لكل نوع بعد قرار
/// صاحب التطبيق (ق-ن5: خارج القاعدة كي لا تتراجع زمنياً مع استعادة
/// نسخة أقدم — علة ث-6 بذاتها). حارس الرتابة (تكليف §8-2): الكتابة
/// لا تُرجع القيمة أبدياً — تكتب الأحدث.
class BackupCatalog {
  final List<BackupCatalogEntry> entries;
  final Map<BackupScheduleKind, DateTime?> lastSuccess;

  BackupCatalog({
    List<BackupCatalogEntry> entries = const [],
    Map<BackupScheduleKind, DateTime?> lastSuccess = const {},
  })  : entries = List.of(entries),
        lastSuccess = Map.of(lastSuccess);

  String toJson() => jsonEncode({
        'version': 1,
        'lastSuccess': {
          for (final k in BackupScheduleKind.values)
            if (lastSuccess[k] != null) k.symbol: lastSuccess[k]!.toIso8601String(),
        },
        'entries': [for (final e in entries) e.toJson()],
      });

  /// الكتالوج من نص JSON — فاسد/مجهول يعود كتالوجاً فارغاً (مسح المجلد
  /// يعيد بناءه؛ لا رسالة خطأ لأن الكتالوج صورة قابلة للتجديد).
  static BackupCatalog fromJson(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map<String, Object?>) return BackupCatalog();
      final lastSuccess = <BackupScheduleKind, DateTime?>{};
      final ls = root['lastSuccess'];
      if (ls is Map<String, Object?>) {
        for (final e in BackupScheduleKind.values) {
          final v = ls[e.symbol];
          final dt = v is String ? DateTime.tryParse(v) : null;
          if (dt != null && dt.isUtc) lastSuccess[e] = dt;
        }
      }
      final rawEntries = root['entries'];
      final entries = rawEntries is List
          ? [
              for (final r in rawEntries)
                if (r is Map<String, Object?>)
                  BackupCatalogEntry.fromJson(r),
            ].whereType<BackupCatalogEntry>().toList()
          : <BackupCatalogEntry>[];
      return BackupCatalog(entries: entries, lastSuccess: lastSuccess);
    } catch (_) {
      return BackupCatalog();
    }
  }

  /// إضافة صف — استبداد بملف مطابق (تحقق معاد بعيد حصة).
  void addEntry(BackupCatalogEntry entry) {
    entries.removeWhere((e) =>
        e.fileName == entry.fileName && e.folderId == entry.folderId);
    entries.add(entry);
  }

  void removeEntry({required String fileName, required String folderId}) {
    entries.removeWhere(
        (e) => e.fileName == fileName && e.folderId == folderId);
  }

  /// تسجيل نجاح نوع — حارس الرتابة: القيمة لا تتراجع أبداً (تكليف
  /// §8-2) فيمنع تقادم زائف بضبط ساعة الجهاز الحذفَ المبكر.
  void recordSuccess(BackupScheduleKind kind, DateTime atUtc) {
    final prev = lastSuccess[kind];
    lastSuccess[kind] =
        prev == null || atUtc.isAfter(prev) ? atUtc : prev;
  }

  /// صفوف نوع بترتيب الأحدث أولاً.
  List<BackupCatalogEntry> entriesFor(BackupScheduleKind kind) => [
        for (final e in entries)
          if (e.kind == kind) e,
      ]..sort((a, b) => b.atUtc.compareTo(a.atUtc));

  /// أحدث نسخة إطلاقاً من أي نوع — مقياس تذكير الثلاثين يوماً (§10-1).
  DateTime? latestAnyUtc() {
    DateTime? latest;
    for (final e in entries) {
      if (latest == null || e.atUtc.isAfter(latest)) latest = e.atUtc;
    }
    for (final v in lastSuccess.values) {
      if (v != null && (latest == null || v.isAfter(latest))) latest = v;
    }
    return latest;
  }

  /// أحدث نسخة تضم المرفقات — مقياس التذكير الذكي (تكليف §3).
  DateTime? latestWithImagesUtc() {
    DateTime? latest;
    for (final e in entries) {
      if (!e.includesImages) continue;
      if (latest == null || e.atUtc.isAfter(latest)) latest = e.atUtc;
    }
    return latest;
  }
}

/// خطة التدوير: أسماء ملفات النوع الزائدة عن حده بالأقدم أولاً —
/// حذفها قرار المنفذ بعد نجاح الجديدة وتحققها (ق-ن4). الأنواع بلا
/// تدوير (سنوية/يدوية) خطة فارغة دائماً.
List<BackupCatalogEntry> planRotation(
    BackupScheduleKind kind, List<BackupCatalogEntry> ofKindSorted) {
  final limit = backupRetentionLimits[kind];
  if (limit == null || !kind.isAutoRotated) return const [];
  if (ofKindSorted.length <= limit) return const [];
  return ofKindSorted.sublist(limit); // مرتبة الأحدث أولاً → الذيل أقدم.
}

/// خطة تقليم السقف (ق-ن3): أقدم نسخ الدورات التلقائية حصراً (h/d/w/m)
/// — السنوية والحدثية واليدوية لا تُمس بالسقف أبداً — بالعدد الأدنى الذي
/// يجعل (المستعمل − المحذوف + القادمة) ≤ السقف.
///
/// د-4 (§25.8، س136): **الأرضية النظامية تسري على السقف** — آخر نسخة
/// من كل نوع محمية فلا تُحذف تحت ضغط الحصة أبداً؛ فإن منعت الأرضية
/// بلوغ السقف توقف الحذف صادقاً (التحذير يتكفل بالبقية لا الحذف القسري).
List<BackupCatalogEntry> planCapTrim({
  required int usageBytes,
  required int capBytes,
  required int incomingBytes,
  required List<BackupCatalogEntry> entries,
}) {
  final deletable = _beyondFloorScheduled(entries);
  final toDelete = <BackupCatalogEntry>[];
  var projected = usageBytes + incomingBytes;
  for (final e in deletable) {
    if (projected <= capBytes) break;
    toDelete.add(e);
    projected -= e.sizeBytes;
  }
  return toDelete;
}

/// القابلة للحذف من التلقائية بعد سريان الأرضية (د-4): لكل نوع مجدول
/// (h/d/w/m) كل ما عدا أحدثه — الأرضية (آخر نسخة من النوع) مستثناة
/// وحدها، والقائمة ترجع بالأقدم أولاً لترتيب الحذف.
List<BackupCatalogEntry> _beyondFloorScheduled(
    List<BackupCatalogEntry> entries) {
  final byKind = <BackupScheduleKind, List<BackupCatalogEntry>>{};
  for (final e in entries) {
    if (!e.kind.isScheduled) continue; // h/d/w/m حصراً
    (byKind[e.kind] ??= []).add(e);
  }
  final out = <BackupCatalogEntry>[];
  for (final list in byKind.values) {
    list.sort((a, b) => b.atUtc.compareTo(a.atUtc)); // الأحدث أولاً
    if (list.length <= 1) continue; // النسخة الوحيدة أرضية
    out.addAll(list.sublist(1)); // كل ما عدا الأحدث
  }
  out.sort((a, b) => a.atUtc.compareTo(b.atUtc)); // الأقدم أولاً للحذف
  return out;
}

/// الأرضية النظامية (د-4 — §25.8، س136): آخر نسخة من كل نوع — أي نوع
/// حاضر بالكتالوج (تلقائية وسنوية وحدثية ويدوية) — لا تُحذف من داخل
/// التطبيق مطلقاً. تعيد أسماء ملفاتها المحمية؛ الحذف المُدار (فردياً
/// أو بتنظيف ذكي) يرفضها حائطاً صلباً تحت أي واجهة.
Set<String> protectedFloorFileNames(List<BackupCatalogEntry> entries) {
  final newest = <BackupScheduleKind, BackupCatalogEntry>{};
  for (final e in entries) {
    final cur = newest[e.kind];
    if (cur == null || e.atUtc.isAfter(cur.atUtc)) newest[e.kind] = e;
  }
  return {for (final e in newest.values) e.fileName};
}

/// اقتراح التنظيف الذكي (د-8 — §25.8، س136): **اقتراح معروض لا حذف** —
/// عند بلوغ منطقة التحذير (80% من السقف — العتبة ذاتها التي تشتعل بها
/// لوحة التذكيرات القائمة) يقترح حذف الأقدم من القابلة للتدوير
/// (h/d/w/m) مع الإبقاء على الأرضية، حتى العودة **تحت** العتبة فتخمد
/// الشارة. ما دون العتبة لا اقتراح له، وما لم يبلغها بعد حذف ما أمكن
/// توقف صادقاً — والتنفيذ بيد المستخدم بعرضه واعتماده بتأكيد مزدوج.
List<BackupCatalogEntry> planSmartCleanup({
  required List<BackupCatalogEntry> entries,
  required int usageBytes,
  required int capBytes,
}) {
  if (capBytes <= 0) return const [];
  final warnTarget = (capBytes * kBackupQuotaWarnFraction).floor();
  if (usageBytes < warnTarget) return const [];
  final plan = <BackupCatalogEntry>[];
  var projected = usageBytes;
  for (final e in _beyondFloorScheduled(entries)) {
    if (projected < warnTarget) break;
    plan.add(e);
    projected -= e.sizeBytes;
  }
  return plan;
}

/// بداية اليوم المحلي — حدود «يومية عند أول تشغيل» (ق-ن6).
DateTime startOfLocalDay(DateTime local) =>
    DateTime(local.year, local.month, local.day);

/// بداية الأسبوع المحلي — السبت (تكليف §2؛ أول يوم أسبوع ثابت بالنسخة
/// الأولى وتوسعته بالإعدادات قرار لاحق).
DateTime startOfLocalWeekSaturday(DateTime local) {
  final day = startOfLocalDay(local);
  // DateTime.weekday: السبت=6 الأحد=7. نرجع أقرب سبت ≤ اليوم.
  final shift = (day.weekday - 6 + 7) % 7;
  return day.subtract(Duration(days: shift));
}

/// بداية الشهر المحلي.
DateTime startOfLocalMonth(DateTime local) =>
    DateTime(local.year, local.month, 1);

/// الدورات المستحقة الآن — سياسة اللحاق بنسخة واحدة (تكليف §8-1):
/// لا نعيد كل الفائت بل ننظر: هل آخر نجاح قبل حدود اليوم/الأسبوع/الشهر
/// المحلية؟ فالمجموعة تُنفَّذ مرة واحدة عند أول تشغيل ثم تهدأ الحدود.
Set<BackupScheduleKind> dueAutoKinds({
  required DateTime nowUtc,
  required DateTime nowLocal,
  required Map<BackupScheduleKind, DateTime?> lastSuccess,
}) {
  final due = <BackupScheduleKind>{};
  final hourlyLast = lastSuccess[BackupScheduleKind.hourly];
  if (hourlyLast == null ||
      nowUtc.difference(hourlyLast) >= const Duration(hours: 1)) {
    due.add(BackupScheduleKind.hourly);
  }
  final dayStart = startOfLocalDay(nowLocal);
  final dailyLast = lastSuccess[BackupScheduleKind.daily];
  if (dailyLast == null || dailyLast.isBefore(dayStart.toUtc())) {
    due.add(BackupScheduleKind.daily);
  }
  final weekStart = startOfLocalWeekSaturday(nowLocal);
  final weeklyLast = lastSuccess[BackupScheduleKind.weekly];
  if (weeklyLast == null || weeklyLast.isBefore(weekStart.toUtc())) {
    due.add(BackupScheduleKind.weekly);
  }
  final monthStart = startOfLocalMonth(nowLocal);
  final monthlyLast = lastSuccess[BackupScheduleKind.monthly];
  if (monthlyLast == null || monthlyLast.isBefore(monthStart.toUtc())) {
    due.add(BackupScheduleKind.monthly);
  }
  return due;
}

/// تذكير الثلاثين يوماً (معيار القبول §10-1): لا نسخة من أي نوع منذ
/// 30 يوماً أو أكثر (أو لا نسخة إطلاقاً).
bool noBackupFor30Days({
  required DateTime nowUtc,
  required DateTime? latestAnyUtc,
}) {
  if (latestAnyUtc == null) return true;
  return nowUtc.difference(latestAnyUtc) >= const Duration(days: 30);
}

/// التذكير الذكي للمرفقات (تكليف §3): مرفقات تغيرت بعد آخر نسخة تضمها
/// (أو لا نسخة تضمها أصلاً) — رسالة مبنية على حالة البيانات الفعلية
/// لا تذكيراً عاماً.
bool attachmentsReminderDue({
  required DateTime? latestAttachmentChangeUtc,
  required DateTime? latestWithImagesUtc,
}) {
  if (latestAttachmentChangeUtc == null) return false;
  if (latestWithImagesUtc == null) return true;
  return latestAttachmentChangeUtc.isAfter(latestWithImagesUtc);
}

/// بصمة SHA-256 للنص الصريح للنسخة — تُحسب مرة عند الإنشاء وتقارن
/// عند كل تحقق سريع (ق-ن4). نقية هنا كي يستهلكها التخزين بلا تبعية
/// جديدة (crypto تبعية مجال قائمة).
String sha256HexOf(List<int> plain) =>
    sha256.convert(plain).toString();
