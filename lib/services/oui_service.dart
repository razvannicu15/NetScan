import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/utils.dart';

/// MAC vendor lookup backed by the bundled IEEE OUI database.
class OuiService {
  OuiService._();
  static final OuiService instance = OuiService._();

  Map<String, String> _map = const {};
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final data = await rootBundle.load('assets/oui.tsv.gz');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      _map = await Isolate.run(() => _decode(bytes));
    } catch (_) {
      _map = const {};
    }
  }

  static Map<String, String> _decode(Uint8List gz) {
    final text = utf8.decode(gzip.decode(gz), allowMalformed: true);
    final map = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final i = line.indexOf('\t');
      if (i == 6) map[line.substring(0, 6)] = _pretty(line.substring(7));
    }
    return map;
  }

  static final RegExp _suffix = RegExp(
    r'[,\s]+(inc\.?|incorporated|co\.?,?\s*ltd\.?|ltd\.?|limited|corp\.?|corporation|gmbh|llc|s\.?a\.?|b\.?v\.?|ag|pte\.?|pvt\.?|technologies|technology|electronics|international|company)$',
    caseSensitive: false,
  );

  static String _pretty(String raw) {
    var s = raw.trim();
    for (var i = 0; i < 4; i++) {
      final n = s.replaceAll(_suffix, '').trim();
      if (n == s || n.isEmpty) break;
      s = n;
    }
    // Title-case names that are written in ALL CAPS.
    if (s == s.toUpperCase() && s.length > 4) {
      s = s
          .toLowerCase()
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }
    return s;
  }

  String? lookup(String? mac) {
    if (mac == null) return null;
    final hex = mac.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
    if (hex.length < 6) return null;
    final v = _map[hex.substring(0, 6)];
    if (v != null) return v;
    final n = normalizeMac(mac);
    if (n != null && isRandomMac(n)) return 'MAC privat (aleator)';
    return null;
  }
}
