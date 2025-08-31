import 'household_member.dart';

class RolePermission {
  final String id;
  final RoleType roleType;
  final String permissionName;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  RolePermission({
    required this.id,
    required this.roleType,
    required this.permissionName,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RolePermission.fromJson(Map<String, dynamic> json) {
    return RolePermission(
      id: json['id'],
      roleType: RoleType.values.firstWhere(
        (e) => e.toString().split('.').last == json['role_type'],
      ),
      permissionName: json['permission_name'],
      description: json['description'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role_type': roleType.toString().split('.').last,
      'permission_name': permissionName,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  RolePermission copyWith({
    String? id,
    RoleType? roleType,
    String? permissionName,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RolePermission(
      id: id ?? this.id,
      roleType: roleType ?? this.roleType,
      permissionName: permissionName ?? this.permissionName,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// 権限名の定数
class PermissionNames {
  // 世帯管理
  static const String householdDelete = 'household.delete';
  
  // 精算管理
  static const String settlementConfirm = 'settlement.confirm';
  static const String settlementCancel = 'settlement.cancel';
  static const String settlementUnlock = 'settlement.unlock';
  static const String settlementResettle = 'settlement.resettle';
  static const String settlementPreview = 'settlement.preview';
  
  // 招待管理
  static const String invitationCreate = 'invitation.create';
  
  // 支払い比率管理
  static const String paymentRatioUpdate = 'payment_ratio.update';
  static const String paymentRatioView = 'payment_ratio.view';
  
  // メンバー管理
  static const String memberRemove = 'member.remove';
  static const String ownershipTransfer = 'ownership.transfer';
  
  // カテゴリ管理
  static const String categoryManage = 'category.manage';
  static const String categoryView = 'category.view';
  
  // 支出管理
  static const String expenseManage = 'expense.manage';
  static const String expenseCreate = 'expense.create';
  static const String expenseUpdate = 'expense.update';
  static const String expenseDelete = 'expense.delete';
  
  // 通知管理
  static const String notificationRead = 'notification.read';
}
