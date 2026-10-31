/// فواصل الألوف أثناء الكتابة (D-102، دفعة 8 س39) — بلفظ المالك:
/// «بالنسبة لفواصل الألوف يجب أن تعمل أثناء الكتابة» ثم تنبيهه
/// «الفاصلة أيضاً تشمل الكميات والمبالغ، ولكنها لا تشمل أرقام الحسابات
/// والهاتف وغيرها».
///
/// القاعدة الملزمة: الفواصل **طبقة إدخال وعرض حصراً** — المخزن يبقى
/// وحدات صغرى صحيحة خاماً (س7) كما حسم D-092، فهذه توسعة لقراره لا نقض:
/// ما كان عرضاً مفصولاً صار إدخالاً مفصولاً أيضاً. وتطبق في حقول
/// المبالغ والكميات حصراً — لا النسب (خصم 0..100 لا يتجاوز المئة)،
/// ولا التواريخ، ولا أرقام الهوية (أطراف/أصناف/حسابات/هاتف/مستندات).
///
/// المؤشر محفوظ بعدد الأرقام قبل موقعه لا بموضعه الحرفي — فالحذف وسط
/// الرقم لا يقفز إلى النهاية (السلوك المتوقع في كل برامج الفواتير).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// النص المعروض مفصولاً — للقيم المعبأة برمجياً (اقتراح المطابقة الآلي
/// مثلاً) كي لا يعتمد التفريغ على formatter الكتابة الذي لا يمر
/// بالتعيين المباشر.
String groupDigits(int amount) {
  final sign = amount < 0 ? '-' : '';
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return sign + grouped;
}

/// قراءة عدد صحيح من نص قد يحمل فواصل عرض — الفراغ صفر (نمط
/// «بلا سعر بعد» الموثق) والمشوّه يعود بالقيمة التي يحكم عليها
/// مدقق المجال في موضع الاستدعاء.
int parseGroupedInt(String text, {int fallback = 0}) {
  final clean = text.trim().replaceAll(',', '');
  if (clean.isEmpty) return 0;
  return int.tryParse(clean) ?? fallback;
}

/// formatter فواصل الألوف الحي — يعاد بناء النص بعد كل تغيير ويعاد
/// وضع المؤشر بحيث يبقى بعد نفس عدد الأرقام الذي كان قبله.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final clean = newValue.text.replaceAll(',', '');
    // المستخدم فرّغ الحقل — أعده فارغاً لا «0» (الفراغ «بلا سعر بعد»).
    if (clean.isEmpty) {
      return const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0));
    }
    // لوازم الإدخال الرقمي أصلاً — أي غير رقم (لصق شاذ) يُمسح ويعود
    // بأقرب حالة رقمية، فلا يدخل النص غير الصالح إلى وحدات التحكم.
    final digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final formatted = groupDigits(int.parse(digitsOnly));
    // عدد الأرقام قبل المؤشر في النص الجديد قبل التنسيق — يبقى بعده.
    var digitsBeforeCursor = 0;
    for (var i = 0; i < newValue.selection.baseOffset && i < newValue.text.length; i++) {
      final ch = newValue.text[i];
      if (ch != ',') digitsBeforeCursor++;
    }
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCursor) {
      if (formatted[offset] != ',') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// غلاف اعتراض مفتاحي الإضافة (س-109/D-110): Tab والسهم السفلي يضيفان
/// بنداً جديداً ولا يقفزان خارج البطاقة نحو زر الحفظ — والـEnter يعالج
/// onSubmitted الحقل نفسه. العرف الموثق: الاعتراض بعقدة Focus للحقل
/// المركّز يسبق تنقل التركيز فاحتجاز المفتاح محتمل السلوك.
class KeyboardAddLine extends StatelessWidget {
  final Widget child;
  final VoidCallback onAdd;

  const KeyboardAddLine({super.key, required this.child, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.tab ||
                event.logicalKey == LogicalKeyboardKey.arrowDown)) {
          onAdd();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
