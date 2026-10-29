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

/// جدول الأصناف — انعكاس مباشر لصف `item` في نموذج البيانات (05، v1.02).
///
/// قواعد معتمدة منعكسة هنا:
/// - الأسعار بوحدات صغرى صحيحة حصراً (س7) — لا عمود عشري في الجدول كله.
/// - `category` اختياري ووُجد أساساً للرفع الجماعي للأسعار (F-165، قرار المالك 2026-10-24).
/// - `default_tax_id` قيمة صفرية محتملة (05).
class Items extends Table {
  TextColumn get sku => text()();

  TextColumn get name => text()();

  TextColumn get category => text().nullable()();

  /// good / service / bundle (05)
  TextColumn get kind => text()();

  IntColumn get baseUnitId => integer().named('base_unit_id')();

  IntColumn get purchasePriceMinor =>
      integer().named('purchase_price_minor')();

  IntColumn get salePriceMinor => integer().named('sale_price_minor')();

  IntColumn get priceCurrencyId => integer().named('price_currency_id')();

  /// قيمة صفرية — ضريبة افتراضية غير معرفة (05)
  IntColumn get defaultTaxId => integer().nullable().named('default_tax_id')();

  BoolColumn get isActive => boolean().named('is_active')();

  /// اصطلاح «كل جدول» (05 §2، D-055): هوية عالمية تحمل النقل بين
  /// الأجهزة في المزامنة — إلزامي عند كل إدراج. ملاحظة موثقة (قرار
  /// الدفعة 2026-10-28): `id` التلقائي مؤجل لهذا الجدول تحديداً —
  /// sku مفتاح طبيعي فريد وuuid يكفي الهوية العالمية، وإعادة بناء
  /// الجدول لإضافة id تُدرس عند أول تطوير تشغيلي للأصناف في m1.
  TextColumn get uuid => text()();

  IntColumn get createdAt =>
      integer().withDefault(const Constant(0)).named('created_at')();

  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0)).named('updated_at')();

  /// حذف منطقي فقط للسجلات غير المرحّلة (05 §2) — المالية بعد الترحيل لا تُمسّ.
  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false)).named('is_deleted')();

  @override
  Set<Column> get primaryKey => {sku};
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

/// قاعدة دِقَّة — نسخة المخطط 4.
///
/// 1 = items فقط (جلسة م0 الأولى). 2 = التهيئة: roles / app_users / app_meta
/// (س-01: F-014/F-015). 3 = اصطلاح «كل جدول» (05 §2، D-055): uuid عالمي +
/// created_at/updated_at + is_deleted على items وroles وapp_users — app_meta
/// مفاتيح نظام معفاة قراراً موثقاً. 4 = جدول الأطراف (05 §3.1 — دفعة م1
/// الأولى: D-062..D-066، س-29..س-35). كل تغيير مخطط قادم يضيف إصداراً
/// وترحيلة — لا تعديل رجعي على إصدار منشور (F-011).
@DriftDatabase(tables: [Items, Roles, AppUsers, AppMeta, Parties])
class DiqqahDatabase extends _$DiqqahDatabase {
  /// التشغيل العادي: ملف القاعدة الوحيد (أساس النسخ الاحتياطي الكامل F-012).
  /// ملف الجيل السابق «heseb.db» يتبنّى آلياً عند أول فتح (D-053 —
  /// adoptLegacyHesebDatabase في backup.dart).
  DiqqahDatabase({String filePath = 'diqqah.db'})
      : super(LazyDatabase(() async => NativeDatabase(File(filePath))));

  /// للاختبارات: قاعدة في الذاكرة — لا أثر على ملف المستخدم أبداً.
  DiqqahDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 4;

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
}
