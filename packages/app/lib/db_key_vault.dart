import 'dart:typed_data' show Uint8List;

import 'package:diqqah_domain/diqqah_domain.dart'
    show BackupCipher, BackupLock, BackupVaultKeys;
import 'package:diqqah_storage/diqqah_storage.dart'
    show DatabaseKeyVault, dbKeyFromHex, dbKeyHexOf, generateDbKey;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// خزنة مفتاح القاعدة على الجهاز — F-150/D-210 P0-ب (س148).
///
/// المفتاح العشوائي 256-bit يولَّد مرة واحدة عند أول فتح ويُحفظ في خزنة
/// الجهاز لا في الكود (F-150 نص الـSRS): أندرويد EncryptedSharedPreferences
/// فوق Keystore، وويندوز DPAPI — افتراضات حزمة flutter_secure_storage
/// المستقرة 10.x على المنصتين بلا إعدادات يدوية. قرار المالك د-٣ (س147):
/// «مفتاح الخزنة وحده بالجيل الأول» — لا كلمة مستخدم في هذا الجيل (P1-أ
/// لاحقاً بتغليف المفتاح ورمز استرداد بجيل v3).
class SecureStorageKeyVault implements DatabaseKeyVault {
  /// مفتاح التخزين داخل الخزنة — لاحقة .v1 تُهيئ جيلاً للمفتاح.
  final String _storageKey;

  final FlutterSecureStorage _storage;

  /// خزنة مفتاح القاعدة — المفتاح `diqqah.db.key.v1` (P0-ب س148).
  SecureStorageKeyVault([FlutterSecureStorage? storage])
      : this._(storage, 'diqqah.db.key.v1');

  /// خزنة مفتاح الملفات المصاحبة (صور الأصناف) — P1-ب (س149/D-210):
  /// KEK مستقل بمفتاح تخزين خاص `diqqah.images.key.v1` — مفاتيح
  /// منفصلة للقاعدة والصور فاستقلال أثر كل طبقة وتدوير مستقبلي
  /// منفصل، وبذات افتراضات الخزنة المنصوية.
  SecureStorageKeyVault.forImages([FlutterSecureStorage? storage])
      : this._(storage, 'diqqah.images.key.v1');

  SecureStorageKeyVault._(FlutterSecureStorage? storage, this._storageKey)
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<Uint8List> loadOrCreateKey() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null) {
      // مفتاح قائم بالخزنة — يُعاد كما هو في كل فتح (ثبات القاعدة)،
      // وبأي صيغة شاذة رفض صوت عالٍ (dbKeyFromHex) فلا مفتاح مشوه.
      return dbKeyFromHex(existing);
    }
    // أول تشغيل: توليد عشوائي آمن وحفظ فوري في الخزنة قبل أي مساس
    // بالقاعدة — فشل الحفظ يفشل الافتتاح بدل تشفير بمفتاح لا يعاد.
    final key = generateDbKey();
    await _storage.write(key: _storageKey, value: dbKeyHexOf(key));
    return key;
  }
}

/// صندوق أسرار مجرد — فاصل اختباري فوق flutter_secure_storage:
/// الاختبارات تحقن صندوقاً بذاكرة، والإنتاج يأخذ الخزنة المنصوية.
abstract class SecureSecretsBox {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// التنفيذ المنصوي — flutter_secure_storage (Keystore أندرويد / DPAPI
/// ويندوز) بذات افتراضات P0-ب.
class SecureSecretsBoxImpl implements SecureSecretsBox {
  final FlutterSecureStorage _storage;
  SecureSecretsBoxImpl([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// أسرار قفل النسخ الاحتياطية — P1-أ (س149/D-210): كلمة المستخدم
/// الاختيارية ورمز الاسترداد يخزنان هنا كي تُكتب النسخ الجديدة بجيل
/// v3 المقفل آلياً، ويُفك نفس الجهاز نسخته صامتاً عند الاستعادة
/// (والحقل اليدوي يقبل الكلمة أو الرمز لنسخة أخرى جهازاً).
///
/// الصدق الموثق: الرمز يخزن بالخزنة كي يُعاد عرضه وينسخ نصياً —
/// فحمايته للمقفلة تظهر عند فكها على جهاز ثانٍ أو بعد نسيان الكلمة،
/// وفقد الخزنة كلها = فقد الاثنين معاً (حد د-٣ الموثق س147).
class BackupSecretsStore {
  /// مفاتيح التخزين — لاحقة .v1 تهيئ جيلاً للإدارة المستقبلية.
  static const String _passKey = 'diqqah.backup.pass.v1';
  static const String _recoveryKey = 'diqqah.backup.recovery.v1';

  final SecureSecretsBox _box;
  BackupSecretsStore({SecureSecretsBox? box})
      : _box = box ?? SecureSecretsBoxImpl();

  /// القفل المخزن — null إن لم يُعيّن أو نقص أحد السرّين (قفل نصفي
  /// لا يقبل: إما سرّان معاً أو لا قفل — فلا نسخة v3 بمادة واحدة).
  Future<BackupLock?> loadLock() async {
    final pass = await _box.read(_passKey);
    final recovery = await _box.read(_recoveryKey);
    if (pass == null || pass.isEmpty) return null;
    if (recovery == null || recovery.isEmpty) return null;
    return BackupLock(password: pass, recoveryCode: recovery);
  }

  /// حفظ القفل — فشل الكتابة يرمي (صوت عالٍ) فلا قفل ناقص يُكتب به.
  Future<void> saveLock(BackupLock lock) async {
    await _box.write(_passKey, lock.password);
    await _box.write(_recoveryKey, lock.recoveryCode);
  }

  /// إزالة القفل — النسخ الجديدة تعود لجيل v2، والمقفلة القائمة
  /// تبقى بكلمتها ورمزها (تُفك بهما لا بشيء من هذه الخزنة).
  Future<void> clearLock() async {
    await _box.delete(_passKey);
    await _box.delete(_recoveryKey);
  }
}

/// مفاتيح نسخ الخزنة — د11 (س229/D-225 الجزء الأول بكلمة المالك
/// «ابدأ د11»): جذر عشوائي 256-bit لكل جهاز يولَّد في خزنة الجهاز عند
/// أول تشغيل (Keystore أندرويد / DPAPI ويندوز — بذات افتراضات P0-ب
/// س148)، ومعه رمز استرداد بنمط v3 القائم يُطبع مرة واحدة عند أول
/// تشغيل (ويبقى قابلاً للعرض من الخزنة بعرف الصدق ذاته). النسخ غير
/// المقفلة تُكتب بجيل v4: تُفك هنا صامتاً بمفتاح هذا الجهاز، وعلى أي
/// جهاز آخر برمز الاسترداد — فسيناريو «فتح النسخة على أي جهاز» (N-005)
/// يلتئم بالرمز بلا كسر (خلاف المحضر الاستشاري المحسوم بد11).
class VaultBackupKeys {
  /// مفاتيح التخزين — لاحقة .v1 تهيئ جيلاً للإدارة المستقبلية (نمط
  /// BackupSecretsStore عينه).
  static const String _rootKey = 'diqqah.backup.root.v1';
  static const String _recoveryKey = 'diqqah.backup.recovery.v1';
  static const String _revealedKey = 'diqqah.backup.recovery.shown.v1';

  final SecureSecretsBox _box;
  VaultBackupKeys({SecureSecretsBox? box})
      : _box = box ?? SecureSecretsBoxImpl();

  /// المواد القائمة — null إن غاب أحد السرّين أو نقص (مواد نصفية لا
  /// تُعاد: النسخ تُكتب v4 بالجذر والرمز معاً أو تنخفض v2 موثقة).
  Future<BackupVaultKeys?> load() async {
    final root = await _box.read(_rootKey);
    final recovery = await _box.read(_recoveryKey);
    if (root == null || root.isEmpty) return null;
    if (recovery == null || recovery.isEmpty) return null;
    return BackupVaultKeys(
        rootKey: dbKeyFromHex(root), recoveryCode: recovery);
  }

  /// المواد حاضرة أو مولَّدة — أول تشغيل: توليد الجذر العشوائي
  /// (256-bit بنمط مفتاح القاعدة ذاته) والرمز (بنمط v3 حرفاً) وحفظهما
  /// فوراً قبل أي نسخة تُكتب بهما؛ والقائمان يُعادان كما هما (آمن
  /// التكرار — الجذر ثابت فالنسخ تُقرأ عبر الإقلاعات).
  Future<BackupVaultKeys> loadOrCreate() async {
    final existing = await load();
    if (existing != null) return existing;
    final root = generateDbKey();
    final recovery = BackupCipher.generateRecoveryCode();
    await _box.write(_rootKey, dbKeyHexOf(root));
    await _box.write(_recoveryKey, recovery);
    return BackupVaultKeys(rootKey: root, recoveryCode: recovery);
  }

  /// هل طُبع الرمز مرة واحدة عند أول تشغيل؟ — الراية بالخزنة ذاتها
  /// (لا بshared_preferences: سرٌّ فلا يخرج من الخزنة).
  Future<bool> recoveryRevealed() async {
    final flag = await _box.read(_revealedKey);
    return flag != null && flag == '1';
  }

  /// وسم الطباعة الواحدة — بعد حوار «سجّلته» حصراً فلا يعود تلقائياً.
  Future<void> markRecoveryRevealed() async {
    await _box.write(_revealedKey, '1');
  }
}
