import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'first_run_screen.dart';
import 'home_screen.dart';
import 'item_images.dart';
import 'print_image_prefs.dart';
import 'ui_fonts.dart';

/// D-104 (دفعة 8 س39): تسجيل عائلتي الخط (ساحل/تجوال) وقراءة الخيار
/// المحفوظ قبل الإقلاع — والخطوط مدمجة حصراً (لا خطوط جهاز) بلفظ
/// المالك، وفشل كل خطوة محاط — إقلاع التطبيق أقدس من خط.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadFontChoice();
  await loadPrintImagePrefs();
  await preloadAppFonts();
  runApp(const DiqqahApp());
}

/// إطار دِقَّة — واجهة واحدة تعمل على أندرويد وWindows (F-001).
class DiqqahApp extends StatelessWidget {
  final DiqqahDatabase? db;

  /// تجاوز مسار القاعدة (اختبارات) — الإنتاج يشتقه من مجلد الدعم.
  final String? dbPath;

  /// عدد تكرارات PBKDF2 — حقن للاختبارات، الافتراضي الإنتاجي.
  final int hasherIterations;

  const DiqqahApp({super.key, this.db, this.dbPath, this.hasherIterations = 50000});

  @override
  Widget build(BuildContext context) {
    // D-104: خيار واحد يغيّر العرض والطباعة معاً (جواب المالك «واحد»)
    // — ValueListenableBuilder يعيد بناء الجذر فور تغيير الخيار من
    // الإعدادات فتتغير الشاشات والمطبوعات لحظياً دون إقلاع جديد.
    return ValueListenableBuilder<String>(
      valueListenable: appFontChoice,
      builder: (context, fontKey, _) => MaterialApp(
        title: 'دِقَّة',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: appFontFamily(fontKey),
        ),
        home: AppGate(
          db: db,
          dbPath: dbPath,
          hasherIterations: hasherIterations,
        ),
      ),
    );
  }
}

/// بوابة أول التشغيل (F-014، س-01): لا شاشة قبل إنشاء المدير —
/// بلا مستخدمين تُفتح شاشة التهيئة، وبمدير موجود تُفتح الهيكلية (F-016).
class AppGate extends StatefulWidget {
  final DiqqahDatabase? db;
  final String? dbPath;
  final int hasherIterations;

  const AppGate({
    super.key,
    this.db,
    this.dbPath,
    this.hasherIterations = 50000,
  });

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  DiqqahDatabase? _db;
  String? _dbPath;
  bool? _hasAnyUser;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final DiqqahDatabase db;
    final String dbPath;
    final injected = widget.db;
    if (injected != null) {
      // حقن الاختبارات — لا قنوات منصة هنا أبداً.
      db = injected;
      dbPath = widget.dbPath ?? 'diqqah.db';
    } else {
      // مسار الإنتاج (قرار موثق — جلسة م0 الثالثة): ملف القاعدة الوحيد
      // F-012 في مجلد الدعم الخاص بالتطبيق على المنصتين. وتبنّي ملف
      // الجيل السابق «heseb.db» عند أول فتح بعد التسمية (D-053).
      final dir = await getApplicationSupportDirectory();
      dbPath = p.join(dir.path, 'diqqah.db');
      await adoptLegacyHesebDatabase(dbPath);
      db = DiqqahDatabase(filePath: dbPath);
    }
    final hasAnyUser = await db.hasAnyUser();
    if (!mounted) return;
    // دفعة (10): جذر مجلد الصور بجوار القاعدة — المواضع كلها تقرأ منه
    // (D-125)، والاختبارات تضبطه يدوياً على مجلد مؤقت.
    ItemImagesStore.root = imagesDirFor(dbPath);
    setState(() {
      _db = db;
      _dbPath = dbPath;
      _hasAnyUser = hasAnyUser;
    });
  }

  /// بعد استعادة ناجحة (F-013): القاعدة القديمة مغلقة والملف استُبدل —
  /// تعيد البوابة فتح قاعدة جديدة من الملف نفسه (الإنتاج).
  void _onRestored() {
    if (widget.db != null) {
      // قاعدة محقونة (اختبارات) — إعادة البناء بيد صاحب الاختبار.
      return;
    }
    setState(() {
      _db = null;
      _dbPath = null;
      _hasAnyUser = null;
    });
    _resolve();
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
    final dbPath = _dbPath ?? widget.dbPath ?? 'diqqah.db';
    if (!hasAnyUser) {
      return FirstRunScreen(
        db: db,
        hasherIterations: widget.hasherIterations,
        onSetupDone: () => setState(() => _hasAnyUser = true),
      );
    }
    return HomeScreen(
      db: db,
      dbPath: dbPath,
      onRestored: _onRestored,
    );
  }
}
