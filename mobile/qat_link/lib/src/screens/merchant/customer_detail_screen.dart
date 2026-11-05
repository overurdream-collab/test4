import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../shared/statement_screen.dart';
import 'new_debt_sheet.dart';

class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({required this.customer, super.key});

  final Contact customer;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final current = state.contactById(customer.id) ?? customer;
    final entries = state.entriesForCustomer(current.id);
    final canClose = state.canCloseCustomerFor(current.id);
    final groups = <String, List<LedgerEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(formatDate(entry.createdAt), () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(current.displayName),
        actions: [
          IconButton(
            tooltip: 'كشف الحساب',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StatementScreen(initialContactId: current.id),
              ),
            ),
            icon: const Icon(Icons.description_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'invite') {
                QToast.show(
                  context,
                  'تم تجهيز رابط دعوة ${current.displayName}',
                );
              } else if (value == 'statement') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        StatementScreen(initialContactId: current.id),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'invite', child: Text('دعوة للتطبيق')),
              PopupMenuItem(value: 'statement', child: Text('كشف الحساب')),
            ],
          ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: ListView(
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
                QCard(
                  gradient: const LinearGradient(
                    colors: [QColors.softMint, QColors.pureWhite],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          QAvatar(
                            label: current.displayName,
                            size: 58,
                            gradient: QColors.gradient,
                          ),
                          const SizedBox(width: QSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  current.displayName,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  current.phone,
                                  textDirection: TextDirection.ltr,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: QSpace.xs),
                                Row(
                                  children: [
                                    Icon(
                                      current.hasApp
                                          ? Icons.verified_rounded
                                          : Icons.person_add_alt_1_rounded,
                                      size: 14,
                                      color: current.hasApp
                                          ? QColors.brightGreen
                                          : QColors.neutralGray,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      current.hasApp
                                          ? 'لديه التطبيق'
                                          : 'لا يملك التطبيق',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: QSpace.lg),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniBalance(
                              label: 'المعتمد',
                              amount: current.balanceMinor,
                              color: QColors.approvedFg,
                              background: QColors.approvedBg,
                            ),
                          ),
                          const SizedBox(width: QSpace.md),
                          Expanded(
                            child: _MiniBalance(
                              label: 'المعلق',
                              amount: current.pendingMinor,
                              color: QColors.pendingFg,
                              background: QColors.pendingBg,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: QSpace.lg),
                      QCreditLimitBar(
                        usedMinor: current.balanceMinor + current.pendingMinor,
                        limitMinor: current.creditLimitMinor,
                        hidden: state.hideAmounts,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.receipt_long_rounded,
                        label: 'دين جديد',
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(QRadius.xl),
                            ),
                          ),
                          builder: (_) =>
                              NewDebtSheet(initialCustomerId: current.id),
                        ),
                      ),
                    ),
                    const SizedBox(width: QSpace.sm),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.notifications_active_outlined,
                        label: 'طلب تسديد',
                        onTap: () => _showReminder(context, current),
                      ),
                    ),
                    const SizedBox(width: QSpace.sm),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.lock_outline_rounded,
                        label: 'إغلاق الحساب',
                        enabled: canClose,
                        onTap: canClose
                            ? () => _confirmClose(context, current)
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: QSpace.lg),
                if (groups.isEmpty)
                  const QStateView(
                    state: QDataState.empty,
                    title: 'لا توجد حركات بعد',
                    message: 'سجل أول دين لهذا العميل ليبدأ الكشف المشترك.',
                  )
                else
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: QSpace.sm,
                        top: QSpace.sm,
                      ),
                      child: Row(
                        children: [
                          Text(
                            entry.key,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(width: QSpace.sm),
                          Expanded(
                            child: Divider(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    QCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < entry.value.length;
                            index++
                          ) ...[
                            QEntryTile(entry: entry.value[index]),
                            if (entry.value[index].status ==
                                    TxStatus.editRequested ||
                                (entry.value[index].status ==
                                        TxStatus.pending &&
                                    !entry.value[index].createdByMe))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  QSpace.md,
                                  0,
                                  QSpace.md,
                                  QSpace.md,
                                ),
                                child: _InlineActions(
                                  entry: entry.value[index],
                                ),
                              ),
                            if (index != entry.value.length - 1)
                              const Divider(),
                          ],
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReminder(BuildContext context, Contact contact) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب تسديد'),
        content: Text(
          'سيصل تذكير لطيف إلى ${contact.displayName} بمطالبة ودية بالسداد. '
          'طلب السداد الرسمي متاح مرة واحدة يومياً من شاشة العميل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              QToast.show(context, 'تم إرسال تذكير السداد');
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context, Contact contact) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إغلاق الحساب'),
        content: Text(
          'الرصيد صفر ولا توجد عمليات معلقة. سيُغلق حساب ${contact.displayName} '
          'مع الاحتفاظ الكامل بكشف الحساب السابق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              QToast.show(context, 'تم تجهيز طلب إغلاق الحساب');
            },
            child: const Text('إغلاق الحساب'),
          ),
        ],
      ),
    );
  }
}

class _MiniBalance extends StatelessWidget {
  const _MiniBalance({
    required this.label,
    required this.amount,
    required this.color,
    required this.background,
  });

  final String label;
  final int amount;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return Container(
      padding: const EdgeInsets.all(QSpace.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(QRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          QMoney(
            minor: amount,
            color: color,
            style: Theme.of(context).textTheme.titleMedium,
            hidden: state.hideAmounts,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: QCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.symmetric(
          horizontal: QSpace.sm,
          vertical: QSpace.md,
        ),
        child: Column(
          children: [
            Icon(icon, color: QColors.brightGreen),
            const SizedBox(height: QSpace.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineActions extends StatelessWidget {
  const _InlineActions({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    if (entry.status == TxStatus.editRequested) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => state.declineEdit(entry.id),
              child: const Text('رفض البديل'),
            ),
          ),
          const SizedBox(width: QSpace.sm),
          Expanded(
            child: FilledButton(
              onPressed: () => state.acceptEdit(entry.id),
              child: const Text('قبول البديل'),
            ),
          ),
        ],
      );
    }
    return Row(
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
            onPressed: () => _requestEdit(context, state, entry),
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
    );
  }

  Future<void> _requestEdit(
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
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
    if (amount != null) {
      state.requestEdit(entry.id, amount, 'طلب تعديل من التاجر');
      if (context.mounted) QToast.show(context, 'تم إرسال طلب التعديل');
    }
  }
}
