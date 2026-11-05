import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../shared/notifications_screen.dart';
import '../shared/photos_screen.dart';
import '../shared/profile_switch_sheet.dart';
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
    final limit = merchants.fold<int>(
      0,
      (total, merchant) => total + merchant.creditLimitMinor,
    );
    final used = state.customerApprovedTotal + state.customerPendingTotal;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: QSpace.lg,
        title: Row(
          children: [
            const QLogoMark(size: 34),
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
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
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
              child: QAvatar(label: state.user.name, size: 38),
            ),
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
                  Text(
                    'مساء الخير، ${state.user.name.split(' ').first}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'هذا ملخص حسابك لدى التجار.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: QSpace.lg),
                  _BalanceCard(state: state, limit: limit, used: used),
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
                    actionLabel: 'الكشف',
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
                  const SizedBox(height: QSpace.xl),
                  _ActionsGrid(
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
    required this.limit,
    required this.used,
  });

  final AppState state;
  final int limit;
  final int used;

  @override
  Widget build(BuildContext context) {
    final pending = state.customerPendingTotal;
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
                    QMoney(
                      minor: state.customerApprovedTotal,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: QSpace.xs),
                    if (pending > 0)
                      Text(
                        'معلق: ${formatMoney(pending, hidden: state.hideAmounts)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: QColors.pendingFg,
                        ),
                      ),
                  ],
                ),
              ),
              QBalanceRing(
                amountMinor: state.customerApprovedTotal,
                label: 'من الحد',
                progress: limit == 0 ? 0 : used / limit,
                size: 132,
                hidden: state.hideAmounts,
                secondaryLabel: 'المتاح',
                secondaryAmountMinor: (limit - used).clamp(0, limit),
              ),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          QCreditLimitBar(
            usedMinor: used,
            limitMinor: limit,
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
            '${merchant?.displayName ?? 'تاجر'} سجل ${formatMoney(entry.amountMinor, hidden: state.hideAmounts)}'
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
          decoration: const InputDecoration(labelText: 'المبلغ البديل بالريال'),
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
      state.requestEdit(entry.id, amount, 'طلب تعديل من العميل');
      if (context.mounted) QToast.show(context, 'تم إرسال طلب التعديل');
    }
  }
}

class _ActionsGrid extends StatelessWidget {
  const _ActionsGrid({
    required this.onPhotos,
    required this.onStatement,
    required this.onSettlement,
  });

  final VoidCallback onPhotos;
  final VoidCallback onStatement;
  final VoidCallback onSettlement;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        label: 'كشف الحساب',
        icon: Icons.description_outlined,
        onTap: onStatement,
      ),
      (label: 'صور اليوم', icon: Icons.photo_library_outlined, onTap: onPhotos),
      (label: 'طلب سداد', icon: Icons.handshake_outlined, onTap: onSettlement),
      (
        label: 'الإشعارات',
        icon: Icons.notifications_none_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        ),
      ),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: QSpace.sm,
      crossAxisSpacing: QSpace.sm,
      childAspectRatio: 0.9,
      children: [
        for (final action in actions)
          QCard(
            onTap: action.onTap,
            padding: const EdgeInsets.all(QSpace.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: QColors.brightGreen),
                const SizedBox(height: QSpace.xs),
                Text(
                  action.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
