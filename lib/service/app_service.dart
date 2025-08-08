// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:diacritic/diacritic.dart';
import 'package:event_taxi/event_taxi.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

// Project imports:
import 'package:my_bismuth_wallet/bus/events.dart';
import 'package:my_bismuth_wallet/network/model/request/send_tx_request.dart';
import 'package:my_bismuth_wallet/network/model/response/addlistlim_response.dart';
import 'package:my_bismuth_wallet/network/model/response/address_txs_response.dart';
import 'package:my_bismuth_wallet/network/model/response/alias_get_response.dart';
import 'package:my_bismuth_wallet/network/model/response/balance_get_response.dart';
import 'package:my_bismuth_wallet/network/model/response/servers_wallet_legacy.dart';
import 'package:my_bismuth_wallet/network/model/response/wstatusget_response.dart';
import 'package:my_bismuth_wallet/service/bismuth_p2p_service.dart';
import 'package:my_bismuth_wallet/service/http_service.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:web_socket_channel/io.dart';

class AppService {
  final Logger log = sl.get<Logger>();

  // Lock instance for synchronization
  String allMessages = "";

  String? getLengthBuffer(String? message) {
    return message == null ? null : message.length.toString().padLeft(10, '0');
  }

  // Helper method to process buffered data and extract complete messages
  List<String> processBuffer(Uint8List data, StringBuffer buffer) {
    List<String> completeMessages = [];
    
    // Add new data to buffer (without trim to preserve exact data)
    buffer.write(String.fromCharCodes(data));
    String bufferContent = buffer.toString();
    
    // Process all complete messages in the buffer
    while (bufferContent.length >= 10) {
      // Try to parse the length header
      String lengthStr = bufferContent.substring(0, 10);
      int? messageLength = int.tryParse(lengthStr);
      
      if (messageLength == null) {
        // Invalid length header, try to recover by finding next valid header
        log.e("Invalid length header: $lengthStr");
        // Skip one character and try again
        bufferContent = bufferContent.substring(1);
        continue;
      }
      
      // Check if we have the complete message
      if (bufferContent.length >= 10 + messageLength) {
        // Extract the complete message
        String message = bufferContent.substring(10, 10 + messageLength);
        completeMessages.add(message);
        
        // Remove processed message from buffer
        bufferContent = bufferContent.substring(10 + messageLength);
      } else {
        // Message is incomplete, wait for more data
        break;
      }
    }
    
    // Update buffer with remaining data
    buffer.clear();
    buffer.write(bufferContent);
    
    return completeMessages;
  }

  Future<void> getWStatusGetResponse() async {
    log.d("getWStatusGetResponse");

    try {
      ServerWalletLegacyResponse serverWalletLegacyResponse =
          await sl.get<HttpService>().getBestServerWalletLegacyResponse();
      
      log.d("Connecting to ${serverWalletLegacyResponse.ip}:${serverWalletLegacyResponse.port}");
      
      IOWebSocketChannel? _webSocket;
      Socket? _socket;
      if (kIsWeb) {
        _webSocket = IOWebSocketChannel.connect(
            'ws://${serverWalletLegacyResponse.ip}:${serverWalletLegacyResponse.port}');
      } else {
        _socket = await Socket.connect(
            serverWalletLegacyResponse.ip, serverWalletLegacyResponse.port,
            timeout: Duration(seconds: 5));
      }

      EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: serverWalletLegacyResponse.ip +
              ":" +
              serverWalletLegacyResponse.port.toString()));

      //Establish the onData, and onDone callbacks
      StringBuffer messageBuffer = StringBuffer();
      
      if (kIsWeb) {
        _webSocket?.stream.listen((data) {
          if (data != null) {
            List<String> messages = processBuffer(data is Uint8List ? data : Uint8List.fromList(data.toString().codeUnits), messageBuffer);
            for (String message in messages) {
              try {
                log.d("Received wstatusget response: $message");
                WStatusGetResponse response = wStatusGetResponseFromJson(message);
                EventTaxiImpl.singleton().fire(WStatusGetEvent(response: response));
              } catch (e) {
                log.e("Failed to parse wstatusget response: $e\nResponse: $message");
              }
            }
          }
        }, onError: ((error, StackTrace trace) {
          log.e("WebSocket error: $error");
        }), onDone: () {
          log.d("WebSocket connection closed");
          _socket?.destroy();
        }, cancelOnError: false);
      } else {
        _socket!.listen((Uint8List data) {
          List<String> messages = processBuffer(data, messageBuffer);
          for (String message in messages) {
            try {
              log.d("Received wstatusget response: $message");
              WStatusGetResponse response = wStatusGetResponseFromJson(message);
              EventTaxiImpl.singleton().fire(WStatusGetEvent(response: response));
            } catch (e) {
              log.e("Failed to parse wstatusget response: $e\nResponse: $message");
            }
          }
        }, onError: ((error, StackTrace trace) {
          log.e("Socket error: $error");
        }), onDone: () {
          log.d("Socket connection closed");
          _socket?.destroy();
        }, cancelOnError: false);
      }

      //Send the request
      String method = '"wstatusget"';
      String request = (getLengthBuffer(method) ?? '') + method;
      log.d("Sending request: $request");

      if (kIsWeb) {
        _webSocket?.sink.add(request);
      } else {
        _socket?.write(request);
      }
    } catch (e) {
      log.e("Socket connection failed: ${e.toString()}");
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
    }
  }

  Future<void> getAlias(String address) async {
    log.d("getAlias for address: $address");

    try {
      ServerWalletLegacyResponse serverWalletLegacyResponse =
          await sl.get<HttpService>().getBestServerWalletLegacyResponse();
      Socket _socket = await Socket.connect(
          serverWalletLegacyResponse.ip, serverWalletLegacyResponse.port,
          timeout: Duration(seconds: 5));

      EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: serverWalletLegacyResponse.ip +
              ":" +
              serverWalletLegacyResponse.port.toString()));

      //Establish the onData, and onDone callbacks
      StringBuffer messageBuffer = StringBuffer();
      _socket.listen((Uint8List data) {
        List<String> messages = processBuffer(data, messageBuffer);
        for (String message in messages) {
          try {
            log.d("Received alias response: $message");
            List alias = aliasGetResponseFromJson(message);
            EventTaxiImpl.singleton().fire(AliasListEvent(response: alias));
          } catch (e) {
            log.e("Failed to parse alias response: $e\nResponse: $message");
          }
        }
      }, onError: ((error, StackTrace trace) {
        log.e("Socket error: $error");
      }), onDone: () {
        log.d("Socket connection closed");
        _socket.destroy();
      }, cancelOnError: false);

      //Send the request
      String method = '"aliasget"';
      String param = '"' + address + '"';
      String request = (getLengthBuffer(method) ?? '') + method + (getLengthBuffer(param) ?? '') + param;
      log.d("Sending request: $request");
      
      _socket.write(request);
    } catch (e) {
      log.e("Socket connection failed: ${e.toString()}");
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
    }
  }

  double getFeesEstimation(String openfield, String operation) {
    const double FEE_BASE = 0.01;
    double fees = FEE_BASE;
    fees += (openfield.length / 100000);
    if (openfield.startsWith("alias=")) {
      fees += 1;
    }
    if (operation == "token:issue") {
      fees += 10;
    }
    if (operation == "alias:register") {
      fees += 1;
    }
  
    log.d("getFeesEstimation: $fees");
    return fees;
  }

  Future<void> getAddressTxsResponse(String address, int limit) async {
    log.d("getAddressTxsResponse for address: $address using P2P network, limit: $limit");
    
    AddressTxsResponse addressTxsResponse = new AddressTxsResponse();

    addressTxsResponse.tokens =
        await sl.get<HttpService>().getTokensBalance(address);

    addressTxsResponse.result = <AddressTxsResponseResult>[];

    try {
      // Use P2P service to get real-time transaction history from Bismuth network
      BismuthP2PService p2pService = BismuthP2PService();
      
      // Get both mempool and blockchain transactions via P2P
      List<List<dynamic>>? mempoolTxs = await p2pService.getMempoolTransactions(address);
      List<List<dynamic>>? blockchainTxs = await p2pService.getTransactionHistory(address, limit);
      
      if (mempoolTxs != null || blockchainTxs != null) {
        // Combined transaction list
        List<List<dynamic>> allTxs = [];
        if (mempoolTxs != null) allTxs.addAll(mempoolTxs);
        if (blockchainTxs != null) allTxs.addAll(blockchainTxs);
        
        // Fire transactions list event for UI
        EventTaxiImpl.singleton().fire(TransactionsListEvent(response: allTxs));
        
        // Convert to AddressTxsResponseResult format
        for (int i = allTxs.length - 1; i >= 0; i--) {
          AddressTxsResponseResult addressTxResponse = new AddressTxsResponseResult();
          addressTxResponse.populate(allTxs[i], address);
          addressTxResponse.getBisToken();
          addressTxsResponse.result?.add(addressTxResponse);
        }
        
        log.i("Transaction history retrieved via P2P: ${allTxs.length} total transactions for $address");
        return;
      }
    } catch (e) {
      log.e("P2P transaction history fetch failed: ${e.toString()}");
    }
    
    // If P2P fails, fire error event
    EventTaxiImpl.singleton().fire(
        ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
    
    EventTaxiImpl.singleton().fire(NetworkErrorEvent(
      errorType: NetworkErrorType.TRANSACTION_HISTORY_FAILED,
      message: "Failed to load transaction history from Bismuth P2P network. Please check your internet connection.",
      operation: "Load Transactions",
      canRetry: true,
    ));
  }

  Future<void> getBalanceGetResponse(String address, bool activeBus) async {
    log.d("getBalanceGetResponse for address: $address using P2P network");
    
    try {
      // Use P2P service to get real-time balance from Bismuth network
      BismuthP2PService p2pService = BismuthP2PService();
      BalanceGetResponse? balanceResponse = await p2pService.getBalance(address);
      
      if (balanceResponse != null) {
        if (activeBus) {
          EventTaxiImpl.singleton().fire(BalanceGetEvent(response: balanceResponse));
        }
        log.i("Balance retrieved via P2P: ${balanceResponse.balance} for $address");
        return;
      }
    } catch (e) {
      log.e("P2P balance fetch failed: ${e.toString()}");
    }
    
    // If P2P fails, fire error event
    EventTaxiImpl.singleton().fire(
        ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
    
    EventTaxiImpl.singleton().fire(NetworkErrorEvent(
      errorType: NetworkErrorType.BALANCE_FETCH_FAILED,
      message: "Failed to fetch wallet balance from Bismuth P2P network. Please check your internet connection.",
      operation: "Balance Update",
      canRetry: true,
    ));
  }

  Future<void> sendTx(
      String address,
      String amount,
      String destination,
      String openfield,
      String operation,
      String publicKey,
      String privateKey) async {
    log.d("sendTx from: $address to: $destination amount: $amount");
    
    SendTxRequest sendTxRequest = SendTxRequest(
      id: 0,
      tx: Tx(
        address: '',
        recipient: '',
        amount: '',
        operation: '',
        openfield: '',
        timestamp: '',
      ),
      publicKey: '',
      signature: '',
      buffer: '',
      websocketCommand: '',
    );
    Tx tx = Tx(
      address: '',
      recipient: '',
      amount: '',
      operation: '',
      openfield: '',
      timestamp: '',
    );

    try {
      // Build transaction data
      // Substract 4 sec to limit the issue with future tx
      DateTime timeBefore4sec = DateTime.now().subtract(new Duration(seconds: 4));
      tx.timestamp = timeBefore4sec
              .toUtc()
              .microsecondsSinceEpoch
              .toString()
              .substring(0, 10) +
          "." +
          timeBefore4sec
              .toUtc()
              .microsecondsSinceEpoch
              .toString()
              .substring(10, 12);
      tx.address = address;
      tx.recipient = destination;
      tx.amount = (double.tryParse(amount) ?? 0.0).toStringAsFixed(8);
      tx.operation = removeDiacritics(operation);
      tx.openfield = removeDiacritics(openfield);

      sendTxRequest.id = 0;
      sendTxRequest.tx = tx;
      sendTxRequest.buffer = tx.buildBufferValue();
      sendTxRequest.publicKey = publicKey;
      sendTxRequest.buildSignature(privateKey);
      sendTxRequest.websocketCommand = "";

      // Use P2P service to send transaction
      BismuthP2PService p2pService = BismuthP2PService();
      
      // Convert to map format for P2P transmission
      Map<String, dynamic> transactionData = {
        'timestamp': tx.timestamp,
        'address': tx.address,
        'recipient': tx.recipient,
        'amount': tx.amount,
        'signature': sendTxRequest.signature,
        'public_key': sendTxRequest.publicKey,
        'operation': tx.operation,
        'openfield': tx.openfield,
      };
      
      String? result = await p2pService.sendTransaction(transactionData);
      
      if (result != null) {
        if (result.toLowerCase().contains("success") || result.contains("ok")) {
          EventTaxiImpl.singleton().fire(TransactionSendEvent(response: "Success"));
          log.i("Transaction sent successfully via P2P: $result");
        } else {
          EventTaxiImpl.singleton().fire(TransactionSendEvent(response: result));
          log.w("Transaction response via P2P: $result");
        }
        return;
      }
    } catch (e) {
      log.e("P2P send transaction failed: ${e.toString()}");
      
      // Fire connection status event
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
      
      // Fire network error event for user feedback  
      EventTaxiImpl.singleton().fire(NetworkErrorEvent(
        errorType: NetworkErrorType.SEND_TRANSACTION_FAILED,
        message: "Failed to send transaction via P2P network. Please check your internet connection and try again.",
        operation: "Send Transaction",
        canRetry: true,
      ));
      
      // Also fire transaction send event with error
      EventTaxiImpl.singleton().fire(TransactionSendEvent(response: "P2P Network Error"));
    }
  }
}