/// الأطراف في دِقَّة — منطق نقي حصراً بلا Flutter ولا Drift (F-010، 07 §1.8).
///
/// القرارات الحاكمة الموثقة (README-v2.01 §3):
/// - D-062: الأساس في بطاقة الأطراف هو الرقم — به ترتبط كل المعاملات
///   لا الاسم، فقد يعدل.
/// - D-063: الرقم يخزن نصاً بأصفاره كما كُتب، والتفرد بعد نزع الأصفار
///   الزائدة («0053» و«53» طرف واحد لا اثنان)، وترتيب رقمي ذكي
///   (1، 2، 10 لا 1، 10، 2)، وتوليد آلي مقترح قابل للتعديل قبل الحفظ
///   حصراً، ولا تعديل للرقم بعد الحفظ.
/// - D-064: البحث خانة واحدة جامعة (الاسم والرقم والهاتف) بكلمات متفرقة
///   تلتقي بأي ترتيب، وتطبيع عربي في البحث فقط — المخزون لا يتغير بايتاً.
/// - D-065: منع تكرار الاسم المطابق حرفياً منعاً تاماً — المقارنة حرفية
///   بلا أي تطبيع، فالتطبيع للبحث حصراً.
/// - D-066: عملة الطرف لا تخزن فارغة أبداً — معبأة بالافتراضية دوماً.
///
/// السيناريوهات المعتمدة من المالك بلفظه «معتمدة» (س17): س-29..س-35 (06 §1-ب).

// ── نزاهة الإدخال الدنيا للنصوص الحرة (D-170 — س56 بكلمة المالك) ────

/// تجريد علامات العرض غير المرئية من الاسم الحر (D-170): العرض الصفري
/// (ZWSP/ZWNJ/ZWJ) وعلامات الاتجاه (LRM/RLM وأقرانها BOM) تتسرب لصقاً
/// من النسخ الخارجي (واتساب/الويب) فتخفي تكرار الأسماء وتكسر البحث
/// خفيةً — وهي علامات لا يراها المستخدم أصلاً فالمخزَّن يطابق المرئي
/// المفهوم (نقيض السحر الخفي لا سحره). ثم تُقلَّم الأطراف. مشتركة بين
/// أسماء الأطراف والأصناف والوحدات (D-170).
String sanitizeFreeName(String raw) => raw
    .replaceAll(RegExp('[\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]'), '')
    .trim();

/// محارف التحكم (C0/C1 وحذف) في الاسم الحر مرفوضة لا تُجرد (D-170):
/// لا تأتي إلا بخطأ إدخال أو إبراق خفي — والرفض برسالة عربية أوضح من
/// الصمت الذي يخفي التلف.
bool freeNameHasControlChars(String name) =>
    RegExp(r'[\x00-\x1F\x7F\u0080-\u009F]').hasMatch(name);

/// القائمة البيضاء الموحدة للرموز القابلة للطباعة والبحث — منبع D-171
/// (كود الصنف) وD-174 (رقم الطرف) معاً: حروف بأي لغة (`\p{L}`) وأرقام
/// (`\p{N}`) و `- _ .` حصراً — بلا فراغ بحسم المالك (س64) ولا فاصل
/// مسار (`/` علّته حية موثقة س-154/D-152) ولا محارف عرضية. تعيش هنا
/// في party.dart لأن item.dart يستوردها أصلاً فلا دورة استيراد —
/// ووحدة القائمة بين الحقلين مضمونة بتقاسم المنبع لا بمضاعفته.
bool isValidCodeToken(String raw) =>
    RegExp(r'^[\p{L}\p{N}_.\-]+$', unicode: true).hasMatch(raw);

/// قائمة بيضاء رقم الطرف (D-174 — الدفعة 20): قائمة D-171 ذاتها حرفياً
/// بحكم D-174 — والكلمات المختصرة داخل الأكواد تُفصل بالشرطة وما
/// جاورها («خال-53» لا «خال 53»).
bool isValidPartyNumber(String raw) => isValidCodeToken(raw);

/// اسم طرف يحمل محارف تحكم خفية (D-170) — مرفوض.
class PartyNameControlChars extends PartyValidationError {
  const PartyNameControlChars();
}

/// نزع الأصفار الزائدة (D-063): مفتاح التفرد الرقمي.
///
/// «0053» و«53» يعودان بالمفتاح نفسه؛ الفراغات الطرفية تُقلَّم أولاً؛
/// الصفر وحده («000») يبقى «0»؛ وغير الرقمي يعود كما هو بلا مساس.
String partyNumberKey(String raw) {
  final s = raw.trim();
  var i = 0;
  while (i < s.length - 1 && s.codeUnitAt(i) == 0x30) {
    i++;
  }
  return s.substring(i);
}

/// هل الرقم (بعد نزع الأصفار الزائدة) أرقاماً صرفاً؟
///
/// يحدد من يشارك في الترتيب العددي والتوليد الآلي؛ غير الرقمي («A-12»)
/// طرف مشروع لكنه خارج التسلسل العددي.
bool isNumericPartyNumber(String raw) {
  final s = partyNumberKey(raw);
  if (s.isEmpty) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

/// الترتيب الرقمي الذكي (D-063/س-29): 1، 2، 10 لا 1، 10، 2.
///
/// الرقما صرفاً يُقارنان عددياً بمقارنة «الطول ثم المعجمية» — دقيقة
/// للأعداد الصحيحة غير السالبة بأي حجم بلا تحويل فلا فائض؛ وغير الرقمي
/// يلحق بعد الرقمي بترتيبه المعجمي.
int comparePartyNumbers(String a, String b) {
  final ka = partyNumberKey(a);
  final kb = partyNumberKey(b);
  final na = isNumericPartyNumber(ka);
  final nb = isNumericPartyNumber(kb);
  if (na && nb) {
    if (ka.length != kb.length) return ka.length - kb.length;
    return ka.compareTo(kb);
  }
  if (na) return -1;
  if (nb) return 1;
  return ka.compareTo(kb);
}

/// زيادة رقم صرف بمقدار واحد على السلسلة النصية نفسها — بلا تحويل لعدد
/// صحيح فلا فائض مهما طال الرقم («999…9» يزيد موضعاً).
String _incrementNumericString(String s) {
  // نسخة قابلة للكتابة — codeUnits تعيد قائمة غير قابلة للتعديل (علّة CI
  // 2026-10-29: «Cannot modify an unmodifiable list» كان يفشل التوليد كله).
  final digits = List<int>.of(s.codeUnits);
  var i = digits.length - 1;
  while (i >= 0) {
    if (digits[i] < 0x39) {
      digits[i]++;
      return String.fromCharCodes(digits);
    }
    digits[i] = 0x30;
    i--;
  }
  return '1${String.fromCharCodes(digits)}';
}

/// التوليد الآلي للرقم (D-063/س-29): التالي في التسلسل العددي للأطراف
/// القائمة، معبأ بأصفار حتى أربعة مواضع على الأقل (نمط «0007» في س-29)،
/// وهو مقترح قابل للتعديل قبل الحفظ حصراً.
///
/// بلا أطراف رقمية قائمة يبدأ التسلسل من «0001»؛ وغير الرقمي لا يشارك
/// في حساب التالي.
String suggestNextPartyNumber(Iterable<String> existingNumbers) {
  String? maxKey;
  for (final raw in existingNumbers) {
    final k = partyNumberKey(raw);
    if (!isNumericPartyNumber(k)) continue;
    if (maxKey == null || comparePartyNumbers(k, maxKey) > 0) {
      maxKey = k;
    }
  }
  if (maxKey == null) return '0001';
  final next = _incrementNumericString(maxKey);
  return next.length >= 4 ? next : next.padLeft(4, '0');
}

/// التطبيع العربي للبحث حصراً (D-064): الهمزات (أ إ آ ٱ ← ا) والى ← ي
/// والتاء المربوطة ← هاء، ونزع التشكيل والتطويل، وتوحيد اللاتيني الصغير.
///
/// الدالة نقية: المدخل لا يتغير بايتاً وتُعاد سلسلة جديدة — «المخزون
/// لا يتغير بايتاً» حرفاً من س-31. همزتا ؤ وئ تُركتا كما هما لأن نص
/// القرار حصر التطبيع في (أ/إ/آ) وى/ي والتاء والتشكيل.
String normalizeArabicForSearch(String input) {
  final buffer = StringBuffer();
  for (final ch in input.runes) {
    // التشكيل: التنوين والشدة والسكون (064B-0652) والألف الخنجرية (0670)
    // والتطويل (0640) — تُسقط جميعاً.
    if ((ch >= 0x064B && ch <= 0x0652) || ch == 0x0670 || ch == 0x0640) {
      continue;
    }
    switch (ch) {
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
      case 0x0671: // ٱ
        buffer.writeCharCode(0x0627); // ا
        break;
      case 0x0649: // ى
        buffer.writeCharCode(0x064A); // ي
        break;
      case 0x0629: // ة
        buffer.writeCharCode(0x0647); // ه
        break;
      default:
        buffer.writeCharCode(ch);
    }
  }
  return buffer.toString().toLowerCase();
}

/// حقول الطرف القابلة للبحث الجامع (D-064/س-31): الاسم والرقم والهاتف.
class PartySearchFields {
  final String name;
  final String number;
  final String phone;

  const PartySearchFields({
    required this.name,
    required this.number,
    this.phone = '',
  });

  /// مطابقة «كلمات متفرقة تلتقي»: كل كلمة مكتوبة تجد موضعها في الاسم
  /// أو الرقم أو الهاتف بأي ترتيب — «خال 53» تجيء بـ«محمد الخالدي (0053)».
  ///
  /// كل كلمة تُطابَع بعد التطبيع في كل حقل على حدة (لا على ضمها) كي لا
  /// تلتقط مطابقة زائفة تعبر حدود الحقول. الخانة الفارغة تجيء بالجميع.
  bool matchesQuery(String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .map(normalizeArabicForSearch)
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return true;
    final nameN = normalizeArabicForSearch(name);
    final numberN = normalizeArabicForSearch(number);
    final phoneN = normalizeArabicForSearch(phone);
    for (final token in tokens) {
      final hit =
          nameN.contains(token) || numberN.contains(token) || phoneN.contains(token);
      if (!hit) return false;
    }
    return true;
  }
}

/// نوع الطرف (05 §3.1): عميل أو مورد أو الاثنان معاً — الطرف المزدوج
/// صف مرجعي واحد يخدم دورتي البيع والشراء (س-30).
enum PartyKind {
  customer('customer', 'عميل'),
  supplier('supplier', 'مورد'),
  both('both', 'عميل ومورد معاً');

  final String storageValue;
  final String label;

  const PartyKind(this.storageValue, this.label);

  static PartyKind fromStorage(String value) {
    for (final k in PartyKind.values) {
      if (k.storageValue == value) return k;
    }
    throw ArgumentError('نوع طرف غير معروف: $value');
  }
}

/// صيغة العرض المعتمدة في القوائم (D-065/س-29): «الاسم (الرقم)».
String partyDisplayLabel(String name, String number) => '$name ($number)';

/// صورة طرف قائم للتحقق والفهرسة — بلا أي اعتماد تخزين أو واجهة.
class ExistingParty {
  final int id;
  final String number;
  final String name;
  final bool isActive;

  const ExistingParty({
    required this.id,
    required this.number,
    required this.name,
    required this.isActive,
  });

  /// مفتاح التفرد الرقمي بعد نزع الأصفار الزائدة (D-063).
  String get numberKey => partyNumberKey(number);

  /// العرض المعتمد «الاسم (الرقم)» — تحمله رسائل الرفض تري صاحبها (س-29).
  String get displayLabel => partyDisplayLabel(name, number);
}

/// مسودة طرف كما تخرج من نموذج الإدخال قبل التحقق — قيم خام غير مقلمة.
class PartyDraft {
  final String number;
  final String name;
  final String phone;
  final String address;
  final PartyKind kind;

  /// معرّف العملة — معبأ مسبقاً بالعملة الأساسية ولا يصل التخزين صفراً
  /// أو سالباً (D-066). القيمة 1 هي العملة الأساسية (D-017) حتى تُبنى
  /// جدول العملات في دفعاتها — الاصطلاح نفسه المعتمد لـ price_currency_id
  /// في الأصناف.
  final int currencyId;

  /// حد ائتمان اختياري بوحدات صغرى (F-023/س-34): null فراغ مشروع معناه
  /// مقصود «بلا سقف» — لا فراغ العملة الممنوع (D-066).
  final int? creditLimitBaseMinor;

  const PartyDraft({
    required this.number,
    required this.name,
    this.phone = '',
    this.address = '',
    required this.kind,
    this.currencyId = 1,
    this.creditLimitBaseMinor,
  });
}

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة: الواجهة وحدها
/// تقرر الصياغة المعروضة (فصل المجال عن العرض).
sealed class PartyValidationError {
  const PartyValidationError();
}

/// بلا اسم — الاسم إلزامي وحده (س-29).
class PartyNameRequired extends PartyValidationError {
  const PartyNameRequired();
}

/// رقم فارغ — مستحيل عملياً بالتوليد الآلي وحارس تكاملي (س-29).
class PartyNumberRequired extends PartyValidationError {
  const PartyNumberRequired();
}

/// رقم مكرر بعد نزع الأصفار الزائدة (D-063) — يحمل مفتاح التكرار وعرض
/// الطرف القائم: «الرقم 53 مستخدم للطرف: محمد الخالدي (0053)».
class PartyNumberTaken extends PartyValidationError {
  final String duplicateKey;
  final String existingLabel;

  const PartyNumberTaken(this.duplicateKey, this.existingLabel);
}

/// اسم مطابق حرفياً لطرف قائم (D-065 — منع لا تنبيه، عدول موثق عن س14).
class PartyNameTaken extends PartyValidationError {
  final String existingLabel;

  const PartyNameTaken(this.existingLabel);
}

/// عملة تصل فارغة أو غير صالحة (D-066: لا فراغ للعملة بل تعبئة الافتراضية).
class PartyCurrencyMissing extends PartyValidationError {
  const PartyCurrencyMissing();
}

/// رقم طرف خارج القائمة البيضاء (D-174 — الدفعة 20) — يحمل الرقم
/// المرفوض ليُعرض في رسالة الواجهة (نمط ItemSkuInvalidFormat).
class PartyNumberInvalidFormat extends PartyValidationError {
  final String number;

  const PartyNumberInvalidFormat(this.number);
}

/// حد ائتمان مُدخل غير صالح — إن أُدخل فيجب أن يكون موجباً؛ والفراغ
/// «بلا سقف» مشروع (س-34).
class PartyCreditLimitInvalid extends PartyValidationError {
  const PartyCreditLimitInvalid();
}

/// فهرس التفرد للأطراف القائمة: بالمفتاح الرقمي بعد نزع الأصفار (D-063)
/// وبالاسم الحرفي بعد تقليم الفراغات الطرفية حصراً بلا أي تطبيع (D-065).
class PartyUniquenessIndex {
  final Map<String, ExistingParty> _byNumberKey;
  final Map<String, ExistingParty> _byLiteralName;

  const PartyUniquenessIndex._(this._byNumberKey, this._byLiteralName);

  factory PartyUniquenessIndex.build(Iterable<ExistingParty> parties) {
    final byNumber = <String, ExistingParty>{};
    final byName = <String, ExistingParty>{};
    for (final party in parties) {
      final nameKey = party.name.trim();
      // أول طرف يفوز بالفهرسة — الفهرس أداة تحقق لا إصلاح تاريخ.
      byNumber.putIfAbsent(party.numberKey, () => party);
      if (nameKey.isNotEmpty) byName.putIfAbsent(nameKey, () => party);
    }
    return PartyUniquenessIndex._(byNumber, byName);
  }

  ExistingParty? byNumberKey(String rawNumber) =>
      _byNumberKey[partyNumberKey(rawNumber)];

  ExistingParty? byLiteralName(String rawName) => _byLiteralName[rawName.trim()];
}

/// التحقق قبل الحفظ (س-29/س-35) — يعيد قائمة الأخطاء (فارغة = سليم).
///
/// - [excludePartyId] للتعديل: يستثني الطرف من فحص التكرار ضد نفسه (س-32)،
///   والرقم لا يعدل بعد الحفظ أصلاً (D-063) فمصدره في التعديل يظل كما هو.
/// - المعطل يبقى في الفهرس: التعطيل لا يحذف أصلاً (س-33) فاسمه ورقمه
///   محجوزان ما دام الصف حياً.
List<PartyValidationError> validatePartyDraft(
  PartyDraft draft, {
  required PartyUniquenessIndex existing,
  int? excludePartyId,
}) {
  final errors = <PartyValidationError>[];
  final name = sanitizeFreeName(draft.name);
  // النظافة D-170 على حدود حقل الرقم أيضاً (D-174): العلامات غير
  // المرئية تُجرد لأن المستخدم لا يراها أصلاً، ثم يقيد الباقي المرئي
  // بقائمة البيضاء — طهّر عند الحدود لا حجب عند الباب.
  final number = sanitizeFreeName(draft.number);

  if (name.isEmpty) errors.add(const PartyNameRequired());
  if (name.isNotEmpty && freeNameHasControlChars(name)) {
    errors.add(const PartyNameControlChars());
  }
  if (number.isEmpty) errors.add(const PartyNumberRequired());
  if (draft.currencyId <= 0) errors.add(const PartyCurrencyMissing());
  final credit = draft.creditLimitBaseMinor;
  if (credit != null && credit <= 0) {
    errors.add(const PartyCreditLimitInvalid());
  }

  if (number.isNotEmpty) {
    final holder = existing.byNumberKey(number);
    // D-174: القائمة البيضاء تُفرض على الرقم الجديد أو المتغير حصراً —
    // والرقم القائم غير المتغير يمر كما هو (الاستثناء الذاتي نمط D-153)
    // فلا يُحبس تعديلُ طرف قديم برقمٍ ما قبل D-174؛ وإن غيّره فالرقم
    // الجديد بقواعد القائمة كاملة.
    final unchangedSelf = holder != null && holder.id == excludePartyId;
    if (!unchangedSelf && !isValidPartyNumber(number)) {
      errors.add(PartyNumberInvalidFormat(number));
    }
    if (holder != null && holder.id != excludePartyId) {
      errors.add(PartyNumberTaken(partyNumberKey(number), holder.displayLabel));
    }
  }
  if (name.isNotEmpty) {
    final holder = existing.byLiteralName(name);
    if (holder != null && holder.id != excludePartyId) {
      errors.add(PartyNameTaken(holder.displayLabel));
    }
  }
  return errors;
}
