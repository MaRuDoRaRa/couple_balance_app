import 'sub_category.dart';
import 'financial_institution.dart';

class Expense {
  final String id;
  final String householdId;
  final String userId;
  final String? subCategoryId;
  final String? financialInstitutionId;
  final double amount;
  final String description;
  final DateTime expenseDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  final SubCategory? subCategory;
  final FinancialInstitution? financialInstitution;
  final String? userName; // 追加：ユーザー名を表示用
  final String? userColor; // 追加：ユーザーカラーを表示用

  Expense({
    required this.id,
    required this.householdId,
    required this.userId,
    this.subCategoryId,
    this.financialInstitutionId,
    required this.amount,
    required this.description,
    required this.expenseDate,
    required this.createdAt,
    required this.updatedAt,

    this.subCategory,
    this.financialInstitution,
    this.userName,
    this.userColor,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      householdId: json['household_id'],
      userId: json['user_id'],
      subCategoryId: json['sub_category_id'],
      financialInstitutionId: json['financial_institution_id'],
      amount: (json['amount'] as num).toDouble(),
      description: json['description'],
      expenseDate: DateTime.parse(json['expense_date']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),

      subCategory: json['sub_category'] != null ? SubCategory.fromJson(json['sub_category']) : null,
      financialInstitution: json['financial_institution'] != null ? FinancialInstitution.fromJson(json['financial_institution']) : null,
      userName: json['user_name'],
      userColor: json['user_color'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'sub_category_id': subCategoryId,
      'financial_institution_id': financialInstitutionId,
      'amount': amount,
      'description': description,
      'expense_date': expenseDate.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Expense copyWith({
    String? id,
    String? householdId,
    String? userId,
    String? subCategoryId,
    String? financialInstitutionId,
    double? amount,
    String? description,
    DateTime? expenseDate,
    DateTime? createdAt,
    DateTime? updatedAt,

    SubCategory? subCategory,
    FinancialInstitution? financialInstitution,
    String? userName,
    String? userColor,
  }) {
    return Expense(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      userId: userId ?? this.userId,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      financialInstitutionId: financialInstitutionId ?? this.financialInstitutionId,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      expenseDate: expenseDate ?? this.expenseDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,

      subCategory: subCategory ?? this.subCategory,
      financialInstitution: financialInstitution ?? this.financialInstitution,
      userName: userName ?? this.userName,
      userColor: userColor ?? this.userColor,
    );
  }
}
