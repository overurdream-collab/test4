class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.phoneE164,
    required this.deviceId,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    this.displayName,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String phoneE164;
  final String deviceId;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final String? displayName;

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    String? displayName,
    DateTime? accessExpiresAt,
    DateTime? refreshExpiresAt,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      userId: userId,
      phoneE164: phoneE164,
      deviceId: deviceId,
      accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
      refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'userId': userId,
    'phoneE164': phoneE164,
    'deviceId': deviceId,
    'accessExpiresAt': accessExpiresAt.toUtc().toIso8601String(),
    'refreshExpiresAt': refreshExpiresAt.toUtc().toIso8601String(),
    'displayName': displayName,
  };

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken']! as String,
      userId: json['userId']! as String,
      phoneE164: json['phoneE164']! as String,
      deviceId: json['deviceId']! as String,
      accessExpiresAt: DateTime.parse(json['accessExpiresAt']! as String),
      refreshExpiresAt: DateTime.parse(json['refreshExpiresAt']! as String),
      displayName: json['displayName'] as String?,
    );
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.code);

  final int statusCode;
  final String code;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isValidation => statusCode == 422 || statusCode == 400;

  @override
  String toString() => '$statusCode:$code';
}

class RemoteUser {
  const RemoteUser({
    required this.id,
    required this.phoneE164,
    required this.deviceId,
    this.displayName,
    this.locale = 'ar',
  });

  final String id;
  final String phoneE164;
  final String deviceId;
  final String? displayName;
  final String locale;
}

class RemoteParty {
  const RemoteParty({
    required this.userId,
    required this.role,
    this.displayName,
    this.phoneE164,
  });

  final String userId;
  final String role;
  final String? displayName;
  final String? phoneE164;
}

class RemoteRelationship {
  const RemoteRelationship({
    required this.relationshipId,
    required this.status,
    required this.currentCycleId,
    required this.myRole,
    this.relationshipType,
    this.otherParty,
  });

  final String relationshipId;
  final String? relationshipType;
  final String status;
  final String currentCycleId;
  final String myRole;
  final RemoteParty? otherParty;
}

class RemoteBalance {
  const RemoteBalance({
    required this.ownerUserId,
    required this.currency,
    required this.receivableMinor,
    required this.payableMinor,
    required this.partyBalanceMinor,
    required this.unappliedPaymentAssetMinor,
    required this.unappliedPaymentLiabilityMinor,
  });

  final String ownerUserId;
  final String currency;
  final int receivableMinor;
  final int payableMinor;
  final int partyBalanceMinor;
  final int unappliedPaymentAssetMinor;
  final int unappliedPaymentLiabilityMinor;
}

class RemoteCycle {
  const RemoteCycle({
    required this.cycleId,
    required this.cycleNumber,
    required this.title,
    required this.status,
    required this.balances,
    this.startedAt,
    this.endedAt,
  });

  final String cycleId;
  final int cycleNumber;
  final String title;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<RemoteBalance> balances;
}

class RemoteAccountCycles {
  const RemoteAccountCycles({
    required this.currentCycleId,
    required this.cycles,
  });

  final String currentCycleId;
  final List<RemoteCycle> cycles;

  RemoteCycle? get currentCycle {
    for (final cycle in cycles) {
      if (cycle.cycleId == currentCycleId) return cycle;
    }
    return cycles.isEmpty ? null : cycles.first;
  }
}

class RemoteDecision {
  const RemoteDecision({
    required this.decision,
    this.reason,
    this.actorUserId,
    this.decidedAt,
  });

  final String decision;
  final String? reason;
  final String? actorUserId;
  final DateTime? decidedAt;
}

class RemoteOperation {
  const RemoteOperation({
    required this.operationId,
    required this.actorUserId,
    required this.operationType,
    required this.businessState,
    required this.baseVersion,
    required this.serverVersion,
    required this.serverSequence,
    required this.payload,
    this.clientCreatedAt,
    this.serverCreatedAt,
    this.decision,
  });

  final String operationId;
  final String actorUserId;
  final String operationType;
  final String businessState;
  final int baseVersion;
  final int serverVersion;
  final int serverSequence;
  final Map<String, Object?> payload;
  final DateTime? clientCreatedAt;
  final DateTime? serverCreatedAt;
  final RemoteDecision? decision;
}

class RemoteOperationResult {
  const RemoteOperationResult({
    required this.outcome,
    required this.operationId,
    required this.businessState,
    required this.serverVersion,
    required this.serverSequence,
  });

  final String outcome;
  final String operationId;
  final String businessState;
  final int serverVersion;
  final int serverSequence;
}

class RemoteSettlementRequest {
  const RemoteSettlementRequest({
    required this.requestId,
    required this.requestedByUserId,
    required this.requestedAt,
  });

  final String requestId;
  final String requestedByUserId;
  final DateTime? requestedAt;
}

class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.label,
    required this.platform,
    required this.status,
    required this.isCurrent,
    this.registeredAt,
    this.lastSeenAt,
  });

  final String id;
  final String label;
  final String platform;
  final String status;
  final bool isCurrent;
  final DateTime? registeredAt;
  final DateTime? lastSeenAt;
}

class RemoteInvitation {
  const RemoteInvitation({
    required this.invitationId,
    required this.relationshipId,
    required this.relationshipType,
    required this.inviterUserId,
    required this.inviteePhoneE164,
    required this.inviterRole,
    required this.inviteeRole,
    required this.status,
    this.inviterDisplayName,
    this.expiresAt,
  });

  final String invitationId;
  final String relationshipId;
  final String relationshipType;
  final String inviterUserId;
  final String inviteePhoneE164;
  final String inviterRole;
  final String inviteeRole;
  final String status;
  final String? inviterDisplayName;
  final DateTime? expiresAt;
}

class CreatedInvitation {
  const CreatedInvitation({
    required this.invitationId,
    required this.relationshipId,
    required this.status,
    this.expiresAt,
  });

  final String invitationId;
  final String relationshipId;
  final String status;
  final DateTime? expiresAt;
}
