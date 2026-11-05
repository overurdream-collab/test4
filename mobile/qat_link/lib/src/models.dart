enum AppPersona { merchant, customer }

enum ContactKind { customer, supplier, merchant }

enum OperationType {
  charge,
  payment,
  salesReturn,
  refund,
  reversal,
  allocation,
  creditApplication,
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
  const Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.kind,
    this.storeName = '',
    this.category = '',
    this.address = '',
    this.balanceMinor = 0,
    this.pendingMinor = 0,
    this.favorite = false,
    this.hasApp = true,
    this.creditLimitMinor = 0,
  });

  final String id;
  final String name;
  final String phone;
  final ContactKind kind;
  final String storeName;
  final String category;
  final String address;
  final int balanceMinor;
  final int pendingMinor;
  final bool favorite;
  final bool hasApp;
  final int creditLimitMinor;

  String get displayName => storeName.isNotEmpty ? storeName : name;

  Contact copyWith({
    int? balanceMinor,
    int? pendingMinor,
    bool? favorite,
    bool? hasApp,
    int? creditLimitMinor,
    String? storeName,
    String? address,
  }) {
    return Contact(
      id: id,
      name: name,
      phone: phone,
      kind: kind,
      storeName: storeName ?? this.storeName,
      category: category,
      address: address ?? this.address,
      balanceMinor: balanceMinor ?? this.balanceMinor,
      pendingMinor: pendingMinor ?? this.pendingMinor,
      favorite: favorite ?? this.favorite,
      hasApp: hasApp ?? this.hasApp,
      creditLimitMinor: creditLimitMinor ?? this.creditLimitMinor,
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
    this.note,
    this.productName,
    this.createdByMe = true,
    this.photoCount = 0,
    this.history = const [],
    this.proposedAmountMinor,
  });

  final String id;
  final String customerId;
  final String merchantId;
  final OperationType type;
  final int amountMinor;
  final TxStatus status;
  final DateTime createdAt;
  final String? note;
  final String? productName;
  final bool createdByMe;
  final int photoCount;
  final List<TxEvent> history;
  final int? proposedAmountMinor;

  LedgerEntry copyWith({
    TxStatus? status,
    List<TxEvent>? history,
    int? photoCount,
    int? proposedAmountMinor,
    bool clearProposedAmount = false,
  }) {
    return LedgerEntry(
      id: id,
      customerId: customerId,
      merchantId: merchantId,
      type: type,
      amountMinor: amountMinor,
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
    );
  }
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

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.at,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final NotificationKind kind;
  final DateTime at;
  final bool read;

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      kind: kind,
      at: at,
      read: read ?? this.read,
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
  });

  final String id;
  final DateTime createdAt;
  final SettlementStatus status;
  final String? note;
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
