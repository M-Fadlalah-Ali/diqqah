import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'input_formatters.dart';
import 'reports_screen.dart' show formatMinorAmount;

/// شاشة الأطراف (F-020/F-021 — دفعة م1 الأولى، س-29..س-35).
///
/// - القائمة تعرض الجميع بصيغة «الاسم (الرقم)» مرتبة بالترتيب الرقمي
///   الذكي (1، 2، 10 لا 1، 10، 2 — D-063).
/// - البحث خانة واحدة جامعة (الاسم والرقم والهاتف) بكلمات متفرقة تلتقي
///   وتطبيع عربي في البحث فقط (D-064/س-31)، والنتيجة الفارغة رسالة لا
///   صمت (س-31).
/// - المعطّل يظهر بشارة لا يُخفى: إعادة التفعيل ممكنة متى شئت (س-33)،
///   أما استبعاد المعطل فهو موضع «قوائم الاختيار الجديد» في الفواتير
///   لاحقاً لا موضع القائمة الإدارية هذه.
/// - زر الحذف غير موجود أصلاً في أي بطاقة (س-33).
class PartiesScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const PartiesScreen({super.key, required this.db});

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  String _query = '';

  // التدفق يُنشأ مرة واحدة لعمر الحالة لا عند كل بناء (علّة CI 2026-10-29
  // س23): تمرير تدفق جديد في build يعيد StreamBuilder الاشتراك عند كل إعادة
  // بناء فيحلّق الجلب والتحديث بلا نهاية — لا تستقر pumpAndSettle قط ولا
  // يهدأ ملف الاختبار، والتطبيق نفسه يهدر اشتراكات قاعدة البيانات.
  late final Stream<List<Party>> _partiesStream = widget.db
      .select(widget.db.parties)
      .watch()
      .map(
        (rows) => [...rows]
          ..sort((a, b) => comparePartyNumbers(a.number, b.number)),
      );

  void _openNewParty() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartyEditScreen(db: widget.db),
      ),
    );
  }

  void _openParty(Party party) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartyEditScreen(db: widget.db, existing: party),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأطراف')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewParty,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة طرف'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث بالاسم أو الرقم أو الهاتف',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Party>>(
              stream: _partiesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!;
                final visible = all
                    .where(
                      (p) => PartySearchFields(
                        name: p.name,
                        number: p.number,
                        phone: p.phone ?? '',
                      ).matchesQuery(_query),
                    )
                    .toList();
                if (visible.isEmpty) {
                  // النتائج الفارغة برسالة لا بصمت (س-31)
                  return Center(
                    child: Text(
                      all.isEmpty
                          ? 'لا أطراف بعد — أضف أول طرف بزر «إضافة طرف»'
                          : 'لا نتائج مطابقة للبحث',
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final party = visible[index];
                    final kind = PartyKind.fromStorage(party.kind);
                    return ListTile(
                      leading: Icon(
                        party.isActive
                            ? Icons.person_outline
                            : Icons.person_off_outlined,
                      ),
                      title: Text(partyDisplayLabel(party.name, party.number)),
                      subtitle: Text(
                        kind.label + (party.phone == null ? '' : ' · ${party.phone}'),
                      ),
                      trailing: party.isActive
                          ? null
                          : const Chip(
                              label: Text('معطّل'),
                              visualDensity: VisualDensity.compact,
                            ),
                      onTap: () => _openParty(party),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة طرف — إضافة أو تعديل (F-020، س-29/س-32).
///
/// - الرقم يقترح آلياً للجديد ويُعدَّل قبل الحفظ حصراً، وفي التعديل لا
///   حقل تعديل له أصلاً (D-063) — الهوية الثابتة التي ترتبط بها المعاملات
///   (D-062).
/// - الاسم إلزامي وحده (س-29) ومنع تكراره الحرفي صارم (D-065).
/// - العملة معبأة مسبقاً بالأساسية ولا تُحفظ فارغة (D-066) — الخانة
///   الوحيدة المعرفة حتى الآن هي الأساسية (D-017)، والتغيير يُفتح مع
///   جدول العملات في دفعته.
/// - حد الائتمان اختياري للعميل والمزدوج، والفراغ فيه «بلا سقف» مشروع
///   (س-34/F-023).
class PartyEditScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final Party? existing;

  const PartyEditScreen({super.key, required this.db, this.existing});

  @override
  State<PartyEditScreen> createState() => _PartyEditScreenState();
}

class _PartyEditScreenState extends State<PartyEditScreen> {
  late final TextEditingController _number;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _credit = TextEditingController();
  late PartyKind _kind;

  /// العملة الأساسية حصراً حتى تُبنى جدول العملات (D-017/D-066).
  static const int _baseCurrencyId = 1;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final party = widget.existing;
    if (party != null) {
      _number = TextEditingController(text: party.number);
      _name.text = party.name;
      _phone.text = party.phone ?? '';
      _address.text = party.address ?? '';
      // مفصولاً (D-102): الحد مبلغ فتُعرض فوائله أثناء الكتابة.
      _credit.text = party.creditLimitBaseMinor == null
          ? ''
          : groupDigits(party.creditLimitBaseMinor!);
      _kind = PartyKind.fromStorage(party.kind);
    } else {
      _number = TextEditingController();
      _kind = PartyKind.customer;
      _suggestNumber();
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _credit.dispose();
    super.dispose();
  }

  /// التوليد الآلي (D-063/س-29): مقترح لا يكتب فوق ما بدأ المستخدم
  /// بكتابته قبل اكتمال القراءة.
  Future<void> _suggestNumber() async {
    final suggestion = await widget.db.nextPartyNumberSuggestion();
    if (!mounted || _isEdit || _number.text.isNotEmpty) return;
    setState(() => _number.text = suggestion);
  }

  /// قراءة حد الائتمان: الفراغ «بلا سقف» (null)؛ وإدخال شاذ (فائض طول
  /// مثلاً رغم قيد الأرقام) يعود -1 فيلتقطه مدقق المجال (س-34).
  int? _parseCreditLimit() {
    final text = _credit.text.trim();
    if (text.isEmpty) return null;
    return parseGroupedInt(text, fallback: -1);
  }

  ExistingParty _asExisting(Party party) => ExistingParty(
        id: party.id,
        number: party.number,
        name: party.name,
        isActive: party.isActive,
      );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final draft = PartyDraft(
        number: _number.text,
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        kind: _kind,
        currencyId: _baseCurrencyId,
        creditLimitBaseMinor: _parseCreditLimit(),
      );
      final rows = await widget.db.select(widget.db.parties).get();
      final errors = validatePartyDraft(
        draft,
        existing: PartyUniquenessIndex.build(rows.map(_asExisting)),
        excludePartyId: widget.existing?.id,
      );
      if (errors.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(partyErrorText(errors.first)),
              duration: const Duration(seconds: 4),
            ),
          );
        return;
      }
      if (_isEdit) {
        // س-155/D-153 (دفعة 17): الرقم يعدل بلفظ المالك (س50/1 «تمام»)
        // — والتفرد دُقق أعلاه بالمدقق المستثنياً النفس، والمعاملات
        // كلها بمعرفه الخفي فلا ينكسر بها شيء. والحفظ بطبقة النظافة
        // D-170 ذاتها التي دُقق بها فما يُخزَّن هو المرئي المدقق
        // (D-174 — الدفعة 20: اتساق الحفظ مع التدقيق).
        await widget.db.updatePartyDetails(
          widget.existing!,
          number: sanitizeFreeName(draft.number),
          name: sanitizeFreeName(draft.name),
          kind: _kind.storageValue,
          phone: draft.phone,
          address: draft.address,
          defaultCurrencyId: _baseCurrencyId,
          creditLimitBaseMinor: draft.creditLimitBaseMinor,
        );
      } else {
        await widget.db.insertParty(
          number: sanitizeFreeName(draft.number),
          name: sanitizeFreeName(draft.name),
          kind: _kind.storageValue,
          phone: draft.phone,
          address: draft.address,
          defaultCurrencyId: _baseCurrencyId,
          creditLimitBaseMinor: draft.creditLimitBaseMinor,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive() async {
    final party = widget.existing;
    if (party == null || _saving) return;
    await widget.db.setPartyActive(party.id, active: !party.isActive);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final party = widget.existing;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'بطاقة طرف' : 'بطاقة طرف جديدة'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _number,
            // س-155/D-153 (دفعة 17): الخانة مفتوحة في التعديل أيضاً بلفظ
            // المالك (س50/1 «تمام») — والمدقق أعلاه يرفض المكرر والمفرغ.
            decoration: InputDecoration(
              labelText: 'رقم الطرف (الأساس)',
              helperText: _isEdit
                  ? 'حروف وأرقام و - _ . فقط (D-174) — والمعاملات مربوطة '
                      'بمعرفه الخفي لا بالرقم'
                  : 'مقترح آلياً — عدّله قبل الحفظ إن شئت (D-063) — '
                      'حروف وأرقام و - _ . فقط (D-174)',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'الاسم *',
              helperText: 'الاسم إلزامي وحده (س-29) — والمطابق حرفياً لطرف قائم مرفوض (D-065)',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'الهاتف (اختياري)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'العنوان (اختياري)'),
          ),
          const SizedBox(height: 16),
          SegmentedButton<PartyKind>(
            segments: [
              for (final kind in PartyKind.values)
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            enabled: false,
            initialValue: 'ليرة سورية (الأساسية)',
            decoration: const InputDecoration(
              labelText: 'العملة الافتراضية',
              helperText: 'معبأة بالافتراضية ولا تُحفظ فارغة (D-066) — '
                  'التغيير يُفتح مع دفعة العملات',
            ),
          ),
          if (_kind != PartyKind.supplier) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _credit,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              onChanged: (_) => setState(() {}), // المعاينة اللحظية (D-102)
              decoration: InputDecoration(
                labelText: 'حد الائتمان (اختياري)',
                helperText: 'اتركه فارغاً ليكون الطرف بلا سقف (س-34) — '
                    'وتنبيه التجاوز يأتي مع دفعة الفواتير (F-164)',
                suffixText: parseGroupedInt(_credit.text) > 0
                    ? 'تعادل ${formatMinorAmount(parseGroupedInt(_credit.text))}'
                    : null,
              ),
            ),
          ],
          if (_isEdit) ...[
            const SizedBox(height: 24),
            // س-33: زر تعطيل/تفعيل — وزر الحذف غير موجود أصلاً في البطاقة
            OutlinedButton.icon(
              onPressed: _saving ? null : _toggleActive,
              icon: Icon(
                party!.isActive ? Icons.block : Icons.check_circle_outline,
              ),
              label: Text(
                party.isActive ? 'تعطيل الطرف' : 'إعادة تفعيل الطرف',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// صياغة رسائل الرفض المعروضة — نطق س-29 حرفاً في رقم مكرر، وD-065 في
/// الاسم المطابق، والبقية بصيغها المعتمدة في السيناريوهات.
String partyErrorText(PartyValidationError error) {
  return switch (error) {
    PartyNameRequired() => 'الاسم إلزامي وحده — أدخل الاسم ثم احفظ (س-29)',
    PartyNumberRequired() => 'الرقم فارغ — لا يُحفظ طرف بلا رقم (D-062)',
    PartyNumberTaken(:final duplicateKey, :final existingLabel) =>
      'الرقم $duplicateKey مستخدم للطرف: $existingLabel',
    PartyNameTaken(:final existingLabel) =>
      'الاسم مطابق حرفياً لطرف قائم: $existingLabel — اختر اسماً آخر (D-065)',
    PartyCurrencyMissing() =>
      'عملة الطرف لا تُحفظ فارغة — أعد اختيار العملة (D-066)',
    PartyCreditLimitInvalid() =>
      'حد الائتمان عدد موجب إن أُدخل — والفراغ يعني بلا سقف (س-34)',
    PartyNameControlChars() =>
      'الاسم يحمل محارف تحكم غير مرئية — أعد كتابته بلا لصق خارجي (D-170)',
    PartyNumberInvalidFormat(:final number) =>
      'الرقم $number يقبل الحروف والأرقام و - _ . حصراً — بلا مسافات ولا '
          'رموز أخرى، والكلمات المختصرة تُفصل بالشرطة (D-174)',
  };
}
