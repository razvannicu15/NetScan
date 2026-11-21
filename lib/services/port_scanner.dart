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

  static Future<void> scan(
    String ip,
    List<int> ports, {
    required void Function(int port) onOpen,
    required void Function(int done, int total) onProgress,
    CancelToken? cancel,
    int concurrency = 200,
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    var done = 0;
    var lastReport = DateTime.now();
    await runPool<int>(ports, concurrency, (port) async {
      final r = await probe(ip, port, timeout);
      if (r == ProbeResult.open) onOpen(port);
      done++;
      final now = DateTime.now();
      if (now.difference(lastReport).inMilliseconds > 80 ||
          done == ports.length) {
        lastReport = now;
        onProgress(done, ports.length);
      }
    }, cancel: cancel);
    onProgress(done, ports.length);
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
