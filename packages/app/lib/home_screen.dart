import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'settings_screen.dart';
import 'parties_screen.dart';
import 'items_screen.dart';
import 'reports_screen.dart';
import 'invoices_screen.dart';
import 'vouchers_screen.dart';
import 'boxes_screen.dart';
import 'roles_screen.dart';
import 'delivery_screen.dart';

/// الشاشة الهيكلية (F-016): قائمة وحدات — إطار التنقل. الوحدات ومراحل
/// توفرها من جدول النطاق (01 §5) حرفاً، والإعدادات متاحة فوراً بعد
/// التهيئة (س-01)، والأطراف أول وحدة تُفتح في م1 (دفعتها الأولى).
///
/// دفعة إغلاق النواة (س37) — ثلاثة إضافات معروضة:
/// - **مدخل «السندات»** بنداً رئيسياً (D-098): كان مدخل القبض والصرف
///   والتحويل والتسوية زراً مدفوناً بشاشة الصناديق فلم يلمحه المالك
///   (س37: «كأني لم ألمح وجوداً لسندات الدفع») — فصار بنداً ظاهراً
///   بعد «الفواتير» مباشرة.
/// - **فرض الصلاحيات** (F-080/D-100): تُعرض للدور وحداته المفتوحة
///   حصراً — ومعطلات الهيكلية تظهر للجميع كما هي (إظهار الواقع F-016).
/// - **الفحص الافتتاحي الصامت للثوابت** (F-006/D-099): يُنفذ بعد أول
///   إطار خلفياً — نظيفٌ مرّ صامتاً، وخرقٌ شريط تنبيه علوي ثابت يحيل
///   إلى بطاقة الفحص في الإعدادات.
class HomeScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final String dbPath;
  final VoidCallback onRestored;

  const HomeScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// (مفتاح الوحدة، اسمها، مرحلة التوفر في 01، متاحة الآن؟) — إظهار
  /// الواقع لا وعود مبكرة. الإعدادات متاحة فوراً بعد التهيئة (س-01)،
  /// والأطراف فُتحت بدفعة م1 الأولى (F-020..F-023، س-29..س-35) والأصناف
  /// بدفعتها الثانية (F-030/F-031، س-36..س-41) والتقارير اليومية بدفعتها
  /// السادسة وواجهاتها (F-189..F-195، دفعتا 6 و6-ب) والفواتير والصناديق
  /// والصلاحيات بدفعة واجهات الإدخال (6-ج) بأمر المالك «تنفيذها كلها
  /// معاً» (س36، F-196..F-199) — والسندات دفعة الإغلاق (D-098 معروض).
  /// البقية في مفرغها.
  static const List<(String, String, String, bool)> _modules = [
    ('parties', 'الأطراف', 'متاحة الآن — بطاقة الأطراف والبحث الجامع (F-020..F-023)', true),
    ('items', 'الأصناف', 'متاحة الآن — بطاقة الصنف والوحدات الأساسية (F-030/F-031)', true),
    ('units', 'وحدات القياس والتعبئة', 'الإصدار 2 — الإدخال في م1 بالوحدة الأساسية من شاشة الأصناف', false),
    ('warehouses', 'المستودعات', 'الإصدار 1 (واحد) → 2 (متعدد + جرد)', false),
    ('invoices', 'الفواتير', 'متاحة الآن — قائمة ونموذج الأنواع الأربعة (F-196..F-198)', true),
    ('vouchers', 'السندات', 'متاحة الآن — قبض وصرف وتحويل وتسوية (D-098)', true),
    // س-139/D-133 (دفعة 12): شاشة متابعة أسطر البيع غير المستلمة —
    // بصلاحية مستقلة افتراضها للمدير حصراً وقابلة للتفويض.
    ('delivery', 'متابعة التسليم', 'متاحة الآن — أسطر البيع غير المستلمة والمورد المسؤول (D-133)', true),
    ('orders', 'طلبات الشراء والبيع', 'لاحقاً — تُقيَّم بعد MVP (D-026)', false),
    ('receivables', 'الذمم', 'الإصدار 1', false),
    ('boxes', 'الصناديق', 'متاحة الآن — القائمة وإنشاء الحساب الآلي (F-199)', true),
    ('ledger', 'الدفتر المحاسبي', 'الإصدار 1 — الأساس', false),
    ('currencies', 'العملات', 'الإصدار 1 (واحدة) → 3 (متعددة + فروق)', false),
    ('roles', 'الصلاحيات', 'متاحة الآن — الأدوار وأذوناتها والمستخدمون (F-080)', true),
    ('reports', 'التقارير اليومية', 'متاحة الآن — التقارير الست والفترات والإقفال (F-189..F-195)', true),
    ('sync', 'المزامنة', 'الإصدار 4', false),
    ('settings', 'الإعدادات', 'متاحة الآن — النسخ الاحتياطي والاستعادة وفحص الثوابت (F-012/F-013)', true),
  ];

  /// أيقونات الوحدات المفتوحة — خريطة ثابتة بدل سلسلة الشروط الطويلة،
  /// والغائب يأخذ أيقونة الإعدادات الاعتيادية.
  static const Map<String, IconData> _moduleIcons = {
    'parties': Icons.people_outline,
    'items': Icons.inventory_2_outlined,
    'invoices': Icons.receipt_long_outlined,
    'vouchers': Icons.request_quote_outlined,
    'delivery': Icons.local_shipping_outlined, // متابعة التسليم (D-133)
    'boxes': Icons.account_balance_wallet_outlined,
    'roles': Icons.shield_outlined,
    'reports': Icons.query_stats,
  };

  /// صلاحيات صاحب الجلسة — فراغها «قيد التحميل» فيعرض مؤقت الانتظار
  /// لا قائمة فارغة (الفشل المغلق: لا وحدة تُظهر قبل جواب الدور).
  RolePermissions? _permissions;

  /// اسم المستخدم صاحب الجلسة — للعرض أسفل الهيكلية فيعرف المالك
  /// بمن هو داخل (D-100 معروض).
  String? _sessionLabel;

  /// نتيجة الفحص الافتتاحي الصامت — نظيفة تبقى null فلا شيء ظاهر.
  IntegrityReport? _openingViolations;

  @override
  void initState() {
    super.initState();
    _loadSession();
    _openingIntegrityCheck();
  }

  /// قراءة صاحب الجلسة ودوره وصلاحياته — الحالي المخزن إن وجد وإلا
  /// أول نشط (المدير المُنشأ أول تشغيل). أي خلل يعرض الكل مفتوحاً
  /// معطلاً؟ لا — الفشل يعرض القائمة كاملة كما كانت قبل دفعة الصلاحيات
  /// (سقوط آمن إلى سلوك م1-نواة قبل D-100 لا شاشة ميتة)، وعلته تظهر
  /// في سطر الحالة.
  Future<void> _loadSession() async {
    try {
      final user = await widget.db.currentUser();
      final role = user == null ? null : await widget.db.roleOf(user);
      if (!mounted) return;
      setState(() {
        _permissions = role == null
            ? const RolePermissions.all()
            : RolePermissions(role.permissions);
        _sessionLabel = user == null
            ? null
            : '${user.name} (${role?.name ?? 'بلا دور'})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _permissions = const RolePermissions.all();
        _sessionLabel = null;
      });
    }
  }

  /// الفحص الافتتاحي الصامت (F-006/N-009، D-099 معروض): بعد أول إطار
  /// خلفياً — النظيف صامت والخرق شريط علوي ثابت. لا يكتب ولا يمنع
  /// الاستخدام (الإيقاف أثناء الكتابة بيد المحرك والحواجز حصراً).
  Future<void> _openingIntegrityCheck() async {
    try {
      final report = await widget.db.integrityCheckReport();
      if (!mounted || report.isClean) return;
      setState(() => _openingViolations = report);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
            'تنبيه: الفحص الافتتاحي للثوابت وجد ${report.violations.length} '
            'خرقاً — راجع بطاقة «فحص الثوابت» في الإعدادات'),
      ));
    } catch (_) {
      // فحص افتتاحي لا يُسقط الرئيسية أبداً — والفحص اليدوي بالإعدادات
      // هو الطريق الموثق عند الشك.
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = _permissions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('دِقَّة'),
      ),
      body: permissions == null
          // الفشل المغلق: مؤقت انتظار جواب الدور — لا قائمة قبل الصلاحيات
          // (شريحة من الثانية على قاعدة محلية).
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_openingViolations != null)
                  MaterialBanner(
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                    content: Text(
                        'الفحص الافتتاحي وجد ${_openingViolations!.violations.length} '
                        'خرقاً للثوابت — راجع الإعدادات ← فحص الثوابت',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer)),
                    actions: [
                      TextButton(
                        onPressed: () => ScaffoldMessenger.of(context)
                            .hideCurrentMaterialBanner(),
                        child: const Text('إغلاق'),
                      ),
                    ],
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // فرض الصلاحيات (F-080/D-100): وحدات الدور المفتوحة
                        // حصراً — ومعطلات الهيكلية للجميع (إظهار الواقع).
                        // أيقونات الوحدات بخريطة ثابتة — ومتابعة التسليم
                        // (س-139/D-133 دفعة 12) شاحنة التسليم.
                        for (final (key, title, stage, enabled) in _modules)
                          if (!enabled || permissions.allows(key))
                            ListTile(
                              leading: Icon(!enabled
                                  ? Icons.lock_outline
                                  : _moduleIcons[key] ??
                                      Icons.settings_outlined),
                              title: Text(title),
                              subtitle: Text(
                                  enabled ? stage : 'معطلة — متاح في $stage'),
                              enabled: enabled,
                              onTap: enabled
                                  ? () {
                                      // الأطراف (دفعة م1 (1)) والأصناف
                                      // (دفعة م1 (2)) والتقارير اليومية
                                      // (دفعتا م1 (6) و(6-ب)) والفواتير
                                      // والصناديق والصلاحيات (دفعة (6-ج))
                                      // والسندات (دفعة الإغلاق D-098)
                                      // ومتابعة التسليم (دفعة 12 D-133) —
                                      // والبقية الإعدادات وحدها حتى دفعاتها.
                                      final Widget target = title == 'الأطراف'
                                          ? PartiesScreen(db: widget.db)
                                          : title == 'الأصناف'
                                              ? ItemsScreen(db: widget.db)
                                              : title == 'التقارير اليومية'
                                                  ? ReportsScreen(
                                                      db: widget.db)
                                                  : title == 'الفواتير'
                                                      ? InvoicesScreen(
                                                          db: widget.db)
                                                      : title == 'السندات'
                                                          ? VouchersScreen(
                                                              db: widget.db)
                                                          : title ==
                                                                  'متابعة التسليم'
                                                              ? DeliveryScreen(
                                                                  db: widget
                                                                      .db)
                                                              : title ==
                                                                      'الصناديق'
                                                                  ? BoxesScreen(
                                                                      db: widget
                                                                          .db)
                                                                  : title ==
                                                                          'الصلاحيات'
                                                                      ? RolesScreen(
                                                                          db: widget
                                                                              .db)
                                                                      : SettingsScreen(
                                                                          db: widget
                                                                              .db,
                                                                          dbPath:
                                                                              widget
                                                                                  .dbPath,
                                                                          onRestored:
                                                                              widget
                                                                                  .onRestored,
                                                                          onSessionChanged:
                                                                              () {
                                                                            // تبديل الجلسة (D-100): يُغلق
                                                                            // الإعدادات وتُعاد قراءة الدور
                                                                            // فتتغير الوحدات الظاهرة فوراً.
                                                                            Navigator.of(context)
                                                                                .pop();
                                                                            _loadSession();
                                                                          },
                                                                        );
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                            builder: (_) => target),
                                      );
                                    }
                                  : null,
                            ),
                      ],
                    ),
                  ),
                ),
                if (_sessionLabel != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('الجلسة: $_sessionLabel',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
    );
  }
}
