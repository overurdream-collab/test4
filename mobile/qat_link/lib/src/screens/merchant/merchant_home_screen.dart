import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../shared/notifications_screen.dart';
import '../shared/profile_switch_sheet.dart';
import 'customer_detail_screen.dart';

class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({super.key});

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  int _period = 0;
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
    final chartValues = switch (_period) {
      0 => const <double>[42, 58, 36, 72, 64, 88, 76],
      1 => const <double>[52, 74, 61, 88, 69, 96, 82],
      _ => const <double>[36, 62, 48, 78, 71, 92, 84],
    };

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(right: QSpace.sm),
          child: GestureDetector(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(QRadius.xl),
                ),
              ),
              builder: (_) => const ProfileSwitchSheet(),
            ),
            child: const QLogoMark(size: 40),
          ),
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
                        if (state.bannerAdVisible) ...[
                          const SizedBox(height: QSpace.md),
                          const _AdminBanner(),
                        ],
                        const SizedBox(height: QSpace.lg),
                        _TotalsRow(state: state),
                        const SizedBox(height: QSpace.lg),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 840;
                            final chart = _ChartCard(
                              period: _period,
                              values: chartValues,
                              onPeriodChanged: (value) =>
                                  setState(() => _period = value),
                            );
                            final list = _CustomersCard(
                              state: state,
                              customers: filtered,
                              selectedCustomer: _customerFilter,
                              onCustomerChanged: (value) =>
                                  setState(() => _customerFilter = value),
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
    return QCard(
      padding: const EdgeInsets.all(QSpace.xl),
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          QColors.brightGreen,
          QColors.freshGreen,
          QColors.lightGreen.withValues(alpha: 0.92),
        ],
      ),
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(QRadius.md),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.36),
                  ),
                ),
                child: const QLogoMark(size: 66),
              ),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.user.storeName,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: QColors.charcoal,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      state.user.category,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: QColors.charcoal.withValues(alpha: 0.74),
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
                  color: Colors.white.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(QRadius.pill),
                ),
                child: Text(
                  'موثّق',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: QColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          Wrap(
            spacing: QSpace.lg,
            runSpacing: QSpace.sm,
            children: [
              _StoreMeta(icon: Icons.place_outlined, label: state.user.address),
              _StoreMeta(icon: Icons.phone_outlined, label: state.user.phone),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          Divider(color: QColors.charcoal.withValues(alpha: 0.14)),
          const SizedBox(height: QSpace.sm),
          Row(
            children: [
              Expanded(
                child: _StoreMetric(
                  label: 'إجمالي المستحق المعتمد',
                  value: formatMoney(
                    state.approvedReceivable,
                    hidden: state.hideAmounts,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: QColors.charcoal.withValues(alpha: 0.14),
              ),
              const SizedBox(width: QSpace.lg),
              Expanded(
                child: _StoreMetric(
                  label: 'المبالغ المعلقة',
                  value: formatMoney(
                    state.pendingReceivable,
                    hidden: state.hideAmounts,
                  ),
                  valueColor: QColors.charcoal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoreMeta extends StatelessWidget {
  const _StoreMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: QColors.charcoal.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: QColors.charcoal.withValues(alpha: 0.76),
            ),
          ),
        ),
      ],
    );
  }
}

class _StoreMetric extends StatelessWidget {
  const _StoreMetric({
    required this.label,
    required this.value,
    this.valueColor = QColors.charcoal,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: QColors.charcoal.withValues(alpha: 0.68),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        label: 'عملاء',
        value: '${state.customers.length}',
        icon: Icons.people_alt_outlined,
        color: QColors.approvedFg,
      ),
      (
        label: 'معلقة',
        value: '${state.pendingMerchantCount}',
        icon: Icons.schedule_rounded,
        color: QColors.pendingFg,
      ),
      (
        label: 'إجمالي الحركة',
        value: formatCompactMoney(
          state.merchantEntries
              .where((entry) => entry.status == TxStatus.approved)
              .fold(0, (total, entry) => total + entry.amountMinor),
        ),
        icon: Icons.swap_horiz_rounded,
        color: QColors.brightGreen,
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
                  Icon(stats[index].icon, size: 20, color: stats[index].color),
                  const SizedBox(height: QSpace.sm),
                  Text(
                    stats[index].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.period,
    required this.values,
    required this.onPeriodChanged,
  });

  final int period;
  final List<double> values;
  final ValueChanged<int> onPeriodChanged;

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
                  title: 'حركة التعاملات',
                  subtitle: 'نظرة سريعة على النشاط',
                  padding: EdgeInsets.zero,
                ),
              ),
              PopupMenuButton<int>(
                initialValue: period,
                onSelected: onPeriodChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 0, child: Text('يومي')),
                  PopupMenuItem(value: 1, child: Text('شهري')),
                  PopupMenuItem(value: 2, child: Text('سنوي')),
                ],
                child: Chip(
                  avatar: const Icon(Icons.tune_rounded, size: 15),
                  label: Text(['يومي', 'شهري', 'سنوي'][period]),
                ),
              ),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          QBarChart(values: values),
          const SizedBox(height: QSpace.md),
          const Wrap(
            spacing: QSpace.md,
            runSpacing: QSpace.sm,
            children: [
              _LegendDot(color: QColors.brightGreen, label: 'مبيعات'),
              _LegendDot(color: QColors.premiumGold, label: 'مستحقات'),
              _LegendDot(color: QColors.neutralGray, label: 'دفعات'),
            ],
          ),
        ],
      ),
    );
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
  });

  final AppState state;
  final List<Contact> customers;
  final String? selectedCustomer;
  final ValueChanged<String?> onCustomerChanged;

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
            for (var index = 0; index < customers.length; index++) ...[
              QContactTile(
                contact: customers[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CustomerDetailScreen(customer: customers[index]),
                  ),
                ),
              ),
              if (index != customers.length - 1) const Divider(),
            ],
          const SizedBox(height: QSpace.sm),
          QGradientButton(
            label: 'عرض كل العملاء',
            icon: Icons.arrow_back_rounded,
            expand: false,
            height: 46,
            onPressed: () {},
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
            onAction: () {},
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

class _AdminBanner extends StatelessWidget {
  const _AdminBanner();

  @override
  Widget build(BuildContext context) {
    return QCard(
      padding: const EdgeInsets.all(QSpace.md),
      gradient: const LinearGradient(
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: QColors.brightGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.campaign_outlined,
              color: QColors.brightGreen,
            ),
          ),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إعلان الإدارة',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  'مساحة Banner مخصصة في رأس الرئيسية فقط.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded, color: QColors.neutralGray),
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
