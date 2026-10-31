import 'package:test/test.dart';
import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات نموذج الصلاحيات (F-080، دفعة إغلاق النواة س37) — القراءة
/// النقية حصراً: التحليل والصياغة والمفاتيح الافتراضية للأدوار الأربعة.
void main() {
  group('RolePermissions — التحليل والسماح', () {
    test('النجمة تسمح بكل الوحدات', () {
      const p = RolePermissions.all();
      for (final key in moduleKeys) {
        expect(p.allows(key), isTrue, reason: 'المفتاح $key يُسمح به');
      }
      expect(p.isAll, isTrue);
      expect(p.summary, 'كل الوحدات');
      expect(p.keys, hasLength(moduleKeys.length));
    });

    test('قائمة مفاتيح تسمح بها حصراً — والمجهول يُرفض', () {
      const p = RolePermissions('parties,invoices');
      expect(p.allows('parties'), isTrue);
      expect(p.allows('invoices'), isTrue);
      expect(p.allows('boxes'), isFalse);
      expect(p.allows('reports'), isFalse);
      expect(p.isAll, isFalse);
    });

    test('المفتاح المجهول المخزن يُسقط صامتاً — لا وحدة لم تعتمد تُتيح', () {
      const p = RolePermissions('parties,ghost_key,boxes');
      expect(p.keys, ['parties', 'boxes']);
      expect(p.allows('ghost_key'), isFalse);
    });

    test('القائمة الفارغة دور مشروع بلا وحدات ظاهرة', () {
      const p = RolePermissions('');
      expect(p.keys, isEmpty);
      expect(p.summary, 'لا وحدات');
      expect(p.allows('parties'), isFalse);
    });
  });

  group('RolePermissions.format — الصياغة بترتيب القائمة المعروفة', () {
    test('يعيد الترتيب ويكشف التكرار والمجهول', () {
      final formatted = RolePermissions.format(
          ['boxes', 'ghost', 'parties', 'boxes', 'invoices']);
      expect(formatted, 'parties,invoices,boxes');
      // والقراءة تعود بالسماح نفسه
      expect(RolePermissions(formatted).allows('invoices'), isTrue);
      expect(RolePermissions(formatted).allows('ghost'), isFalse);
    });

    test('كل المفاتيح المختارة صيغتها النجمة لا قائمة مطولة', () {
      final formatted = RolePermissions.format(moduleKeys);
      expect(formatted, '*');
    });
  });

  group('الأدوار النمطية الأربعة الافتراضية (F-080/D-100)', () {
    test('الأربعة مزروعة بأسمائها المعتمدة', () {
      expect(defaultRolesPermissions.keys,
          ['مدير', 'محاسب', 'أمين مستودع', 'بائع']);
    });

    test('المدير كل الوحدات — والبقية لا نجمة أبداً', () {
      expect(defaultRolesPermissions['مدير'], '*');
      for (final entry in defaultRolesPermissions.entries) {
        if (entry.key == 'مدير') continue;
        expect(entry.value, isNot('*'),
            reason: 'دور ${entry.key} لا يملك النجمة');
        expect(entry.value, isNotEmpty);
      }
    });

    test('المحاسب المحاسبة كلها بلا الصلاحيات ولا المزامنة', () {
      final p = RolePermissions(defaultRolesPermissions['محاسب']!);
      expect(p.allows('invoices'), isTrue);
      expect(p.allows('vouchers'), isTrue);
      expect(p.allows('boxes'), isTrue);
      expect(p.allows('reports'), isTrue);
      expect(p.allows('ledger'), isTrue);
      expect(p.allows('settings'), isTrue);
      expect(p.allows('roles'), isFalse, reason: 'الصلاحيات للمدير');
      expect(p.allows('sync'), isFalse);
    });

    test('أمين المستودع بلا نقود باتاً — وبائع يبيع ويقبض بلا تقارير', () {
      final storekeeper =
          RolePermissions(defaultRolesPermissions['أمين مستودع']!);
      expect(storekeeper.allows('items'), isTrue);
      expect(storekeeper.allows('reports'), isTrue);
      expect(storekeeper.allows('invoices'), isFalse);
      expect(storekeeper.allows('vouchers'), isFalse);
      expect(storekeeper.allows('boxes'), isFalse);

      final seller = RolePermissions(defaultRolesPermissions['بائع']!);
      expect(seller.allows('parties'), isTrue);
      expect(seller.allows('invoices'), isTrue);
      expect(seller.allows('vouchers'), isTrue);
      expect(seller.allows('reports'), isFalse);
      expect(seller.allows('settings'), isFalse);
      expect(seller.allows('roles'), isFalse);
    });

    test('كل مفتاح افتراضي مكتوب معروف في قائمة الوحدات', () {
      for (final entry in defaultRolesPermissions.entries) {
        if (entry.value == '*') continue;
        for (final key in entry.value.split(',')) {
          expect(moduleKeys, contains(key),
              reason: 'دور ${entry.key} يحمل مفتاحاً مجهولاً $key');
        }
      }
    });
  });

  test('مفاتيح الوحدات خمسة عشر بلا تكرار وكلها بتسمية عربية', () {
    expect(moduleKeys, hasLength(15));
    expect(moduleKeys.toSet(), hasLength(moduleKeys.length));
    for (final key in moduleKeys) {
      expect(moduleLabels[key], isNotNull, reason: 'تسمية $key غائبة');
    }
    // مدخل السندات من ضمنها (D-098)
    expect(moduleKeys, contains('vouchers'));
    expect(moduleLabels['vouchers'], 'السندات');
  });
}
