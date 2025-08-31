import 'category.dart';
import 'sub_category.dart';

class CsvImportPattern {
  final String id;
  final String householdId;
  final String userId;
  final String financialInstitutionId;
  final String? subCategoryId;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Category? category;
  final SubCategory? subCategory;

  CsvImportPattern({
    required this.id,
    required this.householdId,
    required this.userId,
    required this.financialInstitutionId,
    this.subCategoryId,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.subCategory,
  });

  factory CsvImportPattern.fromJson(Map<String, dynamic> json) {
    return CsvImportPattern(
      id: json['id'],
      householdId: json['household_id'],
      userId: json['user_id'],
      financialInstitutionId: json['financial_institution_id'],
      subCategoryId: json['sub_category_id'],
      description: json['description'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      category: json['category'] != null ? Category.fromJson(json['category']) : null,
      subCategory: json['sub_category'] != null ? SubCategory.fromJson(json['sub_category']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'financial_institution_id': financialInstitutionId,
      'sub_category_id': subCategoryId,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CsvImportPattern copyWith({
    String? id,
    String? householdId,
    String? userId,
    String? financialInstitutionId,
    String? subCategoryId,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    Category? category,
    SubCategory? subCategory,
  }) {
    return CsvImportPattern(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      userId: userId ?? this.userId,
      financialInstitutionId: financialInstitutionId ?? this.financialInstitutionId,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
    );
  }
}
