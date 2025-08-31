import 'household.dart';
import 'user.dart';

class HouseholdInvitation {
  final String id;
  final String invitationCode;
  final String householdId;
  final DateTime expiresAt;
  final bool isUsed;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  final Household? household;
  final User? creator;

  HouseholdInvitation({
    required this.id,
    required this.invitationCode,
    required this.householdId,
    required this.expiresAt,
    required this.isUsed,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.household,
    this.creator,
  });

  factory HouseholdInvitation.fromJson(Map<String, dynamic> json) {
    return HouseholdInvitation(
      id: json['id'],
      invitationCode: json['invitation_code'],
      householdId: json['household_id'],
      expiresAt: DateTime.parse(json['expires_at']),
      isUsed: json['is_used'] ?? false,
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      household: json['household'] != null ? Household.fromJson(json['household']) : null,
      creator: json['creator'] != null ? User.fromJson(json['creator']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invitation_code': invitationCode,
      'household_id': householdId,
      'expires_at': expiresAt.toIso8601String(),
      'is_used': isUsed,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValid => !isUsed && !isExpired;

  HouseholdInvitation copyWith({
    String? id,
    String? invitationCode,
    String? householdId,
    DateTime? expiresAt,
    bool? isUsed,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    Household? household,
    User? creator,
  }) {
    return HouseholdInvitation(
      id: id ?? this.id,
      invitationCode: invitationCode ?? this.invitationCode,
      householdId: householdId ?? this.householdId,
      expiresAt: expiresAt ?? this.expiresAt,
      isUsed: isUsed ?? this.isUsed,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      household: household ?? this.household,
      creator: creator ?? this.creator,
    );
  }
}
