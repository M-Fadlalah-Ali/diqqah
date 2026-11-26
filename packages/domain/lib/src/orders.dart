/// طلبات البيع والشراء — طبقة تشغيلية فوق الفاتورة (07 §3.2 / قرار n-D-026).
///
/// التفعيل بأمر المالك الحرفي «أريد تفعيل طلبات البيع والشراء»
/// (س121 — 2026-11-07) فاتحاً بند الانتظار §8 الموثق: «سلسلة أوامر
/// البيع/الشراء والشحن كطبقة تشغيلية فوق الفاتورة (07 §3.2)».
///
/// القرار الحاكم الموثق حرفاً (07 §3.2): «سلسلة "أمر بيع ← شحنة ←
/// فاتورة" تُضاف لاحقاً كطبقة تشغيلية فوق الفاتورة إن طلبها العمل،
/// **دون أي تغيير في القلب المحاسبي**» — فالأمر لا يُقيد في الدفتر
/// ولا يحرك مخزوناً ولا صندوقاً أبداً (ما يُقيد ويُحرك هو الفاتورة
/// وحدها)، وهو وثيقة التزام تشغيلية تُحوَّل لفاتورة تحمل مرجعَ الأمر
/// (`invoices.order_id`) فتصير الفاتورة مرجعةً لأمرها لا مستنداً يتيماً
/// بنفس عرف ترويسة نسخة أمين المستودع (س119).
///
/// السلسلة الموثقة بقرار n (12-owner-answers): «أمر ← تسليم/استلام ←
/// فاتورة».
///
/// آلة الحالات صريحة بانتقالات محروسة (07 §1.2): مسودة ← مؤكدة ←
/// مغلقة، والإلغاء من المسودة والمؤكدة — والمغلقة والملغاة طرفان
/// نهائيان. الإغلاق محروس: لا يُغلق الأمر والمتبقي أكبر من صفر
/// (عرف Tryton: يُغلق البيع ب invoicing كامل).
///
/// **الوفاء محسوب لا مخزن** (عرف المشروع الموثق س102/س104: «الحجز
/// محسوب من المعلقات لا حالة مخزنة» و«العهدة قراءة محسوبة»): ما
/// فُضي من الأمر يُشتق حصراً من الفواتير الحية المرجعة له
/// (`invoices.order_id`) بنوعَي البيع والشراء حصراً (المردودات لا
/// تأخذ مرجع الأمر أبداً — التحويل ينشئ بيعاً أو شراءً مباشراً).
library;

/// اتجاه الأمر — موازٍ لنوع الفاتورة المولدة منه (بيع من بيع وشراء
/// من شراء — لا انعكاس اتجاه في التحويل).
enum OrderDirection {
  sale('sale', 'أمر بيع'),
  purchase('purchase', 'أمر شراء');

  final String storageValue;
  final String label;

  const OrderDirection(this.storageValue, this.label);

  static OrderDirection fromStorage(String value) {
    for (final d in OrderDirection.values) {
      if (d.storageValue == value) return d;
    }
    throw ArgumentError('اتجاه أمر غير معروف: $value');
  }
}

/// حالة الأمر (07 §1.2 — صريحة لا عامة). القيم التخزينية إنجليزية
/// والعرض بترجمتها العربية — نمط move_detail الموثق (v19).
enum OrderState {
  draft('draft', 'مسودة'),
  confirmed('confirmed', 'مؤكدة'),
  closed('closed', 'مغلقة'),
  cancelled('cancelled', 'ملغاة');

  final String storageValue;
  final String label;

  const OrderState(this.storageValue, this.label);

  static OrderState fromStorage(String value) {
    for (final s in OrderState.values) {
      if (s.storageValue == value) return s;
    }
    throw ArgumentError('حالة أمر غير معروفة: $value');
  }

  /// الطرفان النهائيان — لا انتقال منهما أبداً (07 §1.2).
  bool get isTerminal => this == closed || this == cancelled;
}

/// الانتقالات المسموحة لآلة حالة الأمر — الخريطة هي القانون الوحيد:
/// ما ليس فيها مرفوض (DQ-0704). المسودة تتحول لتأكيد أو إلغاء،
/// والمؤكدة لإغلاق (بشرط الوفاء الكامل — حرس التخزين) أو إلغاء.
const Map<OrderState, Set<OrderState>> allowedOrderTransitions =
    <OrderState, Set<OrderState>>{
  OrderState.draft: {OrderState.confirmed, OrderState.cancelled},
  OrderState.confirmed: {OrderState.closed, OrderState.cancelled},
  OrderState.closed: {},
  OrderState.cancelled: {},
};

/// هل الانتقال مسموح؟ النقي والقرار الوحيد — الواجهة تعطل زراً
/// لا انتقال له، والتخزين يرفض ما خالفه (حرسان طبقةً طبقة).
bool isOrderTransitionAllowed(OrderState from, OrderState to) =>
    allowedOrderTransitions[from]?.contains(to) ?? false;

/// سطر أمر كما يخرج من النموذج قبل التحقق — لقطة الوحدة ثلاثية
/// الأركان بنمط v21 الموحد (unit_id الأساسية المرجعية + unit_level_id
/// للتعبة + factor_at_entry بمعامل المستوى وقت الإدخال)، والكمية
/// بوحدة الإدخال ومكافؤها الأساسي محسوبان بالواجهة قبل الاستدعاء
/// (المجال يتحقق لا يحسب التحويل — فحصة التحويل بواجهة الإدخال
/// الموحدة كما في الفواتير).
class OrderLineSpec {
  final int itemId;
  final int unitId;
  final int? unitLevelId;
  final int factorAtEntry;
  final int qty;

  /// الكمية بمكافئ الوحدة الأساسية — حصة التخزين والمقارنة حصراً.
  final int qtyBase;

  /// السعر المرجعي بوحدة الإدخال — تسعير وقت الأمر لا سعر إلزام:
  /// الفاتورة المولدة تنتقل إليه قيمةً قابلة للتعديل قبل الترحيل.
  final int unitPriceMinor;

  const OrderLineSpec({
    required this.itemId,
    required this.unitId,
    this.unitLevelId,
    this.factorAtEntry = 1,
    required this.qty,
    required this.qtyBase,
    this.unitPriceMinor = 0,
  });
}

/// مسودة أمر كاملة كما تخرج من النموذج قبل التحقق.
class OrderSpec {
  final OrderDirection direction;
  final int? partyId;
  final int? warehouseId;
  final String orderDate;

  /// تاريخ التوريد المتوقع — اختياري، علم عمل لا محاسبة.
  final String? expectedDate;
  final List<OrderLineSpec> lines;

  const OrderSpec({
    required this.direction,
    required this.orderDate,
    this.partyId,
    this.warehouseId,
    this.expectedDate,
    this.lines = const [],
  });
}

/// أخطاء التحقق — أنواع محمولة بيانات لا رسائل جاهزة: الواجهة وحدها
/// تقرر الصياغة المعروضة (فصل المجال عن العرض — نمط item.dart/unit_group.dart).
sealed class OrderValidationError {
  const OrderValidationError();
}

/// أسطر الأمر فارغة — لا أمر بلا صنف واحد على الأقل (DQ-0701).
class OrderLinesRequired extends OrderValidationError {
  const OrderLinesRequired();
}

/// طرف الأمر مطلوب — أمر بيع لزبون وأمر شراء لمورد (DQ-0702).
class OrderPartyRequired extends OrderValidationError {
  const OrderPartyRequired();
}

/// كمية سطر غير صالحة — صفر أو سالبة أو مكافؤ أساسي غير متسق مع
/// الكمية ومعامل الإدخال (DQ-0703).
class OrderQtyInvalid extends OrderValidationError {
  /// ترتيب السطر المخطئ بدءاً من الواحد — للإشارة بالواجهة.
  final int lineIndex;

  const OrderQtyInvalid(this.lineIndex);
}

/// انتقال حالة غير مسموح (DQ-0704) — يحمل الطرفين للعرض.
class OrderTransitionInvalid extends OrderValidationError {
  final OrderState from;
  final OrderState to;

  const OrderTransitionInvalid(this.from, this.to);
}

/// إغلاق الأمر والمتبقي أكبر من صفر (DQ-0706) — الإغلاق بعد الوفاء
/// الكامل حصراً (حرس التخزين بمعاملة التأكيد).
class OrderCloseIncomplete extends OrderValidationError {
  const OrderCloseIncomplete();
}

/// التحويل لفاتورة يتطلب أمراً مؤكداً (DQ-0707) — المسودة والملغاة
/// والمغلقة لا تُحوَّل: المسودة التزام غير معلن، والمغلقة وفّى
/// كاملاً، والملغاة عُفيت.
class OrderNotConvertible extends OrderValidationError {
  final OrderState state;

  const OrderNotConvertible(this.state);
}

/// أمر مؤكد مجمّد — أي تعديل غير تغيير الحالة مرفوض (DQ-0702):
/// الأسطر والحقل لا يُمسّان بعد التأكيد، والتصحيح بالإلغاء وإعادة
/// الأمر (حاجز SQL trg_orders_frozen هو الظهير الدائم).
class OrderFrozen extends OrderValidationError {
  const OrderFrozen();
}

/// استثناء التحقق — يحمل الأنواع للواجهة ويُرقَّم DQ-1016 عند العرض
/// (نمط InvoiceValidationException حرفاً).
class OrderValidationException implements Exception {
  final List<OrderValidationError> errors;

  const OrderValidationException(this.errors);

  @override
  String toString() =>
      'رفض مدقق الطلبات: ${errors.map((e) => e.toString()).join('؛ ')}';
}

/// التحقق النقي لمسودة أمر — يعيد القائمة فارغةً صحةً. القواعد:
/// أسطر غير فارغة وطرف موجود وكمية كل سطر موجبة متسقة المكافئ.
List<OrderValidationError> validateOrderSpec(OrderSpec spec) {
  final errors = <OrderValidationError>[];
  if (spec.lines.isEmpty) {
    errors.add(const OrderLinesRequired());
  }
  if (spec.partyId == null) {
    errors.add(const OrderPartyRequired());
  }
  for (var i = 0; i < spec.lines.length; i++) {
    final l = spec.lines[i];
    final qtyOk = l.qty > 0;
    // اتساق المكافئ: بالوحدة الأساسية (لا تعبئة) الكمية تساوي
    // مكافؤها حصراً؛ وبمستوى تعبئة فالمكافئ مضاعفة الكمية بالمعامل.
    final expectedBase =
        l.unitLevelId == null ? l.qty : l.qty * l.factorAtEntry;
    final baseConsistent = l.qtyBase > 0 && l.qtyBase == expectedBase;
    if (!qtyOk || !baseConsistent) {
      errors.add(OrderQtyInvalid(i + 1));
    }
  }
  return errors;
}

/// خط الوفاء لصنف واحد داخل أمر — محسوب لا مخزن (رأس الوثيقة أعلاه).
class OrderItemFulfilment {
  final int itemId;
  final int orderedQtyBase;
  final int fulfilledQtyBase;
  final int remainingQtyBase;

  const OrderItemFulfilment({
    required this.itemId,
    required this.orderedQtyBase,
    required this.fulfilledQtyBase,
  }) : remainingQtyBase = orderedQtyBase - fulfilledQtyBase;
}

/// حصة الوفاء لأسطر الأمر: تجميع المطلوب بالمكافئ الأساسي لكل صنف
/// (الصنف نفسه قد يظهر بسطرين — فالمجموع هو المطلوب الحقيقي) ثم
/// خفض ما فُضي منه من فواتير الأمر المرجعة (أصلاً محسوبة بالتخزين).
/// المدخلات نقيّة: قائمة أسطر الأمر ومجموعُ المنفَّذ لكل صنف.
List<OrderItemFulfilment> computeOrderFulfilment(
  List<OrderLineSpec> lines,
  Map<int, int> fulfilledQtyBaseByItem,
) {
  final ordered = <int, int>{};
  for (final l in lines) {
    ordered[l.itemId] = (ordered[l.itemId] ?? 0) + l.qtyBase;
  }
  final result = <OrderItemFulfilment>[];
  // بالترتيب المعتاد للمفاتيح الصغيرة أولاً — قراءة مستقرة.
  final itemIds = ordered.keys.toList()..sort();
  for (final itemId in itemIds) {
    result.add(OrderItemFulfilment(
      itemId: itemId,
      orderedQtyBase: ordered[itemId]!,
      fulfilledQtyBase: fulfilledQtyBaseByItem[itemId] ?? 0,
    ));
  }
  return result;
}

/// هل الأمر مكتمل الوفاء؟ كل صنفٍ متبقّيه ≤ صفر (الزيادة عن المطلوب
/// تُغلق أيضاً — تسليم زائد عن التزام لا يمنع الإقفال).
bool isOrderFullyFulfilled(List<OrderItemFulfilment> fulfilment) =>
    fulfilment.isNotEmpty &&
    fulfilment.every((f) => f.remainingQtyBase <= 0);

/// التحقق النقي قبل الإغلاق — يعيد القائمة فارغةً صحةً (DQ-0706).
List<OrderValidationError> validateOrderClose(
    List<OrderItemFulfilment> fulfilment) {
  if (!isOrderFullyFulfilled(fulfilment)) {
    return [const OrderCloseIncomplete()];
  }
  return const [];
}

/// صلاحية تحويل الأمر إلى فاتورة — الأوامر المؤكدة حصراً (DQ-0707).
List<OrderValidationError> validateOrderConvertible(OrderState state) {
  if (state != OrderState.confirmed) {
    return [OrderNotConvertible(state)];
  }
  return const [];
}

/// مفتاح التسلسل السنوي لترقيم الأوامر (05 §5/D-080 عرف الفواتير):
/// لكل اتجاه أمر تسلسله — والاسم الكامل بsequenceKindLabels.
String orderSequenceKind(OrderDirection direction) => switch (direction) {
      OrderDirection.sale => 'order_sale',
      OrderDirection.purchase => 'order_purchase',
    };
