

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:event_taxi/event_taxi.dart';
import 'package:fluttericon/font_awesome_icons.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

// Project imports:
import 'package:my_bismuth_wallet/app_icons.dart';
import 'package:my_bismuth_wallet/appstate_container.dart';
import 'package:my_bismuth_wallet/bus/events.dart';
import 'package:my_bismuth_wallet/localization.dart';
import 'package:my_bismuth_wallet/network/model/response/wstatusget_response.dart';
import 'package:my_bismuth_wallet/network/model/response/servers_wallet_legacy.dart';
import 'package:my_bismuth_wallet/service/app_service.dart';
import 'package:my_bismuth_wallet/service/http_service.dart';
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/styles.dart';
import 'package:my_bismuth_wallet/ui/widgets/app_text_field.dart';
import 'package:my_bismuth_wallet/util/sharedprefsutil.dart';

class CustomUrl extends StatefulWidget {
  final AnimationController tokensListController;
  bool tokensListOpen;

  CustomUrl(this.tokensListController, this.tokensListOpen, {super.key});

  _CustomUrlState createState() => _CustomUrlState();
}

class _CustomUrlState extends State<CustomUrl> with SingleTickerProviderStateMixin {
  final Logger log = sl.get<Logger>();
  
  late TabController _tabController;
  List<ServerWalletLegacyResponse> _availableServers = [];
  bool _loadingServers = false;
  Timer? _serverRefreshTimer;

  late WStatusGetResponse wStatusGetResponse;

  // Subscriptions
  late StreamSubscription<ConnStatusEvent> _connStatusEventSub;

  late bool walletServerOk;
  late bool tokenApiOk;

  late FocusNode _walletServerFocusNode;
  late FocusNode _tokenApiFocusNode;
  late FocusNode _explorerUrlFocusNode;
  late TextEditingController _walletServerController;
  late TextEditingController _tokenApiController;
  late TextEditingController _explorerUrlController;

  late bool useCustomWalletServer;
  late bool useCustomExplorerUrl;

  String? _walletServerHint = "";
  String? _tokenApiHint = "";
  String? _explorerUrlHint = "";
  String _walletServerValidationText = "";
  String _tokenApiValidationText = "";
  String _explorerUrlValidationText = "";

  void initControllerText() async {
    String w = await sl.get<SharedPrefsUtil>().getWalletServer();
    _walletServerController.text = w;
    if (w == "auto") {
      useCustomWalletServer = false;
    } else {
      useCustomWalletServer = true;
    }
    updateWalletServer();
    _tokenApiController.text = await sl.get<SharedPrefsUtil>().getTokensApi();
    updateTokenApi();
    _explorerUrlController.text =
        await sl.get<SharedPrefsUtil>().getExplorerUrl();
    if (_explorerUrlController.text == "" ||
        _explorerUrlController.text ==
            AppLocalization.of(context).explorerUrlByDefault) {
      useCustomExplorerUrl = false;
    } else {
      useCustomExplorerUrl = true;
    }
  }

  void updateWalletServer() async {
    await sl
        .get<SharedPrefsUtil>()
        .setWalletServer(_walletServerController.text);
    sl.get<AppService>().getWStatusGetResponse();
  }

  void updateTokenApi() async {
    await sl.get<SharedPrefsUtil>().setTokensApi(_tokenApiController.text);
    tokenApiOk = await sl
        .get<HttpService>()
        .isTokensBalance(StateContainer.of(context).selectedAccount?.address ?? '');
    setState(() {});
  }

  void updateExplorerUrl() async {
    await sl.get<SharedPrefsUtil>().setExplorerUrl(_explorerUrlController.text);
    setState(() {});
  }
  
  Future<void> _fetchAvailableServers() async {
    setState(() {
      _loadingServers = true;
    });
    
    try {
      final response = await http.get(
        Uri.parse("https://bismuth.world/api/legacy.json"),
        headers: {
          'content-type': 'application/json',
          'access-Control-Allow-Origin': '*'
        }
      );
      
      if (response.statusCode == 200) {
        List<ServerWalletLegacyResponse> servers = 
            serverWalletLegacyResponseFromJson(response.body);
        
        // Sort servers: active first, then by number of clients
        servers.sort((a, b) {
          if (a.active != b.active) {
            return a.active ? -1 : 1;
          }
          return a.clients.compareTo(b.clients);
        });
        
        setState(() {
          _availableServers = servers;
          _loadingServers = false;
        });
      }
    } catch (e) {
      log.e("Error fetching servers: $e");
      setState(() {
        _loadingServers = false;
      });
    }
  }
  
  void _selectServer(ServerWalletLegacyResponse server) {
    setState(() {
      _walletServerController.text = "${server.ip}:${server.port}";
      useCustomWalletServer = true;
    });
    updateWalletServer();
  }

  @override
  void initState() {
    _registerBus();
    super.initState();
    
    _tabController = TabController(length: 2, vsync: this);

    useCustomWalletServer = false;
    useCustomExplorerUrl = false;

    walletServerOk = false;
    tokenApiOk = false;

    _walletServerFocusNode = FocusNode();
    _tokenApiFocusNode = FocusNode();
    _explorerUrlFocusNode = FocusNode();
    _walletServerController = TextEditingController();
    _tokenApiController = TextEditingController();
    _explorerUrlController = TextEditingController();

    initControllerText();
    
    // Fetch available servers on init
    _fetchAvailableServers();
    
    // Refresh server list every 30 seconds
    _serverRefreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _fetchAvailableServers();
    });

    _walletServerFocusNode.addListener(() {
      if (_walletServerFocusNode.hasFocus) {
        setState(() {
          _walletServerHint = null;
        });
      } else {
        setState(() {
          _walletServerHint = "";
        });
      }
    });
    _tokenApiFocusNode.addListener(() {
      if (_tokenApiFocusNode.hasFocus) {
        setState(() {
          _tokenApiHint = null;
        });
      } else {
        setState(() {
          _tokenApiHint = "";
        });
      }
    });
    _explorerUrlFocusNode.addListener(() {
      if (_explorerUrlFocusNode.hasFocus) {
        setState(() {
          _explorerUrlHint = null;
        });
      } else {
        setState(() {
          _explorerUrlHint = "";
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _serverRefreshTimer?.cancel();
    _destroyBus();
    super.dispose();
  }

  void _destroyBus() {
    _connStatusEventSub.cancel();
    }

  void _registerBus() {
    _connStatusEventSub =
        EventTaxiImpl.singleton().registerTo<ConnStatusEvent>().listen((event) {
      setState(() {
        if (event.status == ConnectionStatus.CONNECTED) {
          walletServerOk = true;
        } else {
          walletServerOk = false;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
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
            bottom: MediaQuery.of(context).size.height * 0.035,
            top: 60,
          ),
          child: Column(
            children: <Widget>[
              Container(
                margin: EdgeInsets.only(bottom: 10.0, top: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(children: <Widget>[
                      //Back button
                      Container(
                        height: 40,
                        width: 40,
                        margin: EdgeInsets.only(right: 10, left: 10),
                        child: TextButton(
                            onPressed: () {
                              setState(() {
                                widget.tokensListOpen = false;
                              });
                              widget.tokensListController.reverse();
                            },
                            child: Icon(AppIcons.back,
                                color: StateContainer.of(context).curTheme.text,
                                size: 24)),
                      ),
                      // Header Text
                      Text(
                        AppLocalization.of(context).customUrlHeader,
                        style: AppStyles.textStyleSettingsHeader(context),
                      ),
                    ]),
                  ],
                ),
              ),
              // Add TabBar
              Container(
                decoration: BoxDecoration(
                  color: StateContainer.of(context).curTheme.backgroundDarkest,
                  border: Border(
                    bottom: BorderSide(
                      color: StateContainer.of(context).curTheme.text15,
                      width: 1,
                    ),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: StateContainer.of(context).curTheme.primary,
                  labelColor: StateContainer.of(context).curTheme.primary,
                  unselectedLabelColor: StateContainer.of(context).curTheme.text60,
                  tabs: [
                    Tab(
                      child: Text(
                        "Available Servers",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    Tab(
                      child: Text(
                        "Custom URL",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              // TabBarView for content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Available Servers
                    _buildAvailableServersTab(),
                    // Tab 2: Custom URL (existing content)
                    SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.only(top: 30, bottom: bottom + 30),
                        child: Column(children: <Widget>[
                            Stack(children: <Widget>[
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          AppLocalization.of(context)
                                              .enterWalletServerSwitch,
                                          style: TextStyle(
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.w100,
                                            fontFamily: 'Roboto',
                                            color: StateContainer.of(context)
                                                .curTheme
                                                .text60,
                                          ),
                                        ),
                                        Switch(
                                            value: useCustomWalletServer,
                                            onChanged: (value) {
                                              setState(() {
                                                useCustomWalletServer = value;
                                                if (useCustomWalletServer ==
                                                    false) {
                                                  _walletServerController.text =
                                                      "auto";
                                                } else {
                                                  EventTaxiImpl.singleton()
                                                      .fire(ConnStatusEvent(
                                                          status:
                                                              ConnectionStatus
                                                                  .DISCONNECTED,
                                                          server: ""));

                                                  _walletServerController.text =
                                                      "";
                                                }
                                                _walletServerValidationText =
                                                    "";
                                                updateWalletServer();
                                              });
                                            },
                                            activeTrackColor:
                                                StateContainer.of(context)
                                                    .curTheme
                                                    .backgroundDarkest,
                                            activeColor: Colors.green),
                                      ],
                                    ),
                                    SizedBox(
                                      height: 20,
                                    ),
                                    useCustomWalletServer
                                        ? Container(
                                            child: getWalletServerContainer(),
                                          )
                                        : SizedBox(),
                                    useCustomWalletServer
                                        ? Container(
                                            alignment:
                                                AlignmentDirectional(0, 0),
                                            margin: EdgeInsets.only(top: 3),
                                            child: Text(
                                                _walletServerValidationText,
                                                style: TextStyle(
                                                  fontSize: 14.0,
                                                  color:
                                                      StateContainer.of(context)
                                                          .curTheme
                                                          .primary,
                                                  fontFamily: 'Roboto',
                                                  fontWeight: FontWeight.w600,
                                                )),
                                          )
                                        : SizedBox(),
                                    SizedBox(
                                      height: 10,
                                    ),
                                    Divider(
                                      height: 2,
                                      color: StateContainer.of(context)
                                          .curTheme
                                          .text15,
                                    ),
                                    SizedBox(
                                      height: 10,
                                    ),
                                    Container(
                                      child: getTokenApiContainer(),
                                    ),
                                    Container(
                                      alignment: AlignmentDirectional(0, 0),
                                      margin: EdgeInsets.only(top: 3),
                                      child: Text(_tokenApiValidationText,
                                          style: TextStyle(
                                            fontSize: 14.0,
                                            color: StateContainer.of(context)
                                                .curTheme
                                                .primary,
                                            fontFamily: 'Roboto',
                                            fontWeight: FontWeight.w600,
                                          )),
                                    ),
                                    Divider(
                                      height: 2,
                                      color: StateContainer.of(context)
                                          .curTheme
                                          .text15,
                                    ),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            AppLocalization.of(context)
                                                .enterExplorerUrlSwitch,
                                            style: TextStyle(
                                              fontSize: 16.0,
                                              fontWeight: FontWeight.w100,
                                              fontFamily: 'Roboto',
                                              color: StateContainer.of(context)
                                                  .curTheme
                                                  .text60,
                                            ),
                                          ),
                                          Switch(
                                              value: useCustomExplorerUrl,
                                              onChanged: (value) {
                                                setState(() {
                                                  useCustomExplorerUrl = value;
                                                  if (useCustomExplorerUrl ==
                                                      false) {
                                                    _explorerUrlController
                                                        .text = AppLocalization
                                                            .of(context)
                                                        .explorerUrlByDefault;
                                                  } else {
                                                    _explorerUrlController
                                                        .text = "";
                                                  }
                                                  _explorerUrlValidationText =
                                                      "";
                                                  updateExplorerUrl();
                                                });
                                              },
                                              activeTrackColor:
                                                  StateContainer.of(context)
                                                      .curTheme
                                                      .backgroundDarkest,
                                              activeColor: Colors.green),
                                        ]),
                                    useCustomExplorerUrl
                                        ? Container(
                                            child: getExplorerUrlContainer(),
                                          )
                                        : SizedBox(),
                                    useCustomExplorerUrl
                                        ? Container(
                                            alignment:
                                                AlignmentDirectional(0, 0),
                                            margin: EdgeInsets.only(top: 3),
                                            child: Text(
                                                _explorerUrlValidationText,
                                                style: TextStyle(
                                                  fontSize: 14.0,
                                                  color:
                                                      StateContainer.of(context)
                                                          .curTheme
                                                          .primary,
                                                  fontFamily: 'Roboto',
                                                  fontWeight: FontWeight.w600,
                                                )),
                                          )
                                        : SizedBox(),
                                  ])
                            ])
                          ])),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }

  Widget _buildAvailableServersTab() {
    return Container(
      padding: EdgeInsets.all(16),
      child: _loadingServers
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  StateContainer.of(context).curTheme.primary,
                ),
              ),
            )
          : _availableServers.isEmpty
              ? Center(
                  child: Text(
                    "No servers available",
                    style: AppStyles.textStyleParagraph(context),
                  ),
                )
              : ListView.builder(
                  itemCount: _availableServers.length,
                  itemBuilder: (context, index) {
                    final server = _availableServers[index];
                    final isCurrentServer = _walletServerController.text == 
                        "${server.ip}:${server.port}";
                    
                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 4),
                      color: isCurrentServer 
                          ? StateContainer.of(context).curTheme.primary.withValues(alpha: 0.1)
                          : StateContainer.of(context).curTheme.backgroundDarkest,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: server.active 
                              ? Colors.green 
                              : Colors.red,
                          radius: 8,
                        ),
                        title: Text(
                          server.label.isNotEmpty ? server.label : "${server.ip}:${server.port}",
                          style: TextStyle(
                            color: StateContainer.of(context).curTheme.text,
                            fontWeight: isCurrentServer ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${server.ip}:${server.port}",
                              style: TextStyle(
                                color: StateContainer.of(context).curTheme.text60,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              "Country: ${server.country} | Clients: ${server.clients}/${server.totalSlots} | Height: ${server.height}",
                              style: TextStyle(
                                color: StateContainer.of(context).curTheme.text45,
                                fontSize: 11,
                              ),
                            ),
                            if (!server.active)
                              Text(
                                "Server is currently offline",
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        trailing: isCurrentServer
                            ? Icon(
                                Icons.check_circle,
                                color: StateContainer.of(context).curTheme.primary,
                              )
                            : null,
                        onTap: server.active
                            ? () => _selectServer(server)
                            : null,
                      ),
                    );
                  },
                ),
    );
  }

  getWalletServerContainer() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            walletServerOk == false
                ? Icon(
                    Icons.signal_cellular_connected_no_internet_4_bar_rounded,
                    color: Colors.red)
                : Icon(Icons.signal_cellular_alt_rounded, color: Colors.green),
            SizedBox(
              width: 10,
            ),
            Text(
              AppLocalization.of(context).enterWalletServer,
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.w100,
                fontFamily: 'Roboto',
                color: StateContainer.of(context).curTheme.text60,
              ),
            ),
          ],
        ),
        AppTextField(
          leftMargin: 10,
          rightMargin: 10,
          topMargin: 10,
          focusNode: _walletServerFocusNode,
          controller: _walletServerController,
          cursorColor: StateContainer.of(context).curTheme.primary,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16.0,
            color: StateContainer.of(context).curTheme.primary,
            fontFamily: 'Roboto',
          ),
          inputFormatters: [LengthLimitingTextInputFormatter(23)],
          onChanged: (text) {
            updateWalletServer();
            // Always reset the error message to be less annoying
            setState(() {
              _walletServerValidationText = "";
            });
          },
          textInputAction: TextInputAction.next,
          maxLines: 1,
          autocorrect: false,
          hintText: _walletServerHint == null
              ? ""
              : AppLocalization.of(context).enterWalletServer,
          keyboardType: TextInputType.multiline,
          textAlign: TextAlign.left,
          onSubmitted: (text) {
            FocusScope.of(context).unfocus();
          },
        ),
        Text(AppLocalization.of(context).enterWalletServerInfo,
            style: AppStyles.textStyleTiny(context)),
      ],
    );
  }

  getTokenApiContainer() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            tokenApiOk == false
                ? Icon(FontAwesome.connectdevelop, size: 16, color: Colors.red)
                : Icon(FontAwesome.connectdevelop,
                    size: 16, color: Colors.green),
            SizedBox(
              width: 10,
            ),
            Text(
              AppLocalization.of(context).enterTokenApi,
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.w100,
                fontFamily: 'Roboto',
                color: StateContainer.of(context).curTheme.text60,
              ),
            ),
          ],
        ),
        AppTextField(
          leftMargin: 10,
          rightMargin: 10,
          topMargin: 10,
          focusNode: _tokenApiFocusNode,
          controller: _tokenApiController,
          cursorColor: StateContainer.of(context).curTheme.primary,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16.0,
            color: StateContainer.of(context).curTheme.primary,
            fontFamily: 'Roboto',
          ),
          inputFormatters: [LengthLimitingTextInputFormatter(150)],
          onChanged: (text) {
            updateTokenApi();
            // Always reset the error message to be less annoying
            setState(() {
              _tokenApiValidationText = "";
            });
          },
          textInputAction: TextInputAction.next,
          maxLines: 1,
          autocorrect: false,
          hintText: _tokenApiHint == null
              ? ""
              : AppLocalization.of(context).enterTokenApi,
          keyboardType: TextInputType.multiline,
          textAlign: TextAlign.left,
          onSubmitted: (text) {
            FocusScope.of(context).unfocus();
          },
        ),
        Text(AppLocalization.of(context).enterTokenApiInfo,
            style: AppStyles.textStyleTiny(context)),
      ],
    );
  }

  getExplorerUrlContainer() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalization.of(context).enterExplorerUrl,
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.w100,
                fontFamily: 'Roboto',
                color: StateContainer.of(context).curTheme.text60,
              ),
            ),
          ],
        ),
        AppTextField(
          leftMargin: 10,
          rightMargin: 10,
          topMargin: 10,
          focusNode: _explorerUrlFocusNode,
          controller: _explorerUrlController,
          cursorColor: StateContainer.of(context).curTheme.primary,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16.0,
            color: StateContainer.of(context).curTheme.primary,
            fontFamily: 'Roboto',
          ),
          inputFormatters: [LengthLimitingTextInputFormatter(150)],
          onChanged: (text) {
            updateExplorerUrl();
            // Always reset the error message to be less annoying
            setState(() {
              _explorerUrlValidationText = "";
            });
          },
          textInputAction: TextInputAction.next,
          maxLines: 1,
          autocorrect: false,
          hintText: _explorerUrlHint == null
              ? ""
              : AppLocalization.of(context).enterExplorerUrl,
          keyboardType: TextInputType.multiline,
          textAlign: TextAlign.left,
          onSubmitted: (text) {
            FocusScope.of(context).unfocus();
          },
        ),
        Text(AppLocalization.of(context).enterExplorerUrlInfo,
            style: AppStyles.textStyleTiny(context)),
      ],
    );
  }

  bool _validateRequest() {
    bool isValid = true;
    _walletServerFocusNode.unfocus();
    _tokenApiFocusNode.unfocus();

    if (_walletServerController.text.trim().isEmpty) {
      isValid = false;
      setState(() {
        //_walletServerValidationText = AppLocalization.of(context).account;
      });
    }

    return isValid;
  }
}
