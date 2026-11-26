/// د5 (س174 — الأرشفة الآلية والانضمام والإبطال — بكلمة المالك الحرفية
/// «تابع مع د5» بنص خارطة م4 §46): الأرشفة السحابية الدورية F-137/م-31 —
/// «نسخة احتياطية كاملة مشفرة ترفع آلياً دورياً عند توفر الاتصال مع
/// الاحتفاظ بآخر 30 نسخة» نص 08 §5، و«الأرشفة التلقائية اليومية مع
/// الاحتفاظ بآخر 30 نسخة» نص م-31 المؤكدة.
///
/// **نقية حصراً** (F-010): لا dart:io ولا Flutter ولا شبكة — السياسة
/// والاحتفاظ والكتالوج نموذجَ بيانات وصياغة JSON، أما توليد النسخة
/// ورفعها وحذف ما تجاوز الحد فقرارُ المنفذ (المهايئ/التخزين) بعد نجاح
/// الجديدة وتحققها (نمط ق-ن4 بالجدولة المحلية: الحذف بعد النجاح لا
/// قبله ولا بقرار الوحدة).
///
/// **مسار الاستعادة واحد لا ثانٍ (معيار قبول د5 نص الخارطة)**: الأرشيف
/// الناتج نسخةٌ قياسية مشفرة بمفتاح البرنامج (F-012/D-060 بصيغتها
/// الجارية) تستهلكها بوابة الاستعادة المحلية F-013 ذاتها بلا آلية
/// ثانية تُصان وتُختبر — فالوحدة تحصّن ذلك وقتَ الترشيح للرفع: بايتات
/// ليست نسخة مشفرة قياسية بإصدارها الجاري تُرفض صوتاً مفهرسة DQ-1118
/// قبل أي رفع، فلا يصعد سحابياً ما لا تفتحه بوابة الاستعادة القائمة.
///
/// **الإيقاع اليومي نص م-31** بنمط اللحاق اليومي بالجدولة المحلية
/// (ق-ن6): مستحقٌ ما لم يكن هناك نجاح في اليوم المحلي الجاري —
/// و«عند توفر الاتصال» نص F-137: غياب الاتصال تأجيلٌ موثق يعاد به
/// الفحص عند كل فرصة، لا رفض ولا صمت.
library;

import 'dart:convert';

import 'backup.dart';
import 'backup_schedule.dart';

/// حد الاحتفاظ بالأرشفة السحابية نص م-31 حرفاً: آخر 30 نسخة.
const int cloudArchiveRetention = 30;

/// لاحقة الأرشيف السحابي — أخو المجدولة المحلية (D-207) فبوابة
/// الاستعادة تقبل اللاحقتين أصلاً.
const String cloudArchiveFileExtension = 'dqk';

/// اسم ملف الأرشيف السحابي: `diqqah-cloud-<deviceTag>-<UTC>.dqk` —
/// بترميز D-207 ذاته ومعرّف نوعه `cloud` المميز فلا يلتبس بمجدولة
/// محلية، ومعرف الجهاز يُطهَّر بنمط backupDeviceTag ذاته.
String cloudArchiveFileName({
  required String deviceId,
  required DateTime atUtc,
}) =>
    'diqqah-cloud-${backupDeviceTag(deviceId)}-'
    '${formatBackupUtcStamp(atUtc)}.$cloudArchiveFileExtension';

/// تحليل اسم أرشيف سحابي — null لغيره (أسماء المجدولة المحلية ويدوية
/// النمط لها محللوها، وهنا الملفات السحابية حصراً).
ParsedCloudArchiveName? parseCloudArchiveFileName(String fileName) {
  final m = RegExp(
          r'^diqqah-cloud-([a-z0-9]{1,16})-(\d{8}T\d{6}Z)\.dqk$')
      .firstMatch(fileName);
  if (m == null) return null;
  final atUtc = parseBackupUtcStamp(m.group(2)!);
  if (atUtc == null) return null;
  return ParsedCloudArchiveName(
      deviceTag: m.group(1)!, atUtc: atUtc);
}

/// اسم أرشيف سحابي مُحلَّل.
class ParsedCloudArchiveName {
  final String deviceTag;
  final DateTime atUtc;
  const ParsedCloudArchiveName(
      {required this.deviceTag, required this.atUtc});
}

/// صف الأرشيف السحابي — النسخة الواحدة بحقائقها (نمط صف الكتالوج
/// المحلي بbackup_schedule، بلا مجلدٍ محلي: الموضع على الخادم بعقد
/// المزوّد لا هنا).
class CloudArchiveRecord {
  final String fileName;
  final DateTime atUtc;
  final int sizeBytes;

  /// بصمة المحتوى الصريح قبل التشفير (sha256HexOf بنمط ق-ن4) — شاهد
  /// المطابقة بين ما رُفع وما وُلّد.
  final String sha256Hex;
  final String deviceId;

  const CloudArchiveRecord({
    required this.fileName,
    required this.atUtc,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.deviceId,
  });

  /// JSON بمفاتيح مرتبة ثابتة — حتمية البصمة نص §10 بالروح نفسها.
  Map<String, Object?> toJson() => {
        'file': fileName,
        'at': atUtc.toIso8601String(),
        'size': sizeBytes,
        'sha256': sha256Hex,
        'device': deviceId,
      };

  /// الصف من JSON — null عند أي حقل فاسد أو تاريخ غير UTC (الصف
  /// يُسقط لا يُخمَّد: الكتالوج قابل لإعادة البناء من قائمة الخادم
  /// بنمط الكتالوج المحلي ق-ن5).
  static CloudArchiveRecord? fromJson(Map<String, Object?> json) {
    final at = DateTime.tryParse('${json['at']}');
    final fileName = '${json['file']}';
    final device = '${json['device']}';
    final size = (json['size'] as num?)?.toInt();
    final sha = json['sha256'] == null ? null : '${json['sha256']}';
    if (at == null || !at.isUtc) return null;
    if (fileName.isEmpty || device.isEmpty) return null;
    if (size == null || size < 0) return null;
    if (sha == null || sha.isEmpty) return null;
    return CloudArchiveRecord(
      fileName: fileName,
      atUtc: at,
      sizeBytes: size,
      sha256Hex: sha,
      deviceId: device,
    );
  }
}

/// كتالوج الأرشفة السحابية — ما على الخادم بوجهة نظر هذا الجهاز.
/// فاسدٌ يعود فارغاً (قابل لإعادة البناء بقائمة الخادم نمط ق-ن5 —
/// ولا يفقد أمناً فحذفُ الكتالوج لا يحذف نسخاً ولا يُبطل إبطالاً).
class CloudArchiveRegistry {
  final List<CloudArchiveRecord> records;

  CloudArchiveRegistry({List<CloudArchiveRecord>? records})
      : records = List.of(records ?? const <CloudArchiveRecord>[]);

  /// إضافة أو استبداد بملف مطابق (نمط الكتالوج المحلي).
  void add(CloudArchiveRecord record) {
    records.removeWhere((e) => e.fileName == record.fileName);
    records.add(record);
  }

  void remove(String fileName) {
    records.removeWhere((e) => e.fileName == fileName);
  }

  /// الصفوف بالأحدث أولاً.
  List<CloudArchiveRecord> get newestFirst => [...records]
    ..sort((a, b) => b.atUtc.compareTo(a.atUtc));

  /// أحدث أرشيف ناجح — مدخل الاستحقاق اليومي.
  DateTime? get latestUtc => newestFirst.isEmpty
      ? null
      : newestFirst.first.atUtc;

  String toJson() => jsonEncode(<String, Object?>{
        'version': 1,
        'records': [for (final r in newestFirst) r.toJson()],
      });

  /// الكتالوج من نص JSON — فاسد/مجهول يعود فارغاً (إعادة البناء من
  /// قائمة الخادم نمط ق-ن5).
  static CloudArchiveRegistry fromJson(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map<String, Object?>) return CloudArchiveRegistry();
      final raw = root['records'];
      final records = raw is List
          ? [
              for (final r in raw)
                if (r is Map<String, Object?>) CloudArchiveRecord.fromJson(r),
            ].whereType<CloudArchiveRecord>().toList()
          : <CloudArchiveRecord>[];
      return CloudArchiveRegistry(records: records);
    } catch (_) {
      return CloudArchiveRegistry();
    }
  }
}

/// الاستحقاق اليومي نص م-31 بنمط اللحاق المحلي (ق-ن6):
/// - بلا اتصال: لا استحقاق الآن — تأجيل موثق نص F-137 «عند توفر
///   الاتصال» يعاد فحصه عند كل فرصة (لا رفض ولا صمت).
/// - بلا نجاح سابق: مستحق (أول تشغيل بنمط اللحاق).
/// - آخر نجاح قبل بداية اليوم المحلي الجاري: مستحق — اليومية حرفاً.
/// - آخر نجاح داخل اليوم المحلي الجاري (أو مستقبلاً بانحراف ساعة):
///   غير مستحق.
bool cloudArchiveDue({
  required DateTime nowUtc,
  required DateTime nowLocal,
  required DateTime? lastSuccessUtc,
  required bool connectivityAvailable,
}) {
  if (!connectivityAvailable) return false;
  if (lastSuccessUtc == null) return true;
  return lastSuccessUtc
      .isBefore(startOfLocalDay(nowLocal).toUtc());
}

/// خطة التقليم نص م-31: ما تجاوز آخر 30 نسخة — بالأقدم أولاً لترتيب
/// الحذف (نمط _beyondFloorScheduled بالجدولة المحلية). والحذف قرار
/// المنفذ **بعد** نجاح رفع الجديدة وتحققها (نمط ق-ن4) فلا فجوة
/// سحابية إن فشل الرفع.
List<CloudArchiveRecord> planCloudArchivePrune(
    List<CloudArchiveRecord> records) {
  final sorted = [...records]..sort((a, b) => b.atUtc.compareTo(a.atUtc));
  if (sorted.length <= cloudArchiveRetention) return const [];
  return sorted.sublist(cloudArchiveRetention)
    ..sort((a, b) => a.atUtc.compareTo(b.atUtc));
}

/// يُرمى حين بايتات مرشّحة للرفع السحابي ليست نسخة قياسية مشفرة
/// بإصدارها الجاري — DQ-1118 (مسار الاستعادة واحد لا ثانٍ نص د5).
class CloudArchivePayloadException implements Exception {
  final String message;
  const CloudArchivePayloadException(this.message);
  @override
  String toString() => message;
}

/// تحصين «مسار واحد لا ثانٍ» قبل أي رفع: المرشح للسحابة نسخةٌ مشفرة
/// بمفتاح البرنامج بإصدارها الجاري حصراً — بنفس مُعرِّف الصيغة الذي
/// تفتتح به بوابة الاستعادة المحلية F-013 (D-1104/D-1014) فما يصعد
/// سحابياً تفتحه البوابة ذاتها بلا آلية ثانية تُصان وتُختبر.
void validateCloudArchivePayload(List<int> bytes) {
  if (bytes.length < 8) {
    throw const CloudArchivePayloadException(
        'الأرشيف المرشّح للسحابة أقصر من ترويسة النسخة المشفرة — '
        'لا رفع (DQ-1118)');
  }
  final kind = BackupCipher.identify(bytes);
  if (kind != BackupKind.encrypted) {
    throw const CloudArchivePayloadException(
        'الأرشيف المرشّح للسحابة ليس نسخة مشفرة قياسية — الأرشفة '
        'السحابية بنسخة بوابة الاستعادة ذاتها لا بآلية ثانية (DQ-1118)');
  }
  final version = BackupCipher.encryptedVersion(bytes);
  if (version != BackupCipher.formatVersion) {
    throw CloudArchivePayloadException(
        'الأرشيف المرشّح للسحابة بإصدار ملف قديم ($version) والإصدار '
        'الجاري ${BackupCipher.formatVersion} — لا رفع بغير الصيغة '
        'الجارية (DQ-1118)');
  }
}
