import 'package:flutter/material.dart';

import 'package:heseb_storage/heseb_storage.dart';

/// الشاشة الهيكلية (F-016): قائمة وحدات معطلة — إطار التنقل
/// دون أي وظيفة محاسبية. الوحدات ومراحل توفرها من جدول النطاق (01 §5) حرفاً.
class HomeScreen extends StatelessWidget {
  final HesebDatabase db;

  const HomeScreen({super.key, required this.db});

  /// (اسم الوحدة، مرحلة التوفر في 01) — إظهار الواقع لا وعود مبكرة.
  static const List<(String, String)> _modules = [
    ('الأطراف', 'الإصدار 1'),
    ('الأصناف', 'الإصدار 1 — البضاعة والخدمات'),
    ('وحدات القياس والتعبئة', 'الإصدار 2'),
    ('المستودعات', 'الإصدار 1 (واحد) → 2 (متعدد + جرد)'),
    ('الفواتير', 'الإصدار 1'),
    ('طلبات الشراء والبيع', 'لاحقاً — تُقيَّم بعد MVP (D-026)'),
    ('الذمم', 'الإصدار 1'),
    ('الصناديق', 'الإصدار 1'),
    ('الدفتر المحاسبي', 'الإصدار 1 — الأساس'),
    ('العملات', 'الإصدار 1 (واحدة) → 3 (متعددة + فروق)'),
    ('الصلاحيات', 'الإصدار 1'),
    ('التقارير اليومية', 'الإصدار 1'),
    ('المزامنة', 'الإصدار 4'),
    ('الإعدادات', 'نسخة الاحتياطي الأولى (F-012) بعد التهيئة — س-01'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حسيب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'الإعدادات — لاحقاً في م0',
            onPressed: null, // معطلة — F-016: بلا وظائف محاسبية
          ),
        ],
      ),
      // قائمة ثابتة تُبنى كاملة — لا lazy builder (ثبات التحقق في الاختبار)
      body: ListView(
        children: [
          for (final (title, stage) in _modules)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(title),
              subtitle: Text('معطلة — متاح في $stage'),
              enabled: false, // F-016: القائمة كلها معطلة في م0
              onTap: null,
            ),
        ],
      ),
    );
  }
}
