// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:event_taxi/event_taxi.dart';

// Project imports:
import 'package:my_bismuth_wallet/bus/events.dart';
import 'package:my_bismuth_wallet/styles.dart';

class SyncInfoView extends StatefulWidget {
  const SyncInfoView({Key? key}) : super(key: key);

  @override
  _SyncInfoViewState createState() => _SyncInfoViewState();
}

class _SyncInfoViewState extends State<SyncInfoView> {
  late bool connected;
  String serverName = "";

  // Subscriptions
  late StreamSubscription<ConnStatusEvent> _connStatusEventSub;

  @override
  void initState() {
    super.initState();
    connected = false; // Initialize with default value
    _registerBus();
  }

  void _registerBus() {
    _connStatusEventSub =
        EventTaxiImpl.singleton().registerTo<ConnStatusEvent>().listen((event) {
      setState(() {
        serverName = event.server ?? "";
        if (event.status == ConnectionStatus.CONNECTED) {
          connected = true;
        } else {
          connected = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _destroyBus();
    super.dispose();
  }

  void _destroyBus() {
    _connStatusEventSub.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return _buildChild();
  }

  Widget _buildChild() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(serverName, style: AppStyles.textStyleTiny(context)),
        connected == false
            ? Icon(Icons.signal_cellular_alt_rounded, color: Colors.red)
            : Icon(Icons.signal_cellular_alt_rounded, color: Colors.green),
      ],
    );
  }
}
