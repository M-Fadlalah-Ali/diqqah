import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';

/// شاشة الصلاحيات — الكتابة الكاملة (F-080، دفعة إغلاق النواة س37).
///
/// كانت بالعرض القراءة حصراً (س-94، D-097) بوصف التنفيذ دفعة تالية —
/// وهذه هي الدفعة: الأدوار النمطية الأربعة مزروعة بأذوناتها الافتراضية
/// (D-100 معروض)، وإنشاء أدوار مخصصة وتعديل أذونات أي دور وتعيين الدور
/// للمستخدمين من هنا — والفرض على الشاشة الهيكلية فوري لصاحب الجلسة
/// (بإعادة بنائها) ولبقية المستخدمين عند تبديل الجلسة بكلمة المرور
/// من الإعدادات.
class RolesScreen extends StatefulWidget {
  final DiqqahDatabase db;

  const RolesScreen({super.key, required this.db});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  List<Role>? _roles;
  List<AppUser>? _users;
  List<String>? _errors;

  @override
  void initState() {
    super.initState();
    // قراءة لحظية واحدة عند الفتح — شاشة إدارية لا تدفق حي ولا مؤقتات
    // (درس CI: أي اشتراك بلا إلغاء محكم يعلق ضخّات الاختبار).
    _reload();
  }

  Future<void> _reload() async {
    final roles = await widget.db.select(widget.db.roles).get();
    final users = await widget.db.select(widget.db.appUsers).get();
    if (!mounted) return;
    setState(() {
      _roles = roles;
      _users = users;
      _errors = null;
    });
  }

  /// حوار أذونات دور — للإنشاء (اسم فارغ) وللتعديل (الدور القائم).
  /// المربعات على مفاتيح الوحدات الخمسة عشر بترتيبها، والنجمة «كل
  /// الوحدات» تُعرض بهذه الصيغة عند الحفظ إذا كُلّها مختارة.
  Future<void> _permissionsDialog({Role? role}) async {
    final nameController = TextEditingController(text: role?.name ?? '');
    final selected = <String>{
      ...(role == null
          ? <String>[]
          : RolePermissions(role.permissions).keys),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(role == null ? 'دور جديد' : 'أذونات الدور «${role.name}»'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (role == null)
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الدور',
                      border: OutlineInputBorder(),
                      helperText: 'فريد — التكرار يُرفض',
                    ),
                  ),
                if (role == null) const SizedBox(height: 8),
                for (final key in moduleKeys)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(key),
                    title: Text(moduleLabels[key] ?? key),
                    onChanged: (v) => setDialogState(() => v == true
                        ? selected.add(key)
                        : selected.remove(key)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(role == null ? 'إنشاء الدور' : 'حفظ الأذونات'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      final permissions = RolePermissions.format(selected);
      if (role == null) {
        await widget.db.createRole(
          name: nameController.text.trim(),
          permissions: permissions,
        );
      } else {
        await widget.db.updateRolePermissions(role.id, permissions);
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors = <String>['رفض الإنشاء: $e']);
    }
  }

  /// تعيين دور لمستخدم — قائمة الأدوار القائمة حصراً (لا إنشاء من هنا).
  Future<void> _assignRoleDialog(AppUser user, List<Role> roles) async {
    int? chosen = user.roleId;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('دور المستخدم «${user.name}»'),
          content: DropdownButton<int>(
            isExpanded: true,
            value: chosen,
            items: [
              for (final role in roles)
                DropdownMenuItem(value: role.id, child: Text(role.name)),
            ],
            onChanged: (id) => setDialogState(() => chosen = id),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تعيين'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || chosen == null || chosen == user.roleId) return;
    await widget.db.updateUserRole(user.id, chosen!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final roles = _roles;
    final users = _users;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصلاحيات'),
        actions: [
          IconButton(
            tooltip: 'دور جديد',
            icon: const Icon(Icons.add),
            onPressed: () => _permissionsDialog(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  'الأدوار النمطية الأربعة مزروعة بأذوناتها الافتراضية '
                  '(F-080/D-100 معروض): مدير الكل، ومحاسب المحاسبة كلها، '
                  'وأمين مستودع الأصناف والتقارير، وبائع الأطراف والفواتير '
                  'والسندات. عدّل ما شئت — والفرض على الرئيسية لصاحب '
                  'الجلسة فور إغلاقها.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          if (_errors != null) Text(_errors!.join('\n')),
          Text('الأدوار', style: Theme.of(context).textTheme.titleMedium),
          if (roles == null)
            const Center(child: CircularProgressIndicator())
          else if (roles.isEmpty)
            const ListTile(title: Text('لا أدوار بعد'))
          else
            for (final role in roles)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(role.name),
                subtitle: Text(
                    '${_users?.where((u) => u.roleId == role.id).length ?? 0} '
                    'مستخدم · الأذونات: '
                    '${RolePermissions(role.permissions).summary}'),
                trailing: IconButton(
                  tooltip: 'تعديل الأذونات',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _permissionsDialog(role: role),
                ),
              ),
          const Divider(),
          Text('المستخدمون',
              style: Theme.of(context).textTheme.titleMedium),
          if (users == null)
            const Center(child: CircularProgressIndicator())
          else if (users.isEmpty)
            const ListTile(title: Text('لا مستخدمين بعد'))
          else
            for (final user in users)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(user.name),
                subtitle: Text(
                    'دخوله: ${user.login}'
                    ' · دور: ${_roleName(roles, user.roleId)}'
                    '${user.isActive ? '' : ' — معطل'}'),
                trailing: IconButton(
                  tooltip: 'تغيير الدور',
                  icon: const Icon(Icons.manage_accounts_outlined),
                  onPressed: roles == null || roles.isEmpty
                      ? null
                      : () => _assignRoleDialog(user, roles),
                ),
              ),
        ],
      ),
    );
  }

  String _roleName(List<Role>? roles, int roleId) {
    for (final role in roles ?? const <Role>[]) {
      if (role.id == roleId) return role.name;
    }
    return 'دور #$roleId';
  }
}
