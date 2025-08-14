// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logger/logger.dart';
import 'package:oktoast/oktoast.dart';

// Project imports:
import 'package:my_bismuth_wallet/appstate_container.dart';
import 'package:my_bismuth_wallet/localization.dart';
import 'package:my_bismuth_wallet/model/available_language.dart';
import 'package:my_bismuth_wallet/model/db/appdb.dart';
import 'package:my_bismuth_wallet/model/vault.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/styles.dart';
import 'package:my_bismuth_wallet/ui/before_scan_screen.dart';
import 'package:my_bismuth_wallet/ui/home_page.dart';
import 'package:my_bismuth_wallet/ui/intro/intro_backup_confirm.dart';
import 'package:my_bismuth_wallet/ui/intro/intro_backup_safety.dart';
import 'package:my_bismuth_wallet/ui/intro/intro_backup_seed.dart';
import 'package:my_bismuth_wallet/ui/intro/intro_import_seed.dart';
import 'package:my_bismuth_wallet/ui/intro/intro_password.dart';
import 'package:my_bismuth_wallet/ui/intro/intro_password_on_launch.dart';
import 'package:my_bismuth_wallet/ui/intro/intro_welcome.dart';
import 'package:my_bismuth_wallet/ui/lock_screen.dart';
import 'package:my_bismuth_wallet/ui/password_lock_screen.dart';
import 'package:my_bismuth_wallet/ui/util/routes.dart';
import 'package:my_bismuth_wallet/util/app_ffi/apputil.dart';
import 'package:my_bismuth_wallet/util/helpers.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

//import 'package:safe_device/safe_device.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DBHelper.setupDatabase();

  // Setup Service Provide
  setupServiceLocator();
  // Setup logger, only show warning and higher in release mode.
  if (kReleaseMode) {
    Logger.level = Level.warning;
  } else {
    Logger.level = Level.debug;
  }
  // Run app
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((_) {
    runApp(new StateContainer(child: new App()));
  });
}

class App extends StatefulWidget {
  @override
  _AppState createState() => new _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
  }

  // This widget is the root of the application.
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
        StateContainer.of(context).curTheme.statusBar);
    return OKToast(
      textStyle: AppStyles.textStyleSnackbar(context),
      backgroundColor: StateContainer.of(context).curTheme.backgroundDark,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'my Bismuth Wallet',
        theme: ThemeData(
          primaryColor: StateContainer.of(context).curTheme.primary,
          fontFamily: 'Roboto',
          brightness: Brightness.dark,
          colorScheme:
              ColorScheme.fromSwatch(brightness: Brightness.dark).copyWith(
            secondary: StateContainer.of(context).curTheme.primary10,
            surface: StateContainer.of(context).curTheme.backgroundDark,
          ),
          dialogTheme: DialogThemeData(
              backgroundColor:
                  StateContainer.of(context).curTheme.backgroundDark),
        ),
        localizationsDelegates: [
          AppLocalizationsDelegate(StateContainer.of(context).curLanguage),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate
        ],
        locale: StateContainer.of(context).curLanguage.language ==
                AvailableLanguage.DEFAULT
            ? null
            : StateContainer.of(context).curLanguage.getLocale(),
        supportedLocales: [
          const Locale('en', 'US'), // English
          // Currency-default requires country included
          const Locale('es', 'AR'),
          const Locale('en', 'AU'),
          const Locale('pt', 'BR'),
          const Locale('en', 'CA'),
          const Locale('de', 'CH'),
          const Locale('es', 'CL'),
          const Locale('zh', 'CN'),
          const Locale('cs', 'CZ'),
          const Locale('da', 'DK'),
          const Locale('fr', 'FR'),
          const Locale('en', 'GB'),
          const Locale('zh', 'HK'),
          const Locale('hu', 'HU'),
          const Locale('id', 'ID'),
          const Locale('he', 'IL'),
          const Locale('hi', 'IN'),
          const Locale('ja', 'JP'),
          const Locale('ko', 'KR'),
          const Locale('es', 'MX'),
          const Locale('ta', 'MY'),
          const Locale('en', 'NZ'),
          const Locale('tl', 'PH'),
          const Locale('ur', 'PK'),
          const Locale('pl', 'PL'),
          const Locale('ru', 'RU'),
          const Locale('sv', 'SE'),
          const Locale('zh', 'SG'),
          const Locale('th', 'TH'),
          const Locale('tr', 'TR'),
          const Locale('en', 'TW'),
          const Locale('es', 'VE'),
          const Locale('en', 'ZA'),
          const Locale('en', 'US'),
          const Locale('es', 'AR'),
          const Locale('de', 'AT'),
          const Locale('fr', 'BE'),
          const Locale('de', 'BE'),
          const Locale('nl', 'BE'),
          const Locale('tr', 'CY'),
          const Locale('et', 'EE'),
          const Locale('fi', 'FI'),
          const Locale('fr', 'FR'),
          const Locale('el', 'GR'),
          const Locale('es', 'AR'),
          const Locale('en', 'IE'),
          const Locale('it', 'IT'),
          const Locale('es', 'AR'),
          const Locale('lv', 'LV'),
          const Locale('lt', 'LT'),
          const Locale('fr', 'LU'),
          const Locale('en', 'MT'),
          const Locale('nl', 'NL'),
          const Locale('pt', 'PT'),
          const Locale('sk', 'SK'),
          const Locale('sl', 'SI'),
          const Locale('es', 'ES'),
          const Locale('ar', 'AE'), // UAE
          const Locale('ar', 'SA'), // Saudi Arabia
          const Locale('ar', 'KW'), // Kuwait
        ],
        initialRoute: '/splash',
        onGenerateRoute: (RouteSettings settings) {
          switch (settings.name) {
            case '/splash':
              return NoTransitionRoute(
                builder: (_) => Splash(),
                settings: settings,
              );
            case '/home':
              return NoTransitionRoute(
                builder: (_) => AppHomePage(
                    priceConversion: settings.arguments as PriceConversion?),
                settings: settings,
              );
            case '/home_transition':
              return NoPopTransitionRoute(
                builder: (_) => AppHomePage(
                    priceConversion: settings.arguments as PriceConversion?),
                settings: settings,
              );
            case '/intro_welcome':
              return NoTransitionRoute(
                builder: (_) => IntroWelcomePage(),
                settings: settings,
              );
            case '/intro_password_on_launch':
              return MaterialPageRoute(
                builder: (_) =>
                    IntroPasswordOnLaunch(seed: settings.arguments as String),
                settings: settings,
              );
            case '/intro_password':
              return MaterialPageRoute(
                builder: (_) =>
                    IntroPassword(seed: settings.arguments as String? ?? ""),
                settings: settings,
              );
            case '/intro_backup':
              return MaterialPageRoute(
                builder: (_) => IntroBackupSeedPage(
                    encryptedSeed: settings.arguments as String? ?? ""),
                settings: settings,
              );
            case '/intro_backup_safety':
              return MaterialPageRoute(
                builder: (_) => IntroBackupSafetyPage(),
                settings: settings,
              );
            case '/intro_backup_confirm':
              return MaterialPageRoute(
                builder: (_) => IntroBackupConfirm(),
                settings: settings,
              );
            case '/intro_import':
              return MaterialPageRoute(
                builder: (_) => IntroImportSeedPage(),
                settings: settings,
              );
            case '/lock_screen':
              return NoTransitionRoute(
                builder: (_) => AppLockScreen(),
                settings: settings,
              );
            case '/lock_screen_transition':
              return MaterialPageRoute(
                builder: (_) => AppLockScreen(),
                settings: settings,
              );
            case '/password_lock_screen':
              return NoTransitionRoute(
                builder: (_) => AppPasswordLockScreen(),
                settings: settings,
              );
            case '/before_scan_screen':
              return NoTransitionRoute(
                builder: (_) => BeforeScanScreen(),
                settings: settings,
              );
            default:
              return null;
          }
        },
        // home: IntroWelcomePage(), // Removed - causes navigation issues
      ),
    );
  }
}

/// Splash
/// Default page route that determines if user is logged in and routes them appropriately.
class Splash extends StatefulWidget {
  @override
  SplashState createState() => new SplashState();
}

class SplashState extends State<Splash> with WidgetsBindingObserver {
  bool _hasCheckedLoggedIn = false;
  bool _retried = false;

  bool seedIsEncrypted(String seed) {
    try {
      String salted = AppHelpers.bytesToUtf8String(
          AppHelpers.hexToBytes(seed.substring(0, 16)));
      if (salted == "Salted__") {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future checkLoggedIn() async {
    print('checkLoggedIn started');
    // Android 15 fix: Defer secure storage access until after UI initialization
    try {
      // Initialize session key if not exists, don't regenerate existing one
      String existingKey = await sl.get<Vault>().getSessionKey().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('Session key timeout - returning empty');
          return "";
        }
      );
      if (existingKey.isEmpty) {
        await sl.get<Vault>().updateSessionKey();
      }
    } catch (e) {
      // Android 15 compatibility: If secure storage fails, continue without session key
      // The session key will be initialized later during normal app flow
      print('SecureStorage access deferred: $e');
    }

    if (!kIsWeb &&
        !Platform.isMacOS &&
        !Platform.isWindows &&
        !Platform.isLinux) {
      // Check if device is rooted or jailbroken, show user a warning informing them of the risks if so
      /*if (!(await sl.get<SharedPrefsUtil>().getHasSeenRootWarning()) &&
          (await SafeDevice.isJailBroken)) {
        AppDialogs.showConfirmDialog(
            context,
            CaseChange.toUpperCase(
                AppLocalization.of(context).warning, context),
            AppLocalization.of(context).rootWarning,
            AppLocalization.of(context).iUnderstandTheRisks.toUpperCase(),
            () async {
              await sl.get<SharedPrefsUtil>().setHasSeenRootWarning();
              checkLoggedIn();
            },
            cancelText: AppLocalization.of(context).exit.toUpperCase(),
            cancelAction: () {
              if (!kIsWeb && Platform.isIOS) {
                exit(0);
              } else {
                SystemChannels.platform.invokeMethod('SystemNavigator.pop');
              }
            });
        return;
      }*/
    }

    if (!_hasCheckedLoggedIn) {
      _hasCheckedLoggedIn = true;
    } else {
      return;
    }
    try {
      // iOS key store is persistent, so if this is first launch then we will clear the keystore
      bool firstLaunch = await sl.get<SharedPrefsUtil>().getFirstLaunch();
      if (firstLaunch) {
        await sl.get<DBHelper>().dropAll();
        await sl.get<Vault>().deleteAll();
      }
      await sl.get<SharedPrefsUtil>().setFirstLaunch();
      // See if logged in already
      bool isEncrypted = false;
      // Android 15 fix: Add timeout to secure storage operations with logging
      print('Attempting to get seed from vault...');
      var seed = await sl.get<Vault>().getSeed().timeout(
        Duration(seconds: 10), 
        onTimeout: () {
          print('getSeed timeout - returning empty');
          return "";
        }
      );
      print('Seed retrieved: ${seed.isNotEmpty}');
      
      print('Attempting to get pin from vault...');
      var pin = await sl.get<Vault>().getPin().timeout(
        Duration(seconds: 10), 
        onTimeout: () {
          print('getPin timeout - returning empty');
          return "";
        }
      );
      print('Pin retrieved: ${pin.isNotEmpty}');
      // If we have a seed set, but not a pin - or vice versa
      // Then delete the seed and pin from device and start over.
      // This would mean user did not complete the intro screen completely.
      bool isLoggedIn = seed.isNotEmpty && pin.isNotEmpty;
      if (isLoggedIn) {
        isEncrypted = seedIsEncrypted(seed);
      }

      if (isLoggedIn) {
        print('User is logged in, navigating to appropriate screen');
        if (isEncrypted) {
          print('Seed is encrypted, navigating to password lock screen');
          Navigator.of(context).pushNamedAndRemoveUntil(
              '/password_lock_screen', (Route<dynamic> route) => false);
        } else if (await sl.get<SharedPrefsUtil>().getLock() ||
            await sl.get<SharedPrefsUtil>().shouldLock()) {
          print('Lock required, navigating to lock screen');
          Navigator.of(context).pushNamedAndRemoveUntil(
              '/lock_screen', (Route<dynamic> route) => false);
        } else {
          print('No lock required, logging in and navigating to home');
          await AppUtil().loginAccount(seed, context);
          // Reset any lingering failed attempts from previous sessions
          await sl.get<SharedPrefsUtil>().resetLockAttempts();
          PriceConversion conversion =
              await sl.get<SharedPrefsUtil>().getPriceConversion();
          Navigator.of(context).pushNamedAndRemoveUntil(
              '/home_transition', (Route<dynamic> route) => false,
              arguments: conversion);
        }
      } else {
        // No valid seed/pin found, go to intro welcome page
        print('No valid seed/pin found, navigating to intro welcome');
        Navigator.of(context).pushReplacementNamed('/intro_welcome');
      }
    } catch (e) {
      print('Error in checkLoggedIn: $e');
      /// Fallback secure storage
      /// A very small percentage of users are encountering issues writing to the
      /// Android keyStore using the flutter_secure_storage plugin.
      ///
      /// Instead of telling them they are out of luck, this is an automatic "fallback"
      /// It will generate a 64-byte secret using the native android "bottlerocketstudios" Vault
      /// This secret is used to encrypt sensitive data and save it in SharedPreferences
      if (kIsWeb ||
          (!kIsWeb &&
              Platform.isAndroid &&
              e.toString().contains("flutter_secure"))) {
        print('Using legacy storage fallback');
        if (!(await sl.get<SharedPrefsUtil>().useLegacyStorage())) {
          await sl.get<SharedPrefsUtil>().setUseLegacyStorage();
          checkLoggedIn();
        } else {
          // If already using legacy storage and still failing, navigate to intro
          print('Legacy storage also failed, navigating to intro');
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/intro_welcome');
          }
        }
      } else {
        print('Clearing all data and retrying');
        await sl.get<Vault>().deleteAll();
        await sl.get<DBHelper>().dropAll();
        await sl.get<SharedPrefsUtil>().deleteAll();
        if (!_retried) {
          _retried = true;
          _hasCheckedLoggedIn = false;
          checkLoggedIn();
        } else {
          // If retry also failed, navigate to intro
          print('Retry failed, navigating to intro');
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/intro_welcome');
          }
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hasCheckedLoggedIn = false;
    _retried = false;
    
    // Android 15 fix: Always use post-frame callback with increased delay
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      // Increased delay for Android 15 compatibility
      await Future.delayed(Duration(milliseconds: 1000));
      print('Starting checkLoggedIn after delay');
      try {
        await checkLoggedIn();
      } catch (e) {
        print('Error in checkLoggedIn: $e');
        // Fallback to intro screen if check fails
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/intro_welcome');
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Account for user changing locale when leaving the app
    switch (state) {
      case AppLifecycleState.paused:
        super.didChangeAppLifecycleState(state);
        break;
      case AppLifecycleState.resumed:
        setLanguage();
        super.didChangeAppLifecycleState(state);
        break;
      default:
        super.didChangeAppLifecycleState(state);
        break;
    }
  }

  void setLanguage() {
    setState(() {
      StateContainer.of(context).deviceLocale = Localizations.localeOf(context);
    });
    sl.get<SharedPrefsUtil>().getLanguage().then((setting) {
      setState(() {
        StateContainer.of(context).curLanguage = setting;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    setLanguage();
    sl
        .get<SharedPrefsUtil>()
        .getCurrency(StateContainer.of(context).deviceLocale)
        .then((currency) {
      StateContainer.of(context).curCurrency = currency;
    });
    return new Scaffold(
      backgroundColor: StateContainer.of(context).curTheme.background,
    );
  }
}
