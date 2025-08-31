import 'user.dart';

enum RoleType {
  owner,
  member,
}

class HouseholdMember {
  final String id;
  final String householdId;
  final String userId;
  final RoleType roleType;
  final int paymentRatio;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? user;

  HouseholdMember({
    required this.id,
    required this.householdId,
    required this.userId,
    required this.roleType,
    required this.paymentRatio,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.user,
  });

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      id: json['id'],
      householdId: json['household_id'],
      userId: json['user_id'],
      roleType: RoleType.values.firstWhere(
        (e) => e.toString().split('.').last == json['role_type'],
      ),
      paymentRatio: json['payment_ratio'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'role_type': roleType.toString().split('.').last,
      'payment_ratio': paymentRatio,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  HouseholdMember copyWith({
    String? id,
    String? householdId,
    String? userId,
    RoleType? roleType,
    int? paymentRatio,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    User? user,
  }) {
    return HouseholdMember(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      userId: userId ?? this.userId,
      roleType: roleType ?? this.roleType,
      paymentRatio: paymentRatio ?? this.paymentRatio,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      user: user ?? this.user,
    );
  }
}
