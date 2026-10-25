import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

/// يُرمى عند فتح قاعدة أحدث مخططاً من التطبيق (F-156: «حدّث التطبيق»).
class HesebNewerSchemaException implements Exception {
  const HesebNewerSchemaException();

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

  @override
  Set<Column> get primaryKey => {sku};
}

/// الأدوار — 05: `role` (name). إصدار 2 أضاف المعرّف الآلي لربط app_user.
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().unique()();
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
}

/// مفاتيح النظام — موطن `device_id` (F-015) وسائر مفاتيح التهيئة.
class AppMeta extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// قاعدة حسيب — نسخة المخطط 2.
///
/// 1 = items فقط (جلسة م0 الأولى). 2 = التهيئة: roles / app_users / app_meta
/// (س-01: F-014/F-015). كل تغيير مخطط قادم يضيف إصداراً وترحيلة — لا تعديل
/// رجعي على إصدار منشور (F-011).
@DriftDatabase(tables: [Items, Roles, AppUsers, AppMeta])
class HesebDatabase extends _$HesebDatabase {
  /// التشغيل العادي: ملف القاعدة الوحيد (أساس النسخ الاحتياطي الكامل F-012).
  HesebDatabase({String filePath = 'heseb.db'})
      : super(LazyDatabase(() async => NativeDatabase(File(filePath))));

  /// للاختبارات: قاعدة في الذاكرة — لا أثر على ملف المستخدم أبداً.
  HesebDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

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
          }
        },
        // F-156: التطبيق الأقدم يرفض قاعدة أحدث مخططاً برسالة «حدّث التطبيق»
        // — باب الاستعادة يفحصها قبل الاستبدال (prepareRestore)، وهذا باب
        // الفتح نفسه. drift يمرر التراجع (9→2) في onUpgrade نفسه فلا
        // تنفذ حلقتنا — والحرس أدناه يرفض قبل أي استخدام.
        beforeOpen: (details) async {
          if ((details.versionBefore ?? 0) > schemaVersion) {
            throw const HesebNewerSchemaException();
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
    final existing = await (select(roles)
          ..where((t) => t.name.equals('مدير')))
        .getSingleOrNull();
    final roleId = existing != null
        ? existing.id
        : await into(roles).insert(RolesCompanion.insert(name: 'مدير'));
    return into(appUsers).insert(
      AppUsersCompanion.insert(
        name: name,
        login: login,
        passwordHash: passwordHash,
        roleId: roleId,
        isActive: true,
      ),
    );
  }
}
