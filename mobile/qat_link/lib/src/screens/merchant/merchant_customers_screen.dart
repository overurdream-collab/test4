import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import 'customer_detail_screen.dart';
import 'new_customer_screen.dart';
import 'new_debt_sheet.dart';

class MerchantCustomersScreen extends StatefulWidget {
  const MerchantCustomersScreen({super.key});

  @override
  State<MerchantCustomersScreen> createState() =>
      _MerchantCustomersScreenState();
}

class _MerchantCustomersScreenState extends State<MerchantCustomersScreen> {
  final _searchController = TextEditingController();
  int _filter = 0;
  int _sort = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final query = _searchController.text.trim();
    var customers = state.customers.where((customer) {
      final matchesQuery =
          query.isEmpty ||
          customer.displayName.contains(query) ||
          customer.phone.contains(query);
      final matchesFilter = switch (_filter) {
        1 => customer.favorite,
        2 => customer.pendingMinor > 0,
        3 => !customer.hasApp,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    customers = [...customers];
    switch (_sort) {
      case 1:
        customers.sort((a, b) => b.balanceMinor.compareTo(a.balanceMinor));
      case 2:
        customers.sort((a, b) => b.pendingMinor.compareTo(a.pendingMinor));
      default:
        customers.sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    final total = state.customers.fold<int>(
      0,
      (sum, customer) => sum + customer.balanceMinor,
    );
    final pending = state.customers.fold<int>(
      0,
      (sum, customer) => sum + customer.pendingMinor,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
        actions: [
          IconButton(
            tooltip: 'فرز',
            onPressed: _showSort,
            icon: const Icon(Icons.sort_rounded),
          ),
          IconButton(
            tooltip: 'إضافة عميل',
            onPressed: () => _openNewCustomer(context),
            icon: const Icon(Icons.person_add_alt_1_rounded),
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
                  _CustomersSummary(
                    total: total,
                    pending: pending,
                    count: state.customers.length,
                    favoriteCount: state.favoriteCustomers.length,
                  ),
                  const SizedBox(height: QSpace.md),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الجوال',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: QSpace.md),
                  QFilterPills(
                    items: const [
                      'الكل',
                      'المفضلة',
                      'لديهم عمليات معلقة',
                      'بدون التطبيق',
                    ],
                    selected: _filter,
                    onSelected: (value) => setState(() => _filter = value),
                  ),
                  const SizedBox(height: QSpace.md),
                  Row(
                    children: [
                      Text(
                        '${customers.length} عميل',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      if (state.offline)
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: QColors.pendingFg,
                        ),
                    ],
                  ),
                  const SizedBox(height: QSpace.sm),
                  if (customers.isEmpty)
                    const QStateView(
                      state: QDataState.empty,
                      title: 'لا يوجد عملاء مطابقون',
                    )
                  else
                    for (var index = 0; index < customers.length; index++) ...[
                      _CustomerCard(
                        customer: customers[index],
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CustomerDetailScreen(
                              customer: customers[index],
                            ),
                          ),
                        ),
                        onDebt: () => _openDebt(context, customers[index].id),
                      ),
                      if (index != customers.length - 1)
                        const SizedBox(height: QSpace.sm),
                    ],
                  const SizedBox(height: QSpace.lg),
                  _InviteCard(onTap: () => _openNewCustomer(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openNewCustomer(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const NewCustomerScreen()));
  }

  void _openDebt(BuildContext context, String customerId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (_) => NewDebtSheet(initialCustomerId: customerId),
    );
  }

  Future<void> _showSort() async {
    final value = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(QSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const QSheetHeader(title: 'ترتيب العملاء'),
              const SizedBox(height: QSpace.md),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha_rounded),
                title: const Text('الاسم'),
                onTap: () => Navigator.of(context).pop(0),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('أعلى رصيد معتمد'),
                onTap: () => Navigator.of(context).pop(1),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('أعلى مبلغ معلق'),
                onTap: () => Navigator.of(context).pop(2),
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null) setState(() => _sort = value);
  }
}

class _CustomersSummary extends StatelessWidget {
  const _CustomersSummary({
    required this.total,
    required this.pending,
    required this.count,
    required this.favoriteCount,
  });

  final int total;
  final int pending;
  final int count;
  final int favoriteCount;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return QCard(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملخص العملاء',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$count عميل • $favoriteCount في المفضلة',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.people_alt_outlined, color: QColors.brightGreen),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          Row(
            children: [
              Expanded(
                child: QSummaryCircle(
                  label: 'إجمالي المستحق',
                  amountMinor: total,
                  color: QColors.approvedFg,
                  size: 82,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: QSummaryCircle(
                  label: 'المعلق',
                  amountMinor: pending,
                  color: QColors.pendingFg,
                  size: 82,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: _CountCircle(
                  label: 'العملاء',
                  value: '$count',
                  color: QColors.brightGreen,
                  size: 82,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountCircle extends StatelessWidget {
  const _CountCircle({
    required this.label,
    required this.value,
    required this.color,
    required this.size,
  });

  final String label;
  final String value;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: QSpace.xs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onOpen,
    required this.onDebt,
  });

  final Contact customer;
  final VoidCallback onOpen;
  final VoidCallback onDebt;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final hasPending = customer.pendingMinor > 0;
    return QCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(QSpace.md),
      child: Column(
        children: [
          Row(
            children: [
              QAvatar(
                label: customer.displayName,
                size: 48,
                gradient: customer.favorite
                    ? QColors.gradient
                    : LinearGradient(
                        colors: [
                          QColors.softMint,
                          QColors.lightGreen.withValues(alpha: 0.55),
                        ],
                      ),
              ),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            customer.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (customer.favorite) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: QColors.premiumGold,
                          ),
                        ],
                        if (!customer.hasApp) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 14,
                            color: QColors.neutralGray,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      customer.phone,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: QColors.neutralGray,
              ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              Expanded(
                child: _Amount(
                  label: 'المعتمد',
                  amount: customer.balanceMinor,
                  color: QColors.approvedFg,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: _Amount(
                  label: 'المعلق',
                  amount: customer.pendingMinor,
                  color: QColors.pendingFg,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: _Amount(
                  label: 'المتاح',
                  amount:
                      (customer.creditLimitMinor -
                              customer.balanceMinor -
                              customer.pendingMinor)
                          .clamp(0, customer.creditLimitMinor),
                  color: QColors.brightGreen,
                  hidden: state.hideAmounts,
                ),
              ),
            ],
          ),
          if (hasPending) ...[
            const SizedBox(height: QSpace.sm),
            Row(
              children: [
                const QStatusBadge(status: TxStatus.pending, compact: true),
                const SizedBox(width: QSpace.sm),
                Expanded(
                  child: Text(
                    'بانتظار اعتماد عملية',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: QSpace.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDebt,
                  icon: const Icon(Icons.receipt_long_rounded, size: 17),
                  label: const Text('دين جديد'),
                ),
              ),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: TextButton(
                  onPressed: onOpen,
                  child: const Text('كشف الحساب'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.label,
    required this.amount,
    required this.color,
    required this.hidden,
  });

  final String label;
  final int amount;
  final Color color;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          formatMoney(amount, hidden: hidden),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return QCard(
      onTap: onTap,
      gradient: const LinearGradient(
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Row(
        children: [
          const QAvatar(label: 'دعوة', icon: Icons.person_add_alt_1_rounded),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أضف عميلاً وادعُه للتطبيق',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'شارك رابط الدعوة عبر واتساب أو الرسائل النصية.',
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
