import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'settings_screen.dart';
import 'parties_screen.dart';
import 'items_screen.dart';
import 'reports_screen.dart';
import 'invoices_screen.dart';
import 'boxes_screen.dart';
import 'roles_screen.dart';

/// الشاشة الهيكلية (F-016): قائمة وحدات — إطار التنقل. الوحدات ومراحل
/// توفرها من جدول النطاق (01 §5) حرفاً، والإعدادات متاحة فوراً بعد
/// التهيئة (س-01)، والأطراف أول وحدة تُفتح في م1 (دفعتها الأولى).
class HomeScreen extends StatelessWidget {
  final DiqqahDatabase db;
  final String dbPath;
  final VoidCallback onRestored;

  const HomeScreen({
    super.key,
    required this.db,
    required this.dbPath,
    required this.onRestored,
  });

  /// (اسم الوحدة، مرحلة التوفر في 01، متاحة الآن؟) — إظهار الواقع لا وعود
  /// مبكرة. الإعدادات متاحة فوراً بعد التهيئة (س-01)، والأطراف فُتحت بدفعة
  /// م1 الأولى (F-020..F-023، س-29..س-35) والأصناف بدفعتها الثانية
  /// (F-030/F-031، س-36..س-41) والتقارير اليومية بدفعتها السادسة وواجهاتها
  /// (F-189..F-195، دفعتا 6 و6-ب) والفواتير والصناديق والصلاحيات بدفعة
  /// واجهات الإدخال (6-ج) بأمر المالك «تنفيذها كلها معاً» (س36،
  /// F-196..F-199، D-094..D-097 معروض) — البقية في مفرغها.
  static const List<(String, String, bool)> _modules = [
    ('الأطراف', 'متاحة الآن — بطاقة الأطراف والبحث الجامع (F-020..F-023)', true),
    ('الأصناف', 'متاحة الآن — بطاقة الصنف والوحدات الأساسية (F-030/F-031)', true),
    ('وحدات القياس والتعبئة', 'الإصدار 2 — الإدخال في م1 بالوحدة الأساسية من شاشة الأصناف', false),
    ('المستودعات', 'الإصدار 1 (واحد) → 2 (متعدد + جرد)', false),
    ('الفواتير', 'متاحة الآن — قائمة ونموذج الأنواع الأربعة (F-196..F-198)', true),
    ('طلبات الشراء والبيع', 'لاحقاً — تُقيَّم بعد MVP (D-026)', false),
    ('الذمم', 'الإصدار 1', false),
    ('الصناديق', 'متاحة الآن — القائمة وإنشاء الحساب الآلي (F-199)', true),
    ('الدفتر المحاسبي', 'الإصدار 1 — الأساس', false),
    ('العملات', 'الإصدار 1 (واحدة) → 3 (متعددة + فروق)', false),
    ('الصلاحيات', 'متاحة الآن — الأدوار والمستخدمون قراءةً (D-097)', true),
    ('التقارير اليومية', 'متاحة الآن — التقارير الست والفترات والإقفال (F-189..F-195)', true),
    ('المزامنة', 'الإصدار 4', false),
    ('الإعدادات', 'متاحة الآن — النسخ الاحتياطي والاستعادة (F-012/F-013)', true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دِقَّة'),
      ),
      // قائمة ثابتة تُبنى كاملة — Column تُنفخ كل أبنائها فوراً بلا كسل
      // شجري (ListView حتى بأبناء صريحين يبني الظاهر وحده — درس CI #8)،
      // وSingleChildScrollView يوفر التمرير على الشاشات القصيرة.
      body: SingleChildScrollView(
        child: Column(
          children: [
            for (final (title, stage, enabled) in _modules)
              ListTile(
                leading: Icon(
                  !enabled
                      ? Icons.lock_outline
                      : title == 'الأطراف'
                          ? Icons.people_outline
                          : title == 'الأصناف'
                              ? Icons.inventory_2_outlined
                              : title == 'التقارير اليومية'
                                  ? Icons.query_stats
                                  : title == 'الفواتير'
                                      ? Icons.receipt_long_outlined
                                      : title == 'الصناديق'
                                          ? Icons
                                              .account_balance_wallet_outlined
                                          : title == 'الصلاحيات'
                                              ? Icons.shield_outlined
                                              : Icons.settings_outlined,
                ),
                title: Text(title),
                subtitle: Text(enabled ? stage : 'معطلة — متاح في $stage'),
                enabled: enabled,
                onTap: enabled
                    ? () {
                        // الأطراف (دفعة م1 (1)) والأصناف (دفعة م1 (2))
                        // والتقارير اليومية (دفعتا م1 (6) و(6-ب)) والفواتير
                        // والصناديق والصلاحيات (دفعة (6-ج)) وحدات مفتوحة —
                        // والبقية الإعدادات وحدها حتى دفعاتها.
                        final Widget target = title == 'الأطراف'
                            ? PartiesScreen(db: db)
                            : title == 'الأصناف'
                                ? ItemsScreen(db: db)
                                : title == 'التقارير اليومية'
                                    ? ReportsScreen(db: db)
                                    : title == 'الفواتير'
                                        ? InvoicesScreen(db: db)
                                        : title == 'الصناديق'
                                            ? BoxesScreen(db: db)
                                            : title == 'الصلاحيات'
                                                ? RolesScreen(db: db)
                                                : SettingsScreen(
                                                    db: db,
                                                    dbPath: dbPath,
                                                    onRestored: onRestored,
                                                  );
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => target),
                        );
                      }
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
