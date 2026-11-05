import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import 'settings_screen.dart';

class ProfileSwitchSheet extends StatelessWidget {
  const ProfileSwitchSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(QSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QSheetHeader(
              title: 'تبديل الحساب',
              subtitle: 'حساب واحد • ملفان مرتبطان',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: QSpace.lg),
            QCard(
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
                          state.user.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          state.user.phone,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.verified_rounded,
                    color: QColors.brightGreen,
                  ),
                ],
              ),
            ),
            const SizedBox(height: QSpace.lg),
            Text(
              'اختر الملف النشط',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: QSpace.sm),
            _ProfileTile(
              title: 'التاجر',
              subtitle: state.user.storeName,
              icon: Icons.storefront_rounded,
              selected: state.persona == AppPersona.merchant,
              onTap: () {
                state.setPersona(AppPersona.merchant);
                Navigator.of(context).pop();
                QToast.show(context, 'تم التبديل إلى ملف التاجر');
              },
            ),
            const SizedBox(height: QSpace.sm),
            _ProfileTile(
              title: 'العميل',
              subtitle: 'متابعة أرصدتك لدى التجار',
              icon: Icons.shopping_bag_outlined,
              selected: state.persona == AppPersona.customer,
              onTap: () {
                state.setPersona(AppPersona.customer);
                Navigator.of(context).pop();
                QToast.show(context, 'تم التبديل إلى ملف العميل');
              },
            ),
            const SizedBox(height: QSpace.lg),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('إدارة الملف والاشتراك'),
            ),
            const SizedBox(height: QSpace.sm),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                state.logout();
              },
              icon: const Icon(Icons.logout_rounded, color: QColors.rejectedFg),
              label: const Text(
                'تسجيل الخروج',
                style: TextStyle(color: QColors.rejectedFg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return QCard(
      onTap: onTap,
      borderColor: selected
          ? QColors.brightGreen
          : Theme.of(context).colorScheme.outlineVariant,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: selected
                  ? QColors.gradient
                  : const LinearGradient(
                      colors: [QColors.softMint, QColors.pureWhite],
                    ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: selected ? QColors.charcoal : QColors.brightGreen,
            ),
          ),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: QColors.brightGreen)
          else
            const Icon(Icons.chevron_left_rounded),
        ],
      ),
    );
  }
}
