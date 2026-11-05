import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../format.dart';
import '../../state/app_state.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _section = 0;

  static const _navItems = [
    (icon: Icons.dashboard_outlined, label: 'نظرة عامة'),
    (icon: Icons.storefront_outlined, label: 'التجار'),
    (icon: Icons.gavel_outlined, label: 'النزاعات'),
    (icon: Icons.workspace_premium_outlined, label: 'الاشتراكات'),
    (icon: Icons.settings_outlined, label: 'الإعدادات'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13251C),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: QColors.gradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                size: 18,
                color: QColors.charcoal,
              ),
            ),
            const SizedBox(width: QSpace.sm),
            const Text(
              'QAT LINK • ADMIN',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: QSpace.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(QRadius.pill),
            ),
            child: const Center(
              child: Text(
                'Web Preview',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: QSpace.sm),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          return Row(
            children: [
              if (wide)
                Container(
                  width: 230,
                  color: const Color(0xFF13251C),
                  child: ListView(
                    padding: const EdgeInsets.all(QSpace.md),
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(QSpace.md),
                        child: Text(
                          'لوحة الإدارة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (var index = 0; index < _navItems.length; index++)
                        _NavItem(
                          icon: _navItems[index].icon,
                          label: _navItems[index].label,
                          selected: _section == index,
                          onTap: () => setState(() => _section = index),
                        ),
                      const SizedBox(height: QSpace.xl),
                      Container(
                        padding: const EdgeInsets.all(QSpace.md),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(QRadius.md),
                        ),
                        child: const Text(
                          'واجهة إدارة مستقلة عن تجربة التاجر.',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (!wide)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: QSpace.md,
                          vertical: QSpace.sm,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < _navItems.length;
                                index++
                              ) ...[
                                ChoiceChip(
                                  label: Text(_navItems[index].label),
                                  selected: _section == index,
                                  onSelected: (_) =>
                                      setState(() => _section = index),
                                ),
                                if (index != _navItems.length - 1)
                                  const SizedBox(width: QSpace.sm),
                              ],
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(QSpace.xl),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: switch (_section) {
                            1 => _MerchantsSection(state: state),
                            2 => _DisputesSection(state: state),
                            3 => _SubscriptionsSection(state: state),
                            4 => _AdminSettingsSection(),
                            _ => _OverviewSection(state: state),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(QRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(QRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: QSpace.md,
              vertical: 13,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? QColors.freshGreen : Colors.white60,
                ),
                const SizedBox(width: QSpace.sm),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        label: 'تجار نشطون',
        value: '${state.contacts.length + 1240}',
        delta: '+4.2%',
        icon: Icons.storefront_outlined,
      ),
      (
        label: 'عمليات اليوم',
        value: '${state.entries.length + 3820}',
        delta: '+8.1%',
        icon: Icons.receipt_long_outlined,
      ),
      (
        label: 'قيمة الحركة',
        value: formatCompactMoney(
          state.entries.fold<int>(0, (sum, entry) => sum + entry.amountMinor) +
              420000000,
        ),
        delta: '+6.4%',
        icon: Icons.trending_up_rounded,
      ),
      (
        label: 'نزاعات مفتوحة',
        value: '3',
        delta: '-2',
        icon: Icons.gavel_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'نظرة عامة',
          subtitle: 'مؤشرات المنصة اليوم • تحديث حي',
        ),
        const SizedBox(height: QSpace.lg),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 270,
            mainAxisSpacing: QSpace.md,
            crossAxisSpacing: QSpace.md,
            childAspectRatio: 1.9,
          ),
          itemBuilder: (context, index) {
            final stat = stats[index];
            return Container(
              padding: const EdgeInsets.all(QSpace.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(QRadius.md),
                border: Border.all(color: const Color(0xFFE4ECE7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(stat.icon, size: 18, color: QColors.brightGreen),
                      const SizedBox(width: QSpace.sm),
                      Text(
                        stat.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: QColors.neutralGray,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        stat.delta,
                        style: const TextStyle(
                          fontSize: 11,
                          color: QColors.approvedFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    stat.value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: QColors.charcoal,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: QSpace.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;
            const chart = _Panel(
              title: 'حركة المنصة • 7 أيام',
              child: QBarChart(
                values: [0.42, 0.58, 0.49, 0.72, 0.85, 0.66, 0.93],
                labels: [
                  'السبت',
                  'الأحد',
                  'الاثنين',
                  'الثلاثاء',
                  'الأربعاء',
                  'الخميس',
                  'الجمعة',
                ],
                height: 180,
              ),
            );
            final recent = _Panel(
              title: 'أحدث التجار',
              child: Column(
                children: [
                  for (final contact in state.contacts.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: QSpace.sm),
                      child: Row(
                        children: [
                          QAvatar(label: contact.displayName, size: 32),
                          const SizedBox(width: QSpace.sm),
                          Expanded(
                            child: Text(
                              contact.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: QColors.brightGreen,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 2, child: chart),
                  const SizedBox(width: QSpace.md),
                  Expanded(child: recent),
                ],
              );
            }
            return Column(
              children: [
                chart,
                const SizedBox(height: QSpace.md),
                recent,
              ],
            );
          },
        ),
        const SizedBox(height: QSpace.lg),
        const _Panel(
          title: 'طلبات تحتاج مراجعة',
          child: Column(
            children: [
              _ReviewRow(
                title: 'طلب تعديل رصيد • مؤسسة النخبة',
                subtitle: '23,000 → 21,000 ر.ي • منذ 3 أيام',
                action: 'مراجعة',
              ),
              SizedBox(height: QSpace.sm),
              _ReviewRow(
                title: 'نزاع مفتوح • سوق السعادة',
                subtitle: 'دفعة غير معتمدة • 12,500 ر.ي',
                action: 'فتح',
              ),
              SizedBox(height: QSpace.sm),
              _ReviewRow(
                title: 'اشتراك منتهٍ • 4 تجار',
                subtitle: 'بحاجة إلى تجديد أو تنبيه',
                action: 'إرسال',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MerchantsSection extends StatelessWidget {
  const _MerchantsSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'إدارة التجار',
          subtitle: 'بحث وتصفية ومراجعة حالة كل تاجر',
        ),
        const SizedBox(height: QSpace.lg),
        _Panel(
          title: 'التجار',
          child: Column(
            children: [
              for (final contact in state.contacts) ...[
                Row(
                  children: [
                    QAvatar(label: contact.displayName, size: 36),
                    const SizedBox(width: QSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${contact.phone} • ${contact.kind.name}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: QColors.neutralGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: QColors.approvedBg,
                        borderRadius: BorderRadius.circular(QRadius.pill),
                      ),
                      child: const Text(
                        'نشط',
                        style: TextStyle(
                          fontSize: 10,
                          color: QColors.approvedFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: QSpace.sm),
                    IconButton(
                      onPressed: () => QToast.show(
                        context,
                        'فتح ملف ${contact.displayName}',
                      ),
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    ),
                  ],
                ),
                const Divider(height: QSpace.lg),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DisputesSection extends StatelessWidget {
  const _DisputesSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'النزاعات',
          subtitle: 'مراجعة الحركات المتنازع عليها وسجل القرارات',
        ),
        const SizedBox(height: QSpace.lg),
        _Panel(
          title: 'نزاع مفتوح • #DSP-1042',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'طرفان: مؤسسة النخبة للقات • أبو أحمد المرادي',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: QSpace.xs),
              const Text(
                'الموضوع: دفعة 2,000 ر.ي مع إيصال لم تُعتمد بعد.',
                style: TextStyle(fontSize: 12, color: QColors.neutralGray),
              ),
              const SizedBox(height: QSpace.md),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        QToast.show(context, 'تم إرجاع النزاع للتاجر'),
                    child: const Text('إرجاع للتاجر'),
                  ),
                  const SizedBox(width: QSpace.sm),
                  FilledButton(
                    onPressed: () =>
                        QToast.show(context, 'تم إغلاق النزاع لصالح العميل'),
                    child: const Text('حسم لصالح العميل'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: QSpace.md),
        const _Panel(
          title: 'سجل القرارات',
          child: Column(
            children: [
              _ReviewRow(
                title: '#DSP-1038 • تم الحسم لصالح التاجر',
                subtitle: 'رصيد غير معتمد • 6,500 ر.ي',
                action: 'عرض',
              ),
              SizedBox(height: QSpace.sm),
              _ReviewRow(
                title: '#DSP-1029 • تم الحسم لصالح العميل',
                subtitle: 'إيصال مكرر • 3,200 ر.ي',
                action: 'عرض',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubscriptionsSection extends StatelessWidget {
  const _SubscriptionsSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'الاشتراكات',
          subtitle: 'استخدام الباقات والحدود اليومية',
        ),
        const SizedBox(height: QSpace.lg),
        _Panel(
          title: 'الباقات',
          child: Column(
            children: [
              for (final plan in state.plans) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium_outlined,
                      color: QColors.brightGreen,
                    ),
                    const SizedBox(width: QSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${plan.photosPerDay} صور يومياً • ${plan.priceLabel}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: QColors.neutralGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${12 + state.plans.indexOf(plan) * 13} تاجر',
                      style: const TextStyle(
                        fontSize: 12,
                        color: QColors.charcoal,
                      ),
                    ),
                  ],
                ),
                const Divider(height: QSpace.lg),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminSettingsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'إعدادات المنصة',
          subtitle: 'ضبط الحدود وسياسات الاحتفاظ والإشعارات',
        ),
        const SizedBox(height: QSpace.lg),
        _Panel(
          title: 'الحدود الافتراضية',
          child: Column(
            children: [
              _SettingRow(
                title: 'حد الصور اليومي للتاجر',
                value: '6 صور',
                onTap: () => QToast.show(context, 'فتح إعدادحد الصور'),
              ),
              const Divider(height: QSpace.lg),
              _SettingRow(
                title: 'مدة الاحتفاظ بالصور',
                value: '30 يوماً',
                onTap: () => QToast.show(context, 'فتح إعداد الاحتفاظ'),
              ),
              const Divider(height: QSpace.lg),
              _SettingRow(
                title: 'طلب السداد اليومي',
                value: 'مرة واحدة',
                onTap: () => QToast.show(context, 'فتح إعداد السداد'),
              ),
              const Divider(height: QSpace.lg),
              _SettingRow(
                title: 'إشعارات الإدارة الأمنية',
                value: 'إلزامية',
                onTap: () => QToast.show(context, 'لا يمكن تعطيلها'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: QColors.charcoal,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: QColors.neutralGray),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(QSpace.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(QRadius.md),
        border: Border.all(color: const Color(0xFFE4ECE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: QColors.charcoal,
            ),
          ),
          const SizedBox(height: QSpace.md),
          child,
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(QSpace.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF8),
        borderRadius: BorderRadius.circular(QRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: QColors.pendingFg),
          const SizedBox(width: QSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12)),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: QColors.neutralGray,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => QToast.show(context, '$action تجريبياً'),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: QColors.brightGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: QSpace.sm),
        IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
        ),
      ],
    );
  }
}
