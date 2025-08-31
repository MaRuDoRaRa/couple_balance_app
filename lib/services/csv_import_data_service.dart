import '../models/financial_institution.dart';
import '../models/expense.dart';
import '../models/category.dart';
import '../models/csv_import_pattern.dart';
import 'supabase_service.dart';

class CsvImportDataService {
  final SupabaseService _supabaseService = SupabaseService();

  /// 1. ユーザーが選択可能な金融機関リストを取得
  Future<List<FinancialInstitution>> getAvailableFinancialInstitutions() async {
    try {
      return await _supabaseService.getFinancialInstitutions();
    } catch (e) {
      print('金融機関リスト取得エラー: $e');
      return [];
    }
  }

  /// 2. ユーザーが選択した金融機関で過去に支出としてインポートされた情報を取得
  Future<List<Expense>> getPastExpensesByInstitution(
    String userId, 
    String financialInstitutionId,
    {int limit = 100}
  ) async {
    try {
      final response = await _supabaseService.client
          .from('expenses')
          .select('''
            *,
            category:categories(*),
            user:users(nickname)
          ''')
          .eq('user_id', userId)
          .order('expense_date', ascending: false)
          .limit(limit);

      return (response as List).map((json) {
        // ユーザー名を追加
        final userData = json['user'] as Map<String, dynamic>?;
        json['user_name'] = userData?['nickname'];
        return Expense.fromJson(json);
      }).toList();
    } catch (e) {
      print('過去の支出取得エラー: $e');
      return [];
    }
  }

  /// 3. 金融機関別の支出統計を取得
  Future<Map<String, dynamic>> getExpenseStatsByInstitution(
    String userId, 
    String financialInstitutionId
  ) async {
    try {
      final expenses = await getPastExpensesByInstitution(userId, financialInstitutionId);
      
      double totalAmount = 0;
      Map<String, double> categoryAmounts = {};
      Map<String, int> categoryCounts = {};
      
      for (final expense in expenses) {
        totalAmount += expense.amount;
        
        if (expense.categoryId != null) {
          final categoryName = expense.category?.name ?? '未分類';
          categoryAmounts[categoryName] = (categoryAmounts[categoryName] ?? 0) + expense.amount;
          categoryCounts[categoryName] = (categoryCounts[categoryName] ?? 0) + 1;
        }
      }
      
      return {
        'totalExpenses': expenses.length,
        'totalAmount': totalAmount,
        'categoryAmounts': categoryAmounts,
        'categoryCounts': categoryCounts,
        'averageAmount': expenses.isNotEmpty ? totalAmount / expenses.length : 0,
      };
    } catch (e) {
      print('支出統計取得エラー: $e');
      return {
        'totalExpenses': 0,
        'totalAmount': 0,
        'categoryAmounts': {},
        'categoryCounts': {},
        'averageAmount': 0,
      };
    }
  }

  /// 4. 金融機関別の店舗パターンを取得
  Future<Map<String, List<String>>> getMerchantPatternsByInstitution(
    String userId, 
    String financialInstitutionId
  ) async {
    try {
      final expenses = await getPastExpensesByInstitution(userId, financialInstitutionId);
      
      Map<String, List<String>> merchantPatterns = {};
      
      for (final expense in expenses) {
        final merchantName = _extractMerchantName(expense.description);
        final categoryName = expense.category?.name ?? '未分類';
        
        if (!merchantPatterns.containsKey(merchantName)) {
          merchantPatterns[merchantName] = [];
        }
        
        if (!merchantPatterns[merchantName]!.contains(categoryName)) {
          merchantPatterns[merchantName]!.add(categoryName);
        }
      }
      
      return merchantPatterns;
    } catch (e) {
      print('店舗パターン取得エラー: $e');
      return {};
    }
  }

  /// 5. カテゴリ一覧を取得
  Future<List<Category>> getCategories() async {
    try {
      return await _supabaseService.getCategories();
    } catch (e) {
      print('カテゴリ取得エラー: $e');
      return [];
    }
  }

  /// 店舗名を抽出（CSVの説明文から）
  String _extractMerchantName(String description) {
    // 基本的な店舗名抽出ロジック
    final commonMerchants = [
      'セブンイレブン', 'イオン', 'ローソン', 'ファミマ', 'ミニストップ',
      'マクドナルド', 'スターバックス', 'ドトール', 'タリーズ',
      'ユニクロ', 'GU', 'ZARA', 'H&M',
      'Amazon', '楽天', 'Yahoo!ショッピング'
    ];

    for (final merchant in commonMerchants) {
      if (description.contains(merchant)) {
        return merchant;
      }
    }

    // 店舗名が見つからない場合は説明文の最初の部分を使用
    return description.split(' ').first;
  }

  /// 6. CSVインポートパターンを取得
  Future<List<CsvImportPattern>> getCsvImportPatterns(String userId, String financialInstitutionId) async {
    try {
      return await _supabaseService.getCsvImportPatterns(userId, financialInstitutionId);
    } catch (e) {
      print('CSVインポートパターン取得エラー: $e');
      return [];
    }
  }
}
