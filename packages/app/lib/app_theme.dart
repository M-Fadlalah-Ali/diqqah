/// نظام ألوان دِقَّة — نهاري/ليلي/نظامي (س182 — م05 من تقرير فحص
/// الواجهات وفق M3، بأمر المالك الحرفي):
/// «انشئ نظام ألوان نهاري/ليلي/نظام واعتمد للنهاري #ffffff ولليلي
/// #1e1e1e» ثم «اعتمد الألوان الستة: الليلي: الأخضر 8ACCA1 الأحمر
/// EDB0B0 الأزرق A2C2E2 / النهاري: الأخضر 21452C الأحمر 781C1C
/// الأزرق 1F4061».
///
/// العقد:
/// - **ستة ألوان معتمدة بلسان المالك حصراً** — ثلاثة أدوار دلالية
///   (الأخضر أساساً والأحمر خطأً والأزرق ثانوية) بقرينين: نهاري غامق
///   على فاتح، وليلي فاتح على داكن — عرف M3 في tone mapping (النهاري
///   درجات داكنة والليلي درجات فاتحة) فلا لون خام خارج الطبقة.
/// - **خلفيتان معتمدتان**: النهاري #FFFFFF والليلي #1E1E1E — تثبتان
///   scaffoldBackground لا غير، وما عداهما من أدوار الحاويات يتوالد
///   من بذرة المادة الثالثة (ColorScheme.fromSeed) فتنسجم الهوية
///   بلا اختراع ألوان لم يعتمدها المالك.
/// - **ثلاثة أوضاع**: «نظام» يتبع إعداد الجهاز (الافتراضي)، و«نهاري»
///   و«ليلي» بخيار صريح — تخزين بالإعدادات المشتركة بنمط الخطوط
///   (D-104): المُنبِّه يقرؤه جذر التطبيق فتتغير الشاشة فوراً بلا
///   إقلاع، وفشل المخزن يعيد الافتراضي بلا كسر.
/// - الخط يمر من خارج الطبقة (خيار الخط الموحد D-104) فالثيم يبني
///   بعائلة الخط المختار والطبقة لا تعرف الخطوط.
///
/// **مراجعة س203 (بأمر المالك الحرفي «البني للهوية فقط لا غير»):**
/// البني لون الهوية والتفاعل بالوضعين (نهاري `#8B5A3C` وليلي
/// `#D4A57E`): البذرة وprimary والأزرار والمختارات — **والأخضر
/// المعتمد دلالي حصراً** لا يلوّن تفاعلاً عاماً: أزقة س186 الإيجابية
/// تُشتق من ثوابت الأخضر ذاتها لا من primary، فلا يُرى أخضر إلا
/// دائناً لنا أو سليماً أو مطابقاً. البني للمسة فقط لا غير ولا يدخل
/// الأزقة الدلالية أبداً.
library;

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// مفتاح الإعدادات المشتركة لوضع المظهر.
const String kThemeModePrefsKey = 'app_theme_mode';

/// مفاتيح الأوضاع الثلاثة بالتخزين والعرض.
const String kThemeModeSystem = 'system';
const String kThemeModeLight = 'light';
const String kThemeModeDark = 'dark';

/// الافتراضي: «نظام» — يتبع إعداد الجهاز بلا فرض.
const String kDefaultThemeModeKey = kThemeModeSystem;

/// خيارات الوضع بالواجهة: (المفتاح، التسمية، الأيقونة).
const List<(String, String, IconData)> kThemeModeChoices = [
  (kThemeModeSystem, 'نظام (يتبع الجهاز)', Icons.brightness_auto_outlined),
  (kThemeModeLight, 'نهاري', Icons.light_mode_outlined),
  (kThemeModeDark, 'ليلي', Icons.dark_mode_outlined),
];

/// مُنبِّه الوضع الحالي — يقرؤه جذر التطبيق، وتحديثه يعيد بناء الجذر
/// فوراً فتتبدل الشاشة كلها بخيار واحد بلا إقلاع (نمط الخط D-104).
final ValueNotifier<String> appThemeMode =
    ValueNotifier<String>(kDefaultThemeModeKey);

/// ترجمة مفتاح الوضع إلى ThemeMode — أي قيمة غريبة تعيد «نظام»
/// بلا استثناء (نمط resolvePageFormat الموثق).
ThemeMode themeModeOf(String key) => switch (key) {
      kThemeModeLight => ThemeMode.light,
      kThemeModeDark => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// قراءة الوضع المحفوظ عند الإقلاع — وأي فشل (اختبارات بلا مخزن أو
/// منصة بلا إعدادات) يعيد الافتراضي «نظام» بلا استثناء يكسر إقلاعاً.
Future<void> loadThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kThemeModePrefsKey);
    if (saved == kThemeModeLight ||
        saved == kThemeModeDark ||
        saved == kThemeModeSystem) {
      // التضييق الصريح — الدليل لا يضيّق String? بمقارنات const المزدوجة.
      appThemeMode.value = saved!;
    }
  } catch (_) {
    // الافتراضي باقٍ — بلا كسر.
  }
}

/// حفظ الوضع بعد تغييره من الإعدادات — والفشل يحتمل: الوضع تغيّر
/// بالجلسة أصلاً والمحفوظ يعاد محاولته في الإقلاع التالي.
Future<void> saveThemeMode(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModePrefsKey, key);
  } catch (_) {
    // بلا كسر — الخيار حي بالذاكرة.
  }
}

// ── الألوان الستة المعتمدة بلسان المالك حرفاً (س182) ──

/// النهاري الأخضر — الدور الأساسي بالنهار: هوية دِقَّة الغامقة.
const Color kLightGreen = Color(0xFF21452C);

/// النهاري الأحمر — دور الخطأ بالنهار.
const Color kLightRed = Color(0xFF781C1C);

/// النهاري الأزرق — الدور الثانوي بالنهار.
const Color kLightBlue = Color(0xFF1F4061);

/// الليلي الأخضر — الدور الأساسي بالليل: فاتح على الداكن.
const Color kDarkGreen = Color(0xFF8ACCA1);

/// الليلي الأحمر — دور الخطأ بالليل.
const Color kDarkRed = Color(0xFFEDB0B0);

/// الليلي الأزرق — الدور الثانوي بالليل.
const Color kDarkBlue = Color(0xFFA2C2E2);

/// البني النهاري — لون الهوية والتفاعل حصراً (س203 بأمر المالك
/// «البني للهوية فقط لا غير»): بذرة النهار وprimary فوق الأبيض
/// بتباين > 4.5:1 (اختبار theme_test) — ولا يدخل الأزقة الدلالية
/// أبداً.
const Color kLightIdentityBrown = Color(0xFF8B5A3C);

/// البني الليلي — لون الهوية والتفاعل بالليل (س203): بذرة الليل
/// وprimary الفاتح فوق الداكن بتباين > 4.5:1 — ولا يدخل الأزقة
/// الدلالية أبداً.
const Color kDarkIdentityBrown = Color(0xFFD4A57E);

/// حاوية الخطأ الليلية الهادئة (س202 — بأمر المالك الحرفي «عدل الأحمر
/// كما اقترحت» على شكواه «الأحمر بالليلي قوي وملمّع»): كانت الشريطية
/// الليلية تقرأ errorContainer من بذرة المادة فصار الشريط أحمر صريحاً
/// يلمع فوق خلفية الليل. الضبط الصريح بتون داكن من عائلة الخطأ M3
/// (#8C1D18) أدنى درجة وقرب خلفية الليل فيهدأ الشريط مع بقاء الدلالة،
/// ولسانه الوردي الفاتح باقٍ فوقه بتباين > 4.5:1 (اختبار theme_test).
/// الأزقة الدلالية لا تمسّ — مشتقة من scheme.error لا من الحاوية.
const Color kDarkErrorContainer = Color(0xFF421D17);

/// لسان النص فوق حاوية الخطأ الليلية الهادئة — وردي فاتح مخفف عن
/// قرين M3 الافتراضي (#F9DEDC) فيبقى الزوج مقروءاً هادئاً معاً.
const Color kDarkOnErrorContainer = Color(0xFFE8C0BB);

// ── قواعد التلميح المركزية (س207 — تنظيف ويندوز، بند 4 من نقاش
// المالك المعتمد: «شرح وظيفة الأيقونات على ويندوز يغطي على اسمها») ──
//
// العقد:
// - **التأخير 500ms**: التلميح لا يبزغ عند العبور العابر — عرف سطح
//   المكتب الناضج (Windows/Fluent والويب) فلا ضجيج تلميحات بالممر.
// - **الظهور فوق لا تحت**: الافتراضي المادة يظهر التلميح أسفل الأيقونة
//   فيغطي نص اسمها تحتها (شكوى المالك بند 4) — فالقاعدة المركزية
//   preferBelow:false فيظهر فوق الأيقونة فالتسمية باقية مقروءة دائماً،
//   والمادة تعكس آلياً عند الحافة إن لم يتسع فوق.
// - **ثلاث ثوانٍ عرضاً**: قراءة مريحة ثم هدوء.
// - **لا تلميح يكرر اسم ظاهر**: قاعدة كتابية على الشاشات — والفحص
//   الحي: التلميح الوحيد بالشجرة (بلاطة الرئيسية) يحمل مرحلة الوحدة
//   لا اسمها (الاسم نص ظاهر مستقل) فالقاعدة محققة، والتلميح الوحيد
//   الآخر بشاشة الفواتير (tooltip: على أزرار أيقونية بلا اسم ظاهر)
//   مشروع لأن الاسم غير ظاهر أصلاً.
const Duration kTooltipWaitDuration = Duration(milliseconds: 500);
const Duration kTooltipShowDuration = Duration(seconds: 3);

/// سمة التلميح الموحدة — تمر للثيمين معاً حرفاً (immutable مشترك).
const TooltipThemeData kDiqqahTooltipTheme = TooltipThemeData(
  waitDuration: kTooltipWaitDuration,
  showDuration: kTooltipShowDuration,
  preferBelow: false,
);

/// خلفية النهار المعتمدة: أبيض خالص.
const Color kLightBackground = Color(0xFFFFFFFF);

/// خلفية الليل المعتمدة: داكن بدرجة #1E1E1E.
const Color kDarkBackground = Color(0xFF1E1E1E);

/// ثيم النهار — الأدوار الثلاثة المعتمدة فوق خلفية بيضاء، والحاويات
/// من بذرة المادة الثلاثة فتنسجم بلا ألوان مبتدعة — ومعها أزقة دِقَّة
/// الدلالية (س186) مشتقة من الأدوار الدلالية المعتمدة لا من primary
/// بعد مراجعة س203.
ThemeData buildLightTheme(String fontFamily) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kLightIdentityBrown,
    brightness: Brightness.light,
  ).copyWith(
    primary: kLightIdentityBrown,
    onPrimary: kLightBackground,
    secondary: kLightBlue,
    onSecondary: kLightBackground,
    error: kLightRed,
    onError: kLightBackground,
    surface: kLightBackground,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: kLightBackground,
    // س203 (صقل M3): بطاقات مسطحة بزوايا موحدة — بلا ظل يزاحم
    // الأزقة الدلالية وبلا هوامش مفروضة تُغيّر ما ضبطته المواضع.
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    // س207: قواعد التلميح المركزية — فوق الأيقونة لا تحت فلا تلميح
    // يغطي اسم ظاهراً، وبتأخير 500ms فلا بزغ عبور.
    tooltipTheme: kDiqqahTooltipTheme,
    extensions: [diqqahLanesFromScheme(scheme)],
  );
}

/// ثيم الليل — الأدوار الثلاثة الفاتحة فوق خلفية داكنة، ونصوص الأدوار
/// بلون الخلفية الداكن نفسها فتبقى الأزواج الثلاثة مقروءة — ومعها
/// أزقتاه الدلالية (س186) المشتقة منها.
ThemeData buildDarkTheme(String fontFamily) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kDarkIdentityBrown,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kDarkIdentityBrown,
    onPrimary: kDarkBackground,
    secondary: kDarkBlue,
    onSecondary: kDarkBackground,
    error: kDarkRed,
    onError: kDarkBackground,
    // س202: حاوية الخطأ الليلية الهادئة بأمر المالك «عدل الأحمر كما
    // اقترحت» — شريط المتابعة/التنبيه الليلي كان يلمع بصرياً فهدأ
    // بتون داكن قرب الخلفية مع بقاء الدلالة وتباين اللسان > 4.5:1.
    errorContainer: kDarkErrorContainer,
    onErrorContainer: kDarkOnErrorContainer,
    surface: kDarkBackground,
    // س225 (خ7 من الدفعة الأولى للحيوية بأمر المالك «الليل يكتسب
    // عمقاً»): سلالم الحاويات الخمس تُشتق بمزج البذرة البنية على
    // الخلفية المعتمدة بنسب متدرجة فتطفو البطاقات والأقراص فوق
    // السطح بدفء الهوية لا بلون خام — عقد س182 باقٍ حرفاً: الخلفية
    // المعتمدة وسطح المخطط لا يُمسّان، والأدوار الدلالية وأزقتها
    // لا تُمسّ، والنهار بأدواره المشتقة كما كان.
    surfaceContainerLowest:
        Color.lerp(kDarkBackground, kDarkIdentityBrown, 0.02)!,
    surfaceContainerLow:
        Color.lerp(kDarkBackground, kDarkIdentityBrown, 0.055)!,
    surfaceContainer:
        Color.lerp(kDarkBackground, kDarkIdentityBrown, 0.09)!,
    surfaceContainerHigh:
        Color.lerp(kDarkBackground, kDarkIdentityBrown, 0.13)!,
    surfaceContainerHighest:
        Color.lerp(kDarkBackground, kDarkIdentityBrown, 0.18)!,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: kDarkBackground,
    // س203 (صقل M3): نفس البلاط المسطح بالليل انسجاماً مع النهار.
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    // س207: قواعد التلميح المركزية — نفس السمة بالوضعين حرفاً.
    tooltipTheme: kDiqqahTooltipTheme,
    extensions: [diqqahLanesFromScheme(scheme)],
  );
}

// ── الأزقة الدلالية (س186 — بقية م05 من تقرير فحص M3) ──
//
// العقد: لكل موضع لوني دلالي (نوع فاتورة، حالة أمر، جدة سطر، صحة نسخ)
// زوقٌ واحد من ثلاثة أدوار معتمدة لا غير: الإيجابي الأخضر (دائن لنا /
// سليم / مطابق)، والسلبي الأحمر (مدين علينا / خطأ / فشل)، والانتباه
// الأزرق (معلومة / التزام معلن / تنبيه بلا فشل) — بقرين مخطط لكل دور
// (بلا تعبئة) يفرّق المردودَ عن أصله، وقرين محايد باهت بلا دلالة.
// التعبئة والإطار يُشتقان بألفا من لون الدور فوق خلفية المخطط نفسها،
// فلا تُخترع عائلة لونية لم يعتمدها المالك (عقد س182 باقٍ حرفاً)،
// والتباين يُفحص اختباراً بحد WCAG 4.5:1 بالوضعين.

/// زوق دلالي واحد — نص وتعبئة وإطار، والتعبئة الشفافة تعني زوقاً
/// مخططاً (المردودات) يقرأ إطاره دون غمر خلفية.
@immutable
class DiqqahLane {
  const DiqqahLane({
    required this.fg,
    required this.bg,
    required this.border,
    this.outlined = false,
  });

  /// لون النص والأيقونة فوق التعبئة.
  final Color fg;

  /// تعبئة الخلفية — شفافة للزوق المخطط.
  final Color bg;

  /// لون الإطار المحيط.
  final Color border;

  /// زوق مخطط (مردود) — بلا تعبئة وإطاره بلون الدور كاملاً.
  final bool outlined;
}

/// أزقة دِقَّة السبعة — مسجلة بامتداد الثيم فتتبدل بالوضعين معه.
@immutable
class DiqqahLanes extends ThemeExtension<DiqqahLanes> {
  const DiqqahLanes({
    required this.positive,
    required this.negative,
    required this.attention,
    required this.positiveOutline,
    required this.negativeOutline,
    required this.attentionOutline,
    required this.neutral,
  });

  /// الإيجابي — الأخضر المعتمد: دائن لنا / سليم / مطابق / وفّى.
  final DiqqahLane positive;

  /// السلبي — الأحمر المعتمد: مدين علينا / خطأ / فشل / ملغى.
  final DiqqahLane negative;

  /// الانتباه — الأزرق المعتمد: معلومة / معلن / تنبيه بلا فشل.
  final DiqqahLane attention;

  /// مردود الاتجاه الإيجابي (مردود شراء) — أخضر بإطار بلا تعبئة.
  final DiqqahLane positiveOutline;

  /// مردود الاتجاه السلبي (مردود بيع) — أحمر بإطار بلا تعبئة.
  final DiqqahLane negativeOutline;

  /// انتباه مخطط — أزرق بإطار (سيُنشأ آلياً بعد الاعتماد).
  final DiqqahLane attentionOutline;

  /// المحايد — بلا دلالة: باهت من أدوار المخطط ذاته.
  final DiqqahLane neutral;

  @override
  DiqqahLanes copyWith({
    DiqqahLane? positive,
    DiqqahLane? negative,
    DiqqahLane? attention,
    DiqqahLane? positiveOutline,
    DiqqahLane? negativeOutline,
    DiqqahLane? attentionOutline,
    DiqqahLane? neutral,
  }) =>
      DiqqahLanes(
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
        attention: attention ?? this.attention,
        positiveOutline: positiveOutline ?? this.positiveOutline,
        negativeOutline: negativeOutline ?? this.negativeOutline,
        attentionOutline: attentionOutline ?? this.attentionOutline,
        neutral: neutral ?? this.neutral,
      );

  @override
  DiqqahLanes lerp(DiqqahLanes? other, double t) {
    if (other == null) return this;
    DiqqahLane lerpLane(DiqqahLane a, DiqqahLane b) => DiqqahLane(
          fg: Color.lerp(a.fg, b.fg, t)!,
          bg: Color.lerp(a.bg, b.bg, t)!,
          border: Color.lerp(a.border, b.border, t)!,
          outlined: t < 0.5 ? a.outlined : b.outlined,
        );
    return DiqqahLanes(
      positive: lerpLane(positive, other.positive),
      negative: lerpLane(negative, other.negative),
      attention: lerpLane(attention, other.attention),
      positiveOutline: lerpLane(positiveOutline, other.positiveOutline),
      negativeOutline: lerpLane(negativeOutline, other.negativeOutline),
      attentionOutline: lerpLane(attentionOutline, other.attentionOutline),
      neutral: lerpLane(neutral, other.neutral),
    );
  }
}

/// بناء زوق معبأ من لون الدور — التعبئة مزج 10% والحد 34% فوق خلفية
/// المخطط فتبقى الأزواج فاتحة النهار داكنة الليل بتباين مقروء.
DiqqahLane _filledLane(Color role, Color surface) => DiqqahLane(
      fg: role,
      bg: Color.lerp(surface, role, 0.10)!,
      border: Color.lerp(surface, role, 0.34)!,
    );

/// بناء زوق مخطط — بلا تعبئة وإطاره بلون الدور كاملاً فيقرأ عوداً.
DiqqahLane _outlineLane(Color role) => DiqqahLane(
      fg: role,
      bg: const Color(0x00000000),
      border: role,
      outlined: true,
    );

/// اشتقاق الأزقة السبعة من مخطط ألوان.
///
/// **س203:** الإيجابي من ثوابت الأخضر المعتمدة ذاتها بحسب الوضع لا من
/// `scheme.primary` — فprimary صار بُنياً للهوية لا غير بأمر المالك
/// والأخضر دلالي حصراً. الأحمر والأزرق من أدوارهما القائمة.
Color _laneSemanticGreenOf(ColorScheme scheme) =>
    scheme.brightness == Brightness.light ? kLightGreen : kDarkGreen;
DiqqahLanes diqqahLanesFromScheme(ColorScheme scheme) => DiqqahLanes(
      positive: _filledLane(_laneSemanticGreenOf(scheme), scheme.surface),
      negative: _filledLane(scheme.error, scheme.surface),
      attention: _filledLane(scheme.secondary, scheme.surface),
      positiveOutline: _outlineLane(_laneSemanticGreenOf(scheme)),
      negativeOutline: _outlineLane(scheme.error),
      attentionOutline: _outlineLane(scheme.secondary),
      neutral: DiqqahLane(
        fg: scheme.onSurfaceVariant,
        bg: Color.lerp(scheme.surface, scheme.onSurfaceVariant, 0.10)!,
        border: scheme.outlineVariant,
      ),
    );

/// قراءة الأزقة من الثيم الحاكم — وسقوط الثيم القديم (اختبارات بلا
/// طبقتنا) يشتقها من مخطط المادة القائم فلا كسر أبداً.
DiqqahLanes diqqahLanesOf(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<DiqqahLanes>() ??
      diqqahLanesFromScheme(theme.colorScheme);
}
