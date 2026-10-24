import 'package:flutter/material.dart';

import 'package:heseb_storage/heseb_storage.dart';

import 'first_run_screen.dart';
import 'home_screen.dart';

void main() => runApp(const HesebApp());

/// إطار الحسيب — واجهة واحدة تعمل على أندرويد وWindows (F-001).
class HesebApp extends StatelessWidget {
  final HesebDatabase? db;

  /// عدد تكرارات PBKDF2 — حقن للاختبارات، الافتراضي الإنتاجي.
  final int hasherIterations;

  const HesebApp({super.key, this.db, this.hasherIterations = 50000});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حسيب',
      theme: ThemeData(useMaterial3: true),
      home: AppGate(
        db: db,
        hasherIterations: hasherIterations,
      ),
    );
  }
}

/// بوابة أول التشغيل (F-014، س-01): لا شاشة قبل إنشاء المدير —
/// بلا مستخدمين تُفتح شاشة التهيئة، وبمدير موجود تُفتح الهيكلية (F-016).
class AppGate extends StatefulWidget {
  final HesebDatabase? db;
  final int hasherIterations;

  const AppGate({super.key, this.db, this.hasherIterations = 50000});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  HesebDatabase? _db;
  bool? _hasAnyUser;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final db = widget.db ?? _db ?? HesebDatabase();
    final hasAnyUser = await db.hasAnyUser();
    if (!mounted) return;
    setState(() {
      _db = db;
      _hasAnyUser = hasAnyUser;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyUser = _hasAnyUser;
    if (hasAnyUser == null) {
      // افتتاح < 3 ثوانٍ (F-016): بلا أي عمل محاسبي على هذا المسار.
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final db = _db!;
    if (!hasAnyUser) {
      return FirstRunScreen(
        db: db,
        hasherIterations: widget.hasherIterations,
        onSetupDone: () => setState(() => _hasAnyUser = true),
      );
    }
    return HomeScreen(db: db);
  }
}
