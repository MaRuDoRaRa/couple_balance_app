import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/user.dart';
import '../models/expense.dart';
import '../models/category.dart';
import '../models/notification.dart';
import '../models/csv_import_pattern.dart';
import '../models/financial_institution.dart';
import '../models/household.dart';
import '../models/household_member.dart';
import '../models/category_icon.dart';
import '../models/monthly_settlement.dart';

// Lightweight auth identity to avoid name collisions with app's User model
class AuthIdentity {
  final String id;
  final String? email;
  AuthIdentity({required this.id, this.email});
}

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  // Expose client for advanced queries used by higher-level services
  SupabaseClient get client => _client;

  /// Get current authenticated user (throws if not logged in)
  Future<AuthIdentity> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('サインインしていません');
    }
    return AuthIdentity(id: user.id, email: user.email);
    }

  /// Sign in with Google OAuth (PKCE flow on mobile)
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(Provider.google);
  }

  /// Sign out current user
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Create or update a user row in application users table
  Future<User> upsertUser(User user) async {
    final response = await _client
        .from('users')
        .upsert(user.toJson())
        .select()
        .single();
    return User.fromJson(response);
  }

  // User related methods
  Future<List<User>> getUsers() async {
    final response = await _client
        .from('users')
        .select()
        .order('created_at');
    
    return (response as List).map((json) => User.fromJson(json)).toList();
  }

  Future<User?> getUserById(String id) async {
    final response = await _client
        .from('users')
        .select()
        .eq('id', id)
        .single();
    
    return response != null ? User.fromJson(response) : null;
  }

  Future<User?> getUserByType(UserType userType) async {
    final response = await _client
        .from('users')
        .select()
        .eq('user_type', userType.toString().split('.').last)
        .single();
    
    return response != null ? User.fromJson(response) : null;
  }

  Future<void> updateUser(User user) async {
    await _client
        .from('users')
        .update(user.toJson())
        .eq('id', user.id);
  }

  // Expense related methods
  Future<List<Expense>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? householdId,
  }) async {
    var query = _client
        .from('expenses')
        .select('''
          *,
          sub_category:sub_categories(*),
          financial_institution:financial_institutions(*),
          user:users(nickname, color)
        ''')
        .order('expense_date', ascending: false);

    if (householdId != null) {
      query = query.eq('household_id', householdId);
    }
    if (startDate != null) {
      query = query.gte('expense_date', startDate.toIso8601String().split('T')[0]);
    }
    if (endDate != null) {
      query = query.lte('expense_date', endDate.toIso8601String().split('T')[0]);
    }

    final response = await query;
    
    return (response as List).map((json) {
      // ユーザー情報を追加
      final userData = json['user'] as Map<String, dynamic>?;
      json['user_name'] = userData?['nickname'];
      json['user_color'] = userData?['color'];
      return Expense.fromJson(json);
    }).toList();
  }

  /// 未設定カテゴリの支出を取得
  Future<List<Expense>> getUncategorizedExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? householdId,
  }) async {
    var query = _client
        .from('expenses')
        .select('''
          *,
          financial_institution:financial_institutions(*),
          user:users(nickname, color)
        ''')
        .is_('sub_category_id', null)
        .order('expense_date', ascending: false);

    if (householdId != null) {
      query = query.eq('household_id', householdId);
    }
    if (startDate != null) {
      query = query.gte('expense_date', startDate.toIso8601String().split('T')[0]);
    }
    if (endDate != null) {
      query = query.lte('expense_date', endDate.toIso8601String().split('T')[0]);
    }

    final response = await query;
    
    return (response as List).map((json) {
      // ユーザー情報を追加
      final userData = json['user'] as Map<String, dynamic>?;
      json['user_name'] = userData?['nickname'];
      json['user_color'] = userData?['color'];
      return Expense.fromJson(json);
    }).toList();
  }

  /// 支出を作成（精算確定済みの月は制限）
  Future<Expense> createExpense(Expense expense) async {
    // 精算確定済みかチェック
    await _checkSettlementStatus(expense.householdId, expense.expenseDate);
    
    final response = await _client
        .from('expenses')
        .insert(expense.toJson())
        .select()
        .single();
    
    return Expense.fromJson(response);
  }

  /// 支出を更新（精算確定済みの月は制限）
  Future<void> updateExpense(Expense expense) async {
    // 精算確定済みかチェック
    await _checkSettlementStatus(expense.householdId, expense.expenseDate);
    
    await _client
        .from('expenses')
        .update(expense.toJson())
        .eq('id', expense.id);
  }

  /// 支出を削除（精算確定済みの月は制限）
  Future<void> deleteExpense(String expenseId) async {
    // 支出の情報を取得
    final expense = await _client
        .from('expenses')
        .select('household_id, expense_date')
        .eq('id', expenseId)
        .single();
    
    if (expense != null) {
      // 精算確定済みかチェック
      await _checkSettlementStatus(expense['household_id'], DateTime.parse(expense['expense_date']));
    }
    
    await _client
        .from('expenses')
        .delete()
        .eq('id', expenseId);
  }

  /// 精算確定済みかチェック
  Future<void> _checkSettlementStatus(String householdId, DateTime expenseDate) async {
    final settlementMonth = DateTime(expenseDate.year, expenseDate.month, 1);
    
    final settlement = await _client
        .from('monthly_settlements')
        .select('status')
        .eq('household_id', householdId)
        .eq('settlement_month', settlementMonth.toIso8601String().split('T')[0])
        .single();
    
    if (settlement != null && settlement['status'] == 'settled') {
      throw Exception('この月の精算は確定済みのため、支出の追加・編集・削除はできません');
    }
  }

  // Category related methods
  Future<List<Category>> getCategories() async {
    final response = await _client
        .from('categories')
        .select()
        .order('name');
    
    return (response as List).map((json) => Category.fromJson(json)).toList();
  }

  Future<void> deleteCategory(String categoryId) async {
    // カテゴリに属するサブカテゴリを取得
    final subCategories = await _client
        .from('sub_categories')
        .select('id')
        .eq('category_id', categoryId);
    
    final subCategoryIds = (subCategories as List).map((e) => e['id'] as String).toList();
    
    if (subCategoryIds.isNotEmpty) {
      // サブカテゴリに属する支出のsub_category_idをNULLに設定
      await _client
          .from('expenses')
          .update({'sub_category_id': null})
          .in_('sub_category_id', subCategoryIds);
      
      // CSVインポートパターンのsub_category_idをNULLに設定
      await _client
          .from('csv_import_patterns')
          .update({'sub_category_id': null})
          .in_('sub_category_id', subCategoryIds);
      
      // サブカテゴリを削除
      await _client
          .from('sub_categories')
          .delete()
          .eq('category_id', categoryId);
    }
    
    // カテゴリを削除
    await _client
        .from('categories')
        .delete()
        .eq('id', categoryId);
  }

  Future<void> deleteSubCategory(String subCategoryId) async {
    // サブカテゴリに属する支出のsub_category_idをNULLに設定
    await _client
        .from('expenses')
        .update({'sub_category_id': null})
        .eq('sub_category_id', subCategoryId);
    
    // CSVインポートパターンのsub_category_idをNULLに設定
    await _client
        .from('csv_import_patterns')
        .update({'sub_category_id': null})
        .eq('sub_category_id', subCategoryId);
    
    // サブカテゴリを削除
    await _client
        .from('sub_categories')
        .delete()
        .eq('id', subCategoryId);
  }

  // Notification related methods
  Future<List<Notification>> getNotifications(String userId) async {
    final response = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    
    return (response as List).map((json) => Notification.fromJson(json)).toList();
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<void> createNotification(Notification notification) async {
    await _client
        .from('notifications')
        .insert(notification.toJson());
  }

  // Household related methods
  Future<List<Household>> getHouseholds(String userId) async {
    final response = await _client
        .from('households')
        .select()
        .order('created_at', ascending: false);
    
    return (response as List).map((json) => Household.fromJson(json)).toList();
  }

  Future<Household> createHousehold(Household household) async {
    final response = await _client
        .from('households')
        .insert(household.toJson())
        .select()
        .single();
    
    return Household.fromJson(response);
  }

  Future<void> updateHousehold(Household household) async {
    await _client
        .from('households')
        .update(household.toJson())
        .eq('id', household.id);
  }

  Future<void> deleteHousehold(String householdId) async {
    await _client
        .from('households')
        .delete()
        .eq('id', householdId);
  }

  // Household Members related methods
  Future<List<HouseholdMember>> getHouseholdMembers(String householdId) async {
    final response = await _client
        .from('household_members')
        .select('''
          *,
          user:users(*)
        ''')
        .eq('household_id', householdId)
        .order('created_at');

    return (response as List).map((json) => HouseholdMember.fromJson(json)).toList();
  }

  Future<HouseholdMember?> getHouseholdMemberById(String memberId) async {
    final response = await _client
        .from('household_members')
        .select('''
          *,
          user:users(*)
        ''')
        .eq('id', memberId)
        .single();
    
    return response != null ? HouseholdMember.fromJson(response) : null;
  }

  Future<HouseholdMember> createHouseholdMember(HouseholdMember member) async {
    final response = await _client
        .from('household_members')
        .insert(member.toJson())
        .select()
        .single();
    
    return HouseholdMember.fromJson(response);
  }

  Future<void> updateHouseholdMember(HouseholdMember member) async {
    await _client
        .from('household_members')
        .update(member.toJson())
        .eq('id', member.id);
  }

  // Category Icons related methods
  Future<List<CategoryIcon>> getCategoryIcons() async {
    final response = await _client
        .from('category_icons')
        .select()
        .eq('is_active', true)
        .order('id');
    
    return (response as List).map((json) => CategoryIcon.fromJson(json)).toList();
  }

  // Financial Institutions related methods
  Future<List<FinancialInstitution>> getFinancialInstitutions() async {
    final response = await _client
        .from('financial_institutions')
        .select()
        .eq('is_active', true)
        .order('name');
    
    return (response as List).map((json) => FinancialInstitution.fromJson(json)).toList();
  }

  Future<FinancialInstitution?> getFinancialInstitutionByCode(String code) async {
    final response = await _client
        .from('financial_institutions')
        .select()
        .eq('code', code)
        .eq('is_active', true)
        .single();
    
    return response != null ? FinancialInstitution.fromJson(response) : null;
  }

  // CSV Import Patterns related methods
  Future<List<CsvImportPattern>> getCsvImportPatterns(String userId, String financialInstitutionId) async {
    final response = await _client
        .from('csv_import_patterns')
        .select('''
          *,
          sub_category:sub_categories(*)
        ''')
        .eq('user_id', userId)
        .eq('financial_institution_id', financialInstitutionId)
        .order('created_at', ascending: false);
    
    return (response as List).map((json) => CsvImportPattern.fromJson(json)).toList();
  }

  Future<CsvImportPattern> createCsvImportPattern(CsvImportPattern pattern) async {
    final response = await _client
        .from('csv_import_patterns')
        .insert(pattern.toJson())
        .select()
        .single();
    
    return CsvImportPattern.fromJson(response);
  }

  Future<void> updateCsvImportPattern(CsvImportPattern pattern) async {
    await _client
        .from('csv_import_patterns')
        .update(pattern.toJson())
        .eq('id', pattern.id);
  }

  Future<void> deleteCsvImportPattern(String patternId) async {
    await _client
        .from('csv_import_patterns')
        .delete()
        .eq('id', patternId);
  }

  // Monthly Settlements
  Future<List<MonthlySettlement>> getMonthlySettlements(
    String householdId, {
    int? limit,
    int? offset,
  }) async {
    var query = _client
        .from('monthly_settlements')
        .select()
        .eq('household_id', householdId)
        .order('settlement_month', ascending: false);
    
    if (limit != null) query = query.limit(limit);
    if (offset != null) query = query.range(offset, offset + (limit ?? 10) - 1);
    
    final response = await query;
    
    return (response as List)
        .map((json) => MonthlySettlement.fromJson(json))
        .toList();
  }

  Future<MonthlySettlement> createMonthlySettlement(MonthlySettlement settlement) async {
    final response = await _client
        .from('monthly_settlements')
        .insert(settlement.toJson())
        .select()
        .single();
    
    return MonthlySettlement.fromJson(response);
  }

  Future<MonthlySettlement> updateMonthlySettlement(MonthlySettlement settlement) async {
    final response = await _client
        .from('monthly_settlements')
        .update(settlement.toJson())
        .eq('id', settlement.id)
        .select()
        .single();
    
    return MonthlySettlement.fromJson(response);
  }

  Future<void> deleteMonthlySettlement(String id) async {
    await _client
        .from('monthly_settlements')
        .delete()
        .eq('id', id);
  }

  // Monthly Settlement Members
  Future<List<MonthlySettlementMember>> getMonthlySettlementMembers(String settlementId) async {
    final response = await _client
        .from('monthly_settlement_members')
        .select()
        .eq('monthly_settlement_id', settlementId)
        .order('created_at', ascending: false);
    
    return (response as List)
        .map((json) => MonthlySettlementMember.fromJson(json))
        .toList();
  }

  Future<MonthlySettlementMember> createMonthlySettlementMember(MonthlySettlementMember member) async {
    final response = await _client
        .from('monthly_settlement_members')
        .insert(member.toJson())
        .select()
        .single();
    
    return MonthlySettlementMember.fromJson(response);
  }

  Future<MonthlySettlementMember> updateMonthlySettlementMember(MonthlySettlementMember member) async {
    final response = await _client
        .from('monthly_settlement_members')
        .update(member.toJson())
        .eq('id', member.id)
        .select()
        .single();
    
    return MonthlySettlementMember.fromJson(response);
  }

  Future<void> deleteMonthlySettlementMember(String id) async {
    await _client
        .from('monthly_settlement_members')
        .delete()
        .eq('id', id);
  }

  // Monthly summary methods
  Future<Map<String, dynamic>> getMonthlySummary(int year, int month) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0);
    
    final expenses = await getExpenses(startDate: startDate, endDate: endDate);
    final users = await getUsers();
    
    double totalAmount = 0;
    Map<String, double> userAmounts = {};
    Map<String, double> categoryAmounts = {};
    
    for (final expense in expenses) {
      totalAmount += expense.amount;
      
      // ユーザー別集計
      userAmounts[expense.userId] = (userAmounts[expense.userId] ?? 0) + expense.amount;
      
      // カテゴリ別集計
      if (expense.categoryId != null) {
        categoryAmounts[expense.categoryId!] = (categoryAmounts[expense.categoryId!] ?? 0) + expense.amount;
      }
    }
    
    // 支払い割合に基づく計算
    Map<String, double> userPayments = {};
    for (final user in users) {
      userPayments[user.id] = totalAmount * (user.paymentRatio / 100);
    }
    
    return {
      'totalAmount': totalAmount,
      'userAmounts': userAmounts,
      'userPayments': userPayments,
      'categoryAmounts': categoryAmounts,
      'expenses': expenses,
    };
  }
}
