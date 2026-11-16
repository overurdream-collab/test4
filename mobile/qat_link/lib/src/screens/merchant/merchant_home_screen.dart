import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../shared/admin_ads_carousel.dart';
import '../shared/notifications_screen.dart';
import '../shared/statement_screen.dart';
import 'customer_detail_screen.dart';
import 'merchant_customers_screen.dart';
import 'new_customer_screen.dart';
import 'new_debt_sheet.dart';

class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({super.key});

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  String? _customerFilter;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final customers = state.customers;
    final filtered = _customerFilter == null
        ? customers
        : customers
              .where((customer) => customer.id == _customerFilter)
              .toList();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(right: QSpace.sm),
          child: QBrandAvatar(size: 40),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أهلاً، ${state.user.name.split(' ').first}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'أنت تسجل.. وأنا أعتمد.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
            icon: Badge(
              isLabelVisible: state.unreadNotifications > 0,
              label: Text('${state.unreadNotifications}'),
              backgroundColor: QColors.brightGreen,
              textColor: QColors.charcoal,
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: RefreshIndicator(
        color: QColors.brightGreen,
        onRefresh: state.refreshHome,
        child: state.loading
            ? const Padding(
                padding: EdgeInsets.all(QSpace.lg),
                child: Column(
                  children: [
                    QLoadingCard(height: 180),
                    SizedBox(height: QSpace.lg),
                    QLoadingCard(),
                    SizedBox(height: QSpace.md),
                    QLoadingCard(),
                  ],
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  QSpace.lg,
                  QSpace.sm,
                  QSpace.lg,
                  QSpace.xxl,
                ),
                children: [
                  QResponsiveBody(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StoreCard(state: state),
                        if (state.ads.isNotEmpty) ...[
                          const SizedBox(height: QSpace.md),
                          AdminAdsCarousel(ads: state.ads),
                        ],
                        const SizedBox(height: QSpace.lg),
                        _QuickActions(state: state),
                        const SizedBox(height: QSpace.xl),
                        _TodaySection(state: state),
                        const SizedBox(height: QSpace.xl),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 840;
                            final chart = _ActivityCard(state: state);
                            final list = _CustomersCard(
                              state: state,
                              customers: filtered,
                              selectedCustomer: _customerFilter,
                              onCustomerChanged: (value) =>
                                  setState(() => _customerFilter = value),
                              onViewAll: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const MerchantCustomersScreen(),
                                ),
                              ),
                              onAdd: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const NewCustomerScreen(),
                                ),
                              ),
                            );
                            if (!wide) {
                              return Column(
                                children: [
                                  chart,
                                  const SizedBox(height: QSpace.lg),
                                  list,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 5, child: chart),
                                const SizedBox(width: QSpace.lg),
                                Expanded(flex: 6, child: list),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: QSpace.lg),
                        _PendingOperations(state: state),
                        const SizedBox(height: QSpace.lg),
                        if (state.paidAdVisible) const _PaidAdCard(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final collected = <String, int>{};
    for (final entry in state.merchantEntries) {
      if (entry.status != TxStatus.approved) continue;
      if (entry.type != OperationType.payment &&
          state.effectOf(entry) != OperationEffect.decrease) {
        continue;
      }
      collected[entry.currency] =
          (collected[entry.currency] ?? 0) + entry.amountMinor;
    }
    return QCard(
      padding: const EdgeInsets.all(QSpace.xl),
      gradient: QColors.gradient,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 2,
                  ),
                ),
                child: const QBrandAvatar(size: 52),
              ),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.user.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: QColors.pureWhite,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      state.user.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: QSpace.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(QRadius.pill),
                ),
                child: Text(
                  'موثّق',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: QColors.pureWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  'الأرصدة حسب العملة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: QColors.pureWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: QSpace.sm),
              Text(
                'YER · SAR · USD',
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
          const SizedBox(height: QSpace.sm),
          Text(
            'إجمالي الديون',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          QMoneyTotals(
            totals: state.approvedReceivableByCurrency,
            style: Theme.of(context).textTheme.headlineMedium,
            color: QColors.pureWhite,
          ),
          const SizedBox(height: QSpace.lg),
          Row(
            children: [
              Expanded(
                child: _CurrencyPill(
                  label: 'المسدد',
                  value: formatMoneyTotals(
                    collected,
                    hidden: state.hideAmounts,
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: _CurrencyPill(
                  label: 'العالق',
                  value: formatMoneyTotals(
                    state.pendingNetByCurrency(state.merchantEntries),
                    hidden: state.hideAmounts,
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: _CurrencyPill(
                  label: 'العملاء',
                  value: '${state.customers.length}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QSpace.sm,
        vertical: QSpace.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(QRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: QColors.pureWhite,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        label: 'دين جديد',
        icon: Icons.receipt_long_rounded,
        onTap: () => _openDebt(context),
      ),
      (
        label: 'عميل جديد',
        icon: Icons.person_add_alt_1_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NewCustomerScreen()),
        ),
      ),
      (
        label: 'الحركة',
        icon: Icons.swap_horiz_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const StatementScreen()),
        ),
      ),
      (
        label: 'الإشعارات',
        icon: Icons.notifications_none_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        ),
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          Expanded(
            child: QQuickAction(
              icon: actions[index].icon,
              label: actions[index].label,
              onTap: actions[index].onTap,
            ),
          ),
          if (index != actions.length - 1) const SizedBox(width: QSpace.sm),
        ],
      ],
    );
  }

  void _openDebt(BuildContext context) {
    if (state.customers.isEmpty) {
      QToast.show(context, 'أضف عميلاً أولاً لتسجيل دين جديد');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (_) => const NewDebtSheet(),
    );
  }
}

class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayEntries = state.merchantEntries.where(
      (entry) =>
          entry.createdAt.year == now.year &&
          entry.createdAt.month == now.month &&
          entry.createdAt.day == now.day,
    );
    final charges = <String, int>{};
    final payments = <String, int>{};
    for (final entry in todayEntries) {
      if (entry.status != TxStatus.approved) continue;
      final effect = state.effectOf(entry);
      if (effect == OperationEffect.increase) {
        charges[entry.currency] =
            (charges[entry.currency] ?? 0) + state.effectAmountOf(entry);
      } else if (entry.type == OperationType.payment ||
          effect == OperationEffect.decrease) {
        payments[entry.currency] =
            (payments[entry.currency] ?? 0) + state.effectAmountOf(entry);
      }
    }
    final pending = todayEntries
        .where((entry) => entry.status == TxStatus.pending)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QSectionHeader(
          title: 'اليوم',
          subtitle: formatDate(now),
          actionLabel: 'الحركة',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const StatementScreen()),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.north_east_rounded,
                label: 'دين جديد',
                value: formatMoneyTotals(
                  charges,
                  hidden: state.hideAmounts,
                  compact: true,
                ),
                color: QColors.brightGreen,
                background: QColors.softMint,
              ),
            ),
            const SizedBox(width: QSpace.sm),
            Expanded(
              child: _MetricCard(
                icon: Icons.south_west_rounded,
                label: 'تحصيل',
                value: formatMoneyTotals(
                  payments,
                  hidden: state.hideAmounts,
                  compact: true,
                ),
                color: QColors.approvedFg,
                background: QColors.approvedBg,
              ),
            ),
            const SizedBox(width: QSpace.sm),
            Expanded(
              child: _MetricCard(
                icon: Icons.schedule_rounded,
                label: 'معلقة',
                value: '$pending',
                suffix: 'عملية',
                color: QColors.pendingFg,
                background: QColors.pendingBg,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return QCard(
      padding: const EdgeInsets.all(QSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: QSpace.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (suffix != null)
            Text(
              suffix!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final values = _weeklyValues();
    final totals = _weeklyTotals();
    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QSectionHeader(
            title: 'حركة الأسبوع',
            subtitle: 'إجمالي الحركات المعتمدة',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              Expanded(
                child: QMoneyTotals(
                  totals: totals,
                  style: Theme.of(context).textTheme.headlineSmall,
                  color: QColors.charcoal,
                ),
              ),
              const Icon(Icons.trending_up_rounded, color: QColors.brightGreen),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          QBarChart(values: values),
          const SizedBox(height: QSpace.md),
          const Wrap(
            spacing: QSpace.md,
            runSpacing: QSpace.sm,
            children: [
              _LegendDot(color: QColors.brightGreen, label: 'الحركة اليومية'),
            ],
          ),
        ],
      ),
    );
  }

  List<double> _weeklyValues() {
    final totals = List<int>.filled(7, 0);
    final now = DateTime.now();
    for (final entry in state.merchantEntries) {
      if (entry.status != TxStatus.approved) continue;
      final difference = DateTime(now.year, now.month, now.day).difference(
        DateTime(
          entry.createdAt.year,
          entry.createdAt.month,
          entry.createdAt.day,
        ),
      );
      if (difference.inDays < 0 || difference.inDays > 6) continue;
      totals[6 - difference.inDays] += 1;
    }
    final highest = totals.fold<int>(1, math.max);
    return [
      for (final total in totals)
        total == 0 ? 6 : (total / highest * 100).clamp(10, 100),
    ];
  }

  Map<String, int> _weeklyTotals() {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final totals = <String, int>{};
    for (final entry in state.merchantEntries) {
      if (entry.status != TxStatus.approved) continue;
      if (entry.createdAt.isBefore(start)) continue;
      totals[entry.currency] =
          (totals[entry.currency] ?? 0) + entry.amountMinor;
    }
    return totals;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CustomersCard extends StatelessWidget {
  const _CustomersCard({
    required this.state,
    required this.customers,
    required this.selectedCustomer,
    required this.onCustomerChanged,
    required this.onViewAll,
    required this.onAdd,
  });

  final AppState state;
  final List<Contact> customers;
  final String? selectedCustomer;
  final ValueChanged<String?> onCustomerChanged;
  final VoidCallback onViewAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: QSectionHeader(
                  title: 'العملاء',
                  subtitle: 'اضغط على العميل لعرض كشفه',
                  padding: EdgeInsets.zero,
                ),
              ),
              IconButton(
                tooltip: 'إضافة عميل',
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
              PopupMenuButton<String?>(
                initialValue: selectedCustomer,
                onSelected: onCustomerChanged,
                itemBuilder: (context) => [
                  const PopupMenuItem<String?>(
                    value: null,
                    child: Text('كل العملاء'),
                  ),
                  for (final customer in state.customers)
                    PopupMenuItem<String?>(
                      value: customer.id,
                      child: Text(customer.displayName),
                    ),
                ],
                child: const Icon(Icons.filter_list_rounded),
              ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          if (customers.isEmpty)
            const QStateView(state: QDataState.empty, compact: true)
          else
            for (var index = 0; index < customers.take(4).length; index++) ...[
              QContactTile(
                contact: customers[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CustomerDetailScreen(customer: customers[index]),
                  ),
                ),
              ),
              if (index != customers.take(4).length - 1) const Divider(),
            ],
          const SizedBox(height: QSpace.sm),
          QGradientButton(
            label: 'عرض كل العملاء',
            icon: Icons.arrow_back_rounded,
            expand: false,
            height: 46,
            onPressed: onViewAll,
          ),
        ],
      ),
    );
  }
}

class _PendingOperations extends StatelessWidget {
  const _PendingOperations({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final pending = state.merchantEntries
        .where((entry) => entry.status == TxStatus.pending)
        .take(3)
        .toList();
    if (pending.isEmpty) {
      return QCard(
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: QColors.approvedFg,
            ),
            const SizedBox(width: QSpace.md),
            Expanded(
              child: Text(
                'لا توجد عمليات معلقة اليوم. كل شيء تحت السيطرة.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    return QCard(
      child: Column(
        children: [
          QSectionHeader(
            title: 'بانتظار الموافقة',
            subtitle: '${pending.length} عمليات تحتاج متابعة',
            padding: EdgeInsets.zero,
            actionLabel: 'عرض',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatementScreen()),
            ),
          ),
          const SizedBox(height: QSpace.sm),
          for (var index = 0; index < pending.length; index++) ...[
            QEntryTile(entry: pending[index]),
            if (index != pending.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _PaidAdCard extends StatelessWidget {
  const _PaidAdCard();

  @override
  Widget build(BuildContext context) {
    return QCard(
      child: Row(
        children: [
          const Icon(Icons.local_offer_outlined, color: QColors.premiumGold),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Text(
              'إعلان مدفوع (يُفعّل لاحقاً) • يظهر أسفل الرئيسية فقط',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
