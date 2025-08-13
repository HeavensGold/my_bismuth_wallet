// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:my_bismuth_wallet/app_icons.dart';
import 'package:my_bismuth_wallet/appstate_container.dart';
import 'package:my_bismuth_wallet/dimens.dart';
import 'package:my_bismuth_wallet/localization.dart';
import 'package:my_bismuth_wallet/model/authentication_method.dart';
import 'package:my_bismuth_wallet/model/vault.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/styles.dart';
import 'package:my_bismuth_wallet/ui/util/routes.dart';
import 'package:my_bismuth_wallet/ui/widgets/buttons.dart';
import 'package:my_bismuth_wallet/ui/widgets/dialog.dart';
import 'package:my_bismuth_wallet/ui/widgets/security.dart';
import 'package:my_bismuth_wallet/util/app_ffi/apputil.dart';
import 'package:my_bismuth_wallet/util/biometrics.dart';
import 'package:my_bismuth_wallet/util/caseconverter.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

class AppLockScreen extends StatefulWidget {
  @override
  _AppLockScreenState createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _showUnlockButton = false;
  bool _showLock = false;
  bool _lockedOut = true;
  String _countDownTxt = "";
  bool _isInitializing = true;

  Future<void> _goHome() async {
    // Initialize the wallet properly after authentication
    try {
      String seed = await sl.get<Vault>().getSeed();
      await AppUtil().loginAccount(seed, context);

      // Wait for wallet state to be properly initialized before navigation
      await Future.delayed(Duration(milliseconds: 100));

      // Ensure requestUpdate completes before navigating
      StateContainer.of(context).requestUpdate();

      // Add small delay to prevent race condition with navigation
      await Future.delayed(Duration(milliseconds: 50));
    } catch (e) {
      print("Error initializing wallet after lock screen: $e");
    }

    PriceConversion conversion =
        await sl.get<SharedPrefsUtil>().getPriceConversion();
    Navigator.of(context).pushNamedAndRemoveUntil(
        '/home_transition', (Route<dynamic> route) => false,
        arguments: conversion);
  }

  Widget _buildPinScreen(BuildContext context, String expectedPin) {
    return PinScreen(PinOverlayType.ENTER_PIN,
        expectedPin: expectedPin,
        description: AppLocalization.of(context).unlockPin,
        pinScreenBackgroundColor:
            StateContainer.of(context).curTheme.backgroundDark);
  }

  String _formatCountDisplay(int count) {
    if (count <= 60) {
      // Seconds only
      String secondsStr = count.toString();
      if (count < 10) {
        secondsStr = "0" + secondsStr;
      }
      return "00:" + secondsStr;
    } else if (count > 60 && count <= 3600) {
      // Minutes:Seconds
      String minutesStr = "";
      int minutes = count ~/ 60;
      if (minutes < 10) {
        minutesStr = "0" + minutes.toString();
      } else {
        minutesStr = minutes.toString();
      }
      String secondsStr = "";
      int seconds = count % 60;
      if (seconds < 10) {
        secondsStr = "0" + seconds.toString();
      } else {
        secondsStr = seconds.toString();
      }
      return minutesStr + ":" + secondsStr;
    } else {
      // Hours:Minutes:Seconds
      String hoursStr = "";
      int hours = count ~/ 3600;
      if (hours < 10) {
        hoursStr = "0" + hours.toString();
      } else {
        hoursStr = hours.toString();
      }
      count = count % 3600;
      String minutesStr = "";
      int minutes = count ~/ 60;
      if (minutes < 10) {
        minutesStr = "0" + minutes.toString();
      } else {
        minutesStr = minutes.toString();
      }
      String secondsStr = "";
      int seconds = count % 60;
      if (seconds < 10) {
        secondsStr = "0" + seconds.toString();
      } else {
        secondsStr = seconds.toString();
      }
      return hoursStr + ":" + minutesStr + ":" + secondsStr;
    }
  }

  Future<void> _runCountdown(int count) async {
    if (count >= 1) {
      if (mounted) {
        setState(() {
          _showUnlockButton = true;
          _showLock = true;
          _lockedOut = true;
          _countDownTxt = _formatCountDisplay(count);
        });
      }
      Future.delayed(Duration(seconds: 1), () {
        _runCountdown(count - 1);
      });
    } else {
      if (mounted) {
        setState(() {
          _lockedOut = false;
        });
      }
    }
  }

  Future<void> authenticateWithBiometrics() async {
    bool authenticated = await sl
        .get<BiometricUtil>()
        .authenticateWithBiometrics(
            context, AppLocalization.of(context).unlockBiometrics);
    if (authenticated) {
      // Reset failed lock attempts on successful authentication
      await sl.get<SharedPrefsUtil>().resetLockAttempts();
      _goHome();
    } else {
      setState(() {
        _showUnlockButton = true;
      });
    }
  }

  Future<void> authenticateWithPin({bool transitions = false}) async {
    String expectedPin = await sl.get<Vault>().getPin();
    bool auth = false;
    if (transitions) {
      auth = await Navigator.of(context).push(
        MaterialPageRoute(builder: (BuildContext context) {
          return _buildPinScreen(context, expectedPin);
        }),
      );
    } else {
      auth = await Navigator.of(context).push(
        NoPushTransitionRoute(builder: (BuildContext context) {
          return _buildPinScreen(context, expectedPin);
        }),
      );
    }

    if (auth) {
      // Successful authentication - keep _isInitializing true to prevent UI flash
      // The navigation will remove this screen anyway
      _goHome();
    } else {
      // Failed authentication or user cancelled - show the lock UI
      await Future.delayed(Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _showUnlockButton = true;
          _showLock = true;
        });
      }
    }
  }

  Future<void> _authenticate({bool transitions = false}) async {
    // Test if user is locked out
    // First check if we should lock at all
    bool shouldLock = await sl.get<SharedPrefsUtil>().shouldLock();
    if (shouldLock) {
      // Get duration of lockout
      DateTime? lockUntil = await sl.get<SharedPrefsUtil>().getLockDate();
      if (lockUntil == null) {
        // If we don't have a lock date but shouldLock is true (attempts >= 5),
        // we need to set a lock date
        await sl.get<SharedPrefsUtil>().updateLockDate();
        lockUntil = await sl.get<SharedPrefsUtil>().getLockDate();
      }

      if (lockUntil != null) {
        int countDown = lockUntil.difference(DateTime.now().toUtc()).inSeconds;
        // They're not allowed to attempt
        if (countDown > 0) {
          setState(() {
            _isInitializing = false;
          });
          _runCountdown(countDown);
          return;
        }
      }
    }
    setState(() {
      _lockedOut = false;
    });
    AuthenticationMethod authMethod =
        await sl.get<SharedPrefsUtil>().getAuthMethod();
    bool hasBiometrics = await sl.get<BiometricUtil>().hasBiometrics();
    if (authMethod.method == AuthMethod.BIOMETRICS && hasBiometrics) {
      setState(() {
        _isInitializing = false;
        _showLock = true;
        _showUnlockButton = true;
      });
      try {
        await authenticateWithBiometrics();
      } catch (e) {
        await authenticateWithPin(transitions: transitions);
      }
    } else {
      // For PIN-only auth, keep _isInitializing = true to prevent UI flash
      // The PIN screen will handle setting it to false only if auth fails
      await authenticateWithPin(transitions: transitions);
    }
  }

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false, // Prevent back button from bypassing authentication
        child: Scaffold(
            body: Container(
                color: StateContainer.of(context).curTheme.backgroundDark,
                width: double.infinity,
                child: _isInitializing
                    ? Container() // Show nothing while initializing
                    : SafeArea(
                        minimum: EdgeInsets.only(
                          bottom: MediaQuery.of(context).size.height * 0.035,
                        ),
                        child: Column(
                          children: <Widget>[
                            // Logout button
                            Container(
                              margin: EdgeInsetsDirectional.only(
                                  start: 16, top: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: <Widget>[
                                  TextButton(
                                    onPressed: () {
                                      AppDialogs.showConfirmDialog(
                                          context,
                                          CaseChange.toUpperCase(
                                              AppLocalization.of(context)
                                                  .warning,
                                              context),
                                          AppLocalization.of(context)
                                              .logoutDetail,
                                          AppLocalization.of(context)
                                              .logoutAction
                                              .toUpperCase(), () {
                                        // Show another confirm dialog
                                        AppDialogs.showConfirmDialog(
                                            context,
                                            AppLocalization.of(context)
                                                .logoutAreYouSure,
                                            AppLocalization.of(context)
                                                .logoutReassurance,
                                            CaseChange.toUpperCase(
                                                AppLocalization.of(context).yes,
                                                context),
                                            () {});
                                      });
                                    },
                                    child: Container(
                                      child: Row(
                                        children: <Widget>[
                                          Icon(AppIcons.logout,
                                              size: 16,
                                              color: StateContainer.of(context)
                                                  .curTheme
                                                  .text),
                                          Container(
                                            margin: EdgeInsetsDirectional.only(
                                                start: 4),
                                            child: Text(
                                                AppLocalization.of(context)
                                                    .logout,
                                                style: AppStyles
                                                    .textStyleLogoutButton(
                                                        context)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _showLock
                                  ? Column(
                                      children: <Widget>[
                                        Container(
                                          child: Icon(
                                            AppIcons.lock,
                                            size: 80,
                                            color: StateContainer.of(context)
                                                .curTheme
                                                .primary,
                                          ),
                                          margin: EdgeInsets.only(
                                              top: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.1),
                                        ),
                                        Container(
                                          child: Text(
                                            CaseChange.toUpperCase(
                                                AppLocalization.of(context)
                                                    .locked,
                                                context),
                                            style: AppStyles
                                                .textStyleHeaderColored(
                                                    context),
                                          ),
                                          margin: EdgeInsets.only(top: 10),
                                        ),
                                      ],
                                    )
                                  : SizedBox(),
                            ),
                            _lockedOut
                                ? Container(
                                    width:
                                        MediaQuery.of(context).size.width - 100,
                                    margin:
                                        EdgeInsets.symmetric(horizontal: 50),
                                    child: Text(
                                      AppLocalization.of(context)
                                          .tooManyFailedAttempts,
                                      style: AppStyles.textStyleErrorMedium(
                                          context),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : SizedBox(),
                            _showUnlockButton
                                ? Row(
                                    children: <Widget>[
                                      AppButton.buildAppButton(
                                          context,
                                          AppButtonType.PRIMARY,
                                          _lockedOut
                                              ? _countDownTxt
                                              : AppLocalization.of(context)
                                                  .unlock,
                                          Dimens.BUTTON_BOTTOM_DIMENS,
                                          onPressed: () {
                                        if (!_lockedOut) {
                                          _authenticate(transitions: true);
                                        }
                                      }, disabled: _lockedOut),
                                    ],
                                  )
                                : SizedBox(),
                          ],
                        )))));
  }
}
