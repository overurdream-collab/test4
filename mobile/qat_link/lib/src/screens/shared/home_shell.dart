import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../customer/customer_home_screen.dart';
import '../customer/customer_merchants_screen.dart';
import '../customer/payment_screen.dart';
import '../merchant/merchant_customers_screen.dart';
import '../merchant/merchant_home_screen.dart';
import '../merchant/new_customer_screen.dart';
import '../merchant/new_debt_sheet.dart';
import 'photos_screen.dart';
import 'settings_screen.dart';
import 'statement_screen.dart';
import 'store_screen.dart';

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
            StatementScreen(),
            StoreScreen(),
            MerchantCustomersScreen(),
            SettingsScreen(),
          ]
        : const [
            CustomerHomeScreen(),
            StatementScreen(),
            StoreScreen(),
            CustomerMerchantsScreen(),
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
        onAdd: () => _showAddMenu(context, state, isMerchant),
      ),
    );
  }

  Future<void> _showAddMenu(
    BuildContext context,
    AppState state,
    bool isMerchant,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: Theme.of(sheetContext).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(QRadius.xl),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              QSpace.lg,
              QSpace.lg,
              QSpace.lg,
              QSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const QSheetHeader(
                  title: 'اختيار نوع الإضافة',
                  subtitle: 'إجراء سريع من شريط التنقل',
                ),
                const SizedBox(height: QSpace.md),
                if (isMerchant) ...[
                  _AddAction(
                    icon: Icons.money_off_csred_rounded,
                    color: QColors.danger,
                    background: QColors.dangerSoft,
                    title: 'تسجيل دين جديد',
                    subtitle: 'أضف مبلغاً على حساب عميل',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openDebt(context, state);
                    },
                  ),
                  _AddAction(
                    icon: Icons.person_add_alt_1_rounded,
                    color: QColors.brightGreen,
                    background: QColors.softMint,
                    title: 'إضافة عميل جديد',
                    subtitle: 'أنشئ علاقة أو أرسل دعوة',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const NewCustomerScreen(),
                        ),
                      );
                    },
                  ),
                  _AddAction(
                    icon: Icons.description_outlined,
                    color: QColors.pendingFg,
                    background: QColors.pendingBg,
                    title: 'مراجعة الحركة',
                    subtitle: 'اعتمد أو راجع العمليات المعلقة',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() => _index = 1);
                    },
                  ),
                ] else ...[
                  _AddAction(
                    icon: Icons.attach_money_rounded,
                    color: QColors.approvedFg,
                    background: QColors.approvedBg,
                    title: 'تسجيل دفعة',
                    subtitle: 'سدد مبلغاً لتاجر',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openPayment(context, state);
                    },
                  ),
                  _AddAction(
                    icon: Icons.handshake_outlined,
                    color: QColors.brightGreen,
                    background: QColors.softMint,
                    title: 'طلب سداد',
                    subtitle: 'أرسل طلب سداد للتاجر',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _requestSettlement(context, state);
                    },
                  ),
                  _AddAction(
                    icon: Icons.photo_library_outlined,
                    color: QColors.pendingFg,
                    background: QColors.pendingBg,
                    title: 'صور اليوم',
                    subtitle: 'أضف صورة أو راجع صورك',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PhotosScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDebt(BuildContext context, AppState state) {
    if (state.customers.isEmpty) {
      QToast.show(context, 'أضف عميلاً أولاً لتسجيل دين جديد');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadius.xl)),
      ),
      builder: (_) => const NewDebtSheet(),
    );
  }

  void _openPayment(BuildContext context, AppState state) {
    final merchants = state.customerMerchants;
    if (merchants.isEmpty) {
      QToast.show(context, 'لا يوجد تاجر مرتبط بحسابك بعد');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentScreen(merchant: merchants.first),
      ),
    );
  }

  void _requestSettlement(BuildContext context, AppState state) {
    final merchants = state.customerMerchants;
    if (merchants.isEmpty) {
      QToast.show(context, 'لا يوجد تاجر مرتبط بحسابك بعد');
      return;
    }
    final merchant = merchants.first;
    if (state.hasSettlementToday(merchant.id)) {
      QToast.show(context, 'لديك طلب سداد اليوم بالفعل');
      return;
    }
    state.requestSettlement(merchant.id);
    QToast.show(context, 'تم إرسال طلب السداد إلى ${merchant.displayName}');
  }
}

class _AddAction extends StatelessWidget {
  const _AddAction({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left_rounded),
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
    required this.onAdd,
  });

  final int selected;
  final bool isMerchant;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      (icon: Icons.home_rounded, label: 'الرئيسية'),
      (icon: Icons.swap_horiz_rounded, label: 'الحركة'),
      (
        icon: Icons.people_alt_rounded,
        label: isMerchant ? 'العملاء' : 'التجار',
      ),
      (icon: Icons.settings_outlined, label: 'الضبط'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? QColors.nightSurface : QColors.pureWhite,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF273449) : const Color(0xFFE4EFF0),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 78,
          child: Row(
            children: [
              Expanded(child: _item(context, 0, items[0].icon, items[0].label)),
              Expanded(child: _item(context, 1, items[1].icon, items[1].label)),
              Expanded(child: _centerItem(context)),
              Expanded(child: _item(context, 3, items[2].icon, items[2].label)),
              Expanded(child: _item(context, 4, items[3].icon, items[3].label)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centerItem(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, -16),
          child: GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: QColors.addGradient,
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? QColors.nightSurface
                      : QColors.pureWhite,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: QColors.danger.withValues(alpha: 0.42),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                color: QColors.pureWhite,
                size: 30,
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -10),
          child: InkWell(
            onTap: () => onSelected(2),
            child: Text(
              isMerchant ? 'متجري' : 'حسابي',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: selected == 2
                    ? QColors.brightGreen
                    : QColors.neutralGray,
                fontWeight: selected == 2 ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
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
              fontSize: 9,
              color: active ? QColors.brightGreen : QColors.neutralGray,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
