

// Dart imports:
import 'dart:math';
import 'dart:typed_data';

// Project imports:
import 'package:my_bismuth_wallet/util/app_ffi/encrypt/aes/aes_cbcpkcs7.dart';
import 'package:my_bismuth_wallet/util/app_ffi/encrypt/kdf/kdf.dart';
import 'package:my_bismuth_wallet/util/app_ffi/encrypt/kdf/sha256_kdf.dart';
import 'package:my_bismuth_wallet/util/app_ffi/encrypt/model/keyiv.dart';
import 'package:my_bismuth_wallet/util/helpers.dart';

/// Utility for encrypting and decrypting
class AppCrypt {
  /// Decrypts a value with a password using AES/CBC/PKCS7
  /// KDF is Sha256KDF if not specified
  static Uint8List decrypt(dynamic value, String password, {KDF? kdf}) {
    kdf = kdf ?? Sha256KDF();
    
    // Validate inputs
    if (value == null) {
      throw Exception('Value cannot be null');
    }
    if (password.isEmpty) {
      throw Exception('Password cannot be empty');
    }
    
    Uint8List valBytes;
    if (value is String) {
      if (value.isEmpty) {
        throw Exception('Value string cannot be empty');
      }
      try {
        valBytes = AppHelpers.hexToBytes(value);
      } catch (e) {
        throw Exception('Invalid hex string: ${e.toString()}');
      }
    } else if (value is Uint8List) {
      if (value.isEmpty) {
        throw Exception('Byte array cannot be empty');
      }
      valBytes = value;
    } else {
      throw Exception('Value should be a string or a byte array, got ${value.runtimeType}');
    }

    Uint8List salt = valBytes.sublist(8, 16);
    KeyIV key = kdf.deriveKey(password, salt: salt);

    // Decrypt
    Uint8List encData = valBytes.sublist(16);

    return AesCbcPkcs7.decrypt(encData, key: key.key, iv: key.iv);
  }

  /// Encrypts a value using AES/CBC/PKCS7
  /// KDF is Sha256KDF if not specified
  static Uint8List encrypt(dynamic value, String password, {KDF? kdf}) {
    kdf = kdf ?? Sha256KDF();
    Uint8List valBytes;
    if (value is String) {
      valBytes = AppHelpers.hexToBytes(value);
    } else if (value is Uint8List) {
      valBytes = value;
    } else {
      throw Exception('Seed should be a string or uint8list');
    }

    // Generate a random salt
    Uint8List salt = Uint8List(8);
    Random rng = Random.secure();
    for (int i = 0; i < 8; i++) {
      salt[i] = rng.nextInt(255);
    }

    KeyIV keyInfo = kdf.deriveKey(password, salt: salt);

    Uint8List seedEncrypted =
        AesCbcPkcs7.encrypt(valBytes, key: keyInfo.key, iv: keyInfo.iv);

    return AppHelpers.concat(
        [AppHelpers.stringToBytesUtf8("Salted__"), salt, seedEncrypted]);
  }
}
