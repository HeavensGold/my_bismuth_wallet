import 'dart:async';
import 'package:my_bismuth_wallet/network/model/response/individual_dex_prices_response.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

/// Data class for exchange rates from CoinGecko
class ExchangeRateData {
  final double usdToTarget;
  final double btcToTarget;
  final double bisBtcPrice;
  final double bisUsdPrice;
  final double bisTargetPrice;
  final String targetCurrency;
  final DateTime timestamp;

  ExchangeRateData({
    required this.usdToTarget,
    required this.btcToTarget,
    required this.bisBtcPrice,
    required this.bisUsdPrice,
    required this.bisTargetPrice,
    required this.targetCurrency,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Check if this exchange rate data is still valid (within cache duration)
  bool isValid(Duration cacheDuration) {
    return DateTime.now().difference(timestamp) < cacheDuration;
  }

  @override
  String toString() {
    return 'ExchangeRateData(1 USD = $usdToTarget $targetCurrency, 1 BTC = $btcToTarget $targetCurrency)';
  }
}

/// Data class for price information from a single source
class PriceData {
  final String sourceName;
  final String sourceId;
  final double btcPrice;
  final double localCurrencyPrice;
  final String currency;
  final double volume24h;
  final bool isActive;
  final DateTime timestamp;
  final DefaultDex? dexType;

  PriceData({
    required this.sourceName,
    required this.sourceId,
    required this.btcPrice,
    required this.localCurrencyPrice,
    required this.currency,
    this.volume24h = 0.0,
    this.isActive = true,
    DateTime? timestamp,
    this.dexType,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create PriceData from DexPriceData
  factory PriceData.fromDexPriceData(
    DexPriceData dexData,
    String currency,
    DefaultDex dexType,
  ) {
    return PriceData(
      sourceName: dexData.name,
      sourceId: dexType.toString().split('.').last.toLowerCase(),
      btcPrice: double.tryParse(dexData.btcPrice) ?? 0.0,
      localCurrencyPrice: double.tryParse(dexData.localCurrencyPrice) ?? 0.0,
      currency: currency,
      volume24h: dexData.volume24h,
      isActive: dexData.isActive,
      dexType: dexType,
    );
  }

  /// Create PriceData for aggregated source
  factory PriceData.aggregated({
    required double btcPrice,
    required double localCurrencyPrice,
    required String currency,
  }) {
    return PriceData(
      sourceName: 'CoinGecko Aggregated',
      sourceId: 'coingecko_aggregated',
      btcPrice: btcPrice,
      localCurrencyPrice: localCurrencyPrice,
      currency: currency,
      dexType: DefaultDex.AGGREGATED,
    );
  }

  /// Convert to DexPriceData for backward compatibility
  DexPriceData toDexPriceData() {
    return DexPriceData(
      name: sourceName,
      btcPrice: btcPrice.toString(),
      localCurrencyPrice: localCurrencyPrice.toString(),
      volume24h: volume24h,
      isActive: isActive,
    );
  }

  @override
  String toString() {
    return 'PriceData(source: $sourceName, btc: $btcPrice, local: $localCurrencyPrice $currency)';
  }
}

/// Abstract base class for all price sources
abstract class PriceSource {
  /// Fetch price data for the given currency
  Future<PriceData?> fetchPrice(String currency);

  /// Human-readable name of this price source
  String get sourceName;

  /// Unique identifier for this price source
  String get sourceId;

  /// Whether this price source is currently available
  bool get isAvailable;

  /// The DEX type this source represents (null for aggregated sources)
  DefaultDex? get dexType;

  /// Whether this source requires internet connectivity
  bool get requiresInternet => true;

  /// Priority of this source (lower numbers = higher priority)
  int get priority => 100;

  /// Cache duration for this source in minutes
  int get cacheDurationMinutes => 5;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PriceSource && other.sourceId == sourceId;
  }

  @override
  int get hashCode => sourceId.hashCode;

  @override
  String toString() => 'PriceSource($sourceId: $sourceName)';
}

/// Base class for price sources that provide error handling and logging
abstract class BasePriceSource extends PriceSource {
  @override
  Future<PriceData?> fetchPrice(String currency) async {
    try {
      if (!isAvailable) {
        return null;
      }
      return await fetchPriceImpl(currency);
    } catch (e) {
      print('Error fetching price from $sourceName: $e');
      return null;
    }
  }

  /// Implementation-specific price fetching logic
  /// Subclasses should override this method instead of fetchPrice
  Future<PriceData?> fetchPriceImpl(String currency);
}