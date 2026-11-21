import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/utils.dart';
import '../services/traceroute.dart';
import 'widgets.dart';

class TraceroutePage extends StatefulWidget {
  const TraceroutePage({super.key, this.initialHost});
  final String? initialHost;

  @override
  State<TraceroutePage> createState() => _TraceroutePageState();
}

class _TraceroutePageState extends State<TraceroutePage> {
  late final _host =
      TextEditingController(text: widget.initialHost ?? 'google.com');
  final List<Hop> _hops = [];
  bool _running = false;
  String? _target;
  String? _message;
  CancelToken? _cancel;

  Future<void> _start() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _hops.clear();
      _running = true;
      _message = tr('Rezolv adresa…', 'Resolving…');
      _target = null;
    });
    final target = await Traceroute.resolve(host);
    if (!mounted) return;
    if (target == null) {
      setState(() {
        _running = false;
        _message = tr('Nu pot rezolva „$host”', 'Cannot resolve “$host”');
      });
      return;
    }
    final cancel = _cancel = CancelToken();
    setState(() {
      _target = target;
      _message = null;
    });
    await Traceroute.run(
      target,
      cancel: cancel,
      onHop: (h) {
        if (mounted) setState(() => _hops.add(h));
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      final reached = _hops.isNotEmpty && _hops.last.reached;
      _message = cancel.isCancelled
          ? tr('Oprit', 'Stopped')
          : reached
              ? tr('Destinație atinsă în ${_hops.length} salturi',
                  'Destination reached in ${_hops.length} hops')
              : tr('Destinația nu a răspuns', 'Destination did not respond');
    });
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Traceroute')),
      body: MaxWidth(
        width: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextField(
              controller: _host,
              enabled: !_running,
              decoration: InputDecoration(
                labelText: tr('Destinație', 'Destination'),
                hintText: 'google.com / 8.8.8.8',
                prefixIcon: const Icon(Icons.route_outlined),
              ),
              onSubmitted: (_) => _start(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? () => _cancel?.cancel() : _start,
              icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(_running ? tr('Oprește', 'Stop') : 'Start'),
            ),
            const SizedBox(height: 12),
            if (_target != null)
              Text('→ $_target',
                  style: tt.titleSmall?.copyWith(color: cs.primary)),
            if (_running) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 8),
            if (_hops.isNotEmpty)
              TableCard(
                margin: EdgeInsets.zero,
                header: _HopRow.cols,
                children: [for (final h in _hops) _HopRow(hop: h)],
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_message!,
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}

class _HopRow extends StatelessWidget {
  const _HopRow({required this.hop});
  final Hop hop;

  static List<TableCol> get cols => [
        const TableCol('#', width: 36),
        TableCol(tr('Gazdă', 'Host'), flex: 5),
        const TableCol('IP', flex: 4),
        TableCol(tr('Timp', 'Time'), width: 64, align: TextAlign.right),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = hop;
    final ms = h.ms;
    final color = ms == null
        ? cs.onSurfaceVariant
        : ms < 30
            ? Colors.green.shade600
            : ms < 100
                ? Colors.orange.shade700
                : cs.error;
    return TableDataRow(
      cols: cols,
      onLongPress: h.ip == null ? null : () => copyText(context, h.ip!),
      cells: [
        CellText('${h.ttl}', muted: !h.reached, bold: h.reached,
            color: h.reached ? cs.primary : null),
        CellText(h.ip == null ? tr('fără răspuns', 'no reply') : (h.host ?? '—'),
            muted: h.ip == null || h.host == null),
        CellText(h.ip ?? '* * *', muted: h.ip == null),
        CellText(ms == null ? '—' : '${ms.toStringAsFixed(ms < 10 ? 1 : 0)} ms',
            color: color, bold: ms != null),
      ],
    );
  }
}
