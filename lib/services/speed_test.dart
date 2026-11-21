import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/utils.dart';

enum SpeedPhase { idle, latency, download, upload, done, error }

/// Internet speed test against Cloudflare's public speed endpoints.
class SpeedTest {
  static const _base = 'https://speed.cloudflare.com';

  SpeedPhase phase = SpeedPhase.idle;
  double? pingMs;
  double? jitterMs;
  double? downloadMbps;
  double? uploadMbps;
  double liveMbps = 0;
  String? error;

  CancelToken? _cancel;
  final List<HttpClient> _clients = [];

  void cancel() {
    _cancel?.cancel();
    for (final c in _clients) {
      c.close(force: true);
    }
    _clients.clear();
  }

  HttpClient _client() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'NetScan';
    _clients.add(c);
    return c;
  }

  Future<void> run(void Function() onUpdate) async {
    final cancel = _cancel = CancelToken();
    pingMs = jitterMs = downloadMbps = uploadMbps = null;
    error = null;
    liveMbps = 0;
    try {
      phase = SpeedPhase.latency;
      onUpdate();
      await _latency(cancel);
      if (cancel.isCancelled) return;
      onUpdate();

      phase = SpeedPhase.download;
      onUpdate();
      downloadMbps = await _download(cancel, onUpdate);
      if (cancel.isCancelled) return;

      phase = SpeedPhase.upload;
      liveMbps = 0;
      onUpdate();
      uploadMbps = await _upload(cancel, onUpdate);
      if (cancel.isCancelled) return;

      phase = SpeedPhase.done;
    } catch (e) {
      if (!cancel.isCancelled) {
        phase = SpeedPhase.error;
        error = e.toString();
      }
    } finally {
      for (final c in _clients) {
        c.close(force: true);
      }
      _clients.clear();
      if (cancel.isCancelled) phase = SpeedPhase.idle;
      onUpdate();
    }
  }

  Future<void> _latency(CancelToken cancel) async {
    final client = _client();
    final samples = <double>[];
    for (var i = 0; i < 9 && !cancel.isCancelled; i++) {
      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse('$_base/__down?bytes=0'));
      final res = await req.close();
      await res.drain<void>();
      sw.stop();
      if (i > 0) samples.add(sw.elapsedMicroseconds / 1000); // skip warm-up
    }
    if (samples.isEmpty) return;
    samples.sort();
    pingMs = samples[samples.length ~/ 2];
    var j = 0.0;
    for (var i = 1; i < samples.length; i++) {
      j += (samples[i] - samples[i - 1]).abs();
    }
    jitterMs = samples.length > 1 ? j / (samples.length - 1) : 0;
  }

  /// Runs [worker] on [streams] parallel connections for [duration] and
  /// returns the average throughput in Mbit/s (first 1.5 s ignored).
  Future<double> _measure(
    CancelToken cancel,
    void Function() onUpdate,
    Future<void> Function(HttpClient c, void Function(int) count, bool Function() stop)
        worker, {
    int streams = 4,
    Duration duration = const Duration(seconds: 10),
  }) async {
    var total = 0;
    var warmBytes = 0;
    Duration? warmAt;
    final sw = Stopwatch()..start();
    const warm = Duration(milliseconds: 1500);
    bool stop() => cancel.isCancelled || sw.elapsed >= duration;
    void count(int n) {
      total += n;
      if (warmAt == null && sw.elapsed >= warm) {
        warmAt = sw.elapsed;
        warmBytes = total;
      }
    }

    final ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final w = warmAt;
      final secs = w == null
          ? sw.elapsedMicroseconds / 1e6
          : (sw.elapsed - w).inMicroseconds / 1e6;
      final bytes = w == null ? total : total - warmBytes;
      if (secs > 0.2) liveMbps = bytes * 8 / secs / 1e6;
      onUpdate();
    });

    final clients = List.generate(streams, (_) => _client());
    final killer = Timer(duration + const Duration(seconds: 2), () {
      for (final c in clients) {
        c.close(force: true);
      }
    });
    await Future.wait([
      for (final c in clients)
        () async {
          while (!stop()) {
            try {
              await worker(c, count, stop);
            } catch (_) {
              if (stop()) break;
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
          }
        }(),
    ]);
    killer.cancel();
    ticker.cancel();
    for (final c in clients) {
      c.close(force: true);
    }
    sw.stop();
    final w = warmAt;
    final secs = w == null
        ? sw.elapsedMicroseconds / 1e6
        : (sw.elapsed - w).inMicroseconds / 1e6;
    final bytes = w == null ? total : total - warmBytes;
    return secs <= 0 ? 0 : bytes * 8 / secs / 1e6;
  }

  Future<double> _download(CancelToken cancel, void Function() onUpdate) {
    return _measure(cancel, onUpdate, (c, count, stop) async {
      final req = await c.getUrl(Uri.parse('$_base/__down?bytes=50000000'));
      final res = await req.close();
      final done = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = res.listen(
        (chunk) {
          count(chunk.length);
          if (stop()) {
            sub.cancel();
            if (!done.isCompleted) done.complete();
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
    });
  }

  Future<double> _upload(CancelToken cancel, void Function() onUpdate) {
    final rnd = Random();
    final chunk = Uint8List(64 * 1024);
    for (var i = 0; i < chunk.length; i++) {
      chunk[i] = rnd.nextInt(256);
    }
    const size = 8 * 1024 * 1024;
    return _measure(cancel, onUpdate, (c, count, stop) async {
      final req = await c.postUrl(Uri.parse('$_base/__up'));
      req.contentLength = size;
      req.headers.contentType = ContentType.binary;
      var sent = 0;
      while (sent < size) {
        if (stop()) {
          // abort the request; the connection is discarded
          req.abort();
          return;
        }
        final n = min(chunk.length, size - sent);
        req.add(n == chunk.length ? chunk : chunk.sublist(0, n));
        await req.flush();
        sent += n;
        count(n);
      }
      final res = await req.close();
      await res.drain<void>();
    });
  }
}
