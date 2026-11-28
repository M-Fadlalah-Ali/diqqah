/// س236 (د10 البنوك — D-224 بأمر المالك «نفذ د10»): شاشة التسوية
/// البنكية لصندوق جارٍ بنكي — رصيد كشف البنك المدخل يقارن بالرصيد
/// الدفتري المعلن فالفرق عجزاً أو زيادة يُرحَّل **بنمط تسوية الصندوق**
/// (س-17/F-067: على 57 — س8) بلا مسار موازٍ، مع قائمة سابقاتها
/// — والشاشة جديدة كلياً فنصوصها بمفاتيح حصراً (عرف د12/س232).
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'app_theme.dart';
import 'dq_log.dart';
import 'date_picker.dart';
import 'hijri_display.dart';
import 'input_formatters.dart';
import 'l10n/app_strings.dart';
import 'reports_screen.dart' show formatMinorAmount;

/// شاشة التسوية البنكية — تفتح من صندوق بنكي بقائمة الصناديق حصراً.
class BankReconScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final CashBoxReportRow box;

  const BankReconScreen({super.key, required this.db, required this.box});

  @override
  State<BankReconScreen> createState() => _BankReconScreenState();
}

class _BankReconScreenState extends State<BankReconScreen> {
  final TextEditingController _date = TextEditingController();
  final TextEditingController _statement = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  /// الرصيد الدفتري بعملة كشف الصندوق — محمّل معلناً للنموذج.
  int? _bookBalanceDocMinor;

  List<BankReconciliationListRow>? _rows;
  List<String>? _errors;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ الافتراضي — نموذج التسوية عينه.
    _date.text = todayIsoDate();
    // س236: الفرق الحي — كتابة الكشف تعيد البناء (لا معاينة بلا جسد).
    _statement.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final book = await widget
        .db.bankBoxBookBalanceDocMinor(widget.box.boxId);
    final rows = await widget.db.bankReconciliationsOf(
        cashBoxId: widget.box.boxId);
    if (!mounted) return;
    setState(() {
      _bookBalanceDocMinor = book;
      _rows = rows;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _date.dispose();
    _statement.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// رصيد الكشف المدخل بوحدة صغرى (المجمّع بفواصل الآلاف).
  int get _statementMinor => parseGroupedInt(_statement.text.trim());

  /// الفرق المحسوب لحظياً — الكشف ناقص الدفتري (موجب: زيادة).
  int? get _differenceDocMinor =>
      _bookBalanceDocMinor == null ? null : _statementMinor - _bookBalanceDocMinor!;

  BankReconciliationDraft _buildDraft() {
    return BankReconciliationDraft(
      dateText: _date.text.trim(),
      cashBoxId: widget.box.boxId,
      currencyId: widget.box.currencyId,
      statementBalanceDocMinor: _statementMinor,
      bookBalanceDocMinor: _bookBalanceDocMinor ?? 0,
      reason: _reason.text,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final draft = _buildDraft();
    final structure = validateBankReconciliationStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure) describeBankReconValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      // بنمط نموذج التسوية حرفاً: مسودة ثم ترحيل — محرك واحد.
      final id = await widget.db.createBankReconciliationDraft(draft);
      await widget.db.postBankReconciliation(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BankReconciliationValidationException catch (e) {
      await dqLog(widget.db, e, context: 'bank.recon');
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeBankReconValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'bank.recon');
      if (!mounted) return;
      setState(() {
        _errors = ['$e${dqTag(e)}'];
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text(S.bankReconTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final diff = _differenceDocMinor;
    final lanes = diqqahLanesOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text(S.bankReconTitle)),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              children: [
                if (_errors != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _errors!)
                            Text(e,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer)),
                        ],
                      ),
                    ),
                  ),
                // بطاقة الصندوق البنكي — هويته ورصيده الدفتري معلنين.
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.account_balance_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${widget.box.name}'
                              '${widget.box.bankName == null ? '' : ' — ${widget.box.bankName}'}'
                              ' (${widget.box.currencyCode})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          '${S.bookBalanceLabel}: '
                          '${formatMinorAmount(_bookBalanceDocMinor ?? 0)}'
                          ' ${widget.box.currencyCode}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                TextField(
                  controller: _statement,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: S.statementBalanceLabel,
                      helperText: S.statementBalanceHelper),
                ),
                // الفرق المحسوب لحظياً — بلون مساره (زيادة إيجابية /
                // عجز سالبة) وبلا ضغطة حتى الآن (معاينة نقية).
                if (diff != null && _statement.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      diff == 0
                          ? S.reconNoDifference
                          : '${diff > 0 ? CashAdjustmentDirection.overage.label : CashAdjustmentDirection.shortage.label}'
                                ': ${formatMinorAmount(diff.abs())}'
                                ' ${widget.box.currencyCode} — 57',
                      style: TextStyle(
                        color: diff == 0
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : (diff > 0 ? lanes.positive.fg : lanes.negative.fg),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                      labelText: S.dateWithFormatHint,
                      suffixIcon: calendarPickerSuffix(context, _date)),
                ),
                TextField(
                  controller: _reason,
                  decoration:
                      const InputDecoration(labelText: S.reconReasonLabel),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text(S.postReconButton),
                ),
                const SizedBox(height: 16),
                // تسويات سابقة — أحدثها أولاً بلغة القوائم الموحدة.
                Text(S.reconHistoryTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (_rows == null || _rows!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(S.emptyReconList,
                        textAlign: TextAlign.center),
                  )
                else
                  for (final row in _rows!)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.fact_check_outlined),
                        title: Text(row.displayLabel),
                        subtitle: Text(
                          '${displayDate(row.dateText)}'
                          ' · ${row.direction.label}'
                          ' · ${S.statementBalanceLabel}: '
                          '${formatMinorAmount(row.statementBalanceDocMinor)}'
                          ' ${row.currencyCode}'
                          ' · ${row.stateLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                            '${formatMinorAmount(row.amountDocMinor)}'
                            ' ${row.currencyCode}'),
                      ),
                    ),
              ],
            ),
    );
  }
}
