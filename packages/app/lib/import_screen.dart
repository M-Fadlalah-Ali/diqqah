/// شاشة استيراد البيانات (D-208/§25.3 — الدفعة الأولى من ثلاث: النواة —
/// الأطراف والأصناف): بند الإعدادات بمسار «استيراد البيانات» ← اختيار
/// القالب ← تنزيل قالب فارغ أو اختيار ملف CSV ← معاينة أول 20 صفاً
/// وعداداتها (جديد/موجود/أخطاء) ← إن وُجدت أخطاء رفض كلي وتقرير
/// قابل للتنزيل، وإلا زر «اعتماد» ← النسخة الحدثية ثم معاملة واحدة
/// ثم انتهى.
///
/// السلامة المعمى (§25.6): نسخة حدثية تلقائية قبل كل استيراد ولا
/// اعتماد بلا نسخة؛ إيقاف المجدول أثناء التنفيذ ثم استئنافه؛ إشعار
/// صريح عند بدء الاستيراد ونافذة التراجع مفتوحة (الاستيراد كتابة
/// تغلقها — §25.7/26.1)؛ والفاصل المنقوطة المكتشف إشعارٌ دائم
/// بالمعاينة لا رسالة عابرة (د-5). والمركز (BackupCenter) قد يكون
/// غائباً بوضع الاختبار فالمسار يكمل والنسخة الحدثية تُحقن.
library;

import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'adaptive.dart';
import 'app_theme.dart';
import 'backup_center.dart';
import 'device_status.dart';
import 'dq_log.dart';
import 'date_picker.dart';

/// صورة معاينة مجمعة فوق أي خطة — الواجهة لا تفرّع على نوعي الخطة
/// إلا في عرض الصفوف.
class _ImportPreview {
  final ImportTemplateId templateId;
  final String templateLabel;
  final bool semicolonUsed;
  final bool overSoftLimit;
  final int totalRows;
  final List<ImportError> errors;
  final List<ImportDifference> differences;
  final List<String> previewLines;
  final int newCount;
  final int existingCount;
  final int unitCreates;
  final bool approvable;

  /// س141 — القالبان الافتتاحيان: تحذيرات المراجعة (لا تمنع) وإجماليات
  /// الميزان المعروضة (د-6: تجميع سليم لكل عملة ومكافئ بالأساسية).
  final List<String> warnings;
  final int partiesCreates;
  final int itemsCreates;
  final int boxesToOpen;
  final int debitBaseMinor;
  final int creditBaseMinor;
  final int counterpartBaseMinor;
  final int receiptValueBaseMinor;
  final Map<String, int> currencyTotalsDocMinor;

  int get errorCount => errors.length;

  bool get isOpening =>
      templateId == ImportTemplateId.partyBalances ||
      templateId == ImportTemplateId.openingFull ||
      templateId == ImportTemplateId.openingQty;

  const _ImportPreview({
    required this.templateId,
    required this.templateLabel,
    required this.semicolonUsed,
    required this.overSoftLimit,
    required this.totalRows,
    required this.errors,
    required this.differences,
    required this.previewLines,
    required this.newCount,
    required this.existingCount,
    required this.unitCreates,
    required this.approvable,
    this.warnings = const [],
    this.partiesCreates = 0,
    this.itemsCreates = 0,
    this.boxesToOpen = 0,
    this.debitBaseMinor = 0,
    this.creditBaseMinor = 0,
    this.counterpartBaseMinor = 0,
    this.receiptValueBaseMinor = 0,
    this.currencyTotalsDocMinor = const {},
  });
}

class ImportScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// مزود النسخة الحدثية قبل الاعتماد — الافتراضي مركز النسخ القائم
  /// (نمط createYearCloseEventBackup المحروس، §25.6) والاختبار يحقنه.
  /// null في الرجع يعني فشل النسخة فلا اعتماد (DQ-1107).
  final Future<String?> Function()? createEventBackup;

  /// ممر الاختبار المحقون — بديل منتقي الملفات (نمط المزودات المحقونة:
  /// الساعة والبطارية بالمركز). null في الإنتاج فمنتقي النظام هو الطريق
  /// الوحيد (D-057)، وفيه كذا القاعدة: ما يُختبر هو ما يُشغَّل بنفس
  /// المسار بعد المنتقي حرفاً.
  final Future<({String name, List<int> bytes})?> Function()? pickOverride;

  /// ممر الاختبار المحقون — بديل نافذة الحفظ باسم (س207 بند 1 من نقاش
  /// المالك المعتمد: «عند اختيار قالب من قوالب الاستيراد على ويندوز
  /// فإنه لا يتيح المجال لحفه على الحاسب»). يُعيد المسار المكتوب أو
  /// null للإلغاء. null في الإنتاج فنافذة حفظ النظام هي الطريق على
  /// سطح المكتب (نمط pickOverride الموثق أعلاه).
  final Future<String?> Function(String fileName, String csv)? saveOverride;

  const ImportScreen({
    super.key,
    required this.db,
    this.createEventBackup,
    this.pickOverride,
    this.saveOverride,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportTemplateId _templateId = ImportTemplateId.parties;
  ImportExistingPolicy _policy = ImportExistingPolicy.addNew;
  String? _fileName;
  _ImportPreview? _preview;
  bool _busy = false;
  bool _picked = false;

  /// س141 — تاريخ الافتتاحي (د-6): افتراضه بداية أقدم فترة مفتوحة
  /// وتحققه حي (DQ-1026/DQ-1025) بكل تغيير — والمعاينة تبنى عليه.
  final TextEditingController _openingDateController =
      TextEditingController();
  List<PeriodInfo> _periods = const [];
  String? _earliestPostedDate;
  List<ImportError> _openingDateErrors = const [];

  String get _templateLabel =>
      importTemplateOf(_templateId)!.label;

  bool get _isOpeningTemplate =>
      _templateId == ImportTemplateId.partyBalances ||
      _templateId == ImportTemplateId.openingFull ||
      _templateId == ImportTemplateId.openingQty;

  @override
  void initState() {
    super.initState();
    _loadOpeningContext();
  }

  @override
  void dispose() {
    _openingDateController.dispose();
    super.dispose();
  }

  Future<void> _loadOpeningContext() async {
    try {
      final start = await widget.db.earliestOpenPeriodStartText();
      final periods = await widget.db.ledgerPeriods();
      final earliestPosted =
          await widget.db.earliestPostedMoveDateText();
      if (!mounted) return;
      setState(() {
        _periods = periods;
        _earliestPostedDate = earliestPosted;
        if (_openingDateController.text.isEmpty) {
          _openingDateController.text = start ?? todayIsoDate();
        }
      });
      _validateOpeningDate();
    } catch (e) {
      await dqLog(widget.db, e, context: 'import.opening_context');
      // سياق التاريخ مسار تحقق لا يُسقط الشاشة — والافتراضي اليوم.
      if (_openingDateController.text.isEmpty) {
        _openingDateController.text = todayIsoDate();
      }
    }
  }

  void _validateOpeningDate() {
    final errors = validateOpeningDateForImport(OpeningImportDateContext(
      openingDateText: _openingDateController.text,
      periods: _periods,
      earliestPostedDateText: _earliestPostedDate,
    ));
    if (mounted) {
      setState(() => _openingDateErrors = errors);
    }
  }

  Future<void> _onOpeningDateChanged(String text) async {
    _validateOpeningDate();
    if (_lastBytes != null && _isOpeningTemplate) {
      setState(() => _busy = true);
      await _buildPreview(_lastBytes!);
    }
  }

  Future<String?> _defaultEventBackup() async {
    final entry = await BackupCenter.instance?.createYearCloseEventBackup();
    return entry?.fileName;
  }

  // ── القالب الفارغ (§25.4) — ما نصدّره هو ما نستورده (مرآة F-166) ──

  Future<void> _downloadTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = buildEmptyTemplateCsv(_templateId);
      final fileName =
          'diqqah-import-${importTemplateOf(_templateId)!.code}-v1.csv';
      // س207 (بند 1): الحفظ باسم على سطح المكتب بنافذة النظام — كان
      // الطريق الوحيد نافذة المشاركة فلا مجال لحفظ القالب على الحاسب
      // (ملاحظة المالك بنقاشه المعتمد). سطح المكتب نافذة حفظ يختار
      // المستخدم مكاناً واسمه، والهاتف بنافذة المشاركة باقياً (عرف
      // D-056: المنصة تحكم الطريق). الإلغاء لا شيء بعرف _pickFile.
      final String? savedPath;
      if (widget.saveOverride != null) {
        savedPath = await widget.saveOverride!(fileName, csv);
      } else if (Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS) {
        savedPath = await _saveTemplateViaPicker(fileName, csv);
      } else {
        savedPath = null;
      }
      if (savedPath != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('حُفظ القالب: $savedPath')),
        );
        return;
      }
      final dir = await Directory.systemTemp.createTemp('diqqah-template');
      final file = File(
          '${dir.path}${Platform.pathSeparator}'
          '$fileName');
      // بترميز UTF-8 مع BOM — القالب النصي يحمل BOM أولَه بعرف F-166.
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)],
          text: 'قالب استيراد ${_templateLabel} — دِقَّة');
    } catch (e) {
      await dqLog(widget.db, e, context: 'import.template');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إخراج القالب — $e${dqTag(e)}')),
      );
    }
  }

  // ── اختيار الملف والمعاينة (§25.3.1) ──

  /// نافذة الحفظ باسم على سطح المكتب — file_picker saveFile، والمسار
  /// المختار يُكتب محتواه بعد اختياره، والإلغاء null لا شيء (عرف
  /// «إلغاء — لا شيء» الموثق _pickFile). بترميز UTF-8 مع BOM —
  /// القالب النصي يحمل BOM أولَه بعرف F-166.
  Future<String?> _saveTemplateViaPicker(
      String fileName, String csv) async {
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null || path.isEmpty) return null; // إلغاء — لا شيء
    await File(path).writeAsString(csv);
    return path;
  }

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      ({String name, List<int> bytes})? picked;
      if (widget.pickOverride != null) {
        picked = await widget.pickOverride!();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          initialDirectory: defaultImportDirectory(
            userProfile: Platform.environment['USERPROFILE'],
            home: Platform.environment['HOME'],
          ),
          withData: true,
        );
        final f = result?.files.single;
        picked = (f == null || f.bytes == null)
            ? null
            : (name: f.name, bytes: f.bytes!);
      }
      final name = picked?.name;
      final bytes = picked?.bytes;
      if (name == null || bytes == null) return; // إلغاء — لا شيء
      if (!mounted) return;
      setState(() {
        _busy = true;
        _picked = true;
        _preview = null;
        _fileName = name;
        _lastBytes = bytes;
      });
      await _buildPreview(bytes);
    } catch (e) {
      await dqLog(widget.db, e, context: 'import.pick');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر فتح منتقي الملفات — $e${dqTag(e)}')),
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _buildPreview(List<int> bytes) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final preview = switch (_templateId) {
        ImportTemplateId.parties => await _previewParties(bytes),
        ImportTemplateId.items => await _previewItems(bytes),
        ImportTemplateId.partyBalances =>
          await _previewPartyBalances(bytes),
        ImportTemplateId.openingFull => await _previewOpeningFull(bytes),
        ImportTemplateId.openingQty => await _previewOpeningQty(bytes),
      };
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = false;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'import.parse');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تحليل الملف — $e${dqTag(e)}')),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_ImportPreview> _previewParties(List<int> bytes) async {
    final parse = parsePartiesFile(bytes);
    final plan = await widget.db.planPartiesImportFromDb(
      parse,
      policy: _policy,
    );
    return _ImportPreview(
      templateId: ImportTemplateId.parties,
      templateLabel: importTemplateOf(ImportTemplateId.parties)!.label,
      semicolonUsed: parse.semicolonUsed,
      overSoftLimit: parse.overSoftLimit,
      totalRows: parse.totalDataRows,
      errors: plan.errors,
      differences: plan.differences,
      previewLines: [
        for (final r in parse.rows.take(20))
          '${r.code} — ${r.name} — '
              '${PartyKind.fromStorage(r.kindStorage).label} — '
              '${r.currencyCode} — '
              '${r.creditLimitRaw ?? 'بلا سقف'}',
      ],
      newCount: plan.newCount,
      existingCount: plan.existingCount,
      unitCreates: 0,
      approvable: plan.isApprovable,
    );
  }

  Future<_ImportPreview> _previewItems(List<int> bytes) async {
    final parse = parseItemsFile(bytes);
    final plan = await widget.db.planItemsImportFromDb(
      parse,
      policy: _policy,
    );
    return _ImportPreview(
      templateId: ImportTemplateId.items,
      templateLabel: importTemplateOf(ImportTemplateId.items)!.label,
      semicolonUsed: parse.semicolonUsed,
      overSoftLimit: parse.overSoftLimit,
      totalRows: parse.totalDataRows,
      errors: plan.errors,
      differences: plan.differences,
      previewLines: [
        for (final r in parse.rows.take(20))
          '${r.sku} — ${r.name} — ${r.unit} — ${r.priceCurrencyCode} — '
              'شراء ${r.purchasePriceRaw ?? '—'} — '
              'بيع ${r.salePriceRaw ?? '—'}',
      ],
      newCount: plan.newCount,
      existingCount: plan.existingCount,
      unitCreates: plan.unitCreates.length,
      approvable: plan.isApprovable,
    );
  }

  // ── س141: معاينتا القالبين الافتتاحيين (الوحدتان 4 و5) ──

  Future<_ImportPreview> _previewPartyBalances(List<int> bytes) async {
    final parse = parsePartyBalancesFile(bytes);
    final plan = await widget.db.planPartyBalancesImportFromDb(
      parse,
      openingDateText: _openingDateController.text,
    );
    return _ImportPreview(
      templateId: ImportTemplateId.partyBalances,
      templateLabel:
          importTemplateOf(ImportTemplateId.partyBalances)!.label,
      semicolonUsed: parse.semicolonUsed,
      overSoftLimit: parse.overSoftLimit,
      totalRows: parse.totalDataRows,
      errors: plan.errors,
      differences: plan.differences,
      previewLines: [
        for (final r in parse.rows.take(20))
          '${r.code} — ${r.name} — '
              '${r.kindStorage == 'customer' ? 'عميل' : 'مورد'} — '
              '${r.balanceRaw} ${r.currencyCode}'
              '${r.fxRateRaw == null ? '' : ' (سعر ${r.fxRateRaw})'}',
      ],
      newCount: plan.partyCreates.length,
      existingCount:
          plan.lines.where((l) => l.partyId != null).length,
      unitCreates: 0,
      partiesCreates: plan.partyCreates.length,
      warnings: plan.warnings,
      debitBaseMinor: plan.debitBaseMinor,
      creditBaseMinor: plan.creditBaseMinor,
      counterpartBaseMinor: plan.counterpartBaseMinor,
      currencyTotalsDocMinor: plan.totalsByCurrencyDocMinor(),
      approvable: plan.isApprovable,
    );
  }

  Future<_ImportPreview> _previewOpeningFull(List<int> bytes) async {
    final parse = parseOpeningFullFile(bytes);
    final plan = await widget.db.planOpeningFullImportFromDb(
      parse,
      openingDateText: _openingDateController.text,
    );
    return _ImportPreview(
      templateId: ImportTemplateId.openingFull,
      templateLabel:
          importTemplateOf(ImportTemplateId.openingFull)!.label,
      semicolonUsed: parse.semicolonUsed,
      overSoftLimit: parse.overSoftLimit,
      totalRows: parse.totalDataRows,
      errors: plan.errors,
      differences: plan.differences,
      previewLines: [
        for (final r in parse.rows.take(20))
          '${r.section == 'parties' ? 'ذمم' : (r.section == 'inventory' ? 'مخزون' : 'نقد')} — '
              '${r.code} ${r.name.isEmpty ? '' : '— ${r.name}'} — '
              '${r.valueRaw} ${r.currencyCode}'
              '${r.qtyRaw == null ? '' : ' (كمية ${r.qtyRaw})'}'
              '${r.unit == null ? '' : ' ${r.unit}'}',
      ],
      newCount: plan.partyCreates.length + plan.itemCreates.length,
      existingCount: plan.partyLines
              .where((l) => l.partyId != null)
              .length +
          plan.inventoryLines.where((l) => l.itemId != null).length,
      unitCreates: plan.unitCreates.length,
      partiesCreates: plan.partyCreates.length,
      itemsCreates: plan.itemCreates.length,
      boxesToOpen: plan.cashLines.length,
      warnings: plan.warnings,
      debitBaseMinor: plan.partyDebitBaseMinor + plan.cashBaseMinor,
      creditBaseMinor: plan.partyCreditBaseMinor,
      counterpartBaseMinor: plan.counterpartBaseMinor,
      receiptValueBaseMinor: plan.receiptValueBaseMinor,
      currencyTotalsDocMinor: _openingTotalsByCurrency(plan),
      approvable: plan.isApprovable,
    );
  }

  /// تجميع «فحص توازن الدفعة» بعملة المستند — عرضاً لا حكماً (د-6).
  static Map<String, int> _openingTotalsByCurrency(
      OpeningFullImportPlan plan) {
    final totals = <String, int>{};
    for (final l in plan.partyLines) {
      totals[l.currencyCode] = (totals[l.currencyCode] ?? 0) + l.docMinor;
    }
    for (final l in plan.cashLines) {
      totals[l.currencyCode] = (totals[l.currencyCode] ?? 0) + l.docMinor;
    }
    return totals;
  }

  /// س142 — معاينة الوحدة 3 «كميات المخزون الافتتاحية» (§25.2): مرآة
  /// قسم المخزون بالوحدة 5 بقيم الملف الصريحة ومقابل الإذن 43 الافتراضي
  /// (F-209) — لا 332 الافتتاحي.
  Future<_ImportPreview> _previewOpeningQty(List<int> bytes) async {
    final parse = parseOpeningQtyFile(bytes);
    final plan = await widget.db.planOpeningQtyImportFromDb(
      parse,
      openingDateText: _openingDateController.text,
    );
    return _ImportPreview(
      templateId: ImportTemplateId.openingQty,
      templateLabel: importTemplateOf(ImportTemplateId.openingQty)!.label,
      semicolonUsed: parse.semicolonUsed,
      overSoftLimit: parse.overSoftLimit,
      totalRows: parse.totalDataRows,
      errors: plan.errors,
      differences: plan.differences,
      previewLines: [
        for (final r in parse.rows.take(20))
          '${r.code} — ${r.name} — ${r.qtyRaw} ${r.unit} — '
              '${r.valueRaw} ${r.currencyCode}'
              '${r.fxRateRaw == null ? '' : ' (سعر ${r.fxRateRaw})'}',
      ],
      newCount: plan.itemCreates.length,
      existingCount:
          plan.inventoryLines.where((l) => l.itemId != null).length,
      unitCreates: plan.unitCreates.length,
      itemsCreates: plan.itemCreates.length,
      warnings: plan.warnings,
      debitBaseMinor: plan.receiptValueBaseMinor,
      creditBaseMinor: plan.receiptValueBaseMinor,
      receiptValueBaseMinor: plan.receiptValueBaseMinor,
      approvable: plan.isApprovable,
    );
  }

  // ── الاعتماد: النافذة ← النسخة الحدثية ← المعاملة الواحدة ──

  Future<void> _approve() async {
    final preview = _preview;
    if (preview == null || !preview.approvable || _busy) return;
    final messenger = ScaffoldMessenger.of(context);

    // إشعار نافذة التراجع (§25.7): الاستيراد كتابة تغلقها — إشعار
    // صريح عند بدئه والنافذة مفتوحة، لا صمتاً.
    final window = await widget.db.rollbackWindow();
    if (window != null && !window.closed && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('نافذة التراجع مفتوحة'),
          content: const Text(
              'الاستيراد كتابة ستغلق نافذة التراجع عن الاستعادة — '
              'فلا زر تراجع بعده. متابعة الاستيراد؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('تراجع'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('متابعة الاستيراد'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _busy = true);
    BackupCenter.instance?.pause(); // §8-5: الاستيراد الكبير — الدورية تنتظر
    try {
      final backupName =
          await (widget.createEventBackup ?? _defaultEventBackup)();
      if (backupName == null || backupName.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _busy = false);
        messenger.showSnackBar(const SnackBar(
          // الرمز DQ-1107 للسجل والمرجع لا نص المستخدم (س204 — م03).
          content: Text('لا اعتماد بلا نسخة حدثية — '
              'إنشاء النسخة قبل الاستيراد فشل. راجع مجلد النسخ '
              'ثم أعد المحاولة.'),
        ));
        return;
      }

      if (preview.templateId == ImportTemplateId.partyBalances ||
          preview.templateId == ImportTemplateId.openingFull ||
          preview.templateId == ImportTemplateId.openingQty) {
        await _approveOpening(preview, backupName);
      } else if (preview.templateId == ImportTemplateId.parties) {
        final parse =
            parsePartiesFile(_lastBytes!);
        final plan = await widget.db.planPartiesImportFromDb(
          parse,
          policy: _policy,
        );
        final result = await widget.db.executePartiesImport(
          plan,
          eventBackupName: backupName,
        );
        await _showLegacyImportDone(result);
      } else {
        final parse = parseItemsFile(_lastBytes!);
        final plan = await widget.db.planItemsImportFromDb(
          parse,
          policy: _policy,
        );
        final result = await widget.db.executeItemsImport(
          plan,
          eventBackupName: backupName,
        );
        await _showLegacyImportDone(result);
      }
    } on ImportExecutionException catch (e) {
      await dqLog(widget.db, e, context: 'import.approve');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text('فشل تنفيذ الاستيراد ولم يُكتب شيء — '
            '$e\nأعِد المعاينة ثم اعتمد من جديد.${dqTag(e)}'),
      ));
    } catch (e) {
      await dqLog(widget.db, e, context: 'import.approve');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text('تعذر الاستيراد — $e${dqTag(e)}'),
      ));
    } finally {
      BackupCenter.instance?.resume();
    }
  }

  /// اعتماد القالبين الافتتاحيين (س141): الخطة تعاد بالتاريخ الحي ثم
  /// المعاملة الواحدة — ولوحة ميزان المراجعة تُعرض تلقائياً بعد ترحيل
  /// القيد الافتتاحي (§25.6).
  Future<void> _approveOpening(
      _ImportPreview preview, String backupName) async {
    final messenger = ScaffoldMessenger.of(context);
    final ImportOpeningResult result;
    if (preview.templateId == ImportTemplateId.partyBalances) {
      final parse = parsePartyBalancesFile(_lastBytes!);
      final plan = await widget.db.planPartyBalancesImportFromDb(
        parse,
        openingDateText: _openingDateController.text,
      );
      result = await widget.db.executePartyBalancesImport(
        plan,
        eventBackupName: backupName,
      );
    } else if (preview.templateId == ImportTemplateId.openingQty) {
      final parse = parseOpeningQtyFile(_lastBytes!);
      final plan = await widget.db.planOpeningQtyImportFromDb(
        parse,
        openingDateText: _openingDateController.text,
      );
      result = await widget.db.executeOpeningQtyImport(
        plan,
        eventBackupName: backupName,
      );
    } else {
      final parse = parseOpeningFullFile(_lastBytes!);
      final plan = await widget.db.planOpeningFullImportFromDb(
        parse,
        openingDateText: _openingDateController.text,
      );
      result = await widget.db.executeOpeningFullImport(
        plan,
        eventBackupName: backupName,
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _picked = false;
      _preview = null;
      _fileName = null;
    });
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('أُتمّ استيراد الأرصدة الافتتاحية'),
        content: Text(
            '${result.moveNumber == null ? '' : 'قيد رقم ${result.moveNumber} — '}'
            '${result.receiptNumber == null ? '' : 'إذن إدخال رقم ${result.receiptNumber} — '}'
            'أطراف: ${result.partiesCreated} — أصناف: '
            '${result.itemsCreated} — وحدات: ${result.unitsCreated} — '
            'صناديق: ${result.boxesCreated}\n'
            'وسُجّل حدث الاستيراد والنسخة الحدثية باسمه.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ميزان المراجعة'),
          ),
        ],
      ),
    );
    // §25.6: ميزان المراجعة يُعرض تلقائياً بعد ترحيل القيد الافتتاحي.
    try {
      final tb = await widget.db.trialBalanceReport();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('ميزان المراجعة بعد الافتتاحي'),
          content: Text(
              'مجموع المدين: ${formatMinorHuman(tb.totalDebitMinor, 2)}\n'
              'مجموع الدائن: ${formatMinorHuman(tb.totalCreditMinor, 2)}\n'
              '${tb.isBalanced ? 'الميزان متوازن — بالمحرك وبهذا العرض معاً.' : 'الميزان غير متوازن — راجع الدفتر فوراً.'}'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      await dqLog(widget.db, e, context: 'import.trial_balance');
      messenger.showSnackBar(
          SnackBar(
              content: Text('تعذر عرض ميزان المراجعة — $e${dqTag(e)}')));
    }
  }

  Future<void> _showLegacyImportDone(ImportExecutionResult result) async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _picked = false;
      _preview = null;
      _fileName = null;
    });
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('أُتمّ الاستيراد'),
        content: Text(
            'جديد: ${result.created} — محْدَث: ${result.updated} — '
            'متخطى: ${result.skipped}\n'
            'وسُجّل حدث الاستيراد والنسخة الحدثية باسمه.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  List<int>? _lastBytes;

  // ── تقارير التنزيل — بنية تقرير F-166 ذاتها ──

  Future<void> _exportCsv(String fileName, String csv, String subject) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await Directory.systemTemp.createTemp('diqqah-report');
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: subject);
    } catch (e) {
      await dqLog(widget.db, e, context: 'import.export');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إخراج التقرير — $e${dqTag(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد البيانات')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16,
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16),
        children: [
          const Text(
            'استيراد بيانات الانتقال على القوالب المعتمدة — '
            'CSV بترميز UTF-8، وكل-أو-لا شيء، وقبله نسخة حدثية تلقائية.',
          ),
          // س142 (§25.10 — التشطيب): ما لا يُستورد يُقال صراحة بالواجهة
          // لا يُترك اكتشافاً — والمؤجلات بأسمائها لا صمتاً.
          const SizedBox(height: 8),
          Card(
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ما لا يُستورد بهذا المسار (صراحة كاملة)'),
                  SizedBox(height: 4),
                  Text('• دليل الحسابات: إعداد ثابت يدوياً من شاشة الدفتر '
                      'لا كوداً.'),
                  Text('• تاريخ الحركات الكامل: هذا استيراد أرصدة لا ترحيل '
                      'تاريخي — الأرصدة أول المدة حصراً.'),
                  Text('• المؤجل بقراره: ربط الأعمدة اليدوي وصيغة xlsx '
                      'والمعالجات الخاصة.'),
                ],
              ),
            ),
          ),
          // س142 (§25.4): اصطلاح الإشارات موثق حيث يُدخل — سالب رصيد
          // العميل دائن وسالب المورد مدين، مشروع بتحذير مراجعة لا رفض.
          if (_isOpeningTemplate) ...[
            const SizedBox(height: 8),
            Card(
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('اصطلاح الإشارات: سالب رصيد العميل رصيد دائن '
                    'وسالب رصيد المورد مدين — مشروع بتحذير مراجعة '
                    'بالعاينة لا رفض، والصفر لا يُستورد.'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SegmentedButton<ImportTemplateId>(
            segments: const [
              ButtonSegment(
                value: ImportTemplateId.parties,
                label: Text('الأطراف'),
                icon: Icon(Icons.people),
              ),
              ButtonSegment(
                value: ImportTemplateId.items,
                label: Text('الأصناف'),
                icon: Icon(Icons.inventory_2),
              ),
              ButtonSegment(
                value: ImportTemplateId.partyBalances,
                label: Text('أرصدة الذمم'),
                icon: Icon(Icons.account_balance_wallet),
              ),
              ButtonSegment(
                value: ImportTemplateId.openingFull,
                label: Text('الافتتاحي الكامل'),
                icon: Icon(Icons.balance),
              ),
              ButtonSegment(
                value: ImportTemplateId.openingQty,
                label: Text('كميات المخزون'),
                icon: Icon(Icons.warehouse),
              ),
            ],
            selected: {_templateId},
            onSelectionChanged: _busy || _picked
                ? null
                : (selection) =>
                    setState(() => _templateId = selection.first),
          ),
          // س141 — تاريخ الافتتاحي (د-6): افتراضه بداية أقدم فترة
          // مفتوحة، وتحققه حي بكل تغيير (DQ-1026/DQ-1025) والمعاينة
          // تبنى عليه — لا اعتماد بتاريخ مرفوض.
          if (_isOpeningTemplate) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _openingDateController,
              decoration: InputDecoration(
                labelText: 'تاريخ القيد الافتتاحي (YYYY-MM-DD)',
                suffixIcon: calendarPickerSuffix(
                    context, _openingDateController),
                helperText: 'افتراضه بداية أقدم فترة مفتوحة — والافتتاحي '
                    'أول مستند مرحّل فأسبق من كل مرحّل.',
                errorText: _openingDateErrors.isEmpty
                    ? null
                    : '(${_openingDateErrors.first.dqCode}) '
                        '${_openingDateErrors.first.description}',
              ),
              onChanged: _onOpeningDateChanged,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _downloadTemplate,
                  icon: const Icon(Icons.download),
                  label: const Text('تنزيل قالب فارغ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('اختيار ملف CSV'),
                ),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (preview != null) ...[
            const SizedBox(height: 16),
            // إشعار الفاصل المنقوطة — دائم بالمعاينة لا عابر (د-5).
            if (preview.semicolonUsed)
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('اكتُشف فاصل منقوطة، قُرئ به — '
                      'وسيُسجل بحدث الاستيراد.'),
                ),
              ),
            if (preview.overSoftLimit)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('الملف كبير — قد يستغرق الاستيراد وقتاً '
                      'فلا تغلق الشاشة حتى ينتهي.'),
                ),
              ),
            const SizedBox(height: 8),
            Text('الملف: ${_fileName ?? ''} — '
                '${preview.totalRows} صف'),
            const SizedBox(height: 8),
            Row(
              children: [
                _counterChip('جديد', preview.newCount,
                    diqqahLanesOf(context).positive.fg),
                const SizedBox(width: 8),
                _counterChip('موجود', preview.existingCount,
                    diqqahLanesOf(context).attention.fg),
                const SizedBox(width: 8),
                _counterChip('أخطاء', preview.errorCount,
                    diqqahLanesOf(context).negative.fg),
                if (preview.unitCreates > 0) ...[
                  const SizedBox(width: 8),
                  _counterChip('وحدات تُنشأ', preview.unitCreates,
                      diqqahLanesOf(context).positiveOutline.fg),
                ],
                if (preview.boxesToOpen > 0) ...[
                  const SizedBox(width: 8),
                  _counterChip('صناديق تُفتح', preview.boxesToOpen,
                      diqqahLanesOf(context).attentionOutline.fg),
                ],
              ],
            ),
            // س141 — تحذيرات المراجعة (لا تمنع): الأرصدة المعكوسة وانحراف
            // السعر عن آخر مسجل (§25.4).
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: diqqahLanesOf(context).attention.bg,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تحذيرات مراجعة (لا تمنع الاعتماد)'),
                      const SizedBox(height: 4),
                      for (final w in preview.warnings.take(6)) Text('• $w'),
                      if (preview.warnings.length > 6)
                        Text('… و${preview.warnings.length - 6} تحذيراً آخر'),
                    ],
                  ),
                ),
              ),
            ],
            // س141 — «فحص توازن الدفعة» عرضاً (د-6): تجميع سليم لكل عملة
            // ومكافئ بالأساسية بالمقابل 332 الآلي.
            if (preview.isOpening) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('توازن الافتتاحي (بالأساسية)'),
                      const SizedBox(height: 4),
                      Text('مدين: ${formatMinorHuman(
                          preview.debitBaseMinor, 2)}'),
                      Text('دائن: ${formatMinorHuman(
                          preview.creditBaseMinor, 2)}'),
                      if (preview.templateId ==
                          ImportTemplateId.openingQty)
                        Text('مقابل الإذن: 43 «إيرادات أخرى» — '
                            'الافتراضي القابل للتغيير من المفعّل'),
                      if (preview.templateId !=
                          ImportTemplateId.openingQty)
                        Text('مقابل 332: ${formatMinorHuman(
                            preview.counterpartBaseMinor.abs(), 2)} '
                            '${preview.counterpartBaseMinor >= 0 ? 'دائناً' : 'مديناً'}'),
                      if (preview.receiptValueBaseMinor > 0)
                        Text('إذن الإدخال بقيمه: ${formatMinorHuman(
                            preview.receiptValueBaseMinor, 2)}'),
                      if (preview.currencyTotalsDocMinor.isNotEmpty)
                        const SizedBox(height: 4),
                      for (final e
                          in preview.currencyTotalsDocMinor.entries)
                        Text('${e.key}: ${formatMinorHuman(e.value, 2)} '
                            '(بعملة المستند)'),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (preview.errors.isNotEmpty) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الأخطاء (${preview.errors.length}) — '
                          'الرفض كلي: لا اعتماد بأي خطأ'),
                      const SizedBox(height: 8),
                      for (final e in preview.errors.take(10))
                        Text('• صف ${e.row == 0 ? '—' : e.row}'
                            '${e.column == null ? '' : ' عمود ${e.column}'}'
                            '${e.value == null || e.value!.isEmpty ? '' : ' «${e.value}»'}'
                            ' (${e.dqCode}): ${e.description}'),
                      if (preview.errors.length > 10)
                        Text('… و${preview.errors.length - 10} خطأ '
                            'أخرى بالتقرير'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _exportCsv(
                  'diqqah-import-errors.csv',
                  buildImportErrorReportCsv(preview.errors),
                  'تقرير أخطاء الاستيراد',
                ),
                icon: const Icon(Icons.report),
                label: const Text('تنزيل تقرير الأخطاء (CSV)'),
              ),
            ] else if (preview.isOpening) ...[
              if (preview.differences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _exportCsv(
                      'diqqah-import-diff.csv',
                      buildImportDiffReportCsv(preview.differences),
                      'تقرير فروق الافتتاحي',
                    ),
                    icon: const Icon(Icons.difference),
                    label: Text('تنزيل تقرير الفروق '
                        '(${preview.differences.length}) — CSV'),
                  ),
                ),
              Text('معاينة أول '
                  '${preview.previewLines.length} صف:'),
              const SizedBox(height: 4),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in preview.previewLines)
                        Text(line, textAlign: TextAlign.right),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || _openingDateErrors.isNotEmpty
                    ? null
                    : _approve,
                icon: const Icon(Icons.check_circle),
                label: const Text('اعتماد الأرصدة الافتتاحية '
                    '(نسخة حدثية ثم معاملة واحدة ثم ميزان المراجعة)'),
              ),
            ] else ...[
              // سياسة الموجود (§25.3.2) — قبل المعاينة تغيّر الفروق.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('سياسة الموجود'),
                      // RadioGroup الواجهة الحالية (3.32+) — بلا خصائص
                      // مهجورة (نمط stock_counts_screen القائم).
                      RadioGroup<ImportExistingPolicy>(
                        groupValue: _policy,
                        onChanged: (value) => _replan(value),
                        child: const Column(
                          children: [
                            RadioListTile<ImportExistingPolicy>(
                              title: Text('إضافة جديد — الموجود يُتخطى '
                                  'والجديد يُنشأ (الافتراضي)'),
                              value: ImportExistingPolicy.addNew,
                            ),
                            RadioListTile<ImportExistingPolicy>(
                              title: Text('تحديث الموجود — وصفيفات فقطفي النسخة الأولى: الاسم والسعر'),
                              value: ImportExistingPolicy.updateExisting,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (preview.differences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _exportCsv(
                      'diqqah-import-diff.csv',
                      buildImportDiffReportCsv(preview.differences),
                      'تقرير فروق التحديث',
                    ),
                    icon: const Icon(Icons.difference),
                    label: Text('تنزيل تقرير الفروق '
                        '(${preview.differences.length}) — CSV'),
                  ),
                ),
              Text('معاينة أول '
                  '${preview.previewLines.length} صف:'),
              const SizedBox(height: 4),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in preview.previewLines)
                        Text(line, textAlign: TextAlign.right),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: const Icon(Icons.check_circle),
                label: const Text('اعتماد الاستيراد '
                    '(نسخة حدثية ثم معاملة واحدة)'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _counterChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text('$label: $count'),
    );
  }

  /// تغيير السياسة يعيد التخطيط من البايتات نفسها — العدادات والفروق
  /// تعكس السياسة الجديدة لحظياً (§25.3.2).
  Future<void> _replan(ImportExistingPolicy? policy) async {
    if (policy == null || _lastBytes == null) return;
    setState(() {
      _policy = policy;
      _busy = true;
    });
    await _buildPreview(_lastBytes!);
  }
}
