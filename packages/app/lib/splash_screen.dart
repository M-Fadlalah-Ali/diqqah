/// شاشة البدء المتحركة (س233 — D-233، المرحلة أ/4 من خارطة الطريق
/// الخماسية): اسم التطبيق بحركة نبض هادئة على الانطلاقة الفحمية
/// الموحدة (س229) ولسان المرحلة المعطِّلة الجارية حصراً — فالحالات
/// التي تُنتظر حقاً (فتح القاعدة وترقيتها، لقطة الأمان، حمل الجذر من
/// الخزنة وفتحها، فحص التهيئة) تُرى بلسانها، والنسخ والمزامنة لا
/// مكان لهما هنا: مؤشرا حالة صغيران بتذييل الرئيسية (لا شاشة انتظار).
///
/// والحد الأدنى نصف ثانية للإنتاج (قابل للحقن — الحقن الاختباري
/// يتجاوزه فلا يبطئ اختباراً): يكفل أن الانطلاقة تُرى لا وميضاً،
/// والحكم بمدخل AppGate لا هنا (الشاشة عرض خالص).
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'l10n/app_strings.dart';

/// شاشة البدء — لسان المرحلة منبِّه قيمة تُحدَّث من بوابة الافتتاح
/// حياً فلا setState في صدر الإقلاع.
class DiqqahSplash extends StatefulWidget {
  final ValueListenable<String> stageListenable;

  const DiqqahSplash({super.key, required this.stageListenable});

  @override
  State<DiqqahSplash> createState() => _DiqqahSplashState();
}

class _DiqqahSplashState extends State<DiqqahSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // س229 (توحيد الانطلاقة): الخلفية الفحمية (30,30,30) ذاتها التي
      // تبدأ بها انطلاقة النظام فلا وميض أبيض بينهما — والبني الهويّي
      // لون العناصر فحسب.
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // اسم التطبيق بحركة نبض هادئة — يتردد شفافيته ببطء فلا
            // صمت ولا صخب (والمتحركة بلسان الخطة: حركة لطيفة مستمرة).
            FadeTransition(
              opacity: CurvedAnimation(
                  parent: _pulse, curve: Curves.easeInOut),
              child: const Text(
                S.splashAppName,
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: kDarkIdentityBrown,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: kDarkIdentityBrown),
            const SizedBox(height: 16),
            // لسان المرحلة الجارية — الحالات المعطِّلة فقط (D-233)،
            // والنص من فهرس l10n ببوابة الافتتاح لا مضمناً هنا.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ValueListenableBuilder<String>(
                valueListenable: widget.stageListenable,
                builder: (context, stage, _) => Text(
                  stage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kDarkIdentityBrown),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
