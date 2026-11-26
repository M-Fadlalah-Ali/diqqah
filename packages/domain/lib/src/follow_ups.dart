/// المتابعات (د-7 — §25.9، س141) — التسمية المعتمدة بقرار المالك.
///
/// الباني نقي حصراً بلا Flutter ولا Drift (F-010): **تجميع عرض فوق
/// المصادر لا كائن بيانات جديد، وكل متابعة صالحة منفردة** (روح
/// س74/D-180)، ولوحة التذكيرات الذكية (b39) هي النمط المعماري المرجعي
/// — باني نقي + لوحة + أفعال محقونة. بنود v1 السبعة بنص §25.9 حرفاً
/// («كميات أُعيد ضبطها» سقطت بمقتضى د-2):
/// 1. قيود افتتاحية تحتاج إعادة تصنيف (332 لم يُوزَّع).
/// 2. أطراف/أصناف/وحدات أُنشئت تلقائياً — للمراجعة.
/// 3. أطراف/أصناف موجودة تم تخطيها — الفروق معروضة وقرار تحديث
///    الوصفيّات.
/// 4. نسخ طوارئ متراكمة وإدارة التخزين.
/// 5. نافذة تراجع استعادة مفتوحة.
/// 6. تاريخ بداية السنة المالية — للإقرار أو التعديل قبل الترحيل.
/// 7. إشعارات عتبات التخزين (د-8: عتبتا 80%/95% بلوحة القائمة).
///
/// «المتابعات اليومية» (س74/D-184 بلفظ المالك: «الأصناف التي انخفضت
/// عن الحد الأدنى المحدد، أو الأرصدة التي تجاوزت سقفها الأعلى من حيث
/// المبلغ أو الزمن») مُستوعَبة هنا بدفعة د6 (س175 — الاستيعاب
/// الواجهي والأحمال الختامية بنص خارطة م4 §46): مصادرها القائمة
/// (حد الائتمان F-023 وسقف السقف الفراغي س-34 ومدة السداد الجديدة
/// على الطرف والحد الأدنى الجديد على الصنف) والبني تجمعها كعرضٍ
/// فوق المصادر لا كائن بيانات جديد — واللوحة ذاتها التي تحملها هي
/// لوحة «يحتاج انتباهك» (F-146 إحالة م4–م5) بلسان شاشة المتابعات
/// والرئيسية القائمَين.
library;

import 'import_core.dart' show formatMinorHuman;

/// شدة المتابعة — العرف اللوني الثلاث بق-ن8 (أحمر عاجل، برتقالي انتباه،
/// هادئ معلومة).
enum FollowUpSeverity {
  urgent('عاجل'),
  attention('انتباه'),
  info('معلومة');

  final String label;
  const FollowUpSeverity(this.label);
}

/// متابعة واحدة — محمولة بيانات لا نص جاهز؟ لا: هذه لوحة عرض صادقة
/// فوق مصادر قائمة، فالعنوان والوصف باللسان العربي الكامل من هنا
/// (نمط buildBackupReminders بb39 — المرجع المعماري الموثق §25.9)
/// والأفعال تُحقن بالواجهة.
class FollowUpEntry {
  final String id;
  final FollowUpSeverity severity;
  final String title;
  final String description;

  /// لسان زر الفعل المقترح — الفعل نفسه محقون بالواجهة.
  final String actionLabel;

  const FollowUpEntry({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    required this.actionLabel,
  });
}

/// مدخلات الباني — كل مصدر مستقل الحضور (null/صفر = المصدر صامت) فتبقى
/// كل متابعة صالحة منفردة. عدادات الاستيراد تُجمَّع من أحداث
/// `import_performed` بعد آخر تأكيد مراجعة (علامة app_meta).
class FollowUpsInput {
  /// رصيد 332 غير الموزَّع بوحدة الأساسية الصغرى — null إن لا قيد
  /// افتتاحي أصلاً (الحساب بلا حركة).
  final int? openingUndistributedBaseMinor;

  /// أحداث استيراد بعد آخر تأكيد مراجعة — صفر إن لا جديد بانتظارها.
  final int importEventsAwaitingReview;
  final int partiesAutoCreated;
  final int itemsAutoCreated;
  final int unitsAutoCreated;
  final int partiesSkipped;
  final int itemsSkipped;

  /// نسخ الطوارئ المتراكمة — الحدثية ولقطات ما قبل الاستعادة.
  final int emergencyCopiesCount;

  /// نافذة التراجع عن الاستعادة مفتوحة (§25.7 — د-3).
  final bool rollbackWindowOpen;

  /// بداية أقدم فترة مفتوحة — لإقرار تاريخ بداية السنة المالية.
  final String? fiscalYearStartText;

  /// آخر إقرار موثق لبداية السنة المالية (app_meta).
  final String? fiscalStartAcknowledgedText;

  /// هل توجد قيود مرحّلة أصلاً؟ بعدها يفوت إقرار الافتتاحي (لا معنى
  /// له بعد بدء الدفاتر).
  final bool hasPostedMoves;

  /// نسبة استهلاك حصة النسخ (0..1) — عتبتا 80% و95% (د-8).
  final double quotaUsedFraction;

  /// المتابعات اليومية — د6 (س175): أصناف تحت الحد الأدنى المحدد
  /// (س74/D-184). القائمة الفارغة مصدر صامت.
  final List<BelowMinimumItem> belowMinimumItems;

  /// المتابعات اليومية — أرصدة تجاوزت سقف الائتمان مبلغاً (س74/D-184).
  final List<OverAmountCapBalance> overAmountCapBalances;

  /// المتابعات اليومية — أرصدة تجاوزت مدة السداد زمناً (س74/D-184).
  final List<OverTimeCapBalance> overTimeCapBalances;

  const FollowUpsInput({
    this.openingUndistributedBaseMinor,
    this.importEventsAwaitingReview = 0,
    this.partiesAutoCreated = 0,
    this.itemsAutoCreated = 0,
    this.unitsAutoCreated = 0,
    this.partiesSkipped = 0,
    this.itemsSkipped = 0,
    this.emergencyCopiesCount = 0,
    this.rollbackWindowOpen = false,
    this.fiscalYearStartText,
    this.fiscalStartAcknowledgedText,
    this.hasPostedMoves = false,
    this.quotaUsedFraction = 0,
    this.belowMinimumItems = const [],
    this.overAmountCapBalances = const [],
    this.overTimeCapBalances = const [],
  });
}

/// عتبة «متراكمة» لنسخ الطوارئ (بند 4): ثلاث فأكثر — دونها دورها
/// الطبيعي قائم لا يستدعي متابعة.
const int kEmergencyCopiesAttentionThreshold = 3;

/// عتبتا التخزين الموثقتان (د-8 — ق-ن3 القائمة بلا أرقام جديدة).
const double kStorageWarningFraction = 0.80;
const double kStorageCriticalFraction = 0.95;

/// صنف انخفض عن حد الأدنى المحدد — مصدر المتابعات اليومية
/// (س74/D-184): الكمية المتاحة عبر المستودعات كلها مقابل الحد
/// الأدنى المحفوظ على الصنف، والصنف الجيد حصراً (الخدمات بلا
/// مخزون أصلاً).
class BelowMinimumItem {
  final String sku;
  final String name;

  /// المتاح المجمّع عبر المستودعات بوحدة الأساسية.
  final int availableQty;

  /// الحد الأدنى المحدد على الصنف — الأدنى موجب (الصفر بلا معنى
  /// للمتابعة فلا يُرسل من الاستعلام).
  final int minimumQty;

  const BelowMinimumItem({
    required this.sku,
    required this.name,
    required this.availableQty,
    required this.minimumQty,
  });
}

/// رصيد طرف تجاوز سقفه الأعلى مبلغاً — حد الائتمان المعرف (F-023)
/// بلسان F-164 ذاته: الوصولُ بالتمام إلى السقف ليس تجاوزاً —
/// التجاوز أشدُّ من السقف، والسقف الفراغي «بلا سقف» لا ينذر أبداً
/// (س-34) فالاستعلام لا يرسله أصلاً.
class OverAmountCapBalance {
  final String partyName;

  /// صافي الذمة الحالي بوحدة الصغرى الأساسية (موجب: يدين لنا).
  final int balanceMinor;

  /// سقف الائتمان المعرف على الطرف.
  final int capMinor;

  const OverAmountCapBalance({
    required this.partyName,
    required this.balanceMinor,
    required this.capMinor,
  });
}

/// رصيد طرف تجاوز سقفه الأعلى زمناً — مدة السداد المحددة على الطرف
/// (س74/D-184 «أو الزمن»): أقدم فاتورة بيع مفتوحة (مرحّلة أو جزئية
/// بباقٍ موجب) عمرها — من تاريخ استحقاقها وإلا تاريخها، بعرف الأعمار
/// س-151/D-149 — تجاوز مدة السداد، والرصيد الصافي الطرفي دينٌ قائم
/// (السالب صامت: سدادٌ زائد لا متابعة).
class OverTimeCapBalance {
  final String partyName;

  /// عمر أقدم فاتورة بيع مفتوحة بالأيام الكاملة من مرساة العمر
  /// (الاستحقاق وإلا التاريخ).
  final int oldestAgeDays;

  /// مدة السداد المحددة على الطرف بالأيام.
  final int termDays;

  const OverTimeCapBalance({
    required this.partyName,
    required this.oldestAgeDays,
    required this.termDays,
  });
}

/// بناء المتابعات — كل بند بشرطه المستقل، والفارغ الكامل قائمة فارغة
/// (الشاشة تعرض «لا متابعات الآن»).
List<FollowUpEntry> buildFollowUps(FollowUpsInput input) {
  final entries = <FollowUpEntry>[];

  // 1. قيود افتتاحية تحتاج إعادة تصنيف — 332 لم يُوزَّع (د-1: جاري
  //    النتيجة حساب عبور لا مستقر — وجود رصيد له بعد الافتتاحي معناه
  //    التوزيع لم يتم).
  final undistributed = input.openingUndistributedBaseMinor;
  if (undistributed != null && undistributed != 0) {
    entries.add(FollowUpEntry(
      id: 'opening_reclassify',
      severity: FollowUpSeverity.attention,
      title: 'قيود افتتاحية تحتاج إعادة تصنيف',
      description: 'حساب «جاري النتيجة (الافتتاح والإقفال)» 332 يحمل '
          'رصيداً غير موزَّع قدره ${formatMinorHuman(undistributed, 2)} '
          'ليرة — وزّعه على حساباته الحقيقية بقيد عام.',
      actionLabel: 'قيد عام من الدفتر',
    ));
  }

  // 2. أُنشئ تلقائياً — للمراجعة (الأحداث بعد آخر تأكيد).
  if (input.importEventsAwaitingReview > 0 &&
      (input.partiesAutoCreated +
              input.itemsAutoCreated +
              input.unitsAutoCreated >
          0)) {
    final createdParts = <String>[
      if (input.partiesAutoCreated > 0)
        '${input.partiesAutoCreated} طرفاً',
      if (input.itemsAutoCreated > 0) '${input.itemsAutoCreated} صنفاً',
      if (input.unitsAutoCreated > 0)
        '${input.unitsAutoCreated} وحدة قياس',
    ];
    entries.add(FollowUpEntry(
      id: 'import_auto_created',
      severity: FollowUpSeverity.attention,
      title: 'أُنشئ تلقائياً بالاستيراد — للمراجعة',
      description: 'أنشأ الاستيراد (${input.importEventsAwaitingReview} '
          'حدثاً بعد آخر مراجعة): ${createdParts.join(' و')}. راجعها ثم '
          'أكّد المراجعة.',
      actionLabel: 'راجع ثم أكّد',
    ));
  }

  // 3. موجود تخطي — الفروق معروضة وقرار التحديث وصفيّات بيدك (د-2).
  final skippedTotal = input.partiesSkipped + input.itemsSkipped;
  if (input.importEventsAwaitingReview > 0 && skippedTotal > 0) {
    entries.add(FollowUpEntry(
      id: 'import_skipped_existing',
      severity: FollowUpSeverity.info,
      title: 'موجود تُخُطّي بالاستيراد — قرار الوصفيّات بيدك',
      description: 'تخطى الاستيراد $skippedTotal موجوداً (فروق معروضة '
          'بتقرير الاستيراد القابل للتنزيل) — تحديث الاسم والسعران '
          'بالسياسة أو يدوياً.',
      actionLabel: 'راجع ثم أكّد',
    ));
  }

  // 4. نسخ طوارئ متراكمة وإدارة التخزين (د-4/د-8).
  if (input.emergencyCopiesCount >= kEmergencyCopiesAttentionThreshold) {
    entries.add(FollowUpEntry(
      id: 'emergency_copies',
      severity: FollowUpSeverity.attention,
      title: 'نسخ طوارئ متراكمة وإدارة التخزين',
      description: '${input.emergencyCopiesCount} نسخة حدثية/طوارئ '
          'متراكمة — راجع إدارة النسخ: تصدير ما يلزم والتنظيف الذكي '
          'يحترم الأرضية النظامية.',
      actionLabel: 'إدارة النسخ',
    ));
  }

  // 5. نافذة تراجع استعادة مفتوحة (§25.7 — د-3: صالحة حتى أول كتابة).
  if (input.rollbackWindowOpen) {
    entries.add(FollowUpEntry(
      id: 'rollback_window_open',
      severity: FollowUpSeverity.urgent,
      title: 'نافذة التراجع عن الاستعادة مفتوحة',
      description: 'التراجع عن آخر استعادة متاح حتى أول عملية كتابة — '
          'قرارك الآن: تراجع أو أقدم على العمل.',
      actionLabel: 'تراجع أو أقدم',
    ));
  }

  // 6. تاريخ بداية السنة المالية — للإقرار أو التعديل قبل الترحيل
  //    (§25.4: قبل الترحيل لا بعده — وبعد أول ترحيل يفوت معناه).
  final fiscalStart = input.fiscalYearStartText;
  if (fiscalStart != null &&
      !input.hasPostedMoves &&
      input.fiscalStartAcknowledgedText != fiscalStart) {
    entries.add(FollowUpEntry(
      id: 'fiscal_year_start',
      severity: FollowUpSeverity.attention,
      title: 'تاريخ بداية السنة المالية — للإقرار أو التعديل',
      description: 'بداية أقدم فترة مفتوحة $fiscalStart — أقرّها أو عدّلها '
          'من شاشة الفترات قبل ترحيل الأرصدة الافتتاحية.',
      actionLabel: 'أقرّ التاريخ',
    ));
  }

  // 7. إشعارات عتبات التخزين (د-8: العتبتان القائمتان لا رقم جديد).
  if (input.quotaUsedFraction >= kStorageCriticalFraction) {
    entries.add(FollowUpEntry(
      id: 'storage_threshold',
      severity: FollowUpSeverity.urgent,
      title: 'التخزين بلغ العتبة الحرجة',
      description: 'نسخك تستهلك ${(input.quotaUsedFraction * 100).round()}% '
          'من الحصة (العتبة الحرجة 95%) — نظّف بالتنظيف الذكي أو ارفع '
          'الحصة من الإعدادات.',
      actionLabel: 'إدارة التخزين',
    ));
  } else if (input.quotaUsedFraction >= kStorageWarningFraction) {
    entries.add(FollowUpEntry(
      id: 'storage_threshold',
      severity: FollowUpSeverity.attention,
      title: 'التخزين تجاوز عتبة التحذير',
      description: 'نسخك تستهلك ${(input.quotaUsedFraction * 100).round()}% '
          'من الحصة (عتبة التحذير 80%) — راجع إدارة النسخ قبل الضيق.',
      actionLabel: 'إدارة التخزين',
    ));
  }

  // 8. المتابعات اليومية — أصناف انخفضت عن الحد الأدنى المحدد
  //    (س74/D-184 بلفظ المالك حرفاً): بند واحد مجمّع بلسان الحقيقة —
  //    أول ثلاثة أسماء بالمتاح والحد ثم «وغيرها» فلا تغرق اللوحة.
  final belowMin = input.belowMinimumItems;
  if (belowMin.isNotEmpty) {
    final named = belowMin
        .take(3)
        .map((i) =>
            '«${i.name}»: المتاح ${i.availableQty} والحد الأدنى '
            '${i.minimumQty}')
        .join('؛ ');
    final extra = belowMin.length > 3
        ? '؛ وغيرها ${belowMin.length - 3} صنفاً'
        : '';
    entries.add(FollowUpEntry(
      id: 'daily_below_minimum',
      severity: FollowUpSeverity.attention,
      title: 'أصناف انخفضت عن الحد الأدنى المحدد (${belowMin.length})',
      description: 'المتابعة اليومية بالأصناف تحت حدّها الأدنى المحدد '
          'عليها — $named$extra. راجعها وورّد ما يلزم أو عدّل الحد.',
      actionLabel: 'أصناف المخزون',
    ));
  }

  // 9. المتابعات اليومية — أرصدة تجاوزت سقفها الأعلى مبلغاً (حد
  //    الائتمان F-023 — لسان F-164: التجاوز أشدُّ من السقف).
  final overAmount = input.overAmountCapBalances;
  if (overAmount.isNotEmpty) {
    final named = overAmount
        .take(3)
        .map((b) =>
            '«${b.partyName}»: الرصيد '
            '${formatMinorHuman(b.balanceMinor, 2)} والسقف '
            '${formatMinorHuman(b.capMinor, 2)}')
        .join('؛ ');
    final extra = overAmount.length > 3
        ? '؛ وغيرها ${overAmount.length - 3} طرفاً'
        : '';
    entries.add(FollowUpEntry(
      id: 'daily_over_credit_cap',
      severity: FollowUpSeverity.urgent,
      title: 'أرصدة تجاوزت سقفها الأعلى مبلغاً (${overAmount.length})',
      description: 'المتابعة اليومية بالأرصدة فوق سقف الائتمان المعرف '
          'عليها — $named$extra. راجع كشوفها وقرر التحصيل أو رفع السقف.',
      actionLabel: 'كشوف الأطراف',
    ));
  }

  // 10. المتابعات اليومية — أرصدة تجاوزت سقفها الأعلى زمناً (مدة
  //     السداد المحددة على الطرف — س74/D-184 «أو الزمن»).
  final overTime = input.overTimeCapBalances;
  if (overTime.isNotEmpty) {
    final named = overTime
        .take(3)
        .map((b) =>
            '«${b.partyName}»: أقدم فاتورة مفتوحة عمرها ${b.oldestAgeDays} '
            'يوماً ومدة السداد ${b.termDays} يوماً')
        .join('؛ ');
    final extra = overTime.length > 3
        ? '؛ وغيرها ${overTime.length - 3} طرفاً'
        : '';
    entries.add(FollowUpEntry(
      id: 'daily_over_term',
      severity: FollowUpSeverity.attention,
      title: 'ذمم تجاوزت مدة السداد المحددة (${overTime.length})',
      description: 'المتابعة اليومية بالأرصدة فوق سقفها الزمني — '
          '$named$extra. راجع أعمار الذمم وقرر التحصيل.',
      actionLabel: 'أعمار الذمم',
    ));
  }

  return entries;
}
