// أدوات الصدمة المعتمدة — الحافظات الآلية الدائمة (D-211).
//
// اعتماد المنهجية س155 (بأمر المالك «قم باعتماد أدوات الصدمة») ثم بناء
// الحافظات الآلية س156 (بكلمة المالك «تابع» — الدفعة التنفيذية الموثقة
// بالمعلق). النقية حصراً (F-010): بلا Flutter ولا Drift ولا أي تبعية
// خارجية (N-001 صفرية التكلفة — أدوات مولدة محلياً لا حزم).
//
// **للاختبار حصراً**: لا مسار إنتاجي يستدعي شيئاً هنا — هذه بذور
// مولّدة حتمية (بذرة ثابتة لا عشوائية) وحافظات ملفات مسمومة وتالفة
// تمارس المفسّرات وبوابات الاستعادة بكل تسليم (10 §10 الجدولة).
//
// الحاكم نصاً (من تقرير المالك المعتمد): اختبار الصدمة لتطبيق محاسبي
// اختبارُ سلامة بيانات قبل أن يكون اختبار واجهة.

import 'dart:convert' show utf8;

import 'csv_export.dart' show csvUtf8Bom;
import 'import_core.dart' show ImportTemplateId, importTemplateOf;
import 'journal.dart' show AccountInfo, AccountType, NormalSide;
import 'reports.dart' show TrialBalanceRawLine;

// ═══════════════════════════════════════════════════════════════════
// الفئة 1 — ضغط البيانات: مولّد العينة الثقيلة المعتمدة
// (5,500 عميل + 1,000 مورد + 10,000 صنف + 500,000 قيد — D-211 بند 1)
// ═══════════════════════════════════════════════════════════════════

/// مواصفة العينة الثقيلة بأرقام التقرير المعتمدة، وعامل مقياس يقلصها
/// نسبياً (الشطر التخزيني بCI يعمل بمقياس 0.1 موثق — القياسات المطلقة
/// على العينة الكاملة بجهاز حقيقي عند بوابات الإصدار حصراً).
class HeavySampleSpec {
  /// 1.0 = العينة الكاملة بأرقام التقرير حرفاً.
  final double scale;

  const HeavySampleSpec({this.scale = 1.0});

  int get customers => (5500 * scale).round();
  int get suppliers => (1000 * scale).round();
  int get items => (10000 * scale).round();

  /// عدد القيود المزدوجة (كل قيد رجلان: مدين ودائن).
  int get moves => (500000 * scale).round();
}

/// بذرة طرف للعينة — بيانات نقية لا كيانات القاعدة، وأرقامها بقائمة
/// D-174 البيضاء (حروف وأرقام و «- _ .» حصراً).
class HeavyPartySeed {
  final String number;
  final String name;
  final String kindStorage;

  const HeavyPartySeed({
    required this.number,
    required this.name,
    required this.kindStorage,
  });
}

/// بذرة صنف للعينة.
class HeavyItemSeed {
  final String sku;
  final String name;

  const HeavyItemSeed({required this.sku, required this.name});
}

/// قيد مزدوج للعينة — رجلان متوازنتان على حسابين من الدليل المزروع.
class HeavyMoveSeed {
  final String number;
  final String dateText;
  final int debitAccountId;
  final int creditAccountId;
  final int amountMinor;

  const HeavyMoveSeed({
    required this.number,
    required this.dateText,
    required this.debitAccountId,
    required this.creditAccountId,
    required this.amountMinor,
  });
}

/// أطراف العينة: العملاء أولى فالموردون — حتمية بالبذرة ذاتها دائماً.
List<HeavyPartySeed> generateHeavyParties({double scale = 1.0}) {
  final spec = HeavySampleSpec(scale: scale);
  final rows = <HeavyPartySeed>[
    for (var i = 1; i <= spec.customers; i++)
      HeavyPartySeed(
        number: 'C${i.toString().padLeft(6, '0')}',
        name: 'عميل رقم $i',
        kindStorage: 'customer',
      ),
    for (var i = 1; i <= spec.suppliers; i++)
      HeavyPartySeed(
        number: 'S${i.toString().padLeft(6, '0')}',
        name: 'مورد رقم $i',
        kindStorage: 'supplier',
      ),
  ];
  return rows;
}

/// أصناف العينة — حتمية بالبذرة ذاتها.
List<HeavyItemSeed> generateHeavyItems({double scale = 1.0}) {
  final spec = HeavySampleSpec(scale: scale);
  return [
    for (var i = 1; i <= spec.items; i++)
      HeavyItemSeed(
        sku: 'P${i.toString().padLeft(6, '0')}',
        name: 'صنف رقم $i',
      ),
  ];
}

/// قيود العينة المزدوجة — مبلغ كل قيد حتمي من رقمه (لا عشوائية أبداً
/// فالفشل قابل للإعادة حرفاً)، والتواريخ داخل فترة مفتوحة افتراضية.
List<HeavyMoveSeed> generateHeavyMoves({
  double scale = 1.0,
  int debitAccountId = 4,
  int creditAccountId = 5,
  String dateText = '2026-01-15',
}) {
  final spec = HeavySampleSpec(scale: scale);
  return [
    for (var i = 1; i <= spec.moves; i++)
      HeavyMoveSeed(
        number: 'SH-${i.toString().padLeft(7, '0')}',
        dateText: dateText,
        debitAccountId: debitAccountId,
        creditAccountId: creditAccountId,
        amountMinor: 100000 + (i * 137) % 999999,
      ),
  ];
}

/// أسطر الميزان الخام من حركة العينة — سطران لكل قيد (المدين ثم
/// الدائن) بنفس المبلغ فالتوازن قيداً وقيداً بالبناء.
List<TrialBalanceRawLine> heavyMovesToTrialLines(List<HeavyMoveSeed> moves) =>
    [
      for (final m in moves) ...[
        TrialBalanceRawLine(
          accountId: m.debitAccountId,
          debitMinor: m.amountMinor,
          creditMinor: 0,
        ),
        TrialBalanceRawLine(
          accountId: m.creditAccountId,
          debitMinor: 0,
          creditMinor: m.amountMinor,
        ),
      ],
    ];

/// دليل مصغّر ورقي متسق لفحص الميزان النقي — حسابان بطبيعتين
/// متقابلتين (أصول مدينة وحقوق دائنة).
List<AccountInfo> heavySampleAccounts() => [
      const AccountInfo(
        id: 4,
        code: '1111',
        name: 'الصندوق',
        type: AccountType.asset,
        normalSide: NormalSide.debit,
        parentId: 3,
        isLeaf: true,
        isActive: true,
      ),
      const AccountInfo(
        id: 5,
        code: '3111',
        name: 'رأس المال',
        type: AccountType.equity,
        normalSide: NormalSide.credit,
        parentId: 3,
        isLeaf: true,
        isActive: true,
      ),
    ];

// ═══════════════════════════════════════════════════════════════════
// الفئة 5 — تلف الملفات: بناة التلف البايتي الموحدة
// ═══════════════════════════════════════════════════════════════════

/// عمليات تلف بايتية حتمية — العبث ببايت واحد هو العلة المختبرة
/// (نص D-211: عبث بايت واحد → رفض وسم GCM بلا مساس بالقاعدة الحية).
class CorruptedArtifacts {
  /// نسخة ببايت واحد مقلوب عند [index] — لا حقول تُفقد ولا طول يتغير.
  static List<int> flipByteAt(List<int> bytes, int index) {
    if (bytes.isEmpty) {
      throw ArgumentError('لا يُقلب بايت في ملف فارغ');
    }
    if (index < 0 || index >= bytes.length) {
      throw RangeError.index(index, bytes, 'index');
    }
    final copy = List<int>.of(bytes);
    copy[index] = (copy[index] ^ 0x5A) & 0xFF;
    return copy;
  }

  /// الملف مقصوصاً إلى [length] بايتة — محاكاة قصور كتابة/نقل.
  static List<int> truncateTo(List<int> bytes, int length) {
    if (length < 0 || length > bytes.length) {
      throw RangeError.range(length, 0, bytes.length, 'length');
    }
    return bytes.sublist(0, length);
  }

  /// نصف الملف الأخير مقطوع — الحالة الأشيع لقصور النقل.
  static List<int> truncateHalf(List<int> bytes) =>
      truncateTo(bytes, bytes.length ~/ 2);

  /// الملف فارغاً تماماً — صفري البايتات.
  static List<int> emptyBytes() => const <int>[];
}

// ═══════════════════════════════════════════════════════════════════
// الفئة 6 — الإدخال العدائي: حافظة الملفات المسمومة الدائمة
// ═══════════════════════════════════════════════════════════════════

/// ملف مسموم مسمّى — بايتاته جاهزة وتوقعه رموز الرفض (فارغ = أي رمز
/// DQ-10xx يكفي؛ القصد الفحص المنهجي لا تعليم المفسّر برمزه).
class PoisonedFile {
  final String id;
  final String note;
  final List<int> bytes;

  /// رموز الرفض المرقمة المتوقعة — القائمة الفارغة تعني «أي DQ-10xx».
  final List<String> expectedCodes;

  const PoisonedFile({
    required this.id,
    required this.note,
    required this.bytes,
    this.expectedCodes = const [],
  });
}

/// بذور صفوف سليمة لكل قالب — أشكالها من عقد §25.4 الموثق بالاختبارات
/// القائمة (الأكواد بالقائمة البيضاء والأسماء نظيفة والمبالغ سليمة).
List<String> _cleanRows(ImportTemplateId id, int count) {
  String pad(int i) => i.toString().padLeft(6, '0');
  switch (id) {
    case ImportTemplateId.parties:
      return [
        for (var i = 1; i <= count; i++)
          'C${pad(i)},طرف رقم $i,عميل,,',
      ];
    case ImportTemplateId.items:
      return [
        for (var i = 1; i <= count; i++)
          'P${pad(i)},صنف رقم $i,قطعة,,,',
      ];
    case ImportTemplateId.partyBalances:
      return [
        for (var i = 1; i <= count; i++)
          'C${pad(i)},طرف رقم $i,عميل,1500,,',
      ];
    case ImportTemplateId.openingFull:
      return [
        for (var i = 1; i <= count; i++)
          'ذمم,C${pad(i)},طرف رقم $i,عميل,,1000,,,',
      ];
    case ImportTemplateId.openingQty:
      return [
        for (var i = 1; i <= count; i++)
          'P${pad(i)},صنف رقم $i,10,1000,قطعة,,',
      ];
  }
}

/// عمود الاسم (1-based) بكل قالب — مقعد سموم المحارف الخفية.
int _nameColumn(ImportTemplateId id) {
  switch (id) {
    case ImportTemplateId.parties:
    case ImportTemplateId.items:
    case ImportTemplateId.partyBalances:
    case ImportTemplateId.openingQty:
      return 2;
    case ImportTemplateId.openingFull:
      return 3;
  }
}

/// عمود المبلغ المعدّد (1-based) بكل قالب — مقعد سموم فائض int64
/// (حدود الأعمدة: حد الائتمان / سعر الشراء / الرصيد / القيمة).
int _amountColumn(ImportTemplateId id) {
  switch (id) {
    case ImportTemplateId.parties:
      return 5;
    case ImportTemplateId.items:
      return 5;
    case ImportTemplateId.partyBalances:
      return 4;
    case ImportTemplateId.openingFull:
      return 6;
    case ImportTemplateId.openingQty:
      return 4;
  }
}

/// استبدال حقل واحد بصف CSV بلا اقتباسات (بذور الحافظة بلا فواصل داخل
/// الحقول فالشطر بالفواصل آمن حصراً).
String _replaceField(String row, int column1based, String value) {
  final parts = row.split(',');
  parts[column1based - 1] = value;
  return parts.join(',');
}

/// الملف النظيف من باني الحافظة ذاته — عقلنة الحافظة: أي رفض على هذا
/// الملف يعني علة باني لا علة مفسّر، فيُقبل قبل كل سموم.
List<int> buildCleanImportFile(
  ImportTemplateId id, {
  int rowCount = 3,
  bool bom = false,
}) {
  final template = importTemplateOf(id);
  if (template == null) {
    throw ArgumentError('قالب غير معروف: $id');
  }
  final lines = <String>[
    template.markerLine,
    template.columns.map((c) => c.label).join(','),
    ..._cleanRows(id, rowCount),
  ];
  final body = lines.join('\n');
  return utf8.encode(bom ? '$csvUtf8Bom$body' : body);
}

/// الحافظة المسمومة الدائمة لقالب واحد — كل حالة ملف كامل بايتاته
/// وتوقع رمزها، ومجموعتها تُمارَس بكل تسليم (10 §10 بند 6: «حافظة
/// الملفات المسمومة دائمةً تمارس كل قالب استيراد»).
///
/// الحالات من تقرير المالك المعتمد مطروحةً على أعمدة القوالب الخمسة:
/// الترميز الفاسد، والملف الفارغ بلا ترويسة، والفاصل الغريب، وكسر
/// عدد الأعمدة، والخانة الإلزامية الفارغة (الكود والاسم)، والمبلغ
/// المتجاوز int64، ومحارف التحكم الخفية (D-170 — النطاق المفحوص
/// [\x00-\x1F\x7F\u0080-\u009F])، والتجاوز الحد الصلب 10,000 صف.
///
/// حدّان صادقان: التكرار الداخلي (DQ-1022) يعيش بطبقة الخطة لا
/// المفسّر (عرف planPartiesImport الموثق بالاختبارات) فلا يعود
/// للحافظة المستوىية — تغطيته قائمة بالاختبارات القائمة؛ والBOM
/// المضاعف يُبتلع رشقاً بتصميم §25.4 (الابتلاع يبدأ من الملف والقص
/// يزيل ما بقي بالسطر) فليس سماً يُرفض ولا يُدرج كذباً.
List<PoisonedFile> buildPoisonedFiles(ImportTemplateId id) {
  final template = importTemplateOf(id);
  if (template == null) {
    throw ArgumentError('قالب غير معروف: $id');
  }
  final marker = template.markerLine;
  final labels = template.columns.map((c) => c.label).join(',');
  List<int> fileOf(List<String> rows, {bool bom = false}) {
    final body = <String>[marker, labels, ...rows].join('\n');
    return utf8.encode(bom ? '$csvUtf8Bom$body' : body);
  }

  final base = _cleanRows(id, 1).single;
  final nameCol = _nameColumn(id);
  final amountCol = _amountColumn(id);

  // الصف السليم بلا كود وبلا اسم — الخانة الإلزامية الفارغة.
  final noCode = _replaceField(base, 1, '');
  final noName = _replaceField(base, nameCol, '');

  final overflow = _replaceField(
    base, amountCol, '9223372036854775808'); // int64Max + 1

  final nullByteName = _replaceField(base, nameCol, 'طرف\x00مسموم');
  final bellName = _replaceField(base, nameCol, 'طرف\u0007مسموم');

  final limitRows = _cleanRows(id, 10001); // الحد الصلب 10,000 + 1

  return [
    PoisonedFile(
      id: 'invalid_utf8',
      note: 'بايتات ليست UTF-8 سليماً — رفض DQ-1017 برسالة الإنقاذ لا تخمين',
      bytes: const [0xC1, 0xC2, 0xC3],
      expectedCodes: const ['DQ-1017'],
    ),
    PoisonedFile(
      id: 'empty_file',
      note: 'الملف صفر البايتات — لا ترويسة أصلاً (DQ-1018)',
      bytes: const <int>[],
      expectedCodes: const ['DQ-1018'],
    ),
    PoisonedFile(
      id: 'pipe_separator',
      note: 'فاصل لا فاصلة ولا منقوطة — رفض DQ-1019 بتوجيه عربي',
      bytes: utf8.encode(<String>[
        marker,
        labels.split(',').join('|'),
        base.split(',').join('|'),
      ].join('\n')),
      expectedCodes: const ['DQ-1019'],
    ),
    PoisonedFile(
      id: 'column_count_mismatch',
      note: 'صف بأعمدة أقل يكسر الفحص البنيوي كله — DQ-1019',
      bytes: fileOf([
        base,
        base.split(',').sublist(0, template.columnCount - 1).join(','),
      ]),
      expectedCodes: const ['DQ-1019'],
    ),
    PoisonedFile(
      id: 'empty_required_code',
      note: 'الخانة الإلزامية فارغة — رفض مرقم بالصف والعمود',
      bytes: fileOf([noCode]),
      // الأطراف تُثبت DQ-1020 حصراً؛ وبقية القوالب أي DQ-10xx مرقم.
      expectedCodes:
          id == ImportTemplateId.parties ? const ['DQ-1020'] : const [],
    ),
    PoisonedFile(
      id: 'empty_name',
      note: 'الاسم إلزامي فارغ — رفض مرقم بالصف والعمود',
      bytes: fileOf([noName]),
      // الأطراف تُثبت DQ-1020 حصراً؛ وبقية القوالب أي DQ-10xx مرقم.
      expectedCodes:
          id == ImportTemplateId.parties ? const ['DQ-1020'] : const [],
    ),
    PoisonedFile(
      id: 'int64_overflow_amount',
      note: 'مبلغ يتجاوز مدى int64 (int64Max + 1) — رفض مرقم لا انهيار',
      bytes: fileOf([overflow]),
    ),
    PoisonedFile(
      id: 'null_byte_in_name',
      note: 'بايت معدوم NUL داخل الاسم — محارف تحكم خفية مرفوضة (D-170)',
      bytes: fileOf([nullByteName]),
      expectedCodes: id == ImportTemplateId.parties
          ? const ['DQ-1020']
          : const [],
    ),
    PoisonedFile(
      id: 'bell_char_in_name',
      note: 'محرف الجرس BEL داخل الاسم — محارف تحكم خفية مرفوضة (D-170)',
      bytes: fileOf([bellName]),
      expectedCodes: id == ImportTemplateId.parties
          ? const ['DQ-1020']
          : const [],
    ),
    PoisonedFile(
      id: 'row_limit_breach',
      note: '10,001 صف فوق الحد الصلب — رفض DQ-1024 بالرقم والحد',
      bytes: fileOf(limitRows),
      expectedCodes: const ['DQ-1024'],
    ),
  ];
}
