package app.diqqah.diqqah_app

import android.content.Context
import android.os.BatteryManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// تكليف النسخ الاحتياطي 2026-11-13 (قرار ق-ن2): قناة يدوية صغيرة
/// لنسبة البطارية — أندرويد حصراً بلا تبعية خارجية، وغلاف try كامل
/// كي لا يعطل أي شيء عند غياب الخدمة. ويندوز بلا قناة أصلاً فيتخطى
/// شرط السارية سائغاً بلفظ القرار «لا تُعطّل النسخ أبداً».
///
/// س213 (دفعة 3 من خطة الجلسة والمستخدمين): قناة الأمان
/// `diqqah/security` — راية FLAG_SECURE قانوناً لا خياراً (سلوك
/// تطبيقات البنوك): لقطات الشاشة ومعاينة المستخدمة الأخيرة لبيانات
/// محاسبية لا تُعرض خارج التطبيق. والغلاف try كامل ففشل الراية لا
/// يُسقط الافتتاح أبداً. والقاعدة `FlutterFragmentActivity` شرطُ
/// البيومتري local_auth (BiometricPrompt يعمل فوق Fragment) —
/// التبديل من FlutterActivity بعقد الحزمة ذاته لا تغيير سلوك آخر.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "diqqah/device_status"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "batteryLevel" -> {
                    try {
                        val bm = getSystemService(Context.BATTERY_SERVICE)
                            as BatteryManager
                        val level = bm.getIntProperty(
                            BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        if (level >= 0) result.success(level) else result.success(null)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "diqqah/security"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    try {
                        val secure = (call.arguments as? Map<*, *>)
                            ?.get("secure") as? Boolean ?: true
                        if (secure) {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(
                                WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // س221 (دفعة سرعة الدخول بأمر المالك «ابدأ بتنفيذ الدفعات الخمسة
        // بالتسلسل الذي عرضته» — المؤجل س219 «تسريع التجزئة بتنفيذ
        // أصلي»): قناة التجزئة الأصيلة PBKDF2-HMAC-SHA256 — نفس
        // الرياضيات المعيارية RFC 2898 وبنفس التكرارات حرفاً (لا خفض
        // أمني بل محرك أسرع حصراً) والعمل الثقيل بمنفذ متسلسل جانب
        // المنصة فخيط واجهة أندرويد لا يحجب أبداً، والجواب يُعاد على
        // الخيط الرئيسي بعقد MethodChannel. الدارت تتحقق ذاتياً بمتجه
        // معياري قبل التثبيت (NativePbkdf2Engine) فأي انحراف يعزل
        // الأصيل ويبقي عزل الخلفية الخالص س219 — والرفض المدى قبل
        // العمل كي لا يُقبل طلب منتهٍ.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "diqqah/security/pbkdf2"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "derive" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        val passwordB64 = args?.get("password") as? String
                        val saltB64 = args?.get("salt") as? String
                        val iterations =
                            (args?.get("iterations") as? Number)?.toInt()
                        val dkLen = (args?.get("dkLen") as? Number)?.toInt()
                        if (passwordB64 == null || saltB64 == null ||
                            iterations == null || dkLen == null ||
                            iterations < 1 || iterations > 10000000 ||
                            dkLen < 1 || dkLen > 1024
                        ) {
                            result.error(
                                "invalid_args", "وسائط التجزئة خارج العقد", null)
                        } else {
                            val password = android.util.Base64.decode(
                                passwordB64, android.util.Base64.NO_WRAP)
                            val salt = android.util.Base64.decode(
                                saltB64, android.util.Base64.NO_WRAP)
                            hashExecutor.execute {
                                try {
                                    val derived = derivePbkdf2HmacSha256(
                                        password, salt, iterations, dkLen)
                                    val answer = android.util.Base64
                                        .encodeToString(
                                            derived, android.util.Base64.NO_WRAP)
                                    mainHandler.post { result.success(answer) }
                                } catch (e: Exception) {
                                    mainHandler.post {
                                        result.error(
                                            "derive_failed", e.message, null)
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        result.error("derive_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        /// منفذ متسلسل واحد على مستوى الصف — عمليات التجزئة لا تتوازى
        /// فلا سباق ذاكرة ولا استنفاد خيوط، وإعادة بناء النشاط لا تسرّب
        /// منفذاً جديداً.
        private val hashExecutor =
            java.util.concurrent.Executors.newSingleThreadExecutor()

        /// جواب القناة يُعاد على الخيط الرئيسي بعقد MethodChannel.
        private val mainHandler =
            android.os.Handler(android.os.Looper.getMainLooper())
    }

    /// PBKDF2-HMAC-SHA256 بمعماره المعياري RFC 2898: F(P, S, c, i) =
    /// U1 xor U2 xor ... xor Uc — بترتيب البايتات الكبير لـINT(i)
    /// وبنفس الرياضيات حرفاً مع PasswordHasher.pbkdf2Bytes في المجال
    /// (المتجهات المعيارية PKCS#5 بالاختبارات والتحقق الذاتي عند
    /// الإقلاع شهود). HmacSHA256 عبر Conscrypt فالحساب بعجلة الجهاز
    /// (امتدادات التشفير ARMv8) — وهذا مصدر التسريع الأصلي كله.
    private fun derivePbkdf2HmacSha256(
        password: ByteArray,
        salt: ByteArray,
        iterations: Int,
        dkLen: Int
    ): ByteArray {
        val mac = javax.crypto.Mac.getInstance("HmacSHA256")
        mac.init(javax.crypto.spec.SecretKeySpec(password, "HmacSHA256"))
        val blocks = (dkLen + 31) / 32
        val out = ByteArray(dkLen)
        var offset = 0
        for (block in 1..blocks) {
            val saltBlock = ByteArray(salt.size + 4)
            salt.copyInto(saltBlock)
            saltBlock[salt.size] = (block ushr 24).toByte()
            saltBlock[salt.size + 1] = (block ushr 16).toByte()
            saltBlock[salt.size + 2] = (block ushr 8).toByte()
            saltBlock[salt.size + 3] = block.toByte()
            var u = mac.doFinal(saltBlock)
            val f = u.copyOf()
            for (i in 1 until iterations) {
                u = mac.doFinal(u)
                for (j in u.indices) {
                    f[j] = (f[j].toInt() xor u[j].toInt()).toByte()
                }
            }
            val n = minOf(f.size, out.size - offset)
            System.arraycopy(f, 0, out, offset, n)
            offset += n
        }
        return out
    }
}
