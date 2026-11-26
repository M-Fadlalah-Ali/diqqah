/// قائمة سياق السجل الموحدة — دفعة س207 (تنظيف ويندوز — بنود 2 و3 من
/// نقاش المالك المعتمد 2026-11-22):
/// «زر اليمين معطل تماماً في ويندوز» و«اقتراح أن يكون النقر الطويل في
/// أندرويد = النقر باليمين في ويندوز».
///
/// العقد:
/// - **مصدر واحد لا اثنان**: الزر الثانوي على سطح المكتب (ويندوز/لينكس/
///   ماك) والضغطة الطويلة على الهاتف تفتحان القائمة ذاتها بمحتواها
///   وترتيبها ذاته — عرف سطح المكتب المحاكم (قائمة السياق في
///   QuickBooks Desktop وDynamics وSAP GUI) وعرف أندرويد المعلن
///   (الضغط الطويل قائمة سياق المنصة) بمكوّن واحد لا ويدجتَين.
/// - **الفعاليات يملكها المضيف حصراً**: كل بند [RecordContextAction]
///   يمرره ملف الشاشة ويستدعي فعالياتها القائمة أصلاً (_openDetail و
///   _quickPrint ونظيراتها) — لا سلوك جديد يُخترع هنا ولا نداء نواة
///   ولا مساس بالمجال والتخزين حرفاً. المكوّن طبقة عرض نقية.
/// - **الفعالية الوحيدة المشتركة المبنية هنا**: نسخ معرّف السجل —
///   فعالية واجهة نقية (حافظة النظام + بشّارة تأكيد) بلا قراءة ولا
///   كتابة قاعدة، ولسانها الوحيد بالثوابت أدناه.
/// - **الوضع الفارغ**: قائمة بلا بنود لا تُفتح أصلاً — الغلاف باقٍ
///   شفافاً فلا يتغير سلوك اللمس ولا يظهر قائمة فارغة أبداً.
/// - **الاتجاهية**: الموضع بحساب شاشي مطلق (global) والقائمة تقلب
///   تلقائياً بعرف المادة لا بمحاذاة فيزيائية — عرف M3 الموثق
///   (م14/م18: الاتجاهية المنطقية لا اليسارية).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// فعالية قائمة سياق واحدة — اللسان والأيقونة والنداء يملكها المضيف.
class RecordContextAction {
  const RecordContextAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  /// لسان الفعالية كما يظهر بالقائمة.
  final String label;

  /// أيقونة الفعالية — من عائلة المادة القائمة بالشاشة.
  final IconData icon;

  /// النداء على فعاليات المضيف القائمة أصلاً — لا جديد هنا.
  final VoidCallback onSelected;
}

/// لسان فعالية نسخ المعرّف — الوحيدة المشتركة بالمكوّن.
const String kCopyIdLabel = 'نسخ المعرّف';

/// أيقونة نسخ المعرّف.
const IconData kCopyIdIcon = Icons.copy_outlined;

/// بشّارة التأكيد بعد النسخ — لسان موحد بكل الشاشات.
const String kCopiedSnack = 'نُسخ المعرّف إلى الحافظة';

/// فعالية جاهزة: نسخ معرّف السجل إلى الحافظة — واجهة نقية
/// (حافظة + بشّارة) بلا مساس بالمجال والتخزين حرفاً.
RecordContextAction copyIdAction(
  BuildContext context,
  Object id,
) =>
    RecordContextAction(
      label: kCopyIdLabel,
      icon: kCopyIdIcon,
      onSelected: () async {
        await Clipboard.setData(ClipboardData(text: '$id'));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text(kCopiedSnack)));
        }
      },
    );

/// غلاف قائمة سياق السجل — يلف بند قائمة والقائمة تفتح من مصدر واحد:
/// الزر الثانوي على سطح المكتب والضغطة الطويلة على الهاتف.
class RecordContextMenu extends StatelessWidget {
  const RecordContextMenu({
    super.key,
    required this.actions,
    required this.child,
  });

  /// بنود القائمة — يملكها المضيف. الفارغة تعني غلافاً شفافاً.
  final List<RecordContextAction> actions;

  /// بند القائمة الملفوف (ListTile أو نظيره).
  final Widget child;

  Future<void> _show(BuildContext context, Offset globalPosition) async {
    if (actions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final picked = await showMenu<RecordContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: [
        for (final action in actions)
          PopupMenuItem<RecordContextAction>(
            value: action,
            child: Row(
              children: [
                Icon(action.icon, size: 18),
                const SizedBox(width: 10),
                Text(action.label),
              ],
            ),
          ),
      ],
    );
    picked?.onSelected();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        // سطح المكتب: الزر الثانوي — عرف الديسكتوب المحاكم.
        onSecondaryTapUp: (details) =>
            _show(context, details.globalPosition),
        // الهاتف: الضغطة الطويلة — القائمة ذاتها بمحتواها وترتيبها
        // (مصدر واحد لا اثنان — بند 3 من النقاش المعتمد).
        onLongPressStart: (details) =>
            _show(context, details.globalPosition),
        child: child,
      );
}
