/// د2 (س173 — المهايئ الثالث: الملف المشفر اليدوي F-133 — بكلمة المالك
/// الحرفية «تابع ب: د2» بنص خارطة م4 §46): الجسر اليدوي س-23 والمزوّد
/// الثالث **بتنفيذ واحد يخدم الاثنين** (08 §5/§10) — فوق حزمة د1 حرفاً:
/// كل ملف يخرج أو يدخل هنا حزمة `.dsync` كاملة موقعة بصيغة §10 ذاتها
/// فلا صيغة جديدة ولا غلاف ثانٍ، والجسر يضيف التزاماته الثلاثة:
///
/// 1. **تقسيم الإرسال تلقائياً عند تجاوز 50MB** بأجزاء «part i/N»
///    مرقمة تحترم تسلسل الأحداث (08 §10): كل جزء حزمة سليمة مستقلة
///    مبنية بمحرك د1 (توقيع وتغليف وفحص بنيوي خاص بها) وتتلو سابقتها
///    بلا فجوة، واسمها الأساس القياسي بعلامة الجزء قبل الامتداد.
/// 2. **الاستيراد «كاملاً بالترتيب» نص §10**: مجموعة الأجزاء تُفتح
///    كلها ويفحص كل جزء نص §10 كاملاً بمحرك د1 (الغلاف DQ-1109 والعبث
///    DQ-1110 والبنية DQ-1111 والشركة DQ-1112) ثم تتجاور بترتيبها —
///    نهاية كل جزء بداية تالِه − 1 — قبل أي إلحاق، والناقص أو المتضارب
///    أو الخليط مرفوض صوتاً مفهرساً **DQ-1115**.
/// 3. **المكرر بهدوء عرف س-23**: المتلقي يمرر مخرج الاستيراد على
///    [filterKnownSyncEvents] (د1) فالفريد يُلحق والمعروف يُعدّ بهدوء
///    — append-only بلا كتابة فوق تاريخ (§10 القاعدة الحاكمة).
///
/// **نقية حصراً** (F-010): لا Flutter ولا Drift ولا شبكة ولا ملفات
/// جهاز — الدوال تأخذ بايتات وأسماً وترد بايتات، والمستهلك (شاشة
/// المزامنة ثم الاستيعاب الواجهي د6) يوصلها بمسار الملفات على عهده.
///
/// **حد صادق**: ما هنا عقد الجسر النقي ومحركه المجرَّب بالاختبارات —
/// والتجربة الحية للجسر على جهازين حقيقيين بتصديق مكتوب موضعها
/// البوابات الجهازية (D-211) لا زعمٌ آلي هنا.
library;

import 'dart:convert';
import 'dart:math';

import 'sync_bundle.dart';
import 'sync_devices.dart';

/// حد التقسيم التلقائي نص §10 — 50 ميجابايت بايتاً بايتاً.
const int syncFilePartLimitBytes = 50 * 1024 * 1024;

/// فوق الحد هذا لا يُقبل حدُ تقسيم أصغر — هامش الترويسة المتغير
/// (معرف الجهاز والشركة نصوص حرة) وعتبة الفحص محسوبة معاً.
const int _partHeaderMarginBytes = 2048;

/// فوق الحد هذا لا يُقبل حدُ تقسيم أصغر (أدنى مشروع للفحص والاختبار):
/// الغلاف 53 بايتاً + هامش الترويسة + سطر حدث واحد على الأقل.
const int _minPartLimitBytes = 2560;

/// فوق الحد هذا ثابت الغلاف: ترويسة DIQQSYNC ثمانية + إصدار بايتة +
/// ملح الاشتقاق 16 + نونس GCM 12 + وسم السلامة 16.
const int _envelopeOverheadBytes = 8 + 1 + 16 + 12 + 16;

/// علامة الأجزاء بالاسم نص §10 — «part i/N» قبل امتداد الحزمة:
/// `diqqah-sync-….part1of3.dsync`.
final RegExp _partNamePattern =
    RegExp(r'^(.*)\.part(\d+)of(\d+)\.dsync$');

/// اسم جزء قياسي فوق الأساس القياسي لاسم الحزمة — علامة «part i/N»
/// قبل الامتداد والأساس يحمل آخر تسلسل للإرسال كله (الأجزاء شطر
/// إرسالٍ واحد لا حزم متفرقة).
String syncFilePartName({
  required String baseName,
  required int index,
  required int total,
}) {
  if (!baseName.endsWith('.dsync')) {
    throw SyncBundleStructureException(
        'اسم الأساس ليس باسم حزمة §10 (لا امتداد .dsync): $baseName');
  }
  if (index < 1 || index > total || total < 1) {
    throw SyncBundleStructureException(
        'رقم الجزء خارج مداه: $index من $total');
  }
  final stem = baseName.substring(0, baseName.length - '.dsync'.length);
  return '$stem.part${index}of$total.dsync';
}

/// يبني إرسال الجسر: حزمة واحدة إن اتّسعت للأحداث كلها تحت الحد،
/// وإلا أجزاء مرقمة تحترم التسلسل نص §10.
///
/// الفحص البنيوي على الإرسال كله أولاً (التسلسل متصل والـuuid فريد
/// والشركة واحدة) بنفس قواعد [buildSyncBundle] — فالأجزاء شطر حزمة
/// واحدة لا حزم متفرقة، ثم يُبنى كل جزء بمحرك د1 ذاته فيخرج كلٌّ
/// موقّعاً مغلفاً سليماً مستقلاً. حد التقسيم يتجاوز [maxPartBytes]
/// نصاً — والسطر الواحد الأعلى من ميزانية الجزء مرفوض صوتاً فلا
/// انقسام حدث أبداً (الحدث سطر واحد لا يُشطر).
Future<List<SyncBundleFile>> exportSyncFileBundles({
  required String companyId,
  required String deviceId,
  required List<SyncEvent> events,
  DateTime? exportedAt,
  Random? rng,
  int maxPartBytes = syncFilePartLimitBytes,
}) async {
  if (maxPartBytes < _minPartLimitBytes) {
    throw SyncBundleStructureException(
        'حد التقسيم أدنى من العتبة المشروعة ($maxPartBytes < '
        '$_minPartLimitBytes) — لا يتسع لغلاف وترويسة وحدث واحد');
  }
  if (companyId.trim().isEmpty) {
    throw const SyncBundleStructureException(
        'البناء: الشركة فارغة — لا حزمة بلا شركة');
  }
  if (deviceId.trim().isEmpty) {
    throw const SyncBundleStructureException('البناء: معرف الجهاز فارغ');
  }
  if (events.isEmpty) {
    throw const SyncBundleStructureException(
        'البناء: لا أحداث في الحزمة — لا معنى لنقل فراغ');
  }
  // فحص الإرسال كله بنفس قواعد البناء — الأجزاء شطر حزمة واحدة.
  final sorted = List<SyncEvent>.from(events)
    ..sort((a, b) => a.seq.compareTo(b.seq));
  final seenUuid = <String>{};
  for (var i = 0; i < sorted.length; i++) {
    final e = sorted[i];
    if (e.seq <= 0) {
      throw SyncBundleStructureException(
          'البناء: تسلسل غير موجب (${e.seq}) — seq يبدأ من 1');
    }
    if (i > 0 && e.seq != sorted[i - 1].seq + 1) {
      throw SyncBundleStructureException(
          'البناء: انكسار تسلسل seq (${sorted[i - 1].seq} ثم ${e.seq}) '
          '— التسلسل متصل بلا فجوة ولا تكرار');
    }
    if (e.uuid.trim().isEmpty || !seenUuid.add(e.uuid)) {
      throw SyncBundleStructureException(
          'البناء: uuid فارغ أو مكرر داخل الإرسال (${e.uuid})');
    }
    if (e.deviceId.trim().isEmpty ||
        e.entityType.trim().isEmpty ||
        e.action.trim().isEmpty) {
      throw const SyncBundleStructureException(
          'البناء: حقل حدث فارغ (device_id/entity_type/action)');
    }
    if (e.companyId.trim().isEmpty) {
      throw const SyncBundleStructureException(
          'البناء: حقل حدث فارغ (company_id)');
    }
    if (e.companyId != companyId) {
      throw SyncBundleStructureException(
          'البناء: حدث بشركة أخرى (${e.companyId}) لا تطابق ترويسة '
          'الإرسال ($companyId) — حزمة الشركة الواحدة لا تحمل غيرها');
    }
    if (e.eventAt < 0) {
      throw SyncBundleStructureException(
          'البناء: طابع زمني سالب (${e.eventAt})');
    }
  }

  // التجميع الجشع بالبايتات: ميزانية الجزء = الحد − الغلاف − هامش
  // الترويسة، والسطر الأعلى من الميزانية وحده مرفوض صوتاً فلا حدث
  // يُشطر بين جزأين أبداً.
  final plainBudget =
      maxPartBytes - _envelopeOverheadBytes - _partHeaderMarginBytes;
  final chunks = <List<SyncEvent>>[];
  var current = <SyncEvent>[];
  var currentBytes = 0;
  for (final e in sorted) {
    final lineBytes = utf8.encode(e.toLine()).length + 1; // + فاصل السطر
    if (lineBytes > plainBudget && current.isEmpty) {
      throw SyncBundleStructureException(
          'حدث واحد أعلى من ميزانية الجزء (${e.seq}) — الحد '
          '$maxPartBytes لا يتسع لحدث لا يُشطر');
    }
    if (currentBytes + lineBytes > plainBudget && current.isNotEmpty) {
      chunks.add(current);
      current = <SyncEvent>[];
      currentBytes = 0;
    }
    current.add(e);
    currentBytes += lineBytes;
  }
  if (current.isNotEmpty) chunks.add(current);

  final at = exportedAt ?? DateTime.now();
  final base = syncBundleFilename(
    at: at,
    deviceId: deviceId,
    lastSeq: sorted.last.seq,
  );
  final bundles = <SyncBundleFile>[];
  for (var i = 0; i < chunks.length; i++) {
    final part = await buildSyncBundle(
      companyId: companyId,
      deviceId: deviceId,
      events: chunks[i],
      exportedAt: at,
      rng: rng,
    );
    if (part.bytes.length > maxPartBytes) {
      throw SyncBundleStructureException(
          'الجزء ${i + 1} تجاوز الحد المسموح (${part.bytes.length} > '
          '$maxPartBytes) — معرف الجهاز أو الشركة طويل استثنائياً');
    }
    bundles.add(SyncBundleFile(
      filename: chunks.length == 1
          ? base
          : syncFilePartName(
              baseName: base, index: i + 1, total: chunks.length),
      bytes: part.bytes,
      header: part.header,
    ));
  }
  return bundles;
}

/// ملف الجسر الوارد — اسمه وبايتاته كما قرأه المستهلك من مسار
/// الملفات، والاسم حاكم علامة الأجزاء فلا يُغيَّر قبل الاستيراد.
class SyncFilePart {
  final String filename;
  final List<int> bytes;

  const SyncFilePart({required this.filename, required this.bytes});
}

/// إرسال مُستورد ومحكوم — الأحداث مدموجة بترتيب الأجزاء بعد اجتياز
/// §10 على كل جزء والتجاور بترتيبها، فالمستهلك يمررها على
/// [filterKnownSyncEvents] بعرف س-23 قبل أي إلحاق.
class SyncFileImport {
  final List<SyncEvent> events;

  /// عدد الأجزاء — للحزم غير المقسمة عدد الملفات المستقلة.
  final int partCount;

  /// هل جاء مقسَّماً بأجزاء «part i/N»؟
  final bool wasSplit;
  final String companyId;
  final String deviceId;
  final int firstSeq;
  final int lastSeq;

  const SyncFileImport({
    required this.events,
    required this.partCount,
    required this.wasSplit,
    required this.companyId,
    required this.deviceId,
    required this.firstSeq,
    required this.lastSeq,
  });
}

/// أجزاء الحزمة المقسمة ناقصة أو مكررة أو متضاربة أو خليط بحزم
/// مفردة — رفض الجسر قبل أي إلحاق — **DQ-1115**.
class SyncFilePartsException implements Exception {
  final String message;
  const SyncFilePartsException(this.message);
  @override
  String toString() => message;
}

/// يستورد ملفات الجسر ويحكمها نص §10 حرفاً:
///
/// - **بلا علامات أجزاء**: كل ملف حزمة مستقلة تُفتح بفحص د1 كاملاً
///   (وعزل الشركة المُتوقَّع إن مرر) وتُدمج أحداثها بترتيب الملفات.
/// - **بعلامات أجزاء**: المجموعة تستورد **كاملة بالترتيب** نص §10 —
///   علامة واحدة تكفي لفرض الاكتمال: نفس الأساس كلها، والترقيم
///   1..N بلا نقص ولا تكرار، وكل جزء يجتاز §10، والترويسات متفقة
///   بالشركة والجهاز، والأجزاء تتلو: نهاية كل جزء بداية تالِه − 1.
///   أي مخالفة رفض صوتي مفهرس **DQ-1115** قبل أي إلحاق.
Future<SyncFileImport> importSyncFileParts({
  required List<SyncFilePart> parts,
  String? expectedCompanyId,
}) async {
  if (parts.isEmpty) {
    throw const SyncBundleStructureException(
        'الاستيراد: لا ملفات — لا شيء يستورد');
  }
  final parsed = <({SyncFilePart part, String base, int index, int total})>[];
  for (final p in parts) {
    final m = _partNamePattern.firstMatch(p.filename);
    if (m == null) {
      parsed.add((part: p, base: '', index: 0, total: 0));
    } else {
      parsed.add((
        part: p,
        base: m.group(1)!,
        index: int.parse(m.group(2)!),
        total: int.parse(m.group(3)!),
      ));
    }
  }
  final marked = parsed.where((x) => x.index > 0).toList();
  final unmarked = parsed.where((x) => x.index == 0).toList();

  // حزم مفردة مستقلة — كل ملف حزمة §10 كاملة بذاته.
  if (marked.isEmpty) {
    final all = <SyncEvent>[];
    String? companyId;
    String? deviceId;
    for (final x in unmarked) {
      final contents = await openSyncBundle(
        x.part.bytes,
        expectedCompanyId: expectedCompanyId,
      );
      all.addAll(contents.events);
      companyId ??= contents.header.companyId;
      deviceId ??= contents.header.deviceId;
    }
    var lo = 0;
    var hi = 0;
    for (final e in all) {
      if (lo == 0 || e.seq < lo) lo = e.seq;
      if (e.seq > hi) hi = e.seq;
    }
    return SyncFileImport(
      events: all,
      partCount: unmarked.length,
      wasSplit: false,
      companyId: companyId ?? kDefaultCompanyId,
      deviceId: deviceId ?? '',
      firstSeq: lo,
      lastSeq: hi,
    );
  }

  // أجزاء حزمة مقسمة — الاكتمال والترتيب نص §10 قبل أي شيء.
  if (unmarked.isNotEmpty) {
    throw const SyncFilePartsException(
        'الاستيراد: خليط أجزاء مقسمة وحزم مفردة — الحزمة المقسمة '
        'تستورد أجزاءها كاملة وحدها نص §10');
  }
  final total = marked.first.total;
  final base = marked.first.base;
  for (final x in marked) {
    if (x.total != total) {
      throw SyncFilePartsException(
          'الاستيراد: عدد الأجزاء متضارب (${x.part.filename} يحمل '
          '${x.total} والبقية $total) — أجزاء إرسال واحد لا تختلف');
    }
    if (x.base != base) {
      throw SyncFilePartsException(
          'الاستيراد: أجزاء من أساسين مختلفين — «${x.base}» و«$base» '
          '— الأجزاء شطر إرسال واحد لا حزم متفرقة');
    }
  }
  final byIndex = <int, (SyncFilePart, int)>{};
  for (final x in marked) {
    if (x.index < 1 || x.index > total) {
      throw SyncFilePartsException(
          'الاستيراد: رقم جزء خارج مداه (${x.part.filename}) — '
          'الترقيم 1..$total');
    }
    if (byIndex.containsKey(x.index)) {
      throw SyncFilePartsException(
          'الاستيراد: الجزء ${x.index} وارد مرتين — الترقيم 1..$total '
          'كل رقم مرة واحدة نص §10');
    }
    byIndex[x.index] = (x.part, x.index);
  }
  for (var i = 1; i <= total; i++) {
    if (!byIndex.containsKey(i)) {
      throw SyncFilePartsException(
          'الاستيراد: أجزاء ناقصة — الجزء $i من $total غائب والحزمة '
          'المقسمة تستورد كاملة بالترتيب نص §10');
    }
  }

  final ordered = <SyncBundleContents>[];
  for (var i = 1; i <= total; i++) {
    final (part, _) = byIndex[i]!;
    ordered.add(await openSyncBundle(
      part.bytes,
      expectedCompanyId: expectedCompanyId,
    ));
  }
  final first = ordered.first.header;
  for (final c in ordered) {
    if (c.header.companyId != first.companyId ||
        c.header.deviceId != first.deviceId) {
      throw const SyncFilePartsException(
          'الاستيراد: أجزاء بترويسات متضاربة (شركة أو جهاز) — الأجزاء '
          'شطر إرسال جهاز واحد لا تختلف');
    }
  }
  for (var i = 1; i < ordered.length; i++) {
    final prev = ordered[i - 1];
    final cur = ordered[i];
    if (prev.header.lastSeq + 1 != cur.events.first.seq) {
      throw SyncFilePartsException(
          'الاستيراد: الأجزاء لا تتلو — نهاية الجزء $i (${prev.header.lastSeq}) '
          'ثم بداية ${i + 1} (${cur.events.first.seq}) — التجاور بلا '
          'فجوة نص §10');
    }
  }
  final merged = <SyncEvent>[
    for (final c in ordered) ...c.events,
  ];
  return SyncFileImport(
    events: merged,
    partCount: total,
    wasSplit: true,
    companyId: first.companyId,
    deviceId: first.deviceId,
    firstSeq: merged.first.seq,
    lastSeq: ordered.last.header.lastSeq,
  );
}
