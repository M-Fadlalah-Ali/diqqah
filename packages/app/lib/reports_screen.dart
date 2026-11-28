import 'dart:async' show Timer;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'aging_prefs.dart';
import 'app_theme.dart' show diqqahLanesOf;
import 'item_images.dart';
import 'print_image_prefs.dart';
import 'periods_screen.dart';
import 'print_service.dart';
import 'dq_log.dart';
import 'date_picker.dart';
import 'drilldown.dart'
    show AccountStatementScreen, showItemSheet, showPartySheet;
import 'adaptive.dart';
import 'report_table.dart';
import 'l10n/app_strings.dart';

/// م09 تنظيم التقارير (س205 — الدفعة الثالثة من فحص الواجهات وفق M3
/// بأمر المالك «تابع في م06 التكيفي ثم بقية الرابعة»): القائمة كانت
/// سطراً واحداً طويلاً نما بنهايته حتى ثلاثة عشر بنداً فغابت الخريطة
/// الذهنية — فصارت خمسة أقسام دلالية بترويساتها (القوائم المالية
/// والدفاتر والمطابقة والصناديق والذمم والمخزون والحركة والإدارة)
/// وبنودها بلسانها وأيقوناتها وأهدافها كما كانت حرفاً.
/// **وإعادة الترتيب هي مهمة الدفعة بحدودها**: لا بند محذوف ولا
/// شاشة جديدة ولا لسان متغيّر — ترويسةُ قسمٍ فوق بنوده لا غير.
Widget _reportsSectionHeader(BuildContext context, String title) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );

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
class ReportsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const ReportsScreen({super.key, required this.db});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  /// س227 (المرحلة صفر د4 من خارطة طريق التقرير الاستشاري — بأمر
  /// المالك «ابدأ التنفيذ»): صلاحية القوائم المالية لصاحب الجلسة —
  /// قراءة لحظية واحدة عند الفتح بنمط شاشة المستخدمين (لا تدفق حي
  /// ولا مؤقتات — درس CI)، وفراغها «قيد التحميل» فالبنان مخفيان حتى
  /// يجيب الدور (الفشل المغلق: لا كشف قبل صلاحية).
  RolePermissions? _perms;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final session = await widget.db.currentUser();
    RolePermissions? perms;
    if (session != null) {
      final role = await widget.db.roleOf(session);
      if (role != null) perms = RolePermissions(role.permissions);
    }
    if (!mounted) return;
    setState(() => _perms = perms);
  }

  /// حارسا المجال معاً (التقارير + البوابة الفرعية) — أمين المستودع
  /// الافتراضي بلاها («بلا نقود باتاً» — تقارير المخزون حصراً)، وما
  /// سواه يراها، والنجمة تشملها.
  bool get _canSeeFinancials =>
      _perms != null && roleCanSeeFinancialReports(_perms!);

  void _open(BuildContext context, Widget target) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.dailyReportsTitle)),
      // م06 التكيفي لويندوز (س205): المحتوى يتوسّط بعرضه الأقصى على
      // العريض والضيّق بهامشه الأساسي كما كان حرفاً.
      body: ListView(
        padding: EdgeInsets.symmetric(
            horizontal: diqqahAdaptiveHorizontalMargin(context)),
        children: [
          _reportsSectionHeader(context, S.financialStatementsTitle),
          ListTile(
            leading: const Icon(Icons.balance_outlined),
            title: const Text(S.trialBalanceTitle),
            subtitle: const Text(
                S.trialBalanceDesc),
            onTap: () => _open(context, _TrialBalanceView(db: widget.db)),
          ),
          // الدفعة 33 (عاشرة م2): القوائم المالية الأساسية F-096 من
          // أنواع الحسابات و07 §1.6 — قائمة الدخل بمدى والميزانية
          // العمومية إلى تاريخ.
          // س227 (المرحلة صفر د4): القائمتان خلف البوابة الفرعية
          // reports.financials — يخفيان عمن لا يملكها (أمين المستودع
          // الافتراضي: تقارير المخزون حصراً) ويراهما من يملكها،
          // وبقية أقسام التقارير بوحدة التقارير العامة كما كانت.
          if (_canSeeFinancials) ...[
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text(S.incomeStatementTitle),
              subtitle: const Text(
                  S.incomeStatementDesc),
              onTap: () =>
                  _open(context, IncomeStatementView(db: widget.db)),
            ),
            ListTile(
              leading: const Icon(Icons.balance_outlined),
              title: const Text(S.balanceSheetTitle),
              subtitle: const Text(
                  S.balanceSheetDesc),
              onTap: () =>
                  _open(context, BalanceSheetView(db: widget.db)),
            ),
          ],
          _reportsSectionHeader(context, S.booksMatchingTitle),
          // س-152/D-150 (دفعة 15): دفتر اليومية — قيود المرحّل
          // بترتيب الزمن بأسطرها بفلاتر المدى والدفتر.
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text(S.journalBookTitle),
            subtitle: const Text(
                S.journalBookDesc),
            onTap: () => _open(context, _JournalBookView(db: widget.db)),
          ),
          // الدفعة 31 (ثامنة م2): ربط المخزون بالدفتر بصرياً — ثابت
          // المطابقة D-067/F-178 معروض بالأرقام لا كلاماً (07 §3.1).
          ListTile(
            leading: const Icon(Icons.rule_outlined),
            title: const Text(S.stockLedgerMatchTitle),
            subtitle: const Text(
                S.stockLedgerMatchDesc),
            onTap: () =>
                _open(context, LedgerReconView(db: widget.db)),
          ),
          _reportsSectionHeader(context, S.boxesAndReceivablesTitle),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text(S.boxesReportTitle),
            subtitle: const Text(
                S.boxesReportDesc),
            onTap: () => _open(context, _CashBoxesView(db: widget.db)),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text(S.receivablesPayablesTitle),
            subtitle: const Text(S.receivablesPayablesDesc),
            onTap: () => _open(context, _ReceivablesPayablesView(db: widget.db)),
          ),
          // س-151/D-149 (دفعة 15): أعمار الذمم — أقرب ربح من دراسة
          // محضر الخبراء (س46/D-140): قراءة خالصة فوق الفواتير
          // المفتوحة والمصالحة المنجزة سلفاً، بفوهج قابلة للتهيئة.
          // موضع البند انتقل بقسمه بتنظيم م09 (س205) واللسان والهدف كما كانا.
          ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: const Text(S.agingTitle),
            subtitle: const Text(
                S.agingDesc),
            onTap: () => _open(context, _AgingView(db: widget.db)),
          ),
          // الدفعة 34 (F-124، D-194): مراكز العملات — كل عملة حية
          // بصناديقها وفواتيرها المفتوحة ومكافئها الأساسي المخزن
          // وآخر سعر مسجل — القيم المخزنة حصراً لا حساب صرف جديد.
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text(S.currencyCentersTitle),
            subtitle: const Text(
                S.currencyCentersDesc),
            onTap: () => _open(context, _CurrencyPositionsView(db: widget.db)),
          ),
          _reportsSectionHeader(context, S.stockAndMovementTitle),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text(S.stockReportTitle),
            subtitle: const Text(
                S.stockReportDesc),
            onTap: () => _open(context, InventoryView(db: widget.db)),
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text(S.itemSalesMovementTitle),
            subtitle: const Text(S.itemSalesMovementDesc),
            onTap: () =>
                _open(context, MovementView(db: widget.db, sales: true)),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: const Text(S.purchasesReportTitle),
            subtitle: const Text(
                S.purchasesReportDesc),
            onTap: () =>
                _open(context, MovementView(db: widget.db, sales: false)),
          ),
          _reportsSectionHeader(context, S.managementTitle),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text(S.periodsClosingTitle),
            subtitle: const Text(
                S.periodsClosingDesc),
            onTap: () => _open(context, PeriodsScreen(db: widget.db)),
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
  required DiqqahDatabase db,
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
      db: db,
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
      SnackBar(content: Text(S.printFailed(e, dqTag(e)))),
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
      SnackBar(content: Text(S.exportFailed(e, dqTag(e)))),
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
              label: const Text(S.exportCsv),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onPrint,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text(S.printOrPdf),
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
      appBar: AppBar(title: const Text(S.trialBalanceTitle)),
      body: FutureBuilder<TrialBalanceReport>(
        future: db.trialBalanceReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final report = snapshot.data!;
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة
          // 20): تجميع واحد فلا انحراف بين ما يُرى وما يُطبع وما يُصدَّر.
          const docColumns = [S.accountLabel, S.debitLabel, S.creditLabel, S.balanceLabel];
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
            (S.totalDebit, formatMinorAmount(report.totalDebitMinor)),
            (S.totalCredit, formatMinorAmount(report.totalCreditMinor)),
            (
              S.statusLabel,
              report.isBalanced
                  ? S.trialBalanced
                  : S.trialNotBalanced,
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
                        S.totalsDebitCredit(formatMinorAmount(report.totalDebitMinor), formatMinorAmount(report.totalCreditMinor)),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.isBalanced
                            ? S.trialBalancedFull
                            : S.trialNotBalanced,
                        style: TextStyle(
                          color: report.isBalanced
                              ? diqqahLanesOf(context).positive.fg
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
                        db: db,
                        context,
                        title: S.trialBalanceTitle,
                        columns: docColumns,
                        rows: docRows,
                        footer: docFooter,
                      ),
                      onCsv: () => _exportReportCsv(
                        context,
                        title: S.trialBalanceTitle,
                        columns: docColumns,
                        rows: docRows,
                        footer: docFooter,
                      ),
                    ),
                    // م07 جداول التقارير (س205): صفوف الميزان أعمدةً
                    // بترويسة منسجمة — وخلاياها سلاسل صفوف المستند ذاتها
                    // (عرف F-166) ونقر الصف بعرفه القائم (س-146).
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.symmetric(
                            horizontal:
                                diqqahAdaptiveHorizontalMargin(context)),
                        children: [
                          DiqqahReportTable(
                            columns: docColumns,
                            rows: docRows,
                            numericColumns: const {1, 2, 3},
                            onRowTap: (index) {
                              final row = report.rows[index];
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AccountStatementScreen(
                                      db: db, accountId: row.account.id),
                                ),
                              );
                            },
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
      appBar: AppBar(title: const Text(S.boxesReportTitle)),
      body: FutureBuilder<List<CashBoxReportRow>>(
        future: db.cashBoxesReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return _reportEmpty(S.noBoxesYet);
          }
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20).
          const docColumns = [
            S.boxLabel, S.accountLabel, S.currencyLabel, S.statusLabel, S.balanceLabel
          ];
          final docRows = [
            for (final box in rows)
              [
                box.name,
                box.accountCode,
                box.currencyCode,
                box.isActive ? S.activeLabel : S.inactiveLabel,
                formatMinorAmount(box.balanceBaseMinor),
              ],
          ];
          return Column(
            children: [
              _ReportActionsBar(
                onPrint: () => _printReportDoc(
                  db: db,
                  context,
                  title: S.boxesReportTitle,
                  columns: docColumns,
                  rows: docRows,
                ),
                onCsv: () => _exportReportCsv(
                  context,
                  title: S.boxesReportTitle,
                  columns: docColumns,
                  rows: docRows,
                ),
              ),
              // م07 (س205): صفوف الصناديق أعمدةً — وخلاياها سلاسل
              // صفوف المستند ذاتها (عرف F-166) فالحالة ظاهرة بعمودها.
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                      horizontal: diqqahAdaptiveHorizontalMargin(context)),
                  children: [
                    DiqqahReportTable(
                      columns: docColumns,
                      rows: docRows,
                      numericColumns: const {4},
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

/// تقرير الذمم (س-73/س-81): الاتجاهان كما يفهمهما صاحب المنشأة — والصفر
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
      appBar: AppBar(title: const Text(S.receivablesPayablesTitle)),
      body: FutureBuilder<List<ReceivablesPayablesRow>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) return _reportWait();
          final all = snapshot.data!;
          if (all.isEmpty) {
            return _reportEmpty(S.noReceivables);
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
              ? S.receivablesPayablesTitle
              : (_kind! ? S.receivablesSide : S.payablesSide);
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة
          // 20): صفوف الفلتر المعروضة ذاتها لا إعادة قراءة ولا حساب.
          const docColumns = [S.partyLabel, S.directionLabel, S.amountLabel];
          final docRows = [
            for (final row in rows)
              [
                row.partyName,
                row.direction == PartyBalanceDirection.theyOweUs
                    ? S.theyOweUs
                    : S.weOweThem,
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
                            const InputDecoration(labelText: S.byTypeLabel),
                        items: const [
                          DropdownMenuItem<bool>(
                              value: null, child: Text(S.allLabel)),
                          DropdownMenuItem<bool>(
                              value: true,
                              child: Text(S.receivableTypeSide)),
                          DropdownMenuItem<bool>(
                              value: false,
                              child: Text(S.payableTypeSide)),
                        ],
                        onChanged: (value) =>
                            setState(() => _kind = value),
                      ),
                    ),
                  ],
                ),
              ),
              // F-166 (الدفعة 20): شريط الأزرار سطرٌ مستقل أسفل الفلاتر —
              // عرض الزرين لا يضيق القائمة المنسدلة تحت حدّها الأدنى
              // (درس جولة 182: تجاوز 89px بحشرتها في الصف نفسه).
              _ReportActionsBar(
                onPrint: () => _printReportDoc(
                  db: widget.db,
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
              Expanded(
                child: rows.isEmpty
                    ? _reportEmpty(S.noReceivablesOfType)
                    // م07 (س205): صفوف الذمم أعمدةً — الطرف والاتجاه
                    // والمبلغ بعمودها، ونقر الصف بعرفه القائم (س-147).
                    : ListView(
                        padding: EdgeInsets.symmetric(
                            horizontal:
                                diqqahAdaptiveHorizontalMargin(context)),
                        children: [
                          DiqqahReportTable(
                            columns: docColumns,
                            rows: docRows,
                            numericColumns: const {2},
                            onRowTap: (index) => showPartySheet(
                                context,
                                widget.db,
                                rows[index].partyId,
                                rows[index].partyName),
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
    'sale': S.receivableFromSales,
    'purchase': S.payableFromPurchases,
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
      ? S.agingTitle
      : S.agingOf(_kindLabels[_kind]!);

  /// لسان صف الطرف — الفوهج غير الصفرية حصراً فلا صمت ولا ضجيج.
  /// (س205: حُذف بتحويل صفوف الأعمار للجدول الموحد م07 — خلايا الجدول
  /// سلاسل صفوف المستند ذاتها فلا لساناً ملموماً بالعرض.)

  /// أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20):
  /// تجميع واحد لصفوف العرض فما يُصدَّر هو المعروض حرفاً لا إعادة حساب.
  List<String> _agingColumns(AgingReport report) => [
        S.partyLabel,
        S.directionLabel,
        ...report.bucketLabels,
        S.totalLabel,
      ];

  List<List<String>> _agingRows(AgingReport report) => [
        for (final party in report.parties)
          [
            party.partyName,
            party.theyOweUs ? S.theyOweUs : S.weOweThem,
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
        (S.totalLabel, formatMinorAmount(report.totalMinor)),
      ];

  Future<void> _print(AgingReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildDocumentPdf(
        db: widget.db,
        title: _kindLabel,
        headerPairs: [
          (S.agingPeriods, agingPresetLabel(report.thresholds)),
        ],
        columns: _agingColumns(report),
        rows: _agingRows(report),
        footerPairs: _agingFooter(report),
        format: resolvePageFormat(docKind: 'report'),
      );
      if (!context.mounted) return;
      await sharePdfBytes(bytes, S.agingPdf);
    } catch (e) {
      await dqLog(widget.db, e, context: 'report.aging_print');
      messenger.showSnackBar(
        SnackBar(content: Text(S.printFailed(e, dqTag(e)))),
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
        (S.agingPeriods, agingPresetLabel(report.thresholds)),
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
                  ? S.theyOweUsOpen
                  : S.weOweThemOpen),
            ),
            for (final inv in party.invoices)
              ListTile(
                title: Text(S.invoiceNumber(inv.number)),
                subtitle: Text(
                    S.dueDateWith(inv.dueDate ?? inv.invoiceDate, inv.daysOver < 0
                        ? S.notDue
                        : inv.daysOver == 0
                            ? S.dueToday
                            : S.overdueDays(inv.daysOver))),
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
      appBar: AppBar(title: const Text(S.agingTitle)),
      body: FutureBuilder<AgingReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) return _reportWait();
          final report = snapshot.data!;
          if (report.parties.isEmpty) {
            return _reportEmpty(S.noOpenReceivables);
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
                            const InputDecoration(labelText: S.byTypeLabel),
                        items: const [
                          DropdownMenuItem<String>(
                              value: null, child: Text(S.allLabel)),
                          DropdownMenuItem<String>(
                              value: 'sale', child: Text(S.receivableLabel)),
                          DropdownMenuItem<String>(
                              value: 'purchase', child: Text(S.payableLabel)),
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
                            labelText: S.agingPeriods),
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
                  ],
                ),
              ),
              // F-166 (الدفعة 20): شريط الأزرار سطرٌ مستقل أسفل الفلاتر —
              // عرض الزرين لا يضيق قائمتي الفلتر تحت حدّهما الأدنى
              // (درس جولة 182: تجاوز 64px بحشرته في الصف نفسه).
              _ReportActionsBar(
                onPrint: () => _print(report),
                onCsv: () => _csv(report),
              ),
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    S.totalOf(formatMinorAmount(report.totalMinor)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              // م07 (س205): صفوف الأعمار جدولاً بفوهجه كاملةً كما
              // تُطبع وتُصدَّر (عرف F-166) والصفر بشرطته «—»، ونقر
              // الصف بعرفه القائم (D-135).
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                      horizontal: diqqahAdaptiveHorizontalMargin(context)),
                  children: [
                    DiqqahReportTable(
                      columns: _agingColumns(report),
                      rows: _agingRows(report),
                      numericColumns: {
                        for (var i = 2;
                            i < _agingColumns(report).length;
                            i++)
                          i,
                      },
                      onRowTap: (index) =>
                          _showPartyInvoices(report.parties[index]),
                      // س225 (الإجماليات بخط مزدوج المحاسبي داخل الجدول):
                      // فوهد الأعمار المجمعة أسفل الجدول — البيانات نفسها
                      // المطبوعة بالفقرة الزائفة (F-166) لا حساب جديد،
                      // والصفر بشرطته «—» بعرف الصفوف، والبطاقة العلوية
                      // بمجموعها البسيط باقية كما هي فلا موضع مختبر يزحزح.
                      footerRows: [
                        [
                          S.invoicesGroupTotal,
                          '',
                          for (var i = 0;
                              i < report.bucketLabels.length;
                              i++)
                            report.bucketTotalsMinor[i] == 0
                                ? '—'
                                : formatMinorAmount(
                                    report.bucketTotalsMinor[i]),
                          formatMinorAmount(report.totalMinor),
                        ],
                      ],
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
    'sales': S.salesLabel,
    'purchase': S.purchasesLabel,
    'cash': S.boxLabel,
    'stock': S.stockLabel,
    'general': S.generalEntry,
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
    S.dateLabel,
    S.entryLabel,
    S.bookLabel,
    S.accountLabel,
    S.partyLabel,
    S.debitLabel,
    S.creditLabel,
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
        (S.totalDebit, formatMinorAmount(report.totalDebitMinor)),
        (S.totalCredit, formatMinorAmount(report.totalCreditMinor)),
        (
          S.statusLabel,
          report.isBalanced
              ? S.bothTotalsBalanced
              : S.notBalanced,
        ),
      ];

  Future<void> _print(JournalBookReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildDocumentPdf(
        db: widget.db,
        title: S.journalBookTitle,
        headerPairs: const [],
        columns: _journalColumns,
        rows: _journalRows(report),
        footerPairs: _journalFooter(report),
        format: resolvePageFormat(docKind: 'report'),
      );
      if (!context.mounted) return;
      await sharePdfBytes(bytes, S.journalPdf);
    } catch (e) {
      await dqLog(widget.db, e, context: 'report.journal_print');
      messenger.showSnackBar(
        SnackBar(content: Text(S.printFailed(e, dqTag(e)))),
      );
    }
  }

  /// F-166 (الدفعة 20): تصدير صورة العرض الحالي بصفوف الطباعة ذاتها.
  Future<void> _csv(JournalBookReport report) {
    return _exportReportCsv(
      context,
      title: S.journalBookTitle,
      columns: _journalColumns,
      rows: _journalRows(report),
      footer: _journalFooter(report),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.journalBookTitle)),
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
                child: Column(
                  children: [
                    // س235 (توحيد النمط بكلمة المالك): النوع منسدلة
                    // مستقلة — والمدى بشريطه الفوري الموحد أدناه.
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _journalKind,
                            decoration:
                                const InputDecoration(labelText: S.bookLabel),
                            items: [
                              const DropdownMenuItem<String>(
                                  value: null, child: Text(S.allLabel)),
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    // س235: شريط المدى الفوري الموحد — الخمسة وحقلا
                    // من/إلى بلا زر عرض (التطبيق الفوري بديبونس قصير).
                    DiqqahInstantRangeBar(
                        from: _from, to: _to, onReload: _reload),
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
                        S.totalsDebitCredit(formatMinorAmount(report.totalDebitMinor), formatMinorAmount(report.totalCreditMinor)),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _csv(report),
                            icon: const Icon(Icons.table_view_outlined),
                            label: const Text(S.exportCsv),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _print(report),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text(S.printOrPdf),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: report.entries.isEmpty
                    ? _reportEmpty(S.noEntriesInRange)
                    : ListView(
                        // م06 (س205): الهامش التكيفي — العريض يتوسّط.
                        padding: EdgeInsets.symmetric(
                            horizontal:
                                diqqahAdaptiveHorizontalMargin(context)),
                        children: [
                          for (final entry in report.entries)
                            Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: Column(
                                children: [
                                  ListTile(
                                    title: Text(
                                        S.withEntryAndDesc(entry.moveDate, entry.moveNumber, entry.journalName)),
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
                                          : Text(S.partyOf(line.partyName)),
                                      trailing: Text(
                                          S.debitCreditOf(formatMinorAmount(line.debitMinor), formatMinorAmount(line.creditMinor))),
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
/// مطابقة دفتر المخزون (الدفعة 31 — ثامنة م2): ثابت المطابقة D-067/F-178
/// معروض للمالك كما هو — «متطابقة ✓» ليرى الربط عيناً، و«ميل» بأرقامه
/// إن ظهر مستحيلاً بنياً (نمط شارة الميزان F-068: الصدق لا الطمْر).
/// الصفوف بترتيب الكود والإجماليان أسفلها — والتصدير والطباعة بصفوف
/// العرض ذاتها (F-166: لا تقرير بلا زر CSV).
class LedgerReconView extends StatelessWidget {
  final DiqqahDatabase db;

  const LedgerReconView({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.stockLedgerMatchTitle)),
      body: FutureBuilder<InventoryReconciliationReport>(
        future: db.inventoryLedgerReconciliation(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final report = snapshot.data!;
          if (report.rows.isEmpty) {
            return _reportEmpty(S.noStockMovesYet);
          }
          const docColumns = [S.itemLabel, S.byLedgerEntries, S.byMovements, S.varianceLabel];
          final docRows = [
            for (final row in report.rows)
              [
                '${row.sku} ${row.name}',
                formatMinorAmount(row.ledgerValueMinor),
                formatMinorAmount(row.stockValueMinor),
                row.driftMinor == 0
                    ? S.matchedLabel
                    : formatMinorAmount(row.driftMinor),
              ],
          ];
          final footer = <(String, String)>[
            (S.totalByEntries, formatMinorAmount(report.ledgerTotalMinor)),
            (S.totalByMovements, formatMinorAmount(report.stockTotalMinor)),
            (S.varianceLabel, report.isMatched
                ? S.zeroLabel
                : formatMinorAmount(report.driftMinor)),
          ];
          return Column(
            children: [
              _ReportActionsBar(
                onPrint: () => _printReportDoc(context,
                  db: db,
                    title: S.stockLedgerMatchTitle,
                    columns: docColumns,
                    rows: docRows,
                    footer: footer),
                onCsv: () => _exportReportCsv(context,
                    title: S.stockLedgerMatchTitle,
                    columns: docColumns,
                    rows: docRows,
                    footer: footer),
              ),
              Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                color: report.isMatched
                    // س182 (م05): حالات المطابقة من أدوار الثيم لا من
                    // أخضر/برتقالي خام — فتنصلح بالوضعين معاً.
                    ? diqqahLanesOf(context).positive.bg
                    : null,
                child: ListTile(
                  textColor: report.isMatched
                      ? diqqahLanesOf(context).positive.fg
                      : null,
                  leading: Icon(
                    report.isMatched
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: report.isMatched
                        ? diqqahLanesOf(context).positive.fg
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: Text(report.isMatched
                      ? S.matchCorrect
                      : S.bookVarianceAlert),
                  subtitle: Text(
                      S.entriesVsStock(formatMinorAmount(report.ledgerTotalMinor), formatMinorAmount(report.stockTotalMinor))),
                ),
              ),
              // م07 (س205): صفوف المطابقة أعمدةً — وحالة الصف بلونها
              // الدلالي القائم (عرف م05: أدوار الثيم لا ألوان خام).
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                      horizontal: diqqahAdaptiveHorizontalMargin(context)),
                  children: [
                    DiqqahReportTable(
                      columns: docColumns,
                      rows: [
                        for (final row in report.rows)
                          [
                            '${row.sku} ${row.name}',
                            formatMinorAmount(row.ledgerValueMinor),
                            formatMinorAmount(row.stockValueMinor),
                            row.driftMinor == 0
                                ? S.matchedCheck
                                : S.varianceOf(formatMinorAmount(row.driftMinor)),
                          ],
                      ],
                      numericColumns: const {1, 2, 3},
                      rowTextColors: [
                        for (final row in report.rows)
                          row.isMatched
                              ? diqqahLanesOf(context).positive.fg
                              : Theme.of(context).colorScheme.error,
                      ],
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

/// قائمة الدخل (الدفعة 33 — عاشرة م2/F-096): إيرادات ومصروفات وصافي
/// بمدى تاريخ مدقَّق قبل القاعدة (D-077)، والمدى الافتراضي سنة البذور
/// كاملة — والأرقام بوحداتها الصغرى كما تُخزن (D-092) والتصدير
/// والطباعة بصفوف العرض ذاتها (F-166).
class IncomeStatementView extends StatefulWidget {
  final DiqqahDatabase db;

  const IncomeStatementView({super.key, required this.db});

  @override
  State<IncomeStatementView> createState() => _IncomeStatementViewState();
}

class _IncomeStatementViewState extends State<IncomeStatementView> {
  late Future<IncomeStatement> _future;
  late final TextEditingController _from;
  late final TextEditingController _to;
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    final year = DateTime.now().year;
    _from = TextEditingController(text: '$year-01-01');
    _to = TextEditingController(text: todayIsoDate());
    _future = widget.db.incomeStatementReport(
        fromText: _from.text, toText: _to.text);
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _reload() {
    final errors = validateReportRange(_from.text.trim(), _to.text.trim());
    setState(() {
      _rangeError = errors.isEmpty
          ? null
          : errors.map(describeReportValidationError).join(S.semicolonSpace);
      if (errors.isEmpty) {
        _future = widget.db.incomeStatementReport(
            fromText: _from.text.trim(), toText: _to.text.trim());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.incomeStatementTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                // س235: شريط المدى الفوري الموحد — الخمسة وحقلا
                // من/إلى بلا زر عرض (التطبيق الفوري بديبونس قصير).
                DiqqahInstantRangeBar(
                    from: _from, to: _to, onReload: _reload),
              ],
            ),
          ),
          if (_rangeError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_rangeError!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: FutureBuilder<IncomeStatement>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return _reportWait();
                final statement = snapshot.data!;
                const docColumns = [S.accountLabel, S.descriptionLabel, S.amountLabel];
                final docRows = [
                  for (final r in statement.revenueRows)
                    [r.code, r.name, formatMinorAmount(r.amountMinor)],
                  for (final r in statement.expenseRows)
                    [
                      r.code,
                      r.name,
                      formatMinorAmount(-r.amountMinor),
                    ],
                ];
                final footer = <(String, String)>[
                  (S.totalRevenues,
                      formatMinorAmount(statement.totalRevenueMinor)),
                  (S.totalExpenses,
                      formatMinorAmount(statement.totalExpenseMinor)),
                  (
                    S.netResult,
                    statement.netResultMinor >= 0
                        ? S.profitOf(formatMinorAmount(statement.netResultMinor))
                        : S.lossOf(formatMinorAmount(-statement.netResultMinor))
                  ),
                ];
                return Column(
                  children: [
                    _ReportActionsBar(
                      onPrint: () => _printReportDoc(context,
                        db: widget.db,
                          title: S.incomeStatementTitle,
                          columns: docColumns,
                          rows: docRows,
                          footer: footer),
                      onCsv: () => _exportReportCsv(context,
                          title: S.incomeStatementTitle,
                          columns: docColumns,
                          rows: docRows,
                          footer: footer),
                    ),
                    Expanded(
                      child: ListView(
                        // م06 (س205): الهامش التكيفي — العريض يتوسّط.
                        padding: EdgeInsets.symmetric(
                            horizontal:
                                diqqahAdaptiveHorizontalMargin(context)),
                        children: [
                          for (final r in statement.revenueRows)
                            ListTile(
                              title: Text('${r.code} ${r.name}'),
                              trailing: Text(
                                  formatMinorAmount(r.amountMinor)),
                            ),
                          for (final r in statement.expenseRows)
                            ListTile(
                              title: Text('${r.code} ${r.name}'),
                              trailing: Text(
                                  '(${formatMinorAmount(r.amountMinor)})'),
                            ),
                          const Divider(),
                          for (final (label, value) in footer)
                            ListTile(
                              title: Text(label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              trailing: Text(value,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
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

/// مراكز العملات (الدفعة 34 — F-124، D-194): كل عملة حية بصناديقها
/// بعددها ومجموع أرصدتها بالأساسية من الدفتر، وفواتيرها المفتوحة
/// المرحّلة المتبقية بعملة الفاتورة وبأساسها المخزن بلقطة الفاتورة
/// ذاتها، ومكافئها الأساسي المجموع — القيم المخزنة حصراً لا حساب
/// صرف جديد — وآخر سعر مسجل بتاريخه. والتصدير والطباعة بصفوف
/// العرض ذاتها (F-166: لا تقرير بلا زر CSV).
class _CurrencyPositionsView extends StatelessWidget {
  final DiqqahDatabase db;

  const _CurrencyPositionsView({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.currencyCentersTitle)),
      body: FutureBuilder<List<CurrencyPositionInput>>(
        future: db.currencyPositions(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _reportWait();
          final rows = currencyPositionsCompute(snapshot.data!);
          const docColumns = [
            S.currencyLabel,
            S.boxesTitle,
            S.boxesBalanceBase,
            S.openInvoices,
            S.remainingInvoiceCurrency,
            S.remainingBaseCurrency,
            S.totalEquivalentBase,
            S.lastRateRecorded,
            S.itsDate,
          ];
          final docRows = [
            for (final r in rows)
              [
                '${r.code}${r.isBase ? S.baseSuffix : ''}',
                '${r.boxesCount}',
                formatMinorAmount(r.boxesBaseMinor),
                '${r.openInvoicesCount}',
                formatMinorAmount(r.openRemainderDocMinor),
                formatMinorAmount(r.openRemainderBaseMinor),
                formatMinorAmount(r.totalBaseMinor),
                r.latestRateToBase == null
                    ? '—'
                    : displayRateToBase(r.latestRateToBase),
                r.latestRateDate ?? '—',
              ],
          ];
          return Column(
            children: [
              _ReportActionsBar(
                onPrint: () => _printReportDoc(context,
                  db: db,
                    title: S.currencyCentersTitle,
                    columns: docColumns,
                    rows: docRows),
                onCsv: () => _exportReportCsv(context,
                    title: S.currencyCentersTitle,
                    columns: docColumns,
                    rows: docRows),
              ),
              // م07 (س205): مراكز العملات أعمدةً بتسعة أعمدتها كما
              // تُطبع وتُصدَّر (عرف F-166) — والعملة بلسانها الكامل
              // بعمودها الأول كما كان عنوان الصف.
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                      horizontal: diqqahAdaptiveHorizontalMargin(context)),
                  children: [
                    DiqqahReportTable(
                      columns: docColumns,
                      rows: [
                        for (final r in rows)
                          [
                            '${r.code} — ${r.name}'
                                '${r.isBase ? S.baseSuffix : ''}',
                            '${r.boxesCount}',
                            formatMinorAmount(r.boxesBaseMinor),
                            '${r.openInvoicesCount}',
                            formatMinorAmount(r.openRemainderDocMinor),
                            formatMinorAmount(r.openRemainderBaseMinor),
                            formatMinorAmount(r.totalBaseMinor),
                            r.latestRateToBase == null
                                ? '—'
                                : displayRateToBase(r.latestRateToBase),
                            r.latestRateDate ?? '—',
                          ],
                      ],
                      numericColumns: const {1, 2, 3, 4, 5, 6},
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

/// الميزانية العمومية إلى تاريخ (الدفعة 33 — عاشرة م2/F-096): أصول
/// وخصوم وحقوق ملكية بنتيجتها الجارية، والمعادلة بشارتها الظاهرة
/// (الصمتُ كذب — D-092 والصدقُ أولاً)، والتصدير والطباعة بصفوف
/// العرض ذاتها (F-166).
class BalanceSheetView extends StatefulWidget {
  final DiqqahDatabase db;

  const BalanceSheetView({super.key, required this.db});

  @override
  State<BalanceSheetView> createState() => _BalanceSheetViewState();
}

class _BalanceSheetViewState extends State<BalanceSheetView> {
  late Future<BalanceSheet> _future;
  late final TextEditingController _asOf;
  String? _rangeError;

  /// س235: ديبونس التطبيق الفوري للتاريخ الأحادي.
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _asOf = TextEditingController(text: todayIsoDate());
    _future =
        widget.db.balanceSheetReport(asOfText: _asOf.text);
    _asOf.addListener(_onAsOfTyped);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _asOf.dispose();
    super.dispose();
  }

  /// س235: الكتابة تُطبَّق بتأخير قصير — والناقص أو الفاسد انتظار
  /// كتابة لا تطبيق ولا وميض أخطاء بكل حرف (عرف D-077 بثوب الفوري).
  void _onAsOfTyped() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final text = _asOf.text.trim();
      if (text.isEmpty || !isValidIsoDate(text)) return;
      _reload();
    });
  }

  void _reload() {
    final text = _asOf.text.trim();
    final valid = isValidIsoDate(text);
    setState(() {
      _rangeError = valid
          ? null
          : describeReportValidationError(ReportRangeInvalidDate(text));
      if (valid) {
        _future = widget.db.balanceSheetReport(asOfText: text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.balanceSheetTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              // س235: التاريخ الأحادي بتطبيق فوري (ديبونس قصير) بلا
              // زر عرض — وليس مدى فلا أزرار الخمسة (تفسير محدود
              // موثق: التوحيد للفورية لا لفرض المدى على حقل واحد).
              Expanded(
                child: TextField(
                  controller: _asOf,
                  decoration: InputDecoration(
                      labelText: S.toDateWithFormat,
                      suffixIcon: calendarPickerSuffix(context, _asOf)),
                ),
              ),
            ]),
          ),
          if (_rangeError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_rangeError!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: FutureBuilder<BalanceSheet>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return _reportWait();
                final sheet = snapshot.data!;
                const docColumns = [S.accountLabel, S.descriptionLabel, S.sideLabel, S.amountLabel];
                final docRows = [
                  for (final r in sheet.assetRows)
                    [
                      r.code,
                      r.name,
                      r.isDebitSide ? S.debitLabel : S.creditLabel,
                      formatMinorAmount(r.magnitudeMinor),
                    ],
                  for (final r in sheet.liabilityRows)
                    [
                      r.code,
                      r.name,
                      r.isDebitSide ? S.debitLabel : S.creditLabel,
                      formatMinorAmount(r.magnitudeMinor),
                    ],
                  for (final r in sheet.equityRows)
                    [
                      r.code,
                      r.name,
                      r.isDebitSide ? S.debitLabel : S.creditLabel,
                      formatMinorAmount(r.magnitudeMinor),
                    ],
                ];
                final footer = <(String, String)>[
                  (S.totalAssets, formatMinorAmount(sheet.totalAssetsMinor)),
                  (S.totalLiabilities,
                      formatMinorAmount(sheet.totalLiabilitiesMinor)),
                  (
                    S.totalEquity,
                    formatMinorAmount(sheet.totalEquityMinor),
                  ),
                ];
                return Column(
                  children: [
                    _ReportActionsBar(
                      onPrint: () => _printReportDoc(context,
                        db: widget.db,
                          title: S.balanceSheetTitle,
                          columns: docColumns,
                          rows: docRows,
                          footer: footer),
                      onCsv: () => _exportReportCsv(context,
                          title: S.balanceSheetTitle,
                          columns: docColumns,
                          rows: docRows,
                          footer: footer),
                    ),
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      // س182 (م05): حالة توازن المعادلة من أدوار الثيم
                      // لا من أخضر/أحمر خام — فتنصلح بالوضعين معاً.
                      color: sheet.isBalanced
                          ? diqqahLanesOf(context).positive.bg
                          : Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        textColor: sheet.isBalanced
                            ? diqqahLanesOf(context).positive.fg
                            : null,
                        leading: Icon(
                          sheet.isBalanced
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_outlined,
                          color: sheet.isBalanced
                              ? diqqahLanesOf(context).positive.fg
                              : Theme.of(context).colorScheme.error,
                        ),
                        title: Text(sheet.isBalanced
                            ? S.equationBalanced
                            : S.equationNotBalanced),
                        subtitle: Text(
                            S.assetsLiabilitiesEquity(formatMinorAmount(sheet.totalAssetsMinor), formatMinorAmount(sheet.totalLiabilitiesMinor), formatMinorAmount(sheet.totalEquityMinor))),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        // م06 (س205): الهامش التكيفي — العريض يتوسّط.
                        padding: EdgeInsets.symmetric(
                            horizontal:
                                diqqahAdaptiveHorizontalMargin(context)),
                        children: [
                          for (final r in sheet.assetRows)
                            ListTile(
                              title: Text('${r.code} ${r.name}'),
                              subtitle: const Text(S.assetsLabel),
                              trailing: Text(
                                  formatMinorAmount(r.magnitudeMinor)),
                            ),
                          for (final r in sheet.liabilityRows)
                            ListTile(
                              title: Text('${r.code} ${r.name}'),
                              subtitle: const Text(S.liabilitiesLabel),
                              trailing: Text(
                                  formatMinorAmount(r.magnitudeMinor)),
                            ),
                          for (final r in sheet.equityRows)
                            ListTile(
                              title: Text('${r.code} ${r.name}'),
                              subtitle: const Text(S.equityLabel),
                              trailing: Text(
                                  formatMinorAmount(r.magnitudeMinor)),
                            ),
                          if (sheet.currentResultMinor != 0)
                            ListTile(
                              title: const Text(S.currentPeriodResult),
                              subtitle:
                                  const Text(S.fromResultAccountsToDate),
                              trailing: Text(
                                  formatMinorAmount(
                                      sheet.currentResultMinor)),
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
              ? S.stockReportTitle
              : S.balanceInStock(widget.isolatedItemName ?? ''))),
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
            return _reportEmpty(S.noStockYet);
          }
          // أجزاء المستند مشتركة بين الطباعة والتصدير (F-166 — الدفعة 20).
          const docColumns = [
            S.itemLabel, S.warehouseLabel, S.quantityLabel, S.valueLabel, S.averageLabel
          ];
          final docRows = [
            for (final row in visibleRows)
              [
                '${row.sku} ${row.name}',
                row.warehouseName ?? S.unspecifiedLabel,
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
                        itemById[row.itemId]?.name ?? S.itemSingular,
                    ];
                  }
                  if (!context.mounted) return;
                  await _printReportDoc(
                    db: widget.db,
                    context,
                    title: isolated == null
                        ? S.stockReportTitle
                        : S.balanceInStock(widget.isolatedItemName ?? ''),
                    columns: docColumns,
                    rows: docRows,
                    rowImages: rowImages,
                    rowLetters: rowLetters,
                  );
                },
                onCsv: () => _exportReportCsv(
                  context,
                  title: isolated == null
                      ? S.stockReportTitle
                      : S.balanceInStock(widget.isolatedItemName ?? ''),
                  columns: docColumns,
                  rows: docRows,
                ),
              ),
              Expanded(
                child: ListView(
                  // م06 (س205): الهامش التكيفي — العريض يتوسّط، وصور
                  // الصفوف القائمة باقية بعرفها (D-123) فلا جدولاً هنا.
                  padding: EdgeInsets.symmetric(
                      horizontal: diqqahAdaptiveHorizontalMargin(context)),
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
                            S.warehouseAndAverage(row.warehouseName ?? S.unspecifiedLabel, row.avgCostBaseMinor == null ? '—' : formatMinorAmount(row.avgCostBaseMinor!))),
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
  static const _movementColumns = [S.itemLabel, S.detailLabel, S.netLabel];

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
              S.salesReturnsDetail(r.qtySoldBase, formatMinorAmount(r.salesValueBaseMinor), r.qtyReturnedBase, formatMinorAmount(r.returnsValueBaseMinor)),
              S.netOf(r.netQtyBase, formatMinorAmount(r.netValueBaseMinor)),
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
              S.purchasesReturnsDetail(r.qtyPurchasedBase, formatMinorAmount(r.purchasesValueBaseMinor), r.qtyReturnedBase, formatMinorAmount(r.returnsValueBaseMinor)),
              S.netOf(r.netQtyBase, formatMinorAmount(r.netValueBaseMinor)),
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
      await dqLog(widget.db, e, context: 'report.run');
      if (!mounted) return;
      setState(() => _error =
          '${e.errors.map(describeReportValidationError).join(S.semicolonSpace)}'
          '${dqTag(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isolatedItemId == null
        ? (widget.sales ? S.itemSalesMovementTitle : S.purchasesReportTitle)
        : (widget.sales
            ? S.salesOf(widget.isolatedItemName ?? '')
            : S.purchasesOf(widget.isolatedItemName ?? ''));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // س235: شريط المدى الفوري الموحد — الخمسة وحقلا
                // من/إلى بلا زر عرض (التطبيق الفوري بديبونس قصير).
                DiqqahInstantRangeBar(
                    from: _from, to: _to, onReload: _run),
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
                        db: widget.db,
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
                ? const Center(child: Text(S.enterRangeThenView))
                : _rows!.isEmpty
                    ? _reportEmpty(S.noMovementInRange)
                    : ListView(
                        // م06 (س205): الهامش التكيفي — العريض يتوسّط،
                        // وصور الصفوف القائمة باقية بعرفها (D-123).
                        padding: EdgeInsets.symmetric(
                            horizontal:
                                diqqahAdaptiveHorizontalMargin(context)),
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
