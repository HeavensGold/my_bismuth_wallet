// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:logger/logger.dart';
import 'package:validators/validators.dart';

// Project imports:
import 'package:my_bismuth_wallet/localization.dart';
import 'package:my_bismuth_wallet/model/address.dart' as BismuthAddress;
import 'package:my_bismuth_wallet/service_locator.dart';
import 'package:my_bismuth_wallet/ui/util/ui_util.dart';
import 'package:my_bismuth_wallet/util/app_ffi/keys/seeds.dart';

enum DataType { RAW, URL, ADDRESS, SEED }

class QRScanErrs {
  static const String PERMISSION_DENIED = "qr_denied";
  static const String UNKNOWN_ERROR = "qr_unknown";
  static const String CANCEL_ERROR = "qr_cancel";
  static const String GENERIC_ERROR = "qr_generic";
  static const List<String> ERROR_LIST = [
    PERMISSION_DENIED,
    UNKNOWN_ERROR,
    CANCEL_ERROR,
    GENERIC_ERROR
  ];
}

class UserDataUtil {
  static final Logger log = sl.get<Logger>();

  static StreamSubscription<dynamic>? setStream;

  static String? parseData(String data, DataType type) {
    data = data.trim();

    if (type == DataType.RAW) {
      return data;
    } else if (type == DataType.URL) {
      if (isIP(data)) {
        return data;
      } else if (isURL(data)) {
        return data;
      }
    } else if (type == DataType.ADDRESS) {
      BismuthAddress.Address address = BismuthAddress.Address(data);
      if (address.isValid()) {
        return address.address;
      }
    } else if (type == DataType.SEED) {
      // Check if valid seed
      if (AppSeeds.isValidSeed(data)) {
        return data;
      }
    }
    return null;
  }

  static Future<String?> getClipboardText(DataType type) async {
    ClipboardData? data = await Clipboard.getData("text/plain");
    if (data?.text == null) {
      return null;
    }
    return parseData(data!.text!, type);
  }

  static Future<String?> getQRData(DataType type, BuildContext context) async {
    UIUtil.cancelLockEvent();

    // Navigate to QR scanner page and wait for result
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => QRScannerPage(dataType: type),
      ),
    );

    // The scanner page already returns parsed data or error codes
    return result;
  }
}

// QR Scanner Page implementation using mobile_scanner
class QRScannerPage extends StatefulWidget {
  final DataType dataType;

  const QRScannerPage({Key? key, required this.dataType}) : super(key: key);

  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  late MobileScannerController cameraController;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalization.of(context).scanQrCode ?? 'Scan QR Code'),
        actions: [
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.flash_off, color: Colors.grey),
            iconSize: 32.0,
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.camera_rear),
            iconSize: 32.0,
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: cameraController,
              onDetect: (BarcodeCapture capture) {
                if (isProcessing) return;

                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final barcode = barcodes.first;
                  if (barcode.rawValue != null) {
                    _processScanResult(barcode.rawValue!);
                  }
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Point your camera at a QR code to scan it',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _processScanResult(String scannedData) {
    if (isProcessing) return;

    setState(() {
      isProcessing = true;
    });

    try {
      final parsedData = UserDataUtil.parseData(scannedData, widget.dataType);

      if (parsedData != null) {
        // Valid data found, return the parsed data
        Navigator.of(context).pop(parsedData);
      } else {
        // Invalid data, show error and continue scanning
        UIUtil.showSnackbar('Invalid QR code format for this field', context);
        // Reset processing flag to allow continued scanning
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              isProcessing = false;
            });
          }
        });
      }
    } catch (e) {
      UserDataUtil.log.e('Error processing QR data: $e');
      Navigator.of(context).pop(QRScanErrs.UNKNOWN_ERROR);
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}
