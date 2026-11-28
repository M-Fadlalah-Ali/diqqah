#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س236 — د10 البنوك (D-224): رقعة واجهة الصناديق —
1) نموذج الصندوق: نوع (نقدي/جارٍ بنكي) واسم البنك ورقم الحساب للجاري.
2) قائمة الصناديق: البنكي بأيقونته واسم بنكه وزر «تسوية بنكية».
3) شاشة التسوية البنكية الجديدة: رصيد الكشف المدخل يقارن بالدفتري
   المعلن فالفرق يُرحَّل بنمط تسوية الصندوق (57) — مع قائمة سابقاتها."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOXES = os.path.join(ROOT, "packages", "app", "lib", "boxes_screen.dart")


def sub(s, old, new, where):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    return s.replace(old, new, 1)


def main():
    s = io.open(BOXES, encoding="utf-8").read()
    if "BankReconScreen" in s:
        print("الواجهة: مرقعة مسبقاً — تُتخطى")
        return

    # ═══ 1) نموذج الصندوق: النوع والبنك ═══
    s = sub(s, """class _BoxEditScreenState extends State<BoxEditScreen> {
  final TextEditingController _name = TextEditingController();
  int _currencyId = 1;
  List<CurrencyRow> _currencies = [];
  List<String>? _errors;
  bool _busy = false;""",
            """class _BoxEditScreenState extends State<BoxEditScreen> {
  final TextEditingController _name = TextEditingController();

  /// س236 (د10 — النوع الجارٍ من الترحيلة v38): نقدي افتراضاً أو جارٍ
  /// بنكي — ومع الجاري اسم البنك ورقم الحساب (بيتان بيانيان).
  String _kind = 'cash';
  final TextEditingController _bankName = TextEditingController();
  final TextEditingController _accountNumber = TextEditingController();

  int _currencyId = 1;
  List<CurrencyRow> _currencies = [];
  List<String>? _errors;
  bool _busy = false;""",
            "حقول النموذج")
    s = sub(s, """  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }""",
            """  @override
  void dispose() {
    _name.dispose();
    _bankName.dispose();
    _accountNumber.dispose();
    super.dispose();
  }""",
            "التنظيف")
    s = sub(s, """      await widget.db.createCashBox(
        name: _name.text.trim(),
        currencyId: _currencyId,
      );""",
            """      await widget.db.createCashBox(
        name: _name.text.trim(),
        currencyId: _currencyId,
        kind: _kind,
        bankName: _bankName.text,
        accountNumber: _accountNumber.text,
      );""",
            "الحفظ")
    s = sub(s, """                DropdownButtonFormField<int>(
                  initialValue: _currencyId,
                  decoration: const InputDecoration(
                      labelText: 'العملة — وسند الصندوق بعملته حصراً'),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem<int>(
                          value: c.id,
                          child: Text('${c.code} ${c.name}')),
                  ],
                  onChanged: (value) =>
                      setState(() => _currencyId = value ?? 1),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('إنشاء الصندوق'),
                ),""",
            """                DropdownButtonFormField<int>(
                  initialValue: _currencyId,
                  decoration: const InputDecoration(
                      labelText: 'العملة — وسند الصندوق بعملته حصراً'),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem<int>(
                          value: c.id,
                          child: Text('${c.code} ${c.name}')),
                  ],
                  onChanged: (value) =>
                      setState(() => _currencyId = value ?? 1),
                ),
                // س236 (د10): نوع الصندوق — نقدي أو جارٍ بنكي.
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(
                      labelText: 'النوع — نقدي أو جارٍ بنكي (حساب بنك)'),
                  items: const [
                    DropdownMenuItem<String>(
                        value: 'cash', child: Text('نقدي')),
                    DropdownMenuItem<String>(
                        value: 'bank', child: Text('جارٍ بنكي')),
                  ],
                  onChanged: (value) =>
                      setState(() => _kind = value ?? 'cash'),
                ),
                if (_kind == 'bank') ...[
                  TextField(
                    controller: _bankName,
                    decoration: const InputDecoration(
                        labelText: 'اسم البنك',
                        helperText: 'بيان الصندوق البنكي بقوائمه'),
                  ),
                  TextField(
                    controller: _accountNumber,
                    decoration: const InputDecoration(
                        labelText: 'رقم الحساب (اختياري)'),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('إنشاء الصندوق'),
                ),""",
            "بنية النموذج")

    # ═══ 2) قائمة الصناديق: البنكي بأيقونته وزر التسوية ═══
    s = sub(s, """                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(row.name),
                    subtitle: Text('حساب ${row.accountCode}'
                        ' · ${row.currencyCode}'
                        '${row.isActive ? '' : ' — معطل'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatMinorAmount(row.balanceBaseMinor)),
                        if (row.isActive)
                          IconButton(
                            tooltip: 'تعطيل',
                            icon: const Icon(Icons.block_outlined),
                            onPressed: () => _disable(row),
                          ),
                      ],
                    ),
                  ),""",
            """                  child: ListTile(
                    // س236 (د10): البنكي بأيقونة الحساب الجاري.
                    leading: Icon(row.isBank
                        ? Icons.account_balance_outlined
                        : Icons.payments_outlined),
                    title: Text(row.name),
                    subtitle: Text((row.isBank
                            ? 'بنك ${row.bankName ?? ''}'
                                '${row.accountNumber == null ? '' : ' — ${row.accountNumber}'} · '
                            : '') +
                        'حساب ${row.accountCode}'
                        ' · ${row.currencyCode}'
                        '${row.isActive ? '' : ' — معطل'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // س236: زر التسوية البنكية للصناديق الجارية
                        // البنكية النشطة حصراً — مستندها بنمط تسوية
                        // الصندوق (57) بمدخل رصيد كشف البنك.
                        if (row.isBank && row.isActive)
                          IconButton(
                            tooltip: 'تسوية بنكية',
                            icon: const Icon(Icons.fact_check_outlined),
                            onPressed: () => Navigator.of(context)
                                .push<bool>(MaterialPageRoute<bool>(
                                    builder: (_) => BankReconScreen(
                                        db: widget.db, box: row)))
                                .then((posted) {
                              if (posted == true) _reload();
                            }),
                          ),
                        Text(formatMinorAmount(row.balanceBaseMinor)),
                        if (row.isActive)
                          IconButton(
                            tooltip: 'تعطيل',
                            icon: const Icon(Icons.block_outlined),
                            onPressed: () => _disable(row),
                          ),
                      ],
                    ),
                  ),""",
            "صف القائمة")

    io.open(BOXES, "w", encoding="utf-8").write(s)
    print("الصناديق: النموذج والقائمة — رُقعا")


if __name__ == "__main__":
    main()
