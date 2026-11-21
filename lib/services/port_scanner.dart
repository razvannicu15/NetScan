import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/ports.dart';
import '../core/utils.dart';

enum ProbeResult { open, closed, filtered }

class PortScanner {
  static const _refused = {111, 61, 10061, 146};

  /// TCP connect probe. "closed" (RST) still proves the host is alive.
  static Future<ProbeResult> probe(String ip, int port, Duration timeout) async {
    try {
      final s = await Socket.connect(ip, port, timeout: timeout);
      s.destroy();
      return ProbeResult.open;
    } on SocketException catch (e) {
      final code = e.osError?.errorCode;
      if (code != null && _refused.contains(code)) return ProbeResult.closed;
      final msg = (e.osError?.message ?? e.message).toLowerCase();
      if (msg.contains('refused')) return ProbeResult.closed;
      return ProbeResult.filtered;
    } catch (_) {
      return ProbeResult.filtered;
    }
  }

  /// Scans [ports]. Ports that time out are re-checked slowly with a longer
  /// timeout, because small devices (routers, cameras, IoT) silently drop
  /// connections when they receive too many at once.
  static Future<void> scan(
    String ip,
    List<int> ports, {
    required void Function(int port) onOpen,
    required void Function(int done, int total) onProgress,
    CancelToken? cancel,
    int concurrency = 64,
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    var done = 0;
    var total = ports.length;
    var lastReport = DateTime.now();
    final found = <int>{};
    final filtered = <int>[];
    var closed = 0;

    void report() {
      final now = DateTime.now();
      if (now.difference(lastReport).inMilliseconds > 80 || done == total) {
        lastReport = now;
        onProgress(done, total);
      }
    }

    await runPool<int>(ports, concurrency, (port) async {
      final r = await probe(ip, port, timeout);
      if (r == ProbeResult.open) {
        found.add(port);
        onOpen(port);
      } else if (r == ProbeResult.closed) {
        closed++;
      } else {
        filtered.add(port);
      }
      done++;
      report();
    }, cancel: cancel);

    if (cancel?.isCancelled ?? false) return;

    // Second pass: slow and patient re-check of timed-out ports.
    // Only hosts that actively answer (RST) for closed ports are worth a
    // re-check: there a timeout means a dropped connection, not a firewall.
    final important = {...kServiceNames.keys, ...kHttpPorts, ...kHttpsPorts};
    final retry = closed == 0
        ? <int>[]
        : (filtered.length <= 300 || closed > filtered.length)
            ? filtered
            : filtered.where(important.contains).toList();
    if (retry.isEmpty) {
      onProgress(done, total);
      return;
    }
    retry.sort();
    total += retry.length;
    final slow = Duration(
        milliseconds: (timeout.inMilliseconds * 3).clamp(1500, 4000).toInt());
    await runPool<int>(retry, 8, (port) async {
      var r = await probe(ip, port, slow);
      if (r == ProbeResult.filtered && important.contains(port)) {
        r = await probe(ip, port, slow);
      }
      if (r == ProbeResult.open && found.add(port)) onOpen(port);
      done++;
      report();
    }, cancel: cancel);
    onProgress(done, total);
  }

  /// Reads a service banner (SSH/FTP/SMTP greet, HTTP Server header).
  static Future<String?> grabBanner(String ip, int port) async {
    Socket? s;
    try {
      if (kHttpsPorts.contains(port)) {
        final sec = await SecureSocket.connect(ip, port,
            timeout: const Duration(seconds: 2),
            onBadCertificate: (_) => true);
        s = sec;
        final cert = sec.peerCertificate;
        sec.write('HEAD / HTTP/1.0\r\nHost: $ip\r\n\r\n');
        final text = await _read(sec, const Duration(milliseconds: 1500));
        final server = _httpSummary(text);
        final cn = cert == null
            ? null
            : RegExp(r'CN=([^,/]+)').firstMatch(cert.subject)?.group(1);
        return [server, if (cn != null) 'cert: $cn']
            .whereType<String>()
            .join(' · ');
      }
      s = await Socket.connect(ip, port,
          timeout: const Duration(milliseconds: 1500));
      if (kHttpPorts.contains(port)) {
        s.write('HEAD / HTTP/1.0\r\nHost: $ip\r\nUser-Agent: NetScan\r\n\r\n');
        return _httpSummary(await _read(s, const Duration(milliseconds: 1500)));
      }
      final text = await _read(s, const Duration(milliseconds: 1200));
      final clean = text
          .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '')
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      return clean.isEmpty
          ? null
          : (clean.length > 120 ? '${clean.substring(0, 120)}…' : clean);
    } catch (_) {
      return null;
    } finally {
      s?.destroy();
    }
  }

  static String? _httpSummary(String text) {
    if (text.isEmpty) return null;
    final lines = const LineSplitter().convert(text);
    final status = lines.first.trim();
    final server = lines
        .firstWhere((l) => l.toLowerCase().startsWith('server:'),
            orElse: () => '')
        .replaceFirst(RegExp('server:', caseSensitive: false), '')
        .trim();
    final code = RegExp(r'HTTP/[\d.]+\s+(\d{3})').firstMatch(status)?.group(1);
    if (!status.startsWith('HTTP')) return null;
    return [if (code != null) 'HTTP $code', if (server.isNotEmpty) server]
        .join(' · ');
  }

  static Future<String> _read(Socket s, Duration wait) async {
    final buf = BytesBuilder();
    final done = Completer<void>();
    final sub = s.listen(
      (data) {
        buf.add(data);
        if (buf.length > 4096 && !done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future.timeout(wait, onTimeout: () {});
    await sub.cancel();
    return latin1.decode(buf.toBytes(), allowInvalid: true);
  }
}
