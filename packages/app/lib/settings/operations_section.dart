/// قسم العمليات بالإعدادات (س233 — D-230، المرحلة أ/1 من خارطة الطريق
/// الخماسية): الترقيم (D-169 — س56) والعملات (الدفعة 34) وقوالب الطباعة
/// (س119) والعمل الجماعي (د6) واستيراد البيانات (س140) والتشخيص (س107)
/// — المتن بنصوص دفعاته حرفاً والتشخيص أخيرة القائمة بعرف درس
/// D-098/س107 باقياً.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import '../currencies_screen.dart';
import '../diagnostics_screen.dart';
import '../import_screen.dart';
import '../l10n/app_strings.dart';
import 'explanation_disclosure.dart';
import '../print_copies.dart' show PrintTemplatesCard;
import '../sync_work_screen.dart' show SyncWorkCard;

/// قسم العمليات — أفعال المنشأة الجارية، والتشخيص آخرها.
class OperationsSection extends StatefulWidget {
  final DiqqahDatabase db;

  /// س140 (D-208/§25.3): استيراد البيانات للمدير حصراً في v1 —
  /// الاستيراد الكبير بالحرس المديري عرف §8-5.
  final bool isManager;

  const OperationsSection({
    super.key,
    required this.db,
    required this.isManager,
  });

  @override
  State<OperationsSection> createState() => _OperationsSectionState();
}

class _OperationsSectionState extends State<OperationsSection> {
  bool _busy = false;

  /// ── بطاقة الترقيم (D-169 — س56): عرض عدّاد الترقيم بعد السنة —
  /// يُقرأ النافذ عند الفتح ويُحفظ مدققاً 3..8 في app_meta، ومعاينة
  /// حية قبل الحفظ، والأرقام الصادرة لا تُمسّ بالتغيير أبداً.
  final _counterWidthController = TextEditingController();
  int _counterWidth = kDefaultCounterWidth;

  @override
  void initState() {
    super.initState();
    _loadCounterWidth();
  }

  @override
  void dispose() {
    _counterWidthController.dispose();
    super.dispose();
  }

  /// قراءة العرض النافذ (D-169) عند الفتح وبعد كل استعادة.
  Future<void> _loadCounterWidth() async {
    final width = await widget.db.counterWidth();
    if (!mounted) return;
    setState(() {
      _counterWidth = width;
      _counterWidthController.text = '$width';
    });
  }

  /// المعاينة الحية — المدخل يعرض إن كان ضمن النطاق وإلا القيمة المحفوظة،
  /// والمثال رقم 1 من سنة اليوم دائماً (formatDocumentNumber نفسها التي
  /// يولّد بها المحرك فلا معاينة تخالف الواقع).
  String _counterWidthPreview() {
    final parsed = int.tryParse(_counterWidthController.text.trim());
    final width = (parsed != null && isValidCounterWidth(parsed))
        ? parsed
        : _counterWidth;
    return formatDocumentNumber(DateTime.now().year, 1, counterWidth: width);
  }

  /// حفظ العرض بعد تدقيقه — خارج 3..8 رفض برسالة عربية بلا كتابة
  /// (وحرس setCounterWidth ثانٍ في التخزين).
  Future<void> _saveCounterWidth() async {
    final parsed = int.tryParse(_counterWidthController.text.trim());
    if (parsed == null || !isValidCounterWidth(parsed)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.counterDigitsRange(kCounterWidthMin, kCounterWidthMax)),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.db.setCounterWidth(parsed);
      if (!mounted) return;
      setState(() => _counterWidth = parsed);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(S.counterDigitsSaved),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// استيراد البيانات (D-208/§25.3 — س140): بطاقة البند وبابها
  /// الوحيد لشاشة الاستيراد — الأطراف والأصناف في دفعة النواة.
  Widget _importDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.dataImportTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            // س198 (م17 من تقرير فحص الواجهات وفق M3): سطر تلخيص
            // ظاهر والشرح الكثيف خلف توسعة «كيف يعمل؟» — فتبقى
            // الحقيقة كاملة والمساحة هادئة فوق الفعل.
            ExplanationDisclosure(
              summary: S.dataImportBody,
              details: S.dataImportMigrationBody,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImportScreen(db: widget.db),
                  ),
                );
              },
              icon: const Icon(Icons.import_export),
              label: const Text(S.openImportScreen),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── بطاقة الترقيم (D-169 — س56): سنة برقمين فالعدّاد بلا فاصل،
        // وعرض العدّاد بعد السنة خانة إعداد المالك (3..8) بمعاينة حية —
        // والأرقام الصادرة لا تُمس فالتغيير للوثائق الجديدة حصراً.
        // س213 (D-218): انتقلت إلى قسم العمليات — المتن حرفاً.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.numberingTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.numberingBody,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _counterWidthController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(1),
                  ],
                  decoration: const InputDecoration(
                    labelText: S.counterDigitsLabel,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 4),
                Text(S.numberingPreview(_counterWidthPreview())),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _busy ? null : _saveCounterWidth,
                  child: const Text(S.saveCounterDigits),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // الدفعة 34 (F-120/F-121، D-194): إدارة العملات وأسعار
        // الصرف — بند ظاهر لا مدفون (درس D-098)، والتعطيل بلا
        // حذف والأسعار المحفوظة لا تعدل أبداً.
        Card(
          child: ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text(S.currenciesTitle),
            subtitle: const Text(
                S.currenciesBody),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => CurrenciesScreen(db: widget.db)),
              );
            },
          ),
        ),
        // ── س119: بطاقة قوالب طباعة الفواتير — بعد بطاقة التشخيص
        // في نهاية القائمة (الوجه الثاني للدرس: الجديد نهاية القائمة
        // فلا تُزيح بنداً ولا ميزانية سحب). فيها مفتاح إلغاء نسخة
        // أمين المستودع وقالب كل نوع بالقياس والاتجاه والأعلام.
        const PrintTemplatesCard(),
        // ── د6 (س175): بطاقة العمل الجماعي والمزامنة — نهاية القائمة
        // (درس D-098/س107: الجديد بنهاية القائمة فلا تُزيح بنداً ولا
        // ميزانية سحب): النافذة الواجهية للانضمام والأرشفة والإبطال
        // المُحالة من د5 بحدّها الصادق الموثق.
        SyncWorkCard(db: widget.db),
        const SizedBox(height: 16),
        // استيراد البيانات (D-208/§25.3 — س140): بند الإعدادات بمسار
        // «استيراد البيانات» — للمدير حصراً في v1: استيراد الانتقال
        // عملية كبرى بمعاملة واحدة تسبقها نسخة حدثية، والاستيراد
        // الكبير بالحرس المديري عرف §8-5. س213 (D-218): قسم العمليات.
        if (widget.isManager) _importDataCard(),
        const SizedBox(height: 16),
        // ── س107: بطاقة التشخيص ومرجع الأخطاء — نهاية القائمة عمداً
        // فلا تُزيح بندَ دفعات سابقة (درس ميزانية السحب D-098/س102).
        // قراءة لا إجراء: هوية النافذة وذيل سجل الأخطاء والمرجع الحي.
        // س213 (D-218): بآخر العمليات وأخيرة القائمة — الموضع الأخير
        // بعرف الدرس باقٍ لا يتزحزح.
        Card(
          child: ListTile(
            key: const ValueKey('settings_diagnostics'),
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text(S.diagnosticsTitle),
            subtitle: const Text(
                S.diagnosticsBody),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DiagnosticsScreen(db: widget.db),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
