enum NotificationType {
  expenseAdded,
  expenseEdited,
  expenseDeleted,
  memberInvitation,
  memberRemoval,
  ownershipTransfer,
  householdDeleted,
  settlementCompleted,
  settlementCancelled,
  settlementResettled,
  settlementUnlocked,
}

class Notification {
  final String id;
  final String userId;
  final String fromUserId;
  final NotificationType notificationType;
  final String? expenseId;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final DateTime updatedAt;

  Notification({
    required this.id,
    required this.userId,
    required this.fromUserId,
    required this.notificationType,
    this.expenseId,
    required this.message,
    this.isRead = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['id'],
      userId: json['user_id'],
      fromUserId: json['from_user_id'],
      notificationType: NotificationType.values.firstWhere(
        (e) => e.toString().split('.').last == json['notification_type'],
      ),
      expenseId: json['expense_id'],
      message: json['message'],
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'from_user_id': fromUserId,
      'notification_type': notificationType.toString().split('.').last,
      'expense_id': expenseId,
      'message': message,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Notification copyWith({
    String? id,
    String? userId,
    String? fromUserId,
    NotificationType? notificationType,
    String? expenseId,
    String? message,
    bool? isRead,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Notification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fromUserId: fromUserId ?? this.fromUserId,
      notificationType: notificationType ?? this.notificationType,
      expenseId: expenseId ?? this.expenseId,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
