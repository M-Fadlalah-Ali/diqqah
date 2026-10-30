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
/// الرئيسي على 1111.
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createLedgerTriggers();
          await _createInvoiceTables();
          await _createInvoiceTriggers();
          await _seedAccountingBaseline();
          await _seedInvoiceBaseline();
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
  });
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
    "CREATE TRIGGER IF NOT EXISTS trg_invoice_lines_frozen_update "
        "BEFORE UPDATE ON invoice_lines FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = OLD.invoice_id) "
        "<> 'draft' "
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

// ─── محرك الفواتير: القراءة الداخلية والتحقق والتخطيط والترحيل ───

/// قيمة مخزون محاكاة داخل التخطيط — تُقرأ مرة وتتطور بكل سطر على حدة
/// فتطابق الكتابة المتسلسلة حرفاً (تكلفة الخروج بالترتيب — D-067).
class _StockSim {
  final int warehouseId;
  final Map<int, (int, int)> _byItem = {};

  _StockSim(this.warehouseId);

  Future<(int, int)> of(int itemId) async {
    final existing = _byItem[itemId];
    if (existing != null) return existing;
    final balance = await _stockBalanceTx(itemId, warehouseId);
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
    "(SELECT COALESCE(SUM(CASE WHEN kind = 'in' THEN amount_base_minor "
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
    'line_total_doc_minor, line_total_base_minor, uuid '
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
  final sim = _StockSim(draft.warehouseId!);
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
      "is_deleted) VALUES (?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
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

/// رصيد صنف في مستودعه (كمية، قيمة إجمالية — D-067) للقراءة والفحص.
Future<(int, int)> stockBalanceOf({
  required int itemId,
  required int warehouseId,
}) =>
    _stockBalanceTx(itemId, warehouseId);

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

/// الصيغة المعروضة لرقم الفاتورة (م-44/D-071): «فاتورة بيع 2026/000001».
String invoiceDisplayLabel(InvoiceDocument invoice) {
  final kind = InvoiceKind.fromStorage(invoice.kind);
  final label =
      sequenceKindLabels[invoiceSequenceKind(kind)] ?? kind.label;
  return '$label ${invoice.number}';
}
