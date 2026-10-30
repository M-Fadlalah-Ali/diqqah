import 'package:flutter/material.dart';

import 'package:diqqah_storage/diqqah_storage.dart';

/// شاشة الصلاحيات — دفعة (6-ج) واجهات الإدخال (س-94، D-097 معروض):
/// عرض قراءة حصراً للأدوار ومستخدميها — الجداول جاهزة من م0 والتنفيذ
/// التفصيلي لصلاحيات الشاشات دفعة تالية بيد المالك (D-093/D-090 إفصاحاً).
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

  @override
  Widget build(BuildContext context) {
    final roles = _roles;
    final users = _users;
    return Scaffold(
      appBar: AppBar(title: const Text('الصلاحيات')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  'العرض قراءة حصراً — صلاحيات الشاشات التفصيلية تنفذ '
                  'بطبقة الواجهة في دفعة تالية بيد المالك (D-093 إفصاحاً)',
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
                    '${_users?.where((u) => u.roleId == role.id).length ?? 0} مستخدم'),
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
                    ' · دور #${user.roleId}'
                    '${user.isActive ? '' : ' — معطل'}'),
              ),
        ],
      ),
    );
  }
}
