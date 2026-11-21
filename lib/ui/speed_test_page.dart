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
            AspectRatio(
              aspectRatio: 1.35,
              child: CustomPaint(
                painter: _GaugePainter(
                  value: gaugeValue,
                  color: gaugeColor,
                  track: cs.surfaceContainerHighest,
                  tick: cs.onSurfaceVariant,
                ),
                child: Align(
                  alignment: const Alignment(0, 0.25),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmt(gaugeValue == 0 && !_running ? null : gaugeValue),
                        style: tt.displayLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text('Mbps',
                          style: tt.titleMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text(_phaseText,
                          style: tt.bodyMedium?.copyWith(color: gaugeColor)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ResultCard(
                  icon: Icons.arrow_downward_rounded,
                  label: tr('Descărcare', 'Download'),
                  value: _fmt(_test.downloadMbps),
                  unit: 'Mbps',
                  active: _test.phase == SpeedPhase.download,
                ),
                const SizedBox(width: 8),
                _ResultCard(
                  icon: Icons.arrow_upward_rounded,
                  label: tr('Încărcare', 'Upload'),
                  value: _fmt(_test.uploadMbps),
                  unit: 'Mbps',
                  active: _test.phase == SpeedPhase.upload,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ResultCard(
                  icon: Icons.timer_outlined,
                  label: 'Ping',
                  value: _fmt(_test.pingMs),
                  unit: 'ms',
                  active: _test.phase == SpeedPhase.latency,
                ),
                const SizedBox(width: 8),
                _ResultCard(
                  icon: Icons.ssid_chart,
                  label: 'Jitter',
                  value: _fmt(_test.jitterMs),
                  unit: 'ms',
                  active: false,
                ),
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

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.active,
  });
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(label,
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: tt.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
                Text(unit,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
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
  });
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
    final r = min(size.width / 2, size.height / 1.15) - 18;
    final c = Offset(size.width / 2, r + 18);
    final rect = Rect.fromCircle(center: c, radius: r);
    final stroke = r * 0.13;

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
      final p = c + Offset(cos(a), sin(a)) * (r - stroke * 1.4);
      final tp = TextPainter(
        text: TextSpan(
            text: '$m', style: TextStyle(color: tick, fontSize: r * 0.075)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color;
}
