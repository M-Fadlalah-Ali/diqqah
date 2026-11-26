/// شاشة العمل الجماعي والمزامنة — د6 (س175 — الاستيعاب الواجهي
/// والأحمال الختامية بنص خارطة م4 §46): النافذة الواجهية للانضمام
/// والأرشفة والإبطال المُحالة من د5 (س174) بحدّها الصادق الموثق.
///
/// **ما تديره هذه النافذة فعلاً**: السجلان المحليان بعقدهما النقية —
/// كتاب رموز الانضمام م-32 (sync_membership.dart: المدير من جهاز
/// موثوق واستهلاك واحد وصلاحية 24 ساعة) وسجل الأجهزة م-33 (إبطال
/// فوري قلبَ حالة لا حذف وتاريخ باقٍ وخيار «مسح عند أول اتصال» على
/// المُبطَل حصراً وإعادة الثقة الصريحة) — وهما الحكم المحلي الموازي
/// للخادم عقد F-136 «لا يثق أحد بطرفٍ آخر»، وحالة الأرشفة السحابية
/// الدورية F-137/م-31 (الإيقاع اليومي بنمط اللحاق والاحتفاظ بآخر 30).
///
/// **الحد الصادق الموثق (لا يزعَم هنا)**: الفرض الخادمي — رفض
/// المُبطَل عند النقل واستهلاك الرمز عند أول اتصال وتنفيذ أمر المسح
/// — موضع المهايئ والخادم (د4) بتصديق مكتوب عرف D-211 عند س-25؛
/// والرفع السحابي الفعلي يتطلب مزوّد مزامنة مضبوطاً. فلا زر يزعم
/// رفعاً ولا استهلاكاً لا يحدثان.
///
/// **الفساد يفشل مقفلاً لا يُصمت**: كتاب الرموز وسجل الأجهزة فاسدٌ
/// برسالة مفهرسة (DQ-1116/DQ-1117) — سجل الإبطال حماية فلا إعادة
/// بناء بالمسح (نقيض الكتالوج — والفرق مقصود موثق).
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

import 'adaptive.dart';
import 'session.dart';

/// حالة الأرشفة السحابية المحفوظة — قراءة دفاعية: الفاسد يعود فارغاً
/// قابل لإعادة البناء (حالة عرض لا سجل حماية).
class CloudArchiveUiState {
  final DateTime? lastAttemptUtc;
  final DateTime? lastSuccessUtc;
  final String? lastError;

  const CloudArchiveUiState({
    this.lastAttemptUtc,
    this.lastSuccessUtc,
    this.lastError,
  });

  static CloudArchiveUiState parse(String? text) {
    if (text == null || text.trim().isEmpty) {
      return const CloudArchiveUiState();
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) {
        return const CloudArchiveUiState();
      }
      DateTime? dt(Object? v) {
        final d = DateTime.tryParse('$v');
        return (d != null && d.isUtc) ? d : null;
      }

      return CloudArchiveUiState(
        lastAttemptUtc: dt(decoded['lastAttemptUtc']),
        lastSuccessUtc: dt(decoded['lastSuccessUtc']),
        lastError: decoded['lastError'] is String &&
                '${decoded['lastError']}'.isNotEmpty
            ? '${decoded['lastError']}'
            : null,
      );
    } catch (_) {
      return const CloudArchiveUiState();
    }
  }
}

/// بطاقة الإعدادات — نهاية القائمة (درس D-098/س107: الجديد بنهاية
/// القائمة فلا تُزيح بنداً ولا ميزانية سحب).
class SyncWorkCard extends StatelessWidget {
  final DiqqahDatabase db;

  const SyncWorkCard({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: const ValueKey('settings_sync_work'),
        leading: const Icon(Icons.devices_other_outlined),
        title: const Text('العمل الجماعي والمزامنة'),
        subtitle: const Text(
            'رمز الانضمام وسجل الأجهزة والأرشفة السحابية الدورية — '
            'نافذة العضوية م-32/م-33 والأرشفة م-31.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SyncWorkScreen(db: db),
            ),
          );
        },
      ),
    );
  }
}

/// صياغة لحظة UTC باللسان الموثق — المحلي عرضاً لا حاكماً.
String fmtUtc(DateTime utc) {
  final local = utc.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// شاشة العضوية — الإصدار والإبطال والأرشفة بأفعالها المحقونة.
class SyncWorkScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// محمّل محقون للاختبار — الافتراضي القراءة من القاعدة.
  final Future<SyncWorkSnapshot> Function()? loadOverride;

  const SyncWorkScreen({super.key, required this.db, this.loadOverride});

  @override
  State<SyncWorkScreen> createState() => _SyncWorkScreenState();
}

/// لقطة النافذة المحمّلة — كل سجل مستقل الحضور.
class SyncWorkSnapshot {
  final String deviceId;
  final bool isManager;
  final int? userId;
  final JoinCodeBook? book;
  final SyncDeviceRegistry? registry;
  final CloudArchiveUiState archive;
  final String? bookError;
  final String? registryError;

  const SyncWorkSnapshot({
    required this.deviceId,
    required this.isManager,
    required this.userId,
    this.book,
    this.registry,
    required this.archive,
    this.bookError,
    this.registryError,
  });
}

Future<SyncWorkSnapshot> loadSyncWork(DiqqahDatabase db) async {
  final deviceId = await db.deviceId();
  final session = await loadSession(db);
  final isManager = session?.permissions.isAll ?? false;
  JoinCodeBook? book;
  String? bookError;
  final bookText = await db.joinCodeBookText();
  if (bookText != null) {
    try {
      book = JoinCodeBook.fromJson(bookText);
    } catch (e) {
      bookError = '$e';
    }
  }
  SyncDeviceRegistry? registry;
  String? registryError;
  final registryText = await db.deviceRegistryText();
  if (registryText != null) {
    try {
      registry = SyncDeviceRegistry.fromJson(registryText);
    } catch (e) {
      registryError = '$e';
    }
  }
  final archive =
      CloudArchiveUiState.parse(await db.cloudArchiveStateText());
  return SyncWorkSnapshot(
    deviceId: deviceId,
    isManager: isManager,
    userId: session?.user.id,
    book: book,
    registry: registry,
    archive: archive,
    bookError: bookError,
    registryError: registryError,
  );
}

class _SyncWorkScreenState extends State<SyncWorkScreen> {
  SyncWorkSnapshot? _snapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _reload() async {
    final snap = widget.loadOverride != null
        ? await widget.loadOverride!()
        : await loadSyncWork(widget.db);
    if (!mounted) return;
    setState(() => _snapshot = snap);
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// إصدار رمز انضمام نص م-32 — المدير من جهاز موثوق حصراً.
  Future<void> _issueCode() async {
    final snap = _snapshot;
    if (snap == null || !snap.isManager) return;
    await _mutate(() async {
      final text = await widget.db.joinCodeBookText();
      final book =
          text == null ? JoinCodeBook() : JoinCodeBook.fromJson(text);
      final record = book.issue(
        issuedByDeviceId: snap.deviceId,
        nowUtc: DateTime.now().toUtc(),
        issuedByManager: true,
      );
      await widget.db.saveJoinCodeBookText(book.toJson());
      // القرار موثق كحدث — ذيل الرمز حصراً فلا سرّ بكامل نصه بالسجل
      // (الرمز نفسه بحوزة المدير للعرض اللحظي واستهلاكه واحد).
      await widget.db.recordSystemEvent('join_code_issued',
          userId: snap.userId,
          payload: {
            'code_tail': record.code.substring(record.code.length - 4),
            'expires_utc': record.expiresAtUtc.toIso8601String(),
          });
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('رمز انضمام جديد: ${formatJoinCode(record.code)} '
                '— صالح 24 ساعة واستهلاك واحد'),
            duration: const Duration(seconds: 5),
          ));
      }
    });
  }

  /// إبطال جهاز نص م-33 — قلب حالة لا حذف وبلحظة واحدة رابتة.
  Future<void> _revokeDevice(SyncDeviceRecord record) async {
    final snap = _snapshot;
    if (snap == null || !snap.isManager) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إبطال الجهاز «${record.deviceId}»'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'السبب (اختياري)',
            helperText: 'نصك يوثق بالسجل — الإبطال فوري وتاريخ الجهاز '
                'يبقى بلا حذف',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إبطال'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _mutate(() async {
      final text = await widget.db.deviceRegistryText();
      final registry = text == null
          ? SyncDeviceRegistry()
          : SyncDeviceRegistry.fromJson(text);
      final reason = reasonCtrl.text.trim();
      registry.revoke(
        deviceId: record.deviceId,
        atUtc: DateTime.now().toUtc(),
        reason: reason.isEmpty ? null : reason,
      );
      await widget.db.saveDeviceRegistryText(registry.toJson());
      await widget.db.recordSystemEvent('sync_device_revoked',
          userId: snap.userId,
          payload: {
            'device': record.deviceId,
            if (reason.isNotEmpty) 'reason': reason,
          });
    });
  }

  /// «مسح عند أول اتصال» نص م-33 — على المُبطَل حصراً.
  Future<void> _markWipe(SyncDeviceRecord record) async {
    final snap = _snapshot;
    if (snap == null || !snap.isManager) return;
    await _mutate(() async {
      final text = await widget.db.deviceRegistryText();
      final registry = text == null
          ? SyncDeviceRegistry()
          : SyncDeviceRegistry.fromJson(text);
      registry.markWipeOnFirstContact(record.deviceId);
      await widget.db.saveDeviceRegistryText(registry.toJson());
      await widget.db.recordSystemEvent('sync_device_wipe_marked',
          userId: snap.userId, payload: {'device': record.deviceId});
    });
  }

  /// إعادة الثقة الصريحة — قرار مدير موثق كحدث والعلم القديم ينطفئ.
  Future<void> _retrust(SyncDeviceRecord record) async {
    final snap = _snapshot;
    if (snap == null || !snap.isManager) return;
    await _mutate(() async {
      final text = await widget.db.deviceRegistryText();
      final registry = text == null
          ? SyncDeviceRegistry()
          : SyncDeviceRegistry.fromJson(text);
      registry.retrust(
        deviceId: record.deviceId,
        atUtc: DateTime.now().toUtc(),
      );
      await widget.db.saveDeviceRegistryText(registry.toJson());
      await widget.db.recordSystemEvent('sync_device_retrusted',
          userId: snap.userId, payload: {'device': record.deviceId});
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('العمل الجماعي والمزامنة')),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
                  16,
                  diqqahAdaptiveHorizontalMargin(context, baseMargin: 16),
                  16),
              key: const ValueKey('sync_work_list'),
              children: [
                _statusCard(snap),
                _joinCodeCard(snap),
                _devicesCard(snap),
                _archiveCard(snap),
              ],
            ),
    );
  }

  Widget _statusCard(SyncWorkSnapshot snap) {
    final prefix = snap.registry?.byId(snap.deviceId)?.prefix;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هذا الجهاز',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('المعرف: ${snap.deviceId}'),
            if (prefix != null) Text('بادئة الترقيم: $prefix'),
            Text(
                'الدور: ${snap.isManager ? 'مدير — كل الوحدات' : 'بلا إصدار رموز'}'),
            const SizedBox(height: 8),
            Text('المزوّد: لا مزوّد مضبوطاً بعد — المهايئ جاهز '
                'والضبط عند أول خادم حي بتصديق مكتوب'),
          ],
        ),
      ),
    );
  }

  Widget _joinCodeCard(SyncWorkSnapshot snap) {
    final records = [...snap.book?.records ?? const <JoinCodeRecord>[]]
      ..sort((a, b) => b.issuedAtUtc.compareTo(a.issuedAtUtc));
    final visible = records.take(5).toList();
    final now = DateTime.now().toUtc();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('رمز الانضمام',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (snap.isManager)
                  FilledButton.icon(
                    key: const ValueKey('sync_issue_code'),
                    onPressed: _busy ? null : _issueCode,
                    icon: const Icon(Icons.qr_code_2_outlined),
                    label: const Text('إصدار رمز'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('المدير يولده من جهاز موثوق — استهلاك واحد وصلاحية '
                '24 ساعة بنمط XXXX-XXXX بلا ملتبس (لا 0/O ولا 1/I/L).'),
            if (snap.bookError != null) ...[
              const SizedBox(height: 8),
              Text(
                'كتاب الرموز فاسد بلا تشغيل: ${snap.bookError}',
                key: const ValueKey('sync_book_error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا رموز مصدرة بعد.'),
              )
            else
              for (final r in visible)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pin_outlined),
                  title: Text(formatJoinCode(r.code)),
                  subtitle: Text(
                      'أُصدر ${fmtUtc(r.issuedAtUtc)} — ينتهي '
                      '${fmtUtc(r.expiresAtUtc)}'),
                  trailing: Text(
                    r.isConsumed
                        ? 'مستهلك${r.consumedByDeviceId == null ? '' : ' من ${r.consumedByDeviceId}'}'
                        : (now.isAfter(r.expiresAtUtc)
                            ? 'منتهي'
                            : 'بانتظار الاستهلاك'),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _devicesCard(SyncWorkSnapshot snap) {
    final devices = [...snap.registry?.devices ?? const <SyncDeviceRecord>[]];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سجل الأجهزة',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('الإبطال فوري قلبَ حالة لا حذف — تاريخ كل جهاز '
                'يبقى إلى الأبد، وإعادة الثقة قرار مدير صريح، وخيار '
                '«مسح عند أول اتصال» على المُبطَل حصراً.'),
            if (snap.registryError != null) ...[
              const SizedBox(height: 8),
              Text(
                'سجل الأجهزة فاسد بلا تشغيل: ${snap.registryError}',
                key: const ValueKey('sync_registry_error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا أجهزة مسجلة بعد.'),
              )
            else
              for (final d in devices)
                ListTile(
                  key: ValueKey('sync_device_${d.deviceId}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    d.status == SyncDeviceStatus.active
                        ? Icons.phone_android_outlined
                        : Icons.phone_disabled_outlined,
                    color: d.status == SyncDeviceStatus.active
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: Text(d.deviceId),
                  subtitle: Text([
                    if (d.joinedAtUtc != null)
                      'انضم ${fmtUtc(d.joinedAtUtc!)}',
                    if (d.prefix != null) 'بادئة ${d.prefix}',
                    if (d.revokedAtUtc != null)
                      'أُبطل ${fmtUtc(d.revokedAtUtc!)}'
                          '${d.revokeReason == null ? '' : ' — ${d.revokeReason}'}',
                    if (d.wipeOnFirstContact)
                      'مسح عند أول اتصال مفعّل',
                  ].join(' · ')),
                  trailing: snap.isManager
                      ? _deviceActions(d)
                      : Text(d.status == SyncDeviceStatus.active
                          ? 'نشط'
                          : 'مُبطَل'),
                ),
          ],
        ),
      ),
    );
  }

  Widget _deviceActions(SyncDeviceRecord d) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (d.status == SyncDeviceStatus.active)
          TextButton(
            key: ValueKey('sync_revoke_${d.deviceId}'),
            onPressed: _busy ? null : () => _revokeDevice(d),
            child: const Text('إبطال'),
          ),
        if (d.status == SyncDeviceStatus.revoked) ...[
          TextButton(
            key: ValueKey('sync_retrust_${d.deviceId}'),
            onPressed: _busy ? null : () => _retrust(d),
            child: const Text('إعادة ثقة'),
          ),
          if (!d.wipeOnFirstContact)
            TextButton(
              key: ValueKey('sync_wipe_${d.deviceId}'),
              onPressed: _busy ? null : () => _markWipe(d),
              child: const Text('مسح عند أول اتصال'),
            ),
        ],
      ],
    );
  }

  Widget _archiveCard(SyncWorkSnapshot snap) {
    final a = snap.archive;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الأرشفة السحابية الدورية',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('نسخة كاملة مشفرة ترفع آلياً يومياً عند توفر '
                'الاتصال مع الاحتفاظ بآخر 30 نسخة — والحذف بعد نجاح '
                // الرمز DQ-1118 للسجل والمرجع لا نص المستخدم (س204 — م03).
                'الجديدة وتحققها فلا فجوة سحابية، وكل ما يصعد يفتحه '
                'بوابة الاستعادة القائمة ذاتها.'),
            const SizedBox(height: 8),
            Text(a.lastSuccessUtc == null
                ? 'آخر نجاح: لا أرشفة بعد'
                : 'آخر نجاح: ${fmtUtc(a.lastSuccessUtc!)}'),
            if (a.lastAttemptUtc != null)
              Text('آخر محاولة: ${fmtUtc(a.lastAttemptUtc!)}'),
            if (a.lastError != null)
              Text('آخر خطأ: ${a.lastError}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            // بلا مزوّد مضبوط فلا اتصال أصلاً — الاستحقاق «بانتظار
            // الاتصال» تأجيل موثق نص F-137 لا رفض ولا صمت ولا «مغطى»
            // زائفاً (الدالة تعيد false بلا اتصال فالفرقان يُفصلان
            // هنا بلسان الحقيقة).
            const Text('الاستحقاق: بانتظار الاتصال — غيابه تأجيل موثق '
                'نص F-137 لا رفض ولا صمت'),
            const SizedBox(height: 8),
            Text('الرفع الفعلي يتطلب مزوّد مزامنة مضبوطاً — بلا زر يزعم '
                'رفعاً لا يحدث (حد د6 الصادق).',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
