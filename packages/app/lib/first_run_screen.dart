import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'adaptive.dart';
import 'dq_log.dart';

/// شاشة أول تشغيل — إنشاء المستخدم الأول (مدير) إلزامياً (F-014، س-01).
///
/// لا يمكن تخطيها ولا الوصول لأي بيانات قبلها: البوابة (AppGate) لا تعرض
/// غيرها ما دام لا مستخدمين في القاعدة.
///
/// س116 (المرحلة أ — التحصين التشغيلي): بعد إنشاء المدير تظهر بطاقة
/// «سير أول استخدام» الموجَّه — أربع خطوات قبل أول بيع بالنظام الأول
/// فيها النسخة الاحتياطية الأولى (طقس §0/4: النسخة بيد المالك تلزم
/// قبل أول استخدام فعلي) — ثم «ابدأ الاستخدام» يفتح الهيكلية.
class FirstRunScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final int hasherIterations;
  final VoidCallback onSetupDone;

  const FirstRunScreen({
    super.key,
    required this.db,
    required this.onSetupDone,
    this.hasherIterations = PasswordHasher.secureIterations,
  });

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _name = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;

  /// س116: هل أُنشئ المدير؟ — صادقةً تُعرض بطاقة السير الموجَّه
  /// قبل فتح الهيكلية، ولا طريق للهيكلية إلا بزرها.
  bool _created = false;

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final login = _login.text.trim();
    final password = _password.text;

    // س-01: الإدخال الاسم وكلمة المرور بدور «مدير» — لا حقول فارغة
    // (حد أدنى بلا قياس مبتكرَع غيره في التوثيق).
    if (name.isEmpty || login.isEmpty || password.isEmpty) {
      setState(() => _error = 'الحقول الثلاثة إلزامية — لا فراغات');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final salt = PasswordHasher.newSalt();
      // س219: التجزئة بعزل الخلفية — أول إنشاء مدير لا يجمّد الواجهة
      // (عقد قابلية الإرسال س218 بالمدار ذاته: الإغلاق قيم بسيطة حصراً).
      final hash = await PasswordHasher.hashInBackground(
          password, salt,
          iterations: widget.hasherIterations);
      await widget.db.createManager(
        name: name,
        login: login,
        // P2: الصيغة الذاتية الوصف — التكرارات مسجلة بالسجل فلا قراءة
        // تتفرض تكرارات لم يسجلها الكاتب (عقد PasswordHasher).
        passwordHash: PasswordHasher.formatStored(
            salt, hash, widget.hasherIterations),
      );
      if (!mounted) return;
      // س116: المدير وُلد — سير أول استخدام الموجَّه قبل الهيكلية.
      setState(() {
        _busy = false;
        _created = true;
      });
    } catch (e) {
      await dqLog(widget.db, e, context: 'first_run.manager');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'تعذر إنشاء المدير — تحقق أن اسم الدخول غير مستخدم'
            '${dqTag(e)}';
      });
    }
  }

  /// س116: بطاقة خطوة من سير أول استخدام — العنوان والشرح بلسان واحد.
  Widget _guideStep(IconData icon, String title, String body) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 6),
            Text(body),
          ],
        ),
      ),
    );
  }

  /// س116: بطاقة السير الموجَّه — أربع خطوات بالنظام الأول أولاً.
  Widget _buildGuide() {
    return Scaffold(
      appBar: AppBar(title: const Text('سير أول استخدام')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 24),
            24,
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 24),
            24),
        children: [
          const Text(
            'أهلاً بك في دِقَّة — أربع خطوات قبل أول بيع',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _guideStep(
            Icons.backup_outlined,
            'الخطوة 1 — النسخة الاحتياطية الأولى',
            'من الإعدادات ← النسخ الاحتياطي والاستعادة: أنشئ نسختك الأولى '
                'وأخرجها من الجهاز (مشاركة أندرويد أو مجلد ويندوز). '
                'والنسخة الدورية بعدها طقس لا يُترك — هي طريق الرجوع الوحيد.',
          ),
          _guideStep(
            Icons.warehouse_outlined,
            'الخطوة 2 — المستودعات والعملات',
            'بطاقة «المستودعات» لضبط مستودعاتك، و«العملات» من الإعدادات '
                'لأسعار الصرف اليومية إن عملت بغير العملة الأساسية.',
          ),
          _guideStep(
            Icons.inventory_2_outlined,
            'الخطوة 3 — الأصناف والأطراف',
            'أدخل أصنافك (بضاعة أو تجميعي أو خدمة) ومورديك وعملائك من '
                'شاشتي «الأصناف» و«الأطراف»، واضبط مجموعات التعبئة '
                'إن بعت بالعلب والكراتين — فكل مستندات المخزون تدخل بها.',
          ),
          _guideStep(
            Icons.event_available_outlined,
            'الخطوة 4 — الفترة وأول فاتورة',
            'افتح فترة الشهر من الإعدادات ثم ابدأ بأول فاتورة شراء يدخل '
                'المخزون بكلفته، ثم أول بيع — والقيد يتبع تلقائياً.',
          ),
          const SizedBox(height: 8),
          const Text(
            'الدليل الكامل: «البدء السريع» ضمن أدلة دِقَّة — ورسائل الأخطاء '
                'برموزها (DQ-xxxx) مشروحة في «مرجع الأخطاء» وشاشة '
                '«التشخيص ومرجع الأخطاء» بالإعدادات.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onSetupDone,
            child: const Text('ابدأ الاستخدام'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // س116: بعد ولادة المدير بطاقة السير الموجَّه — لا هيكلية قبل زرها.
    if (_created) {
      return _buildGuide();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('أول تشغيل')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'دِقَّة — أول تشغيل',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'أول مستخدم في القاعدة يكون مديراً — إلزامي قبل أي شاشة أخرى',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _login,
                decoration: const InputDecoration(
                  labelText: 'اسم الدخول',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              _busy
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton(
                      onPressed: _create,
                      child: const Text('إنشاء المدير'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
