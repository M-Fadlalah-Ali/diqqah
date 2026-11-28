#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س237 — المرحلة ج (D-235): رقعة النطاق والتخزين —
- النطاق: السطر الحر (وصف إلزامي وسعر يدوي موجب) وملاحظة السطر
  القصيرة بحقلها — والمدقق البنيوي يفصل عقود الحر عن عقود الصنف.
- التخزين: الترحيلة v39 (is_free/description/note على invoice_lines)
  وقراءة السطور بها + إنشاء المسودة يكتبها + محرك الترحيل يقبل
  السطر الحر (تخطي الصنف الفارغ — الخطة والمجاميع تسريان طبيعياً)
  وحقلا الإعدادات (invoices.free_line_allowed / invoices.line_notes)
  وتقرير حركة البيع يجمع الحرة تحت «أصناف حرة» (LEFT JOIN)."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INVOICE = os.path.join(ROOT, "packages", "domain", "lib", "src", "invoice.dart")
DB = os.path.join(ROOT, "packages", "storage", "lib", "src", "database.dart")


def sub(s, old, new, where):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    return s.replace(old, new, 1)


def main():
    # ═══ 1) النطاق ═══
    s = io.open(INVOICE, encoding="utf-8").read()
    if "final bool isFree;" in s:
        print("النطاق: مرقع مسبقاً")
    else:
        s = sub(s, """  /// بنية معطلة في م1 — صفر دائماً (05: tax_rate افتراضياً 0).
  final int taxRate;""",
                """  /// بنية معطلة في م1 — صفر دائماً (05: tax_rate افتراضياً 0).
  final int taxRate;

  /// س237 (D-235 — المرحلة ج/السطر الحر): سطر بلا صنف — وصفه إلزامي
  /// وسعره يدوي موجب، ولا حركة مخزون له (المحرك يتخطاه فالخطة
  /// والمجاميع تجريانه بلا مخزون) — وitem_id فيه صفر توكيدياً.
  final bool isFree;

  /// وصف السطر الحر (إلزامي له) — وبطاقة الصنف غير الموجود تعبّئه
  /// بالاسم المكتوب.
  final String? description;

  /// س237 (D-235 — ملاحظات السطور): ملاحظة قصيرة لكل سطر بحقل صغير
  /// قابل للتوسيع — لا أثر لها بالقيد (أثرها المخططي البسيط مع
  /// الترحيل الآمن: بيان سطر خالص).
  final String? note;""",
                "حقول المسودة")
        s = sub(s, """  const InvoiceLineDraft({
    required this.itemId,
    required this.unitId,
    required this.qtyBase,
    this.qty,
    this.unitLevelId,
    this.unitPriceMinor = 0,
    this.discountMinor = 0,
    this.taxRate = 0,
  });""",
                """  const InvoiceLineDraft({
    required this.itemId,
    required this.unitId,
    required this.qtyBase,
    this.qty,
    this.unitLevelId,
    this.unitPriceMinor = 0,
    this.discountMinor = 0,
    this.taxRate = 0,
    this.isFree = false,
    this.description,
    this.note,
  });""",
                "بانية المسودة")
        # المدقق: عقود الحر تفارق عقود الصنف
        s = sub(s, """  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    if (line.qtyBase <= 0) {""",
                """  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    // س237 (D-235): السطر الحر — وصفه إلزامي وسعره اليدوي موجب فلا
    // سطر حر بلا بيان ولا سعر (وسائر فحوص السطر تجرى عليه كما هي).
    if (line.isFree) {
      if (line.description == null || line.description!.trim().isEmpty) {
        errors.add(InvoiceLineDescriptionRequired(i));
      }
      if (line.unitPriceMinor <= 0) {
        errors.add(InvoiceFreeLinePriceRequired(i));
      }
    }
    if (line.qtyBase <= 0) {""",
                "المدقق: عقود الحر")
        # صنفا الخطأ الجديدان — بعد InvoiceLineDiscountInvalid (نجد صنفه)
        anchor = "class InvoiceLineDiscountInvalid extends InvoiceValidationError"
        assert anchor in s
        idx = s.index(anchor)
        # ندرج الصنفين قبل تعليق صنف الخصم (فوقه مباشرة)
        insert_at = s.rindex("\n", 0, idx) + 1
        s = s[:insert_at] + """/// س237: وصف السطر الحر إلزامي (D-235 — المرحلة ج).
class InvoiceLineDescriptionRequired extends InvoiceValidationError {
  final int lineIndex;

  const InvoiceLineDescriptionRequired(this.lineIndex);
}

/// س237: سعر السطر الحر اليدوي موجب إلزاماً (بيان بلا قيمة لا قيد له).
class InvoiceFreeLinePriceRequired extends InvoiceValidationError {
  final int lineIndex;

  const InvoiceFreeLinePriceRequired(this.lineIndex);
}

""" + s[insert_at:]
        # الوصفان بلسان المدقق — قبل «التاريخ» (نضيفهما بأي وصف قائم قريب)
        s = sub(s, """    case InvoiceDateInvalid(:final dateText):
      return 'التاريخ «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)';""",
                """    case InvoiceLineDescriptionRequired(:final lineIndex):
      return 'وصف السطر الحر إلزامي (السطر ${lineIndex + 1})';
    case InvoiceFreeLinePriceRequired(:final lineIndex):
      return 'سعر السطر الحر موجب إلزاماً (السطر ${lineIndex + 1})';
    case InvoiceDateInvalid(:final dateText):
      return 'التاريخ «$dateText» ليس بتاريخ صالح (YYYY-MM-DD)';""",
                "الوصفان")
        io.open(INVOICE, "w", encoding="utf-8").write(s)
        print("النطاق: السطر الحر والملاحظة والمدقق — رُقع")

    # ═══ 2) التخزين ═══
    d = io.open(DB, encoding="utf-8").read()
    if "invoice_lines ADD COLUMN is_free" in d or "'is_free'" in d:
        print("التخزين: مرقع مسبقاً")
        return

    # ٢-أ) المخطط 39 + توثيقه
    d = sub(d, "static const int schemaVersionValue = 38;",
            "static const int schemaVersionValue = 39;", "رقم المخطط")
    d = sub(d, """  /// وجدول bank_reconciliations خالصاً لمستند التسوية البنكية بنمط
  /// cash_adjustments حرفاً (مع رصيدي الكشف والدفتري اللقطة).
  static const int schemaVersionValue = 39;""",
            """  /// وجدول bank_reconciliations خالصاً لمستند التسوية البنكية بنمط
  /// cash_adjustments حرفاً (مع رصيدي الكشف والدفتري اللقطة).
  /// وأحدثتها س237 (المرحلة ج D-235): v39 — ثلاثة أعمدة على
  /// invoice_lines بADD COLUMN بحرس pragma (is_free للسطر الحر
  /// وdescription وصفه وnote ملاحظة السطر القصيرة).
  static const int schemaVersionValue = 39;""",
            "توثيق v39")

    # ٢-ب) كتلة الترحيلة v39 بعد v38
    d = sub(d, """              await _createBankReconciliationTableTx();
            }
          }
        },""",
            """              await _createBankReconciliationTableTx();
            }
            // 38→39 (ومن إصدار أدنى مباشرة): س237 (المرحلة ج D-235):
            // أعمدة السطر الحر والملاحظة على أسطر الفواتير بحرس
            // pragma (آمنة التكرار أي كان مسار الوصول).
            if (version == 39) {
              final lineCols = (await customSelect(
                      "SELECT name FROM pragma_table_info('invoice_lines')")
                    .get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
              if (!lineCols.contains('is_free')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    "is_free INTEGER NOT NULL DEFAULT 0");
              }
              if (!lineCols.contains('description')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    'description TEXT NULL');
              }
              if (!lineCols.contains('note')) {
                await customStatement(
                    'ALTER TABLE invoice_lines ADD COLUMN '
                    'note TEXT NULL');
              }
            }
          }
        },""",
            "كتلة v39")

    # ٢-ج) إنشاء invoice_lines (onCreate) بالأعمدة الثلاثة
    d = sub(d, """    'CREATE TABLE IF NOT EXISTS "invoice_lines" ('""",
            """    // س237 (المرحلة ج): أعمدة السطر الحر وملاحظته.
    'CREATE TABLE IF NOT EXISTS "invoice_lines" ('""", "تعليق الإنشاء")
    # نجد سطر tax_rate بإنشاء السطور ونضيف بعده الثلاثة
    d = sub(d, """        '"tax_rate" INTEGER NOT NULL DEFAULT 0, '""",
            """        '"tax_rate" INTEGER NOT NULL DEFAULT 0, '
        '"is_free" INTEGER NOT NULL DEFAULT 0, '
        '"description" TEXT NULL, '
        '"note" TEXT NULL, '""",
            "أعمدة الإنشاء")

    # ٢-د) إدراج أسطر المسودة يكتب الثلاثة
    d = sub(d, """        'tax_rate, line_total_doc_minor, line_total_base_minor, uuid, '
        'created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          invoiceId,
          r.line.itemId,
          r.line.unitId,""",
            """        'tax_rate, is_free, description, note, '
        'line_total_doc_minor, line_total_base_minor, uuid, '
        'created_at, updated_at, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          invoiceId,
          // س237 (المرحلة ج): السطر الحر بلا صنف — صفر توكيدياً
          // فالمجمعات تسري والخطة تتخطاه.
          r.line.isFree ? 0 : r.line.itemId,
          r.line.isFree ? 0 : r.line.unitId,""",
            "إدراج: الأعمدة والصنف صفر للحر")
    d = sub(d, """          r.line.taxRate,
          r.netDocMinor,""",
            """          r.line.taxRate,
          r.line.isFree ? 1 : 0,
          r.line.isFree ? (r.line.description ?? '') : null,
          r.line.note,
          r.netDocMinor,""",
            "إدراج: قيم الحر والملاحظة")

    io.open(DB, "w", encoding="utf-8").write(d)
    print("التخزين: الترحيلة v39 والإدراج — رُقع")


if __name__ == "__main__":
    main()
