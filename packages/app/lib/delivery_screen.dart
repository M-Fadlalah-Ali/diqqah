import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import 'invoices_screen.dart' show InvoiceDetailScreen;
import 'print_service.dart';

/// شاشة «متابعة التسليم» — س-139/D-133 (دفعة 12) بلفظ المالك «٣. في
/// الهيكلية» وحسمه لسؤال النافذة: شاشة قائمة دائمة لا حوار عابر.
///
/// القائمة: كل سطر بيع غير مستلم — الصنف والكمية، الفاتورة وتاريخها
/// والطرف، المورد المسؤول — الأقدم أولاً. الأفعال: فلتر بالمورد وبحث
/// بالصنف والطرف، زر «سُلِّم» بضغطة واحدة يحفظ فوراً، والنقر على السطر
/// يفتح فاتورته، وطباعة PDF للتقرير المعروض.
///
/// والصلاحية: وحدة مستقلة «delivery» افتراضها بيد المدير حصراً وقابلة
/// للتفويض (D-133 نمط D-049) — والفرض بيد الهيكلية ككل الوحدات.
/// وعلم العمل لا محاسبة: «سُلِّم» تحديث علم السطر حصراً لا قيد ولا
/// حركة مخزون ولا ذمة (D-131).
class DeliveryScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const DeliveryScreen({super.key, required this.db});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  Future<List<UndeliveredLineRow>>? _rows;

  /// فلتر المورد — null الكل، ومعرفه فلترة القائمة المعروضة حصراً.
  int? _supplierFilter;

  /// بحث بالصنف والطرف — نص حر يطابق الاسمين والكود.
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _rows = widget.db.undeliveredSaleLinesReport();
    });
  }

  /// س-139: زر «سُلِّم» بضغطة واحدة — يحفظ علم السطر فوراً (D-131)
  /// فتغيب من القائمة، والفشل رسالة لا صمت.
  Future<void> _markDelivered(UndeliveredLineRow row) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.db.setInvoiceLineDelivered(row.lineId, delivered: true);
      _reload();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تحديث علم التسليم — $e')),
      );
    }
  }

  /// النقر على السطر يفتح فاتورته (س-139) — والعودة تُحدّث القائمة
  /// إن علّم المالك مربعاً هناك.
  Future<void> _openInvoice(UndeliveredLineRow row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceDetailScreen(
            db: widget.db, invoiceId: row.invoiceId),
      ),
    );
    _reload();
  }

  /// طباعة PDF للقائمة المعروضة بفلترها وبحثها الحاليين — قسيمة A4
  /// عرضية بنمط التقارير، والفشل رسالة لا صمت.
  Future<void> _print(List<UndeliveredLineRow> rows) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildDocumentPdf(
        title: 'متابعة التسليم — الأسطر غير المستلمة',
        headerPairs: const [],
        columns: const ['الصنف', 'الكمية', 'الفاتورة', 'التاريخ', 'الطرف', 'المورد المسؤول'],
        rows: [
          for (final row in rows)
            [
              '${row.itemSku} ${row.itemName}',
              '${row.qtyBase}',
              row.invoiceNumber,
              row.invoiceDate,
              row.partyName ?? '—',
              row.supplierName ?? 'بلا مورد',
            ],
        ],
        footerPairs: [
          ('عدد الأسطر غير المستلمة', '${rows.length}'),
        ],
        format: resolvePageFormat(docKind: 'report'),
      );
      await sharePdfBytes(bytes, 'متابعة التسليم.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر توليد الطباعة — $e')),
      );
    }
  }

  /// تطبيق الفلتر والبحث على الصفوف — عرضٌ فوق القراءة لا حساب جديد.
  List<UndeliveredLineRow> _applyFilters(List<UndeliveredLineRow> all) {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final row in all)
        if (_supplierFilter == null ||
            row.supplierPartyId == _supplierFilter)
          if (query.isEmpty ||
              row.itemName.toLowerCase().contains(query) ||
              row.itemSku.toLowerCase().contains(query) ||
              (row.partyName ?? '').toLowerCase().contains(query))
            row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('متابعة التسليم')),
      body: FutureBuilder<List<UndeliveredLineRow>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final rows = _applyFilters(all);
          final suppliers = <int, String>{
            for (final row in all)
              if (row.supplierPartyId != null)
                row.supplierPartyId!: row.supplierName ?? '',
          };
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          labelText: 'بحث بالصنف أو الطرف',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _supplierFilter,
                        decoration:
                            const InputDecoration(labelText: 'حسب المورد'),
                        items: [
                          const DropdownMenuItem<int>(
                              value: null, child: Text('كل الموردين')),
                          for (final entry in suppliers.entries)
                            DropdownMenuItem<int>(
                                value: entry.key,
                                child: Text(entry.value)),
                        ],
                        onChanged: (value) =>
                            setState(() => _supplierFilter = value),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                        'غير مستلم: ${rows.length} من ${all.length}'),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed:
                            rows.isEmpty ? null : () => _print(rows),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('طباعة / PDF'),
                      ),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'لا أسطر غير مستلمة — كل البيع سُلِّم',
                            textAlign: TextAlign.center),
                      ))
                    : ListView(
                        children: [
                          for (final row in rows)
                            ListTile(
                              title: Text(
                                  '${row.itemSku} ${row.itemName} × ${row.qtyBase}'),
                              subtitle: Text(
                                  '${row.invoiceNumber} · ${row.invoiceDate}'
                                  ' · ${row.partyName ?? 'بلا طرف'}'
                                  ' · المورد: ${row.supplierName ?? 'بلا مورد'}'),
                              trailing: FilledButton.tonal(
                                onPressed: () => _markDelivered(row),
                                child: const Text('سُلِّم'),
                              ),
                              onTap: () => _openInvoice(row),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
