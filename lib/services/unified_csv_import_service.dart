import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import '../models/expense.dart';
import '../models/financial_institution.dart';
import '../models/csv_import_pattern.dart';
import 'supabase_service.dart';
import 'permission_service.dart';

/// 統合CSVインポートサービス
/// 金融機関CSVインポートと手動CSVインポートを統一されたフローで処理
class UnifiedCsvImportService {
  final SupabaseService _supabaseService = SupabaseService();
  final PermissionService _permissionService = PermissionService();

  /// CSVファイルを解析（金融機関CSV）
  Future<List<Expense>> parseFinancialInstitutionCsv(
    File file,
    FinancialInstitution institution,
  ) async {
    try {
      final csvString = await file.readAsString();
      final csvTable = const CsvToListConverter().convert(csvString);
      
      List<Expense> expenses = [];
      
      switch (institution.code) {
        case 'risona_bank':
          expenses = _parseRisonaBank(csvTable);
          break;
        case 'jre_bank':
          expenses = _parseJreBank(csvTable);
          break;
        case 'rakuten_bank':
          expenses = _parseRakutenBank(csvTable);
          break;
        case 'jre_view_card':
          expenses = _parseJreViewCard(csvTable);
          break;
        case 'rakuten_card':
          expenses = _parseRakutenCard(csvTable);
          break;
        default:
          throw Exception('サポートされていない金融機関です: ${institution.name}');
      }
      
      return expenses;
    } catch (e) {
      throw Exception('CSVファイルの解析に失敗しました: $e');
    }
  }

  /// CSVファイルを解析（手動CSV）
  Future<List<Map<String, dynamic>>> parseManualCsv(File csvFile) async {
    try {
      final csvString = await csvFile.readAsString();
      final lines = const LineSplitter().convert(csvString);
      
      if (lines.length < 2) {
        throw Exception('CSVファイルにデータが含まれていません');
      }
      
      final headers = lines[0].split(',');
      final dataLines = lines.skip(1).toList();
      
      // ヘッダーの検証
      _validateHeaders(headers);
      
      // データ行を解析
      final details = <Map<String, dynamic>>[];
      for (int i = 0; i < dataLines.length; i++) {
        final line = dataLines[i];
        final rowNumber = i + 2; // ヘッダー行を除いて1から開始
        
        try {
          final values = _parseCsvLine(line);
          final detail = _createImportDetail(rowNumber, headers, values);
          details.add(detail);
        } catch (e) {
          // エラーが発生した場合は無効なレコードとして作成
          details.add({
            'row_number': rowNumber,
            'is_valid': false,
            'error_message': e.toString(),
          });
        }
      }
      
      return details;
    } catch (e) {
      throw Exception('CSVファイルの解析に失敗しました: $e');
    }
  }

  /// 支出として一括登録（統合方式）
  Future<Map<String, dynamic>> importExpenses(
    String householdId,
    List<dynamic> expenses, // Expense または Map<String, dynamic>
  ) async {
    try {
      // 権限チェック
      await _permissionService.hasPermission(householdId, 'expense.create');
      
      final currentUser = await _supabaseService.getCurrentUser();
      
      List<Map<String, dynamic>> expensesJson;
      
      if (institution != null) {
        // 金融機関CSVの場合
        final expenseList = expenses as List<Expense>;
        final classifiedExpenses = await _classifyExpenses(
          expenseList,
          currentUser.id,
          institution.id,
        );
        
        expensesJson = classifiedExpenses.map((expense) => {
          'sub_category_id': expense.subCategoryId,
          'financial_institution_id': institution.id,
          'amount': expense.amount.toString(),
          'description': expense.description,
          'expense_date': expense.expenseDate.toIso8601String().split('T')[0],
          'is_valid': true,
        }).toList();
             } else {
         // 手動CSVの場合
         final detailList = expenses as List<Map<String, dynamic>>;
         final validDetails = detailList.where((d) => d['is_valid'] == true).toList();
         
         if (validDetails.isEmpty) {
           return {
             'success': false,
             'success_count': 0,
             'error_count': detailList.length,
             'error_messages': ['有効なデータがありません'],
           };
         }
         
         expensesJson = validDetails.map((detail) => {
           'sub_category_id': detail['sub_category_id'],
           'financial_institution_id': null, // 手動入力のためnull
           'amount': detail['amount'].toString(),
           'description': detail['description'],
           'expense_date': detail['expense_date'],
           'is_valid': true,
         }).toList();
       }
      
      // 一括インポート関数を呼び出し
      final result = await _supabaseService.client.rpc(
        'bulk_import_expenses',
        params: {
          'p_household_id': householdId,
          'p_user_id': currentUser.id,
          'p_expenses': expensesJson,
        },
      );
      
      final resultMap = Map<String, dynamic>.from(result);
      
      if (resultMap['success'] == true) {
        // 金融機関CSVの場合はパターンを学習
        if (institution != null) {
          final expenseList = expenses as List<Expense>;
          await _learnPatterns(
            currentUser.id,
            institution.id,
            expenseList,
            expenseList.map((e) => e.description).toList(),
          );
        }
        
        return {
          'success': true,
          'success_count': resultMap['success_count'],
          'error_count': resultMap['error_count'],
          'error_messages': List<String>.from(resultMap['error_messages'] ?? []),
        };
      } else {
        return {
          'success': false,
          'success_count': 0,
          'error_count': expenses.length,
          'error_messages': List<String>.from(resultMap['error_messages'] ?? []),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'success_count': 0,
        'error_count': expenses.length,
        'error_messages': [e.toString()],
      };
    }
  }

  // 以下、金融機関CSV解析メソッド（既存のCsvImportServiceから移植）
  List<Expense> _parseRisonaBank(List<List<dynamic>> csvTable) {
    List<Expense> expenses = [];
    
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.length < 6) continue;
      
      try {
        final dateStr = row[0].toString();
        final description = row[1].toString();
        final amountStr = row[2].toString().replaceAll(',', '');
        
        final amount = double.tryParse(amountStr);
        if (amount == null || amount >= 0) continue;
        
        final date = DateTime.parse(dateStr);
        
        expenses.add(Expense(
          id: '',
          householdId: '', // 後で設定
          userId: '', // 後で設定
          amount: amount.abs(),
          description: description,
          expenseDate: date,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      } catch (e) {
        print('行 $i の解析に失敗: $e');
        continue;
      }
    }
    
    return expenses;
  }

  List<Expense> _parseJreBank(List<List<dynamic>> csvTable) {
    // JRE Bankの実装
    return _parseRisonaBank(csvTable); // 簡略化
  }

  List<Expense> _parseRakutenBank(List<List<dynamic>> csvTable) {
    // 楽天銀行の実装
    return _parseRisonaBank(csvTable); // 簡略化
  }

  List<Expense> _parseJreViewCard(List<List<dynamic>> csvTable) {
    // JRE Viewカードの実装
    return _parseRisonaBank(csvTable); // 簡略化
  }

  List<Expense> _parseRakutenCard(List<List<dynamic>> csvTable) {
    // 楽天カードの実装
    return _parseRisonaBank(csvTable); // 簡略化
  }

  // 以下、手動CSV解析メソッド（既存のManualCsvImportServiceから移植）
  void _validateHeaders(List<String> headers) {
    final requiredHeaders = ['amount', 'description', 'date'];
    final missingHeaders = requiredHeaders.where(
      (header) => !headers.any((h) => h.trim().toLowerCase() == header.toLowerCase())
    ).toList();
    
    if (missingHeaders.isNotEmpty) {
      throw Exception('必須ヘッダーが不足しています: ${missingHeaders.join(', ')}');
    }
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final chars = line.split('');
    String current = '';
    bool inQuotes = false;
    
    for (int i = 0; i < chars.length; i++) {
      final char = chars[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.trim());
        current = '';
      } else {
        current += char;
      }
    }
    
    result.add(current.trim());
    return result;
  }

  Map<String, dynamic> _createImportDetail(
    int rowNumber,
    List<String> headers,
    List<String> values,
  ) {
    if (values.length != headers.length) {
      throw Exception('ヘッダーとデータの列数が一致しません');
    }
    
    final data = <String, String>{};
    for (int i = 0; i < headers.length; i++) {
      data[headers[i].trim().toLowerCase()] = values[i].trim();
    }
    
    // 金額の解析
    int? amount;
    try {
      final amountStr = data['amount']?.replaceAll(RegExp(r'[^\d]'), '');
      if (amountStr != null && amountStr.isNotEmpty) {
        amount = int.parse(amountStr);
      }
    } catch (e) {
      throw Exception('金額の形式が正しくありません: ${data['amount']}');
    }
    
    // 日付の解析
    DateTime? expenseDate;
    try {
      final dateStr = data['date'];
      if (dateStr != null && dateStr.isNotEmpty) {
        if (dateStr.contains('/')) {
          final parts = dateStr.split('/');
          if (parts.length == 3) {
            expenseDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        } else if (dateStr.contains('-')) {
          expenseDate = DateTime.parse(dateStr);
        }
      }
    } catch (e) {
      throw Exception('日付の形式が正しくありません: ${data['date']}');
    }
    
    // 説明の検証
    final description = data['description'];
    if (description == null || description.isEmpty) {
      throw Exception('説明が入力されていません');
    }
    
    return {
      'row_number': rowNumber,
      'amount': amount,
      'description': description,
      'expense_date': expenseDate?.toIso8601String().split('T')[0],
      'is_valid': true,
    };
  }

  /// 支出の自動分類を実行
  Future<List<Expense>> _classifyExpenses(
    List<Expense> expenses,
    String userId,
    String financialInstitutionId,
  ) async {
    final classifiedExpenses = <Expense>[];
    
    for (final expense in expenses) {
      try {
        // 過去のパターンを取得
        final patterns = await _supabaseService.getCsvImportPatterns(userId, financialInstitutionId);
        
        String? predictedSubCategoryId;
        
        // 説明文が一致するパターンを検索
        for (final pattern in patterns) {
          if (expense.description.contains(pattern.description) || 
              pattern.description.contains(expense.description)) {
            predictedSubCategoryId = pattern.subCategoryId;
            break;
          }
        }
        
        // 分類された支出を作成
        final classifiedExpense = expense.copyWith(
          subCategoryId: predictedSubCategoryId,
        );
        
        classifiedExpenses.add(classifiedExpense);
      } catch (e) {
        print('自動分類エラー: $e');
        classifiedExpenses.add(expense); // 分類に失敗した場合は元の支出を使用
      }
    }
    
    return classifiedExpenses;
  }

  /// インポートパターンを学習・更新
  Future<void> _learnPatterns(
    String userId,
    String financialInstitutionId,
    List<Expense> expenses,
    List<String> originalDescriptions,
  ) async {
    try {
      for (int i = 0; i < expenses.length; i++) {
        final expense = expenses[i];
        final originalDescription = originalDescriptions[i];
        
        if (expense.subCategoryId != null) {
          // 新しいパターンを作成
          final pattern = CsvImportPattern(
            id: '',
            userId: userId,
            financialInstitutionId: financialInstitutionId,
            subCategoryId: expense.subCategoryId,
            description: originalDescription,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _supabaseService.createCsvImportPattern(pattern);
        }
      }
    } catch (e) {
      print('パターン学習エラー: $e');
    }
  }

  /// CSVテンプレートを生成
  String generateCsvTemplate() {
    return '''amount,description,date,category
1000,食費,2024/01/15,食料品
500,交通費,2024/01/16,電車・バス
2000,外食,2024/01/17,外食''';
  }
}
