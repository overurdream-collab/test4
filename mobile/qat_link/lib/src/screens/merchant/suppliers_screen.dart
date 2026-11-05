import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final suppliers = state.suppliers;
    final total = suppliers.fold<int>(
      0,
      (sum, supplier) => sum + supplier.balanceMinor,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('الموردون'),
        actions: [
          IconButton(
            tooltip: 'إضافة مورد',
            onPressed: () => _showAddSupplier(context, state),
            icon: const Icon(Icons.add_business_outlined),
          ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: QSpace.xxl),
        children: [
          QResponsiveBody(
            maxWidth: 760,
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إجمالي مستحقات الموردين',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: QSpace.xs),
                            QMoney(
                              minor: total,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                              hidden: state.hideAmounts,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: QColors.gradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: QColors.charcoal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                QSectionHeader(
                  title: 'قائمة الموردين',
                  subtitle: '${suppliers.length} مورد',
                ),
                if (suppliers.isEmpty)
                  QStateView(
                    state: QDataState.empty,
                    title: 'لا يوجد موردون',
                    message: 'أضف مورداً لمتابعة أرصدته بشكل منفصل.',
                    onRetry: () => _showAddSupplier(context, state),
                  )
                else
                  for (final supplier in suppliers) ...[
                    _SupplierCard(supplier: supplier),
                    const SizedBox(height: QSpace.md),
                  ],
                const SizedBox(height: QSpace.sm),
                OutlinedButton.icon(
                  onPressed: () => _showAddSupplier(context, state),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('إضافة مورد'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSupplier(BuildContext context, AppState state) async {
    final pageContext = context;
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final storeController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
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
                  title: 'مورد جديد',
                  subtitle: 'يُحفظ حساب المورد منفصلاً عن العملاء.',
                  onClose: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: QSpace.lg),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المورد',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: QSpace.md),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم الجوال',
                    prefixIcon: Icon(Icons.phone_iphone_rounded),
                  ),
                ),
                const SizedBox(height: QSpace.md),
                TextField(
                  controller: storeController,
                  decoration: const InputDecoration(
                    labelText: 'اسم النشاط (اختياري)',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                QGradientButton(
                  label: 'حفظ المورد',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        phoneController.text.trim().length < 8) {
                      QToast.show(
                        sheetContext,
                        'أدخل الاسم ورقم الجوال',
                        error: true,
                      );
                      return;
                    }
                    state.addSupplier(
                      name: nameController.text.trim(),
                      phone: phoneController.text.trim(),
                      storeName: storeController.text.trim(),
                    );
                    Navigator.of(sheetContext).pop();
                    QToast.show(pageContext, 'تمت إضافة المورد');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});

  final Contact supplier;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return QCard(
      child: Row(
        children: [
          QAvatar(
            label: supplier.displayName,
            size: 50,
            gradient: LinearGradient(
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
                  supplier.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  supplier.name,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  supplier.phone,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('المستحق', style: Theme.of(context).textTheme.labelSmall),
              Text(
                formatMoney(supplier.balanceMinor, hidden: state.hideAmounts),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: QColors.approvedFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (supplier.pendingMinor > 0)
                Text(
                  'معلق ${formatMoney(supplier.pendingMinor, hidden: state.hideAmounts)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: QColors.pendingFg),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
