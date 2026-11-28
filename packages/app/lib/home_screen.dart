import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:shared_preferences/shared_preferences.dart';

// س209 الطبقة 6: التذييل بنسخة العرض المحقونة من CI (settings_screen)
// لا كتالوج النسخ — فالكتالوج تقني والموجّه للمالك بلسان العرض D-213.
import 'backup_center.dart' hide kAppVersion;
import 'adaptive.dart';
import 'app_theme.dart' show DiqqahLane, diqqahLanesOf;
import 'auto_backup_prefs.dart';
import 'follow_ups_screen.dart';
import 'l10n/app_strings.dart';
import 'settings_screen.dart'
    show SettingsScreen, diqqahVersionLine, kAppVersion, kBuildNumber;
import 'parties_screen.dart';
import 'items_screen.dart';
import 'unit_groups_screen.dart';
import 'currencies_screen.dart';
import 'reports_screen.dart';
import 'invoices_screen.dart';
import 'vouchers_screen.dart';
import 'boxes_screen.dart';
import 'roles_screen.dart';
import 'users_screen.dart';
import 'delivery_screen.dart';
import 'warehouses_screen.dart';
import 'orders_screen.dart';
import 'receivables_screen.dart';
import 'ledger_screen.dart';
import 'sync_work_screen.dart';
import 'session_guard.dart';
import 'dq_log.dart';

/// س198 (م12 من تقرير فحص الواجهات وفق M3): فعل زر «إغلاق» لافتة
/// الفحص الافتتاحي — كان ينادي hideCurrentMaterialBanner وهي لافتة
/// مضمّنة بالعمود لا معروضة بالرسول فلا فعل له — والإغلاق الحقيقي
/// مسح حالة الخرق من الجذر.
enum HomeAlertAction {
  /// فتح الإعدادات (تفاصيل النسخ والتذكيرات) — فعل لافتات النسخ كلها.
  settings,

  /// إغلاق لافتة خرق الفحص الافتتاحي بمسح حالتها (فعل حقيقي لا ميت).
  closeViolations,
}

/// س198 (م12): بند تنبيه واحد بأولويته ولسانه ودور لونه من الثيم
/// وفعله — الوحدة الحاكمة للّافتة الواحدة ومدخل التنبيهات معاً.
class HomeAlert {
  final int priority;
  final String message;
  final Color color;
  final Color onColor;
  final String actionLabel;
  final HomeAlertAction action;

  const HomeAlert({
    required this.priority,
    required this.message,
    required this.color,
    required this.onColor,
    required this.actionLabel,
    required this.action,
  });
}

/// س198 (م12): قائمة تنبيهات الرئيسية مرتبة بالأولوية — فشل النسخ
/// أولاً (بيانات على المحك بلسان خطأ) ثم خرق الفحص الافتتاحي ثم
/// تحذيرات النسخ الوقائية أخيراً (بلسانها الثانوي secondaryContainer
/// — تقرير م12 سمّى المتابعات من الثلاثة الأولى والتحذيرات أقلها
/// شدة بلونها المعتمد).
///
/// س221 (قرار المالك بتنفيذ دفعة اتساق نبض العمل «أفضل قسماً واحداً
/// فقط وهو نبض العمل»): بند المتابعات الأحمر أُزيل من اللافتات —
/// نبض العمل هو المصدر الواحد لمتابعات الإدارة وبطاقاته مستقلة
/// بأفعالها (المتابعات والأصناف والذمم) فلا ازدواج ولا لسان متكرر
/// ولا وجهان لشيء واحد. الرسائل الباقية حرفاً فلا معلومة تغيرت.
List<HomeAlert> homeAlerts({
  required BuildContext context,
  BackupHealth? health,
  int? violationsCount,
}) {
  final cs = Theme.of(context).colorScheme;
  final alerts = <HomeAlert>[];
  if (health != null && health.hasFailure) {
    alerts.add(HomeAlert(
      priority: 0,
      message: 'فشل النسخ الاحتياطي: ${health.failureMessage} — '
          'راجع كتالوج النسخ بالإعدادات',
      color: cs.errorContainer,
      onColor: cs.onErrorContainer,
      actionLabel: 'التفاصيل',
      action: HomeAlertAction.settings,
    ));
  }
  if (violationsCount != null) {
    alerts.add(HomeAlert(
      priority: 1,
      message: 'الفحص الافتتاحي وجد $violationsCount '
          'خرقاً للثوابت — راجع الإعدادات ← فحص الثوابت',
      color: cs.errorContainer,
      onColor: cs.onErrorContainer,
      actionLabel: 'إغلاق',
      action: HomeAlertAction.closeViolations,
    ));
  }
  if (health != null && health.noBackupFor30Days) {
    alerts.add(HomeAlert(
      priority: 3,
      message: 'لم تُنشأ نسخة احتياطية منذ 30 يوماً على الأقل '
          '— بياناتك بلا حماية، انسخ الآن',
      color: cs.secondaryContainer,
      onColor: cs.onSecondaryContainer,
      actionLabel: 'نسخ الآن',
      action: HomeAlertAction.settings,
    ));
  }
  if (health != null && health.attachmentsStale) {
    alerts.add(HomeAlert(
      priority: 3,
      message: 'صور الأصناف تغيرت ولم تدخل أي نسخة حديثة تضم '
          'المرفقات — أنشئ نسخة مع المرفقات',
      color: cs.secondaryContainer,
      onColor: cs.onSecondaryContainer,
      actionLabel: 'نسخ',
      action: HomeAlertAction.settings,
    ));
  }
  return alerts;
}

/// الشاشة الهيكلية (F-016): قائمة وحدات — إطار التنقل. الوحدات ومراحل
/// توفرها من جدول النطاق (01 §5) حرفاً، والإعدادات متاحة فوراً بعد
/// التهيئة (س-01)، والأطراف أول وحدة تُفتح في م1 (دفعتها الأولى).
///
/// دفعة (18) — عزل إدخال الفواتير (س-163/D-160/D-161): بطاقة «الفواتير»
/// صارت أربعة أزرار مستقلة (فاتورة بيع / فاتورة شراء / مردود بيع /
/// مردود شراء) يُحدد النوع بالضغط لا بانتقاء من قائمة — ومعروضة
/// المعاينة في س-162 واعتمدها المالك بلفظه «اعتمد الدفعات الأربعة وقم
/// بتنفيذ اقتراحك للفواتير» (س52) — وزر «سجل الفواتير» يفتح الأرشيف
/// الموحد بفلتره (الطبقة الثانية من العزل قائمة أصلاً — س-60/D-080).
///
/// س202 (بأمر المالك «تكتل الفواتير في الأعلى لم يعجبني بصرياً أريد
/// التراجع عنه إلى أيقونتين كالبقية: المبيعات - المشتريات»): البطاقة
/// سُحبت من فوق الشبكة، والفواتير بلاطتا جهتها أول الشبكة بنَسَق البقية
/// تفتحان الأرشيف بجهته (فلتر الجهة س202 بالتخزين والأرشيف)، وإدخالُه
/// زر «فاتورة جديدة» بأعلى الأرشيف بورقة اختيار نوعَي الجهة — وعرف
/// التحديد بالضغط الصريح باقٍ (س-163) لا انتقاء بالنموذج.
///
/// دفعة ما بعد م2 (س98 — D-198 بكلمة المالك «افتحهما»): فتح بلاطتَي
/// «وحدات القياس والتعبئة» و«العملات» في الهيكلية — نُفِّذتا فعلاً
/// بدفعات م2 (الوحدات 27/30 والعملات 34) لكن بلاطتاهما بقيتا مقفلتيه
/// بعرض الواقع التاريخي — فأصبحتا بلاطتين مفتوحتين تفتحان شاشتيهما
/// (UnitGroupsScreen وCurrenciesScreen) وفرض الصلاحية نافذ عليهما.
///
/// دفعة إغلاق النواة (س37) — ثلاثة إضافات:
/// - **مدخل «السندات»** بنداً رئيسياً (D-098): كان مدخل القبض والصرف
///   والتحويل والتسوية زراً مدفوناً بشاشة الصناديق فلم يلمحه المالك
///   (س37: «كأني لم ألمح وجوداً لسندات الدفع») — فصار بنداً ظاهراً
///   بعد «الفواتير» مباشرة.
/// - **فرض الصلاحيات** (F-080/D-100): تُعرض للدور وحداته المفتوحة
///   حصراً — ومعطلات الهيكلية تظهر للجميع كما هي (إظهار الواقع F-016).
/// - **الفحص الافتتاحي الصامت للثوابت** (F-006/D-099): يُنفذ بعد أول
///   إطار خلفياً — نظيفٌ مرّ صامتاً، وخرقٌ شريط تنبيه علوي ثابت يحيل
///   إلى بطاقة الفحص في الإعدادات.
/// س203 — الوصول السريع (بأمر المالك «صندوقاً للوصول السريع بمعزل
/// عن أيقونات البرنامج»): بلاطات مثبتة فوق شبكة الوحدات لا ضمنها —
/// فلا يُمس عرف جدول النطاق ولا عرف شبكة الرئيسية. الحد أربعة
/// بضغطة مطولة على البلاطة، والإلغاء بعلامة حذف اللاصقة، والتخزين
/// بالإعدادات المشتركة بنمط الثيم (D-104): الفشل سقوط آمن لا كسر —
/// والترتيب بترتيب التثبيت (السحب والتدريج لاحقاً بأمر المالك).
///
/// س209 — الدفعة 3 (قانون عرض سطح المكتب والرئيسية الست طبقات بأمر
/// المالك «تابع دفعة 3» — تفاصيل بند 6 قواعد الصناعة بيد المجلس
/// س207): الرئيسية ست طبقات بضوء تركيب لوحات Filament القياسي
/// (المراجعة: ترويسة صفحة وبطاقات إحصاء وأدوات سريعة ومحتوى
/// وتنبيهات وتذييل — والاستئناس بAureusERP غير ملزم عرف س182):
///  1) **الترويسة والهوية** — شريط العنوان بالاسم وصاحب الجلسة (قائمة).
///  2) **التنبيهات بالأولوية** — اللافتة والمدخل (س198 م12 قائمة حرفاً).
///  3) **نبض العمل** — بطاقات إحصاء قرائية من لقطة المتابعات المحمّلة
///     أصلاً حصراً (لا استعلام جديد ولا مساس بالمجال والتخزين):
///     البطاقة الجامعة بفعلها كلما كان هناك متابعات — وبداية السنة
///     غير المصدقة متابعة قائمة على القاعدة النظيفة فالجامعة
///     تظهر بالوجود — والتفصيلية الثلاث بوجود عدّادها حصراً فلا
///     بطاقة صفرية تزاحم الشاشة (الصمت الهادئ عرف س198).
///  4) **الوصول السريع** — اللاصقات المثبتة (س203 قائمة حرفاً).
///  5) **شبكة الوحدات** — الضيّق بلاطاته الأيقونية القائمة حرفاً
///     (س182 بأمر المالك) والعريض فوق حد التوسيط بطاقات بشبكة
///     أعمدة (قانون العرض: بطاقة لا أيقونة بوصف المرحلة ظاهراً).
///  6) **التذييل** — سطر الإصدار بدالة العرض القائمة diqqahVersionLine
///     (فارغ التطوير والاختبار بعرفها فلا ضجيج ولا كسر).
const String kQuickAccessPrefsKey = 'home_quick_access';

/// الحد الأقصى للبلاطات المثبتة — أربعة بأمر العرض.
const int kQuickAccessLimit = 4;

/// قراءة المثبتات المحفوظة — وأي فشل يعيد فراغاً بلا كسر (نمط
/// loadThemeMode الموثق).
Future<List<String>> loadQuickAccess() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(kQuickAccessPrefsKey);
    if (saved == null) return const <String>[];
    return [
      // التضييق الصريح: مفاتيح لا تكرار — والحد فرضاً هنا أيضاً.
      for (final k in saved)
        if (!saved.sublist(0, saved.indexOf(k)).contains(k) &&
            saved.indexOf(k) < kQuickAccessLimit)
          k,
    ];
  } catch (_) {
    return const <String>[];
  }
}

/// حفظ المثبتات — والفشل يحتمل: الثبّت حي بالذاكرة والجلسة.
Future<void> saveQuickAccess(List<String> keys) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kQuickAccessPrefsKey, keys);
  } catch (_) {
    // بلا كسر — التثبيت بالجلسة أصلاً.
  }
}

class HomeScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final String dbPath;
  final VoidCallback onRestored;

  /// س212 (D-215): نداء الغلق — أفعال الثلاثة (القفل والتبديل
  /// والخروج) تكتب الراية بالقاعدة ثم تنادي به فتعيد بوابة الإقلاع
  /// الجذر على بوابة الجهاز فلا رئيسية على جلسة مقفلة. الغائب (بعض
  /// الاختبارات الضيقة) يترك الكتابة بلا إعادة وجه.
  final VoidCallback? onLocked;

  const HomeScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
    this.onLocked,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// (مفتاح الوحدة، اسمها، مرحلة توفرها في 01، متاحة الآن؟) — إظهار
  /// الواقع لا وعود مبكرة. الإعدادات متاحة فوراً بعد التهيئة (س-01)،
  /// والأطراف فُتحت بدفعة م1 الأولى (F-020..F-023، س-29..س-35) والأصناف
  /// بدفعتها الثانية (F-030/F-031، س-36..س-41) والتقارير اليومية بدفعتها
  /// السادسة وواجهاتها (F-189..F-195، دفعتا 6 و6-ب) والصناديق
  /// والصلاحيات بدفعة واجهات الإدخال (6-ج) بأمر المالك «تنفيذها كلها
  /// معاً» (س36، F-196..F-199) — والسندات دفعة الإغلاق (D-098 معروض).
  /// **الفواتير خرجت من القائمة بدفعة (18)** (س-163/D-161): بطاقتها
  /// بأزرار الأنواع الأربعة فوق القائمة — **وسُحبت البطاقة بكلمتها
  /// س202** («التراجع عنه إلى أيقونتين كالبقية») فصارت بلاطتا
  /// المبيعات والمشتريات أول الشبكة وإدخالها من الأرشيف — وكانت
  /// فُتحت بدفعة 6-ج نفسها (F-196..F-198).
  /// **س178 (تفعيل المزامنة)**: آخر المعطلات خرج من مفرغه بكلمة المالك
  /// «لا زالت بلاطة المزامنة غير مفعلة في نسخة b55» — فلا معطلات بعد.
  static const List<(String, String, String, bool)> _modules = [
    // س202: الفواتير بلاطتا جهتها أول الشبكة — المبيعات ثم المشتريات —
    // على موضع بطاقة دفعة (18) ذاته لأنها أكثر ما يستعمله صاحب المنشأة،
    // وبصلاحية «الفواتير» ذاتها (مفتاحا البلاطتين يحسمان إليها).
    ('sales', 'المبيعات',
        'فواتير البيع ومردودها بفلتر جهتهما', true),
    ('purchases', 'المشتريات',
        'فواتير الشراء ومردودها بفلتر جهتهما', true),
    ('parties', 'الأطراف', 'بطاقة الأطراف والبحث الجامع', true),
    ('items', 'الأصناف', 'بطاقة الصنف والوحدات الأساسية', true),
    // D-198 (س98): فُتحت البلاطتان بدفعة ما بعد م2 — الوحدات منفذة
    // بالدفعات 27 (F-032/F-033) و30 (س-10 لقطة الوحدة والعامل) والعملات
    // بالدفعة 34 (F-120/F-121/F-124) — فالنص الفرعي واقع لا وعد.
    // س202 (بأمر المالك «تصحيح إلى وحدات»): لسان البلاطة بالمختصر
    // المقروء والاسم الكامل عنوان الشاشة وتلميحها ذاته.
    ('units', 'الوحدات',
        'مجموعات التعبئة وأسعارها ولقطة الوحدة بالفواتير', true),
    // الدفعة 24 (أولى م2 — س77/D-185): المستودعات خرجت من مفرغها —
    // الإدارة والتحويل بين المستودعات (س-18) بشاشتها (س-18/05 §3.3).
    ('warehouses', 'المستودعات', 'الإدارة والتحويل بين المستودعات', true),
    ('vouchers', 'السندات', 'قبض وصرف وتحويل وتسوية', true),
    // س-139/D-133 (دفعة 12): شاشة متابعة أسطر البيع غير المستلمة —
    // بصلاحية مستقلة افتراضها للمدير حصراً وقابلة للتفويض.
    ('delivery', 'متابعة التسليم', 'أسطر البيع غير المستلمة والمورد المسؤول', true),
    // س123 (تفعيل الطلبات — الدفعة الثانية): البلاطة خرجت من مفرغها
    // بأمر المالك «أريد تفعيل طلبات البيع والشراء» — الأساس س121
    // (ترحيلة v27 والمجال والتخزين وحرسا التحويل) والواجهة س123
    // (القائمة والنموذج والتفصيل والتحويل النافذ والطباعة) — 07 §3.2
    // و09 §18.
    // س202 (بأمر المالك «الطلبات»): الاختصار المعتمد بلسان البلاطة
    // والعنوان الكامل عنوان الشاشة ذاتها.
    ('orders', 'الطلبات',
        'أوامر البيع والشراء والتحويل لفاتورة', true),
    // س125 (تفعيل الذمم والدفتر المحاسبي — بأمر المالك الحرفي
    // «بعد الانتهاء نتوجه إلى تفعيل الذمم والدفتر المحاسبي» بعد
    // إغلاق b36 بأمره «قم ببناء b36»): البلاطتان خرجتا من مفرغهما —
    // البنية المنجزة م1 (receivablesPayablesReport وagingReport
    // وpartyStatementReport وallLedgerAccounts وaccountStatementReport)
    // فوقها واجهة قراءة خالصة — الإصدار 1 بلا ترحيلة ولا مساس
    // بالقلب المحاسبي — والذمم الإصدار 1 والدفتر الإصدار 1 «الأساس».
    ('receivables', 'الذمم',
        'أرصدة الأطراف وأعمارها وكشف حساب كل طرف', true),
    ('boxes', 'الصناديق', 'القائمة وإنشاء الحساب الآلي', true),
    ('ledger', 'الدفتر المحاسبي',
        'دليل الحسابات وكشف حساب كل حساب '
        '(الإصدار 1 — الأساس)', true),
    ('currencies', 'العملات',
        'تعدد العملات وأسعار الصرف اليومية', true),
    ('roles', 'الصلاحيات', 'الأدوار وأذوناتها والمستخدمون', true),
    ('reports', 'التقارير اليومية', 'التقارير الست والفترات والإقفال', true),
    // س141 (د-7/§25.9 — الوحدة الثامنة عشرة): المتابعات — تجميع عرض فوق
    // المصادر، والشارة الحمراء على الرئيسية حتى تُعالج.
    ('followups', 'المتابعات',
        'متابعات الانتقال والافتتاح والتخزين', true),
    // س178 (تفعيل المزامنة): البلاطة خرجت من مفرغها بكلمة المالك
    // «لا زالت بلاطة المزامنة غير مفعلة في نسخة b55» بعد اكتمال دفعات
    // م4 الست (د0..د6 — س160..س177) — تفتح نافذة العمل الجماعي ذاتها
    // (س175) خلف صلاحية «sync» والحد الصادق بلسان الشاشة ذاتها: لا
    // مزوّد مضبوطاً بعد والفرض الخادمي موضع س-25 بتصديق مكتوب.
    ('sync', 'المزامنة',
        'رمز الانضمام وسجل الأجهزة وحالة الأرشفة السحابية',
        true),
    ('settings', 'الإعدادات', 'النسخ الاحتياطي والاستعادة وفحص الثوابت', true),
    // س211 (D-216): وحدة «المستخدمون» — إنشاء المستخدمين وحالتهم
    // (المفتاح المفقود للتبديل) — نهاية القائمة عرف D-098 فلا تُزيح
    // بنداً ولا ميزانية سحب، وبوابتاها الفرعيتان تفصلان اليدَين.
    ('users', 'المستخدمون',
        'إنشاء المستخدمين وحالتهم وتعطيلهم', true),
  ];

  /// أيقونات الوحدات المفتوحة — خريطة ثابتة بدل سلسلة الشروط الطويلة،
  /// والغائب يأخذ أيقونة الإعدادات الاعتيادية.
  static const Map<String, IconData> _moduleIcons = {
    // س202: بلاطتا الفواتير بأيقونتا نوعيهما (س186) — المبيعات ورقة
    // البيع والمشتريات عربة الشراء.
    'sales': Icons.receipt_outlined,
    'purchases': Icons.shopping_cart_outlined,
    'parties': Icons.people_outline,
    'items': Icons.inventory_2_outlined,
    'warehouses': Icons.warehouse_outlined, // الدفعة 24 (أولى م2)
    'vouchers': Icons.request_quote_outlined,
    'delivery': Icons.local_shipping_outlined, // متابعة التسليم (D-133)
    'orders': Icons.assignment_outlined, // الطلبات (س123)
    'receivables': Icons.handshake_outlined, // الذمم (س125)
    'ledger': Icons.menu_book_outlined, // الدفتر المحاسبي (س125)
    'boxes': Icons.account_balance_wallet_outlined,
    'roles': Icons.shield_outlined,
    'reports': Icons.query_stats,
    // D-198 (س98): أيقتا الوحدتين والعملات بعد فتح بلاطتيهما.
    'units': Icons.straighten_outlined,
    'currencies': Icons.currency_exchange,
    'followups': Icons.notifications_active_outlined, // س141 (د-7)
    // س178: بلاطة المزامنة بأيقونة بطاقة الإعدادات ذاتها (نافذة واحدة).
    'sync': Icons.devices_other_outlined,
    // س211 (D-216): بلاطة المستخدمين — إنشاء من زر الإضافة وحالتهم
    // بالقائمة، والأيقونة جمعُ الأشخاص لا التعيين.
    'users': Icons.group_outlined,
  };

  // س225 (خ2 من الدفعة الأولى للحيوية بأمر المالك): تمايز الوحدات
  // بثلاث عائلات من مشتقات الستة المعتمدة (عقد س182) بلا لون خام:
  // عائلة الهوية البنية (primaryContainer) لوحدات المال، والثانوية
  // (secondaryContainer) لوحدات العلاقات والمتابعة، والمحايد
  // (surfaceContainerHighest) للبنيوية والمرجعية — والأخضر والأحمر
  // حصراً دلالة (س203) فلا يدخلان الهوية أبداً، والمعطلة محايدة
  // حرفاً فالقفل لا يدعو.
  static const Set<String> _moneyModuleKeys = {
    'sales', 'purchases', 'vouchers', 'boxes',
  };
  static const Set<String> _neutralModuleKeys = {
    'items', 'units', 'warehouses', 'ledger', 'reports',
    'currencies', 'roles', 'users', 'settings', 'sync',
  };

  /// صلاحيات صاحب الجلسة — فراغها «قيد التحميل» فيعرض مؤقت الانتظار
  /// لا قائمة فارغة (الفشل المغلق: لا وحدة تُظهر قبل جواب الدور).
  RolePermissions? _permissions;

  /// اسم المستخدم صاحب الجلسة — للعرض أسفل الهيكلية فيعرف المالك
  /// بمن هو داخل (D-100 معروض).
  String? _sessionLabel;

  /// نتيجة الفحص الافتتاحي الصامت — نظيفة تبقى null فلا شيء ظاهر.
  IntegrityReport? _openingViolations;

  /// س141 (د-7/§25.9): لقطة المتابعات النشطة — الشارة الحمراء على
  /// الرئيسية حتى تُعالج، وتتحدث بكل عودة من وحدة (المتابعة تجميع
  /// عرض فوق مصادر تتغير بالاستعمال).
  /// س209 (الطبقة 3 — نبض العمل): اللقطة كاملة محفوظة فبطاقات النبض
  /// تقرأ عداداتها من مدخلاتها القائمة حصراً (تحت الحد وفوق السقف
  /// والمدة) — لا استعلام جديد ولا مساس بالمجال والتخزين حرفاً.
  FollowUpsSnapshot? _followUpsSnapshot;

  /// عدد المتابعات النشطة من اللقطة — صفر قبل جوابها (الفراغ الهادئ).
  int get _followUpsCount => _followUpsSnapshot?.entries.length ?? 0;

  /// س203: مفاتيح البلاطات المثبتة بالوصول السريع — بترتيب التثبيت.
  List<String> _pinned = <String>[];

  @override
  void initState() {
    super.initState();
    // س213 (D-217): حارس الخمول يبدأ بوجه الجلسة النشطة حصراً —
    // القفل يدوي أو آلي (الخمول أو مغادرة التطبيق) يكتب الراية
    // بالآلة ثم يُنادي بغلّ بوابة الإقلاع فبوابة الجهاز هي الوجه،
    // والانحلّ هنا يوقف الحارس ذاتياً (فلا قفل على بلا جلسة).
    SessionIdleGuard.instance.start(
      widget.db,
      onLocked: () => widget.onLocked?.call(),
    );
    _loadSession();
    _openingIntegrityCheck();
    _refreshFollowUps();
    _loadQuickAccess();
    // س233 (D-233 — المرحلة أ/4): قراءة إعداد المزامنة لمؤشرها الصغير
    // بالتذييل — يظهر عند وجود دفتر انضمام حصراً (صمت غير المفعلة).
    _loadSyncConfigured();
    // س221 (ثبات نبض العمل — دفعة النسخ والاستعادة): لقطة النبض تقرأ
    // من مصدر النسخ حصراً (حصة التخزين ونسخ الطوارئ بمدخلاتها) —
    // فتغيّر صحة النسخ يجدّدها حياً كي لا تبقى البطاقة على قيمة ميتة
    // بعد نسخة مجدولة أو مراجعة كتالوج، والتجديد نفسه بعقد «لا تُسقط
    // الرئيسية أبداً» (الإخفاق محاط داخل _refreshFollowUps ذاته).
    BackupCenter.instance?.health.addListener(_onHealthChanged);
  }

  /// س221 — صحة النسخ تغيّرت فالنبض يُجدد من مصدره.
  void _onHealthChanged() {
    _refreshFollowUps();
  }

  /// س233 (D-233): هل المزامنة مفعلة (دفتر انضمام قائم)؟ — المؤشر
  /// الصغير بالتذييل يظهر حين true حصراً (صمت غير المفعلة).
  bool _syncConfigured = false;

  Future<void> _loadSyncConfigured() async {
    try {
      final book = await widget.db.joinCodeBookText();
      if (!mounted) return;
      setState(() => _syncConfigured = book != null);
    } catch (_) {
      // بلا مؤشر — لا تُسقط الرئيسية أبداً (عقد س221 عينه).
    }
  }

  @override
  void dispose() {
    // س221 — فك مستمع صحة النسخ مع الانحلّ فلا نداء على حالة ميتة.
    BackupCenter.instance?.health.removeListener(_onHealthChanged);
    SessionIdleGuard.instance.stop();
    super.dispose();
  }

  Future<void> _refreshFollowUps() async {
    try {
      final snapshot = await loadFollowUps(widget.db);
      if (!mounted) return;
      // س209: اللقطة كاملة محفوظة — العدد getter منها وبطاقات النبض
      // تقرأ مدخلاتها من المصدر ذاته لا من استعلام ثانٍ.
      setState(() => _followUpsSnapshot = snapshot);
    } catch (e) {
      await dqLog(widget.db, e, context: 'home.followups');
      // المتابعات لا تُسقط الرئيسية أبداً — بلا شارة لا قائمة ميتة.
    }
  }

  Future<void> _openFollowUps() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FollowUpsScreen(
            db: widget.db,
            dbPath: widget.dbPath,
            onRestored: widget.onRestored)));
    await _refreshFollowUps();
  }

  /// س221 — وجه بطاقة الأصناف: شاشة الأصناف المصدر (استقلال البطاقات
  /// بقرار المالك — كل ملاحظة وجهها الحقيقي لا بوابة واحدة)، والتفصيل
  /// الكامل بالمدخل ذاته بشاشة المتابعات.
  void _openItems() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ItemsScreen(db: widget.db)));

  /// س221 — وجه بطاقتا الذمم: شاشة الذمم بأرصدتها وأعمارها (تبويباها
  /// القائمان يغطيان السقف المبلغي ومدة السداد معاً).
  void _openReceivables() =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ReceivablesScreen(db: widget.db)));

  /// س198 (م12): بناء قائمة التنبيهات من مصادرها (صحة النسخ الحية
  /// والفحص الافتتاحي — والمتابعات بعقد س221 من نبض العمل حصراً) ثم
  /// عرضها لافتة واحدة ومدخلاً.
  Widget _alertsFor(BuildContext context, BackupHealth? health) {
    final alerts = homeAlerts(
      context: context,
      health: health,
      violationsCount: _openingViolations?.violations.length,
    );
    if (alerts.isEmpty) return const SizedBox.shrink();
    return _alertsBlock(alerts);
  }

  /// س198 (م12): اللافتة الواحدة للأعلى أولوية حصراً، والبقية خلف
  /// مدخل التنبيهات بشارة عدد يفتح حوارها بأفعالها كاملة —
  /// فالمعلومة كلها باقية والانقطاع بقدر الأهمية لا بقدر العدد.
  Widget _alertsBlock(List<HomeAlert> alerts) {
    final top = alerts.first;
    final rest = alerts.sublist(1);
    return Column(children: [
      MaterialBanner(
        backgroundColor: top.color,
        content: Text(top.message, style: TextStyle(color: top.onColor)),
        actions: [
          TextButton(
            onPressed: () => _runAlertAction(top.action),
            child: Text(top.actionLabel),
          ),
        ],
      ),
      if (rest.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Icon(Icons.notifications_active_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text('تنبيهات أخرى: ${rest.length}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            TextButton(
              onPressed: () => _showOtherAlerts(rest),
              child: const Text('عرض'),
            ),
          ]),
        ),
    ]);
  }

  /// س198 (م12): تنفيذ فعل التنبيه — والأغلق الآن حقيقي بمسح الحالة
  /// من الجذر (كان hideCurrentMaterialBanner بلا أثر على لافتة
  /// مضمّنة).
  void _runAlertAction(HomeAlertAction action) {
    switch (action) {
      case HomeAlertAction.settings:
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SettingsScreen(
                  db: widget.db,
                  dbPath: widget.dbPath,
                  onRestored: widget.onRestored)),
        );
      case HomeAlertAction.closeViolations:
        setState(() => _openingViolations = null);
    }
  }

  /// س198 (م12): حوار «التنبيهات الأخرى» — كل بند برسالته وفعلِه
  /// حرفاً كما كانت لافتته، فلا معلومة ضاعت بتكديسها.
  Future<void> _showOtherAlerts(List<HomeAlert> rest) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('التنبيهات'),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rest.length; i++) ...[
                if (i > 0) const Divider(),
                Row(children: [
                  Expanded(child: Text(rest[i].message)),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _runAlertAction(rest[i].action);
                    },
                    child: Text(rest[i].actionLabel),
                  ),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// س203: قراءة المثبتات من المخزن المحلي بعد أول إطار.
  Future<void> _loadQuickAccess() async {
    final saved = await loadQuickAccess();
    if (!mounted) return;
    setState(() => _pinned = saved);
  }

  /// س203: تثبيت بلاطة بالضغطة المطولة — والحد أربعة فرضاً صارماً
  /// برسالة عربية لا صمت، والمثبت مسبقاً يعاد تجاهله.
  Future<void> _pinModule(String key) async {
    if (_pinned.contains(key)) return;
    if (_pinned.length >= kQuickAccessLimit) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الوصول السريع أربعة كحدٍّ أقصى — ألغِ واحداً أولاً'),
      ));
      return;
    }
    setState(() => _pinned = <String>[..._pinned, key]);
    await saveQuickAccess(_pinned);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('ثُبّت في الوصول السريع'),
    ));
  }

  /// س203: إلغاء التثبيت بعلامة حذف اللاصقة.
  Future<void> _unpinModule(String key) async {
    setState(() => _pinned = [
          for (final k in _pinned)
            if (k != key) k,
        ]);
    await saveQuickAccess(_pinned);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('أُلغي التثبيت'),
    ));
  }

  /// فتح الوحدة بمفتاحها — مسار البلاطة واللاصقة معاً (س203)،
  /// وتحديث شارة المتابعات بعد العودة (س141).
  Future<void> _openModule(String key) async {
    final target = _moduleTarget(key);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => target,
    ));
    if (!mounted) return;
    _refreshFollowUps();
  }

  /// س203: صندوق الوصول السريع — فوق الشبكة بمعزل عنها: لاصقات
  /// الوحدات المثبتة بترتيب التثبيت، مفلترة بالصلاحية (لا لاصقة
  /// لوحدة من دورك مغلقة) وبمفاتيح قائمة حصراً فلا مفتاح قديم
  /// يكسر، والفراغ إرشاد لا صندوق ميت (F-162 روحاً).
  Widget _quickAccessBox(RolePermissions permissions) {
    final scheme = Theme.of(context).colorScheme;
    final pinned = <(String, String, String, bool)>[
      for (final k in _pinned)
        for (final m in _modules)
          if (m.$1 == k && permissions.allows(_permissionKeyOf(k))) m,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.push_pin_outlined,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: kDiqqahSpacingS),
            Text('الوصول السريع',
                style: Theme.of(context).textTheme.labelMedium),
          ]),
          const SizedBox(height: kDiqqahSpacingS),
          if (pinned.isEmpty)
            Text('اضغط مطولاً على أي بلاطة لتثبيتها هنا — الحد أربعة',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant))
          else
            Wrap(
              key: const ValueKey('home_quick_access'),
              spacing: kDiqqahSpacingS,
              runSpacing: kDiqqahSpacingS,
              children: [
                for (final (key, title, _, __) in pinned)
                  InputChip(
                    avatar: Icon(
                        _moduleIcons[key] ?? Icons.settings_outlined,
                        size: 18),
                    label: Text(title),
                    onPressed: () => _openModule(key),
                    onDeleted: () => _unpinModule(key),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// س212 (D-215): أفعال الثلاثة مسارات انتقال لا حالات — القفل
  /// والتبديل قفلٌ بفتح سريع لنفس المستخدم (التبديل قفلٌ ثم بلاطة
  /// أخرى تُختار بالبوابة ذاتها فكلاهما lockSession)، والخروج قفل
  /// بلا مستخدم مستأنف فlogoutSession تمسّ المستأنف — والراية
  /// بالقاعدة أولاً ثم نداء الغلق فتعود بوابة الجهاز.
  Future<void> _sessionAction(String action) async {
    switch (action) {
      case 'logout':
        await widget.db.logoutSession();
      case 'lock':
      case 'switch':
        await widget.db.lockSession();
    }
    if (!mounted) return;
    widget.onLocked?.call();
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
    } catch (e) {
      await dqLog(widget.db, e, context: 'home.session');
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
    } catch (e) {
      await dqLog(widget.db, e, context: 'home.integrity');
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
        // س203 (صقل M3): صاحب الجلسة أعلى الهيكلية
        // لا أسفلها — كان خلف شريط التنقل السفلي.
        // س212 (D-215): شارة الجلسة صارت قائمة أفعال الثلاثة —
        // القفل والتبديل والخروج بنمط ويندوز/أندرويد الموثق بالمقارنة،
        // ومن لا جلسة له فلا قائمة (السقوط الآمن سقوط صامت).
        actions: [
          if (_sessionLabel != null)
            PopupMenuButton<String>(
              tooltip: 'الجلسة',
              onSelected: (action) => _sessionAction(action),
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'lock', child: Text('قفل الجلسة')),
                PopupMenuItem(
                    value: 'switch', child: Text('تبديل المستخدم')),
                PopupMenuItem(value: 'logout', child: Text('خروج')),
              ],
              child: Padding(
                padding:
                    const EdgeInsetsDirectional.only(end: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_outline,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(_sessionLabel!,
                      style: Theme.of(context).textTheme.bodySmall),
                  Icon(Icons.arrow_drop_down,
                      size: 18,
                      color: Theme.of(context)
                          .colorScheme.onSurfaceVariant),
                ]),
              ),
            ),
        ],
      ),
      body: permissions == null
          // الفشل المغلق: مؤقت انتظار جواب الدور — لا قائمة قبل الصلاحيات
          // (شريحة من الثانية على قاعدة محلية).
          ? const Center(child: CircularProgressIndicator())
          // س138 (تكليف المالك 2026-11-14): سطر «الجلسة» أسفل الهيكلية كان
          // خلف شريط التنقل السفلي بأندرويد (الرسم الحافي — الجسم يمدُّ
          // تحت حزام النظام بلا حزام واجهة). فالجسم كله داخل الحزام
          // السفلي: الجلسة وآخر أسطر القائمة يرتفعان فوقه، والعلوي
          // محسوب بـAppBar أصلاً فلا حزام فوق.
          : SafeArea(
              top: false,
              child: Column(
              children: [
                // س198 (م12 من تقرير فحص الواجهات وفق M3): اللافتات
                // الثلاث كانت تتراكم رأسياً فتلتهم رأس الشاشة وتتساوى
                // في الانقطاع رغم تفاوت الأهمية. صارت قائمة تنبيهات
                // مرتبة بالأولوية تُعرض لافتتها الأولى حصراً والبقية
                // خلف مدخل التنبيهات بشارة عدد — فالمعلومة كاملة
                // والشاشة هادئة (homeAlerts بأولوياتها الموثقة).
                if (BackupCenter.instance != null)
                  ValueListenableBuilder<BackupHealth?>(
                    valueListenable: BackupCenter.instance!.health,
                    builder: (context, health, _) =>
                        _alertsFor(context, health),
                  )
                else
                  _alertsFor(context, null),
                Expanded(
                  child: SingleChildScrollView(
                    // م06 التكيفي لويندوز (س205): المحتوى يتوسّط بعرضه
                    // الأقصى على العريض فلا يمتد حرفاً من طرفٍ لطرف،
                    // والضيّق (الجوال وقصوى الاختبار) كما كان حرفاً.
                    child: DiqqahAdaptiveCenter(
                      child: Column(
                      children: [
                        // س182 (بأمر المالك «اعتمد مبدأ الأيقونات في
                        // الواجهة مباشرة لا القائمة»): شبكة أيقونات
                        // الوحدات بدل قائمة الأسطر — فرض الصلاحيات كما
                        // كان (F-080/D-100) والمتابعات بشائرتها (س141).
                        // س202: بطاقة الفواتير سُحبت من فوق الشبكة
                        // (بأمر المالك «التراجع عنه إلى أيقونتين كالبقية»)
                        // — بلاطتا المبيعات والمشتريات أولها بنَسَق البقية
                        // وبصلاحية «الفواتير» ذاتها — واستدعاء واحد لا
                        // ثانٍ (درس الجولة #385: الازدواج ضاعف الشبكة).
                        // س203: الوصول السريع فوق الشبكة بمعزل عنها.
                        // س209 الطبقة 3: نبض العمل — بالوجود لا بالوعد
                        // (التفصيلية الصفرية غائبة) فلا بطاقة صفرية
                        // تزاحم الشاشة.
                        _pulseBlock(),
                        _quickAccessBox(permissions),
                        // س209 الطبقة 5: شبكة الوحدات — بطاقات على العريض
                        // وبلاطاتها القائمة على الضيّق (قانون العرض).
                        _modulesGrid(permissions),
                        // س209 الطبقة 6: التذييل — سطر الإصدار.
                        _homeFooter(),
                      ],
                    ),
                  ),
                ),
                ),
              ],
            ),
          ),
    );
  }

  /// س202: مفتاح صلاحية البلاطة — مفتاحا بلاطتَي الفواتير الجهويان
  /// يحسمان إلى الصلاحية الأم «invoices» والبقية بمفتاحها القائم.
  static String _permissionKeyOf(String key) =>
      key == 'sales' || key == 'purchases' ? 'invoices' : key;

  /// س209 الطبقة 3 — نبض العمل: بطاقات إحصاء قرائية من لقطة المتابعات
  /// المحمّلة أصلاً حصراً (لا استعلام جديد ولا مساس بالمجال والتخزين
  /// حرفاً): البطاقة الجامعة «متابعات نشطة» بفعلها القائم (فتح
  /// المتابعات) والتفصيلية الثلاث بمعلومها من مدخلات اللقطة القائمة
  /// (د6 المتابعات اليومية س74/D-184) — وبالوجود لا بالوعد: الطبقة
  /// تنطبق بأكملها حين كل العدادات صفر (الصمت الهادئ عرف س198).
  ///
  /// س221 (قرار المالك: التصميم يوحي باستقلال البطاقات فالفعل يطابق):
  /// كل بطاقة وجهها الحقيقي — الأصناف بشاشة الأصناف والذمم بشاشة
  /// الذمم، فلا بطاقة ميتة النقر ولا بوابة واحدة غير معلنة.
  Widget _pulseBlock() {
    final snapshot = _followUpsSnapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final input = snapshot.input;
    // س225 (خ1 من الدفعة الأولى للحيوية بأمر المالك): أيقونات النبض
    // وأعدادها بألوان الأزقة الدلالية المعتمدة لا الرمادي المطفي —
    // وبعقد س186 حرفاً: المجموعة الإجمالية والأصناف تحت الحد انتباه
    // أزرق (تنبيه بلا فشل)، وفوق السقف وفوق المدى خطر مالي سلبي
    // أحمر — والبني والأخضر لا يدخلان هنا فالنبض لا هوية ولا دائن.
    final lanes = diqqahLanesOf(context);
    final cards = <(String, int, IconData, DiqqahLane, VoidCallback?)>[
      ('متابعات نشطة', snapshot.entries.length,
          Icons.notifications_active_outlined, lanes.attention,
          _openFollowUps),
      ('أصناف تحت الحد الأدنى', input.belowMinimumItems.length,
          Icons.inventory_2_outlined, lanes.attention, _openItems),
      ('أطراف فوق سقفها المبلغي', input.overAmountCapBalances.length,
          Icons.account_balance_wallet_outlined, lanes.negative,
          _openReceivables),
      ('أطراف تجاوزت مدة السداد', input.overTimeCapBalances.length,
          Icons.schedule_outlined, lanes.negative, _openReceivables),
    ];
    final shown = [for (final c in cards) if (c.$2 > 0) c];
    if (shown.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          kDiqqahSpacingM, kDiqqahSpacingS, kDiqqahSpacingM, 0),
      // س209: عرض البطاقتين من قيود التخطيط لا من قراءة MediaQuery —
      // درس الاختبار المحافي الموثق بالدفعة: القراءة الصفرية ل MediaQuery
      // بلا حجم تولد قيوداً سالبة تكسر البناء، وقيود التخطيط هي
      // الحقيقة السارية أبداً فالبطاقة من قيدها لا من قراءة خارجية.
      child: LayoutBuilder(builder: (context, constraints) {
        final double cardWidth = constraints.maxWidth.isFinite &&
                constraints.maxWidth > kDiqqahSpacingS
            ? (constraints.maxWidth - kDiqqahSpacingS) / 2
            : 160.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.monitor_heart_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: kDiqqahSpacingS),
              Text('نبض العمل',
                  style: Theme.of(context).textTheme.labelMedium),
            ]),
            const SizedBox(height: kDiqqahSpacingS),
            Wrap(
              key: const ValueKey('home_pulse'),
              spacing: kDiqqahSpacingS,
              runSpacing: kDiqqahSpacingS,
              children: [
                for (final (label, count, icon, lane, onTap) in shown)
                  SizedBox(
                      width: cardWidth,
                      height: 56,
                      child: _pulseCard(label, count, icon, lane, onTap)),
              ],
            ),
          ],
        );
      }),
    );
  }

  /// بطاقة نبض واحدة — سطح البطاقة المسطح (س203) بأيقونتها ولسانها
  /// وعدّادها بلون الزوق الدلالي لبطاقتها (س225 خ1 — أدوار الأزقة
  /// المعتمدة لا ألوان خام بعرف م05/س186)، والفعل بعقد س221: كل
  /// بطاقة تفتح وجهها الحقيقي فلا ميت النقر.
  Widget _pulseCard(String label, int count, IconData icon,
      DiqqahLane lane, VoidCallback? onTap) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kDiqqahSpacingM, vertical: kDiqqahSpacingXs),
          child: Row(children: [
            Icon(icon, size: 20, color: lane.fg),
            const SizedBox(width: kDiqqahSpacingS),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium)),
            const SizedBox(width: kDiqqahSpacingS),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: kDiqqahSpacingS, vertical: kDiqqahSpacingXs),
              decoration: BoxDecoration(
                  color: lane.bg,
                  border: Border.all(color: lane.border, width: 1),
                  borderRadius: BorderRadius.circular(12)),
              constraints: const BoxConstraints(minWidth: 24),
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: lane.fg, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }

  /// س182 (بأمر المالك «اعتمد مبدأ الأيقونات في الواجهة مباشرة لا
  /// القائمة» — استئناس غير ملزم بما أعجبه بواجهة aureuserp): شبكة
  /// الوحدات — كل وحدة بلاطة أيقونة دائرية بلسانها تحت اسمها تفتح
  /// شاشتها بضغطة واحدة، بدل قائمة أسطر طويلة. فرض الصلاحيات كما كان
  /// (F-080/D-100): وحدات الدور المفتوحة حصراً والمعطلات للجميع
  /// (إظهار الواقع F-016 بأيقونة القفل) — ووصف المرحلة انتقل إلى
  /// تلميح الأيقونة فلا معلومة ضاعت ولا حاشية أثقلت البلاطة.
  Widget _modulesGrid(RolePermissions permissions) {
    final visible = <(String, String, String, bool)>[
      for (final (key, title, stage, enabled) in _modules)
        if (!enabled || permissions.allows(_permissionKeyOf(key)))
          (key, title, stage, enabled),
    ];
    // Wrap لا GridView عمداً: الشبكة تخلق Scrollable ثانياً داخل تمرير
    // الرئيسية فيكسر عرف اختباراتها القائمة (find.byType(Scrollable)
    // الواحد) — وWrap يوزع البلاطات صفوفاً بتلقائية العرض نفسه.
    // س209 (قانون العرض — شبكة أعمدة وبطاقة لا أيقونة): فوق حد
    // التوسيط 800 البلاطات بطاقات بأربعة أعمدة محسوبة من المتاح
    // بوصف المرحلة ظاهراً؛ وعند الحد وأدنه البلاطات الأيقونية
    // القائمة حرفاً بعرف 104 ثابتة فلا مساس بأي موضع مختبر —
    // فالبطاقة تُفعّل حيث يُفعّل التوسيط بالضبط فلا سلوكان للحدين.
    final width = MediaQuery.sizeOf(context).width;
    final cards = width > kDiqqahAdaptiveMaxWidth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Wrap(
        key: const ValueKey('home_modules_grid'),
        spacing: cards ? kDiqqahSpacingS : 4,
        runSpacing: cards ? kDiqqahSpacingS : 4,
        children: [
          for (final (key, title, stage, enabled) in visible)
            cards
                ? SizedBox(
                    width: (kDiqqahAdaptiveMaxWidth -
                            2 * kDiqqahSpacingM -
                            (kDiqqahModuleGridColumns - 1) * kDiqqahSpacingS) /
                        kDiqqahModuleGridColumns,
                    height: 156,
                    child: _moduleCard(key, title, stage, enabled))
                : SizedBox(
                    width: 104,
                    height: 100,
                    child: _moduleTile(key, title, stage, enabled)),
        ],
      ),
    );
  }

  /// القرص الأيقوني بشارة المتابعات — مصدر واحد للبلاطة والبطاقة
  /// معاً (درس الجولة #385 الموثق: مصدر واحد لا ازدواج)، والموضع
  /// اتجاهي بعرف م18 (الشارة فوق زاوية القرص بالنهاية الاتجاهية).
  /// س225 (خ2): لون القرص بعائلة وحدته أعلاه — المال بنية والعلاقات
  /// ثانوية والبنيوية محايدة، والمعطلة محايدة دائماً.
  Widget _moduleDisc(
      String key, IconData icon, ColorScheme scheme, double size,
      {required bool enabled}) {
    final (Color discColor, Color discFg) = !enabled
        ? (scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : switch (key) {
            _ when _moneyModuleKeys.contains(key) => (
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
              ),
            _ when _neutralModuleKeys.contains(key) => (
                scheme.surfaceContainerHighest,
                scheme.onSurfaceVariant,
              ),
            _ => (
                scheme.secondaryContainer,
                scheme.onSecondaryContainer,
              ),
          };
    return Stack(
      clipBehavior: Clip.none,
      alignment: AlignmentDirectional.center,
      children: [
        Container(
          width: size,
          height: size,
          alignment: AlignmentDirectional.center,
          decoration: BoxDecoration(
            color: discColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: discFg),
        ),
        if (key == 'followups' && _followUpsCount > 0)
          PositionedDirectional(
            top: -2,
            end: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                '$_followUpsCount',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onError,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// س209 (قانون العرض — بطاقة لا أيقونة): بلاطة الوحدة على العريض
  /// بطاقة بسطح البطاقة المسطح (س203) بأيقونتها القرصية وعنوانها
  /// ووصف مرحلتها ظاهراً — ما كان تلميحاً حصراً صار معروضاً فالمعلومة
  /// كاملة بلا تلميح يكرر ما ظاهر بعرف بند 4 س207 — وفرض الصلاحيات
  /// والشارة والضغطة المطولة للتثبيت كما هي حرفاً، والبنية اتجاهية.
  Widget _moduleCard(String key, String title, String stage, bool enabled) {
    final scheme = Theme.of(context).colorScheme;
    final icon = !enabled
        ? Icons.lock_outline
        : _moduleIcons[key] ?? Icons.settings_outlined;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => _openModule(key) : null,
        // س203: الضغطة المطولة تثبت بالوصول السريع كما في البلاطة.
        onLongPress: enabled ? () => _pinModule(key) : null,
        child: Padding(
          padding: const EdgeInsets.all(kDiqqahSpacingM),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _moduleDisc(key, icon, scheme, 48,
                    enabled: enabled),
              ),
              const SizedBox(height: kDiqqahSpacingS),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: kDiqqahSpacingXs),
              Text(
                stage,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// بلاطة وحدة بالشبكة — الأيقونة داخل قرص لوني من دور الثيم
  /// (secondaryContainer/onSecondaryContainer — س182/م05) فتتبدل
  /// بأدوار الطبقة مع الوضعين لا بألوان خام. وس141: بلاطة المتابعات
  /// تحمل شارة عددها النشط (د-7: حتى تُعالَج).
  Widget _moduleTile(String key, String title, String stage, bool enabled) {
    final scheme = Theme.of(context).colorScheme;
    final icon = !enabled
        ? Icons.lock_outline
        : _moduleIcons[key] ?? Icons.settings_outlined;
    final tip = enabled ? stage : 'معطلة — متاح في $stage';
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => _openModule(key) : null,
        // س203: الضغطة المطولة تثبت بالوصول السريع — الحد أربعة
        // والرسالة عند الامتلاء لا صمت.
        onLongPress: enabled ? () => _pinModule(key) : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // س202: شارة المتابعات موضعها ثابت فوق زاوية القرص —
            // والأيقونة مركز القرص حصراً فلا ينزاح مركزها حضوراً
            // الشارة أو غياباً (ملاحظة المالك: الجرس انزاح يمين
            // مجيء الشارة بعرف Badge الافتراضي) — والقرص مصدره
            // الواحد المشترك س209 فبلاطة والبطاقة قرصهما واحد.
            _moduleDisc(key, icon, scheme, 56, enabled: enabled),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// هدف فتح الوحدة — بالمفتاح الثابت لا بالاسم الظاهر (س202: التسميتان
  /// «الوحدات»/«الطلبات» اختصرتا بلسان المالك فصار التوجيه بالمفتاح
  /// لا بنص الواجهة المتغير، وبلاطتا الفواتير بجهتيهما).
  Widget _moduleTarget(String key) => switch (key) {
        // س202: بلاطتا الفواتير تفتحان الأرشيف بجهته — فلتر الجهة
        // وورقة الإدخال بإدراك الجهة (س202 بشاشة الفواتير والتخزين).
        'sales' => InvoicesScreen(
            db: widget.db,
            initialSide: InvoiceArchiveSide.sales,
          ),
        'purchases' => InvoicesScreen(
            db: widget.db,
            initialSide: InvoiceArchiveSide.purchases,
          ),
        'parties' => PartiesScreen(db: widget.db),
        'items' => ItemsScreen(db: widget.db),
        'warehouses' => WarehousesScreen(db: widget.db),
        'reports' => ReportsScreen(db: widget.db),
        'vouchers' => VouchersScreen(db: widget.db),
        'delivery' => DeliveryScreen(db: widget.db),
        'orders' => OrdersScreen(db: widget.db),
        // س125 (تفعيل الذمم والدفتر): بلاطتاهما تفتحان شاشتيهما
        // الجديدتين بقراءة خالصة فوق البنية المنجزة م1.
        'receivables' => ReceivablesScreen(db: widget.db),
        'ledger' => LedgerScreen(db: widget.db),
        'boxes' => BoxesScreen(db: widget.db),
        'roles' => RolesScreen(db: widget.db),
        // D-198 (س98): بلاطتا الوحدات والعملات تفتحان شاشتيهما —
        // نفس الشاشتين المدخلتين من الأصناف والإعدادات.
        'units' => UnitGroupsScreen(db: widget.db),
        'currencies' => CurrenciesScreen(db: widget.db),
        // س141 (د-7/§25.9): المتابعات بلاطتها بشائرتها.
        'followups' => FollowUpsScreen(
            db: widget.db,
            dbPath: widget.dbPath,
            onRestored: widget.onRestored),
        // س178 (تفعيل المزامنة): نافذة العمل الجماعي ذاتها المدخلة من
        // الإعدادات (س175) — لا شاشة ثانية.
        'sync' => SyncWorkScreen(db: widget.db),
        // س211 (D-216): شاشة المستخدمين الجديدة — الإنشاء والحالة
        // بحمولة البوابتين الفرعيتين.
        'users' => UsersScreen(db: widget.db),
        _ => SettingsScreen(
            db: widget.db,
            dbPath: widget.dbPath,
            onRestored: widget.onRestored,
            onSessionLocked: () {
              // س212 (D-215): التبديل عبر الآلة — الإعدادات تُغلق
              // والراية مقفلة فبوابة الجهاز هي الوجه (لا رئيسية
              // على جلسة مقفلة).
              Navigator.of(context).pop();
              widget.onLocked?.call();
            },
          ),
      };

  /// س209 الطبقة 6 — التذييل: سطر الإصدار بدالة العرض القائمة
  /// diqqahVersionLine بنسخة العرض المحقونة من CI (D-213) — فارغ
  /// التطوير والاختبار بعرفها فلا ضجيج ولا كسر، والمفتاح حاضر
  /// لاكتمال الطبقة بنيوياً في الاختبار.
  Widget _homeFooter() {
    final line = diqqahVersionLine(kAppVersion, kBuildNumber);
    return Padding(
      key: const ValueKey('home_footer'),
      padding: const EdgeInsets.fromLTRB(
          kDiqqahSpacingM, kDiqqahSpacingS, kDiqqahSpacingM, kDiqqahSpacingM),
      child: Column(
        children: [
          // س233 (D-233 — المرحلة أ/4): مؤشرا الحالة الصغيران — النسخ
          // والمزامنة داخل طبقة التذييل القائمة ذاتها (لا طبقة سابعة
          // ولا شاشة انتظار) — الست طبقات (س209) باقية ستاً.
          _statusChips(),
          if (line.isNotEmpty)
            Text(
              line,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  /// س233 (D-233 — المرحلة أ/4): مؤشرا النسخ والمزامنة الصغيران بلغة
  /// التذييل — النسخ: يعمل بآخر نسخة آلية سليمة / متوقف (كهرماني) /
  /// فشلت الأخيرة (أحمر)، والمزامنة تظهر عند وجود دفتر انضمام حصراً
  /// فلا ضجيج لغير المفعلة (عرف الصمت الهادئ س198).
  Widget _statusChips() {
    final lanes = diqqahLanesOf(context);
    return Padding(
      key: const ValueKey('home_status_chips'),
      padding: const EdgeInsets.only(bottom: kDiqqahSpacingS),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: kDiqqahSpacingM,
        runSpacing: 4,
        children: [
          ListenableBuilder(
            // س233: النسخ — المفتاح الرئيسي بالخيارات وصحة المركز معاً
            // فالرقاقة تتجدد لحظة تغير أيهما (المركز غائب بالاختبارات
            // فتبقى الرقاقة على وجهها الأول بلا استثناء).
            listenable: Listenable.merge([
              autoBackupEnabled,
              BackupCenter.instance?.health,
            ]),
            builder: (context, _) {
              if (!autoBackupEnabled.value) {
                return _statusChip(S.homeBackupPaused,
                    Icons.pause_circle_outline, lanes.attention.fg);
              }
              if ((BackupCenter.instance?.health.value)?.hasFailure ??
                  false) {
                return _statusChip(S.homeBackupFailed,
                    Icons.error_outline, lanes.negative.fg);
              }
              return _statusChip(
                  S.homeBackupActive, Icons.check_circle_outline,
                  lanes.positive.fg);
            },
          ),
          if (_syncConfigured)
            _statusChip(
                S.homeSyncActive,
                Icons.sync_outlined,
                Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  /// س233: رقاقة الحالة الواحدة — أيقونة صغيرة ولسان تذييل بلون زقها.
  Widget _statusChip(String label, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color),
        ),
      ],
    );
  }
}
