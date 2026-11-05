import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key, this.initialContactId});

  final String? initialContactId;

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  String? _contactId;
  int _period = 2;
  int _status = 0;

  @override
  void initState() {
    super.initState();
    _contactId = widget.initialContactId;
  }

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isMerchant = state.persona == AppPersona.merchant;
    final contacts = isMerchant ? state.customers : state.customerMerchants;
    final selectedContact = _contactId == null
        ? null
        : state.contactById(_contactId!);
    final now = DateTime.now();
    final start = switch (_period) {
      0 => DateTime(now.year, now.month, now.day),
      1 => now.subtract(const Duration(days: 7)),
      3 => now.subtract(const Duration(days: 30)),
      _ => null,
    };
    final allEntries = isMerchant
        ? state.merchantEntries
        : state.customerEntries;
    final entries = allEntries.where((entry) {
      final matchesContact =
          _contactId == null ||
          (isMerchant
              ? entry.customerId == _contactId
              : entry.merchantId == _contactId);
      final matchesPeriod = start == null || entry.createdAt.isAfter(start);
      final matchesStatus = switch (_status) {
        1 => entry.status == TxStatus.approved,
        2 =>
          entry.status == TxStatus.pending ||
              entry.status == TxStatus.editRequested ||
              entry.status == TxStatus.local,
        3 => entry.status == TxStatus.rejected,
        _ => true,
      };
      return matchesContact && matchesPeriod && matchesStatus;
    }).toList();

    final approved = entries
        .where((entry) => entry.status == TxStatus.approved)
        .fold<int>(0, (total, entry) {
          final signed =
              entry.type == OperationType.charge ||
                  entry.type == OperationType.creditApplication
              ? entry.amountMinor
              : -entry.amountMinor;
          return total + signed;
        });
    final pending = entries
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

    final groups = <String, List<LedgerEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(formatDate(entry.createdAt), () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف الحساب'),
        actions: [
          IconButton(
            tooltip: 'تصدير',
            onPressed: entries.isEmpty
                ? null
                : () => _showExport(context, entries, selectedContact),
            icon: const Icon(Icons.ios_share_rounded),
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isMerchant
                                      ? 'صافي الحركة'
                                      : 'صافي الحركة عليه',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                                const SizedBox(height: QSpace.xs),
                                QMoney(
                                  minor: approved.abs(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                  hidden: state.hideAmounts,
                                ),
                              ],
                            ),
                          ),
                          _SummaryChip(
                            label: 'معلق',
                            amount: pending.abs(),
                            color: QColors.pendingFg,
                          ),
                          const SizedBox(width: QSpace.sm),
                          _SummaryChip(
                            label: 'الحركات',
                            amount: null,
                            value: '${entries.length}',
                            color: QColors.brightGreen,
                          ),
                        ],
                      ),
                      const SizedBox(height: QSpace.md),
                      if (selectedContact != null)
                        Row(
                          children: [
                            QAvatar(
                              label: selectedContact.displayName,
                              size: 34,
                            ),
                            const SizedBox(width: QSpace.sm),
                            Expanded(
                              child: Text(
                                selectedContact.displayName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _contactId = null),
                              child: const Text('كل الحسابات'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.md),
                DropdownButtonFormField<String?>(
                  initialValue: _contactId,
                  decoration: InputDecoration(
                    labelText: isMerchant ? 'العميل' : 'التاجر',
                    prefixIcon: const Icon(Icons.person_search_outlined),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(isMerchant ? 'كل العملاء' : 'كل التجار'),
                    ),
                    for (final contact in contacts)
                      DropdownMenuItem<String?>(
                        value: contact.id,
                        child: Text(contact.displayName),
                      ),
                  ],
                  onChanged: (value) => setState(() => _contactId = value),
                ),
                const SizedBox(height: QSpace.md),
                QFilterPills(
                  items: const ['اليوم', '7 أيام', '30 يوماً', 'الكل'],
                  selected: _period,
                  onSelected: (value) => setState(() => _period = value),
                ),
                const SizedBox(height: QSpace.sm),
                QFilterPills(
                  items: const ['كل الحالات', 'معتمد', 'معلق', 'مرفوض'],
                  selected: _status,
                  onSelected: (value) => setState(() => _status = value),
                ),
                const SizedBox(height: QSpace.lg),
                if (entries.isEmpty)
                  const QStateView(
                    state: QDataState.empty,
                    title: 'لا توجد حركات في هذه الفترة',
                  )
                else
                  for (final group in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        top: QSpace.sm,
                        bottom: QSpace.sm,
                      ),
                      child: Row(
                        children: [
                          Text(
                            group.key,
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
                          Text(
                            '${group.value.length} حركة',
                            style: Theme.of(context).textTheme.labelSmall,
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
                            index < group.value.length;
                            index++
                          ) ...[
                            QEntryTile(
                              entry: group.value[index],
                              title: isMerchant
                                  ? _counterparty(
                                      state,
                                      group.value[index],
                                      true,
                                    )
                                  : _counterparty(
                                      state,
                                      group.value[index],
                                      false,
                                    ),
                            ),
                            if (index != group.value.length - 1)
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

  String _counterparty(AppState state, LedgerEntry entry, bool merchantView) {
    final contact = state.contactById(
      merchantView ? entry.customerId : entry.merchantId,
    );
    final base = contact?.displayName ?? 'حساب';
    final title = entry.productName ?? entry.type.label;
    return '$base • $title';
  }

  Future<void> _showExport(
    BuildContext context,
    List<LedgerEntry> entries,
    Contact? contact,
  ) async {
    final pageContext = context;
    final csv = StringBuffer()..writeln('التاريخ,النوع,الحالة,المبلغ,البيان');
    for (final entry in entries) {
      csv.writeln(
        '${formatDate(entry.createdAt)},${entry.type.label},${entry.status.label},'
        '${(entry.amountMinor / 100).toStringAsFixed(2)},'
        '${(entry.productName ?? entry.note ?? '').replaceAll(',', ' ')}',
      );
    }

    await showModalBottomSheet<void>(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QSheetHeader(
                title: 'تصدير كشف الحساب',
                subtitle: contact?.displayName ?? 'كل الحسابات',
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: QSpace.lg),
              QCard(
                child: Text(
                  '${entries.length} حركة جاهزة للتصدير بصيغة CSV. '
                  'يمكنك لصقها في Excel أو مشاركتها عبر التطبيقات.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: QSpace.lg),
              QGradientButton(
                label: 'نسخ ملف CSV',
                icon: Icons.copy_all_outlined,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: csv.toString()));
                  if (pageContext.mounted) {
                    Navigator.of(pageContext).pop();
                    QToast.show(pageContext, 'تم نسخ كشف الحساب');
                  }
                },
              ),
              const SizedBox(height: QSpace.sm),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  QToast.show(pageContext, 'تم تجهيز ملف PDF تجريبي');
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('تصدير PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.color,
    this.amount,
    this.value,
  });

  final String label;
  final Color color;
  final int? amount;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QSpace.md,
        vertical: QSpace.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
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
          Text(
            amount == null
                ? value ?? ''
                : formatMoney(amount!, hidden: state.hideAmounts),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
