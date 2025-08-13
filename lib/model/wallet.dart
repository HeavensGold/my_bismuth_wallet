// Package imports:
import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

// Project imports:
import 'package:my_bismuth_wallet/model/available_currency.dart';
import 'package:my_bismuth_wallet/network/model/response/address_txs_response.dart';
import 'package:my_bismuth_wallet/network/model/response/individual_dex_prices_response.dart';
import 'package:my_bismuth_wallet/network/model/block_types.dart';
import 'package:my_bismuth_wallet/util/numberutil.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

/// Main wallet object that's passed around the app via state
class AppWallet {
  static const String defaultRepresentative =
      '0xf2b4f700d2975abd39000587f9788f66afedf691';

  late bool _loading; // Whether or not app is initially loading
  late bool
      _historyLoading; // Whether or not we have received initial account history response
  late String _address;
  late double _accountBalance;
  late String _representative;
  late String _localCurrencyPrice;
  late String _btcPrice;
  late List<AddressTxsResponseResult> _history;
  late List<BisToken> _tokens;

  // Individual DEX prices
  Map<DefaultDex, DexPriceData>? _dexPrices;

  AppWallet(
      {String? address,
      double? accountBalance,
      String? representative,
      String? localCurrencyPrice,
      String? btcPrice,
      List<AddressTxsResponseResult>? history,
      bool? loading,
      bool? historyLoading,
      List<BisToken>? tokens}) {
    _address = address ?? '';
    _accountBalance = accountBalance ?? 0;
    _representative = representative ?? '';
    _localCurrencyPrice = localCurrencyPrice ?? "0";
    _btcPrice = btcPrice ?? "0";
    _history = history ?? <AddressTxsResponseResult>[];
    _tokens = tokens ?? <BisToken>[];
    _loading = loading ?? true;
    _historyLoading = historyLoading ?? true;
    _dexPrices = null;
  }

  String get address => _address;

  set address(String address) {
    _address = address;
  }

  double get accountBalance => _accountBalance;

  set accountBalance(double accountBalance) {
    _accountBalance = accountBalance;
  }

  // Get pretty account balance version
  String getAccountBalanceDisplay() {
    return NumberUtil.getRawAsUsableString(_accountBalance.toString());
  }

  // Get pretty account balance version
  String getAccountBalanceMoinsFeesDisplay(estimationFees) {
    double value = _accountBalance - estimationFees;
    return NumberUtil.getRawAsUsableString(value.toString());
  }

  String getLocalCurrencyPrice(AvailableCurrency currency,
      {String locale = "en_US"}) {
    Decimal converted = Decimal.parse(_localCurrencyPrice) *
        NumberUtil.getRawAsUsableDecimal(_accountBalance.toString());

    // Adaptive decimal precision to prevent very low prices from showing as 0.00
    int decimalDigits;
    if (converted >= Decimal.parse("0.01")) {
      decimalDigits = 2; // Standard currency format for amounts >= 0.01
    } else if (converted >= Decimal.parse("0.0001")) {
      decimalDigits = 4; // 4 decimals for amounts >= 0.0001
    } else if (converted >= Decimal.parse("0.000001")) {
      decimalDigits = 6; // 6 decimals for amounts >= 0.000001
    } else {
      decimalDigits = 8; // Up to 8 decimals for very small amounts
    }

    return NumberFormat.currency(
            locale: locale,
            symbol: currency.getCurrencySymbol(),
            decimalDigits: decimalDigits)
        .format(converted.toDouble());
  }

  String getLocalCurrencyPriceMoinsFees(
      AvailableCurrency currency, double estimationFees,
      {String locale = "en_US"}) {
    double value = _accountBalance - estimationFees;
    Decimal converted = Decimal.parse(_localCurrencyPrice) *
        NumberUtil.getRawAsUsableDecimal(value.toString());

    // Adaptive decimal precision to prevent very low prices from showing as 0.00
    int decimalDigits;
    if (converted >= Decimal.parse("0.01")) {
      decimalDigits = 2; // Standard currency format for amounts >= 0.01
    } else if (converted >= Decimal.parse("0.0001")) {
      decimalDigits = 4; // 4 decimals for amounts >= 0.0001
    } else if (converted >= Decimal.parse("0.000001")) {
      decimalDigits = 6; // 6 decimals for amounts >= 0.000001
    } else {
      decimalDigits = 8; // Up to 8 decimals for very small amounts
    }

    return NumberFormat.currency(
            locale: locale,
            symbol: currency.getCurrencySymbol(),
            decimalDigits: decimalDigits)
        .format(converted.toDouble());
  }

  set localCurrencyPrice(String value) {
    _localCurrencyPrice = value;
  }

  String get localCurrencyConversion {
    return _localCurrencyPrice;
  }

  String get btcPrice {
    Decimal converted = Decimal.parse(_btcPrice) *
        NumberUtil.getRawAsUsableDecimal(_accountBalance.toString());
    // Show 4 decimal places for BTC price if its >= 0.0001 BTC, otherwise 6 decimals
    if (converted >= Decimal.parse("0.0001")) {
      return new NumberFormat("#,##0.0000", "en_US")
          .format(converted.toDouble());
    } else {
      return new NumberFormat("#,##0.000000000", "en_US")
          .format(converted.toDouble());
    }
  }

  set btcPrice(String value) {
    _btcPrice = value;
  }

  String get representative {
    return _representative.isEmpty ? defaultRepresentative : _representative;
  }

  set representative(String value) {
    _representative = value;
  }

  List<AddressTxsResponseResult> get history => _history;

  set history(List<AddressTxsResponseResult> value) {
    _history = value;
  }

  List<BisToken> get tokens => _tokens;

  set tokens(List<BisToken> value) {
    _tokens = value;
  }

  // Compute pending delta from mempool entries (blockHeight == -1)
  double getPendingDelta() {
    double delta = 0;
    for (final tx in _history) {
      final bool isMempool = (tx.blockHeight == -1);
      if (!isMempool) continue;
      final double amount = double.tryParse(tx.amount ?? '0') ?? 0;
      final double fee = tx.fee ?? 0;
      if (tx.type == BlockTypes.RECEIVE) {
        delta += amount;
      } else {
        // Treat non-RECEIVE as outgoing
        delta -= (amount + fee);
      }
    }
    return delta;
  }

  // Get formatted pending delta string for display
  String getPendingDeltaDisplay() {
    final double delta = getPendingDelta();
    return NumberUtil.getRawAsUsableString(delta.toString());
  }

  bool get loading => _loading;

  set loading(bool value) {
    _loading = value;
  }

  bool get historyLoading => _historyLoading;

  set historyLoading(bool value) {
    _historyLoading = value;
  }

  // Raw price getters for display purposes
  String get rawBtcPrice => _btcPrice;
  String get rawLocalCurrencyPrice => _localCurrencyPrice;

  // Individual DEX prices management
  void updateDexPrices(Map<DefaultDex, DexPriceData>? dexPrices) {
    _dexPrices = dexPrices;
  }

  Map<DefaultDex, DexPriceData>? get dexPrices => _dexPrices;

  // Add methods to get raw per-BIS prices by DEX
  String getRawLocalCurrencyPriceByDex(DefaultDex selectedDex) {
    String priceToUse = _localCurrencyPrice;

    if (_dexPrices != null && _dexPrices![selectedDex] != null) {
      DexPriceData dexData = _dexPrices![selectedDex]!;
      if (dexData.isActive && dexData.localCurrencyPrice != '0') {
        priceToUse = dexData.localCurrencyPrice;
      }
    }

    return priceToUse; // Return raw per-BIS price, not multiplied by balance
  }

  String getRawBtcPriceByDex(DefaultDex selectedDex) {
    String priceToUse = _btcPrice;

    if (_dexPrices != null && _dexPrices![selectedDex] != null) {
      DexPriceData dexData = _dexPrices![selectedDex]!;
      if (dexData.isActive && dexData.btcPrice != '0') {
        priceToUse = dexData.btcPrice;
      }
    }

    return priceToUse; // Return raw per-BIS price, not multiplied by balance
  }

  // Get local currency price by selected DEX
  String getLocalCurrencyPriceByDex(
      DefaultDex selectedDex, AvailableCurrency currency,
      {String locale = "en_US"}) {
    String priceToUse = _localCurrencyPrice;

    // Use DEX-specific price if available and active
    if (_dexPrices != null && _dexPrices![selectedDex] != null) {
      DexPriceData dexData = _dexPrices![selectedDex]!;
      if (dexData.isActive && dexData.localCurrencyPrice != '0') {
        priceToUse = dexData.localCurrencyPrice;
      }
    }

    Decimal converted = Decimal.parse(priceToUse) *
        NumberUtil.getRawAsUsableDecimal(_accountBalance.toString());

    // Adaptive decimal precision to prevent very low prices from showing as 0.00
    int decimalDigits;
    if (converted >= Decimal.parse("0.01")) {
      decimalDigits = 2; // Standard currency format for amounts >= 0.01
    } else if (converted >= Decimal.parse("0.0001")) {
      decimalDigits = 4; // 4 decimals for amounts >= 0.0001
    } else if (converted >= Decimal.parse("0.000001")) {
      decimalDigits = 6; // 6 decimals for amounts >= 0.000001
    } else {
      decimalDigits = 8; // Up to 8 decimals for very small amounts
    }

    return NumberFormat.currency(
            locale: locale,
            symbol: currency.getCurrencySymbol(),
            decimalDigits: decimalDigits)
        .format(converted.toDouble());
  }

  // Get BTC price by selected DEX
  String getBtcPriceByDex(DefaultDex selectedDex) {
    String priceToUse = _btcPrice;

    // Use DEX-specific price if available and active
    if (_dexPrices != null && _dexPrices![selectedDex] != null) {
      DexPriceData dexData = _dexPrices![selectedDex]!;
      if (dexData.isActive && dexData.btcPrice != '0') {
        priceToUse = dexData.btcPrice;
      }
    }

    Decimal converted = Decimal.parse(priceToUse) *
        NumberUtil.getRawAsUsableDecimal(_accountBalance.toString());

    // Show 4 decimal places for BTC price if its >= 0.0001 BTC, otherwise 6 decimals
    if (converted >= Decimal.parse("0.0001")) {
      return new NumberFormat("#,##0.0000", "en_US")
          .format(converted.toDouble());
    } else {
      return new NumberFormat("#,##0.000000000", "en_US")
          .format(converted.toDouble());
    }
  }
}
