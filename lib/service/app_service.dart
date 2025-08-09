

// Dart imports:
import 'dart:async';
import 'dart:io';

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
// import 'package:my_bismuth_wallet/network/model/response/mpinsert_response.dart'; // Deleted file
import 'package:my_bismuth_wallet/network/model/response/servers_wallet_legacy.dart';
import 'package:my_bismuth_wallet/network/model/response/wstatusget_response.dart';
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

  Future<void> getWStatusGetResponse() async {
    //print("getWStatusGetResponse");

    try {
      ServerWalletLegacyResponse serverWalletLegacyResponse =
          await sl.get<HttpService>().getBestServerWalletLegacyResponse();
      IOWebSocketChannel? _webSocket;
      Socket? _socket;
      if (kIsWeb) {
        _webSocket = IOWebSocketChannel.connect(
            serverWalletLegacyResponse.ip +
                ':' +
                serverWalletLegacyResponse.port.toString());
      } else {
        _socket = await Socket.connect(
            serverWalletLegacyResponse.ip, serverWalletLegacyResponse.port,
            timeout: Duration(seconds: 3));
      }

      EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: serverWalletLegacyResponse.ip +
              ":" +
              serverWalletLegacyResponse.port.toString()));

      //Establish the onData, and onDone callbacks
      String message = "";
      if (kIsWeb) {
        _webSocket?.stream.listen((data) {
          if (data != null) {
            message += new String.fromCharCodes(data).trim();
            if (message.length >= 10 &&
                int.tryParse(message.substring(0, 10)) != null &&
                message.length ==
                    10 + (int.tryParse(message.substring(0, 10)) ?? 0)) {
              int? parsedLength = int.tryParse(message.substring(0, 10));
              if (parsedLength != null) {
                message = message.substring(10, 10 + parsedLength);
                // Process the status response
                wStatusGetResponseFromJson(message);
              }
            }
          }
        }, onError: ((error, StackTrace trace) {
          //print("Error");
        }), onDone: () {
          //print("Done");
          _socket?.destroy();
        }, cancelOnError: false);
      } else {
        _socket!.listen((data) {
          message += new String.fromCharCodes(data).trim();
          if (message.length >= 10 &&
              int.tryParse(message.substring(0, 10)) != null &&
              message.length ==
                  10 + (int.tryParse(message.substring(0, 10)) ?? 0)) {
            int? parsedLength = int.tryParse(message.substring(0, 10));
            if (parsedLength != null) {
              message = message.substring(10, 10 + parsedLength);
              // Process the status response
              wStatusGetResponseFromJson(message);
            }
          }
                  }, onError: ((error, StackTrace trace) {
          //print("Error");
        }), onDone: () {
          //print("Done");
          _socket?.destroy();
        }, cancelOnError: false);
      }

      //Send the request
      String method = '"wstatusget"';

      if (kIsWeb) {
        _webSocket?.sink.add((getLengthBuffer(method) ?? '') + method);
      } else {
        _socket?.write((getLengthBuffer(method) ?? '') + method);
      }
        } catch (e) {
      //print("pb socket" + e.toString());
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
    } finally {}
  }

  Future<void> getAlias(String address) async {
    //print("getAlias");

    try {
      ServerWalletLegacyResponse serverWalletLegacyResponse =
          await sl.get<HttpService>().getBestServerWalletLegacyResponse();
      Socket _socket = await Socket.connect(
          serverWalletLegacyResponse.ip, serverWalletLegacyResponse.port,
          timeout: Duration(seconds: 3));

      EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: serverWalletLegacyResponse.ip +
              ":" +
              serverWalletLegacyResponse.port.toString()));

      //Establish the onData, and onDone callbacks
      String message = "";
      _socket.listen((data) {
        message += new String.fromCharCodes(data).trim();
        if (message.length >= 10 &&
            int.tryParse(message.substring(0, 10)) != null &&
            message.length == 10 + (int.tryParse(message.substring(0, 10)) ?? 0)) {
          int? parsedLength = int.tryParse(message.substring(0, 10));
          if (parsedLength != null) {
            message = message.substring(10, 10 + parsedLength);
          }
          List alias = aliasGetResponseFromJson(message);
          //print("fire AliasListEvent");
          EventTaxiImpl.singleton().fire(AliasListEvent(response: alias));
        }
              }, onError: ((error, StackTrace trace) {
        //print("Error");
      }), onDone: () {
        //print("Done");
        _socket.destroy();
      }, cancelOnError: false);

      //Send the request
      String method = '"aliasget"';
      String param = '"' + address + '"';

      _socket.write(
          (getLengthBuffer(method) ?? '') + method + (getLengthBuffer(param) ?? '') + param);
        } catch (e) {
      //print("pb socket" + e.toString());
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
    } finally {}
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
  
    //print("getFeesEstimation: " + fees.toString());
    return fees;
  }

  Future<void> getAddressTxsResponse(String address, int limit) async {
    AddressTxsResponse addressTxsResponse = new AddressTxsResponse();

    addressTxsResponse.tokens =
        await sl.get<HttpService>().getTokensBalance(address);

    addressTxsResponse.result = <AddressTxsResponseResult>[];

    try {
      ServerWalletLegacyResponse serverWalletLegacyResponse =
          await sl.get<HttpService>().getBestServerWalletLegacyResponse();

      IOWebSocketChannel? _webSocket;
      Socket? _socket;
      if (kIsWeb) {
        _webSocket = IOWebSocketChannel.connect(
            serverWalletLegacyResponse.ip +
                ':' +
                serverWalletLegacyResponse.port.toString());
      } else {
        _socket = await Socket.connect(
            serverWalletLegacyResponse.ip, serverWalletLegacyResponse.port,
            timeout: Duration(seconds: 3));
      }

      EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: serverWalletLegacyResponse.ip +
              ":" +
              serverWalletLegacyResponse.port.toString()));

      //Establish the onData, and onDone callbacks
      String message = "";
      if (kIsWeb) {
        _webSocket?.stream.listen((data) {
          if (data != null) {
            message += new String.fromCharCodes(data).trim();
            //print("TX History response : " + message);
            //print("TX History response length : " + message.length.toString());
            if (message.length >= 10 &&
                int.tryParse(message.substring(0, 10)) != null) {
              // Parse mempool tx
              int? mempoolTxListStringLength =
                  int.tryParse(message.substring(0, 10));
              if (mempoolTxListStringLength == null) return;
              if (message.length >= 10 + mempoolTxListStringLength) {
                String mempoolTxListString =
                    message.substring(10, 10 + mempoolTxListStringLength);
                int mempoolTxListStringEnd = 10 + mempoolTxListStringLength;
                print(
                    "getAddressTxsResponse (memPool) : " + mempoolTxListString);
                List mempoolTxs =
                    addlistlimResponseFromJson(mempoolTxListString);

                List blockChainTxs = [];
                // Parse blockchain tx if available
                print("Message length: ${message.length}, mempoolTxListStringEnd: $mempoolTxListStringEnd");
                if (message.length > mempoolTxListStringEnd) {
                  // Check if we have at least 10 bytes for the blockchain length
                  if (message.length >= mempoolTxListStringEnd + 10) {
                    String lengthStr = message.substring(mempoolTxListStringEnd,
                            mempoolTxListStringEnd + 10);
                    print("Blockchain length string: '$lengthStr'");
                    int? blockchainTxListStringLength = int.tryParse(lengthStr);
                    print("Parsed blockchain length: $blockchainTxListStringLength");
                    print("Required message length: ${mempoolTxListStringEnd + 10 + (blockchainTxListStringLength ?? 0)}");
                    print("Actual message length: ${message.length}");
                    
                    // Try to read what we have even if it's truncated
                    if (blockchainTxListStringLength != null && blockchainTxListStringLength > 0) {
                      int availableLength = message.length - mempoolTxListStringEnd - 10;
                      int readLength = availableLength < blockchainTxListStringLength ? availableLength : blockchainTxListStringLength;
                      if (readLength > 0) {
                        String blockchainTxListString = message.substring(
                            mempoolTxListStringEnd + 10,
                            mempoolTxListStringEnd + 10 + readLength);
                        print("getAddressTxsResponse (blockchain) : " +
                            blockchainTxListString);
                        try {
                          blockChainTxs =
                              addlistlimResponseFromJson(blockchainTxListString);
                        } catch (e) {
                          print("Error parsing blockchain transactions (truncated data): $e");
                          // Try to parse what we can from the truncated data
                          // The data might be cut off but still contain valid transactions
                        }
                      }
                    }
                  }
                }

                // Combine transactions and always fire event
                List txs = [];
                txs.addAll(mempoolTxs);
                txs.addAll(blockChainTxs);

                print("Total transactions found: mempool=" + mempoolTxs.length.toString() + " blockchain=" + blockChainTxs.length.toString() + " combined=" + txs.length.toString());

                // Always fire the event, even if empty
                EventTaxiImpl.singleton()
                    .fire(TransactionsListEvent(response: txs));
                    
                for (int i = txs.length - 1; i >= 0; i--) {
                  AddressTxsResponseResult addressTxResponse =
                      new AddressTxsResponseResult();
                  addressTxResponse.populate(txs[i], address);
                  addressTxResponse.getBisToken();
                  addressTxsResponse.result?.add(addressTxResponse);
                }
              }
            } else {
              //print("response length ko : " + message.length.toString());
            }
          }
        }, onError: ((error, StackTrace trace) {
          //print("Error");
        }), onDone: () {
          //print("Done");
          _socket?.destroy();
        }, cancelOnError: false);
      } else {
        _socket?.listen((data) {
          message += new String.fromCharCodes(data).trim();
          //print("TX History response : " + message);
          //print("TX History response length : " + message.length.toString());
          if (message.length >= 10 &&
              int.tryParse(message.substring(0, 10)) != null) {
            // Parse mempool tx
            int? mempoolTxListStringLength =
                int.tryParse(message.substring(0, 10));
            if (mempoolTxListStringLength == null) return;
            if (message.length >= 10 + mempoolTxListStringLength) {
              String mempoolTxListString =
                  message.substring(10, 10 + mempoolTxListStringLength);
              int mempoolTxListStringEnd = 10 + mempoolTxListStringLength;
              print(
                  "getAddressTxsResponse (memPool) : " + mempoolTxListString);
              List mempoolTxs =
                  addlistlimResponseFromJson(mempoolTxListString);

              List blockChainTxs = [];
              // Parse blockchain tx if available
              print("Message length: ${message.length}, mempoolTxListStringEnd: $mempoolTxListStringEnd");
              if (message.length > mempoolTxListStringEnd) {
                // Check if we have at least 10 bytes for the blockchain length
                if (message.length >= mempoolTxListStringEnd + 10) {
                  String lengthStr = message.substring(mempoolTxListStringEnd,
                          mempoolTxListStringEnd + 10);
                  print("Blockchain length string: '$lengthStr'");
                  int? blockchainTxListStringLength = int.tryParse(lengthStr);
                  print("Parsed blockchain length: $blockchainTxListStringLength");
                  print("Required message length: ${mempoolTxListStringEnd + 10 + (blockchainTxListStringLength ?? 0)}");
                  print("Actual message length: ${message.length}");
                  
                  // Try to read what we have even if it's truncated
                  if (blockchainTxListStringLength != null && blockchainTxListStringLength > 0) {
                    int availableLength = message.length - mempoolTxListStringEnd - 10;
                    int readLength = availableLength < blockchainTxListStringLength ? availableLength : blockchainTxListStringLength;
                    if (readLength > 0) {
                      String blockchainTxListString = message.substring(
                          mempoolTxListStringEnd + 10,
                          mempoolTxListStringEnd + 10 + readLength);
                      print("getAddressTxsResponse (blockchain) : " +
                          blockchainTxListString);
                      try {
                        blockChainTxs =
                            addlistlimResponseFromJson(blockchainTxListString);
                      } catch (e) {
                        print("Error parsing blockchain transactions (truncated data): $e");
                        // Try to parse what we can from the truncated data
                        // The data might be cut off but still contain valid transactions
                      }
                    }
                  }
                }
              }

              // Combine transactions and always fire event
              List txs = [];
              txs.addAll(mempoolTxs);
              txs.addAll(blockChainTxs);

              print("Total transactions found: mempool=" + mempoolTxs.length.toString() + " blockchain=" + blockChainTxs.length.toString() + " combined=" + txs.length.toString());

              // Always fire the event, even if empty
              EventTaxiImpl.singleton()
                  .fire(TransactionsListEvent(response: txs));
                  
              for (int i = txs.length - 1; i >= 0; i--) {
                AddressTxsResponseResult addressTxResponse =
                    new AddressTxsResponseResult();
                addressTxResponse.populate(txs[i], address);
                addressTxResponse.getBisToken();
                addressTxsResponse.result?.add(addressTxResponse);
              }
            }
          } else {
            //print("response length ko : " + message.length.toString());
          }
                  }, onError: ((error, StackTrace trace) {
          //print("Error");
        }), onDone: () {
          //print("Done");
          _socket?.destroy();
        }, cancelOnError: false);
      }

      //Send the request
      String method = '"addlistlim"';
      String param1 = '"' + address + '"';
      String param2 = '"' + limit.toString() + '"';
      String method2 = '"mpgetfor"';
      if (kIsWeb) {
        _webSocket?.sink.add((getLengthBuffer(method2) ?? '') +
          method2 +
          (getLengthBuffer(param1) ?? '') +
          param1 +
          (getLengthBuffer(method) ?? '') +
          method +
          (getLengthBuffer(param1) ?? '') +
          param1 +
          (getLengthBuffer(param2) ?? '') +
          param2);
      } else {
        _socket?.write((getLengthBuffer(method2) ?? '') +
          method2 +
          (getLengthBuffer(param1) ?? '') +
          param1 +
          (getLengthBuffer(method) ?? '') +
          method +
          (getLengthBuffer(param1) ?? '') +
          param1 +
          (getLengthBuffer(param2) ?? '') +
          param2);
      }
        } catch (e) {
      log.e("Transaction history fetch failed: ${e.toString()}");
      
      // Fire connection status event
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
      
      // Fire network error event for user feedback
      EventTaxiImpl.singleton().fire(NetworkErrorEvent(
        errorType: NetworkErrorType.TRANSACTION_HISTORY_FAILED,
        message: "Failed to load transaction history. Please check your internet connection.",
        operation: "Load Transactions",
        canRetry: true,
      ));
    } finally {}
  }

  Future<void> getBalanceGetResponse(String address, bool activeBus) async {
    BalanceGetResponse balanceGetResponse = BalanceGetResponse(
      address: '',
      balance: '0',
      balanceNoMempool: '0',
      totalCredits: '0',
      totalDebits: '0',
      totalFees: '0',
      totalRewards: '0',
    );

    try {
      ServerWalletLegacyResponse serverWalletLegacyResponse =
          await sl.get<HttpService>().getBestServerWalletLegacyResponse();
      IOWebSocketChannel? _webSocket;
      Socket? _socket;
      if (kIsWeb) {
        _webSocket = IOWebSocketChannel.connect(
            serverWalletLegacyResponse.ip +
                ':' +
                serverWalletLegacyResponse.port.toString());
      } else {
        _socket = await Socket.connect(
            serverWalletLegacyResponse.ip, serverWalletLegacyResponse.port,
            timeout: Duration(seconds: 3));
      }

      EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: serverWalletLegacyResponse.ip +
              ":" +
              serverWalletLegacyResponse.port.toString()));

      //Establish the onData, and onDone callbacks
      String message = "";
      if (kIsWeb) {
        _webSocket?.stream.listen((data) {
          if (data != null) {
            message += new String.fromCharCodes(data).trim();
            if (message.length >= 10 &&
                int.tryParse(message.substring(0, 10)) != null &&
                message.length ==
                    10 + (int.tryParse(message.substring(0, 10)) ?? 0)) {
              int? parsedLength = int.tryParse(message.substring(0, 10));
              if (parsedLength != null) {
                message = message.substring(10, 10 + parsedLength);
              }
              balanceGetResponse = balanceGetResponseFromJson(message);
              balanceGetResponse.address = address;
              //print(message);
              if (activeBus) {
                EventTaxiImpl.singleton()
                    .fire(BalanceGetEvent(response: balanceGetResponse));
              }
            }
          }
        }, onError: ((error, StackTrace trace) {
          //print("Error");
        }), onDone: () {
          //print("Done");
          _socket?.destroy();
        }, cancelOnError: false);
      } else {
        _socket?.listen((data) {
          message += new String.fromCharCodes(data).trim();
          if (message.length >= 10 &&
              int.tryParse(message.substring(0, 10)) != null &&
              message.length ==
                  10 + (int.tryParse(message.substring(0, 10)) ?? 0)) {
            int? parsedLength = int.tryParse(message.substring(0, 10));
            if (parsedLength != null) {
              message = message.substring(10, 10 + parsedLength);
            }
            balanceGetResponse = balanceGetResponseFromJson(message);
            balanceGetResponse.address = address;
            //print(message);
            if (activeBus) {
              EventTaxiImpl.singleton()
                  .fire(BalanceGetEvent(response: balanceGetResponse));
            }
          }
                  }, onError: ((error, StackTrace trace) {
          //print("Error");
        }), onDone: () {
          //print("Done");
          _socket?.destroy();
        }, cancelOnError: false);
      }

      //Send the request
      String method = '"balancegetjson"';
      String param = '"' + address + '"';

      if (kIsWeb) {
        _webSocket?.sink.add((getLengthBuffer(method) ?? '') + method + (getLengthBuffer(param) ?? '') + param);
      } else {
        _socket?.write((getLengthBuffer(method) ?? '') + method + (getLengthBuffer(param) ?? '') + param);
      }
        } catch (e) {
      log.e("Balance fetch failed: ${e.toString()}");
      
      // Fire connection status event
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
      
      // Fire network error event for user feedback
      EventTaxiImpl.singleton().fire(NetworkErrorEvent(
        errorType: NetworkErrorType.BALANCE_FETCH_FAILED,
        message: "Failed to fetch wallet balance. Please check your internet connection.",
        operation: "Balance Update",
        canRetry: true,
      ));
    } finally {}
  }

  Future<void> sendTx(
      String address,
      String amount,
      String destination,
      String openfield,
      String operation,
      String publicKey,
      String privateKey) async {
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
    //print("address : " + address);
    //print("amount : " + amount);
    //print("destination : " + destination);
    //print("publicKey : " + publicKey);
    //print("privateKey : " + privateKey);

    try {
      ServerWalletLegacyResponse serverWalletLegacyResponse =
          await sl.get<HttpService>().getBestServerWalletLegacyResponse();

      Socket _socket = await Socket.connect(
          serverWalletLegacyResponse.ip, serverWalletLegacyResponse.port,
          timeout: Duration(seconds: 3));

      EventTaxiImpl.singleton().fire(ConnStatusEvent(
          status: ConnectionStatus.CONNECTED,
          server: serverWalletLegacyResponse.ip +
              ":" +
              serverWalletLegacyResponse.port.toString()));

      //print('Connected to: '
      //    '${_socket.remoteAddress.address}:${_socket.remotePort}');
      //Establish the onData, and onDone callbacks
      _socket.listen((data) {
        String message = new String.fromCharCodes(data).trim();
        if (message.length >= 10 &&
            int.tryParse(message.substring(0, 10)) != null &&
            message.length == 10 + (int.tryParse(message.substring(0, 10)) ?? 0)) {
          int? parsedLength = int.tryParse(message.substring(0, 10));
          if (parsedLength != null) {
            message = message.substring(10, 10 + parsedLength);
          }
          //print("Response sendTx : " + message);
          List<String> sendTxResponse = message.split(',');
          
          if (sendTxResponse.length < 4 ||
              sendTxResponse[3].contains("Success") == false) {
            String errorResponse = sendTxResponse.length > 1 ? sendTxResponse[1] : "Unknown Error";
            EventTaxiImpl.singleton()
                .fire(TransactionSendEvent(response: errorResponse));
          } else {
            EventTaxiImpl.singleton()
                .fire(TransactionSendEvent(response: "Success"));
          }
        }
              }, onError: ((error, StackTrace trace) {
        //print("Error");
      }), onDone: () {
        //print("Done");
        _socket.destroy();
      }, cancelOnError: false);

      //Send the request
      // Substract 3 sec to limit the issue with future tx
      DateTime timeBefore4sec =
          DateTime.now().subtract(new Duration(seconds: 4));
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

      String method = '"mpinsert"';
      String param = sendTxRequest.buildCommand();
      String message =
          (getLengthBuffer(method) ?? '') + method + (getLengthBuffer(param) ?? '') + param;
      //print("message: " + message);
      _socket.write(message);
        } catch (e) {
      log.e("Send transaction failed: ${e.toString()}");
      
      // Fire connection status event
      EventTaxiImpl.singleton().fire(
          ConnStatusEvent(status: ConnectionStatus.DISCONNECTED, server: ""));
      
      // Fire network error event for user feedback  
      EventTaxiImpl.singleton().fire(NetworkErrorEvent(
        errorType: NetworkErrorType.SEND_TRANSACTION_FAILED,
        message: "Failed to send transaction. Please check your internet connection and try again.",
        operation: "Send Transaction",
        canRetry: true,
      ));
      
      // Also fire transaction send event with error
      EventTaxiImpl.singleton().fire(TransactionSendEvent(response: "Network Error"));
    } finally {}
  }
}
