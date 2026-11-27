// تفقيط المبلغ بالعربية — دفعة (14) س-149/D-139 بقرار المالك الحرفي
// «التفقيط للمبلغ لا للكميات» — عرف المحاسبة: «فقط ... لا غير» يجعل
// المطبوع حجياً فتمنع الكلمة الكتابةَ فوق الرقم وتحسم الجدال.
//
// محرك خالص لا مساس له بالبيانات ولا بقاعدة: مدخله أرقام ومخرجه كلمات،
// واختباراته تثبّت الصيغ. بلا حزم خارجية — العربية الفصيحة مباشرة.
//
// القواعد المعتمدة (المرفق الموثق بالبوابة):
// - المعدود المذكر يرفع العدد (ثلاثة دولارات) والمؤنث ينخفضه (ثلاث ليرات).
// - 1: «ليرة سورية واحدة» · 2: «ليرتان سوريتان» · 3..10: جمع المعدود
//   · 11..99: مفرد منصوب («خمس وعشرون ليرة سورية») · المئات مفرد مضاف
//   («مئة ليرة»، «مئتا ليرة») · القياسات ألف/مليون/مليار بصيغها.
// - مئتا وألفا ومليونا صيغتا إضافة حين يلحق المعدودُ القياسَ مباشرة.
library;

/// لسان المعدود: مذكر ترتفع به الأعداد أم مؤنث تنخفض به.
enum TafqitGender { masculine, feminine }

/// صيغ المعدود الجاهزة — تُبنى للعملة من جدولها، ولمعدودها الفرعي.
class TafqitNoun {
  /// بعد الصفر والمئة والقياس («ليرة سورية»).
  final String nominative;

  /// بعد أحد عشر..تسع وتسعون — بحركة النصب حيث لسان المعدود يقتضيها
  /// («دولاراً أمريكياً») وبلا حاجة عندها في المؤنث ب TT اللاحقة.
  final String accusative;

  /// صيغة الواحد الكاملة («ليرة سورية واحدة»).
  final String one;

  /// صيغة الثنائي الكاملة («ليرتان سوريتان»).
  final String dual;

  /// الجمع بعد 3..10 («ليرات سورية»).
  final String plural;

  final TafqitGender gender;

  const TafqitNoun({
    required this.nominative,
    required this.accusative,
    required this.one,
    required this.dual,
    required this.plural,
    required this.gender,
  });
}

/// عملة التفقيط: معدودها الكبير ومعدودها الفرعي (وغايبه سلوك عام
/// «وX من المئة») وقاسمها العشري من أعمدة جدول العملات.
class TafqitCurrency {
  final TafqitNoun major;
  final TafqitNoun? minor;
  final int divisor;

  const TafqitCurrency({
    required this.major,
    required this.minor,
    required this.divisor,
  });
}

/// صيغ العملات المبذورة — العملتان المبذورتان بالنظام م1 (ليرة سورية
/// أساساً ودولار أمريكي) بصيغهما الصحيحة، والتوسعة س146/D-209 بخمس
/// عشرة عملة شائعة بالكتالوج ISO 4217 المضمّن بصيغها المرفاعية
/// الكاملة، وأي عملة قادمة خارج الجدول سلوكها العام باسمها كما هو
/// («وX من المئة» للفرعي — عجز معلن موثق لا صمتاً) حتى تُبذر صيغها.
const Map<String, (TafqitNoun, TafqitNoun)> _currencyMorphology = {
  'SYP': (
    TafqitNoun(
      nominative: 'ليرة سورية',
      accusative: 'ليرة سورية',
      one: 'ليرة سورية واحدة',
      dual: 'ليرتان سوريتان',
      plural: 'ليرات سورية',
      gender: TafqitGender.feminine,
    ),
    TafqitNoun(
      nominative: 'قرش',
      accusative: 'قرشاً',
      one: 'قرش واحد',
      dual: 'قرشان',
      plural: 'قروش',
      gender: TafqitGender.masculine,
    ),
  ),
  'USD': (
    TafqitNoun(
      nominative: 'دولار أمريكي',
      accusative: 'دولاراً أمريكياً',
      one: 'دولار أمريكي واحد',
      dual: 'دولاران أمريكيان',
      plural: 'دولارات أمريكية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'سنت',
      accusative: 'سنتاً',
      one: 'سنت واحد',
      dual: 'سنتان',
      plural: 'سنتات',
      gender: TafqitGender.masculine,
    ),
  ),
  'SAR': (
    TafqitNoun(
      nominative: 'ريال سعودي',
      accusative: 'ريالاً سعودياً',
      one: 'ريال سعودي واحد',
      dual: 'ريالان سعوديان',
      plural: 'ريالات سعودية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'هللة',
      accusative: 'هللةً',
      one: 'هللة واحدة',
      dual: 'هللتان',
      plural: 'هللات',
      gender: TafqitGender.feminine,
    ),
  ),
  'EUR': (
    TafqitNoun(
      nominative: 'يورو',
      accusative: 'يورو',
      one: 'يورو واحد',
      dual: 'يوروان',
      plural: 'يورو',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'سنت',
      accusative: 'سنتاً',
      one: 'سنت واحد',
      dual: 'سنتان',
      plural: 'سنتات',
      gender: TafqitGender.masculine,
    ),
  ),
  'GBP': (
    TafqitNoun(
      nominative: 'جنيه إسترليني',
      accusative: 'جنيهاً إسترلينياً',
      one: 'جنيه إسترليني واحد',
      dual: 'جنيهان إسترلينيان',
      plural: 'جنيهات إسترلينية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'بنس',
      accusative: 'بنساً',
      one: 'بنس واحد',
      dual: 'بنسان',
      plural: 'بنسات',
      gender: TafqitGender.masculine,
    ),
  ),
  'EGP': (
    TafqitNoun(
      nominative: 'جنيه مصري',
      accusative: 'جنيهاً مصرياً',
      one: 'جنيه مصري واحد',
      dual: 'جنيهان مصريان',
      plural: 'جنيهات مصرية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'قرش',
      accusative: 'قرشاً',
      one: 'قرش واحد',
      dual: 'قرشان',
      plural: 'قروش',
      gender: TafqitGender.masculine,
    ),
  ),
  'KWD': (
    TafqitNoun(
      nominative: 'دينار كويتي',
      accusative: 'ديناراً كويتياً',
      one: 'دينار كويتي واحد',
      dual: 'ديناران كويتيان',
      plural: 'دينارات كويتية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'فلس',
      accusative: 'فلساً',
      one: 'فلس واحد',
      dual: 'فلسان',
      plural: 'فلوس',
      gender: TafqitGender.masculine,
    ),
  ),
  'AED': (
    TafqitNoun(
      nominative: 'درهم إماراتي',
      accusative: 'درهماً إماراتياً',
      one: 'درهم إماراتي واحد',
      dual: 'درهمان إماراتيان',
      plural: 'دراهم إماراتية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'فلس',
      accusative: 'فلساً',
      one: 'فلس واحد',
      dual: 'فلسان',
      plural: 'فلوس',
      gender: TafqitGender.masculine,
    ),
  ),
  'QAR': (
    TafqitNoun(
      nominative: 'ريال قطري',
      accusative: 'ريالاً قطرياً',
      one: 'ريال قطري واحد',
      dual: 'ريالان قطريان',
      plural: 'ريالات قطرية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'درهم',
      accusative: 'درهماً',
      one: 'درهم واحد',
      dual: 'درهمان',
      plural: 'دراهم',
      gender: TafqitGender.masculine,
    ),
  ),
  'TRY': (
    TafqitNoun(
      nominative: 'ليرة تركية',
      accusative: 'ليرة تركية',
      one: 'ليرة تركية واحدة',
      dual: 'ليرتان تركيتان',
      plural: 'ليرات تركية',
      gender: TafqitGender.feminine,
    ),
    TafqitNoun(
      nominative: 'كوروش',
      accusative: 'كوروشاً',
      one: 'كوروش واحد',
      dual: 'كوروشان',
      plural: 'كروش',
      gender: TafqitGender.masculine,
    ),
  ),
  'JPY': (
    TafqitNoun(
      nominative: 'ين ياباني',
      accusative: 'يناً يابانياً',
      one: 'ين ياباني واحد',
      dual: 'ينان يابانيان',
      plural: 'ينات يابانية',
      gender: TafqitGender.masculine,
    ),
    // الدقة صفر (ISO) — لا جزء للين فالفرعي غائب أصلاً.
    TafqitNoun(
      nominative: 'سنت',
      accusative: 'سنتاً',
      one: 'سنت واحد',
      dual: 'سنتان',
      plural: 'سنتات',
      gender: TafqitGender.masculine,
    ),
  ),
  'MAD': (
    TafqitNoun(
      nominative: 'درهم مغربي',
      accusative: 'درهماً مغربياً',
      one: 'درهم مغربي واحد',
      dual: 'درهمان مغربيان',
      plural: 'دراهم مغربية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'سنتيم',
      accusative: 'سنتيماً',
      one: 'سنتيم واحد',
      dual: 'سنتيمان',
      plural: 'سنتيمات',
      gender: TafqitGender.masculine,
    ),
  ),
  'TND': (
    TafqitNoun(
      nominative: 'دينار تونسي',
      accusative: 'ديناراً تونسياً',
      one: 'دينار تونسي واحد',
      dual: 'ديناران تونسيان',
      plural: 'دينارات تونسية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'ملّيم',
      accusative: 'ملّيماً',
      one: 'ملّيم واحد',
      dual: 'ملّيمان',
      plural: 'ملّيمات',
      gender: TafqitGender.masculine,
    ),
  ),
  'JOD': (
    TafqitNoun(
      nominative: 'دينار أردني',
      accusative: 'ديناراً أردنياً',
      one: 'دينار أردني واحد',
      dual: 'ديناران أردنيان',
      plural: 'دينارات أردنية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'فلس',
      accusative: 'فلساً',
      one: 'فلس واحد',
      dual: 'فلسان',
      plural: 'فلوس',
      gender: TafqitGender.masculine,
    ),
  ),
  'BHD': (
    TafqitNoun(
      nominative: 'دينار بحريني',
      accusative: 'ديناراً بحرينياً',
      one: 'دينار بحريني واحد',
      dual: 'ديناران بحرينيان',
      plural: 'دينارات بحرينية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'فلس',
      accusative: 'فلساً',
      one: 'فلس واحد',
      dual: 'فلسان',
      plural: 'فلوس',
      gender: TafqitGender.masculine,
    ),
  ),
  'OMR': (
    TafqitNoun(
      nominative: 'ريال عماني',
      accusative: 'ريالاً عمانياً',
      one: 'ريال عماني واحد',
      dual: 'ريالان عمانيان',
      plural: 'ريالات عمانية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'بيسة',
      accusative: 'بيسة',
      one: 'بيسة واحدة',
      dual: 'بيسةتان',
      plural: 'بيسات',
      gender: TafqitGender.feminine,
    ),
  ),
  'IQD': (
    TafqitNoun(
      nominative: 'دينار عراقي',
      accusative: 'ديناراً عراقياً',
      one: 'دينار عراقي واحد',
      dual: 'ديناران عراقيان',
      plural: 'دينارات عراقية',
      gender: TafqitGender.masculine,
    ),
    TafqitNoun(
      nominative: 'فلس',
      accusative: 'فلساً',
      one: 'فلس واحد',
      dual: 'فلسان',
      plural: 'فلوس',
      gender: TafqitGender.masculine,
    ),
  ),
  'LBP': (
    TafqitNoun(
      nominative: 'ليرة لبنانية',
      accusative: 'ليرة لبنانية',
      one: 'ليرة لبنانية واحدة',
      dual: 'ليرتان لبنانيتان',
      plural: 'ليرات لبنانية',
      gender: TafqitGender.feminine,
    ),
    TafqitNoun(
      nominative: 'قرش',
      accusative: 'قرشاً',
      one: 'قرش واحد',
      dual: 'قرشان',
      plural: 'قروش',
      gender: TafqitGender.masculine,
    ),
  ),
  'INR': (
    TafqitNoun(
      nominative: 'روبية هندية',
      accusative: 'روبية هندية',
      one: 'روبية هندية واحدة',
      dual: 'روبيتان هنديتان',
      plural: 'روبيات هندية',
      gender: TafqitGender.feminine,
    ),
    TafqitNoun(
      nominative: 'بيسة',
      accusative: 'بيسة',
      one: 'بيسة واحدة',
      dual: 'بيسةتان',
      plural: 'بيسات',
      gender: TafqitGender.feminine,
    ),
  ),
};

/// بناء عملة التفقيط من صف جدول العملات — الرمز المبذور صيغه الكاملة
/// والغائب سلوك عام باسم العملة كما هو (وثّق بالبوابة عجزاً معلناً
/// لا صمتاً).
TafqitCurrency tafqitCurrencyFor({
  required String code,
  required String name,
  required int minorUnits,
}) {
  final known = _currencyMorphology[code];
  final major = known?.$1 ??
      TafqitNoun(
        nominative: name,
        accusative: name,
        one: '$name واحد',
        dual: name,
        plural: name,
        gender: TafqitGender.masculine,
      );
  var divisor = 1;
  for (var i = 0; i < minorUnits; i++) {
    divisor *= 10;
  }
  final minor = known?.$2;
  return TafqitCurrency(major: major, minor: minor, divisor: divisor);
}

const _onesM = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة'];
const _onesF = ['', 'واحدة', 'اثنتان', 'ثلاث', 'أربع', 'خمس', 'ست', 'سبع', 'ثمان', 'تسع'];

/// لفظ العدد المؤنث المركب 21..99 — «إحدى وعشرون» لا «واحدة وعشرون»
/// و«اثنتان وعشرون» لا «اثنتان» وحدها.
const _compoundOnesF = ['', 'إحدى', 'اثنتان', 'ثلاث', 'أربع', 'خمس', 'ست', 'سبع', 'ثمان', 'تسع'];

const _teensM = ['عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'];
const _teensF = ['عشر', 'إحدى عشرة', 'اثنتا عشرة', 'ثلاث عشرة', 'أربع عشرة', 'خمس عشرة', 'ست عشرة', 'سبع عشرة', 'ثمان عشرة', 'تسع عشرة'];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = ['', 'مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة'];

/// صيغ القياس: مفرد وثنائي وثنائي مضاف وجمع ومنصوب بعد 11..99.
class _Scale {
  final String one;
  final String two;
  final String twoIzafat;
  final String plural;
  final String accusative;
  const _Scale(this.one, this.two, this.twoIzafat, this.plural, this.accusative);
}

// بالميليارد ثم المليون ثم الألف — ترتيب التجميع من الأعلى.
const _scales = [
  _Scale('مليار', 'ملياران', 'مليارا', 'مليارات', 'ملياراً'),
  _Scale('مليون', 'مليونان', 'مليونا', 'ملايين', 'مليوناً'),
  _Scale('ألف', 'ألفان', 'ألفا', 'آلاف', 'ألفاً'),
];

/// كلمات مجموعة 1..999 بلسان المعدود الذي يليها — و[nounFollows]
/// يعني أن المعدود يلحقها مباشرة فتُخفى الثنائية «مئتا» لا «مئتان».
String _groupWords(int g, TafqitGender gender, bool nounFollows) {
  assert(g >= 1 && g <= 999, 'مجموعة التفقيط بين 1 و999');
  final hundreds = g ~/ 100;
  final rest = g % 100;
  final parts = <String>[];
  if (hundreds > 0) {
    parts.add(hundreds == 2 && nounFollows && rest == 0 ? 'مئتا' : _hundreds[hundreds]);
  }
  if (rest > 0) {
    if (rest < 10) {
      parts.add(gender == TafqitGender.feminine ? _onesF[rest] : _onesM[rest]);
    } else if (rest < 20) {
      parts.add(gender == TafqitGender.feminine ? _teensF[rest - 10] : _teensM[rest - 10]);
    } else {
      final u = rest % 10;
      final t = rest ~/ 10;
      if (u == 0) {
        parts.add(_tens[t]);
      } else {
        final unit =
            gender == TafqitGender.feminine ? _compoundOnesF[u] : _onesM[u];
        parts.add('$unit و${_tens[t]}');
      }
    }
  }
  return parts.join(' و');
}

/// كلمات مجموعة قياس (ألف/مليون/مليار) — القياسات مذكر دائماً،
/// و[nounFollows] يجعل الصيغة مضافة لصاقاً بالعملة («خمسة وعشرون ألف
/// ليرة») وغايبها منصوبة موصولة بما بعدها («خمسة عشر ألفاً وخمسمئة»).
String _scalePart(int g, _Scale s, bool nounFollows) {
  assert(g >= 1 && g <= 999, 'مجموعة التفقيط بين 1 و999');
  if (g == 1) return s.one;
  if (g == 2) return nounFollows ? s.twoIzafat : s.two;
  final rest = g % 100;
  final hundreds = g ~/ 100;
  // قبل المقياس تبقى المئات مضافة دائماً: «مئتا ألف» لا «مئتان ألف».
  final hPrefix =
      hundreds > 0 ? (hundreds == 2 ? 'مئتا' : _hundreds[hundreds]) : '';
  if (rest == 0) {
    return hPrefix.isEmpty ? s.one : '$hPrefix ${s.one}';
  }
  if (rest == 1) {
    // العرف المعاصر بالفواتير: «مئة وواحد ألف» (والفصيح «مئة وألف ألف»
    // — حُسم للعرف الأوضح وحُقق باختبار).
    return '$hPrefix وواحد ${s.one}';
  }
  if (rest == 2) {
    return '$hPrefix واثنان ${s.one}';
  }
  if (rest <= 10) {
    final few = hPrefix.isEmpty ? '' : '$hPrefix و';
    return '$few${_onesM[rest]} ${s.plural}';
  }
  final scaleWord = nounFollows ? s.one : s.accusative;
  // كلمات الباقي حصراً (لا المئة — فهي في البادئة) والواو بينهما.
  final mid = hPrefix.isEmpty ? '' : '$hPrefix و';
  return '$mid${_groupWords(rest, TafqitGender.masculine, false)} $scaleWord';
}

/// باقي المجموعة (1..99) بلسان المعدود وصيغته — والفاصلة فارغة عند
/// صفر الباقي. والعشرة من صنف الجمع لا المفرد: «عشر ليرات».
String _restWithNoun(int rest, TafqitNoun noun) {
  if (rest == 0) return '';
  if (rest == 1) return noun.one;
  if (rest == 2) return noun.dual;
  if (rest == 10) {
    final w = noun.gender == TafqitGender.feminine ? 'عشر' : 'عشرة';
    return '$w ${noun.plural}';
  }
  if (rest < 10) {
    final w = noun.gender == TafqitGender.feminine ? _onesF[rest] : _onesM[rest];
    return '$w ${noun.plural}';
  }
  if (rest < 20) {
    final w = noun.gender == TafqitGender.feminine ? _teensF[rest - 10] : _teensM[rest - 10];
    return '$w ${noun.accusative}';
  }
  final u = rest % 10;
  final t = rest ~/ 10;
  if (u == 0) return '${_tens[t]} ${noun.accusative}';
  final unit = noun.gender == TafqitGender.feminine ? _compoundOnesF[u] : _onesM[u];
  return '$unit و${_tens[t]} ${noun.accusative}';
}

/// مجموعة الأحاد (1..999) ومعدودها النهائي — هنا يُختار لسان المعدود
/// وصيغته (مفرد/ثنائي/جمع/منصوب) بحسب باقي المجموعة، والمئتان وحدهما
/// بصيغة الإضافة «مئتا ليرة سورية».
String _onesGroupWithNoun(int g, TafqitNoun noun) {
  final hundreds = g ~/ 100;
  final rest = g % 100;
  final parts = <String>[
    if (hundreds > 0) hundreds == 2 && rest == 0 ? 'مئتا' : _hundreds[hundreds],
  ];
  final restPart = _restWithNoun(rest, noun);
  if (restPart.isNotEmpty) {
    parts.add(restPart);
  } else {
    // مئة صافية — والمعدود يلحقها بمسافة الإضافة لا بواو العطف:
    // «مئة ليرة سورية» و«مئتا ليرة سورية» و«تسعمئة ليرة سورية».
    parts.add(noun.nominative);
  }
  return parts.join(restPart.isEmpty ? ' ' : ' و');
}

/// كلمات عدد صحيح بلسان معدود محدد — أسفل المحرك كله.
String tafqitMajorWords(int n, TafqitNoun noun) {
  if (n < 0) throw ArgumentError.value(n, 'n', 'التفقيط لغير السالب');
  if (n == 0) return 'صفر ${noun.nominative}';
  final billions = n ~/ 1000000000 % 1000;
  final millions = n ~/ 1000000 % 1000;
  final thousands = n ~/ 1000 % 1000;
  final ones = n % 1000;
  final scaleValues = [billions, millions, thousands];
  final parts = <String>[];
  for (var i = 0; i < _scales.length; i++) {
    final g = scaleValues[i];
    if (g == 0) continue;
    // هل المعدود يلحق هذه المجموعة مباشرة؟ نعم إن كانت آخر مجموعة
    // غير صفرية (ما بعدها من القياسات والأحاد كله صفر).
    final isLast = ones == 0 && scaleValues.sublist(i + 1).every((v) => v == 0);
    parts.add(_scalePart(g, _scales[i], isLast));
  }
  if (ones > 0) {
    parts.add(_onesGroupWithNoun(ones, noun));
  } else {
    // لا مجموعة أحاد — المعدود يلحق آخر مقياس: «ألف ليرة سورية».
    parts[parts.length - 1] = '${parts.last} ${noun.nominative}';
  }
  return parts.join(' و');
}

/// كلمات عدد بلا معدود — للسلوك العام حين لا صيغ فرعية معروفة
/// («خمسون من مئة»).
String tafqitBareWords(int n, {TafqitGender gender = TafqitGender.masculine}) {
  if (n < 0) throw ArgumentError.value(n, 'n', 'التفقيط لغير السالب');
  if (n == 0) return 'صفر';
  final billions = n ~/ 1000000000 % 1000;
  final millions = n ~/ 1000000 % 1000;
  final thousands = n ~/ 1000 % 1000;
  final ones = n % 1000;
  final scaleValues = [billions, millions, thousands];
  final parts = <String>[];
  for (var i = 0; i < _scales.length; i++) {
    final g = scaleValues[i];
    if (g == 0) continue;
    parts.add(_scalePart(g, _scales[i], false));
  }
  if (ones > 0) parts.add(_groupWords(ones, gender, true));
  return parts.join(' و');
}

/// سطر التفقيط الكامل بعرف المحاسبة «فقط ... لا غير» — من قيمة
/// العملة المصغرة (minor) وعملتها.
String tafqitAmountWords({
  required int totalMinor,
  required TafqitCurrency currency,
}) {
  final major = totalMinor ~/ currency.divisor;
  final minor = totalMinor % currency.divisor;
  final phrase = <String>[];
  if (major > 0 || minor == 0) {
    phrase.add(tafqitMajorWords(major, currency.major));
  }
  if (minor > 0) {
    if (currency.minor != null) {
      phrase.add(tafqitMajorWords(minor, currency.minor!));
    } else {
      // عملة بلا صيغ فرعية مبذورة: «وخمسون من مئة» — سلوك عام موثق.
      phrase.add(
          '${tafqitBareWords(minor)} من ${tafqitBareWords(currency.divisor)}');
    }
  }
  return 'فقط ${phrase.join(' و')} لا غير';
}
