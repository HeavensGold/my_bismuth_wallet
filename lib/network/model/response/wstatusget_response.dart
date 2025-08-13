// To parse this JSON data, do
//
//     final wStatusGetResponse = wStatusGetResponseFromJson(jsonString);

// Dart imports:
import 'dart:convert';

WStatusGetResponse wStatusGetResponseFromJson(String str) =>
    WStatusGetResponse.fromJson(json.decode(str));

String wStatusGetResponseToJson(WStatusGetResponse data) =>
    json.encode(data.toJson());

class WStatusGetResponse {
  WStatusGetResponse({
    required this.version,
    required this.clients,
    required this.maxClients,
    required this.of,
    required this.fd,
    required this.co,
  });

  String version;
  int clients;
  int maxClients;
  int of;
  int fd;
  int co;

  factory WStatusGetResponse.fromJson(Map<String, dynamic> json) =>
      WStatusGetResponse(
        version: json['version'] ?? '',
        clients: json['clients'] ?? 0,
        maxClients: json['max_clients'] ?? 0,
        of: json['of'] ?? 0,
        fd: json['fd'] ?? 0,
        co: json['co'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'clients': clients,
        'max_clients': maxClients,
        'of': of,
        'fd': fd,
        'co': co,
      };
}
