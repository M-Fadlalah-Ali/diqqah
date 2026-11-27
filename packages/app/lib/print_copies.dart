/// قوالب طباعة الفواتير ونسخة أمين المستودع (س119 — بكلمة المالك
/// الحرفية: «قم بتنفيذ قوالب الطباعة في التطبيق، وأضف طباعة الفاتورة
/// على نسختين بأمر طباعة واحد يظهر بعد إضافة/ترحيل الفاتورة مع خيارين
/// مفعلين افتراضياً دائماً، أحدهما لطباعة نسخة الزبون والآخر لطباعة
/// نسخة أمين المستودع، ويمكن للمستخدم إزالة أحدهما لهذه المرة فقط،
/// والأمر التالي للطباعة يعود إلى الحالة الافتراضية وهي تفعيل الاثنين،
/// مع وضع خيار إلغاء خيار طباعة نسخة أمين المستودع في الخيارات»).
///
/// المبادئ الحاكمة الموثقة:
/// - القالب عرض لا مصدر بيانات: يقرر ما يظهر بالورقة لا ما يُحسب،
///   وأرقام المطبوعة من الفاتورة ذاتها لا من القالب (ما يُطبَع لقطة).
/// - النسب حاكمة (D-103): يتبدل القياس والاتجاه ويبقى التخطيط النسبي
///   كل من عرض الصفحة وارتفاعها — «فلو تغير قياس الورق تبقى النسب».
/// - التحويل الحر (D-101 معروض): القياس والاتجاه افتراضٌ لكل نوع
///   قابل للتغيير لحظة الطباعة نفسها لهذه المرة فقط.
/// - نسخة أمين المستودع (عرف Packing Slip عند البرامج: وصل التسليم
///   بOdoo وقسيمة التعبئة بQuickBooks وتقرير شحنة Tryton): الصنف
///   والكمية بلا أسعار ولا مجاميع قيمية، ومجموع الكميات بوحداته
///   (جمع وحدات مختلفة ممنوع — quantitiesByUnit)، وعنوانها يميزها
///   «بلا أسعار» كي لا تدور بين الأيدي وثيقة سعرية، ومعرفات المصدر
///   فيها (المستند والتاريخ والطرف) فهي مرجعة لفاتورة الأم لا مستند
///   يتيم، وخانتا توقيع للمسلِّم والمستلِم.
/// - تفضيلات الجهاز المحلية (نمط D-104/D-123): shared_preferences
///   بمخزن الجهاز لا القاعدة — فلا ترحيلة ولا مساس بالمخطط v26.
/// - حرس D-197: فشل المخزن ذاته لا يرمي أبداً — الإقلاع أقدس من تفضيل.
library;

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_domain/diqqah_domain.dart' show InvoiceKind;
import 'package:diqqah_storage/diqqah_storage.dart';

import 'invoices_screen.dart' show buildInvoicePrintoutBytes;
import 'print_service.dart';
import 'dq_log.dart';

const String _prefix = 'print_tpl_';

/// مفاتيح الأنواع الأربعة بلسانها — مطابقة مفاتيح الصور المطبوعة (س-127).
const List<(String, String)> kPrintTemplateKindChoices = [
  ('sale', 'فواتير البيع'),
  ('purchase', 'فواتير الشراء'),
  ('sale_return', 'مردود البيع'),
  ('purchase_return', 'مردود الشراء'),
];

/// أعلام القالب الثلاثة القابلة للإظهار والإخفاء — الغائب كله ظاهر
/// مطابقاً السلوك القائم حرفاً (حارس انحدار: بلا قالب مطبوع القديم).
enum PrintTemplateFlag { delivered, deliveryNotes, tafqit }

class _KindPrintPrefs {
  final ValueNotifier<String> size; // 'a5' | 'a4' — الغائب a5 (D-101)
  final ValueNotifier<bool> landscape; // الغائب false — طولي (D-101)
  final ValueNotifier<bool> delivered; // عمود «مستلم» — الغائب true
  final ValueNotifier<bool> deliveryNotes; // عمود «ملاحظة» — الغائب true
  final ValueNotifier<bool> tafqit; // سطر التفقيط — الغائب true

  // س162 (الشطر الثاني D-103/م-45): أوزان أعمدة الجدول (نسب بيد المستخدم
  // بنفس ترتيب أعمدة النوع الظاهرة) ونصان حرّان أعلى الورقة وأسفلها —
  // والغائب (null/فراغ) مطابق السلوك القائم حرفاً فلا انحدار.
  final ValueNotifier<List<double>?> weights;
  final ValueNotifier<String> freeHeader;
  final ValueNotifier<String> freeFooter;

  _KindPrintPrefs()
      : size = ValueNotifier<String>('a5'),
        landscape = ValueNotifier<bool>(false),
        delivered = ValueNotifier<bool>(true),
        deliveryNotes = ValueNotifier<bool>(true),
        tafqit = ValueNotifier<bool>(true),
        weights = ValueNotifier<List<double>?>(null),
        freeHeader = ValueNotifier<String>(''),
        freeFooter = ValueNotifier<String>('');

  void reset() {
    size.value = 'a5';
    landscape.value = false;
    delivered.value = true;
    deliveryNotes.value = true;
    tafqit.value = true;
    weights.value = null;
    freeHeader.value = '';
    freeFooter.value = '';
  }
}

final Map<String, _KindPrintPrefs> _kindPrefs = {
  for (final (key, _) in kPrintTemplateKindChoices) key: _KindPrintPrefs(),
};

/// مفتاح إلغاء نسخة أمين المستودع من الخيارات — الغائب مفعّلة بلفظ
/// المالك («مفعلين افتراضياً دائماً»).
final ValueNotifier<bool> warehouseCopyEnabled = ValueNotifier<bool>(true);

/// القراءة عند الإقلاع — نمط loadPrintImagePrefs (D-104/D-123) بحرس
/// D-197: فشل المخزن يُسكَت والافتراضي باقٍ بلا كسر.
Future<void> loadPrintTemplatePrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final (key, _) in kPrintTemplateKindChoices) {
      final p = _kindPrefs[key]!;
      p.size.value = prefs.getString('$_prefix$key_size') ?? 'a5';
      p.landscape.value = prefs.getBool('$_prefix$key_landscape') ?? false;
      p.delivered.value = prefs.getBool('$_prefix$key_delivered') ?? true;
      p.deliveryNotes.value =
          prefs.getBool('$_prefix$key_delivery_notes') ?? true;
      p.tafqit.value = prefs.getBool('$_prefix$key_tafqit') ?? true;
      // س162: الأوزان CSV مفصولة بفواصل لاتينية أو عربية — والفاسد
      // أو الفراغ يعود null فيبقى المتساوي القائم حرفاً.
      p.weights.value =
          parseColumnWeightsInput(prefs.getString('$_prefix$key_weights'));
      p.freeHeader.value =
          prefs.getString('$_prefix$key_free_header') ?? '';
      p.freeFooter.value =
          prefs.getString('$_prefix$key_free_footer') ?? '';
    }
    warehouseCopyEnabled.value =
        prefs.getBool('${_prefix}wh_copy_enabled') ?? true;
  } catch (_) {
    // الافتراضي باقٍ — بلا كسر.
  }
}

/// محلّل حقل الأوزان المفصول بفواصل (نمط حقل مفصول الفواصل D-102):
/// فواصل لاتينية أو عربية، والرقم العشري مقبول، والرموز الشاذة تُمسح
/// لا تُكسر، والفارغ/الكل الفاسد يعود null (متساوٍ حرفاً). دالة نقية
/// تُختبر وحدها وحرسها الثاني بالشيفرة عند الطباعة (طول الأعمدة).
List<double>? parseColumnWeightsInput(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final tokens = raw
      .replaceAll('،', ',')
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;
  final out = <double>[];
  for (final t in tokens) {
    final v = double.tryParse(t);
    if (v != null && v.isFinite && v > 0) out.add(v);
  }
  if (out.isEmpty) return null;
  return out;
}

void _persist(String key, Object value) {
  SharedPreferences.getInstance().then((prefs) {
    if (value is String) {
      prefs.setString(key, value);
    } else if (value is bool) {
      prefs.setBool(key, value);
    }
  });
}

/// قيمة مقروءة للبناء — القياس الافتراضي لنوع الفاتورة.
String templateSizeForKind(InvoiceKind kind) =>
    _kindPrefs[kind.storageValue]?.size.value ?? 'a5';

/// قيمة مقروءة للبناء — الاتجاه الافتراضي لنوع الفاتورة (false طولي).
bool templateLandscapeForKind(InvoiceKind kind) =>
    _kindPrefs[kind.storageValue]?.landscape.value ?? false;

/// قيمة مقروءة للبناء — علم ظهور بالقالب.
bool templateFlagForKind(InvoiceKind kind, PrintTemplateFlag flag) {
  final p = _kindPrefs[kind.storageValue];
  if (p == null) return true;
  switch (flag) {
    case PrintTemplateFlag.delivered:
      return p.delivered.value;
    case PrintTemplateFlag.deliveryNotes:
      return p.deliveryNotes.value;
    case PrintTemplateFlag.tafqit:
      return p.tafqit.value;
  }
}

/// قيمة مقروءة للبناء — أوزان أعمدة النوع (س162) — والغائب null متساوٍ.
List<double>? columnWeightsForKind(InvoiceKind kind) =>
    _kindPrefs[kind.storageValue]?.weights.value;

/// قيمة مقروءة للبناء — النص الحر أعلى الورقة (س162) — والفراغ لا يطبع.
String freeHeaderTextForKind(InvoiceKind kind) =>
    _kindPrefs[kind.storageValue]?.freeHeader.value ?? '';

/// قيمة مقروءة للبناء — النص الحر أسفل الورقة (س162).
String freeFooterTextForKind(InvoiceKind kind) =>
    _kindPrefs[kind.storageValue]?.freeFooter.value ?? '';

void savePrintTemplateSize(String kindKey, String value) {
  _kindPrefs[kindKey]?.size.value = value;
  _persist('$_prefix${kindKey}_size', value);
}

void savePrintTemplateLandscape(String kindKey, bool value) {
  _kindPrefs[kindKey]?.landscape.value = value;
  _persist('$_prefix${kindKey}_landscape', value);
}

void savePrintTemplateFlag(String kindKey, PrintTemplateFlag flag, bool value) {
  final p = _kindPrefs[kindKey];
  if (p == null) return;
  switch (flag) {
    case PrintTemplateFlag.delivered:
      p.delivered.value = value;
      _persist('$_prefix${kindKey}_delivered', value);
    case PrintTemplateFlag.deliveryNotes:
      p.deliveryNotes.value = value;
      _persist('$_prefix${kindKey}_delivery_notes', value);
    case PrintTemplateFlag.tafqit:
      p.tafqit.value = value;
      _persist('$_prefix${kindKey}_tafqit', value);
  }
}

void saveWarehouseCopyEnabled(bool value) {
  warehouseCopyEnabled.value = value;
  _persist('${_prefix}wh_copy_enabled', value);
}

/// حفظ أوزان أعمدة النوع (س162) — CSV والقارئ الفوري يتحدث والفارغ
/// يحفظ فراغاً (أي عودة للمتساوي حرفاً).
void savePrintTemplateWeights(String kindKey, List<double>? weights) {
  final p = _kindPrefs[kindKey];
  if (p == null) return;
  p.weights.value = (weights == null || weights.isEmpty) ? null : weights;
  _persist(
      '$_prefix$kindKey_weights',
      (weights == null || weights.isEmpty)
          ? ''
          : weights.map((w) => w.toStringAsFixed(2)).join(','));
}

/// حفظ النص الحر (س162) — أعلى الورقة أو أسفلها بحسب الموضع.
void savePrintTemplateFreeText(String kindKey,
    {required bool isHeader, required String value}) {
  final p = _kindPrefs[kindKey];
  if (p == null) return;
  final v = value.trim();
  if (isHeader) {
    p.freeHeader.value = v;
    _persist('$_prefix$kindKey_free_header', v);
  } else {
    p.freeFooter.value = v;
    _persist('$_prefix$kindKey_free_footer', v);
  }
}

void _restoreKindDefaults(String kindKey) {
  final p = _kindPrefs[kindKey];
  if (p == null) return;
  p.reset();
  _persist('$_prefix${kindKey}_size', 'a5');
  _persist('$_prefix${kindKey}_landscape', false);
  _persist('$_prefix${kindKey}_delivered', true);
  _persist('$_prefix${kindKey}_delivery_notes', true);
  _persist('$_prefix${kindKey}_tafqit', true);
  _persist('$_prefix${kindKey}_weights', '');
  _persist('$_prefix${kindKey}_free_header', '');
  _persist('$_prefix${kindKey}_free_footer', '');
}

/// أعمدة النوع الظاهرة بنفس ترتيب بناء القسيمة (س162) — الأساس الأربعة
/// ففوقهما «مستلم» بعلمه و«ملاحظة» بفواتير البيع بعلمها — لحقل الأوزان
/// بلسان الترتيب ذاته. وعمود «ملاحظة» بالطباعة يحتاج ملاحظة بيانات
/// أصلاً فطول الأوزان غير المطابق يُتجاهل بالطباعة حارساً ثانياً.
List<String> templateColumnLabels(String kindKey,
    {required bool delivered, required bool notes}) => [
      'الصنف',
      'الكمية',
      'سعر الوحدة',
      'المبلغ',
      if (delivered) 'مستلم',
      if (kindKey == 'sale' && notes) 'ملاحظة',
    ];

/// نافذة أمر الطباعة الواحد بعد إضافة/ترحيل الفاتورة — خياران مفعلان
/// افتراضياً دائماً (نسخة الزبون ونسخة أمين المستودع)، وإزالة أحدهما
/// لهذه المرة فقط: الحالة تُبنى من التفضيلات عند كل فتح ولا تُكتب فيها
/// فالأمر التالي يعود افتراضياً بلفظ المالك حرفاً. والقياس والاتجاه
/// يُقرآن من قالب النوع ويُغيران لحظة الطباعة (التحويل الحر D-101).
Future<void> showInvoicePrintCopiesDialog(
  BuildContext context,
  DiqqahDatabase db,
  int invoiceId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // نوع الفاتورة يقرأ افتراضَي القياس والاتجاه من قالب النوع.
  String kindKey = 'sale';
  try {
    final invoice = await db.invoiceById(invoiceId);
    if (invoice != null) {
      final kind = InvoiceKind.fromStorage(invoice.kind);
      kindKey = kind.storageValue;
    }
  } catch (_) {
    // فشل القراءة لا يمنع النافذة — افتراضيات البيع باقية.
  }
  var customer = true;
  var warehouse = warehouseCopyEnabled.value;
  var size = _kindPrefs[kindKey]?.size.value ?? 'a5';
  var landscape = _kindPrefs[kindKey]?.landscape.value ?? false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('طباعة الفاتورة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              value: customer,
              onChanged: (v) =>
                  setDialogState(() => customer = v ?? customer),
              title: const Text('نسخة الزبون'),
              subtitle: const Text('كاملة بالأسعار والمجاميع والتفقيط'),
            ),
            if (warehouseCopyEnabled.value)
              CheckboxListTile(
                value: warehouse,
                onChanged: (v) =>
                    setDialogState(() => warehouse = v ?? warehouse),
                title: const Text('نسخة أمين المستودع (بلا أسعار)'),
                subtitle: const Text(
                    'الصنف والكمية ومجموع الكميات — للتجهيز والتسليم'),
              ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('القياس:'),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: size,
                  items: const [
                    DropdownMenuItem(value: 'a5', child: Text('A5')),
                    DropdownMenuItem(value: 'a4', child: Text('A4')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => size = v ?? size),
                ),
              ),
            ]),
            Row(children: [
              const Text('الاتجاه:'),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: landscape ? 'landscape' : 'portrait',
                  items: const [
                    DropdownMenuItem(value: 'portrait', child: Text('طولي')),
                    DropdownMenuItem(
                        value: 'landscape', child: Text('عرضي')),
                  ],
                  onChanged: (v) => setDialogState(
                      () => landscape = v == 'landscape'),
                ),
              ),
            ]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                if (customer) {
                  final bytes = await buildInvoicePrintoutBytes(
                    db,
                    invoiceId,
                    sizeOverride: size,
                    landscapeOverride: landscape,
                  );
                  if (!context.mounted) return;
                  await printPdfBytes(context, bytes);
                }
                if (warehouseCopyEnabled.value && warehouse) {
                  final bytes = await buildInvoicePrintoutBytes(
                    db,
                    invoiceId,
                    warehouseCopy: true,
                    sizeOverride: size,
                    landscapeOverride: landscape,
                  );
                  if (!context.mounted) return;
                  await printPdfBytes(context, bytes);
                }
              } catch (e) {
                await dqLog(db, e, context: 'invoice.print_copies');
                messenger.showSnackBar(
                  SnackBar(
                      content: Text('تعذر توليد الطباعة — $e${dqTag(e)}')),
                );
              }
            },
            child: const Text('طباعة'),
          ),
        ],
      ),
    ),
  );
}

/// بطاقة الإعدادات — «قوالب طباعة الفواتير» بنهاية قائمة الإعدادات
/// عمداً (درس ميزانية السحب D-098/س102 بالوجه الثاني الموثق س107:
/// البطاقة الجديدة توضع نهاية القائمة فلا تُزيح بنداً ولا ميزانية).
/// فيها مفتاح إلغاء نسخة أمين المستودع بلفظ المالك، وقالب كل نوع:
/// القياس والاتجاه وأعلام الظهور الثلاثة، وزر استعادة الافتراضي.
class PrintTemplatesCard extends StatefulWidget {
  const PrintTemplatesCard({super.key});

  @override
  State<PrintTemplatesCard> createState() => _PrintTemplatesCardState();
}

class _PrintTemplatesCardState extends State<PrintTemplatesCard> {
  String _kindKey = 'sale';
  // س162: متحكمات النصين الحرين والأوزان — تُزامَن مع النوع عند تبديله
  // والحفظ لحظي بالمخزن المحلي (نمط البطاقة القائمة).
  final TextEditingController _freeHeaderCtrl = TextEditingController();
  final TextEditingController _freeFooterCtrl = TextEditingController();
  final TextEditingController _weightsCtrl = TextEditingController();

  void _syncControllers() {
    final p = _kindPrefs[_kindKey]!;
    _freeHeaderCtrl.text = p.freeHeader.value;
    _freeFooterCtrl.text = p.freeFooter.value;
    _weightsCtrl.text =
        (p.weights.value == null || p.weights.value!.isEmpty)
            ? ''
            : p.weights.value!.map((w) => w.toStringAsFixed(2)).join(', ');
  }

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void dispose() {
    _freeHeaderCtrl.dispose();
    _freeFooterCtrl.dispose();
    _weightsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings_print_templates'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'قوالب طباعة الفواتير',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'القالب يقرر ما يظهر بالورقة لا ما يُحسب — والنسب ثابتة '
              'على أي قياس ورق. نسخة أمين المستودع قالب كمّي '
              'بلا أسعار لعرف قسائم التعبئة عند البرامج.',
            ),
            const SizedBox(height: 8),
            // مفتاح المالك: إلغاء خيار طباعة نسخة أمين المستودع.
            ValueListenableBuilder<bool>(
              valueListenable: warehouseCopyEnabled,
              builder: (_, enabled, __) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('نسخة أمين المستودع مع نسخة الزبون'),
                subtitle: const Text(
                    'إلغاؤه يطبع نسخة الزبون حصراً بعد الترحيل — '
                    'والعودة من هنا.'),
                value: enabled,
                onChanged: (v) =>
                    setState(() => saveWarehouseCopyEnabled(v)),
              ),
            ),
            const Divider(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _kindKey,
              decoration: const InputDecoration(labelText: 'نوع الفاتورة'),
              items: [
                for (final (key, label) in kPrintTemplateKindChoices)
                  DropdownMenuItem(value: key, child: Text(label)),
              ],
              onChanged: (v) => setState(() {
                _kindKey = v ?? _kindKey;
                _syncControllers();
              }),
            ),
            ValueListenableBuilder<String>(
              valueListenable: _kindPrefs[_kindKey]!.size,
              builder: (_, sizeValue, __) => DropdownButtonFormField<String>(
                initialValue: sizeValue,
                decoration: const InputDecoration(labelText: 'القياس'),
                items: const [
                  DropdownMenuItem(value: 'a5', child: Text('A5')),
                  DropdownMenuItem(value: 'a4', child: Text('A4')),
                ],
                onChanged: (v) =>
                    setState(() => savePrintTemplateSize(_kindKey, v ?? 'a5')),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _kindPrefs[_kindKey]!.landscape,
              builder: (_, landscapeValue, __) =>
                  DropdownButtonFormField<String>(
                initialValue: landscapeValue ? 'landscape' : 'portrait',
                decoration: const InputDecoration(labelText: 'الاتجاه'),
                items: const [
                  DropdownMenuItem(value: 'portrait', child: Text('طولي')),
                  DropdownMenuItem(value: 'landscape', child: Text('عرضي')),
                ],
                onChanged: (v) => setState(() => savePrintTemplateLandscape(
                    _kindKey, v == 'landscape')),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _kindPrefs[_kindKey]!.delivered,
              builder: (_, delivered, __) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('عمود «مستلم» بأسطر الفاتورة'),
                value: delivered,
                onChanged: (v) => setState(() => savePrintTemplateFlag(
                    _kindKey, PrintTemplateFlag.delivered, v)),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _kindPrefs[_kindKey]!.deliveryNotes,
              builder: (_, notes, __) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('عمود «ملاحظة التسليم» (فواتير البيع)'),
                value: notes,
                onChanged: (v) => setState(() => savePrintTemplateFlag(
                    _kindKey, PrintTemplateFlag.deliveryNotes, v)),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _kindPrefs[_kindKey]!.tafqit,
              builder: (_, tafqit, __) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('سطر التفقيط «فقط ... لا غير»'),
                value: tafqit,
                onChanged: (v) => setState(() => savePrintTemplateFlag(
                    _kindKey, PrintTemplateFlag.tafqit, v)),
              ),
            ),
            const Divider(height: 16),
            // س162 (الشطر الثاني D-103/م-45): النصان الحرّان وأوزان
            // الأعمدة — تحرير النسب والنصوص بيد المستخدم، والغائب
            // (فراغ) مطابق السلوك القائم حرفاً فلا انحدار.
            ValueListenableBuilder<String>(
              valueListenable: _kindPrefs[_kindKey]!.freeHeader,
              builder: (_, __, ___) => TextField(
                key: const ValueKey('tpl_free_header'),
                controller: _freeHeaderCtrl,
                decoration: const InputDecoration(
                  labelText: 'نص حر أعلى الورقة',
                  hintText: 'مثال: فاتورة ضريبية — يُترك فارغاً لعدم الطباعة',
                ),
                onChanged: (v) =>
                    savePrintTemplateFreeText(_kindKey,
                        isHeader: true, value: v),
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: _kindPrefs[_kindKey]!.freeFooter,
              builder: (_, __, ___) => TextField(
                key: const ValueKey('tpl_free_footer'),
                controller: _freeFooterCtrl,
                decoration: const InputDecoration(
                  labelText: 'نص حر أسفل الورقة',
                  hintText: 'مثال: شكراً لتعاملكم معنا — يُترك فارغاً',
                ),
                onChanged: (v) =>
                    savePrintTemplateFreeText(_kindKey,
                        isHeader: false, value: v),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'نِسب أعمدة الجدول — الأكبر وزناً أعرض عموداً. الترتيب: '
              '${templateColumnLabels(
                _kindKey,
                delivered: _kindPrefs[_kindKey]!.delivered.value,
                notes: _kindPrefs[_kindKey]!.deliveryNotes.value,
              ).join('، ')} — والفراغ يعيد الأعمدة المتساوية.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextField(
              key: const ValueKey('tpl_weights'),
              controller: _weightsCtrl,
              keyboardType: const TextInputType.numberWithOptions(),
              decoration: const InputDecoration(
                labelText: 'نِسب الأعمدة (مفصولة بفواصل)',
                hintText: 'مثال: 2، 1، 1، 1',
              ),
              onChanged: (v) => savePrintTemplateWeights(
                  _kindKey, parseColumnWeightsInput(v)),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _restoreKindDefaults(_kindKey)),
                child: const Text('استعادة افتراضيات هذا النوع'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
