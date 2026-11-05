import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../admin/admin_dashboard_screen.dart';
import '../merchant/employees_screen.dart';
import '../merchant/suppliers_screen.dart';
import '../shared/brand_gallery_screen.dart';
import '../shared/devices_screen.dart';
import '../shared/photos_screen.dart';
import '../shared/profile_switch_sheet.dart';
import '../shared/states_gallery_screen.dart';
import '../shared/statement_screen.dart';
import 'plans_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isMerchant = state.persona == AppPersona.merchant;
    final plan = state.plans.isEmpty
        ? null
        : state.plans[state.currentPlanIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        actions: [
          IconButton(
            tooltip: 'تبديل الملف',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(QRadius.xl),
                ),
              ),
              builder: (_) => const ProfileSwitchSheet(),
            ),
            icon: const Icon(Icons.swap_horiz_rounded),
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
                _ProfileCard(state: state),
                const SizedBox(height: QSpace.lg),
                const _SectionLabel(label: 'التفضيلات'),
                QCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.dark_mode_outlined),
                        title: const Text('الوضع الداكن'),
                        subtitle: const Text(
                          'تبديل بين الواجهة الفاتحة والداكنة',
                        ),
                        value: state.themeMode == ThemeMode.dark,
                        onChanged: state.setDark,
                      ),
                      const Divider(),
                      SwitchListTile(
                        secondary: const Icon(Icons.visibility_off_outlined),
                        title: const Text('إخفاء المبالغ'),
                        subtitle: const Text(
                          'مناسب عند فتح التطبيق أمام الآخرين',
                        ),
                        value: state.hideAmounts,
                        onChanged: (_) => state.toggleHideAmounts(),
                      ),
                      const Divider(),
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_none_rounded),
                        title: const Text('إشعارات التطبيق'),
                        subtitle: const Text('العمليات والموافقات الجديدة'),
                        value: state.appNotificationsEnabled,
                        onChanged: state.toggleAppNotifications,
                      ),
                      const Divider(),
                      SwitchListTile(
                        secondary: const Icon(Icons.alarm_rounded),
                        title: const Text('تذكيرات الديون'),
                        subtitle: const Text('تنبيه لطيف بالمبالغ المعلقة'),
                        value: state.reminderNotificationsEnabled,
                        onChanged: state.toggleReminderNotifications,
                      ),
                    ],
                  ),
                ),
                if (isMerchant) ...[
                  const SizedBox(height: QSpace.lg),
                  const _SectionLabel(label: 'إدارة النشاط'),
                  QCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SettingsTile(
                          icon: Icons.store_mall_directory_outlined,
                          title: 'الموردون',
                          subtitle: '${state.suppliers.length} مورد',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SuppliersScreen(),
                            ),
                          ),
                        ),
                        const Divider(),
                        _SettingsTile(
                          icon: Icons.badge_outlined,
                          title: 'الموظفون والصلاحيات',
                          subtitle: '${state.employees.length} موظف',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const EmployeesScreen(),
                            ),
                          ),
                        ),
                        const Divider(),
                        _SettingsTile(
                          icon: Icons.photo_library_outlined,
                          title: 'صور اليوم',
                          subtitle:
                              '${state.todayPhotos} من ${state.dailyPhotoLimit} صور',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PhotosScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: QSpace.lg),
                const _SectionLabel(label: 'الحساب والاشتراك'),
                QCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.workspace_premium_outlined,
                        title: 'الباقة الحالية',
                        subtitle: plan?.name ?? 'غير محددة',
                        badge: state.subscriptionActive ? 'نشط' : 'منتهٍ',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PlansScreen(),
                          ),
                        ),
                      ),
                      const Divider(),
                      _SettingsTile(
                        icon: Icons.description_outlined,
                        title: 'كشف الحساب',
                        subtitle: 'تصدير ومراجعة كل الحركات',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StatementScreen(),
                          ),
                        ),
                      ),
                      const Divider(),
                      _SettingsTile(
                        icon: Icons.devices_outlined,
                        title: 'الأجهزة والجلسات',
                        subtitle: '${state.sessions.length} أجهزة مرتبطة',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DevicesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                const _SectionLabel(label: 'الهوية والتجربة'),
                QCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.auto_awesome_mosaic_outlined,
                        title: 'مفاهيم الشعار',
                        subtitle: 'ثلاثة اتجاهات بصرية جاهزة',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BrandGalleryScreen(),
                          ),
                        ),
                      ),
                      const Divider(),
                      _SettingsTile(
                        icon: Icons.grid_view_rounded,
                        title: 'معرض حالات الواجهة',
                        subtitle: 'فارغ • تحميل • خطأ • دون إنترنت',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StatesGalleryScreen(),
                          ),
                        ),
                      ),
                      const Divider(),
                      _SettingsTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'معاينة لوحة الإدارة',
                        subtitle: 'واجهة ويب مستقلة',
                        badge: 'Web',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdminDashboardScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                QCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.help_outline_rounded,
                        title: 'المساعدة والدعم',
                        subtitle: 'الأسئلة الشائعة وسياسة النزاعات',
                        onTap: () => _showInfo(
                          context,
                          'المساعدة',
                          'فريق QAT LINK متاح لمساعدتك في إدارة حسابك. '
                              'تُحل النزاعات عبر طلب رسمي من كشف الحساب، '
                              'ويحتفظ النظام بسجل كامل للحركات.',
                        ),
                      ),
                      const Divider(),
                      _SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'الخصوصية',
                        subtitle: 'كيف نحمي بياناتك',
                        onTap: () => _showInfo(
                          context,
                          'الخصوصية',
                          'بياناتك ملكك. لا نبيع بياناتك ولا نشاركها مع أطراف '
                              'ثالثة. تُشفّر الاتصالات، وتُحفظ الصور لمدة محددة '
                              'قابلة للحذف.',
                        ),
                      ),
                      const Divider(),
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        title: 'حول QAT LINK',
                        subtitle: 'الإصدار 1.0.0 • تجريبي',
                        onTap: () => _showInfo(
                          context,
                          'QAT LINK',
                          'دفتر مشترك بين التاجر والعميل. '
                              'أنت تسجل.. وأنا أعتمد. '
                              'الإصدار التجريبي 1.0.0.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    state.logout();
                  },
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: QColors.rejectedFg,
                  ),
                  label: const Text(
                    'تسجيل الخروج',
                    style: TextStyle(color: QColors.rejectedFg),
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                Center(
                  child: Text(
                    'QAT LINK • قات لينك • 2026',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return QCard(
      gradient: const LinearGradient(
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Row(
        children: [
          QAvatar(label: state.user.name, size: 58),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.user.storeName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  state.user.name,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${state.user.category} • ${state.user.address}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تبديل الملف',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(QRadius.xl),
                ),
              ),
              builder: (_) => const ProfileSwitchSheet(),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: QSpace.sm, top: QSpace.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: QColors.brightGreen,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: QColors.softMint,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, size: 21, color: QColors.brightGreen),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: QSpace.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: QColors.pendingBg,
                borderRadius: BorderRadius.circular(QRadius.pill),
              ),
              child: Text(
                badge!,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: QColors.pendingFg),
              ),
            ),
            const SizedBox(width: QSpace.sm),
          ],
          const Icon(Icons.chevron_left_rounded),
        ],
      ),
    );
  }
}
