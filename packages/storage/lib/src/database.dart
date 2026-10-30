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

/// مفاتيح النظام — موطن `device_id` (F-015) وسائر مفاتيح التهيئة.
/// معفاة من اصطلاح «كل جدول» قراراً موثقاً (D-055): مفاتيح نظام
/// لا سجلات أعمال — لا مزامنة ولا حذف منطقي لها.
class AppMeta extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// قاعدة دِقَّة — نسخة المخطط 5.
///
/// 1 = items فقط (جلسة م0 الأولى). 2 = التهيئة: roles / app_users / app_meta
/// (س-01: F-014/F-015). 3 = اصطلاح «كل جدول» (05 §2، D-055): uuid عالمي +
/// created_at/updated_at + is_deleted على items وroles وapp_users — app_meta
/// مفاتيح نظام معفاة قراراً موثقاً. 4 = جدول الأطراف (05 §3.1 — دفعة م1
/// الأولى: D-062..D-066، س-29..س-35). 5 = دفعة م1 الثانية (الأصناف:
/// D-073..D-075، س-36..س-41): إضافة `id` التلقائي لجدول items بإعادة
/// بناء آمنة موثقة (الدرس الموكول من ملاحظة الجدول نفسه)، وجدولا units
/// وitem_barcodes جديدان خالصان (F-031/F-035). كل تغيير مخطط قادم يضيف
/// إصداراً وترحيلة — لا تعديل رجعي على إصدار منشور (F-011).
@DriftDatabase(tables: [Items, Roles, AppUsers, AppMeta, Parties, Units, ItemBarcodes])
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
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
}
