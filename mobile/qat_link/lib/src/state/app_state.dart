import 'package:flutter/material.dart';

import '../models.dart';

class AppState extends ChangeNotifier {
  AppState({bool seed = true}) {
    if (seed) _seed();
  }

  static const meId = 'me';
  static const merchantId = 'merchant-me';

  ThemeMode themeMode = ThemeMode.light;
  bool offline = false;
  bool hideAmounts = false;
  bool loading = false;
  bool loggedIn = true;
  bool subscriptionActive = true;
  bool appNotificationsEnabled = true;
  bool reminderNotificationsEnabled = true;
  bool bannerAdVisible = true;
  bool paidAdVisible = false;
  AppPersona persona = AppPersona.merchant;
  int currentPlanIndex = 1;
  int dailyPhotoCount = 3;
  int dailyPhotoLimit = 6;
  bool resetUnlocked = false;

  AppUser user = const AppUser(
    id: meId,
    name: 'أحمد الصبري',
    phone: '+967 770 123 456',
    storeName: 'مؤسسة النخبة للقات',
    category: 'قات رطب بالجملة',
    address: 'صنعاء • شارع الستين • سوق النخبة',
  );

  final List<Contact> contacts = [];
  final List<LedgerEntry> entries = [];
  final List<Employee> employees = [];
  final List<AppNotification> notifications = [];
  final List<DeviceSession> sessions = [];
  final List<DayPhoto> photos = [];
  final List<SettlementRequest> settlementRequests = [];
  final List<Plan> plans = [];

  List<Contact> get customers => contacts
      .where((contact) => contact.kind == ContactKind.customer)
      .toList();

  List<Contact> get suppliers => contacts
      .where((contact) => contact.kind == ContactKind.supplier)
      .toList();

  List<Contact> get customerMerchants => contacts
      .where((contact) => contact.kind == ContactKind.merchant)
      .toList();

  List<Contact> get favoriteCustomers =>
      customers.where((contact) => contact.favorite).toList();

  Contact? contactById(String id) {
    for (final contact in contacts) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  List<LedgerEntry> get merchantEntries =>
      entries.where((entry) => entry.merchantId == merchantId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<LedgerEntry> get customerEntries =>
      entries.where((entry) => entry.customerId == meId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<LedgerEntry> entriesForCustomer(String customerId) =>
      merchantEntries.where((entry) => entry.customerId == customerId).toList();

  List<LedgerEntry> entriesForMerchantAccount(String merchantContactId) =>
      customerEntries
          .where((entry) => entry.merchantId == merchantContactId)
          .toList();

  List<LedgerEntry> get customerPendingApprovals => customerEntries
      .where(
        (entry) =>
            entry.status == TxStatus.pending && entry.createdByMe == false,
      )
      .toList();

  int get approvedReceivable =>
      customers.fold(0, (total, contact) => total + contact.balanceMinor);

  int get pendingReceivable =>
      customers.fold(0, (total, contact) => total + contact.pendingMinor);

  int get customerApprovedTotal => customerMerchants.fold(
    0,
    (total, contact) => total + contact.balanceMinor,
  );

  int get customerPendingTotal => customerMerchants.fold(
    0,
    (total, contact) => total + contact.pendingMinor,
  );

  int get pendingMerchantCount =>
      merchantEntries.where((entry) => entry.status == TxStatus.pending).length;

  int get unreadNotifications =>
      notifications.where((notification) => !notification.read).length;

  int get todayPhotos => photos
      .where((photo) => _isSameDay(photo.createdAt, DateTime.now()))
      .length;

  bool get canCloseCustomer => entriesForCustomer(
    meId,
  ).where((entry) => entry.status == TxStatus.pending).isEmpty;

  bool canCloseCustomerFor(String customerId) {
    final customer = contactById(customerId);
    if (customer == null) return false;
    return customer.balanceMinor == 0 &&
        customer.pendingMinor == 0 &&
        entriesForCustomer(
          customerId,
        ).where((entry) => entry.status == TxStatus.pending).isEmpty;
  }

  List<SettlementRequest> settlementFor(String merchantContactId) =>
      settlementRequests
          .where((request) => request.id.startsWith('$merchantContactId:'))
          .toList();

  bool hasSettlementToday(String merchantContactId) => settlementFor(
    merchantContactId,
  ).any((request) => _isSameDay(request.createdAt, DateTime.now()));

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setDark(bool value) {
    themeMode = value ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setPersona(AppPersona value) {
    persona = value;
    notifyListeners();
  }

  void toggleOffline() {
    offline = !offline;
    notifyListeners();
  }

  void toggleHideAmounts() {
    hideAmounts = !hideAmounts;
    notifyListeners();
  }

  void toggleAppNotifications(bool value) {
    appNotificationsEnabled = value;
    notifyListeners();
  }

  void toggleReminderNotifications(bool value) {
    reminderNotificationsEnabled = value;
    notifyListeners();
  }

  void toggleBannerAd(bool value) {
    bannerAdVisible = value;
    notifyListeners();
  }

  void togglePaidAd(bool value) {
    paidAdVisible = value;
    notifyListeners();
  }

  void setSubscriptionActive(bool value) {
    subscriptionActive = value;
    notifyListeners();
  }

  void login() {
    loggedIn = true;
    notifyListeners();
  }

  void logout() {
    loggedIn = false;
    notifyListeners();
  }

  Future<void> refreshHome() async {
    loading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    loading = false;
    notifyListeners();
  }

  void addDebt({
    required String customerId,
    required int amountMinor,
    required DateTime date,
    String? productName,
    String? note,
  }) {
    final customer = contactById(customerId);
    if (customer == null) return;
    final entry = LedgerEntry(
      id: 'e-${DateTime.now().microsecondsSinceEpoch}',
      customerId: customerId,
      merchantId: merchantId,
      type: OperationType.charge,
      amountMinor: amountMinor,
      status: offline ? TxStatus.local : TxStatus.pending,
      createdAt: date,
      productName: productName,
      note: note,
      history: [
        TxEvent(
          label: offline ? 'حفظ محلياً' : 'أرسلت للموافقة',
          at: DateTime.now(),
        ),
      ],
    );
    entries.add(entry);
    _replaceContact(
      customer,
      customer.copyWith(pendingMinor: customer.pendingMinor + amountMinor),
    );
    notifyListeners();
  }

  void addSupplier({
    required String name,
    required String phone,
    String? storeName,
  }) {
    final contact = Contact(
      id: 's-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      phone: phone,
      kind: ContactKind.supplier,
      storeName: storeName ?? '',
      creditLimitMinor: 50000000,
    );
    contacts.add(contact);
    notifyListeners();
  }

  void addCustomer({
    required String name,
    required String phone,
    required bool hasApp,
    String? storeName,
  }) {
    final contact = Contact(
      id: 'c-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      phone: phone,
      kind: ContactKind.customer,
      storeName: storeName ?? '',
      hasApp: hasApp,
      favorite: false,
      creditLimitMinor: 10000000,
    );
    contacts.add(contact);
    notifyListeners();
  }

  void approveEntry(String entryId) {
    final index = entries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    final entry = entries[index];
    if (entry.status != TxStatus.pending) return;
    final customer = contactById(entry.customerId);
    entries[index] = entry.copyWith(
      status: TxStatus.approved,
      history: [
        ...entry.history,
        TxEvent(label: 'اعتمدت العملية', at: DateTime.now()),
      ],
    );
    if (customer != null) {
      final isIncrease =
          entry.type == OperationType.charge ||
          entry.type == OperationType.creditApplication;
      final nextBalance = isIncrease
          ? customer.balanceMinor + entry.amountMinor
          : customer.balanceMinor - entry.amountMinor;
      _replaceContact(
        customer,
        customer.copyWith(
          balanceMinor: nextBalance < 0 ? 0 : nextBalance,
          pendingMinor: (customer.pendingMinor - entry.amountMinor).clamp(
            0,
            1 << 62,
          ),
        ),
      );
    }
    notifyListeners();
  }

  void rejectEntry(String entryId) {
    final index = entries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    final entry = entries[index];
    final customer = contactById(entry.customerId);
    entries[index] = entry.copyWith(
      status: TxStatus.rejected,
      history: [
        ...entry.history,
        TxEvent(label: 'رفضت العملية', at: DateTime.now()),
      ],
    );
    if (customer != null) {
      _replaceContact(
        customer,
        customer.copyWith(
          pendingMinor: (customer.pendingMinor - entry.amountMinor).clamp(
            0,
            1 << 62,
          ),
        ),
      );
    }
    notifyListeners();
  }

  void requestEdit(String entryId, int proposedAmountMinor, String note) {
    final index = entries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    final entry = entries[index];
    entries[index] = entry.copyWith(
      status: TxStatus.editRequested,
      proposedAmountMinor: proposedAmountMinor,
      history: [
        ...entry.history,
        TxEvent(
          label: 'طلب تعديل بمبلغ ${formatEditorAmount(proposedAmountMinor)}',
          at: DateTime.now(),
          note: note,
        ),
      ],
    );
    notifyListeners();
  }

  void acceptEdit(String entryId) {
    final index = entries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    final entry = entries[index];
    final nextAmount = entry.proposedAmountMinor ?? entry.amountMinor;
    final customer = contactById(entry.customerId);
    entries[index] = entry.copyWith(
      status: TxStatus.approved,
      clearProposedAmount: true,
      history: [
        ...entry.history,
        TxEvent(label: 'قبل التاجر المبلغ البديل', at: DateTime.now()),
      ],
    );
    if (customer != null) {
      _replaceContact(
        customer,
        customer.copyWith(
          balanceMinor: customer.balanceMinor + nextAmount,
          pendingMinor: (customer.pendingMinor - entry.amountMinor).clamp(
            0,
            1 << 62,
          ),
        ),
      );
    }
    notifyListeners();
  }

  void declineEdit(String entryId) {
    final index = entries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    final entry = entries[index];
    final customer = contactById(entry.customerId);
    entries[index] = entry.copyWith(
      status: TxStatus.rejected,
      clearProposedAmount: true,
      history: [
        ...entry.history,
        TxEvent(label: 'رفض المبلغ البديل', at: DateTime.now()),
      ],
    );
    if (customer != null) {
      _replaceContact(
        customer,
        customer.copyWith(
          pendingMinor: (customer.pendingMinor - entry.amountMinor).clamp(
            0,
            1 << 62,
          ),
        ),
      );
    }
    notifyListeners();
  }

  void addPayment({
    required String merchantContactId,
    required int amountMinor,
    required String method,
    required bool withReceipt,
    String? note,
  }) {
    final merchant = contactById(merchantContactId);
    if (merchant == null) return;
    final entry = LedgerEntry(
      id: 'p-${DateTime.now().microsecondsSinceEpoch}',
      customerId: meId,
      merchantId: merchantContactId,
      type: OperationType.payment,
      amountMinor: amountMinor,
      status: offline ? TxStatus.local : TxStatus.pending,
      createdAt: DateTime.now(),
      note: note == null ? method : '$method • $note',
      createdByMe: true,
      photoCount: withReceipt ? 1 : 0,
      history: [
        TxEvent(
          label: withReceipt ? 'دفعة مع إيصال' : 'دفعة',
          at: DateTime.now(),
        ),
      ],
    );
    entries.add(entry);
    _replaceContact(
      merchant,
      merchant.copyWith(pendingMinor: merchant.pendingMinor + amountMinor),
    );
    notifyListeners();
  }

  void requestSettlement(String merchantContactId) {
    if (hasSettlementToday(merchantContactId)) return;
    settlementRequests.add(
      SettlementRequest(
        id: '$merchantContactId:${DateTime.now().microsecondsSinceEpoch}',
        createdAt: DateTime.now(),
        status: SettlementStatus.pending,
        note: 'طلب سداد يومي',
      ),
    );
    notifyListeners();
  }

  void approveSettlement(String requestId) {
    final index = settlementRequests.indexWhere(
      (request) => request.id == requestId,
    );
    if (index == -1) return;
    final request = settlementRequests[index];
    settlementRequests[index] = SettlementRequest(
      id: request.id,
      createdAt: request.createdAt,
      status: SettlementStatus.approved,
      note: request.note,
    );
    notifyListeners();
  }

  void addPhoto(String title, String audience) {
    if (todayPhotos >= dailyPhotoLimit) return;
    photos.add(
      DayPhoto(
        id: 'photo-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        audience: audience,
        createdAt: DateTime.now(),
        hue: (photos.length * 47) % 360,
      ),
    );
    dailyPhotoCount = todayPhotos;
    notifyListeners();
  }

  void addEmployee({
    required String name,
    required String phone,
    required String role,
    required Set<String> permissions,
  }) {
    employees.add(
      Employee(
        id: 'employee-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        phone: phone,
        role: role,
        permissions: permissions,
      ),
    );
    notifyListeners();
  }

  void toggleEmployee(String employeeId) {
    final index = employees.indexWhere((employee) => employee.id == employeeId);
    if (index == -1) return;
    final employee = employees[index];
    employees[index] = employee.copyWith(active: !employee.active);
    notifyListeners();
  }

  void markNotificationRead(String id) {
    final index = notifications.indexWhere(
      (notification) => notification.id == id,
    );
    if (index == -1) return;
    notifications[index] = notifications[index].copyWith(read: true);
    notifyListeners();
  }

  void markAllNotificationsRead() {
    for (var index = 0; index < notifications.length; index++) {
      notifications[index] = notifications[index].copyWith(read: true);
    }
    notifyListeners();
  }

  void revokeSession(String id) {
    sessions.removeWhere((session) => session.id == id);
    notifyListeners();
  }

  void revokeOtherSessions() {
    final current = sessions.where((session) => session.current).toList();
    sessions
      ..clear()
      ..addAll(current);
    notifyListeners();
  }

  void selectPlan(int index) {
    currentPlanIndex = index;
    notifyListeners();
  }

  void requestReset() {
    resetUnlocked = true;
    notifyListeners();
  }

  void _replaceContact(Contact previous, Contact next) {
    final index = contacts.indexWhere((contact) => contact.id == previous.id);
    if (index != -1) contacts[index] = next;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _seed() {
    final now = DateTime.now();
    contacts.addAll(const [
      Contact(
        id: 'c1',
        name: 'أبو أحمد المرادي',
        phone: '+967 771 845 220',
        kind: ContactKind.customer,
        balanceMinor: 12000000,
        pendingMinor: 1500000,
        favorite: true,
        creditLimitMinor: 20000000,
      ),
      Contact(
        id: 'c2',
        name: 'صالح الحميري',
        phone: '+967 733 901 442',
        kind: ContactKind.customer,
        balanceMinor: 8450000,
        favorite: true,
        creditLimitMinor: 15000000,
      ),
      Contact(
        id: 'c3',
        name: 'محمد العزي',
        phone: '+967 715 442 781',
        kind: ContactKind.customer,
        pendingMinor: 3200000,
        hasApp: false,
        creditLimitMinor: 10000000,
      ),
      Contact(
        id: 'c4',
        name: 'فؤاد الشرعبي',
        phone: '+967 777 332 109',
        kind: ContactKind.customer,
        balanceMinor: 23000000,
        creditLimitMinor: 10000000,
      ),
      Contact(
        id: 'c5',
        name: 'عبدالله الريمي',
        phone: '+967 739 557 810',
        kind: ContactKind.customer,
        balanceMinor: 5600000,
        pendingMinor: 800000,
        creditLimitMinor: 12000000,
      ),
      Contact(
        id: 's1',
        name: 'مزارع بني مطر',
        phone: '+967 770 664 001',
        kind: ContactKind.supplier,
        storeName: 'مزارع بني مطر',
        balanceMinor: 31000000,
        creditLimitMinor: 50000000,
      ),
      Contact(
        id: 's2',
        name: 'مورد القات الذهبي',
        phone: '+967 712 884 330',
        kind: ContactKind.supplier,
        storeName: 'مورد القات الذهبي',
        balanceMinor: 7650000,
        pendingMinor: 1200000,
        creditLimitMinor: 30000000,
      ),
      Contact(
        id: 'm1',
        name: 'مؤسسة النخبة للقات',
        phone: '+967 770 123 456',
        kind: ContactKind.merchant,
        storeName: 'مؤسسة النخبة للقات',
        category: 'قات رطب بالجملة',
        address: 'صنعاء • شارع الستين',
        balanceMinor: 8250000,
        pendingMinor: 1500000,
        favorite: true,
        creditLimitMinor: 20000000,
      ),
      Contact(
        id: 'm2',
        name: 'سوق السعادة',
        phone: '+967 771 200 340',
        kind: ContactKind.merchant,
        storeName: 'سوق السعادة',
        category: 'قات درجة أولى',
        address: 'صنعاء • سوق السعادة',
        pendingMinor: 1250000,
        creditLimitMinor: 10000000,
      ),
      Contact(
        id: 'm3',
        name: 'مؤسسة الوادي الأخضر',
        phone: '+967 733 760 118',
        kind: ContactKind.merchant,
        storeName: 'مؤسسة الوادي الأخضر',
        category: 'قات مبرد',
        address: 'ذمار • السوق المركزي',
        balanceMinor: 14600000,
        creditLimitMinor: 25000000,
      ),
    ]);

    entries.addAll([
      LedgerEntry(
        id: 'e1',
        customerId: 'c1',
        merchantId: merchantId,
        type: OperationType.charge,
        amountMinor: 5000000,
        status: TxStatus.approved,
        createdAt: now.subtract(const Duration(hours: 2)),
        productName: 'قات رطب درجة أولى',
        note: 'ربطة كبيرة',
        history: [
          TxEvent(
            label: 'اعتمدها العميل',
            at: now.subtract(const Duration(hours: 1, minutes: 40)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'e2',
        customerId: 'c1',
        merchantId: merchantId,
        type: OperationType.payment,
        amountMinor: 2000000,
        status: TxStatus.pending,
        createdAt: now.subtract(const Duration(hours: 5)),
        note: 'دفعة جزئية',
        history: [
          TxEvent(
            label: 'بانتظار موافقة العميل',
            at: now.subtract(const Duration(hours: 5)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'e3',
        customerId: 'c2',
        merchantId: merchantId,
        type: OperationType.charge,
        amountMinor: 8450000,
        status: TxStatus.approved,
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        productName: 'قات مبرد',
        history: [
          TxEvent(
            label: 'اعتمدها العميل',
            at: now.subtract(const Duration(days: 1, hours: 2)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'e4',
        customerId: 'c3',
        merchantId: merchantId,
        type: OperationType.charge,
        amountMinor: 3200000,
        status: TxStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 40)),
        productName: 'ربطة صغيرة',
        note: 'عميل جديد',
        history: [
          TxEvent(
            label: 'أرسلت الدعوة والفاتورة',
            at: now.subtract(const Duration(minutes: 39)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'e5',
        customerId: 'c4',
        merchantId: merchantId,
        type: OperationType.charge,
        amountMinor: 23000000,
        status: TxStatus.editRequested,
        proposedAmountMinor: 21000000,
        createdAt: now.subtract(const Duration(days: 3)),
        productName: 'كمية جملة',
        note: 'طلب العميل تعديل المبلغ',
        history: [
          TxEvent(
            label: 'طلب تعديل',
            at: now.subtract(const Duration(days: 2, hours: 20)),
            note: 'خصم فرق الوزن',
          ),
        ],
      ),
      LedgerEntry(
        id: 'e6',
        customerId: 'c5',
        merchantId: merchantId,
        type: OperationType.charge,
        amountMinor: 5600000,
        status: TxStatus.local,
        createdAt: now.subtract(const Duration(hours: 1)),
        productName: 'قات رطب',
        note: 'محفوظة محلياً بانتظار الشبكة',
        history: [
          TxEvent(
            label: 'حفظ محلياً',
            at: now.subtract(const Duration(hours: 1)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'ce1',
        customerId: meId,
        merchantId: 'm1',
        type: OperationType.charge,
        amountMinor: 8250000,
        status: TxStatus.approved,
        createdAt: now.subtract(const Duration(days: 5)),
        productName: 'قات رطب درجة أولى',
        createdByMe: false,
        history: [
          TxEvent(
            label: 'اعتمدتها',
            at: now.subtract(const Duration(days: 5, hours: -1)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'ce2',
        customerId: meId,
        merchantId: 'm1',
        type: OperationType.payment,
        amountMinor: 1500000,
        status: TxStatus.pending,
        createdAt: now.subtract(const Duration(hours: 3)),
        note: 'دفعة نقدية',
        createdByMe: true,
        photoCount: 1,
        history: [
          TxEvent(
            label: 'أرسلت الدفعة مع الإيصال',
            at: now.subtract(const Duration(hours: 3)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'ce3',
        customerId: meId,
        merchantId: 'm2',
        type: OperationType.charge,
        amountMinor: 1250000,
        status: TxStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 55)),
        productName: 'ربطة قات',
        createdByMe: false,
        history: [
          TxEvent(
            label: 'بانتظار موافقتك',
            at: now.subtract(const Duration(minutes: 55)),
          ),
        ],
      ),
      LedgerEntry(
        id: 'ce4',
        customerId: meId,
        merchantId: 'm3',
        type: OperationType.charge,
        amountMinor: 14600000,
        status: TxStatus.approved,
        createdAt: now.subtract(const Duration(days: 12)),
        productName: 'كمية أسبوعية',
        createdByMe: false,
        history: [
          TxEvent(
            label: 'اعتمدتها',
            at: now.subtract(const Duration(days: 12)),
          ),
        ],
      ),
    ]);

    employees.addAll(const [
      Employee(
        id: 'emp1',
        name: 'ياسر الحاشدي',
        phone: '+967 770 441 020',
        role: 'كاشير',
        permissions: {'تسجيل الديون', 'تسجيل الدفعات'},
      ),
      Employee(
        id: 'emp2',
        name: 'هدى العمراني',
        phone: '+967 733 009 771',
        role: 'مشرف مبيعات',
        permissions: {'تسجيل الديون', 'تسجيل الدفعات', 'عرض الكشوف'},
      ),
    ]);

    notifications.addAll([
      AppNotification(
        id: 'n1',
        title: 'عملية بانتظار موافقتك',
        body: 'سوق السعادة سجل ديناً بمبلغ 12,500 ر.ي',
        kind: NotificationKind.app,
        at: now.subtract(const Duration(minutes: 55)),
      ),
      AppNotification(
        id: 'n2',
        title: 'تذكير بالديون',
        body: 'لدى 3 عملاء مبالغ معلقة منذ أكثر من يوم',
        kind: NotificationKind.reminder,
        at: now.subtract(const Duration(hours: 4)),
      ),
      AppNotification(
        id: 'n3',
        title: 'تحديث سياسة النزاعات',
        body: 'تم تحديث إجراءات فتح النزاع. لا يمكن إيقاف إشعارات الإدارة.',
        kind: NotificationKind.admin,
        at: now.subtract(const Duration(days: 1)),
      ),
    ]);

    sessions.addAll([
      DeviceSession(
        id: 'd1',
        name: 'Pixel 8 Pro',
        platform: 'Android 15',
        lastActive: now,
        location: 'صنعاء، اليمن',
        current: true,
      ),
      DeviceSession(
        id: 'd2',
        name: 'iPhone 14',
        platform: 'iOS 18',
        lastActive: now.subtract(const Duration(days: 2, hours: 3)),
        location: 'صنعاء، اليمن',
      ),
      DeviceSession(
        id: 'd3',
        name: 'Chrome على الويب',
        platform: 'Windows 11',
        lastActive: now.subtract(const Duration(days: 6)),
        location: 'عدن، اليمن',
      ),
    ]);

    photos.addAll([
      DayPhoto(
        id: 'ph1',
        title: 'وصلات قات رطب',
        audience: 'جميع العملاء',
        createdAt: now.subtract(const Duration(hours: 2)),
        hue: 132,
      ),
      DayPhoto(
        id: 'ph2',
        title: 'تشكيلة الصباح',
        audience: 'العملاء المفضلون',
        createdAt: now.subtract(const Duration(hours: 5)),
        hue: 88,
      ),
      DayPhoto(
        id: 'ph3',
        title: 'كمية الجملة',
        audience: 'عميل محدد: أبو أحمد',
        createdAt: now.subtract(const Duration(days: 1)),
        hue: 162,
      ),
    ]);

    plans.addAll(const [
      Plan(
        id: 'basic',
        name: 'الباقة الأساسية',
        description: 'للتاجر الفردي وبداية رقمنة الدفتر',
        limits: ['عملاء غير محدودين', 'كشف حساب وتصدير', 'دعم فني أساسي'],
        photosPerDay: 3,
      ),
      Plan(
        id: 'pro',
        name: 'باقة النمو',
        description: 'للتجار أصحاب الحركة اليومية العالية',
        limits: ['كل مزايا الأساسية', 'موظفون وصلاحيات', 'تقارير متقدمة'],
        photosPerDay: 6,
        featured: true,
      ),
      Plan(
        id: 'business',
        name: 'باقة الأعمال',
        description: 'للمؤسسات ومتاجر الجملة متعددة الفروع',
        limits: ['فروع متعددة', 'حدود أعلى للصور', 'أولوية في الدعم'],
        photosPerDay: 12,
      ),
    ]);
  }
}

String formatEditorAmount(int minor) => (minor / 100).round().toString();
