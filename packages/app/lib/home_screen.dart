import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'settings_screen.dart';

/// الشاشة الهيكلية (F-016): قائمة وحدات — إطار التنقل دون أي وظيفة
/// محاسبية. الوحدات ومراحل توفرها من جدول النطاق (01 §5) حرفاً،
/// والإعدادات متاحة فوراً بعد التهيئة (س-01: F-012/F-013).
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
  /// مبكرة، والإعدادات وحدها مفتوحة في م0 (س-01: بعد التهيئة فوراً).
  static const List<(String, String, bool)> _modules = [
    ('الأطراف', 'الإصدار 1', false),
    ('الأصناف', 'الإصدار 1 — البضاعة والخدمات', false),
    ('وحدات القياس والتعبئة', 'الإصدار 2', false),
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
                  enabled ? Icons.settings_outlined : Icons.lock_outline,
                ),
                title: Text(title),
                subtitle: Text(enabled ? stage : 'معطلة — متاح في $stage'),
                enabled: enabled,
                onTap: enabled
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SettingsScreen(
                              db: db,
                              dbPath: dbPath,
                              onRestored: onRestored,
                            ),
                          ),
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
