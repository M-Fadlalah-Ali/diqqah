import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart'
    show PasswordHasher;
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
import 'l10n/app_strings.dart';
import 'session.dart';
import 'settings/backup_section.dart' show BackupSection;
import 'settings/display_section.dart' show DisplaySection;
import 'settings/identity_section.dart' show IdentitySection;
import 'settings/operations_section.dart' show OperationsSection;
import 'settings/security_section.dart' show SecuritySection;
import 'settings/sales_section.dart' show SalesSection;

/// مساعدات النسخ الخالصة — مكانها الأصلي بذات نصوصها، وتصديرها من
/// هنا باقٍ لمستهلكيها (الاختبارات النقية س229/س-129).
export 'settings/backup_section.dart'
    show freeBackupPath, formatImagesBytes;

/// Task 51: هوية الإصدار تُحقن زمن الترجمة من CI (--dart-define) —
/// مصدر الحقيقة pubspec.yaml، ويظهر السطر للمالك أسفل شاشة الإعدادات
/// فيعرف أي نسخة مثبتة عنده. فارغ في التطوير والاختبار فلا ضجيج ولا كسر.
const String kAppVersion = String.fromEnvironment('APP_VERSION');
const String kBuildNumber = String.fromEnvironment('BUILD_NUMBER');

/// D-213 (كلمة المالك 2026-11-21 «b60 ينتقل ليصبح 0.260 دون الإضافات
/// الأخرى»): الإصدارات الجديدة شطران «0.2N» فالعرض بالإصدار وحده بلا
/// لاحقة البناء (الرقم التشغيلي داخل الحزمة versionCode لا نصاً) —
/// وبالبادئة المُشعرة «v.» بكلمة المالك اللاحقة «أضف قبل رقم الإصدار
/// ما يوحي بأنه رقم الإصدار v.0.260» فالعرض «دِقَّة v.0.260» يُقرأ
/// مُشعراً لا رقماً مجرداً — والبادئة عرضية حصراً: APP_VERSION
/// وكتالوج الإصدار والمرشّح البايتي ⑤ بالصيغة التقنية كما هي فحارس
/// البناء لا ينزلق.
/// والصيغة القديمة الثلاثية (D-058) بلسانها التاريخي: التبطين ومرقّ
/// البناء كما كانت.
String diqqahVersionLine(String version, String build) {
  if (version.isEmpty) return '';
  final parts = version.split('.');
  if (parts.length == 2) return S.appVersionLine(version);
  final display =
      '${parts[0]}.${parts[1]}.${parts[2].padLeft(2, '0')}';
  return build.isEmpty ? S.appTitleWith(display) : S.appTitleWithMinor(display, build);
}

/// شاشة الإعدادات — قشرة تجمع الأقسام الستة (س233 — D-230، المرحلة أ/1
/// من خارطة الطريق الخماسية): شطر «البيانات والأمان» القائم (D-218)
/// قسمين — **الأمان والجلسة** (الخمول وفحص الثوابت) و**النسخ
/// والاستعادة** (النسخ الآلي الجديد D-232 والمجدولة والكاملة
/// والاستعادة ونسخة الصور) — وبقاء **الهوية والصلاحيات** و**سياسات
/// البيع** و**العرض والمظهر** و**العمليات** بأسمائها وترتيبها حرفاً،
/// وبطاقات كل قسم بملفاتها بمجلد settings/ (متنها ونصوصها ومفاتيحها
/// حرفاً فلا اختبار ينقلب ولا ميزانية سحب تنقلب) — والشاشة صفر نص
/// مضمن بعهد حارس النصوص (س232).
///
/// الأصل التاريخي (F-012/F-013 — س-01): الإعدادات ونسخة الاحتياطي
/// الأولى متاحة فوراً بعد التهيئة، والاستعادة بتأكيد مزدوج وإلغاء
/// آمن — ومتن كل ذلك بملفات أقسامه.
class SettingsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// مسار ملف القاعدة الحي — منه يشتق مجلد النسخ ولقطات الرجوع.
  final String dbPath;

  /// بعد استعادة ناجحة: البوابة تعيد بناء القاعدة والشاشات من الملف الجديد.
  final VoidCallback onRestored;

  /// س212 (D-215): نداء الغلق للتبديل عبر آلة الحالتين — الزر
  /// «قفل وتبديل المستخدم» يكتب الراية بالقاعدة بlockSession ثم
  /// ينادي به فتعيد بوابة الإقلاع الجذر على بوابة الجهاز (التبديل
  /// قفلٌ ثم بلاطة أخرى — فلا تبديل مباشر يتجاوز الآلة بعد اليوم).
  /// اختياري — الاختبارات المباشرة لا تمرره.
  final VoidCallback? onSessionLocked;

  /// س211 (D-216): تكرارات الهاش لتغيير الكلمة الذاتي والولادة —
  /// الافتراضي العتبة الآمنة والاختبارات تحقن الصغيرة بنمط first_run.
  final int hasherIterations;

  const SettingsScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
    this.onSessionLocked,
    this.hasherIterations = PasswordHasher.secureIterations,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// جلسة القارئ — بوابات بطاقات الأقسام (المدير ووحدة النسخ).
  SessionInfo? _session;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await loadSession(widget.db);
    if (!mounted) return;
    setState(() => _session = session);
  }

  @override
  Widget build(BuildContext context) {
    final isManager = _session?.permissions.isAll ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text(S.settingsTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16,
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16),
        children: [
          // ── الأقسام الستة (س233 — D-230): ترويسة لكل قسم داخل
          // القائمة ذاتها بلا صفحات فئات (عرف D-218 الخيار أ باقياً)
          // وبترتيبه: الهوية والصلاحيات، الأمان والجلسة، النسخ
          // والاستعادة، سياسات البيع، العرض والمظهر، العمليات.
          _SettingsSectionHeader(S.identitySectionTitle),
          IdentitySection(
            db: widget.db,
            hasherIterations: widget.hasherIterations,
            onSessionLocked: widget.onSessionLocked,
            isManager: isManager,
          ),
          const SizedBox(height: 16),
          _SettingsSectionHeader(S.securitySessionTitle),
          SecuritySection(db: widget.db, isManager: isManager),
          const SizedBox(height: 16),
          _SettingsSectionHeader(S.backupRestoreTitle),
          BackupSection(
            db: widget.db,
            dbPath: widget.dbPath,
            onRestored: widget.onRestored,
            session: _session,
          ),
          const SizedBox(height: 16),
          _SettingsSectionHeader(S.salesPoliciesTitle),
          SalesSection(db: widget.db),
          const SizedBox(height: 16),
          _SettingsSectionHeader(S.displaySectionTitle),
          const DisplaySection(),
          const SizedBox(height: 16),
          _SettingsSectionHeader(S.operationsTitle),
          OperationsSection(db: widget.db, isManager: isManager),
          if (diqqahVersionLine(kAppVersion, kBuildNumber).isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              diqqahVersionLine(kAppVersion, kBuildNumber),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// س213 (D-218 الخيار أ): ترويسة قسم داخل قائمة الإعدادات ذاتها —
/// بلا صفحات فئات ولا جانب كاشف (الخيار ب مؤجل بوعي بقرار D-218
/// مع تذكير تنفيذه): لسان قصير بلون الثيم يفصل الأقسام الستة،
/// والبطاقات تصل بنصّها فاختباراتها لا تنقلب.
class _SettingsSectionHeader extends StatelessWidget {
  final String title;
  const _SettingsSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
