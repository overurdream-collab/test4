import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';

class NewCustomerScreen extends StatefulWidget {
  const NewCustomerScreen({super.key});

  @override
  State<NewCustomerScreen> createState() => _NewCustomerScreenState();
}

class _NewCustomerScreenState extends State<NewCustomerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _storeController = TextEditingController();
  bool _hasApp = true;
  bool _saving = false;

  static const _suggestedContacts = [
    (name: 'عمار الصنعاني', phone: '+967 771 550 902', hasApp: true),
    (name: 'نبيل الزبيري', phone: '+967 733 881 210', hasApp: false),
    (name: 'فتحي الحداد', phone: '+967 715 990 127', hasApp: true),
    (name: 'مروان الشميري', phone: '+967 777 201 448', hasApp: false),
  ];

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _storeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عميل جديد')),
      body: QResponsiveBody(
        maxWidth: 720,
        padding: const EdgeInsets.fromLTRB(
          QSpace.lg,
          QSpace.sm,
          QSpace.lg,
          QSpace.xxl,
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(QRadius.md),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  gradient: QColors.gradient,
                  borderRadius: BorderRadius.circular(QRadius.md),
                ),
                labelColor: QColors.charcoal,
                unselectedLabelColor: QColors.neutralGray,
                tabs: const [
                  Tab(text: 'من جهات الاتصال'),
                  Tab(text: 'إدخال يدوي'),
                ],
              ),
            ),
            const SizedBox(height: QSpace.lg),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_contactsTab(), _manualTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactsTab() {
    return ListView(
      children: [
        QCard(
          gradient: const LinearGradient(
            colors: [QColors.softMint, QColors.pureWhite],
          ),
          child: Row(
            children: [
              const Icon(Icons.contacts_outlined, color: QColors.brightGreen),
              const SizedBox(width: QSpace.md),
              Expanded(
                child: Text(
                  'نعرض جهات الاتصال التجريبية. في النسخة النهائية تُقرأ جهات الاتصال بعد إذنك فقط.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: QSpace.md),
        QCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (
                var index = 0;
                index < _suggestedContacts.length;
                index++
              ) ...[
                _SuggestedContactTile(
                  name: _suggestedContacts[index].name,
                  phone: _suggestedContacts[index].phone,
                  hasApp: _suggestedContacts[index].hasApp,
                  onAdd: () => _addSuggested(_suggestedContacts[index]),
                ),
                if (index != _suggestedContacts.length - 1) const Divider(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _manualTab() {
    return ListView(
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'اسم العميل',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: QSpace.md),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'رقم الجوال',
            hintText: '+967 7xx xxx xxx',
            prefixIcon: Icon(Icons.phone_iphone_rounded),
          ),
        ),
        const SizedBox(height: QSpace.md),
        TextField(
          controller: _storeController,
          decoration: const InputDecoration(
            labelText: 'اسم المتجر أو النشاط (اختياري)',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
        ),
        const SizedBox(height: QSpace.md),
        QCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hasApp,
            onChanged: (value) => setState(() => _hasApp = value),
            title: const Text('لديه تطبيق QAT LINK'),
            subtitle: Text(
              _hasApp
                  ? 'سيتم ربط الحسابين مباشرة بعد الحفظ.'
                  : 'سنعرض واتساب أو رسالة نصية لدعوته.',
            ),
          ),
        ),
        const SizedBox(height: QSpace.lg),
        QGradientButton(
          label: _saving ? 'جارٍ الحفظ...' : 'حفظ العميل',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: _saving ? null : _saveManual,
        ),
      ],
    );
  }

  Future<void> _saveManual() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().length < 8) {
      QToast.show(context, 'أدخل الاسم ورقم الجوال', error: true);
      return;
    }
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    final state = QScope.of(context);
    state.addCustomer(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      hasApp: _hasApp,
      storeName: _storeController.text.trim(),
    );
    if (!_hasApp) {
      await _showInvite(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
    } else if (mounted) {
      Navigator.of(context).pop();
      QToast.show(context, 'تمت إضافة العميل وربط الحساب');
    }
  }

  Future<void> _addSuggested(dynamic contact) async {
    final state = QScope.of(context);
    state.addCustomer(
      name: contact.name as String,
      phone: contact.phone as String,
      hasApp: contact.hasApp as bool,
    );
    if (!(contact.hasApp as bool)) {
      await _showInvite(
        name: contact.name as String,
        phone: contact.phone as String,
      );
    } else if (mounted) {
      QToast.show(context, 'تمت إضافة ${contact.name}');
    }
  }

  Future<void> _showInvite({
    required String name,
    required String phone,
  }) async {
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
                title: 'دعوة $name',
                subtitle: 'ليس لديه التطبيق • أرسل رابط الدعوة',
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: QSpace.lg),
              QCard(
                child: Text(
                  'مرحباً $name، هذه دعوة للانضمام إلى QAT LINK لمتابعة حسابك مع مؤسسة النخبة للقات. '
                  'أنت تسجل.. وأنا أعتمد. https://qatlink.app/invite/$phone',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: QSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(this.context).pop();
                        QToast.show(
                          this.context,
                          'تم فتح واتساب برسالة الدعوة',
                        );
                      },
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('واتساب'),
                    ),
                  ),
                  const SizedBox(width: QSpace.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(this.context).pop();
                        QToast.show(this.context, 'تم تجهيز رسالة SMS للدعوة');
                      },
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('رسالة نصية'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestedContactTile extends StatelessWidget {
  const _SuggestedContactTile({
    required this.name,
    required this.phone,
    required this.hasApp,
    required this.onAdd,
  });

  final String name;
  final String phone;
  final bool hasApp;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: QAvatar(label: name),
      title: Text(name),
      subtitle: Text(phone, textDirection: TextDirection.ltr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasApp ? Icons.verified_rounded : Icons.person_add_alt_1_rounded,
            size: 18,
            color: hasApp ? QColors.brightGreen : QColors.neutralGray,
          ),
          const SizedBox(width: QSpace.sm),
          FilledButton(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 36),
              padding: const EdgeInsets.symmetric(horizontal: QSpace.md),
            ),
            child: Text(hasApp ? 'ربط' : 'دعوة'),
          ),
        ],
      ),
    );
  }
}
