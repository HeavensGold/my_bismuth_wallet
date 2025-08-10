

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:event_taxi/event_taxi.dart';
import 'package:hex/hex.dart';
import 'package:logger/logger.dart';

// Project imports:
import 'package:my_bismuth_wallet/bus/events.dart';
import 'package:my_bismuth_wallet/model/address.dart';
import 'package:my_bismuth_wallet/model/available_currency.dart';
import 'package:my_bismuth_wallet/model/available_language.dart';
import 'package:my_bismuth_wallet/model/db/appdb.dart';
import 'package:my_bismuth_wallet/model/db/hiveDB.dart';
import 'package:my_bismuth_wallet/model/vault.dart';
import 'package:my_bismuth_wallet/model/wallet.dart';
import 'package:my_bismuth_wallet/network/model/block_types.dart';
import 'package:my_bismuth_wallet/network/model/response/address_txs_response.dart';
import 'package:my_bismuth_wallet/network/model/response/balance_get_response.dart';
import 'package:my_bismuth_wallet/service/app_service.dart';
import 'package:my_bismuth_wallet/service/http_service.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/themes.dart';
import 'package:my_bismuth_wallet/util/app_ffi/apputil.dart';
import 'package:my_bismuth_wallet/util/app_ffi/encrypt/crypter.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

class _InheritedStateContainer extends InheritedWidget {
  // Data is your entire state. In our case just 'User'
  final StateContainerState data;

  // You must pass through a child and your state.
  _InheritedStateContainer({
    Key? key,
    required this.data,
    required Widget child,
  }) : super(key: key, child: child);

  // This is a built in method which you can use to check if
  // any state has changed. If not, no reason to rebuild all the widgets
  // that rely on your state.
  @override
  bool updateShouldNotify(_InheritedStateContainer old) => true;
}

class StateContainer extends StatefulWidget {
  // You must pass through a child.
  final Widget child;

  StateContainer({required this.child});

  // This is the secret sauce. Write your own 'of' method that will behave
  // Exactly like MediaQuery.of and Theme.of
  // It basically says 'get the data from the widget of this type.
  static StateContainerState of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InheritedStateContainer>()
        ?.data ?? (throw Exception('StateContainer not found'));
  }

  @override
  StateContainerState createState() => StateContainerState();
}

/// App InheritedWidget
/// This is where we handle the global state and also where
/// we interact with the server and make requests/handle+propagate responses
///
/// Basically the central hub behind the entire app
class StateContainerState extends State<StateContainer> {
  // Minimum receive = 0.000001
  String receiveThreshold = BigInt.from(10).pow(24).toString();

  AppWallet? wallet;
  String? currencyLocale;
  Locale deviceLocale = const Locale('en', 'US');
  AvailableCurrency curCurrency = AvailableCurrency(AvailableCurrencyEnum.USD);
  LanguageSetting curLanguage = LanguageSetting(AvailableLanguage.DEFAULT);
  BaseTheme curTheme = BismuthTheme();
  // Currently selected account
  Account selectedAccount =
      Account(name: "AB", index: 0, lastAccess: 0, selected: true);
  // Two most recently used accounts
  Account? recentLast;
  Account? recentSecondLast;


  // When wallet is encrypted
  String? encryptedSecret;

  @override
  void initState() {
    super.initState();

    // Register RxBus
    _registerBus();
    
    // Initialize wallet on startup
    Future.delayed(Duration(milliseconds: 100), () async {
      if (mounted) {
        // Try to get the saved selected account
        try {
          String seed = await getSeed();
          Account? savedAccount = await sl.get<DBHelper>().getSelectedAccount(seed);
          if (savedAccount != null) {
            // Initialize wallet with saved account
            updateWallet(account: savedAccount);
          } else {
            // No saved account, get the main account
            Account mainAccount = await sl.get<DBHelper>().getMainAccount(seed);
            updateWallet(account: mainAccount);
          }
        } catch (e) {
          // Error getting seed or account, wallet will be initialized later
          print("Could not initialize wallet on startup: $e");
        }
      }
    });
    // Set currency locale here for the UI to access
    sl.get<SharedPrefsUtil>().getCurrency(deviceLocale).then((currency) {
      setState(() {
        currencyLocale = currency.getLocale().toString();
        curCurrency = currency;
      });
    });
    // Get default language setting
    sl.get<SharedPrefsUtil>().getLanguage().then((language) {
      setState(() {
        curLanguage = language;
      });
    });
  }

  // Subscriptions
  StreamSubscription<BalanceGetEvent>? _balanceGetEventSub;
  StreamSubscription<PriceEvent>? _priceEventSub;
  StreamSubscription<AccountModifiedEvent>? _accountModifiedSub;
  StreamSubscription<TransactionsListEvent>? _transactionsListEventSub;

  // Register RX event listeners
  void _registerBus() {
    _balanceGetEventSub =
        EventTaxiImpl.singleton().registerTo<BalanceGetEvent>().listen((event) {
      //print("listen BalanceGetEvent");
      if (event.response != null) {
        handleAddressResponse(event.response!);
      }
    });

    // Transaction event subscription is now managed in requestUpdate() to avoid duplicates
    
    _priceEventSub =
        EventTaxiImpl.singleton().registerTo<PriceEvent>().listen((event) {
      // PriceResponse's get pushed periodically, it wasn't a request we made so don't pop the queue
      setState(() {
        wallet?.btcPrice = event.response?.btcPrice.toString() ?? '0';
        wallet?.localCurrencyPrice =
            event.response?.localCurrencyPrice.toString() ?? '0';
      });
    });

    // Account has been deleted or name changed
    _accountModifiedSub = EventTaxiImpl.singleton()
        .registerTo<AccountModifiedEvent>()
        .listen((event) {
      if (!event.deleted) {
        if (event.account?.index == selectedAccount.index) {
          setState(() {
            selectedAccount.name = event.account?.name ?? selectedAccount.name;
          });
        } else {
          updateRecentlyUsedAccounts();
        }
      } else {
        // Remove account
        updateRecentlyUsedAccounts().then((_) {
          if (event.account?.index == selectedAccount.index) {
            if (recentLast != null) {
              sl.get<DBHelper>().changeAccount(recentLast!);
              setState(() {
                selectedAccount = recentLast!;
              });
              EventTaxiImpl.singleton()
                  .fire(AccountChangedEvent(account: recentLast!, noPop: true));
            }
          } else if (event.account?.index == selectedAccount.index) {
            if (recentSecondLast != null) {
              sl.get<DBHelper>().changeAccount(recentSecondLast!);
              setState(() {
                selectedAccount = recentSecondLast!;
              });
              EventTaxiImpl.singleton().fire(
                  AccountChangedEvent(account: recentSecondLast!, noPop: true));
            }
          } else if (event.account?.index == selectedAccount.index) {
            getSeed().then((seed) {
              sl.get<DBHelper>().getMainAccount(seed).then((mainAccount) {
                sl.get<DBHelper>().changeAccount(mainAccount);
                setState(() {
                  selectedAccount = mainAccount;
                });
                EventTaxiImpl.singleton().fire(
                    AccountChangedEvent(account: mainAccount, noPop: true));
              });
            });
          }
        });
        updateRecentlyUsedAccounts();
      }
    });
  }

  void _handleTransactionsListEvent(TransactionsListEvent event) {
    print("listen TransactionsListEvent - received " + (event.response?.length ?? 0).toString() + " transactions");
    
    // Check if widget is still mounted before processing
    if (!mounted) {
      print("Widget not mounted, skipping transaction event processing");
      return;
    }
    
    // Skip processing empty responses in certain conditions to prevent flickering
    if (event.response?.isEmpty == true) {
      // If we already have transactions, skip empty responses
      if (wallet?.history.isNotEmpty ?? false) {
        print("Skipping empty response to prevent UI flicker");
        return;
      }
      // For accounts with no transactions, we need to process the empty response
      // to clear the loading state. Don't skip empty responses for initial loads.
    }
    
    try {
      AddressTxsResponse addressTxsResponse = new AddressTxsResponse();
      addressTxsResponse.result = <AddressTxsResponseResult>[];
      for (int i = 0; i < (event.response?.length ?? 0); i++) {
        AddressTxsResponseResult addressTxResponseResult = AddressTxsResponseResult();
        addressTxResponseResult.populate(event.response![i], selectedAccount.address!);
        addressTxResponseResult.getBisToken();
        addressTxsResponse.result?.add(addressTxResponseResult);
      }

      // Server-mempool-only flow: rebuild history from server data only
      wallet?.history.clear();
      print("Processed transactions: " + (addressTxsResponse.result?.length ?? 0).toString());

      // Add all transactions to a temporary list and sort them by timestamp (oldest first)
      List<AddressTxsResponseResult> allTransactions = [];
      for (AddressTxsResponseResult item in addressTxsResponse.result ?? []) {
        allTransactions.add(item);
      }

      allTransactions.sort((a, b) {
        if (a.timestamp == null && b.timestamp == null) return 0;
        if (a.timestamp == null) return 1;
        if (b.timestamp == null) return -1;
        return a.timestamp!.compareTo(b.timestamp!);
      });

      // Check mounted again before setState
      if (!mounted) {
        print("Widget unmounted during processing, skipping setState");
        return;
      }

      setState(() {
        for (AddressTxsResponseResult item in allTransactions) {
          wallet?.history.add(item);
        }
        wallet?.historyLoading = false;
        wallet?.loading = false;
      });

      EventTaxiImpl.singleton().fire(HistoryHomeEvent(items: wallet?.history ?? []));
    } catch (e) {
      sl.get<Logger>().e("Error in _handleTransactionsListEvent", e);
      // Always clear loading state on error
      if (mounted) {
        setState(() {
          wallet?.historyLoading = false;
          wallet?.loading = false;
        });
        // Fire event with empty history to unstick UI
        EventTaxiImpl.singleton().fire(HistoryHomeEvent(items: wallet?.history ?? []));
      }
    }
  }

  @override
  void dispose() {
    _destroyBus();
    super.dispose();
  }

  void _destroyBus() {
    _balanceGetEventSub?.cancel();
      _priceEventSub?.cancel();
      _accountModifiedSub?.cancel();
      _transactionsListEventSub?.cancel();
    }

  // Update the global wallet instance with a new address
  Future<void> updateWallet({required Account account, String? seedOverride}) async {
    String address;
    String seed;
    
    if (seedOverride != null) {
      seed = seedOverride;
    } else {
      try {
        seed = await getSeed();
      } catch (e) {
        seed = await sl.get<Vault>().getSeed();
      }
    }
    
    address = AppUtil().seedToAddress(seed, account.index ?? 0);
    account.address = address;
    selectedAccount = account;
    updateRecentlyUsedAccounts();

    setState(() {
      wallet = AppWallet(address: address, loading: true);
      requestUpdate();
    });
  }

  Future<void> updateRecentlyUsedAccounts() async {
    try {
      String seed;
      try {
        seed = await getSeed();
      } catch (e) {
        seed = await sl.get<Vault>().getSeed();
      }
      
      List<Account> otherAccounts =
          await sl.get<DBHelper>().getRecentlyUsedAccounts(seed);
      
      if (otherAccounts.length > 0) {
        if (otherAccounts.length > 1) {
          setState(() {
            recentLast = otherAccounts[0];
            recentSecondLast = otherAccounts[1];
          });
        } else {
          setState(() {
            recentLast = otherAccounts[0];
            recentSecondLast = null;
          });
        }
      } else {
        setState(() {
          recentLast = null;
          recentSecondLast = null;
        });
      }
    } catch (e) {
      print("Error updating recently used accounts: $e");
      setState(() {
        recentLast = null;
        recentSecondLast = null;
      });
    }
  }

  // Change language
  void updateLanguage(LanguageSetting language) {
    setState(() {
      curLanguage = language;
    });
  }

  // Change curency
  void updateCurrency(AvailableCurrency currency) async {
    await sl.get<HttpService>().getSimplePrice(currency.getIso4217Code());
    setState(() {
      curCurrency = currency;
    });
  }

  // Set encrypted secret
  void setEncryptedSecret(String secret) {
    setState(() {
      encryptedSecret = secret;
    });
  }

  // Reset encrypted secret
  void resetEncryptedSecret() {
    setState(() {
      encryptedSecret = null;
    });
  }

  /// Handle address response
  void handleAddressResponse(BalanceGetResponse response) {
    // Set currency locale here for the UI to access
    sl.get<SharedPrefsUtil>().getCurrency(deviceLocale).then((currency) {
      setState(() {
        currencyLocale = currency.getLocale().toString();
        curCurrency = currency;
      });
    });
    setState(() {
      // Use confirmed-only balance from server when available
      double? confirmedBalance = double.tryParse(
          (response.balanceNoMempool.isNotEmpty
              ? response.balanceNoMempool
              : response.balance));
      if (wallet != null && confirmedBalance != null) {
        wallet!.accountBalance = confirmedBalance;
        print("Updated confirmed balance from server: " + confirmedBalance.toString());
      }
      // Persist to DB if we have a valid selected account
      if (selectedAccount.address != null && selectedAccount.address!.isNotEmpty) {
        sl.get<DBHelper>().updateAccountBalance(
            selectedAccount, wallet?.accountBalance.toString() ?? '0');
      }
    });
  }

  Future<void> requestUpdate() async {
    // Debug: Check if we have a valid address to work with
    if (selectedAccount.address != null && selectedAccount.address!.isNotEmpty) {
      // Request account history
      int count = 100;
      print("Requesting transaction history for address: " + selectedAccount.address! + " with limit: " + count.toString());
      try {
        // Before firing new requests, ensure previous listeners won't duplicate UI
        _transactionsListEventSub?.cancel();
        _transactionsListEventSub = EventTaxiImpl.singleton()
            .registerTo<TransactionsListEvent>()
            .listen((event) => _handleTransactionsListEvent(event));

        // Making balance and transaction requests
        sl.get<AppService>().getBalanceGetResponse(selectedAccount.address!, true);

        await sl.get<HttpService>().getSimplePrice(curCurrency.getIso4217Code());

        sl.get<AppService>().getAddressTxsResponse(selectedAccount.address!, count);

        //sl.get<AppService>().getAlias(wallet.address);

        AddressTxsResponse addressTxsResponse = new AddressTxsResponse();
        addressTxsResponse.tokens = await sl
            .get<HttpService>()
            .getTokensBalance(selectedAccount.address!);
        setState(() {
          if (wallet != null) {
            wallet!.tokens.clear();
            wallet!.tokens.add(
                BisToken(tokenName: "", tokensQuantity: 0, tokenMessage: ""));
            wallet!.tokens.addAll(addressTxsResponse.tokens ?? []);
          }
        });
      } catch (e) {
        // TODO handle account history error
        sl.get<Logger>().e("account_history e", e);
        // Error in requestUpdate
        if (mounted) {
          setState(() {
            wallet?.historyLoading = false;
            wallet?.loading = false;
          });
          // Notify UI to refresh with whatever we have
          EventTaxiImpl.singleton().fire(HistoryHomeEvent(items: wallet?.history ?? []));
        }
      }
    } else {
      // requestUpdate skipped - selectedAccount.address is null or empty
    }
  }

  void addUnconfirmedTransaction({
    required String fromAddress,
    required String toAddress,
    required String amount,
    required String operation,
    required String openfield,
  }) {
    // Create unconfirmed transaction
    AddressTxsResponseResult unconfirmedTx = AddressTxsResponseResult();
    unconfirmedTx.timestamp = DateTime.now();
    unconfirmedTx.from = fromAddress;
    unconfirmedTx.recipient = toAddress;
    unconfirmedTx.amount = amount;
    unconfirmedTx.operation = operation;
    unconfirmedTx.openfield = openfield;
    unconfirmedTx.blockHeight = null; // No block height for unconfirmed
    unconfirmedTx.type = BlockTypes.UNCONFIRMED;
    unconfirmedTx.signature = "pending..."; // Placeholder
    unconfirmedTx.hash = "pending..."; // Placeholder
    unconfirmedTx.fee = 0.01; // Standard fee
    
    setState(() {
      // Add to the end of history (will display at top due to UI reverse indexing)
      wallet?.history.add(unconfirmedTx);
    });
    
    print("=== UNCONFIRMED TRANSACTION CREATED ===");
    print("From: " + fromAddress);
    print("To: " + toAddress);  
    print("Amount: " + amount);
    print("Type: " + unconfirmedTx.type.toString());
    print("Timestamp: " + unconfirmedTx.timestamp.toString());
    print("Total history count: " + (wallet?.history.length ?? 0).toString());
    
    // Count unconfirmed transactions
    int unconfirmedCount = wallet?.history.where((tx) => tx.type == BlockTypes.UNCONFIRMED).length ?? 0;
    print("Unconfirmed transactions in history: " + unconfirmedCount.toString());
    print("=== END UNCONFIRMED CREATION DEBUG ===");
    
    // Fire event to update UI
    EventTaxiImpl.singleton().fire(HistoryHomeEvent(items: wallet?.history ?? []));
  }

  void logOut() {
    setState(() {
      wallet = AppWallet();
      encryptedSecret = null;
    });
    sl.get<DBHelper>().dropAccounts();
  }

  Future<String> getSeed() async {
    // Check if encryptedSecret is available
    if (encryptedSecret == null || encryptedSecret!.isEmpty) {
      throw Exception('Encrypted secret is not available');
    }
    
    String sessionKey = await sl.get<Vault>().getSessionKey();
    if (sessionKey.isEmpty) {
      throw Exception('Session key is not available');
    }
    
    try {
      String seed = HEX.encode(AppCrypt.decrypt(encryptedSecret!, sessionKey));
      return seed;
    } catch (e) {
      throw Exception('Failed to decrypt seed: ${e.toString()}');
    }
  }

  // Simple build method that just passes this state through
  // your InheritedWidget
  @override
  Widget build(BuildContext context) {
    return _InheritedStateContainer(
      data: this,
      child: widget.child,
    );
  }
}
