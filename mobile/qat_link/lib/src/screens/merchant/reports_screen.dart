import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../shared/statement_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _period = 1;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isMerchant = state.persona == AppPersona.merchant;
    final allEntries = isMerchant
        ? state.merchantEntries
        : state.customerEntries;
    final now = DateTime.now();
    final start = switch (_period) {
      0 => DateTime(now.year, now.month, now.day),
      1 => now.subtract(const Duration(days: 7)),
      2 => DateTime(now.year, now.month, 1),
      _ => DateTime(now.year, 1, 1),
    };
    final entries = allEntries
        .where(
          (entry) =>
              !entry.createdAt.isBefore(start) &&
              entry.status != TxStatus.rejected,
        )
        .toList();
    final charges = _sum(
      entries.where(
        (entry) =>
            entry.type == OperationType.charge ||
            entry.type == OperationType.creditApplication,
      ),
    );
    final payments = _sum(
      entries.where(
        (entry) =>
            entry.type == OperationType.payment ||
            entry.type == OperationType.refund ||
            entry.type == OperationType.salesReturn,
      ),
    );
    final pending = _sum(
      entries.where(
        (entry) =>
            entry.status == TxStatus.pending ||
            entry.status == TxStatus.editRequested ||
            entry.status == TxStatus.local,
      ),
    );
    final approvedCount = entries
        .where((entry) => entry.status == TxStatus.approved)
        .length;
    final contacts = isMerchant ? state.customers : state.customerMerchants;
    final top = [...contacts]
      ..sort((a, b) => b.balanceMinor.compareTo(a.balanceMinor));
    final topEntries = top.take(4).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير'),
        actions: [
          IconButton(
            tooltip: 'الحركة التفصيلية',
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
                  QFilterPills(
                    items: const ['اليوم', '7 أيام', 'هذا الشهر', 'هذه السنة'],
                    selected: _period,
                    onSelected: (value) => setState(() => _period = value),
                  ),
                  const SizedBox(height: QSpace.md),
                  _SummaryHero(
                    charges: charges,
                    payments: payments,
                    pending: pending,
                    count: approvedCount,
                    hidden: state.hideAmounts,
                  ),
                  const SizedBox(height: QSpace.lg),
                  const QSectionHeader(
                    title: 'التوزيع',
                    subtitle: 'حسب نوع العملية',
                  ),
                  _BreakdownCard(
                    charges: charges,
                    payments: payments,
                    pending: pending,
                    hidden: state.hideAmounts,
                  ),
                  const SizedBox(height: QSpace.xl),
                  QSectionHeader(
                    title: isMerchant ? 'أعلى العملاء' : 'أعلى التجار',
                    subtitle: 'حسب الرصيد المعتمد',
                  ),
                  if (topEntries.isEmpty)
                    const QStateView(state: QDataState.empty, compact: true)
                  else
                    for (var index = 0; index < topEntries.length; index++) ...[
                      QContactTile(
                        contact: topEntries[index],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StatementScreen(
                              initialContactId: topEntries[index].id,
                            ),
                          ),
                        ),
                      ),
                      if (index != topEntries.length - 1) const Divider(),
                    ],
                  const SizedBox(height: QSpace.lg),
                  QGradientButton(
                    label: 'عرض الحركة والتصدير',
                    icon: Icons.ios_share_rounded,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StatementScreen(),
                      ),
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

  int _sum(Iterable<LedgerEntry> entries) {
    return entries.fold<int>(0, (total, entry) {
      final signed =
          entry.type == OperationType.charge ||
              entry.type == OperationType.creditApplication
          ? entry.amountMinor
          : -entry.amountMinor;
      return total + signed;
    });
  }
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.charges,
    required this.payments,
    required this.pending,
    required this.count,
    required this.hidden,
  });

  final int charges;
  final int payments;
  final int pending;
  final int count;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final net = charges - payments;
    return QCard(
      gradient: QColors.gradient,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: QColors.pureWhite),
              const SizedBox(width: QSpace.sm),
              Text(
                'صافي الحركة',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: QColors.pureWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$count عملية معتمدة',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          Text(
            formatMoney(net.abs(), hidden: hidden),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: QColors.pureWhite,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: QSpace.lg),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: 'ديون جديدة',
                  value: formatCompactMoney(charges),
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: 'تحصيلات',
                  value: formatCompactMoney(payments),
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: 'معلق',
                  value: formatCompactMoney(pending.abs()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: QSpace.xs),
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
              color: Colors.white.withValues(alpha: 0.8),
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

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.charges,
    required this.payments,
    required this.pending,
    required this.hidden,
  });

  final int charges;
  final int payments;
  final int pending;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return QCard(
      child: Column(
        children: [
          _BreakdownRow(
            label: 'ديون جديدة',
            value: charges,
            color: QColors.brightGreen,
            hidden: hidden,
          ),
          const Divider(height: QSpace.xl),
          _BreakdownRow(
            label: 'تحصيلات ومدفوعات',
            value: payments,
            color: QColors.approvedFg,
            hidden: hidden,
          ),
          const Divider(height: QSpace.xl),
          _BreakdownRow(
            label: 'مبالغ معلقة',
            value: pending.abs(),
            color: QColors.pendingFg,
            hidden: hidden,
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.color,
    required this.hidden,
  });

  final String label;
  final int value;
  final Color color;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: QSpace.sm),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          formatMoney(value, hidden: hidden),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
