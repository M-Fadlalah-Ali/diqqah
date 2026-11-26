import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات مطابقة دفتر المخزون — الدفعة 31 (ثامنة م2: ربط المخزون
/// بالدفتر بصرياً — 07 §3.1/D-012/D-067/F-178).
///
/// المجال النقي حصراً: البناء من خامتين (أسطر القيود المرحّلة المربوطة
/// بحركاتها وقيمة المخزون بالأرصدة) والدمج بالصنف والميل مشتقاً لا
/// مخزناً — نمط بنّاءي التقارير (س-50/س-71).
InventoryLedgerRawRow ledgerRow(int id, String sku, int debit, int credit) =>
    InventoryLedgerRawRow(
        itemId: id, sku: sku, name: 'صنف $sku',
        debitMinor: debit, creditMinor: credit);

InventoryStockRawRow stockRow(int id, String sku, int value) =>
    InventoryStockRawRow(
        itemId: id, sku: sku, name: 'صنف $sku', valueMinor: value);

void main() {
  test('الحالة المطابقة: القيمة الدفترية (مدين − دائن) تساوي قيمة '
      'المخزون فالثابت صحيح على كل صنف والإجمالي (F-178)', () {
    final report = buildInventoryLedgerReconciliation([
      ledgerRow(1, 'A-1', 500000, 200000),
    ], [
      stockRow(1, 'A-1', 300000),
    ]);
    expect(report.rows, hasLength(1));
    final row = report.rows.single;
    expect(row.ledgerValueMinor, 300000);
    expect(row.stockValueMinor, 300000);
    expect(row.driftMinor, 0);
    expect(row.isMatched, isTrue);
    expect(report.isMatched, isTrue);
    expect(report.driftMinor, 0);
    expect(report.ledgerTotalMinor, 300000);
    expect(report.stockTotalMinor, 300000);
  });

  test('حالة الميل: اختلافٍ بين الطرفين يظهر بأرقامه لا يطمَر — '
      'والإشارة بالاتجاهين (زائد وناقص)', () {
    final plus = buildInventoryLedgerReconciliation([
      ledgerRow(1, 'A-1', 500000, 0),
    ], [
      stockRow(1, 'A-1', 400000),
    ]);
    expect(plus.driftMinor, 100000);
    expect(plus.isMatched, isFalse);
    expect(plus.rows.single.isMatched, isFalse);

    final minus = buildInventoryLedgerReconciliation([
      ledgerRow(1, 'A-1', 300000, 0),
    ], [
      stockRow(1, 'A-1', 500000),
    ]);
    expect(minus.driftMinor, -200000);
    expect(minus.isMatched, isFalse);
  });

  test('الصنف بجهة واحدة فقط يظهر بطرف صفر — لا انفراد يخفى', () {
    final report = buildInventoryLedgerReconciliation([
      ledgerRow(1, 'A-1', 700000, 0),
    ], [
      stockRow(2, 'B-2', 250000),
    ]);
    expect(report.rows, hasLength(2));
    final a = report.rows.firstWhere((r) => r.sku == 'A-1');
    final b = report.rows.firstWhere((r) => r.sku == 'B-2');
    expect(a.ledgerValueMinor, 700000);
    expect(a.stockValueMinor, 0);
    expect(b.ledgerValueMinor, 0);
    expect(b.stockValueMinor, 250000);
    expect(report.isMatched, isFalse);
    expect(report.ledgerTotalMinor, 700000);
    expect(report.stockTotalMinor, 250000);
  });

  test('الدمج بعدة أصناف بترتيب الكود — والإجماليان مجموع الصفوف', () {
    final report = buildInventoryLedgerReconciliation([
      ledgerRow(2, 'B-1', 100000, 40000),
      ledgerRow(1, 'A-2', 60000, 0),
    ], [
      stockRow(1, 'A-2', 60000),
      stockRow(2, 'B-1', 60000),
    ]);
    expect([for (final r in report.rows) r.sku], ['A-2', 'B-1']);
    expect(report.isMatched, isTrue,
        reason: '60,000 مطابق و60,000 مطابق — الإجمالي كذلك');
    expect(report.ledgerTotalMinor, 120000);
    expect(report.stockTotalMinor, 120000);
  });

  test('الطرفان فارغان: تقرير بلا صفوف متطابق بالبناء', () {
    final report =
        buildInventoryLedgerReconciliation(const [], const []);
    expect(report.rows, isEmpty);
    expect(report.isMatched, isTrue);
    expect(report.driftMinor, 0);
  });
}
