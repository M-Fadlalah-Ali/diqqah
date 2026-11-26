// اختبارات الحافظات الآلية للصدمة — الشطر النقي (س156، D-211).
//
// الفئة 6: حافظة الملفات المسمومة الدائمة تمارس القوالب الخمسة كلها
// بالترميز والقالب والفاصل والأعمدة والإلزامي والتكرار وint64 ومحارف
// التحكم والحد الصلب — والفئة 1 (الشطر النقي): مولّد العينة الثقيلة
// بأرقام التقرير المعتمدة وتوازنها وميزانها وقياسها بحارس انحدار
// متساهل بالCI (نمط party_test — العتبات المطلقة جهاز حقيقي حصراً).
//
// الحاكم: معايير نجاح الصدمة الخمسة (10 §10) — سلامة البيانات والرسائل
// المرقمة بالصف والعمود والسبب (DQ-10xx) وأي رفض بلا رمز فجوة.
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

void main() {
  group('الفئة 6 — حافظة الملفات المسمومة الدائمة (كل قالب استيراد)', () {
    const templates = <(ImportTemplateId, String)>[
      (ImportTemplateId.parties, 'الأطراف'),
      (ImportTemplateId.items, 'الأصناف'),
      (ImportTemplateId.partyBalances, 'أرصدة الذمم'),
      (ImportTemplateId.openingFull, 'الأرصدة الكاملة'),
      (ImportTemplateId.openingQty, 'كميات المخزون الافتتاحية'),
    ];

    // مفسّر القالب — الحافظة تُمارَس على مدخل المفسّر النقي حصراً.
    ({bool isRejected, List<ImportError> errors}) parseBy(
      ImportTemplateId id,
      List<int> bytes,
    ) {
      switch (id) {
        case ImportTemplateId.parties:
          final r = parsePartiesFile(bytes);
          return (isRejected: r.isRejected, errors: r.errors);
        case ImportTemplateId.items:
          final r = parseItemsFile(bytes);
          return (isRejected: r.isRejected, errors: r.errors);
        case ImportTemplateId.partyBalances:
          final r = parsePartyBalancesFile(bytes);
          return (isRejected: r.isRejected, errors: r.errors);
        case ImportTemplateId.openingFull:
          final r = parseOpeningFullFile(bytes);
          return (isRejected: r.isRejected, errors: r.errors);
        case ImportTemplateId.openingQty:
          final r = parseOpeningQtyFile(bytes);
          return (isRejected: r.isRejected, errors: r.errors);
      }
    }

    for (final (id, label) in templates) {
      test('$label: الملف النظيف من باني الحافظة يُقبل — عقلنة الحافظة',
          () {
        final r = parseBy(id, buildCleanImportFile(id, rowCount: 3));
        expect(r.isRejected, isFalse, reason: 'أخطاء العقلنة: ${r.errors}');
      });

      test('$label: الملف النظيف بBOM يُقرأ — البذرة بجلدها', () {
        final r = parseBy(
            id, buildCleanImportFile(id, rowCount: 1, bom: true));
        expect(r.isRejected, isFalse, reason: 'أخطاء BOM: ${r.errors}');
      });

      for (final pf in buildPoisonedFiles(id)) {
        test('$label — ${pf.id}: يُرفض مرقماً لا صمتاً (${pf.note})', () {
          final r = parseBy(id, pf.bytes);
          expect(r.isRejected, isTrue,
              reason: '${pf.id} لا يُقبل: ${r.errors}');
          expect(r.errors, isNotEmpty,
              reason: '${pf.id}: الرفض بلا أخطاء مرقمة فجوة');
          for (final e in r.errors) {
            expect(e.dqCode, startsWith('DQ-10'),
                reason: '${pf.id}: رمز خارج عائلة الاستيراد ${e.dqCode}');
            expect(e.description, isNotEmpty,
                reason: '${pf.id}: وصف عربي فارغ — رسالة غامضة');
            expect(e.suggestedAction, isNotEmpty,
                reason: '${pf.id}: الإجراء المقترح فارغ');
          }
          if (pf.expectedCodes.isNotEmpty) {
            final seen = r.errors.map((e) => e.dqCode).toSet();
            expect(
              pf.expectedCodes.any(seen.contains),
              isTrue,
              reason: '${pf.id}: توقع ${pf.expectedCodes} ولم يظهر — '
                  'الظاهر: $seen',
            );
          }
        });
      }
    }

    test('الحافظة عشر حالات لكل قالب خمس — خمسون سماً دائماً', () {
      for (final id in ImportTemplateId.values) {
        final files = buildPoisonedFiles(id);
        expect(files, hasLength(10),
            reason: 'حافظة $id ناقصة: ${files.map((f) => f.id)}');
      }
    });
  });

  group('الفئة 1 — الشطر النقي للعينة الثقيلة (D-211 بند 1)', () {
    test('العينة الكاملة تُولد بأعداد التقرير حرفاً: '
        '5,500 عميل و1,000 مورد و10,000 صنف و500,000 قيد', () {
      final parties = generateHeavyParties();
      final items = generateHeavyItems();
      final moves = generateHeavyMoves();

      expect(parties.where((p) => p.kindStorage == 'customer'), hasLength(5500));
      expect(parties.where((p) => p.kindStorage == 'supplier'), hasLength(1000));
      expect(items, hasLength(10000));
      expect(moves, hasLength(500000));

      // الحتمية: نفس البذرة نفس البيانات حرفاً — الفشل قابل للإعادة.
      final partiesAgain = generateHeavyParties();
      expect(partiesAgain.map((p) => p.number).toList(),
          parties.map((p) => p.number).toList());

      // التفرد: أرقام الأطراف وأكواد الأصناف فريدة كلها.
      expect(parties.map((p) => p.number).toSet(), hasLength(parties.length));
      expect(items.map((i) => i.sku).toSet(), hasLength(items.length));
    });

    test('أرجل العينة متوازنة قيداً وقيداً ومجموعاً — لا غبار', () {
      final moves = generateHeavyMoves(scale: 0.01);
      var totalDebit = 0;
      var totalCredit = 0;
      for (final m in moves) {
        expect(m.amountMinor, greaterThan(0),
            reason: 'قيد بمبلغ ${m.number} صفر');
        expect(m.debitAccountId, isNot(equals(m.creditAccountId)),
            reason: 'قيد ${m.number} على حساب واحد');
        totalDebit += m.amountMinor;
        totalCredit += m.amountMinor;
      }
      expect(totalDebit, totalCredit);

      final lines = heavyMovesToTrialLines(moves);
      expect(lines, hasLength(moves.length * 2));
      final sumDebit = lines.fold<int>(0, (s, l) => s + l.debitMinor);
      final sumCredit = lines.fold<int>(0, (s, l) => s + l.creditMinor);
      expect(sumDebit, sumCredit);
    });

    test('ميزان المراجعة على العينة الكاملة: متوازن وقياس التوليد '
        'بحارس انحدار متساهل بالCI (العتبات المطلقة جهاز حقيقي حصراً)',
        () {
      final watch = Stopwatch()..start();
      final accounts = heavySampleAccounts();
      final lines = heavyMovesToTrialLines(generateHeavyMoves());
      final report = buildTrialBalance(lines, accounts);
      watch.stop();

      expect(report.isBalanced, isTrue,
          reason: 'ميزان العينة الكاملة غير متوازن');
      expect(report.totalDebitMinor, greaterThan(0));
      // الحسابان فقط لهما حركة فصفا الميزان اثنان.
      expect(report.rows, hasLength(2));
      // حارس الانحدار: التوليد والتجميع عند مليون رجل أضعاف أسرع من
      // الحد — الارتفاع عنه علة انحدار لا بطء طبيعي (نمط party_test).
      expect(watch.elapsed, lessThan(const Duration(seconds: 120)),
          reason: 'التوليد والميزان عند 500,000 قيد استغرق ${watch.elapsed}');

      // القياس مطبوع ليُوثق به الاتجاه بين الجولات لا ليحكم.
      // ignore: avoid_print
      print('العينة الكاملة: ${lines.length} رجل — التوليد والميزان '
          '${watch.elapsedMilliseconds}ms');
    });

    test('المقياس 0.1 يحافظ النسب: 550 عميلاً و100 مورد و1,000 صنف '
        'و50,000 قيد — شطر CI التخزيني', () {
      final spec = const HeavySampleSpec(scale: 0.1);
      expect(spec.customers, 550);
      expect(spec.suppliers, 100);
      expect(spec.items, 1000);
      expect(spec.moves, 50000);
      expect(generateHeavyParties(scale: 0.1), hasLength(650));
      expect(generateHeavyItems(scale: 0.1), hasLength(1000));
      expect(generateHeavyMoves(scale: 0.1), hasLength(50000));
    });
  });
}
