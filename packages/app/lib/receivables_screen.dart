/// شاشة الذمم — الوحدة المفتوحة الرابعة عشرة (س125 — بأمر المالك
/// الحرفي «بعد الانتهاء نتوجه إلى تفعيل الذمم والدفتر المحاسبي»
/// بعد إغلاق b36 بأمره «قم ببناء b36»).
///
/// الإصدار 1 قراءة خالصة فوق البنية المنجزة م1 بلا ترحيلة ولا مساس
/// بالقلب المحاسبي — عين روح الطلبات (س121: الأساس قائم فالواجهة
/// تستكمل):
/// - تبويب «أرصدة الأطراف»: receivablesPayablesReport (س-73/س-81)
///   بلسان المالك الموثق: المدينة «هم يدينون لنا» أولاً ثم الدائنة
///   «نحن مدينون لهم» — وكل مجموعة بأسمائها — وفلاتر الكل/المدينة/الدائنة
///   بنمط تقرير التقارير اليومية ذاته (المصدر واحد فالعرض واحد).
/// - الضغط على طرف يفتح «كشف حساب الطرف» (partyStatementReport):
///   أسطر القيود المرحّلة المجمدة لا يعاد حسابها (07 §2) بخلاصة
///   مدين/دائن وصافٍ تراكمي بصيغة الذمم (مدين − دائن).
/// - تبويب «أعمار الذمم» (س-151/D-149): agingReport بفوهج aging_prefs
///   القابلة للتهيئة — المفهرس الجاهز حصراً (درس D-149: القيمة تطابق
///   بالهوية) — والمفهرس مشترك ValueNotifier فتتجدد الشاشة لحظياً
///   وتُحفظ بالتفضيل ذاته فالشاشتان (هنا والتقارير) بلسان واحد.
///
/// الحدود الصادقة (الإصدار 1): لا تسويات من هنا — التصحيح سند
/// أو مردود بمساره القائم — ولا إرسال ولا طباعة دفعة هذه، والحدود
/// الائتمانية ببطاقة الطرف الموجودة لا هنا.
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart'
    show PartyBalanceDirection, ReceivablesPayablesRow;
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
import 'aging_prefs.dart';
import 'vouchers_screen.dart';
import 'reports_screen.dart' show formatMinorAmount;
import 'app_theme.dart';

class ReceivablesScreen extends StatelessWidget {
  final DiqqahDatabase db;

  const ReceivablesScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الذمم'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'أرصدة الأطراف'),
              Tab(text: 'أعمار الذمم'),
            ],
          ),
        ),
        body: DiqqahAdaptiveCenter(child: TabBarView(
          children: [
            _BalancesTab(db: db),
            _AgingTab(db: db),
          ],
        ),
      )),
    );
  }
}

/// تبويب الأرصدة — المدينة أولاً بلفظ المالك الموثق (س-73/س-81)
/// ثم الدائنة، وكل مجموعة بأسمائها — والفلاتر الثلاثة.
class _BalancesTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _BalancesTab({required this.db});

  @override
  State<_BalancesTab> createState() => _BalancesTabState();
}

class _BalancesTabState extends State<_BalancesTab>
    with AutomaticKeepAliveClientMixin {
  /// المستقبل مرة واحدة لعمر الحالة — درس السرد الكسول الموثق.
  late final Future<List<ReceivablesPayablesRow>> _data =
      widget.db.receivablesPayablesReport();

  /// قيمة الفلتر: null = الكل، true = مدينة (هم يدينون لنا)،
  /// false = دائنة (نحن مدينون لهم) — بنمط تقرير التقارير ذاته.
  bool? _kind;

  @override
  bool get wantKeepAlive => true;

  String _directionLabel(PartyBalanceDirection d) => d == PartyBalanceDirection.theyOweUs
      ? 'مدينة — هم يدينون لنا'
      : 'دائنة — نحن مدينون لهم';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<ReceivablesPayablesRow>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        if (all.isEmpty) {
          return const Center(child: Text('لا ذمم — كل الحسابات مصفاة'));
        }
        // الترتيب الافتراضي بلفظ المالك: المدينة ثم الدائنة — وكل
        // مجموعة بأسمائها (المصدر واحد فالعرض واحد مع تقرير التقارير).
        final sorted = [...all]..sort((a, b) {
            final ka = a.direction == PartyBalanceDirection.theyOweUs ? 0 : 1;
            final kb = b.direction == PartyBalanceDirection.theyOweUs ? 0 : 1;
            if (ka != kb) return ka - kb;
            return a.partyName.compareTo(b.partyName);
          });
        final rows = _kind == null
            ? sorted
            : sorted
                .where((r) =>
                    (r.direction == PartyBalanceDirection.theyOweUs) ==
                    _kind!)
                .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  ChoiceChip(
                    label: const Text('مدينة'),
                    selected: _kind == true,
                    onSelected: (_) => setState(() => _kind = true),
                  ),
                  ChoiceChip(
                    label: const Text('دائنة'),
                    selected: _kind == false,
                    onSelected: (_) => setState(() => _kind = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('لا أرصدة بهذا الفلتر'))
                  : ListView(
                      children: [
                        for (final r in rows)
                          ListTile(
                            leading: Icon(
                              r.direction == PartyBalanceDirection.theyOweUs
                                  ? Icons.call_received
                                  : Icons.call_made,
                              color: r.direction ==
                                      PartyBalanceDirection.theyOweUs
                                  ? diqqahLanesOf(context).positive.fg
                                  : diqqahLanesOf(context).negative.fg,
                            ),
                            title: Text(r.partyName),
                            subtitle: Text(_directionLabel(r.direction)),
                            trailing: Text(
                              formatMinorAmount(r.amountMinor),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartyStatementPage(
                                  db: widget.db,
                                  partyId: r.partyId,
                                  partyName: r.partyName,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// كشف حساب الطرف — partyStatementReport: أسطر القيود المرحّلة
/// المجمدة لا يعاد حسابها (07 §2) بخلاصته بصيغة الذمم (مدين − دائن).
class PartyStatementPage extends StatelessWidget {
  final DiqqahDatabase db;
  final int partyId;
  final String partyName;

  const PartyStatementPage({
    super.key,
    required this.db,
    required this.partyId,
    required this.partyName,
  });

  String _closingLabel(int net) {
    if (net > 0) return 'الصافي: هم يدينون لنا ${formatMinorAmount(net)}';
    if (net < 0) {
      return 'الصافي: نحن مدينون لهم ${formatMinorAmount(-net)}';
    }
    return 'الصافي: مصفاة — لا ذمة';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('كشف حساب — $partyName')),
      floatingActionButton: FloatingActionButton.extended(
        // س203: «+» كشف حساب الطرف — سند جديد بطرف الكشف معبّأً
        // من أول لحظة (عميل يفتح القبض ومورد الصرف) بضغطة أقل،
        // وعرف النوع بالضغط الصريح باقٍ (س-163).
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VoucherEditScreen(
              db: db,
              initialPartyId: partyId,
            ),
          ),
        ),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('سند جديد'),
      ),
      body: DiqqahAdaptiveCenter(child: FutureBuilder<PartyStatementReport>(
        future: db.partyStatementReport(partyId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snapshot.data!;
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المدين: ${formatMinorAmount(r.totalDebitMinor)}'
                          ' — الدائن: ${formatMinorAmount(r.totalCreditMinor)}'),
                      const SizedBox(height: 4),
                      Text(
                        _closingLabel(r.closingNetDebitMinor),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: r.entries.isEmpty
                    ? const Center(child: Text('لا قيود مرحّلة على الطرف'))
                    : ListView(
                        children: [
                          for (final e in r.entries)
                            ListTile(
                              dense: true,
                              title: Text('${e.moveNumber} — ${e.moveDate}'),
                              subtitle: Text(
                                '${e.accountCode}'
                                '${e.narration == null || e.narration!.isEmpty ? '' : ' • ${e.narration}'}',
                              ),
                              trailing: SizedBox(
                                width: 170,
                                child: Text(
                                  'مدين ${formatMinorAmount(e.debitMinor)}\n'
                                  'دائن ${formatMinorAmount(e.creditMinor)}\n'
                                  'الصافي التراكمي: '
                                  '${formatMinorAmount(e.runningNetDebitMinor)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                      height: 1.25),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      )),
    );
  }
}

/// تبويب أعمار الذمم (س-151/D-149) — الفوهج من aging_prefs بالفهرس
/// الجاهز حصراً والمفهرس مشترك فتتجدد الشاشة لحظياً بنمط الخط.
class _AgingTab extends StatelessWidget {
  final DiqqahDatabase db;

  const _AgingTab({required this.db});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: agingPresetIndex,
      builder: (context, index, _) {
        final thresholds = kAgingBucketPresets[index];
        return FutureBuilder<AgingReport>(
          // المفتاح بفوهج التهيئة — تغيّر الفهرس يعيد البناء من جديد.
          key: ValueKey<List<int>>(thresholds),
          future: db.agingReport(thresholds: thresholds),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final r = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const Text('فوهج الأعمار: '),
                      DropdownButton<int>(
                        value: index,
                        items: [
                          for (var i = 0;
                              i < kAgingBucketPresets.length;
                              i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(agingPresetLabel(
                                  kAgingBucketPresets[i])),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) saveAgingPreset(v);
                        },
                      ),
                      const Spacer(),
                      Text(
                        'الإجمالي: ${formatMinorAmount(r.totalMinor)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: r.parties.isEmpty
                      ? const Center(
                          child: Text('لا أعمار — لا فواتير آجلة مستحقة'))
                      : ListView(
                          children: [
                            // ترويسة الفوهج — بطول الفوهج + 2 دائماً
                            // (الفوهج + تجاوز آخر فوهة + الإجمالي).
                            ListTile(
                              dense: true,
                              title: const Text('الطرف',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                r.bucketLabels.join(' · '),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const Divider(height: 1),
                            for (final p in r.parties)
                              ListTile(
                                dense: true,
                                title: Text(p.partyName),
                                subtitle: Text(
                                  p.theyOweUs ? 'مدينة' : 'دائنة',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Text(
                                  formatMinorAmount(p.bucketMinor.fold(
                                      0, (a, b) => a + b)),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: const Text('مجموع الفوهة',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(r.bucketLabels.join(' · ')),
                              trailing: Text(
                                formatMinorAmount(r.totalMinor),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
