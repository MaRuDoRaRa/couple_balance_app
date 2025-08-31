import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import '../models/expense.dart';

import 'supabase_service.dart';
import '../models/csv_import_pattern.dart';

// 金融機関の定義はfinancial_institutionsテーブルから取得

class CsvImportService {
  final SupabaseService _supabaseService = SupabaseService();

  Future<List<Expense>> parseCsvFile(
    File file,
    FinancialInstitution institution,
    String userId,
  ) async {
    try {
      final csvString = await file.readAsString();
      final csvTable = const CsvToListConverter().convert(csvString);
      
      List<Expense> expenses = [];
      
      switch (institution.code) {
        case 'risona_bank':
          expenses = _parseRisonaBank(csvTable, userId);
          break;
        case 'jre_bank':
          expenses = _parseJreBank(csvTable, userId);
          break;
        case 'rakuten_bank':
          expenses = _parseRakutenBank(csvTable, userId);
          break;
        case 'jre_view_card':
          expenses = _parseJreViewCard(csvTable, userId);
          break;
        case 'rakuten_card':
          expenses = _parseRakutenCard(csvTable, userId);
          break;
        default:
          throw Exception('サポートされていない金融機関です: ${institution.name}');
      }
      
      return expenses;
    } catch (e) {
      throw Exception('CSVファイルの解析に失敗しました: $e');
    }
  }

  List<Expense> _parseRisonaBank(List<List<dynamic>> csvTable, String userId) {
    List<Expense> expenses = [];
    
    // ヘッダー行をスキップ
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.length < 6) continue;
      
      try {
        final dateStr = row[0].toString();
        final description = row[1].toString();
        final amountStr = row[2].toString().replaceAll(',', '');
        final balanceStr = row[3].toString().replaceAll(',', '');
        
        // 支出のみを処理（マイナス値）
        final amount = double.tryParse(amountStr);
        if (amount == null || amount >= 0) continue;
        
        final date = DateTime.parse(dateStr);
        
        expenses.add(Expense(
          id: '', // Supabaseで自動生成
          householdId: '', // 後で設定
          userId: userId,
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

  List<Expense> _parseJreBank(List<List<dynamic>> csvTable, String userId) {
    List<Expense> expenses = [];
    
    // JRE BankのCSVフォーマットに応じて実装
    // 実際のフォーマットに合わせて調整が必要
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.length < 4) continue;
      
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
          userId: userId,
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

  List<Expense> _parseRakutenBank(List<List<dynamic>> csvTable, String userId) {
    List<Expense> expenses = [];
    
    // 楽天銀行のCSVフォーマットに応じて実装
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.length < 5) continue;
      
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
          userId: userId,
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

  List<Expense> _parseJreViewCard(List<List<dynamic>> csvTable, String userId) {
    List<Expense> expenses = [];
    
    // JRE ViewカードのCSVフォーマットに応じて実装
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.length < 4) continue;
      
      try {
        final dateStr = row[0].toString();
        final description = row[1].toString();
        final amountStr = row[2].toString().replaceAll(',', '');
        
        final amount = double.tryParse(amountStr);
        if (amount == null || amount <= 0) continue;
        
        final date = DateTime.parse(dateStr);
        
        expenses.add(Expense(
          id: '',
          householdId: '', // 後で設定
          userId: userId,
          amount: amount,
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

  List<Expense> _parseRakutenCard(List<List<dynamic>> csvTable, String userId) {
    List<Expense> expenses = [];
    
    // 楽天カードのCSVフォーマットに応じて実装
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.length < 4) continue;
      
      try {
        final dateStr = row[0].toString();
        final description = row[1].toString();
        final amountStr = row[2].toString().replaceAll(',', '');
        
        final amount = double.tryParse(amountStr);
        if (amount == null || amount <= 0) continue;
        
        final date = DateTime.parse(dateStr);
        
        expenses.add(Expense(
          id: '',
          householdId: '', // 後で設定
          userId: userId,
          amount: amount,
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

  Future<Map<String, dynamic>> importExpenses(
    String householdId,
    List<Expense> expenses,
    List<String> originalDescriptions,
    FinancialInstitution institution,
  ) async {
    try {
      final currentUser = await _supabaseService.getCurrentUser();
      
      // 自動分類を実行
      final classifiedExpenses = await _classifyExpenses(
        expenses,
        currentUser.id,
        institution.id,
      );
      
      // 支出データをJSONB形式に変換
      final expensesJson = classifiedExpenses.map((expense) => {
        'sub_category_id': expense.subCategoryId,
        'financial_institution_id': institution.id,
        'amount': expense.amount.toString(),
        'description': expense.description,
        'expense_date': expense.expenseDate.toIso8601String().split('T')[0],
        'is_valid': true,
      }).toList();
      
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
        // パターンを学習
        await _learnPatterns(
          currentUser.id,
          institution.id,
          classifiedExpenses,
          originalDescriptions,
        );
        
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


}
