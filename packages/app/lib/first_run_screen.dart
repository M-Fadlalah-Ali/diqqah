import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// شاشة أول تشغيل — إنشاء المستخدم الأول (مدير) إلزامياً (F-014، س-01).
///
/// لا يمكن تخطيها ولا الوصول لأي بيانات قبلها: البوابة (AppGate) لا تعرض
/// غيرها ما دام لا مستخدمين في القاعدة.
class FirstRunScreen extends StatefulWidget {
  final DiqqahDatabase db;
  final int hasherIterations;
  final VoidCallback onSetupDone;

  const FirstRunScreen({
    super.key,
    required this.db,
    required this.onSetupDone,
    this.hasherIterations = 50000,
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
      final hash = PasswordHasher(iterations: widget.hasherIterations)
          .hash(password, salt);
      await widget.db.createManager(
        name: name,
        login: login,
        passwordHash: '$salt:$hash',
      );
      if (!mounted) return;
      // س-01: بعد التنفيذ تُفتح الشاشة الهيكلية.
      widget.onSetupDone();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذر إنشاء المدير — تحقق أن اسم الدخول غير مستخدم';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                'أول مستخدم في القاعدة يكون مديراً — إلزامي قبل أي شاشة أخرى (س-01)',
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
                  style: const TextStyle(color: Colors.red),
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
