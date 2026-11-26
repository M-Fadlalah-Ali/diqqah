/// س203 — بيانات المنشأة: هوية صاحب العمل لا هوية التطبيق (بأمر
/// المالك «بيانات المنشأة والطباعة التجارية»): الاسم ووسائل الاتصال
/// تُدخل من الإعدادات وتُخزن بapp_meta (جدول من v2 فلا ترحيلة ولا
/// مساس بالمخطط) وتسافر مع النسخ الاحتياطية تلقائياً، وتظهر أول
/// المطبوعات حين حُفظت — والغائب يعيد ترويسة العلامة القائمة حرفاً
/// فلا طباعة تُكسر ولا هويّة تختفي (س-157/D-155 روحاً).
library;

import 'dart:convert';

import 'package:diqqah_storage/diqqah_storage.dart';

/// مفتاح app_meta لحمل بيانات المنشأة JSON.
const String kCompanyProfileMetaKey = 'company_profile';

/// بيانات المنشأة — الاسم إلزامي عند الحفظ والبقية اختيارية.
class CompanyProfile {
  final String name;
  final String? phone;
  final String? address;
  final String? taxNumber;

  const CompanyProfile({
    required this.name,
    this.phone,
    this.address,
    this.taxNumber,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'address': address,
        'taxNumber': taxNumber,
      };

  /// JSON الفاسد أو الناقص يقرأ ما أمكن والبقية null — بلا كسر.
  factory CompanyProfile.fromJson(Map<String, dynamic> json) =>
      CompanyProfile(
        name: (json['name'] ?? '').toString(),
        phone: json['phone']?.toString(),
        address: json['address']?.toString(),
        taxNumber: json['taxNumber']?.toString(),
      );
}

/// قراءة بيانات المنشأة من app_meta — والغائب أو الفاسد null فتعيد
/// الطباعة ترويستها القائمة (نمط السقوط الآمن D-104).
Future<CompanyProfile?> loadCompanyProfile(DiqqahDatabase db) async {
  try {
    final raw = await db.metaValueOf(kCompanyProfileMetaKey);
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final profile = CompanyProfile.fromJson(decoded);
    if (profile.name.trim().isEmpty) return null;
    return profile;
  } catch (_) {
    return null;
  }
}

/// حفظ بيانات المنشأة — الزرع فوق العرف القائم (upsertMetaValue).
Future<void> saveCompanyProfile(DiqqahDatabase db, CompanyProfile p) =>
    db.upsertMetaValue(kCompanyProfileMetaKey, jsonEncode(p.toJson()));
