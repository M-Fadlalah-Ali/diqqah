import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// F-150/D-210 P0 (س148): دليل الدمج الحي — المكتبة المدمجة عبر hooks
/// (user_defines sqlite3mc) تجيب `PRAGMA cipher` غير فارغة (توثيق drift
/// «Important notice» حرفاً — فحص debug). بلا الدمج يفشل هذا الاختبار
/// فلا نص صريح صامت يمر في البيئة المحكومة.
void main() {
  test('الدمج MC حاضر: PRAGMA cipher غير فارغة على المكتبة المدمجة', () {
    final db = sqlite3.openInMemory();
    final cipher = db.select('PRAGMA cipher;');
    // ignore: avoid_print
    print('PRAGMA cipher = $cipher');
    expect(cipher, isNotEmpty,
        reason: 'الدمج SQLite3MultipleCiphers يجب أن يكون حاضراً');
    db.close();
  });
}
