const defaultCurrency = 'YER';
const supportedCurrencies = ['YER', 'SAR', 'USD'];

enum AppPersona { merchant, customer }

enum AccountType { customer, merchant, supplier }

extension AccountTypeLabel on AccountType {
  String get label => switch (this) {
    AccountType.customer => 'زبون',
    AccountType.merchant => 'تاجر',
    AccountType.supplier => 'مورد',
  };

  String get description => switch (this) {
    AccountType.customer => 'متابعة ما عليّ لدى التجار',
    AccountType.merchant => 'إدارة العملاء والديون',
    AccountType.supplier => 'إدارة المشتريات والموردين',
  };

  bool get isMerchantSide => this != AccountType.customer;
}

enum ContactKind { customer, supplier, merchant }

enum OperationType {
  charge,
  payment,
  salesReturn,
  refund,
  reversal,
  allocation,
  creditApplication,
  supply,
}

enum OperationEffect { increase, decrease, neutral }

extension OperationEffectLabel on OperationEffect {
  String get label => switch (this) {
    OperationEffect.increase => 'زيادة الدين',
    OperationEffect.decrease => 'تخفيض الدين',
    OperationEffect.neutral => 'بلا أثر صافي',
  };

  String get sign => switch (this) {
    OperationEffect.increase => '+',
    OperationEffect.decrease => '−',
    OperationEffect.neutral => '•',
  };

  int apply(int amountMinor) => switch (this) {
    OperationEffect.increase => amountMinor,
    OperationEffect.decrease => -amountMinor,
    OperationEffect.neutral => 0,
  };

  OperationEffect get inverse => switch (this) {
    OperationEffect.increase => OperationEffect.decrease,
    OperationEffect.decrease => OperationEffect.increase,
    OperationEffect.neutral => OperationEffect.neutral,
  };
}

extension OperationTypeEffect on OperationType {
  OperationEffect get baseEffect => switch (this) {
    OperationType.charge => OperationEffect.increase,
    OperationType.payment => OperationEffect.neutral,
    OperationType.salesReturn => OperationEffect.decrease,
    OperationType.refund => OperationEffect.increase,
    OperationType.reversal => OperationEffect.neutral,
    OperationType.allocation => OperationEffect.decrease,
    OperationType.creditApplication => OperationEffect.neutral,
    OperationType.supply => OperationEffect.neutral,
  };
}

enum TxStatus { pending, approved, rejected, editRequested, local, syncing }

enum NotificationKind { app, reminder, admin }

enum SettlementStatus { pending, approved, rejected }

extension OperationTypeLabel on OperationType {
  String get label => switch (this) {
    OperationType.charge => 'دين جديد',
    OperationType.payment => 'دفعة',
    OperationType.salesReturn => 'مرتجع',
    OperationType.refund => 'رد نقدي',
    OperationType.reversal => 'عكس عملية',
    OperationType.allocation => 'تخصيص دفعة',
    OperationType.creditApplication => 'تطبيق رصيد',
    OperationType.supply => 'توريد',
  };
}

extension TxStatusLabel on TxStatus {
  String get label => switch (this) {
    TxStatus.pending => 'معلقة',
    TxStatus.approved => 'معتمدة',
    TxStatus.rejected => 'مرفوضة',
    TxStatus.editRequested => 'طلب تعديل',
    TxStatus.local => 'محفوظة محلياً',
    TxStatus.syncing => 'بانتظار المزامنة',
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.storeName,
    required this.category,
    required this.address,
  });

  final String id;
  final String name;
  final String phone;
  final String storeName;
  final String category;
  final String address;
}

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.kind,
    this.storeName = '',
    this.category = '',
    this.address = '',
    int balanceMinor = 0,
    int pendingMinor = 0,
    Map<String, int>? balancesMinor,
    Map<String, int>? pendingByCurrencyMinor,
    this.favorite = false,
    this.hasApp = true,
    int creditLimitMinor = 0,
    Map<String, int>? creditLimitsMinor,
  }) : balancesMinor = Map.unmodifiable(
         balancesMinor ??
             (balanceMinor == 0
                 ? const <String, int>{}
                 : {defaultCurrency: balanceMinor}),
       ),
       pendingByCurrencyMinor = Map.unmodifiable(
         pendingByCurrencyMinor ??
             (pendingMinor == 0
                 ? const <String, int>{}
                 : {defaultCurrency: pendingMinor}),
       ),
       creditLimitsMinor = Map.unmodifiable(
         creditLimitsMinor ??
             (creditLimitMinor == 0
                 ? const <String, int>{}
                 : {defaultCurrency: creditLimitMinor}),
       );

  final String id;
  final String name;
  final String phone;
  final ContactKind kind;
  final String storeName;
  final String category;
  final String address;
  final Map<String, int> balancesMinor;
  final Map<String, int> pendingByCurrencyMinor;
  final Map<String, int> creditLimitsMinor;
  final bool favorite;
  final bool hasApp;

  String get displayName => storeName.isNotEmpty ? storeName : name;

  int creditLimitFor(String currency) => creditLimitsMinor[currency] ?? 0;

  int get creditLimitMinor => creditLimitFor(defaultCurrency);

  int availableFor(String currency) {
    final limit = creditLimitFor(currency);
    if (limit <= 0) return 0;
    return (limit - balanceFor(currency) - pendingFor(currency)).clamp(0, limit);
  }

  int balanceFor(String currency) => balancesMinor[currency] ?? 0;

  int pendingFor(String currency) => pendingByCurrencyMinor[currency] ?? 0;

  int get balanceMinor => balanceFor(defaultCurrency);

  int get pendingMinor => pendingFor(defaultCurrency);

  bool get hasAnyBalance =>
      balancesMinor.values.any((value) => value != 0) ||
      pendingByCurrencyMinor.values.any((value) => value != 0);

  String get primaryCurrency {
    for (final entry in balancesMinor.entries) {
      if (entry.value != 0) return entry.key;
    }
    for (final entry in pendingByCurrencyMinor.entries) {
      if (entry.value != 0) return entry.key;
    }
    return defaultCurrency;
  }

  Contact copyWith({
    int? balanceMinor,
    int? pendingMinor,
    Map<String, int>? balancesMinor,
    Map<String, int>? pendingByCurrencyMinor,
    bool? favorite,
    bool? hasApp,
    int? creditLimitMinor,
    Map<String, int>? creditLimitsMinor,
    String? storeName,
    String? address,
  }) {
    var nextBalances = balancesMinor ?? this.balancesMinor;
    if (balanceMinor != null) {
      nextBalances = {...nextBalances, defaultCurrency: balanceMinor};
    }
    var nextPending = pendingByCurrencyMinor ?? this.pendingByCurrencyMinor;
    if (pendingMinor != null) {
      nextPending = {...nextPending, defaultCurrency: pendingMinor};
    }
    var nextLimits = creditLimitsMinor ?? this.creditLimitsMinor;
    if (creditLimitMinor != null) {
      nextLimits = {...nextLimits, defaultCurrency: creditLimitMinor};
    }
    return Contact(
      id: id,
      name: name,
      phone: phone,
      kind: kind,
      storeName: storeName ?? this.storeName,
      category: category,
      address: address ?? this.address,
      balancesMinor: nextBalances,
      pendingByCurrencyMinor: nextPending,
      favorite: favorite ?? this.favorite,
      hasApp: hasApp ?? this.hasApp,
      creditLimitsMinor: nextLimits,
    );
  }
}

class TxEvent {
  const TxEvent({required this.label, required this.at, this.note});

  final String label;
  final DateTime at;
  final String? note;
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.customerId,
    required this.merchantId,
    required this.type,
    required this.amountMinor,
    required this.status,
    required this.createdAt,
    this.currency = defaultCurrency,
    this.note,
    this.productName,
    this.createdByMe = true,
    this.photoCount = 0,
    this.history = const [],
    this.proposedAmountMinor,
    this.serverVersion = 0,
    this.originalOperationId,
  });

  final String id;
  final String customerId;
  final String merchantId;
  final OperationType type;
  final int amountMinor;
  final String currency;
  final TxStatus status;
  final DateTime createdAt;
  final String? note;
  final String? productName;
  final bool createdByMe;
  final int photoCount;
  final List<TxEvent> history;
  final int? proposedAmountMinor;
  final int serverVersion;
  final String? originalOperationId;

  OperationEffect get baseEffect => type.baseEffect;

  LedgerEntry copyWith({
    TxStatus? status,
    String? currency,
    List<TxEvent>? history,
    int? photoCount,
    int? proposedAmountMinor,
    bool clearProposedAmount = false,
    int? serverVersion,
    String? originalOperationId,
  }) {
    return LedgerEntry(
      id: id,
      customerId: customerId,
      merchantId: merchantId,
      type: type,
      amountMinor: amountMinor,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      createdAt: createdAt,
      note: note,
      productName: productName,
      createdByMe: createdByMe,
      photoCount: photoCount ?? this.photoCount,
      history: history ?? this.history,
      proposedAmountMinor: clearProposedAmount
          ? null
          : (proposedAmountMinor ?? this.proposedAmountMinor),
      serverVersion: serverVersion ?? this.serverVersion,
      originalOperationId:
          originalOperationId ?? this.originalOperationId,
    );
  }
}

class PendingBreakdown {
  const PendingBreakdown({
    required this.currency,
    required this.type,
    required this.effect,
    required this.amountMinor,
  });

  final String currency;
  final OperationType type;
  final OperationEffect effect;
  final int amountMinor;

  int get signedAmountMinor => effect.apply(amountMinor);
}

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.permissions,
    this.active = true,
  });

  final String id;
  final String name;
  final String phone;
  final String role;
  final Set<String> permissions;
  final bool active;

  Employee copyWith({bool? active}) {
    return Employee(
      id: id,
      name: name,
      phone: phone,
      role: role,
      permissions: permissions,
      active: active ?? this.active,
    );
  }
}

class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.description,
    required this.limits,
    required this.photosPerDay,
    this.priceLabel = 'يُحدد لاحقاً',
    this.featured = false,
  });

  final String id;
  final String name;
  final String description;
  final List<String> limits;
  final int photosPerDay;
  final String priceLabel;
  final bool featured;
}

class AdminAd {
  const AdminAd({
    required this.id,
    required this.imageUrl,
    this.title,
    this.sortOrder = 0,
  });

  final String id;
  final String imageUrl;
  final String? title;
  final int sortOrder;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.at,
    this.read = false,
    this.invitationId,
    this.relationshipId,
  });

  final String id;
  final String title;
  final String body;
  final NotificationKind kind;
  final DateTime at;
  final bool read;
  final String? invitationId;
  final String? relationshipId;

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      kind: kind,
      at: at,
      read: read ?? this.read,
      invitationId: invitationId,
      relationshipId: relationshipId,
    );
  }
}

class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastActive,
    required this.location,
    this.current = false,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime lastActive;
  final String location;
  final bool current;
}

class DayPhoto {
  const DayPhoto({
    required this.id,
    required this.title,
    required this.audience,
    required this.createdAt,
    required this.hue,
  });

  final String id;
  final String title;
  final String audience;
  final DateTime createdAt;
  final double hue;
}

class SettlementRequest {
  const SettlementRequest({
    required this.id,
    required this.createdAt,
    required this.status,
    this.note,
    this.serverId,
  });

  final String id;
  final DateTime createdAt;
  final SettlementStatus status;
  final String? note;
  final String? serverId;
}

class BrandConcept {
  const BrandConcept({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;
}
