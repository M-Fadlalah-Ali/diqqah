/// س107 (أساس الأخطاء — قرار المالك الخامس): توصيل طبقة الرموز
/// بالواجهة — خريطة موحدة فوق خرائط الطبقتين وتسجيلٌ أقصى جهد.
///
/// العقد:
/// - الرمز يُشتق من الاستثناء بخريطة المجال ثم خريطة التخزين، وغير
///   المصنف يقع في الفاصلة الآمنة DQ-0999 (لا يبقى بلا رمز أبداً).
/// - `dqLog` تسجيلٌ أقصى جهد (logError بعقد «لا يفشل التدفق» بالتخزين)
///   فالاستدعاء داخل كتل catch لا يضيف خطراً جديداً على المسار.
/// - `dqTag` لسان العرض: « (DQ-xxxx)» يُلحق برسالة الـSnackBar فترى
///   الرسالة والرمز معاً كما يعرفهما مرجع الأخطاء.
library;

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// رمز أي خطأ — خريطة المجال ثم التخزين ثم الفاصلة الآمنة DQ-0999.
String dqCodeOf(Object error) =>
    dqCodeForDomainError(error) ??
    dqCodeForStorageError(error) ??
    diqqahUnclassifiedError.code;

/// لسان العرض: اللاحقة المرئية للرمز بعد الرسالة.
String dqTag(Object error) => ' (${dqCodeOf(error)})';

/// تسجيل أقصى جهد بسجل التشخيص — لا يرمي أبداً (عقد logError) ويعود
/// بصمت إن تعذر الوصول للقاعدة.
Future<void> dqLog(
  DiqqahDatabase db,
  Object error, {
  String? context,
}) async {
  try {
    await db.logError(
      code: dqCodeOf(error),
      message: error.toString(),
      context: context,
    );
  } catch (_) {
    // أقصى جهد — التسجيل خدمة تشخيص لا شرط عمل.
  }
}
