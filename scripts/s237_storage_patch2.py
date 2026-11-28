#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س237 — رقعة التخزين الثانية: قراءة السطر الحر وملاحظته (المستند
والمسودة) وقبول المحرك له (تخطي فحص الصنف) وحقلا الإعدادات وتجميع
«أصناف حرة» بتقرير حركة البيع."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "packages", "storage", "lib", "src", "database.dart")


def sub(s, old, new, where):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    return s.replace(old, new, 1)


def main():
    d = io.open(DB, encoding="utf-8").read()
    if "final bool isFree;" in d:
        print("رقعة ٢: مرقعة مسبقاً")
        return

    # ١) نموذج سطر المستند: الحرة الثلاثة
    d = sub(d, """  final int lineTotalDocMinor;
  final int lineTotalBaseMinor;
  final String uuid;""",
            """  final int lineTotalDocMinor;
  final int lineTotalBaseMinor;
  final String uuid;

  /// س237 (المرحلة ج — D-235): السطر الحر — بلا صنف فوصفه بيانه،
  /// وملاحظته القصيرة بيان سطر خالص.
  final bool isFree;
  final String? description;
  final String? note;""",
            "حقول المستند")
    d = sub(d, """    this.deliveryNote;

  const InvoiceLineDocument({""",
            """    this.deliveryNote,
    this.isFree = false,
    this.description,
    this.note,
  };

  const InvoiceLineDocument._hidden({""",
            "بانية المستند") if False else d
    # البانية: نجد سطر المعامل الأخير في البانية (deliveryNote: this.deliveryNote؟)
    d = sub(d, """    this.deliveryNote,
  });""",
            """    this.deliveryNote,
    this.isFree = false,
    this.description,
    this.note,
  });""",
            "بانية المستند")

    # ٢) القراءة: الأعمدة والتعيين
    d = sub(d, """    'line_total_doc_minor, line_total_base_minor, uuid, delivered, '
    'supplier_party_id, delivery_note '
    'FROM invoice_lines WHERE invoice_id = ? ORDER BY id',""",
            """    'line_total_doc_minor, line_total_base_minor, uuid, delivered, '
    'supplier_party_id, delivery_note, '
    'is_free, description, note '
    'FROM invoice_lines WHERE invoice_id = ? ORDER BY id',""",
            "استعلام القراءة")
    d = sub(d, """        // س-153/D-151 (دفعة 15): خانة «ملاحظة التسليم» مع السطر.
        deliveryNote: r.data['delivery_note'] as String?,
      ),""",
            """        // س-153/D-151 (دفعة 15): خانة «ملاحظة التسليم» مع السطر.
        deliveryNote: r.data['delivery_note'] as String?,
        // س237 (المرحلة ج): الحرة الثلاثة مع السطر.
        isFree: (r.data['is_free'] as int? ?? 0) == 1,
        description: r.data['description'] as String?,
        note: r.data['note'] as String?,
      ),""",
            "تعيين القراءة")

    # ٣) المسودة من الصفوف: الحرة تعود للمسودة (وإلا ضاع الحر بالترحيل)
    d = sub(d, """          unitPriceMinor: l.unitPriceMinor,
          discountMinor: l.discountMinor,
          taxRate: l.taxRate,
        ),
    ],
  );
}""",
            """          unitPriceMinor: l.unitPriceMinor,
          discountMinor: l.discountMinor,
          taxRate: l.taxRate,
          // س237: الحرة الثلاثة تعود مع المسودة — فالترحيل يعيد
          // بناءها من الصفوف لا من الذاكرة.
          isFree: l.isFree,
          description: l.description,
          note: l.note,
        ),
    ],
  );
}""",
            "المسودة من الصفوف")

    # ٤) المحرك يقبل الحر: تخطي فحص الصنف
    d = sub(d, """    if (item == null) {
      errors.add(InvoiceItemNotFound(i, line.itemId));
      continue;
    }""",
            """    // س237 (المرحلة ج): السطر الحر بلا صنف أصلاً — فحص الصنف
    // يخطاه وعقده البنيوية فُحصت بالمدقق (وصف وسعر يدوي موجب)،
    // والخطة والمجاميع تجريانه بلا مخزون.
    if (item == null) {
      if (!line.isFree) {
        errors.add(InvoiceItemNotFound(i, line.itemId));
      }
      continue;
    }""",
            "المحرك يقبل الحر")

    # ٥) حقا الإعدادات — بعد زوج حجز مسودات البيع
    d = sub(d, """  static const String draftOverStockMetaKey = 'invoices.draft_over_stock';""",
            """  static const String draftOverStockMetaKey = 'invoices.draft_over_stock';

  /// س237 (المرحلة ج — D-235): خانتا سياسات البيع — السطر الحر
  /// وملاحظات السطور (نافذتاها بالإعدادات وتقرؤهما شاشة التحرير).
  static const String freeLineAllowedMetaKey = 'invoices.free_line_allowed';
  static const String lineNotesMetaKey = 'invoices.line_notes';""",
            "مفتاحا الإعدادات")
    d = sub(d, """  /// ضبط الخيار — قيمته '1'/'0' حرفاً كأخوته في app_meta.
  Future<void> setHeldInvoicesReserveQty(bool enabled) async {""",
            """  /// س237: هل السطر الحر نافذ؟ (يقرأه محرر الفاتورة وبوابة
  /// «إدراج صنف حر» بنافذة الصنف غير الموجود).
  Future<bool> invoiceFreeLineAllowed() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(freeLineAllowedMetaKey)))
        .getSingleOrNull();
    return row?.value.trim() == '1';
  }

  /// س237: ضبط السطر الحر — '1'/'0' حرفاً كأخوته.
  Future<void> setInvoiceFreeLineAllowed(bool enabled) async {
    await _setAppMetaFlag(freeLineAllowedMetaKey, enabled);
  }

  /// س237: هل ملاحظات السطور نافذة؟ (حقلها الصغير قابل للتوسيع).
  Future<bool> invoiceLineNotesEnabled() async {
    final row = await (select(appMeta)
          ..where((t) => t.key.equals(lineNotesMetaKey)))
        .getSingleOrNull();
    return row?.value.trim() == '1';
  }

  /// س237: ضبط ملاحظات السطور — '1'/'0' حرفاً.
  Future<void> setInvoiceLineNotesEnabled(bool enabled) async {
    await _setAppMetaFlag(lineNotesMetaKey, enabled);
  }

  /// س237: ضبط علم app_meta موحداً (أخو الحروف حرفاً: '1'/'0').
  Future<void> _setAppMetaFlag(String key, bool enabled) async {
    final value = enabled ? '1' : '0';
    final existing = await (select(appMeta)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing == null) {
      await into(appMeta).insert(AppMetaCompanion.insert(
          key: key, value: value, createdAt: Value(now), updatedAt: Value(now)));
    } else {
      await (update(appMeta)..where((t) => t.key.equals(key))).write(
          AppMetaCompanion(value: Value(value), updatedAt: Value(now)));
    }
  }

  /// ضبط الخيار — قيمته '1'/'0' حرفاً كأخوته في app_meta.
  Future<void> setHeldInvoicesReserveQty(bool enabled) async {""",
            "مصرّحا الإعدادات")

    # ٦) تقرير حركة البيع: الحرة مجمّعة تحت «أصناف حرة»
    d = sub(d, """    'SELECT il.item_id AS item_id, i.sku AS sku, i.name AS name, '""",
            """    // س237 (المرحلة ج — D-235): أسطر الحرة تجمع تحت «أصناف حرة»
    // كي تتطابق المجاميع (LEFT JOIN فلا يسقط سطر حر بالربط).
    'SELECT il.item_id AS item_id, '
    "COALESCE(i.sku, '') AS sku, "
    "COALESCE(i.name, 'أصناف حرة') AS name, \"""",
            "استعلام الحركة") if False else d
    d = sub(d, """    'SELECT il.item_id AS item_id, i.sku AS sku, i.name AS name, '""",
            """    // س237 (المرحلة ج — D-235): أسطر الحرة تجمع تحت «أصناف حرة»
    // كي تتطابق المجاميع (LEFT JOIN فلا يسقط سطر حر بالربط).
    'SELECT il.item_id AS item_id, '
    "COALESCE(i.sku, 'حر') AS sku, "
    "COALESCE(i.name, 'أصناف حرة') AS name, '""",
            "استعلام الحركة")
    d = sub(d, """    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'JOIN items i ON i.id = il.item_id '""",
            """    'FROM invoice_lines il '
    'JOIN invoices inv ON inv.id = il.invoice_id '
    'LEFT JOIN items i ON i.id = il.item_id '""",
            "ربط الحركة")

    io.open(DB, "w", encoding="utf-8").write(d)
    print("رقعة ٢: القراءة والمحرك والإعدادات والتقرير — رُقع كلها")


if __name__ == "__main__":
    main()
