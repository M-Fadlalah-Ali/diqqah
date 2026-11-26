/// شاشة الدفتر المحاسبي — الوحدة المفتوحة الخامسة عشرة (س125 — بأمر
/// المالك الحرفي «بعد الانتهاء نتوجه إلى تفعيل الذمم والدفتر المحاسبي»
/// بعد إغلاق b36 بأمره «قم ببناء b36»).
///
/// الإصدار 1 «الأساس» قراءة خالصة فوق البنية المنجزة م1 بلا ترحيلة
/// ولا مساس بالقلب المحاسبي — عين روح الطلبات (س121):
/// - «دليل الحسابات» (allLedgerAccounts): الشجرة بكودها واسمها ونوعها
///   ولسانها العربي من المجال (AccountType.label) وعلم الورقة —
///   والمعطّل باهت بعِلمه (لا حذف ولا تعطيل من هنا — الدليل يولد
///   زرعاً من م1 والصناديق تنشئ حساباتها الآلية D-086 فلا إنشاءً
///   يدوياً بدفعة الأساس).
/// - الضغط على حساب يفتح «كشف الحساب» (accountStatementReport):
///   أسطر القيود المرحّلة المجمدة لا يعاد حسابها (07 §2) بمجاميع
///   مدين/دائن ورصيد ختامي على جانبه الطبيعي (نمط الميزان الموثق:
///   موجب على الطبيعي وسالب على المعاكس — لا يُقلب خفية) وبالصافي
///   التراكمي بعد كل قيد.
///
/// الحدود الصادقة (الإصدار 1 الأساس): لا قيداً يدوياً ولا إنشاء حساب
/// من هنا — القيد بالسندات والفواتير والإذنان والجرد والإقفال
/// بمساراتها المحروسة حصراً (السابع والثامن وما تفرع عنها) — ولا
/// ميزان مراجعة ولا قوائم من هنا فهي منجزة بالتقارير اليومية
/// والفرق عرضاً لا مصدراً.
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart'
    show AccountInfo, NormalSide;
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
// س223: الحد المتدرج الموحد لقوائم المستندات (المتبقي من د5).
import 'list_display.dart';
import 'empty_state.dart';
import 'reports_screen.dart' show formatMinorAmount;

class LedgerScreen extends StatelessWidget {
  final DiqqahDatabase db;

  const LedgerScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدفتر المحاسبي')),
      body: DiqqahAdaptiveCenter(child: FutureBuilder<List<AccountInfo>>(
        // المستقبل مرة واحدة لعمر الحالة — درس السرد الكسول الموثق.
        future: db.allLedgerAccounts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snapshot.data!;
          if (accounts.isEmpty) {
            // س225 (خ6): حالة الفراغ الحية — ولسان الشاشة القائم حرفاً.
            return Center(
              child: DiqqahEmptyState(
                icon: Icons.menu_book_outlined,
                message: 'لا حسابات — الدليل فارغ',
              ),
            );
          }
          final leafCount = accounts.where((a) => a.isLeaf).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'دليل الحسابات — ${accounts.length} حساباً '
                  'منها $leafCount ورقة تفتح كشف حسابها',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final a in accounts)
                      ListTile(
                        dense: !a.isLeaf,
                        leading: Icon(
                          a.isLeaf
                              ? Icons.receipt_long_outlined
                              : Icons.folder_outlined,
                          color: a.isActive
                              ? null
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                        title: Text(
                          '${a.code} — ${a.name}',
                          style: TextStyle(
                            color: a.isActive
                                ? null
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                        subtitle: Text(
                          '${a.type.label}'
                          '${a.isLeaf ? '' : ' • مجموعة'}'
                          '${a.isActive ? '' : ' • معطّل'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: a.isLeaf
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AccountStatementPage(
                                      db: db,
                                      account: a,
                                    ),
                                  ),
                                )
                            : null,
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

/// كشف الحساب — accountStatementReport: أسطر القيود المرحّلة المجمدة
/// لا يعاد حسابها (07 §2) بالرصيد الختامي على جانبه الطبيعي.
/// س223 (المتبقي من د5): الصفحة Stateful بحجّة حد العرض المتدرج —
/// أسطر القيود تنمو بعمر الحساب فالحد بناء واجهة حصراً.
class AccountStatementPage extends StatefulWidget {
  final DiqqahDatabase db;
  final AccountInfo account;

  const AccountStatementPage({
    super.key,
    required this.db,
    required this.account,
  });

  @override
  State<AccountStatementPage> createState() =>
      _AccountStatementPageState();
}

class _AccountStatementPageState extends State<AccountStatementPage> {
  DiqqahDatabase get db => widget.db;
  AccountInfo get account => widget.account;

  /// س223 — الحد المتدرج لأسطر كشف الحساب (المتبقي من د5 بنمط
  /// list_display.dart): القراءة كاملة (accountStatementReport) لا
  /// مساس بها والحد بناء واجهة حصراً وزر التوسيع بعدّاد الباقي فالوجود
  /// كله متاح بالتوسع المتكرر.
  int _displayLimit = kListDisplayPageSize;

  /// جانب الرصيد بلفظ الموثق: موجبٌ على جانب الحساب الطبيعي وسالبٌ
  /// على المعاكس — لا يُقلب خفية (نمط الميزان الموثق بحقل
  /// runningBalanceMinor).
  String _closingLabel(int closing) {
    if (closing == 0) return 'الرصيد الختامي: صفر — متوازن';
    final normalIsDebit = account.normalSide == NormalSide.debit;
    final positiveOnNormal = closing > 0;
    final isDebit = positiveOnNormal ? normalIsDebit : !normalIsDebit;
    final magnitude = formatMinorAmount(closing.abs());
    return 'الرصيد الختامي: $magnitude '
        '${isDebit ? 'مدين' : 'دائن'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('كشف الحساب — ${account.code}')),
      body: DiqqahAdaptiveCenter(child: FutureBuilder<AccountStatementReport>(
        future: db.accountStatementReport(account.id),
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
                      Text('${account.code} — ${account.name}'
                          ' (${account.type.label})'),
                      const SizedBox(height: 4),
                      Text('مدين: ${formatMinorAmount(r.totalDebitMinor)}'
                          ' — دائن: ${formatMinorAmount(r.totalCreditMinor)}'),
                      const SizedBox(height: 4),
                      Text(
                        _closingLabel(r.closingBalanceMinor),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: r.entries.isEmpty
                    ? Center(
                        // س225 (خ6): حالة الفراغ الحية — ولسان الشاشة
                        // القائم حرفاً.
                        child: DiqqahEmptyState(
                          icon: Icons.receipt_long_outlined,
                          message: 'لا قيود مرحّلة على الحساب',
                        ),
                      )
                    : ListView(
                        children: [
                          // س223 (المتبقي من د5): الشحنة من الأسطر كاملةً
                          // والحد بناء واجهة حصراً بعقد س221.
                          for (final e in listDisplayPage(
                              r.entries, limit: _displayLimit))
                            ListTile(
                              dense: true,
                              title: Text('${e.moveNumber} — ${e.moveDate}'),
                              subtitle: Text(
                                e.narration == null || e.narration!.isEmpty
                                    ? '—'
                                    : e.narration!,
                              ),
                              trailing: SizedBox(
                                width: 170,
                                child: Text(
                                  'مدين ${formatMinorAmount(e.debitMinor)}\n'
                                  'دائن ${formatMinorAmount(e.creditMinor)}\n'
                                  'الرصيد التراكمي: '
                                  '${formatMinorAmount(e.runningBalanceMinor)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                      height: 1.25),
                                ),
                              ),
                            ),
                          if (r.entries.length > _displayLimit)
                            listDisplayExpandButton(
                              context: context,
                              remaining:
                                  r.entries.length - _displayLimit,
                              onExpand: () => setState(() =>
                                  _displayLimit += kListDisplayPageSize),
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
