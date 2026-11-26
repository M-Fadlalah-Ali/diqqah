/// شاشة فشل الافتتاح — D-197 (دفعة التحصين الافتتاحي، س96).
///
/// العقد الجديد بعد العلة الميدانية (تحديث b24→b26 على جهاز المالك
/// فشلَ ولو أظهر دورة تدوير أبدية بلا كلمة ولا كود): **لا دورة أبدية
/// بعد اليوم** — أي فشل في افتتاح البوابة (المجلد أو التبني أو لقطة
/// الأمان أو فتح القاعدة وترقية المخطط أو فحص التهيئة) يعرض رسالته
/// الحقيقية كاملةً قابلة للتحديد والنسخ، بزري إعادة المحاولة والمشاركة.
///
/// والمشاركة هنا بديل السجل: نص الخطأ يُشارك نصاً حصراً بلا ملفات
/// ولا صلاحيات (share_plus القائمة) — فلقطة المالك للشاشة أو نصها
/// المُشارك يحمل ما كان سطرُ logcat يحمله حرفياً.
///
/// التوجيه الأمني مثبت بالشاشة ذاتها: لا حذف للطبيق — بيانات القاعدة
/// بملفها والإعادة آمنة دائماً (الترحيلات آمنة التكرار، ولقطة الأمان
/// preup* تحفظ الأصل النقي — D-197).
library;

import 'package:flutter/material.dart';

import 'package:share_plus/share_plus.dart';

import 'adaptive.dart';

/// شاشة فشل الافتتاح — رسالة حقيقية وزرّا إعادة ومشاركة.
class GateErrorScreen extends StatelessWidget {
  /// نص الفشل كاملاً: المرحلة التي رمت ثم الاستثناء الحقيقي.
  final String message;

  /// إعادة محاولة الافتتاح من البداية (الترحيلات آمنة التكرار).
  final VoidCallback onRetry;

  const GateErrorScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  Future<void> _share() async {
    // نص حصراً — بلا ملفات ولا صلاحيات، والقناة القائمة share_plus.
    await Share.share('خطأ افتتاح دِقَّة\n\n$message\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('gate_error_screen'),
      body: DiqqahAdaptiveCenter(child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.error_outline,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'تعذر افتتاح التطبيق',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'فشلٌ في خطوة من خطوات الافتتاح — رسالته الحقيقية أدناه '
                'كاملة. لا تحذف التطبيق إطلاقاً: بياناتك محفوظة بملف '
                'القاعدة، وإعادة المحاولة آمنة دائماً.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(message),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                key: const ValueKey('gate_retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('gate_share'),
                onPressed: _share,
                icon: const Icon(Icons.share),
                label: const Text('مشاركة الخطأ'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      )),
    );
  }
}
