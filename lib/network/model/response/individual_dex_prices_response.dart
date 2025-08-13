import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

/// Response model for individual DEX prices with aggregated fallback
class IndividualDexPricesResponse {
  final Map<DefaultDex, DexPriceData> dexPrices;
  final String aggregatedBtcPrice;
  final String aggregatedLocalPrice;

  IndividualDexPricesResponse({
    required this.dexPrices,
    required this.aggregatedBtcPrice,
    required this.aggregatedLocalPrice,
  });

  factory IndividualDexPricesResponse.fromJson(Map<String, dynamic> json) {
    Map<DefaultDex, DexPriceData> dexPricesMap = {};

    // Parse individual DEX data if available
    if (json['dex_prices'] != null) {
      Map<String, dynamic> dexData = json['dex_prices'];

      // Parse Uniswap V2 data
      if (dexData['uniswap_v2'] != null) {
        dexPricesMap[DefaultDex.UNISWAP_V2] =
            DexPriceData.fromJson(dexData['uniswap_v2']);
      }

      // Parse PancakeSwap data
      if (dexData['pancakeswap'] != null) {
        dexPricesMap[DefaultDex.PANCAKESWAP] =
            DexPriceData.fromJson(dexData['pancakeswap']);
      }
    }

    return IndividualDexPricesResponse(
      dexPrices: dexPricesMap,
      aggregatedBtcPrice: json['aggregated_btc_price']?.toString() ?? '0',
      aggregatedLocalPrice: json['aggregated_local_price']?.toString() ?? '0',
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> dexData = {};

    dexPrices.forEach((dex, data) {
      String key;
      switch (dex) {
        case DefaultDex.UNISWAP_V2:
          key = 'uniswap_v2';
          break;
        case DefaultDex.PANCAKESWAP:
          key = 'pancakeswap';
          break;
        case DefaultDex.AGGREGATED:
          key = 'aggregated';
          break;
      }
      dexData[key] = data.toJson();
    });

    return {
      'dex_prices': dexData,
      'aggregated_btc_price': aggregatedBtcPrice,
      'aggregated_local_price': aggregatedLocalPrice,
    };
  }
}

/// Individual DEX price data
class DexPriceData {
  final String name;
  final String btcPrice;
  final String localCurrencyPrice;
  final double volume24h;
  final bool isActive;

  DexPriceData({
    required this.name,
    required this.btcPrice,
    required this.localCurrencyPrice,
    required this.volume24h,
    required this.isActive,
  });

  factory DexPriceData.fromJson(Map<String, dynamic> json) {
    return DexPriceData(
      name: json['name']?.toString() ?? '',
      btcPrice: json['btc_price']?.toString() ?? '0',
      localCurrencyPrice: json['local_currency_price']?.toString() ?? '0',
      volume24h: (json['volume_24h'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'btc_price': btcPrice,
      'local_currency_price': localCurrencyPrice,
      'volume_24h': volume24h,
      'is_active': isActive,
    };
  }

  /// Create a DEX price data from GeckoTerminal pool data
  factory DexPriceData.fromGeckoTerminalPool(
      Map<String, dynamic> poolData, String dexName) {
    final attributes = poolData['attributes'];
    if (attributes == null) {
      return DexPriceData(
        name: dexName,
        btcPrice: '0',
        localCurrencyPrice: '0',
        volume24h: 0.0,
        isActive: false,
      );
    }

    // Parse volume - it's a string in the API response
    double volume24h = 0.0;
    if (attributes['volume_usd'] != null &&
        attributes['volume_usd']['h24'] != null) {
      var volumeStr = attributes['volume_usd']['h24'].toString();
      volume24h = double.tryParse(volumeStr) ?? 0.0;
    }

    // Get USD price from base_token_price_usd
    String usdPrice = attributes['base_token_price_usd']?.toString() ?? '0';

    // Calculate BTC price (approximately - we'll need to get actual BTC price)
    // For now, we'll use a rough estimate (1 BTC ≈ $45000)
    double usdPriceNum = double.tryParse(usdPrice) ?? 0.0;
    double btcPriceNum = usdPriceNum /
        45000.0; // This will be updated with actual BTC price later
    String btcPrice = btcPriceNum.toStringAsFixed(10);

    return DexPriceData(
      name: dexName,
      btcPrice: btcPrice,
      localCurrencyPrice: usdPrice,
      volume24h: volume24h,
      isActive: true,
    );
  }
}
