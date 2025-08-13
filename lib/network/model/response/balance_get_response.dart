// To parse this JSON data, do
//
//     final balanceGetResponse = balanceGetResponseFromJson(jsonString);

// Dart imports:
import 'dart:convert';

BalanceGetResponse balanceGetResponseFromJson(String str) =>
    BalanceGetResponse.fromJson(json.decode(str));

String balanceGetResponseToJson(BalanceGetResponse data) =>
    json.encode(data.toJson());

class BalanceGetResponse {
  BalanceGetResponse({
    required this.address,
    required this.balance,
    required this.totalCredits,
    required this.totalDebits,
    required this.totalFees,
    required this.totalRewards,
    required this.balanceNoMempool,
  });

  String address;
  String balance;
  String totalCredits;
  String totalDebits;
  String totalFees;
  String totalRewards;
  String balanceNoMempool;

  factory BalanceGetResponse.fromJson(Map<String, dynamic> json) =>
      BalanceGetResponse(
        address: json['address'] ?? '',
        balance: json['balance'] ?? '',
        totalCredits: json['total_credits'] ?? '',
        totalDebits: json['total_debits'] ?? '',
        totalFees: json['total_fees'] ?? '',
        totalRewards: json['total_rewards'] ?? '',
        balanceNoMempool: json['balance_no_mempool'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'balance': balance,
        'total_credits': totalCredits,
        'total_debits': totalDebits,
        'total_fees': totalFees,
        'total_rewards': totalRewards,
        'balance_no_mempool': balanceNoMempool,
      };
}
