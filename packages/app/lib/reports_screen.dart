import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'aging_prefs.dart';
import 'item_images.dart';
import 'print_image_prefs.dart';
import 'periods_screen.dart';
import 'print_service.dart';
import 'drilldown.dart'
    show AccountStatementScreen, showItemSheet, showPartySheet;

/// تنسيق عرض المبلغ بوحداته الصغرى كما تُخزن — فواصل آلاف للقراءة فقط
/// (عرضاً حصراً: أرقام السيناريوهات المعروفة تُرى كما هي لا محوَّلة —
/// D-092 معروض).
String formatMinorAmount(int amount) {
  final sign = amount < 0 ? '-' : '';
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return sign + grouped;
}

/// شاشة التقارير اليومية — دفعة م1 (6-ب): واجهات الدفعة السادسة
/// (س-79..س-85). التقارير الست قراءات لحظية من المرحّل حصراً — لا جداول
/// تجميع ولا أرقام مخزنة (D-089)، والفترات والإقفال شاشة قائمة بذاتها
/// منها (س-85) بصلاحية الإقفال إفصاحاً بطبقة الواجهة (D-090).
class ReportsScreen extends StatelessWidget {
  final DiqqahDatabase db;

  const ReportsScreen({super.key, required this.db});

  void _open(BuildContext context, Widget target) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير اليومية')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.balance_outlined),
            title: const Text('ميزان المراجعة'),
            subtitle: const Text(
                'أرصدة الحسابات من المرحّل لحظة الطلب — ومجموعاه متوازنان (F-068)'),
            onTap: () => _open(context, _TrialBalanceView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('تقرير الصناديق'),
            subtitle: const Text(
                'رصيد كل صندوق بمعادلة الصندوق ذاتها — والمعطل بشارته لا يُخفى'),
            onTap: () => _open(context, _CashBoxesView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('الذمم المدينة والدائنة'),
            subtitle: const Text('صافي كل طرف — هم يدينون لنا / نحن مدينون لهم'),
            onTap: () => _open(context, _ReceivablesPayablesView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('تقرير المخزون'),
            subtitle: const Text(
                'الكمية والقيمة الدفترية لكل صنف — والمتوسط عرضاً حصراً'),
            onTap: () => _open(context, InventoryView(db: db)),
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('مبيعات وحركة الأصناف'),
            subtitle: const Text('بيع ومردود بيع بمدى تاريخ — والصافي مشتق لا مخزن'),
            onTap: () => _open(context, MovementView(db: db, sales: true)),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: const Text('تقرير المشتريات'),
            subtitle: const Text(
                'المستقل — شراء ومردود شراء بمدى تاريخ (وعد D-089، س-84)'),
            onTap: () => _open(context, MovementView(db: db, sales: false)),
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('الفترات والإقفال'),
            subtitle: const Text(
                'إقفال فترة وما فيها يثبّت إلى الأبد — والفك طارئ بسبب نصي إلزامي'),
            onTap: () => _open(context, PeriodsScreen(db: db)),
          ),
          // س-151/D-149 (دفعة 15): أعمار الذمم — أقرب ربح من دراسة
          // محضر الخبراء (س46/D-140): قراءة خالصة فوق الفواتير
          // المفتوحة والمصالحة المنجزة سلفاً، بفوهج قابلة للتهيئة.
          // البندان الجديدان خلف قائمة التقارير القائمة — نمو القائمة
          // بنهايتها فلا يُزاح بند معتمد من موضعه المختبر.
          ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: const Text('أعمار الذمم'),
            subtitle: const Text(
                'كل طرف بمبلغه المفتوح موزعاً على فترات التأخر عن الاستحقاق'),
            onTap: () => _open(context, _AgingView(db: db)),
          ),
          // س-152/D-150 (دفعة 15): دفتر اليومية — قيود المرحّل
          // بترتيب الزمن بأسطرها بفلاتر المدى والدفتر.
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('دفتر اليومية'),
            subtitle: const Text(
                'كل قيد بأسطره بترتيب الزمن — ومجموعاه متوازنان'),
            onTap: () => _open(context, _JournalBookView(db: db)),
          ),
        ],
      ),
    );
  }
}

/// عرض الحالة الجارية للقراءة — مؤشر انتظار بلا وعد مبكر (نمط الشاشات).
Widget _reportWait() => const Center(child: CircularProgressIndicator());

/// شريط «لا شيء بعد» الموحد — رسالة لا صمت (F-162 روحاً).
Widget _reportEmpty(String message) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );

/// قراءة بايتات صورة صنف للمطبوع — الغائب/الفاسد null فالنائب مكانه
/// (س-125) ولا يكسر الطباعة أبداً.
Future<Uint8List?> loadReportImageBytes(String? relativePath) async {
  final abs = ItemImagesStore.resolve(relativePath);
  if (abs == null || !File(abs).existsSync()) return null;
  try {
    return await File(abs).readAsBytes();
  } catch (_) {
    return null;
  }
}

/// زر الطباعة الموحد للتقارير (D-016، دفعة إغلاق النواة س37) — توليد
/// PDF بالقياس الافتراضي للتقارير (A4 عرضي، D-101 معروض) ومشاركته
/// بنافذة النظام، والفشل رسالة لا صمت.
///
/// س-128 (دفعة 10): صور الصفوف تمرر غير null حصراً حين مفتاح التقرير
/// مفعّل من الإعدادات (D-123) — والافتراضي معطل فلا قراءة ملفات أبداً.
Future<void> _printReportDoc(
  BuildContext context, {
  required String title,
  required List<String> columns,
  required List<List<String>> rows,
  List<(String, String)> footer = const [],
  List<Uint8List?>? rowImages,
  List<String>? rowLetters,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildDocumentPdf(
      title: title,
      headerPairs: const [],
      columns: columns,
      rows: rows,
      footerPairs: footer,
      rowLeadingImages: rowImages,
      rowPlaceholderLetters: rowLetters,
      format: resolvePageFormat(docKind: 'report'),
    );
    if (!context.mounted) return;
    await sharePdfBytes(bytes, '$title.pdf');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر توليد الطباعة — $e')),
    );
  }
}

/// زر التصدير الموحد للتقارير (F-166 — الدفعة 20) — CSV بترميز UTF-8
/// مع BOM وعربي سليم في Excel، وصورة للعرض الحالي بصفوفه ذاتها التي
/// تُطبع لا إعادة حساب (الفند الموثق: أرقام الملف تطابق الشاشة حرفاً).
/// والفشل رسالة لا صمت — نمط الطباعة ذاته.
Future<void> _exportReportCsv(
  BuildContext context, {
  required String title,
  required List<String> columns,
  required List<List<String>> rows,
  List<(String, String)> footer = const [],
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final csv = buildCsvSnapshot(
      title: title,
      columns: columns,
      rows: rows,
      footer: footer,
    );
    if (!context.mounted) return;
    await shareCsvBytes(csv, '$title.csv');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر توليد التصدير — $e')),
    );
  }
}

/// شريط زر الطباعة والتصدير فوق قائمة التقرير — ظاهر دائماً لا يختفي
/// بالتمرير.
///
/// F-166 (الدفعة 20): زر التصدير مطلوب `onCsv` في كل تقرير — required
/// هنا يجعل المصرّف يرفض أي شريط بلا تصدير فلا تقرير يبقى بلا زر CSV.
class _ReportActionsBar extends StatelessWidget {
  final VoidCallback onPrint;
  final VoidCallback onCsv;

  const _ReportActionsBar({required this.onPrint, required this.onCsv});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onCsv,
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('تصدير CSV'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onPrint,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('طباعة / PDF'),
            ),
          ],
        ),
      );
}

/// ميزان المراجعة (س-71/س-80): المجمعان يُعرضان كما هما فلا يُطمَر خلل
/// ولو كان مستحيلاً — والرصيد باتجاهه الطبيعي والعكسي يظهر كما هو.
///
/// س-146 (D-137، دفعة 13): النقر على الحساب يفتح كشف حسابه — «دفتر
/// الأستاذ» بقيوده بترتيب الزمن ورصيده التراكمي، ومجموعه يطابق صف
/// الميزان حصراً — بمبدأ س-143 «كل اسم يصير مدخلاً».
class _TrialBalanceView extends StatelessWidget {
  final DiqqahDatabase db;

  const _TrialBalanceView({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ميزان المراجعة')),
      body: FutureBuilder<TrialBalanceReport>(
        future: db.trialBalanceReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final report = snapshot.data!;
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة
          // 20): تجميع واحد فلا انحراف بين ما يُرى وما يُطبع وما يُصدَّر.
          const docColumns = ['الحساب', 'مدين', 'دائن', 'الرصيد'];
          final docRows = [
            for (final row in report.rows)
              [
                '${row.account.code} ${row.account.name}',
                formatMinorAmount(row.debitSumMinor),
                formatMinorAmount(row.creditSumMinor),
                formatMinorAmount(row.balanceMinor),
              ],
          ];
          final docFooter = <(String, String)>[
            ('مجموع المدين', formatMinorAmount(report.totalDebitMinor)),
            ('مجموع الدائن', formatMinorAmount(report.totalCreditMinor)),
            (
              'الحالة',
              report.isBalanced
                  ? 'الميزان متوازن ✓ (F-068)'
                  : 'الميزان غير متوازن — راجع فوراً!',
            ),
          ];
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        'مجموع المدين ${formatMinorAmount(report.totalDebitMinor)}'
                        ' — مجموع الدائن ${formatMinorAmount(report.totalCreditMinor)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.isBalanced
                            ? 'الميزان متوازن ✓ — مجموعا الجانبين متساويان (F-068)'
                            : 'الميزان غير متوازن — راجع فوراً!',
                        style: TextStyle(
                          color: report.isBalanced
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    _ReportActionsBar(
                      onPrint: () => _printReportDoc(
                        context,
                        title: 'ميزان المراجعة',
                        columns: docColumns,
                        rows: docRows,
                        footer: docFooter,
                      ),
                      onCsv: () => _exportReportCsv(
                        context,
                        title: 'ميزان المراجعة',
                        columns: docColumns,
                        rows: docRows,
                        footer: docFooter,
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final row in report.rows)
                            ListTile(
                              title: Text(
                                  '${row.account.code} ${row.account.name}'),
                              subtitle: Text(
                                  'مدين ${formatMinorAmount(row.debitSumMinor)}'
                                  ' · دائن ${formatMinorAmount(row.creditSumMinor)}'),
                              trailing: Text(
                                  'الرصيد ${formatMinorAmount(row.balanceMinor)}'),
                              // س-146/D-137: الحساب اسم يُقرأ فيصير مدخلاً
                              // — النقر يفتح كشف حسابه.
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AccountStatementScreen(
                                      db: db, accountId: row.account.id),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// تقرير الصناديق (س-72/س-81): الصندوق المعطل بشارة «معطل» ولا يُخفى —
/// الصدق أولاً.
class _CashBoxesView extends StatelessWidget {
  final DiqqahDatabase db;

  const _CashBoxesView({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير الصناديق')),
      body: FutureBuilder<List<CashBoxReportRow>>(
        future: db.cashBoxesReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return _reportEmpty('لا صناديق بعد');
          }
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20).
          const docColumns = [
            'الصندوق', 'الحساب', 'العملة', 'الحالة', 'الرصيد'
          ];
          final docRows = [
            for (final box in rows)
              [
                box.name,
                box.accountCode,
                box.currencyCode,
                box.isActive ? 'نشط' : 'معطل',
                formatMinorAmount(box.balanceBaseMinor),
              ],
          ];
          return Column(
            children: [
              _ReportActionsBar(
                onPrint: () => _printReportDoc(
                  context,
                  title: 'تقرير الصناديق',
                  columns: docColumns,
                  rows: docRows,
                ),
                onCsv: () => _exportReportCsv(
                  context,
                  title: 'تقرير الصناديق',
                  columns: docColumns,
                  rows: docRows,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final box in rows)
                      ListTile(
                        title: Text(box.name),
                        subtitle: Text('حساب ${box.accountCode}'
                            ' · ${box.currencyCode}'
                            '${box.isActive ? '' : ' — معطل'}'),
                        trailing:
                            Text(formatMinorAmount(box.balanceBaseMinor)),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// تقرير الذمم (س-73/س-81): الاتجاهان كما يفهمهما صاحب المحل — والصفر
/// لا ذمة فلا صف.
///
/// س-136 (D-130، دفعة 11): خيار «حسب النوع» أعلى التقرير بلفظ المالك
/// «في التقارير التي فيها أكثر من نوع يجب أن يوجد خيار: حسب النوع،
/// مثال على ذلك تقرير الذمم المدينة والدائنة، فأنا أريد المدينة ثم
/// الدائنة» — الكل بترتيب المدينة ثم الدائنة، والفلتر عرضٌ فوق القراءة
/// القائمة ذاتها فلا تغيير في القراءة ولا أرقامها. والقاعدة العامة
/// الموثقة: **كل تقرير فيه أكثر من نوع له خيار «حسب النوع»**.
class _ReceivablesPayablesView extends StatefulWidget {
  final DiqqahDatabase db;

  const _ReceivablesPayablesView({required this.db});

  @override
  State<_ReceivablesPayablesView> createState() =>
      _ReceivablesPayablesViewState();
}

class _ReceivablesPayablesViewState extends State<_ReceivablesPayablesView> {
  /// المستقبل مرة واحدة لعمر الحالة — درس السرد الكسول الموثق.
  late final Future<List<ReceivablesPayablesRow>> _data =
      widget.db.receivablesPayablesReport();

  /// قيمة الفلتر: null = الكل، true = مدينة (هم يدينون لنا)،
  /// false = دائنة (نحن مدينون لهم).
  bool? _kind;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الذمم المدينة والدائنة')),
      body: FutureBuilder<List<ReceivablesPayablesRow>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) return _reportWait();
          final all = snapshot.data!;
          if (all.isEmpty) {
            return _reportEmpty('لا ذمم — كل الحسابات مصفاة');
          }
          // الترتيب الافتراضي بلفظ المالك: المدينة ثم الدائنة — وكل
          // مجموعة بأسمائها.
          List<ReceivablesPayablesRow> rows;
          if (_kind == null) {
            rows = [
              ...all.where((r) =>
                  r.direction == PartyBalanceDirection.theyOweUs),
              ...all.where((r) =>
                  r.direction != PartyBalanceDirection.theyOweUs),
            ];
          } else {
            rows = [
              for (final r in all)
                if ((r.direction == PartyBalanceDirection.theyOweUs) ==
                    _kind)
                  r,
            ];
          }
          final kindLabel = _kind == null
              ? 'الذمم المدينة والدائنة'
              : (_kind! ? 'الذمم المدينة (هم يدينون لنا)' : 'الذمم الدائنة (نحن مدينون لهم)');
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة
          // 20): صفوف الفلتر المعروضة ذاتها لا إعادة قراءة ولا حساب.
          const docColumns = ['الطرف', 'الاتجاه', 'المبلغ'];
          final docRows = [
            for (final row in rows)
              [
                row.partyName,
                row.direction == PartyBalanceDirection.theyOweUs
                    ? 'هم يدينون لنا'
                    : 'نحن مدينون لهم',
                formatMinorAmount(row.amountMinor),
              ],
          ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<bool>(
                        initialValue: _kind,
                        decoration:
                            const InputDecoration(labelText: 'حسب النوع'),
                        items: const [
                          DropdownMenuItem<bool>(
                              value: null, child: Text('الكل')),
                          DropdownMenuItem<bool>(
                              value: true,
                              child: Text('المدينة — هم يدينون لنا')),
                          DropdownMenuItem<bool>(
                              value: false,
                              child: Text('الدائنة — نحن مدينون لهم')),
                        ],
                        onChanged: (value) =>
                            setState(() => _kind = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ReportActionsBar(
                      onPrint: () => _printReportDoc(
                        context,
                        title: kindLabel,
                        columns: docColumns,
                        rows: docRows,
                      ),
                      onCsv: () => _exportReportCsv(
                        context,
                        title: kindLabel,
                        columns: docColumns,
                        rows: docRows,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? _reportEmpty('لا ذمم في هذا النوع')
                    : ListView(
                        children: [
                          for (final row in rows)
                            ListTile(
                              title: Text(row.partyName),
                              subtitle: Text(row.direction ==
                                      PartyBalanceDirection.theyOweUs
                                  ? 'هم يدينون لنا'
                                  : 'نحن مدينون لهم'),
                              trailing:
                                  Text(formatMinorAmount(row.amountMinor)),
                              // س-147: الطرف اسم يُقرأ فيصير مدخلاً —
                              // النقر يفتح ورقته (بطاقة وفواتير وسندات وكشف).
                              onTap: () => showPartySheet(
                                  context,
                                  widget.db,
                                  row.partyId,
                                  row.partyName),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// تقرير أعمار الذمم (س-151/D-149 — دفعة 15): كل طرف بمبلغه المفتوح
/// موزعاً على فهرات التأخر — قراءة خالصة فوق محرك المصالحة المنجز
/// (D-140 روحاً من س46) بلا ترحيلة ولا حساب جديد.
///
/// الفوهج إعدادات لا كود (قرار الدراسة): قوائم جاهزة بقائمة منسدلة
/// محفوظة بمخزن الخيارات (نمط D-123)، والافتراض 30/60/90/120.
/// والفلتر «حسب النوع» بقاعدة D-130 الموثقة: الكل بترتيب المدينة ثم
/// الدائنة — وكل اسم يصير مدخلاً (D-135): النقر على الطرف يعرض
/// فواتيره المفتوحة بأيام تأخرها.
class _AgingView extends StatefulWidget {
  final DiqqahDatabase db;

  const _AgingView({required this.db});

  @override
  State<_AgingView> createState() => _AgingViewState();
}

class _AgingViewState extends State<_AgingView> {
  /// فلتر النوع بقاعدة D-130 — null الكل، sale مدينة، purchase دائنة.
  String? _kind;

  Future<AgingReport>? _future;

  static const Map<String, String> _kindLabels = {
    'sale': 'المدينة — فواتير البيع',
    'purchase': 'الدائنة — فواتير الشراء',
  };

  @override
  void initState() {
    super.initState();
    agingPresetIndex.addListener(_onPrefs);
    _reload();
  }

  @override
  void dispose() {
    agingPresetIndex.removeListener(_onPrefs);
    super.dispose();
  }

  /// تغيّر مخزن الفوهج يعيد القراءة بالقائمة الجديدة (درس السرد
  /// الكسول: المستقبل يُنشأ بأمر صريح هنا لا في build).
  void _onPrefs() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.db.agingReport(
        thresholds: agingThresholds,
        kindStorageValue: _kind,
      );
    });
  }

  String get _kindLabel => _kind == null
      ? 'أعمار الذمم'
      : 'أعمار الذمم — ${_kindLabels[_kind]!}';

  /// لسان صف الطرف — الفوهج غير الصفرية حصراً فلا صمت ولا ضجيج.
  String _partySubtitle(AgingPartyRow row, List<String> labels) {
    final parts = <String>[];
    for (var i = 0;
        i < row.bucketMinor.length && i < labels.length;
        i++) {
      if (row.bucketMinor[i] > 0) {
        parts.add(
            '${labels[i]}: ${formatMinorAmount(row.bucketMinor[i])}');
      }
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  /// أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20):
  /// تجميع واحد لصفوف العرض فما يُصدَّر هو المعروض حرفاً لا إعادة حساب.
  List<String> _agingColumns(AgingReport report) => [
        'الطرف',
        'الاتجاه',
        ...report.bucketLabels,
        'الإجمالي',
      ];

  List<List<String>> _agingRows(AgingReport report) => [
        for (final party in report.parties)
          [
            party.partyName,
            party.theyOweUs ? 'هم يدينون لنا' : 'نحن مدينون لهم',
            for (final amount in party.bucketMinor)
              amount == 0 ? '—' : formatMinorAmount(amount),
            formatMinorAmount(party.totalMinor),
          ],
      ];

  List<(String, String)> _agingFooter(AgingReport report) => [
        for (var i = 0; i < report.bucketLabels.length; i++)
          if (report.bucketTotalsMinor[i] > 0)
            (
              report.bucketLabels[i],
              formatMinorAmount(report.bucketTotalsMinor[i]),
            ),
        ('الإجمالي', formatMinorAmount(report.totalMinor)),
      ];

  Future<void> _print(AgingReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildDocumentPdf(
        title: _kindLabel,
        headerPairs: [
          ('فترات الأعمار', agingPresetLabel(report.thresholds)),
        ],
        columns: _agingColumns(report),
        rows: _agingRows(report),
        footerPairs: _agingFooter(report),
        format: resolvePageFormat(docKind: 'report'),
      );
      if (!context.mounted) return;
      await sharePdfBytes(bytes, 'أعمار الذمم.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  /// F-166 (الدفعة 20): تصدير صورة العرض — وفترات الأعمار تُلحق
  /// التذييل كي لا يضيع سياق القياس عن المستورد.
  Future<void> _csv(AgingReport report) {
    return _exportReportCsv(
      context,
      title: _kindLabel,
      columns: _agingColumns(report),
      rows: _agingRows(report),
      footer: [
        ('فترات الأعمار', agingPresetLabel(report.thresholds)),
        ..._agingFooter(report),
      ],
    );
  }

  /// س-135/D-135: اسم الطرف مدخل — الورقة تعرض فواتيره المفتوحة
  /// بأيام تأخرها فتُعرف الذمة تفصيلاً لا إجمالاً فقط.
  void _showPartyInvoices(AgingPartyRow party) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(party.partyName),
              subtitle: Text(party.theyOweUs
                  ? 'هم يدينون لنا — الفواتير المفتوحة'
                  : 'نحن مدينون لهم — الفواتير المفتوحة'),
            ),
            for (final inv in party.invoices)
              ListTile(
                title: Text('فاتورة ${inv.number}'),
                subtitle: Text(
                    'الاستحقاق: ${inv.dueDate ?? inv.invoiceDate}'
                    ' · ${inv.daysOver < 0
                        ? 'غير مستحق'
                        : inv.daysOver == 0
                            ? 'استحقاق اليوم'
                            : 'متأخر ${inv.daysOver} يوماً'}'),
                trailing: Text(formatMinorAmount(inv.remainingBaseMinor)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أعمار الذمم')),
      body: FutureBuilder<AgingReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) return _reportWait();
          final report = snapshot.data!;
          if (report.parties.isEmpty) {
            return _reportEmpty('لا ذمم مفتوحة — كل الفواتير مصفاة');
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _kind,
                        decoration:
                            const InputDecoration(labelText: 'حسب النوع'),
                        items: const [
                          DropdownMenuItem<String>(
                              value: null, child: Text('الكل')),
                          DropdownMenuItem<String>(
                              value: 'sale', child: Text('المدينة')),
                          DropdownMenuItem<String>(
                              value: 'purchase', child: Text('الدائنة')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _kind = value;
                            _reload();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: agingPresetIndex.value,
                        decoration: const InputDecoration(
                            labelText: 'فترات الأعمار'),
                        items: [
                          for (var i = 0;
                              i < kAgingBucketPresets.length;
                              i++)
                            DropdownMenuItem<int>(
                                value: i,
                                child: Text(
                                    agingPresetLabel(kAgingBucketPresets[i]))),
                        ],
                        // الفوهج إعدادات لا كود (قرار الدراسة) —
                        // الاختيار يُحفظ فيبقى لعجله، والمستمع
                        // يعيد القراءة بالقائمة الجديدة.
                        onChanged: (value) {
                          if (value == null) return;
                          saveAgingPreset(value);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ReportActionsBar(
                      onPrint: () => _print(report),
                      onCsv: () => _csv(report),
                    ),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'الإجمالي ${formatMinorAmount(report.totalMinor)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final party in report.parties)
                      ListTile(
                        title: Text(party.partyName),
                        subtitle: Text(
                            '${party.theyOweUs ? 'هم يدينون لنا' : 'نحن مدينون لهم'}'
                            ' — ${_partySubtitle(party, report.bucketLabels)}'),
                        trailing:
                            Text(formatMinorAmount(party.totalMinor)),
                        // كل اسم يصير مدخلاً (D-135): فواتير الطرف
                        // المفتوحة بأيام تأخرها.
                        onTap: () => _showPartyInvoices(party),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// دفتر اليومية (س-152/D-150 — دفعة 15): قيود المرحّل بترتيب الزمن
/// بأسطرها — قراءة خالصة نمط كشف الحساب (D-137) بفلاتر المدى والدفتر
/// ومجموعا الجانبين ضابط توازنهما روح F-068.
class _JournalBookView extends StatefulWidget {
  final DiqqahDatabase db;

  const _JournalBookView({required this.db});

  @override
  State<_JournalBookView> createState() => _JournalBookViewState();
}

class _JournalBookViewState extends State<_JournalBookView> {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();

  /// فلتر الدفتر — null الكل، وإلا أحد الأنواع الخمسة (D-076).
  String? _journalKind;

  Future<JournalBookReport>? _future;

  static const Map<String, String> _journalKindLabels = {
    'sales': 'المبيعات',
    'purchase': 'المشتريات',
    'cash': 'الصندوق',
    'stock': 'المخزون',
    'general': 'قيد عام',
  };

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = widget.db.journalBookReport(
        fromText: _from.text.trim(),
        toText: _to.text.trim(),
        journalKind: _journalKind,
      );
    });
  }

  /// أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20).
  static const _journalColumns = [
    'التاريخ',
    'القيد',
    'الدفتر',
    'الحساب',
    'الطرف',
    'مدين',
    'دائن',
  ];

  List<List<String>> _journalRows(JournalBookReport report) => [
        for (final entry in report.entries)
          for (final line in entry.lines)
            [
              entry.moveDate,
              entry.moveNumber,
              entry.journalName,
              '${line.accountCode} ${line.accountName}',
              line.partyName ?? '—',
              formatMinorAmount(line.debitMinor),
              formatMinorAmount(line.creditMinor),
            ],
      ];

  List<(String, String)> _journalFooter(JournalBookReport report) => [
        ('مجموع المدين', formatMinorAmount(report.totalDebitMinor)),
        ('مجموع الدائن', formatMinorAmount(report.totalCreditMinor)),
        (
          'الحالة',
          report.isBalanced
              ? 'المجموعان متوازنان ✓ (F-068)'
              : 'غير متوازن — راجع فوراً!',
        ),
      ];

  Future<void> _print(JournalBookReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildDocumentPdf(
        title: 'دفتر اليومية',
        headerPairs: const [],
        columns: _journalColumns,
        rows: _journalRows(report),
        footerPairs: _journalFooter(report),
        format: resolvePageFormat(docKind: 'report'),
      );
      if (!context.mounted) return;
      await sharePdfBytes(bytes, 'دفتر اليومية.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  /// F-166 (الدفعة 20): تصدير صورة العرض الحالي بصفوف الطباعة ذاتها.
  Future<void> _csv(JournalBookReport report) {
    return _exportReportCsv(
      context,
      title: 'دفتر اليومية',
      columns: _journalColumns,
      rows: _journalRows(report),
      footer: _journalFooter(report),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دفتر اليومية')),
      body: FutureBuilder<JournalBookReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // المدى الفاسد يُعرض بلسان المدقق من الـFutureBuilder —
            // لا صمت ولا انهيار (D-077: المدقق حرس أول).
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) return _reportWait();
          final report = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _from,
                        decoration: const InputDecoration(
                            labelText: 'من تاريخ (سنة-شهر-يوم)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _to,
                        decoration: const InputDecoration(
                            labelText: 'إلى تاريخ (سنة-شهر-يوم)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _journalKind,
                        decoration:
                            const InputDecoration(labelText: 'الدفتر'),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('الكل')),
                          for (final e in _journalKindLabels.entries)
                            DropdownMenuItem<String>(
                                value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _journalKind = value;
                            _reload();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('عرض'),
                    ),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        'مجموع المدين ${formatMinorAmount(report.totalDebitMinor)}'
                        ' — مجموع الدائن ${formatMinorAmount(report.totalCreditMinor)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _csv(report),
                            icon: const Icon(Icons.table_view_outlined),
                            label: const Text('تصدير CSV'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _print(report),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('طباعة / PDF'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: report.entries.isEmpty
                    ? _reportEmpty('لا قيود مرحّلة في هذا المدى')
                    : ListView(
                        children: [
                          for (final entry in report.entries)
                            Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: Column(
                                children: [
                                  ListTile(
                                    title: Text(
                                        '${entry.moveDate} · قيد ${entry.moveNumber}'
                                        ' · ${entry.journalName}'),
                                    subtitle: entry.narration == null ||
                                            entry.narration!.isEmpty
                                        ? null
                                        : Text(entry.narration!),
                                    dense: true,
                                  ),
                                  for (final line in entry.lines)
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                          '${line.accountCode} ${line.accountName}'),
                                      subtitle: line.partyName == null
                                          ? null
                                          : Text('الطرف: ${line.partyName}'),
                                      trailing: Text(
                                          'مدين ${formatMinorAmount(line.debitMinor)}'
                                          ' · دائن ${formatMinorAmount(line.creditMinor)}'),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// تقرير المخزون (س-74/س-82): الكمية والقيمة من السجل والمتوسط عرضاً
/// حصراً بالرسة المعتمدة.
///
/// س-128 (دفعة 10/D-118): عمود صورة في الشاشة والمطبوع — بمفتاحه
/// المستقل من الإعدادات (D-123، افتراضه معطل) والنائب البصري لمن بلا
/// صورة (س-125/D-122).
/// س-144/س-145 (دفعة 13/D-136): اسم الصنف في أي صف مدخلاً — النقر
/// يفتح ورقة الصنف — والعزل على الصنف الواحد (رصيده) عرضٌ مفلتر لا
/// حساب جديد.
/// درس السرد الموثق (علّة CI 2026-10-29 س23) بوجهه المستقبلي: المستقبل
/// يُنشأ مرة واحدة لعمر الحالة لا في build — إنشاؤه في build يعيد
/// FutureBuilder الانتظار عند كل إطار فيحلّق الجلب والتحديث بلا نهاية
/// ويحرق pumpAndSettle بمهلته الكاملة.
class InventoryView extends StatefulWidget {
  final DiqqahDatabase db;

  /// س-145/D-136: العزل على الصنف الواحد — null يعني التقرير كاملاً.
  final int? isolatedItemId;
  final String? isolatedItemName;

  const InventoryView({
    super.key,
    required this.db,
    this.isolatedItemId,
    this.isolatedItemName,
  });

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  /// المستقبل مرة واحدة — صفوف التقرير مع الأصناف لمسارات صورها.
  late final Future<List<dynamic>> _data = Future.wait([
    widget.db.inventoryReport(),
    widget.db.select(widget.db.items).get(),
  ]);

  @override
  Widget build(BuildContext context) {
    final isolated = widget.isolatedItemId;
    return Scaffold(
      appBar: AppBar(
          title: Text(isolated == null
              ? 'تقرير المخزون'
              : 'رصيد ${widget.isolatedItemName ?? ''} في المخزون')),
      body: FutureBuilder<List<dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final rows = snapshot.data![0] as List<InventoryReportRow>;
          final items = snapshot.data![1] as List<Item>;
          final itemById = {for (final it in items) it.id: it};
          final withImages = printImageInventory.value;
          // س-145/D-136: العزل عرضٌ مفلتر فوق القراءة ذاتها — لا حساب جديد.
          final visibleRows = isolated == null
              ? rows
              : [
                  for (final row in rows)
                    if (row.itemId == isolated) row,
                ];
          if (visibleRows.isEmpty) {
            return _reportEmpty('لا مخزون بعد');
          }
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20).
          const docColumns = [
            'الصنف', 'المستودع', 'الكمية', 'القيمة', 'المتوسط'
          ];
          final docRows = [
            for (final row in visibleRows)
              [
                '${row.sku} ${row.name}',
                row.warehouseName ?? 'غير محدد',
                '${row.qtyBase}',
                formatMinorAmount(row.totalValueMinor),
                row.avgCostBaseMinor == null
                    ? '—'
                    : formatMinorAmount(row.avgCostBaseMinor!),
              ],
          ];
          return Column(
            children: [
              _ReportActionsBar(
                onPrint: () async {
                  // الصور تُقرأ حصراً بمفتاح مفعّل (D-123) — والافتراضي
                  // معطل في كل التقريرات فلا قراءة ملفات بلا سبب.
                  List<Uint8List?>? rowImages;
                  List<String>? rowLetters;
                  if (withImages) {
                    rowImages = [
                      for (final row in visibleRows)
                        await loadReportImageBytes(
                            itemById[row.itemId]?.imageFile),
                    ];
                    rowLetters = [
                      for (final row in visibleRows)
                        itemById[row.itemId]?.name ?? 'صنف',
                    ];
                  }
                  if (!context.mounted) return;
                  await _printReportDoc(
                    context,
                    title: isolated == null
                        ? 'تقرير المخزون'
                        : 'رصيد ${widget.isolatedItemName ?? ''} في المخزون',
                    columns: docColumns,
                    rows: docRows,
                    rowImages: rowImages,
                    rowLetters: rowLetters,
                  );
                },
                onCsv: () => _exportReportCsv(
                  context,
                  title: isolated == null
                      ? 'تقرير المخزون'
                      : 'رصيد ${widget.isolatedItemName ?? ''} في المخزون',
                  columns: docColumns,
                  rows: docRows,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final row in visibleRows)
                      ListTile(
                        leading: withImages
                            ? ItemImageBox(
                                imagePath: itemById[row.itemId]?.imageThumb,
                                itemName: row.name,
                                size: 44,
                              )
                            : null,
                        title: Text('${row.sku} ${row.name}'),
                        subtitle: Text(
                            'المستودع: ${row.warehouseName ?? 'غير محدد'}'
                            ' · المتوسط: ${row.avgCostBaseMinor == null ? '—' : formatMinorAmount(row.avgCostBaseMinor!)}'),
                        trailing: Text(
                            '${row.qtyBase} × ${formatMinorAmount(row.totalValueMinor)}'),
                        // س-144/D-136: اسم الصنف مدخلاً — النقر يفتح ورقته.
                        onTap: () => showItemSheet(context, widget.db,
                            row.itemId, '${row.sku} ${row.name}'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// صورة عرض موحدة لحركة صنف — تُبنى من صفوف البيع أو الشراء فتُقرأ
/// الدفعتان بلسان واحد. س-128: الصورة ترويسة تأكيد أعلى الكشف —
/// تنظر إلى وجه الصنف قبل أرقامه، بمفتاحها المستقل (D-123).
class _MovementDisplay {
  final String title;
  final String subtitle;
  final String trailing;
  final int itemId;
  final String name;

  const _MovementDisplay(
    this.title,
    this.subtitle,
    this.trailing, {
    required this.itemId,
    required this.name,
  });
}

/// شاشة الحركة بمدى تاريخ (س-75/س-83 للمبيعات وس-84 للمشتريات): المدى
/// يُدقق قبل لمس القاعدة أصلاً، والمدى الغائب يعطي رسالة لا صمت.
///
/// س-144/س-145 (دفعة 13/D-136): اسم الصنف في أي صف مدخلاً — النقر
/// يفتح ورقة الصنف — والعزل على الصنف الواحد (مبيعاته/مشترياته)
/// بمدى D-113 الافتراضي القابل للتعديل — عرضٌ مفلتر لا حساب جديد.
class MovementView extends StatefulWidget {
  final DiqqahDatabase db;

  /// صحيح: مبيعات وحركة الأصناف — كاذب: تقرير المشتريات المستقل.
  final bool sales;

  /// س-145/D-136: العزل على الصنف الواحد — null يعني التقرير كاملاً.
  final int? isolatedItemId;
  final String? isolatedItemName;

  const MovementView({
    super.key,
    required this.db,
    required this.sales,
    this.isolatedItemId,
    this.isolatedItemName,
  });

  @override
  State<MovementView> createState() => _MovementViewState();
}

class _MovementViewState extends State<MovementView> {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  String? _error;
  List<_MovementDisplay>? _rows;

  /// أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20).
  static const _movementColumns = ['الصنف', 'التفصيل', 'الصافي'];

  /// صفوف العرض ذاتها للطباعة والتصدير — تجميع واحد فلا انحراف.
  List<List<String>> _movementRows() => [
        for (final row in _rows!) [row.title, row.subtitle, row.trailing],
      ];

  /// خريطة الأصناف لمسارات صورها (س-128) — تُحمّل مع كل عرض.
  Map<int, Item> _itemById = {};

  String? _thumbPathOf(int itemId) => _itemById[itemId]?.imageThumb;

  String? _filePathOf(int itemId) => _itemById[itemId]?.imageFile;

  @override
  void initState() {
    super.initState();
    _fillDefaultRange();
  }

  /// س-118 (D-113): افتراضيات المدى بلفظ المالك «اجعل "من" تاريخ أول
  /// العام الحالي أو تاريخ أول المدة المحدد إن لم يكن هو بداية العام،
  /// واجعل "إلى" تاريخ اليوم الحالي» — «من» أول السنة أو أول مستند
  /// مرحّل أيهما أحدث (earliestDocumentDate قراءة خالصة نمط D-088)،
  /// و«إلى» اليوم — وكلاهما قابل للتعديل اليدوي.
  Future<void> _fillDefaultRange() async {
    final earliest = await widget.db.earliestDocumentDate();
    if (!mounted) return;
    final jan1 = '${DateTime.now().year}-01-01';
    final from =
        (earliest != null && earliest.compareTo(jan1) > 0) ? earliest : jan1;
    setState(() {
      _from.text = from;
      _to.text = todayIsoDate();
    });
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _rows = null;
    });
    try {
      final items = await widget.db.select(widget.db.items).get();
      final itemById = {for (final it in items) it.id: it};
      _itemById = itemById;
      final List<_MovementDisplay> out;
      if (widget.sales) {
        final rows = await widget.db.salesMovementReport(
          fromText: _from.text.trim(),
          toText: _to.text.trim(),
        );
        out = [
          for (final r in rows)
            _MovementDisplay(
              '${r.sku} ${r.name}',
              'بيع ${r.qtySoldBase} × ${formatMinorAmount(r.salesValueBaseMinor)}'
                  ' · مردود ${r.qtyReturnedBase} × ${formatMinorAmount(r.returnsValueBaseMinor)}',
              'الصافي ${r.netQtyBase} × ${formatMinorAmount(r.netValueBaseMinor)}',
              itemId: r.itemId,
              name: itemById[r.itemId]?.name ?? r.name,
            ),
        ];
      } else {
        final rows = await widget.db.purchasesMovementReport(
          fromText: _from.text.trim(),
          toText: _to.text.trim(),
        );
        out = [
          for (final r in rows)
            _MovementDisplay(
              '${r.sku} ${r.name}',
              'شراء ${r.qtyPurchasedBase} × ${formatMinorAmount(r.purchasesValueBaseMinor)}'
                  ' · مردود ${r.qtyReturnedBase} × ${formatMinorAmount(r.returnsValueBaseMinor)}',
              'الصافي ${r.netQtyBase} × ${formatMinorAmount(r.netValueBaseMinor)}',
              itemId: r.itemId,
              name: itemById[r.itemId]?.name ?? r.name,
            ),
        ];
      }
      if (!mounted) return;
      // س-145/D-136: العزل على الصنف الواحد — عرضٌ مفلتر فوق القراءة
      // ذاتها فلا تتغير أرقام القراءة بحال.
      final isolated = widget.isolatedItemId;
      final visible = isolated == null
          ? out
          : [
              for (final row in out)
                if (row.itemId == isolated) row,
            ];
      setState(() => _rows = visible);
    } on ReportValidationException catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = e.errors.map(describeReportValidationError).join('؛ '));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isolatedItemId == null
        ? (widget.sales ? 'مبيعات وحركة الأصناف' : 'تقرير المشتريات')
        : (widget.sales
            ? 'مبيعات ${widget.isolatedItemName ?? ''}'
            : 'مشتريات ${widget.isolatedItemName ?? ''}');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _from,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                            labelText: 'من (YYYY-MM-DD)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _to,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                            labelText: 'إلى (YYYY-MM-DD)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _run, child: const Text('عرض')),
                if (_rows != null)
                  _ReportActionsBar(
                    onPrint: () async {
                      // س-128: صور الحركة بمفتاحها المستقل (D-123) —
                      // الافتراضي معطل فلا قراءة ملفات بلا مفتاح.
                      List<Uint8List?>? rowImages;
                      List<String>? rowLetters;
                      if (printImageMovement.value) {
                        rowImages = [
                          for (final row in _rows!)
                            await loadReportImageBytes(
                                _filePathOf(row.itemId)),
                        ];
                        rowLetters = [
                          for (final row in _rows!) row.name,
                        ];
                      }
                      if (!context.mounted) return;
                      await _printReportDoc(
                        context,
                        title: title,
                        columns: _movementColumns,
                        rows: _movementRows(),
                        rowImages: rowImages,
                        rowLetters: rowLetters,
                      );
                    },
                    onCsv: () => _exportReportCsv(
                      context,
                      title: title,
                      columns: _movementColumns,
                      rows: _movementRows(),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _rows == null
                ? const Center(child: Text('أدخل المدى ثم اضغط «عرض»'))
                : _rows!.isEmpty
                    ? _reportEmpty('لا حركة في هذا المدى')
                    : ListView(
                        children: [
                          for (final row in _rows!)
                            ListTile(
                              leading: printImageMovement.value
                                  ? ItemImageBox(
                                      imagePath: _thumbPathOf(row.itemId),
                                      itemName: row.name,
                                      size: 44,
                                    )
                                  : null,
                              title: Text(row.title),
                              subtitle: Text(row.subtitle),
                              trailing: Text(row.trailing),
                              // س-144/D-136: اسم الصنف مدخلاً — النقر
                              // يفتح ورقة الصنف من مواضعها الخمسة.
                              onTap: () => showItemSheet(
                                  context, widget.db, row.itemId, row.name),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
