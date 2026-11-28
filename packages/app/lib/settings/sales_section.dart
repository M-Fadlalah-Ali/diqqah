/// قسم سياسات البيع بالإعدادات (س233 — D-230، المرحلة أ/1 من خارطة
/// الطريق الخماسية): بطاقتا مسودات البيع (س102/س164) وسقف عهدة
/// المندوبين (س105) — المتن بنصوص دفعاته حرفاً والقسم بقائمة D-218
/// القائمة (وخانتا المرحلة ج — السطر الحر وملاحظات السطور —
/// تلحقان به لاحقاً بقرار D-235).
library;

import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

import '../input_formatters.dart';
import '../l10n/app_strings.dart';

/// قسم سياسات البيع — خيارا المنشأة ببطاقة المسودات وسقف العهدة.
class SalesSection extends StatefulWidget {
  final DiqqahDatabase db;

  const SalesSection({super.key, required this.db});

  @override
  State<SalesSection> createState() => _SalesSectionState();
}

class _SalesSectionState extends State<SalesSection> {
  bool _busy = false;

  /// س102 ثم س164: خيار حجز كميات مسودات البيع — يُقرأ النافذ عند
  /// الفتح من app_meta (نمط عرض العدّاد)، والغائب مطفأ (السلوك القائم).
  bool _heldReserve = false;

  /// س164: خيار «مسودة أكبر من المتاح» — يُقرأ النافذ عند الفتح
  /// (نمط أخيه أعلاه)، والغائب مطفأ (فحص الإنشاء القائم باقٍ).
  bool _draftOverStock = false;

  /// س105: سقف عهدة المندوبين — يُقرأ النافذ عند الفتح (نمط العدّاد
  /// D-169)، والفراغ أو الصفر بلا سقف (سلوك س104 القائم افتراضاً).
  final _custodyCapController = TextEditingController();
  String? _custodyCapResult;

  @override
  void initState() {
    super.initState();
    _loadHeldReserve();
    _loadCustodyCap();
  }

  @override
  void dispose() {
    _custodyCapController.dispose();
    super.dispose();
  }

  /// قراءة خيارَي مسودات البيع النافذَين عند الفتح وبعد كل استعادة
  /// (onRestored يعيد بناء الشاشة فتُقرأ من جديد) — نمط _loadCounterWidth ذاته.
  Future<void> _loadHeldReserve() async {
    final on = await widget.db.heldInvoicesReserveQty();
    final over = await widget.db.invoiceDraftOverStock();
    if (!mounted) return;
    setState(() {
      _heldReserve = on;
      _draftOverStock = over;
    });
  }

  /// س105: قراءة السقف النافذ عند الفتح وبعد كل استعادة — الوحّدة
  /// الصغرى معروضة مفصولة (D-102) والصفر فراغاً بلسان «بلا سقف».
  Future<void> _loadCustodyCap() async {
    final cap = await widget.db.heldReceiptCustodyCap();
    if (!mounted) return;
    setState(() {
      _custodyCapController.text = cap > 0 ? groupDigits(cap) : '';
      _custodyCapResult = null;
    });
  }

  /// حفظ السقف بعد تدقيقه — الفراغ صفر (بلا سقف) والمشوّه رفضٌ بلسان
  /// عربي بلا كتابة (وحرز التخزين ثانٍ بالسالب — نمط العدّاد D-169).
  Future<void> _saveCustodyCap() async {
    final text = _custodyCapController.text.trim();
    final cap = text.isEmpty ? 0 : parseGroupedInt(text, fallback: -1);
    if (cap < 0) {
      setState(() => _custodyCapResult =
          S.custodyCapInvalid);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.db.setHeldReceiptCustodyCap(cap);
      if (!mounted) return;
      setState(() {
        _custodyCapController.text = cap > 0 ? groupDigits(cap) : '';
        _custodyCapResult = cap > 0
            ? S.custodyCapSaved(groupDigits(cap))
            : S.custodyCapCleared;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── س164: بطاقة مسودات البيع — خيارا المنشأة معاً: الحجز
        // (س102 بمفتاحه الباقي حرفاً) صار بتابع المسودة بعد إلغاء
        // التعليق، و«مسودة أكبر من المتاح» نقطة المالك الخامسة:
        // تُحفظ المسودة التزاماً غير معلن والحاكم لحظة الترحيل.
        // إعدادا منشأة في القاعدة (app_meta) لا جهاز، والحجز محسوب
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.salesDraftsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.salesDraftsBody,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(S.draftsHoldStock),
                  subtitle: const Text(
                      S.draftsHoldStockBody),
                  value: _heldReserve,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          await widget.db.setHeldInvoicesReserveQty(v);
                          if (mounted) setState(() => _heldReserve = v);
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(S.allowDraftOverStock),
                  subtitle: const Text(
                      S.allowDraftOverStockBody),
                  value: _draftOverStock,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          await widget.db.setInvoiceDraftOverStock(v);
                          if (mounted) setState(() => _draftOverStock = v);
                        },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── س105: بطاقة سقف عهدة المندوبين — دفعة المندوب الرابعة:
        // ما يحمله المندوب الواحد من تحصيلات معلقة له سقفٌ من المنشأة
        // لا سكوت شيفرة، إعداد قاعدةٍ (app_meta) فيسري على كل مستخدميها
        // (عرف س102)، والفرض عند التعليق بالمحرك ذاته لا الواجهة.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.agentCollectionsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  S.agentCollectionsBody,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _custodyCapController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: S.custodyCapLabel,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _busy ? null : _saveCustodyCap,
                  child: const Text(S.saveCustodyCap),
                ),
                if (_custodyCapResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_custodyCapResult!),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
