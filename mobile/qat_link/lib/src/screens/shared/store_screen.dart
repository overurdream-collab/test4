import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../customer/customer_merchants_screen.dart';
import '../customer/payment_screen.dart';
import '../merchant/employees_screen.dart';
import '../merchant/reports_screen.dart';
import 'notifications_screen.dart';
import 'photos_screen.dart';
import 'settings_screen.dart';
import 'statement_screen.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isMerchant = state.persona == AppPersona.merchant;
    final entries = isMerchant ? state.merchantEntries : state.customerEntries;

    return Scaffold(
      appBar: AppBar(
        title: Text(isMerchant ? 'متجري' : 'حسابي'),
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
            icon: Badge(
              isLabelVisible: state.unreadNotifications > 0,
              label: Text('${state.unreadNotifications}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            tooltip: 'الضبط',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: RefreshIndicator(
        color: QColors.brightGreen,
        onRefresh: state.refreshHome,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: QSpace.xxl),
          children: [
            QResponsiveBody(
              padding: const EdgeInsets.fromLTRB(
                QSpace.lg,
                QSpace.sm,
                QSpace.lg,
                QSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileHero(state: state, isMerchant: isMerchant),
                  const SizedBox(height: QSpace.md),
                  _StatsRow(state: state, isMerchant: isMerchant),
                  const SizedBox(height: QSpace.lg),
                  _StoreActions(state: state, isMerchant: isMerchant),
                  const SizedBox(height: QSpace.xl),
                  QSectionHeader(
                    title: 'نشاط أخير',
                    subtitle: isMerchant
                        ? 'آخر الحركات على حساب المتجر'
                        : 'آخر حركاتك مع التجار',
                    actionLabel: 'الحركة',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StatementScreen(),
                      ),
                    ),
                  ),
                  QCard(
                    padding: EdgeInsets.zero,
                    child: entries.isEmpty
                        ? const QStateView(
                            state: QDataState.empty,
                            compact: true,
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < entries.take(4).length;
                                index++
                              ) ...[
                                QEntryTile(
                                  entry: entries[index],
                                  title: isMerchant
                                      ? _entryTitle(state, entries[index])
                                      : entries[index].productName ??
                                            entries[index].type.label,
                                ),
                                if (index != entries.take(4).length - 1)
                                  const Divider(),
                              ],
                            ],
                          ),
                  ),
                  if (isMerchant && state.isAdmin) ...[
                    const SizedBox(height: QSpace.lg),
                    QCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ReportsScreen(),
                        ),
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
                              'إدارة المنصة والإعلانات من لوحة الويب',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const Icon(Icons.chevron_left_rounded),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _entryTitle(AppState state, LedgerEntry entry) {
    final customer = state.contactById(entry.customerId);
    final base = customer?.displayName ?? 'عميل';
    return '$base • ${entry.productName ?? entry.type.label}';
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.state, required this.isMerchant});

  final AppState state;
  final bool isMerchant;

  @override
  Widget build(BuildContext context) {
    return QCard(
      padding: const EdgeInsets.all(QSpace.xl),
      gradient: QColors.gradient,
      borderColor: Colors.transparent,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.75),
                    width: 3,
                  ),
                ),
                child: const QBrandAvatar(size: 72),
              ),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMerchant ? state.user.storeName : state.user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: QColors.pureWhite,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isMerchant
                          ? state.user.category
                          : '${state.accountType.label} • ${formatPhoneLocal(state.user.phone)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: QSpace.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: QSpace.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(QRadius.pill),
                      ),
                      child: Text(
                        isMerchant ? 'متجر موثّق' : 'حساب موثّق',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: QColors.pureWhite,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isMerchant) ...[
            const SizedBox(height: QSpace.lg),
            Row(
              children: [
                Expanded(
                  child: _HeroMeta(
                    icon: Icons.place_outlined,
                    label: state.user.address,
                  ),
                ),
                const SizedBox(width: QSpace.md),
                Expanded(
                  child: _HeroMeta(
                    icon: Icons.phone_outlined,
                    label: state.user.phone,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.8)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state, required this.isMerchant});

  final AppState state;
  final bool isMerchant;

  @override
  Widget build(BuildContext context) {
    final stats = isMerchant
        ? [
            (
              label: 'المستحق',
              value: formatCompactMoney(state.approvedReceivable),
              color: QColors.approvedFg,
              background: QColors.approvedBg,
            ),
            (
              label: 'المعلق',
              value: formatCompactMoney(state.pendingReceivable),
              color: QColors.pendingFg,
              background: QColors.pendingBg,
            ),
            (
              label: 'العملاء',
              value: '${state.customers.length}',
              color: QColors.brightGreen,
              background: QColors.softMint,
            ),
          ]
        : [
            (
              label: 'المستحق',
              value: formatCompactMoney(state.customerApprovedTotal),
              color: QColors.approvedFg,
              background: QColors.approvedBg,
            ),
            (
              label: 'المعلق',
              value: formatCompactMoney(state.customerPendingTotal),
              color: QColors.pendingFg,
              background: QColors.pendingBg,
            ),
            (
              label: 'التجار',
              value: '${state.customerMerchants.length}',
              color: QColors.brightGreen,
              background: QColors.softMint,
            ),
          ];
    return Row(
      children: [
        for (var index = 0; index < stats.length; index++) ...[
          Expanded(
            child: QCard(
              padding: const EdgeInsets.all(QSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: stats[index].color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: QSpace.sm),
                  Text(
                    stats[index].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: stats[index].color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    stats[index].label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
          if (index != stats.length - 1) const SizedBox(width: QSpace.sm),
        ],
      ],
    );
  }
}

class _StoreActions extends StatelessWidget {
  const _StoreActions({required this.state, required this.isMerchant});

  final AppState state;
  final bool isMerchant;

  @override
  Widget build(BuildContext context) {
    final actions = isMerchant
        ? [
            (
              icon: Icons.people_alt_outlined,
              label: 'الموظفون',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EmployeesScreen(),
                ),
              ),
            ),
            (
              icon: Icons.bar_chart_rounded,
              label: 'التقارير',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
              ),
            ),
            (
              icon: Icons.swap_horiz_rounded,
              label: 'الحركة',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StatementScreen(),
                ),
              ),
            ),
            (
              icon: Icons.settings_outlined,
              label: 'الضبط',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          ]
        : [
            (
              icon: Icons.storefront_outlined,
              label: 'التجار',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomerMerchantsScreen(),
                ),
              ),
            ),
            (
              icon: Icons.description_outlined,
              label: 'الحركة',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StatementScreen(),
                ),
              ),
            ),
            (
              icon: Icons.photo_library_outlined,
              label: 'صور اليوم',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PhotosScreen()),
              ),
            ),
            (
              icon: Icons.payments_outlined,
              label: 'دفعة',
              onTap: () {
                if (state.customerMerchants.isEmpty) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PaymentScreen(merchant: state.customerMerchants.first),
                  ),
                );
              },
            ),
          ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: QSpace.sm,
      crossAxisSpacing: QSpace.sm,
      childAspectRatio: 0.95,
      children: [
        for (final action in actions)
          QQuickAction(
            icon: action.icon,
            label: action.label,
            onTap: action.onTap,
          ),
      ],
    );
  }
}
