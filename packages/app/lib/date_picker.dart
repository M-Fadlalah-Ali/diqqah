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

import 'package:flutter/material.dart';

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
/// - **لا تفتح شيئاً ولا تُعيد تحميل**: تملأ الحقلين حصراً وعينَ
///   زر «عرض» القائم هو الذي يُدقق ويُحمّل — عرف D-077 باقٍ حرفاً
///   (حرس المدقق أول قبل لمس القاعدة) وعقد م02 س182 باقٍ: تحسين
///   طبقة الإدخال دون لمس منطق المدقق والتصفية.
enum DiqqahRangePreset { today, thisMonth, lastMonth, thisYear }

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
  }
}

/// صف اختصارات المدى — رقائق تملأ حقلي من/إلى الممرَّرين. الشاشات
/// لا تمرر [onPicked] إلا إن أرادت setState بعد الملء (بنمط المعاينة
/// اللحظية D-102) — والافتراضي ملءٌ صامت وزر العرض هو الفعّال.
class DiqqahRangeShortcuts extends StatelessWidget {
  final TextEditingController from;
  final TextEditingController to;
  final VoidCallback? onPicked;

  const DiqqahRangeShortcuts({
    super.key,
    required this.from,
    required this.to,
    this.onPicked,
  });

  static const Map<DiqqahRangePreset, String> _labels = {
    DiqqahRangePreset.today: 'اليوم',
    DiqqahRangePreset.thisMonth: 'هذا الشهر',
    DiqqahRangePreset.lastMonth: 'الشهر الماضي',
    DiqqahRangePreset.thisYear: 'هذا العام',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final e in _labels.entries)
            ActionChip(
              label: Text(e.value),
              tooltip: 'ملء المدى: ${e.value}',
              onPressed: () {
                final (f, t) = diqqahRangeShortcutDates(e.key);
                from.text = f;
                to.text = t;
                // مؤشر الكتابة لآخر الحقلين — درس س182 نفسه.
                from.selection =
                    TextSelection.collapsed(offset: from.text.length);
                to.selection =
                    TextSelection.collapsed(offset: to.text.length);
                onPicked?.call();
              },
            ),
        ],
      ),
    );
  }
}
