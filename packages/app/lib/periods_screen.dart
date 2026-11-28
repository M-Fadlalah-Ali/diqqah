import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
import 'auto_backup_prefs.dart';
import 'backup_center.dart';
import 'dq_log.dart';
import 'app_theme.dart';

/// شاشة الفترات والإقفال — س-85 من دفعة (6-ب): الإقفال يعرض قائمة مسودات
/// الفترة لطلب الحسم بتأكيد صريح (س-20: «ترحيلها أو تركها معلقة لا تُرحَّل
/// حتى الفك»)، والفك طارئ بسبب نصي إلزامي يوثق في السجل (س2).
///
/// الإقفال صلاحية مدير حصراً (07 §1.5) — وتنفيذ الصلاحية بطبقة الواجهة
/// إفصاحاً معروضاً (D-090/D-092): شاشة الأدوار الكاملة تليها، والمحرك
/// نفسه يوثق من قفل وفكَّ ولماذا بلقطة السجل بغض النظر عن الشاشة.
class PeriodsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const PeriodsScreen({super.key, required this.db});

  @override
  State<PeriodsScreen> createState() => _PeriodsScreenState();
}

class _PeriodsScreenState extends State<PeriodsScreen> {
  late Future<List<PeriodInfo>> _future;

  /// نشرة أعلى القائمة بعد كل نجاح — رسالة ثابتة لا مؤقتات خفية (درس
  /// مؤقتات Snackbar معلقة بتاريخ س22..س25).
  String? _notice;

  @override
  void initState() {
    super.initState();
    _future = widget.db.ledgerPeriods();
  }

  void _reload() {
    // بأقواس لا سهم: السهم يرجع Future من setState فيرمي استثناء (فشل CI
    // الجولة الأولى لدفعة 6-ب — 2026-10-31)
    setState(() {
      _future = widget.db.ledgerPeriods();
    });
  }

  Future<void> _closePeriod(PeriodInfo period) async {
    final drafts = await widget.db.periodOpenDrafts(period.id);
    if (!mounted) return;
    var confirmed = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
              'إقفال الفترة ${period.startDateText} → ${period.endDateText}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (drafts.isEmpty)
                  const Text(
                      'لا مسودات مفتوحة في هذه الفترة — الإقفال يجمد كل ما فيها إلى الأبد.')
                else ...[
                  Text('في الفترة ${drafts.length} مسودة غير محسومة:'),
                  for (final draft in drafts)
                    ListTile(
                      dense: true,
                      title: Text(draft.label),
                      subtitle: Text('${draft.docType} · ${draft.dateText}'),
                    ),
                  CheckboxListTile(
                    value: confirmed,
                    onChanged: (value) =>
                        setDialogState(() => confirmed = value ?? false),
                    title: const Text('أكّد تركها معلقة لا تُرحَّل حتى الفك'),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: (drafts.isEmpty || confirmed)
                  ? () async {
                      try {
                        await widget.db.closePeriod(
                          period.id,
                          draftsConfirmed:
                              drafts.isEmpty ? true : confirmed,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        setState(() {
                          _notice =
                              'أُقفلت الفترة ${period.startDateText} → '
                              '${period.endDateText} — وما فيها مثبّت لا حركة تعود إليه';
                        });
                        _reload();
                      } on PeriodClosingException catch (e) {
                        await dqLog(widget.db, e, context: 'period.close');
                        setDialogState(() => error =
                            '${e.errors.map(describePeriodClosingValidationError).join('؛ ')}'
                            '${dqTag(e)}');
                      }
                    }
                  : null,
              child: const Text('إقفال الفترة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPeriod(PeriodInfo period) async {
    final reasonController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
              'فك إقفال الفترة ${period.startDateText} → ${period.endDateText}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'سبب الفك (إلزامي)',
                  helperText:
                      'يوثق في سجل الأحداث بلقطة «لماذا فُتح»',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  setDialogState(() => error =
                      'فك الإقفال طارئ بسبب نصي إلزامي — اكتب سبب الفك ولا يفتح بلا سبب');
                  return;
                }
                try {
                  await widget.db.openPeriod(period.id, reason: reason);
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  setState(() {
                    _notice = 'فُتحت الفترة ${period.startDateText} → '
                        '${period.endDateText} — والسبب موثق في سجل الأحداث';
                  });
                  _reload();
                } on PeriodClosingException catch (e) {
                  await dqLog(widget.db, e, context: 'period.open');
                  setDialogState(() => error =
                      '${e.errors.map(describePeriodClosingValidationError).join('؛ ')}'
                      '${dqTag(e)}');
                }
              },
              child: const Text('فتح الفترة'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الفترات والإقفال'), actions: [
        // الدفعة 32 (تاسعة م2): الإقفال السنوي — س-21/F-077/D-068:
        // شاشة نهاية السنة بالمعاينة والتأكيد الصريح.
        TextButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => YearCloseScreen(db: widget.db),
            ),
          ),
          icon: const Icon(Icons.event_available_outlined),
          label: const Text('الإقفال السنوي'),
        ),
      ]),
      body: DiqqahAdaptiveCenter(child: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'الإقفال صلاحية مدير حصراً — والفك طارئ لأن سببه نصي '
                'إلزامي يوثق في السجل. المسودات المعلقة فوق المقفلة لا تُرحَّل حتى الفك.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (_notice != null)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_notice!),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<PeriodInfo>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final periods = [...snapshot.data!]
                  ..sort((a, b) =>
                      a.startDateText.compareTo(b.startDateText));
                return ListView(
                  children: [
                    for (final period in periods)
                      ListTile(
                        title: Text(
                            'فترة ${period.startDateText} → ${period.endDateText}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(period.isOpen ? 'مفتوحة' : 'مقفلة'),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => period.isOpen
                                  ? _closePeriod(period)
                                  : _openPeriod(period),
                              child: Text(period.isOpen
                                  ? 'إقفال'
                                  : 'فك الإقفال'),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}

/// شاشة الإقفال السنوي — الدفعة 32 (تاسعة م2) على نص س-21/F-077 حرفاً:
/// «مراجعة ميزان المراجعة والنتيجة قبلية؛ تأكيد الإقفال بعد إقفال كل
/// فترات السنة» — المعاينة كلها قراءة (D-183: ما يُرى هو ما سينفذ)
/// وبأخطاء الرفض ظاهرة، والتنفيذ بتأكيد صريح فتُرحَّل قيود الإغلاق
/// الثلاثة وافتتاحية السنة الجديدة عبر المحرك الموحد، والسنة «مقفلة»
/// ولا ترحيل فيها أبداً — والإقفال صلاحية مدير حصراً (07 §1.5) بتنفيذ
/// الصلاحية بطبقة الواجهة إفصاحاً (D-090).
class YearCloseScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const YearCloseScreen({super.key, required this.db});

  @override
  State<YearCloseScreen> createState() => _YearCloseScreenState();
}

class _YearCloseScreenState extends State<YearCloseScreen> {
  late Future<YearClosePreview> _future;
  bool _confirmed = false;
  String? _notice;
  String? _resultSummary;

  @override
  void initState() {
    super.initState();
    // معرّف السنة المفتوحة الأخيرة — الإقفال يبدأ منها دائماً (البذر
    // سنة واحدة والافتتاحية تضيف التالية فالآخرة هي مرشحة الإقفال).
    _future = _latestOpenYearId().then((id) => widget.db.fiscalYearClosePreview(id));
  }

  /// معرّف السنة الأخيرة المفتوحة.
  Future<int> _latestOpenYearId() async {
    final rows = await widget.db.customSelect(
      "SELECT id FROM fiscal_years WHERE state = 'open' "
      'ORDER BY id DESC LIMIT 1',
    ).get();
    return rows.first.data['id'] as int;
  }

  void _reload() {
    if (_resultSummary != null) {
      // بعد الإقفال: الصفحة تعرض النتيجة وحدها حتى الخروج — لا معاينة
      // بعد الإقفال (الإقفال مرة واحدة ولا سنة مفتوحة قابلة للمعاينة).
      return;
    }
    setState(() {
      _future = _latestOpenYearId()
          .then((id) => widget.db.fiscalYearClosePreview(id));
    });
  }

  Future<void> _executeClose() async {
    // تكليف 2026-11-13 §2: نسخة حدثية (بيانات+مرفقات، آخر 5) قبل
    // الإقفال — شبكة الأمان ضد عطل إقفال يظهر لاحقاً؛ ثم سنوية دائمة
    // (بيانات+مرفقات) بعد نجاحه — أرشيف السنة المقفلة، مع رسالة تنبيه
    // بنقلها خارج الجهاز (قرارك: تنبيه بلا متابعة). المركز غائب في
    // الاختبارات المحقونة فتجري الإقفالات بلا نسخ — سلوك محقون صريح.
    final center = BackupCenter.instance;
    center?.pause();
    try {
      if (center != null) {
        final event = await center.createYearCloseEventBackup();
        if (event == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'تعذرت النسخة الحدثية قبل الإقفال — الإقفال يمضي '
                    'ومركز النسخ سجل العطل بشارة حمراء')),
          );
        }
      }
      final yearId = await _latestOpenYearId();
      final result = await widget.db.fiscalYearClose(yearId);
      if (!mounted) return;
      setState(() {
        _notice = null;
        _confirmed = false;
        _resultSummary =
            'أُقفلت السنة ${result.yearName} — صافيها '
            '${result.netResultMinor >= 0 ? 'ربح' : 'خسارة'} '
            '${result.netResultMinor.abs()} وحدة صغرى، وقيودها '
            '${result.closingMoveIds.length} إغلاقية و'
            '${result.openingMoveId == null ? 'بلا افتتاحية' : 'افتتاحية'}، '
            'والبذرة ${result.nextYearName} بفتراتها المفتوحة. '
            'السنة المقفلة لا ترحيل فيها أبداً';
      });
      _reload();
      // السنوية بعد نجاح الإقفال حصراً — أرشيف السنة بمقعدها الأخير.
      // س233 (D-232 — المرحلة أ/3): الخانة السنوية المتقدمة ببطاقة
      // النسخ الآلي تحكمها وحدها (والحدثية قبل الإقفال شبكة أمان فوقها
      // لا تُمس بهذه الخانة أبداً).
      if (center != null && autoBackupAnnualAtClose.value) {
        final annual = await center.createAnnualBackup();
        if (annual != null && mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('نسخة سنوية دائمة'),
              content: Text(
                  'أُنشئت النسخة السنوية للسنة ${result.yearName} '
                  '(بيانات مع المرفقات) ولا تُحذف آلياً أبداً.\n''انقلها الآن خارج الجهاز من شاشة كتالوج النسخ — هي '
                  'النسخة الأرشيفية الوحيدة للسنة المقفلة.'),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('تم')),
              ],
            ),
          );
        }
      }
    } on YearCloseException catch (e) {
      await dqLog(widget.db, e, context: 'year.close');
      if (!mounted) return;
      setState(() {
        _notice =
            '${e.errors.map(describeYearCloseValidationError).join('؛ ')}'
            '${dqTag(e)}';
      });
      _reload();
    } finally {
      // §8-5: إيقاف المجدول كان للحدثية — يعود بعد الإقفال.
      center?.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإقفال السنوي')),
      body: _resultSummary != null
          ? ListView(
              padding: EdgeInsets.fromLTRB(
                  diqqahAdaptiveHorizontalMargin(context),
                  12,
                  diqqahAdaptiveHorizontalMargin(context),
                  12),
              children: [
              Card(
                color: diqqahLanesOf(context).positive.bg,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_resultSummary!),
                ),
              ),
            ])
          : FutureBuilder<YearClosePreview>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final preview = snapshot.data!;
                final (debitTotal, creditTotal) = preview.trialTotals;
                final balanced = debitTotal == creditTotal;
                final plan = preview.plan;
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('سنة ${preview.yearName} '
                                '(${preview.startDateText} → '
                                '${preview.endDateText})',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium),
                            const SizedBox(height: 4),
                            Text(preview.yearClosed
                                ? 'الحالة: مقفلة — الإقفال مرة واحدة'
                                : 'الحالة: مفتوحة · الفترات: '
                                    '${preview.periodsCount} منها '
                                    '${preview.openPeriodsCount} مفتوحة'),
                          ],
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: Icon(
                          balanced
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_outlined,
                          color: balanced
                              ? diqqahLanesOf(context).positive.fg
                              : diqqahLanesOf(context).negative.fg,
                        ),
                        title: Text(balanced
                            ? 'الميزان متوازن ✓'
                            : 'الميزان غير متوازن — راجع فوراً!'),
                        subtitle: Text('مدين $debitTotal · دائن $creditTotal'),
                      ),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('النتيجة قبلية',
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(plan.netResultMinor >= 0
                                ? 'ربح ${plan.netResultMinor} وحدة صغرى — '
                                    'ينتقل 332 مديناً / 331 دائناً'
                                : 'خسارة ${plan.netResultMinor.abs()} وحدة '
                                    'صغرى — بالعكس 331 مديناً / 332 دائناً'),
                            const SizedBox(height: 4),
                            Text('الإيرادات ${plan.incomeTotalMinor} · '
                                'المصروفات ${plan.expenseTotalMinor} · '
                                'أسطر الإغلاق ${plan.incomeLines.length + plan.expenseLines.length} '
                                '· الافتتاحية ${plan.openingLines.length} سطراً'),
                          ],
                        ),
                      ),
                    ),
                    if (_notice != null)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_notice!),
                        ),
                      ),
                    if (preview.openPeriodsCount > 0)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(describeYearCloseValidationError(
                              YearHasOpenPeriods(
                                  preview.yearName,
                                  preview.openPeriodsCount))),
                        ),
                      ),
                    if (preview.yearClosed)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(describeYearCloseValidationError(
                              FiscalYearAlreadyClosed(preview.yearName))),
                        ),
                      ),
                    CheckboxListTile(
                      value: _confirmed,
                      onChanged: preview.isReady
                          ? (value) =>
                              setState(() => _confirmed = value ?? false)
                          : null,
                      title: const Text(
                          'أكّد الإقفال السنوي — قيودُ الإغلاق تُرحَّل '
                          'بتاريخ نهاية السنة وتُبذر السنة التالية '
                          'بافتتاحيتها، والسنة المقفلة لا ترحيل فيها أبداً'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          preview.isReady && _confirmed ? _executeClose : null,
                      icon: const Icon(Icons.event_available),
                      label: const Text('ترحيل الإقفال السنوي'),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
