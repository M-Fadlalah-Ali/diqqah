#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س236 — رقعة التخزين الثانية: معرف عملة الصندوق بصف تقرير الصناديق
(لواجهة التسوية البنكية — عملة المسودة عملة صندوقها) والمصرّح العمومي
للرصيد الدفتري بعملة الكشف (لقطة أساس افتراضاً)."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORTS = os.path.join(ROOT, "packages", "domain", "lib", "src", "reports.dart")
DB = os.path.join(ROOT, "packages", "storage", "lib", "src", "database.dart")


def sub(s, old, new, where):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    return s.replace(old, new, 1)


def main():
    # ١) صف التقرير: معرف العملة
    s = io.open(REPORTS, encoding="utf-8").read()
    if "final int currencyId;" in s:
        print("النطاق: مرقع مسبقاً")
    else:
        s = sub(s, """  final String kind;
  final String? bankName;
  final String currencyCode;""",
                """  final String kind;
  final String? bankName;

  /// س236: معرف العملة — التسوية البنكية تعمل بعملة صندوقها (D-086).
  final int currencyId;
  final String currencyCode;""",
                "حقول الصف")
        s = sub(s, """    this.kind = 'cash',
    this.bankName,
    required this.currencyCode,""",
                """    this.kind = 'cash',
    this.bankName,
    this.currencyId = 1,
    required this.currencyCode,""",
                "بانية الصف")
        io.open(REPORTS, "w", encoding="utf-8").write(s)
        print("النطاق: معرف العملة بالصف")

    # ٢) التخزين: الاستعلام + المصرّح العمومي
    d = io.open(DB, encoding="utf-8").read()
    if "bankBoxBookBalanceDocMinor" in d:
        print("التخزين: مرقع مسبقاً")
    else:
        d = sub(d, """    'SELECT b.id AS box_id, b.name AS name, b.kind AS kind, '
    'b.bank_name AS bank_name, b.account_number AS account_number, '
    'c.code AS currency_code, '
    'a.code AS account_code, a.is_active AS account_active '""",
                """    'SELECT b.id AS box_id, b.name AS name, b.kind AS kind, '
    'b.bank_name AS bank_name, b.account_number AS account_number, '
    'b.currency_id AS currency_id, '
    'c.code AS currency_code, '
    'a.code AS account_code, a.is_active AS account_active '""",
                "استعلام الصناديق")
        d = sub(d, """      kind: (r.data['kind'] as String?) ?? 'cash',
      bankName: r.data['bank_name'] as String?,
      currencyCode: r.data['currency_code'] as String,""",
                """      kind: (r.data['kind'] as String?) ?? 'cash',
      bankName: r.data['bank_name'] as String?,
      currencyId: r.data['currency_id'] as int,
      currencyCode: r.data['currency_code'] as String,""",
                "صف التقرير")
        d = sub(d, """  /// س236: قائمة تسويات صندوق بنكي بترتيب أحدثها أولاً.""",
                """  /// س236: الرصيد الدفتري بعملة الكشف — علني لواجهة التسوية البنكية
  /// (لقطة السعر بقيمة المستند أو لقطة الأساس لعملته — حرس D-082).
  Future<int> bankBoxBookBalanceDocMinor(int boxId, {int? fxRate}) async {
    return _cashBoxBalanceDocTx(boxId, fxRate ?? baseCurrencyFxRate);
  }

  /// س236: قائمة تسويات صندوق بنكي بترتيب أحدثها أولاً.""",
                "المصرّح العمومي")
        io.open(DB, "w", encoding="utf-8").write(d)
        print("التخزين: العملة بالمصرّحين")


if __name__ == "__main__":
    main()
