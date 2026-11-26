/// د5 الشطر الثاني (س174 — الأرشفة الآلية والانضمام والإبطال — بكلمة
/// المالك الحرفية «تابع مع د5» بنص خارطة م4 §46): **رمز الانضمام
/// م-32** — «المدير يولده من جهاز موثوق، استهلاك واحد، صلاحية 24
/// ساعة» نص 08 §5 المؤكدة — و**الجهاز المفقود/المسروق م-33** —
/// «أحداث الجهاز المفقود أو المسروق تبقى في السجل إلى الأبد مع إبطال
/// صلاحياته فقط — لا حذف تاريخ» نص 08 §6 المؤكدة، وخيار «مسح عند أول
/// اتصال» نص م-33.
///
/// **نقية حصراً** (F-010): لا dart:io ولا Flutter ولا شبكة — الكتاب
/// والسجل نموذجَ بيانات وصياغة JSON وحسم قراءاتي، أما الفرض الخادمي
/// (رفض المُبطَل عند النقل) فموضعه المهايئ والخادم بعقد F-136 «لا
/// يثق أحد بطرفٍ آخر» — وهنا عقد الحكم المحلي الذي يفرض به الجهاز
/// والخادم معاً.
///
/// **حدّا أمنيان موثقان**:
/// - سجل الأجهزة **يفشل مقفلاً** عند أي فساد: الإبطال حمايةٌ فلا
///   يُصمت عن فساد سجلها إطلاقاً ولا يعاد بناؤه بالمسح كالكتالوج —
///   الفساد استثناء مفهرس يُرفع للمالك (نقيض الكتالوج القابل
///   لإعادة البناء — والفرق مقصود موثق).
/// - **لا حذف تاريخ نص م-33 حرفاً**: الوحدة بلا أي API حذفٍ أو تقليم
///   لصف جهاز أو لحدث — الإبطال قلبُ حالةٍ فقط، وأحداث الجهاز
///   append-only بالسجل الحدثي ذاته (وعرف p3/س153 حاجزُه البنيوي
///   قائم)، والحاجزُ بلا اتصال هو التشفير المحلي F-150 المنفذ س148
///   — فلا شيئ هنا يُنجز عن تلك الطبقات ولا يزعمها.
library;

import 'dart:convert';
import 'dart:math';

/// صلاحية رمز الانضمام نص م-32 حرفاً: 24 ساعة.
const Duration joinCodeValidity = Duration(hours: 24);

/// طول رمز الانضمام المحرفي (بلا فاصل): ثمانية محارف من أبجدية بلا
/// ملتبس (لا 0/O ولا 1/I/L) فتُقرأ من الورق وتُكتب باليد بسلام.
const int joinCodeLength = 8;

/// أبجدية الرمز — 31 محرفاً بلا ملتبس.
const String joinCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// تطبيع الرمز: تجريد الفواصل والمسافات ورفع الحالة — القراءة من
/// الورق أو الرسالة تمر بهذا حصراً قبل أي حكم.
String normalizeJoinCode(String raw) => raw
    .replaceAll(RegExp(r'[\s\-–—]'), '')
    .toUpperCase();

/// هل الشكل المطبع سليم؟ ثمانية محارف من الأبجدية بلا ملتبس.
bool isValidJoinCodeShape(String normalized) =>
    normalized.length == joinCodeLength &&
    normalized.split('').every(joinCodeAlphabet.contains);

/// الصيغة البشرية المعروضة: «XXXX-XXXX».
String formatJoinCode(String normalized) {
  if (!isValidJoinCodeShape(normalized)) {
    throw FormatException('رمز انضمام غير سليم الشكل: "$normalized"');
  }
  return '${normalized.substring(0, 4)}-'
      '${normalized.substring(4)}';
}

/// يُرمى على كل رفض في عالم الانضمام — DQ-1116.
class JoinCodeException implements Exception {
  final String message;
  const JoinCodeException(this.message);
  @override
  String toString() => message;
}

/// صف رمز انضمام — تاريخه الكامل للسجل: مَن أصدره ومتى ومَن استهلكه.
class JoinCodeRecord {
  /// الرمز مطبعاً ثمانية محارف بلا فواصل.
  final String code;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final String issuedByDeviceId;

  /// الاستهلاك الواحد نص م-32: يُملأان عند أول استهلاك صحيح ولا
  /// يعودان فارغين بعده أبداً.
  final DateTime? consumedAtUtc;
  final String? consumedByDeviceId;

  const JoinCodeRecord({
    required this.code,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required this.issuedByDeviceId,
    this.consumedAtUtc,
    this.consumedByDeviceId,
  });

  bool get isConsumed => consumedAtUtc != null;

  JoinCodeRecord consumed({
    required DateTime atUtc,
    required String byDeviceId,
  }) =>
      JoinCodeRecord(
        code: code,
        issuedAtUtc: issuedAtUtc,
        expiresAtUtc: expiresAtUtc,
        issuedByDeviceId: issuedByDeviceId,
        consumedAtUtc: atUtc,
        consumedByDeviceId: byDeviceId,
      );

  /// JSON بمفاتيح مرتبة ثابتة.
  Map<String, Object?> toJson() => {
        'code': code,
        'issued': issuedAtUtc.toIso8601String(),
        'expires': expiresAtUtc.toIso8601String(),
        'issuedBy': issuedByDeviceId,
        if (consumedAtUtc != null)
          'consumedAt': consumedAtUtc!.toIso8601String(),
        if (consumedByDeviceId != null)
          'consumedBy': consumedByDeviceId,
      };

  /// الصف من JSON — null عند فساد أي حقل جوهري أو مفتاح غائب.
  static JoinCodeRecord? fromJson(Map<String, Object?> json) {
    final codeRaw = json['code'];
    if (codeRaw is! String) return null;
    final code = normalizeJoinCode(codeRaw);
    final issuedRaw = json['issued'];
    final expiresRaw = json['expires'];
    final issuedByRaw = json['issuedBy'];
    if (issuedRaw is! String || expiresRaw is! String) return null;
    final issued = DateTime.tryParse(issuedRaw);
    final expires = DateTime.tryParse(expiresRaw);
    if (!isValidJoinCodeShape(code)) return null;
    if (issued == null || !issued.isUtc) return null;
    if (expires == null || !expires.isUtc) return null;
    if (issuedByRaw is! String || issuedByRaw.trim().isEmpty) return null;
    final consumedAtRaw = json['consumedAt'];
    final consumedByRaw = json['consumedBy'];
    if ((consumedAtRaw == null) != (consumedByRaw == null)) return null;
    final consumedAt = consumedAtRaw == null
        ? null
        : DateTime.tryParse('$consumedAtRaw');
    if (consumedAtRaw != null &&
        (consumedAt == null || !consumedAt.isUtc)) {
      return null;
    }
    final consumedBy =
        consumedByRaw is String && consumedByRaw.isNotEmpty
            ? consumedByRaw
            : null;
    return JoinCodeRecord(
      code: code,
      issuedAtUtc: issued,
      expiresAtUtc: expires,
      issuedByDeviceId: issuedByRaw.trim(),
      consumedAtUtc: consumedAt,
      consumedByDeviceId: consumedBy,
    );
  }
}

/// كتاب رموز الانضمام — ما أصدره المدير وأسرسته الأجهزة.
class JoinCodeBook {
  final List<JoinCodeRecord> records;

  JoinCodeBook({List<JoinCodeRecord>? records})
      : records = List.of(records ?? const <JoinCodeRecord>[]);

  /// إصدار رمز جديد نص م-32 حرفاً:
  /// - **المدير حصراً**: حارس المصفوفة المحلية بيد المنفذ (F-136)
  ///   والوحدة ترفض بغيره صوتاً — لا رمز انضمام بيد غير المدير.
  /// - **من جهاز موثوق**: معرف الجهاز المُصدر إلزامي بغير فراغ.
  /// - عشوائية آمنة افتراضاً وقابلة للحقن حتمياً للاختبار — والرمز
  ///   الجديد لا يتصادم بما بالكتاب (إعادة السحب حتى التفرد).
  JoinCodeRecord issue({
    required String issuedByDeviceId,
    required DateTime nowUtc,
    required bool issuedByManager,
    Random? random,
  }) {
    if (!issuedByManager) {
      throw const JoinCodeException('رمز الانضمام يولده المدير حصراً '
          'من جهاز موثوق — نص م-32 (DQ-1116)');
    }
    final device = issuedByDeviceId.trim();
    if (device.isEmpty) {
      throw const JoinCodeException('إصدار رمز الانضمام يتطلب معرف '
          'الجهاز الموثوق المُصدر (DQ-1116)');
    }
    final rng = random ?? Random.secure();
    String candidate;
    do {
      candidate = [
        for (var i = 0; i < joinCodeLength; i++)
          joinCodeAlphabet[rng.nextInt(joinCodeAlphabet.length)],
      ].join();
    } while (records.any((r) => r.code == candidate));
    final record = JoinCodeRecord(
      code: candidate,
      issuedAtUtc: nowUtc,
      expiresAtUtc: nowUtc.add(joinCodeValidity),
      issuedByDeviceId: device,
    );
    records.add(record);
    return record;
  }

  /// الاستهلاك نص م-32 حرفاً — **استهلاك واحد** بكل رفضه المفهرس:
  /// مجهول أو فاسد الشكل أو منتهي أو مستهلك من قبل — والاستهلاك
  /// الصحيح يسجل مَن استهلك ومتى فلا رمز يُستهلك مرتين أبداً.
  /// الحكم حتى نهاية الساعة الرابعة والعشرين حرفاً: لحظة الانتهاء
  /// ذاتها تجوز، وما بعدها رفض.
  JoinCodeRecord consume({
    required String code,
    required String consumingDeviceId,
    required DateTime nowUtc,
  }) {
    final device = consumingDeviceId.trim();
    if (device.isEmpty) {
      throw const JoinCodeException('استهلاك رمز الانضمام يتطلب معرف '
          'الجهاز المستهلك (DQ-1116)');
    }
    final normalized = normalizeJoinCode(code);
    if (!isValidJoinCodeShape(normalized)) {
      throw JoinCodeException('رمز الانضمام غير سليم الشكل — ثمانية '
          'محارف من الأبجدية الآمنة: "${formatJoinCodeSafe(normalized)}" '
          '(DQ-1116)');
    }
    final idx = records.indexWhere((r) => r.code == normalized);
    if (idx < 0) {
      throw JoinCodeException('رمز الانضمام مجهول: '
          '"${formatJoinCodeSafe(normalized)}" (DQ-1116)');
    }
    final record = records[idx];
    if (record.isConsumed) {
      throw JoinCodeException('رمز الانضمام مستهلك من قبل — استهلاك '
          'واحد نص م-32 (DQ-1116)');
    }
    if (nowUtc.isAfter(record.expiresAtUtc)) {
      throw JoinCodeException('رمز الانضمام انتهت صلاحيته (24 ساعة '
          'نص م-32) — اطلب رمزاً جديداً (DQ-1116)');
    }
    final consumed = record.consumed(atUtc: nowUtc, byDeviceId: device);
    records[idx] = consumed;
    return consumed;
  }

  String toJson() => jsonEncode(<String, Object?>{
        'version': 1,
        'records': [for (final r in records) r.toJson()],
      });

  /// الكتاب من JSON — **يفشل مقفلاً**: أي صف فاسد استثناء صوت لا
  /// إسقاط صامت (سجل الانضمام حماية ففساده لا يُخمَّد).
  static JoinCodeBook fromJson(String text) {
    Object? root;
    try {
      root = jsonDecode(text);
    } catch (e) {
      throw JoinCodeException('كتاب رموز الانضمام فاسد البنية — لا '
          'تشغيل بلا سجل سليم (DQ-1116)');
    }
    if (root is! Map<String, Object?>) {
      throw const JoinCodeException('كتاب رموز الانضمام فاسد البنية '
          '— لا تشغيل بلا سجل سليم (DQ-1116)');
    }
    final raw = root['records'];
    if (raw is! List) {
      throw const JoinCodeException('كتاب رموز الانضمام بلا سجلاته '
          '— لا تشغيل بلا سجل سليم (DQ-1116)');
    }
    final records = <JoinCodeRecord>[];
    for (final r in raw) {
      if (r is! Map<String, Object?>) {
        throw const JoinCodeException('صف رمز انضمام فاسد بالكتاب — '
            'لا تشغيل بلا سجل سليم (DQ-1116)');
      }
      final record = JoinCodeRecord.fromJson(r);
      if (record == null) {
        throw const JoinCodeException('صف رمز انضمام فاسد بالكتاب — '
            'لا تشغيل بلا سجل سليم (DQ-1116)');
      }
      records.add(record);
    }
    return JoinCodeBook(records: records);
  }
}

/// صياغة آمنة للعرض برسائل الرفض — الرمز الفاسد الشكل لا يرمي وهو
/// يُرسَّب رسالة.
String formatJoinCodeSafe(String normalized) =>
    isValidJoinCodeShape(normalized) && normalized.length == joinCodeLength
        ? formatJoinCode(normalized)
        : normalized;

/// حالة الجهاز في سجل العضوية.
enum SyncDeviceStatus { active, revoked }

extension SyncDeviceStatusWire on SyncDeviceStatus {
  String get wire => this == SyncDeviceStatus.active ? 'active' : 'revoked';
  static SyncDeviceStatus fromWire(String s) => s == 'revoked'
      ? SyncDeviceStatus.revoked
      : SyncDeviceStatus.active;
}

/// حكم أول اتصال بجهاز — فرض العضوية بوجهتَيها (المحلي والخادم
/// بعقد F-136).
enum FirstContactVerdict {
  allow, // جهاز نشط مسجل — المزامنة تجري
  refuse, // مجهول أو مُبطَل بلا علم مسح — رفض صرف
  refuseAndWipe, // مُبطَل وختير «مسح عند أول اتصال» نص م-33
}

extension FirstContactVerdictLabel on FirstContactVerdict {
  String get label => switch (this) {
        FirstContactVerdict.allow => 'مسموح',
        FirstContactVerdict.refuse => 'مرفوض',
        FirstContactVerdict.refuseAndWipe => 'مرفوض ومسح عند أول اتصال',
      };
}

/// صف جهاز في سجل العضوية — تاريخه محفوظ بلا حذف نص م-33 حرفاً.
class SyncDeviceRecord {
  final String deviceId;
  final SyncDeviceStatus status;

  /// لحظة الانضمام (أول تسجيل) — باقية بعد الإبطال عقد م-33.
  final DateTime? joinedAtUtc;

  /// لحظة الإبطال الأولى — رتابة: لا تتراجع بإعادة إبطال.
  final DateTime? revokedAtUtc;
  final bool wipeOnFirstContact;

  /// بادئة الترقيم (د3 «جN») إن حُجزت — عرضاً بالسجل لا حاكماً هنا.
  final String? prefix;

  /// سبب الإبطال إن وُجد — نص المالك موثق بالسجل.
  final String? revokeReason;

  const SyncDeviceRecord({
    required this.deviceId,
    required this.status,
    this.joinedAtUtc,
    this.revokedAtUtc,
    this.wipeOnFirstContact = false,
    this.prefix,
    this.revokeReason,
  });

  SyncDeviceRecord copyWith({
    SyncDeviceStatus? status,
    DateTime? joinedAtUtc,
    DateTime? revokedAtUtc,
    bool? wipeOnFirstContact,
    String? prefix,
    String? revokeReason,
  }) =>
      SyncDeviceRecord(
        deviceId: deviceId,
        status: status ?? this.status,
        joinedAtUtc: joinedAtUtc ?? this.joinedAtUtc,
        revokedAtUtc: revokedAtUtc ?? this.revokedAtUtc,
        wipeOnFirstContact: wipeOnFirstContact ?? this.wipeOnFirstContact,
        prefix: prefix ?? this.prefix,
        revokeReason: revokeReason ?? this.revokeReason,
      );

  /// JSON بمفاتيح مرتبة ثابتة.
  Map<String, Object?> toJson() => {
        'device': deviceId,
        'status': status.wire,
        if (joinedAtUtc != null)
          'joinedAt': joinedAtUtc!.toIso8601String(),
        if (revokedAtUtc != null)
          'revokedAt': revokedAtUtc!.toIso8601String(),
        'wipe': wipeOnFirstContact,
        if (prefix != null) 'prefix': prefix,
        if (revokeReason != null) 'reason': revokeReason,
      };

  /// الصف من JSON — null عند فساد جوهري أو مفتاح غائب (التقاطع
  /// الحرفي لا الاستيفاء الصامت لقيمة null نصاً).
  static SyncDeviceRecord? fromJson(Map<String, Object?> json) {
    final deviceRaw = json['device'];
    if (deviceRaw is! String || deviceRaw.trim().isEmpty) return null;
    final device = deviceRaw.trim();
    final status = SyncDeviceStatusWire.fromWire('${json['status']}');
    final joined = json['joinedAt'] == null
        ? null
        : DateTime.tryParse('${json['joinedAt']}');
    final revoked = json['revokedAt'] == null
        ? null
        : DateTime.tryParse('${json['revokedAt']}');
    if ((joined != null && !joined.isUtc) ||
        (revoked != null && !revoked.isUtc)) {
      return null;
    }
    final prefixRaw = json['prefix'];
    final reasonRaw = json['reason'];
    return SyncDeviceRecord(
      deviceId: device,
      status: status,
      joinedAtUtc: joined,
      revokedAtUtc: revoked,
      wipeOnFirstContact: json['wipe'] == true,
      prefix: prefixRaw is String && prefixRaw.isNotEmpty
          ? prefixRaw
          : null,
      revokeReason: reasonRaw is String && reasonRaw.isNotEmpty
          ? reasonRaw
          : null,
    );
  }
}

/// يُرمى حين جهاز مُبطَل يحاول العودة من باب التسجيل — DQ-1117
/// (الإبطال لا يُلغى بالتسجيل المكرر: إعادة الثقة قرار مدير صريح).
class SyncDeviceRevokedException implements Exception {
  final String message;
  const SyncDeviceRevokedException(this.message);
  @override
  String toString() => message;
}

/// سجل عضوية الأجهزة — الحكم المحلي الموازي للخادم نص F-136.
///
/// **العقد الصلب نص م-33**: الإبطال فوري وحالةً فقط — ولا حذفَ ولا
/// تقليمَ لأي صف: الوحدة بلا API حذف أصلاً، وصفُّ الجهاز يبقى
/// بتاريخه (لحظة الانضمام والإبطال وسببه) بعد الإبطال كما كان.
class SyncDeviceRegistry {
  final List<SyncDeviceRecord> devices;

  SyncDeviceRegistry({List<SyncDeviceRecord>? devices})
      : devices = List.of(devices ?? const <SyncDeviceRecord>[]);

  SyncDeviceRecord? byId(String deviceId) {
    final id = deviceId.trim();
    for (final d in devices) {
      if (d.deviceId == id) return d;
    }
    return null;
  }

  /// تسجيل جهاز (عقب استهلاك رمز انضمام سليم):
  /// - المجهول: ينضم نشطاً بلحظة انضمامه.
  /// - النشط القائم: عودةٌ مطابقة (المكرر بهدوء عرف س-23) بلا صفين.
  /// - **المُبطَل: رفض صوتي DQ-1117** — التسجيل المكرر لا يلغي
  ///   الإبطال أبداً؛ إعادة الثقة قرار مدير صريح بretrust.
  SyncDeviceRecord register({
    required String deviceId,
    required DateTime atUtc,
    String? prefix,
  }) {
    final id = deviceId.trim();
    if (id.isEmpty) {
      throw const FormatException('تسجيل جهاز يتطلب معرفاً غير فارغ');
    }
    final existing = byId(id);
    if (existing == null) {
      final record = SyncDeviceRecord(
        deviceId: id,
        status: SyncDeviceStatus.active,
        joinedAtUtc: atUtc,
        prefix: prefix,
      );
      devices.add(record);
      return record;
    }
    if (existing.status == SyncDeviceStatus.revoked) {
      throw SyncDeviceRevokedException('جهاز مُبطَل لا يعود بالتسجيل '
          'المكرر — إعادة الثقة قرار مدير صريح (DQ-1117)');
    }
    return existing;
  }

  /// الإبطال الفوري نص م-33 حرفاً — قلب حالة لا حذف: الصف يبقى
  /// بتاريخ انضمامه ولاحظة السبب، ولحظة الإبطال الأولى رابتة لا
  /// تتراجع بإعادة إبطال.
  SyncDeviceRecord revoke({
    required String deviceId,
    required DateTime atUtc,
    String? reason,
  }) {
    final existing = byId(deviceId);
    if (existing == null) {
      throw FormatException('إبطال جهاز غير مسجل: "$deviceId"');
    }
    if (existing.status == SyncDeviceStatus.revoked) {
      // الرتابة: أول لحظة إبطال هي المخزونة — والسبب الجديد يُحفظ
      // إن جاء.
      final idx = devices.indexOf(existing);
      final kept = reason == null
          ? existing
          : existing.copyWith(revokeReason: reason);
      devices[idx] = kept;
      return kept;
    }
    final revoked = existing.copyWith(
      status: SyncDeviceStatus.revoked,
      revokedAtUtc: atUtc,
      revokeReason: reason,
    );
    devices[devices.indexOf(existing)] = revoked;
    return revoked;
  }

  /// خيار «مسح عند أول اتصال» نص م-33 — على المُبطَل حصراً: على
  /// جهاز نشط لا معنى له فيُرفض صوتاً فلا يُخمَد خطأ إبطال.
  SyncDeviceRecord markWipeOnFirstContact(String deviceId) {
    final existing = byId(deviceId);
    if (existing == null) {
      throw FormatException('جهاز غير مسجل: "$deviceId"');
    }
    if (existing.status != SyncDeviceStatus.revoked) {
      throw const FormatException('خيار «مسح عند أول اتصال» على '
          'المُبطَل حصراً — أبطِل الجهاز أولاً نص م-33');
    }
    final idx = devices.indexOf(existing);
    final flagged = existing.copyWith(wipeOnFirstContact: true);
    devices[idx] = flagged;
    return flagged;
  }

  /// إعادة الثقة الصريحة (قرار مدير موثق كحدث عند المنفذ): المُبطَل
  /// يعود نشطاً وعلمُ المسح القديم ينطفئ معها فلا أمر قديم يبقى
  /// ناصباً على جهاز وُثِق من جديد.
  SyncDeviceRecord retrust({
    required String deviceId,
    required DateTime atUtc,
  }) {
    final existing = byId(deviceId);
    if (existing == null) {
      throw FormatException('إعادة ثقة لجهاز غير مسجل: "$deviceId"');
    }
    if (existing.status == SyncDeviceStatus.active) {
      return existing;
    }
    final idx = devices.indexOf(existing);
    final trusted = SyncDeviceRecord(
      deviceId: existing.deviceId,
      status: SyncDeviceStatus.active,
      joinedAtUtc: existing.joinedAtUtc,
      prefix: existing.prefix,
    );
    devices[idx] = trusted;
    return trusted;
  }

  /// حكم أول اتصال — القراءة الواحدة التي يفرض بها المحلي والخادم
  /// معاً بعقد F-136: المجهول رفض (الانضمام برمز انضمام لا باتصال)،
  /// والنشط مسموح، والمُبطَل رفض — وعلمُ المسح يرفع الرفض إلى
  /// «مرفوض ومسح» نص م-33.
  FirstContactVerdict firstContactVerdict(String deviceId) {
    final d = byId(deviceId);
    if (d == null) return FirstContactVerdict.refuse;
    if (d.status == SyncDeviceStatus.active) {
      return FirstContactVerdict.allow;
    }
    return d.wipeOnFirstContact
        ? FirstContactVerdict.refuseAndWipe
        : FirstContactVerdict.refuse;
  }

  String toJson() => jsonEncode(<String, Object?>{
        'version': 1,
        'devices': [for (final d in devices) d.toJson()],
      });

  /// السجل من JSON — **يفشل مقفلاً** بنمط كتاب الرموز: فساد سجل
  /// الإبطال استثناء صوت لا سجل فارغ متسامح.
  static SyncDeviceRegistry fromJson(String text) {
    Object? root;
    try {
      root = jsonDecode(text);
    } catch (_) {
      throw const SyncDeviceRevokedException('سجل الأجهزة فاسد البنية '
          '— لا تشغيل بلا سجل إبطال سليم (DQ-1117)');
    }
    if (root is! Map<String, Object?>) {
      throw const SyncDeviceRevokedException('سجل الأجهزة فاسد البنية '
          '— لا تشغيل بلا سجل إبطال سليم (DQ-1117)');
    }
    final raw = root['devices'];
    if (raw is! List) {
      throw const SyncDeviceRevokedException('سجل الأجهزة بلا صفوفه '
          '— لا تشغيل بلا سجل إبطال سليم (DQ-1117)');
    }
    final devices = <SyncDeviceRecord>[];
    for (final r in raw) {
      if (r is! Map<String, Object?>) {
        throw const SyncDeviceRevokedException('صف جهاز فاسد بالسجل — '
            'لا تشغيل بلا سجل إبطال سليم (DQ-1117)');
      }
      final record = SyncDeviceRecord.fromJson(r);
      if (record == null) {
        throw const SyncDeviceRevokedException('صف جهاز فاسد بالسجل — '
            'لا تشغيل بلا سجل إبطال سليم (DQ-1117)');
      }
      devices.add(record);
    }
    return SyncDeviceRegistry(devices: devices);
  }
}
