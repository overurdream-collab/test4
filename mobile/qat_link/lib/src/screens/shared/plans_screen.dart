import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../../state/app_state.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الباقات')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: QSpace.xxl),
        children: [
          QResponsiveBody(
            maxWidth: 900,
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
                      const Icon(
                        Icons.workspace_premium_outlined,
                        color: QColors.brightGreen,
                        size: 30,
                      ),
                      const SizedBox(width: QSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.subscriptionActive
                                  ? 'اشتراكك نشط'
                                  : 'اشتراكك منتهٍ',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'الأسعار تُحدد عند الإطلاق. لا توجد مدفوعات داخل التطبيق حالياً.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      QStatusBadge(
                        status: state.subscriptionActive
                            ? TxStatus.approved
                            : TxStatus.rejected,
                        compact: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                for (var index = 0; index < state.plans.length; index++) ...[
                  _PlanCard(
                    plan: state.plans[index],
                    selected: state.currentPlanIndex == index,
                    onSelect: () => _confirmPlan(context, state, index),
                  ),
                  const SizedBox(height: QSpace.md),
                ],
                QCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'وضع تجريبي',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: state.subscriptionActive,
                        onChanged: state.setSubscriptionActive,
                        title: const Text('اشتراك نشط'),
                        subtitle: const Text(
                          'أوقفه لمعاينة شاشة الاشتراك المنتهي.',
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
    );
  }

  Future<void> _confirmPlan(
    BuildContext context,
    AppState state,
    int index,
  ) async {
    if (state.currentPlanIndex == index) return;
    final plan = state.plans[index];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تغيير إلى ${plan.name}؟'),
        content: const Text(
          'سيُطبق التغيير تجريبياً على هذا الحساب. لا توجد أي عملية دفع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              state.selectPlan(index);
              Navigator.of(context).pop();
              QToast.show(context, 'تم اختيار ${plan.name}');
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onSelect,
  });

  final Plan plan;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return QCard(
      borderColor: selected
          ? QColors.brightGreen
          : plan.featured
          ? QColors.premiumGold.withValues(alpha: 0.6)
          : null,
      gradient: plan.featured
          ? const LinearGradient(colors: [QColors.softMint, QColors.pureWhite])
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          plan.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (plan.featured) ...[
                          const SizedBox(width: QSpace.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: QSpace.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: QColors.pendingBg,
                              borderRadius: BorderRadius.circular(QRadius.pill),
                            ),
                            child: Text(
                              'الأكثر اختياراً',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: QColors.pendingFg),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      plan.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: QColors.brightGreen,
                  size: 28,
                ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          for (final limit in plan.limits)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: QColors.brightGreen,
                  ),
                  const SizedBox(width: QSpace.sm),
                  Expanded(
                    child: Text(
                      limit,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: QSpace.sm),
          Row(
            children: [
              const Icon(
                Icons.photo_camera_back_outlined,
                size: 17,
                color: QColors.neutralGray,
              ),
              const SizedBox(width: 4),
              Text(
                '${plan.photosPerDay} صور يومياً',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                plan.priceLabel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: QSpace.md),
          SizedBox(
            width: double.infinity,
            child: selected
                ? const OutlinedButton(
                    onPressed: null,
                    child: Text('الباقة الحالية'),
                  )
                : QGradientButton(
                    label: 'اختيار الباقة',
                    height: 46,
                    onPressed: onSelect,
                  ),
          ),
        ],
      ),
    );
  }
}
