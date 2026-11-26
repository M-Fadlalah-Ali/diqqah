// اختبارات p3 (س146 — خط التشفير المرحلة الثالثة): إحكام سجلي
// الأحداث والأخطاء — الختم قبل الكتابة، حاجزا الإلحاق الرباعي
// (append-only عتاداً لا عادة)، ختم سجلات ما قبل v28 عند الترقية،
// والتوافق الرجعي بقراءة الخام، والتلف المعبوث يُعلن لا يفسد صامتاً.
import 'dart:io';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// س216: عزل الخلفية يغلف أخطاء عبور العزل بDriftRemoteException
/// (سلوك drift الموثق بعزل المحرك createInBackground) — فالتحقق
/// بالسبب الجذري مهما كان الغلاف، والقاعدة الملفية بعزلها الخلفي
/// والإنتارية بأصلها (عرف س165 الديناميكي).
Object rootCauseOf(Object e) =>
    e is DriftRemoteException ? e.remoteCause : e;

/// قاعدة ملف كاملة المخطط مغلقة — نمط حارس الترقية في
/// upgrade_snapshot_test (تخفيض user_version يحاكي قاعدة إصدار أقدم).
/// ثم زرع سجلَي حدث وخطأ خامين (نص صريح كما كانت v27 تكتبه) قبل
/// الترقية، ليحكم الاختبار الختم التلقائي بالترحيلة ذاتها.
void main() {
  group('الختم قبل الكتابة — قاعدة جديدة v28', () {
    test('حدث النظام يُختم: الخام dq3log1: والفك يعيد الحمولة', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();

      await db.recordSystemEvent('p3_probe',
          payload: {'kind': 'probe', 'amount_minor': 4242});

      final raw = await db.customSelect(
              "SELECT payload FROM events WHERE action = 'p3_probe'")
          .getSingle();
      final stored = raw.data['payload'] as String;
      expect(stored.startsWith(LogCipher.envelopePrefix), isTrue,
          reason: 'بلا ختم لا معنى للإحكام — والبادئة عقد الغلاف');
      expect(stored.contains('amount_minor'), isFalse,
          reason: 'النص الصريح القديم لا يبقى بالقاعدة');
      final opened = await db.openLogText(stored);
      expect(opened, contains('4242'));
    });

    test('أحداث المستندات (الاستيراد) تُختم بالنمط ذاته', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();

      // recordSystemEvent هو المنفذ الموحد لأحداث النظام — وأحداث
      // المستندات تمر بجلسة الختم نفسها (كتسبيط recordSystemEvent
      // ومواضع الحمولة الخمسة عشر). الدليل هنا حدث نظام بحمولة JSON
      // يحاكي بنية import_performed.
      await db.recordSystemEvent('import_performed',
          payload: {'unit': 'parties', 'rows': 3, 'created': 3});
      final raw = await db.customSelect(
              "SELECT payload FROM events WHERE action='import_performed'")
          .getSingle();
      expect((raw.data['payload'] as String)
          .startsWith(LogCipher.envelopePrefix), isTrue);
    });

    test('logError يختم الرسالة والسياق والرمز يبقى خاماً', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();

      await db.logError(
          code: 'DQ-0201', message: 'رصيد سالب مرفوض', context: 'invoice.post');

      final raw = await db.customSelect(
              'SELECT code, message, context FROM error_log LIMIT 1')
          .getSingle();
      expect(raw.data['code'], 'DQ-0201',
          reason: 'الرمز خام للفهرسة والعرض بلا فك');
      final msg = raw.data['message'] as String;
      final ctx = raw.data['context'] as String;
      expect(msg.startsWith(LogCipher.envelopePrefix), isTrue);
      expect(ctx.startsWith(LogCipher.envelopePrefix), isTrue);
      expect(msg.contains('رصيد'), isFalse);
      // والقراءة للعرض تفك شفافة.
      final rows = await db.recentErrors();
      expect(rows.first['message'], 'رصيد سالب مرفوض');
      expect(rows.first['context'], 'invoice.post');
    });

    test('الملح يُزرع مرة ويُعاد كما هو — وتفرّق الأجهزة محفوظ', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      final s1 = await db.p3LogSalt();
      final s2 = await db.p3LogSalt();
      expect(s1, s2);
      expect(s1.length, 32, reason: '16 بايتة hex');
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(s1), isTrue);
    });

    test('سياق حكما متطابقان لا يظهر بالخام نصاً واحداً', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.recordSystemEvent('p3_probe', payload: {'n': 1});
      await db.recordSystemEvent('p3_probe', payload: {'n': 1});
      final rows = await db.customSelect(
              "SELECT payload FROM events WHERE action='p3_probe'")
          .get();
      expect(rows.length, 2);
      expect(rows.first.data['payload'],
          isNot(rows.last.data['payload']),
          reason: 'نونس لكل سجل — بند IV الفريد بالوثيقة');
    });
  });

  group('حاجزا الإلحاق الرباعي — append-only عتاداً (p3)', () {
    test('UPDATE على الأحداث مرفوض بأمر صريح', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.recordSystemEvent('p3_probe', payload: {'n': 1});
      await expectLater(
        db.customStatement("UPDATE events SET action = 'tampered'"),
        throwsA(isA<SqliteException>()),
      );
      final raw = await db.customSelect(
              "SELECT action FROM events WHERE action='p3_probe'")
          .get();
      expect(raw.length, 1, reason: 'الصف سليم لم يُمس');
    });

    test('DELETE على الأحداث مرفوض', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.recordSystemEvent('p3_probe', payload: {'n': 1});
      await expectLater(
        db.customStatement('DELETE FROM events'),
        throwsA(isA<SqliteException>()),
      );
      final cnt = await db
          .customSelect('SELECT COUNT(*) c FROM events')
          .getSingle();
      expect(cnt.data['c'], 1);
    });

    test('UPDATE وDELETE على سجل الأخطاء مرفوضان', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.logError(code: 'DQ-0999', message: 'سجل p3');
      await expectLater(
        db.customStatement(
            "UPDATE error_log SET message = 'عبث'"),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        db.customStatement('DELETE FROM error_log'),
        throwsA(isA<SqliteException>()),
      );
      expect(await db.errorLogCount(), 1);
    });

    test('الشرائب الأربع قائمة بsqlite_master بأسمائها', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      final names = (await db.customSelect(
              "SELECT name FROM sqlite_master WHERE type='trigger' "
              "AND name LIKE 'trg_%no_%'")
          .get())
          .map((r) => r.data['name'] as String)
          .toSet();
      expect(names, containsAll(<String>[
        'trg_events_no_update',
        'trg_events_no_delete',
        'trg_error_log_no_update',
        'trg_error_log_no_delete',
      ]));
    });

    test('الإسقاط الكامل للجدول يبقى ممكناً (اختبار س107 القائم)',
        () async {
      // DROP TABLE لا يرمي حوافز UPDATE/DELETE (DDL لا DML) —
      // وعقد «أقصى جهد» بس107 يعتمد عليه، فلا حاجز يكسر العقد.
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.logError(code: 'DQ-0999', message: 'قبل السقوط');
      await db.customStatement('DROP TABLE error_log');
      await db.logError(code: 'DQ-0999', message: 'بعد السقوط');
    });
  });

  group('الترقية 27→28 — ختم القائمة وإحكام العتاد', () {
    test('سجلات v27 الخام تُختم تلقائياً بالترحيلة وتُقرأ بعدها',
        () async {
      final tmp = Directory.systemTemp.createTempSync('diqqah_p3_upg');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final path = '${tmp.path}/upg.db';

      // (1) قاعدة بملف كامل المخطط، ثم خفض الإصدار لتحاكي v27.
      final seed = DiqqahDatabase(filePath: path);
      await seed.deviceId();
      await seed.close();
      final raw = sqlite3.open(path);
      try {
        raw.execute('PRAGMA user_version = 27');
        // (2) زرع سجلَين خامين نصاً صريحاً كما كانت v27 تكتبهما —
        // SQL خام قبل إعادة الفتح فلا ختم يسبقه (مسار الاختبار حصراً).
        raw.execute(
            "INSERT INTO events (event_at, user_id, device_id, "
            "entity_type, entity_id, action, payload, uuid, "
            "created_at, updated_at, is_deleted) VALUES ("
            "1700000000000, NULL, 'seed-device', 'system', NULL, "
            "'p3_pre_upgrade', '{\"v\":27}', 'uuid-legacy-1', 0, 0, 0)");
        raw.execute(
            "INSERT INTO error_log (code, message, context, created_at) "
            "VALUES ('DQ-0999', 'خطأ ما قبل v28', 'legacy', 1700000000000)");
      } finally {
        raw.close();
      }

      // (3) فتح بإصدار 28: الترحيلة تختم الخام ثم ترفع الحواجز.
      final db = DiqqahDatabase(filePath: path);
      addTearDown(db.close);
      final probe = await db.customSelect(
              "SELECT payload FROM events WHERE action='p3_pre_upgrade'")
          .getSingle();
      final stored = probe.data['payload'] as String;
      expect(stored.startsWith(LogCipher.envelopePrefix), isTrue,
          reason: 'الترحيلة ختمت سجل v27 الخام موقعياً');
      expect(stored.contains('"v":27'), isFalse);
      final opened = await db.openLogText(stored);
      expect(opened, contains('"v":27'));

      final errRows = await db.recentErrors();
      expect(errRows.first['message'], 'خطأ ما قبل v28');
      expect(errRows.first['context'], 'legacy');
      final errRaw = await db.customSelect(
              'SELECT message FROM error_log LIMIT 1')
          .getSingle();
      expect((errRaw.data['message'] as String)
          .startsWith(LogCipher.envelopePrefix), isTrue);

      // (4) والحواجز حية بعد الترقية — UPDATE بعد الختم مرفوض.
      await expectLater(
        db.customStatement("UPDATE events SET action='tampered' "
            "WHERE action='p3_pre_upgrade'"),
        throwsA(predicate((Object e) =>
            rootCauseOf(e) is SqliteException)),
      );
    });

    test('الترحيلة آمنة التكرار: فتح ثانٍ على نفس الملف لا يختم مرتين',
        () async {
      final tmp = Directory.systemTemp.createTempSync('diqqah_p3_idem');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final path = '${tmp.path}/idem.db';

      // قاعدة v27 بختم سجل خام واحد، ثم ترقية ثم فتح ثانٍ.
      final seed = DiqqahDatabase(filePath: path);
      await seed.deviceId();
      await seed.close();
      final raw = sqlite3.open(path);
      try {
        raw.execute('PRAGMA user_version = 27');
        raw.execute(
            "INSERT INTO events (event_at, user_id, device_id, "
            "entity_type, entity_id, action, payload, uuid, "
            "created_at, updated_at, is_deleted) VALUES ("
            "1700000000000, NULL, 'seed-device', 'system', NULL, "
            "'p3_idem', '{\"n\":7}', 'uuid-legacy-2', 0, 0, 0)");
      } finally {
        raw.close();
      }

      final db = DiqqahDatabase(filePath: path);
      await db.customSelect('SELECT 1').get();
      final first = await db.customSelect(
              "SELECT payload FROM events WHERE action='p3_idem'")
          .getSingle();
      expect((first.data['payload'] as String)
          .startsWith(LogCipher.envelopePrefix), isTrue);
      await db.close();

      // فتح ثانٍ: لا ترحيلة مادة فلا ختم ثانٍ — والصف يبقى مقروءاً.
      final db2 = DiqqahDatabase(filePath: path);
      addTearDown(db2.close);
      final second = await db2.customSelect(
              "SELECT payload FROM events WHERE action='p3_idem'")
          .getSingle();
      expect(second.data['payload'], first.data['payload'],
          reason: 'التخمين حرفاً: الترحيلة لم تعمل ثانية فلم يتغير الغلاف');
      expect(await db2.openLogText(second.data['payload'] as String),
          contains('"n":7'));
    });
  });

  group('المسارات القائمة فوق السجل المختوم', () {
    test('قارئ الاستيراد importEventsSince يفك الحمولة شفافة', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.recordSystemEvent('import_performed',
          payload: {'unit': 'parties', 'rows': 5, 'created': 4, 'skipped': 1});
      final since = await db.importEventsSince(0);
      expect(since.length, 1);
      expect(since.first.unit, 'parties');
      expect(since.first.rows, 5);
      expect(since.first.partiesCreated, 4);
      expect(since.first.partiesSkipped, 1);
    });

    test('حمولة معبوثة بالوسم تعامل كالغائبة — D-169 لا فساد صامت',
        () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.recordSystemEvent('import_performed',
          payload: {'unit': 'items', 'rows': 2});
      // عبث مباشر بالقاعدة عبر SQL خام: نسخ الغلاف وقطع بايتاته —
      // القارئ يبلع التلف (DQ-1108) ويعيد مجاميع الصفر لا ينهار.
      final sealedRow = await db.customSelect(
              "SELECT id, payload FROM events WHERE action='import_performed'")
          .getSingle();
      final id = sealedRow.data['id'] as int;
      // لا UPDATE ممكن بعد الحاجز — فالتلف يُزرع بجدول شاهد منفصل:
      // نحذف الجدول ونعيد إنشاءه بلا حوافز لنزرع صف التلف (مسار
      // الاختبار حصراً — التطبيق لا يفعل ذلك أبداً).
      await db.customStatement('DROP TRIGGER trg_events_no_update');
      final envelope = sealedRow.data['payload'] as String;
      final broken = '${envelope.substring(0, envelope.length - 8)}AAAAAA==';
      await db.customStatement(
          'UPDATE events SET payload = ? WHERE id = ?', [broken, id]);
      final since = await db.importEventsSince(0);
      expect(since.length, 1);
      expect(since.first.rows, 0, reason: 'الفاسد كالغائب لا فساد صامت');
      // وإعادة الحاجز لما كان — فالاختبار لا يترك قاعدة مكسورة.
      await db.customStatement(_restoreGuardSql());
    });

    test('خطأ معبوث بالوسم يعرض برسالة DQ-1108 لا استثناء', () async {
      final db = DiqqahDatabase.inMemorySyncClose();
      addTearDown(db.close);
      await db.deviceId();
      await db.logError(code: 'DQ-0999', message: 'رسالة حقيقية');
      await db.customStatement('DROP TRIGGER trg_error_log_no_update');
      final rawRow = await db
          .customSelect('SELECT id, message FROM error_log')
          .getSingle();
      final envelope = rawRow.data['message'] as String;
      final broken = '${envelope.substring(0, envelope.length - 8)}AAAAAA==';
      await db.customStatement(
          'UPDATE error_log SET message = ? WHERE id = ?',
          [broken, rawRow.data['id'] as int]);
      final rows = await db.recentErrors();
      expect(rows.first['message'], contains('DQ-1108'),
          reason: 'التلف معلن للمستخدم لا فساد صامت ولا انهيار شاشة');
      await db.customStatement(_restoreErrorGuardSql());
    });
  });
}

/// إعادة إنشاء حاجز الأحداث بعد اختبار العبث — بنص الترحيلة حرفاً.
String _restoreGuardSql() =>
    "CREATE TRIGGER trg_events_no_update BEFORE UPDATE ON events BEGIN "
    "SELECT RAISE(ABORT, 'سجل الأحداث إلحاقي — التعديل مرفوض (DQ-1119)'); END";

/// إعادة إنشاء حاجز سجل الأخطاء بعد اختبار العبث — بنص الترحيلة حرفاً.
String _restoreErrorGuardSql() =>
    "CREATE TRIGGER trg_error_log_no_update BEFORE UPDATE ON error_log BEGIN "
    "SELECT RAISE(ABORT, 'سجل الأخطاء إلحاقي — التعديل مرفوض (DQ-1121)'); END";
