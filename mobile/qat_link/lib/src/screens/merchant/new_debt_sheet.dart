import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class NewDebtSheet extends StatefulWidget {
  const NewDebtSheet({super.key, this.initialCustomerId});

  final String? initialCustomerId;

  @override
  State<NewDebtSheet> createState() => _NewDebtSheetState();
}

class _NewDebtSheetState extends State<NewDebtSheet> {
  final _amountController = TextEditingController();
  final _productController = TextEditingController();
  final _noteController = TextEditingController();
  final _searchController = TextEditingController();
  String? _customerId;
  DateTime _date = DateTime.now();
  bool _creditConfirmed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _productController.dispose();
    _noteController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final customers = state.customers.where((customer) {
      final query = _searchController.text.trim();
      return query.isEmpty ||
          customer.displayName.contains(query) ||
          customer.phone.contains(query);
    }).toList();
    final selected = _customerId == null
        ? null
        : state.contactById(_customerId!);
    final amountMinor =
        (int.tryParse(_amountController.text.trim()) ?? 0) * 100;
    final exceedsLimit =
        selected != null &&
        selected.creditLimitMinor > 0 &&
        selected.balanceMinor + selected.pendingMinor + amountMinor >
            selected.creditLimitMinor;

    return Padding(
      padding: EdgeInsets.only(
        left: QSpace.xl,
        right: QSpace.xl,
        top: QSpace.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + QSpace.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QSheetHeader(
              title: selected == null ? 'اختر العميل' : 'دين جديد',
              subtitle: selected == null
                  ? 'الخطوة 1 من 2 • اختر من المفضلة أو ابحث'
                  : 'الخطوة 2 من 2 • أدخل المبلغ ثم احفظ',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: QSpace.lg),
            if (selected == null)
              _customerStep(state, customers)
            else
              _amountStep(state, selected, amountMinor, exceedsLimit),
            const SizedBox(height: QSpace.lg),
          ],
        ),
      ),
    );
  }

  Widget _customerStep(AppState state, List<Contact> customers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'ابحث بالاسم أو رقم الجوال',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: QSpace.md),
        if (state.favoriteCustomers.isNotEmpty) ...[
          Text('المفضلة', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: QSpace.sm),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.favoriteCustomers.length,
              separatorBuilder: (_, _) => const SizedBox(width: QSpace.sm),
              itemBuilder: (context, index) {
                final customer = state.favoriteCustomers[index];
                return InkWell(
                  onTap: () => setState(() => _customerId = customer.id),
                  borderRadius: BorderRadius.circular(QRadius.md),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        QAvatar(label: customer.displayName, size: 52),
                        const SizedBox(height: QSpace.xs),
                        Text(
                          customer.displayName.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: QSpace.md),
        ],
        Text('كل العملاء', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: QSpace.sm),
        if (customers.isEmpty)
          const QStateView(state: QDataState.empty, compact: true)
        else
          QCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < customers.length; index++) ...[
                  QContactTile(
                    contact: customers[index],
                    onTap: () =>
                        setState(() => _customerId = customers[index].id),
                  ),
                  if (index != customers.length - 1) const Divider(),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _amountStep(
    AppState state,
    Contact selected,
    int amountMinor,
    bool exceedsLimit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QCard(
          onTap: () => setState(() => _customerId = null),
          padding: const EdgeInsets.all(QSpace.md),
          child: Row(
            children: [
              QAvatar(label: selected.displayName, size: 44),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      'الرصيد: ${formatMoney(selected.balanceMinor, hidden: state.hideAmounts)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const Text('تغيير'),
            ],
          ),
        ),
        const SizedBox(height: QSpace.lg),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          style: Theme.of(context).textTheme.headlineMedium,
          decoration: const InputDecoration(
            labelText: 'المبلغ',
            hintText: '0',
            suffixText: 'ر.ي',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        const SizedBox(height: QSpace.md),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(QRadius.md),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'التاريخ',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(formatDate(_date)),
                ),
              ),
            ),
            const SizedBox(width: QSpace.md),
            Expanded(
              child: TextField(
                controller: _productController,
                decoration: const InputDecoration(
                  labelText: 'اسم المنتج (اختياري)',
                  prefixIcon: Icon(Icons.eco_outlined),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: QSpace.md),
        TextField(
          controller: _noteController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'ملاحظة (اختياري)',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        if (exceedsLimit) ...[
          const SizedBox(height: QSpace.md),
          QCard(
            borderColor: QColors.premiumGold.withValues(alpha: 0.7),
            gradient: const LinearGradient(
              colors: [QColors.pendingBg, QColors.pureWhite],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: QColors.pendingFg),
                    const SizedBox(width: QSpace.sm),
                    Text(
                      'تجاوز العميل الحد الائتماني',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: QColors.pendingFg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: QSpace.sm),
                Text(
                  'لن يتم التجاوز تلقائياً. يلزم تأكيدك للمتابعة.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                CheckboxListTile(
                  value: _creditConfirmed,
                  onChanged: (value) =>
                      setState(() => _creditConfirmed = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('أؤكد متابعة العملية مع تجاوز الحد'),
                ),
              ],
            ),
          ),
        ],
        if (state.offline) ...[
          const SizedBox(height: QSpace.md),
          const QOfflineBanner(),
        ],
        const SizedBox(height: QSpace.lg),
        QGradientButton(
          label: _saving
              ? 'جارٍ الحفظ...'
              : state.offline
              ? 'حفظ محلياً'
              : 'حفظ وإرسال للموافقة',
          icon: state.offline ? Icons.offline_pin_outlined : Icons.send_rounded,
          onPressed:
              amountMinor <= 0 || _saving || (exceedsLimit && !_creditConfirmed)
              ? null
              : () => _save(state, selected, amountMinor),
        ),
        const SizedBox(height: QSpace.sm),
        Center(
          child: Text(
            'لن تُعتمد العملية إلا بعد موافقة الطرف الآخر.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _save(AppState state, Contact selected, int amountMinor) async {
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    state.addDebt(
      customerId: selected.id,
      amountMinor: amountMinor,
      date: _date,
      productName: _productController.text.trim().isEmpty
          ? null
          : _productController.text.trim(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    QToast.show(
      context,
      state.offline
          ? 'تم الحفظ محلياً • ستُزامن عند عودة الاتصال'
          : 'تم إرسال الدين إلى ${selected.displayName} للموافقة',
    );
  }
}
