

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

// Package imports:
import 'package:auto_size_text/auto_size_text.dart';
import 'package:event_taxi/event_taxi.dart';
import 'package:hex/hex.dart';
// import 'package:flare_flutter/base/animation/actor_animation.dart'; // Removed - deprecated
// import 'package:flare_flutter/flare.dart'; // Removed - deprecated  
// import 'package:flare_flutter/flare_actor.dart'; // Removed - deprecated
// import 'package:flare_flutter/flare_controller.dart'; // Removed - deprecated
import 'package:fluttericon/font_awesome5_icons.dart';
import 'package:fluttericon/font_awesome_icons.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Project imports:
import 'package:my_bismuth_wallet/app_icons.dart';
import 'package:my_bismuth_wallet/appstate_container.dart';
import 'package:my_bismuth_wallet/bus/events.dart';
import 'package:my_bismuth_wallet/dimens.dart';
import 'package:my_bismuth_wallet/localization.dart';
// import 'package:my_bismuth_wallet/model/bis_url.dart'; // Commented out - file deleted
import 'package:my_bismuth_wallet/model/db/appdb.dart';
import 'package:my_bismuth_wallet/model/db/hiveDB.dart';
import 'package:my_bismuth_wallet/model/vault.dart';
import 'package:my_bismuth_wallet/network/model/block_types.dart';
import 'package:my_bismuth_wallet/network/model/response/address_txs_response.dart';
import 'package:my_bismuth_wallet/service/app_service.dart';
import 'package:my_bismuth_wallet/service/http_service.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/styles.dart';
import 'package:my_bismuth_wallet/ui/contacts/add_contact.dart';
import 'package:my_bismuth_wallet/ui/popup_button.dart';
import 'package:my_bismuth_wallet/ui/receive/receive_sheet.dart';
import 'package:my_bismuth_wallet/ui/send/send_sheet.dart';
import 'package:my_bismuth_wallet/ui/settings/settings_drawer.dart';
// import 'package:my_bismuth_wallet/ui/tokens/my_tokens_list.dart'; // Commented out - file deleted
import 'package:my_bismuth_wallet/ui/util/routes.dart';
import 'package:my_bismuth_wallet/ui/util/ui_util.dart';
import 'package:my_bismuth_wallet/ui/widgets/buttons.dart';
import 'package:my_bismuth_wallet/ui/widgets/dialog.dart';
import 'package:my_bismuth_wallet/ui/widgets/list_slidable.dart';
import 'package:my_bismuth_wallet/ui/widgets/reactive_refresh.dart';
import 'package:my_bismuth_wallet/ui/widgets/sheet_util.dart';
import 'package:my_bismuth_wallet/ui/widgets/sync_info_view.dart';
import 'package:my_bismuth_wallet/util/app_ffi/apputil.dart';
import 'package:my_bismuth_wallet/util/app_ffi/encrypt/crypter.dart';
import 'package:my_bismuth_wallet/util/caseconverter.dart';
import 'package:my_bismuth_wallet/util/hapticutil.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

class AppHomePage extends StatefulWidget {
  final PriceConversion? priceConversion;

  const AppHomePage({super.key, this.priceConversion});

  @override
  _AppHomePageState createState() => _AppHomePageState();
}

class _AppHomePageState extends State<AppHomePage>
    with
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  final Logger log = sl.get<Logger>();

  // Controller for placeholder card animations
  late AnimationController _placeholderCardAnimationController;
  late Animation<double> _opacityAnimation;
  late bool _animationDisposed;

  late bool _displayReleaseNote;

  int _eggPrice = 0;

  // Receive card instance
  late ReceiveSheet receive;

  // A separate unfortunate instance of this list, is a little unfortunate
  // but seems the only way to handle the animations
  final Map<String, GlobalKey<AnimatedListState>> _listKeyMap = Map();

  // List of contacts (Store it so we only have to query the DB once for transaction cards)
  List<Contact> _contacts = <Contact>[];

  // Price conversion state (BTC, app cryptocurrency, NONE)
  late PriceConversion _priceConversion;

  bool _isRefreshing = false;
  int _historyVersion = 0; // bump to force list rebuild when content changes without length change

  bool _lockDisabled = false; // whether we should avoid locking the app
  
  Timer? _updateTimer; // Timer for periodic updates
  DateTime? _lastBackPressed; // Track back button presses for double-tap exit

  // Main card height
  late double mainCardHeight;
  double settingsIconMarginTop = 5;

  bool releaseAnimation = false;

  // Simplified animation methods (flare_flutter removed)
  // void initialize(FlutterActorArtboard actor) - removed
  // void setViewTransform(Mat2D viewTransform) - removed  
  // bool advance(FlutterActorArtboard artboard, double elapsed) - removed

  _checkVersionApp() async {
    String versionAppCached = await sl.get<SharedPrefsUtil>().getVersionApp();
    PackageInfo.fromPlatform().then((packageInfo) async {
      if (versionAppCached != packageInfo.version) {
        _displayReleaseNote = true;
      } else {
        _displayReleaseNote = false;
      }
    });
  }

  _getEggPrice() async {
    _eggPrice = await sl.get<HttpService>().getEggPrice();
  }

  @override
  void initState() {
    super.initState();

    _displayReleaseNote = false;
    _checkVersionApp();
    _getEggPrice();
    _registerBus();
    _startPeriodicUpdates();
    
    // Initialize receive sheet
    receive = ReceiveSheet();
    WidgetsBinding.instance.addObserver(this);
    _priceConversion = widget.priceConversion ?? PriceConversion.BTC;
    
    // Generate initial QR code after frame is rendered
    // This fixes the issue where QR code is not generated on first app launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && StateContainer.of(context).wallet?.address != null) {
        paintQrCode(address: StateContainer.of(context).wallet!.address!);
      }
    });
      // Main Card Size
    if (_priceConversion == PriceConversion.BTC) {
      mainCardHeight = 120;
      settingsIconMarginTop = 7;
    } else if (_priceConversion == PriceConversion.NONE) {
      mainCardHeight = 64;
      settingsIconMarginTop = 7;
    } else if (_priceConversion == PriceConversion.HIDDEN) {
      mainCardHeight = 64;
      settingsIconMarginTop = 5;
    }

    _addSampleContact();
    _updateContacts();
    // Setup placeholder animation and start
    _animationDisposed = false;
    _placeholderCardAnimationController = new AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _placeholderCardAnimationController
        .addListener(_animationControllerListener);
    _opacityAnimation = new Tween(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(
        parent: _placeholderCardAnimationController,
        curve: Curves.easeIn,
        reverseCurve: Curves.easeOut,
      ),
    );
    _opacityAnimation.addStatusListener(_animationStatusListener);
    _placeholderCardAnimationController.forward();
  }

  void _animationStatusListener(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.dismissed:
        _placeholderCardAnimationController.forward();
        break;
      case AnimationStatus.completed:
        _placeholderCardAnimationController.reverse();
        break;
      default:
        return null;
    }
  }

  void _animationControllerListener() {
    setState(() {});
  }

  void _startAnimation() {
    if (_animationDisposed) {
      _animationDisposed = false;
      _placeholderCardAnimationController
          .addListener(_animationControllerListener);
      _opacityAnimation.addStatusListener(_animationStatusListener);
      _placeholderCardAnimationController.forward();
    }
  }

  void _disposeAnimation() {
    if (!_animationDisposed) {
      _animationDisposed = true;
      _opacityAnimation.removeStatusListener(_animationStatusListener);
      _placeholderCardAnimationController
          .removeListener(_animationControllerListener);
      _placeholderCardAnimationController.stop();
    }
  }

  /// Add donations contact if it hasnt already been added
  Future<void> _addSampleContact() async {
    bool contactAdded = await sl.get<SharedPrefsUtil>().getFirstContactAdded();
    if (!contactAdded) {
      bool addressExists = await sl
          .get<DBHelper>()
          .contactExistsWithAddress(AppLocalization.of(context).donationsUrl);
      if (addressExists) {
        return;
      }
      bool nameExists = await sl
          .get<DBHelper>()
          .contactExistsWithName(AppLocalization.of(context).donationsName);
      if (nameExists) {
        return;
      }
      await sl.get<SharedPrefsUtil>().setFirstContactAdded(true);
      Contact c = Contact(
          name: AppLocalization.of(context).donationsName,
          address: AppLocalization.of(context).donationsUrl);
      await sl.get<DBHelper>().saveContact(c);
    }
  }

  void _updateContacts() {
    sl.get<DBHelper>().getContacts().then((contacts) {
      setState(() {
        _contacts = contacts;
      });
    });
  }

  late StreamSubscription<HistoryHomeEvent> _historySub;
  late StreamSubscription<ContactModifiedEvent> _contactModifiedSub;
  late StreamSubscription<DisableLockTimeoutEvent> _disableLockSub;
  late StreamSubscription<AccountChangedEvent> _switchAccountSub;
  late StreamSubscription<NetworkErrorEvent> _networkErrorSub;
  late StreamSubscription<BalanceGetEvent> _balanceGetSub;
  // _transactionsListSub removed - using sophisticated handler in appstate_container.dart instead

  void _registerBus() {
    _historySub = EventTaxiImpl.singleton()
        .registerTo<HistoryHomeEvent>()
        .listen((event) {
      setState(() {
        _isRefreshing = false;
        _historyVersion++;
        // Force UI rebuild to show updated transaction history
        // The transaction history data is already updated in StateContainer
        // This setState ensures the UI reflects the changes
      });
      print("HistoryHomeEvent received - UI refreshed with " + (event.items?.length ?? 0).toString() + " transactions");
      // TODO: Fix deep link handling
      // if (StateContainer.of(context).initialDeepLink != null) {
      //   handleDeepLink(StateContainer.of(context).initialDeepLink);
      //   StateContainer.of(context).initialDeepLink = null;
      // }
    });
    _contactModifiedSub = EventTaxiImpl.singleton()
        .registerTo<ContactModifiedEvent>()
        .listen((event) {
      _updateContacts();
    });
    // Hackish event to block auto-lock functionality
    _disableLockSub = EventTaxiImpl.singleton()
        .registerTo<DisableLockTimeoutEvent>()
        .listen((event) {
      if (event.disable ?? false) {
        cancelLockEvent();
      }
      _lockDisabled = event.disable ?? false;
    });
    // User changed account
    _switchAccountSub = EventTaxiImpl.singleton()
        .registerTo<AccountChangedEvent>()
        .listen((event) {
      setState(() {
        StateContainer.of(context).wallet?.loading = true;
        StateContainer.of(context).wallet?.historyLoading = true;

        _startAnimation();
          StateContainer.of(context).updateWallet(account: event.account!);

          // Do not immediately flip loading flags here; let StateContainer manage them after data loads
      });
      paintQrCode(address: event.account?.address ?? '');
      if (event.delayPop) {
        Future.delayed(Duration(milliseconds: 300), () {
          Navigator.of(context).popUntil(RouteUtils.withNameLike("/home"));
        });
      } else if (!event.noPop) {
        Navigator.of(context).popUntil(RouteUtils.withNameLike("/home"));
      }
    });
    
    // Network error handling
    _networkErrorSub = EventTaxiImpl.singleton()
        .registerTo<NetworkErrorEvent>()
        .listen((event) {
      _showNetworkError(event);
    });
    
    // Balance updates
    _balanceGetSub = EventTaxiImpl.singleton()
        .registerTo<BalanceGetEvent>()
        .listen((event) {
      if (mounted && event.response != null) {
        setState(() {
          if (StateContainer.of(context).wallet != null) {
            double? balance = double.tryParse(event.response!.balance);
            if (balance != null) {
              StateContainer.of(context).wallet!.accountBalance = balance;
            }
            StateContainer.of(context).wallet!.loading = false;
          }
        });
      }
    });
    
    // Transaction updates - Legacy handler removed to prevent conflicts with sophisticated handler in appstate_container.dart
    // The sophisticated handler preserves unconfirmed transactions properly
  }

  @override
  void dispose() {
    _destroyBus();
    _updateTimer?.cancel();
    lockStreamListener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _placeholderCardAnimationController.dispose();
    super.dispose();
  }

  void _destroyBus() {
    _historySub.cancel();
      _contactModifiedSub.cancel();
      _disableLockSub.cancel();
      _switchAccountSub.cancel();
      _networkErrorSub.cancel();
      _balanceGetSub.cancel();
      // _transactionsListSub.cancel(); // removed - no longer using this subscription
    }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle websocket connection when app is in background
    // terminate it to be eco-friendly
    switch (state) {
      case AppLifecycleState.paused:
        setAppLockEvent();
        super.didChangeAppLifecycleState(state);
        break;
      case AppLifecycleState.resumed:
        cancelLockEvent();
        // Clear any stale error messages when app resumes
        ScaffoldMessenger.of(context).clearSnackBars();
        // Reset error flag
        _isShowingNetworkError = false;
        
        // Check if we need to re-authenticate in password mode
        // Check if encryptedSecret is null OR if it's invalid/corrupted
        sl.get<Vault>().getSeed().then((vaultSeed) async {
          bool needsReauth = false;
          
          if (AppUtil.isSeedEncrypted(vaultSeed)) {
            // In password mode, validate that encryptedSecret works
            if (StateContainer.of(context).encryptedSecret == null) {
              needsReauth = true;
            } else {
              // Try to decrypt to validate it's still valid
              try {
                await StateContainer.of(context).getSeed();
              } catch (e) {
                // Decryption failed, encryptedSecret is corrupted
                log.w("encryptedSecret validation failed after resume: ${e.toString()}");
                needsReauth = true;
              }
            }
            
            if (needsReauth) {
              // Navigate to password lock screen
              Navigator.of(context).pushNamedAndRemoveUntil(
                  '/password_lock_screen', (Route<dynamic> route) => false);
            }
          } else {
            // For non-password mode, setup encryptedSecret if missing
            if (StateContainer.of(context).encryptedSecret == null) {
              String sessionKey = await sl.get<Vault>().getSessionKey();
              if (sessionKey.isNotEmpty) {
                StateContainer.of(context).setEncryptedSecret(
                    HEX.encode(AppCrypt.encrypt(vaultSeed, sessionKey))
                );
              }
            }
          }
        });
        
        // Don't refresh if already loading to prevent duplicate requests
        if (!(StateContainer.of(context).wallet?.loading ?? false)) {
          // Add a longer delay for Android to stabilize network connections
          // Especially important for Android 15+ with aggressive power management
          Future.delayed(Duration(milliseconds: 1500), () {
            if (mounted && 
                StateContainer.of(context).wallet != null &&
                !(StateContainer.of(context).wallet?.loading ?? false)) {
              // Trigger a refresh to update data
              StateContainer.of(context).requestUpdate();
            }
          });
        }
        
        if (!(StateContainer.of(context).wallet?.loading ?? false) &&
            false) {
          // TODO: Fix deep link handling
          // handleDeepLink(StateContainer.of(context).initialDeepLink);
        }
        super.didChangeAppLifecycleState(state);
        break;
      default:
        super.didChangeAppLifecycleState(state);
        break;
    }
  }

  // To lock and unlock the app
  StreamSubscription<dynamic>? lockStreamListener;

  Future<void> setAppLockEvent() async {
    if (((await sl.get<SharedPrefsUtil>().getLock()) ||
            StateContainer.of(context).encryptedSecret != null) &&
        !_lockDisabled) {
      lockStreamListener?.cancel();
          Future<dynamic> delayed = new Future.delayed(
          (await sl.get<SharedPrefsUtil>().getLockTimeout()).getDuration());
      delayed.then((_) {
        return true;
      });
      lockStreamListener = delayed.asStream().listen((_) {
        try {
          StateContainer.of(context).resetEncryptedSecret();
        } catch (e) {
          log.w(
              "Failed to reset encrypted secret when locking ${e.toString()}");
        } finally {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
        }
      });
    }
  }

  Future<void> cancelLockEvent() async {
    lockStreamListener?.cancel();
    }

  // Track if we're already showing a network error to prevent duplicates
  bool _isShowingNetworkError = false;
  
  // Show user-friendly network error messages with retry option
  void _showNetworkError(NetworkErrorEvent event) {
    if (!mounted) return;
    
    // Prevent duplicate error messages
    if (_isShowingNetworkError) return;
    _isShowingNetworkError = true;
    
    // Clear any existing snackbars first
    ScaffoldMessenger.of(context).clearSnackBars();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.operation ?? "Network Error",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(event.message ?? "Network connection failed"),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: Duration(seconds: event.canRetry ? 6 : 4),
        action: event.canRetry ? SnackBarAction(
          label: "Retry",
          textColor: Colors.white,
          onPressed: () {
            _isShowingNetworkError = false;
            _retryNetworkOperation(event.errorType);
          },
        ) : null,
      ),
    ).closed.then((_) {
      // Reset flag when snackbar is dismissed
      _isShowingNetworkError = false;
    });
  }

  // Retry network operations based on error type
  void _retryNetworkOperation(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.BALANCE_FETCH_FAILED:
        // Retry balance fetch
        sl.get<AppService>().getBalanceGetResponse(
          StateContainer.of(context).selectedAccount.address ?? '', 
          true
        );
        break;
      case NetworkErrorType.TRANSACTION_HISTORY_FAILED:
        // Retry transaction history
        sl.get<AppService>().getAddressTxsResponse(
          StateContainer.of(context).selectedAccount.address ?? '', 
          100
        );
        break;
      case NetworkErrorType.SEND_TRANSACTION_FAILED:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Please try sending the transaction again"),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      default:
        // Generic retry - refresh the wallet state
        sl.get<AppService>().getBalanceGetResponse(
          StateContainer.of(context).selectedAccount.address ?? '', 
          true
        );
        break;
    }
  }

  // Used to build list items that haven't been removed.
  Widget _buildItem(
      BuildContext context, int index, Animation<double> animation) {
    // Reverse the index to show newest transactions first
    int totalItems = StateContainer.of(context).wallet?.history.length ?? 0;
    int reversedIndex = totalItems - 1 - index;
    
    String displayName = smallScreen(context)
        ? StateContainer.of(context).wallet?.history[reversedIndex].getShorterString() ?? ""
        : StateContainer.of(context).wallet?.history[reversedIndex].getShortString() ?? "";
    _contacts.forEach((contact) {
      if (StateContainer.of(context).wallet?.history[reversedIndex].type ==
          BlockTypes.RECEIVE) {
        if (contact.address ==
            StateContainer.of(context).wallet?.history[reversedIndex].from) {
          displayName = contact.name ?? "";
        }
      } else {
        if (contact.address ==
            StateContainer.of(context).wallet?.history[reversedIndex].recipient) {
          displayName = contact.name ?? "";
        }
      }
    });
    return _buildTransactionCard(
        StateContainer.of(context).wallet?.history[reversedIndex] ?? AddressTxsResponseResult(),
        animation,
        displayName,
        context);
  }

  // Return widget for list
  Widget _getListWidget(BuildContext context) {
    if (StateContainer.of(context).wallet?.historyLoading ?? false) {
      // Loading Animation
      return ReactiveRefreshIndicator(
          backgroundColor: StateContainer.of(context).curTheme.backgroundDark,
          onRefresh: _refresh,
          isRefreshing: _isRefreshing,
          child: ListView(
            padding: EdgeInsetsDirectional.fromSTEB(0, 5.0, 0, 15.0),
            children: <Widget>[
              _buildLoadingTransactionCard(
                  "Sent", "10244000", "123456789121234", context),
              _buildLoadingTransactionCard(
                  "Received", "100,00000", "@reddwarf1234", context),
              _buildLoadingTransactionCard(
                  "Sent", "14500000", "12345678912345671234", context),
              _buildLoadingTransactionCard(
                  "Sent", "12,51200", "123456789121234", context),
              _buildLoadingTransactionCard(
                  "Received", "1,45300", "123456789121234", context),
              _buildLoadingTransactionCard(
                  "Sent", "100,00000", "12345678912345671234", context),
              _buildLoadingTransactionCard(
                  "Received", "24,00000", "12345678912345671234", context),
              _buildLoadingTransactionCard(
                  "Sent", "1,00000", "123456789121234", context),
              _buildLoadingTransactionCard(
                  "Sent", "1,00000", "123456789121234", context),
              _buildLoadingTransactionCard(
                  "Sent", "1,00000", "123456789121234", context),
            ],
          ));
    } else if (StateContainer.of(context).wallet?.history.length == 0) {
      _disposeAnimation();
      return ReactiveRefreshIndicator(
        backgroundColor: StateContainer.of(context).curTheme.backgroundDark,
        child: ListView(
          padding: EdgeInsetsDirectional.fromSTEB(0, 5.0, 0, 15.0),
          children: <Widget>[
            _buildWelcomeTransactionCard(context),
            _buildDummyTransactionCard(
              AppLocalization.of(context).sent,
              AppLocalization.of(context).exampleCardLittle,
              AppLocalization.of(context).exampleCardTo,
              context,
            ),
            _buildDummyTransactionCard(
              AppLocalization.of(context).received,
              AppLocalization.of(context).exampleCardLot,
              AppLocalization.of(context).exampleCardFrom,
              context,
            ),
          ],
        ),
        onRefresh: _refresh,
        isRefreshing: _isRefreshing,
      );
    } else {
      _disposeAnimation();
    }
    return ReactiveRefreshIndicator(
      backgroundColor: StateContainer.of(context).curTheme.backgroundDark,
      child: AnimatedList(
        key: ValueKey((StateContainer.of(context).wallet?.address ?? "unknown") + "_" + (StateContainer.of(context).wallet?.history.length ?? 0).toString() + "_" + _historyVersion.toString()),
        padding: EdgeInsetsDirectional.fromSTEB(0, 5.0, 0, 15.0),
        initialItemCount: StateContainer.of(context).wallet?.history.length ?? 0,
        itemBuilder: _buildItem,
      ),
      onRefresh: _refresh,
      isRefreshing: _isRefreshing,
    );
  }

  // Start periodic updates every 30 seconds
  void _startPeriodicUpdates() {
    // Cancel existing timer if any
    _updateTimer?.cancel();
    
    // Start new timer for periodic updates
    _updateTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted && StateContainer.of(context).wallet?.address != null) {
        StateContainer.of(context).requestUpdate();
      }
    });
    
    // Also request an initial update
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        StateContainer.of(context).requestUpdate();
      }
    });
  }

  // Refresh list
  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      // Clear error state on manual refresh
      _isShowingNetworkError = false;
    });
    // Clear any existing error messages
    ScaffoldMessenger.of(context).clearSnackBars();
    HapticUtil.lightFeedback();
    StateContainer.of(context).requestUpdate();

    // Hide refresh indicator after 3 seconds if no server response
    Future.delayed(new Duration(seconds: 3), () {
      setState(() {
        _isRefreshing = false;
      });
    });
  }

  Future<void> handleDeepLink(String link) async {
    // TODO: Implement BisUrl parsing for deep links
    // BisUrl bisUrl = await new BisUrl().getInfo(Uri.decodeFull(link));
    print("Deep link handling disabled: $link");
    return;

    // Remove any other screens from stack
    Navigator.of(context).popUntil(RouteUtils.withNameLike('/home'));

    // Go to send confirm with amount
    // Deep link handling disabled - commenting out for now
    // Sheets.showAppHeightNineSheet(
    //     context: context,
    //     widget: SendConfirmSheet(
    //         amountRaw: bisUrl.amount,
    //         operation: bisUrl.operation,
    //         openfield: bisUrl.openfield,
    //         comment: bisUrl.comment,
    //         destination: bisUrl.address,
    //         contactName: bisUrl.contactName,
    //         localCurrency: "",
    //         title: AppLocalization.of(context).sending));
  }

  void paintQrCode({required String address}) {
    final qrData = address.isEmpty 
        ? StateContainer.of(context).wallet?.address ?? "" 
        : address;
    
    // Validate QR data
    if (qrData.isEmpty) {
      print('Warning: Empty QR data');
      return;
    }
    
    try {
      QrPainter painter = QrPainter(
        data: qrData,
        version: 6,
        gapless: false,
        errorCorrectionLevel: QrErrorCorrectLevel.Q,
      );
      
      // Use a fixed size for consistency
      final double imageSize = 800.0;
      
      painter.toImageData(imageSize, format: ui.ImageByteFormat.png).then((byteData) {
        if (!mounted) return;
        
        if (byteData != null && byteData.buffer.asUint8List().length > 100) {
          // Check if the image data looks valid (should be larger than 100 bytes for a QR code)
          final imageBytes = byteData.buffer.asUint8List();
          
          setState(() {
            receive = ReceiveSheet(
              qrWidget: Container(
                width: MediaQuery.of(context).size.width / 2.675,
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                ),
              ),
            );
          });
        } else {
          print('QR generation produced invalid data (size: ${byteData?.buffer.asUint8List().length ?? 0})');
          // Fallback to QrImageView
          setState(() {
            receive = ReceiveSheet(
              qrWidget: Container(
                width: MediaQuery.of(context).size.width / 2.675,
                child: QrImageView(
                  data: qrData,
                  version: 6,
                  size: MediaQuery.of(context).size.width / 2.675,
                  gapless: false,
                  errorCorrectionLevel: QrErrorCorrectLevel.Q,
                ),
              ),
            );
          });
        }
      }).catchError((error) {
        print('Error generating QR with QrPainter: $error');
        // Fallback to QrImageView
        if (mounted) {
          setState(() {
            receive = ReceiveSheet(
              qrWidget: Container(
                width: MediaQuery.of(context).size.width / 2.675,
                child: QrImageView(
                  data: qrData,
                  version: 6,
                  size: MediaQuery.of(context).size.width / 2.675,
                  gapless: false,
                  errorCorrectionLevel: QrErrorCorrectLevel.Q,
                ),
              ),
            );
          });
        }
      });
    } catch (e) {
      print('Exception in QR generation: $e');
      // Fallback to QrImageView  
      if (mounted) {
        setState(() {
          receive = ReceiveSheet(
            qrWidget: Container(
              width: MediaQuery.of(context).size.width / 2.675,
              child: QrImageView(
                data: qrData,
                version: 6,
                size: MediaQuery.of(context).size.width / 2.675,
                gapless: false,
                errorCorrectionLevel: QrErrorCorrectLevel.Q,
              ),
            ),
          );
        });
      }
    }
  }

  void _handleBackButton() {
    final now = DateTime.now();
    const exitDuration = Duration(seconds: 2);
    
    if (_lastBackPressed == null || now.difference(_lastBackPressed!) > exitDuration) {
      // First back press or too much time has passed - show warning
      _lastBackPressed = now;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Press back again to exit'),
          duration: exitDuration,
          backgroundColor: StateContainer.of(context).curTheme.primary,
        ),
      );
    } else {
      // Second back press within timeframe - exit app
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    _displayReleaseNote
        ? WidgetsBinding.instance
            .addPostFrameCallback((_) => displayReleaseNote())
        : null;

    return PopScope(
      canPop: false, // Prevent accidental exits, but allow intentional double-tap
      onPopInvokedWithResult: (didPop, result) {
        _handleBackButton();
      },
      child: Scaffold(
        drawerEdgeDragWidth: 200,
        resizeToAvoidBottomInset: false,
        key: _scaffoldKey,
        backgroundColor: StateContainer.of(context).curTheme.background,
        drawer: SizedBox(
          width: UIUtil.drawerWidth(context),
          child: Drawer(
            child: SettingsSheet(_eggPrice),
          ),
        ),
        body: SafeArea(
          minimum: EdgeInsets.only(
              top: MediaQuery.of(context).size.height * 0.045,
              bottom: MediaQuery.of(context).size.height * 0.035),
          child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  //Everything else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      //Main Card
                      _buildMainCard(context, _scaffoldKey),
                      //Main Card End

                      //Transactions Text
                      Container(
                        margin: EdgeInsetsDirectional.fromSTEB(
                            30.0, 20.0, 26.0, 0.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              CaseChange.toUpperCase(
                                  AppLocalization.of(context).transactions,
                                  context),
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                fontSize: 14.0,
                                fontWeight: FontWeight.w100,
                                color: StateContainer.of(context).curTheme.text,
                              ),
                            ),
                            SyncInfoView(),
                          ],
                        ),
                      ), //Transactions Text End

                      //Transactions List
                      Expanded(
                        child: Stack(
                          children: <Widget>[
                            _getListWidget(context),
                            //List Top Gradient End
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                height: 10.0,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      StateContainer.of(context)
                                          .curTheme
                                          .background00,
                                      StateContainer.of(context)
                                          .curTheme
                                          .background
                                    ],
                                    begin: AlignmentDirectional(0.5, 1.0),
                                    end: AlignmentDirectional(0.5, -1.0),
                                  ),
                                ),
                              ),
                            ), // List Top Gradient End

                            //List Bottom Gradient
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 30.0,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      StateContainer.of(context)
                                          .curTheme
                                          .background00,
                                      StateContainer.of(context)
                                          .curTheme
                                          .background
                                    ],
                                    begin: AlignmentDirectional(0.5, -1),
                                    end: AlignmentDirectional(0.5, 0.5),
                                  ),
                                ),
                              ),
                            ), //List Bottom Gradient End
                          ],
                        ),
                      ), //Transactions List End
                      //Buttons background
                      SizedBox(
                        height: 55,
                        width: MediaQuery.of(context).size.width,
                      ), //Buttons background
                    ],
                  ),
                  // Buttons
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Container(
                        decoration: BoxDecoration(
                          color: StateContainer.of(context).curTheme.primary,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            StateContainer.of(context).curTheme.boxShadowButton
                          ],
                        ),
                        height: 55,
                        width: (MediaQuery.of(context).size.width - 18) / 3,
                        margin: EdgeInsetsDirectional.only(
                            start: 14, top: 0.0, end: 7.0),
                        child: TextButton(
                          child: AutoSizeText(
                            AppLocalization.of(context).receive,
                            textAlign: TextAlign.center,
                            style: receive != null
                                ? AppStyles.textStyleButtonPrimary(context)
                                : AppStyles.textStyleButtonPrimary60(context),
                            maxLines: 1,
                            stepGranularity: 0.5,
                          ),
                          onPressed: () {
                            Sheets.showAppHeightEightSheet(
                                context: context, widget: receive);
                          },
                        ),
                      ),
                      Expanded(child: Container()),
                      AppPopupButton(),
                    ],
                  ),
                ],
              ), // Close Stack
            ), // Close Expanded  
          ], // Close Column children
        ), // Close Column (SafeArea child)
      ), // Close SafeArea
        ), // Close Scaffold
    ); // Close PopScope
  }

  void displayReleaseNote() {
    _displayReleaseNote = false;
    PackageInfo.fromPlatform().then((packageInfo) {
      AppDialogs.showConfirmDialog(
          context,
          AppLocalization.of(context).releaseNoteHeader +
              " " +
              packageInfo.version,
          "- Minor changes",
          CaseChange.toUpperCase(AppLocalization.of(context).ok, context),
          () async {
        await sl.get<SharedPrefsUtil>().setVersionApp(packageInfo.version);
      });
    });
  }

  // Transaction Card/List Item
  Widget _buildTransactionCard(AddressTxsResponseResult item,
      Animation<double> animation, String displayName, BuildContext context) {
    String text;
    if (item.type == BlockTypes.SEND) {
      text = AppLocalization.of(context).sent;
    } else if (item.type == BlockTypes.UNCONFIRMED) {
      text = "Unconfirmed";
    } else {
      text = AppLocalization.of(context).received;
    }
    return Slidable(
      delegate: SlidableScrollDelegate(),
      actionExtentRatio: 0.35,
      movementDuration: Duration(milliseconds: 300),
      enabled: (StateContainer.of(context).wallet?.accountBalance ?? 0) > 0,
      onTriggered: (preempt) {
        if (preempt) {
          setState(() {
            releaseAnimation = true;
          });
        } else {
          // See if a contact
          sl.get<DBHelper>().getContactWithAddress(item.from ?? '').then((contact) {
            // Go to send with address
            Sheets.showAppHeightNineSheet(
                context: context,
                widget: SendSheet(
                  sendATokenActive: true,
                  localCurrency: StateContainer.of(context).curCurrency,
                  contact: contact,
                  address: item.from,
                  quickSendAmount: item.amount,
                ));
          });
        }
      },
      onAnimationChanged: (animation) {
        if (animation != null) {
          if (animation.value == 0.0 && releaseAnimation) {
            setState(() {
              releaseAnimation = false;
            });
          }
        }
      },
      secondaryActions: <Widget>[
        SlideAction(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
            ),
            margin: EdgeInsetsDirectional.only(
                end: MediaQuery.of(context).size.width * 0.15,
                top: 4,
                bottom: 4),
            child: Container(
              alignment: AlignmentDirectional(-0.5, 0),
              constraints: BoxConstraints.expand(),
              child: Container(
                  decoration: BoxDecoration(
                    color: StateContainer.of(context).curTheme.primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.swipe,
                    color: StateContainer.of(context).curTheme.primary,
                    size: 24,
                  ),
                ),
            ),
          ),
        ),
      ],
      child: _SizeTransitionNoClip(
        sizeFactor: animation,
        child: Container(
          margin: EdgeInsetsDirectional.fromSTEB(14.0, 4.0, 14.0, 4.0),
          decoration: BoxDecoration(
            color: StateContainer.of(context).curTheme.backgroundDark,
            borderRadius: BorderRadius.circular(10.0),
            boxShadow: [StateContainer.of(context).curTheme.boxShadow],
          ),
          child: TextButton(
            onPressed: () {
              Sheets.showAppHeightEightSheet(
                  context: context,
                  widget: TransactionDetailsSheet(
                      item: item,
                      address: (item.type == BlockTypes.SEND || item.type == BlockTypes.UNCONFIRMED)
                          ? item.recipient
                          : item.from,
                      displayName: displayName),
                  animationDurationMs: 175);
            },
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 14.0, horizontal: 20.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: MediaQuery.of(context).size.width / 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              item.isAliasRegister()
                                  ? Text(
                                      "Alias",
                                      textAlign: TextAlign.start,
                                      style: AppStyles.textStyleTransactionType(
                                          context),
                                    )
                                  : Text(
                                      item.blockHeight == -1
                                          ? text +
                                              " - " +
                                              AppLocalization.of(context)
                                                  .mempool
                                          : text,
                                      textAlign: TextAlign.start,
                                      style: AppStyles.textStyleTransactionType(
                                          context),
                                    ),
                              Text(
                                DateFormat.yMd(Localizations.localeOf(context)
                                        .languageCode)
                                    .add_Hms()
                                    .format(item.timestamp ?? DateTime.now())
                                    .toString(),
                                style:
                                    AppStyles.textStyleTransactionUnit(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Container(
                            width: MediaQuery.of(context).size.width / 2.4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                (double.tryParse(item
                                            .getFormattedAmount()
                                            .replaceAll(",", "")) ?? 0) >
                                        0
                                    ? Container(
                                        child: RichText(
                                          textAlign: TextAlign.start,
                                          text: TextSpan(
                                            text: '',
                                            children: [
                                              TextSpan(
                                                text: item.type ==
                                                        BlockTypes.SEND
                                                    ? "- " +
                                                        item
                                                            .getFormattedAmount() +
                                                        ( (item.blockHeight == -1)
                                                          ? " BIS (pending)"
                                                          : " BIS")
                                                    : (item.type ==
                                                                BlockTypes.UNCONFIRMED ||
                                                            item.blockHeight == -1)
                                                        ? (item.recipient == StateContainer.of(context).selectedAccount.address
                                                            ? "+ " +
                                                                item
                                                                    .getFormattedAmount() +
                                                                " BIS (pending)"
                                                            : "- " +
                                                                item
                                                                    .getFormattedAmount() +
                                                                " BIS (pending)")
                                                        : "+ " +
                                                            item.getFormattedAmount() +
                                                            " BIS",
                                                style: item.type ==
                                                        BlockTypes.SEND
                                                    ? AppStyles
                                                        .textStyleTransactionTypeRed(
                                                            context)
                                                    : (item.type ==
                                                                BlockTypes.UNCONFIRMED ||
                                                            item.blockHeight == -1)
                                                        ? (item.recipient == StateContainer.of(context).selectedAccount.address
                                                            ? AppStyles
                                                                .textStyleTransactionTypeGreen(
                                                                    context)
                                                                .copyWith(
                                                                    color: Colors
                                                                        .orange)
                                                            : AppStyles
                                                                .textStyleTransactionTypeRed(
                                                                    context)
                                                                .copyWith(
                                                                    color: Colors
                                                                        .orange))
                                                        : AppStyles
                                                            .textStyleTransactionTypeGreen(
                                                                context),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : SizedBox(),
                                item.isTokenTransfer() == true
                                    ? Container(
                                        child: RichText(
                                          textAlign: TextAlign.start,
                                          text: TextSpan(
                                            text: '',
                                            children: [
                                              TextSpan(
                                                text: item.type ==
                                                        BlockTypes.SEND
                                                    ? "- " +
                                                        item
                                                            .getBisToken()
                                                            .tokensQuantity
                                                            .toString() +
                                                        " " +
                                                        (item
                                                            .getBisToken()
                                                            .tokenName ?? '') +
                                                        ( (item.blockHeight == -1)
                                                          ? " (pending)"
                                                          : "")
                                                    : (item.type == BlockTypes.UNCONFIRMED || item.blockHeight == -1)
                                                        ? "- " +
                                                            item
                                                                .getBisToken()
                                                                .tokensQuantity
                                                                .toString() +
                                                            " " +
                                                            (item
                                                                .getBisToken()
                                                                .tokenName ?? '') +
                                                            " (pending)"
                                                        : "+ " +
                                                            item
                                                                .getBisToken()
                                                                .tokensQuantity
                                                                .toString() +
                                                            " " +
                                                            (item
                                                                .getBisToken()
                                                                .tokenName ?? ''),
                                                style: item.type ==
                                                        BlockTypes.SEND
                                                    ? AppStyles
                                                        .textStyleTransactionTypeRed(
                                                            context)
                                                    : (item.type == BlockTypes.UNCONFIRMED || item.blockHeight == -1)
                                                        ? AppStyles
                                                            .textStyleTransactionTypeRed(
                                                                context)
                                                            .copyWith(
                                                                color: Colors
                                                                    .orange)
                                                        : AppStyles
                                                            .textStyleTransactionTypeGreen(
                                                                context),
                                              ),
                                              item.getBisToken().tokenName ==
                                                      "egg"
                                                  ? TextSpan(text: " ")
                                                  : TextSpan(text: ""),
                                              item.getBisToken().tokenName ==
                                                      "egg"
                                                  ? WidgetSpan(
                                                      child: Icon(
                                                          FontAwesome5.egg,
                                                          size: AppFontSizes
                                                              .small,
                                                          color: item.type ==
                                                                  BlockTypes
                                                                      .SEND
                                                              ? Colors.red[400]
                                                              : Colors
                                                                  .green[400]),
                                                      style: item.type ==
                                                              BlockTypes.SEND
                                                          ? AppStyles
                                                              .textStyleTransactionTypeRed(
                                                                  context)
                                                          : AppStyles
                                                              .textStyleTransactionTypeGreen(
                                                                  context),
                                                    )
                                                  : TextSpan(text: "")
                                            ],
                                          ),
                                        ),
                                      )
                                    : item.isAliasRegister()
                                        ? Container(
                                            child: RichText(
                                              textAlign: TextAlign.start,
                                              text: TextSpan(
                                                text: '',
                                                children: [
                                                  TextSpan(
                                                    text: item.openfield
                                                        ?.replaceAll(
                                                            "alias=", "") ?? '',
                                                    style: AppStyles
                                                        .textStyleTransactionTypeBlue(
                                                            context),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : item.isDragginatorNew()
                                            ? Container(
                                                child: RichText(
                                                  textAlign: TextAlign.start,
                                                  text: TextSpan(
                                                    text: '',
                                                    children: [
                                                      WidgetSpan(
                                                        child: Icon(
                                                            FontAwesome5.dragon,
                                                            size: AppFontSizes
                                                                .small,
                                                            color: Colors
                                                                .blue[400]),
                                                      ),
                                                      TextSpan(
                                                        text: "   new egg",
                                                        style: AppStyles
                                                            .textStyleTransactionTypeBlue(
                                                                context),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : item.isDragginatorMerge()
                                                ? Container(
                                                    child: RichText(
                                                      textAlign:
                                                          TextAlign.start,
                                                      text: TextSpan(
                                                        text: '',
                                                        children: [
                                                          WidgetSpan(
                                                            child: Icon(
                                                                FontAwesome5
                                                                    .dragon,
                                                                size:
                                                                    AppFontSizes
                                                                        .small,
                                                                color: Colors
                                                                    .blue[400]),
                                                          ),
                                                          TextSpan(
                                                            text:
                                                                "   eggs merge",
                                                            style: AppStyles
                                                                .textStyleTransactionTypeBlue(
                                                                    context),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                : item.isDragginator()
                                                    ? Container(
                                                        child: RichText(
                                                          textAlign:
                                                              TextAlign.start,
                                                          text: TextSpan(
                                                            text: '',
                                                            children: [
                                                              WidgetSpan(
                                                                child: Icon(
                                                                    FontAwesome5
                                                                        .dragon,
                                                                    size: AppFontSizes
                                                                        .small,
                                                                    color: Colors
                                                                            .blue[
                                                                        400]),
                                                              ),
                                                              TextSpan(
                                                                text: "   " +
                                                                    (item.operation
                                                                        ?.split(
                                                                            ":")[1] ?? ''),
                                                                style: AppStyles
                                                                    .textStyleTransactionTypeBlue(
                                                                        context),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      )
                                                    : item.isHNRegister()
                                                        ? Container(
                                                            child: RichText(
                                                              textAlign:
                                                                  TextAlign
                                                                      .start,
                                                              text: TextSpan(
                                                                text: '',
                                                                children: [
                                                                  WidgetSpan(
                                                                    child: Icon(
                                                                        FontAwesome5
                                                                            .linode,
                                                                        size: AppFontSizes
                                                                            .small,
                                                                        color: Colors
                                                                            .blue[400]),
                                                                  ),
                                                                  TextSpan(
                                                                    text:
                                                                        "  HN register",
                                                                    style: AppStyles
                                                                        .textStyleTransactionTypeBlue(
                                                                            context),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          )
                                                        : SizedBox(),
                                /*Container(
                                  width: 26.0,
                                  height: 26.0,
                                  child: CircleAvatar(
                                    backgroundColor: StateContainer.of(context)
                                        .curTheme
                                        .text05,
                                    backgroundImage: NetworkImage(
                                      UIUtil.getRobohashURL(
                                          (item.type == BlockTypes.SEND || item.type == BlockTypes.UNCONFIRMED)
                                              ? item.recipient
                                              : item.from),
                                    ),
                                    radius: 30.0,
                                  ),
                                ),*/
                                Text(
                                  displayName,
                                  textAlign: TextAlign.end,
                                  style: AppStyles.textStyleTransactionAddress(
                                      context),
                                ),
                              ],
                            )),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  } //Transaction Card End

  // Dummy Transaction Card
  Widget _buildDummyTransactionCard(
      String type, String amount, String address, BuildContext context) {
    String text;
    IconData icon;
    Color iconColor;
    if (type == AppLocalization.of(context).sent) {
      text = AppLocalization.of(context).sent;
      icon = AppIcons.sent;
      iconColor = StateContainer.of(context).curTheme.text60;
    } else {
      text = AppLocalization.of(context).received;
      icon = AppIcons.received;
      iconColor = StateContainer.of(context).curTheme.primary60;
    }
    return Container(
      margin: EdgeInsetsDirectional.fromSTEB(14.0, 4.0, 14.0, 4.0),
      decoration: BoxDecoration(
        color: StateContainer.of(context).curTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: [StateContainer.of(context).curTheme.boxShadow],
      ),
      child: TextButton(
        onPressed: () {
          return null;
        },
        child: Center(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 14.0, horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      margin: EdgeInsetsDirectional.only(end: 16.0),
                      child: Icon(icon, color: iconColor, size: 15),
                    ),
                    Container(
                      width: MediaQuery.of(context).size.width / 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            text,
                            textAlign: TextAlign.start,
                            style: AppStyles.textStyleTransactionType(context),
                          ),
                          RichText(
                            textAlign: TextAlign.start,
                            text: TextSpan(
                              text: '',
                              children: [
                                TextSpan(
                                  text: amount,
                                  style: AppStyles.textStyleTransactionAmount(
                                      context),
                                ),
                                TextSpan(
                                  text: " BIS",
                                  style: AppStyles.textStyleTransactionUnit(
                                      context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  width: MediaQuery.of(context).size.width / 2.4,
                  child: Text(
                    address,
                    textAlign: TextAlign.end,
                    style: AppStyles.textStyleTransactionAddress(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } //Dummy Transaction Card End

  // Welcome Card
  TextSpan _getExampleHeaderSpan(BuildContext context) {
    String workingStr;
    if (StateContainer.of(context).selectedAccount.index == 0) {
      workingStr = AppLocalization.of(context).exampleCardIntro;
    } else {
      workingStr = AppLocalization.of(context).newAccountIntro;
    }
    if (!workingStr.contains("BIS")) {
      return TextSpan(
        text: workingStr,
        style: AppStyles.textStyleTransactionWelcome(context),
      );
    }
    // Colorize cryptocurrency
    List<String> splitStr = workingStr.split("BIS");
    if (splitStr.length != 2) {
      return TextSpan(
        text: workingStr,
        style: AppStyles.textStyleTransactionWelcome(context),
      );
    }
    return TextSpan(
      text: '',
      children: [
        TextSpan(
          text: splitStr[0],
          style: AppStyles.textStyleTransactionWelcome(context),
        ),
        TextSpan(
          text: "BIS",
          style: AppStyles.textStyleTransactionWelcomePrimary(context),
        ),
        TextSpan(
          text: splitStr[1],
          style: AppStyles.textStyleTransactionWelcome(context),
        ),
      ],
    );
  }

  Widget _buildWelcomeTransactionCard(BuildContext context) {
    return Container(
      margin: EdgeInsetsDirectional.fromSTEB(14.0, 4.0, 14.0, 4.0),
      decoration: BoxDecoration(
        color: StateContainer.of(context).curTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: [StateContainer.of(context).curTheme.boxShadow],
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Container(
              width: 7.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10.0),
                    bottomLeft: Radius.circular(10.0)),
                color: StateContainer.of(context).curTheme.primary,
                boxShadow: [StateContainer.of(context).curTheme.boxShadow],
              ),
            ),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 14.0, horizontal: 15.0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: _getExampleHeaderSpan(context),
                ),
              ),
            ),
            Container(
              width: 7.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                    topRight: Radius.circular(10.0),
                    bottomRight: Radius.circular(10.0)),
                color: StateContainer.of(context).curTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  } // Welcome Card End

  // Loading Transaction Card
  Widget _buildLoadingTransactionCard(
      String type, String amount, String address, BuildContext context) {
    String text;
    IconData icon;
    Color iconColor;
    if (type == "Sent") {
      text = "Senttt";
      icon = AppIcons.dotfilled;
      iconColor = StateContainer.of(context).curTheme.text20;
    } else {
      text = "Receiveddd";
      icon = AppIcons.dotfilled;
      iconColor = StateContainer.of(context).curTheme.primary20;
    }
    return Container(
      margin: EdgeInsetsDirectional.fromSTEB(14.0, 4.0, 14.0, 4.0),
      decoration: BoxDecoration(
        color: StateContainer.of(context).curTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: [StateContainer.of(context).curTheme.boxShadow],
      ),
      child: TextButton(
        onPressed: () {
          return null;
        },
        child: Center(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 14.0, horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    // Transaction Icon
                    Opacity(
                      opacity: _opacityAnimation.value,
                      child: Container(
                          margin: EdgeInsetsDirectional.only(end: 16.0),
                          child: Icon(icon, color: iconColor, size: 20)),
                    ),
                    Container(
                      width: MediaQuery.of(context).size.width / 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Transaction Type Text
                          Container(
                            child: Stack(
                              alignment: AlignmentDirectional(-1, 0),
                              children: <Widget>[
                                Text(
                                  text,
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: "Roboto",
                                    fontSize: AppFontSizes.small,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.transparent,
                                  ),
                                ),
                                Opacity(
                                  opacity: _opacityAnimation.value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: StateContainer.of(context)
                                          .curTheme
                                          .text45,
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      text,
                                      textAlign: TextAlign.start,
                                      style: TextStyle(
                                        fontFamily: "Roboto",
                                        fontSize: AppFontSizes.small - 4,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Amount Text
                          Container(
                            child: Stack(
                              alignment: AlignmentDirectional(-1, 0),
                              children: <Widget>[
                                Text(
                                  amount,
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                      fontFamily: "Roboto",
                                      color: Colors.transparent,
                                      fontSize: AppFontSizes.smallest,
                                      fontWeight: FontWeight.w600),
                                ),
                                Opacity(
                                  opacity: _opacityAnimation.value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: StateContainer.of(context)
                                          .curTheme
                                          .primary20,
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      amount,
                                      textAlign: TextAlign.start,
                                      style: TextStyle(
                                          fontFamily: "Roboto",
                                          color: Colors.transparent,
                                          fontSize: AppFontSizes.smallest - 3,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Address Text
                Container(
                  width: MediaQuery.of(context).size.width / 2.4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Container(
                        child: Stack(
                          alignment: AlignmentDirectional(1, 0),
                          children: <Widget>[
                            Text(
                              address,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: AppFontSizes.smallest,
                                fontFamily: 'OverpassMono',
                                fontWeight: FontWeight.w100,
                                color: Colors.transparent,
                              ),
                            ),
                            Opacity(
                              opacity: _opacityAnimation.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: StateContainer.of(context)
                                      .curTheme
                                      .text20,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  address,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: AppFontSizes.smallest - 3,
                                    fontFamily: 'OverpassMono',
                                    fontWeight: FontWeight.w100,
                                    color: Colors.transparent,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } // Loading Transaction Card End

  //Main Card
  Widget _buildMainCard(BuildContext context, _scaffoldKey) {
    return Container(
      decoration: BoxDecoration(
        color: StateContainer.of(context).curTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: [StateContainer.of(context).curTheme.boxShadow],
      ),
      margin: EdgeInsets.only(
          left: 14.0,
          right: 14.0,
          top: MediaQuery.of(context).size.height * 0.005),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          AnimatedContainer(
            duration: Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 80.0,
            height: mainCardHeight,
            alignment: AlignmentDirectional(-1, -1),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              margin: EdgeInsetsDirectional.only(
                  top: settingsIconMarginTop, start: 5),
              height: 50,
              width: 50,
              child: TextButton(
                  onPressed: () {
                    _scaffoldKey.currentState.openDrawer();
                  },
                  child: Icon(FontAwesome.sliders,
                      color: StateContainer.of(context).curTheme.icon,
                      size: 24)),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: 200),
            height: mainCardHeight,
            curve: Curves.easeInOut,
            child: _getBalanceWidget(),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: mainCardHeight == 64 ? 60 : 74,
            height: mainCardHeight == 64 ? 60 : 74,
            margin: EdgeInsets.only(right: 2),
            alignment: Alignment(0, 0),
            child: Stack(
              children: <Widget>[
                Center(
                  child: Container(
                    child: Hero(
                      tag: "avatar",
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (BuildContext context) {
                            return UIUtil.showAccountWebview(
                                context,
                                StateContainer.of(context)
                                    .selectedAccount
                                    .address ?? '');
                          }));
                        },
                        child: CircleAvatar(
                          backgroundColor:
                              StateContainer.of(context).curTheme.text05,
                          backgroundImage: NetworkImage(
                            StateContainer.of(context)
                                            .selectedAccount
                                            .dragginatorDna ==
                                        null ||
                                    StateContainer.of(context)
                                            .selectedAccount
                                            .dragginatorDna ==
                                        ""
                                ? UIUtil.getRobohashURL(
                                    StateContainer.of(context)
                                        .selectedAccount
                                        .address ?? '')
                                : UIUtil.getDragginatorURL(
                                    StateContainer.of(context)
                                        .selectedAccount
                                        .dragginatorDna ?? '',
                                    StateContainer.of(context)
                                        .selectedAccount
                                        .dragginatorStatus ?? ''),
                          ),
                          radius: 50.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  } //Main Card

  // Get balance display
  Widget _getBalanceWidget() {
    if (StateContainer.of(context).wallet?.loading ?? false) {
      // Placeholder for balance text
      return Container(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _priceConversion == PriceConversion.BTC
                ? Container(
                    child: Stack(
                      alignment: AlignmentDirectional(0, 0),
                      children: <Widget>[
                        Text(
                          "1234567",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: "Roboto",
                              fontSize: AppFontSizes.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.transparent),
                        ),
                        Opacity(
                          opacity: _opacityAnimation.value,
                          child: Container(
                            decoration: BoxDecoration(
                              color: StateContainer.of(context).curTheme.text20,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              "1234567",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: "Roboto",
                                  fontSize: AppFontSizes.small - 3,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.transparent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : SizedBox(),
            Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 225),
              child: Stack(
                alignment: AlignmentDirectional(0, 0),
                children: <Widget>[
                  AutoSizeText(
                    "1234567",
                    style: TextStyle(
                        fontFamily: "Roboto",
                        fontSize: AppFontSizes.largestc,
                        fontWeight: FontWeight.w900,
                        color: Colors.transparent),
                    maxLines: 1,
                    stepGranularity: 0.1,
                    minFontSize: 1,
                  ),
                  Opacity(
                    opacity: _opacityAnimation.value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: StateContainer.of(context).curTheme.primary60,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: AutoSizeText(
                        "1234567",
                        style: TextStyle(
                            fontFamily: "Roboto",
                            fontSize: AppFontSizes.largestc - 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.transparent),
                        maxLines: 1,
                        stepGranularity: 0.1,
                        minFontSize: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _priceConversion == PriceConversion.BTC
                ? Container(
                    child: Stack(
                      alignment: AlignmentDirectional(0, 0),
                      children: <Widget>[
                        Text(
                          "1234567",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: "Roboto",
                              fontSize: AppFontSizes.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.transparent),
                        ),
                        Opacity(
                          opacity: _opacityAnimation.value,
                          child: Container(
                            decoration: BoxDecoration(
                              color: StateContainer.of(context).curTheme.text20,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              "1234567",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: "Roboto",
                                  fontSize: AppFontSizes.small - 3,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.transparent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : SizedBox(),
          ],
        ),
      );
    }
    // Balance texts
    return GestureDetector(
      onTap: () {
        if (_priceConversion == PriceConversion.BTC) {
          // Hide prices
          setState(() {
            _priceConversion = PriceConversion.NONE;
            mainCardHeight = 64;
            settingsIconMarginTop = 7;
          });
          sl.get<SharedPrefsUtil>().setPriceConversion(PriceConversion.NONE);
        } else if (_priceConversion == PriceConversion.NONE) {
          // Cycle to hidden
          setState(() {
            _priceConversion = PriceConversion.HIDDEN;
            mainCardHeight = 64;
            settingsIconMarginTop = 7;
          });
          sl.get<SharedPrefsUtil>().setPriceConversion(PriceConversion.HIDDEN);
        } else if (_priceConversion == PriceConversion.HIDDEN) {
          // Cycle to BTC price
          setState(() {
            mainCardHeight = 120;
            settingsIconMarginTop = 5;
          });
          Future.delayed(Duration(milliseconds: 150), () {
            setState(() {
              _priceConversion = PriceConversion.BTC;
            });
          });
          sl.get<SharedPrefsUtil>().setPriceConversion(PriceConversion.BTC);
        }
      },
      child: Container(
        alignment: Alignment.center,
        width: MediaQuery.of(context).size.width - 190,
        color: Colors.transparent,
        child: _priceConversion == PriceConversion.HIDDEN
            ? Center(
                child: Container(
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Image.asset("assets/icon.png"),
                  ),
                ),
              )
            : Container(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _priceConversion == PriceConversion.BTC
                        ? Text(
                            StateContainer.of(context)
                                .wallet
                                ?.getLocalCurrencyPrice(
                                    StateContainer.of(context).curCurrency,
                                    locale: StateContainer.of(context)
                                        .currencyLocale ?? '') ?? '0.00',
                            textAlign: TextAlign.center,
                            style: AppStyles.textStyleCurrencyAlt(context))
                        : SizedBox(height: 0),
                    Container(
                      margin: EdgeInsetsDirectional.only(end: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Container(
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width - 205),
                            child: AutoSizeText.rich(
                              TextSpan(
                                children: [
                                  // Main balance text
                                  TextSpan(
                                    text: (StateContainer.of(context)
                                            .wallet
                                            ?.getAccountBalanceDisplay() ?? '0.00') +
                                        " BIS",
                                    style: _priceConversion ==
                                            PriceConversion.BTC
                                        ? AppStyles.textStyleCurrency(context)
                                        : AppStyles.textStyleCurrencySmaller(
                                            context),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize:
                                      _priceConversion == PriceConversion.BTC
                                          ? 28
                                          : 22),
                              stepGranularity: 0.1,
                              minFontSize: 1,
                              maxFontSize:
                                  _priceConversion == PriceConversion.BTC
                                      ? 28
                                      : 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Pending delta from mempool (server)
                    Builder(builder: (context) {
                      final wallet = StateContainer.of(context).wallet;
                      if (wallet == null) return SizedBox(height: 0);
                      final double pendingDelta = wallet.getPendingDelta();
                      if (pendingDelta == 0) return SizedBox(height: 0);
                      final String pendingText = (pendingDelta > 0 ? "+ " : "- ") +
                          wallet.getPendingDeltaDisplay() +
                          " BIS (pending)";
                      final Color color = Colors.orange; // Keep pending as orange
                      final TextStyle baseStyle = pendingDelta > 0
                          ? AppStyles.textStyleTransactionTypeGreen(context)
                          : AppStyles.textStyleTransactionTypeRed(context);
                      return Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Pending: " + pendingText,
                          style: baseStyle.copyWith(color: color),
                        ),
                      );
                    }),
                    _priceConversion == PriceConversion.BTC
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                  _priceConversion == PriceConversion.BTC
                                      ? AppIcons.btc
                                      // TODO : pas bon
                                      : AppIcons.accountwallet,
                                  color:
                                      _priceConversion == PriceConversion.NONE
                                          ? Colors.transparent
                                          : StateContainer.of(context)
                                              .curTheme
                                              .text60,
                                  size: 14),
                              Text(StateContainer.of(context).wallet?.btcPrice ?? '0.00',
                                  textAlign: TextAlign.center,
                                  style:
                                      AppStyles.textStyleCurrencyAlt(context)),
                            ],
                          )
                        : SizedBox(height: 0),
                  ],
                ),
              ),
      ), // Close WillPopScope child (Scaffold)  
    );
  }
}

class TransactionDetailsSheet extends StatefulWidget {
  final AddressTxsResponseResult? item;
  final String? address;
  final String? displayName;

  TransactionDetailsSheet({this.item, this.address, this.displayName})
      : super();

  _TransactionDetailsSheetState createState() =>
      _TransactionDetailsSheetState();
}

class _TransactionDetailsSheetState extends State<TransactionDetailsSheet> {
  // Current state references
  bool _addressCopied = false;
  // Timer reference so we can cancel repeated events
  late Timer _addressCopiedTimer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        minimum:
            EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.035),
        child: Column(
          children: <Widget>[
            // A row for the address text and close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                //Empty SizedBox
                SizedBox(
                  width: 60,
                  height: 60,
                ),
                Column(
                  children: <Widget>[
                    // Sheet handle
                    Container(
                      margin: EdgeInsets.only(top: 10),
                      height: 5,
                      width: MediaQuery.of(context).size.width * 0.15,
                      decoration: BoxDecoration(
                        color: StateContainer.of(context).curTheme.text10,
                        borderRadius: BorderRadius.circular(100.0),
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.only(top: 15.0),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width - 140),
                      child: Column(
                        children: <Widget>[
                          // Header
                          AutoSizeText(
                            CaseChange.toUpperCase(
                                AppLocalization.of(context).transactionHeader,
                                context),
                            style: AppStyles.textStyleHeader(context),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            stepGranularity: 0.1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                //Empty SizedBox
                SizedBox(
                  width: 60,
                  height: 60,
                ),
              ],
            ),

            Expanded(
              child: Container(
                margin: EdgeInsets.only(top: 0, bottom: 10),
                child: Center(
                  child: Stack(children: <Widget>[
                    SingleChildScrollView(
                        child: Padding(
                      padding: EdgeInsets.only(
                          top: 30, bottom: 80, left: 10, right: 10),
                      child: Column(
                        children: <Widget>[
                          // list
                          Stack(
                            children: <Widget>[
                              Column(
                                children: [
                                  SizedBox(height: 20),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailBlock),
                                  (widget.item?.blockHeight ?? 0) == -1
                                      ? SizedBox()
                                      : SelectableText(widget.item?.blockHash ?? '',
                                          style: AppStyles
                                              .textStyleTransactionUnit(
                                                  context),
                                          textAlign: TextAlign.center),
                                  (widget.item?.blockHeight ?? 0) == -1
                                      ? Text(
                                          "(" +
                                              AppLocalization.of(context)
                                                  .mempool +
                                              ")",
                                          style: AppStyles
                                              .textStyleTransactionUnit(
                                                  context))
                                      : Text(
                                          "(" +
                                              (widget.item?.blockHeight ?? 0)
                                                  .toString() +
                                              ")",
                                          style: AppStyles
                                              .textStyleTransactionUnit(
                                                  context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailDate),
                                  Text(
                                      DateFormat.yMd(
                                              Localizations.localeOf(context)
                                                  .languageCode)
                                          .add_Hms()
                                          .format(widget.item?.timestamp ?? DateTime.now())
                                          .toString(),
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailFrom),
                                  SelectableText(widget.item?.from ?? '',
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailTo),
                                  SelectableText(widget.item?.recipient ?? '',
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailTxId),
                                  SelectableText(widget.item?.hash ?? '',
                                      style: AppStyles.textStyleTransactionUnit(
                                          context),
                                      textAlign: TextAlign.center),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailAmount),
                                  Text(
                                      (widget.item?.type ?? BlockTypes.RECEIVE) == BlockTypes.SEND
                                          ? "- " +
                                              (widget.item?.getFormattedAmount() ?? '0.00') +
                                              " BIS"
                                          : (widget.item?.type ?? BlockTypes.RECEIVE) == BlockTypes.UNCONFIRMED
                                          ? (widget.item?.recipient == StateContainer.of(context).selectedAccount.address
                                              ? "+ " +
                                                  (widget.item?.getFormattedAmount() ?? '0.00') +
                                                  " BIS (pending)"
                                              : "- " +
                                                  (widget.item?.getFormattedAmount() ?? '0.00') +
                                                  " BIS (pending)")
                                          : "+ " +
                                              (widget.item?.getFormattedAmount() ?? '0.00') +
                                              " BIS",
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailFee),
                                  Text(
                                      "- " +
                                          (widget.item?.fee ?? 0).toString() +
                                          " BIS",
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailReward),
                                  Text((widget.item?.reward ?? 0).toString() + " BIS",
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailSignature),
                                  SelectableText(widget.item?.signature ?? '',
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailOperation),
                                  SelectableText(widget.item?.operation ?? '',
                                      style: AppStyles.textStyleTransactionUnit(
                                          context)),
                                  SizedBox(height: 10),
                                  Text(AppLocalization.of(context)
                                      .transactionDetailOpenfield),
                                  SelectableText(widget.item?.openfield ?? '',
                                      style: AppStyles.textStyleTransactionUnit(
                                          context),
                                      textAlign: TextAlign.center),
                                  SizedBox(height: 20),
                                  Text(
                                      "* " +
                                          AppLocalization.of(context)
                                              .transactionDetailCopyPaste,
                                      style: AppStyles.textStyleTransactionUnit(
                                          context),
                                      textAlign: TextAlign.left),
                                  Column(
                                    children: <Widget>[
                                      // A stack for Copy Address and Add Contact buttons
                                      Stack(
                                        children: <Widget>[
                                          // A row for Copy Address Button
                                          Row(
                                            children: <Widget>[
                                              AppButton.buildAppButton(
                                                  context,
                                                  // Share Address Button
                                                  _addressCopied
                                                      ? AppButtonType.SUCCESS
                                                      : AppButtonType.PRIMARY,
                                                  _addressCopied
                                                      ? AppLocalization.of(
                                                              context)
                                                          .addressCopied
                                                      : AppLocalization.of(
                                                              context)
                                                          .copyAddress,
                                                  Dimens
                                                      .BUTTON_TOP_EXCEPTION_DIMENS,
                                                  onPressed: () {
                                                Clipboard.setData(
                                                    new ClipboardData(
                                                        text: widget.address ?? ""));
                                                if (mounted) {
                                                  setState(() {
                                                    // Set copied style
                                                    _addressCopied = true;
                                                  });
                                                }
                                                _addressCopiedTimer.cancel();
                                                                                              _addressCopiedTimer = new Timer(
                                                    const Duration(
                                                        milliseconds: 800), () {
                                                  if (mounted) {
                                                    setState(() {
                                                      _addressCopied = false;
                                                    });
                                                  }
                                                });
                                              }),
                                            ],
                                          ),
                                          // A row for Add Contact Button
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: <Widget>[
                                              Container(
                                                margin: EdgeInsetsDirectional.only(
                                                    top: Dimens
                                                            .BUTTON_TOP_EXCEPTION_DIMENS[
                                                        1],
                                                    end: Dimens
                                                        .BUTTON_TOP_EXCEPTION_DIMENS[2]),
                                                child: Container(
                                                  height: 55,
                                                  width: 55,
                                                  // Add Contact Button
                                                  child: !(widget.displayName
                                                          ?.startsWith("@") ?? false)
                                                      ? TextButton(
                                                          onPressed: () {
                                                            Navigator.of(
                                                                    context)
                                                                .pop();
                                                            Sheets.showAppHeightNineSheet(
                                                                context:
                                                                    context,
                                                                widget: AddContactSheet(
                                                                    address: widget
                                                                        .address));
                                                          },
                                                          child: Icon(
                                                              AppIcons
                                                                  .addcontact,
                                                              size: 35,
                                                              color: _addressCopied
                                                                  ? StateContainer.of(
                                                                          context)
                                                                      .curTheme
                                                                      .successDark
                                                                  : StateContainer.of(
                                                                          context)
                                                                      .curTheme
                                                                      .backgroundDark),
                                                        )
                                                      : SizedBox(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    )),
                  ]),
                ),
              ),
            ),
          ],
        ));
  }
}

/// This is used so that the elevation of the container is kept and the
/// drop shadow is not clipped.
///
class _SizeTransitionNoClip extends AnimatedWidget {
  final Widget? child;

  const _SizeTransitionNoClip(
      {required Animation<double> sizeFactor, this.child})
      : super(listenable: sizeFactor);

  @override
  Widget build(BuildContext context) {
    return new Align(
      alignment: const AlignmentDirectional(-1.0, -1.0),
      widthFactor: null,
      heightFactor: (this.listenable as Animation<double>).value,
      child: child,
    );
  }
}
