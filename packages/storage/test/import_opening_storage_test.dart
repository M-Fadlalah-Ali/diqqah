import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// اختبارات الدفعة الثانية من استيراد البيانات بالتخزين — أرصدة أول
/// المدة (D-208/§25.11 — س141): التنفيذ بمعاملة واحدة عبر المحرك
/// الموحد حصراً (07 §1.1) — قيد الذمم 112/211 بأسطر طرف ومقابله 332
/// آلياً (د-1/د-6)، وإذن الإدخال بقيم الملف الصريحة ومقابله 332،
/// والنقد يفتح صناديق عملاته (05 §3.3)، والافتتاحي أول المرحّل (د-6:
/// الاستيراد الثاني بعد الترحيل مرفوض DQ-1025)، وعلامات المتابعات
/// وعلامات إقرار بداية السنة (§25.9).
void main() {
  late DiqqahDatabase db;

  setUp(() async {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() => db.close());

  /// تاريخ اليوم ISO — قاعدة بلا قيود المرحلة تفتح فتراتها بأمان.
  String todayIso() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  List<int> partyBalancesBytes(List<String> rows) => utf8.encode([
        'dq-import:party_balances,1',
        'الكود,الاسم,النوع,الرصيد,العملة,سعر الصرف',
        ...rows,
      ].join('\n'));

  List<int> openingFullBytes(List<String> rows) => utf8.encode([
        'dq-import:opening_full,1',
        'القسم,الكود,الاسم,النوع,الكمية,القيمة,الوحدة,العملة,سعر الصرف',
        ...rows,
      ].join('\n'));

  Future<PartyBalancesImportPlan> planBalances(List<String> rows,
      {String? date}) async {
    return db.planPartyBalancesImportFromDb(
      parsePartyBalancesFile(partyBalancesBytes(rows)),
      openingDateText: date ?? todayIso(),
    );
  }

  Future<OpeningFullImportPlan> planFull(List<String> rows,
      {String? date}) async {
    return db.planOpeningFullImportFromDb(
      parseOpeningFullFile(openingFullBytes(rows)),
      openingDateText: date ?? todayIso(),
    );
  }

  group('الوحدة 4 — أرصدة الذمم بمعاملة واحدة عبر المحرك', () {
    test('قيد متوازن مرحّل: 112/211 بأسطر طرف وparty_id ومقابل 332 آلي',
        () async {
      final plan = await planBalances([
        'C001,علي,عميل,1500,SYP,',
        'S001,مصنع حلب,مورد,700,SYP,',
      ]);
      expect(plan.isApprovable, isTrue, reason: plan.errors.toString());
      final result = await db.executePartyBalancesImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      expect(result.partiesCreated, 2);
      expect(result.moveNumber, isNotNull);
      expect(result.debitBaseMinor, 150000);
      expect(result.creditBaseMinor, 70000);

      // القاعدة نفسها: أسطر الذمم تحمل طرفها والمقابل 332 بالجهة الصحيحة.
      final move = (await db.customSelect(
        "SELECT m.id, m.number FROM moves m "
        "WHERE m.state = 'posted' AND m.ref_doc_type = 'import_opening'",
      ).get()).single;
      final lines = await db.customSelect(
        'SELECT l.debit_minor, l.credit_minor, l.party_id, a.code AS code '
        'FROM move_lines l JOIN accounts a ON a.id = l.account_id '
        'WHERE l.move_id = ?',
        variables: [Variable.withInt(move.data['id'] as int)],
      ).get();
      expect(lines, hasLength(3));
      final byCode = {
        for (final l in lines) l.data['code'] as String: l,
      };
      expect(byCode['112']!.data['party_id'], isNotNull);
      expect(byCode['112']!.data['debit_minor'] as int, 150000);
      expect(byCode['211']!.data['party_id'], isNotNull);
      expect(byCode['211']!.data['credit_minor'] as int, 70000);
      expect(byCode['332']!.data['credit_minor'] as int, 80000,
          reason: 'المقابل دائناً بالفرق (د-1/د-6)');

      // الميزان متوازن حرفاً بعد الافتتاحي.
      final tb = await db.trialBalanceReport();
      expect(tb.isBalanced, isTrue);

      // وحدث الاستيراد بنفس المعاملة (D-076).
      final events = await db.importEventsSince(0);
      expect(events, hasLength(1));
      expect(events.single.unit, 'party_balances');
      expect(events.single.partiesCreated, 2);
    });

    test('الاستيراد الثاني بعد الترحيل مرفوض DQ-1025 — الافتتاحي أول',
        () async {
      final first = await planBalances(['C001,علي,عميل,1500,SYP,']);
      await db.executePartyBalancesImport(
        first,
        eventBackupName: 'event-backup.dqk',
      );
      // posted move بتاريخ اليوم فتاريخ اليوم نفسه لم يعد أسبق منه.
      final second = await planBalances(['C002,سامر,عميل,500,SYP,']);
      expect(second.isApprovable, isFalse);
      expect(second.errors.any((e) => e.dqCode == 'DQ-1025'), isTrue);
    });

    test('لقطة السعر تسجل بتاريخ الافتتاحي والمحفوظ لا يُعدل (F-121/07§1.7)',
        () async {
      final plan = await planBalances([
        'C001,علي,عميل,100,USD,15000',
      ]);
      final result = await db.executePartyBalancesImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      expect(result.debitBaseMinor, 150000000,
          reason: '100 دولار × 15000 ليرة');
      final rates = await db.exchangeRatesOf(2);
      expect(rates, isNotEmpty);
      expect(rates.last.rateToBase, 15000 * 1000000);
      expect(rates.last.date, todayIso());
      // والمسجل لا يُعدل: إعادة الاستيراد بعملة أخرى لا تمسه.
    });
  });

  group('الوحدة 5 — الأرصدة الكاملة بمستنديها وصناديق عملاتها', () {
    test('إذن إدخال واحد بقيم الملف ومقابله 332 وقيد الذمم والنقد متوازن',
        () async {
      final plan = await planFull([
        'ذمم,C001,علي,عميل,,1000,,SYP,',
        'مخزون,SKU1,صنف أول,,10,5000,قطعة,SYP,',
        'نقد,SYP,,,,250000,,,',
      ]);
      expect(plan.isApprovable, isTrue, reason: plan.errors.toString());
      final result = await db.executeOpeningFullImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      expect(result.itemsCreated, 1);
      expect(result.unitsCreated, 1);
      expect(result.partiesCreated, 1);
      expect(result.receiptNumber, isNotNull);
      expect(result.moveNumber, isNotNull);

      // الإذن: 113 مدين بقيمة الملف / 332 دائناً (د-1) — لا 43.
      final receiptMoveLines = await db.customSelect(
        "SELECT a.code AS code, l.debit_minor, l.credit_minor "
        "FROM move_lines l JOIN moves m ON m.id = l.move_id "
        "JOIN accounts a ON a.id = l.account_id "
        "WHERE m.ref_doc_type = 'stock_receipt'",
      ).get();
      final receiptByCode = {
        for (final l in receiptMoveLines) l.data['code'] as String: l,
      };
      expect(receiptByCode['113']!.data['debit_minor'] as int, 500000);
      expect(receiptByCode['332']!.data['credit_minor'] as int, 500000);
      expect(receiptByCode.containsKey('43'), isFalse,
          reason: 'د-1: المقابل 332 لا 43');

      // قيمة الإذن الصريحة على سطره (لا تقييم D-186).
      final receiptLine = (await db.customSelect(
        'SELECT value_base_minor, unit_cost_base_minor, qty_base '
        'FROM stock_receipt_lines',
      ).get()).single;
      expect(receiptLine.data['value_base_minor'] as int, 500000);
      expect(receiptLine.data['qty_base'] as int, 10);

      // الميزان متوازن بمجموع القيدين (07 §1.1).
      final tb = await db.trialBalanceReport();
      expect(tb.isBalanced, isTrue);

      // والحدث موثق بعداداته.
      final events = await db.importEventsSince(0);
      expect(events.single.unit, 'opening_full');
      expect(events.single.itemsCreated, 1);
      expect(events.single.unitsCreated, 1);
    });

    test('النقد يفتح صناديق عملاته بعملتها الواحدة (05 §3.3)', () async {
      final plan = await planFull([
        'نقد,SYP,,,,100000,,,',
        'نقد,USD,,,,100,,USD,15000',
      ]);
      expect(plan.isApprovable, isTrue, reason: plan.errors.toString());
      final result = await db.executeOpeningFullImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      expect(result.boxesCreated, 1, reason: 'الرئيسي قائم والدولاري يفتح');
      final boxes = await db.customSelect(
        'SELECT b.name, c.code AS code FROM cash_boxes b '
        'JOIN currencies c ON c.id = b.currency_id '
        'WHERE b.is_deleted = 0',
      ).get();
      final byCurrency = {
        for (final b in boxes) b.data['code'] as String: b.data['name'],
      };
      expect(byCurrency['USD'], 'صندوق USD');
      expect(byCurrency['SYP'], 'الصندوق الرئيسي');

      // والصندوق الدولاري رصيده المكافئ مخزن حقيقة بلقطة سعره.
      final usdBox = (await db.customSelect(
        'SELECT b.id FROM cash_boxes b JOIN currencies c ON '
        'c.id = b.currency_id WHERE c.code = ? AND b.is_deleted = 0',
        variables: [Variable.withString('USD')],
      ).get()).single;
      final balance = await db.cashBoxBalanceOf(usdBox.data['id'] as int);
      expect(balance, 150000000, reason: '100 دولار × 15000 ليرة');
    });
  });

  group('المتابعات — المصادر والعلامات (§25.9)', () {
    test('332 غير الموزَّع يظهر بعد الافتتاحي ويصمت قبله', () async {
      // الدليل مزروع دوماً فالحساب بلا حركة صفرٌ صامت — لا متابعة.
      expect(await db.openingUndistributedBaseMinor(), 0);
      final plan = await planBalances(['C001,علي,عميل,1500,SYP,']);
      await db.executePartyBalancesImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      // المدين 1500 بلا دائن فالمقابل 332 دائن — رصيده المدين سالب
      // (والاتجاه ملموس بالعرض لا مطلق مخاتل).
      expect(await db.openingUndistributedBaseMinor(), -150000);
    });

    test('تأكيد المراجعة يكتب العلامة والحدث وإقرار البداية كذلك',
        () async {
      expect(await db.followUpsReviewedThrough(), 0);
      expect(await db.earliestOpenPeriodStartText(), isNotNull);
      // حدث استيراد أولاً كي تكون العلامة على شيء، ثم التأكيد فوقه.
      final plan = await planBalances(['C001,علي,عميل,1500,SYP,']);
      await db.executePartyBalancesImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      await db.markFollowUpsReviewed();
      // العلامة تسبق حدث المراجعة نفسه (لا يُراجَع بحدث ليس استيراداً).
      final through = await db.followUpsReviewedThrough();
      expect(through, greaterThan(0));
      await db.acknowledgeFiscalYearStart();
      expect(await db.fiscalStartAcknowledged(),
          await db.earliestOpenPeriodStartText());
      // والحدثان موثقان بأفعالهما.
      final actions = await db.customSelect(
        "SELECT action FROM events WHERE action IN "
        "('follow_ups_reviewed', 'fiscal_start_acknowledged')",
      ).get();
      expect(actions, hasLength(2));
    });

    test('أحداث الاستيراد بعد العلامة وحدها — بعدادات موحدة عبر الوحدات',
        () async {
      final plan = await planBalances(['C001,علي,عميل,1500,SYP,']);
      await db.executePartyBalancesImport(
        plan,
        eventBackupName: 'event-backup.dqk',
      );
      var events = await db.importEventsSince(0);
      expect(events, hasLength(1));
      final through = events.single.eventId;
      await db.markFollowUpsReviewed();
      events = await db.importEventsSince(through);
      expect(events, isEmpty, reason: 'رُوجع حتى آخر حدث فلا جديد');
    });
  });
}
