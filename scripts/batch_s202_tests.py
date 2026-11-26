#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س202 — إعادة كتابة batch18_test على نمط بلاطتا الجهة وورقة الإدخال
بمراسٍ دقيقة مع تحقق صارم: كل عملية تحتسب مرة واحدة وإلا فشل السكربت."""

import sys

PATH = "/home/z/my-project/diqqah/packages/app/test/batch18_test.dart"

with open(PATH, encoding="utf-8") as f:
    text = f.read()

def replace_once(text, start_marker, end_marker, replacement, label):
    """يستبدل المقطع من بداية start_marker إلى نهاية end_marker (شاملاً)
    بمقطع replacement — ويجب أن يعثر على كل مرسٍ مرة واحدة حصراً."""
    i = text.find(start_marker)
    if i < 0 or text.find(start_marker, i + 1) >= 0:
        print(f"فشل: مرسٍ البداية «{label}» غائب أو مكرر")
        sys.exit(1)
    j = text.find(end_marker, i)
    if j < 0:
        print(f"فشل: مرسٍ النهاية «{label}» غائب")
        sys.exit(1)
    j += len(end_marker)
    return text[:i] + replacement + text[j:]

# ── 1: التعليق التوثيقي للملف ──
doc_new = """/// اختبارات دفعة (18) معلَّلة بس202 — عزل إدخال الفواتير بالضغط الصريح
/// (س-163/D-161 على معاينة س-162/D-160 المعتمدة بلفظ المالك
/// «اعتمد الدفعات الأربعة وقم بتنفيذ اقتراحك للفواتير» — س52) بعد
/// سحب البطاقة بكلمته س202 («التراجع عنه إلى أيقونتين كالبقية»):
/// بلاطتا المبيعات والمشتريات أول الشبكة وورقةُ الإدخال بأرشيف الجهة
/// بنوعَيها، والنموذج بنوعه المثبت بلا مبدّل نوع، والحفظ عبر الزر يكتب
/// فاتورة بيع بتسلسل نوعها (س-60/D-080) وتُرحَّل نقدياً مدفوعة (س-03/س-06).
///
/// نمط القاعدة `inMemorySyncClose` حصراً وضخّات محدودة لا pumpAndSettle
/// (درس س22..س26 الموثق)."""
text = replace_once(
    text,
    "/// اختبارات دفعة (18)",
    "/// (درس س22..س26 الموثق).",
    doc_new,
    "التعليق التوثيقي")

# ── 2: الاختبار الأول — بلاطتا الجهة وورقة الإدخال ──
test1_new = """  testWidgets('س202: بلاطتا الفواتير بالرئيسية وورقة الإدخال بجهتها — '
      'وزر البيع بالورقة يفتح النموذج بنوعه المثبت بلا مبدّل نوع '
      '(س-163 بلسان س202)', (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // بلاطتا الجهة أول الشبكة ولا بطاقة أنواع ولا زر سجل بالرئيسية (س202)
    expect(find.text('المبيعات'), findsOneWidget);
    expect(find.text('المشتريات'), findsOneWidget);
    expect(find.text('اختر النوع بالضغط — لا قائمة انتقاء'), findsNothing);
    expect(find.text('سجل الفواتير'), findsNothing);

    // بلاطة المبيعات تفتح الأرشيف بجهته — وزر الإدخال بورقة نوعَي الجهة
    await tester.tap(find.text('المبيعات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(InvoicesScreen), findsOneWidget);
    await tester.tap(find.text('فاتورة جديدة'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة بيع'), findsOneWidget);
    expect(find.text('مردود بيع'), findsOneWidget);
    expect(find.text('فاتورة شراء'), findsNothing,
        reason: 'ورقة الجهة نوعاها حصراً — المبيعات ببيعها ومردودها (س202)');
    await tester.tap(find.text('فاتورة بيع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(InvoiceEditScreen), findsOneWidget);
    expect(find.text('نوع الفاتورة'), findsNothing,
        reason: 'النوع من زر الدخول حصراً — لا انتقاء بالنموذج (س-163)');
    expect(find.text('النوع يُحدد من زر الدخول — لا مبدّل هنا'),
        findsOneWidget);
  });

  """
text = replace_once(
    text,
    "  testWidgets('س-163: بطاقة الفواتير بالرئيسية",
    "  });\n\n",
    test1_new,
    "الاختبار الأول")

# ── 3: الاختبار الثاني — العنوان وخطوة الدخول ──
test2_new = """  testWidgets('س202: بلاطة المبيعات ← ورقة جهتها ← نموذج بيع نقدي ← '
      'حفظ وترحيل — الفاتورة مخزونة بيعاً بتسلسل نوعها ومدفوعة (س-03/س-06)',
      (tester) async {
    final db = DiqqahDatabase.inMemorySyncClose();
    addTearDown(db.close);
    await seedKnownCycle(db);
    await db.createManager(name: 'المالك', login: 'owner', passwordHash: 's:h');

    await tester.pumpWidget(DiqqahApp(db: db));
    await tester.pumpAndSettle();

    // الدخول من بلاطة المبيعات ثم ورقة جهتها (س202) — لا نموذج موحد بانتقاء نوع
    await tester.tap(find.text('المبيعات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('فاتورة جديدة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فاتورة بيع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('نوع الفاتورة'), findsNothing);
"""
text = replace_once(
    text,
    "  testWidgets('س-163: زر البيع بالرئيسية",
    "    expect(find.text('نوع الفاتورة'), findsNothing);\n",
    test2_new,
    "الاختبار الثاني")

# ── 4: تعليق التأكيد القاعدي ──
text = replace_once(
    text,
    "// الفاتورة الجديدة بيعٌ نقدي مرحّل مدفوع — عبر زر الرئيسية لا غير",
    "عبر زر الرئيسية لا غير",
    "// الفاتورة الجديدة بيعٌ نقدي مرحّل مدفوع — عبر بلاطة الجهة وورقتها لا غير",
    "تعليق التأكيد القاعدي")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(text)

# ── التحقق النهائي ──
checks = [
    ("لا بطاقة قديمة", "س-163: بطاقة الفواتير", False),
    ("لا دخول بالزر القديم", "س-163: زر البيع بالرئيسية", False),
    ("بلاطة المبيعات بالاختبار الأول", "بلاطتا الفواتير بالرئيسية", True),
    ("ورقة الجهة", "ورقة الجهة نوعاها حصراً", True),
    ("لسان الشارة الجديد", "النوع يُحدد من زر الدخول", True),
    ("الخطوات القاعدية باقية", "حفظ وترحيل", True),
    ("التسلسل السنوي باقٍ", "26000002", True),
]
bad = 0
for label, marker, want in checks:
    got = marker in text
    ok = got == want
    if not ok:
        bad += 1
    print(f"[{'سليم' if ok else 'مرفوض'}] {label}: {marker[:36]} حاضر={got}")
print(f"الحصيلة: {len(checks)-bad}/{len(checks)}")
sys.exit(1 if bad else 0)
