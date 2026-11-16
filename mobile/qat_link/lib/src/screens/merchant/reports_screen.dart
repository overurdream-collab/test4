import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
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
    final approvedEntries = entries
        .where((entry) => entry.status == TxStatus.approved)
        .toList();
    final increases = _effectTotals(
      state,
      approvedEntries,
      OperationEffect.increase,
    );
    final decreases = _effectTotals(
      state,
      approvedEntries,
      OperationEffect.decrease,
    );
    final unappliedPayments = state.unappliedPaymentTotals(allEntries);
    final pending = _pendingTotals(state, entries);
    final approvedCount = approvedEntries.length;
    final contacts = isMerchant ? state.customers : state.customerMerchants;
    final top = [...contacts]
      ..sort(
        (a, b) => b
            .balanceFor(b.primaryCurrency)
            .compareTo(a.balanceFor(a.primaryCurrency)),
      );
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
                    increases: increases,
                    decreases: decreases,
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
                    increases: increases,
                    decreases: decreases,
                    unappliedPayments: unappliedPayments,
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

  Map<String, int> _effectTotals(
    AppState state,
    Iterable<LedgerEntry> entries,
    OperationEffect effect,
  ) {
    final totals = <String, int>{};
    for (final entry in entries) {
      if (state.effectOf(entry) != effect) continue;
      totals[entry.currency] =
          (totals[entry.currency] ?? 0) + state.effectAmountOf(entry);
    }
    return totals;
  }

  Map<String, int> _pendingTotals(
    AppState state,
    Iterable<LedgerEntry> entries,
  ) {
    final totals = <String, int>{};
    for (final entry in entries) {
      if (entry.status != TxStatus.pending &&
          entry.status != TxStatus.editRequested &&
          entry.status != TxStatus.local) {
        continue;
      }
      totals[entry.currency] =
          (totals[entry.currency] ?? 0) + state.signedEffectOf(entry);
    }
    totals.removeWhere((_, value) => value == 0);
    return totals;
  }
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.increases,
    required this.decreases,
    required this.pending,
    required this.count,
    required this.hidden,
  });

  final Map<String, int> increases;
  final Map<String, int> decreases;
  final Map<String, int> pending;
  final int count;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final net = <String, int>{
      for (final currency in {...increases.keys, ...decreases.keys})
        currency: (increases[currency] ?? 0) - (decreases[currency] ?? 0),
    };
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
            formatMoneyTotals(net, hidden: hidden),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
                  label: 'زيادة الدين',
                  value: formatMoneyTotals(
                    increases,
                    hidden: hidden,
                    compact: true,
                  ),
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: 'تخفيض الدين',
                  value: formatMoneyTotals(
                    decreases,
                    hidden: hidden,
                    compact: true,
                  ),
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: 'معلق',
                  value: formatMoneyTotals(
                    pending,
                    hidden: hidden,
                    compact: true,
                  ),
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
            maxLines: 2,
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
    required this.increases,
    required this.decreases,
    required this.unappliedPayments,
    required this.pending,
    required this.hidden,
  });

  final Map<String, int> increases;
  final Map<String, int> decreases;
  final Map<String, int> unappliedPayments;
  final Map<String, int> pending;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return QCard(
      child: Column(
        children: [
          _BreakdownRow(
            label: 'زيادة الدين (دين جديد/إرجاع)',
            value: increases,
            color: QColors.brightGreen,
            hidden: hidden,
          ),
          const Divider(height: QSpace.xl),
          _BreakdownRow(
            label: 'تخفيض الدين (إرجاع مبيعات/تخصيص)',
            value: decreases,
            color: QColors.approvedFg,
            hidden: hidden,
          ),
          const Divider(height: QSpace.xl),
          _BreakdownRow(
            label: 'دفعات غير مخصصة',
            value: unappliedPayments,
            color: QColors.brightGreen,
            hidden: hidden,
          ),
          const Divider(height: QSpace.xl),
          _BreakdownRow(
            label: 'صافي المبالغ المعلقة',
            value: pending,
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
  final Map<String, int> value;
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
          formatMoneyTotals(value, hidden: hidden, compact: true),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
