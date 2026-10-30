import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

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
                  Text('في الفترة ${drafts.length} مسودة غير محسومة (س-20):'),
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
                              '${period.endDateText} — وما فيها مثبّت لا حركة تعود إليه (س-20)';
                        });
                        _reload();
                      } on PeriodClosingException catch (e) {
                        setDialogState(() => error = e.errors
                            .map(describePeriodClosingValidationError)
                            .join('؛ '));
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
                      'يوثق في سجل الأحداث بلقطة «لماذا فُتح» (س2)',
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
                  setDialogState(() => error = e.errors
                      .map(describePeriodClosingValidationError)
                      .join('؛ '));
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
      appBar: AppBar(title: const Text('الفترات والإقفال')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'الإقفال صلاحية مدير حصراً (07 §1.5) — والفك طارئ بسبب نصي '
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
      ),
    );
  }
}
