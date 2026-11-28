import 'dart:convert';
import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import 'db_encryption.dart';

part 'database.g.dart';

/// س218 (علّة b72 الحيّة المالِفية — أول فتح قاعدة مشفرة برمز البوابة
/// DQ-0999): «Invalid argument in isolate message: object is unsendable
/// — dart:async _AsyncCompleter». الجذر توثيق drift حرفاً (native.dart
/// لسطري 141–145): «دوال setup وisolateSetup وsqlite3 تُرسَل إلى عزلات
/// أخرى وتُنفَّذ هناك — فاحذر ألا تلتقط حالة غير مقصودة للإرسال».
/// وإغلاقُ الإعداد المشفر كان مبنِياً بنطاق المُصنعية داخل إغلاق
/// LazyDatabase فيحمل عند التسلسل سلسلة سياقه اللفظية كاملة: سياقُه
/// يلتقط keyHex النصي فحسب لكن سياقَ الأب يلتقط `late final db` —
/// كائن قاعدة البيانات ذاته — وفيه DatabaseConnection بLazyDatabase
/// تسبِيغُه _AsyncCompleter من dart:async وكائنات async الحيّة لا
/// تُرسَل بين العزلات إطلاقاً — فرفض Dart الرسالة كلها (Isolate.spawn
/// برسالة _NativeIsolateStartup لحظة أول افتتاح) قبل فتح ملف SQLite
/// بحال: لا قراءة ولا كتابة ولا ترحيلة — البيانات سليمة والعللة
/// حتمية كل تشغيل. والفرع النصي سلم محضاً لأن إغلاقه بلا أي التقاط
/// (واختبارات CI الخضراء على المصنعية النصية خير شاهد).
///
/// القانون المعماري بعد س218: أي دالة تُمرَّر إلى
/// [NativeDatabase.createInBackground] (setup/isolateSetup/sqlite3)
/// يُبنى نطاقها علوياً حصراً — دالة علوية أو بنّاءة علوية تلتقط قيماً
/// بسيطة قابلة للإرسال (String/int/bool/مسار) حصراً — ولا `this` ولا
/// كائن قاعدة ولا اتصال ولا مستقبل أو مكتمل async إطلاقاً. والحرس
/// البنيوي باختبار s218 يمنع عودة الإغلاق المضمّن بنطاق المُصنعية.

/// س218: إعداد الفرع النصي — إغلاق بلا أي التقاط فقابل للإرسال
/// بنيوياً. مشترك بنطاقٍ علوي بين الإنتاج الخلفي وتوأم الاختبار
/// المتزامن فنص البراغمات متطابق ببنية الشيفرة لا بالنسخ اليدوي.
final DatabaseSetup _applyPlainPragmas = (rawDb) {
  rawDb.execute('PRAGMA synchronous = NORMAL');
};

/// س218: بنّاءة إعداد الفرع المشفر — النطاق العلوي يقطع سلسلة السياق
/// عن المُصنعية فالإغلاق يلتقط المفتاح النصي حصراً (قيمة بسيطة قابلة
/// للإرسال) ولا يحمل قاعدة البيانات ولا الاتصال إطلاقاً. علنية كي
/// يرسلها اختبار الانحدار s218 عبر حدود عزل فعلاً (العلة لا تظهر إلا
/// بعبور العزل — والفرع المشفر لا يُفتح ببيئة الاختبار بلا دمج MC
/// فحارس debug يرمي هناك).
DatabaseSetup cipherSetupFor(String keyHex) {
  return (rawDb) {
    // فحص debug بـ`PRAGMA cipher` — توثيق drift حرفاً:
    // بلا دمج MC الصوت عالٍ ولا نص صريح صامت أبداً.
    assert(debugCheckHasCipher(rawDb));
    // النمط المعتمد د-٢ يُثبَّت قبل المفتاح (توثيق MC).
    rawDb.execute("PRAGMA cipher = '$kDbCipherScheme'");
    rawDb.execute(dbKeyPragmaRaw(keyHex));
    // س216: بالوضع اللوحي — Normal آمنة ومكسبها موثق بالمُصنعية.
    rawDb.execute('PRAGMA synchronous = NORMAL');
  };
}

/// س218: الفرع النصي الإنتاجي — المحرك بعزل الخلفية (س216) بإغلاق
/// إعداد بلا التقاط (بنّاءة علوية بعقد س218).
QueryExecutor _openPlainInBackground(String filePath) =>
    NativeDatabase.createInBackground(
      File(filePath),
      setup: _applyPlainPragmas,
    );

/// س218: الفرع المشفر الإنتاجي — ذات البناء بإعداد البنّاءة العلوية
/// [cipherSetupFor] القابلة للإرسال.
QueryExecutor _openCipherInBackground(String filePath, String keyHex) =>
    NativeDatabase.createInBackground(
      File(filePath),
      setup: cipherSetupFor(keyHex),
    );

/// حامل مفتاح القاعدة النسبي — قابل للتغيير من داخل اختام الفتح (درس
/// المصرّف: حقول النسخة لا تُلمس من قائمة البواني فحامل مستقل يُضبط وقت
/// الفتح الفعلي ويقرأه backup.dart عبر dbKeyHex).
class _DbKeyHolder {
  String? hex;
}

/// يُرمى عند فتح قاعدة أحدث مخططاً من التطبيق (F-156: «حدّث التطبيق»).
class DiqqahNewerSchemaException implements Exception {
  const DiqqahNewerSchemaException();

  @override
  String toString() => 'القاعدة أحدث مخططاً من التطبيق — حدّث التطبيق';
}

/// F-033: محاولة تعديل عامل تحويل بعد وجود حركات على أصناف المجموعة —
/// مرفوضة، والمسار الوحيد إنشاء وحدة جديدة (D-026). الواجهة تفحص
/// التجمد سلفاً فتعطّل الخانة — وهذا الاستثناء حرس ثانوي للمسار
/// المباشر.
class UnitGroupFactorFrozenException implements Exception {
  const UnitGroupFactorFrozenException();

  @override
  String toString() =>
      'عامل التحويل يتجمد بعد وجود حركات على أصناف المجموعة (F-033) — '
      'والمسار الوحيد إنشاء وحدة جديدة';
}

/// علامة «لا مساس» لمعامل الاختياري في updateItemDetails — الواجهة
/// التي لا تعرف المجموعة أصلاً لا تمسحها بالمرور (Presence absent
/// بنمط F-165).
const Object _keepCurrent = Object();

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

  /// مجموعة تعبئة الصنف — F-032/D-026 (الدفعة 27): null يعني صنفاً
  /// بلا مجموعة تعبئة فلا مستويات ولا اشتقاق.
  IntColumn get unitGroupId =>
      integer().nullable().named('unit_group_id')();

  /// مربع «آلي» — F-208 (اللفظ النهائي س84/D-187): افتراضه مفعل،
  /// مفعّلاً الوحدة الصغرى للكتابة والمستويات للقراءة تُشتق، وتعطيله
  /// يتاح كل الخانات، وإعادة تفعيله تستبدل المستويات بالاشتقاق.
  BoolColumn get priceAuto =>
      boolean().named('price_auto').withDefault(const Constant(true))();

  /// الحد الأدنى المحدد للصنف — د6 (س175) المتابعات اليومية
  /// (س74/D-184 بلفظ المالك «الأصناف التي انخفضت عن الحد الأدنى
  /// المحدد»): null يعني بلا حد أدنى فلا متابعة، والحد بوحدة
  /// الأساسية على السلع حصراً (الخدمات بلا مخزون أصلاً).
  IntColumn get minQty => integer().nullable().named('min_qty')();

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

/// مجموعة تعبئة — F-032/D-026 (الدفعة 27): قوالب مقترحة غير حصرية
/// (قطعة/علبة/كرتونة) ويضيف المستخدم ما يشابه ومستوياته الأعلى.
/// الاسم فريد حرفياً (D-074، قيد UNIQUE حرس ثانوي) — إضافة وتسمية
/// حصراً: لا حذف ولا تعطيل فالصنف قد يحيل بها (نمط المراجع 03 §6-3).
class UnitGroups extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().unique()();

  /// اصطلاح «كل جدول» (D-055).
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// مستوى مجموعة تعبئة — عامل تحويل صحيح ثابت نحو الوحدة الأساسية
/// (≥2: الأساسية عاملها 1 بذاتها ولا تُخزن مستوى — 05). تفرد الاسم
/// داخل المجموعة قيدُ UNIQUE داخل DDL الجدول ذاته (uniqueKeys — درس
/// آمنة التكرار: فهرس @TableIndex مستقل تبنيه createAll بلا IF NOT
/// EXISTS فينكسر مع نداءات createAll المتعددة عبر خطوات الترقية،
/// والقيد داخل الجدول يولد مرة واحدة معه)، والعامل يتجمد بعد
/// الحركات (F-033) بحراسة المسار `updateUnitGroupLevel` لا بقاعدة
/// — القاعدة لا تعرف الحركات، والمسار الوحيد حينها وحدة جديدة.
class UnitGroupLevels extends Table {
  @override
  List<Set<Column>> get uniqueKeys => [
        {groupId, name},
      ];

  IntColumn get id => integer().autoIncrement()();

  IntColumn get groupId => integer().named('group_id')();

  TextColumn get name => text()();

  IntColumn get factor => integer()();

  /// اصطلاح «كل جدول» (D-055).
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// سعر مستوى تعبئة لصنف — «خانة مستقلة لكل مستوى» (F-208/D-187):
/// الآلي يكتب الاشتقاق عند كل حفظ واليدوي يحفظ ما كتبه المالك،
/// ولقطة السعر في سطر المستند كما هي بلا مساس (D-187). وتفرد
/// (الصنف، المستوى) قيدُ UNIQUE داخل DDL الجدول ذاته (uniqueKeys —
/// درس آمنة التكرار أعلاه).
class ItemLevelPrices extends Table {
  @override
  List<Set<Column>> get uniqueKeys => [
        {itemId, levelId},
      ];

  IntColumn get id => integer().autoIncrement()();

  IntColumn get itemId => integer().named('item_id')();

  IntColumn get levelId => integer().named('level_id')();

  IntColumn get salePriceMinor => integer().named('sale_price_minor')();

  IntColumn get purchasePriceMinor =>
      integer().named('purchase_price_minor')();

  /// اصطلاح «كل جدول» (D-055).
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();
}

/// وصفة التجميعي — `bundle_component` (05 §3.2/الدفعة 28/F-034/F-212):
/// مكونات الصنف التجميعي بكمياتها الوصفية بالوحدة الأساسية لكل وحدة
/// تجميعية واحدة، وتكلفة المكوّن الخدمي اختيارياً (للخدمة بالخيارين
/// F-212: فارغة = بند بيعي ضمن السعر، بقيمة = تدخل مجموع كلف الوصفة؛
/// للبضاعة null حصراً فكلفة البضاعة من مخزونها الحاكم لا من الخانة).
/// تفرد (التجميعي، المكوّن) قيدُ UNIQUE داخل DDL الجدول ذاته
/// (uniqueKeys — درس آمنة التكرار الموثق س86: فهرس @TableIndex
/// المستقل يكسر نداءات createAll المتعددة عبر خطوات الترقية).
class BundleComponents extends Table {
  @override
  List<Set<Column>> get uniqueKeys => [
        {bundleItemId, componentItemId},
      ];

  IntColumn get id => integer().autoIncrement()();

  IntColumn get bundleItemId => integer().named('bundle_item_id')();

  IntColumn get componentItemId => integer().named('component_item_id')();

  IntColumn get qtyBase => integer().named('qty_base')();

  /// تكلفة المكوّن الخدمي — null للبضاعة واختيارية للخدمة (F-212).
  IntColumn get costMinor => integer().nullable().named('cost_minor')();

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

  /// س211 (D-216): راية «إلزام تغيير الكلمة عند أول جلسة» — تُرفع عند
  /// الولادة بcreateUser حصراً (المدير البذري والعلماء القائمون صفر)،
  /// وفنجانها بchangeOwnPassword عند النجاح حصراً، وفرضُها بالواجهة
  /// عند التبديل (س211). عمود قاعدة البيانات الافتراضي صفر فالصفوف
  /// القائمة قبل الترحيلة v34 باقية كما هي.
  BoolColumn get mustChangePassword =>
      boolean().named('must_change_password')
          .withDefault(const Constant(false))();

  /// س227 (المرحلة صفر د3 من خارطة طريق التقرير الاستشاري بأمر المالك
  /// «ابدأ التنفيذ»): عداد محاولات الدخول الفاشلة وقفلها المتدرج —
  /// صفر يعني لا فشل بعد، والحال على صف المستخدم فتنجو بموت العملية
  /// بعقد آلة الحالتين (س212) بنمط الراية، والقفل بمستويات مغلقة
  /// (نمط مستويات الخمول D-217) عند كل عتبة خمس محاولات.
  IntColumn get failedLoginAttempts =>
      integer().withDefault(const Constant(0))
          .named('failed_login_attempts')();

  /// لحظة انتهاء القفل بالميلي ثانية (epoch) — صفر يعني غير مقفل.
  IntColumn get lockedUntil =>
      integer().withDefault(const Constant(0)).named('locked_until')();

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

  /// مدة السداد المحددة للطرف بالأيام — د6 (س175) المتابعات اليومية
  /// (س74/D-184 بلفظ المالك «الأرصدة التي تجاوزت سقفها الأعلى من
  /// حيث المبلغ أو الزمن»): السقف المبلغي حد الائتمان أعلاه والسقف
  /// الزمني هذه المدة، وnull يعني بلا مدة فلا متابعة زمنية.
  IntColumn get paymentTermDays =>
      integer().nullable().named('payment_term_days')();

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
/// - `number` نص الرقم المُصدَر — والمسودة بلا رقم («»): الترقيم لحظة
///   الترحيل حصراً فلا رقم يُصدر ولا يُعاد (07 §1.9). الصيغة الجديدة
///   D-169 «سنة رقمين + عدّاد مبطن بلا فاصل» («26000001» بعرض 6)،
///   والصادرة قبلها بصيغة «2026/000001» بيانات أعمال لا تُمسّ — فتعيش
///   القاعدة فترة انتقالية بصيغتين موثقة. الصيغة الكاملة المعروضة
///   «قيد عام …» تولّد للعرض من الرقم المخزن كما هو بformatSequenceLabel
///   (م-44 — الاسم الكامل بلا بادئة مختصرة).
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

  /// الشركة الحاملة للحدث — د3 (س170/D-188/م-٥: «كل حدث يحمل
  /// company_id والعزل للخادم» عرف 08 §7): default الشركة الافتراضية
  /// الواحدة (F-111) فالقديمة تملأ بلا كتابة، والإدارة النشطة بموضعها
  /// (F-112) والحزمة تحملها ترويسةً وصفاً بعقد د1/د3.
  TextColumn get companyId =>
      text().named('company_id').withDefault(const Constant('main'))();

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
/// س121 — مسودة سطر أمر كما تخرج من نموذج الواجهة قبل التحقق
/// (لقطة الوحدة ثلاثية الأركان والكمية بوحدة الإدخال ومكافؤها
/// الأساسي محسوبان بالواجهة كما في الفواتير — والسعر المرجعي
/// تسعير وقت الأمر لا سعر إلزام).
class OrderLineDraft {
  final int itemId;
  final int unitId;
  final int? unitLevelId;
  final int factorAtEntry;
  final int qty;
  final int qtyBase;
  final int unitPriceMinor;

  const OrderLineDraft({
    required this.itemId,
    required this.unitId,
    this.unitLevelId,
    this.factorAtEntry = 1,
    required this.qty,
    required this.qtyBase,
    this.unitPriceMinor = 0,
  });
}

/// س121 — مسودة أمر كاملة كما تخرج من نموذج الواجهة قبل التحقق.
class OrderDraft {
  final OrderDirection direction;
  final int? partyId;
  final int? warehouseId;

  /// تاريخ الأمر ISO «YYYY-MM-DD» (D-077 المعتمد) — منه سنة التسلسل.
  final String orderDate;
  final String? expectedDate;

  /// عملة الأسعار المرجعية — لا قيداً عملةً أبداً (الأمر لا يُقيد).
  final int currencyId;
  final String? narration;
  final List<OrderLineDraft> lines;

  const OrderDraft({
    required this.direction,
    required this.orderDate,
    this.partyId,
    this.warehouseId,
    this.expectedDate,
    this.currencyId = 1,
    this.narration,
    this.lines = const [],
  });
}

/// س121 — صف قائمة الطلبات للعرض (الرأس مع عدّ الأسطر ومجموع
/// الكميات الأساسي واسم الطرف للعرض).
class OrderListRow {
  final int id;
  final String direction;
  final String number;
  final int? partyId;
  final String? partyName;
  final int? warehouseId;
  final String orderDate;
  final String? expectedDate;
  final int currencyId;
  final String state;
  final String? narration;
  final int linesCount;
  final int totalQtyBase;

  const OrderListRow({
    required this.id,
    required this.direction,
    required this.number,
    this.partyId,
    this.partyName,
    this.warehouseId,
    required this.orderDate,
    this.expectedDate,
    required this.currencyId,
    required this.state,
    this.narration,
    required this.linesCount,
    required this.totalQtyBase,
  });
}

/// س121 — سطر أمر كما يُقرأ للتفصيل والتحويل (باسم الصنف وكوده
/// للعرض عرف السطور القائمة).
class OrderLineRow {
  final int id;
  final int orderId;
  final int itemId;
  final String? itemSku;
  final String? itemName;
  final int unitId;
  final int? unitLevelId;
  final int factorAtEntry;
  final int qty;
  final int qtyBase;
  final int unitPriceMinor;

  const OrderLineRow({
    required this.id,
    required this.orderId,
    required this.itemId,
    this.itemSku,
    this.itemName,
    required this.unitId,
    this.unitLevelId,
    required this.factorAtEntry,
    required this.qty,
    required this.qtyBase,
    required this.unitPriceMinor,
  });
}

/// س121 — خلاصة التحويل: الأمر وأسطره ومتبقٍّ كل صنف بالمكافئ
/// الأساسي محسوباً من فواتير الأمر الحية (الوفاء محسوب لا مخزن).
class OrderConversionPreview {
  final OrderListRow order;
  final List<OrderLineRow> lines;

  /// لكل صنفٍ بالأمر: المطلوب والمنفَّذ والمتبقي بالمكافئ الأساسي.
  final List<OrderItemFulfilment> fulfilment;

  const OrderConversionPreview({
    required this.order,
    required this.lines,
    required this.fulfilment,
  });

  /// المتبقي لصنف — صفر لمن ليس بالأمر (الأمانة في الحرس: ما ليس
  /// بالأمر لا يمر عبر التحويل).
  int remainingQtyBaseOf(int itemId) {
    for (final f in fulfilment) {
      if (f.itemId == itemId) return f.remainingQtyBase;
    }
    return 0;
  }
}


@DriftDatabase(tables: [
  Items,
  Roles,
  AppUsers,
  AppMeta,
  Parties,
  Units,
  UnitGroups,
  UnitGroupLevels,
  ItemLevelPrices,
  BundleComponents,
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
  /// مفتاح القاعدة الخام بالصيغة الست عشرية — يُضبط داخل LazyDatabase بعد
  /// تحميله من الخزنة، ويقرأه backup.dart لتصدير صورة صريحة للنسخ (P0-ج).
  /// null = قاعدة بلا خزنة (الاختبارات والقواعد في الذاكرة — نص صريح
  /// بذاكرة العمل لا ملف جهاز فلا مساس بF-150).
  final _DbKeyHolder _key = _DbKeyHolder();

  /// عتبة ترقية هاش الدخول (P2 — 09 §40): عند التحقق الناجح، السجل
  /// بتكرارات أدنى من هذه يُعاد تجزئته بملح جديد وعند هذه العتبة —
  /// الترقية آلية عند أول دخول ناجح (نمط «الترحيل عند أول فتح» P0/P1).
  /// الاختبارات تحقن قيمة صغيرة أو [PasswordHasher.legacyIterations]
  /// لتعطيل الترقية (نمط hasherIterations الموثق).
  final int passwordUpgradeIterations;

  String? get dbKeyHex => _key.hex;

  /// التشغيل العادي: ملف القاعدة الوحيد (أساس النسخ الاحتياطي الكامل F-012).
  /// ملف الجيل السابق «heseb.db» يتبنّى آلياً عند أول فتح (D-053 —
  /// adoptLegacyHesebDatabase في backup.dart).
  ///
  /// F-150/D-210 P0 (س148): [keyVault] خزنة الجهاز — عند تمريرها يُحمل
  /// المفتاح العشوائي 256-bit ويُرحَّل النص الصريح عند أول فتح (لقطة
  /// preenc ثم VACUUM INTO ثم rekey ثم إعادة تسمية — فشل آمن) ثم يُفتح
  /// الاتصال المشفر بحارس debug بـ`PRAGMA cipher` (توثيق drift). بحذفه
  /// يبقى الفتح النصي القديم حرفاً (الاختبارات).
  ///
  /// مصنعية لا بانية مباشرة — الاختام والترحيل والمفتاح بجسم المصنعية
  /// كي تُضبط حقول النسخة وقت الفتح الفعلي (الاختام في قائمة البواني
  /// لا تلمس هذا — درس المصرّف بالجولة الأولى).
  /// س216 (معالجة ثقل الدقائق الأولى — قرار المالك «أريد الانتهاء من
  /// ثقل التطبيق أولاً»): المحرك يعمل بعزل خلفي حصراً
  /// [NativeDatabase.createInBackground] فكل عمل SQLite الثقيل (ترحيلة
  /// v35 و16 فهرساً على قاعدة كبيرة، وVACUUM INTO للنسخ، والفحص
  /// الافتتاحي، واستعلامات الرئيسية) يجري خارج عزل الواجهة فلا تجميد
  /// إطارات ولا تحذير ANR من أندرويد عند أول فتح بعد ترقية.
  /// الافتراض القديم NativeDatabase على عزل الواجهة كان جذر الثقل:
  /// أثقل عمل القاعدة كان يحجب الخيط الواجهي نفسه (درس b71 الحي:
  /// رسالة توقف من أندرويد في الدقائق الأولى ثم سلاسة بعد الإغلاق
  /// لأن الفهارس أُنشئت مرة واحدة على العزل المحجوب نفسه).
  /// PRAGMA synchronous=NORMAL بWAL (اللقطات تنسخ -wal/-shm فالوضع
  /// اللوحي قائم) — عقد SQLite الموثق: فوضى الطاقة المفاجئة قد تُسقط
  /// آخر معاملات حديثة ولا تفسد القاعدة أبداً، ومكسبه عدد أقل من
  /// المزامات القرصية عند البناء الكبير والكتابة.
  /// س218 (علّة b72 الحيّة — أول فتح قاعدة مشفرة برمز البوابة
  /// DQ-0999 «object is unsendable — _AsyncCompleter»): بناء المحرك
  /// كله ببنّاءتين علويتين [_openPlainInBackground] و
  /// [_openCipherInBackground] فإغلاقُ الإعداد المرسل لعزل الخلفية
  /// لا يحمل سياق المُصنعية إطلاقاً (درس العلة وتفصيل القانون فوق
  /// البنّاءتين — والحرس البنيوي باختبار s218).
  factory DiqqahDatabase(
      {String filePath = 'diqqah.db',
      DatabaseKeyVault? keyVault,
      List<int>? logRootKey,
      int passwordUpgradeIterations = PasswordHasher.secureIterations}) {
    late final DiqqahDatabase db;
    db = DiqqahDatabase._crypto(LazyDatabase(() async {
      if (keyVault == null) {
        // س218: البناء ببنّاءة علوية — الإغلاق المرسل لعزل الخلفية
        // بلا سياق المُصنعية إطلاقاً (درس b72).
        return _openPlainInBackground(filePath);
      }
      final keyHex = dbKeyHexOf(await keyVault.loadOrCreateKey());
      db._key.hex = keyHex;
      // لقطة الأمان قبل التشفير (نمط D-197) — أقصى جهد لا حاجز.
      await snapshotBeforeEncryption(filePath);
      // ترحيل النص الصريح عند أول فتح — فشل آمن: الأصل لا يُمس
      // حتى إعادة التسمية الأخيرة، والشاشة الحارسة تعرض الخطأ.
      await migratePlainToEncrypted(filePath, keyHex);
      return _openCipherInBackground(filePath, keyHex);
    }),
        passwordUpgradeIterations: passwordUpgradeIterations,
        logRootKey: logRootKey);
    return db;
  }

  DiqqahDatabase._crypto(QueryExecutor executor,
      {this.passwordUpgradeIterations = PasswordHasher.secureIterations,
      List<int>? logRootKey})
      : _p3LogCipher = LogCipher(logRootKey),
        super(executor);

  /// للاختبارات: قاعدة في الذاكرة — لا أثر على ملف المستخدم أبداً.
  /// س230: [logRootKey] جذر سجلات الجهاز للاتصال (لاختبارات الخزنة) —
  /// والغائب الجذر الإرثي المضمّن.
  DiqqahDatabase.inMemory(
      {int passwordUpgradeIterations = PasswordHasher.secureIterations,
      List<int>? logRootKey})
      : passwordUpgradeIterations = passwordUpgradeIterations,
        _p3LogCipher = LogCipher(logRootKey),
        super(NativeDatabase.memory());

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
  factory DiqqahDatabase.inMemorySyncClose(
          {int passwordUpgradeIterations =
              PasswordHasher.secureIterations,
          List<int>? logRootKey}) =>
      DiqqahDatabase._syncClose(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
          passwordUpgradeIterations: passwordUpgradeIterations,
          logRootKey: logRootKey);

  /// س217 (توأم الاختبار للملف الحقيقي — درس الجولة #436): مصنعية
  /// اختبارية لمسارات الملف الحقيقي (النسخ والاستعادة والتشفير) بمحرك
  /// متزامن داخل عزل المستدعي حصراً، بنمط [inMemorySyncClose] الموثق.
  /// لماذا لا الإنتاجية [DiqqahDatabase] في اختبارات الواجهة؟ بيئة
  /// widget tests الزائفة (FakeAsync) لا تُكمل عمليات العزل الخلفي
  /// حصراً: إكمال السلسلة يتطلب تفريغ microtasks الزائفة التي لا تجري
  /// إلا في pump بينما رسائل المنافذ لا تُسلَّم إلا بنوافذ runAsync
  /// الواقعية — والتركيبان معاً ميتان دورياً بالحالتين (انتظار داخل
  /// runAsync أو خارجه — المسبار المحلي س217 بالجلسة: IO واقعي يعمل
  /// وIsolate.run يعمل بالنمطين وVACUUM على العزل الخلفي لا يكتمل
  /// إطلاقاً) فتعلق الجناح الواجهي كله وتفسد قناة بروتوكول الاختبار
  /// («Cannot close sink while adding stream») فتتجمد الجولة بملفاتها
  /// المتزامنة (الجولة #436: صمت 26.5 دقيقة حتى حصاد السقف).
  /// الإنتاج لا يمسه شيء: المصنعية الإنتاجية بعزلها الخلفي هي وجه
  /// الإنتاج حصراً وحماية الثقل الموثقة س216 باقية، والتغطية البنيوية
  /// للعزل الخلفي باقية باختبارات التخزين (dart test بمنطقه الواقعي
  /// لا زائف). وإغلاق التدفقات فوراً بعقد inMemorySyncClose ذاته كي
  /// لا تعلق الإغلاقات بعد الاختبار (درس CI 2026-10-29/30).
  /// PRAGMA synchronous=NORMAL بمساواة الإنتاجية كي يظل سلوك الملف
  /// (WAL واللقطات) مطابقاً.
  /// س218: البراغمات بالإغلاقات العلوية المشتركة ذاتها مع الإنتاج
  /// ([_applyPlainPragmas] و[cipherSetupFor]) فالتطابق ببنية الشيفرة
  /// لا بالنسخ — والمحرك المتزامن هنا لا يعبُر عزلاً فالإغلاقان لا
  /// يُرسَلان أصلاً (العقد الإرسالي للإنتاج الخلفي حصراً).
  factory DiqqahDatabase.fileSyncClose(
      {String filePath = 'diqqah.db',
      DatabaseKeyVault? keyVault,
      List<int>? logRootKey,
      int passwordUpgradeIterations = PasswordHasher.secureIterations}) {
    late final DiqqahDatabase db;
    db = DiqqahDatabase._syncClose(DatabaseConnection(
      LazyDatabase(() async {
        if (keyVault == null) {
          return NativeDatabase(File(filePath), setup: _applyPlainPragmas);
        }
        final keyHex = dbKeyHexOf(await keyVault.loadOrCreateKey());
        db._key.hex = keyHex;
        // لقطة الأمان قبل التشفير وترحيل النص الصريح — بنص المصنعية
        // الإنتاجية حرفاً (نمط D-197 والفشل الآمن) لا إعادة كتابته.
        await snapshotBeforeEncryption(filePath);
        await migratePlainToEncrypted(filePath, keyHex);
        return NativeDatabase(File(filePath), setup: cipherSetupFor(keyHex));
      }),
      closeStreamsSynchronously: true,
    ),
        passwordUpgradeIterations: passwordUpgradeIterations,
        logRootKey: logRootKey);
    return db;
  }

  DiqqahDatabase._syncClose(DatabaseConnection connection,
      {this.passwordUpgradeIterations = PasswordHasher.secureIterations,
      List<int>? logRootKey})
      : _p3LogCipher = LogCipher(logRootKey),
        super(connection);

  /// D-197 (دفعة التحصين الافتتاحي — س96): إصدار المخطط الثابت الوحيد —
  /// يقرأه المتجدد والفتح واللقطة الأمانة (snapshotBeforeUpgrade) من
  /// مصدر واحد فلا تفرّق أرقام تُنسى في تعديل قادم.
  /// v28 (س146 — p3 خط التشفير): إحكام سجلي الأحداث والأخطاء — لا
  /// جداول ولا أعمدة جديدة: ملح اشتقاق بـapp_meta وختم القائمة
  /// وشرائب الحاجز حصراً (نمط ترحيلات «بلا مخطط» المجرّبة).
  /// v29 (س160 — د0 أولى خارطة م4 09 §46): فهرس `ix_move_lines_move_id`
  /// على `move_lines (move_id)` — المرشح الموثق س156 صار مخططاً: بلا
  /// فهرس يصعد ترحيل العينة الكبيرة O(N²) بمجموعَي زناد التوازن لكل
  /// صف، والفهرس يخفض فحص التوازن لكل قيد إلى O(log N). ترحيلة
  /// مخططية واحدة بلا جداول ولا أعمدة ولا إعادة بناء (قرار م-٤:
  /// د0 تسبق فكل دفعة تُقاس على أداء معلوم).
  /// v30 (س164 — إلغاء التعليق وبوابة «ترحيل مسودات الآخرين»): ترحيلة
  /// بيانات لا مخطط — إلحاق مفتاح البوابة الفرعية `invoices.post_others`
  /// بكل دور قائم كان يعتمد سلفاً (ليس النجمة ولا بائعاً ولا مندوباً
  /// ومعه وحدة الفواتير) عرف «من كان يعتمد يبقى يعتمد» فلا يفقد
  /// معتمِدُ قائمةٍ قدرتَه بالترقية، والنجمة تشمل البوابة أصلاً،
  /// ومنحُ البوابة لمن سواه بيد المالك من شاشة الصلاحيات
  /// (كلمة المالك: «حتى البائع يمكن منحه صلاحية ترحيل فاتورة مندوب»).
  /// v31 (س170 — د3 الترقيم متعدد الأجهزة وتعدد الشركات بموضع م-٥/D-188
  /// بكلمة المالك «تابع د1 و3 و4»): كل حدث يحمل company_id — عمود واحد
  /// بdefault الشركة الافتراضية الواحدة 'main' (F-111) بADD COLUMN
  /// بحرس pragma (درس v3) فالقاعدة الجديدة تولد بالعمود (default drift)
  /// والقديمة ترقى بلا إعادة بناء ولا مساس بالصفوف، والحزمة تحملها
  /// ترويسةً وصفاً بعقد §10 ود1/د3 والعزل يمتد للخادم مع أول مهايئ (د4) —
  /// وإدارة التعدد النشطة (F-112/F-113) بموضعها الموثق دفعتها الخاصة.
  /// إصدار المخطط — الحاكم الوحيد (درس v14): أحدثه د6 (س175) v32:
  /// المتابعات اليومية (س74/D-184) عمودا الحد الأدنى على الأصناف
  /// ومدة السداد على الأطراف بADD COLUMN بحرس pragma — بلا إعادة
  /// بناء ولا مساس بالقيم القائمة — وأحدثته س181 (إعادة تأسيس تنظيف
  /// الرموز، وأصله س166 المفقودة على قاعدة قديمة) v33: ترحيلة بيانات
  /// لا مخطط — إعادة تعريف موثقة لنصوص الحواجز (درس v9/v21/v22/س107):
  /// نزع الإحالات الداخلية (س-x/F-xxx/§) من الرسائل التي يراها
  /// المستخدم وبقاؤها بتعليقات الشيفرة، وترميز حواجز الإلحاق الرباعية
  /// للسجلين أول ترقيم لها (DQ-1119..1122 بعد أن حجزت دفعات م4
  /// الرقميةَ السابقة) — فكل رسالة رفض تحمل رمزها حصراً بعقد مرجع
  /// الأخطاء 08، ودوال الإنشاء كلها بـDROP داخلي فإعادة الاستدعاء
  /// آمنة التكرار أي كان مسار الوصول.
  /// وأحدثتها س211 v34: عمود `must_change_password` بADD COLUMN
  /// بحرس pragma بنمط v31/v32.
  /// وأحدثتها س215 (أمر المالك «أرى بدء البند 7 المعماري «نواة واحدة
  /// قشرة لكل منصة»، ومعالجة الثقل الجذري للبيانات الضخمة (فهارس
  /// واستعلامات الرئيسية) ثم التوثيق والدفع والبناء») v35 — ترحيلة
  /// مخططية خالصة بلا جداول ولا أعمدة ولا إعادة بناء ولا مساس بالبيانات:
  /// فهارس طرق الوصول الحارة التي كشفها اختبار قاعدة المالك التجريبية
  /// الكبيرة (س214: 3,863 فاتورة و11,378 سطراً و997 سنداً و4,650 حركة
  /// و18,814 حدثاً — فحص الثوابت الافتتاحي T4/M1/M3 وأرصدة الحسابات
  /// والصناديق وأسطر الفواتير والأحداث) كلها CREATE INDEX IF NOT
  /// EXISTS آمنة التكرار أي كان مسار الوصول (onCreate زرعها سلفاً
  /// بعرف v29) — والدليل البنيوي كامل بسجل الدفعة والاختبار s215.
  /// وأحدثتها س227 (المرحلة صفر بخارطة طريق التقرير الاستشاري بأمر
  /// المالك «ابدأ التنفيذ»): v36 — عمودا قفل الدخول المتدرج
  /// (failed_login_attempts وlocked_until) على app_users بADD COLUMN
  /// بحرس pragma بنمط v31/v32/v34، وv37 — ترحيلة بيانات بنمط v30
  /// حرفاً: إلحاق بوابة القوائم المالية الفرعية reports.financials
  /// بكل دور قائم يعتمد التقارير (لا النجمة ولا أمين المستودع
  /// المخصوص بالاسم — «تقارير المخزون حصراً» بقرار المالك) عرف
  /// «من كان يعتمد يبقى يعتمد».
  /// وأحدثتها س236 (د10 البنوك D-224 بأمر المالك «نفذ د10»): v38 —
  /// ثلاثة أعمدة على cash_boxes بADD COLUMN بحرس pragma بنمط v31/v36
  /// (kind نقدي/جارٍ بنكي وbank_name وaccount_number لصناديق البنوك)
  /// وجدول bank_reconciliations خالصاً لمستند التسوية البنكية بنمط
  /// cash_adjustments حرفاً (مع رصيدي الكشف والدفتري اللقطة).
  /// وأحدثتها س237 (المرحلة ج D-235): v39 — ثلاثة أعمدة على
  /// invoice_lines بADD COLUMN بحرس pragma (is_free للسطر الحر
  /// وdescription وصفه وnote ملاحظة السطر القصيرة).
  static const int schemaVersionValue = 39;

  @override
  int get schemaVersion => schemaVersionValue;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // د0 (س160): فهرس move_id من أول إنشاء — فالقاعدة الجديدة
          // تولد بأدائها النهائي لا بفجوة س156 (الفهرس كان محلياً
          // بالاختبار حصراً) — والترحيلة v29 تضمن القائمة.
          await _createMoveLinesIndex();
          await _createLedgerTriggers();
          await _createInvoiceTables();
          await _createInvoiceTriggers();
          await _createVoucherTables();
          await _createVoucherTriggers();
          await _createTransferTables();
          await _createCountTables();
          await _createMovementDocTables();
          await _createOrderTables();
          await _createOrderTriggers();
          await _createAssemblyTables();
          await _createExchangeRateTables();
          await _createErrorLogTable();
          // س215 (الثقل الجذري): الفهارس الحارة بعد إنشاء الجداول كلها
          // — درس الجولة #426 الموثق: الاستدعاء الأول كان بعد فهرس
          // move_id وقبل دوال إنشاء جداول المستندات الخام ففشل كل
          // قاعدة جديدة بـ«no such table» — فوالقاعدة الجديدة تولد
          // بأدائها النهائي لا بفجوة بعد إنشاء كل ما تفهرسه.
          await _createHotDataIndexes();
          // p3: الملح يُزرع عند الإنشاء لا عند أول كتابة — فحالة
          // الإحكام صادقة من أول فتح (القاعدة الجديدة تُبلّغ مفعّلاً
          // بملحها المزروع وصفار أحداثها المختومة لا «الملح غائب»).
          await p3LogSalt();
          await _createLogGuards();
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
            // فآمنة التكرار أي كان مسار الوصول. وجداول الجرد تُبنى قبلها
            // إلزاماً منذ الدفعة 25 (س-19/D-186): حاجز الفترة صار يشمل
            // stock_counts فلا حاجز قبل جدوله — والبنية IF NOT EXISTS
            // فلا مساس بمسارات الترقية الأدنى ولا خطوة v16 بعدها.
            if (version == 9) {
              // الدفعة 26 (F-209/F-210): جدولا الإذنين يُبنيان هنا أيضاً
              // قبل الحواجز — درس الجرد الموثق (س-19/D-186): حاجز
              // المستند القيدي لا يسبق جدوله، والبنية IF NOT EXISTS
              // فلا مساس بمسارات أعلى ولا تكرار ضار.
              await _createCountTables();
              await _createMovementDocTables();
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
            // 13→14 (ومن إصدار أدنى مباشرة): دفعة (15) «ما قبل إغلاق
            // م1» (س-153/D-151) — خانة «ملاحظة التسليم» القصيرة على
            // السطر غير المستلم: عمود `delivery_note` نصي nullable
            // بـADD COLUMN بحرس pragma (نمط v12/v13 المجرّب) — فلا
            // إعادة بناء ولا قيم تُهجّر (كل القائمة بلا ملاحظة null
            // طبيعياً). وعلم عمل لا محاسبة نمط D-131: الحرس يجمّد
            // المال والبنية حصراً فملاحظة السطر تُحدّث على المرحّلة
            // بلا فك إقفال — ولا مساس بالقيود والمخزون والذمم.
            if (version == 14) {
              final lineCols14 = (await customSelect(
                      "SELECT name FROM pragma_table_info('invoice_lines')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!lineCols14.contains('delivery_note')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    'delivery_note TEXT NULL');
              }
            }
            // 14→15 (ومن إصدار أدنى مباشرة): الدفعة 24 — أولى م2
            // «تعدد المستودعات والتحويل بينها» (D-184/D-185، س-77):
            // جدولان جديدان خالصان SQL خاماً بنمط v7/v8 المجرّب
            // (آمنة التكرار بـIF NOT EXISTS ولا مساس بجداول قائمة) —
            // رأس تحويل بلا مسودة (يُنشأ مرحّلاً — س-18: الرفض قبل
            // الكتابة حصراً) وأسطره، ومُشغّلات تجميدهما (نمط F-140:
            // لقطة تاريخية لا تعدل ولا تحذف). بنية تعدد المستودعات
            // جاهزة منذ البداية (warehouses/stock_moves/stock_balances
            // بv7) فلا أعمدة على جداول قائمة هنا أصلاً.
            if (version == 15) {
              await _createTransferTables();
            }
            // 15→16 (ومن إصدار أدنى مباشرة): الدفعة 25 — الجرد وتسوياته
            // (س-19/F-046، س79/D-186): جدولان جديدان خالصان SQL خاماً
            // بنمط v7/v8/v15 المجرّب (آمنة التكرار بـIF NOT EXISTS ولا
            // مساس بجداول قائمة) — رأس جلسة جرد بحالة جارٍ/مرحّل وأسطره
            // بعدّاتها ولقطة الترحيل، ومُشغّلات تجميد المرحّل نمط F-140
            // وفهرس تفرد الصنف بالجلسة. وإعادة بناء حواجز الإقفال إلزامية
            // هنا: الجلسة تُرحّل قيداً محاسبياً فتاريخها تحكمه الفترة،
            // وحاجز stock_counts الجديد لا يولد إلا بـ_createClosingTriggers
            // التي لا تستدعى بالترقيات إلا بخطوتها (v9) — والبناء DROP+
            // CREATE فآمن التكرار أي كان مسار الوصول (درس v9 ذاته).
            if (version == 16) {
              await _createCountTables();
              await _createClosingTriggers();
            }
            // 16→17 (من إصدار أدنى مباشرة): الدفعة 26 — إذنا المخزون
            // (F-209/F-210، س85/D-189): أربعة جداول جديدة خالصة SQL
            // خاماً بنمط v15/v16 المجرّب (آمنة التكرار بـIF NOT EXISTS
            // ولا مساس بجداول قائمة) — رأس إذن إدخال وإذن إخراج بحالة
            // مرحّل فوراً (بلا مسودة — نمط س-18) وسبب نصي إلزامي وحساب
            // مقابل قابل للتغيير، وأسطرهما، ومُشغّلات تجميد المرحّل
            // نمط F-140. وإعادة بناء حواجز الإقفال إلزامية هنا: الإذن
            // يُرحّل قيداً محاسبياً فتاريخه تحكمه الفترة، وحاجزا
            // stock_receipts/stock_issues الجديدان لا يولدان إلا
            // بـ_createClosingTriggers — والبناء DROP+CREATE فآمن
            // التكرار أي كان مسار الوصول (درس v9 ذاته).
            if (version == 17) {
              await _createMovementDocTables();
              await _createClosingTriggers();
            }
            // 17→18 (ومن إصدار أدنى مباشرة): الدفعة 27 — مجموعات
            // التعبئة وأسعارها آلي (F-032/F-033/F-208، D-026/D-187):
            // ثلاثة جداول جديدة خالصة (المجموعات ومستوياتها وأسعار
            // الأصناف بالمستوى) يبنيها createAll بـIF NOT EXISTS ولا
            // مساس بجداول قائمة، وعمودا items الجديدان بحرس pragma
            // (درس v3 — آمن التكرار أي مسار وصول): unit_group_id NULL
            // وprice_auto NOT NULL DEFAULT 1 — فالقائمة القائمة تولد
            // آلياً مفعلاً (افتراض D-187) وبلا مجموعة.
            if (version == 18) {
              await m.createAll();
              final itemCols18 = (await customSelect(
                      "SELECT name FROM pragma_table_info('items')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!itemCols18.contains('unit_group_id')) {
                await customStatement(
                    'ALTER TABLE items ADD COLUMN unit_group_id INTEGER NULL');
              }
              if (!itemCols18.contains('price_auto')) {
                await customStatement(
                    'ALTER TABLE items ADD COLUMN price_auto INTEGER NOT NULL DEFAULT 1');
              }
            }
            // 18→19 (من إصدار أدنى مباشرة): الدفعة 28 — التجميعي الجاهز
            // والفكك (F-034/F-212): جدول الوصفة خالص يبنيه createAll
            // بـIF NOT EXISTS ولا مساس بجداول قائمة (نمط v18)، وعمود
            // «جاهز/فُكِّك» (F-034: التفصيل بعلم في الحركات) على
            // stock_moves بـADD COLUMN بحرس pragma (درس v3 — آمن
            // التكرار أي مسار وصول): NULL للحركات العادية و«ready»
            // لخروج الجاهز و«broken» لحركات مكونات الفكك.
            if (version == 19) {
              await m.createAll();
              final moveCols19 = (await customSelect(
                      "SELECT name FROM pragma_table_info('stock_moves')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!moveCols19.contains('move_detail')) {
                await customStatement(
                    'ALTER TABLE stock_moves ADD COLUMN move_detail TEXT NULL');
              }
            }
            // 19→20 (من إصدار أدنى مباشرة): الدفعة 29 — مستند التجميع
            // (F-211، س88): جدولان جديدان خالصان SQL خاماً بنمط
            // v15/v16/v17 المجرّب (آمنة التكرار بـIF NOT EXISTS ولا مساس
            // بجداول قائمة) — رأس تجميع مرحّل فوراً (بلا مسودة — نمط
            // س-18) بكمية الناتج وقيمتها الإجمالية، وأسطر مكوناته بلقطة
            // الكلفة، ومُشغّلات تجميد المرحّل نمط F-140. وبلا حاجز فترة
            // جديد إطلاقاً: التجميع بلا قيد محاسبي (F-211) فأرصدته حالية
            // لا تاريخية — عين قرار التحويل الموثق D-185 (س78) — فلا
            // إعادة بناء حواجز ولا بذر بخطوة v9 (درس v16 لا يُستدعى إلا
            // لحاجزٍ جديد).
            if (version == 20) {
              await _createAssemblyTables();
            }
            // 20→21 (من إصدار أدنى مباشرة): الدفعة 30 — لقطة الوحدة
            // والعامل (س-10/D-031، F-032): عمود unit_level_id على
            // invoice_lines بـADD COLUMN بحرس pragma (درس v3 — آمن
            // التكرار أي مسار وصول): NULL للإدخال بالوحدة الأساسية (كل
            // القائم) ومعرف مستوى التعبئة عند الإدخال بها، واللقطة
            // الثلاثية (unit_id للأساسية المرجعية + unit_level_id +
            // factor_at_entry بعامل المستوى وقت الإنشاء) مجمّدة بحرس
            // تجميد أسطر المرحّل المحدث — إعادة بناؤه DROP+CREATE
            // إلزامية هنا لأن CREATE IF NOT EXISTS لا تستبدل المشغل
            // القائم (نمط v9: البناء DROP+CREATE آمن التكرار أي مسار
            // وصول).
            if (version == 21) {
              final lineCols21 = (await customSelect(
                      "SELECT name FROM pragma_table_info('invoice_lines')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!lineCols21.contains('unit_level_id')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN unit_level_id INTEGER NULL');
              }
              await customStatement(
                  'DROP TRIGGER IF EXISTS trg_invoice_lines_frozen_update');
              await _createInvoiceTriggers();
            }
            // 21→22 (ومن إصدار أدنى مباشرة): الدفعة 32 — الإقفال السنوي
            // (س-21/F-077/D-068) بلا جداول ولا أعمدة جديدة: إعادة بناء
            // حواجز الإقفال DROP+CREATE بإعفاء قيود fiscal_year على
            // moves حصراً (نمط إعادة التعريف الموثق آمنة التكرار —
            // درس v9/v21). وCREATE IF NOT EXISTS لا يستبدل القائم
            // (درس v9 الموثق) فالـDROP إلزامي قبله.
            if (version == 22) {
              await _createClosingTriggers();
            }
            // 22→23 (ومن إصدار أدنى مباشرة): الدفعة 34 — تعدد العملات
            // الفعلي (F-120/F-121/F-124، D-194): جدول أسعار الصرف
            // التاريخية جديد خالص SQL خاماً بنمط v15..v20 (آمن التكرار
            // بـIF NOT EXISTS وتفرد (العملة، اليوم) داخل DDL — درس س86)
            // ومشغلات تجميد نمط F-140 — لا تعديل لسعر محفوظ أبداً.
            // وبلا أعمدة جديدة على جداول قائمة — بنية اللقطات على
            // المستندات قائمة من م1 (F-122/D-070) — ولا بذر بخطوة v9
            // إلزاماً (لا حاجز فترة جديد: الأسعار مرجع عملة لا مستند
            // قيدي — درس v16 لا يُستدعى إلا لحاجزٍ جديد).
            if (version == 23) {
              await _createExchangeRateTables();
            }
            // 23→24 (من إصدار أدنى مباشرة): أساس الأخطاء (قرار المالك
            // الخامس، س107) — (1) جدول error_log جديد خالص SQL خاماً
            // بنمط v15..v23 (آمن التكرار بـIF NOT EXISTS) معفًى من
            // اصطلاح «كل جدول» بعرف app_meta (D-055) — سجل تشخيص
            // append-only لا سجل أعمال. (2) تحديث نصوص حواجز القاعدة
            // القائمة برموزها DQ-xxxx: إعادة تعريف موثقة DROP+CREATE
            // (درس v9/v21/v22) بدوال الإنشاء ذاتها بترتيب onCreate
            // نفسه — فالحاجز الأخير هو النافذ. والترتيب حرصٌ لا
            // رفاهية: trg_cash_no_negative تُعرف بدالّتين (الفواتير
            // ثم السندات الأوسع) فالخاتمة يجب أن تبقى نسخة السندات.
            if (version == 24) {
              await _createErrorLogTable();
              await _createLedgerTriggers();
              await _createInvoiceTriggers();
              await _createVoucherTriggers();
              await _createTransferTables();
              await _createCountTables();
              await _createMovementDocTables();
              await _createAssemblyTables();
              await _createExchangeRateTables();
              await _createClosingTriggers();
            }
            // 24→25 (ومن إصدار أدنى مباشرة): س113 — لقطة الإدخال
            // بالتعبئة على أسطر الإذنين والتحويل (نمط v21 للفواتير):
            // ثلاثة أعمدة خالصة بـADD COLUMN بحرس pragma (درس v3 —
            // آمنة التكرار أي مسار وصول) وDDL الإنشاء نفسه حُدّث فقاعدة
            // الجديدة تولد بالأعمدة والقديمة ترقى بلا إعادة بناء —
            // والغائب إدخال بالأساسية كما اعتاد (NULL بلا مساس).
            if (version == 25) {
              for (final table in const [
                'stock_transfer_lines',
                'stock_receipt_lines',
                'stock_issue_lines',
              ]) {
                final cols = (await customSelect(
                        "SELECT name FROM pragma_table_info('$table')")
                      .get())
                    .map((r) => r.data['name'] as String)
                    .toSet();
                if (!cols.contains('unit_level_id')) {
                  await customStatement(
                      'ALTER TABLE $table ADD COLUMN unit_level_id INTEGER NULL');
                }
                if (!cols.contains('qty_doc')) {
                  await customStatement(
                      'ALTER TABLE $table ADD COLUMN qty_doc INTEGER NULL');
                }
                if (!cols.contains('factor_at_entry')) {
                  await customStatement(
                      'ALTER TABLE $table ADD COLUMN factor_at_entry INTEGER NULL');
                }
              }
            }
            // 25→26 (ومن إصدار أدنى مباشرة): س115 — الشطر الثاني من
            // حدّا الدفعة 30: لقطة العدّ بالتعبئة على أسطر الجرد ولقطة
            // الناتج بالتعبئة على رأس التجميع (الوصفة بالأساسية نص
            // F-211 ثابت) — نمط v25/v21 حرفاً: ثلاثة أعمدة خالصة
            // بـADD COLUMN بحرس pragma (درس v3 — آمنة التكرار أي مسار
            // وصول) وDDL الإنشاء نفسه حُدّث فقاعدة الجديدة تولد
            // بالأعمدة والقديمة ترقى بلا إعادة بناء — والغائب إدخال
            // بالأساسية كما اعتاد (NULL بلا مساس).
            if (version == 26) {
              for (final table in const [
                'stock_count_lines',
                'assemblies',
              ]) {
                final cols = (await customSelect(
                        "SELECT name FROM pragma_table_info('$table')")
                      .get())
                    .map((r) => r.data['name'] as String)
                    .toSet();
                if (!cols.contains('unit_level_id')) {
                  await customStatement(
                      'ALTER TABLE $table ADD COLUMN unit_level_id INTEGER NULL');
                }
                if (!cols.contains('qty_doc')) {
                  await customStatement(
                      'ALTER TABLE $table ADD COLUMN qty_doc INTEGER NULL');
                }
                if (!cols.contains('factor_at_entry')) {
                  await customStatement(
                      'ALTER TABLE $table ADD COLUMN factor_at_entry INTEGER NULL');
                }
              }
            }
            // 26→27 (ومن إصدار أدنى مباشرة): س121 — تفعيل طلبات البيع
            // والشراء (07 §3.2/D-026 بأمر المالك «أريد تفعيل طلبات
            // البيع والشراء»): جدولان جديدان خالصان بنمط دفعة الفواتير
            // (آمنة التكرار بـIF NOT EXISTS عبر createAll) — القلب
            // المحاسبي باقٍ لا مساس (نص 07 §3.2 الحاكم) — وعمود
            // المرجع `order_id` على الفواتير بـADD COLUMN بحرس pragma
            // (درس v3 — آمنة التكرار أي مسار وصول) فالغائب فاتورة حرة
            // كما كانت كلها قبل س121، وDDL الإنشاء نفسه حُدّث فقاعدة
            // الجديدة تولد بالعمود والقديمة ترقى بلا إعادة بناء،
            // والمُشغِّلات الحواجز تُبنى هنا لأي مسار وصول.
            if (version == 27) {
              await m.createAll();
              final invoiceCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('invoices')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!invoiceCols.contains('order_id')) {
                await customStatement(
                    'ALTER TABLE invoices ADD COLUMN order_id INTEGER NULL');
              }
              await _createOrderTables();
              await _createOrderTriggers();
            }
            // 27→28 (ومن إصدار أدنى مباشرة): p3 (س146 — خط التشفير
            // المرحلة الثالثة بجدول المستند الخامس): إحكام سجلي الأحداث
            // والأخطاء — بلا جداول ولا أعمدة جديدة فلا إعادة بناء:
            // (1) ملح اشتقاق مفتاح السجلات يُزرع أول مرة (16 بايتة
            // عشوائية hex بالSQL randomblob — عتاد القاعدة ذاتها لا
            // دارت)، (2) سجلات ما قبل v28 تُختَم موقعياً (حمولة الأحداث
            // ورسائل الأخطاء وسياقها) قبل إنشاء الحواجز — فالترحيلة
            // تستعمل UPDATE بلا مساس ثم يقفل الباب بعدها، (3) شرائب
            // الحاجز الرباعي: BEFORE UPDATE/DELETE على السجلين يرفضان
            // بأمر صريح فانضباط append-only الموثق (D-067/07 §2.3)
            // يصير عتاداً لا عادة كود.
            if (version == 28) {
              await customStatement(
                  "INSERT OR IGNORE INTO app_meta (key, value) "
                  "VALUES ('$p3LogSaltMetaKey', lower(hex(randomblob(16))))");
              // مسار الوصول الهجين: حاجزٌ قائم من جلسة سابقة لا يسد
              // ختم القائمة — الدروب قبل الختم حصراً (نمط س107).
              await _dropLogGuards();
              await _sealLegacyLogRows();
              await _createLogGuards();
            }
            // 28→29 (ومن إصدار أدنى مباشرة): د0 (س160 — أولى خارطة م4
            // 09 §46): فهرس move_id على move_lines — المرشح الموثق س156
            // يصير مخططاً بترحيلة مخططية واحدة: CREATE INDEX آمن
            // التكرار بـIF NOT EXISTS فأي مسار وصول يعمل، ولا جداول
            // ولا أعمدة ولا إعادة بناء ولا مساس بالبيانات — والفهرس
            // يخفض فحص توازن كل قيد (زنادا DQ-0101/0102) من مسح كامل
            // للجدول إلى بحث بالمؤشر، فهو شرط قياس عينة م4 الكاملة
            // (م-٤: «كل دفعة تُقاس على أداء معلوم»).
            if (version == 29) {
              await _createMoveLinesIndex();
            }
            // 29→30 (س164): إلحاق بوابة «ترحيل مسودات الآخرين» بمن كان
            // يعتمد سلفاً — ترحيلة بيانات لا مخطط: دورٌ قائم غير النجمة
            // وحامل وحدة الفواتير وغير الأدوار البيعية بالاسم (بائع/
            // مندوب — كان حجبُهما بالاسم س101 ولا بوابة لهما) يُلحق
            // مفتاحُها فرعياً بقائمة أذوناته، والحامل للبوابة أصلاً
            // يُسقط بـNOT LIKE فآمنة التكرار أي كان مسار الوصول
            // (v29→30 أو أصغر مباشرة). والقائمة الفارغة والنجمة لا
            // تُمسان: النجمة تشمل البوابة أصلاً، والفارغة بلا فواتير.
            if (version == 30) {
              await customStatement(
                "UPDATE roles SET permissions = permissions "
                "|| ',invoices.post_others', updated_at = ? "
                'WHERE is_deleted = 0 AND permissions <> \'*\' '
                "AND permissions LIKE '%invoices%' "
                "AND permissions NOT LIKE '%invoices.post_others%' "
                "AND name NOT IN ('بائع', 'مندوب')",
                [DateTime.now().millisecondsSinceEpoch],
              );
            }
            // 30→31 (ومن إصدار أدنى مباشرة): د3 (س170/D-188) — كل حدث
            // يحمل company_id: عمود واحد بdefault الشركة الافتراضية
            // الواحدة 'main' بADD COLUMN بحرس pragma (درس v3 — آمنة
            // التكرار أي مسار وصول) فالصفوف القائمة تملأ بلا كتابة
            // ولا إعادة بناء ولا مساس، والقاعدة الجديدة تولد بالعمود
            // من DDL drift ذاته، والكتابة بقيم غير الافتراضية مع
            // إدارة التعدد (F-112) والعزل للخادم مع أول مهايئ (د4).
            if (version == 31) {
              final eventCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('events')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!eventCols.contains('company_id')) {
                await customStatement(
                    "ALTER TABLE events ADD COLUMN company_id TEXT NOT NULL "
                    "DEFAULT 'main'");
              }
            }
            // 31→32 (ومن إصدار أدنى مباشرة بحلقة الترقية): د6 (س175) —
            // المتابعات اليومية (س74/D-184 بلفظ المالك): عمودا الحد
            // الأدنى على الأصناف ومدة السداد على الأطراف، كلٌّ بADD
            // COLUMN nullable بحرس pragma (نمط v31 — آمنة التكرار أي
            // مسار وصول) فالصفوف القائمة تملأ null بلا كتابة ولا إعادة
            // بناء ولا مساس، والغائب مصدر صامت بالمتابعات، والكتابة
            // بقيم غير الافتراضية من النموذجين الجديدين.
            if (version == 32) {
              final itemCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('items')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!itemCols.contains('min_qty')) {
                await customStatement(
                    'ALTER TABLE items ADD COLUMN min_qty INTEGER NULL');
              }
              final partyCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('parties')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!partyCols.contains('payment_term_days')) {
                await customStatement(
                    'ALTER TABLE parties ADD COLUMN '
                    'payment_term_days INTEGER NULL');
              }
            }
            // 32→33 (ومن إصدار أدنى مباشرة بحلقة الترقية) (س181 —
            // إعادة تأسيس تنظيف الرموز، أصله س166 المفقودة على قاعدة
            // قديمة): إعادة تعريف موثقة لنصوص الحواجز بلا مخطط ولا
            // بيانات — دوال الإنشاء كلها بـDROP داخلي (درس س107)
            // فالاستدعاء يستبدل النصوص القديمة بنصوصها المرقّمة
            // المنزّعة الإحالات ويرمّز حواجز الإلحاق الرباعية
            // (DQ-1119..1122) على أي قاعدة قائمة أي كان مسار وصولها.
            if (version == 33) {
              await _createInvoiceTriggers();
              await _createVoucherTriggers();
              await _createTransferTables();
              await _createCountTables();
              await _createExchangeRateTables();
              await _createMovementDocTables();
              await _createLogGuards();
            }
            // 33→34 (ومن إصدار أدنى مباشرة بحلقة الترقية) (س211/D-216):
            // راية إلزام تغيير الكلمة على المستخدمين — ADD COLUMN بحرس
            // pragma (نمط v31/v32 — آمنة التكرار أي مسار وصول) والافتراضي
            // صفر فالصفوف القائمة (المدير البذري ومن قبله) باقية كما هي
            // بلا كتابة ولا إعادة بناء، والراية تُرفع عند الولادة بcreateUser
            // حصراً وفنجانها بchangeOwnPassword عند النجاح حصراً.
            if (version == 34) {
              final userCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('app_users')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!userCols.contains('must_change_password')) {
                await customStatement(
                    'ALTER TABLE app_users ADD COLUMN '
                    'must_change_password INTEGER NOT NULL DEFAULT 0');
              }
            }
            // 34→35 (ومن إصدار أدنى مباشرة بحلقة الترقية) (س215 —
            // الثقل الجذري للبيانات الضخمة): فهارس طرق الوصول الحارة
            // دفعة واحدة — CREATE INDEX آمن التكرار بـIF NOT EXISTS
            // فأي مسار وصول يعمل، ولا جداول ولا أعمدة ولا إعادة
            // بناء ولا مساس بالبيانات — وعرف v29 (د0): كل فهرس
            // يستبدل مسحاً كاملاً للجدول بحثاً بالمؤشر في مسارات
            // فحص الثوابت الافتتاحي وأرصدة الحسابات والصناديق
            // وقوائم المستندات وقراءة أسطرها.
            if (version == 35) {
              await _createHotDataIndexes();
            }
            // 35→36 (ومن إصدار أدنى مباشرة): س227 (المرحلة صفر د3 —
            // قفل محاولات الدخول المتدرج): عمودان على app_users بADD
            // COLUMN بحرس pragma (درس v3 — آمنة التكرار أي كان مسار
            // الوصول) فالصفوف القائمة تملأ بالافتراضي صفراً ولا إعادة
            // بناء ولا مساس بالبيانات، والقاعدة الجديدة تولد بهما من
            // DDL drift ذاته.
            if (version == 36) {
              final userCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('app_users')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!userCols.contains('failed_login_attempts')) {
                await customStatement(
                    'ALTER TABLE app_users ADD COLUMN '
                    'failed_login_attempts INTEGER NOT NULL DEFAULT 0');
              }
              if (!userCols.contains('locked_until')) {
                await customStatement(
                    'ALTER TABLE app_users ADD COLUMN '
                    'locked_until INTEGER NOT NULL DEFAULT 0');
              }
            }
            // 36→37 (ومن إصدار أدنى مباشرة): س227 (المرحلة صفر د4 —
            // بوابة القوائم المالية الفرعية): ترحيلة بيانات بنمط v30
            // حرفاً — إلحاق reports.financials بكل دور قائم يعتمد
            // التقارير (لا النجمة ولا أمين المستودع المخصوص بالاسم
            // «تقارير المخزون حصراً» بقرار المالك — وحجبه بالاسم
            // سابقة v30 بالبائع والمندوب) عرف «من كان يعتمد يبقى
            // يعتمد» فلا يفقد محاسبٌ قائمةً بترقية البوابة، والنجمة
            // تشمل البوابة أصلاً، والحامل لها يُسقط بNOT LIKE فآمنة
            // التكرار أي كان مسار الوصول.
            if (version == 37) {
              await customStatement(
                "UPDATE roles SET permissions = permissions "
                "|| ',reports.financials', updated_at = ? "
                'WHERE is_deleted = 0 AND permissions <> \'*\' '
                "AND permissions LIKE '%reports%' "
                "AND permissions NOT LIKE '%reports.financials%' "
                "AND name <> 'أمين مستودع'",
                [DateTime.now().millisecondsSinceEpoch],
              );
            }
            // 37→38 (ومن إصدار أدنى مباشرة): س236 (د10 البنوك D-224):
            // أعمدة النوع والبنك على الصناديق بحرس pragma (آمنة التكرار
            // أي كان مسار الوصول) وجدول التسويات البنكية الخالص.
            if (version == 38) {
              final boxCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('cash_boxes')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!boxCols.contains('kind')) {
                await customStatement(
                    "ALTER TABLE cash_boxes ADD COLUMN "
                    "kind TEXT NOT NULL DEFAULT 'cash'");
              }
              if (!boxCols.contains('bank_name')) {
                await customStatement(
                    'ALTER TABLE cash_boxes ADD COLUMN '
                    'bank_name TEXT NULL');
              }
              if (!boxCols.contains('account_number')) {
                await customStatement(
                    'ALTER TABLE cash_boxes ADD COLUMN '
                    'account_number TEXT NULL');
              }
              await _createBankReconciliationTableTx();
            }
            // 38→39 (ومن إصدار أدنى مباشرة): س237 (المرحلة ج D-235):
            // أعمدة السطر الحر والملاحظة على أسطر الفواتير بحرس
            // pragma (آمنة التكرار أي كان مسار الوصول).
            if (version == 39) {
              final lineCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('invoice_lines')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!lineCols.contains('is_free')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    "is_free INTEGER NOT NULL DEFAULT 0");
              }
              if (!lineCols.contains('description')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    'description TEXT NULL');
              }
              if (!lineCols.contains('note')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    'note TEXT NULL');
              }
            }
          }
        },
        // F-156: التطبيق الأقدم يرفض قاعدة أحدث مخططاً برسالة «حدّث التطبيق»
        // — باب الاستعادة يفحصها قبل الاستبدال (prepareRestore)، وهذا باب
        // الفتح نفسه. drift يمرر التراجع (9→2) في onUpgrade نفسه فلا
        // تنفذ حلقتنا — والحرس أدناه يرفض قبل أي استخدام.
        // وس101 تضيف بعده ضمان الأدوار النمطية (بذرُ صفوفٍ بيانٌ لا
        // مخطط، فاحصُ الفراغ بالاسم آمنُ التكرار): أي دور نمطي يُضاف
        // إلى defaultRolesPermissions مستقبلاً يُزرع أول فتح لأي قاعدة
        // قائمة بلا ترحيلة — وv24 تبقى محجوزة لأساس الأخطاء بقرار
        // المالك (خريطة الحالة §١).
        beforeOpen: (details) async {
          if ((details.versionBefore ?? 0) > schemaVersion) {
            throw const DiqqahNewerSchemaException();
          }
          await ensureDefaultRoles();
          // س104: الحساب الوسيط «تحصيلات في الطريق» (116) — بذرُ بيانٍ لا
          // مخطط بعرف الأدوار س101: فاحص الفراغ بالكود آمن التكرار، وأي
          // قاعدة قائمة (أو جديدة) تضمن حسابَها أول فتح بلا ترحيلة،
          // وv24 تبقى محجوزة لأساس الأخطاء بقرار المالك.
          await ensureTransitAccount();
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

  /// س107 (أساس الأخطاء): تسجيل خطأ بالسجل التشخيصي — أقصى جهد لا
  /// حاجز: فشل التسجيل ذاته (قاعدة مقفلة/قرص ممتلئ) لا يفشل التدفق
  /// الذي استدعاه أبداً، فالتسجيل خدمة التشخيص لا شرط العمل.
  /// الرمز DQ-xxxx من سلطة الترقيم بالمجال (error_codes.dart) عبر
  /// خرائط التحقق، والرسالة نص الاستثناء الحقيقي كما ظهر.
  /// p3 (س146): الرسالة والسياق يُختمان قبل الكتابة (AES-256-GCM
  /// لكل سجل) — فسجل الأخطاء نص صريحَه النصُ الأخطر (سياق التشغيل
  /// وقد يحمل بيانات مالية)، والرمز DQ-xxxx يبقى خاماً للفهرسة
  /// والعرض بلا فك.
  Future<void> logError({
    required String code,
    required String message,
    String? context,
  }) async {
    try {
      await customStatement(
        'INSERT INTO error_log (code, message, context, created_at) '
        'VALUES (?, ?, ?, ?)',
        [
          code,
          await sealLogText(message),
          context == null ? null : await sealLogText(context),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    } catch (_) {
      // أقصى جهد — لا حاجز (تعاقد الدالة الموثق أعلاه).
    }
  }

  /// س107: آخر سجلات الأخطاء — الأحدث أولاً (فهرس created_at DESC).
  /// صفوف خاماً (code/message/context/created_at/id) لشاشة التشخيص.
  /// p3: الرسالة والسياق يُفكّان للعرض — والخام بلا بادئة يمر كما
  /// هو (توافق سجلات ما قبل الإحكام)، والعابث يكسر وسم GCM فالصف
  /// يُعرض برسالة DQ-1108 بدل نصه — فالفاسد كالغائب (D-169) لا
  /// فساد صامت ولا انهيار شاشة.
  Future<List<Map<String, Object?>>> recentErrors({int limit = 50}) async {
    final rows = await customSelect(
      'SELECT id, code, message, context, created_at FROM error_log '
      'ORDER BY id DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();
    return [
      for (final r in rows)
        {
          ...r.data,
          'message': await _openLogTextOrIntegrity(r.data['message'] as String),
          'context': r.data['context'] == null
              ? null
              : await _openLogTextOrIntegrity(r.data['context'] as String),
        },
    ];
  }

  /// p3: فك نص سجل للعرض — التلف يعرض برسالة DQ-1108 لا استثناء.
  Future<String> _openLogTextOrIntegrity(String text) async {
    try {
      return await openLogText(text);
    } on LogCipherIntegrityException {
      return 'سجل مشفر تالف أو مُعبث به (DQ-1108)';
    }
  }

  /// س107: عدد سجلات الأخطاء الحالي — بطاقة شاشة التشخيص.
  Future<int> errorLogCount() async {
    final rows =
        await customSelect('SELECT COUNT(*) AS c FROM error_log').get();
    return (rows.first.data['c'] as int? ?? 0);
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

  /// س211 (D-216 — الضابط الخامس «أقل امتياز عند الولادة»): إنشاء
  /// مستخدم جديد بيد صاحب بوابة «users.create» — الوليد أعري بنيوياً:
  /// دور «مستخدم» (kBareUserRoleName) القائم بلا أي وحدة فالسقف الإذني
  /// صفر لا بالثقة، والراية must_change_password مرفوعة فتُلزَم بتغيير
  /// كلمته عند أول جلسة، وتعيين أدواره لاحقاً بباب «الصلاحيات» القائم
  /// بحدوده — فلا تصعيد بالإنشاء أصلاً. دور الولادة يُضمن هنا فاحص
  /// الفراغ بالاسم (نمط createManager/ensureDefaultRoles — آمن التكرار
  /// أي مسار وصول)، وتفرد الدخول قيد قاعدة البيانات ذاته (UNIQUE)
  /// فيُرفض التكرار استثناءً تلتقطه الواجهة. والحدث بنظام الأحداث
  /// (عرف p3) بهوية الفاعل من الجلسة وحمولة الوليد.
  Future<int> createUser({
    required String name,
    required String login,
    required String passwordHash,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final bare = await (select(roles)
          ..where((t) => t.name.equals(kBareUserRoleName)))
        .getSingleOrNull();
    final roleId = bare != null
        ? bare.id
        : await into(roles).insert(
            RolesCompanion.insert(
              name: kBareUserRoleName,
              permissions: const Value(''),
              uuid: const Uuid().v4(),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    final id = await into(appUsers).insert(
      AppUsersCompanion.insert(
        name: name,
        login: login,
        passwordHash: passwordHash,
        roleId: roleId,
        isActive: true,
        mustChangePassword: const Value(true),
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await recordSystemEvent(
      'user_created',
      userId: await currentUserId(),
      payload: <String, Object?>{
        'new_user_id': id,
        'login': login,
        'role': kBareUserRoleName,
      },
    );
    return id;
  }

  /// س211 (D-216): التعطيل والتفعيل بطي is_active حصراً — لا حذف
  /// فيزيائي (عرف س-33) وأرشفةُ المستخدم تعقب أثريه القيدي. الحمايات
  /// الثلاثة المعتمدة: الجلسة الحالية لا تُعطَّل بيدها (التبديل هو
  /// الخروج المعتمد)، وآخر مستخدم نشط لا يُعطَّل فلا إقفال خارجي للبرنامج
  /// كله، ومستخدمُ دورٍ كامل الوحدات لا يُمس بيدٍ غير كاملة الوحدات
  /// (سقف التصعيد) — والحدث بنظام الأحداث بهوية الفاعل وحالته الهدف.
  Future<void> setUserActive(int userId, bool active) async {
    final target = await (select(appUsers)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (target == null) {
      throw StateError('المستخدم المطلوب غير موجود');
    }
    if (!active) {
      if (userId == await currentUserId()) {
        throw StateError('لا تعطيل للجلسة الحالية — بدّل المستخدم أولاً');
      }
      final actives = await (select(appUsers)
            ..where((t) =>
                t.isActive.equals(true) & t.isDeleted.equals(false)))
          .get();
      if (actives.length <= 1 && actives.any((u) => u.id == userId)) {
        throw StateError('آخر مستخدم نشط لا يُعطّل');
      }
      final targetRole = await roleOf(target);
      if (targetRole != null &&
          RolePermissions(targetRole.permissions).isAll) {
        final actor = await currentUser();
        final actorRole = actor == null ? null : await roleOf(actor);
        if (actorRole == null ||
            !RolePermissions(actorRole.permissions).isAll) {
          throw StateError('تعطيل مستخدم بكامل الوحدات بيدٍ غير كاملة '
              'الوحدات مرفوض');
        }
      }
    }
    await (update(appUsers)..where((t) => t.id.equals(userId))).write(
      AppUsersCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    final actor = await currentUser();
    await recordSystemEvent(
      'user_active_toggled',
      userId: actor?.id,
      payload: <String, Object?>{'target': userId, 'active': active},
    );
  }

  /// س211 (D-216 — الضابط الثالث تكملة): تغيير الكلمة الذاتي — التحقق
  /// بالكلمة الحالية حصراً (لا جلسة بلا تحقق D-100) وفنجانُ الراية
  /// must_change_password عند النجاح حصراً فلا إلزام يتيمة، والهاش
  /// الجديد بالصيغة الذاتية الوصف (UI يصوغه بPasswordHasher بنمط
  /// first_run) والحدث بنظام الأحداث.
  Future<void> changeOwnPassword({
    required int userId,
    required String currentPassword,
    required String newPasswordHash,
  }) async {
    final user = await (select(appUsers)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (user == null || !user.isActive) {
      throw StateError('المستخدم غير موجود أو معطل');
    }
    // س219: التحقق بعزل الخلفية — 600,000 تكراراً بنوى دارت الخالصة
    // كانت تجمّد خيط الواجهة كاملاً مهما كانت الشاشة (القياس الحي
    // b73: 4.69 ثانية على الجهاز المنخفض)، والعقد الإرسالي س218
    // بالمدار ذاته: الإغلاق قيم بسيطة قابلة للإرسال حصراً.
    if (!await PasswordHasher.verifyStoredInBackground(
        user.passwordHash, currentPassword)) {
      throw StateError('كلمة المرور الحالية غير صحيحة');
    }
    await (update(appUsers)..where((t) => t.id.equals(userId))).write(
      AppUsersCompanion(
        passwordHash: Value(newPasswordHash),
        mustChangePassword: const Value(false),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    await recordSystemEvent('user_password_changed', userId: user.id);
  }

  // ═══════════════════════════════════════════════════════════════
  // س212 (دفعة 2 من خطة الجلسة والمستخدمين — D-215/U-005): آلة
  // الحالتين وبوابة الجهاز — الراية المحفوظة في app_meta.
  // ═══════════════════════════════════════════════════════════════

  /// راية حالة الجلسة بمفتاح app_meta — الحالتان المعتمدتان لا ثلاثة:
  /// الغائب «نشط داخل الجلسة» (توافق تثبيتات س211 السابقة بلا راية
  /// فلا إقلاع مقفلاً بعد الترقية)، والمكتوبة '1' «مقفلة خارج الجلسة»
  /// فالإقلاع يعرض بوابة الجهاز لا الرئيسية. الراية بالقاعدة نفسها
  /// فلا ثقب عودة مفتوحة بعد موت العملية — إعادة التشغيل تجدها مقفلة
  /// بعرف ق-ن1-أ (نمط مفتاح بوابة الاستعادة restore.gate).
  static const String sessionLockedMetaKey = 'session_locked';

  /// الحالة الحالية للجلسة — true: مقفلة خارج الجلسة (بوابة الجهاز
  /// هي الوجه)، false: نشطة داخل الجلسة (الرئيسية كما كانت).
  Future<bool> sessionLocked() async =>
      (await metaValueOf(sessionLockedMetaKey)) == '1';

  /// مصدر القفل في حمل الحدث — يدويًا بزر الشارة («manual»)، أو
  /// خمولاً بعد انقضاء مدة D-217 («idle»)، أو قفلًا فوريًا عند
  /// مغادرة التطبيق («app_left»): تتبّع تدقيق يفرّق فعل صاحب الجلسة
  /// عن فعل الحارس الآلي دون أي مساس بأسماء الأحداث الثلاثة.
  static const List<String> sessionLockVias = ['manual', 'idle', 'app_left'];

  /// الفعل الأول «القفل» — الانتقال نشطة→مقفلة بفتح سريع لنفس
  /// المستخدم: الراية تُكتب أولاً (فأي موت للعملية بعد هنا يفتح
  /// بوابة الجهاز لا الرئيسية) والمستخدم الحالي يبقى مستأنفاً فبلاطته
  /// بالبوابة مختارة بلسان الفتح السريع، والحدث بهوية الفاعل. القفل
  /// وجهة الفعلَين «القفل» و«التبديل» معاً (D-215: التبديل قفلٌ ثم
  /// بلاطة أخرى تُختار بالبوابة ذاتها).
  Future<void> lockSession({String via = 'manual'}) async {
    final actor = await currentUser();
    await upsertMetaValue(sessionLockedMetaKey, '1');
    await recordSystemEvent(
      'session_locked',
      userId: actor?.id,
      payload: <String, Object?>{'resumable_user_id': actor?.id, 'via': via},
    );
  }

  /// الفعل الثالث «الخروج» — قفل بلا مستخدم مستأنف: الراية تُكتب
  /// أولاً ثم يُمسى المستخدم الحالي فبوابة الجهاز بلا بلاطة فتح
  /// سريع ولا جلسة مستأنفة، والحدث بهوية الفاعل المنصرف.
  Future<void> logoutSession() async {
    final actor = await currentUser();
    await upsertMetaValue(sessionLockedMetaKey, '1');
    await setCurrentUserId(null);
    await recordSystemEvent('session_logged_out', userId: actor?.id);
  }

  /// الانتقال مقفلة→نشطة نصفه الأول: التحقق بكلمة البلاطة المختارة
  /// حصراً (لا جلسة بلا تحقق D-100) وتعيين صاحب الجلسة القادم.
  /// المعطل والكلمة الخاطئة يُرفضان بعقد verifyUserPassword ذاته.
  /// **والراية باقية مقفلة** فلا ثقب عودة إن ماتت العملية قبل اكتمال
  /// إلزام تغيير الكلمة لصاحب الراية (must_change_password) —
  /// الواجهة تُكمل الانتقال بopenSession بعد الحوار الإلزامي حصراً
  /// (ولمَن لا راية عليه فوراً) فيُعاد عند أي موت للبوابة لا لرئيسية.
  Future<AppUser> resumeSession({
    required int userId,
    required String password,
  }) async {
    // س227 — الفحص قبل التحقق (قفل المحاولات المتدرج): المستخدم
    // المقفل يفشل فوراً بموازنة توقيت (س219) فلا قناة توقيتية تكشف
    // حالة القفل قبل كلفة التحقق.
    final lock = await loginLockoutRemaining(userId);
    if (lock != null) {
      await PasswordHasher.equalizingWorkInBackground(
          iterations: passwordUpgradeIterations);
      throw StateError(
          'الدخول مقفل مؤقتاً بعد محاولات فاشلة — أعد المحاولة بعد '
          '${loginLockoutMinutesText(lock)}');
    }
    final user = await verifyUserPassword(userId, password);
    if (user == null) {
      await bumpFailedLoginAttempts(userId);
      throw StateError('كلمة المرور غير صحيحة أو المستخدم معطل');
    }
    await resetFailedLoginAttempts(user.id);
    await setCurrentUserId(user.id);
    await recordSystemEvent(
      'session_resumed',
      userId: user.id,
      payload: <String, Object?>{'via': 'device_gate'},
    );
    return user;
  }

  /// س216 (بند الدخول اليدوي بأمر المالك «قائمة أسماء المستخدمين التي
  /// لا زالت موجودة» ثانياً): الانتقال مقفلة→نشطة بمن يدخل اسمَ دخوله
  /// بنفسه حصراً — لا تعداد أسماء على البوابة عرف تطبيقات المصادقة
  /// الكبيرة (OWASP: لا معرفة حساباتٍ من شاشة الدخول). البحث بlogin
  /// (العمود فريد بالمخطط) مطابقةً غير حساسة لحالة اللاتينية، وكل
  /// الفشل (اسم مجهول/معطل/كلمة خاطئة) يُرمى برسالة واحدة عامة
  /// «بيانات الدخول غير صحيحة» حصراً فلا تمييز معلوماتي يغري تجريب
  /// الأسماء — والتفصيل الحقيقي في سجل الأخطاء المحلي بيد صاحب الجهاز
  /// (الواجهة تعرض العامة لا الاستثناء الخام بنمط dqTag السابق).
  /// النجاح بعقد resumeSession ذاته: تعيين صاحب الجلسة وحدث
  /// session_resumed والراية باقية مقفلة حتى openSession حصراً.
  Future<AppUser> resumeSessionByLogin({
    required String login,
    required String password,
  }) async {
    const generic = 'بيانات الدخول غير صحيحة';
    final user = await (select(appUsers)
          ..where((t) => t.login.lower().equals(login.trim().toLowerCase())))
        .getSingleOrNull();
    // س227 — الفحص قبل التحقق (قفل المحاولات المتدرج بموازنة توقيت
    // س219): القفل الوحيد الذي يخرق الرسالة الموحدة س216 — فهو لا
    // يكشف وجود حسابٍ غيبه المجهول بل حالة حسابٍ عرفه صاحبه دخولاً
    // ويحتاج إخبار مدته المتنقية، وهذا قرار المالك الموثق.
    if (user == null) {
      // س219 — موازنة التوقيت: الفشل بلا حساب كان يُرد بالملي ثانية
      // بينما كلمة خاطئة بحساب قائم بثوانٍ (600,000 تكراراً) فالرسالة
      // الموحدة س216 كانت تُكسر بالساعة — قناة تعداد توقيتية رغم النص
      // الموحد. عمل الموازنة بكلفة تكرارات الجيل الحالي قبل الرمي
      // يجعل الفشلين بكلفة واحدة فلا تمييز توقيتي يغري تجريب الأسماء
      // (الحكم الصادق: سجلات الإرث غير المرقّى أسرع حلم موثق يُرقّى
      // آلياً عند أول دخول ناجح بعقد verifyUserPassword).
      await PasswordHasher.equalizingWorkInBackground(
          iterations: passwordUpgradeIterations);
      throw StateError(generic);
    }
    // س227 — الفحص قبل التحقق (قفل المحاولات المتدرج بموازنة توقيت
    // س219): القفل الوحيد الذي يخرق الرسالة الموحدة س216 — فهو لا
    // يكشف وجود حسابٍ غيبه المجهول بل حالة حسابٍ عرفه صاحبه دخولاً
    // ويحتاج إخبار مدته المتنقية، وهذا قرار المالك الموثق.
    final lock = await loginLockoutRemaining(user.id);
    if (lock != null) {
      await PasswordHasher.equalizingWorkInBackground(
          iterations: passwordUpgradeIterations);
      throw StateError(
          'الدخول مقفل مؤقتاً بعد محاولات فاشلة — أعد المحاولة بعد '
          '${loginLockoutMinutesText(lock)}');
    }
    final verified = await verifyUserPassword(user.id, password);
    if (verified == null) {
      // س227 — الفشل يرفع عداد القفل المتدرج (المجهول أعلاه بلا
      // عداد فلا قفل بحساب وهمي) والرسالة الموحدة س216 باقية حرفاً.
      await bumpFailedLoginAttempts(user.id);
      throw StateError(generic);
    }
    await resetFailedLoginAttempts(verified.id);
    await setCurrentUserId(verified.id);
    await recordSystemEvent(
      'session_resumed',
      userId: verified.id,
      payload: <String, Object?>{'via': 'device_gate'},
    );
    return verified;
  }

  /// الانتقال مقفلة→نشطة نصفه الثاني — إزالة الراية بعد اكتمال شروط
  /// بدء الجلسة (والحوار الإلزامي لصاحب الراية قبله حصراً بعقد
  /// D-216 الضابط الثالث) فتعود الرئيسية بصاحبها الجديد.
  Future<void> openSession() async {
    await (delete(appMeta)
          ..where((t) => t.key.equals(sessionLockedMetaKey)))
        .go();
  }

  // ═════════════════════════════════════════════════════════════
  // س213 (دفعة 3 من خطة الجلسة والمستخدمين — D-217): الخمول إعداد
  // جهاز في قسم «البيانات والأمان» والبيومتري للفتح السريع للمعلق
  // فقط — إعداد وفتح بلا ترحيلة (v34 الباقية) بعرف س212.
  // ═════════════════════════════════════════════════════════════

  /// مدة الخمول قبل القفل الآلي — مفتاح app_meta (إعداد جهاز لا
  /// ترحيلة: القاعدة نفسها تحمله فلا ينجو بموت العملية بنمط الراية).
  /// المستويات المغلقة الموثقة بD-217 حصراً فلا حقل حر ولا «أبداً»
  /// (حدّا F-147 السابقان انتقلا بعقد D-217 الأحدث — الحد الصادق
  /// موثق بسجل العمل)، والافتراض 10 دقائق حسمُ F-147 الموثق.
  static const String sessionIdleMinutesMetaKey = 'session_idle_minutes';
  static const List<int> sessionIdleMinuteChoices = [1, 5, 10, 15, 30];
  static const int sessionIdleMinutesDefault = 10;

  /// مدة الخمول النافذة — الغائب أو الفاسد يعود الافتراض 10 (نمط
  /// القراءات المحمية الموثقة: الفاسد يعيد الافتراضي لا يكسر).
  Future<int> sessionIdleMinutes() async {
    final raw = await metaValueOf(sessionIdleMinutesMetaKey);
    final parsed = raw == null ? null : int.tryParse(raw);
    if (parsed == null ||
        !sessionIdleMinuteChoices.contains(parsed)) {
      return sessionIdleMinutesDefault;
    }
    return parsed;
  }

  /// كتابة المدة — المستويات المغلقة حصراً فلا قيمة يخترعها
  /// منوّب، والرفض برسالة عربية بعرف الحمايات الموثقة.
  Future<void> setSessionIdleMinutes(int minutes) async {
    if (!sessionIdleMinuteChoices.contains(minutes)) {
      throw StateError(
          'مدة الخمول من المستويات المعتمدة حصراً — 1 أو 5 أو 10 أو 15 أو 30 دقيقة');
    }
    await upsertMetaValue(
        sessionIdleMinutesMetaKey, minutes.toString());
  }

  // ═════════════════════════════════════════════════════════
  // س227 (المرحلة صفر د3 من خارطة طريق التقرير الاستشاري — بأمر
  // المالك «ابدأ التنفيذ» وباستثناء صريح لحد أدنى لكلمة المرور):
  // قفل محاولات الدخول المتدرج بالقاعدة — الحال على صف المستخدم
  // (app_users) فتنجو بموت العملية بعقد آلة الحالتين (س212)،
  // والمستويات مغلقة بنمط مستويات الخمول (D-217)، والفحص قبل
  // التحقق من الكلمة بموازنة توقيت (س219) فلا قناة تعداد
  // توقيتية تكشف حالة القفل، وverifyUserPassword نفسه بلا مساس
  // فبوابة الاستعادة (تستدعيه) لا يقفلها عدّاد الدخول.
  // ═════════════════════════════════════════════════════════

  /// عتبة القفل ودرجاته المغلقة — كل خمس محاولات فاشلة عتبة تقفل
  /// بمدة مستواها من القائمة، وكل عتبة تالية ترفع المدة درجة حتى
  /// سقف 30 دقيقة (متدرج لا نهائي التكرار).
  static const int loginLockoutMaxAttempts = 5;
  static const List<int> loginLockoutMinuteSteps = [1, 5, 15, 30];

  /// المدة المتبقية للقفل — صفر يعني غير مقفل، والمستخدم المجهول
  /// يعود صفراً فلا قفل لمجهول (الرسالة العامة س216 تحرسه).
  Future<Duration?> loginLockoutRemaining(int userId) async {
    final user = await (select(appUsers)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (user == null) return null;
    final remainingMs =
        user.lockedUntil - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return null;
    return Duration(milliseconds: remainingMs);
  }

  /// محاولة فاشلة — يزيد العداد ويقفل عند العتبات بمستواها المتدرج
  /// ويسجل حدث التدقيق (login_lockout) بحمولة العدد والمدة — سجل
  /// الأحداث ملحق فقط فالعداد على صف المستخدم حصراً.
  Future<void> bumpFailedLoginAttempts(int userId) async {
    final user = await (select(appUsers)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (user == null) return;
    final attempts = user.failedLoginAttempts + 1;
    var lockedUntil = user.lockedUntil;
    final level = attempts ~/ loginLockoutMaxAttempts;
    if (attempts % loginLockoutMaxAttempts == 0 && level >= 1) {
      final step = level - 1 < loginLockoutMinuteSteps.length
          ? level - 1
          : loginLockoutMinuteSteps.length - 1;
      final lockedMinutes = loginLockoutMinuteSteps[step];
      lockedUntil = DateTime.now().millisecondsSinceEpoch +
          lockedMinutes * 60 * 1000;
      await recordSystemEvent(
        'login_lockout',
        userId: userId,
        payload: <String, Object?>{
          'attempts': attempts,
          'minutes': lockedMinutes,
        },
      );
    }
    await (update(appUsers)..where((t) => t.id.equals(userId))).write(
        AppUsersCompanion(
      failedLoginAttempts: Value(attempts),
      lockedUntil: Value(lockedUntil),
    ));
  }

  /// نجاح الدخول — يصفّر العداد والقفل معاً فلا قفل يتيم بعد نجاح.
  Future<void> resetFailedLoginAttempts(int userId) async {
    await (update(appUsers)..where((t) => t.id.equals(userId))).write(
        const AppUsersCompanion(
      failedLoginAttempts: Value(0),
      lockedUntil: Value(0),
    ));
  }

  /// صيغة الدقائق لرسالة القفل — عربية سليمة الجمع بتقريب صاعد.
  static String loginLockoutMinutesText(Duration remaining) {
    final minutes = (remaining.inSeconds / 60).ceil();
    if (minutes <= 1) return 'دقيقة واحدة';
    if (minutes == 2) return 'دقيقتين';
    if (minutes <= 10) return '$minutes دقائق';
    return '$minutes دقيقة';
  }

  /// نصف الاستئناف الأول بالبصمة — **للمعلق حصراً** (س213): التحقق
  /// البيومتري على الجهاز يُثبت أنّ صاحب الجلسة المعلقة هو نفسه،
  /// فالتخزين يُحصّن البوابة الأربعة: المستخدم موجوداً ونشطاً
  /// (المعطل ليس مهيأً على الجهاز عرف U-005)، والمطلوب هو المستأنف
  /// ذاته فلا بصة تفتح جلسة غيره ولا تُبدّل مستخدماً (D-215:
  /// التبديل بلاطته بكلمته حصراً)، وصاحب راية الإلزام لا يدخل
  /// بها (حواره الإلزامي يحتاج كلمة متحققة — راجع الحد الصادق
  /// بسجل العمل)، وتعيين صاحب الجلسة والراية باقية مقفلة
  /// بنفس عقد resumeSession فلا ثقب عودة بكل خطوة، والحدث بهوية
  /// الفاعل وحمله يفرّق مسار البصمة عن الكلمة.
  Future<AppUser> resumeSessionBiometric({required int userId}) async {
    final resumableId = await currentUserId();
    if (resumableId == null || resumableId != userId) {
      throw StateError(
          'الفتح بالبصمة لصاحب الجلسة المعلقة حصراً — أدخل كلمة المرور');
    }
    final user = await (select(appUsers)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (user == null || user.isDeleted || !user.isActive) {
      throw StateError('المستخدم معطل أو غير مهيأ على هذا الجهاز');
    }
    if (user.mustChangePassword) {
      throw StateError(
          'صاحب الإلزام يدخل بتحقق الكلمة حصراً');
    }
    await setCurrentUserId(user.id);
    await recordSystemEvent(
      'session_resumed',
      userId: user.id,
      payload: <String, Object?>{'via': 'device_gate_biometric'},
    );
    return user;
  }

  /// بذر الأدوار النمطية بأذوناتها الافتراضية (F-080، D-100 معروض؛
  /// والدور الخامس «مندوب» س101 بكلمة المالك) — فاحص الفراغ بالاسم فآمن
  /// التكرار أي كان مسار الوصول (onCreate أو ترحيلة 9→10 أو قبل الفتح
  /// ensureDefaultRoles)، والأدوار القائمة لا تُمسّ أبداً.
  Future<void> _seedDefaultRoles() => ensureDefaultRoles();

  /// الضمان العلني للأدوار النمطية — بذر صفوف بيان لا مخطط: يُستدعى قبل
  /// كل فتح قاعدة (beforeOpen س101) فكل دور نمطي جديد في
  /// defaultRolesPermissions يُزرع أول فتح لأي قاعدة قائمة بلا ترحيلة،
  /// والأدوار القائمة بأذوناتها كما عدّلها المالك لا تُمسّ.
  Future<void> ensureDefaultRoles() async {
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

  /// ضمان الحساب الوسيط «تحصيلات في الطريق» (س104) — بذرُ بيانٍ لا مخطط
  /// بعرف ensureDefaultRoles: فاحصُ الفراغ بالكود (`transitAccountCode`
  /// — الكود هو العقد) آمنُ التكرار أي كان مسار الوصول (بذرة الدليل
  /// الجديدة تضمه وbeforeOpen يضمنه لقواعد v23 القائمة)، والقائم بالكود
  /// ذاته لا يُمسُّ ولو غيّر المالك اسمَه (عرف الأدوار القائمة).
  Future<void> ensureTransitAccount() async {
    final existing = await (select(accounts)
          ..where((t) => t.code.equals(transitAccountCode)))
        .getSingleOrNull();
    if (existing != null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // الأب 11 «الأصول المتداولة» من بذرة الدليل حصراً — وغيابه حالة
    // دليل مقصوص يُرفض صادقاً لا يُخترع أب.
    final parent = await (select(accounts)
          ..where((t) => t.code.equals('11')))
        .getSingleOrNull();
    if (parent == null) {
      throw StateError(
          'لا يمكن بذر «تحصيلات في الطريق»: حساب الأب 11 (الأصول المتداولة) غائب');
    }
    await into(accounts).insert(
      AccountsCompanion.insert(
        code: transitAccountCode,
        name: 'تحصيلات في الطريق (عهدة المندوبين)',
        type: AccountType.asset.name,
        normalSide: NormalSide.debit.name,
        parentId: Value(parent.id),
        isLeaf: true,
        isActive: true,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
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

  /// س203: قراءة قيمة نصية من app_meta بمفتاحها — والغائب null.
  /// KV عام لمفاتيح الهوية (بيانات المنشأة س203) على نمط
  /// setCurrentUserId القائم، وجدول app_meta من v2 فلا ترحيلة.
  Future<String?> metaValueOf(String key) async {
    final row = await (select(appMeta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// س203: زرع/تحديث قيمة app_meta — نمط setCurrentUserId حرفاً.
  Future<void> upsertMetaValue(String key, String value) async {
    final existing = await (select(appMeta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)..where((t) => t.key.equals(key)))
          .write(AppMetaCompanion(value: Value(value)));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: key,
        value: value,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // تكليف النسخ الاحتياطي 2026-11-13 — أحداث نظام وبوابة الاستعادة
  // واسم الجهاز وحقائق ملخص ما بعد الاستعادة (§5/§6/§8-7).
  // ═══════════════════════════════════════════════════════════════

  /// حدث نظام عام (entityType='system') — أحداث التدقيق: تنفيذ استعادة،
  /// عرض ملخص الاستعادة — بالنمط ذاته الذي تكتب به أحداث المستندات
  /// (لقطة JSON كاملة ب07 §2.3) بلا أي مستخدم إلزامي.
  Future<void> recordSystemEvent(
    String action, {
    int? userId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: DateTime.now().millisecondsSinceEpoch,
        userId: userId == null ? const Value.absent() : Value(userId),
        deviceId: await deviceId(),
        entityType: 'system',
        action: action,
        payload: await sealLogText(jsonEncode(payload)),
        uuid: const Uuid().v4(),
      ),
    );
  }

  /// اسم الجهاز المعروض (تكليف §8-6 «الجهاز») — مفتاح app_meta يُملأ
  /// أول مرة ويحرَّر من الإعدادات؛ الفراغ يُسقط إلى null.
  static const String deviceNameMetaKey = 'device_name';

  Future<String?> deviceName() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(deviceNameMetaKey)))
        .getSingleOrNull();
    final v = row?.value.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  Future<void> setDeviceName(String name) async {
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(deviceNameMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)..where((t) => t.key.equals(deviceNameMetaKey)))
          .write(AppMetaCompanion(value: Value(name)));
    } else {
      await into(appMeta).insert(
          AppMetaCompanion.insert(key: deviceNameMetaKey, value: name));
    }
  }

  /// حالة بوابة الاستعادة — يزرعها applyRestore ويستهلكها الإقلاع
  /// (ق-ن1-أ): null = لا بوابة؛ غير null = دخول إلزامي بمدير نشط
  /// من النسخة المستعادة قبل أي بيانات.
  static const String restoreGateMetaKey = 'restore.gate';

  Future<RestoreGateState?> restoreGate() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(restoreGateMetaKey)))
        .getSingleOrNull();
    if (row == null) return null;
    try {
      final map = jsonDecode(row.value);
      if (map is! Map<String, Object?>) return null;
      return RestoreGateState(
        at: DateTime.tryParse('${map['at']}'),
        source: '${map['source']}',
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        locked: map['locked'] == true,
        snapshot:
            map['snapshot'] == null ? null : '${map['snapshot']}',
      );
    } catch (_) {
      return null; // تالف كالغائب — البوابة لا تنغلق بملف عطب.
    }
  }

  Future<void> _writeRestoreGate(RestoreGateState state) async {
    final value = jsonEncode(<String, Object?>{
      'at': state.at?.toIso8601String(),
      'source': state.source,
      'attempts': state.attempts,
      'locked': state.locked,
      if (state.snapshot != null) 'snapshot': state.snapshot,
    });
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(restoreGateMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)..where((t) => t.key.equals(restoreGateMetaKey)))
          .write(AppMetaCompanion(value: Value(value)));
    } else {
      await into(appMeta).insert(
          AppMetaCompanion.insert(key: restoreGateMetaKey, value: value));
    }
  }

  /// محاولة دخول فاشلة — يعيد العدد الجديد، وعند الخامسة يقفل (§5-5).
  Future<int> bumpRestoreGateAttempts() async {
    final gate = await restoreGate();
    if (gate == null) return 0;
    final attempts = gate.attempts + 1;
    await _writeRestoreGate(RestoreGateState(
      at: gate.at,
      source: gate.source,
      attempts: attempts,
      locked: attempts >= 5 || gate.locked,
      snapshot: gate.snapshot,
    ));
    return attempts;
  }

  /// إعادة المحاولة لاحقاً (§5-5) — تفتح القفل وترجّع المحاولات صفراً.
  Future<void> resetRestoreGateAttempts() async {
    final gate = await restoreGate();
    if (gate == null) return;
    await _writeRestoreGate(RestoreGateState(
      at: gate.at,
      source: gate.source,
      attempts: 0,
      locked: false,
      snapshot: gate.snapshot,
    ));
  }

  /// اجتياز البوابة — يمسح المفتاح كله فلا إقلاع قادم يسأل ثانية.
  Future<void> clearRestoreGate() async {
    await (delete(appMeta)..where((t) => t.key.equals(restoreGateMetaKey)))
        .go();
  }

  // ── نافذة التراجع عن الاستعادة (د-3 — §25.7، س136) ──────────────
  //
  // بعد كل استعادة تُسلَّح نافذة تراجع عند اجتياز البوابة (بعد أحداث
  // التدقيق فخط الأساس يسبق أول كتابة حقيقية)، وتُغلق بأول حدث جديد
  // يتجاوز خط الأساس — الحارس سجل الأحداث — فيُسجل حدث الإغلاق مرة
  // واحدة. الاستعادة الجديدة تستبدل النافذة فتعود لآخر استعادة حصراً.

  /// مفتاح حالة النافذة — مفاتيح نظام معفاة من اصطلاح المزامنة (D-055).
  static const String rollbackWindowMetaKey = 'restore.rollback_window';

  /// آخر معرّف حدث بسجل الأحداث — صفر على سجل فارغ (خط أساس التسليح).
  Future<int> maxEventId() async {
    final rows = await customSelect(
      'SELECT COALESCE(MAX(id), 0) AS m FROM events',
    ).get();
    return (rows.first.data['m'] as int? ?? 0);
  }

  /// تسليح النافذة: خط الأساس هو آخر حدث لحظة التسليح — فأول كتابة
  /// تَبعُد الحدثَ عنه وتُغلق. الاستدعاء يستبدل أي حالة سابقة (تعود
  /// لآخر استعادة).
  Future<void> armRollbackWindow(
      {required String snapshotFileName}) async {
    final state = RollbackWindowState(
      snapshotFileName: snapshotFileName,
      openedAtUtc: DateTime.now().toUtc(),
      baselineEventId: await maxEventId(),
      closed: false,
    );
    await _writeRollbackWindow(state);
  }

  Future<void> _writeRollbackWindow(RollbackWindowState state) async {
    final value = state.toJson();
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(rollbackWindowMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)
            ..where((t) => t.key.equals(rollbackWindowMetaKey)))
          .write(AppMetaCompanion(value: Value(value)));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
          key: rollbackWindowMetaKey, value: value));
    }
  }

  /// قراءة النافذة مع الحارس: المفتوحة التي تجاوز خط أساسها حدثٌ جديد
  /// تُغلق هنا (كتابة الحالة + تسجيل حدث الإغلاق مرة واحدة) وتُعاد
  /// مغلقة. الفاسد كالغائب — null بلا سحر.
  Future<RollbackWindowState?> rollbackWindow() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(rollbackWindowMetaKey)))
        .getSingleOrNull();
    if (row == null) return null;
    final state = RollbackWindowState.tryParse(row.value);
    if (state == null) return null;
    if (!state.closed &&
        rollbackWindowClosedByWrite(state, await maxEventId())) {
      final closed = state.withClosed();
      await _writeRollbackWindow(closed);
      await recordSystemEvent('rollback_window_closed', payload: {
        'reason': 'first_write',
        'snapshot': state.snapshotFileName,
      });
      return closed;
    }
    return state;
  }

  /// حقائق ملخص ما بعد الاستعادة (§6) — تشغيلية غير حساسة للجميع:
  /// آخر مستند وعدد المستخدمين وعدد الفواتير — يستدعيها من اجتاز
  /// البوابة فقط.
  Future<RestoreSummaryFacts> restoreSummaryFacts() async {
    final rows = await customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM app_users WHERE is_deleted = 0) AS users, '
      '(SELECT COUNT(*) FROM invoices WHERE is_deleted = 0) AS invoices, '
      '(SELECT MAX(d) FROM ('
      "  SELECT MAX(invoice_date) AS d FROM invoices WHERE is_deleted = 0 "
      '  UNION ALL '
      "  SELECT MAX(voucher_date) FROM vouchers WHERE is_deleted = 0 "
      '  UNION ALL '
      "  SELECT MAX(date_text) FROM moves WHERE is_deleted = 0"
      ')) AS last_doc',
    ).get();
    final row = rows.isEmpty ? null : rows.first.data;
    return RestoreSummaryFacts(
      usersCount: (row?['users'] as num?)?.toInt() ?? 0,
      invoicesCount: (row?['invoices'] as num?)?.toInt() ?? 0,
      lastDocumentDateText: row?['last_doc'] == null
          ? null
          : '${row!['last_doc']}',
    );
  }

  /// عرض عدّاد الترقيم (D-169 — س56 بلفظ المالك) — يُخزَّن في app_meta
  /// (مفاتيح نظام معفاة من اصطلاح المزامنة D-055) ويقرؤه التوليد عند
  /// كل ترحيل فتسري الخانة على كل أنواع المستندات واحدة. الغائب أو
  /// التالف يعود الافتراضي 6 — القاعدة الموثقة: التالف كالغياب بلا
  /// سحر ولا استثناء.
  static const String counterWidthMetaKey = 'numbering.counter_width';

  /// القراءة المعلنة للواجهة (بطاقة الإعدادات تعرض القيمة النافذة).
  Future<int> counterWidth() => _counterWidth();

  Future<int> _counterWidth() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(counterWidthMetaKey)))
        .getSingleOrNull();
    final parsed = row == null ? null : int.tryParse(row.value.trim());
    return (parsed != null && isValidCounterWidth(parsed))
        ? parsed
        : kDefaultCounterWidth;
  }

  /// ضبط عرض العدّاد (D-169) — خارج النطاق 3..8 يُرفض بلا كتابة،
  /// والواجهة تدقق قبل هذا الحرس الثانوي.
  Future<void> setCounterWidth(int width) async {
    if (!isValidCounterWidth(width)) {
      throw ArgumentError(
          'عرض عدّاد الترقيم خارج النطاق المسموح '
          '($kCounterWidthMin..$kCounterWidthMax): $width');
    }
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(counterWidthMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)..where((t) => t.key.equals(counterWidthMetaKey)))
          .write(AppMetaCompanion(value: Value('$width')));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: counterWidthMetaKey,
        value: '$width',
      ));
    }
  }

  /// ── س102 ثم س164: خيار المالك «بيع المندوب يحجز الكمية أم مسودة فقط» ──
  /// بكلمة المالك: «أريد أن يكون الخيار بيد المستخدم إما أن يكون بيع
  /// المندوب يحجز الكمية أم فقط مسودة». يُخزَّن في app_meta (نمط عرض
  /// العدّاد D-169 — مفاتيح نظام معفاة من اصطلاح المزامنة D-055) فيكون
  /// قرارَ منشأةٍ لا جهازاً: كل من يفتح القاعدة يرى الخيار نفسه.
  ///
  /// وبنقاط المالك س164 صار الحجز بتابع المسودة لا «التعليق» (أُلغي):
  /// مفتاح التخزين باقٍ حرفاً (القائم لا يُمس — القواعد القائمة بقيمها)
  /// ومعناه الحيّ اليوم: مسودات البيع تحجز كمياتها عند تفعيله — كلها
  /// لا المعلقات وحدها. والغائب يعني مطفأً — مسودة فقط لا مساس
  /// بالكمية (السلوك القائم افتراضاً). والحجز محسوبٌ لحظة كل فحص من
  /// المسودات لا مخزّن في عمود، فتفعيل الخيار يحجز المسودات القائمة
  /// فوراً وتعطيله يفكّها كلها — بلا ترحيلة ولا ترحيل بيانات ولا حالة
  /// محجوزة تُنسى.
  static const String heldReserveQtyMetaKey = 'invoices.held_reserve_qty';

  /// القراءة المعلنة — هل مسودات البيع تحجز كمية أسطرها (س164)؟
  /// القيمة الفاسدة كالغائب (D-169): لا '1' تعني مطفأً بلا سحر.
  Future<bool> heldInvoicesReserveQty() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(heldReserveQtyMetaKey)))
        .getSingleOrNull();
    return row?.value.trim() == '1';
  }

  /// س237: هل السطر الحر نافذ؟ (يقرأه محرر الفاتورة وبوابة
  /// «إدراج صنف حر» بنافذة الصنف غير الموجود).
  Future<bool> invoiceFreeLineAllowed() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(freeLineAllowedMetaKey)))
        .getSingleOrNull();
    return row?.value.trim() == '1';
  }

  /// س237: ضبط السطر الحر — '1'/'0' حرفاً كأخوته.
  Future<void> setInvoiceFreeLineAllowed(bool enabled) async {
    await _setAppMetaFlag(freeLineAllowedMetaKey, enabled);
  }

  /// س237: هل ملاحظات السطور نافذة؟ (حقلها الصغير قابل للتوسيع).
  Future<bool> invoiceLineNotesEnabled() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(lineNotesMetaKey)))
        .getSingleOrNull();
    return row?.value.trim() == '1';
  }

  /// س237: ضبط ملاحظات السطور — '1'/'0' حرفاً.
  Future<void> setInvoiceLineNotesEnabled(bool enabled) async {
    await _setAppMetaFlag(lineNotesMetaKey, enabled);
  }

  /// س237: ضبط علم app_meta موحداً بنمط أخيه حرفاً ('1'/'0').
  Future<void> _setAppMetaFlag(String key, bool enabled) async {
    final value = enabled ? '1' : '0';
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)..where((t) => t.key.equals(key)))
          .write(AppMetaCompanion(value: Value(value)));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: key,
        value: value,
      ));
    }
  }

  /// ضبط الخيار — قيمته '1'/'0' حرفاً كأخوته في app_meta.
  Future<void> setHeldInvoicesReserveQty(bool enabled) async {
    final value = enabled ? '1' : '0';
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(heldReserveQtyMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)
            ..where((t) => t.key.equals(heldReserveQtyMetaKey)))
          .write(AppMetaCompanion(value: Value(value)));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: heldReserveQtyMetaKey,
        value: value,
      ));
    }
  }

  // ═════════════════════════════════════════════════════════════
  // س164: خيار «مسودة أكبر من المتاح» — نقطة المالك الخامسة
  // بتفاعلها مع الحجز. المسودة التزام غير معلن لا حركة (عرف
  // الأوامر 07 §3.2) فحفظُها فوق المتاح يقبل بنص الخيار، والحجز
  // عند تفعيله يحجز كميتها كاملة (الإفراط حجزٌ لا بيع — اتجاه
  // أمان س102 ذاته)، والحاكم لحظة الترحيل حصراً: «من رحّل أولاً
  // غلب» (F-042 بالمتاح بعد الحجز). مفتاحٌ بإصلاح الكيان
  // «invoices.» أخو س102، والغائب والفاسد مطفأً — سلوك القائم
  // افتراضاً: الإنشاء يفحص فلا مسودة فوق المتاح إلا بيد الخيار.
  // ═════════════════════════════════════════════════════════════

  /// مفتاح خيار حفظ مسودة فوق المتاح (س164).
  static const String draftOverStockMetaKey = 'invoices.draft_over_stock';

  /// س237 (المرحلة ج — D-235): خانتا سياسات البيع — السطر الحر
  /// وملاحظات السطور (نافذتاها بالإعدادات وتقرؤهما شاشة التحرير).
  static const String freeLineAllowedMetaKey = 'invoices.free_line_allowed';
  static const String lineNotesMetaKey = 'invoices.line_notes';

  /// القراءة المعلنة — هل يُسمح بحفظ مسودة بيع كمياتها فوق المتاح؟
  /// الغائب والفاسد مطفأً (D-169 كالغائب).
  Future<bool> invoiceDraftOverStock() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(draftOverStockMetaKey)))
        .getSingleOrNull();
    return row?.value.trim() == '1';
  }

  /// ضبط الخيار — قيمته '1'/'0' حرفاً كأخوته في app_meta.
  Future<void> setInvoiceDraftOverStock(bool enabled) async {
    final value = enabled ? '1' : '0';
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(draftOverStockMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)
            ..where((t) => t.key.equals(draftOverStockMetaKey)))
          .write(AppMetaCompanion(value: Value(value)));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: draftOverStockMetaKey,
        value: value,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // س105: سقف عهدة المندوبين — إعداد منشأة في app_meta (عرف س102
  // بعدّاد D-169): أقصى ما يُسمح لحامل تحصيل واحد بتراكمه من القبض
  // المعلق «في الطريق» بوحدات صغرى من العملة الأساسية. الغائب أو
  // الفاسد أو الصفر يعني بلا سقف (سلوك س104 القائم افتراضاً — الفاسد
  // كالغائب D-169). الفرض عند التعليق حصراً (createHeldVoucher) —
  // فلا يمنع السقفُ الاعتمادَ ولا الرفض ولا قراءات العهدة وأعمارها.
  // ═══════════════════════════════════════════════════════════════

  /// مفتاح سقف العهدة — بإصلاح الكيان «vouchers.» بعرف المفاتيح
  /// المعفاة من اصطلاح المزامنة D-055 (أخو مفاتيح الفواتير س102).
  static const String custodyCapMetaKey = 'vouchers.custody_cap_minor';

  /// قراءة السقف — الصفر بلا سقف (الغائب والفاسد والسالب الشاذ صفراً
  /// كذلك بلا سحر — القراءة الصادقة لا تخترع حداً من فساد).
  Future<int> heldReceiptCustodyCap() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(custodyCapMetaKey)))
        .getSingleOrNull();
    final parsed = int.tryParse(row?.value.trim() ?? '');
    return (parsed == null || parsed < 0) ? 0 : parsed;
  }

  /// ضبط السقف — والصفر يُكتب قيمةً ظاهرة («0») فيرى المالك أنه بلا
  /// سقف لا مفتاحاً يتيماً، والسالب رفضٌ صادق قبل أي كتابة.
  Future<void> setHeldReceiptCustodyCap(int capBaseMinor) async {
    if (capBaseMinor < 0) {
      throw ArgumentError.value(
          capBaseMinor, 'capBaseMinor', 'سقف العهدة لا يكون سالباً');
    }
    final value = '$capBaseMinor';
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(custodyCapMetaKey)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(appMeta)
            ..where((t) => t.key.equals(custodyCapMetaKey)))
          .write(AppMetaCompanion(value: Value(value)));
    } else {
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: custodyCapMetaKey,
        value: value,
      ));
    }
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
  ///
  /// P2 (09 §40) — الترقية الآلية عند أول دخول ناجح: السجل الإرث
  /// «salt:hash» (تكراراته 50,000 ضمنياً) أو أي سجل بتكرارات أدنى من
  /// [passwordUpgradeIterations] يُعاد تجزئته بملح جديد وعند العتبة
  /// وتُحدَّث صفته فلا سجل أدنى يبقى بعد دخوله مرة واحدة (نمط «الترحيل
  /// عند أول فتح» الموثق P0/P1) — والفشل في الترقية لا يرفض الدخول
  /// ولا يوقفه (يُعاد الاحتمال عند الدخول التالي) والسجل الذي بلغ
  /// العتبة لا يُمس. الترقية الناجحة تُسجل حدثاً بنظام الأحداث
  /// (بذرة m4) بحمولتها من وإلى.
  ///
  /// س219 (قياس b73 الحي): النواة الحسابية بعزل الخلفية حصراً
  /// ([PasswordHasher.verifyStoredInBackground] و[hashInBackground]
  /// — 600,000 تكراراً بنوى دارت كانت تجمّد خيط الواجهة كاملاً كل
  /// محاولة بالقياس الحي 4.69 ثانية وعتبة ANR الإدخالية أندرويد 5
  /// ثوانٍ)، ومسارات الرفض الثلاثة (مفقود/معطل/كلمة خاطئة) بكلفة
  /// حسابية واحدة بعمل الموازنة فلا قناة تعداد توقيتية — الرسالة
  /// الموحدة س216 تكتمل توقيتاً لا نصاً حصراً (عقد الموازنة فوق
  /// [resumeSessionByLogin] و[PasswordHasher.equalizingWorkInBackground]
  /// — والمفتاح الواحد تكرارات الجيل الحالي passwordUpgradeIterations).
  Future<AppUser?> verifyUserPassword(int userId, String password) async {
    final user = await (select(appUsers)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    // س219 — موازنة التوقيت بالمسارات الثلاثة: المفقود يأخذ عمل
    // الموازنة، والمعطل حساباً حقيقياً بسجله ذاته (فاسد السجل عمل
    // الموازنة) — كلفة الرفض كلفة كلمة خاطئة بالضبط فلا ساعة تميّز
    // معطلاً من كلمة خاطئة من اسم مجهول، والرسالة الموحدة س216
    // تكتمل توقيتاً لا نصاً حصراً.
    if (user == null) {
      await PasswordHasher.equalizingWorkInBackground(
          iterations: passwordUpgradeIterations);
      return null;
    }
    if (!user.isActive) {
      if (PasswordHasher.parseStored(user.passwordHash) == null) {
        await PasswordHasher.equalizingWorkInBackground(
            iterations: passwordUpgradeIterations);
      } else {
        await PasswordHasher.verifyStoredInBackground(
            user.passwordHash, password);
      }
      return null;
    }
    // س219: التحقق بعزل الخلفية — عقد قابلية الإرسال س218 بالمدار
    // ذاته: الإغلاق قيم بسيطة قابلة للإرسال حصراً فلا تجميد واجهة
    // (القياس الحي b73: 4.69 ثانية تجميداً كل محاولة).
    final ok = await PasswordHasher.verifyStoredInBackground(
        user.passwordHash, password);
    if (!ok) {
      return null;
    }
    try {
      final parsed = PasswordHasher.parseStored(user.passwordHash);
      if (parsed != null &&
          parsed.iterations < passwordUpgradeIterations) {
        final salt = PasswordHasher.newSalt();
        // س219: الترقية أيضاً بعزل الخلفية — 600,000 تكراراً أخرى
        // كانت تجميداً ثانياً بعزل الواجهة عند أول دخول ناجح بإرث.
        final hash = await PasswordHasher.hashInBackground(
            password, salt,
            iterations: passwordUpgradeIterations);
        final stored = PasswordHasher.formatStored(
            salt, hash, passwordUpgradeIterations);
        await (update(appUsers)..where((t) => t.id.equals(user.id))).write(
          AppUsersCompanion(
            passwordHash: Value(stored),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
        await recordSystemEvent(
          'password_hash_iterations_upgraded',
          userId: user.id,
          payload: <String, Object?>{
            'from_iterations': parsed.iterations,
            'to_iterations': passwordUpgradeIterations,
          },
        );
      }
    } catch (_) {
      // الترقية أفضل جهد بعقد الدفعة: فشلها لا يرفض الدخول الناجح —
      // والسجل يبقى مؤهلاً للترقية عند الدخول التالي.
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
    int? paymentTermDays,
  }) async {
    assert(defaultCurrencyId > 0, 'D-066: عملة الطرف لا تصل فارغة أبداً');
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(parties).insert(
      PartiesCompanion.insert(
        number: number,
        name: sanitizeFreeName(name),
        kind: kind,
        phone: Value(_nullIfBlank(phone)),
        address: Value(_nullIfBlank(address)),
        defaultCurrencyId: defaultCurrencyId,
        creditLimitBaseMinor: Value(creditLimitBaseMinor),
        paymentTermDays: Value(_positiveOrNull(paymentTermDays)),
        isActive: true,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// تحديث بيانات طرف — الرقم قابل للتعديل الآن بلفظ المالك (س50/1:
  /// «تمام» على عرض س50، س-155/D-153): المعاملات ترتبط بالمعرف الخفي
  /// `id` لا بالرقم الظاهر فتعديله آمن على التاريخ والذمم والتقارير،
  /// والتفرد محروس بالمدقق قبل الكتابة (نمط س-29 بالاستثناء النفس)
  /// وقيد UNIQUE حرس ثانوي من القاعدة. والاسم يعدل بحرية مع بقاء
  /// قاعدة المنع الحرفي (س-32/D-065). تخزينه null لحد الائتمان
  /// يعني إزالة السقف عمداً (س-34).
  Future<void> updatePartyDetails(
    Party party, {
    required String number,
    required String name,
    required String kind,
    String? phone,
    String? address,
    required int defaultCurrencyId,
    int? creditLimitBaseMinor,
    int? paymentTermDays,
  }) async {
    assert(defaultCurrencyId > 0, 'D-066: عملة الطرف لا تصل فارغة أبداً');
    await (update(parties)..where((t) => t.id.equals(party.id))).write(
      PartiesCompanion(
        number: Value(number),
        name: Value(sanitizeFreeName(name)),
        kind: Value(kind),
        phone: Value(_nullIfBlank(phone)),
        address: Value(_nullIfBlank(address)),
        defaultCurrencyId: Value(defaultCurrencyId),
        creditLimitBaseMinor: Value(creditLimitBaseMinor),
        paymentTermDays: Value(_positiveOrNull(paymentTermDays)),
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

  /// د6 (س175): الصفر والسالب يُخزَّنان null — الحد الأدنى ومدة
  /// السداد معناهما الحد الموجب حصراً، والفراغ مصدر صامت بالمتابعات
  /// فلا حد أدنى صفر يولد متابعة بلا معنى.
  int? _positiveOrNull(int? v) =>
      (v == null || v <= 0) ? null : v;

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
    int? unitGroupId,
    bool priceAuto = true,
    int? minQty,
  }) async {
    assert(baseUnitId > 0, 'F-031: الوحدة الأساسية إلزامية');
    assert(priceCurrencyId > 0, 'D-066: عملة السعر لا تصل فارغة أبداً');
    assert(purchasePriceMinor >= 0 && salePriceMinor >= 0,
        'س6: لا سعر سالب — والصفر مشروع');
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(items).insert(
      ItemsCompanion.insert(
        sku: sku.trim(),
        name: sanitizeFreeName(name),
        category: Value(_nullIfBlank(category)),
        kind: kind,
        baseUnitId: baseUnitId,
        purchasePriceMinor: purchasePriceMinor,
        salePriceMinor: salePriceMinor,
        priceCurrencyId: priceCurrencyId,
        unitGroupId: Value(unitGroupId),
        priceAuto: Value(priceAuto),
        minQty: Value(_positiveOrNull(minQty)),
        isActive: true,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// تحديث بيانات صنف — الكود قابل للتعديل الآن بلفظ المالك (س50/1:
  /// «تمام» على عرض س50، س-155/D-153): الفواتير ترتبط بمعرّفه الخفي
  /// `id` فتعديل الكود الظاهر آمن، والتفرد الحرفي بعد تقليم الفراغات
  /// محروس بالمدقق (س-39) وقيد UNIQUE حرس ثانوي. والبقية تعدل بحرية.
  Future<void> updateItemDetails(
    Item item, {
    required String sku,
    required String name,
    String? category,
    required String kind,
    required int baseUnitId,
    required int purchasePriceMinor,
    required int salePriceMinor,
    required int priceCurrencyId,
    Object? unitGroupId = _keepCurrent,
    bool? priceAuto,
    int? minQty,
  }) async {
    assert(baseUnitId > 0, 'F-031: الوحدة الأساسية إلزامية');
    assert(priceCurrencyId > 0, 'D-066: عملة السعر لا تصل فارغة أبداً');
    assert(purchasePriceMinor >= 0 && salePriceMinor >= 0,
        'س6: لا سعر سالب — والصفر مشروع');
    await (update(items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        sku: Value(sku.trim()),
        name: Value(sanitizeFreeName(name)),
        category: Value(_nullIfBlank(category)),
        kind: Value(kind),
        baseUnitId: Value(baseUnitId),
        purchasePriceMinor: Value(purchasePriceMinor),
        salePriceMinor: Value(salePriceMinor),
        priceCurrencyId: Value(priceCurrencyId),
        unitGroupId: unitGroupId == _keepCurrent
            ? const Value.absent()
            : Value(unitGroupId as int?),
        priceAuto:
            priceAuto == null ? const Value.absent() : Value(priceAuto),
        minQty: Value(_positiveOrNull(minQty)),
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
  // مجموعات التعبئة وأسعارها آلي — الدفعة 27 (F-032/F-033/F-208،
  // D-026/D-187). المرجع يُضاف ويُسمّى ولا يُحذف ولا يُعطّل (نمط
  // المراجع 03 §6-3 — الصنف قد يحيل)، والعامل يتجمد بعد الحركات
  // (F-033) والمسار الوحيد وحدة جديدة، والآلي يُشتق واليدوي يُكتب
  // (D-187) — والتخزين يحفظ ولا يحسب (الاشتقاق بمحرك المجال حصراً).
  // ─────────────────────────────────────────────────────────────────

  /// إدراج مجموعة تعبئة بمستوياتها الأولية — الاسم مقلم فريد حرفياً
  /// (D-074، قيد UNIQUE حرس ثانوي) والمستويات بفهرس التفرد (المجموعة،
  /// الاسم). العوامل الصحيحة من مدقق المجال (parseUnitGroupFactor)
  /// وحرساً ثانوياً هنا.
  Future<int> insertUnitGroup({
    required String name,
    List<({String name, int factor})> levels = const [],
  }) async {
    final clean = name.trim();
    assert(clean.isNotEmpty, 'اسم مجموعة التعبئة إلزامي (F-032)');
    assert(
        levels.every((l) => l.name.trim().isNotEmpty && l.factor >= 2),
        'F-032: المستوى باسمه وعامله ≥2');
    final now = DateTime.now().millisecondsSinceEpoch;
    return transaction(() async {
      final id = await into(unitGroups).insert(
        UnitGroupsCompanion.insert(
          name: clean,
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      for (final level in levels) {
        await _insertUnitGroupLevelRow(
            groupId: id, name: level.name, factor: level.factor, now: now);
      }
      return id;
    });
  }

  Future<int> _insertUnitGroupLevelRow({
    required int groupId,
    required String name,
    required int factor,
    required int now,
  }) {
    return into(unitGroupLevels).insert(
      UnitGroupLevelsCompanion.insert(
        groupId: groupId,
        name: name.trim(),
        factor: factor,
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// إعادة تسمية مجموعة — التفرد الحرفي بالمدقق قبل الاستدعاء وقيد
  /// UNIQUE حرساً ثانوياً. التسمية لا تمس التاريخ فلا تجميد لها.
  Future<void> renameUnitGroup(int groupId, {required String name}) async {
    final clean = name.trim();
    assert(clean.isNotEmpty, 'الاسم إلزامي (F-032)');
    await (update(unitGroups)..where((t) => t.id.equals(groupId))).write(
      UnitGroupsCompanion(
        name: Value(clean),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// المجموعات مرتبة معجمياً بالاسم (D-074 نمط القوائم).
  Future<List<UnitGroup>> allUnitGroups() async {
    final rows = await select(unitGroups).get();
    return [...rows]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// مستويات مجموعة مرتبة بالعامل تصاعدياً — ترتيب العرض الطبيعي.
  Future<List<UnitGroupLevel>> levelsOfGroup(int groupId) async {
    return (select(unitGroupLevels)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.asc(t.factor)]))
        .get();
  }

  /// مستويات كل المجموعات دفعةً — خريطة شاشات الأصناف والترقية.
  Future<Map<int, List<UnitGroupLevel>>> allUnitGroupLevels() async {
    final rows = await (select(unitGroupLevels)
          ..orderBy([(t) => OrderingTerm.asc(t.factor)]))
        .get();
    final map = <int, List<UnitGroupLevel>>{};
    for (final r in rows) {
      (map[r.groupId] ??= []).add(r);
    }
    return map;
  }

  /// F-033 المسار الوحيد: وحدة جديدة تُضاف لمجموعة قائمة — في أي وقت
  /// (الإضافة لا تمس التاريخ فلا تجميد لها).
  Future<int> insertUnitGroupLevel({
    required int groupId,
    required String name,
    required int factor,
  }) async {
    assert(name.trim().isNotEmpty, 'اسم المستوى إلزامي');
    assert(factor >= 2, 'العامل ≥2 (الأساسية 1 بذاتها)');
    return _insertUnitGroupLevelRow(
        groupId: groupId,
        name: name,
        factor: factor,
        now: DateTime.now().millisecondsSinceEpoch);
  }

  /// F-033: هل توجد حركات على أصناف المجموعة؟ الحركة حقيقية لا مسودة:
  /// حركة مخزون أو سطر فاتورة مرحّل — والمسودات لا تجمد، وجلسة العد
  /// الجارية بلا أثر لا تجمد (ترحيلها يصنع حركة تجمّد).
  Future<bool> unitGroupHasMovements(int groupId) async {
    final row = await customSelect(
      "SELECT ("
      "EXISTS(SELECT 1 FROM stock_moves sm "
      "JOIN items i ON i.id = sm.item_id WHERE i.unit_group_id = ?) "
      "OR EXISTS(SELECT 1 FROM invoice_lines il "
      "JOIN invoices inv ON inv.id = il.invoice_id "
      "JOIN items i ON i.id = il.item_id "
      "WHERE i.unit_group_id = ? AND inv.state = 'posted')"
      ") AS frozen",
      variables: [Variable.withInt(groupId), Variable.withInt(groupId)],
    ).getSingle();
    return (row.data['frozen'] as int) == 1;
  }

  /// تعديل مستوى قائم — التسمية حرة، والعامل بالحرس الوحيد (F-033):
  /// تجميد بعد الحركات برمي [UnitGroupFactorFrozenException] والمسار
  /// الوحيد وحدة جديدة. الواجهة تفحص التجمد سلفاً فتعطّل الخانة —
  /// والاستثناء حرس ثانوي للمسار المباشر.
  Future<void> updateUnitGroupLevel(
    int levelId, {
    String? name,
    int? factor,
  }) async {
    assert(name != null || factor != null, 'لا تعديل بلا تغيير');
    if (factor != null) {
      final row = await (select(unitGroupLevels)
            ..where((t) => t.id.equals(levelId)))
          .getSingle();
      if (factor != row.factor && await unitGroupHasMovements(row.groupId)) {
        throw const UnitGroupFactorFrozenException();
      }
    }
    await (update(unitGroupLevels)..where((t) => t.id.equals(levelId)))
        .write(
      UnitGroupLevelsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        factor: factor == null ? const Value.absent() : Value(factor),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// أسعار مستويات صنف — خريطة (معرّف المستوى) ← (بيع، شراء).
  /// (الاسم مُبعَّد عن getter الجدول المولد `itemLevelPrices` — درس
  /// تصادم الأسماء المولدة، نمط س78).
  Future<Map<int, (int, int)>> itemLevelPriceMap(int itemId) async {
    final rows = await (select(itemLevelPrices)
          ..where((t) => t.itemId.equals(itemId)))
        .get();
    return {
      for (final r in rows)
        r.levelId: (r.salePriceMinor, r.purchasePriceMinor),
    };
  }

  /// أسعار مستويات أصناف متعددة دفعةً — معاينة الرفع الجماعي (F-165).
  Future<Map<int, Map<int, (int, int)>>> itemLevelPricesForItems(
      List<int> itemIds) async {
    if (itemIds.isEmpty) return {};
    final rows = await (select(itemLevelPrices)
          ..where((t) => t.itemId.isIn(itemIds)))
        .get();
    final map = <int, Map<int, (int, int)>>{};
    for (final r in rows) {
      (map[r.itemId] ??= {})[r.levelId] =
          (r.salePriceMinor, r.purchasePriceMinor);
    }
    return map;
  }

  /// حفظ أسعار مستويات صنف — استبدال كامل بمعاملة واحدة (نمط اللقطة
  /// الموثق): الآلي يكتب الاشتقاقَ المحسوبَ بمحرك المجال، واليدوي يكتب
  /// المُدخل — ولقطة السعر في سطر المستند كما هي بلا مساس (D-187).
  Future<void> saveItemLevelPrices(
    int itemId,
    List<({int levelId, int salePriceMinor, int purchasePriceMinor})> rows,
  ) async {
    assert(
        rows.every((r) =>
            r.salePriceMinor >= 0 && r.purchasePriceMinor >= 0),
        'س6: لا سعر سالب — والصفر مشروع');
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      await (delete(itemLevelPrices)
            ..where((t) => t.itemId.equals(itemId)))
          .go();
      for (final r in rows) {
        await into(itemLevelPrices).insert(
          ItemLevelPricesCompanion.insert(
            itemId: itemId,
            levelId: r.levelId,
            salePriceMinor: r.salePriceMinor,
            purchasePriceMinor: r.purchasePriceMinor,
            uuid: const Uuid().v4(),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // وصفة التجميعي — الدفعة 28 (F-034/F-212): حفظ وقراءة بمدققين
  // (المجال ثم القاعدة) والرفض قبل الكتابة حصراً.
  // ─────────────────────────────────────────────────────────────────

  /// حفظ وصفة تجميعي — الاستبدال الكامل داخل معاملة (نمط
  /// saveItemLevelPrices) بعد مدققين: مدقق المجال (البنية والكميات
  /// والتكاليف والتكرار والذاتية — س-09) ثم مدقق القاعدة (الوجود
  /// والتفعيل والنوع: التجميعي صاحبها ومكوناتها بضاعة أو خدمة حصراً —
  /// لا تداخل) — فلا وصفة ناقصة تُخزن ولا استبدال جزئي.
  Future<void> saveBundleRecipe(
    int bundleItemId,
    List<BundleComponentDraft> components,
  ) async {
    final structural = validateBundleRecipeStructure(
      BundleRecipeDraft(bundleItemId: bundleItemId, components: components),
    );
    if (structural.isNotEmpty) {
      throw BundleValidationException(structural);
    }
    final errors = <BundleValidationError>[];
    final owner = await _itemByIdTx(bundleItemId);
    if (owner == null) {
      errors.add(BundleOwnerNotFound(bundleItemId));
    } else {
      final ownerLabel =
          itemDisplayLabel(owner['name'] as String, owner['sku'] as String);
      if ((owner['is_active'] as int) == 0) {
        errors.add(BundleOwnerInactive(ownerLabel));
      }
      if ((owner['kind'] as String) != 'bundle') {
        errors.add(BundleOwnerNotBundle(ownerLabel));
      }
    }
    for (var i = 0; i < components.length; i++) {
      final comp = await _itemByIdTx(components[i].componentItemId);
      if (comp == null) {
        errors.add(
            BundleComponentNotFound(i, components[i].componentItemId));
        continue;
      }
      final compLabel =
          itemDisplayLabel(comp['name'] as String, comp['sku'] as String);
      if ((comp['is_active'] as int) == 0) {
        errors.add(BundleComponentInactive(i, compLabel));
      }
      if ((comp['kind'] as String) == 'bundle') {
        errors.add(BundleComponentIsBundle(i, compLabel));
      }
      // خانة التكلفة للخدمة بالخيارين حصراً (F-212) — والبضاعة كلفتها
      // من مخزونها الحاكم لحظة الفك (F-034) فلا خانة تكلفة لها أبداً.
      if ((comp['kind'] as String) == 'good' &&
          components[i].costMinor != null) {
        errors.add(BundleComponentCostInvalid(i, components[i].costMinor));
      }
    }
    if (errors.isNotEmpty) throw BundleValidationException(errors);

    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      await (delete(bundleComponents)
            ..where((t) => t.bundleItemId.equals(bundleItemId)))
          .go();
      for (final c in components) {
        await into(bundleComponents).insert(
          BundleComponentsCompanion.insert(
            bundleItemId: bundleItemId,
            componentItemId: c.componentItemId,
            qtyBase: c.qtyBase,
            costMinor: Value(c.costMinor),
            uuid: const Uuid().v4(),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// وصفة تجميعي بمكوناتها — عرض محرر الوصفة ببطاقة الصنف: المكوّن
  /// باسمه وكوده ونوعه وكميته الوصفية وتكلفته الخدمية إن قُيمت (F-212).
  Future<List<BundleRecipeRow>> bundleRecipeByItem(int bundleItemId) async {
    final rows = await customSelect(
      'SELECT bc.component_item_id, bc.qty_base, bc.cost_minor, '
      'i.kind, i.sku, i.name '
      'FROM bundle_components bc '
      'JOIN items i ON i.id = bc.component_item_id '
      'WHERE bc.bundle_item_id = ?1 AND bc.is_deleted = 0 '
      'ORDER BY bc.id',
      variables: [Variable.withInt(bundleItemId)],
    ).get();
    return [
      for (final r in rows)
        BundleRecipeRow(
          componentItemId: r.data['component_item_id'] as int,
          qtyBase: r.data['qty_base'] as int,
          costMinor: r.data['cost_minor'] as int?,
          kind: r.data['kind'] as String,
          sku: r.data['sku'] as String,
          name: r.data['name'] as String,
        ),
    ];
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

  // ── الدفعة 23 (D-183): F-146 اقتراحات الإدخال وF-165 الترقية
  // الجماعية — قراءتا اقتراح بنمط customSelect القائم، وكتابة ترقية
  // معاملة واحدة. بلا أحداث اتفاقاً مع updateItemDetails: تفاصيل
  // الأصناف بلا أحداث حتى مرحلة المزامنة (08).

  /// عدادات تداول الأطراف لاقتراح «الأكثر تداولاً» (F-146): فواتير
  /// مرحّلة من عائلة الجهة كاملة (المردود تداول حقيقي) منذ تاريخ ISO
  /// حصراً، والأطراف وحدها من لها طرف أصلاً.
  Future<Map<int, int>> partyUsageCounts({
    required bool salesSide,
    required String sinceIso,
  }) async {
    final kinds = salesSide
        ? "('sale','sale_return')"
        : "('purchase','purchase_return')";
    final rows = await customSelect(
      'SELECT party_id AS pid, COUNT(*) AS c FROM invoices '
      // «المرحّل» بلسان batch22 الموثق: ليس مسودة — فالتوزيع يغيّر
      // الحالة إلى paid/partially_paid (س-156/D-154) وكلها مرحّلة.
      "WHERE state <> 'draft' AND party_id IS NOT NULL AND is_deleted = 0 "
      'AND kind IN $kinds AND invoice_date >= ?1 '
      'GROUP BY party_id',
      variables: [Variable.withString(sinceIso)],
    ).get();
    return {
      for (final r in rows)
        if (r.data['pid'] != null) r.data['pid'] as int: r.data['c'] as int,
    };
  }

  /// آخر سعر فعلي لكل صنف مع طرف (F-146) — من فواتير عائلة الجهة
  /// المرحّلة بأسعار موجبة حصراً، والأحدث فوزاً (أول ظهور بعد الترتيب
  /// التنازلي). قراءة لا كتابة — القبول بشري بالواجهة.
  Future<Map<int, LastPriceSuggestion>> lastPricesForParty({
    required int partyId,
    required bool salesSide,
  }) async {
    final kinds = salesSide
        ? "('sale','sale_return')"
        : "('purchase','purchase_return')";
    final rows = await customSelect(
      'SELECT il.item_id AS item_id, il.unit_price_minor AS price_minor, '
      'inv.number AS doc_number, inv.invoice_date AS doc_date '
      'FROM invoice_lines il JOIN invoices inv ON inv.id = il.invoice_id '
      // «المرحّل» = ليس مسودة (درس البذرة: التوزيع يغيّر الحالة).
      "WHERE inv.party_id = ?1 AND inv.state <> 'draft' AND inv.kind IN $kinds "
      'AND il.unit_price_minor > 0 '
      'AND inv.is_deleted = 0 AND il.is_deleted = 0 '
      'ORDER BY inv.id DESC, il.id DESC',
      variables: [Variable.withInt(partyId)],
    ).get();
    final out = <int, LastPriceSuggestion>{};
    for (final r in rows) {
      final itemId = r.data['item_id'] as int;
      if (out.containsKey(itemId)) continue;
      out[itemId] = LastPriceSuggestion(
        itemId: itemId,
        priceMinor: r.data['price_minor'] as int,
        docLabel: '${r.data['doc_number']} بتاريخ ${r.data['doc_date']}',
      );
    }
    return out;
  }

  /// تنفيذ الترقية الجماعية (F-165) — معاملة واحدة تُحدّث الحقول
  /// المستهدفة بقيمها المحسوبة سلفاً بالمعاينة. الحساب في المجال
  /// والكتابة هنا حصراً — التخزين يحفظ ولا يقرر — والحقل غير المستهدف
  /// بلا Presence فلا يُمس إطلاقاً. ومستويات التعبئة (تقاطع
  /// F-165/D-187) تُكتب بقيمها المحسوبة ذاتها مع صيانة الحقل غير
  /// المستهدف لكل مستوى من صفه القائم فلا يضيع يدويٌّ محفوظ.
  Future<void> applyBulkPriceUpdates(
      List<BulkPriceUpdateRow> updates) async {
    assert(updates.every((u) =>
        (u.newSalePriceMinor == null || u.newSalePriceMinor! >= 0) &&
        (u.newPurchasePriceMinor == null || u.newPurchasePriceMinor! >= 0)),
        'س6: لا سعر سالب');
    assert(
        updates.every((u) => u.levels.every((l) =>
            (l.newSalePriceMinor == null || l.newSalePriceMinor! >= 0) &&
            (l.newPurchasePriceMinor == null ||
                l.newPurchasePriceMinor! >= 0))),
        'س6: لا سعر سالب بالمستويات');
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      await batch((b) {
        for (final u in updates) {
          b.update(
            items,
            ItemsCompanion(
              salePriceMinor: u.newSalePriceMinor == null
                  ? const Value.absent()
                  : Value(u.newSalePriceMinor!),
              purchasePriceMinor: u.newPurchasePriceMinor == null
                  ? const Value.absent()
                  : Value(u.newPurchasePriceMinor!),
              updatedAt: Value(now),
            ),
            where: ($ItemsTable t) => t.id.equals(u.itemId),
          );
        }
      });
      // مستويات التعبئة — استبدال الصفوف المستهدفة حصراً، والحقل غير
      // المستهدف لكل مستوى يُحفظ من صفه القائم فلا قيمة يدوية تضيع.
      for (final u in updates) {
        for (final l in u.levels) {
          final existing = await (select(itemLevelPrices)
                ..where((t) =>
                    t.itemId.equals(u.itemId) & t.levelId.equals(l.levelId)))
              .getSingleOrNull();
          final sale = l.newSalePriceMinor ??
              existing?.salePriceMinor ??
              0;
          final purchase = l.newPurchasePriceMinor ??
              existing?.purchasePriceMinor ??
              0;
          await (delete(itemLevelPrices)..where((t) =>
                  t.itemId.equals(u.itemId) & t.levelId.equals(l.levelId)))
              .go();
          await into(itemLevelPrices).insert(
            ItemLevelPricesCompanion.insert(
              itemId: u.itemId,
              levelId: l.levelId,
              salePriceMinor: sale,
              purchasePriceMinor: purchase,
              uuid: const Uuid().v4(),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        }
      }
    });
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
      // س107 (أساس الأخطاء): DROP قبل كل CREATE — إعادة تعريف موثقة
      // (درس v9/v21/v22) تُحدّث نصوص الحواجز المرقّمة DQ على أي قاعدة
      // قائمة عند مرور الترحيلة، وCREATE IF NOT EXISTS وحدها لا
      // تستبدل القائم فبقي الرسالة القديمة بلا رمز.
      'DROP TRIGGER IF EXISTS trg_moves_post_balance',
      'DROP TRIGGER IF EXISTS trg_moves_posted_frozen',
      'DROP TRIGGER IF EXISTS trg_moves_no_delete_posted',
      'DROP TRIGGER IF EXISTS trg_move_lines_frozen_insert',
      'DROP TRIGGER IF EXISTS trg_move_lines_frozen_update',
      'DROP TRIGGER IF EXISTS trg_move_lines_frozen_delete',
      "CREATE TRIGGER trg_moves_post_balance "
          "BEFORE UPDATE ON moves FOR EACH ROW "
          "WHEN NEW.state = 'posted' AND OLD.state <> 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'قيد غير متوازن: مجموع المدين لا يساوي "
          "مجموع الدائن (DQ-0101)') "
          "WHERE (SELECT COALESCE(SUM(debit_minor),0) FROM move_lines "
          "WHERE move_id = NEW.id) <> "
          "(SELECT COALESCE(SUM(credit_minor),0) FROM move_lines "
          "WHERE move_id = NEW.id); "
          "SELECT RAISE(ABORT, 'قيد مرحّل بأسطر أقل من اثنين (DQ-0102)') "
          "WHERE (SELECT COUNT(*) FROM move_lines WHERE move_id = NEW.id) "
          "< 2; "
          "END",
      "CREATE TRIGGER trg_moves_posted_frozen "
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
          "SELECT RAISE(ABORT, 'القيد المرحّل لا يعدل — التصحيح بقيد عكس (DQ-0103)'); "
          "END",
      "CREATE TRIGGER trg_moves_no_delete_posted "
          "BEFORE DELETE ON moves FOR EACH ROW "
          "WHEN OLD.state = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'القيد المرحّل لا يحذف — التصحيح بقيد عكس (DQ-0104)'); "
          "END",
      "CREATE TRIGGER trg_move_lines_frozen_insert "
          "BEFORE INSERT ON move_lines FOR EACH ROW "
          "WHEN (SELECT state FROM moves WHERE id = NEW.move_id) = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'أسطر القيد المرحّل لا تضاف (DQ-0105)'); END",
      "CREATE TRIGGER trg_move_lines_frozen_update "
          "BEFORE UPDATE ON move_lines FOR EACH ROW "
          "WHEN (SELECT state FROM moves WHERE id = NEW.move_id) = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'أسطر القيد المرحّل لا تعدل (DQ-0106)'); END",
      "CREATE TRIGGER trg_move_lines_frozen_delete "
          "BEFORE DELETE ON move_lines FOR EACH ROW "
          "WHEN (SELECT state FROM moves WHERE id = OLD.move_id) = 'posted' "
          "BEGIN "
          "SELECT RAISE(ABORT, 'أسطر القيد المرحّل لا تحذف (DQ-0107)'); END",
    ];
    for (final sql in triggers) {
      await customStatement(sql);
    }
  }

  /// د0 (س160 — أولى خارطة م4 09 §46): فهرس `move_id` على `move_lines`
  /// — المرشح الموثق س156 صار مخططاً (v29): بلا فهرس يصعد ترحيل
  /// العينة الكبيرة O(N²) بمجموعَي زناد التوازن (DQ-0101/0102) لكل
  /// صف — فحصُ توازن كل قيد يمسح الجدول كله بحثاً عن أسطر قيده —
  /// والفهرس يخفضه إلى بحث بالمؤشر فالترحيل الفردي والإفرادي
  /// والاستيراد الكبير كلها على أداء معلوم. آمن التكرار بـIF NOT
  /// EXISTS (عرف الفهارس الموثقة — درس س86: فهرس @TableIndex يكسر
  /// نداءات createAll المتعددة عبر خطوات الترقية فالعرف
  /// customStatement)، ويُبنى من أول إنشاء (onCreate) ومن الترحيلة
  /// v29 لأي قاعدة قائمة أي كان مسار وصولها.
  Future<void> _createMoveLinesIndex() async {
    await customStatement('CREATE INDEX IF NOT EXISTS ix_move_lines_move_id '
        'ON move_lines (move_id)');
  }

  /// س215 (الثقل الجذري للبيانات الضخمة — بنود الفهارس المُنفَّذة
  /// بأمر المالك «معالجة الثقل الجذري للبيانات الضخمة (فهارس
  /// واستعلامات الرئيسية)»): كل فهرس هنا يقيّد مساراً حاراً موثقاً
  /// من الشيفرة القائمة نفسها — فحص الثوابت الافتتاحي (T1..T4 و
  /// M1..M3) وأرصدة الحسابات والصناديق وقوائم المستندات وقراءة
  /// أسطرها والأحداث — وقد كان كلها تمسح الجدول كله بلا فهرس
  /// (فهارس القاعدة قبل هذه الدفعة سبعة حصراً) فكانت التكلفة
  /// الجذرية على قاعدة ضخمة O(N×M) في أسوأها (T4: EXISTS لكل
  /// فاتورة على moves بلا فهرس — والقاعدة التجريبية الكبيرة س214:
  /// 3,863 فاتورة على قيودها كانت تكلفة كل فتح). آمنة التكرار كلها
  /// بـIF NOT EXISTS (عرف الفهارس الموثقة — درس س86: فهرس
  /// @TableIndex يكسر نداءات createAll المتعددة عبر خطوات الترقية
  /// فالعرف customStatement)، وتُبنى من أول إنشاء (onCreate) ومن
  /// الترحيلة v35 لأي قاعدة قائمة أي كان مسار وصولها.
  Future<void> _createHotDataIndexes() async {
    // الدفتر — رصيد الحساب (accountBalanceOf/postedLedgerLines) وفحص
    // M3 (سطر ذمة على 112/211) ومطابقات الأرصدة كانت تمسح move_lines
    // كاملاً لكل حساب ولا فهرس على account_id أصلاً.
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_move_lines_account ON move_lines (account_id)');
    // أعمار الذمم وفواتير الطرف وفتح ورقة الطرف — بسطر الذمة
    // (party_id) الذي كان بلا فهرس.
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_move_lines_party ON move_lines (party_id)');
    // فحص T4 (كل فاتورة مرحّلة لها قيد): NOT EXISTS لكل فاتورة على
    // moves بربط (ref_doc_type، ref_doc_id) — وكان تمسح moves كاملاً
    // لكل فاتورة مرحّلة فالأولى O(N×M) على القاعدة الضخمة.
    await customStatement('CREATE INDEX IF NOT EXISTS ix_moves_ref '
        'ON moves (ref_doc_type, ref_doc_id)');
    // حقائق ما بعد الاستعادة: MAX(date_text) على moves كان مسحاً
    // كاملاً للقيود — والفهرس يجعله قراءة أعلى المؤشر.
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_moves_date_text ON moves (date_text)');
    // أرشيف الفواتير (ترتيب التاريخ الهابط) وحقائق ما بعد الاستعادة
    // (COUNT وMAX(invoice_date) بصيغة is_deleted = 0).
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_invoices_deleted_date ON invoices (is_deleted, invoice_date)');
    // فواتير الطرف (س-147/الذمم والأعمار) — بلا فهرس على party_id.
    await customStatement('CREATE INDEX IF NOT EXISTS ix_invoices_party '
        'ON invoices (party_id)');
    // أسطر الفاتورة — أثقل مسارات القراءة (تفاصيل الفاتورة والمردود
    // والحذف والاستيراد WHERE invoice_id) كانت بلا فهرس إطلاقاً.
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_invoice_lines_invoice ON invoice_lines (invoice_id)');
    // حركة الصنف من فواتيره (مطابقة المخزون ومجاميع الأصناف
    // GROUP BY item_id).
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_invoice_lines_item ON invoice_lines (item_id)');
    // حركات المخزون المرتبطة بالمستند (استيفاء الفاتورة وقراءة
    // حركاتها WHERE ref_doc_type/ref_doc_id) — كانت بلا فهرس.
    await customStatement('CREATE INDEX IF NOT EXISTS ix_stock_moves_ref '
        'ON stock_moves (ref_doc_type, ref_doc_id)');
    // تاريخ الصنف وحركة منشأه (GROUP BY item_id وإعادة بناء الأرصدة).
    await customStatement('CREATE INDEX IF NOT EXISTS ix_stock_moves_item '
        'ON stock_moves (item_id)');
    // رصيد الصندوق (_cashBoxBalanceTx وزناده وفحص M1 لكل صندوق) —
    // كان مسحاً كاملاً لكل صندوق.
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_cash_movements_box ON cash_movements (cash_box_id)');
    // الأحداث أسرع جداول نمواً (لكل عملية صف — 18,814 حدثاً بالقاعدة
    // التجريبية س214) — قراءة آخر تقديم معلق وتاريخ الكيان WHERE
    // entity_type/entity_id ORDER BY event_at كانت تمسح الجدول كله.
    await customStatement('CREATE INDEX IF NOT EXISTS ix_events_entity '
        'ON events (entity_type, entity_id, event_at)');
    // حقائق ما بعد الاستعادة: MAX(voucher_date) على السندات.
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_vouchers_date ON vouchers (voucher_date)');
    // أسطر المستندات الأخرى — بنمط أسطر الفاتورة ذاته (قراءة
    // التفاصيل WHERE doc_id بلا فهرس).
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_stock_transfer_lines_doc ON stock_transfer_lines (transfer_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_stock_count_lines_doc ON stock_count_lines (count_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'ix_assembly_lines_doc ON assembly_lines (assembly_id)');
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
        payload: await sealLogText(payload ?? await _moveSnapshot(moveId)),
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
  ///
  /// [bypassClosedPeriod] استثناءٌ محركي موثق حصراً لقيود الإقفال
  /// السنوي الثلاثة (الدفعة 32/س-21): تُرحَّل بتاريخ ذي الحجة داخل
  /// فترتها المقفلة لأنها جزء من عملية الإقفال ذاتها — فلا مسار موازٍ
  /// ولا قيد يُكتب خارج المحرك، والحاجز الباقي كاملٌ: الفترة يجب أن
  /// توجد أصلاً (MoveNoPeriod باقٍ) والتوازن والترقيم والتجميد
  /// والمُشغِّلات كما هي. القيود العادية لا تلمسه أبداً.
  Future<int> _postMoveWithinTx(
    int moveId, {
    required String sequenceKind,
    bool bypassClosedPeriod = false,
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
      var errors = validateMoveForPosting(
        draft,
        index: index,
        periods: periodInfos,
      );
      if (bypassClosedPeriod) {
        // الاستثناء الموثق (الدفعة 32/س-21): رفض الفترة المقفلة فقط
        // يسقط — وكل الأخطاء الأخرى باقية حرفاً.
        errors = errors.where((e) => e is! MoveClosedPeriod).toList();
      }
      if (errors.isNotEmpty) {
        throw LedgerValidationException(errors);
      }
      final period = findPeriodForDate(periodInfos, moveRow.dateText)!;

      // الترقيم المركزي داخل المعاملة ذاتها (07 §1.9) — الأرقام المُصدَرة
      // لا تُعاد أبداً: العدّاد يزحف عند الترحيل الناجح حصراً.
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(moveRow.dateText);
      final nextNumber = await _advanceSequenceWithinTx(sequenceKind, year);
      // الصيغة الجديدة D-169 (سنة رقمين + عدّاد مبطن بلا فاصل) — للأرقام
      // الجديدة حصراً؛ الصادرة قبلها «2026/000001» بيانات لا تُمس.
      final numberText = formatDocumentNumber(year, nextNumber,
          counterWidth: await _counterWidth());

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
  /// متقابلين، والوصف الافتراضي «عكس قيد …» بالرقم المخزن كما هو (قديم
  /// «2026/000001» أو جديد «26000001» — D-169) والمرجع محفوظ
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
          payload: await sealLogText(snapshot),
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
        // س236 (د10): النوع الجارٍ وبيتا البنك — النقدي افتراضاً
        // فالقائمة القديمة كلها نقدي بلا مساس.
        '"kind" TEXT NOT NULL DEFAULT \'cash\', '
        '"bank_name" TEXT NULL, '
        '"account_number" TEXT NULL, '
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
        // v27 (س121): مرجع الأمر المولّدة منه — طبقة الطلبات التشغيلية
        // فوق الفاتورة (07 §3.2) بلا مساس بالقلب المحاسبي.
        '"order_id" INTEGER NULL, '
        '"narration" TEXT NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    // س237 (المرحلة ج): أعمدة السطر الحر وملاحظته.
    'CREATE TABLE IF NOT EXISTS "invoice_lines" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"invoice_id" INTEGER NOT NULL, '
        '"item_id" INTEGER NOT NULL, '
        '"unit_id" INTEGER NOT NULL, '
        '"factor_at_entry" INTEGER NOT NULL DEFAULT 1, '
        // v21 (الدفعة 30/س-10/D-031): لقطة الوحدة — معرف مستوى التعبئة،
        // NULL للإدخال بالوحدة الأساسية (كل القائم قبل الدفعة).
        '"unit_level_id" INTEGER NULL, '
        '"qty" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL, '
        '"unit_price_minor" INTEGER NOT NULL DEFAULT 0, '
        '"discount_minor" INTEGER NOT NULL DEFAULT 0, '
        '"tax_rate" INTEGER NOT NULL DEFAULT 0, '
        '"is_free" INTEGER NOT NULL DEFAULT 0, '
        '"description" TEXT NULL, '
        '"note" TEXT NULL, '
        '"line_total_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"line_total_base_minor" INTEGER NOT NULL DEFAULT 0, '
        // v13 (دفعة 12/D-131/D-132): علم التسليم والمورد المسؤول —
        // علم عمل لا محاسبة، والافتراضي غير مستلم بلفظ المالك.
        '"delivered" INTEGER NOT NULL DEFAULT 0, '
        '"supplier_party_id" INTEGER NULL, '
        // v14 (دفعة 15/D-151): خانة «ملاحظة التسليم» القصيرة على السطر
        // غير المستلم — علم عمل لا محاسبة، والافتراضي بلا ملاحظة.
        '"delivery_note" TEXT NULL, '
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
        // v19 (الدفعة 28/F-034): علم «جاهز/فُكِّك» — NULL للحركات
        // العادية و«ready» لخروج التجميعي الجاهز و«broken» لحركات
        // مكونات الفكك، بقيم إنجليزية مخزنة والعرض ترجمتها الواجهة.
        '"move_detail" TEXT NULL, '
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
    // س107: إعادة تعريف موثقة (درس v9/v21/v22) — DROP قبل CREATE
    // لتحديث نصوص الحواجز المرقّمة DQ على أي مسار.
    'DROP TRIGGER IF EXISTS trg_stock_balances_no_negative',
    'DROP TRIGGER IF EXISTS trg_stock_moves_frozen_update',
    'DROP TRIGGER IF EXISTS trg_stock_moves_no_delete',
    'DROP TRIGGER IF EXISTS trg_cash_no_negative',
    'DROP TRIGGER IF EXISTS trg_cash_movements_no_delete',
    'DROP TRIGGER IF EXISTS trg_invoices_posted_frozen',
    'DROP TRIGGER IF EXISTS trg_invoice_lines_frozen_insert',
    'DROP TRIGGER IF EXISTS trg_invoice_lines_frozen_update',
    'DROP TRIGGER IF EXISTS trg_invoice_lines_frozen_delete',
    'DROP TRIGGER IF EXISTS trg_invoices_no_delete_posted',
    "CREATE TRIGGER trg_stock_balances_no_negative "
        "BEFORE UPDATE ON stock_balances FOR EACH ROW "
        "WHEN NEW.qty_base < 0 OR NEW.total_value_minor < 0 "
        "BEGIN "
        "SELECT RAISE(ABORT, 'رصيد مخزون سالب مرفوض — منع السالب (DQ-0201)'); "
        "END",
    // حركة المخزون لقطة تاريخية لا تعدل ولا تحذف (F-140/05 §7-4)
    "CREATE TRIGGER trg_stock_moves_frozen_update "
        "BEFORE UPDATE ON stock_moves FOR EACH ROW "
        "BEGIN "
        "SELECT RAISE(ABORT, 'حركة المخزون لقطة لا تعدل (DQ-0202)'); END",
    "CREATE TRIGGER trg_stock_moves_no_delete "
        "BEFORE DELETE ON stock_moves FOR EACH ROW "
        "BEGIN "
        "SELECT RAISE(ABORT, 'حركة المخزون لا تحذف (DQ-0203)'); END",
    // منع سالب الصندوق (05 §7-2/س8) — الرصيد = الافتتاحي + الداخل − الخارج
    "CREATE TRIGGER trg_cash_no_negative "
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
        "(DQ-0301)'); END",
    // حركة الصندوق لقطة لا تحذف (05 §7-4)
    "CREATE TRIGGER trg_cash_movements_no_delete "
        "BEFORE DELETE ON cash_movements FOR EACH ROW "
        "BEGIN "
        "SELECT RAISE(ABORT, 'حركة الصندوق لا تحذف (DQ-0302)'); END",
    // تجميد الفاتورة المرحّلة — حقولها المالية لا تعدل (05 §4.1/F-052)
    // والحالة تُدار بالمحرك (الجزئية/المدفوعة مشتقة بالسندات دفعة 5)
    "CREATE TRIGGER trg_invoices_posted_frozen "
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
        "(DQ-0204)'); END",
    // أسطر الفاتورة تجمد بلحظة الترحيل (نمط أسطر القيود F-055)
    "CREATE TRIGGER trg_invoice_lines_frozen_insert "
        "BEFORE INSERT ON invoice_lines FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = NEW.invoice_id) "
        "<> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الفاتورة المرحّلة لا تضاف (DQ-0205)'); END",
    // v13 (D-131): الصيغة المحدّثة لحرس تجميد أسطر المرحّل — تجميد
    // الحقول المالية والبنيوية حصراً فيسمح تحديث علم التسليم
    // (delivered) والمورد المسؤول (supplier_party_id) على السطر
    // المرحّل — تحديث جزئي موثق لعلم عمل لا محاسبة بلا فك إقفال،
    // وأي مساس بمال السطر يرفض كما كان.
    // v21 (الدفعة 30/س-10): لقطة الوحدة unit_level_id ضمن المجمدة —
    // القائمة القديمة من المشغل تعاد بناؤها DROP+CREATE بالترحيلة
    // لأن CREATE IF NOT EXISTS لا تستبدل المشغل القائم.
    "CREATE TRIGGER trg_invoice_lines_frozen_update "
        "BEFORE UPDATE ON invoice_lines FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = OLD.invoice_id) "
        "<> 'draft' AND ("
        "OLD.invoice_id IS NOT NEW.invoice_id OR "
        "OLD.item_id IS NOT NEW.item_id OR "
        "OLD.unit_id IS NOT NEW.unit_id OR "
        "OLD.factor_at_entry IS NOT NEW.factor_at_entry OR "
        "COALESCE(OLD.unit_level_id,-1) IS NOT "
        "COALESCE(NEW.unit_level_id,-1) OR "
        "OLD.qty IS NOT NEW.qty OR "
        "OLD.qty_base IS NOT NEW.qty_base OR "
        "OLD.unit_price_minor IS NOT NEW.unit_price_minor OR "
        "OLD.discount_minor IS NOT NEW.discount_minor OR "
        "OLD.tax_rate IS NOT NEW.tax_rate OR "
        "OLD.line_total_doc_minor IS NOT NEW.line_total_doc_minor OR "
        "OLD.line_total_base_minor IS NOT NEW.line_total_base_minor) "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الفاتورة المرحّلة لا تعدل (DQ-0206)'); END",
    "CREATE TRIGGER trg_invoice_lines_frozen_delete "
        "BEFORE DELETE ON invoice_lines FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = OLD.invoice_id) "
        "<> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الفاتورة المرحّلة لا تحذف (DQ-0207)'); END",
    // الفاتورة المرحّلة لا تحذف — التصحيح بمردود (05 §4.1/§7-4)
    "CREATE TRIGGER trg_invoices_no_delete_posted "
        "BEFORE DELETE ON invoices FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN "
        "SELECT RAISE(ABORT, 'الفاتورة المرحّلة لا تحذف — التصحيح بمردود (DQ-0208)'); "
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

/// جداول الدفعة 24 — تحويل الأصناف بين مستودعات (س-18/F-045 أولى م2):
/// جدولان جديدان خالصان ببنية اصطلاح «كل جدول» (D-055) — الرأس بلا
/// مسودة أصلاً (يُنشأ مرحّلاً فالرفض قبل الكتابة حصراً — س-18: لا ذمة
/// ولا صندوق في التحويل فلا مسودة تحتاجها)، وأسطره بلقطة كلفة السطر.
/// والمُشغِّلات الحواجز بنمط لقطات الحركات (F-140): التحويل المرحّل
/// لقطة تاريخية لا تعدل ولا تحذف — والحركات الخلفية مرجعيتها إليه
/// فتجريدها تعني فقد أثر التدقيق (07 §2.3).
Future<void> _createTransferTables() async {
  const statements = <String>[
    'CREATE TABLE IF NOT EXISTS "stock_transfers" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"transfer_date" TEXT NOT NULL, '
        '"from_warehouse_id" INTEGER NOT NULL, '
        '"to_warehouse_id" INTEGER NOT NULL, '
        '"narration" TEXT NULL, '
        '"state" TEXT NOT NULL DEFAULT \'posted\', '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "stock_transfer_lines" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"transfer_id" INTEGER NOT NULL, '
        '"item_id" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL, '
        '"unit_level_id" INTEGER NULL, '
        '"qty_doc" INTEGER NULL, '
        '"factor_at_entry" INTEGER NULL, '
        '"unit_cost_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"value_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    // الحاجز — تجميد الرأس (نمط trg_stock_moves_frozen_update/F-140)
    // س107: إعادة تعريف موثقة — DROP قبل CREATE لتحديث الرموز DQ.
    'DROP TRIGGER IF EXISTS trg_stock_transfers_frozen_update',
    'DROP TRIGGER IF EXISTS trg_stock_transfers_frozen_delete',
    'DROP TRIGGER IF EXISTS trg_stock_transfer_lines_frozen_update',
    'DROP TRIGGER IF EXISTS trg_stock_transfer_lines_frozen_delete',
    'CREATE TRIGGER trg_stock_transfers_frozen_update '
        'BEFORE UPDATE ON stock_transfers FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'تحويل المستودعات لقطة تاريخية — لا تعديل "
        "(DQ-0401)'); "
        'END',
    'CREATE TRIGGER trg_stock_transfers_frozen_delete '
        'BEFORE DELETE ON stock_transfers FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'تحويل المستودعات لا يُحذف — لقطة تاريخية "
        'والعكس بمردود لا بحذف (DQ-0402)\'); '
        'END',
    'CREATE TRIGGER trg_stock_transfer_lines_frozen_update '
        'BEFORE UPDATE ON stock_transfer_lines FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'سطر التحويل لقطة تاريخية — لا تعديل (DQ-0403)'); "
        'END',
    'CREATE TRIGGER trg_stock_transfer_lines_frozen_delete '
        'BEFORE DELETE ON stock_transfer_lines FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'سطر التحويل لا يُحذف — لقطة تاريخية (DQ-0404)'); "
        'END',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

Future<Map<String, Object?>?> _itemByIdTx(int id) async {
  final rows = await customSelect(
    // س-10 (الدفعة 30): unit_group_id مع القراءة — مدقق مستوى التعبئة
    // يفحص انتماء المستوى لمجموعة الصنف من هذه القراءة ذاتها.
    'SELECT id, sku, name, kind, base_unit_id, is_active, '
    'purchase_price_minor, unit_group_id FROM items '
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

/// س111: كميات الدخول المرجعة بمردودات أصل بيع لكل صنف — موازين
/// الجاهز والفكك بالمرآة النسبية (كميات لا قيم).
Future<Map<int, int>> _returnedInQtyByItemTx(int originalInvoiceId) async {
  final rows = await customSelect(
    "SELECT sm.item_id AS item_id, SUM(sm.qty_base) AS q "
    "FROM stock_moves sm JOIN invoices i ON i.id = sm.ref_doc_id "
    "WHERE sm.ref_doc_type = 'invoice' AND i.original_invoice_id = ?1 "
    "AND i.kind = 'sale_return' AND sm.qty_base > 0 GROUP BY sm.item_id",
    variables: [Variable.withInt(originalInvoiceId)],
  ).get();
  return {for (final r in rows) r.data['item_id'] as int: r.data['q'] as int};
}

/// س111: رجل 211 الدائنة بقيد أصل البيع (D-190) — لقطة تكلفة
/// الخدمات المفككة التي عُدّلت على المورد الخارجي.
Future<int> _originalServiceCreditTx(int originalInvoiceId) async {
  final acc211 = await _accountIdByCodeTx('211');
  final row = await customSelect(
    'SELECT COALESCE(SUM(ml.credit_minor), 0) AS v '
    'FROM move_lines ml JOIN moves m ON m.id = ml.move_id '
    "WHERE m.ref_doc_type = 'invoice' AND m.ref_doc_id = ?1 "
    'AND ml.account_id = ?2',
    variables: [
      Variable.withInt(originalInvoiceId),
      Variable.withInt(acc211),
    ],
  ).getSingle();
  return row.data['v'] as int;
}

/// س111: ما عُكس سلفاً من رجل 211 بمردودات أصل بيع — كي لا يتجاوز
/// العكسُ الرجلَ الأصلية مهما تعددت المردودات.
Future<int> _returnedServiceReversalTx(int originalInvoiceId) async {
  final acc211 = await _accountIdByCodeTx('211');
  final row = await customSelect(
    'SELECT COALESCE(SUM(ml.debit_minor), 0) AS v '
    'FROM move_lines ml JOIN moves m ON m.id = ml.move_id '
    'JOIN invoices i ON i.id = m.ref_doc_id '
    "WHERE m.ref_doc_type = 'invoice' AND i.original_invoice_id = ?1 "
    "AND i.kind = 'sale_return' AND ml.account_id = ?2",
    variables: [
      Variable.withInt(originalInvoiceId),
      Variable.withInt(acc211),
    ],
  ).getSingle();
  return row.data['v'] as int;
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
    'SELECT id, invoice_id, item_id, unit_id, factor_at_entry, '
    'unit_level_id, qty, '
    'qty_base, unit_price_minor, discount_minor, tax_rate, '
    'line_total_doc_minor, line_total_base_minor, uuid, delivered, '
    'supplier_party_id, delivery_note, '
    'is_free, description, note '
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
        // v21 (س-10): لقطة الوحدة مع السطر — null للأساسية.
        unitLevelId: r.data['unit_level_id'] as int?,
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
        // س-153/D-151 (دفعة 15): خانة «ملاحظة التسليم» مع السطر.
        deliveryNote: r.data['delivery_note'] as String?,
        // س237 (المرحلة ج): الحرة الثلاثة مع السطر.
        isFree: (r.data['is_free'] as int? ?? 0) == 1,
        description: r.data['description'] as String?,
        note: r.data['note'] as String?,
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
          'factor_at_entry': l.factorAtEntry,
          'unit_level_id': l.unitLevelId,
          'qty': l.qty,
          'qty_base': l.qtyBase,
          'unit_price_minor': l.unitPriceMinor,
          'discount_minor': l.discountMinor,
          'line_total_doc_minor': l.lineTotalDocMinor,
          'line_total_base_minor': l.lineTotalBaseMinor,
          // س-153/D-151: الملاحظة بلقطة السطر الكاملة (07 §2.3).
          'delivery_note': l.deliveryNote,
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
      payload: await sealLogText(payload ?? await _invoiceSnapshotTx(invoiceId)),
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
          // v21 (س-10): اللقطة المخزنة تعود للمسودة كما خزنت — الكمية
          // بوحدة الاختيار ومستواها، والتحقق على ما خُزّن لا على ما قيل.
          qty: l.qty,
          unitLevelId: l.unitLevelId,
          unitPriceMinor: l.unitPriceMinor,
          discountMinor: l.discountMinor,
          taxRate: l.taxRate,
          // س237: الحرة الثلاثة تعود مع المسودة — فالترحيل يعيد
          // بناءها من الصفوف لا من الذاكرة.
          isFree: l.isFree,
          description: l.description,
          note: l.note,
        ),
    ],
  );
}

/// تخطيط الأسطر المخزنية لكل أنواع الفواتير — البضاعة والتجميعي حصراً
/// (الخدمة بلا مخزون ولا تكلفة — س-08): دخول الشراء صافي السطر (والتجميعي
/// يدخل الجاهز مباشرة بلا فكك — F-034)، وخروج البيع والمردود الشرائي
/// بالمتوسط الجاري المتسلسل (D-067)، ودخول مردود البيع بلقطة كلفة الأصل
/// ويمتص آخر مردود ما تبقى من قيمتها (م-25/D-067) — وبيع التجميعي
/// بالجاهز أولاً ثم الفكك بمكوناته (F-034/الدفعة 28). أخطاء الاكتفاء
/// تضاف إلى [errors] (منع السالب — F-042).
///
/// س102: بالإعداد المعتمد (heldInvoicesReserveQty) وفاتورة البيع حصراً
/// تُخصم حجوزات المعلّقات من رصيد الفحص فلا بيعٌ مباشر ولا مسودةٌ
/// معلّقة جديدة تبتلع حجزَ غيرها — و[excludeReservationOfInvoiceId]
/// يستثني الفاتورة قيد الترحيل حتى لا يحجزها القديم ضدّ اعتمادها
/// (اعتماد المعلّقة يحرر حجزها إلى الخصم الفعلي). وبالإعداد المطفأ
/// الفحص كما كان س101 حرفاً: مسودة لا مساس بالكمية.
Future<List<_StockLinePlan>> _planStockLines(
  InvoiceDraft draft,
  List<InvoiceLineResult> results,
  List<InvoiceValidationError> errors, {
  int? excludeReservationOfInvoiceId,

  /// س110 (D-190): تكلفة الخدمات المفككة لسطر التجميعي — تجمعها الخريطة
  /// (lineIndex ← مجموع تكاليف الخدمات المفككة بالأساسية) لتُقيد
  /// 51 مديناً ضمن السطر المركب و211 دائناً بلا طرف في postInvoice
  /// حصراً — والفراغ (خدمة بلا خانة تكلفة) بند بيعي ضمن السعر فلا قيد.
  Map<int, int>? serviceCostsByLine,

  /// س111: عكس تكلفة الخدمات المفككة بمردود بيع التجميعي —
  /// (lineIndex ← الحصة المرجعة) تُقيد 211 مديناً و51 دائناً في
  /// postInvoice حصراً — من رجل الأصل 211 لا بإعادة حساب.
  Map<int, int>? serviceRestoreByLine,
}) async {
  final plans = <_StockLinePlan>[];
  if (draft.warehouseId == null) return plans;
  final sim = _StockSim(_stockBalanceTx, draft.warehouseId!);
  // س102: خريطة الحجز تُقرأ مرة واحدة هنا فيصدق الفحص المتسلسل كلّه
  // عليها — والمردود الشرائي (خروج مخزني برفقه البيع) يفحص الرصيد
  // الفعلي حصراً بلا حجز (حد الدفعة، موثق بالحدود الصادقة).
  final reserveOn = draft.kind == InvoiceKind.sale &&
      await heldInvoicesReserveQty();
  final reserved = reserveOn
      ? await heldSaleReservationsByItem(
          warehouseId: draft.warehouseId!,
          excludeInvoiceId: excludeReservationOfInvoiceId)
      : const <int, int>{};
  int reservedOf(int itemId) => reserveOn ? (reserved[itemId] ?? 0) : 0;
  final origMoveQty = <int, int>{};
  final origMoveVal = <int, int>{};
  final returnedQty = <int, int>{};
  // س111: موازين المرآة النسبية لمردود التجميعي.
  final restoredQty = <int, int>{};
  final origLineQty = <int, int>{};
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
      // س111: موازين المرآة النسبية — كميات الدخول المرجعة لكل صنف
      // (حركات المردودات السابقة) وكميات أسطر الأصل المبيعة.
      restoredQty.addAll(await _returnedInQtyByItemTx(draft.originalInvoiceId!));
      origLineQty.addAll(await _origQtyByItemTx(draft.originalInvoiceId!));
    }
  }
  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    final item = await _itemByIdTx(line.itemId);
    if (item == null) continue;
    final kind = item['kind'] as String;
    // الخدمة بلا مخزون ولا تكلفة — والبضاعة والتجميعي مخزونيان.
    if (kind == 'service') continue;
    final label =
        itemDisplayLabel(item['name'] as String, item['sku'] as String);

    // س111: مردود بيع التجميعي — المرآة النسبية فوق اللقطات القائمة
    // (م-25 لكل صنف بعينه): ما خرج جاهزاً يعود للتجميعي وما فُكك
    // يعود لمكوناته بأعرافها، وتكلفة الخدمات المفككة تُعكس من 211
    // (عكس D-190) — والقيم من لقطات حركات الأصل بالآلية القائمة.
    if (draft.kind == InvoiceKind.saleReturn && kind == 'bundle') {
      final originalId = draft.originalInvoiceId!;
      final soldQty = origLineQty[line.itemId] ?? 0;
      final readyExited = origMoveQty[line.itemId] ?? 0;
      final remainingReady = readyExited - (restoredQty[line.itemId] ?? 0);
      final brokenExited = soldQty - readyExited;
      // الحصة الجاهزة نسبةً لبنية خروج الأصل مقيدةً بالمتبقي الجاهز.
      var readyShare = soldQty <= 0
          ? 0
          : roundHalfAwayFromZeroRatio(line.qtyBase * readyExited, soldQty);
      if (readyShare > remainingReady) readyShare = remainingReady;
      if (readyShare < 0) readyShare = 0;
      var brokenShare = line.qtyBase - readyShare;
      // سعة الفكك المتبقية: أضيق مكوّن بضاعة بكمية وصفته — وحصة
      // الفكك لا تتجاوزها وإلا رُفض السطر بالمتبقي القابل للاستعادة.
      final recipe = await _bundleRecipeTx(line.itemId);
      int? capacity;
      for (final r in recipe) {
        if ((r['kind'] as String) == 'service') continue;
        final per = r['qty_base'] as int;
        if (per <= 0) continue;
        final cid = r['component_item_id'] as int;
        final remainingC =
            (origMoveQty[cid] ?? 0) - (restoredQty[cid] ?? 0);
        final cap = remainingC > 0 ? remainingC ~/ per : 0;
        if (capacity == null || cap < capacity) capacity = cap;
      }
      final effective = remainingReady + (capacity ?? 0);
      if (line.qtyBase > effective) {
        errors.add(InvoiceReturnQtyExceedsRemaining(i, label, effective));
        continue;
      }
      if (brokenShare > (capacity ?? 0)) brokenShare = capacity ?? 0;
      // الجاهز: دخول بلقطة خروج الأصل (م-25) والنظير بالمتوسط الجاري
      // والفرق على 58 — بالصيغة العامة ذاتها بكمية الحصة الجاهزة.
      if (readyShare > 0) {
        final (qty, value) = await sim.of(line.itemId);
        final wac = wacExitValue(value, qty, readyShare);
        final vOrig = origMoveVal[line.itemId] ?? 0;
        final remainingValue = vOrig - (restoredVal[line.itemId] ?? 0);
        final restore = readyShare >= remainingReady
            ? remainingValue
            : (readyExited <= 0
                ? 0
                : roundHalfAwayFromZeroRatio(
                    vOrig * readyShare, readyExited));
        sim.apply(line.itemId, readyShare, restore);
        plans.add(_StockLinePlan(
          lineIndex: i,
          itemId: line.itemId,
          qtyBase: readyShare,
          stockValueMinor: restore,
          counterpartMinor: wac,
        ));
      }
      // مكونات الفكك: تعود بأعرافها بكمياتها الوصفية × حصة الفكك
      // وبلقطات خروجها ذاتها.
      if (brokenShare > 0) {
        for (final r in recipe) {
          if ((r['kind'] as String) == 'service') continue;
          final per = r['qty_base'] as int;
          if (per <= 0) continue;
          final cid = r['component_item_id'] as int;
          final qRestore = per * brokenShare;
          final (qty, value) = await sim.of(cid);
          final wac = wacExitValue(value, qty, qRestore);
          final qOrigC = origMoveQty[cid] ?? 0;
          final vOrigC = origMoveVal[cid] ?? 0;
          final remainingC = qOrigC - (restoredQty[cid] ?? 0);
          final remainingValueC = vOrigC - (restoredVal[cid] ?? 0);
          final restoreC = qRestore >= remainingC
              ? remainingValueC
              : (qOrigC <= 0
                  ? 0
                  : roundHalfAwayFromZeroRatio(vOrigC * qRestore, qOrigC));
          sim.apply(cid, qRestore, restoreC);
          plans.add(_StockLinePlan(
            lineIndex: i,
            itemId: cid,
            qtyBase: qRestore,
            stockValueMinor: restoreC,
            counterpartMinor: wac,
            detail: 'broken',
          ));
        }
        // عكس تكلفة الخدمات المفككة (عكس D-190): من رجل الأصل 211
        // دائناً حصراً لا بإعادة حساب — والحصة نسبةً لحصة الفكك
        // المرجعة، مقيدة بمتبقي الرجل عن مردودات الأصل كلها.
        final sOrig = await _originalServiceCreditTx(originalId);
        if (sOrig > 0 && brokenExited > 0) {
          final reversed = await _returnedServiceReversalTx(originalId);
          final remainingService = sOrig - reversed;
          if (remainingService > 0) {
            var rev = roundHalfAwayFromZeroRatio(
                sOrig * brokenShare, brokenExited);
            if (rev > remainingService) rev = remainingService;
            if (rev > 0) {
              serviceRestoreByLine?[i] =
                  (serviceRestoreByLine[i] ?? 0) + rev;
            }
          }
        }
      }
      continue;
    }

    if (draft.kind == InvoiceKind.purchase) {
      // الدخول بقيمة السطر الصافية (بعد خصمه — «لا يمس كلفة المخزون»
      // معناه الخصم يخفض الكلفة لا يفصل حساباً — 05 §4.1) — والتجميعي
      // يدخل الجاهز مباشرة بلا فكك (الوصفة لا تفعل شيئاً في الشراء
      // الجاهز — F-034).
      plans.add(_StockLinePlan(
        lineIndex: i,
        itemId: line.itemId,
        qtyBase: line.qtyBase,
        stockValueMinor: results[i].baseMinor,
        counterpartMinor: results[i].baseMinor,
      ));
      continue;
    }

    // بيع التجميعي — الجاهز أولاً ثم الفكك (F-034/الدفعة 28 حرفاً)،
    // وس102: الحجز على كمية سطر الأب فيخصم من الجاهز المعروض للغير
    // (وإن فاض المطلوب على الجاهز بعد الخصم فالفكك بعرفه القائم).
    if (draft.kind == InvoiceKind.sale && kind == 'bundle') {
      final (bundleQty, bundleValue) = await sim.of(line.itemId);
      if (line.qtyBase <= bundleQty - reservedOf(line.itemId)) {
        // الجاهز يكفي — لا فكك ولا مساس بالوصفة والمكونات، وخروج
        // بالمتوسط الحاكم (F-047/D-067) بعلم «جاهز».
        final exit = wacExitValue(bundleValue, bundleQty, line.qtyBase);
        sim.apply(line.itemId, -line.qtyBase, -exit);
        plans.add(_StockLinePlan(
          lineIndex: i,
          itemId: line.itemId,
          qtyBase: line.qtyBase,
          stockValueMinor: exit,
          counterpartMinor: exit,
          detail: 'ready',
        ));
        continue;
      }
      // النقص يفكك — الوصفة إلزاماً وسلامة مكوناتها شرطاً (س-09/F-034).
      final recipe = await _bundleRecipeTx(line.itemId);
      if (recipe.isEmpty) {
        errors.add(InvoiceBundleRecipeRequired(i, label));
        continue;
      }
      final inputs = <BundleComponentStockInput>[];
      final componentLabels = <int, String>{};
      var recipeInvalid = false;
      for (final r in recipe) {
        final compId = r['component_item_id'] as int;
        final compKind = r['kind'] as String;
        final compLabel = itemDisplayLabel(
            r['name'] as String, r['sku'] as String);
        componentLabels[compId] = compLabel;
        if ((r['is_active'] as int) == 0) {
          errors.add(InvoiceBundleInvalid(
              i, label, 'المكوّن «$compLabel» معطل'));
          recipeInvalid = true;
          continue;
        }
        if (compKind == 'bundle') {
          errors.add(InvoiceBundleInvalid(i, label,
              'المكوّن «$compLabel» تجميعي — لا تداخل وصفة (بضاعة أو خدمة حصراً)'));
          recipeInvalid = true;
          continue;
        }
        final isService = compKind == 'service';
        final (sq, sv) = isService ? (0, 0) : await sim.of(compId);
        inputs.add(BundleComponentStockInput(
          itemId: compId,
          isService: isService,
          qtyPerBundle: r['qty_base'] as int,
          serviceCostMinor: r['cost_minor'] as int?,
          stockQty: sq,
          stockValue: sv,
        ));
      }
      if (recipeInvalid) continue;

      final outcome = planBundleSaleBreakdown(
        saleQtyBase: line.qtyBase,
        bundleReadyQty: bundleQty,
        bundleReadyValue: bundleValue,
        components: inputs,
      );
      var blocked = false;
      for (final e in outcome.errors) {
        switch (e) {
          case BundleSaleRecipeRequired():
            errors.add(InvoiceBundleRecipeRequired(i, label));
            blocked = true;
          case BundleSaleComponentInsufficient(
              :final componentItemId,
              :final neededQty,
              :final availableQty
            ):
            errors.add(InvoiceBundleComponentInsufficient(
              i,
              componentLabels[componentItemId] ??
                  'معرف $componentItemId',
              neededQty,
              availableQty,
            ));
            blocked = true;
        }
      }
      if (blocked) continue;

      final bp = outcome.plan;
      // الجاهز أولاً — خروج التجميعي بعلمه (F-034: علم «جاهز»).
      if (bp.readyQty > 0) {
        sim.apply(line.itemId, -bp.readyQty, -bp.readyValueMinor);
        plans.add(_StockLinePlan(
          lineIndex: i,
          itemId: line.itemId,
          qtyBase: bp.readyQty,
          stockValueMinor: bp.readyValueMinor,
          counterpartMinor: bp.readyValueMinor,
          detail: 'ready',
        ));
      }
      // النقص يفكك — مكونات البضاعة بحركاتها بعلم «فُكِّك»، والخدمة
      // بلا حركة ولا خطة (بلا مساس قيمةً ولا كميةً — F-212) — وتكلفتها
      // × المفكك تُجمع لخريطة D-190 (س110) فتقيد 51/211 بلا طرف عند
      // الترحيل حصراً، والفراغ بند بيعي ضمن السعر فلا قيد له.
      for (final c in bp.components) {
        if (c.isService) {
          if (c.valueMinor > 0) {
            serviceCostsByLine?[i] =
                (serviceCostsByLine[i] ?? 0) + c.valueMinor;
          }
          continue;
        }
        if (c.qtyOut == 0) continue;
        sim.apply(c.itemId, -c.qtyOut, -c.valueMinor);
        plans.add(_StockLinePlan(
          lineIndex: i,
          itemId: c.itemId,
          qtyBase: c.qtyOut,
          stockValueMinor: c.valueMinor,
          counterpartMinor: c.valueMinor,
          detail: 'broken',
        ));
      }
      continue;
    }

    if (draft.kind == InvoiceKind.sale ||
        draft.kind == InvoiceKind.purchaseReturn) {
      // الخروج بالقيمة الدفترية الجارية — متسلسل بالترتيب (D-067)،
      // وس102: بالبيع حصراً يُخصم حجز المعلّقات فيقول الخطأ صادقاً
      // بالمتاح بعد الحجز لا بالرصيد الخام (F-042 بلسان الواقع).
      final (qty, value) = await sim.of(line.itemId);
      final reservedOut = reservedOf(line.itemId);
      if (line.qtyBase > qty - reservedOut) {
        // س165: المتاح المعلن لا يكون سالباً — الحجز الفوقي (الإفراط
        // حجزٌ لا بيع) يصفّر الإعلان فيقول الخطأ صادقاً بصفر المتاح
        // بعد الحجز لا برقم سالب، والرفضُ بذاته باقٍ حرفاً فالحاكم
        // لحظة الترحيل «من رحّل أولاً غلب».
        final announced = qty - reservedOut;
        errors.add(InvoiceStockInsufficient(
            i, label, announced < 0 ? 0 : announced));
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

/// قراءة وصفة تجميعي بمكوناتها من القاعدة — انعكاس مستخدم بالمخطط
/// (نمط القراءات الداخلية للمحرك): نوع كل مكوّن وتفعيله واسمه وكمية
/// الوصفة وتكلفة الخدمة (F-212).
Future<List<Map<String, Object?>>> _bundleRecipeTx(int bundleItemId) async {
  final rows = await customSelect(
    'SELECT bc.component_item_id, bc.qty_base, bc.cost_minor, '
    'i.kind, i.name, i.sku, i.is_active '
    'FROM bundle_components bc '
    'JOIN items i ON i.id = bc.component_item_id '
    'WHERE bc.bundle_item_id = ?1 AND bc.is_deleted = 0 '
    'ORDER BY bc.id',
    variables: [Variable.withInt(bundleItemId)],
  ).get();
  return [for (final r in rows) r.data];
}

/// جمع أخطاء الفاتورة بمعطيات القاعدة — التسلسل التدريجي المعتمد:
/// البنية ثم الزمن (عند الترحيل) ثم الأسطر (الوجود والتفعيل والوحدة
/// والنوع) ثم المستودع ثم جهة الدفع ثم الأصل والمتبقي للمردود ثم
/// الاكتفاء (المخزون والصندوق). «رسالة واحدة أول خطأ» عرضاً (نمط س-36)
/// والقائمة كاملة للفحص.
Future<List<InvoiceValidationError>> _collectInvoiceErrors(
  InvoiceDraft draft, {
  required bool forPosting,

  /// س102: فاتورة قيد الترحيل تُستثنى من حجزها القديم (الاعتماد يحرر
  /// حجز المعلّقة إلى الخصم الفعلي) — وnull عند الإنشاء فلا ذات بعد.
  int? excludeReservationOfInvoiceId,
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
  var hasStock = false;
  for (final line in draft.lines) {
    final item = await _itemByIdTx(line.itemId);
    itemByLine.add(item);
    // البضاعة والتجميعي مخزونيان — والتجميعي رصيده الجاهز (F-034).
    if (item != null &&
        ((item['kind'] as String) == 'good' ||
            (item['kind'] as String) == 'bundle')) {
      hasStock = true;
    }
  }
  for (var i = 0; i < draft.lines.length; i++) {
    final item = itemByLine[i];
    final line = draft.lines[i];
    // س237 (المرحلة ج): السطر الحر بلا صنف أصلاً — فحص الصنف
    // يخطاه وعقده البنيوية فُحصت بالمدقق (وصف وسعر يدوي موجب)،
    // والخطة والمجاميع تجريانه بلا مخزون.
    if (item == null) {
      if (!line.isFree) {
        errors.add(InvoiceItemNotFound(i, line.itemId));
      }
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
    // س-10 (الدفعة 30): مسار مستوى التعبئة — المستوى من مجموعة الصنف
    // حصراً والتحويل بعامله الحالي، والكمية بالأساسية محسوبة به فلا
    // يمر سطرٌ لا يلتقي حواملُه. والتحقق على ما خُزّن لا على ما قيل:
    // فاتورة تُرحّل بعد تغيّر العامل تُرفض فتعاد مسودتها (المسودة
    // حرة الحذف والفاصل موثق برسالته).
    if (line.unitLevelId != null) {
      final groupId = item['unit_group_id'] as int?;
      var levelValid = false;
      int levelFactor = 0;
      if (groupId != null) {
        final levelRows = await customSelect(
          'SELECT group_id, factor FROM unit_group_levels '
          'WHERE id = ? AND is_deleted = 0',
          variables: [Variable.withInt(line.unitLevelId!)],
        ).get();
        if (levelRows.isNotEmpty) {
          final level = levelRows.first.data;
          if (level['group_id'] as int == groupId) {
            levelFactor = level['factor'] as int;
            levelValid = levelFactor >= 2;
          }
        }
      }
      if (!levelValid) {
        errors.add(InvoiceUnitLevelInvalid(i, label));
      } else {
        final chosenQty = line.qty ?? line.qtyBase;
        if (chosenQty * levelFactor != line.qtyBase) {
          errors.add(InvoiceUnitFactorMismatch(
              i, label, chosenQty, levelFactor, line.qtyBase));
        }
      }
    } else if ((line.qty ?? line.qtyBase) != line.qtyBase) {
      // سطر بلا مستوى فكميته بالأساسية ذاتها — اختلافهما بيانات لا
      // تلتقي (حرس بيانات لا يلمسه المسار الطبيعي).
      errors.add(InvoiceUnitFactorMismatch(
          i, label, line.qty ?? line.qtyBase, 1, line.qtyBase));
    }
    final kind = item['kind'] as String;
    // التجميعي يُشترى جاهزاً ويُبَع بالجاهز أولاً ثم الفكك (F-034) —
    // ومردود بيعه قاعدةُ المرآة النسبية (س111) فخطته أسفله تحكم.
    if (draft.kind == InvoiceKind.purchase && kind == 'service') {
      errors.add(InvoiceServiceInPurchase(i, label));
    }
  }

  if (hasStock) {
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

  // س121 — حرس مرجع الأمر (07 §3.2/D-026): الفاتورة المرجعة لأمر
  // تتطلب الأمر مؤكداً (DQ-0707 عرفاً) وأسطرها لا تتجاوز متبقي كل
  // صنف (الوفاء لا يتجاوز الالتزام) — بنمط فحص المردود عن الأصل
  // حرفاً، والمتبقي محسوبٌ من بقية فواتير الأمر فلا تحسب فاتورةٌ
  // نفسها مرتين (إنشاءً أو ترحيلاً بالاستثناء الممرر).
  if (draft.orderId != null) {
    final orderRow = await customSelect(
      'SELECT id, state, direction FROM orders WHERE id = ? '
      'AND is_deleted = 0',
      variables: [Variable.withInt(draft.orderId!)],
    ).getSingleOrNull();
    if (orderRow == null) {
      errors.add(InvoiceOrderNotFound(draft.orderId!));
    } else if ((orderRow.data['state'] as String) !=
        OrderState.confirmed.storageValue) {
      errors.add(InvoiceOrderNotConfirmed(
          draft.orderId!,
          OrderState.fromStorage(orderRow.data['state'] as String).label));
    } else {
      final fulfilled = await orderFulfilledQtyByItem(draft.orderId!,
          excludeInvoiceId: excludeReservationOfInvoiceId);
      final orderedRows = await customSelect(
        'SELECT item_id, SUM(qty_base) AS ordered FROM order_lines '
        'WHERE order_id = ? AND is_deleted = 0 GROUP BY item_id',
        variables: [Variable.withInt(draft.orderId!)],
      ).get();
      final orderedByItem = <int, int>{
        for (final r in orderedRows)
          r.data['item_id'] as int: (r.data['ordered'] as num).toInt(),
      };
      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        final item = itemByLine[i];
        final label = item == null
            ? 'معرف ${line.itemId}'
            : itemDisplayLabel(item['name'] as String, item['sku'] as String);
        final remaining = (orderedByItem[line.itemId] ?? 0) -
            (fulfilled[line.itemId] ?? 0);
        if (line.qtyBase > remaining) {
          errors.add(InvoiceOrderQtyExceedsRemaining(i, label, remaining));
        }
      }
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

  // الاكتفاء: خروج المخزون (بيع/مردود شراء) يفحص بالتخطيط نفسه —
  // وس164 بالإنشاء حصراً: خيار «مسودة أكبر من المتاح» المعتمد
  // يُسقط فحص التخطيط عن الحفظ فتُحفظ المسودة التزاماً غير معلن
  // (عرف الأوامر) ويفحصها الترحيل كاملة فالحاكم لحظة الترحيل.
  // وبقية فحوص الإنشاء (البنية والمراجع والأصل والأمر والصندوق)
  // باقية حرفاً فلا مسودة فاسدة البنية مهما فُعل.
  final totals = computeInvoiceTotals(draft);
  final skipStockPlan = !forPosting && await invoiceDraftOverStock();
  if (!skipStockPlan) {
    await _planStockLines(draft, totals.lines, errors,
        excludeReservationOfInvoiceId: excludeReservationOfInvoiceId);
    if (errors.isNotEmpty) return errors;
  }

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

/// س121 — سطر الأحداث المصرية (07 §2.3): لقطة الأمر الكاملة بمعاملة
/// العملية ذاتها فلا حدث بلا عملية ولا عملية بلا حدث.
Future<void> _recordOrderEvent({
  required int orderId,
  required String action,
}) async {
  await into(events).insert(
    EventsCompanion.insert(
      eventAt: DateTime.now().millisecondsSinceEpoch,
      deviceId: await deviceId(),
      entityType: 'order',
      entityId: Value(orderId),
      action: action,
      payload: await sealLogText(await _orderSnapshot(orderId)),
      uuid: const Uuid().v4(),
    ),
  );
}

/// لقطة الأمر الكاملة للحدث (الرأس وأسطره) — JSON حرفاً.
Future<String> _orderSnapshot(int orderId) async {
  final orderRow = await customSelect(
    'SELECT * FROM orders WHERE id = ?',
    variables: [Variable.withInt(orderId)],
  ).getSingleOrNull();
  if (orderRow == null) return '{}';
  final lines = await customSelect(
    'SELECT * FROM order_lines WHERE order_id = ? ORDER BY id',
    variables: [Variable.withInt(orderId)],
  ).get();
  return jsonEncode({
    ...orderRow.data,
    'lines': lines.map((l) => l.data).toList(),
  });
}

/// حصة الوفاء بالمكافئ الأساسي لكل صنف من فواتير الأمر الحية —
/// محسوبة لا مخزنة (عرف س102/س104). فواتير الأمر بنوعَي البيع
/// والشراء حصراً (المردودات لا تأخذ مرجع الأمر أبداً)، وكل الحيّة
/// تحسباً (مسودة أو معلقة أو مرحّلة — كلها التزام قائم حتى تحذف)،
/// و[excludeInvoiceId] يستثني الفاتورة ذاتها عند الترحيل فلا تحسب
/// ضد نفسها.
Future<Map<int, int>> orderFulfilledQtyByItem(int orderId,
    {int? excludeInvoiceId}) async {
  final rows = await customSelect(
    'SELECT il.item_id AS item_id, SUM(il.qty_base) AS fulfilled '
    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'WHERE inv.order_id = ? AND inv.is_deleted = 0 '
    "AND inv.kind IN ('sale', 'purchase') "
    "${excludeInvoiceId == null ? '' : 'AND inv.id <> ? '}"
    'GROUP BY il.item_id',
    variables: [
      Variable.withInt(orderId),
      if (excludeInvoiceId != null) Variable.withInt(excludeInvoiceId),
    ],
  ).get();
  return {
    for (final r in rows)
      r.data['item_id'] as int: (r.data['fulfilled'] as num).toInt(),
  };
}

/// س121: إنشاء أمر مسودة — المدقق حرس التخزين الثاني بعد مدقق
/// الواجهة: لا مسار يكتب أمراً غير مدقق. الأمر وأسطره وحدثه
/// («created» بلقطته) معاملة واحدة (07 §2.4). المسودة بلا رقم:
/// الترقيم لحظة التأكيد حصراً (لحظة الالتزام — 07 §1.9).
Future<int> createOrderDraft(OrderDraft draft) async {
  final errors = validateOrderSpec(OrderSpec(
    direction: draft.direction,
    orderDate: draft.orderDate,
    partyId: draft.partyId,
    warehouseId: draft.warehouseId,
    expectedDate: draft.expectedDate,
    lines: draft.lines
        .map((l) => OrderLineSpec(
              itemId: l.itemId,
              unitId: l.unitId,
              unitLevelId: l.unitLevelId,
              factorAtEntry: l.factorAtEntry,
              qty: l.qty,
              qtyBase: l.qtyBase,
              unitPriceMinor: l.unitPriceMinor,
            ))
        .toList(),
  ));
  if (errors.isNotEmpty) {
    throw OrderValidationException(errors);
  }
  return transaction(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      "INSERT INTO orders (direction, number, party_id, warehouse_id, "
      "order_date, expected_date, currency_id, state, narration, uuid, "
      "created_at, updated_at, is_deleted) "
      "VALUES (?, '', ?, ?, ?, ?, ?, 'draft', ?, ?, ?, ?, 0)",
      [
        draft.direction.storageValue,
        draft.partyId,
        draft.warehouseId,
        draft.orderDate,
        draft.expectedDate,
        draft.currencyId,
        draft.narration,
        const Uuid().v4(),
        now,
        now,
      ],
    );
    final orderId = (await customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle()).data['id'] as int;
    for (final l in draft.lines) {
      await customStatement(
        'INSERT INTO order_lines (order_id, item_id, unit_id, '
        'unit_level_id, factor_at_entry, qty, qty_base, '
        'unit_price_minor, uuid, created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          orderId,
          l.itemId,
          l.unitId,
          l.unitLevelId,
          l.factorAtEntry,
          l.qty,
          l.qtyBase,
          l.unitPriceMinor,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }
    await _recordOrderEvent(orderId: orderId, action: 'created');
    return orderId;
  });
}

/// س121: تعديل أمر مسودة — المسودة حرة التحرير والمؤكد مجمّد (حاجز
/// SQL trg_orders_frozen الظهير الدائم، والفحص الصريح هنا يرفض
/// بأصحّ لسان). الحدث «updated» بلقطته داخل المعاملة ذاتها.
Future<void> updateOrderDraft(int orderId, OrderDraft draft) async {
  final errors = validateOrderSpec(OrderSpec(
    direction: draft.direction,
    orderDate: draft.orderDate,
    partyId: draft.partyId,
    warehouseId: draft.warehouseId,
    expectedDate: draft.expectedDate,
    lines: draft.lines
        .map((l) => OrderLineSpec(
              itemId: l.itemId,
              unitId: l.unitId,
              unitLevelId: l.unitLevelId,
              factorAtEntry: l.factorAtEntry,
              qty: l.qty,
              qtyBase: l.qtyBase,
              unitPriceMinor: l.unitPriceMinor,
            ))
        .toList(),
  ));
  if (errors.isNotEmpty) {
    throw OrderValidationException(errors);
  }
  return transaction(() async {
    final row = await customSelect(
      'SELECT state FROM orders WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(orderId)],
    ).getSingleOrNull();
    if (row == null) {
      throw OrderValidationException(const [OrderFrozen()]);
    }
    if ((row.data['state'] as String) != 'draft') {
      throw OrderValidationException(const [OrderFrozen()]);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      'UPDATE orders SET direction = ?, party_id = ?, warehouse_id = ?, '
      'order_date = ?, expected_date = ?, currency_id = ?, narration = ?, '
      'updated_at = ? WHERE id = ?',
      [
        draft.direction.storageValue,
        draft.partyId,
        draft.warehouseId,
        draft.orderDate,
        draft.expectedDate,
        draft.currencyId,
        draft.narration,
        now,
        orderId,
      ],
    );
    await customStatement(
      'DELETE FROM order_lines WHERE order_id = ?',
      [orderId],
    );
    for (final l in draft.lines) {
      await customStatement(
        'INSERT INTO order_lines (order_id, item_id, unit_id, '
        'unit_level_id, factor_at_entry, qty, qty_base, '
        'unit_price_minor, uuid, created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          orderId,
          l.itemId,
          l.unitId,
          l.unitLevelId,
          l.factorAtEntry,
          l.qty,
          l.qtyBase,
          l.unitPriceMinor,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }
    await _recordOrderEvent(orderId: orderId, action: 'updated');
  });
}

/// س121: حذف أمر مسودة — المسودة وحدها تحذف (حاجز trg_orders_no_delete
/// الظهير) والأسطر معها في المعاملة ذاتها.
Future<void> deleteOrderDraft(int orderId) async {
  return transaction(() async {
    final row = await customSelect(
      'SELECT state FROM orders WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(orderId)],
    ).getSingleOrNull();
    if (row == null) {
      throw OrderValidationException(const [OrderFrozen()]);
    }
    if ((row.data['state'] as String) != 'draft') {
      throw OrderValidationException(const [OrderFrozen()]);
    }
    await customStatement(
      'DELETE FROM order_lines WHERE order_id = ?',
      [orderId],
    );
    await customStatement(
      'DELETE FROM orders WHERE id = ?',
      [orderId],
    );
  });
}

/// س121: تأكيد الأمر — لحظة الالتزام: فحصٌ مزدوج (المحرك ثم الحواجز)
/// وترقيم بمعاملة التأكيد ذاتها (07 §1.9 — لا رقم يُصدر بلا أمر
/// مؤكد مكتوب) وحدث «confirmed» بلقطته الرقمية.
Future<String> confirmOrder(int orderId) async {
  return transaction(() async {
    final orderRow = await customSelect(
      'SELECT * FROM orders WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(orderId)],
    ).getSingleOrNull();
    if (orderRow == null) {
      throw OrderValidationException(const [OrderFrozen()]);
    }
    final state = OrderState.fromStorage(orderRow.data['state'] as String);
    if (!isOrderTransitionAllowed(state, OrderState.confirmed)) {
      throw OrderValidationException(
          [OrderTransitionInvalid(state, OrderState.confirmed)]);
    }
    final direction = OrderDirection.fromStorage(
        orderRow.data['direction'] as String);
    final lineRows = await customSelect(
      'SELECT * FROM order_lines WHERE order_id = ? AND is_deleted = 0 '
      'ORDER BY id',
      variables: [Variable.withInt(orderId)],
    ).get();
    if (lineRows.isEmpty) {
      // حرس التأكيد الأول — الأسطر إلزاماً (DQ-0705 بنصه).
      throw const OrderValidationException([OrderLinesRequired()]);
    }
    final spec = OrderSpec(
      direction: direction,
      orderDate: orderRow.data['order_date'] as String,
      partyId: orderRow.data['party_id'] as int?,
      warehouseId: orderRow.data['warehouse_id'] as int?,
      expectedDate: orderRow.data['expected_date'] as String?,
      lines: lineRows
          .map((r) => OrderLineSpec(
                itemId: r.data['item_id'] as int,
                unitId: r.data['unit_id'] as int,
                unitLevelId: r.data['unit_level_id'] as int?,
                factorAtEntry: (r.data['factor_at_entry'] as num).toInt(),
                qty: (r.data['qty'] as num).toInt(),
                qtyBase: (r.data['qty_base'] as num).toInt(),
                unitPriceMinor:
                    (r.data['unit_price_minor'] as num).toInt(),
              ))
          .toList(),
    );
    final errors = validateOrderSpec(spec);
    if (errors.isNotEmpty) {
      // ما بقي من حرس التأكيد: الطرف والكميات (DQ-1016 عرفاً).
      throw OrderValidationException(errors);
    }
    final year =
        int.tryParse(orderRow.data['order_date'].toString().split('-').first) ??
            DateTime.now().year;
    final nextNumber = await _advanceSequenceWithinTx(
        orderSequenceKind(direction), year);
    final numberText = formatDocumentNumber(year, nextNumber);
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      "UPDATE orders SET state = 'confirmed', number = ?, updated_at = ? "
      'WHERE id = ?',
      [numberText, now, orderId],
    );
    await _recordOrderEvent(orderId: orderId, action: 'confirmed');
    return numberText;
  });
}

/// س121: إلغاء الأمر — من المسودة والمؤكدة حصراً (آلة الحالات) وما
/// كان قد حُوِّل من فواتير يبقى قائماً بذاته فلا مساس بالقلب.
Future<void> cancelOrder(int orderId) async {
  return transaction(() async {
    final orderRow = await customSelect(
      'SELECT state FROM orders WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(orderId)],
    ).getSingleOrNull();
    if (orderRow == null) {
      throw OrderValidationException(const [OrderFrozen()]);
    }
    final state = OrderState.fromStorage(orderRow.data['state'] as String);
    if (!isOrderTransitionAllowed(state, OrderState.cancelled)) {
      throw OrderValidationException(
          [OrderTransitionInvalid(state, OrderState.cancelled)]);
    }
    await customStatement(
      "UPDATE orders SET state = 'cancelled', updated_at = ? WHERE id = ?",
      [DateTime.now().millisecondsSinceEpoch, orderId],
    );
    await _recordOrderEvent(orderId: orderId, action: 'cancelled');
  });
}

/// س121: إغلاق الأمر — بعد الوفاء الكامل حصراً (حرس DQ-0706: المتبقي
/// أكبر من صفر مرفوض) والوفاء محسوب من فواتير الأمر لحظة الإغلاق.
Future<void> closeOrder(int orderId) async {
  return transaction(() async {
    final orderRow = await customSelect(
      'SELECT state FROM orders WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(orderId)],
    ).getSingleOrNull();
    if (orderRow == null) {
      throw OrderValidationException(const [OrderFrozen()]);
    }
    final state = OrderState.fromStorage(orderRow.data['state'] as String);
    if (!isOrderTransitionAllowed(state, OrderState.closed)) {
      throw OrderValidationException(
          [OrderTransitionInvalid(state, OrderState.closed)]);
    }
    final lines = await customSelect(
      'SELECT * FROM order_lines WHERE order_id = ? AND is_deleted = 0',
      variables: [Variable.withInt(orderId)],
    ).get();
    final fulfilled = await orderFulfilledQtyByItem(orderId);
    final fulfilment = computeOrderFulfilment(
      lines
          .map((r) => OrderLineSpec(
                itemId: r.data['item_id'] as int,
                unitId: r.data['unit_id'] as int,
                unitLevelId: r.data['unit_level_id'] as int?,
                factorAtEntry: (r.data['factor_at_entry'] as num).toInt(),
                qty: (r.data['qty'] as num).toInt(),
                qtyBase: (r.data['qty_base'] as num).toInt(),
              ))
          .toList(),
      fulfilled,
    );
    final closeErrors = validateOrderClose(fulfilment);
    if (closeErrors.isNotEmpty) {
      throw OrderValidationException(closeErrors);
    }
    await customStatement(
      "UPDATE orders SET state = 'closed', updated_at = ? WHERE id = ?",
      [DateTime.now().millisecondsSinceEpoch, orderId],
    );
    await _recordOrderEvent(orderId: orderId, action: 'closed');
  });
}

/// س121: قائمة الطلبات بالأحدث — بفلتر الاتجاه والحالة اختيارياً
/// (والقائمة تُعرض للدور صاحب وحدة «طلبات الشراء والبيع» حصراً —
/// المفتاح جاهز بpermissions منذ اليوم الأول).
Future<List<OrderListRow>> listOrders({
  OrderDirection? direction,
  OrderState? state,
  int limit = 200,
}) async {
  final where = <String>['o.is_deleted = 0'];
  final args = <Object?>[];
  if (direction != null) {
    where.add('o.direction = ?');
    args.add(direction.storageValue);
  }
  if (state != null) {
    where.add('o.state = ?');
    args.add(state.storageValue);
  }
  final rows = await customSelect(
    'SELECT o.*, p.name AS party_name, '
    '(SELECT COUNT(*) FROM order_lines ol WHERE ol.order_id = o.id '
    ' AND ol.is_deleted = 0) AS lines_count, '
    '(SELECT COALESCE(SUM(ol.qty_base), 0) FROM order_lines ol '
    ' WHERE ol.order_id = o.id AND ol.is_deleted = 0) AS total_qty_base '
    'FROM orders o '
    'LEFT JOIN parties p ON p.id = o.party_id '
    'WHERE ${where.join(' AND ')} '
    'ORDER BY o.id DESC LIMIT ?',
    variables: [
      for (final a in args)
        a is int ? Variable.withInt(a) : Variable.withString(a as String),
      Variable.withInt(limit),
    ],
  ).get();
  return rows
      .map((r) => OrderListRow(
            id: r.data['id'] as int,
            direction: r.data['direction'] as String,
            number: r.data['number'] as String,
            partyId: r.data['party_id'] as int?,
            partyName: r.data['party_name'] as String?,
            warehouseId: r.data['warehouse_id'] as int?,
            orderDate: r.data['order_date'] as String,
            expectedDate: r.data['expected_date'] as String?,
            currencyId: (r.data['currency_id'] as num).toInt(),
            state: r.data['state'] as String,
            narration: r.data['narration'] as String?,
            linesCount: (r.data['lines_count'] as num).toInt(),
            totalQtyBase: (r.data['total_qty_base'] as num).toInt(),
          ))
      .toList();
}

/// س121: تفصيل الأمر — الرأس وأسطره بأسماء الأصناف للعرض.
Future<(OrderListRow, List<OrderLineRow>)?> getOrderWithLines(
    int orderId) async {
  final headRows = await customSelect(
    'SELECT o.*, p.name AS party_name, '
    '(SELECT COUNT(*) FROM order_lines ol WHERE ol.order_id = o.id '
    ' AND ol.is_deleted = 0) AS lines_count, '
    '(SELECT COALESCE(SUM(ol.qty_base), 0) FROM order_lines ol '
    ' WHERE ol.order_id = o.id AND ol.is_deleted = 0) AS total_qty_base '
    'FROM orders o '
    'LEFT JOIN parties p ON p.id = o.party_id '
    'WHERE o.id = ? AND o.is_deleted = 0',
    variables: [Variable.withInt(orderId)],
  ).get();
  if (headRows.isEmpty) return null;
  final h = headRows.first;
  final head = OrderListRow(
    id: h.data['id'] as int,
    direction: h.data['direction'] as String,
    number: h.data['number'] as String,
    partyId: h.data['party_id'] as int?,
    partyName: h.data['party_name'] as String?,
    warehouseId: h.data['warehouse_id'] as int?,
    orderDate: h.data['order_date'] as String,
    expectedDate: h.data['expected_date'] as String?,
    currencyId: (h.data['currency_id'] as num).toInt(),
    state: h.data['state'] as String,
    narration: h.data['narration'] as String?,
    linesCount: (h.data['lines_count'] as num).toInt(),
    totalQtyBase: (h.data['total_qty_base'] as num).toInt(),
  );
  final lineRows = await customSelect(
    'SELECT ol.*, i.sku AS item_sku, i.name AS item_name '
    'FROM order_lines ol '
    'LEFT JOIN items i ON i.id = ol.item_id '
    'WHERE ol.order_id = ? AND ol.is_deleted = 0 ORDER BY ol.id',
    variables: [Variable.withInt(orderId)],
  ).get();
  final lines = lineRows
      .map((r) => OrderLineRow(
            id: r.data['id'] as int,
            orderId: r.data['order_id'] as int,
            itemId: r.data['item_id'] as int,
            itemSku: r.data['item_sku'] as String?,
            itemName: r.data['item_name'] as String?,
            unitId: r.data['unit_id'] as int,
            unitLevelId: r.data['unit_level_id'] as int?,
            factorAtEntry: (r.data['factor_at_entry'] as num).toInt(),
            qty: (r.data['qty'] as num).toInt(),
            qtyBase: (r.data['qty_base'] as num).toInt(),
            unitPriceMinor: (r.data['unit_price_minor'] as num).toInt(),
          ))
      .toList();
  return (head, lines);
}

/// س121: خلاصة التحويل — فحص صلاحية التحويل (المؤكد حصراً) ثم
/// الوفاء محسوباً لحظة الاستدعاء فترى الواجهة المتبقي الحقيقي.
Future<OrderConversionPreview> prepareOrderConversion(
    int orderId) async {
  final detail = await getOrderWithLines(orderId);
  if (detail == null) {
    throw OrderValidationException(const [OrderFrozen()]);
  }
  final (head, lines) = detail;
  final state = OrderState.fromStorage(head.state);
  final convertErrors = validateOrderConvertible(state);
  if (convertErrors.isNotEmpty) {
    throw OrderValidationException(convertErrors);
  }
  final fulfilled = await orderFulfilledQtyByItem(orderId);
  final fulfilment = computeOrderFulfilment(
    lines
        .map((l) => OrderLineSpec(
              itemId: l.itemId,
              unitId: l.unitId,
              unitLevelId: l.unitLevelId,
              factorAtEntry: l.factorAtEntry,
              qty: l.qty,
              qtyBase: l.qtyBase,
            ))
        .toList(),
    fulfilled,
  );
  return OrderConversionPreview(
    order: head,
    lines: lines,
    fulfilment: fulfilment,
  );
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
      'original_invoice_id, order_id, narration, uuid, created_at, '
      "updated_at, is_deleted) VALUES (?, '', ?, ?, ?, ?, ?, ?, ?, ?, "
      "?, ?, ?, ?, 'draft', NULL, ?, ?, ?, ?, ?, ?, 0)",
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
        draft.orderId,
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
      // س-10 (الدفعة 30): لقطة العامل مشتقة من السطر المتسق المدقق —
      // القسمة تامة بالضبط لأن المدقق اشترط qtyBase == qty × عامل
      // المستوى الحالي داخل المعاملة ذاتها، وبالأساسية العامل 1
      // كالقائم (qty = qtyBase).
      final factorAtEntry =
          r.line.qtyBase ~/ (r.line.qty ?? r.line.qtyBase);
      await customStatement(
        'INSERT INTO invoice_lines (invoice_id, item_id, unit_id, '
        'factor_at_entry, unit_level_id, qty, qty_base, '
        'unit_price_minor, discount_minor, '
        'tax_rate, is_free, description, note, '
        'line_total_doc_minor, line_total_base_minor, uuid, '
        'created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          invoiceId,
          // س237 (المرحلة ج): السطر الحر بلا صنف — صفر توكيدياً
          // فالمجمعات تسري والخطة تتخطاه.
          r.line.isFree ? 0 : r.line.itemId,
          r.line.isFree ? 0 : r.line.unitId,
          factorAtEntry,
          r.line.unitLevelId,
          r.line.qty ?? r.line.qtyBase,
          r.line.qtyBase,
          r.line.unitPriceMinor,
          r.line.discountMinor,
          r.line.taxRate,
          r.line.isFree ? 1 : 0,
          r.line.isFree ? (r.line.description ?? '') : null,
          r.line.note,
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
    // س102: فاتورة قيد الترحيل تُستثنى من حجزها القديم — الاعتماد يحرر
    // حجز المعلّقة إلى الخصم الفعلي فلا تعترضها مطالبتها السابقة.
    final errors = await _collectInvoiceErrors(draft, forPosting: true,
        excludeReservationOfInvoiceId: invoiceId);
    if (errors.isNotEmpty) {
      throw InvoiceValidationException(errors);
    }
    final totals = computeInvoiceTotals(draft);
    final now = DateTime.now().millisecondsSinceEpoch;
    final year = yearOfIsoDate(draft.dateText);

    final invoiceNumber = formatDocumentNumber(year,
        await _advanceSequenceWithinTx(invoiceSequenceKind(draft.kind), year),
        counterWidth: await _counterWidth());

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
    // س110 (D-190): خريطة تكاليف الخدمات المفككة لأسطر التجميعي —
    // تُقيد في فرع البيع أدناه 51 مديناً ضمن السطر المركب و211 دائناً.
    final serviceCostsByLine = <int, int>{};
    // س111: خريطة عكس تكلفة الخدمات المفككة بمردود التجميعي.
    final serviceRestoreByLine = <int, int>{};
    final plan = await _planStockLines(draft, totals.lines, planErrors,
        excludeReservationOfInvoiceId: invoiceId,
        serviceCostsByLine: serviceCostsByLine,
        serviceRestoreByLine: serviceRestoreByLine);
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
    // — وعلم «جاهز/فُكِّك» يحملته خطط التجميعي (F-034/الدفعة 28).
    final stockMoveIds = <int>[];
    final stockIn =
        draft.kind == InvoiceKind.purchase || draft.kind == InvoiceKind.saleReturn;
    for (final p in plan) {
      await customStatement(
        "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
        "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
        "ref_doc_type, ref_doc_id, move_detail, uuid, created_at, "
        "updated_at, is_deleted) "
        "VALUES (?, ?, ?, ?, ?, ?, 'posted', 'invoice', ?, ?, ?, ?, ?, 0)",
        [
          p.itemId,
          stockIn ? p.qtyBase : -p.qtyBase,
          stockIn ? null : draft.warehouseId,
          stockIn ? draft.warehouseId : null,
          p.stockValueMinor,
          roundHalfAwayFromZeroRatio(p.stockValueMinor, p.qtyBase),
          invoiceId,
          p.detail,
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
      // سطر التكلفة الواحد لكل سطر فاتورة (F-034: «سطر تكلفة واحد
      // بالمبلغ المركب»): البضاعة العادية خطة واحدة فلا تغيير، وسطر
      // التجميعي خططُه (الجاهز + مكونات الفكك) تُجمع في سطر 51 واحد —
      // و113 دائناً بحركة كل خطة مربوطة بها فمجموعها المركب حرفاً.
      final planByLine = <int, List<int>>{};
      for (var k = 0; k < plan.length; k++) {
        planByLine.putIfAbsent(plan[k].lineIndex, () => []).add(k);
      }
      // س110 (D-190): اتحاد أسطر التكلفة — خطط المخزون وأسطر الخدمات
      // المفككة (وصفة خدمات فقط لا خطة مخزنية لها — D-190 شاملها).
      final costLineIndexes = <int>{...planByLine.keys, ...serviceCostsByLine.keys};
      for (final li in costLineIndexes) {
        final ks = planByLine[li] ?? const <int>[];
        final lineInventory = ks.fold(0, (s, k) => s + plan[k].stockValueMinor);
        final lineService = serviceCostsByLine[li] ?? 0;
        // سطر التكلفة الواحد لكل سطر فاتورة (F-034: «سطر تكلفة واحد
        // بالمبلغ المركب») — والمركب صار حرفياً بالقيد (س110): الخروج
        // المخزني + تكلفة الخدمات المفككة (D-190) — و113 دائناً بحركة
        // كل خطة مربوطة بها فمجموعها المخزني حرفاً.
        final lineCost = lineInventory + lineService;
        if (lineCost > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc51,
            debitMinor: lineCost,
            currencyId: 1,
            amountMinor: lineCost,
          ));
        }
        for (final k in ks) {
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
        // D-190 (س110): نظير التكلفة الخدمية — 211 دائناً بلا طرف
        // (دائن الخدمة الخارجية — بذر الدليل 211 ولا طرف على الرجل)
        // والفراغ بند بيعي ضمن السعر فلا رجل له.
        if (lineService > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc211,
            creditMinor: lineService,
            currencyId: 1,
            amountMinor: lineService,
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
      // س111: عكس تكلفة الخدمات المفككة عن مردود التجميعي — 211 مديناً
      // (إنقاص دائن الخدمة الخارجية) و51 دائناً (إنقاص المصروف) —
      // من رجل الأصل 211 حصراً فلا إعادة حساب ولا فجوة.
      for (final rev in serviceRestoreByLine.values) {
        if (rev > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc211,
            debitMinor: rev,
            currencyId: 1,
            amountMinor: rev,
          ));
          moveLines.add(MoveLineDraft(
            accountId: acc51,
            creditMinor: rev,
            currencyId: 1,
            amountMinor: rev,
          ));
        }
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
        payload: await sealLogText(snapshot),
        uuid: const Uuid().v4(),
      ),
    );
  });
}

// ─── قراءات الفواتير العامة — التخزين يقرأ ولا يحسب (نمط القلب) ───

Future<InvoiceDocument?> invoiceById(int id) => _invoiceRowTx(id);


Future<List<InvoiceLineDocument>> invoiceLines(int invoiceId) =>
    _invoiceLinesTx(invoiceId);

// ─── س101: تقديم الفاتورة للاعتماد — حدث تدقيق بهوية المانِح ───
// بوابة «المندوب يعلق» (كلمة المالك): المسودة المحفوظة بدور معلّق
// تُسجَّل لها وقائعُ تقديمٍ بسجل الأحداث (الجدول المصير الكامل append-only
// 07 §2.3) بهوية من قدّمها ومتى — لا عمود جديد ولا مخطط؛ والمطالعة من
// الحدث الأخير حصراً فالتقديمات المتعاقبة (إعادة حفظ لاحقة) بالأحدث فوزاً.
// وصورة التقديم (InvoiceSubmissionInfo) بدفتر الصفوف آخر الملف عرفها.

/// تسجيل تقديم مسودة فاتورة للاعتماد بهوية المانِح — المسودة حصراً
/// (المرحّلة لا تُقدَّم)، والفاتورة الغائبة برسالته. الحدث تدقيقٌ لا
/// شرط ترحيل: المحرك (postInvoice) يتحقق بحالته لا بحدثه.
Future<void> recordInvoiceSubmission(
  int invoiceId, {
  required int userId,
  required String userName,
  required String roleName,
}) async {
  return transaction(() async {
    final inv = await _invoiceRowTx(invoiceId);
    if (inv == null) {
      throw StateError('لا فاتورة بالمعرف $invoiceId');
    }
    if (inv.state != 'draft') {
      throw InvoiceValidationException([InvoiceStateNotDraft(inv.state)]);
    }
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: DateTime.now().millisecondsSinceEpoch,
        deviceId: await deviceId(),
        entityType: 'invoice',
        entityId: Value(invoiceId),
        userId: Value(userId),
        action: 'submitted_for_approval',
        payload: await sealLogText(jsonEncode(<String, Object?>{
          'by_user_id': userId,
          'by_user_name': userName,
          'by_role_name': roleName,
        })),
        uuid: const Uuid().v4(),
      ),
    );
  });
}

/// آخر تقديم معلق لفاتورة — من أحداثها بالأحدث فوزاً، والغائب null
/// (مسودة قديمة سبقت الدفعة أو مسودة صاحب صلاحية لا يعلّق).
Future<InvoiceSubmissionInfo?> invoiceSubmissionOf(int invoiceId) async {
  final rows = await customSelect(
    "SELECT user_id, payload, event_at FROM events "
    "WHERE entity_type = 'invoice' AND entity_id = ? "
    "AND action = 'submitted_for_approval' "
    'ORDER BY event_at DESC, id DESC LIMIT 1',
    variables: [Variable.withInt(invoiceId)],
  ).get();
  if (rows.isEmpty) return null;
  final r = rows.single;
  final payload =
      jsonDecode(await openLogText(r.data['payload'] as String))
          as Map<String, dynamic>;
  return InvoiceSubmissionInfo(
    invoiceId: invoiceId,
    userId: (payload['by_user_id'] as num).toInt(),
    userName: (payload['by_user_name'] as String?) ?? '',
    roleName: (payload['by_role_name'] as String?) ?? '',
    submittedAtMs: r.data['event_at'] as int,
  );
}

/// ── س102 ثم س164: خريطة الحجز — كميات مسودات البيع المحجوزة لكل صنف ──
/// مجموع كميات أسطر بيع المسودات الحيّة بلا الخدمات (لا مخزون لها —
/// س-08) وبلا المحذوف من الفواتير والأسطر. بنقاط المالك س164 صار
/// الحجز بتابع المسودة لا «التعليق»: التعليق ألغى وكل مسودة بيع
/// تحجز بالإعداد المعتمد من كانت المعلقات وحدها — فالشرط حدثُ التقديم
/// (submitted_for_approval) أُسقط من القراءة والهوية بهوية المنشئ
/// باقية للتدقيق والفصل (invoiceSubmissionOf) لا للحجز. قراءة خالصة
/// تُحسب لحظة النداء لا حالة مخزنة: الترحيل يُخرجها (حالتها لم تعد
/// draft) والحذف يُخرجها (is_deleted) فلا حجز يتيم يُنسى — ولا عمود
/// جديد ولا مخطط.
///
/// و[excludeInvoiceId] يستثني فاتورة قيد الترحيل حتى لا يحجزها حجزُها
/// القديم ضدّ ترحيلها — حجزها لحظة الترحيل يتحرك خصماً فعلياً
/// بالمحرك (postInvoice) لا حساباً معلقاً.
Future<Map<int, int>> heldSaleReservationsByItem({
  required int warehouseId,
  int? excludeInvoiceId,
}) async {
  final rows = await customSelect(
    'SELECT il.item_id AS item_id, SUM(il.qty_base) AS qty '
    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'JOIN items it ON it.id = il.item_id '
    "WHERE inv.kind = 'sale' AND inv.state = 'draft' "
    'AND inv.is_deleted = 0 AND il.is_deleted = 0 '
    'AND inv.warehouse_id = ?1 '
    "AND it.kind <> 'service' "
    'AND (?2 IS NULL OR inv.id <> ?2) '
    'GROUP BY il.item_id',
    variables: [
      Variable.withInt(warehouseId),
      Variable(excludeInvoiceId),
    ],
  ).get();
  return {
    for (final r in rows)
      r.data['item_id'] as int: r.data['qty'] as int? ?? 0,
  };
}

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

/// س-153/D-151 (دفعة 15): خانة «ملاحظة التسليم» القصيرة على السطر —
/// تُحرَّر من شاشة «متابعة التسليم» على السطر غير المستلم (س-139)
/// وتظهر في شاشة المتابعة والمطبوع بلفظ بوابة دفعة (12) §3. علم عمل
/// لا محاسبة نمط D-131: الحرس يجمّد المال والبنية حصراً فالملاحظة
/// تُحدّث على المرحّلة بلا فك إقفال — والسطر الغائب برسالته،
/// والفراغ (نص فارغ أو null) يمحو الملاحظة ولا يخزّن فارغاً.
Future<void> setInvoiceLineDeliveryNote(
  int lineId, {
  required String? note,
}) async {
  final existing = await customSelect(
    'SELECT id FROM invoice_lines WHERE id = ?',
    variables: [Variable.withInt(lineId)],
  ).get();
  if (existing.isEmpty) {
    throw StateError('لا سطر فاتورة بالمعرف $lineId');
  }
  final trimmed = note?.trim();
  await customStatement(
    'UPDATE invoice_lines SET delivery_note = ?, updated_at = ? WHERE id = ?',
    [
      (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      DateTime.now().millisecondsSinceEpoch,
      lineId,
    ],
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
    'il.supplier_party_id AS supplier_party_id, sp.name AS supplier_name, '
    // س-148/D-138: اسم وحدة السطر لتجميع الكميات «بالواحدة».
    // س-153/D-151: خانة «ملاحظة التسليم» مع صف المتابعة.
    'u.name AS unit_name, il.delivery_note AS delivery_note '
    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'LEFT JOIN items i ON i.id = il.item_id '
    'JOIN units u ON u.id = il.unit_id '
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
        unitName: r.data['unit_name'] as String,
        deliveryNote: r.data['delivery_note'] as String?,
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

// ═══ الدفعة 24 (أولى م2) — تعدد المستودعات والتحويل بينها ═══
// المحرك بنمط دفعة السندات: المدقق البنيوي بالمجال والفحوص المحركية
// هنا على ما خُزّن لا على ما قيل، والحاجز الثاني مُشغِّلات القاعدة
// (التجميد أعلاه)، والترحيل معاملة واحدة أي رفض يتراجع كله بما فيه
// العدّاد (07 §1.9/§2.4).

/// إنشاء مستودع جديد (س-18 مركز الرفض: الاسم فريد بغير فارغ — نمط
/// الصناديق). بلا حساب ورقي: المخزون حساب 113 موحداً على الشركة.
Future<int> warehouseCreate({required String name}) async {
  final err = warehouseNameError(name);
  if (err != null) throw StateError(err);
  final trimmed = name.trim();
  final dup = await customSelect(
    'SELECT id FROM warehouses WHERE name = ? AND is_deleted = 0',
    variables: [Variable.withString(trimmed)],
  ).get();
  if (dup.isNotEmpty) {
    throw StateError('اسم المستودع «$trimmed» مستخدم سلفاً — '
        'وأسماء المستودعات فريدة');
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  await customStatement(
    'INSERT INTO warehouses (name, is_active, uuid, created_at, '
    'updated_at, is_deleted) VALUES (?, 1, ?, ?, ?, 0)',
    [trimmed, const Uuid().v4(), now, now],
  );
  return (await customSelect('SELECT last_insert_rowid() AS id')
          .getSingle())
      .data['id'] as int;
}

/// إعادة تسمية مستودع قائم — الاسم الذاتي يمر (الاستثناء الذاتي نمط
/// D-153) والغير مكرر يقبل فلا يُحبس تعديل مستودع قديم باسمه نفسه.
Future<void> warehouseRename({
  required int id,
  required String name,
}) async {
  final err = warehouseNameError(name);
  if (err != null) throw StateError(err);
  final trimmed = name.trim();
  final row = await _warehouseByIdTx(id);
  if (row == null) throw StateError('لا مستودع بالمعرف $id');
  final dup = await customSelect(
    'SELECT id FROM warehouses WHERE name = ? AND is_deleted = 0 '
    'AND id <> ?',
    variables: [Variable.withString(trimmed), Variable.withInt(id)],
  ).get();
  if (dup.isNotEmpty) {
    throw StateError('اسم المستودع «$trimmed» مستخدم سلفاً — '
        'وأسماء المستودعات فريدة');
  }
  await customStatement(
    'UPDATE warehouses SET name = ?, updated_at = ? WHERE id = ?',
    [trimmed, DateTime.now().millisecondsSinceEpoch, id],
  );
}

/// تعطيل/تفعيل مستودع — بلا حذف أبداً (المرجع المحاسبي المرتبط
/// بحركات لا يُحذف). الحراسة على التعطيل حصراً بنمط الصناديق
/// (03 §6-3): لا يُعطَّل آخر مستودع نشط (يبقى باب الإدخال مغلقاً
/// وإلا رحلت كل فاتورة بلا مستودع) ولا مستودع برصيد قائم — يُفرَّغ
/// أولاً بالتحويل أو تسوية الجرد. الأرصدة باقية مهما فعلت.
Future<void> warehouseSetActive({
  required int id,
  required bool active,
}) async {
  final row = await _warehouseByIdTx(id);
  if (row == null) throw StateError('لا مستودع بالمعرف $id');
  if (!active && row.isActive) {
    final activeCount = (await customSelect(
      'SELECT COUNT(*) AS c FROM warehouses '
      'WHERE is_active = 1 AND is_deleted = 0',
    ).getSingle()).data['c'] as int;
    if (activeCount <= 1) {
      throw StateError('المستودع «${row.name}» آخر مستودع نشط — '
          'لا يُعطَّل حتى يُنشأ مستودع آخر');
    }
    final bal = await customSelect(
      'SELECT qty_base FROM stock_balances '
      'WHERE warehouse_id = ? AND (qty_base <> 0 OR total_value_minor <> 0) '
      'LIMIT 1',
      variables: [Variable.withInt(id)],
    ).get();
    if (bal.isNotEmpty) {
      throw StateError('المستودع «${row.name}» برصيد قائم — تعطيله غير '
          'آمن (نمط 03 §6-3): يُفرَّغ أولاً بالتحويل أو تسوية الجرد');
    }
  }
  await customStatement(
    'UPDATE warehouses SET is_active = ?, updated_at = ? WHERE id = ?',
    [active ? 1 : 0, DateTime.now().millisecondsSinceEpoch, id],
  );
}

/// التحويل بين مستودعين (س-18/F-045): مستند يُنشأ مرحّلاً بلا مسودة،
/// وحركتا مخزون متقابلتان بلا قيد محاسبي (05 §6)، والقيمة تنتقل كما
/// هي بالمتوسط الجاري المتسلسل للمصدر (D-067) فلا فروق تكلفة ولا
/// غبار تقريب (الخروج بكل الكمية يمتص القيمة كلها)، ورقم من التسلسل
/// السنوي داخل المعاملة ذاتها (07 §1.9)، وحدث «posted» بلقطة الصف
/// الكاملة في المعاملة نفسها (07 §2.3). لا فحص فترة: لا قيد بذاك
/// التاريخ أصلاً وأرصدته حالية دائماً لا تاريخية.
Future<int> stockTransferPost(StockTransferDraft draft) async {
  final structural =
      validateStockTransferStructure(draft);
  if (structural.isNotEmpty) {
    throw StockTransferValidationException(structural);
  }
  return transaction(() async {
    final errors = await _collectStockTransferErrors(draft);
    if (errors.isNotEmpty) {
      throw StockTransferValidationException(errors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final year = yearOfIsoDate(draft.dateText);
    final number = formatDocumentNumber(year,
        await _advanceSequenceWithinTx('stock_transfer', year),
        counterWidth: await _counterWidth());
    await customStatement(
      "INSERT INTO stock_transfers (number, transfer_date, "
      "from_warehouse_id, to_warehouse_id, narration, state, uuid, "
      "created_at, updated_at, is_deleted) "
      "VALUES (?, ?, ?, ?, ?, 'posted', ?, ?, ?, 0)",
      [
        number,
        draft.dateText,
        draft.fromWarehouseId,
        draft.toWarehouseId,
        draft.narration,
        const Uuid().v4(),
        now,
        now,
      ],
    );
    final transferId = (await customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle()).data['id'] as int;
    for (final line in draft.lines) {
      final (qty, value) =
          await _stockBalanceTx(line.itemId, draft.fromWarehouseId);
      final exitValue = wacExitValue(value, qty, line.qtyBase);
      final unitCost = roundHalfAwayFromZeroRatio(exitValue, line.qtyBase);
      await customStatement(
        'INSERT INTO stock_transfer_lines (transfer_id, item_id, '
        'qty_base, unit_level_id, qty_doc, factor_at_entry, '
        'unit_cost_base_minor, value_base_minor, uuid, '
        'created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          transferId,
          line.itemId,
          line.qtyBase,
          line.unitLevelId,
          line.qtyDoc,
          line.factorAtEntry,
          unitCost,
          exitValue,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      // حركتا المخزون المتقابلتان — الخروج سالب الإشارة بنمط الفواتير
      // (05 §117: qty_base موجب/سالب بالاتفاقية) والمرجعية «stock_transfer».
      for (final entry in [
        (-line.qtyBase, draft.fromWarehouseId, null),
        (line.qtyBase, null, draft.toWarehouseId),
      ]) {
        await customStatement(
          'INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, '
          'to_warehouse_id, value_base_minor, unit_cost_base_minor, '
          "state, ref_doc_type, ref_doc_id, uuid, created_at, "
          "updated_at, is_deleted) "
          "VALUES (?, ?, ?, ?, ?, ?, 'posted', 'stock_transfer', "
          '?, ?, ?, ?, 0)',
          [
            line.itemId,
            entry.$1,
            entry.$2,
            entry.$3,
            exitValue,
            unitCost,
            transferId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
      }
      // دلتا أرصدة الطرفين — upsert بالنمط القائم (05 §117) والحاجز
      // يحرس السالب (F-042)؛ القيمة تنتقل كما هي فمجموع 113 ثابت.
      for (final delta in [
        (draft.fromWarehouseId, -line.qtyBase, -exitValue),
        (draft.toWarehouseId, line.qtyBase, exitValue),
      ]) {
        await customStatement(
          'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
          'total_value_minor, uuid, created_at, updated_at, is_deleted) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
          'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
          'qty_base = qty_base + excluded.qty_base, '
          'total_value_minor = total_value_minor + excluded.total_value_minor, '
          'updated_at = excluded.updated_at',
          [
            line.itemId,
            delta.$1,
            delta.$2,
            delta.$3,
            const Uuid().v4(),
            now,
            now,
          ],
        );
      }
    }
    await _recordDocEventTx(
      entityType: 'stock_transfer',
      table: 'stock_transfers',
      entityId: transferId,
      action: 'posted',
    );
    return transferId;
  });
}

/// فحوص التحويل بقاعدة البيانات — س-18: المستودعان موجودان نشطان،
/// والأصناف موجودة نشطة بضاعة (الخدمة بلا مخزون — س-08)، ورصيد
/// المصدر يكفي (منع السالب — F-042).
Future<List<StockTransferValidationError>> _collectStockTransferErrors(
    StockTransferDraft draft) async {
  final errors = <StockTransferValidationError>[];
  final from = await _warehouseByIdTx(draft.fromWarehouseId);
  if (from == null) {
    errors.add(StockTransferWarehouseMissing(draft.fromWarehouseId));
  } else if (!from.isActive) {
    errors.add(StockTransferWarehouseInactive(from.name));
  }
  final to = await _warehouseByIdTx(draft.toWarehouseId);
  if (to == null) {
    errors.add(StockTransferWarehouseMissing(draft.toWarehouseId));
  } else if (!to.isActive) {
    errors.add(StockTransferWarehouseInactive(to.name));
  }
  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    final item = await _itemByIdTx(line.itemId);
    if (item == null) {
      errors.add(StockTransferItemMissing(line.itemId, i));
      continue;
    }
    final label =
        itemDisplayLabel(item['name'] as String, item['sku'] as String);
    if ((item['is_active'] as int) != 1) {
      errors.add(StockTransferItemInactive(label, i));
      continue;
    }
    if ((item['kind'] as String) != 'good') {
      errors.add(StockTransferItemNotGood(label, i));
      continue;
    }
    // س113: حرس مستوى التعبئة (نمط الفواتير س89) — المستوى من مجموعة
    // الصنف حصراً وعاملُه يطابق الكمية المدخلة، والمخالف مرفوض بلا
    // كتابة (الرفض قبل الترحيل حصراً — نمط س-18).
    if (line.unitLevelId != null) {
      final groupId = item['unit_group_id'] as int?;
      var levelValid = false;
      var levelFactor = 0;
      if (groupId != null) {
        final levelRows = await customSelect(
          'SELECT group_id, factor FROM unit_group_levels '
          'WHERE id = ? AND is_deleted = 0',
          variables: [Variable.withInt(line.unitLevelId!)],
        ).get();
        if (levelRows.isNotEmpty &&
            levelRows.first.data['group_id'] as int == groupId) {
          levelFactor = levelRows.first.data['factor'] as int;
          levelValid = levelFactor >= 2;
        }
      }
      final qtyDoc = line.qtyDoc ?? 0;
      final factor = line.factorAtEntry ?? 0;
      if (!levelValid ||
          qtyDoc <= 0 ||
          factor != levelFactor ||
          line.qtyBase != qtyDoc * factor) {
        errors.add(StockTransferLevelInvalid(i, label));
      }
    }
    final (qty, _) =
        await _stockBalanceTx(line.itemId, draft.fromWarehouseId);
    if (line.qtyBase > qty) {
      errors.add(StockTransferStockInsufficient(
        itemLabel: label,
        onHandQty: qty,
        requestedQty: line.qtyBase,
        lineIndex: i,
      ));
    }
  }
  return errors;
}

/// سجل التحويلات — الرؤوس بأسماء المستودعين وعدد الأسطر ومجاميعها
/// (قراءة عرض خالصة — التخزين يقرأ لا يحسب).
Future<List<StockTransferListRow>> stockTransfersOf() async {
  final rows = await customSelect(
    'SELECT t.id, t.number, t.transfer_date, t.state, t.narration, '
    't.from_warehouse_id, t.to_warehouse_id, '
    'wf.name AS from_name, wt.name AS to_name, '
    'COUNT(l.id) AS line_count, '
    'COALESCE(SUM(l.qty_base), 0) AS total_qty, '
    'COALESCE(SUM(l.value_base_minor), 0) AS total_value '
    'FROM stock_transfers t '
    'LEFT JOIN warehouses wf ON wf.id = t.from_warehouse_id '
    'LEFT JOIN warehouses wt ON wt.id = t.to_warehouse_id '
    'LEFT JOIN stock_transfer_lines l '
    'ON l.transfer_id = t.id AND l.is_deleted = 0 '
    'WHERE t.is_deleted = 0 '
    'GROUP BY t.id ORDER BY t.id DESC',
  ).get();
  return [
    for (final r in rows)
      StockTransferListRow(
        id: r.data['id'] as int,
        number: r.data['number'] as String,
        transferDate: r.data['transfer_date'] as String,
        state: r.data['state'] as String,
        narration: r.data['narration'] as String?,
        fromWarehouseId: r.data['from_warehouse_id'] as int,
        toWarehouseId: r.data['to_warehouse_id'] as int,
        fromName: r.data['from_name'] as String?,
        toName: r.data['to_name'] as String?,
        lineCount: r.data['line_count'] as int,
        totalQtyBase: r.data['total_qty'] as int,
        totalValueMinor: r.data['total_value'] as int,
      ),
  ];
}

/// أسطر تحويل قائم — للعرض التفصيلي (اللقطة المخزنة لا حساب جديد).
Future<List<StockTransferLineRow>> stockTransferLinesOf(
    int transferId) async {
  final rows = await customSelect(
    'SELECT l.item_id, i.name AS item_name, i.sku, l.qty_base, '
    'l.unit_cost_base_minor, l.value_base_minor '
    'FROM stock_transfer_lines l '
    'LEFT JOIN items i ON i.id = l.item_id '
    'WHERE l.transfer_id = ? AND l.is_deleted = 0 ORDER BY l.id',
    variables: [Variable.withInt(transferId)],
  ).get();
  return [
    for (final r in rows)
      StockTransferLineRow(
        itemId: r.data['item_id'] as int,
        itemName: r.data['item_name'] as String?,
        sku: r.data['sku'] as String?,
        qtyBase: r.data['qty_base'] as int,
        unitCostBaseMinor: r.data['unit_cost_base_minor'] as int,
        valueBaseMinor: r.data['value_base_minor'] as int,
      ),
  ];
}

/// جداول الدفعة 25 — الجرد وتسوياته (س-19/F-046 ثاني م2):
/// جلسة عدّ بحالتين «جارٍ/مرحّل» تُنشأ مفتوحةً تُحفظ عدّاتها متكرراً ثم
/// تُرحَّل بترحيلة واحدة — لا مسودة قيدية: الجلسة وثيقة عدّ والمحاسبة
/// لحظة الترحيل حصراً. الرأس بنطاقه (كل الأصناف أو مجموعة تصنيف) وأسطره
/// مزروعة آلياً من أرصدة المستودع داخل النطاق، والفرق والقيمة لقطة
/// الترحيل (المحسوبة ضد الأرصدة الآنية لا لقطة عدّ قديم) لا مكتوبة
/// أثناء العدّ. المُشغِّلات: تجميد المرحّل نمط F-140 (الجلسة المرحّلة
/// وأسطرها لقطة تاريخية لا تعدل ولا تحذف)، وحاجز الفترة المقفلة من
/// _createClosingTriggers (الجلسة تُرحّل قيداً محاسبياً فالتاريخ تحكمه
/// الفترة خلافاً للتحويل بلا قيد).
Future<void> _createCountTables() async {
  const statements = <String>[
    'CREATE TABLE IF NOT EXISTS "stock_counts" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"count_date" TEXT NOT NULL, '
        '"warehouse_id" INTEGER NOT NULL, '
        '"scope" TEXT NOT NULL, '
        '"scope_category" TEXT NULL, '
        '"narration" TEXT NULL, '
        '"state" TEXT NOT NULL DEFAULT \'open\', '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "stock_count_lines" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"count_id" INTEGER NOT NULL, '
        '"item_id" INTEGER NOT NULL, '
        // العدّة null = لم يُعدّ بعد — والصفر عدّ شرعي «الرف فارغ».
        '"counted_qty_base" INTEGER NULL, '
        // س115: لقطة العدّ بالتعبئة (نمط v25/v21) — والغائب عدّ بالأساسية.
        '"unit_level_id" INTEGER NULL, '
        '"qty_doc" INTEGER NULL, '
        '"factor_at_entry" INTEGER NULL, '
        // لقطة الترحيل: رصيد النظام الآني والفرق واتجاهه وقيمته وتكلفتها.
        '"system_qty_base" INTEGER NULL, '
        '"diff_qty_base" INTEGER NULL, '
        '"direction" TEXT NULL, '
        '"value_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"unit_cost_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    // الصنف الواحد سطراً واحداً بالجلسة (نمط D-183) — حاجز قاعدة فوق المجال
    'CREATE UNIQUE INDEX IF NOT EXISTS ux_stock_count_lines_session_item '
        'ON stock_count_lines (count_id, item_id)',
    // الحاجز — تجميد الجلسة المرحّلة (نمط trg_stock_transfers_frozen/F-140)
    // س107: إعادة تعريف موثقة — DROP قبل CREATE لتحديث الرموز DQ.
    'DROP TRIGGER IF EXISTS trg_stock_counts_frozen_update',
    'DROP TRIGGER IF EXISTS trg_stock_counts_frozen_delete',
    'DROP TRIGGER IF EXISTS trg_stock_count_lines_frozen_update',
    'DROP TRIGGER IF EXISTS trg_stock_count_lines_frozen_delete',
    'CREATE TRIGGER trg_stock_counts_frozen_update '
        'BEFORE UPDATE ON stock_counts FOR EACH ROW '
        "WHEN OLD.state = 'posted' "
        'BEGIN '
        "SELECT RAISE(ABORT, 'جلسة الجرد المرحّلة لقطة تاريخية — لا تعديل "
        "(DQ-0405)'); "
        'END',
    'CREATE TRIGGER trg_stock_counts_frozen_delete '
        'BEFORE DELETE ON stock_counts FOR EACH ROW '
        "WHEN OLD.state = 'posted' "
        'BEGIN '
        "SELECT RAISE(ABORT, 'جلسة الجرد المرحّلة لا تحذف — لقطة تاريخية "
        'وتسويتها بمردود لا بحذف (DQ-0406)\'); '
        'END',
    // أسطر الجلسة تتجمد لحظة ترحيل رأسها — والجارٍ حر العدّ المتكرر
    'CREATE TRIGGER trg_stock_count_lines_frozen_update '
        'BEFORE UPDATE ON stock_count_lines FOR EACH ROW '
        "WHEN (SELECT state FROM stock_counts WHERE id = NEW.count_id) = "
        "'posted' "
        'BEGIN '
        "SELECT RAISE(ABORT, 'سطر جلسة مرحّلة لقطة تاريخية — لا تعديل (DQ-0407)'); "
        'END',
    'CREATE TRIGGER trg_stock_count_lines_frozen_delete '
        'BEFORE DELETE ON stock_count_lines FOR EACH ROW '
        "WHEN (SELECT state FROM stock_counts WHERE id = OLD.count_id) = "
        "'posted' "
        'BEGIN '
        "SELECT RAISE(ABORT, 'سطر جلسة مرحّلة لا يحذف — لقطة تاريخية (DQ-0408)'); "
        'END',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

/// جدول الدفعة 34 — أسعار الصرف التاريخية (F-121، D-194): سجل واحد
/// لكل (العملة، اليوم) بالتفرّد داخل DDL الجدول ذاته (درس س86:
/// القيد يولد مع جدوله مرة واحدة آمناً أي مسار وصول)، ومُشغّلات
/// تجميد نمط F-140 — «لا تعديل لسعر محفوظ أبداً» — بلا حاجز فترة
/// (الأسعار مرجع عملة لا مستند قيدي، ولا بذر بخطوة v9 إلزاماً —
/// درس v16 لا يُستدعى إلا لحاجزٍ جديد). والسعر عدد صحيح مكبَّر
/// باصطلاح fxRateScale الموحد (invoice.dart).
Future<void> _createExchangeRateTables() async {
  const statements = <String>[
    // س107: إعادة تعريف موثقة — DROP قبل CREATE لتحديث الرموز DQ.
    'DROP TRIGGER IF EXISTS trg_exchange_rate_frozen_update',
    'DROP TRIGGER IF EXISTS trg_exchange_rate_frozen_delete',
    'CREATE TABLE IF NOT EXISTS "exchange_rate" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"currency_id" INTEGER NOT NULL, '
        '"date" TEXT NOT NULL, '
        '"rate_to_base" INTEGER NOT NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0, '
        'UNIQUE("currency_id", "date"))',
    'CREATE TRIGGER trg_exchange_rate_frozen_update '
        'BEFORE UPDATE ON exchange_rate FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'سعر الصرف المحفوظ لا يُعدل أبداً (DQ-0509)'); "
        'END',
    'CREATE TRIGGER trg_exchange_rate_frozen_delete '
        'BEFORE DELETE ON exchange_rate FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'سعر الصرف المحفوظ لا يُحذف أبداً (DQ-0510)'); "
        'END',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

/// س107 (أساس الأخطاء — قرار المالك الخامس): جدول سجل الأخطاء —
/// مرساة شاشة التشخيص. جدول نظام تشخيصي لا سجل أعمال: معفى من
/// اصطلاح «كل جدول» بعرف app_meta الموثق (D-055) — لا مزامنة ولا
/// حذف منطقي ولا uuid؛ append-only بحت (لا تعديل ولا حذف — عرف
/// الأحداث المصيرة 07 §2.3) والرمز DQ-xxxx هو عقد التفسير (سلطة
/// الترقيم بالمجال: error_codes.dart).
/// آمن التكرار بـIF NOT EXISTS بنمط v15..v23، وبلا حاجز فترة:
/// سجل تشخيص لا مستند قيدي — درس v16 لا يُستدعى إلا لحاجزٍ جديد.
Future<void> _createErrorLogTable() async {
  const statements = <String>[
    'CREATE TABLE IF NOT EXISTS "error_log" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"code" TEXT NOT NULL, '
        '"message" TEXT NOT NULL, '
        '"context" TEXT NULL, '
        '"created_at" INTEGER NOT NULL)',
    'CREATE INDEX IF NOT EXISTS ix_error_log_created '
        'ON error_log (created_at DESC)',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

// ═══════════════════════════════════════════════════════════════
// p3 (س146 — خط التشفير المرحلة الثالثة): إحكام سجلي الأحداث والأخطاء
// ═══════════════════════════════════════════════════════════════

/// p3: مفتاح ملح اشتقاق مفتاح سجلات هذه القاعدة — app_meta بعرف
/// مفاتيح النظام المعفى (D-055). قيمة القاعدة تُولد عشوائياً أول
/// مرة فتختلف بين الأجهزة (نسختا قاعدة لا تتطابقا بايتات حتى لو
/// تطابقت أحداثهما)، وهي بيانات نظام لا سر عمومي.
static const String p3LogSaltMetaKey = 'p3_log_salt';

/// p3: مشفر السجلات الوحيد — الجذر والسياق والذاكرة بداخله
/// (منبع واحد لا تكرار، عرف المنبع الموحد الموثق).
///
/// د11 الجزء الثاني (س230/D-225): الجذر بجذر الجهاز من الخزنة —
/// يُحقن من بواني القاعدة ([logRootKey]: الإنتاج يحمله من LogRootVault
/// بخزنة الجهاز عند الافتتاح قبل أي ترحيلة أو كتابة، والاختبارات
/// بجذورها الخاصة)، وغائبه الجذر الإرثي المضمّن انخفاضاً موثقاً
/// (نمط مواد النسخ عينه) — ختماً وقراءةً كالقائم قبل س230، والقراءة
/// الإرثية تبقى بجذرها المضمّن إلى الأبد (LogCipher.open).
final LogCipher _p3LogCipher;

/// p3: ملح هذه القاعدة — يُزرع أول نداء (randomblob بالSQL) ويُقرأ
/// بعده؛ الغائب يُزرع والقائم يُعاد كما هو (آمن التكرار).
Future<String> p3LogSalt() async {
  final existing = await (select(appMeta)
        ..where((t) => t.key.equals(p3LogSaltMetaKey)))
      .get();
  if (existing.isNotEmpty && existing.first.value.isNotEmpty) {
    return existing.first.value;
  }
  await customStatement(
      "INSERT OR IGNORE INTO app_meta (key, value) "
      "VALUES ('$p3LogSaltMetaKey', lower(hex(randomblob(16))))");
  final grown = await (select(appMeta)
        ..where((t) => t.key.equals(p3LogSaltMetaKey)))
      .get();
  return grown.first.value;
}

/// p3: ختم نص سجل (حمولة JSON حدث أو رسالة/سياق خطأ) بالغلاف
/// المعتمد `dq3log1:` — AES-256-GCM لكل سجل بنونس عشوائي فلا نمط
/// يتكرر بين سجلات حكما متشابهة. يُستدعى قبل كل كتابة بالسجلين.
Future<String> sealLogText(String text) async {
  return _p3LogCipher.seal(text, await p3LogSalt());
}

/// p3: فك غلاف نص سجل — النص الخام بلا بادئة يمر كما هو (سجلات ما
/// قبل الإحكام عرف التوافق الرجعي)، والعبث يكسر وسم GCM فترمى
/// LogCipherIntegrityException (DQ-1108) قبل تسليم أي نص.
Future<String> openLogText(String text) async {
  return _p3LogCipher.open(text, await p3LogSalt());
}

/// p3: ختم سجلات ما قبل v28 عند الترقية — الأحداث القائمة حمولاتها
/// JSON صريح وسجل الأخطاء رسائله وسياقه نص صريح، فتُختم كلها هنا
/// قبل إنشاء الحواجز (الترحيلة تستعمل UPDATE بلا مساس ثم يقفل
/// الباب). آمنة التكرار: المختوم بالبادئة يُتخطى بلا تمييز ثانٍ.
Future<void> _sealLegacyLogRows() async {
  final salt = await p3LogSalt();
  final eventRows =
      await customSelect('SELECT id, payload FROM events').get();
  for (final r in eventRows) {
    final payload = r.data['payload'] as String;
    if (payload.startsWith(LogCipher.envelopePrefix)) continue;
    await customStatement(
        'UPDATE events SET payload = ? WHERE id = ?',
        [await _p3LogCipher.seal(payload, salt), r.data['id'] as int]);
  }
  final errorRows = await customSelect(
      'SELECT id, message, context FROM error_log').get();
  for (final r in errorRows) {
    final id = r.data['id'] as int;
    final message = r.data['message'] as String;
    final context = r.data['context'] as String?;
    if (!message.startsWith(LogCipher.envelopePrefix)) {
      await customStatement(
          'UPDATE error_log SET message = ? WHERE id = ?',
          [await _p3LogCipher.seal(message, salt), id]);
    }
    if (context != null && !context.startsWith(LogCipher.envelopePrefix)) {
      await customStatement(
          'UPDATE error_log SET context = ? WHERE id = ?',
          [await _p3LogCipher.seal(context, salt), id]);
    }
  }
}

/// p3/س230 (د11 الجزء الثاني): عبارات سقوط حواجز السجلين — منبع واحد
/// تستهلكه ترحيلات drift (بالأصناف أدناه) ومسار إعادة ختم السجلات
/// الخام بالنسخ الاحتياطية (sqlite3 خام بapplyRestore) فلا تفرّق
/// كلمتان عن الحاجز ذاته مهما تعددت الواجهات.
static const List<String> logGuardsDropSql = [
  'DROP TRIGGER IF EXISTS trg_events_no_update',
  'DROP TRIGGER IF EXISTS trg_events_no_delete',
  'DROP TRIGGER IF EXISTS trg_error_log_no_update',
  'DROP TRIGGER IF EXISTS trg_error_log_no_delete',
];

/// p3/س230: عبارات إنشاء حاجزي الإلحاق الرباعي — المنبع الموحد ذاته
/// (الرسائل برموز خريطة الأخطاء DQ-1119..DQ-1122 حرفاً).
static const List<String> logGuardsCreateSql = [
  'CREATE TRIGGER IF NOT EXISTS trg_events_no_update '
      'BEFORE UPDATE ON events BEGIN '
      "SELECT RAISE(ABORT, 'سجل الأحداث إلحاقي — التعديل مرفوض (DQ-1119)'); END",
  'CREATE TRIGGER IF NOT EXISTS trg_events_no_delete '
      'BEFORE DELETE ON events BEGIN '
      "SELECT RAISE(ABORT, 'سجل الأحداث إلحاقي — الحذف مرفوض (DQ-1120)'); END",
  'CREATE TRIGGER IF NOT EXISTS trg_error_log_no_update '
      'BEFORE UPDATE ON error_log BEGIN '
      "SELECT RAISE(ABORT, 'سجل الأخطاء إلحاقي — التعديل مرفوض (DQ-1121)'); END",
  'CREATE TRIGGER IF NOT EXISTS trg_error_log_no_delete '
      'BEFORE DELETE ON error_log BEGIN '
      "SELECT RAISE(ABORT, 'سجل الأخطاء إلحاقي — الحذف مرفوض (DQ-1122)'); END",
];

/// p3: سقوط الحواجز — تستدعيها الترحيلة قبل الختم (الوصول الهجين:
/// حاجزٌ من جلسة سابقة لا يسد ختم القائمة) وبناة الحاجز أولاً
/// (نمط س107: الدروب قبل CREATE فالإعادة تعريف موثقة لا تخمين).
Future<void> _dropLogGuards() async {
  for (final sql in logGuardsDropSql) {
    await customStatement(sql);
  }
}

/// p3: حاجزا الإلحاق الرباعي — BEFORE UPDATE/DELETE على السجلين
/// يرفضان بأمر صريح: سجل الأحداث append-only بعقده الموثق (D-067:
/// لا يُعدل ولا يُحذف ولا يُعاد بناؤه) وسجل الأخطاء بعرف س107 نفسه.
/// الانضباط كان عادة كود — وبهذا يصير عتاد القاعدة ذاته: أي أداة
/// خارجية أو شيفرة مستقبلية تصطدم بالرفض قبل أن تمس بايتاً. آمنة
/// التكرار أي مسار وصول (createAll أو الترقية أو جلسة سابقة): الدروب
/// أولاً بنمط س107 الموثق (إعادة تعريف موثقة لا تخمين) ثم الإنشاء.
Future<void> _createLogGuards() async {
  await _dropLogGuards();
  for (final sql in logGuardsCreateSql) {
    await customStatement(sql);
  }
}

/// جداول طلبات البيع والشراء (س121 — 07 §3.2/D-026 بأمر المالك
/// «أريد تفعيل طلبات البيع والشراء»): طبقة تشغيلية فوق الفاتورة
/// «دون أي تغيير في القلب المحاسبي» نصاً — فالأمر لا يُقيد ولا يحرك
/// مخزوناً ولا صندوقاً أبداً (ما يُقيد الفاتورة وحدها)، وهو وثيقة
/// التزام تُحوَّل لفاتورة تحمل مرجعها (invoices.order_id). جدولان
/// خالصان بنمط دفعة الفواتير (آمنة التكرار بـIF NOT EXISTS) وباصطلاح
/// «كل جدول» (D-055) وسلسلة «أمر ← تسليم/استلام ← فاتورة» بقرار n.
Future<void> _createOrderTables() async {
  const statements = <String>[
    'CREATE TABLE IF NOT EXISTS "orders" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"direction" TEXT NOT NULL, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"party_id" INTEGER NULL, '
        '"warehouse_id" INTEGER NULL, '
        '"order_date" TEXT NOT NULL, '
        '"expected_date" TEXT NULL, '
        '"currency_id" INTEGER NOT NULL DEFAULT 1, '
        '"state" TEXT NOT NULL DEFAULT \'draft\', '
        '"narration" TEXT NULL, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    // فهرسا القائمة بالأحدث والذمم — والقائمة تُقرأ بالاتجاه والحالة
    'CREATE INDEX IF NOT EXISTS ix_orders_recent '
        'ON orders (is_deleted, direction, state, id DESC)',
    'CREATE INDEX IF NOT EXISTS ix_orders_party ON orders (party_id)',
    'CREATE TABLE IF NOT EXISTS "order_lines" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"order_id" INTEGER NOT NULL, '
        '"item_id" INTEGER NOT NULL, '
        // لقطة الوحدة ثلاثية الأركان بنمط v21 الموحد — الغائب إدخال
        // بالوحدة الأساسية كما اعتاد
        '"unit_id" INTEGER NOT NULL, '
        '"unit_level_id" INTEGER NULL, '
        '"factor_at_entry" INTEGER NOT NULL DEFAULT 1, '
        '"qty" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL, '
        // السعر المرجعي وقت الأمر — تسعير معلوم لا سعر إلزام
        '"unit_price_minor" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE INDEX IF NOT EXISTS ix_order_lines_order '
        'ON order_lines (order_id)',
    'CREATE INDEX IF NOT EXISTS ix_order_lines_item '
        'ON order_lines (item_id)',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

/// المُشغِّلات الحواجز للطلبات — الحاجز الثاني بعد فحص المحرك (07 §2.2):
/// الأسطر تجمّد بلحظة التأكيد (نمط أسطر الفواتير حرفاً)، والرأس
/// المؤكد لا يعدل إلا بتغيير الحالة (فالانتقالات وحدها مسموحة وهي
/// بيد المحرك)، والانتقالات المحروسة بالحرس الصريح، والمؤكد لا يحذف
/// (الإلغاء هو الطريق — DQ-0704).
Future<void> _createOrderTriggers() async {
  const triggers = <String>[
    // س107: إعادة تعريف موثقة (درس v9/v21) — DROP قبل CREATE فتُحدَّث
    // النصوص المرقّمة على أي مسار إنشاء.
    'DROP TRIGGER IF EXISTS trg_order_lines_frozen_insert',
    'DROP TRIGGER IF EXISTS trg_order_lines_frozen_update',
    'DROP TRIGGER IF EXISTS trg_order_lines_frozen_delete',
    'DROP TRIGGER IF EXISTS trg_orders_frozen',
    'DROP TRIGGER IF EXISTS trg_orders_transition_guard',
    'DROP TRIGGER IF EXISTS trg_orders_no_delete',
    "CREATE TRIGGER trg_order_lines_frozen_insert "
        "BEFORE INSERT ON order_lines FOR EACH ROW "
        "WHEN (SELECT state FROM orders WHERE id = NEW.order_id) "
        "<> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الأمر مجمّدة — لا تضاف بعد "
        "التأكيد (DQ-0701)'); END",
    "CREATE TRIGGER trg_order_lines_frozen_update "
        "BEFORE UPDATE ON order_lines FOR EACH ROW "
        "WHEN (SELECT state FROM orders WHERE id = OLD.order_id) "
        "<> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الأمر مجمّدة — لا تعدل بعد "
        "التأكيد (DQ-0701)'); END",
    "CREATE TRIGGER trg_order_lines_frozen_delete "
        "BEFORE DELETE ON order_lines FOR EACH ROW "
        "WHEN (SELECT state FROM orders WHERE id = OLD.order_id) "
        "<> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'أسطر الأمر مجمّدة — لا تحذف بعد "
        "التأكيد (DQ-0701)'); END",
    // الرأس المؤكد مجمّد — أي تحديث لا يغيّر الحالة مرفوض (الانتقالات
    // وحدها تمر وهي بيد المحرك بفحصه المزدوج)
    "CREATE TRIGGER trg_orders_frozen "
        "BEFORE UPDATE ON orders FOR EACH ROW "
        "WHEN OLD.state <> 'draft' AND NEW.state = OLD.state "
        "BEGIN SELECT RAISE(ABORT, 'الأمر المؤكد مجمّد — لا تعديل إلا "
        "بتغيير الحالة (DQ-0702)'); END",
    // الانتقالات المحروسة (07 §1.2): لا رجوع من الطرفين النهائيين
    // ولا قفزة من المسودة للإغلاق مباشرة
    "CREATE TRIGGER trg_orders_transition_guard "
        "BEFORE UPDATE ON orders FOR EACH ROW "
        "WHEN (OLD.state IN ('closed', 'cancelled') AND "
        "NEW.state <> OLD.state) OR (OLD.state = 'draft' AND "
        "NEW.state = 'closed') "
        "BEGIN SELECT RAISE(ABORT, 'انتقال حالة الأمر غير مسموح "
        "(DQ-0703)'); END",
    // المؤكد لا يحذف — الإلغاء هو الطريق (نمط «منع حذف المرحّل»)
    "CREATE TRIGGER trg_orders_no_delete "
        "BEFORE DELETE ON orders FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'الأمر المؤكد لا يحذف — ألغه (DQ-0704)'); "
        "END",
  ];
  for (final sql in triggers) {
    await customStatement(sql);
  }
}

/// جدولا إذني المخزون وأسطرهما (F-209/F-210 — الدفعة 26 س85/D-189):
/// أربعة جداول خالصة بنمط v15/v16 (آمنة التكرار بـIF NOT EXISTS) —
/// الرأس مرحّل فوراً (state 'posted' ثابت — بلا مسودة نمط س-18:
/// الإذن فعل آني والرفض قبل الكتابة حصراً) بسببه النصي الإلزامي
/// وحساب المقابل القابل للتغيير (43/596 افتراضاً — 03 §4) ومُشغّلات
/// تجميد المرحّل نمط F-140 (لقطة تاريخية لا تعدل ولا تحذف — والعكس
/// بمردود لا بحذف). الإذنان سابع وثامن المستندات القيدية (حاجزا
/// الفترة ب_createClosingTriggers).
Future<void> _createMovementDocTables() async {
  // (الجدول، عمود التاريخ، جدول الأسطر) — عرف أسطر المستندات: مفرد
  // الجذع كـ stock_transfer_lines وstock_count_lines (05 §117).
  const docTables = <(String, String, String)>[
    ('stock_receipts', 'receipt_date', 'stock_receipt_lines'),
    ('stock_issues', 'issue_date', 'stock_issue_lines'),
  ];
  final statements = <String>[
    for (final (table, dateColumn, linesTable) in docTables) ...[
      // س107: إعادة تعريف موثقة — DROP قبل CREATE لتحديث الرموز DQ.
      'DROP TRIGGER IF EXISTS trg_${table}_frozen_update',
      'DROP TRIGGER IF EXISTS trg_${table}_frozen_delete',
      'DROP TRIGGER IF EXISTS trg_${linesTable}_frozen_update',
      'DROP TRIGGER IF EXISTS trg_${linesTable}_frozen_delete',
      'CREATE TABLE IF NOT EXISTS "$table" ('
          '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
          '"number" TEXT NOT NULL DEFAULT \'\', '
          '"$dateColumn" TEXT NOT NULL, '
          '"warehouse_id" INTEGER NOT NULL, '
          '"reason" TEXT NOT NULL, '
          '"counter_account_id" INTEGER NOT NULL, '
          '"narration" TEXT NULL, '
          '"state" TEXT NOT NULL DEFAULT \'posted\', '
          '"uuid" TEXT NOT NULL, '
          '"created_at" INTEGER NOT NULL DEFAULT 0, '
          '"updated_at" INTEGER NOT NULL DEFAULT 0, '
          '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
      'CREATE TABLE IF NOT EXISTS "$linesTable" ('
          '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
          '"doc_id" INTEGER NOT NULL, '
          '"item_id" INTEGER NOT NULL, '
          '"qty_base" INTEGER NOT NULL, '
          '"unit_level_id" INTEGER NULL, '
          '"qty_doc" INTEGER NULL, '
          '"factor_at_entry" INTEGER NULL, '
          '"unit_cost_base_minor" INTEGER NOT NULL DEFAULT 0, '
          '"value_base_minor" INTEGER NOT NULL DEFAULT 0, '
          '"uuid" TEXT NOT NULL, '
          '"created_at" INTEGER NOT NULL DEFAULT 0, '
          '"updated_at" INTEGER NOT NULL DEFAULT 0, '
          '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
      // الحاجز — تجميد الرأس المرحّل (نمط F-140؛ الرأس مرحّل دائماً
      // فالحاجز بلا شرط حالة)
      'CREATE TRIGGER IF NOT EXISTS trg_${table}_frozen_update '
          'BEFORE UPDATE ON $table FOR EACH ROW '
          'BEGIN '
          "SELECT RAISE(ABORT, 'إذن المخزون المرحّل لقطة تاريخية — لا تعديل "
          "(DQ-0501)'); "
          'END',
      'CREATE TRIGGER IF NOT EXISTS trg_${table}_frozen_delete '
          'BEFORE DELETE ON $table FOR EACH ROW '
          'BEGIN '
          "SELECT RAISE(ABORT, 'إذن المخزون المرحّل لا يُحذف — لقطة "
          'تاريخية والعكس بمردود لا بحذف (DQ-0502)\'); '
          'END',
      'CREATE TRIGGER IF NOT EXISTS trg_${linesTable}_frozen_update '
          'BEFORE UPDATE ON $linesTable FOR EACH ROW '
          'BEGIN '
          "SELECT RAISE(ABORT, 'سطر إذن المخزون لقطة تاريخية — لا تعديل (DQ-0503)'); "
          'END',
      'CREATE TRIGGER IF NOT EXISTS trg_${linesTable}_frozen_delete '
          'BEFORE DELETE ON $linesTable FOR EACH ROW '
          'BEGIN '
          "SELECT RAISE(ABORT, 'سطر إذن المخزون لا يُحذف — لقطة تاريخية (DQ-0504)'); "
          'END',
    ],
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

/// جداول الدفعة 29 — مستند التجميع (F-211، س88): رأس تجميع مرحّل فوراً
/// (بلا مسودة — نمط س-18: الرفض قبل الكتابة حصراً) بكمية الناتج
/// وقيمتها الإجمالية (مجموع كلف المكونات المسحوبة حصراً — F-211)،
/// وأسطر مكوناته بلقطة الكلفة المخزنية، ومُشغّلات تجميد المرحّل نمط
/// F-140 (لا تعديل ولا حذف — لقطة تاريخية والعكس بمستند عكسي إن حاج
/// المالك إليه مستقبلاً). وبلا حاجز فترة: التجميع بلا قيد محاسبي
/// فأرصدته حالية لا تاريخية — عين قرار التحويل الموثق D-185 (س78).
Future<void> _createAssemblyTables() async {
  const statements = <String>[
    'CREATE TABLE IF NOT EXISTS "assemblies" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"assembly_date" TEXT NOT NULL, '
        '"warehouse_id" INTEGER NOT NULL, '
        '"bundle_item_id" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL, '
        // س115: لقطة الناتج بالتعبئة (نمط v25/v21) — والغائب إدخال
        // بالأساسية، والوصفة بالأساسية نص F-211 ثابت.
        '"unit_level_id" INTEGER NULL, '
        '"qty_doc" INTEGER NULL, '
        '"factor_at_entry" INTEGER NULL, '
        '"total_value_minor" INTEGER NOT NULL DEFAULT 0, '
        '"state" TEXT NOT NULL DEFAULT \'posted\', '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS "assembly_lines" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"assembly_id" INTEGER NOT NULL, '
        '"item_id" INTEGER NOT NULL, '
        '"qty_base" INTEGER NOT NULL, '
        '"unit_cost_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"value_base_minor" INTEGER NOT NULL DEFAULT 0, '
        '"uuid" TEXT NOT NULL, '
        '"created_at" INTEGER NOT NULL DEFAULT 0, '
        '"updated_at" INTEGER NOT NULL DEFAULT 0, '
        '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    // الحاجز — تجميد المرحّل (نمط trg_stock_transfers_frozen/F-140):
    // لا تعديل ولا حذف أبداً — التجميع حدث تاريخي، وعلاج أي خطأ
    // بمستند عكسي لا بالمساس بالتاريخ.
    // س107: إعادة تعريف موثقة — DROP قبل CREATE لتحديث الرموز DQ.
    'DROP TRIGGER IF EXISTS trg_assemblies_frozen_update',
    'DROP TRIGGER IF EXISTS trg_assemblies_frozen_delete',
    'DROP TRIGGER IF EXISTS trg_assembly_lines_frozen_update',
    'DROP TRIGGER IF EXISTS trg_assembly_lines_frozen_delete',
    'CREATE TRIGGER trg_assemblies_frozen_update '
        'BEFORE UPDATE ON assemblies FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'مستند التجميع لقطة تاريخية — لا تعديل "
        "(DQ-0505)'); "
        'END',
    'CREATE TRIGGER trg_assemblies_frozen_delete '
        'BEFORE DELETE ON assemblies FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'مستند التجميع لا يُحذف — لقطة تاريخية "
        'والعلاج بمستند عكسي حصراً (DQ-0506)\'); '
        'END',
    'CREATE TRIGGER trg_assembly_lines_frozen_update '
        'BEFORE UPDATE ON assembly_lines FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'سطر التجميع لقطة تاريخية — لا تعديل (DQ-0507)'); "
        'END',
    'CREATE TRIGGER trg_assembly_lines_frozen_delete '
        'BEFORE DELETE ON assembly_lines FOR EACH ROW '
        'BEGIN '
        "SELECT RAISE(ABORT, 'سطر التجميع لا يُحذف — لقطة تاريخية (DQ-0508)'); "
        'END',
  ];
  for (final sql in statements) {
    await customStatement(sql);
  }
}

/// افتتاح جلسة جرد (س-19): رأس بحالة «جارٍ» وأسطر مزروعة آلياً من
/// أرصدة المستودع داخل النطاق (الصنف النشط بضاعة برصيد كمية قائم
/// سطرٌ إلزامي العدّ؛ الأرصدة الأصفارية بلا عدّ بلا معنى ولا سطر —
/// ما وُجد فعلاً يضاف يدياً «صنف وجدناه»). الرقم من التسلسل السنوي
/// داخل المعاملة ذاتها (07 §1.9) فرفض الافتتاح لا يحرق رقماً،
/// وحدث «created» بلقطة (07 §2.3). ومنع الجلستين المتوازيتين على
/// مستودع واحد (سجل الرسائل: StockCountOpenSessionExists).
Future<int> stockCountStart(StockCountStartDraft draft) async {
  final structural = validateStockCountStartStructure(draft);
  if (structural.isNotEmpty) {
    throw StockCountValidationException(structural);
  }
  return transaction(() async {
    final errors = <StockCountValidationError>[];
    final warehouse = await _warehouseByIdTx(draft.warehouseId);
    if (warehouse == null) {
      errors.add(StockCountWarehouseMissing(draft.warehouseId));
    } else if (!warehouse.isActive) {
      errors.add(StockCountWarehouseInactive(warehouse.name));
    }
    final openSession = await customSelect(
      "SELECT id FROM stock_counts WHERE warehouse_id = ? AND state = "
      "'open' AND is_deleted = 0 LIMIT 1",
      variables: [Variable.withInt(draft.warehouseId)],
    ).get();
    if (openSession.isNotEmpty && warehouse != null) {
      errors.add(StockCountOpenSessionExists(warehouse.name));
    }
    if (errors.isNotEmpty) {
      throw StockCountValidationException(errors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final year = yearOfIsoDate(draft.dateText);
    final number = formatDocumentNumber(
        year,
        await _advanceSequenceWithinTx('stock_count', year),
        counterWidth: await _counterWidth());
    await customStatement(
      "INSERT INTO stock_counts (number, count_date, warehouse_id, scope, "
      "scope_category, narration, state, uuid, created_at, updated_at, "
      "is_deleted) VALUES (?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, 0)",
      [
        number,
        draft.dateText,
        draft.warehouseId,
        draft.scope == StockCountScope.group ? 'group' : 'all',
        draft.scope == StockCountScope.group
            ? draft.scopeCategory!.trim()
            : null,
        draft.narration,
        const Uuid().v4(),
        now,
        now,
      ],
    );
    final sessionId = (await customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle()).data['id'] as int;
    // بذر الأسطر من أرصدة المستودع داخل النطاق — المجموعة بتصنيفها
    // والكل بكل بضاعة نشطة برصيد قائم.
    final categoryFilter =
        draft.scope == StockCountScope.group ? 'AND i.category = ?' : '';
    final vars = <Object>[
      draft.warehouseId,
      if (draft.scope == StockCountScope.group) draft.scopeCategory!.trim(),
    ];
    final seed = await customSelect(
      'SELECT b.item_id AS item_id FROM stock_balances b '
      'JOIN items i ON i.id = b.item_id '
      'WHERE b.warehouse_id = ? AND b.is_deleted = 0 '
      'AND b.qty_base <> 0 AND i.is_deleted = 0 AND i.is_active = 1 '
      "AND i.kind = 'good' $categoryFilter",
      variables: [
        Variable.withInt(vars[0] as int),
        if (vars.length > 1) Variable.withString(vars[1] as String),
      ],
    ).get();
    for (final row in seed) {
      await customStatement(
        'INSERT INTO stock_count_lines (count_id, item_id, counted_qty_base, '
        'uuid, created_at, updated_at, is_deleted) '
        'VALUES (?, ?, NULL, ?, ?, ?, 0)',
        [
          sessionId,
          row.data['item_id'] as int,
          const Uuid().v4(),
          now,
          now,
        ],
      );
    }
    await _recordDocEventTx(
      entityType: 'stock_count',
      table: 'stock_counts',
      entityId: sessionId,
      action: 'created',
    );
    return sessionId;
  });
}

/// حفظ العدّات المتكرر على جلسة جارٍ — العدّة موجبة أو صفر (الصفر
/// «الرف فارغ» شرعي)، والمفاتيح أسطر الجلسة بمعرفات أصنافها، وما لا
/// يُذكر في الخريطة يبقى كما هو. الفروقات لا تُحسب هنا إطلاقاً —
/// لقطة الترحيل وحدها تحسب ضد الأرصدة الآنية.
/// س115: العدّ بالتعبئة بلقطة اختيارية [levelsByItemId] (نمط الفواتير
/// س89 والإذنين والتحويل س113): المستوى من مجموعة الصنف حصراً وعاملُه
/// يطابق العدّة المدخلة بالمخزونية، والمخالف مرفوض بلا كتابة —
/// وإعادة العدّ بالأساسية تمحو اللقطة (NULL) فآخر عدّ هو المعروض.
Future<void> stockCountSaveCounts(
    int sessionId, Map<int, int> countsByItemId,
    {Map<int, StockCountLevelSnapshot> levelsByItemId = const {}}) async {
  final structural = validateStockCountCounts(countsByItemId);
  if (structural.isNotEmpty) {
    throw StockCountValidationException(structural);
  }
  await transaction(() async {
    final session = await _stockCountByIdTx(sessionId);
    if (session == null) {
      throw StockCountValidationException([StockCountNotFound(sessionId)]);
    }
    if (session['state'] == 'posted') {
      throw StockCountValidationException([const StockCountAlreadyPosted()]);
    }
    // س115: حرس مستوى التعبئة على العدّات — الرفض قبل أي كتابة
    // (نمط س-18: الرفض قبل الكتابة حصراً).
    final levelErrors = <StockCountValidationError>[];
    var levelIndex = 0;
    for (final entry in countsByItemId.entries) {
      final snapshot = levelsByItemId[entry.key];
      if (snapshot != null) {
        final invalid = await _countLevelInvalidTx(entry.key, entry.value,
            snapshot);
        if (invalid) {
          final item = await _itemByIdTx(entry.key);
          levelErrors.add(StockCountLevelInvalid(
            levelIndex,
            item == null
                ? '؟'
                : itemDisplayLabel(
                    item['name'] as String, item['sku'] as String),
          ));
        }
      }
      levelIndex++;
    }
    if (levelErrors.isNotEmpty) {
      throw StockCountValidationException(levelErrors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in countsByItemId.entries) {
      final snapshot = levelsByItemId[entry.key];
      // س115: الأعمدة الثلاثة nullable فالكتابة بقيم خام عبر
      // customStatement (نمط الإدراجات — Variable لا يحمل null)،
      // والوجود يُتحقق قبلها فالرفض بلا كتابة عينَ السابق.
      final existing = await customSelect(
        'SELECT id FROM stock_count_lines '
        'WHERE count_id = ? AND item_id = ? AND is_deleted = 0',
        variables: [
          Variable.withInt(sessionId),
          Variable.withInt(entry.key),
        ],
      ).get();
      if (existing.isEmpty) {
        throw StockCountValidationException([
          StockCountItemMissing(entry.key, countsByItemId.keys
              .toList()
              .indexOf(entry.key)),
        ]);
      }
      await customStatement(
        'UPDATE stock_count_lines SET counted_qty_base = ?, '
        'unit_level_id = ?, qty_doc = ?, factor_at_entry = ?, '
        'updated_at = ? WHERE id = ?',
        [
          entry.value,
          snapshot?.unitLevelId,
          snapshot?.qtyDoc,
          snapshot?.factorAtEntry,
          now,
          existing.first.data['id'] as int,
        ],
      );
    }
  });
}

/// س115: فحص لقطة عدّ بالتعبئة — المستوى من مجموعة الصنف حصراً
/// وعاملُه ≥2 والعدّة بالمخزونية تساوي المدخل × العامل (نمط حرس
/// الفواتير س89). TRUE = غير صالحة.
Future<bool> _countLevelInvalidTx(
    int itemId, int countedQtyBase, StockCountLevelSnapshot snapshot) async {
  final item = await _itemByIdTx(itemId);
  final groupId = item == null ? null : item['unit_group_id'] as int?;
  var levelValid = false;
  var levelFactor = 0;
  if (groupId != null) {
    final levelRows = await customSelect(
      'SELECT group_id, factor FROM unit_group_levels '
      'WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(snapshot.unitLevelId)],
    ).get();
    if (levelRows.isNotEmpty &&
        levelRows.first.data['group_id'] as int == groupId) {
      levelFactor = levelRows.first.data['factor'] as int;
      levelValid = levelFactor >= 2;
    }
  }
  return !levelValid ||
      snapshot.qtyDoc <= 0 ||
      snapshot.factorAtEntry != levelFactor ||
      countedQtyBase != snapshot.qtyDoc * snapshot.factorAtEntry;
}

/// إضافة «صنف وجدناه» لجلسة جارٍ — صنف برصيد صفير وُجد فعلاً على
/// الرف، داخل النطاق حصراً (المجموعة بتصنيفها) وبضاعة نشطة وعدّته
/// موجبة (وجوده فعلاً يعني عدّة). رصيد الصفير يعني زيادة من الصفر
/// وتكلفتها بمرجع التكلفة المتاح لحظة الترحيل (قرار D-186).
Future<void> stockCountAddFoundItem(
    int sessionId, StockCountLineDraft line) async {
  final structural = validateStockCountFoundLine(line);
  if (structural.isNotEmpty) {
    throw StockCountValidationException(structural);
  }
  await transaction(() async {
    final session = await _stockCountByIdTx(sessionId);
    if (session == null) {
      throw StockCountValidationException([StockCountNotFound(sessionId)]);
    }
    if (session['state'] == 'posted') {
      throw StockCountValidationException([const StockCountAlreadyPosted()]);
    }
    final errors = <StockCountValidationError>[];
    final item = await _itemByIdTx(line.itemId);
    if (item == null) {
      throw StockCountValidationException(
          [StockCountItemMissing(line.itemId, 0)]);
    }
    final label = itemDisplayLabel(item['name'] as String, item['sku'] as String);
    if ((item['is_active'] as int) != 1) {
      errors.add(StockCountItemInactive(label, 0));
    } else if ((item['kind'] as String) != 'good') {
      errors.add(StockCountItemNotGood(label, 0));
    }
    // س115: حرس مستوى التعبئة لسطر المكتشف (نمط العدّات أعلاه) —
    // والمخالف مرفوض بلا كتابة.
    if (line.unitLevelId != null &&
        await _countLevelInvalidTx(
          line.itemId,
          line.countedQtyBase,
          StockCountLevelSnapshot(
            unitLevelId: line.unitLevelId!,
            qtyDoc: line.qtyDoc ?? 0,
            factorAtEntry: line.factorAtEntry ?? 0,
          ),
        )) {
      errors.add(StockCountLevelInvalid(0, label));
    }
    final scope = session['scope'] as String;
    if (scope == 'group') {
      final category = session['scope_category'] as String?;
      if ((item['category'] as String?) != category) {
        errors.add(StockCountItemOutsideScope(
          itemLabel: label,
          scopeCategory: category ?? '',
          lineIndex: 0,
        ));
      }
    }
    final existing = await customSelect(
      'SELECT id FROM stock_count_lines WHERE count_id = ? AND item_id = ? '
      'AND is_deleted = 0',
      variables: [
        Variable.withInt(sessionId),
        Variable.withInt(line.itemId),
      ],
    ).get();
    if (existing.isNotEmpty) {
      errors.add(const StockCountItemDuplicated(0));
    }
    if (errors.isNotEmpty) {
      throw StockCountValidationException(errors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      'INSERT INTO stock_count_lines (count_id, item_id, counted_qty_base, '
      'unit_level_id, qty_doc, factor_at_entry, '
      'uuid, created_at, updated_at, is_deleted) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
      [
        sessionId,
        line.itemId,
        line.countedQtyBase,
        line.unitLevelId,
        line.qtyDoc,
        line.factorAtEntry,
        const Uuid().v4(),
        now,
        now,
      ],
    );
  });
}

/// ترحيل جلسة الجرد (س-19) — قلب الدفعة: لكل صنف الفرق ضد الرصيد
/// الآني لحظة الترحيل، عجزاً كان أو زيادة:
/// - **عجز** (النظام أكثر من المعدود): قيمة الخروج بالامتصاص
///   (wacExitValue نمط D-067 — العدّ بكامل الكمية يمتص القيمة كلها)
///   وقيدُه **56 عجز الجرد مدين / 113 دائن** وحركة تسوية نزول.
/// - **زيادة** (المعدود أكثر من النظام): تكلفتها بالمتوسط المرجح
///   الحالي للمستودع (F-047: كلفة الوحدة مشتقة من القيمة الإجمالية
///   D-067) وعند رصيد صفير بلا متوسط تُقيَّم بآخر سعر دخول معروف
///   (سعر الشراء المسجل بالصنف — قرار D-186)، وقيدُها **113 مدين /
///   43 إيرادات أخرى دائن** وحركة تسوية صعود. والزيادة بلا مرجع
///   تكلفة إطلاقاً (رصيد صفير وسعر شراء صفر) تمر قيمتها صفراً —
///   حركة ورصيد بلا سطر قيد (سطر صفر مرفوض بالمدقق المحاسبي 07 §2.1).
/// - الفروقات الصفرية لا حركة ولا قيد لها — لا قيمة مالية.
/// القيد قيدٌ واحد للجلسة «مجمع بمرجعها» (س-19: ref_doc_type=
/// 'stock_count') بدفتر المخزون بنوعه move_stock، بأسطر لكل صنف
/// (زوج عجز أو زوج زيادة) كل 113 مربوط بحركته (نمط الفواتير)،
/// ويرحّل بالمحرك الموحد _postMoveWithinTx ففحص الفترة المقفلة
/// والتوازن والترقيم المركزي من منظامه (07 §1.5/§1.9/§2.1) —
/// والحاجز الثالث مُشغِّلات الفترة على الرأس نفسه. أسطر الجلسة
/// تخزن لقطة الترحيل كاملة (system/diff/direction/value) فالشاشة
/// بعد الترحيل قراءة لا حساب. حدث «posted» بلقطة الرأس والأسطر.
/// س112: إلغاء جلسة عدٍّ مفتوحة مهجورة — حذف منطقي للرأس وأسطره
/// (روح D-043: الإلغاء حذف منطقي) فالجلسة بلا ترحيل لا أثر لها ولا
/// لأسطرها — والمرحّلة لقطة تاريخية لا تُلغى (نمط F-140) — والإلغاء
/// يحرر مستودعَها لجلسة جديدة (حرس الجلسة المفتوحة الواحدة).
Future<void> stockCountCancel(int sessionId) async {
  await transaction(() async {
    final session = await _stockCountByIdTx(sessionId);
    if (session == null) {
      throw StockCountValidationException([StockCountNotFound(sessionId)]);
    }
    if (session['state'] != 'open') {
      throw StockCountValidationException([const StockCountNotOpen()]);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      'UPDATE stock_counts SET is_deleted = 1, updated_at = ? '
      'WHERE id = ? AND state = \'open\' AND is_deleted = 0',
      [now, sessionId],
    );
    await customStatement(
      'UPDATE stock_count_lines SET is_deleted = 1, updated_at = ? '
      'WHERE count_id = ?',
      [now, sessionId],
    );
  });
}

Future<void> stockCountPost(int sessionId) async {
  await transaction(() async {
    final session = await _stockCountByIdTx(sessionId);
    if (session == null) {
      throw StockCountValidationException([StockCountNotFound(sessionId)]);
    }
    if (session['state'] == 'posted') {
      throw StockCountValidationException([const StockCountAlreadyPosted()]);
    }
    final warehouseId = session['warehouse_id'] as int;
    final warehouse = await _warehouseByIdTx(warehouseId);
    if (warehouse == null) {
      throw StockCountValidationException(
          [StockCountWarehouseMissing(warehouseId)]);
    }
    if (!warehouse.isActive) {
      throw StockCountValidationException(
          [StockCountWarehouseInactive(warehouse.name)]);
    }
    final lineRows = await customSelect(
      'SELECT l.id, l.item_id, l.counted_qty_base, i.name, i.sku, '
      'i.kind, i.is_active, i.category, i.purchase_price_minor '
      'FROM stock_count_lines l JOIN items i ON i.id = l.item_id '
      'WHERE l.count_id = ? AND l.is_deleted = 0 ORDER BY l.id',
      variables: [Variable.withInt(sessionId)],
    ).get();
    if (lineRows.isEmpty) {
      throw StockCountValidationException([const StockCountNoLines()]);
    }
    // لا تسوية جزئية: كل سطر مُعدّ (الصفر شرعي) والصنف نشط بضاعة.
    final errors = <StockCountValidationError>[];
    for (var i = 0; i < lineRows.length; i++) {
      final row = lineRows[i].data;
      final label =
          itemDisplayLabel(row['name'] as String, row['sku'] as String);
      if (row['counted_qty_base'] == null) {
        errors.add(StockCountLineNotCounted(label, i));
        continue;
      }
      if ((row['is_active'] as int) != 1) {
        errors.add(StockCountItemInactive(label, i));
      } else if ((row['kind'] as String) != 'good') {
        errors.add(StockCountItemNotGood(label, i));
      }
    }
    if (errors.isNotEmpty) {
      throw StockCountValidationException(errors);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dateText = session['count_date'] as String;
    final acc113 = await _accountIdByCodeTx('113');
    final acc43 = await _accountIdByCodeTx('43');
    final acc56 = await _accountIdByCodeTx('56');
    final journalId = await _journalIdByCodeTx('stock');
    // حركات المخزون أولاً لأخذ معرفاتها لربط أسطر 113 (نمط الفواتير)
    // ثم القيد المجمع ثم دلتا الأرصدة — كله بالمعاملة ذاتها.
    final moveLines = <MoveLineDraft>[];
    for (final row in lineRows) {
      final d = row.data;
      final itemId = d['item_id'] as int;
      final counted = d['counted_qty_base'] as int;
      final (systemQty, systemValue) =
          await _stockBalanceTx(itemId, warehouseId);
      final diff = counted - systemQty;
      if (diff == 0) {
        // فرق صفري: لقطة اتجاهها none بلا حركة ولا قيد
        await customStatement(
          'UPDATE stock_count_lines SET system_qty_base = ?, '
          "diff_qty_base = 0, direction = 'none', value_base_minor = 0, "
          'unit_cost_base_minor = 0, updated_at = ? WHERE id = ?',
          [systemQty, now, d['id'] as int],
        );
        continue;
      }
      if (diff < 0) {
        // عجز — الخروج بالامتصاص (D-067)
        final qtyOut = -diff;
        final exitValue = wacExitValue(systemValue, systemQty, qtyOut);
        await customStatement(
          "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
          "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
          "ref_doc_type, ref_doc_id, uuid, created_at, updated_at, "
          "is_deleted) VALUES (?, ?, ?, NULL, ?, ?, 'posted', "
          "'stock_count', ?, ?, ?, ?, 0)",
          [
            itemId,
            -qtyOut,
            warehouseId,
            exitValue,
            roundHalfAwayFromZeroRatio(exitValue, qtyOut),
            sessionId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        final moveId = (await customSelect(
          'SELECT last_insert_rowid() AS id',
        ).getSingle()).data['id'] as int;
        if (exitValue > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc56,
            debitMinor: exitValue,
            currencyId: 1,
            amountMinor: exitValue,
          ));
          moveLines.add(MoveLineDraft(
            accountId: acc113,
            creditMinor: exitValue,
            currencyId: 1,
            amountMinor: exitValue,
            refStockMoveId: moveId,
          ));
        }
        await customStatement(
          'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
          'total_value_minor, uuid, created_at, updated_at, is_deleted) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
          'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
          'qty_base = qty_base + excluded.qty_base, '
          'total_value_minor = total_value_minor + excluded.total_value_minor, '
          'updated_at = excluded.updated_at',
          [
            itemId,
            warehouseId,
            -qtyOut,
            -exitValue,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        await customStatement(
          'UPDATE stock_count_lines SET system_qty_base = ?, '
          'diff_qty_base = ?, direction = ?, value_base_minor = ?, '
          'unit_cost_base_minor = ?, updated_at = ? WHERE id = ?',
          [
            systemQty,
            diff,
            'deficit',
            exitValue,
            roundHalfAwayFromZeroRatio(exitValue, qtyOut),
            now,
            d['id'] as int,
          ],
        );
      } else {
        // زيادة — بالمتوسط المرجح الحالي (F-047/D-067) وبلا رصيد
        // بآخر سعر دخول معروف (D-186) وبلا مرجع تكلفتها صفراً.
        final qtyIn = diff;
        final int valueIn;
        final int unitCost;
        if (systemQty > 0) {
          valueIn = roundHalfAwayFromZeroRatio(systemValue * qtyIn, systemQty);
          unitCost = roundHalfAwayFromZeroRatio(valueIn, qtyIn);
        } else {
          final purchase =
              (d['purchase_price_minor'] as int?) ?? 0;
          valueIn = purchase * qtyIn;
          unitCost = purchase;
        }
        await customStatement(
          "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
          "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
          "ref_doc_type, ref_doc_id, uuid, created_at, updated_at, "
          "is_deleted) VALUES (?, ?, NULL, ?, ?, ?, 'posted', "
          "'stock_count', ?, ?, ?, ?, 0)",
          [
            itemId,
            qtyIn,
            warehouseId,
            valueIn,
            unitCost,
            sessionId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        final moveId = (await customSelect(
          'SELECT last_insert_rowid() AS id',
        ).getSingle()).data['id'] as int;
        if (valueIn > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc113,
            debitMinor: valueIn,
            currencyId: 1,
            amountMinor: valueIn,
            refStockMoveId: moveId,
          ));
          moveLines.add(MoveLineDraft(
            accountId: acc43,
            creditMinor: valueIn,
            currencyId: 1,
            amountMinor: valueIn,
          ));
        }
        await customStatement(
          'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
          'total_value_minor, uuid, created_at, updated_at, is_deleted) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
          'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
          'qty_base = qty_base + excluded.qty_base, '
          'total_value_minor = total_value_minor + excluded.total_value_minor, '
          'updated_at = excluded.updated_at',
          [
            itemId,
            warehouseId,
            qtyIn,
            valueIn,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        await customStatement(
          'UPDATE stock_count_lines SET system_qty_base = ?, '
          'diff_qty_base = ?, direction = ?, value_base_minor = ?, '
          'unit_cost_base_minor = ?, updated_at = ? WHERE id = ?',
          [
            systemQty,
            diff,
            'surplus',
            valueIn,
            unitCost,
            now,
            d['id'] as int,
          ],
        );
      }
    }
    // القيد المجمع بمرجع الجلسة — بأسطر لا يمرر صفراً (الزيادة بلا
    // تكلفة حركة بلا قيد) فجلسة فروقاتها كلها صفرية القيمة بلا قيد.
    if (moveLines.isNotEmpty) {
      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: dateText,
        narration: session['narration'] as String? ??
            'تسوية جرد المستودع «${warehouse.name}»',
        refDocType: 'stock_count',
        refDocId: sessionId,
        lines: moveLines,
      ));
      await _postMoveWithinTx(moveId, sequenceKind: 'move_stock');
    }
    await customStatement(
      "UPDATE stock_counts SET state = 'posted', updated_at = ? "
      'WHERE id = ?',
      [now, sessionId],
    );
    await _recordDocEventTx(
      entityType: 'stock_count',
      table: 'stock_counts',
      entityId: sessionId,
      action: 'posted',
    );
  });
}

/// رأس جلسة جرد بالمعرف داخل معاملة قائمة (نمط القلب — الأداة المشتركة).
Future<Map<String, Object?>?> _stockCountByIdTx(int id) async {
  final rows = await customSelect(
    'SELECT id, number, count_date, warehouse_id, scope, scope_category, '
    "narration, state FROM stock_counts WHERE id = ? AND is_deleted = 0",
    variables: [Variable.withInt(id)],
  ).get();
  return rows.isEmpty ? null : rows.first.data;
}

/// سجل جلسات الجرد — الرؤوس بأسماء مستودعاتها وعدّاداتها المجمعية
/// (قراءة عرض خالصة — التخزين يقرأ لا يحسب)، الأحدث أولاً.
Future<List<StockCountListRow>> stockCountsOf() async {
  final rows = await customSelect(
    'SELECT c.id, c.number, c.count_date, c.warehouse_id, c.scope, '
    'c.scope_category, c.narration, c.state, '
    'w.name AS warehouse_name, '
    'COUNT(l.id) AS line_count, '
    "COUNT(l.counted_qty_base) AS counted_count, "
    "COALESCE(SUM(CASE WHEN l.direction = 'deficit' THEN 1 ELSE 0 END), 0) "
    'AS deficit_count, '
    "COALESCE(SUM(CASE WHEN l.direction = 'surplus' THEN 1 ELSE 0 END), 0) "
    'AS surplus_count, '
    "COALESCE(SUM(CASE WHEN l.direction = 'deficit' THEN l.value_base_minor "
    'ELSE 0 END), 0) AS deficit_value, '
    "COALESCE(SUM(CASE WHEN l.direction = 'surplus' THEN l.value_base_minor "
    'ELSE 0 END), 0) AS surplus_value '
    'FROM stock_counts c '
    'LEFT JOIN warehouses w ON w.id = c.warehouse_id '
    'LEFT JOIN stock_count_lines l ON l.count_id = c.id AND l.is_deleted = 0 '
    'WHERE c.is_deleted = 0 '
    'GROUP BY c.id ORDER BY c.id DESC',
  ).get();
  return [
    for (final r in rows)
      StockCountListRow(
        id: r.data['id'] as int,
        number: r.data['number'] as String,
        countDate: r.data['count_date'] as String,
        warehouseId: r.data['warehouse_id'] as int,
        warehouseName: r.data['warehouse_name'] as String? ?? '؟',
        scope: r.data['scope'] as String,
        scopeCategory: r.data['scope_category'] as String?,
        narration: r.data['narration'] as String?,
        state: r.data['state'] as String,
        lineCount: r.data['line_count'] as int,
        countedCount: r.data['counted_count'] as int,
        deficitCount: r.data['deficit_count'] as int,
        surplusCount: r.data['surplus_count'] as int,
        deficitValueMinor: r.data['deficit_value'] as int,
        surplusValueMinor: r.data['surplus_value'] as int,
      ),
  ];
}

/// أسطر جلسة جرد — للعدّ المتكرر قبل الترحيل (بالرصيد الآني ليسحق
/// الفرق على الشاشة) وللقطة بعد الترحيل (اللقطة المخزنة لا حساب جديد).
Future<List<StockCountLineRow>> stockCountLinesOf(int sessionId) async {
  final rows = await customSelect(
    'SELECT l.item_id, i.name AS item_name, i.sku, i.category, '
    'l.counted_qty_base, l.unit_level_id, l.qty_doc, l.factor_at_entry, '
    'l.system_qty_base, l.diff_qty_base, '
    'l.direction, l.value_base_minor, l.unit_cost_base_minor '
    'FROM stock_count_lines l '
    'LEFT JOIN items i ON i.id = l.item_id '
    'WHERE l.count_id = ? AND l.is_deleted = 0 ORDER BY l.id',
    variables: [Variable.withInt(sessionId)],
  ).get();
  return [
    for (final r in rows)
      StockCountLineRow(
        itemId: r.data['item_id'] as int,
        itemName: r.data['item_name'] as String?,
        sku: r.data['sku'] as String?,
        itemCategory: r.data['category'] as String?,
        countedQtyBase: r.data['counted_qty_base'] as int?,
        unitLevelId: r.data['unit_level_id'] as int?,
        qtyDoc: r.data['qty_doc'] as int?,
        factorAtEntry: r.data['factor_at_entry'] as int?,
        systemQtyBase: r.data['system_qty_base'] as int?,
        diffQtyBase: r.data['diff_qty_base'] as int?,
        direction: r.data['direction'] as String?,
        valueBaseMinor: r.data['value_base_minor'] as int,
        unitCostBaseMinor: r.data['unit_cost_base_minor'] as int,
      ),
  ];
}

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

// ═══ الدفعة 34 — تعدد العملات الفعلي (F-120/F-121/F-124، D-194) ═══
// الإدارة الكاملة بلا مساس بالبنية القائمة من م1 (D-070/F-122/F-123):
// إضافة عملات جديدة حصراً — لا تعديل بعد الحفظ — والتعطيل بحرستيه
// (الأساسية محمية والمرجعية مرفوضة)، وأسعار الصرف التاريخية مجمدة
// بطبقة القاعدة (لا تعديل لسعر محفوظ أبداً — F-121)، وتقرير مراكز
// العملات بقيمه المخزنة حصراً بلا أي حساب صرف جديد (F-124).

/// إضافة عملة جديدة (F-120/D-194) — المدقق البنيوي في المجال
/// (validateCurrencySpec) والفحص هنا على ما خُزّن: تفرد الكود مطلق
/// بالحي والمعطل معاً لأن اللقطات التاريخية تحيل إلى الكود لا إلى
/// الصف، والحقول محفوظة كما كتبت أول مرة فلا تعديل بعد الحفظ
/// (نمط المرجع الدائم 03 §6-3).
Future<int> currenciesAdd({
  required String code,
  required String name,
  required int minorUnits,
}) async {
  final existingCodes = <String>{
    for (final r in (await customSelect('SELECT code FROM currencies').get()))
      normalizeCurrencyCode(r.data['code'] as String),
  };
  final errors = validateCurrencySpec(
    CurrencySpec(code: code, name: name, minorUnits: minorUnits),
    existingCodes: existingCodes,
  );
  if (errors.isNotEmpty) {
    throw StateError('عملة غير سليمة — ${errors.first.runtimeType}');
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  await customStatement(
    'INSERT INTO currencies (code, name, minor_units, is_base, uuid, '
    'created_at, updated_at, is_deleted) VALUES (?, ?, ?, 0, ?, ?, ?, 0)',
    [
      normalizeCurrencyCode(code),
      name.trim(),
      minorUnits,
      const Uuid().v4(),
      now,
      now,
    ],
  );
  return (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
      .data['id'] as int;
}

/// تعطيل عملة (F-120/D-194) — بحرستيه: الأساسية لا تُعطَّل (هي مقياس
/// الكل)، والعملة عليها مرجع قائم — ولو في صف معطَّل — لا تُعطَّل
/// لأن اللقطات التاريخية تحيل إليها. والتعطيل علامة is_deleted لا
/// حذف أبداً (نمط 03 §6-3).
Future<void> currenciesDeactivate(int currencyId) async {
  final cur = await customSelect(
    'SELECT id, is_base FROM currencies WHERE id = ? AND is_deleted = 0',
    variables: [Variable.withInt(currencyId)],
  ).get();
  if (cur.isEmpty) {
    throw StateError('لا عملة حية بالمعرف $currencyId');
  }
  if ((cur.first.data['is_base'] as int) == 1) {
    throw StateError('عملة الأساسية لا تُعطَّل — هي مقياس الكل (D-194)');
  }
  const checks = <(String, String)>[
    ('invoices', 'currency_id'),
    ('vouchers', 'currency_id'),
    ('cash_boxes', 'currency_id'),
    ('parties', 'default_currency_id'),
    ('move_lines', 'currency_id'),
    ('items', 'price_currency_id'),
  ];
  var refs = 0;
  for (final (table, column) in checks) {
    final r = await customSelect(
      'SELECT COUNT(*) AS c FROM "$table" WHERE "$column" = ?',
      variables: [Variable.withInt(currencyId)],
    ).getSingle();
    refs += r.data['c'] as int;
  }
  if (refs > 0) {
    throw StateError(
      'العملة عليها $refs مرجع قائم — التعطيل للعملات غير المستخدمة '
      'حصراً (اللقطات التاريخية تحيل إليها — D-194)',
    );
  }
  await customStatement(
    'UPDATE currencies SET is_deleted = 1, updated_at = ? WHERE id = ?',
    [DateTime.now().millisecondsSinceEpoch, currencyId],
  );
}

/// تسجيل سعر صرف يومي (F-121/D-194) — المدقق في المجال (السعر
/// المكبَّر موجب والتاريخ ISO صالح غير مستقبل والعملة ليست الأساسية)
/// والفحص هنا على ما خُزّن: العملة حية واليوم بلا سجل سابق — فاليوم
/// المسجل لا يقبل ثانية والسجل المحفوظ لا يُعدل ولا يُحذف إطلاقاً
/// (التجميد نمط F-140 بطبقة القاعدة).
Future<int> exchangeRateRecord({
  required int currencyId,
  required String date,
  required int rateToBase,
}) async {
  final cur = await customSelect(
    'SELECT is_base FROM currencies WHERE id = ? AND is_deleted = 0',
    variables: [Variable.withInt(currencyId)],
  ).get();
  if (cur.isEmpty) {
    throw StateError('لا عملة حية بالمعرف $currencyId');
  }
  final errors = validateExchangeRateRecord(
    rateToBase: rateToBase,
    date: date,
    todayIso: todayIsoDate(),
    isBase: (cur.first.data['is_base'] as int) == 1,
  );
  if (errors.isNotEmpty) {
    throw StateError('سعر غير سليم — ${errors.first.runtimeType}');
  }
  final day = date.trim();
  final dup = await customSelect(
    'SELECT id FROM exchange_rate WHERE currency_id = ? AND date = ?',
    variables: [Variable.withInt(currencyId), Variable.withString(day)],
  ).get();
  if (dup.isNotEmpty) {
    throw StateError(
      'سعر هذا اليوم محفوظ سابقاً — لا تعديل لسعر محفوظ أبداً (F-121)',
    );
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  await customStatement(
    'INSERT INTO exchange_rate (currency_id, date, rate_to_base, uuid, '
    'created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, 0)',
    [currencyId, day, rateToBase, const Uuid().v4(), now, now],
  );
  return (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
      .data['id'] as int;
}

/// أسعار عملة محفوظة — الأحدث أولاً (F-121).
Future<List<ExchangeRateEntry>> exchangeRatesOf(int currencyId) async {
  final rows = await customSelect(
    'SELECT currency_id, date, rate_to_base FROM exchange_rate '
    'WHERE currency_id = ? ORDER BY date DESC, id DESC',
    variables: [Variable.withInt(currencyId)],
  ).get();
  return [
    for (final r in rows)
      ExchangeRateEntry(
        currencyId: r.data['currency_id'] as int,
        date: r.data['date'] as String,
        rateToBase: r.data['rate_to_base'] as int,
      ),
  ];
}

/// آخر سعر مسجل لعملة — يملأ الافتراض بلقطة المستند فحسب (D-070:
/// اللقطة اليدوية باقية) — ويعود null بلا سجل.
Future<ExchangeRateEntry?> latestExchangeRate(int currencyId) async {
  final rows = await exchangeRatesOf(currencyId);
  return rows.isEmpty ? null : rows.first;
}

/// مراكز العملات (F-124/D-194) — لكل عملة حية: صناديقها بعددها
/// ومجموع أرصدتها بالأساسية من الدفتر (نمط تقرير الصناديق ذاته)،
/// وفواتيرها المفتوحة المرحّلة المتبقية بعملة الفاتورة وبأساسها
/// المخزن بلقطة الفاتورة ذاتها (لا حساب صرف جديد — القيم المخزنة
/// حصراً؛ الصندوق الدولاري رصيده الدفتري بالأساسية)، وآخر سعر
/// مسجل بتاريخه. التجميع النهائي بالمجال النقي
/// (currencyPositionsCompute).
Future<List<CurrencyPositionInput>> currencyPositions() async {
  final currencies = await customSelect(
    'SELECT id, code, name, is_base FROM currencies '
    'WHERE is_deleted = 0 ORDER BY id',
  ).get();
  final rows = <CurrencyPositionInput>[];
  for (final c in currencies) {
    final cid = c.data['id'] as int;
    final boxes = await customSelect(
      'SELECT id FROM cash_boxes WHERE currency_id = ? '
      'AND is_deleted = 0 ORDER BY id',
      variables: [Variable.withInt(cid)],
    ).get();
    var boxesBase = 0;
    for (final b in boxes) {
      boxesBase += await _cashBoxBalanceTx(b.data['id'] as int);
    }
    final open = await customSelect(
      'SELECT COUNT(*) AS cnt, '
      'COALESCE(SUM(i.total_doc_minor - COALESCE(a.applied, 0)), 0) '
      'AS rem_doc, '
      'COALESCE(SUM(i.total_base_minor - COALESCE(a.applied_base, 0)), 0) '
      'AS rem_base '
      'FROM invoices i '
      'LEFT JOIN (SELECT invoice_id, SUM(applied_doc_minor) AS applied, '
      'SUM(applied_base_minor) AS applied_base FROM voucher_allocations '
      'GROUP BY invoice_id) a ON a.invoice_id = i.id '
      'WHERE i.currency_id = ? AND i.is_deleted = 0 '
      "AND i.state IN ('posted', 'partially_paid') "
      'AND (i.total_doc_minor - COALESCE(a.applied, 0)) > 0',
      variables: [Variable.withInt(cid)],
    ).getSingle();
    final rate = await latestExchangeRate(cid);
    rows.add(CurrencyPositionInput(
      currencyId: cid,
      code: c.data['code'] as String,
      name: c.data['name'] as String,
      isBase: (c.data['is_base'] as int) == 1,
      boxesCount: boxes.length,
      boxesBaseMinor: boxesBase,
      openInvoicesCount: open.data['cnt'] as int,
      openRemainderDocMinor: open.data['rem_doc'] as int,
      openRemainderBaseMinor: open.data['rem_base'] as int,
      latestRateToBase: rate?.rateToBase,
      latestRateDate: rate?.date,
    ));
  }
  return rows;
}

  // ═══ الدفعة 26 — إذنا المخزون (F-209/F-210، س85/D-189) ═══
  // المحرك على نمط التحويل والجرد: المدقق البنيوي في المجال والفحوص
  // المحركية هنا على ما خُزّن لا على ما قيل، والحاجز الثاني مُشغِّلات
  // القاعدة (التجميد نمط F-140 وحاجزا الفترة — سابع وثامن المستندات
  // القيدية)، وكل ترحيل معاملة واحدة أي رفض يتراجع كله بما فيه
  // العدّاد فلا رقم يُحرق بترحيل مرفوض (07 §1.9).

  /// ترحيل إذن إدخال المخزون (F-209) — بلا مسودة (نمط س-18: الرفض قبل
  /// الكتابة حصراً). الزيادة بتقييم زيادة الجرد المقرر (D-186): المتوسط
  /// الحالي عند رصيد موجب فلا يمس المتوسط، وسعر الشراء المسجل عند رصيد
  /// صفير، وصفر بلا مرجعين فلا سطر قيد لها (حركة بقيمة صفر). المقابل
  /// افتراضه 43 من الواجهة وقابل التغيير من الحسابات المفعلة حصراً.
  Future<int> stockReceiptPost(StockReceiptDraft draft) async {
    final structural = validateStockReceiptStructure(draft);
    if (structural.isNotEmpty) {
      throw StockDocValidationException(structural);
    }
    return transaction(() => _stockReceiptPostWithinTx(draft));
  }

  /// س141: الشطر الداخلي لترحيل إذن الإدخال — داخل معاملة قائمة حصراً:
  /// استيراد الأرصدة الكاملة يمر به داخل معاملته الواحدة فلا مسار
  /// ترحيل ثاني ولا إذن يُكتب خارج المحرك الموحد (07 §1.1).
  Future<int> _stockReceiptPostWithinTx(StockReceiptDraft draft) async {
      final errors = await _collectStockDocErrors(
        dateText: draft.dateText,
        warehouseId: draft.warehouseId,
        reason: draft.reason,
        counterAccountId: draft.counterAccountId,
        lines: draft.lines,
        direction: 'receipt',
      );
      if (errors.isNotEmpty) {
        throw StockDocValidationException(errors);
      }
      final docId = await _insertStockDocHeadWithinTx(
        table: 'stock_receipts',
        dateColumn: 'receipt_date',
        sequenceKind: 'stock_receipt',
        dateText: draft.dateText,
        warehouseId: draft.warehouseId,
        reason: draft.reason,
        counterAccountId: draft.counterAccountId,
        narration: draft.narration,
      );
      final acc113 = await _accountIdByCodeTx('113');
      final moveLines = <MoveLineDraft>[];
      var totalValue = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final line in draft.lines) {
        // تقييم الزيادة بروح D-186 — المتوسط الحاكم لا يتغير بإضافة
        // كمية بتكلفته (05: الترصيد بالقيمة الإجمالية D-067) — إلا سطر
        // القيمة الصريحة (س141): رصيد أول المدة قيمة تاريخية من الملف
        // لا زيادة جرد تُقيَّن، فتُصدَّق كما وردت.
        final (systemQty, systemValue) =
            await _stockBalanceTx(line.itemId, draft.warehouseId);
        final item = await _itemByIdTx(line.itemId);
        final int valueIn;
        final int unitCost;
        if (line.valueBaseMinor != null) {
          valueIn = line.valueBaseMinor!;
          unitCost = roundHalfAwayFromZeroRatio(valueIn, line.qtyBase);
        } else if (systemQty > 0) {
          valueIn = roundHalfAwayFromZeroRatio(
              systemValue * line.qtyBase, systemQty);
          unitCost = roundHalfAwayFromZeroRatio(valueIn, line.qtyBase);
        } else {
          final purchase =
              (item?['purchase_price_minor'] as int?) ?? 0;
          valueIn = purchase * line.qtyBase;
          unitCost = purchase;
        }
        await customStatement(
          'INSERT INTO stock_receipt_lines (doc_id, item_id, qty_base, '
          'unit_level_id, qty_doc, factor_at_entry, '
          'unit_cost_base_minor, value_base_minor, uuid, created_at, '
          'updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
          [
            docId,
            line.itemId,
            line.qtyBase,
            line.unitLevelId,
            line.qtyDoc,
            line.factorAtEntry,
            unitCost,
            valueIn,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        await customStatement(
          "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
          "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
          "ref_doc_type, ref_doc_id, uuid, created_at, updated_at, "
          "is_deleted) VALUES (?, ?, NULL, ?, ?, ?, 'posted', "
          "'stock_receipt', ?, ?, ?, ?, 0)",
          [
            line.itemId,
            line.qtyBase,
            draft.warehouseId,
            valueIn,
            unitCost,
            docId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        final moveId = (await customSelect(
          'SELECT last_insert_rowid() AS id',
        ).getSingle()).data['id'] as int;
        if (valueIn > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc113,
            debitMinor: valueIn,
            currencyId: 1,
            amountMinor: valueIn,
            refStockMoveId: moveId,
          ));
        }
        totalValue += valueIn;
        await customStatement(
          'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
          'total_value_minor, uuid, created_at, updated_at, is_deleted) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
          'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
          'qty_base = qty_base + excluded.qty_base, '
          'total_value_minor = total_value_minor + excluded.total_value_minor, '
          'updated_at = excluded.updated_at',
          [
            line.itemId,
            draft.warehouseId,
            line.qtyBase,
            valueIn,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        // لقطة التكلفة على سطر المستند — لقطة تاريخية مجمدة بمُشغّل
        // الجدول (نمط F-140) فلا تحديث لاحق عليها.
      }
      // القيد — 113 مدين بحركاته / المقابل دائن بمجموع القيم — والزيادة
      // بلا مرجع تكلفة كلها بلا قيد (D-186: قيمة صفر بلا سطر قيد).
      if (totalValue > 0) {
        moveLines.add(MoveLineDraft(
          accountId: draft.counterAccountId,
          creditMinor: totalValue,
          currencyId: 1,
          amountMinor: totalValue,
        ));
        final moveId = await _insertMoveDraftWithinTx(MoveDraft(
          journalId: await _journalIdByCodeTx('stock'),
          dateText: draft.dateText,
          narration: draft.narration ?? 'إذن إدخال مخزون (${draft.reason})',
          refDocType: 'stock_receipt',
          refDocId: docId,
          lines: moveLines,
        ));
        await _postMoveWithinTx(moveId, sequenceKind: 'move_stock');
      }
      await _recordDocEventTx(
        entityType: 'stock_receipt',
        table: 'stock_receipts',
        entityId: docId,
        action: 'posted',
      );
      return docId;
  }

  /// ترحيل إذن إخراج المخزون (F-210) — بلا مسودة، والخروج بتكلفة
  /// المتوسط الحاكم بالامتصاص (F-047/D-067) وبحماية السالب (F-042):
  /// الفحص على ما خُزّن قبل الكتابة والحاجز في القاعدة احتياطاً.
  /// المقابل افتراضه 596 من الواجهة وقابل التغيير من الحسابات المفعلة.
  Future<int> stockIssuePost(StockIssueDraft draft) async {
    final structural = validateStockIssueStructure(draft);
    if (structural.isNotEmpty) {
      throw StockDocValidationException(structural);
    }
    return transaction(() async {
      final errors = await _collectStockDocErrors(
        dateText: draft.dateText,
        warehouseId: draft.warehouseId,
        reason: draft.reason,
        counterAccountId: draft.counterAccountId,
        lines: draft.lines,
        direction: 'issue',
      );
      if (errors.isNotEmpty) {
        throw StockDocValidationException(errors);
      }
      final docId = await _insertStockDocHeadWithinTx(
        table: 'stock_issues',
        dateColumn: 'issue_date',
        sequenceKind: 'stock_issue',
        dateText: draft.dateText,
        warehouseId: draft.warehouseId,
        reason: draft.reason,
        counterAccountId: draft.counterAccountId,
        narration: draft.narration,
      );
      final acc113 = await _accountIdByCodeTx('113');
      final moveLines = <MoveLineDraft>[];
      var totalValue = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final line in draft.lines) {
        final (systemQty, systemValue) =
            await _stockBalanceTx(line.itemId, draft.warehouseId);
        // الخروج بالامتصاص (D-067) — ما خرج يحمل قيمته كاملة
        // والباقي بمتوسطه السابق بلا غبار تقريب.
        final exitValue =
            wacExitValue(systemValue, systemQty, line.qtyBase);
        final unitCost =
            roundHalfAwayFromZeroRatio(exitValue, line.qtyBase);
        await customStatement(
          'INSERT INTO stock_issue_lines (doc_id, item_id, qty_base, '
          'unit_level_id, qty_doc, factor_at_entry, '
          'unit_cost_base_minor, value_base_minor, uuid, created_at, '
          'updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
          [
            docId,
            line.itemId,
            line.qtyBase,
            line.unitLevelId,
            line.qtyDoc,
            line.factorAtEntry,
            unitCost,
            exitValue,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        await customStatement(
          "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
          "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
          "ref_doc_type, ref_doc_id, uuid, created_at, updated_at, "
          "is_deleted) VALUES (?, ?, ?, NULL, ?, ?, 'posted', "
          "'stock_issue', ?, ?, ?, ?, 0)",
          [
            line.itemId,
            -line.qtyBase,
            draft.warehouseId,
            exitValue,
            unitCost,
            docId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        final moveId = (await customSelect(
          'SELECT last_insert_rowid() AS id',
        ).getSingle()).data['id'] as int;
        if (exitValue > 0) {
          moveLines.add(MoveLineDraft(
            accountId: acc113,
            creditMinor: exitValue,
            currencyId: 1,
            amountMinor: exitValue,
            refStockMoveId: moveId,
          ));
        }
        totalValue += exitValue;
        await customStatement(
          'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
          'total_value_minor, uuid, created_at, updated_at, is_deleted) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
          'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
          'qty_base = qty_base + excluded.qty_base, '
          'total_value_minor = total_value_minor + excluded.total_value_minor, '
          'updated_at = excluded.updated_at',
          [
            line.itemId,
            draft.warehouseId,
            -line.qtyBase,
            -exitValue,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        // لقطة التكلفة على سطر المستند — لقطة تاريخية مجمدة بمُشغّل
        // الجدول (نمط F-140) فلا تحديث لاحق عليها.
      }
      // القيد — المقابل مدين بمجموع القيم / 113 دائن بحركاته — والخروج
      // بلا قيمة (رصيد صفيري القيمة) بلا قيد.
      if (totalValue > 0) {
        moveLines.add(MoveLineDraft(
          accountId: draft.counterAccountId,
          debitMinor: totalValue,
          currencyId: 1,
          amountMinor: totalValue,
        ));
        final moveId = await _insertMoveDraftWithinTx(MoveDraft(
          journalId: await _journalIdByCodeTx('stock'),
          dateText: draft.dateText,
          narration: draft.narration ?? 'إذن إخراج مخزون (${draft.reason})',
          refDocType: 'stock_issue',
          refDocId: docId,
          lines: moveLines,
        ));
        await _postMoveWithinTx(moveId, sequenceKind: 'move_stock');
      }
      await _recordDocEventTx(
        entityType: 'stock_issue',
        table: 'stock_issues',
        entityId: docId,
        action: 'posted',
      );
      return docId;
    });
  }

  /// رأس الإذن — إدراج مرحّل برقمه من التسلسل السنوي داخل المعاملة
  /// ذاتها (07 §1.9: لا رقم بلا ترحيل ناجح) بكل شطرَي الإذنين.
  Future<int> _insertStockDocHeadWithinTx({
    required String table,
    required String dateColumn,
    required String sequenceKind,
    required String dateText,
    required int warehouseId,
    required String reason,
    required int counterAccountId,
    required String? narration,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final year = yearOfIsoDate(dateText);
    final number = formatDocumentNumber(year,
        await _advanceSequenceWithinTx(sequenceKind, year),
        counterWidth: await _counterWidth());
    await customStatement(
      'INSERT INTO $table (number, $dateColumn, warehouse_id, reason, '
      "counter_account_id, narration, state, uuid, created_at, updated_at, "
      "is_deleted) VALUES (?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?, 0)",
      [
        number,
        dateText,
        warehouseId,
        reason.trim(),
        counterAccountId,
        narration,
        const Uuid().v4(),
        now,
        now,
      ],
    );
    return (await customSelect('SELECT last_insert_rowid() AS id')
            .getSingle())
        .data['id'] as int;
  }

  /// فحوص الإذنين بقاعدة البيانات — المستودع موجود نشط، والحساب المقابل
  /// موجود مفعّل (F-209/F-210: من الحسابات المفعلة حصراً)، والأصناف
  /// موجودة نشطة بضاعة (س-08)، والإخراج بحماية السالب (F-042) على ما
  /// خُزّن لا على ما قيل.
  Future<List<StockDocValidationError>> _collectStockDocErrors({
    required String dateText,
    required int warehouseId,
    required String reason,
    required int counterAccountId,
    required List<StockDocLineDraft> lines,
    required String direction,
  }) async {
    final errors = <StockDocValidationError>[];
    final warehouse = await _warehouseByIdTx(warehouseId);
    if (warehouse == null) {
      errors.add(StockDocWarehouseMissing(warehouseId, direction: direction));
    } else if (!warehouse.isActive) {
      errors.add(StockDocWarehouseInactive(warehouse.name,
          direction: direction));
    }
    final accRows = await customSelect(
      'SELECT code, name, is_active FROM accounts '
      'WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(counterAccountId)],
    ).get();
    if (accRows.isEmpty) {
      errors.add(StockDocCounterAccountMissing(counterAccountId,
          direction: direction));
    } else if ((accRows.first.data['is_active'] as int) != 1) {
      final label = '${accRows.first.data['name']} '
          '(${accRows.first.data['code']})';
      errors.add(StockDocCounterAccountInactive(label, direction: direction));
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final item = await _itemByIdTx(line.itemId);
      if (item == null) {
        errors.add(StockDocItemMissing(line.itemId, i, direction: direction));
        continue;
      }
      final label =
          itemDisplayLabel(item['name'] as String, item['sku'] as String);
      if ((item['is_active'] as int) != 1) {
        errors.add(StockDocItemInactive(label, i, direction: direction));
        continue;
      }
      if ((item['kind'] as String) != 'good') {
        errors.add(StockDocItemNotGood(label, i, direction: direction));
        continue;
      }
      // س113: حرس مستوى التعبئة (نمط الفواتير س89) — المستوى من
      // مجموعة الصنف حصراً وعاملُه يطابق الكمية المدخلة، والتحويل
      // المخالف مرفوض بلا كتابة.
      if (line.unitLevelId != null) {
        final groupId = item['unit_group_id'] as int?;
        var levelValid = false;
        var levelFactor = 0;
        if (groupId != null) {
          final levelRows = await customSelect(
            'SELECT group_id, factor FROM unit_group_levels '
            'WHERE id = ? AND is_deleted = 0',
            variables: [Variable.withInt(line.unitLevelId!)],
          ).get();
          if (levelRows.isNotEmpty &&
              levelRows.first.data['group_id'] as int == groupId) {
            levelFactor = levelRows.first.data['factor'] as int;
            levelValid = levelFactor >= 2;
          }
        }
        final qtyDoc = line.qtyDoc ?? 0;
        final factor = line.factorAtEntry ?? 0;
        if (!levelValid ||
            qtyDoc <= 0 ||
            factor != levelFactor ||
            line.qtyBase != qtyDoc * factor) {
          errors.add(StockDocLevelInvalid(i, label, direction: direction));
        }
      }
      if (direction == 'issue') {
        final (qty, _) = await _stockBalanceTx(line.itemId, warehouseId);
        if (line.qtyBase > qty) {
          errors.add(StockDocStockInsufficient(
            itemLabel: label,
            onHandQty: qty,
            requestedQty: line.qtyBase,
            lineIndex: i,
            direction: direction,
          ));
        }
      }
    }
    return errors;
  }

  /// سجل إذن — الرؤوس باسم مستودعه وعدد أسطره ومجاميعه وسببه (قراءة
  /// عرض خالصة — التخزين يقرأ لا يحسب) باتجاه واحد لكل نداء.
  Future<List<StockDocListRow>> _stockDocsOf({
    required String table,
    required String linesTable,
    required String dateColumn,
  }) async {
    final rows = await customSelect(
      'SELECT d.id, d.number, d.$dateColumn AS doc_date, d.state, '
      'd.reason, d.narration, d.warehouse_id, w.name AS warehouse_name, '
      'COUNT(l.id) AS line_count, '
      'COALESCE(SUM(l.qty_base), 0) AS total_qty, '
      'COALESCE(SUM(l.value_base_minor), 0) AS total_value '
      'FROM $table d '
      'LEFT JOIN warehouses w ON w.id = d.warehouse_id '
      'LEFT JOIN $linesTable l ON l.doc_id = d.id AND l.is_deleted = 0 '
      'WHERE d.is_deleted = 0 '
      'GROUP BY d.id ORDER BY d.id DESC',
    ).get();
    return [
      for (final r in rows)
        StockDocListRow(
          id: r.data['id'] as int,
          number: r.data['number'] as String,
          dateText: r.data['doc_date'] as String,
          state: r.data['state'] as String,
          reason: r.data['reason'] as String,
          narration: r.data['narration'] as String?,
          warehouseId: r.data['warehouse_id'] as int,
          warehouseName: r.data['warehouse_name'] as String?,
          lineCount: r.data['line_count'] as int,
          totalQtyBase: r.data['total_qty'] as int,
          totalValueMinor: r.data['total_value'] as int,
        ),
    ];
  }

  /// سجل إذون الإدخال — الأحدث أولاً.
  Future<List<StockDocListRow>> stockReceiptsOf() => _stockDocsOf(
      table: 'stock_receipts',
      linesTable: 'stock_receipt_lines',
      dateColumn: 'receipt_date');

  /// سجل إذون الإخراج — الأحدث أولاً.
  Future<List<StockDocListRow>> stockIssuesOf() => _stockDocsOf(
      table: 'stock_issues',
      linesTable: 'stock_issue_lines',
      dateColumn: 'issue_date');

  /// أسطر إذن معين بتفصيله — للسجل والتفصيل (قراءة خالصة).
  Future<List<StockDocLineRow>> _stockDocLinesOf({
    required String linesTable,
    required int docId,
  }) async {
    final rows = await customSelect(
      'SELECT l.item_id, l.qty_base, l.unit_cost_base_minor, '
      'l.value_base_minor, i.name, i.sku '
      'FROM $linesTable l JOIN items i ON i.id = l.item_id '
      'WHERE l.doc_id = ? AND l.is_deleted = 0 ORDER BY l.id',
      variables: [Variable.withInt(docId)],
    ).get();
    return [
      for (final r in rows)
        StockDocLineRow(
          itemId: r.data['item_id'] as int,
          itemName: r.data['name'] as String?,
          sku: r.data['sku'] as String?,
          qtyBase: r.data['qty_base'] as int,
          unitCostBaseMinor: r.data['unit_cost_base_minor'] as int,
          valueBaseMinor: r.data['value_base_minor'] as int,
        ),
    ];
  }

  /// أسطر إذن إدخال بالمعرف.
  Future<List<StockDocLineRow>> stockReceiptLinesOf(int docId) =>
      _stockDocLinesOf(linesTable: 'stock_receipt_lines', docId: docId);

  /// أسطر إذن إخراج بالمعرف.
  Future<List<StockDocLineRow>> stockIssueLinesOf(int docId) =>
      _stockDocLinesOf(linesTable: 'stock_issue_lines', docId: docId);

  // ═══ الدفعة 29 — مستند التجميع (F-211، س88) ═══
  // المحرك على نمط التحويل والجرد: المدقق البنيوي في المجال والفحوص
  // المحركية هنا على ما خُزّن لا على ما قيل، والحاجز الثاني مُشغِّلات
  // القاعدة (تجميد المرحّل نمط F-140)، وكل ترحيل معاملة واحدة أي رفض
  // يتراجع كله بما فيه العدّاد فلا رقم يُحرق بترحيل مرفوض (07 §1.9).
  // والتجميع **بلا قيد محاسبي** (F-211): نقل قيمة بين أصناف داخل 113
  // — قيمة الناتج الداخل مجموع قيم المكونات الخارجة حصراً فيثبت
  // الثابت F-178 حرفاً — بروح النقل بين المستودعات (بلا حاجز فترة:
  // الأرصدة حالية لا تاريخية — D-185/س78).

  /// معاينة مستند تجميع — قراءة خالصة لا كتابة (نمط المعاينة هي
  /// التنفيذ D-183 والفرق الحي D-106): أسطر المكونات المطلوبة بالوصفة
  /// × العدد ومتاحها وقيمتها التقديرية بالمتوسط الحاكم لحظة النداء،
  /// وأخطاء الصلاحية والاكتفاء كاملةً فما يُرى هو ما سينفذ حرفاً.
  Future<AssemblyPreviewResult> assemblyPreview({
    required String dateText,
    required int warehouseId,
    required int bundleItemId,
    required int qtyBundles,
    int? unitLevelId,
    int? qtyDoc,
    int? factorAtEntry,
  }) async {
    final draft = AssemblyDraft(
      dateText: dateText,
      warehouseId: warehouseId,
      bundleItemId: bundleItemId,
      qtyBundles: qtyBundles,
      unitLevelId: unitLevelId,
      qtyDoc: qtyDoc,
      factorAtEntry: factorAtEntry,
    );
    final structural = validateAssemblyStructure(draft);
    if (structural.isNotEmpty) {
      return AssemblyPreviewResult(
        bundleLabel: null,
        totalValueMinor: 0,
        lines: const [],
        errors: structural,
      );
    }
    final errors = <AssemblyValidationError>[];
    final lines = <AssemblyPreviewLine>[];
    String? bundleLabel;
    var totalValue = 0;
    final warehouse = await _warehouseByIdTx(warehouseId);
    if (warehouse == null) {
      errors.add(AssemblyWarehouseMissing(warehouseId));
    } else if (!warehouse.isActive) {
      errors.add(AssemblyWarehouseInactive(warehouse.name));
    }
    final bundle = await _itemByIdTx(bundleItemId);
    if (bundle == null) {
      errors.add(AssemblyBundleItemMissing(bundleItemId));
    } else {
      bundleLabel =
          itemDisplayLabel(bundle['name'] as String, bundle['sku'] as String);
      if ((bundle['is_active'] as int) == 0) {
        errors.add(AssemblyBundleItemInactive(bundleLabel));
      } else if ((bundle['kind'] as String) != 'bundle') {
        errors.add(AssemblyBundleItemNotBundle(bundleLabel));
      } else {
        // س115: حرس مستوى الناتج بالمعاينة أيضاً — المعاينة هي
        // التنفيذ (D-183) فما يُرى من الأخطاء هو ما سيرفض بالترحيل.
        final levelError = await _assemblyLevelErrorTx(draft, bundle);
        if (levelError != null) {
          errors.add(levelError);
        }
      }
    }
    if (errors.isEmpty) {
      final recipe = await _bundleRecipeTx(bundleItemId);
      if (recipe.isEmpty) {
        errors.add(const AssemblyRecipeRequired());
      }
      for (var i = 0; i < recipe.length; i++) {
        final r = recipe[i];
        final compId = r['component_item_id'] as int;
        final kind = r['kind'] as String;
        final label =
            itemDisplayLabel(r['name'] as String, r['sku'] as String);
        if ((r['is_active'] as int) == 0) {
          errors.add(AssemblyComponentInactive(i, label));
          continue;
        }
        if (kind == 'bundle') {
          errors.add(AssemblyComponentIsBundle(i, label));
          continue;
        }
        if (kind == 'service') {
          // F-212/F-211 — الحد الصادق: المكوّن الخدمي لا يُسحب في
          // التجميع (لا مخزون له ولا قيمة داخل 113 — قيمته من صميم
          // البيع لا البناء) فيظهر بالمعاينة عِلمَه بلا قيمة ولا طلب.
          lines.add(AssemblyPreviewLine(
            itemId: compId,
            label: label,
            isService: true,
            qtyNeeded: 0,
            qtyAvailable: 0,
            valueMinor: 0,
          ));
          continue;
        }
        final needed = (r['qty_base'] as int) * qtyBundles;
        final (qty, value) = await _stockBalanceTx(compId, warehouseId);
        final estimate = wacExitValue(value, qty, needed);
        lines.add(AssemblyPreviewLine(
          itemId: compId,
          label: label,
          isService: false,
          qtyNeeded: needed,
          qtyAvailable: qty,
          valueMinor: estimate,
        ));
        totalValue += estimate;
        if (needed > qty) {
          errors.add(AssemblyComponentInsufficient(
            index: i,
            componentLabel: label,
            neededQty: needed,
            onHandQty: qty,
          ));
        }
      }
    }
    return AssemblyPreviewResult(
      bundleLabel: bundleLabel,
      totalValueMinor: totalValue,
      lines: lines,
      errors: errors,
    );
  }

  /// ترحيل مستند التجميع (F-211) — بلا مسودة (نمط س-18): المكونات
  /// تُسحب من رصيد المستودع بكميات الوصفة × العدد بالمتوسط الحاكم
  /// بالامتصاص (F-047/D-067) بحماية السالب (F-042)، والناتج يدخل
  /// جاهزاً بقيمة مكوناته المسحوبة حصراً — **بلا قيد محاسبي** فمجموع
  /// قيمة 113 ثابت قبل وبعد (الثابت F-178، بروح النقل D-185)، والرقم
  /// من التسلسل السنوي المستقل داخل المعاملة ذاتها (07 §1.9).
  Future<int> assemblyPost(AssemblyDraft draft) async {
    final structural = validateAssemblyStructure(draft);
    if (structural.isNotEmpty) {
      throw AssemblyValidationException(structural);
    }
    return transaction(() async {
      final errors = await _collectAssemblyErrors(draft);
      if (errors.isNotEmpty) {
        throw AssemblyValidationException(errors);
      }
      final recipe = await _bundleRecipeTx(draft.bundleItemId);
      final now = DateTime.now().millisecondsSinceEpoch;
      // خطة الخروج أولاً بقراءات الآنية — قيمة الناتج مجموع الخارج
      // حصراً فالرأس يُزرع بقيَمته النهائية (الرأس مجمّد لا يُحدَّث —
      // نمط F-140) والمكوّن الواحد سطراً واحداً بتفرد الوصفة.
      final exits = <(int, int, int)>[]; // (componentItemId, needed, exit)
      var totalValue = 0;
      for (final r in recipe) {
        if ((r['kind'] as String) == 'service') {
          // F-212/F-211 — الحد الصادق: الخدمة بلا مخزون ولا قيمة
          // بنائية (عِلمَها بالمعاينة) — لا سطر ولا حركة ولا قيمة.
          continue;
        }
        final compId = r['component_item_id'] as int;
        final needed = (r['qty_base'] as int) * draft.qtyBundles;
        final (qty, value) =
            await _stockBalanceTx(compId, draft.warehouseId);
        final exit = wacExitValue(value, qty, needed);
        exits.add((compId, needed, exit));
        totalValue += exit;
      }
      final year = yearOfIsoDate(draft.dateText);
      final number = formatDocumentNumber(
          year,
          await _advanceSequenceWithinTx('assembly', year),
          counterWidth: await _counterWidth());
      await customStatement(
        "INSERT INTO assemblies (number, assembly_date, warehouse_id, "
        "bundle_item_id, qty_base, unit_level_id, qty_doc, factor_at_entry, "
        "total_value_minor, state, uuid, "
        "created_at, updated_at, is_deleted) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?, 0)",
        [
          number,
          draft.dateText,
          draft.warehouseId,
          draft.bundleItemId,
          draft.qtyBundles,
          draft.unitLevelId,
          draft.qtyDoc,
          draft.factorAtEntry,
          totalValue,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      final docId = (await customSelect(
        'SELECT last_insert_rowid() AS id',
      ).getSingle()).data['id'] as int;
      for (final (compId, needed, exit) in exits) {
        final unitCost =
            needed > 0 ? roundHalfAwayFromZeroRatio(exit, needed) : 0;
        await customStatement(
          'INSERT INTO assembly_lines (assembly_id, item_id, qty_base, '
          'unit_cost_base_minor, value_base_minor, uuid, created_at, '
          'updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
          [
            docId,
            compId,
            needed,
            unitCost,
            exit,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        await customStatement(
          "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
          "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
          "ref_doc_type, ref_doc_id, uuid, created_at, updated_at, "
          "is_deleted) VALUES (?, ?, ?, NULL, ?, ?, 'posted', "
          "'assembly', ?, ?, ?, ?, 0)",
          [
            compId,
            -needed,
            draft.warehouseId,
            -exit,
            unitCost,
            docId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
        await customStatement(
          'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
          'total_value_minor, uuid, created_at, updated_at, is_deleted) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
          'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
          'qty_base = qty_base + excluded.qty_base, '
          'total_value_minor = total_value_minor + excluded.total_value_minor, '
          'updated_at = excluded.updated_at',
          [
            compId,
            draft.warehouseId,
            -needed,
            -exit,
            const Uuid().v4(),
            now,
            now,
          ],
        );
      }
      // الناتج يدخل جاهزاً بقيمة مكوناته المسحوبة حصراً — حتى بقيمة
      // صفرية (مكونات بلا مرجع تكلفة روح D-186) فالكمية تدخل ولا
      // القيمة، وفي الحالتين يثبت مجموع 113 (F-178).
      final bundleUnitCost = draft.qtyBundles > 0
          ? roundHalfAwayFromZeroRatio(totalValue, draft.qtyBundles)
          : 0;
      await customStatement(
        "INSERT INTO stock_moves (item_id, qty_base, from_warehouse_id, "
        "to_warehouse_id, value_base_minor, unit_cost_base_minor, state, "
        "ref_doc_type, ref_doc_id, uuid, created_at, updated_at, "
        "is_deleted) VALUES (?, ?, NULL, ?, ?, ?, 'posted', "
        "'assembly', ?, ?, ?, ?, 0)",
        [
          draft.bundleItemId,
          draft.qtyBundles,
          draft.warehouseId,
          totalValue,
          bundleUnitCost,
          docId,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      await customStatement(
        'INSERT INTO stock_balances (item_id, warehouse_id, qty_base, '
        'total_value_minor, uuid, created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
        'ON CONFLICT(item_id, warehouse_id) DO UPDATE SET '
        'qty_base = qty_base + excluded.qty_base, '
        'total_value_minor = total_value_minor + excluded.total_value_minor, '
        'updated_at = excluded.updated_at',
        [
          draft.bundleItemId,
          draft.warehouseId,
          draft.qtyBundles,
          totalValue,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      await _recordDocEventTx(
        entityType: 'assembly',
        table: 'assemblies',
        entityId: docId,
        action: 'posted',
      );
      return docId;
    });
  }

  /// فحوص التجميع بقاعدة البيانات — المستودع موجود نشط، والصنف
  /// التجميعي موجود نشطاً تجميعياً صاحب وصفة، ومكونات الوصفة صالحة
  /// (نشطة بضاعة أو خدمة — لا تداخل تجميعي)، ومكونات البضاعة كافية
  /// (منع السالب F-042) على ما خُزّن لا على ما قيل.
  Future<List<AssemblyValidationError>> _collectAssemblyErrors(
      AssemblyDraft draft) async {
    final errors = <AssemblyValidationError>[];
    final warehouse = await _warehouseByIdTx(draft.warehouseId);
    if (warehouse == null) {
      errors.add(AssemblyWarehouseMissing(draft.warehouseId));
    } else if (!warehouse.isActive) {
      errors.add(AssemblyWarehouseInactive(warehouse.name));
    }
    final bundle = await _itemByIdTx(draft.bundleItemId);
    if (bundle == null) {
      errors.add(AssemblyBundleItemMissing(draft.bundleItemId));
      return errors;
    }
    final bundleLabel =
        itemDisplayLabel(bundle['name'] as String, bundle['sku'] as String);
    if ((bundle['is_active'] as int) == 0) {
      errors.add(AssemblyBundleItemInactive(bundleLabel));
      return errors;
    }
    if ((bundle['kind'] as String) != 'bundle') {
      errors.add(AssemblyBundleItemNotBundle(bundleLabel));
      return errors;
    }
    // س115: حرس مستوى الناتج بالتعبئة (نمط الفواتير س89 والإذنين
    // والتحويل س113) — المستوى من مجموعة التجميعي حصراً وعاملُه
    // يطابق العدد المدخل بالمخزونية، والمخالف مرفوض بلا كتابة —
    // والوصفة بالأساسية نص F-211 ثابت لا مساس بها.
    final levelError = await _assemblyLevelErrorTx(draft, bundle);
    if (levelError != null) {
      errors.add(levelError);
      return errors;
    }
    final recipe = await _bundleRecipeTx(draft.bundleItemId);
    if (recipe.isEmpty) {
      errors.add(const AssemblyRecipeRequired());
      return errors;
    }
    for (var i = 0; i < recipe.length; i++) {
      final r = recipe[i];
      final kind = r['kind'] as String;
      final label =
          itemDisplayLabel(r['name'] as String, r['sku'] as String);
      if ((r['is_active'] as int) == 0) {
        errors.add(AssemblyComponentInactive(i, label));
        continue;
      }
      if (kind == 'bundle') {
        errors.add(AssemblyComponentIsBundle(i, label));
        continue;
      }
      if (kind == 'service') continue; // F-212 — بلا مخزون ولا قيمة
      final needed = (r['qty_base'] as int) * draft.qtyBundles;
      final (qty, _) = await _stockBalanceTx(
          r['component_item_id'] as int, draft.warehouseId);
      if (needed > qty) {
        errors.add(AssemblyComponentInsufficient(
          index: i,
          componentLabel: label,
          neededQty: needed,
          onHandQty: qty,
        ));
      }
    }
    return errors;
  }

  /// س115: فحص لقطة الناتج بالتعبئة — المستوى من مجموعة التجميعي
  /// حصراً وعاملُه ≥2 والعدد بالمخزونية يساوي المدخل × العامل
  /// (نمط حرس الفواتير س89). NULL = صالحة، وإلا خطأها الجاهز.
  Future<AssemblyValidationError?> _assemblyLevelErrorTx(
      AssemblyDraft draft, Map<String, Object?> bundle) async {
    final levelId = draft.unitLevelId;
    if (levelId == null) return null;
    final groupId = bundle['unit_group_id'] as int?;
    var levelValid = false;
    var levelFactor = 0;
    if (groupId != null) {
      final levelRows = await customSelect(
        'SELECT group_id, factor FROM unit_group_levels '
        'WHERE id = ? AND is_deleted = 0',
        variables: [Variable.withInt(levelId)],
      ).get();
      if (levelRows.isNotEmpty &&
          levelRows.first.data['group_id'] as int == groupId) {
        levelFactor = levelRows.first.data['factor'] as int;
        levelValid = levelFactor >= 2;
      }
    }
    final qtyDoc = draft.qtyDoc ?? 0;
    final factor = draft.factorAtEntry ?? 0;
    if (!levelValid ||
        qtyDoc <= 0 ||
        factor != levelFactor ||
        draft.qtyBundles != qtyDoc * factor) {
      return AssemblyLevelInvalid(itemDisplayLabel(
          bundle['name'] as String, bundle['sku'] as String));
    }
    return null;
  }

  /// سجل التجميعات — الأحدث أولاً برأسه بأسمائه المحسوبة ومجاميعه
  /// (قراءة عرض خالصة — التخزين يقرأ لا يحسب، نمط قراءة الإذنين)
  /// وبلقطة الناتج بالتعبئة س115 للعرض («2 (بالمستوى) = 24»).
  Future<List<AssemblyListRow>> assembliesOf() async {
    final rows = await customSelect(
      'SELECT a.id, a.number, a.assembly_date, a.state, a.qty_base, '
      'a.unit_level_id, a.qty_doc, a.factor_at_entry, '
      'a.total_value_minor, a.warehouse_id, w.name AS warehouse_name, '
      'a.bundle_item_id, i.name AS bundle_name, i.sku AS bundle_sku, '
      'COUNT(l.id) AS line_count '
      'FROM assemblies a '
      'LEFT JOIN warehouses w ON w.id = a.warehouse_id '
      'LEFT JOIN items i ON i.id = a.bundle_item_id '
      'LEFT JOIN assembly_lines l ON l.assembly_id = a.id '
      'AND l.is_deleted = 0 '
      'WHERE a.is_deleted = 0 '
      'GROUP BY a.id ORDER BY a.id DESC',
    ).get();
    return [
      for (final r in rows)
        AssemblyListRow(
          id: r.data['id'] as int,
          number: r.data['number'] as String,
          assemblyDate: r.data['assembly_date'] as String,
          state: r.data['state'] as String,
          qtyBase: r.data['qty_base'] as int,
          unitLevelId: r.data['unit_level_id'] as int?,
          qtyDoc: r.data['qty_doc'] as int?,
          factorAtEntry: r.data['factor_at_entry'] as int?,
          totalValueMinor: r.data['total_value_minor'] as int,
          warehouseId: r.data['warehouse_id'] as int,
          warehouseName: r.data['warehouse_name'] as String?,
          bundleItemId: r.data['bundle_item_id'] as int,
          bundleName: r.data['bundle_name'] as String?,
          bundleSku: r.data['bundle_sku'] as String?,
          lineCount: r.data['line_count'] as int,
        ),
    ];
  }

  /// أسطر تجميع معين — لقطة الكلفة المخزنة (F-140) قراءة خالصة.
  Future<List<AssemblyLineRow>> assemblyLinesOf(int assemblyId) async {
    final rows = await customSelect(
      'SELECT l.item_id, l.qty_base, l.unit_cost_base_minor, '
      'l.value_base_minor, i.name, i.sku '
      'FROM assembly_lines l JOIN items i ON i.id = l.item_id '
      'WHERE l.assembly_id = ? AND l.is_deleted = 0 ORDER BY l.id',
      variables: [Variable.withInt(assemblyId)],
    ).get();
    return [
      for (final r in rows)
        AssemblyLineRow(
          itemId: r.data['item_id'] as int,
          itemName: r.data['name'] as String?,
          sku: r.data['sku'] as String?,
          qtyBase: r.data['qty_base'] as int,
          unitCostBaseMinor: r.data['unit_cost_base_minor'] as int,
          valueBaseMinor: r.data['value_base_minor'] as int,
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

    /// س236 (د10 — النوع الجارٍ): 'cash' نقدي افتراضاً و'bank' جارٍ
    /// بنكي (ومعه اسم البنك ورقم الحساب — بيتان بيانيان للصندوق
    /// البنكي لا حقول إلزام فالاسم يكفي، والرقم لاحقاً).
    String kind = 'cash',
    String? bankName,
    String? accountNumber,
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
    if (kind != 'cash' && kind != 'bank') {
      throw StateError('نوع صندوق غير معروف: $kind');
    }
    return transaction(() => _createCashBoxWithinTx(
        name: trimmed,
        currencyId: currencyId,
        kind: kind,
        bankName: bankName?.trim(),
        accountNumber: accountNumber?.trim()));
  }

  /// س141 (الوحدة 5 — 05 §3.3): الشطر الداخلي لإنشاء الصندوق — حساب
  /// ورقي آلي تحت 111 (F-199) وصندوقه بعملته الواحدة؛ يستدعى داخل
  /// معاملة قائمة حصراً: استيراد الأرصدة الكاملة يفتح صناديق عملاته
  /// النقد بمعاملته الواحدة فلا مسار ثاني ولا صندوق بلا قيده.
  Future<int> _createCashBoxWithinTx({
    required String name,
    required int currencyId,
    String kind = 'cash',
    String? bankName,
    String? accountNumber,
  }) async {
    final trimmed = name.trim();
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
      'INSERT INTO cash_boxes (name, currency_id, account_id, kind, '
      'bank_name, account_number, opening_balance_base_minor, uuid, '
      'created_at, updated_at, is_deleted) '
      "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 0)",
      [
        trimmed,
        currencyId,
        accountId,
        kind,
        kind == 'bank' ? (bankName == null || bankName.isEmpty ? null : bankName) : null,
        kind == 'bank' ? (accountNumber == null || accountNumber.isEmpty ? null : accountNumber) : null,
        const Uuid().v4(),
        now,
        now,
      ],
    );
    return (await customSelect('SELECT last_insert_rowid() AS id')
            .getSingle())
        .data['id'] as int;
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
          await _advanceSequenceWithinTx(voucherSequenceKind(draft.kind), year),
          counterWidth: await _counterWidth());
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
          payload: await sealLogText(snapshot),
          uuid: const Uuid().v4(),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // س104: القبض المعلق بحساب الطريق — كلمة المالك: «ابدأ بدفعة المندوب
  // 3» (التحصيلات المعلقة بالحساب الوسيط «تحصيلات في الطريق» وبعهدة
  // المندوب). آلة الحالات: draft (مسودة عادية بمسارها) ← held (معلّق:
  // قيدُ الطريق مقيد وتصفو ذمة الطرف ولا صندوق ولا رقم) ← posted
  // (باعتماد صاحب الصلاحية: قيدُ الصندوق وحركة النقد والرقم) أو
  // rejected (بالرفض: قيدُ عكسٍ حرف لقيد الطريق فتعود ذمة الطرف).
  // ═══════════════════════════════════════════════════════════════

  /// حفظ تحصيل معلق بهوية المانِح — معاملة واحدة: القبض الطرفي حصراً،
  /// وفحوص الترحيل كاملة (فترة مفتوحة وصندوق نشط بعملته ومطابقات فواتير
  /// مرحّلة مفتوحة)، وقيدُ الطريق (مدين 116 / دائن 112 بالمطابقات
  /// بلقطاتها والفائض رصيداً مقدّماً وفرق اللقطات 44/55 بعرف الترحيل)
  /// يُقيد لحظة الحفظ فتصفو ذمة الطرف بوقوع القبض لا بوقوع التسليم.
  /// وترتيب المعاملة حاكم (درس المشغلات): السند يُبذر مسودةً ثم مطابقاته
  /// ثم قيد الطريق ومكافئات المطابقة كلها بحالة draft (حاجز «مطابقات
  /// المرحّل لا تضاف» حارسٌ حقيقي) ثم يُقلب إلى held آخراً — والتغطية
  /// أثناء الحساب تستثني المسودة ذاتها فلا يحجز تحصيلُه حجزَه (نمط
  /// postVoucher بعينه)، واشتقاق حالات الفواتير بعد القلب فيشمل التغطية
  /// المعلق. والرقم لا يُمنح إلا بالاعتماد (07 §1.9)، وحدثا created
  /// وsubmitted_for_approval بهوية المانِح (عرف س101).
  Future<int> createHeldVoucher(
    VoucherDraft draft, {
    required int userId,
    required String userName,
    required String roleName,
  }) async {
    if (!draft.kind.isReceipt) {
      throw VoucherValidationException(
          [VoucherHoldKindInvalid(draft.kind.label)]);
    }
    if (draft.partyId == null) {
      throw const VoucherValidationException([VoucherHoldRequiresParty()]);
    }
    return transaction(() async {
      final errors = await _collectVoucherErrors(draft, forPosting: true);
      if (errors.isNotEmpty) {
        throw VoucherValidationException(errors);
      }
      // س105: سقف العهدة — عهدة المانِح الحالية زائد القبض الجديد
      // (بالوحدات الصغرى من العملة الأساسية) لا تجاوز السقف إن كان
      // مفروضاً، فرُفضٌ بلسانه قبل أي كتابة (بوابة المحرك ذاتها لا
      // الواجهة — نمط كل بوابات التخزين)، والقراءة بهوية المانِح من
      // حدث تقديمه (عرف العهدة المحسوبة س104).
      final cap = await heldReceiptCustodyCap();
      if (cap > 0) {
        final custody = await heldCustodyTotalOf(userId);
        final incoming =
            convertToBaseMinor(draft.amountDocMinor, draft.fxRate);
        if (custody + incoming > cap) {
          throw VoucherValidationException([
            VoucherCustodyCapExceeded(
              custodyBaseMinor: custody,
              capBaseMinor: cap,
              incomingBaseMinor: incoming,
            ),
          ]);
        }
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

      // قيد الطريق — مرآة أرجل الترحيل الطرفي (postVoucher) والحساب
      // الوسيط 116 محل حساب الصندوق: ما بيدي المندوب الآن لا ما بالصندوق.
      final allocRows = await _voucherAllocationsTx(voucherId);
      final journalId = await _journalIdByCodeTx('cash');
      final acc112 = await _accountIdByCodeTx('112');
      final accTransit = await _accountIdByCodeTx(transitAccountCode);
      final acc44 = await _accountIdByCodeTx('44');
      final acc55 = await _accountIdByCodeTx('55');
      final totalDoc = draft.amountDocMinor;
      final totalBase = convertToBaseMinor(totalDoc, draft.fxRate);
      final invCache = <int, InvoiceDocument>{};
      final allocations = [
        for (final r in allocRows)
          (
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
        baseByAllocationRow[a.invoiceId] = base;
        allocatedDocTotal += a.appliedDocMinor;
        allocatedBaseTotal += base;
      }
      final advanceDoc = totalDoc - allocatedDocTotal;
      final advanceBase = convertToBaseMinor(advanceDoc, draft.fxRate);
      final fxDiff = totalBase - allocatedBaseTotal - advanceBase;
      final docCur = draft.currencyId;
      final lines = <MoveLineDraft>[
        MoveLineDraft(
          accountId: accTransit,
          debitMinor: totalBase,
          currencyId: docCur,
          amountMinor: totalDoc,
          fxRate: draft.fxRate,
        ),
        for (final a in allocations)
          MoveLineDraft(
            accountId: acc112,
            creditMinor: baseByAllocationRow[a.invoiceId]!,
            partyId: draft.partyId,
            currencyId: invCache[a.invoiceId]!.currencyId,
            amountMinor: a.appliedDocMinor,
            fxRate: invCache[a.invoiceId]!.fxRate,
          ),
        if (advanceDoc > 0)
          MoveLineDraft(
            accountId: acc112,
            creditMinor: advanceBase,
            partyId: draft.partyId,
            currencyId: docCur,
            amountMinor: advanceDoc,
            fxRate: draft.fxRate,
          ),
        if (fxDiff > 0)
          MoveLineDraft(
              accountId: acc44,
              creditMinor: fxDiff,
              currencyId: 1,
              amountMinor: fxDiff)
        else if (fxDiff < 0)
          MoveLineDraft(
              accountId: acc55,
              debitMinor: -fxDiff,
              currencyId: 1,
              amountMinor: -fxDiff),
      ];
      final transitMoveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: draft.dateText,
        narration: draft.narration == null || draft.narration!.isEmpty
            ? 'تحصيل معلق — بانتظار الاعتماد والتسليم'
            : 'تحصيل معلق — ${draft.narration}',
        refDocType: 'voucher',
        refDocId: voucherId,
        lines: lines,
      ));
      await _postMoveWithinTx(transitMoveId, sequenceKind: 'move_cash');

      // مكافئات صفوف المطابقة تُكتب قبل قلب الحالة (نمط الترحيل — والترتيب
      // جزء من الصحة) فتكتمل تغطية المعلق لمن يأتي بعده.
      for (final a in allocations) {
        await customStatement(
          'UPDATE voucher_allocations SET applied_base_minor = ?, '
          'updated_at = ? WHERE voucher_id = ? AND invoice_id = ?',
          [baseByAllocationRow[a.invoiceId]!, now, voucherId, a.invoiceId],
        );
      }

      // قلب الحالة آخر الخطوات الكتابية — بعد المطابقات والقيد والمكافئات
      // (حاجز «مطابقات المرحّل» حارس حقيقي فالبذر بحالة draft حصراً).
      await customStatement(
        "UPDATE vouchers SET state = 'held', move_id = ?, updated_at = ? "
        'WHERE id = ?',
        [transitMoveId, now, voucherId],
      );

      // اشتقاق حالات الفواتير المُطابَقة — التغطية تشمل المعلق الآن فتصفو
      // الذمة بوقوع القبض (عرف الترحيل ذاته — F-063/D-084).
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

      await _recordVoucherEventTx(voucherId: voucherId, action: 'created');
      // حدث التقديم بهوية المانِح — عرف س101 حرفاً: الحدث تدقيقٌ لا شرط
      // اعتماد (المحرك يتحقق بحالة السند)، وموضعه داخل المعاملة فلا
      // معلَّق بلا تقديمه.
      await into(events).insert(
        EventsCompanion.insert(
          eventAt: now,
          deviceId: await deviceId(),
          entityType: 'voucher',
          entityId: Value(voucherId),
          userId: Value(userId),
          action: 'submitted_for_approval',
          payload: await sealLogText(jsonEncode(<String, Object?>{
            'by_user_id': userId,
            'by_user_name': userName,
            'by_role_name': roleName,
          })),
          uuid: const Uuid().v4(),
        ),
      );
      return voucherId;
    });
  }

  /// اعتماد التحصيل المعلق وتسليمه للصندوق — معاملة واحدة على المعلق
  /// حصراً (VoucherStateNotHeld برسالة المدقق): فحوص الصندوق والفترة
  /// مركزة (المطابقات لا تُعاد فحصاً — حجزها بالتغطية باقٍ والفواتير
  /// صارت مدفوعة/جزئية بالتعليق ففحصُها الكامل يكذب)، ثم قيدُ الصندوق
  /// (مدين حساب الصندوق / دائن 116) وحركة النقد «داخل» والرقم من تسلسل
  /// نوعه لحظة الاعتماد (07 §1.9) وتحديث move_id بقيد الصندوق — وقيدُ
  /// الطريق السابق باقٍ بمرجعيته (moves.ref_doc_type/ref_doc_id) جزء
  /// القصة المحاسبية، وحدث posted بلقطة السند.
  Future<int> approveHeldVoucher(int voucherId) async {
    return transaction(() async {
      final v = await _voucherRowTx(voucherId);
      if (v == null) {
        throw StateError('لا سند بالمعرف $voucherId');
      }
      if (v['state'] != 'held') {
        throw VoucherValidationException(
            [VoucherStateNotHeld(v['state'] as String)]);
      }
      final kind = VoucherKind.fromStorage(v['kind'] as String);
      final dateText = v['voucher_date'] as String;
      final currencyId = v['currency_id'] as int;
      final fxRate = v['fx_rate'] as int;
      final totalDoc = v['amount_doc_minor'] as int;
      final totalBase = v['amount_base_minor'] as int;
      final boxId = v['cash_box_id'] as int;
      // فحوص التسليم المركزة — بنفس رسائل المدقق (نمط _collectVoucherErrors
      // بعينها بلا مطابقات).
      final errors = <VoucherValidationError>[];
      final period = findPeriodForDate(await ledgerPeriods(), dateText);
      if (period == null) {
        errors.add(VoucherNoPeriod(dateText));
      } else if (!period.isOpen) {
        errors.add(VoucherClosedPeriod(dateText));
      }
      final box = await _cashBoxByIdTx(boxId);
      if (box == null) {
        errors.add(const VoucherBoxMissing());
      } else {
        if (!await _accountActiveTx(box.accountId)) {
          errors.add(VoucherBoxInactive('${box.name} (حساب الصندوق)'));
        }
        if (box.currencyId != currencyId) {
          errors.add(const VoucherBoxCurrencyMismatch());
        }
      }
      if (errors.isNotEmpty) {
        throw VoucherValidationException(errors);
      }
      // الصندوق مقرَّر بعد سقوط الأخطاء — والتحليل النقي يطلب التصريح
      // (نمط postVoucher: (!) بعد الفحص).
      final resolvedBox = box!;
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(dateText);
      final voucherNumber = formatDocumentNumber(
          year,
          await _advanceSequenceWithinTx(voucherSequenceKind(kind), year),
          counterWidth: await _counterWidth());
      final journalId = await _journalIdByCodeTx('cash');
      final accTransit = await _accountIdByCodeTx(transitAccountCode);
      final approvalMoveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: dateText,
        narration: 'اعتماد تحصيل معلق وتسليمه للصندوق',
        refDocType: 'voucher',
        refDocId: voucherId,
        lines: [
          MoveLineDraft(
            accountId: resolvedBox.accountId,
            debitMinor: totalBase,
            currencyId: currencyId,
            amountMinor: totalDoc,
            fxRate: fxRate,
          ),
          MoveLineDraft(
            accountId: accTransit,
            creditMinor: totalBase,
            currencyId: currencyId,
            amountMinor: totalDoc,
            fxRate: fxRate,
          ),
        ],
      ));
      await _postMoveWithinTx(approvalMoveId, sequenceKind: 'move_cash');
      // حركة الصندوق بمصدرها المعلن — النقد دخل فعلاً الآن (05 §4.2/D-105).
      await customStatement(
        "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
        "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, user_id, "
        "uuid, created_at, updated_at, is_deleted) "
        "VALUES (?, 'in', ?, ?, ?, 'voucher', ?, NULL, ?, ?, ?, 0)",
        [
          resolvedBox.id,
          totalDoc,
          totalBase,
          fxRate,
          voucherId,
          const Uuid().v4(),
          now,
          now,
        ],
      );
      await customStatement(
        "UPDATE vouchers SET state = 'posted', number = ?, move_id = ?, "
        'updated_at = ? WHERE id = ?',
        [voucherNumber, approvalMoveId, now, voucherId],
      );
      await _recordVoucherEventTx(voucherId: voucherId, action: 'posted');
      return voucherId;
    });
  }

  /// رفض التحصيل المعلق — عكسٌ حرف لقيد الطريق (كل سطر يُقلب مديناً
  /// دائناً بعينه فتعود ذمة الطرف بما قُيّد عليها ويعود ميزان 116
  /// صفراً لهذا التحصيل) وحالة rejected واضحةً بالتدقيق لا محذوفة
  /// (حاجز «المرحّل لا يحذف» يمنع حذف كل غير مسودة والمرفض منها)،
  /// وحالات الفواتير تُشتق من جديد بالتغطية (المرفض خارجها فتبقى
  /// الذمة كما كانت قبل التعليق)، وحدث rejected بهوية الرافع والسبب.
  Future<void> rejectHeldVoucher(
    int voucherId, {
    required int userId,
    required String userName,
    required String roleName,
    String? reason,
  }) async {
    return transaction(() async {
      final v = await _voucherRowTx(voucherId);
      if (v == null) {
        throw StateError('لا سند بالمعرف $voucherId');
      }
      if (v['state'] != 'held') {
        throw VoucherValidationException(
            [VoucherStateNotHeld(v['state'] as String)]);
      }
      final transitMoveId = v['move_id'] as int?;
      if (transitMoveId == null) {
        throw StateError(
            'التحصيل المعلق بلا قيد طريق — حالة فاسدة تُرفض صادقاً');
      }
      final moveRows = await customSelect(
        'SELECT account_id, party_id, debit_minor, credit_minor, '
        'currency_id, amount_minor, fx_rate, ref_stock_move_id '
        'FROM move_lines WHERE move_id = ? ORDER BY id',
        variables: [Variable.withInt(transitMoveId)],
      ).get();
      final dateText = v['voucher_date'] as String;
      final journalId = await _journalIdByCodeTx('cash');
      final lines = <MoveLineDraft>[
        for (final r in moveRows)
          MoveLineDraft(
            accountId: r.data['account_id'] as int,
            partyId: r.data['party_id'] as int?,
            debitMinor: r.data['credit_minor'] as int,
            creditMinor: r.data['debit_minor'] as int,
            currencyId: r.data['currency_id'] as int?,
            amountMinor: r.data['amount_minor'] as int?,
            fxRate: r.data['fx_rate'] as int?,
            refStockMoveId: r.data['ref_stock_move_id'] as int?,
          ),
      ];
      final reversalId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: dateText,
        narration: reason == null || reason.trim().isEmpty
            ? 'عكس تحصيل معلق — رفض الاعتماد'
            : 'عكس تحصيل معلق — رفض الاعتماد: ${reason.trim()}',
        refDocType: 'voucher',
        refDocId: voucherId,
        lines: lines,
      ));
      await _postMoveWithinTx(reversalId, sequenceKind: 'move_cash');
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "UPDATE vouchers SET state = 'rejected', updated_at = ? WHERE id = ?",
        [now, voucherId],
      );
      // اشتقاق حالات الفواتير من جديد — المرفض خارج التغطية فتعود الذمة
      // بما كانت عليه قبل التعليق (posted إن خلت تماماً وجزئية إن بقي
      // منها ومدفوعة إن غير هذا التحصيل غطاها).
      final allocRows = await _voucherAllocationsTx(voucherId);
      final invIds = [
        for (final r in allocRows) r['invoice_id'] as int,
      ];
      for (final iid in invIds.toSet()) {
        final inv = await _invoiceRowTx(iid);
        if (inv == null) continue;
        final covered = await _coveredDocSingleTx(iid);
        final String newState;
        if (covered <= 0) {
          newState = 'posted';
        } else if (covered >= inv.totalDocMinor) {
          newState = 'paid';
        } else {
          newState = 'partially_paid';
        }
        await customStatement(
          'UPDATE invoices SET state = ?, updated_at = ? WHERE id = ?',
          [newState, now, iid],
        );
      }
      await into(events).insert(
        EventsCompanion.insert(
          eventAt: now,
          deviceId: await deviceId(),
          entityType: 'voucher',
          entityId: Value(voucherId),
          userId: Value(userId),
          action: 'rejected',
          payload: await sealLogText(jsonEncode(<String, Object?>{
            'by_user_id': userId,
            'by_user_name': userName,
            'by_role_name': roleName,
            if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          })),
          uuid: const Uuid().v4(),
        ),
      );
    });
  }

  /// آخر تقديم معلق لسند — من أحداثه بالأحدث فوزاً (عرف invoiceSubmissionOf
  /// س101)، والغائب null (معلَّق بحالة فاسدة بلا تقديم لا يحدث بالمسار
  /// المعتمد — والقراءة الصادقة لا تخترع هوية).
  Future<VoucherSubmissionInfo?> voucherSubmissionOf(int voucherId) async {
    final rows = await customSelect(
      "SELECT user_id, payload, event_at FROM events "
      "WHERE entity_type = 'voucher' AND entity_id = ? "
      "AND action = 'submitted_for_approval' "
      'ORDER BY event_at DESC, id DESC LIMIT 1',
      variables: [Variable.withInt(voucherId)],
    ).get();
    if (rows.isEmpty) return null;
    final r = rows.single;
    final payload =
        jsonDecode(await openLogText(r.data['payload'] as String))
            as Map<String, dynamic>;
    return VoucherSubmissionInfo(
      voucherId: voucherId,
      userId: (payload['by_user_id'] as num).toInt(),
      userName: (payload['by_user_name'] as String?) ?? '',
      roleName: (payload['by_role_name'] as String?) ?? '',
      submittedAtMs: r.data['event_at'] as int,
    );
  }

  /// عهدة المندوبين — تحصيلات القبض المعلقة مجمّعة بهوية مقدمها من حدث
  /// التقديم (قراءة خالصة لا حالة مخزنة — عرف الحجز المحسوب س102): كل
  /// معلّق بلا حدث تقديم (مستحيل بالمسار المعتمد) يجتمع تحت «غير معروف»
  /// صادقاً لا صامتاً، والمجموع العام يساوي ميزان 116 فعلياً. وس105
  /// يلحق كل صف طابعَي أقدم تقديم وأحدثه — لسان أعمار العهدة يصوغه
  /// التطبيق من الطابعين لا من نص مخزن (نمط القلب).
  Future<List<HeldCollectionCustodyRow>> heldReceiptCustody() async {
    final rows = await customSelect(
      "SELECT id, amount_base_minor FROM vouchers "
      "WHERE kind = 'receipt' AND state = 'held' AND is_deleted = 0 "
      'ORDER BY id',
    ).get();
    final byUser = <int, HeldCollectionCustodyRow>{};
    for (final r in rows) {
      final voucherId = r.data['id'] as int;
      final amountBase = r.data['amount_base_minor'] as int;
      final sub = await voucherSubmissionOf(voucherId);
      final key = sub?.userId ?? -1;
      final prev = byUser[key];
      final stamp = sub?.submittedAtMs;
      final prevOldest = prev?.oldestSubmittedAtMs;
      final prevNewest = prev?.newestSubmittedAtMs;
      byUser[key] = HeldCollectionCustodyRow(
        userId: key,
        userName: sub?.userName ?? prev?.userName ?? 'غير معروف',
        roleName: sub?.roleName ?? prev?.roleName ?? '—',
        count: (prev?.count ?? 0) + 1,
        totalBaseMinor: (prev?.totalBaseMinor ?? 0) + amountBase,
        oldestSubmittedAtMs: stamp == null
            ? prevOldest
            : (prevOldest == null || stamp < prevOldest ? stamp : prevOldest),
        newestSubmittedAtMs: stamp == null
            ? prevNewest
            : (prevNewest == null || stamp > prevNewest ? stamp : prevNewest),
      );
    }
    return byUser.values.toList();
  }

  /// مدخلات العهدة صفّاً صفّاً (س162 — بقية فكرة المندوب: شرائح الأعمار
  /// بكلمة المالك — التوثيق نص س105 «توزيع الأعمار بشرائح (0-7/8-15/…)»):
  /// كل تحصيل معلق بهوية آخر تقديم له وطابعه، والتوزيع النقي بالتطبيق
  /// (custodyAgeSliceDistribution بالمجال) فلا شرائح مخزنة ولا إعداد —
  /// والغائب (لا حدث تقديم) «غير معروف» صادقاً بنمط heldReceiptCustody
  /// وعمره null فلا شريحة له.
  Future<List<HeldCustodyEntry>> heldReceiptCustodyEntries() async {
    final rows = await customSelect(
      "SELECT id, amount_base_minor FROM vouchers "
      "WHERE kind = 'receipt' AND state = 'held' AND is_deleted = 0 "
      'ORDER BY id',
    ).get();
    final out = <HeldCustodyEntry>[];
    for (final r in rows) {
      final sub = await voucherSubmissionOf(r.data['id'] as int);
      out.add(HeldCustodyEntry(
        voucherId: r.data['id'] as int,
        amountBaseMinor: r.data['amount_base_minor'] as int,
        userId: sub?.userId ?? -1,
        userName: sub?.userName ?? 'غير معروف',
        submittedAtMs: sub?.submittedAtMs,
      ));
    }
    return out;
  }

  /// معرفات السندات التي آخر تقديم لها بهوية المستخدم (س162 — القصر
  /// التفصيلي «تحصيلاتي» بنص س104 «عرض فوق القراءة مؤجل بترتيب المالك»):
  /// لا شرط SQL جديد ولا حالة مخزنة — أحداث التقديم تُقرأ كلها بالأحدث
  /// فوزاً والفكّ بالدارت (الحمولة مختومة بlog_cipher فلا LIKE بالSQL)
  /// وآخر تقديم لكل سند هو هويته عرف voucherSubmissionOf.
  Future<Set<int>> voucherIdsSubmittedBy(int userId) async {
    final rows = await customSelect(
      "SELECT entity_id, payload, event_at, id FROM events "
      "WHERE entity_type = 'voucher' AND action = 'submitted_for_approval' "
      'ORDER BY event_at DESC, id DESC',
    ).get();
    final judged = <int>{};
    final ids = <int>{};
    for (final r in rows) {
      final voucherId = r.data['entity_id'] as int;
      if (judged.contains(voucherId)) continue;
      judged.add(voucherId);
      final payload =
          jsonDecode(await openLogText(r.data['payload'] as String))
              as Map<String, dynamic>;
      if ((payload['by_user_id'] as num).toInt() == userId) {
        ids.add(voucherId);
      }
    }
    return ids;
  }

  /// عهدة مانِح بعينه — مجموع تحصيلاته المعلقة (بالوحدات الصغرى من
  /// العملة الأساسية) بهوية آخر تقديم له: عليها يُفرض سقف العهدة
  /// (س105) عند كل تعليق جديد. ومن لا حدث تقديم له فليس بعهدته شيء
  /// (قراءة صادقة لا صامتة — نمط heldReceiptCustody بعينه).
  Future<int> heldCustodyTotalOf(int userId) async {
    final rows = await customSelect(
      "SELECT id, amount_base_minor FROM vouchers "
      "WHERE kind = 'receipt' AND state = 'held' AND is_deleted = 0 "
      'ORDER BY id',
    ).get();
    var total = 0;
    for (final r in rows) {
      final sub = await voucherSubmissionOf(r.data['id'] as int);
      if (sub?.userId == userId) {
        total += r.data['amount_base_minor'] as int;
      }
    }
    return total;
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
      // أقدمية المطابقات (02 §8: الاستحقاق ثم التاريخ ثم الرقم) — والرقم
      // يُرتب بسنته وعدّاده المستخلصين لا بالنص الخام (D-169): الفترة
      // الانتقالية تعيش صيغتين («2026/000001» القديمة و«26000001» الجديدة)
      // والفرز النصي الخام يقلب الترتيب بينهما لأطوال وفواصل مختلفة.
      // القديمة: السنة قبل المائل والعدّاد بعده؛ الجديدة: رقما السنة
      // ثم العدّاد.
      "ORDER BY COALESCE(due_date, '9999-12-31'), invoice_date, "
      "CASE WHEN number LIKE '%/%' "
      "THEN CAST(substr(number, 1, instr(number, '/') - 1) AS INTEGER) "
      "ELSE 2000 + CAST(substr(number, 1, 2) AS INTEGER) END, "
      "CASE WHEN number LIKE '%/%' "
      "THEN CAST(substr(number, instr(number, '/') + 1) AS INTEGER) "
      "ELSE CAST(substr(number, 3) AS INTEGER) END",
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
          await _advanceSequenceWithinTx('box_transfer', year),
          counterWidth: await _counterWidth());
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
          await _advanceSequenceWithinTx('cash_adjustment', year),
          counterWidth: await _counterWidth());
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

  /// تغطية الفواتير بمطابقات السندات المرحّلة والمعلقة معاً (س104) —
  /// (مطبَّق بعملة الفاتورة، مكافؤه الأساسي) لكل فاتورة من المطلوبة.
  Future<Map<int, (int, int)>> _coverageByInvoiceTx(
      List<int> invoiceIds) async {
    if (invoiceIds.isEmpty) return {};
    final rows = await customSelect(
      'SELECT va.invoice_id AS iid, '
      'COALESCE(SUM(va.applied_doc_minor), 0) AS doc, '
      'COALESCE(SUM(va.applied_base_minor), 0) AS base '
      'FROM voucher_allocations va JOIN vouchers v ON v.id = va.voucher_id '
      // س104: المعلق يحجز ذمة الفاتورة كمثل المرحّل — التحصيل وقع بيد
      // المندوب فلا تُطالَب به ثانية، والرفض يعيدها (حالته rejected خارج
      // القائمتين فلا يُحتسب) — والاعتماد يمرّه مرحّلاً بلا قفزة.
      "WHERE v.state IN ('posted', 'held') AND v.is_deleted = 0 "
      'AND va.is_deleted = 0 '
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
      "WHERE va.invoice_id = ?1 AND v.state IN ('posted', 'held') "
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
        payload: await sealLogText(await _voucherSnapshotTx(voucherId)),
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
        payload: await sealLogText(payload),
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

  /// المغطى لفاتورة واحدة بوحدات المستند — بذرة الاشتقاق والقراءة
  /// (F-063/D-084 معروضان) ممتدة بلفظ المالك (س50/4 «في الخاتمة
  /// تكتب الدفعة والباقي» — س-156/D-154): النقدي المرحّل مسدّد بمجرد
  /// ترحيله (س-03/س-06 «مدفوعة فوراً») ولا مطابقة سند عليه فالمغطى
  /// محصلته إجماليه والباقي صفر بلسان التصنيف نفسه، والمسودة النقدية
  /// لم تتحرك بعد فبالمطابقات، والآجل بالمطابقات حصراً، والغائب صفر
  /// بلا استثناء فلا تُكسر قسيمة عرضية.
  Future<int> invoiceCoveredDocMinor(int invoiceId) async {
    final rows = await customSelect(
      'SELECT cash_box_id, total_doc_minor, state FROM invoices '
      'WHERE id = ?1 AND is_deleted = 0',
      variables: [Variable.withInt(invoiceId)],
    ).get();
    if (rows.isEmpty) return 0;
    final d = rows.first.data;
    final isCash = (d['cash_box_id'] as int?) != null;
    final isDraft = d['state'] == 'draft';
    if (isCash && !isDraft) {
      return d['total_doc_minor'] as int;
    }
    return _coveredDocSingleTx(invoiceId);
  }

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
    // س236 (د10 — التسوية البنكية بنمط تسوية الصندوق حرفاً): برصيدي
    // الكشف والدفتري اللقطة والاتجاه والمبلغ محسوبين من الفرق.
    'CREATE TABLE IF NOT EXISTS "bank_reconciliations" ('
        '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
        '"number" TEXT NOT NULL DEFAULT \'\', '
        '"cash_box_id" INTEGER NOT NULL, '
        '"reconciliation_date" TEXT NOT NULL, '
        '"currency_id" INTEGER NOT NULL DEFAULT 1, '
        '"fx_rate" INTEGER NOT NULL, '
        '"statement_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"book_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
        '"direction" TEXT NOT NULL, '
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
    // س107: DROP قبل CREATE لتحديث الرموز DQ على الحواجز كلها
    // (إعادة تعريف موثقة — درس v9/v21/v22).
    'DROP TRIGGER IF EXISTS trg_cash_no_negative',
    'DROP TRIGGER IF EXISTS trg_vouchers_posted_frozen',
    'DROP TRIGGER IF EXISTS trg_vouchers_no_delete_posted',
    'DROP TRIGGER IF EXISTS trg_voucher_allocations_frozen_insert',
    'DROP TRIGGER IF EXISTS trg_voucher_allocations_frozen_update',
    'DROP TRIGGER IF EXISTS trg_voucher_allocations_frozen_delete',
    'DROP TRIGGER IF EXISTS trg_voucher_allocations_no_draft_invoice',
    'DROP TRIGGER IF EXISTS trg_box_transfers_posted_frozen',
    'DROP TRIGGER IF EXISTS trg_box_transfers_no_delete_posted',
    'DROP TRIGGER IF EXISTS trg_cash_adjustments_posted_frozen',
    'DROP TRIGGER IF EXISTS trg_cash_adjustments_no_delete_posted',
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
        "(DQ-0301)'); END",
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
        "تكميلية أو مستند معاكس (DQ-0303)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_vouchers_no_delete_posted "
        "BEFORE DELETE ON vouchers FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'السند المرحّل لا يحذف (DQ-0304)'); END",
    // صفوف مطابقة السند المرحّل مجمدة — والمسودة تُعدَّل بحرية قبل الترحيل
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_frozen_insert "
        "BEFORE INSERT ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM vouchers WHERE id = NEW.voucher_id) "
        "<> 'draft' "
        "BEGIN "
        "SELECT RAISE(ABORT, 'مطابقات السند المرحّل لا تضاف — التصحيح "
        "بمطابقة تكميلية (DQ-0305)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_frozen_update "
        "BEFORE UPDATE ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM vouchers WHERE id = OLD.voucher_id) "
        "= 'posted' "
        "BEGIN SELECT RAISE(ABORT, 'مطابقات السند المرحّل لا تعدل (DQ-0306)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_frozen_delete "
        "BEFORE DELETE ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM vouchers WHERE id = OLD.voucher_id) "
        "= 'posted' "
        "BEGIN SELECT RAISE(ABORT, 'مطابقات السند المرحّل لا تحذف (DQ-0307)'); END",
    // حاجز ثالث: لا مطابقة على فاتورة مسودة حتى لو تسللت بمعاملة خارجية
    "CREATE TRIGGER IF NOT EXISTS trg_voucher_allocations_no_draft_invoice "
        "BEFORE INSERT ON voucher_allocations FOR EACH ROW "
        "WHEN (SELECT state FROM invoices WHERE id = NEW.invoice_id) "
        "= 'draft' "
        "BEGIN "
        "SELECT RAISE(ABORT, 'لا مطابقة على فاتورة مسودة — تُرحَّل أولاً (DQ-0308)'); "
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
        "SELECT RAISE(ABORT, 'التحويل المرحّل لا تعدل (DQ-0309)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_box_transfers_no_delete_posted "
        "BEFORE DELETE ON box_transfers FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'التحويل المرحّل لا يحذف (DQ-0310)'); END",
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
        "SELECT RAISE(ABORT, 'التسوية المرحّلة لا تعدل (DQ-0311)'); END",
    "CREATE TRIGGER IF NOT EXISTS trg_cash_adjustments_no_delete_posted "
        "BEFORE DELETE ON cash_adjustments FOR EACH ROW "
        "WHEN OLD.state <> 'draft' "
        "BEGIN SELECT RAISE(ABORT, 'التسوية المرحّلة لا تحذف (DQ-0312)'); END",
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
        payload: await sealLogText(jsonEncode(<String, Object?>{
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
        })),
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
        payload: await sealLogText(jsonEncode(<String, Object?>{
          'period_id': periodId,
          'start_date_text': startDateText,
          'end_date_text': endDateText,
          'reopen_reason': reason,
        })),
        uuid: const Uuid().v4(),
      ),
    );
  });
}

// ═══ الدفعة 32 (تاسعة م2): الإقفال السنوي (س-21/F-077/D-068) ═══
// ثلاثة قيود إغلاق ثم افتتاحية السنة الجديدة — كلها عبر المحرك الموحد
// حصراً (07 §1.1) بترقيم move_general من دفتر القيد العام، وقيودُ
// الإغلاق الثلاثة وحدها تُرحَّل بتاريخ ذي الحجة داخل فترتها المقفلة
// (استثناء محركي موثق على _postMoveWithinTx — جزء من عملية الإقفال
// ذاتها). السنة تُقفل «مقفلة» ولا ترحيل فيها أبداً والافتتاحية بسنة
// جديدة شطرها الشهري مفتوح. حاضنتا المعاينة والنتيجة (YearClosePreview/
// YearCloseResult) بالمجال النقي — التخزين يملؤها من قراءاته.

/// قراءة أرصدة الحسابات الورقية حتى تاريخ ما (مجمّعةً من المرحّل) —
/// مصدر الخطة النقية، والصياغة بالمجال لا هنا (نمط س-50).
Future<List<YearCloseAccountBalance>> _yearCloseBalancesUntil(
    String endDateText) async {
  final rows = await customSelect(
    'SELECT a.id AS id, a.code AS code, a.name AS name, a.type AS type, '
    'a.normal_side AS normal_side, a.is_leaf AS is_leaf, '
    'COALESCE(SUM(l.debit_minor), 0) AS debit_minor, '
    'COALESCE(SUM(l.credit_minor), 0) AS credit_minor '
    'FROM accounts a '
    'LEFT JOIN move_lines l ON l.account_id = a.id '
    'LEFT JOIN moves m ON m.id = l.move_id AND m.state = \'posted\' '
    'AND m.date_text <= ?1 '
    'GROUP BY a.id ORDER BY a.code',
    variables: [Variable.withString(endDateText)],
  ).get();
  return [
    for (final r in rows)
      YearCloseAccountBalance(
        accountId: r.data['id'] as int,
        code: r.data['code'] as String,
        name: r.data['name'] as String,
        type: AccountType.values.byName(r.data['type'] as String),
        normalSide: NormalSide.values.byName(r.data['normal_side'] as String),
        isLeaf: (r.data['is_leaf'] as int) != 0,
        debitMinor: r.data['debit_minor'] as int,
        creditMinor: r.data['credit_minor'] as int,
      ),
  ];
}

/// جمع أخطاء الإقفال السنوي — مشترك بين المعاينة والتنفيذ فلا يُرى
/// ما لا يُنفذ ولا يُنفذ ما لم يُرَ (نمط المعاينة D-183).
Future<(List<YearCloseValidationError>, FiscalYear, List<Period>)>
    _collectYearCloseErrors(int fiscalYearId) async {
  final yearRows = await (select(fiscalYears)
        ..where((t) => t.id.equals(fiscalYearId)))
      .get();
  if (yearRows.isEmpty) {
    throw StateError('لا سنة مالية بالمعرف $fiscalYearId');
  }
  final year = yearRows.single;
  final yearPeriods = await (select(periods)
        ..where((t) => t.fiscalYearId.equals(fiscalYearId))
        ..orderBy([(t) => OrderingTerm.asc(t.startDateText)]))
      .get();
  final errors = <YearCloseValidationError>[];
  if (year.state == 'closed') {
    errors.add(FiscalYearAlreadyClosed(year.name));
  }
  final openCount = yearPeriods.where((p) => p.state == 'open').length;
  if (openCount > 0) {
    errors.add(YearHasOpenPeriods(year.name, openCount));
  }
  final nextName =
      (int.parse(year.name) + 1).toString();
  final nextRows = await (select(fiscalYears)
        ..where((t) => t.name.equals(nextName)))
      .get();
  if (nextRows.isNotEmpty) {
    errors.add(NextFiscalYearExists(nextName));
  }
  final index = LedgerAccountIndex.build(await allLedgerAccounts());
  if (index.byCode('332') == null) {
    errors.add(const YearCloseAccountMissing('332'));
  }
  if (index.byCode('331') == null) {
    errors.add(const YearCloseAccountMissing('331'));
  }
  return (errors, year, yearPeriods);
}

/// معاينة الإقفال السنوي — قراءة خالصة: الحالة والفترات والميزان
/// والخطة الكاملة (س-21: «مراجعة ميزان المراجعة والنتيجة قبلية») —
/// والخطة تُحسب دائماً ولو كانت الفترات مفتوحة فالمراجعة قبلية أول
/// خطوة، أما الجاهزية فأخطاء الرفض هي التي تحكمها ([YearClosePreview.isReady]).
Future<YearClosePreview> fiscalYearClosePreview(int fiscalYearId) async {
  final (errors, year, yearPeriods) =
      await _collectYearCloseErrors(fiscalYearId);
  final balances = await _yearCloseBalancesUntil(year.endDateText);
  final index = LedgerAccountIndex.build(await allLedgerAccounts());
  final plan = buildYearClosePlan(
    balances: balances,
    resultAccountId: index.byCode('332')!.id,
    retainedAccountId: index.byCode('331')!.id,
  );
  return YearClosePreview(
    yearName: year.name,
    startDateText: year.startDateText,
    endDateText: year.endDateText,
    yearClosed: year.state == 'closed',
    periodsCount: yearPeriods.length,
    openPeriodsCount: yearPeriods.where((p) => p.state == 'open').length,
    trialTotals: await trialBalanceTotalsOf(),
    plan: plan,
  );
}

/// تنفيذ الإقفال السنوي (س-21/F-077) — معاملة ذرية واحدة:
/// (1) قيد إغلاق الإيرادات: كل إيرادٍ يُصفَّر بالجانب المعاكس لرصيده /
/// 332 يقابله. (2) قيد إغلاق المصروفات: 332 مدين / كل مصروفٍ يُصفَّر.
/// (3) قيد الصافي: ربح 332 مدين / 331 دائن (خسارة بالعكس، صفر بلا
/// قيد). (4) بذر السنة التالية بفتراتها الشهرية المفتوحة. (5) قيد
/// الافتتاحية عليها بأرصدة الحسابات الميزانية — والنتيجة قدمت إلى
/// 331 فدخلت ضمنها. (6) السنة «مقفلة» وحدث سجل موثق باللقطة الكاملة.
Future<YearCloseResult> fiscalYearClose(int fiscalYearId) {
  return transaction(() async {
    final (errors, year, yearPeriods) =
        await _collectYearCloseErrors(fiscalYearId);
    if (errors.isNotEmpty) {
      throw YearCloseException(errors);
    }
    final index = LedgerAccountIndex.build(await allLedgerAccounts());
    final resultAccount = index.byCode('332')!;
    final retainedAccount = index.byCode('331')!;
    final plan = buildYearClosePlan(
      balances: await _yearCloseBalancesUntil(year.endDateText),
      resultAccountId: resultAccount.id,
      retainedAccountId: retainedAccount.id,
    );
    final generalRows = await (select(journals)
          ..where((t) => t.code.equals('general')))
        .get();
    if (generalRows.isEmpty) {
      throw StateError('دفتر القيد العام غائب عن البذر');
    }
    final generalJournalId = generalRows.single.id;
    final now = DateTime.now().millisecondsSinceEpoch;

    Future<int> postEngineMove({
      required String dateText,
      required String narration,
      required List<YearCloseLine> accountLines,
      required YearCloseLine? resultLine,
      bool bypass = false,
      String refType = 'fiscal_year',
    }) async {
      final lines = <MoveLineDraft>[
        for (final l in accountLines)
          MoveLineDraft(
            accountId: l.accountId,
            debitMinor: l.debitMinor,
            creditMinor: l.creditMinor,
          ),
        if (resultLine != null)
          MoveLineDraft(
            accountId: resultLine.accountId,
            debitMinor: resultLine.debitMinor,
            creditMinor: resultLine.creditMinor,
          ),
      ];
      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: generalJournalId,
        dateText: dateText,
        narration: narration,
        refDocType: refType,
        refDocId: fiscalYearId,
        lines: lines,
      ));
      return _postMoveWithinTx(
        moveId,
        sequenceKind: ledgerMoveSequenceKind,
        bypassClosedPeriod: bypass,
      );
    }

    // (1) إغلاق الإيرادات — 332 يستقبل صافيها دائناً (وبالنادر مديناً
    // إن غلبته العكسية 42)، وصفرُ الصافي مع وجود أسطرٍ يعني تعادلها
    // داخلياً فلا سطر لـ332 أصلاً — والقيد متوازن بالبناء في الحالين.
    YearCloseLine? incomeCounterpart;
    if (plan.incomeTotalMinor > 0) {
      incomeCounterpart = YearCloseLine(
          accountId: resultAccount.id, creditMinor: plan.incomeTotalMinor);
    } else if (plan.incomeTotalMinor < 0) {
      incomeCounterpart = YearCloseLine(
          accountId: resultAccount.id,
          debitMinor: -plan.incomeTotalMinor);
    }
    final incomeMoveId = plan.incomeLines.isEmpty
        ? null
        : await postEngineMove(
            dateText: year.endDateText,
            narration: 'إغلاق إيرادات سنة ${year.name}',
            accountLines: plan.incomeLines,
            resultLine: incomeCounterpart,
            bypass: true,
          );

    // (2) إغلاق المصروفات — 332 مدين بصافيها (ودائناً إن غلبت العكسية
    // 53) — والقيد متوازن بالبناء.
    YearCloseLine? expenseCounterpart;
    if (plan.expenseTotalMinor > 0) {
      expenseCounterpart = YearCloseLine(
          accountId: resultAccount.id, debitMinor: plan.expenseTotalMinor);
    } else if (plan.expenseTotalMinor < 0) {
      expenseCounterpart = YearCloseLine(
          accountId: resultAccount.id,
          creditMinor: -plan.expenseTotalMinor);
    }
    final expenseMoveId = plan.expenseLines.isEmpty
        ? null
        : await postEngineMove(
            dateText: year.endDateText,
            narration: 'إغلاق مصروفات سنة ${year.name}',
            accountLines: plan.expenseLines,
            resultLine: expenseCounterpart,
            bypass: true,
          );

    // (3) الصافي إلى 331 — ربح 332 مدين/331 دائن والخسارة بالعكس.
    int? netMoveId;
    if (plan.netResultMinor != 0) {
      final isProfit = plan.netResultMinor > 0;
      final amount = plan.netResultMinor.abs();
      netMoveId = await postEngineMove(
        dateText: year.endDateText,
        narration:
            'نقل نتيجة سنة ${year.name} (${isProfit ? 'ربح' : 'خسارة'}) '
            'إلى الأرباح المحتجزة',
        accountLines: [
          isProfit
              ? YearCloseLine(
                  accountId: retainedAccount.id, creditMinor: amount)
              : YearCloseLine(
                  accountId: retainedAccount.id, debitMinor: amount),
        ],
        resultLine: isProfit
            ? YearCloseLine(
                accountId: resultAccount.id, debitMinor: amount)
            : YearCloseLine(
                accountId: resultAccount.id, creditMinor: amount),
        bypass: true,
      );
    }

    // (4) بذر السنة التالية بفتراتها الشهرية المفتوحة (D-068).
    final nextYear = int.parse(year.name) + 1;
    final nextYearId = await into(fiscalYears).insert(
      FiscalYearsCompanion.insert(
        name: nextYear.toString(),
        startDateText: '$nextYear-01-01',
        endDateText: '$nextYear-12-31',
        state: 'open',
        uuid: const Uuid().v4(),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    for (var month = 1; month <= 12; month++) {
      final mm = month.toString().padLeft(2, '0');
      final lastDay = DateTime(nextYear, month + 1, 0).day;
      await into(periods).insert(
        PeriodsCompanion.insert(
          fiscalYearId: nextYearId,
          startDateText: '$nextYear-$mm-01',
          endDateText: '$nextYear-$mm-${lastDay.toString().padLeft(2, '0')}',
          state: 'open',
          uuid: const Uuid().v4(),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }

    // (5) افتتاحية السنة الجديدة — بسنة مفتوحة فترحَّل بالمسار العادي
    // بلا أي استثناء، و332 مستبعدة (صفر بعد الصافي) — ومرجعها المميز
    // fiscal_year_opening كي تعرفه قراءة الميزانية وتتأسس منه بعد
    // الإقفال (قيود الإغلاق الثلاثة بمرجع fiscal_year وحدها لا تُعتبر
    // افتتاحاً).
    int? openingMoveId;
    if (plan.openingLines.isNotEmpty) {
      openingMoveId = await postEngineMove(
        dateText: '$nextYear-01-01',
        narration: 'قيد افتتاح سنة $nextYear',
        accountLines: plan.openingLines,
        resultLine: null,
        refType: 'fiscal_year_opening',
      );
    }

    // (6) السنة «مقفلة» وحدث سجل موثق باللقطة الكاملة (07 §2.3).
    await (update(fiscalYears)..where((t) => t.id.equals(fiscalYearId)))
        .write(FiscalYearsCompanion(
      state: const Value('closed'),
      updatedAt: Value(now),
    ));
    await into(events).insert(
      EventsCompanion.insert(
        eventAt: now,
        deviceId: await deviceId(),
        entityType: 'fiscal_year',
        entityId: Value(fiscalYearId),
        action: 'fiscal_year_closed',
        payload: await sealLogText(jsonEncode(<String, Object?>{
          'year_name': year.name,
          'start_date_text': year.startDateText,
          'end_date_text': year.endDateText,
          'income_total_minor': plan.incomeTotalMinor,
          'expense_total_minor': plan.expenseTotalMinor,
          'net_result_minor': plan.netResultMinor,
          'income_move_id': incomeMoveId,
          'expense_move_id': expenseMoveId,
          'net_move_id': netMoveId,
          'opening_move_id': openingMoveId,
          'next_year_id': nextYearId,
          'periods_closed': yearPeriods.length,
        })),
        uuid: const Uuid().v4(),
      ),
    );
    return YearCloseResult(
      yearName: year.name,
      nextYearName: nextYear.toString(),
      closingMoveIds: [
        if (incomeMoveId != null) incomeMoveId,
        if (expenseMoveId != null) expenseMoveId,
        if (netMoveId != null) netMoveId,
      ],
      openingMoveId: openingMoveId,
      netResultMinor: plan.netResultMinor,
      nextYearId: nextYearId,
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

/// قائمة الدخل بمدى تاريخ (الدفعة 33 — عاشرة م2: F-096 من أنواع
/// الحسابات و07 §1.6) — من المرحّل حصراً بمدقق المدى حرساً أولاً
/// (نمط تقارير المدى D-077)، والصياغة بالمجال النقي لا هنا.
Future<IncomeStatement> incomeStatementReport({
  required String fromText,
  required String toText,
}) async {
  final errors = validateReportRange(fromText, toText);
  if (errors.isNotEmpty) {
    throw ReportValidationException(errors);
  }
  final rows = await customSelect(
    'SELECT l.account_id AS account_id, '
    'SUM(l.debit_minor) AS debit_minor, '
    'SUM(l.credit_minor) AS credit_minor '
    'FROM move_lines l JOIN moves m ON m.id = l.move_id '
    "WHERE m.state = 'posted' "
    'AND m.date_text >= ?1 AND m.date_text <= ?2 '
    'GROUP BY l.account_id',
    variables: [
      Variable.withString(fromText),
      Variable.withString(toText),
    ],
  ).get();
  return buildIncomeStatement([
    for (final r in rows)
      LedgerLine(
        moveId: 0,
        accountId: r.data['account_id'] as int,
        debitMinor: r.data['debit_minor'] as int,
        creditMinor: r.data['credit_minor'] as int,
      ),
  ], await allLedgerAccounts());
}

/// الميزانية العمومية إلى تاريخ (الدفعة 33 — عاشرة م2: F-096) — من
/// المرحّل حصراً بتاريخٍ مدقق حرساً أولاً، والصياغة بالمجال النقي،
/// والنتيجة الجارية من حسابات النتيجة ذاتها حتى ذاك التاريخ.
///
/// التأسيس بعد الإقفال: إن وُجد قيدٌ افتتاحي (مرجع fiscal_year) بتاريخ
/// ≤ التاريخ فالأرصدة تُبنى منه ثم بحركات ما بعده حصراً — فلا ازدواج
/// بين سنةٍ افتتاحيتها قدمت أرصدتَها وسلفها (الافتتاحية تعيد إثبات
/// ما قبلها فالتراكم الخام يضاعف)، وقبل أي إقفال فالتراكم الخام هو
/// الأصح أصلاً.
Future<BalanceSheet> balanceSheetReport({required String asOfText}) async {
  if (!isValidIsoDate(asOfText)) {
    throw ReportValidationException([ReportRangeInvalidDate(asOfText)]);
  }
  final openingRows = await customSelect(
    "SELECT id, date_text FROM moves WHERE ref_doc_type = "
    "'fiscal_year_opening' "
    "AND state = 'posted' AND date_text <= ?1 "
    'ORDER BY date_text DESC, id DESC LIMIT 1',
    variables: [Variable.withString(asOfText)],
  ).get();
  final balances = <int, (int, int)>{};
  void addRow(dynamic row) {
    final id = row.data['account_id'] as int;
    final (d, c) = balances[id] ?? (0, 0);
    balances[id] = (
      d + (row.data['debit_minor'] as int),
      c + (row.data['credit_minor'] as int),
    );
  }

  if (openingRows.isEmpty) {
    final rows = await customSelect(
      'SELECT l.account_id AS account_id, '
      'SUM(l.debit_minor) AS debit_minor, '
      'SUM(l.credit_minor) AS credit_minor '
      'FROM move_lines l JOIN moves m ON m.id = l.move_id '
      "WHERE m.state = 'posted' AND m.date_text <= ?1 "
      'GROUP BY l.account_id',
      variables: [Variable.withString(asOfText)],
    ).get();
    for (final row in rows) {
      addRow(row);
    }
  } else {
    final opening = openingRows.single;
    final openingId = opening.data['id'] as int;
    final openingDate = opening.data['date_text'] as String;
    final baseRows = await customSelect(
      'SELECT account_id, SUM(debit_minor) AS debit_minor, '
      'SUM(credit_minor) AS credit_minor '
      'FROM move_lines WHERE move_id = ?1 GROUP BY account_id',
      variables: [Variable.withInt(openingId)],
    ).get();
    for (final row in baseRows) {
      addRow(row);
    }
    final deltaRows = await customSelect(
      'SELECT l.account_id AS account_id, '
      'SUM(l.debit_minor) AS debit_minor, '
      'SUM(l.credit_minor) AS credit_minor '
      'FROM move_lines l JOIN moves m ON m.id = l.move_id '
      "WHERE m.state = 'posted' AND m.date_text > ?1 "
      'AND m.date_text <= ?2 GROUP BY l.account_id',
      variables: [
        Variable.withString(openingDate),
        Variable.withString(asOfText),
      ],
    ).get();
    for (final row in deltaRows) {
      addRow(row);
    }
  }
  return buildBalanceSheet([
    for (final entry in balances.entries)
      LedgerLine(
        moveId: 0,
        accountId: entry.key,
        debitMinor: entry.value.$1,
        creditMinor: entry.value.$2,
      ),
  ], await allLedgerAccounts());
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

  // ═══ س236 (د10 البنوك D-224): مستند التسوية البنكية بنمط تسوية
  // الصندوق (س-17) حرفاً — للصناديق الجارية البنكية حصراً، ورصيد كشف
  // البنك المدخل يقارن بالدفتري فالفرق يقيد على 57 (س8). ═══

  /// إنشاء جدول التسويات البنكية (عند الإنشاء والترقية معاً — آمن
  /// التكرار بIF NOT EXISTS).
  Future<void> _createBankReconciliationTableTx() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS "bank_reconciliations" ('
      '"id" INTEGER PRIMARY KEY AUTOINCREMENT, '
      "'number' TEXT NOT NULL DEFAULT '', "
      '"cash_box_id" INTEGER NOT NULL, '
      '"reconciliation_date" TEXT NOT NULL, '
      '"currency_id" INTEGER NOT NULL DEFAULT 1, '
      '"fx_rate" INTEGER NOT NULL, '
      '"statement_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
      '"book_balance_doc_minor" INTEGER NOT NULL DEFAULT 0, '
      '"direction" TEXT NOT NULL, '
      '"amount_doc_minor" INTEGER NOT NULL DEFAULT 0, '
      '"amount_base_minor" INTEGER NOT NULL DEFAULT 0, '
      "'reason' TEXT NOT NULL DEFAULT '', "
      "'state' TEXT NOT NULL DEFAULT 'draft', "
      '"move_id" INTEGER NULL, '
      '"uuid" TEXT NOT NULL, '
      '"created_at" INTEGER NOT NULL DEFAULT 0, '
      '"updated_at" INTEGER NOT NULL DEFAULT 0, '
      '"is_deleted" INTEGER NOT NULL DEFAULT 0)',
    );
  }

  /// س236: فحوص التسوية البنكية المحركية — الصندوق موجود **وجارٍ
  /// بنكي** (نوعه من v38) وحسابه نشط وعملته عملة التسوية.
  Future<List<BankReconciliationValidationError>> _collectBankReconErrors(
    BankReconciliationDraft draft, {
    required bool forPosting,
  }) async {
    final errors = validateBankReconciliationStructure(draft);
    if (errors.isNotEmpty) return errors;
    if (forPosting) {
      final period = findPeriodForDate(await ledgerPeriods(), draft.dateText);
      if (period == null) {
        return [BankReconNoPeriod(draft.dateText)];
      }
      if (!period.isOpen) {
        return [BankReconClosedPeriod(draft.dateText)];
      }
    }
    final box = await _cashBoxByIdTx(draft.cashBoxId);
    if (box == null) {
      return [const BankReconBoxMissing()];
    }
    final row = (await customSelect(
            "SELECT kind, name FROM cash_boxes WHERE id = ? AND is_deleted = 0",
            variables: [Variable.withInt(draft.cashBoxId)])
        .get());
    if (row.isEmpty) {
      return [const BankReconBoxMissing()];
    }
    final kind = (row.first.data['kind'] as String?) ?? 'cash';
    if (kind != 'bank') {
      return [BankReconBoxNotBank(row.first.data['name'] as String)];
    }
    final account = await _accountByIdTx(box.accountId);
    if (account == null || !account.$4) {
      return [BankReconBoxInactive(box.name)];
    }
    final boxCurrencyId = (await customSelect(
            'SELECT currency_id FROM cash_boxes WHERE id = ?',
            variables: [Variable.withInt(draft.cashBoxId)])
        .getSingle())
        .data['currency_id'] as int;
    if (boxCurrencyId != draft.currencyId) {
      return [const BankReconBoxCurrencyMismatch()];
    }
    return const [];
  }

  /// س236: إنشاء مسودة تسوية بنكية — الرصيد الدفتري يُلتقط لحظتها
  /// (لقطة المسودة F-122/D-082) والفرق محسوب لا مُدخل.
  Future<int> createBankReconciliationDraft(
      BankReconciliationDraft draft) async {
    return transaction(() async {
      final bookBalance =
          await _cashBoxBalanceDocTx(draft.cashBoxId, draft.fxRate);
      final effective = BankReconciliationDraft(
        dateText: draft.dateText,
        cashBoxId: draft.cashBoxId,
        currencyId: draft.currencyId,
        fxRate: draft.fxRate,
        statementBalanceDocMinor: draft.statementBalanceDocMinor,
        bookBalanceDocMinor: bookBalance,
        reason: draft.reason,
      );
      final errors = await _collectBankReconErrors(effective, forPosting: false);
      if (errors.isNotEmpty) {
        throw BankReconciliationValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT INTO bank_reconciliations (number, cash_box_id, "
        "reconciliation_date, currency_id, fx_rate, "
        "statement_balance_doc_minor, book_balance_doc_minor, direction, "
        "amount_doc_minor, amount_base_minor, reason, state, move_id, "
        "uuid, created_at, updated_at, is_deleted) "
        "VALUES ('', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft', NULL, ?, ?, ?, 0)",
        [
          effective.cashBoxId,
          effective.dateText,
          effective.currencyId,
          effective.fxRate,
          effective.statementBalanceDocMinor,
          effective.bookBalanceDocMinor,
          effective.direction.storageValue,
          effective.amountDocMinor,
          convertToBaseMinor(effective.amountDocMinor, effective.fxRate),
          effective.reason.trim(),
          const Uuid().v4(),
          now,
          now,
        ],
      );
      final id =
          (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
              .data['id'] as int;
      await _recordDocEventTx(
        entityType: 'bank_reconciliation',
        table: 'bank_reconciliations',
        entityId: id,
        action: 'created',
      );
      return id;
    });
  }

  /// س236: ترحيل التسوية البنكية بنمط ترحيل تسوية الصندوق حرفاً —
  /// العجز: 57 مدين / الصندوق دائن والزيادة: الصندوق مدين / 57 دائن
  /// (س8)، وحركة الصندوق بمصدرها والرقم من تسلسل bank_reconciliation.
  Future<int> postBankReconciliation(int bankReconId) async {
    return transaction(() async {
      final a = await _bankReconRowTx(bankReconId);
      if (a == null) {
        throw StateError('لا تسوية بنكية بالمعرف $bankReconId');
      }
      if (a['state'] != 'draft') {
        throw BankReconciliationValidationException(
            [BankReconStateNotDraft(a['state'] as String)]);
      }
      final draft = BankReconciliationDraft(
        dateText: a['reconciliation_date'] as String,
        cashBoxId: a['cash_box_id'] as int,
        currencyId: a['currency_id'] as int,
        fxRate: a['fx_rate'] as int,
        statementBalanceDocMinor: a['statement_balance_doc_minor'] as int,
        bookBalanceDocMinor: a['book_balance_doc_minor'] as int,
        reason: a['reason'] as String? ?? '',
      );
      final errors = await _collectBankReconErrors(draft, forPosting: true);
      if (errors.isNotEmpty) {
        throw BankReconciliationValidationException(errors);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final year = yearOfIsoDate(draft.dateText);
      final number = formatDocumentNumber(
          year, await _advanceSequenceWithinTx('bank_reconciliation', year),
          counterWidth: await _counterWidth());
      final journalId = await _journalIdByCodeTx('cash');
      final acc57 = await _accountIdByCodeTx('57');
      final box = (await _cashBoxByIdTx(draft.cashBoxId))!;
      final totalDoc = draft.amountDocMinor;
      final totalBase = convertToBaseMinor(totalDoc, draft.fxRate);
      final isShortage = draft.direction == CashAdjustmentDirection.shortage;

      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: journalId,
        dateText: draft.dateText,
        narration:
            'تسوية بنكية — ${draft.direction.label}: ${draft.reason.trim()}',
        refDocType: 'bank_reconciliation',
        refDocId: bankReconId,
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
        "VALUES (?, ?, ?, ?, ?, 'bank_reconciliation', ?, NULL, ?, ?, ?, 0)",
        [
          box.id,
          isShortage ? 'out' : 'in',
          totalDoc,
          totalBase,
          draft.fxRate,
          bankReconId,
          const Uuid().v4(),
          now,
          now,
        ],
      );

      await customStatement(
        "UPDATE bank_reconciliations SET state = 'posted', number = ?, "
        'move_id = ?, updated_at = ? WHERE id = ?',
        [number, moveId, now, bankReconId],
      );
      await _recordDocEventTx(
        entityType: 'bank_reconciliation',
        table: 'bank_reconciliations',
        entityId: bankReconId,
        action: 'posted',
      );
      return bankReconId;
    });
  }

  /// س236: صف التسوية البنكية داخل معاملة.
  Future<Map<String, Object?>?> _bankReconRowTx(int id) async {
    final rows = await customSelect(
      'SELECT * FROM bank_reconciliations WHERE id = ? AND is_deleted = 0',
      variables: [Variable.withInt(id)],
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// س236: رصيد الصندوق الدفتري بعملة كشفه — من رصيد الأساس الموحد
  /// (معادلة الصندوق ذاتها: الافتتاحي + الداخل − الخارج) بقسمة لقطة
  /// السعر بدالة التقريب ذاتها (F-122) — فالأساس مصدر الحقيقة الوحيد
  /// وعملة الأساس (fxRate = 10^6) تعيد الرصيد ذاته بالضبط.
  Future<int> _cashBoxBalanceDocTx(int boxId, int fxRate) async {
    final balanceBase = await _cashBoxBalanceTx(boxId);
    return roundHalfAwayFromZeroRatio(balanceBase * fxRateScale, fxRate);
  }

  /// س236: الرصيد الدفتري بعملة الكشف — علني لواجهة التسوية البنكية
  /// (لقطة السعر بقيمة المستند أو لقطة الأساس لعملته — حرس D-082).
  Future<int> bankBoxBookBalanceDocMinor(int boxId, {int? fxRate}) async {
    return _cashBoxBalanceDocTx(boxId, fxRate ?? baseCurrencyFxRate);
  }

  /// س236: قائمة تسويات صندوق بنكي بترتيب أحدثها أولاً.
  Future<List<BankReconciliationListRow>> bankReconciliationsOf(
      {int? cashBoxId}) async {
    final where = cashBoxId == null
        ? 'WHERE r.is_deleted = 0'
        : 'WHERE r.is_deleted = 0 AND r.cash_box_id = ?';
    final args = <Variable<Object>>[
      if (cashBoxId != null) Variable.withInt(cashBoxId),
    ];
    final rows = await customSelect(
      'SELECT r.id AS id, r.number AS number, r.reconciliation_date AS date, '
      'r.direction AS direction, r.statement_balance_doc_minor AS stmt, '
      'r.book_balance_doc_minor AS book, r.amount_doc_minor AS amount, '
      'r.reason AS reason, r.state AS state, b.name AS box_name, '
      'c.code AS currency_code '
      'FROM bank_reconciliations r '
      'JOIN cash_boxes b ON b.id = r.cash_box_id '
      'JOIN currencies c ON c.id = r.currency_id '
      '$where ORDER BY r.id DESC LIMIT 200',
      variables: args,
    ).get();
    return [
      for (final r in rows)
        BankReconciliationListRow(
          id: r.data['id'] as int,
          number: r.data['number'] as String? ?? '',
          dateText: r.data['date'] as String,
          boxName: r.data['box_name'] as String,
          direction: CashAdjustmentDirection.fromStorage(
              r.data['direction'] as String),
          statementBalanceDocMinor: r.data['stmt'] as int,
          bookBalanceDocMinor: r.data['book'] as int,
          amountDocMinor: r.data['amount'] as int,
          reason: r.data['reason'] as String? ?? '',
          state: r.data['state'] as String,
          currencyCode: r.data['currency_code'] as String,
        ),
    ];
  }


Future<List<CashBoxReportRow>> cashBoxesReport() async {
  final rows = await customSelect(
    'SELECT b.id AS box_id, b.name AS name, b.kind AS kind, '
    'b.bank_name AS bank_name, b.account_number AS account_number, '
    'b.currency_id AS currency_id, '
    'c.code AS currency_code, '
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
      // س236: النوع واسم البنك للصناديق الجارية البنكية.
      kind: (r.data['kind'] as String?) ?? 'cash',
      bankName: r.data['bank_name'] as String?,
      accountNumber: r.data['account_number'] as String?,
      currencyId: r.data['currency_id'] as int,
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

/// م04 منتقي المردود (س205 — الدفعة الثالثة من فحص الواجهات وفق M3
/// بأمر المالك «تابع في م06 التكيفي ثم بقية الرابعة»): مرشحو الأصل —
/// المرحّل بنوعه المطلوب حصراً (بيع لمردود البيع وشراء لمردود
/// الشراء) وغير المحذوف، بأحدث تاريخٍ ثم أحدث رقم، وبحد خمسين
/// آخرَ قراءة للورقة (الباحث في سجلٍ طويل يرقم أصله). قراءة خالصة
/// لا قرار — وحرس المحرك بعد التعبئة هو الحارس الحقيقي.
Future<List<InvoiceReturnCandidate>> invoiceReturnCandidatesOf(
    String originalKindStorageValue) async {
  final rows = await customSelect(
    'SELECT i.id AS id, i.invoice_date AS invoice_date, '
    'i.party_id AS party_id, p.name AS party_name, '
    'i.currency_id AS currency_id, i.total_doc_minor AS total_doc_minor '
    'FROM invoices i LEFT JOIN parties p ON p.id = i.party_id '
    "WHERE i.kind = ?1 AND i.state <> 'draft' AND i.is_deleted = 0 "
    'ORDER BY i.invoice_date DESC, i.id DESC LIMIT 50',
    variables: [Variable.withString(originalKindStorageValue)],
  ).get();
  return [
    for (final r in rows)
      InvoiceReturnCandidate(
        id: r.data['id'] as int,
        invoiceDate: r.data['invoice_date'] as String,
        partyId: r.data['party_id'] as int?,
        partyName: r.data['party_name'] as String?,
        currencyId: r.data['currency_id'] as int,
        totalDocMinor: r.data['total_doc_minor'] as int,
      ),
  ];
}

/// م04 (س205): بذرة المردود من أصل منتقى — رأسه المعبأ (المعرف
/// والطرف والمستودع والعملة) وأسطره **بحساب المحرك ذاته**: كميات
/// الأصل مجمعةً بالصنف (عرف _origQtyByItemTx) ناقص مردودات المرحّل
/// بنوع المردود (عرف _returnedQtyByItemTx — والمسودات خارج الحساب)
/// فما يُبذر لا يُرفض بفحص InvoiceReturnQtyExceedsRemaining. والسعر
/// أول سعر سطر الصنف بترتيب أسطر الأصل — قابل للتعديل قبل الحفظ
/// (عرف س123). والأصل الغائب أو المسودة أو المخالف لنوع المردود
/// null — فالعلة انحرافٌ يُعاد فحصه لا حالة عرض.
Future<InvoiceReturnSeed?> invoiceReturnSeedOf({
  required int originalInvoiceId,
  required InvoiceKind returnKind,
}) async {
  final expected = returnKind.expectedOriginalKind;
  if (expected == null) return null;
  final origRows = await customSelect(
    'SELECT i.id AS id, i.kind AS kind, i.state AS state, '
    'i.party_id AS party_id, p.name AS party_name, '
    'i.warehouse_id AS warehouse_id, i.currency_id AS currency_id '
    'FROM invoices i LEFT JOIN parties p ON p.id = i.party_id '
    'WHERE i.id = ?1 AND i.is_deleted = 0',
    variables: [Variable.withInt(originalInvoiceId)],
  ).get();
  if (origRows.isEmpty) return null;
  final orig = origRows.first.data;
  if (orig['state'] as String == 'draft') return null;
  final origKind = InvoiceKind.fromStorage(orig['kind'] as String);
  if (origKind != expected) return null;
  final origQty = await _origQtyByItemTx(originalInvoiceId);
  final returnedQty =
      await _returnedQtyByItemTx(originalInvoiceId, returnKind.storageValue);
  // أول سعر سطر لكل صنف بترتيب أسطر الأصل — والصنف بسطرين يأخذ
  // سعر أوله (الجمع كميةً بكمية الأصل أعلاه).
  final priceRows = await customSelect(
    'SELECT item_id, unit_price_minor FROM invoice_lines '
    'WHERE invoice_id = ?1 ORDER BY id',
    variables: [Variable.withInt(originalInvoiceId)],
  ).get();
  final priceByItem = <int, int>{};
  for (final r in priceRows) {
    final itemId = r.data['item_id'] as int;
    if (!priceByItem.containsKey(itemId)) {
      priceByItem[itemId] = r.data['unit_price_minor'] as int;
    }
  }
  final itemById = {
    for (final it in await select(items).get()) it.id: it,
  };
  final seedLines = <InvoiceReturnSeedLine>[];
  final itemIds = origQty.keys.toList()..sort();
  for (final itemId in itemIds) {
    final returned = returnedQty[itemId] ?? 0;
    final remaining = (origQty[itemId] ?? 0) - returned;
    if (remaining <= 0) continue; // الموفى كاملاً لا يُبذر (عرف س123)
    final item = itemById[itemId];
    seedLines.add(InvoiceReturnSeedLine(
      itemId: itemId,
      itemSku: item?.sku ?? '',
      itemName: item?.name ?? '',
      origQtyBase: origQty[itemId] ?? 0,
      returnedQtyBase: returned,
      remainingQtyBase: remaining,
      unitPriceMinor: priceByItem[itemId] ?? 0,
    ));
  }
  return InvoiceReturnSeed(
    originalId: originalInvoiceId,
    originalKind: origKind,
    partyId: orig['party_id'] as int?,
    partyName: orig['party_name'] as String?,
    warehouseId: orig['warehouse_id'] as int?,
    currencyId: orig['currency_id'] as int,
    lines: seedLines,
  );
}

// ═══ دفعة (15) «ما قبل إغلاق م1» (س-151..س-153/D-149..D-151) ═══
// أمر المالك الحرفي (س47): «كل شيء يمكن تنفيذه قبل إغلاق م1 قم بتنفيذه»
// — فأُقدّم من خريطة دراسة محضر الخبراء (س46) ما تنفيذه قراءة فوق
// أعمدة القائمة بلا ترحيلة: أعمار الذمم بفوهجها القابلة للتهيئة
// (D-140 روحاً — أقرب ربح في المحضر كله لما منجز سلفاً من مصالحة
// وذمم واستحقاق) ودفتر اليومية المرشّح، ومعهما خانة «ملاحظة
// التسليم» المعروضة منذ بوابة دفعة (12) §3 والمحجوبة بلا كلمة حتى
// جاء هذا الأمر الشامل — بترحيلة v14 لعمودها النصي حصراً.

/// س-151/D-149: تقرير أعمار الذمم — قراءة خالصة بلا ترحيلة ولا
/// جداول تجميع (D-089 روحاً): الفواتير المفتوحة (المرحّلة غير
/// المغطاة كلياً بمطابقات السندات المرحّلة — محرك المصالحة ذاته:
/// حالتا posted/partially_paid والمفتوح = الإجمالي − المغطى doc-side
/// كما في التوزيع الآلي س-63) تُعمَّر بتاريخ الاستحقاق وإلا تاريخ
/// الفاتورة، والمفتوح بوحدات المستند يُرفع إلى الأساسية بتحويل
/// المحرك ذاته (convertToBaseMinor — F-122/D-082) فتُقرأ الأعمار
/// بالأساسية نمط تقرير الذمم. الفوهج قابلة للتهيئة افتراضها
/// 30/60/90/120 بقرار الدراسة، والفوهة الأولى «غير مستحق» لمن
/// استحقاقه اليوم أو بعده، والترتيب مدينة ثم دائنة بلفظ D-130،
/// وكل طرف بفواتيره المفتوحة فتصير الأسماء مداخِل (D-135).
/// فواتير البيع آجلة بلا طرف لا توجد أصلاً (س-04: بلا طرف مرفوضة)
// فصف بلا طرف يُسقط آمناً.
Future<AgingReport> agingReport({
  required List<int> thresholds,
  String? kindStorageValue,
}) async {
  final clean = [
    for (final t in thresholds)
      if (t > 0) t,
  ]..sort();
  if (clean.isEmpty) {
    throw ArgumentError('فوهج الأعمار قائمة أيام موجبة لا تكون فارغة');
  }
  final kind = kindStorageValue?.trim() ?? '';
  assert(
    kind == '' || kind == 'sale' || kind == 'purchase',
    'فلتر النوع: بيع أو شراء أو الكل',
  );
  final rows = await customSelect(
    'SELECT inv.id AS id, inv.kind AS kind, inv.number AS number, '
    'inv.invoice_date AS invoice_date, inv.due_date AS due_date, '
    'inv.total_doc_minor AS total_doc, inv.fx_rate AS fx_rate, '
    'c.code AS currency_code, p.id AS party_id, p.name AS party_name, '
    'COALESCE(cov.covered, 0) AS covered_doc '
    'FROM invoices inv '
    'LEFT JOIN parties p ON p.id = inv.party_id '
    'JOIN currencies c ON c.id = inv.currency_id '
    'LEFT JOIN (SELECT va.invoice_id AS iid, '
    'SUM(va.applied_doc_minor) AS covered '
    'FROM voucher_allocations va '
    'JOIN vouchers v ON v.id = va.voucher_id '
    "WHERE v.state = 'posted' AND v.is_deleted = 0 "
    'AND va.is_deleted = 0 GROUP BY va.invoice_id) cov '
    'ON cov.iid = inv.id '
    'WHERE inv.is_deleted = 0 '
    "AND inv.state IN ('posted', 'partially_paid') "
    "AND inv.kind IN ('sale', 'purchase') "
    "AND (?1 = '' OR inv.kind = ?1) "
    'ORDER BY inv.invoice_date ASC, inv.id ASC',
    variables: [Variable.withString(kind)],
  ).get();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  int dayOf(String dateText) {
    final d = DateTime.parse(dateText);
    // أيام التجاوز = اليوم − موعد الاستحقاق: الماضي موجب (متأخر)
    // والمستقبل سالب (غير مستحق) — علة جولة CI 149 كانت الإشارة
    // معكوسة (فرق الاستحقاق عن اليوم) فولت الفوهج بلا أعمار.
    return today.difference(DateTime(d.year, d.month, d.day)).inDays;
  }

  // الفوهة صفراً لغير المستحق، و1..n للفوهج بالترتيب، وn+1 لما فاق
  // آخر فوهة — بطول n+2 دائماً.
  final n = clean.length;
  int bucketIndex(int daysOver) {
    if (daysOver < 0) return 0;
    for (var i = 0; i < n; i++) {
      if (daysOver <= clean[i]) return i + 1;
    }
    return n + 1;
  }

  final labels = <String>['غير مستحق'];
  for (var i = 0; i < n; i++) {
    labels.add(i == 0
        ? 'حتى ${clean[i]} يوماً'
        : '${clean[i - 1] + 1} حتى ${clean[i]} يوماً');
  }
  labels.add('أكثر من ${clean[n - 1]} يوماً');

  // تجميع على الطرف — مفتاحه معرفه واتجاهه من نوع الفاتورة (البيع
  // ذمة له علينا يطالبنا، والشراء ذمة لنا عليه).
  final partyOrder = <int>[];
  final partyByKey = <int, _AgingPartyBuilder>{};
  for (final r in rows) {
    final partyId = r.data['party_id'] as int?;
    if (partyId == null) continue;
    final remainingDoc =
        (r.data['total_doc'] as int) - (r.data['covered_doc'] as int);
    if (remainingDoc <= 0) continue;
    final builder = partyByKey.putIfAbsent(partyId, () {
      partyOrder.add(partyId);
      return _AgingPartyBuilder(
        partyId: partyId,
        partyName: (r.data['party_name'] as String?) ?? 'بلا طرف',
        theyOweUs: (r.data['kind'] as String) == 'sale',
      );
    });
    final invoiceDate = r.data['invoice_date'] as String;
    final dueDate = r.data['due_date'] as String?;
    final anchor = dueDate ?? invoiceDate;
    final daysOver = dayOf(anchor);
    final idx = bucketIndex(daysOver);
    final remainingBase = convertToBaseMinor(
      remainingDoc,
      r.data['fx_rate'] as int,
    );
    builder.add(
      idx,
      remainingBase,
      AgingInvoiceRow(
        invoiceId: r.data['id'] as int,
        number: r.data['number'] as String,
        invoiceDate: invoiceDate,
        dueDate: dueDate,
        remainingDocMinor: remainingDoc,
        remainingBaseMinor: remainingBase,
        daysOver: daysOver,
        currencyCode: r.data['currency_code'] as String,
      ),
    );
  }
  final parties = <AgingPartyRow>[
    // الترتيب بلفظ D-130: المدينة (هم يدينون لنا) ثم الدائنة، وكل
    // مجموعة بأسمائها.
    for (final id in partyOrder)
      if (partyByKey[id]!.theyOweUs) partyByKey[id]!.build(n + 2),
    for (final id in partyOrder)
      if (!partyByKey[id]!.theyOweUs) partyByKey[id]!.build(n + 2),
  ];
  final totals = List<int>.filled(n + 2, 0);
  for (final p in parties) {
    for (var i = 0; i < totals.length; i++) {
      totals[i] += p.bucketMinor[i];
    }
  }
  return AgingReport(
    thresholds: List<int>.unmodifiable(clean),
    bucketLabels: List<String>.unmodifiable(labels),
    parties: parties,
    bucketTotalsMinor: totals,
  );
}

/// س-152/D-150: دفتر اليومية — قراءة خالصة ثالثة من نوعها منذ دفعة
/// التقارير (نمط كشف الحساب D-137): قيود المرحّل بترتيب الزمن
/// (تاريخ القيد ثم معرفه ثم أسطره) بأسطرها كاملة (الحساب الورقي
/// والطرف والجانبتان)، بفلتر مدى تاريخ يُدقق قبل لمس القاعدة
/// (D-077) وفلتر دفتر من الأنواع الخمسة (D-076)، ومجموعا الجانبين
/// ضابط توازنهما روح F-068 — وقراءة واحدة تجمع القيود وأسطرها
/// فيصير الترتيب بلسان SQL لا محاكاة.
Future<JournalBookReport> journalBookReport({
  String? fromText,
  String? toText,
  String? journalKind,
}) async {
  final from = fromText?.trim() ?? '';
  final to = toText?.trim() ?? '';
  if (from.isNotEmpty || to.isNotEmpty) {
    final errors = validateReportRange(from, to);
    if (errors.isNotEmpty) {
      throw ReportValidationException(errors);
    }
  }
  final jk = journalKind?.trim() ?? '';
  assert(
    jk == '' ||
        jk == 'sales' ||
        jk == 'purchase' ||
        jk == 'cash' ||
        jk == 'stock' ||
        jk == 'general',
    'فلتر الدفتر: أحد الأنواع الخمسة أو الكل',
  );
  final rows = await customSelect(
    'SELECT m.id AS move_id, m.date_text AS move_date, '
    'm.number AS move_number, m.narration AS narration, '
    'j.name AS journal_name, '
    'a.code AS account_code, a.name AS account_name, '
    'p.name AS party_name, '
    'l.debit_minor AS debit_minor, l.credit_minor AS credit_minor '
    'FROM move_lines l '
    'JOIN moves m ON m.id = l.move_id '
    'JOIN journals j ON j.id = m.journal_id '
    'JOIN accounts a ON a.id = l.account_id '
    'LEFT JOIN parties p ON p.id = l.party_id '
    "WHERE m.state = 'posted' AND m.is_deleted = 0 "
    'AND l.is_deleted = 0 '
    "AND (?1 = '' OR m.date_text >= ?1) "
    "AND (?2 = '' OR m.date_text <= ?2) "
    "AND (?3 = '' OR j.kind = ?3) "
    'ORDER BY m.date_text ASC, m.id ASC, l.id ASC',
    variables: [
      Variable.withString(from),
      Variable.withString(to),
      Variable.withString(jk),
    ],
  ).get();
  final builders = <JournalBookBuilder>[];
  JournalBookBuilder? current;
  var totalDebit = 0;
  var totalCredit = 0;
  for (final r in rows) {
    final moveId = r.data['move_id'] as int;
    if (current == null || current.moveId != moveId) {
      final moveDate = r.data['move_date'] as String;
      final moveNumber = r.data['move_number'] as String;
      final journalName = r.data['journal_name'] as String;
      final narration = r.data['narration'] as String?;
      current = JournalBookBuilder(
        moveId: moveId,
        moveDate: moveDate,
        moveNumber: moveNumber,
        journalName: journalName,
        narration: narration,
      );
      builders.add(current);
    }
    final debit = r.data['debit_minor'] as int;
    final credit = r.data['credit_minor'] as int;
    totalDebit += debit;
    totalCredit += credit;
    current.addLine(
      JournalBookLine(
        accountCode: r.data['account_code'] as String,
        accountName: r.data['account_name'] as String,
        partyName: r.data['party_name'] as String?,
        debitMinor: debit,
        creditMinor: credit,
      ),
    );
  }
  // القيد يُبنى بعد اكتمال أسطره حصراً — مجاميعه من أسطره المخزونة
  // لا من لقطة مبكرة (علّة مُصلَحة قبل CI: لقطة late final كانت
  // تلتقط الأصفار لحظة أول قراءة قبل الملء).
  final entries = [for (final b in builders) b.build()];
  return JournalBookReport(
    entries: entries,
    totalDebitMinor: totalDebit,
    totalCreditMinor: totalCredit,
  );
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

/// مطابقة دفتر المخزون (الدفعة 31 — ثامنة م2: ربط المخزون بالدفتر) —
/// قراءتان خامتان والصياغة بالمجال النقي: (أ) أسطر القيود المرحّلة
/// الحاملة مرجع حركة مخزون مجمّعةً بالصنف (07 §3.1: الربط من الإصدار
/// الأول — م-27 مؤكد)، (ب) قيمة المخزون من stock_balances مجمّعةً
/// بالصنف — فثابت المطابقة D-067/F-178 يُعرض بالأرقام لا كلاماً.
/// التخزين يقرأ ويجمع ولا يقرر — الاختلاف والاتجاهات بالمجال حصراً.
Future<InventoryReconciliationReport> inventoryLedgerReconciliation() async {
  final ledgerRows = await customSelect(
    'SELECT sm.item_id AS item_id, i.sku AS sku, i.name AS name, '
    'SUM(ml.debit_minor) AS debit_minor, SUM(ml.credit_minor) AS credit_minor '
    'FROM move_lines ml '
    'JOIN moves m ON m.id = ml.move_id '
    'JOIN stock_moves sm ON sm.id = ml.ref_stock_move_id '
    'JOIN items i ON i.id = sm.item_id '
    "WHERE m.state = 'posted' AND ml.ref_stock_move_id IS NOT NULL "
    'AND sm.is_deleted = 0 '
    'GROUP BY sm.item_id',
  ).get();
  final stockRows = await customSelect(
    'SELECT sb.item_id AS item_id, i.sku AS sku, i.name AS name, '
    'SUM(sb.total_value_minor) AS value_minor '
    'FROM stock_balances sb '
    'JOIN items i ON i.id = sb.item_id '
    'WHERE sb.is_deleted = 0 '
    'GROUP BY sb.item_id',
  ).get();
  return buildInventoryLedgerReconciliation([
    for (final r in ledgerRows)
      InventoryLedgerRawRow(
        itemId: r.data['item_id'] as int,
        sku: r.data['sku'] as String,
        name: r.data['name'] as String,
        debitMinor: r.data['debit_minor'] as int,
        creditMinor: r.data['credit_minor'] as int,
      ),
  ], [
    for (final r in stockRows)
      InventoryStockRawRow(
        itemId: r.data['item_id'] as int,
        sku: r.data['sku'] as String,
        name: r.data['name'] as String,
        valueMinor: r.data['value_minor'] as int,
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
    // س237 (المرحلة ج — D-235): أسطر الحرة تجمع تحت «أصناف حرة»
    // كي تتطابق المجاميع (LEFT JOIN فلا يسقط سطر حر بالربط).
    'SELECT il.item_id AS item_id, '
    "COALESCE(i.sku, 'حر') AS sku, "
    "COALESCE(i.name, 'أصناف حرة') AS name, "
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
    // س237: ربط أيسر فأسطر الحرة (بلا صنف) تجمع ولا تسقط.
    'LEFT JOIN items i ON i.id = il.item_id '
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
///
/// الدفعة 21 (F-168 بكلمة المالك «سجل الفواتير موافق» س71): فلتر
/// الاستلام — الكل (null) أو 'undelivered' (غير مستلم: كل أسطر
/// الفاتورة غير مستلمة أو لا أسطر لها) أو 'partial' (جزئي: بعض
/// الأسطر مستلمة) أو 'received' (مكتمل الاستلام: كل الأسطر مستلمة
/// ولا سطر غير مستلم) — محسوباً من عمود العلم القائم v13 بلا
/// ترحيلة جديدة، وعدّادا الأسطر يُرجَعان بالصف ليكون ما يُعرض
/// في القائمة هو ذاته المطبوع والمصدَّر (نمط F-166: ما يُرى
/// يُطبع ويُصدَّر).
Future<List<InvoiceListRow>> invoicesListReport({
  String? fromText,
  String? toText,
  String? kindStorageValue,

  /// س-147 (دفعة 13): فلتر الطرف الاختياري — روابط الطرف من الذمم
  /// تفتح «فواتيره» بهذا الفلتر، وعرضٌ فوق القراءة لا حساب جديد.
  int? partyId,

  /// الدفعة 21 (F-168): فلتر الاستلام — null الكل، وإلا 'undelivered'
  /// أو 'partial' أو 'received' كما في التوثيق أعلاه.
  String? receiptFilter,

  /// س101: فلتر الحالة — null الكل، وإلا 'draft' (المسودات المعلقة
  /// بانتظار الاعتماد) أو 'posted' (المرحّلة) — لسان المعتمد الذي يبحث
  /// عن معلّقات المندوبين، وأي قيمة أخرى تُسقط صامتاً كأنها null.
  String? stateFilter,

  /// س202 (بأمر المالك «قم بتنفيذ المطلوب 1-5»): فلتر الجهة — null الكل،
  /// وإلا 'sales' (البيع ومردوده) أو 'purchases' (الشراء ومردوده) —
  /// بلاطتا «المبيعات»/«المشتريات» بالرئيسية تفتحان الأرشيف بجهته
  /// فتُرى الفاتورة ومردودها معاً بلا تبديل فلتر يدوي، وأي قيمة أخرى
  /// تُسقط صامتاً كأنها null (عرف stateFilter ذاته).
  String? sideFilter,
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
  final receipt = receiptFilter?.trim() ?? '';
  // س101: قيمتا فلتر الحالة المقبولتان حصراً draft وposted — وأي قيمة
  // أخرى تُسقط كأنها لا فلتر (لا تخمين خفي).
  final state =
      (stateFilter == 'draft' || stateFilter == 'posted') ? stateFilter! : '';
  // س202: فلتر الجهة — القيمتان المقبولتان حصراً sales وpurchases —
  // وأي قيمة أخرى تُسقط كأنها لا فلتر (لا تخمين خفي).
  final side = (sideFilter == 'sales' || sideFilter == 'purchases')
      ? sideFilter!
      : '';
  final rows = await customSelect(
    'SELECT inv.id AS id, inv.kind AS kind, inv.number AS number, '
    'inv.invoice_date AS invoice_date, inv.state AS state, '
    'inv.total_doc_minor AS total_doc_minor, '
    'inv.total_base_minor AS total_base_minor, '
    'c.code AS currency_code, p.name AS party_name, b.name AS box_name, '
    'COALESCE(ls.line_total, 0) AS lines_total, '
    'COALESCE(ls.line_undelivered, 0) AS lines_undelivered '
    'FROM invoices inv '
    'JOIN currencies c ON c.id = inv.currency_id '
    'LEFT JOIN parties p ON p.id = inv.party_id '
    'LEFT JOIN cash_boxes b ON b.id = inv.cash_box_id '
    // الدفعة 21: عدّاد الأسطر لكل فاتورة من الأعمدة القائمة — والمحذوف
    // من الأسطر يستثنى كما قراءة متابعة التسليم (il.is_deleted = 0).
    'LEFT JOIN (SELECT invoice_id, COUNT(*) AS line_total, '
    'SUM(CASE WHEN delivered = 0 THEN 1 ELSE 0 END) '
    'AS line_undelivered FROM invoice_lines WHERE is_deleted = 0 '
    'GROUP BY invoice_id) ls ON ls.invoice_id = inv.id '
    "WHERE inv.is_deleted = 0 "
    "AND (?1 = '' OR inv.kind = ?1) "
    "AND (?2 = '' OR inv.invoice_date >= ?2) "
    "AND (?3 = '' OR inv.invoice_date <= ?3) "
    'AND (?4 IS NULL OR inv.party_id = ?4) '
    // الدفعة 21: فلتر الاستلام الثلاثي — لا فارغ يمر والجزئي حالة
    // مستقلة فلا تخفي الثنائية فاتورة سُلِّم نصفها (قرار المالك س71).
    "AND (?5 = '' OR "
    "(?5 = 'undelivered' AND COALESCE(ls.line_undelivered, 0) = "
    'COALESCE(ls.line_total, 0)) OR '
    "(?5 = 'partial' AND COALESCE(ls.line_undelivered, 0) > 0 "
    'AND COALESCE(ls.line_undelivered, 0) < '
    'COALESCE(ls.line_total, 1)) OR '
    "(?5 = 'received' AND COALESCE(ls.line_total, 0) > 0 "
    'AND COALESCE(ls.line_undelivered, 0) = 0)) '
    "AND (?6 = '' OR inv.state = ?6) "
    // س202: فلتر الجهة — المبيعات ببيعها ومردودها والمشتريات بشرائها
    // ومردودها بIN على القيم المخزنة حرفاً (بلا أي منطق خارج SQL).
    "AND (?7 = '' OR "
    "(?7 = 'sales' AND inv.kind IN ('sale', 'sale_return')) OR "
    "(?7 = 'purchases' AND inv.kind IN ('purchase', 'purchase_return'))) "
    'ORDER BY inv.invoice_date DESC, inv.id DESC',
    variables: [
      Variable.withString(kind),
      Variable.withString(from),
      Variable.withString(to),
      Variable(partyId),
      Variable.withString(receipt),
      Variable.withString(state),
      Variable.withString(side),
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
        linesTotal: r.data['lines_total'] as int,
        linesUndelivered: r.data['lines_undelivered'] as int,
      ),
  ];
}

/// صف قائمة سندات القبض والدفع للعرض (05 §4.2/D-105) — الطرفي وغير الطرفي
/// معاً والمميزان بحقليهما (طرف أو حساب مباشر).
///
/// س-147 (D-135 روحاً، دفعة 13): فلتر الطرف الاختياري — روابط الطرف
/// من الذمم تفتح «سنداته» بهذا الفلتر، وعرضٌ فوق القراءة لا حساب جديد.
/// وس104: فلتر الحالة (كل الحالات / المعلقة «في الطريق» / المرحّلة)
/// بلسان المعتمد الذي يبحث عن تحصيلات المندوبين — عرضٌ فوق القراءة
/// بعرف س101 ذاته فلا تغييراً في الترقيم ولا بأرشيف ما قبله.
Future<List<VoucherListRow>> vouchersListReport({
  String? fromText,
  String? toText,
  int? partyId,
  String? stateFilter,
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
    "AND (?4 = '' OR v.state = ?4) "
    'ORDER BY v.voucher_date DESC, v.id DESC',
    variables: [
      Variable.withString(from),
      Variable.withString(to),
      Variable(partyId),
      Variable.withString(stateFilter?.trim() ?? ''),
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
  // الستة بأعمدة تواريخها (الجلسة سادستها منذ الدفعة 25 — س-19/D-186)،
  // والفواتير بحالتَيها المحسومتين posted/paid
  // (النقدية غير المردودة «paid» فوراً — دفعة 4).
  //
  // س97 — حسم علة الجهاز الموثقة (D-197 بلوق المالك الأول الحرفي
  // «no such table: main.stock_receipts» عند CREATE TRIGGER
  // trg_stock_receipts_closed_period_insert): بذر الجداول قبل الحواجز
  // كان موضعاً في الخطوات (v9/v16) لا في الدالة ذاتها — فمسار يبدأ
  // من v14 مثلاً لا يعيد v9، وخطوة v16 أعادت الحواجز قبل أن تولد
  // جداول الإذنين (v17) فانفجر الافتتاح بدورة أبدية على جهاز المالك.
  // العلاج الجذري: الدالة تؤمّن جداول حواجزها بنفسها قبل أي حاجز —
  // ثلاثة بوانٍ IF NOT EXISTS آمنة التكرار أي مسار وصول وكل بقايا
  // استدعاء خارجي تصير لا-عملية — فقاعدة «حاجز المستند القيدي لا
  // يسبق جدوله» صارت مضمونة ببنية الدالة لا بترتيب مواضع الاستدعاء
  // (درس س79 معمَّم). وجداول مجال المحرك (moves/invoices/vouchers/
  // cash_adjustments) من مخطط التهيئة القديم فقائمة على كل مسار.
  // وكل جدول يُضاف مستقبلاً إلى docTables يجب أن يبذر بانيته هنا
  // قبل الحاجز — لا في خطوة الترحيلة — إلزاماً.
  await _createTransferTables();
  await _createCountTables();
  await _createMovementDocTables();
  const docTables = <(String, String, String)>[
    ('moves', 'date_text', "'posted'"),
    ('invoices', 'invoice_date', "'posted', 'paid'"),
    ('vouchers', 'voucher_date', "'posted'"),
    ('box_transfers', 'transfer_date', "'posted'"),
    ('cash_adjustments', 'adjustment_date', "'posted'"),
    // الدفعة 25 (س-19/D-186): جلسة الجرد تُرحّل قيداً محاسبياً فتاريخها
    // تحكمه الفترة خلافاً للتحويل بلا قيد — الإدراج المرحّل مباشرة
    // والانتقال جارٍ→مرحّل كلاهما محجوبان بفترة مقفلة.
    ('stock_counts', 'count_date', "'posted'"),
    // الدفعة 26 (F-209/F-210 س85/D-189): الإذنان سابع وثامن المستندات
    // القيدية — يُنشآن مرحّلين مباشرة (بلا مسودة) فالحاجز على الإدراج
    // وحده، والانتقال state→posted محجوب احتياطاً كالجلسة.
    ('stock_receipts', 'receipt_date', "'posted'"),
    ('stock_issues', 'issue_date', "'posted'"),
  ];
  for (final (table, dateColumn, committedStates) in docTables) {
    final periodClosed = '(SELECT p.state FROM periods p '
        'WHERE p.is_deleted = 0 '
        'AND p.start_date_text <= NEW.$dateColumn '
        'AND p.end_date_text >= NEW.$dateColumn LIMIT 1) = '
        "'closed'";
    // الدفعة 32 (تاسعة م2/س-21/F-077): قيود الإقفال السنوي الثلاثة
    // مرحّلة بتاريخ ذي الحجة داخل فترتها المقفلة لأنها جزء من عملية
    // الإقفال ذاتها — فالإعفاء على جدول moves حصراً وبمرجع
    // ref_doc_type = 'fiscal_year' حصراً، وهو ما يكتبه محرك الإقفال
    // وحده (وحاجز المحرك bypassClosedPeriod مضبوط على المسار ذاته —
    // قفلٌ مزدوج: لا مسار آخر يكتب المرجع ولا يمرر الاستثناء).
    final exemption = table == 'moves'
        ? " AND COALESCE(NEW.ref_doc_type,'') <> 'fiscal_year'"
        : '';
    await customStatement(
        'DROP TRIGGER IF EXISTS trg_${table}_closed_period_insert');
    await customStatement(
        'DROP TRIGGER IF EXISTS trg_${table}_closed_period_post');
    await customStatement(
      'CREATE TRIGGER trg_${table}_closed_period_insert '
      'BEFORE INSERT ON $table FOR EACH ROW '
      "WHEN NEW.state IN ($committedStates) AND $periodClosed$exemption "
      "BEGIN SELECT RAISE(ABORT, 'فترة مقفلة: لا ترحيل فيها "
      "(حاجز القاعدة) (DQ-0601)'); END",
    );
    await customStatement(
      'CREATE TRIGGER trg_${table}_closed_period_post '
      'BEFORE UPDATE OF state ON $table FOR EACH ROW '
      "WHEN NEW.state IN ($committedStates) "
      'AND OLD.state NOT IN ($committedStates) AND $periodClosed$exemption '
      "BEGIN SELECT RAISE(ABORT, 'فترة مقفلة: لا ترحيل فيها "
      "(حاجز القاعدة) (DQ-0601)'); END",
    );
  }
}
// ═══════════════════════════════════════════════════════════════
// استيراد البيانات — النواة (D-208/§25.11 — الدفعة الأولى من ثلاث):
// التخطيط من قراءات القاعدة الحية ثم التنفيذ بمعاملة واحدة كل-أو-لا
// شيء (07 §2.4) وحدث الاستيراد بنفس المعاملة (لا حدث بلا عملية ولا
// عملية بلا حدث — D-076) والنسخة الحدثية شرط اعتماد (§25.6).
// ═══════════════════════════════════════════════════════════════


/// مرجع العملات الحية للاستيراد — المعطل لا يُستورد إليه: عملة
/// الاستيراد يجب أن تكون حية بجدول العملات (فحص المرجع §25.5).
Future<Map<String, ImportCurrencyRef>> importCurrencyIndex() async {
  final index = <String, ImportCurrencyRef>{};
  for (final r in await currenciesOf()) {
    index[normalizeCurrencyCode(r.code)] = ImportCurrencyRef(
      id: r.id,
      code: r.code,
      minorUnits: r.minorUnits,
    );
  }
  return index;
}

/// تخطيط استيراد الأطراف من القاعدة — الفهارس من قراءاتها الحية
/// (المعطل يبقى بالفهرس: اسمه ورقمه محجوزان ما دام الصف حياً — س-33)
/// ثم التخطيط النقي بأكمله.
Future<PartiesImportPlan> planPartiesImportFromDb(
  PartiesFileParse parse, {
  required ImportExistingPolicy policy,
}) async {
  final rows = await customSelect(
    'SELECT id, number, name, is_active FROM parties WHERE is_deleted = 0',
  ).get();
  final index = PartyUniquenessIndex.build([
    for (final r in rows)
      ExistingParty(
        id: r.data['id'] as int,
        number: r.data['number'] as String,
        name: r.data['name'] as String,
        isActive: (r.data['is_active'] as int) == 1,
      ),
  ]);
  return planPartiesImport(
    parse,
    currencies: await importCurrencyIndex(),
    existing: index,
    policy: policy,
  );
}

/// تخطيط استيراد الأصناف من القاعدة — وحدات وتفاصيل الأصناف القائمة
/// (الوحدة والأسعار وعملتها) للفروق الحقيقية ولحارس وحدة الصنف.
Future<ItemsImportPlan> planItemsImportFromDb(
  ItemsFileParse parse, {
  required ImportExistingPolicy policy,
}) async {
  final unitRows = await customSelect(
    'SELECT id, name FROM units WHERE is_deleted = 0',
  ).get();
  final unitIndex = UnitUniquenessIndex.build([
    for (final r in unitRows)
      ExistingUnit(
        id: r.data['id'] as int,
        name: r.data['name'] as String,
        isActive: true,
      ),
  ]);
  final itemRows = await customSelect(
    'SELECT i.id, i.sku, i.name, i.purchase_price_minor, '
    'i.sale_price_minor, i.price_currency_id, u.name AS unit_name '
    'FROM items i LEFT JOIN units u ON u.id = i.base_unit_id '
    'WHERE i.is_deleted = 0',
  ).get();
  final details = <int, ExistingItemImportRef>{};
  final forIndex = <ExistingItem>[];
  for (final r in itemRows) {
    final id = r.data['id'] as int;
    forIndex.add(ExistingItem(
      id: id,
      sku: r.data['sku'] as String,
      name: r.data['name'] as String,
      isActive: true,
    ));
    details[id] = ExistingItemImportRef(
      id: id,
      sku: r.data['sku'] as String,
      name: r.data['name'] as String,
      unitName: (r.data['unit_name'] as String?) ?? '',
      purchasePriceMinor: r.data['purchase_price_minor'] as int,
      salePriceMinor: r.data['sale_price_minor'] as int,
      priceCurrencyId: r.data['price_currency_id'] as int,
    );
  }
  return planItemsImport(
    parse,
    currencies: await importCurrencyIndex(),
    existing: ItemUniquenessIndex.build(forIndex),
    units: unitIndex,
    existingDetails: details,
    policy: policy,
  );
}

/// تنفيذ استيراد الأطراف — معاملة واحدة: إعادة تحقق حية ثم الإدراج
/// والتحديث ثم حدث الاستيراد بنفس المعاملة. أي اصطدام بالحية يرفع
/// [ImportExecutionException] فترجع المعاملة كلها بلا أي كتابة.
///
/// [eventBackupName] اسم النسخة الحدثية قبل الاعتماد — لا اعتماد
/// بلا نسخة (§25.6) حرساً ثانوياً بعد بوابة الواجهة.
Future<ImportExecutionResult> executePartiesImport(
  PartiesImportPlan plan, {
  required String eventBackupName,
  int? userId,
}) {
  assert(eventBackupName.trim().isNotEmpty,
      'لا اعتماد بلا نسخة حدثية (§25.6)');
  return transaction(() async {
    final live = await customSelect(
      'SELECT id, number, name, is_active FROM parties WHERE is_deleted = 0',
    ).get();
    final liveIndex = PartyUniquenessIndex.build([
      for (final r in live)
        ExistingParty(
          id: r.data['id'] as int,
          number: r.data['number'] as String,
          name: r.data['name'] as String,
          isActive: (r.data['is_active'] as int) == 1,
        ),
    ]);
    for (final c in plan.creates) {
      final byNumber = liveIndex.byNumberKey(c.number);
      if (byNumber != null) {
        throw ImportExecutionException(
            'الكود ${c.number} مستخدم للطرف: ${byNumber.displayLabel} '
            '— القاعدة تغيرت بين المعاينة والاعتماد.');
      }
      final byName = liveIndex.byLiteralName(c.name);
      if (byName != null) {
        throw ImportExecutionException('الاسم «${c.name}» مستخدم '
            'للطرف: ${byName.displayLabel}.');
      }
    }
    var created = 0;
    for (final c in plan.creates) {
      await insertParty(
        number: c.number,
        name: c.name,
        kind: c.kindStorage,
        defaultCurrencyId: c.currencyId,
        creditLimitBaseMinor: c.creditLimitBaseMinor,
      );
      created++;
    }
    var updated = 0;
    for (final u in plan.updates) {
      final row = await (select(parties)..where((t) =>
          t.id.equals(u.partyId) & t.isDeleted.equals(false)))
          .getSingleOrNull();
      if (row == null) {
        throw const ImportExecutionException('الطرف المزمع تحديثه غاب '
            'عن القاعدة بين المعاينة والاعتماد.');
      }
      // التحديث وصفيّات v1 حصراً: الاسم (د-2) — لا مساس بالرقم ولا
      // بالنوع ولا بالعملة ولا بحد الائتمان من هذا المسار.
      await (update(parties)..where((t) => t.id.equals(u.partyId))).write(
        PartiesCompanion(
          name: Value(sanitizeFreeName(u.newName)),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      updated++;
    }
    await recordSystemEvent('import_performed', userId: userId, payload: {
      'unit': 'parties',
      'template': 'parties,1',
      'separator': plan.semicolonUsed ? '؛' : ',',
      'policy': importPolicyLabel(plan.policy),
      'rows': plan.totalDataRows,
      'created': created,
      'updated': updated,
      'skipped': plan.skipped.length,
      'event_backup': eventBackupName,
      if (plan.overSoftLimit) 'warning': 'over_soft_limit',
    });
    return ImportExecutionResult(
      created: created,
      updated: updated,
      skipped: plan.skipped.length,
    );
  });
}

/// تنفيذ استيراد الأصناف — معاملة واحدة: وحدات الخطة الآلية أولاً
/// (القائمة بمعرّفها والغائب يُنشأ بوحدة أساسية بعامل 1 — §25.4)
/// ثم الأصناف الجديدة بالبضاعة حصراً (حد موثق v1) ثم التحديثات
/// الوصفية (الاسم والسعران — د-2) ثم حدث الاستيراد.
Future<ImportExecutionResult> executeItemsImport(
  ItemsImportPlan plan, {
  required String eventBackupName,
  int? userId,
}) {
  assert(eventBackupName.trim().isNotEmpty,
      'لا اعتماد بلا نسخة حدثية (§25.6)');
  return transaction(() async {
    final unitIdByName = <String, int>{};
    for (final r
        in await customSelect('SELECT id, name FROM units WHERE is_deleted = 0')
            .get()) {
      unitIdByName[(r.data['name'] as String).trim()] = r.data['id'] as int;
    }
    for (final name in plan.unitCreates) {
      if (unitIdByName.containsKey(name)) {
        // أُنشئت بين المعاينة والاعتماد — تُعاد بمعرّفها لا تكرار.
        continue;
      }
      unitIdByName[name] = await insertUnit(name: name);
    }
    final liveRows = await customSelect(
      'SELECT id, sku, name FROM items WHERE is_deleted = 0',
    ).get();
    final liveBySku = <String, ExistingItem>{};
    final liveByName = <String, ExistingItem>{};
    for (final r in liveRows) {
      final it = ExistingItem(
        id: r.data['id'] as int,
        sku: r.data['sku'] as String,
        name: r.data['name'] as String,
        isActive: true,
      );
      liveBySku.putIfAbsent(it.skuKey, () => it);
      final nameKey = it.name.trim();
      if (nameKey.isNotEmpty) liveByName.putIfAbsent(nameKey, () => it);
    }
    for (final c in plan.creates) {
      final skuHolder = liveBySku[itemSkuKey(c.sku)];
      if (skuHolder != null) {
        throw ImportExecutionException('الكود ${c.sku} مستخدم للصنف: '
            '${skuHolder.displayLabel} — القاعدة تغيرت بين المعاينة '
            'والاعتماد.');
      }
      final nameHolder = liveByName[c.name.trim()];
      if (nameHolder != null) {
        throw ImportExecutionException('الاسم «${c.name}» مستخدم '
            'للصنف: ${nameHolder.displayLabel}.');
      }
      final unitId = c.baseUnitId != -1
          ? c.baseUnitId
          : unitIdByName[c.unitName];
      if (unitId == null) {
        throw ImportExecutionException('وحدة الصنف ${c.sku} غابت بين '
            'المعاينة والاعتماد.');
      }
      await insertItem(
        sku: c.sku,
        name: c.name,
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: c.purchasePriceMinor,
        salePriceMinor: c.salePriceMinor,
        priceCurrencyId: c.priceCurrencyId,
      );
    }
    var updated = 0;
    for (final u in plan.updates) {
      final row = await (select(items)..where((t) =>
          t.id.equals(u.itemId) & t.isDeleted.equals(false)))
          .getSingleOrNull();
      if (row == null) {
        throw const ImportExecutionException('الصنف المزمع تحديثه غاب '
            'عن القاعدة بين المعاينة والاعتماد.');
      }
      await (update(items)..where((t) => t.id.equals(u.itemId))).write(
        ItemsCompanion(
          name: u.newName == null
              ? const Value.absent()
              : Value(sanitizeFreeName(u.newName!)),
          purchasePriceMinor: u.newPurchasePriceMinor == null
              ? const Value.absent()
              : Value(u.newPurchasePriceMinor!),
          salePriceMinor: u.newSalePriceMinor == null
              ? const Value.absent()
              : Value(u.newSalePriceMinor!),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      updated++;
    }
    await recordSystemEvent('import_performed', userId: userId, payload: {
      'unit': 'items',
      'template': 'items,1',
      'separator': plan.semicolonUsed ? '؛' : ',',
      'policy': importPolicyLabel(plan.policy),
      'rows': plan.totalDataRows,
      'unit_created': plan.unitCreates.length,
      'created': plan.creates.length,
      'updated': updated,
      'skipped': plan.skipped.length,
      'event_backup': eventBackupName,
      if (plan.overSoftLimit) 'warning': 'over_soft_limit',
    });
    return ImportExecutionResult(
      created: plan.creates.length,
      updated: updated,
      skipped: plan.skipped.length,
    );
  });
}

// ═══════════════════════════════════════════════════════════════
// استيراد أرصدة أول المدة (D-208/§25.11 — الدفعة الثانية س141):
// الوحدتان 4 و5 — التخطيط من قراءات القاعدة الحية والتنفيذ بمعاملة
// واحدة كل-أو-لا شيء عبر المحرك الموحد حصراً (07 §1.1): قيد الذمم
// 112/211 بأسطر طرف + مقابل 332 آلي (د-1/د-6)، وإذن إدخال واحد
// للكميات بقيمها الصريحة، والنقد يفتح صناديق عملاته بمعاملته
// (05 §3.3)، وحدث الاستيراد بنفس المعاملة (D-076).
// ═══════════════════════════════════════════════════════════════

/// أقدم قيد مرحّل بتاريخه — «الافتتاحي أول مستند مرحّل» (د-6) يفحصه.
Future<String?> earliestPostedMoveDateText() async {
  final rows = await customSelect(
    "SELECT MIN(date_text) AS d FROM moves WHERE state = 'posted'",
  ).get();
  final d = rows.first.data['d'];
  return d == null ? null : d as String;
}

/// بداية أقدم فترة مفتوحة — الافتراض الموثق لتاريخ الافتتاحي بالواجهة
/// وللمتابعة سادسة (§25.9: للإقرار أو التعديل قبل الترحيل).
Future<String?> earliestOpenPeriodStartText() async {
  PeriodInfo? earliest;
  for (final p in await ledgerPeriods()) {
    if (!p.isOpen) continue;
    if (earliest == null ||
        p.startDateText.compareTo(earliest.startDateText) < 0) {
      earliest = p;
    }
  }
  return earliest?.startDateText;
}

/// آخر سعر مسجل لكل عملة أجنبية مكبَّراً — لتحذير انحراف المعاينة
/// (§25.4): قيم مخزنة حقيقة لا حساب جديد.
Future<Map<String, int>> latestImportRatesByCurrency() async {
  final rows = await customSelect(
    "SELECT c.code AS code, e.rate_to_base AS rate FROM currencies c "
    "JOIN exchange_rate e ON e.currency_id = c.id "
    "WHERE c.is_deleted = 0 AND c.is_base = 0 AND e.is_deleted = 0 "
    "AND e.date = (SELECT MAX(e2.date) FROM exchange_rate e2 "
    "WHERE e2.currency_id = c.id AND e2.is_deleted = 0)",
  ).get();
  return {
    for (final r in rows)
      normalizeCurrencyCode(r.data['code'] as String):
          r.data['rate'] as int,
  };
}

/// سياق التاريخ الافتتاحي الحي — يُبنى لحظة التخطيط (د-6).
Future<OpeningImportDateContext> _openingDateContextNow(
    String openingDateText) async {
  return OpeningImportDateContext(
    openingDateText: openingDateText,
    periods: await ledgerPeriods(),
    earliestPostedDateText: await earliestPostedMoveDateText(),
  );
}

/// تخطيط أرصدة الذمم من القاعدة الحية — فهرس الأطراف بأنواعها
/// (لفرق النوع المعروض) ومرجع العملات وآخر أسعارها المسجلة.
Future<PartyBalancesImportPlan> planPartyBalancesImportFromDb(
  PartyBalancesFileParse parse, {
  required String openingDateText,
}) async {
  final partyRows = await customSelect(
    'SELECT id, number, name, kind, is_active FROM parties '
    'WHERE is_deleted = 0',
  ).get();
  return planPartyBalancesImport(
    parse,
    currencies: await importCurrencyIndex(),
    existing: PartyUniquenessIndex.build([
      for (final r in partyRows)
        ExistingParty(
          id: r.data['id'] as int,
          number: r.data['number'] as String,
          name: r.data['name'] as String,
          isActive: (r.data['is_active'] as int) == 1,
        ),
    ]),
    dateContext: await _openingDateContextNow(openingDateText),
    existingKindByNumberKey: {
      for (final r in partyRows)
        partyNumberKey(r.data['number'] as String):
            r.data['kind'] as String,
    },
    latestRateByCurrency: await latestImportRatesByCurrency(),
  );
}

/// تخطيط الأرصدة الكاملة من القاعدة الحية — فهارس الأطراف والأصناف
/// بوحداتها وتفاصيلها ومرجع العملات وآخر أسعارها المسجلة.
Future<OpeningFullImportPlan> planOpeningFullImportFromDb(
  OpeningFullFileParse parse, {
  required String openingDateText,
}) async {
  final partyRows = await customSelect(
    'SELECT id, number, name, kind, is_active FROM parties '
    'WHERE is_deleted = 0',
  ).get();
  final unitRows = await customSelect(
    'SELECT id, name FROM units WHERE is_deleted = 0',
  ).get();
  final itemRows = await customSelect(
    'SELECT i.id, i.sku, i.name, i.purchase_price_minor, '
    'i.sale_price_minor, i.price_currency_id, u.name AS unit_name '
    'FROM items i LEFT JOIN units u ON u.id = i.base_unit_id '
    'WHERE i.is_deleted = 0',
  ).get();
  final details = <int, ExistingItemImportRef>{};
  final forIndex = <ExistingItem>[];
  for (final r in itemRows) {
    final id = r.data['id'] as int;
    forIndex.add(ExistingItem(
      id: id,
      sku: r.data['sku'] as String,
      name: r.data['name'] as String,
      isActive: true,
    ));
    details[id] = ExistingItemImportRef(
      id: id,
      sku: r.data['sku'] as String,
      name: r.data['name'] as String,
      unitName: (r.data['unit_name'] as String?) ?? '',
      purchasePriceMinor: r.data['purchase_price_minor'] as int,
      salePriceMinor: r.data['sale_price_minor'] as int,
      priceCurrencyId: r.data['price_currency_id'] as int,
    );
  }
  return planOpeningFullImport(
    parse,
    currencies: await importCurrencyIndex(),
    existingParties: PartyUniquenessIndex.build([
      for (final r in partyRows)
        ExistingParty(
          id: r.data['id'] as int,
          number: r.data['number'] as String,
          name: r.data['name'] as String,
          isActive: (r.data['is_active'] as int) == 1,
        ),
    ]),
    existingPartyKindByNumberKey: {
      for (final r in partyRows)
        partyNumberKey(r.data['number'] as String):
            r.data['kind'] as String,
    },
    existingItems: ItemUniquenessIndex.build(forIndex),
    existingItemDetails: details,
    units: UnitUniquenessIndex.build([
      for (final r in unitRows)
        ExistingUnit(
          id: r.data['id'] as int,
          name: r.data['name'] as String,
          isActive: true,
        ),
    ]),
    dateContext: await _openingDateContextNow(openingDateText),
    latestRateByCurrency: await latestImportRatesByCurrency(),
  );
}

/// لقطة أسعار الملف بالسجل التاريخي بتاريخ الافتتاحي (07 §1.7 — س141):
/// المحفوظ ليومٍ بعينه لا يُعدل أبداً (F-121)، والأساسية لا يقيس لها
/// سعر، والمستقبلية تحملها سطور القيد حصراً فالتسجيل لليوم أو الماضي.
Future<void> _recordOpeningFxRatesWithinTx({
  required List<({int currencyId, int rateToBase})> rates,
  required String openingDateText,
}) async {
  final day = openingDateText.trim();
  if (!isValidIsoDate(day)) return;
  if (day.compareTo(todayIsoDate()) > 0) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final r in rates) {
    if (r.currencyId <= 1 || r.rateToBase <= 0) continue;
    final dup = await customSelect(
      'SELECT id FROM exchange_rate WHERE currency_id = ? AND date = ?',
      variables: [Variable.withInt(r.currencyId), Variable.withString(day)],
    ).get();
    if (dup.isNotEmpty) continue;
    await customStatement(
      'INSERT INTO exchange_rate (currency_id, date, rate_to_base, uuid, '
      'created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, 0)',
      [r.currencyId, day, r.rateToBase, const Uuid().v4(), now, now],
    );
  }
}

/// تنفيذ استيراد أرصدة الذمم — الوحدة 4: معاملة واحدة كل-أو-لا شيء،
/// الطرف الغائب يُنشأ آلياً، والقيد يمر بالمحرك الموحد (112/211 بأسطر
/// طرف party_id بلقطة عملتها وسعرها + مقابل 332 آلياً بجهته — د-1/د-6)
/// وحدث الاستيراد بنفس المعاملة (D-076).
Future<ImportOpeningResult> executePartyBalancesImport(
  PartyBalancesImportPlan plan, {
  required String eventBackupName,
  int? userId,
}) {
  assert(eventBackupName.trim().isNotEmpty,
      'لا اعتماد بلا نسخة حدثية (§25.6)');
  return transaction(() async {
    // إعادة تحقق حية بالتاريخ أولاً (د-6): القاعدة قد تُرحّل بين
    // المعاينة والاعتماد فالافتتاحي يظل أول المرحّل حرفاً.
    final dateErrors = validateOpeningDateForImport(
        await _openingDateContextNow(plan.openingDateText));
    if (dateErrors.isNotEmpty) {
      throw ImportExecutionException(
          'تاريخ الافتتاحي لم يعد صالحاً: '
          '${dateErrors.first.description}');
    }
    final live = await customSelect(
      'SELECT id, number, name, is_active FROM parties '
      'WHERE is_deleted = 0',
    ).get();
    final liveIndex = PartyUniquenessIndex.build([
      for (final r in live)
        ExistingParty(
          id: r.data['id'] as int,
          number: r.data['number'] as String,
          name: r.data['name'] as String,
          isActive: (r.data['is_active'] as int) == 1,
        ),
    ]);
    final liveIds = <int>{for (final r in live) r.data['id'] as int};
    final currenciesById = {
      for (final ref in (await importCurrencyIndex()).values) ref.id: ref,
    };
    final acc112 = await _accountIdByCodeTx('112');
    final acc211 = await _accountIdByCodeTx('211');
    final acc332 = await _accountIdByCodeTx('332');

    var partiesCreated = 0;
    final moveLines = <MoveLineDraft>[];
    var debitTotal = 0;
    var creditTotal = 0;
    final fxSnapshots = <({int currencyId, int rateToBase})>{};
    for (final line in plan.lines) {
      if (currenciesById[line.currencyId] == null) {
        throw ImportExecutionException('العملة (المعرف ${line.currencyId}) '
            'غابت عن القاعدة بين المعاينة والاعتماد.');
      }
      fxSnapshots.add(
          (currencyId: line.currencyId, rateToBase: line.fxRate));
      int partyId;
      if (line.partyId != null) {
        if (!liveIds.contains(line.partyId)) {
          throw ImportExecutionException('الطرف ${line.code} غاب عن '
              'القاعدة بين المعاينة والاعتماد.');
        }
        partyId = line.partyId!;
      } else {
        final byNumber = liveIndex.byNumberKey(line.code);
        if (byNumber != null) {
          throw ImportExecutionException('الكود ${line.code} مستخدم '
              'للطرف: ${byNumber.displayLabel} — القاعدة تغيرت بين '
              'المعاينة والاعتماد.');
        }
        final byName = liveIndex.byLiteralName(line.name);
        if (byName != null) {
          throw ImportExecutionException('الاسم «${line.name}» مستخدم '
              'للطرف: ${byName.displayLabel}.');
        }
        partyId = await insertParty(
          number: line.code,
          name: line.name,
          kind: line.kindStorage,
          defaultCurrencyId: line.currencyId,
        );
        partiesCreated++;
      }
      moveLines.add(MoveLineDraft(
        accountId: line.debit ? acc112 : acc211,
        partyId: partyId,
        debitMinor: line.debit ? line.baseMinor : 0,
        creditMinor: line.debit ? 0 : line.baseMinor,
        currencyId: line.currencyId,
        amountMinor: line.docMinor,
        fxRate: line.fxRate,
      ));
      if (line.debit) {
        debitTotal += line.baseMinor;
      } else {
        creditTotal += line.baseMinor;
      }
    }
    if (moveLines.isEmpty) {
      throw const ImportExecutionException('لا أسطر رصص بالخطة — لا '
          'استيراد بلا أثر محاسبي.');
    }
    // مقابل 332 الآلي (د-1/د-6) — سطر واحد بالجهة التي تمسك التوازن.
    final counterpart = debitTotal - creditTotal;
    if (counterpart > 0) {
      moveLines.add(MoveLineDraft(
        accountId: acc332,
        creditMinor: counterpart,
        currencyId: 1,
        amountMinor: counterpart,
      ));
    } else if (counterpart < 0) {
      moveLines.add(MoveLineDraft(
        accountId: acc332,
        debitMinor: -counterpart,
        currencyId: 1,
        amountMinor: -counterpart,
      ));
    }
    final moveId = await _insertMoveDraftWithinTx(MoveDraft(
      journalId: await _journalIdByCodeTx('general'),
      dateText: plan.openingDateText,
      narration: 'قيد أرصدة أول المدة — الذمم (استيراد)',
      refDocType: 'import_opening',
      lines: moveLines,
    ));
    await _postMoveWithinTx(moveId, sequenceKind: ledgerMoveSequenceKind);
    final moveNumber = (await customSelect(
      'SELECT number FROM moves WHERE id = ?',
      variables: [Variable.withInt(moveId)],
    ).getSingle()).data['number'] as String;

    await _recordOpeningFxRatesWithinTx(
      rates: fxSnapshots.toList(),
      openingDateText: plan.openingDateText,
    );
    await recordSystemEvent('import_performed', userId: userId, payload: {
      'unit': 'party_balances',
      'template': 'party_balances,1',
      'separator': plan.semicolonUsed ? '؛' : ',',
      'rows': plan.totalDataRows,
      'parties_created': partiesCreated,
      'move_number': moveNumber,
      'opening_date': plan.openingDateText,
      'debit_base': debitTotal,
      'credit_base': creditTotal,
      'event_backup': eventBackupName,
      if (plan.overSoftLimit) 'warning': 'over_soft_limit',
    });
    return ImportOpeningResult(
      partiesCreated: partiesCreated,
      itemsCreated: 0,
      unitsCreated: 0,
      boxesCreated: 0,
      moveNumber: moveNumber,
      receiptNumber: null,
      debitBaseMinor: debitTotal,
      creditBaseMinor: creditTotal,
    );
  });
}

/// تنفيذ استيراد الأرصدة الكاملة — الوحدة 5: معاملة واحدة كل-أو-لا
/// شيء: وحدات وأصناف وأطراف تنشأ آلياً، ثم إذن إدخال واحد للكميات
/// بقيم ملفها الصريحة ومقابله 332 (د-1)، والنقد يفتح صناديق عملاته
/// بمعاملته (05 §3.3 — _createCashBoxWithinTx)، ثم قيد الذمم والنقد
/// بمقابل 332 — وبمجموع القيدين يمسك الميزان (07 §1.1).
Future<ImportOpeningResult> executeOpeningFullImport(
  OpeningFullImportPlan plan, {
  required String eventBackupName,
  int? userId,
}) {
  assert(eventBackupName.trim().isNotEmpty,
      'لا اعتماد بلا نسخة حدثية (§25.6)');
  return transaction(() async {
    final dateErrors = validateOpeningDateForImport(
        await _openingDateContextNow(plan.openingDateText));
    if (dateErrors.isNotEmpty) {
      throw ImportExecutionException(
          'تاريخ الافتتاحي لم يعد صالحاً: '
          '${dateErrors.first.description}');
    }
    final currenciesById = {
      for (final ref in (await importCurrencyIndex()).values) ref.id: ref,
    };

    // الوحدات: القائمة بمعرفها والغائب ينشأ آلياً مرة واحدة (§25.4).
    final unitIdByName = <String, int>{};
    for (final r in await customSelect(
            'SELECT id, name FROM units WHERE is_deleted = 0')
        .get()) {
      unitIdByName[(r.data['name'] as String).trim()] =
          r.data['id'] as int;
    }
    var unitsCreated = 0;
    for (final name in plan.unitCreates) {
      if (unitIdByName.containsKey(name)) continue;
      unitIdByName[name] = await insertUnit(name: name);
      unitsCreated++;
    }

    // الأصناف: القائمة تُرفق، والغائب ينشأ بضاعة بلا أسعار (حد موثق —
    // قيمة الافتتاحي من الملف لا من سعر الصنف).
    final liveItems = await customSelect(
      'SELECT id, sku, name FROM items WHERE is_deleted = 0',
    ).get();
    final liveItemBySku = <String, int>{};
    final liveItemByName = <String, int>{};
    for (final r in liveItems) {
      liveItemBySku[itemSkuKey(r.data['sku'] as String)] =
          r.data['id'] as int;
      final nameKey = (r.data['name'] as String).trim();
      if (nameKey.isNotEmpty) {
        liveItemByName.putIfAbsent(nameKey, () => r.data['id'] as int);
      }
    }
    var itemsCreated = 0;
    final itemIdBySku = <String, int>{};
    for (final c in plan.itemCreates) {
      final skuHolder = liveItemBySku[itemSkuKey(c.sku)];
      if (skuHolder != null) {
        // أُنشئ بين المعاينة والاعتماد — يُرفق به لا يكرر.
        itemIdBySku[itemSkuKey(c.sku)] = skuHolder;
        continue;
      }
      if (liveItemByName.containsKey(c.name.trim())) {
        throw ImportExecutionException('الاسم «${c.name}» مستخدم لصنف '
            'قائم — القاعدة تغيرت بين المعاينة والاعتماد.');
      }
      final unitId = c.baseUnitId != -1
          ? c.baseUnitId
          : unitIdByName[c.unitName];
      if (unitId == null) {
        throw ImportExecutionException('وحدة الصنف ${c.sku} غابت بين '
            'المعاينة والاعتماد.');
      }
      final id = await insertItem(
        sku: c.sku,
        name: c.name,
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: c.purchasePriceMinor,
        salePriceMinor: c.salePriceMinor,
        priceCurrencyId: c.priceCurrencyId,
      );
      itemIdBySku[itemSkuKey(c.sku)] = id;
      itemsCreated++;
    }

    // الأطراف: القائمة تُرفق والغائب ينشأ آلياً (§25.2).
    final liveParties = await customSelect(
      'SELECT id, number, name, is_active FROM parties '
      'WHERE is_deleted = 0',
    ).get();
    final livePartyIndex = PartyUniquenessIndex.build([
      for (final r in liveParties)
        ExistingParty(
          id: r.data['id'] as int,
          number: r.data['number'] as String,
          name: r.data['name'] as String,
          isActive: (r.data['is_active'] as int) == 1,
        ),
    ]);
    final livePartyIds = <int>{
      for (final r in liveParties) r.data['id'] as int
    };
    var partiesCreated = 0;
    final partyIdByCode = <String, int>{};
    for (final c in plan.partyCreates) {
      final byNumber = livePartyIndex.byNumberKey(c.number);
      if (byNumber != null) {
        partyIdByCode[partyNumberKey(c.number)] = byNumber.id;
        continue;
      }
      final byName = livePartyIndex.byLiteralName(c.name);
      if (byName != null) {
        throw ImportExecutionException('الاسم «${c.name}» مستخدم للطرف: '
            '${byName.displayLabel} — القاعدة تغيرت بين المعاينة '
            'والاعتماد.');
      }
      partyIdByCode[partyNumberKey(c.number)] = await insertParty(
        number: c.number,
        name: c.name,
        kind: c.kindStorage,
        defaultCurrencyId: c.currencyId,
      );
      partiesCreated++;
    }

    // إذن الإدخال الواحد — بقيم الملف الصريحة ومقابله 332 (د-1).
    String? receiptNumber;
    if (plan.inventoryLines.isNotEmpty) {
      final wh = await customSelect(
        "SELECT id FROM warehouses WHERE is_deleted = 0 AND is_active = 1 "
        "ORDER BY id LIMIT 1",
      ).get();
      if (wh.isEmpty) {
        throw const ImportExecutionException(
            'لا مستودع نشط لإذن إدخال الأرصدة الافتتاحية.');
      }
      final acc332 = await _accountIdByCodeTx('332');
      final receiptId = await _stockReceiptPostWithinTx(StockReceiptDraft(
        dateText: plan.openingDateText,
        warehouseId: wh.first.data['id'] as int,
        reason: 'استيراد أرصدة أول المدة',
        counterAccountId: acc332,
        narration: 'إذن إدخال الأرصدة الافتتاحية — بقيم الملف',
        lines: [
          for (final line in plan.inventoryLines)
            StockDocLineDraft(
              itemId: line.itemId ??
                  itemIdBySku[itemSkuKey(line.sku)] ??
                  (liveItemBySku[itemSkuKey(line.sku)] ?? -1),
              qtyBase: line.qtyBase,
              valueBaseMinor: line.valueBaseMinor,
            ),
        ],
      ));
      receiptNumber = (await customSelect(
        'SELECT number FROM stock_receipts WHERE id = ?',
        variables: [Variable.withInt(receiptId)],
      ).getSingle()).data['number'] as String;
    }

    // النقد يفتح صناديق عملاته بمعاملته (05 §3.3) — والصندوق القائم
    // بحسابه هو المستقر، وحركة الصندوق تكتب مع قيمه فلا يكفي الدفتر
    // (05 §4.2 نمط الفواتير: الرصيد المُدار بحركاته هو رصيد الصندوق).
    final boxIdByCurrency = <int, int>{};
    final boxAccountIdByCurrency = <int, int>{};
    for (final r in await customSelect(
            'SELECT id, currency_id, account_id FROM cash_boxes '
            'WHERE is_deleted = 0 ORDER BY id')
        .get()) {
      boxIdByCurrency.putIfAbsent(
          r.data['currency_id'] as int, () => r.data['id'] as int);
      boxAccountIdByCurrency.putIfAbsent(
          r.data['currency_id'] as int, () => r.data['account_id'] as int);
    }
    var boxesCreated = 0;
    for (final line in plan.cashLines) {
      if (boxAccountIdByCurrency.containsKey(line.currencyId)) continue;
      if (currenciesById[line.currencyId] == null) {
        throw ImportExecutionException('عملة النقد (المعرف '
            '${line.currencyId}) غابت عن القاعدة بين المعاينة والاعتماد.');
      }
      final boxId = await _createCashBoxWithinTx(
        name: 'صندوق ${line.currencyCode}',
        currencyId: line.currencyId,
      );
      final accountId = (await customSelect(
        'SELECT account_id FROM cash_boxes WHERE id = ?',
        variables: [Variable.withInt(boxId)],
      ).getSingle()).data['account_id'] as int;
      boxIdByCurrency[line.currencyId] = boxId;
      boxAccountIdByCurrency[line.currencyId] = accountId;
      boxesCreated++;
    }

    // قيد الذمم والنقد — 112/211 بأسطر طرف + صناديق النقد مدينة
    // بلقطات عملاتها وأسعارها + مقابل 332 بجهته (07 §1.7/د-1).
    final acc112 = await _accountIdByCodeTx('112');
    final acc211 = await _accountIdByCodeTx('211');
    final acc332 = await _accountIdByCodeTx('332');
    final moveLines = <MoveLineDraft>[];
    var debitTotal = 0;
    var creditTotal = 0;
    final fxSnapshots = <({int currencyId, int rateToBase})>{};
    for (final line in plan.partyLines) {
      if (currenciesById[line.currencyId] == null) {
        throw ImportExecutionException('العملة (المعرف ${line.currencyId}) '
            'غابت عن القاعدة بين المعاينة والاعتماد.');
      }
      fxSnapshots.add(
          (currencyId: line.currencyId, rateToBase: line.fxRate));
      final int partyId;
      if (line.partyId != null) {
        if (!livePartyIds.contains(line.partyId)) {
          throw ImportExecutionException('الطرف ${line.code} غاب عن '
              'القاعدة بين المعاينة والاعتماد.');
        }
        partyId = line.partyId!;
      } else {
        partyId = partyIdByCode[partyNumberKey(line.code)] ??
            (livePartyIndex.byNumberKey(line.code)?.id ?? -1);
        if (partyId <= 0) {
          throw ImportExecutionException('الطرف ${line.code} غاب عن '
              'القاعدة بين المعاينة والاعتماد.');
        }
      }
      moveLines.add(MoveLineDraft(
        accountId: line.debit ? acc112 : acc211,
        partyId: partyId,
        debitMinor: line.debit ? line.baseMinor : 0,
        creditMinor: line.debit ? 0 : line.baseMinor,
        currencyId: line.currencyId,
        amountMinor: line.docMinor,
        fxRate: line.fxRate,
      ));
      if (line.debit) {
        debitTotal += line.baseMinor;
      } else {
        creditTotal += line.baseMinor;
      }
    }
    for (final line in plan.cashLines) {
      fxSnapshots.add(
          (currencyId: line.currencyId, rateToBase: line.fxRate));
      final accountId = boxAccountIdByCurrency[line.currencyId]!;
      moveLines.add(MoveLineDraft(
        accountId: accountId,
        debitMinor: line.baseMinor,
        currencyId: line.currencyId,
        amountMinor: line.docMinor,
        fxRate: line.fxRate,
      ));
      debitTotal += line.baseMinor;
    }
    String? moveNumber;
    int? openingMoveId;
    if (moveLines.isNotEmpty) {
      final counterpart = debitTotal - creditTotal;
      if (counterpart > 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc332,
          creditMinor: counterpart,
          currencyId: 1,
          amountMinor: counterpart,
        ));
      } else if (counterpart < 0) {
        moveLines.add(MoveLineDraft(
          accountId: acc332,
          debitMinor: -counterpart,
          currencyId: 1,
          amountMinor: -counterpart,
        ));
      }
      final moveId = await _insertMoveDraftWithinTx(MoveDraft(
        journalId: await _journalIdByCodeTx('general'),
        dateText: plan.openingDateText,
        narration: 'قيد الأرصدة الافتتاحية — الذمم والنقد (استيراد)',
        refDocType: 'import_opening',
        lines: moveLines,
      ));
      await _postMoveWithinTx(moveId, sequenceKind: ledgerMoveSequenceKind);
      openingMoveId = moveId;
      moveNumber = (await customSelect(
        'SELECT number FROM moves WHERE id = ?',
        variables: [Variable.withInt(moveId)],
      ).getSingle()).data['number'] as String;
    }

    // حركات الصناديق للنقد الافتتاحي — بمصدره (ref_doc_type =
    // import_opening بقيمه) فالرصيد المُدار بالحركات هو ما تعرضه
    // الواجهة ويرعاه مُشغّل الرصيد (05 §4.2 — 05 §3.3).
    if (plan.cashLines.isNotEmpty && openingMoveId != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final line in plan.cashLines) {
        await customStatement(
          "INSERT INTO cash_movements (cash_box_id, kind, amount_minor, "
          "amount_base_minor, fx_rate, ref_doc_type, ref_doc_id, user_id, "
          "uuid, created_at, updated_at, is_deleted) "
          "VALUES (?, 'in', ?, ?, ?, 'import_opening', ?, ?, ?, ?, ?, 0)",
          [
            boxIdByCurrency[line.currencyId]!,
            line.docMinor,
            line.baseMinor,
            line.fxRate,
            openingMoveId,
            userId,
            const Uuid().v4(),
            now,
            now,
          ],
        );
      }
    }

    await _recordOpeningFxRatesWithinTx(
      rates: fxSnapshots.toList(),
      openingDateText: plan.openingDateText,
    );
    await recordSystemEvent('import_performed', userId: userId, payload: {
      'unit': 'opening_full',
      'template': 'opening_full,1',
      'separator': plan.semicolonUsed ? '؛' : ',',
      'rows': plan.totalDataRows,
      'parties_created': partiesCreated,
      'items_created': itemsCreated,
      'units_created': unitsCreated,
      'boxes_created': boxesCreated,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (moveNumber != null) 'move_number': moveNumber,
      'opening_date': plan.openingDateText,
      'inventory_value_base': plan.receiptValueBaseMinor,
      'event_backup': eventBackupName,
      if (plan.overSoftLimit) 'warning': 'over_soft_limit',
    });
    return ImportOpeningResult(
      partiesCreated: partiesCreated,
      itemsCreated: itemsCreated,
      unitsCreated: unitsCreated,
      boxesCreated: boxesCreated,
      moveNumber: moveNumber,
      receiptNumber: receiptNumber,
      debitBaseMinor: debitTotal,
      creditBaseMinor: creditTotal,
    );
  });
}

// ═══════════════════════════════════════════════════════════════
// الوحدة 3: كميات المخزون الافتتاحية (§25.2 — س142 التشطيب) — إذن
// إدخال مخزون قياسي (F-209) بمقابله 43 الافتراضي لا 332 الافتتاحي.
// ═══════════════════════════════════════════════════════════════

/// تخطيط استيراد كميات المخزون الافتتاحية من القاعدة — فهارس الحي:
/// الأصناف والوحدات والعملات وسياق التاريخ وأسعار آخر مسجل.
Future<OpeningQtyImportPlan> planOpeningQtyImportFromDb(
  OpeningQtyFileParse parse, {
  required String openingDateText,
}) async {
  final unitRows = await customSelect(
    'SELECT id, name FROM units WHERE is_deleted = 0',
  ).get();
  final itemRows = await customSelect(
    'SELECT i.id, i.sku, i.name, i.purchase_price_minor, '
    'i.sale_price_minor, i.price_currency_id, u.name AS unit_name '
    'FROM items i LEFT JOIN units u ON u.id = i.base_unit_id '
    'WHERE i.is_deleted = 0',
  ).get();
  final details = <int, ExistingItemImportRef>{};
  final forIndex = <ExistingItem>[];
  for (final r in itemRows) {
    final id = r.data['id'] as int;
    forIndex.add(ExistingItem(
      id: id,
      sku: r.data['sku'] as String,
      name: r.data['name'] as String,
      isActive: true,
    ));
    details[id] = ExistingItemImportRef(
      id: id,
      sku: r.data['sku'] as String,
      name: r.data['name'] as String,
      unitName: (r.data['unit_name'] as String?) ?? '',
      purchasePriceMinor: r.data['purchase_price_minor'] as int,
      salePriceMinor: r.data['sale_price_minor'] as int,
      priceCurrencyId: r.data['price_currency_id'] as int,
    );
  }
  return planOpeningQtyImport(
    parse,
    currencies: await importCurrencyIndex(),
    existingItems: ItemUniquenessIndex.build(forIndex),
    existingItemDetails: details,
    units: UnitUniquenessIndex.build([
      for (final r in unitRows)
        ExistingUnit(
          id: r.data['id'] as int,
          name: r.data['name'] as String,
          isActive: true,
        ),
    ]),
    dateContext: await _openingDateContextNow(openingDateText),
    latestRateByCurrency: await latestImportRatesByCurrency(),
  );
}

/// تنفيذ استيراد كميات المخزون الافتتاحية — الوحدة 3: معاملة واحدة
/// كل-أو-لا شيء، الوحدات والأصناف تنشأ آلياً، ثم إذن إدخال مخزون قياسي
/// (F-209) بقيم الملف الصريحة ومقابله 43 الافتراضي القابل للتغيير من
/// المفعّل — لا 332 (هذا إذنُ مخزونٍ لا قيدُ افتتاحِ ذمم ونقد)، وتاريخه
/// الافتتاحي المعاد التحقق منه حياً، وحدث الاستيراد بنفس المعاملة
/// (D-076)، ولقطة أسعار القيم بسجلها بتاريخ الافتتاحي (§25.4).
Future<ImportOpeningResult> executeOpeningQtyImport(
  OpeningQtyImportPlan plan, {
  required String eventBackupName,
  int? userId,
}) {
  assert(eventBackupName.trim().isNotEmpty,
      'لا اعتماد بلا نسخة حدثية (§25.6)');
  return transaction(() async {
    final dateErrors = validateOpeningDateForImport(
        await _openingDateContextNow(plan.openingDateText));
    if (dateErrors.isNotEmpty) {
      throw ImportExecutionException(
          'تاريخ الافتتاحي لم يعد صالحاً: '
          '${dateErrors.first.description}');
    }

    // الوحدات: القائمة بمعرفها والغائب ينشأ آلياً مرة واحدة (§25.4).
    final unitIdByName = <String, int>{};
    for (final r in await customSelect(
            'SELECT id, name FROM units WHERE is_deleted = 0')
        .get()) {
      unitIdByName[(r.data['name'] as String).trim()] =
          r.data['id'] as int;
    }
    var unitsCreated = 0;
    for (final name in plan.unitCreates) {
      if (unitIdByName.containsKey(name)) continue;
      unitIdByName[name] = await insertUnit(name: name);
      unitsCreated++;
    }

    // الأصناف: القائمة تُرفق، والغائب ينشأ بضاعة بلا أسعار (حد موثق —
    // قيمة الافتتاحي من الملف لا من سعر الصنف).
    final liveItems = await customSelect(
      'SELECT id, sku, name FROM items WHERE is_deleted = 0',
    ).get();
    final liveItemBySku = <String, int>{};
    final liveItemByName = <String, int>{};
    for (final r in liveItems) {
      liveItemBySku[itemSkuKey(r.data['sku'] as String)] =
          r.data['id'] as int;
      final nameKey = (r.data['name'] as String).trim();
      if (nameKey.isNotEmpty) {
        liveItemByName.putIfAbsent(nameKey, () => r.data['id'] as int);
      }
    }
    var itemsCreated = 0;
    final itemIdBySku = <String, int>{};
    for (final c in plan.itemCreates) {
      final skuHolder = liveItemBySku[itemSkuKey(c.sku)];
      if (skuHolder != null) {
        // أُنشئ بين المعاينة والاعتماد — يُرفق به لا يكرر.
        itemIdBySku[itemSkuKey(c.sku)] = skuHolder;
        continue;
      }
      if (liveItemByName.containsKey(c.name.trim())) {
        throw ImportExecutionException('الاسم «${c.name}» مستخدم لصنف '
            'قائم — القاعدة تغيرت بين المعاينة والاعتماد.');
      }
      final unitId = c.baseUnitId != -1
          ? c.baseUnitId
          : unitIdByName[c.unitName];
      if (unitId == null) {
        throw ImportExecutionException('وحدة الصنف ${c.sku} غابت بين '
            'المعاينة والاعتماد.');
      }
      final id = await insertItem(
        sku: c.sku,
        name: c.name,
        kind: 'good',
        baseUnitId: unitId,
        purchasePriceMinor: c.purchasePriceMinor,
        salePriceMinor: c.salePriceMinor,
        priceCurrencyId: c.priceCurrencyId,
      );
      itemIdBySku[itemSkuKey(c.sku)] = id;
      itemsCreated++;
    }

    // إذن الإدخال القياسي (F-209) — بقيم الملف الصريحة ومقابله 43
    // الافتراضي، والمستودع الأول النشط عرف الافتتاحي (نمط الوحدة 5).
    final wh = await customSelect(
      "SELECT id FROM warehouses WHERE is_deleted = 0 AND is_active = 1 "
      "ORDER BY id LIMIT 1",
    ).get();
    if (wh.isEmpty) {
      throw const ImportExecutionException(
          'لا مستودع نشط لإذن إدخال كميات المخزون الافتتاحية.');
    }
    final acc43 = await _accountIdByCodeTx('43');
    final receiptId = await _stockReceiptPostWithinTx(StockReceiptDraft(
      dateText: plan.openingDateText,
      warehouseId: wh.first.data['id'] as int,
      reason: 'استيراد كميات المخزون الافتتاحية',
      counterAccountId: acc43,
      narration: 'إذن إدخال كميات المخزون الافتتاحية — بقيم الملف',
      lines: [
        for (final line in plan.inventoryLines)
          StockDocLineDraft(
            itemId: line.itemId ??
                itemIdBySku[itemSkuKey(line.sku)] ??
                (liveItemBySku[itemSkuKey(line.sku)] ?? -1),
            qtyBase: line.qtyBase,
            valueBaseMinor: line.valueBaseMinor,
          ),
      ],
    ));
    final receiptNumber = (await customSelect(
      'SELECT number FROM stock_receipts WHERE id = ?',
      variables: [Variable.withInt(receiptId)],
    ).getSingle()).data['number'] as String;

    // لقطة أسعار القيم بسجلها بتاريخ الافتتاحي — المحفوظ ليومٍ بعينه
    // لا يُعدل (F-121)، والأساسية لا يقيس لها سعر (07 §1.7/§25.4).
    await _recordOpeningFxRatesWithinTx(
      rates: [
        for (final l in plan.inventoryLines)
          (currencyId: l.currencyId, rateToBase: l.fxRate),
      ],
      openingDateText: plan.openingDateText,
    );
    await recordSystemEvent('import_performed', userId: userId, payload: {
      'unit': 'opening_qty',
      'template': 'opening_qty,1',
      'separator': plan.semicolonUsed ? '؛' : ',',
      'rows': plan.totalDataRows,
      'items_created': itemsCreated,
      'units_created': unitsCreated,
      'receipt_number': receiptNumber,
      'opening_date': plan.openingDateText,
      'inventory_value_base': plan.receiptValueBaseMinor,
      'event_backup': eventBackupName,
      if (plan.overSoftLimit) 'warning': 'over_soft_limit',
    });
    return ImportOpeningResult(
      partiesCreated: 0,
      itemsCreated: itemsCreated,
      unitsCreated: unitsCreated,
      boxesCreated: 0,
      moveNumber: null,
      receiptNumber: receiptNumber,
      debitBaseMinor: plan.receiptValueBaseMinor,
      creditBaseMinor: plan.receiptValueBaseMinor,
    );
  });
}

// ═══════════════════════════════════════════════════════════════
// المتابعات (د-7/§25.9 — س141): مصادرها من القاعدة وعلامات إقرارها —
// تجميع عرض فوق المصادر لا كائن بيانات جديد (البناء النقي بالمجال).
// ═══════════════════════════════════════════════════════════════

/// مفتاحا العلامتين بمفاتيح نظام app_meta (معفاة من اصطلاح المزامنة
/// D-055): آخر حدث استيراد رُوجع، وتاريخ البداية المُقَرّ.
static const String followUpsReviewedThroughMetaKey =
    'follow_ups.reviewed_through';
static const String fiscalStartAckMetaKey =
    'follow_ups.fiscal_start_ack';

Future<void> _writeAppMetaValue(String key, String value) async {
  final existing = await (select(appMeta)
        ..where((t) => t.key.equals(key)))
      .getSingleOrNull();
  if (existing != null) {
    await (update(appMeta)..where((t) => t.key.equals(key)))
        .write(AppMetaCompanion(value: Value(value)));
  } else {
    await into(appMeta)
        .insert(AppMetaCompanion.insert(key: key, value: value));
  }
}

/// رصيد «جاري النتيجة (الافتتاح والإقفال)» 332 غير الموزَّع — null إن
/// لا حركة عليه أصلاً (لا قيد افتتاحي فلا متابعة).
Future<int?> openingUndistributedBaseMinor() async {
  final acc = await customSelect(
    "SELECT id FROM accounts WHERE code = '332' AND is_deleted = 0",
  ).get();
  if (acc.isEmpty) return null;
  final rows = await customSelect(
    "SELECT COALESCE(SUM(l.debit_minor), 0) - "
    "COALESCE(SUM(l.credit_minor), 0) AS bal "
    "FROM move_lines l JOIN moves m ON m.id = l.move_id "
    "WHERE l.account_id = ? AND m.state = 'posted' AND l.is_deleted = 0",
    variables: [Variable.withInt(acc.first.data['id'] as int)],
  ).get();
  return rows.first.data['bal'] as int;
}

/// أحداث الاستيراد بعد [afterEventId] — بعداداتها الموحدة لأمر
/// المتابعة (الإنشاء الآلي والتخطي — بنود §25.9 الثانية والثالثة).
Future<List<ImportEventSummary>> importEventsSince(int afterEventId) async {
  final rows = await customSelect(
    "SELECT id, payload FROM events WHERE action = 'import_performed' "
    "AND id > ? ORDER BY id",
    variables: [Variable.withInt(afterEventId)],
  ).get();
  final result = <ImportEventSummary>[];
  for (final r in rows) {
    Map<String, Object?> payload = const {};
    try {
      final decoded =
          jsonDecode(await openLogText(r.data['payload'] as String));
      if (decoded is Map<String, Object?>) payload = decoded;
    } catch (_) {
      // الحمولة الفاسدة كالغائبة — لا سحر (عرف D-169)، والعابث
      // يكسر وسم GCM فيقع هنا بعده (DQ-1108 لا فساد صامت).
    }
    final unit = '${payload['unit'] ?? ''}';
    int? toInt(Object? v) => v is num ? v.toInt() : null;
    result.add(ImportEventSummary(
      eventId: r.data['id'] as int,
      unit: unit,
      rows: toInt(payload['rows']) ?? 0,
      partiesCreated: toInt(payload['parties_created']) ??
          (unit == 'parties' ? toInt(payload['created']) ?? 0 : 0),
      itemsCreated: toInt(payload['items_created']) ??
          (unit == 'items' ? toInt(payload['created']) ?? 0 : 0),
      unitsCreated: toInt(payload['units_created']) ??
          toInt(payload['unit_created']) ??
          0,
      partiesSkipped:
          unit == 'parties' ? toInt(payload['skipped']) ?? 0 : 0,
      itemsSkipped: unit == 'items' ? toInt(payload['skipped']) ?? 0 : 0,
    ));
  }
  return result;
}

/// آخر حدث رُوجعت متابعاته — صفر قبل أول تأكيد.
Future<int> followUpsReviewedThrough() async {
  final row = await (select(appMeta)
        ..where((t) => t.key.equals(followUpsReviewedThroughMetaKey)))
      .getSingleOrNull();
  if (row == null) return 0;
  return int.tryParse(row.value.trim()) ?? 0;
}

/// تأكيد مراجعة المتابعات — علامة app_meta بآخر معرف حدث + حدث موثق
/// (بنود §25.9 الثانية والثالثة: راجع ثم أكّد).
Future<void> markFollowUpsReviewed({int? userId}) async {
  final through = await maxEventId();
  await _writeAppMetaValue(followUpsReviewedThroughMetaKey, '$through');
  await recordSystemEvent('follow_ups_reviewed', userId: userId, payload: {
    'through_event': through,
  });
}

/// آخر تاريخ بداية مُقَرّ — null قبل أول إقرار.
Future<String?> fiscalStartAcknowledged() async {
  final row = await (select(appMeta)
        ..where((t) => t.key.equals(fiscalStartAckMetaKey)))
      .getSingleOrNull();
  if (row == null) return null;
  final v = row.value.trim();
  return v.isEmpty ? null : v;
}

/// إقرار تاريخ بداية السنة المالية (§25.4: قبل الترحيل لا بعده) —
/// علامة app_meta بقيمة أقدم فترة مفتوحة + حدث موثق.
Future<void> acknowledgeFiscalYearStart({int? userId}) async {
  final start = await earliestOpenPeriodStartText();
  if (start == null) {
    throw StateError('لا فترة مفتوحة لإقرار بدايتها');
  }
  await _writeAppMetaValue(fiscalStartAckMetaKey, start);
  await recordSystemEvent('fiscal_start_acknowledged',
      userId: userId, payload: {'fiscal_year_start': start});
}

// ═══════════════════════════════════════════════════════════════
// د6 (س175) — المتابعات اليومية (س74/D-184) ولوحة «يحتاج انتباهك»
// (F-146 إحالة م4–م5) ومفاتيح سجلات العمل الجماعي: استعلامات عرض
// فوق المصادر القائمة حصراً والصياغة بالمجال النقي (follow_ups.dart)
// — والتخزين يقرأ ويجمع ولا يقرر (عرف المطابقة المخزونية س-56).
// ═══════════════════════════════════════════════════════════════

/// مصادر المتابعات اليومية — عتبة العرض الأقصى للفهرسة الأولية؛
/// اللوحة تعرض كل الصفوف والعدّ بالبني النقي.
static const int dailyFollowUpsRowLimit = 200;

/// الأصناف التي انخفضت عن الحد الأدنى المحدد عليها (س74/D-184 بلفظ
/// المالك حرفاً): السلع حصراً (الخدمات بلا مخزون أصلاً) بحد أدنى
/// موجب مخزّن، والمتاح مجموع المخزون الحي عبر المستودعات كلها —
/// والترتيب بالنقص الأشد ثم الاسم.
Future<List<BelowMinimumItemRow>> itemsBelowMinimum() async {
  final rows = await customSelect(
    'SELECT i.id AS item_id, i.sku AS sku, i.name AS name, '
    'i.min_qty AS min_qty, COALESCE(sb.qty, 0) AS available '
    'FROM items i '
    'LEFT JOIN (SELECT item_id, SUM(qty_base) AS qty '
    'FROM stock_balances WHERE is_deleted = 0 '
    'GROUP BY item_id) sb ON sb.item_id = i.id '
    'WHERE i.is_deleted = 0 AND i.kind = \'good\' '
    'AND i.min_qty IS NOT NULL '
    'AND COALESCE(sb.qty, 0) < i.min_qty '
    'ORDER BY (COALESCE(sb.qty, 0) - i.min_qty) ASC, i.name ASC '
    'LIMIT ?1',
    variables: [Variable.withInt(dailyFollowUpsRowLimit)],
  ).get();
  return [
    for (final r in rows)
      BelowMinimumItemRow(
        itemId: r.data['item_id'] as int,
        sku: r.data['sku'] as String,
        name: r.data['name'] as String,
        availableQty: (r.data['available'] as int?) ?? 0,
        minimumQty: r.data['min_qty'] as int,
      ),
  ];
}

/// الأرصدة التي تجاوزت سقفها الأعلى مبلغاً — حد الائتمان المعرف
/// (F-023) بلسان F-164 ذاته: الصافي المرحّل الطرفي أشدُّ من السقف
/// والدين قائم موجب (السقف الفراغي س-34 لا يُرسل أصلاً).
Future<List<OverCapPartyRow>> partiesOverCreditCap() async {
  final rows = await customSelect(
    'SELECT p.id AS party_id, p.name AS party_name, '
    'p.credit_limit_base_minor AS cap_minor, '
    'COALESCE(SUM(l.debit_minor), 0) - COALESCE(SUM(l.credit_minor), 0) '
    'AS net_minor '
    'FROM parties p '
    'JOIN move_lines l ON l.party_id = p.id '
    'JOIN moves m ON m.id = l.move_id '
    'WHERE p.is_deleted = 0 '
    'AND p.credit_limit_base_minor IS NOT NULL '
    "AND m.state = 'posted' "
    'GROUP BY p.id '
    'HAVING (COALESCE(SUM(l.debit_minor), 0) - '
    'COALESCE(SUM(l.credit_minor), 0)) > p.credit_limit_base_minor '
    'AND (COALESCE(SUM(l.debit_minor), 0) - '
    'COALESCE(SUM(l.credit_minor), 0)) > 0 '
    'LIMIT ?1',
    variables: [Variable.withInt(dailyFollowUpsRowLimit)],
  ).get();
  return [
    for (final r in rows)
      OverCapPartyRow(
        partyId: r.data['party_id'] as int,
        partyName: r.data['party_name'] as String,
        netDebitBaseMinor: (r.data['net_minor'] as int?) ?? 0,
        capBaseMinor: r.data['cap_minor'] as int,
      ),
  ];
}

/// الأرصدة التي تجاوزت سقفها الأعلى زمناً — مدة السداد المحددة على
/// الطرف (س74/D-184 «أو الزمن»): أقدم فاتورة بيع مفتوحة (مرحّلة أو
/// جزئية بباقٍ موجب فوق تغطية السندات بعرف الأعمار س-151/D-149)
/// عمرها من مرساتها (الاستحقاق وإلا التاريخ) تجاوز مدة السداد —
/// والفاتورة المفتوحة هي المصدر حصراً (عرف الأعمار) فلا فلتر رصيد
/// يكتم متأخراً مشروعاً.
Future<List<OverTermPartyRow>> partiesOverPaymentTerm(
    {DateTime? nowLocal}) async {
  final rows = await customSelect(
    'SELECT p.id AS party_id, p.name AS party_name, '
    'p.payment_term_days AS term_days, '
    'MIN(COALESCE(inv.due_date, inv.invoice_date)) AS oldest_anchor '
    'FROM parties p '
    'JOIN invoices inv ON inv.party_id = p.id '
    "AND inv.kind = 'sale' "
    "AND inv.state IN ('posted', 'partially_paid') "
    'AND inv.is_deleted = 0 '
    'LEFT JOIN (SELECT va.invoice_id AS iid, '
    'SUM(va.applied_doc_minor) AS covered '
    'FROM voucher_allocations va '
    'JOIN vouchers v ON v.id = va.voucher_id '
    "WHERE v.state = 'posted' AND v.is_deleted = 0 "
    'AND va.is_deleted = 0 GROUP BY va.invoice_id) cov '
    'ON cov.iid = inv.id '
    'WHERE p.is_deleted = 0 '
    'AND p.payment_term_days IS NOT NULL '
    'AND inv.total_doc_minor - COALESCE(cov.covered, 0) > 0 '
    'GROUP BY p.id '
    'LIMIT ?1',
    variables: [Variable.withInt(dailyFollowUpsRowLimit)],
  ).get();
  final today = nowLocal ?? DateTime.now();
  final todayDay = DateTime(today.year, today.month, today.day);
  final result = <OverTermPartyRow>[];
  for (final r in rows) {
    final anchor =
        DateTime.tryParse('${r.data['oldest_anchor']}');
    final term = r.data['term_days'] as int;
    if (anchor == null) continue;
    final ageDays = todayDay
        .difference(DateTime(anchor.year, anchor.month, anchor.day))
        .inDays;
    if (ageDays <= term) continue;
    result.add(OverTermPartyRow(
      partyId: r.data['party_id'] as int,
      partyName: r.data['party_name'] as String,
      oldestAnchorText: '${r.data['oldest_anchor']}',
      oldestAgeDays: ageDays,
      termDays: term,
    ));
  }
  result.sort((a, b) => b.oldestAgeDays.compareTo(a.oldestAgeDays));
  return result;
}

// ── مفاتيح سجلات العمل الجماعي (مفاتيح نظام app_meta معفاة من
//    اصطلاح المزامنة D-055 نمط علامتي المتابعات): كتاب رموز
//    الانضمام وسجل الأجهزة بحكمهما «يفشلان مقفلاً» فالنص يُحفظ
//    كما هو والفساد يحسمه البني النقي منعاً لا إسقاطاً، وحالة
//    الأرشفة السحابية فاسدها عودة فارغة قابلة لإعادة البناء.

static const String joinCodeBookMetaKey = 'sync.join_code_book';
static const String deviceRegistryMetaKey = 'sync.device_registry';
static const String cloudArchiveStateMetaKey =
    'sync.cloud_archive.state';

Future<String?> _readAppMetaValue(String key) async {
  final row = await (select(appMeta)
        ..where((t) => t.key.equals(key)))
      .getSingleOrNull();
  if (row == null) return null;
  final v = row.value.trim();
  return v.isEmpty ? null : v;
}

/// نص كتاب رموز الانضمام — null قبل أول إصدار.
Future<String?> joinCodeBookText() =>
    _readAppMetaValue(joinCodeBookMetaKey);

Future<void> saveJoinCodeBookText(String text) =>
    _writeAppMetaValue(joinCodeBookMetaKey, text);

/// نص سجل الأجهزة — null قبل أول انضمام.
Future<String?> deviceRegistryText() =>
    _readAppMetaValue(deviceRegistryMetaKey);

Future<void> saveDeviceRegistryText(String text) =>
    _writeAppMetaValue(deviceRegistryMetaKey, text);

/// نص حالة الأرشفة السحابية (آخر محاولة ونجاح وخطأ والكتالوج).
Future<String?> cloudArchiveStateText() =>
    _readAppMetaValue(cloudArchiveStateMetaKey);

Future<void> saveCloudArchiveStateText(String text) =>
    _writeAppMetaValue(cloudArchiveStateMetaKey, text);
}

// ═══ د6 (س175) — صفوف المتابعات اليومية الثلاثة (خارج الصنف العملاق
// درس س43 فتوليد database.g.dart يبقى سالماً) — التخزين يقرأ ويجمع
// والصياغة والشدّة بالمجال النقي حصراً (follow_ups.dart).

/// صف صنف انخفض عن حد الأدنى المحدد — مصدر بنود اليومية.
class BelowMinimumItemRow {
  final int itemId;
  final String sku;
  final String name;

  /// المتاح المجمّع عبر المستودعات كلها بوحدة الأساسية.
  final int availableQty;

  /// الحد الأدنى المحدد على الصنف (موجب من الحرس).
  final int minimumQty;

  const BelowMinimumItemRow({
    required this.itemId,
    required this.sku,
    required this.name,
    required this.availableQty,
    required this.minimumQty,
  });
}

/// صف طرف تجاوز سقفه المبلغي (حد الائتمان) — مصدر بنود اليومية.
class OverCapPartyRow {
  final int partyId;
  final String partyName;

  /// الصافي المرحّل الطرفي بوحدة الصغرى الأساسية (دين قائم موجب).
  final int netDebitBaseMinor;

  /// سقف الائتمان المعرف على الطرف.
  final int capBaseMinor;

  const OverCapPartyRow({
    required this.partyId,
    required this.partyName,
    required this.netDebitBaseMinor,
    required this.capBaseMinor,
  });
}

/// صف طرف تجاوز سقفه الزمني (مدة السداد) — مصدر بنود اليومية.
class OverTermPartyRow {
  final int partyId;
  final String partyName;

  /// مرساة العمر لأقدم فاتورة بيع مفتوحة (الاستحقاق وإلا التاريخ).
  final String oldestAnchorText;

  /// عمر تلك الفاتورة بالأيام الكاملة من المرساة.
  final int oldestAgeDays;

  /// مدة السداد المحددة على الطرف بالأيام.
  final int termDays;

  const OverTermPartyRow({
    required this.partyId,
    required this.partyName,
    required this.oldestAnchorText,
    required this.oldestAgeDays,
    required this.termDays,
  });
}

/// استثناء تنفيذ الاستيراد — القاعدة تغيرت بين المعاينة والاعتماد
/// أو فشلت كتابة: المعاملة كلها تُرجع فلا يُكتب شيء، والرمز DQ-1106
/// بالعرض (فشل تنفيذ الاستيراد).
class ImportExecutionException implements Exception {
  final String message;

  const ImportExecutionException(this.message);

  @override
  String toString() => message;
}

/// نتيجة تنفيذ استيراد — عدادات الكتابة الفعلية لا عدادات الخطة.
class ImportExecutionResult {
  final int created;
  final int updated;
  final int skipped;

  const ImportExecutionResult({
    required this.created,
    required this.updated,
    required this.skipped,
  });
}

/// نتيجة تنفيذ استيراد أرصدة أول المدة (س141 — الوحدتان 4 و5): أرقام
/// المستندين المرحّلين (القيد وإذن الإدخال إن وُجد) وعدادات الإنشاء
/// الآلي والإجماليين بالأساسية — لسان نجاح الواجهة ولوحة الميزان
/// التلقائية بعده (§25.6).
class ImportOpeningResult {
  final int partiesCreated;
  final int itemsCreated;
  final int unitsCreated;

  /// صناديق النقد التي فُتحت بعملاتها (05 §3.3).
  final int boxesCreated;

  /// رقم القيد المرحّل — null إن لا قيد (مخزون حصراً).
  final String? moveNumber;

  /// رقم إذن الإدخال المرحّل — null إن لا مخزون.
  final String? receiptNumber;
  final int debitBaseMinor;
  final int creditBaseMinor;

  const ImportOpeningResult({
    required this.partiesCreated,
    required this.itemsCreated,
    required this.unitsCreated,
    required this.boxesCreated,
    required this.moveNumber,
    required this.receiptNumber,
    required this.debitBaseMinor,
    required this.creditBaseMinor,
  });
}

/// ملخص حدث استيراد واحد كما يقرأ لأمر المتابعة (§25.9 — س141):
/// بعدادات موحدة عبر وحدات الدفعات الثلاث (الأطراف والأصناف
/// بس140 وأرصدة أول المدة بس141).
class ImportEventSummary {
  final int eventId;
  final String unit;
  final int rows;
  final int partiesCreated;
  final int itemsCreated;
  final int unitsCreated;
  final int partiesSkipped;
  final int itemsSkipped;

  const ImportEventSummary({
    required this.eventId,
    required this.unit,
    required this.rows,
    required this.partiesCreated,
    required this.itemsCreated,
    required this.unitsCreated,
    required this.partiesSkipped,
    required this.itemsSkipped,
  });
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

  /// س-148/D-138 (دفعة 14): اسم وحدة السطر — «مجموع الكميات بالواحدة»
  /// بقرار المالك يجمع بالوحدة لا رقماً عرياً، والقائمة تعرضها.
  final String unitName;

  /// س-153/D-151 (دفعة 15): خانة «ملاحظة التسليم» مع صف المتابعة —
  /// المواصفات الخاصة أو وعد التسليم، وnull لمن بلا ملاحظة.
  final String? deliveryNote;

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
    required this.unitName,
    this.deliveryNote,
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

// ═══ دفعة (15) «ما قبل إغلاق م1» — صفوف التقريرَين الجديدَين ═══
// (درس بنية الملف الكبرى س43: الأصناف الجديدة خارج الصنف العملاق
// DiqqahDatabase حصراً بعد إقفاله — فتوليد database.g.dart يبقى سالماً)

/// س-151/D-149: فاتورة مفتوحة داخل أعمار طرف — رصيدها المفتوح
/// بوحدات المستند والأساسية، وأيام تجاوزها عن موعد الاستحقاق
/// (سالب = لم يستحق بعد، وصفر = استحقاق اليوم).
class AgingInvoiceRow {
  final int invoiceId;
  final String number;
  final String invoiceDate;
  final String? dueDate;
  final int remainingDocMinor;
  final int remainingBaseMinor;
  final int daysOver;
  final String currencyCode;

  const AgingInvoiceRow({
    required this.invoiceId,
    required this.number,
    required this.invoiceDate,
    required this.dueDate,
    required this.remainingDocMinor,
    required this.remainingBaseMinor,
    required this.daysOver,
    required this.currencyCode,
  });
}

/// س-151/D-149: صف طرف واحد بتقرير الأعمار — مبالغه موزعة على الفوهج
/// بمؤشر الفوهة (0 = غير مستحق، ثم الفوهج بالترتيب، وأخيراً «أكثر من
/// آخر فوهة»)، والاتجاهان بمجال الذمم (05 §5): هم يدينون لنا / نحن
/// مدينون لهم، وفواتيره المفتوحة مدخلها (D-135).
class AgingPartyRow {
  final int partyId;
  final String partyName;
  final bool theyOweUs;

  /// المبالغ بالأساسية بمؤشر الفوهة — بطول الفوهج + 2 دائماً.
  final List<int> bucketMinor;
  final List<AgingInvoiceRow> invoices;

  int get totalMinor => bucketMinor.fold(0, (a, b) => a + b);

  const AgingPartyRow({
    required this.partyId,
    required this.partyName,
    required this.theyOweUs,
    required this.bucketMinor,
    required this.invoices,
  });
}

/// س-151/D-149: تقرير الأعمار كاملاً — الفوهج بنسخها المعتمدة
/// ولسانها المحسوب («حتى 30 يوماً»...)، وصفوف الأطراف بترتيب
/// المدينة ثم الدائنة (D-130)، ومجاميع الفوهج والإجمالي.
class AgingReport {
  final List<int> thresholds;
  final List<String> bucketLabels;
  final List<AgingPartyRow> parties;
  final List<int> bucketTotalsMinor;

  int get totalMinor => bucketTotalsMinor.fold(0, (a, b) => a + b);

  const AgingReport({
    required this.thresholds,
    required this.bucketLabels,
    required this.parties,
    required this.bucketTotalsMinor,
  });
}

/// س-152/D-150: سطر قيد بدفتر اليومية — الحساب الورقي والطرف
/// والجانبتان كما خُزّنت.
class JournalBookLine {
  final String accountCode;
  final String accountName;
  final String? partyName;
  final int debitMinor;
  final int creditMinor;

  const JournalBookLine({
    required this.accountCode,
    required this.accountName,
    required this.partyName,
    required this.debitMinor,
    required this.creditMinor,
  });
}

/// س-152/D-150: قيد واحد بدفتر اليومية — ترويسته (التاريخ والرقم
/// والدفتر والبيان) وأسطره، بمجاميع جانبَيه من أسطره حصراً.
class JournalBookEntry {
  final int moveId;
  final String moveDate;
  final String moveNumber;
  final String journalName;
  final String? narration;
  final List<JournalBookLine> lines;
  final int totalDebitMinor;
  final int totalCreditMinor;

  const JournalBookEntry({
    required this.moveId,
    required this.moveDate,
    required this.moveNumber,
    required this.journalName,
    required this.narration,
    required this.lines,
    required this.totalDebitMinor,
    required this.totalCreditMinor,
  });
}

/// س-152/D-150: دفتر اليومية كاملاً — القيود بترتيب الزمن ومجموعا
/// الجانبين، وضابط توازنهما روح F-068: المجموعان متساويان حصراً.
class JournalBookReport {
  final List<JournalBookEntry> entries;
  final int totalDebitMinor;
  final int totalCreditMinor;

  bool get isBalanced => totalDebitMinor == totalCreditMinor;

  const JournalBookReport({
    required this.entries,
    required this.totalDebitMinor,
    required this.totalCreditMinor,
  });
}

/// بانِي صف طرف بالأعمار — يجمع فواتير الطرف الواحد قبل تصفيته
/// (أداة داخلية للقارئة لا واجهة عامة).
class _AgingPartyBuilder {
  final int partyId;
  final String partyName;
  final bool theyOweUs;
  final List<int> _buckets;
  final List<AgingInvoiceRow> _invoices = [];

  _AgingPartyBuilder({
    required this.partyId,
    required this.partyName,
    required this.theyOweUs,
  }) : _buckets = <int>[];

  /// طول الفوهج لا يُعرف لحظة البناء فتُمدد القائمة عند كل إضافة.
  void add(int bucketIndex, int amountMinor, AgingInvoiceRow invoice) {
    while (_buckets.length <= bucketIndex) {
      _buckets.add(0);
    }
    _buckets[bucketIndex] += amountMinor;
    _invoices.add(invoice);
  }

  /// التصفية بطول الفوهج الكلي (n+2) — فقصر قائمة طرف ما (بلا مبالغ
  /// في الفوهج الأخيرة) لا يكسر مجاميع التقرير.
  AgingPartyRow build(int bucketCount) {
    final padded = [..._buckets];
    while (padded.length < bucketCount) {
      padded.add(0);
    }
    return AgingPartyRow(
      partyId: partyId,
      partyName: partyName,
      theyOweUs: theyOweUs,
      bucketMinor: List<int>.unmodifiable(padded),
      invoices: List<AgingInvoiceRow>.unmodifiable(_invoices),
    );
  }
}

/// بانِي قيد دفتر اليومية — يبني الصف عند أول سطر ثم يملاه ببقية
/// الأسطر (أداة داخلية للقارئة لا واجهة عامة).
class JournalBookBuilder {
  final int moveId;
  final String moveDate;
  final String moveNumber;
  final String journalName;
  final String? narration;
  final List<JournalBookLine> lines = [];
  int _debit = 0;
  int _credit = 0;

  JournalBookBuilder({
    required this.moveId,
    required this.moveDate,
    required this.moveNumber,
    required this.journalName,
    required this.narration,
  });

  /// القيد يُبنى بعد اكتمال الأسطر حصراً — مجاميعه من أسطره المخزونة
  /// لا من لقطة مبكرة.
  JournalBookEntry build() => JournalBookEntry(
        moveId: moveId,
        moveDate: moveDate,
        moveNumber: moveNumber,
        journalName: journalName,
        narration: narration,
        lines: List<JournalBookLine>.unmodifiable(lines),
        totalDebitMinor: _debit,
        totalCreditMinor: _credit,
      );

  void addLine(JournalBookLine line) {
    lines.add(line);
    _debit += line.debitMinor;
    _credit += line.creditMinor;
  }
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

/// رأس تحويل مخزني بالسجل (الدفعة 24 — س-18): أسماء المستودعين وعدد
/// الأسطر ومجاميعها لقطة من القاعدة لا حساب جديد.
class StockTransferListRow {
  final int id;
  final String number;
  final String transferDate;
  final String state;
  final String? narration;
  final int fromWarehouseId;
  final int toWarehouseId;
  final String? fromName;
  final String? toName;
  final int lineCount;
  final int totalQtyBase;
  final int totalValueMinor;

  const StockTransferListRow({
    required this.id,
    required this.number,
    required this.transferDate,
    required this.state,
    this.narration,
    required this.fromWarehouseId,
    required this.toWarehouseId,
    this.fromName,
    this.toName,
    required this.lineCount,
    required this.totalQtyBase,
    required this.totalValueMinor,
  });
}

/// سطر تحويل مخزني بلقطته — الصنف والكمية وكلفة الوحدة والقيمة كما
/// خُزنت لحظة الترحيل (لا حساب جديد — نمط لقطات الحركات F-140).
class StockTransferLineRow {
  final int itemId;
  final String? itemName;
  final String? sku;
  final int qtyBase;
  final int unitCostBaseMinor;
  final int valueBaseMinor;

  const StockTransferLineRow({
    required this.itemId,
    this.itemName,
    this.sku,
    required this.qtyBase,
    required this.unitCostBaseMinor,
    required this.valueBaseMinor,
  });
}

/// جلسة جرد قائمة للقراءة — الرأس بأسمائه المحسوبة وعدّاداته المجمعية
/// (نمط قراءة التحويل).
class StockCountListRow {
  final int id;
  final String number;
  final String countDate;
  final int warehouseId;
  final String warehouseName;
  final String scope;
  final String? scopeCategory;
  final String? narration;
  final String state;
  final int lineCount;
  final int countedCount;
  final int deficitCount;
  final int surplusCount;
  final int deficitValueMinor;
  final int surplusValueMinor;

  const StockCountListRow({
    required this.id,
    required this.number,
    required this.countDate,
    required this.warehouseId,
    required this.warehouseName,
    required this.scope,
    required this.scopeCategory,
    required this.narration,
    required this.state,
    required this.lineCount,
    required this.countedCount,
    required this.deficitCount,
    required this.surplusCount,
    required this.deficitValueMinor,
    required this.surplusValueMinor,
  });
}

/// سطر جلسة جرد للعرض — ما قبل الترحيل: العدّة ورصيد النظام الآني
/// للشاشة؛ وما بعده: لقطة الترحيل المخزنة حصراً.
class StockCountLineRow {
  final int itemId;
  final String? itemName;
  final String? sku;
  final String? itemCategory;
  final int? countedQtyBase;

  /// س115: لقطة العدّ بالتعبئة (نمط v25/v21) — والغائب عدّ بالأساسية.
  final int? unitLevelId;
  final int? qtyDoc;
  final int? factorAtEntry;
  final int? systemQtyBase;
  final int? diffQtyBase;
  final String? direction;
  final int valueBaseMinor;
  final int unitCostBaseMinor;

  const StockCountLineRow({
    required this.itemId,
    this.itemName,
    this.sku,
    required this.itemCategory,
    required this.countedQtyBase,
    this.unitLevelId,
    this.qtyDoc,
    this.factorAtEntry,
    required this.systemQtyBase,
    required this.diffQtyBase,
    required this.direction,
    required this.valueBaseMinor,
    required this.unitCostBaseMinor,
  });
}

/// صف سجل إذن مخزون (إدخال أو إخراج — الدفعة 26) — الشكل واحد
/// والاتجاه يحدده جدول المنبع، والسبب النصي الإلزامي بجانب الرقم.
class StockDocListRow {
  final int id;
  final String number;
  final String dateText;
  final String state;

  /// السبب النصي الإلزامي (F-209/F-210).
  final String reason;
  final String? narration;
  final int warehouseId;
  final String? warehouseName;
  final int lineCount;
  final int totalQtyBase;
  final int totalValueMinor;

  const StockDocListRow({
    required this.id,
    required this.number,
    required this.dateText,
    required this.state,
    required this.reason,
    this.narration,
    required this.warehouseId,
    this.warehouseName,
    required this.lineCount,
    required this.totalQtyBase,
    required this.totalValueMinor,
  });
}

/// سطر إذن مخزون بتفصيله — الكمية ولقطة كلفة الوحدة وقيمتها (نمط F-140).
class StockDocLineRow {
  final int itemId;
  final String? itemName;
  final String? sku;
  final int qtyBase;
  final int unitCostBaseMinor;
  final int valueBaseMinor;

  const StockDocLineRow({
    required this.itemId,
    this.itemName,
    this.sku,
    required this.qtyBase,
    required this.unitCostBaseMinor,
    required this.valueBaseMinor,
  });
}

/// تجميع قائم بالسجل (الدفعة 29 — F-211): الرأس بأسمائه المحسوبة
/// وكمية الناتج وقيمته الإجمالية وعدد أسطره — لقطة من القاعدة لا حساب
/// جديد (نمط قراءة الإذنين).
class AssemblyListRow {
  final int id;
  final String number;
  final String assemblyDate;
  final String state;

  /// عدد الوحدات المنتجة من الصنف التجميعي (بالمخزونية دائماً).
  final int qtyBase;

  /// س115: لقطة الناتج بالتعبئة (نمط v25/v21) — والغائب إدخال بالأساسية.
  final int? unitLevelId;
  final int? qtyDoc;
  final int? factorAtEntry;
  final int totalValueMinor;
  final int warehouseId;
  final String? warehouseName;
  final int bundleItemId;
  final String? bundleName;
  final String? bundleSku;
  final int lineCount;

  const AssemblyListRow({
    required this.id,
    required this.number,
    required this.assemblyDate,
    required this.state,
    required this.qtyBase,
    this.unitLevelId,
    this.qtyDoc,
    this.factorAtEntry,
    required this.totalValueMinor,
    required this.warehouseId,
    this.warehouseName,
    required this.bundleItemId,
    this.bundleName,
    this.bundleSku,
    required this.lineCount,
  });
}

/// سطر تجميع — لقطة كلفة المكوّن المسحوب (نمط F-140) قراءة خالصة.
class AssemblyLineRow {
  final int itemId;
  final String? itemName;
  final String? sku;

  /// الكمية المسحوبة من المكوّن (الوصفة × عدد الوحدات المنتجة).
  final int qtyBase;
  final int unitCostBaseMinor;
  final int valueBaseMinor;

  const AssemblyLineRow({
    required this.itemId,
    this.itemName,
    this.sku,
    required this.qtyBase,
    required this.unitCostBaseMinor,
    required this.valueBaseMinor,
  });
}

/// سطر معاينة تجميع — المطلوب والمتاح والقيمة التقديرية بالمتوسط
/// الحاكم لحظة النداء (نمط المعاينة هي التنفيذ D-183)، والمكوّن
/// الخدمي ظاهر بعِلمه بلا طلب ولا قيمة (F-212/F-211 — حد صادق).
class AssemblyPreviewLine {
  final int itemId;
  final String label;
  final bool isService;
  final int qtyNeeded;
  final int qtyAvailable;
  final int valueMinor;

  const AssemblyPreviewLine({
    required this.itemId,
    required this.label,
    required this.isService,
    required this.qtyNeeded,
    required this.qtyAvailable,
    required this.valueMinor,
  });
}

/// حصيلة المعاينة — الأسطر والقيمة التقديرية والأخطاء معاً (نمط
/// المدققين: القائمة فارغة = الترحيل سيمر بهذه القيمَ عينَها).
class AssemblyPreviewResult {
  final String? bundleLabel;
  final int totalValueMinor;
  final List<AssemblyPreviewLine> lines;
  final List<AssemblyValidationError> errors;

  const AssemblyPreviewResult({
    required this.bundleLabel,
    required this.totalValueMinor,
    required this.lines,
    required this.errors,
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

  /// v21 (الدفعة 30/س-10): لقطة الوحدة — معرف مستوى التعبئة عند
  /// الإدخال بها، وnull للإدخال بالوحدة الأساسية (كل القائم).
  final int? unitLevelId;

  /// الكمية المخزنة بوحدة الاختيار — بالأساسية تساوي qtyBase (القائم).
  final int qty;
  final int qtyBase;
  final int unitPriceMinor;
  final int discountMinor;
  final int taxRate;
  final int lineTotalDocMinor;
  final int lineTotalBaseMinor;
  final String uuid;

  /// س237 (المرحلة ج — D-235): السطر الحر — بلا صنف فوصفه بيانه،
  /// وملاحظته القصيرة بيان سطر خالص.
  final bool isFree;
  final String? description;
  final String? note;

  /// س-137/D-131: مربع «مستلم» — غير محدد افتراضاً لكل سطر جديد،
  /// والتحديد يُحفظ فوراً بقاعدة البيانات.
  final bool delivered;

  /// س-138/D-132: المورد المسؤول — اختيار يدوي مع اقتراح من آخر
  /// شراء مرحّل، ويُخزّن على السطر فيظهر بشاشة المتابعة وحده.
  final int? supplierPartyId;

  /// س-153/D-151 (دفعة 15): خانة «ملاحظة التسليم» القصيرة — المواصفات
  /// الخاصة أو وعد التسليم على السطر غير المستلم، وتظهر بشاشة
  /// المتابعة والمطبوع بلفظ البوابة. null لمن بلا ملاحظة.
  final String? deliveryNote;

  const InvoiceLineDocument({
    required this.id,
    required this.invoiceId,
    required this.itemId,
    required this.unitId,
    required this.factorAtEntry,
    this.unitLevelId,
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
    this.deliveryNote,
    // س237 (المرحلة ج): الحرة الثلاثة مع سطر المستند.
    this.isFree = false,
    this.description,
    this.note,
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
  /// (الدفعة 28: سطر التجميعي خططه تُجمع في سطر 51 واحد بالمبلغ
  /// المركب — F-034 — فالنظير صار لكل سطر فاتورة لا لكل خطة.)
  final int counterpartMinor;

  /// علم «جاهز/فُكِّك» (F-034/الدفعة 28): «ready» لخروج التجميعي
  /// الجاهز و«broken» لحركات مكونات الفكك — وNULL لبقية الحركات.
  final String? detail;

  const _StockLinePlan({
    required this.lineIndex,
    required this.itemId,
    required this.qtyBase,
    required this.stockValueMinor,
    required this.counterpartMinor,
    this.detail,
  });
}

/// اقتراح آخر سعر فعلي لصنف مع طرف (F-146/D-183) — قراءة خالصة.
class LastPriceSuggestion {
  final int itemId;
  final int priceMinor;

  /// لسان المصدر: «2026/000123 بتاريخ 2026-03-15» — يعرض ليبين الاقتراح
  /// من أين جاء (الصدق أولاً) ويبقى الحقل حراً بعدوه.
  final String docLabel;

  const LastPriceSuggestion({
    required this.itemId,
    required this.priceMinor,
    required this.docLabel,
  });
}

/// صف ترقية مستوى تعبئة داخل ترقية صنف — القيم المستهدفة فقط تُكتب
/// (null = لا مساس) بنمط الحقل غير المستهدف (F-165).
class BulkLevelPriceUpdateRow {
  final int levelId;
  final int? newSalePriceMinor;
  final int? newPurchasePriceMinor;

  const BulkLevelPriceUpdateRow({
    required this.levelId,
    this.newSalePriceMinor,
    this.newPurchasePriceMinor,
  });
}

/// صف ترقية جماعية (F-165/D-183) — الحقل غير المستهدف null فلا يُمس
/// إطلاقاً (Presence absent بالكتابة)، والقيم محسوبة سلفاً بالمعاينة
/// بمحرك المجال.
class BulkPriceUpdateRow {
  final int itemId;
  final int? newSalePriceMinor;
  final int? newPurchasePriceMinor;

  /// مستويات التعبئة للصنف — تقاطع F-165/D-187: الآلي بقيمه المشتقة
  /// من الأساس الجديد واليدوي مضروباً بالنسبة نفسها — الحساب بمحرك
  /// المجال حصراً وهنا الكتابة فقط.
  final List<BulkLevelPriceUpdateRow> levels;

  const BulkPriceUpdateRow({
    required this.itemId,
    this.newSalePriceMinor,
    this.newPurchasePriceMinor,
    this.levels = const [],
  });
}

/// الصيغة المعروضة لرقم الفاتورة (م-44/D-071): «فاتورة بيع » + الرقم
/// المخزن كما هو — «فاتورة بيع 2026/000001» للصادرة قبل D-169
/// و«فاتورة بيع 26000001» بعدها — فلا عرض يخالف المخزن أبداً.
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

/// الصيغة المعروضة لرقم السند (م-44/D-071): «سند قبض » + الرقم المخزن
/// كما هو (قديم «2026/000001» أو جديد «26000001» — D-169).
String voucherDisplayLabel(VoucherDocument voucher) {
  final kind = VoucherKind.fromStorage(voucher.kind);
  final label =
      sequenceKindLabels[voucherSequenceKind(kind)] ?? kind.label;
  return '$label ${voucher.number}';
}

// ═══ صفوف قوائم المستندات — دفعة (6-ج): صور عرض للتصفح لا للقرار،
// والتسميات من دوال المجال الجاهزة حصراً (لا صياغة مخزنة — D-089).

/// حقيقة تقديم فاتورة للاعتماد (س101) — أرقام وأسماء جاهزة للعرض لا
/// حسابات: من قدّم المسودة بأي دور ومتى، من حدث
/// «submitted_for_approval» الأخير.
class InvoiceSubmissionInfo {
  final int invoiceId;
  final int userId;
  final String userName;
  final String roleName;
  final int submittedAtMs;

  const InvoiceSubmissionInfo({
    required this.invoiceId,
    required this.userId,
    required this.userName,
    required this.roleName,
    required this.submittedAtMs,
  });
}

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

  /// الدفعة 21 (F-168): عدّادا أسطر الفاتورة من القاعدة — الكلي
  /// وغير المستلم منه. الأساس الذي يُبنى عليه لسان الحالة والفلتر،
  /// فلا إعادة حساب عند العرض ولا انحراف بين الشاشة والمطبوع.
  final int linesTotal;
  final int linesUndelivered;

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
    required this.linesTotal,
    required this.linesUndelivered,
  });

  /// «فاتورة بيع » + الرقم المخزن كما هو (قديم أو جديد — D-169) —
  /// والمسودة بلا رقم بعد فتسميتها «— مسودة».
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

  /// لسان حالة الاستلام للقائمة والمطبوع والCSV (الدفعة 21/F-168) —
  /// ثلاث حالات لا اثنتان: الثنائية تخفي الجزئي فتظهر فاتورة سُلِّم
  /// نصفها «غير مستلم» وكأن لم يُسلَّم منها شيء.
  String get receiptLabel {
    if (linesTotal > 0 && linesUndelivered == 0) return 'مكتمل الاستلام';
    final delivered = linesTotal - linesUndelivered;
    if (delivered > 0) return 'جزئي: مستلم $delivered من $linesTotal';
    return 'غير مستلم';
  }
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
    // س104: المعلّق بلسانه «معلّق — في الطريق» لا «مسودة» — إنه قيد
    // الطريق مقيد وذمة الطرف صفت فكذبُ «مسودة» يخفي حقيقته (F-016).
    if (number.isEmpty) {
      return state == 'held'
          ? '$kindLabel — معلّق في الطريق'
          : '$kindLabel — مسودة';
    }
    return '$kindLabel $number';
  }

  String get stateLabel => switch (state) {
        'held' => 'معلّق — في الطريق',
        'posted' => 'مرحّل',
        'rejected' => 'مرفوض',
        _ => 'مسودة',
      };

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

/// صف وصفة تجميعي للعرض — الدفعة 28 (F-034/F-212): المكوّن بمعرفه
/// ونوعه وكميته الوصفية وتكلفته الخدمية إن قُيمت.
class BundleRecipeRow {
  final int componentItemId;
  final int qtyBase;
  final int? costMinor;
  final String kind;
  final String sku;
  final String name;

  const BundleRecipeRow({
    required this.componentItemId,
    required this.qtyBase,
    required this.kind,
    required this.sku,
    required this.name,
    this.costMinor,
  });

  /// العرض المعتمد «الاسم (الكود)».
  String get displayLabel => itemDisplayLabel(name, sku);

  bool get isService => kind == 'service';
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
/// س236 (د10): صف قائمة تسوية بنكية — لسان قائمة الصندوق البنكي.
class BankReconciliationListRow {
  final int id;
  final String number;
  final String dateText;
  final String boxName;
  final CashAdjustmentDirection direction;
  final int statementBalanceDocMinor;
  final int bookBalanceDocMinor;
  final int amountDocMinor;
  final String reason;
  final String state;
  final String currencyCode;

  const BankReconciliationListRow({
    required this.id,
    required this.number,
    required this.dateText,
    required this.boxName,
    required this.direction,
    required this.statementBalanceDocMinor,
    required this.bookBalanceDocMinor,
    required this.amountDocMinor,
    required this.reason,
    required this.state,
    required this.currencyCode,
  });

  String get displayLabel =>
      number.isEmpty ? 'تسوية بنكية' : 'تسوية بنكية $number';

  String get stateLabel => state == 'posted' ? 'مرحّلة' : 'مسودة';
}


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

/// ─── س104: صفوف القبض المعلق (دفتر الصفوف آخر الملف — درس س101) ───

/// معلومات تقديم سند معلق بهوية مقدمه — مرآة InvoiceSubmissionInfo
/// (س101) بكيان السند، من أحداث التقديم بالأحدث فوزاً.
class VoucherSubmissionInfo {
  final int voucherId;
  final int userId;
  final String userName;
  final String roleName;
  final int submittedAtMs;

  const VoucherSubmissionInfo({
    required this.voucherId,
    required this.userId,
    required this.userName,
    required this.roleName,
    required this.submittedAtMs,
  });
}

/// صف عهدة مندوب — تحصيلاته المعلقة (في الطريق) مجمعة بهوية مقدمها:
/// العدد والمجموع الأساسي، وطابعا أقدم تقديم وأحدثه (أعمار العهدة
/// س105)، ولسان العرض في بطاقة العهدة.
class HeldCollectionCustodyRow {
  /// معرف مقدم التحصيل — و-1 لمن لا حدث تقديم له (حالة فاسدة مستحيلة
  /// بالمسار المعتمد يجتمع أصحابها تحت «غير معروف» صادقاً لا صامتاً).
  final int userId;
  final String userName;
  final String roleName;
  final int count;
  final int totalBaseMinor;

  /// طابع أقدم تحصيلاته المعلقة (ميلي ثانية) — وnull لمن لا حدث
  /// تقديم له (مجموعة «غير معروف»)، فلغة الأعمار من التطبيق لا نصاً
  /// مخزناً (نمط القلب — عرف س104).
  final int? oldestSubmittedAtMs;

  /// طابع أحدث تحصيلاته المعلقة (ميلي ثانية) — مع الأقدم يرى المعتمد
  /// امتداد العهدة لا مجموعها وحده.
  final int? newestSubmittedAtMs;

  const HeldCollectionCustodyRow({
    required this.userId,
    required this.userName,
    required this.roleName,
    required this.count,
    required this.totalBaseMinor,
    this.oldestSubmittedAtMs,
    this.newestSubmittedAtMs,
  });
  // لسان العهدة يصوغه التطبيق بمهيّئه المعتمد (formatMinorAmount) —
  // التخزين يقرأ ولا يزخرف (نمط القلب).
}

/// مدخل عهدة واحد (س162 — بقية فكرة المندوب: شرائح الأعمار) — تحصيل
/// معلق واحد بهوية آخر مقدمه وطابعه، والتوزيع النقي بالتطبيق
/// (custodyAgeSliceDistribution بالمجال) فلا شرائح مخزنة ولا إعداد.
class HeldCustodyEntry {
  final int voucherId;
  final int amountBaseMinor;

  /// و-1 لمن لا حدث تقديم له (مجموعة «غير معروف» — نمط الصف المجمّع).
  final int userId;
  final String userName;

  /// وnull لمن لا حدث تقديم له فلا شريحة عمر له.
  final int? submittedAtMs;

  const HeldCustodyEntry({
    required this.voucherId,
    required this.amountBaseMinor,
    required this.userId,
    required this.userName,
    required this.submittedAtMs,
  });
}

/// حالة بوابة الاستعادة (تكليف 2026-11-13 §5/ق-ن1-أ) — يزرعها
/// applyRestore بمفتاح app_meta 'restore.gate' وتستهلكها بوابة الإقلاع:
/// دخول إلزامي بمدير نشط من النسخة المستعادة، 5 محاولات ثم قفل
/// بمخرج اختيار نسخة أخرى أو إعادة محاولة لاحقاً.
class RestoreGateState {
  final DateTime? at;
  final String source;
  final int attempts;
  final bool locked;

  /// د-3 (§25.7، س136): اسم ملف لقطة ما قبل الاستعادة التي أنشأتها
  /// applyRestore لهذه الاستعادة — عينها التي تثبتها نافذة التراجع
  /// وتستعيدها بمر المسار ذاته. الفارغ (بوابات الجيل القديم) = لا زر.
  final String? snapshot;

  const RestoreGateState({
    required this.at,
    required this.source,
    required this.attempts,
    required this.locked,
    this.snapshot,
  });
}

/// حقائق ملخص ما بعد الاستعادة (تكليف §6) — تشغيلية غير حساسة:
/// سطر واحد يكشف الاستعادة الخطأ فوراً بلا كشف مالي.
class RestoreSummaryFacts {
  final int usersCount;
  final int invoicesCount;
  final String? lastDocumentDateText;

  const RestoreSummaryFacts({
    required this.usersCount,
    required this.invoicesCount,
    required this.lastDocumentDateText,
  });
}
