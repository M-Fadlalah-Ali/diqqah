import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

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

/// قاعدة حسيب — نسخة المخطط 1 (أول إنشاء، F-011: الترحيلات من أول يوم).
@DriftDatabase(tables: [Items])
class HesebDatabase extends _$HesebDatabase {
  /// التشغيل العادي: ملف القاعدة الوحيد (أساس النسخ الاحتياطي الكامل F-012).
  HesebDatabase({String filePath = 'heseb.db'})
      : super(LazyDatabase(() async => NativeDatabase(File(filePath))));

  /// للاختبارات: قاعدة في الذاكرة — لا أثر على ملف المستخدم أبداً.
  HesebDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // النسخة الأولى: إنشاء كل المخطط دفعة واحدة.
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // كل ترقية مستقبلية تُكتب خطوة خطوة هنا — لا إعادة بناء بيانات أبداً
          // (قاعدة تغيير آلية البيانات، س1: رسالة أثر + نافذة تسوية + قيد واحد)،
          // ولقطة التكلفة في كل حركة تضمن إعادة القيم نفسها لا إعادة حساب (س1).
        },
      );
}
