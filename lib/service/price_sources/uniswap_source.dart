import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:my_bismuth_wallet/service/price_sources/price_source.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

/// Uniswap V2 price source via GeckoTerminal
class UniswapSource extends BasePriceSource {
  static const String wBIS_ETH = "0xf5cb350b40726b5bcf170d12e162b6193b291b41";

  @override
  String get sourceName => 'Uniswap V2';

  @override
  String get sourceId => 'uniswap_v2';

  @override
  bool get isAvailable => true;

  @override
  DefaultDex get dexType => DefaultDex.UNISWAP_V2;

  @override
  int get priority => 10;

  @override
  int get cacheDurationMinutes => 3; // More frequent updates for DEX prices

  @override
  Future<PriceData?> fetchPriceImpl(String currency) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.geckoterminal.com/api/v2/networks/eth/tokens/$wBIS_ETH/pools'
        ),
        headers: {
          'accept': 'application/json',
          'user-agent': 'BismuthWallet/1.0',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        List<dynamic>? pools = data['data'];

        if (pools != null && pools.isNotEmpty) {
          // Find the pool with highest liquidity/volume
          var bestPool = pools.reduce((a, b) {
            // Volume is a string in the API response
            String aVolumeStr =
                a['attributes']?['volume_usd']?['h24']?.toString() ?? '0';
            String bVolumeStr =
                b['attributes']?['volume_usd']?['h24']?.toString() ?? '0';
            double aVolume = double.tryParse(aVolumeStr) ?? 0.0;
            double bVolume = double.tryParse(bVolumeStr) ?? 0.0;
            return aVolume > bVolume ? a : b;
          });

          return _parsePoolData(bestPool, currency);
        }
      }

      return null;
    } catch (e) {
      print('Uniswap V2 fetch failed: $e');
      return null;
    }
  }

  /// Parse pool data from GeckoTerminal response
  PriceData? _parsePoolData(Map<String, dynamic> poolData, String currency) {
    try {
      final attributes = poolData['attributes'];
      if (attributes == null) return null;

      // Parse volume - it's a string in the API response
      double volume24h = 0.0;
      if (attributes['volume_usd'] != null &&
          attributes['volume_usd']['h24'] != null) {
        var volumeStr = attributes['volume_usd']['h24'].toString();
        volume24h = double.tryParse(volumeStr) ?? 0.0;
      }

      // Get USD price from base_token_price_usd
      String usdPriceStr = attributes['base_token_price_usd']?.toString() ?? '0';
      double usdPrice = double.tryParse(usdPriceStr) ?? 0.0;

      if (usdPrice <= 0) return null;

      // Don't calculate BTC price here - let PriceManager handle it with real-time rates
      // Always return USD price data from GeckoTerminal API
      
      return PriceData(
        sourceName: sourceName,
        sourceId: sourceId,
        btcPrice: 0, // Will be calculated by PriceManager using real BTC/USD rate
        localCurrencyPrice: usdPrice,
        currency: 'USD', // Always USD from GeckoTerminal API
        volume24h: volume24h,
        isActive: true,
        dexType: dexType,
      );
    } catch (e) {
      print('Error parsing Uniswap pool data: $e');
      return null;
    }
  }

}