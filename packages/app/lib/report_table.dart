import 'package:flutter/material.dart';

/// م07 جداول التقارير (س205 — الدفعة الثالثة من فحص الواجهات وفق M3
/// بأمر المالك «تابع في م06 التكيفي ثم بقية الرابعة»): صفوف التقارير
/// كانت أسطر ListTile بنصوصها الملحومة («مدين X · دائن Y» بلحم
/// العنوان والرصيد) — والجدول الموحد يفصلها أعمدةً مرئية بترويسة
/// ظاهرة وأرقام بأطرافها منسجمة فتُقرأ العمود بعمود لا سطراً سطراً.
///
/// **وعرف F-166 باقٍ حرفاً**: ما يُرى على الشاشة هو صفوف الطباعة
/// والتصدير ذاتها — فخلايا الجدول سلاسل صفوف المستند الموثقة بكل
/// تقرير لا نصوصاً جديدة، وما يزاح عرضاً لا قراءةً. والنقر على الصف
/// بعرفه القائم (كل اسم يصير مدخلاً — س-146/س-147/D-135/س-144)
/// يُمرَّر كما هو فلا مدخل ضاع.
///
/// **والحد الصادق**: الترويسة والأعمدة عرضٌ فوق البيانات ذاتها — لا
/// حساب جديد ولا قراءة جديدة ولا لسان جديد، ودفتر اليومية وقائمة
/// الدخل والميزانية العمومية بخاريجهما القسمية الموثقة بحدود
/// الدفعة.
///
/// **س225 (الزيبرا المحايد بأمر المالك «أنا موافق على الزيبرا
/// المحايد»)**: الأسطر الفردية تُضمّد بتون محايد مشتق من أدوار
/// الثيم (ألفا 6% من onSurfaceVariant فوق سطح المخطط ذاته) — لا
/// أخضر ولا أحمر ولا أزرق أبداً فالتضميد تتبع بصري لا دلالة (عقد
/// س186/س203)، والمطبوعات زِبرتها القائمة حرفاً والشاشة حصراً موضع
/// هذه الدفعة، والأزواج الدلالية بالتلوين النصي باقية فوقها.
/// **وإجماليات الجدول** (footerRows — س225): سطر الإجماليات داخل
/// الجدول بخط مزدوج المحاسبي تحتَه لا بتلوين — عرف دفاتر الأستاذ.
class DiqqahReportTable extends StatelessWidget {
  /// أسماء الأعمدة بترويسة الجدول.
  final List<String> columns;

  /// صفوف الجدول — كل صف سلاسل خلاياه بترتيب الأعمدة نفسه.
  final List<List<String>> rows;

  /// فهارس الأعمدة الرقمية — خلاياها بأطرافها المنسجمة (الرقم عند
  /// طرف الخلية ذاته في كل الصفوف فتُقرأ العمود ميزاناً).
  final Set<int> numericColumns;

  /// النقر على الصف بعرفه القائم — فهرس الصف في [rows].
  final void Function(int index)? onRowTap;

  /// وزن عمود العنوان الأول — الأعرض من البقية لصلاحية الأسماء.
  final int firstColumnFlex;

  /// لون نص الصف بحالته الدلالية (عرف م05: أدوار الثيم لا ألوان خام)
  /// — لتقرير المطابقة الذي يلوّن صفه بحسب مطابقته، والغائب نص عادي.
  final List<Color?> rowTextColors;

  /// صفوف الإجماليات أسفل الجدول (س225) — كل صف خلاياه بترتيب الأعمدة
  /// نفسه، بخط عريض وخط مزدوج المحاسبي تحتَه لا تلوين، والغائب لا
  /// إجماليات (المطبوع بفقعه الزائف القائم كما هو حرفاً).
  final List<List<String>> footerRows;

  const DiqqahReportTable({
    super.key,
    required this.columns,
    required this.rows,
    this.numericColumns = const <int>{},
    this.onRowTap,
    this.firstColumnFlex = 3,
    this.rowTextColors = const <Color?>[],
    this.footerRows = const <List<String>>[],
  });

  Widget _cell(
    BuildContext context,
    String text,
    int columnIndex, {
    Color? rowColor,
    bool bold = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isNumeric = numericColumns.contains(columnIndex);
    return Expanded(
      flex: columnIndex == 0 ? firstColumnFlex : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          text,
          textAlign: isNumeric ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            color: rowColor ?? cs.onSurface,
            fontWeight: bold ? FontWeight.w700 : null,
          ),
        ),
      ),
    );
  }

  /// سطر الإجماليات (س225) — النص عريض والخط المزدوج المحاسبي تحته:
  /// القاعدة الأولى أسفل الصف من حدّه القائم والثانية سطر مستقل بعد
  /// فجوة — عرف دفاتر الأستاذ بلا تلوين ولا دلالة مستعارة.
  Widget _footerRow(BuildContext context, List<String> cells) {
    final cs = Theme.of(context).colorScheme;
    final rule = BorderSide(color: cs.outlineVariant, width: 1);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: rule)),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                _cell(context, i < cells.length ? cells[i] : '', i,
                    bold: true),
            ],
          ),
          const SizedBox(height: 2),
          Container(height: 1, color: cs.outlineVariant),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divider = BorderSide(color: cs.outlineVariant, width: 1);
    return Column(
      children: [
        // الترويسة — وعاء دور الثيم الثانوي فتتبدل بالوضعين لا لون خام.
        Container(
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            border: Border(bottom: divider),
          ),
          child: Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(
                  flex: i == 0 ? firstColumnFlex : 1,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(
                      columns[i],
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('لا صفوف',
                style: Theme.of(context).textTheme.bodySmall),
          )
        else ...[
          // س225 — الزيبرا المحايد: الأسطر الفردية بتون 6% من
          // onSurfaceVariant فوق سطح المخطط ذاته — مشتق لا خام، ولا
          // يعلم الدلالة النصية الملوّنة (rowTextColors) ولا المطبوع.
          for (var r = 0; r < rows.length; r++)
            InkWell(
              onTap: onRowTap == null ? null : () => onRowTap!(r),
              child: Container(
                decoration: BoxDecoration(
                  color: r.isOdd
                      ? cs.onSurfaceVariant.withValues(alpha: 0.06)
                      : null,
                  border: Border(bottom: divider),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      _cell(context,
                          i < rows[r].length ? rows[r][i] : '', i,
                          rowColor: r < rowTextColors.length
                              ? rowTextColors[r]
                              : null),
                  ],
                ),
              ),
            ),
          // س225 — سطر الإجماليات بخط مزدوج المحاسبي لا تلوين.
          for (final footer in footerRows) _footerRow(context, footer),
        ],
      ],
    );
  }
}
