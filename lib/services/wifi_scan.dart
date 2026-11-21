import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../core/utils.dart';

/// One access point seen in a Wi-Fi scan.
class WifiAp {
  WifiAp({
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.channel,
    required this.band,
    this.centerChannel,
    this.widthMhz = 20,
    this.security,
    this.standard,
  });

  final String ssid; // empty = hidden
  final String bssid;
  final int rssi; // dBm
  final int channel; // primary channel
  final int? centerChannel; // for 40/80/160 MHz
  final String band; // '2.4 GHz' | '5 GHz' | '6 GHz'
  final int widthMhz;
  final String? security;
  final String? standard;

  bool get hidden => ssid.isEmpty;
  int get center => centerChannel ?? channel;

  /// Half the occupied width, in channel numbers (5 MHz per number).
  double get halfSpan => widthMhz / 10;

  int get signalPercent => (2 * (rssi + 100)).clamp(0, 100).toInt();
}

int? channelFromFreq(int f) {
  if (f <= 0) return null;
  if (f == 2484) return 14;
  if (f < 3000) return (f - 2407) ~/ 5;
  if (f < 5925) return (f - 5000) ~/ 5;
  return (f - 5950) ~/ 5;
}

String? bandFromFreq(int f) {
  if (f <= 0) return null;
  if (f < 3000) return '2.4 GHz';
  if (f < 5925) return '5 GHz';
  return '6 GHz';
}

class WifiScanService {
  static const _ch = MethodChannel('netscan/wifi');

  static bool get supported => Platform.isAndroid || Platform.isWindows;

  static Future<List<WifiAp>> scan({bool trigger = false}) async {
    try {
      if (Platform.isAndroid) return await _android(trigger);
      if (Platform.isWindows) return await _windows();
    } catch (_) {}
    return [];
  }

  static Future<List<WifiAp>> _android(bool trigger) async {
    final list = await _ch.invokeListMethod<dynamic>('scan', {'trigger': trigger});
    if (list == null) return [];
    final out = <WifiAp>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final f = raw['frequency'] as int? ?? 0;
      final ch = channelFromFreq(f);
      final band = bandFromFreq(f);
      final bssid = normalizeMac(raw['bssid'] as String?);
      if (ch == null || band == null || bssid == null) continue;
      final w = switch (raw['width']) { 1 => 40, 2 => 80, 3 || 4 => 160, 5 => 320, _ => 20 };
      final c0 = raw['center0'] as int? ?? 0;
      final caps = (raw['caps'] as String? ?? '').toUpperCase();
      out.add(WifiAp(
        ssid: (raw['ssid'] as String? ?? '').replaceAll('"', ''),
        bssid: bssid,
        rssi: raw['level'] as int? ?? -100,
        channel: ch,
        band: band,
        centerChannel: (w > 20 && c0 > 0) ? channelFromFreq(c0) : null,
        widthMhz: w,
        security: caps.contains('SAE')
            ? 'WPA3'
            : caps.contains('WPA2') || caps.contains('RSN')
                ? 'WPA2'
                : caps.contains('WPA')
                    ? 'WPA'
                    : caps.contains('WEP')
                        ? 'WEP'
                        : 'Open',
        standard: switch (raw['standard']) {
          4 => 'Wi-Fi 4',
          5 => 'Wi-Fi 5',
          6 => band == '6 GHz' ? 'Wi-Fi 6E' : 'Wi-Fi 6',
          8 => 'Wi-Fi 7',
          _ => null,
        },
      ));
    }
    return out;
  }

  /// Parses `netsh wlan show networks mode=bssid` (locale independent).
  static Future<List<WifiAp>> _windows() async {
    final txt = await runCommand('netsh', ['wlan', 'show', 'networks', 'mode=bssid'],
        timeout: const Duration(seconds: 5));
    if (txt == null) return [];
    final out = <WifiAp>[];
    String ssid = '';
    String? auth;
    String? bssid;
    int? pct;
    int? ch;
    String? band;
    String? std;

    void flush() {
      final b = bssid;
      final c = ch;
      if (b != null && c != null && pct != null) {
        out.add(WifiAp(
          ssid: ssid,
          bssid: b,
          rssi: (pct! / 2 - 100).round(),
          channel: c,
          band: band ?? (c <= 14 ? '2.4 GHz' : '5 GHz'),
          security: auth,
          standard: std,
        ));
      }
      bssid = null;
      pct = null;
      ch = null;
      band = null;
      std = null;
    }

    final ssidRe = RegExp(r'^SSID\s+\d+\s*:\s?(.*)$');
    final bssidRe = RegExp(r'^BSSID\s+\d+\s*:\s?(.*)$');
    for (final raw in txt.split('\n')) {
      final line = raw.trim();
      final sm = ssidRe.firstMatch(line);
      if (sm != null) {
        flush();
        ssid = sm.group(1)!.trim();
        auth = null;
        continue;
      }
      final bm = bssidRe.firstMatch(line);
      if (bm != null) {
        flush();
        bssid = normalizeMac(bm.group(1));
        continue;
      }
      final i = line.indexOf(':');
      if (i < 0) continue;
      final k = line.substring(0, i).trim().toLowerCase();
      final v = line.substring(i + 1).trim();
      if (RegExp(r'^\d{1,3}\s?%$').hasMatch(v)) {
        pct = int.parse(v.replaceAll(RegExp(r'[^\d]'), ''));
      } else if ((k.contains('chan') || k.contains('canal') || k.contains('kanal')) &&
          int.tryParse(v) != null) {
        ch = int.parse(v);
      } else if (RegExp(r'^\d(\.\d)?\s?GHz$', caseSensitive: false).hasMatch(v)) {
        band = v.replaceAll(' ', '').replaceAll('GHz', ' GHz');
      } else if (v.contains('802.11')) {
        final l = v.toLowerCase();
        std = l.contains('be')
            ? 'Wi-Fi 7'
            : l.contains('ax')
                ? 'Wi-Fi 6'
                : l.contains('ac')
                    ? 'Wi-Fi 5'
                    : 'Wi-Fi 4';
      } else if (v.toUpperCase().contains('WPA') || v.toUpperCase().contains('WEP')) {
        auth = v;
      } else if (v.toLowerCase() == 'open' || v.toLowerCase() == 'deschis') {
        auth = 'Open';
      }
    }
    flush();
    return out;
  }

  /// Least-interfered channel for [band] (ignores the user's own AP [ownBssid]).
  static int? recommend(List<WifiAp> aps, String band, {String? ownBssid}) {
    final cands = switch (band) {
      '2.4 GHz' => [1, 6, 11],
      '5 GHz' => [36, 40, 44, 48, 149, 153, 157, 161, 165],
      _ => [for (var c = 1; c <= 93; c += 4) c],
    };
    final inBand = aps.where((a) => a.band == band && a.bssid != ownBssid).toList();
    double cost(int c) {
      var sum = 0.0;
      for (final a in inBand) {
        final dist = (c - a.center).abs();
        if (dist < a.halfSpan + 2) sum += pow(10, a.rssi / 10).toDouble();
      }
      return sum;
    }

    int? best;
    var bestCost = double.infinity;
    for (final c in cands) {
      final v = cost(c);
      if (v < bestCost) {
        bestCost = v;
        best = c;
      }
    }
    return best;
  }
}
