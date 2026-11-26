import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_test/flutter_test.dart';

import 'package:pdf/pdf.dart' show PdfPageFormat;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:diqqah_app/print_service.dart' show buildDocumentPdf;
import 'package:diqqah_app/ui_fonts.dart';

import 'test_guard.dart';

/// اختبارات س158 — دفعة الخطوط بقرار D-212 (بلفظ المالك الحرفي:
/// «انقل الخطين ومحرك gsub إلى الأفكار التطويرية المؤجلة — أدرج
/// الخطوط المتبقية»): المكتبة المدمجة صارت أربع عائلات (ساحل
/// الافتراضي وIBM Plex Sans Arabic وNoto Sans Arabic وVazirmatn)
/// وتجوال خرج بأصوله ورخصته فترحّل محفوظه إلى ساحل إقلاعاً،
/// والراكنان Rubik وReadex Pro ومحرك الطباعة GSUB-aware بقائمة
/// الانتظار (09 §8) — والتقرير البايتي المصدّق «فحص الخطوط قبل
/// التنفيذ v1.00» بجلسة س158.
///
/// الحارس الطباعي الجديد يمارس العربية الحية كما تُطبع فعلاً بكل
/// خيار من الخيارات الأربعة — أي غياب رمز يرمي استثناء Missing glyph
/// فيُحمرّ الجولة قبل أن يصل للمالك (نص التقرير §6.2). والنواقص
/// الهامشية الموثقة (الشدة المركبة FC5E-FC63 وأشكال الفارسية في
/// بلكس ووزيرمتن) خارج المحتوى الحي عمداً — نصوص الإنتاج بلا
/// تشكيل غالباً والتقرير حكم عليها هامشية بحدوده الصادقة §9.
void main() {
  installTestTimeoutGuard();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    appFontChoice.value = kDefaultFontKey;
  });

  test('D-212: أصول الخط الأربع موجودة Regular/Bold ورخصها الأربعة '
      'مرفقة، وأصول تجوال ورخصته حذفت لا تُحمَّل', () async {
    for (final family in <String>[
      'Sahel',
      'IBMPlexSansArabic',
      'NotoSansArabic',
      'Vazirmatn',
    ]) {
      for (final suffix in const ['-Regular.ttf', '-Bold.ttf']) {
        final data = await rootBundle.load('assets/fonts/$family$suffix');
        expect(data.lengthInBytes, greaterThan(10000),
            reason: '$family$suffix أصل مدمج حقيقي');
      }
    }
    for (final license in <String>[
      'LICENSE-sahel.txt',
      'LICENSE-ibmplexsansarabic.txt',
      'LICENSE-notosansarabic.txt',
      'LICENSE-vazirmatn.txt',
    ]) {
      final data = await rootBundle.load('assets/fonts/$license');
      expect(data.lengthInBytes, greaterThan(1000),
          reason: '$license رخصة مرفقة التزاماً بها');
    }
    var tajawalThrew = false;
    try {
      await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
    } catch (_) {
      tajawalThrew = true;
    }
    expect(tajawalThrew, isTrue,
        reason: 'تجوال خرج بD-212 — أصوله حذفت فلا تُحمَّل');
    var tajawalLicenseThrew = false;
    try {
      await rootBundle.load('assets/fonts/LICENSE-tajawal.txt');
    } catch (_) {
      tajawalLicenseThrew = true;
    }
    expect(tajawalLicenseThrew, isTrue,
        reason: 'ورخصته حذفت معه فلا أثر لها');
  });

  test('D-212: الترحيل الصامت — المحفوظ القديم tajawal يعود ساحل فوراً '
      'ويُكتب المحفوظ من جديد فلا يُعاد الترحيل كل إقلاع، والخيار '
      'السليم يمر بلا مساس', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kFontChoicePrefsKey: kFontLegacyTajawal,
    });
    await loadFontChoice();
    expect(appFontChoice.value, kDefaultFontKey,
        reason: 'صاحب الخط المحذوف يعود الافتراضي بلا كسر سلوك');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kFontChoicePrefsKey), kDefaultFontKey,
        reason: 'المحفوظ هُجر إلى ساحل فلا إعادة ترحيل كل إقلاع');
    // الخيار السليم من الخيارات الجديدة يمر كما هو.
    SharedPreferences.setMockInitialValues(<String, Object>{
      kFontChoicePrefsKey: kFontVazir,
    });
    await loadFontChoice();
    expect(appFontChoice.value, kFontVazir);
  });

  test('D-212 الحارس الطباعي: توليد PDF عربي حي كامل بكل خيار من '
      'الأربعة — أي غياب رمز يرمي Missing glyph فيحمرّ الجولة '
      '(عقد D-104 خيار واحد يحكم العرض والطباعة معاً)', () async {
    for (final (key, label) in kFontChoices) {
      final bytes = await buildDocumentPdf(
        title: 'فاتورة مبيعات رقم 26000123',
        headerPairs: const [
          ('التاريخ', '2026-11-17'),
          ('العميل', 'مؤسسة النور للألبان'),
        ],
        columns: const ['الصنف', 'الكمية', 'الإجمالي'],
        rows: const [
          ['لبان حملي فاخر', '12', '36,000'],
          ['أرز بسمتي أصلان', '5', '11,250'],
          ['زيت زيتون بكر', '3', '8,400'],
        ],
        footerPairs: const [
          ('المجموع', '55,650'),
          ('تفقيط', 'خمسة وخمسون ألفاً وستمائة وخمسون ريالاً لا غير'),
        ],
        format: PdfPageFormat.a5,
        fontKey: key,
      );
      expect(bytes, isNotEmpty,
          reason: 'الطباعة بالخيار «$label» تولد PDF سليماً — '
              'واللام-ألف والتنوين وأرقام القيم كلها بلا Missing glyph');
    }
  });
}
