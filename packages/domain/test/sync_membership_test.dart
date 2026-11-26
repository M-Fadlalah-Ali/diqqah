import 'dart:math';

import 'package:test/test.dart';

import 'package:diqqah_domain/diqqah_domain.dart';

/// اختبارات د5 الشطر الثاني — رمز الانضمام (م-32: المدير يولده من
/// جهاز موثوق، استهلاك واحد، صلاحية 24 ساعة) والجهاز المفقود (م-33:
/// إبطال فوري وأحداثه append-only بلا حذف وخيار «مسح عند أول اتصال»)
/// نص خارطة م4 §46 بكلمة المالك «تابع مع د5».
void main() {
  final base = DateTime.utc(2026, 11, 19, 10, 0, 0);

  group('شكل الرمز والتطبيع — أبجدية بلا ملتبس', () {
    test('الأبجدية بلا 0/O ولا 1/I/L — وقابلة للقراءة باليد', () {
      expect(joinCodeAlphabet.contains('0'), isFalse);
      expect(joinCodeAlphabet.contains('O'), isFalse);
      expect(joinCodeAlphabet.contains('1'), isFalse);
      expect(joinCodeAlphabet.contains('I'), isFalse);
      expect(joinCodeAlphabet.contains('L'), isFalse);
      expect(joinCodeAlphabet.split('').toSet(),
          hasLength(joinCodeAlphabet.length));
    });

    test('التطبيع يجرد الفواصل والمسافات ويرفع الحالة', () {
      expect(normalizeJoinCode('abcd-efgh'), 'ABCDEFGH');
      expect(normalizeJoinCode(' ab 2C - DeFg '), 'AB2CDEFG');
      // الأبجدية بلا I فالرمز بحرفها فاسد الشكل بعد التطبيع
      expect(isValidJoinCodeShape(normalizeJoinCode('ai2c-defg')), isFalse);
    });

    test('الصيغة البشرية «XXXX-XXXX» — والفاسد الشكل يرمي لا يُصاغ', () {
      expect(formatJoinCode('ABCD2345'), 'ABCD-2345');
      expect(
          () => formatJoinCode('SHORT'),
          throwsA(isA<FormatException>()));
      // والملتبس المستبعَد (1) فاسد الشكل لا يُصاغ
      expect(
          () => formatJoinCode('ABCD1234'),
          throwsA(isA<FormatException>()));
    });

    test('الرمز المُصدر سليم الشكل بطوله المعتاد', () {
      final book = JoinCodeBook();
      final record = book.issue(
          issuedByDeviceId: 'd-manager',
          nowUtc: base,
          issuedByManager: true);
      expect(record.code, hasLength(joinCodeLength));
      expect(isValidJoinCodeShape(record.code), isTrue);
      expect(record.expiresAtUtc.difference(record.issuedAtUtc),
          joinCodeValidity);
      expect(record.issuedByDeviceId, 'd-manager');
    });
  });

  group('الإصدار نص م-32 — المدير من جهاز موثوق', () {
    test('بغير المدير يُرفض صوتاً مفهرساً — لا رمز انضمام بيد غيره', () {
      final book = JoinCodeBook();
      expect(
        () => book.issue(
            issuedByDeviceId: 'd-any', nowUtc: base, issuedByManager: false),
        throwsA(isA<JoinCodeException>()
            .having((e) => e.toString(), 'msg', contains('DQ-1116'))),
      );
      expect(book.records, isEmpty);
    });

    test('بلا جهاز مُصدر يُرفض — «من جهاز موثوق» حرفاً', () {
      final book = JoinCodeBook();
      expect(
        () => book.issue(
            issuedByDeviceId: '   ', nowUtc: base, issuedByManager: true),
        throwsA(isA<JoinCodeException>()),
      );
    });

    test('حتمية الاختبار: بذرة واحدة رمز واحد — وتفرد الرمز بالكتاب', () {
      final a = JoinCodeBook().issue(
          issuedByDeviceId: 'd1',
          nowUtc: base,
          issuedByManager: true,
          random: Random(20261119));
      final b = JoinCodeBook().issue(
          issuedByDeviceId: 'd1',
          nowUtc: base,
          issuedByManager: true,
          random: Random(20261119));
      expect(a.code, b.code);
      // والكتاب الواحد لا يحمل رمزين متطابقين مهما طال الإصدار
      final book = JoinCodeBook();
      for (var i = 0; i < 50; i++) {
        book.issue(
            issuedByDeviceId: 'd1',
            nowUtc: base.add(Duration(minutes: i)),
            issuedByManager: true,
            random: Random(i));
      }
      expect(book.records.map((r) => r.code).toSet(),
          hasLength(book.records.length));
    });
  });

  group('الاستهلاك نص م-32 — استهلاك واحد وصلاحية 24 ساعة', () {
    JoinCodeBook seeded() {
      final book = JoinCodeBook();
      book.issue(
          issuedByDeviceId: 'd-manager',
          nowUtc: base,
          issuedByManager: true);
      return book;
    }

    test('الاستهلاك الصحيح داخل الصلاحية يسجل مَن ومتى', () {
      final book = seeded();
      final code = book.records.single.code;
      final consumed = book.consume(
          code: code, consumingDeviceId: 'd-new', nowUtc: base.add(const Duration(hours: 1)));
      expect(consumed.consumedByDeviceId, 'd-new');
      expect(consumed.consumedAtUtc, base.add(const Duration(hours: 1)));
    });

    test('الرمز المجهول والفاسد الشكل يُرفضان', () {
      final book = seeded();
      expect(
        () => book.consume(
            code: 'ZZZZ9999', consumingDeviceId: 'd-new', nowUtc: base),
        throwsA(isA<JoinCodeException>()
            .having((e) => e.toString(), 'msg', contains('مجهول'))),
      );
      expect(
        () => book.consume(
            code: 'أبجد', consumingDeviceId: 'd-new', nowUtc: base),
        throwsA(isA<JoinCodeException>()
            .having((e) => e.toString(), 'msg', contains('DQ-1116'))),
      );
    });

    test('استهلاك واحد حرفاً: الثاني مرفوض حتى داخل الصلاحية', () {
      final book = seeded();
      final code = book.records.single.code;
      book.consume(
          code: code,
          consumingDeviceId: 'd-first',
          nowUtc: base.add(const Duration(minutes: 5)));
      expect(
        () => book.consume(
            code: code,
            consumingDeviceId: 'd-second',
            nowUtc: base.add(const Duration(hours: 1))),
        throwsA(isA<JoinCodeException>()
            .having((e) => e.toString(), 'msg', contains('مستهلك'))),
      );
    });

    test('الصلاحية 24 ساعة حرفاً: لحظة الانتهاء تجوز وما بعدها رفض', () {
      final book = seeded();
      final code = book.records.single.code;
      // لحظة الانتهاء ذاتها تجوز — الحكم حتى نهاية الساعة الرابعة والعشرين
      book.consume(
          code: code,
          consumingDeviceId: 'd-edge',
          nowUtc: base.add(joinCodeValidity));
      // ورمز آخر ما بعد الانتهاء رفض صريح
      final book2 = seeded();
      final code2 = book2.records.single.code;
      expect(
        () => book2.consume(
            code: code2,
            consumingDeviceId: 'd-late',
            nowUtc: base.add(joinCodeValidity).add(const Duration(seconds: 1))),
        throwsA(isA<JoinCodeException>()
            .having((e) => e.toString(), 'msg', contains('صلاحيته'))),
      );
    });

    test('بلا جهاز مستهلك يُرفض', () {
      final book = seeded();
      expect(
        () => book.consume(
            code: book.records.single.code,
            consumingDeviceId: '',
            nowUtc: base),
        throwsA(isA<JoinCodeException>()),
      );
    });

    test('كتاب JSON: الجولة تحفظ التاريخ — والفساد يفشل مقفلاً لا '
        'سجلاً فارغاً متسامحاً', () {
      final book = seeded();
      book.consume(
          code: book.records.single.code,
          consumingDeviceId: 'd-new',
          nowUtc: base.add(const Duration(minutes: 2)));
      final restored = JoinCodeBook.fromJson(book.toJson());
      expect(restored.records.single.isConsumed, isTrue);
      expect(restored.records.single.consumedByDeviceId, 'd-new');
      // الفساد استثناء صوت — الأمن يفشل مقفلاً
      expect(() => JoinCodeBook.fromJson('نص فاسد'),
          throwsA(isA<JoinCodeException>()));
      expect(() => JoinCodeBook.fromJson('{"records": [5]}'),
          throwsA(isA<JoinCodeException>()));
      expect(
          () => JoinCodeBook.fromJson(
              '{"records": [{"code":"AB12CD34","issued":"باد","expires":"باد","issuedBy":"d"}]}'),
          throwsA(isA<JoinCodeException>()));
    });
  });

  group('سجل الأجهزة نص م-33 — إبطال فوري وتاريخ باقٍ بلا حذف', () {
    test('الانضمام بالتسجيل بعد استهلاك الرمز — والمكرر بهدوء عرف س-23', () {
      final reg = SyncDeviceRegistry();
      reg.register(deviceId: 'd-1', atUtc: base, prefix: 'ج1');
      expect(reg.byId('d-1')!.status, SyncDeviceStatus.active);
      expect(reg.byId('d-1')!.joinedAtUtc, base);
      expect(reg.byId('d-1')!.prefix, 'ج1');
      // العودة المطابقة بلا صفين
      reg.register(deviceId: 'd-1', atUtc: base.add(const Duration(hours: 1)));
      expect(reg.devices, hasLength(1));
      expect(reg.byId('d-1')!.joinedAtUtc, base,
          reason: 'لحظة الانضمام الأولى باقية');
    });

    test('الإبطال فوري — والصف يبقى بتاريخه كاملاً: عقد «لا حذف تاريخ» '
        'نص م-33 حرفاً', () {
      final reg = SyncDeviceRegistry();
      reg.register(deviceId: 'd-1', atUtc: base);
      final revokedAt = base.add(const Duration(days: 3));
      final revoked = reg.revoke(
          deviceId: 'd-1', atUtc: revokedAt, reason: 'هاتف مفقود');
      expect(revoked.status, SyncDeviceStatus.revoked);
      expect(revoked.revokedAtUtc, revokedAt);
      expect(revoked.joinedAtUtc, base,
          reason: 'تاريخ الانضمام باقٍ بعد الإبطال نص م-33');
      expect(revoked.revokeReason, 'هاتف مفقود');
      // ولا API حذف في السجل أصلاً — الصف باقٍ
      expect(reg.byId('d-1'), isNotNull);
      expect(reg.devices, hasLength(1));
    });

    test('الجهاز المُبطَل لا يعود بالتسجيل المكرر — DQ-1117 وإعادة '
        'الثقة قرار مدير صريح', () {
      final reg = SyncDeviceRegistry();
      reg.register(deviceId: 'd-1', atUtc: base);
      reg.revoke(deviceId: 'd-1', atUtc: base.add(const Duration(hours: 1)));
      expect(
        () => reg.register(deviceId: 'd-1', atUtc: base.add(const Duration(hours: 2))),
        throwsA(isA<SyncDeviceRevokedException>()
            .having((e) => e.toString(), 'msg', contains('DQ-1117'))),
      );
    });

    test('الإبطال إبطالاً متكرراً يحفظ أول لحظة — رتابة نمط recordSuccess', () {
      final reg = SyncDeviceRegistry();
      reg.register(deviceId: 'd-1', atUtc: base);
      reg.revoke(deviceId: 'd-1', atUtc: base.add(const Duration(hours: 1)));
      final again = reg.revoke(
          deviceId: 'd-1',
          atUtc: base.add(const Duration(days: 2)),
          reason: 'تأكيد ثانٍ');
      expect(again.revokedAtUtc, base.add(const Duration(hours: 1)));
      expect(again.revokeReason, 'تأكيد ثانٍ');
    });

    test('إبطال جهاز غير مسجل رفض صوتي', () {
      final reg = SyncDeviceRegistry();
      expect(() => reg.revoke(deviceId: 'd-ghost', atUtc: base),
          throwsA(isA<FormatException>()));
    });

    test('علم «مسح عند أول اتصال» على المُبطَل حصراً — نص م-33', () {
      final reg = SyncDeviceRegistry();
      reg.register(deviceId: 'd-1', atUtc: base);
      expect(() => reg.markWipeOnFirstContact('d-1'),
          throwsA(isA<FormatException>()));
      reg.revoke(deviceId: 'd-1', atUtc: base.add(const Duration(hours: 1)));
      final flagged = reg.markWipeOnFirstContact('d-1');
      expect(flagged.wipeOnFirstContact, isTrue);
    });

    test('إعادة الثقة الصريحة تعيد النشاط وتنطفئ العلم القديم', () {
      final reg = SyncDeviceRegistry();
      reg.register(deviceId: 'd-1', atUtc: base);
      reg.revoke(deviceId: 'd-1', atUtc: base.add(const Duration(hours: 1)));
      reg.markWipeOnFirstContact('d-1');
      final trusted = reg.retrust(
          deviceId: 'd-1', atUtc: base.add(const Duration(days: 1)));
      expect(trusted.status, SyncDeviceStatus.active);
      expect(trusted.wipeOnFirstContact, isFalse);
      expect(trusted.joinedAtUtc, base,
          reason: 'تاريخ الانضمام الأصلي باقٍ');
      expect(reg.firstContactVerdict('d-1'), FirstContactVerdict.allow);
    });

    test('حكم أول اتصال — الأوجه الأربعة بعقد F-136', () {
      final reg = SyncDeviceRegistry();
      expect(reg.firstContactVerdict('d-ghost'), FirstContactVerdict.refuse,
          reason: 'المجهول رفض — الانضمام برمز انضمام لا باتصال');
      reg.register(deviceId: 'd-active', atUtc: base);
      expect(reg.firstContactVerdict('d-active'),
          FirstContactVerdict.allow);
      reg.register(deviceId: 'd-revoked', atUtc: base);
      reg.revoke(deviceId: 'd-revoked', atUtc: base.add(const Duration(hours: 1)));
      expect(reg.firstContactVerdict('d-revoked'),
          FirstContactVerdict.refuse);
      reg.register(deviceId: 'd-wipe', atUtc: base);
      reg.revoke(deviceId: 'd-wipe', atUtc: base.add(const Duration(hours: 1)));
      reg.markWipeOnFirstContact('d-wipe');
      expect(reg.firstContactVerdict('d-wipe'),
          FirstContactVerdict.refuseAndWipe);
    });

    test('سجل JSON: الجولة تحفظ الأوجه — والفساد يفشل مقفلاً بنمط '
        'الكتاب (سجل الإبطال حماية فلا إسقاط صامت)', () {
      final reg = SyncDeviceRegistry();
      reg.register(deviceId: 'd-1', atUtc: base, prefix: 'ج2');
      reg.register(deviceId: 'd-2', atUtc: base.add(const Duration(minutes: 30)));
      reg.revoke(deviceId: 'd-2', atUtc: base.add(const Duration(hours: 1)));
      reg.markWipeOnFirstContact('d-2');
      final restored = SyncDeviceRegistry.fromJson(reg.toJson());
      expect(restored.byId('d-1')!.prefix, 'ج2');
      expect(restored.byId('d-2')!.status, SyncDeviceStatus.revoked);
      expect(restored.byId('d-2')!.wipeOnFirstContact, isTrue);
      expect(() => SyncDeviceRegistry.fromJson('فاسد'),
          throwsA(isA<SyncDeviceRevokedException>()));
      expect(() => SyncDeviceRegistry.fromJson('{"devices": [{"status": "active"}]}'),
          throwsA(isA<SyncDeviceRevokedException>()),
          reason: 'صف بلا معرف جهاز فاسد جوهرياً');
    });
  });

  test('الرموز الثلاثة مفهرسة بالسجل وخريطة الاستثناءات — عقد الفهرسة', () {
    expect(dqCodeForDomainError(const JoinCodeException('x')), 'DQ-1116');
    expect(
        dqCodeForDomainError(const SyncDeviceRevokedException('x')),
        'DQ-1117');
    expect(diqqahErrorCodeOf('DQ-1116')!.title, 'رمز الانضمام مرفوض');
    expect(diqqahErrorCodeOf('DQ-1117')!.title, 'جهاز مُبطَل يحاول المزامنة');
    for (final code in ['DQ-1116', 'DQ-1117', 'DQ-1118']) {
      expect(diqqahErrorCodes.where((e) => e.code == code), hasLength(1));
    }
  });
}
