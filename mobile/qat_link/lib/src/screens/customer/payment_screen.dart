import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({required this.merchant, super.key});

  final Contact merchant;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _method = 'نقداً';
  bool _withReceipt = true;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final merchant = state.contactById(widget.merchant.id) ?? widget.merchant;
    final amountMinor =
        (int.tryParse(_amountController.text.trim()) ?? 0) * 100;

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل دفعة')),
      body: QResponsiveBody(
        maxWidth: 720,
        padding: const EdgeInsets.fromLTRB(
          QSpace.lg,
          QSpace.sm,
          QSpace.lg,
          QSpace.xxl,
        ),
        child: ListView(
          children: [
            QCard(
              gradient: const LinearGradient(
                colors: [QColors.softMint, QColors.pureWhite],
              ),
              child: Row(
                children: [
                  QAvatar(label: merchant.displayName, size: 52),
                  const SizedBox(width: QSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchant.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (merchant.category.isNotEmpty)
                          Text(
                            merchant.category,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'المستحق',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      QMoney(
                        minor: merchant.balanceMinor,
                        style: Theme.of(context).textTheme.titleSmall,
                        hidden: state.hideAmounts,
                      ),
                    ],
                  ),
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
            const SizedBox(height: QSpace.sm),
            Wrap(
              spacing: QSpace.sm,
              children: [
                ActionChip(
                  label: const Text('سداد كامل'),
                  onPressed: () => _setAmount(merchant.balanceMinor),
                ),
                ActionChip(
                  label: const Text('النصف'),
                  onPressed: () =>
                      _setAmount((merchant.balanceMinor / 2).round()),
                ),
                ActionChip(
                  label: const Text('الربع'),
                  onPressed: () =>
                      _setAmount((merchant.balanceMinor / 4).round()),
                ),
              ],
            ),
            const SizedBox(height: QSpace.lg),
            Text('طريقة الدفع', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: QSpace.sm),
            Wrap(
              spacing: QSpace.sm,
              children: [
                for (final method in ['نقداً', 'تحويل', 'محفظة'])
                  ChoiceChip(
                    label: Text(method),
                    selected: _method == method,
                    onSelected: (_) => setState(() => _method = method),
                  ),
              ],
            ),
            const SizedBox(height: QSpace.lg),
            QCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _withReceipt,
                onChanged: (value) => setState(() => _withReceipt = value),
                title: const Text('إرفاق صورة الإيصال'),
                subtitle: Text(
                  _withReceipt
                      ? 'سيُطلب منك التقاط صورة واضحة للإيصال.'
                      : 'يمكن للتاجر طلب الإيصال لاحقاً.',
                ),
              ),
            ),
            if (_withReceipt) ...[
              const SizedBox(height: QSpace.md),
              QCard(
                onTap: () => QToast.show(context, 'تم التقاط الإيصال تجريبياً'),
                borderColor: QColors.brightGreen.withValues(alpha: 0.45),
                child: Row(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: QColors.softMint,
                        borderRadius: BorderRadius.circular(QRadius.md),
                      ),
                      child: const Icon(
                        Icons.add_a_photo_outlined,
                        color: QColors.brightGreen,
                      ),
                    ),
                    const SizedBox(width: QSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إضافة صورة الإيصال',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            'صورة واحدة • اختيارية ولكنها تقوّي الثقة',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left_rounded),
                  ],
                ),
              ),
            ],
            const SizedBox(height: QSpace.md),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (state.offline) ...[
              const SizedBox(height: QSpace.md),
              const QOfflineBanner(),
            ],
            const SizedBox(height: QSpace.lg),
            QGradientButton(
              label: _saving
                  ? 'جارٍ الإرسال...'
                  : state.offline
                  ? 'حفظ محلياً'
                  : 'إرسال الدفعة للموافقة',
              icon: Icons.send_rounded,
              onPressed: amountMinor <= 0 || _saving
                  ? null
                  : () => _save(state, merchant, amountMinor),
            ),
            const SizedBox(height: QSpace.sm),
            Center(
              child: Text(
                'لن تُخصم الدفعة من رصيدك إلا بعد اعتماد التاجر.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setAmount(int minor) {
    _amountController.text = (minor / 100).round().toString();
    setState(() {});
  }

  Future<void> _save(AppState state, Contact merchant, int amountMinor) async {
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    state.addPayment(
      merchantContactId: merchant.id,
      amountMinor: amountMinor,
      method: _method,
      withReceipt: _withReceipt,
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
          : 'تم إرسال الدفعة إلى ${merchant.displayName}',
    );
  }
}
