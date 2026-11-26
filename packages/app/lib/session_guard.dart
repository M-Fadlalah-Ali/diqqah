import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

/// س213 (دفعة 3 من خطة الجلسة والمستخدمين — D-217): حارس الخمول وقفل
/// مغادرة التطبيق — إعداد جهاز في قسم «البيانات والأمان» بيد المدير
/// لا تفضيل شخصي فلا يعطّله الكاشير.
///
/// القانون الموثق:
/// - مدة الخمول من المستويات المغلقة 1/5/10/15/30 دقيقة (الافتراض 10
///   حسمُ F-147 الموثق) — تُقرأ من القاعدة عند كل نبضة فتغييرُ
///   الإعداد من البطاقة يسري حياً بلا إقلاع.
/// - **قفل فوري عند مغادرة التطبيق** قانوناً لا خياراً: حالةُ
///   `hidden` (النافذة مخفية كلياً — تصغير ويندوز أو إخفاء أندرويد)
///   و`paused` (الخلفية) تُقفلان الجلسة فوراً — و`inactive` لا يقفل
///   (حوارات النظام والمكالمات لا مغادرة).
/// - النشاط الذي يمدّ العدّ: لمس الشاشة وحركته وعجلة التمرير
///   (بمستمع المؤشر على جذر MaterialApp)، والمفاتيح الصلبة
///   (HardwareKeyboard — لوحات سطح المكتب). **الحد الصادق**: الكتابة
///   بلوحة اللمس الناعمة على الهاتف بلا لمس شاشة لا تُرصد إشارةَ
///   إطارٍ نقية في Flutter — فمدة الخمول لا تُمدّ بها (الفعل العملي
///   مصحوب لمسات حقول، والفتح السريع بالبصمة ردٌّ فوري إن نال) —
///   موثقة هنا وسجل العمل لا يُخفى.
///
/// القفل عبر آلة الحالتين حصراً (س212/D-215): `lockSession(via: …)`
/// تكتب الراية بالقاعدة فموتُ العملية بعدها يرد البوابة لا الرئيسية
/// — والحاكم البصري (onLocked) يعرض بوابة الجهاز بغلٍّ واحد في
/// AppGate. الحارس يسكت ذاتياً حين لا جلسة نشطة (البوابة أو
/// التهيئة أو فحص الاستعادة) فلا قفل على وجه بلا جلسة.
class SessionIdleGuard {
  SessionIdleGuard._();

  static SessionIdleGuard? _instance;
  static SessionIdleGuard get instance => _instance ??= SessionIdleGuard._();

  /// فترة النبض — فحص دوري خفيف يقرأ المدة النافذة ويسائل الخمول
  /// (قراءة صف واحد بapp_meta كل نبضة فلا تكلفة تُذكر).
  static const Duration _tickPeriod = Duration(seconds: 5);

  Timer? _ticker;
  AppLifecycleListener? _lifecycle;
  DiqqahDatabase? _db;
  VoidCallback? _onLocked;
  bool _locking = false;

  /// عدّ النبضات الخمولية المتتالية — قياس الخمول بنبضات المؤقت لا
  /// بساعة الحائط: النشاط يصفّر العدّ وكل نبضة بلا نشاط تزيده،
  /// والقفل عند (العدّ × فترة النبض) ≥ المدة النافذة. الدقة ± نبضة
  /// واحدة فلا فرق إنتاجياً، والاختبارات تسير بالساعة الوهمية ذاتها
  /// (نبضات tester.pump تُحصى حرفاً — درس الاختبار الموثق بالدفعة:
  /// DateTime.now() لا يتقدم بالساعة الوهمية فالقياس الزمني الصريح
  /// يفسد اختباراً وإنتاجاً على السواء).
  int _idleTicks = 0;
  bool _activitySinceTick = false;

  /// الحارس قائم بجلسة نشطة — يُنادى من initState الرئيسية حصراً
  /// (وجه الجلسة النشطة) فالبوابة والتهيئة والاستعادة بلا حارس.
  void start(DiqqahDatabase db, {required VoidCallback onLocked}) {
    stop();
    _db = db;
    _onLocked = onLocked;
    _locking = false;
    // افتتاح الجلسة نشاطٌ بذاته — أول نبضة تصفّر لا تُحتسب خمولاً.
    _activitySinceTick = true;
    _idleTicks = 0;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleState);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _ticker = Timer.periodic(_tickPeriod, (_) => _checkIdle());
  }

  /// مصفوفة المفاتيح الصلبة — سطح المكتب أساساً: كل ضغطة تمدّ العدّ
  /// ولا تستهلك الحدث (شاهد لا مستهلك بعرف المستمع السطحي).
  bool _onKeyEvent(KeyEvent event) {
    noteActivity();
    return false;
  }

  /// يُنادى من dispose الرئيسية — القفل (يدوي أو آلي) يحوّل الوجه
  /// لبوابة الجهاز فتنحل الرئيسية ويتوقف الحارس ذاتياً.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _db = null;
    _onLocked = null;
  }

  /// نبض النشاط من مستمع المؤشر على جذر MaterialApp — اللمس
  /// والحركة والعجلة كلها تمدّ العدّ بلا تمييز عنصر.
  void noteActivity() {
    _activitySinceTick = true;
  }

  void _onLifecycleState(AppLifecycleState state) {
    // D-217: القفل الفوري عند مغادرة التطبيق — hidden (النافذة
    // مخفية كلياً) وpaused (الخلفية) مغادرة، وinactive حوارُ نظام
    // أو انتقال عابر فلا قفل به.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _lockNow('app_left');
    }
  }

  Future<void> _checkIdle() async {
    final db = _db;
    if (db == null || _locking) return;
    if (_activitySinceTick) {
      _activitySinceTick = false;
      _idleTicks = 0;
      return;
    }
    _idleTicks++;
    try {
      if (await db.sessionLocked()) return;
      final minutes = await db.sessionIdleMinutes();
      if (_tickPeriod * _idleTicks >=
          Duration(minutes: minutes)) {
        _lockNow('idle');
      }
    } catch (_) {
      // فحص الحارس أقصى جهد — فشل قراءة لا يُسقط الجلسة النشطة.
    }
  }

  Future<void> _lockNow(String via) async {
    final db = _db;
    if (db == null || _locking) return;
    _locking = true;
    try {
      // الجلسة مقفلة أصلاً (منافس آلي يدوي؟) فلا حدث مكرر ولا كتابة
      // ثانية — الراية موجودة يكفي.
      if (await db.sessionLocked()) return;
      await db.lockSession(via: via);
      final callback = _onLocked;
      callback?.call();
    } catch (_) {
      // فشل القفل الآلي لا يُسقط الجلسة — النبضة التالية تجرب،
      // والقفل اليدوي بشارة الرئيسية باقٍ متاحاً دائماً.
    } finally {
      _locking = false;
    }
  }

  /// مستمع المؤشر الموحد — يُركَّب فوق MaterialApp في الجذر فيلتقط
  /// النشاط على كل الطبقات حصراً (القوائم والحوار والمصفوفة) بلا
  /// مساس بسلوك اللمس ذاته (المستمع شاهد لا مستهلك).
  static Widget pointerActivityListener({required Widget child}) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => instance.noteActivity(),
      onPointerMove: (_) => instance.noteActivity(),
      onPointerPanZoomUpdate: (_) => instance.noteActivity(),
      child: child,
    );
  }
}

/// س213: FLAG_SECURE على أندرويد — قانون لا خيار (بلا مفتاح إعداد):
/// لقطات الشاشة ومعاينة المستخدمة الأخيرة لبيانات محاسبية لا تُعرض
/// خارج التطبيق (سلوك تطبيقات البنوك الموثق بنقاش المالك). القناة
/// الأصلية `diqqah/security` بنمط قناة البطارية (`diqqah/device_status`)
/// — أندرويد حصراً والويندوز بلا قناة أصلاً فيتخطى الشرط سائغاً،
/// وفشل القناة (الاختبارات بلا منصة) مبتلعٌ فلا يُسقط الإقلاع أبداً
/// (إقلاع التطبيق أقدس من راية).
Future<void> applyAndroidFlagSecure() async {
  if (!Platform.isAndroid) return;
  try {
    const channel = MethodChannel('diqqah/security');
    await channel.invokeMethod<void>('setSecure', <String, Object?>{
      'secure': true,
    });
  } on MissingPluginException {
    // الاختبارات والبيئات بلا قناة — الراية حاضرة بالإنتاج حصراً.
  } catch (_) {
    // أي فشل آخر لا يمنع الافتتاح — الحماية تجرب عند الإقلاع التالي.
  }
}
