#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س235 — رقع اختبارات عقد التطبيق الفوري الجديد:
- reports×4 وbatch33×2: ضغطة «عرض» صارت ديبونساً (600ms) بلا ضغطة.
- s204×3: الرقائق صارت أزراراً تملأ وتطبق فوراً — عقودها المكتوبة
  «الملء بلا تحميل» عُفّيت بقرار المالك (توحيد النمط) فتحديث اللسان:
  الحقول تمتلئ (بالوسم الموحد الجديد بدل وسم اليومية القديم) والقائمة
  تعاد بمدى الزر الجديد."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sub(s, old, new, where, count=1):
    assert old in s, "غائب (%s): %r…" % (where, old[:70])
    return s.replace(old, new, count)


def main():
    # ١) reports_screen_test — أربع ضغطات عرض بدُيبونس
    p = os.path.join(ROOT, "packages", "app", "test", "reports_screen_test.dart")
    s = io.open(p, encoding="utf-8").read()
    n = s.count("await tester.tap(find.text('عرض'));")
    if n == 0 and "س235: زر عرض رُفع" in s:
        print("reports_screen_test: مرقع مسبقاً")
    else:
        assert n == 4, "ضغطات العرض: %d" % n
    s = s.replace(
        "await tester.tap(find.text('عرض'));",
        "// س235: زر عرض رُفع — التطبيق الفوري بديبونس قصير بعد آخر حرف.\n"
        "    await tester.pump(const Duration(milliseconds: 600));")
    io.open(p, "w", encoding="utf-8").write(s)
    print("reports_screen_test: %d مواضع" % n)

    # ٢) batch33 — ضغطتان
    p = os.path.join(ROOT, "packages", "app", "test", "batch33_test.dart")
    s = io.open(p, encoding="utf-8").read()
    n = s.count("await tester.tap(find.text('عرض'));")
    if n == 0 and "س235: التطبيق الفوري بديبونس" in s:
        print("batch33_test: مرقع مسبقاً")
    else:
        assert n == 2, "ضغطات batch33: %d" % n
    s = s.replace(
        "await tester.tap(find.text('عرض'));",
        "// س235: التطبيق الفوري بديبونس قصير بلا زر عرض.\n"
        "    await tester.pump(const Duration(milliseconds: 600));")
    io.open(p, "w", encoding="utf-8").write(s)
    print("batch33_test: %d مواضع" % n)

    # ٣) s204 — عقود الأزرار الخمسة الجديدة
    p = os.path.join(ROOT, "packages", "app", "test", "s204_test.dart")
    s = io.open(p, encoding="utf-8").read()

    # ٣-أ) السندات: التطبيق فوري — القائمة تعاد بمدى الزر
    s = sub(s, """  testWidgets('م02: رقائق شريط السندات تملأ من/إلى بلا إعادة تحميل — '
      'وعرف D-077 باقٍ فزر العرض هو الفعّال', (tester) async {""",
            """  testWidgets('س235: أزرار السندات الخمسة تملأ من/إلى وتطبق '
      'فوراً — بلا زر عرض', (tester) async {""", "اسم اختبار السندات")
    s = sub(s, """    await tester.tap(find.text('هذا الشهر'));
    await tester.pump();

    final expected = diqqahRangeShortcutDates(DiqqahRangePreset.thisMonth);
    final from = tester
        .widget<TextField>(
            find.widgetWithText(TextField, 'من (YYYY-MM-DD)'))
        .controller!
        .text;
    final to = tester
        .widget<TextField>(
            find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'))
        .controller!
        .text;
    expect(from, expected.$1, reason: 'الملء بصيغة المنتقي ذاتها (س182)');
    expect(to, expected.$2);
    // والقائمة المعروفة باقية كما كانت — الرقاقة تملأ لا تُحمّل.
    expect(find.textContaining('سند قبض 26000001'), findsOneWidget);
  });""",
            """    await tester.tap(find.text('هذا الشهر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final expected = diqqahRangeShortcutDates(DiqqahRangePreset.thisMonth);
    final from = tester
        .widget<TextField>(
            find.widgetWithText(TextField, 'من (YYYY-MM-DD)'))
        .controller!
        .text;
    final to = tester
        .widget<TextField>(
            find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'))
        .controller!
        .text;
    expect(from, expected.$1, reason: 'الملء بصيغة المنتقي ذاتها (س182)');
    expect(to, expected.$2);
    // س235: التطبيق فوري — القائمة تعاد بمدى الزر فالسند المزروع
    // (آذار) خارج هذا الشهر (تشرين الثاني) فلا يظهر.
    expect(find.textContaining('سند قبض 26000001'), findsNothing,
        reason: 'الزر يطبق لحظته: قائمة الشهر الحالي لا سند آذار فيه');
  });""", "جسد اختبار السندات")

    # ٣-ب) الدخل: التسمية بالأزرار (الجسد يصمد — الملء ذاته)
    s = sub(s, """  testWidgets('م02: قائمة الدخل برقائقها — «هذا العام» يملأ من أول '
      'السنة إلى اليوم', (tester) async {""",
            """  testWidgets('س235: قائمة الدخل بأزرارها — «هذا العام» يملأ من أول '
      'السنة إلى اليوم ويطبق فوراً', (tester) async {""", "اسم اختبار الدخل")

    # ٣-ج) دفتر اليومية: وسما الحقول الموحدان الجديدان (حقلا اليومية
    # القديمان المسمان رُفعا مع الشريط الموحد)
    s = sub(s, """    expect(find.text('اليوم'), findsOneWidget);
    await tester.tap(find.text('اليوم'));
    await tester.pump();

    final expected = diqqahRangeShortcutDates(DiqqahRangePreset.today);
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'من تاريخ (سنة-شهر-يوم)'))
          .controller!
          .text,
      expected.$1,
    );
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'إلى تاريخ (سنة-شهر-يوم)'))
          .controller!
          .text,
      expected.$2,
    );
  });""",
            """    expect(find.text('اليوم'), findsOneWidget);
    await tester.tap(find.text('اليوم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final expected = diqqahRangeShortcutDates(DiqqahRangePreset.today);
    // س235: حقلا الشريط الموحد بوسميه الموحدين (وسما اليومية القديمان
    // رُفعا مع صف الحقول القديم).
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'من (YYYY-MM-DD)'))
          .controller!
          .text,
      expected.$1,
    );
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'إلى (YYYY-MM-DD)'))
          .controller!
          .text,
      expected.$2,
    );
  });""", "جسد اختبار اليومية")
    s = sub(s, """  testWidgets('م02: دفتر اليومية من قائمة التقارير برقائقها — '
      '«اليوم» يملأ الحقلين بيوم واحد', (tester) async {""",
            """  testWidgets('س235: دفتر اليومية من قائمة التقارير بأزراره — '
      '«اليوم» يملأ الحقلين بيوم واحد ويطبق فوراً', (tester) async {""",
            "اسم اختبار اليومية")

    io.open(p, "w", encoding="utf-8").write(s)
    print("s204_test: العقود الثلاثة محدثة")


if __name__ == "__main__":
    main()
