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

/// قاعدة دِقَّة — نسخة المخطط 6.
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
/// وترحيلة — لا تعديل رجعي على إصدار منشور (F-011).
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
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createLedgerTriggers();
          await _seedAccountingBaseline();
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
    final now = DateTime.now().millisecondsSinceEpoch;
    return transaction(() async {
      final moveId = await into(moves).insert(
        MovesCompanion.insert(
          journalId: journalId,
          dateText: dateText,
          state: 'draft',
          number: '',
          narration: Value(narration),
          refDocType: Value(refDocType),
          refDocId: Value(refDocId),
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      for (final line in lines) {
        await into(moveLines).insert(
          MoveLinesCompanion.insert(
            moveId: moveId,
            accountId: line.accountId,
            debitMinor: Value(line.debitMinor),
            creditMinor: Value(line.creditMinor),
            partyId: Value(line.partyId),
            uuid: const Uuid().v4(),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
      await _recordMoveEvent(moveId: moveId, action: 'created');
      return moveId;
    });
  }

  /// س-46/س-47: ترحيل المسودة — المحرك الحاكم (07 §1.1): المدقق الحاكم
  /// (قواعد المسودة + الفترة المفتوحة — 07 §1.5)، والترقيم المركزي داخل
  /// المعاملة ذاتها فلا رقم يُصدر بلا قيد مكتوب (07 §1.9/§2.4)، والحاجز
  /// الثاني مُشغِّلات القاعدة تتحقق عند كتابة الحالة، وأي رفض يتراجع كل
  /// شيء. والحدث «posted» بلقطة القيد المرحّل في المعاملة نفسها.
  Future<int> postMove(int moveId) async {
    return transaction(() async {
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
      final seqRow = await (select(sequences)
            ..where((t) =>
                t.kind.equals(ledgerMoveSequenceKind) &
                t.year.equals(year)))
          .getSingleOrNull();
      final nextNumber =
          seqRow == null ? 1 : nextSequenceNumber(seqRow.lastNumber);
      if (seqRow == null) {
        await into(sequences).insert(
          SequencesCompanion.insert(
            kind: ledgerMoveSequenceKind,
            year: year,
            lastNumber: nextNumber,
            uuid: const Uuid().v4(),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      } else {
        await (update(sequences)
              ..where((t) =>
                  t.kind.equals(ledgerMoveSequenceKind) &
                  t.year.equals(year)))
            .write(SequencesCompanion(
          lastNumber: Value(nextNumber),
          updatedAt: Value(now),
        ));
      }
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
    });
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
}

/// رفض مدقق الدفتر — يحمل الأخطاء النوعية المحمولة (نمط الأطراف: أنواع
/// بيانات لا نصوص جاهزة) وأوصافها العربية تخدم صفوف فشل التنفيذ حصراً؛
/// الواجهة حرية صياغتها المعروضة.
class LedgerValidationException implements Exception {
  final List<MoveValidationError> errors;

  const LedgerValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق الدفتر: ${errors.map(describeMoveValidationError).join('؛ ')}';
}
