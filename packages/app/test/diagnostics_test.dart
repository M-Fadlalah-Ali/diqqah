import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_app/diagnostics_screen.dart';
import 'package:diqqah_app/settings_screen.dart';

import 'test_guard.dart';

/// ═══ س107 (أساس الأخطاء — قرار المالك الخامس): شاشة التشخيص ═══
///
/// (1) بطاقة الإعدادات تفتح الشاشة (D-098: البند بلسان الوصول — وبنهاية
///     القائمة عمداً فلا تُزيح بندَ دفعات سابقة ولا ميزانية سحب اختبار).
/// (2) الشاشة تعرض هوية النافذة (الإصدار/المخطط/الجهاز) وذيل السجل
///     والمرجع الحي — قراءة لا إجراء. (3) التسجيل من التدفق يظهر بالشاشة
///     برمزه وسياقه. (4) سجل فارغ بلسان «لا سجلات» لا فراغاً أعمى.
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق).
void main() {
  installTestTimeoutGuard();
  EditableText.debugDeterministicCursor = true;

  /// تمرير حتى نصٍ أسفل قائمة الإعدادات الطويلة (الدرس الموثق س35/س36).
  Future<void> scrollToText(WidgetTester tester, String label) async {
    for (var i = 0; i < 40 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
    }
  }

  Future<DiqqahDatabase> freshDb() async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.deviceId();
    return db;
  }

  testWidgets('بطاقة الإعدادات بنهاية القائمة تفتح شاشة التشخيص',
      (tester) async {
    final db = await freshDb();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        db: db,
        dbPath: '/tmp/diqqah_diagnostics/dummy.db',
        onRestored: () {},
      ),
    ));
    await tester.pump();

    await scrollToText(tester, 'التشخيص ومرجع الأخطاء');
    expect(find.text('التشخيص ومرجع الأخطاء'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_diagnostics')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('diagnostics_screen')), findsOneWidget);
    expect(find.text('النظام'), findsOneWidget);
    expect(find.text('آخر الأخطاء'), findsOneWidget);
    // المخطط من الثابت الديناميكي الوحيد بعرف س165/س175 (فلا توقيع
    // إصدار بالحرف بعد اليوم — v35 س215 والفهارس الحارة قبلها v34
    // س211 وv33 س181 وv32 س175).
    expect(find.text('إصدار المخطط: ${DiqqahDatabase.schemaVersionValue}'),
        findsOneWidget);
    // سطر حالة الإحكام p3 حي من القاعدة — ثلاث استعلامات متتالية
    // فبضع دفعات محدودة لا pumpAndSettle (درس س22..س26 الموثق)،
    // والانتظار للحالة المحسومة لا للعنصر النائب «…».
    bool resolved() =>
        find.textContaining('مفعّل').evaluate().isNotEmpty ||
        find.textContaining('غير مفعّل').evaluate().isNotEmpty;
    for (var i = 0; i < 10 && !resolved(); i++) {
      await tester.pump();
    }
    expect(find.textContaining('تشفير السجلات (p3): مفعّل'), findsOneWidget);
    // والسجل فارغ بلسانه الموثق لا فراغاً.
    expect(find.textContaining('لا سجلات'), findsOneWidget);
  });

  testWidgets('الشاشة تعرض السجل المرقّم وسياقه بعد تسجيل من التدفق',
      (tester) async {
    final db = await freshDb();
    await db.logError(
        code: 'DQ-0208',
        message: 'الفاتورة المرحّلة لا تحذف — التصحيح بمردود',
        context: 'invoices.post');
    await tester.pumpWidget(MaterialApp(home: DiagnosticsScreen(db: db)));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('diagnostics_errors')), findsOneWidget);
    expect(find.textContaining('[DQ-0208]'), findsOneWidget);
    expect(find.textContaining('السياق: invoices.post'), findsOneWidget);
  });

  testWidgets('مرجع الرموز بالشاشة يقرأ سجل المجال حرفاً', (tester) async {
    final db = await freshDb();
    await tester.pumpWidget(MaterialApp(home: DiagnosticsScreen(db: db)));
    await tester.pump();

    // أول السجل وفاصلته الآمنة حاضران باللسان الموثق — تمرير متدرج
    // (السحب الواحد لا يقطع القائمة كلها — درس ListView الكسول).
    for (var i = 0;
        i < 60 && find.textContaining('DQ-0101').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump();
    }
    expect(find.textContaining('DQ-0101'), findsOneWidget);
    for (var i = 0;
        i < 60 && find.textContaining('DQ-0999').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pump();
    }
    expect(find.textContaining('DQ-0999'), findsWidgets);
  });
}
