import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// المصفوفة المولَّدة للصلاحيات الافتراضية — س167 بقرار المالك الحرفي
/// «أوافق على اقتراحك بالنسبة للاختبارات» (من نقاش الاختبارات المقترح:
/// «مصفوفة الأدوار المولَّدة آلياً — نفع عالٍ كلفة صفرية تقريباً»).
///
/// العقد: المصفوفة المشتقة للأدوار الافتراضية الستة (س211/D-216: أُضيف دور الولادة الأعرى نهاية القائمة) — كل وحدة × كل
/// بوابة فرعية × كل حارس بوابة — مثفَّتة هنا مرجعاً. أي انزلاق مستقبلي
/// في defaultRolesPermissions أو في الحواجز يفشل الجولة صوتياً ويستوجب
/// تحديث المرجع بوعي لا صمتاً. التوليد يمرّ على حلقات (الأدوار ×
/// moduleKeys × subGateKeys) لا على أسطر مكتوبة يدوياً — فتُضاف وحدة
/// أو بوابة جديدة فيغطيها الحلقة فوراً ويكشف الاختبار نقص مرجعها.
///
/// البذرة التاريخية المحفوظة هنا: س164 ألغت التعليق وأدخلت البوابة
/// الفرعية invoices.post_others بلسان «من كان يعتمد يبقى يعتمد» —
/// فالمحاسب الافتراضي حاملها وحده دون المدير (النجمة تحملها كلها بلا
/// إلحاق بالصيغة) ودون الأدوار البيعية، وس104 أبقت بوابات القبض المعلق
/// على اسم المندوب حصراً وباباً للسندات لا للفواتير.
class RoleExpectation {
  final String role;
  final Set<String> modules;
  final List<String> subs;
  final String stored;
  final String summary;
  final bool canPostOthers;
  final bool holdsReceipts;
  final bool approvesHeldReceipts;

  const RoleExpectation({
    required this.role,
    required this.modules,
    required this.subs,
    required this.stored,
    required this.summary,
    required this.canPostOthers,
    required this.holdsReceipts,
    required this.approvesHeldReceipts,
  });
}

/// المرجع المثفَّت — قراءة حرفية من س164/س104 كما حُكمت بالجولة #327.
List<RoleExpectation> frozenExpectations() {
  const salesModules = <String>{'parties', 'invoices', 'vouchers'};
  const accountantModules = <String>{
    'parties', 'items', 'invoices', 'vouchers',
    'boxes', 'reports', 'ledger', 'settings',
  };
  const keeperModules = <String>{'items', 'reports'};
  return [
    const RoleExpectation(
      role: 'مدير',
      modules: {
        'parties', 'items', 'units', 'warehouses', 'invoices', 'vouchers',
        'orders', 'receivables', 'delivery', 'boxes', 'ledger', 'currencies',
        'roles', 'reports', 'sync', 'settings', 'backup', 'followups',
        'users', // س211/D-216: الوحدة التاسعة عشرة — النجمة تشملها
      },
      subs: [
        kPostOthersInvoicesKey,
        kCreateUsersKey, // س211/D-216: النجمة تشمل البوابتين الجديدتين
        kDeactivateUsersKey,
      ],
      stored: '*',
      summary: 'كل الوحدات',
      canPostOthers: true,
      holdsReceipts: false,
      approvesHeldReceipts: true,
    ),
    const RoleExpectation(
      role: 'محاسب',
      modules: accountantModules,
      subs: [kPostOthersInvoicesKey],
      stored: 'parties,items,invoices,vouchers,boxes,reports,ledger,settings,'
          'invoices.post_others',
      summary: 'الأطراف، الأصناف، الفواتير، السندات، الصناديق، '
          'التقارير اليومية، الدفتر المحاسبي، الإعدادات '
          '+ ترحيل مسودات الآخرين (الفواتير)',
      canPostOthers: true,
      holdsReceipts: false,
      approvesHeldReceipts: true,
    ),
    const RoleExpectation(
      role: 'أمين مستودع',
      modules: keeperModules,
      subs: [],
      stored: 'items,reports',
      summary: 'الأصناف، التقارير اليومية',
      canPostOthers: false,
      holdsReceipts: false,
      approvesHeldReceipts: false,
    ),
    const RoleExpectation(
      role: 'بائع',
      modules: salesModules,
      subs: [],
      stored: 'parties,invoices,vouchers',
      summary: 'الأطراف، الفواتير، السندات',
      canPostOthers: false,
      holdsReceipts: false,
      approvesHeldReceipts: false,
    ),
    const RoleExpectation(
      role: 'مندوب',
      modules: salesModules,
      subs: [],
      stored: 'parties,invoices,vouchers',
      summary: 'الأطراف، الفواتير، السندات',
      canPostOthers: false,
      holdsReceipts: true,
      approvesHeldReceipts: false,
    ),
    // س211/D-216: دور الولادة الأعرى — لا وحدات ولا بوابات ولا نجمة،
    // وصيغة التخزين الفارغة جزء من العقد (الولادة بأقل امتياز بنيوياً).
    const RoleExpectation(
      role: kBareUserRoleName,
      modules: {},
      subs: [],
      stored: '',
      summary: 'لا وحدات',
      canPostOthers: false,
      holdsReceipts: false,
      approvesHeldReceipts: false,
    ),
  ];
}

void main() {
  final expectations = frozenExpectations();

  test('المصفوفة المولَّدة: الأدوار الافتراضية الستة × 19 وحدة × البوابات الفرعية — '
      'المرجع المثفَّت يطابق حرفاً', () {
    expect(defaultRolesPermissions.keys.toSet(), equals(
        expectations.map((e) => e.role).toSet()),
        reason: 'لا دور يتيم ولا مرجع بلا دور — الستة حصراً');

    for (final exp in expectations) {
      final perms = RolePermissions(defaultRolesPermissions[exp.role]!);
      expect(perms.isAll, exp.role == 'مدير',
          reason: '${exp.role}: النجمة للمدير وحده');

      for (final key in moduleKeys) {
        expect(perms.allows(key), exp.modules.contains(key),
            reason: '${exp.role} × وحدة «$key»: المرجع المثفَّت '
                'يخالف الحساب المشتق');
      }
      expect(defaultRolesPermissions[exp.role], exp.stored,
          reason: '${exp.role}: صيغة التخزين جزء من العقد الظاهر');

      for (final gate in subGateKeys) {
        expect(perms.allowsSub(gate), exp.subs.contains(gate),
            reason: '${exp.role} × بوابة «$gate»');
      }
      expect(perms.subKeys, equals(exp.subs),
          reason: '${exp.role}: بواباته الملحقة بترتيبها المعروف');

      expect(roleCanPostOthersInvoices(perms), exp.canPostOthers,
          reason: '${exp.role}: حارسا البوابة (الوحدة + البوابة)');
      expect(roleHoldsReceiptsForApproval(exp.role), exp.holdsReceipts,
          reason: '${exp.role}: بوابة القبض المعلق بالاسم (س104)');
      expect(roleCanApproveHeldReceipts(exp.role, perms),
          exp.approvesHeldReceipts,
          reason: '${exp.role}: اعتماد التحصيلات المعلقة');
      expect(roleCanManageBackups(perms), exp.role == 'مدير',
          reason: '${exp.role}: بوابة النسخ (ث-12) للنجمة حصراً');
    }
  });

  test('أدوار البيع بلا اعتماد تحصيلات بالاسم — وفواتيرها بعد س164 '
      'بلا حجب بالاسم أصلاً (البوابة تُمنح لا تُورث)', () {
    expect(salesSideNoApprovalRoleNames, equals({'بائع', kSalesRepRoleName}));
    expect(receiptHoldRoleNames, equals({kSalesRepRoleName}));
    // البائع والمندوب والنجمة: فواتيرهما لا تعتمد التحصيلات حتى بامتلاك
    // السندات — والعقد الظاهر لس104 يبقى على السندات حصراً بعد س164.
    for (final name in {'بائع', 'مندوب'}) {
      final perms = RolePermissions(defaultRolesPermissions[name]!);
      expect(roleCanApproveHeldReceipts(name, perms), isFalse,
          reason: '$name: من الأدوار البيعية بلا اعتماد');
    }
  });

  test('النجمة تشمل البوابات كلها بلا إلحاق بالصيغة — وقائمة الدور '
      'تُقلَّم بمعروفِ البوابات حصراً', () {
    final star = RolePermissions.all();
    expect(star.subKeys, equals(subGateKeys),
        reason: 'النجمة تحمل كل بوابة معروفة');
    expect(defaultRolesPermissions['مدير'], allModulesToken,
        reason: 'صيغة المدير النجمة الخام — لا قائمة مطولة');

    // المفتاح المجهول يسقط صامتاً عرف مفاتيح الوحدات ذاته.
    final mixed = RolePermissions(' parties , $kPostOthersInvoicesKey ,bogus');
    expect(mixed.keys, equals(['parties']),
        reason: 'المجهول «bogus» يسقط والمفتاح المقلّم يُقتطع');
    expect(mixed.subKeys, equals([kPostOthersInvoicesKey]));

    // البوابة وحدها بلا وحدة الفواتير لا تفتح الترحيل — الحارسان معاً.
    final gateOnly =
        RolePermissions(kPostOthersInvoicesKey);
    expect(roleCanPostOthersInvoices(gateOnly), isFalse,
        reason: 'الحارس الأول: وحدة الفواتير إلزاماً مع البوابة');
  });

  test('الصياغة format: ترتيب معروف وإسقاط التكرار والمجهول — '
      'والنجمة تُختار متى اكتملت الوحدات مهما لُحق بمطابقاتها', () {
    expect(RolePermissions.format(moduleKeys), allModulesToken);
    expect(
        RolePermissions.format(moduleKeys,
            subs: {kPostOthersInvoicesKey, 'bogus.gate'}),
        allModulesToken,
        reason: 'النجمة تشمل البوابات فلا تلحق مفاتيحها بصدقته');

    expect(
        RolePermissions.format(['items', 'parties'],
            subs: {kPostOthersInvoicesKey}),
        'parties,items,$kPostOthersInvoicesKey',
        reason: 'ترتيب moduleKeys ثم ترتيب subGateKeys');
    expect(RolePermissions.format(['parties', 'parties', 'bogus', 'items']),
        'parties,items',
        reason: 'التكرار والمجهول يسقطان');
    expect(RolePermissions.format([], subs: {kPostOthersInvoicesKey}),
        kPostOthersInvoicesKey,
        reason: 'بوابة بلا وحدات صيغة صالحة — والحارس الأول يبقى حاكماً');
    expect(RolePermissions.format(<String>[], subs: const {'x.y'}), '',
        reason: 'البوابة المجهولة تسقط فتبقى القائمة الفارغة صالحة');
  });

  test('الملخص العربي والعناوين: كل مفتاح وحدة بلا تسمية يتيمة وكل '
      'بوابة بتسميتها وسطر إفصاحها — إظهار الواقع F-016', () {
    for (final key in moduleKeys) {
      expect(moduleLabels[key], isNotNull, reason: 'تسمية «$key» إلزامية');
      expect(moduleLabels[key], isNotEmpty);
    }
    for (final gate in subGateKeys) {
      expect(subGateLabels[gate], isNotNull, reason: 'تسمية «$gate»');
      expect(subGateHints[gate], isNotNull, reason: 'إفصاح «$gate»');
    }
    for (final exp in expectations) {
      expect(RolePermissions(defaultRolesPermissions[exp.role]!).summary,
          exp.summary,
          reason: '${exp.role}: الملخص جزء من اللسان الظاهر');
    }
    // الحالة الطرفية الموثقة: دور بلا وحدات ظاهرة يرى الرئيسية المعطلة.
    expect(const RolePermissions('').summary, 'لا وحدات');
    expect(const RolePermissions('').keys, isEmpty);
    expect(const RolePermissions('').allows('parties'), isFalse);
  });
}
