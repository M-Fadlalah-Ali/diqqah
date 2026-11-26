/// جلسة صاحب الشاشة (س101) — قراءة موحدة لمن في الدخول ودوره وصلاحياته،
/// كانت الرئيسية وحدها تقرؤها (home_screen) وبوابات «المندوب يعلق»
/// أحتاجها في نموذج الفاتورة والأرشيف والتفاصيل معاً فصار المنبع واحداً
/// (وحدة المنبع بتقاسمه لا بمضاعفته — عرف القائمة البيضاء D-171).
///
/// قرارات البوابات من المجال النقي حصراً (permissions.dart):
/// - `canPostOthersInvoices`: بوابة «ترحيل مسودات الآخرين» (س164) —
///   صاحب وحدة الفواتير المُنَح المفتاح الفرعي (النجمة تشمله) —
///   ومسودة صاحب اليد تُرحَّل بيده من التفاصيل بلا بوابة (فصل الأيدي).
///
/// السقوط الآمن بعرف الرئيسية (F-080): غياب المستخدم أو فشل القراءة
/// يعود null فلا بوابة تنطبق — والشاشات تعامله بلا دور (الوصول إلى
/// الشاشات أصلاً خلف بوابة F-014 والتهيئة فلا null عادي).
library;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// من في الدخول الآن — مستخدم ودور وصلاحيات وبوابة ترحيل الآخرين.
class SessionInfo {
  final AppUser user;
  final Role role;
  final RolePermissions permissions;

  const SessionInfo({
    required this.user,
    required this.role,
    required this.permissions,
  });

  /// بوابة «ترحيل مسودات الآخرين» على الفواتير (س164) — صاحب وحدة
  /// الفواتير المُنَح المفتاح الفرعي، والنجمة تشمله، والبائعُ (وباقي
  /// الأدوار) يُمنحها من شاشة الصلاحيات بلا حجبٍ بالاسم بعد إلغاء
  /// التعليق. (كانت canApproveHeldInvoices بوابة اعتماد المعلق
  /// س101 حتى إلغاء التعليق — بلا مساس بالسندات س104).
  bool get canPostOthersInvoices =>
      roleCanPostOthersInvoices(permissions);

  /// أدوار تعلق تحصيلاتها للاعتماد — «مندوب» (س104: القبض المعلق
  /// بحساب الطريق).
  bool get holdsReceiptsForApproval =>
      roleHoldsReceiptsForApproval(role.name);

  /// أدوار تعتمد التحصيلات المعلقة وتسلمها للصندوق — صاحب وحدة
  /// السندات من غير الأدوار البيعية (س104).
  bool get canApproveHeldReceipts =>
      roleCanApproveHeldReceipts(role.name, permissions);
}

/// قراءة الجلسة من القاعدة — null عند غياب المستخدم أو فشل القراءة
/// (سقوط آمن بعرف home_screen: الفشل لا يُسقط الشاشة ولا يخترع دوراً).
Future<SessionInfo?> loadSession(DiqqahDatabase db) async {
  try {
    final user = await db.currentUser();
    if (user == null) return null;
    final role = await db.roleOf(user);
    if (role == null) return null;
    return SessionInfo(
      user: user,
      role: role,
      permissions: RolePermissions(role.permissions),
    );
  } catch (_) {
    return null;
  }
}
