// Package imports:
import 'package:event_taxi/event_taxi.dart';

// Bus event for network errors
enum NetworkErrorType { 
  CONNECTION_FAILED, 
  TIMEOUT, 
  SERVER_ERROR, 
  UNKNOWN_ERROR,
  BALANCE_FETCH_FAILED,
  TRANSACTION_HISTORY_FAILED,
  SEND_TRANSACTION_FAILED
}

class NetworkErrorEvent implements Event {
  final NetworkErrorType errorType;
  final String? message;
  final String? operation;
  final bool canRetry;

  NetworkErrorEvent({
    required this.errorType,
    this.message,
    this.operation,
    this.canRetry = true,
  });
}