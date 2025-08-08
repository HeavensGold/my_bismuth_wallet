# Bismuth Wallet Communication Issues - Analysis and Fix

## Root Causes Identified

### 1. **Message Buffer Corruption**
- **Issue**: Using `.trim()` on binary socket data corrupts message boundaries
- **Location**: `app_service.dart` lines 88, 142, 229, 294, 443, 468, 574
- **Impact**: Length headers and message content get corrupted, preventing proper parsing

### 2. **Buffer Not Cleared After Processing**
- **Issue**: Message buffer isn't cleared after processing, causing subsequent messages to be misaligned
- **Location**: All socket listeners in `app_service.dart`
- **Impact**: After first message, all subsequent messages fail to parse

### 3. **No TCP Message Fragmentation Handling**
- **Issue**: Code assumes complete messages arrive in one chunk, but TCP can fragment
- **Location**: All socket data handlers
- **Impact**: Large responses (transaction lists) may arrive in multiple chunks and fail to parse

### 4. **Silent JSON Parsing Failures**
- **Issue**: JSON parsing errors are caught but not logged or reported to UI
- **Location**: Response parsing functions don't fire error events
- **Impact**: Users see no balance/transactions with no error indication

### 5. **WebSocket URL Format Issues**
- **Issue**: WebSocket connections missing 'ws://' protocol prefix
- **Location**: `IOWebSocketChannel.connect()` calls
- **Impact**: WebSocket connections may fail on web platform

## Key Fixes Applied

### 1. Proper Buffer Management
```dart
// NEW: Process buffer without trim() to preserve exact data
List<String> processBuffer(Uint8List data, StringBuffer buffer) {
  buffer.write(String.fromCharCodes(data)); // No trim!
  // Extract complete messages while handling fragmentation
}
```

### 2. Enhanced Error Handling
```dart
try {
  WStatusGetResponse response = wStatusGetResponseFromJson(message);
  EventTaxiImpl.singleton().fire(WStatusGetEvent(response: response));
} catch (e) {
  log.e("Failed to parse response: $e\nResponse: $message");
  // Fire error event for UI feedback
}
```

### 3. Improved Logging
- Added debug logs for all requests/responses
- Log connection attempts and failures
- Log parsing errors with context

### 4. Connection Timeout Improvements
- Increased timeout from 3 to 5 seconds for better reliability
- Added proper WebSocket URL formatting

## Testing Commands

Test the fixes with these commands:

```bash
# Test server availability
curl -s https://bismuth.world/api/legacy.json | jq

# Test direct socket connection
echo '0000000013"wstatusget"' | nc -w 3 62.112.10.156 8150

# Test balance request (replace with actual address)
echo -e '0000000017"balancegetjson"0000000056"YOUR_ADDRESS_HERE"' | nc -w 3 62.112.10.156 8150
```

## Files Modified

1. **app_service.dart**: Main service file with socket communication
   - Fixed buffer handling
   - Added proper error handling
   - Improved logging
   - Fixed WebSocket URLs

## Recommendations

1. **Replace the original file**: Copy `app_service_fixed.dart` over `app_service.dart`
2. **Enable logging**: Set logger level to debug to see communication details
3. **Test thoroughly**: Test with different addresses and network conditions
4. **Monitor logs**: Watch for any parsing errors or connection failures

## Quick Fix Application

To apply the fix:
```bash
cp lib/service/app_service_fixed.dart lib/service/app_service.dart
flutter clean
flutter pub get
flutter run
```