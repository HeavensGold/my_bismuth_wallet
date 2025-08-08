

class SimplePriceResponse {
  SimplePriceResponse({
    required this.currency,
    required this.btcPrice,
    required this.localCurrencyPrice,
  });

  String currency;
  double btcPrice;
  double localCurrencyPrice;
}
