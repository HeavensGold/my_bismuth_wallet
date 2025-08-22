import 'dart:math' as math;

/// Configuration for retry behavior
class RetryConfig {
  final String sourceId;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitterFactor;

  const RetryConfig({
    required this.sourceId,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.jitterFactor = 0.3, // 30% jitter
  });

  /// Default config for price sources
  static const RetryConfig priceSource = RetryConfig(
    sourceId: 'default',
    maxAttempts: 3,
    baseDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
  );

  /// High priority config for CoinGecko
  static const RetryConfig coingecko = RetryConfig(
    sourceId: 'coingecko',
    maxAttempts: 2,
    baseDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 15),
  );

  /// DEX config with more patience
  static const RetryConfig dex = RetryConfig(
    sourceId: 'dex',
    maxAttempts: 4,
    baseDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 45),
  );
}

/// Circuit breaker to prevent overwhelming failing services
class CircuitBreaker {
  final String sourceId;
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  bool _isOpen = false;
  
  static const int maxFailures = 5;
  static const Duration cooldownPeriod = Duration(minutes: 2);
  
  CircuitBreaker(this.sourceId);
  
  bool get isOpen {
    if (_isOpen && _lastFailureTime != null) {
      if (DateTime.now().difference(_lastFailureTime!) > cooldownPeriod) {
        _isOpen = false;
        _failureCount = 0;
        print('Circuit breaker reset for $sourceId');
      }
    }
    return _isOpen;
  }
  
  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    if (_failureCount >= maxFailures) {
      _isOpen = true;
      print('Circuit breaker opened for $sourceId after $_failureCount failures');
    }
  }
  
  void recordSuccess() {
    _failureCount = 0;
    _isOpen = false;
    _lastFailureTime = null;
  }

  /// Get current status info
  Map<String, dynamic> getStatus() {
    return {
      'sourceId': sourceId,
      'isOpen': _isOpen,
      'failureCount': _failureCount,
      'lastFailure': _lastFailureTime?.toIso8601String(),
    };
  }
}

/// Advanced retry service with exponential backoff and circuit breaker
class RetryService {
  final Map<String, CircuitBreaker> _circuitBreakers = {};
  
  /// Singleton instance
  static RetryService? _instance;
  static RetryService get instance => _instance ??= RetryService._();
  
  RetryService._();

  /// Execute operation with retry logic and circuit breaker
  Future<T?> executeWithRetry<T>(
    Future<T> Function() operation,
    RetryConfig config,
  ) async {
    final breaker = _getCircuitBreaker(config.sourceId);
    
    if (breaker.isOpen) {
      print('Circuit breaker open for ${config.sourceId}, skipping operation');
      return null;
    }
    
    for (int attempt = 0; attempt < config.maxAttempts; attempt++) {
      try {
        final result = await operation();
        breaker.recordSuccess();
        
        if (attempt > 0) {
          print('Operation succeeded for ${config.sourceId} on attempt ${attempt + 1}');
        }
        
        return result;
      } catch (e) {
        
        if (attempt == config.maxAttempts - 1) {
          // Last attempt failed
          breaker.recordFailure();
          print('All ${config.maxAttempts} retry attempts failed for ${config.sourceId}: $e');
          return null;
        }
        
        // Calculate delay with exponential backoff and jitter
        final delay = _calculateDelay(attempt, config);
        print('Attempt ${attempt + 1} failed for ${config.sourceId}: $e. Retrying in ${delay.inMilliseconds}ms...');
        await Future.delayed(delay);
      }
    }
    
    return null;
  }

  /// Calculate delay with exponential backoff and jitter
  Duration _calculateDelay(int attempt, RetryConfig config) {
    // Exponential backoff: baseDelay * 2^attempt
    final exponentialDelay = config.baseDelay * math.pow(2, attempt);
    
    // Apply jitter to avoid thundering herd
    final jitter = (math.Random().nextDouble() * 2 - 1) * config.jitterFactor; // -30% to +30%
    final delayWithJitter = exponentialDelay * (1 + jitter);
    
    // Cap at maximum delay
    final cappedDelay = Duration(
      milliseconds: math.min(delayWithJitter.inMilliseconds, config.maxDelay.inMilliseconds)
    );
    
    return cappedDelay;
  }

  /// Get or create circuit breaker for source
  CircuitBreaker _getCircuitBreaker(String sourceId) {
    return _circuitBreakers.putIfAbsent(sourceId, () => CircuitBreaker(sourceId));
  }

  /// Check if circuit breaker is open for source
  bool isCircuitOpen(String sourceId) {
    return _getCircuitBreaker(sourceId).isOpen;
  }

  /// Get status of all circuit breakers
  Map<String, Map<String, dynamic>> getAllCircuitBreakerStatus() {
    Map<String, Map<String, dynamic>> status = {};
    for (String sourceId in _circuitBreakers.keys) {
      status[sourceId] = _circuitBreakers[sourceId]!.getStatus();
    }
    return status;
  }

  /// Reset circuit breaker for source (for testing/manual recovery)
  void resetCircuitBreaker(String sourceId) {
    CircuitBreaker? breaker = _circuitBreakers[sourceId];
    if (breaker != null) {
      breaker.recordSuccess();
      print('Manually reset circuit breaker for $sourceId');
    }
  }

  /// Get retry statistics
  Map<String, dynamic> getRetryStatistics() {
    return {
      'active_circuit_breakers': _circuitBreakers.length,
      'open_circuit_breakers': _circuitBreakers.values.where((cb) => cb.isOpen).length,
      'circuit_breaker_status': getAllCircuitBreakerStatus(),
    };
  }
}