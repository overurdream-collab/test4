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
  String? _merchantId;
  DateTime? _date;
  int _status = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final query = _searchController.text.trim();
    final allMerchants = state.customerMerchants;
    final merchants = allMerchants.where((merchant) {
      final matchesQuery =
          query.isEmpty ||
          merchant.displayName.contains(query) ||
          merchant.category.contains(query);
      final matchesMerchant = _merchantId == null || merchant.id == _merchantId;
      return matchesQuery && matchesMerchant;
    }).toList();
    final selectedMerchant = _merchantId == null
        ? null
        : state.contactById(_merchantId!);
    final allEntries = state.customerEntries.where((entry) {
      final matchesMerchant =
          _merchantId == null || entry.merchantId == _merchantId;
      final matchesDate =
          _date == null ||
          (entry.createdAt.year == _date!.year &&
              entry.createdAt.month == _date!.month &&
              entry.createdAt.day == _date!.day);
      return matchesMerchant && matchesDate;
    }).toList();
    final summaryEntries = allEntries.where((entry) {
      return entry.status != TxStatus.rejected;
    }).toList();
    final approved = _net(summaryEntries, TxStatus.approved).abs();
    final pending = _pendingNet(summaryEntries).abs();
    final entries = allEntries.where((entry) {
      return switch (_status) {
        1 => entry.status == TxStatus.approved,
        2 =>
          entry.status == TxStatus.pending ||
              entry.status == TxStatus.editRequested ||
              entry.status == TxStatus.local,
        3 => entry.status == TxStatus.rejected,
        _ => true,
      };
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('التجار'),
        actions: [
          IconButton(
            tooltip: 'الحركة',
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
                  _TotalsBox(
                    totalMinor: approved + pending,
                    approvedMinor: approved,
                    pendingMinor: pending,
                    hidden: state.hideAmounts,
                  ),
                  const SizedBox(height: QSpace.md),
                  DropdownButtonFormField<String?>(
                    initialValue: _merchantId,
                    decoration: const InputDecoration(
                      labelText: 'التاجر',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('كل التجار'),
                      ),
                      for (final merchant in allMerchants)
                        DropdownMenuItem<String?>(
                          value: merchant.id,
                          child: Text(merchant.displayName),
                        ),
                    ],
                    onChanged: (value) => setState(() => _merchantId = value),
                  ),
                  const SizedBox(height: QSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(context),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            _date == null ? 'كل التواريخ' : formatDate(_date!),
                          ),
                        ),
                      ),
                      if (_date != null) ...[
                        const SizedBox(width: QSpace.sm),
                        IconButton(
                          tooltip: 'مسح التاريخ',
                          onPressed: () => setState(() => _date = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: QSpace.md),
                  QFilterPills(
                    items: const ['كل الحالات', 'معتمد', 'معلق', 'مرفوض'],
                    selected: _status,
                    onSelected: (value) => setState(() => _status = value),
                  ),
                  const SizedBox(height: QSpace.md),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن تاجر أو نشاط',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
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
                  if (selectedMerchant != null) ...[
                    const SizedBox(height: QSpace.sm),
                    QSectionHeader(
                      title: 'حركات ${selectedMerchant.displayName}',
                      subtitle: _date == null
                          ? 'كل التواريخ'
                          : formatDate(_date!),
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
                                  QEntryTile(
                                    entry: entries[index],
                                    title: entries[index].productName ??
                                        entries[index].type.label,
                                  ),
                                  if (index != entries.length - 1)
                                    const Divider(),
                                ],
                              ],
                            ),
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

  int _pendingNet(List<LedgerEntry> entries) {
    return entries
        .where(
          (entry) =>
              entry.status == TxStatus.pending ||
              entry.status == TxStatus.editRequested ||
              entry.status == TxStatus.local,
        )
        .fold<int>(0, (total, entry) {
          final signed =
              entry.type == OperationType.charge ||
                  entry.type == OperationType.creditApplication
              ? entry.amountMinor
              : -entry.amountMinor;
          return total + signed;
        });
  }

  int _net(List<LedgerEntry> entries, TxStatus status) {
    return entries
        .where((entry) => entry.status == status)
        .fold<int>(0, (total, entry) {
          final signed =
              entry.type == OperationType.charge ||
                  entry.type == OperationType.creditApplication
              ? entry.amountMinor
              : -entry.amountMinor;
          return total + signed;
        });
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _date = picked);
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

class _TotalsBox extends StatelessWidget {
  const _TotalsBox({
    required this.totalMinor,
    required this.approvedMinor,
    required this.pendingMinor,
    required this.hidden,
  });

  final int totalMinor;
  final int approvedMinor;
  final int pendingMinor;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return QCard(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إجمالي المبالغ',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: QSpace.md),
          Row(
            children: [
              Expanded(
                child: _SummaryCircle(
                  label: 'الإجمالي',
                  amountMinor: totalMinor,
                  color: QColors.brightGreen,
                  hidden: hidden,
                ),
              ),
              Expanded(
                child: _SummaryCircle(
                  label: 'المعتمد',
                  amountMinor: approvedMinor,
                  color: QColors.rejectedFg,
                  hidden: hidden,
                ),
              ),
              Expanded(
                child: _SummaryCircle(
                  label: 'المعلق',
                  amountMinor: pendingMinor,
                  color: QColors.pendingFg,
                  hidden: hidden,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCircle extends StatelessWidget {
  const _SummaryCircle({
    required this.label,
    required this.amountMinor,
    required this.color,
    required this.hidden,
  });

  final String label;
  final int amountMinor;
  final Color color;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(QSpace.xs),
            child: Text(
              hidden ? '••••' : formatCompactMoney(amountMinor),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: QSpace.xs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
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
