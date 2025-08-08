// Minimal Bismuth P2P client for direct blockchain access
// Connects to Bismuth peer-to-peer network for real-time data

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:event_taxi/event_taxi.dart';

import 'package:my_bismuth_wallet/bus/events.dart';
import 'package:my_bismuth_wallet/network/model/response/balance_get_response.dart';
import 'package:my_bismuth_wallet/service_locator.dart';

class BismuthP2PService {
  final Logger log = sl.get<Logger>();
  
  // Bootstrap peers from the Bismuth network
  static const List<String> BOOTSTRAP_PEERS = [
    "62.112.10.156",
    "185.184.192.210", 
    "91.121.77.179",
    "188.165.199.153",
    "46.105.43.213",
    "139.180.199.99",
    "185.100.232.131",
    "192.99.34.19",
    "91.121.87.99",
    "198.245.62.30",
    "51.15.90.15",
    "149.28.120.120"
  ];
  
  static const int P2P_PORT = 5658;
  static const String PROTOCOL_VERSION = "mainnet0022";
  static const int MESSAGE_TIMEOUT = 5;

  // Send data with 10-byte length prefix (Bismuth P2P protocol)
  void _sendMessage(Socket socket, dynamic data) {
    String jsonData = json.encode(data);
    String lengthHeader = jsonData.length.toString().padLeft(10, '0');
    String message = lengthHeader + jsonData;
    socket.write(message);
    log.d("Sent P2P message: $message");
  }

  // Receive data with 10-byte length prefix using a completely isolated approach
  Future<dynamic> _receiveMessage(Socket socket, {int timeoutSeconds = MESSAGE_TIMEOUT}) async {
    List<int> buffer = [];
    int totalBytesRead = 0;
    bool messageComplete = false;
    dynamic result;
    
    // Wait for data in chunks
    int attempts = 0;
    final maxAttempts = timeoutSeconds * 10; // Check every 100ms
    
    while (attempts < maxAttempts && !messageComplete) {
      await Future.delayed(Duration(milliseconds: 100));
      attempts++;
      
      try {
        // Try to read available bytes
        List<int> chunk = await socket.first.timeout(Duration(milliseconds: 50));
        buffer.addAll(chunk);
        totalBytesRead += chunk.length;
        
        log.d("P2P received ${chunk.length} bytes, total: $totalBytesRead");
        
        // Process buffer if we have enough data
        if (buffer.length >= 10) {
          String lengthStr = String.fromCharCodes(buffer.sublist(0, 10));
          int? messageLength = int.tryParse(lengthStr);
          
          if (messageLength != null && buffer.length >= 10 + messageLength) {
            List<int> messageBytes = buffer.sublist(10, 10 + messageLength);
            String message = String.fromCharCodes(messageBytes);
            
            log.d("P2P complete message received: $message");
            
            try {
              result = json.decode(message);
              messageComplete = true;
            } catch (e) {
              log.d("Message is not JSON, returning as string: $message");
              result = message;
              messageComplete = true;
            }
          }
        }
      } catch (e) {
        // No data available yet, continue waiting
        if (e.toString().contains('timeout')) {
          continue;
        } else {
          log.e("P2P receive error: $e");
          break;
        }
      }
    }
    
    if (messageComplete) {
      return result;
    } else {
      throw Exception('Timeout waiting for P2P response after ${timeoutSeconds}s');
    }
  }

  // Perform version handshake with peer
  Future<bool> _doHandshake(Socket socket) async {
    try {
      // Send protocol version
      _sendMessage(socket, "version");
      _sendMessage(socket, PROTOCOL_VERSION);
      
      // Wait for "ok" response
      dynamic response = await _receiveMessage(socket, timeoutSeconds: 5);
      
      log.d("P2P handshake response: '$response' (${response.runtimeType})");
      
      // Handle both "ok" string and quoted "ok" JSON responses
      String responseStr = response.toString();
      if (responseStr == "ok" || responseStr == '"ok"') {
        log.d("P2P handshake successful");
        return true;
      } else {
        log.w("P2P handshake failed, expected 'ok' but got: '$response'");
        return false;
      }
    } catch (e) {
      log.e("P2P handshake error: $e");
      return false;
    }
  }

  // Connect to a Bismuth peer and perform handshake
  Future<Socket?> _connectToPeer(String peerIp) async {
    try {
      log.d("Connecting to Bismuth peer: $peerIp:$P2P_PORT");
      
      Socket socket = await Socket.connect(
        peerIp, 
        P2P_PORT,
        timeout: Duration(seconds: 3)
      );
      
      // Perform version handshake
      bool handshakeSuccess = await _doHandshake(socket);
      
      if (handshakeSuccess) {
        log.i("Successfully connected to Bismuth peer: $peerIp");
        EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: "$peerIp:$P2P_PORT (P2P)"
        ));
        return socket;
      } else {
        socket.destroy();
        return null;
      }
    } catch (e) {
      log.d("Failed to connect to peer $peerIp: $e");
      return null;
    }
  }

  // Create a fresh connection for balance operations
  Future<Socket?> _connectForBalance(String peerIp) async {
    try {
      log.d("Creating fresh connection to Bismuth peer: $peerIp:$P2P_PORT");
      
      Socket socket = await Socket.connect(
        peerIp, 
        P2P_PORT,
        timeout: Duration(seconds: 3)
      );
      
      // Perform version handshake on fresh socket
      bool handshakeSuccess = await _doHandshake(socket);
      
      if (handshakeSuccess) {
        log.i("Fresh connection established to Bismuth peer: $peerIp");
        return socket;
      } else {
        socket.destroy();
        return null;
      }
    } catch (e) {
      log.d("Failed to create fresh connection to peer $peerIp: $e");
      return null;
    }
  }

  // Get balance from Bismuth P2P network
  Future<BalanceGetResponse?> getBalance(String address) async {
    Socket? socket;
    
    // Try connecting to peers until one works (use fresh connections)
    for (String peerIp in BOOTSTRAP_PEERS) {
      socket = await _connectForBalance(peerIp);
      if (socket != null) break;
    }
    
    if (socket == null) {
      log.e("Could not connect to any Bismuth peers");
      EventTaxiImpl.singleton().fire(
        ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
      return null;
    }
    
    try {
      // Send balance request
      log.d("Sending balance request for address: $address");
      _sendMessage(socket, "balancegetjson");
      _sendMessage(socket, address);
      
      // Receive balance response
      dynamic response = await _receiveMessage(socket, timeoutSeconds: 10);
      
      log.d("P2P balance response received: $response (${response.runtimeType})");
      
      if (response is Map<String, dynamic>) {
        BalanceGetResponse balanceResponse = BalanceGetResponse(
          address: address,
          balance: response['balance']?.toString() ?? '0',
          totalCredits: response['credit']?.toString() ?? '0', 
          totalDebits: response['debit']?.toString() ?? '0',
          totalFees: response['fees']?.toString() ?? '0',
          totalRewards: response['rewards']?.toString() ?? '0',
          balanceNoMempool: response['balance_no_mempool']?.toString() ?? '0',
        );
        
        log.i("Got balance from P2P network: ${balanceResponse.balance} for $address");
        return balanceResponse;
      } else {
        log.e("Unexpected P2P balance response format: $response (${response.runtimeType})");
        return null;
      }
    } catch (e) {
      log.e("P2P balance request failed: $e");
      return null;
    } finally {
      socket?.destroy();
    }
  }

  // Send transaction to Bismuth P2P network
  Future<String?> sendTransaction(Map<String, dynamic> transactionData) async {
    Socket? socket;
    
    // Try connecting to peers until one works  
    for (String peerIp in BOOTSTRAP_PEERS) {
      socket = await _connectToPeer(peerIp);
      if (socket != null) break;
    }
    
    if (socket == null) {
      log.e("Could not connect to any Bismuth peers for transaction");
      return "Network Error: No peers available";
    }
    
    try {
      // Send transaction
      _sendMessage(socket, "mpinsert"); 
      _sendMessage(socket, transactionData);
      
      // Receive response
      dynamic response = await _receiveMessage(socket, timeoutSeconds: 15);
      
      log.i("Transaction response from P2P: $response");
      return response?.toString() ?? "Unknown response";
      
    } catch (e) {
      log.e("P2P transaction failed: $e");
      return "Error: $e";
    } finally {
      socket?.destroy();
    }
  }

  // Get transaction history from Bismuth P2P network
  Future<List<List<dynamic>>?> getTransactionHistory(String address, int limit) async {
    Socket? socket;
    
    // Try connecting to peers until one works (use fresh connections)
    for (String peerIp in BOOTSTRAP_PEERS) {
      socket = await _connectForBalance(peerIp);
      if (socket != null) break;
    }
    
    if (socket == null) {
      log.e("Could not connect to any Bismuth peers for transaction history");
      return null;
    }
    
    try {
      log.d("Sending transaction history request for address: $address, limit: $limit");
      
      // Send blockchain transactions request
      _sendMessage(socket, "addlistlimjson");
      _sendMessage(socket, address);
      _sendMessage(socket, limit.toString());
      
      // Receive blockchain transactions response  
      dynamic blockchainResponse = await _receiveMessage(socket, timeoutSeconds: 15);
      log.d("P2P blockchain transactions response: ${blockchainResponse?.toString().substring(0, blockchainResponse.toString().length > 200 ? 200 : blockchainResponse.toString().length)}...");
      
      List<List<dynamic>> blockchainTxs = [];
      if (blockchainResponse is List) {
        blockchainTxs = List<List<dynamic>>.from(blockchainResponse);
      }
      
      log.i("Got ${blockchainTxs.length} blockchain transactions from P2P for $address");
      return blockchainTxs;
      
    } catch (e) {
      log.e("P2P transaction history request failed: $e");
      return null;
    } finally {
      socket?.destroy();
    }
  }

  // Get mempool transactions from Bismuth P2P network
  Future<List<List<dynamic>>?> getMempoolTransactions(String address) async {
    Socket? socket;
    
    // Try connecting to peers until one works
    for (String peerIp in BOOTSTRAP_PEERS) {
      socket = await _connectToPeer(peerIp);
      if (socket != null) break;
    }
    
    if (socket == null) {
      log.e("Could not connect to any Bismuth peers for mempool");
      return null;
    }
    
    try {
      log.d("Sending mempool request for address: $address");
      
      // Send mempool transactions request
      _sendMessage(socket, "mpgetfor");
      _sendMessage(socket, address);
      
      // Receive mempool transactions response
      dynamic mempoolResponse = await _receiveMessage(socket, timeoutSeconds: 15);
      log.d("P2P mempool transactions response: ${mempoolResponse?.toString().substring(0, mempoolResponse.toString().length > 200 ? 200 : mempoolResponse.toString().length)}...");
      
      List<List<dynamic>> mempoolTxs = [];
      if (mempoolResponse is List) {
        mempoolTxs = List<List<dynamic>>.from(mempoolResponse);
      }
      
      log.i("Got ${mempoolTxs.length} mempool transactions from P2P for $address");
      return mempoolTxs;
      
    } catch (e) {
      log.e("P2P mempool request failed: $e");
      return null;
    } finally {
      socket?.destroy();
    }
  }

  // Get network status from a peer
  Future<Map<String, dynamic>?> getNetworkStatus() async {
    Socket? socket;
    
    for (String peerIp in BOOTSTRAP_PEERS) {
      socket = await _connectToPeer(peerIp);
      if (socket != null) break;
    }
    
    if (socket == null) {
      return null;
    }
    
    try {
      _sendMessage(socket, "statusjson");
      dynamic response = await _receiveMessage(socket);
      
      if (response is Map<String, dynamic>) {
        log.i("Network status: blocks=${response['blocks']}, connections=${response['connections']}");
        return response;
      }
      return null;
    } catch (e) {
      log.e("Failed to get network status: $e");
      return null;
    } finally {
      socket?.destroy();
    }
  }
}