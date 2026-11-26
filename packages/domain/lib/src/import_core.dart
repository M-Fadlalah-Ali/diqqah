/// استيراد البيانات — النواة النقية (D-208/§25) — النواة (الدفعة الأولى
/// من ثلاث) ثم أرصدة أول المدة (الدفعة الثانية: الوحدتان 4 و5 — س141
/// بقرار د-1: المقابل 332 لا 3999، ود-6: بلا عمود مقابل بالملف).
///
/// عقد الدفعة الموثق (09 §25 — س133، بقرارات د-1..د-9):
/// - **القوالب (§25.4)**: CSV بترميز UTF-8 حصراً (يُبتلع BOM إن وُجد —
///   مرآة F-166 «ما نصدّره هو ما نستورده»)، لا xlsx. ترويسة القالب
///   (`dq-import:<كود>,<إصدار>`) تعرّفه فتُرفض «القالب غير المعروف»
///   كخطأ طبقة الملف — تأمين مستقبلي رخيص. أعمدة ثابتة بالكامل في v1 —
///   عمود العملة دائم (فراغه = SYP) ولا ربط أعمدة ولا تخمين تلقائي
///   إطلاقاً.
/// - **الفاصل (د-5)**: فحص بنيوي مرسى على عدد أعمدة القالب المعروف —
///   فاصل واحد حصراً («,» أو «؛») يطابق العدد بكل الصفوف؛ فإن انطبق
///   كلاهما أو لا منهما: رفض بتوجيه عربي. عند القراءة بالمنقوطة
///   `semicolonUsed` فيُعرض إشعار صريح دائم بالمعاينة «اكتُشف فاصل
///   منقوطة، قُرئ به» ويُسجل الفاصل بحدث الاستيراد.
/// - **الترميز صارم**: ملف ليس UTF-8 سليماً يُرفض برسالة إنقاذ عربية —
///   كشف الترميز وتحويله تخمينُ معنى مرفوض.
/// - **التحقق ثلاث طبقات (§25.5)**: فحص الملف (ترميز/قالب/فاصل) ← فحص
///   الصف (إلزامي/صيغة) ← فحص الدفعة (تكرار داخلي/مرجع مفقود) —
///   و«كل-أو-لا شيء»: أي خطأ يمنع الاعتماد كله، ولا كتابة جزئية
///   (07 §2.4). تقرير الأخطاء: رقم الصف + العمود + القيمة + رمز DQ +
///   وصف عربي + إجراء مقترح، قابل للتنزيل CSV.
/// - **الحد**: 10,000 صف لكل وحدة — تحذير زمني فوق 5,000 ورفض صريح
///   فوق 10,000 بالرقم الفعلي والحد واقتراح التقسيم.
/// - **الأسعار بوحدات بشرية** تُحوَّل إلى minor بالمجال (المحور المُلزم:
///   لا أرقام مكبَّرة على المستخدم) — بلا كسور عائمة: تحليل بنيوي صارم
///   لعدد خانات الكسر ورياضة أعداد صحيحة حصراً (عرف money.dart).
/// - **السياسة (§25.3.2)**: «إضافة جديد» (افتراضي — الموجود يُتخطى
///   والجديد يُنشأ) أو «تحديث الموجود» — **وصفيّات فقط في v1 (د-2)**:
///   الاسم والسعر حصراً؛ وما لا يُحدَّث (نوع الطرف وعملته وحد ائتمانه
///   ووحدة الصنف القائم) يُعرض فرقاً غير مُحدَّث بسبيه لا سحراً صامتاً.
///   «التكرار داخل الملف نفسه خطأ فادح — رفض كلي».
///
/// هذا الملف نقية حصراً: بلا Flutter ولا Drift ولا قاعدة (F-010،
/// 07 §1.8) — الفهارس القائمة (أطراف/أصناف/وحدات) ومرجع العملات
/// تُحقن من التخزين، فالاختبار بلا قاعدة والواجهة بلا تكرار.
library;

import 'dart:convert' show utf8;

import 'csv_export.dart';
import 'currencies.dart'
    show displayRateToBase, fxRateScaleConst, normalizeCurrencyCode;
import 'item.dart';
import 'journal.dart'
    show PeriodInfo, findPeriodForDate, isValidIsoDate;
import 'party.dart';

// ═══════════════════════════════════════════════════════════════
// القوالب — أعمدة ثابتة بالكامل في v1 (§25.4)
// ═══════════════════════════════════════════════════════════════

/// هويات القوالب المدعومة — النواة (الأطراف والأصناف — §25.11 الوحدتان
/// 1 و2) ثم أرصدة أول المدة بدفعتها الثانية (الوحدتان 4 و5 — س141)
/// ثم كميات المخزون الافتتاحية بتشطيب الخط (الوحدة 3 — س142).
enum ImportTemplateId {
  parties,
  items,
  partyBalances,
  openingFull,
  openingQty,
}

/// عمود قالب ثابت: مفتاحه البنيوي وعنوانه العربي كما يراه المستخدم.
class ImportColumnSpec {
  final String key;
  final String label;

  const ImportColumnSpec(this.key, this.label);
}

/// تعريف قالب استيراد: كوده بإرويسته وإصداره وأعمدته الثابتة.
class ImportTemplate {
  final ImportTemplateId id;

  /// كود القالب بإرويسة الملف (`dq-import:<code>,<version>`).
  final String code;

  /// إصدار القالب — يرفض الملف ذا الإصدار المخالف (تأمين مستقبلي).
  final int version;

  /// العنوان العربي للقالب كما يُعرض.
  final String label;

  final List<ImportColumnSpec> columns;

  const ImportTemplate({
    required this.id,
    required this.code,
    required this.version,
    required this.label,
    required this.columns,
  });

  /// عدد الأعمدة الثابتة — مرساة الفحص البنيوي للفاصل (د-5).
  int get columnCount => columns.length;

  /// سطر الترويسة كما يُكتب أول الملف.
  String get markerLine => 'dq-import:$code,$version';
}

/// سجل القوالب — المرجع الوحيد لتعريفها (سلطة الترقيم بنمط error_codes).
const List<ImportTemplate> importTemplates = [
  ImportTemplate(
    id: ImportTemplateId.parties,
    code: 'parties',
    version: 1,
    label: 'الأطراف',
    columns: [
      ImportColumnSpec('code', 'الكود'),
      ImportColumnSpec('name', 'الاسم'),
      ImportColumnSpec('kind', 'النوع'),
      ImportColumnSpec('currency', 'العملة'),
      ImportColumnSpec('credit_limit', 'حد الائتمان'),
    ],
  ),
  ImportTemplate(
    id: ImportTemplateId.items,
    code: 'items',
    version: 1,
    label: 'الأصناف',
    columns: [
      ImportColumnSpec('sku', 'كود الصنف'),
      ImportColumnSpec('name', 'الاسم'),
      ImportColumnSpec('unit', 'الوحدة'),
      ImportColumnSpec('price_currency', 'عملة السعر'),
      ImportColumnSpec('purchase_price', 'سعر الشراء'),
      ImportColumnSpec('sale_price', 'سعر البيع'),
    ],
  ),
  // س141 (الدفعة الثانية — §25.2 الوحدتان 4 و5): أرصدة الذمم ستة
  // أعمدة (لا عمود مقابل — د-6: 332 يولَّد آلياً) والأرصدة الكاملة
  // تسعة بعمود القسم (الذمم/المخزون/النقد) يحدد معاني الأعمدة بلا
  // تخمين (د-2/§25.4).
  ImportTemplate(
    id: ImportTemplateId.partyBalances,
    code: 'party_balances',
    version: 1,
    label: 'أرصدة الذمم لأول المدة',
    columns: [
      ImportColumnSpec('code', 'الكود'),
      ImportColumnSpec('name', 'الاسم'),
      ImportColumnSpec('kind', 'النوع'),
      ImportColumnSpec('balance', 'الرصيد'),
      ImportColumnSpec('currency', 'العملة'),
      ImportColumnSpec('fx_rate', 'سعر الصرف'),
    ],
  ),
  ImportTemplate(
    id: ImportTemplateId.openingFull,
    code: 'opening_full',
    version: 1,
    label: 'الأرصدة الكاملة لأول المدة',
    columns: [
      ImportColumnSpec('section', 'القسم'),
      ImportColumnSpec('code', 'الكود'),
      ImportColumnSpec('name', 'الاسم'),
      ImportColumnSpec('kind', 'النوع'),
      ImportColumnSpec('quantity', 'الكمية'),
      ImportColumnSpec('value', 'القيمة'),
      ImportColumnSpec('unit', 'الوحدة'),
      ImportColumnSpec('currency', 'العملة'),
      ImportColumnSpec('fx_rate', 'سعر الصرف'),
    ],
  ),
  // س142 (الدفعة الثالثة — تشطيب الخط §25.11): الوحدة 3 «كميات المخزون
  // الافتتاحية» — سبعة أعمدة بمرآة قسم المخزون بالوحدة 5 بلا قسم ولا
  // نوع (بضاعة حصراً — عقد الاستيراد الموثق)، وعمود العملة دائم
  // بعقد §25.4 وفراغه الأساسية.
  ImportTemplate(
    id: ImportTemplateId.openingQty,
    code: 'opening_qty',
    version: 1,
    label: 'كميات المخزون الافتتاحية',
    columns: [
      ImportColumnSpec('code', 'كود الصنف'),
      ImportColumnSpec('name', 'الاسم'),
      ImportColumnSpec('quantity', 'الكمية'),
      ImportColumnSpec('value', 'القيمة'),
      ImportColumnSpec('unit', 'الوحدة'),
      ImportColumnSpec('currency', 'العملة'),
      ImportColumnSpec('fx_rate', 'سعر الصرف'),
    ],
  ),
];

/// القالب بالهوية أو null إن لم يوجد (القالب غير المعروف).
ImportTemplate? importTemplateOf(ImportTemplateId id) {
  for (final t in importTemplates) {
    if (t.id == id) return t;
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════
// الأخطاء — رقم الصف + العمود + القيمة + رمز DQ + وصف عربي + إجراء
// (§25.5) — رموز الدفعة DQ-1017..DQ-1024 المخصصة بسجل error_codes.
// ═══════════════════════════════════════════════════════════════

/// خطأ استيراد واحد كما يظهر بتقرير الأخطاء — محمول بيانات لا رسالة
/// جاهزة (فصل المجال عن العرض).
class ImportError {
  /// رقم الصف في الملف كما يراه المستخدم (سطر الترويسة أولٌ والقوالب
  /// سطران: الترويسة ثم عناوين الأعمدة) — صفر لخطأ طبقة الملف كله.
  final int row;

  /// رقم العمود بالصف (1-based) — null لخطأ لا يربط بعمود واحد.
  final int? column;

  /// القيمة المرفوضة كما كُتبت — للعرض لا للإصلاح الآلي.
  final String? value;

  final String dqCode;
  final String description;
  final String suggestedAction;

  const ImportError({
    required this.row,
    this.column,
    this.value,
    required this.dqCode,
    required this.description,
    required this.suggestedAction,
  });

  @override
  String toString() =>
      'ImportError(row: $row, column: $column, value: $value, '
      '$dqCode: $description)';
}

/// رموز الدفعة الثابتة — لا تُعاد ولا تُرقَّم من جديد (عرف D-055).
const String dqImportEncoding = 'DQ-1017';
const String dqImportTemplateUnknown = 'DQ-1018';
const String dqImportSeparatorAmbiguous = 'DQ-1019';
const String dqImportRowInvalid = 'DQ-1020';
const String dqImportReferenceMissing = 'DQ-1021';
const String dqImportInternalDuplicate = 'DQ-1022';
const String dqImportConflictExisting = 'DQ-1023';
const String dqImportRowLimit = 'DQ-1024';

/// حد الصفوف الموثق (§25.5): تحذير زمني فوق العتبة اللينة ورفض فوق
/// الحد الصلب.
const int importSoftRowLimit = 5000;
const int importHardRowLimit = 10000;

// ═══════════════════════════════════════════════════════════════
// طبقة الملف: ترميز صارم + BOM + محلل RFC 4180 + كشف الفاصل (د-5)
// ═══════════════════════════════════════════════════════════════

/// المرشحان الوحيدان للفاصل (د-5) — غيرهما لا يُخمَّن.
const String importSeparatorComma = ',';
const String importSeparatorSemicolon = '؛';

/// سجل قياسي داخل المحلل: بداية السجل برقم سطره وحقولته.
class _CsvRecord {
  final int line;
  final List<String> fields;

  const _CsvRecord(this.line, this.fields);

  bool get isBlank =>
      fields.length == 1 && fields.first.trim().isEmpty;
}

/// نتيجة التقطيع بفاصل مرشح واحد — أو أول سطر بتنصيص غير مغلق.
/// أرقام السطور مطلقة بالملف: [startLine] إزاحة سطر الترويسة
/// المستهلك نصاً خاماً (الترقية كما يراها المستخدم في Excel).
class _TokenizeOutcome {
  final List<_CsvRecord> records;
  final int? malformedQuoteLine;

  const _TokenizeOutcome(this.records, this.malformedQuoteLine);
}

/// محلل CSV بالاصطلاح القائم حرفاً (اقتباس RFC 4180 وتضاعف التنصيص —
/// مرآة csvEscapeField): الفاصل خارج التنصيص حصراً، والحقل المقتبس
/// يحمل فاصلاً وأسطراً وتنصيصاً مضاعفاً. تعيد null في التغليف إذا
/// وُجد تنصيص غير مغلق (سطره بالنتيجة).
_TokenizeOutcome _tokenizeCsv(
    String text, String separator,
    {required int startLine}) {
  final records = <_CsvRecord>[];
  var field = StringBuffer();
  final fields = <String>[];
  var inQuotes = false;
  var quoteClosed = false;
  var line = startLine;
  var recordLine = startLine;
  var sawAnyField = false;

  void endField() {
    fields.add(field.toString());
    field = StringBuffer();
    quoteClosed = false;
  }

  void endRecord() {
    endField();
    records.add(_CsvRecord(recordLine, List.of(fields)));
    fields.clear();
    sawAnyField = false;
    recordLine = line;
  }

  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        quoteClosed = true;
        i++;
        continue;
      }
      if (c == '\n') line++;
      field.write(c);
      i++;
      continue;
    }
    if (c == '"') {
      if (quoteClosed) {
        return _TokenizeOutcome(const [], recordLine);
      }
      if (sawAnyField && field.isNotEmpty) {
        // تنصيص بعُذر حرف بعد حقل خام — ليس حقلَا مقتبساً.
        return _TokenizeOutcome(const [], recordLine);
      }
      inQuotes = true;
      sawAnyField = true;
      i++;
      continue;
    }
    if (c == separator) {
      endField();
      sawAnyField = true;
      i++;
      continue;
    }
    if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
      line++;
      endRecord();
      i++;
      continue;
    }
    field.write(c);
    sawAnyField = true;
    i++;
  }
  if (inQuotes) {
    return _TokenizeOutcome(const [], recordLine);
  }
  if (field.isNotEmpty || fields.isNotEmpty || sawAnyField) {
    endRecord();
  }
  return _TokenizeOutcome(records, null);
}

/// تشريح الملف الخام: ترويسته وسجلاته الحية بالفاصل المقرر.
///
/// الترويسة (السطر الأول) تُستهلك نصاً خاماً لا تحليلاً CSV — فهي
/// بنية ثابتة `dq-import:<كود>,<إصدار>` لا بيانات، ويُعفى سطرها من
/// فحص عدد الأعمدة الذي يمرّس الفاصل.
class _RawFileParse {
  final ImportTemplate template;
  final List<_CsvRecord> records;

  /// سجلات عناوين الأعمدة وبياناتها بعد إسقاط الترويسة والسطور
  /// الفارغة، محفوظة بأرقام سطورها المطلقة بالملف.
  final bool semicolonUsed;
  final List<ImportError> errors;

  const _RawFileParse(
      this.template, this.records, this.semicolonUsed, this.errors);
}

/// خطأ طبقة الملف — الصف صفر لأنه يخص الملف كله.
ImportError _fileError({
  required String dqCode,
  required String description,
  required String suggestedAction,
  int? column,
  String? value,
}) =>
    ImportError(
      row: 0,
      column: column,
      value: value,
      dqCode: dqCode,
      description: description,
      suggestedAction: suggestedAction,
    );

/// التحليل المشترك: ترميز صارم، BOM، ترويسة القالب، كشف الفاصل (د-5)
/// بفحصه البنيوي المرسى على عدد الأعمدة، وحد الصفوف. يعيد الأخطاء
/// القاتلة فارغاً من السجلات عند أي رفض ملفي.
_RawFileParse _parseRawFile(List<int> bytes, ImportTemplateId id) {
  final template = importTemplateOf(id)!;

  // الترميز صارم (§25.4): utf8.decode بلا تهاون — الفاسد برسالة إنقاذ.
  String text;
  try {
    text = utf8StrictDecode(bytes);
  } on FormatException {
    return _RawFileParse(template, const [], false, [
      _fileError(
        dqCode: dqImportEncoding,
        description: 'الملف ليس UTF-8 سليماً فلا يُقرأ بايتاً بايتاً '
            'بلا تخمين.',
        suggestedAction: 'من Excel: حفظ باسم ← CSV UTF-8، ثم أعد '
            'الاستيراد.',
      ),
    ]);
  }

  // BOM يُبتلع إن وُجد (مرآة F-166).
  if (text.startsWith(csvUtf8Bom)) text = text.substring(1);

  // الترويسة: السطر الأول نصاً خاماً.
  final firstBreak = _firstLineBreak(text);
  final markerLine = (firstBreak == -1 ? text : text.substring(0, firstBreak))
      .trim();
  final rest =
      firstBreak == -1 ? '' : text.substring(firstBreak + _breakLength(text, firstBreak));
  final marker = _parseMarkerLine(markerLine);
  if (marker == null) {
    return _RawFileParse(template, const [], false, [
      _fileError(
        dqCode: dqImportTemplateUnknown,
        description: 'السطر الأول ليس ترويسة قالب دِقَّة '
            '(المتوقع: ${template.markerLine}).',
        suggestedAction: 'نزّل القالب الفارغ من شاشة الاستيراد واملأه '
            'على بنته دون مساس بسطرَي الترويسة.',
      ),
    ]);
  }
  if (marker.$1 != template.code) {
    return _RawFileParse(template, const [], false, [
      _fileError(
        dqCode: dqImportTemplateUnknown,
        description: 'الملف قالب «${marker.$1}» بينما الاستيراد المطلوب '
            '«${template.code}» — قالب لا يطابق الوحدة.',
        suggestedAction: 'اختر الوحدة المطابقة أو نزّل قالبها الفارغ '
            'من التطبيق.',
      ),
    ]);
  }
  if (marker.$2 != template.version) {
    return _RawFileParse(template, const [], false, [
      _fileError(
        dqCode: dqImportTemplateUnknown,
        description: 'إصدار القالب v${marker.$2} غير المدعوم '
            '(المدعوم: v${template.version}).',
        suggestedAction: 'نزّل القالب الحالي من شاشة الاستيراد '
            'ثم أعد الاستيراد.',
      ),
    ]);
  }

  // كشف الفاصل (د-5): فاصل واحد حصراً يطابق عدد الأعمدة بكل السجلات.
  // سطر الترويسة المستهلك يحسب سطراً واحداً فتبدأ الترقية من 2.
  const startLine = 2;
  final comma = _tokenizeCsv(rest, importSeparatorComma,
      startLine: startLine);
  final semicolon = _tokenizeCsv(rest, importSeparatorSemicolon,
      startLine: startLine);

  // التنصيص المكسور مرشحاً مرشحاً لا خطأ ملف مطلقاً: ملف الفاصلة
  // يبدو «مكسوراً» لقارئ المنقوطة (الاقتباس وسط حقل خام لديه) —
  // الفساد الملفي الصادق ما هو إلا مكسور تحت الفاصلين معاً.
  final commaRecords = comma.malformedQuoteLine == null
      ? comma.records.where((r) => !r.isBlank).toList()
      : const <_CsvRecord>[];
  final semicolonRecords = semicolon.malformedQuoteLine == null
      ? semicolon.records.where((r) => !r.isBlank).toList()
      : const <_CsvRecord>[];

  final commaFits = _allRecordsMatchCount(commaRecords, template.columnCount);
  final semicolonFits =
      _allRecordsMatchCount(semicolonRecords, template.columnCount);

  // مكسور تحت الفاصلين معاً — فساد بنيوي صادق بسطره الأول المعلن.
  if (!commaFits &&
      !semicolonFits &&
      comma.malformedQuoteLine != null &&
      semicolon.malformedQuoteLine != null) {
    return _RawFileParse(template, const [], false, [
      _fileError(
        dqCode: dqImportRowInvalid,
        column: null,
        value: null,
        description: 'سطر ${comma.malformedQuoteLine} يحمل تنصيصاً '
            'غير مغلق أو حرفاً بعُذر تنصيص — البنية غير سليمة.',
        suggestedAction: 'صحّح التنصيص بهذا السطر (علامة التنصيص '
            'المزدوجة داخل الحقل تُكتب مرتين) أو أعد التصدير من المصدر.',
      ),
    ]);
  }

  if (commaFits == semicolonFits) {
    // انطبق كلاهما (غامض) أو لا منهما (مكسور) — رفض بتوجيه عربي (د-5).
    return _RawFileParse(template, const [], false, [
      _fileError(
        dqCode: dqImportSeparatorAmbiguous,
        description: commaFits
            ? 'الملف يطابق عدد أعمدة القالب بالفاصلين معاً — الفاصل '
                'غير معلوم بلا تخمين.'
            : 'لا فاصلة («,») ولا منقوطة («؛») تطابق عدد أعمدة القالب '
                '(${template.columnCount}) بكل الصفوف.',
        suggestedAction: 'استخدم القالب الفارغ المنزّل من التطبيق '
            'حصراً — وفاصله الفاصلة.',
      ),
    ]);
  }

  final semicolonUsed = semicolonFits;
  final records = semicolonUsed ? semicolonRecords : commaRecords;

  // سجل عناوين الأعمدة أول السجلات — بنية القالب لا بيانات: يُستهلك
  // وفحص بنويته مكفول بعدد الأعمدة أعلاه. وبلا بيانات بعده: رفض صريح
  // لا قائمة فارغة صامتة (القالب الفارغ كما وُلد لا يُعتمد).
  final data =
      records.isEmpty ? const <_CsvRecord>[] : records.sublist(1);
  if (data.isEmpty) {
    return _RawFileParse(template, const [], semicolonUsed, [
      _fileError(
        dqCode: dqImportRowInvalid,
        description: 'الملف بلا صفوف بيانات — سطر الترويسة وعناوين '
            'الأعمدة فقط.',
        suggestedAction: 'املأ صفوف البيانات تحت سطر العناوين ثم '
            'أعد الاستيراد.',
      ),
    ]);
  }

  // الحد الموثق (§25.5): رفض صريح فوق 10,000 بالرقم الفعلي والحد
  // واقتراح التقسيم.
  if (data.length > importHardRowLimit) {
    return _RawFileParse(template, const [], semicolonUsed, [
      _fileError(
        dqCode: dqImportRowLimit,
        description: 'الملف يحمل ${data.length} صف والحد ${importHardRowLimit} '
            'صفاً لكل وحدة.',
        suggestedAction: 'قسّم الملف على ملفات أصغر ثم استوردها '
            'كل على حدة.',
      ),
    ]);
  }

  return _RawFileParse(
      template, data, semicolonUsed, const []);
}

int _firstLineBreak(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x0A || c == 0x0D) return i;
  }
  return -1;
}

int _breakLength(String text, int at) {
  if (text.codeUnitAt(at) == 0x0D &&
      at + 1 < text.length &&
      text.codeUnitAt(at + 1) == 0x0A) {
    return 2;
  }
  return 1;
}

/// ترويسة القالب: `dq-import:<كود>,<إصدار>` — null إن لم تطابق النمط.
/// درس س141: كود القالب بنية لا نص حر — الشرطة السفلية جزء منه
/// (`party_balances`/`opening_full`) فالنمط يقبلها حرفاً.
(String, int)? _parseMarkerLine(String line) {
  final m = RegExp(r'^dq-import:([a-z][a-z0-9_-]*),(\d+)$').firstMatch(line);
  if (m == null) return null;
  return (m.group(1)!, int.parse(m.group(2)!));
}

bool _allRecordsMatchCount(List<_CsvRecord> records, int count) {
  if (records.isEmpty) return false; // الفراغ لا «يطابق» بلا سحر
  for (final r in records) {
    if (r.fields.length != count) return false;
  }
  return true;
}

/// فك UTF-8 صارم — منفصل توثيقاً (§25.4: لا كشف ترميز ولا تحويل):
/// utf8.decode الصارم يرمي FormatException عند أول بايت فاسد فتُرفض
/// رسالةَ الإنقاذ العربية بدل تخمين المعنى.
String utf8StrictDecode(List<int> bytes) => utf8.decode(bytes);

// ═══════════════════════════════════════════════════════════════
// الأعداد البشرية — تحليل بنيوي صارم ثم تحويل برياضة أعداد صحيحة
// ═══════════════════════════════════════════════════════════════

/// أجزاء عدد بشري مقروء: الجزء الصحيح وخانات الكسر — بلا أي تحويل
/// عائم. القاعدة الموثقة: أرقام لاتينية أو عربية-هندية (تحويل محدد
/// المعنى لا تخمين)، فاصلة عشرية واحدة «.»، بلا فواصل آلاف، بلا إشارة
/// سالبة (لا سعر سالب — س6).
class DecimalParts {
  /// خانات الجزء الصحيح كسلسلة أرقام — «0» للكسري الصرف.
  final String intPart;

  /// عدد خانات الكسر المكتوبة.
  final int fracDigits;

  /// الخانات الكسرية كسلسلة أرقام (فارغة إن لم تُكتب).
  final String fracPart;

  const DecimalParts(this.intPart, this.fracDigits, this.fracPart);
}

/// طول أقصى للجزء الصحيح — أي رقم أكبر خارج مدى العدد الصحيح الآمن
/// مرفوض بلا صمت («الرقم أكبر من المدى المدعوم»).
const int _maxIntegerDigits = 15;

/// تحليل بنيوي صارم لعدد بشري. يعيد null عند الفراغ (يقرر المستدعي
/// سياسة الفراغ: سعر فارغ = صفر «بلا سعر بعد»، حد ائتمان فارغ = بلا
/// سقف) وعند الفساد.
DecimalParts? parseHumanDecimal(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  // الأرقام العربية-الهندية تحويلٌ محدد المعنى (٠-٩ ← 0-9) — مثل
  // ابتلاع BOM لا تخمين معنى.
  final digits = <int>[];
  for (final ch in s.runes) {
    if (ch >= 0x0660 && ch <= 0x0669) {
      digits.add(0x30 + (ch - 0x0660));
    } else if (ch >= 0x06F0 && ch <= 0x06F9) {
      digits.add(0x30 + (ch - 0x06F0));
    } else {
      digits.add(ch);
    }
  }
  s = String.fromCharCodes(digits);
  var dot = false;
  var intPart = StringBuffer();
  var fracPart = StringBuffer();
  for (final c in s.codeUnits) {
    if (c == 0x2E) {
      if (dot) return null; // فاصلة عشرية ثانية
      dot = true;
      continue;
    }
    if (c < 0x30 || c > 0x39) return null; // ما ليس رقماً — فساد
    if (dot) {
      fracPart.writeCharCode(c);
    } else {
      intPart.writeCharCode(c);
    }
  }
  // قيادة الأصفار مقبولة («007») — القيمة بنت الرياضة لا الظاهر.
  final finalInt = intPart.isEmpty ? '0' : intPart.toString();
  if (finalInt.length > _maxIntegerDigits) return null;
  return DecimalParts(finalInt, fracPart.length, fracPart.toString());
}

/// التحويل النهائي إلى الوحدة الصغرى بدقة العملة — خانة كسرية تفوق
/// دقة العملة رفضٌ صريح لا تقريب صامت، والرياضة أعداد صحيحة حصراً.
/// يعيد null عند تجاوز الدقة أو الطفح.
int? decimalPartsToMinor(DecimalParts p, int minorUnits) {
  if (p.fracDigits > minorUnits) return null;
  final scale = _pow10(minorUnits);
  final intMinor = _intFromDigits(p.intPart) * scale;
  final fracMinor = p.fracDigits == 0
      ? 0
      : _intFromDigits(p.fracPart) * _pow10(minorUnits - p.fracDigits);
  final total = intMinor + fracMinor;
  if (total < 0) return null; // طفح صحيح — رفض صريح
  return total;
}

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

int _intFromDigits(String digits) {
  if (digits.isEmpty) return 0;
  var v = 0;
  for (final c in digits.codeUnits) {
    v = v * 10 + (c - 0x30);
  }
  return v;
}

// ═══════════════════════════════════════════════════════════════
// السياسة (§25.3.2) ومرجع العملات المحقون
// ═══════════════════════════════════════════════════════════════

/// سياسة الموجود — «إضافة جديد» الافتراضي و«تحديث الموجود» وصفيفات
/// فقط في v1 (د-2).
enum ImportExistingPolicy {
  /// الموجود يُتخطى والجديد يُنشأ (الافتراضي).
  addNew,

  /// الوصفيّات القابلة للتحديث تتحدث والفروق تُعرض بتقريرها (د-2).
  updateExisting,
}

/// شعار السياسة كما يُعرض ويسجل بحدث الاستيراد.
String importPolicyLabel(ImportExistingPolicy policy) =>
    policy == ImportExistingPolicy.addNew
        ? 'إضافة جديد'
        : 'تحديث الموجود';

/// مرجع عملة محقون من التخزين — بالمعرّف ودقة الوحدة الصغرى، كي يتحول
/// البشري إلى minor بدقة العملة نفسها لا بدقة افتراضية.
class ImportCurrencyRef {
  final int id;
  final String code;
  final int minorUnits;

  const ImportCurrencyRef({
    required this.id,
    required this.code,
    required this.minorUnits,
  });
}

/// فرق عمود واحد بمعاينة التحديث — المحْدَث والمُترك مع سبيه.
class ImportDifference {
  final int row;
  final String columnKey;
  final String columnLabel;
  final String oldValue;
  final String newValue;

  /// هل سيُكتب هذا الفرق؟ ما لا يُحدَّث في v1 (د-2) يُعرض بسبيه
  /// لا سحراً صامتاً.
  final bool updated;
  final String? note;

  const ImportDifference({
    required this.row,
    required this.columnKey,
    required this.columnLabel,
    required this.oldValue,
    required this.newValue,
    required this.updated,
    this.note,
  });
}

// ═══════════════════════════════════════════════════════════════
// الأطراف — تحليل الملف (طبقة الملف والصف) ثم التخطيط (طبقة الدفعة)
// ═══════════════════════════════════════════════════════════════

/// صف أطراف خام بعد فحص الصيغة — القيم المنظمة قبل مرجع الدفعة.
class PartiesImportRowRaw {
  final int row;
  final String code;
  final String name;
  final String kindStorage;
  final String currencyCode;

  /// الفراغ مشروع «بلا سقف» (س-34) — null.
  final String? creditLimitRaw;

  const PartiesImportRowRaw({
    required this.row,
    required this.code,
    required this.name,
    required this.kindStorage,
    required this.currencyCode,
    required this.creditLimitRaw,
  });
}

/// نتيجة تحليل ملف الأطراف — الأخطاء القاتلة تمنع الاعتماد كله.
class PartiesFileParse {
  final List<PartiesImportRowRaw> rows;
  final List<ImportError> errors;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const PartiesFileParse({
    required this.rows,
    required this.errors,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isRejected => errors.isNotEmpty;
}

/// قيم عمود «النوع» المقبولة — عناوين القالب العربية بقيم التخزين،
/// وقيم التخزين اللاتينية مقبولة كذلك (ملفات مصدَّرة سابقاً).
const Map<String, String> partyKindImportValues = {
  'عميل': 'customer',
  'مورد': 'supplier',
  'عميل ومورد معاً': 'both',
  'customer': 'customer',
  'supplier': 'supplier',
  'both': 'both',
};

/// تحليل ملف أطراف: طبقة الملف (ترميز/قالب/فاصل/حد) ثم طبقة الصف
/// (إلزامي/صيغة) — والمرجع والتكرار الداخلي لطبقة الدفعة بالتخطيط.
PartiesFileParse parsePartiesFile(List<int> bytes) {
  final raw = _parseRawFile(bytes, ImportTemplateId.parties);
  final rows = <PartiesImportRowRaw>[];
  final errors = List<ImportError>.of(raw.errors);

  for (final rec in raw.records) {
    final f = rec.fields;
    // فحص الصف (§25.5): الإلزامي والصيغة — برقم الصف والعمود والقيمة.

    final code = sanitizeFreeName(f[0]);
    if (code.isEmpty) {
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'الكود إلزامي وصف فارغ مرفوض.',
        suggestedAction: 'املأ كود الطرف — به يرتبط كل ما بعده (D-062).',
      ));
    } else if (!isValidPartyNumber(code)) {
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'الكود خارج القائمة البيضاء: حروف وأرقام '
            'و «- _ .» حصراً بلا فراغ.',
        suggestedAction: 'صحّح كود الطرف إلى رمز من القائمة البيضاء.',
      ));
    }

    final name = sanitizeFreeName(f[1]);
    if (name.isEmpty) {
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم إلزامي وصف فارغ مرفوض.',
        suggestedAction: 'املأ اسم الطرف.',
      ));
    } else if (freeNameHasControlChars(name)) {
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم يحمل محارف تحكم خفية.',
        suggestedAction: 'أعد كتابة الاسم بلا لصق من مصدر يحمل علامات '
            'غير مرئية.',
      ));
    }

    final kindRaw = f[2].trim();
    final kind = partyKindImportValues[kindRaw] ??
        partyKindImportValues[kindRaw.toLowerCase()];
    if (kind == null) {
      errors.add(ImportError(
        row: rec.line,
        column: 3,
        value: f[2],
        dqCode: dqImportRowInvalid,
        description: 'النوع إلزامي بقيمة معروفة: عميل، مورد، '
            'عميل ومورد معاً.',
        suggestedAction: 'اكتب أحد القيم الثلاث حرفاً كما بالقالب.',
      ));
    }

    final currencyRaw = f[3].trim();
    final currencyCode =
        currencyRaw.isEmpty ? 'SYP' : normalizeCurrencyCode(currencyRaw);
    if (currencyRaw.isNotEmpty && !RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
      errors.add(ImportError(
        row: rec.line,
        column: 4,
        value: f[3],
        dqCode: dqImportRowInvalid,
        description: 'كود العملة ثلاثة أحرف لاتينية A-Z حصراً '
            '(صيغة ISO 4217).',
        suggestedAction: 'اكتب كود العملة ثلاثة أحرف (مثال: SYP) أو '
            'اتركه فارغاً للأساسية.',
      ));
    }

    final creditRaw = f[4].trim();
    String? creditLimitRaw;
    if (creditRaw.isNotEmpty) {
      final parts = parseHumanDecimal(creditRaw);
      if (parts == null) {
        errors.add(ImportError(
          row: rec.line,
          column: 5,
          value: f[4],
          dqCode: dqImportRowInvalid,
          description: 'حد الائتمان عدد بشري سليم فقط: أرقام وفاصلة '
              'عشرية واحدة، بلا فواصل آلاف ولا إشارة سالب.',
          suggestedAction: 'اكتبه رقمًا عادياً (مثال: 150000) أو اتركه '
              'فارغاً «بلا سقف».',
        ));
      } else {
        creditLimitRaw = creditRaw;
      }
    }

    // الصف يُحفظ حتى مع خطأ في عمود آخر — التقرير يعرض كل الأخطاء
    // دفعة واحدة (§25.5) والاعتماد مسدود كله على أي خطأ.
    if (code.isNotEmpty &&
        name.isNotEmpty &&
        kind != null &&
        (creditLimitRaw != null || creditRaw.isEmpty)) {
      rows.add(PartiesImportRowRaw(
        row: rec.line,
        code: code,
        name: name,
        kindStorage: kind,
        currencyCode: currencyCode,
        creditLimitRaw: creditLimitRaw,
      ));
    }
  }

  return PartiesFileParse(
    rows: rows,
    errors: errors,
    semicolonUsed: raw.semicolonUsed,
    overSoftLimit: raw.records.length > importSoftRowLimit,
    totalDataRows: raw.records.length,
  );
}

/// خطة استيراد الأطراف — ناتج طبقة الدفعة كاملاً.
class PartiesImportPlan {
  /// الأسطر الجديدة المزمع إضافتها.
  final List<PartyImportCreate> creates;

  /// الموجود المزمع تحديث وصفيّاته القابلة (الاسم حصراً في v1 — د-2).
  final List<PartyImportUpdate> updates;

  /// الموجود المتخطى بسياسة «إضافة جديد».
  final List<PartyImportSkip> skipped;

  /// كل أخطاء المسار (ملف + صف + دفعة) — فارغتها شرط الاعتماد.
  final List<ImportError> errors;

  /// فروق التحديث (المحدث والمترك بسبيه) لتقرير الفروق (§25.3.2).
  final List<ImportDifference> differences;

  /// سياسة الموجود كما خُطّط بها — تسجّل بحدث الاستيراد (§25.6).
  final ImportExistingPolicy policy;

  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const PartiesImportPlan({
    required this.creates,
    required this.updates,
    required this.skipped,
    required this.errors,
    required this.differences,
    required this.policy,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isApprovable => errors.isEmpty;
  int get newCount => creates.length;
  int get existingCount => updates.length + skipped.length;
  int get errorCount => errors.length;
}

/// سطر إضافة طرف — القيم محولة نهائياً (معرّف العملة والحد بوحدة
/// الصغرى) جاهزة للمعاملة الواحدة.
class PartyImportCreate {
  final int row;
  final String number;
  final String name;
  final String kindStorage;
  final int currencyId;
  final int? creditLimitBaseMinor;

  const PartyImportCreate({
    required this.row,
    required this.number,
    required this.name,
    required this.kindStorage,
    required this.currencyId,
    required this.creditLimitBaseMinor,
  });
}

/// سطر تحديث طرف — الاسم حصراً في v1 (د-2) مع فروقه.
class PartyImportUpdate {
  final int row;
  final int partyId;
  final String currentName;
  final String newName;

  const PartyImportUpdate({
    required this.row,
    required this.partyId,
    required this.currentName,
    required this.newName,
  });
}

/// سطر تخطي — موجود سابقاً بسياسة «إضافة جديد».
class PartyImportSkip {
  final int row;
  final String number;
  final String existingLabel;

  const PartyImportSkip({
    required this.row,
    required this.number,
    required this.existingLabel,
  });
}

/// تخطيط استيراد الأطراف — طبقة الدفعة نقية: التكرار الداخلي (فادح
/// رفض كلي)، المرجع (عملة غير معرفة)، التحويل النهائي، وسياسة الموجود.
///
/// [currencies] مرجع العملات المزروعة بمكوّداتها المقلمة؛ [existing]
/// فهرس تفرد الأطراف القائمة بنمط D-063/D-065.
PartiesImportPlan planPartiesImport(
  PartiesFileParse parse, {
  required Map<String, ImportCurrencyRef> currencies,
  required PartyUniquenessIndex existing,
  required ImportExistingPolicy policy,
}) {
  final errors = List<ImportError>.of(parse.errors);
  final creates = <PartyImportCreate>[];
  final updates = <PartyImportUpdate>[];
  final skipped = <PartyImportSkip>[];
  final differences = <ImportDifference>[];

  // التكرار الداخلي (§25.5) — فادح رفض كلي: بالكود بمفتاح D-063
  // وبالاسم الحرفي بقاعدة D-065.
  final seenCodes = <String, int>{};
  final seenNames = <String, int>{};
  for (final row in parse.rows) {
    final codeKey = partyNumberKey(row.code);
    if (seenCodes.containsKey(codeKey)) {
      errors.add(ImportError(
        row: row.row,
        column: 1,
        value: row.code,
        dqCode: dqImportInternalDuplicate,
        description: 'الكود مكرر داخل الملف نفسه (صف ${seenCodes[codeKey]}) '
            '— التكرار الداخلي خطأ فادح.',
        suggestedAction: 'وحّد صفَّي الكود أو احذف الزائد ثم أعد '
            'الاستيراد.',
      ));
    } else {
      seenCodes[codeKey] = row.row;
    }
    if (seenNames.containsKey(row.name)) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportInternalDuplicate,
        description: 'الاسم مكرر داخل الملف نفسه (صف ${seenNames[row.name]}) '
            '— منع تكرار الاسم الحرفي D-065.',
        suggestedAction: 'وحّد صفَّي الاسم أو ميّزهما ثم أعد الاستيراد.',
      ));
    } else {
      seenNames[row.name] = row.row;
    }
  }

  for (final row in parse.rows) {
    // مرجع العملة — غير المعرفة رفض صف صريح لا افتراض (§25.5).
    final currency = currencies[normalizeCurrencyCode(row.currencyCode)];
    if (currency == null) {
      errors.add(ImportError(
        row: row.row,
        column: 4,
        value: row.currencyCode,
        dqCode: dqImportReferenceMissing,
        description: 'العملة ${row.currencyCode} غير معرفة بالتطبيق.',
        suggestedAction: 'أضف العملة من شاشة العملات أولاً أو صحّح '
            'الكود (الفراغ يعني الأساسية SYP).',
      ));
      continue;
    }

    // تحويل حد الائتمان بدقة العملة — والفراغ «بلا سقف» مشروع (س-34).
    int? creditMinor;
    final creditRaw = row.creditLimitRaw;
    if (creditRaw != null) {
      final parts = parseHumanDecimal(creditRaw)!;
      final minor = decimalPartsToMinor(parts, currency.minorUnits);
      if (minor == null || minor <= 0) {
        errors.add(ImportError(
          row: row.row,
          column: 5,
          value: creditRaw,
          dqCode: dqImportRowInvalid,
          description: minor == null
              ? 'خانات الكسر تفوق دقة العملة ${currency.code} '
                  '(${currency.minorUnits} خانات) — لا تقريب صامت.'
              : 'حد الائتمان إن أُدخل فيجب أن يكون موجباً (س-34).',
          suggestedAction: 'صحّح القيمة بدقة العملة أو اتركه فارغاً '
              '«بلا سقف».',
        ));
        continue;
      }
      creditMinor = minor;
    }

    final holderByNumber = existing.byNumberKey(row.code);
    if (holderByNumber != null) {
      // الموجود — بالسياسة (§25.3.2).
      if (policy == ImportExistingPolicy.addNew) {
        skipped.add(PartyImportSkip(
          row: row.row,
          number: row.code,
          existingLabel: holderByNumber.displayLabel,
        ));
        // فرق الاسم إن وجد يُعرض كغير مُحدَّث — شفافية لا سحر.
        if (holderByNumber.name != row.name) {
          differences.add(ImportDifference(
            row: row.row,
            columnKey: 'name',
            columnLabel: 'الاسم',
            oldValue: holderByNumber.name,
            newValue: row.name,
            updated: false,
            note: 'الموجود يُتخطى بسياسة «إضافة جديد» — حدّث الاسم '
                'يدوياً أو استخدم سياسة التحديث.',
          ));
        }
        continue;
      }
      // سياسة التحديث — الاسم حصراً في v1 (د-2)، وبقية الفروق تُعرض
      // غير مُحدَّثة بسبيها.
      if (holderByNumber.name != row.name) {
        updates.add(PartyImportUpdate(
          row: row.row,
          partyId: holderByNumber.id,
          currentName: holderByNumber.name,
          newName: row.name,
        ));
        differences.add(ImportDifference(
          row: row.row,
          columnKey: 'name',
          columnLabel: 'الاسم',
          oldValue: holderByNumber.name,
          newValue: row.name,
          updated: true,
        ));
      }
      continue;
    }

    // طرف جديد — الاسم الحرفي لا يصطدم بطرف آخر (D-065).
    final nameHolder = existing.byLiteralName(row.name);
    if (nameHolder != null) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportConflictExisting,
        description: 'الاسم مستخدم للطرف: ${nameHolder.displayLabel} '
            '— منع تكرار الاسم الحرفي (D-065).',
        suggestedAction: 'غيّر الاسم أو استخدم سياسة التحديث إن كان '
            'هذا هو الطرف نفسه بكود آخر ملف.',
      ));
      continue;
    }

    creates.add(PartyImportCreate(
      row: row.row,
      number: row.code,
      name: row.name,
      kindStorage: row.kindStorage,
      currencyId: currency.id,
      creditLimitBaseMinor: creditMinor,
    ));
  }

  return PartiesImportPlan(
    creates: creates,
    updates: updates,
    skipped: skipped,
    errors: errors,
    differences: differences,
    policy: policy,
    semicolonUsed: parse.semicolonUsed,
    overSoftLimit: parse.overSoftLimit,
    totalDataRows: parse.totalDataRows,
  );
}

// ═══════════════════════════════════════════════════════════════
// الأصناف — النمط ذاته بإضافة الوحدات (الإنشاء الآلي إن لم توجد —
// وحدة أساسية بعامل 1، §25.4)
// ═══════════════════════════════════════════════════════════════

/// صف أصناف خام بعد فحص الصيغة.
class ItemsImportRowRaw {
  final int row;
  final String sku;
  final String name;
  final String unit;
  final String priceCurrencyCode;
  final String? purchasePriceRaw;
  final String? salePriceRaw;

  const ItemsImportRowRaw({
    required this.row,
    required this.sku,
    required this.name,
    required this.unit,
    required this.priceCurrencyCode,
    required this.purchasePriceRaw,
    required this.salePriceRaw,
  });
}

class ItemsFileParse {
  final List<ItemsImportRowRaw> rows;
  final List<ImportError> errors;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const ItemsFileParse({
    required this.rows,
    required this.errors,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isRejected => errors.isNotEmpty;
}

/// تحليل ملف أصناف — طبقة الملف ثم الصف، والوحدة إلزامية بالاسم.
ItemsFileParse parseItemsFile(List<int> bytes) {
  final raw = _parseRawFile(bytes, ImportTemplateId.items);
  final rows = <ItemsImportRowRaw>[];
  final errors = List<ImportError>.of(raw.errors);

  for (final rec in raw.records) {
    final f = rec.fields;

    final sku = f[0].trim();
    if (sku.isEmpty) {
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'كود الصنف إلزامي وهو ما يُنادى به الصنف.',
        suggestedAction: 'املأ كود الصنف بقائمة البيضاء (D-171): حروف '
            'وأرقام و «- _ .».',
      ));
    } else if (!isValidItemSku(sku)) {
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'كود الصنف خارج القائمة البيضاء: بلا فراغ '
            'ولا فاصل مسار.',
        suggestedAction: 'صحّح الكود إلى رمز من القائمة البيضاء.',
      ));
    }

    final name = sanitizeFreeName(f[1]);
    if (name.isEmpty) {
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم إلزامي وصف فارغ مرفوض.',
        suggestedAction: 'املأ اسم الصنف.',
      ));
    } else if (freeNameHasControlChars(name)) {
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم يحمل محارف تحكم خفية.',
        suggestedAction: 'أعد كتابة الاسم بلا لصق من مصدر يحمل علامات '
            'غير مرئية.',
      ));
    }

    final unit = sanitizeFreeName(f[2]);
    if (unit.isEmpty) {
      errors.add(ImportError(
        row: rec.line,
        column: 3,
        value: f[2],
        dqCode: dqImportRowInvalid,
        description: 'الوحدة إلزامية — تُنشأ آلياً إن لم توجد '
            'بالاسم.',
        suggestedAction: 'املأ اسم الوحدة (مثال: قطعة).',
      ));
    }

    final currencyRaw = f[3].trim();
    final currencyCode =
        currencyRaw.isEmpty ? 'SYP' : normalizeCurrencyCode(currencyRaw);
    if (currencyRaw.isNotEmpty &&
        !RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
      errors.add(ImportError(
        row: rec.line,
        column: 4,
        value: f[3],
        dqCode: dqImportRowInvalid,
        description: 'كود عملة السعر ثلاثة أحرف لاتينية A-Z حصراً.',
        suggestedAction: 'اكتب كود العملة أو اتركه فارغاً للأساسية.',
      ));
    }

    String? purchaseRaw;
    final purchaseField = f[4].trim();
    if (purchaseField.isNotEmpty) {
      if (parseHumanDecimal(purchaseField) == null) {
        errors.add(ImportError(
          row: rec.line,
          column: 5,
          value: f[4],
          dqCode: dqImportRowInvalid,
          description: 'سعر الشراء عدد بشري سليم فقط — بلا فواصل آلاف '
              'ولا إشارة سالب (س6).',
          suggestedAction: 'اكتبه رقمًا عادياً (مثال: 1250.5) أو اتركه '
              'فارغاً «بلا سعر بعد».',
        ));
      } else {
        purchaseRaw = purchaseField;
      }
    }

    String? saleRaw;
    final saleField = f[5].trim();
    if (saleField.isNotEmpty) {
      if (parseHumanDecimal(saleField) == null) {
        errors.add(ImportError(
          row: rec.line,
          column: 6,
          value: f[5],
          dqCode: dqImportRowInvalid,
          description: 'سعر البيع عدد بشري سليم فقط — بلا فواصل آلاف '
              'ولا إشارة سالب (س6).',
          suggestedAction: 'اكتبه رقمًا عادياً أو اتركه فارغاً «بلا سعر '
              'بعد».',
        ));
      } else {
        saleRaw = saleField;
      }
    }

    if (sku.isNotEmpty &&
        name.isNotEmpty &&
        unit.isNotEmpty &&
        (purchaseRaw != null || purchaseField.isEmpty) &&
        (saleRaw != null || saleField.isEmpty)) {
      rows.add(ItemsImportRowRaw(
        row: rec.line,
        sku: sku,
        name: name,
        unit: unit,
        priceCurrencyCode: currencyCode,
        purchasePriceRaw: purchaseRaw,
        salePriceRaw: saleRaw,
      ));
    }
  }

  return ItemsFileParse(
    rows: rows,
    errors: errors,
    semicolonUsed: raw.semicolonUsed,
    overSoftLimit: raw.records.length > importSoftRowLimit,
    totalDataRows: raw.records.length,
  );
}

/// خطة استيراد الأصناف — الوحدات الغائبة تُنشأ آلياً بعامل 1 لا تكرار.
class ItemsImportPlan {
  /// أسماء الوحدات الغائبة المزمع إنشائها آلياً (فريدة، مقلمة).
  final List<String> unitCreates;

  final List<ItemImportCreate> creates;
  final List<ItemImportUpdate> updates;
  final List<ItemImportSkip> skipped;
  final List<ImportError> errors;
  final List<ImportDifference> differences;

  /// سياسة الموجود كما خُطّط بها — تسجّل بحدث الاستيراد (§25.6).
  final ImportExistingPolicy policy;

  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const ItemsImportPlan({
    required this.unitCreates,
    required this.creates,
    required this.updates,
    required this.skipped,
    required this.errors,
    required this.differences,
    required this.policy,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isApprovable => errors.isEmpty;
  int get newCount => creates.length;
  int get existingCount => updates.length + skipped.length;
  int get errorCount => errors.length;
}

class ItemImportCreate {
  final int row;
  final String sku;
  final String name;

  /// اسم الوحدة كما ورد بالملف — التنفيذ يحلّه بمعرّفاً (القائمة
  /// بمعرّفها والغائب المزمع إنشاؤه آلياً ينشأ أول المعاملة).
  final String unitName;

  /// معرّف الوحدة القائمة بالاسم — «-1» لوحدة الخطة الجديدة.
  final int baseUnitId;
  final int priceCurrencyId;
  final int purchasePriceMinor;
  final int salePriceMinor;

  const ItemImportCreate({
    required this.row,
    required this.sku,
    required this.name,
    required this.unitName,
    required this.baseUnitId,
    required this.priceCurrencyId,
    required this.purchasePriceMinor,
    required this.salePriceMinor,
  });
}

/// تفاصيل صنف قائم محقونة من التخزين — للفروق الحقيقية بتقرير
/// التحديث (القيم القديمة بلا placeholders) ولحارس وحدة الصنف.
class ExistingItemImportRef {
  final int id;
  final String sku;
  final String name;
  final String unitName;
  final int purchasePriceMinor;
  final int salePriceMinor;
  final int priceCurrencyId;

  const ExistingItemImportRef({
    required this.id,
    required this.sku,
    required this.name,
    required this.unitName,
    required this.purchasePriceMinor,
    required this.salePriceMinor,
    required this.priceCurrencyId,
  });
}

/// تنسيق قيمة بوحدة الصغرى إلى بشري موثوق — العكس المطابق لتحليل
/// parseHumanDecimal (نفس الدقة، بلا كسور عائمة).
String formatMinorHuman(int minor, int minorUnits) {
  if (minorUnits == 0) return '$minor';
  final scale = _pow10(minorUnits);
  final intPart = minor ~/ scale;
  final frac = minor % scale;
  if (frac == 0) return '$intPart';
  var fracStr = frac.toString().padLeft(minorUnits, '0');
  // صفرٌ زائد ذيل الكسر يُقص — القيمة بننت الرياضة لا الظاهر
  // («1250.50» و«1250.5» عددان واحد) والقائد لا يُمس («0.05» تبقى).
  while (fracStr.endsWith('0')) {
    fracStr = fracStr.substring(0, fracStr.length - 1);
  }
  return '$intPart.$fracStr';
}

/// تفاصيل صنف قائم محقونة من التخزين — للفروق الحقيقية بتقرير
/// التحديث (القيم القديمة بلا placeholders) ولحارس وحدة الصنف.
/// تحديث صنف — الوصفيّات القابلة في v1 (د-2): الاسم والسعران؛
/// وحدة الصنف القائم لا تتغير بالاستيراد (حماية أرصدة المخزون
/// القائمة بوحدتها) وفرقها يُعرض بسبيه.
class ItemImportUpdate {
  final int row;
  final int itemId;
  final String currentName;
  final String? newName;
  final int currentPurchasePriceMinor;
  final int? newPurchasePriceMinor;
  final int currentSalePriceMinor;
  final int? newSalePriceMinor;

  const ItemImportUpdate({
    required this.row,
    required this.itemId,
    required this.currentName,
    required this.newName,
    required this.currentPurchasePriceMinor,
    required this.newPurchasePriceMinor,
    required this.currentSalePriceMinor,
    required this.newSalePriceMinor,
  });
}

class ItemImportSkip {
  final int row;
  final String sku;
  final String existingLabel;

  const ItemImportSkip({
    required this.row,
    required this.sku,
    required this.existingLabel,
  });
}

/// تخطيط استيراد الأصناف — نقية: الوحدات بالفهرس المحقون، والغائب
/// بالاسم يُنشأ آلياً (وحدة أساسية بعامل 1 — حد مصرَّح به §25.4).
ItemsImportPlan planItemsImport(
  ItemsFileParse parse, {
  required Map<String, ImportCurrencyRef> currencies,
  required ItemUniquenessIndex existing,
  required UnitUniquenessIndex units,

  /// تفاصيل الأصناف القائمة بالمعرّف — للفروق الحقيقية ولحارس
  /// وحدة الصنف القائم.
  required Map<int, ExistingItemImportRef> existingDetails,
  required ImportExistingPolicy policy,
}) {
  final currenciesById = <int, ImportCurrencyRef>{
    for (final ref in currencies.values) ref.id: ref,
  };
  final errors = List<ImportError>.of(parse.errors);
  final unitCreates = <String>[];
  final creates = <ItemImportCreate>[];
  final updates = <ItemImportUpdate>[];
  final skipped = <ItemImportSkip>[];
  final differences = <ImportDifference>[];

  // التكرار الداخلي — فادح رفض كلي (بالكود الحرفي D-073 وبالاسم D-074).
  final seenSkus = <String, int>{};
  final seenNames = <String, int>{};
  for (final row in parse.rows) {
    if (seenSkus.containsKey(row.sku)) {
      errors.add(ImportError(
        row: row.row,
        column: 1,
        value: row.sku,
        dqCode: dqImportInternalDuplicate,
        description: 'الكود مكرر داخل الملف نفسه (صف ${seenSkus[row.sku]}) '
            '— التكرار الداخلي خطأ فادح.',
        suggestedAction: 'وحّد صفَّي الكود أو احذف الزائد ثم أعد '
            'الاستيراد.',
      ));
    } else {
      seenSkus[row.sku] = row.row;
    }
    if (seenNames.containsKey(row.name)) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportInternalDuplicate,
        description: 'الاسم مكرر داخل الملف نفسه (صف ${seenNames[row.name]}) '
            '— منع تكرار الاسم الحرفي D-074.',
        suggestedAction: 'وحّد صفَّي الاسم أو ميّزهما ثم أعد الاستيراد.',
      ));
    } else {
      seenNames[row.name] = row.row;
    }
  }

  // خطة الوحدات: الموجود بالاسم يُعاد بمعرّفه، والغائب يُنشأ آلياً
  // مرة واحدة بلا تكرار (§25.4).
  final unitIdByName = <String, int>{};
  final unitNamesSeen = <String>{};
  for (final row in parse.rows) {
    final unitKey = row.unit.trim();
    if (unitNamesSeen.contains(unitKey)) continue;
    unitNamesSeen.add(unitKey);
    final holder = units.byLiteralName(unitKey);
    if (holder != null) {
      unitIdByName[unitKey] = holder.id;
    } else {
      unitCreates.add(unitKey);
    }
  }

  for (final row in parse.rows) {
    final currency = currencies[normalizeCurrencyCode(row.priceCurrencyCode)];
    if (currency == null) {
      errors.add(ImportError(
        row: row.row,
        column: 4,
        value: row.priceCurrencyCode,
        dqCode: dqImportReferenceMissing,
        description: 'العملة ${row.priceCurrencyCode} غير معرفة '
            'بالتطبيق.',
        suggestedAction: 'أضف العملة من شاشة العملات أولاً أو صحّح '
            'الكود (الفراغ يعني الأساسية SYP).',
      ));
      continue;
    }

    // الأسعار بدقة عملة السعر — الصفر مشروع «بلا سعر بعد» والفراغ
    // صفر (موثق بالقالب)، ولا تقريب صامت لخانة زائدة.
    int? purchaseMinor;
    int? saleMinor;
    var rowFatal = false;
    final purchaseRaw = row.purchasePriceRaw;
    final saleRaw = row.salePriceRaw;
    if (purchaseRaw != null) {
      final minor = decimalPartsToMinor(
          parseHumanDecimal(purchaseRaw)!, currency.minorUnits);
      if (minor == null) {
        errors.add(ImportError(
          row: row.row,
          column: 5,
          value: row.purchasePriceRaw,
          dqCode: dqImportRowInvalid,
          description: 'خانات الكسر تفوق دقة العملة ${currency.code} '
              '(${currency.minorUnits} خانات) — لا تقريب صامت.',
          suggestedAction: 'صحّح السعر بدقة العملة أو اتركه فارغاً.',
        ));
        rowFatal = true;
      } else {
        purchaseMinor = minor;
      }
    }
    if (saleRaw != null) {
      final minor = decimalPartsToMinor(
          parseHumanDecimal(saleRaw)!, currency.minorUnits);
      if (minor == null) {
        errors.add(ImportError(
          row: row.row,
          column: 6,
          value: row.salePriceRaw,
          dqCode: dqImportRowInvalid,
          description: 'خانات الكسر تفوق دقة العملة ${currency.code} '
              '(${currency.minorUnits} خانات) — لا تقريب صامت.',
          suggestedAction: 'صحّح السعر بدقة العملة أو اتركه فارغاً.',
        ));
        rowFatal = true;
      } else {
        saleMinor = minor;
      }
    }
    if (rowFatal) continue;

    final holderBySku = existing.bySkuKey(row.sku);
    if (holderBySku != null) {
      if (policy == ImportExistingPolicy.addNew) {
        skipped.add(ItemImportSkip(
          row: row.row,
          sku: row.sku,
          existingLabel: holderBySku.displayLabel,
        ));
        if (holderBySku.name != row.name) {
          differences.add(ImportDifference(
            row: row.row,
            columnKey: 'name',
            columnLabel: 'الاسم',
            oldValue: holderBySku.name,
            newValue: row.name,
            updated: false,
            note: 'الموجود يُتخطى بسياسة «إضافة جديد».',
          ));
        }
        continue;
      }
      // سياسة التحديث — الوصفيّات القابلة (د-2): الاسم والسعران.
      final details = existingDetails[holderBySku.id];
      final unitName = details?.unitName ?? '';
      if (unitName.isNotEmpty && unitName != row.unit) {
        differences.add(ImportDifference(
          row: row.row,
          columnKey: 'unit',
          columnLabel: 'الوحدة',
          oldValue: unitName,
          newValue: row.unit,
          updated: false,
          note: 'وحدة الصنف القائم لا تتغير بالاستيراد في v1 — '
              'حماية أرصدة المخزون القائمة بوحدتها.',
        ));
      }
      var hasChange = false;
      if (holderBySku.name != row.name) {
        differences.add(ImportDifference(
          row: row.row,
          columnKey: 'name',
          columnLabel: 'الاسم',
          oldValue: holderBySku.name,
          newValue: row.name,
          updated: true,
        ));
        hasChange = true;
      }
      final newPurchase = purchaseMinor;
      final newSale = saleMinor;
      final detailMinorUnits = details == null
          ? 2
          : (currenciesById[details.priceCurrencyId]?.minorUnits ?? 2);
      if (newPurchase != null) {
        differences.add(ImportDifference(
          row: row.row,
          columnKey: 'purchase_price',
          columnLabel: 'سعر الشراء',
          oldValue: details == null
              ? '—'
              : formatMinorHuman(
                  details.purchasePriceMinor, detailMinorUnits),
          newValue: formatMinorHuman(newPurchase, currency.minorUnits),
          updated: true,
        ));
        hasChange = true;
      }
      if (newSale != null) {
        differences.add(ImportDifference(
          row: row.row,
          columnKey: 'sale_price',
          columnLabel: 'سعر البيع',
          oldValue: details == null
              ? '—'
              : formatMinorHuman(
                  details.salePriceMinor, detailMinorUnits),
          newValue: formatMinorHuman(newSale, currency.minorUnits),
          updated: true,
        ));
        hasChange = true;
      }
      if (hasChange) {
        updates.add(ItemImportUpdate(
          row: row.row,
          itemId: holderBySku.id,
          currentName: holderBySku.name,
          newName: holderBySku.name == row.name ? null : row.name,
          currentPurchasePriceMinor: details?.purchasePriceMinor ?? 0,
          newPurchasePriceMinor: newPurchase,
          currentSalePriceMinor: details?.salePriceMinor ?? 0,
          newSalePriceMinor: newSale,
        ));
      } else {
        skipped.add(ItemImportSkip(
          row: row.row,
          sku: row.sku,
          existingLabel: holderBySku.displayLabel,
        ));
      }
      continue;
    }

    // صنف جديد — الاسم الحرفي لا يصطدم بصنف آخر (D-074).
    final nameHolder = existing.byLiteralName(row.name);
    if (nameHolder != null) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportConflictExisting,
        description: 'الاسم مستخدم للصنف: ${nameHolder.displayLabel} '
            '— منع تكرار الاسم الحرفي (D-074).',
        suggestedAction: 'غيّر الاسم أو استخدم سياسة التحديث.',
      ));
      continue;
    }

    final unitKey = row.unit.trim();
    final unitId = unitIdByName[unitKey];
    creates.add(ItemImportCreate(
      row: row.row,
      sku: row.sku,
      name: row.name,
      unitName: unitKey,
      baseUnitId: unitId ?? -1,
      priceCurrencyId: currency.id,
      purchasePriceMinor: purchaseMinor ?? 0,
      salePriceMinor: saleMinor ?? 0,
    ));
  }

  return ItemsImportPlan(
    unitCreates: unitCreates,
    creates: creates,
    updates: updates,
    skipped: skipped,
    errors: errors,
    differences: differences,
    policy: policy,
    semicolonUsed: parse.semicolonUsed,
    overSoftLimit: parse.overSoftLimit,
    totalDataRows: parse.totalDataRows,
  );
}

// ═══════════════════════════════════════════════════════════════
// القوالب والتقارير — ما نصدّره هو ما نستورده (مرآة F-166)
// ═══════════════════════════════════════════════════════════════

/// القالب الفارغ نصاً — يُصدَّر من التطبيق بترميز UTF-8 مع BOM: سطر
/// الترويسة (اسم القالب وإصداره) ثم عناوين الأعمدة الثابتة.
String buildEmptyTemplateCsv(ImportTemplateId id) {
  final template = importTemplateOf(id)!;
  final buffer = StringBuffer(csvUtf8Bom);
  buffer.writeln(template.markerLine);
  buffer.writeln([for (final c in template.columns) csvEscapeField(c.label)]
      .join(importSeparatorComma));
  return buffer.toString();
}

/// تقرير أخطاء الاستيراد CSV — رقم الصف والعمود والقيمة والرمز
/// والوصف والإجراء (§25.5) ببنية تقرير F-166 ذاتها.
String buildImportErrorReportCsv(List<ImportError> errors) {
  final rows = <List<String>>[
    for (final e in errors)
      [
        e.row == 0 ? '—' : '${e.row}',
        e.column == null ? '—' : '${e.column}',
        e.value ?? '—',
        e.dqCode,
        e.description,
        e.suggestedAction,
      ],
  ];
  return buildCsvSnapshot(
    title: 'تقرير أخطاء الاستيراد',
    columns: const [
      'الصف',
      'العمود',
      'القيمة',
      'الرمز',
      'الوصف',
      'الإجراء المقترح',
    ],
    rows: rows,
  );
}

/// تقرير فروق التحديث CSV — المحْدَث والمُترك بسبيه (§25.3.2).
String buildImportDiffReportCsv(List<ImportDifference> differences) {
  final rows = <List<String>>[
    for (final d in differences)
      [
        '${d.row}',
        d.columnLabel,
        d.oldValue,
        d.newValue,
        d.updated ? 'سيُحدَّث' : 'لن يُحدَّث',
        d.note ?? '',
      ],
  ];
  return buildCsvSnapshot(
    title: 'تقرير فروق التحديث — وصفيفات فقط في v1 (د-2)',
    columns: const ['الصف', 'العمود', 'القائم', 'الملف', 'الحكم', 'ملاحظة'],
    rows: rows,
  );
}

// ═══════════════════════════════════════════════════════════════
// الدفعة الثانية (س141 — §25.11): أرصدة أول المدة — الوحدتان 4 و5.
//
// القرارات الحاكمة الموثقة:
// - د-1/د-6: المقابل 332 «جاري النتيجة (الافتتاح والإقفال)» يولَّد
//   آلياً — لا عمود مقابل بالملف إطلاقاً، وسطره واحد على الجهة التي
//   تمسك توازن القيد.
// - §25.4: الأرصدة موقّعة — سالب رصيد العميل رصيد دائن (وسالب رصيد
//   المورد مدين) مشروع بتحذير مراجعة بالمعاينة لا رفض.
// - د-6: الافتتاحي أول مستند مرحّل بالقاعدة — فحص آلي «لا قيود مرحّلة
//   قبل تاريخ القيد الافتتاحي» (DQ-1025) والتاريخ نفسه صالح ISO
//   وتحضنه فترة مفتوحة (DQ-1026).
// - 07 §1.7: سعر الملف لقطة تُخزَّن لحظة الاعتماد بلقطة سعر صرف على
//   أسطر القيد — والتحويل للأساسية بدقة تامة: أي باقٍ قسمة رفض لا
//   تقريب صامت، وطفح ضرب 64-بت حرس صريح قبل الرياضة.
// ═══════════════════════════════════════════════════════════════

/// رمزا تاريخ الافتتاحي (د-6) — س141.
const String dqImportOpeningDateInvalid = 'DQ-1026';
const String dqImportOpeningNotFirst = 'DQ-1025';

/// قيم عمود «القسم» بقالب الأرصدة الكاملة — العربية بقيم التخزين
/// واللاتينية مقبولة كذلك (نمط قيم النوع للأطراف).
const Map<String, String> openingSectionImportValues = {
  'ذمم': 'parties',
  'مخزون': 'inventory',
  'نقد': 'cash',
  'parties': 'parties',
  'inventory': 'inventory',
  'cash': 'cash',
};

/// مقياس السعر المكبَّر الموحد (fxRateScale — 10^6) — موثقاً هنا كي
/// تبقى وحدة الاستيراد ذاتية المرجع، وعدد خانات كسره أقصى ما يمثله.
const int importFxRateScale = fxRateScaleConst;
const int importFxRateMaxFracDigits = 6;

/// حد خانات الجزء الصحيح لسعر الصرف البشري — حرس طفح صريح: سعر يبلغ
/// المليار وحدة أساسية لكل وحدة رفض بلا رياضة تلف الأعداد.
const int importFxRateMaxIntDigits = 9;

/// عتبة انحراف سعر الملف عن آخر سعر مسجل — تحذير معاينة لا رفض
/// (§25.4: «مع تحذير انحراف بالمعاينة إن باعد عن آخر سعر مسجل بشكل
/// لافت» — عُشر القيمة فأكثر لافت).
const int importFxRateDeviationTenth = 10;

// ── الأعداد الموقّعة وأسعار الصرف ──────────────────────────────

/// عدد بشري موقّت — إشارة سلب واحدة يقوده حصراً (اصطلاح رصيد أول
/// المدة: سالب العميل دائن وسالب المورد مدين — §25.4).
class SignedDecimalParts {
  final bool negative;
  final DecimalParts parts;

  const SignedDecimalParts(this.negative, this.parts);
}

/// تحليل عدد بشري موقّت — كسالب يقود رصيداً أو موجب؛ يعيد null عند
/// الفراغ أو الفساد أو إشارة بلا رقم بعدها.
SignedDecimalParts? parseHumanSignedDecimal(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
    if (s.isEmpty) return null;
  }
  final parts = parseHumanDecimal(s);
  if (parts == null) return null;
  return SignedDecimalParts(negative, parts);
}

/// تحليل عمود سعر الصرف إلى مكبَّره — null عند الفساد أو تجاوز حدود
/// الدقة (خانات الكسر فوق 6) أو خانات الصحيح فوق الحرس (9).
int? _parseFxRateScaled(String raw) {
  final parts = parseHumanDecimal(raw);
  if (parts == null) return null;
  if (parts.intPart.length > importFxRateMaxIntDigits) return null;
  final scaled = decimalPartsToMinor(parts, importFxRateMaxFracDigits);
  if (scaled == null) return null;
  if (scaled <= 0) return null; // الصفر بلا معنى صرفي (نمط F-121)
  return scaled;
}

/// تحويل مبلغ بعملة المستند إلى الأساسية بلقطة سعره — بدقة تامة لا
/// تقريب صامت: أي باقٍ قسمةً رفضٌ صريح (خانة لا تمثل بالأساسية لا
/// يقدّرها المحرك)، وطفح ضرب الأعداد الصحيحة حرسٌ قبل الرياضة
/// (64-بت). يعيد null عند الرفضين.
int? convertDocMinorToBaseExact(int docMinor, int rateToBase) {
  if (docMinor < 0 || rateToBase <= 0) return null;
  const int64Max = 0x7FFFFFFFFFFFFFFF;
  if (docMinor > 0 && rateToBase > int64Max ~/ docMinor) return null;
  final product = docMinor * rateToBase;
  if (product % importFxRateScale != 0) return null;
  return product ~/ importFxRateScale;
}

// ── سياق تاريخ الافتتاحي المشترك (د-6) ─────────────────────────

/// سياق فحص تاريخ الافتتاحي — يُحقن من التخزين حياً: الفترات كافة
/// (المفتوحة والمقفلة كي يميز الفحص حالتيه) وأقدم قيد مرحّل.
class OpeningImportDateContext {
  final String openingDateText;
  final List<PeriodInfo> periods;
  final String? earliestPostedDateText;

  const OpeningImportDateContext({
    required this.openingDateText,
    required this.periods,
    this.earliestPostedDateText,
  });
}

/// فحص تاريخ الافتتاحي (د-6): صالح ISO وتحضنه فترة مفتوحة (لا فترة
/// أصلاً أو مقفلة — كلاهما DQ-1026 برسالتين صادقتين)، وأسبق من كل
/// قيد مرحّل (DQ-1025 — الافتتاحي أول مستند مرحّل بالقاعدة حرفاً).
List<ImportError> validateOpeningDateForImport(
    OpeningImportDateContext context) {
  final errors = <ImportError>[];
  final t = context.openingDateText.trim();
  if (!isValidIsoDate(t)) {
    errors.add(ImportError(
      row: 0,
      value: context.openingDateText,
      dqCode: dqImportOpeningDateInvalid,
      description: 'تاريخ الافتتاحي «${context.openingDateText}» ليس '
          'بتاريخ صالح (YYYY-MM-DD).',
      suggestedAction: 'اكتب تاريخ بداية السنة المالية بصيغته كاملة '
          '(مثال: 2026-01-01).',
    ));
    return errors;
  }
  final period = findPeriodForDate(context.periods, t);
  if (period == null || !period.isOpen) {
    errors.add(ImportError(
      row: 0,
      value: t,
      dqCode: dqImportOpeningDateInvalid,
      description: period == null
          ? 'لا فترة محاسبية تحضن تاريخ الافتتاحي $t.'
          : 'الفترة المحضنة لتاريخ الافتتاحي $t مقفلة.',
      suggestedAction: 'افتح الفترة من شاشة الفترات أو أصحح التاريخ '
          'إلى بداية سنة مالية مفتوحة.',
    ));
  }
  final earliest = context.earliestPostedDateText?.trim();
  if (earliest != null && earliest.isNotEmpty && t.compareTo(earliest) >= 0) {
    errors.add(ImportError(
      row: 0,
      value: t,
      dqCode: dqImportOpeningNotFirst,
      description: 'يوجد قيد مرحّل بتاريخ $earliest — الافتتاحي أول '
          'مستند مرحّل فتاريخه أسبق من كل مرحّل.',
      suggestedAction: 'قدّم تاريخ الافتتاحي قبل $earliest — أو استورد '
          'الأرصدة بقاعدة جديدة قبل أي ترحيل.',
    ));
  }
  return errors;
}

// ── الوحدة 4: أرصدة الذمم لأول المدة (§25.2 — ستة أعمدة) ───────

/// صف أرصدة ذمم خام بعد فحص الصيغة — القيم المنظمة قبل مرجع الدفعة.
class PartyBalanceRowRaw {
  final int row;

  /// كود الطرف — موجوداً فيُرفق به، أو غائباً فيُنشأ آلياً (§25.2).
  final String code;
  final String name;

  /// 'customer' أو 'supplier' — «عميل ومورد معاً» مرفوض صراحة: رصيد
  /// أول المدة جهة واحدة.
  final String kindStorage;

  /// الرصيد الموقّع كما ورد — موجب أو سالب (تحذير مراجعة لا رفض).
  final String balanceRaw;
  final String currencyCode;

  /// سعر الصرف الخام — إلزامي لغير الأساسية ومرفوض لفراغه.
  final String? fxRateRaw;

  const PartyBalanceRowRaw({
    required this.row,
    required this.code,
    required this.name,
    required this.kindStorage,
    required this.balanceRaw,
    required this.currencyCode,
    this.fxRateRaw,
  });
}

/// نتيجة تحليل ملف أرصدة الذمم.
class PartyBalancesFileParse {
  final List<PartyBalanceRowRaw> rows;
  final List<ImportError> errors;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const PartyBalancesFileParse({
    required this.rows,
    required this.errors,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isRejected => errors.isNotEmpty;
}

/// تحليل ملف أرصدة الذمم — طبقتا الملف والصف بمعايير النواة نفسها.
PartyBalancesFileParse parsePartyBalancesFile(List<int> bytes) {
  final raw = _parseRawFile(bytes, ImportTemplateId.partyBalances);
  final rows = <PartyBalanceRowRaw>[];
  final errors = List<ImportError>.of(raw.errors);

  for (final rec in raw.records) {
    final f = rec.fields;
    var rowOk = true;

    final code = sanitizeFreeName(f[0]);
    if (code.isEmpty) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'الكود إلزامي وصف فارغ مرفوض.',
        suggestedAction: 'املأ كود الطرف — به يرتبط الرصيد بذمته (D-062).',
      ));
    } else if (!isValidPartyNumber(code)) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'الكود خارج القائمة البيضاء: حروف وأرقام '
            'و «- _ .» حصراً بلا فراغ.',
        suggestedAction: 'صحّح كود الطرف إلى رمز من القائمة البيضاء.',
      ));
    }

    final name = sanitizeFreeName(f[1]);
    if (name.isEmpty) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم إلزامي (يُستخدم إنشاءً آلياً للطرف الغائب).',
        suggestedAction: 'املأ اسم الطرف أو استورده أولاً بوحدة الأطراف.',
      ));
    } else if (freeNameHasControlChars(name)) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم يحمل محارف تحكم خفية.',
        suggestedAction: 'أعد كتابة الاسم بلا لصق من مصدر يحمل علامات '
            'غير مرئية.',
      ));
    }

    final kindRaw = f[2].trim();
    final kind = partyKindImportValues[kindRaw] ??
        partyKindImportValues[kindRaw.toLowerCase()];
    if (kind == null) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 3,
        value: f[2],
        dqCode: dqImportRowInvalid,
        description: 'النوع إلزامي بقيمة معروفة: عميل أو مورد.',
        suggestedAction: 'اكتب «عميل» أو «مورد» حرفاً كما بالقالب.',
      ));
    } else if (kind == 'both') {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 3,
        value: f[2],
        dqCode: dqImportRowInvalid,
        description: 'رصيد أول المدة جهة واحدة — «عميل ومورد معاً» لا '
            'يُستورد رصيداً افتتاحياً.',
        suggestedAction: 'قسّمه سطرين: سطر عميل وسطر مورد، أو اختر '
            'جهة واحدة.',
      ));
    }

    final balanceRaw = f[3].trim();
    final signed = parseHumanSignedDecimal(balanceRaw);
    if (signed == null) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 4,
        value: f[3],
        dqCode: dqImportRowInvalid,
        description: 'الرصيد عدد بشري سليم مع إشارة سالبة اختيارية — '
            'بلا فواصل آلاف ولا محارف غير رقمية.',
        suggestedAction: 'اكتب الرصيد رقماً (مثال: 150000 أو -2500.50).',
      ));
    } else if (signed.parts.intPart == '0' && signed.parts.fracPart.isEmpty) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 4,
        value: f[3],
        dqCode: dqImportRowInvalid,
        description: 'الرصيد صفر — لا أثر محاسبي له فلا يُستورد.',
        suggestedAction: 'احذف صف الرصيد الصفري من الملف.',
      ));
    }

    final currencyRaw = f[4].trim();
    final currencyCode =
        currencyRaw.isEmpty ? 'SYP' : normalizeCurrencyCode(currencyRaw);
    if (currencyRaw.isNotEmpty &&
        !RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 5,
        value: f[4],
        dqCode: dqImportRowInvalid,
        description: 'كود العملة ثلاثة أحرف لاتينية A-Z حصراً (ISO 4217).',
        suggestedAction: 'اكتب كود العملة (مثال: SYP أو USD) أو اتركه '
            'فارغاً للأساسية.',
      ));
    }

    final fxRaw = f[5].trim();
    if (currencyCode == 'SYP') {
      if (fxRaw.isNotEmpty) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 6,
          value: f[5],
          dqCode: dqImportRowInvalid,
          description: 'لا سعر صرف للعملة الأساسية — هي مقياس الكل.',
          suggestedAction: 'اترك عمود السعر فارغاً لأسطر الليرة أو صحّح '
              'عملة الصف.',
        ));
      }
    } else {
      if (fxRaw.isEmpty) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 6,
          value: f[5],
          dqCode: dqImportRowInvalid,
          description: 'سعر الصرف إلزامي لغير العملة الأساسية — رصيد '
              'بعملة بلا لقطة سعر لا يُحوَّل تخميناً.',
          suggestedAction: 'اكتب سعر صرف العملة إلى الأساسية (مثال: '
              '15000) — لقطة تُخزَّن لحظة الاعتماد.',
        ));
      } else if (_parseFxRateScaled(fxRaw) == null) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 6,
          value: f[5],
          dqCode: dqImportRowInvalid,
          description: 'سعر الصرف عدد بشري سليم حتى 6 خانات كسر وحتى 9 '
              'خانات صحيح — موجب حصراً.',
          suggestedAction: 'صحّح السعر (مثال: 15000 أو 0.85).',
        ));
      }
    }

    if (rowOk) {
      rows.add(PartyBalanceRowRaw(
        row: rec.line,
        code: code,
        name: name,
        kindStorage: kind!,
        balanceRaw: balanceRaw,
        currencyCode: currencyCode,
        fxRateRaw: fxRaw.isEmpty ? null : fxRaw,
      ));
    }
  }

  return PartyBalancesFileParse(
    rows: rows,
    errors: errors,
    semicolonUsed: raw.semicolonUsed,
    overSoftLimit: raw.records.length > importSoftRowLimit,
    totalDataRows: raw.records.length,
  );
}

/// سطر ذمم مفتتاح بالخطة — القيم النهائية جاهزة للمعاملة الواحدة.
/// [debit] اتجاه السطر على حساب السيطرة: العميل الموجب مدين (112) —
/// وسالبه دائن، والمورد الموجب دائن (211) — وسالبه مدين (§25.4).
/// [partyId] null للطرف المزمع إنشاؤه آلياً فيربطه التنفيذ بعد إدراجه.
class OpeningPartyLine {
  final int row;
  final int? partyId;
  final String code;
  final String name;
  final String kindStorage;
  final int currencyId;

  /// كود عملة السطر — لتجميع «فحص توازن الدفعة» بعملة المستند (د-6).
  final String currencyCode;
  final int docMinor;
  final bool debit;
  final int fxRate;
  final int baseMinor;

  const OpeningPartyLine({
    required this.row,
    this.partyId,
    required this.code,
    required this.name,
    required this.kindStorage,
    required this.currencyId,
    required this.currencyCode,
    required this.docMinor,
    required this.debit,
    required this.fxRate,
    required this.baseMinor,
  });
}

/// خطة استيراد أرصدة الذمم — الوحدة 4 كاملة.
class PartyBalancesImportPlan {
  final List<PartyImportCreate> partyCreates;
  final List<OpeningPartyLine> lines;
  final List<ImportError> errors;
  final List<ImportDifference> differences;

  /// تحذيرات مراجعة المعاينة (لا تمنع): انحراف السعر عن آخر مسجل،
  /// والأرصدة المعكوسة الاتجاه (سالب العميل / موجب معكوس المورد).
  final List<String> warnings;
  final String openingDateText;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const PartyBalancesImportPlan({
    required this.partyCreates,
    required this.lines,
    required this.errors,
    required this.differences,
    required this.warnings,
    required this.openingDateText,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isApprovable => errors.isEmpty;

  int get debitBaseMinor => lines
      .where((l) => l.debit)
      .fold(0, (sum, l) => sum + l.baseMinor);
  int get creditBaseMinor => lines
      .where((l) => !l.debit)
      .fold(0, (sum, l) => sum + l.baseMinor);

  /// مقابل 332 الآلي (د-6): الموجب دائن والسالب مدين والصفر بلا سطر.
  int get counterpartBaseMinor => debitBaseMinor - creditBaseMinor;

  /// تجميع الأرصدة بعملة المستند — «فحص توازن الدفعة» عرضاً (د-6).
  Map<String, int> totalsByCurrencyDocMinor() {
    final totals = <String, int>{};
    for (final l in lines) {
      totals[l.currencyCode] = (totals[l.currencyCode] ?? 0) + l.docMinor;
    }
    return totals;
  }
}

/// تخطيط أرصدة الذمم — طبقة الدفعة النقية: التكرار الداخلي، مرجع
/// العملة والسعر، التحويل التام، إرفاق الطرف القائم أو إنشاؤه، وفحص
/// التاريخ الافتتاحي (د-6). [existingKindByNumberKey] أنواع الأطراف
/// القائمة بمفتاح رقمها — لفرق عرض إساءة مطابقة النوع (لا تحديث ولا
/// رفض). [latestRateByCurrency] آخر سعر مسجل مكبَّراً — لتحذير الانحراف.
PartyBalancesImportPlan planPartyBalancesImport(
  PartyBalancesFileParse parse, {
  required Map<String, ImportCurrencyRef> currencies,
  required PartyUniquenessIndex existing,
  required OpeningImportDateContext dateContext,
  Map<String, String> existingKindByNumberKey = const {},
  Map<String, int> latestRateByCurrency = const {},
}) {
  final errors = List<ImportError>.of(parse.errors);
  errors.addAll(validateOpeningDateForImport(dateContext));
  final partyCreates = <PartyImportCreate>[];
  final lines = <OpeningPartyLine>[];
  final differences = <ImportDifference>[];
  final warnings = <String>[];

  // التكرار الداخلي — فادح رفض كلي: بالكود (D-063) وبالاسم للمنشآت.
  final seenCodes = <String, int>{};
  final seenNames = <String, int>{};
  for (final row in parse.rows) {
    final codeKey = partyNumberKey(row.code);
    if (seenCodes.containsKey(codeKey)) {
      errors.add(ImportError(
        row: row.row,
        column: 1,
        value: row.code,
        dqCode: dqImportInternalDuplicate,
        description: 'الكود مكرر داخل الملف نفسه (صف ${seenCodes[codeKey]}) '
            '— التكرار الداخلي خطأ فادح.',
        suggestedAction: 'وحّد صفَّي الكود أو احذف الزائد ثم أعد '
            'الاستيراد.',
      ));
    } else {
      seenCodes[codeKey] = row.row;
    }
    if (seenNames.containsKey(row.name)) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportInternalDuplicate,
        description: 'الاسم مكرر داخل الملف نفسه (صف ${seenNames[row.name]}) '
            '— منع تكرار الاسم الحرفي D-065.',
        suggestedAction: 'وحّد صفَّي الاسم أو ميّزهما ثم أعد الاستيراد.',
      ));
    } else {
      seenNames[row.name] = row.row;
    }
  }

  for (final row in parse.rows) {
    final currency =
        currencies[normalizeCurrencyCode(row.currencyCode)];
    if (currency == null) {
      errors.add(ImportError(
        row: row.row,
        column: 5,
        value: row.currencyCode,
        dqCode: dqImportReferenceMissing,
        description: 'العملة ${row.currencyCode} غير معرفة بالتطبيق.',
        suggestedAction: 'أضف العملة من شاشة العملات أولاً أو صحّح '
            'الكود (الفراغ يعني الأساسية SYP).',
      ));
      continue;
    }

    // السعر: الأساسية (SYP — عرف التوحيد المقلم D-017) هويته المعيارية
    // 10^6/1، وغيرها لقطة الملف الإلزامية.
    final int fxRate;
    if (currency.code == 'SYP') {
      fxRate = importFxRateScale;
    } else {
      final parsed = _parseFxRateScaled(row.fxRateRaw ?? '');
      if (parsed == null) {
        // عُرض خطأه بالتحليل — لا تكرار هنا برسالة ثانية.
        continue;
      }
      fxRate = parsed;
      final latest = latestRateByCurrency[normalizeCurrencyCode(
          row.currencyCode)];
      if (latest != null &&
          (fxRate - latest).abs() * importFxRateDeviationTenth > latest) {
        warnings.add(
            'صف ${row.row} — سعر ${row.currencyCode} بالملف '
            '(${displayRateToBase(fxRate)}) يباعد آخر سعر مسجل '
            '(${displayRateToBase(latest)}) بأكثر من عُشر قيمته.');
      }
    }

    // الرصيد بدقة عملته ثم التحويل التام للأساسية (لا تقريب صامت).
    final signed = parseHumanSignedDecimal(row.balanceRaw)!;
    final docMinor =
        decimalPartsToMinor(signed.parts, currency.minorUnits);
    if (docMinor == null) {
      errors.add(ImportError(
        row: row.row,
        column: 4,
        value: row.balanceRaw,
        dqCode: dqImportRowInvalid,
        description: 'خانات الكسر تفوق دقة العملة ${currency.code} '
            '(${currency.minorUnits} خانات) — لا تقريب صامت.',
        suggestedAction: 'صحّح الرصيد بدقة العملة.',
      ));
      continue;
    }
    final baseMinor = convertDocMinorToBaseExact(docMinor, fxRate);
    if (baseMinor == null) {
      errors.add(ImportError(
        row: row.row,
        column: 4,
        value: row.balanceRaw,
        dqCode: dqImportRowInvalid,
        description: 'تحويل الرصيد إلى الأساسية غير تام بهذا السعر — '
            'خانة لا تمثل بلا تقريب أو قيمة تبلغ حد الأعداد — رفض '
            'صريح لا صمت.',
        suggestedAction: 'عدّل الرصيد أو السعر بما يمثل بالأساسية '
            'تمثيلاً تاماً (بلا باقٍ قسمة).',
      ));
      continue;
    }

    final debit = (row.kindStorage == 'customer') != signed.negative;
    if (signed.negative) {
      final reversedLabel = row.kindStorage == 'customer'
          ? 'عميل برصيد دائن'
          : 'مورد برصيد مدين';
      warnings.add('صف ${row.row} — رصيد ${row.code} بسالب: '
          '$reversedLabel (مقلوب الاتجاه الطبيعي — مشروع ويثبت '
          'للمراجعة).');
    }

    // الطرف: القائم يُرفق به والغائب يُنشأ آلياً (§25.2).
    final holder = existing.byNumberKey(row.code);
    if (holder != null) {
      final existingKind =
          existingKindByNumberKey[holder.numberKey];
      if (existingKind != null &&
          existingKind != row.kindStorage &&
          existingKind != 'both') {
        differences.add(ImportDifference(
          row: row.row,
          columnKey: 'kind',
          columnLabel: 'النوع',
          oldValue: existingKind == 'customer' ? 'عميل' : 'مورد',
          newValue: row.kindStorage == 'customer' ? 'عميل' : 'مورد',
          updated: false,
          note: 'نوع الطرف القائم لا يتغير بالاستيراد (د-2) — الرصيد '
              'يقيد على جهة الملف.',
        ));
      }
      lines.add(OpeningPartyLine(
        row: row.row,
        partyId: holder.id,
        code: row.code,
        name: row.name,
        kindStorage: row.kindStorage,
        currencyId: currency.id,
        currencyCode: currency.code,
        docMinor: docMinor,
        debit: debit,
        fxRate: fxRate,
        baseMinor: baseMinor,
      ));
      continue;
    }

    final nameHolder = existing.byLiteralName(row.name);
    if (nameHolder != null) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportConflictExisting,
        description: 'الاسم مستخدم للطرف: ${nameHolder.displayLabel} '
            '— منع تكرار الاسم الحرفي (D-065).',
        suggestedAction: 'غيّر الاسم أو استخدم كود الطرف القائم نفسه '
            'لتربط رصيده به.',
      ));
      continue;
    }

    partyCreates.add(PartyImportCreate(
      row: row.row,
      number: row.code,
      name: row.name,
      kindStorage: row.kindStorage,
      currencyId: currency.id,
      creditLimitBaseMinor: null,
    ));
    lines.add(OpeningPartyLine(
      row: row.row,
      partyId: null,
      code: row.code,
      name: row.name,
      kindStorage: row.kindStorage,
      currencyId: currency.id,
      currencyCode: currency.code,
      docMinor: docMinor,
      debit: debit,
      fxRate: fxRate,
      baseMinor: baseMinor,
    ));
  }

  return PartyBalancesImportPlan(
    partyCreates: partyCreates,
    lines: lines,
    errors: errors,
    differences: differences,
    warnings: warnings,
    openingDateText: dateContext.openingDateText,
    semicolonUsed: parse.semicolonUsed,
    overSoftLimit: parse.overSoftLimit,
    totalDataRows: parse.totalDataRows,
  );
}

// ── الوحدة 5: الأرصدة الكاملة لأول المدة (§25.2 — تسعة أعمدة) ──
// القسم (ذمم/مخزون/نقد) يحدد معاني الأعمدة بلا تخمين: الكمية والوحدة
// للمخزون حصراً، والنوع للذمم حصراً، والكود بقسم النقد عملةُ الصندوق.

/// صف أرصدة كاملة خام بعد فحص الصيغة.
class OpeningFullRowRaw {
  final int row;

  /// 'parties' | 'inventory' | 'cash'.
  final String section;
  final String code;
  final String name;

  /// 'customer'/'supplier' — بقسم الذمم حصراً.
  final String? kindStorage;

  /// الكمية الخام — بقسم المخزون حصراً (عدد صحيح موجب بالأساسية).
  final String? qtyRaw;

  /// القيمة/الرصيد الخام — موقّع بقسم الذمم، موجب بالمخزون والنقد.
  final String valueRaw;

  /// الوحدة الخام — بقسم المخزون حصراً.
  final String? unit;
  final String currencyCode;
  final String? fxRateRaw;

  const OpeningFullRowRaw({
    required this.row,
    required this.section,
    required this.code,
    required this.name,
    this.kindStorage,
    this.qtyRaw,
    required this.valueRaw,
    this.unit,
    required this.currencyCode,
    this.fxRateRaw,
  });
}

/// نتيجة تحليل ملف الأرصدة الكاملة.
class OpeningFullFileParse {
  final List<OpeningFullRowRaw> rows;
  final List<ImportError> errors;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const OpeningFullFileParse({
    required this.rows,
    required this.errors,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isRejected => errors.isNotEmpty;
}

/// فحص عمودَي العملة والسعر المشترك — يعيد كود العملة المعياري ويكتب
/// أخطاءه بالقائمة (نمط النواة: كل الأخطاء دفعة واحدة).
String _openingCurrencyAndRateCheck({
  required List<String> f,
  required int row,
  required List<ImportError> errors,
  required int currencyColumn,
  required int fxColumn,
}) {
  final currencyRaw = f[currencyColumn].trim();
  final currencyCode =
      currencyRaw.isEmpty ? 'SYP' : normalizeCurrencyCode(currencyRaw);
  if (currencyRaw.isNotEmpty &&
      !RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
    errors.add(ImportError(
      row: row,
      column: currencyColumn + 1,
      value: f[currencyColumn],
      dqCode: dqImportRowInvalid,
      description: 'كود العملة ثلاثة أحرف لاتينية A-Z حصراً (ISO 4217).',
      suggestedAction: 'اكتب كود العملة (مثال: SYP أو USD) أو اتركه '
          'فارغاً للأساسية.',
    ));
    return currencyCode;
  }
  final fxRaw = f[fxColumn].trim();
  if (currencyCode == 'SYP') {
    if (fxRaw.isNotEmpty) {
      errors.add(ImportError(
        row: row,
        column: fxColumn + 1,
        value: f[fxColumn],
        dqCode: dqImportRowInvalid,
        description: 'لا سعر صرف للعملة الأساسية — هي مقياس الكل.',
        suggestedAction: 'اترك عمود السعر فارغاً لأسطر الليرة أو صحّح '
            'عملة الصف.',
      ));
    }
  } else {
    if (fxRaw.isEmpty) {
      errors.add(ImportError(
        row: row,
        column: fxColumn + 1,
        value: f[fxColumn],
        dqCode: dqImportRowInvalid,
        description: 'سعر الصرف إلزامي لغير العملة الأساسية — قيمة بعملة '
            'بلا لقطة سعر لا تُحوَّل تخميناً.',
        suggestedAction: 'اكتب سعر صرف العملة إلى الأساسية (مثال: 15000).',
      ));
    } else if (_parseFxRateScaled(fxRaw) == null) {
      errors.add(ImportError(
        row: row,
        column: fxColumn + 1,
        value: f[fxColumn],
        dqCode: dqImportRowInvalid,
        description: 'سعر الصرف عدد بشري سليم حتى 6 خانات كسر وحتى 9 '
            'خانات صحيح — موجب حصراً.',
        suggestedAction: 'صحّح السعر (مثال: 15000 أو 0.85).',
      ));
    }
  }
  return currencyCode;
}

/// تحليل ملف الأرصدة الكاملة — القسم يحكم الأعمدة: ما لا يملأ بقسمه
/// رفضٌ صريح لا تجاهل (بلا تخمين — §25.4).
OpeningFullFileParse parseOpeningFullFile(List<int> bytes) {
  final raw = _parseRawFile(bytes, ImportTemplateId.openingFull);
  final rows = <OpeningFullRowRaw>[];
  final errors = List<ImportError>.of(raw.errors);

  for (final rec in raw.records) {
    final f = rec.fields;
    var rowOk = true;

    final sectionRaw = f[0].trim();
    final section = openingSectionImportValues[sectionRaw] ??
        openingSectionImportValues[sectionRaw.toLowerCase()];
    if (section == null) {
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'القسم إلزامي بقيمة معروفة: ذمم أو مخزون أو نقد.',
        suggestedAction: 'اكتب أحد الأقسام الثلاثة حرفاً كما بالقالب.',
      ));
      continue;
    }

    // الأعمدة المشتركة: الكود (2) والاسم (3) والنوع (4) والكمية (5)
    // والقيمة (6) والوحدة (7) والعملة (8) والسعر (9).
    final code = sanitizeFreeName(f[1]);
    final name = sanitizeFreeName(f[2]);
    final kindRaw = f[3].trim();
    final qtyRaw = f[4].trim();
    final valueRaw = f[5].trim();
    final unit = sanitizeFreeName(f[6]);
    final currencyCode = _openingCurrencyAndRateCheck(
      f: f,
      row: rec.line,
      errors: errors,
      currencyColumn: 7,
      fxColumn: 8,
    );
    final fxRaw = f[8].trim();

    if (section == 'parties') {
      if (code.isEmpty || !isValidPartyNumber(code)) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 2,
          value: f[1],
          dqCode: dqImportRowInvalid,
          description: 'كود الطرف إلزامي ومن القائمة البيضاء.',
          suggestedAction: 'املأ كود الطرف برمز من القائمة البيضاء.',
        ));
      }
      if (name.isEmpty) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 3,
          value: f[2],
          dqCode: dqImportRowInvalid,
          description: 'الاسم إلزامي بقسم الذمم (يُستخدم إنشاءً آلياً).',
          suggestedAction: 'املأ اسم الطرف أو اربط الرصيد بكوده القائم.',
        ));
      } else if (freeNameHasControlChars(name)) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 3,
          value: f[2],
          dqCode: dqImportRowInvalid,
          description: 'الاسم يحمل محارف تحكم خفية.',
          suggestedAction:
              'أعد كتابة الاسم بلا لصق من مصدر يحمل علامات غير مرئية.',
        ));
      }
      final kind = partyKindImportValues[kindRaw] ??
          partyKindImportValues[kindRaw.toLowerCase()];
      if (kind == null) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 4,
          value: f[3],
          dqCode: dqImportRowInvalid,
          description: 'النوع إلزامي بقسم الذمم: عميل أو مورد.',
          suggestedAction: 'اكتب «عميل» أو «مورد» حرفاً كما بالقالب.',
        ));
      } else if (kind == 'both') {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 4,
          value: f[3],
          dqCode: dqImportRowInvalid,
          description: 'رصيد أول المدة جهة واحدة — «عميل ومورد معاً» لا '
              'يُستورد رصيداً افتتاحياً.',
          suggestedAction: 'قسّمه سطرين: سطر عميل وسطر مورد.',
        ));
      }
      if (parseHumanSignedDecimal(valueRaw) == null ||
          (parseHumanSignedDecimal(valueRaw)!.parts.intPart == '0' &&
              parseHumanSignedDecimal(valueRaw)!.parts.fracPart.isEmpty)) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 6,
          value: f[5],
          dqCode: dqImportRowInvalid,
          description: 'الرصيد عدد بشري سليم غير صفري — بإشارة سالبة '
              'اختيارية.',
          suggestedAction: 'اكتب الرصيد رقماً (مثال: 150000 أو -2500.50).',
        ));
      }
      if (qtyRaw.isNotEmpty || unit.isNotEmpty) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: qtyRaw.isNotEmpty ? 5 : 7,
          value: qtyRaw.isNotEmpty ? f[4] : f[6],
          dqCode: dqImportRowInvalid,
          description: 'عمودا الكمية والوحدة لقسم المخزون حصراً — بقسم '
              'الذمم يُتركان فارغين.',
          suggestedAction: 'أفرغ عمودي الكمية والوحدة أو انقل الصف إلى '
              'قسم المخزون.',
        ));
      }
      if (rowOk) {
        rows.add(OpeningFullRowRaw(
          row: rec.line,
          section: section,
          code: code,
          name: name,
          kindStorage: partyKindImportValues[kindRaw] ??
              partyKindImportValues[kindRaw.toLowerCase()],
          valueRaw: valueRaw,
          currencyCode: currencyCode,
          fxRateRaw: fxRaw.isEmpty ? null : fxRaw,
        ));
      }
      continue;
    }

    if (section == 'inventory') {
      if (code.isEmpty || !isValidItemSku(code)) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 2,
          value: f[1],
          dqCode: dqImportRowInvalid,
          description: 'كود الصنف إلزامي (SKU) بقسم المخزون.',
          suggestedAction: 'املأ كود الصنف كما بوحدة الأصناف.',
        ));
      }
      if (name.isEmpty) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 3,
          value: f[2],
          dqCode: dqImportRowInvalid,
          description: 'الاسم إلزامي بقسم المخزون (يُستخدم إنشاءً آلياً).',
          suggestedAction: 'املأ اسم الصنف.',
        ));
      } else if (freeNameHasControlChars(name)) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 3,
          value: f[2],
          dqCode: dqImportRowInvalid,
          description: 'الاسم يحمل محارف تحكم خفية.',
          suggestedAction:
              'أعد كتابة الاسم بلا لصق من مصدر يحمل علامات غير مرئية.',
        ));
      }
      if (kindRaw.isNotEmpty) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 4,
          value: f[3],
          dqCode: dqImportRowInvalid,
          description: 'عمود النوع لقسم الذمم حصراً — بقسم المخزون '
              'يُترك فارغاً.',
          suggestedAction: 'أفرغ عمود النوع أو انقل الصف إلى قسم الذمم.',
        ));
      }
      if (unit.isEmpty) {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 7,
          value: f[6],
          dqCode: dqImportRowInvalid,
          description: 'الوحدة إلزامية بقسم المخزون (أساسية تنشأ آلياً '
              'إن غابت بالتطبيق).',
          suggestedAction: 'املأ وحدة الصنف (مثال: قطعة).',
        ));
      }
      final qtyParts = parseHumanDecimal(qtyRaw);
      if (qtyParts == null || qtyParts.fracDigits > 0 ||
          qtyParts.intPart == '0') {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 5,
          value: f[4],
          dqCode: dqImportRowInvalid,
          description: 'الكمية عدد صحيح موجب بالوحدة الأساسية — لا كسور '
          'بأرصدة المخزون الافتتاحية.',
          suggestedAction: 'اكتب الكمية عدداً صحيحاً (مثال: 120).',
        ));
      }
      final valueParts = parseHumanDecimal(valueRaw);
      if (valueParts == null || valueParts.intPart == '0') {
        rowOk = false;
        errors.add(ImportError(
          row: rec.line,
          column: 6,
          value: f[5],
          dqCode: dqImportRowInvalid,
          description: 'قيمة المخزون الافتتاحي موجبة غير صفرية — قيمة '
              'تاريخية من ملفك لا تقييم محرك.',
          suggestedAction: 'اكتب قيمة الصف رقماً موجباً بعملة الصف.',
        ));
      }
      if (rowOk) {
        rows.add(OpeningFullRowRaw(
          row: rec.line,
          section: section,
          code: code,
          name: name,
          qtyRaw: qtyRaw,
          valueRaw: valueRaw,
          unit: unit,
          currencyCode: currencyCode,
          fxRateRaw: fxRaw.isEmpty ? null : fxRaw,
        ));
      }
      continue;
    }

    // قسم النقد: الكود عملة الصندوق والقيمة مبلغها بعملتها.
    final cashCurrency = code.trim().isEmpty
        ? ''
        : normalizeCurrencyCode(code);
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(cashCurrency)) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'كود قسم النقد هو كود العملة — ثلاثة أحرف لاتينية '
            '(الصندوق عملة واحدة — 05 §3.3).',
        suggestedAction: 'اكتب كود العملة (مثال: USD) — لكل عملة صندوقها.',
      ));
    }
    final currencyColumnRaw = f[7].trim();
    if (currencyColumnRaw.isNotEmpty &&
        normalizeCurrencyCode(currencyColumnRaw) != cashCurrency) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 8,
        value: f[7],
        dqCode: dqImportRowInvalid,
        description: 'عمودا الكود والعملة لا يختلفان بقسم النقد — كلاهما '
            'عملة الصندوق نفسها.',
        suggestedAction: 'وحّد العملة بعمودَي الكود والعملة أو أفرغ عمود '
            'العملة.',
      ));
    }
    if (name.isNotEmpty || kindRaw.isNotEmpty ||
        qtyRaw.isNotEmpty || unit.isNotEmpty) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: name.isNotEmpty ? 3 : (kindRaw.isNotEmpty ? 4 : (qtyRaw.isNotEmpty ? 5 : 7)),
        value: name.isNotEmpty
            ? f[2]
            : (kindRaw.isNotEmpty
                ? f[3]
                : (qtyRaw.isNotEmpty ? f[4] : f[6])),
        dqCode: dqImportRowInvalid,
        description: 'أعمدة الاسم والنوع والكمية والوحدة ليست لقسم النقد '
            '— الصف عملة ومبلغ حصراً.',
        suggestedAction: 'أفرغ هذه الأعمدة أو انقل الصف إلى قسمه الصحيح.',
      ));
    }
    final cashValue = parseHumanDecimal(valueRaw);
    if (cashValue == null || cashValue.intPart == '0') {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 6,
        value: f[5],
        dqCode: dqImportRowInvalid,
        description: 'مبلغ النقد الافتتاحي موجب غير صفري بعملة الصندوق.',
        suggestedAction: 'اكتب المبلغ رقماً موجباً (مثال: 5000).',
      ));
    }
    if (rowOk) {
      rows.add(OpeningFullRowRaw(
        row: rec.line,
        section: section,
        code: cashCurrency,
        name: '',
        valueRaw: valueRaw,
        currencyCode: cashCurrency,
        fxRateRaw: fxRaw.isEmpty ? null : fxRaw,
      ));
    }
  }

  return OpeningFullFileParse(
    rows: rows,
    errors: errors,
    semicolonUsed: raw.semicolonUsed,
    overSoftLimit: raw.records.length > importSoftRowLimit,
    totalDataRows: raw.records.length,
  );
}

/// سطر مخزون مفتتاح بالخطة — قيمة تاريخية صريحة من الملف (لا تقييم
/// D-186 — رصيد أول المدة ماضٍ لا زيادة جرد).
class OpeningInventoryLine {
  final int row;

  /// null للصنف المزمع إنشاؤه آلياً.
  final int? itemId;
  final String sku;
  final String name;
  final String unitName;
  final int qtyBase;
  final int valueBaseMinor;

  /// س142 (الوحدة 3): عملة القيمة ولقطة سعرها للتحويل — توثَّق لقطة
  /// الاعتماد بسجل الأسعار (§25.4/07 §1.7). الوحدة 5 لا تحملها بأسطر
  /// المخزون (تحويلها تخطيطي) فافتراضاها الأساسية بهويته المعيارية.
  final int currencyId;
  final int fxRate;

  const OpeningInventoryLine({
    required this.row,
    this.itemId,
    required this.sku,
    required this.name,
    required this.unitName,
    required this.qtyBase,
    required this.valueBaseMinor,
    this.currencyId = 1,
    this.fxRate = importFxRateScale,
  });
}

/// سطر نقد مفتتاح بالخطة — عملة واحدة سطر واحد (الصندوق عملة واحدة).
class OpeningCashLine {
  final int row;
  final int currencyId;
  final String currencyCode;
  final int docMinor;
  final int fxRate;
  final int baseMinor;

  const OpeningCashLine({
    required this.row,
    required this.currencyId,
    required this.currencyCode,
    required this.docMinor,
    required this.fxRate,
    required this.baseMinor,
  });
}

/// خطة استيراد الأرصدة الكاملة — الوحدة 5 كاملة: إذن إدخال واحد
/// للكميات بقيمها (مقابله 332 — د-1) وقيد واحد للذمم والنقد بمقابل
/// 332، وبمجموعهما يمسك الميزان (07 §1.1).
class OpeningFullImportPlan {
  final List<PartyImportCreate> partyCreates;
  final List<ItemImportCreate> itemCreates;
  final List<String> unitCreates;
  final List<OpeningPartyLine> partyLines;
  final List<OpeningInventoryLine> inventoryLines;
  final List<OpeningCashLine> cashLines;
  final List<ImportError> errors;
  final List<ImportDifference> differences;
  final List<String> warnings;
  final String openingDateText;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const OpeningFullImportPlan({
    required this.partyCreates,
    required this.itemCreates,
    required this.unitCreates,
    required this.partyLines,
    required this.inventoryLines,
    required this.cashLines,
    required this.errors,
    required this.differences,
    required this.warnings,
    required this.openingDateText,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isApprovable => errors.isEmpty;

  int get receiptValueBaseMinor =>
      inventoryLines.fold(0, (sum, l) => sum + l.valueBaseMinor);

  int get partyDebitBaseMinor => partyLines
      .where((l) => l.debit)
      .fold(0, (sum, l) => sum + l.baseMinor);
  int get partyCreditBaseMinor => partyLines
      .where((l) => !l.debit)
      .fold(0, (sum, l) => sum + l.baseMinor);
  int get cashBaseMinor =>
      cashLines.fold(0, (sum, l) => sum + l.baseMinor);

  /// مقابل 332 بقيد الذمم والنقد — الموجب دائن والسالب مدين.
  int get counterpartBaseMinor =>
      partyDebitBaseMinor + cashBaseMinor - partyCreditBaseMinor;
}

/// تخطيط الأرصدة الكاملة — طبقة الدفعة النقية بمعايير الوحدة 4 نفسها
/// مع الوحدات والأصناف بنمط نواة الأصناف (الإنشاء الآلي مرة واحدة).
OpeningFullImportPlan planOpeningFullImport(
  OpeningFullFileParse parse, {
  required Map<String, ImportCurrencyRef> currencies,
  required PartyUniquenessIndex existingParties,
  required Map<String, String> existingPartyKindByNumberKey,
  required ItemUniquenessIndex existingItems,
  required Map<int, ExistingItemImportRef> existingItemDetails,
  required UnitUniquenessIndex units,
  required OpeningImportDateContext dateContext,
  Map<String, int> latestRateByCurrency = const {},
}) {
  final errors = List<ImportError>.of(parse.errors);
  errors.addAll(validateOpeningDateForImport(dateContext));
  final partyCreates = <PartyImportCreate>[];
  final itemCreates = <ItemImportCreate>[];
  final unitCreates = <String>[];
  final partyLines = <OpeningPartyLine>[];
  final inventoryLines = <OpeningInventoryLine>[];
  final cashLines = <OpeningCashLine>[];
  final differences = <ImportDifference>[];
  final warnings = <String>[];

  // التكرار الداخلي — فادح رفض كلي: طرف بكوده، صنف بكوده، نقد بعملته،
  // والاسم الحرفي لمنشآت الذمم والأصناف (D-065/D-074).
  final seenPartyCodes = <String, int>{};
  final seenPartyNames = <String, int>{};
  final seenSkus = <String, int>{};
  final seenItemNames = <String, int>{};
  final seenCashCurrencies = <String, int>{};
  for (final row in parse.rows) {
    switch (row.section) {
      case 'parties':
        final codeKey = partyNumberKey(row.code);
        if (seenPartyCodes.containsKey(codeKey)) {
          errors.add(ImportError(
            row: row.row,
            column: 2,
            value: row.code,
            dqCode: dqImportInternalDuplicate,
            description: 'كود الطرف مكرر داخل الملف (صف '
                '${seenPartyCodes[codeKey]}) — التكرار الداخلي خطأ فادح.',
            suggestedAction: 'وحّد صفَّي الكود أو احذف الزائد.',
          ));
        } else {
          seenPartyCodes[codeKey] = row.row;
        }
        if (seenPartyNames.containsKey(row.name)) {
          errors.add(ImportError(
            row: row.row,
            column: 3,
            value: row.name,
            dqCode: dqImportInternalDuplicate,
            description: 'الاسم مكرر داخل الملف (صف ${seenPartyNames[row.name]}) '
                '— منع تكرار الاسم الحرفي D-065.',
            suggestedAction: 'وحّد صفَّي الاسم أو ميّزهما.',
          ));
        } else {
          seenPartyNames[row.name] = row.row;
        }
      case 'inventory':
        if (seenSkus.containsKey(row.code)) {
          errors.add(ImportError(
            row: row.row,
            column: 2,
            value: row.code,
            dqCode: dqImportInternalDuplicate,
            description: 'كود الصنف مكرر داخل الملف (صف ${seenSkus[row.code]}) '
                '— التكرار الداخلي خطأ فادح.',
            suggestedAction: 'وحّد صفَّي الكود أو احذف الزائد.',
          ));
        } else {
          seenSkus[row.code] = row.row;
        }
        if (seenItemNames.containsKey(row.name)) {
          errors.add(ImportError(
            row: row.row,
            column: 3,
            value: row.name,
            dqCode: dqImportInternalDuplicate,
            description: 'الاسم مكرر داخل الملف (صف ${seenItemNames[row.name]}) '
                '— منع تكرار الاسم الحرفي D-074.',
            suggestedAction: 'وحّد صفَّي الاسم أو ميّزهما.',
          ));
        } else {
          seenItemNames[row.name] = row.row;
        }
      case 'cash':
        if (seenCashCurrencies.containsKey(row.currencyCode)) {
          errors.add(ImportError(
            row: row.row,
            column: 2,
            value: row.code,
            dqCode: dqImportInternalDuplicate,
            description: 'عملة النقد ${row.currencyCode} مكررة (صف '
                '${seenCashCurrencies[row.currencyCode]}) — لكل عملة سطر '
                'واحد وصندوقها واحد.',
            suggestedAction: 'اجمع مبلغ العملة بسطر واحد.',
          ));
        } else {
          seenCashCurrencies[row.currencyCode] = row.row;
        }
    }
  }

  // خطة الوحدات: الموجود بالاسم يُعاد بمعرّفه والغائب يُنشأ مرة واحدة.
  final unitIdByName = <String, int>{};
  final unitNamesSeen = <String>{};
  for (final row in parse.rows) {
    if (row.section != 'inventory') continue;
    final unitKey = row.unit?.trim() ?? '';
    if (unitKey.isEmpty || unitNamesSeen.contains(unitKey)) continue;
    unitNamesSeen.add(unitKey);
    final holder = units.byLiteralName(unitKey);
    if (holder != null) {
      unitIdByName[unitKey] = holder.id;
    } else {
      unitCreates.add(unitKey);
    }
  }

  // حل سعر الصرف والعملة المشترك — يعيد null وقد كتب خطأه.
  (ImportCurrencyRef, int)? resolveCurrency(String currencyCode, int row,
      String? fxRateRaw, int fxColumn, String valueLabel) {
    final currency = currencies[normalizeCurrencyCode(currencyCode)];
    if (currency == null) {
      errors.add(ImportError(
        row: row,
        column: 8,
        value: currencyCode,
        dqCode: dqImportReferenceMissing,
        description: 'العملة $currencyCode غير معرفة بالتطبيق.',
        suggestedAction: 'أضف العملة من شاشة العملات أولاً (الفراغ يعني '
            'الأساسية SYP).',
      ));
      return null;
    }
    final int fxRate;
    if (currency.code == 'SYP') {
      fxRate = importFxRateScale;
    } else {
      final parsed = _parseFxRateScaled(fxRateRaw ?? '');
      if (parsed == null) return null; // عُرض خطأه بالتحليل
      fxRate = parsed;
      final latest =
          latestRateByCurrency[normalizeCurrencyCode(currencyCode)];
      if (latest != null &&
          (fxRate - latest).abs() * importFxRateDeviationTenth > latest) {
        warnings.add('صف $row — سعر $currencyCode بالملف '
            '(${displayRateToBase(fxRate)}) يباعد آخر سعر مسجل '
            '(${displayRateToBase(latest)}) بأكثر من عُشر قيمته.');
      }
    }
    return (currency, fxRate);
  }

  for (final row in parse.rows) {
    if (row.section == 'parties') {
      final resolved = resolveCurrency(
          row.currencyCode, row.row, row.fxRateRaw, 9, 'الرصيد');
      if (resolved == null) continue;
      final (currency, fxRate) = resolved;
      final signed = parseHumanSignedDecimal(row.valueRaw)!;
      final docMinor =
          decimalPartsToMinor(signed.parts, currency.minorUnits);
      if (docMinor == null) {
        errors.add(ImportError(
          row: row.row,
          column: 6,
          value: row.valueRaw,
          dqCode: dqImportRowInvalid,
          description: 'خانات الكسر تفوق دقة العملة ${currency.code} '
              '(${currency.minorUnits} خانات) — لا تقريب صامت.',
          suggestedAction: 'صحّح الرصيد بدقة العملة.',
        ));
        continue;
      }
      final baseMinor = convertDocMinorToBaseExact(docMinor, fxRate);
      if (baseMinor == null) {
        errors.add(ImportError(
          row: row.row,
          column: 6,
          value: row.valueRaw,
          dqCode: dqImportRowInvalid,
          description: 'تحويل الرصيد إلى الأساسية غير تام بهذا السعر — '
              'رفض صريح لا تقريب صامت.',
          suggestedAction: 'عدّل الرصيد أو السعر بما يمثل بالأساسية '
              'تمثيلاً تاماً.',
        ));
        continue;
      }
      final debit = (row.kindStorage == 'customer') != signed.negative;
      if (signed.negative) {
        final reversedLabel = row.kindStorage == 'customer'
            ? 'عميل برصيد دائن'
            : 'مورد برصيد مدين';
        warnings.add('صف ${row.row} — رصيد ${row.code} بسالب: '
            '$reversedLabel (مقلوب الاتجاه الطبيعي — مشروع ويثبت '
            'للمراجعة).');
      }
      final holder = existingParties.byNumberKey(row.code);
      if (holder != null) {
        final existingKind =
            existingPartyKindByNumberKey[holder.numberKey];
        if (existingKind != null &&
            existingKind != row.kindStorage &&
            existingKind != 'both') {
          differences.add(ImportDifference(
            row: row.row,
            columnKey: 'kind',
            columnLabel: 'النوع',
            oldValue: existingKind == 'customer' ? 'عميل' : 'مورد',
            newValue: row.kindStorage == 'customer' ? 'عميل' : 'مورد',
            updated: false,
            note: 'نوع الطرف القائم لا يتغير بالاستيراد (د-2).',
          ));
        }
        partyLines.add(OpeningPartyLine(
          row: row.row,
          partyId: holder.id,
          code: row.code,
          name: row.name,
          kindStorage: row.kindStorage!,
          currencyId: currency.id,
          currencyCode: currency.code,
          docMinor: docMinor,
          debit: debit,
          fxRate: fxRate,
          baseMinor: baseMinor,
        ));
        continue;
      }
      final nameHolder = existingParties.byLiteralName(row.name);
      if (nameHolder != null) {
        errors.add(ImportError(
          row: row.row,
          column: 3,
          value: row.name,
          dqCode: dqImportConflictExisting,
          description: 'الاسم مستخدم للطرف: ${nameHolder.displayLabel} '
              '— منع تكرار الاسم الحرفي (D-065).',
          suggestedAction: 'غيّر الاسم أو استخدم كود الطرف القائم.',
        ));
        continue;
      }
      partyCreates.add(PartyImportCreate(
        row: row.row,
        number: row.code,
        name: row.name,
        kindStorage: row.kindStorage!,
        currencyId: currency.id,
        creditLimitBaseMinor: null,
      ));
      partyLines.add(OpeningPartyLine(
        row: row.row,
        partyId: null,
        code: row.code,
        name: row.name,
        kindStorage: row.kindStorage!,
        currencyId: currency.id,
        currencyCode: currency.code,
        docMinor: docMinor,
        debit: debit,
        fxRate: fxRate,
        baseMinor: baseMinor,
      ));
      continue;
    }

    if (row.section == 'inventory') {
      final resolved = resolveCurrency(
          row.currencyCode, row.row, row.fxRateRaw, 9, 'القيمة');
      if (resolved == null) continue;
      final (currency, fxRate) = resolved;
      final valueParts = parseHumanDecimal(row.valueRaw)!;
      final docMinor =
          decimalPartsToMinor(valueParts, currency.minorUnits);
      if (docMinor == null) {
        errors.add(ImportError(
          row: row.row,
          column: 6,
          value: row.valueRaw,
          dqCode: dqImportRowInvalid,
          description: 'خانات الكسر تفوق دقة العملة ${currency.code} '
              '(${currency.minorUnits} خانات) — لا تقريب صامت.',
          suggestedAction: 'صحّح القيمة بدقة العملة.',
        ));
        continue;
      }
      final baseMinor = convertDocMinorToBaseExact(docMinor, fxRate);
      if (baseMinor == null) {
        errors.add(ImportError(
          row: row.row,
          column: 6,
          value: row.valueRaw,
          dqCode: dqImportRowInvalid,
          description: 'تحويل القيمة إلى الأساسية غير تام بهذا السعر — '
              'رفض صريح لا تقريب صامت.',
          suggestedAction: 'عدّل القيمة أو السعر بما يمثل بالأساسية '
              'تمثيلاً تاماً.',
        ));
        continue;
      }
      final qtyBase = int.parse(
          '${parseHumanDecimal(row.qtyRaw!)!.intPart}');
      final holder = existingItems.bySkuKey(row.code);
      if (holder != null) {
        final details = existingItemDetails[holder.id];
        if (details != null && details.unitName != row.unit) {
          differences.add(ImportDifference(
            row: row.row,
            columnKey: 'unit',
            columnLabel: 'الوحدة',
            oldValue: details.unitName,
            newValue: row.unit ?? '',
            updated: false,
            note: 'وحدة الصنف القائم لا تتغير بالاستيراد — الكمية '
                'بوحدة الصنف القائمة نفسها.',
          ));
        }
        inventoryLines.add(OpeningInventoryLine(
          row: row.row,
          itemId: holder.id,
          sku: row.code,
          name: row.name,
          unitName: row.unit ?? '',
          qtyBase: qtyBase,
          valueBaseMinor: baseMinor,
        ));
        continue;
      }
      final nameHolder = existingItems.byLiteralName(row.name);
      if (nameHolder != null) {
        errors.add(ImportError(
          row: row.row,
          column: 3,
          value: row.name,
          dqCode: dqImportConflictExisting,
          description: 'الاسم مستخدم للصنف: ${nameHolder.displayLabel} '
              '— منع تكرار الاسم الحرفي D-074.',
          suggestedAction: 'غيّر الاسم أو استخدم كود الصنف القائم.',
        ));
        continue;
      }
      itemCreates.add(ItemImportCreate(
        row: row.row,
        sku: row.code,
        name: row.name,
        unitName: row.unit ?? '',
        baseUnitId: unitIdByName[row.unit] ?? -1,
        priceCurrencyId: currency.id,
        purchasePriceMinor: 0,
        salePriceMinor: 0,
      ));
      inventoryLines.add(OpeningInventoryLine(
        row: row.row,
        itemId: null,
        sku: row.code,
        name: row.name,
        unitName: row.unit ?? '',
        qtyBase: qtyBase,
        valueBaseMinor: baseMinor,
      ));
      continue;
    }

    // قسم النقد.
    final resolved =
        resolveCurrency(row.currencyCode, row.row, row.fxRateRaw, 9, 'المبلغ');
    if (resolved == null) continue;
    final (currency, fxRate) = resolved;
    final valueParts = parseHumanDecimal(row.valueRaw)!;
    final docMinor = decimalPartsToMinor(valueParts, currency.minorUnits);
    if (docMinor == null) {
      errors.add(ImportError(
        row: row.row,
        column: 6,
        value: row.valueRaw,
        dqCode: dqImportRowInvalid,
        description: 'خانات الكسر تفوق دقة العملة ${currency.code} '
            '(${currency.minorUnits} خانات) — لا تقريب صامت.',
        suggestedAction: 'صحّح المبلغ بدقة العملة.',
      ));
      continue;
    }
    final baseMinor = convertDocMinorToBaseExact(docMinor, fxRate);
    if (baseMinor == null) {
      errors.add(ImportError(
        row: row.row,
        column: 6,
        value: row.valueRaw,
        dqCode: dqImportRowInvalid,
        description: 'تحويل المبلغ إلى الأساسية غير تام بهذا السعر — '
            'رفض صريح لا تقريب صامت.',
        suggestedAction: 'عدّل المبلغ أو السعر بما يمثل بالأساسية '
            'تمثيلاً تاماً.',
      ));
      continue;
    }
    cashLines.add(OpeningCashLine(
      row: row.row,
      currencyId: currency.id,
      currencyCode: currency.code,
      docMinor: docMinor,
      fxRate: fxRate,
      baseMinor: baseMinor,
    ));
  }

  return OpeningFullImportPlan(
    partyCreates: partyCreates,
    itemCreates: itemCreates,
    unitCreates: unitCreates,
    partyLines: partyLines,
    inventoryLines: inventoryLines,
    cashLines: cashLines,
    errors: errors,
    differences: differences,
    warnings: warnings,
    openingDateText: dateContext.openingDateText,
    semicolonUsed: parse.semicolonUsed,
    overSoftLimit: parse.overSoftLimit,
    totalDataRows: parse.totalDataRows,
  );
}

// ═══════════════════════════════════════════════════════════════
// الدفعة الثالثة (س142 — §25.11 التشطيب): الوحدة 3 — كميات المخزون
// الافتتاحية. الوحدة الباقية من الخمس المعتمدة (§25.2) — لم تُسمَّ
// بدفعة بعينها في تفصيل الدفعات فالتشطيب يكمل الوحدات الخمس بعقدها:
// إذن إدخال مخزون قياسي (F-209 — 113 مديناً ومقابله 43 الافتراضي
// القابل للتغيير من المفعّل — لا 332 الافتتاحي)، بقيم الملف الصريحة
// تخطي تقييم D-186 (رصيد أول المدة ماضٍ لا زيادة جرد — روح س141)،
// وبلا أطراف ولا نقد (ذولاك للوحدتين 4 و5 حصراً).
// ═══════════════════════════════════════════════════════════════

/// صف كميات مخزون افتتاحية خام بعد فحص الصيغة — سبعة أعمدة: صنف
/// وكمية وقيمة ووحدة (§25.2 الوحدة 3) وعمود العملة دائم بعقد §25.4
/// وفراغه الأساسية.
class OpeningQtyRowRaw {
  final int row;
  final String code;
  final String name;
  final String qtyRaw;
  final String valueRaw;
  final String unit;
  final String currencyCode;

  /// سعر الصرف الخام — إلزامي لغير الأساسية ومرفوض لفراغه.
  final String? fxRateRaw;

  const OpeningQtyRowRaw({
    required this.row,
    required this.code,
    required this.name,
    required this.qtyRaw,
    required this.valueRaw,
    required this.unit,
    required this.currencyCode,
    this.fxRateRaw,
  });
}

/// نتيجة تحليل ملف كميات المخزون الافتتاحية.
class OpeningQtyFileParse {
  final List<OpeningQtyRowRaw> rows;
  final List<ImportError> errors;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const OpeningQtyFileParse({
    required this.rows,
    required this.errors,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isRejected => errors.isNotEmpty;
}

/// تحليل ملف كميات المخزون الافتتاحية — طبقتا الملف والصف بمعايير
/// قسم المخزون بالوحدة 5 نفسها (بلا تخمين — §25.4).
OpeningQtyFileParse parseOpeningQtyFile(List<int> bytes) {
  final raw = _parseRawFile(bytes, ImportTemplateId.openingQty);
  final rows = <OpeningQtyRowRaw>[];
  final errors = List<ImportError>.of(raw.errors);

  for (final rec in raw.records) {
    final f = rec.fields;
    var rowOk = true;

    // الأعمدة: الكود (1) والاسم (2) والكمية (3) والقيمة (4) والوحدة (5)
    // والعملة (6) والسعر (7).
    final code = sanitizeFreeName(f[0]);
    if (code.isEmpty || !isValidItemSku(code)) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 1,
        value: f[0],
        dqCode: dqImportRowInvalid,
        description: 'كود الصنف إلزامي (SKU).',
        suggestedAction: 'املأ كود الصنف كما بوحدة الأصناف.',
      ));
    }

    final name = sanitizeFreeName(f[1]);
    if (name.isEmpty) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم إلزامي (يُستخدم إنشاءً آلياً للصنف الغائب).',
        suggestedAction: 'املأ اسم الصنف أو استورده أولاً بوحدة الأصناف.',
      ));
    } else if (freeNameHasControlChars(name)) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 2,
        value: f[1],
        dqCode: dqImportRowInvalid,
        description: 'الاسم يحمل محارف تحكم خفية.',
        suggestedAction: 'أعد كتابة الاسم بلا لصق من مصدر يحمل علامات '
            'غير مرئية.',
      ));
    }

    final qtyRaw = f[2].trim();
    final qtyParts = parseHumanDecimal(qtyRaw);
    if (qtyParts == null || qtyParts.fracDigits > 0 ||
        qtyParts.intPart == '0') {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 3,
        value: f[2],
        dqCode: dqImportRowInvalid,
        description: 'الكمية عدد صحيح موجب بالوحدة الأساسية — لا كسور '
            'بأرصدة المخزون الافتتاحية.',
        suggestedAction: 'اكتب الكمية عدداً صحيحاً (مثال: 120).',
      ));
    }

    final valueRaw = f[3].trim();
    final valueParts = parseHumanDecimal(valueRaw);
    if (valueParts == null || valueParts.intPart == '0') {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 4,
        value: f[3],
        dqCode: dqImportRowInvalid,
        description: 'قيمة المخزون الافتتاحي موجبة غير صفرية — قيمة '
            'تاريخية من ملفك لا تقييم محرك.',
        suggestedAction: 'اكتب قيمة الصف رقماً موجباً بعملة الصف.',
      ));
    }

    final unit = sanitizeFreeName(f[4]);
    if (unit.isEmpty) {
      rowOk = false;
      errors.add(ImportError(
        row: rec.line,
        column: 5,
        value: f[4],
        dqCode: dqImportRowInvalid,
        description: 'الوحدة إلزامية (أساسية تنشأ آلياً إن غابت '
            'بالتطبيق).',
        suggestedAction: 'املأ وحدة الصنف (مثال: قطعة).',
      ));
    }

    final currencyCode = _openingCurrencyAndRateCheck(
      f: f,
      row: rec.line,
      errors: errors,
      currencyColumn: 5,
      fxColumn: 6,
    );
    final fxRaw = f[6].trim();

    if (rowOk) {
      rows.add(OpeningQtyRowRaw(
        row: rec.line,
        code: code,
        name: name,
        qtyRaw: qtyRaw,
        valueRaw: valueRaw,
        unit: unit,
        currencyCode: currencyCode,
        fxRateRaw: fxRaw.isEmpty ? null : fxRaw,
      ));
    }
  }

  return OpeningQtyFileParse(
    rows: rows,
    errors: errors,
    semicolonUsed: raw.semicolonUsed,
    overSoftLimit: raw.records.length > importSoftRowLimit,
    totalDataRows: raw.records.length,
  );
}

/// خطة استيراد كميات المخزون الافتتاحية — الوحدة 3 كاملة: إذن إدخال
/// واحد بقيم الملف الصريحة ومقابله 43 الافتراضي (F-209 — لا 332
/// الافتتاحي: هذا إذنُ مخزونٍ قياسي لا قيدُ افتتاحِ ذمم ونقد).
class OpeningQtyImportPlan {
  final List<ItemImportCreate> itemCreates;
  final List<String> unitCreates;
  final List<OpeningInventoryLine> inventoryLines;
  final List<ImportError> errors;
  final List<ImportDifference> differences;

  /// تحذيرات مراجعة المعاينة (لا تمنع): انحراف السعر عن آخر مسجل.
  final List<String> warnings;
  final String openingDateText;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalDataRows;

  const OpeningQtyImportPlan({
    required this.itemCreates,
    required this.unitCreates,
    required this.inventoryLines,
    required this.errors,
    required this.differences,
    required this.warnings,
    required this.openingDateText,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalDataRows,
  });

  bool get isApprovable => errors.isEmpty;

  int get receiptValueBaseMinor =>
      inventoryLines.fold(0, (sum, l) => sum + l.valueBaseMinor);
}

/// تخطيط كميات المخزون الافتتاحية — طبقة الدفعة النقية بمعايير قسم
/// المخزون بالوحدة 5 نفسها مع الوحدات والأصناف بنمط نواة الأصناف
/// (الإنشاء الآلي مرة واحدة).
OpeningQtyImportPlan planOpeningQtyImport(
  OpeningQtyFileParse parse, {
  required Map<String, ImportCurrencyRef> currencies,
  required ItemUniquenessIndex existingItems,
  required Map<int, ExistingItemImportRef> existingItemDetails,
  required UnitUniquenessIndex units,
  required OpeningImportDateContext dateContext,
  Map<String, int> latestRateByCurrency = const {},
}) {
  final errors = List<ImportError>.of(parse.errors);
  errors.addAll(validateOpeningDateForImport(dateContext));
  final itemCreates = <ItemImportCreate>[];
  final unitCreates = <String>[];
  final inventoryLines = <OpeningInventoryLine>[];
  final differences = <ImportDifference>[];
  final warnings = <String>[];

  // التكرار الداخلي — فادح رفض كلي: الصنف بكوده وبالاسم الحرفي
  // (D-074).
  final seenSkus = <String, int>{};
  final seenItemNames = <String, int>{};
  for (final row in parse.rows) {
    if (seenSkus.containsKey(row.code)) {
      errors.add(ImportError(
        row: row.row,
        column: 1,
        value: row.code,
        dqCode: dqImportInternalDuplicate,
        description: 'كود الصنف مكرر داخل الملف (صف ${seenSkus[row.code]}) '
            '— التكرار الداخلي خطأ فادح.',
        suggestedAction: 'وحّد صفَّي الكود أو احذف الزائد ثم أعد '
            'الاستيراد.',
      ));
    } else {
      seenSkus[row.code] = row.row;
    }
    if (seenItemNames.containsKey(row.name)) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportInternalDuplicate,
        description: 'الاسم مكرر داخل الملف (صف '
            '${seenItemNames[row.name]}) — منع تكرار الاسم الحرفي '
            'D-074.',
        suggestedAction: 'وحّد صفَّي الاسم أو ميّزهما ثم أعد الاستيراد.',
      ));
    } else {
      seenItemNames[row.name] = row.row;
    }
  }

  // خطة الوحدات: الموجود بالاسم يُعاد بمعرّفه والغائب يُنشأ مرة واحدة.
  final unitIdByName = <String, int>{};
  final unitNamesSeen = <String>{};
  for (final row in parse.rows) {
    final unitKey = row.unit.trim();
    if (unitKey.isEmpty || unitNamesSeen.contains(unitKey)) continue;
    unitNamesSeen.add(unitKey);
    final holder = units.byLiteralName(unitKey);
    if (holder != null) {
      unitIdByName[unitKey] = holder.id;
    } else {
      unitCreates.add(unitKey);
    }
  }

  for (final row in parse.rows) {
    // العملة والسعر: الأساسية هويته المعيارية 10^6/1، وغيرها لقطة
    // الملف الإلزامية بتحذير انحرافها عن آخر مسجل (§25.4).
    final currency = currencies[normalizeCurrencyCode(row.currencyCode)];
    if (currency == null) {
      errors.add(ImportError(
        row: row.row,
        column: 6,
        value: row.currencyCode,
        dqCode: dqImportReferenceMissing,
        description: 'العملة ${row.currencyCode} غير معرفة بالتطبيق.',
        suggestedAction: 'أضف العملة من شاشة العملات أولاً أو صحّح '
            'الكود (الفراغ يعني الأساسية SYP).',
      ));
      continue;
    }
    final int fxRate;
    if (currency.code == 'SYP') {
      fxRate = importFxRateScale;
    } else {
      final parsed = _parseFxRateScaled(row.fxRateRaw ?? '');
      if (parsed == null) {
        // عُرض خطأه بالتحليل — لا تكرار هنا برسالة ثانية.
        continue;
      }
      fxRate = parsed;
      final latest =
          latestRateByCurrency[normalizeCurrencyCode(row.currencyCode)];
      if (latest != null &&
          (fxRate - latest).abs() * importFxRateDeviationTenth > latest) {
        warnings.add('صف ${row.row} — سعر ${row.currencyCode} بالملف '
            '(${displayRateToBase(fxRate)}) يباعد آخر سعر مسجل '
            '(${displayRateToBase(latest)}) بأكثر من عُشر قيمته.');
      }
    }

    // القيمة بدقة عملتها ثم التحويل التام للأساسية (لا تقريب صامت).
    final valueParts = parseHumanDecimal(row.valueRaw)!;
    final docMinor = decimalPartsToMinor(valueParts, currency.minorUnits);
    if (docMinor == null) {
      errors.add(ImportError(
        row: row.row,
        column: 4,
        value: row.valueRaw,
        dqCode: dqImportRowInvalid,
        description: 'خانات الكسر تفوق دقة العملة ${currency.code} '
            '(${currency.minorUnits} خانات) — لا تقريب صامت.',
        suggestedAction: 'صحّح القيمة بدقة العملة.',
      ));
      continue;
    }
    final baseMinor = convertDocMinorToBaseExact(docMinor, fxRate);
    if (baseMinor == null) {
      errors.add(ImportError(
        row: row.row,
        column: 4,
        value: row.valueRaw,
        dqCode: dqImportRowInvalid,
        description: 'تحويل القيمة إلى الأساسية غير تام بهذا السعر — '
            'خانة لا تمثل بلا تقريب أو قيمة تبلغ حد الأعداد — رفض '
            'صريح لا صمت.',
        suggestedAction: 'عدّل القيمة أو السعر بما يمثل بالأساسية '
            'تمثيلاً تاماً (بلا باقٍ قسمة).',
      ));
      continue;
    }
    final qtyBase =
        int.parse('${parseHumanDecimal(row.qtyRaw)!.intPart}');

    // الصنف: القائم يُرفق به والغائب يُنشأ آلياً (§25.2).
    final holder = existingItems.bySkuKey(row.code);
    if (holder != null) {
      final details = existingItemDetails[holder.id];
      if (details != null && details.unitName != row.unit) {
        differences.add(ImportDifference(
          row: row.row,
          columnKey: 'unit',
          columnLabel: 'الوحدة',
          oldValue: details.unitName,
          newValue: row.unit,
          updated: false,
          note: 'وحدة الصنف القائم لا تتغير بالاستيراد — الكمية بوحدة '
              'الصنف القائمة نفسها.',
        ));
      }
      inventoryLines.add(OpeningInventoryLine(
        row: row.row,
        itemId: holder.id,
        sku: row.code,
        name: row.name,
        unitName: row.unit,
        qtyBase: qtyBase,
        valueBaseMinor: baseMinor,
        currencyId: currency.id,
        fxRate: fxRate,
      ));
      continue;
    }
    final nameHolder = existingItems.byLiteralName(row.name);
    if (nameHolder != null) {
      errors.add(ImportError(
        row: row.row,
        column: 2,
        value: row.name,
        dqCode: dqImportConflictExisting,
        description: 'الاسم مستخدم للصنف: ${nameHolder.displayLabel} '
            '— منع تكرار الاسم الحرفي D-074.',
        suggestedAction: 'غيّر الاسم أو استخدم كود الصنف القائم نفسه '
            'لتربط كميته به.',
      ));
      continue;
    }
    itemCreates.add(ItemImportCreate(
      row: row.row,
      sku: row.code,
      name: row.name,
      unitName: row.unit,
      baseUnitId: unitIdByName[row.unit] ?? -1,
      priceCurrencyId: currency.id,
      purchasePriceMinor: 0,
      salePriceMinor: 0,
    ));
    inventoryLines.add(OpeningInventoryLine(
      row: row.row,
      itemId: null,
      sku: row.code,
      name: row.name,
      unitName: row.unit,
      qtyBase: qtyBase,
      valueBaseMinor: baseMinor,
      currencyId: currency.id,
      fxRate: fxRate,
    ));
  }

  return OpeningQtyImportPlan(
    itemCreates: itemCreates,
    unitCreates: unitCreates,
    inventoryLines: inventoryLines,
    errors: errors,
    differences: differences,
    warnings: warnings,
    openingDateText: dateContext.openingDateText,
    semicolonUsed: parse.semicolonUsed,
    overSoftLimit: parse.overSoftLimit,
    totalDataRows: parse.totalDataRows,
  );
}
