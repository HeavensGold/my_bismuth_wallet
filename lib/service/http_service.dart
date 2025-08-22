// Dart imports:
import 'dart:async';
import 'dart:convert';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

// Project imports:
// import 'package:my_bismuth_wallet/model/token_ref.dart'; // Deleted
import 'package:my_bismuth_wallet/network/model/response/address_txs_response.dart';
import 'package:my_bismuth_wallet/network/model/response/servers_wallet_legacy.dart';
// import 'package:my_bismuth_wallet/network/model/response/tokens_balance_get_response.dart'; // Deleted
// import 'package:my_bismuth_wallet/network/model/response/tokens_list_get_response.dart'; // Deleted
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

class HttpService {
  final Logger log = sl.get<Logger>();

  Future<ServerWalletLegacyResponse> getBestServerWalletLegacyResponse() async {
    List<ServerWalletLegacyResponse> serverWalletLegacyResponseList =
        <ServerWalletLegacyResponse>[];
    ServerWalletLegacyResponse serverWalletLegacyResponse =
        ServerWalletLegacyResponse(
      active: true,
      clients: 0,
      ip: '',
      port: 0,
      label: '',
      country: '',
      height: 0,
      version: '',
      totalSlots: 0,
      lastActive: 0,
    );

    String walletServer = await sl.get<SharedPrefsUtil>().getWalletServer();
    if (walletServer != "auto") {
      if (walletServer.split(":").length > 1) {
        serverWalletLegacyResponse.ip = walletServer.split(":")[0];
        serverWalletLegacyResponse.port =
            int.tryParse(walletServer.split(":")[1]) ?? 0;
      }

      return serverWalletLegacyResponse;
    }

    try {
      final http.Response response = await http
          .get(Uri.parse("https://bismuth.world/api/legacy.json"), headers: {
        'content-type': 'application/json',
        'access-Control-Allow-Origin': '*'
      });

      if (response.statusCode == 200) {
        String reply = response.body;
        //print("serverWalletLegacyResponseList=" + reply);
        serverWalletLegacyResponseList =
            serverWalletLegacyResponseFromJson(reply);

        // Best server active with less clients
        serverWalletLegacyResponseList
            .removeWhere((element) => element.active == false);
        serverWalletLegacyResponseList.sort((a, b) {
          return a.clients
              .toString()
              .toLowerCase()
              .compareTo(b.clients.toString().toLowerCase());
        });
        if (serverWalletLegacyResponseList.length > 0) {
          serverWalletLegacyResponse = serverWalletLegacyResponseList[0];
        }
      }
    } catch (e) {
      print(e);
    }
    //print("Server Wallet : " +
    //    serverWalletLegacyResponse.ip +
    //    ":" +
    //    serverWalletLegacyResponse.port.toString());
    return serverWalletLegacyResponse;
  }



  Future<bool> isTokensBalance(String address) async {
    try {
      String tokensApi = await sl.get<SharedPrefsUtil>().getTokensApi();
      Uri uri;
      try {
        uri = Uri.parse(tokensApi + address);
      } catch (FormatException) {
        return false;
      }

      http.Response response = await http.get(uri, headers: {
        'content-type': 'application/json',
        'access-Control-Allow-Origin': '*'
      });

      if (response.statusCode == 200) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<List<BisToken>> getTokensBalance(String address) async {
    List<BisToken> bisTokenList = <BisToken>[];

    try {
      String tokensApi = await sl.get<SharedPrefsUtil>().getTokensApi();

      final http.Response response = await http
          .get(Uri.parse(tokensApi + address), headers: {
        'content-type': 'application/json',
        'access-Control-Allow-Origin': '*'
      });

      if (response.statusCode == 200) {
        String reply = response.body;
        List<dynamic> tokensBalanceGetResponse = json.decode(reply);

        for (int i = 0; i < tokensBalanceGetResponse.length; i++) {
          var tokenData = tokensBalanceGetResponse[i];
          if (tokenData is List && tokenData.length >= 2) {
            BisToken bisToken = BisToken(
              tokenName: tokenData[0]?.toString(),
              tokensQuantity:
                  int.tryParse(tokenData[1]?.toString() ?? '0') ?? 0,
            );
            bisTokenList.add(bisToken);
          }
        }
      }
    } catch (e) {}
    return bisTokenList;
  }

  // Future<List<TokenRef>> getTokensReflist() async {
  //   List<TokenRef> tokensRefList = new List<TokenRef>();

  //   try {
  //     final http.Response response = await http
  //         .get(Uri.parse("https://bismuth.today/api/tokens/"), headers: {
  //       'content-type': 'application/json',
  //       'access-Control-Allow-Origin': '*'
  //     });

  //     if (response.statusCode == 200) {
  //       String reply = response.body;
  //       var tokensRefListGetResponse = tokensListGetResponseFromJson(reply);

  //       for (int i = 0; i < tokensRefListGetResponse.length; i++) {
  //         TokenRef tokenRef = new TokenRef();
  //         tokenRef.token = tokensRefListGetResponse.keys.elementAt(i);
  //         tokenRef.creator = tokensRefListGetResponse.values.elementAt(i)[0];
  //         tokenRef.totalSupply =
  //             tokensRefListGetResponse.values.elementAt(i)[1];
  //         tokenRef.creationDate = DateTime.fromMillisecondsSinceEpoch(
  //             (tokensRefListGetResponse.values.elementAt(i)[2] * 1000).toInt());
  //         tokensRefList.add(tokenRef);
  //       }
  //     }
  //   } catch (e) {}
  //   return [];
  // }

  Future<int> getEggPrice() async {
    int price = 0;
    try {
      final http.Response response = await http.get(
          Uri.parse("https://dragginator.com/api/info.php?type=price"),
          headers: {
            'content-type': 'application/json',
            'access-Control-Allow-Origin': '*'
          });

      if (response.statusCode == 200) {
        String reply = response.body;
        price = int.tryParse(
                reply.replaceAll('[', '').replaceAll(']', '').split(',')[0]) ??
            0;
      }
    } catch (e) {}
    return price;
  }
}
