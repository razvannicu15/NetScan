import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/utils.dart';

// ======================================================================= ARP

class ArpService {
  /// Returns ip -> MAC from the operating system neighbour cache.
  static Future<Map<String, String>> readTable() async {
    final result = <String, String>{};
    void parse(String text) {
      for (final line in const LineSplitter().convert(text)) {
        final ipM = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
            .firstMatch(line);
        if (ipM == null) continue;
        final lower = line.toLowerCase();
        if (lower.contains('incomplete') || lower.contains('failed')) continue;
        final mac = normalizeMac(line.substring(ipM.end));
        if (mac != null) result[ipM.group(1)!] = mac;
      }
    }

    if (Platform.isWindows) {
      parse(await runCommand('arp', ['-a']) ?? '');
      return result;
    }
    if (Platform.isMacOS) {
      parse(await runCommand('arp', ['-an']) ?? '');
      return result;
    }
    // Android / Linux: /proc/net/arp (blocked on Android 10+ for apps),
    // then `ip neigh` (works on some devices / ROMs).
    try {
      final lines = await File('/proc/net/arp').readAsLines();
      for (final l in lines.skip(1)) {
        final cols = l.trim().split(RegExp(r'\s+'));
        if (cols.length >= 4 && cols[2] != '0x0') {
          final mac = normalizeMac(cols[3]);
          if (mac != null) result[cols[0]] = mac;
        }
      }
    } catch (_) {}
    if (result.isEmpty) {
      parse(await runCommand('ip', ['neigh', 'show']) ?? '');
    }
    return result;
  }
}

// =================================================================== NetBIOS

class NetbiosInfo {
  NetbiosInfo({this.name, this.workgroup, this.mac});
  final String? name;
  final String? workgroup;
  final String? mac;
}

class NetbiosService {
  static Uint8List _query(int id) {
    final b = BytesBuilder();
    b.add([id >> 8 & 0xFF, id & 0xFF, 0x00, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
    b.addByte(0x20);
    // '*' padded with NULs, first-level encoded
    final raw = [0x2A, ...List.filled(15, 0)];
    for (final c in raw) {
      b.addByte(0x41 + (c >> 4));
      b.addByte(0x41 + (c & 0x0F));
    }
    b.add([0x00, 0x00, 0x21, 0x00, 0x01]);
    return b.toBytes();
  }

  static NetbiosInfo? _parse(Uint8List d) {
    try {
      if (d.length < 57) return null;
      var off = 12;
      // skip the (possibly compressed) name
      if ((d[off] & 0xC0) == 0xC0) {
        off += 2;
      } else {
        while (off < d.length && d[off] != 0) {
          off += d[off] + 1;
        }
        off += 1;
      }
      off += 10; // type, class, ttl, rdlength
      final count = d[off];
      off += 1;
      String? name, group;
      for (var i = 0; i < count; i++) {
        if (off + 18 > d.length) break;
        final n = latin1.decode(d.sublist(off, off + 15)).trim();
        final suffix = d[off + 15];
        final flags = (d[off + 16] << 8) | d[off + 17];
        final isGroup = (flags & 0x8000) != 0;
        if (suffix == 0x00 && !isGroup) name ??= n;
        if (suffix == 0x00 && isGroup) group ??= n;
        off += 18;
      }
      String? mac;
      if (off + 6 <= d.length) {
        mac = normalizeMac(d
            .sublist(off, off + 6)
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':'));
      }
      if (name == null && mac == null) return null;
      return NetbiosInfo(name: name, workgroup: group, mac: mac);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, NetbiosInfo>> queryAll(List<String> ips,
      {Duration wait = const Duration(milliseconds: 1800)}) async {
    final results = <String, NetbiosInfo>{};
    if (ips.isEmpty) return results;
    RawDatagramSocket? sock;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock = s;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null) return;
        final info = _parse(dg.data);
        if (info != null) results[dg.address.address] = info;
      });
      final rnd = Random();
      for (var round = 0; round < 2; round++) {
        for (final ip in ips) {
          if (results.containsKey(ip)) continue;
          s.send(_query(rnd.nextInt(0xFFFF)), InternetAddress(ip), 137);
        }
        await Future<void>.delayed(Duration(milliseconds: wait.inMilliseconds ~/ 2));
      }
    } catch (_) {
    } finally {
      sock?.close();
    }
    return results;
  }
}

// ====================================================================== mDNS

class MdnsService {
  static Uint8List _ptrQuery(String ip, int id) {
    final b = BytesBuilder();
    b.add([id >> 8 & 0xFF, id & 0xFF, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    final labels = [...ip.split('.').reversed, 'in-addr', 'arpa'];
    for (final l in labels) {
      b.addByte(l.length);
      b.add(ascii.encode(l));
    }
    b.addByte(0);
    b.add([0x00, 0x0C, 0x80, 0x01]); // PTR, QU bit + IN
    return b.toBytes();
  }

  static (String, int) _readName(Uint8List d, int off) {
    final parts = <String>[];
    var jumped = false;
    var end = off;
    var guard = 0;
    while (off < d.length && guard++ < 64) {
      final len = d[off];
      if (len == 0) {
        if (!jumped) end = off + 1;
        break;
      }
      if ((len & 0xC0) == 0xC0) {
        if (off + 1 >= d.length) break;
        final ptr = ((len & 0x3F) << 8) | d[off + 1];
        if (!jumped) end = off + 2;
        jumped = true;
        off = ptr;
        continue;
      }
      if (off + 1 + len > d.length) break;
      parts.add(utf8.decode(d.sublist(off + 1, off + 1 + len),
          allowMalformed: true));
      off += len + 1;
    }
    return (parts.join('.'), end);
  }

  static String? _parsePtr(Uint8List d) {
    try {
      if (d.length < 12) return null;
      final qd = (d[4] << 8) | d[5];
      final an = (d[6] << 8) | d[7];
      final ar = (d[10] << 8) | d[11];
      var off = 12;
      for (var i = 0; i < qd; i++) {
        off = _readName(d, off).$2 + 4;
      }
      for (var i = 0; i < an + ar; i++) {
        final (_, after) = _readName(d, off);
        off = after;
        if (off + 10 > d.length) return null;
        final type = (d[off] << 8) | d[off + 1];
        final rdlen = (d[off + 8] << 8) | d[off + 9];
        off += 10;
        if (type == 12) return _readName(d, off).$1;
        off += rdlen;
      }
    } catch (_) {}
    return null;
  }

  /// Unicast reverse lookups sent straight to each host's mDNS responder.
  static Future<Map<String, String>> reverseAll(List<String> ips,
      {Duration wait = const Duration(milliseconds: 1800)}) async {
    final results = <String, String>{};
    if (ips.isEmpty) return results;
    RawDatagramSocket? sock;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock = s;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null) return;
        final name = _parsePtr(dg.data);
        if (name != null && name.isNotEmpty) results[dg.address.address] = name;
      });
      final rnd = Random();
      for (var round = 0; round < 2; round++) {
        for (final ip in ips) {
          if (results.containsKey(ip)) continue;
          s.send(_ptrQuery(ip, rnd.nextInt(0xFFFF)), InternetAddress(ip), 5353);
        }
        await Future<void>.delayed(Duration(milliseconds: wait.inMilliseconds ~/ 2));
      }
    } catch (_) {
    } finally {
      sock?.close();
    }
    return results;
  }
}

// ================================================================ SSDP/UPnP

class UpnpInfo {
  String? location;
  String? server;
  String? friendlyName;
  String? manufacturer;
  String? modelName;
}

class SsdpService {
  static Future<Map<String, UpnpInfo>> discover(
      {Duration wait = const Duration(seconds: 3)}) async {
    final results = <String, UpnpInfo>{};
    RawDatagramSocket? sock;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock = s;
      s.multicastHops = 4;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null) return;
        final text = utf8.decode(dg.data, allowMalformed: true);
        final info = results.putIfAbsent(dg.address.address, UpnpInfo.new);
        for (final line in const LineSplitter().convert(text)) {
          final i = line.indexOf(':');
          if (i <= 0) continue;
          final k = line.substring(0, i).trim().toLowerCase();
          final v = line.substring(i + 1).trim();
          if (k == 'location' && info.location == null) info.location = v;
          if (k == 'server' && info.server == null) info.server = v;
        }
      });
      const msg = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: ssdp:all\r\n\r\n';
      final target = InternetAddress('239.255.255.250');
      for (var i = 0; i < 2; i++) {
        s.send(utf8.encode(msg), target, 1900);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await Future<void>.delayed(wait);
    } catch (_) {
    } finally {
      sock?.close();
    }

    await runPool(results.values.where((i) => i.location != null), 8,
        (info) => _describe(info));
    return results;
  }

  static String? _tag(String xml, String tag) {
    final m = RegExp('<$tag>([^<]*)</$tag>', caseSensitive: false)
        .firstMatch(xml);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : _unescape(v);
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  static Future<void> _describe(UpnpInfo info) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..badCertificateCallback = (_, __, ___) => true;
    try {
      final req = await client
          .getUrl(Uri.parse(info.location!))
          .timeout(const Duration(seconds: 2));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));
      info.friendlyName = _tag(body, 'friendlyName');
      info.manufacturer = _tag(body, 'manufacturer');
      info.modelName = _tag(body, 'modelName');
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }
}

// ================================================================== Ping

class PingResult {
  PingResult(this.alive, {this.ttl, this.timeMs});
  final bool alive;
  final int? ttl;
  final double? timeMs;
}

class PingService {
  static Future<PingResult> ping(String host,
      {Duration timeout = const Duration(seconds: 1)}) async {
    final List<String> args;
    if (Platform.isWindows) {
      args = ['-n', '1', '-w', '${timeout.inMilliseconds}', host];
    } else if (Platform.isMacOS) {
      args = ['-c', '1', '-W', '${timeout.inMilliseconds}', host];
    } else {
      args = ['-c', '1', '-W', '${max(1, timeout.inSeconds)}', host];
    }
    final out = await runCommand('ping', args,
        timeout: timeout + const Duration(seconds: 2));
    if (out == null) return PingResult(false);
    final ttl = RegExp(r'ttl[=:]\s?(\d+)', caseSensitive: false).firstMatch(out);
    if (ttl == null) return PingResult(false);
    final t = RegExp(r'[=<]\s?([\d.,]+)\s?ms', caseSensitive: false)
        .firstMatch(out);
    return PingResult(
      true,
      ttl: int.tryParse(ttl.group(1)!),
      timeMs: double.tryParse((t?.group(1) ?? '').replaceAll(',', '.')),
    );
  }
}

// ========================================================== Wake-on-LAN

class WakeOnLan {
  static Future<bool> send(String mac, {String? broadcast}) async {
    final bytes = macBytes(mac);
    if (bytes == null) return false;
    final packet = <int>[...List.filled(6, 0xFF)];
    for (var i = 0; i < 16; i++) {
      packet.addAll(bytes);
    }
    RawDatagramSocket? sock;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock = s;
      s.broadcastEnabled = true;
      final targets = {'255.255.255.255', if (broadcast != null) broadcast};
      for (final t in targets) {
        for (final port in [9, 7]) {
          s.send(packet, InternetAddress(t), port);
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      sock?.close();
    }
  }
}
