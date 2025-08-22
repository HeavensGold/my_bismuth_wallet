import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:event_taxi/event_taxi.dart';
import 'package:my_bismuth_wallet/service/price_sources/price_source.dart';
import 'package:my_bismuth_wallet/bus/unified_price_event.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';
import 'package:my_bismuth_wallet/service/retry_service.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:http/http.dart' as http;

/// Central manager for all price operations
class PriceManager extends WidgetsBindingObserver {
  final List<PriceSource> _sources = [];
  final Map<String, PriceData> _cachedPrices = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  String _currentCurrency = 'USD'; // Will be overridden by _initializeCurrency() from SharedPrefs
  DefaultDex _selectedDex = DefaultDex.AGGREGATED;
  
  // Lifecycle state tracking
  AppLifecycleState _appState = AppLifecycleState.resumed;
  DateTime? _lastUpdate;
  bool _hasInitializedPrices = false;

  // Enhanced: Exchange rate tracking from CoinGecko
  double? _btcToLocalRate;
  String? _currentLocalCurrency;

  // Global exchange rate cache (shared across all operations)
  static final Map<String, ExchangeRateData> _globalExchangeRates = {};
  static DateTime? _globalRatesTimestamp;
  static const Duration _rateCacheDuration = Duration(minutes: 5);
  
  // Lock to prevent concurrent API calls
  static bool _fetchingRates = false;
  static final List<Completer<void>> _rateWaiters = [];

  /// Singleton instance
  static PriceManager? _instance;
  static PriceManager get instance => _instance ??= PriceManager._();
  
  PriceManager._() {
    _setupEventListeners();
    _initializeCurrency();
  }
  
  /// Initialize currency from SharedPrefs
  Future<void> _initializeCurrency() async {
    try {
      final sharedPrefsUtil = sl.get<SharedPrefsUtil>();
      final savedCurrency = await sharedPrefsUtil.getCurrency(
          const Locale('en', 'US')); // Default locale, actual value comes from SharedPrefs
      _currentCurrency = savedCurrency.getIso4217Code();
      print('💰 PriceManager initialized with currency: $_currentCurrency from SharedPrefs');
    } catch (e) {
      print('⚠️  Failed to load currency from SharedPrefs, using USD default: $e');
      _currentCurrency = 'USD';
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('App resumed - checking if price refresh needed');
        if (_shouldRefreshOnResume()) {
          requestPriceUpdate();
        }
        _startPeriodicUpdates();
        break;
      case AppLifecycleState.paused:
        print('App paused - stopping price updates');
        stopPeriodicUpdates();
        break;
      case AppLifecycleState.inactive:
        print('App inactive - pausing price updates');
        stopPeriodicUpdates();
        break;
      case AppLifecycleState.detached:
        print('App detached - cleaning up price manager');
        _cleanup();
        break;
      case AppLifecycleState.hidden:
        print('App hidden - pausing price updates');
        stopPeriodicUpdates();
        break;
    }
  }
  
  /// Check if should refresh prices on app resume
  bool _shouldRefreshOnResume() {
    if (_lastUpdate == null) return true;
    return DateTime.now().difference(_lastUpdate!) > Duration(minutes: 1);
  }
  
  /// Initialize prices on first app launch/login
  Future<void> initializePrices() async {
    if (!_hasInitializedPrices) {
      print('Initializing prices for first time');
      await requestPriceUpdate(forceRefresh: true);
      _hasInitializedPrices = true;
    }
  }
  
  /// Start periodic updates with lifecycle awareness
  void _startPeriodicUpdates() {
    if (_appState == AppLifecycleState.resumed) {
      startPeriodicUpdates(interval: Duration(minutes: 5));
    }
  }
  
  /// Cleanup resources
  void _cleanup() {
    stopPeriodicUpdates();
    _debounceTimer?.cancel();
    _clearCache();
  }

  /// Register a price source
  void registerSource(PriceSource source) {
    if (!_sources.contains(source)) {
      _sources.add(source);
      _sources.sort((a, b) => a.priority.compareTo(b.priority));
      print('Registered price source: ${source.sourceName}');
    }
  }

  /// Unregister a price source
  void unregisterSource(PriceSource source) {
    _sources.remove(source);
    _cachedPrices.remove(source.sourceId);
    _cacheTimestamps.remove(source.sourceId);
    print('Unregistered price source: ${source.sourceName}');
  }

  /// Get all registered sources
  List<PriceSource> get sources => List.unmodifiable(_sources);

  /// Get available sources only
  List<PriceSource> get availableSources => 
      _sources.where((source) => source.isAvailable).toList();

  /// Get source by ID
  PriceSource? getSourceById(String sourceId) {
    try {
      return _sources.firstWhere((source) => source.sourceId == sourceId);
    } catch (e) {
      return null;
    }
  }

  /// Get source by DEX type
  PriceSource? getSourceByDex(DefaultDex dex) {
    try {
      return _sources.firstWhere((source) => source.dexType == dex);
    } catch (e) {
      return null;
    }
  }

  /// Set current currency
  void setCurrency(String currency) {
    if (_currentCurrency != currency) {
      _currentCurrency = currency;
      _clearCache();
      requestPriceUpdate(forceRefresh: true, skipDebounce: true);
    }
  }

  /// Set selected DEX/source
  void setSelectedDex(DefaultDex dex) {
    if (_selectedDex != dex) {
      DefaultDex previousDex = _selectedDex;
      _selectedDex = dex;
      
      EventTaxiImpl.singleton().fire(PriceSourceChangedEvent(
        previousDex: previousDex,
        newDex: dex,
      ));
      
      _fireUnifiedUpdate();
    }
  }

  /// Get current selected DEX
  DefaultDex get selectedDex => _selectedDex;

  /// Get current currency
  String get currency => _currentCurrency;

  /// Extract BTC exchange rates from cached exchange rate data
  void updateExchangeRates(PriceData coingeckoData) {
    // Get the exchange rate data for the current currency
    ExchangeRateData? rates = _globalExchangeRates[coingeckoData.currency];
    
    if (rates != null && rates.isValid(_rateCacheDuration)) {
      // Use the properly calculated BTC rate from exchange rate cache
      _btcToLocalRate = rates.btcToTarget;
      _currentLocalCurrency = coingeckoData.currency;
      print('Updated BTC rate from cache: 1 BTC = ${_btcToLocalRate?.toStringAsFixed(2)} ${_currentLocalCurrency}');
    } else {
      // Fallback: calculate from BIS prices (this is what was happening before)
      if (coingeckoData.btcPrice > 0 && coingeckoData.localCurrencyPrice > 0) {
        _btcToLocalRate = coingeckoData.localCurrencyPrice / coingeckoData.btcPrice;
        _currentLocalCurrency = coingeckoData.currency;
        print('Updated BTC rate from BIS fallback: 1 BTC = ${_btcToLocalRate?.toStringAsFixed(2)} ${_currentLocalCurrency}');
      }
    }
  }

  /// Get BTC exchange rate for currency conversion
  double? getBtcRate(String targetCurrency) {
    if (_currentLocalCurrency == targetCurrency) {
      return _btcToLocalRate;
    }
    // Return current rate even for different currencies
    // This could be enhanced with proper currency conversion later
    return _btcToLocalRate;
  }

  /// Request price update from all sources - CENTRALIZED APPROACH with debouncing
  Future<void> requestPriceUpdate({
    String? currency,
    bool forceRefresh = false,
    bool parallel = true,
    bool skipDebounce = false,
  }) async {
    // Don't update if app is backgrounded
    if (_appState != AppLifecycleState.resumed) {
      print('Skipping price update - app is not in foreground (${_appState})');
      return;
    }

    // Implement debouncing to prevent rapid requests (unless skipped or forced)
    if (!skipDebounce && !forceRefresh) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(Duration(milliseconds: 500), () {
        _performPriceUpdate(currency, forceRefresh, parallel);
      });
      return;
    }

    // Cancel any pending debounced request
    _debounceTimer?.cancel();
    
    return _performPriceUpdate(currency, forceRefresh, parallel);
  }

  /// Perform the actual price update (called after debounce or immediately)
  Future<void> _performPriceUpdate(String? currency, bool forceRefresh, bool parallel) async {
    final targetCurrency = currency ?? _currentCurrency;
    
    try {
      Map<String, PriceData> newPrices = {};
      
      // Step 1: SINGLE CoinGecko API call - PriceManager makes the call directly
      PriceData? coingeckoData = await _fetchCoingeckoDataDirectly(targetCurrency, forceRefresh);
      if (coingeckoData != null) {
        // Extract BTC exchange rate from our own API call
        updateExchangeRates(coingeckoData);
        
        // Cache BTC/USD rate when we have USD data for DEX source calculations
        if (targetCurrency.toUpperCase() == 'USD' && coingeckoData.btcPrice > 0) {
          // This is already handled by updateExchangeRates above
          print('💰 Cached BTC/USD rate from CoinGecko: ${_btcToLocalRate?.toStringAsFixed(2)}');
        }
        
        newPrices['coingecko_aggregated'] = coingeckoData;
      }
      
      // Step 2: Process DEX sources using shared data (no additional API calls for rates)
      List<PriceSource> dexSources = availableSources
          .where((source) => source.dexType != DefaultDex.AGGREGATED)
          .toList();
      
      if (parallel) {
        // Fetch DEX data in parallel, but they all use our shared BTC rate
        List<Future<MapEntry<String, PriceData>?>> futures = dexSources
            .map((source) => _fetchFromSourceWithBtcCorrection(source, targetCurrency, forceRefresh))
            .toList();
        
        List<MapEntry<String, PriceData>?> results = await Future.wait(futures);
        
        for (MapEntry<String, PriceData>? result in results) {
          if (result != null) {
            newPrices[result.key] = result.value;
          }
        }
      } else {
        // Fetch sequentially (fallback mode)
        for (PriceSource source in dexSources) {
          MapEntry<String, PriceData>? result = 
              await _fetchFromSourceWithBtcCorrection(source, targetCurrency, forceRefresh);
          if (result != null) {
            newPrices[result.key] = result.value;
          }
        }
      }

      if (newPrices.isNotEmpty) {
        _cachedPrices.clear();
        _cachedPrices.addAll(newPrices);
        _lastUpdate = DateTime.now();
        _fireUnifiedUpdate();
      } else {
        _fireFailedUpdate('No price sources returned data');
      }
    } catch (e) {
      print('Error in requestPriceUpdate: $e');
      _fireFailedUpdate('Failed to fetch prices: $e');
    }
  }

  /// CENTRALIZED CoinGecko API call - Using global exchange rate cache
  Future<PriceData?> _fetchCoingeckoDataDirectly(String currency, bool forceRefresh) async {
    String cacheKey = 'coingecko_aggregated_$currency';
    
    if (!forceRefresh && _isCacheValid(cacheKey, 5)) { // 5 minutes cache for CoinGecko
      PriceData? cached = _cachedPrices['coingecko_aggregated'];
      if (cached != null) {
        return cached;
      }
    }

    // Use the new global exchange rate cache system
    ExchangeRateData? exchangeRates = await _getOrFetchExchangeRates(currency);
    
    if (exchangeRates != null) {
      // Create PriceData from cached exchange rates (no additional API call!)
      PriceData result = PriceData.aggregated(
        btcPrice: exchangeRates.bisBtcPrice,
        localCurrencyPrice: exchangeRates.bisTargetPrice,
        currency: currency,
      );
      
      _cacheTimestamps[cacheKey] = DateTime.now();
      return result;
    }
    
    return null;
  }



  /// Fetch price from a single source with caching and retry logic
  /// NOTE: CoinGecko source is handled centrally, this is for DEX sources only
  Future<MapEntry<String, PriceData>?> _fetchFromSource(
    PriceSource source,
    String currency,
    bool forceRefresh,
  ) async {
    // Skip CoinGecko source - it's handled centrally by _fetchCoingeckoDataDirectly
    if (source.dexType == DefaultDex.AGGREGATED) {
      print('⚠️  Skipping CoinGecko source - handled centrally');
      return null;
    }

    String cacheKey = '${source.sourceId}_$currency';
    
    if (!forceRefresh && _isCacheValid(cacheKey, source.cacheDurationMinutes)) {
      PriceData? cached = _cachedPrices[source.sourceId];
      if (cached != null) {
        return MapEntry(source.sourceId, cached);
      }
    }

    // Determine retry config based on source type
    RetryConfig config = _getRetryConfigForSource(source);
    
    // Use retry service for robust fetching
    PriceData? priceData = await RetryService.instance.executeWithRetry<PriceData?>(
      () => source.fetchPrice(currency),
      config,
    );
    
    if (priceData != null) {
      _cacheTimestamps[cacheKey] = DateTime.now();
      return MapEntry(source.sourceId, priceData);
    }
    
    return null;
  }

  /// Get appropriate retry configuration for a price source
  RetryConfig _getRetryConfigForSource(PriceSource source) {
    if (source.dexType == DefaultDex.AGGREGATED) {
      return RetryConfig(
        sourceId: source.sourceId,
        maxAttempts: 2, // CoinGecko is usually reliable
        baseDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 15),
      );
    } else if (source.sourceName.contains('Uniswap') || source.sourceName.contains('PancakeSwap')) {
      return RetryConfig(
        sourceId: source.sourceId,
        maxAttempts: 4, // DEX sources can be flakier
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 45),
      );
    } else {
      return RetryConfig(
        sourceId: source.sourceId,
        maxAttempts: 3, // Default config
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
      );
    }
  }

  /// Fetch price from a single source with BTC rate correction for DEX sources
  Future<MapEntry<String, PriceData>?> _fetchFromSourceWithBtcCorrection(
    PriceSource source,
    String currency,
    bool forceRefresh,
  ) async {
    MapEntry<String, PriceData>? result = await _fetchFromSource(source, currency, forceRefresh);
    
    if (result != null) {
      PriceData originalData = result.value;
      
      // Apply enhancements for DEX sources
      if (source.sourceName.contains('Uniswap') || source.sourceName.contains('PancakeSwap')) {
        try {
          PriceData enhancedData = originalData;
          
          // Apply currency conversion if needed (only if currencies don't match)
          if (currency.toUpperCase() != enhancedData.currency.toUpperCase()) {
            try {
              PriceData? convertedData = await convertDexPriceData(enhancedData, currency);
              if (convertedData != null) {
                enhancedData = convertedData;
                print('✅ Currency conversion successful for ${source.sourceName}: ${enhancedData.currency}');
              } else {
                print('⚠️  Currency conversion returned null for ${source.sourceName}');
              }
            } catch (e) {
              print('⚠️  Currency conversion error for ${source.sourceName}: $e');
            }
          } else if (enhancedData.btcPrice <= 0) {
            // Calculate BTC price for DEX sources that return btcPrice=0 (like GeckoTerminal API)
            try {
              ExchangeRateData? rates = _globalExchangeRates[currency];
              if (rates != null && rates.isValid(_rateCacheDuration) && rates.btcToTarget > 0) {
                double calculatedBtcPrice = enhancedData.localCurrencyPrice / rates.btcToTarget;
                enhancedData = PriceData(
                  sourceName: enhancedData.sourceName,
                  sourceId: enhancedData.sourceId,
                  btcPrice: calculatedBtcPrice,
                  localCurrencyPrice: enhancedData.localCurrencyPrice,
                  currency: enhancedData.currency,
                  volume24h: enhancedData.volume24h,
                  isActive: enhancedData.isActive,
                  dexType: enhancedData.dexType,
                  timestamp: enhancedData.timestamp,
                );
                print('✅ Calculated BTC price for ${source.sourceName}: ${calculatedBtcPrice.toStringAsFixed(8)} BTC');
              }
            } catch (e) {
              print('⚠️  Failed to calculate BTC price for ${source.sourceName}: $e');
            }
          }
          
          return MapEntry(result.key, enhancedData);
        } catch (e) {
          print('Failed to enhance DEX source data for ${source.sourceName}: $e');
          // Return original data if enhancement fails
          return result;
        }
      }
    }
    
    return result;
  }


  /// Convert DEX price data using cached exchange rates (no API calls)
  PriceData? _convertWithCachedRates(PriceData usdData, ExchangeRateData rates) {
    if (rates.targetCurrency.toUpperCase() == 'USD') return usdData;
    
    try {
      // No API calls - just math with cached rates
      final convertedPrice = usdData.localCurrencyPrice * rates.usdToTarget;
      final btcPrice = convertedPrice / rates.btcToTarget;
      
      print('✅ Cached conversion for ${usdData.sourceName}: ${usdData.localCurrencyPrice} ${usdData.currency} -> ${convertedPrice.toStringAsFixed(6)} ${rates.targetCurrency}');
      
      return PriceData(
        sourceName: usdData.sourceName,
        sourceId: usdData.sourceId,
        btcPrice: btcPrice,
        localCurrencyPrice: convertedPrice,
        currency: rates.targetCurrency,
        volume24h: usdData.volume24h,
        isActive: usdData.isActive,
        dexType: usdData.dexType,
        timestamp: usdData.timestamp,
      );
    } catch (e) {
      print('⚠️  Cached conversion failed for ${usdData.sourceName}: $e');
      return null;
    }
  }


  /// Convert DEX price data from USD to target currency using cached rates
  Future<PriceData?> convertDexPriceData(PriceData usdData, String targetCurrency) async {
    if (targetCurrency.toUpperCase() == 'USD') return usdData;
    
    try {
      // Use cached exchange rates (no API calls!)
      ExchangeRateData? exchangeRates = _globalExchangeRates[targetCurrency];
      
      if (exchangeRates != null && exchangeRates.isValid(_rateCacheDuration)) {
        return _convertWithCachedRates(usdData, exchangeRates);
      } else {
        print('⚠️  No valid cached exchange rates for $targetCurrency, fetching...');
        // This should rarely happen since we pre-fetch rates in requestPriceUpdate
        exchangeRates = await _getOrFetchExchangeRates(targetCurrency);
        if (exchangeRates != null) {
          return _convertWithCachedRates(usdData, exchangeRates);
        }
      }
    } catch (e) {
      print('⚠️  Currency conversion failed: $e');
    }
    
    // Fallback: Return USD data when conversion fails
    print('⚠️  Currency conversion failed, returning USD data for ${usdData.sourceName}');
    return PriceData(
      sourceName: usdData.sourceName,
      sourceId: usdData.sourceId,
      btcPrice: usdData.btcPrice,
      localCurrencyPrice: usdData.localCurrencyPrice,
      currency: 'USD', // Mark as USD when conversion fails
      volume24h: usdData.volume24h,
      isActive: usdData.isActive,
      dexType: usdData.dexType,
      timestamp: usdData.timestamp,
    );
  }

  /// Check if cache is valid for given duration
  bool _isCacheValid(String cacheKey, int durationMinutes) {
    DateTime? timestamp = _cacheTimestamps[cacheKey];
    if (timestamp == null) return false;
    
    Duration elapsed = DateTime.now().difference(timestamp);
    return elapsed.inMinutes < durationMinutes;
  }

  /// Check if global exchange rate cache is valid
  bool _isRateCacheValid(String targetCurrency) {
    if (_globalRatesTimestamp == null) return false;
    
    final exchangeData = _globalExchangeRates[targetCurrency];
    if (exchangeData == null) return false;
    
    return exchangeData.isValid(_rateCacheDuration);
  }

  /// Get or fetch exchange rates with deduplication (single API call approach)
  Future<ExchangeRateData?> _getOrFetchExchangeRates(String targetCurrency) async {
    // Check cache first
    if (_isRateCacheValid(targetCurrency)) {
      print('✅ Using cached exchange rates for $targetCurrency');
      return _globalExchangeRates[targetCurrency];
    }
    
    // If already fetching, wait for completion
    if (_fetchingRates) {
      print('⏳ Exchange rates fetch in progress, waiting...');
      final completer = Completer<void>();
      _rateWaiters.add(completer);
      await completer.future;
      return _globalExchangeRates[targetCurrency];
    }
    
    // Single fetch with lock
    _fetchingRates = true;
    try {
      print('🔄 Fetching fresh exchange rates for $targetCurrency');
      // ONE API call for all needed data
      final rates = await _fetchAllRatesOnce(targetCurrency);
      
      if (rates != null) {
        _globalExchangeRates[targetCurrency] = rates;
        _globalRatesTimestamp = DateTime.now();
        print('✅ Cached exchange rates: ${rates}');
      }
      
      // Notify all waiters
      for (final waiter in _rateWaiters) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
      _rateWaiters.clear();
      
      return rates;
    } catch (e) {
      print('❌ Failed to fetch exchange rates: $e');
      // Notify waiters of failure
      for (final waiter in _rateWaiters) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
      _rateWaiters.clear();
      return null;
    } finally {
      _fetchingRates = false;
    }
  }

  /// Fetch all exchange rates in a single API call
  Future<ExchangeRateData?> _fetchAllRatesOnce(String targetCurrency) async {
    try {
      // Single API call to get both BIS and BTC prices in USD and target currency
      String currenciesQuery = "usd," + targetCurrency.toLowerCase();

      // Fetch both bismuth and bitcoin prices
      http.Response response = await http.get(
        Uri.parse(
          "https://api.coingecko.com/api/v3/simple/price?ids=bismuth,bitcoin&vs_currencies=" +
              currenciesQuery
        ),
        headers: {
          'content-type': 'application/json',
          'access-Control-Allow-Origin': '*'
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        String reply = response.body;
        Map<String, dynamic> priceData = json.decode(reply);
        Map<String, dynamic>? bismuthData = priceData['bismuth'];
        Map<String, dynamic>? bitcoinData = priceData['bitcoin'];

        if (bismuthData != null && bitcoinData != null) {
          // Extract BIS prices
          double bisUsdPrice = bismuthData['usd']?.toDouble() ?? 0.0;
          double bisTargetPrice = bismuthData[targetCurrency.toLowerCase()]?.toDouble() ?? 0.0;
          
          // Extract BTC prices for real exchange rates
          double btcUsdPrice = bitcoinData['usd']?.toDouble() ?? 0.0;
          double btcTargetPrice = bitcoinData[targetCurrency.toLowerCase()]?.toDouble() ?? 0.0;

          if (bisUsdPrice > 0 && bisTargetPrice > 0 && btcUsdPrice > 0 && btcTargetPrice > 0) {
            // Calculate exchange rates using actual BTC prices
            double usdToTargetRate = bisTargetPrice / bisUsdPrice;
            double btcToTargetRate = btcTargetPrice; // Direct BTC to target currency rate
            
            // Calculate BIS/BTC price for the aggregated source
            double bisBtcPrice = bisUsdPrice / btcUsdPrice;

            return ExchangeRateData(
              usdToTarget: usdToTargetRate,
              btcToTarget: btcToTargetRate,
              bisBtcPrice: bisBtcPrice,
              bisUsdPrice: bisUsdPrice,
              bisTargetPrice: bisTargetPrice,
              targetCurrency: targetCurrency,
            );
          }
        }
      } else {
        throw Exception('CoinGecko API returned ${response.statusCode}: ${response.reasonPhrase}');
      }

      return null;
    } catch (e) {
      print('Exchange rates API call failed: $e');
      rethrow;
    }
  }

  /// Clear all cached data
  void _clearCache() {
    _cachedPrices.clear();
    _cacheTimestamps.clear();
    // Clear global exchange rate cache
    _globalExchangeRates.clear();
    _globalRatesTimestamp = null;
  }

  /// Get current price data for selected source
  PriceData? get selectedPrice {
    PriceSource? source = getSourceByDex(_selectedDex);
    if (source != null) {
      return _cachedPrices[source.sourceId];
    }
    return null;
  }

  /// Get all current cached prices
  Map<String, PriceData> get allPrices => Map.unmodifiable(_cachedPrices);

  /// Start periodic price updates
  void startPeriodicUpdates({Duration interval = const Duration(seconds: 30)}) {
    stopPeriodicUpdates();
    _periodicTimer = Timer.periodic(interval, (_) {
      requestPriceUpdate();
    });
    print('Started periodic price updates every ${interval.inSeconds} seconds');
  }

  /// Stop periodic price updates
  void stopPeriodicUpdates() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Fire unified price update event
  void _fireUnifiedUpdate() {
    PriceData? selected = selectedPrice;
    
    EventTaxiImpl.singleton().fire(UnifiedPriceUpdateEvent(
      allPrices: Map.from(_cachedPrices),
      selectedPrice: selected,
      selectedDex: _selectedDex,
      currency: _currentCurrency,
    ));
  }

  /// Fire failed update event
  void _fireFailedUpdate(String errorMessage) {
    EventTaxiImpl.singleton().fire(UnifiedPriceUpdateEvent.failed(
      selectedDex: _selectedDex,
      currency: _currentCurrency,
      errorMessage: errorMessage,
    ));
  }

  /// Setup event listeners
  void _setupEventListeners() {
    EventTaxiImpl.singleton().registerTo<PriceRefreshRequestedEvent>().listen((event) {
      requestPriceUpdate(
        currency: event.currency,
        forceRefresh: event.forceRefresh,
      );
    });
  }

  /// Get price statistics for all sources
  Map<String, dynamic> getPriceStatistics() {
    Map<String, dynamic> stats = {
      'total_sources': _sources.length,
      'available_sources': availableSources.length,
      'cached_prices': _cachedPrices.length,
      'current_currency': _currentCurrency,
      'selected_dex': _selectedDex.toString(),
      'last_update': null,
      'btc_exchange_rate': _btcToLocalRate,
      'btc_rate_currency': _currentLocalCurrency,
      'retry_statistics': RetryService.instance.getRetryStatistics(),
    };

    if (_cacheTimestamps.isNotEmpty) {
      DateTime latestUpdate = _cacheTimestamps.values
          .reduce((a, b) => a.isAfter(b) ? a : b);
      stats['last_update'] = latestUpdate.toIso8601String();
    }

    return stats;
  }

  /// Dispose of resources
  void dispose() {
    stopPeriodicUpdates();
    _debounceTimer?.cancel();
    _clearCache();
    _sources.clear();
  }
}

/// Extension to add firstOrNull to Iterable
extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}