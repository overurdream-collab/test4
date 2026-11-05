import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});

  static const roles = ['كاشير', 'مشرف مبيعات', 'محاسب', 'مدير فرع'];
  static const allPermissions = [
    'تسجيل الديون',
    'تسجيل الدفعات',
    'عرض الكشوف',
    'إدارة العملاء',
    'إدارة الموظفين',
  ];

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفون والصلاحيات'),
        actions: [
          IconButton(
            tooltip: 'إضافة موظف',
            onPressed: () => _showAddEmployee(context, state),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: QSpace.xxl),
        children: [
          QResponsiveBody(
            maxWidth: 760,
            padding: const EdgeInsets.fromLTRB(
              QSpace.lg,
              QSpace.sm,
              QSpace.lg,
              QSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QCard(
                  gradient: const LinearGradient(
                    colors: [QColors.softMint, QColors.pureWhite],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: QColors.brightGreen,
                      ),
                      const SizedBox(width: QSpace.md),
                      Expanded(
                        child: Text(
                          'كل موظف يرى فقط ما تسمح به صلاحياته. '
                          'مالك الحساب يملك كل الصلاحيات دائماً.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                QSectionHeader(
                  title: 'الفريق',
                  subtitle: '${state.employees.length} موظفين',
                ),
                if (state.employees.isEmpty)
                  QStateView(
                    state: QDataState.empty,
                    title: 'لا يوجد موظفون',
                    message: 'أضف أول موظف وحدد صلاحياته بدقة.',
                    onRetry: () => _showAddEmployee(context, state),
                  )
                else
                  for (final employee in state.employees) ...[
                    _EmployeeCard(employee: employee),
                    const SizedBox(height: QSpace.md),
                  ],
                const SizedBox(height: QSpace.md),
                OutlinedButton.icon(
                  onPressed: () => _showAddEmployee(context, state),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('إضافة موظف'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddEmployee(BuildContext context, AppState state) async {
    final pageContext = context;
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String role = roles.first;
    final permissions = <String>{'تسجيل الديون', 'تسجيل الدفعات'};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: QSpace.xl,
            right: QSpace.xl,
            top: QSpace.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + QSpace.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QSheetHeader(
                  title: 'موظف جديد',
                  subtitle: 'حدد الدور والصلاحيات بوضوح',
                  onClose: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: QSpace.lg),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الموظف',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: QSpace.md),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم الجوال',
                    prefixIcon: Icon(Icons.phone_iphone_rounded),
                  ),
                ),
                const SizedBox(height: QSpace.md),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'الدور',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: [
                    for (final role in roles)
                      DropdownMenuItem(value: role, child: Text(role)),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => role = value);
                  },
                ),
                const SizedBox(height: QSpace.md),
                Text(
                  'الصلاحيات',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: QSpace.sm),
                Wrap(
                  spacing: QSpace.sm,
                  runSpacing: QSpace.sm,
                  children: [
                    for (final permission in allPermissions)
                      FilterChip(
                        label: Text(permission),
                        selected: permissions.contains(permission),
                        onSelected: (selected) {
                          setSheetState(() {
                            if (selected) {
                              permissions.add(permission);
                            } else {
                              permissions.remove(permission);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: QSpace.lg),
                QGradientButton(
                  label: 'حفظ الموظف',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        phoneController.text.trim().length < 8) {
                      QToast.show(
                        context,
                        'أدخل الاسم ورقم الجوال',
                        error: true,
                      );
                      return;
                    }
                    state.addEmployee(
                      name: nameController.text.trim(),
                      phone: phoneController.text.trim(),
                      role: role,
                      permissions: {...permissions},
                    );
                    Navigator.of(context).pop();
                    QToast.show(pageContext, 'تمت إضافة الموظف');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QAvatar(label: employee.name, size: 48),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${employee.role} • ${employee.phone}',
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: employee.active,
                onChanged: (_) => state.toggleEmployee(employee.id),
              ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          Wrap(
            spacing: QSpace.xs,
            runSpacing: QSpace.xs,
            children: [
              for (final permission in employee.permissions)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: QSpace.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: QColors.softMint,
                    borderRadius: BorderRadius.circular(QRadius.pill),
                  ),
                  child: Text(
                    permission,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: QColors.approvedFg),
                  ),
                ),
            ],
          ),
          if (!employee.active) ...[
            const SizedBox(height: QSpace.sm),
            Text(
              'الحساب موقوف مؤقتاً ولا يمكنه تسجيل عمليات.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: QColors.rejectedFg),
            ),
          ],
        ],
      ),
    );
  }
}
