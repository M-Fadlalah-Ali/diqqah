import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'input_formatters.dart';

/// شاشة العملات وأسعار الصرف — الدفعة 34 «تعدد العملات الفعلي»
/// (F-120/F-121، D-194): القائمة من currenciesOf لحظياً والإدارة بها
/// — إضافة عملة جديدة حصراً (لا تعديل بعد الحفظ — نمط المرجع الدائم
/// 03 §6-3) والتعطيل بحرستيه بلا حذف أبداً — وأسعار الصرف التاريخية
/// مسجلة بيوم واحد لا يقبل ثانية والسجل المحفوظ لا يُعدل ولا يُحذف
/// (التجميد نمط F-140 بطبقة القاعدة — رسالة المحرك برسالتها لا صياغة
/// واجهة موازية). ولقطة المستند اليدوية باقية (D-070): الجدول يملأ
/// الافتراض فحسب — يقرأه مُدخل الفاتورة والسند من latestExchangeRate.
/// وأزرار الإضافة ظاهرة لا مدفونة (درس D-098).
class CurrenciesScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const CurrenciesScreen({super.key, required this.db});

  @override
  State<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends State<CurrenciesScreen> {
  List<CurrencyRow>? _currencies;
  String? _notice;
  String? _error;

  // قسم أسعار الصرف — العملة المختارة وسجلها وحقلا التسجيل.
  int? _rateCurrencyId;
  List<ExchangeRateEntry>? _rates;
  final _rateDate = TextEditingController(text: todayIsoDate());
  final _rateValue = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _rateDate.dispose();
    _rateValue.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final currencies = await widget.db.currenciesOf();
    List<ExchangeRateEntry>? rates;
    if (_rateCurrencyId != null) {
      final live = currencies.any((c) => c.id == _rateCurrencyId);
      rates = live ? await widget.db.exchangeRatesOf(_rateCurrencyId!) : null;
      if (!live) _rateCurrencyId = null;
    }
    if (!mounted) return;
    setState(() {
      _currencies = currencies;
      _rates = rates;
      _error = null;
      // _notice لا تُمسح هنا — نمط الصناديق: بطاقة النجاح تبقى حتى
      // الإجراء التالي، وإلا ومضت وأفلتت قبل أن يراها المالك.
    });
  }

  Future<void> _openAdd() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final minor = TextEditingController(text: '2');
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('عملة جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'الكود (ثلاثة أحرف لاتينية — مثال: EUR)',
              ),
            ),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'اسم العملة'),
            ),
            TextField(
              controller: minor,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'خانات الوحدة الصغرى (0..8 — الافتراض 2)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('تراجع')),
          FilledButton(
            onPressed: () {
              final existingCodes = {
                for (final c in _currencies ?? const <CurrencyRow>[])
                  normalizeCurrencyCode(c.code),
              };
              final minorUnits = int.tryParse(minor.text.trim());
              final errors = validateCurrencySpec(
                CurrencySpec(
                  code: code.text,
                  name: name.text,
                  minorUnits: minorUnits ?? -1,
                ),
                existingCodes: existingCodes,
              );
              if (minorUnits == null && errors.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(
                    content: Text(
                        'خانات الوحدة الصغرى عدداً صحيحاً بين 0 و8')));
                return;
              }
              if (errors.isNotEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                    content: Text(describeCurrencyError(errors.first))));
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (created != true) return;
    try {
      await widget.db.currenciesAdd(
        code: code.text,
        name: name.text,
        minorUnits: int.parse(minor.text.trim()),
      );
      if (!mounted) return;
      setState(() =>
          _notice = 'أُضيفت العملة ${normalizeCurrencyCode(code.text)}');
      _reload();
    } catch (e) {
      if (!mounted) return;
      // رسالة المحرك برسالتها (تفرد الكود على ما خُزّن).
      setState(() => _error = '$e');
    }
  }

  Future<void> _deactivate(CurrencyRow currency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تعطيل العملة ${currency.code}؟'),
        content: const Text(
          'التعطيل للعملات غير المستخدمة حصراً — والعملة عليها أي مرجع '
          '(فاتورة أو سند أو صندوق أو طرف أو قيد أو سعر صنف) ترفض '
          'التعطيل برسالته. والتعطيل بلا حذف أبداً.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تعطيل')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.db.currenciesDeactivate(currency.id);
      if (!mounted) return;
      setState(() => _notice = 'عُطّلت العملة ${currency.code}');
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _recordRate() async {
    final cid = _rateCurrencyId;
    if (cid == null) {
      setState(() => _error = 'اختَر عملة غير الأساسية أولاً — مقياس الكل '
          'لا يقاس');
      return;
    }
    final rate = parseGroupedInt(_rateValue.text.trim());
    final date = _rateDate.text.trim();
    final cur = _currencies!
        .where((c) => c.id == cid)
        .map((c) => (isBase: c.isBase, code: c.code))
        .toList();
    final errors = validateExchangeRateRecord(
      rateToBase: rate,
      date: date,
      todayIso: todayIsoDate(),
      isBase: cur.isNotEmpty && cur.first.isBase,
    );
    if (errors.isNotEmpty) {
      setState(() => _error = describeCurrencyError(errors.first));
      return;
    }
    try {
      await widget.db.exchangeRateRecord(
        currencyId: cid,
        date: date,
        rateToBase: rate,
      );
      if (!mounted) return;
      setState(() => _notice =
          'حُفظ سعر ${cur.first.code} بتاريخ $date — الأسعار المحفوظة '
          'لا تُعدل أبداً');
      _rateValue.clear();
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _currencies;
    return Scaffold(
      appBar: AppBar(title: const Text('العملات وأسعار الصرف')),
      body: currencies == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_notice != null)
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_notice!),
                    ),
                  ),
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'العملات (F-120)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'الأساسية واحدة لا ثانية لها — عملة المستندات '
                          'والقيود، والإضافة تشريع جديد والتعطيل بلا حذف.',
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _openAdd,
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة عملة'),
                        ),
                        const SizedBox(height: 8),
                        for (final c in currencies)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              c.isBase
                                  ? Icons.star
                                  : Icons.currency_exchange_outlined,
                              size: 22,
                            ),
                            title: Text(
                                '${c.code} — ${c.name}'
                                '${c.isBase ? ' (الأساسية)' : ''}'),
                            subtitle:
                                Text('خانات الوحدة الصغرى: ${c.minorUnits}'),
                            trailing: c.isBase
                                ? null
                                : IconButton(
                                    tooltip: 'تعطيل',
                                    icon: const Icon(
                                        Icons.toggle_off_outlined),
                                    onPressed: () => _deactivate(c),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'أسعار الصرف التاريخية (F-121)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'سجل بيوم واحد لكل عملة — والسجل المحفوظ لا '
                          'يُعدل ولا يُحذف أبداً. والسعر مكبَّر ×1,000,000 '
                          '(مثال: 15000000 = 15) على اصطلاح لقطة '
                          'المستندات، ولقطة المستند اليدوية باقية — '
                          'الجدول يملأ الافتراض فحسب.',
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _rateCurrencyId,
                          decoration: const InputDecoration(
                              labelText: 'العملة (غير الأساسية)'),
                          items: [
                            for (final c in currencies)
                              if (!c.isBase)
                                DropdownMenuItem<int>(
                                    value: c.id,
                                    child: Text('${c.code} — ${c.name}')),
                          ],
                          onChanged: (value) async {
                            setState(() {
                              _rateCurrencyId = value;
                              _rates = null;
                            });
                            if (value != null) {
                              final rates =
                                  await widget.db.exchangeRatesOf(value);
                              if (!mounted) return;
                              setState(() => _rates = rates);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _rateDate,
                              decoration: const InputDecoration(
                                  labelText: 'التاريخ (YYYY-MM-DD)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _rateValue,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                ThousandsSeparatorInputFormatter()
                              ],
                              decoration: const InputDecoration(
                                  labelText:
                                      'السعر مكبَّر ×1,000,000 (مثال: 15000000 = 15)'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _recordRate,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('تسجيل السعر'),
                        ),
                        const SizedBox(height: 8),
                        if (_rates != null)
                          for (final r in _rates!)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.history, size: 20),
                              title: Text(r.date),
                              trailing: Text(
                                  displayRateToBase(r.rateToBase) +
                                      ' لكل 1 من العملة'),
                            ),
                        if (_rates != null && _rates!.isEmpty)
                          const Text(
                            'لا أسعار مسجلة لهذه العملة بعد — والقسيمة '
                            'تعمل بلقطة المستند اليدوية كما هي.',
                            style: TextStyle(fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// صياغة لفظ خطأ العملة — الواجهة وحدها تقرر الصياغة المعروضة
/// (فصل المجال عن العرض — نمط الوحدات والتجميعي).
String describeCurrencyError(CurrencyValidationError error) {
  if (error is CurrencyCodeInvalid) {
    return 'كود العملة ثلاثة أحرف لاتينية A-Z حصراً (مثال: EUR) — '
        'والمدخل «${error.raw}» لا يصح';
  }
  if (error is CurrencyCodeTaken) {
    return 'الكود «${error.code}» محفوظ سابقاً — الأكواد فريدة مهما '
        'كان مصير العملة لاحقاً (اللقطات تحيل إليها)';
  }
  if (error is CurrencyNameRequired) {
    return 'اسم العملة إلزامي';
  }
  if (error is CurrencyMinorUnitsInvalid) {
    return 'خانات الوحدة الصغرى عدداً بين 0 و8 — والمدخل '
        '${error.value} خارج المدى';
  }
  if (error is CurrencyRateInvalid) {
    return 'السعر عدد صحيح موجب مكبَّر — الصفر والسالب بلا معنى صرفي';
  }
  if (error is CurrencyRateDateInvalid) {
    return 'التاريخ بصيغة YYYY-MM-DD صالحة — والمدخل «${error.raw}» '
        'لا يصح';
  }
  if (error is CurrencyRateDateFuture) {
    return 'لا سعر مستقبلي — السعر يُسجل لليوم أو الماضي حصراً';
  }
  if (error is CurrencyBaseProtected) {
    return 'عملة الأساسية لا تُسجل لها أسعار ولا تُعطَّل — هي مقياس الكل';
  }
  if (error is CurrencyInUse) {
    return 'العملة عليها ${error.references} مرجع قائم — التعطيل '
        'لغير المستخدمة حصراً';
  }
  return 'عملة غير سليمة';
}
