import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:local_auth/local_auth.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'dq_log.dart';

/// بوابة الجهاز — س212 (دفعة 2 من خطة الجلسة والمستخدمين، D-215) بنقض
/// س216 لأحد قرارَي U-005 بأمر المالك («ما السبب في إبقائك على قائمة
/// الأسماء في شاشة الدخول؟»): شاشة الحالة «مقفلة خارج الجلسة» بإدخال
/// يدوي حصراً — اسمُ الدخول وكلمة المرور لا بلاطات أسماء، عرف تطبيقات
/// المصادقة الكبيرة (لا تعداد حساباتٍ من شاشة الدخول: مَن يلتقط الجهاز
/// لا يرى أصحابه ولا يستهدف كلمة أحد بعينه، ونقض بلاطات U-005 موثق
/// بworklog س216). لا بيانات خلفها ولا رئيسية ولا قوائم، والإقلاع
/// يعرضها حصراً حين الراية `session_locked` مكتوبة بapp_meta فلا ثقب
/// عودة مفتوحة بعد موت العملية (إعادة التشغيل تعيد البوابة لا الجلسة).
///
/// الأفعال الثلاثة مسارات انتقال لا حالات (D-215): القفل فتح سريع
/// لنفس المستخدم (بالبصمة إن نال)، والتبديل قفلٌ ثم دخول باسم آخر،
/// والخروج قفل بلا مستخدم مستأنف — والبوابة وجهة الأفعال الثلاثة
/// كلها والفرق بينها ما يفعله صاحب الشاشة بعدها. الفتح بتحقق الكلمة
/// حصراً (لا جلسة بلا تحقق D-100) عبر resumeSessionByLogin (س216)
/// فكل الفشل برسالة واحدة عامة «بيانات الدخول غير صحيحة» بلا تفرقة
/// بين اسم مجهول ومعطل وكلمة خاطئة، وصاحب الراية
/// `must_change_password` لا يدخل جلسه قبل كلمة جديدة بحوار غير قابل
/// للرصد (D-216 الضابط الثالث) — والراية تفنجان ثم تُزال بopenSession
/// حصراً فأي موت للعملية قبل الاكتمال يعيد البوابة لا رئيسية.
class DeviceGateScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// تكرارات الهاش لكلمة المرور الجديدة في الحوار الإلزامي —
  /// الافتراض العتبة الآمنة، والاختبارات تحقن قيماً صغيرة
  /// بنمط first_run والشاشة الإدارية الموثق.
  final int hasherIterations;

  /// يُنادى بعد إزالة الراية اكتمالاً — البوابة الإلكترونية للإقلاع
  /// تعيد بناء الجذر فتظهر الرئيسية بصاحب الجلسة الجديد.
  final VoidCallback onUnlocked;

  /// س213: حقن الاختبارات للبيومتري — «ما يُختبر هو ما يُشغّل حرفاً»
  /// (عرف saveOverride الموثق س207): التوفّر والتحقق يُحقنان فتُختبر
  /// الواجهة والآلة على المنصتين، والإنتاج بلا حقن فيمرّ بالقناة
  /// الحقيقية local_auth على أندرويد حصراً (الويندوز بلا قناة أصلاً
  /// فلا بصة عنده — الحد الصادق بالسجل).
  final Future<bool> Function()? biometricAvailability;

  /// س213: حقن نتيجة التحقق البيومتري ذاته — true: أنجز، false: رفض
  /// أو إلغاء — فالمسار الحي بلا حقن يستدعي local_auth مباشرة.
  final Future<bool> Function()? biometricAuthenticate;

  const DeviceGateScreen({
    super.key,
    required this.db,
    this.hasherIterations = PasswordHasher.secureIterations,
    required this.onUnlocked,
    this.biometricAvailability,
    this.biometricAuthenticate,
  });

  @override
  State<DeviceGateScreen> createState() => _DeviceGateScreenState();
}

class _DeviceGateScreenState extends State<DeviceGateScreen> {
  /// هل يوجد مستخدم نشط واحد على الأقل — لسان الفراغ الموحد حين لا
  /// أحد (س216: وجودُ حساباتٍ لا يعني عرضَ أسمائها — لا تعداد).
  bool? _hasActiveUsers;

  /// المستخدم المستأنف بلسان الفتح السريع — قفلُ جلسةٍ قائمة (D-215:
  /// «القفل فتح سريع لنفس المستخدم») يُقرأ بالمفتاح current_user_id
  /// حصراً لا بتصفير الأسماء، فالبصمة للمعلق ذاته ولا شيء يظهر
  /// عن غيره من الحسابات.
  AppUser? _resumable;
  final TextEditingController _login = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  /// س213: توفّر البيومتري على الجهاز — أندرويد حصراً بحسّاسَي
  /// local_auth (مدعوم وقابل للفحص)، والاختبارات بالحقن.
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _checkBiometric();
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    bool available = false;
    final probe = widget.biometricAvailability;
    try {
      if (probe != null) {
        available = await probe();
      } else if (Platform.isAndroid) {
        final auth = LocalAuthentication();
        available = await auth.isDeviceSupported() &&
            await auth.canCheckBiometrics;
      }
    } on MissingPluginException {
      available = false;
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  /// قراءة واحدة عند الفتح — المستأنف بالمفتاح لا بتصفير قائمة،
  /// ووجودُ نشطٍ واحد محسوباً للسان الفراغ. قارئة واحدة بلا تدفق حي
  /// ولا مؤقتات (درس CI الموثق س212).
  Future<void> _reload() async {
    final all = await widget.db.select(widget.db.appUsers).get();
    final resumableId = await widget.db.currentUserId();
    AppUser? resumable;
    for (final u in all) {
      if (u.id == resumableId &&
          u.isActive &&
          !u.isDeleted) {
        resumable = u;
      }
    }
    final hasActive = all.any((u) => u.isActive && !u.isDeleted);
    if (!mounted) return;
    setState(() {
      _hasActiveUsers = hasActive;
      _resumable = resumable;
      _error = null;
    });
  }

  /// الفتح — الانتقال مقفلة→نشطة بنصفَيه الموثقين بالتخزين:
  /// resumeSessionByLogin بالتحقق حصراً فلا جلسة بلا كلمة (س216)،
  /// ثم الحوار الإلزامي لصاحب الراية (غير قابل للرصد — لا يُعاد منه
  /// إلا بنجاح)، ثم openSession إزالة الراية فلا ثقب عودة بكل خطوة.
  Future<void> _unlock() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      setState(() => _error = 'اسم الدخول إلزامي');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() =>
          _error = 'كلمة المرور إلزامية — لا جلسة بلا تحقق');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final typed = _password.text;
      final user = await widget.db
          .resumeSessionByLogin(login: login, password: typed);
      if (user.mustChangePassword) {
        final changed =
            await _showForcedPasswordDialog(user, verifiedCurrent: typed);
        if (!mounted) return;
        if (changed != true) {
          // الحوار غير قابل للرصد — لا يُعاد إلا بنجاح، والبقاء هنا
          // على البوابة والراية مقفلة حرسٌ لا عيب.
          setState(() => _busy = false);
          return;
        }
      }
      await widget.db.openSession();
      if (!mounted) return;
      widget.onUnlocked();
    } catch (e) {
      // س216: الفشل العام حصراً — «بيانات الدخول غير صحيحة» بلا تفرقة
      // (اسم مجهول/معطل/كلمة خاطئة) فلا معلومات تسريب من شاشة الدخول،
      // والتفصيل الحقيقي بسجل الأخطاء المحلي بيد صاحب الجهاز (dqLog
      // بعقد أقصى جهد لا يفشل المسار).
      if (!mounted) return;
      await dqLog(widget.db, e, context: 'gate.unlock');
      setState(() {
        _busy = false;
        _error = 'بيانات الدخول غير صحيحة';
      });
    }
  }

  /// الفتح بالبصمة — **للمعلق حصراً** (س213): التحقق البيومتري على
  /// الجهاز يثبت هوية صاحب الجلسة المعلقة فتخزينُ resumeSessionBiometric
  /// يرد غيره (لا بصة تفتح غير المستأنف ولا صاحب الإلزام)،
  /// ثم openSession بعقد س212 حصراً فلا ثقب عودة بكل خطوة،
  /// والرفض أو الإلغاء بلسانه والبوابة باقية والكلمة مسراها.
  Future<void> _unlockBiometric() async {
    final resumable = _resumable;
    if (_busy || resumable == null || resumable.mustChangePassword) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = widget.biometricAuthenticate != null
          ? await widget.biometricAuthenticate!()
          : await LocalAuthentication().authenticate(
              localizedReason: 'أكمل التحقق لفتح الجلسة المعلقة',
              options: const AuthenticationOptions(
                biometricOnly: true,
                stickyAuth: true,
              ),
            );
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'لم يُكمل التحقق البيومتري — أدخل كلمة المرور';
        });
        return;
      }
      await widget.db.resumeSessionBiometric(userId: resumable.id);
      await widget.db.openSession();
      if (!mounted) return;
      widget.onUnlocked();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e${dqTag(e)}';
      });
    }
  }

  /// حوار إلزام تغيير الكلمة بعد التحقق — بنمط الحوار الإلزامي الموثق
  /// س211 حرفاً: بلا حقل حالي (الكلمة المتحققة بالبوابة هي الحالية)
  /// وبلا إلغاء ولا رصد خارجي، والنجاح فنجانُ الراية بالتخزين حصراً
  /// (changeOwnPassword) فلا إلزام يتيمة.
  Future<bool?> _showForcedPasswordDialog(
    AppUser user, {
    required String verifiedCurrent,
  }) {
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    Future<void> submit(
        BuildContext dialogContext, StateSetter setDialogState) async {
      if (next.text.isEmpty) {
        setDialogState(() => error = 'الكلمة الجديدة إلزامية — لا فراغات');
        return;
      }
      if (next.text != confirm.text) {
        setDialogState(() => error = 'التأكيد لا يطابق الكلمة الجديدة');
        return;
      }
      try {
        final salt = PasswordHasher.newSalt();
        // س219: التجزئة بعزل الخلفية — لا تجميد واجهة بالحوار الإلزامي
        // (عقد قابلية الإرسال س218 بالمدار ذاته: الإغلاق قيم بسيطة حصراً).
        final hash = await PasswordHasher.hashInBackground(
            next.text, salt,
            iterations: widget.hasherIterations);
        await widget.db.changeOwnPassword(
          userId: user.id,
          currentPassword: verifiedCurrent,
          newPasswordHash: PasswordHasher.formatStored(
              salt, hash, widget.hasherIterations),
        );
        if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
      } catch (e) {
        await dqLog(widget.db, e, context: 'gate.password');
        setDialogState(() => error = '$e${dqTag(e)}');
      }
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('غيّر كلمة مرورك لمتابعة الجلسة'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text('كلمتك تحقق البوابة — اكتب الجديدة فقط.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: next,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirm,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'تأكيد كلمة المرور الجديدة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: TextStyle(
                            color:
                                Theme.of(dialogContext).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => submit(dialogContext, setDialogState),
                child: const Text('حفظ الكلمة الجديدة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resumable = _resumable;
    final hasActiveUsers = _hasActiveUsers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة الجهاز'),
        // البوابة حارسة — لا رجوع منها إلى شيء: مَن وراءها لا جلسة.
        automaticallyImplyLeading: false,
      ),
      body: hasActiveUsers == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'الجلسة مقفلة — أدخل اسم الدخول وكلمة المرور',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (!hasActiveUsers) ...[
                      const SizedBox(height: 16),
                      const Text('لا مستخدمين نشطين على هذا الجهاز'),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _login,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _busy ? null : _unlock(),
                      decoration: const InputDecoration(
                        labelText: 'اسم الدخول',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      enabled: !_busy,
                      onSubmitted: (_) => _busy ? null : _unlock(),
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // س213: زر البصمة للمعلق حصراً — بلا راية إلزام
                    // (حواره يحتاج كلمة متحققة) والجهاز بحسّاس فعّال
                    // — غير ذلك الكلمة هي المسار.
                    if (_biometricAvailable &&
                        resumable != null &&
                        !resumable.mustChangePassword) ...[
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _unlockBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('فتح بالبصمة'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'البصمة لصاحب الجلسة المعلقة حصراً — غيره ببيانات دخوله',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: _busy ? null : _unlock,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('دخول'),
                    ),
                    // س219: مؤشر الجريان أثناء التحقق — التجزئة صارت
                    // بعزل الخلفية فالمؤشر يتحرك فعلاً مهما كانت
                    // التكرارات (قبلها كان أي مؤشر سيتجمّد مع الخيط
                    // المحجوب 600,000 تكراراً — القياس الحي b73).
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
