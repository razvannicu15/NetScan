import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../services/live_monitor.dart';
import 'widgets.dart';

/// Full-screen signal meter with beeps: walk around to find the best spot.
class SignalFinderPage extends StatefulWidget {
  const SignalFinderPage({super.key});

  @override
  State<SignalFinderPage> createState() => _SignalFinderPageState();
}

class _SignalFinderPageState extends State<SignalFinderPage> {
  Timer? _read;
  Timer? _beep;
  double? _smooth; // EMA of RSSI
  int? _min;
  int? _max;
  String? _ssid;
  bool _sound = true;
  final List<(DateTime, double)> _recent = [];

  @override
  void initState() {
    super.initState();
    _tick();
    _read = Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());
    _scheduleBeep();
  }

  Future<void> _tick() async {
    final s = await LiveWifi.read();
    if (!mounted || s?.rssi == null) return;
    final r = s!.rssi!;
    setState(() {
      _ssid = s.ssid;
      _smooth = _smooth == null ? r.toDouble() : _smooth! * 0.6 + r * 0.4;
      _min = _min == null ? r : min(_min!, r);
      _max = _max == null ? r : max(_max!, r);
      final now = DateTime.now();
      _recent.add((now, r.toDouble()));
      _recent.removeWhere((p) => now.difference(p.$1).inSeconds > 6);
    });
  }

  int get _percent =>
      _smooth == null ? 0 : (2 * (_smooth! + 100)).clamp(0, 100).round();

  void _scheduleBeep() {
    _beep?.cancel();
    // stronger signal → faster beeps (250 ms … 1300 ms)
    final ms = (1300 - _percent * 10.5).clamp(250, 1300).round();
    _beep = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      if (_sound && _smooth != null) {
        LiveWifi.tone((_percent / 11.2).ceil().clamp(1, 9).toInt());
        HapticFeedback.selectionClick();
      }
      _scheduleBeep();
    });
  }

  @override
  void dispose() {
    _read?.cancel();
    _beep?.cancel();
    super.dispose();
  }

  Color _color(ColorScheme cs) => _percent >= 80
      ? Colors.green.shade600
      : _percent >= 55
          ? Colors.lightGreen.shade700
          : _percent >= 35
              ? Colors.orange.shade700
              : cs.error;

  String get _label => _percent >= 80
      ? tr('Excelent', 'Excellent')
      : _percent >= 55
          ? tr('Bun', 'Good')
          : _percent >= 35
              ? tr('Slab', 'Weak')
              : tr('Foarte slab', 'Very weak');

  /// +1 rising, -1 falling, 0 stable (last ~5 s).
  int get _trend {
    if (_recent.length < 6) return 0;
    final first = _recent.take(3).map((e) => e.$2).reduce((a, b) => a + b) / 3;
    final last = _recent.skip(_recent.length - 3).map((e) => e.$2).reduce((a, b) => a + b) / 3;
    if (last - first >= 3) return 1;
    if (first - last >= 3) return -1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = _color(cs);
    final trend = _trend;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Caută semnal', 'Signal finder')),
        actions: [
          IconButton(
            tooltip: _sound ? tr('Fără sunet', 'Mute') : tr('Cu sunet', 'Sound on'),
            icon: Icon(_sound ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() => _sound = !_sound),
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.withValues(alpha: 0.16), Theme.of(context).scaffoldBackgroundColor],
          ),
        ),
        child: _smooth == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    tr('Conectează-te la o rețea Wi-Fi ca să măsori semnalul.',
                        'Connect to a Wi-Fi network to measure the signal.'),
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge,
                  ),
                ),
              )
            : MaxWidth(
                width: 520,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  children: [
                    if (_ssid != null)
                      Text(_ssid!,
                          textAlign: TextAlign.center,
                          style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    AspectRatio(
                      aspectRatio: 1,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: _percent / 100),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => CustomPaint(
                          painter: _RingPainter(
                            value: v,
                            color: c,
                            track: cs.surfaceContainerHighest,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_smooth!.round()}',
                                  style: tt.displayLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: c,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text('dBm', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('$_label · ${_percent}%',
                                        style: tt.titleMedium?.copyWith(color: c, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 6),
                                    Icon(
                                      trend > 0
                                          ? Icons.trending_up
                                          : trend < 0
                                              ? Icons.trending_down
                                              : Icons.trending_flat,
                                      color: trend > 0
                                          ? Colors.green.shade600
                                          : trend < 0
                                              ? cs.error
                                              : cs.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TableCard(margin: EdgeInsets.zero, children: [
                      InfoRow(Icons.arrow_upward, tr('Cel mai bun', 'Best'), '$_max dBm', copy: false),
                      InfoRow(Icons.arrow_downward, tr('Cel mai slab', 'Worst'), '$_min dBm', copy: false),
                    ]),
                    const SizedBox(height: 16),
                    Text(
                      tr('Mergi încet prin casă. Cu cât bipurile sunt mai rapide și mai ascuțite, cu atât semnalul e mai bun. Peste -60 dBm e foarte bine pentru streaming și jocuri.',
                          'Walk slowly around. Faster, higher-pitched beeps mean a better signal. Above -60 dBm is great for streaming and gaming.'),
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _min = null;
                        _max = null;
                      }),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(tr('Resetează min / max', 'Reset min / max')),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) / 2 - 16;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    const start = 135 * pi / 180;
    const sweep = 270 * pi / 180;
    final stroke = r * 0.11;
    canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);
    if (value > 0) {
      canvas.drawArc(
          rect,
          start,
          sweep * value,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value || old.color != color;
}
