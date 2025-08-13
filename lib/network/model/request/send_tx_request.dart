// To parse this JSON data, do
//
//     final sendTxRequest = sendTxRequestFromJson(jsonString);

// Dart imports:
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// Package imports:
import 'package:asn1lib/asn1lib.dart' as asn1lib;
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';

class SendTxRequest {
  SendTxRequest({
    required this.id,
    required this.tx,
    required this.buffer,
    required this.signature,
    required this.publicKey,
    required this.websocketCommand,
  });

  int id;
  Tx tx;
  String buffer;
  String signature;
  String publicKey;
  String websocketCommand;

  Uint8List getSecureRandom(int length) {
    var random = Random.secure();
    List<int> seeds = [];
    for (int i = 0; i < length; i++) {
      seeds.add(random.nextInt(255));
    }

    return new Uint8List.fromList(seeds);
  }

  String signString(String privateKey, String msgToSign) {
    final ECDSASigner signer = Signer('SHA-256/ECDSA') as ECDSASigner;

    // Validate privateKey before parsing
    if (privateKey.isEmpty) {
      throw Exception('Private key is empty');
    }

    // Remove any whitespace and ensure it's valid hex
    String cleanPrivateKey = privateKey.trim();
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleanPrivateKey)) {
      throw Exception('Private key contains invalid characters');
    }

    final _privateKey = ECPrivateKey(
      BigInt.parse(cleanPrivateKey, radix: 16),
      ECDomainParameters('secp256k1'),
    );
    var privParams = PrivateKeyParameter(_privateKey);

    final rnd = new SecureRandom("AES/CTR/PRNG");
    final key = getSecureRandom(16);
    final iv = getSecureRandom(16);
    final keyParam = new KeyParameter(new Uint8List.fromList(key));

    final params = new ParametersWithIV(keyParam, new Uint8List.fromList(iv));
    rnd.seed(params);

    signer.reset();
    signer.init(true, new ParametersWithRandom(privParams, rnd));
    ECSignature sig =
        signer.generateSignature(utf8.encode(msgToSign)) as ECSignature;
    sig = sig.normalize(ECDomainParameters('secp256k1'));

    var topLevel = new asn1lib.ASN1Sequence();
    topLevel.add(asn1lib.ASN1Integer(sig.r));
    topLevel.add(asn1lib.ASN1Integer(sig.s));

    var sig64 = base64.encode(topLevel.encodedBytes);

    //print("return sig64 : " + sig64);
    return sig64;
  }

  void buildSignature(String privateKey) async {
    signature = signString(privateKey, buffer);
    //print("signature: " + signature);
  }

  factory SendTxRequest.fromJson(Map<String, dynamic> json) => SendTxRequest(
        id: json['id'],
        tx: Tx.fromJson(json['tx']),
        buffer: json['buffer'],
        signature: json['signature'],
        publicKey: json['public_key'],
        websocketCommand: json['websocket_command'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tx': tx.toJson(),
        'buffer': buffer,
        'signature': signature,
        'public_key': publicKey,
        'websocket_command': websocketCommand,
      };

  String buildCommand() {
    String command = '["' + tx.timestamp + '",';
    command += '"' + tx.address + '", ';
    command += '"' + tx.recipient + '", ';
    command += '"' + tx.amount + '", ';
    command += '"' + signature + '", ';
    command += '"' + publicKey + '", ';
    command += '"' + tx.operation + '", ';
    command += '"' + tx.openfield.replaceAll('"', '\\"') + '"]';
    //print("command : " + command);
    return command;
  }
}

class Tx {
  Tx({
    required this.timestamp,
    required this.address,
    required this.recipient,
    required this.amount,
    required this.operation,
    required this.openfield,
  });

  String timestamp;
  String address;
  String recipient;
  String amount;
  String operation;
  String openfield;

  factory Tx.fromJson(Map<String, dynamic> json) => Tx(
        timestamp: json['timestamp'],
        address: json['address'],
        recipient: json['recipient'],
        amount: json['amount'],
        operation: json['operation'],
        openfield: json['openfield'],
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'address': address,
        'recipient': recipient,
        'amount': amount,
        'operation': operation,
        'openfield': openfield,
      };

  String buildBufferValue() {
    String _buffer = "('" +
        timestamp +
        "', '" +
        address +
        "', '" +
        recipient +
        "', '" +
        amount +
        "', '" +
        operation +
        "', '" +
        openfield +
        "')";
    //print("_buffer : " + _buffer);
    return _buffer;
  }
}
