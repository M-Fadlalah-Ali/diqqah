/// كشف تدريجي للشرح الكثيف (س198 — م17 من تقرير فحص الواجهات وفق M3،
/// نقلته دفعة س233 من settings_screen إلى ملفه بسؤال القسمين: النسخ
/// والاستعادة، والعمليات): سطر تلخيص ظاهر دائماً فوق فعل التوسعة
/// «كيف يعمل؟»، والتفصيل الكامل خلفه حرفاً فلا حقيقة ضاعت ولا فقرة
/// ثابتة تُطيل البطاقة فوق أفعالها.
library;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// كشف تدريجي — سطر التلخيص والتفصيل خلف توسعة «كيف يعمل؟».
class ExplanationDisclosure extends StatefulWidget {
  final String summary;
  final String details;

  const ExplanationDisclosure({
    super.key,
    required this.summary,
    required this.details,
  });

  @override
  State<ExplanationDisclosure> createState() => _ExplanationDisclosureState();
}

class _ExplanationDisclosureState extends State<ExplanationDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.summary),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
            label: Text(_open ? S.hideExplanation : S.howItWorks),
          ),
        ),
        if (_open)
          Text(widget.details,
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
