// اختبارات س232 — فهرس النصوص العربية (د12: استخراج نصوص الشاشات
// الثلاث الكبرى وفاء وعد التدويل D-037): القيم الحرفية بعينها (بما
// فيها الفروغ الأمامية والخلفية الحرجة)، والقوالب ذات الوسائط بخرجها
// الدقيق، ووحدانية القيم بقراءة المصدر (بنمط س215 الذي يقرأ pubspec)،
// ومدخل اللغة بسطره الواحد القابل للتبديل (نقطة إطلاق الإنكليزية
// بلا إعادة هيكلة — D-037).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/l10n/app_strings.dart';

void main() {
  test('س232: القيم الثابتة حرفاً — بما فيه الفروغ الأمامية والخلفية',
      () {
    expect(S.allLabel, 'الكل');
    expect(S.invoicesTitle, 'الفواتير');
    expect(S.settingsTitle, 'الإعدادات');
    expect(S.semicolonSpace, '؛ ');
    expect(S.draftSuffix, ' · مسودة');
    expect(S.serviceSuffix, ' (خدمة)');
    expect(S.assemblySuffix, ' (تجميعي)');
    expect(S.equivalentTrailing('USD', '150'), 'المكافئ بUSD 150 · ');
    expect(S.exportCsv, 'تصدير CSV');
    expect(S.trialBalanceTitle, 'ميزان المراجعة');
  });

  test('س232: القوالب ذات الوسائط بخرجها الدقيق — الوسائط Object '
      'فالاستيفاء يطابق الأصل حرفاً', () {
    expect(S.itemWithNumber(47), 'صنف #47');
    expect(S.paidAndRemaining('1,200', '1,000', '300'),
        '1,200المدفوع 1,000 · الباقي 300');
    expect(
        S.postDraftBody('بيع — أبو أحمد', '15,000', 'SYP'),
        'بيع — أبو أحمد بمبلغ 15,000 SYP.\n'
        'الترحيل يُرحّل الفاتورة: تمس المخزون والدفتر والذمة وتُمنح رقمها '
        'النهائي — ولا رجوع بعده إلا بمردود.');
    expect(S.creditLimitExceededBody('أبو أحمد', '1,500', '1,000', '500'),
        'رصيد «أبو أحمد» بعد هذه الفاتورة 1,500 — يتجاوز الحد المسموح '
        '1,000 بفائض 500.\nالتنبيه إرشاد لا منع — القرار لك.');
    expect(S.vaultRecoveryCodeBody,
        startsWith('يفك نسخ الجيل الرابع والخامس على جهاز آخر غير هذا'));
    expect(S.draftHoldsStockNote,
        startsWith(' وبالإعداد المعتمد تحجز كمياتها'));
  });

  test('س232: وحدانية القيم وقيمها غير الفارغة بقراءة مصدر الفهرس '
      '(لا قيمة ل مفتاحين — والعدد لا ينزل تحت أرضية الدفعة)', () {
    final src = File('lib/l10n/strings_ar.dart').readAsStringSync();
    final consts = RegExp(r"static const String (\w+) = (.+);")
        .allMatches(src)
        .toList();
    final methods = RegExp(r"static String (\w+)\([^)]*\) => (.+);")
        .allMatches(src)
        .toList();
    expect(consts, isNotEmpty);
    expect(methods, isNotEmpty);
    final values = <String>[];
    for (final m in consts.followedBy(methods)) {
      final v = m.group(2)!.trim();
      expect(v.length, greaterThan(2), reason: 'قيمة فارغة لمفتاح ${m.group(1)}');
      values.add(v);
    }
    expect(values.toSet().length, values.length,
        reason: 'قيمة واحدة ل مفتاحين — الفهرس يوحد القوالب فلا تكرار');
    expect(values.length, greaterThanOrEqualTo(506),
        reason: 'أرضية دفعة س232: 506 مفاتيح فأكثر');
  });

  test('س232: مدخل اللغة بسطر تبديل واحد — إطلاق الإنكليزية لاحقاً '
      'بلا مساس بشاشة (D-037: لا إعادة هيكلة)', () {
    final src = File('lib/l10n/app_strings.dart').readAsStringSync();
    final exports = RegExp(r"^export '[^']+'( show S)?;$", multiLine: true)
        .allMatches(src)
        .toList();
    expect(exports.length, 1, reason: 'سطر لغة واحد قابل للتبديل حصراً');
    expect(exports.single.group(0), contains('strings_ar.dart'));
  });

  test('س232: الشاشات الثلاث تستورد المدخل الواحد — لا استيراد بيانات '
      'مباشرة', () {
    for (final f in [
      'lib/invoices_screen.dart',
      'lib/settings_screen.dart',
      'lib/reports_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains("import 'l10n/app_strings.dart';"), isTrue,
          reason: '$f');
      expect(src.contains('l10n/strings_ar.dart'), isFalse,
          reason: '$f: البيانات لا تُستورد مباشرة — المدخل وحده');
    }
  });
}
