/// شاشة التشخيص ومرجع الأخطاء — س107 (أساس الأخطاء، قرار المالك الخامس).
///
/// ثلاث بطاقات قراءة بحتة لا إجراء فيها على البيانات:
/// (1) النظام: سطر الإصدار المحقون زمن الترجمة (Task 51) وإصدار المخطط
///     ومعرف الجهاز — هوية النافذة التي يشاركها المالك مع أي بلاغ —
///     وس146 (p3 خط التشفير) يضيف سطر حالة الإحكام حياً: فحص الحواجز
///     الرباعية والملح والختم من القاعدة ذاتها لا نص ثابت.
/// (2) آخر الأخطاء: ذيل سجل error_log (الأحدث أولاً، حد 50) بالرمز
///     والرسالة والسياق والزمن — append-only لا حذف ولا تفريغ —
///     والرسالة والسياق مفكّان شفافاً من ختم p3 (p3_log_text عرف
///     التوافق: الخام يمر والتلف يعرض برسالة DQ-1108 لا انهيار).
/// (3) مرجع الرموز: سجل DQ-xxxx كاملاً من سلطة الترقيم بالمجال
///     (error_codes.dart) — الشاشة والوثيقة 08 يقرآن المصدر نفسه.
///
/// وزر المشاركة يبني نصاً من البطاقات الثلاث (بديل السجل — عرف D-197:
/// النص المشارك يحمل ما كان سطرُ logcat يحمله) — وس146 يضيف حالة
/// الإحكام للنص المشارك كي يوثق البلاغ حالة الحماية مع الهوية.
library;

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'package:share_plus/share_plus.dart';

import 'adaptive.dart';
import 'settings_screen.dart' show diqqahVersionLine, kAppVersion,
    kBuildNumber;

/// شاشة التشخيص — قراءة لا إجراء.
class DiagnosticsScreen extends StatelessWidget {
  final DiqqahDatabase db;

  const DiagnosticsScreen({super.key, required this.db});

  Future<void> _share(
    String versionText,
    List<Map<String, Object?>> errors,
  ) async {
    final buf = StringBuffer('تشخيص دِقَّة\n');
    buf.writeln('الإصدار: $versionText');
    buf.writeln('إصدار المخطط: ${DiqqahDatabase.schemaVersionValue}');
    final deviceId = await db.deviceId();
    buf.writeln('معرف الجهاز: $deviceId');
    buf.writeln(await _p3StatusLine());
    buf.writeln('عدد سجلات الأخطاء: ${await db.errorLogCount()}');
    buf.writeln();
    buf.writeln('آخر الأخطاء (الأحدث أولاً):');
    if (errors.isEmpty) {
      buf.writeln('  (لا سجلات)');
    }
    for (final e in errors.take(20)) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        e['created_at'] as int? ?? 0,
      );
      buf.writeln(
          '  [${e['code']}] ${e['message']}'
          '${e['context'] == null ? '' : ' — ${e['context']}'}'
          ' — $at');
    }
    await Share.share(buf.toString());
  }

  /// p3 (س146): حالة الإحكام حية من القاعدة — الحواجز الرباعية
  /// بsqlite_master والملح بapp_meta وصف مختوم بالسجل: أيها غاب
  /// يُعلن بالاسم لا «مفعّل» عامة — فالعرض الصادق لا يطمئن بلا دليل.
  Future<String> _p3StatusLine() async {
    final guards = (await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type='trigger' AND name IN "
          "('trg_events_no_update','trg_events_no_delete',"
          "'trg_error_log_no_update','trg_error_log_no_delete')",
        ).get())
        .length;
    if (guards != 4) {
      return 'تشفير السجلات (p3): غير مفعّل — الحواجز $guards/4';
    }
    final saltRow = await (db.select(db.appMeta)
          ..where((t) =>
              t.key.equals(DiqqahDatabase.p3LogSaltMetaKey)))
        .getSingleOrNull();
    if (saltRow == null || saltRow.value.isEmpty) {
      return 'تشفير السجلات (p3): غير مفعّل — الملح غائب';
    }
    final sealed = await db.customSelect(
          "SELECT COUNT(*) c FROM events WHERE payload LIKE 'dq3log1:%'",
        ).getSingleOrNull();
    final sealedCount = sealed?.data['c'] as int? ?? 0;
    return 'تشفير السجلات (p3): مفعّل — الحواجز 4/4 والملح قائم '
        'ومختوم $sealedCount حدثاً';
  }

  @override
  Widget build(BuildContext context) {
    final versionText = diqqahVersionLine(kAppVersion, kBuildNumber).isEmpty
        ? 'نسخة تطوير (بلا حقن إصدار)'
        : diqqahVersionLine(kAppVersion, kBuildNumber);

    return Scaffold(
      key: const ValueKey('diagnostics_screen'),
      appBar: AppBar(title: const Text('التشخيص')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16,
            diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
            16),
        children: [
          // ── بطاقة النظام ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                key: const ValueKey('diagnostics_system'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('النظام',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('الإصدار: $versionText'),
                  Text('إصدار المخطط: ${DiqqahDatabase.schemaVersionValue}'),
                  FutureBuilder<String>(
                    future: db.deviceId(),
                    builder: (context, snap) => Text(
                        'معرف الجهاز: ${snap.data ?? '…'}'),
                  ),
                  FutureBuilder<String>(
                    key: const ValueKey('diagnostics_p3_status'),
                    future: _p3StatusLine(),
                    builder: (context, snap) =>
                        Text(snap.data ?? 'تشفير السجلات (p3): …'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── بطاقة آخر الأخطاء ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                key: const ValueKey('diagnostics_errors'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('آخر الأخطاء',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Map<String, Object?>>>(
                    future: db.recentErrors(limit: 50),
                    builder: (context, snap) {
                      final rows = snap.data ?? const [];
                      if (rows.isEmpty) {
                        return const Text(
                            'لا سجلات — لا خطأ مسجلاً بعد (سجل append-only '
                            'لا يحذف ولا يفرَّغ).');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('عدد السجلات الكلي: ظهور آخر 50 من ${rows.length}'),
                          const SizedBox(height: 8),
                          for (final r in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '[${r['code']}] ${r['message']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${r['context'] == null ? '' : 'السياق: ${r['context']} — '}'
                                    '${DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int? ?? 0)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── بطاقة مرجع الرموز ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                key: const ValueKey('diagnostics_registry'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مرجع الرموز DQ-xxxx',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'كل رمز برسالة رفض يعني مدخلاً بالمرجع أدناه — '
                    'و${diqqahUnclassifiedError.code} فاصلة ما ليس بالسجل.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final e in [...diqqahErrorCodes, diqqahUnclassifiedError])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e.code} — ${e.title}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text(e.guidance,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('diagnostics_share'),
            onPressed: () async {
              final rows = await db.recentErrors(limit: 50);
              await _share(versionText, rows);
            },
            icon: const Icon(Icons.share),
            label: const Text('مشاركة التشخيص'),
          ),
        ],
      ),
    );
  }
}
