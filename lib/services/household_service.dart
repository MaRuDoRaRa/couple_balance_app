import 'dart:math';
import '../models/household.dart';
import '../models/household_member.dart';
import '../models/household_invitation.dart';
import '../models/notification.dart';
import '../models/user.dart';
import '../models/role_permission.dart';
import 'supabase_service.dart';
import 'notification_service.dart';
import 'permission_service.dart';

class HouseholdService {
  final SupabaseService _supabaseService = SupabaseService();
  final PermissionService _permissionService = PermissionService();

  /// 世帯カラーを更新（権限チェック付き）
  Future<void> updateHouseholdColor(String householdId, String color) async {
    try {
      // 権限チェック
      await _checkPermission(householdId, PermissionNames.categoryManage);
      
      await _supabaseService.client
          .from('households')
          .update({'color': color})
          .eq('id', householdId);
    } catch (e) {
      throw Exception('世帯カラーの更新に失敗しました: $e');
    }
  }

  /// Google認証後にプロフィール入力と世帯作成をまとめて実行し、当人をオーナーとして登録
  Future<Household> registerNewHouseholdAndOwner({
    required String householdName,
    required String nickname,
    required String iconUrl,
    required String color,
  }) async {
    try {
      // 認証済みユーザー取得（Google認証はUI側で実施済みを想定）
      final auth = await _supabaseService.getCurrentUser();

      // プロフィールをUsersテーブルに作成/更新（メールはGoogleのアドレスを使用・変更不可）
      final appUser = User(
        id: auth.id,
        email: auth.email ?? '',
        nickname: nickname,
        iconUrl: iconUrl,
        color: color,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _supabaseService.upsertUser(appUser);

      // 世帯作成 + オーナー追加（支払い比率100%）
      final createdHousehold = await createHouseholdWithOwner(householdName, auth.id);

      return createdHousehold;
    } catch (e) {
      throw Exception('新規世帯登録に失敗しました: $e');
    }
  }

  /// 世帯メンバーの支払い比率を更新（権限チェック付き、合計100になるように自動調整）
  Future<void> updatePaymentRatios(
    String householdId,
    Map<String, int> memberRatios, // user_id -> payment_ratio
  ) async {
    try {
      // 権限チェック
      await _checkPermission(householdId, PermissionNames.paymentRatioUpdate);
      
      // 現在のアクティブなメンバーを取得
      final currentMembers = await getActiveHouseholdMembers(householdId);
      
      // 変更対象のメンバーと変更されないメンバーを分離
      final changedMembers = <String, int>{};
      final unchangedMembers = <HouseholdMember>[];
      
      for (final member in currentMembers) {
        if (memberRatios.containsKey(member.userId)) {
          changedMembers[member.userId] = memberRatios[member.userId]!;
        } else {
          unchangedMembers.add(member);
        }
      }
      
      // 変更されないメンバーの現在の合計
      final unchangedTotal = unchangedMembers.fold(0, (sum, member) => sum + member.paymentRatio);
      
      // 変更対象メンバーの新しい合計
      final changedTotal = changedMembers.values.fold(0, (sum, ratio) => sum + ratio);
      
      // 全体の合計
      final newTotal = unchangedTotal + changedTotal;
      
      if (newTotal > 100) {
        // 変更されないメンバーの比率を保持しつつ、変更対象メンバーを調整
        final availableRatio = 100 - unchangedTotal;
        
        if (availableRatio < 0) {
          throw Exception('変更されないメンバーの合計比率が100を超えています');
        }
        
        // 変更対象メンバーの比率を利用可能な範囲内で正規化
        final normalizedChangedMembers = <String, int>{};
        changedMembers.forEach((userId, ratio) {
          final normalizedRatio = ((ratio * availableRatio) / changedTotal).round();
          normalizedChangedMembers[userId] = normalizedRatio;
        });
        
        // 丸め誤差を調整
        final adjustedTotal = normalizedChangedMembers.values.fold(0, (sum, ratio) => sum + ratio);
        if (adjustedTotal != availableRatio && normalizedChangedMembers.isNotEmpty) {
          final firstUserId = normalizedChangedMembers.keys.first;
          normalizedChangedMembers[firstUserId] = normalizedChangedMembers[firstUserId]! + (availableRatio - adjustedTotal);
        }
        
        changedMembers.clear();
        changedMembers.addAll(normalizedChangedMembers);
      }
      
      // 変更対象メンバーを更新
      for (final entry in changedMembers.entries) {
        final userId = entry.key;
        final newRatio = entry.value;
        
        final member = currentMembers.firstWhere(
          (m) => m.userId == userId,
          orElse: () => throw Exception('Member not found: $userId'),
        );
        
        final updatedMember = member.copyWith(paymentRatio: newRatio);
        await _supabaseService.updateHouseholdMember(updatedMember);
      }
      
    } catch (e) {
      throw Exception('支払い比率の更新に失敗しました: $e');
    }
  }

  /// 世帯メンバーの支払い比率を更新（権限チェック付き、比例配分で調整）
  Future<void> updatePaymentRatiosWithProportionalAdjustment(
    String householdId,
    Map<String, int> memberRatios, // user_id -> payment_ratio
  ) async {
    try {
      // 権限チェック
      await _checkPermission(householdId, PermissionNames.paymentRatioUpdate);
      
      final currentMembers = await getActiveHouseholdMembers(householdId);
      
      // 変更対象と変更されないメンバーを分離
      final changedMembers = <String, int>{};
      final unchangedMembers = <HouseholdMember>[];
      
      for (final member in currentMembers) {
        if (memberRatios.containsKey(member.userId)) {
          changedMembers[member.userId] = memberRatios[member.userId]!;
        } else {
          unchangedMembers.add(member);
        }
      }
      
      // 変更対象メンバーの新しい合計
      final changedTotal = changedMembers.values.fold(0, (sum, ratio) => sum + ratio);
      
      // 変更されないメンバーの現在の合計
      final unchangedTotal = unchangedMembers.fold(0, (sum, member) => sum + member.paymentRatio);
      
      // 全体の合計
      final newTotal = unchangedTotal + changedTotal;
      
      if (newTotal > 100) {
        // 変更されないメンバーの現在の比率の合計
        final unchangedTotalRatio = unchangedMembers.fold(0, (sum, member) => sum + member.paymentRatio);
        
        // 利用可能な比率（100 - 変更対象の合計）
        final availableRatio = 100 - changedTotal;
        
        // 変更されないメンバーの比率を現在の比率に比例して分配
        for (final member in unchangedMembers) {
          final currentRatio = member.paymentRatio;
          final newRatio = ((currentRatio * availableRatio) / unchangedTotalRatio).round();
          
          final updatedMember = member.copyWith(paymentRatio: newRatio);
          await _supabaseService.updateHouseholdMember(updatedMember);
        }
      }
      
      // 変更対象メンバーを更新
      for (final entry in changedMembers.entries) {
        final userId = entry.key;
        final newRatio = entry.value;
        
        final member = currentMembers.firstWhere(
          (m) => m.userId == userId,
          orElse: () => throw Exception('Member not found: $userId'),
        );
        
        final updatedMember = member.copyWith(paymentRatio: newRatio);
        await _supabaseService.updateHouseholdMember(updatedMember);
      }
      
    } catch (e) {
      throw Exception('支払い比率の更新に失敗しました: $e');
    }
  }

  /// 世帯メンバーを追加（自動的に比率を調整）
  Future<void> addHouseholdMember(
    String householdId,
    String userId,
    RoleType roleType,
    int paymentRatio,
  ) async {
    try {
      // 現在のアクティブなメンバーを取得
      final currentMembers = await getActiveHouseholdMembers(householdId);
      
      // 新しいメンバーを追加した場合の合計比率を計算
      int totalRatio = currentMembers.fold(0, (sum, member) => sum + member.paymentRatio) + paymentRatio;
      
      // 合計が100を超える場合は既存メンバーの比率を調整
      if (totalRatio > 100) {
        final excessRatio = totalRatio - 100;
        final currentTotal = currentMembers.fold(0, (sum, member) => sum + member.paymentRatio);
        
        // 既存メンバーの比率を比例配分で調整
        for (final member in currentMembers) {
          final currentRatio = member.paymentRatio;
          final adjustedRatio = ((currentRatio * (currentTotal - excessRatio)) / currentTotal).round();
          
          final updatedMember = member.copyWith(paymentRatio: adjustedRatio);
          await _supabaseService.updateHouseholdMember(updatedMember);
        }
        
        // 新しいメンバーの比率を調整
        paymentRatio = paymentRatio - excessRatio;
      }
      
      // 新しいメンバーを作成
      final newMember = HouseholdMember(
        id: '',
        householdId: householdId,
        userId: userId,
        roleType: roleType,
        paymentRatio: paymentRatio,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _supabaseService.createHouseholdMember(newMember);
      
    } catch (e) {
      throw Exception('世帯メンバーの追加に失敗しました: $e');
    }
  }

  /// 世帯メンバーを削除（自動的に比率を再分配）
  Future<void> removeHouseholdMember(String memberId) async {
    try {
      // 削除するメンバーを取得
      final member = await _supabaseService.getHouseholdMemberById(memberId);
      if (member == null) {
        throw Exception('Member not found: $memberId');
      }
      
      // 削除するメンバーの比率
      final removedRatio = member.paymentRatio;
      
      // メンバーを削除（is_active = falseに設定）
      final updatedMember = member.copyWith(isActive: false);
      await _supabaseService.updateHouseholdMember(updatedMember);
      
      // 残りのアクティブなメンバーを取得
      final remainingMembers = await getActiveHouseholdMembers(member.householdId);
      
      // 削除された比率を残りのメンバーに再分配
      if (remainingMembers.isNotEmpty && removedRatio > 0) {
        final currentTotal = remainingMembers.fold(0, (sum, m) => sum + m.paymentRatio);
        
        for (final remainingMember in remainingMembers) {
          final currentRatio = remainingMember.paymentRatio;
          final newRatio = currentRatio + ((currentRatio * removedRatio) / currentTotal).round();
          
          final updatedRemainingMember = remainingMember.copyWith(paymentRatio: newRatio);
          await _supabaseService.updateHouseholdMember(updatedRemainingMember);
        }
      }
      
    } catch (e) {
      throw Exception('世帯メンバーの削除に失敗しました: $e');
    }
  }

  /// アクティブな世帯メンバーを取得
  Future<List<HouseholdMember>> getActiveHouseholdMembers(String householdId) async {
    try {
      final members = await _supabaseService.getHouseholdMembers(householdId);
      return members.where((member) => member.isActive).toList();
    } catch (e) {
      throw Exception('世帯メンバーの取得に失敗しました: $e');
    }
  }

  /// 世帯の支払い比率合計を取得
  Future<int> getPaymentRatioTotal(String householdId) async {
    try {
      final members = await getActiveHouseholdMembers(householdId);
      return members.fold(0, (sum, member) => sum + member.paymentRatio);
    } catch (e) {
      throw Exception('支払い比率合計の取得に失敗しました: $e');
    }
  }

  /// 支払い比率の妥当性をチェック
  Future<bool> validatePaymentRatios(String householdId) async {
    try {
      final total = await getPaymentRatioTotal(householdId);
      return total == 100;
    } catch (e) {
      return false;
    }
  }

  /// 支払い比率を自動調整（合計が100になるように）
  Future<void> autoAdjustPaymentRatios(String householdId) async {
    try {
      final members = await getActiveHouseholdMembers(householdId);
      if (members.isEmpty) return;
      
      final totalRatio = members.fold(0, (sum, member) => sum + member.paymentRatio);
      
      if (totalRatio != 100) {
        // 比率を正規化
        final adjustedMembers = <HouseholdMember>[];
        
        for (int i = 0; i < members.length; i++) {
          final member = members[i];
          int newRatio;
          
          if (i == members.length - 1) {
            // 最後のメンバーには残りの比率を割り当て
            final assignedTotal = adjustedMembers.fold(0, (sum, m) => sum + m.paymentRatio);
            newRatio = 100 - assignedTotal;
          } else {
            // 他のメンバーは比例配分
            newRatio = ((member.paymentRatio * 100) / totalRatio).round();
          }
          
          final adjustedMember = member.copyWith(paymentRatio: newRatio);
          adjustedMembers.add(adjustedMember);
        }
        
        // 更新を実行
        for (final member in adjustedMembers) {
          await _supabaseService.updateHouseholdMember(member);
        }
      }
      
    } catch (e) {
      throw Exception('支払い比率の自動調整に失敗しました: $e');
    }
  }

  /// 世帯を作成し、作成者をオーナーとして追加
  Future<Household> createHouseholdWithOwner(
    String householdName,
    String ownerUserId,
  ) async {
    try {
      // 世帯を作成
      final household = Household(
        id: '',
        name: householdName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      final createdHousehold = await _supabaseService.createHousehold(household);
      
      // 作成者をオーナーとして追加
      final ownerMember = HouseholdMember(
        id: '',
        householdId: createdHousehold.id,
        userId: ownerUserId,
        roleType: RoleType.owner,
        paymentRatio: 100, // 最初は100%
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _supabaseService.createHouseholdMember(ownerMember);
      
      return createdHousehold;
      
    } catch (e) {
      throw Exception('世帯の作成に失敗しました: $e');
    }
  }

  

  /// 招待を作成し、メール送信をトリガー（オーナーのみ、自分の世帯限定）
  Future<String> createInvitationAndSendEmail({
    required String householdId,
    required String inviteeEmail,
    required RoleType roleType,
    Duration ttl = const Duration(hours: 24),
  }) async {
    try {
      // 1) 権限チェック（自分の世帯に対する招待作成権限）
      await _checkPermission(householdId, PermissionNames.invitationCreate);

      // 2) 招待コード生成と保存（RLSによりownerのみ可、created_by=auth.uid必須）
      final invitationCode = _generateInvitationCode();
      final currentUser = await _supabaseService.getCurrentUser();

      await _supabaseService.client
          .from('household_invitations')
          .insert({
            'invitation_code': invitationCode,
            'household_id': householdId,
            'expires_at': DateTime.now().add(ttl).toIso8601String(),
            'created_by': currentUser.id,
          });

      // 3) Deep Link と Web フォールバックURL
      final appDeepLink = 'io.couplebalance.app://invitation?code=$invitationCode&role=${roleType.toString().split('.').last}';
      final webFallback = 'https://your-app.com/invitation/$invitationCode';

      // 4) Edge Function でメール送信をトリガー
      await _supabaseService.client.functions.invoke('send-invitation-email', body: {
        'to': inviteeEmail,
        'household_id': householdId,
        'invitation_code': invitationCode,
        'role_type': roleType.toString().split('.').last,
        'app_link': appDeepLink,
        'web_fallback': webFallback,
      });

      return appDeepLink;
    } catch (e) {
      throw Exception('招待の作成/送信に失敗しました: $e');
    }
  }

  /// 招待コードを生成
  String _generateInvitationCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  /// 権限チェック
  Future<void> _checkPermission(String householdId, String permissionName) async {
    if (!await _permissionService.hasPermission(householdId, permissionName)) {
      throw Exception('この操作には権限が必要です: $permissionName');
    }
  }

  /// オーナー権限チェック（後方互換性のため残す）
  Future<void> _checkOwnerPermission(String householdId) async {
    await _checkPermission(householdId, PermissionNames.paymentRatioUpdate);
  }

  /// 招待コードで招待情報を取得
  Future<HouseholdInvitation> getInvitationByCode(String invitationCode) async {
    try {
      final invitation = await _supabaseService.client
          .from('household_invitations')
          .select('''
            *,
            household:households(name),
            creator:users(nickname)
          ''')
          .eq('invitation_code', invitationCode)
          .eq('is_used', false)
          .single();
      
      if (invitation == null) {
        throw Exception('招待が見つからないか、既に使用されています');
      }
      
      return HouseholdInvitation.fromJson(invitation);
      
    } catch (e) {
      throw Exception('招待情報の取得に失敗しました: $e');
    }
  }

  

  /// 招待を承諾（プロフィール保存を含む）
  Future<void> acceptInvitationWithProfile({
    required String invitationCode,
    required String nickname,
    required String iconUrl,
    required String color,
  }) async {
    try {
      // 招待情報を取得（世帯名の表示に利用可能）
      final invitation = await getInvitationByCode(invitationCode);
      if (!invitation.isValid) {
        throw Exception('招待が無効です（期限切れまたは既に使用済み）');
      }

      // Google認証はUI側で実施済みを前提に、現在のユーザーを取得
      final auth = await _supabaseService.getCurrentUser();

      // プロフィールを作成/更新（メールはGoogleのアドレス固定）
      final appUser = User(
        id: auth.id,
        email: auth.email ?? '',
        nickname: nickname,
        iconUrl: iconUrl,
        color: color,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _supabaseService.upsertUser(appUser);

      // 世帯メンバーとして追加（初期比率0% / roleはmember）
      await addHouseholdMember(
        invitation.householdId,
        auth.id,
        RoleType.member,
        0,
      );

      // 招待を使用済みにマーク
      await _supabaseService.client
          .from('household_invitations')
          .update({'is_used': true})
          .eq('invitation_code', invitationCode);
    } catch (e) {
      throw Exception('招待の承諾（プロフィール含む）に失敗しました: $e');
    }
  }

  /// 世帯からメンバーを削除（権限チェック付き）
  Future<void> removeMemberFromHousehold(
    String householdId,
    String memberUserId,
  ) async {
    try {
      // 権限チェック
      await _checkPermission(householdId, PermissionNames.memberRemove);
      
      // メンバーを取得
      final members = await getActiveHouseholdMembers(householdId);
      final member = members.where((m) => m.userId == memberUserId).firstOrNull;
      
      if (member == null) {
        throw Exception('メンバーが見つかりません');
      }
      
      // オーナーは削除できない
      if (member.roleType == RoleType.owner) {
        throw Exception('オーナーは削除できません');
      }
      
      // メンバーを削除（自動的に比率を再分配）
      await removeHouseholdMember(member.id);
      
      // 削除通知を作成
      final notification = Notification(
        id: '',
        householdId: householdId,
        userId: memberUserId,
        type: NotificationType.memberRemoval,
        title: '世帯からの削除',
        message: '世帯から削除されました',
        isRead: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _supabaseService.createNotification(notification);
      
    } catch (e) {
      throw Exception('メンバーの削除に失敗しました: $e');
    }
  }

  /// 世帯のオーナーを変更（権限チェック付き）
  Future<void> transferOwnership(
    String householdId,
    String newOwnerUserId,
  ) async {
    try {
      // 権限チェック
      await _checkPermission(householdId, PermissionNames.ownershipTransfer);
      
      // 現在のメンバーを取得
      final members = await getActiveHouseholdMembers(householdId);
      
      // 新しいオーナー候補を確認
      final newOwner = members.where((m) => m.userId == newOwnerUserId).firstOrNull;
      if (newOwner == null) {
        throw Exception('新しいオーナー候補が世帯のメンバーではありません');
      }
      
      // 現在のオーナーを取得
      final currentOwner = members.where((m) => m.roleType == RoleType.owner).firstOrNull;
      if (currentOwner == null) {
        throw Exception('現在のオーナーが見つかりません');
      }
      
      // 役割を変更
      final updatedCurrentOwner = currentOwner.copyWith(roleType: RoleType.member);
      final updatedNewOwner = newOwner.copyWith(roleType: RoleType.owner);
      
      await _supabaseService.updateHouseholdMember(updatedCurrentOwner);
      await _supabaseService.updateHouseholdMember(updatedNewOwner);
      
      // オーナー変更通知を作成
      final notification = Notification(
        id: '',
        householdId: householdId,
        userId: newOwnerUserId,
        type: NotificationType.ownershipTransfer,
        title: 'オーナー権限の譲渡',
        message: '世帯のオーナーになりました',
        isRead: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _supabaseService.createNotification(notification);
      
    } catch (e) {
      throw Exception('オーナーの変更に失敗しました: $e');
    }
  }

  /// 世帯を削除（権限チェック付き）
  Future<void> deleteHousehold(String householdId, String requestingUserId) async {
    try {
      // 権限チェック
      await _checkPermission(householdId, PermissionNames.householdDelete);
      
      // リクエストしたユーザーが現在のユーザーかチェック
      final currentUser = await _supabaseService.getCurrentUser();
      if (currentUser.id != requestingUserId) {
        throw Exception('不正なリクエストです');
      }
      
      // 世帯に属するデータを削除（CASCADE制約により自動削除）
      // - household_members
      // - expenses
      // - categories
      // - sub_categories
      // - notifications
      // - monthly_settlements
      // - monthly_settlement_members
      // - csv_import_patterns
      
      // 世帯を削除
      await _supabaseService.deleteHousehold(householdId);
      
      // 削除通知を全メンバーに送信（削除前に送信）
      for (final member in members) {
        if (member.userId != requestingUserId) { // 削除実行者以外
          final notification = Notification(
            id: '',
            householdId: householdId,
            userId: member.userId,
            type: NotificationType.householdDeleted,
            title: '世帯の削除',
            message: '世帯が削除されました',
            isRead: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _supabaseService.createNotification(notification);
        }
      }
      
    } catch (e) {
      throw Exception('世帯の削除に失敗しました: $e');
    }
  }

  /// 世帯削除の確認（削除前のデータ確認、権限チェック付き）
  Future<Map<String, dynamic>> getHouseholdDeletionSummary(String householdId, String requestingUserId) async {
    try {
      // 権限チェック
      await _checkPermission(householdId, PermissionNames.householdDelete);
      
      // リクエストしたユーザーが現在のユーザーかチェック
      final currentUser = await _supabaseService.getCurrentUser();
      if (currentUser.id != requestingUserId) {
        throw Exception('不正なリクエストです');
      }
      
      // 削除されるデータの概要を取得
      final expenses = await _supabaseService.getExpenses(householdId: householdId);
      final categories = await _supabaseService.getCategories(householdId: householdId);
      final subCategories = await _supabaseService.getSubCategories(householdId: householdId);
      final settlements = await _supabaseService.getMonthlySettlements(householdId: householdId);
      
      return {
        'memberCount': members.length,
        'expenseCount': expenses.length,
        'totalExpenseAmount': expenses.fold(0, (sum, e) => sum + e.amount.toInt()),
        'categoryCount': categories.length,
        'subCategoryCount': subCategories.length,
        'settlementCount': settlements.length,
        'members': members.map((m) => {
          'userId': m.userId,
          'role': m.roleType.toString(),
          'paymentRatio': m.paymentRatio,
        }).toList(),
      };
      
    } catch (e) {
      throw Exception('世帯削除確認の取得に失敗しました: $e');
    }
  }
}
