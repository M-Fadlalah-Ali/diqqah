#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س235 — رقع توحيد النمط الفوري على شاشتي التقارير والسندات:
- دفر اليومية: النوع منسدلة مستقلة + شريط المدى الفوري (بدل من/إلى/النوع/عرض + رقائق).
- قائمة الدخل وحركة الصنف: الشريط الموحد بدل (الحقول + زر عرض + رقائق).
- الميزانية: حقل التاريخ الأحادي بتطبيق فوري (ديبونس) بلا زر عرض —
  ليس مدى فلا أزرار الخمسة (تفسير محدود موثق).
- السندات: تبويباتها الثلاثة على الشريط الموحد وحذف _RangeBar القديم.
- حذف DiqqahRangeShortcuts من date_picker (عقد الملء-بلا-تحميل عُفّي
  بالتطبيق الفوري — الشاشات الثلاث كلها على الموحد فلا مستهلك يبقى)."""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORTS = os.path.join(ROOT, "packages", "app", "lib", "reports_screen.dart")
VOUCHERS = os.path.join(ROOT, "packages", "app", "lib", "vouchers_screen.dart")
DATEPICKER = os.path.join(ROOT, "packages", "app", "lib", "date_picker.dart")


def sub(s, old, new, where):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    return s.replace(old, new, 1)


def main():
    # ══════════ 1) التقارير ══════════
    s = io.open(REPORTS, encoding="utf-8").read()
    if "DiqqahInstantRangeBar(" in s:
        print("التقارير: محوَّلة مسبقاً")
    else:
        # أ) دفر اليومية — الحقلان يرفعان والنوع يبقى وحده
        s = sub(s, """                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _from,
                            decoration: InputDecoration(
                                labelText: S.fromDateArabicHint,
                                suffixIcon:
                                    calendarPickerSuffix(context, _from)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _to,
                            decoration: InputDecoration(
                                labelText: S.toDateArabicHint,
                                suffixIcon:
                                    calendarPickerSuffix(context, _to)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(""",
                """                    // س235 (توحيد النمط بكلمة المالك): النوع منسدلة
                    // مستقلة — والمدى بشريطه الفوري الموحد أدناه.
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(""",
                "دفر اليومية: المقدمة")
        s = sub(s, """                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _reload,
                          child: const Text(S.viewButton),
                        ),
                      ],
                    ),
                    // س204 (م02 — اختصارات المدى): ملء سريع بلا إعادة
                    // تحميل — زر العرض القائم هو الفعّال بعرف D-077.
                    DiqqahRangeShortcuts(from: _from, to: _to),""",
                """                      ],
                    ),
                    const SizedBox(height: 8),
                    // س235: شريط المدى الفوري الموحد — الخمسة وحقلا
                    // من/إلى بلا زر عرض (التطبيق الفوري بديبونس قصير).
                    DiqqahInstantRangeBar(
                        from: _from, to: _to, onReload: _reload),""",
                "دفر اليومية: الذيل")

        # ب) قائمة الدخل — الصف والرقائق كلها بالشريط
        s = sub(s, """                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _from,
                      decoration: InputDecoration(
                          labelText: S.fromDateLabel,
                          suffixIcon: calendarPickerSuffix(context, _from)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _to,
                      decoration: InputDecoration(
                          labelText: S.toDateLabel,
                          suffixIcon: calendarPickerSuffix(context, _to)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _reload, child: const Text(S.viewButton)),
                ]),
                // س204 (م02 — اختصارات المدى): ملء سريع بلا إعادة
                // تحميل — زر العرض القائم هو الفعّال بعرف D-077.
                DiqqahRangeShortcuts(from: _from, to: _to),""",
                """                // س235: شريط المدى الفوري الموحد — الخمسة وحقلا
                // من/إلى بلا زر عرض (التطبيق الفوري بديبونس قصير).
                DiqqahInstantRangeBar(
                    from: _from, to: _to, onReload: _reload),""",
                "قائمة الدخل")

        # ج) الميزانية — التاريخ الأحادي فوري (لا مدى فلا خمسة)
        s = sub(s, """            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _asOf,
                  decoration: InputDecoration(
                      labelText: S.toDateWithFormat,
                      suffixIcon: calendarPickerSuffix(context, _asOf)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _reload, child: const Text(S.viewButton)),
            ]),""",
                """            child: Row(children: [
              // س235: التاريخ الأحادي بتطبيق فوري (ديبونس قصير) بلا
              // زر عرض — وليس مدى فلا أزرار الخمسة (تفسير محدود
              // موثق: التوحيد للفورية لا لفرض المدى على حقل واحد).
              Expanded(
                child: TextField(
                  controller: _asOf,
                  decoration: InputDecoration(
                      labelText: S.toDateWithFormat,
                      suffixIcon: calendarPickerSuffix(context, _asOf)),
                ),
              ),
            ]),""",
                "الميزانية: البناء")
        s = sub(s, """  @override
  void initState() {
    super.initState();
    _asOf = TextEditingController(text: todayIsoDate());
    _future =
        widget.db.balanceSheetReport(asOfText: _asOf.text);
  }

  @override
  void dispose() {
    _asOf.dispose();
    super.dispose();
  }""",
                """  /// س235: ديبونس التطبيق الفوري للتاريخ الأحادي.
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _asOf = TextEditingController(text: todayIsoDate());
    _future =
        widget.db.balanceSheetReport(asOfText: _asOf.text);
    _asOf.addListener(_onAsOfTyped);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _asOf.dispose();
    super.dispose();
  }

  /// س235: الكتابة تُطبَّق بتأخير قصير — والناقص أو الفاسد انتظار
  /// كتابة لا تطبيق ولا وميض أخطاء بكل حرف (عرف D-077 بثوب الفوري).
  void _onAsOfTyped() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final text = _asOf.text.trim();
      if (text.isEmpty || !isValidIsoDate(text)) return;
      _reload();
    });
  }""",
                "الميزانية: الحالة")

        # د) حركة الصنف — الحقول والرقائق والزر بالشريط
        s = sub(s, """                Row(
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
                // س204 (م02 — اختصارات المدى): ملء سريع بلا إعادة
                // تحميل — زر العرض القائم هو الفعّال بعرف D-077.
                DiqqahRangeShortcuts(from: _from, to: _to),
                const SizedBox(height: 8),
                FilledButton(onPressed: _run, child: const Text(S.viewButton)),""",
                """                // س235: شريط المدى الفوري الموحد — الخمسة وحقلا
                // من/إلى بلا زر عرض (التطبيق الفوري بديبونس قصير).
                DiqqahInstantRangeBar(
                    from: _from, to: _to, onReload: _run),""",
                "حركة الصنف")

        # Timer للتقارير (الميزانية) — استيراد dart:async إن غاب
        if "import 'dart:async'" not in s:
            m = re.search(r"^import ", s, re.M)
            s = s[:m.start()] + "import 'dart:async' show Timer;\n" + s[m.start():]
        io.open(REPORTS, "w", encoding="utf-8").write(s)
        print("التقارير: المواضع الأربعة على النمط الفوري")

    # ══════════ 2) السندات ══════════
    v = io.open(VOUCHERS, encoding="utf-8").read()
    if "DiqqahInstantRangeBar(" in v:
        print("السندات: محوَّلة مسبقاً")
    else:
        for _ in range(3):
            v = sub(v, "_RangeBar(from: _from, to: _to, onShow: _reload)",
                    """// س235 (توحيد النمط بكلمة المالك): شريط المدى الفوري الموحد
                    // بلا زر عرض — الخمعة وحقلا من/إلى بتطبيق فوري.
                    DiqqahInstantRangeBar(
                        from: _from, to: _to, onReload: _reload)""",
                    "استعمال شريط السندات")
        # حذف صنف _RangeBar كاملاً (من تعليقه إلى غلقه قبل _tabList)
        m = re.search(r"\n/// شريط المدى الموحد للتبويبات.*?\n}\n\n(?=/// بناء القائمة القرائية الموحد)",
                      v, re.S)
        assert m, "صنف _RangeBar غير موجود"
        v = v[:m.start()] + "\n" + v[m.end():]
        io.open(VOUCHERS, "w", encoding="utf-8").write(v)
        print("السندات: التبويبات الثلاثة على الموحد وصنف القديم حُذف")

    # ══════════ 3) حذف الرقائق المعفّاة ══════════
    d = io.open(DATEPICKER, encoding="utf-8").read()
    if "class DiqqahRangeShortcuts" in d:
        m = re.search(r"\n/// صف اختصارات المدى — رقائق تملأ حقلي من/إلى الممرَّرين\. .*?\n}\n\n"
                      r"(?=/// س234 \(D-234 — المرحلة ب/2\): السطر الفعلي الصغير)",
                      d, re.S)
        assert m, "صنف الرقائق غير موجود للحذف"
        d = d[:m.start()] + "\n" + d[m.end():]
        # تنظيف عقد الملء-بلا-تحميل من تعليق المعدود
        d = d.replace(
            "/// - **لا تفتح شيئاً ولا تُعيد تحميل**: تملأ الحقلين حصراً وعينَ\n"
            "///   زر «عرض» القائم هو الذي يُدقق ويُحمّل — عرف D-077 باقٍ حرفاً\n"
            "///   (حرس المدقق أول قبل لمس القاعدة) وعقد م02 س182 باقٍ: تحسين\n"
            "///   طبقة الإدخال دون لمس منطق المدقق والتصفية.\n",
            "/// - الملء بصيغة YYYY-MM-DD ذاتها التي يكتبها المنتقي (س182) فكل\n"
            "///   فحوص صيغة الحقول القائمة تعمل كما هي — (س235: عقد الرقائق\n"
            "///   «الملء بلا تحميل» عُفّي بالتطبيق الفوري بقرار المالك — الشاشات\n"
            "///   الثلاث على شريط DiqqahInstantRangeBar الموحد والدوال النقية\n"
            "///   باقية تخدمه).\n")
        io.open(DATEPICKER, "w", encoding="utf-8").write(d)
        print("date_picker: صنف الرقائق المعفّاة حُذف")
    else:
        print("date_picker: الرقائق محذوفة مسبقاً")


if __name__ == "__main__":
    main()
