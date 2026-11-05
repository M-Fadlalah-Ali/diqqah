import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:drift/drift.dart' show Value, Variable;

/// الصيغة الجديدة D-169 (سنة رقمين + عدّاد مبطن بلا فاصل) — تُشتق من
/// سنة البذرة نفسها كي لا يكسر تغيّر سنة CI (نمط التواريخ المشتقة).
String seqNum(int year, int n, [int w = 6]) =>
    '${(year % 100).toString().padLeft(2, '0')}${n.toString().padLeft(w, '0')}';

/// أدوات الدفعة: معرفات حسابات البذر بالبحث بالكود (لا بالثبوت الأعمى
/// من الترتيب) — الدليل بيانات إعداد وقد يعاد ترقيمه (07 §1.6).
Future<int> accountIdByCode(DiqqahDatabase db, String code) async {
  final rows = await db.customSelect(
    'SELECT id FROM accounts WHERE code = ?',
    variables: [Variable.withString(code)],
  ).get();
  expect(rows, hasLength(1), reason: 'كود الدليل $code فريد من البذر');
  return rows.first.data['id'] as int;
}

Future<int> generalJournalId(DiqqahDatabase db) async {
  final rows = await db.customSelect(
    "SELECT id FROM journals WHERE code = 'general'",
  ).get();
  expect(rows, hasLength(1));
  return rows.first.data['id'] as int;
}

/// السنة المالية المزروعة (سنة «الآن» وقت البذر) — بلا افتراض سنة
/// شئها CI؛ التواريخ المولدة داخل نطاقها.
Future<int> seededYear(DiqqahDatabase db) async {
  final rows =
      await db.customSelect('SELECT name, state FROM fiscal_years').get();
  expect(rows, hasLength(1));
  expect(rows.first.data['state'], 'open');
  return int.parse(rows.first.data['name'] as String);
}

MoveLineDraft line(int accountId,
        {required int debit, required int credit}) =>
    MoveLineDraft(
        accountId: accountId, debitMinor: debit, creditMinor: credit);

/// تاريخ ديناميكي داخل السنة المزروعة (سنة «الآن» وقت البذر) — بلا
/// افتراض سنة شئها CI فالبذر يزرع DateTime.now().year. اليوم 15 افتراضياً
/// ضمن أي فترة شهرية.
Future<String> isoDate(DiqqahDatabase db, {int month = 1, int day = 15}) async {
  final year = await seededYear(db);
  final mm = month.toString().padLeft(2, '0');
  final dd = day.toString().padLeft(2, '0');
  return '$year-$mm-$dd';
}


void main() {
  late DiqqahDatabase db;

  setUp(() {
    db = DiqqahDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('نسخة المخطط = 7 (F-011 — v7 دفعة الفواتير: D-079..D-082 معروضة)', () {
    expect(db.schemaVersion, 21);
  });

  group('البذر الأولي (س-42) — الدليل إعداد لا كود (07 §1.6)', () {
    test('الدليل الافتراضي 58 حساباً بأكواد 03 المعتمدة والاتجاهات الصحيحة',
        () async {
      // أول قراءة تثير onCreate: createAll + المُشغِّلات + البذر
      final accounts = await db.allLedgerAccounts();
      expect(accounts, hasLength(58));
      final byCode = {for (final a in accounts) a.code: a};
      final cash = byCode['1111']!;
      expect(cash.name, 'الصندوق الرئيسي');
      expect(cash.type, AccountType.asset);
      expect(cash.normalSide, NormalSide.debit);
      expect(cash.isLeaf, isTrue);
      expect(cash.isActive, isTrue);
      // العكسية: 42 income مدينها و53 expense دائنها (03 §1-4)
      expect(byCode['42']!.normalSide, NormalSide.debit);
      expect(byCode['53']!.normalSide, NormalSide.credit);
      // الجاهز معطّل: 121 أصوات ثابتة
      expect(byCode['121']!.isActive, isFalse);
      // الأب غير الورقي: «1 الأصول»
      expect(byCode['1']!.isLeaf, isFalse);
    });

    test('الدفاتر الخمسة وسنة «الآن» بفتراتها الشهرية المفتوحة', () async {
      final journals = await db.select(db.journals).get();
      expect(journals.map((j) => j.code).toSet(),
          {'sales', 'purchase', 'cash', 'stock', 'general'});
      final periods = await db.ledgerPeriods();
      expect(periods, hasLength(12), reason: 'D-027: شهرية افتراضياً');
      expect(periods.every((p) => p.isOpen), isTrue);
      final year = await seededYear(db);
      final february = periods.firstWhere((p) => p.startDateText.endsWith('-02-01'));
      expect(february.startDateText, '$year-02-01');
      expect(february.endDateText, '$year-02-28');
      final january = periods.firstWhere((p) => p.startDateText.endsWith('-01-01'));
      expect(january.endDateText, '$year-01-31');
    });

    test('الازدواج مستحيل — كل كود بذر فريد بصف واحد ولا صف مكرر', () async {
      // فاحص الفراغ ذاته حارس التكرار — والترحيلة (الاختبار الأخير)
      // هي المسار الذي يجري البذر بعد خطوات سابقة، فالحارس هنا نفسه
      final accounts = await db.allLedgerAccounts();
      final before = accounts.length;
      expect(before, 58);
      final dupes = await db
          .customSelect(
              'SELECT code, COUNT(*) AS c FROM accounts GROUP BY code HAVING c > 1')
          .get();
      expect(dupes, isEmpty);
    });
  });

  group('المسودة والترحيل (س-43..س-47) — المحرك والترقيم', () {
    test('س-43: مسودة متوازنة تُخزن بلا رقم وحدث «created» بلقطة كاملة',
        () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final dateText = await isoDate(db, month: 10);
      final moveId = await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        narration: 'مسحوبات المالك',
        lines: [
          line(withdrawals, debit: 50000, credit: 0),
          line(cash, debit: 0, credit: 50000),
        ],
      );
      final move = await (db.select(db.moves)
            ..where((t) => t.id.equals(moveId)))
          .getSingle();
      expect(move.state, 'draft');
      expect(move.number, '', reason: 'الترقيم عند الترحيل حصراً (07 §1.9)');
      expect(move.periodId, isNull, reason: 'الفترة تُكتب عند الترحيل');
      final lines =
          await (db.select(db.moveLines)..where((t) => t.moveId.equals(moveId)))
              .get();
      expect(lines, hasLength(2));
      final events = await db.select(db.events).get();
      expect(events, hasLength(1));
      expect(events.first.action, 'created');
      expect(events.first.payload, contains('مسحوبات المالك'));
      expect(events.first.payload, contains('account_id'),
          reason: 'اللقطة الكاملة بأسطرها (07 §2.3)');
    });

    test('س-44: مسودة غير متوازنة ترفض قبل الكتابة بلا أي صف ولا حدث',
        () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final sales = await accountIdByCode(db, '411');
      final dateText = await isoDate(db, month: 10);
      expect(
        () => db.createMoveDraft(
          journalId: journalId,
          dateText: dateText,
          lines: [
            line(cash, debit: 50000, credit: 0),
            line(sales, debit: 0, credit: 40000),
          ],
        ),
        throwsA(isA<LedgerValidationException>()),
      );
      expect(await db.select(db.moves).get(), isEmpty,
          reason: 'لا قيد مكتوب');
      expect(await db.select(db.events).get(), isEmpty,
          reason: 'ولا حدث — الحدث مع العملية في المعاملة ذاتها (07 §2.4)');
    });

    test('س-45: السطر الواحد والأب والمعطل كلها مرفوضة', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final root = await accountIdByCode(db, '1'); // أب غير ورقي
      final reserved = await accountIdByCode(db, '52'); // جاهز معطّل
      final dateText = await isoDate(db, month: 10);
      expect(
        () => db.createMoveDraft(
          journalId: journalId,
          dateText: dateText,
          lines: [line(cash, debit: 100, credit: 0)],
        ),
        throwsA(isA<LedgerValidationException>()),
        reason: 'سطر واحد — 05 §7-1',
      );
      expect(
        () => db.createMoveDraft(
          journalId: journalId,
          dateText: dateText,
          lines: [
            line(root, debit: 100, credit: 0),
            line(cash, debit: 0, credit: 100),
          ],
        ),
        throwsA(isA<LedgerValidationException>()),
        reason: 'الورقية وحدها تقيد — 03 §1-2',
      );
      expect(
        () => db.createMoveDraft(
          journalId: journalId,
          dateText: dateText,
          lines: [
            line(reserved, debit: 100, credit: 0),
            line(cash, debit: 0, credit: 100),
          ],
        ),
        throwsA(isA<LedgerValidationException>()),
        reason: 'المعطل لا يقيد — 03 §1-3',
      );
    });

    test('D-169 (س56): ضبط عرض العدّاد 5 يجعل الترقيم «سنة رقمين + عدّاد 5» بلا فاصل',
        () async {
      await db.setCounterWidth(5);
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final year = await seededYear(db);
      final dateText = await isoDate(db, month: 10);
      final moveId = await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        narration: 'تجربة العرض',
        lines: [
          line(withdrawals, debit: 1000, credit: 0),
          line(cash, debit: 0, credit: 1000),
        ],
      );
      await db.postMove(moveId);
      final move = await (db.select(db.moves)
            ..where((t) => t.id.equals(moveId)))
          .getSingle();
      expect(move.number, seqNum(year, 1, 5),
          reason: 'مثال المالك نفسه: 2026 بعرض 5 = «2600001» (D-169)');
    });

    test('س-46: الترحيل يكتب الحالة والرقم والفترة وحدث «posted»', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final year = await seededYear(db);
      final dateText = await isoDate(db, month: 10);
      final moveId = await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        narration: 'مسحوبات المالك',
        lines: [
          line(withdrawals, debit: 50000, credit: 0),
          line(cash, debit: 0, credit: 50000),
        ],
      );
      await db.postMove(moveId);
      final move = await (db.select(db.moves)
            ..where((t) => t.id.equals(moveId)))
          .getSingle();
      expect(move.state, 'posted');
      expect(move.number, '${seqNum(year, 1)}',
          reason: 'الترقيم السنوي من سنة تاريخ القيد (07 §1.9)');
      expect(move.periodId, isNotNull);
      final actions = (await db.select(db.events).get())
          .map((e) => e.action)
          .toList();
      expect(actions, containsAll(['created', 'posted']));
    });

    test('س-47: الترقيم متصل بلا فجوات ولا إعادة استعمال (07 §1.9)', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final year = await seededYear(db);
      final dateText = await isoDate(db, month: 10);
      Future<int> makeDraft() => db.createMoveDraft(
            journalId: journalId,
            dateText: dateText,
            lines: [
              line(withdrawals, debit: 1000, credit: 0),
              line(cash, debit: 0, credit: 1000),
            ],
          );
      final first = await makeDraft();
      final second = await makeDraft();
      final third = await makeDraft();
      // ترحيل متباعد الترتيب لا يغير التسلسل — العدّاد المركزي لا نافذة
      await db.postMove(third);
      await db.postMove(first);
      await db.postMove(second);
      final numbers = (await db.select(db.moves).get())
          .map((m) => m.number)
          .toSet();
      expect(numbers,
          {'${seqNum(year, 1)}', '${seqNum(year, 2)}', '${seqNum(year, 3)}'});
      // حذف مسودة لا يعيد رقمها للأمام ولا للأثر — السجل يوثق الحذف
      final draftToDelete = await makeDraft();
      await db.deleteMoveDraft(draftToDelete);
      final fourth = await makeDraft();
      await db.postMove(fourth);
      final fourthRow = await (db.select(db.moves)
            ..where((t) => t.id.equals(fourth)))
          .getSingle();
      expect(fourthRow.number, '${seqNum(year, 4)}',
          reason: 'الترحيل اللاحق يواصل التسلسل بلا فجوة ولا إعادة');
      final actions =
          (await db.select(db.events).get()).map((e) => e.action).toList();
      expect(actions.where((a) => a == 'draft_deleted'), hasLength(1));
    });

    test('ترحيل قيد مرحّل ثانية يرفض — الآلة بلا رجوع (07 §1.2)', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final dateText = await isoDate(db, month: 10);
      final moveId = await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        lines: [
          line(withdrawals, debit: 100, credit: 0),
          line(cash, debit: 0, credit: 100),
        ],
      );
      await db.postMove(moveId);
      expect(() => db.postMove(moveId), throwsA(anything));
    });
  });

  group('المُشغِّلات الحواجز (س-48 جزء الحاجز الثاني — 07 §2.2)', () {
    /// إدراج خام يتجاوز المحرك عمداً — ليثبت الحاجز الثاني مستقلاً عن
    /// المدقق (07 §2.2: «كل واحد منهما وحده قابل للتعطيل بالخطأ»).
    Future<int> rawUnbalancedMove(String dateText) async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final sales = await accountIdByCode(db, '411');
      await db.customStatement(
        'INSERT INTO moves (journal_id, date_text, state, number, uuid) '
        'VALUES (?, ?, ?, ?, ?)',
        [journalId, dateText, 'draft', '', 'raw-uuid-1'],
      );
      final moveId = (await db.customSelect('SELECT MAX(id) AS m FROM moves')
              .getSingle())
          .data['m'] as int;
      for (final pair in [
        [cash, 50000, 0],
        [sales, 0, 40000],
      ]) {
        await db.customStatement(
          'INSERT INTO move_lines (move_id, account_id, debit_minor, '
          'credit_minor, uuid) VALUES (?, ?, ?, ?, ?)',
          [moveId, pair[0], pair[1], pair[2], 'raw-line-${pair[0]}'],
        );
      }
      return moveId;
    }

    test('التوازن مفروض من القاعدة حتى لو تجاوز المدقق', () async {
      final moveId = await rawUnbalancedMove(await isoDate(db, month: 10));
      expect(
        () => db.customStatement(
            "UPDATE moves SET state = 'posted' WHERE id = ?", [moveId]),
        throwsA(anything),
        reason: 'المُشغِّل يرفض الانتقال بقيد غير متوازن',
      );
      final state = (await db.customSelect(
              'SELECT state FROM moves WHERE id = ?',
              variables: [Variable.withInt(moveId)])
          .getSingle());
      expect(state.data['state'], 'draft',
          reason: 'الانتقال لم يقع — لا حالة وسطى');
    });

    test('الحد الأدنى سطران مفروض من القاعدة', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      await db.customStatement(
        'INSERT INTO moves (journal_id, date_text, state, number, uuid) '
        'VALUES (?, ?, ?, ?, ?)',
        [journalId, '2026-10-30', 'draft', '', 'raw-uuid-2'],
      );
      final moveId = (await db.customSelect('SELECT MAX(id) AS m FROM moves')
              .getSingle())
          .data['m'] as int;
      // سطر وحيد بمبلغين صفرين — التوازن 0=0 يمرّ فيفصح فحصُ العدد:
      // قيد مرحّل بأسطر أقل من اثنين (05 §7-1) حاجزاً مستقلاً عن التوازن.
      await db.customStatement(
        'INSERT INTO move_lines (move_id, account_id, debit_minor, '
        'credit_minor, uuid) VALUES (?, ?, ?, ?, ?)',
        [moveId, cash, 0, 0, 'raw-line-single'],
      );
      expect(
        () => db.customStatement(
            "UPDATE moves SET state = 'posted' WHERE id = ?", [moveId]),
        throwsA(anything),
      );
    });

    test('المرحّل مجمد: لا تعديل أسطره ولا إدراج عليها ولا حذف قيده',
        () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final moveId = await db.createMoveDraft(
        journalId: journalId,
        dateText: await isoDate(db, month: 10),
        lines: [
          line(withdrawals, debit: 100, credit: 0),
          line(cash, debit: 0, credit: 100),
        ],
      );
      await db.postMove(moveId);
      // لا تعديل سطر مرحّل (F-055)
      expect(
        () => db.customStatement(
            'UPDATE move_lines SET debit_minor = 999 WHERE move_id = ?',
            [moveId]),
        throwsA(anything),
      );
      // لا إدراج سطر على مرحّل
      expect(
        () => db.customStatement(
            'INSERT INTO move_lines (move_id, account_id, debit_minor, '
            'credit_minor, uuid) VALUES (?, ?, ?, ?, ?)',
            [moveId, cash, 1, 0, 'raw-line-3']),
        throwsA(anything),
      );
      // لا حذف سطر مرحّل
      expect(
        () => db.customStatement('DELETE FROM move_lines WHERE move_id = ?',
            [moveId]),
        throwsA(anything),
      );
      // لا حذف قيد مرحّل (05 §7-4)
      expect(
        () => db.customStatement('DELETE FROM moves WHERE id = ?', [moveId]),
        throwsA(anything),
      );
      // ولا تعديل حقوله الجوهرية (07 §1.3)
      expect(
        () => db.customStatement(
            "UPDATE moves SET narration = 'عبّث' WHERE id = ?", [moveId]),
        throwsA(anything),
      );
      // حذف المسودة بقي — مسموح (07 §1.3)
      final draftId = await db.createMoveDraft(
        journalId: journalId,
        dateText: await isoDate(db, month: 10),
        lines: [
          line(cash, debit: 5, credit: 0),
          line(withdrawals, debit: 0, credit: 5),
        ],
      );
      await db.deleteMoveDraft(draftId);
      expect(
          await (db.select(db.moves)..where((t) => t.id.equals(draftId)))
              .get(),
          isEmpty);
    });
  });

  group('العكس (س-48) — التصحيح بقيد جديد لا بتعديل', () {
    test('المرحّل يعكس بمسودة معكوسة تُرحّل بالمحرك نفسه برقم متصل',
        () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final year = await seededYear(db);
      final dateText = await isoDate(db, month: 10);
      final originalId = await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        narration: 'مسحوبات أُدخلت خطأً',
        lines: [
          line(withdrawals, debit: 70000, credit: 0),
          line(cash, debit: 0, credit: 70000),
        ],
      );
      await db.postMove(originalId);
      final reversalId = await db.createReversalDraft(originalId,
          reversalDateText: dateText);
      final reversal = await (db.select(db.moves)
            ..where((t) => t.id.equals(reversalId)))
          .getSingle();
      expect(reversal.state, 'draft');
      expect(reversal.refDocType, 'move');
      expect(reversal.refDocId, originalId);
      expect(reversal.narration, 'عكس قيد ${seqNum(year, 1)}');
      await db.postMove(reversalId);
      final posted = await (db.select(db.moves)
            ..where((t) => t.id.equals(reversalId)))
          .getSingle();
      expect(posted.number, '${seqNum(year, 2)}',
          reason: 'العكس قيد جديد برقم متصل (07 §1.9)');
      // وبعد العكس رصيدا الحسابين صفر — التوازن الحقيقي
      expect(await db.accountBalanceOf(withdrawals), 0);
      expect(await db.accountBalanceOf(cash), 0);
      // وميزان المراجعة الافتراضي متوازن
      final (debit, credit) = await db.trialBalanceTotalsOf();
      expect(debit, credit);
    });

    test('العكس يقتصر على المرحّل — مسودة ترفض', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      final dateText = await isoDate(db, month: 10);
      final draftId = await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        lines: [
          line(withdrawals, debit: 100, credit: 0),
          line(cash, debit: 0, credit: 100),
        ],
      );
      expect(
        () => db.createReversalDraft(draftId, reversalDateText: dateText),
        throwsA(anything),
      );
    });
  });

  group('الفترات (س-49) — الزمن المحاسبي (07 §1.5)', () {
    test('فترة مقفلة: المسودة تُنشأ والترحيل يرفض', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final withdrawals = await accountIdByCode(db, '321');
      // أقفل فترة يناير مباشرة (الإقفال صلاحية مدير — دفعة الإقفال
      // شاشتها؛ الفحص هنا من وجهة المحرك) — سنة البذر الديناميكية
      final year = await seededYear(db);
      final january = await (db.select(db.periods)
            ..where((t) => t.startDateText.equals('$year-01-01')))
          .getSingle();
      await (db.update(db.periods)..where((t) => t.id.equals(january.id)))
          .write(PeriodsCompanion(state: const Value('closed')));
      final moveId = await db.createMoveDraft(
        journalId: journalId,
        dateText: '$year-01-20',
        lines: [
          line(withdrawals, debit: 100, credit: 0),
          line(cash, debit: 0, credit: 100),
        ],
      );
      try {
        await db.postMove(moveId);
        fail('الفترة المقفلة يجب أن تمنع الترحيل');
      } on LedgerValidationException catch (e) {
        expect(describeMoveValidationError(e.errors.first),
            contains('مقفلة'));
      }
      final move = await (db.select(db.moves)
            ..where((t) => t.id.equals(moveId)))
          .getSingle();
      expect(move.state, 'draft', reason: 'بقيت معلقة لا مرحّلة');
      // ولا رقم صدر عن المحاولة المرفوضة (07 §1.9: العدّاد عند النجاح)
      final seqs = await db.select(db.sequences).get();
      expect(seqs, isEmpty);
    });
  });

  group('الأرصدة والميزان (س-50) — ثابت المطابقة الأول', () {
    test('رصيد الحساب من المرحّل حصراً والمسودات لا تنعكس', () async {
      final journalId = await generalJournalId(db);
      final cash = await accountIdByCode(db, '1111');
      final sales = await accountIdByCode(db, '411');
      final withdrawals = await accountIdByCode(db, '321');
      // بيع نقدي مبسط: صندوق مدين / مبيعات دائن 100,000
      final dateText = await isoDate(db, month: 10);
      final saleId = await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        lines: [
          line(cash, debit: 100000, credit: 0),
          line(sales, debit: 0, credit: 100000),
        ],
      );
      // ومسحوبات 40,000 — مسودة فقط (لا تُرحّل بعد)
      await db.createMoveDraft(
        journalId: journalId,
        dateText: dateText,
        lines: [
          line(withdrawals, debit: 40000, credit: 0),
          line(cash, debit: 0, credit: 40000),
        ],
      );
      await db.postMove(saleId);
      expect(await db.accountBalanceOf(cash), 100000,
          reason: 'المسودة غير المرحّلة لا تدخل الرصيد');
      expect(await db.accountBalanceOf(sales), 100000);
      expect(await db.accountBalanceOf(withdrawals), 0,
          reason: 'مسحوبات مسودة لم ترحل');
      final (debit, credit) = await db.trialBalanceTotalsOf();
      expect(debit, 100000);
      expect(credit, 100000);
    });
  });

  group('ترحيلة 5→6 بقاعدة خام (F-011) — بذر القلب فوق بيانات قائمة',
      () {
    test('الترقية من v4 تمر بالخطوتين وتحفظ البيانات وتزرع القلب والمشغلات تعمل',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('diqqah_v6_mig_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dbPath = p.join(tempDir.path, 'migrate.db');
      // قاعدة v4 خام بنمط اختبار الترحيلة السابقة: items بالشكل القديم
      // (sku مفتاح أساس بلا id) وصف واحد — والبقية يبنيها createAll.
      final raw = sqlite3.open(dbPath);
      raw.execute('CREATE TABLE "items" ('
          '"sku" TEXT NOT NULL PRIMARY KEY,'
          '"name" TEXT NOT NULL,'
          '"category" TEXT NULL,'
          '"kind" TEXT NOT NULL,'
          '"base_unit_id" INTEGER NOT NULL,'
          '"purchase_price_minor" INTEGER NOT NULL,'
          '"sale_price_minor" INTEGER NOT NULL,'
          '"price_currency_id" INTEGER NOT NULL,'
          '"default_tax_id" INTEGER NULL,'
          '"is_active" INTEGER NOT NULL DEFAULT 0,'
          '"uuid" TEXT NOT NULL,'
          '"created_at" INTEGER NOT NULL DEFAULT 0,'
          '"updated_at" INTEGER NOT NULL DEFAULT 0,'
          '"is_deleted" INTEGER NOT NULL DEFAULT 0)');
      raw.execute("INSERT INTO items (sku, name, kind, base_unit_id, "
          "purchase_price_minor, sale_price_minor, price_currency_id, "
          "is_active, uuid) VALUES ('SKU-OLD', 'بضاعة قبل الترحيل', 'good', 1, "
          "250000, 275000, 1, 1, 'uuid-old-1')");
      raw.execute('PRAGMA user_version = 4');
      raw.dispose();

      final migrated = DiqqahDatabase(filePath: dbPath);
      addTearDown(migrated.close);
      await migrated.select(migrated.items).get();
      expect(migrated.schemaVersion, 21);

      // بيانات القائمة محفوظة — الترحيلة لم تلمس جداول قائمة
      final items = await migrated.select(migrated.items).get();
      expect(items, hasLength(1));
      expect(items.first.sku, 'SKU-OLD');

      // وقلب الدفتر زُرع فوقها كاملاً
      expect(await migrated.allLedgerAccounts(), hasLength(58));
      final journals = await migrated.select(migrated.journals).get();
      expect(journals, hasLength(5));
      final periods = await migrated.ledgerPeriods();
      expect(periods, hasLength(12));

      // والمُشغِّلات قائمة فعلاً — خام كالاختبار الأعلى
      final journalId = await generalJournalId(migrated);
      final cash = await accountIdByCode(migrated, '1111');
      final sales = await accountIdByCode(migrated, '411');
      await migrated.customStatement(
        'INSERT INTO moves (journal_id, date_text, state, number, uuid) '
        'VALUES (?, ?, ?, ?, ?)',
        [journalId, '2026-10-30', 'draft', '', 'mig-raw-1'],
      );
      final moveId = (await migrated
              .customSelect('SELECT MAX(id) AS m FROM moves').getSingle())
          .data['m'] as int;
      for (final pair in [
        [cash, 10, 0],
        [sales, 0, 5],
      ]) {
        await migrated.customStatement(
          'INSERT INTO move_lines (move_id, account_id, debit_minor, '
          'credit_minor, uuid) VALUES (?, ?, ?, ?, ?)',
          [moveId, pair[0], pair[1], pair[2], 'mig-line-${pair[0]}'],
        );
      }
      expect(
        () => migrated.customStatement(
            "UPDATE moves SET state = 'posted' WHERE id = ?", [moveId]),
        throwsA(anything),
        reason: 'حاجز التوازن وُلد مع الترحيلة لا مع التثبيت الجديد حصراً',
      );
    });
  });
}
