import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';

class StatesGalleryScreen extends StatelessWidget {
  const StatesGalleryScreen({super.key});

  static const states = [
    QDataState.empty,
    QDataState.loading,
    QDataState.error,
    QDataState.success,
    QDataState.offline,
    QDataState.local,
    QDataState.syncing,
    QDataState.subscriptionExpired,
    QDataState.creditLimitExceeded,
  ];

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('حالات الواجهة')),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كل حالة لها لون وأيقونة ونص واضح',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: QSpace.xs),
                      Text(
                        'هذه المعاينة تتحقق من اتساق الحالات في الوضعين الفاتح والداكن.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: QSpace.md),
                      Wrap(
                        spacing: QSpace.sm,
                        runSpacing: QSpace.sm,
                        children: [
                          FilterChip(
                            label: const Text('دون اتصال'),
                            selected: state.offline,
                            onSelected: (_) => state.toggleOffline(),
                          ),
                          FilterChip(
                            label: const Text('اشتراك نشط'),
                            selected: state.subscriptionActive,
                            onSelected: (value) =>
                                state.setSubscriptionActive(value),
                          ),
                          FilterChip(
                            label: const Text('إخفاء المبالغ'),
                            selected: state.hideAmounts,
                            onSelected: (_) => state.toggleHideAmounts(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                if (state.offline) ...[
                  const QOfflineBanner(),
                  const SizedBox(height: QSpace.md),
                ],
                if (!state.subscriptionActive) ...[
                  _SubscriptionPreview(),
                  const SizedBox(height: QSpace.md),
                ],
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: states.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisSpacing: QSpace.md,
                    crossAxisSpacing: QSpace.md,
                    childAspectRatio: 0.86,
                  ),
                  itemBuilder: (context, index) {
                    final dataState = states[index];
                    return QCard(
                      child: Column(
                        children: [
                          Expanded(
                            child: QStateView(
                              state: dataState,
                              compact: true,
                              onRetry:
                                  dataState == QDataState.error ||
                                      dataState == QDataState.offline
                                  ? () => QToast.show(
                                      context,
                                      'إعادة المحاولة تجريبياً',
                                    )
                                  : null,
                            ),
                          ),
                          Text(
                            dataState.name,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: QColors.neutralGray),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: QSpace.lg),
                const QSectionHeader(
                  title: 'مكونات التحميل',
                  subtitle: 'هياكل عظمية قبل وصول البيانات',
                ),
                const QLoadingCard(height: 80),
                const SizedBox(height: QSpace.sm),
                const QLoadingCard(height: 80),
                const SizedBox(height: QSpace.sm),
                const QLoadingCard(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return QCard(
      borderColor: QColors.premiumGold.withValues(alpha: 0.65),
      gradient: const LinearGradient(
        colors: [QColors.pendingBg, QColors.pureWhite],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: QColors.premiumGold,
            size: 30,
          ),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'انتهى الاشتراك',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'كشف الحساب والتصدير متاحان، والعمليات الجديدة متوقفة مؤقتاً.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => QToast.show(context, 'تجديد تجريبي'),
            child: const Text('تجديد'),
          ),
        ],
      ),
    );
  }
}
