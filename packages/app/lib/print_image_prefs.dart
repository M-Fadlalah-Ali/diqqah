/// مفاتيح صور الأصناف في المطبوعات — دفعة (10) «الصور والباركود»
/// (س-127/س-128، D-123).
///
/// بلفظ المالك المعتمد: «يمكن إلغاؤه افتراضياً ويحتاج تفعيله الدخول إلى
/// الإعدادات ثم اختيار أين نريد تفعيلها افتراضياً» — فالافتراضي معطل
/// في كل المستندات، والتفعيل من الإعدادات بمفاتيح لكل نوع فاتورة
/// ومفتاحين للتقارير (المخزون والحركة) — مستقلة عن بعضها كله (س-128:
/// مفاتيح التقارير مستقلة عن مفاتيح الفواتير).
///
/// التخزين بمخزن الخيارات القائم (shared_preferences — نمط D-104 للخط)
/// والقيم ValueNotifier فتتجدد المطبوعات لحظياً بنمط الخط.
library;

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_domain/diqqah_domain.dart' show InvoiceKind;

/// مفاتيح المخزن — بادئة موحدة وقراءة آمنة عند غياب المفتاح.
const String _prefix = 'print_images_';

const List<(String, String)> kPrintImageChoices = [
  ('sale', 'فواتير البيع'),
  ('purchase', 'فواتير الشراء'),
  ('sale_return', 'مردود البيع'),
  ('purchase_return', 'مردود الشراء'),
  ('inventory', 'تقرير المخزون'),
  ('movement', 'تقارير الحركة والمشتريات'),
];

final Map<String, ValueNotifier<bool>> _notifiers = {
  for (final (key, _) in kPrintImageChoices) key: ValueNotifier<bool>(false),
};

/// قراءة مفاتيح الطباعة بالصور عند الإقلاع — نمط loadFontChoice (D-104).
Future<void> loadPrintImagePrefs() async {
  final prefs = await SharedPreferences.getInstance();
  for (final (key, _) in kPrintImageChoices) {
    _notifiers[key]!.value = prefs.getBool('$_prefix$key') ?? false;
  }
}

void savePrintImagePref(String key, bool value) {
  _notifiers[key]?.value = value;
  SharedPreferences.getInstance().then((prefs) {
    prefs.setBool('$_prefix$key', value);
  });
}

/// مفتاح نوع فاتورة — الأنواع الأربعة حصراً (س-127).
String printImageKeyForKind(InvoiceKind kind) => kind.storageValue;

/// هل تُطبع الصور لهذا النوع؟ — الافتراضي معطل في كل شيء (D-123).
bool printImagesForKind(InvoiceKind kind) =>
    _notifiers[kind.storageValue]?.value ?? false;

/// قيمة أي مفتاح بمعرفه — لعرض المفاتيح في الإعدادات.
bool printImageValueOf(String key) => _notifiers[key]?.value ?? false;

/// مفتاحا التقارير — المخزون مستقل والحركة (بيعية وشرائية) مفتاح واحد
/// كما سمّاه البوابة «تقارير الحركة والمشتريات».
ValueNotifier<bool> get printImageInventory => _notifiers['inventory']!;
ValueNotifier<bool> get printImageMovement => _notifiers['movement']!;
