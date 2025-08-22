// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:event_taxi/event_taxi.dart';
import 'package:fluttericon/font_awesome_icons.dart';
import 'package:fluttericon/typicons_icons.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:my_bismuth_wallet/app_icons.dart';
import 'package:my_bismuth_wallet/appstate_container.dart';
import 'package:my_bismuth_wallet/bus/events.dart';
import 'package:my_bismuth_wallet/bus/unified_price_event.dart';
import 'package:my_bismuth_wallet/localization.dart';
import 'package:my_bismuth_wallet/model/authentication_method.dart';
import 'package:my_bismuth_wallet/model/available_currency.dart';
import 'package:my_bismuth_wallet/model/available_language.dart';
import 'package:my_bismuth_wallet/model/db/appdb.dart';
import 'package:my_bismuth_wallet/model/db/hiveDB.dart';
import 'package:my_bismuth_wallet/model/device_lock_timeout.dart';
import 'package:my_bismuth_wallet/model/device_unlock_option.dart';
import 'package:my_bismuth_wallet/model/vault.dart';
// import 'package:my_bismuth_wallet/service/dragginator_service.dart'; // Deleted
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/styles.dart';
import 'package:my_bismuth_wallet/util/app_ffi/apputil.dart';
import 'package:my_bismuth_wallet/ui/accounts/accountdetails_sheet.dart';
import 'package:my_bismuth_wallet/ui/accounts/accounts_sheet.dart';
// import 'package:my_bismuth_wallet/ui/dragginator/my_dragginator_breeding_list.dart'; // Deleted
// import 'package:my_bismuth_wallet/ui/dragginator/my_dragginator_merging.dart'; // Deleted
import 'package:my_bismuth_wallet/ui/settings/backupseed_sheet.dart';
import 'package:my_bismuth_wallet/ui/settings/contacts_widget.dart';
import 'package:my_bismuth_wallet/ui/settings/custom_url_widget.dart';
import 'package:my_bismuth_wallet/ui/settings/disable_password_sheet.dart';
import 'package:my_bismuth_wallet/ui/settings/set_password_sheet.dart';
import 'package:my_bismuth_wallet/ui/settings/settings_list_item.dart';
import 'package:my_bismuth_wallet/ui/settings/exchanges_sheet.dart';
// import 'package:my_bismuth_wallet/ui/settings/tokens_widget.dart'; // Deleted
import 'package:my_bismuth_wallet/ui/util/ui_util.dart';
import 'package:my_bismuth_wallet/ui/widgets/app_simpledialog.dart';
import 'package:my_bismuth_wallet/ui/widgets/dialog.dart';
import 'package:my_bismuth_wallet/ui/widgets/security.dart';
import 'package:my_bismuth_wallet/ui/widgets/sheet_util.dart';
import 'package:my_bismuth_wallet/util/biometrics.dart';
import 'package:my_bismuth_wallet/util/hapticutil.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';
import 'package:my_bismuth_wallet/service/price_manager.dart';
import 'package:my_bismuth_wallet/service/price_sources/price_source.dart';

class SettingsSheet extends StatefulWidget {
  final int eggPrice;
  SettingsSheet(this.eggPrice);

  _SettingsSheetState createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _securityController;
  late Animation<Offset> _securityOffsetFloat;
  late AnimationController _customUrlController;
  late Animation<Offset> _customUrlOffsetFloat;
  late AnimationController _contactsController;
  late Animation<Offset> _contactsOffsetFloat;

  String versionString = "";

  final Logger log = sl.get<Logger>();
  bool _hasBiometrics = false;
  AuthenticationMethod _curAuthMethod =
      AuthenticationMethod(AuthMethod.BIOMETRICS);
  UnlockSetting _curUnlockSetting = UnlockSetting(UnlockOption.NO);
  LockTimeoutSetting _curTimeoutSetting =
      LockTimeoutSetting(LockTimeoutOption.ONE);

  late bool _securityOpen;
  late bool _loadingAccounts;
  bool _isPasswordMode = false;

  late bool _customUrlOpen;
  late bool _contactsOpen;
  
  // Price event subscription for auto-refresh
  StreamSubscription<UnifiedPriceUpdateEvent>? _unifiedPriceEventSub;

  bool notNull(Object o) => o != null;

  @override
  void initState() {
    super.initState();

    _securityOpen = false;
    _loadingAccounts = false;
    _customUrlOpen = false;
    _contactsOpen = false;
    // Check if wallet is in password mode
    _checkPasswordMode().then((isPasswordMode) {
      if (mounted) {
        setState(() {
          _isPasswordMode = isPasswordMode;
        });
      }
    });
    // Determine if they have face or fingerprint enrolled, if not hide the setting
    sl.get<BiometricUtil>().hasBiometrics().then((bool hasBiometrics) {
      setState(() {
        _hasBiometrics = hasBiometrics;
      });
    });
    // Get default auth method setting
    sl.get<SharedPrefsUtil>().getAuthMethod().then((authMethod) {
      setState(() {
        _curAuthMethod = authMethod;
      });
    });
    // Get default unlock settings
    sl.get<SharedPrefsUtil>().getLock().then((lock) {
      setState(() {
        _curUnlockSetting = lock
            ? UnlockSetting(UnlockOption.YES)
            : UnlockSetting(UnlockOption.NO);
      });
    });
    sl.get<SharedPrefsUtil>().getLockTimeout().then((lockTimeout) {
      setState(() {
        _curTimeoutSetting = lockTimeout;
      });
    });
    // Subscribe to price events for auto-refresh
    _unifiedPriceEventSub = EventTaxiImpl.singleton().registerTo<UnifiedPriceUpdateEvent>().listen((event) {
      if (mounted) {
        setState(() {
          // Price update will trigger rebuild of _getPriceInfo()
        });
      }
    });
    
    // For security menu
    _securityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    // For customUrl menu
    _customUrlController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    // For contacts menu
    _contactsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _securityOffsetFloat =
        Tween<Offset>(begin: Offset(1.1, 0), end: Offset(0, 0))
            .animate(_securityController);
    _customUrlOffsetFloat =
        Tween<Offset>(begin: Offset(1.1, 0), end: Offset(0, 0))
            .animate(_customUrlController);
    _contactsOffsetFloat =
        Tween<Offset>(begin: Offset(1.1, 0), end: Offset(0, 0))
            .animate(_contactsController);
    // Version string
    PackageInfo.fromPlatform().then((packageInfo) {
      setState(() {
        versionString = "v${packageInfo.version}";
      });
    });
  }

  @override
  void dispose() {
    _unifiedPriceEventSub?.cancel();
    _securityController.dispose();
    _customUrlController.dispose();
    _contactsController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        super.didChangeAppLifecycleState(state);
        break;
      case AppLifecycleState.resumed:
        super.didChangeAppLifecycleState(state);
        break;
      default:
        super.didChangeAppLifecycleState(state);
        break;
    }
  }

  Future<void> _authMethodDialog() async {
    switch (await showDialog<AuthMethod>(
        context: context,
        builder: (BuildContext context) {
          return AppSimpleDialog(
            title: Text(
              AppLocalization.of(context).authMethod,
              style: AppStyles.textStyleDialogHeader(context),
            ),
            children: <Widget>[
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, AuthMethod.BIOMETRICS);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).biometricsMethod,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, AuthMethod.PIN);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).pinMethod,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
            ],
          );
        })) {
      case AuthMethod.PIN:
        sl
            .get<SharedPrefsUtil>()
            .setAuthMethod(AuthenticationMethod(AuthMethod.PIN))
            .then((result) {
          setState(() {
            _curAuthMethod = AuthenticationMethod(AuthMethod.PIN);
          });
        });
        break;
      case AuthMethod.BIOMETRICS:
        sl
            .get<SharedPrefsUtil>()
            .setAuthMethod(AuthenticationMethod(AuthMethod.BIOMETRICS))
            .then((result) {
          setState(() {
            _curAuthMethod = AuthenticationMethod(AuthMethod.BIOMETRICS);
          });
        });
        break;
      case null:
        break;
    }
  }

  Future<void> _lockDialog() async {
    switch (await showDialog<UnlockOption>(
        context: context,
        builder: (BuildContext context) {
          return AppSimpleDialog(
            title: Text(
              AppLocalization.of(context).lockAppSetting,
              style: AppStyles.textStyleDialogHeader(context),
            ),
            children: <Widget>[
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, UnlockOption.NO);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).no,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, UnlockOption.YES);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).yes,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
            ],
          );
        })) {
      case UnlockOption.YES:
        sl.get<SharedPrefsUtil>().setLock(true).then((result) {
          setState(() {
            _curUnlockSetting = UnlockSetting(UnlockOption.YES);
          });
        });
        break;
      case UnlockOption.NO:
        sl.get<SharedPrefsUtil>().setLock(false).then((result) {
          setState(() {
            _curUnlockSetting = UnlockSetting(UnlockOption.NO);
          });
        });
        break;
      case null:
        break;
    }
  }

  List<Widget> _buildCurrencyOptions() {
    List<Widget> ret = <Widget>[];
    AvailableCurrencyEnum.values.forEach((AvailableCurrencyEnum value) {
      ret.add(SimpleDialogOption(
        onPressed: () {
          Navigator.pop(context, value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            AvailableCurrency(value).getDisplayName(context),
            style: AppStyles.textStyleDialogOptions(context),
          ),
        ),
      ));
    });
    return ret;
  }

  Future<void> _currencyDialog() async {
    AvailableCurrencyEnum? selection =
        await showAppDialog<AvailableCurrencyEnum>(
            context: context,
            builder: (BuildContext context) {
              return AppSimpleDialog(
                title: Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: Text(
                    AppLocalization.of(context).currency,
                    style: AppStyles.textStyleDialogHeader(context),
                  ),
                ),
                children: _buildCurrencyOptions(),
              );
            });
    if (selection != null) {
      sl
          .get<SharedPrefsUtil>()
          .setCurrency(AvailableCurrency(selection))
          .then((result) {
        if (StateContainer.of(context).curCurrency.currency != selection) {
          setState(() {
            StateContainer.of(context).curCurrency =
                AvailableCurrency(selection);
            StateContainer.of(context)
                .updateCurrency(AvailableCurrency(selection));
          });
        }
      });
    }
  }

  List<Widget> _buildLanguageOptions() {
    List<Widget> ret = <Widget>[];
    AvailableLanguage.values.forEach((AvailableLanguage value) {
      ret.add(SimpleDialogOption(
        onPressed: () {
          Navigator.pop(context, value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            LanguageSetting(value).getDisplayName(context),
            style: AppStyles.textStyleDialogOptions(context),
          ),
        ),
      ));
    });
    return ret;
  }

  Future<void> _languageDialog() async {
    AvailableLanguage? selection = await showAppDialog<AvailableLanguage>(
        context: context,
        builder: (BuildContext context) {
          return AppSimpleDialog(
            title: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Text(
                AppLocalization.of(context).language,
                style: AppStyles.textStyleDialogHeader(context),
              ),
            ),
            children: _buildLanguageOptions(),
          );
        });
    if (selection != null) {
      sl
          .get<SharedPrefsUtil>()
          .setLanguage(LanguageSetting(selection))
          .then((result) {
        if (StateContainer.of(context).curLanguage.language != selection) {
          setState(() {
            StateContainer.of(context)
                .updateLanguage(LanguageSetting(selection));
          });
        }
      });
    }
  }

  List<Widget> _buildLockTimeoutOptions() {
    List<Widget> ret = <Widget>[];
    LockTimeoutOption.values.forEach((LockTimeoutOption value) {
      ret.add(SimpleDialogOption(
        onPressed: () {
          Navigator.pop(context, value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            LockTimeoutSetting(value).getDisplayName(context),
            style: AppStyles.textStyleDialogOptions(context),
          ),
        ),
      ));
    });
    return ret;
  }

  Future<bool> _checkPasswordMode() async {
    try {
      String seed = await sl.get<Vault>().getSeed();
      return AppUtil.isSeedEncrypted(seed);
    } catch (e) {
      return false;
    }
  }

  Future<void> _lockTimeoutDialog() async {
    LockTimeoutOption? selection = await showAppDialog<LockTimeoutOption>(
        context: context,
        builder: (BuildContext context) {
          return AppSimpleDialog(
            title: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Text(
                AppLocalization.of(context).autoLockHeader,
                style: AppStyles.textStyleDialogHeader(context),
              ),
            ),
            children: _buildLockTimeoutOptions(),
          );
        });
    if (selection != null) {
      sl
          .get<SharedPrefsUtil>()
          .setLockTimeout(LockTimeoutSetting(selection))
          .then((result) {
        if (_curTimeoutSetting.setting != selection) {
          sl
              .get<SharedPrefsUtil>()
              .setLockTimeout(LockTimeoutSetting(selection))
              .then((_) {
            setState(() {
              _curTimeoutSetting = LockTimeoutSetting(selection);
            });
          });
        }
      });
    }
  }

  Future<bool> _onBackButtonPressed() async {
    if (_securityOpen) {
      setState(() {
        _securityOpen = false;
      });
      _securityController.reverse();
      return false;
    } else if (_customUrlOpen) {
      setState(() {
        _customUrlOpen = false;
      });
      _customUrlController.reverse();
      return false;
    } else if (_contactsOpen) {
      setState(() {
        _contactsOpen = false;
      });
      _contactsController.reverse();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Drawer in flutter doesn't have a built-in way to push/pop elements
    // on top of it like our Android counterpart. So we can override back button
    // presses and replace the main settings widget with contacts based on a bool
    return new PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          bool shouldPop = await _onBackButtonPressed();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: ClipRect(
        child: Stack(
          children: <Widget>[
            Container(
              color: StateContainer.of(context).curTheme.backgroundDark,
              constraints: BoxConstraints.expand(),
            ),
            buildMainSettings(context),
            SlideTransition(
                position: _securityOffsetFloat,
                child: buildSecurityMenu(context)),
            SlideTransition(
                position: _customUrlOffsetFloat,
                child: CustomUrl(_customUrlController, _customUrlOpen)),
            SlideTransition(
                position: _contactsOffsetFloat,
                child: ContactsList(_contactsController, _contactsOpen)),
          ],
        ),
      ),
    );
  }

  Widget buildMainSettings(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StateContainer.of(context).curTheme.backgroundDark,
      ),
      child: SafeArea(
        minimum: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 30,
        ),
        child: Column(
          children: <Widget>[
            // A container for accounts area
            Container(
              margin:
                  EdgeInsetsDirectional.only(start: 26.0, end: 20, bottom: 15),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        margin: EdgeInsetsDirectional.only(start: 4.0),
                        child: Stack(
                          children: <Widget>[
                            Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(100.0),
                                  border: Border.all(
                                      color: StateContainer.of(context)
                                          .curTheme
                                          .primary,
                                      width: 0),
                                ),
                                alignment: AlignmentDirectional(-1, 0),
                                child: CircleAvatar(
                                  backgroundColor: StateContainer.of(context)
                                      .curTheme
                                      .text05,
                                  backgroundImage: NetworkImage(
                                    StateContainer.of(context)
                                                    .selectedAccount
                                                    ?.dragginatorDna ==
                                                null ||
                                            StateContainer.of(context)
                                                    .selectedAccount
                                                    ?.dragginatorDna ==
                                                ""
                                        ? UIUtil.getRobohashURL(
                                            StateContainer.of(context)
                                                    .selectedAccount
                                                    ?.address ??
                                                "")
                                        : UIUtil.getDragginatorURL(
                                            StateContainer.of(context)
                                                    .selectedAccount
                                                    ?.dragginatorDna ??
                                                "",
                                            StateContainer.of(context)
                                                    .selectedAccount
                                                    ?.dragginatorStatus ??
                                                ""),
                                  ),
                                  radius: 50.0,
                                ),
                              ),
                            ),
                            Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                child: TextButton(
                                  child: SizedBox(
                                    width: 60,
                                    height: 60,
                                  ),
                                  onPressed: () {
                                    AccountDetailsSheet(
                                            StateContainer.of(context)
                                                .selectedAccount)
                                        .mainBottomSheet(context);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // A row for other accounts and account switcher
                      Row(
                        children: <Widget>[
                          // Second Account
                          StateContainer.of(context).recentLast != null
                              ? Container(
                                  child: Stack(
                                    children: <Widget>[
                                      Center(
                                        child: Container(
                                          height: 52,
                                          width: 52,
                                          child: CircleAvatar(
                                            backgroundColor:
                                                StateContainer.of(context)
                                                    .curTheme
                                                    .text05,
                                            backgroundImage: NetworkImage(
                                              StateContainer.of(context)
                                                              .recentLast
                                                              ?.dragginatorDna ==
                                                          null ||
                                                      StateContainer.of(context)
                                                              .recentLast
                                                              ?.dragginatorDna ==
                                                          ""
                                                  ? UIUtil.getRobohashURL(
                                                      StateContainer.of(context)
                                                              .recentLast
                                                              ?.address ??
                                                          "")
                                                  : UIUtil.getDragginatorURL(
                                                      StateContainer.of(context)
                                                              .recentLast
                                                              ?.dragginatorDna ??
                                                          "",
                                                      StateContainer.of(context)
                                                              .recentLast
                                                              ?.dragginatorStatus ??
                                                          ""),
                                            ),
                                            radius: 50.0,
                                          ),
                                        ),
                                      ),
                                      Center(
                                        child: Container(
                                          width: 52,
                                          height: 52,
                                          color: Colors.transparent,
                                          child: TextButton(
                                            onPressed: () {
                                              sl
                                                  .get<DBHelper>()
                                                  .changeAccount(
                                                      StateContainer.of(context)
                                                          .recentLast!)
                                                  .then((_) {
                                                EventTaxiImpl.singleton().fire(
                                                    AccountChangedEvent(
                                                        account:
                                                            StateContainer.of(
                                                                    context)
                                                                .recentLast,
                                                        delayPop: true));
                                              });
                                            },
                                            child: Container(
                                              width: 52,
                                              height: 52,
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SizedBox(),
                          // Third Account
                          StateContainer.of(context).recentSecondLast != null
                              ? Container(
                                  child: Stack(
                                    children: <Widget>[
                                      Center(
                                        child: Container(
                                          height: 52,
                                          width: 52,
                                          child: CircleAvatar(
                                            backgroundColor:
                                                StateContainer.of(context)
                                                    .curTheme
                                                    .text05,
                                            backgroundImage: NetworkImage(
                                              StateContainer.of(context)
                                                              .recentSecondLast
                                                              ?.dragginatorDna ==
                                                          null ||
                                                      StateContainer.of(context)
                                                              .recentSecondLast
                                                              ?.dragginatorDna ==
                                                          ""
                                                  ? UIUtil.getRobohashURL(
                                                      StateContainer.of(context)
                                                              .recentSecondLast
                                                              ?.address ??
                                                          "")
                                                  : UIUtil.getDragginatorURL(
                                                      StateContainer.of(context)
                                                              .recentSecondLast
                                                              ?.dragginatorDna ??
                                                          "",
                                                      StateContainer.of(context)
                                                              .recentSecondLast
                                                              ?.dragginatorStatus ??
                                                          ""),
                                            ),
                                            radius: 50.0,
                                          ),
                                        ),
                                      ),
                                      Center(
                                        child: Container(
                                          width: 52,
                                          height: 52,
                                          color: Colors.transparent,
                                          child: TextButton(
                                            onPressed: () {
                                              sl
                                                  .get<DBHelper>()
                                                  .changeAccount(
                                                      StateContainer.of(context)
                                                          .recentSecondLast!)
                                                  .then((_) {
                                                EventTaxiImpl.singleton().fire(
                                                    AccountChangedEvent(
                                                        account: StateContainer
                                                                .of(context)
                                                            .recentSecondLast,
                                                        delayPop: true));
                                              });
                                            },
                                            child: Container(
                                              width: 52,
                                              height: 52,
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SizedBox(),
                          // Account switcher
                          Container(
                            height: 36,
                            width: 36,
                            margin: EdgeInsets.symmetric(horizontal: 6.0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                            ),
                            child: TextButton(
                              onPressed: () async {
                                if (!_loadingAccounts) {
                                  setState(() {
                                    _loadingAccounts = true;
                                  });
                                  try {
                                    String? seed =
                                        await AppUtil.getSeedSafely(context);
                                    if (seed == null) {
                                      // Password mode but not unlocked
                                      setState(() {
                                        _loadingAccounts = false;
                                      });
                                      UIUtil.showSnackbar(
                                          AppLocalization.of(context).unlock,
                                          context);
                                      return;
                                    }

                                    List<Account> accounts = await sl
                                        .get<DBHelper>()
                                        .getAccounts(seed);
                                    setState(() {
                                      _loadingAccounts = false;
                                    });
                                    AppAccountsSheet(accounts)
                                        .mainBottomSheet(context);
                                  } catch (e) {
                                    setState(() {
                                      _loadingAccounts = false;
                                    });
                                    UIUtil.showSnackbar(
                                        AppLocalization.of(context).sendError,
                                        context);
                                    print("Error loading accounts: $e");
                                  }
                                }
                              },
                              child: Icon(Typicons.users_outline,
                                  size: 26,
                                  color: _loadingAccounts
                                      ? StateContainer.of(context)
                                          .curTheme
                                          .icon60
                                      : StateContainer.of(context)
                                          .curTheme
                                          .icon),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    margin: EdgeInsets.only(top: 2),
                    child: TextButton(
                      onPressed: () {
                        AccountDetailsSheet(
                                StateContainer.of(context).selectedAccount)
                            .mainBottomSheet(context);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Main account name
                          Container(
                            child: Text(
                              StateContainer.of(context)
                                      .selectedAccount
                                      ?.name ??
                                  "",
                              style: TextStyle(
                                fontFamily: "Roboto",
                                fontWeight: FontWeight.w600,
                                fontSize: 16.0,
                                color: StateContainer.of(context).curTheme.text,
                              ),
                            ),
                          ),
                          // Main account address
                          Container(
                            child: Text(
                              StateContainer.of(context).wallet?.address != null
                                  ? StateContainer.of(context)
                                          .wallet
                                          ?.address ??
                                      ""
                                  : "",
                              style: TextStyle(
                                fontFamily: "OverpassMono",
                                fontWeight: FontWeight.w100,
                                fontSize: 14.0,
                                color:
                                    StateContainer.of(context).curTheme.text60,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Settings items
            Expanded(
                child: Stack(
              children: <Widget>[
                ListView(
                  padding: EdgeInsets.only(top: 15.0),
                  children: <Widget>[
                    Container(
                      margin:
                          EdgeInsetsDirectional.only(start: 30.0, bottom: 10.0),
                      child: Text(AppLocalization.of(context).informations,
                          style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w100,
                              color:
                                  StateContainer.of(context).curTheme.text60)),
                    ),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemSingleLineWithInfos(
                      context,
                      AppLocalization.of(context).bisPrice,
                      _getPriceInfo(context),
                      FontAwesome.money,
                      onPressed: () {
                        _showExchangesSheet(context);
                      },
                    ),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    Container(
                      margin: EdgeInsetsDirectional.only(
                          start: 30.0, top: 20.0, bottom: 10.0),
                      child: Text(AppLocalization.of(context).manage,
                          style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w100,
                              color:
                                  StateContainer.of(context).curTheme.text60)),
                    ),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemSingleLine(
                        context,
                        AppLocalization.of(context).customUrlHeader,
                        FontAwesome.code, onPressed: () {
                      setState(() {
                        _customUrlOpen = true;
                      });
                      _customUrlController.forward();
                    }),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemSingleLine(
                        context,
                        AppLocalization.of(context).contactsHeader,
                        AppIcons.addcontact, onPressed: () {
                      setState(() {
                        _contactsOpen = true;
                      });
                      _contactsController.forward();
                    }),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    Container(
                      margin: EdgeInsetsDirectional.only(
                          start: 30.0, top: 20.0, bottom: 10.0),
                      child: Text(AppLocalization.of(context).preferences,
                          style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w100,
                              color:
                                  StateContainer.of(context).curTheme.text60)),
                    ),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemDoubleLine(
                        context,
                        AppLocalization.of(context).changeCurrency,
                        StateContainer.of(context).curCurrency,
                        FontAwesome.money,
                        _currencyDialog),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemDoubleLine(
                        context,
                        AppLocalization.of(context).language,
                        StateContainer.of(context).curLanguage,
                        FontAwesome.language,
                        _languageDialog),
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemSingleLine(
                        context,
                        AppLocalization.of(context).securityHeader,
                        AppIcons.security, onPressed: () {
                      setState(() {
                        _securityOpen = true;
                      });
                      _securityController.forward();
                    }),
                    /*Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemSingleLine(
                        context,
                        AppLocalization.of(context).logout,
                        FontAwesome.logout, onPressed: () {
                      AppDialogs.showConfirmDialog(
                          context,
                          CaseChange.toUpperCase(
                              AppLocalization.of(context).warning, context),
                          AppLocalization.of(context).logoutDetail,
                          AppLocalization.of(context)
                              .logoutAction
                              .toUpperCase(), () {
                        // Show another confirm dialog
                        AppDialogs.showConfirmDialog(
                            context,
                            AppLocalization.of(context).logoutAreYouSure,
                            AppLocalization.of(context).logoutReassurance,
                            CaseChange.toUpperCase(
                                AppLocalization.of(context).yes, context), () {
                          // Delete all data
                          sl.get<Vault>().deleteAll().then((_) {
                            sl
                                .get<SharedPrefsUtil>()
                                .deleteAll()
                                .then((result) {
                              StateContainer.of(context).logOut();
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/', (Route<dynamic> route) => false);
                            });
                          });
                        });
                      });
                    }),*/
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 10.0, bottom: 10.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(versionString,
                              style: AppStyles.textStyleVersion(context)),
                          Text(" | ",
                              style: AppStyles.textStyleVersion(context)),
                          GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (BuildContext context) {
                                  return UIUtil.showWebview(
                                      context,
                                      AppLocalization.of(context).privacyUrl,
                                      '');
                                }));
                              },
                              child: Text(
                                  AppLocalization.of(context).privacyPolicy,
                                  style: AppStyles.textStyleVersionUnderline(
                                      context))),
                        ],
                      ),
                    ),
                  ].where(notNull).toList(),
                ),
                //List Top Gradient End
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 20.0,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          StateContainer.of(context).curTheme.backgroundDark,
                          StateContainer.of(context).curTheme.backgroundDark00
                        ],
                        begin: AlignmentDirectional(0.5, -1.0),
                        end: AlignmentDirectional(0.5, 1.0),
                      ),
                    ),
                  ),
                ), //List Top Gradient End
              ],
            )),
          ],
        ),
      ),
    );
  }

  Widget buildSecurityMenu(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StateContainer.of(context).curTheme.backgroundDark,
        boxShadow: [
          BoxShadow(
              color: StateContainer.of(context).curTheme.overlay30,
              offset: Offset(-5, 0),
              blurRadius: 20),
        ],
      ),
      child: SafeArea(
        minimum: EdgeInsets.only(
          top: 60,
        ),
        child: Column(
          children: <Widget>[
            // Back button and Security Text
            Container(
              margin: EdgeInsets.only(bottom: 10.0, top: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      //Back button
                      Container(
                        height: 40,
                        width: 40,
                        margin: EdgeInsets.only(right: 10, left: 10),
                        child: TextButton(
                            onPressed: () {
                              setState(() {
                                _securityOpen = false;
                              });
                              _securityController.reverse();
                            },
                            child: Icon(AppIcons.back,
                                color: StateContainer.of(context).curTheme.text,
                                size: 24)),
                      ),
                      //Security Header Text
                      Text(
                        AppLocalization.of(context).securityHeader,
                        style: AppStyles.textStyleSettingsHeader(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
                child: Stack(
              children: <Widget>[
                ListView(
                  padding: EdgeInsets.only(top: 15.0),
                  children: <Widget>[
                    Container(
                      margin:
                          EdgeInsetsDirectional.only(start: 30.0, bottom: 10),
                      child: Text(AppLocalization.of(context).preferences,
                          style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w100,
                              color:
                                  StateContainer.of(context).curTheme.text60)),
                    ),
                    // Backup Secret Phrase
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemSingleLine(
                        context,
                        AppLocalization.of(context).backupSecretPhrase,
                        AppIcons.backupseed, onPressed: () async {
                      // Authenticate
                      AuthenticationMethod authMethod =
                          await sl.get<SharedPrefsUtil>().getAuthMethod();
                      bool hasBiometrics =
                          await sl.get<BiometricUtil>().hasBiometrics();
                      if (authMethod.method == AuthMethod.BIOMETRICS &&
                          hasBiometrics) {
                        try {
                          bool authenticated = await sl
                              .get<BiometricUtil>()
                              .authenticateWithBiometrics(
                                  context,
                                  AppLocalization.of(context)
                                      .fingerprintSeedBackup);
                          if (authenticated) {
                            HapticUtil.lightFeedback();
                            try {
                              // For backup, use proper seed access method that handles both password and non-password modes
                              String? seed =
                                  await AppUtil.getSeedSafely(context);
                              if (seed != null) {
                                AppSeedBackupSheet(seed)
                                    .mainBottomSheet(context);
                              } else {
                                print("Error: Could not get seed for backup");
                                await authenticateWithPin();
                              }
                            } catch (e) {
                              print("Error getting seed for backup: $e");
                              await authenticateWithPin();
                            }
                          }
                        } catch (e) {
                          await authenticateWithPin();
                        }
                      } else {
                        await authenticateWithPin();
                      }
                    }),
                    // Authentication Method
                    if (_hasBiometrics) ...[
                      Divider(
                        height: 2,
                        color: StateContainer.of(context).curTheme.text15,
                      ),
                      AppSettings.buildSettingsListItemDoubleLine(
                          context,
                          AppLocalization.of(context).authMethod,
                          _curAuthMethod,
                          AppIcons.fingerprint,
                          _authMethodDialog),
                    ],
                    // Authenticate on Launch
                    !_isPasswordMode
                        ? Column(children: <Widget>[
                            Divider(
                                height: 2,
                                color:
                                    StateContainer.of(context).curTheme.text15),
                            AppSettings.buildSettingsListItemDoubleLine(
                                context,
                                AppLocalization.of(context).lockAppSetting,
                                _curUnlockSetting,
                                AppIcons.lock,
                                _lockDialog),
                          ])
                        : SizedBox(),
                    // Authentication Timer
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemDoubleLine(
                      context,
                      AppLocalization.of(context).autoLockHeader,
                      _curTimeoutSetting,
                      AppIcons.timer,
                      _lockTimeoutDialog,
                      disabled: _curUnlockSetting.setting == UnlockOption.NO &&
                          !_isPasswordMode,
                    ),
                    // Encrypt option - check if seed is actually encrypted, not if encryptedSecret exists
                    !_isPasswordMode
                        ? Column(children: <Widget>[
                            Divider(
                                height: 2,
                                color:
                                    StateContainer.of(context).curTheme.text15),
                            AppSettings.buildSettingsListItemSingleLine(
                                context,
                                AppLocalization.of(context).setWalletPassword,
                                AppIcons.walletpassword, onPressed: () async {
                              await Sheets.showAppHeightNineSheet(
                                  context: context, widget: SetPasswordSheet());
                              // Refresh password mode state after setting password
                              bool isPasswordMode = await _checkPasswordMode();
                              if (mounted) {
                                setState(() {
                                  _isPasswordMode = isPasswordMode;
                                });
                              }
                            })
                          ])
                        : // Decrypt option
                        Column(children: <Widget>[
                            Divider(
                                height: 2,
                                color:
                                    StateContainer.of(context).curTheme.text15),
                            AppSettings.buildSettingsListItemSingleLine(
                                context,
                                AppLocalization.of(context)
                                    .disableWalletPassword,
                                AppIcons.walletpassworddisabled,
                                onPressed: () async {
                              await Sheets.showAppHeightNineSheet(
                                  context: context,
                                  widget: DisablePasswordSheet());
                              // Refresh password mode state after disabling password
                              bool isPasswordMode = await _checkPasswordMode();
                              if (mounted) {
                                setState(() {
                                  _isPasswordMode = isPasswordMode;
                                });
                              }
                            }),
                          ]),
                    // Reset Account Seed option
                    Divider(
                      height: 2,
                      color: StateContainer.of(context).curTheme.text15,
                    ),
                    AppSettings.buildSettingsListItemSingleLine(
                      context,
                      "Reset Account Seed",
                      Icons.refresh_rounded,
                      onPressed: () {
                        _showResetConfirmation();
                      },
                    ),
                    Divider(
                        height: 2,
                        color: StateContainer.of(context).curTheme.text15),
                  ].where(notNull).toList(),
                ),
                //List Top Gradient End
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 20.0,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          StateContainer.of(context).curTheme.backgroundDark,
                          StateContainer.of(context).curTheme.backgroundDark00
                        ],
                        begin: AlignmentDirectional(0.5, -1.0),
                        end: AlignmentDirectional(0.5, 1.0),
                      ),
                    ),
                  ),
                ), //List Top Gradient End
              ],
            )),
          ],
        ),
      ),
    );
  }

  void _showResetConfirmation() {
    AppDialogs.showConfirmDialog(
      context,
      "Warning",
      "Are you sure you want to reset your wallet? This will delete your current seed and all accounts. Make sure you have backed up your seed phrase!",
      "Continue",
      () {
        // Show second confirmation
        AppDialogs.showConfirmDialog(
          context,
          "Final Warning",
          "This action cannot be undone. Your current wallet will be permanently deleted. Do you want to proceed?",
          "Yes, Reset Wallet",
          () {
            // Proceed with PIN authentication
            _authenticateForReset();
          },
          cancelText: "Cancel",
        );
      },
      cancelText: "Cancel",
    );
  }

  Future<void> _authenticateForReset() async {
    // PIN Authentication for reset
    String? expectedPin = await sl.get<Vault>().getPin();
    if (expectedPin == null) {
      return;
    }

    bool authenticated = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (BuildContext context) {
      return PinScreen(
        PinOverlayType.ENTER_PIN,
        expectedPin: expectedPin,
        description: "Enter PIN to reset wallet",
      );
    }));

    if (authenticated != null && authenticated) {
      // Reset the wallet
      await _performWalletReset();
    }
  }

  Future<void> _performWalletReset() async {
    try {
      // Clear all wallet data
      await sl.get<DBHelper>().dropAll();
      await sl.get<Vault>().deleteAll();
      await sl.get<SharedPrefsUtil>().deleteAll();

      // Navigate to intro welcome screen
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/intro_welcome',
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      log.e("Error resetting wallet: $e");
      // Show error dialog
      AppDialogs.showConfirmDialog(
        context,
        "Error",
        "Failed to reset wallet. Please try again.",
        "OK",
        () {},
      );
    }
  }

  Future<void> authenticateWithPin() async {
    // PIN Authentication
    String expectedPin = await sl.get<Vault>().getPin();
    bool auth = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (BuildContext context) {
      return new PinScreen(
        PinOverlayType.ENTER_PIN,
        expectedPin: expectedPin,
        description: AppLocalization.of(context).pinSeedBackup,
      );
    }));
    if (auth) {
      await Future.delayed(Duration(milliseconds: 200));
      Navigator.of(context).pop();
      try {
        // For backup, use proper seed access method that handles both password and non-password modes
        String? seed = await AppUtil.getSeedSafely(context);
        if (seed != null) {
          AppSeedBackupSheet(seed).mainBottomSheet(context);
        } else {
          print("Error: Could not get seed for backup");
          // Show error dialog if seed retrieval fails
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error accessing wallet seed. Please try again."),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print("Error getting seed for backup: $e");
        // Show error dialog if seed retrieval fails
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error accessing wallet seed. Please try again."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getPriceInfo(BuildContext context) {
    final wallet = StateContainer.of(context).wallet;
    final currency = StateContainer.of(context).curCurrency;
    final selectedDex =
        StateContainer.of(context).selectedDefaultDex ?? DefaultDex.PANCAKESWAP;

    if (wallet == null) {
      return "Loading...";
    }

    // Get prices from PriceManager for selected DEX
    PriceData? priceData;
    PriceManager priceManager = PriceManager.instance;
    
    // Get price data for current selected DEX
    priceData = priceManager.selectedPrice;
    
    String btcPriceStr = priceData?.btcPrice.toString() ?? "0";
    String localPriceStr = priceData?.localCurrencyPrice.toString() ?? "0";

    // Parse the prices
    double btcPrice = double.tryParse(btcPriceStr) ?? 0;
    double localPrice = double.tryParse(localPriceStr) ?? 0;

    if (btcPrice == 0 && localPrice == 0) {
      return "Price unavailable";
    }

    // Format BTC price (show more decimal places for small values)
    String formattedBtcPrice = btcPrice < 0.001
        ? btcPrice.toStringAsFixed(8)
        : btcPrice.toStringAsFixed(6);
    formattedBtcPrice = formattedBtcPrice
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');

    // Format local currency price
    String formattedLocalPrice = localPrice < 1
        ? localPrice.toStringAsFixed(6)
        : localPrice.toStringAsFixed(2);
    formattedLocalPrice = formattedLocalPrice
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');

    // Add source indicator based on selected DEX
    String source = "";
    switch (selectedDex) {
      case DefaultDex.AGGREGATED:
        source = " (Aggregated)";
        break;
      case DefaultDex.UNISWAP_V2:
        source = " (via Uniswap V2)";
        break;
      case DefaultDex.PANCAKESWAP:
        source = " (via PancakeSwap)";
        break;
    }

    return "$formattedBtcPrice BTC\n${currency.getCurrencySymbol()}$formattedLocalPrice$source";
  }

  void _showExchangesSheet(BuildContext context) async {
    // Request fresh price update to ensure we have latest DEX prices
    StateContainer.of(context).requestPriceUpdate(forceRefresh: true);
    
    // Show exchanges sheet - it will get prices from PriceManager
    AppExchangesSheet(null).mainBottomSheet(context);
  }
}
