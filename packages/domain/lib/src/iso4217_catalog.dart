// كتالوج العملات ISO 4217 المضمّن — س146/D-209.
//
// توليد آلي بالسكربت scripts/gen_iso4217_catalog.py
// (Babel 2.18 — CLDR 45 — 2026-11-15) — لا تحرير يدوي
// عليه: التحديث عند تغيّرات ISO بإعادة التشغيل ومراجعة الفروق.
//
// - العملات: ISO 4217 نشطة بعملات الدفع حصراً
//   (بلا أكواد الأموال والمعادن والاختبار والمتقادمة).
// - nameAr/nameEn/symbol: CLDR (locale ar/en) بتطبيع الرمز
//   (نزع بادئة الحروف اللاتينية والنقطة الختامية).
// - minorUnits: دقة الفواصل العشرية الافتراضية من الوحدة
//   الصغرى ISO عبر CLDR — الاقتراح المعرض للمستخدم القابل
//   للتعديل قبل الحفظ (D-209) وبعد الحفظ لا تعديل (D-194).
// - subunitAr: اسم الجزء العربي المنقَّح يدوياً للشائع،
//   والغائب سلوك عام موثق بالتققيط («وX من المئة»).
//
// المصفوفة مرتبة بالكود تصاعدياً وتُفحص سلامتها بالاختبارات
// (domain/test/iso4217_catalog_test.dart).
library;

/// صف كتالوج ISO 4217 — قيم ثابتة لا تتغير بعد التوليد.
class IsoCurrency {
  /// الكود الحرفي ثلاثي A-Z (ISO 4217 alpha-3).
  final String code;

  /// الاسم العربي المعروض (CLDR — عربي).
  final String nameAr;

  /// الاسم الإنجليزي الرسمي (CLDR — إنجليزي) للبحث ثنائي اللغة.
  final String nameEn;

  /// الرمز المعروض المطبَّع — والغائب يعرض الكود حرفاً
  /// (نمط currency_display الموثق س50/D-156).
  final String symbol;

  /// دقة الفواصل العشرية الافتراضية = الوحدة الصغرى ISO
  /// (0..3 ضمن المدى الأوسع 0..8 بالتحقق F-120).
  final int minorUnits;

  /// اسم الجزء العربي للتققيط — للشائع المنقَّح حصراً.
  final String? subunitAr;

  const IsoCurrency({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.symbol,
    required this.minorUnits,
    this.subunitAr,
  });
}

/// الكتالوج الكامل — 155 عملة دفع نشطة (ISO 4217).
const List<IsoCurrency> kIso4217Currencies = [
  IsoCurrency(code: 'AED', nameAr: 'درهم إماراتي', nameEn: 'United Arab Emirates Dirham', symbol: 'د.إ', minorUnits: 2, subunitAr: 'فلس'),
  IsoCurrency(code: 'AFN', nameAr: 'أفغاني', nameEn: 'Afghan Afghani', symbol: 'AFN', minorUnits: 0),
  IsoCurrency(code: 'ALL', nameAr: 'ليك ألباني', nameEn: 'Albanian Lek', symbol: 'ALL', minorUnits: 0),
  IsoCurrency(code: 'AMD', nameAr: 'درام أرميني', nameEn: 'Armenian Dram', symbol: 'AMD', minorUnits: 2),
  IsoCurrency(code: 'ANG', nameAr: 'غيلدر أنتيلي هولندي', nameEn: 'Netherlands Antillean Guilder', symbol: 'ANG', minorUnits: 2),
  IsoCurrency(code: 'AOA', nameAr: 'كوانزا أنغولي', nameEn: 'Angolan Kwanza', symbol: 'AOA', minorUnits: 2),
  IsoCurrency(code: 'ARS', nameAr: 'بيزو أرجنتيني', nameEn: 'Argentine Peso', symbol: 'ARS', minorUnits: 2),
  IsoCurrency(code: 'AUD', nameAr: 'دولار أسترالي', nameEn: 'Australian Dollar', symbol: '\$', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'AWG', nameAr: 'فلورن أروبي', nameEn: 'Aruban Florin', symbol: 'AWG', minorUnits: 2),
  IsoCurrency(code: 'AZN', nameAr: 'مانات أذربيجان', nameEn: 'Azerbaijani Manat', symbol: 'AZN', minorUnits: 2),
  IsoCurrency(code: 'BAM', nameAr: 'مارك البوسنة والهرسك قابل للتحويل', nameEn: 'Bosnia-Herzegovina Convertible Mark', symbol: 'BAM', minorUnits: 2),
  IsoCurrency(code: 'BBD', nameAr: 'دولار بربادوسي', nameEn: 'Barbadian Dollar', symbol: 'BBD', minorUnits: 2),
  IsoCurrency(code: 'BDT', nameAr: 'تاكا بنغلاديشي', nameEn: 'Bangladeshi Taka', symbol: 'BDT', minorUnits: 2),
  IsoCurrency(code: 'BGN', nameAr: 'ليف بلغاري', nameEn: 'Bulgarian Lev', symbol: 'BGN', minorUnits: 2),
  IsoCurrency(code: 'BHD', nameAr: 'دينار بحريني', nameEn: 'Bahraini Dinar', symbol: 'د.ب', minorUnits: 3, subunitAr: 'فلس'),
  IsoCurrency(code: 'BIF', nameAr: 'فرنك بروندي', nameEn: 'Burundian Franc', symbol: 'BIF', minorUnits: 0),
  IsoCurrency(code: 'BMD', nameAr: 'دولار برمودي', nameEn: 'Bermudan Dollar', symbol: 'BMD', minorUnits: 2),
  IsoCurrency(code: 'BND', nameAr: 'دولار بروناي', nameEn: 'Brunei Dollar', symbol: 'BND', minorUnits: 2),
  IsoCurrency(code: 'BOB', nameAr: 'بوليفيانو بوليفي', nameEn: 'Bolivian Boliviano', symbol: 'BOB', minorUnits: 2),
  IsoCurrency(code: 'BRL', nameAr: 'ريال برازيلي', nameEn: 'Brazilian Real', symbol: '\$', minorUnits: 2),
  IsoCurrency(code: 'BSD', nameAr: 'دولار باهامي', nameEn: 'Bahamian Dollar', symbol: 'BSD', minorUnits: 2),
  IsoCurrency(code: 'BTN', nameAr: 'نولتوم بوتاني', nameEn: 'Bhutanese Ngultrum', symbol: 'BTN', minorUnits: 2),
  IsoCurrency(code: 'BWP', nameAr: 'بولا بتسواني', nameEn: 'Botswanan Pula', symbol: 'BWP', minorUnits: 2),
  IsoCurrency(code: 'BYN', nameAr: 'روبل بيلاروسي', nameEn: 'Belarusian Ruble', symbol: 'BYN', minorUnits: 2),
  IsoCurrency(code: 'BZD', nameAr: 'دولار بليزي', nameEn: 'Belize Dollar', symbol: 'BZD', minorUnits: 2),
  IsoCurrency(code: 'CAD', nameAr: 'دولار كندي', nameEn: 'Canadian Dollar', symbol: '\$', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'CDF', nameAr: 'فرنك كونغولي', nameEn: 'Congolese Franc', symbol: 'CDF', minorUnits: 2),
  IsoCurrency(code: 'CHF', nameAr: 'فرنك سويسري', nameEn: 'Swiss Franc', symbol: 'CHF', minorUnits: 2, subunitAr: 'سنتيم'),
  IsoCurrency(code: 'CLP', nameAr: 'بيزو تشيلي', nameEn: 'Chilean Peso', symbol: 'CLP', minorUnits: 0),
  IsoCurrency(code: 'CNY', nameAr: 'يوان صيني', nameEn: 'Chinese Yuan', symbol: '¥', minorUnits: 2),
  IsoCurrency(code: 'COP', nameAr: 'بيزو كولومبي', nameEn: 'Colombian Peso', symbol: 'COP', minorUnits: 2),
  IsoCurrency(code: 'CRC', nameAr: 'كولن كوستاريكي', nameEn: 'Costa Rican Colón', symbol: 'CRC', minorUnits: 2),
  IsoCurrency(code: 'CUP', nameAr: 'بيزو كوبي', nameEn: 'Cuban Peso', symbol: 'CUP', minorUnits: 2),
  IsoCurrency(code: 'CVE', nameAr: 'اسكودو الرأس الأخضر', nameEn: 'Cape Verdean Escudo', symbol: 'CVE', minorUnits: 2),
  IsoCurrency(code: 'CZK', nameAr: 'كرونة تشيكية', nameEn: 'Czech Koruna', symbol: 'CZK', minorUnits: 2),
  IsoCurrency(code: 'DJF', nameAr: 'فرنك جيبوتي', nameEn: 'Djiboutian Franc', symbol: 'DJF', minorUnits: 0),
  IsoCurrency(code: 'DKK', nameAr: 'كرونة دنماركية', nameEn: 'Danish Krone', symbol: 'DKK', minorUnits: 2),
  IsoCurrency(code: 'DOP', nameAr: 'بيزو الدومنيكان', nameEn: 'Dominican Peso', symbol: 'DOP', minorUnits: 2),
  IsoCurrency(code: 'DZD', nameAr: 'دينار جزائري', nameEn: 'Algerian Dinar', symbol: 'د.ج', minorUnits: 2, subunitAr: 'سنتيم'),
  IsoCurrency(code: 'EGP', nameAr: 'جنيه مصري', nameEn: 'Egyptian Pound', symbol: 'ج.م', minorUnits: 2, subunitAr: 'قرش'),
  IsoCurrency(code: 'ERN', nameAr: 'ناكفا أريتري', nameEn: 'Eritrean Nakfa', symbol: 'ERN', minorUnits: 2),
  IsoCurrency(code: 'ETB', nameAr: 'بير أثيوبي', nameEn: 'Ethiopian Birr', symbol: 'ETB', minorUnits: 2),
  IsoCurrency(code: 'EUR', nameAr: 'يورو', nameEn: 'Euro', symbol: '€', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'FJD', nameAr: 'دولار فيجي', nameEn: 'Fijian Dollar', symbol: 'FJD', minorUnits: 2),
  IsoCurrency(code: 'FKP', nameAr: 'جنيه جزر فوكلاند', nameEn: 'Falkland Islands Pound', symbol: 'FKP', minorUnits: 2),
  IsoCurrency(code: 'GBP', nameAr: 'جنيه إسترليني', nameEn: 'British Pound', symbol: '£', minorUnits: 2, subunitAr: 'بنس'),
  IsoCurrency(code: 'GEL', nameAr: 'لارى جورجي', nameEn: 'Georgian Lari', symbol: 'GEL', minorUnits: 2),
  IsoCurrency(code: 'GHS', nameAr: 'سيدي غانا', nameEn: 'Ghanaian Cedi', symbol: 'GHS', minorUnits: 2),
  IsoCurrency(code: 'GIP', nameAr: 'جنيه جبل طارق', nameEn: 'Gibraltar Pound', symbol: 'GIP', minorUnits: 2),
  IsoCurrency(code: 'GMD', nameAr: 'دلاسي غامبي', nameEn: 'Gambian Dalasi', symbol: 'GMD', minorUnits: 2),
  IsoCurrency(code: 'GNF', nameAr: 'فرنك غينيا', nameEn: 'Guinean Franc', symbol: 'GNF', minorUnits: 0),
  IsoCurrency(code: 'GTQ', nameAr: 'كوتزال غواتيمالا', nameEn: 'Guatemalan Quetzal', symbol: 'GTQ', minorUnits: 2),
  IsoCurrency(code: 'GYD', nameAr: 'دولار غيانا', nameEn: 'Guyanaese Dollar', symbol: 'GYD', minorUnits: 2),
  IsoCurrency(code: 'HKD', nameAr: 'دولار هونغ كونغ', nameEn: 'Hong Kong Dollar', symbol: '\$', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'HNL', nameAr: 'ليمبيرا هنداروس', nameEn: 'Honduran Lempira', symbol: 'HNL', minorUnits: 2),
  IsoCurrency(code: 'HTG', nameAr: 'جوردى هايتي', nameEn: 'Haitian Gourde', symbol: 'HTG', minorUnits: 2),
  IsoCurrency(code: 'HUF', nameAr: 'فورينت هنغاري', nameEn: 'Hungarian Forint', symbol: 'HUF', minorUnits: 2),
  IsoCurrency(code: 'IDR', nameAr: 'روبية إندونيسية', nameEn: 'Indonesian Rupiah', symbol: 'IDR', minorUnits: 2),
  IsoCurrency(code: 'ILS', nameAr: 'شيكل إسرائيلي جديد', nameEn: 'Israeli New Shekel', symbol: '₪', minorUnits: 2),
  IsoCurrency(code: 'INR', nameAr: 'روبية هندي', nameEn: 'Indian Rupee', symbol: '₹', minorUnits: 2, subunitAr: 'بيسة'),
  IsoCurrency(code: 'IQD', nameAr: 'دينار عراقي', nameEn: 'Iraqi Dinar', symbol: 'د.ع', minorUnits: 0, subunitAr: 'فلس'),
  IsoCurrency(code: 'IRR', nameAr: 'ريال إيراني', nameEn: 'Iranian Rial', symbol: 'ر.إ', minorUnits: 0),
  IsoCurrency(code: 'ISK', nameAr: 'كرونة أيسلندية', nameEn: 'Icelandic Króna', symbol: 'ISK', minorUnits: 0),
  IsoCurrency(code: 'JMD', nameAr: 'دولار جامايكي', nameEn: 'Jamaican Dollar', symbol: 'JMD', minorUnits: 2),
  IsoCurrency(code: 'JOD', nameAr: 'دينار أردني', nameEn: 'Jordanian Dinar', symbol: 'د.أ', minorUnits: 3, subunitAr: 'فلس'),
  IsoCurrency(code: 'JPY', nameAr: 'ين ياباني', nameEn: 'Japanese Yen', symbol: '¥', minorUnits: 0),
  IsoCurrency(code: 'KES', nameAr: 'شلن كينيي', nameEn: 'Kenyan Shilling', symbol: 'KES', minorUnits: 2),
  IsoCurrency(code: 'KGS', nameAr: 'سوم قيرغستاني', nameEn: 'Kyrgystani Som', symbol: 'KGS', minorUnits: 2),
  IsoCurrency(code: 'KHR', nameAr: 'رييال كمبودي', nameEn: 'Cambodian Riel', symbol: 'KHR', minorUnits: 2),
  IsoCurrency(code: 'KMF', nameAr: 'فرنك جزر القمر', nameEn: 'Comorian Franc', symbol: 'KMF', minorUnits: 0),
  IsoCurrency(code: 'KPW', nameAr: 'وون كوريا الشمالية', nameEn: 'North Korean Won', symbol: 'KPW', minorUnits: 0),
  IsoCurrency(code: 'KRW', nameAr: 'وون كوريا الجنوبية', nameEn: 'South Korean Won', symbol: '₩', minorUnits: 0),
  IsoCurrency(code: 'KWD', nameAr: 'دينار كويتي', nameEn: 'Kuwaiti Dinar', symbol: 'د.ك', minorUnits: 3, subunitAr: 'فلس'),
  IsoCurrency(code: 'KYD', nameAr: 'دولار جزر كيمن', nameEn: 'Cayman Islands Dollar', symbol: 'KYD', minorUnits: 2),
  IsoCurrency(code: 'KZT', nameAr: 'تينغ كازاخستاني', nameEn: 'Kazakhstani Tenge', symbol: 'KZT', minorUnits: 2),
  IsoCurrency(code: 'LAK', nameAr: 'كيب لاوسي', nameEn: 'Laotian Kip', symbol: 'LAK', minorUnits: 0),
  IsoCurrency(code: 'LBP', nameAr: 'جنيه لبناني', nameEn: 'Lebanese Pound', symbol: 'ل.ل', minorUnits: 0, subunitAr: 'قرش'),
  IsoCurrency(code: 'LKR', nameAr: 'روبية سريلانكية', nameEn: 'Sri Lankan Rupee', symbol: 'LKR', minorUnits: 2),
  IsoCurrency(code: 'LRD', nameAr: 'دولار ليبيري', nameEn: 'Liberian Dollar', symbol: 'LRD', minorUnits: 2),
  IsoCurrency(code: 'LSL', nameAr: 'لوتي ليسوتو', nameEn: 'Lesotho Loti', symbol: 'LSL', minorUnits: 2),
  IsoCurrency(code: 'LYD', nameAr: 'دينار ليبي', nameEn: 'Libyan Dinar', symbol: 'د.ل', minorUnits: 3, subunitAr: 'درهم'),
  IsoCurrency(code: 'MAD', nameAr: 'درهم مغربي', nameEn: 'Moroccan Dirham', symbol: 'د.م', minorUnits: 2, subunitAr: 'سنتيم'),
  IsoCurrency(code: 'MDL', nameAr: 'ليو مولدوفي', nameEn: 'Moldovan Leu', symbol: 'MDL', minorUnits: 2),
  IsoCurrency(code: 'MGA', nameAr: 'أرياري مدغشقر', nameEn: 'Malagasy Ariary', symbol: 'MGA', minorUnits: 0),
  IsoCurrency(code: 'MKD', nameAr: 'دينار مقدوني', nameEn: 'Macedonian Denar', symbol: 'MKD', minorUnits: 2),
  IsoCurrency(code: 'MMK', nameAr: 'كيات ميانمار', nameEn: 'Myanmar Kyat', symbol: 'MMK', minorUnits: 0),
  IsoCurrency(code: 'MNT', nameAr: 'توغروغ منغولي', nameEn: 'Mongolian Tugrik', symbol: 'MNT', minorUnits: 2),
  IsoCurrency(code: 'MOP', nameAr: 'باتاكا ماكاوي', nameEn: 'Macanese Pataca', symbol: 'MOP', minorUnits: 2),
  IsoCurrency(code: 'MRU', nameAr: 'أوقية موريتانية', nameEn: 'Mauritanian Ouguiya', symbol: 'أ.م', minorUnits: 2),
  IsoCurrency(code: 'MUR', nameAr: 'روبية موريشيوسية', nameEn: 'Mauritian Rupee', symbol: 'MUR', minorUnits: 2),
  IsoCurrency(code: 'MVR', nameAr: 'روفيه جزر المالديف', nameEn: 'Maldivian Rufiyaa', symbol: 'MVR', minorUnits: 2),
  IsoCurrency(code: 'MWK', nameAr: 'كواشا مالاوي', nameEn: 'Malawian Kwacha', symbol: 'MWK', minorUnits: 2),
  IsoCurrency(code: 'MXN', nameAr: 'بيزو مكسيكي', nameEn: 'Mexican Peso', symbol: '\$', minorUnits: 2),
  IsoCurrency(code: 'MYR', nameAr: 'رينغيت ماليزي', nameEn: 'Malaysian Ringgit', symbol: 'MYR', minorUnits: 2),
  IsoCurrency(code: 'MZN', nameAr: 'متكال موزمبيقي', nameEn: 'Mozambican Metical', symbol: 'MZN', minorUnits: 2),
  IsoCurrency(code: 'NAD', nameAr: 'دولار ناميبي', nameEn: 'Namibian Dollar', symbol: 'NAD', minorUnits: 2),
  IsoCurrency(code: 'NGN', nameAr: 'نايرا نيجيري', nameEn: 'Nigerian Naira', symbol: 'NGN', minorUnits: 2),
  IsoCurrency(code: 'NIO', nameAr: 'قرطبة نيكاراغوا', nameEn: 'Nicaraguan Córdoba', symbol: 'NIO', minorUnits: 2),
  IsoCurrency(code: 'NOK', nameAr: 'كرونة نرويجية', nameEn: 'Norwegian Krone', symbol: 'NOK', minorUnits: 2),
  IsoCurrency(code: 'NPR', nameAr: 'روبية نيبالي', nameEn: 'Nepalese Rupee', symbol: 'NPR', minorUnits: 2),
  IsoCurrency(code: 'NZD', nameAr: 'دولار نيوزيلندي', nameEn: 'New Zealand Dollar', symbol: '\$', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'OMR', nameAr: 'ريال عماني', nameEn: 'Omani Rial', symbol: 'ر.ع', minorUnits: 3, subunitAr: 'بيسة'),
  IsoCurrency(code: 'PAB', nameAr: 'بالبوا بنمي', nameEn: 'Panamanian Balboa', symbol: 'PAB', minorUnits: 2),
  IsoCurrency(code: 'PEN', nameAr: 'سول بيروفي', nameEn: 'Peruvian Sol', symbol: 'PEN', minorUnits: 2),
  IsoCurrency(code: 'PGK', nameAr: 'كينا بابوا غينيا الجديدة', nameEn: 'Papua New Guinean Kina', symbol: 'PGK', minorUnits: 2),
  IsoCurrency(code: 'PHP', nameAr: 'بيزو فلبيني', nameEn: 'Philippine Peso', symbol: 'PHP', minorUnits: 2),
  IsoCurrency(code: 'PKR', nameAr: 'روبية باكستاني', nameEn: 'Pakistani Rupee', symbol: 'PKR', minorUnits: 2, subunitAr: 'بيسة'),
  IsoCurrency(code: 'PLN', nameAr: 'زلوتي بولندي', nameEn: 'Polish Zloty', symbol: 'PLN', minorUnits: 2),
  IsoCurrency(code: 'PYG', nameAr: 'غواراني باراغواي', nameEn: 'Paraguayan Guarani', symbol: 'PYG', minorUnits: 0),
  IsoCurrency(code: 'QAR', nameAr: 'ريال قطري', nameEn: 'Qatari Riyal', symbol: 'ر.ق', minorUnits: 2, subunitAr: 'درهم'),
  IsoCurrency(code: 'RON', nameAr: 'ليو روماني', nameEn: 'Romanian Leu', symbol: 'RON', minorUnits: 2),
  IsoCurrency(code: 'RSD', nameAr: 'دينار صربي', nameEn: 'Serbian Dinar', symbol: 'RSD', minorUnits: 0),
  IsoCurrency(code: 'RUB', nameAr: 'روبل روسي', nameEn: 'Russian Ruble', symbol: 'RUB', minorUnits: 2),
  IsoCurrency(code: 'RWF', nameAr: 'فرنك رواندي', nameEn: 'Rwandan Franc', symbol: 'RWF', minorUnits: 0),
  IsoCurrency(code: 'SAR', nameAr: 'ريال سعودي', nameEn: 'Saudi Riyal', symbol: 'ر.س', minorUnits: 2, subunitAr: 'هللة'),
  IsoCurrency(code: 'SBD', nameAr: 'دولار جزر سليمان', nameEn: 'Solomon Islands Dollar', symbol: 'SBD', minorUnits: 2),
  IsoCurrency(code: 'SCR', nameAr: 'روبية سيشيلية', nameEn: 'Seychellois Rupee', symbol: 'SCR', minorUnits: 2),
  IsoCurrency(code: 'SDG', nameAr: 'جنيه سوداني', nameEn: 'Sudanese Pound', symbol: 'ج.س', minorUnits: 2, subunitAr: 'قرش'),
  IsoCurrency(code: 'SEK', nameAr: 'كرونة سويدية', nameEn: 'Swedish Krona', symbol: 'SEK', minorUnits: 2),
  IsoCurrency(code: 'SGD', nameAr: 'دولار سنغافوري', nameEn: 'Singapore Dollar', symbol: 'SGD', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'SHP', nameAr: 'جنيه سانت هيلين', nameEn: 'St. Helena Pound', symbol: 'SHP', minorUnits: 2),
  IsoCurrency(code: 'SLE', nameAr: 'ليون سيراليوني', nameEn: 'Sierra Leonean Leone', symbol: 'SLE', minorUnits: 2),
  IsoCurrency(code: 'SOS', nameAr: 'شلن صومالي', nameEn: 'Somali Shilling', symbol: 'SOS', minorUnits: 0),
  IsoCurrency(code: 'SRD', nameAr: 'دولار سورينامي', nameEn: 'Surinamese Dollar', symbol: 'SRD', minorUnits: 2),
  IsoCurrency(code: 'SSP', nameAr: 'جنيه جنوب السودان', nameEn: 'South Sudanese Pound', symbol: 'SSP', minorUnits: 2),
  IsoCurrency(code: 'STN', nameAr: 'دوبرا ساو تومي وبرينسيبي', nameEn: 'São Tomé & Príncipe Dobra', symbol: 'STN', minorUnits: 2),
  IsoCurrency(code: 'SYP', nameAr: 'ليرة سورية', nameEn: 'Syrian Pound', symbol: 'ل.س', minorUnits: 2, subunitAr: 'قرش'),
  IsoCurrency(code: 'SZL', nameAr: 'ليلانجيني سوازيلندي', nameEn: 'Swazi Lilangeni', symbol: 'SZL', minorUnits: 2),
  IsoCurrency(code: 'THB', nameAr: 'باخت تايلاندي', nameEn: 'Thai Baht', symbol: '฿', minorUnits: 2),
  IsoCurrency(code: 'TJS', nameAr: 'سوموني طاجيكستاني', nameEn: 'Tajikistani Somoni', symbol: 'TJS', minorUnits: 2),
  IsoCurrency(code: 'TMT', nameAr: 'مانات تركمانستان', nameEn: 'Turkmenistani Manat', symbol: 'TMT', minorUnits: 2),
  IsoCurrency(code: 'TND', nameAr: 'دينار تونسي', nameEn: 'Tunisian Dinar', symbol: 'د.ت', minorUnits: 3, subunitAr: 'ملّيم'),
  IsoCurrency(code: 'TOP', nameAr: 'بانغا تونغا', nameEn: 'Tongan Paʻanga', symbol: 'TOP', minorUnits: 2),
  IsoCurrency(code: 'TRY', nameAr: 'ليرة تركية', nameEn: 'Turkish Lira', symbol: 'TRY', minorUnits: 2, subunitAr: 'كوروش'),
  IsoCurrency(code: 'TTD', nameAr: 'دولار ترينداد وتوباغو', nameEn: 'Trinidad & Tobago Dollar', symbol: 'TTD', minorUnits: 2),
  IsoCurrency(code: 'TWD', nameAr: 'دولار تايواني', nameEn: 'New Taiwan Dollar', symbol: '\$', minorUnits: 2),
  IsoCurrency(code: 'TZS', nameAr: 'شلن تنزاني', nameEn: 'Tanzanian Shilling', symbol: 'TZS', minorUnits: 2),
  IsoCurrency(code: 'UAH', nameAr: 'هريفنيا أوكراني', nameEn: 'Ukrainian Hryvnia', symbol: 'UAH', minorUnits: 2),
  IsoCurrency(code: 'UGX', nameAr: 'شلن أوغندي', nameEn: 'Ugandan Shilling', symbol: 'UGX', minorUnits: 0),
  IsoCurrency(code: 'USD', nameAr: 'دولار أمريكي', nameEn: 'US Dollar', symbol: '\$', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'UYU', nameAr: 'بيزو اوروغواي', nameEn: 'Uruguayan Peso', symbol: 'UYU', minorUnits: 2),
  IsoCurrency(code: 'UZS', nameAr: 'سوم أوزبكستاني', nameEn: 'Uzbekistani Som', symbol: 'UZS', minorUnits: 2),
  IsoCurrency(code: 'VED', nameAr: 'VED', nameEn: 'Bolívar Soberano', symbol: 'VED', minorUnits: 2),
  IsoCurrency(code: 'VES', nameAr: 'بوليفار فنزويلي', nameEn: 'Venezuelan Bolívar', symbol: 'VES', minorUnits: 2),
  IsoCurrency(code: 'VND', nameAr: 'دونج فيتنامي', nameEn: 'Vietnamese Dong', symbol: '₫', minorUnits: 0),
  IsoCurrency(code: 'VUV', nameAr: 'فاتو فانواتو', nameEn: 'Vanuatu Vatu', symbol: 'VUV', minorUnits: 0),
  IsoCurrency(code: 'WST', nameAr: 'تالا ساموا', nameEn: 'Samoan Tala', symbol: 'WST', minorUnits: 2),
  IsoCurrency(code: 'XAF', nameAr: 'فرنك وسط أفريقي', nameEn: 'Central African CFA Franc', symbol: 'FCFA', minorUnits: 0),
  IsoCurrency(code: 'XCD', nameAr: 'دولار شرق الكاريبي', nameEn: 'East Caribbean Dollar', symbol: '\$', minorUnits: 2),
  IsoCurrency(code: 'XOF', nameAr: 'فرنك غرب أفريقي', nameEn: 'West African CFA Franc', symbol: ' CFA', minorUnits: 0),
  IsoCurrency(code: 'XPF', nameAr: 'فرنك سي إف بي', nameEn: 'CFP Franc', symbol: 'CFPF', minorUnits: 0),
  IsoCurrency(code: 'YER', nameAr: 'ريال يمني', nameEn: 'Yemeni Rial', symbol: 'ر.ي', minorUnits: 0, subunitAr: 'فلس'),
  IsoCurrency(code: 'ZAR', nameAr: 'راند جنوب أفريقيا', nameEn: 'South African Rand', symbol: 'ZAR', minorUnits: 2, subunitAr: 'سنت'),
  IsoCurrency(code: 'ZMW', nameAr: 'كواشا زامبي', nameEn: 'Zambian Kwacha', symbol: 'ZMW', minorUnits: 2),
  IsoCurrency(code: 'ZWG', nameAr: 'ZWG', nameEn: 'Zimbabwean Gold', symbol: 'ZWG', minorUnits: 2),
];
