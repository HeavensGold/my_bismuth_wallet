import 'package:my_bismuth_wallet/service/price_sources/price_source.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

/// CoinGecko aggregated price source
class CoingeckoSource extends BasePriceSource {
  @override
  String get sourceName => 'CoinGecko Aggregated';

  @override
  String get sourceId => 'coingecko_aggregated';

  @override
  bool get isAvailable => true;

  @override
  DefaultDex get dexType => DefaultDex.AGGREGATED;

  @override
  int get priority => 1; // Highest priority for aggregated data

  @override
  int get cacheDurationMinutes => 5;

  @override
  Future<PriceData?> fetchPriceImpl(String currency) async {
    // ⚠️  DEPRECATED: This method should NOT be called directly anymore!
    // The PriceManager now handles CoinGecko API calls centrally.
    // This source exists only for compatibility and should return null
    // to indicate that data comes from the centralized manager.
    
    print('⚠️  WARNING: CoinGecko source fetchPriceImpl() called directly - this should not happen!');
    print('   CoinGecko data should come from PriceManager._fetchCoingeckoDataDirectly()');
    
    // Return null to force use of centralized API call
    return null;
  }
}