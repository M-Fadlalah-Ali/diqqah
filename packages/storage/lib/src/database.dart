import 'dart:convert';
import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

/// يُرمى عند فتح قاعدة أحدث مخططاً من التطبيق (F-156: «حدّث التطبيق»).
class DiqqahNewerSchemaException implements Exception {
  const DiqqahNewerSchemaException();

  @override
  String toString() => 'القاعدة أحدث مخططاً من التطبيق — حدّث التطبيق';
}

/// جدول الأصناف — انعكاس مباشر لصف `item` في نموذج البيانات (05 §3.2)
/// بقرارات بطاقة الأصناف (D-073/D-074) والسيناريوهات (س-36..س-41):
///
/// - `id` التلقائي هو الهوية الدائمة — الدرس الموكول من ملاحظة م0 في هذا
///   الجدول نفسه: «إعادة بناء الجدول لإضافة id تُدرس عند أول تطوير
///   تشغيلي للأصناف في m1»، وهذه الدفعة هي أول تطوير تشغيلي، والفواتير
///   القادمة تحيل بالمعرف كما تحيل بطرفها (D-073).
/// - `sku` نص فريد **لا يعدل بعد الحفظ** (D-073 — الأساس روح D-062):
///   قيد UNIQUE هنا تفرد حرفي حصراً، والتفرد المطبَّع في المجال نفسه
///   حرفي (itemSkuKey) — بلا نزع أصفار ولا ترتيب رقمي (قرارات أطراف
///   خاصة لا تُسقط على كود متنوع).
/// - الأسعار بوحدات صغرى صحيحة حصراً (س7) — لا عمود عشري في الجدول كله،
///   والصفر مشروع «بلا سعر بعد» والسالب يمنعه المجال حصراً (س6).
/// - `category` اختياري ووُجد أساساً للرفع الجماعي للأسعار (F-165).
/// - `default_tax_id` قيمة صفرية محتملة (05) — بنية معطلة في م1.
/// - `base_unit_id` يحيل إلى جدول units — إلزامي من المجال (F-031).
/// - `kind` يقبل good/service/bundle ببنية 05، والواجهة في م1 تعرض
///   البضاعة والخدمة حصراً (التجميعي م2 — F-034).
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get sku => text().unique()();

  TextColumn get name => text()();

  TextColumn get category => text().nullable()();

  /// good / service / bundle (05 §3.2)
  TextColumn get kind => text()();

  IntColumn get baseUnitId => integer().named('base_unit_id')();

  IntColumn get purchasePriceMinor =>
      integer().named('purchase_price_minor')();

  IntColumn get salePriceMinor => integer().named('sale_price_minor')();

  IntColumn get priceCurrencyId => integer().named('price_currency_id')();

  /// قيمة صفرية — ضريبة افتراضية غير معرفة (05)
  IntColumn get defaultTaxId => integer().nullable().named('default_tax_id')();

  /// صورة الصنف — دفعة (10) بترحيلة v12 (س-123/D-120/D-125): مساران
  /// نسبيان لمجلد القاعدة («صور بجوار ملف القاعدة لا مدموغة فيه»)،
  /// الأصل 512 والمشتق المصغر 128 — null يعني الصنف بلا صورة والحالة
  /// طبيعية تُعرض بالنائب البصري (س-125/D-122).
  TextColumn get imageFile => text().nullable().named('image_file')();

  /// المشتق المصغر لسطور الفواتير حصراً (س-126) — لا الأصل.
  TextColumn get imageThumb => text().nullable().named('image_thumb')();

  BoolColumn get isActive => boolean().named('is_active')();

  /// اصطلاح «كل جدول» (D-055) — uuid إلزامي عند كل إدراج.
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  /// حذف منطقي فقط للسجلات غير المرحّلة (05 §2) — المالية بعد الترحيل لا تُمسّ.
  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// جدول الوحدات — انعكاس مباشر لصف `unit` في نموذج البيانات (05 §3.2)
/// مبسطاً لاحتياج م1 (D-075):
///
/// - `name` فريد حرفياً (D-074 — تمديد منع تكرار الأسماء للوحدات) و
///   إضافة حصراً في م1: لا تعديل ولا حذف ولا تعطيل — الصنف يحيل بمعرفها
///   ووحدة بلا صنف هي بضاعة مستقبل لا حاجة لمساره الآن.
/// - `is_base` بنية جاهزة لم2 (05: «الوحدة الأساسية عاملها 1») — قيمتها
///   ثابتة true في م1 لأن كل وحدة يُدخلها المستخدم مرشحة لأن تكون وحدة
///   أساسية لصنف ما؛ مجموعات التعبئة والتحويل م2 (F-032).
class Units extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().unique()();

  /// بنية لم2 — ثابتة true في م1 (D-075).
  BoolColumn get isBase =>
      boolean().named('is_base').withDefault(const Constant(true))();

  /// اصطلاح «كل جدول» (D-055).
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// بنية الباركود — 05: `item_barcode` جاهزة من اليوم الأول (F-035،
/// «بنية الباركود جدول جاهز من اليوم الأول، القراءة الفعلية مؤجلة للمرحلة
/// 5») — لا شاشة قراءة ولا مسار مستخدم في م1، والحقلان `unit_id`
/// (وحدة قراءة الباركود عند التعبئة) قيمة صفرية حتى م2.
class ItemBarcodes extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get itemId => integer().named('item_id')();

  TextColumn get barcode => text().unique()();

  /// وحدة القراءة (تعبئة م2) — null في م1 (بنية جاهزة لا مسار استخدام).
  IntColumn get unitId => integer().nullable().named('unit_id')();

  /// اصطلاح «كل جدول» (D-055).
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// الأدوار — 05: `role` (name). الإصدار 2 أضاف المعرّف الآلي لربط app_user،
/// والإصدار 3 أضاف أعمدة اصطلاح «كل جدول» (D-055).
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().unique()();

  /// صلاحيات الشاشات (F-080، دفعة إغلاق النواة س37): صيغة مخزنة واحدة
  /// من المجال (permissions.dart) — النجمة «*» بمعنى كل الوحدات أو
  /// مفاتيح مفصولة بفواصل. الافتراضي «*» حتى يبقى الدور القديم (مدير)
  /// كاملاً بعد الترحيلة v10 قبل أي تعديل يدوي.
  TextColumn get permissions =>
      text().withDefault(const Constant('*'))();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// المستخدمون المحليون — 05: `app_user` «مستخدمون محليون من الإصدار الأول».
class AppUsers extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get login => text().unique()();

  /// بصيغة «salt:hash» — PBKDF2-HMAC-SHA256 في حزمة المجال (setup.dart).
  TextColumn get passwordHash => text().named('password_hash')();

  IntColumn get roleId => integer().named('role_id')();

  BoolColumn get isActive => boolean().named('is_active')();

  /// اصطلاح «كل جدول» (D-055) — نفس أعمدة roles أعلاه.
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// جدول الأطراف — انعكاس مباشر لصف `party` في نموذج البيانات (05 §3.1)
/// بقرارات بطاقة الأطراف (D-062..D-066) والسيناريوهات المعتمدة (س-29..س-35):
///
/// - `number` يخزن نصاً كما كُتب بأصفاره («0053» تبقى 0053 — D-063)؛
///   قيد UNIQUE هنا تفرد حرفي للتخزين حصراً، أما التفرد المطبَّق بعد نزع
///   الأصفار الزائدة («0053» و«53» طرف واحد) فهو قاعدة مجال تُفحص قبل
///   الحفظ (validatePartyDraft) — فـ SQLite يفرق بين النصين وما من قيد
///   SQL يفعل ذلك بعد كتابتهما.
/// - الرقم لا يعدل بعد الحفظ (D-063) — لا مسار تحديث له في هذا الملف
///   عملاً، والبطاقة تقفل حقلَه في التعديل (س-32).
/// - منع تكرار الاسم المطابق حرفياً (D-065) قاعدة مجال حصراً — المقارنة
///   حرفية بلا تطبيع، والتطبيع للبحث حصراً (D-064).
/// - العملة معبأة دوماً بالافتراضية ولا تخزن فارغة (D-066)؛ المعرّف 1
///   هو العملة الأساسية (D-017) حتى تُبنى جدول العملات في دفعاتها —
///   الاصطلاح نفسه المعتمد لـ price_currency_id في الأصناف.
/// - حد الائتمان اختياري (F-023/س-34) — null فراغ مشروع معناه «بلا سقف».
/// - زر الحذف غير موجود أصلاً والتعطيل بطي is_active (س-33)؛ is_deleted
///   من اصطلاح «كل جدول» (D-055) يبقى للبنية لا لمسار مستخدم.
class Parties extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get number => text().unique()();

  TextColumn get name => text()();

  /// customer / supplier / both (05 §3.1، س-30)
  TextColumn get kind => text()();

  TextColumn get phone => text().nullable()();

  TextColumn get address => text().nullable()();

  IntColumn get defaultCurrencyId => integer().named('default_currency_id')();

  IntColumn get creditLimitBaseMinor =>
      integer().nullable().named('credit_limit_base_minor')();

  BoolColumn get isActive => boolean().named('is_active')();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// دليل الحسابات — 05 §3.4 `account` + 03 كاملاً: «الدليل إعداد لا كود»
/// (07 §1.6) — الصفوف تُزرع من الدليل الافتراضي المعتمد (م-10/م-11/م-13/
/// م-15) ويعدلها المالك من الشاشة دون أي برمجة، والتقارير من `type` لا
/// من الاسم أو الكود.
///
/// - الورقية وحدها تقيد (`is_leaf`) والحساب الأب يعرض مجمّع أبنائه (03 §1-2).
/// - `normal_side` مستقل عن النوع لقبول العكسية (42 مردودات المبيعات
///   income مدينها — 32/321 المسحوبات equity مدينها — 53 مردودات
///   المشتريات expense دائنها — 03 §1-4).
/// - `parent_id` يحيل بالمعرف — الأصل الهرمي من أكواد 03 كما هي.
/// - المعطل يبقى بتاريخه وأرصدته سليمة، ولا حذف لحساب له حركة (03 §1-3).
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get code => text().unique()();

  TextColumn get name => text()();

  /// asset / liability / equity / income / expense (03 §2)
  TextColumn get type => text()();

  /// debit / credit — اتجاه يزيد الرصيد الطبيعي
  TextColumn get normalSide => text().named('normal_side')();

  IntColumn get parentId => integer().nullable().named('parent_id')();

  BoolColumn get isLeaf => boolean().named('is_leaf')();

  BoolColumn get isActive => boolean().named('is_active')();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// الدفاتر — 05 §3.4 `journal`: كل قيد يصدر عن دفتر من هذه. الخمسة
/// تُزرع منذ اليوم الأول بنيةً جاهزة (D-076 معروض) — دفاتر sales/purchase/
/// cash/stock تدخل حيز العمل مع مستنداتها في دفعاتها (الفواتير دفعة 4،
/// والصندوق دفعة 5)، و`general` قيود الدفعة (3) اليدوية.
class Journals extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get code => text().unique()();

  TextColumn get name => text()();

  /// sales / purchase / cash / stock / general (05 §3.4)
  TextColumn get kind => text()();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// السنوات المالية — 05 §3.4 `fiscal_year`: سنة ميلادية واحدة مفتوحة
/// غالباً (D-017). تُزرع سنة «الآن» عند التثبيت بأفتراضيها الشهري.
class FiscalYears extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get startDateText => text().named('start_date_text')();

  TextColumn get endDateText => text().named('end_date_text')();

  /// open / closed — إقفالها مع دفعة التقارير والإغلاق (6)
  TextColumn get state => text()();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// الفترات المالية — 05 §3.4 `period`: شهرية افتراضياً ويمكن أسبوعاً أو
/// ربعاً أو الاقتصار على الإقفال اليدوي (D-027). الفترة المقفلة تتجمد:
/// لا ترحيل فيها (07 §1.5) — الفحص بالمحرك (validateMoveForPosting).
class Periods extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get fiscalYearId => integer().named('fiscal_year_id')();

  TextColumn get startDateText => text().named('start_date_text')();

  TextColumn get endDateText => text().named('end_date_text')();

  /// open / closed
  TextColumn get state => text()();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// القيود — 05 §3.4 `move`: آلة الحالة صريحة (07 §1.2) مسودة ← مرحّل
/// بلا رجوع، وما رُحّل لا يعدل ولا يحذف أبداً (07 §1.3 — مُشغِّلات
/// القاعدة حاجزها الثاني، 07 §2.2 نمط D-067).
///
/// - `date_text` تواريخ العملية نص ISO «YYYY-MM-DD» حصراً — فرزها
///   المعجمي زمني صحيح (D-077 معروض)، والميلادي أساس التخزين حصراً (F-167).
/// - `number` نص الرقم المُصدَر «2026/000001» (سنة/رقم مبطن 6) — والمسودة
///   بلا رقم («»): الترقيم لحظة الترحيل حصراً فلا رقم يُصدر ولا يُعاد (07 §1.9).
///   الصيغة الكاملة المعروضة «قيد عام 2026/000001» تولّد للعرض ب
///   formatSequenceLabel (م-44 — الاسم الكامل بلا بادئة مختصرة).
/// - `period_id` يُكتب عند الترحيل بعد فحص الفترة المفتوحة — فالمسودة
///   القائمة فوق شهر مقفل تبقى معلقة لا مرحّلة.
/// - `ref_doc_type/ref_doc_id` مرجع المستند المولد للقيد (05 §2) — القيد
///   العكس يُحيل قيدَ الأصل (07 §1.3) بقيمة «move».
/// - البنية الجاهزة منذ اليوم الأول (درس D-075): لا إعادة هيكلة لاحقاً.
class Moves extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get journalId => integer().named('journal_id')();

  IntColumn get periodId => integer().nullable().named('period_id')();

  TextColumn get dateText => text().named('date_text')();

  /// draft / posted (07 §1.2)
  TextColumn get state => text()();

  TextColumn get number => text()();

  TextColumn get narration => text().nullable()();

  TextColumn get refDocType => text().nullable().named('ref_doc_type')();

  IntColumn get refDocId => integer().nullable().named('ref_doc_id')();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// أسطر القيود — 05 §3.4 `move_line`: الحساب ورقي حصراً، والسطر جهة
/// واحدة (مدين أو دائن) بمبالغ وحدات صغرى صحيحة (07 §2.1).
///
/// - `party_id` للذمم على حسابي السيطرة 112/211 (اصطلاح م-14).
/// - `currency_id`/`amount_minor`/`fx_rate` بنية العملات جاهزة منذ اليوم
///   الأول (07 §1.7): القيود اليدوية في م1 بالعملة الأساسية المعتمدة
///   (المعرف 1 — اصطلاح D-066/D-017) بلا سعر؛ وقيود الدولار مع مستنداتها
///   (الفواتير دفعة 4) بلقطة سعرها. `fx_rate` عدد صحيح مكبَّر (اصطلاح
///   exchange_rate في 05 §3.5).
/// - `ref_stock_move_id` الالتزام التنفيذي لربط المخزون بالدفتر (07 §3.1
///   — م-27 مؤكد): يُملأ من حركة المخزون المولدة لسطر التكلفة عند ترحيل
///   الفواتير، بلا أي إعادة هيكلة لاحقاً.
/// - لا تعديل ولا حذف ولا إدراج على أسطر قيد مرحّل — ثلاثة مُشغِّلات
///   (07 §2.2/F-055): الحاجز الثاني مختبَر لا نية موثقة.
class MoveLines extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get moveId => integer().named('move_id')();

  IntColumn get accountId => integer().named('account_id')();

  IntColumn get debitMinor =>
      integer().withDefault(const Constant(0)).named('debit_minor')();

  IntColumn get creditMinor =>
      integer().withDefault(const Constant(0)).named('credit_minor')();

  IntColumn get partyId => integer().nullable().named('party_id')();

  IntColumn get currencyId =>
      integer().withDefault(const Constant(1)).named('currency_id')();

  IntColumn get amountMinor =>
      integer().nullable().named('amount_minor')();

  IntColumn get fxRate => integer().nullable().named('fx_rate')();

  IntColumn get refStockMoveId =>
      integer().nullable().named('ref_stock_move_id')();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// الترقيم المركزي — 05 §5 `sequence`: تسلسل سنوي لكل نوع مستند، والأرقام
/// المُصدَرة لا تُعاد أبداً (07 §1.9/D-071). المُصدَر عند الترحيل حصراً
/// داخل المعاملة ذاتها (07 §2.4 — فلا رقم يُصدر بقيد لم يكتب).
///
/// مفتاحه المركب (kind, year) — وسُعّت كامل أعمدة الاصطلاح (D-055) لأرقامه
/// بيانات أعمال تُزامن مستقبلاً ولا مفاتيح نظام (عكس إعفاء app_meta).
/// ترقيم قيود المستندات المولدة (فواتير/سندات) أنواعه الخاصة بدفعاتها —
/// نوع الدفعة (3): `move_general` للقيود اليدوية (D-076 معروض).
class Sequences extends Table {
  TextColumn get kind => text()();

  IntColumn get year => integer()();

  IntColumn get lastNumber => integer().named('last_number')();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();

  @override
  Set<Column> get primaryKey => {kind, year};
}

/// سجل الأحداث — 05 §5/07 §2.3 (D-067): جدول مصدر كامل بصفة «لقطة كاملة»
/// للكيان عند كل تغيير — append-only لا يُعدل ولا يُحذف ولا يُعاد بناؤه
/// من غيره، وهو أساس التدقيق والمزامنة لاحقاً (المرحلة 4 نقل أحداث مرتبة).
///
/// **إفصاح موثق**: هذا الجدول كان حاكماً «من اليوم الأول» (07 §2.3) وغاب
/// عن ترحيلات م0 ودفعتَي م1 السابقتين بلا عمليات محاسبية تُسجَّل أصلاً —
/// دفعة القلب أول عملية قيدية ففتح هذا الجدول معها (D-076): كل إنشاء
/// مسودة وترحيل وحذف مسودة وإنشاء عكس يحمل لقطته الكاملة بـ`payload`
/// (JSON) وحدثه يُكتب في معاملة العملية ذاتها فلا حدث بلا عملية ولا
/// عملية بلا حدث.
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get eventAt => integer().named('event_at')();

  /// صاحب العملية — من جلسة الدخول لاحقاً؛ الخلفية البحتة الآن بلا مستخدم
  IntColumn get userId => integer().nullable().named('user_id')();

  TextColumn get deviceId => text().named('device_id')();

  /// move / (invoice، voucher… في دفعاتها)
  TextColumn get entityType => text().named('entity_type')();

  IntColumn get entityId => integer().nullable().named('entity_id')();

  /// created / posted / reversal_created / draft_deleted
  TextColumn get action => text()();

  /// لقطة الكيان الكاملة JSON عند وقوع الحدث (07 §2.3)
  TextColumn get payload => text()();

  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// مفاتيح النظام — موطن `device_id` (F-015) وسائر مفاتيح التهيئة.
/// معفاة من اصطلاح «كل جدول» قراراً موثقاً (D-055): مفاتيح نظام
/// لا سجلات أعمال — لا مزامنة ولا حذف منطقي لها.
class AppMeta extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// قاعدة دِقَّة — نسخة المخطط 7.
///
/// 1 = items فقط (جلسة م0 الأولى). 2 = التهيئة: roles / app_users / app_meta
/// (س-01: F-014/F-015). 3 = اصطلاح «كل جدول» (05 §2، D-055): uuid عالمي +
/// created_at/updated_at + is_deleted على items وroles وapp_users — app_meta
/// مفاتيح نظام معفاة قراراً موثقاً. 4 = جدول الأطراف (05 §3.1 — دفعة م1
/// الأولى: D-062..D-066، س-29..س-35). 5 = دفعة م1 الثانية (الأصناف:
/// D-073..D-075، س-36..س-41): إضافة `id` التلقائي لجدول items بإعادة
/// بناء آمنة موثقة (الدرس الموكول من ملاحظة الجدول نفسه)، وجدولا units
/// وitem_barcodes جديدان خالصان (F-031/F-035). 6 = دفعة م1 الثالثة (قلب
/// الدفتر: D-076..D-078 معروضة، س-42..س-50): ثمانية جداول جديدة خالصة
/// (accounts/journals/fiscal_years/periods/moves/move_lines/sequences/
/// events — 05 §3.4/§5) + ستة مُشغِّلات حواجز (توازن الترحيل وتجميد
/// المرحّل — 07 §2.2) + بذر الدليل الافتراضي (03 §3) والدفاتر الخمسة
/// وسنة «الآن» بفتراتها الشهرية. كل تغيير مخطط قادم يضيف إصداراً
/// وترحيلة — لا تعديل رجعي على إصدار منشور (F-011). 7 = دفعة م1
/// الرابعة (الفواتير: D-079..D-082 معروضة، س-51..س-60): ثمانية جداول
/// جديدة خالصة (currencies/warehouses/cash_boxes/invoices/
/// invoice_lines/stock_moves/stock_balances/cash_movements —
/// 05 §3.3/§4/§5) تُدار SQL خاماً بنمط المُشغِّلات المجرَّب (D-079) +
/// مُشغِّلات حواجز (منع سالب المخزون والصندوق، تجميد حركات المخزون
/// والصندوق، تجميد الفاتورة المرحّلة وأسطرها، منع حذفها) + بذر
/// العملتين SYP/USD (D-070/F-120) والمستودع الافتراضي والصندوق
/// والصندوق الرئيسي على 1111.
///
/// v8 (دفعة السندات والصندوق — س-61..س-70/D-083..D-087 معروضة):
/// أربعة جداول جديدة خالصة (vouchers/voucher_allocations/
/// box_transfers/cash_adjustments — 05 §4.2 + س-16/س-17) تُدار SQL
/// خاماً بنمط D-079 + مُشغِّلات حواجزها (تجميد السند المرحّل
/// ومطابقاته ومستندَي التحويل والتسوية، ومنع حذف المرحّل، ومنع
/// مطابقة فاتورة مسودة، وتوسعة حاجز سالب الصندوق للخروج بالتحويل)
/// + بذر تفعيل حسابَي فروق العملة 44/55 (F-123/D-085 معروضان) —
/// ومحرك السندات والتحويل والتسوية كامل الفحص خلفياً.
/// v9 (دفعة 6): حواجز الإقفال D-088. v10 (س37): صلاحيات الشاشات
/// F-080/D-100. v11 (س40): الخصم العشري ×100 D-112. v12 (دفعة 10:
/// الصور والباركود س-123..س-132/D-118..D-126): عمودا الصورة على
/// items (image_file/image_thumb مساران نسبيان لمجلد بجوار القاعدة)
/// بـADD COLUMN بحرس pragma (درس v3/v10 المجرّب) — وجدول الباركود
/// الجاهز من اليوم الأول (F-035) لا يُمسّ بل يُفتح مساره: لا جداول
/// جديدة ولا أعمدة عليه.
/// v13 (دفعة 12 — متابعة التسليم س-137..س-142/D-131..D-134 بأمر
/// المالك «ابدأ» وتصديقه على زر «تسليم الكل» بـ«لا بأس»، س43):
/// عمودان على invoice_lines بـADD COLUMN بحرس pragma (نمط v12):
/// `delivered` (0/1 — افتراضه 0 بلفظ المالك «ما ليس محدد يكون غير
/// مستلم») و`supplier_party_id` (nullable — المورد المسؤول بلا
/// مفروض) — علم عمل لا محاسبة: لا قيد ولا حركة مخزون ولا ذمة.
/// ومعها حرس تجميد أسطر المرحّل يُعاد بصيغته المحدّثة (درس v11 في
/// طرحه وإعادته): يجمّد الحقول المالية والبنيوية حصراً فيسمح تحديث
/// علم التسليم والمورد على السطر المرحّل بلا فك إقفال (D-131:
/// تحديث جزئي موثق لعلم عمل).
@DriftDatabase(tables: [
  Items,
  Roles,
  AppUsers,
  AppMeta,
  Parties,
  Units,
  ItemBarcodes,
  Accounts,
  Journals,
  FiscalYears,
  Periods,
  Moves,
  MoveLines,
  Sequences,
  Events,
])
class DiqqahDatabase extends _$DiqqahDatabase {
  /// التشغيل العادي: ملف القاعدة الوحيد (أساس النسخ الاحتياطي الكامل F-012).
  /// ملف الجيل السابق «heseb.db» يتبنّى آلياً عند أول فتح (D-053 —
  /// adoptLegacyHesebDatabase في backup.dart).
  DiqqahDatabase({String filePath = 'diqqah.db'})
      : super(LazyDatabase(() async => NativeDatabase(File(filePath))));

  /// للاختبارات: قاعدة في الذاكرة — لا أثر على ملف المستخدم أبداً.
  DiqqahDatabase.inMemory() : super(NativeDatabase.memory());

  /// اتصال اختباري بإغلاق التدفقات فوراً بلا مؤقتات — الخيار الموثق في
  /// drift نفسها (DatabaseConnection.closeStreamsSynchronously) «لبيئات
  /// الاختبار التي ترمي استثناءات على المؤقتات المتبقية بعد الاختبارات»
  /// (علّة CI 2026-10-29/30 — س24/س25/س26): drift يؤجل تنظيف تدفق watch
  /// مؤقتاً زائفاً بعد آخر إلغاء اشتراك كي لا يعيد الاستعلام عند إعادة
  /// الاتصال السريع، وفحص ثوابت flutter_test («مؤقت ما زال معلقاً بعد
  /// تفكيك الشجرة») يسبق teardowns فلا سبيل لإطلاقه بعد التفكيك —
  /// والخيار هنا يقطع الطريق من مصدره: لا مؤقت يُجدول أصلاً عند إلغاء
  /// أي اشتراك. للاختبارات حصراً — المنتج لا يستعمله.
  /// ملاحظة مصدرية: DatabaseConnectionUser الرئيسي يمرر DatabaseConnection
  /// كما هو بلا إعادة غلاف (`executor is DatabaseConnection ? executor`)
  /// فتبقى مخزنة التدفقات المخصصة هنا هي الفاعلة.
  factory DiqqahDatabase.inMemorySyncClose() =>
      DiqqahDatabase._syncClose(DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ));

  DiqqahDatabase._syncClose(DatabaseConnection connection)
      : super(connection);

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createLedgerTriggers();
          await _createInvoiceTables();
          await _createInvoiceTriggers();
          await _createVoucherTables();
          await _createVoucherTriggers();
          await _createClosingTriggers();
          await _seedAccountingBaseline();
          await _seedInvoiceBaseline();
          await _seedVoucherBaseline();
          await _seedDefaultRoles();
        },
        onUpgrade: (m, from, to) async {
          // 1→2: جداول التهيئة جديدة خالصة — createAll يبني الناقص بـ
          // IF NOT EXISTS ولا يمس جدول items الموجود. الترقيات التي تغيّر
          // أعمدة قائمة ستحتاج SQL صريحاً — لا createAll (قاعدة التغيير، س1).
          for (var version = from + 1; version <= to; version++) {
            if (version == 2) {
              await m.createAll();
            }
            // 2→3 (ومن 1 مباشرة): اصطلاح «كل جدول» (D-055). أعمدة جديدة
            // خالصة بـ ADD COLUMN — لا تعديل لأعمدة قائمة، فلا إعادة بناء.
            // uuid NOT NULL DEFAULT '' ثم تعبئة فورية أدناه — الصفر القائم
            // لا يبقى سوى لأجزاء من الثانية داخل الترحيلة نفسها.
            // حارس التكرار (علة CI 2026-10-28): خطوة v2 تبني الجداول
            // الناقصة بـ createAll بشكلتها الحالية — أي بأعمدة الاصطلاح
            // أصلاً عند الترقية من v1 — فالإضافة العمياء تصطدم بـ
            // «duplicate column». فحص pragma_table_info يجعل الترحيلة
            // آمنة التكرار أي كان مسار الوصول (v1→3 أو v2→3).
            if (version == 3) {
              const convention = <String, String>{
                'uuid': "TEXT NOT NULL DEFAULT ''",
                'created_at': 'INTEGER NOT NULL DEFAULT 0',
                'updated_at': 'INTEGER NOT NULL DEFAULT 0',
                'is_deleted': 'INTEGER NOT NULL DEFAULT 0',
              };
              for (final table in const ['items', 'roles', 'app_users']) {
                final existing = (await customSelect(
                        "SELECT name FROM pragma_table_info('$table')")
                      .get())
                    .map((r) => r.data['name'] as String)
                    .toSet();
                for (final col in convention.entries) {
                  if (!existing.contains(col.key)) {
                    await customStatement(
                        'ALTER TABLE $table ADD COLUMN ${col.key} ${col.value}');
                  }
                }
              }
              // تعبئة uuid وأزمنة السجلات القائمة — م0 صغيرة فالحلقة
              // صف بأصفار كلفة، والكبيرة لما تأتي ستكون مختبرة.
              final ts = DateTime.now().millisecondsSinceEpoch;
              const keyed = [('items', 'sku'), ('roles', 'id'), ('app_users', 'id')];
              for (final (table, pk) in keyed) {
                final rows = await customSelect('SELECT $pk AS pk FROM $table').get();
                for (final row in rows) {
                  await customStatement(
                    'UPDATE $table SET uuid = ?, created_at = ?, updated_at = ? '
                    'WHERE $pk = ?',
                    [const Uuid().v4(), ts, ts, row.data['pk'] as Object],
                  );
                }
              }
            }
            // 3→4 (ومن إصدار أدنى مباشرة): جدول الأطراف جديد خالص —
            // createAll يبني الناقص بـ IF NOT EXISTS ولا يمس الجداول
            // القائمة (نمط v2 المجرّب)، ولا أعمدة على جداول قائمة هنا
            // أصلاً فلا يلحق درس علة «duplicate column» في v3.
            if (version == 4) {
              await m.createAll();
            }
            // 4→5 (ومن إصدار أدنى مباشرة): دفعة الأصناف (D-073..D-075).
            // (أ) الجدولان الجديدان خالصان — createAll يبني الناقص ولا
            // يمس القائم (النمط المجرّب). (ب) items الحامل لإضافة id:
            // إعادة بناء آمنة موكولة من ملاحظة م0 في الجدول نفسه («تُدرس
            // عند أول تطوير تشغيلي للأصناف في m1») — الحكم من
            // pragma_table_info كي تكون الترحيلة آمنة التكرار أي كان
            // مسار الوصول (v4→5 يعيد البناء؛ v≤3 وصلت بitems الجديد
            // من createAll فالفحص يقفز)، والنسخ كامل الأعمدة حصراً:
            // بلا id قديم فيعاد ترقيمه آلياً وهذا لا مساس بأي مرجع
            // لأن جدولا items حتى اليوم بلا حواف أجنبية تُشير إليه
            // (المتطلبات التشغيلية للصنف كله في هذه الدفعة).
            if (version == 5) {
              await m.createAll();
              final itemCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('items')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!itemCols.contains('id')) {
                await customStatement(
                    'CREATE TABLE "items_new_v5" ('
                    '  "id" INTEGER PRIMARY KEY AUTOINCREMENT,'
                    '  "sku" TEXT NOT NULL UNIQUE,'
                    '  "name" TEXT NOT NULL,'
                    '  "category" TEXT NULL,'
                    '  "kind" TEXT NOT NULL,'
                    '  "base_unit_id" INTEGER NOT NULL,'
                    '  "purchase_price_minor" INTEGER NOT NULL,'
                    '  "sale_price_minor" INTEGER NOT NULL,'
                    '  "price_currency_id" INTEGER NOT NULL,'
                    '  "default_tax_id" INTEGER NULL,'
                    '  "is_active" INTEGER NOT NULL DEFAULT 0,'
                    '  "uuid" TEXT NOT NULL,'
                    '  "created_at" INTEGER NOT NULL DEFAULT 0,'
                    '  "updated_at" INTEGER NOT NULL DEFAULT 0,'
                    '  "is_deleted" INTEGER NOT NULL DEFAULT 0'
                    ')');
                await customStatement(
                  'INSERT INTO "items_new_v5" '
                  '("sku", "name", "category", "kind", "base_unit_id", '
                  '"purchase_price_minor", "sale_price_minor", '
                  '"price_currency_id", "default_tax_id", "is_active", '
                  '"uuid", "created_at", "updated_at", "is_deleted") '
                  'SELECT "sku", "name", "category", "kind", "base_unit_id", '
                  '"purchase_price_minor", "sale_price_minor", '
                  '"price_currency_id", "default_tax_id", "is_active", '
                  '"uuid", "created_at", "updated_at", "is_deleted" '
                  'FROM "items"',
                );
                await customStatement('DROP TABLE "items"');
                await customStatement(
                    'ALTER TABLE "items_new_v5" RENAME TO "items"');
              }
            }
            // 5→6 (ومن إصدار أدنى مباشرة): دفعة القلب — جداول الدفتر
            // الثمانية جديدة خالصة فـcreateAll يبنيها (نمط v2/v4 المجرّب)
            // بلا أي مساس بجداول قائمة، ثم المُشغِّلات الحواجز (07 §2.2
            // نمط D-067) ثم بذر خط القاعدة المحاسبي (03 §3 + الدفاتر +
            // سنة «الآن»). البذر فاحص الفراغ ذاته فآمنة التكرار أي كان
            // مسار الوصول (5→6 أو 1→6 مباشرة حيث onCreate زرعها سلفاً).
            if (version == 6) {
              await m.createAll();
              await _createLedgerTriggers();
              await _seedAccountingBaseline();
            }
            // 6→7 (ومن إصدار أدنى مباشرة): دفعة الفواتير (D-079..D-082
            // معروضة) — جداول ثمانية جديدة خالصة SQL خاماً (بنمط
            // المُشغِّلات: آمنة التكرار بـ IF NOT EXISTS ولا مساس بجداول
            // قائمة) ثم مُشغِّلاتها الحواجز ثم بذر العملتين والمستودع
            // والصندوق الرئيسي. البذر فاحص الفراغ ذاته فآمنة التكرار
            // أي كان مسار الوصول (onCreate زرعها سلفاً).
            if (version == 7) {
              await m.createAll();
              await _createLedgerTriggers();
              await _createInvoiceTables();
              await _createInvoiceTriggers();
              await _seedAccountingBaseline();
              await _seedInvoiceBaseline();
            }
            // 7→8 (ومن إصدار أدنى مباشرة): دفعة السندات والصندوق
            // (D-083..D-087 معروضة) — أربعة جداول جديدة خالصة SQL
            // خاماً (نمط v7 المجرَّب: آمنة التكرار بـIF NOT EXISTS ولا
            // مساس بجداول قائمة) ثم مُشغِّلات حواجزها — وتوسعة حاجز
            // سالب الصندوق للخروج بالتحويل — ثم بذر تفعيل حسابَي
            // فروق العملة (44/55 — F-123/D-085). البذر فاحص الحالة
            // ذاته فآمن التكرار أي كان مسار الوصول.
            if (version == 8) {
              await m.createAll();
              await _createLedgerTriggers();
              await _createInvoiceTables();
              await _createInvoiceTriggers();
              await _createVoucherTables();
              await _createVoucherTriggers();
              await _seedAccountingBaseline();
              await _seedInvoiceBaseline();
              await _seedVoucherBaseline();
            }
            // 8→9 (ومن إصدار أدنى مباشرة): دفعة (6) حواجز الإقفال حصراً
            // (D-088 معروض) — بلا جداول ولا أعمدة جديدة، والبناة DROP+CREATE
            // فآمنة التكرار أي كان مسار الوصول.
            if (version == 9) {
              await _createClosingTriggers();
            }
            // 9→10 (ومن إصدار أدنى مباشرة): دفعة إغلاق النواة (س37) —
            // صلاحيات الشاشات الكاملة (F-080/D-100 معروض): عمود واحد
            // جديد على roles بـADD COLUMN بحرس pragma (درس v3 المجرّب:
            // الترقيات من إصدار أدنى تكون قد بنته createAll بشكله الحالي
            // فالإضافة العمياء تصطدم بـduplicate column) — ثم بذر الأدوار
            // النمطية الأربعة بأذوناتها الافتراضية (بذر فاحص الفراغ فآمن
            // التكرار)، والأدوار القائمة تبقى بأذوناتها («*» افتراضياً).
            if (version == 10) {
              final roleCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('roles')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!roleCols.contains('permissions')) {
                await customStatement(
                    "ALTER TABLE roles ADD COLUMN permissions TEXT "
                    "NOT NULL DEFAULT '*'");
              }
              await _seedDefaultRoles();
            }
            // 10→11 (س-117/D-112): الخصم العشري — النسبة تُخزن ×100
            // (350 = 3.5%) فتقبل الفاصلة العشرية حتى خانتين، وترحيلة
            // القيم القائمة تضربها 100 بلا مساس بالمخطط (العمود INTEGER
            // كما هو — لا إعادة بناء). حارس المشغل الثابت:
            // trg_invoices_posted_frozen يمنع تغيير discount_rate على
            // المرحّلة فيُطرح قبل التحديث ويُعاد بعده بالدالة ذاتها
            // (كل مشغلاتها IF NOT EXISTS فآمنة التكرار — درس v10).
            if (version == 11) {
              await customStatement(
                  'DROP TRIGGER IF EXISTS trg_invoices_posted_frozen');
              await customStatement(
                  'UPDATE invoices SET discount_rate = discount_rate * 100');
              await _createInvoiceTriggers();
            }
            // 11→12 (ومن إصدار أدنى مباشرة): دفعة (10) الصور والباركود
            // (س-123..س-132/D-118..D-126) — عمودا الصورة على items
            // بـADD COLUMN بحرس pragma (درس v3/v10: الترقيات من إصدار
            // أدنى تكون قد بنته createAll بشكله الحالي فالإضافة العمياء
            // تصطدم بـduplicate column). مساران nullable فلا إعادة بناء
            // ولا قيم تُهجّر: الصنف بلا صورة null طبيعياً والنائب
            // البصري يعرضه (س-125). جدول الباركود جاهز من اليوم الأول
            // (F-035) فلا حاجة لأي بنية جديدة.
            if (version == 12) {
              final itemCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('items')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!itemCols.contains('image_file')) {
                await customStatement(
                    'ALTER TABLE items ADD COLUMN image_file TEXT NULL');
              }
              if (!itemCols.contains('image_thumb')) {
                await customStatement(
                    'ALTER TABLE items ADD COLUMN image_thumb TEXT NULL');
              }
            }
            // 12→13 (ومن إصدار أدنى مباشرة): دفعة (12) متابعة التسليم
            // (س-137..س-142/D-131..D-134) — عمودا علم التسليم والمورد
            // المسؤول على invoice_lines بـADD COLUMN بحرس pragma (نمط
            // v12 المجرّب): `delivered` افتراضه 0 بلفظ المالك «ما ليس
            // محدد يكون غير مستلم» فكل السطور القائمة تولد غير مستلمة
            // بلا تهجير قيم، و`supplier_party_id` nullable فلا إعادة
            // بناء ولا إعادة ترقيم. وعلم العمل يُحدَّث على المرحّلة
            // فيُعاد حرس تجميد الأسطر بصيغته المحدّثة (درس v11:
            // طرح المُشغِّل وإعادته — وكل مُشغِّلاتها IF NOT EXISTS
            // فآمنة التكرار).
            if (version == 13) {
              final lineCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('invoice_lines')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!lineCols.contains('delivered')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    'delivered INTEGER NOT NULL DEFAULT 0');
              }
              if (!lineCols.contains('supplier_party_id')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    'supplier_party_id INTEGER NULL');
              }
              await customStatement(
                  'DROP TRIGGER IF EXISTS trg_invoice_lines_frozen_update');
              await _createInvoiceTriggers();
            }
          }
        },
        // F-156: التطبيق الأقدم يرفض قاعدة أحدث مخططاً برسالة «حدّث التطبيق»
        // — باب الاستعادة يفحصها قبل الاستبدال (prepareRestore)، وهذا باب
        // الفتح نفسه. drift يمرر التراجع (9→2) في onUpgrade نفسه فلا
        // تنفذ حلقتنا — والحرس أدناه يرفض قبل أي استخدام.
        beforeOpen: (details) async {
          if ((details.versionBefore ?? 0) > schemaVersion) {
            throw const DiqqahNewerSchemaException();
          }
        },
      );

  /// F-015: `device_id` يتولد مرة واحدة ويعود ثابتاً في كل الاستدعاءات
  /// وبعد الترقيات — يعيش في القاعدة (بقاء تام فوق نفس القاعدة، DoD).
  Future<String> deviceId() async {
    final rows = await (select(appMeta)
          ..where((t) => t.key.equals('device_id')))
        .get();
    if (rows.isNotEmpty) {
      return rows.first.value;
    }
    final id = const Uuid().v4();
    await into(appMeta)
        .insert(AppMetaCompanion.insert(key: 'device_id', value: id));
    return id;
  }

  /// F-014: هل التهيئة منتهية؟ (وُجد مستخدم على الأقل)
  Future<bool> hasAnyUser() async {
    final rows = await select(appUsers).get();
    return rows.isNotEmpty;
  }

  /// س-01: إنشاء المستخدم الأول بدور «مدير» — يزرع الدور إن لم يوجد
  /// ويعيد استخدامه إن وُجد (لا تكرار أدوار)، ويتولد device_id مع التهيئة
  /// حرفاً من «عند التنفيذ» (F-015) حتى لو لم يقرأه أحد بعدها.
  Future<int> createManager(
      {required String name,
      required String login,
      required String passwordHash}) async {
    await deviceId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await (select(roles)
          ..where((t) => t.name.equals('مدير')))
        .getSingleOrNull();
    final roleId = existing != null
        ? existing.id
        : await into(roles).insert(
            RolesCompanion.insert(
              name: 'مدير',
              uuid: const Uuid().v4(),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    return into(appUsers).insert(
      AppUsersCompanion.insert(
        name: name,
        login: login,
        passwordHash: passwordHash,
        roleId: roleId,
        isActive: true,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// بذر الأدوار النمطية الأربعة بأذوناتها الافتراضية (F-080، D-100
  /// معروض) — فاحص الفراغ بالاسم فآمن التكرار أي كان مسار الوصول
  /// (onCreate أو ترحيلة 9→10)، والأدوار القائمة لا تُمسّ أبداً.
  Future<void> _seedDefaultRoles() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in defaultRolesPermissions.entries) {
      final existing = await (select(roles)
            ..where((t) => t.name.equals(entry.key)))
          .getSingleOrNull();
      if (existing != null) continue;
      await into(roles).insert(
        RolesCompanion.insert(
          name: entry.key,
          permissions: Value(entry.value),
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// المستخدم الحالي (F-080/D-100 معروض) — يُخزَّن في app_meta ويبقى
  /// بين الجلسات، والواجهة تفاضله صاحب الرئيسية (فرض الصلاحيات عليه).
  /// الفراغ مشروع: قبل أول تبديل تقع الواجهة على أول مستخدم نشط.
  static const String currentUserMetaKey = 'current_user_id';

  Future<void> setCurrentUserId(int? userId) async {
    if (userId == null) {
      await (delete(appMeta)..where((t) => t.key.equals(currentUserMetaKey)))
          .go();
      return;
    }
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(currentUserMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)..where((t) => t.key.equals(currentUserMetaKey)))
          .write(AppMetaCompanion(value: Value('$userId')));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: currentUserMetaKey,
        value: '$userId',
      ));
    }
  }

  Future<int?> currentUserId() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(currentUserMetaKey)))
        .getSingleOrNull();
    return row == null ? null : int.tryParse(row.value);
  }

  /// المستخدم صاحب الجلسة الحالية — الحالي المخزن إن كان نشطاً، وإلا
  /// أول مستخدم نشط، وإلا أي مستخدم (قاعدة فيها معطلون حصراً)، وإلا
  /// null (قاعدة قبل التهيئة — لا يصلها الواجهة أصلاً ببوابة F-014).
  Future<AppUser?> currentUser() async {
    final users = await select(appUsers).get();
    if (users.isEmpty) return null;
    final storedId = await currentUserId();
    for (final u in users) {
      if (u.id == storedId && u.isActive) return u;
    }
    for (final u in users) {
      if (u.isActive) return u;
    }
    return users.first;
  }

  /// دور المستخدم الحالي وصلاحياته — والواجهة تفاضل بها الرئيسية.
  Future<Role?> roleOf(AppUser user) =>
      (select(roles)..where((t) => t.id.equals(user.roleId)))
          .getSingleOrNull();

  /// تحقق كلمة مرور مستخدم قائم (F-080/D-100 معروض: تبديل المستخدم
  /// بكلمة المرور — لا جلسة بلا تحقق). يعيد صف المستخدم عند النجاح.
  Future<AppUser?> verifyUserPassword(int userId, String password) async {
    final user = await (select(appUsers)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (user == null || !user.isActive) return null;
    if (!PasswordHasher.verifyStored(user.passwordHash, password)) {
      return null;
    }
    return user;
  }

  /// إنشاء دور مخصص بأذوناته (F-080: «إنشاء أدوار مخصصة») — الاسم
  /// الفريد قيد قاعدة البيانات ذاته (UNIQUE) والتكرار يُرفض استثناءً
  /// تلتقطه الواجهة وتعرضه برسالته.
  Future<int> createRole(
      {required String name, required String permissions}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(roles).insert(
      RolesCompanion.insert(
        name: name,
        permissions: Value(permissions),
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// تحديث أذونات دور قائم — الاسم لا يُمسّ (هوية الدور، والسندات
  /// المرجعية به تظل صحيحة).
  Future<void> updateRolePermissions(
      int roleId, String permissions) async {
    await (update(roles)..where((t) => t.id.equals(roleId))).write(
      RolesCompanion(
        permissions: Value(permissions),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// تعيين دور لمستخدم — تعديل الدور وحده، والحالة والبقية لا تُمسّ.
  Future<void> updateUserRole(int userId, int roleId) async {
    await (update(appUsers)..where((t) => t.id.equals(userId))).write(
      AppUsersCompanion(
        roleId: Value(roleId),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// إدراج طرف جديد بأعمدة الاصطلاح (D-055) — يعيد معرّف الصف (س-29).
  ///
  /// العملة تُستلم معبأة من الواجهة ولا تُقبل صفراً هنا حرساً ثانوياً بعد
  /// مدقق المجال (D-066). الهاتف والعنوان الفارغان يسجلان null — اختياريان
  /// (س-29). حد الائتمان null فراغ مشروع «بلا سقف» (س-34).
  Future<int> insertParty({
    required String number,
    required String name,
    required String kind,
    String? phone,
    String? address,
    required int defaultCurrencyId,
    int? creditLimitBaseMinor,
  }) async {
    assert(defaultCurrencyId > 0, 'D-066: عملة الطرف لا تصل فارغة أبداً');
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(parties).insert(
      PartiesCompanion.insert(
        number: number,
        name: name,
        kind: kind,
        phone: Value(_nullIfBlank(phone)),
        address: Value(_nullIfBlank(address)),
        defaultCurrencyId: defaultCurrencyId,
        creditLimitBaseMinor: Value(creditLimitBaseMinor),
        isActive: true,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// تحديث بيانات طرف — الرقم خارج التوقيع أصلاً فلا يعدل بعد الحفظ
  /// (D-063)، والاسم يعدل بحرية مع بقاء قاعدة المنع الحرفي (س-32/D-065).
  /// تخزينه null لحد الائتمان يعني إزالة السقف عمداً (س-34).
  Future<void> updatePartyDetails(
    Party party, {
    required String name,
    required String kind,
    String? phone,
    String? address,
    required int defaultCurrencyId,
    int? creditLimitBaseMinor,
  }) async {
    assert(defaultCurrencyId > 0, 'D-066: عملة الطرف لا تصل فارغة أبداً');
    await (update(parties)..where((t) => t.id.equals(party.id))).write(
      PartiesCompanion(
        name: Value(name),
        kind: Value(kind),
        phone: Value(_nullIfBlank(phone)),
        address: Value(_nullIfBlank(address)),
        defaultCurrencyId: Value(defaultCurrencyId),
        creditLimitBaseMinor: Value(creditLimitBaseMinor),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// س-33: التعطيل والتفعيل بطي is_active حصراً — لا حذف فيزيائي ولا
  /// منطقي هنا: المستندات القائمة تبقى سليمة والطرف يبقى في كشفه
  /// وتقاريره، وإعادة التفعيل ممكنة متى شئت.
  Future<void> setPartyActive(int id, {required bool active}) async {
    await (update(parties)..where((t) => t.id.equals(id))).write(
      PartiesCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// اقتراح الرقم التالي آلياً (D-063/س-29): القراءة من هنا والحساب في
  /// المجال النقي (suggestNextPartyNumber) — مقترح قابل للتعديل قبل
  /// الحفظ حصراً.
  Future<String> nextPartyNumberSuggestion() async {
    final rows = await select(parties).get();
    return suggestNextPartyNumber(rows.map((r) => r.number));
  }

  String? _nullIfBlank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  /// إضافة وحدة قياس أساسية جديدة (F-031/س-41) — الاسم مقلم غير فارغ
  /// وفريد حرفياً (D-074، وقيد UNIQUE حرس ثانوي من القاعدة). إضافة حصراً
  /// في م1: لا تعديل ولا حذف ولا تعطيل (D-075). `is_base` ثابتة true
  /// بقيمتها الافتراضية حتى م2 (D-075).
  Future<int> insertUnit({required String name}) async {
    final clean = name.trim();
    assert(clean.isNotEmpty, 'اسم الوحدة إلزامي (F-031)');
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(units).insert(
      UnitsCompanion.insert(
        name: clean,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// إدراج صنف جديد بأعمدة الاصطلاح (D-055) — يعيد معرّف الصف (س-36).
  ///
  /// الكود والاسم مقلَّمان، والوحدة إلزامية (F-031) وعملة السعر معبأة من
  /// الواجهة ولا تُقبل صفراً حرساً ثانوياً بعد مدقق المجال (D-066
  /// الاصطلاح)، والأسعار بوحدات صغرى صحيحة لا تصل سالبة (س6). الكود لا
  /// يعدل بعد الحفظ (D-073) فلا مسار تحديث له أصلاً.
  Future<int> insertItem({
    required String sku,
    required String name,
    String? category,
    required String kind,
    required int baseUnitId,
    required int purchasePriceMinor,
    required int salePriceMinor,
    required int priceCurrencyId,
  }) async {
    assert(baseUnitId > 0, 'F-031: الوحدة الأساسية إلزامية');
    assert(priceCurrencyId > 0, 'D-066: عملة السعر لا تصل فارغة أبداً');
    assert(purchasePriceMinor >= 0 && salePriceMinor >= 0,
        'س6: لا سعر سالب — والصفر مشروع');
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(items).insert(
      ItemsCompanion.insert(
        sku: sku.trim(),
        name: name.trim(),
        category: Value(_nullIfBlank(category)),
        kind: kind,
        baseUnitId: baseUnitId,
        purchasePriceMinor: purchasePriceMinor,
        salePriceMinor: salePriceMinor,
        priceCurrencyId: priceCurrencyId,
        isActive: true,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// تحديث بيانات صنف — الكود خارج التوقيع أصلاً فلا يعدل بعد الحفظ
  /// (D-073)، والبقية تعدل بحرية مع بقاء قواعد التفرد الحرفي (س-39).
  Future<void> updateItemDetails(
    Item item, {
    required String name,
    String? category,
    required String kind,
    required int baseUnitId,
    required int purchasePriceMinor,
    required int salePriceMinor,
    required int priceCurrencyId,
  }) async {
    assert(baseUnitId > 0, 'F-031: الوحدة الأساسية إلزامية');
    assert(priceCurrencyId > 0, 'D-066: عملة السعر لا تصل فارغة أبداً');
    assert(purchasePriceMinor >= 0 && salePriceMinor >= 0,
        'س6: لا سعر سالب — والصفر مشروع');
    await (update(items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        name: Value(name.trim()),
        category: Value(_nullIfBlank(category)),
        kind: Value(kind),
        baseUnitId: Value(baseUnitId),
        purchasePriceMinor: Value(purchasePriceMinor),
        salePriceMinor: Value(salePriceMinor),
        priceCurrencyId: Value(priceCurrencyId),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// س-40: التعطيل والتفعيل بطي is_active حصراً — لا حذف فيزيائي ولا
  /// منطقي هنا: الصنف يبقى بكشفه وتقاريره والفواتير القائمة سليمة
  /// بإحالتها إلى معرفه، وإعادة التفعيل ممكنة متى شئت.
  Future<void> setItemActive(int id, {required bool active}) async {
    await (update(items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // صورة الصنف والباركود — دفعة (10) «الصور والباركود»
  // (س-123..س-132، D-118..D-126). الملفات نفسها تديرها الواجهة
  // (كتابة/حذف في مجلد بجوار القاعدة D-125) — والتخزين هنا يحمل
  // المسارين النسبيين وقراءات الباركود حصراً.
  // ─────────────────────────────────────────────────────────────────

  /// تثبيت مسارَي صورة صنف بعد كتابة الملفين (س-123) — المسارات نسبية
  /// لمجلد القاعدة كي تعمل بعد الاستعادة على أي جهاز بلا هجرة مسارات.
  Future<void> setItemImages(
    int itemId, {
    required String imageFile,
    required String imageThumb,
  }) async {
    await (update(items)..where((t) => t.id.equals(itemId))).write(
      ItemsCompanion(
        imageFile: Value(imageFile),
        imageThumb: Value(imageThumb),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// حذف صورة صنف بمطابقة (س-124: الحذف بمطابقة يمسح الحقل والملفين
  /// — ملفات المجلد بيد الواجهة).
  Future<void> clearItemImages(int itemId) async {
    await (update(items)..where((t) => t.id.equals(itemId))).write(
      ItemsCompanion(
        imageFile: const Value(null),
        imageThumb: const Value(null),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// س-131: إضافة رمز باركود لصنف — التفرد مضمون بالفهرس القائم
  /// (F-035) وholderBarcode قبل الاستدعاء يحمي برسالة الصنف الحامل
  /// بدل استثناء خام. أكثر من رمز للصنف مشروع تمهيداً لوحدات التعبئة
  /// (م2 — F-035).
  Future<int> insertItemBarcode({
    required int itemId,
    required String barcode,
  }) async {
    final clean = barcode.trim();
    assert(clean.isNotEmpty, 'الرمز إلزامي (س-131)');
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(itemBarcodes).insert(
      ItemBarcodesCompanion.insert(
        itemId: itemId,
        barcode: clean,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// س-131: حذف رمز من بطاقة صنف — حذف فيزيائي لارتباط عرض لا حاجة
  /// لتاريخه (لا محاسبة على رمز)، والرمز الوحيد المتأثر هو هذا الصف.
  Future<void> deleteItemBarcode(int barcodeId) async {
    await (delete(itemBarcodes)..where((t) => t.id.equals(barcodeId))).go();
  }

  /// رموز صنف مرتبة — عرض قسم الباركود في البطاقة (س-131).
  Future<List<ItemBarcode>> barcodesOfItem(int itemId) async {
    return (select(itemBarcodes)
          ..where((t) => t.itemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// صف حامل رمز مكرر — رسالة س-131 الحرفية: «الرمز مستخدم للصنف:
  /// <الاسم (الكود)>» — الاسم والكود من صنفه الحي (المعطل ما زال
  /// حاجزاً فاسمه وكوده محجوزان).
  Future<BarcodeHolderRow?> barcodeHolder(String barcode) async {
    final rows = await customSelect(
      'SELECT b.id AS barcode_id, b.item_id AS item_id, '
      'i.sku AS sku, i.name AS name '
      'FROM item_barcodes b JOIN items i ON i.id = b.item_id '
      'WHERE b.barcode = ?1 AND b.is_deleted = 0 AND i.is_deleted = 0 '
      'LIMIT 1',
      variables: [Variable.withString(barcode.trim())],
    ).get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return BarcodeHolderRow(
      barcodeId: r.data['barcode_id'] as int,
      itemId: r.data['item_id'] as int,
      sku: r.data['sku'] as String,
      name: r.data['name'] as String,
    );
  }

  /// س-132: فهرس الرموز كلها بمعرفات أصنافها — خانة بحث البنود
  /// (المطابقة الكاملة قارئ البلوتوث) وخانة اقتراحاتها.
  Future<Map<int, List<String>>> barcodeIndexByItem() async {
    final rows = await customSelect(
      'SELECT item_id, barcode FROM item_barcodes '
      'WHERE is_deleted = 0 ORDER BY id',
    ).get();
    final out = <int, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r.data['item_id'] as int, () => []).add(
            r.data['barcode'] as String,
          );
    }
    return out;
  }

  /// س-132: صنف رمز كامل — الطريق المباشر للقارئ. null = رمز غير
  /// مرتبط بأي صنف (رسالة السيناريو الحرفية).
  Future<int?> itemIdByBarcode(String barcode) async {
    final rows = await customSelect(
      'SELECT item_id FROM item_barcodes '
      'WHERE barcode = ?1 AND is_deleted = 0 LIMIT 1',
      variables: [Variable.withString(barcode.trim())],
    ).get();
    return rows.isEmpty ? null : rows.first.data['item_id'] as int;
  }

  // ─────────────────────────────────────────────────────────────────
  // قلب الدفتر — دفعة م1 الثالثة (س-42..س-50، D-076..D-078 معروضة):
  // المُشغِّلات الحواجز + البذر + المحرك (مسودة/ترحيل/عكس/حذف مسودة)
  // + القارئات النقية التي تمرر الحساب للمجال (التخزين يحفظ ولا يقرر).
  // ─────────────────────────────────────────────────────────────────

  /// المُشغِّلات الحواجز (07 §2.2 نمط D-067 — الحاجز الثاني المختبَر):
  /// (1) التوازن والحد الأدنى للأسطر عند الانتقال إلى «مرحّل»، (2) تجميد
  /// القيد المرحّل حقلاً حقلاً، (3) منع حذفه، و(4..6) تجميد أسطره إدراجاً
  /// وتعديلاً وحذفاً (F-055). الرمي RAISE(ABORT) يتراجع المعاملة كاملة
  /// فلا حالة وسطى (07 §2.4). IF NOT EXISTS فآمنة التكرار أي كان مسار
  /// الوصول (onCreate أو ترحيلة 5→6).
  Future<void> _createLedgerTriggers() async {
    const triggers = <String>[
      "CREATE TRIGGER IF NOT EXISTS trg_moves_post_balance "
          "BEFORE UPDATE ON moves FOR EACH ROW "
          "WHEN NEW.state = 'posted' AND OLD.state <> 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'قيد غير متوازن: مجموع المدين لا يساوي "
          "مجموع الدائن') "
          "WHERE (SELECT COALESCE(SUM(debit_minor),0) FROM move_lines "
          "WHERE move_id = NEW.id) <> "
          "(SELECT COALESCE(SUM(credit_minor),0) FROM move_lines "
          "WHERE move_id = NEW.id); "
          "SELECT RAISE(ABORT, 'قيد مرحّل بأسطر أقل من اثنين') "
          "WHERE (SELECT COUNT(*) FROM move_lines WHERE move_id = NEW.id) "
          "< 2; "
          "END",
      "CREATE TRIGGER IF NOT EXISTS trg_moves_posted_frozen "
          "BEFORE UPDATE ON moves FOR EACH ROW "
          "WHEN OLD.state = 'posted' AND ("
          "NEW.journal_id IS NOT OLD.journal_id OR "
          "NEW.date_text IS NOT OLD.date_text OR "
          "NEW.state IS NOT OLD.state OR "
          "NEW.number IS NOT OLD.number OR "
          "COALESCE(NEW.narration,'') IS NOT COALESCE(OLD.narration,'') OR "
          "COALESCE(NEW.ref_doc_type,'') IS NOT "
          "COALESCE(OLD.ref_doc_type,'') OR "
          "COALESCE(NEW.ref_doc_id,-1) IS NOT COALESCE(OLD.ref_doc_id,-1) OR "
          "COALESCE(NEW.period_id,-1) IS NOT COALESCE(OLD.period_id,-1)) "
          "BEGIN "
          "SELECT RAISE(ABORT, 'القيد المرحّل لا يعدل — التصحيح بقيد عكس'); "
          "END",
      "CREATE TRIGGER IF NOT EXISTS trg_moves_no_delete_posted "
          "BEFORE DELETE ON moves FOR EACH ROW "
          "WHEN OLD.state = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'القيد المرحّل لا يحذف — التصحيح بقيد عكس'); "
          "END",
      "CREATE TRIGGER IF NOT EXISTS trg_move_lines_frozen_insert "
          "BEFORE INSERT ON move_lines FOR EACH ROW "
          "WHEN (SELECT state FROM moves WHERE id = NEW.move_id) = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'أسطر القيد المرحّل لا تضاف'); END",
      "CREATE TRIGGER IF NOT EXISTS trg_move_lines_frozen_update "
          "BEFORE UPDATE ON move_lines FOR EACH ROW "
          "WHEN (SELECT state FROM moves WHERE id = NEW.move_id) = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'أسطر القيد المرحّل لا تعدل'); END",
      "CREATE TRIGGER IF NOT EXISTS trg_move_lines_frozen_delete "
          "BEFORE DELETE ON move_lines FOR EACH ROW "
          "WHEN (SELECT state FROM moves WHERE id = OLD.move_id) = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'أسطر القيد المرحّل لا تحذف'); END",
    ];
    for (final sql in triggers) {
      await customStatement(sql);
    }
  }

  /// بذر خط القاعدة المحاسبي (س-42): الدليل الافتراضي حرفاً من 03 §3
  /// («الدليل إعداد لا كود» — 07 §1.6)، والدفاتر الخمسة بنيةً جاهزة
  /// (D-076)، وسنة «الآن» بفتراتها الشهرية الافتراضية المفتوحة (D-027).
  /// كل شطر فاحص الفراغ ذاته فالبذر آمن التكرار، والترتيب الهرمي للدليل
  /// (كل أب يسبق أبناءه — كما في 03) هو ما يجعل خريطة الأكواد تصلح أباً.
  Future<void> _seedAccountingBaseline() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingAccounts = await select(accounts).get();
    if (existingAccounts.isEmpty) {
      final codeToId = <String, int>{};
      for (final spec in defaultChartOfAccounts) {
        assert(
            spec.parentCode == null || codeToId.containsKey(spec.parentCode),
            'ترتيب الدليل الهرمي: كل أب يسبق أبناءه (${spec.code})');
        final id = await into(accounts).insert(
          AccountsCompanion.insert(
            code: spec.code,
            name: spec.name,
            type: spec.type.name,
            normalSide: spec.effectiveNormalSide.name,
            parentId:
                Value(spec.parentCode == null ? null : codeToId[spec.parentCode!]),
            isLeaf: spec.isLeaf,
            isActive: spec.isActive,
            uuid: const Uuid().v4(),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        codeToId[spec.code] = id;
      }
    }
    final existingJournals = await select(journals).get();
    if (existingJournals.isEmpty) {
      for (final spec in defaultJournals) {
        await into(journals).insert(
          JournalsCompanion.insert(
            code: spec.code,
            name: spec.name,
            kind: spec.kind.name,
            uuid: const Uuid().v4(),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    }
    final existingYears = await select(fiscalYears).get();
    if (existingYears.isEmpty) {
      final year = DateTime.now().year;
      final yearId = await into(fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: year.toString(),
          startDateText: '$year-01-01',
          endDateText: '$year-12-31',
          state: 'open',
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      for (var month = 1; month <= 12; month++) {
        final mm = month.toString().padLeft(2, '0');
        final lastDay = DateTime(year, month + 1, 0).day;
        await into(periods).insert(
          PeriodsCompanion.insert(
            fiscalYearId: yearId,
            startDateText: '$year-$mm-01',
            endDateText: '$year-$mm-${lastDay.toString().padLeft(2, '0')}',
            state: 'open',
            uuid: const Uuid().v4(),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    }
  }

  /// لقطة القيد الكاملة JSON للسجل (07 §2.3/D-067) — تُكتب لحظة الحدث
  /// فتحفظ الحالة كما كانت لا كما صارت.
  Future<String> _moveSnapshot(int moveId) async {
    final moveRow =
        await (select(moves)..where((t) => t.id.equals(moveId))).getSingle();
    final lineRows =
        await (select(moveLines)..where((t) => t.moveId.equals(moveId))).get();
    return jsonEncode(<String, Object?>{
      'id': moveRow.id,
      'uuid': moveRow.uuid,
      'journal_id': moveRow.journalId,
      'date': moveRow.dateText,
      'state': moveRow.state,
      'number': moveRow.number,
      'narration': moveRow.narration,
      'ref_doc_type': moveRow.refDocType,
      'ref_doc_id': moveRow.refDocId,
      'lines': [
        for (final l in lineRows)
          <String, Object?>{
            'account_id': l.accountId,
            'debit_minor': l.debitMinor,
            'credit_minor': l.creditMinor,
            'party_id': l.partyId,
            'currency_id': l.currencyId,
            'amount_minor': l.amountMinor,
            'fx_rate': l.fxRate,
            'uuid': l.uuid,
          }
      ],
    });
  }

  Future<void> _recordMoveEvent({
    required int moveId,
    required String action,
    String? payload,
  }) async {
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: DateTime.now().millisecondsSinceEpoch,
        deviceId: await deviceId(),
        entityType: 'move',
        entityId: Value(moveId),
        action: action,
        payload: payload ?? await _moveSnapshot(moveId),
        uuid: const Uuid().v4(),
      ),
    );
  }

  /// س-43: إنشاء قيد مسودة متوازن — المدقق حرس التخزين الثاني بعد مدقق
  /// الواجهة: لا مسار يكتب قيداً غير مدقق (07 §1.1). القيد وأسطره وحدثه
  /// («created» بلقطته) معاملة واحدة (07 §2.4).
  Future<int> createMoveDraft({
    required int journalId,
    required String dateText,
    String? narration,
    String? refDocType,
    int? refDocId,
    required List<MoveLineDraft> lines,
  }) async {
    final draft = MoveDraft(
      journalId: journalId,
      dateText: dateText,
      narration: narration,
      refDocType: refDocType,
      refDocId: refDocId,
      lines: lines,
    );
    final errors =
        validateMoveDraft(draft, index: LedgerAccountIndex.build(
            await allLedgerAccounts()));
    if (errors.isNotEmpty) {
      throw LedgerValidationException(errors);
    }
    return transaction(() => _insertMoveDraftWithinTx(draft));
  }

  /// الشطر الداخلي لإدراج مسودة قيد — يُستدعى داخل معاملة قائمة حصراً:
  /// محرك الفواتير (دفعة 4) يعيد استخدامه داخل معاملة الترحيل الواحدة
  /// فلا مسار يكتب قيداً خارج هذا الشطر (D-079). حقول العملات (F-174)
  /// تُملأ من مستنداتها واليدوية تتركها فارغة.
  Future<int> _insertMoveDraftWithinTx(MoveDraft draft) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final moveId = await into(moves).insert(
      MovesCompanion.insert(
        journalId: draft.journalId,
        dateText: draft.dateText,
        state: 'draft',
        number: '',
        narration: Value(draft.narration),
        refDocType: Value(draft.refDocType),
        refDocId: Value(draft.refDocId),
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    for (final line in draft.lines) {
      await into(moveLines).insert(
        MoveLinesCompanion.insert(
          moveId: moveId,
          accountId: line.accountId,
          debitMinor: Value(line.debitMinor),
          creditMinor: Value(line.creditMinor),
          partyId: Value(line.partyId),
          currencyId: Value(line.currencyId ?? 1),
          amountMinor: Value(line.amountMinor),
          fxRate: Value(line.fxRate),
          refStockMoveId: Value(line.refStockMoveId),
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
    await _recordMoveEvent(moveId: moveId, action: 'created');
    return moveId;
  }

  /// س-46/س-47: ترحيل المسودة — المحرك الحاكم (07 §1.1): المدقق الحاكم
  /// (قواعد المسودة + الفترة المفتوحة — 07 §1.5)، والترقيم المركزي داخل
  /// المعاملة ذاتها فلا رقم يُصدر بلا قيد مكتوب (07 §1.9/§2.4)، والحاجز
  /// الثاني مُشغِّلات القاعدة تتحقق عند كتابة الحالة، وأي رفض يتراجع كل
  /// شيء. والحدث «posted» بلقطة القيد المرحّل في المعاملة نفسها.
  Future<int> postMove(int moveId) =>
      transaction(() => _postMoveWithinTx(moveId,
          sequenceKind: ledgerMoveSequenceKind));

  /// تقدّم عدّاد تسلسل مركزي داخل معاملة قائمة — يعيد الرقم التالي
  /// ويكتبه في المعاملة ذاتها فلا رقم يُصدر بلا قيد مكتوب ولا عدّاد
  /// يُلمس بلا ترحيل ناجح (07 §1.9/§2.4). مشترك بين القيود اليدوية
  /// وقيود المستندات المولدة (D-080 معروض).
  Future<int> _advanceSequenceWithinTx(String kind, int year) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seqRow = await (select(sequences)
          ..where((t) => t.kind.equals(kind) & t.year.equals(year)))
        .getSingleOrNull();
    final nextNumber =
        seqRow == null ? 1 : nextSequenceNumber(seqRow.lastNumber);
    if (seqRow == null) {
      await into(sequences).insert(
        SequencesCompanion.insert(
          kind: kind,
          year: year,
          lastNumber: nextNumber,
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    } else {
      await (update(sequences)
            ..where((t) => t.kind.equals(kind) & t.year.equals(year)))
          .write(SequencesCompanion(
        lastNumber: Value(nextNumber),
        updatedAt: Value(now),
      ));
    }
    return nextNumber;
  }

  /// الشطر الداخلي للترحيل — داخل معاملة قائمة حصراً (المرجع نفسه):
  /// [sequenceKind] نوع التسلسل المركزي (قيود يدوية move_general وقيود
  /// المستندات من دفتر جهتها — D-080 معروض).
  Future<int> _postMoveWithinTx(
    int moveId, {
    required String sequenceKind,
  }) async {
      final moveRow = await (select(moves)
            ..where((t) => t.id.equals(moveId)))
          .getSingleOrNull();
      if (moveRow == null) {
        throw StateError('لا قيد بالمعرف $moveId');
      }
      if (moveRow.state == 'posted') {
        throw StateError(
            'القيد مرحّل أصلاً — الآلة مسودة ← مرحّل بلا رجوع (07 §1.2)');
      }
      final lineRows = await (select(moveLines)
            ..where((t) => t.moveId.equals(moveId)))
          .get();
      final draft = MoveDraft(
        journalId: moveRow.journalId,
        dateText: moveRow.dateText,
        narration: moveRow.narration,
        refDocType: moveRow.refDocType,
        refDocId: moveRow.refDocId,
        lines: [
          for (final l in lineRows)
            MoveLineDraft(
              accountId: l.accountId,
              partyId: l.partyId,
              debitMinor: l.debitMinor,
              creditMinor: l.creditMinor,
            )
        ],
      );
      final index =
          LedgerAccountIndex.build(await allLedgerAccounts());
      // كل الفترات لا المفتوحة حصراً — كي يميز المدقق فترةً مقفلة
      // (MoveClosedPeriod) عن تاريخ بلا فترة (MoveNoPeriod): رسالة
      // المالك الصادقة تختلف بين الحالتين (07 §1.5).
      final periodInfos = await ledgerPeriods();
      final errors = validateMoveForPosting(
        draft,
        index: index,
        periods: periodInfos,
      );
      if (errors.isNotEmpty) {
        throw LedgerValidationException(errors);
      }
      final period = findPeriodForDate(periodInfos, moveRow.dateText)!;

      // الترقيم المركزي داخل المعاملة ذاتها (07 §1.9) — الأرقام المُصدَرة
      // لا تُعاد أبداً: العدّاد يزحف عند الترحيل الناجح حصراً.
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(moveRow.dateText);
      final nextNumber = await _advanceSequenceWithinTx(sequenceKind, year);
      final numberText =
          '$year/${nextNumber.toString().padLeft(6, '0')}';

      // الحاجز الثاني (07 §2.2): المُشغِّلات تفحص التوازن والأسطر عند
      // كتابة الحالة — ورفضها ABORT يتراجع المعاملة كاملة بما فيه العدّاد.
      await (update(moves)..where((t) => t.id.equals(moveId))).write(
        MovesCompanion(
          state: const Value('posted'),
          number: Value(numberText),
          periodId: Value(period.id),
          updatedAt: Value(now),
        ),
      );
      await _recordMoveEvent(moveId: moveId, action: 'posted');
      return moveId;
  }

  /// س-48: مسودة العكس لقيد مرحّل (07 §1.3) — الأسطر نفسها بجانبين
  /// متقابلين، والوصف الافتراضي «عكس قيد 2026/000001» والمرجع محفوظ
  /// (ref_doc_type='move'). تُنشأ مسودةً بكل حواجز الإنشاء ثم يرحّلها
  /// المحرك نفسه (postMove) فلا مسار عكس بلا فحص. وأي محاولة عكس قيد
  /// غير مرحّل رفض صريح — العكس للمرحّل وحده.
  Future<int> createReversalDraft(
    int postedMoveId, {
    required String reversalDateText,
    String? narration,
  }) async {
    final original = await (select(moves)
          ..where((t) => t.id.equals(postedMoveId)))
        .getSingleOrNull();
    if (original == null) {
      throw StateError('لا قيد بالمعرف $postedMoveId');
    }
    if (original.state != 'posted') {
      throw StateError('العكس يقتصر على قيد مرحّل (07 §1.3)');
    }
    final lineRows = await (select(moveLines)
          ..where((t) => t.moveId.equals(postedMoveId)))
        .get();
    final reversal = buildReversalMoveDraft(
      journalId: original.journalId,
      originalLines: [
        for (final l in lineRows)
          LedgerLine(
            moveId: l.moveId,
            accountId: l.accountId,
            debitMinor: l.debitMinor,
            creditMinor: l.creditMinor,
          )
      ],
      originalLabel: original.number,
      reversalDateText: reversalDateText,
      originalMoveId: postedMoveId,
      narration: narration,
    );
    final moveId = await createMoveDraft(
      journalId: reversal.journalId,
      dateText: reversal.dateText,
      narration: reversal.narration,
      refDocType: reversal.refDocType,
      refDocId: reversal.refDocId,
      lines: reversal.lines,
    );
    await _recordMoveEvent(moveId: moveId, action: 'reversal_created');
    return moveId;
  }

  /// حذف مسودة (07 §1.3: «حذف المسودات مسموح») — باللقطة كاملة في سجل
  /// الأحداث (السجل يوثق حتى إلغاء المسودات) والمرحّل مستحيل الحذف
  /// حرساً هنا ومشغلاً في القاعدة (05 §7-4).
  Future<void> deleteMoveDraft(int moveId) async {
    return transaction(() async {
      final moveRow = await (select(moves)
            ..where((t) => t.id.equals(moveId)))
          .getSingleOrNull();
      if (moveRow == null) return;
      if (moveRow.state == 'posted') {
        throw StateError(
            'حذف القيد المرحّل مستحيل — التصحيح بقيد عكس (07 §1.3)');
      }
      final snapshot = await _moveSnapshot(moveId);
      await (delete(moveLines)..where((t) => t.moveId.equals(moveId))).go();
      await (delete(moves)..where((t) => t.id.equals(moveId))).go();
      await into(events).insert(
        EventsCompanion.insert(
          eventAt: DateTime.now().millisecondsSinceEpoch,
          deviceId: await deviceId(),
          entityType: 'move',
          entityId: Value(moveId),
          action: 'draft_deleted',
          payload: snapshot,
          uuid: const Uuid().v4(),
        ),
      );
    });
  }

  /// قراءة الحسابات بترتيب أكوادها (1، 11، 111، 1111 — فرز الدليل
  /// المعجمي الصحيح) بصورتها النقية — التخزين يقرأ ولا يحسب.
  Future<List<AccountInfo>> allLedgerAccounts() async {
    final rows = await (select(accounts)
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();
    return [
      for (final r in rows)
        AccountInfo(
          id: r.id,
          code: r.code,
          name: r.name,
          type: AccountType.values.byName(r.type),
          normalSide: NormalSide.values.byName(r.normalSide),
          parentId: r.parentId,
          isLeaf: r.isLeaf,
          isActive: r.isActive,
        )
    ];
  }

  /// قراءة الفترات بصورتها النقية — فحص الترحيل للمجال.
  Future<List<PeriodInfo>> ledgerPeriods() async {
    final rows = await select(periods).get();
    return [
      for (final p in rows)
        PeriodInfo(
          id: p.id,
          fiscalYearId: p.fiscalYearId,
          startDateText: p.startDateText,
          endDateText: p.endDateText,
          isOpen: p.state == 'open',
        )
    ];
  }

  /// أسطر القيود المرحّلة (واختيارياً حساب واحد) — المواد الخام للرصيد
  /// والميزان، والحساب للمجال (computeAccountBalance/trialBalanceTotals).
  Future<List<LedgerLine>> postedLedgerLines({int? accountId}) async {
    final rows = await customSelect(
      "SELECT l.move_id AS move_id, l.account_id AS account_id, "
      "l.debit_minor AS debit_minor, l.credit_minor AS credit_minor "
      "FROM move_lines l JOIN moves m ON m.id = l.move_id "
      "WHERE m.state = 'posted'" +
          (accountId == null ? '' : ' AND l.account_id = ?'),
      variables: accountId == null
          ? const <Variable>[]
          : <Variable>[Variable.withInt(accountId)],
    ).get();
    return [
      for (final r in rows)
        LedgerLine(
          moveId: r.data['move_id'] as int,
          accountId: r.data['account_id'] as int,
          debitMinor: r.data['debit_minor'] as int,
          creditMinor: r.data['credit_minor'] as int,
        )
    ];
  }

  /// رصيد حساب ورقي بالاتجاه الطبيعي من المرحّل حصراً (س-50) — القراءة
  /// هنا والحساب بدالة المجال النقية ذاتها المستعملة بالاختبارات.
  Future<int> accountBalanceOf(int accountId) async {
    final accountRow = await (select(accounts)
          ..where((t) => t.id.equals(accountId)))
        .getSingle();
    final accountInfo = AccountInfo(
      id: accountRow.id,
      code: accountRow.code,
      name: accountRow.name,
      type: AccountType.values.byName(accountRow.type),
      normalSide: NormalSide.values.byName(accountRow.normalSide),
      parentId: accountRow.parentId,
      isLeaf: accountRow.isLeaf,
      isActive: accountRow.isActive,
    );
    return computeAccountBalance(
      await postedLedgerLines(accountId: accountId),
      accountInfo,
    );
  }

  /// مجاميع ميزان المراجعة الافتراضي من المرحّل حصراً (س-50) — والحساب
  /// بدالة المجال النقية ذاتها.
  Future<(int, int)> trialBalanceTotalsOf() async {
    return trialBalanceTotals(await postedLedgerLines());
  }

  /// فحص الثوابت الآلي الكامل (F-006، 07 §1.10، D-067) — دفعة إغلاق
  /// النواة (س37). سبعة فحوص قراءةً خالصة لا تكتب شيئاً ولا ترمي
  /// استثناءً: الخرق يُجمع في التقرير ولا يُعالج هنا (الخرق يعالجه
  /// المالك بيد المحاسب، والفحص صاحب الإيقاف هو مدققات المحرك
  /// ومُشغِّلات الحواجز أثناء الكتابة). يُستدعى من بطاقة الإعدادات
  /// بيد المالك ومن الرئيسية افتتاحياً صامتاً (D-099 معروض).
  Future<IntegrityReport> integrityCheckReport() async {
    final violations = <IntegrityViolation>[];

    // T1 — توازن القيود المرحّلة: مجموع المدين يساوي الدائن في كل
    // قيد مرحّل (المُشغِّل يحرس الانتقال والفحص يكشف أي طعن خارجي).
    final unbalanced = await customSelect(
      'SELECT m.number AS number, '
      'SUM(l.debit_minor) AS d, SUM(l.credit_minor) AS c '
      'FROM moves m JOIN move_lines l ON l.move_id = m.id '
      "WHERE m.state = 'posted' AND m.is_deleted = 0 "
      'GROUP BY m.id HAVING d <> c',
    ).get();
    for (final r in unbalanced) {
      violations.add(IntegrityViolation(
        checkCode: 'T1',
        detail: 'القيد ${r.data['number']} — مدين ${r.data['d']} '
            'لا يساوي دائن ${r.data['c']}',
      ));
    }

    // T2 — عدم سالبية المخزون: كمية أو قيمة سالبة في أرصدة المخزون.
    final negativeStock = await customSelect(
      'SELECT item_id, warehouse_id, qty_base, total_value_minor '
      'FROM stock_balances WHERE qty_base < 0 OR total_value_minor < 0',
    ).get();
    for (final r in negativeStock) {
      violations.add(IntegrityViolation(
        checkCode: 'T2',
        detail: 'صنف #${r.data['item_id']} بمستودع '
            '#${r.data['warehouse_id']} — كمية ${r.data['qty_base']} '
            'وقيمة ${r.data['total_value_minor']}',
      ));
    }

    // T3 — لا حركة صندوق يتيمة: كل حركة صندوق بمستند مرحّل (فاتورة أو
    // سند أو تحويل أو تسوية) — الحركة اليتيمة بلا مستند مرحّل خرق N-009.
    final orphanMoves = await customSelect(
      'SELECT COUNT(*) AS n FROM cash_movements cm '
      'WHERE cm.is_deleted = 0 AND NOT ('
      "  (cm.ref_doc_type = 'invoice' AND EXISTS ("
      '    SELECT 1 FROM invoices i WHERE i.id = cm.ref_doc_id '
      "    AND i.state IN ('posted', 'paid', 'partially_paid'))) OR "
      "  (cm.ref_doc_type = 'voucher' AND EXISTS ("
      '    SELECT 1 FROM vouchers v WHERE v.id = cm.ref_doc_id '
      "    AND v.state = 'posted')) OR "
      "  (cm.ref_doc_type = 'box_transfer' AND EXISTS ("
      '    SELECT 1 FROM box_transfers b WHERE b.id = cm.ref_doc_id '
      "    AND b.state = 'posted')) OR "
      "  (cm.ref_doc_type = 'cash_adjustment' AND EXISTS ("
      '    SELECT 1 FROM cash_adjustments a WHERE a.id = cm.ref_doc_id '
      "    AND a.state = 'posted')))",
    ).get();
    final orphanCount = orphanMoves.first.data['n'] as int;
    if (orphanCount > 0) {
      violations.add(IntegrityViolation(
        checkCode: 'T3',
        detail: '$orphanCount حركة صندوق بلا مستند مرحّل',
      ));
    }

    // T4 — كل فاتورة مرحّلة لها قيد مرتبط (ref_doc_type/ref_doc_id).
    final unlinkedInvoices = await customSelect(
      'SELECT i.number AS number FROM invoices i '
      "WHERE i.state IN ('posted', 'paid', 'partially_paid') "
      'AND NOT EXISTS ('
      '  SELECT 1 FROM moves m WHERE m.ref_doc_type = \'invoice\' '
      '  AND m.ref_doc_id = i.id AND m.state = \'posted\')',
    ).get();
    for (final r in unlinkedInvoices) {
      violations.add(IntegrityViolation(
        checkCode: 'T4',
        detail: 'الفاتورة ${r.data['number']} مرحّلة بلا قيد مرتبط',
      ));
    }

    // M1 — مطابقة D-067 الأولى: رصيد كل حساب صندوق (111x) في الدفتر =
    // رصيد الصندوق المحسوب (الافتتاحي + الداخل − الخارج).
    final boxes = await customSelect(
      'SELECT b.id AS box_id, b.name AS name, b.account_id AS account_id '
      'FROM cash_boxes b WHERE b.is_deleted = 0 ORDER BY b.id',
    ).get();
    for (final r in boxes) {
      final boxId = r.data['box_id'] as int;
      final ledger = await accountBalanceOf(r.data['account_id'] as int);
      final box = await _cashBoxBalanceTx(boxId);
      if (ledger != box) {
        violations.add(IntegrityViolation(
          checkCode: 'M1',
          detail: 'الصندوق «${r.data['name']}» — الدفتر $ledger '
              'لا يساوي الصندوق $box',
        ));
      }
    }

    // M2 — مطابقة D-067 الثانية: رصيد حساب المخزون 113 = قيمة المخزون
    // المحسوبة من stock_balances (total_value_minor).
    final stock113 = await customSelect(
      "SELECT id FROM accounts WHERE code = '113'",
    ).get();
    if (stock113.isNotEmpty) {
      final ledger = await accountBalanceOf(stock113.first.data['id'] as int);
      final inventoryRow = await customSelect(
        'SELECT COALESCE(SUM(total_value_minor), 0) AS v FROM stock_balances',
      ).get();
      final inventory = inventoryRow.first.data['v'] as int;
      if (ledger != inventory) {
        violations.add(IntegrityViolation(
          checkCode: 'M2',
          detail: 'حساب 113 في الدفتر $ledger لا يساوي قيمة المخزون $inventory',
        ));
      }
    }

    // M3 — مطابقة D-067 الثالثة: رصيدا حسابَي السيطرة 112/211 في
    // الدفتر = مجموع أرصدة الأطراف عليهما — وبحث الحوامل اليتيمة:
    // سطر ذمة بلا طرف أو بطرف غائب ينكسر به التجميع فخرق قائم.
    final orphanPartyLines = await customSelect(
      'SELECT COUNT(*) AS n FROM move_lines ml '
      'JOIN moves m ON m.id = ml.move_id '
      'JOIN accounts a ON a.id = ml.account_id '
      "WHERE m.state = 'posted' AND a.code IN ('112', '211') "
      'AND (ml.party_id IS NULL OR NOT EXISTS ('
      '  SELECT 1 FROM parties p WHERE p.id = ml.party_id))',
    ).get();
    final orphanPartyCount = orphanPartyLines.first.data['n'] as int;
    if (orphanPartyCount > 0) {
      violations.add(IntegrityViolation(
        checkCode: 'M3',
        detail: '$orphanPartyCount سطر ذمة بلا طرف صحيح على 112/211',
      ));
    }
    final controlCodes = <String>['112', '211'];
    for (final code in controlCodes) {
      // المجموع الخام (مدين − دائن) على الجهتين — موحّد الصيغة حتى لا
      // يرفع حساب 211 (دائن الطبيعة) خرقاً كاذباً بالاتجاه الطبيعي.
      final ledgerRow = await customSelect(
        'SELECT COALESCE(SUM(l.debit_minor) - SUM(l.credit_minor), 0) AS s '
        'FROM move_lines l '
        'JOIN moves m ON m.id = l.move_id '
        'JOIN accounts a ON a.id = l.account_id '
        "WHERE m.state = 'posted' AND a.code = ?",
        variables: [Variable.withString(code)],
      ).get();
      final ledger = ledgerRow.first.data['s'] as int;
      final partySum = await customSelect(
        'SELECT COALESCE(SUM(net), 0) AS s FROM ('
        'SELECT SUM(ml.debit_minor) - SUM(ml.credit_minor) AS net '
        'FROM move_lines ml '
        'JOIN moves m ON m.id = ml.move_id '
        'JOIN accounts a ON a.id = ml.account_id '
        "WHERE m.state = 'posted' AND a.code = ? "
        'AND ml.party_id IS NOT NULL '
        'GROUP BY ml.party_id)',
        variables: [Variable.withString(code)],
      ).get();
      final parties = partySum.first.data['s'] as int;
      if (ledger != parties) {
        violations.add(IntegrityViolation(
          checkCode: 'M3',
          detail: 'حساب $code في الدفتر $ledger لا يساوي مجموع الأطراف '
              '$parties',
        ));
      }
    }

    return IntegrityReport(violations);
  }

/// إنشاء جداول الفواتير الثمانية (05 §3.3/§4/§5 + أعمدة الاصطلاح D-055)
/// — IF NOT EXISTS فآمنة التكرار أي كان مسار الوصول (onCreate أو 6→7).
/// أعمدة القيم التوثيقية الإضافية موثقة في D-079: `value_base_minor` في
/// حركة المخزون (لقطة F-140 الكاملة إلى جانب كلفة الوحدة) و
/// `amount_base_minor`/`fx_rate` في حركة الصندوق (نمط F-122) و
/// `line_total_doc_minor` في سطر الفاتورة (المكافئ التوثيقي) و
/// `account_id` في الصندوق (قاعدة 03 §3 ذاتها).
Future<void> _createInvoiceTables() async {
  const statements = <String>[
    'CREATE TABLE IF NOT EXISTS "currencies" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"code" TEXT NOT NULL UNIQUE, '
        '"name" TEXT NOT NULL, '
        '"minor_units" INTEGER NOT NULL, '
        '"is_base" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "warehouses" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"name" TEXT NOT NULL UNIQUE, '
        '"is_active" INTEGER NOT NULL DEFAULT 1, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "cash_boxes" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"name" TEXT NOT NULL UNIQUE, '
        '"currency_id" INTEGER NOT NULL, '
        '"account_id" INTEGER NOT NULL, '
        '"opening_balance_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "invoices" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"kind" TEXT NOT NULL, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"party_id" INTEGER NULL, '
        '"cash_box_id" INTEGER NULL, '
        '"warehouse_id" INTEGER NULL, '
        '"invoice_date" TEXT NOT NULL, '
        '"due_date" TEXT NULL, '
        '"currency_id" INTEGER NOT NULL DEFAULT 1, '
        '"fx_rate" INTEGER NOT NULL, '
        '"discount_rate" INTEGER NOT NULL DEFAULT 0, '
        '"subtotal_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"discount_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"total_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"total_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"state" TEXT NOT NULL DEFAULT \'draft\', '
        '"move_id" INTEGER NULL, '
        '"original_invoice_id" INTEGER NULL, '
        '"narration" TEXT NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "invoice_lines" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"invoice_id" INTEGER NOT NULL, '
        '"item_id" INTEGER NOT NULL, '
        '"unit_id" INTEGER NOT NULL, '
        '"factor_at_entry" INTEGER NOT NULL DEFAULT 1, '
        '"qty" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL, '
        '"unit_price_minor" INTEGER NOT NULL DEFAULT 0, '
        '"discount_minor" INTEGER NOT NULL DEFAULT 0, '
        '"tax_rate" INTEGER NOT NULL DEFAULT 0, '
        '"line_total_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"line_total_base_minor" INTEGER NOT NULL DEFAULT 0, '
        // v13 (دفعة 12/D-131/D-132): علم التسليم والمورد المسؤول —
        // علم عمل لا محاسبة، والافتراضي غير مستلم بلفظ المالك.
        '"delivered" INTEGER NOT NULL DEFAULT 0, '
        '"supplier_party_id" INTEGER NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "stock_moves" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"item_id" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL, '
        '"from_warehouse_id" INTEGER NULL, '
        '"to_warehouse_id" INTEGER NULL, '
        '"value_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"unit_cost_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"state" TEXT NOT NULL DEFAULT \'posted\', '
        '"ref_doc_type" TEXT NOT NULL, '
        '"ref_doc_id" INTEGER NOT NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "stock_balances" ('
        '"item_id" INTEGER NOT NULL, '
        '"warehouse_id" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL DEFAULT 0, '
        '"total_value_minor" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY ("item_id", "warehouse_id"))',
    'CREATE TABLE IF NOT EXISTS "cash_movements" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"cash_box_id" INTEGER NOT NULL, '
        '"kind" TEXT NOT NULL, '
        '"amount_minor" INTEGER NOT NULL, '
        '"amount_base_minor" INTEGER NOT NULL, '
        '"fx_rate" INTEGER NOT NULL, '
        '"ref_doc_type" TEXT NOT NULL, '
        '"ref_doc_id" INTEGER NOT NULL, '
        '"user_id" INTEGER NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

/// المُشغِّلات الحواجز لجداول الفواتير — الحاجز الثاني المختبَر بعد فحص
/// المحرك (07 §2.2 نمط D-067): منع سالب المخزون والصندوق، تجميد لقطات
/// الحركات، تجميد الفاتورة المرحّلة وأسطرها، ومنع حذفها (05 §7-4).
Future<void> _createInvoiceTriggers() async {
  const triggers = <String>[
    // منع سالب المخزون (F-042/05 §7-2) — الدلتا سالبة ترفض قبل الكتابة
    "CREATE TRIGGER IF NOT EXISTS trg_stock_balances_no_negative "
        "BEFORE UPDATE ON stock_balances FOR EACH ROW "
        "WHEN NEW.qty_base < 0 OR NEW.total_value_minor < 0 "
        "BEGIN "
        "SELECT RAISE(ABORT, 'رصيد مخزون سالب مرفوض — منع السالب (F-042)'); "
        "END",
    // حركة المخزون لقطة تاريخية لا تعدل ولا تحذف (F-140/05 §7-4)
    "CREATE TRIGGER IF NOT EXISTS trg_stock_moves_frozen_update "
        "BEFORE UPDATE ON stock_moves FOR EACH ROW "
        "BEGIN "
        "SELECT RAISE(ABORT, 'حركة المخزون لقطة لا تعدل (F-140)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_stock_moves_no_delete "
        "BEFORE DELETE ON stock_moves FOR EACH ROW "
        "BEGIN "
        "SELECT RAISE(ABORT, 'حركة المخزون لا تحذف (05 §7-4)'); END",
    // منع سالب الصندوق (05 §7-2/س8) — الرصيد = الافتتاحي + الداخل − الخارج
    "CREATE TRIGGER IF NOT EXISTS trg_cash_no_negative "
        "BEFORE INSERT ON cash_movements FOR EACH ROW "
        "WHEN NEW.kind = 'out' AND ("
        "(SELECT COALESCE(opening_balance_base_minor, 0) FROM cash_boxes "
        " WHERE id = NEW.cash_box_id)"
        " + (SELECT COALESCE(SUM(CASE WHEN kind = 'in' THEN "
        "amount_base_minor ELSE -amount_base_minor END), 0) "
        "FROM cash_movements WHERE cash_box_id = NEW.cash_box_id)"
        " - NEW.amount_base_minor < 0) "
        "BEGIN "
        "SELECT RAISE(ABORT, 'رصيد الصندوق لا يكفي — منع السالب الموحد "
        "(05 §7-2)'); END",
    // حركة الصندوق لقطة لا تحذف (05 §7-4)
    "CREATE TRIGGER IF NOT EXISTS trg_cash_movements_no_delete "
        "BEFORE DELETE ON cash_movements FOR EACH ROW "
        "BEGIN "
        "SELECT RAISE(ABORT, 'حركة الصندوق لا تحذف (05 §7-4)'); END",
    // تجميد الفاتورة المرحّلة — حقولها المالية لا تعدل (05 §4.1/F-052)
    // والحالة تُدار بالمحرك (الجزئية/المدفوعة مشتقة بالسندات دفعة 5)
    "CREATE TRIGGER IF NOT EXISTS trg_invoices_posted_frozen "
        "BEFORE UPDATE ON invoices FOR EACH ROW "
        "WHEN OLD.state IN ('posted', 'paid', 'partially_paid') AND ("
        "NEW.kind IS NOT OLD.kind OR "
        "NEW.number IS NOT OLD.number OR "
        "COALESCE(NEW.party_id,-1) IS NOT COALESCE(OLD.party_id,-1) OR "
        "COALESCE(NEW.cash_box_id,-1) IS NOT COALESCE(OLD.cash_box_id,-1) OR "
        "COALESCE(NEW.warehouse_id,-1) IS NOT COALESCE(OLD.warehouse_id,-1) OR "
        "NEW.invoice_date IS NOT OLD.invoice_date OR "
        "NEW.currency_id IS NOT OLD.currency_id OR "
        "NEW.fx_rate IS NOT OLD.fx_rate OR "
        "NEW.discount_rate IS NOT OLD.discount_rate OR "
        "NEW.subtotal_doc_minor IS NOT OLD.subtotal_doc_minor OR "
        "NEW.discount_doc_minor IS NOT OLD.discount_doc_minor OR "
        "NEW.total_doc_minor IS NOT OLD.total_doc_minor OR "
        "NEW.total_base_minor IS NOT OLD.total_base_minor OR "
        "COALESCE(NEW.move_id,-1) IS NOT COALESCE(OLD.move_id,-1) OR "
        "COALESCE(NEW.original_invoice_id,-1) IS NOT "
        "COALESCE(OLD.original_invoice_id,-1)) "
        "BEGIN "
        "SELECT RAISE(ABORT, 'الفاتورة المرحّلة لا تعدل — التصحيح بمردود "
        "(05 §4.1)'); END",
    // أسطر الفاتورة تجمد بلحظة الترحيل (نمط أسطر القيود F-055)
    "CREATE TRIGGER IF NOT EXISTS trg_invoice_lines_frozen_insert "
        "BEFORE INSERT ON invoice_lines FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = NEW.invoice_id) "
        "<> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الفاتورة المرحّلة لا تضاف'); END",
    // v13 (D-131): الصيغة المحدّثة لحرس تجميد أسطر المرحّل — تجميد
    // الحقول المالية والبنيوية حصراً فيسمح تحديث علم التسليم
    // (delivered) والمورد المسؤول (supplier_party_id) على السطر
    // المرحّل — تحديث جزئي موثق لعلم عمل لا محاسبة بلا فك إقفال،
    // وأي مساس بمال السطر يرفض كما كان.
    "CREATE TRIGGER IF NOT EXISTS trg_invoice_lines_frozen_update "
        "BEFORE UPDATE ON invoice_lines FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = OLD.invoice_id) "
        "<> 'draft' AND ("
        "OLD.invoice_id IS NOT NEW.invoice_id OR "
        "OLD.item_id IS NOT NEW.item_id OR "
        "OLD.unit_id IS NOT NEW.unit_id OR "
        "OLD.factor_at_entry IS NOT NEW.factor_at_entry OR "
        "OLD.qty IS NOT NEW.qty OR "
        "OLD.qty_base IS NOT NEW.qty_base OR "
        "OLD.unit_price_minor IS NOT NEW.unit_price_minor OR "
        "OLD.discount_minor IS NOT NEW.discount_minor OR "
        "OLD.tax_rate IS NOT NEW.tax_rate OR "
        "OLD.line_total_doc_minor IS NOT NEW.line_total_doc_minor OR "
        "OLD.line_total_base_minor IS NOT NEW.line_total_base_minor) "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الفاتورة المرحّلة لا تعدل'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_invoice_lines_frozen_delete "
        "BEFORE DELETE ON invoice_lines FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = OLD.invoice_id) "
        "<> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الفاتورة المرحّلة لا تحذف'); END",
    // الفاتورة المرحّلة لا تحذف — التصحيح بمردود (05 §4.1/§7-4)
    "CREATE TRIGGER IF NOT EXISTS trg_invoices_no_delete_posted "
        "BEFORE DELETE ON invoices FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN "
        "SELECT RAISE(ABORT, 'الفاتورة المرحّلة لا تحذف — التصحيح بمردود'); "
        "END",
  ];
  for (final sql in triggers) {
    await customStatement(sql);
  }
}

/// بذر دفعة الفواتير (س-51): العملتان ببنيتهما (F-120/D-070 — الأساسية
/// SYP والدولار بجانبها لا غير قبل م3)، والمستودع الواحد (05 §3.3)،
/// والصندوق الرئيسي على حساب 1111 (03 §3). كل شطر فاحص الفراغ ذاته
/// فالبذر آمن التكرار.
Future<void> _seedInvoiceBaseline() async {
  final now = DateTime.now().millisecondsSinceEpoch;
  if ((await customSelect('SELECT id FROM currencies').get()).isEmpty) {
    for (final spec in const [
      ('SYP', 'ليرة سورية', 2, 1),
      ('USD', 'دولار أمريكي', 2, 0),
    ]) {
      await customStatement(
        'INSERT INTO currencies (code, name, minor_units, is_base, uuid, '
        'created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
        [spec.$1, spec.$2, spec.$3, spec.$4, const Uuid().v4(), now, now],
      );
    }
  }
  if ((await customSelect('SELECT id FROM warehouses').get()).isEmpty) {
    await customStatement(
      'INSERT INTO warehouses (name, is_active, uuid, created_at, '
      'updated_at, is_deleted) VALUES (?, 1, ?, ?, ?, 0)',
      ['المستودع الرئيسي', const Uuid().v4(), now, now],
    );
  }
  if ((await customSelect('SELECT id FROM cash_boxes').get()).isEmpty) {
    final mainAccount = await customSelect(
      "SELECT id FROM accounts WHERE code = '1111'",
    ).get();
    assert(mainAccount.isNotEmpty, 'حساب الصندوق الرئيسي 1111 من البذر');
    if (mainAccount.isNotEmpty) {
      await customStatement(
        'INSERT INTO cash_boxes (name, currency_id, account_id, '
        'opening_balance_base_minor, uuid, created_at, updated_at, '
        'is_deleted) VALUES (?, 1, ?, 0, ?, ?, ?, 0)',
        [
          'الصندوق الرئيسي',
          mainAccount.first.data['id'] as int,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }
  }
}

Future<Map<String, Object?>?> _itemByIdTx(int id) async {
  final rows = await customSelect(
    'SELECT id, sku, name, kind, base_unit_id, is_active FROM items '
    'WHERE id = ? AND is_deleted = 0',
    variables: [Variable.withInt(id)],
  ).get();
  return rows.isEmpty ? null : rows.first.data;
}

Future<CashBoxRow?> _cashBoxByIdTx(int id) async {
  final rows = await customSelect(
    'SELECT id, name, currency_id, account_id, opening_balance_base_minor '
    'FROM cash_boxes WHERE id = ? AND is_deleted = 0',
    variables: [Variable.withInt(id)],
  ).get();
  if (rows.isEmpty) return null;
  final d = rows.first.data;
  return CashBoxRow(
    id: d['id'] as int,
    name: d['name'] as String,
    currencyId: d['currency_id'] as int,
    accountId: d['account_id'] as int,
    openingBalanceBaseMinor: d['opening_balance_base_minor'] as int,
  );
}

Future<WarehouseRow?> _warehouseByIdTx(int id) async {
  final rows = await customSelect(
    'SELECT id, name, is_active FROM warehouses '
    'WHERE id = ? AND is_deleted = 0',
    variables: [Variable.withInt(id)],
  ).get();
  if (rows.isEmpty) return null;
  final d = rows.first.data;
  return WarehouseRow(
    id: d['id'] as int,
    name: d['name'] as String,
    isActive: (d['is_active'] as int) == 1,
  );
}

/// الحساب بالكود من الدليل المزروع (03 §4: أكواد خريطة العمليات) —
/// الغياب يرمي صريحاً لأن الدليل إعداد والكود المعتمد مرجع الخريطة.
Future<int> _accountIdByCodeTx(String code) async {
  final rows = await customSelect(
    'SELECT id FROM accounts WHERE code = ?',
    variables: [Variable.withString(code)],
  ).get();
  if (rows.isEmpty) {
    throw StateError('حساب الدليل بالكود $code غير موجود — الدليل إعداد '
        'وأكواد خريطة العمليات (03 §4) مرجع المحرك');
  }
  return rows.first.data['id'] as int;
}

Future<int> _journalIdByCodeTx(String code) async {
  final rows = await customSelect(
    'SELECT id FROM journals WHERE code = ?',
    variables: [Variable.withString(code)],
  ).get();
  if (rows.isEmpty) {
    throw StateError('الدفتر بالكود $code غير موجود من البذر (05 §3.4)');
  }
  return rows.first.data['id'] as int;
}

/// رصيد صنف في مستودعه (كمية، قيمة) — مصدر الترصيد القيمة الإجمالية
/// (D-067) والغائب صفر.
Future<(int, int)> _stockBalanceTx(int itemId, int warehouseId) async {
  final rows = await customSelect(
    'SELECT qty_base, total_value_minor FROM stock_balances '
    'WHERE item_id = ? AND warehouse_id = ?',
    variables: [Variable.withInt(itemId), Variable.withInt(warehouseId)],
  ).get();
  if (rows.isEmpty) return (0, 0);
  final d = rows.first.data;
  return (d['qty_base'] as int, d['total_value_minor'] as int);
}

/// رصيد صندوق بالأساسية: الافتتاحي + الداخل − الخارج (05 §5).
Future<int> _cashBoxBalanceTx(int boxId) async {
  final rows = await customSelect(
    "SELECT (SELECT COALESCE(opening_balance_base_minor, 0) FROM cash_boxes "
    "WHERE id = ?1) + "
    "(SELECT COALESCE(SUM(CASE WHEN kind IN ('in', 'transfer_in') THEN amount_base_minor "
    "ELSE -amount_base_minor END), 0) FROM cash_movements "
    "WHERE cash_box_id = ?1) AS balance",
    variables: [Variable.withInt(boxId)],
  ).get();
  return rows.first.data['balance'] as int;
}

/// كمية الأصل لكل صنف (مجموع أسطره — التكرار مشروع فيتجمّع).
Future<Map<int, int>> _origQtyByItemTx(int originalInvoiceId) async {
  final rows = await customSelect(
    'SELECT item_id, SUM(qty_base) AS q FROM invoice_lines '
    'WHERE invoice_id = ? GROUP BY item_id',
    variables: [Variable.withInt(originalInvoiceId)],
  ).get();
  return {for (final r in rows) r.data['item_id'] as int: r.data['q'] as int};
}

/// كمية المردودات المرحّلة للأصل لكل صنف بنوعها (س-05/س-11: المتبقي
/// من الأصل مطروحاً منه مردوداته).
Future<Map<int, int>> _returnedQtyByItemTx(
  int originalInvoiceId,
  String returnKindValue,
) async {
  final rows = await customSelect(
    'SELECT il.item_id AS item_id, SUM(il.qty_base) AS q '
    'FROM invoice_lines il JOIN invoices i ON i.id = il.invoice_id '
    "WHERE i.original_invoice_id = ?1 AND i.kind = ?2 AND i.state <> 'draft' "
    'GROUP BY il.item_id',
    variables: [
      Variable.withInt(originalInvoiceId),
      Variable.withString(returnKindValue),
    ],
  ).get();
  return {for (final r in rows) r.data['item_id'] as int: r.data['q'] as int};
}

/// حركات خروج الأصل لكل صنف (كمية، قيمة) — مصدر لقطة التكلفة لمردود
/// البيع (م-25: «لقطة تكلفة خروج الأصل المخزنة في حركة الخروج»).
Future<(Map<int, int>, Map<int, int>)> _originalOutMovesByItemTx(
  int originalInvoiceId,
) async {
  final rows = await customSelect(
    "SELECT item_id, SUM(-qty_base) AS q, SUM(value_base_minor) AS v "
    "FROM stock_moves WHERE ref_doc_type = 'invoice' AND ref_doc_id = ?1 "
    'AND qty_base < 0 GROUP BY item_id',
    variables: [Variable.withInt(originalInvoiceId)],
  ).get();
  final qty = <int, int>{};
  final value = <int, int>{};
  for (final r in rows) {
    qty[r.data['item_id'] as int] = r.data['q'] as int;
    value[r.data['item_id'] as int] = r.data['v'] as int;
  }
  return (qty, value);
}

/// قيم الاستعادة الممنوحة سلفاً لمردودات أصل بيع (دخول المخزون) لكل
/// صنف — كي يمتص آخر مردود ما تبقى من قيمة الأصل بلا غبار (D-067).
Future<Map<int, int>> _returnedRestoreByItemTx(int originalInvoiceId) async {
  final rows = await customSelect(
    "SELECT sm.item_id AS item_id, SUM(sm.value_base_minor) AS v "
    "FROM stock_moves sm JOIN invoices i ON i.id = sm.ref_doc_id "
    "WHERE sm.ref_doc_type = 'invoice' AND i.original_invoice_id = ?1 "
    "AND i.kind = 'sale_return' AND sm.qty_base > 0 GROUP BY sm.item_id",
    variables: [Variable.withInt(originalInvoiceId)],
  ).get();
  return {for (final r in rows) r.data['item_id'] as int: r.data['v'] as int};
}

Future<InvoiceDocument?> _invoiceRowTx(int id) async {
  final rows = await customSelect(
    'SELECT id, kind, number, party_id, cash_box_id, warehouse_id, '
    'invoice_date, due_date, currency_id, fx_rate, discount_rate, '
    'subtotal_doc_minor, discount_doc_minor, total_doc_minor, '
    'total_base_minor, state, move_id, original_invoice_id, narration '
    'FROM invoices WHERE id = ? AND is_deleted = 0',
    variables: [Variable.withInt(id)],
  ).get();
  if (rows.isEmpty) return null;
  final d = rows.first.data;
  return InvoiceDocument(
    id: d['id'] as int,
    kind: d['kind'] as String,
    number: d['number'] as String,
    partyId: d['party_id'] as int?,
    cashBoxId: d['cash_box_id'] as int?,
    warehouseId: d['warehouse_id'] as int?,
    invoiceDate: d['invoice_date'] as String,
    dueDate: d['due_date'] as String?,
    currencyId: d['currency_id'] as int,
    fxRate: d['fx_rate'] as int,
    discountRate: d['discount_rate'] as int,
    subtotalDocMinor: d['subtotal_doc_minor'] as int,
    discountDocMinor: d['discount_doc_minor'] as int,
    totalDocMinor: d['total_doc_minor'] as int,
    totalBaseMinor: d['total_base_minor'] as int,
    state: d['state'] as String,
    moveId: d['move_id'] as int?,
    originalInvoiceId: d['original_invoice_id'] as int?,
    narration: d['narration'] as String?,
  );
}

Future<List<InvoiceLineDocument>> _invoiceLinesTx(int invoiceId) async {
  final rows = await customSelect(
    'SELECT id, invoice_id, item_id, unit_id, factor_at_entry, qty, '
    'qty_base, unit_price_minor, discount_minor, tax_rate, '
    'line_total_doc_minor, line_total_base_minor, uuid, delivered, '
    'supplier_party_id '
    'FROM invoice_lines WHERE invoice_id = ? ORDER BY id',
    variables: [Variable.withInt(invoiceId)],
  ).get();
  return [
    for (final r in rows)
      InvoiceLineDocument(
        id: r.data['id'] as int,
        invoiceId: r.data['invoice_id'] as int,
        itemId: r.data['item_id'] as int,
        unitId: r.data['unit_id'] as int,
        factorAtEntry: r.data['factor_at_entry'] as int,
        qty: r.data['qty'] as int,
        qtyBase: r.data['qty_base'] as int,
        unitPriceMinor: r.data['unit_price_minor'] as int,
        discountMinor: r.data['discount_minor'] as int,
        taxRate: r.data['tax_rate'] as int,
        lineTotalDocMinor: r.data['line_total_doc_minor'] as int,
        lineTotalBaseMinor: r.data['line_total_base_minor'] as int,
        uuid: r.data['uuid'] as String,
        delivered: (r.data['delivered'] as int? ?? 0) == 1,
        supplierPartyId: r.data['supplier_party_id'] as int?,
      ),
  ];
}

/// لقطة الفاتورة الكاملة JSON للسجل (07 §2.3/D-067) — تُكتب لحظة الحدث.
Future<String> _invoiceSnapshotTx(int invoiceId) async {
  final inv = (await _invoiceRowTx(invoiceId))!;
  final lines = await _invoiceLinesTx(invoiceId);
  return jsonEncode(<String, Object?>{
    'id': inv.id,
    'kind': inv.kind,
    'number': inv.number,
    'party_id': inv.partyId,
    'cash_box_id': inv.cashBoxId,
    'warehouse_id': inv.warehouseId,
    'date': inv.invoiceDate,
    'due_date': inv.dueDate,
    'currency_id': inv.currencyId,
    'fx_rate': inv.fxRate,
    'discount_rate': inv.discountRate,
    'total_doc_minor': inv.totalDocMinor,
    'total_base_minor': inv.totalBaseMinor,
    'state': inv.state,
    'move_id': inv.moveId,
    'original_invoice_id': inv.originalInvoiceId,
    'lines': [
      for (final l in lines)
        <String, Object?>{
          'item_id': l.itemId,
          'unit_id': l.unitId,
          'qty_base': l.qtyBase,
          'unit_price_minor': l.unitPriceMinor,
          'discount_minor': l.discountMinor,
          'line_total_doc_minor': l.lineTotalDocMinor,
          'line_total_base_minor': l.lineTotalBaseMinor,
          'uuid': l.uuid,
        }
    ],
  });
}

Future<void> _recordInvoiceEventTx({
  required int invoiceId,
  required String action,
  String? payload,
}) async {
  await into(events).insert(
    EventsCompanion.insert(
      eventAt: DateTime.now().millisecondsSinceEpoch,
      deviceId: await deviceId(),
      entityType: 'invoice',
      entityId: Value(invoiceId),
      action: action,
      payload: payload ?? await _invoiceSnapshotTx(invoiceId),
      uuid: const Uuid().v4(),
    ),
  );
}

/// إعادة بناء مسودة الفاتورة من صفوفها — التحقق على ما خُزّن لا على ما
/// قيل (07 §1.1: لا ثقة بالمدخلات بعد كتابتها).
InvoiceDraft _draftFromRows(InvoiceDocument inv, List<InvoiceLineDocument> lines) {
  return InvoiceDraft(
    kind: InvoiceKind.fromStorage(inv.kind),
    dateText: inv.invoiceDate,
    dueDateText: inv.dueDate,
    partyId: inv.partyId,
    cashBoxId: inv.cashBoxId,
    warehouseId: inv.warehouseId,
    currencyId: inv.currencyId,
    fxRate: inv.fxRate,
    discountRate: inv.discountRate,
    originalInvoiceId: inv.originalInvoiceId,
    narration: inv.narration,
    lines: [
      for (final l in lines)
        InvoiceLineDraft(
          itemId: l.itemId,
          unitId: l.unitId,
          qtyBase: l.qtyBase,
          unitPriceMinor: l.unitPriceMinor,
          discountMinor: l.discountMinor,
          taxRate: l.taxRate,
        ),
    ],
  );
}

/// تخطيط الأسطر المخزنية لكل أنواع الفواتير — بضاعة حصراً (الخدمة بلا
/// مخزون ولا تكلفة — س-08): دخول الشراء صافي السطر، خروج البيع ومردود
/// الشراء بالمتوسط الجاري المتسلسل (D-067)، ودخول مردود البيع بلقطة
/// كلفة الأصل ويمتص آخر مردود ما تبقى من قيمتها (م-25/D-067). أخطاء
/// الاكتفاء تضاف إلى [errors] (منع السالب — F-042).
Future<List<_StockLinePlan>> _planStockLines(
  InvoiceDraft draft,
  List<InvoiceLineResult> results,
  List<InvoiceValidationError> errors,
) async {
  final plans = <_StockLinePlan>[];
  if (draft.warehouseId == null) return plans;
  final sim = _StockSim(_stockBalanceTx, draft.warehouseId!);
  final origMoveQty = <int, int>{};
  final origMoveVal = <int, int>{};
  final returnedQty = <int, int>{};
  final restoredVal = <int, int>{};
  if (draft.kind.isReturn && draft.originalInvoiceId != null) {
    returnedQty.addAll(await _returnedQtyByItemTx(
        draft.originalInvoiceId!, draft.kind.storageValue));
    if (draft.kind == InvoiceKind.saleReturn) {
      final (qty, value) =
          await _originalOutMovesByItemTx(draft.originalInvoiceId!);
      origMoveQty.addAll(qty);
      origMoveVal.addAll(value);
      restoredVal.addAll(await _returnedRestoreByItemTx(draft.originalInvoiceId!));
    }
  }
  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    final item = await _itemByIdTx(line.itemId);
    if (item == null || (item['kind'] as String) != 'good') continue;
    final label =
        itemDisplayLabel(item['name'] as String, item['sku'] as String);
    if (draft.kind == InvoiceKind.purchase) {
      // الدخول بقيمة السطر الصافية (بعد خصمه — «لا يمس كلفة المخزون»
      // معناه الخصم يخفض الكلفة لا يفصل حساباً — 05 §4.1)
      plans.add(_StockLinePlan(
        lineIndex: i,
        itemId: line.itemId,
        qtyBase: line.qtyBase,
        stockValueMinor: results[i].baseMinor,
        counterpartMinor: results[i].baseMinor,
      ));
      continue;
    }
    if (draft.kind == InvoiceKind.sale ||
        draft.kind == InvoiceKind.purchaseReturn) {
      // الخروج بالقيمة الدفترية الجارية — متسلسل بالترتيب (D-067)
      final (qty, value) = await sim.of(line.itemId);
      if (line.qtyBase > qty) {
        errors.add(InvoiceStockInsufficient(i, label, qty));
        continue;
      }
      final exit = wacExitValue(value, qty, line.qtyBase);
      sim.apply(line.itemId, -line.qtyBase, -exit);
      plans.add(_StockLinePlan(
        lineIndex: i,
        itemId: line.itemId,
        qtyBase: line.qtyBase,
        stockValueMinor: exit,
        counterpartMinor:
            draft.kind == InvoiceKind.sale ? exit : results[i].baseMinor,
      ));
      continue;
    }
    // مردود البيع: دخول بلقطة كلفة الأصل (م-25) والنظير بالمتوسط الجاري
    // والفرق على 58 — وعلى مخزون فارغ النظير صفر فالفرق كله على 58 (س-56)
    final (qty, value) = await sim.of(line.itemId);
    final wac = wacExitValue(value, qty, line.qtyBase);
    final qOrig = origMoveQty[line.itemId] ?? 0;
    final vOrig = origMoveVal[line.itemId] ?? 0;
    final returned = returnedQty[line.itemId] ?? 0;
    final remaining = qOrig - returned;
    final remainingValue = vOrig - (restoredVal[line.itemId] ?? 0);
    final restore = line.qtyBase >= remaining
        ? remainingValue
        : (qOrig <= 0
            ? 0
            : roundHalfAwayFromZeroRatio(vOrig * line.qtyBase, qOrig));
    sim.apply(line.itemId, line.qtyBase, restore);
    plans.add(_StockLinePlan(
      lineIndex: i,
      itemId: line.itemId,
      qtyBase: line.qtyBase,
      stockValueMinor: restore,
      counterpartMinor: wac,
    ));
  }
  return plans;
}

/// جمع أخطاء الفاتورة بمعطيات القاعدة — التسلسل التدريجي المعتمد:
/// البنية ثم الزمن (عند الترحيل) ثم الأسطر (الوجود والتفعيل والوحدة
/// والنوع) ثم المستودع ثم جهة الدفع ثم الأصل والمتبقي للمردود ثم
/// الاكتفاء (المخزون والصندوق). «رسالة واحدة أول خطأ» عرضاً (نمط س-36)
/// والقائمة كاملة للفحص.
Future<List<InvoiceValidationError>> _collectInvoiceErrors(
  InvoiceDraft draft, {
  required bool forPosting,
}) async {
  final errors = validateInvoiceDraftStructure(draft);
  if (errors.isNotEmpty) return errors;

  if (forPosting) {
    final period = findPeriodForDate(await ledgerPeriods(), draft.dateText);
    if (period == null) {
      errors.add(InvoiceNoPeriod(draft.dateText));
    } else if (!period.isOpen) {
      errors.add(InvoiceClosedPeriod(draft.dateText));
    }
  }

  final itemByLine = <Map<String, Object?>?>[];
  var hasGoods = false;
  for (final line in draft.lines) {
    final item = await _itemByIdTx(line.itemId);
    itemByLine.add(item);
    if (item != null && (item['kind'] as String) == 'good') hasGoods = true;
  }
  for (var i = 0; i < draft.lines.length; i++) {
    final item = itemByLine[i];
    final line = draft.lines[i];
    if (item == null) {
      errors.add(InvoiceItemNotFound(i, line.itemId));
      continue;
    }
    final label =
        itemDisplayLabel(item['name'] as String, item['sku'] as String);
    if ((item['is_active'] as int) == 0) {
      errors.add(InvoiceItemInactive(i, label));
    }
    if (line.unitId != (item['base_unit_id'] as int)) {
      errors.add(InvoiceUnitMismatch(i, label));
    }
    final kind = item['kind'] as String;
    if (kind == 'bundle') {
      errors.add(InvoiceBundleUnsupported(i, label));
    }
    if (draft.kind == InvoiceKind.purchase && kind == 'service') {
      errors.add(InvoiceServiceInPurchase(i, label));
    }
  }

  if (hasGoods) {
    final warehouse = draft.warehouseId == null
        ? null
        : await _warehouseByIdTx(draft.warehouseId!);
    if (warehouse == null || !warehouse.isActive) {
      errors.add(InvoiceWarehouseMissing(draft.warehouseId));
    }
  }

  if (draft.isCash) {
    final box = await _cashBoxByIdTx(draft.cashBoxId!);
    if (box == null) {
      errors.add(InvoiceBoxMissing(draft.cashBoxId!));
    } else if (box.currencyId != draft.currencyId) {
      errors.add(InvoiceBoxCurrencyMismatch(
          box.name, box.currencyId, draft.currencyId));
    }
  } else if (draft.partyId != null) {
    final party = await (select(parties)
          ..where((t) => t.id.equals(draft.partyId!)))
        .getSingleOrNull();
    if (party == null) {
      errors.add(InvoicePartyMissing(draft.partyId!));
    }
  }

  if (draft.kind.isReturn && draft.originalInvoiceId != null) {
    final original = await _invoiceRowTx(draft.originalInvoiceId!);
    if (original == null) {
      errors.add(InvoiceOriginalNotFound(draft.originalInvoiceId!));
    } else {
      if (!original.isCommitted) {
        errors.add(InvoiceOriginalNotPosted(original.id, original.state));
      }
      final expected = draft.kind == InvoiceKind.saleReturn
          ? InvoiceKind.sale
          : InvoiceKind.purchase;
      if (InvoiceKind.fromStorage(original.kind) != expected) {
        errors.add(InvoiceOriginalKindMismatch(original.id, expected.label));
      }
      final origQty = await _origQtyByItemTx(original.id);
      final returnedQty = await _returnedQtyByItemTx(
          original.id, draft.kind.storageValue);
      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        final item = itemByLine[i];
        final label = item == null
            ? 'معرف ${line.itemId}'
            : itemDisplayLabel(item['name'] as String, item['sku'] as String);
        final remaining =
            (origQty[line.itemId] ?? 0) - (returnedQty[line.itemId] ?? 0);
        if (line.qtyBase > remaining) {
          errors.add(
              InvoiceReturnQtyExceedsRemaining(i, label, remaining));
        }
      }
    }
  }

  if (errors.isNotEmpty) return errors;

  // الاكتفاء: خروج المخزون (بيع/مردود شراء) يفحص بالتخطيط نفسه
  final totals = computeInvoiceTotals(draft);
  await _planStockLines(draft, totals.lines, errors);
  if (errors.isNotEmpty) return errors;

  // منع سالب الصندوق للأرجل الخارجة (شراء نقدي ورد مردود بيع — 05 §7-2)
  if (draft.isCash &&
      (draft.kind == InvoiceKind.purchase ||
          draft.kind == InvoiceKind.saleReturn)) {
    final box = await _cashBoxByIdTx(draft.cashBoxId!);
    if (box != null) {
      final balance = await _cashBoxBalanceTx(box.id);
      if (balance < totals.totalBaseMinor) {
        errors.add(InvoiceBoxInsufficient(box.name, balance));
      }
    }
  }
  return errors;
}

/// س-51..س-59: إنشاء فاتورة مسودة — المدقق حرس التخزين الثاني بعد مدقق
/// الواجهة: لا مسار يكتب مستنداً غير مدقق. المسودة والأسطر وحدثها
/// («created» بلقطتها) معاملة واحدة (07 §2.4) — والمسودة بلا رقم:
/// الترقيم لحظة الترحيل حصراً (07 §1.9).
Future<int> createInvoiceDraft(InvoiceDraft draft) async {
  final structureErrors = validateInvoiceDraftStructure(draft);
  if (structureErrors.isNotEmpty) {
    throw InvoiceValidationException(structureErrors);
  }
  return transaction(() async {
    final errors = await _collectInvoiceErrors(draft, forPosting: false);
    if (errors.isNotEmpty) {
      throw InvoiceValidationException(errors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final totals = computeInvoiceTotals(draft);
    await customStatement(
      'INSERT INTO invoices (kind, number, party_id, cash_box_id, '
      'warehouse_id, invoice_date, due_date, currency_id, fx_rate, '
      'discount_rate, subtotal_doc_minor, discount_doc_minor, '
      'total_doc_minor, total_base_minor, state, move_id, '
      'original_invoice_id, narration, uuid, created_at, updated_at, '
      "is_deleted) VALUES (?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
      "'draft', NULL, ?, ?, ?, ?, ?, 0)",
      [
        draft.kind.storageValue,
        draft.partyId,
        draft.cashBoxId,
        draft.warehouseId,
        draft.dateText,
        draft.dueDateText,
        draft.currencyId,
        draft.fxRate,
        draft.discountRate,
        totals.subtotalDocMinor,
        totals.discountDocMinor,
        totals.totalDocMinor,
        totals.totalBaseMinor,
        draft.originalInvoiceId,
        draft.narration,
        const Uuid().v4(),
        now,
        now,
      ],
    );
    final invoiceId = (await customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle()).data['id'] as int;
    for (final r in totals.lines) {
      await customStatement(
        'INSERT INTO invoice_lines (invoice_id, item_id, unit_id, '
        'factor_at_entry, qty, qty_base, unit_price_minor, discount_minor, '
        'tax_rate, line_total_doc_minor, line_total_base_minor, uuid, '
        'created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          invoiceId,
          r.line.itemId,
          r.line.unitId,
          r.line.qtyBase,
          r.line.qtyBase,
          r.line.unitPriceMinor,
          r.line.discountMinor,
          r.line.taxRate,
          r.netDocMinor,
          r.baseMinor,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }
    await _recordInvoiceEventTx(invoiceId: invoiceId, action: 'created');
    return invoiceId;
  });
}

/// س-51..س-59: ترحيل الفاتورة — المحرك الحاكم كاملاً في معاملة واحدة:
/// التحقق (بنية + زمن + مرجعية + اكتفاء) ثم رقم الفاتورة من تسلسل نوعها
/// (D-080 معروض) ثم حركات المخزون بلقطاتها ثم القيد المتوازن من دفتر
/// جهته بترقيمه المركزي ثم أرصدة المخزون وحركة الصندوق ثم حالة الفاتورة
/// ورقمها ثم حدث «posted» بلقطته — وأي رفض يتراجع كل شيء (07 §2.4).
///
/// خريطة الترحيل (05 §6/03 §4 حرفاً):
/// - شراء: 113 مدين بكل سطر (مرتبط بحركته) / الصندوق أو 211 دائن.
/// - بيع: الصندوق أو 112 مدين / 411 (بضاعة) و412 (خدمة) دائن + 51/113
///   بالتكلفة المتسلسلة لكل سطر بضاعة.
/// - مردود بيع: 42 مدين / الصندوق أو 112 دائن + 113 بلقطة الأصل / 51
///   بالمتوسط الجاري والفرق على 58 (م-25).
/// - مردود شراء: الصندوق أو 211 مدين / 113 بالقيمة الدفترية والفرق على
///   58 (س-05/D-067).
Future<int> postInvoice(int invoiceId) async {
  return transaction(() async {
    final inv = await _invoiceRowTx(invoiceId);
    if (inv == null) {
      throw StateError('لا فاتورة بالمعرف $invoiceId');
    }
    if (inv.state != 'draft') {
      throw InvoiceValidationException([InvoiceStateNotDraft(inv.state)]);
    }
    final lineRows = await _invoiceLinesTx(invoiceId);
    final draft = _draftFromRows(inv, lineRows);
    final errors = await _collectInvoiceErrors(draft, forPosting: true);
    if (errors.isNotEmpty) {
      throw InvoiceValidationException(errors);
    }
    final totals = computeInvoiceTotals(draft);
    final now = DateTime.now().millisecondsSinceEpoch;
    final year = yearOfIsoDate(draft.dateText);

    final invoiceNumber = formatDocumentNumber(year,
        await _advanceSequenceWithinTx(invoiceSequenceKind(draft.kind), year));

    final journalCode = draft.kind.isSalesSide ? 'sales' : 'purchase';
    final journalId = await _journalIdByCodeTx(journalCode);
    final moveSeqKind = moveSequenceKindForJournal(journalCode);

    final acc113 = await _accountIdByCodeTx('113');
    final acc112 = await _accountIdByCodeTx('112');
    final acc211 = await _accountIdByCodeTx('211');
    final acc411 = await _accountIdByCodeTx('411');
    final acc412 = await _accountIdByCodeTx('412');
    final acc42 = await _accountIdByCodeTx('42');
    final acc51 = await _accountIdByCodeTx('51');
    final acc58 = await _accountIdByCodeTx('58');
    final box =
        draft.isCash ? (await _cashBoxByIdTx(draft.cashBoxId!))! : null;

    final planErrors = <InvoiceValidationError>[];
    final plan = await _planStockLines(draft, totals.lines, planErrors);
    if (planErrors.isNotEmpty) {
      throw InvoiceValidationException(planErrors);
    }
    final goodsLineIndexes = <int>{for (final p in plan) p.lineIndex};

    // فرق 58 المجمّع: مردود البيع (الاستعادة − المتوسط الجاري) ومردود
    // الشراء (الائتمان − القيمة الدفترية) — الموجب يُدائن به والعكس
    // مدين به (03 §3: «العكس دائن به»).
    var diffMinor = 0;
    if (draft.kind == InvoiceKind.saleReturn) {
      for (final p in plan) {
        diffMinor += p.stockValueMinor - p.counterpartMinor;
      }
    } else if (draft.kind == InvoiceKind.purchaseReturn) {
      for (final p in plan) {
        diffMinor += totals.lines[p.lineIndex].baseMinor - p.stockValueMinor;
      }
    }

    // حركات المخزون أولاً (داخل المعاملة) لأخذ معرفاتها لربط أسطر 113
    final stockMoveIds = <int>[];
    final stockIn =
        draft.kind == InvoiceKind.purchase || draft.kind == InvoiceKind.saleReturn;
    for (final p in plan) {
      await customStatement(
        "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
        "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
        "ref_doc_type, ref_doc_id, uuid, created_at, updated_at, is_deleted) "
        "VALUES (?, ?, ?, ?, ?, ?, 'posted', 'invoice', ?, ?, ?, ?, 0)",
        [
          p.itemId,
          stockIn ? p.qtyBase : -p.qtyBase,
          stockIn ? null : draft.warehouseId,
          stockIn ? draft.warehouseId : null,
          p.stockValueMinor,
          roundHalfAwayFromZeroRatio(p.stockValueMinor, p.qtyBase),
          invoiceId,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      stockMoveIds.add((await customSelect(
        'SELECT last_insert_rowid() AS id',
      ).getSingle()).data['id'] as int);
    }

    // أسطر القيد — لقطة العملة على أرجل المستند (F-122/D-082) وأرجل
    // التكلفة بالأساسية الخالصة
    final docCur = draft.currencyId;
    final fx = draft.fxRate;
    final moveLines = <MoveLineDraft>[];
    if (draft.kind == InvoiceKind.purchase) {
      for (var k = 0; k < plan.length; k++) {
        final p = plan[k];
        moveLines.add(MoveLineDraft(
          accountId: acc113,
          debitMinor: p.stockValueMinor,
          currencyId: docCur,
          amountMinor: totals.lines[p.lineIndex].netDocMinor,
          fxRate: fx,
          refStockMoveId: stockMoveIds[k],
        ));
      }
      moveLines.add(MoveLineDraft(
        accountId: box != null ? box.accountId : acc211,
        creditMinor: totals.totalBaseMinor,
        partyId: box != null ? null : draft.partyId,
        currencyId: docCur,
        amountMinor: totals.totalDocMinor,
        fxRate: fx,
      ));
    } else if (draft.kind == InvoiceKind.sale) {
      moveLines.add(MoveLineDraft(
        accountId: box != null ? box.accountId : acc112,
        debitMinor: totals.totalBaseMinor,
        partyId: box != null ? null : draft.partyId,
        currencyId: docCur,
        amountMinor: totals.totalDocMinor,
        fxRate: fx,
      ));
      var goodsDoc = 0, goodsBase = 0, servDoc = 0, servBase = 0;
      for (var i = 0; i < totals.lines.length; i++) {
        final r = totals.lines[i];
        if (goodsLineIndexes.contains(i)) {
          goodsDoc += r.netDocMinor;
          goodsBase += r.baseMinor;
        } else {
          servDoc += r.netDocMinor;
          servBase += r.baseMinor;
        }
      }
      if (goodsBase > 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc411,
          creditMinor: goodsBase,
          currencyId: docCur,
          amountMinor: goodsDoc,
          fxRate: fx,
        ));
      }
      if (servBase > 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc412,
          creditMinor: servBase,
          currencyId: docCur,
          amountMinor: servDoc,
          fxRate: fx,
        ));
      }
      for (var k = 0; k < plan.length; k++) {
        final p = plan[k];
        if (p.counterpartMinor > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc51,
            debitMinor: p.counterpartMinor,
            currencyId: 1,
            amountMinor: p.counterpartMinor,
          ));
        }
        if (p.stockValueMinor > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc113,
            creditMinor: p.stockValueMinor,
            currencyId: 1,
            amountMinor: p.stockValueMinor,
            refStockMoveId: stockMoveIds[k],
          ));
        }
      }
    } else if (draft.kind == InvoiceKind.saleReturn) {
      moveLines.add(MoveLineDraft(
        accountId: acc42,
        debitMinor: totals.totalBaseMinor,
        currencyId: docCur,
        amountMinor: totals.totalDocMinor,
        fxRate: fx,
      ));
      moveLines.add(MoveLineDraft(
        accountId: box != null ? box.accountId : acc112,
        creditMinor: totals.totalBaseMinor,
        partyId: box != null ? null : draft.partyId,
        currencyId: docCur,
        amountMinor: totals.totalDocMinor,
        fxRate: fx,
      ));
      for (var k = 0; k < plan.length; k++) {
        final p = plan[k];
        if (p.stockValueMinor > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc113,
            debitMinor: p.stockValueMinor,
            currencyId: 1,
            amountMinor: p.stockValueMinor,
            refStockMoveId: stockMoveIds[k],
          ));
        }
        if (p.counterpartMinor > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc51,
            creditMinor: p.counterpartMinor,
            currencyId: 1,
            amountMinor: p.counterpartMinor,
          ));
        }
      }
      if (diffMinor > 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc58,
          creditMinor: diffMinor,
          currencyId: 1,
          amountMinor: diffMinor,
        ));
      } else if (diffMinor < 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc58,
          debitMinor: -diffMinor,
          currencyId: 1,
          amountMinor: -diffMinor,
        ));
      }
    } else {
      // مردود الشراء
      moveLines.add(MoveLineDraft(
        accountId: box != null ? box.accountId : acc211,
        debitMinor: totals.totalBaseMinor,
        partyId: box != null ? null : draft.partyId,
        currencyId: docCur,
        amountMinor: totals.totalDocMinor,
        fxRate: fx,
      ));
      for (var k = 0; k < plan.length; k++) {
        final p = plan[k];
        if (p.stockValueMinor > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc113,
            creditMinor: p.stockValueMinor,
            currencyId: 1,
            amountMinor: p.stockValueMinor,
            refStockMoveId: stockMoveIds[k],
          ));
        }
      }
      if (diffMinor > 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc58,
          creditMinor: diffMinor,
          currencyId: 1,
          amountMinor: diffMinor,
        ));
      } else if (diffMinor < 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc58,
          debitMinor: -diffMinor,
          currencyId: 1,
          amountMinor: -diffMinor,
        ));
      }
    }

    final moveId = await _insertMoveDraftWithinTx(MoveDraft(
      journalId: journalId,
      dateText: draft.dateText,
      narration: draft.narration ?? draft.kind.label,
      refDocType: 'invoice',
      refDocId: invoiceId,
      lines: moveLines,
    ));
    await _postMoveWithinTx(moveId, sequenceKind: moveSeqKind);

    // أرصدة المخزون — دلتا كل سطر على حدة بالترتيب فالحاجز يفحص كل خطوة
    for (final p in plan) {
      await customStatement(
        'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
        'total_value_minor, uuid, created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
        'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
        'qty_base = qty_base + excluded.qty_base, '
        'total_value_minor = total_value_minor + excluded.total_value_minor, '
        'updated_at = excluded.updated_at',
        [
          p.itemId,
          draft.warehouseId!,
          stockIn ? p.qtyBase : -p.qtyBase,
          stockIn ? p.stockValueMinor : -p.stockValueMinor,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }

    // حركة الصندوق للنقدي بمصدرها (05 §4.2): البيع ومردود الشراء داخل
    // والشراء ومردود البيع خارج
    if (box != null) {
      final cashIn = draft.kind == InvoiceKind.sale ||
          draft.kind == InvoiceKind.purchaseReturn;
      await customStatement(
        "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
        "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, user_id, "
        "uuid, created_at, updated_at, is_deleted) "
        "VALUES (?, ?, ?, ?, ?, 'invoice', ?, NULL, ?, ?, ?, 0)",
        [
          box.id,
          cashIn ? 'in' : 'out',
          totals.totalDocMinor,
          totals.totalBaseMinor,
          draft.fxRate,
          invoiceId,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }

    // أسطر الفاتورة بمجاميعها النهائية — قبل تغيير الحالة كي لا يجمد
    // المُشغِّل تحديثها (نمط الحواجز: الترتيب جزء من الصحة)
    for (var i = 0; i < totals.lines.length; i++) {
      await customStatement(
        'UPDATE invoice_lines SET line_total_doc_minor = ?, '
        'line_total_base_minor = ?, updated_at = ? WHERE id = ?',
        [
          totals.lines[i].netDocMinor,
          totals.lines[i].baseMinor,
          now,
          lineRows[i].id,
        ],
      );
    }

    // حالة الفاتورة ورقمها وقيدُها — النقدية «مدفوعة» فوراً (س-03/س-06)
    // والمردودات والآجل «مرحّلة»
    final newState = draft.isCash && !draft.kind.isReturn ? 'paid' : 'posted';
    await customStatement(
      'UPDATE invoices SET state = ?, number = ?, move_id = ?, '
      'subtotal_doc_minor = ?, discount_doc_minor = ?, total_doc_minor = ?, '
      'total_base_minor = ?, updated_at = ? WHERE id = ?',
      [
        newState,
        invoiceNumber,
        moveId,
        totals.subtotalDocMinor,
        totals.discountDocMinor,
        totals.totalDocMinor,
        totals.totalBaseMinor,
        now,
        invoiceId,
      ],
    );
    await _recordInvoiceEventTx(invoiceId: invoiceId, action: 'posted');
    return invoiceId;
  });
}

/// س-59: حذف مسودة فاتورة — المسودة حصراً وباللقطة الكاملة في سجل
/// الأحداث (السجل يوثق حتى إلغاء المسودات — نمط القيود المعتمد)،
/// والمرحّلة مستحيلة الحذف حرساً هنا ومشغلاً في القاعدة.
Future<void> deleteInvoiceDraft(int invoiceId) async {
  return transaction(() async {
    final inv = await _invoiceRowTx(invoiceId);
    if (inv == null) return;
    if (inv.state != 'draft') {
      throw InvoiceValidationException([InvoiceStateNotDraft(inv.state)]);
    }
    final snapshot = await _invoiceSnapshotTx(invoiceId);
    await customStatement(
      'DELETE FROM invoice_lines WHERE invoice_id = ?',
      [invoiceId],
    );
    await customStatement('DELETE FROM invoices WHERE id = ?', [invoiceId]);
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: DateTime.now().millisecondsSinceEpoch,
        deviceId: await deviceId(),
        entityType: 'invoice',
        entityId: Value(invoiceId),
        action: 'draft_deleted',
        payload: snapshot,
        uuid: const Uuid().v4(),
      ),
    );
  });
}

// ─── قراءات الفواتير العامة — التخزين يقرأ ولا يحسب (نمط القلب) ───

Future<InvoiceDocument?> invoiceById(int id) => _invoiceRowTx(id);

Future<List<InvoiceLineDocument>> invoiceLines(int invoiceId) =>
    _invoiceLinesTx(invoiceId);

// ─── دفعة (12) متابعة التسليم (س-137..س-142/D-131..D-134) ───
// علم عمل لا محاسبة: تحديثان جزئيان موثقان على السطر المرحّلة (الحرس
// المحدَّث يسمح بهذين العمودين حصراً بلا فك إقفال)، وقارئة واحدة
// لسطور البيع غير المستلمة — لا جداول جديدة ولا قيود ولا مخزون.

/// س-137/D-131: تحديد/إزالة تحديد مربع «مستلم» على سطر — يحفظ فوراً
/// بقاعدة البيانات على المرحّلة كما على المسودة، والسطر الغائب
/// برسالته (لا صمت على معرف فاسد).
Future<void> setInvoiceLineDelivered(
  int lineId, {
  required bool delivered,
}) async {
  final existing = await customSelect(
    'SELECT id FROM invoice_lines WHERE id = ?',
    variables: [Variable.withInt(lineId)],
  ).get();
  if (existing.isEmpty) {
    throw StateError('لا سطر فاتورة بالمعرف $lineId');
  }
  await customStatement(
    'UPDATE invoice_lines SET delivered = ?, updated_at = ? WHERE id = ?',
    [delivered ? 1 : 0, DateTime.now().millisecondsSinceEpoch, lineId],
  );
}

/// س-138/D-132: تعيين المورد المسؤول على السطر — اختيار المالك يُخزَّن
/// كما هو (ولا تخمين لحظة العرض)، والسطر الغائب برسالته.
Future<void> setInvoiceLineSupplier(
  int lineId, {
  required int? supplierPartyId,
}) async {
  final existing = await customSelect(
    'SELECT id FROM invoice_lines WHERE id = ?',
    variables: [Variable.withInt(lineId)],
  ).get();
  if (existing.isEmpty) {
    throw StateError('لا سطر فاتورة بالمعرف $lineId');
  }
  await customStatement(
    'UPDATE invoice_lines SET supplier_party_id = ?, updated_at = ? '
    'WHERE id = ?',
    [supplierPartyId, DateTime.now().millisecondsSinceEpoch, lineId],
  );
}

/// س-138/D-132: اقتراح المورد — آخر فاتورة شراء مرحّلة فيها الصنف
/// فطرفها هو المقترح، وبلا شراء سابق null (فيُدخل يدوياً بلفظ
/// اختيار المالك «٢. أ»).
Future<int?> latestSupplierPartyIdForItem(int itemId) async {
  final rows = await customSelect(
    'SELECT inv.party_id AS party_id '
    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    "WHERE il.item_id = ?1 AND inv.kind = 'purchase' "
    "AND inv.state <> 'draft' AND inv.is_deleted = 0 "
    'AND il.is_deleted = 0 AND inv.party_id IS NOT NULL '
    'ORDER BY inv.invoice_date DESC, inv.id DESC LIMIT 1',
    variables: [Variable.withInt(itemId)],
  ).get();
  if (rows.isEmpty) return null;
  return rows.first.data['party_id'] as int?;
}

/// س-139/D-133: قارئة سطور البيع غير المستلمة — من المرحّل حصراً
/// (المسودة ليست بيعاً واقعياً بعد)، والمردودات ليست تسليم زبون فلا
/// تدخل، والأقدم أولاً بلفظ البوابة، والقراءة خالصة بلا جداول جديدة
/// (D-089 روحاً).
Future<List<UndeliveredLineRow>> undeliveredSaleLinesReport() async {
  final rows = await customSelect(
    'SELECT il.id AS line_id, inv.id AS invoice_id, inv.kind AS kind, '
    'inv.number AS number, inv.invoice_date AS invoice_date, '
    'il.item_id AS item_id, i.sku AS sku, i.name AS item_name, '
    'il.qty_base AS qty_base, p.name AS party_name, '
    'il.supplier_party_id AS supplier_party_id, sp.name AS supplier_name '
    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'JOIN items i ON i.id = il.item_id '
    'LEFT JOIN parties p ON p.id = inv.party_id '
    'LEFT JOIN parties sp ON sp.id = il.supplier_party_id '
    "WHERE inv.kind = 'sale' AND inv.state <> 'draft' "
    'AND inv.is_deleted = 0 AND il.is_deleted = 0 '
    'AND il.delivered = 0 '
    'ORDER BY inv.invoice_date ASC, il.id ASC',
  ).get();
  return [
    for (final r in rows)
      UndeliveredLineRow(
        lineId: r.data['line_id'] as int,
        invoiceId: r.data['invoice_id'] as int,
        invoiceKind: r.data['kind'] as String,
        invoiceNumber: r.data['number'] as String,
        invoiceDate: r.data['invoice_date'] as String,
        itemId: r.data['item_id'] as int,
        itemSku: r.data['sku'] as String,
        itemName: r.data['item_name'] as String,
        qtyBase: r.data['qty_base'] as int,
        partyName: r.data['party_name'] as String?,
        supplierPartyId: r.data['supplier_party_id'] as int?,
        supplierName: r.data['supplier_name'] as String?,
      ),
  ];
}

/// رصيد صنف في مستودعه (كمية، قيمة إجمالية — D-067) للقراءة والفحص.
Future<(int, int)> stockBalanceOf({
  required int itemId,
  required int warehouseId,
}) =>
    _stockBalanceTx(itemId, warehouseId);

/// كميات الأصناف المتاحة في مستودع واحد — خريطة (صنف ← كمية) للقراءة
/// الخالصة من stock_balances حصراً (D-106، دفعة 8 س39): عرض المتاح في
/// قائمة اختيار الأصناف بالفاتورة (س-108) — قراءة لا جداول تجميع ولا
/// أرقام مخزنة، والمستودع غير الموجود بالخريطة متاحه صفر.
Future<Map<int, int>> stockQuantitiesByItem({required int warehouseId}) async {
  final rows = await customSelect(
    'SELECT item_id, SUM(qty_base) AS qty FROM stock_balances '
    'WHERE warehouse_id = ? GROUP BY item_id',
    variables: [Variable.withInt(warehouseId)],
  ).get();
  return {
    for (final r in rows)
      r.data['item_id'] as int: r.data['qty'] as int? ?? 0,
  };
}

/// أقدم تاريخ مستند مرحّل (فواتير وسندات) — قراءة عرض خالصة (س-118/D-113
/// دفعة 9): افتراضيات المدى في التقارير — «من» أول السنة الحالية أو أول
/// مستند أيهما أحدث (بلفظ المالك «تاريخ أول المدة المحدد إن لم يكن هو
/// بداية العام»). المسودات خارجها (التقارير لا تراها أصلاً)، ولا مستندات
/// فالعدم null ويقع الافتراض على أول السنة.
Future<String?> earliestDocumentDate() async {
  final rows = await customSelect(
    "SELECT MIN(d) AS d FROM ("
    "SELECT MIN(invoice_date) AS d FROM invoices "
    "WHERE is_deleted = 0 AND state <> 'draft' "
    "UNION ALL "
    "SELECT MIN(voucher_date) AS d FROM vouchers "
    "WHERE is_deleted = 0 AND state <> 'draft')",
  ).get();
  return rows.first.data['d'] as String?;
}

/// رصيد صندوق بالأساسية (الافتتاحي + الداخل − الخارج).
Future<int> cashBoxBalanceOf(int boxId) => _cashBoxBalanceTx(boxId);

Future<CashBoxRow?> cashBoxById(int id) => _cashBoxByIdTx(id);

Future<WarehouseRow?> warehouseById(int id) => _warehouseByIdTx(id);

/// العملات المزروعة (F-120/D-070: الأساسية والدولار قبل م3).
Future<List<CurrencyRow>> currenciesOf() async {
  final rows = await customSelect(
    'SELECT id, code, name, minor_units, is_base FROM currencies '
    'WHERE is_deleted = 0 ORDER BY id',
  ).get();
  return [
    for (final r in rows)
      CurrencyRow(
        id: r.data['id'] as int,
        code: r.data['code'] as String,
        name: r.data['name'] as String,
        minorUnits: r.data['minor_units'] as int,
        isBase: (r.data['is_base'] as int) == 1,
      ),
  ];
}

  // ═══ دفعة السندات والصندوق (5) — س-61..س-70 / D-083..D-087 معروضة ═══
  // المحرك على نمط دفعة الفواتير: المدقق البنيوي في المجال والفحوص
  // المحركية هنا على ما خُزّن لا على ما قيل، والحاجز الثاني مُشغِّلات
  // القاعدة، وكل ترحيل معاملة واحدة أي رفض يتراجع كله بما فيه العدّاد.

  /// س-62: إنشاء صندوق جديد بحسابه الورقي 111x التالي (03 §3: «يُنشأ معه
  /// حساب ورقي لكل صندوق جديد (1112, 1113...)» — D-086 معروض): حساب ورقي
  /// مفعّل تحت 111 بعمته اسم الصندوق، وصندوق برصيد افتتاحي صفر وعملة
  /// واحدة لا تتغير (سند كل صندوق بعملته).
  Future<int> createCashBox({
    required String name,
    required int currencyId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('اسم الصندوق إلزامي');
    }
    final cur = await customSelect(
      'SELECT id FROM currencies WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(currencyId)],
    ).get();
    if (cur.isEmpty) {
      throw StateError('عملة الصندوق غير معروفة (س-03: «صندوق غير معرف»)');
    }
    final dup = await customSelect(
      'SELECT id FROM cash_boxes WHERE name = ? AND is_deleted = 0',
      variables: [Variable.withString(trimmed)],
    ).get();
    if (dup.isNotEmpty) {
      throw StateError('اسم الصندوق «$trimmed» مستخدم سلفاً');
    }
    return transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final maxRow = await customSelect(
        "SELECT MAX(CAST(code AS INTEGER)) AS m FROM accounts "
        "WHERE is_leaf = 1 AND code LIKE '111_'",
      ).getSingle();
      final nextCode = (maxRow.data['m'] as int? ?? 1110) + 1;
      final parentId = await _accountIdByCodeTx('111');
      final accountId = await into(accounts).insert(
        AccountsCompanion.insert(
          code: '$nextCode',
          name: trimmed,
          type: 'asset',
          normalSide: 'debit',
          parentId: Value(parentId),
          isLeaf: true,
          isActive: true,
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await customStatement(
        'INSERT INTO cash_boxes (name, currency_id, account_id, '
        'opening_balance_base_minor, uuid, created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, 0, ?, ?, ?, 0)',
        [trimmed, currencyId, accountId, const Uuid().v4(), now, now],
      );
      return (await customSelect('SELECT last_insert_rowid() AS id')
              .getSingle())
          .data['id'] as int;
    });
  }

  /// س-62: تعطيل صندوق آمن — بلا رصيد (03 §6-3: التعطيل آمن بلا أرصدة
  /// قائمة) فيعطَّل حسابه الورقي فيختفي من الاختيار ولا يقيد عليه
  /// (D-086 معروض).
  Future<void> disableCashBox(int boxId) async {
    final box = await _cashBoxByIdTx(boxId);
    if (box == null) {
      throw StateError('لا صندوق بالمعرف $boxId');
    }
    final balance = await _cashBoxBalanceTx(boxId);
    if (balance != 0) {
      throw StateError(
          'الصندوق «${box.name}» برصيد قائم — تعطيله غير آمن (03 §6-3): '
          'يُصفَّر أولاً بمستند قبض أو صرف أو تحويل أو تسوية');
    }
    await customStatement(
      'UPDATE accounts SET is_active = 0, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, box.accountId],
    );
  }

  /// س-63..س-67: إنشاء مسودة سند — المدقق البنيوي ثم الفحوص المحركية،
  /// وصفوف المطابقة صفوف مسودة تُثبت مكافئاتها عند الترحيل (عرف المسودات
  /// والترقيم لحظة الترحيل حصراً — 07 §1.9).
  Future<int> createVoucherDraft(VoucherDraft draft) async {
    return transaction(() async {
      final errors =
          await _collectVoucherErrors(draft, forPosting: false);
      if (errors.isNotEmpty) {
        throw VoucherValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT INTO vouchers (kind, number, party_id, direct_account_id, "
        "cash_box_id, voucher_date, currency_id, fx_rate, amount_doc_minor, "
        "amount_base_minor, state, move_id, narration, uuid, created_at, "
        "updated_at, is_deleted) "
        "VALUES (?, '', ?, ?, ?, ?, ?, ?, ?, ?, 'draft', NULL, ?, ?, ?, ?, 0)",
        [
          draft.kind.storageValue,
          draft.partyId,
          draft.directAccountId,
          draft.cashBoxId,
          draft.dateText,
          draft.currencyId,
          draft.fxRate,
          draft.amountDocMinor,
          convertToBaseMinor(draft.amountDocMinor, draft.fxRate),
          draft.narration,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      final voucherId = (await customSelect('SELECT last_insert_rowid() AS id')
              .getSingle())
          .data['id'] as int;
      await _replaceVoucherAllocationsTx(voucherId, draft.allocations, now);
      await _recordVoucherEventTx(voucherId: voucherId, action: 'created');
      return voucherId;
    });
  }

  /// كتابة صفوف مطابقة السند — الإدراج والمسح معاً كي يوافق المدقق دائماً
  /// ما خُزّن (المطابقات صفوف المسودة المعدَّلة قبل الترحيل).
  Future<void> _replaceVoucherAllocationsTx(
    int voucherId,
    List<VoucherAllocationDraft> allocations,
    int now,
  ) async {
    await customStatement(
      'DELETE FROM voucher_allocations WHERE voucher_id = ?',
      [voucherId],
    );
    for (final a in allocations) {
      await customStatement(
        'INSERT INTO voucher_allocations (voucher_id, invoice_id, '
        'applied_doc_minor, applied_base_minor, uuid, created_at, updated_at, '
        "is_deleted) VALUES (?, ?, ?, 0, ?, ?, ?, 0)",
        [
          voucherId,
          a.invoiceId,
          a.appliedDocMinor,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }
  }

  /// س-63..س-68: ترحيل السند — معاملة واحدة: الرقم من تسلسل نوعه ثم القيد
  /// من دفتر النقدية (move_cash) بأرجل اللقطات ثم مكافئات المطابقة بلقطة
  /// الفاتورة وآخر ما يغطيها يمتص الفارق (D-067 نمط) ثم الفائض «رصيداً
  /// مقدّماً» وفرق اللقطات صرفاً محققاً على 44/55 (F-123/D-085 معروضان)
  /// ثم حركة الصندوق ثم الحالة والرقم والقيد ثم اشتقاق حالات الفواتير
  /// المُطابَقة آلياً (F-063/D-084 معروضان) ثم حدث «posted» بلقطة السند.
  Future<int> postVoucher(int voucherId) async {
    return transaction(() async {
      final v = await _voucherRowTx(voucherId);
      if (v == null) {
        throw StateError('لا سند بالمعرف $voucherId');
      }
      if (v['state'] != 'draft') {
        throw VoucherValidationException(
            [VoucherStateNotDraft(v['state'] as String)]);
      }
      final allocRows = await _voucherAllocationsTx(voucherId);
      final draft = _voucherDraftFromRows(v, allocRows);
      final errors =
          await _collectVoucherErrors(draft, forPosting: true);
      if (errors.isNotEmpty) {
        throw VoucherValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(draft.dateText);
      final voucherNumber = formatDocumentNumber(year,
          await _advanceSequenceWithinTx(voucherSequenceKind(draft.kind), year));
      final journalId = await _journalIdByCodeTx('cash');
      final acc112 = await _accountIdByCodeTx('112');
      final acc211 = await _accountIdByCodeTx('211');
      final acc44 = await _accountIdByCodeTx('44');
      final acc55 = await _accountIdByCodeTx('55');
      final box = (await _cashBoxByIdTx(draft.cashBoxId))!;
      final totalDoc = draft.amountDocMinor;
      final totalBase = convertToBaseMinor(totalDoc, draft.fxRate);

      // مكافئ كل مطابقة بلقطة فاتورتها — وآخر ما يغطي الفاتورة يمتص فارق
      // التقريب فمجموع مطابقاتها الأساسي يساوي قيمتها المسجلة حرفاً
      // (D-084: لا غبار تقريب — نمط D-067).
      final invCache = <int, InvoiceDocument>{};
      // صفوف المطابقة خاماً من القاعدة — تُعرَّب سجلاً مكتوباً مرة واحدة
      // كي تكون حواملها نمطاً لا خرائط (درس جولة س32 الثانية).
      final allocations = [
        for (final r in allocRows)
          (
            id: r['id'] as int,
            invoiceId: r['invoice_id'] as int,
            appliedDocMinor: r['applied_doc_minor'] as int,
          ),
      ];
      final coverage =
          await _coverageByInvoiceTx([for (final a in allocations) a.invoiceId]);
      var allocatedDocTotal = 0;
      var allocatedBaseTotal = 0;
      final baseByAllocationRow = <int, int>{};
      for (final a in allocations) {
        final inv =
            invCache[a.invoiceId] ??= (await _invoiceRowTx(a.invoiceId))!;
        final remainingDoc = inv.totalDocMinor - (coverage[a.invoiceId]?.$1 ?? 0);
        final int base;
        if (a.appliedDocMinor >= remainingDoc) {
          base = inv.totalBaseMinor - (coverage[a.invoiceId]?.$2 ?? 0);
        } else {
          base = convertToBaseMinor(a.appliedDocMinor, inv.fxRate);
        }
        baseByAllocationRow[a.id] = base;
        allocatedDocTotal += a.appliedDocMinor;
        allocatedBaseTotal += base;
      }
      final advanceDoc = totalDoc - allocatedDocTotal;
      final advanceBase = convertToBaseMinor(advanceDoc, draft.fxRate);
      // فرق اللقطات على المطبَّق: ربح 44 دائناً أو خسارة 55 مديناً —
      // ولعملة الأساسية محايد صفراً حرفاً (D-085 معروض).
      final fxDiff = totalBase - allocatedBaseTotal - advanceBase;

      final docCur = draft.currencyId;
      final lines = <MoveLineDraft>[];
      if (draft.partyId != null) {
        if (draft.kind.isReceipt) {
          lines.add(MoveLineDraft(
            accountId: box.accountId,
            debitMinor: totalBase,
            currencyId: docCur,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ));
          for (final a in allocations) {
            final inv = invCache[a.invoiceId]!;
            lines.add(MoveLineDraft(
              accountId: acc112,
              creditMinor: baseByAllocationRow[a.id]!,
              partyId: draft.partyId,
              currencyId: inv.currencyId,
              amountMinor: a.appliedDocMinor,
              fxRate: inv.fxRate,
            ));
          }
          if (advanceDoc > 0) {
            lines.add(MoveLineDraft(
              accountId: acc112,
              creditMinor: advanceBase,
              partyId: draft.partyId,
              currencyId: docCur,
              amountMinor: advanceDoc,
              fxRate: draft.fxRate,
            ));
          }
          if (fxDiff > 0) {
            lines.add(MoveLineDraft(
                accountId: acc44,
                creditMinor: fxDiff,
                currencyId: 1,
                amountMinor: fxDiff));
          } else if (fxDiff < 0) {
            lines.add(MoveLineDraft(
                accountId: acc55,
                debitMinor: -fxDiff,
                currencyId: 1,
                amountMinor: -fxDiff));
          }
        } else {
          for (final a in allocations) {
            final inv = invCache[a.invoiceId]!;
            lines.add(MoveLineDraft(
              accountId: acc211,
              debitMinor: baseByAllocationRow[a.id]!,
              partyId: draft.partyId,
              currencyId: inv.currencyId,
              amountMinor: a.appliedDocMinor,
              fxRate: inv.fxRate,
            ));
          }
          if (advanceDoc > 0) {
            lines.add(MoveLineDraft(
              accountId: acc211,
              debitMinor: advanceBase,
              partyId: draft.partyId,
              currencyId: docCur,
              amountMinor: advanceDoc,
              fxRate: draft.fxRate,
            ));
          }
          if (fxDiff > 0) {
            lines.add(MoveLineDraft(
                accountId: acc55,
                debitMinor: fxDiff,
                currencyId: 1,
                amountMinor: fxDiff));
          } else if (fxDiff < 0) {
            lines.add(MoveLineDraft(
                accountId: acc44,
                creditMinor: -fxDiff,
                currencyId: 1,
                amountMinor: -fxDiff));
          }
          lines.add(MoveLineDraft(
            accountId: box.accountId,
            creditMinor: totalBase,
            currencyId: docCur,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ));
        }
      } else {
        // السند بغير طرف على حسابه المباشر (س-13/س-15): ضخ رأس مال
        // 311 ومسحوبات 321 ومصروفات 54x — بلا مطابقات ولا فروق صرفية.
        final direct = draft.directAccountId!;
        if (draft.kind.isReceipt) {
          lines.add(MoveLineDraft(
            accountId: box.accountId,
            debitMinor: totalBase,
            currencyId: docCur,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ));
          lines.add(MoveLineDraft(
            accountId: direct,
            creditMinor: totalBase,
            currencyId: docCur,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ));
        } else {
          lines.add(MoveLineDraft(
            accountId: direct,
            debitMinor: totalBase,
            currencyId: docCur,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ));
          lines.add(MoveLineDraft(
            accountId: box.accountId,
            creditMinor: totalBase,
            currencyId: docCur,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ));
        }
      }

      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: draft.dateText,
        narration: draft.narration ?? draft.kind.label,
        refDocType: 'voucher',
        refDocId: voucherId,
        lines: lines,
      ));
      await _postMoveWithinTx(moveId, sequenceKind: 'move_cash');

      // مكافئات صفوف المطابقة تُكتب قبل تجميد السند كي لا يجمد المُشغِّل
      // تحديثها (نمط الحواجز: الترتيب جزء من الصحة).
      for (final a in allocations) {
        await customStatement(
          'UPDATE voucher_allocations SET applied_base_minor = ?, '
          'updated_at = ? WHERE id = ?',
          [baseByAllocationRow[a.id]!, now, a.id],
        );
      }

      // حركة الصندوق بمصدرها المعلن (05 §4.2): القبض «داخل» والدفع «خارج» (D-105)
      await customStatement(
        "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
        "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, user_id, "
        "uuid, created_at, updated_at, is_deleted) "
        "VALUES (?, ?, ?, ?, ?, 'voucher', ?, NULL, ?, ?, ?, 0)",
        [
          box.id,
          draft.kind.isReceipt ? 'in' : 'out',
          totalDoc,
          totalBase,
          draft.fxRate,
          voucherId,
          const Uuid().v4(),
          now,
          now,
        ],
      );

      await customStatement(
        "UPDATE vouchers SET state = 'posted', number = ?, move_id = ?, "
        'amount_base_minor = ?, updated_at = ? WHERE id = ?',
        [voucherNumber, moveId, totalBase, now, voucherId],
      );

      // اشتقاق حالات الفواتير المُطابَقة آلياً بالمطابقات حصراً (F-063/
      // D-084 معروضان): غطت صافيها «مدفوعة» وجزءاً منه «جزئية» — والسند
      // صار مرحّلاً فتُحسب مطابقاته في التغطية.
      for (final iid in invCache.keys) {
        final inv = invCache[iid]!;
        final covered = await _coveredDocSingleTx(iid);
        final newState =
            covered >= inv.totalDocMinor ? 'paid' : 'partially_paid';
        await customStatement(
          'UPDATE invoices SET state = ?, updated_at = ? WHERE id = ?',
          [newState, now, iid],
        );
      }

      await _recordVoucherEventTx(voucherId: voucherId, action: 'posted');
      return voucherId;
    });
  }

  /// حذف مسودة سند — المسودة حصراً وباللقطة الكاملة في سجل الأحداث
  /// (نمط س-59)، والترقيم لحظة الترحيل فلا رقم يهدر (07 §1.9).
  Future<void> deleteVoucherDraft(int voucherId) async {
    return transaction(() async {
      final v = await _voucherRowTx(voucherId);
      if (v == null) return;
      if (v['state'] != 'draft') {
        throw VoucherValidationException(
            [VoucherStateNotDraft(v['state'] as String)]);
      }
      final snapshot = await _voucherSnapshotTx(voucherId);
      await customStatement(
        'DELETE FROM voucher_allocations WHERE voucher_id = ?',
        [voucherId],
      );
      await customStatement('DELETE FROM vouchers WHERE id = ?', [voucherId]);
      await into(events).insert(
        EventsCompanion.insert(
          eventAt: DateTime.now().millisecondsSinceEpoch,
          deviceId: await deviceId(),
          entityType: 'voucher',
          entityId: Value(voucherId),
          action: 'draft_deleted',
          payload: snapshot,
          uuid: const Uuid().v4(),
        ),
      );
    });
  }

  /// فحوص السند المحركية — المشتركة بين الإنشاء والترحيل: الفترة المفتوحة
  /// عند الترحيل حصراً (المسودات على أي تاريخ — نمط الفواتير)، والصندوق
  /// ونشاط حسابه وعملته، والحساب المباشر ورقياً نشطاً غير صندوق، وصفوف
  /// المطابقة لفواتير الطرف المرحّلة المفتوحة بعملة السند (D-084 معروض).
  Future<List<VoucherValidationError>> _collectVoucherErrors(
    VoucherDraft draft, {
    required bool forPosting,
  }) async {
    final errors = validateVoucherDraftStructure(draft);
    if (errors.isNotEmpty) return errors;

    if (forPosting) {
      final period = findPeriodForDate(await ledgerPeriods(), draft.dateText);
      if (period == null) {
        errors.add(VoucherNoPeriod(draft.dateText));
      } else if (!period.isOpen) {
        errors.add(VoucherClosedPeriod(draft.dateText));
      }
    }

    final box = await _cashBoxByIdTx(draft.cashBoxId);
    if (box == null) {
      errors.add(const VoucherBoxMissing());
    } else {
      if (!await _accountActiveTx(box.accountId)) {
        errors.add(VoucherBoxInactive('${box.name} (حساب الصندوق)'));
      }
      if (box.currencyId != draft.currencyId) {
        errors.add(const VoucherBoxCurrencyMismatch());
      }
    }

    if (draft.directAccountId != null) {
      final acc = await _accountByIdTx(draft.directAccountId!);
      final label = acc == null
          ? 'معرّف ${draft.directAccountId}'
          : '${acc.$2} (${acc.$1})';
      if (acc == null || !acc.$3 || !acc.$4) {
        errors.add(VoucherDirectAccountNotLedgerable(label));
      } else if (await _isBoxAccountTx(draft.directAccountId!)) {
        errors.add(VoucherDirectAccountIsBox(label));
      }
    }

    if (draft.partyId != null && errors.isEmpty) {
      final expectedKind = draft.kind.isReceipt ? 'sale' : 'purchase';
      final coverage = await _coverageByInvoiceTx(
          [for (final a in draft.allocations) a.invoiceId]);
      for (final a in draft.allocations) {
        final inv = await _invoiceRowTx(a.invoiceId);
        if (inv == null) {
          errors.add(VoucherAllocationInvoiceUnknown(a.invoiceId));
          continue;
        }
        if (inv.state == 'draft') {
          errors.add(
              VoucherAllocationInvoiceNotCommitted(a.invoiceId, inv.state));
          continue;
        }
        if (inv.state == 'paid') {
          errors.add(VoucherAllocationInvoicePaid(a.invoiceId));
          continue;
        }
        if (inv.partyId != draft.partyId) {
          errors.add(VoucherAllocationWrongParty(a.invoiceId));
          continue;
        }
        if (inv.kind != expectedKind) {
          errors.add(VoucherAllocationWrongKind(a.invoiceId));
          continue;
        }
        if (inv.currencyId != draft.currencyId) {
          errors.add(VoucherAllocationCurrencyMismatch(a.invoiceId));
          continue;
        }
        final remaining = inv.totalDocMinor - (coverage[a.invoiceId]?.$1 ?? 0);
        if (a.appliedDocMinor > remaining) {
          errors.add(VoucherAllocationExceedsRemaining(
              a.invoiceId, invoiceDisplayLabel(inv), remaining));
        }
      }
    }
    return errors;
  }

  /// س-63: التوزيع الآلي بالأقدمية على فواتير الطرف المفتوحة بعملة السند
  /// (02 §8/س-12) — اقتراح معدَّل قبل الترحيل لا قرار نهائي.
  Future<List<VoucherAllocationDraft>> proposeVoucherAllocations({
    required VoucherKind kind,
    required int partyId,
    required int currencyId,
    required int amountDocMinor,
  }) async {
    final open = await openInvoicesForParty(
        kind: kind, partyId: partyId, currencyId: currencyId);
    return proposeOldestAllocations(
        amountDocMinor: amountDocMinor, openInvoices: open);
  }

  /// فواتير الطرف المفتوحة (المرحّلة غير المغطاة كلياً بمطابقات السندات
  /// المرحّلة) بعملة السند — مرشحات التوزيع الآلي (المسودات مقترحات
  /// لا تُحسب).
  Future<List<OpenInvoiceCandidate>> openInvoicesForParty({
    required VoucherKind kind,
    required int partyId,
    required int currencyId,
  }) async {
    final docKind = kind.isReceipt ? 'sale' : 'purchase';
    final rows = await customSelect(
      "SELECT id, number, invoice_date, due_date, total_doc_minor "
      "FROM invoices WHERE party_id = ?1 AND kind = ?2 AND currency_id = ?3 "
      "AND state IN ('posted', 'partially_paid') AND is_deleted = 0 "
      "ORDER BY COALESCE(due_date, '9999-12-31'), invoice_date, number",
      variables: [
        Variable.withInt(partyId),
        Variable.withString(docKind),
        Variable.withInt(currencyId),
      ],
    ).get();
    final out = <OpenInvoiceCandidate>[];
    for (final r in rows) {
      final covered = await _coveredDocSingleTx(r.data['id'] as int);
      final remaining = (r.data['total_doc_minor'] as int) - covered;
      if (remaining <= 0) continue;
      out.add(OpenInvoiceCandidate(
        invoiceId: r.data['id'] as int,
        remainingDocMinor: remaining,
        dateText: r.data['invoice_date'] as String,
        dueDateText: r.data['due_date'] as String?,
        number: r.data['number'] as String,
      ));
    }
    return out;
  }

  /// س-69: إنشاء مسودة تحويل بين صندوقين (س-16/F-068) — والفحوص المحركية
  /// كاملة: صندوقان مختلفان بنفس العملة وحساباهما نشطان ورصيد المرسل
  /// يكفي (منع السالب الموحد — 05 §7-2).
  Future<int> createCashTransferDraft(CashTransferDraft draft) async {
    return transaction(() async {
      final errors = await _collectTransferErrors(draft, forPosting: false);
      if (errors.isNotEmpty) {
        throw CashTransferValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT INTO box_transfers (number, from_box_id, to_box_id, "
        "transfer_date, currency_id, fx_rate, amount_doc_minor, "
        "amount_base_minor, state, move_id, narration, uuid, created_at, "
        "updated_at, is_deleted) "
        "VALUES ('', ?, ?, ?, ?, ?, ?, ?, 'draft', NULL, ?, ?, ?, ?, 0)",
        [
          draft.fromBoxId,
          draft.toBoxId,
          draft.dateText,
          draft.currencyId,
          draft.fxRate,
          draft.amountDocMinor,
          convertToBaseMinor(draft.amountDocMinor, draft.fxRate),
          draft.narration,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      final transferId = (await customSelect('SELECT last_insert_rowid() AS id')
              .getSingle())
          .data['id'] as int;
      await _recordDocEventTx(
        entityType: 'box_transfer',
        table: 'box_transfers',
        entityId: transferId,
        action: 'created',
      );
      return transferId;
    });
  }

  /// س-69: ترحيل التحويل — قيد متوازن بسطرين «صندوق المستلم مدين / صندوق
  /// المرسل دائن» يجسد القيدين المتكاملين (خروج/دخول) بلا حساب وسيط ولا
  /// رصيد معلق (D-087 معروض — توازن الطرفين لحظياً معيار F-068)، وحركتا
  /// صندوق بمرجعية المستند المتبادلة، والرقم من تسلسل «box_transfer».
  Future<int> postCashTransfer(int transferId) async {
    return transaction(() async {
      final t = await _transferRowTx(transferId);
      if (t == null) {
        throw StateError('لا تحويل بالمعرف $transferId');
      }
      if (t['state'] != 'draft') {
        throw CashTransferValidationException(
            [TransferStateNotDraft(t['state'] as String)]);
      }
      final draft = CashTransferDraft(
        dateText: t['transfer_date'] as String,
        fromBoxId: t['from_box_id'] as int,
        toBoxId: t['to_box_id'] as int,
        amountDocMinor: t['amount_doc_minor'] as int,
        currencyId: t['currency_id'] as int,
        fxRate: t['fx_rate'] as int,
        narration: t['narration'] as String?,
      );
      final errors = await _collectTransferErrors(draft, forPosting: true);
      if (errors.isNotEmpty) {
        throw CashTransferValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(draft.dateText);
      final number = formatDocumentNumber(year,
          await _advanceSequenceWithinTx('box_transfer', year));
      final journalId = await _journalIdByCodeTx('cash');
      final fromBox = (await _cashBoxByIdTx(draft.fromBoxId))!;
      final toBox = (await _cashBoxByIdTx(draft.toBoxId))!;
      final totalDoc = draft.amountDocMinor;
      final totalBase = convertToBaseMinor(totalDoc, draft.fxRate);

      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: draft.dateText,
        narration: draft.narration ?? 'تحويل بين صناديق',
        refDocType: 'box_transfer',
        refDocId: transferId,
        lines: [
          MoveLineDraft(
            accountId: toBox.accountId,
            debitMinor: totalBase,
            currencyId: draft.currencyId,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ),
          MoveLineDraft(
            accountId: fromBox.accountId,
            creditMinor: totalBase,
            currencyId: draft.currencyId,
            amountMinor: totalDoc,
            fxRate: draft.fxRate,
          ),
        ],
      ));
      await _postMoveWithinTx(moveId, sequenceKind: 'move_cash');

      // حركتا الصندوق بمرجعية متبادلة عبر مرجع المستند المشترك (03 §4)
      for (final entry in [
        (fromBox.id, 'transfer_out'),
        (toBox.id, 'transfer_in'),
      ]) {
        await customStatement(
          "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
          "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, user_id, "
          "uuid, created_at, updated_at, is_deleted) "
          "VALUES (?, ?, ?, ?, ?, 'box_transfer', ?, NULL, ?, ?, ?, 0)",
          [
            entry.$1,
            entry.$2,
            totalDoc,
            totalBase,
            draft.fxRate,
            transferId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
      }

      await customStatement(
        "UPDATE box_transfers SET state = 'posted', number = ?, move_id = ?, "
        'updated_at = ? WHERE id = ?',
        [number, moveId, now, transferId],
      );
      await _recordDocEventTx(
        entityType: 'box_transfer',
        table: 'box_transfers',
        entityId: transferId,
        action: 'posted',
      );
      return transferId;
    });
  }

  /// فحوص التحويل المحركية — الصندوقان موجودان نشطا الحساب وبنفس العملة
  /// ورصيد المرسل يكفي (س-16/§10.1).
  Future<List<CashTransferValidationError>> _collectTransferErrors(
    CashTransferDraft draft, {
    required bool forPosting,
  }) async {
    final errors = validateCashTransferStructure(draft);
    if (errors.isNotEmpty) return errors;

    if (forPosting) {
      final period = findPeriodForDate(await ledgerPeriods(), draft.dateText);
      if (period == null) {
        errors.add(TransferNoPeriod(draft.dateText));
      } else if (!period.isOpen) {
        errors.add(TransferClosedPeriod(draft.dateText));
      }
    }

    final fromBox = await _cashBoxByIdTx(draft.fromBoxId);
    final toBox = await _cashBoxByIdTx(draft.toBoxId);
    if (fromBox == null || toBox == null) {
      errors.add(const TransferBoxMissing());
      return errors;
    }
    if (!await _accountActiveTx(fromBox.accountId)) {
      errors.add(TransferBoxInactive('${fromBox.name} (المرسل)'));
    }
    if (!await _accountActiveTx(toBox.accountId)) {
      errors.add(TransferBoxInactive('${toBox.name} (المستلم)'));
    }
    if (fromBox.currencyId != toBox.currencyId) {
      errors.add(const TransferCurrencyMismatch());
    }
    final amountBase = convertToBaseMinor(draft.amountDocMinor, draft.fxRate);
    final balance = await _cashBoxBalanceTx(draft.fromBoxId);
    if (balance < amountBase) {
      errors.add(TransferSenderInsufficient(balance, amountBase));
    }
    return errors;
  }

  /// س-70: إنشاء مسودة تسوية صندوق (س-17/F-067) — والفرق صفر لا يولّد
  /// تسوية أصلاً فالمبلغ موجب ببنية المسودة، والسبب نصي إلزامي.
  Future<int> createCashAdjustmentDraft(CashAdjustmentDraft draft) async {
    return transaction(() async {
      final errors = await _collectAdjustmentErrors(draft, forPosting: false);
      if (errors.isNotEmpty) {
        throw CashAdjustmentValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT INTO cash_adjustments (number, cash_box_id, adjustment_date, "
        "direction, currency_id, fx_rate, amount_doc_minor, "
        "amount_base_minor, reason, state, move_id, uuid, created_at, "
        "updated_at, is_deleted) "
        "VALUES ('', ?, ?, ?, ?, ?, ?, ?, ?, 'draft', NULL, ?, ?, ?, 0)",
        [
          draft.cashBoxId,
          draft.dateText,
          draft.direction.storageValue,
          draft.currencyId,
          draft.fxRate,
          draft.amountDocMinor,
          convertToBaseMinor(draft.amountDocMinor, draft.fxRate),
          draft.reason.trim(),
          const Uuid().v4(),
          now,
          now,
        ],
      );
      final adjustmentId =
          (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
              .data['id'] as int;
      await _recordDocEventTx(
        entityType: 'cash_adjustment',
        table: 'cash_adjustments',
        entityId: adjustmentId,
        action: 'created',
      );
      return adjustmentId;
    });
  }

  /// س-70: ترحيل التسوية — العجز: 57 مدين / الصندوق دائن والزيادة:
  /// الصندوق مدين / 57 دائن (الحساب الواحد للعجز والزيادة — س8/F-067)،
  /// وحركة الصندوق بمصدرها والرقم من تسلسل «cash_adjustment».
  Future<int> postCashAdjustment(int adjustmentId) async {
    return transaction(() async {
      final a = await _adjustmentRowTx(adjustmentId);
      if (a == null) {
        throw StateError('لا تسوية بالمعرف $adjustmentId');
      }
      if (a['state'] != 'draft') {
        throw CashAdjustmentValidationException(
            [AdjustmentStateNotDraft(a['state'] as String)]);
      }
      final draft = CashAdjustmentDraft(
        dateText: a['adjustment_date'] as String,
        cashBoxId: a['cash_box_id'] as int,
        currencyId: a['currency_id'] as int,
        fxRate: a['fx_rate'] as int,
        direction:
            CashAdjustmentDirection.fromStorage(a['direction'] as String),
        amountDocMinor: a['amount_doc_minor'] as int,
        reason: a['reason'] as String? ?? '',
      );
      final errors = await _collectAdjustmentErrors(draft, forPosting: true);
      if (errors.isNotEmpty) {
        throw CashAdjustmentValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(draft.dateText);
      final number = formatDocumentNumber(year,
          await _advanceSequenceWithinTx('cash_adjustment', year));
      final journalId = await _journalIdByCodeTx('cash');
      final acc57 = await _accountIdByCodeTx('57');
      final box = (await _cashBoxByIdTx(draft.cashBoxId))!;
      final totalDoc = draft.amountDocMinor;
      final totalBase = convertToBaseMinor(totalDoc, draft.fxRate);
      final isShortage = draft.direction == CashAdjustmentDirection.shortage;

      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: draft.dateText,
        narration: 'تسوية صندوق — ${draft.direction.label}: ${draft.reason.trim()}',
        refDocType: 'cash_adjustment',
        refDocId: adjustmentId,
        lines: [
          if (isShortage)
            MoveLineDraft(
              accountId: acc57,
              debitMinor: totalBase,
              currencyId: 1,
              amountMinor: totalBase,
            )
          else
            MoveLineDraft(
              accountId: box.accountId,
              debitMinor: totalBase,
              currencyId: draft.currencyId,
              amountMinor: totalDoc,
              fxRate: draft.fxRate,
            ),
          if (isShortage)
            MoveLineDraft(
              accountId: box.accountId,
              creditMinor: totalBase,
              currencyId: draft.currencyId,
              amountMinor: totalDoc,
              fxRate: draft.fxRate,
            )
          else
            MoveLineDraft(
              accountId: acc57,
              creditMinor: totalBase,
              currencyId: 1,
              amountMinor: totalBase,
            ),
        ],
      ));
      await _postMoveWithinTx(moveId, sequenceKind: 'move_cash');

      await customStatement(
        "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
        "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, user_id, "
        "uuid, created_at, updated_at, is_deleted) "
        "VALUES (?, ?, ?, ?, ?, 'cash_adjustment', ?, NULL, ?, ?, ?, 0)",
        [
          box.id,
          isShortage ? 'out' : 'in',
          totalDoc,
          totalBase,
          draft.fxRate,
          adjustmentId,
          const Uuid().v4(),
          now,
          now,
        ],
      );

      await customStatement(
        "UPDATE cash_adjustments SET state = 'posted', number = ?, "
        'move_id = ?, updated_at = ? WHERE id = ?',
        [number, moveId, now, adjustmentId],
      );
      await _recordDocEventTx(
        entityType: 'cash_adjustment',
        table: 'cash_adjustments',
        entityId: adjustmentId,
        action: 'posted',
      );
      return adjustmentId;
    });
  }

  /// فحوص التسوية المحركية — الصندوق موجود وحسابه نشط وعملته عملة التسوية.
  Future<List<CashAdjustmentValidationError>> _collectAdjustmentErrors(
    CashAdjustmentDraft draft, {
    required bool forPosting,
  }) async {
    final errors = validateCashAdjustmentStructure(draft);
    if (errors.isNotEmpty) return errors;

    if (forPosting) {
      final period = findPeriodForDate(await ledgerPeriods(), draft.dateText);
      if (period == null) {
        errors.add(AdjustmentNoPeriod(draft.dateText));
      } else if (!period.isOpen) {
        errors.add(AdjustmentClosedPeriod(draft.dateText));
      }
    }

    final box = await _cashBoxByIdTx(draft.cashBoxId);
    if (box == null) {
      errors.add(const AdjustmentBoxMissing());
    } else {
      if (!await _accountActiveTx(box.accountId)) {
        errors.add(AdjustmentBoxInactive('${box.name} (حساب الصندوق)'));
      }
      if (box.currencyId != draft.currencyId) {
        errors.add(const AdjustmentBoxCurrencyMismatch());
      }
    }
    return errors;
  }

  // ─── قراءات السندات وأدواتها الداخلية ───

  Future<Map<String, Object?>?> _voucherRowTx(int id) async {
    final rows = await customSelect(
      'SELECT * FROM vouchers WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(id)],
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<List<Map<String, Object?>>> _voucherAllocationsTx(int voucherId) async {
    final rows = await customSelect(
      'SELECT * FROM voucher_allocations WHERE voucher_id = ? '
      'AND is_deleted = 0 ORDER BY id',
      variables: [Variable.withInt(voucherId)],
    ).get();
    return [for (final r in rows) r.data];
  }

  Future<Map<String, Object?>?> _transferRowTx(int id) async {
    final rows = await customSelect(
      'SELECT * FROM box_transfers WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(id)],
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<Map<String, Object?>?> _adjustmentRowTx(int id) async {
    final rows = await customSelect(
      'SELECT * FROM cash_adjustments WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(id)],
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// إعادة بناء مسودة السند من صفوفها — التحقق على ما خُزّن لا على ما قيل
  /// (نمط الفواتير: لا ثقة بالمدخلات بعد كتابتها).
  VoucherDraft _voucherDraftFromRows(
    Map<String, Object?> v,
    List<Map<String, Object?>> allocs,
  ) {
    return VoucherDraft(
      kind: VoucherKind.fromStorage(v['kind'] as String),
      dateText: v['voucher_date'] as String,
      partyId: v['party_id'] as int?,
      directAccountId: v['direct_account_id'] as int?,
      cashBoxId: v['cash_box_id'] as int,
      currencyId: v['currency_id'] as int,
      fxRate: v['fx_rate'] as int,
      amountDocMinor: v['amount_doc_minor'] as int,
      narration: v['narration'] as String?,
      allocations: [
        for (final a in allocs)
          VoucherAllocationDraft(
            invoiceId: a['invoice_id'] as int,
            appliedDocMinor: a['applied_doc_minor'] as int,
          ),
      ],
    );
  }

  /// تغطية الفواتير بمطابقات السندات المرحّلة حصراً — (مطبَّق بعملة
  /// الفاتورة، مكافؤه الأساسي) لكل فاتورة من المطلوبة.
  Future<Map<int, (int, int)>> _coverageByInvoiceTx(
      List<int> invoiceIds) async {
    if (invoiceIds.isEmpty) return {};
    final rows = await customSelect(
      'SELECT va.invoice_id AS iid, '
      'COALESCE(SUM(va.applied_doc_minor), 0) AS doc, '
      'COALESCE(SUM(va.applied_base_minor), 0) AS base '
      'FROM voucher_allocations va JOIN vouchers v ON v.id = va.voucher_id '
      "WHERE v.state = 'posted' AND v.is_deleted = 0 AND va.is_deleted = 0 "
      'AND va.invoice_id IN (${invoiceIds.join(',')}) '
      'GROUP BY va.invoice_id',
    ).get();
    return {
      for (final r in rows)
        r.data['iid'] as int: (
          (r.data['doc'] as int?) ?? 0,
          (r.data['base'] as int?) ?? 0,
        )
    };
  }

  Future<int> _coveredDocSingleTx(int invoiceId) async {
    final rows = await customSelect(
      'SELECT COALESCE(SUM(va.applied_doc_minor), 0) AS c '
      'FROM voucher_allocations va JOIN vouchers v ON v.id = va.voucher_id '
      "WHERE va.invoice_id = ?1 AND v.state = 'posted' "
      'AND v.is_deleted = 0 AND va.is_deleted = 0',
      variables: [Variable.withInt(invoiceId)],
    ).get();
    return rows.first.data['c'] as int;
  }

  Future<(String, String, bool, bool)?> _accountByIdTx(int id) async {
    final rows = await customSelect(
      'SELECT code, name, is_leaf, is_active FROM accounts WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).get();
    if (rows.isEmpty) return null;
    final d = rows.first.data;
    return (
      d['code'] as String,
      d['name'] as String,
      (d['is_leaf'] as int) == 1,
      (d['is_active'] as int) == 1,
    );
  }

  Future<bool> _accountActiveTx(int accountId) async {
    final rows = await customSelect(
      'SELECT is_active FROM accounts WHERE id = ?',
      variables: [Variable.withInt(accountId)],
    ).get();
    return rows.isNotEmpty && (rows.first.data['is_active'] as int) == 1;
  }

  Future<bool> _isBoxAccountTx(int accountId) async {
    final rows = await customSelect(
      'SELECT id FROM cash_boxes WHERE account_id = ? AND is_deleted = 0',
      variables: [Variable.withInt(accountId)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<String> _voucherSnapshotTx(int voucherId) async {
    final v = (await _voucherRowTx(voucherId))!;
    final allocs = await _voucherAllocationsTx(voucherId);
    return jsonEncode(<String, Object?>{
      'id': v['id'],
      'kind': v['kind'],
      'number': v['number'],
      'party_id': v['party_id'],
      'direct_account_id': v['direct_account_id'],
      'cash_box_id': v['cash_box_id'],
      'date': v['voucher_date'],
      'currency_id': v['currency_id'],
      'fx_rate': v['fx_rate'],
      'amount_doc_minor': v['amount_doc_minor'],
      'amount_base_minor': v['amount_base_minor'],
      'state': v['state'],
      'move_id': v['move_id'],
      'narration': v['narration'],
      'allocations': [
        for (final a in allocs)
          <String, Object?>{
            'invoice_id': a['invoice_id'],
            'applied_doc_minor': a['applied_doc_minor'],
            'applied_base_minor': a['applied_base_minor'],
          },
      ],
    });
  }

  Future<void> _recordVoucherEventTx({
    required int voucherId,
    required String action,
  }) async {
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: DateTime.now().millisecondsSinceEpoch,
        deviceId: await deviceId(),
        entityType: 'voucher',
        entityId: Value(voucherId),
        action: action,
        payload: await _voucherSnapshotTx(voucherId),
        uuid: const Uuid().v4(),
      ),
    );
  }

  /// حدث عام لمستندَي التحويل والتسوية — لقطة الصف الكامل (F-173 نمط).
  Future<void> _recordDocEventTx({
    required String entityType,
    required String table,
    required int entityId,
    required String action,
  }) async {
    final rows = await customSelect(
      'SELECT * FROM $table WHERE id = ?',
      variables: [Variable.withInt(entityId)],
    ).get();
    final payload = jsonEncode(rows.isEmpty ? <String, Object?>{} : rows.first.data);
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: DateTime.now().millisecondsSinceEpoch,
        deviceId: await deviceId(),
        entityType: entityType,
        entityId: Value(entityId),
        action: action,
        payload: payload,
        uuid: const Uuid().v4(),
      ),
    );
  }

  /// قراءة سند قائم — التخزين يقرأ ولا يحسب (نمط القلب).
  Future<VoucherDocument?> voucherById(int id) async {
    final v = await _voucherRowTx(id);
    if (v == null) return null;
    return VoucherDocument(
      id: v['id'] as int,
      kind: v['kind'] as String,
      number: v['number'] as String,
      partyId: v['party_id'] as int?,
      directAccountId: v['direct_account_id'] as int?,
      cashBoxId: v['cash_box_id'] as int,
      voucherDate: v['voucher_date'] as String,
      currencyId: v['currency_id'] as int,
      fxRate: v['fx_rate'] as int,
      amountDocMinor: v['amount_doc_minor'] as int,
      amountBaseMinor: v['amount_base_minor'] as int,
      state: v['state'] as String,
      moveId: v['move_id'] as int?,
      narration: v['narration'] as String?,
    );
  }

  Future<List<VoucherAllocationDocument>> voucherAllocationsOf(
      int voucherId) async {
    final rows = await _voucherAllocationsTx(voucherId);
    return [
      for (final a in rows)
        VoucherAllocationDocument(
          id: a['id'] as int,
          voucherId: a['voucher_id'] as int,
          invoiceId: a['invoice_id'] as int,
          appliedDocMinor: a['applied_doc_minor'] as int,
          appliedBaseMinor: a['applied_base_minor'] as int,
        ),
    ];
  }

  /// مجموع مطابقات فاتورة من السندات المرحّلة بعملة الفاتورة — بذرة
  /// الاشتقاق والقراءة (F-063/D-084 معروضان).
  Future<int> invoiceCoveredDocMinor(int invoiceId) =>
      _coveredDocSingleTx(invoiceId);

/// جداول دفعة السندات (05 §4.2 + س-16/س-17): السند وصفوف مطابقته
/// (تشغيلية جزء لا يتجزأ من السند — م-21/D-042) ومستندا التحويل
/// والتسوية برقمهما المستقل (D-083 معروض). الأعمدة التنفيذية:
/// `applied_doc_minor` على المطابقة بعملة الفاتورة (D-084 معروض)
/// و`number`/`state`/`move_id` على المستندات الأربعة بنمط الفواتير.
Future<void> _createVoucherTables() async {
  const statements = <String>[
    'CREATE TABLE IF NOT EXISTS "vouchers" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"kind" TEXT NOT NULL, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"party_id" INTEGER NULL, '
        '"direct_account_id" INTEGER NULL, '
        '"cash_box_id" INTEGER NOT NULL, '
        '"voucher_date" TEXT NOT NULL, '
        '"currency_id" INTEGER NOT NULL DEFAULT 1, '
        '"fx_rate" INTEGER NOT NULL, '
        '"amount_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"amount_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"state" TEXT NOT NULL DEFAULT \'draft\', '
        '"move_id" INTEGER NULL, '
        '"narration" TEXT NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "voucher_allocations" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"voucher_id" INTEGER NOT NULL, '
        '"invoice_id" INTEGER NOT NULL, '
        '"applied_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"applied_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "box_transfers" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"from_box_id" INTEGER NOT NULL, '
        '"to_box_id" INTEGER NOT NULL, '
        '"transfer_date" TEXT NOT NULL, '
        '"currency_id" INTEGER NOT NULL DEFAULT 1, '
        '"fx_rate" INTEGER NOT NULL, '
        '"amount_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"amount_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"state" TEXT NOT NULL DEFAULT \'draft\', '
        '"move_id" INTEGER NULL, '
        '"narration" TEXT NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "cash_adjustments" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"cash_box_id" INTEGER NOT NULL, '
        '"adjustment_date" TEXT NOT NULL, '
        '"direction" TEXT NOT NULL, '
        '"currency_id" INTEGER NOT NULL DEFAULT 1, '
        '"fx_rate" INTEGER NOT NULL, '
        '"amount_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"amount_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"reason" TEXT NOT NULL DEFAULT \'\', '
        '"state" TEXT NOT NULL DEFAULT \'draft\', '
        '"move_id" INTEGER NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

/// المُشغِّلات الحواجز لجداول السندات — الحاجز الثاني المختبَر بعد فحص
/// المحرك (نمط D-067): تجميد السند المرحّل وصفوف مطابقاته ومستندَي
/// التحويل والتسوية، ومنع حذف المرحّل، ومنع مطابقة فاتورة مسودة،
/// وتوسعة حاجز سالب الصندوق لتشمل الخروج بالتحويل (D-083 معروض).
Future<void> _createVoucherTriggers() async {
  const triggers = <String>[
    // توسيع حاجز سالب الصندوق (05 §7-2): الخروج بالتحويل خروج فعلي من
    // الصندوق يقبضه الحاجز ذاته — والداخل بالتحويل دخول لا حاجز عليه.
    // إعادة تعريف موثقة للنسخة المجرَّبة بشرط أوسع وتوازن يشمل transfer_in.
    'DROP TRIGGER IF EXISTS trg_cash_no_negative',
    "CREATE TRIGGER trg_cash_no_negative "
        "BEFORE INSERT ON cash_movements FOR EACH ROW "
        "WHEN NEW.kind IN ('out', 'transfer_out') AND ("
        "(SELECT COALESCE(opening_balance_base_minor, 0) FROM cash_boxes "
        " WHERE id = NEW.cash_box_id)"
        " + (SELECT COALESCE(SUM(CASE WHEN kind IN ('in', 'transfer_in') "
        "THEN amount_base_minor ELSE -amount_base_minor END), 0) "
        "FROM cash_movements WHERE cash_box_id = NEW.cash_box_id)"
        " - NEW.amount_base_minor < 0) "
        "BEGIN "
        "SELECT RAISE(ABORT, 'رصيد الصندوق لا يكفي — منع السالب الموحد "
        "(05 §7-2)'); END",
    // تجميد السند المرحّل — ما رُحّل لا يعدل (07 §1.3/05 §7-4) والتصحيح
    // بمطابقة تكميلية (س-12) أو مستند معاكس
    "CREATE TRIGGER IF NOT EXISTS trg_vouchers_posted_frozen "
        "BEFORE UPDATE ON vouchers FOR EACH ROW "
        "WHEN OLD.state = 'posted' AND ("
        "NEW.kind IS NOT OLD.kind OR "
        "NEW.number IS NOT OLD.number OR "
        "COALESCE(NEW.party_id,-1) IS NOT COALESCE(OLD.party_id,-1) OR "
        "COALESCE(NEW.direct_account_id,-1) IS NOT "
        "COALESCE(OLD.direct_account_id,-1) OR "
        "NEW.cash_box_id IS NOT OLD.cash_box_id OR "
        "NEW.voucher_date IS NOT OLD.voucher_date OR "
        "NEW.currency_id IS NOT OLD.currency_id OR "
        "NEW.fx_rate IS NOT OLD.fx_rate OR "
        "NEW.amount_doc_minor IS NOT OLD.amount_doc_minor OR "
        "NEW.amount_base_minor IS NOT OLD.amount_base_minor OR "
        "COALESCE(NEW.move_id,-1) IS NOT COALESCE(OLD.move_id,-1)) "
        "BEGIN "
        "SELECT RAISE(ABORT, 'السند المرحّل لا تعدل — التصحيح بمطابقة "
        "تكميلية أو مستند معاكس (07 §1.3)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_vouchers_no_delete_posted "
        "BEFORE DELETE ON vouchers FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'السند المرحّل لا يحذف (05 §7-4)'); END",
    // صفوف مطابقة السند المرحّل مجمدة — والمسودة تُعدَّل بحرية قبل الترحيل
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_frozen_insert "
        "BEFORE INSERT ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM vouchers WHERE id = NEW.voucher_id) "
        "<> 'draft' "
        "BEGIN "
        "SELECT RAISE(ABORT, 'مطابقات السند المرحّل لا تضاف — التصحيح "
        "بمطابقة تكميلية (س-12)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_frozen_update "
        "BEFORE UPDATE ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM vouchers WHERE id = OLD.voucher_id) "
        "= 'posted' "
        "BEGIN SELECT RAISE(ABORT, 'مطابقات السند المرحّل لا تعدل'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_frozen_delete "
        "BEFORE DELETE ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM vouchers WHERE id = OLD.voucher_id) "
        "= 'posted' "
        "BEGIN SELECT RAISE(ABORT, 'مطابقات السند المرحّل لا تحذف'); END",
    // حاجز ثالث: لا مطابقة على فاتورة مسودة حتى لو تسللت بمعاملة خارجية
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_no_draft_invoice "
        "BEFORE INSERT ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = NEW.invoice_id) "
        "= 'draft' "
        "BEGIN "
        "SELECT RAISE(ABORT, 'لا مطابقة على فاتورة مسودة — تُرحَّل أولاً'); "
        "END",
    // تجميد التحويل المرحّل — قيد الطرفين لحظي لا مساس به (F-068)
    "CREATE TRIGGER IF NOT EXISTS trg_box_transfers_posted_frozen "
        "BEFORE UPDATE ON box_transfers FOR EACH ROW "
        "WHEN OLD.state = 'posted' AND ("
        "NEW.number IS NOT OLD.number OR "
        "NEW.from_box_id IS NOT OLD.from_box_id OR "
        "NEW.to_box_id IS NOT OLD.to_box_id OR "
        "NEW.transfer_date IS NOT OLD.transfer_date OR "
        "NEW.currency_id IS NOT OLD.currency_id OR "
        "NEW.fx_rate IS NOT OLD.fx_rate OR "
        "NEW.amount_doc_minor IS NOT OLD.amount_doc_minor OR "
        "NEW.amount_base_minor IS NOT OLD.amount_base_minor OR "
        "COALESCE(NEW.move_id,-1) IS NOT COALESCE(OLD.move_id,-1)) "
        "BEGIN "
        "SELECT RAISE(ABORT, 'التحويل المرحّل لا تعدل (07 §1.3)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_box_transfers_no_delete_posted "
        "BEFORE DELETE ON box_transfers FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'التحويل المرحّل لا يحذف (05 §7-4)'); END",
    // تجميد التسوية المرحّلة — مستند موثق مرقّم لا يعدل (س-17)
    "CREATE TRIGGER IF NOT EXISTS trg_cash_adjustments_posted_frozen "
        "BEFORE UPDATE ON cash_adjustments FOR EACH ROW "
        "WHEN OLD.state = 'posted' AND ("
        "NEW.number IS NOT OLD.number OR "
        "NEW.cash_box_id IS NOT OLD.cash_box_id OR "
        "NEW.adjustment_date IS NOT OLD.adjustment_date OR "
        "NEW.direction IS NOT OLD.direction OR "
        "NEW.currency_id IS NOT OLD.currency_id OR "
        "NEW.fx_rate IS NOT OLD.fx_rate OR "
        "NEW.amount_doc_minor IS NOT OLD.amount_doc_minor OR "
        "NEW.amount_base_minor IS NOT OLD.amount_base_minor OR "
        "NEW.reason IS NOT OLD.reason OR "
        "COALESCE(NEW.move_id,-1) IS NOT COALESCE(OLD.move_id,-1)) "
        "BEGIN "
        "SELECT RAISE(ABORT, 'التسوية المرحّلة لا تعدل (07 §1.3)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_cash_adjustments_no_delete_posted "
        "BEFORE DELETE ON cash_adjustments FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'التسوية المرحّلة لا تحذف (05 §7-4)'); END",
  ];
  for (final sql in triggers) {
    await customStatement(sql);
  }
}

/// بذر دفعة السندات (س-61): تفعيل حسابَي فروق العملة الجاهزين معطلين
/// (44 أرباحها و55 خسائرها — F-123/D-085 معروضان: تفعيل إعداداً بلا
/// واجهة إعدادات بعد، نتيجة تقديم D-070 لتعدد العملات إلى م1-نواة).
/// البذر فاحص الحالة ذاته فآمن التكرار.
Future<void> _seedVoucherBaseline() async {
  await customStatement(
      "UPDATE accounts SET is_active = 1 "
      "WHERE code IN ('44', '55') AND is_active = 0");
}

// ═══════════════════════════════════════════════════════════════════
// دفعة (6) التقارير والإغلاق — الدفعة السادسة والأخيرة من م1-نواة
// (س-71..س-78، D-088..D-090 معروضة): التقارير الخمسة قراءات من المرحّل
// حصراً بلا جداول تجميع مخزنة (D-089 معروض — السجل مصدراً D-067)،
// والإقفال حالة الفترة وحدها بحدثَي سجل موثقين (D-090 معروض)، وحاجز
// الإقفال الثالث مُشغِّلات v9 فوق حاجزَي المجال والمحرك (نمط D-067).
// ═══════════════════════════════════════════════════════════════════

/// صف الفترة (المدى والحالة) — حرس قراءة المستندات والإقفال.
Future<(String, String, String)?> _periodRowTx(int periodId) async {
  final rows = await customSelect(
    'SELECT start_date_text, end_date_text, state FROM periods '
    'WHERE id = ? AND is_deleted = 0',
    variables: [Variable.withInt(periodId)],
  ).get();
  if (rows.isEmpty) return null;
  final data = rows.first.data;
  return (
    data['start_date_text'] as String,
    data['end_date_text'] as String,
    data['state'] as String,
  );
}

/// مسودات فترة قائمة بكل المستندات القيدية الخمسة (س-20: «تظهر قائمة
/// المستندات المفتوحة (المسودات) في الفترة لطلب حسمها أولاً») — والمسودة
/// بلا رقم فتلقب «مسودة #المعرف» (الترقيم لحظة الترحيل حصراً — 07 §1.9).
Future<List<PeriodDraftInfo>> periodOpenDrafts(int periodId) async {
  final row = await _periodRowTx(periodId);
  if (row == null) return const <PeriodDraftInfo>[];
  final (startDateText, endDateText, _) = row;
  final rows = await customSelect(
    "SELECT 'move' AS doc_type, id, '' AS number, date_text AS doc_date "
    'FROM moves WHERE is_deleted = 0 AND state = '
    "'draft' AND date_text BETWEEN ?1 AND ?2 "
    'UNION ALL '
    "SELECT 'invoice', id, number, invoice_date FROM invoices "
    "WHERE is_deleted = 0 AND state = 'draft' "
    'AND invoice_date BETWEEN ?1 AND ?2 '
    'UNION ALL '
    "SELECT 'voucher', id, number, voucher_date FROM vouchers "
    "WHERE is_deleted = 0 AND state = 'draft' "
    'AND voucher_date BETWEEN ?1 AND ?2 '
    'UNION ALL '
    "SELECT 'box_transfer', id, number, transfer_date FROM box_transfers "
    "WHERE is_deleted = 0 AND state = 'draft' "
    'AND transfer_date BETWEEN ?1 AND ?2 '
    'UNION ALL '
    "SELECT 'cash_adjustment', id, number, adjustment_date "
    'FROM cash_adjustments '
    "WHERE is_deleted = 0 AND state = 'draft' "
    'AND adjustment_date BETWEEN ?1 AND ?2',
    variables: [
      Variable.withString(startDateText),
      Variable.withString(endDateText),
    ],
  ).get();
  return [
    for (final r in rows)
      PeriodDraftInfo(
        docType: r.data['doc_type'] as String,
        docId: r.data['id'] as int,
        label: (r.data['number'] as String).isEmpty
            ? 'مسودة #${r.data['id']}'
            : r.data['number'] as String,
        dateText: r.data['doc_date'] as String,
      ),
  ];
}

/// إقفال فترة (س-20): مسوداتها تُعرض وتُطلب حسمها بتأكيد صريح — رحّلها
/// أو أكّد تركها معلقة لا تُرحَّل حتى الفك — ثم الحالة «مقفلة» وحدث
/// سجل موثق بلقطة المسودات عند القفل (لا مستندات تُمسّ هنا إطلاقاً:
/// المرحّل مجمد أصلاً — 07 §1.3).
Future<void> closePeriod(int periodId, {required bool draftsConfirmed}) {
  return transaction(() async {
    final row = await _periodRowTx(periodId);
    if (row == null) {
      throw StateError('الفترة $periodId غير موجودة');
    }
    final (startDateText, endDateText, state) = row;
    final drafts = await periodOpenDrafts(periodId);
    final errors = validatePeriodClose(
      periodId: periodId,
      startDateText: startDateText,
      endDateText: endDateText,
      isOpen: state == 'open',
      openDraftsCount: drafts.length,
      draftsConfirmed: draftsConfirmed,
    );
    if (errors.isNotEmpty) {
      throw PeriodClosingException(errors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(periods)..where((t) => t.id.equals(periodId))).write(
      PeriodsCompanion(
        state: const Value('closed'),
        updatedAt: Value(now),
      ),
    );
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: now,
        deviceId: await deviceId(),
        entityType: 'period',
        entityId: Value(periodId),
        action: 'period_closed',
        payload: jsonEncode(<String, Object?>{
          'period_id': periodId,
          'start_date_text': startDateText,
          'end_date_text': endDateText,
          'open_drafts': [
            for (final d in drafts)
              <String, Object?>{
                'doc_type': d.docType,
                'doc_id': d.docId,
                'label': d.label,
                'date_text': d.dateText,
              },
          ],
        }),
        uuid: const Uuid().v4(),
      ),
    );
  });
}

/// فكُّ الإقفال (س-20/س2): طارئ بسبب نصي إلزامي يوثق في السجل بلقطة
/// «لماذا فُتح» — والتقارير التاريخية لا تتأثر إطلاقاً فمصدرها المرحّل
/// المجمد (D-090 معروض: لقطة «كما قُفل» الختامية مع الإقفال السنوي م2).
Future<void> openPeriod(int periodId, {required String reason}) {
  return transaction(() async {
    final row = await _periodRowTx(periodId);
    if (row == null) {
      throw StateError('الفترة $periodId غير موجودة');
    }
    final (startDateText, endDateText, state) = row;
    final errors = validatePeriodOpen(
      periodId: periodId,
      isClosed: state == 'closed',
      reason: reason,
    );
    if (errors.isNotEmpty) {
      throw PeriodClosingException(errors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(periods)..where((t) => t.id.equals(periodId))).write(
      PeriodsCompanion(state: const Value('open'), updatedAt: Value(now)),
    );
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: now,
        deviceId: await deviceId(),
        entityType: 'period',
        entityId: Value(periodId),
        action: 'period_opened',
        payload: jsonEncode(<String, Object?>{
          'period_id': periodId,
          'start_date_text': startDateText,
          'end_date_text': endDateText,
          'reopen_reason': reason,
        }),
        uuid: const Uuid().v4(),
      ),
    );
  });
}

/// ميزان المراجعة من المرحّل حصراً (س-71) — البناء بدالة المجال النقية
/// ذاتها المستعملة بالاختبارات (نمط س-50: التخزين يقرأ ولا يحسب).
Future<TrialBalanceReport> trialBalanceReport() async {
  final lines = [
    for (final line in await postedLedgerLines())
      TrialBalanceRawLine(
        accountId: line.accountId,
        debitMinor: line.debitMinor,
        creditMinor: line.creditMinor,
      ),
  ];
  return buildTrialBalance(lines, await allLedgerAccounts());
}

// ═══ دفعة (13) الروابط التفرعية (س-143..س-147/D-135..D-137) ═══
// قراءات خالصة من جداول القيود القائمة بلا جداول جديدة (D-089 روحاً) —
// وكشف الحساب أول قراءة جديدة من نوعها منذ دفعة التقارير، وضابطه
// التوازن: مجموع الكشف ورصيده النهائي يطابقان صف الحساب في ميزان
// المراجعة حصراً (روح F-068).

/// س-146/D-137: قارئة كشف الحساب من سطور القيود المرحّلة — بترتيب
/// الزمن (تاريخ القيد ثم معرفه)، والرصيد التراكمي باتجاه الحساب
/// الطبيعي بدالة صيغة الميزان ذاتها كي يطابق صف الميزان حرفاً،
/// والحساب الغائب برسالته.
Future<AccountStatementReport> accountStatementReport(int accountId) async {
  final accountRows = await (select(accounts)
        ..where((t) => t.id.equals(accountId)))
      .get();
  if (accountRows.isEmpty) {
    throw StateError('لا حساب بالمعرف $accountId');
  }
  final r0 = accountRows.single;
  final account = AccountInfo(
    id: r0.id,
    code: r0.code,
    name: r0.name,
    type: AccountType.values.byName(r0.type),
    normalSide: NormalSide.values.byName(r0.normalSide),
    parentId: r0.parentId,
    isLeaf: r0.isLeaf,
    isActive: r0.isActive,
  );
  final rows = await customSelect(
    'SELECT m.id AS move_id, m.date_text AS move_date, '
    'm.number AS move_number, m.narration AS narration, '
    'l.debit_minor AS debit_minor, l.credit_minor AS credit_minor '
    'FROM move_lines l JOIN moves m ON m.id = l.move_id '
    "WHERE m.state = 'posted' AND l.account_id = ?1 "
    'ORDER BY m.date_text ASC, m.id ASC',
    variables: [Variable.withInt(accountId)],
  ).get();
  final entries = <AccountStatementEntry>[];
  var debitTotal = 0;
  var creditTotal = 0;
  for (final r in rows) {
    final debit = r.data['debit_minor'] as int;
    final credit = r.data['credit_minor'] as int;
    debitTotal += debit;
    creditTotal += credit;
    final balance = account.normalSide == NormalSide.debit
        ? debitTotal - creditTotal
        : creditTotal - debitTotal;
    entries.add(AccountStatementEntry(
      moveId: r.data['move_id'] as int,
      moveDate: r.data['move_date'] as String,
      moveNumber: r.data['move_number'] as String,
      narration: r.data['narration'] as String?,
      debitMinor: debit,
      creditMinor: credit,
      runningBalanceMinor: balance,
    ));
  }
  final closing = account.normalSide == NormalSide.debit
      ? debitTotal - creditTotal
      : creditTotal - debitTotal;
  return AccountStatementReport(
    account: account,
    entries: entries,
    totalDebitMinor: debitTotal,
    totalCreditMinor: creditTotal,
    closingBalanceMinor: closing,
  );
}

/// س-147: قارئة كشف حساب الطرف من أرجل طرفه على كل الحسابات (الذمم
/// 112/211 وغيرهما إن ظهر طرف على حساب) — بترتيب الزمن، والحساب
/// الغائب برسالته.
Future<PartyStatementReport> partyStatementReport(int partyId) async {
  final partyRows = await (select(parties)
        ..where((t) => t.id.equals(partyId)))
      .get();
  if (partyRows.isEmpty) {
    throw StateError('لا طرف بالمعرف $partyId');
  }
  final partyName = partyRows.single.name;
  final rows = await customSelect(
    'SELECT m.id AS move_id, m.date_text AS move_date, '
    'm.number AS move_number, m.narration AS narration, '
    'a.code AS account_code, '
    'l.debit_minor AS debit_minor, l.credit_minor AS credit_minor '
    'FROM move_lines l '
    'JOIN moves m ON m.id = l.move_id '
    'JOIN accounts a ON a.id = l.account_id '
    "WHERE m.state = 'posted' AND l.party_id = ?1 "
    'ORDER BY m.date_text ASC, m.id ASC',
    variables: [Variable.withInt(partyId)],
  ).get();
  final entries = <PartyStatementEntry>[];
  var debitTotal = 0;
  var creditTotal = 0;
  for (final r in rows) {
    final debit = r.data['debit_minor'] as int;
    final credit = r.data['credit_minor'] as int;
    debitTotal += debit;
    creditTotal += credit;
    entries.add(PartyStatementEntry(
      moveId: r.data['move_id'] as int,
      moveDate: r.data['move_date'] as String,
      moveNumber: r.data['move_number'] as String,
      narration: r.data['narration'] as String?,
      accountCode: r.data['account_code'] as String,
      debitMinor: debit,
      creditMinor: credit,
      runningNetDebitMinor: debitTotal - creditTotal,
    ));
  }
  return PartyStatementReport(
    partyId: partyId,
    partyName: partyName,
    entries: entries,
    totalDebitMinor: debitTotal,
    totalCreditMinor: creditTotal,
    closingNetDebitMinor: debitTotal - creditTotal,
  );
}

/// س-145/D-136: قارئة حركة الصنف الواحد — من stock_moves مع فاتورتها
/// (مرجعها) ومستودعها، بترتيب الورود، والصنف الغائب برسالته.
Future<List<ItemStockMoveRow>> itemStockMovesReport(int itemId) async {
  final itemRows = await (select(items)
        ..where((t) => t.id.equals(itemId)))
      .get();
  if (itemRows.isEmpty) {
    throw StateError('لا صنف بالمعرف $itemId');
  }
  final rows = await customSelect(
    'SELECT sm.id AS move_id, sm.qty_base AS qty_base, '
    'sm.from_warehouse_id AS from_warehouse_id, '
    'sm.to_warehouse_id AS to_warehouse_id, '
    'sm.value_base_minor AS value_base_minor, '
    'sm.ref_doc_type AS ref_doc_type, sm.ref_doc_id AS ref_doc_id, '
    'sm.created_at AS created_at, '
    'wf.name AS from_warehouse, wt.name AS to_warehouse, '
    'inv.number AS invoice_number, inv.kind AS invoice_kind, '
    'inv.invoice_date AS invoice_date '
    'FROM stock_moves sm '
    'LEFT JOIN warehouses wf ON wf.id = sm.from_warehouse_id '
    'LEFT JOIN warehouses wt ON wt.id = sm.to_warehouse_id '
    "LEFT JOIN invoices inv ON sm.ref_doc_type = 'invoice' "
    'AND inv.id = sm.ref_doc_id '
    'WHERE sm.item_id = ?1 '
    'ORDER BY sm.id ASC',
    variables: [Variable.withInt(itemId)],
  ).get();
  return [
    for (final r in rows)
      ItemStockMoveRow(
        moveId: r.data['move_id'] as int,
        isIn: (r.data['qty_base'] as int) > 0,
        qtyBase: (r.data['qty_base'] as int).abs(),
        warehouseName:
            (r.data['to_warehouse'] ?? r.data['from_warehouse']) as String?,
        valueBaseMinor: r.data['value_base_minor'] as int,
        dateText: (r.data['invoice_date'] as String?) ??
            DateTime.fromMillisecondsSinceEpoch(
              r.data['created_at'] as int,
            )
                .toIso8601String()
                .substring(0, 10),
        docLabel: r.data['invoice_number'] == null
            ? null
            : invoiceDisplayLabel(InvoiceDocument(
                id: r.data['ref_doc_id'] as int,
                kind: r.data['invoice_kind'] as String,
                number: r.data['invoice_number'] as String,
                partyId: null,
                cashBoxId: null,
                warehouseId: null,
                invoiceDate: r.data['invoice_date'] as String,
                dueDate: null,
                currencyId: 1,
                fxRate: 1,
                discountRate: 0,
                subtotalDocMinor: 0,
                discountDocMinor: 0,
                totalDocMinor: 0,
                totalBaseMinor: 0,
                state: 'posted',
                moveId: null,
                originalInvoiceId: null,
                narration: null,
              )),
      ),
  ];
}

/// تقرير الصناديق (س-72) — الرصيد بمعادلة الصندوق ذاتها (الافتتاحي +
/// الداخل − الخارج، والتحويل دخلاً للمستلم وخروجاً للمرسل) ونشاط
/// الصندوق نشاط حسابه الورقي (تعطيل الحساب تعطيل للصندوق — 03 §6-3).
Future<List<CashBoxReportRow>> cashBoxesReport() async {
  final rows = await customSelect(
    'SELECT b.id AS box_id, b.name AS name, c.code AS currency_code, '
    'a.code AS account_code, a.is_active AS account_active '
    'FROM cash_boxes b '
    'JOIN currencies c ON c.id = b.currency_id '
    'JOIN accounts a ON a.id = b.account_id '
    'WHERE b.is_deleted = 0 ORDER BY b.id',
  ).get();
  final report = <CashBoxReportRow>[];
  for (final r in rows) {
    report.add(CashBoxReportRow(
      boxId: r.data['box_id'] as int,
      name: r.data['name'] as String,
      currencyCode: r.data['currency_code'] as String,
      accountCode: r.data['account_code'] as String,
      balanceBaseMinor: await _cashBoxBalanceTx(r.data['box_id'] as int),
      isActive: (r.data['account_active'] as int) == 1,
    ));
  }
  return report;
}

/// تقرير الذمم (س-73) — صافي كل طرف على حسابَي السيطرة (112/211) من
/// المرحّل حصراً، والاتجاهان (هم يدينون/نحن مدينون) بالمجال (05 §5).
Future<List<ReceivablesPayablesRow>> receivablesPayablesReport() async {
  final rows = await customSelect(
    'SELECT ml.party_id AS party_id, p.name AS party_name, '
    'SUM(ml.debit_minor) - SUM(ml.credit_minor) AS net_debit '
    'FROM move_lines ml '
    'JOIN moves m ON m.id = ml.move_id '
    'JOIN parties p ON p.id = ml.party_id '
    'JOIN accounts a ON a.id = ml.account_id '
    "WHERE m.state = 'posted' AND ml.party_id IS NOT NULL "
    "AND a.code IN ('112', '211') "
    'GROUP BY ml.party_id ORDER BY p.name',
  ).get();
  return buildReceivablesPayables([
    for (final r in rows)
      PartyControlRaw(
        partyId: r.data['party_id'] as int,
        partyName: r.data['party_name'] as String,
        netDebitMinor: r.data['net_debit'] as int,
      ),
  ]);
}

/// تقرير المخزون (س-74) — من stock_balances مباشرة (السجل مصدراً
/// D-067) والمتوسط عرضاً حصراً بالمجال (رسة النصف بعيداً عن الصفر).
Future<List<InventoryReportRow>> inventoryReport() async {
  final rows = await customSelect(
    'SELECT sb.item_id AS item_id, i.sku AS sku, i.name AS name, '
    'w.name AS warehouse_name, sb.qty_base AS qty_base, '
    'sb.total_value_minor AS total_value '
    'FROM stock_balances sb '
    'JOIN items i ON i.id = sb.item_id '
    'LEFT JOIN warehouses w ON w.id = sb.warehouse_id '
    'WHERE sb.qty_base <> 0 OR sb.total_value_minor <> 0 '
    'ORDER BY i.sku',
  ).get();
  return buildInventoryReport([
    for (final r in rows)
      InventoryRawRow(
        itemId: r.data['item_id'] as int,
        sku: r.data['sku'] as String,
        name: r.data['name'] as String,
        warehouseName: r.data['warehouse_name'] as String?,
        qtyBase: r.data['qty_base'] as int,
        totalValueMinor: r.data['total_value'] as int,
      ),
  ]);
}

/// تقرير مبيعات وحركة الأصناف (س-75) — بيع ومردود بيع مرحّلان بمدى
/// تاريخ، والقيم بالأساسية من سطور الفواتير المخزنة (D-089 معروض:
/// حركة الشراء ظاهرة في المخزون والميزان، وتقرير المشتريات المستقل
/// مع واجهات التقارير).
Future<List<SalesMovementRow>> salesMovementReport({
  required String fromText,
  required String toText,
}) async {
  final errors = validateReportRange(fromText, toText);
  if (errors.isNotEmpty) {
    throw ReportValidationException(errors);
  }
  final rows = await customSelect(
    'SELECT il.item_id AS item_id, i.sku AS sku, i.name AS name, '
    "SUM(CASE WHEN inv.kind = 'sale' "
    'THEN il.qty_base ELSE 0 END) AS qty_sold, '
    "SUM(CASE WHEN inv.kind = 'sale' "
    'THEN il.line_total_base_minor ELSE 0 END) AS sales_value, '
    "SUM(CASE WHEN inv.kind = 'sale_return' "
    'THEN il.qty_base ELSE 0 END) AS qty_returned, '
    "SUM(CASE WHEN inv.kind = 'sale_return' "
    'THEN il.line_total_base_minor ELSE 0 END) AS returns_value '
    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'JOIN items i ON i.id = il.item_id '
    "WHERE inv.state <> 'draft' AND inv.is_deleted = 0 "
    'AND il.is_deleted = 0 '
    'AND inv.invoice_date >= ?1 AND inv.invoice_date <= ?2 '
    'GROUP BY il.item_id ORDER BY i.sku',
    variables: [
      Variable.withString(fromText),
      Variable.withString(toText),
    ],
  ).get();
  return buildSalesMovementReport([
    for (final r in rows)
      SalesMovementRawRow(
        itemId: r.data['item_id'] as int,
        sku: r.data['sku'] as String,
        name: r.data['name'] as String,
        qtySoldBase: r.data['qty_sold'] as int,
        salesValueBaseMinor: r.data['sales_value'] as int,
        qtyReturnedBase: r.data['qty_returned'] as int,
        returnsValueBaseMinor: r.data['returns_value'] as int,
      ),
  ]);
}

/// تقرير المشتريات المستقل (س-84، دفعة 6-ب) — شراء ومردود شراء مرحّلان
/// بمدى تاريخ تنفيذاً لوعد D-089 «تقرير المشتريات المستقل مع واجهات
/// التقارير» — بمرآة salesMovementReport ذاتها وبفلتر قيم **التخزين**
/// `purchase`/`purchase_return` لا قيم التسلسل (درس «قيمتان لنوع واحد»
/// س34)، ومدقق المدى حرسها الأول.
Future<List<PurchasesMovementRow>> purchasesMovementReport({
  required String fromText,
  required String toText,
}) async {
  final errors = validateReportRange(fromText, toText);
  if (errors.isNotEmpty) {
    throw ReportValidationException(errors);
  }
  final rows = await customSelect(
    'SELECT il.item_id AS item_id, i.sku AS sku, i.name AS name, '
    "SUM(CASE WHEN inv.kind = 'purchase' "
    'THEN il.qty_base ELSE 0 END) AS qty_purchased, '
    "SUM(CASE WHEN inv.kind = 'purchase' "
    'THEN il.line_total_base_minor ELSE 0 END) AS purchases_value, '
    "SUM(CASE WHEN inv.kind = 'purchase_return' "
    'THEN il.qty_base ELSE 0 END) AS qty_returned, '
    "SUM(CASE WHEN inv.kind = 'purchase_return' "
    'THEN il.line_total_base_minor ELSE 0 END) AS returns_value '
    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'JOIN items i ON i.id = il.item_id '
    "WHERE inv.state <> 'draft' AND inv.is_deleted = 0 "
    'AND il.is_deleted = 0 '
    'AND inv.invoice_date >= ?1 AND inv.invoice_date <= ?2 '
    'GROUP BY il.item_id ORDER BY i.sku',
    variables: [
      Variable.withString(fromText),
      Variable.withString(toText),
    ],
  ).get();
  return buildPurchasesMovementReport([
    for (final r in rows)
      PurchasesMovementRawRow(
        itemId: r.data['item_id'] as int,
        sku: r.data['sku'] as String,
        name: r.data['name'] as String,
        qtyPurchasedBase: r.data['qty_purchased'] as int,
        purchasesValueBaseMinor: r.data['purchases_value'] as int,
        qtyReturnedBase: r.data['qty_returned'] as int,
        returnsValueBaseMinor: r.data['returns_value'] as int,
      ),
  ]);
}

// ═══ قراءات قوائم المستندات — دفعة (6-ج) واجهات الإدخال (س-86..س-94،
// D-094..D-097 معروضة): قراءات عرض خالصة من المرحّل حصراً على نمط
// قراءات دفعة (6) الموثقة (D-088/D-089) — لا جداول تجميع ولا أعمدة
// جديدة، والمدى الاختياري يُدقق بمدقق التقارير ذاته قبل لمس القاعدة
// (D-077)، والفراغ يعطي القائمة كاملة لا صمتاً (F-162 روحاً). الصياغة
// العرضية (تسميات الأنواع والحالات) بدوال المجال الجاهزة — التخزين
// يقرأ ولا يحسب (نمط س-50).

/// المستودعات القائمة للنماذج (05 §3.3) — المستودع الواحد في م1
/// والبنية تعددية من م0. قراءة عرض خالصة.
Future<List<WarehouseRow>> warehousesOf() async {
  final rows = await customSelect(
    'SELECT id, name, is_active FROM warehouses '
    'WHERE is_deleted = 0 ORDER BY id',
  ).get();
  return [
    for (final r in rows)
      WarehouseRow(
        id: r.data['id'] as int,
        name: r.data['name'] as String,
        isActive: (r.data['is_active'] as int) == 1,
      ),
  ];
}

/// صف قائمة فواتير للعرض (05 §4.1) — للتصفح لا للقرار.
Future<List<InvoiceListRow>> invoicesListReport({
  String? fromText,
  String? toText,
  String? kindStorageValue,

  /// س-147 (دفعة 13): فلتر الطرف الاختياري — روابط الطرف من الذمم
  /// تفتح «فواتيره» بهذا الفلتر، وعرضٌ فوق القراءة لا حساب جديد.
  int? partyId,
}) async {
  final from = fromText?.trim() ?? '';
  final to = toText?.trim() ?? '';
  if (from.isNotEmpty || to.isNotEmpty) {
    final errors = validateReportRange(from, to);
    if (errors.isNotEmpty) {
      throw ReportValidationException(errors);
    }
  }
  final kind = kindStorageValue?.trim() ?? '';
  final rows = await customSelect(
    'SELECT inv.id AS id, inv.kind AS kind, inv.number AS number, '
    'inv.invoice_date AS invoice_date, inv.state AS state, '
    'inv.total_doc_minor AS total_doc_minor, '
    'inv.total_base_minor AS total_base_minor, '
    'c.code AS currency_code, p.name AS party_name, b.name AS box_name '
    'FROM invoices inv '
    'JOIN currencies c ON c.id = inv.currency_id '
    'LEFT JOIN parties p ON p.id = inv.party_id '
    'LEFT JOIN cash_boxes b ON b.id = inv.cash_box_id '
    "WHERE inv.is_deleted = 0 "
    "AND (?1 = '' OR inv.kind = ?1) "
    "AND (?2 = '' OR inv.invoice_date >= ?2) "
    "AND (?3 = '' OR inv.invoice_date <= ?3) "
    'AND (?4 IS NULL OR inv.party_id = ?4) '
    'ORDER BY inv.invoice_date DESC, inv.id DESC',
    variables: [
      Variable.withString(kind),
      Variable.withString(from),
      Variable.withString(to),
      Variable(partyId),
    ],
  ).get();
  return [
    for (final r in rows)
      InvoiceListRow(
        id: r.data['id'] as int,
        kind: r.data['kind'] as String,
        number: r.data['number'] as String,
        invoiceDate: r.data['invoice_date'] as String,
        state: r.data['state'] as String,
        totalDocMinor: r.data['total_doc_minor'] as int,
        totalBaseMinor: r.data['total_base_minor'] as int,
        currencyCode: r.data['currency_code'] as String,
        partyName: r.data['party_name'] as String?,
        boxName: r.data['box_name'] as String?,
      ),
  ];
}

/// صف قائمة سندات القبض والدفع للعرض (05 §4.2/D-105) — الطرفي وغير الطرفي
/// معاً والمميزان بحقليهما (طرف أو حساب مباشر).
///
/// س-147 (D-135 روحاً، دفعة 13): فلتر الطرف الاختياري — روابط الطرف
/// من الذمم تفتح «سنداته» بهذا الفلتر، وعرضٌ فوق القراءة لا حساب جديد.
Future<List<VoucherListRow>> vouchersListReport({
  String? fromText,
  String? toText,
  int? partyId,
}) async {
  final from = fromText?.trim() ?? '';
  final to = toText?.trim() ?? '';
  if (from.isNotEmpty || to.isNotEmpty) {
    final errors = validateReportRange(from, to);
    if (errors.isNotEmpty) {
      throw ReportValidationException(errors);
    }
  }
  final rows = await customSelect(
    'SELECT v.id AS id, v.kind AS kind, v.number AS number, '
    'v.voucher_date AS voucher_date, v.state AS state, '
    'v.amount_doc_minor AS amount_doc_minor, '
    'v.amount_base_minor AS amount_base_minor, v.narration AS narration, '
    'c.code AS currency_code, p.name AS party_name, '
    'a.code AS direct_account_code, b.name AS box_name '
    'FROM vouchers v '
    'JOIN currencies c ON c.id = v.currency_id '
    'LEFT JOIN parties p ON p.id = v.party_id '
    'LEFT JOIN accounts a ON a.id = v.direct_account_id '
    'JOIN cash_boxes b ON b.id = v.cash_box_id '
    "WHERE v.is_deleted = 0 "
    "AND (?1 = '' OR v.voucher_date >= ?1) "
    "AND (?2 = '' OR v.voucher_date <= ?2) "
    'AND (?3 IS NULL OR v.party_id = ?3) '
    'ORDER BY v.voucher_date DESC, v.id DESC',
    variables: [
      Variable.withString(from),
      Variable.withString(to),
      Variable(partyId),
    ],
  ).get();
  return [
    for (final r in rows)
      VoucherListRow(
        id: r.data['id'] as int,
        kind: r.data['kind'] as String,
        number: r.data['number'] as String,
        voucherDate: r.data['voucher_date'] as String,
        state: r.data['state'] as String,
        amountDocMinor: r.data['amount_doc_minor'] as int,
        narration: r.data['narration'] as String?,
        currencyCode: r.data['currency_code'] as String,
        partyName: r.data['party_name'] as String?,
        directAccountCode: r.data['direct_account_code'] as String?,
        boxName: r.data['box_name'] as String,
      ),
  ];
}

/// صف قائمة تحويلات الصناديق للعرض (س-16/05 §6) — المستند موحد بطرفه
/// (من/إلى) والمبلغ بعملة الصندوقين (الواحدة — D-087 معتمد).
Future<List<BoxTransferListRow>> boxTransfersListReport({
  String? fromText,
  String? toText,
}) async {
  final from = fromText?.trim() ?? '';
  final to = toText?.trim() ?? '';
  if (from.isNotEmpty || to.isNotEmpty) {
    final errors = validateReportRange(from, to);
    if (errors.isNotEmpty) {
      throw ReportValidationException(errors);
    }
  }
  final rows = await customSelect(
    'SELECT t.id AS id, t.number AS number, '
    't.transfer_date AS transfer_date, t.state AS state, '
    't.amount_doc_minor AS amount_doc_minor, t.narration AS narration, '
    'c.code AS currency_code, '
    'f.name AS from_box_name, u.name AS to_box_name '
    'FROM box_transfers t '
    'JOIN currencies c ON c.id = t.currency_id '
    'JOIN cash_boxes f ON f.id = t.from_box_id '
    'JOIN cash_boxes u ON u.id = t.to_box_id '
    "WHERE t.is_deleted = 0 "
    "AND (?1 = '' OR t.transfer_date >= ?1) "
    "AND (?2 = '' OR t.transfer_date <= ?2) "
    'ORDER BY t.transfer_date DESC, t.id DESC',
    variables: [
      Variable.withString(from),
      Variable.withString(to),
    ],
  ).get();
  return [
    for (final r in rows)
      BoxTransferListRow(
        id: r.data['id'] as int,
        number: r.data['number'] as String,
        transferDate: r.data['transfer_date'] as String,
        state: r.data['state'] as String,
        amountDocMinor: r.data['amount_doc_minor'] as int,
        narration: r.data['narration'] as String?,
        currencyCode: r.data['currency_code'] as String,
        fromBoxName: r.data['from_box_name'] as String,
        toBoxName: r.data['to_box_name'] as String,
      ),
  ];
}

/// صف قائمة تسويات الصناديق للعرض (س-17) — الاتجاه والسبب النصي
/// الإلزامي ظاهران بالصفحة فتُرى مسوغة كل فرق.
Future<List<CashAdjustmentListRow>> cashAdjustmentsListReport({
  String? fromText,
  String? toText,
}) async {
  final from = fromText?.trim() ?? '';
  final to = toText?.trim() ?? '';
  if (from.isNotEmpty || to.isNotEmpty) {
    final errors = validateReportRange(from, to);
    if (errors.isNotEmpty) {
      throw ReportValidationException(errors);
    }
  }
  final rows = await customSelect(
    'SELECT s.id AS id, s.number AS number, '
    's.adjustment_date AS adjustment_date, s.direction AS direction, '
    's.state AS state, s.reason AS reason, '
    's.amount_doc_minor AS amount_doc_minor, '
    'c.code AS currency_code, b.name AS box_name '
    'FROM cash_adjustments s '
    'JOIN currencies c ON c.id = s.currency_id '
    'JOIN cash_boxes b ON b.id = s.cash_box_id '
    "WHERE s.is_deleted = 0 "
    "AND (?1 = '' OR s.adjustment_date >= ?1) "
    "AND (?2 = '' OR s.adjustment_date <= ?2) "
    'ORDER BY s.adjustment_date DESC, s.id DESC',
    variables: [
      Variable.withString(from),
      Variable.withString(to),
    ],
  ).get();
  return [
    for (final r in rows)
      CashAdjustmentListRow(
        id: r.data['id'] as int,
        number: r.data['number'] as String,
        adjustmentDate: r.data['adjustment_date'] as String,
        direction: r.data['direction'] as String,
        state: r.data['state'] as String,
        reason: r.data['reason'] as String,
        amountDocMinor: r.data['amount_doc_minor'] as int,
        currencyCode: r.data['currency_code'] as String,
        boxName: r.data['box_name'] as String,
      ),
  ];
}

Future<void> _createClosingTriggers() async {
  // ═══ حواجز الإقفال الثالثة (دفعة 6 — ترحيلة v9): المجال يفحص فترة
  // التاريخ (MoveClosedPeriod وأخواتها الأربع) والمحرك يمنع قبل أي كتابة
  // والقاعدة تحبط أي إدراج أو ترحيل خام في فترة مقفلة — الحاجز الثالث
  // على نمط D-067 (07 §2.2). DROP+CREATE فإعادة التعريف موثقة آمنة
  // التكرار (نمط توسعة حاجز سالب الصندوق س33). والمستندات القيدية
  // الخمسة بأعمدة تواريخها، والفواتير بحالتَيها المحسومتين posted/paid
  // (النقدية غير المردودة «paid» فوراً — دفعة 4).
  const docTables = <(String, String, String)>[
    ('moves', 'date_text', "'posted'"),
    ('invoices', 'invoice_date', "'posted', 'paid'"),
    ('vouchers', 'voucher_date', "'posted'"),
    ('box_transfers', 'transfer_date', "'posted'"),
    ('cash_adjustments', 'adjustment_date', "'posted'"),
  ];
  for (final (table, dateColumn, committedStates) in docTables) {
    final periodClosed = '(SELECT p.state FROM periods p '
        'WHERE p.is_deleted = 0 '
        'AND p.start_date_text <= NEW.$dateColumn '
        'AND p.end_date_text >= NEW.$dateColumn LIMIT 1) = '
        "'closed'";
    await customStatement(
        'DROP TRIGGER IF EXISTS trg_${table}_closed_period_insert');
    await customStatement(
        'DROP TRIGGER IF EXISTS trg_${table}_closed_period_post');
    await customStatement(
      'CREATE TRIGGER trg_${table}_closed_period_insert '
      'BEFORE INSERT ON $table FOR EACH ROW '
      "WHEN NEW.state IN ($committedStates) AND $periodClosed "
      "BEGIN SELECT RAISE(ABORT, 'فترة مقفلة: لا ترحيل فيها "
      "(حاجز القاعدة)'); END",
    );
    await customStatement(
      'CREATE TRIGGER trg_${table}_closed_period_post '
      'BEFORE UPDATE OF state ON $table FOR EACH ROW '
      "WHEN NEW.state IN ($committedStates) "
      'AND OLD.state NOT IN ($committedStates) AND $periodClosed '
      "BEGIN SELECT RAISE(ABORT, 'فترة مقفلة: لا ترحيل فيها "
      "(حاجز القاعدة)'); END",
    );
  }
}
}

/// رفض مدقق الدفتر — يحمل الأخطاء النوعية المحمولة (نمط الأطراف: أنواع
/// بيانات لا نصوص جاهزة) وأوصافها العربية تخدم صفوف فشل التنفيذ حصراً؛
/// الواجهة حرية صياغتها المعروضة.
/// صف شاشة «متابعة التسليم» (س-139/D-133) — كل سطر بيع غير مستلم
/// بفاتورته وتاريخه وطرفه ومورده، الأقدم أولاً.
class UndeliveredLineRow {
  final int lineId;
  final int invoiceId;
  final String invoiceKind;
  final String invoiceNumber;
  final String invoiceDate;
  final int itemId;
  final String itemSku;
  final String itemName;
  final int qtyBase;
  final String? partyName;
  final int? supplierPartyId;
  final String? supplierName;

  const UndeliveredLineRow({
    required this.lineId,
    required this.invoiceId,
    required this.invoiceKind,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.itemId,
    required this.itemSku,
    required this.itemName,
    required this.qtyBase,
    required this.partyName,
    required this.supplierPartyId,
    required this.supplierName,
  });
}

/// سطر في كشف الحساب (س-146/D-137) — قيدٌ بتاريخه ورقمه وبيانه
/// ومدينه ودائنه والرصيد التراكمي بعده.
class AccountStatementEntry {
  final int moveId;
  final String moveDate;
  final String moveNumber;
  final String? narration;
  final int debitMinor;
  final int creditMinor;

  /// الرصيد التراكمي بعد القيد باتجاه الحساب الطبيعي (نمط الميزان:
  /// موجب على جانبه الطبيعي وسالب على المعاكس — لا يُقلب خفية).
  final int runningBalanceMinor;

  const AccountStatementEntry({
    required this.moveId,
    required this.moveDate,
    required this.moveNumber,
    required this.narration,
    required this.debitMinor,
    required this.creditMinor,
    required this.runningBalanceMinor,
  });
}

/// كشف الحساب كاملاً (س-146/D-137) — «دفتر الأستاذ» المعروف: كل قيود
/// الحساب بترتيب الزمن، والمجاميع والرصيد النهائي يطابقان صف الحساب
/// في ميزان المراجعة حصراً.
class AccountStatementReport {
  final AccountInfo account;
  final List<AccountStatementEntry> entries;
  final int totalDebitMinor;
  final int totalCreditMinor;
  final int closingBalanceMinor;

  const AccountStatementReport({
    required this.account,
    required this.entries,
    required this.totalDebitMinor,
    required this.totalCreditMinor,
    required this.closingBalanceMinor,
  });
}

/// سطر في كشف حساب الطرف (س-147) — قيدٌ على طرف بذمّته.
class PartyStatementEntry {
  final int moveId;
  final String moveDate;
  final String moveNumber;
  final String? narration;
  final String accountCode;
  final int debitMinor;
  final int creditMinor;

  /// الصافي التراكمي بعد القيد: موجب «هم يدينون لنا» وسالب «نحن
  /// مدينون لهم» — بصيغة الذمم ذاتها (مدين − دائن).
  final int runningNetDebitMinor;

  const PartyStatementEntry({
    required this.moveId,
    required this.moveDate,
    required this.moveNumber,
    required this.narration,
    required this.accountCode,
    required this.debitMinor,
    required this.creditMinor,
    required this.runningNetDebitMinor,
  });
}

/// كشف حساب الطرف كاملاً (س-147) — ضابطه: صافيه النهائي يطابق صف
/// الطرف في تقرير الذمم حصراً (مدين − دائن على أرجل طرفه).
class PartyStatementReport {
  final int partyId;
  final String partyName;
  final List<PartyStatementEntry> entries;
  final int totalDebitMinor;
  final int totalCreditMinor;
  final int closingNetDebitMinor;

  const PartyStatementReport({
    required this.partyId,
    required this.partyName,
    required this.entries,
    required this.totalDebitMinor,
    required this.totalCreditMinor,
    required this.closingNetDebitMinor,
  });
}

/// حركة الصنف الواحد (س-145/D-136) — لقطات مخزونه من سجل الحركات
/// حصراً بفاتورتها وتاريخها، بترتيب الورود (لقطات لا تعدل — F-140).
class ItemStockMoveRow {
  final int moveId;
  final bool isIn;
  final int qtyBase;
  final String? warehouseName;
  final int valueBaseMinor;
  final String dateText;
  final String? docLabel;

  const ItemStockMoveRow({
    required this.moveId,
    required this.isIn,
    required this.qtyBase,
    required this.warehouseName,
    required this.valueBaseMinor,
    required this.dateText,
    required this.docLabel,
  });
}

class LedgerValidationException implements Exception {
  final List<MoveValidationError> errors;

  const LedgerValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق الدفتر: ${errors.map(describeMoveValidationError).join('؛ ')}';
}

// ═══════════════════════════════════════════════════════════════════
// دفعة الفواتير — دفعة م1 الرابعة (س-51..س-60، D-079..D-082 معروضة):
// جداول v7 تُدار SQL خاماً بنمط المُشغِّلات المجرَّب (D-079) — بلا كود
// مولد: إدراجات صريحة آمنة التكرار، وحواجز القاعدة ثانية بعد فحص
// المحرك (07 §2.2 نمط D-067)، والبذر فاحص الفراغ ذاته.
// ═══════════════════════════════════════════════════════════════════

/// صورة عملة قائمة (05 §3.5/F-120/D-070).
class CurrencyRow {
  final int id;
  final String code;
  final String name;
  final int minorUnits;
  final bool isBase;

  const CurrencyRow({
    required this.id,
    required this.code,
    required this.name,
    required this.minorUnits,
    required this.isBase,
  });
}

/// صورة مستودع (05 §3.3) — المستودع الواحد في م1 ببنية تعددية.
class WarehouseRow {
  final int id;
  final String name;
  final bool isActive;

  const WarehouseRow({
    required this.id,
    required this.name,
    required this.isActive,
  });
}

/// صورة صندوق نقدي (05 §3.3) — كل صندوق عملته واحدة، وحسابه الورقي
/// تحت 111 (03 §3: الصندوق الرئيسي 1111 وكل صندوق جديد حسابه 111x).
/// `account_id` إضافة تنفيذية لقاعدة 03 نفسها («يُنشأ معه حساب ورقي لكل
/// صندوق») — 05 §3.3 يعدد الحقول الجوهرية لا الحصرية (D-079 معروض).
class CashBoxRow {
  final int id;
  final String name;
  final int currencyId;
  final int accountId;
  final int openingBalanceBaseMinor;

  const CashBoxRow({
    required this.id,
    required this.name,
    required this.currencyId,
    required this.accountId,
    required this.openingBalanceBaseMinor,
  });
}

/// صورة فاتورة قائمة (05 §4.1) — للقراءة والتوثيق لا للقرار.
class InvoiceDocument {
  final int id;
  final String kind;
  final String number;
  final int? partyId;
  final int? cashBoxId;
  final int? warehouseId;
  final String invoiceDate;
  final String? dueDate;
  final int currencyId;
  final int fxRate;
  final int discountRate;
  final int subtotalDocMinor;
  final int discountDocMinor;
  final int totalDocMinor;
  final int totalBaseMinor;
  final String state;
  final int? moveId;
  final int? originalInvoiceId;
  final String? narration;

  const InvoiceDocument({
    required this.id,
    required this.kind,
    required this.number,
    required this.partyId,
    required this.cashBoxId,
    required this.warehouseId,
    required this.invoiceDate,
    required this.dueDate,
    required this.currencyId,
    required this.fxRate,
    required this.discountRate,
    required this.subtotalDocMinor,
    required this.discountDocMinor,
    required this.totalDocMinor,
    required this.totalBaseMinor,
    required this.state,
    required this.moveId,
    required this.originalInvoiceId,
    required this.narration,
  });

  bool get isCommitted =>
      state == 'posted' || state == 'paid' || state == 'partially_paid';
}

/// صورة سطر فاتورة قائمة (05 §4.1) — مع مكافئه التوثيقي بعملة المستند
/// (F-122/D-082: `line_total_doc_minor` بجانب `line_total_base_minor`).
/// v13 (دفعة 12/D-131/D-132): مع علم التسليم والمورد المسؤول —
/// علم عمل لا محاسبة يُحدّث على المرحّلة (الحرس يسمح بهذين حصراً).
class InvoiceLineDocument {
  final int id;
  final int invoiceId;
  final int itemId;
  final int unitId;
  final int factorAtEntry;
  final int qty;
  final int qtyBase;
  final int unitPriceMinor;
  final int discountMinor;
  final int taxRate;
  final int lineTotalDocMinor;
  final int lineTotalBaseMinor;
  final String uuid;

  /// س-137/D-131: مربع «مستلم» — غير محدد افتراضاً لكل سطر جديد،
  /// والتحديد يُحفظ فوراً بقاعدة البيانات.
  final bool delivered;

  /// س-138/D-132: المورد المسؤول — اختيار يدوي مع اقتراح من آخر
  /// شراء مرحّل، ويُخزّن على السطر فيظهر بشاشة المتابعة وحده.
  final int? supplierPartyId;

  const InvoiceLineDocument({
    required this.id,
    required this.invoiceId,
    required this.itemId,
    required this.unitId,
    required this.factorAtEntry,
    required this.qty,
    required this.qtyBase,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.taxRate,
    required this.lineTotalDocMinor,
    required this.lineTotalBaseMinor,
    required this.uuid,
    this.delivered = false,
    this.supplierPartyId,
  });
}

// ─── محرك الفواتير: القراءة الداخلية والتحقق والتخطيط والترحيل ───

/// قيمة مخزون محاكاة داخل التخطيط — تُقرأ مرة وتتطور بكل سطر على حدة
/// فتطابق الكتابة المتسلسلة حرفاً (تكلفة الخروج بالترتيب — D-067).
class _StockSim {
  /// قارئ رصيد الصنف — يمرر من محرك الفواتير (نسخ دالة عضو الفئة) كي
  /// يبقى الصنف أعلى المستوى بلا اعتماد على مثال القاعدة.
  final Future<(int, int)> Function(int itemId, int warehouseId) readBalance;
  final int warehouseId;
  final Map<int, (int, int)> _byItem = {};

  _StockSim(this.readBalance, this.warehouseId);

  Future<(int, int)> of(int itemId) async {
    final existing = _byItem[itemId];
    if (existing != null) return existing;
    final balance = await readBalance(itemId, warehouseId);
    _byItem[itemId] = balance;
    return balance;
  }

  void apply(int itemId, int qtyDelta, int valueDelta) {
    final current = _byItem[itemId] ?? (0, 0);
    _byItem[itemId] = (current.$1 + qtyDelta, current.$2 + valueDelta);
  }
}

/// خطة سطر مخزني داخل فاتورة — قيمه محسوبة مقدماً فالكتابة تكرر
/// المحاكاة حرفاً ولا تعيد الحساب (لا فجوة بين الفحص والتنفيذ).
class _StockLinePlan {
  final int lineIndex;
  final int itemId;
  final int qtyBase;

  /// قيمة حركة المخزون ودلتا الرصيد القيمية: دخول الشراء صافي السطر،
  /// خروج البيع تكلفته المحمولة، دخول مردود البيع لقطة الأصل (م-25)،
  /// خروج مردود الشراء القيمة الدفترية الجارية (D-067).
  final int stockValueMinor;

  /// نظير سطر التكلفة 51: تكلفة البيع أو المتوسط الجاري للمردود —
  /// والفرق بينه وبين [stockValueMinor] يجمع على 58 فروق التكلفة.
  final int counterpartMinor;

  const _StockLinePlan({
    required this.lineIndex,
    required this.itemId,
    required this.qtyBase,
    required this.stockValueMinor,
    required this.counterpartMinor,
  });
}

/// الصيغة المعروضة لرقم الفاتورة (م-44/D-071): «فاتورة بيع 2026/000001».
String invoiceDisplayLabel(InvoiceDocument invoice) {
  final kind = InvoiceKind.fromStorage(invoice.kind);
  final label =
      sequenceKindLabels[invoiceSequenceKind(kind)] ?? kind.label;
  return '$label ${invoice.number}';
}

// ═══════════════════════════════════════════════════════════════════
// دفعة السندات والصندوق — دفعة م1 الخامسة (س-61..س-70، D-083..D-087
// معروضة): جداول v8 الأربعة تُدار SQL خاماً بنمط D-079 المجرَّب — بلا
// كود مولد: إدراجات صريحة آمنة التكرار، وحواجز القاعدة ثانية بعد فحص
// المحرك (07 §2.2 نمط D-067) بما فيها توسعة حاجز سالب الصندوق للخروج
// بالتحويل، والبذر فاحص الحالة ذاته.
// ═══════════════════════════════════════════════════════════════════

/// صورة سند قائم للقراءة (05 §4.2) — للقراءة والتوثيق لا للقرار.
class VoucherDocument {
  final int id;
  final String kind;
  final String number;
  final int? partyId;

  /// الحساب المباشر للسند بغير طرف (س-13/س-15).
  final int? directAccountId;
  final int cashBoxId;
  final String voucherDate;
  final int currencyId;
  final int fxRate;
  final int amountDocMinor;
  final int amountBaseMinor;
  final String state;
  final int? moveId;
  final String? narration;

  const VoucherDocument({
    required this.id,
    required this.kind,
    required this.number,
    required this.partyId,
    required this.directAccountId,
    required this.cashBoxId,
    required this.voucherDate,
    required this.currencyId,
    required this.fxRate,
    required this.amountDocMinor,
    required this.amountBaseMinor,
    required this.state,
    required this.moveId,
    required this.narration,
  });
}

/// صورة صف مطابقة قائم (05 §4.2 + D-084 معروض): المطبَّق بعملة الفاتورة
/// وبلقطة الفاتورة فتصفو الذمة حرفاً.
class VoucherAllocationDocument {
  final int id;
  final int voucherId;
  final int invoiceId;
  final int appliedDocMinor;
  final int appliedBaseMinor;

  const VoucherAllocationDocument({
    required this.id,
    required this.voucherId,
    required this.invoiceId,
    required this.appliedDocMinor,
    required this.appliedBaseMinor,
  });
}

/// الصيغة المعروضة لرقم السند (م-44/D-071): «سند قبض 2026/000001».
String voucherDisplayLabel(VoucherDocument voucher) {
  final kind = VoucherKind.fromStorage(voucher.kind);
  final label =
      sequenceKindLabels[voucherSequenceKind(kind)] ?? kind.label;
  return '$label ${voucher.number}';
}

// ═══ صفوف قوائم المستندات — دفعة (6-ج): صور عرض للتصفح لا للقرار،
// والتسميات من دوال المجال الجاهزة حصراً (لا صياغة مخزنة — D-089).

/// صف قائمة فواتير للتصفح (05 §4.1).
class InvoiceListRow {
  final int id;
  final String kind;

  /// فارغ للمسودة — الترقيم لحظة الترحيل حصراً (07 §1.9).
  final String number;
  final String invoiceDate;
  final String state;
  final int totalDocMinor;
  final int totalBaseMinor;
  final String currencyCode;

  /// الطرف للآجل واسم صندوق النقدية للنقدي — أحدهما فأعلى.
  final String? partyName;
  final String? boxName;

  const InvoiceListRow({
    required this.id,
    required this.kind,
    required this.number,
    required this.invoiceDate,
    required this.state,
    required this.totalDocMinor,
    required this.totalBaseMinor,
    required this.currencyCode,
    required this.partyName,
    required this.boxName,
  });

  /// «فاتورة بيع 2026/000001» — والمسودة بلا رقم بعد فتسميتها «— مسودة».
  String get displayLabel {
    final k = InvoiceKind.fromStorage(kind);
    final kindLabel =
        sequenceKindLabels[invoiceSequenceKind(k)] ?? k.label;
    return number.isEmpty ? '$kindLabel — مسودة' : '$kindLabel $number';
  }

  String get stateLabel => InvoiceState.fromStorage(state).label;

  InvoiceKind get kindValue => InvoiceKind.fromStorage(kind);

  /// الطرف أو الصندوق بالعرض — الآجل طرفاً والنقدي صندوقاً (س-03/س-06).
  String get counterpartLabel =>
      partyName ?? boxName ?? '—';
}

/// صف قائمة سندات القبض والدفع للتصفح (05 §4.2/D-105).
class VoucherListRow {
  final int id;
  final String kind;
  final String number;
  final String voucherDate;
  final String state;
  final int amountDocMinor;
  final String? narration;
  final String currencyCode;

  /// طرف السند الطرفي — وحسابه المباشر لغير الطرفي (س-13/س-15).
  final String? partyName;
  final String? directAccountCode;
  final String boxName;

  const VoucherListRow({
    required this.id,
    required this.kind,
    required this.number,
    required this.voucherDate,
    required this.state,
    required this.amountDocMinor,
    required this.narration,
    required this.currencyCode,
    required this.partyName,
    required this.directAccountCode,
    required this.boxName,
  });

  String get displayLabel {
    final k = VoucherKind.fromStorage(kind);
    final kindLabel =
        sequenceKindLabels[voucherSequenceKind(k)] ?? k.label;
    return number.isEmpty ? '$kindLabel — مسودة' : '$kindLabel $number';
  }

  String get stateLabel =>
      state == 'posted' ? 'مرحّل' : 'مسودة';

  /// الجهة المعروضة بالسطر: طرفاً بلسان الطرفية أو حساباً بالكود
  /// للسند بغير طرف — والفراغ لا يظهر.
  String get counterpartLabel =>
      partyName ??
      (directAccountCode == null ? '—' : 'حساب $directAccountCode');
}

/// صف حامل رمز باركود مكرر (س-131، دفعة 10) — يحمل عرض الصنف الحامل
/// بصيغة «الاسم (الكود)» المعتمدة كما تحمله رسائل الأصناف.
class BarcodeHolderRow {
  final int barcodeId;
  final int itemId;
  final String sku;
  final String name;

  const BarcodeHolderRow({
    required this.barcodeId,
    required this.itemId,
    required this.sku,
    required this.name,
  });

  /// العرض المعتمد «الاسم (الكود)» — صياغة رسالة الرفض تري صاحبها.
  String get displayLabel => itemDisplayLabel(name, sku);
}

/// صف قائمة تحويلات الصناديق للتصفح (س-16/05 §6).
class BoxTransferListRow {
  final int id;
  final String number;
  final String transferDate;
  final String state;
  final int amountDocMinor;
  final String? narration;
  final String currencyCode;
  final String fromBoxName;
  final String toBoxName;

  const BoxTransferListRow({
    required this.id,
    required this.number,
    required this.transferDate,
    required this.state,
    required this.amountDocMinor,
    required this.narration,
    required this.currencyCode,
    required this.fromBoxName,
    required this.toBoxName,
  });

  String get displayLabel {
    final kindLabel = sequenceKindLabels['box_transfer'] ?? 'تحويل بين صناديق';
    return number.isEmpty ? '$kindLabel — مسودة' : '$kindLabel $number';
  }

  String get stateLabel =>
      state == 'posted' ? 'مرحّل' : 'مسودة';
}

/// صف قائمة تسويات الصناديق للتصفح (س-17) — والسبب نصي إلزامي ظاهر.
class CashAdjustmentListRow {
  final int id;
  final String number;
  final String adjustmentDate;
  final String direction;
  final String state;
  final String reason;
  final int amountDocMinor;
  final String currencyCode;
  final String boxName;

  const CashAdjustmentListRow({
    required this.id,
    required this.number,
    required this.adjustmentDate,
    required this.direction,
    required this.state,
    required this.reason,
    required this.amountDocMinor,
    required this.currencyCode,
    required this.boxName,
  });

  String get displayLabel {
    final kindLabel =
        sequenceKindLabels['cash_adjustment'] ?? 'تسوية صندوق';
    return number.isEmpty ? '$kindLabel — مسودة' : '$kindLabel $number';
  }

  String get directionLabel =>
      CashAdjustmentDirection.fromStorage(direction).label;

  String get stateLabel =>
      state == 'posted' ? 'مرحّل' : 'مسودة';
}
