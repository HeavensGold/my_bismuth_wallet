

// Dart imports:
import 'dart:core';

// Object to represent an account address or address URI, and provide useful utilities
class Address {
  late String _address;
  String _amount = '';

  Address(String value) {
    _address = value;
  }

  String get address => _address;

  String get amount => _amount;

  String getShortString() {
    if (_address.length < 21) {
      return _address;
    } else {
      return _address.substring(0, 11) +
          "..." +
          _address.substring(_address.length - 6);
    }
  }

  String getShortString2() {
    if (_address.length < 21) {
      return _address;
    } else {
      return _address.substring(0, 18) +
          "..." +
          _address.substring(_address.length - 6);
    }
  }

  String getShorterString() {
    if (_address.length < 21) {
      return _address;
    } else {
      return _address.substring(0, 9) +
          "..." +
          _address.substring(_address.length - 4);
    }
  }

  bool isValid() {
    if (_address.isEmpty) return false;
    
    // Check for Bis1 format (34-38 characters, base58)
    if (_address.startsWith('Bis1')) {
      if (_address.length < 34 || _address.length > 38) return false;
      // Base58 character check (no 0, O, I, l)
      final base58Chars = RegExp(r'^[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]+$');
      return base58Chars.hasMatch(_address);
    }
    
    // Check for hex format (56 characters, hexadecimal)
    if (_address.length == 56) {
      final hexChars = RegExp(r'^[0-9a-fA-F]+$');
      return hexChars.hasMatch(_address);
    }
    
    return false;
  }
}
