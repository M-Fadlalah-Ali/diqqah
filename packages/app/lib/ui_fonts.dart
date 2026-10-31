/// خط التطبيق المضمّن (D-104، دفعة 8 س39) — بلفظ المالك:
/// «أريد الخط الافتراضي للطباعة والعرض: خط ساحل sahel» و«يمكن إضافة
/// خط تجوال» و«أقترح أيضاً أن لا نسمح باعتماد مكتبة خطوط الجهاز، وإنما
/// أن تكون الخطوط مدمجة مع التطبيق على الكمبيوتر وعلى الهاتف» ثم
/// «احذف خط أميري من الخيارات، أبقِ فقط ساحل وتجوال».
///
/// الملزم: مكتبة خطين مدمجين حصراً (ساحل، تجوال) — لا خطوط جهاز ولا
/// تحميل خارجي زمن التشغيل — **خيار واحد** يغيّر العرض والطباعة معاً
/// بجوابه «واحد» على استئناسنا، والافتراضي ساحل. وأميري (خط الطباعة
/// الرسمي السابق D-101) خرج من الخيارات وأصوله حُذفت بقرار D-104 ذاته.
/// رخصتا الخطين (MIT ساحل — OFL تجوال) مرفقتان مع الأصول التزاماً بهما.
///
/// الخيار يخزَّن بالإعدادات المشتركة ويقرأه الثيم وprint_service من
/// المُنبِّه ذاته، وكل قراءة محميّة — فشل مخزن الاختبارات يعيد
/// الافتراضي بلا كسر (درس الاختبارات: لا قنوات منصة في التخمين).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// مفتاح الإعدادات المشتركة للخط.
const String kFontChoicePrefsKey = 'app_font_choice';

/// مفاتيح الخيارات بالتخزين والعرض — والأسماء بأسماء عائلات الخط.
const String kFontSahel = 'sahel';
const String kFontTajawal = 'tajawal';

/// الافتراضي المعتمد: ساحل للعرض والطباعة معاً (D-104).
const String kDefaultFontKey = kFontSahel;

/// تسميات الخيارات بالواجهة.
const List<(String, String)> kFontChoices = [
  (kFontSahel, 'ساحل'),
  (kFontTajawal, 'تجوال'),
];

/// مُنبِّه الخيار الحالي — يقرؤه الثيم في الجذر وprint_service عند
/// كل توليد PDF، وتحديثه يعيد بناء الجذر فوراً فتتغير الشاشات
/// والمطبوعات معاً بخيار واحد (جواب المالك «واحد»).
final ValueNotifier<String> appFontChoice =
    ValueNotifier<String>(kDefaultFontKey);

/// عائلة الخط بالواجهة من مفتاح الخيار — أي قيمة غريبة تعيد ساحل
/// (لا استثناء في قراءة عرضية، نمط resolvePageFormat الموثق).
String appFontFamily(String fontKey) =>
    fontKey == kFontTajawal ? 'Tajawal' : 'Sahel';

/// تسجيل عائلتي الخط من الأصول زمن الإقلاع — FontLoader يربط الاسم
/// الذي يستعمله الثيم، والفشل غير قاتل: الخط يقع على النظام بصمت
/// ولا يكسر إقلاعاً ولا اختباراً (الطباعة تحمل ملفاتها بنفسها).
Future<void> preloadAppFonts() async {
  for (final (key, _) in kFontChoices) {
    final family = appFontFamily(key);
    final suffixes = ['-Regular', '-Bold'];
    final loader = FontLoader(family);
    for (final suffix in suffixes) {
      try {
        final data =
            await rootBundle.load('assets/fonts/$family$suffix.ttf');
        loader.addFont(Future.value(data));
      } catch (_) {
        // الأصل مفقود — الخط يبقى غير مسجل ويقع على النظام، بلا انهيار.
      }
    }
    try {
      await loader.load();
    } catch (_) {
      // نفس الغلاف — إقلاع التطبيق أقدس من خط.
    }
  }
}

/// قراءة الخيار المحفوظ عند الإقلاع — وأي فشل (اختبارات بلا مخزن
/// أو منصة بلا إعدادات) يعيد الافتراضي ساحل بلا استثناء يكسر إقلاعاً.
Future<void> loadFontChoice() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kFontChoicePrefsKey);
    if (saved == kFontSahel || saved == kFontTajawal) {
      // التضييق الصريح — الدليل لا يضيّق String? بمقارنات const المزدوجة.
      appFontChoice.value = saved!;
    }
  } catch (_) {
    // الافتراضي باقٍ — بلا كسر.
  }
}

/// حفظ الخيار بعد تغييره من الإعدادات — والفشل هنا يحتمل: الثيم
/// تغيّر بالجلسة أصلاً والمحفوظ يعاد محاولته في الإقلاع التالي.
Future<void> saveFontChoice(String fontKey) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kFontChoicePrefsKey, fontKey);
  } catch (_) {
    // بلا كسر — الخيار حي بالذاكرة.
  }
}
