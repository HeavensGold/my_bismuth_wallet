// To parse this JSON data, do
//
//     final simplePriceEurResponse = simplePriceEurResponseFromJson(jsonString);


// Dart imports:
import 'dart:convert';

SimplePriceEurResponse simplePriceEurResponseFromJson(String str) =>
    SimplePriceEurResponse.fromJson(json.decode(str));

String simplePriceEurResponseToJson(SimplePriceEurResponse data) =>
    json.encode(data.toJson());

class SimplePriceEurResponse {
  SimplePriceEurResponse({
    required this.bismuth,
  });

  Bismuth bismuth;

  factory SimplePriceEurResponse.fromJson(Map<String, dynamic> json) =>
      SimplePriceEurResponse(
        bismuth: Bismuth.fromJson(json['bismuth'] ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'bismuth': bismuth.toJson(),
      };
}

class Bismuth {
  Bismuth({
    required this.eur,
  });

  double eur;

  factory Bismuth.fromJson(Map<String, dynamic> json) => Bismuth(
        eur: (json["eur"] ?? 0.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "eur": eur,
      };
}
