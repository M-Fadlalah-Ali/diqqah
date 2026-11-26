/// خط التطبيق المضمّن (D-104 دفعة 8 س39 — ومُحدَّث بقرار D-212 س158)
/// — بلفظ المالك:
/// «أريد الخط الافتراضي للطباعة والعرض: خط ساحل sahel» و«أقترح أيضاً
/// أن لا نسمح باعتماد مكتبة خطوط الجهاز، وإنما أن تكون الخطوط مدمجة
/// مع التطبيق على الكمبيوتر وعلى الهاتف» ثم «احذف خط أميري من الخيارات،
/// أبقِ فقط ساحل وتجوال»، ثم بقرار D-212 (س158 — 2026-11-17) بلفظه
/// الحرفي: «أدرج الخطوط المتبقية» — فأُضيفت الثلاثة الآمنة طباعةً
/// (IBM Plex Sans Arabic وNoto Sans Arabic وVazirmatn) وحُذف تجوال من
/// الخيارات والأصول معاً، و«انقل الخطين ومحرك gsub إلى الأفكار التطويرية
/// المؤجلة» فرُكِن Rubik وReadex Pro ومحرك الطباعة GSUB-aware بقائمة
/// الانتظار (09 §8) عرف التقرير البايتي المصدّق «فحص الخطوط قبل
/// التنفيذ v1.00» بجلسة س158.
///
/// الملزم: مكتبة خطوط مدمجة حصراً — لا خطوط جهاز ولا تحميل خارجي زمن
/// التشغيل — **خيار واحد** يغيّر العرض والطباعة معاً بجواب المالك
/// «واحد» على استئناسنا، والافتراضي ساحل، ورخص الخط الأربعة مرفقة
/// مع الأصول (MIT ساحل — OFL 1.1 للثلاثة المضافة). وأميري (خط الطباعة
/// الرسمي السابق D-101) خرج بD-104 وتجوال خرج بD-212 فلا أصول لهما.
///
/// الاثنان الراكنان لا يدخلان المكتبة اليوم: طباعتهما تنكسر على محرك
/// PDF الحالي (Rubik 17/223 وReadex Pro 0/223 من أشكال العرض الإلزامية
/// — عرف D-104 «خيار واحد يحكم العرض والطباعة معاً»)، وتأهيلهما
/// تلقائيٌّ بتقرير الفحص المنجز حين يُتبنى المحرك الجديد وفق §0.
///
/// الخيار يخزَّن بالإعدادات المشتركة ويقرأه الثيم وprint_service من
/// المُنبِّه ذاته، وكل قراءة محميّة — فشل مخزن الاختبارات يعيد
/// الافتراضي بلا كسر (درس الاختبارات: لا قنوات منصة في التخمين).
/// والمفتاح المحفوظ القديم «tajawal» يُرحَّل عند الإقلاع إلى ساحل
/// تلقائياً بلا كسر سلوك (D-212) فلا ترحيلة قاعدة ولا مساس بها.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// مفتاح الإعدادات المشتركة للخط.
const String kFontChoicePrefsKey = 'app_font_choice';

/// مفاتيح الخيارات بالتخزين والعرض — والأسماء بأسماء عائلات الخط.
const String kFontSahel = 'sahel';
const String kFontPlex = 'plex';
const String kFontNoto = 'noto';
const String kFontVazir = 'vazir';

/// المفتاح القديم المحذوف — للترحيل الصامت عند الإقلاع حصراً (D-212).
const String kFontLegacyTajawal = 'tajawal';

/// الافتراضي المعتمد: ساحل للعرض والطباعة معاً (D-104 وD-212).
const String kDefaultFontKey = kFontSahel;

/// تسميات الخيارات بالواجهة — أربع عائلات مدمجة بقرار D-212.
const List<(String, String)> kFontChoices = [
  (kFontSahel, 'ساحل'),
  (kFontPlex, 'IBM Plex Sans Arabic'),
  (kFontNoto, 'Noto Sans Arabic'),
  (kFontVazir, 'Vazirmatn'),
];

/// مُنبِّه الخيار الحالي — يقرؤه الثيم في الجذر وprint_service عند
/// كل توليد PDF، وتحديثه يعيد بناء الجذر فوراً فتتغير الشاشات
/// والمطبوعات معاً بخيار واحد (جواب المالك «واحد»).
final ValueNotifier<String> appFontChoice =
    ValueNotifier<String>(kDefaultFontKey);

/// عائلة الخط بالواجهة من مفتاح الخيار — أي قيمة غريبة (ومنها المفتاح
/// المحذوف tajawal بعد الترحيل) تعيد ساحل بلا استثناء في قراءة عرضية
/// (نمط resolvePageFormat الموثق).
String appFontFamily(String fontKey) => switch (fontKey) {
      kFontPlex => 'IBMPlexSansArabic',
      kFontNoto => 'NotoSansArabic',
      kFontVazir => 'Vazirmatn',
      _ => 'Sahel',
    };

/// تسجيل عائلات الخط الأربع من الأصول زمن الإقلاع — FontLoader يربط
/// الاسم الذي يستعمله الثيم، والفشل غير قاتل: الخط يقع على النظام
/// بصمت ولا يكسر إقلاعاً ولا اختباراً (الطباعة تحمل ملفاتها بنفسها).
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
/// والمفتاح القديم «tajawal» المحذوف بD-212 يُرحَّل هنا إلى ساحل
/// ويُكتب المحفوظ من جديد فلا يُعاد الترحيل في كل إقلاع.
Future<void> loadFontChoice() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kFontChoicePrefsKey);
    if (saved == kFontSahel ||
        saved == kFontPlex ||
        saved == kFontNoto ||
        saved == kFontVazir) {
      // التضييق الصريح — الدليل لا يضيّق String? بمقارنات const المزدوجة.
      appFontChoice.value = saved!;
    } else if (saved == kFontLegacyTajawal) {
      // ترحيل الخط المحذوف (D-212): صاحب تجوال يعود ساحل الافتراضي
      // فوراً والمحفوظ يُكتب من جديد — بلا كسر ولا سؤال ولا ترحيلة.
      appFontChoice.value = kDefaultFontKey;
      await prefs.setString(kFontChoicePrefsKey, kDefaultFontKey);
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
