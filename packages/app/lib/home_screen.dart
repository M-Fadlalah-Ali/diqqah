import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'settings_screen.dart';
import 'parties_screen.dart';
import 'items_screen.dart';

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
  /// (F-030/F-031، س-36..س-41) — البقية في مفرغها.
  static const List<(String, String, bool)> _modules = [
    ('الأطراف', 'متاحة الآن — بطاقة الأطراف والبحث الجامع (F-020..F-023)', true),
    ('الأصناف', 'متاحة الآن — بطاقة الصنف والوحدات الأساسية (F-030/F-031)', true),
    ('وحدات القياس والتعبئة', 'الإصدار 2 — الإدخال في م1 بالوحدة الأساسية من شاشة الأصناف', false),
    ('المستودعات', 'الإصدار 1 (واحد) → 2 (متعدد + جرد)', false),
    ('الفواتير', 'الإصدار 1', false),
    ('طلبات الشراء والبيع', 'لاحقاً — تُقيَّم بعد MVP (D-026)', false),
    ('الذمم', 'الإصدار 1', false),
    ('الصناديق', 'الإصدار 1', false),
    ('الدفتر المحاسبي', 'الإصدار 1 — الأساس', false),
    ('العملات', 'الإصدار 1 (واحدة) → 3 (متعددة + فروق)', false),
    ('الصلاحيات', 'الإصدار 1', false),
    ('التقارير اليومية', 'الإصدار 1', false),
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
                              : Icons.settings_outlined,
                ),
                title: Text(title),
                subtitle: Text(enabled ? stage : 'معطلة — متاح في $stage'),
                enabled: enabled,
                onTap: enabled
                    ? () {
                        // الأطراف (دفعة م1 (1)) والأصناف (دفعة م1 (2))
                        // وحدات مفتوحة — والبقية الإعدادات وحدها حتى دفعاتها.
                        final Widget target = title == 'الأطراف'
                            ? PartiesScreen(db: db)
                            : title == 'الأصناف'
                                ? ItemsScreen(db: db)
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
