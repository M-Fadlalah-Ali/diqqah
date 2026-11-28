import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'print_service.dart';
import 'adaptive.dart';
import 'context_menu.dart';
// س223: الحد المتدرج الموحد لقوائم المستندات (المتبقي من د5).
import 'list_display.dart';
import 'empty_state.dart';
import 'input_formatters.dart';
import 'reports_screen.dart' show formatMinorAmount;
import 'currency_display.dart';
import 'hijri_display.dart';
import 'session.dart';
import 'dq_log.dart';
import 'date_picker.dart';

/// تصفية صفوف التوزيع الحية (س202 — علّة الدفع الجزئي الموثقة): كانت
/// المسودة تُرسل كل صفوف المطابقة المعروضة بما فيها غير الممسوسة
/// (المطبَّق صفر) فيرفضها حرس المجال برسالته «مطبَّق الفاتورة رقم X
/// يجب أن يكون أكبر من صفر» — فيُعاد النموذج وما أراده المالك دفعَ
/// جزءٍ حصراً (شكواه الموثقة: دفع 325 فأُلزم إعادة الإدخال مرات).
/// فالصفرية تُصفّى هنا ولا يُرسل إلا ما دخل المالك فعلاً، والحرس
/// المجالي (voucher.dart) باقٍ حارساً لما يعبر إليه — والفائض غير
/// المطابق رصيد مقدَّم على الذمة بعرفه القائم (س-12/س5).
List<VoucherAllocationDraft> liveVoucherAllocations(
    List<(int invoiceId, int appliedDocMinor)> rows) => [
      for (final (invoiceId, applied) in rows)
        if (applied > 0)
          VoucherAllocationDraft(
              invoiceId: invoiceId, appliedDocMinor: applied),
    ];

/// طباعة سند أو تحويل أو تسوية (D-016، دفعة إغلاق النواة س37) — قسيمة
/// A5 طولية (D-101 معروض) ببيانات الصف المعروضة حصراً، ومشاركتها
/// بنافذة النظام، والفشل رسالة لا صمت.
Future<void> _printVoucherDoc(
  BuildContext context, {
  DiqqahDatabase? db,
  required String title,
  required List<(String, String)> headerPairs,
  required String amountLabel,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildDocumentPdf(
      db: db,
      title: title,
      headerPairs: headerPairs,
      columns: const [],
      rows: const [],
      footerPairs: [('المبلغ', amountLabel)],
      format: resolvePageFormat(docKind: 'voucher'),
    );
    if (!context.mounted) return;
    await sharePdfBytes(bytes, '$title.pdf');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر توليد الطباعة — $e${dqTag(e)}')),
    );
  }
}

/// زر طباعة صف السند — بجوار المبلغ في نفس السطر.
Widget _voucherPrintTrailing({
  required VoidCallback onPrint,
  required String amountText,
}) =>
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'طباعة / PDF',
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: onPrint,
        ),
        Text(amountText),
      ],
    );

/// شاشة السندات والصناديق المالية — دفعة (6-ج) واجهات الإدخال
/// (س-89..س-94، D-094..D-096 معروض): ثلاث تبويبات قراءة لحظية من
/// المرحّل (السندات الطرفية وغير الطرفية، التحويلات، التسويات) ونماذج
/// إنشاء يفوض الحكم كله للمحرك — المدقق البنيوي ثم الفحوص المحركية
/// ثم حواجز القاعدة (منع السالب الموحد) — والواجهة تعرض رسائل المدقق
/// العربية كما هي.
///
/// درس CI (س36): زر الإنشاء زرٌّ واحد في Scaffold الأم يتبدل نصه وعمله
/// بالتبويب النشط — لا FAB داخل كل تبويب فتتكدس الأزرار في
/// PageView ويتحجب بعضها بعضاً في الاختبارات ولا يُضرب.
/// ودفعة الإغلاق (س37): زر طباعة / PDF بكل صف (D-016).
class VouchersScreen extends StatefulWidget {
  final DiqqahDatabase db;
  const VouchersScreen({super.key, required this.db});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  final GlobalKey<_VouchersTabState> _voucherTabKey =
      GlobalKey<_VouchersTabState>();
  final GlobalKey<_TransfersTabState> _transfersTabKey =
      GlobalKey<_TransfersTabState>();
  final GlobalKey<_AdjustmentsTabState> _adjustmentsTabKey =
      GlobalKey<_AdjustmentsTabState>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openCreate() async {
    final Widget target = switch (_tabs.index) {
      0 => VoucherEditScreen(db: widget.db),
      1 => TransferEditScreen(db: widget.db),
      _ => AdjustmentEditScreen(db: widget.db),
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
    // بعد العودة من النموذج تُحدّث قائمة التبويب المنشئ حصراً
    switch (_tabs.index) {
      case 0:
        _voucherTabKey.currentState?.reload();
      case 1:
        _transfersTabKey.currentState?.reload();
      default:
        _adjustmentsTabKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('السندات'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'السندات'),
            Tab(text: 'التحويلات'),
            Tab(text: 'التسويات'),
          ],
        ),
      ),
      // زر واحد لا ثلاثة — والنص يتبدل بالتبويب (درس CI أعلاه)
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: _openCreate,
          icon: const Icon(Icons.add_circle_outline),
          label: Text(switch (_tabs.index) {
            0 => 'سند جديد',
            1 => 'تحويل جديد',
            _ => 'تسوية جديدة',
          }),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _VouchersTab(key: _voucherTabKey, db: widget.db),
          _TransfersTab(key: _transfersTabKey, db: widget.db),
          _AdjustmentsTab(key: _adjustmentsTabKey, db: widget.db),
        ],
      ),
    );
  }
}

/// بناء القائمة القرائية الموحد للتبويبات الثلاثة — رسالة المدقق تظهر
/// لا صمتاً، والفراغ رسالة إرشاد لا شاشة خاوية (F-162 روحاً).
Widget _tabList<T>(BuildContext context, AsyncSnapshot<List<T>> snapshot,
    String emptyMessage, Widget Function(T row) builder,
    {required int displayLimit, required VoidCallback onExpand}) {
  if (snapshot.hasError) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('${snapshot.error}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    );
  }
  if (!snapshot.hasData) {
    return const Center(child: CircularProgressIndicator());
  }
  final rows = snapshot.data!;
  if (rows.isEmpty) {
    // س225 (خ6): حالة الفراغ الحية بدل النص العائم — واللسان
    // القائم لكل تبويب حرفاً فلا لسان يُبتدع هنا.
    return Center(
      child: DiqqahEmptyState(
        icon: Icons.request_quote_outlined,
        message: emptyMessage,
      ),
    );
  }
  // س208 (الدفعة 2 — الاتساق): القائمة كسولة builder بهامش التكيف
  // م06 ونهاية مساحة الزر العائم — نمط شاشة القائمة المرجعي
  // (الطلبات س122/س123) لا بناء كامل الصفوف دفعة.
  // س223 (المتبقي من د5 — أمر المالك «قم بتنفيذ المتبقي من د5
  // بالكامل»): الحد المتدرج الموحد بنمط list_display.dart على
  // التبويبات الثلاثة — القراءة كاملة كما هي والحد بناء واجهة
  // حصراً (عقد س221) وزر التوسيع بعدّاد الباقي فالوجود كله متاح
  // بالتوسع المتكرر، والطباعة القائمة (D-016) على العرض المطبَّق
  // كاملاً كما كانت — الحد للشاشة لا للورقة.
  final shown = listDisplayPage(rows, limit: displayLimit);
  final remaining = rows.length - shown.length;
  return ListView.builder(
    padding: EdgeInsets.fromLTRB(
        diqqahAdaptiveHorizontalMargin(context), 8,
        diqqahAdaptiveHorizontalMargin(context), 88),
    itemCount: shown.length + (remaining > 0 ? 1 : 0),
    itemBuilder: (context, i) => i >= shown.length
        ? listDisplayExpandButton(
            context: context, remaining: remaining, onExpand: onExpand)
        : builder(shown[i]),
  );
}

/// تبويب السندات (قبض/دفع — س-12..س-15، D-105) — القائمة الطرفية وغير الطرفية
/// معاً والمميزان بحقليهما.
class _VouchersTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _VouchersTab({super.key, required this.db});

  @override
  State<_VouchersTab> createState() => _VouchersTabState();
}

class _VouchersTabState extends State<_VouchersTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();

  /// س104: فلتر الحالة — null الكل وإلا 'held' (المعلقة — في الطريق)
  /// أو 'posted' (المرحّلة) — بلسان المعتمد الذي يبحث عن تحصيلات
  /// المندوبين (عرف فلتر الفواتير س101).
  String? _state;

  static final List<(String?, String)> _stateChoices = [
    (null, 'كل الحالات'),
    ('held', 'المعلقة — في الطريق'),
    ('posted', 'المرحّلة'),
  ];

  /// س104: جلسة صاحب القائمة — المعتمدون وحدهم يرون زرَي الاعتماد
  /// والرفض وبطاقة العهدة، والفراغ لا زر — عملُ مالٍ فسقوطه مغلق
  /// (عرف الأرشيف س101).
  SessionInfo? _session;

  /// س162: القصر التفصيلي «تحصيلاتي» — بنص س104 الموثق «عرض فوق القراءة
  /// مؤجل بترتيب المالك» (وس105 «القصر التفصيلي «تحصيلاتي» مؤجلان»):
  /// الغائب مطابق القائم حرفاً (كل السندات للجميع)، وتفعيله يقصر القائمة
  /// على ما آخر تقديمه بهوية الجلسة الحالية — عرضٌ فوق القراءة فلا شرط
  /// SQL جديد ولا حالة مخزنة ولا ترحيلة.
  bool _mineOnly = false;

  bool get _canApprove => _session?.canApproveHeldReceipts ?? false;

  /// عدّاد بطاقة العهدة — تتجدد مع كل إعادة تحميل للقائمة.
  int _custodyTick = 0;

  /// س105: لسان صف العهدة — العدد والمجموع وأقدم تحصيلاته (أعمار
  /// العهدة من طوابع التقديم لا نصاً مخزناً) وما تبقّى تحت السقف إن
  /// وُجد، والتجاوز يُعرض صادقاً (قد يخفض المالك السقف دون معلّقات
  /// قائمة فيظهر ما فوقه بلسان الواقع لا صمتاً).
  String _custodyLine(HeldCollectionCustodyRow c, int cap) {
    final buf = StringBuffer('${c.userName} — ${c.count} تحصيلات بمجموع '
        '${formatMinorAmount(c.totalBaseMinor)}');
    final age = _custodyAgeText(c.oldestSubmittedAtMs);
    if (age != null) buf.write(' — أقدمها $age');
    if (cap > 0) {
      final remaining = cap - c.totalBaseMinor;
      buf.write(remaining >= 0
          ? ' — المتباح تحت السقف ${formatMinorAmount(remaining)}'
          : ' — متجاوز السقف بـ${formatMinorAmount(-remaining)}');
    }
    return buf.toString();
  }

  /// لسان العمر بالعربية من طابع التقديم — يوم/يومين/أيام/يوماً،
  /// والفارغ (مجموعة «غير معروف») لا عمرَ له بلسان.
  String? _custodyAgeText(int? submittedAtMs) {
    if (submittedAtMs == null) return null;
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(submittedAtMs))
        .inDays;
    if (days <= 0) return 'منذ أقل من يوم';
    if (days == 1) return 'منذ يوم';
    if (days == 2) return 'منذ يومين';
    if (days <= 10) return 'منذ $days أيام';
    return 'منذ $days يوماً';
  }

  /// س162: سطر شرائح العهدة — مدخلات المانِح توزع بالدالة النقية
  /// custodyAgeSliceDistribution (حدود 0-7/8-15/16-30/فوق 30 بنص
  /// التوثيق س105) والشرائح غير الخالية بلسان واحد، والمجموعة بلا
  /// طابع («غير معروف») أو بلا مدخلات لا سطر لها (نمط F-016).
  String? _custodySlicesLine(int userId, List<HeldCustodyEntry> entries) {
    final now = DateTime.now();
    final mine = <({int ageDays, int totalBaseMinor})>[
      for (final e in entries)
        if (e.userId == userId && e.submittedAtMs != null)
          (
            ageDays: now
                .difference(DateTime.fromMillisecondsSinceEpoch(
                    e.submittedAtMs!))
                .inDays,
            totalBaseMinor: e.amountBaseMinor,
          ),
    ];
    if (mine.isEmpty) return null;
    final slices = custodyAgeSliceDistribution(mine);
    if (slices.isEmpty) return null;
    return 'شرائح العهدة: '
        '${slices.map((s) => '${s.$1}: ${s.$2} (${formatMinorAmount(s.$3)})').join(' · ')}';
  }

  Future<List<VoucherListRow>>? _rows;

  /// س223 — الحد المتدرج لقائمة التبويب (المتبقي من د5 بنمط
  /// list_display.dart): شحنة [kListDisplayPageSize] صفّاً ثم توسيع
  /// بضغطة ويصفر مع كل استعلام جديد فالفلتر المنعش يبدأ من أعلى
  /// القائمة.
  int _displayLimit = kListDisplayPageSize;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadSession();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _rows = _loadRows();
      // س223: استعلام جديد فالحد المتدرج يصفر — البدء من أعلى القائمة.
      _displayLimit = kListDisplayPageSize;
      _custodyTick++;
    });
  }

  /// س162: القائمة بفلتر الحالة من القاعدة — والقصر «تحصيلاتي» طبقة
  /// عرض فوقها بهوية آخر تقديم (voucherIdsSubmittedBy) فلا مسار موازٍ.
  Future<List<VoucherListRow>> _loadRows() async {
    final rows = await widget.db.vouchersListReport(
      fromText: _from.text.trim(),
      toText: _to.text.trim(),
      // س104: فلتر الحالة يمر للقاعدة مع البقية.
      stateFilter: _state,
    );
    if (!_mineOnly) return rows;
    final ids = await widget.db
        .voucherIdsSubmittedBy(_session?.user.id ?? 0);
    return [for (final r in rows) if (ids.contains(r.id)) r];
  }

  /// إعادة التحميل من الأم (بعد العودة من نموذج إنشاء)
  void reload() => _reload();

  /// س104: قراءة الجلسة مرة — من يملك الاعتماد يرى أدواته.
  Future<void> _loadSession() async {
    final s = await loadSession(widget.db);
    if (!mounted) return;
    setState(() => _session = s);
  }

  /// س104: نافذة تأكيد الاعتماد — الاعتماد تسليمٌ يدخل الصندوق ويُرقِّم
  /// فالقرار بضغطة واعية لا بصمت زر (عرف الفواتير س101).
  Future<bool> _confirmApprove(VoucherListRow row) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اعتماد التحصيل وتسليمه للصندوق؟'),
        content: Text(
          '${row.displayLabel} بمبلغ '
          '${formatMinorAmount(row.amountDocMinor)} ${row.currencyCode}.\n'
          'الاعتماد يدخل المبلغ صندوق «${row.boxName}» ويُمنح السند رقمه '
          'النهائي — ولا رجوع بعده إلا بمستند معاكس.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تركه معلّقاً'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('اعتماد وتسليم'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  /// س104: الاعتماد من القائمة — المحرك ذاته (approveHeldVoucher) فلا
  /// مسار موازٍ، والخطأ بلسان مدققه والنجاح تحديثاً للقائمة والعهدة.
  Future<void> _approve(VoucherListRow row) async {
    if (!await _confirmApprove(row)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.db.approveHeldVoucher(row.id);
      final posted = await widget.db.voucherById(row.id);
      messenger.showSnackBar(SnackBar(
        content: Text(posted == null || posted.number.isEmpty
            ? 'اعتمد التحصيل وسُلّم للصندوق'
            : 'اعتمد وسُلّم برقم ${posted.number}'),
      ));
      _reload();
    } on VoucherValidationException catch (e) {
      await dqLog(widget.db, e, context: 'voucher.approve');
      // الرمز DQ-1002 للسجل والمرجع لا نص المستخدم (س204 — م03).
      messenger.showSnackBar(SnackBar(
        content: Text(
          [
            for (final err in e.errors) describeVoucherValidationError(err)
          ].join('\n'),
        ),
      ));
    } catch (e) {
      await dqLog(widget.db, e, context: 'voucher.approve');
      messenger.showSnackBar(SnackBar(content: Text('$e${dqTag(e)}')));
    }
  }

  /// س104: نافذة الرفض مع سبب اختياري — الرفض عكسٌ محاسبي حرف لقيد
  /// الطريق فيعود ما حُقّق للذمة، والسبب يوثق بالحدث بلسان الرافع.
  /// والسبب يعود قيمةَ pop لا بقراءة لاحقة — فمتحكم الحقل من نافذة
  /// الحوار ولا يُلمس بعد إغلاقها (درس الاستثناء الموثق بالجولة).
  Future<void> _reject(VoucherListRow row) async {
    final reasonController = TextEditingController();
    final result = await showDialog<(bool, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض التحصيل المعلق؟'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row.displayLabel} بمبلغ '
              '${formatMinorAmount(row.amountDocMinor)} ${row.currencyCode}.\n'
              'الرفض يُقيد عكس قيد الطريق حرفاً فتعود ذمة العميل كما كانت '
              'قبل التعليق — ولا رجوع على المرفض إلا بتحصيل جديد.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'السبب (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop((false, '')),
            child: const Text('تركه معلّقاً'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop((true, reasonController.text.trim())),
            child: const Text('رفض وعكس القيد'),
          ),
        ],
      ),
    );
    if (result == null || !result.$1) return;
    final reason = result.$2;
    final session = _session;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.db.rejectHeldVoucher(
        row.id,
        userId: session?.user.id ?? 0,
        userName: session?.user.name ?? 'غير معروف',
        roleName: session?.role.name ?? '—',
        reason: reason.isEmpty ? null : reason,
      );
      messenger.showSnackBar(
          const SnackBar(content: Text('رُفض التحصيل وعُكس قيد الطريق')));
      _reload();
    } on VoucherValidationException catch (e) {
      await dqLog(widget.db, e, context: 'voucher.reject');
      // الرمز DQ-1002 للسجل والمرجع لا نص المستخدم (س204 — م03).
      messenger.showSnackBar(SnackBar(
        content: Text(
          [
            for (final err in e.errors) describeVoucherValidationError(err)
          ].join('\n'),
        ),
      ));
    } catch (e) {
      await dqLog(widget.db, e, context: 'voucher.reject');
      messenger.showSnackBar(SnackBar(content: Text('$e${dqTag(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // س235 (توحيد النمط بكلمة المالك): شريط المدى الفوري الموحد
                    // بلا زر عرض — الخمعة وحقلا من/إلى بتطبيق فوري.
                    DiqqahInstantRangeBar(
                        from: _from, to: _to, onReload: _reload),
        // س104: فلتر الحالة سطراً مستقلاً — عرف درس س67: لا حشر عنصر
        // بصف فيه Expanded فتنضغط القوائم المنسدلة.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _state,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                  items: [
                    for (final (value, label) in _stateChoices)
                      DropdownMenuItem<String>(
                          value: value, child: Text(label)),
                  ],
                  onChanged: (value) => setState(() {
                    _state = value;
                    _reload();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              // س162: القصر التفصيلي «تحصيلاتي» — عرض فوق القراءة،
              // والغائب مطابق القائم حرفاً (حارس انحدار س104).
              FilterChip(
                selected: _mineOnly,
                label: const Text('تحصيلاتي'),
                onSelected: (v) => setState(() {
                  _mineOnly = v;
                  _reload();
                }),
              ),
            ],
          ),
        ),
        // س104: بطاقة العهدة للمعتمد حصراً — من بيده الاعتماد يعلم من
        // يحمل نقد المنشأة الآن، والقراءة خالصة تتجدد مع القائمة.
        // س105: مع السقف إن وُجد — الأعمار من طوابع التقديم والمتباح
        // تحت السقف (نمط القلب: التخزين يقرأ واللسان هنا).
        if (_canApprove)
          FutureBuilder<(List<HeldCollectionCustodyRow>, int,
              List<HeldCustodyEntry>)>(
            key: ValueKey(_custodyTick),
            future: () async {
              final custody = await widget.db.heldReceiptCustody();
              final cap = await widget.db.heldReceiptCustodyCap();
              // س162: مدخلات العهدة للشرائح — قراءة خالصة موازية للصف المجمّع.
              final entries = await widget.db.heldReceiptCustodyEntries();
              return (custody, cap, entries);
            }(),
            builder: (context, snap) {
              final custody =
                  snap.data?.$1 ?? const <HeldCollectionCustodyRow>[];
              final cap = snap.data?.$2 ?? 0;
              final entries =
                  snap.data?.$3 ?? const <HeldCustodyEntry>[];
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تحصيلات في الطريق — عهدة المندوبين',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      if (custody.isEmpty)
                        Text('لا تحصيلات معلقة الآن',
                            style: Theme.of(context).textTheme.bodySmall)
                      else
                        for (final c in custody) ...[
                          Text(_custodyLine(c, cap),
                              style: Theme.of(context).textTheme.bodySmall),
                          // س162: شرائح الأعمار بنص س105 «توزيع الأعمار
                          // بشرائح (0-7/8-15/…)» — والتوزيع نقي بالتطبيق
                          // والمجموعة بلا طابع («غير معروف») لا شرائح لها.
                          if (_custodySlicesLine(c.userId, entries) != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12, bottom: 2),
                              child: Text(
                                  _custodySlicesLine(c.userId, entries)!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          fontStyle: FontStyle.italic)),
                            ),
                        ],
                    ],
                  ),
                ),
              );
            },
          ),
        Expanded(
          child: FutureBuilder<List<VoucherListRow>>(
            future: _rows,
            builder: (context, snapshot) => _tabList<VoucherListRow>(
              context,
              snapshot,
              'لا سندات بعد — أضف أول سند بزر «سند جديد»',
              (row) {
                // س208: النمط الموحد — بطاقة بقائمة سياق س207 بفعاليات
                // المضيف القائمة حصراً (الطباعة القائمة D-016) ونسخ
                // المعرّف، وأيقونة الاتجاه قبض/دفع وسطر معلومات مقصوص.
                final onPrint = () => _printVoucherDoc(
                      db: widget.db,
                      context,
                      title: row.displayLabel,
                      headerPairs: [
                        ('التاريخ', row.voucherDate),
                        ('النوع', VoucherKind.fromStorage(row.kind).label),
                        ('الحالة', row.stateLabel),
                        ('الجهة', row.counterpartLabel),
                        ('الصندوق', row.boxName),
                        if (row.narration != null &&
                            row.narration!.isNotEmpty)
                          ('البيان', row.narration!),
                      ],
                      amountLabel:
                          '${formatMinorAmount(row.amountDocMinor)} '
                              '${row.currencyCode}',
                    );
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: RecordContextMenu(
                    actions: [
                      RecordContextAction(
                        label: 'طباعة السند',
                        icon: Icons.print_outlined,
                        onSelected: onPrint,
                      ),
                      copyIdAction(context, row.id),
                    ],
                    child: ListTile(
                      leading: Icon(
                          VoucherKind.fromStorage(row.kind) ==
                                  VoucherKind.receipt
                              ? Icons.south_west_outlined
                              : Icons.north_east_outlined),
                      title: Text(row.displayLabel),
                      subtitle: Text('${row.voucherDate}'
                          ' · ${row.counterpartLabel}'
                          ' · ${row.boxName}'
                          ' · ${row.stateLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // س104: زرا الاعتماد والرفض على المعلق للمعتمدين
                          // حصراً — نفس المحرك لا مسار موازٍ، والمعلّق لا
                          // يرى أدوات الاعتماد أصلاً.
                          if (row.state == 'held' && _canApprove) ...[
                            IconButton(
                              tooltip: 'اعتماد وتسليم للصندوق',
                              icon: const Icon(Icons.task_alt_outlined),
                              onPressed: () => _approve(row),
                            ),
                            IconButton(
                              tooltip: 'رفض وعكس القيد',
                              icon: const Icon(Icons.cancel_outlined),
                              onPressed: () => _reject(row),
                            ),
                          ],
                          _voucherPrintTrailing(
                            amountText:
                                '${formatMinorAmount(row.amountDocMinor)}'
                                ' ${row.currencyCode}',
                            onPrint: onPrint,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              displayLimit: _displayLimit,
              onExpand: () => setState(
                  () => _displayLimit += kListDisplayPageSize),
            ),
          ),
        ),
      ],
    );
  }
}

/// تبويب التحويلات بين الصناديق (س-16/D-087 معتمد) — القيد بسطرين
/// «صندوق المستلم مدين / صندوق المرسل دائن» والقراءة تعرض الطرفين.
class _TransfersTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _TransfersTab({super.key, required this.db});

  @override
  State<_TransfersTab> createState() => _TransfersTabState();
}

class _TransfersTabState extends State<_TransfersTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  Future<List<BoxTransferListRow>>? _rows;

  /// س223 — الحد المتدرج لقائمة التبويب (المتبقي من د5 بنمط
  /// list_display.dart): شحنة [kListDisplayPageSize] صفّاً ثم توسيع
  /// بضغطة ويصفر مع كل استعلام جديد فالفلتر المنعش يبدأ من أعلى
  /// القائمة.
  int _displayLimit = kListDisplayPageSize;

  @override
  bool get wantKeepAlive => true;

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
      // س223: استعلام جديد فالحد المتدرج يصفر — البدء من أعلى القائمة.
      _displayLimit = kListDisplayPageSize;
      _rows = widget.db.boxTransfersListReport(
          fromText: _from.text.trim(), toText: _to.text.trim());
    });
  }

  /// إعادة التحميل من الأم (بعد العودة من نموذج إنشاء)
  void reload() => _reload();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // س235 (توحيد النمط بكلمة المالك): شريط المدى الفوري الموحد
                    // بلا زر عرض — الخمعة وحقلا من/إلى بتطبيق فوري.
                    DiqqahInstantRangeBar(
                        from: _from, to: _to, onReload: _reload),
        Expanded(
          child: FutureBuilder<List<BoxTransferListRow>>(
            future: _rows,
            builder: (context, snapshot) => _tabList<BoxTransferListRow>(
              context,
              snapshot,
              'لا تحويلات بعد — أضف أول تحويل بزر «تحويل جديد»',
              (row) {
                // س208: النمط الموحد — بطاقة بقائمة سياق س207 وأيقونة
                // الاتجاه وسطر معلومات مقصوص (نمط الطلبات).
                final onPrint = () => _printVoucherDoc(
                      db: widget.db,
                      context,
                      title: row.displayLabel,
                      headerPairs: [
                        ('التاريخ', row.transferDate),
                        ('الحالة', row.stateLabel),
                        ('من صندوق', row.fromBoxName),
                        ('إلى صندوق', row.toBoxName),
                      ],
                      amountLabel:
                          '${formatMinorAmount(row.amountDocMinor)} '
                              '${row.currencyCode}',
                    );
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: RecordContextMenu(
                    actions: [
                      RecordContextAction(
                        label: 'طباعة التحويل',
                        icon: Icons.print_outlined,
                        onSelected: onPrint,
                      ),
                      copyIdAction(context, row.id),
                    ],
                    child: ListTile(
                      leading: const Icon(Icons.swap_horiz_outlined),
                      title: Text(row.displayLabel),
                      subtitle: Text('${row.transferDate}'
                          ' · من ${row.fromBoxName}'
                          ' · إلى ${row.toBoxName}'
                          ' · ${row.stateLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: _voucherPrintTrailing(
                        amountText:
                            '${formatMinorAmount(row.amountDocMinor)}'
                            ' ${row.currencyCode}',
                        onPrint: onPrint,
                      ),
                    ),
                  ),
                );
              },
              displayLimit: _displayLimit,
              onExpand: () => setState(
                  () => _displayLimit += kListDisplayPageSize),
            ),
          ),
        ),
      ],
    );
  }
}

/// تبويب تسويات الصناديق (س-17/F-067) — الاتجاه والسبب الظاهران بالصف.
class _AdjustmentsTab extends StatefulWidget {
  final DiqqahDatabase db;

  const _AdjustmentsTab({super.key, required this.db});

  @override
  State<_AdjustmentsTab> createState() => _AdjustmentsTabState();
}

class _AdjustmentsTabState extends State<_AdjustmentsTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  Future<List<CashAdjustmentListRow>>? _rows;

  /// س223 — الحد المتدرج لقائمة التبويب (المتبقي من د5 بنمط
  /// list_display.dart): شحنة [kListDisplayPageSize] صفّاً ثم توسيع
  /// بضغطة ويصفر مع كل استعلام جديد فالفلتر المنعش يبدأ من أعلى
  /// القائمة.
  int _displayLimit = kListDisplayPageSize;

  @override
  bool get wantKeepAlive => true;

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
      // س223: استعلام جديد فالحد المتدرج يصفر — البدء من أعلى القائمة.
      _displayLimit = kListDisplayPageSize;
      _rows = widget.db.cashAdjustmentsListReport(
          fromText: _from.text.trim(), toText: _to.text.trim());
    });
  }

  /// إعادة التحميل من الأم (بعد العودة من نموذج إنشاء)
  void reload() => _reload();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // س235 (توحيد النمط بكلمة المالك): شريط المدى الفوري الموحد
                    // بلا زر عرض — الخمعة وحقلا من/إلى بتطبيق فوري.
                    DiqqahInstantRangeBar(
                        from: _from, to: _to, onReload: _reload),
        Expanded(
          child: FutureBuilder<List<CashAdjustmentListRow>>(
            future: _rows,
            builder: (context, snapshot) => _tabList<CashAdjustmentListRow>(
              context,
              snapshot,
              'لا تسويات بعد — أضف أول تسوية بزر «تسوية جديدة»',
              (row) {
                // س208: النمط الموحد — بطاقة بقائمة سياق س207 وأيقونة
                // الاتجاه وسطر معلومات مقصوص (نمط الطلبات).
                final onPrint = () => _printVoucherDoc(
                      db: widget.db,
                      context,
                      title: row.displayLabel,
                      headerPairs: [
                        ('التاريخ', row.adjustmentDate),
                        ('الحالة', row.stateLabel),
                        ('الصندوق', row.boxName),
                        ('الاتجاه', row.directionLabel),
                        ('السبب', row.reason),
                      ],
                      amountLabel:
                          '${formatMinorAmount(row.amountDocMinor)} '
                              '${row.currencyCode}',
                    );
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: RecordContextMenu(
                    actions: [
                      RecordContextAction(
                        label: 'طباعة التسوية',
                        icon: Icons.print_outlined,
                        onSelected: onPrint,
                      ),
                      copyIdAction(context, row.id),
                    ],
                    child: ListTile(
                      leading: const Icon(Icons.balance_outlined),
                      title: Text(row.displayLabel),
                      subtitle: Text('${row.adjustmentDate}'
                          ' · ${row.boxName}'
                          ' · ${row.directionLabel}'
                          ' · السبب: ${row.reason}'
                          ' · ${row.stateLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: _voucherPrintTrailing(
                        amountText:
                            '${formatMinorAmount(row.amountDocMinor)}'
                            ' ${row.currencyCode}',
                        onPrint: onPrint,
                      ),
                    ),
                  ),
                );
              },
              displayLimit: _displayLimit,
              onExpand: () => setState(
                  () => _displayLimit += kListDisplayPageSize),
            ),
          ),
        ),
      ],
    );
  }
}

/// حالة حقل مطابقة — تحكم نصي لكل فاتورة مفتوحة يعبئه المستخدم
/// أو المقترح الآلي بالأقدمية.
class _AllocationUi {
  final int invoiceId;
  final String label;
  final int remainingDocMinor;
  final TextEditingController applied = TextEditingController();

  _AllocationUi({
    required this.invoiceId,
    required this.label,
    required this.remainingDocMinor,
  });

  void dispose() {
    applied.dispose();
  }
}

/// نموذج سند قبض/دفع (س-89/س-90، D-105): الطرفي بمطابقاته «يدوياً أو آلياً
/// بالأقدمية مع إمكانية التعديل» (05 §4.2/م-21) والفائض غير المطابق
/// «رصيد مقدَّم» على الذمة (س-12/س5)؛ وبغير طرف على حساب مباشر (311
/// ضخ رأس مال — 321 مسحوبات — 54x مصروف) بلا دخول الإيرادات (س-13/س-15).
class VoucherEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// س203: تعبئة الطرف من «+» كشف حساب الطرف — الطرف المعبأ يحدد
  /// جهة السند (عميل يفتح القبض ومورد الصرفَ — خريطة الذمم 05 §5)
  /// بضغطة أقل، وعرف النوع بالضغط الصريح باقٍ (س-163). الغائب
  /// نموذج حر كما كان حرفاً.
  final int? initialPartyId;

  const VoucherEditScreen({
    super.key,
    required this.db,
    this.initialPartyId,
  });

  @override
  State<VoucherEditScreen> createState() => _VoucherEditScreenState();
}

class _VoucherEditScreenState extends State<VoucherEditScreen> {
  VoucherKind _kind = VoucherKind.receipt;
  bool _partyVoucher = true;
  int? _boxId;
  int? _partyId;
  int? _directAccountId;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _narration = TextEditingController();

  List<CashBoxReportRow> _boxes = [];
  List<Party> _parties = [];
  List<AccountInfo> _accounts = [];
  List<CurrencyRow> _currencies = [];

  /// لقطة صرف السند لغير الأساسية — الافتراضي لقطة الأساسية المحايدة
  /// (D-082)، وحقلها يظهر إذا كانت عملة الصندوق غير الأساسية.
  final TextEditingController _fx = TextEditingController();

  List<_AllocationUi> _allocations = [];
  List<String>? _errors;
  bool _busy = false;

  /// بوابة التحميل — فقيم الحقول الابتدائية جاهزة قبل أول بناء
  /// (نمط items_screen الموثق بالـinitialValue).
  bool _loaded = false;

  /// س104: جلسة صاحب النموذج — أدوار تعلق قبضها («مندوب») لا ترى منسدلَي
  /// النوع والجهة أصلاً (قبض طرفي حصراً — بوابة لا تفشل على الحفظ بل
  /// لا تُعرض) ولا «حفظ وترحيل» بل «حفظ وإرسال للاعتماد» بالمحرك
  /// createHeldVoucher، والفراغ سقوط آمن بعرف الرئيسية (السلوك القديم
  /// بلا دور).
  SessionInfo? _session;

  bool get _holdsForApproval => _session?.holdsReceiptsForApproval ?? false;

  /// س105: سقف العهدة وما استهلكه المانِح منه — لسان «المتباح» في
  /// نموذج المعلّق قبل أن يفصل المحرك (الإظهار قبل الفصل F-016)،
  /// والصفر بلا سقف فلا لسان (سلوك س104 القائم افتراضاً).
  int _custodyCap = 0;
  int _custodyUsed = 0;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ الافتراضي بتاريخ اليوم قابلاً للتعديل —
    // ويذهب جذر درس س-90 (حفظ بتاريخ فارغ) — والنماذج الثلاثة.
    _date.text = todayIsoDate();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    final parties = await widget.db.select(widget.db.parties).get();
    final accounts = await widget.db.allLedgerAccounts();
    final currencies = await widget.db.currenciesOf();
    // أرصدة الأطراف الجارية (س-105/D-106) — قراءة خالصة من تقرير الذمم.
    final balances = await widget.db.receivablesPayablesReport();
    // س104: الجلسة مع القراءات الأولى — من في الدخول يحدد النموذج كله.
    final session = await loadSession(widget.db);
    // س105: السقف وعهدة المانِح الحالية — لنموذج المعلّق حصراً،
    // ولسان المتباح من القراءتين لا من نص مخزن (نمط القلب).
    final custodyCap = await widget.db.heldReceiptCustodyCap();
    final custodyUsed =
        session != null && session.holdsReceiptsForApproval
            ? await widget.db.heldCustodyTotalOf(session.user.id)
            : 0;
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _parties = parties.where((p) => p.isActive).toList();
      _accounts = accounts.where((a) => a.isActive && a.isLeaf).toList();
      _currencies = currencies;
      _session = session;
      _custodyCap = custodyCap;
      _custodyUsed = custodyUsed;
      _partyBalances
        ..clear()
        ..addEntries([for (final r in balances) MapEntry(r.partyId, r)]);
      // الصندوق الافتراضي أول الصناديق النشطة — سطر استُردّ بالجولة #394
      // (علّة تحرير س203: كان محوَلاً بحذفه عند زرع كتلة تعبئة الطرف
      // فبقي الصندوق بلا اختيار: لا «الرصيد الآن» (س-121/D-116) ولا
      // مطابقات الطرف (س-90) ولا حفظَ المندوب المعلق وسقف عهدته
      // (س104/س105) — فالمسودة cashBoxId=0 يرفضها المحرك برسالته).
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      // س203: تعبئة الطرف من «+» الكشف — والغائب بالأطراف النشطة
      // يُسقط صامتاً فلا قيمة فانتقائية بالقائمة ولا انكسار.
      final initialParty = widget.initialPartyId;
      if (initialParty != null) {
        final matches =
            _parties.where((p) => p.id == initialParty).toList();
        if (matches.isNotEmpty) {
          final p = matches.first;
          // العميل يفتح القبض عرف النموذج، والمورد يقلب النوع للصرف
          // (خريطة الذمم 05 §5) — ولا جهة يفتح نموذجاً فانتقائياً.
          if (p.kind == 'supplier') {
            _kind = VoucherKind.payment;
          }
          if (p.kind == (_kind.isReceipt ? 'customer' : 'supplier')) {
            _partyId = p.id;
          }
        }
      }
      _loaded = true;
    });
    // س203: المطابقات للطرف المعبأ تُبنى فوراً لا بانتظار تغيير يدوي —
    // المقترحات بيد المستخدم ولا تُحسب سواها (س-163 روحاً).
    if (_partyId != null) {
      await _reloadOpenInvoices();
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _narration.dispose();
    _fx.dispose();
    for (final a in _allocations) {
      a.dispose();
    }
    super.dispose();
  }

  /// عملة الصندوق المختار — سند الصندوق بعملته حصراً (D-086 معتمد).
  CashBoxReportRow? get _box {
    for (final b in _boxes) {
      if (b.boxId == _boxId) return b;
    }
    return null;
  }

  CurrencyRow _currencyOf(CashBoxReportRow box) {
    for (final c in _currencies) {
      if (c.code == box.currencyCode) return c;
    }
    return _currencies.first;
  }

  /// الحسابات المباشرة المتاحة — الورقية النشطة دون حسابات الصناديق
  /// (111x): المحرك يمنعها برسالته فلا تُعرض أصلاً (س-13/س-15).
  List<AccountInfo> get _directChoices => _accounts
      .where((a) => !a.code.startsWith('111') && a.isLeaf && a.isActive)
      .toList();

  /// أطراف جهة السند: القبض عملاء والدفع موردون (خريطة الذمم 05 §5).
  List<Party> get _sideParties => _parties
      .where((p) => p.kind == (_kind.isReceipt ? 'customer' : 'supplier'))
      .toList();

  /// رصيد الطرف الجاري (س-105/D-106) — من تقرير الذمم ذاته (المرحّل
  /// حصراً) — بالاتجاهين: هم يدينون لنا أو نحن ندن له.
  final Map<int, ReceivablesPayablesRow> _partyBalances = {};

  /// صياغة الرصيد المعروضة: «50,000 لنا» أو «نحن ندن له بـ20,000» —
  /// والطرف بلا ذمة صف «بلا ذمة بعد» (الصفر يخرج من التقرير أصلاً).
  String _partyBalanceText(int partyId) {
    final row = _partyBalances[partyId];
    if (row == null) return 'بلا ذمة بعد';
    return switch (row.direction) {
      PartyBalanceDirection.theyOweUs =>
        'لنا ${formatMinorAmount(row.amountMinor)}',
      PartyBalanceDirection.weOweThem =>
        'نحن ندن له بـ${formatMinorAmount(row.amountMinor)}',
    };
  }

  /// الفواتير المفتوحة للطرف بعملة الصندوق — وحقول المطابقة تُبنى
  /// من جديد عند كل تحميل (المسودات مقترحات لا تُحسب).
  Future<void> _reloadOpenInvoices() async {
    final box = _box;
    if (!_partyVoucher || _partyId == null || box == null) {
      if (mounted) {
        setState(() {
          for (final a in _allocations) {
            a.dispose();
          }
          _allocations = [];
        });
      }
      return;
    }
    final currency = _currencyOf(box);
    final open = await widget.db.openInvoicesForParty(
      kind: _kind,
      partyId: _partyId!,
      currencyId: currency.id,
    );
    if (!mounted) return;
    setState(() {
      for (final a in _allocations) {
        a.dispose();
      }
      _allocations = [
        for (final c in open)
          _AllocationUi(
            invoiceId: c.invoiceId,
            label:
                '${c.number} — متبقٍ ${formatMinorAmount(c.remainingDocMinor)}'
                ' (${displayDate(c.dateText)})',
            remainingDocMinor: c.remainingDocMinor,
          ),
      ];
    });
  }

  /// المقترح الآلي بالأقدمية (proposeOldestAllocations عبر المرحّل) —
  /// يعبئ الحقول ويبقى كل حقل قابلاً للتعديل (م-21: يدوياً أو آلياً
  /// مع إمكانية التعديل).
  Future<void> _proposeAutomatically() async {
    final box = _box;
    if (_partyId == null || box == null) return;
    // D-102: الحقل مفصول أثناء الكتابة — والقراءة تنزع الفواصل
    // (كسر CI س39: int.tryParse على «30,000» صفر فتوقف المقترح بلا تعبئة)
    final amount = parseGroupedInt(_amount.text.trim());
    if (amount <= 0) return;
    final currency = _currencyOf(box);
    final proposed = await widget.db.proposeVoucherAllocations(
      kind: _kind,
      partyId: _partyId!,
      currencyId: currency.id,
      amountDocMinor: amount,
    );
    if (!mounted) return;
    for (final a in _allocations) {
      a.applied.clear();
    }
    for (final p in proposed) {
      for (final a in _allocations) {
        if (a.invoiceId == p.invoiceId) {
          // مفصولاً (D-102): التعبئة البرمجية تعرض بالفواصل كالكتابة.
          a.applied.text = groupDigits(p.appliedDocMinor);
        }
      }
    }
    setState(() {});
  }

  int get _appliedTotal {
    var total = 0;
    for (final a in _allocations) {
      total += parseGroupedInt(a.applied.text.trim());
    }
    return total;
  }

  int get _amountValue => parseGroupedInt(_amount.text.trim());

  /// لقطة صرف السند — عملة الصندوق الأساسية لقطتها المحايدة (D-082)
  /// وغيرها من الحقل، والفراغ صفر يلتقطه المدقق برسالته.
  int get _fxValue {
    final box = _box;
    if (box == null) return baseCurrencyFxRate;
    return _currencyOf(box).isBase
        ? baseCurrencyFxRate
        : (parseGroupedInt(_fx.text.trim()));
  }

  /// تعبئة لقطة الصرف من آخر سعر مسجل بالجدول (F-121/D-194) — الجدول
  /// يملأ الافتراض فحسب والحقل المكتوب يدوياً لا يُمس (D-070 اللقطة
  /// اليدوية باقية) وبلا سجل يبقى الحقل فارغاً ليدخله المالك.
  Future<void> _prefillFxFromLedger() async {
    final box = _box;
    if (box == null) return;
    final currency = _currencyOf(box);
    if (currency.isBase) return;
    if (_fx.text.trim().isNotEmpty) return;
    final rate = await widget.db.latestExchangeRate(currency.id);
    if (!mounted || rate == null) return;
    if (_fx.text.trim().isNotEmpty) return;
    setState(() => _fx.text = '${rate.rateToBase}');
  }

  VoucherDraft _buildDraft() {
    return VoucherDraft(
      kind: _kind,
      dateText: _date.text.trim(),
      partyId: _partyVoucher ? _partyId : null,
      directAccountId: _partyVoucher ? null : _directAccountId,
      cashBoxId: _boxId ?? 0,
      currencyId: _box == null ? 1 : _currencyOf(_box!).id,
      fxRate: _fxValue,
      amountDocMinor: _amountValue,
      narration: _narration.text.trim().isEmpty ? null : _narration.text.trim(),
      // س202: الصفوف الصفرية غير الممسوسة لا تُرسل — liveVoucherAllocations
      // أعلاه — فيستقيم الدفع الجزئي والمطابقة الآلية بالأقدمية معاً،
      // والحرس المجالي باقٍ على ما يعبر.
      allocations: liveVoucherAllocations([
        for (final a in _allocations)
          (
            a.invoiceId,
            // D-102: الحقل مفصول — والقراءة تنزع الفواصل (كسر CI جولة
            // 114: رسالة المدقق الحرفية «مطبَّق الفاتورة رقم 2 يجب أن
            // يكون أكبر من صفر» كشفتها بطاقة الرسائل المعادة للنافذة)
            parseGroupedInt(a.applied.text.trim()),
          )
      ]),
    );
  }

  Future<void> _save({required bool post}) async {
    if (_busy) return;
    final draft = _buildDraft();
    final structure = validateVoucherDraftStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure) describeVoucherValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      // س104: المعلّق مساره الوحيد createHeldVoucher — قبضه يُقيد على
      // حساب الطريق لحظة الحفظ ولا يدخل الصندوق ولا يُرقَّم إلا
      // باعتماد صاحب الصلاحية، بهوية المانِح من الجلسة (عرف س101).
      if (_holdsForApproval) {
        final s = _session!;
        await widget.db.createHeldVoucher(
          draft,
          userId: s.user.id,
          userName: s.user.name,
          roleName: s.role.name,
        );
      } else {
        final id = await widget.db.createVoucherDraft(draft);
        if (post) {
          await widget.db.postVoucher(id);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on VoucherValidationException catch (e) {
      await dqLog(widget.db, e, context: 'voucher.save');
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeVoucherValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'voucher.save');
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
        appBar: AppBar(title: Text('سند جديد')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final directChoices = _directChoices;
    final box = _box;
    final unapplied = _amountValue - _appliedTotal;
    return Scaffold(
      appBar: AppBar(title: const Text('سند جديد')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          // م06 التكيفي لويندوز (س205): العريض يتوسّط بعرضه الأقصى
          // والضيّق بهامشه الأساسي كما كان حرفاً — بنماذج السندات الثلاثة.
          : ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: diqqahAdaptiveHorizontalMargin(context),
                  vertical: 12),
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
                // س104: أدوار تعلق قبضها («مندوب») لا ترى منسدلَي النوع
                // والجهة أصلاً — القبض الطرفي حصراً فرضٌ مسبق لا خيار
                // يُعطَّل (بوابة لا تفشل بل لا تُعرض — عرف س101).
                if (!_holdsForApproval)
                  DropdownButtonFormField<String>(
                    initialValue: _kind.storageValue,
                    decoration: const InputDecoration(labelText: 'نوع السند'),
                    items: [
                      for (final k in VoucherKind.values)
                        DropdownMenuItem<String>(
                            value: k.storageValue, child: Text(k.label)),
                    ],
                    onChanged: (value) => setState(() {
                      _kind = VoucherKind.values
                          .firstWhere((k) => k.storageValue == value);
                      _partyId = null;
                    }),
                  ),
                if (!_holdsForApproval)
                  DropdownButtonFormField<bool>(
                    initialValue: _partyVoucher,
                    decoration: const InputDecoration(
                        labelText: 'الجهة (طرفية أو بغير طرف)'),
                    items: const [
                      DropdownMenuItem<bool>(value: true, child: Text('طرفي')),
                      DropdownMenuItem<bool>(
                          value: false, child: Text('بغير طرف — حساب مباشر')),
                    ],
                    onChanged: (value) =>
                        setState(() => _partyVoucher = value ?? true),
                  ),
                if (_partyVoucher)
                  DropdownButtonFormField<int>(
                    initialValue: _partyId,
                    decoration: InputDecoration(
                        labelText: _kind.isReceipt
                            ? 'العميل (القبض على ذمم العملاء)'
                            : 'المورد (الدفع من ذمم الموردين)'
                                ''),
                    items: [
                      for (final p in _sideParties)
                        DropdownMenuItem<int>(
                            value: p.id,
                            child: Text('${p.number} ${p.name} — '
                                '${_partyBalanceText(p.id)}')),
                    ],
                    onChanged: (value) {
                      setState(() => _partyId = value);
                      _reloadOpenInvoices();
                    },
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: _directAccountId,
                    decoration: const InputDecoration(
                        labelText:
                            'الحساب المباشر (311 ضخ — 321 مسحوبات — 54x مصروف)'),
                    items: [
                      for (final a in directChoices)
                        DropdownMenuItem<int>(
                            value: a.id, child: Text('${a.code} ${a.name}')),
                    ],
                    onChanged: (value) =>
                        setState(() => _directAccountId = value),
                  ),
                DropdownButtonFormField<int>(
                  initialValue: _boxId,
                  decoration: const InputDecoration(
                      labelText: 'الصندوق — وعمله سند العملة'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) {
                    setState(() => _boxId = value);
                    _prefillFxFromLedger();
                    _reloadOpenInvoices();
                  },
                ),
                if (_box != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      // س-121 (D-116): رصيد الصندوق المختار قبل الحفظ —
                      // بنفس سطر الفاتورة النقدية (س-105/D-106) — بلفظ
                      // المالك «رصيد الصندوق في السندات غير موجود»،
                      // ويتجدد مع تبديل الصندوق (القائمة محملة بأرصدتها).
                      'الرصيد الآن: ${formatMinorAmount(_box!.balanceBaseMinor)} $kBaseCurrencySymbol',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                      labelText: 'التاريخ (YYYY-MM-DD)',
                      suffixIcon: calendarPickerSuffix(context, _date)),
                ),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  // تصويب الجولة #401 (علّة حية كشفها التشخيص الذاتي
                  // بالجولتين #400/#401): المعاينة تُقيّم وقت البناء
                  // حصراً والكتابة بالمتحكّم تحدثه دون إعادة بناء فبقيت
                  // المعاينة على حالة آخر setState — ف«لحظة الكتابة»
                  // الموعودة بس204 تتطلب النبض ذاته بنمط الفواتير
                  // (onChanged → setState) — وهو يحيي المتبقي عن
                  // المطابقات أيضاً.
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: 'المبلغ بوحدة صغرى'),
                ),
                // س204 (م01 مرحلته الأولى — معاينات «تعادل»): المكافئ
                // بالأساسية لحظة الكتابة حين الصندوق بغير العملة
                // الأساسية — بحساب المجال ذاته convertToBaseMinor بلقطة
                // السند المعتمدة (لا حساب عرض جديد) — وبعملة الأساس لا
                // معاينة (المكافئ = المبلغ — س-159/D-157 بنفس العرف).
                if (box != null &&
                    !_currencyOf(box).isBase &&
                    _amountValue > 0 &&
                    _fxValue > 0)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'تعادل ${groupDigits(convertToBaseMinor(_amountValue, _fxValue))} '
                      '$kBaseCurrencySymbol بالأساسية',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_partyVoucher && _partyId != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'رصيد حسابه الجاري: ${_partyBalanceText(_partyId!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (box != null && !_currencyOf(box).isBase)
                  TextField(
                    controller: _fx,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
                    // ونفس النبض للقطة الصرف — يديةً كانت أو معبأة آلياً —
                    // فالمعاينة تقرأها وقت البناء (درس الجولة #401).
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText:
                            'لقطة الصرف مكبرة ×1,000,000 (مثال: 15000000 = 15)'),
                  ),
                if (_partyVoucher) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _proposeAutomatically,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('اقتراح المطابقة آلياً بالأقدمية'),
                    ),
                  ),
                  if (_allocations.isEmpty && _partyId != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          'لا فواتير مفتوحة لهذا الطرف بعملة الصندوق — المبلغ كله «رصيد مقدَّم»'),
                    ),
                  for (final a in _allocations)
                    ListTile(
                      dense: true,
                      title: Text(a.label),
                      subtitle: TextField(
                        controller: a.applied,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsSeparatorInputFormatter()],
                        decoration: const InputDecoration(
                            labelText: 'المطبَّق بوحدة صغرى'),
                      ),
                    ),
                  if (_allocations.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'المطبَّق ${formatMinorAmount(_appliedTotal)}'
                          ' — الفائض (رصيد مقدَّم) ${formatMinorAmount(unapplied < 0 ? 0 : unapplied)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                ],
                TextField(
                  controller: _narration,
                  decoration:
                      const InputDecoration(labelText: 'الوصف (اختياري)'),
                ),
                const SizedBox(height: 8),
                // س104: لسان الدور قبل الحفظ — بلسان الحقيقة المحاسبية:
                // التحصيل يُقيد على حساب الطريق وتصفو ذمة العميل بوقوع
                // القبض، ولا صندوق ولا رقم إلا بالاعتماد (إظهار الواقع F-016).
                if (_holdsForApproval)
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'بدور «${_session!.role.name}»: يُحفظ التحصيل معلّقاً '
                            'في «تحصيلات في الطريق» — يُقيد لحظة الحفظ على حساب '
                            'الطريق وتصفو ذمة العميل، ولا يدخل الصندوق النقدي '
                            'ولا يُمنح رقمه إلا باعتماده وتسليمه من صاحب الصلاحية.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          // س105: لسان المتباح تحت السقف قبل أن يفصل
                          // المحرك — والفوق السقف (سقف خُفض دون معلّقات
                          // قائمة) يُعرض صادقاً بلسان التسليم أولاً.
                          if (_custodyCap > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              _custodyCap > _custodyUsed
                                  ? 'سقف العهدة ${formatMinorAmount(_custodyCap)} — '
                                      'المتباح لتحصيل جديد '
                                      '${formatMinorAmount(_custodyCap - _custodyUsed)}'
                                  : 'عهدتك الحالية '
                                      '${formatMinorAmount(_custodyUsed)} فوق '
                                      'السقف ${formatMinorAmount(_custodyCap)} — '
                                      'سلّم تحصيلاتك أولاً',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                // س104: المعلّق زره الوحيد «حفظ وإرسال للاعتماد» — لا زر
                // ترحيل أصلاً (بوابة لا تفشل بل لا تُعرض)، وغيره كما كان.
                if (_holdsForApproval)
                  FilledButton(
                    onPressed: () => _save(post: false),
                    child: const Text('حفظ وإرسال للاعتماد'),
                  )
                else
                  FilledButton(
                    onPressed: () => _save(post: true),
                    child: const Text('حفظ وترحيل'),
                  ),
              ],
            ),
    );
  }
}

/// نموذج تحويل بين صندوقين (س-91/س-16): قيد سطرين بلا وسيط (D-087
/// معتمد) والعملة واحدة على الطرفين — وحاجز القاعدة يمنع سالب المرسل
/// (منع السالب الموحد 05 §7-2) برسالته العربية.
class TransferEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const TransferEditScreen({super.key, required this.db});

  @override
  State<TransferEditScreen> createState() => _TransferEditScreenState();
}

class _TransferEditScreenState extends State<TransferEditScreen> {
  int? _fromBoxId;
  int? _toBoxId;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _narration = TextEditingController();

  /// لقطة صرف التحويل لغير الأساسية — الصندوقان بعملتهما الواحدة
  /// (D-087 معتمد) واللقطة لحظة العملية (F-122/D-082).
  final TextEditingController _fx = TextEditingController();

  List<CashBoxReportRow> _boxes = [];
  List<CurrencyRow> _currencies = [];
  List<String>? _errors;
  bool _busy = false;

  /// بوابة التحميل — نمط initialValue الموثق.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ الافتراضي — نموذج التحويل.
    _date.text = todayIsoDate();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    final currencies = await widget.db.currenciesOf();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _currencies = currencies;
      _fromBoxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _toBoxId = _boxes.length < 2 ? null : _boxes[1].boxId;
      _loaded = true;
    });
  }

  CashBoxReportRow? get _fromBox {
    for (final b in _boxes) {
      if (b.boxId == _fromBoxId) return b;
    }
    return null;
  }

  CashBoxReportRow? get _toBox {
    for (final b in _boxes) {
      if (b.boxId == _toBoxId) return b;
    }
    return null;
  }

  CurrencyRow _currencyOf(CashBoxReportRow box) {
    for (final c in _currencies) {
      if (c.code == box.currencyCode) return c;
    }
    return _currencies.first;
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _narration.dispose();
    _fx.dispose();
    super.dispose();
  }

  CashTransferDraft _buildDraft() {
    final from = _fromBox;
    return CashTransferDraft(
      dateText: _date.text.trim(),
      fromBoxId: _fromBoxId ?? 0,
      toBoxId: _toBoxId ?? 0,
      // العملة الواحدة على الطرفين من عملة صندوق «من» — والتحويل بين
      // عملتين مؤجل (D-087 معتمد) فيمسكه المدقق برسالته.
      currencyId: from == null ? 1 : _currencyOf(from).id,
      fxRate: from == null
          ? baseCurrencyFxRate
          : (_currencyOf(from).isBase
              ? baseCurrencyFxRate
              : parseGroupedInt(_fx.text.trim())),
      amountDocMinor: parseGroupedInt(_amount.text.trim()),
      narration: _narration.text.trim().isEmpty ? null : _narration.text.trim(),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final draft = _buildDraft();
    final structure = validateCashTransferStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure) describeCashTransferValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final id = await widget.db.createCashTransferDraft(draft);
      await widget.db.postCashTransfer(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CashTransferValidationException catch (e) {
      await dqLog(widget.db, e, context: 'box.transfer');
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeCashTransferValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'box.transfer');
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
        appBar: AppBar(title: Text('تحويل بين صناديق')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('تحويل بين صناديق')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          // م06 التكيفي لويندوز (س205): العريض يتوسّط بعرضه الأقصى
          // والضيّق بهامشه الأساسي كما كان حرفاً — بنماذج السندات الثلاثة.
          : ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: diqqahAdaptiveHorizontalMargin(context),
                  vertical: 12),
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
                DropdownButtonFormField<int>(
                  initialValue: _fromBoxId,
                  decoration:
                      const InputDecoration(labelText: 'من صندوق (المرسل)'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) => setState(() => _fromBoxId = value),
                ),
                if (_fromBox != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      // س-122 (D-117): رصيد الصندوقين قبل التحويل —
                      // إضافة المستشار المعتمدة ببوابة دفعة (9).
                      'الرصيد الآن: ${formatMinorAmount(_fromBox!.balanceBaseMinor)} $kBaseCurrencySymbol',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                DropdownButtonFormField<int>(
                  initialValue: _toBoxId,
                  decoration:
                      const InputDecoration(labelText: 'إلى صندوق (المستلم)'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) => setState(() => _toBoxId = value),
                ),
                if (_toBox != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      // س-122 (D-117): رصيد المستلم قبل التحويل —
                      // موازن سطر المرسل أعلاه.
                      'الرصيد الآن: ${formatMinorAmount(_toBox!.balanceBaseMinor)} $kBaseCurrencySymbol',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                      labelText: 'التاريخ (YYYY-MM-DD)',
                      suffixIcon: calendarPickerSuffix(context, _date)),
                ),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration:
                      const InputDecoration(labelText: 'المبلغ بوحدة صغرى'),
                ),
                if (_fromBox != null && !_currencyOf(_fromBox!).isBase)
                  TextField(
                    controller: _fx,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
                    decoration: const InputDecoration(
                        labelText:
                            'لقطة الصرف مكبرة ×1,000,000 (مثال: 15000000 = 15)'),
                  ),
                TextField(
                  controller: _narration,
                  decoration:
                      const InputDecoration(labelText: 'الوصف (اختياري)'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('حفظ وترحيل'),
                ),
              ],
            ),
    );
  }
}

/// نموذج تسوية صندوق (س-92/س-17): عجزاً أو زيادةً على 57 (الحساب
/// الواحد — س8) بسبب نصي إلزامي — والفراغ يرفضه المدقق برسالته ذاتها
/// (درس س2: الحكم بالنص الحرفي لرسالة المدقق).
class AdjustmentEditScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const AdjustmentEditScreen({super.key, required this.db});

  @override
  State<AdjustmentEditScreen> createState() => _AdjustmentEditScreenState();
}

class _AdjustmentEditScreenState extends State<AdjustmentEditScreen> {
  int? _boxId;
  CashAdjustmentDirection _direction = CashAdjustmentDirection.shortage;

  final TextEditingController _date = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  List<CashBoxReportRow> _boxes = [];
  List<String>? _errors;
  bool _busy = false;

  /// بوابة التحميل — نمط initialValue الموثق.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // س-111 (D-108): التاريخ الافتراضي — نموذج التسوية.
    _date.text = todayIsoDate();
    _load();
  }

  Future<void> _load() async {
    final boxes =
        (await widget.db.cashBoxesReport()).where((b) => b.isActive).toList();
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _boxId = _boxes.isEmpty ? null : _boxes.first.boxId;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  CashAdjustmentDraft _buildDraft() {
    return CashAdjustmentDraft(
      dateText: _date.text.trim(),
      cashBoxId: _boxId ?? 0,
      direction: _direction,
      amountDocMinor: parseGroupedInt(_amount.text.trim()),
      reason: _reason.text,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final draft = _buildDraft();
    final structure = validateCashAdjustmentStructure(draft);
    if (structure.isNotEmpty) {
      setState(() => _errors = [
            for (final e in structure) describeCashAdjustmentValidationError(e)
          ]);
      return;
    }
    setState(() {
      _busy = true;
      _errors = null;
    });
    try {
      final id = await widget.db.createCashAdjustmentDraft(draft);
      await widget.db.postCashAdjustment(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CashAdjustmentValidationException catch (e) {
      await dqLog(widget.db, e, context: 'cash.adjust');
      if (!mounted) return;
      setState(() {
        _errors = [
          for (final err in e.errors) describeCashAdjustmentValidationError(err)
        ];
        _busy = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'cash.adjust');
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
        appBar: AppBar(title: Text('تسوية صندوق')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('تسوية صندوق')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          // م06 التكيفي لويندوز (س205): العريض يتوسّط بعرضه الأقصى
          // والضيّق بهامشه الأساسي كما كان حرفاً — بنماذج السندات الثلاثة.
          : ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: diqqahAdaptiveHorizontalMargin(context),
                  vertical: 12),
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
                DropdownButtonFormField<int>(
                  initialValue: _boxId,
                  decoration: const InputDecoration(labelText: 'الصندوق'),
                  items: [
                    for (final b in _boxes)
                      DropdownMenuItem<int>(
                          value: b.boxId,
                          child: Text('${b.name} (${b.currencyCode})')),
                  ],
                  onChanged: (value) => setState(() => _boxId = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _direction.storageValue,
                  decoration: const InputDecoration(
                      labelText: 'اتجاه الفرق (عجزاً أو زيادةً — على 57)'),
                  items: [
                    for (final d in CashAdjustmentDirection.values)
                      DropdownMenuItem<String>(
                          value: d.storageValue, child: Text(d.label)),
                  ],
                  onChanged: (value) => setState(() {
                    _direction = CashAdjustmentDirection.values
                        .firstWhere((d) => d.storageValue == value);
                  }),
                ),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                      labelText: 'التاريخ (YYYY-MM-DD)',
                      suffixIcon: calendarPickerSuffix(context, _date)),
                ),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration:
                      const InputDecoration(labelText: 'قيمة الفرق بوحدة صغرى'),
                ),
                TextField(
                  controller: _reason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'سبب الفرق (إلزامي — يوثق بالمستند)'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('حفظ وترحيل'),
                ),
              ],
            ),
    );
  }
}
