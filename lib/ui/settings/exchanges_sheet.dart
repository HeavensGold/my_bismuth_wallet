// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_size_text/auto_size_text.dart';
import 'package:fluttericon/font_awesome_icons.dart';

// Project imports:
import 'package:my_bismuth_wallet/appstate_container.dart';
import 'package:my_bismuth_wallet/network/model/response/individual_dex_prices_response.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/styles.dart';
import 'package:my_bismuth_wallet/ui/widgets/sheet_util.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';
import 'package:my_bismuth_wallet/service/price_manager.dart';
import 'package:my_bismuth_wallet/service/price_sources/price_source.dart';

class AppExchangesSheet {
  final Map<DefaultDex, DexPriceData>? dexPrices;

  AppExchangesSheet(this.dexPrices);

  // Format price with appropriate decimal places
  String _formatPrice(String priceStr, bool isFiat) {
    double price = double.tryParse(priceStr) ?? 0.0;
    if (isFiat) {
      // Dynamic decimals for fiat
      if (price >= 1) return price.toStringAsFixed(2);
      if (price >= 0.01) return price.toStringAsFixed(4);
      return price.toStringAsFixed(6);
    } else {
      // BTC formatting with better precision
      if (price == 0.0) return '0';
      if (price < 0.00000001) {
        // Use scientific notation for very small numbers
        return price.toStringAsExponential(3);
      }
      if (price < 0.0001) {
        // Show up to 12 decimal places for small BTC amounts
        return price
            .toStringAsFixed(12)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
      }
      // Standard 8 decimal places for normal BTC amounts
      return price
          .toStringAsFixed(8)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
    }
  }

  /// Get current price data from PriceManager
  Map<String, PriceData> _getCurrentPrices() {
    return PriceManager.instance.allPrices;
  }

  /// Get price data for a specific DEX from PriceManager
  PriceData? _getPriceForDex(DefaultDex dex) {
    final prices = _getCurrentPrices();
    switch (dex) {
      case DefaultDex.AGGREGATED:
        return prices['coingecko_aggregated'];
      case DefaultDex.UNISWAP_V2:
        return prices['uniswap_v2'];
      case DefaultDex.PANCAKESWAP:
        return prices['pancakeswap'];
    }
  }

  mainBottomSheet(BuildContext context) {
    Sheets.showAppHeightNineSheet(
      context: context,
      widget: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return SafeArea(
            minimum: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height * 0.035,
            ),
            child: Container(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: <Widget>[
                  // Header with sheet handle
                  Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(width: 60, height: 60),
                          Column(
                            children: <Widget>[
                              // Sheet handle
                              Container(
                                margin: EdgeInsets.only(top: 10),
                                height: 5,
                                width: MediaQuery.of(context).size.width * 0.15,
                                decoration: BoxDecoration(
                                  color: StateContainer.of(context)
                                      .curTheme
                                      .text10,
                                  borderRadius: BorderRadius.circular(100.0),
                                ),
                              ),
                              // Header text
                              Container(
                                margin: EdgeInsets.only(top: 15),
                                child: AutoSizeText(
                                  "Exchanges", // AppLocalization.of(context).exchanges,
                                  style: AppStyles.textStyleHeader(context),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  stepGranularity: 0.1,
                                ),
                              ),
                              // Subtitle
                              Container(
                                margin: EdgeInsets.only(
                                    top: 5, left: 30, right: 30),
                                child: AutoSizeText(
                                  "Select your default price source", // AppLocalization.of(context).selectDefaultExchange,
                                  style: AppStyles.textStyleParagraph(context),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  stepGranularity: 0.1,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(width: 60, height: 60),
                        ],
                      ),
                    ],
                  ),

                  // Exchanges List
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(top: 20),
                      child: Column(
                        children: [
                          // Build options using PriceManager data
                          ...(() {
                            List<Widget> options = [];
                            
                            // Aggregated option (CoinGecko)
                            PriceData? aggregatedPrice = _getPriceForDex(DefaultDex.AGGREGATED);
                            options.add(_buildDexOption(
                              context,
                              setState,
                              DefaultDex.AGGREGATED,
                              'Aggregated (by CoinGecko)',
                              aggregatedPrice?.btcPrice.toString() ?? '0',
                              aggregatedPrice?.localCurrencyPrice.toString() ?? '0',
                              0.0, // No specific volume for aggregated
                            ));

                            // Uniswap V2 option
                            PriceData? uniswapPrice = _getPriceForDex(DefaultDex.UNISWAP_V2);
                            if (uniswapPrice != null) {
                              options.add(_buildDexOption(
                                context,
                                setState,
                                DefaultDex.UNISWAP_V2,
                                'Uniswap V2',
                                uniswapPrice.btcPrice.toString(),
                                uniswapPrice.localCurrencyPrice.toString(),
                                uniswapPrice.volume24h,
                              ));
                            }

                            // PancakeSwap option
                            PriceData? pancakePrice = _getPriceForDex(DefaultDex.PANCAKESWAP);
                            if (pancakePrice != null) {
                              options.add(_buildDexOption(
                                context,
                                setState,
                                DefaultDex.PANCAKESWAP,
                                'PancakeSwap',
                                pancakePrice.btcPrice.toString(),
                                pancakePrice.localCurrencyPrice.toString(),
                                pancakePrice.volume24h,
                              ));
                            }

                            return options;
                          })(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDexOption(
    BuildContext context,
    StateSetter setState,
    DefaultDex dex,
    String displayName,
    String btcPrice,
    String localPrice,
    double volume24h,
  ) {
    final currentDex =
        StateContainer.of(context).selectedDefaultDex ?? DefaultDex.PANCAKESWAP;
    final isSelected = currentDex == dex;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            // Update selected DEX in preferences and state
            await sl.get<SharedPrefsUtil>().setDefaultDex(dex);
            StateContainer.of(context).updateDefaultDex(dex);

            // Close the sheet
            Navigator.of(context).pop();
          },
          child: Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isSelected
                  ? StateContainer.of(context).curTheme.primary.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? StateContainer.of(context).curTheme.primary
                    : StateContainer.of(context).curTheme.text15,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Radio button indicator
                Container(
                  width: 20,
                  height: 20,
                  margin: EdgeInsets.only(right: 15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? StateContainer.of(context).curTheme.primary
                          : StateContainer.of(context).curTheme.text45,
                      width: 2,
                    ),
                    color: isSelected
                        ? StateContainer.of(context).curTheme.primary
                        : Colors.transparent,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 12,
                          color: StateContainer.of(context)
                              .curTheme
                              .backgroundDark,
                        )
                      : null,
                ),

                // DEX info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // DEX name
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: isSelected ? 18 : 16,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: StateContainer.of(context).curTheme.text,
                        ),
                      ),

                      // Prices (with "1 BIS =" prefix)
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '1 BIS = ',
                            style: TextStyle(
                              fontSize: 13,
                              color: StateContainer.of(context).curTheme.text45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${_formatPrice(localPrice, true)} ${StateContainer.of(context).curCurrency.getIso4217Code()} • ',
                            style: TextStyle(
                              fontSize: 14,
                              color: StateContainer.of(context).curTheme.text60,
                            ),
                          ),
                          Icon(
                            FontAwesome.bitcoin,
                            size: 12,
                            color: StateContainer.of(context).curTheme.primary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            _formatPrice(btcPrice, false),
                            style: TextStyle(
                              fontSize: 14,
                              color: StateContainer.of(context).curTheme.text60,
                            ),
                          ),
                        ],
                      ),

                      // Volume (only for DEXs with volume data)
                      if (volume24h > 0) ...[
                        SizedBox(height: 2),
                        Text(
                          'Volume 24h: \$${_formatVolume(volume24h)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: StateContainer.of(context).curTheme.text45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatVolume(double volume) {
    if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(2)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(2)}K';
    } else {
      return volume.toStringAsFixed(2);
    }
  }
}
