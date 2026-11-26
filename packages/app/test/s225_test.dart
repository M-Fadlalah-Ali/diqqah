import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/empty_state.dart';
import 'package:diqqah_app/report_table.dart';

/// جذر المستودع: الاختبارات تعمل من packages/app في CI ومحلياً
/// بعرف الدورة (نمط s221/s218).
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${dir.path}/worklog.md').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('جذر المستودع غير موجود من ${Directory.current.path}');
}

/// س225 — الدفعة الأولى للحيوية بأمر المالك «قم بالتنفيذ الكامل /
/// ولا تنس التوثيق والدفع والبناء ل 0.277» بعد اعتماده الشفهي الموثق
/// بالنقاش («أنا موافق على الزيبرا المحايد» و«الدفعة الأولى — خ1 +
/// خ2 + خ7 + خ6» وبديل التحديد المتعدد عن لوح الفئة):
///
/// 1. خ1 نبض العمل بألوان الأزقة الدلالية المعتمدة لا الرمادي —
///    بعقد س186 حرفاً (الأخضر لا يُرى إلا دائناً فلا نبض أخضر أصلاً).
/// 2. خ2 هوية الوحدات بثلاث عائلات من مشتقات الستة (عقد س182) —
///    والأخضر والأحمر حصراً دلالة (س203) فلا يدخلان الهوية.
/// 3. خ7 طبقات الليل — سلالم الحاويات مشتقة من البذرة على الخلفية
///    المعتمدة لا ألوان خام، والخلفية والسطح والدلالية لا تُمسّ.
/// 4. خ6 الحالات الفارغة الحية بالقرص البني الهويّي — الفراغ ليس
///    دلالة.
/// 5. الزيبرا المحايد بجداول الشاشة وإجمالياتها بخط مزدوج المحاسبي
///    لا تلوين — والمطبوعات زِبرتها القائمة حرفاً.
/// 6. التحديد المتعدد الجماعي بديل لوح الفئة — اللمس الطويل أو Ctrl
///    للدخول وShift للتمديد والصبّ بترتيب الاختيار بعقد س-109/D-110.
void main() {
  test('س225: الحرس البنيوي للدفعة — النبض بالأزقة والوحدات بعائلاتها '
      'والليل بسلالمه والزيبرا المحايد والإجماليات المزدوجة', () {
    final home = File(
            '${_repoRoot().path}/packages/app/lib/home_screen.dart')
        .readAsStringSync();
    // خ1: النبض بألوان الأزقة لا الرمادي.
    expect(home.contains('lanes.attention'), isTrue,
        reason: 'بطاقة المتابعات والأصناف زوق الانتباه الأزرق');
    expect(home.contains('lanes.negative'), isTrue,
        reason: 'بطاقتا السقف والمدى الزوق السلبي الأحمر');
    expect(home.contains('DiqqahLane lane'), isTrue,
        reason: 'توقيع البطاقة بزوقها المعتمد');
    // خ2: عائلات الوحدات الثلاث.
    expect(home.contains('_moneyModuleKeys'), isTrue,
        reason: 'عائلة المال البنية');
    expect(home.contains('_neutralModuleKeys'), isTrue,
        reason: 'عائلة البنيوية المحايدة');
    expect(home.contains('{required bool enabled}'), isTrue,
        reason: 'المعطلة محايدة حرفاً فالقفل لا يدعو');
    // خ7: سلالم الليل مشتقة من البذرة على الخلفية المعتمدة.
    final theme = File(
            '${_repoRoot().path}/packages/app/lib/app_theme.dart')
        .readAsStringSync();
    expect(theme.contains('Color.lerp(kDarkBackground, kDarkIdentityBrown'),
        isTrue,
        reason: 'السلالم مزج البذرة على الخلفية لا ألوان خام');
    expect(theme.contains('surfaceContainerLowest'), isTrue,
        reason: 'السلالم الخمس معتمدة');
  });

  test('س225: الحرس البنيوي للزيبرا والإجماليات والتحديد المتعدد '
      'والحالات الفارغة', () {
    final root = _repoRoot().path;
    // الزيبرا المحايد والإجماليات المزدوجة بجدول الشاشة.
    final table = File('$root/packages/app/lib/report_table.dart')
        .readAsStringSync();
    expect(table.contains('withValues(alpha: 0.06)'), isTrue,
        reason: 'الزيبرا تون 6% مشتق لا خام');
    expect(table.contains('footerRows'), isTrue,
        reason: 'إجماليات الجدول بخط مزدوج المحاسبي');
    expect(table.contains('fontWeight: bold ? FontWeight.w700 : null'),
        isTrue, reason: 'سطر الإجماليات عريض');
    // التحديد المتعدد الجماعي بمسار البحث السريع.
    final invoices = File(
            '$root/packages/app/lib/invoices_screen.dart')
        .readAsStringSync();
    expect(invoices.contains('_quickSelectMode'), isTrue,
        reason: 'وضع التحديد داخل الاقتراحات لا شاشة جديدة');
    expect(invoices.contains('إضافة المحدد'), isTrue,
        reason: 'زر الصبّ الموثق');
    expect(invoices.contains('تحديد كل النتائج'), isTrue,
        reason: 'تحديد نتائج المرشّح كلها');
    expect(invoices.contains('isControlPressed'), isTrue,
        reason: 'الدخول بالنقر مع Ctrl على ويندوز');
    expect(invoices.contains('_toggleQuickSelect'), isTrue,
        reason: 'اللمس الطويل يدخل الوضع على أندرويد');
    expect(invoices.contains('qty.text = \'1\''), isTrue,
        reason: 'الصبّ بكمية الواحدة والتركيز على أول مضاف');
    // خ6: الحالات الفارغة الحية بالأسطر الست.
    final empty = File('$root/packages/app/lib/empty_state.dart')
        .readAsStringSync();
    expect(empty.contains('primaryContainer'), isTrue,
        reason: 'القرص من عائلة الهوية البنية — الفراغ ليس دلالة');
    for (final f in [
      'invoices_screen.dart',
      'vouchers_screen.dart',
      'orders_screen.dart',
      'ledger_screen.dart',
      'stock_docs_screen.dart',
    ]) {
      final src =
          File('$root/packages/app/lib/$f').readAsStringSync();
      expect(src.contains('DiqqahEmptyState'), isTrue,
          reason: '$f بلحتها الفارغة الحية');
    }
  });

  testWidgets('س225: حالة الفراغ الحية — القرص البني بأيقونته '
      'واللسان القائم حرفاً', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DiqqahEmptyState(
          icon: Icons.inbox_outlined,
          message: 'لا بيانات بعد',
        ),
      ),
    ));
    expect(find.text('لا بيانات بعد'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    final context = tester.element(find.text('لا بيانات بعد'));
    final cs = Theme.of(context).colorScheme;
    final disc = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere((c) =>
            (c.decoration as BoxDecoration?)?.shape == BoxShape.circle);
    expect((disc.decoration as BoxDecoration).color, cs.primaryContainer,
        reason: 'القرص من عائلة الهوية لا الدلالة');
  });

  testWidgets('س225: جدول الشاشة بزِبرته المحايدة وإجمالياته المزدوجة '
      '— اللسان عريض والصفوف تتناوب', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiqqahReportTable(
          columns: const ['الصنف', 'القيمة'],
          rows: const [
            ['زيت', '100'],
            ['سكر', '200'],
          ],
          numericColumns: const {1},
          footerRows: const [
            ['الإجمالي', '300'],
          ],
        ),
      ),
    ));
    expect(find.text('الإجمالي'), findsOneWidget,
        reason: 'سطر الإجماليات داخل الجدول');
    expect(find.text('300'), findsOneWidget);
    // الزيبرا: الأسطر الفردية بلون مشتق (الرأس الملون + صفان أحدهما
    // مضمّد = حاويتان بلون على الأقل).
    final colored = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) =>
            (c.decoration as BoxDecoration?)?.color != null)
        .length;
    expect(colored, greaterThanOrEqualTo(2),
        reason: 'الرأس والسطر الفردي المضمّد');
  });
}
