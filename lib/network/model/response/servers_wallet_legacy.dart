// To parse this JSON data, do
//
//     final serverWalletLegacyResponse = serverWalletLegacyResponseFromJson(jsonString);

// Dart imports:
import 'dart:convert';

List<ServerWalletLegacyResponse> serverWalletLegacyResponseFromJson(
        String str) =>
    List<ServerWalletLegacyResponse>.from(
        json.decode(str).map((x) => ServerWalletLegacyResponse.fromJson(x)));

String serverWalletLegacyResponseToJson(
        List<ServerWalletLegacyResponse> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class ServerWalletLegacyResponse {
  ServerWalletLegacyResponse({
    required this.label,
    required this.ip,
    required this.port,
    required this.country,
    required this.height,
    required this.version,
    required this.active,
    required this.clients,
    required this.totalSlots,
    required this.lastActive,
  });

  String label;
  String ip;
  int port;
  String country;
  int height;
  String version;
  bool active;
  int clients;
  int totalSlots;
  int lastActive;

  factory ServerWalletLegacyResponse.fromJson(Map<String, dynamic> json) =>
      ServerWalletLegacyResponse(
        label: json['label'] ?? '',
        ip: json['ip'] ?? '',
        port: json['port'] ?? 0,
        country: json['country'] ?? '',
        height: json['height'] ?? 0,
        version: json['version'] ?? '',
        active: json['active'] ?? false,
        clients: json['clients'] ?? 0,
        totalSlots: json['total_slots'] ?? 0,
        lastActive: json['last_active'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'ip': ip,
        'port': port,
        'country': country,
        'height': height,
        'version': version,
        'active': active,
        'clients': clients,
        'total_slots': totalSlots,
        'last_active': lastActive,
      };
}
