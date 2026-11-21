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
            for (final h in _hops) _HopTile(hop: h),
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

class _HopTile extends StatelessWidget {
  const _HopTile({required this.hop});
  final Hop hop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final h = hop;
    final ms = h.ms;
    final color = ms == null
        ? cs.onSurfaceVariant
        : ms < 30
            ? Colors.green.shade600
            : ms < 100
                ? Colors.orange.shade700
                : cs.error;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor:
            h.reached ? cs.primary : cs.secondaryContainer,
        foregroundColor:
            h.reached ? cs.onPrimary : cs.onSecondaryContainer,
        child: Text('${h.ttl}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      title: Text(h.ip == null ? '* * *' : (h.host ?? h.ip!),
          overflow: TextOverflow.ellipsis),
      subtitle: h.ip == null
          ? Text(tr('Fără răspuns', 'No reply'))
          : h.host != null
              ? Text(h.ip!)
              : null,
      trailing: Text(ms == null ? '' : '${ms.toStringAsFixed(ms < 10 ? 1 : 0)} ms',
          style: tt.titleSmall?.copyWith(color: color)),
      onLongPress: h.ip == null ? null : () => copyText(context, h.ip!),
    );
  }
}
