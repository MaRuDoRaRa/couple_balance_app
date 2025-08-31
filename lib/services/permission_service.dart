import '../models/role_permission.dart';
import '../models/household_member.dart';
import 'supabase_service.dart';

class PermissionService {
  final SupabaseService _supabaseService = SupabaseService();

  /// ユーザーが指定された権限を持っているかチェック
  Future<bool> hasPermission(String householdId, String permissionName) async {
    try {
      // データベースの権限チェック関数を使用
      final result = await _supabaseService.client.rpc(
        'check_user_permission',
        params: {
          'target_household_id': householdId,
          'required_permission': permissionName,
        },
      );
      
      return result as bool;
    } catch (e) {
      print('権限チェックエラー: $e');
      return false;
    }
  }

  /// ユーザーのロールを取得
  Future<RoleType?> getUserRole(String householdId) async {
    try {
      final currentUser = await _supabaseService.getCurrentUser();
      final members = await _supabaseService.getHouseholdMembers(householdId);
      
      final member = members.where((m) => m.userId == currentUser.id && m.isActive).firstOrNull;
      return member?.roleType;
    } catch (e) {
      print('ロール取得エラー: $e');
      return null;
    }
  }

  /// 指定されたロールの権限一覧を取得
  Future<List<RolePermission>> getRolePermissions(RoleType roleType) async {
    try {
      final response = await _supabaseService.client
          .from('role_permissions')
          .select('*')
          .eq('role_type', roleType.toString().split('.').last)
          .eq('is_active', true)
          .order('permission_name');
      
      return (response as List).map((json) => RolePermission.fromJson(json)).toList();
    } catch (e) {
      throw Exception('権限一覧の取得に失敗しました: $e');
    }
  }

  /// 全ての権限一覧を取得
  Future<List<RolePermission>> getAllPermissions() async {
    try {
      final response = await _supabaseService.client
          .from('role_permissions')
          .select('*')
          .eq('is_active', true)
          .order('role_type')
          .order('permission_name');
      
      return (response as List).map((json) => RolePermission.fromJson(json)).toList();
    } catch (e) {
      throw Exception('権限一覧の取得に失敗しました: $e');
    }
  }

  /// 新しい権限を追加（システム管理者のみ）
  Future<void> addPermission(RoleType roleType, String permissionName, String? description) async {
    try {
      await _supabaseService.client
          .from('role_permissions')
          .insert({
            'role_type': roleType.toString().split('.').last,
            'permission_name': permissionName,
            'description': description,
            'is_active': true,
          });
    } catch (e) {
      throw Exception('権限の追加に失敗しました: $e');
    }
  }

  /// 権限を無効化（システム管理者のみ）
  Future<void> deactivatePermission(String permissionId) async {
    try {
      await _supabaseService.client
          .from('role_permissions')
          .update({'is_active': false})
          .eq('id', permissionId);
    } catch (e) {
      throw Exception('権限の無効化に失敗しました: $e');
    }
  }

  /// 権限を有効化（システム管理者のみ）
  Future<void> activatePermission(String permissionId) async {
    try {
      await _supabaseService.client
          .from('role_permissions')
          .update({'is_active': true})
          .eq('id', permissionId);
    } catch (e) {
      throw Exception('権限の有効化に失敗しました: $e');
    }
  }

  /// 権限チェック付きの操作実行
  Future<T> executeWithPermission<T>(
    String householdId,
    String permissionName,
    Future<T> Function() operation,
  ) async {
    if (!await hasPermission(householdId, permissionName)) {
      throw Exception('この操作には権限が必要です: $permissionName');
    }
    
    return await operation();
  }

  /// 複数権限のいずれかを持っているかチェック
  Future<bool> hasAnyPermission(String householdId, List<String> permissionNames) async {
    for (final permissionName in permissionNames) {
      if (await hasPermission(householdId, permissionName)) {
        return true;
      }
    }
    return false;
  }

  /// 全ての権限を持っているかチェック
  Future<bool> hasAllPermissions(String householdId, List<String> permissionNames) async {
    for (final permissionName in permissionNames) {
      if (!await hasPermission(householdId, permissionName)) {
        return false;
      }
    }
    return true;
  }
}
