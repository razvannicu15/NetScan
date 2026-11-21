import 'dart:async';
import 'dart:io';

import '../core/utils.dart';
import 'protocols.dart';

class Hop {
  Hop(this.ttl);
  final int ttl;
  String? ip;
  String? host;
  double? ms;
  bool reached = false;
}

/// Traceroute built on the system `ping` with an increasing TTL
/// (no raw sockets needed, works on Android and Windows).
class Traceroute {
  static final _ip = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})');
  static final _reply = RegExp(r'ttl[=:]\s?\d+', caseSensitive: false);

  static Future<String?> resolve(String host) async {
    if (isValidIp(host)) return host;
    try {
      final r = await InternetAddress.lookup(host, type: InternetAddressType.IPv4)
          .timeout(const Duration(seconds: 5));
      return r.isEmpty ? null : r.first.address;
    } catch (_) {
      return null;
    }
  }

  static List<String> _args(String target, int ttl) {
    if (Platform.isWindows) {
      return ['-n', '1', '-i', '$ttl', '-w', '1000', target];
    }
    if (Platform.isMacOS) {
      return ['-c', '1', '-m', '$ttl', '-W', '1000', target];
    }
    return ['-c', '1', '-t', '$ttl', '-W', '1', target];
  }

  /// Returns (hop ip, reached target).
  static Future<(String?, bool)> _probe(String target, int ttl) async {
    final out = await runCommand('ping', _args(target, ttl),
        timeout: const Duration(seconds: 4));
    if (out == null) return (null, false);
    if (_reply.hasMatch(out)) return (target, true);
    for (final m in _ip.allMatches(out)) {
      final ip = m.group(1)!;
      if (ip != target && isValidIp(ip)) return (ip, false);
    }
    return (null, false);
  }

  static Future<void> run(
    String target, {
    required void Function(Hop hop) onHop,
    CancelToken? cancel,
    int maxHops = 30,
  }) async {
    for (var ttl = 1; ttl <= maxHops; ttl++) {
      if (cancel?.isCancelled ?? false) return;
      final hop = Hop(ttl);
      final sw = Stopwatch()..start();
      final (ip, reached) = await _probe(target, ttl);
      sw.stop();
      hop.ip = ip;
      hop.reached = reached;
      if (ip != null) {
        final p = await PingService.ping(ip, timeout: const Duration(seconds: 1));
        hop.ms = p.timeMs ?? (p.alive ? sw.elapsedMilliseconds.toDouble() : null);
        try {
          final r = await InternetAddress(ip)
              .reverse()
              .timeout(const Duration(milliseconds: 1200));
          if (r.host != ip) hop.host = r.host;
        } catch (_) {}
      }
      if (cancel?.isCancelled ?? false) return;
      onHop(hop);
      if (reached) return;
    }
  }
}
