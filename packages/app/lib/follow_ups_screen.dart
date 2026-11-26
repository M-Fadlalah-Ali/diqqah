/// شاشة المتابعات (د-7/§25.9 — س141 — التسمية المعتمدة بقرار المالك):
/// تجميع عرض فوق المصادر لا كائن بيانات جديد — الباني النقي بالمجال
/// (follow_ups.dart) واللوحة هنا بأفعالها المحقونة (نمط لوحة التذكيرات
/// الذكية b39: باني نقي + لوحة + أفعال محقونة). يدخلها المسؤول، ولا
/// تمنع العمل — والرئيسية تحمل شارة حمراء حتى تُعالَج (§25.9).
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
import 'backup_center.dart';
import 'import_screen.dart';
import 'items_screen.dart';
import 'ledger_screen.dart';
import 'periods_screen.dart';
import 'receivables_screen.dart';
import 'settings_screen.dart';
import 'app_theme.dart';

/// لقطة المتابعات المحمّلة — المدخلات ببنودها (كل متابعة صالحة منفردة).
class FollowUpsSnapshot {
  final FollowUpsInput input;
  final List<FollowUpEntry> entries;

  const FollowUpsSnapshot(this.input, this.entries);
}

/// تحميل مصادر المتابعات من القاعدة ومركز النسخ — تجميع عرض فوق
/// المصادر القائمة لا قراءة سحرية: أحداث الاستيراد بعد آخر تأكيد،
/// ورصيد 332، والنافذة، وبداية السنة، وحصة النسخ — ومركز النسخ قد
/// يغيب بوضع الاختبار فمصدراه (العتبات والطوارئ) يصمتان.
Future<FollowUpsSnapshot> loadFollowUps(DiqqahDatabase db) async {
  final reviewedThrough = await db.followUpsReviewedThrough();
  final events = await db.importEventsSince(reviewedThrough);
  var partiesCreated = 0;
  var itemsCreated = 0;
  var unitsCreated = 0;
  var partiesSkipped = 0;
  var itemsSkipped = 0;
  for (final e in events) {
    partiesCreated += e.partiesCreated;
    itemsCreated += e.itemsCreated;
    unitsCreated += e.unitsCreated;
    partiesSkipped += e.partiesSkipped;
    itemsSkipped += e.itemsSkipped;
  }
  final rollback = await db.rollbackWindow();
  final fiscalStart = await db.earliestOpenPeriodStartText();
  final fiscalAck = await db.fiscalStartAcknowledged();
  final hasPosted = await db.earliestPostedMoveDateText() != null;
  final undistributed = await db.openingUndistributedBaseMinor();
  double quota = 0;
  var emergency = 0;
  final center = BackupCenter.instance;
  if (center != null) {
    quota = center.health.value?.quotaUsedFraction ?? 0;
    final store = center.store;
    if (store != null) {
      emergency = store.catalog.entries
          .where((e) =>
              e.kind == BackupScheduleKind.event ||
              e.fileName.startsWith('diqqah-before-restore'))
          .length;
    }
  }
  final input = FollowUpsInput(
    openingUndistributedBaseMinor: undistributed,
    importEventsAwaitingReview: events.length,
    partiesAutoCreated: partiesCreated,
    itemsAutoCreated: itemsCreated,
    unitsAutoCreated: unitsCreated,
    partiesSkipped: partiesSkipped,
    itemsSkipped: itemsSkipped,
    emergencyCopiesCount: emergency,
    rollbackWindowOpen: rollback != null && !rollback.closed,
    fiscalYearStartText: fiscalStart,
    fiscalStartAcknowledgedText: fiscalAck,
    hasPostedMoves: hasPosted,
    quotaUsedFraction: quota,
    // د6 (س175): المتابعات اليومية (س74/D-184) — مصادرها الثلاثة
    // من استعلاماتها القائمة والصياغة بالمجال النقي حصراً.
    belowMinimumItems: [
      for (final r in await db.itemsBelowMinimum())
        BelowMinimumItem(
          sku: r.sku,
          name: r.name,
          availableQty: r.availableQty,
          minimumQty: r.minimumQty,
        ),
    ],
    overAmountCapBalances: [
      for (final r in await db.partiesOverCreditCap())
        OverAmountCapBalance(
          partyName: r.partyName,
          balanceMinor: r.netDebitBaseMinor,
          capMinor: r.capBaseMinor,
        ),
    ],
    overTimeCapBalances: [
      for (final r in await db.partiesOverPaymentTerm())
        OverTimeCapBalance(
          partyName: r.partyName,
          oldestAgeDays: r.oldestAgeDays,
          termDays: r.termDays,
        ),
    ],
  );
  return FollowUpsSnapshot(input, buildFollowUps(input));
}

class FollowUpsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// مسار القاعدة ولسان الاستعادة — يمرّران لمن تفتحه المتابعات
  /// (الإعدادات) فلا مسار ميت بلا سلسلة (نمط الرئيسية القائمة).
  final String dbPath;
  final VoidCallback onRestored;

  /// محمّل محقون للاختبار (نمط المزودات المحقونة) — الافتراضي
  /// loadFollowUps بالقاعدة الحية.
  final Future<FollowUpsSnapshot> Function()? loadOverride;

  /// أفعال محقونة (نمط لوحة b39): ما يُختبر هو ما يُشغَّل حرفاً.
  final VoidCallback? onOpenImport;
  final VoidCallback? onOpenBackups;
  final VoidCallback? onOpenPeriods;
  final VoidCallback? onOpenLedger;

  /// س221 — وجه المدخلات اليومية الثلاثة الحقيقي: الأصناف بشاشتها
  /// والذمم بشاشتها (قرار المالك بعلاج زرّي «أصناف المخزون» و«أعمار
  /// الذمم» اللذين كانا يفتحان استيراد البيانات — خطأ مسار موثق
  /// بلسان المالك).
  final VoidCallback? onOpenItems;
  final VoidCallback? onOpenReceivables;
  final Future<void> Function()? onConfirmReview;
  final Future<void> Function()? onAckFiscalStart;

  const FollowUpsScreen({
    super.key,
    required this.db,
    this.dbPath = '',
    this.onRestored = _noop,
    this.loadOverride,
    this.onOpenImport,
    this.onOpenBackups,
    this.onOpenPeriods,
    this.onOpenLedger,
    this.onOpenItems,
    this.onOpenReceivables,
    this.onConfirmReview,
    this.onAckFiscalStart,
  });

  static void _noop() {}

  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  FollowUpsSnapshot? _snapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final loader = widget.loadOverride ?? () => loadFollowUps(widget.db);
    final snapshot = await loader();
    if (mounted) setState(() => _snapshot = snapshot);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      await _reload();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openImport() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ImportScreen(db: widget.db)));

  void _openBackups() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
          db: widget.db, dbPath: widget.dbPath, onRestored: widget.onRestored)));

  void _openPeriods() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PeriodsScreen(db: widget.db)));

  void _openLedger() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LedgerScreen(db: widget.db)));

  /// س221 — وجه المدخلات اليومية الحقيقي (شاشة المصدر لا الاستيراد).
  void _openItems() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ItemsScreen(db: widget.db)));

  void _openReceivables() =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ReceivablesScreen(db: widget.db)));

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('المتابعات')),
      body: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : snapshot.entries.isEmpty
              ? const Center(
                  child: Text('لا متابعات الآن — كل شيء متابَع'),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      diqqahAdaptiveHorizontalMargin(context),
                      12,
                      diqqahAdaptiveHorizontalMargin(context),
                      12),
                  children: [
                    const Text(
                        'تجميع ما يحتاج انتباهك فوق مصادره القائمة — لا '
                        'يمنع العمل، وكل متابعة صالحة منفردة.'),
                    const SizedBox(height: 8),
                    for (final entry in snapshot.entries)
                      _entryCard(entry),
                  ],
                ),
    );
  }

  Widget _entryCard(FollowUpEntry entry) {
    // الأزقة الدلالية (س186): العاجل سلبي والانتباه أزرق والمعلومة
    // أساس — لا برتقالي خام.
    final lanes = diqqahLanesOf(context);
    final color = switch (entry.severity) {
      FollowUpSeverity.urgent => lanes.negative.fg,
      FollowUpSeverity.attention => lanes.attention.fg,
      FollowUpSeverity.info => lanes.positive.fg,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(switch (entry.severity) {
                  FollowUpSeverity.urgent => Icons.error_outline,
                  FollowUpSeverity.attention => Icons.warning_amber,
                  FollowUpSeverity.info => Icons.info_outline,
                }, color: color),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(entry.title,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 4),
            Text(entry.description),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _entryAction(entry),
                icon: const Icon(Icons.arrow_back),
                label: Text(entry.actionLabel),
              ),
            ),
            // بند التاريخ (§25.9): الإقرار فعله الأساسي والتعديل من
            // شاشة الفترات قبله — «للإقرار أو التعديل قبل الترحيل».
            if (entry.id == 'fiscal_year_start')
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed:
                      _busy ? null : (widget.onOpenPeriods ?? _openPeriods),
                  child: const Text('تعديل التاريخ من شاشة الفترات'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _entryAction(FollowUpEntry entry) async {
    switch (entry.id) {
      case 'import_auto_created':
      case 'import_skipped_existing':
        await _run(widget.onConfirmReview ??
            () => widget.db.markFollowUpsReviewed());
      case 'fiscal_year_start':
        await _run(widget.onAckFiscalStart ??
            () => widget.db.acknowledgeFiscalYearStart());
      case 'opening_reclassify':
        (widget.onOpenLedger ?? _openLedger)();
      case 'daily_below_minimum':
        // س221 — وجهها شاشة الأصناف لا الاستيراد (قرار المالك بعلاج
        // خطأ المسار الموثق: زرّا أصناف المخزون وأعمار الذمم كانا
        // يفتحان استيراد البيانات بسقوطهما في default).
        (widget.onOpenItems ?? _openItems)();
      case 'daily_over_credit_cap':
      case 'daily_over_term':
        // س221 — وجههما شاشة الذمم (أرصدة الأطراف وأعمار الذمم).
        (widget.onOpenReceivables ?? _openReceivables)();
      case 'rollback_window_open':
      case 'emergency_copies':
      case 'storage_threshold':
        (widget.onOpenBackups ?? _openBackups)();
      default:
        // درس س221 الموثق: كل مدخل جديد يُمنح وجهه الحقيقي صراحة —
        // الاستيراد وجه النواقص لا وجه كل ما لم يُخصَّص.
        (widget.onOpenImport ?? _openImport)();
    }
  }
}
