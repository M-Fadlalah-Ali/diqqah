import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// شاشة مجموعات التعبئة — F-032/F-033 (الدفعة 27، D-026).
///
/// - قوالب مقترحة غير حصرية (D-026): الإنشاء يفتح بصفوف «علبة ×12»
///   و«كرتونة ×144» قابلة للتعديل والإزالة قبل الحفظ — والمستخدم
///   يعرّف وحداته ومستوياته الأعلى كما يشاء.
/// - المرجع إضافة وتسمية حصراً: لا حذف ولا تعطيل فالصنف قد يحيل
///   (نمط المراجع 03 §6-3).
/// - العامل يتجمد بعد الحركات (F-033): خانة العامل تُعطّل في شاشة
///   التعديل بفحص التجمد، وفحص التخزين حرس ثانوي — والمسار الوحيد
///   وحدة جديدة.
class UnitGroupsScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const UnitGroupsScreen({super.key, required this.db});

  @override
  State<UnitGroupsScreen> createState() => _UnitGroupsScreenState();
}

class _UnitGroupsScreenState extends State<UnitGroupsScreen> {
  List<UnitGroup> _groups = const [];
  Map<int, List<UnitGroupLevel>> _levelsByGroup = const {};

  /// تجمد العوامل لكل مجموعة — يُفحص عند التحميل ليعطَّل خانة العامل
  /// سلفاً بدل رفض بعد الكتابة (F-033).
  Set<int> _frozenGroupIds = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final groups = await widget.db.allUnitGroups();
    final levels = await widget.db.allUnitGroupLevels();
    final frozen = <int>{};
    for (final g in groups) {
      if (await widget.db.unitGroupHasMovements(g.id)) frozen.add(g.id);
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _levelsByGroup = levels;
      _frozenGroupIds = frozen;
      _loaded = true;
    });
  }

  Future<void> _openEditor(UnitGroup? existing) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _UnitGroupEditScreen(db: widget.db, existing: existing),
      ),
    );
    if (saved == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مجموعات التعبئة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مجموعة'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(
                  child: Text(
                      'لا مجموعات بعد — أضف مجموعة تعبئة (F-032/D-026)'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final group in _groups)
                      ListTile(
                        leading: const Icon(Icons.layers_outlined),
                        title: Text(group.name),
                        subtitle: Text(
                          _levelsSummary(group.id) +
                              (_frozenGroupIds.contains(group.id)
                                  ? ' · العوامل مجمدة بعد الحركات (F-033)'
                                  : ''),
                        ),
                        onTap: () => _openEditor(group),
                      ),
                  ],
                ),
    );
  }

  String _levelsSummary(int groupId) {
    final levels = _levelsByGroup[groupId] ?? const <UnitGroupLevel>[];
    if (levels.isEmpty) return 'بلا مستويات';
    return levels.map((l) => '${l.name} ×${l.factor}').join(' · ');
  }
}

/// شاشة إنشاء/تعديل مجموعة — الاسم والمستويات بأسمائها وعواملها،
/// والتحقق بمحرك المجال (validateUnitGroupSpec) والكتابة بمسار
/// التخزين الواحد.
class _UnitGroupEditScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final UnitGroup? existing;

  const _UnitGroupEditScreen({required this.db, this.existing});

  @override
  State<_UnitGroupEditScreen> createState() => _UnitGroupEditScreenState();
}

class _LevelRow {
  /// معرّف المستوى القائم — null لصف جديد (وضع الإضافة أو القالب).
  final int? levelId;
  final TextEditingController name;
  final TextEditingController factor;

  _LevelRow({this.levelId, String name = '', String factor = ''})
      : name = TextEditingController(text: name),
        factor = TextEditingController(text: factor);

  void dispose() {
    name.dispose();
    factor.dispose();
  }

  bool get isEmpty => name.text.trim().isEmpty && factor.text.trim().isEmpty;
}

class _UnitGroupEditScreenState extends State<_UnitGroupEditScreen> {
  late final TextEditingController _name;
  List<_LevelRow> _rows = [];
  bool _saving = false;

  /// F-033: تجمد العوامل في وضع التعديل — تُفحص مرة عند الفتح فتُعطَّل
  /// الخانة سلفاً (والتخزين حرس ثانوي للمسار المباشر).
  bool _frozen = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    if (_isEdit) {
      _loadExisting();
    } else {
      // قوالب مقترحة غير حصرية (D-026) — قابلة للتعديل والإزالة قبل الحفظ.
      _rows = [
        _LevelRow(name: 'علبة', factor: '12'),
        _LevelRow(name: 'كرتونة', factor: '144'),
      ];
    }
  }

  Future<void> _loadExisting() async {
    final levels = await widget.db.levelsOfGroup(widget.existing!.id);
    final frozen = await widget.db.unitGroupHasMovements(widget.existing!.id);
    if (!mounted) return;
    setState(() {
      _rows = [
        for (final l in levels)
          _LevelRow(levelId: l.id, name: l.name, factor: '${l.factor}'),
      ];
      _frozen = frozen;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// تجميع المواصفة من الصفوف — الصف الفارغ تماماً يتجاهل (القالب
  /// يُزال بتفريغه)، وصف منصف يُرفض برسالة موضعية.
  (UnitGroupSpec?, String?) _collectSpec() {
    final specs = <UnitGroupLevelSpec>[];
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (row.isEmpty) continue;
      final factor = parseUnitGroupFactor(row.factor.text);
      if (factor == null) {
        return (
          null,
          'عامل المستوى ${i + 1} عدد صحيح ≥2 — «${row.factor.text.trim()}» '
              'غير مقبول'
        );
      }
      specs.add(UnitGroupLevelSpec(name: row.name.text, factor: factor));
    }
    return (
      UnitGroupSpec(name: _name.text, levels: specs),
      null,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final groups = await widget.db.allUnitGroups();
      final existingNames = {
        for (final g in groups)
          if (!_isEdit || g.id != widget.existing!.id) g.name.trim(),
      };
      final (spec, rowError) = _collectSpec();
      if (rowError != null) {
        if (!mounted) return;
        _showError(rowError);
        return;
      }
      final errors = validateUnitGroupSpec(
        spec!,
        existingGroupNames: existingNames,
      );
      if (errors.isNotEmpty) {
        if (!mounted) return;
        _showError(unitGroupErrorText(errors.first));
        return;
      }
      if (_isEdit) {
        if (_name.text.trim() != widget.existing!.name) {
          await widget.db
              .renameUnitGroup(widget.existing!.id, name: _name.text);
        }
        for (var i = 0; i < _rows.length; i++) {
          final row = _rows[i];
          if (row.isEmpty) continue;
          final factor = parseUnitGroupFactor(row.factor.text)!;
          if (row.levelId != null) {
            await widget.db.updateUnitGroupLevel(
              row.levelId!,
              name: row.name.text,
              // F-033: المجمد لا يُرسل له عامل أصلاً — والخانة معطلة.
              factor: _frozen ? null : factor,
            );
          } else {
            await widget.db.insertUnitGroupLevel(
                groupId: widget.existing!.id,
                name: row.name.text,
                factor: factor);
          }
        }
      } else {
        await widget.db.insertUnitGroup(
          name: _name.text,
          levels: [
            for (final l in spec.levels) (name: l.name, factor: l.factor),
          ],
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on UnitGroupFactorFrozenException catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message), duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'بطاقة مجموعة تعبئة' : 'مجموعة تعبئة جديدة'),
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
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'اسم المجموعة *',
              helperText: 'مثال: تعبئة عامة — والمطابق حرفياً لمجموعة '
                  'قائمة مرفوض (D-074)',
            ),
          ),
          const SizedBox(height: 16),
          Text('المستويات أعلى الوحدة الأساسية',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'القوالب مقترحة غير حصرية (D-026): عدّل أو أضف ما تشاء — '
            'والعامل عدد صحيح ≥2 نحو الوحدة الأساسية (قطعة = 1 بذاتها)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_frozen)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'العوامل مجمدة بعد وجود حركات على أصناف المجموعة '
                    '(F-033) — والمسار الوحيد إضافة وحدة جديدة'),
              ),
            ),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _rows[i].name,
                      decoration: InputDecoration(
                        labelText: 'اسم المستوى ${i + 1}',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _rows[i].factor,
                      enabled: !_frozen,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'العامل',
                        helperText: '≥2',
                        isDense: true,
                      ),
                    ),
                  ),
                  // الإزالة قبل الحفظ حصراً (القالب) — القائم لا يُحذف
                  // (نمط المراجع: لا حذف).
                  if (!_isEdit)
                    IconButton(
                      tooltip: 'إزالة الصف',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() {
                        _rows[i].dispose();
                        _rows.removeAt(i);
                      }),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _rows.add(_LevelRow())),
            icon: const Icon(Icons.add),
            label: const Text('إضافة مستوى (F-033)'),
          ),
        ],
      ),
    );
  }
}

/// صياغة رسائل رفض مجموعة التعبئة المعروضة — أنواع المجال المحمولة
/// بصيغها العربية (نمط itemErrorText).
String unitGroupErrorText(UnitGroupValidationError error) {
  return switch (error) {
    UnitGroupNameRequired() => 'اسم المجموعة إلزامي (F-032)',
    UnitGroupNameTaken(:final existingName) =>
      'الاسم مطابق حرفياً لمجموعة قائمة: $existingName — اختر اسماً آخر '
          '(D-074)',
    UnitGroupLevelsMissing() =>
      'المجموعة بلا مستويات — أضف مستوى تعبئة واحداً على الأقل (F-032)',
    UnitGroupLevelNameRequired(:final index) =>
      'اسم المستوى ${index + 1} إلزامي',
    UnitGroupLevelNameDuplicate(:final name) =>
      'الاسم «$name» مكرر داخل المجموعة (D-074)',
    UnitGroupFactorInvalid(:final raw, :final index) =>
      'عامل المستوى ${index + 1} عدد صحيح ≥2 — «$raw» غير مقبول',
    UnitGroupFactorDuplicate(:final factor) =>
      'العامل $factor مكرر — وحدتان بحجم واحد داخل المجموعة مرفوض',
  };
}
