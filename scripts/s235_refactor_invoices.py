#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س235 — إعادة سجل الفواتير إلى شريط المدى الفوري الموحد (DiqqahInstantRangeBar):
حذف التنفيذ الخاص بس234 (الأزرار الخمسة + حراس الزوج) والاتكاء على
المصدر الواحد الجديد بdate_picker.dart — عقود س234 كلها باقية (السلوك
ذاته حرفاً) والاختبارات القائمة تختبر الودجت من فوق الشاشة."""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREEN = os.path.join(ROOT, "packages", "app", "lib", "invoices_screen.dart")


def main():
    s = io.open(SCREEN, encoding="utf-8").read()
    if "DiqqahInstantRangeBar(" in s:
        print("مُحوَّل مسبقاً — تُتخطى")
        return

    # ١) حذف الدالة المنقولة (أصبحت بdate_picker)
    m = re.search(r"\n/// س234 \(D-234 — المرحلة ب/2 من خارطة الطريق الخماسية\): السطر الفعلي"
                  r".*?\n}\n\n(?=class InvoicesScreen)", s, re.S)
    assert m, "دالة السطر الصغير غير موجودة"
    s = s[:m.start()] + "\n" + s[m.end():]

    # ٢) حقول الحالة: _preset و_suppressed يحذفان والمفتاح يضاف
    old = """  /// س234 (D-234 — المرحلة ب/2 من خارطة الطريق الخماسية): الاختصار
  /// المختار من أزرار التاريخ الخمسة — يتلون المختار، وتحرير الحقلين
  /// يدوياً يفرغه (فلا تلوين بلا مطابقة)، والتطبيق فوري (لا زر عرض).
  DiqqahRangePreset? _preset;

  /// س234 (المرحلة ب/3): التطبيق الفوري — زر «عرض» رُفع فالكتابة
  /// (البحث والمدى) تُطبَّق بتأخير قصير (نصف ثانية بلا ضغط آخر حرف)
  /// والاختيارات الجاهزة (الفلاتر والاختصارات) لحظية.
  Timer? _applyDebounce;

  /// س234: حرس الملء الآلي — تطبيق الاختصار يملا الحقلين برمجياً
  /// فيطلق مستمعيهما؛ فالحرس يمنع الاستطالة المزدوجة (ملءٌ فورّي
  /// وحسب، لا تطبيق بعده).
  bool _suppressFieldListener = false;"""
    new = """  /// س235: شريط المدى الفوري الموحد — المصدر الواحد لأزرار التاريخ
  /// الخمسة وحقلي من/إلى بحرسيه (التلوين والديبونس) — والمسح الشامل
  /// يفرّغه بمفتاحه (clear) فلا تكرار تحميل.
  final GlobalKey<DiqqahInstantRangeBarState> _rangeBarKey =
      GlobalKey<DiqqahInstantRangeBarState>();

  /// س234 (المرحلة ب/3): ديبونس البحث — زر «عرض» رُفع فالكتابة
  /// تُطبَّق بتأخير قصير (نصف ثانية بلا ضغط آخر حرف).
  Timer? _applyDebounce;"""
    assert old in s, "حقول الحالة القديمة غير موجودة"
    s = s.replace(old, new, 1)

    # ٣) المستمعون: المدى انتقل للودجت — البحث وحده يبقى
    old = """    // س234 (المرحلة ب/3): التطبيق الفوري — البحث والمدى يستمعان
    // للكتابة فيطبقانها بتأخير قصير (لا زر عرض بعد اليوم بسجل
    // الفواتير — عقد D-234 بلسان الخطة «التطبيق الفوري»).
    _search.addListener(_onSearchTyped);
    _from.addListener(_onRangeTyped);
    _to.addListener(_onRangeTyped);
  }"""
    new = """    // س234 (المرحلة ب/3): التطبيق الفوري — البحث يستمع للكتابة
    // فيطبقها بتأخير قصير (والمدى بشريطه الموحد س235).
    _search.addListener(_onSearchTyped);
  }"""
    assert old in s, "المستمعون القدامى غير موجودين"
    s = s.replace(old, new, 1)

    # ٤) حذف _onRangeTyped و_applyPreset كاملين (من تعليقهما إلى غلقهما)
    m = re.search(r"\n  /// س234: تحرير المدى يدوياً.*?\n  }\n\n  /// س234 \(المرحلة ب/2\): تطبيق اختصار التاريخ فوراً.*?\n  }\n", s, re.S)
    assert m, "تطبيقا المدى القديمان غير موجودين"
    s = s[:m.start()] + "\n" + s[m.end():]

    # ٥) المسح الشامل عبر الودجت
    old = """    _applyDebounce?.cancel();
    _suppressFieldListener = true;
    _from.clear();
    _to.clear();
    _search.clear();
    _suppressFieldListener = false;
    setState(() {"""
    new = """    _applyDebounce?.cancel();
    // س235: الشريط الموحد يفرّغ حقليه وتلوينه بلا تحميل (clear)
    // — والشاشة تفرغ ما عندها وتحمل مرة واحدة.
    _rangeBarKey.currentState?.clear();
    _search.clear();
    setState(() {"""
    assert old in s, "كتلة المسح القديمة غير موجودة"
    s = s.replace(old, new, 1)
    s = s.replace("""      _receipt = null;
      _state = null;
      _preset = null;
    });
    _reload();""",
                  """      _receipt = null;
      _state = null;
    });
    _reload();""", 1)

    # ٦) حذف ودجت الأزرار الخاصة (من تعليقها إلى غلق الصنف قبل build)
    m = re.search(r"\n  /// س234 \(D-234 — المرحلة ب/2\): أزرار التاريخ الخمعة بسطر واحد.*?\n  }\n\n(?=  @override\n  Widget build\(BuildContext context\) \{\n    return Scaffold\()", s, re.S)
    if not m:
        m = re.search(r"\n  /// س234 \(D-234 — المرحلة ب/2\): أزرار التاريخ الخمسة بسطر واحد.*?\n  }\n\n(?=  @override\n  Widget build)", s, re.S)
    assert m, "ودجت الأزرار الخاصة غير موجودة"
    s = s[:m.start()] + "\n" + s[m.end():]

    # ٧) البناء: البحث ثم الشريط الموحد (بدل الأزرار + حقلي من/إلى)
    old = """                const SizedBox(height: 8),
                // س234 (المرحلة ب/2): أزرار التاريخ الخمسة بسطر واحد —
                // السطر الصغير الفعلي أعلى الزر والمختار ملون.
                _presetButtons(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _from,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                            labelText: S.fromDateLabel,
                            suffixIcon:
                                calendarPickerSuffix(context, _from)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _to,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                            labelText: S.toDateLabel,
                            suffixIcon:
                                calendarPickerSuffix(context, _to)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),"""
    new = """                const SizedBox(height: 8),
                // س235: شريط المدى الفوري الموحد — أزرار التاريخ
                // الخمسة بسطورها الصغيرة وتلوين المختار وحقلا من/إلى
                // بديبونسهما وحرس زواجهما (المصدر الواحد بdate_picker).
                DiqqahInstantRangeBar(
                  key: _rangeBarKey,
                  from: _from,
                  to: _to,
                  onReload: _reload,
                ),
                const SizedBox(height: 8),"""
    assert old in s, "كتلة البناء القديمة غير موجودة"
    s = s.replace(old, new, 1)

    io.open(SCREEN, "w", encoding="utf-8").write(s)
    print("سجل الفواتير على الشريط الموحد")


if __name__ == "__main__":
    main()
