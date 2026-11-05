import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../shared/statement_screen.dart';
import 'payment_screen.dart';

class CustomerMerchantsScreen extends StatefulWidget {
  const CustomerMerchantsScreen({super.key});

  @override
  State<CustomerMerchantsScreen> createState() =>
      _CustomerMerchantsScreenState();
}

class _CustomerMerchantsScreenState extends State<CustomerMerchantsScreen> {
  final _searchController = TextEditingController();
  int _filter = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final query = _searchController.text.trim();
    final merchants = state.customerMerchants.where((merchant) {
      final matchesQuery =
          query.isEmpty ||
          merchant.displayName.contains(query) ||
          merchant.category.contains(query);
      final matchesFilter = switch (_filter) {
        1 => merchant.balanceMinor > 0,
        2 => merchant.pendingMinor > 0,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('التجار'),
        actions: [
          IconButton(
            tooltip: 'كشف الحساب',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatementScreen()),
            ),
            icon: const Icon(Icons.description_outlined),
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
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن تاجر أو نشاط',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: QSpace.md),
                  QFilterPills(
                    items: const ['الكل', 'عليهم رصيد', 'لديهم عمليات معلقة'],
                    selected: _filter,
                    onSelected: (value) => setState(() => _filter = value),
                  ),
                  const SizedBox(height: QSpace.md),
                  if (merchants.isEmpty)
                    const QStateView(
                      state: QDataState.empty,
                      title: 'لا يوجد تجار مطابقون',
                    )
                  else
                    for (final merchant in merchants) ...[
                      _MerchantCard(
                        merchant: merchant,
                        onPay: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PaymentScreen(merchant: merchant),
                          ),
                        ),
                        onSettle: () => _settle(context, state, merchant),
                      ),
                      const SizedBox(height: QSpace.md),
                    ],
                  const SizedBox(height: QSpace.sm),
                  QCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: QColors.brightGreen,
                        ),
                        const SizedBox(width: QSpace.md),
                        Expanded(
                          child: Text(
                            'الرصيد المعتمد نهائي. المبالغ المعلقة بانتظار موافقة أحد الطرفين.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
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

  void _settle(BuildContext context, AppState state, Contact merchant) {
    if (state.hasSettlementToday(merchant.id)) {
      QToast.show(context, 'لديك طلب سداد اليوم بالفعل');
      return;
    }
    state.requestSettlement(merchant.id);
    QToast.show(context, 'تم إرسال طلب السداد إلى ${merchant.displayName}');
  }
}

class _MerchantCard extends StatelessWidget {
  const _MerchantCard({
    required this.merchant,
    required this.onPay,
    required this.onSettle,
  });

  final Contact merchant;
  final VoidCallback onPay;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final limit = merchant.creditLimitMinor;
    final used = merchant.balanceMinor + merchant.pendingMinor;
    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QAvatar(
                label: merchant.displayName,
                size: 50,
                gradient: merchant.favorite
                    ? QColors.gradient
                    : LinearGradient(
                        colors: [
                          QColors.softMint,
                          QColors.lightGreen.withValues(alpha: 0.45),
                        ],
                      ),
              ),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (merchant.category.isNotEmpty)
                      Text(
                        merchant.category,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              if (merchant.favorite)
                const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: QColors.premiumGold,
                ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              Expanded(
                child: _Amount(
                  label: 'المعتمد',
                  amount: merchant.balanceMinor,
                  color: QColors.approvedFg,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: _Amount(
                  label: 'المعلق',
                  amount: merchant.pendingMinor,
                  color: QColors.pendingFg,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: _Amount(
                  label: 'المتاح',
                  amount: (limit - used).clamp(0, limit),
                  color: QColors.brightGreen,
                  hidden: state.hideAmounts,
                ),
              ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          QCreditLimitBar(
            usedMinor: used,
            limitMinor: limit,
            hidden: state.hideAmounts,
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              Expanded(
                child: QGradientButton(
                  label: 'تسجيل دفعة',
                  icon: Icons.payments_outlined,
                  height: 42,
                  onPressed: onPay,
                ),
              ),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSettle,
                  child: const Text('طلب سداد'),
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
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
