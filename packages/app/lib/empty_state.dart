import 'package:flutter/material.dart';

/// س225 (خ6 من الدفعة الأولى للحيوية بأمر المالك «أوافق على الدفعة
/// الأولى — خ1 وخ2 وخ7 وخ6»): حالة الفراغ الحية — القرص البني الهويّي
/// بأيقونته ورسالة الفراغ وتلميحها الاختياري بدل نص عائم معلم.
///
/// العقد اللوني (س182/س203) باقٍ حرفاً: الفراغ ليس دلالة — فلا أخضر
/// ولا أحمر ولا أزرق هنا أبداً؛ القرص من primaryContainer وأيقونته
/// onPrimaryContainer (عائلة الهوية البنية) والتلميح من onSurfaceVariant
/// — أدوار الثيم لا ألوان خام، ولسان الفراغ القائم في كل شاشة باقٍ
/// حرفاً فلا اختبار ينكسر ولا لسان يُبتدع.
class DiqqahEmptyState extends StatelessWidget {
  /// أيقونة القرص — من الأيقونات المخططة بعرف الواجهة.
  final IconData icon;

  /// رسالة الفراغ — لسان الشاشة القائم حصراً.
  final String message;

  /// تلميح إرشادي اختياري تحت الرسالة.
  final String? hint;

  const DiqqahEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: AlignmentDirectional.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
