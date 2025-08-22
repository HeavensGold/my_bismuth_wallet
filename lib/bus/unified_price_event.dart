import 'package:event_taxi/event_taxi.dart';
import 'package:my_bismuth_wallet/service/price_sources/price_source.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

/// Event fired when unified price data is updated from all sources
class UnifiedPriceUpdateEvent implements Event {
  /// Map of all price data by source ID
  final Map<String, PriceData> allPrices;
  
  /// Current selected price source data
  final PriceData? selectedPrice;
  
  /// Currently selected DEX/source
  final DefaultDex selectedDex;
  
  /// Currency for which prices were fetched
  final String currency;
  
  /// Timestamp when this update occurred
  final DateTime timestamp;
  
  /// Whether this update was successful
  final bool isSuccess;
  
  /// Error message if update failed
  final String? errorMessage;

  UnifiedPriceUpdateEvent({
    required this.allPrices,
    required this.selectedPrice,
    required this.selectedDex,
    required this.currency,
    DateTime? timestamp,
    this.isSuccess = true,
    this.errorMessage,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a failed update event
  UnifiedPriceUpdateEvent.failed({
    required this.selectedDex,
    required this.currency,
    required this.errorMessage,
    DateTime? timestamp,
  }) : allPrices = {},
        selectedPrice = null,
        isSuccess = false,
        timestamp = timestamp ?? DateTime.now();

  /// Get price data for a specific DEX type
  PriceData? getPriceForDex(DefaultDex dex) {
    return allPrices.values
        .where((price) => price.dexType == dex)
        .firstOrNull;
  }

  /// Get price data for a specific source ID
  PriceData? getPriceForSource(String sourceId) {
    return allPrices[sourceId];
  }

  /// Get all DEX prices as a map (for backward compatibility)
  Map<DefaultDex, PriceData> get dexPrices {
    Map<DefaultDex, PriceData> result = {};
    for (PriceData price in allPrices.values) {
      if (price.dexType != null) {
        result[price.dexType!] = price;
      }
    }
    return result;
  }

  @override
  String toString() {
    return 'UnifiedPriceUpdateEvent(currency: $currency, sources: ${allPrices.length}, selected: ${selectedPrice?.sourceName}, success: $isSuccess)';
  }
}

/// Event fired when the user changes the selected price source
class PriceSourceChangedEvent implements Event {
  final DefaultDex previousDex;
  final DefaultDex newDex;
  final DateTime timestamp;

  PriceSourceChangedEvent({
    required this.previousDex,
    required this.newDex,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'PriceSourceChangedEvent(from: $previousDex, to: $newDex)';
  }
}

/// Event to request a manual price refresh
class PriceRefreshRequestedEvent implements Event {
  final String? currency;
  final bool forceRefresh;
  final DateTime timestamp;

  PriceRefreshRequestedEvent({
    this.currency,
    this.forceRefresh = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'PriceRefreshRequestedEvent(currency: $currency, force: $forceRefresh)';
  }
}

/// Event fired when price source availability changes
class PriceSourceAvailabilityEvent implements Event {
  final String sourceId;
  final bool isAvailable;
  final String? reason;
  final DateTime timestamp;

  PriceSourceAvailabilityEvent({
    required this.sourceId,
    required this.isAvailable,
    this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'PriceSourceAvailabilityEvent(source: $sourceId, available: $isAvailable, reason: $reason)';
  }
}