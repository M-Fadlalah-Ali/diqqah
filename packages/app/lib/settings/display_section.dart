/// قسم العرض والمظهر بالإعدادات (س233 — D-230، المرحلة أ/1 من خارطة
/// الطريق الخماسية): بطاقة خيارات العرض القائمة (الهجري F-167/D-183)
/// يلحق بها خيارا التقويم الجديدان (D-231 — أسماء الأشهر شامية/دولية
/// وأول الأسبوع سبت/أحد/اثنين بجوار الهجري)، فبطاقة صور المطبوعات
/// والخط (D-104/D-212) والمظهر (س182) — المتن القائم حرفاً والجديد
/// بإسناد الخطة.
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart' show todayIsoDate;

import '../app_theme.dart';
import '../calendar_prefs.dart';
import '../hijri_display.dart';
import '../l10n/app_strings.dart';
import '../print_image_prefs.dart';
import '../ui_fonts.dart';

/// قسم العرض والمظهر — عرض لا سياسات (D-218): الهجري والتقويم والصور
/// والخط والمظهر (مُنظَّم: بطاقة الصور تعيد بناءها بمفاتيحها الحية).
class DisplaySection extends StatefulWidget {
  const DisplaySection({super.key});

  @override
  State<DisplaySection> createState() => _DisplaySectionState();
}

class _DisplaySectionState extends State<DisplaySection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── بطاقة خيارات العرض (F-167/D-183 — الدفعة 23): مفتاح
        // الهجري بجانب الميلادي — عرض لا إدخال، والميلادي أساس
        // التخزين والإدخال دائماً (D-077/F-175: لا إدخال هجري أبداً).
        // س233 (D-231): ويلحق به خيارا التقويم الجديدان — أسماء الأشهر
        // (شامية/دولية) وأول الأسبوع (السبت/الأحد/الاثنين) — تطبيقهما
        // فوري على منتقي التاريخ كله (وفد الجذر) وعلى تاريخ المطبوعات.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.displayOptionsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.hijriBesideGregorianBody,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(S.hijriBesideGregorian),
                  subtitle: Text(
                      S.previewOf(displayDate(todayIsoDate()))),
                  value: hijriDisplayEnabled.value,
                  onChanged: (v) async {
                    await setHijriDisplayEnabled(v);
                  },
                ),
                const SizedBox(height: 8),
                // ── س233 (D-231): أسماء الأشهر — شامية أو دولية.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.monthNamesLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    ValueListenableBuilder<DiqqahMonthNames>(
                      valueListenable: calendarMonthNames,
                      builder: (context, choice, _) => Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            key: const ValueKey(
                                'settings_month_names_shami'),
                            label: const Text(S.monthNamesShami),
                            selected:
                                choice == DiqqahMonthNames.shami,
                            onSelected: (_) =>
                                setCalendarMonthNames(DiqqahMonthNames.shami),
                          ),
                          ChoiceChip(
                            key: const ValueKey(
                                'settings_month_names_international'),
                            label: const Text(S.monthNamesInternational),
                            selected: choice ==
                                DiqqahMonthNames.international,
                            onSelected: (_) =>
                                setCalendarMonthNames(
                                    DiqqahMonthNames.international),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ── س233 (D-231): أول الأسبوع — سبت أو أحد أو اثنين.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.weekStartLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    ValueListenableBuilder<DiqqahWeekStart>(
                      valueListenable: calendarWeekStart,
                      builder: (context, choice, _) => Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            key: const ValueKey(
                                'settings_week_start_saturday'),
                            label: const Text(S.weekStartSaturday),
                            selected:
                                choice == DiqqahWeekStart.saturday,
                            onSelected: (_) =>
                                setCalendarWeekStart(
                                    DiqqahWeekStart.saturday),
                          ),
                          ChoiceChip(
                            key: const ValueKey(
                                'settings_week_start_sunday'),
                            label: const Text(S.weekStartSunday),
                            selected: choice == DiqqahWeekStart.sunday,
                            onSelected: (_) => setCalendarWeekStart(
                                DiqqahWeekStart.sunday),
                          ),
                          ChoiceChip(
                            key: const ValueKey(
                                'settings_week_start_monday'),
                            label: const Text(S.weekStartMonday),
                            selected: choice == DiqqahWeekStart.monday,
                            onSelected: (_) => setCalendarWeekStart(
                                DiqqahWeekStart.monday),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── صور الأصناف في المطبوعات (س-127/س-128، D-123) ──
        // بلفظ المالك: «يمكن إلغاؤه افتراضياً ويحتاج تفعيله الدخول إلى
        // الإعدادات ثم اختيار أين نريد تفعيلها افتراضياً» — الافتراضي
        // معطل في كل المستندات، ومفاتيح التقارير مستقلة عن الفواتير.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.itemImagesInPrints,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.itemImagesInPrintsBody,
                ),
                const SizedBox(height: 8),
                for (final (key, label) in kPrintImageChoices)
                  SwitchListTile(
                    value: printImageValueOf(key),
                    onChanged: (v) =>
                        setState(() => savePrintImagePref(key, v)),
                    title: Text(label),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // خط التطبيق والطباعة (D-104 دفعة 8 س39 — مُحدّث بD-212 س158) —
        // خيار واحد يغيّر العرض والطباعة معاً بلفظ المالك، والمكتبة
        // مدمجة حصراً بأربع عائلات: ساحل وIBM Plex Sans Arabic
        // وNoto Sans Arabic وVazirmatn — لا خطوط جهاز ولا تحميل
        // خارجي، وتجوال خرج بD-212 وترحّل محفوظه إلى ساحل، والاثنان
        // الراكنان (Rubik وReadex Pro) بقائمة الانتظار 09 §8.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.appFontTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.appFontBody,
                ),
                const SizedBox(height: 4),
                // منتقي الشرائح الأربع (D-212) — شفرات اختيار بقائمة
                // طولية فلا تفيض الشاشة الضيقة بأربعة أسماء كاملة،
                // والمعيّن بعلامة الاختيار حي من المُنبّه ذاته.
                Column(
                  children: [
                    for (final (key, label) in kFontChoices)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label),
                        trailing: Icon(
                          appFontChoice.value == key
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () {
                          appFontChoice.value = key;
                          saveFontChoice(key);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // س182 (م05 — بأمر المالك «انشئ نظام ألوان نهاري/ليلي/نظام»):
        // بطاقة المظهر — ثلاثة أوضاع (نظام/نهاري/ليلي) بأثر فوري بلا
        // إقلاع (المُنبّه يعيد بناء الجذر)، والافتراضي «نظام» يتبع
        // الجهاز. الخيار محفوظ بنمط الخطوط (D-104) والمحل كما هو.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.themeTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.themeBody,
                ),
                const SizedBox(height: 4),
                // منتقي الأوضاع الثلاثة (س182) — بنمط منتقي الخطوط:
                // قائمة طولية والمعيّن بعلامة الاختيار حي من المُنبّه.
                Column(
                  children: [
                    for (final (key, label, icon) in kThemeModeChoices)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(icon),
                        title: Text(label),
                        trailing: Icon(
                          appThemeMode.value == key
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () {
                          appThemeMode.value = key;
                          saveThemeMode(key);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
