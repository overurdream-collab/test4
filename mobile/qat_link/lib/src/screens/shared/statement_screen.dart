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
  int _period = 0;
  int _status = 0;
  DateTimeRange? _range;

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
    final bounds = _bounds();
    final allEntries = isMerchant
        ? state.merchantEntries
        : state.customerEntries;
    final entries = allEntries.where((entry) {
      final matchesContact =
          _contactId == null ||
          (isMerchant
              ? entry.customerId == _contactId
              : entry.merchantId == _contactId);
      final matchesPeriod =
          bounds.start == null ||
          (!entry.createdAt.isBefore(bounds.start!) &&
              (bounds.end == null || entry.createdAt.isBefore(bounds.end!)));
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

    final approved = _effectTotals(
      state,
      entries.where((entry) => entry.status == TxStatus.approved),
    );
    final pending = _effectTotals(
      state,
      entries.where(
        (entry) =>
            entry.status == TxStatus.pending ||
            entry.status == TxStatus.editRequested ||
            entry.status == TxStatus.local,
      ),
    );
    final total = <String, int>{
      for (final currency in {...approved.keys, ...pending.keys})
        currency: (approved[currency] ?? 0) + (pending[currency] ?? 0),
    };

    final groups = <String, List<LedgerEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(formatDate(entry.createdAt), () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الحركة'),
        actions: [
          IconButton(
            tooltip: 'نطاق مخصص',
            onPressed: () => _pickRange(context),
            icon: Icon(
              _range == null
                  ? Icons.calendar_month_outlined
                  : Icons.event_available_rounded,
            ),
          ),
          IconButton(
            tooltip: 'تصدير',
            onPressed: entries.isEmpty
                ? null
                : () => _showExport(context, state, entries, selectedContact),
            icon: const Icon(Icons.ios_share_rounded),
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
                  _SummaryCard(
                    approved: approved,
                    pending: pending,
                    total: total,
                    count: entries.length,
                    periodLabel: _periodLabel(),
                    selectedContact: selectedContact,
                    onClearContact: () => setState(() => _contactId = null),
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
                    items: const [
                      'اليوم',
                      'أمس',
                      'آخر 7 أيام',
                      '30 يوماً',
                      'الكل',
                    ],
                    selected: _range == null ? _period : -1,
                    onSelected: (value) => setState(() {
                      _period = value;
                      _range = null;
                    }),
                  ),
                  if (_range != null) ...[
                    const SizedBox(height: QSpace.sm),
                    Row(
                      children: [
                        const Icon(
                          Icons.date_range_rounded,
                          size: 16,
                          color: QColors.brightGreen,
                        ),
                        const SizedBox(width: QSpace.xs),
                        Expanded(
                          child: Text(
                            '${formatDate(_range!.start)} - ${formatDate(_range!.end)}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _range = null),
                          child: const Text('مسح'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: QSpace.sm),
                  QFilterPills(
                    items: const ['كل الحالات', 'معتمد', 'معلق', 'مرفوض'],
                    selected: _status,
                    onSelected: (value) => setState(() => _status = value),
                  ),
                  const SizedBox(height: QSpace.lg),
                  QSectionHeader(
                    title: 'الحركات',
                    subtitle: '${entries.length} حركة • ${_periodLabel()}',
                    padding: const EdgeInsets.only(bottom: QSpace.sm),
                  ),
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
      ),
    );
  }

  ({DateTime? start, DateTime? end}) _bounds() {
    if (_range != null) {
      return (
        start: DateTime(
          _range!.start.year,
          _range!.start.month,
          _range!.start.day,
        ),
        end: DateTime(
          _range!.end.year,
          _range!.end.month,
          _range!.end.day,
        ).add(const Duration(days: 1)),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (_period) {
      0 => (start: today, end: tomorrow),
      1 => (start: today.subtract(const Duration(days: 1)), end: today),
      2 => (start: now.subtract(const Duration(days: 7)), end: tomorrow),
      3 => (start: now.subtract(const Duration(days: 30)), end: tomorrow),
      _ => (start: null, end: null),
    };
  }

  String _periodLabel() {
    if (_range != null) return 'نطاق مخصص';
    return switch (_period) {
      0 => 'اليوم',
      1 => 'أمس',
      2 => 'آخر 7 أيام',
      3 => 'آخر 30 يوماً',
      _ => 'كل الفترات',
    };
  }

  Map<String, int> _effectTotals(
    AppState state,
    Iterable<LedgerEntry> entries,
  ) {
    final totals = <String, int>{};
    for (final entry in entries) {
      totals[entry.currency] =
          (totals[entry.currency] ?? 0) + state.signedEffectOf(entry);
    }
    totals.removeWhere((_, value) => value == 0);
    return totals;
  }

  String _counterparty(AppState state, LedgerEntry entry, bool merchantView) {
    final contact = state.contactById(
      merchantView ? entry.customerId : entry.merchantId,
    );
    final base = contact?.displayName ?? 'حساب';
    final title = entry.productName ?? entry.type.label;
    return '$base • $title';
  }

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range,
      helpText: 'اختر فترة الحركة',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
      saveText: 'تطبيق',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _showExport(
    BuildContext context,
    AppState state,
    List<LedgerEntry> entries,
    Contact? contact,
  ) async {
    final pageContext = context;
    final csv = StringBuffer()
      ..writeln('التاريخ,النوع,الحالة,العملة,الأثر,المبلغ,البيان');
    for (final entry in entries) {
      final effect = state.effectOf(entry);
      final signed = effect.apply(state.effectAmountOf(entry));
      csv.writeln(
        '${formatDate(entry.createdAt)},${entry.type.label},${entry.status.label},'
        '${entry.currency},${effect.label},'
        '${(signed / 100).toStringAsFixed(2)},'
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
                title: 'تصدير الحركة',
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
                    QToast.show(pageContext, 'تم نسخ الحركة');
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.approved,
    required this.pending,
    required this.total,
    required this.count,
    required this.periodLabel,
    required this.selectedContact,
    required this.onClearContact,
  });

  final Map<String, int> approved;
  final Map<String, int> pending;
  final Map<String, int> total;
  final int count;
  final String periodLabel;
  final Contact? selectedContact;
  final VoidCallback onClearContact;

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
                      'ملخص الحركة',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$periodLabel • $count حركة',
                      style: Theme.of(context).textTheme.labelSmall,
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
                  color: QColors.pureWhite.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(QRadius.pill),
                ),
                child: Text(
                  'متعدد العملات',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: QColors.brightGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          Row(
            children: [
              Expanded(
                child: QSummaryCircle(
                  label: 'الإجمالي',
                  totals: total,
                  color: QColors.brightGreen,
                  size: 82,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: QSummaryCircle(
                  label: 'المعتمد',
                  totals: approved,
                  color: QColors.approvedFg,
                  size: 82,
                  hidden: state.hideAmounts,
                ),
              ),
              Expanded(
                child: QSummaryCircle(
                  label: 'المعلق',
                  totals: pending,
                  color: QColors.pendingFg,
                  size: 82,
                  hidden: state.hideAmounts,
                ),
              ),
            ],
          ),
          if (selectedContact != null) ...[
            const SizedBox(height: QSpace.md),
            Row(
              children: [
                QAvatar(label: selectedContact!.displayName, size: 32),
                const SizedBox(width: QSpace.sm),
                Expanded(
                  child: Text(
                    selectedContact!.displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: onClearContact,
                  child: const Text('كل الحسابات'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
