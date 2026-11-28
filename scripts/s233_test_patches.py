#!/usr/bin/env python3
# -*- coding utf-8 -*-
# -*- coding: utf-8 -*-
"""س233 — ترقيع اختبارات الجولة المحلية الأولى: بطاقات المرحلة أ أطالت
قائمة الإعدادات فخرجت أهداف مباشرة من نطاق البناء الكسول (درس D-098:
الوصول بالتمرير ثم الإظهار قبل الضغط)، وحارس س219 يتبع مالك التجزئة
الخلفية بعد شطر الملف (settings/identity_section)، وشاشة الخطأ تحتاج
حقن صفر للحد الأدنى لشاشة البدء — كل تصويب موثق بموضعه.
"""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = lambda name: os.path.join(ROOT, "packages", "app", "test", name)
L = lambda name: os.path.join(ROOT, "packages", "app", "lib", name)


def patch(path, pairs):
    s = io.open(path, encoding="utf-8").read()
    for (old, new) in pairs:
        assert old in s, "NOT FOUND in %s: %r" % (path, old[:70])
        assert s.count(old) >= 1
        s = s.replace(old, new, 1)
    io.open(path, "w", encoding="utf-8").write(s)
    print("patched", os.path.basename(path))


# ═══ ١) main.dart: حقن الحد الأدنى لشاشة البدء بDiqqahApp ═══
patch(L("main.dart"), [
    ("""  const DiqqahApp({super.key, this.db, this.dbPath, this.hasherIterations = PasswordHasher.secureIterations});""",
     """  /// س233 (D-233): الحد الأدنى لشاشة البدء — الإنتاج نصف ثانية،
  /// واختبارات فشل الافتتاح تحقن الصفر فتصل شاشة الخطأ فوراً.
  final Duration splashMinimum;

  const DiqqahApp({
    super.key,
    this.db,
    this.dbPath,
    this.hasherIterations = PasswordHasher.secureIterations,
    this.splashMinimum = const Duration(milliseconds: 500),
  });"""),
    ("""                // س233 (D-233 — المرحلة أ/4): الحد الأدنى نصف ثانية
                // لشاشة البدء بالإنتاج حصراً — والحقن الاختباري (قاعدة
                // محقونة) يتجاوزه فلا يبطئ اختباراً واحداً.
                splashMinimum: db == null
                    ? const Duration(milliseconds: 500)
                    : Duration.zero,""",
     """                // س233 (D-233 — المرحلة أ/4): الحد الأدنى نصف ثانية
                // بالإنتاج حصراً — والحقن الاختباري (قاعدة محقونة)
                // يتجاوزه فلا يبطئ اختباراً واحداً.
                splashMinimum:
                    db == null ? widget.splashMinimum : Duration.zero,"""),
])

# ═══ ٢) gate_error_test: حقن الصفر لشاشة الخطأ ═══
patch(T("gate_error_test.dart"), [
    ("""    await tester.pumpWidget(const DiqqahApp());""",
     """    // س233 (D-233): شاشة البدء بحدّها الأدنى حق الإنتاج — شاشة
    // الخطأ تُختبر بالصفر فتظهر فور فشل الافتتاح لا بعد نصف ثانية.
    await tester.pumpWidget(
        const DiqqahApp(splashMinimum: Duration.zero));"""),
])

# ═══ ٣) s219_test: مالك التجزئة الخلفية بعد الشطر ملف الهوية ═══
patch(T("s219_test.dart"), [
    ("""      'device_gate_screen.dart',
      'settings_screen.dart',
      'users_screen.dart',
      'first_run_screen.dart',""",
     """      'device_gate_screen.dart',
      // س233 (D-230): شطر ملف الإعدادات — مالك تجزئة الكلمة صار ملف
      // الهوية (settings/identity_section.dart) فالحارس يتبعه.
      'settings/identity_section.dart',
      'users_screen.dart',
      'first_run_screen.dart',"""),
])

# ═══ ٤) s213_test: الأقسام صارت ستة (D-230) ═══
patch(T("s213_test.dart"), [
    ("""  testWidgets('س213/D-218: ترويسات الأقسام الخمسة داخل القائمة ذاتها '
      'بترتيب القرار — بلا صفحات فئات ولا جانب كاشف (الخيار ب مؤجل)',
      (tester) async {""",
     """  testWidgets('س213/D-218 وس233/D-230: ترويسات الأقسام الستة داخل '
      'القائمة ذاتها بترتيب القرار — بلا صفحات فئات ولا جانب كاشف '
      '(الخيار ب مؤجل)',
      (tester) async {"""),
    ("""    for (final header in [
      'الهوية والصلاحيات',
      'البيانات والأمان',
      'سياسات البيع',
      'العرض والمظهر',
      'العمليات',
    ]) {""",
     """    // س233 (D-230): «البيانات والأمان» شُطرت قسمين — الأمان والجلسة
    // والنسخ والاستعادة — فصارت الأقسام ستة بترتيب القرار.
    for (final header in [
      'الهوية والصلاحيات',
      'الأمان والجلسة',
      'النسخ والاستعادة',
      'سياسات البيع',
      'العرض والمظهر',
      'العمليات',
    ]) {"""),
])

# ═══ ٥) widget_test: سحب قبل الإظهار (درس D-098) ═══
SCROLL_BACKUP = """    // س233: بطاقة النسخ الآلي أطالت القائمة فخرج الزر من نطاق البناء
    // الكسول — سحبٌ حتى يُبنى ثم إظهار (درس D-098 والسرد الكسول).
    for (var i = 0;
        i < 12 && find.text('إنشاء نسخة احتياطية').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
"""
patch(T("widget_test.dart"), [
    ("""    await tester.ensureVisible(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    // النسخ فيها IO حقيقي متسلسل""",
     SCROLL_BACKUP + """    await tester.ensureVisible(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    // النسخ فيها IO حقيقي متسلسل"""),
    ("""    await tester.ensureVisible(find.text('تشفير النسخة بمفتاح البرنامج'));""",
     """    // س233: نفس درس السحب أعلاه — الوصول بالتمرير قبل الإظهار.
    for (var i = 0;
        i < 12 &&
            find.text('تشفير النسخة بمفتاح البرنامج').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('تشفير النسخة بمفتاح البرنامج'));"""),
])

# ٥-ب) الموضع الثالث (زر النسخ باختبار D-056 آخر الملف)
s = io.open(T("widget_test.dart"), encoding="utf-8").read()
OLD3 = """    await tester.ensureVisible(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء نسخة احتياطية'));"""
COUNT = s.count(OLD3)
assert COUNT >= 1, "موضع D-056 غير موجود"
s = s.replace(OLD3, SCROLL_BACKUP + OLD3, 1)
io.open(T("widget_test.dart"), "w", encoding="utf-8").write(s)
print("widget_test D-056: patched (%d مواضع متبقية للنمط)" % (COUNT - 1))

# ═══ ٦) batch10: سحب إلى مربع التضمين قبل التوقع ═══
patch(T("batch10_test.dart"), [
    ("""    expect(find.text('تضمين صور الأصناف'), findsOneWidget,
        reason: 'س-129: مربع التضمين افتراضه مفعّل بحجم المجلد ظاهراً');""",
     """    // س233: بطاقة النسخ الآلي وبطاقة فحص الثوابت (بقسمها الجديد) أزاحتا
    // بطاقة العرض أسفل — سحبٌ إلى مربع التضمين قبل التوقع (درس D-098).
    await _scrollToText(tester, 'تضمين صور الأصناف');
    expect(find.text('تضمين صور الأصناف'), findsOneWidget,
        reason: 'س-129: مربع التضمين افتراضه مفعّل بحجم المجلد ظاهراً');"""),
])

# ═══ ٧) batch34 + sync_work + diagnostics: إظهار قبل الضغط ═══
ENSURE = """    // س233: درس السرد الكسول الثاني — الموجود بنطاق الكاش قد يكون خارج
    // الشاشة فلا يتلقى الضغطة؛ الإظهار قبل الضغط (عرف D-098).
    await tester.ensureVisible(find.text('%s'));
    await tester.pump();
"""
patch(T("batch34_test.dart"), [
    ("""    await tester.tap(find.text('العملات وأسعار الصرف'));""",
     (ENSURE % 'العملات وأسعار الصرف') +
     """    await tester.tap(find.text('العملات وأسعار الصرف'));"""),
])
patch(T("sync_work_test.dart"), [
    ("""    await tester.tap(find.text('العمل الجماعي والمزامنة'));""",
     """    // س233: درس السرد الكسول الثاني — الإظهار قبل الضغط (عرف D-098).
    await tester.ensureVisible(find.text('العمل الجماعي والمزامنة'));
    await tester.pump();
    await tester.tap(find.text('العمل الجماعي والمزامنة'));"""),
])
patch(T("diagnostics_test.dart"), [
    ("""    await scrollToText(tester, 'التشخيص ومرجع الأخطاء');
    expect(find.text('التشخيص ومرجع الأخطاء'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_diagnostics')));""",
     """    await scrollToText(tester, 'التشخيص ومرجع الأخطاء');
    expect(find.text('التشخيص ومرجع الأخطاء'), findsOneWidget);
    // س233: درس السرد الكسول الثاني — الإظهار قبل الضغط (عرف D-098).
    await tester.ensureVisible(find.text('التشخيص ومرجع الأخطاء'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings_diagnostics')));"""),
])

# ═══ ٨) m3_polish_s198: سحب إلى كشف بطاقة النسخ الكامل قبل التوقع ═══
patch(T("m3_polish_s198_test.dart"), [
    ("""      // بلا جلسة: بطاقة المجدول محجوبة بصلاحيتها والاستيراد بالمديرية
      // — فكشف بطاقة النسخ الكامل وحدها على المسرح.
      expect(find.text('كيف يعمل؟'), findsOneWidget);""",
     """      // بلا جلسة: بطاقة المجدول محجوبة بصلاحيتها والاستيراد بالمديرية
      // — فكشف بطاقة النسخ الكامل وحدها على المسرح.
      // س233 (D-230): بطاقة فحص الثوابت بقسم الأمان الجديد أزاحت بطاقة
      // النسخ الكامل أسفل نطاق البناء الأولي — سحبٌ إلى كشفها أولاً
      // (درس D-098: الوصول بالتمرير لا الافتراض).
      for (var i = 0;
          i < 12 && find.text('كيف يعمل؟').evaluate().isEmpty;
          i++) {
        await tester.drag(find.byType(ListView).first,
            const Offset(0, -300));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('كيف يعمل؟'));
      await tester.pump();
      expect(find.text('كيف يعمل؟'), findsOneWidget);"""),
])

print("ALL TEST PATCHES APPLIED")
