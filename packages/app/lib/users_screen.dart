import 'package:flutter/material.dart';

import 'package:diqqah_domain/diqqah_domain.dart';
import 'package:diqqah_storage/diqqah_storage.dart';
import 'dq_log.dart';

/// شاشة المستخدمين — س211 (D-216) دفعة 1 من خطة الجلسة المعتمدة:
/// إنشاء المستخدمين وحالتهم — **المفتاح المفقود** الذي يسكن كل نقاش
/// التبديل: قبل هذه الشاشة كان الوحيدَ النافذ لإنشاء مستخدم
/// `createManager` بأول تشغيل حصراً، وشاشة الأدوار تعيّن الأدوار
/// لمستخدمين قائمين فحسب.
///
/// الحدود المعتمدة (D-216):
/// - الوليد أعري بنيوياً: دور «مستخدم» بلا أي وحدة، والراية
///   `must_change_password` مرفوعة فتُلزَم بتغيير كلمته عند أول جلسة —
///   وتعيين أدواره لاحقاً بباب «الصلاحيات» القائم بحدوده.
/// - قدرتان منفصلتان لا واحدة (فصل الأيدي): بوابة `users.create`
///   للإنشاء وبوابة `users.deactivate` للتعطيل والتفعيل — ومن مُنح
///   الوحدة وحدها يرى الشاشة قراءةً خالصة، والنجمة تشمل البوابتين.
/// - حمايات التعطيل الثلاث بالتخزين: الجلسة الحالية لا تُعطَّل بيدها،
///   وآخر مستخدم نشط لا يُعطَّل، ومستخدمُ دورٍ كامل الوحدات لا يُمس
///   بيدٍ غير كاملة الوحدات — والواجهة تعرض رسالة الرفض العربية كما هي.
class UsersScreen extends StatefulWidget {
  final DiqqahDatabase db;

  /// تكرارات الهاش لكلمة المرور الأولية — الافتراض العتبة الآمنة،
  /// والاختبارات تحقن قيماً صغيرة بنمط first_run الموثق.
  final int hasherIterations;

  const UsersScreen({
    super.key,
    required this.db,
    this.hasherIterations = PasswordHasher.secureIterations,
  });

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser>? _users;
  List<Role>? _roles;

  /// صلاحيات صاحب الجلسة — فراغها «قيد التحميل» فالزران معطلان حتى
  /// يجيب الدور (الفشل المغلق: لا فعل يُظهر قبل صلاحية).
  RolePermissions? _perms;
  List<String>? _errors;

  @override
  void initState() {
    super.initState();
    // قراءة لحظية واحدة عند الفتح — شاشة إدارية لا تدفق حي ولا مؤقتات
    // (درس CI: أي اشتراك بلا إلغاء محكم يعلق ضخّات الاختبار).
    _reload();
  }

  Future<void> _reload() async {
    final users = await widget.db.select(widget.db.appUsers).get();
    final roles = await widget.db.select(widget.db.roles).get();
    final session = await widget.db.currentUser();
    RolePermissions? perms;
    if (session != null) {
      final role = await widget.db.roleOf(session);
      if (role != null) perms = RolePermissions(role.permissions);
    }
    if (!mounted) return;
    setState(() {
      _users = users;
      _roles = roles;
      _perms = perms;
      _errors = null;
    });
  }

  bool get _canCreate => _perms?.allowsSub(kCreateUsersKey) ?? false;
  bool get _canToggle => _perms?.allowsSub(kDeactivateUsersKey) ?? false;

  /// حوار «مستخدم جديد» — الولادة بأقل امتياز: دور «مستخدم» بلا أي
  /// وحدة وإلزام تغيير الكلمة عند أول جلسة، وتفرد الدخول قيد القاعدة
  /// ذاته فالتكرار يُرفض برسالته.
  Future<void> _createUserDialog() async {
    final name = TextEditingController();
    final login = TextEditingController();
    final password = TextEditingController();
    final confirm = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('مستخدم جديد'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الظاهر',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: login,
                  decoration: const InputDecoration(
                    labelText: 'اسم الدخول',
                    border: OutlineInputBorder(),
                    helperText: 'فريد — التكرار يُرفض',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الأولية',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'يُولد بلا أي صلاحية بدور «$kBareUserRoleName» ويُلزَم '
                  'بتغيير كلمة مروره عند أول جلسة — وتعيين دوره لاحقاً من '
                  'شاشة «الصلاحيات».',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
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
              child: const Text('إنشاء المستخدم'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final trimmedName = name.text.trim();
    final trimmedLogin = login.text.trim();
    if (trimmedName.isEmpty ||
        trimmedLogin.isEmpty ||
        password.text.isEmpty) {
      if (!mounted) return;
      setState(() => _errors = <String>[
            'الاسم واسم الدخول والكلمة إلزامية — لا فراغات',
          ]);
      return;
    }
    if (password.text != confirm.text) {
      if (!mounted) return;
      setState(() => _errors = <String>['التأكيد لا يطابق الكلمة']);
      return;
    }
    try {
      final salt = PasswordHasher.newSalt();
      // س219: التجزئة بعزل الخلفية — لا تجميد واجهة عند إنشاء مستخدم
      // (عقد قابلية الإرسال س218 بالمدار ذاته: الإغلاق قيم بسيطة حصراً).
      final hash = await PasswordHasher.hashInBackground(
          password.text, salt,
          iterations: widget.hasherIterations);
      await widget.db.createUser(
        name: trimmedName,
        login: trimmedLogin,
        passwordHash:
            PasswordHasher.formatStored(salt, hash, widget.hasherIterations),
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أُنشئ المستخدم: $trimmedName')),
      );
    } catch (e) {
      await dqLog(widget.db, e, context: 'users.create');
      if (!mounted) return;
      setState(() => _errors = <String>['رفض الإنشاء: $e${dqTag(e)}']);
    }
  }

  /// التعطيل والتفعيل بطي الحالة — والرفض بالرسالة العربية للحماية
  /// الثلاث (الجلسة الحالية/آخر نشط/النجمة) كما يصوغها التخزين.
  Future<void> _toggleActive(AppUser user) async {
    try {
      await widget.db.setUserActive(user.id, !user.isActive);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(user.isActive
            ? 'عُطّل المستخدم: ${user.name}'
            : 'فُعّل المستخدم: ${user.name}')),
      );
    } catch (e) {
      await dqLog(widget.db, e, context: 'users.toggle');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('رفض التعطيل: $e${dqTag(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    final roles = _roles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المستخدمون'),
        actions: [
          IconButton(
            tooltip: 'مستخدم جديد',
            icon: const Icon(Icons.person_add_alt_outlined),
            onPressed: _canCreate ? () => _createUserDialog() : null,
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
                  'المستخدم الجديد يُولد بلا أي صلاحية بدور '
                  '«$kBareUserRoleName» ويُلزَم بتغيير كلمة مروره عند أول '
                  'جلسة — وتعيين الأدوار من شاشة «الصلاحيات». الجلسة '
                  'الحالية لا تُعطَّل بيدها، وآخر مستخدم نشط لا يُعطَّل، '
                  'ومستخدم كامل الوحدات لا يُمس بيدٍ غير كاملة الوحدات.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          if (_errors != null) Text(_errors!.join('\n')),
          if (users == null || roles == null)
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
                    '${user.isActive ? '' : ' — معطل'}'
                    '${user.mustChangePassword ? ' — يُلزَم بتغيير كلمته' : ''}'),
                trailing: IconButton(
                  tooltip: user.isActive ? 'تعطيل المستخدم' : 'تفعيل المستخدم',
                  icon: Icon(user.isActive
                      ? Icons.block_outlined
                      : Icons.check_circle_outline),
                  onPressed: _canToggle ? () => _toggleActive(user) : null,
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
