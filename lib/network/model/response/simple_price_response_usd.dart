// To parse this JSON data, do
//
//     final simplePriceUsdResponse = simplePriceUsdResponseFromJson(jsonString);

// Dart imports:
import 'dart:convert';

SimplePriceUsdResponse simplePriceUsdResponseFromJson(String str) =>
    SimplePriceUsdResponse.fromJson(json.decode(str));

String simplePriceUsdResponseToJson(SimplePriceUsdResponse data) =>
    json.encode(data.toJson());

class SimplePriceUsdResponse {
  SimplePriceUsdResponse({
    required this.bismuth,
  });

  Bismuth bismuth;

  factory SimplePriceUsdResponse.fromJson(Map<String, dynamic> json) =>
      SimplePriceUsdResponse(
        bismuth: Bismuth.fromJson(json['bismuth'] ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'bismuth': bismuth.toJson(),
      };
}

class Bismuth {
  Bismuth({
    required this.usd,
  });

  double usd;

  factory Bismuth.fromJson(Map<String, dynamic> json) => Bismuth(
        usd: (json["usd"] ?? 0.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "usd": usd,
      };
}
