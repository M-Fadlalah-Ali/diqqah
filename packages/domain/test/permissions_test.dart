import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات نموذج الصلاحيات (F-080، دفعة إغلاق النواة س37) — القراءة
/// النقية حصراً: التحليل والصياغة والمفاتيح الافتراضية للأدوار —
/// وبوابات تعليق المندوب واعتماده (س101 بكلمة المالك).
void main() {
  group('RolePermissions — التحليل والسماح', () {
    test('النجمة تسمح بكل الوحدات', () {
      const p = RolePermissions.all();
      for (final key in moduleKeys) {
        expect(p.allows(key), isTrue, reason: 'المفتاح $key يُسمح به');
      }
      expect(p.isAll, isTrue);
      expect(p.summary, 'كل الوحدات');
      expect(p.keys, hasLength(moduleKeys.length));
    });

    test('قائمة مفاتيح تسمح بها حصراً — والمجهول يُرفض', () {
      const p = RolePermissions('parties,invoices');
      expect(p.allows('parties'), isTrue);
      expect(p.allows('invoices'), isTrue);
      expect(p.allows('boxes'), isFalse);
      expect(p.allows('reports'), isFalse);
      expect(p.isAll, isFalse);
    });

    test('المفتاح المجهول المخزن يُسقط صامتاً — لا وحدة لم تعتمد تُتيح', () {
      const p = RolePermissions('parties,ghost_key,boxes');
      expect(p.keys, ['parties', 'boxes']);
      expect(p.allows('ghost_key'), isFalse);
    });

    test('القائمة الفارغة دور مشروع بلا وحدات ظاهرة', () {
      const p = RolePermissions('');
      expect(p.keys, isEmpty);
      expect(p.summary, 'لا وحدات');
      expect(p.allows('parties'), isFalse);
    });
  });

  group('RolePermissions.format — الصياغة بترتيب القائمة المعروفة', () {
    test('يعيد الترتيب ويكشف التكرار والمجهول', () {
      final formatted = RolePermissions.format(
          ['boxes', 'ghost', 'parties', 'boxes', 'invoices']);
      expect(formatted, 'parties,invoices,boxes');
      // والقراءة تعود بالسماح نفسه
      expect(RolePermissions(formatted).allows('invoices'), isTrue);
      expect(RolePermissions(formatted).allows('ghost'), isFalse);
    });

    test('كل المفاتيح المختارة صيغتها النجمة لا قائمة مطولة', () {
      final formatted = RolePermissions.format(moduleKeys);
      expect(formatted, '*');
    });
  });

  group('الأدوار النمطية الافتراضية (F-080/D-100؛ والخامس مندوب س101؛ والسادس الوليد الأعرى س211)', () {
    test('الستة مزروعة بأسمائها المعتمدة بترتيبها — والمستخدم الأعرى نهاية القائمة عرف D-098', () {
      expect(defaultRolesPermissions.keys,
          ['مدير', 'محاسب', 'أمين مستودع', 'بائع', 'مندوب', kBareUserRoleName]);
    });

    test('المدير كل الوحدات — والبقية لا نجمة أبداً — والوليد الأعرى فراغٌ صالح', () {
      expect(defaultRolesPermissions['مدير'], '*');
      for (final entry in defaultRolesPermissions.entries) {
        if (entry.key == 'مدير') continue;
        expect(entry.value, isNot('*'),
            reason: 'دور ${entry.key} لا يملك النجمة');
        // س211 (D-216): دور الولادة الأعرى قيمته صيغة فارغة صالحة
        // موثقة بformat — الولادة بأقل امتياز بنيوياً.
        if (entry.key == kBareUserRoleName) {
          expect(entry.value, isEmpty);
          expect(RolePermissions(entry.value).keys, isEmpty);
          continue;
        }
        expect(entry.value, isNotEmpty);
      }
    });

    test('المحاسب المحاسبة كلها بلا الصلاحيات ولا المزامنة', () {
      final p = RolePermissions(defaultRolesPermissions['محاسب']!);
      expect(p.allows('invoices'), isTrue);
      expect(p.allows('vouchers'), isTrue);
      expect(p.allows('boxes'), isTrue);
      expect(p.allows('reports'), isTrue);
      expect(p.allows('ledger'), isTrue);
      expect(p.allows('settings'), isTrue);
      expect(p.allows('roles'), isFalse, reason: 'الصلاحيات للمدير');
      expect(p.allows('sync'), isFalse);
    });

    test('أمين المستودع بلا نقود باتاً — وبائع يبيع ويقبض بلا تقارير', () {
      final storekeeper =
          RolePermissions(defaultRolesPermissions['أمين مستودع']!);
      expect(storekeeper.allows('items'), isTrue);
      expect(storekeeper.allows('reports'), isTrue);
      expect(storekeeper.allows('invoices'), isFalse);
      expect(storekeeper.allows('vouchers'), isFalse);
      expect(storekeeper.allows('boxes'), isFalse);

      final seller = RolePermissions(defaultRolesPermissions['بائع']!);
      expect(seller.allows('parties'), isTrue);
      expect(seller.allows('invoices'), isTrue);
      expect(seller.allows('vouchers'), isTrue);
      expect(seller.allows('reports'), isFalse);
      expect(seller.allows('settings'), isFalse);
      expect(seller.allows('roles'), isFalse);
    });

    test('مندوب (س101 ثم س104): الأطراف والفواتير والسندات — وسنداته '
        'بوابة قبض معلق لا ترحيل مباشر، وبلا تقارير ولا صناديق ولا '
        'إعدادات', () {
      final rep = RolePermissions(defaultRolesPermissions['مندوب']!);
      expect(rep.allows('parties'), isTrue);
      expect(rep.allows('invoices'), isTrue);
      // س104 بكلمة المالك «ابدأ بدفعة المندوب 3»: تكتمل يد المندوب
      // بوحدة السندات — وقبضه معلق بالوسيط لا مباشرة (بوابة القبض
      // المعلق أدناه) فالفرق عن البائع بالمسار لا بالوحدة.
      expect(rep.allows('vouchers'), isTrue,
          reason: 'دفعة المندوب الثالثة: القبض المعلق بحساب الطريق');
      expect(rep.allows('reports'), isFalse);
      expect(rep.allows('boxes'), isFalse);
      expect(rep.allows('settings'), isFalse);
      expect(rep.allows('roles'), isFalse);
    });
  });

  group('بوابات القبض المعلق بحساب الطريق (س104 — كلمة المالك: «ابدأ '
      'بدفعة المندوب 3»)', () {
    test('المندوب يعلق قبضه — وغيره من الأدوار لا يعلق', () {
      expect(roleHoldsReceiptsForApproval('مندوب'), isTrue);
      expect(roleHoldsReceiptsForApproval(' مندوب '), isTrue,
          reason: 'التقميم أطراف حصراً والمقارنة حرفية');
      expect(roleHoldsReceiptsForApproval('بائع'), isFalse);
      expect(roleHoldsReceiptsForApproval('مدير'), isFalse);
      expect(roleHoldsReceiptsForApproval('محاسب'), isFalse);
      expect(roleHoldsReceiptsForApproval('كاشير'), isFalse);
    });

    test('المعتمد صاحب وحدة السندات من غير الأدوار البيعية — والمدير '
        'والمحاسب يعتمدان والبائع لا يعتمد ولو ملك الوحدة وأمين '
        'المستودع بلاها لا يعتمد حتى يُمنحها', () {
      const star = RolePermissions.all();
      expect(roleCanApproveHeldReceipts('مدير', star), isTrue);
      expect(
          roleCanApproveHeldReceipts(
              'محاسب',
              RolePermissions(
                  defaultRolesPermissions['محاسب']!)),
          isTrue,
          reason: 'المحاسب من وحدة السندات');
      expect(
          roleCanApproveHeldReceipts(
              'أمين مستودع',
              RolePermissions(defaultRolesPermissions['أمين مستودع']!)),
          isFalse,
          reason: 'بلا وحدة السندات حتى تُمنح');
      expect(
          roleCanApproveHeldReceipts(
              'بائع', RolePermissions(defaultRolesPermissions['بائع']!)),
          isFalse,
          reason: 'يد البيع ليست يد الاعتماد');
      expect(
          roleCanApproveHeldReceipts(
              'مندوب', RolePermissions(defaultRolesPermissions['مندوب']!)),
          isFalse,
          reason: 'المانح لا يعتمد تحصيله هو');
      expect(roleCanApproveHeldReceipts('مشرف', const RolePermissions('vouchers')),
          isTrue,
          reason: 'دور مخصص صاحب وحدة السندات يعتمد');
    });
  });

  group('بوابة «ترحيل مسودات الآخرين» وإلغاء التعليق (س164 — كلمة المالك '
      '«حتى البائع يمكن منحه صلاحية ترحيل فاتورة مندوب»)', () {
    test('المفتاح الفرعي بمحلله وصياغته — والنجمة تشمل البوابات', () {
      const star = RolePermissions.all();
      expect(star.allowsSub(kPostOthersInvoicesKey), isTrue);
      expect(star.subKeys, equals(subGateKeys));
      final granted = const RolePermissions(
          'parties,invoices,invoices.post_others');
      expect(granted.allowsSub(kPostOthersInvoicesKey), isTrue);
      expect(granted.subKeys, equals([kPostOthersInvoicesKey]));
      expect(const RolePermissions('parties,invoices')
          .allowsSub(kPostOthersInvoicesKey), isFalse);
      // الصياغة: البوابة تلحق بعد الوحدات بترتيبها المعروف
      expect(
          RolePermissions.format(['parties', 'invoices'],
              subs: {kPostOthersInvoicesKey}),
          'parties,invoices,invoices.post_others');
      // والنجم يشمل البوابات فلا تلحق مفاتيحها بصدقته
      expect(RolePermissions.format(moduleKeys), allModulesToken);
    });

    test('البوابة بحارسَيها: وحدة الفواتير والمفتاح المُنَح — '
        '«من كان يعتمد يبقى يعتمد» بالمحاسب', () {
      const star = RolePermissions.all();
      expect(roleCanPostOthersInvoices(star), isTrue,
          reason: 'النجمة تشمل الوحدة والبوابة معاً');
      expect(
          roleCanPostOthersInvoices(
              RolePermissions(defaultRolesPermissions['محاسب']!)),
          isTrue,
          reason: 'كان يعتمد المعلقات س101 فالبوابة باقية بيده');
      expect(
          roleCanPostOthersInvoices(
              RolePermissions(defaultRolesPermissions['بائع']!)),
          isFalse,
          reason: 'لا تُمنح افتراضاً — والمنح بيد المالك');
    });

    test('حتى البائع يُمنح البوابة بنص كلمة المالك — وبلا وحدة الفواتير '
        'لا بوابة حتى مع المفتاح', () {
      final sellerGranted = RolePermissions(RolePermissions.format(
          ['parties', 'invoices', 'vouchers'],
          subs: {kPostOthersInvoicesKey}));
      expect(roleCanPostOthersInvoices(sellerGranted), isTrue,
          reason: 'البائع مُنح البوابة فرحّل مسودات المندوبين');
      // المفتاح بلا الوحدة لا يفتح — حارسان معاً لا واحد
      expect(
          roleCanPostOthersInvoices(
              const RolePermissions('parties,invoices.post_others')),
          isFalse,
          reason: 'بلا وحدة الفواتير فلا شاشة فواتير أصلاً');
      // والمندوب بلا بوابة افتراضاً — مسودة الآخرين ليست بيده
      expect(
          roleCanPostOthersInvoices(
              RolePermissions(defaultRolesPermissions['مندوب']!)),
          isFalse);
    });

    test('ملخص الدور بلسان بواباته الملحقة بعد «+»', () {
      final accountant = RolePermissions(defaultRolesPermissions['محاسب']!);
      expect(accountant.summary, contains('ترحيل مسودات الآخرين (الفواتير)'));
      expect(RolePermissions(defaultRolesPermissions['بائع']!).summary,
          isNot(contains('ترحيل مسودات الآخرين')));
    });

    test('كل مفتاح افتراضي مكتوب معروف — بوحدةٍ أو بوابةٍ فرعية', () {
      for (final entry in defaultRolesPermissions.entries) {
        if (entry.value == '*') continue;
        // س211 (D-216): صيغة دور الولادة الأعرى فارغة بلا مفاتيح أصلاً.
        if (entry.value.isEmpty) continue;
        for (final key in entry.value.split(',')) {
          expect(moduleKeys.contains(key) || subGateKeys.contains(key),
              isTrue,
              reason: 'دور ${entry.key} يحمل مفتاحاً مجهولاً $key');
        }
      }
    });
  });
  test('مفاتيح الوحدات تسعة عشر بلا تكرار وكلها بتسمية عربية', () {
    // تكليف 2026-11-13: «backup» السابع عشر — بطاقة النسخ المجدول
    // والكتالوج بالإعدادات، قابلة للمنح كوحدة (§7).
    // س141 (د-7/§25.9): «followups» الثامن عشر — المتابعات بلاطتها
    // بالهيكلية وخلف صلاحيتها.
    // س211 (D-216): «users» التاسع عشر نهاية القائمة عرف D-098 —
    // وحدة المستخدمين وبوابتَيها أدناه، افتراضها المدير حصراً.
    expect(moduleKeys, hasLength(19));
    expect(moduleKeys, contains('backup'));
    expect(moduleLabels['backup'], 'النسخ الاحتياطي');
    expect(moduleKeys, contains('followups'));
    expect(moduleLabels['followups'], 'المتابعات');
    expect(moduleKeys.toSet(), hasLength(moduleKeys.length));
    for (final key in moduleKeys) {
      expect(moduleLabels[key], isNotNull, reason: 'تسمية $key غائبة');
    }
    // مدخل السندات من ضمنها (D-098) ومتابعة التسليم (س-139/D-133 دفعة 12)
    expect(moduleKeys, contains('vouchers'));
    expect(moduleLabels['vouchers'], 'السندات');
    expect(moduleKeys, contains('delivery'));
    expect(moduleLabels['delivery'], 'متابعة التسليم');
    expect(moduleKeys, contains('users'));
    expect(moduleLabels['users'], 'المستخدمون');
    expect(moduleKeys.last, 'users',
        reason: 'الجديد نهاية القائمة عرف D-098');
  });

  test('بوابتا وحدة المستخدمين (س211/D-216) — قدرتان منفصلتان والنجمة تشملهما', () {
    expect(subGateKeys, contains(kCreateUsersKey));
    expect(subGateKeys, contains(kDeactivateUsersKey));
    // س227 (المرحلة صفر د4): بوابة القوائم المالية آخر القائمة
    // حرفاً بعرف D-098 — وسابقتها بوابتا المستخدمين باقيتان بعقدهما.
    expect(subGateKeys.last, kFinancialReportsKey,
        reason: 'الجديد نهاية القائمة عرف D-098');
    expect(subGateLabels[kCreateUsersKey], 'إنشاء مستخدم جديد');
    expect(subGateLabels[kDeactivateUsersKey], 'تعطيل مستخدم وفعّله');
    expect(subGateLabels[kFinancialReportsKey], 'القوائم المالية (دخل وميزانية)');
    // النجمة تشمل البوابتين (المدير يمسك اليدتين)
    const star = RolePermissions.all();
    expect(star.allowsSub(kCreateUsersKey), isTrue);
    expect(star.allowsSub(kDeactivateUsersKey), isTrue);
    expect(star.allowsSub(kFinancialReportsKey), isTrue,
        reason: 'النجمة تشمل البوابة الجديدة — المدير يرى القوائم');
    // ومن مُنح الوحدة وحدها بلا بوابة فالقراءة خالصة
    const viewer = RolePermissions('users');
    expect(viewer.allows('users'), isTrue);
    expect(viewer.allowsSub(kCreateUsersKey), isFalse);
    expect(viewer.allowsSub(kDeactivateUsersKey), isFalse);
    // والبوابة منفردة تفتح يدها الواحدة حصراً (فصل الأيدي)
    const creator = RolePermissions('users,users.create');
    expect(creator.allowsSub(kCreateUsersKey), isTrue);
    expect(creator.allowsSub(kDeactivateUsersKey), isFalse);
    // والصياغة تُلحق البوابة بعد الوحدات بترتيبها المعروف
    expect(RolePermissions.format(['users'], subs: {kCreateUsersKey}),
        'users,users.create');
    // والأدوار الافتراضية لا تحمل أيّتهما — افتراضها المدير حصراً
    // (التفويض بعدها بيد المالك من شاشة الصلاحيات بنمط D-049)
    for (final entry in defaultRolesPermissions.entries) {
      final p = RolePermissions(entry.value);
      expect(p.allowsSub(kCreateUsersKey), entry.key == 'مدير',
          reason: 'دور ${entry.key} ببوابة الإنشاء');
      expect(p.allowsSub(kDeactivateUsersKey), entry.key == 'مدير',
          reason: 'دور ${entry.key} ببوابة التعطيل');
    }
  });

  test('صلاحية «متابعة التسليم» افتراضها بيد المدير حصراً (D-133) — '
      'والتفويض بعدها بيد المالك', () {
    // المدير النجمة يشملها
    expect(const RolePermissions.all().allows('delivery'), isTrue);
    // والأدوار الافتراضية الأخرى لا — التسليم بيد المدير حصراً
    for (final entry in defaultRolesPermissions.entries) {
      if (entry.key == 'مدير') continue;
      expect(
          RolePermissions(entry.value).allows('delivery'), isFalse,
          reason: 'دور ${entry.key} لا يجري التسليم افتراضاً');
    }
  });
}
