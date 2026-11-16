import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../shared/admin_ads_carousel.dart';
import '../shared/notifications_screen.dart';
import '../shared/photos_screen.dart';
import '../shared/statement_screen.dart';
import 'customer_merchants_screen.dart';
import 'payment_screen.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final pending = state.customerPendingApprovals;
    final merchants = state.customerMerchants;
    final entries = state.customerEntries.take(4).toList();
    final limits = <String, int>{};
    for (final merchant in merchants) {
      for (final entry in merchant.creditLimitsMinor.entries) {
        limits[entry.key] = (limits[entry.key] ?? 0) + entry.value;
      }
    }
    final used = <String, int>{
      for (final currency in supportedCurrencies)
        currency:
            (state.customerApprovedByCurrency[currency] ?? 0) +
            (state.pendingNetByCurrency(state.customerEntries)[currency] ?? 0),
    };
    final now = DateTime.now();
    final todayEntries = state.customerEntries.where(
      (entry) =>
          entry.createdAt.year == now.year &&
          entry.createdAt.month == now.month &&
          entry.createdAt.day == now.day,
    );
    final todayPayments = <String, int>{};
    for (final entry in todayEntries) {
      if (entry.status != TxStatus.approved) continue;
      if (entry.type != OperationType.payment) continue;
      todayPayments[entry.currency] =
          (todayPayments[entry.currency] ?? 0) + entry.amountMinor;
    }
    final todayPending = todayEntries
        .where((entry) => entry.status == TxStatus.pending)
        .length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: QSpace.lg,
        title: Row(
          children: [
            const QBrandAvatar(size: 34),
            const SizedBox(width: QSpace.sm),
            Text(
              'QAT LINK',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
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
          Padding(
            padding: const EdgeInsetsDirectional.only(end: QSpace.lg),
            child: QAvatar(label: state.user.name, size: 38),
          ),
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
                  _WelcomeCard(state: state),
                  if (state.ads.isNotEmpty) ...[
                    const SizedBox(height: QSpace.lg),
                    AdminAdsCarousel(ads: state.ads),
                  ],
                  const SizedBox(height: QSpace.lg),
                  _BalanceCard(state: state, limits: limits, used: used),
                  const SizedBox(height: QSpace.lg),
                  Row(
                    children: [
                      Expanded(
                        child: QGradientButton(
                          label: 'سجل دفعة',
                          icon: Icons.payments_outlined,
                          onPressed: merchants.isEmpty
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PaymentScreen(
                                      merchant: merchants.first,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: QSpace.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: merchants.isEmpty
                              ? null
                              : () => _requestSettlement(context, state),
                          icon: const Icon(Icons.handshake_outlined),
                          label: const Text('طلب سداد'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: QSpace.md),
                  _CustomerQuickActions(
                    onPhotos: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PhotosScreen(),
                      ),
                    ),
                    onStatement: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StatementScreen(),
                      ),
                    ),
                    onSettlement: () => _requestSettlement(context, state),
                    onNotifications: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: QSpace.xl),
                  _TodaySection(
                    payments: todayPayments,
                    pending: todayPending,
                    onStatement: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StatementScreen(),
                      ),
                    ),
                  ),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: QSpace.lg),
                    _PendingCard(pending: pending),
                  ],
                  const SizedBox(height: QSpace.xl),
                  QSectionHeader(
                    title: 'التجار',
                    subtitle: 'أرصدتك لدى كل تاجر',
                    actionLabel: 'الكل',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CustomerMerchantsScreen(),
                      ),
                    ),
                  ),
                  QCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < merchants.take(3).length;
                          index++
                        ) ...[
                          QContactTile(
                            contact: merchants[index],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    PaymentScreen(merchant: merchants[index]),
                              ),
                            ),
                          ),
                          if (index != merchants.take(3).length - 1)
                            const Divider(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: QSpace.xl),
                  QSectionHeader(
                    title: 'نشاطك الأخير',
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
                                index < entries.length;
                                index++
                              ) ...[
                                QEntryTile(entry: entries[index]),
                                if (index != entries.length - 1)
                                  const Divider(),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _requestSettlement(BuildContext context, AppState state) {
    final merchants = state.customerMerchants;
    if (merchants.isEmpty) return;
    final merchant = merchants.first;
    if (state.hasSettlementToday(merchant.id)) {
      QToast.show(context, 'لديك طلب سداد اليوم بالفعل');
      return;
    }
    state.requestSettlement(merchant.id);
    QToast.show(context, 'تم إرسال طلب السداد إلى ${merchant.displayName}');
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.state,
    required this.limits,
    required this.used,
  });

  final AppState state;
  final Map<String, int> limits;
  final Map<String, int> used;

  @override
  Widget build(BuildContext context) {
    final pending = state.pendingNetByCurrency(state.customerEntries);
    final limitTotal = limits.values.fold<int>(0, (sum, value) => sum + value);
    final usedTotal = used.values.fold<int>(0, (sum, value) => sum + value);
    final available = <String, int>{
      for (final entry in limits.entries)
        entry.key: (entry.value - (used[entry.key] ?? 0)).clamp(0, entry.value),
    };
    return QCard(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إجمالي المستحق',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: QSpace.xs),
                    QMoneyTotals(
                      totals: state.customerApprovedByCurrency,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: state.customerApprovedByCurrency.values.any(
                              (value) => value > 0,
                            )
                                ? QColors.rejectedFg
                                : QColors.charcoal,
                          ),
                    ),
                    const SizedBox(height: QSpace.xs),
                    if (pending.isNotEmpty)
                      Text(
                        'معلق: ${formatMoneyTotals(pending, hidden: state.hideAmounts, compact: true)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: QColors.pendingFg,
                        ),
                      ),
                  ],
                ),
              ),
              QBalanceRing(
                amountMinor: state.customerApprovedTotal,
                totals: state.customerApprovedByCurrency,
                label: 'من الحد',
                progress: limitTotal == 0 ? 0 : usedTotal / limitTotal,
                size: 132,
                hidden: state.hideAmounts,
                secondaryLabel: 'المتاح',
                secondaryTotals: available,
              ),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          QCreditLimitBars(
            limitsMinor: limits,
            usedMinor: used,
            hidden: state.hideAmounts,
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.pending});

  final List<LedgerEntry> pending;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final entry = pending.first;
    final merchant = state.contactById(entry.merchantId);
    return QCard(
      borderColor: QColors.premiumGold.withValues(alpha: 0.7),
      gradient: const LinearGradient(
        colors: [QColors.pendingBg, QColors.pureWhite],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: QColors.pendingFg),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: Text(
                  '${pending.length} عملية بانتظار موافقتك',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const QStatusBadge(status: TxStatus.pending, compact: true),
            ],
          ),
          const SizedBox(height: QSpace.md),
          Text(
            '${merchant?.displayName ?? 'تاجر'} سجل ${formatMoney(entry.amountMinor, currency: entry.currency, hidden: state.hideAmounts)}'
            '${entry.productName == null ? '' : ' • ${entry.productName}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => state.rejectEntry(entry.id),
                  child: const Text('رفض'),
                ),
              ),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showEdit(context, state, entry),
                  child: const Text('طلب تعديل'),
                ),
              ),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => state.approveEntry(entry.id),
                  child: const Text('موافقة'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEdit(
    BuildContext context,
    AppState state,
    LedgerEntry entry,
  ) async {
    final controller = TextEditingController(
      text: ((entry.proposedAmountMinor ?? entry.amountMinor) / 100)
          .round()
          .toString(),
    );
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب تعديل المبلغ'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'المبلغ البديل (${entry.currency})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(value == null ? null : value * 100);
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (amount != null) {
      final sent = await state.requestEdit(
        entry.id,
        amount,
        'طلب تعديل من العميل',
      );
      if (context.mounted) {
        QToast.show(
          context,
          sent ? 'تم إرسال طلب التعديل' : 'طلب التعديل غير متاح بعد',
        );
      }
    }
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return QCard(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Row(
        children: [
          const QBrandAvatar(size: 62),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPhoneLocal(state.user.phone),
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: QColors.neutralGray,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: QSpace.xs),
                Text(
                  'هذا ملخص حسابك لدى التجار.',
                  style: Theme.of(context).textTheme.bodySmall,
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
              color: QColors.brightGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(QRadius.pill),
            ),
            child: Text(
              state.accountType.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: QColors.brightGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerQuickActions extends StatelessWidget {
  const _CustomerQuickActions({
    required this.onPhotos,
    required this.onStatement,
    required this.onSettlement,
    required this.onNotifications,
  });

  final VoidCallback onPhotos;
  final VoidCallback onStatement;
  final VoidCallback onSettlement;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (label: 'الحركة', icon: Icons.swap_horiz_rounded, onTap: onStatement),
      (label: 'صور اليوم', icon: Icons.photo_library_outlined, onTap: onPhotos),
      (label: 'طلب سداد', icon: Icons.handshake_outlined, onTap: onSettlement),
      (
        label: 'الإشعارات',
        icon: Icons.notifications_none_rounded,
        onTap: onNotifications,
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
}

class _TodaySection extends StatelessWidget {
  const _TodaySection({
    required this.payments,
    required this.pending,
    required this.onStatement,
  });

  final Map<String, int> payments;
  final int pending;
  final VoidCallback onStatement;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QSectionHeader(
          title: 'اليوم',
          subtitle: formatDate(DateTime.now()),
          actionLabel: 'الحركة',
          onAction: onStatement,
        ),
        Row(
          children: [
            Expanded(
              child: QCard(
                padding: const EdgeInsets.all(QSpace.md),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: QColors.approvedBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.south_west_rounded,
                        size: 19,
                        color: QColors.approvedFg,
                      ),
                    ),
                    const SizedBox(width: QSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatMoneyTotals(
                              payments,
                              compact: true,
                              hidden: QScope.of(context).hideAmounts,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: QColors.approvedFg,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          Text(
                            'دفعات اليوم',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: QSpace.sm),
            Expanded(
              child: QCard(
                padding: const EdgeInsets.all(QSpace.md),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: QColors.pendingBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        size: 19,
                        color: QColors.pendingFg,
                      ),
                    ),
                    const SizedBox(width: QSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$pending',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: QColors.pendingFg,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          Text(
                            'بانتظار موافقتك',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
