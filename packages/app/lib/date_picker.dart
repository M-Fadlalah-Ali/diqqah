/// منتقي التاريخ الموحد (س182 — م02 من تقرير فحص الواجهات وفق M3،
/// بأمر المالك الحرفي «اعتمد منتقي التاريخ في الأماكن التي فيها إدخال
/// للتاريخ»).
///
/// العقد (بديل م02 الدلالي حرفاً):
/// - **منتقي المادة الثالثة مع الإبقاء على الكتابة اليدوية خياراً
///   ثانياً** — الحقل نصي كما كان (صيغة YYYY-MM-DD) وزر تقويم طرفي
///   يفتح showDatePicker واملأ الحقل بالتاريخ المختار.
/// - المنتقي بلسان الجهاز العربي تلقائياً — وراثة locale من الجذر
///   (س-135/D-129) بلا إعداد هنا.
/// - القيمة الحالية إن صلحت تفتح المنتقي عليها (initialDate) وإلا
///   فاليوم — فلا يبدأ المستخدم من سنة بعيدة بلا سبب.
/// - المدى المعقول 2000..2100 — أوسع من كل سنة مالية يعرفها البرنامج.
/// - بلا مساس بمنطق المدقق حرفاً: الحقل يُملأ كأن المستخدم كتب بنفسه
///   فكل فحوص الصيغة القائمة باقية كما هي (حد م02: تحسين طبقة
///   الإدخال دون لمس منطق المدقق).
library;

import 'dart:async' show Timer;

import 'package:flutter/material.dart';

import 'calendar_prefs.dart';
import 'l10n/app_strings.dart';

/// يفتح منتقي التاريخ ويكتب الاختيار بالمتحكم بصيغة YYYY-MM-DD —
/// والإلغاء لا يمس ما في الحقل شيئاً.
Future<void> pickDateIntoController(
    BuildContext context, TextEditingController controller) async {
  final initial = DateTime.tryParse(controller.text.trim());
  final picked = await showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
  );
  if (picked != null) {
    controller.text = picked.toIso8601String().substring(0, 10);
    // مؤشر الكتابة لآخر الحقل — فالامتداد اليدوي يكمل من نهايته.
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
  }
}

/// زر التقويم الطرفي لحقل التاريخ — أيقونة بتلميح واضح تفتح المنتقي.
Widget calendarPickerSuffix(
    BuildContext context, TextEditingController controller) {
  return IconButton(
    tooltip: 'اختيار التاريخ',
    icon: const Icon(Icons.edit_calendar_outlined),
    onPressed: () => pickDateIntoController(context, controller),
  );
}

/// اختصارات المدى (س204 — بقيةُ م02 من تقرير فحص الواجهات وفق M3
/// بعد منتقي التاريخ المنفذ س182 — بأمر المالك «ابدأ الدفعة الثانية
/// من m3»): رقائق مدى سريع بجانب أزواج حقلي «من/إلى».
///
/// العقد (بديل البند الدلالي حرفاً):
/// - أربعة اختصارات بلسان المستخدم: «اليوم» و«هذا الشهر» و«الشهر
///   الماضي» و«هذا العام» — تواريخها من اليوم المرجعي بدالة نقية
///   تُختبر بلا قاعدة ولا قنوات (نمط اختبار س182).
/// - الملء بصيغة YYYY-MM-DD ذاتها التي يكتبها المنتقي (س182) فكل
///   فحوص صيغة الحقول القائمة تعمل كما هي.
/// - الملء بصيغة YYYY-MM-DD ذاتها التي يكتبها المنتقي (س182) فكل
///   فحوص صيغة الحقول القائمة تعمل كما هي — (س235: عقد الرقائق
///   «الملء بلا تحميل» عُفّي بالتطبيق الفوري بقرار المالك — الشاشات
///   الثلاث على شريط DiqqahInstantRangeBar الموحد والدوال النقية
///   باقية تخدمه).
enum DiqqahRangePreset {
  today,
  thisMonth,
  lastMonth,
  thisYear,

  /// س234 (D-234 — المرحلة ب/2 من خارطة الطريق الخماسية): السنة
  /// السابقة كاملة — أولها إلى آخرها (سنة «كانون الأول» السابق).
  /// الاختصار الخامس لأزرار التاريخ الجديدة بسجل الفواتير حصراً —
  /// ورقائق DiqqahRangeShortcuts القائمة بشاشاتها الأربع كما هي
  /// (بند مسح الشاشات الأخرى: بلا تعديل بكلمة المالك).
  previousYear,
}

/// تواريخ الاختصار نقيةً — زوج (من، إلى) بصيغة ISO القصيرة، واليوم
/// المرجعي قابل للحقن للاختبار فلا زمن خفٍ في القراءة.
(String, String) diqqahRangeShortcutDates(
  DiqqahRangePreset preset, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  String day(DateTime x) =>
      DateTime(x.year, x.month, x.day).toIso8601String().substring(0, 10);
  switch (preset) {
    case DiqqahRangePreset.today:
      return (day(now), day(now));
    case DiqqahRangePreset.thisMonth:
      return (day(DateTime(now.year, now.month, 1)), day(now));
    case DiqqahRangePreset.lastMonth:
      // آخر يوم من الشهر الماضي = أول هذا الشهر ناقص يوماً — فلا
      // حساب أطوال شهور يدوي ولا كسر عند فبراير والسنين الكبيسة.
      final first = DateTime(now.year, now.month, 1);
      final lastOfPrev = first.subtract(const Duration(days: 1));
      return (
        day(DateTime(lastOfPrev.year, lastOfPrev.month, 1)),
        day(lastOfPrev),
      );
    case DiqqahRangePreset.thisYear:
      return (day(DateTime(now.year, 1, 1)), day(now));
    case DiqqahRangePreset.previousYear:
      // س234: السنة السابقة كاملة — أولها إلى آخرها (وآخرها كانون
      // الأول السابق بعينه، فالشهر السابق دائماً مفعّل بحده الصحيح
      // ولو كانت السنة الحالية جديدة).
      return (
        day(DateTime(now.year - 1, 1, 1)),
        day(DateTime(now.year - 1, 12, 31)),
      );
  }
}

/// س234 (D-234 — المرحلة ب/2): السطر الفعلي الصغير فوق زر اختصار التاريخ
/// — بلا سنة قرب الشهرين (اليوم بيومه واسم شهره، والشهران باسم شهرهما
/// حصراً بأسماء الأشهر المختارة من خيار D-231) وسنوات الزوج الأخير
/// بأرقامها وحدها («سنة كانون الأول السابق وحده») — نقية تُختبر بلا
/// قنوات (نمط س204 عينه)، واليوم المرجعي قابل للحقن. (نُقلت من سجل
/// الفواتير بس235 لتوحيد النمط على الشاشات كلها — عقد واحد مصدر واحد.)
String diqqahPresetSmallLine(
  DiqqahRangePreset preset, {
  DateTime? today,
  DiqqahMonthNames? names,
}) {
  final now = today ?? DateTime.now();
  switch (preset) {
    case DiqqahRangePreset.today:
      return '${now.day} ${diqqahMonthName(now.month, names: names)}';
    case DiqqahRangePreset.thisMonth:
      return diqqahMonthName(now.month, names: names);
    case DiqqahRangePreset.lastMonth:
      // آخر يوم من الشهر الماضي — قوس السنة سالك فالشهر السابق مفعّل
      // دائماً ولو كانت السنة جديدة (يناير: كانون الأول السابق).
      final first = DateTime(now.year, now.month, 1);
      final lastOfPrev = first.subtract(const Duration(days: 1));
      return diqqahMonthName(lastOfPrev.month, names: names);
    case DiqqahRangePreset.thisYear:
      return '${now.year}';
    case DiqqahRangePreset.previousYear:
      return '${now.year - 1}';
  }
}

/// س235 (بكلمة المالك «احذف زر العرض وطبق النمط الجديد لتوحيد تجربة
/// المستخدم»): شريط المدى الفوري الموحد — أزرار التاريخ الخمسة بسطر
/// واحد بسطرها الفعلي الصغير وتلوين المختار (عقد D-234/2 من سجل
/// الفواتير س234) فوق حقلي من/إلى، **بلا زر عرض** (عقد D-234/3):
/// الاختيار يطبق لحظته، والمكتوب ديبونس قصير (نصف ثانية بعد آخر حرف)
/// بحرس الزوج (كلاهما فارغان أو كلاهما تاريخان — فالناقص أو الفاسد
/// انتظار كتابة لا تطبيق ولا وميض أخطاء بكل حرف — عرف D-077 بثوب
/// التطبيق الفوري بقرار المالك)، والتحرير اليدوي يفرغ التلوين،
/// والتمرير الأفقي عند الضيق حصراً.
///
/// العقد: الشاشة تملك المتحكمين وتزوّد [onReload] فيُستدعى عند كل
/// تطبيق (اختيار جاهز أو ديبونس زوج صالح) — و[clear] يفرّغ الحقلين
/// والتلوين بلا تحميل (لمسح الفلاتر الشامل) — والديبونس يُلغى عند
/// الخروج فلا استطالة بعد الموت.
class DiqqahInstantRangeBar extends StatefulWidget {
  final TextEditingController from;
  final TextEditingController to;
  final VoidCallback onReload;

  const DiqqahInstantRangeBar({
    super.key,
    required this.from,
    required this.to,
    required this.onReload,
  });

  @override
  DiqqahInstantRangeBarState createState() => DiqqahInstantRangeBarState();
}

/// عام عمداً — زر «مسح الفلاتر» بالشاشات يفرّغ الشريط بمفتاحه
/// (GlobalKey) عبر [clear] فلا تكرار تحميل.
class DiqqahInstantRangeBarState extends State<DiqqahInstantRangeBar> {
  DiqqahRangePreset? _preset;
  Timer? _applyDebounce;

  /// حرس الملء الآلي — تطبيق الاختصار يملا الحقلين برمجياً فيطلق
  /// مستمعيهما؛ فالحرس يمنع الاستطالة المزدوجة.
  bool _suppressFieldListener = false;

  @override
  void initState() {
    super.initState();
    widget.from.addListener(_onRangeTyped);
    widget.to.addListener(_onRangeTyped);
  }

  @override
  void dispose() {
    _applyDebounce?.cancel();
    super.dispose();
  }

  /// تحرير المدى يدوياً — تأخير قصير ثم التحميل حين يصلح الزوجان
  /// (كلاهما فارغان بلا مدى أو كلاهما تاريخان سليمان)، والتحرير
  /// يفرغ التلوين.
  void _onRangeTyped() {
    if (_suppressFieldListener) return;
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final f = widget.from.text.trim();
      final t = widget.to.text.trim();
      final bothEmpty = f.isEmpty && t.isEmpty;
      final fDate = f.isEmpty ? null : DateTime.tryParse(f);
      final tDate = t.isEmpty ? null : DateTime.tryParse(t);
      if (!bothEmpty && (fDate == null || tDate == null)) return;
      if (_preset != null) setState(() => _preset = null);
      widget.onReload();
    });
  }

  /// تطبيق اختصار التاريخ فوراً — يملأ الحقلين ويتلون المختار ويحمل.
  void _applyPreset(DiqqahRangePreset preset) {
    _applyDebounce?.cancel();
    final (f, t) = diqqahRangeShortcutDates(preset);
    _suppressFieldListener = true;
    widget.from.text = f;
    widget.to.text = t;
    _suppressFieldListener = false;
    setState(() => _preset = preset);
    widget.onReload();
  }

  /// تفريغ الحقلين والتلوين بلا تحميل — لمسح الفلاتر الشامل بالشاشة
  /// (المسح يستدعيه ثم يفرغ ما عنده ويحمل مرة واحدة).
  void clear() {
    _applyDebounce?.cancel();
    _suppressFieldListener = true;
    widget.from.clear();
    widget.to.clear();
    _suppressFieldListener = false;
    if (_preset != null) setState(() => _preset = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _presetButtons(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.from,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                    labelText: S.fromDateLabel,
                    suffixIcon: calendarPickerSuffix(context, widget.from)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.to,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                    labelText: S.toDateLabel,
                    suffixIcon: calendarPickerSuffix(context, widget.to)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// أزرار التاريخ الخمسة بسطر واحد — فوق كل زر سطره الفعلي الصغير،
  /// والمختار معبأ بلون الثيم والبقية محددة، والتمرير الأفقي عند
  /// الضيق حصراً (نمط س234 منقول حرفاً).
  Widget _presetButtons() {
    final entries = <(DiqqahRangePreset, String, Key)>[
      (
        DiqqahRangePreset.today,
        S.todayPreset,
        const ValueKey('date_preset_today')
      ),
      (
        DiqqahRangePreset.thisMonth,
        S.thisMonthPreset,
        const ValueKey('date_preset_this_month')
      ),
      (
        DiqqahRangePreset.lastMonth,
        S.lastMonthPreset,
        const ValueKey('date_preset_last_month')
      ),
      (
        DiqqahRangePreset.thisYear,
        S.thisYearPreset,
        const ValueKey('date_preset_this_year')
      ),
      (
        DiqqahRangePreset.previousYear,
        S.previousYearPreset,
        const ValueKey('date_preset_previous_year')
      ),
    ];
    Widget button(DiqqahRangePreset preset, String label, Key key) {
      final selected = _preset == preset;
      final buttonChild = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            diqqahPresetSmallLine(preset),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 36,
            child: selected
                ? FilledButton(
                    key: key,
                    onPressed: () => _applyPreset(preset),
                    child: buttonChild,
                  )
                : OutlinedButton(
                    key: key,
                    onPressed: () => _applyPreset(preset),
                    child: buttonChild,
                  ),
          ),
        ],
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      // التمرير الأفقي عند الضيق حصراً — تحت 480 عرضاً تمرُّ الأزرار
      // أفقياً بعرض ثابت مريح، وفوقه صف ممتد متوازن.
      final narrow = constraints.maxWidth < 480;
      if (narrow) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                SizedBox(
                    width: 104,
                    child: button(
                        entries[i].$1, entries[i].$2, entries[i].$3)),
              ],
            ],
          ),
        );
      }
      return Row(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
                child: button(
                    entries[i].$1, entries[i].$2, entries[i].$3)),
          ],
        ],
      );
    });
  }
}
