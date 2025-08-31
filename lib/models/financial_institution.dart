enum InstitutionType {
  bank,
  creditCard,
}

class FinancialInstitution {
  final String id;
  final String code;
  final String name;
  final InstitutionType type;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  FinancialInstitution({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FinancialInstitution.fromJson(Map<String, dynamic> json) {
    return FinancialInstitution(
      id: json['id'],
      code: json['code'],
      name: json['name'],
      type: InstitutionType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'type': type.toString().split('.').last,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  FinancialInstitution copyWith({
    String? id,
    String? code,
    String? name,
    InstitutionType? type,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FinancialInstitution(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
