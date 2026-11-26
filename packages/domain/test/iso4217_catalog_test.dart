// اختبار سلامة كتالوج ISO 4217 المضمّن — س146/D-209: الكتالوج بيانات
// مولدة آلياً بالسكربت scripts/gen_iso4217_catalog.py (CLDR عبر Babel)
// والاختبارات تحرس بنيتها: تفرد الأكواد وصيغتها ومدى الخانات وسلامة
// الأسماء والرموز وغياب أكواد الأموال والمعادن والاختبار، وحضور
// العملتين المبذورتين بالنظام بقيمهما (D-070/D-017)، ودالتا الجلب
// والبحث النقيتان بشاشة الانتقاء.
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  group('سلامة بنية الكتالوج', () {
    test('العدد ضمن المدى المتوقع — عملات الدفع النشطة حصراً', () {
      expect(kIso4217Currencies.length, inInclusiveRange(155, 165));
    });

    test('الأكواد فريدة مرتبة تصاعدياً وبصيغة ISO الثلاثية', () {
      final codes = [for (final c in kIso4217Currencies) c.code];
      expect(codes.toSet().length, codes.length);
      expect(codes, equals([...codes]..sort()));
      for (final c in kIso4217Currencies) {
        expect(RegExp(r'^[A-Z]{3}$').hasMatch(c.code), isTrue,
            reason: 'كود شاذ بالكتالوج: ${c.code}');
      }
    });

    test('الخانات 0..3 ضمن سقف التحقق الأوسع 0..8 (F-120)', () {
      for (final c in kIso4217Currencies) {
        expect(c.minorUnits, inInclusiveRange(0, 3),
            reason: 'خانات شاذة: ${c.code}=${c.minorUnits}');
      }
    });

    test('لا أكواد أموال ولا معادن ولا اختبار ولا عملات متقادمة', () {
      const banned = {
        'BOV', 'CHE', 'CHW', 'CLF', 'COU', 'MXV', 'SUC', 'USN', 'UYI',
        'UYW', 'XAU', 'XAG', 'XPD', 'XPT', 'XDR', 'XTS', 'XXX', 'XSU',
        'XUA', 'XBD', 'CUC', 'MRO', 'STD', 'SLL', 'ZWL', 'VEF',
      };
      final codes = {for (final c in kIso4217Currencies) c.code};
      expect(codes.intersection(banned), isEmpty);
    });

    test('الأسماء العربية والإنجليزية والرموز غير فارغة كلها', () {
      for (final c in kIso4217Currencies) {
        expect(c.nameAr.trim(), isNotEmpty, reason: c.code);
        expect(c.nameEn.trim(), isNotEmpty, reason: c.code);
        expect(c.symbol.trim(), isNotEmpty, reason: c.code);
      }
    });

    test('العملتان المبذورتان بالنظام حاضرتان بقيمهما (D-070/D-017)', () {
      final syp = isoCurrencyByCode('SYP')!;
      expect(syp.nameAr, 'ليرة سورية');
      expect(syp.minorUnits, 2);
      final usd = isoCurrencyByCode('USD')!;
      expect(usd.nameAr, 'دولار أمريكي');
      expect(usd.minorUnits, 2);
    });
  });

  group('isoCurrencyByCode', () {
    test('المعروف بصفه والغائب بلا صف والتطبيع يحكم', () {
      expect(isoCurrencyByCode('sar')!.code, 'SAR');
      expect(isoCurrencyByCode('  kwd ')!.code, 'KWD');
      expect(isoCurrencyByCode('ZZZ'), isNull);
      expect(isoCurrencyByCode('AB'), isNull);
      expect(isoCurrencyByCode(''), isNull);
    });

    test('الافتراضات الموثقة: ثلاثية الخليج وتونس واليابان صفرية', () {
      expect(isoCurrencyByCode('KWD')!.minorUnits, 3);
      expect(isoCurrencyByCode('BHD')!.minorUnits, 3);
      expect(isoCurrencyByCode('OMR')!.minorUnits, 3);
      expect(isoCurrencyByCode('TND')!.minorUnits, 3);
      expect(isoCurrencyByCode('JPY')!.minorUnits, 0);
    });

    test('أسماء الجزء المنقّحة للشائع والغائب بلا جزء', () {
      expect(isoCurrencyByCode('SAR')!.subunitAr, 'هللة');
      expect(isoCurrencyByCode('KWD')!.subunitAr, 'فلس');
      expect(isoCurrencyByCode('TND')!.subunitAr, 'ملّيم');
      expect(isoCurrencyByCode('EUR')!.subunitAr, 'سنت');
      expect(isoCurrencyByCode('OMR')!.subunitAr, 'بيسة');
      // دقة صفر — لا جزء للين أصلاً.
      expect(isoCurrencyByCode('JPY')!.subunitAr, isNull);
    });

    test('الرموز المطبّعة: بلا بادئة لاتينية ولا نقطة ختامية ولا علامة اتجاه',
        () {
      expect(isoCurrencyByCode('USD')!.symbol, r'$');
      expect(isoCurrencyByCode('EUR')!.symbol, '€');
      expect(isoCurrencyByCode('JPY')!.symbol, '¥');
      expect(isoCurrencyByCode('SAR')!.symbol, 'ر.س');
      for (final c in kIso4217Currencies) {
        expect(c.symbol.endsWith('.'), isFalse, reason: c.code);
        expect(c.symbol.contains('\u200f'), isFalse, reason: c.code);
      }
    });
  });

  group('isoCurrenciesSearch — بحث شاشة الانتقاء', () {
    test('الاستعلام الفارغ يعود بالكتالوج كاملاً', () {
      expect(identical(isoCurrenciesSearch(''), kIso4217Currencies), isTrue);
      expect(isoCurrenciesSearch('   ').length, kIso4217Currencies.length);
    });

    test('بالكود بجزء منه — وعقد البحث: أو الكود أو العربي أو الإنجليزي',
        () {
      final r = isoCurrenciesSearch('kw');
      expect(r.map((c) => c.code), contains('KWD'));
      // كل نتيجة تبرر ب أحد المصادر الثلاثة الموثقة (KW بالكود أو
      // بالاسم الإنجليزي «Kwanza/Kwacha» أو بالعربي).
      for (final c in r) {
        expect(
          c.code.contains('KW') ||
              c.nameEn.toLowerCase().contains('kw') ||
              c.nameAr.contains('kw'),
          isTrue,
          reason: '${c.code} لا يطابق الاستعلام بأي مصدر موثق',
        );
      }
    });

    test('بالاسم العربي بالاحتواء', () {
      expect(isoCurrenciesSearch('كويتي').map((c) => c.code),
          contains('KWD'));
    });

    test('بالاسم الإنجليزي بلا حس للحالة', () {
      expect(
          isoCurrenciesSearch('kuwait').map((c) => c.code), contains('KWD'));
    });

    test('بلا نتائج قائمة فارغة لا الكتالوج كله', () {
      expect(isoCurrenciesSearch('ZZZZZZ'), isEmpty);
    });
  });
}
