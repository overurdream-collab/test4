import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../customer/customer_home_screen.dart';
import '../customer/customer_merchants_screen.dart';
import '../customer/payment_screen.dart';
import '../merchant/merchant_customers_screen.dart';
import '../merchant/merchant_home_screen.dart';
import '../merchant/new_customer_screen.dart';
import '../merchant/new_debt_sheet.dart';
import 'settings_screen.dart';
import 'statement_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final isMerchant = state.persona == AppPersona.merchant;
    final screens = isMerchant
        ? const [
            MerchantHomeScreen(),
            MerchantCustomersScreen(),
            StatementScreen(),
            SettingsScreen(),
          ]
        : const [
            CustomerHomeScreen(),
            CustomerMerchantsScreen(),
            StatementScreen(),
            SettingsScreen(),
          ];
    final safeIndex = _index.clamp(0, screens.length - 1);

    return Scaffold(
      body: Column(
        children: [
          if (state.offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                QSpace.lg,
                QSpace.sm,
                QSpace.lg,
                0,
              ),
              child: QOfflineBanner(onRetry: state.toggleOffline),
            ),
          if (!state.subscriptionActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                QSpace.lg,
                QSpace.sm,
                QSpace.lg,
                0,
              ),
              child: _SubscriptionBanner(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
            ),
          Expanded(child: screens[safeIndex]),
        ],
      ),
      bottomNavigationBar: _QBottomBar(
        selected: safeIndex,
        isMerchant: isMerchant,
        onSelected: (value) => setState(() => _index = value),
        onQuickAction: _openQuickActions,
      ),
    );
  }

  Future<void> _openQuickActions() async {
    final state = QScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(QSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const QSheetHeader(
                  title: 'إضافة سريعة',
                  subtitle: 'أقل من 10 ثوانٍ لتسجيل العملية',
                ),
                const SizedBox(height: QSpace.lg),
                if (state.persona == AppPersona.merchant) ...[
                  _QuickAction(
                    icon: Icons.receipt_long_rounded,
                    title: 'دين جديد',
                    subtitle: 'اختر العميل ثم المبلغ ثم احفظ',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(QRadius.xl),
                          ),
                        ),
                        builder: (_) => const NewDebtSheet(),
                      );
                    },
                  ),
                  const SizedBox(height: QSpace.md),
                  _QuickAction(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'عميل جديد',
                    subtitle: 'من جهات الاتصال أو برقم الجوال',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const NewCustomerScreen(),
                        ),
                      );
                    },
                  ),
                ] else ...[
                  _QuickAction(
                    icon: Icons.payments_outlined,
                    title: 'تسجيل دفعة',
                    subtitle: 'مع إمكانية إرفاق الإيصال',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _chooseMerchant(
                        onSelected: (merchant) => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PaymentScreen(merchant: merchant),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: QSpace.md),
                  _QuickAction(
                    icon: Icons.handshake_outlined,
                    title: 'طلب سداد',
                    subtitle: 'طلب واحد يومياً لكل تاجر',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _chooseMerchant(
                        onSelected: (merchant) {
                          state.requestSettlement(merchant.id);
                          QToast.show(
                            context,
                            state.hasSettlementToday(merchant.id)
                                ? 'تم إرسال طلب السداد إلى ${merchant.displayName}'
                                : 'لديك طلب سداد اليوم بالفعل',
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _chooseMerchant({
    required ValueChanged<Contact> onSelected,
  }) async {
    final state = QScope.of(context);
    final merchants = state.customerMerchants;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(QSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const QSheetHeader(title: 'اختر التاجر'),
                const SizedBox(height: QSpace.lg),
                for (final merchant in merchants) ...[
                  QContactTile(
                    contact: merchant,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onSelected(merchant);
                    },
                  ),
                  const Divider(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return QCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: QColors.gradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: QColors.charcoal),
          ),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded, color: QColors.neutralGray),
        ],
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return QCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: QSpace.md,
        vertical: QSpace.sm,
      ),
      gradient: LinearGradient(
        colors: [QColors.premiumGold.withValues(alpha: 0.22), QColors.softMint],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: QColors.pendingFg,
          ),
          const SizedBox(width: QSpace.sm),
          Expanded(
            child: Text(
              'انتهى الاشتراك • القراءة والتصدير متاحان',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: QColors.pendingFg),
            ),
          ),
          const Icon(Icons.chevron_left_rounded, size: 18),
        ],
      ),
    );
  }
}

class _QBottomBar extends StatelessWidget {
  const _QBottomBar({
    required this.selected,
    required this.isMerchant,
    required this.onSelected,
    required this.onQuickAction,
  });

  final int selected;
  final bool isMerchant;
  final ValueChanged<int> onSelected;
  final VoidCallback onQuickAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      (icon: Icons.home_rounded, label: 'الرئيسية'),
      (
        icon: isMerchant ? Icons.people_alt_rounded : Icons.storefront_rounded,
        label: isMerchant ? 'العملاء' : 'التجار',
      ),
      (icon: Icons.description_outlined, label: 'الكشف'),
      (icon: Icons.settings_outlined, label: 'الإعدادات'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? QColors.nightSurface : QColors.pureWhite,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF243A2E) : const Color(0xFFE8F1EC),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(child: _item(context, 0, items[0].icon, items[0].label)),
              Expanded(child: _item(context, 1, items[1].icon, items[1].label)),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: onQuickAction,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        gradient: QColors.gradient,
                        shape: BoxShape.circle,
                        boxShadow: QColors.brandGlow,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: QColors.charcoal,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: _item(context, 2, items[2].icon, items[2].label)),
              Expanded(child: _item(context, 3, items[3].icon, items[3].label)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int index, IconData icon, String label) {
    final active = selected == index;
    return InkWell(
      onTap: () => onSelected(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 23,
            color: active ? QColors.brightGreen : QColors.neutralGray,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active ? QColors.brightGreen : QColors.neutralGray,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
