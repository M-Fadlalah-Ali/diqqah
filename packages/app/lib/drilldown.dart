import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'invoices_screen.dart' show InvoiceDetailScreen;
import 'items_screen.dart' show ItemEditScreen;
import 'parties_screen.dart' show PartyEditScreen;
import 'print_service.dart';
import 'reports_screen.dart'
    show MovementView, InventoryView, formatMinorAmount;

// ═══════════════════════════════════════════════════════════════════
// دفعة (13) الروابط التفرعية (س-143..س-147/D-135..D-137)
//
// المبدأ المؤسسي (س-143/D-135) بلفظ المالك «ثالثاً موافق» على «كل اسم
// تقرأه في أي شاشة يصير مدخلاً»: كل اسم صنف أو حساب أو طرف يظهر في أي
// شاشة يصير نقرةً تفتح بطاقته وتفاصيلها — وتلزِم كل شاشة قادمة.
//
// هنا ورقة الصنف من مواضعها الخمسة (س-144/D-136) وورقة الطرف من الذمم
// (س-147) وكشف الحساب وكشف الطرف وحركة المادة وقوائم مستندات الطرف —
// كلها قراءات خالصة من المرحّل حصراً بلا حساب جديد.
// ═══════════════════════════════════════════════════════════════════

/// س-144/D-136: ورقة الصنف — النقر على اسم الصنف في أي موضع من مواضعه
/// الخمسة يفتح ورقة خياراته: بطاقة الصنف (للتعديل) وحركة المادة
/// ومبيعاته ومشترياته ورصيده في المخزون.
Future<void> showItemSheet(
  BuildContext context,
  DiqqahDatabase db,
  int itemId,
  String itemLabel,
) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('الصنف: $itemLabel',
                style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('بطاقة الصنف — فتح للتعديل'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final rows = await db.select(db.items).get();
              final item =
                  rows.where((r) => r.id == itemId).firstOrNull;
              if (item == null || !sheetContext.mounted) return;
              await Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ItemEditScreen(db: db, existing: item),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert_outlined),
            title: const Text('حركة المادة'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => ItemStockMovesScreen(
                      db: db, itemId: itemId, itemLabel: itemLabel),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('مبيعاته — معزولة على الصنف'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => MovementView(
                    db: db,
                    sales: true,
                    isolatedItemId: itemId,
                    isolatedItemName: itemLabel,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: const Text('مشترياته — معزولة على الصنف'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => MovementView(
                    db: db,
                    sales: false,
                    isolatedItemId: itemId,
                    isolatedItemName: itemLabel,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('رصيده في المخزون'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => InventoryView(
                    db: db,
                    isolatedItemId: itemId,
                    isolatedItemName: itemLabel,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// س-147/D-135: ورقة الطرف — النقر على الطرف في الذمم يفتح بطاقته
/// للتعديل وقوائم فواتيره وسنداته وكشف حسابه.
Future<void> showPartySheet(
  BuildContext context,
  DiqqahDatabase db,
  int partyId,
  String partyName,
) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('الطرف: $partyName',
                style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('بطاقة الطرف — فتح للتعديل'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final rows = await db.select(db.parties).get();
              final party =
                  rows.where((r) => r.id == partyId).firstOrNull;
              if (party == null || !sheetContext.mounted) return;
              await Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PartyEditScreen(db: db, existing: party),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('فواتيره'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => PartyInvoicesScreen(
                      db: db, partyId: partyId, partyName: partyName),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.request_quote_outlined),
            title: const Text('سنداته'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => PartyVouchersScreen(
                      db: db, partyId: partyId, partyName: partyName),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt),
            title: const Text('كشف حسابه'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(sheetContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => PartyStatementScreen(
                      db: db, partyId: partyId, partyName: partyName),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// شريط زر الطباعة الموحد لشاشات الدفعة — ظاهر دائماً لا يختفي
/// بالتمرير، والفشل رسالة لا صمت.
class DrilldownActionsBar extends StatelessWidget {
  final VoidCallback onPrint;

  const DrilldownActionsBar({super.key, required this.onPrint});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onPrint,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('طباعة / PDF'),
            ),
          ],
        ),
      );
}

/// طباعة تقرير روابط بنمط التقارير (A4 عرضي) — نقطة إخراج واحدة
/// لشاشات هذه الوحدة، والفشل رسالة لا صمت.
Future<void> printDrilldownDoc(
  BuildContext context, {
  required String title,
  required List<String> columns,
  required List<List<String>> rows,
  List<(String, String)> footer = const [],
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildDocumentPdf(
      title: title,
      headerPairs: const [],
      columns: columns,
      rows: rows,
      footerPairs: footer,
      format: resolvePageFormat(docKind: 'report'),
    );
    await sharePdfBytes(bytes, '$title.pdf');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر توليد الطباعة — $e')),
    );
  }
}

// ─── كشف الحساب (س-146/D-137) ───

/// شاشة كشف الحساب — «دفتر الأستاذ»: كل قيود الحساب بترتيب الزمن
/// والرصيد التراكمي بعد كل قيد، ومجموعه ورصيده النهائي يطابقان صف
/// الحساب في ميزان المراجعة حصراً (ضابط التوازن — روح F-068).
/// تُفتح بالنقر على الحساب في ميزان المراجعة.
class AccountStatementScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final int accountId;

  const AccountStatementScreen({
    super.key,
    required this.db,
    required this.accountId,
  });

  @override
  State<AccountStatementScreen> createState() =>
      _AccountStatementScreenState();
}

class _AccountStatementScreenState extends State<AccountStatementScreen> {
  /// المستقبل مرة واحدة لعمر الحالة — درس السرد الكسول الموثق.
  late final Future<AccountStatementReport> _data =
      widget.db.accountStatementReport(widget.accountId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كشف حساب')),
      body: FutureBuilder<AccountStatementReport>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = snapshot.data!;
          final account = report.account;
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text('${account.code} ${account.name}',
                          style:
                              Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'مجموع المدين '
                        '${formatMinorAmount(report.totalDebitMinor)}'
                        ' — مجموع الدائن '
                        '${formatMinorAmount(report.totalCreditMinor)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الرصيد النهائي '
                        '${formatMinorAmount(report.closingBalanceMinor)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
              DrilldownActionsBar(
                onPrint: () => printDrilldownDoc(
                  context,
                  title: 'كشف حساب ${account.code} ${account.name}',
                  columns: const [
                    'التاريخ',
                    'القيد',
                    'البيان',
                    'مدين',
                    'دائن',
                    'الرصيد'
                  ],
                  rows: [
                    for (final e in report.entries)
                      [
                        e.moveDate,
                        e.moveNumber,
                        e.narration ?? '—',
                        formatMinorAmount(e.debitMinor),
                        formatMinorAmount(e.creditMinor),
                        formatMinorAmount(e.runningBalanceMinor),
                      ],
                  ],
                  footer: [
                    (
                      'مجموع المدين',
                      formatMinorAmount(report.totalDebitMinor),
                    ),
                    (
                      'مجموع الدائن',
                      formatMinorAmount(report.totalCreditMinor),
                    ),
                    (
                      'الرصيد النهائي',
                      formatMinorAmount(report.closingBalanceMinor),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: report.entries.isEmpty
                    ? const Center(child: Text('لا قيود على هذا الحساب'))
                    : ListView(
                        children: [
                          for (final e in report.entries)
                            ListTile(
                              dense: true,
                              title: Text(
                                  '${e.moveDate} · ${e.moveNumber}'
                                  '${e.narration == null ? '' : ' · ${e.narration}'}'),
                              subtitle: Text(
                                  'مدين ${formatMinorAmount(e.debitMinor)}'
                                  ' · دائن ${formatMinorAmount(e.creditMinor)}'),
                              trailing: Text(
                                  'الرصيد ${formatMinorAmount(e.runningBalanceMinor)}'),
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

// ─── كشف حساب الطرف (س-147) ───

/// شاشة كشف حساب الطرف — كل قيود أرجل طرفه بترتيب الزمن وصافيه
/// التراكمي، وصافيه النهائي يطابق صف الطرف في تقرير الذمم حصراً.
class PartyStatementScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final int partyId;
  final String partyName;

  const PartyStatementScreen({
    super.key,
    required this.db,
    required this.partyId,
    required this.partyName,
  });

  @override
  State<PartyStatementScreen> createState() => _PartyStatementScreenState();
}

class _PartyStatementScreenState extends State<PartyStatementScreen> {
  late final Future<PartyStatementReport> _data =
      widget.db.partyStatementReport(widget.partyId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كشف حساب الطرف')),
      body: FutureBuilder<PartyStatementReport>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = snapshot.data!;
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(widget.partyName,
                          style:
                              Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'الصافي النهائي '
                        '${formatMinorAmount(report.closingNetDebitMinor)}'
                        ' — موجب: هم يدينون لنا وسالب: نحن مدينون لهم',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              DrilldownActionsBar(
                onPrint: () => printDrilldownDoc(
                  context,
                  title: 'كشف حساب الطرف ${widget.partyName}',
                  columns: const [
                    'التاريخ',
                    'القيد',
                    'الحساب',
                    'مدين',
                    'دائن',
                    'الصافي'
                  ],
                  rows: [
                    for (final e in report.entries)
                      [
                        e.moveDate,
                        e.moveNumber,
                        e.accountCode,
                        formatMinorAmount(e.debitMinor),
                        formatMinorAmount(e.creditMinor),
                        formatMinorAmount(e.runningNetDebitMinor),
                      ],
                  ],
                  footer: [
                    (
                      'الصافي النهائي (مدين − دائن)',
                      formatMinorAmount(report.closingNetDebitMinor),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: report.entries.isEmpty
                    ? const Center(child: Text('لا قيود على هذا الطرف'))
                    : ListView(
                        children: [
                          for (final e in report.entries)
                            ListTile(
                              dense: true,
                              title: Text(
                                  '${e.moveDate} · ${e.moveNumber} · حساب ${e.accountCode}'),
                              subtitle: Text(
                                  'مدين ${formatMinorAmount(e.debitMinor)}'
                                  ' · دائن ${formatMinorAmount(e.creditMinor)}'),
                              trailing: Text(
                                  'الصافي ${formatMinorAmount(e.runningNetDebitMinor)}'),
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

// ─── حركة المادة (س-145/D-136) ───

/// شاشة حركة الصنف الواحد — لقطات مخزونه من سجل الحركات بفاتورتها
/// وتاريخها ومستودعها، بترتيب الورود (لقطات لا تعدل — F-140).
class ItemStockMovesScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final int itemId;
  final String itemLabel;

  const ItemStockMovesScreen({
    super.key,
    required this.db,
    required this.itemId,
    required this.itemLabel,
  });

  @override
  State<ItemStockMovesScreen> createState() =>
      _ItemStockMovesScreenState();
}

class _ItemStockMovesScreenState extends State<ItemStockMovesScreen> {
  late final Future<List<ItemStockMoveRow>> _data =
      widget.db.itemStockMovesReport(widget.itemId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حركة المادة')),
      body: FutureBuilder<List<ItemStockMoveRow>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.itemLabel,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              DrilldownActionsBar(
                onPrint: () => printDrilldownDoc(
                  context,
                  title: 'حركة المادة ${widget.itemLabel}',
                  columns: const [
                    'التاريخ',
                    'المستند',
                    'النوع',
                    'الكمية',
                    'المستودع',
                    'القيمة'
                  ],
                  rows: [
                    for (final r in rows)
                      [
                        r.dateText,
                        r.docLabel ?? '—',
                        r.isIn ? 'دخول' : 'خروج',
                        '${r.qtyBase}',
                        r.warehouseName ?? '—',
                        formatMinorAmount(r.valueBaseMinor),
                      ],
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('لا حركة لهذا الصنف'))
                    : ListView(
                        children: [
                          for (final r in rows)
                            ListTile(
                              dense: true,
                              title: Text(
                                  '${r.dateText} · ${r.docLabel ?? '—'}'),
                              subtitle: Text(
                                  '${r.isIn ? 'دخول' : 'خروج'} ${r.qtyBase}'
                                  ' · ${r.warehouseName ?? '—'}'),
                              trailing: Text(
                                  formatMinorAmount(r.valueBaseMinor)),
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

// ─── مستندات الطرف (س-147) ───

/// قائمة فواتير الطرف — قراءة القائمة بفلتر طرفها، والنقر يفتح
/// تفاصيل الفاتورة.
class PartyInvoicesScreen extends StatelessWidget {
  final DiqqahDatabase db;
  final int partyId;
  final String partyName;

  const PartyInvoicesScreen({
    super.key,
    required this.db,
    required this.partyId,
    required this.partyName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('فواتير $partyName')),
      body: FutureBuilder<List<InvoiceListRow>>(
        future: db.invoicesListReport(partyId: partyId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('لا فواتير لهذا الطرف'));
          }
          return ListView(
            children: [
              for (final row in rows)
                ListTile(
                  dense: true,
                  title: Text(row.displayLabel),
                  subtitle: Text(
                      '${row.invoiceDate} · ${row.stateLabel}'),
                  trailing: Text(
                      '${formatMinorAmount(row.totalDocMinor)}'
                      ' ${row.currencyCode}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          InvoiceDetailScreen(db: db, invoiceId: row.id),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// قائمة سندات الطرف — قراءة القائمة بفلتر طرفها.
class PartyVouchersScreen extends StatelessWidget {
  final DiqqahDatabase db;
  final int partyId;
  final String partyName;

  const PartyVouchersScreen({
    super.key,
    required this.db,
    required this.partyId,
    required this.partyName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('سندات $partyName')),
      body: FutureBuilder<List<VoucherListRow>>(
        future: db.vouchersListReport(partyId: partyId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('لا سندات لهذا الطرف'));
          }
          return ListView(
            children: [
              for (final row in rows)
                ListTile(
                  dense: true,
                  title: Text(row.displayLabel),
                  subtitle: Text(
                      '${row.voucherDate} · ${row.stateLabel}'),
                  trailing: Text(
                      '${formatMinorAmount(row.amountDocMinor)}'
                      ' ${row.currencyCode}'),
                ),
            ],
          );
        },
      ),
    );
  }
}
