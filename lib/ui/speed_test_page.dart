import 'dart:math';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/speed_test.dart';
import 'widgets.dart';

class SpeedTestPage extends StatefulWidget {
  const SpeedTestPage({super.key});

  @override
  State<SpeedTestPage> createState() => _SpeedTestPageState();
}

class _SpeedTestPageState extends State<SpeedTestPage> {
  final _test = SpeedTest();

  bool get _running =>
      _test.phase == SpeedPhase.latency ||
      _test.phase == SpeedPhase.download ||
      _test.phase == SpeedPhase.upload;

  void _start() {
    _test.run(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _test.cancel();
    super.dispose();
  }

  String get _phaseText => switch (_test.phase) {
        SpeedPhase.idle => tr('Gata de test', 'Ready'),
        SpeedPhase.latency => tr('Măsor latența…', 'Measuring latency…'),
        SpeedPhase.download => tr('Testez descărcarea…', 'Testing download…'),
        SpeedPhase.upload => tr('Testez încărcarea…', 'Testing upload…'),
        SpeedPhase.done => tr('Test finalizat', 'Test complete'),
        SpeedPhase.error =>
          tr('Eroare: nu pot contacta serverul', 'Error: cannot reach the server'),
      };

  Widget _resultRow(BuildContext context, IconData icon, String label,
      double? value, String unit, bool active) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      color: active ? cs.primaryContainer.withValues(alpha: 0.55) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          ),
          if (active && value == null)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Text(_fmt(value),
                style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          SizedBox(
            width: 38,
            child: Text(unit,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  String _fmt(double? v) => v == null
      ? '—'
      : v >= 100
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final gaugeValue = switch (_test.phase) {
      SpeedPhase.download || SpeedPhase.upload => _test.liveMbps,
      SpeedPhase.done => _test.downloadMbps ?? 0.0,
      _ => 0.0,
    };
    final gaugeColor =
        _test.phase == SpeedPhase.upload ? cs.tertiary : cs.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Speed test')),
      body: MaxWidth(
        width: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            LayoutBuilder(builder: (context, box) {
              final w = min(box.maxWidth, 420.0);
              final r = w * 0.40;
              final stroke = r * 0.12;
              final cy = stroke + r;
              final h = cy + r * 0.5 + stroke + 4;
              final shown = gaugeValue == 0 && !_running ? null : gaugeValue;
              return Center(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GaugePainter(
                            value: gaugeValue,
                            color: gaugeColor,
                            track: cs.surfaceContainerHighest,
                            tick: cs.onSurfaceVariant,
                            center: Offset(w / 2, cy),
                            radius: r,
                            stroke: stroke,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: cy - r * 0.42,
                        child: Column(
                          children: [
                            SizedBox(
                              width: r * 1.2,
                              height: r * 0.48,
                              child: FittedBox(
                                child: Text(
                                  _fmt(shown),
                                  style: TextStyle(
                                    fontSize: r * 0.40,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                    color: cs.onSurface,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Mbps',
                                style: tt.titleMedium
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(_phaseText,
                textAlign: TextAlign.center,
                style: tt.titleSmall?.copyWith(color: gaugeColor)),
            const SizedBox(height: 16),
            TableCard(
              margin: EdgeInsets.zero,
              children: [
                _resultRow(context, Icons.arrow_downward_rounded,
                    tr('Descărcare', 'Download'), _test.downloadMbps, 'Mbps',
                    _test.phase == SpeedPhase.download),
                _resultRow(context, Icons.arrow_upward_rounded,
                    tr('Încărcare', 'Upload'), _test.uploadMbps, 'Mbps',
                    _test.phase == SpeedPhase.upload),
                _resultRow(context, Icons.timer_outlined, 'Ping', _test.pingMs,
                    'ms', _test.phase == SpeedPhase.latency),
                _resultRow(context, Icons.ssid_chart, 'Jitter', _test.jitterMs,
                    'ms', false),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _running
                    ? () {
                        _test.cancel();
                        setState(() {});
                      }
                    : _start,
                icon: Icon(_running ? Icons.stop_rounded : Icons.speed),
                label: Text(_running
                    ? tr('Oprește', 'Stop')
                    : _test.phase == SpeedPhase.done
                        ? tr('Testează din nou', 'Test again')
                        : tr('Pornește testul', 'Start test')),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('Server: Cloudflare (cel mai apropiat). Testul consumă aprox. 100–500 MB pe conexiuni rapide.',
                  'Server: Cloudflare (nearest). The test uses about 100–500 MB on fast connections.'),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 240° gauge with a logarithmic scale 0–1000 Mbps.
class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.color,
    required this.track,
    required this.tick,
    required this.center,
    required this.radius,
    required this.stroke,
  });
  final Offset center;
  final double radius;
  final double stroke;
  final double value;
  final Color color;
  final Color track;
  final Color tick;

  static const _marks = [0, 5, 10, 50, 100, 250, 500, 1000];
  static const _start = 150 * pi / 180;
  static const _sweep = 240 * pi / 180;

  double _frac(double v) {
    if (v <= 0) return 0;
    return (log(1 + v) / log(1001)).clamp(0.0, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius;
    final c = center;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawArc(
        rect,
        _start,
        _sweep,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);

    final f = _frac(value);
    if (f > 0) {
      canvas.drawArc(
          rect,
          _start,
          _sweep * f,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round);
    }

    for (final m in _marks) {
      final a = _start + _sweep * _frac(m.toDouble());
      final p = c + Offset(cos(a), sin(a)) * (r - stroke * 1.9);
      final tp = TextPainter(
        text: TextSpan(
            text: '$m', style: TextStyle(color: tick, fontSize: max(10, r * 0.075))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color || old.radius != radius;
}
