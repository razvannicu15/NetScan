import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/i18n.dart';

class ChartSeries {
  ChartSeries({
    required this.color,
    required this.points,
    this.width = 2,
    this.fill = false,
  });

  final Color color;

  /// (time, value); use double.nan for a gap (e.g. lost ping).
  final List<(DateTime, double)> points;
  final double width;
  final bool fill;
}

/// Time-series chart that scrolls smoothly every frame.
class LiveChart extends StatefulWidget {
  const LiveChart({
    super.key,
    required this.series,
    required this.minY,
    required this.maxY,
    required this.yStep,
    this.windowSec = 60,
    this.yFormat,
    this.aspectRatio = 1.6,
  });

  final List<ChartSeries> series;
  final double minY;
  final double maxY;
  final double yStep;
  final int windowSec;
  final String Function(double v)? yFormat;
  final double aspectRatio;

  @override
  State<LiveChart> createState() => _LiveChartState();
}

class _LiveChartState extends State<LiveChart> with SingleTickerProviderStateMixin {
  final _clock = ValueNotifier<DateTime>(DateTime.now());
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (elapsed - _last >= const Duration(milliseconds: 33)) {
        _last = elapsed;
        _clock.value = DateTime.now();
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: CustomPaint(
        painter: _LivePainter(
          clock: _clock,
          series: widget.series,
          minY: widget.minY,
          maxY: widget.maxY,
          yStep: widget.yStep,
          windowSec: widget.windowSec,
          yFormat: widget.yFormat ?? (v) => v.round().toString(),
          grid: cs.outlineVariant.withValues(alpha: 0.5),
          text: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LivePainter extends CustomPainter {
  _LivePainter({
    required this.clock,
    required this.series,
    required this.minY,
    required this.maxY,
    required this.yStep,
    required this.windowSec,
    required this.yFormat,
    required this.grid,
    required this.text,
  }) : super(repaint: clock);

  final ValueNotifier<DateTime> clock;
  final List<ChartSeries> series;
  final double minY;
  final double maxY;
  final double yStep;
  final int windowSec;
  final String Function(double) yFormat;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(36, 8, size.width - 6, size.height - 22);
    final now = clock.value;
    double x(DateTime t) =>
        plot.right - now.difference(t).inMicroseconds / 1e6 / windowSec * plot.width;
    double y(double v) =>
        plot.bottom - ((v.clamp(minY, maxY).toDouble() - minY) / (maxY - minY)) * plot.height;

    // grid + y labels
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = minY; v <= maxY + 0.001; v += yStep) {
      final yy = y(v);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gp);
      final tp = TextPainter(
        text: TextSpan(text: yFormat(v), style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plot.left - tp.width - 6, yy - tp.height / 2));
    }
    // x labels
    final step = windowSec >= 60 ? 15 : 10;
    for (var s = 0; s <= windowSec; s += step) {
      final tx = plot.right - s / windowSec * plot.width;
      final tp = TextPainter(
        text: TextSpan(
            text: s == 0 ? tr('acum', 'now') : '-${s}s',
            style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (tx - tp.width / 2).clamp(plot.left, plot.right - tp.width).toDouble();
      tp.paint(canvas, Offset(lx, plot.bottom + 6));
    }

    canvas.save();
    canvas.clipRect(plot);
    for (final s in series) {
      final pts = s.points
          .where((p) => now.difference(p.$1).inMilliseconds <= (windowSec + 2) * 1000)
          .toList();
      if (pts.isEmpty) continue;

      // split into continuous segments (NaN = gap)
      final segments = <List<Offset>>[];
      var cur = <Offset>[];
      for (final p in pts) {
        if (p.$2.isNaN) {
          if (cur.isNotEmpty) segments.add(cur);
          cur = <Offset>[];
          // lost sample marker
          canvas.drawCircle(Offset(x(p.$1), plot.top + 4), 2.5, Paint()..color = s.color.withValues(alpha: 0.6));
          continue;
        }
        cur.add(Offset(x(p.$1), y(p.$2)));
      }
      if (cur.isNotEmpty) {
        cur.add(Offset(plot.right, cur.last.dy)); // extend to "now"
        segments.add(cur);
      }

      for (final seg in segments) {
        final path = Path()..moveTo(seg.first.dx, seg.first.dy);
        for (var i = 1; i < seg.length; i++) {
          final a = seg[i - 1], b = seg[i];
          final mx = (a.dx + b.dx) / 2;
          path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
        }
        if (s.fill) {
          final area = Path.from(path)
            ..lineTo(seg.last.dx, plot.bottom)
            ..lineTo(seg.first.dx, plot.bottom)
            ..close();
          canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [s.color.withValues(alpha: 0.28), s.color.withValues(alpha: 0.02)],
              ).createShader(plot),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      final last = segments.isEmpty ? null : segments.last.last;
      if (last != null) {
        canvas.drawCircle(last, s.width + 1.5, Paint()..color = s.color);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LivePainter old) => true;
}
