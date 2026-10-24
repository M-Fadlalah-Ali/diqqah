import 'package:flutter/material.dart';

void main() => runApp(const HesebApp());

/// إطار الحسيب — واجهة واحدة تعمل على أندرويد وWindows (F-001).
///
/// جلسة م0 الأولى: الهيكل الثلاثي فقط (F-010).
/// لا وحدات محاسبية بعد — الشاشة الهيكلية بقائمة الوحدات تُبنى في F-016.
class HesebApp extends StatelessWidget {
  const HesebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حسيب',
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(
        body: Center(
          child: Text('حسيب — الهيكل قيد البناء (م0)'),
        ),
      ),
    );
  }
}
