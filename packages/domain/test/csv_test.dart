import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات باني CSV (F-166 — الدفعة 20): بناء نقي حصراً — الترميز
/// UTF-8 مع BOM، والتهريب وفق RFC 4180 (ما فيه فاصلة أو تنصيص أو نهاية
/// سطر يُقتبس ويُضاعف التنصيص داخله)، والبنية: عنوان ثم فارغ ثم ترويسة
/// ثم صفوف ثم تذييل زوجاً زوجاً — صورة للعرض لا إعادة حساب.
void main() {
  group('buildCsvSnapshot (F-166 — الدفعة 20)', () {
    test('BOM أول الملف كي يفتح Excel العربية سليمة', () {
      final csv = buildCsvSnapshot(
          title: 'تقرير', columns: ['أ'], rows: []);
      expect(csv.startsWith('\uFEFF'), isTrue);
    });

    test('البنية: عنوان ثم سطر فارغ ثم ترويسة ثم صفوف ثم تذييل', () {
      final csv = buildCsvSnapshot(
        title: 'ميزان المراجعة',
        columns: ['الحساب', 'مدين', 'دائن', 'الرصيد'],
        rows: [
          ['1111 الصندوق', '545,000', '0', '545,000'],
        ],
        footer: [('مجموع المدين', '546,000')],
      );
      final lines = csv.split('\n');
      expect(lines[0], '\uFEFFميزان المراجعة');
      expect(lines[1], isEmpty);
      expect(lines[2], 'الحساب,مدين,دائن,الرصيد');
      expect(lines[3], '1111 الصندوق,"545,000","0","545,000"',
          reason: 'الأرقام المعروضة بفواصلها تُقتبس حرفاً — تطابق الشاشة');
      expect(lines[4], 'مجموع المدين,"546,000"');
      expect(csv.endsWith('\n'), isTrue);
    });

    test('التهريب: التنصيص الداخلي يُضاعف والسطر الجديد يقتبس الحقل', () {
      final csv = buildCsvSnapshot(
        title: 'ت',
        columns: ['حقل'],
        rows: [
          ['حقل "مقتبس", مع فاصلة'],
          ['سطر\nجديد'],
        ],
      );
      expect(csv, contains('"حقل ""مقتبس"", مع فاصلة"'));
      expect(csv, contains('"سطر\nجديد"'));
    });

    test('الصفوف الفارغة: ترويسة وحدها — لا صمت ولا انهيار', () {
      final csv = buildCsvSnapshot(
          title: 'تقرير فارغ', columns: ['أ', 'ب'], rows: []);
      final lines = csv.split('\n');
      expect(lines[2], 'أ,ب');
      expect(lines[3], isEmpty);
    });

    test('الحقول النظيفة تمر بلا اقتباس زائد', () {
      final csv = buildCsvSnapshot(
          title: 'ت', columns: ['أ', 'ب'], rows: [['x1', 'y2']]);
      expect(csv, contains('x1,y2'));
      expect(csv, isNot(contains('"x1"')));
    });
  });
}
