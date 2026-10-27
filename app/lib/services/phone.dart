import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Must match normalizePhone() + sha256() in server/src/store.js
String? normalizePhone(String raw, {String defaultCountry = '880'}) {
  var d = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = defaultCountry + d.substring(1);
  if (d.length < 8 || d.length > 15) return null;
  return d;
}

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();
