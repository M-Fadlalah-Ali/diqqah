// اختبارات مجال الطلبات (س121 — 07 §3.2/D-026): آلة الحالات المحروسة
// والتحقق النقي والوفاء المحسوب — كلها نقية بلا تخزين (F-010).
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:test/test.dart';

OrderLineSpec _line(int itemId, int qty,
        {int qtyBase = 0, int factor = 1, int? level}) =>
    OrderLineSpec(
      itemId: itemId,
      unitId: 1,
      unitLevelId: level,
      factorAtEntry: factor,
      qty: qty,
      qtyBase: qtyBase == 0 ? qty : qtyBase,
    );

OrderSpec _spec({int? party = 5, List<OrderLineSpec>? lines}) => OrderSpec(
      direction: OrderDirection.sale,
      orderDate: '2026-11-07',
      partyId: party,
      lines: lines ?? [_line(1, 10)],
    );

void main() {
  group('آلة حالة الأمر (07 §1.2)', () {
    test('الانتقالات المسموحة الأربعة فقط', () {
      expect(isOrderTransitionAllowed(OrderState.draft, OrderState.confirmed),
          isTrue);
      expect(isOrderTransitionAllowed(OrderState.draft, OrderState.cancelled),
          isTrue);
      expect(isOrderTransitionAllowed(OrderState.confirmed, OrderState.closed),
          isTrue);
      expect(
          isOrderTransitionAllowed(
              OrderState.confirmed, OrderState.cancelled),
          isTrue);
    });

    test('المرفوضة: قفزة المسودة للإغلاق ولا رجوع من الطرفين النهائيين',
        () {
      expect(isOrderTransitionAllowed(OrderState.draft, OrderState.closed),
          isFalse);
      expect(isOrderTransitionAllowed(OrderState.closed, OrderState.confirmed),
          isFalse);
      expect(
          isOrderTransitionAllowed(OrderState.cancelled, OrderState.confirmed),
          isFalse);
      // حتى بقاء الطرف النهائي على ذاته ليس انتقالاً مسموحاً بالمحرك
      // (الحاجز SQL يمنعه بالتجميد).
      expect(isOrderTransitionAllowed(OrderState.closed, OrderState.closed),
          isFalse);
    });

    test('الطرفان النهائيان', () {
      expect(OrderState.closed.isTerminal, isTrue);
      expect(OrderState.cancelled.isTerminal, isTrue);
      expect(OrderState.draft.isTerminal, isFalse);
      expect(OrderState.confirmed.isTerminal, isFalse);
    });
  });

  group('التحقق النقي لمسودة الأمر', () {
    test('أمر صحيح يمر بلا أخطاء', () {
      expect(validateOrderSpec(_spec()), isEmpty);
    });

    test('بلا أسطر — DQ-0701 عرفاً', () {
      final errors = validateOrderSpec(_spec(lines: const []));
      expect(errors, hasLength(1));
      expect(errors.first, isA<OrderLinesRequired>());
    });

    test('بلا طرف — DQ-0702 عرفاً', () {
      final errors = validateOrderSpec(_spec(party: null));
      expect(errors, hasLength(1));
      expect(errors.first, isA<OrderPartyRequired>());
    });

    test('كمية صفر مرفوضة وترتيب السطر يُحمل', () {
      final errors = validateOrderSpec(_spec(lines: [
        _line(1, 10),
        _line(2, 0),
      ]));
      expect(errors, hasLength(1));
      final err = errors.first as OrderQtyInvalid;
      expect(err.lineIndex, 2);
    });

    test('مكافئ الأساسي غير متسق مع معامل التعبئة مرفوض', () {
      final errors = validateOrderSpec(_spec(lines: [
        OrderLineSpec(
            itemId: 1,
            unitId: 1,
            unitLevelId: 7,
            factorAtEntry: 12,
            qty: 2,
            qtyBase: 10), // المفروض 24
      ]));
      expect(errors, hasLength(1));
      expect(errors.first, isA<OrderQtyInvalid>());
    });

    test('أسطر متعددة بأخطاء متعددة تُجمع كلها', () {
      final errors = validateOrderSpec(_spec(party: null, lines: const []));
      expect(errors, hasLength(2));
    });
  });

  group('الوفاء المحسوب لا المخزن', () {
    test('تجميع الصنف الواحد عبر سطرين', () {
      final result = computeOrderFulfilment(
        [_line(1, 10, qtyBase: 10), _line(1, 5, qtyBase: 5), _line(2, 3)],
        const {},
      );
      expect(result, hasLength(2));
      expect(result.first.orderedQtyBase, 15); // الصنف 1 مجمّعاً
      expect(result.first.remainingQtyBase, 15);
      expect(result.last.orderedQtyBase, 3);
    });

    test('خفض المنفَّذ — والمتبقي بصفر عند الوفاء الكامل', () {
      final result = computeOrderFulfilment([_line(1, 10)], const {1: 10});
      expect(result.first.remainingQtyBase, 0);
      expect(isOrderFullyFulfilled(result), isTrue);
    });

    test('الوفاء الزائد عن الالتزام يُغلق أيضاً (المتبقي بالسالب)', () {
      final result = computeOrderFulfilment([_line(1, 10)], const {1: 12});
      expect(result.first.remainingQtyBase, -2);
      expect(isOrderFullyFulfilled(result), isTrue);
    });

    test('الجزئي لا يُغلق', () {
      final result = computeOrderFulfilment([_line(1, 10)], const {1: 4});
      expect(isOrderFullyFulfilled(result), isFalse);
    });

    test('الأمر الفارغ ليس مكتملاً', () {
      expect(isOrderFullyFulfilled(const []), isFalse);
    });

    test('حرس الإغلاق يرفض الجزئي بالخط الموثق', () {
      final partial = computeOrderFulfilment([_line(1, 10)], const {1: 4});
      expect(validateOrderClose(partial), hasLength(1));
      expect(validateOrderClose(partial).first, isA<OrderCloseIncomplete>());
      final full = computeOrderFulfilment([_line(1, 10)], const {1: 10});
      expect(validateOrderClose(full), isEmpty);
    });
  });

  group('صلاحية التحويل والتسلسل', () {
    test('المؤكد وحده يُحوَّل — DQ-0707 عرفاً', () {
      expect(validateOrderConvertible(OrderState.confirmed), isEmpty);
      for (final s in const [
        OrderState.draft,
        OrderState.closed,
        OrderState.cancelled
      ]) {
        final errors = validateOrderConvertible(s);
        expect(errors, hasLength(1));
        expect((errors.first as OrderNotConvertible).state, s);
      }
    });

    test('تسلسل لكل اتجاه', () {
      expect(orderSequenceKind(OrderDirection.sale), 'order_sale');
      expect(orderSequenceKind(OrderDirection.purchase), 'order_purchase');
    });

    test('اتجاهات الأمر بأسمائها', () {
      expect(OrderDirection.sale.label, 'أمر بيع');
      expect(OrderDirection.purchase.label, 'أمر شراء');
      expect(OrderDirection.fromStorage('sale'), OrderDirection.sale);
      expect(() => OrderDirection.fromStorage('x'), throwsArgumentError);
    });

    test('حالات الأمر بأسمائها والغريب مرفوض', () {
      expect(OrderState.draft.label, 'مسودة');
      expect(OrderState.fromStorage('confirmed'), OrderState.confirmed);
      expect(() => OrderState.fromStorage('x'), throwsArgumentError);
    });
  });
}
