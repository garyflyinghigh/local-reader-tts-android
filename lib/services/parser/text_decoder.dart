import 'dart:convert';

import 'package:flutter/services.dart';

class TextDecoder {
  static const MethodChannel _channel =
      MethodChannel('local_reader/text_decoder');

  static Future<String> decodeChineseText(List<int> bytes) async {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      return _decodeChineseBytes(bytes);
    }
  }

  static Future<String> _decodeChineseBytes(List<int> bytes) async {
    try {
      final decoded = await _channel.invokeMethod<String>(
        'decodeBytes',
        <String, Object>{
          'base64': base64Encode(bytes),
          'charsets': <String>['GB18030', 'GBK', 'GB2312'],
        },
      );
      if (decoded != null && decoded.isNotEmpty) {
        return decoded;
      }
    } on MissingPluginException {
      // Non-Android debug targets do not provide the native decoder.
    } on PlatformException {
      // Fall through to a visible best-effort decode instead of failing import.
    }

    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }
}
