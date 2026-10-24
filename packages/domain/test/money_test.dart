import 'package:test/test.dart';
import 'package:heseb_domain/heseb_domain.dart';

void main() {
  group('Money — أعداد صحيحة بوحدات صغرى حصراً (05، س7)', () {
    test('الجمع يبقى ضمن الأعداد الصحيحة', () {
      expect(
        const Money(100000).add(const Money(250)).amountMinor,
        100250,
      );
    });

    test('الطرح السليم يعيد الفرق', () {
      expect(
        const Money(1500).subtract(const Money(1000)).amountMinor,
        500,
      );
    });

    test('الطرح يمنع السالب — قاعدة السالب الموحدة (س6)', () {
      expect(
        () => const Money(100).subtract(const Money(150)),
        throwsA(isA<NegativeBalanceException>()),
      );
    });

    test('الصفر والسالب بالتعريف', () {
      expect(const Money(0).isZero, isTrue);
      expect(const Money(500).isZero, isFalse);
      // المُنشئ لا يمنع قيمة سالبة (تُستخدم داخلياً لفروق فروق التكلفة 53/56)،
      // لكن subtract وحده صارم.
      expect(const Money(-5).isNegative, isTrue);
    });

    test('التساوي بالقيمة لا بالمرجع', () {
      expect(const Money(100), const Money(100));
      expect(const Money(100) == const Money(101), isFalse);
    });

    test('قاعدة آخر خروج يمتص الفارق — 100,000 ÷ 3 (س7)', () {
      const total = 100000;
      final base = total ~/ 3; // 33,333
      final last = total - base * 2; // 33,334
      expect(base, 33333);
      expect(last, 33334);
      expect(base + base + last, total);
      // كل حصة مبلغ صحيح بوحدات صغرى — لا كسر في أي سطر
      expect(
        Money(base).add(Money(base)).add(Money(last)).amountMinor,
        total,
      );
    });
  });
}
