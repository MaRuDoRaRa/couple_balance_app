import '../models/notification.dart';
import '../models/expense.dart';
import '../models/user.dart';
import 'supabase_service.dart';

class NotificationService {
  final SupabaseService _supabaseService = SupabaseService();

  /// 支出が追加された時に通知を作成
  Future<void> notifyExpenseAdded(Expense expense, String fromUserId) async {
    try {
      // 他のユーザーに通知を送信
      final users = await _supabaseService.getUsers();
      final otherUsers = users.where((user) => user.id != fromUserId).toList();
      
      for (final user in otherUsers) {
        final now = DateTime.now();
        final notification = Notification(
          id: '',
          userId: user.id,
          fromUserId: fromUserId,
          notificationType: NotificationType.expenseAdded,
          expenseId: expense.id,
          message: '${expense.description} (¥${expense.amount.toStringAsFixed(0)}) が追加されました',
          createdAt: now,
          updatedAt: now,
        );
        
        await _supabaseService.createNotification(notification);
      }
    } catch (e) {
      print('通知の作成に失敗: $e');
    }
  }

  /// 支出が編集された時に通知を作成
  Future<void> notifyExpenseEdited(Expense expense, String fromUserId) async {
    try {
      final users = await _supabaseService.getUsers();
      final otherUsers = users.where((user) => user.id != fromUserId).toList();
      
      for (final user in otherUsers) {
        final now = DateTime.now();
        final notification = Notification(
          id: '',
          userId: user.id,
          fromUserId: fromUserId,
          notificationType: NotificationType.expenseEdited,
          expenseId: expense.id,
          message: '${expense.description} (¥${expense.amount.toStringAsFixed(0)}) が編集されました',
          createdAt: now,
          updatedAt: now,
        );
        
        await _supabaseService.createNotification(notification);
      }
    } catch (e) {
      print('通知の作成に失敗: $e');
    }
  }

  /// 支出が削除された時に通知を作成
  Future<void> notifyExpenseDeleted(String expenseId, String description, double amount, String fromUserId) async {
    try {
      final users = await _supabaseService.getUsers();
      final otherUsers = users.where((user) => user.id != fromUserId).toList();
      
      for (final user in otherUsers) {
        final now = DateTime.now();
        final notification = Notification(
          id: '',
          userId: user.id,
          fromUserId: fromUserId,
          notificationType: NotificationType.expenseDeleted,
          expenseId: expenseId,
          message: '$description (¥${amount.toStringAsFixed(0)}) が削除されました',
          createdAt: now,
          updatedAt: now,
        );
        
        await _supabaseService.createNotification(notification);
      }
    } catch (e) {
      print('通知の作成に失敗: $e');
    }
  }

  /// ユーザーの未読通知数を取得
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final notifications = await _supabaseService.getNotifications(userId);
      return notifications.where((notification) => !notification.isRead).length;
    } catch (e) {
      print('未読通知数の取得に失敗: $e');
      return 0;
    }
  }

  /// 通知を既読にする
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _supabaseService.markNotificationAsRead(notificationId);
    } catch (e) {
      print('通知の既読化に失敗: $e');
    }
  }

  /// 全ての通知を既読にする
  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      final notifications = await _supabaseService.getNotifications(userId);
      final unreadNotifications = notifications.where((notification) => !notification.isRead).toList();
      
      for (final notification in unreadNotifications) {
        await _supabaseService.markNotificationAsRead(notification.id);
      }
    } catch (e) {
      print('全通知の既読化に失敗: $e');
    }
  }
}
