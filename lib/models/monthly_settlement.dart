import 'package:freezed_annotation/freezed_annotation.dart';

part 'monthly_settlement.freezed.dart';
part 'monthly_settlement.g.dart';

enum SettlementStatus {
  @JsonValue('pending')
  pending, // 未確定（編集可能）
  @JsonValue('settled')
  settled, // 確定済み（編集不可）
  @JsonValue('cancelled')
  cancelled, // キャンセル済み
}

@freezed
class MonthlySettlement with _$MonthlySettlement {
  const factory MonthlySettlement({
    required String id,
    required String householdId,
    required DateTime settlementMonth,
    required int totalAmount,
    @Default(SettlementStatus.pending) SettlementStatus status,
    DateTime? settledAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _MonthlySettlement;

  factory MonthlySettlement.fromJson(Map<String, dynamic> json) =>
      _$MonthlySettlementFromJson(json);
}

@freezed
class MonthlySettlementMember with _$MonthlySettlementMember {
  const factory MonthlySettlementMember({
    required String id,
    required String monthlySettlementId,
    required String userId,
    required int paymentRatio,
    required int actualAmount,
    required int calculatedAmount,
    required int settlementAmount,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _MonthlySettlementMember;

  factory MonthlySettlementMember.fromJson(Map<String, dynamic> json) =>
      _$MonthlySettlementMemberFromJson(json);
}
