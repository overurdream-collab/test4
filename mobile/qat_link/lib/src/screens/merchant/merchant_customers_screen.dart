import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import 'customer_detail_screen.dart';
import 'new_customer_screen.dart';

class MerchantCustomersScreen extends StatefulWidget {
  const MerchantCustomersScreen({super.key});

  @override
  State<MerchantCustomersScreen> createState() =>
      _MerchantCustomersScreenState();
}

class _MerchantCustomersScreenState extends State<MerchantCustomersScreen> {
  final _searchController = TextEditingController();
  int _filter = 0;
  int _sort = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = QScope.of(context);
    final query = _searchController.text.trim();
    var customers = state.customers.where((customer) {
      final matchesQuery =
          query.isEmpty ||
          customer.displayName.contains(query) ||
          customer.phone.contains(query);
      final matchesFilter = switch (_filter) {
        1 => customer.favorite,
        2 => customer.pendingMinor > 0,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    customers = [...customers];
    switch (_sort) {
      case 1:
        customers.sort((a, b) => b.balanceMinor.compareTo(a.balanceMinor));
      case 2:
        customers.sort((a, b) => b.pendingMinor.compareTo(a.pendingMinor));
      default:
        customers.sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
        actions: [
          IconButton(
            tooltip: 'فرز',
            onPressed: _showSort,
            icon: const Icon(Icons.sort_rounded),
          ),
          IconButton(
            tooltip: 'إضافة عميل',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NewCustomerScreen(),
              ),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded),
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
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الجوال',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: QSpace.md),
                  QFilterPills(
                    items: const ['الكل', 'المفضلة', 'لديهم عمليات معلقة'],
                    selected: _filter,
                    onSelected: (value) => setState(() => _filter = value),
                  ),
                  const SizedBox(height: QSpace.md),
                  Row(
                    children: [
                      Text(
                        '${customers.length} عميل',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      if (state.offline)
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: QColors.pendingFg,
                        ),
                    ],
                  ),
                  const SizedBox(height: QSpace.sm),
                  if (customers.isEmpty)
                    const QStateView(state: QDataState.empty)
                  else
                    QCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < customers.length;
                            index++
                          ) ...[
                            QContactTile(
                              contact: customers[index],
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CustomerDetailScreen(
                                    customer: customers[index],
                                  ),
                                ),
                              ),
                            ),
                            if (index != customers.length - 1) const Divider(),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: QSpace.lg),
                  _InviteCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NewCustomerScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSort() async {
    final value = await showModalBottomSheet<int>(
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
            children: [
              const QSheetHeader(title: 'ترتيب العملاء'),
              const SizedBox(height: QSpace.md),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha_rounded),
                title: const Text('الاسم'),
                onTap: () => Navigator.of(context).pop(0),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('أعلى رصيد معتمد'),
                onTap: () => Navigator.of(context).pop(1),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('أعلى مبلغ معلق'),
                onTap: () => Navigator.of(context).pop(2),
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null) setState(() => _sort = value);
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return QCard(
      onTap: onTap,
      gradient: const LinearGradient(
        colors: [QColors.softMint, QColors.pureWhite],
      ),
      child: Row(
        children: [
          const QAvatar(label: 'دعوة', icon: Icons.person_add_alt_1_rounded),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أضف عميلاً وادعُه للتطبيق',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'شارك رابط الدعوة عبر واتساب أو الرسائل النصية.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded, color: QColors.neutralGray),
        ],
      ),
    );
  }
}
