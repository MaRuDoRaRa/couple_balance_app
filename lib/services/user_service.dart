import '../models/user.dart';
import 'supabase_service.dart';

class UserService {
  final SupabaseService _supabaseService = SupabaseService();

  /// ユーザーのカラーを更新
  Future<void> updateUserColor(String color) async {
    try {
      final currentUser = await _supabaseService.getCurrentUser();
      await _supabaseService.client
          .from('users')
          .update({'color': color})
          .eq('id', currentUser.id);
    } catch (e) {
      throw Exception('ユーザーカラーの更新に失敗しました: $e');
    }
  }

  /// ユーザー情報を取得（カラー情報を含む）
  Future<User> getUser(String userId) async {
    try {
      final response = await _supabaseService.client
          .from('users')
          .select('*')
          .eq('id', userId)
          .single();
      
      return User.fromJson(response);
    } catch (e) {
      throw Exception('ユーザー情報の取得に失敗しました: $e');
    }
  }

  /// 現在のユーザー情報を取得
  Future<User> getCurrentUser() async {
    try {
      final authUser = await _supabaseService.getCurrentUser();
      return await getUser(authUser.id);
    } catch (e) {
      throw Exception('現在のユーザー情報の取得に失敗しました: $e');
    }
  }

  /// 世帯メンバーのユーザー情報を取得（カラー情報を含む）
  Future<List<User>> getHouseholdMemberUsers(String householdId) async {
    try {
      final response = await _supabaseService.client
          .from('household_members')
          .select('''
            user_id,
            users!inner(*)
          ''')
          .eq('household_id', householdId)
          .eq('is_active', true);
      
      return (response as List)
          .map((json) => User.fromJson(json['users']))
          .toList();
    } catch (e) {
      throw Exception('世帯メンバーのユーザー情報取得に失敗しました: $e');
    }
  }

  /// 支出作成者のユーザー情報を取得（カラー情報を含む）
  Future<User?> getExpenseCreator(String userId) async {
    try {
      final response = await _supabaseService.client
          .from('users')
          .select('*')
          .eq('id', userId)
          .maybeSingle();
      
      return response != null ? User.fromJson(response) : null;
    } catch (e) {
      print('支出作成者のユーザー情報取得エラー: $e');
      return null;
    }
  }

  /// デフォルトカラーパレット（ユーザー用）
  static const List<String> defaultColors = [
    '#3B82F6', // 青
    '#EF4444', // 赤
    '#10B981', // 緑
    '#F59E0B', // オレンジ
    '#8B5CF6', // 紫
    '#EC4899', // ピンク
    '#06B6D4', // シアン
    '#84CC16', // ライム
    '#F97316', // オレンジ
    '#6366F1', // インディゴ
  ];

  /// デフォルトカラーパレット（世帯用）
  static const List<String> householdColors = [
    '#10B981', // 緑
    '#3B82F6', // 青
    '#F59E0B', // オレンジ
    '#8B5CF6', // 紫
    '#EC4899', // ピンク
    '#EF4444', // 赤
    '#06B6D4', // シアン
    '#84CC16', // ライム
    '#F97316', // オレンジ
    '#6366F1', // インディゴ
  ];

  /// ランダムなユーザーカラーを取得
  static String getRandomColor() {
    final random = DateTime.now().millisecondsSinceEpoch % defaultColors.length;
    return defaultColors[random];
  }

  /// ランダムな世帯カラーを取得
  static String getRandomHouseholdColor() {
    final random = DateTime.now().millisecondsSinceEpoch % householdColors.length;
    return householdColors[random];
  }

  /// カラーが有効なHEX形式かチェック
  static bool isValidColor(String color) {
    final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
    return hexPattern.hasMatch(color);
  }
}
