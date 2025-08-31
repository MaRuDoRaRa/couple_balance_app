import '../models/monthly_settlement.dart';
import '../models/household_member.dart';
import '../models/expense.dart';
import 'supabase_service.dart';
import 'household_service.dart';

class SettlementService {
  final SupabaseService _supabaseService = SupabaseService();
  final HouseholdService _householdService = HouseholdService();

  /// 月次精算のプレビューを作成
  Future<Map<String, dynamic>> createSettlementPreview(
    String householdId,
    DateTime settlementMonth,
  ) async {
    try {
      // その月の支出を取得
      final expenses = await _getMonthlyExpenses(householdId, settlementMonth);
      
      // 現在のアクティブなメンバーを取得
      final members = await _householdService.getActiveHouseholdMembers(householdId);
      
      // 総支出額を計算
      final totalAmount = expenses.fold(0, (sum, expense) => sum + expense.amount.toInt());
      
      // 各メンバーの実際の支出額を計算
      final memberActualAmounts = <String, int>{};
      for (final member in members) {
        final memberExpenses = expenses.where((e) => e.userId == member.userId);
        final actualAmount = memberExpenses.fold(0, (sum, e) => sum + e.amount.toInt());
        memberActualAmounts[member.userId] = actualAmount;
      }
      
      // 各メンバーの精算額を計算
      final settlementDetails = <Map<String, dynamic>>[];
      for (final member in members) {
        final actualAmount = memberActualAmounts[member.userId] ?? 0;
        final calculatedAmount = (totalAmount * member.paymentRatio / 100).round();
        final settlementAmount = calculatedAmount - actualAmount;
        
        settlementDetails.add({
          'userId': member.userId,
          'userName': member.userId, // TODO: ユーザー名を取得
          'paymentRatio': member.paymentRatio,
          'actualAmount': actualAmount,
          'calculatedAmount': calculatedAmount,
          'settlementAmount': settlementAmount,
          'expenseCount': expenses.where((e) => e.userId == member.userId).length,
        });
      }
      
      // 未設定カテゴリの支出数を取得
      final uncategorizedCount = expenses.where((e) => e.subCategoryId == null).length;
      
      // カテゴリ別集計
      final categorySummary = <Map<String, dynamic>>[];
      final categoryGroups = <String, List<Expense>>{};
      
      for (final expense in expenses) {
        if (expense.subCategoryId != null) {
          final categoryId = expense.subCategoryId!;
          categoryGroups.putIfAbsent(categoryId, () => []).add(expense);
        }
      }
      
      for (final entry in categoryGroups.entries) {
        final categoryId = entry.key;
        final categoryExpenses = entry.value;
        final categoryTotal = categoryExpenses.fold(0, (sum, e) => sum + e.amount.toInt());
        
        categorySummary.add({
          'categoryId': categoryId,
          'categoryName': 'カテゴリ名', // TODO: カテゴリ名を取得
          'totalAmount': categoryTotal,
          'expenseCount': categoryExpenses.length,
        });
      }
      
      return {
        'settlementMonth': settlementMonth,
        'totalAmount': totalAmount,
        'memberCount': members.length,
        'settlementDetails': settlementDetails,
        'uncategorizedCount': uncategorizedCount,
        'categorySummary': categorySummary,
        'expenseCount': expenses.length,
        'canSettle': totalAmount > 0 && members.isNotEmpty,
      };
      
    } catch (e) {
      throw Exception('精算プレビューの作成に失敗しました: $e');
    }
  }

  /// 月次精算を確定（オーナーのみ実行可能）
  Future<void> settleMonthlyExpenses(
    String householdId,
    DateTime settlementMonth,
    String settledByUserId, // 精算確定者
  ) async {
    try {
      // オーナー権限チェック
      final members = await _householdService.getActiveHouseholdMembers(householdId);
      final owner = members.where((m) => m.roleType == RoleType.owner).firstOrNull;
      
      if (owner == null) {
        throw Exception('世帯のオーナーが見つかりません');
      }
      
      if (owner.userId != settledByUserId) {
        throw Exception('精算の確定はオーナーのみ実行できます');
      }
      
      // 既存の精算があるかチェック
      final existingSettlement = await _getSettlementByMonth(householdId, settlementMonth);
      if (existingSettlement != null) {
        throw Exception('この月の精算は既に確定されています');
      }
      
      // プレビューを作成
      final preview = await createSettlementPreview(householdId, settlementMonth);
      
      // 精算可能かチェック
      if (!(preview['canSettle'] as bool)) {
        throw Exception('精算可能なデータがありません');
      }
      
      // 現在のメンバーを取得
      final members = await _householdService.getActiveHouseholdMembers(householdId);
      
      // 月次精算レコードを作成
      final settlement = MonthlySettlement(
        id: '',
        householdId: householdId,
        settlementMonth: settlementMonth,
        totalAmount: preview['totalAmount'] as int,
        status: SettlementStatus.settled,
        settledAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      final createdSettlement = await _supabaseService.createMonthlySettlement(settlement);
      
      // 各メンバーの精算詳細を作成
      final details = preview['settlementDetails'] as List<Map<String, dynamic>>;
      for (final detail in details) {
        final settlementMember = MonthlySettlementMember(
          id: '',
          monthlySettlementId: createdSettlement.id,
          userId: detail['userId'] as String,
          paymentRatio: detail['paymentRatio'] as int,
          actualAmount: detail['actualAmount'] as int,
          calculatedAmount: detail['calculatedAmount'] as int,
          settlementAmount: detail['settlementAmount'] as int,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        
        await _supabaseService.createMonthlySettlementMember(settlementMember);
      }
      
      // 精算完了通知を全メンバーに送信
      for (final member in members) {
        if (member.userId != settledByUserId) { // 確定者以外
          final notification = Notification(
            id: '',
            householdId: householdId,
            userId: member.userId,
            type: NotificationType.settlementCompleted,
            title: '月次精算完了',
            message: '${settlementMonth.year}年${settlementMonth.month}月の精算が確定されました',
            isRead: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _supabaseService.createNotification(notification);
        }
      }
      
    } catch (e) {
      throw Exception('月次精算の確定に失敗しました: $e');
    }
  }

  /// 月次精算をキャンセル（オーナーのみ実行可能）
  Future<void> cancelMonthlySettlement(
    String householdId,
    DateTime settlementMonth,
    String cancelledByUserId, // キャンセル実行者
  ) async {
    try {
      // オーナー権限チェック
      final members = await _householdService.getActiveHouseholdMembers(householdId);
      final owner = members.where((m) => m.roleType == RoleType.owner).firstOrNull;
      
      if (owner == null) {
        throw Exception('世帯のオーナーが見つかりません');
      }
      
      if (owner.userId != cancelledByUserId) {
        throw Exception('精算のキャンセルはオーナーのみ実行できます');
      }
      
      final settlement = await _getSettlementByMonth(householdId, settlementMonth);
      if (settlement == null) {
        throw Exception('この月の精算が見つかりません');
      }
      
      if (settlement.status != SettlementStatus.settled) {
        throw Exception('確定されていない精算はキャンセルできません');
      }
      
      // ステータスをcancelledに更新
      final updatedSettlement = settlement.copyWith(
        status: SettlementStatus.cancelled,
        updatedAt: DateTime.now(),
      );
      
      await _supabaseService.updateMonthlySettlement(updatedSettlement);
      
      // キャンセル通知を全メンバーに送信
      for (final member in members) {
        if (member.userId != cancelledByUserId) { // キャンセル実行者以外
          final notification = Notification(
            id: '',
            householdId: householdId,
            userId: member.userId,
            type: NotificationType.settlementCancelled,
            title: '月次精算キャンセル',
            message: '${settlementMonth.year}年${settlementMonth.month}月の精算がキャンセルされました',
            isRead: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _supabaseService.createNotification(notification);
        }
      }
      
    } catch (e) {
      throw Exception('月次精算のキャンセルに失敗しました: $e');
    }
  }

  /// 月次精算履歴を取得
  Future<List<MonthlySettlement>> getSettlementHistory(
    String householdId, {
    int? limit,
    int? offset,
  }) async {
    try {
      return await _supabaseService.getMonthlySettlements(
        householdId,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      throw Exception('精算履歴の取得に失敗しました: $e');
    }
  }

  /// 特定の月の精算詳細を取得
  Future<Map<String, dynamic>?> getSettlementDetails(
    String householdId,
    DateTime settlementMonth,
  ) async {
    try {
      final settlement = await _getSettlementByMonth(householdId, settlementMonth);
      if (settlement == null) return null;
      
      final members = await _supabaseService.getMonthlySettlementMembers(settlement.id);
      
      return {
        'settlement': settlement,
        'members': members,
      };
    } catch (e) {
      throw Exception('精算詳細の取得に失敗しました: $e');
    }
  }

  /// 精算可能な月を取得
  Future<List<DateTime>> getSettlableMonths(String householdId) async {
    try {
      // 過去12ヶ月分の精算状況をチェック
      final now = DateTime.now();
      final settlableMonths = <DateTime>[];
      
      for (int i = 0; i < 12; i++) {
        final targetMonth = DateTime(now.year, now.month - i, 1);
        
        // 既に精算済みかチェック
        final existingSettlement = await _getSettlementByMonth(householdId, targetMonth);
        if (existingSettlement == null) {
          // その月に支出があるかチェック
          final expenses = await _getMonthlyExpenses(householdId, targetMonth);
          if (expenses.isNotEmpty) {
            settlableMonths.add(targetMonth);
          }
        }
      }
      
      return settlableMonths;
    } catch (e) {
      throw Exception('精算可能月の取得に失敗しました: $e');
    }
  }

  /// その月の支出を取得
  Future<List<Expense>> _getMonthlyExpenses(
    String householdId,
    DateTime settlementMonth,
  ) async {
    final startDate = settlementMonth;
    final endDate = DateTime(settlementMonth.year, settlementMonth.month + 1, 0);
    
    return await _supabaseService.getExpenses(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 特定の月の精算を取得
  Future<MonthlySettlement?> _getSettlementByMonth(
    String householdId,
    DateTime settlementMonth,
  ) async {
    final settlements = await _supabaseService.getMonthlySettlements(householdId);
    return settlements.where((s) => 
      s.settlementMonth.year == settlementMonth.year &&
      s.settlementMonth.month == settlementMonth.month
    ).firstOrNull;
  }

  /// 精算を再確定（オーナーのみ実行可能）
  Future<void> resettleMonthlyExpenses(
    String householdId,
    DateTime settlementMonth,
    String resettledByUserId, // 再確定者
  ) async {
    try {
      // オーナー権限チェック
      final members = await _householdService.getActiveHouseholdMembers(householdId);
      final owner = members.where((m) => m.roleType == RoleType.owner).firstOrNull;
      
      if (owner == null) {
        throw Exception('世帯のオーナーが見つかりません');
      }
      
      if (owner.userId != resettledByUserId) {
        throw Exception('精算の再確定はオーナーのみ実行できます');
      }
      
      // 既存の精算を取得
      final existingSettlement = await _getSettlementByMonth(householdId, settlementMonth);
      if (existingSettlement == null) {
        throw Exception('この月の精算が見つかりません');
      }
      
      // 精算が確定済みでない場合は通常の確定処理
      if (existingSettlement.status != SettlementStatus.settled) {
        await settleMonthlyExpenses(householdId, settlementMonth, resettledByUserId);
        return;
      }
      
      // プレビューを作成（現在の支払い比率で再計算）
      final preview = await createSettlementPreview(householdId, settlementMonth);
      
      // 精算可能かチェック
      if (!(preview['canSettle'] as bool)) {
        throw Exception('精算可能なデータがありません');
      }
      
      // 既存の精算メンバー詳細を削除
      final existingMembers = await _supabaseService.getMonthlySettlementMembers(existingSettlement.id);
      for (final member in existingMembers) {
        await _supabaseService.deleteMonthlySettlementMember(member.id);
      }
      
      // 精算レコードを更新
      final updatedSettlement = existingSettlement.copyWith(
        totalAmount: preview['totalAmount'] as int,
        settledAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _supabaseService.updateMonthlySettlement(updatedSettlement);
      
      // 新しい精算メンバー詳細を作成
      final details = preview['settlementDetails'] as List<Map<String, dynamic>>;
      for (final detail in details) {
        final settlementMember = MonthlySettlementMember(
          id: '',
          monthlySettlementId: existingSettlement.id,
          userId: detail['userId'] as String,
          paymentRatio: detail['paymentRatio'] as int,
          actualAmount: detail['actualAmount'] as int,
          calculatedAmount: detail['calculatedAmount'] as int,
          settlementAmount: detail['settlementAmount'] as int,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        
        await _supabaseService.createMonthlySettlementMember(settlementMember);
      }
      
      // 再確定通知を全メンバーに送信
      for (final member in members) {
        if (member.userId != resettledByUserId) { // 再確定者以外
          final notification = Notification(
            id: '',
            householdId: householdId,
            userId: member.userId,
            type: NotificationType.settlementResettled,
            title: '月次精算再確定',
            message: '${settlementMonth.year}年${settlementMonth.month}月の精算が再確定されました',
            isRead: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _supabaseService.createNotification(notification);
        }
      }
      
    } catch (e) {
      throw Exception('月次精算の再確定に失敗しました: $e');
    }
  }

  /// 精算確定を解除（オーナーのみ実行可能）
  Future<void> unlockSettlement(
    String householdId,
    DateTime settlementMonth,
    String unlockedByUserId, // 解除者
  ) async {
    try {
      // オーナー権限チェック
      final members = await _householdService.getActiveHouseholdMembers(householdId);
      final owner = members.where((m) => m.roleType == RoleType.owner).firstOrNull;
      
      if (owner == null) {
        throw Exception('世帯のオーナーが見つかりません');
      }
      
      if (owner.userId != unlockedByUserId) {
        throw Exception('精算確定の解除はオーナーのみ実行できます');
      }
      
      final settlement = await _getSettlementByMonth(householdId, settlementMonth);
      if (settlement == null) {
        throw Exception('この月の精算が見つかりません');
      }
      
      if (settlement.status != SettlementStatus.settled) {
        throw Exception('確定されていない精算は解除できません');
      }
      
      // ステータスをpendingに更新（編集可能に戻す）
      final updatedSettlement = settlement.copyWith(
        status: SettlementStatus.pending,
        settledAt: null,
        updatedAt: DateTime.now(),
      );
      
      await _supabaseService.updateMonthlySettlement(updatedSettlement);
      
      // 解除通知を全メンバーに送信
      for (final member in members) {
        if (member.userId != unlockedByUserId) { // 解除者以外
          final notification = Notification(
            id: '',
            householdId: householdId,
            userId: member.userId,
            type: NotificationType.settlementUnlocked,
            title: '月次精算確定解除',
            message: '${settlementMonth.year}年${settlementMonth.month}月の精算確定が解除されました',
            isRead: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _supabaseService.createNotification(notification);
        }
      }
      
    } catch (e) {
      throw Exception('精算確定の解除に失敗しました: $e');
    }
  }
}
