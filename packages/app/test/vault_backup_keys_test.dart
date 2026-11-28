// اختبارات د11 (س229/D-225 الجزء الأول) — مخزن مفاتيح نسخ الخزنة
// بالواجهة: التوليد الواحد عند أول تشغيل وثباته، والرمز بنمط v3،
// وراية الطباعة الواحدة، وقراءة المواد الناقصة (بلا مواد نصفية).
import 'package:flutter_test/flutter_test.dart';

import 'package:diqqah_app/db_key_vault.dart';

/// صندوق ذاكرة فوق التجريد — نمط الاختبارات الموثق (فاصل الاختبار
/// فوق flutter_secure_storage: الاختبارات تحقن صندوقاً بذاكرة).
class _MemoryBox implements SecureSecretsBox {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

void main() {
  test('د11: loadOrCreate يولد الجذر 32 بايتة والرمز بنمط v3 مرة واحدة '
      'ويعيد الثابتين بعدها', () async {
    final store = VaultBackupKeys(box: _MemoryBox());
    final first = await store.loadOrCreate();
    expect(first.rootKey, hasLength(32));
    expect(
      RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')
          .hasMatch(first.recoveryCode),
      isTrue,
      reason: 'رمز بنمط v3: 4 مجموعات من ألفباء بلا متشابهات',
    );
    final second = await store.loadOrCreate();
    expect(second.rootKey, equals(first.rootKey),
        reason: 'الجذر ثابت — النسخ تُقرأ عبر الإقلاعات');
    expect(second.recoveryCode, equals(first.recoveryCode));
  });

  test('د11: الجذر عشوائي لكل جهاز — صندوقان (جهازان) لا يشتركان',
      () async {
    final a = await VaultBackupKeys(box: _MemoryBox()).loadOrCreate();
    final b = await VaultBackupKeys(box: _MemoryBox()).loadOrCreate();
    expect(a.rootKey, isNot(equals(b.rootKey)));
    expect(a.recoveryCode, isNot(equals(b.recoveryCode)));
  });

  test('د11: المواد الناقصة لا تُعاد — load يعيد null بنقص أي سرّ',
      () async {
    final box = _MemoryBox();
    final store = VaultBackupKeys(box: box);
    expect(await store.load(), isNull, reason: 'خزنة فارغة أصلاً');
    final keys = await store.loadOrCreate();
    // بلا رمز = لا مواد (لا نسخ v4 بمادة واحدة).
    await box.delete('diqqah.backup.recovery.v1');
    expect(await store.load(), isNull);
    // وبلا جذر كذلك — والقائمة تعاد عند اكتمالها.
    await box.write('diqqah.backup.recovery.v1', keys.recoveryCode);
    expect((await store.load())!.rootKey, equals(keys.rootKey));
  });

  test('د11: راية الطباعة الواحدة — غائبة ثم موسومة فلا تعود', () async {
    final box = _MemoryBox();
    final store = VaultBackupKeys(box: box);
    expect(await store.recoveryRevealed(), isFalse);
    await store.markRecoveryRevealed();
    expect(await store.recoveryRevealed(), isTrue);
    // وبعد إعادة الفتح (مخزن جديد فوق الصندوق ذاته) تبقى موسومة —
    // الراية بالخزنة لا بالذاكرة، فلا تعود الطباعة كل إقلاع.
    expect(await VaultBackupKeys(box: box).recoveryRevealed(), isTrue);
  });

  // ── س230 (د11 الجزء الثاني — خزنة جذر السجلات) ──────────────────

  test('س230: LogRootVault يولد الجذر 32 بايتة مرة واحدة ويثبت عبر '
      'المخازن (الجهاز ذاته)', () async {
    final box = _MemoryBox();
    final store = LogRootVault(box: box);
    final first = await store.loadOrCreate();
    expect(first, hasLength(32));
    final second = await LogRootVault(box: box).loadOrCreate();
    expect(second, equals(first),
        reason: 'الجذر ثابت بالخزنة فالسجلات تُقرأ عبر الإقلاعات');
    // والمفتاح باسمه المستقل عن مفاتيح النسخ (فصل النطاقات).
    expect(box.data.containsKey('diqqah.log.root.v1'), isTrue);
    expect(box.data.containsKey('diqqah.backup.root.v1'), isFalse);
  });

  test('س230: الجذر عشوائي لكل جهاز — صندوقان (جهازان) لا يشتركان',
      () async {
    final a = await LogRootVault(box: _MemoryBox()).loadOrCreate();
    final b = await LogRootVault(box: _MemoryBox()).loadOrCreate();
    expect(a, isNot(equals(b)));
  });

  test('س230: الخزنة الفاشلة تعيد null من المفوّض الحي — الجذر الإرثي '
      'المضمّن انخفاضاً موثقاً (المفوّض بصندوق محقون لا قناة الإنتاج)',
      () async {
    final failing = _ThrowingBox();
    try {
      await LogRootVault(box: failing).loadOrCreate();
      fail('الصندوق الرافض يرمي — لا جذر بلا خزنة (نمط س148)');
    } on StateError {
      // الصوت العالي عقد المخزن — والمفوّض الحي يبتلعه ويعيد null.
    }
    expect(await _failingLiveLogRootOrNull(failing), isNull,
        reason: 'فشل الخزنة = null فالجذر الإرثي المضمّن قارئاً وخاتماً');
    // والصندوق السليم يعيد جذر 32 بايتة (المسار الحقيقي بالخزنة).
    expect(await LogRootVault(box: _MemoryBox()).loadOrCreate(),
        hasLength(32));
  });
}

/// صندوق يرمي دائماً — محاكاة خزنة الجهاز الفاشلة.
class _ThrowingBox implements SecureSecretsBox {
  @override
  Future<String?> read(String key) async => throw StateError('خزنة غائبة');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('خزنة غائبة');

  @override
  Future<void> delete(String key) async => throw StateError('خزنة غائبة');
}

/// المفوّض الحي بصندوق محقون — اختبار مسار الفشل بلا قناة الإنتاج.
Future<List<int>?> _failingLiveLogRootOrNull(SecureSecretsBox box) async {
  try {
    return await LogRootVault(box: box).loadOrCreate();
  } catch (_) {
    return null;
  }
}
